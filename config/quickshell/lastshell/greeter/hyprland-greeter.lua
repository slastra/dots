-- Hyprland as the greeter compositor. Mirrors the desktop's monitor block so
-- the login screen lands at the same scale, depth and colour management the
-- session will use — no mode flash on handover, and lastshell's sizes carry
-- over 1:1. Installed to /usr/local/share/lastshell-greeter/greeter/.

hl.monitor({
	output = "HDMI-A-1",
	mode = "3840x2160@119.88",
	position = "0x0",
	scale = 1.25,
	bitdepth = 10,
	cm = "hdredid",
	sdrbrightness = 2.05,
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.env("XCURSOR_SIZE", "36")
hl.env("HYPRCURSOR_SIZE", "36")
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
