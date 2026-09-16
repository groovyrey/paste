local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")
local Net = game:GetService("Stats").Network
local Camera = workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")

local Player = Players.LocalPlayer
local CoreUI = game:GetService("CoreGui")
if CoreUI:FindFirstChild("Debold") then CoreUI.Debold:Destroy() end

local C = {
	Bg    = Color3.fromRGB(16, 20, 25),
	Panel = Color3.fromRGB(24, 29, 35),
	Line  = Color3.fromRGB(44, 51, 61),
	Txt   = Color3.fromRGB(226, 231, 240),
	Dim   = Color3.fromRGB(139, 149, 164),
	Accent = Color3.fromRGB(122, 224, 195),
	Danger = Color3.fromRGB(240, 118, 118),
	Warn   = Color3.fromRGB(244, 208, 128),
	Hover  = Color3.fromRGB(31, 37, 44),
}

local root = Instance.new("ScreenGui")
root.Name = "Debold"
root.ResetOnSpawn = false
root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
root.Parent = CoreUI

local function corner(obj, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r)
	u.Parent = obj
end

local function stroke(obj, t, tl)
	local s = Instance.new("UIStroke")
	s.Color = C.Line
	s.Thickness = t or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if tl ~= nil then s.Transparency = tl end
	s.Parent = obj
end

local function make(parent, class, props)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end

local function listLayout(parent, pad)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, pad or 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment.Left
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

local vp = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
local inset = GuiService:GetGuiInset()
local pad = math.clamp(vp.X * 0.02, 8, 18)
local frameW = math.min(450, vp.X - pad * 2)
local frameH = math.min(620, vp.Y - pad * 2)

local frame = make(root, "Frame", {
	Size = UDim2.new(0, frameW, 0, frameH),
	Position = UDim2.new(0, (vp.X - frameW) / 2, 0, inset.Y + 12),
	BackgroundColor3 = C.Bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
})
corner(frame, 14)
stroke(frame, 1)

local shade = make(frame, "Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.Line,
	BorderSizePixel = 0,
})

local titlebar = make(frame, "Frame", {
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
})

local brand = make(titlebar, "TextLabel", {
	Position = UDim2.new(0, 18, 0, 13),
	Size = UDim2.new(0, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "DEBOLD",
	TextColor3 = C.Txt,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 19,
	AutomaticSize = Enum.AutomaticSize.X,
})

make(titlebar, "TextLabel", {
	Position = UDim2.new(0, 76, 0, 17),
	Size = UDim2.new(0, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "LAUNCHER",
	TextColor3 = C.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 11,
	AutomaticSize = Enum.AutomaticSize.X,
})

local closeBtn = make(titlebar, "TextButton", {
	Size = UDim2.new(0, 34, 0, 34),
	Position = UDim2.new(1, -40, 0, 6),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "X",
	TextColor3 = C.Dim,
	TextSize = 14,
})
corner(closeBtn, 8)

local dragging = false
local lastX, lastY

local function onInputBegan(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		dragging = true
		lastX = input.Position.X
		lastY = input.Position.Y
	end
end
local function onInputEnded(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		dragging = false
	end
end
local function onInputChanged(input)
	if not dragging then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
		local curX = input.Position.X
		local curY = input.Position.Y
		local pos = frame.Position
		local dv = Camera and Camera.ViewportSize or vp
		local nx = pos.X.Offset + (curX - lastX)
		local ny = pos.Y.Offset + (curY - lastY)
		if nx < 10 then nx = 10 end
		if ny < 10 then ny = 10 end
		if nx > dv.X - 90 then nx = dv.X - 90 end
		if ny > dv.Y - 60 then ny = dv.Y - 60 end
		frame.Position = UDim2.new(0, nx, 0, ny)
		lastX = curX
		lastY = curY
	end
end

titlebar.InputBegan:Connect(onInputBegan)
titlebar.InputEnded:Connect(onInputEnded)
titlebar.InputChanged:Connect(onInputChanged)
UserInputService.InputChanged:Connect(onInputChanged)

local tabbar = make(frame, "Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, 46),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
})
make(tabbar, "Frame", {
	Size = UDim2.new(1, -36, 0, 1),
	Position = UDim2.new(0, 18, 1, -1),
	BackgroundColor3 = C.Line,
	BorderSizePixel = 0,
})

local function makeTab(text, xoff)
	local b = make(tabbar, "TextButton", {
		Size = UDim2.new(0, 84, 0, 32),
		Position = UDim2.new(0, xoff, 0, 4),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = text,
		TextColor3 = C.Dim,
		TextSize = 13,
	})
	corner(b, 8)
	return b
end

local tabDebug = makeTab("DEBUG", 18)
local tabScripts = makeTab("SCRIPTS", 108)
local tabConsole = makeTab("CONSOLE", 198)
tabDebug.TextColor3 = C.Txt

local pages = {}

local pageH = frameH - 126

local function makePage()
	return make(frame, "Frame", {
		Size = UDim2.new(1, 0, 0, pageH),
		Position = UDim2.new(0, 0, 0, 86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
end

local debugPage = makePage()
local debugScroll = make(debugPage, "ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Line,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
local debugContent = make(debugScroll, "Frame", {
	Size = UDim2.new(1, -28, 0, 0),
	Position = UDim2.new(0, 14, 0, 10),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
listLayout(debugContent, 6)

local dbgRows = {}

local function row(label)
	local ground = make(debugContent, "Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		LayoutOrder = #dbgRows + 1,
	})
	corner(ground, 6)
	make(ground, "TextLabel", {
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(0, 130, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = label,
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
	})
	local v = make(ground, "TextLabel", {
		Position = UDim2.new(0, 150, 0, 4),
		Size = UDim2.new(1, -160, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "-",
		TextColor3 = C.Txt,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	dbgRows[#dbgRows + 1] = v
	return v
end

local vGame = row("GAME")
local vPlace = row("PLACE ID")
local vJob = row("JOB ID")
local vCreator = row("CREATOR")
local vGenre = row("GENRE")
local vFps = row("FPS")
local vPing = row("PING")
local vPlr = row("PLAYERS")
local vServer = row("SERVER TIME")

local playerHeader = make(debugContent, "TextLabel", {
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "IN SERVER",
	TextColor3 = C.Dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 11,
	LayoutOrder = 10,
	AutomaticSize = Enum.AutomaticSize.Y,
})

local playerRows = {}

local function buildPlayers()
	for _, pr in ipairs(playerRows) do
		pr:Destroy()
	end
	playerRows = {}
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		local ra = a == Player and 0 or 1
		local rb = b == Player and 0 or 1
		if ra ~= rb then return ra < rb end
		return a.Name < b.Name
	end)
	for i, p in ipairs(list) do
		local chip = make(debugContent, "Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = C.Panel,
			BorderSizePixel = 0,
			LayoutOrder = 11 + i,
		})
		corner(chip, 6)
		make(chip, "Frame", {
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = p == Player and C.Accent or C.Line,
			BorderSizePixel = 0,
		})
		make(chip, "TextLabel", {
			Position = UDim2.new(0, 16, 0, 4),
			Size = UDim2.new(1, -22, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = (p == Player and "* " or "") .. p.Name,
			TextColor3 = p == Player and C.Txt or C.Dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		playerRows[#playerRows + 1] = chip
	end
end

pages.debug = debugPage

local scriptsPage = makePage()
scriptsPage.Visible = false

local scriptsScroll = make(scriptsPage, "ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Line,
	CanvasSize = UDim2.new(0, 0, 0, 300),
})
local scriptsContent = make(scriptsScroll, "Frame", {
	Size = UDim2.new(1, -28, 0, 0),
	Position = UDim2.new(0, 14, 0, 10),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
listLayout(scriptsContent, 8)

local function scriptHeader(text, order)
	return make(scriptsContent, "TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

scriptHeader("SCRIPT SOURCE", 1)
local srcBox = make(scriptsContent, "TextBox", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	PlaceholderText = "URL or raw script code",
	PlaceholderColor3 = C.Dim,
	Text = "",
	TextColor3 = C.Txt,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	LayoutOrder = 2,
})
corner(srcBox, 8)

scriptHeader("SCRIPT NAME", 3)
local nameBox = make(scriptsContent, "TextBox", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	PlaceholderText = "name",
	PlaceholderColor3 = C.Dim,
	Text = "",
	TextColor3 = C.Txt,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	LayoutOrder = 4,
})
corner(nameBox, 8)

local function patchBtn(btn, on)
	if on then
		btn.TextColor3 = C.Txt
		btn.BackgroundColor3 = C.Hover
	else
		btn.TextColor3 = C.Dim
		btn.BackgroundColor3 = C.Panel
	end
end

local function actionBtn(text, order, color)
	local b = make(scriptsContent, "TextButton", {
		Size = UDim2.new(0, 118, 0, 30),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = color or C.Txt,
		TextSize = 12,
		LayoutOrder = order,
	})
	corner(b, 8)
	return b
end

local runBtn = actionBtn("RUN", 5, C.Accent)
local saveBtn = actionBtn("SAVE", 6)

make(scriptsContent, "Frame", {
	Size = UDim2.new(0, 0, 0, 6),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = 7,
	AutomaticSize = Enum.AutomaticSize.Y,
})

scriptHeader("SAVED SCRIPTS", 8)

local savedScroll = make(scriptsContent, "ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 180),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Line,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	LayoutOrder = 9,
})

local savedContent = make(savedScroll, "Frame", {
	Size = UDim2.new(1, -28, 0, 0),
	Position = UDim2.new(0, 14, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
listLayout(savedContent, 6)

local savedClear = make(savedContent, "TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Nothing saved yet. Add a script above.",
	TextColor3 = C.Dim,
	TextSize = 12,
	TextWrapped = true,
	LayoutOrder = 0,
})

pages.scripts = scriptsPage

local consolePage = makePage()
consolePage.Visible = false

make(consolePage, "Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.Line,
	BorderSizePixel = 0,
})

local conTop = make(consolePage, "Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
})

local conTitle = make(conTop, "TextLabel", {
	Position = UDim2.new(0, 4, 0, 12),
	Size = UDim2.new(0, 120, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "OUTPUT LOG",
	TextColor3 = C.Dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 11,
	TextTruncate = Enum.TextTruncate.AtEnd,
})

local copyBtn = make(conTop, "TextButton", {
	Position = UDim2.new(1, -168, 0, 6),
	Size = UDim2.new(0, 72, 0, 28),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "COPY",
	TextColor3 = C.Accent,
	TextSize = 11,
})
corner(copyBtn, 7)

local clearBtn = make(conTop, "TextButton", {
	Position = UDim2.new(1, -88, 0, 6),
	Size = UDim2.new(0, 72, 0, 28),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "CLEAR",
	TextColor3 = C.Dim,
	TextSize = 11,
})
corner(clearBtn, 7)

local logScroll = make(consolePage, "ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -40),
	Position = UDim2.new(0, 0, 0, 40),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Line,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
local logContent = make(logScroll, "Frame", {
	Size = UDim2.new(1, -24, 0, 0),
	Position = UDim2.new(0, 12, 0, 8),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
listLayout(logContent, 2)

local logEmpty = make(logContent, "TextLabel", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "No console output yet.",
	TextColor3 = C.Dim,
	TextSize = 12,
	TextWrapped = true,
	LayoutOrder = 0,
})

pages.console = consolePage

local function relayout()
	local c = workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
	local nv = c and c.ViewportSize or vp
	inset = GuiService:GetGuiInset()
	frameW = math.min(450, nv.X - math.max(8, nv.X * 0.02) * 2)
	frameH = math.min(620, nv.Y - inset.Y - 24)
	frame.Size = UDim2.new(0, frameW, 0, frameH)
	frame.Position = UDim2.new(0, (nv.X - frameW) / 2, 0, inset.Y + 12)
	pageH = frameH - 126
	debugPage.Size = UDim2.new(1, 0, 0, pageH)
	scriptsPage.Size = UDim2.new(1, 0, 0, pageH)
	consolePage.Size = UDim2.new(1, 0, 0, pageH)
end

pcall(function()
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end)

local consoleStatus = make(frame, "TextLabel", {
	Position = UDim2.new(0, 18, 1, -40),
	Size = UDim2.new(1, -36, 0, 24),
	BackgroundColor3 = C.Panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	Text = "DEBOLD // READY",
	TextColor3 = C.Dim,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
corner(consoleStatus, 6)

local function log(msg, good)
	consoleStatus.Text = msg
	consoleStatus.TextColor3 = good and C.Accent or C.Danger
end

local activeTab = tabDebug
local function setTab(tab)
	activeTab = tab
	patchBtn(tabDebug, tab == tabDebug)
	patchBtn(tabScripts, tab == tabScripts)
	patchBtn(tabConsole, tab == tabConsole)
	pages.debug.Visible = tab == tabDebug
	pages.scripts.Visible = tab == tabScripts
	pages.console.Visible = tab == tabConsole
end

tabDebug.MouseButton1Click:Connect(function() setTab(tabDebug) end)
tabScripts.MouseButton1Click:Connect(function() setTab(tabScripts) end)
tabConsole.MouseButton1Click:Connect(function() setTab(tabConsole) end)

closeBtn.MouseButton1Click:Connect(function()
	root:Destroy()
end)

closeBtn.MouseEnter:Connect(function()
	closeBtn.TextColor3 = C.Danger
end)
closeBtn.MouseLeave:Connect(function()
	closeBtn.TextColor3 = C.Dim
end)

for _, b in ipairs({runBtn, saveBtn, copyBtn, clearBtn, tabDebug, tabScripts, tabConsole}) do
	b.MouseEnter:Connect(function()
		if b.BackgroundColor3 == C.Panel then
			b.BackgroundColor3 = C.Hover
		end
	end)
	b.MouseLeave:Connect(function()
		if b.BackgroundColor3 == C.Hover then
			b.BackgroundColor3 = C.Panel
		end
	end)
end

local fpsFrames = 0
local fpsTimer = 0
local fps = 0
local frameCount = 0
local lastPlayerCount = -1

RunService.RenderStepped:Connect(function(dt)
	fpsFrames = fpsFrames + 1
	fpsTimer = fpsTimer + dt
	if fpsTimer >= 0.5 then
		fps = math.floor(fpsFrames / fpsTimer + 0.5)
		fpsFrames = 0
		fpsTimer = 0
		vFps.Text = tostring(fps)
	end

	frameCount = frameCount + 1
	if frameCount % 10 ~= 0 then return end

	local ok, ping = pcall(function()
		return Net.ServerStats["Data Ping"]:GetValue()
	end)
	if ok then vPing.Text = string.format("%d ms", ping) end

	local ok2, clock = pcall(function()
		return Lighting.ClockTime
	end)
	if ok2 then
		local h = math.floor(clock)
		local m = math.floor((clock - h) * 60)
		vServer.Text = string.format("%02d:%02d", h % 24, m)
	end

	local count = Players.NumPlayers
	if count ~= lastPlayerCount then
		lastPlayerCount = count
		vPlr.Text = tostring(count)
		buildPlayers()
	end
end)

vGame.Text = tostring(game.Name)
vPlace.Text = tostring(game.PlaceId)
local ok3, job = pcall(function()
	return tostring(game.JobId)
end)
vJob.Text = ok3 and job or "-"
local ok4, creator = pcall(function()
	return (game.Creator ~= nil and game.Creator.Name or "-")
end)
vCreator.Text = ok4 and creator or "-"
local ok5, genre = pcall(function()
	return tostring(game.Genre)
end)
vGenre.Text = ok5 and genre or "-"

buildPlayers()

local logLines = {}
local logCursor = 0
local maxShown = 350
local shownQueue = {}
local follow = true

local logColors = {
	[Enum.MessageType.Error] = C.Danger,
	[Enum.MessageType.Warning] = C.Warn,
	[Enum.MessageType.Info] = C.Dim,
	[Enum.MessageType.Output] = C.Txt,
}

local function appendLogLine(entry)
	local msg = tostring(entry.message or entry.Message or "")
	if #msg == 0 then return end
	local mtype = entry.messageType or entry.type or entry.MessageType or Enum.MessageType.Info

	if #shownQueue >= maxShown then
		local oldest = table.remove(shownQueue, 1)
		oldest:Destroy()
	end
	logEmpty.Visible = false

	local line = make(logContent, "TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = msg,
		TextColor3 = logColors[mtype] or C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 10,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = #shownQueue + 1,
		ClipsDescendants = true,
	})
	shownQueue[#shownQueue + 1] = line

	if follow then
		logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y + 64)
	end
end

local function tailConsole()
	local lines = LogService:GetLogHistory()
	local n = #lines
	if n <= logCursor then return end
	for i = logCursor + 1, n do
		local e = lines[i]
		logLines[#logLines + 1] = e
		appendLogLine(e)
	end
	logCursor = n
	if #logLines > 4000 then
		local excess = #logLines - 4000
		for _ = 1, excess do table.remove(logLines, 1) end
	end
end

clearBtn.MouseButton1Click:Connect(function()
	logLines = {}
	logCursor = #LogService:GetLogHistory()
	for _, l in ipairs(shownQueue) do l:Destroy() end
	shownQueue = {}
	logEmpty.Visible = true
	log("CONSOLE // CLEARED", true)
end)

local function copyText(text)
	local ok = false
	pcall(function()
		if type(setclipboard) == "function" then
			setclipboard(text)
			ok = true
		end
	end)
	if not ok then
		pcall(function()
			game:GetService("Clipboard"):SetText(text)
			ok = true
		end)
	end
	return ok
end

copyBtn.MouseButton1Click:Connect(function()
	if #logLines == 0 then
		log("CONSOLE // NOTHING TO COPY", false)
		return
	end
	local parts = {}
	for _, e in ipairs(logLines) do
		parts[#parts + 1] = tostring(e.message or e.Message or "")
	end
	local text = table.concat(parts, "\n")
	if copyText(text) then
		log(string.format("CONSOLE // COPIED %d LINES", #logLines), true)
	else
		log("CONSOLE // CLIPBOARD NOT AVAILABLE", false)
	end
end)

tailConsole()

RunService.Heartbeat:Connect(tailConsole)

local DeboldDir = "Debold/scripts"

local function safe(fn, ...)
	return pcall(fn, ...)
end

local function ensureDir()
	safe(function()
		if not isfolder(DeboldDir) then
			makefolder(DeboldDir)
		end
	end)
end

local function scriptFiles()
	local out = {}
	ensureDir()
	local ok, files = safe(function()
		return listfiles(DeboldDir)
	end)
	if ok and files then
		for _, f in ipairs(files) do
			out[#out + 1] = f
		end
	end
	table.sort(out)
	return out
end

local function cleanName(f)
	local base = tostring(f):gsub("\\", "/")
	local idx = base:find("/[^/]*$")
	if idx then base = base:sub(idx + 1) end
	return base
end

local function executeScript(content, button)
	content = tostring(content)
	if #content == 0 then
		log("EMPTY SOURCE", false)
		return
	end
	local isUrl = content:match("^https?://")
	local ok, f = pcall(function()
		if isUrl then
			return loadstring(game:HttpGet(content, true))
		end
		return loadstring(content)
	end)
	if not ok then
		log("COMPILE ERROR // " .. tostring(f), false)
		return
	end
	if not f then
		log("INVALID CHUNK", false)
		return
	end
	local ok2, err = pcall(f)
	if ok2 then
		log(string.format("LOADED // %s", isUrl and "URL" or "CODE"), true)
		if button then
			button.TextColor3 = C.Accent
		end
	else
		log("RUNTIME ERROR // " .. tostring(err), false)
	end
end

local function refreshSaved()
	for _, child in ipairs(savedContent:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local files = scriptFiles()
	savedClear.Visible = #files == 0
	for _, f in ipairs(files) do
		local name = cleanName(f)
		local rowF = make(savedContent, "Frame", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.Panel,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		})
		corner(rowF, 7)
		make(rowF, "TextLabel", {
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -100, 0, 44),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = name,
			TextColor3 = C.Txt,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local runB = make(rowF, "TextButton", {
			Position = UDim2.new(1, -152, 0, 6),
			Size = UDim2.new(0, 68, 0, 32),
			BackgroundColor3 = C.Hover,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = "RUN",
			TextColor3 = C.Accent,
			TextSize = 10,
		})
		corner(runB, 5)
		local delB = make(rowF, "TextButton", {
			Position = UDim2.new(1, -80, 0, 6),
			Size = UDim2.new(0, 68, 0, 32),
			BackgroundColor3 = C.Hover,
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			Text = "DEL",
			TextColor3 = C.Danger,
			TextSize = 10,
		})
		corner(delB, 5)
		runB.MouseButton1Click:Connect(function()
			local ok, content = safe(function()
				return readfile(f)
			end)
			if not ok then
				log("READ FAILED // " .. tostring(content), false)
				return
			end
			executeScript(content, runB)
		end)
		delB.MouseButton1Click:Connect(function()
			safe(function()
				delfile(f)
			end)
			refreshSaved()
			log("DELETED // " .. name, true)
		end)
	end
end

runBtn.MouseButton1Click:Connect(function()
	local content = srcBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if #content == 0 then
		log("ENTER A URL OR CODE", false)
		return
	end
	executeScript(content, runBtn)
end)

saveBtn.MouseButton1Click:Connect(function()
	local content = srcBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local name = nameBox.Text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #content == 0 then
		log("ENTER A URL OR CODE", false)
		return
	end
	if #name == 0 then
		log("NAME REQUIRED", false)
		return
	end
	name = name:gsub("[^%w%-. ]", ""):gsub("[^%w%- ]", "-")
	if #name == 0 then name = "script" end
	ensureDir()
	local ok, err = safe(function()
		writefile(DeboldDir .. "/" .. name .. ".txt", content)
	end)
	if not ok then
		log("SAVE FAILED // " .. tostring(err), false)
		return
	end
	srcBox.Text = ""
	nameBox.Text = ""
	refreshSaved()
	log("SAVED // " .. name, true)
end)

refreshSaved()
setTab(tabDebug)
log("DEBOLD // READY", true)