# dots

My Hyprland desktop config: lastshell, hyprglaze, and kitty, themed from one terminal color scheme.

![The desktop in motion](docs/demo.gif)

Full quality: [docs/demo.mp4](docs/demo.mp4).

Desktop configuration for `desk`.
Arch Linux, Hyprland, Quickshell. One terminal color scheme colors everything,
and [tint](https://github.com/slastra/tint) applies it. `hosts/lap` is the laptop.

## Usage

| Bind | Modal |
|---|---|
| `SUPER + Space` | Launcher. Open windows first, by focus recency, then apps by frecency. |
| `SUPER + W` | Tab switcher. Every tab in every browser window, globally. |
| `SUPER + A` | Audio sink picker. |
| `SUPER + B` | Wallpaper effect picker. |
| `SUPER + SHIFT + B` | Color scheme picker. Previews on the live desktop as you move; Tab narrows to dark or light. |
| `SUPER + V` | Clipboard history. |
| `SUPER + N` | Notification center. |
| `SUPER + /` | Hotkey sheet, parsed live from `binds.lua`. It cannot drift. |
| `Print` | Capture menu. Stops a recording instantly if one is running. |
| `SUPER + X` | Dictation. Tap to talk, tap to stop; the transcript comes back cleaned up for the window it is headed to, and Enter pastes it there. |

`SUPER + T` reads the selection (else the clipboard) aloud. The player is
a chip on the bottom bar, not a modal: hover it for the passage, progress,
speed, voice and tidy. `SUPER + SHIFT + T` pauses, `SUPER + CTRL + T` stops.

Hyprland reads the Lua files. Hyprland reloads the configuration when you save a
file. Do not run `hyprctl reload`.

## Layout

```
config/
├── quickshell/lastshell/   the shell (QML)
├── hypr/                   hyprland.lua, binds.lua, theme.lua, hypridle.conf, hyprglaze.toml, scripts/
├── lastshell/              lamp.sh (shell-adjacent)
├── tint/                   targets.toml, templates/, schemes/, hooks/ (the theming setup)
├── qt6ct/colors/           tint.conf (Qt palette, generated)
├── kitty/                  kitty.conf, colors.conf (generated, and the shell's palette source)
├── nvim/lua/               colors.lua (generated), plugins/vague.lua
└── starship.toml
hosts/lap/                  the laptop (below)
```

## The TV

The display is an LG OLED. `scripts/tv-screen.sh` turns the TV itself off
and on over the LAN instead of using DPMS. A DPMS wake forces an HDMI
2.1 FRL retrain the NVIDIA driver refuses to retry, which latches the
desktop at 60 Hz. `scripts/tv-pixel-refresh.sh` runs the panel's pixel
cleaning nightly by driving the TV's own menus over the remote-control
API. `scripts/lg-ipctl.py` speaks the TV's encrypted IP-control protocol;
its key lives in `~/.config/lgtv/ipcontrol.key`, outside this repo.

`deskpresence` (radar presence) owns blanking the TV. `scripts/tv-watchdog.sh`
is the fallback: if `deskpresence` has died, it blanks the TV after 10
minutes without input. `scripts/unblank.sh` lifts lastshell's blackout
shader on input if a crash left it applied.

## The laptop

`hosts/lap` is a Lenovo Slim 7 14IRP8 running the same lastshell checkout
with its own Hyprland config: time-of-flight presence, perceptual
brightness, a Wi-Fi picker, an eco mode and the root-owned power tweaks.
[docs/laptop.md](docs/laptop.md) has the details.

## How it works

### Session

greetd starts lastshell's greeter. The greeter starts Hyprland.
`hyprland.lua` starts lastshell itself (it is the session's polkit agent,
and apps it launches get their own scopes). Everything else is a systemd
user unit on `graphical-session.target`, which Hyprland 0.57 starts with
the session:

```sh
systemctl --user enable hyprglaze.service hypridle.service cliphist.service   # packaged units
systemctl --user enable ~/Projects/Go/tabstrip/systemd/tabstrip.service \
    ~/.config/quickshell/lastshell/systemd/claude-status.service           # from their repos
```

| Program | Function |
|---|---|
| `lastshell` | The shell. Two bars, nine modals, notifications, a narrator. Quickshell. |
| `tabstrip` | Browser-tab daemon. Feeds the bar strip and the tab switcher. |
| `claude-status.py` | Claude Code session daemon, in lastshell's `scripts/`. Feeds the session chips. |
| `hyprglaze` | Shader wallpaper daemon. It draws the wallpaper. |
| `hypridle` | Idle timers (`hypridle.conf`). They report input to `deskpresence` and run `scripts/tv-watchdog.sh`. |
| `cliphist` | Clipboard history (`cliphist.service` runs the `wl-paste` watcher). |

### lastshell

`config/quickshell/lastshell` is the shell (a vendored copy of
[slastra/lastshell](https://github.com/slastra/lastshell), last synced at `7761828`). Raw Quickshell,
no framework.

The bars are zones: flat plates flush to the screen edges, each a row of
items divided by hairlines. Hovering an item unfolds a popout from its plate,
and every popout shares one layout. Four instruments are
drawn, not fonted: an analog clock (hour hand only), a thermometer, a
speaker whose arcs grow with volume, and a usage ring. Icons are
[Lucide](https://lucide.dev); text is ShureTechMono. Nerd-font icon glyphs
are banned. Qt renders their private-use codepoints wrong.

The modals share one chrome: header with an identity icon and a prompt
caret, scrolling body with a gliding cursor and gold match highlighting,
hint footer, animated backdrop mask.

Notifications are lastshell's own server: toasts with an urgency rule on the
left and a countdown line along the bottom, and a history the center reads.

### Theming

Nothing here is colored by hand. A scheme is 16 ANSI colors plus a
background and a foreground, and `tint apply NAME` renders it into every
file listed in `config/tint/targets.toml`: kitty, Hyprland's borders, GTK 3
and 4, Qt, fish, Starship, Neovim, Zed, mpv, hyprglaze, the keyboard's LEDs,
and a generated icon and cursor theme. `tint shape --radius N --border N`
sets corner radius and border thickness the same way.

- `config/tint/templates/` holds each of those files with `{{key}}` where a
  color goes. The files marked "generated" in the layout above are their
  output, committed as whatever scheme was applied at the last sync.
- lastshell is not a target. It reads kitty's `colors.conf` itself and gives
  each ANSI slot one role: an accent for what is active, warning and critical
  colors for what needs attention, and plain text for everything else.
- `config/tint/schemes/Vague.conf` is the default scheme,
  [Vague](https://github.com/vague2k/vague.nvim) on a true black background.
- `hooks/assets` rebuilds the `Tint` icon and cursor theme: Papirus folders in
  the accent, and the BreezeX cursor shapes in the scheme's own dark and light.
  It expects Papirus, `hyprcursor-util`, `rsvg-convert` and `xcursorgen`.
- `hooks/start-page` sends the palette to a personal start page. It does
  nothing without its env file, which is not in this repo.

To use it, install [tint](https://github.com/slastra/tint) and copy
`config/tint` to `~/.config/tint`. Run `tint check` first: targets for apps
you do not have will fail there, and can be deleted from `targets.toml`.

### Daemons

The shell renders; daemons own data. `tabstrip` (Go,
[repo](https://github.com/slastra/tabstrip)) watches browsers over D-Bus
and writes a snapshot the shell's FileView watches. The bar strip is
workspace-filtered; `tabstrip list` is the global view. `claude-status.py`
(lastshell's `scripts/`) watches Claude Code sessions, usage quotas, Hyprland
focus, and MQTT face state, and writes one JSON snapshot.

### Engines

`hotkeys.py` is a rofi-era script kept as a backend with its menu stripped
off: the live binds.lua parser behind the hotkey sheet (`--json`). It and the
capture engine, `capture.sh`, live in lastshell's `scripts/`.

## Components

- [lastshell](https://github.com/slastra/lastshell), the shell itself
- [tabstrip](https://github.com/slastra/tabstrip), the browser-tab daemon
- [tabctl](https://github.com/slastra/tabctl), the D-Bus mediator underneath
- [tint](https://github.com/slastra/tint), the theming tool
- [Vague](https://github.com/vague2k/vague.nvim), the default scheme, and [Gogh](https://github.com/Gogh-Co/Gogh), the collection the rest come from

## License

GPL-3.0. See [LICENSE](LICENSE).
