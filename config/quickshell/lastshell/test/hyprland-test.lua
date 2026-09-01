-- Minimal Hyprland config for the lastshell test harness (nested instance).
-- Mirrors the live config's Lua dialect but starts nothing except the shell.

hl.monitor({ output = "", mode = "1920x1080@60", position = "0x0", scale = 1.0 })

-- The harness launches qs itself (so it can capture logs); nothing autostarts.
