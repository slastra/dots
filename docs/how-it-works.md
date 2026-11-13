# How it works

The detail behind the README: how the shell is drawn, how one scheme reaches
every app, and which daemons feed the bars.

## lastshell

`config/quickshell/lastshell` is the shell (a vendored copy of
[slastra/lastshell](https://github.com/slastra/lastshell), last synced at `074fb3d`). Raw Quickshell,
no framework.

The bars are zones: flat plates flush to the screen edges, each a row of
items divided by hairlines. Hovering an item unfolds a popout from its plate,
and every popout shares one layout. Four instruments are
drawn, not fonted: an analog clock (hour hand only), a thermometer, a
speaker whose arcs grow with volume, and a usage ring. Icons are
[Lucide](https://lucide.dev). Text is Martian Mono unless the Look dialog
picks another font pair. Nerd-font icon glyphs are not used: Qt renders their
private-use codepoints wrong.

The modals share one chrome: header with an identity icon and a prompt
caret, scrolling body with a gliding cursor and match highlighting,
hint footer, animated backdrop mask.

Notifications are lastshell's own server: toasts with an urgency rule on the
left and a countdown line along the bottom, and a history the center reads.

## Theming

Nothing here is colored by hand. A scheme is 16 ANSI colors plus a
background and a foreground, and `tint apply NAME` renders it into every
file listed in `config/tint/targets.toml`: kitty, Hyprland's borders, GTK 3
and 4, Qt, fish, Starship, Neovim, Zed, hoja, mpv, hyprglaze, the keyboard's
LEDs, and a generated icon and cursor theme. `tint look` sets the corner
radius, border thickness, accent colors, and font pair the same way.

- `config/tint/templates/` holds each of those files with `{{key}}` where a
  color goes. The files marked "generated" in the README's layout are their
  output, committed as whatever scheme was applied at the last sync.
- lastshell is not a target. It reads kitty's `colors.conf` itself and gives
  each ANSI slot one role: an accent for what is active, warning and critical
  colors for what needs attention, and plain text for everything else.
- `config/tint/schemes/Vague.conf` is the default scheme,
  [Vague](https://github.com/vague2k/vague.nvim) on a true black background.
  The other 365 are the [Gogh](https://github.com/Gogh-Co/Gogh) collection,
  which ships with tint.
- `hooks/assets` rebuilds the `Tint` icon and cursor theme: Papirus folders in
  the accent, and the BreezeX cursor shapes in the scheme's own dark and light.
  It expects Papirus, `hyprcursor-util`, `rsvg-convert` and `xcursorgen`.
- `hooks/fonts` hands the font pair to GTK, Qt and mpv, which keep fonts in
  their own settings files. The pairs are listed in `config/tint/fonts.toml`.
- `hooks/start-page` sends the palette to a personal start page. It does
  nothing without its env file, which is not in this repo.

## Daemons

The shell renders; daemons own data. `tabstrip` (Go,
[repo](https://github.com/slastra/tabstrip)) watches browsers over D-Bus
and writes a snapshot the shell's FileView watches. The bar strip is
workspace-filtered; `tabstrip list` is the global view. `claude-status.py`
(lastshell's `scripts/`) watches Claude Code sessions, usage quotas, Hyprland
focus, and MQTT face state, and writes one JSON snapshot.

## Engines

`hotkeys.py` is a rofi-era script kept as a backend with its menu stripped
off: the live binds.lua parser behind the hotkey sheet (`--json`). It and the
capture engine, `capture.sh`, live in lastshell's `scripts/`.
