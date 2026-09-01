#!/usr/bin/env python3
"""waybar modules: one tab per Claude Code session, plus a quota gauge.

Mirrors the tabstrip architecture already on this bar:

    custom/claudedrv   --write    computes state -> $XDG_RUNTIME_DIR/waybar-claude.json
                                  and renders the quota gauge chip
    custom/claude1..6  --slot N   render tab N from that file (empty = hidden)

Reads only local files. No network, no credentials.

  ~/.claude/sessions/<pid>.json        live session state
  $XDG_RUNTIME_DIR/claude-usage.json   quota, written by the statusLine feeder
  ~/.claude.json                       cold-start fallback (usually stale)
"""

import glob
import html
import json
import os
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
SESSIONS = os.path.join(HOME, ".claude", "sessions")
USAGE = os.path.join(RUNTIME, "claude-usage.json")
STATE = os.path.join(RUNTIME, "waybar-claude.json")
FALLBACK = os.path.join(HOME, ".claude.json")

SLOTS = 6
# Per-frame Nerd Font icons. The icon carries which window is shown, the same
# way the top bar's #cpu / #memory / #disk read as "45% <icon>".
ICONS = {
    "5h":     "\U000f051f",       # nf-md-timer_sand — NOT a clock; #clock owns that
    "wk":     "\U000f0a34",       # nf-md-calendar_week
    "opus":   "\U000f0a34",
    "sonnet": "\U000f0a34",
}
BUSY, IDLE = "●", "○"
ASKING = "\U000f02d6"     # nf-md-help — session is waiting on you
WARN_PCT, CRIT_PCT = 70, 90
STALE_SECS = 3600
FRAME = os.path.join(RUNTIME, "claude-frame")   # which usage window to show


def frame_index():
    try:
        with open(FRAME) as fh:
            return int(fh.read().strip() or 0)
    except Exception:
        return 0


def bump_frame():
    """Advance the selected usage window. Called from the module's on-click."""
    n = frame_index() + 1
    try:
        fd, tmp = tempfile.mkstemp(dir=RUNTIME, prefix=".claude-frame.")
        with os.fdopen(fd, "w") as fh:
            fh.write(str(n))
        os.replace(tmp, FRAME)
    except Exception:
        pass
    return n


# ---------------------------------------------------------------- helpers

def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


def human_age(s):
    if s == float("inf"):
        return "never"
    s = int(s)
    if s < 90:
        return f"{s}s"
    if s < 5400:
        return f"{s // 60}m"
    if s < 172800:
        return f"{s // 3600}h"
    return f"{s // 86400}d"


def when(v):
    """resets_at is an epoch int on 2.1.220, an ISO string on some versions."""
    if isinstance(v, (int, float)) and v > 0:
        d = v - time.time()
        return f"in {human_age(d)}" if d > 0 else f"{human_age(-d)} ago"
    if isinstance(v, str) and v:
        return v[:16].replace("T", " ")
    return "?"


def label(path):
    """Path is the primary identifier on the chip, so keep enough of it to
    disambiguate: the last two components, which turns ~/Projects/Nuxt/relo
    into 'Nuxt/relo' and keeps '~' readable for a home session."""
    if not path:
        return "?"
    p = path.replace(HOME, "~").rstrip("/")
    if p in ("~", ""):
        return "~"
    parts = [x for x in p.split("/") if x]
    if parts and parts[0] == "~":
        parts = parts[1:]
        if not parts:
            return "~"
    # Drop the uninformative 'Projects' container; Lang/name is the useful pair.
    if parts and parts[0] == "Projects":
        parts = parts[1:] or ["Projects"]
    return "/".join(parts[-2:]) if len(parts) > 1 else (parts[0] if parts else "~")


# ---------------------------------------------------------------- sources

def sessions():
    out = []
    for path in sorted(glob.glob(os.path.join(SESSIONS, "*.json"))):
        pid = os.path.basename(path)[:-5]
        if not alive(pid):
            continue
        try:
            with open(path) as fh:
                d = json.load(fh)
        except Exception:
            continue
        if isinstance(d, dict):
            out.append(d)
    # Stable left-to-right order: oldest session first, so tabs don't reshuffle
    # when one comes or goes.
    out.sort(key=lambda s: s.get("startedAt") or 0)
    # A parked interactive session and the `kind: bg` job that continues it
    # (jobId == parkedJobId) are one logical session. Fold the job into the
    # interactive entry — that pid is the one whose parent chain reaches a
    # terminal window, so --focus keeps working — and stash the job under
    # _jobs for tab() to count as an extra agent.
    by_job = {s["jobId"]: s for s in out
              if s.get("kind") == "bg" and s.get("jobId")}
    claimed = set()
    for s in out:
        job = by_job.get(s.get("parkedJobId"))
        if job is not None and job is not s:
            s["_jobs"] = [job]
            claimed.add(id(job))
    return [s for s in out if id(s) not in claimed]


def quota():
    try:
        with open(USAGE) as fh:
            d = json.load(fh)
        rl = d.get("rate_limits") or {}
        if any((v or {}).get("pct") is not None for v in rl.values()):
            return {
                "rl": rl,
                "age": max(0.0, time.time() - float(d.get("written_at") or 0)),
                "source": "live",
                "ctx_pct": d.get("ctx_pct"),
                "ctx_size": d.get("ctx_size"),
                "cost": d.get("cost_usd"),
                "session_id": d.get("session_id"),
            }
    except Exception:
        pass
    try:
        with open(FALLBACK) as fh:
            d = json.load(fh)
        cu = d.get("cachedUsageUtilization") or {}
        u = cu.get("utilization") or {}
        rl = {}
        for name in ("five_hour", "seven_day"):
            b = u.get(name)
            if isinstance(b, dict) and isinstance(b.get("utilization"), (int, float)):
                rl[name] = {"pct": float(b["utilization"]), "resets_at": b.get("resets_at")}
        return {"rl": rl,
                "age": max(0.0, time.time() - float(cu.get("fetchedAtMs") or 0) / 1000.0),
                "source": "fallback", "ctx_pct": None, "ctx_size": None,
                "cost": None, "session_id": None}
    except Exception:
        return {"rl": {}, "age": float("inf"), "source": "none",
                "ctx_pct": None, "ctx_size": None, "cost": None, "session_id": None}


# ---------------------------------------------------------------- rendering

def tab(s, q, focused_addr=None, win_index=None, face=None):
    """One session chip.

    Two independent signals, deliberately not conflated:
      glyph  ● / ○   Claude's own state (busy / idle)
      class  active  this session's terminal is the focused window

    `active` is the same class the Firefox tab strip uses, so the existing
    `window#waybar.fftabs .active` rule styles it identically — no separate
    CSS needed.
    """
    # A session folded together with its background job (see sessions()) is
    # busy if *any* of its agents is; the ×N suffix counts only the ones
    # actively working, so a parked-idle terminal with one running job is a
    # plain busy chip and ×2 means two agents are chewing at once.
    jobs = s.get("_jobs") or []
    statuses = [s.get("status") or "idle"] + [j.get("status") or "idle" for j in jobs]
    active = sum(st == "busy" for st in statuses)
    busy = active > 0
    status = "busy" if busy else (s.get("status") or "idle")
    # face.py already publishes "waiting" to MQTT on PermissionRequest and
    # Notification, i.e. exactly "this session needs you". Reuse it rather than
    # inventing a second signal.
    asking = any((face or {}).get(x.get("sessionId")) == "waiting"
                 for x in [s] + jobs)
    name = label(s.get("cwd"))
    up = human_age(time.time() - float(s.get("startedAt") or 0) / 1000.0)
    addr = (win_index or {}).get(s.get("pid"))
    is_active = bool(addr) and addr == focused_addr

    # Tooltip leads with the two things that matter: full path, then status.
    tip = [
        f"<b>{html.escape(str(s.get('cwd') or '?').replace(HOME, '~'))}</b>",
        f"status    <b>{'waiting on you' if asking else html.escape(status)}</b>",
        "",
        f"session   {html.escape(str(s.get('name') or '—'))}",
        f"uptime    {up}",
        f"version   {html.escape(str(s.get('version') or '?'))}",
        f"pid       {s.get('pid')}",
    ]
    for j in jobs:
        tip.insert(2, f"bg job    {html.escape(str(j.get('name') or j.get('jobId') or '?'))}"
                      f" — <b>{html.escape(j.get('status') or 'idle')}</b>")
    # Colour is left entirely to CSS so this matches the tab strip: plain @text
    # normally, @rose via the shared .active rule when focused.
    glyph = ASKING if asking else (BUSY if busy else IDLE)
    classes = []
    if is_active:
        classes.append("active")
    if asking:
        classes.append("waiting")
    text = f"{glyph} {html.escape(name)}"
    if active > 1:
        text += f" ×{active}"
    return {
        "text": text,
        "tooltip": "\n".join(tip),
        "class": classes,
        # Carried in the state file so --focus can resolve the window; stripped
        # before the chip is handed to waybar.
        "pid": s.get("pid"),
        # Raw fields for the lastshell snapshot (see write_state); stripped
        # from the waybar slot output like pid is.
        "ls": {
            "pid": s.get("pid"),
            "label": name,
            "cwd": str(s.get("cwd") or "?").replace(HOME, "~"),
            "state": "waiting" if asking else status,
            "agents": active,
            "focused": is_active,
            "address": addr,
            "session": s.get("name"),
            "uptime": up,
            "jobs": [{"name": j.get("name") or j.get("jobId"),
                      "status": j.get("status") or "idle"} for j in jobs],
        },
    }


def gauge(q, n_sessions):
    """Shows one labelled usage window; click the module to advance to the next.
    Colour tracks the worst *rate limit* rather than the frame on screen, so a
    critical quota still reads red while you're looking at another window."""
    rl, age, source = q["rl"], q["age"], q["source"]
    stale = age > STALE_SECS

    frames = []
    for key, lab in (("five_hour", "5h"), ("seven_day", "wk"),
                     ("seven_day_opus", "opus"), ("seven_day_sonnet", "sonnet")):
        p = (rl.get(key) or {}).get("pct")
        if p is not None:
            frames.append((lab, p))
    if not frames:
        return {"text": "", "tooltip": "", "class": "empty"}

    lab, val = frames[frame_index() % len(frames)]
    icon = ICONS.get(lab, "")
    text = (f"{val:.0f}% {icon}"
            + ("<span alpha='55%'>*</span>" if stale else ""))

    limits = [p for p in ((rl.get(k) or {}).get("pct") for k in rl) if p is not None]
    worst = max(limits, default=0)
    cls = "critical" if worst >= CRIT_PCT else "warning" if worst >= WARN_PCT else "normal"

    labels = {"five_hour": "5-hour", "seven_day": "weekly",
              "seven_day_opus": "weekly opus", "seven_day_sonnet": "weekly sonnet"}
    tip = ["<b>Usage</b>"]
    for k, v in rl.items():
        p = v.get("pct")
        if p is not None:
            tip.append(f"  {labels.get(k, k):<13} {p:5.1f}%   resets {html.escape(when(v.get('resets_at')))}")
    tip += ["", f"<i>{n_sessions} session(s) · {'stale ' if stale else ''}{source}, {human_age(age)} ago</i>"]
    if source == "fallback":
        tip.append("<i>statusLine feeder has not run yet</i>")
    return {"text": text, "tooltip": "\n".join(tip), "class": cls}


# ---------------------------------------------------------------- focus

def ppid(pid):
    """Parent of pid, via /proc/<pid>/stat. Field 4, but comm (field 2) can
    contain spaces and parens, so split after the final ')'."""
    try:
        with open(f"/proc/{pid}/stat") as fh:
            data = fh.read()
        return int(data[data.rindex(")") + 2:].split()[1])
    except Exception:
        return None


def hypr(args):
    import subprocess
    env = dict(os.environ)
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        # Signatures go stale across Hyprland restarts; pick the newest.
        try:
            base = os.path.join(RUNTIME, "hypr")
            sigs = sorted(os.listdir(base),
                          key=lambda d: os.path.getmtime(os.path.join(base, d)),
                          reverse=True)
            if sigs:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = sigs[0]
        except Exception:
            pass
    try:
        r = subprocess.run(["hyprctl"] + args, capture_output=True, text=True,
                           env=env, timeout=3)
        return r.stdout
    except Exception:
        return ""


def focus_slot(n):
    """Focus the terminal window hosting slot n's session.

    The session JSON records the *claude* pid; Hyprland knows the *terminal*
    pid (claude <- fish <- kitty). So walk up the parent chain until a pid
    matches a Hyprland client.
    """
    try:
        with open(STATE) as fh:
            tabs = json.load(fh).get("tabs") or []
        pid = tabs[n].get("pid")
    except Exception:
        return 1
    if not pid:
        return 1
    try:
        clients = json.loads(hypr(["clients", "-j"]) or "[]")
    except Exception:
        return 1
    by_pid = {c.get("pid"): c.get("address") for c in clients if c.get("pid")}

    cur, seen = int(pid), 0
    while cur and cur > 1 and seen < 12:
        if cur in by_pid:
            # This Hyprland is configured in Lua, so hyprctl parses dispatch
            # arguments as Lua. The classic `focuswindow address:0x..` is a
            # syntax error here; the Lua form also switches workspace for free.
            hypr(["dispatch", f'hl.dsp.focus({{window="address:{by_pid[cur]}"}})'])
            return 0
        cur = ppid(cur)
        seen += 1
    return 1


# ---------------------------------------------------------------- daemon

PIDFILE = os.path.join(RUNTIME, "claude-status.pid")
# lastshell runs the daemon standalone; waybar's lifecycle coupling is off.
STANDALONE = os.environ.get("LASTSHELL_STANDALONE") == "1"
SLOT_SIGNAL = 10          # waybar RTMIN+10 -> slot modules re-read the state
IDLE_TICK = 5.0           # seconds between polls for non-push changes (socket2 + MQTT push the fast paths)


def event_socket():
    """Hyprland's socket2 pushes `activewindowv2>>ADDR` on every focus change."""
    import socket
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        try:
            base = os.path.join(RUNTIME, "hypr")
            sig = sorted(os.listdir(base),
                         key=lambda d: os.path.getmtime(os.path.join(base, d)),
                         reverse=True)[0]
        except Exception:
            return None
    path = os.path.join(RUNTIME, "hypr", sig, ".socket2.sock")
    try:
        s = socket.socket(socket.AF_UNIX)
        s.connect(path)
        s.setblocking(False)
        return s
    except Exception:
        return None


def face_subscriber():
    """`mosquitto_sub -v` on claude/face/+ — one line per retained/published
    message: "<topic> <json>". Gives push-based "needs you" with no new hook,
    since face.py already publishes that state."""
    import subprocess
    try:
        return subprocess.Popen(
            ["mosquitto_sub", "-h", "localhost", "-t", "claude/face/+", "-v"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1)
    except Exception:
        return None


def daemon():
    """Long-running driver, same shape as `tabstrip daemon` on this bar.

    Focus changes arrive by push from Hyprland rather than polling, so the
    active chip updates in milliseconds instead of up to two 3s waybar ticks.
    Session busy/idle and quota still need a poll, but a slow one.
    """
    import select
    import signal as sig_mod
    import subprocess

    try:
        with open(PIDFILE, "w") as fh:
            fh.write(str(os.getpid()))
    except Exception:
        pass

    # --cycle pokes us with SIGUSR1 so a click repaints immediately.
    poked = {"v": False}
    sig_mod.signal(sig_mod.SIGUSR1, lambda *_: poked.update(v=True))

    sock = event_socket()
    face_proc = face_subscriber()
    face = {}
    last_tabs, last_tick, buf = None, 0.0, b""

    while True:
        timeout = IDLE_TICK
        push = False
        watch = [f for f in (sock, face_proc.stdout if face_proc else None) if f]
        if watch:
            try:
                r, _, _ = select.select(watch, [], [], timeout)
            except Exception:
                r = []
            if face_proc and face_proc.stdout in r:
                try:
                    line = face_proc.stdout.readline()
                    if not line:
                        face_proc = face_subscriber()
                    else:
                        topic, _, payload = line.strip().partition(" ")
                        sid = topic.rsplit("/", 1)[-1]
                        if not payload:
                            face.pop(sid, None)          # retained message cleared
                        else:
                            try:
                                face[sid] = (json.loads(payload) or {}).get("state")
                            except Exception:
                                face.pop(sid, None)
                        push = True
                except Exception:
                    face_proc = face_subscriber()
            if sock is not None and sock in r:
                try:
                    chunk = sock.recv(8192)
                    if not chunk:            # socket closed; try to reattach
                        sock = event_socket()
                    else:
                        buf += chunk
                        *lines, buf = buf.split(b"\n")
                        for ln in lines:
                            if ln.startswith(b"activewindowv2>>"):
                                push = True
                except Exception:
                    sock = event_socket()
        else:
            time.sleep(timeout)
            sock = event_socket()

        now = time.time()
        if not (push or poked["v"] or now - last_tick >= IDLE_TICK):
            continue
        poked["v"] = False
        last_tick = now

        # waybar reloads by respawning this command; if it went away, exit
        # rather than looping forever as an orphan. Standalone (lastshell,
        # launched from hyprland autostart and reparented to init by design)
        # must NOT suicide on either signal — there is no waybar to die with.
        if os.getppid() == 1 and not STANDALONE:
            return
        try:
            chip = write_state(face)
        except Exception:
            continue
        try:
            if not STANDALONE:
                print(json.dumps(chip), flush=True)
        except (BrokenPipeError, OSError):
            return        # stdout closed -> waybar dropped us
        try:
            # Only wake the slot modules when their content actually changed.
            with open(STATE) as fh:
                tabs = json.load(fh).get("tabs") or []
            fingerprint = [(t.get("text"), t.get("class")) for t in tabs]
            if fingerprint != last_tabs:
                last_tabs = fingerprint
                subprocess.run(["pkill", f"-RTMIN+{SLOT_SIGNAL}", "waybar"],
                               capture_output=True)
        except Exception:
            pass


def poke_daemon():
    try:
        with open(PIDFILE) as fh:
            os.kill(int(fh.read().strip()), 10)   # SIGUSR1
    except Exception:
        pass


# ---------------------------------------------------------------- commands

def window_map(pids):
    """{session pid -> owning window address} plus the focused address.

    One `hyprctl clients -j` call serves both: it carries every window's pid
    and a focusHistoryID where 0 is the focused window.
    """
    try:
        clients = json.loads(hypr(["clients", "-j"]) or "[]")
    except Exception:
        return {}, None
    by_pid = {c["pid"]: c for c in clients if c.get("pid")}
    focused = next((c.get("address") for c in clients
                    if c.get("focusHistoryID") == 0), None)
    idx = {}
    for pid in pids:
        cur, seen = pid, 0
        while cur and cur > 1 and seen < 12:
            if cur in by_pid:
                idx[pid] = by_pid[cur].get("address")
                break
            cur = ppid(cur)
            seen += 1
    return idx, focused


def write_state(face=None):
    ses = sessions()
    q = quota()
    shown = ses[:SLOTS]
    idx, focused = window_map([s.get("pid") for s in shown if s.get("pid")])
    state = {"written_at": time.time(),
             "tabs": [tab(s, q, focused, idx, face) for s in shown]}
    # Skip the rewrite when nothing changed (written_at aside): the daemon
    # ticks every 2s and was rewriting both snapshots each time, forcing a
    # FileView wake in the shell for identical content.
    fingerprint = json.dumps(state["tabs"], sort_keys=True) + json.dumps(q, sort_keys=True, default=str)
    if fingerprint == getattr(write_state, "_last", None):
        return gauge(q, len(ses))
    write_state._last = fingerprint
    fd, tmp = tempfile.mkstemp(dir=RUNTIME, prefix=".waybar-claude.")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(state, fh)
        os.replace(tmp, STATE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass

    # lastshell snapshot: one file, all frames, raw values — the Quickshell
    # bar renders from this and needs none of waybar's slot machinery.
    rl, age, source = q["rl"], q["age"], q["source"]
    frame_defs = (("five_hour", "5h"), ("seven_day", "wk"),
                  ("seven_day_opus", "opus"), ("seven_day_sonnet", "sonnet"))
    frames = [{"id": lab, "pct": (rl.get(k) or {}).get("pct"),
               "resets": (rl.get(k) or {}).get("resets_at")}
              for k, lab in frame_defs if (rl.get(k) or {}).get("pct") is not None]
    ls_state = {
        "written_at": time.time(),
        "sessions": [t["ls"] for t in state["tabs"]],
        "quota": {
            "frames": frames,
            "worstPct": max((f["pct"] for f in frames), default=0),
            "stale": age > STALE_SECS,
            "source": source,
            "age": age,
        },
    }
    fd, tmp = tempfile.mkstemp(dir=RUNTIME, prefix=".lastshell-claude.")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(ls_state, fh)
        os.replace(tmp, os.path.join(RUNTIME, "lastshell-claude.json"))
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return gauge(q, len(ses))


def read_slot(n):
    try:
        with open(STATE) as fh:
            tabs = json.load(fh).get("tabs") or []
    except Exception:
        return None
    if not (0 <= n < len(tabs)):
        return None
    chip = dict(tabs[n])
    chip.pop("pid", None)          # waybar ignores extras, but keep output clean
    chip.pop("ls", None)
    return chip


def main(argv):
    if "--daemon" in argv:
        daemon()
        return 0
    if "--cycle" in argv:
        bump_frame()
        poke_daemon()        # repaint now instead of waiting for the next tick
        return 0
    if "--focus" in argv:
        try:
            return focus_slot(int(argv[argv.index("--focus") + 1]))
        except (IndexError, ValueError):
            return 1
    if "--write" in argv:
        print(json.dumps(write_state()))
        return 0
    if "--slot" in argv:
        try:
            n = int(argv[argv.index("--slot") + 1])
        except (IndexError, ValueError):
            return 0
        chip = read_slot(n)
        if chip:
            print(json.dumps(chip))
        return 0
    # No args: one-line summary, handy for testing outside waybar.
    q = quota()
    ses = sessions()
    print(json.dumps(gauge(q, len(ses))))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        print(json.dumps({"text": "", "tooltip": f"claude-status: {e}", "class": "empty"}))
        sys.exit(0)
