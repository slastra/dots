-- Nested-preview config for greeter/harness.sh: a 1080p window at scale 1.
hl.monitor({ output = "", mode = "1920x1080@60", position = "0x0", scale = 1.0 })
hl.config({
	general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
	decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
	animations = { enabled = false },
	misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, background_color = "rgb(13111e)" },
})
