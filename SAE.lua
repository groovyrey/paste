--[[
	SAE.lua (Features, for use with FeatureLoader)

	Registers two independent FeatureLoader features:

	"SAE" — a small ModernUI window with a read-only, copyable textbox and a
	"Save Position" button. Clicking the button writes the LocalPlayer's
	character root part position into the textbox as a ready-to-paste
	Vector3.new(x, y, z) string.

	"SAE:PromptWatcher" — detects a successful egg steal by watching the
	RunBackEffects ScreenGui that Roblox keeps in the same parent as
	ProximityPrompts (PlayerGui). It ships with Enabled=false; Roblox flips it
	to Enabled=true the instant the steal animation fires, and that flip is the
	trigger. On trigger we instantly teleport to the egg spot and back.

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

	-- RunBackEffects-based trigger watcher: sits in the same parent as the
	-- ProximityPrompts folder. Roblox leaves it Enabled=false and flips it to
	-- Enabled=true the moment a steal fully completes — that flip is our cue.
	Loader.Register("SAE:PromptWatcher", function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local notify = NotificationSystem.new()
		notify:Info("SAE", "Prompt watcher started", 2)

		-- Root folder Roblox keeps ProximityPrompts under. RunBackEffects lives
		-- beside it, so its real parent is whatever parents ProximityPrompts.
		local proximityRoot = playerGui:FindFirstChild("ProximityPrompts")
		local rootParent = proximityRoot and proximityRoot.Parent or playerGui

		local TELEPORT_TO = Vector3.new(542.18, 70.67, -349.22)
		local TELEPORT_BACK_AFTER = 0.5 -- seconds at the egg spot before returning

		local connections = {} -- every RBXScriptConnection made here, disconnected on stop
		local triggered = {} -- [gui] = true once fired, re-armed when it flips back off

		local function instantTeleport()
			local rootPart = getRootPart()
			if not rootPart then return end
			local saved = rootPart.Position
			rootPart.CFrame = CFrame.new(TELEPORT_TO)
			wait(TELEPORT_BACK_AFTER)
			if rootPart.Parent then
				rootPart.CFrame = CFrame.new(saved)
			end
		end

		-- gui is the RunBackEffects ScreenGui. When Enabled goes true the steal
		-- finished: toast + instantly teleport to the egg spot and back.
		local function watchRunBackEffects(gui)
			if triggered[gui] then
				return -- already watching this one
			end
			triggered[gui] = false

			table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if gui.Enabled then
					triggered[gui] = true
					notify:Success("Egg", "Steal triggered", 3)
					spawn(instantTeleport)
				else
					triggered[gui] = false -- re-arm for the next steal
				end
			end))

			-- If the GUI is created already-enabled (odd edge case), fire once.
			if gui.Enabled then
				triggered[gui] = true
				notify:Success("Egg", "Steal triggered", 3)
				spawn(instantTeleport)
			end

			-- Clean up once the GUI is torn down.
			table.insert(connections, gui.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					triggered[gui] = nil
				end
			end))
		end

		-- RunBackEffects appears lazily, so tolerate it not existing yet.
		local function attach(parent)
			local existing = parent:FindFirstChild("RunBackEffects")
			if existing then
				watchRunBackEffects(existing)
			end
			table.insert(connections, parent.ChildAdded:Connect(function(child)
				if child.Name == "RunBackEffects" then
					watchRunBackEffects(child)
				end
			end))
		end

		attach(rootParent)

		return function()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			notify:Destroy()
		end
	end)
end
