--!nonstrict
-- Synapse-lite declarative window, ~20 statements. Delta/executor-safe (no deps, no syn).
local Tween, UIS = game:GetService("TweenService"), game:GetService("UserInputService")
local lpg, Pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"), ReplicatedStorage.Packages
local RotJs = require(lpg.Parent.Packages:WaitForChild("Networking", 30) and game:GetService("ReplicatedStorage").Packages.Networking)
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.ResetOnSpawn, screen.ZIndexBehavior = true, false, Enum.ZIndexBehavior.Sibling
screen.Parent = lpg
local Canvas = Instance.new("CanvasGroup") -- fold
Canvas.GroupTransparency, Canvas.Size, Canvas.Anchored, Canvas.Position, Canvas.BackgroundTransparency = 0, UDim2.new(0, 500, 0, 324), true, UDim2.new(0.3515, 0, 0.3123, 0), 1
Canvas.Parent = screen
local bg = Instance.new("Frame")
bg.BorderSizePixel, bg.BackgroundColor3, bg.Active, bg.Size = 0, Color3.fromRGB(27, 27, 30), true, UDim2.new(1, 0, 1, 0)
bg.Parent = Canvas
local uic = Instance.new("UICorner")
uic.CornerRadius = UDim.new(0, 8)
uic.Parent = bg
local drag = Instance.new("Frame")
drag.Size, drag.BackgroundTransparency, drag.ZIndex = UDim2.new(1, 0, 0, 32), 1, 8
drag.Parent = bg
local dragOffset; drag.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragOffset = i.Position - Canvas.AbsolutePosition end end)
drag.InputChanged:Connect(function(i) if dragOffset and i.UserInputType == Enum.UserInputType.MouseMovement then Canvas.Position = UDim2.fromOffset(i.Position.X - dragOffset.X, i.Position.Y - dragOffset.Y) end end)
drag.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragOffset = nil end end)
local bar = Instance.new("Frame")
bar.BackgroundColor3, bar.BorderSizePixel, bar.Rotation, bar.AnchorPoint = Color3.fromRGB(255, 219, 88), 0, 6, Vector2.new(0.5, 0.5)
bar.Size, bar.Position, bar.ZIndex = UDim2.new( rent= 0.86, 0, 0, 4), UDim2.new(0.5, 0, 0, 0), 2
bar.Parent = bg
