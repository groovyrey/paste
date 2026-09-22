--[[
	NotificationSystem.lua

	Toast-style notification queue, styled to match ModernUI.lua. Standalone —
	does not require ModernUI, but accepts a ModernUI.Theme table if you want
	notifications to match a ModernUI window's palette.

	Usage (executor):
		local Notif = loadstring(readfile("NotificationSystem.lua"))()
		local notify = Notif.new()
		notify:Push({ Title = "Saved", Message = "Settings written to disk.", Type = "Success" })
		notify:Push({ Title = "Heads up", Message = "Connection is slow.", Type = "Warning", Duration = 6 })

	Usage (ModuleScript, sharing a ModernUI theme):
		local ModernUI = require(path.to.ModernUI)
		local NotificationSystem = require(path.to.NotificationSystem)
		local notify = NotificationSystem.new({ Theme = ModernUI.Theme })

	Options for new():
		Theme      (table | nil)   override any DEFAULT_THEME field
		                           (notifications always anchor top-center of the screen)
		Width      (number)        toast width in pixels, default 300
		Margin     (number)        distance from screen edge, default 16
		Spacing    (number)        gap between stacked toasts, default 8
		MaxVisible (number)        oldest toast is dismissed once exceeded, default 5
		Gui        (ScreenGui|nil) parent notifications into an existing GUI
		Parent     (instance|nil)  default LocalPlayer.PlayerGui
		Name       (string)        ScreenGui name, default "NotificationSystem"

	Push(options):
		Title      (string)        default "Notification"
		Message    (string|nil)    optional body text
		Type       (string)        "Info" | "Success" | "Warning" | "Error", default "Info"
		Duration   (number)        seconds before auto-dismiss, default 4; pass 0 / math.huge to persist
		Closable   (boolean)       show an × button, default true
		OnClick    (function|nil)  fired when the toast body is clicked
--]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local NotificationSystem = {}
NotificationSystem.__index = NotificationSystem

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
NotificationSystem.Theme = DEFAULT_THEME

-- Per-type accent colors, layered on top of whatever Theme is passed in.
local TYPE_COLORS = {
	Info = Color3.fromRGB(99, 102, 241),
	Success = Color3.fromRGB(52, 199, 89),
	Warning = Color3.fromRGB(255, 179, 64),
	Error = Color3.fromRGB(255, 92, 92),
}

local TYPE_GLYPH = {
	Info = "i",
	Success = "✓",
	Warning = "!",
	Error = "✕",
}

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

-- Layout rules per corner: which edge anchors the stack, which direction new
-- toasts push older ones, and where a toast slides in from.
local POSITION_RULES = {
	TopRight = { anchorX = 1, anchorY = 0, growDown = true, slideX = 1 },
	TopLeft = { anchorX = 0, anchorY = 0, growDown = true, slideX = -1 },
	BottomRight = { anchorX = 1, anchorY = 1, growDown = false, slideX = 1 },
	BottomLeft = { anchorX = 0, anchorY = 1, growDown = false, slideX = -1 },
	TopCenter = { anchorX = 0.5, anchorY = 0, growDown = true, slideX = 0 },
	BottomCenter = { anchorX = 0.5, anchorY = 1, growDown = false, slideX = 0 },
}

--// CONSTRUCTOR ----------------------------------------------------------

function NotificationSystem.new(options)
	options = options or {}
	local self = setmetatable({}, NotificationSystem)

	self.Theme = mergeTheme(DEFAULT_THEME, options.Theme)
	self.Position = "TopCenter" -- fixed: notifications always anchor to top-center
	self.Rule = POSITION_RULES[self.Position]
	self.Width = options.Width or 300
	self.Margin = options.Margin or 16
	self.Spacing = options.Spacing or 8
	self.MaxVisible = options.MaxVisible or 5

	local parent = options.Parent
	if parent == nil then
		local lp = Players.LocalPlayer
		if not lp then
			error("NotificationSystem.new: no Parent given and no LocalPlayer available", 2)
		end
		parent = lp:WaitForChild("PlayerGui")
	end

	local gui = options.Gui
	if not gui then
		gui = create("ScreenGui", {
			Name = options.Name or "NotificationSystem",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = 500, -- float above most other UI, including a ModernUI window
			Parent = parent,
		})
	end
	self.Gui = gui

	-- Invisible stack container anchored to the chosen corner. Toasts are
	-- parented here and positioned manually (not a UIListLayout) so each one
	-- can independently tween its position when a sibling is removed.
	local rule = self.Rule
	self.Stack = create("Frame", {
		Name = "NotificationStack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(rule.anchorX, rule.anchorY),
		Position = UDim2.new(rule.anchorX, 0, rule.anchorY, 0),
		Size = UDim2.fromOffset(self.Width + self.Margin * 2, 0),
		Parent = gui,
	})

	self.Items = {} -- ordered list of active toast records

	return self
end

--// LAYOUT ---------------------------------------------------------------

-- Recomputes each toast's target Y offset from the anchored edge and tweens
-- everyone into place. Called after any push or removal.
function NotificationSystem:_relayout()
	local rule = self.Rule
	local cursor = self.Margin
	for _, item in ipairs(self.Items) do
		local h = item.Frame.AbsoluteSize.Y
		if h <= 0 then h = item.TargetHeight or 60 end

		local yOffset
		if rule.growDown then
			yOffset = cursor
		else
			yOffset = -cursor - h
		end

		local xOffset
		if rule.anchorX == 0 then
			xOffset = self.Margin
		elseif rule.anchorX == 1 then
			xOffset = -self.Margin - self.Width
		else
			xOffset = -self.Width / 2
		end

		local targetPos = UDim2.new(0, xOffset, 0, yOffset)
		if item.Settled then
			tween(item.Frame, TWEEN_MED, { Position = targetPos })
		else
			item.Frame.Position = targetPos
		end
		item.RestPosition = targetPos

		cursor = cursor + h + self.Spacing
	end
end

--// TOAST LIFECYCLE -------------------------------------------------------

function NotificationSystem:_dismiss(item)
	if item.Dismissed then return end
	item.Dismissed = true

	if item.ProgressConn then
		item.ProgressConn:Disconnect()
		item.ProgressConn = nil
	end

	for i, existing in ipairs(self.Items) do
		if existing == item then
			table.remove(self.Items, i)
			break
		end
	end

	local rule = self.Rule
	local slideOut = item.RestPosition + UDim2.fromOffset(rule.slideX * (self.Width + 40), 0)
	tween(item.Frame, TWEEN_MED, { Position = slideOut, BackgroundTransparency = 1 })
	tween(item.Stroke, TWEEN_MED, { Transparency = 1 })
	for _, obj in ipairs(item.Frame:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			tween(obj, TWEEN_MED, { TextTransparency = 1 })
		elseif obj:IsA("Frame") and obj ~= item.Frame then
			tween(obj, TWEEN_MED, { BackgroundTransparency = 1 })
		elseif obj:IsA("UIStroke") then
			tween(obj, TWEEN_MED, { Transparency = 1 })
		end
	end

	task.delay(TWEEN_MED.Time, function()
		item.Frame:Destroy()
	end)

	self:_relayout()
end

-- Push a new toast. Returns a handle table with :Dismiss() so callers can
-- close it early (e.g. once a long-running task finishes).
function NotificationSystem:Push(options)
	options = options or {}
	local theme = self.Theme
	local kind = TYPE_COLORS[options.Type] and options.Type or "Info"
	local accentColor = TYPE_COLORS[kind]
	local duration = options.Duration
	if duration == nil then duration = 4 end
	local closable = options.Closable
	if closable == nil then closable = true end

	-- Evict the oldest toast if we're over capacity, so the stack never runs
	-- off the bottom of the screen.
	if #self.Items >= self.MaxVisible then
		self:_dismiss(self.Items[1])
	end

	local hasMessage = options.Message ~= nil and options.Message ~= ""

	local frame = create("Frame", {
		Name = "Toast",
		BackgroundColor3 = theme.Surface,
		Size = UDim2.fromOffset(self.Width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		Parent = self.Stack,
	})
	local frameCorner = corner(0)
	local frameStroke = stroke(theme.Border, 1)
	frameCorner.Parent = frame
	frameStroke.Parent = frame

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	}, { padding(12) })

	-- Colored accent bar down the left edge signals severity at a glance.
	create("Frame", {
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, 0),
		Parent = frame,
	})

	local glyphBadge = create("Frame", {
		BackgroundColor3 = accentColor,
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(4, 0),
		Parent = body,
	}, { corner(12) })
	create("TextLabel", {
		Text = TYPE_GLYPH[kind],
		Font = theme.FontBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = glyphBadge,
	})

	local textWidth = closable and (self.Width - 12 * 2 - 32 - 28) or (self.Width - 12 * 2 - 32)

	local titleLabel = create("TextLabel", {
		Text = options.Title or "Notification",
		Font = theme.FontBold,
		TextSize = 14,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(textWidth, 18),
		Position = UDim2.fromOffset(36, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})

	if hasMessage then
		create("TextLabel", {
			Text = options.Message,
			Font = theme.Font,
			TextSize = 13,
			TextColor3 = theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(textWidth, 0),
			Position = UDim2.fromOffset(36, 20),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = body,
		})
	end

	-- Invisible click-catcher over the body, for OnClick handlers.
	local clickCatcher = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 0,
		Parent = body,
	})

	local closeBtn
	if closable then
		closeBtn = create("TextButton", {
			Text = "×",
			Font = theme.FontBold,
			TextSize = 16,
			TextColor3 = theme.SubText,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.new(1, -22, 0, -2),
			AutoButtonColor = false,
			Parent = body,
		})
		closeBtn.MouseEnter:Connect(function()
			tween(closeBtn, TWEEN_FAST, { TextColor3 = theme.Text })
		end)
		closeBtn.MouseLeave:Connect(function()
			tween(closeBtn, TWEEN_FAST, { TextColor3 = theme.SubText })
		end)
	end

	-- Progress bar along the bottom edge shows time remaining before auto-dismiss.
	local progressTrack, progressFill
	if duration and duration > 0 and duration ~= math.huge then
		progressTrack = create("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 3),
			Position = UDim2.new(0, 0, 1, -3),
			Parent = frame,
		})
		progressFill = create("Frame", {
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = progressTrack,
		})
	end

	local item = {
		Frame = frame,
		Stroke = frameStroke,
		TargetHeight = hasMessage and 76 or 52,
		Settled = false,
		Dismissed = false,
	}
	table.insert(self.Items, item)

	if options.OnClick then
		clickCatcher.MouseButton1Click:Connect(function()
			options.OnClick()
		end)
	end
	if closeBtn then
		closeBtn.MouseButton1Click:Connect(function()
			self:_dismiss(item)
		end)
	end

	-- Slide-and-fade entrance from the edge the stack is anchored to.
	local rule = self.Rule
	frame.BackgroundTransparency = 1
	frameStroke.Transparency = 1
	titleLabel.TextTransparency = 1
	task.defer(function()
		self:_relayout()
		item.Settled = true
		local restPos = item.RestPosition
		frame.Position = restPos + UDim2.fromOffset(rule.slideX * 30, 0)
		tween(frame, TWEEN_IN, { Position = restPos, BackgroundTransparency = 0 })
		tween(frameStroke, TWEEN_MED, { Transparency = 0 })
		tween(titleLabel, TWEEN_MED, { TextTransparency = 0 })
	end)

	if duration and duration > 0 and duration ~= math.huge then
		if progressFill then
			tween(progressFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
				Size = UDim2.new(0, 0, 1, 0),
			})
		end
		task.delay(duration, function()
			self:_dismiss(item)
		end)
	end

	return {
		Dismiss = function()
			self:_dismiss(item)
		end,
		Frame = frame,
	}
end

--// CONVENIENCE SHORTHANDS -----------------------------------------------

function NotificationSystem:Info(title, message, duration)
	return self:Push({ Title = title, Message = message, Type = "Info", Duration = duration })
end

function NotificationSystem:Success(title, message, duration)
	return self:Push({ Title = title, Message = message, Type = "Success", Duration = duration })
end

function NotificationSystem:Warn(title, message, duration)
	return self:Push({ Title = title, Message = message, Type = "Warning", Duration = duration })
end

function NotificationSystem:Error(title, message, duration)
	return self:Push({ Title = title, Message = message, Type = "Error", Duration = duration })
end

function NotificationSystem:ClearAll()
	for _, item in ipairs(table.clone(self.Items)) do
		self:_dismiss(item)
	end
end

function NotificationSystem:Destroy()
	self.Gui:Destroy()
end

return NotificationSystem
