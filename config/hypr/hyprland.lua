-- Hyprland config — Lua (0.55+)

local theme = require("theme")

----------------
--- MONITORS ---
----------------

hl.monitor({
	output = "HDMI-A-1",
	mode = "3840x2160@119.88",
	position = "0x0",
	scale = 1.25,
	bitdepth = 10,
	cm = "hdredid", -- HDR, luminance ranges from the TV's EDID ("auto" resolved to wide-gamut SDR)
	sdrbrightness = 1, -- lift SDR content a bit against the HDR range; tune to taste
})

-----------------
--- AUTOSTART ---
-----------------

hl.on("hyprland.start", function()
	-- Session daemons are systemd user units WantedBy graphical-session.target
	-- (since 2026-11-03): Hyprland imports WAYLAND_DISPLAY and
	-- HYPRLAND_INSTANCE_SIGNATURE, starts hyprland-session.target (which binds
	-- graphical-session.target) and stops it on exit. That covers tabstrip,
	-- claude-status, hyprglaze, cliphist, hypridle, Sunshine and
	-- eufy-bridge-notify; `systemctl --user list-dependencies
	-- graphical-session.target` shows them. Restart=on-failure, journald and
	-- per-unit cgroups (deskwatch's desk.hot) come with it.
	--
	-- lastshell (Quickshell) stays launched here, in the login session: it is
	-- the polkit agent (registered per login session) and its launcher starts
	-- apps as its children, which a unit's cgroup would kill on restart.
	hl.exec_cmd("qs -c lastshell &")
	-- AI-generated startup jingle (GLM 5.3 Flash via OpenRouter, an emotune
	-- score); falls back to ~/.cache/boot-jingle/known-good.toml when offline.
	hl.exec_cmd("~/.local/bin/boot-jingle &")
	-- Variables Hyprland's own import leaves out, for D-Bus-activated and
	-- later-started apps (cursor theme; GDK_WAYLAND_DISABLE, see ENVIRONMENT).
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XCURSOR_THEME XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE GDK_WAYLAND_DISABLE")
	-- No polkit agent here: lastshell is the agent (overlays/PolkitDialog.qml)
	-- since 2026-10-16. A second agent would take the session's registration
	-- first and lastshell's would fail, so hyprpolkitagent stays disabled.
end)

-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------

-- Qt6 apps need the qt6ct platformtheme plugin; /etc/environment still says
-- qt5ct (pam-level, needs sudo to fix), which Qt6 cannot load — so every Qt6
-- app fell back to unthemed Fusion. This override wins for everything
-- Hyprland spawns. Palette: ~/.config/qt6ct/colors/rose-pine.conf.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- BreezeX Rosé Pine (rose-pine/cursor), one theme dir in ~/.local/share/icons
-- holding both formats: hyprcursors/ is ndom91's SVG build plus the animated
-- wait/progress it lacks (built in ~/Projects/Scratch/cursors/build-breezex),
-- cursors/ is the stock Xcursor release for GTK, Qt and XWayland. Its Xcursor
-- frames stop at 40/48, so 36 at 1.25 scale draws the 48 there.
-- Simp1e-Rose-Pine (2026-10-04) and Bibata-Modern-RosePine are still installed.
-- Since 2026-11-10 the theme in use is "Tint": the same shapes, recolored to the
-- current color scheme by ~/.config/tint/hooks/assets on every `tint apply`.
hl.env("XCURSOR_THEME", "Tint")
hl.env("HYPRCURSOR_THEME", "Tint")
hl.env("XCURSOR_SIZE", "36")
hl.env("HYPRCURSOR_SIZE", "36")
hl.env("GDK_SCALE", "2")

-- GTK 4.24 attaches ext-background-effect to every surface it creates, and
-- once a surface has one Hyprland blurs only the region the client asks for,
-- ignoring decoration:blur. GTK asks for none unless CSS uses backdrop-filter,
-- so every GTK4 window lost blur (most visible on inactive floats over other
-- windows). Hiding the global from GTK hands blur back to the compositor.
hl.env("GDK_WAYLAND_DISABLE", "ext_background_effect_manager_v1")

-- NVIDIA VA-API for Firefox / browsers
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")

-- No realtime scheduling for the compositor (2026-11-03). Since 0.56 Hyprland
-- asks rtkit for SCHED_RR with RLIMIT_RTTIME 150/200 ms. When the TV wakes and
-- HDMI reconnects, one nvidia-drm connector probe (link training + EDID, ~240 ms
-- of CPU in the kernel) blows the 200 ms hard limit and the kernel SIGKILLs
-- Hyprland: no core, no crash report, safe-mode relaunch, blank screen. That
-- happened on the 11:27 wake today. Upstream: discussion #16648 (LG C1 + RTX,
-- same driver), fix pending in PR #16737 (not in 0.57.1). hl.env setenv()s
-- during config load, before startCompositor() checks this, so it takes effect
-- from the next Hyprland start. Remove once #16737 ships in a release.
hl.env("HYPRLAND_NO_RT", "1")

---------------------
--- LOOK AND FEEL ---
---------------------

hl.config({
	general = {
		gaps_in = 4,
		gaps_out = 8,
		-- Plate: one hairline, the accent on the focused window, no gradient
		border_size = theme.border_size or 1,
		col = {
			active_border = theme.border_active,
			inactive_border = theme.border_inactive,
		},
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",
	},

	decoration = {
		rounding = theme.rounding or 0, -- `tint shape --radius N`; GTK's --window-radius follows
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		dim_inactive = false,
		dim_strength = 0.4,
		shadow = { enabled = false },
		blur = {
			enabled = true,
			size = 5,
			passes = 4,
			vibrancy = 0.1696,
			noise = 0, -- default ~0.0117 dithering noise reads as visible grain on this HDR panel
		},
	},

	animations = { enabled = true },

	dwindle = { preserve_split = true },
	master = { new_status = "master" },

	-- Scroll layout (uncomment to enable; pair with workspace = 1 rule below)
	-- scrolling = {
	--     column_width = 0.5,
	--     fullscreen_on_one_column = true,
	--     explicit_column_widths = { 0.333, 0.5, 0.667, 1.0 },
	-- },

	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo = true,
		vrr =  0, -- VRR off: LG OLED gamma/brightness flicker under VRR in fullscreen games (was 2, 2026-09-04)
		background_color = "rgb(000000)",
	},

	render = {
		cm_enabled = true,
		cm_auto_hdr = 2, -- HDR always on (EDID profile)
		-- Blur isn't color-managed yet; under HDR/CM it renders grainy without
		-- these (keep_unmodified_copy feeds blur a pre-CM copy, and
		-- use_shader_blur_blend fixes the blend now that copy exists).
		keep_unmodified_copy = true,
		use_shader_blur_blend = true,
	},

xwayland = { force_zero_scaling = true },

	input = {
		kb_layout = "us",
		follow_mouse = 1,
		sensitivity = 0,
		touchpad = { natural_scroll = false },
	},

	-- Pinned to the 0.57.0 default. It keeps direct scanout from going black in
	-- native-Wayland Vulkan games (discussion #14843, NVIDIA included). 0.57.1
	-- flips the default back to false because it blacks out transparent
	-- Quickshell panels on some GPUs (#16736); lastshell renders fine with it on.
	quirks = { skip_non_kms_dmabuf_formats = true },

	-- Nvidia (RTX 4080 / nvidia-open): hardware cursors vanish in fullscreen
	-- games (Godot titles like Dome Keeper hide the HW cursor to draw their
	-- own, and the swap renders nothing). Software cursors fix it everywhere.
	cursor = {
		no_hardware_cursors = true,
		-- "auto" (2) doesn't reliably force a CPU cursor buffer on Nvidia, so
		-- the software cursor blanks on click and only redraws on next input.
		-- Forcing the CPU buffer keeps it damaged/redrawn every frame.
		use_cpu_buffer = true,
	},
})

------------------
--- ANIMATIONS ---
------------------

-- One motion language: the spring drives everything that moves (window
-- open/move, workspace slide), quint drives everything that fades.
-- Enters settle out (easeOutQuint), exits accelerate away (easeInQuint).
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInQuint", { type = "bezier", points = { { 0.5, 0 }, { 0.78, 0 } } })
hl.curve("easeInOutQuint", { type = "bezier", points = { { 0.83, 0 }, { 0.17, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

-- Spring curve for window motion (0.55+). Tune to taste:
--   stiffness ↑ = snappier  •  damping ↓ = more bounce  •  mass ↑ = heavier feel
-- (0.57 renamed dampening to damping; the old key is only a fallback now.)
hl.curve("springy", { type = "spring", mass = 1, stiffness = 71.2633, damping = 15.8273644 })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "springy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, spring = "springy", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.5, bezier = "easeInQuint", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2, bezier = "easeInQuint" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "easeInOutQuint" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "easeInQuint", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.5, bezier = "easeInQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, spring = "springy", style = "slide" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.94, spring = "springy", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, spring = "springy", style = "slide" })
hl.animation({ leaf = "borderangle", enabled = false })

---------------
--- GESTURE ---
---------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

----------------
--- KEYBINDS ---
----------------

require("binds")

--------------------
--- WINDOW RULES ---
--------------------

hl.window_rule({
	name = "suppress-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "xwayland-drag-fix",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

-- Steam
hl.window_rule({
	name = "steam-main",
	match = { class = "^(steam)$", title = "^()$" },
	stay_focused = true,
	min_size = "1 1",
})
hl.window_rule({
	name = "steam-app",
	match = { class = "^(steam_app).*" },
	immediate = true,
})
hl.window_rule({
	name = "steam-notifications",
	match = { class = "^(steam)$", title = "^(notificationtoasts.*)$" },
	no_initial_focus = true,
	no_focus = true,
})

-- Nested compositors (hyprglaze's test harness runs Hyprland inside this one,
-- one aquamarine window per virtual output). Floating keeps the output at the
-- size the harness asked for -- tiled, the host resizes it and every fixed
-- test coordinate lands off-monitor. no_focus so it can never take the
-- keyboard: input for the nested session is injected into it directly, so
-- anything typed here would be going somewhere unintended.
hl.window_rule({
	name = "nested-aquamarine",
	match = { class = "^(aquamarine)$" },
	float = true,
	no_initial_focus = true,
	no_focus = true,
	no_anim = true,
	-- Off-screen from birth: a special workspace nothing ever toggles, so a
	-- test run never appears, not even for the frame before a move. It still
	-- needs frame callbacks there or grim/wlrctl inside it hang (same lesson
	-- as the hoja rule above). `hyprctl dispatch 'hl.dsp.workspace.toggle_special({ name = "harness" })'`
	-- shows it if you want to watch a run.
	workspace = "special:harness silent",
	render_unfocused = true,
})

-- Picture-in-Picture
hl.window_rule({
	name = "helium-pip",
	match = { title = "^(Picture in picture)$" },
	float = true,
	pin = true,
})
hl.window_rule({
	name = "firefox-pip",
	match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" },
	float = true,
	pin = true,
})

-- Floating apps
hl.window_rule({
	name = "mpv-float",
	match = { class = "^(mpv)$" },
	float = true,
	center = true,
})
hl.window_rule({
	name = "scrcpy-float",
	match = { class = "^(scrcpy)$" },
	float = true,
	center = true,
})
hl.window_rule({
	name = "hoja-float",
	match = { class = "^(hoja)$" },
	float = true,
	size = "900 600",
	center = true,
})
hl.window_rule({
	name = "calculator-float",
	match = { class = "^(org.gnome.Calculator)$" },
	float = true,
	center = true,
})
hl.window_rule({
	name = "image-viewer-float",
	match = { class = "^(feh|swayimg|imv)$" },
	float = true,
	center = true,
})

hl.window_rule({
	name = "satty-float",
	match = { class = "^(com.gabm.satty)$" },
	float = true,
	center = true,
})

-- A nested wlroots compositor — sway, run by hoja's interface tests
-- (scripts/sway-harness.sh). Floated at a fixed size because tiled it takes the
-- shape of whatever slot it lands in, and the test clicks rows by coordinate.
-- no_initial_focus rather than no_focus: the harness drives it entirely
-- through wlrctl/wtype scoped to the nested WAYLAND_DISPLAY, which never goes
-- through Hyprland's focus at all, so nothing about the test needs this
-- window focused. Plain no_focus would go one step further and make it
-- permanently unclickable, which would stop you from clicking into it to
-- watch a run by hand.
-- Sent to workspace 2, and `silent` so the view does not follow it there: a
-- test run opens and closes one of these every couple of minutes, and each one
-- would otherwise land on top of whatever is being worked on.
hl.window_rule({
	name = "nested-wlroots",
	match = { class = "^(wlroots)$" },
	float = true,
	size = "1400 900",
	center = true,
	no_initial_focus = true,
	workspace = "2 silent",
	-- Without this the tests stop dead. A window on a workspace that is not
	-- being looked at gets no frame callbacks, so the nested compositor paints
	-- nothing, so hoja inside it never renders past its first frame and every
	-- assertion times out against a listing that is permanently empty.
	render_unfocused = true,
})

hl.window_rule({
	name = "1password-dialog",
	match = { class = "^(1password)$" },
	float = true,
	center = true,
})

-- Dome Keeper (Godot). Cursor fix is the global no_hardware_cursors above;
-- immediate cuts input latency for the game window.
hl.window_rule({
	name = "dome-keeper",
	match = { class = "^(Dome Keeper)$" },
	immediate = true,
})

-- Portal
hl.window_rule({
	name = "portal-gtk",
	match = { class = "^(xdg-desktop-portal-gtk)$" },
	float = true,
	center = true,
})
hl.window_rule({
	name = "portal-gnome",
	match = { class = "^(xdg-desktop-portal-gnome)$" },
	float = true,
	center = true,
})

-- bgen-ui (per-window animation override may need adjustment in 0.55 lua)
hl.window_rule({
	name = "bgen-ui",
	match = { class = "^(bgen-ui)$" },
	float = true,
	size = "800 120",
	center = true,
	no_shadow = true,
	border_size = 0,
	animation = "slide 1 3 default",
})
