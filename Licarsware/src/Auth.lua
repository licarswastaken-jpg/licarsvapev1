-- Licarsware // Auth client
-- Flow:
--   1. saved key? -> server verify
--   2. server verdict: valid | wrong-key (counts attempts) | ip-mismatch (KEY CONFLICT) | blacklisted (permanent)
--   3. UI: enter key, link to discord, locked screen when blacklisted

local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

local Config = script.Parent.Config
local Theme = script.Parent.Theme
local Util = script.Parent.Util

local Auth = {}

-- saved key storage (executor writefile/readfile)
local KEY_FILE = 'licarsware_key.txt'

local function readSaved()
	if not (isfile and isfile(KEY_FILE)) then return nil end
	local ok, res = pcall(readfile, KEY_FILE)
	return ok and res ~= '' and res or nil
end

local function saveKey(key)
	if not (writefile and writefile) then return end
	pcall(writefile, KEY_FILE, key)
end

local function clearSaved()
	if isfile and isfile(KEY_FILE) then pcall(delfile, KEY_FILE) end
end

-- server request (covers the main executor HTTP APIs)
local function request(payload)
	local body = HttpService:JSONEncode({
		script = Config.ScriptName,
		key    = payload.key,
		hwid   = payload.hwid or Util.GetHwid(),
		action = payload.action or 'verify',
	})
	local res
	local ok = pcall(function()
		if http_request then
			res = http_request({ Url = Config.AuthUrl, Method = 'POST', Body = body }).Body
		elseif syn and syn.request then
			res = syn.request({ Url = Config.AuthUrl, Method = 'POST', Body = body }).Body
		elseif request then
			res = request({ Url = Config.AuthUrl, Method = 'POST', Body = body }).Body
		else
			res = game:HttpPost(Config.AuthUrl, body)
		end
	end)
	if not ok or type(res) ~= 'string' then return nil end
	local decOK, data = pcall(HttpService.JSONDecode, HttpService, res)
	return decOK and data or nil
end

-- verdict model shared with the GUI
Auth.Verdict = { status = 'pending', message = '', attempts = 0 }
Auth.OnVerdict = nil -- set by KeySystem UI

function Auth.Verify(key)
	Auth.Verdict = { status = 'checking', message = 'Contacting auth server...', attempts = Auth.Verdict.attempts or 0 }
	if Auth.OnVerdict then Auth.OnVerdict(Auth.Verdict) end

	local data = request({ key = key, action = 'verify' })

	if not data then
		Auth.Verdict = { status = 'offline', message = 'Auth server unreachable. Try again later.' }
	elseif data.status == 'valid' then
		-- surface license info: duration + time left (server clock, authoritative)
		Auth.Verdict = {
			status = 'valid',
			message = 'Key verified!',
			attempts = 0,
			duration = data.duration,
			expiresIn = data.expires_in,
		}
		saveKey(key)
	elseif data.status == 'expired' then
		Auth.Verdict = { status = 'expired', message = data.message or 'License expired.' }
		clearSaved()
	elseif data.status == 'blacklisted' then
		Auth.Verdict = { status = 'blacklisted', message = data.reason or 'You are blacklisted.' }
		clearSaved() -- stop auto-retrying a dead key on every launch
	elseif data.status == 'ip_mismatch' then
		-- key is already bound to a different IP -> treat as theft attempt
		Auth.Verdict = { status = 'blacklisted', message = 'Key in use on another network. Access denied.' }
		-- the server auto-blacklists this HWID on ip_mismatch; we lock locally too
	elseif data.status == 'locked' then
		Auth.Verdict = { status = 'locked', message = ('Too many attempts. Wait %ss.'):format(data.retryAfter or 600) }
	else
		Auth.Verdict = { status = 'wrong', message = data.message or 'Invalid key.' }
		Auth.Verdict.attempts = (Auth.Verdict.attempts or 0) + 1
		if Auth.Verdict.attempts >= Config.Whitelist.MaxAttempts then
			Auth.Verdict.status = 'locked'
			Auth.Verdict.message = 'Too many attempts. Lockout engaged.'
		end
	end

	if Auth.OnVerdict then Auth.OnVerdict(Auth.Verdict) end
	return Auth.Verdict
end

function Auth.ResetAttempts()
	Auth.Verdict.attempts = 0
end

-- ============ UI ============
function Auth.ShowKeySystem(onSuccess)
	local gui = Instance.new('ScreenGui')
	gui.Name = 'Licarsware.KeySystem'
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function()
		gui.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')
	end)
	if not ok then gui.Parent = game:GetService('CoreGui') end

	local blur = Instance.new('Frame')
	blur.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	blur.BackgroundTransparency = 0.45
	blur.BorderSizePixel = 0
	blur.Size = UDim2.new(1, 0, 1, 0)
	blur.Parent = gui

	local card = Instance.new('Frame')
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 400, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BorderSizePixel = 0
	card.Parent = blur
	Instance.new('UICorner', card).CornerRadius = UDim.new(0, 14)

	local shadow = Instance.new('ImageLabel')
	shadow.Name = 'Shadow'
	shadow.BackgroundTransparency = 1
	shadow.Image = 'rbxassetid://6014261993'
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.45
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(49, 49, 450, 450)
	shadow.Size = UDim2.new(1, 60, 1, 60)
	shadow.Position = UDim2.new(0, -30, 0, -30)
	shadow.ZIndex = -1
	shadow.Parent = card

	local stroke = Instance.new('UIStroke')
	stroke.Transparency = 0.4
	stroke.Parent = card

	local pad = Instance.new('UIPadding')
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 26), UDim.new(0, 26)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 22), UDim.new(0, 22)
	pad.Parent = card

	local layout = Instance.new('UIListLayout')
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	-- logo
	local logo = Instance.new('TextLabel')
	logo.BackgroundTransparency = 1
	logo.Font = Enum.Font.GothamBlack
	logo.Text = 'licarsware'
	logo.TextSize = 26
	logo.TextXAlignment = Enum.TextXAlignment.Left
	logo.Size = UDim2.new(1, 0, 0, 30)
	logo.LayoutOrder = 1
	logo.Parent = card

	local tag = Instance.new('TextLabel')
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.Gotham
	tag.Text = ('private build  •  %s  •  hwid verified'):format(Config.ScriptName)
	tag.TextSize = 12
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Size = UDim2.new(1, 0, 0, 16)
	tag.LayoutOrder = 2
	tag.Parent = card

	local desc = Instance.new('TextLabel')
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.Text = 'Enter your key to continue. We don\'t grab your IP or store anything personal — the one-network lock exists only to stop key sharing, so you get the best cheating experience without getting banned. Still, we recommend playing on a new account, just in case.'
	desc.TextSize = 12
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.LayoutOrder = 3
	desc.Parent = card

	-- key input (real textbox)
	local inputHolder = Instance.new('Frame')
	inputHolder.BackgroundTransparency = 1
	inputHolder.Size = UDim2.new(1, 0, 0, 40)
	inputHolder.LayoutOrder = 4
	inputHolder.Parent = card

	local input = Instance.new('TextBox')
	input.Font = Enum.Font.Code
	input.TextSize = 14
	input.PlaceholderText = 'XXXX-XXXX-XXXX-XXXX'
	input.Text = readSaved() or ''
	input.ClearTextOnFocus = false
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Size = UDim2.new(1, -90, 1, 0)
	input.Parent = inputHolder
	Instance.new('UICorner', input).CornerRadius = UDim.new(0, 8)

	local inputPad = Instance.new('UIPadding')
	inputPad.PaddingLeft = UDim.new(0, 12)
	inputPad.Parent = input

	local submit = Instance.new('TextButton')
	submit.Font = Enum.Font.GothamBold
	submit.TextSize = 13
	submit.Text = 'SUBMIT'
	submit.AutoButtonColor = false
	submit.AnchorPoint = Vector2.new(1, 0)
	submit.Position = UDim2.new(1, 0, 0, 0)
	submit.Size = UDim2.new(0, 82, 1, 0)
	submit.Parent = inputHolder
	Instance.new('UICorner', submit).CornerRadius = UDim.new(0, 8)

	local msg = Instance.new('TextLabel')
	msg.BackgroundTransparency = 1
	msg.Font = Enum.Font.GothamSemibold
	msg.TextSize = 12
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextWrapped = true
	msg.Text = ' '
	msg.Size = UDim2.new(1, 0, 0, 0)
	msg.AutomaticSize = Enum.AutomaticSize.Y
	msg.LayoutOrder = 5
	msg.Parent = card

	local attempts = Instance.new('TextLabel')
	attempts.BackgroundTransparency = 1
	attempts.Font = Enum.Font.Gotham
	attempts.TextSize = 11
	attempts.TextXAlignment = Enum.TextXAlignment.Left
	attempts.Text = ('%d attempts remaining'):format(Config.Whitelist.MaxAttempts)
	attempts.Size = UDim2.new(1, 0, 0, 14)
	attempts.LayoutOrder = 6
	attempts.Parent = card

	local links = Instance.new('Frame')
	links.BackgroundTransparency = 1
	links.Size = UDim2.new(1, 0, 0, 24)
	links.LayoutOrder = 7
	links.Parent = card

	local discord = Instance.new('TextButton')
	discord.Font = Enum.Font.GothamSemibold
	discord.TextSize = 12
	discord.Text = 'discord.gg/licarsware'
	discord.TextXAlignment = Enum.TextXAlignment.Left
	discord.BackgroundTransparency = 1
	discord.Size = UDim2.new(0.5, 0, 1, 0)
	discord.Parent = links

	local getKey = Instance.new('TextButton')
	getKey.Font = Enum.Font.GothamSemibold
	getKey.TextSize = 12
	getKey.Text = 'Get a key →'
	getKey.TextXAlignment = Enum.TextXAlignment.Right
	getKey.BackgroundTransparency = 1
	getKey.AnchorPoint = Vector2.new(1, 0)
	getKey.Position = UDim2.new(1, 0, 0, 0)
	getKey.Size = UDim2.new(0.5, 0, 1, 0)
	getKey.Parent = links

	-- theme application
	local function applyTheme(t)
		card.BackgroundColor3 = t.Main
		stroke.Color = t.Stroke
		logo.TextColor3 = t.Text
		tag.TextColor3 = t.Dim
		desc.TextColor3 = t.Dim
		msg.TextColor3 = t.Dim
		attempts.TextColor3 = t.Dim
		input.BackgroundColor3 = t.Raised
		input.TextColor3 = t.Text
		input.PlaceholderColor3 = t.Dim
		submit.BackgroundColor3 = t.Accent
		submit.TextColor3 = Color3.fromRGB(255, 255, 255)
		discord.TextColor3 = t.Accent
		getKey.TextColor3 = t.Accent
		blur.BackgroundTransparency = t.IsDark and 0.55 or 0.35
	end
	Theme.Bind(applyTheme)

	local locked = false

	local function setMsg(text, colorKind)
		msg.Text = text
		msg.TextColor3 = colorKind == 'error' and Theme.Get().Error
			or colorKind == 'success' and Theme.Get().Success
			or Theme.Get().Dim
	end

	local function setLocked()
		locked = true
		input.TextEditable = false
		submit.Text = 'LOCKED'
		submit.BackgroundColor3 = Theme.Get().Error
		submit.TextColor3 = Color3.fromRGB(255, 255, 255)
		input.Text = 'BLACKLISTED'
		setMsg('This device is blacklisted. No further attempts allowed.', 'error')
		attempts.Text = '0 attempts remaining'
	end

	Auth.OnVerdict = function(verdict)
		if verdict.status == 'checking' then
			setMsg(verdict.message, 'info')
			submit.Text = '...'
		elseif verdict.status == 'valid' then
			setMsg(verdict.message, 'success')
			attempts.Text = verdict.expiresIn
				and ('%s license • %s remaining'):format(verdict.duration or 'timed', Util.FormatDuration(verdict.expiresIn))
				or 'lifetime license'
			task.delay(0.7, function()
				gui:Destroy()
				onSuccess(verdict)
			end)
		elseif verdict.status == 'expired' then
			setMsg(verdict.message, 'error')
			attempts.Text = 'license expired'
			submit.Text = 'SUBMIT'
		elseif verdict.status == 'blacklisted' then
			setLocked()
		elseif verdict.status == 'locked' then
			setMsg(verdict.message, 'error')
			submit.Text = 'WAIT'
			task.delay(Config.Whitelist.LockoutTime, function()
				locked = false
				Auth.ResetAttempts()
				submit.Text = 'SUBMIT'
				setMsg('You may try again.', 'info')
			end)
		else
			setMsg(verdict.message, 'error')
			local left = math.max(Config.Whitelist.MaxAttempts - (Auth.Verdict.attempts or 0), 0)
			attempts.Text = ('%d attempts remaining'):format(left)
			submit.Text = 'SUBMIT'
		end

	end

	local function try()
		if locked then return end
		local key = input.Text:gsub('%s', '')
		if #key < 3 then
			setMsg('Key must be at least 3 characters.', 'error')
			return
		end
		Auth.Verify(key)
	end

	submit.MouseButton1Click:Connect(try)
	input.FocusLost:Connect(function(enter) if enter then try() end end)

	-- start: auto-verify saved key, else empty state
	task.spawn(function()
		local saved = readSaved()
		if saved and #saved >= 3 then
			Auth.Verify(saved)
		end
	end)


	return gui
end

return Auth
