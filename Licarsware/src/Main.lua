-- Licarsware // Main window (vape v4 "Main" category + draggable category windows)
-- RightShift toggles. Gear (top right) opens the theme dropdown (Dark default / Light).

local UserInputService = game:GetService('UserInputService')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

local Config = script.Parent.Config
local Theme = script.Parent.Theme
local Components = script.Parent.Components
local Notifications = script.Parent.Notifications
local Modules = script.Parent.Modules
local TargetInfo = script.Parent.TargetInfo
local Bindings = script.Parent.Bindings

local TW = TweenInfo.new(0.16, Enum.EasingStyle.Linear)
local TW_WINDOW = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- module registry for the GUI layer (search, favorites, keybinds, panic)
local moduleRows = {}   -- [name] = ModuleRow component (category window row)
local moduleHome = {}   -- [name] = { window, expand, btn } (category it lives in)
local realModules = {}  -- [name] = real module table ({Enable, Disable})
local favRows = {}      -- [name] = favorite-replica ModuleRow (Favorites window)
local updateFavReplicas -- forward declaration (set up with the Favorites window)
local rebuildFavorites  -- forward declaration (set up with the Favorites window)
local cats = {}         -- [name] = category table from createCategory

-- standard vape-style enabled/disabled toast for any module
local function moduleToast(name, on)
	Notifications.Show(name, on and "<font color='#00AA00'>Enabled</font>" or "<font color='#FF5A5A'>Disabled</font>", on and 'success' or 'alert', 1.5)
end

-- wraps a real module ({Enable,Disable}) into a GUI toggle callback
local function bindModule(mod, name)
	realModules[name] = mod
	return function(on)
		if on then mod.Enable() else mod.Disable() end
		moduleToast(name, on)
		if updateFavReplicas then updateFavReplicas(name, on) end
	end
end

-- Nightmare emote has its own toggle flow (one-shot activate, not an on/off module)
local function bindEmote(mod, name)
	realModules[name] = mod
	return function(on)
		if on then mod.Enable() else mod.Disable() end
		Notifications.Show(name, on and "<font color='#00AA00'>Emote summoned</font>" or "Emote stopped", on and 'success' or 'info', 2)
	end
end

-- destructive one-shot buttons (Rejoin / Server hop): click twice within 5s
local armedButtons = {}
local function confirmClick(name, action)
	local now = os.clock()
	if armedButtons[name] and now - armedButtons[name] < 5 then
		armedButtons[name] = nil
		action()
	else
		armedButtons[name] = now
		Notifications.Show(name, 'Click again within 5 seconds to confirm', 'warning', 4)
	end
end

local Main = {}

function Main.Load()
	-- hand the overlay to Modules so KillAura can drive it (avoids a require cycle)
	Modules.TargetInfo = TargetInfo

	local gui = Instance.new('ScreenGui')
	gui.Name = 'Licarsware.Main'
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 99999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function()
		gui.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')
	end)
	if not ok then gui.Parent = game:GetService('CoreGui') end

	-- keybind listener boots with the menu (loads saved binds + favorites)
	Bindings.Start()

	-- root container so RightShift hides everything at once (vape's clickgui)
	local clickgui = Instance.new('Frame')
	clickgui.BackgroundTransparency = 1
	clickgui.Size = UDim2.fromScale(1, 1)
	clickgui.Parent = gui

	-- ============ helpers ============
	local function makeDraggable(frame)
		local dragging, dragStart, startPos
		frame.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			-- vape: drag only from the 41px header
			if input.Position.Y - frame.AbsolutePosition.Y > 41 then return end
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				frame.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end)
	end

	local function windowChrome(parent)
		local shadow = Instance.new('UIShadow')
		shadow.BlurRadius = UDim.new(0, 13)
		shadow.Transparency = 0.25
		shadow.Parent = parent
		local stroke = Instance.new('UIStroke')
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Theme.Get().Stroke
		stroke.Transparency = 0.8
		stroke.Parent = parent
		Theme.OnChanged(function(t) stroke.Color = t.Stroke end)
		Instance.new('UICorner', parent).CornerRadius = UDim.new(0, 5)
	end

	-- ============ main window (220 wide, like vape's GUICategory) ============
	local window = Instance.new('TextButton')
	window.AutoButtonColor = false
	window.BackgroundColor3 = Theme.Get().Main
	window.Name = 'LicarswareMain'
	window.Position = UDim2.fromOffset(6, 60)
	window.Size = UDim2.fromOffset(220, 41)
	window.Text = ''
	window.Parent = clickgui
	windowChrome(window)
	makeDraggable(window)

	-- logo text + colored tag (vape renders vapelogomini.png + colored v4mini)
	local logo = Instance.new('TextLabel')
	logo.BackgroundTransparency = 1
	logo.Font = Enum.Font.GothamBlack
	logo.Position = UDim2.fromOffset(12, 11)
	logo.Size = UDim2.new(0, 0, 0, 16)
	logo.AutomaticSize = Enum.AutomaticSize.X
	logo.Text = 'licarsware'
	logo.TextColor3 = Theme.Get().Text
	logo.TextSize = 13
	logo.TextXAlignment = Enum.TextXAlignment.Left
	logo.Parent = window
	Theme.OnChanged(function(t) logo.TextColor3 = t.Text end)

	local v4tag = Instance.new('TextLabel')
	v4tag.BackgroundTransparency = 1
	v4tag.Font = Enum.Font.GothamBlack
	v4tag.AnchorPoint = Vector2.new(0, 0)
	v4tag.Position = UDim2.new(1, 3, 0, 0)
	v4tag.Size = UDim2.fromOffset(24, 16)
	v4tag.Text = 'v4'
	v4tag.TextColor3 = Theme.Get().Accent
	v4tag.TextSize = 11
	v4tag.TextXAlignment = Enum.TextXAlignment.Left
	v4tag.Parent = logo
	Theme.OnChanged(function(t) v4tag.TextColor3 = t.Accent end)

	-- gear state must exist before any handler references it
	local gearMenuOpen = false

	-- gear button (top right)
	local gear = Instance.new('TextButton')
	gear.AutoButtonColor = false
	gear.BackgroundTransparency = 1
	gear.Font = Enum.Font.Arial
	gear.Position = UDim2.new(1, -30, 0, 0)
	gear.Size = UDim2.fromOffset(24, 41)
	gear.Text = '⚙'
	gear.TextColor3 = Theme.Get().Dim
	gear.TextSize = 14
	gear.Parent = window
	Theme.OnChanged(function(t)
		if not gearMenuOpen then gear.TextColor3 = t.Dim end
	end)

	-- theme dropdown (opens under the gear)
	local gearMenu = Instance.new('Frame')
	gearMenu.BackgroundColor3 = Theme.Get().Main
	gearMenu.BorderSizePixel = 0
	gearMenu.Position = UDim2.new(1, -166, 0, 41)
	gearMenu.Size = UDim2.fromOffset(160, 74)
	gearMenu.Visible = false
	gearMenu.ZIndex = 50
	gearMenu.Parent = window
	windowChrome(gearMenu)

	local gearTitle = Instance.new('TextLabel')
	gearTitle.BackgroundTransparency = 1
	gearTitle.Font = Enum.Font.Arial
	gearTitle.Position = UDim2.fromOffset(12, 8)
	gearTitle.Size = UDim2.new(1, -12, 0, 12)
	gearTitle.Text = 'THEME'
	gearTitle.TextColor3 = Theme.Get().Dim
	gearTitle.TextSize = 10
	gearTitle.TextXAlignment = Enum.TextXAlignment.Left
	gearTitle.ZIndex = 50
	gearTitle.Parent = gearMenu
	Theme.OnChanged(function(t) gearTitle.TextColor3 = t.Dim end)

	local function gearOption(text, y)
		local btn = Instance.new('TextButton')
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Theme.Get().Main
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.Arial
		btn.Position = UDim2.fromOffset(6, y)
		btn.Size = UDim2.new(1, -12, 0, 24)
		btn.Text = string.rep(' ', 4) .. text
		btn.TextColor3 = Theme.Get().Muted
		btn.TextSize = 13
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.ZIndex = 50
		btn.Parent = gearMenu
		Instance.new('UICorner', btn).CornerRadius = UDim.new(0, 4)
		return btn
	end

	local darkOpt = gearOption('Dark  •  default', 22)
	local lightOpt = gearOption('Light', 48)

	-- children of the main window (category buttons list)
	local children = Instance.new('Frame')
	children.BackgroundTransparency = 1
	children.Position = UDim2.fromOffset(0, 37)
	children.Size = UDim2.new(1, 0, 1, -33)
	children.Parent = window

	local windowlist = Instance.new('UIListLayout')
	windowlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	windowlist.SortOrder = Enum.SortOrder.LayoutOrder
	windowlist.Parent = children

	windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
		window.Size = UDim2.fromOffset(220, 41 + windowlist.AbsoluteContentSize.Y)
	end)

	-- ============ sidebar search (filters every module by name) ============
	local searchHolder = Instance.new('Frame')
	searchHolder.BackgroundTransparency = 1
	searchHolder.Size = UDim2.new(1, -12, 0, 30)
	searchHolder.LayoutOrder = -1
	searchHolder.Parent = children

	local searchBox = Instance.new('TextBox')
	searchBox.BackgroundColor3 = Theme.Get().Raised
	searchBox.BorderSizePixel = 0
	searchBox.ClearTextOnFocus = false
	searchBox.Font = Enum.Font.Arial
	searchBox.Position = UDim2.fromOffset(0, 0)
	searchBox.Size = UDim2.new(1, 0, 1, 0)
	searchBox.PlaceholderText = '  Search modules...'
	searchBox.PlaceholderColor3 = Theme.Get().Dim
	searchBox.Text = ''
	searchBox.TextColor3 = Theme.Get().Text
	searchBox.TextSize = 13
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Parent = searchHolder
	Instance.new('UICorner', searchBox).CornerRadius = UDim.new(0, 5)
	Theme.OnChanged(function(t)
		searchBox.BackgroundColor3 = t.Raised
		searchBox.PlaceholderColor3 = t.Dim
	end)

	local searchResults = Instance.new('Frame')
	searchResults.BackgroundTransparency = 1
	searchResults.Size = UDim2.new(1, 0, 0, 0)
	searchResults.LayoutOrder = -0.5
	searchResults.Visible = false
	searchResults.Parent = children
	local resultList = Instance.new('UIListLayout')
	resultList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	resultList.SortOrder = Enum.SortOrder.LayoutOrder
	resultList.Parent = searchResults

	-- ============ gear menu behaviour ============
	local function setGearMenu(open)
		gearMenuOpen = open
		gearMenu.Visible = true
		TweenService:Create(gearMenu, TW, {
			Size = open and UDim2.fromOffset(160, 74) or UDim2.fromOffset(160, 0),
		}):Play()
		if not open then
			task.delay(0.16, function()
				if not gearMenuOpen then gearMenu.Visible = false end
			end)
		end
		gear.TextColor3 = open and Theme.Get().Accent or Theme.Get().Dim
		local t = Theme.Get()
		darkOpt.Text = (Theme.Current == 'Dark' and '●  ' or '○  ') .. 'Dark  •  default'
		lightOpt.Text = (Theme.Current == 'Light' and '●  ' or '○  ') .. 'Light'
		darkOpt.BackgroundColor3 = Theme.Current == 'Dark' and t.Hover or t.Main
		lightOpt.BackgroundColor3 = Theme.Current == 'Light' and t.Hover or t.Main
		darkOpt.TextColor3 = Theme.Current == 'Dark' and t.Text or t.Muted
		lightOpt.TextColor3 = Theme.Current == 'Light' and t.Text or t.Muted
	end

	gear.MouseButton1Click:Connect(function() setGearMenu(not gearMenuOpen) end)
	darkOpt.MouseButton1Click:Connect(function()
		Theme.Set('Dark')
		setGearMenu(false)
	end)
	lightOpt.MouseButton1Click:Connect(function()
		Theme.Set('Light')
		setGearMenu(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and gearMenuOpen then
			local pos = input.Position
			local abs, size = gearMenu.AbsolutePosition, gearMenu.AbsoluteSize
			if pos.X < abs.X or pos.X > abs.X + size.X or pos.Y < abs.Y or pos.Y > abs.Y + size.Y then
				setGearMenu(false)
			end
		end
	end)

	-- ============ category windows ============
	local function createCategory(name, order, modules)
		-- button row in main window
		local btn = Instance.new('TextButton')
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Theme.Get().Main
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.Arial
		btn.Size = UDim2.new(1, -12, 0, 30)
		btn.Text = string.rep(' ', 12) .. name
		btn.TextColor3 = Theme.Get().Muted
		btn.TextSize = 14
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.LayoutOrder = math.floor(order) + 10 -- integer-safe (search results use fractional orders)
		btn.Parent = children
		btn.MouseEnter:Connect(function() btn.TextColor3 = Theme.Get().Text end)
		btn.MouseLeave:Connect(function() btn.TextColor3 = Theme.Get().Muted end)
		Theme.OnChanged(function(t) btn.BackgroundColor3 = t.Main end)

		-- the category window itself (220 wide, draggable)
		local catWindow = Instance.new('TextButton')
		catWindow.AutoButtonColor = false
		catWindow.BackgroundColor3 = Theme.Get().Main
		catWindow.Name = name .. 'Category'
		catWindow.Position = UDim2.fromOffset(236, 60 + (order - 1) * 46)
		catWindow.Size = UDim2.fromOffset(220, 41)
		catWindow.Text = ''
		catWindow.Visible = false
		catWindow.Parent = clickgui
		windowChrome(catWindow)
		makeDraggable(catWindow)

		local icon = Instance.new('Frame') -- accent square instead of icon image
		icon.BackgroundColor3 = Theme.Get().Accent
		icon.BorderSizePixel = 0
		icon.Position = UDim2.fromOffset(12, 16)
		icon.Size = UDim2.fromOffset(9, 9)
		icon.Parent = catWindow
		Instance.new('UICorner', icon).CornerRadius = UDim.new(0, 2)
		Theme.OnChanged(function(t) icon.BackgroundColor3 = t.Accent end)

		local title = Instance.new('TextLabel')
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.Arial
		title.Size = UDim2.new(1, -40, 0, 41)
		title.Position = UDim2.fromOffset(33, 0)
		title.Text = name
		title.TextColor3 = Theme.Get().Text
		title.TextSize = 13
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = catWindow
		Theme.OnChanged(function(t) title.TextColor3 = t.Text end)

		local arrow = Instance.new('TextButton') -- TextButton: ImageButton has no .Text
		arrow.AutoButtonColor = false
		arrow.BackgroundTransparency = 1
		arrow.Position = UDim2.new(1, -27, 0, 0)
		arrow.Size = UDim2.fromOffset(27, 41)
		arrow.Text = '▼'
		arrow.TextColor3 = Theme.Get().Dim
		arrow.TextSize = 10
		arrow.Parent = catWindow

		local divider = Instance.new('Frame')
		divider.BackgroundColor3 = Color3.new(1, 1, 1)
		divider.BackgroundTransparency = 0.93
		divider.BorderSizePixel = 0
		divider.Position = UDim2.fromOffset(0, 37)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Visible = false
		divider.Parent = catWindow

		local list = Instance.new('ScrollingFrame')
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.CanvasSize = UDim2.new()
		list.Position = UDim2.fromOffset(0, 37)
		list.ScrollBarThickness = 2
		list.ScrollBarImageTransparency = 0.75
		list.Size = UDim2.new(1, 0, 1, -41)
		list.Visible = false
		list.Parent = catWindow

		local listLayout = Instance.new('UIListLayout')
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = list

		local expanded = false
		listLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y)
			if expanded then
				catWindow.Size = UDim2.fromOffset(220, math.min(41 + listLayout.AbsoluteContentSize.Y, 601))
			end
		end)

		local function setExpanded(v)
			expanded = v
			list.Visible = v
			divider.Visible = v
			arrow.Text = v and '▲' or '▼'
			catWindow.Size = UDim2.fromOffset(220, v and math.min(41 + listLayout.AbsoluteContentSize.Y, 601) or 41)
		end

		arrow.MouseButton1Click:Connect(function() setExpanded(not expanded) end)
		title.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then setExpanded(not expanded) end
		end)

		-- build module rows from the declaration
		local built = {}
		for index, mod in ipairs(modules) do
			if mod.type == 'button' then
				built[mod.name] = Components.Button(list, mod.name, index, mod.callback)
			elseif mod.type == 'description' then
				built[mod.name] = Components.Description(list, mod.text, index)
			elseif mod.type == 'toggle' then
				built[mod.name] = Components.Toggle(list, mod.name, mod.default, index, mod.callback)
			elseif mod.type == 'slider' then
				built[mod.name] = Components.Slider(list, mod.name, mod.min, mod.max, mod.default, index, mod.callback, mod.suffix)
			elseif mod.type == 'dropdown' then
				built[mod.name] = Components.Dropdown(list, mod.name, mod.values, mod.default, index, mod.callback)
			elseif mod.type == 'module' then
				local row = Components.ModuleRow(list, mod.name, index, mod.callback)
				built[mod.name] = row
				moduleRows[mod.name] = row
				moduleHome[mod.name] = { window = catWindow, expand = setExpanded, btn = btn }

				-- A-Z keybind: chip click -> wait for any key -> Bindings decides validity
				row.OnBindRequest = function(key)
					if Bindings.SetBind(mod.name, key) then
						row.SetBind(key)
					else
						Notifications.Show('Keybind', (key and key.Name or 'That key') .. ' is reserved — pick another', 'warning', 3)
					end
				end
				if Bindings.GetBind(mod.name) then row.SetBind(Bindings.GetBind(mod.name)) end

				-- favorite star: persists to Bindings + rebuilds the Favorites window
				row.OnFavoriteChange = function(v)
					Bindings.SetFavorite(mod.name, v)
					if rebuildFavorites then rebuildFavorites() end
				end
				row.SetFavorite(Bindings.IsFavorite(mod.name))

				-- pressing the bound key (or a favorites/search row) toggles the real row
				Bindings.Register(mod.name, function() row.Toggle() end)
				if mod.options then
					local optIndex = 0
					for _, opt in ipairs(mod.options) do
						optIndex += 1
						if opt.type == 'toggle' then
							row.Options[opt.name] = Components.Toggle(row.Children, opt.name, opt.default, optIndex, opt.callback)
						elseif opt.type == 'slider' then
							row.Options[opt.name] = Components.Slider(row.Children, opt.name, opt.min, opt.max, opt.default, optIndex, opt.callback, opt.suffix)
						elseif opt.type == 'dropdown' then
							row.Options[opt.name] = Components.Dropdown(row.Children, opt.name, opt.values, opt.default, optIndex, opt.callback)
						end
					end
				end
			end
		end

		btn.MouseButton1Click:Connect(function()
			catWindow.Visible = not catWindow.Visible
		end)

		return { window = catWindow, modules = built, button = btn, list = list }
	end

	-- ============ content declarations (all real modules) ============
	-- Favorites window (built first so module rows can replica into it)
	cats.Favorites = createCategory('Favorites', 0.5, {})

	cats.Combat = createCategory('Combat', 1, {
		{ type = 'module', name = 'Auto clicker', options = {
			{ type = 'slider', name = 'CPS', min = 1, max = 20, default = 8, callback = function(v) Modules.AutoClicker.Configure({ cps = v }) end },
			{ type = 'slider', name = 'Range', min = 5, max = 25, default = 12, suffix = ' studs', callback = function(v) Modules.AutoClicker.Configure({ range = v }) end },
		}, callback = bindModule(Modules.AutoClicker, 'Auto clicker') },
		{ type = 'module', name = 'Velocity', options = {
			{ type = 'slider', name = 'Horizontal', min = 0, max = 100, default = 0, suffix = '%', callback = function(v) Modules.Velocity.Configure({ horizontal = v }) end },
			{ type = 'slider', name = 'Vertical', min = 0, max = 100, default = 0, suffix = '%', callback = function(v) Modules.Velocity.Configure({ vertical = v }) end },
		}, callback = bindModule(Modules.Velocity, 'Velocity') },
		{ type = 'module', name = 'Aim assist', options = {
			{ type = 'slider', name = 'FOV', min = 10, max = 180, default = 60, callback = function(v) Modules.AimAssist.Configure({ fov = v }) end },
			{ type = 'slider', name = 'Smoothness', min = 0.05, max = 1, default = 0.35, callback = function(v) Modules.AimAssist.Configure({ smoothness = v }) end },
		}, callback = bindModule(Modules.AimAssist, 'Aim assist') },
		{ type = 'module', name = 'Trigger bot', options = {
			{ type = 'slider', name = 'Delay', min = 0, max = 1, default = 0.15, suffix = 's', callback = function(v) Modules.TriggerBot.Configure({ delay = v }) end },
		}, callback = bindModule(Modules.TriggerBot, 'Trigger bot') },
	})

	cats.Blatant = createCategory('Blatant', 2, {
		{ type = 'button', name = 'Closet cheat (recommended)', callback = function()
			-- the preset: aura ranges snap to 14.4 studs and get hard-capped at 18
			local trVal, arVal = Modules.KillAura.Configure({ closetMode = true, targetRange = 14.4, attackRange = 14.4 })
			local ka = cats.Blatant and cats.Blatant.modules['Kill aura']
			if ka then
				local tr, ar = ka.Options['Target range'], ka.Options['Attack range']
				if tr and tr.SetBounds then tr.SetBounds(10, 18); tr.Set(trVal) end
				if ar and ar.SetBounds then ar.SetBounds(10, 18); ar.Set(arVal) end
			end
			Notifications.Show('Closet cheat', ('Preset applied • %.1f studs • capped at 18 (Bedwars reach = 12)'):format(trVal), 'info', 5)
		end },
		{ type = 'description', text = 'Bedwars attack reach is 12 studs. Closet cheating means staying at or below ~14.4 so your range never exceeds what a legit player could hit — anything over 18 is flaggable. Ranges are capped at 25.' },
		{ type = 'module', name = 'Kill aura', options = {
			{ type = 'slider', name = 'Target range', min = 10, max = 25, default = 12, suffix = ' studs', callback = function(v) Modules.KillAura.Configure({ targetRange = v }) end },
			{ type = 'slider', name = 'Attack range', min = 10, max = 25, default = 12, suffix = ' studs', callback = function(v) Modules.KillAura.Configure({ attackRange = v }) end },
			{ type = 'dropdown', name = 'Target mode', values = { 'Closest', 'Lowest HP', 'Random' }, default = 'Closest', callback = function(v) Modules.KillAura.Configure({ mode = v }) end },
			{ type = 'toggle', name = 'Team check', default = true, callback = function(v) Modules.KillAura.Configure({ teamCheck = v }) end },
			{ type = 'toggle', name = 'Auto equip', default = true, callback = function(v) Modules.KillAura.Configure({ autoEquip = v }) end },
			{ type = 'slider', name = 'Swing delay', min = 0.1, max = 1, default = 0.35, suffix = 's', callback = function(v) Modules.KillAura.Configure({ clickDelay = v }) end },
		}, callback = bindModule(Modules.KillAura, 'Kill aura') },
		{ type = 'module', name = 'Speed', options = {
			{ type = 'slider', name = 'Speed', min = 16, max = 22, default = 16, callback = function(v) Modules.Speed.SetValue(v) end },
		}, callback = bindModule(Modules.Speed, 'Speed') },
		{ type = 'module', name = 'High jump', options = {
			{ type = 'slider', name = 'Power', min = 30, max = 120, default = 50, callback = function(v) Modules.HighJump.SetValue(v) end },
		}, callback = bindModule(Modules.HighJump, 'High jump') },
		{ type = 'module', name = 'Infinite jump', callback = bindModule(Modules.InfiniteJump, 'Infinite jump') },
		{ type = 'module', name = 'Noclip', callback = bindModule(Modules.Noclip, 'Noclip') },
		{ type = 'module', name = 'Fly', options = {
			{ type = 'slider', name = 'Speed', min = 20, max = 200, default = 60, callback = function(v) Modules.Fly.Configure({ speed = v }) end },
		}, callback = bindModule(Modules.Fly, 'Fly') },
		{ type = 'module', name = 'Long jump', options = {
			{ type = 'slider', name = 'Power', min = 20, max = 100, default = 45, callback = function(v) Modules.LongJump.Configure({ power = v }) end },
		}, callback = bindModule(Modules.LongJump, 'Long jump') },
		{ type = 'module', name = 'Spider', callback = bindModule(Modules.Spider, 'Spider') },
		{ type = 'module', name = 'Sprint', options = {
			{ type = 'slider', name = 'Multiplier', min = 1.1, max = 3, default = 1.6, suffix = 'x', callback = function(v) Modules.Sprint.Configure({ multiplier = v }) end },
		}, callback = bindModule(Modules.Sprint, 'Sprint') },
		{ type = 'module', name = 'Safe walk', callback = bindModule(Modules.SafeWalk, 'Safe walk') },
	})

	cats.Render = createCategory('Render', 3, {
		{ type = 'module', name = 'ESP', options = {
			{ type = 'toggle', name = 'Boxes', default = true, callback = function(v) Modules.ESP.Configure({ boxes = v }) end },
			{ type = 'toggle', name = 'Names', default = true, callback = function(v) Modules.ESP.Configure({ names = v }) end },
			{ type = 'toggle', name = 'Health bar', callback = function(v) Modules.ESP.Configure({ health = v }) end },
			{ type = 'dropdown', name = 'Box color', values = { 'Team', 'Red', 'Green', 'Rainbow' }, default = 'Team', callback = function(v) Modules.ESP.Configure({ color = v }) end },
		}, callback = bindModule(Modules.ESP, 'ESP') },
		{ type = 'module', name = 'Fullbright', callback = bindModule(Modules.Fullbright, 'Fullbright') },
		{ type = 'module', name = 'No fog', callback = bindModule(Modules.NoFog, 'No fog') },
		{ type = 'module', name = 'Chams', options = {
			{ type = 'toggle', name = 'Team color', default = true, callback = function(v) Modules.Chams.Configure({ teamColor = v }) end },
			{ type = 'toggle', name = 'Through walls', default = true, callback = function(v) Modules.Chams.Configure({ throughWalls = v }) end },
		}, callback = bindModule(Modules.Chams, 'Chams') },
		{ type = 'module', name = 'Name tags', callback = bindModule(Modules.NameTags, 'Name tags') },
		{ type = 'module', name = 'FOV', options = {
			{ type = 'slider', name = 'Value', min = 60, max = 120, default = 90, callback = function(v) Modules.FOV.SetValue(v) end },
		}, callback = bindModule(Modules.FOV, 'FOV') },
		{ type = 'module', name = 'FPS uncap', options = {
			{ type = 'slider', name = 'Cap', min = 60, max = 999, default = 240, callback = function(v) Modules.FPS.SetValue(v) end },
		}, callback = bindModule(Modules.FPS, 'FPS uncap') },
		{ type = 'module', name = 'Invisible', callback = bindModule(Modules.Invisible, 'Invisible') },
		{ type = 'module', name = 'Headless', callback = bindModule(Modules.Headless, 'Headless') },
	})

	cats.Utility = createCategory('Utility', 4, {
		{ type = 'module', name = 'Anti AFK', callback = bindModule(Modules.AntiAFK, 'Anti AFK') },
		{ type = 'module', name = 'Chat spy', callback = bindModule(Modules.ChatSpy, 'Chat spy') },
		{ type = 'module', name = 'Click TP', callback = bindModule(Modules.ClickTP, 'Click TP') },
		{ type = 'module', name = 'Rejoin', callback = function()
			local row = moduleRows['Rejoin']
			confirmClick('Rejoin', function()
				Modules.Rejoin.Execute()
				if row then row.SetEnabled(false) end
			end)
		end },
		{ type = 'module', name = 'Server hop', callback = function()
			local row = moduleRows['Server hop']
			confirmClick('Server hop', function()
				Modules.ServerHop.Execute()
				if row then row.SetEnabled(false) end
			end)
		end },			{ type = 'module', name = 'Panic', callback = function()
				-- everything off, instantly, then reset every row visual
				for _, mod in pairs(realModules) do
					pcall(function() mod.Disable() end)
				end
				for _, row in pairs(moduleRows) do
					row.SetEnabled(false)
				end
				updateFavReplicas(nil)
				Notifications.Show('Panic', 'Everything disabled', 'warning', 3)
			end },
	})

	cats.World = createCategory('World', 5, {
		{ type = 'module', name = 'Gravity', options = {
			{ type = 'slider', name = 'Strength', min = 0, max = 196, default = 60, callback = function(v) Modules.Gravity.SetValue(v) end },
		}, callback = bindModule(Modules.Gravity, 'Gravity') },
		{ type = 'module', name = 'Clock time', options = {
			{ type = 'slider', name = 'Hour', min = 0, max = 24, default = 14, callback = function(v) Modules.Clock.SetValue(v) end },
		}, callback = bindModule(Modules.Clock, 'Clock time') },
	})

	cats.Scripts = createCategory('Scripts', 6, {
		{ type = 'description', text = 'Scripts are one-shot and keybindable — click the key chip (—) next to a script, press any key, and it fires from anywhere in-game.' },
		{ type = 'module', name = 'Nightmare emote', callback = bindEmote(Modules.NightmareEmote, 'Nightmare emote') },
	})

	-- ============ favorites: replicas of starred rows live in the Favorites window ============
	local function replicaToggle(name)
		return function(on)
			local real = moduleRows[name]
			if real and real.Enabled ~= on then real.Toggle() end -- single source of truth
		end
	end

	local function replicaStarSync(name)
		return function(v)
			local real = moduleRows[name]
			if real then real.SetFavorite(v) end -- chains: persists + rebuilds favorites
		end
	end

	rebuildFavorites = function()
		for _, child in ipairs(cats.Favorites.list:GetChildren()) do
			if child:IsA('TextButton') or child:IsA('Frame') then child:Destroy() end
		end
		favRows = {}
		local names = {}
		for name in pairs(moduleRows) do table.insert(names, name) end
		table.sort(names)
		local order = 0
		for _, name in ipairs(names) do
			if Bindings.IsFavorite(name) then
				order += 1
				local rep = Components.ModuleRow(cats.Favorites.list, name, order, replicaToggle(name))
				rep.SetEnabled(moduleRows[name].Enabled)
				rep.SetFavorite(true)
				if Bindings.GetBind(name) then rep.SetBind(Bindings.GetBind(name)) end
				rep.OnFavoriteChange = replicaStarSync(name)
				favRows[name] = rep
			end
		end
		if order == 0 then
			local hint = Instance.new('TextLabel')
			hint.BackgroundTransparency = 1
			hint.Size = UDim2.new(1, -24, 0, 44)
			hint.Position = UDim2.fromOffset(12, 0)
			hint.Font = Enum.Font.Arial
			hint.Text = 'No favorites yet — star a module with ☆'
			hint.TextColor3 = Theme.Get().Dim
			hint.TextSize = 12
			hint.TextWrapped = true
			hint.TextXAlignment = Enum.TextXAlignment.Left
			hint.Parent = cats.Favorites.list
			Theme.OnChanged(function(t) hint.TextColor3 = t.Dim end)
		end
	end

	-- keep favorite replicas' on/off state glued to the real rows
	updateFavReplicas = function(name)
		if name then
			local rep = favRows[name]
			if rep and moduleRows[name] then rep.SetEnabled(moduleRows[name].Enabled) end
		else
			for n, rep in pairs(favRows) do
				if moduleRows[n] then rep.SetEnabled(moduleRows[n].Enabled) end
			end
		end
	end

	rebuildFavorites()

	-- ============ search: filters modules by name, results toggle the real rows ============
	local function clearSearchReplicas()
		for _, child in ipairs(searchResults:GetChildren()) do
			if child:IsA('TextButton') or child:IsA('Frame') then child:Destroy() end
		end
	end

	searchBox:GetPropertyChangedSignal('Text'):Connect(function()
		local q = searchBox.Text:lower()
		if q == '' then
			searchResults.Visible = false
			clearSearchReplicas()
			for _, cat in pairs(cats) do cat.button.Visible = true end
			return
		end
		for _, cat in pairs(cats) do cat.button.Visible = false end
		clearSearchReplicas()
		local names = {}
		for name in pairs(moduleRows) do table.insert(names, name) end
		table.sort(names)
		local order = 0			for _, name in ipairs(names) do
				if name:lower():find(q, 1, true) then
					order += 1
					local rep = Components.ModuleRow(searchResults, name, order, replicaToggle(name))
					rep.SetEnabled(moduleRows[name].Enabled)
					rep.SetFavorite(Bindings.IsFavorite(name))
					if Bindings.GetBind(name) then rep.SetBind(Bindings.GetBind(name)) end
					rep.OnFavoriteChange = replicaStarSync(name)
				end
			end
		searchResults.Visible = true
	end)

	-- settings row (opens the same gear menu)
	local settingsRow = Instance.new('TextButton')
	settingsRow.AutoButtonColor = false
	settingsRow.BackgroundColor3 = Theme.Get().Main
	settingsRow.BorderSizePixel = 0
	settingsRow.Font = Enum.Font.Arial
	settingsRow.Size = UDim2.new(1, -12, 0, 30)
	settingsRow.Text = string.rep(' ', 12) .. 'Settings'
	settingsRow.TextColor3 = Theme.Get().Muted
	settingsRow.TextSize = 14
	settingsRow.TextXAlignment = Enum.TextXAlignment.Left
	settingsRow.LayoutOrder = 10
	settingsRow.Parent = children
	settingsRow.MouseEnter:Connect(function() settingsRow.TextColor3 = Theme.Get().Text end)
	settingsRow.MouseLeave:Connect(function() settingsRow.TextColor3 = Theme.Get().Muted end)
	Theme.OnChanged(function(t) settingsRow.BackgroundColor3 = t.Main end)
	settingsRow.MouseButton1Click:Connect(function()
		setGearMenu(not gearMenuOpen)
	end)

	-- ============ self destruct ============
	-- Order matters: restore game state FIRST, then kill theme listeners
	-- (so no callbacks fire onto destroyed instances), then remove GUIs.
	local destroyed = false
	local selfDestruct = Instance.new('TextButton')
	selfDestruct.AutoButtonColor = false
	selfDestruct.BackgroundColor3 = Theme.Get().Main
	selfDestruct.BorderSizePixel = 0
	selfDestruct.Font = Enum.Font.Arial
	selfDestruct.Size = UDim2.new(1, -12, 0, 30)
	selfDestruct.Text = string.rep(' ', 12) .. 'Self destruct'
	selfDestruct.TextColor3 = Theme.Get().Error
	selfDestruct.TextSize = 14
	selfDestruct.TextXAlignment = Enum.TextXAlignment.Left
	selfDestruct.LayoutOrder = 11
	selfDestruct.Parent = children
	selfDestruct.MouseEnter:Connect(function()
		selfDestruct.BackgroundColor3 = Theme.Get().Hover
	end)
	selfDestruct.MouseLeave:Connect(function()
		selfDestruct.BackgroundColor3 = Theme.Get().Main
	end)
	Theme.OnChanged(function(t)
		selfDestruct.TextColor3 = t.Error
		selfDestruct.BackgroundColor3 = t.Main
	end)

	selfDestruct.MouseButton1Click:Connect(function()
		if destroyed then return end
		destroyed = true

		-- 1) disconnect + restore everything the modules touched
		Modules.UnloadAll()
		Bindings.Stop() -- keyboard hook dies with the GUI

		-- 2) freeze theme callbacks before GUIs die
		Theme.ClearListeners()
		TargetInfo.Unload()

		-- 3) remove every licarsware ScreenGui from wherever it lives
		local containers = {}
		pcall(function() table.insert(containers, Players.LocalPlayer.PlayerGui) end)
		pcall(function() table.insert(containers, game:GetService('CoreGui')) end)
		for _, name in ipairs({ 'Licarsware.Main', 'Licarsware.KeySystem', 'Licarsware.Notifications', 'Licarsware.TargetInfo' }) do
			for _, container in ipairs(containers) do
				local g = container and container:FindFirstChild(name)
				if g then g:Destroy() end
			end
		end
	end)

	-- ============ RightShift toggle ============
	local open = true
	UserInputService.InputBegan:Connect(function(input, processed)
		if destroyed then return end -- self destructed: keyboard hooks must die too
		if input.KeyCode ~= Config.Menu.ToggleKey then return end
		if UserInputService:GetFocusedTextBox() then return end
		open = not open
		clickgui.Visible = open
	end)

	return gui
end

return Main
