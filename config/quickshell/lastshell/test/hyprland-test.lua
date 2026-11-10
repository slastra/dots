-- Minimal Hyprland config for the lastshell test harness (nested instance).
-- Mirrors the live config's Lua dialect but starts nothing except the shell.

hl.monitor({ output = "", mode = "1920x1080@60", position = "0x0", scale = 1.0 })

-- The harness launches qs itself (so it can capture logs); nothing autostarts.

-- Windows in the shell's own language: square, one hairline, the accent on
-- the focused one. The env knobs let a run follow a test scheme, or put the
-- old look (LASTSHELL_TEST_ROUNDING=12, _BORDER=2) beside the new one.
local accent = os.getenv("LASTSHELL_TEST_ACCENT") or "EBBCBA"
local hairline = os.getenv("LASTSHELL_TEST_HAIRLINE") or "403D52"
hl.config({
	general = {
		gaps_in = 4,
		gaps_out = 8,
		border_size = tonumber(os.getenv("LASTSHELL_TEST_BORDER") or "1"),
		col = { active_border = "rgb(" .. accent .. ")", inactive_border = "rgb(" .. hairline .. ")" },
		layout = "dwindle",
	},
	decoration = {
		rounding = tonumber(os.getenv("LASTSHELL_TEST_ROUNDING") or "0"),
		shadow = { enabled = false },
		blur = { enabled = false },
	},
	animations = { enabled = false },
})

-- As in the live config: kitty asks to be maximized on map, which would
-- cover every other test window.
hl.window_rule({
	name = "suppress-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})
