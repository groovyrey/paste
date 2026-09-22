--[[
	ModernUI.lua

	Reusable modern dark-themed UI module. No standalone behaviour — build a
	window with ModernUI.new(...) and call the returned UI methods.

	Usage (executor):
		local ModernUI = loadstring(readfile("ModernUI.lua"))() -- or require a ModuleScript
		local ui = ModernUI.new({ Title = "Orbyte", Size = Vector2.new(340, 420) })

		ui:AddLabel("hello")
		ui:AddButton("go", function() end)
		ui:AddToggle("on?", false, function(state) end)
		ui:AddSlider("Vol", 0, 100, 50, function(v) end)
		ui:AddTextBox("...", function(text, enter) end)

		-- Tabs: each page behaves exactly like `ui` itself (same Add* methods),
		-- it just writes into its own tab's content instead of the window's.
		local tabs = ui:AddTabs({ "Main", "Settings" }) -- 2nd arg: default index, default 1
		tabs:GetPage("Main"):AddButton("Click me", function() end)
		tabs:GetPage("Settings"):AddToggle("Beta features", false, function() end)
		tabs:OnChanged(function(name, page) end) -- fires whenever the active tab changes
		tabs:SetActive("Settings")

		-- Pagination: a Prev/Next-controlled list. Each item also behaves like
		-- `ui` (same Add* methods), scoped to that one row/card.
		local list = ui:AddPagination({ PerPage = 5 })
		for i = 1, 23 do
			list:AddItem(function(item)
				item:AddLabel("Row " .. i)
			end)
		end
		list:OnChanged(function(pageNumber, pageCount) end)
		list:GoToPage(1) / list:NextPage() / list:PrevPage()
		list:Clear() -- wipes all items back to an empty page 1

	Options for new():
		Title      (string)        default "Modern UI"
		Size       (Vector2)       default 340x420 (preferred size; it is
		                           clamped so the window always fits the screen —
		                           content scrolls when it is taller than that)
		Margin     (number)        default 16, free space kept around the window
		Theme      (table | nil)   override any DEFAULT_THEME field
		Gui        (ScreenGui | nil) parent a window into an existing GUI
		Parent     (instance | nil) default LocalPlayer.PlayerGui
		Name       (string)        ScreenGui name, default "ModernUI"
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local ModernUI = {}
ModernUI.__index = ModernUI

--// THEME ---------------------------------------------------------------

local DEFAULT_THEME = {
	Background = Color3.fromRGB(24, 24, 28),
	Surface = Color3.fromRGB(32, 32, 38),
	SurfaceLight = Color3.fromRGB(42, 42, 50),
	Accent = Color3.fromRGB(99, 102, 241), -- indigo
	AccentHover = Color3.fromRGB(129, 132, 255),
	Text = Color3.fromRGB(235, 235, 240),
	SubText = Color3.fromRGB(160, 160, 170),
	Border = Color3.fromRGB(50, 50, 58),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
ModernUI.Theme = DEFAULT_THEME

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MIN_WINDOW = 120 -- smallest width/height the window may shrink to

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

-- Usable screen area for the GUI (already excludes the top bar inset unless the
-- ScreenGui ignores it). Falls back to the camera viewport if the ScreenGui
-- hasn't been laid out yet.
local function getViewport(gui)
	local abs = gui.AbsoluteSize
	if abs.X > 0 and abs.Y > 0 then
		return abs
	end
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(800, 600)
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

-- Metatables for the lightweight "page-like" objects Tabs and Pagination hand
-- back. They deliberately share ModernUI's __index so every ModernUI:AddX
-- component function works on them unmodified, as long as they expose the
-- same fields those functions read (Theme, TweenFast, TweenMed, Content, order).
local TabsMeta = {}
TabsMeta.__index = TabsMeta

local PaginationMeta = {}
PaginationMeta.__index = PaginationMeta

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

	-- Preferred size is clamped to the screen so the window always fits (phones
	-- included). The content area is a ScrollingFrame, so anything taller than
	-- the window just scrolls.
	self.DesiredSize = options.Size or Vector2.new(340, 420)
	self.Margin = options.Margin or 16
	local size = self:_fitSize()
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
		ScrollingDirection = Enum.ScrollingDirection.Y,
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

	-- Re-fit when the screen size changes (rotation, window resize, keyboard…).
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Refit()
	end)

	return self
end

--// SIZING ---------------------------------------------------------------

-- Preferred size clamped to the available screen area (minus margin).
function ModernUI:_fitSize()
	local view = getViewport(self.Gui)
	local m = self.Margin
	return Vector2.new(
		math.max(math.min(self.DesiredSize.X, view.X - m * 2), MIN_WINDOW),
		math.max(math.min(self.DesiredSize.Y, view.Y - m * 2), MIN_WINDOW)
	)
end

-- Nudge the window back on screen if it's hanging off any edge.
function ModernUI:_clampToScreen()
	local window = self.Window
	if not window or not window.Parent then return end
	local view = getViewport(self.Gui)
	local rel = window.AbsolutePosition - self.Gui.AbsolutePosition
	local size = window.AbsoluteSize
	local targetX = math.clamp(rel.X, 0, math.max(0, view.X - size.X))
	local targetY = math.clamp(rel.Y, 0, math.max(0, view.Y - size.Y))
	local dx, dy = targetX - rel.X, targetY - rel.Y
	if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
		tween(window, self.TweenFast, {
			Position = window.Position + UDim2.fromOffset(dx, dy),
		})
	end
end

-- Recompute the window size for the current screen. Called automatically when
-- the screen size changes; call it yourself after changing DesiredSize/Margin.
function ModernUI:Refit()
	local fit = self:_fitSize()
	self.ExpandedSize = UDim2.fromOffset(fit.X, fit.Y)
	if not self.isCollapsed then
		tween(self.Window, self.TweenFast, { Size = self.ExpandedSize })
		task.delay(self.TweenFast.Time, function()
			self:_clampToScreen()
		end)
	else
		self:_clampToScreen()
	end
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
			self:_clampToScreen() -- expanded near an edge? pull it back on screen
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
			self.Content.ScrollingEnabled = false -- don't scroll the window while sliding
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
			if dragging then
				dragging = false
				self.Content.ScrollingEnabled = true
			end
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

--// TABS -------------------------------------------------------------
--
-- ui:AddTabs({"Main","Settings"}, 1) returns a Tabs controller. Each tab's
-- "page" is a table sharing ModernUI's metatable, so tabs:GetPage("Main")
-- gets every ModernUI:AddX method for free, scoped to that tab's own content
-- frame. Only the active page's frame is Visible at a time; UIListLayout
-- automatically skips invisible siblings, so the window still resizes to fit
-- whichever tab is showing.

function ModernUI:AddTabs(names, defaultIndex)
	local theme = self.Theme
	names = names or {}
	defaultIndex = defaultIndex or 1

	local bar = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})

	local pagesContainer = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	})

	local tabs = setmetatable({
		Theme = theme,
		TweenFast = self.TweenFast,
		TweenMed = self.TweenMed,
		Bar = bar,
		PagesContainer = pagesContainer,
		Buttons = {}, -- [name] = TextButton
		Pages = {}, -- [name] = page object
		Order = {}, -- names in the order they were added
		ActiveName = nil,
		ActivePage = nil,
		ChangedCallback = nil,
	}, TabsMeta)

	for _, name in ipairs(names) do
		tabs:AddPage(name)
	end
	if names[defaultIndex] then
		tabs:SetActive(names[defaultIndex])
	end

	return tabs
end

-- Adds one tab, returns its page object (same Add* methods as ModernUI).
function TabsMeta:AddPage(name)
	local theme = self.Theme

	local textSize = TextService:GetTextSize(name, 13, theme.FontBold, Vector2.new(1000, 30))
	local btn = create("TextButton", {
		Text = name,
		Font = theme.FontBold,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundColor3 = theme.Surface,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(textSize.X + 24, 30),
		LayoutOrder = #self.Order + 1,
		Parent = self.Bar,
	}, { corner(8) })

	local pageContent = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = #self.Order + 1,
		Parent = self.PagesContainer,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})

	local page = setmetatable({
		Theme = theme,
		TweenFast = self.TweenFast,
		TweenMed = self.TweenMed,
		Content = pageContent,
		order = 0,
	}, ModernUI)

	self.Buttons[name] = btn
	self.Pages[name] = page
	table.insert(self.Order, name)

	btn.MouseButton1Click:Connect(function()
		self:SetActive(name)
	end)
	btn.MouseEnter:Connect(function()
		if self.ActiveName ~= name then
			tween(btn, self.TweenFast, { BackgroundColor3 = theme.SurfaceLight })
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.ActiveName ~= name then
			tween(btn, self.TweenFast, { BackgroundColor3 = theme.Surface })
		end
	end)

	return page
end

-- Switches which tab is showing. No-op if `name` is already active or unknown.
function TabsMeta:SetActive(name)
	local page = self.Pages[name]
	if not page or self.ActiveName == name then return end

	if self.ActiveName then
		local prevPage = self.Pages[self.ActiveName]
		if prevPage then prevPage.Content.Visible = false end
		local prevBtn = self.Buttons[self.ActiveName]
		if prevBtn then
			tween(prevBtn, self.TweenFast, {
				BackgroundColor3 = self.Theme.Surface,
				TextColor3 = self.Theme.SubText,
			})
		end
	end

	page.Content.Visible = true
	self.ActiveName = name
	self.ActivePage = page

	local btn = self.Buttons[name]
	if btn then
		tween(btn, self.TweenFast, {
			BackgroundColor3 = self.Theme.Accent,
			TextColor3 = Color3.new(1, 1, 1),
		})
	end

	if self.ChangedCallback then
		self.ChangedCallback(name, page)
	end
end

function TabsMeta:GetPage(name)
	return self.Pages[name]
end

function TabsMeta:GetActive()
	return self.ActiveName, self.ActivePage
end

-- callback(name, page) fires every time SetActive changes the active tab.
function TabsMeta:OnChanged(callback)
	self.ChangedCallback = callback
end

--// PAGINATION ---------------------------------------------------------
--
-- ui:AddPagination({ PerPage = 5 }) returns a Pagination controller with a
-- Prev/Next control row. list:AddItem(builderFn) adds one row/card; builderFn
-- receives a page-like object (same Add* methods as ModernUI) scoped to that
-- item. Only the current page's items are Visible; everything else follows
-- the same show/hide approach as Tabs above.

function ModernUI:AddPagination(options)
	options = options or {}
	local theme = self.Theme
	local perPage = math.max(1, options.PerPage or 5)

	local itemsContainer = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})

	local controls = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(self),
		Parent = self.Content,
	})

	local prevBtn = create("TextButton", {
		Text = "‹",
		Font = theme.FontBold,
		TextSize = 16,
		TextColor3 = theme.Text,
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(0, 0),
		Parent = controls,
	}, { corner(10) })

	local pageLabel = create("TextLabel", {
		Text = "1 / 1",
		Font = theme.Font,
		TextSize = 13,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -76, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		Parent = controls,
	})

	local nextBtn = create("TextButton", {
		Text = "›",
		Font = theme.FontBold,
		TextSize = 16,
		TextColor3 = theme.Text,
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -34, 0, 0),
		Parent = controls,
	}, { corner(10) })

	local pag = setmetatable({
		Theme = theme,
		TweenFast = self.TweenFast,
		TweenMed = self.TweenMed,
		ItemsContainer = itemsContainer,
		Controls = controls,
		PrevButton = prevBtn,
		NextButton = nextBtn,
		PageLabel = pageLabel,
		PerPage = perPage,
		Items = {}, -- { Frame = Frame, Page = page }[]
		CurrentPage = 1,
		ChangedCallback = nil,
	}, PaginationMeta)

	prevBtn.MouseButton1Click:Connect(function() pag:PrevPage() end)
	nextBtn.MouseButton1Click:Connect(function() pag:NextPage() end)
	prevBtn.MouseEnter:Connect(function() tween(prevBtn, self.TweenFast, { BackgroundColor3 = theme.Accent }) end)
	prevBtn.MouseLeave:Connect(function() tween(prevBtn, self.TweenFast, { BackgroundColor3 = theme.SurfaceLight }) end)
	nextBtn.MouseEnter:Connect(function() tween(nextBtn, self.TweenFast, { BackgroundColor3 = theme.Accent }) end)
	nextBtn.MouseLeave:Connect(function() tween(nextBtn, self.TweenFast, { BackgroundColor3 = theme.SurfaceLight }) end)

	pag:_refresh()
	return pag
end

function PaginationMeta:_pageCount()
	return math.max(1, math.ceil(#self.Items / self.PerPage))
end

-- Shows/hides items for the current page and updates the "n / n" label and
-- Prev/Next enabled state. Called automatically by AddItem/Clear/NextPage/etc.
function PaginationMeta:_refresh()
	local pageCount = self:_pageCount()
	self.CurrentPage = math.clamp(self.CurrentPage, 1, pageCount)

	local startIdx = (self.CurrentPage - 1) * self.PerPage + 1
	local endIdx = math.min(startIdx + self.PerPage - 1, #self.Items)

	for i, item in ipairs(self.Items) do
		item.Frame.Visible = (i >= startIdx and i <= endIdx)
	end

	self.PageLabel.Text = string.format("%d / %d", self.CurrentPage, pageCount)

	local canPrev = self.CurrentPage > 1
	local canNext = self.CurrentPage < pageCount
	self.PrevButton.Active = canPrev
	self.NextButton.Active = canNext
	self.PrevButton.TextTransparency = canPrev and 0 or 0.6
	self.NextButton.TextTransparency = canNext and 0 or 0.6

	if self.ChangedCallback then
		self.ChangedCallback(self.CurrentPage, pageCount)
	end
end

function PaginationMeta:NextPage()
	if self.CurrentPage < self:_pageCount() then
		self.CurrentPage += 1
		self:_refresh()
	end
end

function PaginationMeta:PrevPage()
	if self.CurrentPage > 1 then
		self.CurrentPage -= 1
		self:_refresh()
	end
end

function PaginationMeta:GoToPage(n)
	self.CurrentPage = math.clamp(n, 1, self:_pageCount())
	self:_refresh()
end

-- Adds one paginated item. builderFn(item) is called immediately with a
-- page-like object (same Add* methods as ModernUI) scoped to this item's own
-- frame; returns that same object.
function PaginationMeta:AddItem(builderFn)
	local itemFrame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = #self.Items + 1,
		Parent = self.ItemsContainer,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})

	local itemPage = setmetatable({
		Theme = self.Theme,
		TweenFast = self.TweenFast,
		TweenMed = self.TweenMed,
		Content = itemFrame,
		order = 0,
	}, ModernUI)

	table.insert(self.Items, { Frame = itemFrame, Page = itemPage })

	if builderFn then
		builderFn(itemPage)
	end

	self:_refresh()
	return itemPage
end

-- Destroys every item's frame and resets back to an empty page 1.
function PaginationMeta:Clear()
	for _, item in ipairs(self.Items) do
		item.Frame:Destroy()
	end
	self.Items = {}
	self.CurrentPage = 1
	self:_refresh()
end

function PaginationMeta:SetPerPage(n)
	self.PerPage = math.max(1, n)
	self:_refresh()
end

-- callback(pageNumber, pageCount) fires whenever the current page changes
-- (NextPage/PrevPage/GoToPage) or the item count changes (AddItem/Clear).
function PaginationMeta:OnChanged(callback)
	self.ChangedCallback = callback
end

return ModernUI
