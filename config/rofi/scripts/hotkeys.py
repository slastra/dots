#!/usr/bin/env python3
"""Hotkey cheatsheet for rofi, parsed live from binds.lua.

The point of parsing rather than keeping a second hand-written list is that the
sheet cannot drift. Add a bind, it shows up. Delete one, it disappears.

Layout is done with a monospace pango span on the key column, because the rofi
font is proportional and space padding would not line up otherwise.
"""
from __future__ import annotations

import html
import re
import subprocess
import sys
from pathlib import Path

BINDS = Path.home() / ".config/hypr/binds.lua"
THEME = Path.home() / ".config/rofi/themes/hotkeys.rasi"

MONO = "ShureTechMono Nerd Font"
ROSE, IRIS, MUTED = "#EBBCBA", "#C4A7E7", "#6E6A86"
KEYW = 22  # key column width, in monospace characters

# A section header is a short single-line comment that sits directly above a
# bind. Longer comments are prose explaining the bind under them, not headers.
MAX_HEADER = 40

# Media keys: the raw XF86 name is accurate but unreadable, so each maps to a
# short key label plus what it does.
XF86 = {
    "XF86AudioRaiseVolume": ("Vol +", "Raise volume"),
    "XF86AudioLowerVolume": ("Vol -", "Lower volume"),
    "XF86AudioMute": ("Mute", "Mute output"),
    "XF86AudioMicMute": ("Mic mute", "Mute microphone"),
    "XF86AudioNext": ("Next", "Next track"),
    "XF86AudioPrev": ("Prev", "Previous track"),
    "XF86AudioPlay": ("Play", "Play or pause"),
    "XF86AudioPause": ("Pause", "Play or pause"),
    "Print": ("Print", "Screenshot or record"),
}

# Dispatcher -> label. First match wins, so order matters.
RULES: list[tuple[str, str]] = [
    (r"window\.close",                      "Close window"),
    (r"exit\(",                             "Exit Hyprland"),
    (r"fullscreen.*maximized",              "Maximize"),
    (r"fullscreen.*fullscreen",             "Fullscreen"),
    (r"window\.move.*special:(\w+)",        r"Send to \1 pad"),
    (r"workspace\.toggle_special\(\"(\w+)\"", r"Toggle \1 pad"),
    (r"window\.move.*direction = \"(\w+)\"", r"Move window \1"),
    (r"window\.move.*workspace",            "Move to workspace"),
    (r"focus.*direction = \"(\w+)\"",       r"Focus \1"),
    (r"focus.*workspace = \"previous\"",    "Last workspace"),
    (r"focus.*workspace = \"e\+1\"",        "Next workspace"),
    (r"focus.*workspace = \"e-1\"",         "Previous workspace"),
    (r"focus.*workspace",                   "Go to workspace"),
    (r"window\.drag",                       "Drag window"),
    (r"window\.resize\(\)",                 "Resize window"),
    # Check the negatives first, and require 1-9 on the positives, so that the
    # `x = 0` in a vertical resize never reads as a horizontal one.
    (r"window\.resize.*x = -\d",            "Shrink horizontally"),
    (r"window\.resize.*y = -\d",            "Shrink vertically"),
    (r"window\.resize.*x =\s*[1-9]",        "Grow horizontally"),
    (r"window\.resize.*y =\s*[1-9]",        "Grow vertically"),
    (r"submap\(\"reset\"\)",                "Leave resize mode"),
    (r"submap\(\"(\w+)\"\)",                r"Enter \1 mode"),
]

# exec_cmd payload -> label, matched on the command text.
EXEC = [
    (r"rofi/scripts/(\w+)\.(?:sh|py)", None),        # handled specially below
    (r"hyprpicker",             "Pick a colour"),
    (r"kasactl",                "Toggle the office light"),
    (r"scrcpy",                 "Mirror the phone"),
    (r"wpctl set-volume.*%\+",  "Volume up"),
    (r"wpctl set-volume.*%-",   "Volume down"),
    (r"wpctl set-mute.*SOURCE", "Mute microphone"),
    (r"wpctl set-mute",         "Mute output"),
    (r"playerctl next",         "Next track"),
    (r"playerctl previous",     "Previous track"),
    (r"playerctl play-pause",   "Play or pause"),
]

# lastshell overlay IPC calls (the binds moved off rofi scripts 2026-08-31).
IPC = {
    "toggleLauncher":      "App & window launcher",
    "toggleSwitcher":      "Browser tabs",
    "toggleAudio":         "Audio output",
    "toggleEffects":       "Wallpaper effect",
    "toggleClipboard":     "Clipboard history",
    "toggleNotifications": "Notification history",
    "toggleCapture":       "Screenshot or record",
    "toggleHotkeys":       "This cheatsheet",
}

SCRIPTS = {
    "tabs":          "Browser tabs",
    "audio":         "Audio output",
    "effect":        "Wallpaper effect",
    "clipboard":     "Clipboard history",
    "notifications": "Notification history",
    "capture":       "Screenshot or record",
    "hotkeys":       "This cheatsheet",
}


def label_for(dispatcher: str, consts: dict[str, str]) -> str:
    """Turn a Lua dispatcher expression into something a human reads."""
    if dispatcher.startswith("function"):
        return "Float and centre"

    m = re.search(r"exec_cmd\((.+)\)\s*$", dispatcher)
    if m:
        payload = m.group(1).strip()
        if payload in consts:                      # exec_cmd(terminal)
            resolved = consts[payload]
            if "rofi" in resolved:
                return "Application launcher"
            return resolved.split()[0].capitalize()
        s = re.search(r"rofi/scripts/(\w+)\.(?:sh|py)", payload)
        if s:
            return SCRIPTS.get(s.group(1), s.group(1).capitalize())
        i = re.search(r"ipc call overlays (\w+)", payload)
        if i:
            return IPC.get(i.group(1), i.group(1))
        b = re.search(r"\.local/bin/([\w-]+)", payload)
        if b:
            return b.group(1).replace("-", " ").capitalize()
        for pat, name in EXEC:
            if name and re.search(pat, payload):
                return name
        return payload.strip('"').split()[0].capitalize()

    for pat, name in RULES:
        m = re.search(pat, dispatcher)
        if m:
            return re.sub(r"\\(\d)", lambda g: m.group(int(g.group(1))), name) \
                if "\\" in name else name
    return dispatcher.replace("hl.dsp.", "").rstrip("()")


def parse() -> list[tuple[str, list[tuple[str, str]]]]:
    lines = BINDS.read_text().splitlines()
    consts = dict(re.findall(r'^local (\w+)\s*=\s*"([^"]*)"', "\n".join(lines), re.M))

    sections: list[tuple[str, list[tuple[str, str]]]] = []
    current = "General"
    rows: list[tuple[str, str]] = []

    def flush():
        nonlocal rows
        if rows:
            sections.append((current, rows))
            rows = []

    in_submap = False
    in_loop = False
    for i, line in enumerate(lines):
        stripped = line.strip()

        # Section header: a short comment directly above a bind or the ws loop.
        # A comment whose previous line is also a comment is a continuation of
        # a prose block, not a header.
        if stripped.startswith("--") and len(stripped) <= MAX_HEADER:
            prev = lines[i - 1].strip() if i else ""
            # Skip any prose comment lines between the header and its binds.
            nxt = next((l.strip() for l in lines[i + 1:]
                        if l.strip() and not l.strip().startswith("--")), "")
            if nxt.startswith(("hl.bind", "for ")) and not prev.startswith("--"):
                flush()
                current = stripped.lstrip("- ").strip()
                continue

        # The workspace loop generates 20 binds. Summarise it as two rows and
        # skip its body, or every iteration's bind is re-parsed with no key.
        if stripped.startswith("for i = 1, 10"):
            rows.append(("SUPER + 1 … 0", "Go to workspace"))
            rows.append(("SUPER + SHIFT + 1 … 0", "Move window to workspace"))
            in_loop = True
            continue
        if in_loop:
            if stripped == "end":
                in_loop = False
            continue

        if stripped.startswith("hl.define_submap"):
            in_submap = True
            continue
        if in_submap and stripped == "end)":
            in_submap = False
            continue

        m = re.match(r"hl\.bind\((.+?),\s*(.+?)(?:,\s*\{.*\})?\)?\s*$", stripped)
        if not (stripped.startswith("hl.bind") and m):
            continue

        keyexpr, dispatcher = m.group(1).strip(), m.group(2).strip().rstrip(",")

        # mod .. " + X"  ->  SUPER + X   |   "XF86..."  ->  itself
        km = re.match(r'mod\s*\.\.\s*"\s*\+\s*(.+?)"', keyexpr)
        if km:
            key = f"SUPER + {km.group(1).strip()}"
        else:
            key = keyexpr.strip('"')
            if in_submap:
                key = f"  {key}"

        key = key.replace("mouse_down", "Scroll down").replace("mouse_up", "Scroll up")
        key = key.replace("slash", "/").replace("escape", "ESC")
        key = re.sub(r"mouse:272", "Left drag", key)
        key = re.sub(r"mouse:273", "Right drag", key)

        if key.strip() in XF86:
            key, desc = XF86[key.strip()]
        else:
            desc = label_for(dispatcher, consts)
        rows.append((key, desc))

    flush()
    return sections


def render(sections) -> str:
    out = []
    for name, rows in sections:
        out.append(f'<span foreground="{IRIS}"><b>{html.escape(name.upper())}</b></span>')
        for key, desc in rows:
            pad = key.ljust(KEYW)
            out.append(
                f'<span font_family="{MONO}" foreground="{ROSE}">{html.escape(pad)}</span>'
                f'{html.escape(desc)}'
            )
        out.append(f'<span foreground="{MUTED}"> </span>')
    return "\n".join(out[:-1])


def main() -> int:
    if not BINDS.exists():
        print(f"no binds file at {BINDS}", file=sys.stderr)
        return 1
    if "--json" in sys.argv:
        # For lastshell's hotkey sheet: same live parse, structured output.
        import json
        print(json.dumps([
            {"section": name, "rows": [{"key": k, "desc": d} for k, d in rows]}
            for name, rows in parse()
        ]))
        return 0
    body = render(parse())
    subprocess.run(
        ["rofi", "-dmenu", "-i", "-markup-rows", "-p", "󰌌 ",
         "-selected-row", "1", "-theme", str(THEME)],
        input=body, text=True, capture_output=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
