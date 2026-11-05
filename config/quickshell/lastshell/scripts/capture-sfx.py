#!/usr/bin/env python3
"""Mix click and key sounds into a finished screen recording.

capture.sh runs this after gpu-screen-recorder exits. Nothing plays live:
the sounds exist only in the video. They are synthesized here (no sample
files) and placed at the moments scripts/inputcast.py logged, aligned to the
video by gsr's -write-first-frame-ts file:

    capture-sfx.py VIDEO.mp4 [--log PATH]

Reads VIDEO.mp4.ts (gsr: a header line, then monotonic and realtime
microseconds of the first frame) and the inputcast log (JSON lines of
{"t": realtime seconds, "s": click|key|space|enter, "d": 1 press / 0 release}).
Rewrites VIDEO.mp4 in place: video stream copied untouched, its audio (the
desktop) mixed with the effects track and re-encoded. Deletes the log and
the .ts afterwards. With no events in the window it only cleans up.

Sound design, all short and quiet so they sit under desktop audio:
  key    a soft tactile "tock": a damped low body under a short filtered
         noise transient, its release a faint tick. Each press is drawn from
         a few seeded variants with a little pitch and level drift, so typing
         doesn't machine-gun the same sample.
  space, enter   the same, deeper and a touch longer (stabilized keys)
  click  a crisp, small mouse switch: a bright band-limited tick; release
         quieter and higher
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 48000
RNG = np.random.default_rng(1793)
VARIANTS = 6


def db(x):
    return 10 ** (x / 20)


def env(n, tau):
    return np.exp(-np.arange(n) / (tau * RATE))


def onepole_lp(x, hz):
    a = np.exp(-2 * np.pi * hz / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def norm(x, peak_db):
    return x / (np.max(np.abs(x)) or 1) * db(peak_db)


def key_down(body_hz, body_tau, noise_tau, length, peak):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    body = np.sin(2 * np.pi * body_hz * t * (1 - 0.25 * t / length)) * env(n, body_tau)
    noise = RNG.standard_normal(n)
    tick = onepole_lp(np.diff(noise, prepend=0.0), 5200) * env(n, noise_tau)
    # a hair of pre-attack softening so it never clicks digitally
    attack = np.minimum(1, np.arange(n) / (0.0006 * RATE))
    return norm((0.55 * body + 0.9 * tick) * attack, peak)


def key_up(peak):
    n = int(0.022 * RATE)
    noise = np.diff(RNG.standard_normal(n), prepend=0.0)
    return norm(onepole_lp(noise, 7000) * env(n, 0.0025), peak)


def mouse(hz, tau, peak):
    n = int(0.018 * RATE)
    t = np.arange(n) / RATE
    noise = np.diff(np.diff(RNG.standard_normal(n), prepend=0.0), prepend=0.0)
    tick = onepole_lp(noise, 9000) * env(n, tau)
    tone = np.sin(2 * np.pi * hz * t) * env(n, tau * 1.6)
    return norm(0.8 * tick + 0.35 * tone, peak)


def bank():
    """sound class -> (press variants, release variants)"""
    def drift(f):
        return f * RNG.uniform(0.93, 1.07)
    return {
        "key": ([key_down(drift(210), 0.016, 0.0040, 0.055, -24) for _ in range(VARIANTS)],
                [key_up(-36) for _ in range(VARIANTS)]),
        "space": ([key_down(drift(135), 0.026, 0.0050, 0.075, -23) for _ in range(VARIANTS)],
                  [key_up(-34) for _ in range(VARIANTS)]),
        "enter": ([key_down(drift(155), 0.022, 0.0045, 0.070, -23) for _ in range(VARIANTS)],
                  [key_up(-34) for _ in range(VARIANTS)]),
        "click": ([mouse(drift(2600), 0.0022, -21) for _ in range(VARIANTS)],
                  [mouse(drift(3400), 0.0016, -29) for _ in range(VARIANTS)]),
    }


def first_frame_realtime(ts_path):
    with open(ts_path) as f:
        last = [line.split() for line in f if line.strip()][-1]
    return int(last[1]) / 1e6


def probe(video):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
         "-of", "json", video], capture_output=True, text=True, check=True).stdout
    info = json.loads(out)
    has_audio = any(s.get("codec_type") == "audio" for s in info.get("streams", []))
    return float(info["format"]["duration"]), has_audio


def render(events, t0, duration):
    track = np.zeros(int((duration + 0.2) * RATE), dtype=np.float64)
    sounds = bank()
    for ev in events:
        press, release = sounds.get(ev["s"], sounds["key"])
        pool = press if ev["d"] else release
        clip = pool[RNG.integers(len(pool))] * db(RNG.uniform(-1.5, 1.5))
        i = int(round((ev["t"] - t0) * RATE))
        if i < 0 or i >= len(track):
            continue
        j = min(len(track), i + len(clip))
        track[i:j] += clip[: j - i]
    peak = np.max(np.abs(track)) if len(track) else 0
    if peak > 0.98:  # a chord of presses stacking up: soft-limit, don't clip
        track = np.tanh(track / 0.98) * 0.98
    return (track * 32767).astype("<i2")


def write_wav(path, pcm):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--log", default=os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "lastshell-capture-input.jsonl"))
    args = ap.parse_args()
    ts_path = args.video + ".ts"

    try:
        t0 = first_frame_realtime(ts_path)
        duration, has_audio = probe(args.video)
        events = []
        with open(args.log) as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if t0 <= ev.get("t", 0) <= t0 + duration:
                    events.append(ev)
    except (OSError, IndexError, ValueError, subprocess.CalledProcessError) as err:
        print(f"capture-sfx: nothing mixed ({err})", file=sys.stderr)
        events = []

    if events:
        tmpdir = os.path.dirname(os.path.abspath(args.video))
        with tempfile.TemporaryDirectory(dir=os.environ.get("XDG_RUNTIME_DIR")) as tmp:
            wav = os.path.join(tmp, "sfx.wav")
            write_wav(wav, render(events, t0, duration))
            out = os.path.join(tmpdir, "." + os.path.basename(args.video) + ".sfx.mp4")
            if has_audio:
                audio = ["-filter_complex",
                         "[1:a]aresample=async=0,pan=stereo|c0=c0|c1=c0[fx];"
                         "[0:a][fx]amix=inputs=2:duration=first:normalize=0[a]",
                         "-map", "0:v", "-map", "[a]"]
            else:
                audio = ["-map", "0:v", "-map", "1:a", "-shortest"]
            cmd = ["ffmpeg", "-v", "error", "-y", "-i", args.video, "-i", wav, *audio,
                   "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                   "-movflags", "+faststart", out]
            if subprocess.run(cmd).returncode == 0:
                os.replace(out, args.video)
            else:
                print("capture-sfx: ffmpeg failed, recording left as recorded", file=sys.stderr)
                try:
                    os.unlink(out)
                except OSError:
                    pass

    for path in (args.log, ts_path):
        try:
            os.unlink(path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
