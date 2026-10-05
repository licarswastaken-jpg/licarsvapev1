-- Licarsware // real game modules
-- Every module follows the same contract:
--   Enable()   -> applies + hooks (idempotent)
--   Disable()  -> disconnects + RESTORES original game state
--   SetValue/Configure -> live option updates
-- Restore-on-disable matters: unloading must leave the game untouched.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local Lighting = game:GetService('Lighting')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local TeleportService = game:GetService('TeleportService')
-- fail-soft: some executors block these services; AntiAFK/KillAura lose the
-- fallback instead of the whole module table erroring at load
local okVU, VirtualUser = pcall(game.GetService, game, 'VirtualUser')
VirtualUser = okVU and VirtualUser or nil
local okVIM, VirtualInputManager = pcall(game.GetService, game, 'VirtualInputManager')
VirtualInputManager = okVIM and VirtualInputManager or nil

local Modules = {}
local LocalPlayer = Players.LocalPlayer

-- Target info overlay is injected into Modules.TargetInfo by Main.Load
-- (loaded after this file, so we read it off the registry at call time — no require cycle)

local function getHumanoid()
	local char = LocalPlayer.Character
	return char and char:FindFirstChildOfClass('Humanoid')
end

-- wait for a humanoid (used on respawn)
local function waitForHumanoid(char)
	return char:WaitForChild('Humanoid', 5)
end

-- ============================================================
-- Speed (WalkSpeed enforcement, survives respawn)
-- ============================================================
local Speed = { enabled = false, value = 16, conns = {}, original = 16 }

local function speedApply()
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = Speed.value end
end

function Speed.Enable()
	if Speed.enabled then return end
	Speed.enabled = true
	local hum = getHumanoid()
	Speed.original = hum and hum.WalkSpeed or 16
	speedApply()
	table.insert(Speed.conns, RunService.Heartbeat:Connect(function()
		local h = getHumanoid()
		if h and h.WalkSpeed ~= Speed.value then
			h.WalkSpeed = Speed.value -- re-assert: games reset WalkSpeed constantly
		end
	end))
	table.insert(Speed.conns, LocalPlayer.CharacterAdded:Connect(function(char)
		local h = waitForHumanoid(char)
		if h and Speed.enabled then h.WalkSpeed = Speed.value end
	end))
end

function Speed.Disable()
	if not Speed.enabled then return end
	Speed.enabled = false
	for _, c in ipairs(Speed.conns) do c:Disconnect() end
	table.clear(Speed.conns)
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = Speed.original end
end

function Speed.SetValue(v)
	Speed.value = v
	if Speed.enabled then speedApply() end
end
Modules.Speed = Speed

-- ============================================================
-- High jump (JumpPower / JumpHeight depending on game settings)
-- ============================================================
local HighJump = { enabled = false, value = 50, conns = {}, originalPower = 50, originalHeight = 7.2 }

local function jumpApply()
	local hum = getHumanoid()
	if not hum then return end
	if hum.UseJumpPower then
		hum.JumpPower = HighJump.value
	else
		hum.JumpHeight = HighJump.value * 0.264 -- studs->height approximation consistent with Roblox formula
	end
end

function HighJump.Enable()
	if HighJump.enabled then return end
	HighJump.enabled = true
	local hum = getHumanoid()
	if hum then
		HighJump.originalPower = hum.JumpPower
		HighJump.originalHeight = hum.JumpHeight
	end
	jumpApply()
	table.insert(HighJump.conns, LocalPlayer.CharacterAdded:Connect(function(char)
		local h = waitForHumanoid(char)
		if h and HighJump.enabled then
			if h.UseJumpPower then h.JumpPower = HighJump.value else h.JumpHeight = HighJump.value * 0.264 end
		end
	end))
end

function HighJump.Disable()
	if not HighJump.enabled then return end
	HighJump.enabled = false
	for _, c in ipairs(HighJump.conns) do c:Disconnect() end
	table.clear(HighJump.conns)
	local hum = getHumanoid()
	if hum then
		hum.JumpPower = HighJump.originalPower
		hum.JumpHeight = HighJump.originalHeight
	end
end

function HighJump.SetValue(v)
	HighJump.value = v
	if HighJump.enabled then jumpApply() end
end
Modules.HighJump = HighJump

-- ============================================================
-- Infinite jump (JumpRequest -> rejump)
-- ============================================================
local InfJump = { enabled = false, conn = nil }

function InfJump.Enable()
	if InfJump.enabled then return end
	InfJump.enabled = true
	InfJump.conn = UserInputService.JumpRequest:Connect(function()
		if not InfJump.enabled then return end
		local hum = getHumanoid()
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

function InfJump.Disable()
	if not InfJump.enabled then return end
	InfJump.enabled = false
	if InfJump.conn then InfJump.conn:Disconnect(); InfJump.conn = nil end
end
Modules.InfiniteJump = InfJump

-- ============================================================
-- Noclip (per-part CanCollide with restore map)
-- ============================================================
local Noclip = { enabled = false, conns = {}, restore = {} }

local function noclipApply(char)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA('BasePart') and Noclip.restore[part] == nil then
			Noclip.restore[part] = part.CanCollide
			part.CanCollide = false
		end
	end
end

function Noclip.Enable()
	if Noclip.enabled then return end
	Noclip.enabled = true
	table.clear(Noclip.restore)
	if LocalPlayer.Character then noclipApply(LocalPlayer.Character) end
	table.insert(Noclip.conns, RunService.Heartbeat:Connect(function()
		local char = LocalPlayer.Character
		if char then noclipApply(char) end
	end))
	table.insert(Noclip.conns, LocalPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5) -- let the map finish loading the new character
		table.clear(Noclip.restore)
		if Noclip.enabled and char.Parent then noclipApply(char) end
	end))
end

function Noclip.Disable()
	if not Noclip.enabled then return end
	Noclip.enabled = false
	for _, c in ipairs(Noclip.conns) do c:Disconnect() end
	table.clear(Noclip.conns)
	for part, original in pairs(Noclip.restore) do
		if part and part.Parent then pcall(function() part.CanCollide = original end) end
	end
	table.clear(Noclip.restore)
end
Modules.Noclip = Noclip

-- ============================================================
-- ESP (Highlight boxes + name/health billboards, team/rainbow colors)
-- ============================================================
local ESP = {
	enabled = false,
	conns = {},
	state = {}, -- player -> { highlight, name, health, fill }
	options = { boxes = true, names = true, health = false, color = 'Team' },
}

local function espColor(player, hue)
	local mode = ESP.options.color
	if mode == 'Rainbow' then
		return Color3.fromHSV(hue, 0.72, 1)
	elseif mode == 'Red' then
		return Color3.fromRGB(255, 64, 64)
	elseif mode == 'Green' then
		return Color3.fromRGB(64, 255, 106)
	elseif mode == 'Team' then
		return player.Team and player.Team.TeamColor.Color or Color3.fromRGB(255, 255, 255)
	end
	return Color3.fromRGB(255, 255, 255)
end

local function espClear(player)
	local s = ESP.state[player]
	if not s then return end
	if s.highlight then s.highlight:Destroy() end
	if s.name then s.name:Destroy() end
	if s.health then s.health:Destroy() end
	ESP.state[player] = nil
end

local function espBuild(player, hue)
	espClear(player)
	local char = player.Character
	if not char or not char.Parent then return end
	local head = char:FindFirstChild('Head') or char:FindFirstChildWhichIsA('BasePart')
	if not head then return end
	local color = espColor(player, hue)
	local s = { conns = {} }

	-- boxes: Highlight through walls
	local hl = Instance.new('Highlight')
	hl.Name = 'LW_ESP'
	hl.FillColor = color
	hl.OutlineColor = color
	hl.FillTransparency = ESP.options.boxes and 0.65 or 1
	hl.OutlineTransparency = ESP.options.boxes and 0 or 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = char
	s.highlight = hl

	-- name billboard
	if ESP.options.names then
		local bb = Instance.new('BillboardGui')
		bb.Name = 'LW_Name'
		bb.Adornee = head
		bb.Size = UDim2.new(0, 200, 0, 22)
		bb.StudsOffset = Vector3.new(0, 3.2, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 500
		local text = Instance.new('TextLabel')
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.Arial
		text.TextSize = 14
		text.TextStrokeTransparency = 0.4
		text.TextColor3 = color
		text.Text = player.DisplayName
		text.Parent = bb
		bb.Parent = char
		s.name = bb
		s.nameText = text
	end

	-- health bar billboard
	if ESP.options.health then
		local hum = char:FindFirstChildOfClass('Humanoid')
		local bb = Instance.new('BillboardGui')
		bb.Name = 'LW_Health'
		bb.Adornee = head
		bb.Size = UDim2.new(0, 100, 0, 7)
		bb.StudsOffset = Vector3.new(0, 2.8, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 500
		local bg = Instance.new('Frame')
		bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		bg.BackgroundTransparency = 0.25
		bg.BorderSizePixel = 0
		bg.Size = UDim2.fromScale(1, 1)
		bg.Parent = bb
		local fill = Instance.new('Frame')
		fill.BackgroundColor3 = Color3.fromRGB(64, 255, 106)
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = bg
		bb.Parent = char
		s.health = bb
		s.healthFill = fill
		s.humanoid = hum
	end

	-- rebuild this player's esp on respawn while enabled
	table.insert(s.conns, player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if ESP.enabled then espBuild(player, 0) end
	end))

	ESP.state[player] = s
end

function ESP.Configure(opts)
	for k, v in pairs(opts) do ESP.options[k] = v end
	if ESP.enabled then ESP.Refresh() end
end

function ESP.Refresh()
	local hue = 0
	for player in pairs(ESP.state) do
		espClear(player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			espBuild(player, hue)
			hue += 0.13
		end
	end
end

function ESP.Enable()
	if ESP.enabled then return end
	ESP.enabled = true

	ESP.Refresh()

	table.insert(ESP.conns, Players.PlayerAdded:Connect(function(p)
		if ESP.enabled then espBuild(p, 0) end
	end))
	table.insert(ESP.conns, Players.PlayerRemoving:Connect(function(p)
		espClear(p)
	end))
	table.insert(ESP.conns, RunService.Heartbeat:Connect(function()
		-- rainbow hue + live health bars, both need per-frame updates
		local hue = (os.clock() * 0.35) % 1
		for player, s in pairs(ESP.state) do
			if s.highlight and ESP.options.color == 'Rainbow' then
				local c = Color3.fromHSV(hue, 0.72, 1)
				s.highlight.FillColor = c
				s.highlight.OutlineColor = c
			end
			if s.healthFill and s.humanoid then
				local alpha = math.clamp(s.humanoid.Health / math.max(s.humanoid.MaxHealth, 1), 0, 1)
				s.healthFill.Size = UDim2.fromScale(alpha, 1)
				s.healthFill.BackgroundColor3 = Color3.fromRGB(255 * (1 - alpha), 255 * alpha, 64)
			end
			if s.nameText and ESP.options.color ~= 'Team' then
				s.nameText.TextColor3 = espColor(player, hue)
			end
		end
	end))
end

function ESP.Disable()
	if not ESP.enabled then return end
	ESP.enabled = false
	for _, c in ipairs(ESP.conns) do c:Disconnect() end
	table.clear(ESP.conns)
	for player in pairs(ESP.state) do
		espClear(player)
	end
	table.clear(ESP.state)
end
Modules.ESP = ESP

-- ============================================================
-- Fullbright (capture + restore Lighting)
-- ============================================================
local Fullbright = { enabled = false, conns = {}, saved = nil }

function Fullbright.Enable()
	if Fullbright.enabled then return end
	Fullbright.enabled = true
	Fullbright.saved = {
		Ambient = Lighting.Ambient,
		Brightness = Lighting.Brightness,
		ColorShift_Top = Lighting.ColorShift_Top,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local function apply()
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.Brightness = 3
		Lighting.ColorShift_Top = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	end
	apply()
	table.insert(Fullbright.conns, RunService.Heartbeat:Connect(apply)) -- re-assert: games fight back
end

function Fullbright.Disable()
	if not Fullbright.enabled then return end
	Fullbright.enabled = false
	for _, c in ipairs(Fullbright.conns) do c:Disconnect() end
	table.clear(Fullbright.conns)
	if Fullbright.saved then
		for k, v in pairs(Fullbright.saved) do
			pcall(function() Lighting[k] = v end)
		end
	end
end
Modules.Fullbright = Fullbright

-- ============================================================
-- No fog
-- ============================================================
local NoFog = { enabled = false, conns = {}, saved = nil }

function NoFog.Enable()
	if NoFog.enabled then return end
	NoFog.enabled = true
	NoFog.saved = { FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, FogColor = Lighting.FogColor }
	local function apply()
		Lighting.FogEnd = 1e6
		Lighting.FogStart = 1e6
	end
	apply()
	table.insert(NoFog.conns, RunService.Heartbeat:Connect(apply))
end

function NoFog.Disable()
	if not NoFog.enabled then return end
	NoFog.enabled = false
	for _, c in ipairs(NoFog.conns) do c:Disconnect() end
	table.clear(NoFog.conns)
	if NoFog.saved then
		for k, v in pairs(NoFog.saved) do
			pcall(function() Lighting[k] = v end)
		end
	end
end
Modules.NoFog = NoFog

-- ============================================================
-- Anti AFK (VirtualUser idled capture)
-- ============================================================
local AntiAFK = { enabled = false, conn = nil }

function AntiAFK.Enable()
	if AntiAFK.enabled then return end
	AntiAFK.enabled = true
	if not VirtualUser then return end -- executor blocked it; module no-ops safely
	AntiAFK.conn = LocalPlayer.Idled:Connect(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end

function AntiAFK.Disable()
	if not AntiAFK.enabled then return end
	AntiAFK.enabled = false
	if AntiAFK.conn then AntiAFK.conn:Disconnect(); AntiAFK.conn = nil end
end
Modules.AntiAFK = AntiAFK

-- ============================================================
-- Kill aura (auto-attack nearest valid target with equipped tool)
-- Targeting: Closest | Lowest HP | Random. Team check, facing so
-- facing-based hit detection accepts swings, click fallback.
-- ============================================================
local KillAura = {
	enabled = false,
	conns = {},		options = {
		targetRange = 12, -- scan/aim range (max 25, closet cap 18)
		attackRange = 6,  -- actual swing distance: target must be THIS close
		closetMode = false, -- Closet cheat preset: ranges hard-capped at 18
		mode = 'Closest',
		teamCheck = true,
		facing = true,
		autoEquip = true,
		clickDelay = 0.35, -- seconds between swings
	},
	_nextSwing = 0,
	_lastTarget = nil,
}

local function characterRoot(char)
	return char and (char:FindFirstChild('HumanoidRootPart') or char:FindFirstChildWhichIsA('BasePart'))
end

-- KillAura range model (closet-cheat friendly):
--   * user slider caps at 25 studs; anything above (30, 100, ...) is silently
--     pulled back to 25 so the range can never exceed the legit hitbox limit
--   * floor of 10 studs so the aura always has a usable working range
--   * closetMode (Closet cheat preset) hard-caps everything at 18 studs —
--     Bedwars' real attack reach is 12, so 18 keeps hits landing while the
--     range itself never looks impossible
local KILLAURA_RANGE_CAP = 25
local KILLAURA_RANGE_FLOOR = 10
local function killAuraClampRange(v, closetMode)
	v = tonumber(v) or KILLAURA_RANGE_FLOOR
	if closetMode then
		v = math.min(v, 18)
	end
	return math.clamp(math.floor(v * 10 + 0.5) / 10, KILLAURA_RANGE_FLOOR, KILLAURA_RANGE_CAP)
end

-- returns (humanoid, root) when the player is a valid target
local function killAuraValidTarget(player)
	if player == LocalPlayer then return nil end
	if KillAura.options.teamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team then
		return nil
	end
	local char = player.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass('Humanoid')
	local root = characterRoot(char)
	if not hum or hum.Health <= 0 or not root then return nil end
	return hum, root
end

local function killAuraFindTarget()
	local myRoot = characterRoot(LocalPlayer.Character)
	if not myRoot then return nil end

	local targetRange = KillAura.options.targetRange
	local best, bestRoot, bestDist
	local candidates = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local hum, root = killAuraValidTarget(player)
		if hum and root then
			local dist = (root.Position - myRoot.Position).Magnitude
			if dist <= targetRange then
				if KillAura.options.mode == 'Random' then
					table.insert(candidates, { player = player, root = root, dist = dist })
				elseif KillAura.options.mode == 'Lowest HP' then
					if not bestDist or hum.Health < bestDist then -- bestDist doubles as score here
						best, bestRoot, bestDist = player, root, hum.Health
					end
				else -- Closest
					if not bestDist or dist < bestDist then
						best, bestRoot, bestDist = player, root, dist
					end
				end
			end
		end
	end

	if KillAura.options.mode == 'Random' then
		if #candidates > 0 then
			local pick = candidates[math.random(#candidates)]
			return pick.player, pick.root, pick.dist
		end
		return nil
	end
	return best, bestRoot, bestDist
end

-- face the target so facing-based hit detection accepts our swings
local function killAuraFace(myRoot, targetRoot)
	local look = targetRoot.Position - myRoot.Position
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.05 then return end
	myRoot.CFrame = CFrame.lookAt(myRoot.Position, myRoot.Position + look.Unit)
end

-- weapon-name scoring: higher = preferred. Generic tools keep a low baseline
-- so ANY tool beats empty hands, but a sword beats a walkie-talkie.
local WEAPON_KEYWORDS = {
	sword = 100, blade = 92, katana = 90, saber = 85, machete = 82,
	knife = 75, dagger = 75, spear = 68, trident = 68,
	axe = 62, scythe = 62, hammer = 58, bat = 52, wrench = 45, pipe = 45,
	gun = 40, rifle = 40, pistol = 40, bow = 38, wand = 30,
}

local function killAuraToolScore(tool)
	local n = tool.Name:lower()
	local best = 10 -- generic baseline
	for keyword, score in pairs(WEAPON_KEYWORDS) do
		if n:find(keyword, 1, true) and score > best then
			best = score
		end
	end
	return best
end

-- auto-equip: only when nothing is held, so we never fight a tool the user
-- equipped on purpose. Games that force-unequip get re-equipped next tick.
local function killAuraEnsureEquipped()
	if not KillAura.options.autoEquip then return end
	local char = LocalPlayer.Character
	if not char or char:FindFirstChildOfClass('Tool') then return end
	local hum = char:FindFirstChildOfClass('Humanoid')
	local backpack = LocalPlayer:FindFirstChildOfClass('Backpack')
	if not hum or not backpack then return end

	local best, bestScore
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA('Tool') then
			local score = killAuraToolScore(tool)
			if not bestScore or score > bestScore then
				best, bestScore = tool, score
			end
		end
	end
	if best then
		pcall(function() hum:EquipTool(best) end)
	end
end

local function killAuraSwing(target)
	local char = LocalPlayer.Character
	local tool = char and char:FindFirstChildOfClass('Tool')

	-- 1) direct tool activation (most sword games)
	if tool then
		tool:Activate()
	end

	-- 2) click-to-attack fallback (games that listen for clicks, not tools)
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
		end)
	end

	KillAura._lastTarget = target
end

function KillAura.Enable()
	if KillAura.enabled then return end
	KillAura.enabled = true
	KillAura._nextSwing = 0
	killAuraEnsureEquipped() -- instant equip on enable

	table.insert(KillAura.conns, RunService.Heartbeat:Connect(function()
		if not KillAura.enabled then return end
		local now = os.clock()
		if now < KillAura._nextSwing then return end

		killAuraEnsureEquipped() -- re-equip if a game force-unequipped us

		-- catvape two-range model: aim out to targetRange, swing only inside attackRange
		local targetPlayer, targetRoot, dist = killAuraFindTarget()
		if not targetPlayer then return end

		-- target info shows whoever we're AIMING at, even before attack range
		if Modules.TargetInfo then
			local tchar = targetPlayer.Character
			Modules.TargetInfo.SetTarget(targetPlayer, tchar and tchar:FindFirstChildOfClass('Humanoid'))
		end

		if dist > KillAura.options.attackRange then return end -- aimed but too far to hit

		KillAura._nextSwing = now + KillAura.options.clickDelay

		local myRoot = characterRoot(LocalPlayer.Character)
		if myRoot and KillAura.options.facing then
			killAuraFace(myRoot, targetRoot)
		end
		killAuraSwing(targetPlayer)
	end))
end

function KillAura.Disable()
	if not KillAura.enabled then return end
	KillAura.enabled = false
	for _, c in ipairs(KillAura.conns) do c:Disconnect() end
	table.clear(KillAura.conns)
	KillAura._lastTarget = nil
	if Modules.TargetInfo then Modules.TargetInfo.Clear() end
end

function KillAura.Configure(opts)
	for k, v in pairs(opts) do KillAura.options[k] = v end
	-- enforce the range contract AFTER copying, so scripted Configures get
	-- exactly the same treatment as slider drags (30 -> 25, floors, closet cap)
	local closet = KillAura.options.closetMode
	KillAura.options.targetRange = killAuraClampRange(KillAura.options.targetRange, closet)
	KillAura.options.attackRange = killAuraClampRange(KillAura.options.attackRange, closet)
	-- return the APPLIED values so GUI sliders can snap to what the module
	-- actually uses (30 -> 25, 14.4 in closet mode, etc.)
	return KillAura.options.targetRange, KillAura.options.attackRange
end
Modules.KillAura = KillAura

-- ============================================================
-- Nightmare emote (user script, faithfully ported + made bindable)
-- Spins the game's NightmareEmote effects model under your legs and
-- plays its animation. Bind it to any key from the Scripts menu.
-- ============================================================
local NightmareEmote = {
	enabled = false,
	active = false,
	_conns = {},
	tweens = {},
	_animTrack = nil,
	_model = nil,
	EMOTE_ANIMATION = 'rbxassetid://9191822700',
}

local function emoteSpinParts(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA('BasePart') and (part.Name == 'Middle' or part.Name == 'Outer') then
			local tweenInfo, goal
			if part.Name == 'Middle' then
				tweenInfo = TweenInfo.new(12.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 0)
				goal = { Orientation = part.Orientation + Vector3.new(0, -360, 0) }
			elseif part.Name == 'Outer' then
				tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 0)
				goal = { Orientation = part.Orientation + Vector3.new(0, 360, 0) }
			end
			local tween = game:GetService('TweenService'):Create(part, tweenInfo, goal)
			tween:Play()
			table.insert(NightmareEmote.tweens, tween)
		end
	end
end

local function emoteStop()
	for _, tween in ipairs(NightmareEmote.tweens) do pcall(function() tween:Cancel() end) end
	table.clear(NightmareEmote.tweens)
	if NightmareEmote._animTrack then pcall(function() NightmareEmote._animTrack:Stop() end) end
	NightmareEmote._animTrack = nil
	if NightmareEmote._model then pcall(function() NightmareEmote._model:Destroy() end) end
	NightmareEmote._model = nil
	NightmareEmote.active = false
end

function NightmareEmote.activate()
	if NightmareEmote.active then return end
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild('HumanoidRootPart')
	local humanoid = char and char:FindFirstChildOfClass('Humanoid')
	if not (root and humanoid) then return end

	NightmareEmote.active = true
	local assets = ReplicatedStorage:FindFirstChild('Assets')
	local effects = assets and assets:FindFirstChild('Effects')
	local template = effects and effects:FindFirstChild('NightmareEmote')
	if template and template:IsA('Model') then
		local model = template:Clone()
		model.Parent = workspace
		if model.PrimaryPart then
			model:SetPrimaryPartCFrame(root.CFrame - Vector3.new(0, 3, 0))
			emoteSpinParts(model)
			NightmareEmote._model = model
		end
	end

	-- the emote animation
	pcall(function()
		local animator = humanoid:FindFirstChildOfClass('Animator') or Instance.new('Animator', humanoid)
		local anim = Instance.new('Animation')
		anim.AnimationId = NightmareEmote.EMOTE_ANIMATION
		NightmareEmote._animTrack = animator:LoadAnimation(anim)
		NightmareEmote._animTrack:Play()
	end)

	-- moving cancels the emote (faithful to the original script) —
	-- stored separately and refreshed per activation so old ones never pile up
	if NightmareEmote._runConn then
		pcall(function() NightmareEmote._runConn:Disconnect() end)
	end
	NightmareEmote._runConn = humanoid.Running:Connect(function(speed)
		if speed > 0 and NightmareEmote.active then
			emoteStop()
			if NightmareEmote.enabled then NightmareEmote.enabled = false end
		end
	end)
end

function NightmareEmote.Enable()
	if NightmareEmote.enabled then return end
	NightmareEmote.enabled = true
	-- one-shot activation on toggle, then stays "on" so the bind re-fires it
	task.spawn(function() NightmareEmote.activate() end)
end

function NightmareEmote.Disable()
	if not NightmareEmote.enabled then return end
	NightmareEmote.enabled = false
	for _, c in ipairs(NightmareEmote._conns) do pcall(function() c:Disconnect() end) end
	table.clear(NightmareEmote._conns)
	if NightmareEmote._runConn then
		pcall(function() NightmareEmote._runConn:Disconnect() end)
		NightmareEmote._runConn = nil
	end
	emoteStop()
end
Modules.NightmareEmote = NightmareEmote

-- ============================================================
-- Aim assist (mouse drifts toward the closest visible target's head)
-- Only assists when the crosshair is already near a target, so it
-- feels like a mouse-care assist instead of a lock.
-- ============================================================
local AimAssist = {
	enabled = false,
	conns = {},
	options = { fov = 60, smoothness = 0.35, teamCheck = true },
}

function AimAssist.Enable()
	if AimAssist.enabled then return end
	AimAssist.enabled = true
	table.insert(AimAssist.conns, RunService.RenderStepped:Connect(function()
		if not AimAssist.enabled then return end
		local camera = workspace.CurrentCamera -- re-fetch: respawns replace it
		local myRoot = characterRoot(LocalPlayer.Character)
		if not myRoot then return end
		local best, bestAngle
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and not (AimAssist.options.teamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team) then
				local char = player.Character
				local head = char and (char:FindFirstChild('Head') or char:FindFirstChild('HumanoidRootPart'))
				local hum = char and char:FindFirstChildOfClass('Humanoid')
				if head and hum and hum.Health > 0 then
					local screen, visible = camera:WorldToViewportPoint(head.Position)
					if visible then
						local center = camera.ViewportSize / 2
						local angle = (Vector2.new(screen.X, screen.Y) - center).Magnitude
						if angle <= AimAssist.options.fov and (not bestAngle or angle < bestAngle) then
							best, bestAngle = head.Position, angle
						end
					end
				end
			end
		end
		if best then
			local camCF = camera.CFrame
			local goal = CFrame.lookAt(camCF.Position, best)
			camera.CFrame = camCF:Lerp(goal, AimAssist.options.smoothness)
		end
	end))
end

function AimAssist.Disable()
	if not AimAssist.enabled then return end
	AimAssist.enabled = false
	for _, c in ipairs(AimAssist.conns) do c:Disconnect() end
	table.clear(AimAssist.conns)
end

function AimAssist.Configure(opts)
	for k, v in pairs(opts) do AimAssist.options[k] = v end
end
Modules.AimAssist = AimAssist

-- ============================================================
-- Trigger bot (auto-fires when your crosshair is over a valid enemy)
-- ============================================================
local TriggerBot = {
	enabled = false,
	conns = {},
	options = { delay = 0.15, teamCheck = true },
	_nextShot = 0,
}

local function triggerBotShoot()
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
		end)
	end
end

function TriggerBot.Enable()
	if TriggerBot.enabled then return end
	TriggerBot.enabled = true
	TriggerBot._nextShot = 0
	table.insert(TriggerBot.conns, RunService.RenderStepped:Connect(function()
		if not TriggerBot.enabled then return end
		local now = os.clock()
		if now < TriggerBot._nextShot then return end
		local camera = workspace.CurrentCamera
		local mousePos = UserInputService:GetMouseLocation()
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and not (TriggerBot.options.teamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team) then
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass('Humanoid')
				local root = char and characterRoot(char)
				if hum and hum.Health > 0 and root then
					local screen, visible = camera:WorldToViewportPoint(root.Position)
					-- ~20px crosshair window over the target's screen position
					if visible and (Vector2.new(screen.X, screen.Y) - mousePos).Magnitude <= 20 then
						TriggerBot._nextShot = now + TriggerBot.options.delay
						triggerBotShoot()
						break
					end
				end
			end
		end
	end))
end

function TriggerBot.Disable()
	if not TriggerBot.enabled then return end
	TriggerBot.enabled = false
	for _, c in ipairs(TriggerBot.conns) do c:Disconnect() end
	table.clear(TriggerBot.conns)
end

function TriggerBot.Configure(opts)
	for k, v in pairs(opts) do TriggerBot.options[k] = v end
end
Modules.TriggerBot = TriggerBot

-- ============================================================
-- Fly (flight velocity; W/S/A/D + Space/Ctrl relative to camera)
-- ============================================================
local Fly = {
	enabled = false,
	conns = {},
	options = { speed = 60 },
	_bodyVelocity = nil,
	_bodyGyro = nil,
}

function Fly.Enable()
	if Fly.enabled then return end
	Fly.enabled = true
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild('HumanoidRootPart')
	local hum = char and char:FindFirstChildOfClass('Humanoid')
	if not (root and hum) then Fly.enabled = false return end

	local bv = Instance.new('BodyVelocity')
	bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	bv.Velocity = Vector3.zero
	bv.Parent = root
	local bg = Instance.new('BodyGyro')
	bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	bg.P = 9e4
	bg.D = 0
	bg.CFrame = root.CFrame
	bg.Parent = root
	Fly._bodyVelocity, Fly._bodyGyro = bv, bg

	table.insert(Fly.conns, RunService.Heartbeat:Connect(function()
		if not Fly.enabled or not bv.Parent then return end
		local cam = workspace.CurrentCamera
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
		bv.Velocity = move.Magnitude > 0 and move.Unit * Fly.options.speed or Vector3.zero
		bg.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
	end))
end

function Fly.Disable()
	if not Fly.enabled then return end
	Fly.enabled = false
	for _, c in ipairs(Fly.conns) do c:Disconnect() end
	table.clear(Fly.conns)
	if Fly._bodyVelocity then pcall(function() Fly._bodyVelocity:Destroy() end) end
	if Fly._bodyGyro then pcall(function() Fly._bodyGyro:Destroy() end) end
	Fly._bodyVelocity, Fly._bodyGyro = nil, nil
end

function Fly.Configure(opts)
	for k, v in pairs(opts) do Fly.options[k] = v end
end
Modules.Fly = Fly

-- ============================================================
-- Sprint (hold Shift for a burst of speed)
-- ============================================================
local Sprint = {
	enabled = false,
	conns = {},
	options = { multiplier = 1.6 },
}

function Sprint.Enable()
	if Sprint.enabled then return end
	Sprint.enabled = true
	table.insert(Sprint.conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
			if hum then Sprint._orig = hum.WalkSpeed; hum.WalkSpeed = Sprint._orig * Sprint.options.multiplier end
		end
	end))
	table.insert(Sprint.conns, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
			if hum and Sprint._orig then hum.WalkSpeed = Sprint._orig end
		end
	end))
end

function Sprint.Disable()
	if not Sprint.enabled then return end
	Sprint.enabled = false
	for _, c in ipairs(Sprint.conns) do c:Disconnect() end
	table.clear(Sprint.conns)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
	if hum and Sprint._orig then hum.WalkSpeed = Sprint._orig end
end

function Sprint.Configure(opts)
	for k, v in pairs(opts) do Sprint.options[k] = v end
end
Modules.Sprint = Sprint

-- ============================================================
-- Spider (hold jump against a wall to climb it)
-- ============================================================
local Spider = { enabled = false, conns = {} }

function Spider.Enable()
	if Spider.enabled then return end
	Spider.enabled = true
	table.insert(Spider.conns, RunService.Heartbeat:Connect(function()
		if not Spider.enabled then return end
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		local root = char and char:FindFirstChild('HumanoidRootPart')
		if not (hum and root) or hum:GetState() ~= Enum.HumanoidStateType.Freefall then return end
		if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
		-- wall directly in front? climb it
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(root.Position, root.CFrame.LookVector * 2, params)
		if hit then
			root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 18, root.AssemblyLinearVelocity.Z)
		end
	end))
end

function Spider.Disable()
	if not Spider.enabled then return end
	Spider.enabled = false
	for _, c in ipairs(Spider.conns) do c:Disconnect() end
	table.clear(Spider.conns)
end
Modules.Spider = Spider

-- ============================================================
-- Safe walk (no falling off edges)
-- ============================================================
local SafeWalk = { enabled = false, conn = nil }

function SafeWalk.Enable()
	if SafeWalk.enabled then return end
	SafeWalk.enabled = true
	SafeWalk.conn = RunService.Heartbeat:Connect(function()
		if not SafeWalk.enabled then return end
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild('HumanoidRootPart')
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		if not (root and hum) or root.AssemblyLinearVelocity.Y > 0 then return end
		-- a tiny downward ray at the edge: teleport-stick when about to walk off
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -4, 0), params)
		if not hit and hum:GetState() == Enum.HumanoidStateType.Freefall then
			root.CFrame = root.CFrame - Vector3.new(0, 0.1, 0)
		end
	end)
end

function SafeWalk.Disable()
	if not SafeWalk.enabled then return end
	SafeWalk.enabled = false
	if SafeWalk.conn then SafeWalk.conn:Disconnect(); SafeWalk.conn = nil end
end
Modules.SafeWalk = SafeWalk

-- ============================================================
-- FOV changer (camera field of view)
-- ============================================================
local FOV = { enabled = false, value = 90, original = nil }

function FOV.Enable()
	if FOV.enabled then return end
	FOV.enabled = true
	FOV.original = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	workspace.CurrentCamera.FieldOfView = FOV.value
end

function FOV.Disable()
	if not FOV.enabled then return end
	FOV.enabled = false
	if workspace.CurrentCamera and FOV.original then
		workspace.CurrentCamera.FieldOfView = FOV.original
	end
end

function FOV.SetValue(v)
	FOV.value = v
	if FOV.enabled and workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = v
	end
end
Modules.FOV = FOV

-- ============================================================
-- FPS uncap (setFPSCap where the executor supports it)
-- ============================================================
local FPS = { enabled = false, cap = 240 }

function FPS.Enable()
	if FPS.enabled then return end
	FPS.enabled = true
	if setfpscap then pcall(setfpscap, FPS.cap) end
end

function FPS.Disable()
	if not FPS.enabled then return end
	FPS.enabled = false
	if setfpscap then pcall(setfpscap, 60) end
end

function FPS.SetValue(v)
	FPS.cap = v
	if FPS.enabled and setfpscap then pcall(setfpscap, v) end
end
Modules.FPS = FPS

-- ============================================================
-- Click TP (teleport to where you click)
-- ============================================================
local ClickTP = { enabled = false, conn = nil }

function ClickTP.Enable()
	if ClickTP.enabled then return end
	ClickTP.enabled = true
	ClickTP.conn = UserInputService.InputBegan:Connect(function(input, processed)
		if not ClickTP.enabled or processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
		local camera = workspace.CurrentCamera
		local unitRay = camera:ViewportPointToRay(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { LocalPlayer.Character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
		if hit and root then
			root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3, 0))
		end
	end)
end

function ClickTP.Disable()
	if not ClickTP.enabled then return end
	ClickTP.enabled = false
	if ClickTP.conn then ClickTP.conn:Disconnect(); ClickTP.conn = nil end
end
Modules.ClickTP = ClickTP

-- ============================================================
-- Gravity (set workspace gravity)
-- ============================================================
local Gravity = { enabled = false, value = 60, original = nil }

function Gravity.Enable()
	if Gravity.enabled then return end
	Gravity.enabled = true
	Gravity.original = workspace.Gravity
	workspace.Gravity = Gravity.value
end

function Gravity.Disable()
	if not Gravity.enabled then return end
	Gravity.enabled = false
	if Gravity.original then workspace.Gravity = Gravity.original end
end

function Gravity.SetValue(v)
	Gravity.value = v
	if Gravity.enabled then workspace.Gravity = v end
end
Modules.Gravity = Gravity

-- ============================================================
-- Clock time (freeze the sun where you want it)
-- ============================================================
local Clock = { enabled = false, value = 14 }

function Clock.Enable()
	if Clock.enabled then return end
	Clock.enabled = true
	Clock._conn = RunService.Heartbeat:Connect(function()
		if Clock.enabled then Lighting.ClockTime = Clock.value end
	end)
end

function Clock.Disable()
	if not Clock.enabled then return end
	Clock.enabled = false
	if Clock._conn then Clock._conn:Disconnect(); Clock._conn = nil end
end

function Clock.SetValue(v)
	Clock.value = v
end
Modules.Clock = Clock

-- ============================================================
-- Rejoin (teleports you back into the same server; useful on bad servers)
-- ============================================================
local Rejoin = {}

function Rejoin.Execute()
	local gamePlaceId = game.PlaceId
	pcall(function()
		TeleportService:Teleport(gamePlaceId, LocalPlayer)
	end)
end
Modules.Rejoin = Rejoin

-- ============================================================
-- Auto clicker (clicks at CPS while a player is inside Range)
-- ============================================================
local AutoClicker = {
	enabled = false,
	conns = {},
	options = { cps = 8, range = 12 },
	_next = 0,
}

function AutoClicker.Enable()
	if AutoClicker.enabled then return end
	AutoClicker.enabled = true
	AutoClicker._next = 0
	table.insert(AutoClicker.conns, RunService.Heartbeat:Connect(function()
		if not AutoClicker.enabled then return end
		local now = os.clock()
		if now < AutoClicker._next then return end

		-- range gate: pause clicking when nobody is close (combat-only clicking)
		local myRoot = characterRoot(LocalPlayer.Character)
		if myRoot then
			local inRange = false
			for _, player in ipairs(Players:GetPlayers()) do
				local _, root = killAuraValidTarget(player)
				if root and (root.Position - myRoot.Position).Magnitude <= AutoClicker.options.range then
					inRange = true
					break
				end
			end
			if not inRange then return end
		end

		AutoClicker._next = now + 1 / math.max(AutoClicker.options.cps, 0.1)
		if VirtualInputManager then
			pcall(function()
				VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
				VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
			end)
		end
	end))
end

function AutoClicker.Disable()
	if not AutoClicker.enabled then return end
	AutoClicker.enabled = false
	for _, c in ipairs(AutoClicker.conns) do c:Disconnect() end
	table.clear(AutoClicker.conns)
end

function AutoClicker.Configure(opts)
	for k, v in pairs(opts) do AutoClicker.options[k] = v end
end
Modules.AutoClicker = AutoClicker

-- ============================================================
-- Velocity (real: dampens knockback taken)
-- Hooks the standard knockback remotes in preload pcall loops —
-- bedwars-style games send root velocity through them. When a hook
-- fires, incoming knockback is scaled by H% / V% (0 = no knockback).
-- If a game uses none of the known remotes the module no-ops safely.
-- ============================================================
local Velocity = {
	enabled = false,
	options = { horizontal = 0, vertical = 0 },
	_conns = {},
	_hooked = false,
}

function Velocity.Enable()
	if Velocity.enabled then return end
	Velocity.enabled = true
	Velocity._hooked = false

	-- The scale the hooks read; kept on the module so Configure is live.
	local hScale, vScale = 0, 0
	task.spawn(function()
		while Velocity.enabled do
			hScale = Velocity.options.horizontal / 100
			vScale = Velocity.options.vertical / 100
			task.wait(0.25)
		end
	end)

	-- 1) KnockbackUtil-style takeKnockback (roblox bedwars and clones)
	task.spawn(function()
		pcall(function()
			local kb = require(game:GetService('ReplicatedStorage'):WaitForChild('Packages', 5)
				:WaitForChild('KnockbackUtil', 5))
			if kb and kb.takeKnockback and not Velocity._hooked then
				Velocity._hooked = true
				local old
				old = hookfunction(kb.takeKnockback, function(root, dir, mag, ...) -- luacheck: ignore
					if Velocity.enabled then
						if hScale == 0 and vScale == 0 then return end
						return old(root, dir * hScale, mag * ((vScale + hScale) / 2), ...)
					end
					return old(root, dir, mag, ...)
				end)
			end
		end)
	end)

	-- 2) generic Damage/Knockback remotes: rewrite the velocity vector they carry
	local REMOTES = { 'knockback', 'Knockback', 'damage', 'Damage', 'TakeDamage', 'Hit' }
	local function watchRemote(remote)
		if not (remote and remote:IsA('RemoteEvent')) then return end
		table.insert(Velocity._conns, remote.OnClientEvent:Connect(function(...)
			if not Velocity.enabled then return end
			local myRoot = characterRoot(LocalPlayer.Character)
			for _, arg in ipairs({ ... }) do
				if typeof(arg) == 'Vector3' and myRoot
					and (arg - myRoot.Position).Magnitude < 100
					and arg.Y > -1 and arg.Y < 120 -- knockback-shaped, not a position
				then
					-- rewrite in place is impossible; damp it on our root instead
					task.defer(function()
						if not (Velocity.enabled and myRoot.Parent) then return end
						local v = myRoot.AssemblyLinearVelocity
						myRoot.AssemblyLinearVelocity = Vector3.new(v.X * hScale, v.Y * vScale, v.Z * hScale)
					end)
					break
				end
			end
			end))
	end
	task.spawn(function()
		pcall(function()
			for _, name in ipairs(REMOTES) do
				local rs = game:GetService('ReplicatedStorage')
				for _, obj in ipairs(rs:GetDescendants()) do
					if not Velocity.enabled then break end
					if (obj:IsA('RemoteEvent') or obj:IsA('UnreliableRemoteEvent')) and obj.Name == name then
						watchRemote(obj)
					end
				end
			end
		end)
	end)

	-- wait for late-loading remotes too
	task.spawn(function()
		pcall(function()
			for _, name in ipairs(REMOTES) do
				local obj = game:GetService('ReplicatedStorage'):WaitForChild(name, 3)
				if Velocity.enabled then watchRemote(obj) end
			end
		end)
	end)
end

function Velocity.Disable()
	Velocity.enabled = false
	for _, c in ipairs(Velocity._conns) do pcall(function() c:Disconnect() end) end
	table.clear(Velocity._conns)
end

function Velocity.Configure(opts)
	for k, v in pairs(opts) do Velocity.options[k] = v end
end
Modules.Velocity = Velocity

-- ============================================================
-- Chat spy (real: prints every chat message to the console)
-- Supports BOTH chat systems: TextChatService (new) and the legacy
-- Player.Chatted event (old games). Toggled with the module row.
-- ============================================================
local ChatSpy = {
	enabled = false,
	conns = {},
	options = {},
	_spyAll = false, -- reserve: spy a specific player only
}

local TextChatService = game:GetService('TextChatService')

local function spyLog(plr, msg)
	pcall(rconsoleprint, ('[licarsware] %s: %s\n'):format(plr and plr.Name or '?', tostring(msg)))
end

function ChatSpy.Enable()
	if ChatSpy.enabled then return end
	ChatSpy.enabled = true

	-- console window for the spy output (pcall: some executors lack rconsole)
	pcall(rconsolecreate)
	pcall(rconsolesettitle, 'licarsware // chat spy')

	-- 1) TextChatService (default in new Roblox)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		table.insert(ChatSpy.conns, TextChatService.MessageReceived:Connect(function(msg)
			if not ChatSpy.enabled then return end
			local status = msg.Status
			if status ~= Enum.TextChatMessageStatus.Success and status ~= Enum.TextChatMessageStatus.Unknown then
				return
			end
			local senderName = nil
			if msg.TextSource then
				local plr = Players:GetPlayerByUserId(tonumber(msg.TextSource.Name) or -1)
				if plr then senderName = plr end
			end
			if msg.Status == Enum.TextChatMessageStatus.Unknown then
				-- system messages (join/leave, /commands echo)
				pcall(rconsoleprint, ('[licarsware] [system] %s\n'):format(tostring(msg.Text)))
			elseif senderName then
				spyLog(senderName, msg.Text)
			end
		end))
	end

	-- 2) legacy chat (Player.Chatted) — always wired, harmless in new games
	table.insert(ChatSpy.conns, Players.PlayerAdded:Connect(function(plr)
		if not ChatSpy.enabled then return end
		table.insert(ChatSpy.conns, plr.Chatted:Connect(function(msg)
			if ChatSpy.enabled then spyLog(plr, msg) end
		end))
	end))
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			table.insert(ChatSpy.conns, plr.Chatted:Connect(function(msg)
				if ChatSpy.enabled then spyLog(plr, msg) end
			end))
		end
	end
end

function ChatSpy.Disable()
	if not ChatSpy.enabled then return end
	ChatSpy.enabled = false
	for _, c in ipairs(ChatSpy.conns) do pcall(function() c:Disconnect() end) end
	table.clear(ChatSpy.conns)
end

function ChatSpy.Configure(opts)
	for k, v in pairs(opts) do ChatSpy.options[k] = v end
end
Modules.ChatSpy = ChatSpy

-- ============================================================
-- Reach (extends your melee: enlarges the equipped tool's Handle)
-- ============================================================
local Reach = {
	enabled = false,
	options = { reach = 8 },
	conn = nil,
	_originals = {}, -- [tool] = original size
}

local function reachApply(tool)
	if not (tool and tool:IsA('Tool')) then return end
	local handle = tool:FindFirstChild('Handle')
	if not (handle and handle:IsA('BasePart')) then return end
	if not Reach._originals[tool] then Reach._originals[tool] = handle.Size end
	local orig = Reach._originals[tool]
	local scale = math.clamp(Reach.options.reach / 5, 1, 4)
	handle.Size = Vector3.new(orig.X, orig.Y, orig.Z * scale)
end

local function reachRestore(tool)
	local orig = Reach._originals[tool]
	local handle = tool and tool:FindFirstChild('Handle')
	if orig and handle and handle:IsA('BasePart') then
		handle.Size = orig
	end
	Reach._originals[tool] = nil
end

function Reach.Enable()
	if Reach.enabled then return end
	Reach.enabled = true
	local char = LocalPlayer.Character
	if char and char:FindFirstChildOfClass('Tool') then reachApply(char:FindFirstChildOfClass('Tool')) end
	Reach.conn = LocalPlayer.Character.ChildAdded:Connect(function(child)
		if Reach.enabled then reachApply(child) end
	end)
end

function Reach.Disable()
	if not Reach.enabled then return end
	Reach.enabled = false
	if Reach.conn then Reach.conn:Disconnect(); Reach.conn = nil end
	for tool in pairs(Reach._originals) do reachRestore(tool) end
	table.clear(Reach._originals)
end

function Reach.Configure(opts)
	for k, v in pairs(opts) do Reach.options[k] = v end
	-- live re-apply to the currently held tool
	local char = LocalPlayer.Character
	if Reach.enabled and char then reachApply(char:FindFirstChildOfClass('Tool')) end
end
Modules.Reach = Reach

-- ============================================================
-- Long jump (boosted horizontal leap on every jump)
-- ============================================================
local LongJump = {
	enabled = false,
	conns = {},
	options = { power = 45 },
	_ready = true,
}

function LongJump.Enable()
	if LongJump.enabled then return end
	LongJump.enabled = true
	LongJump._ready = true
	table.insert(LongJump.conns, UserInputService.JumpRequest:Connect(function()
		if not (LongJump.enabled and LongJump._ready) then return end
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild('HumanoidRootPart')
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		if not (root and hum) or hum:GetState() == Enum.HumanoidStateType.Freefall then return end
		LongJump._ready = false
		local cam = workspace.CurrentCamera
		local dir = cam.CFrame.LookVector
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 0.05 then
			root.AssemblyLinearVelocity = dir.Unit * LongJump.options.power + Vector3.new(0, 30, 0)
		end
	end))
	table.insert(LongJump.conns, RunService.Heartbeat:Connect(function()
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		if hum and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
			LongJump._ready = true -- landed: arm the next boost
		end
	end))
end

function LongJump.Disable()
	if not LongJump.enabled then return end
	LongJump.enabled = false
	for _, c in ipairs(LongJump.conns) do c:Disconnect() end
	table.clear(LongJump.conns)
end

function LongJump.Configure(opts)
	for k, v in pairs(opts) do LongJump.options[k] = v end
end
Modules.LongJump = LongJump

-- ============================================================
-- Chams (Highlight on every player, visible through walls)
-- ============================================================
local Chams = {
	enabled = false,
	conns = {},
	options = { teamColor = true, throughWalls = true },
	_highlights = {},
}

local function chamApply(player)
	if player == LocalPlayer then return end
	local char = player.Character
	if not char then return end
	local hl = Chams._highlights[player]
	if not hl or not hl.Parent then
		hl = Instance.new('Highlight')
		Chams._highlights[player] = hl
	end
	hl.Adornee = char
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0
	hl.DepthMode = Chams.options.throughWalls
		and Enum.HighlightDepthMode.AlwaysOnTop
		or Enum.HighlightDepthMode.Occluded
	hl.FillColor = Chams.options.teamColor and (player.Team and player.Team.TeamColor.Color or Color3.fromRGB(120, 170, 255))
		or Color3.fromRGB(120, 170, 255)
	hl.Parent = char
end

local function chamRemove(player)
	local hl = Chams._highlights[player]
	if hl then pcall(function() hl:Destroy() end) end
	Chams._highlights[player] = nil
end

function Chams.Enable()
	if Chams.enabled then return end
	Chams.enabled = true
	for _, plr in ipairs(Players:GetPlayers()) do chamApply(plr) end
	table.insert(Chams.conns, Players.PlayerAdded:Connect(function(plr)
		if Chams.enabled then chamApply(plr) end
	end))
	table.insert(Chams.conns, Players.PlayerRemoving:Connect(chamRemove))
end

function Chams.Disable()
	if not Chams.enabled then return end
	Chams.enabled = false
	for _, c in ipairs(Chams.conns) do c:Disconnect() end
	table.clear(Chams.conns)
	for player in pairs(Chams._highlights) do chamRemove(player) end
end

function Chams.Configure(opts)
	for k, v in pairs(opts) do Chams.options[k] = v end
	if Chams.enabled then
		for _, plr in ipairs(Players:GetPlayers()) do chamApply(plr) end
	end
end
Modules.Chams = Chams

-- ============================================================
-- Name tags (overhead name + live health bar for every player)
-- ============================================================
local NameTags = {
	enabled = false,
	conns = {},
	_tags = {}, -- [player] = billboard
}

local function tagApply(player)
	if player == LocalPlayer then return end
	local char = player.Character
	local head = char and char:FindFirstChild('Head')
	if not head then return end
	local old = NameTags._tags[player]
	if old then pcall(function() old:Destroy() end) end

	local bb = Instance.new('BillboardGui')
	bb.Name = 'LicarswareTag'
	bb.Adornee = head
	bb.Size = UDim2.new(0, 120, 0, 34)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500

	local name = Instance.new('TextLabel')
	name.Size = UDim2.new(1, 0, 0, 18)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.ArialBold
	name.TextSize = 13
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = ('%s (@%s)'):format(player.DisplayName, player.Name)
	name.Parent = bb

	local hpBg = Instance.new('Frame')
	hpBg.Position = UDim2.new(0, 10, 0, 20)
	hpBg.Size = UDim2.new(1, -20, 0, 5)
	hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = bb

	local hp = Instance.new('Frame')
	hp.Size = UDim2.fromScale(1, 1)
	hp.BackgroundColor3 = Color3.fromRGB(90, 220, 120)
	hp.BorderSizePixel = 0
	hp.Parent = hpBg

	bb.Parent = head
	NameTags._tags[player] = bb

	-- live health updates
	local hum = char:FindFirstChildOfClass('Humanoid')
	if hum then
		NameTags._tags[player .. '_conn'] = hum.HealthChanged:Connect(function(h)
			local pct = math.clamp(h / math.max(hum.MaxHealth, 1), 0, 1)
			hp.Size = UDim2.fromScale(pct, 1)
			hp.BackgroundColor3 = Color3.fromHSV(pct / 2.5, 0.89, 0.75)
		end)
	end
end

function NameTags.Enable()
	if NameTags.enabled then return end
	NameTags.enabled = true
	for _, plr in ipairs(Players:GetPlayers()) do tagApply(plr) end
	table.insert(NameTags.conns, Players.PlayerAdded:Connect(function(plr)
		if NameTags.enabled then
			plr.CharacterAdded:Wait()
			if NameTags.enabled then tagApply(plr) end
		end
	end))
	table.insert(NameTags.conns, Players.PlayerRemoving:Connect(function(plr)
		local bb = NameTags._tags[plr]
		if bb then pcall(function() bb:Destroy() end) end
		NameTags._tags[plr] = nil
	end))
end

function NameTags.Disable()
	if not NameTags.enabled then return end
	NameTags.enabled = false
	for _, c in ipairs(NameTags.conns) do pcall(function() c:Disconnect() end) end
	table.clear(NameTags.conns)
	for k, v in pairs(NameTags._tags) do
		if typeof(v) == 'Instance' then pcall(function() v:Destroy() end) end
		NameTags._tags[k] = nil
	end
end
Modules.NameTags = NameTags

-- ============================================================
-- Invisible (client-side: your character stops rendering for YOU)
-- NOTE: purely visual/LocalTransparencyModifier; the server still
-- sees you. Great for screenshots and POV videos.
-- ============================================================
local Invisible = { enabled = false, conns = {} }

local function invisibleApply(char, transparent)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA('BasePart') or part:IsA('Decal') then
			part.LocalTransparencyModifier = transparent and 1 or 0
		end
	end
end

function Invisible.Enable()
	if Invisible.enabled then return end
	Invisible.enabled = true
	local char = LocalPlayer.Character
	if char then invisibleApply(char, true) end
	table.insert(Invisible.conns, LocalPlayer.CharacterAdded:Connect(function(c)
		if Invisible.enabled then
			task.wait(0.5)
			if Invisible.enabled then invisibleApply(c, true) end
		end
	end))
end

function Invisible.Disable()
	if not Invisible.enabled then return end
	Invisible.enabled = false
	for _, c in ipairs(Invisible.conns) do c:Disconnect() end
	table.clear(Invisible.conns)
	local char = LocalPlayer.Character
	if char then invisibleApply(char, false) end
end
Modules.Invisible = Invisible

-- ============================================================
-- Headless (hide just the head + face)
-- ============================================================
local Headless = { enabled = false, conns = {} }

local function headlessApply(char, hidden)
	local head = char and char:FindFirstChild('Head')
	if head then
		head.LocalTransparencyModifier = hidden and 1 or 0
		local face = head:FindFirstChildOfClass('Decal')
		if face then face.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

function Headless.Enable()
	if Headless.enabled then return end
	Headless.enabled = true
	local char = LocalPlayer.Character
	if char then headlessApply(char, true) end
	table.insert(Headless.conns, LocalPlayer.CharacterAdded:Connect(function(c)
		if Headless.enabled then
			task.wait(0.5)
			if Headless.enabled then headlessApply(c, true) end
		end
	end))
end

function Headless.Disable()
	if not Headless.enabled then return end
	Headless.enabled = false
	for _, c in ipairs(Headless.conns) do c:Disconnect() end
	table.clear(Headless.conns)
	local char = LocalPlayer.Character
	if char then headlessApply(char, false) end
end
Modules.Headless = Headless

-- ============================================================
-- Server hop (teleports to a fresh instance of the same game)
-- ============================================================
local ServerHop = {}

function ServerHop.Execute()
	pcall(function()
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	end)
end
Modules.ServerHop = ServerHop

-- ============================================================
-- Unload everything (used by future self-destruct)
-- ============================================================
function Modules.UnloadAll()
	Speed.Disable()
	HighJump.Disable()
	InfJump.Disable()
	Noclip.Disable()
	KillAura.Disable()
	AutoClicker.Disable()
	Velocity.Disable()
	ChatSpy.Disable()
	ESP.Disable()
	Fullbright.Disable()
	NoFog.Disable()
	AntiAFK.Disable()
	NightmareEmote.Disable()
	AimAssist.Disable()
	TriggerBot.Disable()
	Fly.Disable()
	Sprint.Disable()
	Spider.Disable()
	SafeWalk.Disable()
	FOV.Disable()
	FPS.Disable()
	ClickTP.Disable()
	Gravity.Disable()
	Clock.Disable()
	Reach.Disable()
	LongJump.Disable()
	Chams.Disable()
	NameTags.Disable()
	Invisible.Disable()
	Headless.Disable()
end

return Modules
