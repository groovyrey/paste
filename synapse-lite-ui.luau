--!nonstrict
-- Steal-lane aide · minimalist editorial bento. Executor-safe (Delta), mobile-aware.
local Players, Tween, UIS = game:GetService("Players"), game:GetService("TweenService"), game:GetService("UserInputService")
local lpg = Players.LocalPlayer:WaitForChild("PlayerGui")
local cvp = workspace.CurrentCamera.ViewportSize
local sc = math.max(0.72, math.min(1, (cvp.X - 32) / 352, (cvp.Y - 120) / 462))
local serif, body, mono = Enum.Font.Fraunces, Enum.Font.Gotham, Enum.Font.Code
local bone, paper, ink, mut, lineC = Color3.fromRGB(247, 246, 243), Color3.fromRGB(255, 255, 255), Color3.fromRGB(25, 25, 24), Color3.fromRGB(120, 119, 116), Color3.fromRGB(234, 234, 234)
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.ResetOnSpawn = true, false
screen.Parent = lpg
local win = Instance.new("Frame")
win.BackgroundColor3, win.BorderSizePixel = bone, 0
win.Size, win.Position = UDim2.fromOffset(352 * sc, 462 * sc), UDim2.new(0.5, -176 * sc, 0.45, -231 * sc)
win.Parent = screen
local head = Instance.new("TextLabel")
head.BackgroundTransparency, head.Text, head.TextColor3, head.Font = 1, "GROOVYREY / STEAL PASTE", mut, mono
head.TextSize, head.Position, head.Size = math.clamp(9 * sc, 7, 11), UDim2.new(0, 18, 0, 11), UDim2.new(0, 240, 0, 14)
head.Parent = win
local title = Instance.new("TextLabel")
title.BackgroundTransparency, title.Text, title.TextColor3, title.Font = 1, "Steal lane", ink, serif
title.TextSize, title.Position, title.Size = math.clamp(28 * sc, 18, 30), UDim2.new(0, 18, 0, 30), UDim2.new(0, 220, 0, 40)
title.Parent = win
local cap1 = Instance.new("TextLabel")
cap1.BackgroundTransparency, cap1.Text, cap1.TextColor3, cap1.Font = 1, "Live lane-state, arm and we escort you home at guard pace.", mut, body
cap1.TextSize, cap1.TextWrapped, cap1.Position, cap1.Size = math.clamp(11 * sc, 9, 12), true, UDim2.new(0, 18, 0, 84), UDim2.new(0, 300, 0, 34)
cap1.Parent = win
local dragOff
local top = Instance.new("Frame")
top.BackgroundTransparency, top.BorderSizePixel, top.Size = 1, 0, UDim2.new(1, 0, 0, 40)
top.Parent = win
top.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragOff = i.Position - win.AbsolutePosition end
end)
top.InputChanged:Connect(function(i)
	if dragOff and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		win.Position = UDim2.fromOffset(i.Position.X - dragOff.X, i.Position.Y - dragOff.Y)
	end
end)
top.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragOff = nil end
end)
local function lbl(props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	for k, v in pairs(props) do t[k] = v end
	t.Parent = win
	return t
end
local function card(x, y, w, h)
	local c = Instance.new("Frame")
	c.BackgroundColor3, c.BorderSizePixel = paper, 0
	c.Position, c.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
	c.Parent = win
	local k = Instance.new("UICorner")
	k.CornerRadius, k.Parent = UDim.new(0, 8), c
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Parent = lineC, 1, c
	return c
end
local a = card(math.round(18 * sc), math.round(140 * sc), math.round(198 * sc), math.round(124 * sc))
local b = card(math.round(224 * sc), math.round(140 * sc), math.round(110 * sc), math.round(124 * sc))
lbl{ Text = "Carry signal", TextColor3 = mut, Font = mono, TextSize = math.clamp(9 * sc, 7, 10), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 18, 0, 16), Size = UDim2.new(0, 150, 0, 14) }
local big = Instance.new("TextLabel")
big.Parent = a
big.BackgroundTransparency, big.Text, big.TextColor3, big.Font = 1, "0", ink, serif
big.TextSize, big.Position, big.Size = math.clamp(40 * sc, 24, 42), UDim2.new(0, 20, 0, 62), UDim2.new(0, 60, 0, 46)
local stl = Instance.new("TextLabel")
stl.BackgroundTransparency, stl.Text, stl.TextColor3, stl.Font = 1, "IDLE", mut, mono
stl.TextSize, stl.TextXAlignment, stl.Position, stl.Size = math.clamp(9 * sc, 7, 10), Enum.TextXAlignment.Left, UDim2.new(0, 18, 0, 92), UDim2.new(0, 90, 0, 14)
stl.Parent = a
local stt = Instance.new("TextLabel")
stt.BackgroundTransparency, stt.Text, stt.TextColor3, stt.Font = 1, "State", mut, body
stt.TextSize, stt.TextXAlignment, stt.Position, stt.Size = math.clamp(10 * sc, 8, 11), Enum.TextXAlignment.Left, UDim2.new(0, 22, 0, 44), UDim2.new(0, 140, 0, 14)
stt.Parent = a
lbl{ Text = "Escort", TextColor3 = mut, Font = body, TextSize = math.clamp(10 * sc, 8, 11), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 16, 0, 104), Size = UDim2.new(0, 90, 0, 14) }
lbl{ Text = "SpeedToll\194\183Lane", TextColor3 = ink, Font = serif, TextSize = math.clamp(15 * sc, 11, 16), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 98, 0, 142), Size = UDim2.new(0, 150, 0, 22) }
lbl{ Text = "return", TextColor3 = mut, Font = body, TextSize = math.clamp(10 * sc, 8, 11), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 68, 0, 25), Size = UDim2.new(0, 130, 0, 14) }
lbl{ Text = "38\194\176", TextColor3 = ink, Font = serif, TextSize = math.clamp(24 * sc, 15, 26), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 14, 0, 48), Size = UDim2.new(0, 90, 0, 28) }
local arm = Instance.new("TextButton")
arm.BackgroundColor3, arm.Text, arm.TextColor3 = ink, "ARM \226\128\148 notify on carry", Color3.fromRGB(250, 250, 249)
arm.Font, arm.TextSize = body, math.clamp(11 * sc, 9, 12)
arm.Position, arm.Size = UDim2.new(0, 18, 0, 300), UDim2.new(1, -36, 0, 54)
arm.Parent = win
local amid = Instance.new("UICorner")
amid.CornerRadius, amid.Parent = UDim.new(0, 6), arm
local armed = false
arm.MouseButton1Click:Connect(function()
	armed = not armed
	if armed then
		arm.BackgroundColor3, arm.Text = Color3.fromRGB(52, 143, 115), "ARMED \226\128\148 carry will notify"
		big.Text, stl.Text = "1", "CARRY"
		pcall(writefile, "pasteUI_carry.txt", "armed " .. tostring(os.time()))
	else
		arm.BackgroundColor3, arm.Text = ink, "ARM \226\128\148 notify on carry"
		big.Text, stl.Text = "0", "IDLE"
		pcall(writefile, "pasteUI_carry.txt", "idle " .. tostring(os.time()))
	end
end)
lbl{ Text = "Server-authoritative lane-state \226\128\148 the only return that sticks.", TextColor3 = mut, Font = body, TextSize = math.clamp(10 * sc, 8, 11), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 18, 0, 374), Size = UDim2.new(0, 300, 0, 30) }
lbl{ Text = "marker \226\134\146 /files/pasteUI_carry.txt", TextColor3 = mut, Font = mono, TextSize = math.clamp(8 * sc, 6, 9), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 18, 0, 406), Size = UDim2.new(0, 300, 0, 14) }