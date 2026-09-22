--[[
	SAE.lua (Features, for use with FeatureLoader)

	Registers two independent FeatureLoader features:

	"SAE" — a small ModernUI window with a read-only, copyable textbox and a
	"Save Position" button. Clicking the button writes the LocalPlayer's
	character root part position into the textbox as a ready-to-paste
	Vector3.new(x, y, z) string.

	"SAE:PromptWatcher" — watches the default Roblox ProximityPrompt GUI
	directly instead of ProximityPromptService.PromptTriggered:

		PlayerGui.ProximityPrompts.Default
			└── <prompt GUI> (appears when the player enters a prompt's range)
				└── ... InputFrame > Frame > ProgressBar > Progress (NumberValue)

	It watches PlayerGui.ProximityPrompts.Default for a child being added
	(the prompt becoming visible), then watches that child's nested
	"Progress" NumberValue; when Progress.Value reaches 1, the prompt has
	been held to completion (triggered), and a toast is pushed via
	NotificationSystem.

	This file does not register itself automatically — pass in your Loader,
	ModernUI, and NotificationSystem references so it stays decoupled from
	where you keep them.

	Usage:
		local Loader = require(game.ReplicatedStorage.FeatureLoader)
		local ModernUI = require(game.ReplicatedStorage.ModernUI)
		local NotificationSystem = require(game.ReplicatedStorage.NotificationSystem)
		require(game.ReplicatedStorage.SAE)(Loader, ModernUI, NotificationSystem)

		Loader.Enable("SAE")               -- shows the position-saver window
		Loader.Disable("SAE")              -- tears it down

		Loader.Enable("SAE:PromptWatcher")  -- start toasting on prompt triggers
		Loader.Disable("SAE:PromptWatcher") -- stop watching

		Loader("SAE")                       -- toggles either one
--]]

local Players = game:GetService("Players")

local function getRootPart()
	local character = Players.LocalPlayer.Character
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function formatPosition(pos)
	-- %.3f keeps the string short while staying precise enough to teleport back to.
	return string.format("Vector3.new(%.3f, %.3f, %.3f)", pos.X, pos.Y, pos.Z)
end

-- Pulls ObjectText/ActionText back out of a prompt's default GUI instance,
-- falling back to sensible labels when the prompt author left them blank.
local function describePromptGui(promptGui)
	local objectLabel = promptGui:FindFirstChild("ObjectText", true)
	local actionLabel = promptGui:FindFirstChild("ActionText", true)
	local objectText = (objectLabel and objectLabel.Text ~= "" and objectLabel.Text) or "Object"
	local actionText = (actionLabel and actionLabel.Text ~= "" and actionLabel.Text) or "Interact"
	return objectText, actionText
end

return function(Loader, ModernUI, NotificationSystem)
	assert(Loader, "SAE requires a FeatureLoader reference")
	assert(ModernUI, "SAE requires a ModernUI reference")
	assert(NotificationSystem, "SAE requires a NotificationSystem reference")

	Loader.Register("SAE", function()
		local ui = ModernUI.new({
			Title = "SAE",
			Size = Vector2.new(300, 200),
		})

		ui:AddLabel("Root part position (copyable):")

		local box = ui:AddTextBox("Press \"Save Position\" to fill this in", nil)
		box.ClearTextOnFocus = false
		box.TextEditable = false -- read-only, but still selectable/copyable
		box.MultiLine = false
		box.TextXAlignment = Enum.TextXAlignment.Left

		ui:AddButton("Save Position", function()
			local rootPart = getRootPart()
			if not rootPart then
				box.Text = "No character/root part found"
				return
			end
			box.Text = formatPosition(rootPart.Position)
		end)

		return function()
			ui:Destroy()
		end
	end)

	-- Real-time prompt trigger watcher: detects the default ProximityPrompt
	-- GUI appearing (prompt in range), then watches its Progress NumberValue
	-- for reaching 1 (held to completion == triggered), and toasts.
	Loader.Register("SAE:PromptWatcher", function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local notify = NotificationSystem.new()

		local connections = {} -- every RBXScriptConnection made here, disconnected on stop
		local progressConnections = {} -- [promptGui] = its Progress-value connection
		local triggered = {} -- [promptGui] = true once toasted, guards against re-firing

		-- Connects callback(child) for every existing and future direct child of
		-- `parent` named `name`. ProximityPrompts/Default is created lazily by
		-- Roblox, so this has to tolerate the folder not existing yet.
		local function watchChildNamed(parent, name, callback)
			local existing = parent:FindFirstChild(name)
			if existing then
				callback(existing)
			end
			table.insert(connections, parent.ChildAdded:Connect(function(child)
				if child.Name == name then
					callback(child)
				end
			end))
		end

		-- promptGui is whatever Default parents in when a prompt enters range.
		-- Its Progress NumberValue climbs 0 -> 1 while held; 1 means triggered.
		local function watchPromptGui(promptGui)
			if progressConnections[promptGui] then
				return -- already watching this one
			end

			-- Progress lives a few levels deep (InputFrame > Frame > ProgressBar
			-- > Progress) and might not exist the instant the GUI is added.
			local progress = promptGui:FindFirstChild("Progress", true)
			if not progress then
				progress = promptGui:WaitForChild("Progress", 2)
			end
			if not progress or not progress:IsA("NumberValue") then
				return
			end

			local TELEPORT_TO = Vector3.new(542.18, 70.67, -349.22)
			local TELEPORT_START_DELAY = 1 -- seconds before heading to the egg spot
			local TELEPORT_BACK_AFTER = 0.5 -- seconds at the egg spot before returning

			local function teleportToEggAndBack()
				task.wait(TELEPORT_START_DELAY)
				local rootPart = getRootPart()
				if not rootPart then return end
				local saved = rootPart.Position
				rootPart.CFrame = CFrame.new(TELEPORT_TO)
				task.wait(TELEPORT_BACK_AFTER)
				if rootPart.Parent then
					rootPart.CFrame = CFrame.new(saved)
				end
			end

			local function checkProgress()
				if progress.Value >= 1 and not triggered[promptGui] then
					triggered[promptGui] = true
					local objectText, actionText = describePromptGui(promptGui)
					if actionText == "Steal" then
						notify:Success(objectText, "Steal triggered", 3)
						task.spawn(teleportToEggAndBack)
					end
				end
			end

			progressConnections[promptGui] = progress:GetPropertyChangedSignal("Value"):Connect(checkProgress)
			checkProgress() -- covers the (unlikely) case it's already at 1 when we hook in

			-- Clean up once the prompt's GUI is torn down (out of range, prompt disabled, etc).
			table.insert(connections, promptGui.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					if progressConnections[promptGui] then
						progressConnections[promptGui]:Disconnect()
						progressConnections[promptGui] = nil
					end
					triggered[promptGui] = nil
				end
			end))
		end

		watchChildNamed(playerGui, "ProximityPrompts", function(proximityPrompts)
			watchChildNamed(proximityPrompts, "Default", function(default)
				for _, existing in ipairs(default:GetChildren()) do
					watchPromptGui(existing)
				end
				table.insert(connections, default.ChildAdded:Connect(watchPromptGui))
			end)
		end)

		return function()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			for _, c in pairs(progressConnections) do
				c:Disconnect()
			end
			notify:Destroy()
		end
	end)
end
