-- Licarsware // UI components
-- Faithful vape v4 idiom: 30px rows, muted text that brightens on hover,
-- 22x12 pill toggles, divider on enabled modules, Arial 14.

local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')

local Theme = script.Parent.Theme

local TW = TweenInfo.new(0.16, Enum.EasingStyle.Linear) -- uipallet.Tween

local Components = {}

local function dark(c, n) return Theme.dark(c, n) end
local function light(c, n) return Theme.light(c, n) end

-- ============ button row (full-row click, accent flash on press) ============
function Components.Button(parent, text, layoutOrder, callback)
	local row = Instance.new('TextButton')
	row.AutoButtonColor = false
	row.BackgroundColor3 = Theme.Get().Main
	row.BorderSizePixel = 0
	row.Font = Enum.Font.Arial
	row.Size = UDim2.new(1, -12, 0, 30)
	row.Text = string.rep(' ', 12) .. text
	row.TextColor3 = Theme.Get().Muted
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent
	Components.Corner(row, 5)

	row.MouseEnter:Connect(function() row.TextColor3 = Theme.Get().Text end)
	row.MouseLeave:Connect(function() row.TextColor3 = Theme.Get().Muted end)
	row.MouseButton1Click:Connect(function()
		row.TextColor3 = Theme.Get().Accent
		task.delay(0.25, function()
			if row.Parent then row.TextColor3 = Theme.Get().Muted end
		end)
		if callback then callback() end
	end)
	Theme.Bind(function(t)
		row.BackgroundColor3 = t.Main
		row.TextColor3 = t.Muted
	end)
	return row
end

-- ============ description row (small muted helper text, wraps) ============
function Components.Description(parent, text, layoutOrder)
	local row = Instance.new('TextLabel')
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.Arial
	row.Size = UDim2.new(1, -24, 0, 52)
	row.Position = UDim2.fromOffset(12, 0)
	row.Text = text
	row.TextColor3 = Theme.Get().Dim
	row.TextSize = 12
	row.TextWrapped = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextYAlignment = Enum.TextYAlignment.Top
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent
	Theme.Bind(function(t) row.TextColor3 = t.Dim end)
	return row
end

function Components.Create(class, props, children)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= 'Parent' then obj[k] = v end
	end
	if children then
		for _, child in ipairs(children) do child.Parent = obj end
	end
	if props.Parent then obj.Parent = props.Parent end
	return obj
end

function Components.Corner(parent, r)
	local c = Instance.new('UICorner')
	c.CornerRadius = UDim.new(0, r or 5)
	c.Parent = parent
	return c
end

function Components.Stroke(parent, color, transparency)
	local s = Instance.new('UIStroke')
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Get().Stroke
	s.Transparency = transparency or 0.8
	s.Parent = parent
	return s
end

-- hover/leave helpers (vape always tweens uipallet.Tween)
function Components.Hover(obj, onEnter, onLeave)
	obj.MouseEnter:Connect(onEnter)
	obj.MouseLeave:Connect(onLeave)
end

-- ============ row label (module/toggle text) ============
function Components.RowText(parent, text, y)
	local t = Instance.new('TextLabel')
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arial
	t.Size = UDim2.new(1, -46, 0, y or 30)
	t.Position = UDim2.fromOffset(12, 0)
	t.Text = text
	t.TextColor3 = Theme.Get().Muted
	t.TextSize = 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	Theme.OnChanged(function(th) t.TextColor3 = th.Muted end)
	return t
end

-- ============ Toggle (22x12 pill, knob 8x8) ============
function Components.Toggle(parent, text, default, layoutOrder, callback)
	local component = { Enabled = false }

	local toggle = Instance.new('TextButton')
	toggle.AutoButtonColor = false
	toggle.BackgroundColor3 = Theme.Get().Raised
	toggle.BorderSizePixel = 0
	toggle.Font = Enum.Font.Arial
	toggle.Size = UDim2.new(1, 0, 0, 30)
	toggle.Text = string.rep(' ', 12) .. text
	toggle.TextColor3 = Theme.Get().Muted
	toggle.TextSize = 14
	toggle.TextXAlignment = Enum.TextXAlignment.Left
	toggle.LayoutOrder = layoutOrder or 0
	toggle.Parent = parent

	local holder = Instance.new('Frame')
	holder.BackgroundColor3 = light(Theme.Get().Main, 0.14)
	holder.Position = UDim2.new(1, -30, 0, 9)
	holder.Size = UDim2.fromOffset(22, 12)
	holder.Parent = toggle
	Components.Corner(holder, 12)

	local knob = Instance.new('Frame')
	knob.BackgroundColor3 = Theme.Get().Main
	knob.Position = UDim2.fromOffset(2, 2)
	knob.Size = UDim2.fromOffset(8, 8)
	knob.Parent = holder
	Components.Corner(knob, 8)

	local isHover = false
	local function render()
		TweenService:Create(holder, TW, {
			BackgroundColor3 = component.Enabled
				and Theme.Get().Accent
				or (isHover and light(Theme.Get().Main, 0.37) or light(Theme.Get().Main, 0.14)),
		}):Play()
		TweenService:Create(knob, TW, {
			Position = UDim2.fromOffset(component.Enabled and 12 or 2, 2),
		}):Play()
	end
	Theme.OnChanged(render)

	toggle.MouseEnter:Connect(function()
		isHover = true
		if not component.Enabled then
			toggle.TextColor3 = Theme.Get().Text
		end
		render()
	end)
	toggle.MouseLeave:Connect(function()
		isHover = false
		if not component.Enabled then
			toggle.TextColor3 = Theme.Get().Muted
		end
		render()
	end)
	toggle.MouseButton1Click:Connect(function()
		component.Enabled = not component.Enabled
		render()
		if callback then callback(component.Enabled) end
	end)

	if default then
		component.Enabled = true
		render()
	end

	component.Set = function(v)
		if v ~= component.Enabled then
			component.Enabled = v
			render()
		end
	end
	return component
end

-- ============ Module row (40px, left-aligned name, dots, right-click opens options) ============
function Components.ModuleRow(parent, name, layoutOrder, callback)
	local component = { Enabled = false, Options = {}, Favorite = false, BoundKey = nil }

	local button = Instance.new('TextButton')
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Get().Main
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Arial
	button.Size = UDim2.fromOffset(218, 40)
	button.Text = string.rep(' ', 12) .. name
	button.TextColor3 = Theme.Get().Muted
	button.TextSize = 14
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.LayoutOrder = layoutOrder or 0
	button.Parent = parent

	local children = Instance.new('Frame')
	children.BackgroundColor3 = Theme.Get().Raised
	children.BorderSizePixel = 0
	children.Size = UDim2.new(1, 0, 0, 0)
	children.Visible = false
	children.LayoutOrder = (layoutOrder or 0) + 1
	children.Parent = parent

	local list = Instance.new('UIListLayout')
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = children

	-- content-size tracking so parents can resize
	local contentSize = 0
	list:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
		contentSize = list.AbsoluteContentSize.Y
		children.Size = UDim2.new(1, 0, 0, contentSize)
		if component.OnResize then component.OnResize() end
	end)

	local divider = Instance.new('Frame')
	divider.BackgroundColor3 = Color3.new(0.19, 0.19, 0.19)
	divider.BackgroundTransparency = 0.52
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, 0, 1, -1)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Visible = false
	divider.Parent = button

	-- three dots icon (clickable button so it sinks the click like vape's dotsbutton)
	local dots = Instance.new('TextButton')
	dots.AutoButtonColor = false
	dots.BackgroundTransparency = 1
	dots.Text = ''
	dots.Position = UDim2.new(1, -25, 0, 0)
	dots.Size = UDim2.fromOffset(25, 40)
	dots.Parent = button
	for i = 1, 3 do
		local d = Instance.new('Frame')
		d.BackgroundColor3 = light(Theme.Get().Main, 0.37)
		d.BorderSizePixel = 0
		d.Position = UDim2.fromOffset(11, (i - 1) * 6 + 12)
		d.Size = UDim2.fromOffset(3, 3)
		d.Parent = dots
	end

	-- ============ favorite star (right of the dots area) ============
	local star = Instance.new('TextButton')
	star.AutoButtonColor = false
	star.BackgroundTransparency = 1
	star.Position = UDim2.new(1, -52, 0, 0)
	star.Size = UDim2.fromOffset(22, 40)
	star.Font = Enum.Font.Arial
	star.Text = '☆'
	star.TextSize = 13
	star.TextColor3 = Theme.Get().Dim
	star.Parent = button

	-- ============ keybind chip (left of the star; shows the bound key) ============
	local bindChip = Instance.new('TextButton')
	bindChip.AutoButtonColor = false
	bindChip.BackgroundTransparency = 1
	bindChip.Position = UDim2.new(1, -78, 0, 0)
	bindChip.Size = UDim2.fromOffset(24, 40)
	bindChip.Font = Enum.Font.Arial
	bindChip.Text = '—'
	bindChip.TextSize = 10
	bindChip.TextColor3 = Theme.Get().Dim
	bindChip.Parent = button

	local listening = false
	local bindConn
	local function renderStar()
		star.Text = component.Favorite and '★' or '☆'
		star.TextColor3 = component.Favorite and Color3.fromRGB(255, 200, 60) or Theme.Get().Dim
	end
	local function renderBind()
		if listening then
			bindChip.Text = '...'
			bindChip.TextColor3 = Theme.Get().Accent
		elseif component.BoundKey then
			bindChip.Text = component.BoundKey.Name
			bindChip.TextColor3 = Theme.Get().Accent
		else
			bindChip.Text = '—'
			bindChip.TextColor3 = Theme.Get().Dim
		end
	end
	renderStar()
	renderBind()
	Theme.OnChanged(function()
		renderStar()
		renderBind()
	end)

	star.MouseEnter:Connect(function()
		if not component.Favorite then star.TextColor3 = Theme.Get().Text end
	end)
	star.MouseLeave:Connect(function() renderStar() end)
	star.MouseButton1Click:Connect(function()
		component.SetFavorite(not component.Favorite)
	end)

	bindChip.MouseEnter:Connect(function()
		if not (listening or component.BoundKey) then bindChip.TextColor3 = Theme.Get().Text end
	end)
	bindChip.MouseLeave:Connect(function() renderBind() end)
	bindChip.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		renderBind()
		bindConn = UserInputService.InputBegan:Connect(function(input)
			if bindConn then bindConn:Disconnect(); bindConn = nil end
			listening = false
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Escape then
				-- Main.lua decides validity (reserved keys etc.) and calls SetBind
				if component.OnBindRequest then component.OnBindRequest(input.KeyCode) end
			end
			renderBind()
		end)
	end)

	local isHover = false
	local function render()
		divider.Visible = component.Enabled
		button.TextColor3 = (isHover or children.Visible) and Theme.Get().Text or Theme.Get().Muted
		button.BackgroundColor3 = component.Enabled
			and Theme.Get().Accent
			or ((isHover or children.Visible) and Theme.Get().Hover or Theme.Get().Main)
		for _, d in ipairs(dots:GetChildren()) do
			d.BackgroundColor3 = component.Enabled
				and Color3.fromRGB(50, 50, 50)
				or light(Theme.Get().Main, 0.37)
		end
	end
	Theme.OnChanged(render)

	button.MouseEnter:Connect(function()
		isHover = true
		if not component.Enabled and not children.Visible then
			button.TextColor3 = Theme.Get().Text
			button.BackgroundColor3 = Theme.Get().Hover
		end
		for _, d in ipairs(dots:GetChildren()) do
			if not component.Enabled then d.BackgroundColor3 = Theme.Get().Text end
		end
	end)
	button.MouseLeave:Connect(function()
		isHover = false
		if not component.Enabled and not children.Visible then
			button.TextColor3 = Theme.Get().Muted
			button.BackgroundColor3 = Theme.Get().Main
		end
		for _, d in ipairs(dots:GetChildren()) do
			if not component.Enabled then d.BackgroundColor3 = light(Theme.Get().Main, 0.37) end
		end
	end)
	dots.MouseEnter:Connect(function()
		if not component.Enabled then
			for _, d in ipairs(dots:GetChildren()) do d.BackgroundColor3 = Theme.Get().Text end
		end
	end)
	dots.MouseLeave:Connect(function()
		if not component.Enabled then
			for _, d in ipairs(dots:GetChildren()) do d.BackgroundColor3 = light(Theme.Get().Main, 0.37) end
		end
	end)

	local function setOpen(open)
		children.Visible = open
		render()
	end

	button.MouseButton1Click:Connect(function()
		component.Enabled = not component.Enabled
		render()
		if callback then callback(component.Enabled) end
	end)
	button.MouseButton2Click:Connect(function() setOpen(not children.Visible) end)
	dots.MouseButton1Click:Connect(function() setOpen(not children.Visible) end)

	component.Object = button
	component.Children = children
	component.Toggle = function(v)
		if v ~= nil then
			if v ~= component.Enabled then component.Enabled = v; render() end
		else
			component.Enabled = not component.Enabled
			render()
		end
		if callback then callback(component.Enabled) end
	end
	-- external state sync (favorites list, keybinds, config load)
	component.SetEnabled = function(v)
		if v ~= component.Enabled then component.Enabled = v; render() end
	end
	component.SetFavorite = function(v)
		component.Favorite = v and true or false
		renderStar()
		if component.OnFavoriteChange then component.OnFavoriteChange(component.Favorite) end
	end
	component.SetBind = function(key)
		component.BoundKey = key
		renderBind()
	end
	component.OnBindRequest = nil
	component.OnFavoriteChange = nil
	return component
end

-- ============ Slider (6px track, teal fill, knob) ============
function Components.Slider(parent, text, min, max, default, layoutOrder, callback, suffix)
	local row = Instance.new('Frame')
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local label = Components.RowText(row, text, 16)
	label.Position = UDim2.fromOffset(12, 4)
	label.Size = UDim2.new(1, -70, 0, 16)

	local value = Instance.new('TextLabel')
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.Arial
	value.Position = UDim2.new(1, -66, 0, 4)
	value.Size = UDim2.fromOffset(54, 16)
	value.Text = tostring(default) .. (suffix or '')
	value.TextColor3 = Theme.Get().Dim
	value.TextSize = 12
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row
	Theme.OnChanged(function(t) value.TextColor3 = t.Dim end)

	local track = Instance.new('TextButton')
	track.AutoButtonColor = false
	track.BackgroundColor3 = Theme.Get().Hover
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(12, 26)
	track.Size = UDim2.new(1, -24, 0, 6)
	track.Text = ''
	track.Parent = row
	Components.Corner(track, 3)

	local fill = Instance.new('Frame')
	fill.BackgroundColor3 = Theme.Get().Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	Components.Corner(fill, 3)

	local knob = Instance.new('Frame')
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(10, 10)
	knob.Parent = track
	Components.Corner(knob, 5)

	local current = default
	local function render()
		local t = Theme.Get()
		local alpha = (current - min) / (max - min)
		track.BackgroundColor3 = t.Hover
		fill.BackgroundColor3 = t.Accent
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		value.Text = tostring(math.floor(current * 100 + 0.5) / 100) .. (suffix or '')
	end
	Theme.OnChanged(render)

	local dragging = false
	track.MouseButton1Down:Connect(function() dragging = true end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			current = min + (max - min) * rel
			render()
			if callback then callback(current) end
		end
	end)

	return {
		Set = function(v)
			current = math.clamp(v, min, max)
			render()
		end,
		-- live bounds change (used by the Closet cheat preset to cap at 18)
		SetBounds = function(newMin, newMax)
			min, max = newMin, newMax
			current = math.clamp(current, min, max)
			render()
		end,
	}
end

-- ============ Dropdown (vape-style: expands under the row) ============
function Components.Dropdown(parent, text, values, default, layoutOrder, callback)
	local current = default
	local open = false

	local row = Instance.new('TextButton')
	row.AutoButtonColor = false
	row.BackgroundColor3 = Theme.Get().Raised
	row.BorderSizePixel = 0
	row.Font = Enum.Font.Arial
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Text = string.rep(' ', 12) .. text
	row.TextColor3 = Theme.Get().Muted
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local value = Instance.new('TextLabel')
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.Arial
	value.Position = UDim2.new(1, -12, 0, 0)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Size = UDim2.new(0, 100, 1, 0)
	value.Text = tostring(default or 'Select...')
	value.TextColor3 = Theme.Get().Dim
	value.TextSize = 13
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row
	Theme.OnChanged(function(t) value.TextColor3 = t.Dim end)

	local list = Instance.new('Frame')
	list.BackgroundColor3 = Theme.Get().Raised
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, 30)
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Visible = false
	list.LayoutOrder = (layoutOrder or 0) + 1
	list.Parent = parent
	Components.Corner(list, 5)

	local listLayout = Instance.new('UIListLayout')
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local api = {}
	local function rebuild()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA('TextButton') then child:Destroy() end
		end
		for i, val in ipairs(values) do
			local opt = Instance.new('TextButton')
			opt.AutoButtonColor = false
			opt.BackgroundColor3 = Theme.Get().Raised
			opt.BorderSizePixel = 0
			opt.Font = Enum.Font.Arial
			opt.Size = UDim2.new(1, 0, 0, 26)
			opt.Text = string.rep(' ', 12) .. tostring(val)
			opt.TextColor3 = Theme.Get().Muted
			opt.TextSize = 13
			opt.TextXAlignment = Enum.TextXAlignment.Left
			opt.LayoutOrder = i
			opt.Parent = list
			Theme.OnChanged(function(t)
				opt.TextColor3 = t.Muted
				opt.BackgroundColor3 = t.Raised
			end)
			opt.MouseEnter:Connect(function()
				opt.TextColor3 = Theme.Get().Text
				opt.BackgroundColor3 = Theme.Get().Hover
			end)
			opt.MouseLeave:Connect(function()
				opt.TextColor3 = Theme.Get().Muted
				opt.BackgroundColor3 = Theme.Get().Raised
			end)
			opt.MouseButton1Click:Connect(function()
				current = val
				value.Text = tostring(val)
				api.SetOpen(false)
				if callback then callback(val) end
			end)
		end
	end
	rebuild()

	function api.SetOpen(v)
		open = v
		list.Visible = true
		local target = v and UDim2.new(1, 0, 0, #values * 26) or UDim2.new(1, 0, 0, 0)
		TweenService:Create(list, TW, { Size = target }):Play()
		if not v then
			task.delay(0.18, function()
				if not open then list.Visible = false end
			end)
		end
	end

	row.MouseButton1Click:Connect(function() api.SetOpen(not open) end)

	function api.SetValues(newValues)
		values = newValues
		rebuild()
	end

	return api
end

return Components
