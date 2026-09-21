--[[
	FeatureLoader (ModuleScript)
	Put in ReplicatedStorage and require it from a LocalScript.

	Usage:
		local Loader = require(game.ReplicatedStorage.FeatureLoader)

		Loader("InfiniteJump")            -- callable: toggles the feature
		Loader.Enable("InfiniteJump")     -- turn on
		Loader.Disable("InfiniteJump")    -- turn off
		Loader.Toggle("InfiniteJump")     -- flip state
		Loader.IsEnabled("InfiniteJump")  -- true / false
		Loader.Register("Name", function(...) ... return cleanupFn end)
]]

local Players = game:GetService("Players")
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
-- Built-in features
----------------------------------------------------------------------

Loader.Register("InfiniteJump", function()
	local player = Players.LocalPlayer

	local connection = UserInputService.JumpRequest:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	return function()
		connection:Disconnect()
	end
end)

-- Example of a feature that takes an argument: Loader.Enable("WalkSpeed", 32)
Loader.Register("WalkSpeed", function(speed)
	local player = Players.LocalPlayer
	speed = speed or 32

	local function apply(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.WalkSpeed = speed
		end
	end

	if player.Character then
		apply(player.Character)
	end
	local connection = player.CharacterAdded:Connect(apply)

	return function()
		connection:Disconnect()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
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
