-- Licarsware // HWID utility
-- HWID = SHA-256( salt + executor name + userId )
-- Deliberately EXCLUDES game.JobId: JobId changes every server hop, which would
-- make the fingerprint change mid-session and trip the server's hwid-mismatch
-- blacklist. Executor+userId is stable across servers and places.
-- The salt in Config.Hwid.Salt makes your users' HWIDs unique to YOUR script,
-- so a leaked HWID from another script cannot collide with yours.

local Config = script.Parent.Config

local HttpService = game:GetService('HttpService')

local function bytesToHex(bytes)
	local out = {}
	for i = 1, #bytes do
		out[i] = string.format('%02x', string.byte(bytes, i, i))
	end
	return table.concat(out)
end

local Util = {}

-- cached so every auth call in a session reuses one id
local cached

function Util.GetHwid()
	if cached then return cached end

	local ok, result = pcall(function()
		local player = game:GetService('Players').LocalPlayer
		local execName = 'unknown-executor'
		if identifyexecutor then
			pcall(function() execName = select(1, identifyexecutor()) or execName end)
		end
		local parts = {
			Config.Hwid.Salt,
			execName,
			tostring(player and player.UserId or 0),
		}
		return bytesToHex((HttpService):sha256(table.concat(parts, '|')))
	end)

	cached = ok and result or 'hwid-unavailable'
	return cached
end

-- seconds -> human label, e.g. 86100 -> '23h 55m', nil -> 'lifetime'
function Util.FormatDuration(seconds)
	if seconds == nil or seconds == false then return 'lifetime' end
	seconds = math.max(math.floor(seconds), 0)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	if days > 0 then return ('%dd %dh'):format(days, hours) end
	if hours > 0 then return ('%dh %dm'):format(hours, mins) end
	return ('%dm'):format(mins)
end

-- call after auth; cached so the console badge is printed once per session
function Util.GetExecutorName()
	local ok, name = pcall(function()
		return select(1, identifyexecutor())
	end)
	return (ok and name) or 'Unknown'
end

Util._badgePrinted = false
function Util.PrintBadge()
	if Util._badgePrinted then return end
	Util._badgePrinted = true
	print(('[Licarsware] hwid %s | executor %s'):format(Util.GetHwid(), Util.GetExecutorName()))
end

return Util
