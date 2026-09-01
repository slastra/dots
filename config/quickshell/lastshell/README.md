# lastshell

A Quickshell desktop shell for Hyprland. Rosé Pine everywhere.

![lastshell](https://raw.githubusercontent.com/slastra/dots/main/docs/demo.gif)

Two bars, eight modals, and a notification server. Raw
[Quickshell](https://quickshell.org), no framework.

## The shape of it

The bars are tab chips hanging off the screen edges. Four instruments are
drawn with Canvas rather than fonted: an analog clock (hour hand only), a
thermometer whose mercury tracks the CPU package, a speaker whose arcs grow
with volume, and a usage ring that sweeps between quota windows. Icons are
[Lucide](https://lucide.dev); text is ShureTechMono.

The modals share one chrome: a header with an identity icon and a prompt
caret, a scrolling body with a gliding cursor and gold match highlighting,
a hint footer, and an animated backdrop mask.

| Surface | Summon |
|---|---|
| Launcher (windows first by focus recency, then apps by frecency) | `qs ipc call overlays toggleLauncher` |
| Tab switcher (every tab, every browser window, every workspace) | `toggleSwitcher` |
| Audio sink picker | `toggleAudio` |
| Wallpaper effect picker | `toggleEffects` |
| Clipboard history | `toggleClipboard` |
| Notification center | `toggleNotifications` |
| Hotkey sheet | `toggleHotkeys` |
| Capture menu | `toggleCapture` |

Bind them from your compositor config; the IPC calls are the whole
interface. Notifications are the shell's own `NotificationServer`:
urgency-washed toasts with a countdown ring around the dismiss button,
and a history the center reads.

## Runs on

- [Quickshell](https://quickshell.org) 0.3.1, Hyprland (workspace and
  focus integration speak its IPC)
- The [Lucide](https://lucide.dev) icon font, installed as a user font
  (`lucide.ttf` from `lucide-static`)
- ShureTechMono Nerd Font for text

Some widgets pair with daemons that own their data, and degrade quietly
without them:

- [tabstrip](https://github.com/slastra/tabstrip) feeds the browser tab
  strip and the tab switcher
- a Claude Code session daemon feeds the session chips and usage ring
- the capture and hotkey modals shell out to engine scripts (see
  [dots](https://github.com/slastra/dots) for working copies)

## Install

```sh
git clone https://github.com/slastra/lastshell ~/.config/quickshell/lastshell
qs -c lastshell
```

The full working configuration, including the Hyprland Lua config, the
daemons, and the engine scripts, lives in
[dots](https://github.com/slastra/dots).

## Testing

`scripts/test-harness.sh` runs the shell inside a nested Hyprland so
development never touches the session you are sitting in. grim, wtype,
and wlrctl all scope to the nested compositor.

## License

MIT
