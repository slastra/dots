#!/usr/bin/env python3
"""claude-status: Claude Code session state for lastshell's bottom bar.

Writes $XDG_RUNTIME_DIR/lastshell-claude.json, which services/Claude.qml
watches: one entry per live session (merged with its background job) plus
the usage quota. Reads only local files. No network, no credentials.

  ~/.claude/sessions/<pid>.json        live session state
  $XDG_RUNTIME_DIR/claude-usage.json   quota, written by the statusLine feeder
  ~/.claude.json                       quota cold-start fallback (usually stale)
  MQTT claude/face/+                   "waiting on you", published by face.py

Focus changes arrive by push on Hyprland's event socket and face state by
MQTT; session status and quota are polled every IDLE_TICK seconds. Window
lookups talk to Hyprland's request socket directly instead of spawning
hyprctl. The snapshot is only rewritten when its content changes.

  claude-status.py --daemon    run (started from hyprland.lua)
  claude-status.py             print one snapshot and exit
"""

import glob
import json
import os
import select
import socket
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
SESSIONS = os.path.join(HOME, ".claude", "sessions")
USAGE = os.path.join(RUNTIME, "claude-usage.json")
FALLBACK = os.path.join(HOME, ".claude.json")
SNAPSHOT = os.path.join(RUNTIME, "lastshell-claude.json")

MAX_SESSIONS = 6
STALE_SECS = 3600
IDLE_TICK = 5.0
FRAMES = (("five_hour", "5h"), ("seven_day", "wk"),
          ("seven_day_opus", "opus"), ("seven_day_sonnet", "sonnet"))


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


def label(path):
    """The chip's name: the last two path components, so ~/Projects/Nuxt/relo
    reads 'Nuxt/relo', dropping the uninformative 'Projects' container."""
    if not path:
        return "?"
    parts = [x for x in path.replace(HOME, "~").rstrip("/").split("/") if x]
    if parts and parts[0] == "~":
        parts = parts[1:]
    if parts and parts[0] == "Projects":
        parts = parts[1:] or ["Projects"]
    if not parts:
        return "~"
    return "/".join(parts[-2:])


def ppid(pid):
    """Parent of pid. comm (field 2) can hold spaces and parens, so split
    after the final ')'."""
    try:
        with open(f"/proc/{pid}/stat") as fh:
            data = fh.read()
        return int(data[data.rindex(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return None


# ---------------------------------------------------------------- sources

def sessions():
    out = []
    for path in sorted(glob.glob(os.path.join(SESSIONS, "*.json"))):
        if not alive(os.path.basename(path)[:-5]):
            continue
        try:
            with open(path) as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        if isinstance(d, dict):
            out.append(d)
    # oldest first, so chips don't reshuffle when one comes or goes
    out.sort(key=lambda s: s.get("startedAt") or 0)
    # A parked interactive session and the `kind: bg` job that continues it
    # (jobId == parkedJobId) are one logical session. Fold the job into the
    # interactive entry, whose pid is the one with a terminal window above it.
    by_job = {s["jobId"]: s for s in out if s.get("kind") == "bg" and s.get("jobId")}
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
            return rl, max(0.0, time.time() - float(d.get("written_at") or 0)), "live"
    except (OSError, ValueError, AttributeError):
        pass
    try:
        with open(FALLBACK) as fh:
            cu = json.load(fh).get("cachedUsageUtilization") or {}
        u = cu.get("utilization") or {}
        rl = {}
        for name in ("five_hour", "seven_day"):
            b = u.get(name)
            if isinstance(b, dict) and isinstance(b.get("utilization"), (int, float)):
                rl[name] = {"pct": float(b["utilization"]), "resets_at": b.get("resets_at")}
        return rl, max(0.0, time.time() - float(cu.get("fetchedAtMs") or 0) / 1000.0), "fallback"
    except (OSError, ValueError, AttributeError):
        return {}, float("inf"), "none"


# ---------------------------------------------------------------- hyprland

def hypr_dir():
    """This Hyprland's socket dir. Signatures go stale across Hyprland
    restarts, so without the env var take the newest."""
    base = os.path.join(RUNTIME, "hypr")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        try:
            sig = max(os.listdir(base), key=lambda d: os.path.getmtime(os.path.join(base, d)))
        except (OSError, ValueError):
            return None
    return os.path.join(base, sig)


def hypr_clients():
    """`j/clients` over the request socket: what hyprctl clients -j prints."""
    d = hypr_dir()
    if not d:
        return []
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(2)
            s.connect(os.path.join(d, ".socket.sock"))
            s.sendall(b"j/clients")
            chunks = []
            while chunk := s.recv(65536):
                chunks.append(chunk)
        return json.loads(b"".join(chunks) or b"[]")
    except (OSError, ValueError):
        return []


def event_socket():
    """Hyprland's socket2 pushes `activewindowv2>>ADDR` on every focus change."""
    d = hypr_dir()
    if not d:
        return None
    try:
        s = socket.socket(socket.AF_UNIX)
        s.connect(os.path.join(d, ".socket2.sock"))
        s.setblocking(False)
        return s
    except OSError:
        return None


def window_map(pids):
    """{session pid: window address} and the focused address. Sessions
    record the claude pid; Hyprland knows the terminal's (claude <- fish <-
    kitty), so walk up the parent chain until a pid owns a window."""
    clients = hypr_clients()
    by_pid = {c["pid"]: c.get("address") for c in clients if c.get("pid")}
    focused = next((c.get("address") for c in clients if c.get("focusHistoryID") == 0), None)
    idx = {}
    for pid in pids:
        cur, hops = pid, 0
        while cur and cur > 1 and hops < 12:
            if cur in by_pid:
                idx[pid] = by_pid[cur]
                break
            cur, hops = ppid(cur), hops + 1
    return idx, focused


# ---------------------------------------------------------------- snapshot

def session_entry(s, focused, idx, face):
    # Merged with its background job, a session is busy if any agent is;
    # `agents` counts only the busy ones, so 2 means two at work at once.
    jobs = s.get("_jobs") or []
    statuses = [s.get("status") or "idle"] + [j.get("status") or "idle" for j in jobs]
    busy = sum(st == "busy" for st in statuses)
    # face.py publishes "waiting" on PermissionRequest and Notification:
    # exactly "this session needs you".
    asking = any(face.get(x.get("sessionId")) == "waiting" for x in [s] + jobs)
    addr = idx.get(s.get("pid"))
    return {
        "pid": s.get("pid"),
        "label": label(s.get("cwd")),
        "cwd": str(s.get("cwd") or "?").replace(HOME, "~"),
        "state": "waiting" if asking else ("busy" if busy else s.get("status") or "idle"),
        "agents": busy,
        "focused": bool(addr) and addr == focused,
        "address": addr,
        "session": s.get("name"),
        "uptime": human_age(time.time() - float(s.get("startedAt") or 0) / 1000.0),
        "jobs": [{"name": j.get("name") or j.get("jobId"), "status": j.get("status") or "idle"}
                 for j in jobs],
    }


def snapshot(face):
    shown = sessions()[:MAX_SESSIONS]
    idx, focused = window_map([s.get("pid") for s in shown if s.get("pid")])
    rl, age, source = quota()
    frames = [{"id": lab, "pct": (rl.get(k) or {}).get("pct"), "resets": (rl.get(k) or {}).get("resets_at")}
              for k, lab in FRAMES if (rl.get(k) or {}).get("pct") is not None]
    return {
        "written_at": time.time(),
        "sessions": [session_entry(s, focused, idx, face) for s in shown],
        "quota": {
            "frames": frames,
            "worstPct": max((f["pct"] for f in frames), default=0),
            "stale": age > STALE_SECS,
            "source": source,
            "age": age,
        },
    }


def fingerprint(snap):
    """Content minus the fields that change every call: written_at, and the
    quota age (the shell only cares whether it crossed STALE_SECS)."""
    q = {k: v for k, v in snap["quota"].items() if k != "age"}
    return json.dumps([snap["sessions"], q], sort_keys=True, default=str)


def write_atomic(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


# ---------------------------------------------------------------- daemon

def face_subscriber():
    try:
        return subprocess.Popen(["mosquitto_sub", "-h", "localhost", "-t", "claude/face/+", "-v"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except OSError:
        return None


def apply_face(face, line):
    """One `mosquitto_sub -v` line, "<topic> <json>"; an empty payload is a
    cleared retained message."""
    topic, _, payload = line.strip().partition(" ")
    sid = topic.rsplit("/", 1)[-1]
    try:
        state = (json.loads(payload) or {}).get("state") if payload else None
    except (ValueError, AttributeError):
        state = None
    if state is None:
        face.pop(sid, None)
    else:
        face[sid] = state


def daemon():
    sock, face_proc = event_socket(), face_subscriber()
    face, last, last_tick, buf = {}, None, 0.0, b""
    while True:
        push = False
        watch = [f for f in (sock, face_proc.stdout if face_proc else None) if f]
        try:
            ready = select.select(watch, [], [], IDLE_TICK)[0] if watch else []
        except (OSError, ValueError):
            ready = []
        if not watch:
            time.sleep(IDLE_TICK)
        if face_proc and face_proc.stdout in ready:
            line = face_proc.stdout.readline()
            if line:
                apply_face(face, line)
                push = True
            else:                                   # mosquitto went away
                face_proc = face_subscriber()
        if sock is None:
            sock = event_socket()
        elif sock in ready:
            try:
                chunk = sock.recv(8192)
            except OSError:
                chunk = b""
            if not chunk:                           # Hyprland restarted
                sock.close()
                sock = event_socket()
            else:
                *lines, buf = (buf + chunk).split(b"\n")
                push = push or any(ln.startswith(b"activewindowv2>>") for ln in lines)

        now = time.time()
        if not push and now - last_tick < IDLE_TICK:
            continue
        last_tick = now
        snap = snapshot(face)
        fp = fingerprint(snap)
        if fp != last:
            last = fp
            write_atomic(SNAPSHOT, snap)


def main(argv):
    if "--daemon" in argv:
        daemon()
        return 0
    print(json.dumps(snapshot({}), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
