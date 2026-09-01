local mod = "SUPER"
local terminal    = "kitty"
local fileManager = "hoja"
local menu        = "rofi -no-config -no-lazy-grab -show combi -modi combi run -show-icons -theme ~/.config/rofi/themes/launcher.rasi"

-- Apps
hl.bind(mod .. " + Return",     hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Space",      hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleLauncher"))
hl.bind(mod .. " + G",          hl.dsp.exec_cmd("python3 ~/.config/hypr/scripts/float-arrange.py")) -- gather floats
hl.bind(mod .. " + W",          hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleSwitcher"))
hl.bind(mod .. " + A",          hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleAudio"))
hl.bind(mod .. " + B",          hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleEffects"))
hl.bind(mod .. " + C",          hl.dsp.exec_cmd("hyprpicker -a"))
hl.bind(mod .. " + E",          hl.dsp.exec_cmd(fileManager))
-- Clipboard history. cliphist only has content because hyprland.lua starts a
-- `wl-paste --watch cliphist store` daemon; without it the picker is empty.
hl.bind(mod .. " + V",          hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleClipboard"))
-- Office light: toggle the Kasa HS210 directly over the LAN (no cloud/IFTTT).
-- SUPER+L was the old binding but it now means focus-right, so SUPER+O ("Office").
hl.bind(mod .. " + O",          hl.dsp.exec_cmd("python /home/shaun/Projects/Python/kasactl/kasactl.py toggle 192.168.11.97"))
-- Phone mirror: toggle scrcpy over wireless adb (Pixel 8a). adb tcpip mode resets on
-- phone reboot; plug in USB once and run `adb tcpip 5555` to re-arm. --no-audio keeps
-- sound on the phone; drop it to pipe audio to the desktop.
hl.bind(mod .. " + P",          hl.dsp.exec_cmd("sh -c 'pkill -x scrcpy || scrcpy --tcpip=192.168.11.131:5555 --no-audio'"))
-- Read aloud ("T" for talk): speaks the primary selection, falling back to the
-- clipboard, through piper-tts. Pressing it again while something is playing
-- replaces the queue with the new selection rather than opening a second window.
hl.bind(mod .. " + T",          hl.dsp.exec_cmd("/home/shaun/.local/bin/piper-reader"))

-- Window management
hl.bind(mod .. " + SHIFT + C",  hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + Q",  hl.dsp.exit())
hl.bind(mod .. " + M",          hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }))
hl.bind(mod .. " + F",          hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mod .. " + S", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.center())
end)

-- Focus (vim keys)
hl.bind(mod .. " + H",          hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + L",          hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + K",          hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + J",          hl.dsp.focus({ direction = "down" }))

-- Move window (vim keys)
hl.bind(mod .. " + SHIFT + H",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + L",  hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. " + SHIFT + K",  hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + J",  hl.dsp.window.move({ direction = "down" }))

-- Scroll-layout column-width cycle (not currently used)
-- hl.bind(mod .. " + comma",  hl.dsp.layout("column_widths -1"))
-- hl.bind(mod .. " + period", hl.dsp.layout("column_widths +1"))

-- Workspaces
for i = 1, 10 do
    local key = i % 10 -- 10 maps to 0
    hl.bind(mod .. " + " .. key,          hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad (Hyprland special workspace). SUPER+D shows/hides it, SUPER+SHIFT+D
-- throws the focused window into it.
hl.bind(mod .. " + D",          hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mod .. " + SHIFT + D",  hl.dsp.window.move({ workspace = "special:scratch" }))

hl.bind(mod .. " + Tab",        hl.dsp.focus({ workspace = "previous" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse move/resize
hl.bind(mod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- No reload bind: Hyprland live-reloads the Lua on save, and `hyprctl reload`
-- is not wanted here.

-- Resize submap
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("H",      hl.dsp.window.resize({ x = -20, y = 0,  relative = true }), { repeating = true })
    hl.bind("L",      hl.dsp.window.resize({ x =  20, y = 0,  relative = true }), { repeating = true })
    hl.bind("K",      hl.dsp.window.resize({ x = 0,  y = -20, relative = true }), { repeating = true })
    hl.bind("J",      hl.dsp.window.resize({ x = 0,  y =  20, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)

-- Volume and media
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })

hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- No XF86MonBrightness binds: this box has no backlight device, so brightnessctl
-- falls through to the first LED it finds and dims the NIC port light. Panel
-- brightness lives on the TV and in scripts/tv-screen.sh.

-- Screencast / notifications
hl.bind(mod .. " + N",          hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleNotifications"))
hl.bind("Print",                hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleCapture"))

-- Help
-- The cheatsheet parses this file, so it never needs updating by hand.
hl.bind(mod .. " + slash",      hl.dsp.exec_cmd("qs -c lastshell ipc call overlays toggleHotkeys"))
