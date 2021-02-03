--[[
Created by: V3N0M_Z (V3N0M#8545)
Version: 0.2
 
API:
 
    Constructor:
 
        Path SimplePath.new(Model Rig, [Optional] table PathParams)
            -- Creates new Path with optional PathParams
            -- Use one Path per rig
 
 
    Functions:
 
        void Path:Run(Vector3 FinalPosition)
            -- Starts pathfinding and moves the Rig to FinalPosition
 
        void Path:Stop([Optional] string Status)
            -- Stops moving the Rig and fire Path.Completed sending Status
 
        number Path:Distance(Vector3 TargetPosition or BasePart TargetPart)
            -- Returns the vector magnitude between the Rig and Target
 
        void Path:Destroy()
            -- Destroy Path
 
    Events:
 
        RBXScriptSignal Path.Completed(string Status, Model Rig, Vector3 FinalPosition)
            -- Fires when pathfinding has ended
            -- Check status to see why pathfinding ended
 
        RBXScriptSignal Path.WaypointReached(bool Reached, int CurrentWaypoint, table Waypoints)
            -- Fires when a waypoint has been reached
 
        RBXScriptSignal Path.Blocked(int BlockedWaypoint, int CurrentWaypoint, table Waypoints)
            -- Fires when a waypoint has been blocked
 
 
    Properties:
 
        Model Path.Rig [readonly]
            -- Returns active Rig
 
        Humanoid Path.Humanoid [readonly]
            -- Returns Rig.Humanoid
 
        BasePart Path.HumanoidRootPart [readonly]
            -- Returns Rig.PrimaryPart
 
        Instance Path.Path [readonly]
            -- Returns Path object
 
        Vector3 Path.InitialPosition [writeonly]
            -- Change InitialPosition of the path (returns nil) // Default: Rig.PrimaryPart.Position
 
        int Path.Timeout
            -- Change Rig.HumanoidMoveTo timeout // Default: 1
]]

local PathfindingService = game:GetService("PathfindingService")
local ObjectsHandler = script:WaitForChild("ObjectHandler")
local Objects = require(ObjectsHandler).Objects

local Path = {}
Path.__index = Path

local function move(self)
	if self.Waypoints[self.currentWaypoint] and self.Running then
		self.Humanoid:MoveTo(self.Waypoints[self.currentWaypoint].Position)
		self.elapsed = tick()
	else
		self:Stop("Error: Invalid Waypoints")
	end
end

local function onWaypointReached(self, reached)
	if reached and self.currentWaypoint < #self.Waypoints and self.Running then
		self.currentWaypoint += 1
		move(self)
	else
		self:Stop("Success: Path Reached")
	end
end

local function timeoutLoop(self)
	while self.running do
		if self.elapsed and (tick() - self.elapsed) >= self.Timeout then
			self:Stop("Error: MoveTo Timeout")
		end
	wait(0.1) end
end

local function validate(self)
	local exists = nil
	if #Objects > 0 then
		for i = 1, #Objects do
			if Objects[i][1] == nil or Objects[i][2] == nil then
				table.remove(Objects, i)
			end
			if Objects[i][1] == self.Rig then
				exists = Objects[i][2]
			end
		end
	end
	if not exists then
		table.insert(Objects, #Objects + 1, {self.Rig, self})
		exists = self
	else
		self = nil
	end
	return exists
end

local function removeObject(self)
	for i = 1, #Objects do
		if Objects[i][1] == self.Rig then
			table.remove(Objects, i)
			break
		end
	end
end

function Path.new(Rig, PathParams)
	
	local self = setmetatable({}, Path)
	
	self.Rig = Rig
	self.HumanoidRootPart = Rig:WaitForChild("HumanoidRootPart")
	self.Humanoid = Rig:WaitForChild("Humanoid")
	self.Timeout = 1
	
	self.__Blocked = Instance.new("BindableEvent")
	self.__WaypointReached = Instance.new("BindableEvent")
	self.__Completed = Instance.new("BindableEvent")
	self.Blocked = self.__Blocked.Event
	self.WaypointReached = self.__WaypointReached.Event
	self.Completed = self.__Completed.Event
	
	if PathParams then
		self.Path = PathfindingService:CreatePath(PathParams)
	else
		self.Path = PathfindingService:CreatePath()
	end
	
	if game:FindFirstChild("NetworkServer") ~= nil then
		self.HumanoidRootPart:SetNetworkOwner(nil)
	end
	
	return validate(self, Rig)
end

function Path:Stop(Status)
	if self.connection and self.connection.Connected then
		self.connection:Disconnect()
	end
	if self.blockedConnection and self.blockedConnection.Connected then
		self.blockedConnection:Disconnect()
	end
	self.blockedConnection = nil
	self.connection = nil
	self.Running = nil
	self.__Completed:Fire(Status, self.Rig, self.finalPosition)
	return
end

function Path:Run(finalPosition)
	if self.Running then self:Stop("Stopped Previous Path") end
	self.Running = true
	
	self.finalPosition = finalPosition
	self.Path:ComputeAsync(self.InitialPosition or self.HumanoidRootPart.Position, finalPosition)
	if self.Path.Status == Enum.PathStatus.NoPath then self:Stop("Error: No path found") end
	self.Waypoints = self.Path:GetWaypoints()
	self.currentWaypoint = 1
	
	self.connection = self.Humanoid.MoveToFinished:Connect(function(Reached)
		self.__WaypointReached:Fire(Reached, self.currentWaypoint, self.Waypoints)
		onWaypointReached(self, Reached)
	end)
	coroutine.wrap(timeoutLoop)(self)
	
	self.blockedConnection = self.Path.Blocked:Connect(function(BlockedWaypoint)
		self.__Blocked:Fire(BlockedWaypoint, self.currentWaypoint, self.Waypoints)
	end)
	
	move(self)
	
end

function Path:Distance(Target)
	local position = Target
	if typeof(Target) == "Instance" then
		position = Target.Position
	end
	return (position - self.HumanoidRootPart.Position).Magnitude
end

function Path:Destroy()
	removeObject(self)
	self = nil
end

return Path