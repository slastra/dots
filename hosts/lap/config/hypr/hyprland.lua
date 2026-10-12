-- Hyprland config — Lua (0.55+)
-- The laptop's copy of the desk's config (desk.lastra:~/.config/hypr). Look,
-- motion, binds and the lastshell session are the desk's; the monitor,
-- input, idle and power pieces are the laptop's own.

local theme = require("theme")

-- On battery: 60 Hz, no blur (~2.6 W less during fullscreen video) and no
-- borderangle loop (~2 W at idle: it redraws every frame), and VRR off so
-- the panel can self-refresh (PSR2).
-- scripts/power-watch.sh reloads the config when the adapter changes.
local function on_ac()
    local f = io.open("/sys/class/power_supply/ADP1/online")
    if not f then return true end
    local v = f:read("*l")
    f:close()
    return v == "1"
end
local ac = on_ac()
-- Eco mode (scripts/eco.sh, Super+Shift+E) keeps the lean look on AC too
-- and also turns animations off.
local eco_file = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/eco"
local eco = false
do
    local f = io.open(eco_file)
    if f then f:close(); eco = true end
end
local full = ac and not eco

----------------
--- MONITORS ---
----------------

hl.monitor({
    output   = "eDP-1",
    mode     = full and "2880x1800@120" or "2880x1800@60",
    position = "0x0",
    scale    = 1.5,
})

-----------------
--- AUTOSTART ---
-----------------

hl.on("hyprland.start", function()
    -- lastshell (Quickshell) replaces waybar and dunst, as on the desk; see
    -- ~/Projects/Quickshell/lastshell. Its two data daemons run standalone:
    -- tabstrip writes the browser-tab snapshot, claude-status the session
    -- snapshot (LASTSHELL_STANDALONE disables its die-with-waybar coupling).
    hl.exec_cmd("qs -c lastshell &")
    hl.exec_cmd("~/.local/bin/tabstrip daemon &")
    hl.exec_cmd("~/.config/hypr/scripts/power-watch.sh &")
    hl.exec_cmd("env LASTSHELL_STANDALONE=1 ~/.config/lastshell/claude-status.py --daemon &")
    hl.exec_cmd("/home/shaun/go/bin/deskpresence input active; hypridle &")
    -- Clipboard history store. Without this daemon cliphist records nothing and
    -- the SUPER+V picker comes up empty.
    hl.exec_cmd("wl-paste --watch cliphist store &")
    -- Polkit agent: the password/fingerprint prompt behind 1Password's system
    -- unlock, fprintd-enroll and GUI admin actions. Started before 1Password.
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent &")
    hl.exec_cmd("1password --ozone-platform-hint=wayland &")
    -- hyprglaze runs as a user service so scripts/power-watch.sh can stop it
    -- on battery and start it on AC. Start it only after the env update (the
    -- unit needs WAYLAND_DISPLAY), and only on AC out of eco; otherwise the
    -- still wallpaper (wallpaper-still.service: hyprpaper, walls/mesh.png).
    -- The units swap the two from then on.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XCURSOR_THEME XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE"
        .. " && if [ \"$(cat /sys/class/power_supply/ADP1/online)\" = 1 ] && [ ! -f ~/.local/state/eco ];"
        .. " then systemctl --user start hyprglaze.service;"
        .. " else systemctl --user start wallpaper-still.service; fi")
end)

-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------

-- Qt6 apps need the qt6ct platformtheme plugin. Palette:
-- ~/.config/qt6ct/colors/rose-pine.conf.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- BreezeX Rosé Pine, copied from the desk (~/.local/share/icons): hyprcursors/
-- for Hyprland, cursors/ (Xcursor) for GTK, Qt and XWayland. The greeter needs
-- a copy in /usr/share/icons too, since it can't read ~/.local/share/icons.
hl.env("XCURSOR_THEME",       "BreezeX-RosePine")
hl.env("HYPRCURSOR_THEME",    "BreezeX-RosePine")
hl.env("XCURSOR_SIZE",        "32")
hl.env("HYPRCURSOR_SIZE",     "32")
hl.env("XDG_SESSION_TYPE",    "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

---------------------
--- LOOK AND FEEL ---
---------------------

hl.config({
    general = {
        gaps_in = theme.brutal and 12 or 4,
        gaps_out = theme.brutal and 20 or 8,
        border_size = theme.brutal and 4 or 2,
        col = theme.brutal and {
            active_border = theme.brutal_active,
            inactive_border = theme.brutal_inactive,
        } or {
            active_border = { colors = { theme.border_1, theme.border_2, theme.border_3 }, angle = 45 },
            inactive_border = theme.border_inactive,
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = theme.brutal and 0 or 12, -- 12 = libadwaita --window-radius default
        active_opacity = 1.0,
        inactive_opacity = 1.0, -- <1 makes every unfocused window blur its background
        dim_inactive = false,
        dim_strength = 0.4,
        shadow = theme.brutal and {
            enabled = true,
            range = 2,        -- near-hard edge; 0 renders nothing
            render_power = 1,
            offset = "8 8",
            color = theme.brutal_shadow,
            color_inactive = theme.brutal_shadow_inactive,
        } or { enabled = false },
        blur = {
            enabled = not theme.brutal and full,
            size = 5,
            passes = 4,
            vibrancy = 0.1696,
        },
    },

    animations = { enabled = not eco },

    dwindle = { preserve_split = true },
    master = { new_status = "master" },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = full and 1 or 0, -- VRR disables i915 panel self refresh (PSR2): 4.17 W -> 2.52 W idle without it
        background_color = "rgb(13111e)",
    },

    xwayland = { force_zero_scaling = true },

    -- Fullscreen windows that qualify (an opaque single surface, e.g. mpv with
    -- --gpu-api=opengl) go straight to the panel, skipping compositing.
    render = { direct_scanout = 1 },

    input = {
        kb_layout = "us",
        numlock_by_default = true,
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            disable_while_typing = true,
            natural_scroll = false,
        },
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
--   stiffness ↑ = snappier  •  dampening ↓ = more bounce  •  mass ↑ = heavier feel
hl.curve("springy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

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
hl.animation({ leaf = "borderangle", enabled = not theme.brutal and full, speed = 30, bezier = "linear", style = "loop" })

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

-- Nested compositors (lastshell's test harness runs Hyprland inside this one).
-- Off-screen from birth on a special workspace nothing toggles; it still
-- needs frame callbacks there or grim inside it hangs. no_focus so it can
-- never take the keyboard.
hl.window_rule({
    name = "nested-aquamarine",
    match = { class = "^(aquamarine)$" },
    float = true,
    no_initial_focus = true,
    no_focus = true,
    no_anim = true,
    workspace = "special:harness silent",
    render_unfocused = true,
})

-- A nested wlroots compositor — sway, run by hoja's interface tests
-- (scripts/sway-harness.sh). Floated at a fixed size because the test clicks
-- rows by coordinate; sent to workspace 2 silently so runs never land on top
-- of the work; render_unfocused or the nested compositor never paints.
hl.window_rule({
    name = "nested-wlroots",
    match = { class = "^(wlroots)$" },
    float = true,
    size = "1400 900",
    center = true,
    no_initial_focus = true,
    workspace = "2 silent",
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
    name = "nemo-float",
    match = { class = "^(nemo)$" },
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
hl.window_rule({
    name = "1password-float",
    match = { class = "^(1[Pp]assword)$" },
    float = true,
    center = true,
})
hl.window_rule({
    name = "roku-remote-float",
    match = { class = "^(io.github.roku_remote)$" },
    float = true,
    center = true,
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

-- WORKAROUND (Hyprland 0.56.2): leaving direct scanout doesn't damage the whole
-- output, so unchanged areas (window borders) show stale pixels until a
-- workspace switch. Fixed upstream (CMonitor::handleDSleave now calls
-- m_damage.damageEntire()); remove this once a release includes it.
-- Re-setting border_size (to the same value) trips REFRESH_WINDOW_STATES:
-- every monitor is damaged and gets 2 full frames, with no visible change.
local function redraw_after_scanout()
    hl.timer(function()
        hl.config({ general = { border_size = theme.brutal and 4 or 2 } })
        hl.exec_scheduled_prop_refresh_immediately()
    end, { timeout = 150, type = "oneshot" })
end
hl.on("window.fullscreen", function(w)
    if w.fullscreen == 0 then redraw_after_scanout() end
end)
hl.on("window.close", function(w)
    if w.fullscreen ~= 0 then redraw_after_scanout() end
end)
