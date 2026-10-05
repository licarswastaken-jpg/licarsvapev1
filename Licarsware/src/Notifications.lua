-- Licarsware // Notifications
-- Pixel-faithful port of vape:CreateNotification: bottom-right stack, slide in
-- from the right edge, text-stroke title, muted body, 1px depleting progress bar.

local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

local Theme = script.Parent.Theme

local gui = Instance.new('ScreenGui')
gui.Name = 'Licarsware.Notifications'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100000
local ok = pcall(function()
	gui.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')
end)
if not ok then gui.Parent = game:GetService('CoreGui') end

local notifications = Instance.new('Folder')
notifications.Name = 'Notifications'
notifications.Parent = gui

local TW = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

local function slideTo(frame, index)
	TweenService:Create(frame, TW, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 1, -(29 + (78 * index))),
	}):Play()
end

local Notifications = {}

-- Notifications.Show(title, body, type, duration)
-- type: 'info' | 'alert' | 'warning' | 'success'
function Notifications.Show(title, body, kind, duration)
	duration = duration or 4

	if not gui.Parent then return end -- self-destructed: drop late toasts silently

	local frame = Instance.new('Frame')
	frame.BackgroundColor3 = Theme.Get().Main
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0, 0) -- starts offscreen right, like vape
	frame.Position = UDim2.new(1, 0, 1, -(29 + (78 * (#notifications:GetChildren() + 1))))
	frame.Size = UDim2.fromOffset(290, 75)
	frame.Parent = notifications
	Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 5)

	local shadow = Instance.new('UIShadow')
	shadow.BlurRadius = UDim.new(0, 13)
	shadow.Transparency = 0.25
	shadow.Parent = frame

	local stroke = Instance.new('UIStroke')
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Get().Stroke
	stroke.Transparency = 0.8
	stroke.Parent = frame

	-- icon disc (vape uses a 60px icon image with shadow; disc keeps it asset-free)
	local icon = Instance.new('Frame')
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundColor3 = kind == 'alert' and Theme.Get().Error
		or kind == 'warning' and Theme.Get().Warning
		or kind == 'success' and Theme.Get().Success
		or Theme.Get().Accent
	icon.BackgroundTransparency = kind == 'info' and 0.2 or 0
	icon.BorderSizePixel = 0
	icon.Position = UDim2.fromOffset(28, 34)
	icon.Size = UDim2.fromOffset(26, 26)
	icon.Parent = frame
	Instance.new('UICorner', icon).CornerRadius = UDim.new(1, 0)

	local glyph = Instance.new('TextLabel')
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.GothamBold
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = kind == 'alert' and '!' or kind == 'warning' and '!' or kind == 'success' and '✓' or 'i'
	glyph.TextColor3 = Color3.new(1, 1, 1)
	glyph.TextSize = 14
	glyph.Parent = icon

	-- title with text stroke (vape style)
	local label = Instance.new('TextLabel')
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Position = UDim2.fromOffset(48, 12)
	label.RichText = true
	label.Size = UDim2.new(1, -58, 0, 20)
	label.Text = title
	label.TextColor3 = kind == 'alert' and Theme.Get().Error or Color3.new(1, 1, 1)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = frame

	local titleStroke = Instance.new('UIStroke')
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Color = Color3.new(0, 0, 0)
	titleStroke.Thickness = 0.6
	titleStroke.Transparency = 0.5
	titleStroke.Parent = label

	-- body (muted, like vape's RGB(170,170,170) with drop shadow)
	local bodyShadow = Instance.new('TextLabel')
	bodyShadow.BackgroundTransparency = 1
	bodyShadow.Font = Enum.Font.Gotham
	bodyShadow.Position = UDim2.fromOffset(49, 39)
	bodyShadow.Size = UDim2.new(1, -60, 0, 28)
	bodyShadow.Text = body
	bodyShadow.TextColor3 = Color3.new(0, 0, 0)
	bodyShadow.TextTransparency = 0.5
	bodyShadow.TextSize = 13
	bodyShadow.TextWrapped = true
	bodyShadow.TextXAlignment = Enum.TextXAlignment.Left
	bodyShadow.TextYAlignment = Enum.TextYAlignment.Top
	bodyShadow.Parent = frame

	local bodyLabel = bodyShadow:Clone()
	bodyLabel.Position = UDim2.fromOffset(48, 38)
	bodyLabel.TextColor3 = Theme.Get().NotifSub
	bodyLabel.TextTransparency = 0
	bodyLabel.Parent = bodyShadow

	-- 1px depleting progress bar, exactly like vape
	local progress = Instance.new('Frame')
	progress.BackgroundColor3 = kind == 'alert' and Theme.Get().Error
		or kind == 'warning' and Theme.Get().Warning
		or kind == 'success' and Theme.Get().Success
		or Color3.new(1, 1, 1)
	progress.BorderSizePixel = 0
	progress.Position = UDim2.new(0, 3, 1, -4)
	progress.Size = UDim2.new(1, -13, 0, 1)
	progress.Parent = frame

	-- theme restyle
	Theme.OnChanged(function(t)
		frame.BackgroundColor3 = t.Main
		stroke.Color = t.Stroke
		label.TextColor3 = kind == 'alert' and t.Error or Color3.new(1, 1, 1)
		bodyLabel.TextColor3 = t.NotifSub
	end)

	-- slide in from right edge
	slideTo(frame, #notifications:GetChildren())
	TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromOffset(0, 1),
	}):Play()

	task.delay(duration, function()
		-- slide back out, then destroy (stack re-tweens on ChildRemoved)
		TweenService:Create(frame, TW, {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(1, 0, frame.Position.Y.Scale, frame.Position.Y.Offset),
		}):Play()
		task.wait(0.35)
		frame:Destroy()
	end)

	return frame
end

notifications.ChildRemoved:Connect(function()
	for index, notif in ipairs(notifications:GetChildren()) do
		slideTo(notif, index)
	end
end)

function Notifications.Injected(executorName)
	Notifications.Show('Injected', 'licarsware loaded successfully • ' .. (executorName or 'executor'), 'success', 5)
end

return Notifications
