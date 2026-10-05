-- Licarsware // Target info overlay (port of vape's TargetInfo)
-- 240x89 card: avatar headshot + name (drop shadow) + pill health bar that
-- shifts green->red as health drops, hurt flash on damage. Draggable.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')

local Theme = script.Parent.Theme

local TargetInfo = {}

local LocalPlayer = Players.LocalPlayer

local gui = Instance.new('ScreenGui')
gui.Name = 'Licarsware.TargetInfo'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99997
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local parented = pcall(function()
	gui.Parent = LocalPlayer:WaitForChild('PlayerGui')
end)
if not parented then gui.Parent = game:GetService('CoreGui') end

local holder = Instance.new('Frame')
holder.Size = UDim2.fromOffset(240, 89)
holder.Position = UDim2.new(0.5, -120, 1, -320)
holder.BackgroundColor3 = Theme.dark(Theme.Get().Main, 0.1)
holder.BackgroundTransparency = 0.5
holder.Visible = false
holder.Parent = gui
Instance.new('UICorner', holder).CornerRadius = UDim.new(0, 5)

local shadow = Instance.new('UIShadow')
shadow.BlurRadius = UDim.new(0, 13)
shadow.Transparency = 0.25
shadow.Parent = holder

-- headshot (vape uses rbxthumb; falls back gracefully if blocked)
local headshot = Instance.new('ImageLabel')
headshot.Size = UDim2.fromOffset(26, 27)
headshot.Position = UDim2.fromOffset(19, 17)
headshot.BackgroundColor3 = Theme.Get().Main
headshot.Image = 'rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420'
headshot.Parent = holder
Instance.new('UICorner', headshot).CornerRadius = UDim.new(1, 0)

local hurtFlash = Instance.new('Frame')
hurtFlash.Size = UDim2.fromScale(1, 1)
hurtFlash.BackgroundTransparency = 1
hurtFlash.BackgroundColor3 = Color3.new(1, 0, 0)
hurtFlash.Parent = headshot
Instance.new('UICorner', hurtFlash).CornerRadius = UDim.new(1, 0)

local name = Instance.new('TextLabel')
name.Size = UDim2.fromOffset(145, 20)
name.Position = UDim2.fromOffset(54, 20)
name.BackgroundTransparency = 1
name.Text = 'Target name'
name.TextXAlignment = Enum.TextXAlignment.Left
name.TextYAlignment = Enum.TextYAlignment.Top
name.TextScaled = true
name.TextColor3 = Theme.light(Theme.Get().Text, 0.4)
name.TextStrokeTransparency = 1
name.Font = Enum.Font.Arial
name.Parent = holder

local nameShadow = name:Clone()
nameShadow.Position = UDim2.fromOffset(55, 21)
nameShadow.TextColor3 = Color3.new()
nameShadow.TextTransparency = 0.65
nameShadow.Parent = holder

local healthBkg = Instance.new('Frame')
healthBkg.Size = UDim2.fromOffset(200, 9)
healthBkg.Position = UDim2.fromOffset(20, 56)
healthBkg.BackgroundColor3 = Theme.Get().Main
healthBkg.BorderSizePixel = 0
healthBkg.Parent = holder
Instance.new('UICorner', healthBkg).CornerRadius = UDim.new(1, 0)

local healthFill = Instance.new('Frame')
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BackgroundColor3 = Color3.fromHSV(0.4, 0.89, 0.75)
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBkg
Instance.new('UICorner', healthFill).CornerRadius = UDim.new(1, 0)

-- drag (whole card, it's small)	do
	local dragging, dragStart, startPos
	holder.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = holder.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	local uis = game:GetService('UserInputService')
	uis.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- ============ state ============
local current = nil -- { player, humanoid, lastHealth }
local hideAt = nil -- os.clock() when to hide after target lost

-- theme restyle
Theme.OnChanged(function(t)
	holder.BackgroundColor3 = Theme.dark(t.Main, 0.1)
	headshot.BackgroundColor3 = t.Main
	name.TextColor3 = Theme.light(t.Text, 0.4)
	healthBkg.BackgroundColor3 = t.Main
end)

-- ============ update loop ============
local loopConn
loopConn = RunService.RenderStepped:Connect(function()
	if not holder.Parent then
		loopConn:Disconnect() -- self-destructed GUI: let the connection die
		return
	end

	-- linger then hide after the target is gone
	if not current and hideAt and os.clock() > hideAt then
		holder.Visible = false
		hideAt = nil
		return
	end
	if not current or not holder.Visible then return end

	local hum = current.humanoid
	if not hum or not hum.Parent then
		TargetInfo.Clear()
		return
	end

	local health = hum.Health
	local maxHealth = math.max(hum.MaxHealth, 1)

	if math.abs(health - current.lastHealth) > 0.01 then
		local percent = math.clamp(health / maxHealth, 0, 1)

		-- vape's hue mapping: full health = green (0.4), dead = red (0)
		TweenService:Create(healthFill, TweenInfo.new(0.3), {
			Size = UDim2.fromScale(percent, 1),
			BackgroundColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.89, 0.75),
		}):Play()

		-- hurt flash when damaged
		if health < current.lastHealth then
			TweenService:Create(hurtFlash, TweenInfo.new(0.05), { BackgroundTransparency = 0.3 }):Play()
			task.delay(0.06, function()
				if hurtFlash.Parent then
					TweenService:Create(hurtFlash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				end
			end)
		end

		current.lastHealth = health
	end
end)

-- ============ API ============
function TargetInfo.SetTarget(player, humanoid)
	if not player then return end

	if not current or current.player ~= player then
		name.Text = player.DisplayName
		nameShadow.Text = name.Text
		headshot.Image = ('rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420'):format(player.UserId)
		healthFill.Size = UDim2.fromScale(1, 1)
	end

	current = { player = player, humanoid = humanoid, lastHealth = humanoid and humanoid.Health or 100 }
	hideAt = nil
	holder.Visible = true
end

function TargetInfo.Clear()
	if current then
		current = nil
		hideAt = os.clock() + 1.2 -- short linger so flicker targets don't blink the card
	end
end

function TargetInfo.Unload()
	if loopConn then loopConn:Disconnect() end
	gui:Destroy()
end

return TargetInfo
