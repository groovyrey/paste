--[[
	ModernUI.client.lua
	Standalone LocalScript — modern dark-themed UI. No require() needed.

	Place this directly inside StarterPlayerScripts (or StarterGui) as a LocalScript.
	Everything below runs immediately and builds the UI + example components.
	Edit the "BUILD YOUR UI HERE" section at the bottom to customize.
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--// THEME ---------------------------------------------------------------
local Theme = {
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

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
		Color = color or Theme.Border,
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

--// BUILD THE WINDOW ------------------------------------------------------

local ScreenGui = create("ScreenGui", {
	Name = "ModernUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = PlayerGui,
})

local windowCorner = corner(14)
local Window = create("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(340, 420),
	Position = UDim2.new(0.5, -170, 0.5, -210),
	BackgroundColor3 = Theme.Background,
	Parent = ScreenGui,
}, { windowCorner, stroke(Theme.Border, 1) })

create("ImageLabel", {
	Name = "Shadow",
	BackgroundTransparency = 1,
	Image = "rbxassetid://1316045217",
	ImageColor3 = Color3.new(0, 0, 0),
	ImageTransparency = 0.4,
	ScaleType = Enum.ScaleType.Slice,
	SliceCenter = Rect.new(10, 10, 118, 118),
	Size = UDim2.new(1, 40, 1, 40),
	Position = UDim2.new(0, -20, 0, -20),
	ZIndex = 0,
	Parent = Window,
})

-- NOTE: this is a TextButton (not a Frame) so that Roblox marks drag input as
-- "game processed" — otherwise the default camera script also reads the same
-- mouse-drag input and rotates the camera while you're dragging the window.
local titleBarCorner = corner(14)
local TitleBar = create("TextButton", {
	Name = "TitleBar",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = Theme.Surface,
	Parent = Window,
}, { titleBarCorner })

local titleBarMask = create("Frame", {
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 1, -14),
	BackgroundColor3 = Theme.Surface,
	BorderSizePixel = 0,
	Parent = TitleBar,
})

local titleText = create("TextLabel", {
	Text = "Modern UI",
	Font = Theme.FontBold,
	TextSize = 16,
	TextColor3 = Theme.Text,
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
	Font = Theme.FontBold,
	TextSize = 16,
	TextColor3 = Theme.SubText,
	BackgroundColor3 = Theme.SurfaceLight,
	Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, -38, 0.5, -14),
	AutoButtonColor = false,
	ZIndex = 2,
	Parent = TitleBar,
}, { corner(14) })

collapseBtn.MouseEnter:Connect(function()
	tween(collapseBtn, TWEEN_FAST, { BackgroundColor3 = Theme.AccentHover })
end)
collapseBtn.MouseLeave:Connect(function()
	tween(collapseBtn, TWEEN_FAST, { BackgroundColor3 = Theme.SurfaceLight })
end)

makeDraggable(TitleBar, Window)

local Content = create("ScrollingFrame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Theme.Accent,
	BorderSizePixel = 0,
	Parent = Window,
}, {
	padding(14),
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}),
})

Window.Size = UDim2.fromOffset(0, 0)
Window.Position = UDim2.new(0.5, 0, 0.5, 0)
tween(Window, TWEEN_MED, {
	Size = UDim2.fromOffset(340, 420),
	Position = UDim2.new(0.5, -170, 0.5, -210),
})

--// COLLAPSE / EXPAND -----------------------------------------------------

local EXPANDED_SIZE = UDim2.fromOffset(340, 420)
local COLLAPSED_SIZE = UDim2.fromOffset(56, 56)
local isCollapsed = false

local function setCollapsed(state)
	if isCollapsed == state then return end
	isCollapsed = state

	if isCollapsed then
		-- fade out everything except the collapse button itself
		titleText.Visible = false
		titleBarMask.Visible = false
		Content.Visible = false

		tween(windowCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 28) })
		tween(titleBarCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 28) })
		tween(Window, TWEEN_MED, { Size = COLLAPSED_SIZE })
		tween(TitleBar, TWEEN_MED, { Size = UDim2.new(1, 0, 1, 0) })
		tween(collapseBtn, TWEEN_MED, {
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromOffset(0, 0),
		})
		collapseBtn.Text = ""
		local collapseBtnCorner = collapseBtn:FindFirstChildOfClass("UICorner")
		if collapseBtnCorner then
			tween(collapseBtnCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 28) })
		end
	else
		tween(windowCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 14) })
		tween(titleBarCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 14) })
		tween(Window, TWEEN_MED, { Size = EXPANDED_SIZE })
		tween(TitleBar, TWEEN_MED, { Size = UDim2.new(1, 0, 0, 44) })
		tween(collapseBtn, TWEEN_MED, {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -38, 0.5, -14),
		})
		local collapseBtnCorner = collapseBtn:FindFirstChildOfClass("UICorner")
		if collapseBtnCorner then
			tween(collapseBtnCorner, TWEEN_MED, { CornerRadius = UDim.new(0, 14) })
		end

		task.delay(TWEEN_MED.Time, function()
			if isCollapsed then return end -- toggled again before this fired
			collapseBtn.Text = "–"
			titleText.Visible = true
			titleBarMask.Visible = true
			Content.Visible = true
		end)
	end
end

-- collapseBtn covers the whole window once collapsed, so it needs to be
-- draggable too (not just clickable) — makeDraggable's onClick param handles
-- telling a genuine click apart from a drag.
makeDraggable(collapseBtn, Window, function()
	setCollapsed(not isCollapsed)
end)

local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

--// COMPONENT FUNCTIONS ---------------------------------------------------

local function AddLabel(text)
	return create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = Content,
	})
end

local function AddButton(text, callback)
	local btn = create("TextButton", {
		Text = text,
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Accent,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = nextOrder(),
		Parent = Content,
	}, { corner(10) })

	btn.MouseEnter:Connect(function()
		tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.AccentHover })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.Accent })
	end)
	btn.MouseButton1Down:Connect(function()
		tween(btn, TWEEN_FAST, { Size = UDim2.new(1, -6, 0, 36) })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(btn, TWEEN_FAST, { Size = UDim2.new(1, 0, 0, 38) })
	end)
	btn.MouseButton1Click:Connect(function()
		if callback then callback() end
	end)

	return btn
end

local function AddToggle(text, default, callback)
	local state = default or false

	local row = create("Frame", {
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = nextOrder(),
		Parent = Content,
	}, { corner(10), padding(10) })

	create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -50, 1, 0),
		Parent = row,
	})

	local track = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = state and Theme.Accent or Theme.SurfaceLight,
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
		tween(track, TWEEN_FAST, { BackgroundColor3 = state and Theme.Accent or Theme.SurfaceLight })
		tween(knob, TWEEN_FAST, {
			Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		})
		if callback then callback(state) end
	end)

	return track
end

local function AddSlider(text, min, max, default, callback)
	min, max = min or 0, max or 100
	default = math.clamp(default or min, min, max)

	local row = create("Frame", {
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = nextOrder(),
		Parent = Content,
	}, { corner(10), padding(10) })

	local label = create("TextLabel", {
		Text = text .. ": " .. tostring(default),
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = row,
	})

	local bar = create("Frame", {
		BackgroundColor3 = Theme.SurfaceLight,
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -8),
		Parent = row,
	}, { corner(3) })

	local fillPct = (default - min) / (max - min)
	local fill = create("Frame", {
		BackgroundColor3 = Theme.Accent,
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

local function AddTextBox(placeholder, callback)
	local box = create("TextBox", {
		Text = "",
		PlaceholderText = placeholder or "Enter text...",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		BackgroundColor3 = Theme.Surface,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = nextOrder(),
		Parent = Content,
	}, { corner(10), padding(8), stroke(Theme.Border, 1) })

	box.Focused:Connect(function()
		tween(box.UIStroke, TWEEN_FAST, { Color = Theme.Accent })
	end)
	box.FocusLost:Connect(function(enterPressed)
		tween(box.UIStroke, TWEEN_FAST, { Color = Theme.Border })
		if callback then callback(box.Text, enterPressed) end
	end)

	return box
end

--// FEATURE: Infinite Jump -------------------------------------------------
-- Hooks the jump input directly: whenever the player requests a jump while
-- the toggle is on, it forces the humanoid into the Jumping state even if
-- they're airborne, which lets them jump repeatedly with no landing needed.

local infiniteJumpEnabled = false
local humanoid = nil

local function bindHumanoid(character)
	humanoid = character:WaitForChild("Humanoid")
end

if LocalPlayer.Character then
	bindHumanoid(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(bindHumanoid)

UserInputService.JumpRequest:Connect(function()
	if infiniteJumpEnabled and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

--// BUILD YOUR UI HERE ----------------------------------------------------
-- Edit / add / remove calls below to customize the window's contents.

AddLabel("Welcome to the app")

AddButton("Click Me", function()
	print("Button clicked!")
end)

AddToggle("Enable Feature", false, function(state)
	print("Toggle:", state)
end)

AddToggle("Infinite Jump", false, function(state)
	infiniteJumpEnabled = state
end)

AddSlider("Volume", 0, 100, 50, function(value)
	print("Slider:", value)
end)

AddTextBox("Enter name...", function(text)
	print("Text entered:", text)
end)
