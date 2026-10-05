-- Licarsware // Central config
-- AuthUrl: deploy server/server.py (see README §3: Render is free) and put your
-- service URL here. Generate keys with POST /admin/gen + your LW_ADMIN token.
local Config = {
	AuthUrl = 'https://licarsware-xxxx.onrender.com/verify', -- TODO: your Render URL from README §3
	ScriptName = 'licarsware', -- MUST match the 'script' value used in /admin/gen, or every verify is rejected
	Whitelist = {
		MaxAttempts   = 5,   -- wrong keys before temporary lockout
		LockoutTime   = 600, -- seconds of lockout after too many wrong keys
	},
	Hwid = {
		Salt = 'licarsware::hwid::v1', -- change this so your HWIDs are unique to you
	},
	Menu = {
		ToggleKey  = Enum.KeyCode.RightShift,
		DefaultTheme = 'Dark', -- 'Dark' (normal) or 'Light'
	},
	Cdn = {
		Base = 'https://raw.githubusercontent.com/YOURNAME/Licarsware/main/', -- optional remote hosting
	},
}

return Config
