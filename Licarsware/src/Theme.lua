-- Licarsware // Theme
-- Palette lifted straight from Vape v4 (uipallet + color.lua):
--   Main = RGB(26,25,26), Text = RGB(200,200,200), Accent = HSV(0.46, 0.96, 0.52)
-- Dark is the NORMAL mode. Gear icon (top right) switches Light/Dark.

local Theme = {}

local function dark(col, num)
	local h, s, v = col:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v - num, 0, 1))
end

local function light(col, num)
	local h, s, v = col:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + num, 0, 1))
end

local DARK_MAIN = Color3.fromRGB(26, 25, 26)
local DARK_TEXT = Color3.fromRGB(200, 200, 200)

local LIGHT_MAIN = Color3.fromRGB(236, 237, 239)
local LIGHT_TEXT = Color3.fromRGB(45, 45, 50)

local themes = {
	Dark = {
		Main     = DARK_MAIN,                          -- window bg
		Raised   = dark(DARK_MAIN, 0.02),              -- options / children bg
		Hover    = light(DARK_MAIN, 0.02),             -- row hover
		Text     = DARK_TEXT,                          -- bright text
		Muted    = dark(DARK_TEXT, 0.16),              -- default row text
		Dim      = Color3.fromRGB(140, 140, 140),      -- arrows / icons
		NotifSub = Color3.fromRGB(170, 170, 170),      -- notification body
		Stroke   = Color3.fromRGB(85, 85, 85),         -- window outline (0.8 transparency)
		Accent   = Color3.fromHSV(0.46, 0.96, 0.52),   -- vape teal
		Error    = Color3.fromRGB(250, 50, 56),        -- vape alert red
		Warning  = Color3.fromRGB(236, 129, 44),
		Success  = Color3.fromRGB(5, 190, 102),
		IsDark   = true,
	},
	Light = {
		Main     = LIGHT_MAIN,
		Raised   = dark(LIGHT_MAIN, 0.04),
		Hover    = dark(LIGHT_MAIN, 0.03),
		Text     = LIGHT_TEXT,
		Muted    = light(LIGHT_TEXT, 0.24),
		Dim      = Color3.fromRGB(120, 120, 126),
		NotifSub = Color3.fromRGB(95, 95, 100),
		Stroke   = Color3.fromRGB(160, 160, 166),
		Accent   = Color3.fromHSV(0.46, 0.96, 0.62),
		Error    = Color3.fromRGB(220, 55, 60),
		Warning  = Color3.fromRGB(220, 130, 40),
		Success  = Color3.fromRGB(20, 160, 90),
		IsDark   = false,
	},
}

local listeners = {}
Theme.Current = 'Dark'

function Theme.Get()
	return themes[Theme.Current] or themes.Dark
end

function Theme.Set(name)
	Theme.Current = themes[name] and name or 'Dark'
	for _, fn in ipairs(listeners) do
		task.spawn(fn, Theme.Get(), Theme.Current)
	end
end

function Theme.Toggle()
	Theme.Set(Theme.Current == 'Dark' and 'Light' or 'Dark')
end

-- self-destruct support: after GUIs are destroyed, queued callbacks would
-- error on destroyed instances. Drop them all and freeze registration so
-- stragglers from still-running code can't queue onto nothing.
local frozen = false

function Theme.OnChanged(fn)
	if frozen then return end
	table.insert(listeners, fn)
end

function Theme.ClearListeners()
	frozen = true
	table.clear(listeners)
end

function Theme.Bind(callback)
	if frozen then return end
	Theme.OnChanged(callback)
	callback(Theme.Get(), Theme.Current)
end

-- exposed for components (vape-style derived shades)
Theme.dark = dark
Theme.light = light

return Theme
