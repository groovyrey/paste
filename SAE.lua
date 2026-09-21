--[[
	SAE.lua (Features, for use with FeatureLoader)

	Registers two independent FeatureLoader features:

	"SAE" — a small ModernUI window with a read-only, copyable textbox and a
	"Save Position" button. Clicking the button writes the LocalPlayer's
	character root part position into the textbox as a ready-to-paste
	Vector3.new(x, y, z) string.

	"SAE:PromptWatcher" — watches ProximityPromptService.PromptTriggered in
	real time and pushes a toast (via NotificationSystem) every time the
	LocalPlayer triggers a ProximityPrompt anywhere in the game.

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
local ProximityPromptService = game:GetService("ProximityPromptService")

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

-- Falls back to sensible labels when a prompt author left ObjectText/ActionText blank.
local function describePrompt(prompt)
	local objectText = (prompt.ObjectText ~= "" and prompt.ObjectText) or "Object"
	local actionText = (prompt.ActionText ~= "" and prompt.ActionText) or "Interact"
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

	-- Real-time prompt trigger watcher: pops a toast the moment the
	-- LocalPlayer triggers any ProximityPrompt in the game.
	Loader.Register("SAE:PromptWatcher", function()
		local notify = NotificationSystem.new()

		local connection = ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
			-- PromptTriggered can report other players' triggers depending on
			-- replication setup; only toast for prompts *this* client fired.
			if triggeringPlayer ~= Players.LocalPlayer then
				return
			end

			local objectText, actionText = describePrompt(prompt)
			notify:Info(objectText, actionText .. " triggered", 3)
		end)

		return function()
			connection:Disconnect()
			notify:Destroy()
		end
	end)
end
