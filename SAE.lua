--[[
	SAE.lua (Features, for use with FeatureLoader)

	Registers two independent FeatureLoader features:

	"SAE" — a small ModernUI window with a read-only, copyable textbox and a
	"Save Position" button. Clicking the button writes the LocalPlayer's
	character root part position into the textbox as a ready-to-paste
	Vector3.new(x, y, z) string.

	"InstantTP" — detects a successful egg steal by watching the
	DropHeldEgg instance that Roblox parents into the same folder as
	ProximityPrompts (PlayerGui). The egg-drop only happens once a steal fully
	completes, and DropHeldEgg appears earlier than the RunBackEffects GUI —
	its arrival is the trigger. On trigger we instantly teleport to the egg
	spot and back.

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

		Loader.Enable("InstantTP")  -- start toasting on prompt triggers
		Loader.Disable("InstantTP") -- stop watching

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

-- DropHeldEgg-based trigger watcher: lives in the same folder as
		-- ProximityPrompts (PlayerGui). Roblox parents a DropHeldEgg instance in
		-- the moment a steal fully completes, earlier than RunBackEffects, so its
		-- appearance is the earliest reliable cue we have.
		Loader.Register("InstantTP", function()
			local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
			local notify = NotificationSystem.new()
			notify:Info("InstantTP", "Started", 2)

			-- Root folder Roblox keeps ProximityPrompts under. DropHeldEgg lives
			-- beside it, so its real parent is whatever parents ProximityPrompts.
			local proximityRoot = playerGui:FindFirstChild("ProximityPrompts")
			local rootParent = proximityRoot and proximityRoot.Parent or playerGui

			local TELEPORT_TO = Vector3.new(542.18, 70.67, -349.22)
			local TELEPORT_BACK_AFTER = 0.5 -- seconds at the egg spot before returning

			local connections = {} -- every RBXScriptConnection made here, disconnected on stop
			local fired = {} -- [inst] = true; fresh instances are each a new steal

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

			local function fire(inst)
				if fired[inst] then return end
				fired[inst] = true
				notify:Success("Egg", "Steal triggered", 3)
				spawn(instantTeleport)
			end

			-- DropHeldEgg is a ScreenGui parented into the folder the instant the
			-- egg drop starts — that parented-in IS our trigger (it's earlier than
			-- any Enabled flip). Each steal parents a fresh instance, so firing is
			-- per-instance: a newly arrived GUI always means a new steal. If one
			-- exists already disabled, fall back to an Enabled watch.
			local function watchDropHeldEgg(inst)
				if type(inst.Enabled) == "boolean" and not inst.Enabled then
					table.insert(connections, inst.Changed:Connect(function(prop)
						if prop ~= "Enabled" then return end
						if inst.Enabled then
							fire(inst) -- became active: fire once per enabled-on
						else
							fired[inst] = nil -- flipped off: allows re-fire next time
						end
					end))
				else
					fire(inst) -- just appeared (or is enabled already)
				end

				table.insert(connections, inst.AncestryChanged:Connect(function(_, parent)
					if parent == nil then
						fired[inst] = nil -- gone; forget so a later re-parent re-fires
					end
				end))
			end

			-- DropHeldEgg is (re)parented lazily on every steal, so it may not
			-- exist yet — watch for arrivals.
			local function attach(parent)
				local existing = parent:FindFirstChild("DropHeldEgg")
				if existing then
					watchDropHeldEgg(existing)
				end
				table.insert(connections, parent.ChildAdded:Connect(function(child)
					if child.Name == "DropHeldEgg" then
						watchDropHeldEgg(child)
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
