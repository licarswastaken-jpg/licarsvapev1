-- Licarsware // Bindings: A-Z keybinds + favorites + persistence
-- Keybinds:  every module row gets a bind chip; click it, press any key (A-Z,
--            digits, F-keys...) and that key toggles the module in-game — vape style.
-- Favorites: star a module (Phase, Fly, whatever) and it also appears in the
--            sidebar's Favorites section.
-- Persistence: saved to disk via writefile when the executor allows it, so your
--            binds and stars survive re-executes. Session-only otherwise.

local UserInputService = game:GetService('UserInputService')
local HttpService = game:GetService('HttpService')

local Bindings = {
	binds = {},      -- ['Fly'] = Enum.KeyCode.F
	favorites = {},  -- ['Fly'] = true
	Registry = {},   -- ['Fly'] = function() toggle it end   (set by Main.lua)
	_conns = {},
}

local SAVE_FILE = 'licarsware/prefs.json'

-- keys you should never get as a module bind (movement breaks otherwise)
local RESERVED = {
	W = true, A = true, S = true, D = true, Space = true,
	RightShift = true, -- menu toggle
	Slash = true, BackSlash = true, Return = true, Backspace = true, Tab = true,
}

-- ============ persistence ============
function Bindings.Save()
	if not (writefile and HttpService) then return end
	pcall(function()
		if isfolder and not isfolder('licarsware') and makefolder then
			makefolder('licarsware')
		end
		local data = { binds = {}, favorites = {} }
		for name, key in pairs(Bindings.binds) do
			data.binds[name] = key and key.Name or nil
		end
		for name, isFav in pairs(Bindings.favorites) do
			if isFav then table.insert(data.favorites, name) end
		end
		writefile(SAVE_FILE, HttpService:JSONEncode(data))
	end)
end

function Bindings.Load()
	if not (isfile and readfile) then return end
	pcall(function()
		if not isfile(SAVE_FILE) then return end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(SAVE_FILE))
		end)
		if not ok or type(data) ~= 'table' then return end
		for name, keyName in pairs(type(data.binds) == 'table' and data.binds or {}) do
			local key = Enum.KeyCode[tostring(keyName)]
			if key then Bindings.binds[tostring(name)] = key end
		end
		for _, name in ipairs(type(data.favorites) == 'table' and data.favorites or {}) do
			Bindings.favorites[tostring(name)] = true
		end
	end)
end

-- ============ bind API ============
-- key: Enum.KeyCode to bind, or nil to clear. Returns true if accepted.
function Bindings.SetBind(moduleName, key)
	if key ~= nil then
		if key.UserInputType ~= Enum.UserInputType.Keyboard then return false end
		if RESERVED[key.Name] then return false end
	end
	Bindings.binds[moduleName] = key
	Bindings.Save()
	return true
end

function Bindings.GetBind(moduleName)
	return Bindings.binds[moduleName]
end

function Bindings.ClearBind(moduleName)
	Bindings.binds[moduleName] = nil
	Bindings.Save()
end

-- ============ favorites API ============
function Bindings.SetFavorite(moduleName, isFav)
	Bindings.favorites[moduleName] = isFav and true or nil
	Bindings.Save()
end

function Bindings.ClearFavorite(moduleName)
	Bindings.favorites[moduleName] = nil
	Bindings.Save()
end

function Bindings.ToggleFavorite(moduleName)
	Bindings.favorites[moduleName] = not Bindings.favorites[moduleName] or nil
	Bindings.Save()
	return Bindings.favorites[moduleName] and true or false
end

function Bindings.IsFavorite(moduleName)
	return Bindings.favorites[moduleName] and true or false
end

-- remove every bind + star (used by self destruct so nothing lingers)
function Bindings.Wipe()
	table.clear(Bindings.binds)
	table.clear(Bindings.favorites)
	table.clear(Bindings.Registry)
	Bindings.Stop()
end

-- ============ module registry (toggling from a keypress) ============
function Bindings.Register(moduleName, toggleFn)
	Bindings.Registry[moduleName] = toggleFn
end

function Bindings.Unregister(moduleName)
	Bindings.Registry[moduleName] = nil
end

-- ============ key listener ============
function Bindings.Start()
	Bindings.Load()
	table.insert(Bindings._conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end -- typing in chat / a textbox: never fire
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if UserInputService:GetFocusedTextBox() then return end
		local key = input.KeyCode
		if not key or key == Enum.KeyCode.Unknown then return end
		for name, boundKey in pairs(Bindings.binds) do
			if boundKey == key then
				local fn = Bindings.Registry[name]
				if fn then
					task.spawn(fn)
				end
			end
		end
	end))
end

function Bindings.Stop()
	for _, c in ipairs(Bindings._conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(Bindings._conns)
end

return Bindings
