--!nonstrict
-- Synapse-lite drag window, Delta-executor-safe, declarative. ~24 lines (+marker).
local Players, Tween, UIS = game:GetService("Players"), game:GetService("TweenService"), game:GetService("UserInputService")
local lpg = Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.ResetOnSpawn = true, false
screen.Parent = lpg
local win = Instance.new("Frame")
win.BackgroundColor3, win.BackgroundTransparency, win.BorderSizePixel = Color3.fromRGB(27, 27, 30), 0.05, 0
win.Size, win.Position = UDim2.fromOffset(508, 420), UDim2.new(0.5, -254, 0.4, -210)
win.Parent = screen
local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 10)
rc.Parent = win
local st = Instance.new("UIStroke")
st.Color, st.Thickness, st.Transparency = Color3.fromRGB(120, 116, 110), 1, 0.55
st.Parent = win
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 95, 70)) })
grad.Parent = win
local top = Instance.new("Frame")
top.BackgroundTransparency, top.BorderSizePixel = 1, 0
top.Size, top.Position = UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0)
top.Parent = win
local title = Instance.new("TextLabel")
title.BackgroundTransparency, title.Text = 1, "groovyrey · steal lane"
title.TextColor3, title.Font, title.TextSize = Color3.fromRGB(238, 238, 238), Enum.Font.GothamBold, 15
title.Position, title.Size = UDim2.new(0, 14, 0, 9), UDim2.new(0, 220, 0, 20)
title.Parent = top
local dragOffset
top.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then dragOffset = i.Position - win.AbsolutePosition end
end)
top.InputChanged:Connect(function(i)
	if dragOffset and i.UserInputType == Enum.UserInputType.MouseMovement then
		win.Position = UDim2.fromOffset(i.Position.X - dragOffset.X, i.Position.Y - dragOffset.Y)
	end
end)
top.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then dragOffset = nil end
end)
local line = Instance.new("Frame")
line.BackgroundColor3, line.BorderSizePixel, line.Size = Color3.fromRGB(80, 72, 60), 0, UDim2.new(1, -28, 0, 1)
line.Position = UDim2.new(0, 14, 0, 38)
line.Parent = win
local label = Instance.new("TextLabel")
label.BackgroundTransparency, label.Text = 1, "Auto-carry detection"
label.TextColor3, label.Font, label.TextSize = Color3.fromRGB(210, 210, 210), Enum.Font.Gotham, 13
label.Position, label.Size = UDim2.new(0, 16, 0, 64), UDim2.new(0, 200, 0, 22)
label.Parent = win
local knobRow = Instance.new("Frame")
knobRow.BackgroundTransparency, knobRow.BorderSizePixel, knobRow.Size = 1, 0, UDim2.new(1, -32, 0, 34)
knobRow.Position = UDim2.new(0, 16, 0, 90)
knobRow.Parent = win
local knob = Instance.new("TextButton")
knob.BackgroundColor3, knob.AutoButtonColor, knob.Text = Color3.fromRGB(255, 190, 80), false, "  OFF"
knob.TextColor3, knob.Font, knob.TextSize = Color3.fromRGB(20, 20, 20), Enum.Font.GothamBold, 13
knob.Size, knob.Position = UDim2.new(0, 130, 0, 34), UDim2.new(0, 0, 0, 0)
knob.Parent = knobRow
local on = false
knob.MouseButton1Click:Connect(function()
	on = not on
	knob.BackgroundColor3, knob.Text = on and Color3.fromRGB(120, 210, 120) or Color3.fromRGB(255, 190, 80), on and "  ON" or "  OFF"
end)
local footer = Instance.new("TextLabel")
footer.BackgroundTransparency, footer.Text = 1, "server keeps guard motion; toll lane is the sanctioned return"
footer.TextColor3, footer.Font, footer.TextSize = Color3.fromRGB(140, 140, 150), Enum.Font.Gotham, 11
footer.Position, footer.Size = UDim2.new(0, 16, 0, 374), UDim2.new(0, 476, 0, 20)
footer.Parent = win
local okM, errM = pcall(function()
	writefile("pasteUImarker.txt", "armed " .. tostring(os.time()))
end)
print("[pasteUI] armed (marker " .. tostring(okM) .. ")" .. (okM and "" or " err=" .. tostring(errM)))