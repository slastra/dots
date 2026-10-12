#!/usr/bin/env python3
"""Arrange floating windows: a tight mosaic, maximum edge contact.

Greedy contact packing. Windows keep their sizes; largest places first,
and each next window tries every position snapped GAP away from placed
edges (corner-aligned candidates), scored by total edge length shared
with neighbours — tie-broken by tighter bounding box. The finished
cluster is centered in the work area. Four windows naturally form the
quad-corner cross; more keep welding on wherever they touch most.

    float-arrange.py [workspace-id]     defaults to the active workspace
"""
import json, subprocess, sys

BAR = 34
MARGIN = 48
GAP = 48
TOL = 2  # adjacency tolerance

def hypr(args):
    return json.loads(subprocess.check_output(["hyprctl", "-j"] + args))

def dispatch(lua):
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True)

mon = next(m for m in hypr(["monitors"]) if m["focused"])
W = round(mon["width"] / mon["scale"])
H = round(mon["height"] / mon["scale"])
ws = int(sys.argv[1]) if len(sys.argv) > 1 else hypr(["activeworkspace"])["id"]

wins = [c for c in hypr(["clients"])
        if c["workspace"]["id"] == ws and c["floating"] and c["mapped"]]
if not wins:
    sys.exit(0)

usable_w, usable_h = W - 2 * MARGIN, H - 2 * BAR - 2 * MARGIN
wins.sort(key=lambda c: -(c["size"][0] * c["size"][1]))

placed = []  # (x, y, w, h, client)

def overlaps(x, y, w, h):
    for px, py, pw, ph, _ in placed:
        if x < px + pw + GAP - TOL and px < x + w + GAP - TOL and \
           y < py + ph + GAP - TOL and py < y + h + GAP - TOL:
            # inside the forbidden zone unless exactly on the GAP seam
            hgap = abs(x - (px + pw + GAP)) <= TOL or abs(px - (x + w + GAP)) <= TOL
            vgap = abs(y - (py + ph + GAP)) <= TOL or abs(py - (y + h + GAP)) <= TOL
            if not (hgap or vgap):
                return True
    return False

def contact(x, y, w, h):
    total = 0
    for px, py, pw, ph, _ in placed:
        # vertical seams
        if abs((x + w + GAP) - px) <= TOL or abs((px + pw + GAP) - x) <= TOL:
            total += max(0, min(y + h, py + ph) - max(y, py))
        # horizontal seams
        if abs((y + h + GAP) - py) <= TOL or abs((py + ph + GAP) - y) <= TOL:
            total += max(0, min(x + w, px + pw) - max(x, px))
    return total

def bbox_with(x, y, w, h):
    xs = [x] + [p[0] for p in placed]
    ys = [y] + [p[1] for p in placed]
    xe = [x + w] + [p[0] + p[2] for p in placed]
    ye = [y + h] + [p[1] + p[3] for p in placed]
    return (max(xe) - min(xs)), (max(ye) - min(ys))

for c in wins:
    w, h = c["size"]
    if not placed:
        placed.append((0, 0, w, h, c))
        continue
    cands = []
    for px, py, pw, ph, _ in placed:
        # adjacent to each side, aligned at both corners plus centered
        for x, y in [
            (px + pw + GAP, py), (px + pw + GAP, py + ph - h), (px + pw + GAP, py + (ph - h) // 2),
            (px - GAP - w, py), (px - GAP - w, py + ph - h), (px - GAP - w, py + (ph - h) // 2),
            (px, py + ph + GAP), (px + pw - w, py + ph + GAP), (px + (pw - w) // 2, py + ph + GAP),
            (px, py - GAP - h), (px + pw - w, py - GAP - h), (px + (pw - w) // 2, py - GAP - h),
        ]:
            if not overlaps(x, y, w, h):
                bw, bh = bbox_with(x, y, w, h)
                # hard constraint: the growing cluster must still fit the
                # work area, or the tallest-seam preference builds a tower
                # straight off the bottom of the screen
                fits = bw <= usable_w and bh <= usable_h
                cands.append((fits, contact(x, y, w, h), -(bw * bh), x, y))
    if cands:
        _, _, _, x, y = max(cands)
        placed.append((x, y, w, h, c))
    else:
        # nowhere adjacent fits: drop below the cluster
        ymax = max(p[1] + p[3] for p in placed)
        placed.append((0, ymax + GAP, w, h, c))

# center the finished cluster in the work area
xs = min(p[0] for p in placed); ys = min(p[1] for p in placed)
xe = max(p[0] + p[2] for p in placed); ye = max(p[1] + p[3] for p in placed)
ox = MARGIN + max(0, (usable_w - (xe - xs)) / 2) - xs
oy = BAR + MARGIN + max(0, (usable_h - (ye - ys)) / 2) - ys
for x, y, w, h, c in placed:
    dispatch(f'hl.dsp.window.move({{ window = "address:{c["address"]}", '
             f'x = {round(x + ox)}, y = {round(y + oy)}, relative = false }})')
