#!/usr/bin/env python3
"""Mouse and keyboard input for screen recordings: click ripples, the key
display, and the timing of the click/key sounds mixed into the video.

overlays/InputCast.qml runs this only while gpu-screen-recorder is recording.
Wayland gives clients no global input, so devices are read straight from
evdev (the user is in the `input` group, no root needed) and Hyprland is asked
where the cursor is.

stdout is EngineProcess's line protocol, `<name> <json>`, for the overlays:

    down {"b": "left", "x": 1177, "y": 1360}   button pressed, at the cursor
    move {"x": 1180, "y": 1362}                pointer moved while one is held
    up   {"b": "left", "x": 1180, "y": 1362}
    key  {"kind": "char", "text": "a"}         typed character (Shift applied)
    key  {"kind": "keys", "caps": ["Super", "W"], "repeat": false}
                                               a combo, a named key, or a
                                               modifier tapped on its own

x/y are Hyprland's global layout coordinates (logical pixels). The key
labels exist only on that pipe, in memory.

--log PATH appends every press and release to PATH as JSON lines for
scripts/capture-sfx.py, which turns them into sound after the recording:

    {"t": 1793823338.4417, "s": "key", "d": 1}

t is the kernel's event time (CLOCK_REALTIME, the clock gsr's
-write-first-frame-ts also reports), s the sound class (click, key, space,
enter), d 1 for press and 0 for release. Which key was pressed is NOT logged:
the file only says when to play which kind of sound. capture-sfx.py deletes
it once mixed.

Limits: the layout is US QWERTY (the desk's and the laptop's). A touchpad's
tap-to-click is synthesized by libinput above evdev, so only its physical
clicks show. Every device is read and presses are counted per key across
them, so a device grabbed by keyd (it reports through keyd's virtual
devices instead) still yields each press exactly once.

    inputcast.py --list    the devices it would read, then exit
"""

import argparse
import json
import os
import select
import socket
import sys
import time

import evdev
from evdev import ecodes as e

BUTTONS = {e.BTN_LEFT: "left", e.BTN_RIGHT: "right", e.BTN_MIDDLE: "middle"}
RESCAN_S = 2.0      # pick up a device that (re)connects mid-recording
MOVE_S = 1 / 60     # drag updates: at most one cursor query per frame

# --- key labels (US QWERTY) -------------------------------------------------

MODS = {
    e.KEY_LEFTCTRL: "Ctrl", e.KEY_RIGHTCTRL: "Ctrl",
    e.KEY_LEFTSHIFT: "Shift", e.KEY_RIGHTSHIFT: "Shift",
    e.KEY_LEFTALT: "Alt", e.KEY_RIGHTALT: "Alt",
    e.KEY_LEFTMETA: "Super", e.KEY_RIGHTMETA: "Super",
}
MOD_ORDER = ["Super", "Ctrl", "Alt", "Shift"]

# key -> (plain, shifted)
CHARS = {getattr(e, f"KEY_{c.upper()}"): (c, c.upper()) for c in "abcdefghijklmnopqrstuvwxyz"}
CHARS.update({getattr(e, f"KEY_{d}"): (d, s) for d, s in zip("1234567890", "!@#$%^&*()")})
CHARS.update({
    e.KEY_MINUS: ("-", "_"), e.KEY_EQUAL: ("=", "+"),
    e.KEY_LEFTBRACE: ("[", "{"), e.KEY_RIGHTBRACE: ("]", "}"),
    e.KEY_SEMICOLON: (";", ":"), e.KEY_APOSTROPHE: ("'", '"'),
    e.KEY_GRAVE: ("`", "~"), e.KEY_BACKSLASH: ("\\", "|"),
    e.KEY_COMMA: (",", "<"), e.KEY_DOT: (".", ">"), e.KEY_SLASH: ("/", "?"),
    e.KEY_SPACE: (" ", " "),
    e.KEY_KPSLASH: ("/", "/"), e.KEY_KPASTERISK: ("*", "*"),
    e.KEY_KPMINUS: ("-", "-"), e.KEY_KPPLUS: ("+", "+"), e.KEY_KPDOT: (".", "."),
})
CHARS.update({getattr(e, f"KEY_KP{d}"): (str(d), str(d)) for d in range(10)})

# Named keys. Backspace, Enter and Tab travel as glyphs so the overlay can
# write them inline in a typing run; the rest render as keycaps.
NAMED = {
    e.KEY_ENTER: "⏎", e.KEY_KPENTER: "⏎", e.KEY_BACKSPACE: "⌫", e.KEY_TAB: "⇥",
    e.KEY_ESC: "Esc", e.KEY_DELETE: "Del", e.KEY_INSERT: "Ins",
    e.KEY_HOME: "Home", e.KEY_END: "End", e.KEY_PAGEUP: "PgUp", e.KEY_PAGEDOWN: "PgDn",
    e.KEY_UP: "↑", e.KEY_DOWN: "↓", e.KEY_LEFT: "←", e.KEY_RIGHT: "→",
    e.KEY_CAPSLOCK: "Caps", e.KEY_SYSRQ: "Print", e.KEY_PRINT: "Print",
    e.KEY_VOLUMEUP: "Vol+", e.KEY_VOLUMEDOWN: "Vol−", e.KEY_MUTE: "Mute",
    e.KEY_PLAYPAUSE: "⏯", e.KEY_NEXTSONG: "⏭", e.KEY_PREVIOUSSONG: "⏮", e.KEY_STOPCD: "⏹",
    e.KEY_BACK: "Back", e.KEY_FORWARD: "Fwd", e.KEY_MENU: "Menu", e.KEY_COMPOSE: "Menu",
}
NAMED.update({getattr(e, f"KEY_F{n}"): f"F{n}" for n in range(1, 25)})

def is_key(code):
    """A keyboard key, not a BTN_* (mouse side buttons, joystick, ...)."""
    return code < e.BTN_MISC or e.KEY_OK <= code < e.BTN_DPAD_UP


# sound class per key, for capture-sfx.py
SOUND = {e.KEY_SPACE: "space", e.KEY_ENTER: "enter", e.KEY_KPENTER: "enter"}


class Keys:
    """Turns raw key events into overlay events. Pure: no devices, testable."""

    def __init__(self, caps_lock=False):
        self.held = {}          # code -> number of devices holding it
        self.caps_lock = caps_lock
        self.lone_mod = None    # a modifier pressed with nothing else yet

    def mods(self):
        names = {MODS[c] for c, n in self.held.items() if n and c in MODS}
        return [m for m in MOD_ORDER if m in names]

    def feed(self, code, value):
        """value 1 press, 0 release, 2 autorepeat -> list of overlay events"""
        if value == 2:
            return self._press(code, repeat=True) if code not in MODS else []
        n = self.held.get(code, 0)
        if value == 1:
            self.held[code] = n + 1
            if n:                       # same key down on a second device
                return []
            if code in MODS:
                self.lone_mod = code if not any(
                    c in MODS and c != code and k for c, k in self.held.items()) else None
                return []
            self.lone_mod = None
            if code == e.KEY_CAPSLOCK:
                self.caps_lock = not self.caps_lock
            return self._press(code, repeat=False)
        # release
        if not n:
            return []
        self.held[code] = n - 1
        if n - 1:
            return []
        if code in MODS and self.lone_mod == code:
            self.lone_mod = None
            return [{"kind": "keys", "caps": [MODS[code]], "repeat": False}]
        return []

    def _press(self, code, repeat):
        mods = self.mods()
        combo = [m for m in mods if m != "Shift"]
        if code in CHARS and not combo:
            plain, shifted = CHARS[code]
            shift = "Shift" in mods
            if plain.isalpha() and self.caps_lock:
                shift = not shift
            return [{"kind": "char", "text": shifted if shift else plain}]
        if code in CHARS:
            plain, _ = CHARS[code]
            label = "Space" if plain == " " else plain.upper()
        elif code in NAMED:
            label = NAMED[code]
        else:
            name = e.KEY.get(code)
            if isinstance(name, list):
                name = name[0]
            if not name or not name.startswith("KEY_"):
                return []
            label = name[4:].capitalize()
        # Shift alone stays inline for the glyph keys (Shift+Enter is still a
        # line break to a viewer); with Ctrl/Alt/Super it is a combo.
        if not combo and label in ("⏎", "⌫", "⇥"):
            return [{"kind": "char", "text": label}]
        return [{"kind": "keys", "caps": mods + [label], "repeat": repeat}]


# --- devices ----------------------------------------------------------------

def hypr_socket():
    run = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    return f"{run}/hypr/{sig}/.socket.sock"


def cursor(path):
    """Hyprland's cursor position, through its socket (no hyprctl spawn)."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(b"cursorpos")
        data = b""
        while chunk := s.recv(256):
            data += chunk
    x, y = data.decode().split(",")
    return round(float(x)), round(float(y))


def wanted(dev):
    """A pointer (left button + relative motion) or a keyboard (has A and Z)."""
    keys = dev.capabilities().get(e.EV_KEY, [])
    pointer = e.BTN_LEFT in keys and e.EV_REL in dev.capabilities()
    keyboard = e.KEY_A in keys and e.KEY_Z in keys
    return pointer or keyboard


def scan(known, rejected):
    """Devices not yet seen that we read.

    Only paths new since the last scan are opened: the power button, HDMI-CEC,
    the lid switch and the like are probed once, not every RESCAN_S. A
    rejected path that disappears is forgotten, since a replugged device can
    come back on the same eventN.
    """
    present = set(evdev.list_devices())
    rejected &= present
    found = {}
    for path in present - known.keys() - rejected:
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue  # vanished mid-scan, or unreadable; retried next scan
        if wanted(dev):
            found[path] = dev
        else:
            dev.close()
            rejected.add(path)
    return found


def caps_lock_on(devices):
    for dev in devices.values():
        try:
            if e.LED_CAPSL in dev.leds():
                return True
        except OSError:
            pass
    return False


def emit(name, value):
    try:
        print(name, json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        sys.exit(0)  # the shell went away


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--log", help="press/release timing for capture-sfx.py")
    args = ap.parse_args()

    if args.list:
        for dev in scan({}, set()).values():
            print(dev.path, dev.name)
        return

    sock = hypr_socket()
    log = None
    if args.log:
        fd = os.open(args.log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        log = os.fdopen(fd, "w", buffering=1)

    def note(ev, sound, down):
        if log:
            log.write(json.dumps({"t": round(ev.timestamp(), 6), "s": sound, "d": int(down)}) + "\n")

    devices = {}
    rejected = set()
    held = {name: set() for name in BUTTONS.values()}  # button -> device paths
    keys = None
    last_scan = 0.0
    last_move = 0.0
    moved = False

    def pos():
        x, y = cursor(sock)
        return {"x": x, "y": y}

    def press(name, path, down):
        was = bool(held[name])
        (held[name].add if down else held[name].discard)(path)
        if bool(held[name]) != was:
            emit("down" if down else "up", {"b": name, **pos()})
            return True
        return False

    while True:
        if os.getppid() == 1:
            return  # orphaned: the shell died without stopping us
        now = time.monotonic()
        if now - last_scan >= RESCAN_S:
            devices.update(scan(devices, rejected))
            if keys is None:
                keys = Keys(caps_lock=caps_lock_on(devices))
            last_scan = now

        dragging = any(held.values())
        timeout = MOVE_S if (dragging and moved) else 0.5
        ready, _, _ = select.select(list(devices.values()), [], [], timeout)

        for dev in ready:
            try:
                events = list(dev.read())
            except OSError:  # unplugged: release whatever it was holding
                devices.pop(dev.path, None)
                for name in held:
                    if dev.path in held[name]:
                        press(name, dev.path, False)
                continue
            for ev in events:
                if ev.type == e.EV_KEY and ev.code in BUTTONS:
                    if ev.value in (0, 1) and press(BUTTONS[ev.code], dev.path, ev.value == 1):
                        note(ev, "click", ev.value == 1)
                elif ev.type == e.EV_KEY and is_key(ev.code):
                    # a sound per physical press/release, not per autorepeat
                    # and not twice for a key held on two devices
                    first = ev.value != 2 and (
                        (ev.value == 1 and not keys.held.get(ev.code))
                        or (ev.value == 0 and keys.held.get(ev.code) == 1))
                    for out in keys.feed(ev.code, ev.value):
                        emit("key", out)
                    if first:
                        note(ev, SOUND.get(ev.code, "key"), ev.value == 1)
                elif ev.type == e.EV_REL and any(held.values()):
                    moved = True

        now = time.monotonic()
        if moved and any(held.values()) and now - last_move >= MOVE_S:
            emit("move", pos())
            last_move = now
            moved = False
        elif not any(held.values()):
            moved = False


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
