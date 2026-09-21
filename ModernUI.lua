--[[
	ModernUI.lua
	Reusable modern dark-themed UI module. No standalone behaviour — build a
	window with ModernUI.new(...) and call the returned UI methods.

	Usage (executor):
		local ModernUI = loadstring(readfile("ModernUI.lua"))()   -- or require a ModuleScript
		local ui = ModernUI.new({ Title = "Orbyte", Size = Vector2.new(340, 420) })
		ui:AddLabel("hello")
		ui:AddButton("go", function() end)
		ui:AddToggle("on?", false, function(state) end)
		ui:AddSlider("Vol", 0, 100, 50, function(v) end)
		ui:AddTextBox("...", function(text, enter) end)

	Options for new():
		Title  (string)            default "Modern UI"
		Size   (Vector2)           default 340x420
		Theme  (table | nil)       override any DEFAULT_THEME field
		Gui    (ScreenGui | nil)   parent a window into an existing GUI
		Parent (instance | nil)    default LocalPlayer.PlayerGui
		Name   (string)            ScreenGui name, default "ModernUI"
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local ModernUI = {}
ModernUI.__index = ModernUI

--// THEME ---------------------------------------------------------------
local DEFAULT_THEME = {
	Background   = Color3.fromRGB(24, 24, 28),
	Surface      = Color3.fromRGB(32, 32, 38),
	SurfaceLight = Color3.fromRGB(42, 42, 50),
	Accent       = Color3.fromRGB(99, 102, 241),   -- indigo
	AccentHover  = Color3.fromRGB(129, 132, 255),
	Text         = Color3.fromRGB(235, 235, 240),
	SubText      = Color3.fromRGB(160, 160, 170),
	Border       = Color3.fromRGB(50, 50, 58),
	Font         = Enum.Font.GothamMedium,
	FontBold     = Enum.Font.GothamBold,
}
ModernUI.Theme = DEFAULT_THEME

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function mergeTheme(base, overrides)
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	for k, v in pairs(overrides or {}) do t[k] = v end
	return t
end

--// HELPERS --------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	for prop, value in pairs(props or {}) do
		inst[prop] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function stroke(color, thickness)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(amount)
	amount = amount or 12
	return create("UIPadding", {
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
	})
end

local function tween(inst, info, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

-- onClick (optional) fires on release only if the pointer barely moved,
-- so the same element can act as both a drag handle and a click target
-- (used by the collapse button, which becomes the whole draggable circle).
local function makeDraggable(handle, target, onClick)
	local dragging, dragInput, dragStart, startPos, moved

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = 0
			dragStart = input.Position
			startPos = target.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if onClick and moved and moved < 6 then
						onClick()
					end
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			moved = math.max(moved or 0, delta.Magnitude)
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

--// CONSTRUCTOR ----------------------------------------------------------

function ModernUI.new(options)
	options = options or {}
	local self = setmetatable({}, ModernUI)

	local theme = mergeTheme(DEFAULT_THEME, options.Theme)
	self.Theme = theme
	self.TweenFast = options.TweenFast or TWEEN_FAST
	self.TweenMed = options.TweenMed or TWEEN_MED

	local parent = options.Parent
	if parent == nil then
		local lp = Players.LocalPlayer
		if not lp then
			error("ModernUI.new: no Parent given and no LocalPlayer available", 2)
		end
		parent = lp:WaitForChild("PlayerGui")
	end

	local gui = options.Gui
	if not gui then
		gui = create("ScreenGui", {
			Name = options.Name or "ModernUI",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = parent,
		})
	end
	self.Gui = gui

	local size = options.Size or Vector2.new(340, 420)
	local expanded = UDim2.fromOffset(size.X, size.Y)
	local collapsed = options.CollapsedSize or UDim2.fromOffset(56, 56)

	--// BUILD THE WINDOW --------------------------------------------------
	local windowCorner = corner(14)
	local Window = create("Frame", {
		Name = "Window",
		Size = expanded,
		Position = UDim2.new(0.5, -size.X / 2, 0.5, -size.Y / 2),
		BackgroundColor3 = theme.Background,
		Parent = gui,
	}, { windowCorner, stroke(theme.Border, 1) })

	-- NOTE: this is a TextButton (not a Frame) so that Roblox marks drag input
	-- as "game processed" — otherwise the default camera script also reads the
	-- same mouse-drag input and rotates the camera while you're dragging.
	local titleBarCorner = corner(14)
	local TitleBar = create("TextButton", {
		Name = "TitleBar",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = theme.Surface,
		Parent = Window,
	}, { titleBarCorner })

	local titleBarMask = create("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Parent = TitleBar,
	})

	local titleText = create("TextLabel", {
		Text = options.Title or "Modern UI",
		Font = theme.FontBold,
		TextSize = 16,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = TitleBar,
	})

	-- Single open/close toggle. When open it's a small "–" button in the title
	-- bar; when closed it resizes to fill the entire (now circular) window, so
	-- the whole circle becomes the click target to reopen.
	local collapseBtn = create("TextButton", {
		Name = "CollapseButton",
		Text = "–",
		Font = theme.FontBold,
		TextSize = 16,
		TextColor3 = theme.SubText,
		BackgroundColor3 = theme.SurfaceLight,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -38, 0.5, -14),
		AutoButtonColor = false,
		ZIndex = 2,
		Parent = TitleBar,
	}, { corner(14) })

	collapseBtn.MouseEnter:Connect(function()
		tween(collapseBtn, self.TweenFast, { BackgroundColor3 = theme.AccentHover })
	end)
	collapseBtn.MouseLeave:Connect(function()
		tween(collapseBtn, self.TweenFast, { BackgroundColor3 = theme.SurfaceLight })
	end)

	local Content = create("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = Window,
	}, {
		padding(14),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})

	makeDraggable(TitleBar, Window)

	self.Window = Window
	self.TitleBar = TitleBar
	self.TitleBarMask = titleBarMask
	self.TitleText = titleText
	self.CollapseButton = collapseBtn
	self.Content = Content
	self.ExpandedSize = expanded
	self.CollapsedSize = collapsed
	self.windowCorner = windowCorner
	self.titleBarCorner = titleBarCorner
	self.isCollapsed = false
	self.order = 0

	-- entrance animation
	Window.Size = UDim2.fromOffset(0, 0)
	Window.Position = UDim2.new(0.5, 0, 0.5, 0)
	Window.Visible = true
	tween(Window, self.TweenMed, {
		Size = expanded,
		Position = UDim2.new(0.5, -size.X / 2, 0.5, -size.Y / 2),
	})

	-- collapseBtn covers the whole window once collapsed, so it needs to be
	-- draggable too (not just clickable) — makeDraggable's onClick param tells
	-- a genuine click apart from a drag.
	makeDraggable(collapseBtn, Window, function()
		self:SetCollapsed(not self.isCollapsed)
	end)

	return self
end

--// WINDOW CONTROLS ------------------------------------------------------

function ModernUI:SetTitle(text)
	self.TitleText.Text = text
end

function ModernUI:Destroy()
	self.Gui:Destroy()
end

function ModernUI:SetCollapsed(state)
	if self.isCollapsed == state then return end
	self.isCollapsed = state

	if state then
		-- fade out everything except the collapse button itself
		self.TitleText.Visible = false
		self.TitleBarMask.Visible = false
		self.Content.Visible = false

		tween(self.windowCorner, self.TweenMed, { CornerRadius = UDim.new(0, 28) })
		tween(self.titleBarCorner, self.TweenMed, { CornerRadius = UDim.new(0, 28) })
		tween(self.Window, self.TweenMed, { Size = self.CollapsedSize })
		tween(self.TitleBar, self.TweenMed, { Size = UDim2.new(1, 0, 1, 0) })
		tween(self.CollapseButton, self.TweenMed, {
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromOffset(0, 0),
		})
		self.CollapseButton.Text = ""
		local cc = self.CollapseButton:FindFirstChildOfClass("UICorner")
		if cc then
			tween(cc, self.TweenMed, { CornerRadius = UDim.new(0, 28) })
		end
	else
		tween(self.windowCorner, self.TweenMed, { CornerRadius = UDim.new(0, 14) })
		tween(self.titleBarCorner, self.TweenMed, { CornerRadius = UDim.new(0, 14) })
		tween(self.Window, self.TweenMed, { Size = self.ExpandedSize })
		tween(self.TitleBar, self.TweenMed, { Size = UDim2.new(1, 0, 0, 44) })
		tween(self.CollapseButton, self.TweenMed, {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -38, 0.5, -14),
		})
		local cc = self.CollapseButton:FindFirstChildOfClass("UICorner")
		if cc then
			tween(cc, self.TweenMed, { CornerRadius = UDim.new(0, 14) })
		end

		task.delay(self.TweenMed.Time, function()
			if self.isCollapsed then return end -- toggled again before this fired
			self.CollapseButton.Text = "–"
			self.TitleText.Visible = true
			self.TitleBarMask.Visible = true
			self.Content.Visible = true
		end)
	end
end

function ModernUI:ToggleCollapsed()
	self:SetCollapsed(not self.isCollapsed)
end

--// COMPONENT FUNCTIONS ---------------------------------------------------

local function nextOrder(self)
	self.order += 1
	return self.order
end

function ModernUI:AddLabel(text)
	return create("TextLabel", {
		Text = text,
		Font = self.Theme.Font,
		TextSize = 14,
		TextColor3 = self.Theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	})
end

function ModernUI:AddButton(text, callback)
	local theme = self.Theme
	local btn = create("TextButton", {
		Text = text,
		Font = theme.FontBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = theme.Accent,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, { corner(10) })

	btn.MouseEnter:Connect(function()
		tween(btn, self.TweenFast, { BackgroundColor3 = theme.AccentHover })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, self.TweenFast, { BackgroundColor3 = theme.Accent })
	end)
	btn.MouseButton1Down:Connect(function()
		tween(btn, self.TweenFast, { Size = UDim2.new(1, -6, 0, 36) })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(btn, self.TweenFast, { Size = UDim2.new(1, 0, 0, 38) })
	end)
	btn.MouseButton1Click:Connect(function()
		if callback then callback() end
	end)

	return btn
end

function ModernUI:AddToggle(text, default, callback)
	local theme = self.Theme
	local state = default or false

	local row = create("Frame", {
		BackgroundColor3 = theme.Surface,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, { corner(10), padding(10) })

	create("TextLabel", {
		Text = text,
		Font = theme.Font,
		TextSize = 14,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -50, 1, 0),
		Parent = row,
	})

	local track = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = state and theme.Accent or theme.SurfaceLight,
		Size = UDim2.fromOffset(40, 22),
		Position = UDim2.new(1, -40, 0.5, -11),
		Parent = row,
	}, { corner(11) })

	local knob = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(18, 18),
		Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		Parent = track,
	}, { corner(9) })

	track.MouseButton1Click:Connect(function()
		state = not state
		tween(track, self.TweenFast, { BackgroundColor3 = state and theme.Accent or theme.SurfaceLight })
		tween(knob, self.TweenFast, {
			Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		})
		if callback then callback(state) end
	end)

	return track
end

function ModernUI:AddSlider(text, min, max, default, callback)
	local theme = self.Theme
	min, max = min or 0, max or 100
	default = math.clamp(default or min, min, max)

	local row = create("Frame", {
		BackgroundColor3 = theme.Surface,
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, { corner(10), padding(10) })

	local label = create("TextLabel", {
		Text = text .. ": " .. tostring(default),
		Font = theme.Font,
		TextSize = 14,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = row,
	})

	local bar = create("Frame", {
		BackgroundColor3 = theme.SurfaceLight,
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -8),
		Parent = row,
	}, { corner(3) })

	local fillPct = (default - min) / (max - min)
	local fill = create("Frame", {
		BackgroundColor3 = theme.Accent,
		Size = UDim2.new(fillPct, 0, 1, 0),
		Parent = bar,
	}, { corner(3) })

	local knob = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(fillPct, -7, 0.5, -7),
		ZIndex = 2,
		Parent = bar,
	}, { corner(7) })

	local dragging = false

	local function updateFromInput(inputPos)
		local relX = math.clamp((inputPos.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local value = math.floor(min + (max - min) * relX + 0.5)
		fill.Size = UDim2.new(relX, 0, 1, 0)
		knob.Position = UDim2.new(relX, -7, 0.5, -7)
		label.Text = text .. ": " .. tostring(value)
		if callback then callback(value) end
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input.Position)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input.Position)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return row
end

function ModernUI:AddTextBox(placeholder, callback)
	local theme = self.Theme
	local box = create("TextBox", {
		Text = "",
		PlaceholderText = placeholder or "Enter text...",
		Font = theme.Font,
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.SubText,
		BackgroundColor3 = theme.Surface,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, { corner(10), padding(8), stroke(theme.Border, 1) })

	box.Focused:Connect(function()
		tween(box.UIStroke, self.TweenFast, { Color = theme.Accent })
	end)
	box.FocusLost:Connect(function(enterPressed)
		tween(box.UIStroke, self.TweenFast, { Color = theme.Border })
		if callback then callback(box.Text, enterPressed) end
	end)

	return box
end

return ModernUI