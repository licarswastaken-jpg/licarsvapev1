-- Licarsware // entry point
-- 1) key system gate  ->  2) "Injected" toast (bottom right)  ->  3) main menu (RightShift)

local Notifications = script.Parent.Notifications
local Auth = script.Parent.Auth
local Main = script.Parent.Main
local Util = script.Parent.Util

local function start(verdict)
	Util.PrintBadge()
	Notifications.Injected(Util.GetExecutorName())

	-- timed licenses: warn the user with a second toast
	if verdict and verdict.expiresIn then
		task.delay(5.5, function()
			Notifications.Show(
				'License',
				('%s • %s remaining'):format(verdict.duration or 'timed', Util.FormatDuration(verdict.expiresIn)),
				'info',
				6
			)
		end)
	end

	Main.Load()
end

-- never boot the menu before the key gate passes
Auth.ShowKeySystem(start)

return true
