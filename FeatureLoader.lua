--[[
	FeatureLoader (ModuleScript)
	Put in ReplicatedStorage and require it from a LocalScript
	(put that LocalScript in StarterPlayerScripts so it survives respawns).

	Usage:
		local Loader = require(game.ReplicatedStorage.FeatureLoader)

		Loader("InfiniteJump")            -- callable: toggles the feature
		Loader.Enable("WalkSpeed", 40)    -- features can take arguments
		Loader.Disable("InfiniteJump")    -- the ONLY thing that turns a feature off
		Loader.IsEnabled("InfiniteJump")
		Loader.Register("Name", function(...) ... return cleanupFn end)

	Enabled features stay on through respawns, humanoid replacement, and other
	scripts trying to change the values, until you call Disable/Toggle/DisableAll.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Loader = {}

local features = {} -- name -> function(...) that returns a cleanup function
local active = {}   -- name -> cleanup function

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function Loader.Register(name, startFn)
	assert(type(name) == "string", "Feature name must be a string")
	assert(type(startFn) == "function", "Feature must be a function")
	features[name] = startFn
end

function Loader.Enable(name, ...)
	local startFn = features[name]
	if not startFn then
		warn(("[FeatureLoader] Unknown feature '%s'"):format(tostring(name)))
		return false
	end
	if active[name] then
		return true -- already on
	end

	local ok, cleanup = pcall(startFn, ...)
	if not ok then
		warn(("[FeatureLoader] '%s' failed to start: %s"):format(name, tostring(cleanup)))
		return false
	end

	active[name] = type(cleanup) == "function" and cleanup or function() end
	return true
end

function Loader.Disable(name)
	local cleanup = active[name]
	if not cleanup then
		return false
	end
	active[name] = nil
	pcall(cleanup)
	return true
end

function Loader.IsEnabled(name)
	return active[name] ~= nil
end

function Loader.Toggle(name, ...)
	if Loader.IsEnabled(name) then
		Loader.Disable(name)
		return false
	end
	return Loader.Enable(name, ...)
end

function Loader.DisableAll()
	for name in pairs(active) do
		Loader.Disable(name)
	end
end

function Loader.List()
	local names = {}
	for name in pairs(features) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getHumanoid()
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

----------------------------------------------------------------------
-- Built-in features
----------------------------------------------------------------------

Loader.Register("InfiniteJump", function()
	local connections = {}

	-- Jump requests are read fresh every time, so this survives respawns.
	table.insert(connections, UserInputService.JumpRequest:Connect(function()
		local humanoid = getHumanoid()
		if humanoid and humanoid.Health > 0 then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end))

	-- Keep the Jumping state enabled even if another script disables it.
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local humanoid = getHumanoid()
		if humanoid and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end))

	return function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end
end)

-- Loader.Enable("WalkSpeed", 40)
Loader.Register("WalkSpeed", function(speed)
	speed = speed or 32

	local original = 16
	local first = getHumanoid()
	if first then
		original = first.WalkSpeed
	end

	local connections = {}
	local watched = nil

	local function apply(humanoid)
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
	end

	-- Instantly undo any change made by other scripts on the current humanoid.
	local function watch(humanoid)
		if watched == humanoid then
			return
		end
		if connections.changed then
			connections.changed:Disconnect()
		end
		watched = humanoid
		apply(humanoid)
		connections.changed = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			apply(humanoid)
		end)
	end

	-- Every frame: catches respawns and replaced humanoids.
	connections.heartbeat = RunService.Heartbeat:Connect(function()
		local humanoid = getHumanoid()
		if humanoid then
			watch(humanoid)
			apply(humanoid)
		end
	end)

	return function()
		for _, c in pairs(connections) do
			c:Disconnect()
		end
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.WalkSpeed = original
		end
	end
end)

----------------------------------------------------------------------
-- Make the module itself callable: Loader("InfiniteJump")
----------------------------------------------------------------------

return setmetatable(Loader, {
	__call = function(_, name, ...)
		return Loader.Toggle(name, ...)
	end,
})
