-- Hyprland as the greeter compositor. Mirrors each machine's monitor block so
-- the login screen lands at the same scale, depth and colour management the
-- session will use — no mode flash on handover, and lastshell's sizes carry
-- over 1:1. Installed to /usr/local/share/lastshell-greeter/greeter/.

local host = "desk"
local f = io.open("/etc/hostname")
if f then host = (f:read("l") or host):match("^%s*(.-)%s*$"); f:close() end

if host == "lap" then
	hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5 })
	hl.env("XCURSOR_SIZE", "32")
	hl.env("HYPRCURSOR_SIZE", "32")
else
	hl.monitor({
		output = "HDMI-A-1",
		mode = "3840x2160@119.88",
		position = "0x0",
		scale = 1.25,
		bitdepth = 10,
		cm = "hdredid",
		sdrbrightness = 2.05,
	})
	hl.env("XCURSOR_SIZE", "36")
	hl.env("HYPRCURSOR_SIZE", "36")
end
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- The greeter user can't read ~/.local/share/icons, so this needs the theme
-- copied to /usr/share/icons too; without it the login screen draws Adwaita.
hl.env("XCURSOR_THEME", "BreezeX-RosePine")
hl.env("HYPRCURSOR_THEME", "BreezeX-RosePine")
hl.env("QT_QPA_PLATFORM", "wayland")

hl.config({
	general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
	decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
	animations = { enabled = false },
	input = { kb_layout = "us", numlock_by_default = true },
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		background_color = "rgb(13111e)",
	},
})

hl.on("hyprland.start", function()
	-- Quickshell exits itself once greetd accepts the session; then the
	-- compositor must go too, or greetd waits on it. If the QML greeter
	-- fails to start, ReGreet (still installed) takes over in this same
	-- session rather than leaving a dark screen.
	hl.exec_cmd(
		"qs -p /usr/local/share/lastshell-greeter/greeter.qml"
			.. " || regreet"
			.. " ; hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || hyprctl dispatch exit"
	)
end)
