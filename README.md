# dots

Desktop configuration for `desk`.
Arch Linux, Hyprland, Quickshell, Rosé Pine.

![The desktop in motion](docs/demo.gif)

Full quality: [docs/demo.mp4](docs/demo.mp4).

## Session

greetd starts tuigreet. tuigreet starts Hyprland.
`hyprland.lua` then starts the desktop.

| Program | Function |
|---|---|
| `lastshell` | The shell. Two bars, eight modals, notifications. Quickshell. |
| `tabstrip` | Browser-tab daemon. Feeds the bar strip and the tab switcher. |
| `claude-status.py` | Claude Code session daemon. Feeds the session chips. |
| `hyprglaze` | Shader wallpaper daemon. It draws the wallpaper. |
| `idle.sh` | Idle timers. It calls `scripts/tv-screen.sh`. |
| `wl-paste` | Clipboard watcher. It stores history in `cliphist`. |

Hyprland reads the Lua files. Hyprland reloads the configuration when you save a
file. Do not run `hyprctl reload`.

## lastshell

`config/quickshell/lastshell` is the shell (a vendored copy of
[slastra/lastshell](https://github.com/slastra/lastshell)). Raw Quickshell,
no framework.

The bars are tab chips hanging off the screen edges. Four instruments are
drawn, not fonted: an analog clock (hour hand only), a thermometer, a
speaker whose arcs grow with volume, and a usage ring. Icons are
[Lucide](https://lucide.dev); text is ShureTechMono. Nerd-font icon glyphs
are banned. Qt renders their private-use codepoints wrong.

The modals share one chrome: header with an identity icon and a prompt
caret, scrolling body with a gliding cursor and gold match highlighting,
hint footer, animated backdrop mask.

| Bind | Modal |
|---|---|
| `SUPER + Space` | Launcher. Open windows first, by focus recency, then apps by frecency. |
| `SUPER + W` | Tab switcher. Every tab in every browser window, globally. |
| `SUPER + A` | Audio sink picker. |
| `SUPER + B` | Wallpaper effect picker. |
| `SUPER + V` | Clipboard history. |
| `SUPER + N` | Notification center. |
| `SUPER + /` | Hotkey sheet, parsed live from `binds.lua`. It cannot drift. |
| `Print` | Capture menu. Stops a recording instantly if one is running. |

Notifications are lastshell's own server: urgency-washed toasts with a
countdown ring around the dismiss button, and a history the center reads.

## Daemons

The shell renders; daemons own data. `tabstrip` (Go,
[repo](https://github.com/slastra/tabstrip)) watches browsers over D-Bus
and writes a snapshot the shell's FileView watches. The bar strip is
workspace-filtered; `tabstrip list` is the global view. `claude-status.py`
(`config/claude/`) watches Claude Code sessions, usage quotas, Hyprland
focus, and MQTT face state, and writes one JSON snapshot.

## Engines

Two rofi-era scripts survive as backends with the menus stripped off:
`capture.sh` (grim/slurp/satty screenshots and gpu-screen-recorder capture,
invoked by subcommand from the capture modal) and `hotkeys.py` (the live
binds.lua parser behind the hotkey sheet, `--json`).

## The TV

The display is an LG OLED. `scripts/tv-screen.sh` turns the TV itself off
and on over the LAN instead of using DPMS. A DPMS wake forces an HDMI
2.1 FRL retrain the NVIDIA driver refuses to retry, which latches the
desktop at 60 Hz. `scripts/tv-pixel-refresh.sh` runs the panel's pixel
cleaning nightly by driving the TV's own menus over the remote-control
API.

## Layout

```
config/
├── quickshell/lastshell/   the shell (QML)
├── hypr/                   hyprland.lua, binds.lua, theme.lua, idle.sh, scripts/
├── claude/                 claude-status.py
├── rofi/scripts/           capture.sh, hotkeys.py (engines, menuless)
├── mako/scripts/           lamp.sh (notification lamp hook)
├── qt6ct/colors/           rose-pine.conf (Qt palette)
├── kitty/                  kitty.conf, colors.conf
├── nvim/lua/               colors.lua
└── starship.toml
```

## Components

- [lastshell](https://github.com/slastra/lastshell), the shell itself
- [tabstrip](https://github.com/slastra/tabstrip), the browser-tab daemon
- [tabctl](https://github.com/slastra/tabctl), the D-Bus mediator underneath
- [Rosé Pine](https://rosepinetheme.com), the palette everywhere

## License

MIT
