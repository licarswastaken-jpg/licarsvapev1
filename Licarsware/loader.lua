-- licarsware // remote loader (dev convenience)
-- Prefers the built single file. For production, distribute dist/Licarsware.lua instead.

local BASE = 'https://raw.githubusercontent.com/YOURNAME/Licarsware/main/src/'
local FILES = { 'Config', 'Util', 'Theme', 'Notifications', 'Components', 'Bindings', 'Modules', 'TargetInfo', 'Auth', 'Main', 'init' }

local loaded = {}
local parentShim -- forward declaration

local function get(name)
	if loaded[name] then return loaded[name] end

	local src
	if readfile and isfile and isfile('licarsware/' .. name .. '.lua') then
		src = readfile('licarsware/' .. name .. '.lua')
	else
		src = game:HttpGet(BASE .. name .. '.lua', true)
	end

	local fn, err = loadstring(src, 'licarsware/' .. name)
	if not fn then
		error('licarsware: failed to compile ' .. name .. ': ' .. tostring(err))
	end

	local fakeScript = newproxy(true)
	getmetatable(fakeScript).__index = function(_, k)
		if k == 'Parent' then return parentShim end
		return nil
	end

	local env = getfenv(fn)
	setfenv(fn, setmetatable({}, {
		__index = function(_, k)
			if k == 'script' then return fakeScript end
			return env[k]
		end,
	}))

	local ok, res = pcall(fn)
	if not ok then
		error('licarsware: ' .. name .. ' errored: ' .. tostring(res))
	end
	loaded[name] = res
	return res
end

parentShim = setmetatable({}, {
	__index = function(_, key)
		return get(key)
	end,
})

-- entry point (init requires Config/Notifications/Auth/Main through the shim)
get('init')
