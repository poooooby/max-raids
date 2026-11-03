"""Bakes the raid's pixel art effects from pixelfx (github.com/patch-gg/pixelfx, MIT) into a grey atlas.

Render the sheets first, in a pixelfx checkout:
    node tools/render.mjs <ids...> --sheet --no-actor --out <out>
then:
    python tools/pixelfx_pack.py <out>
writes assets/fx/pixelfx/atlas_<n>.png (PAGE x PAGE, grey + alpha: each pixel's brightness, its
colour put back at draw time by src/fx.lua's gradient map from the effect's tint), the licence beside
them, and data/raid_pixelfx.lua: per key how it is placed, its fps, loop, anchor, tint and frames.

Only effects that draw no body of their own: pixelfx's status/freeze/heal/curse effects that paint
the stand-in character (actorAlpha 0: poisoned, burning, frozen, ice/freeze, holy/heal, shadow/curse)
would put its figure over a Pokemon.

Every frame is trimmed to what it draws (an empty one is kept as a gap) and the trimmed frames are
packed in shelves across the pages. An effect longer than HALVE_OVER frames keeps every other one
(played at half its fps).

  place  strike  a melee effect: its anchor is the attacker's feet, the blow lands act.targets[1] px
                 ahead of it - that point goes on the target's feet
         impact  the anchor is the point of impact: on the target's middle
         ground  standing on the floor at the target's feet
         body    on the target (its feet), drawn to its height
  tint   typed   recoloured by the move's type (else its own tint)
         own     its own colours' tint always
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = 2048
PAD = 1
HALVE_OVER = 60

# key -> (pixelfx id, place, tint)
EFFECTS = {
    "claw": ("melee/claw-swipe", "strike", "typed"),
    "slash": ("melee/double-slash", "strike", "typed"),
    "spark": ("impacts/hit-spark", "impact", "typed"),
    "blunt": ("impacts/blunt-hit", "impact", "typed"),
    "crit": ("impacts/crit-hit", "impact", "own"),
    "zap": ("lightning/zap-hit", "impact", "own"),
    "splash": ("water/splash", "ground", "own"),
    "acid": ("nature/acid-splash", "ground", "own"),
    "spores": ("nature/spore-burst", "ground", "own"),
    "freeze": ("ice/snowflake-burst", "body", "own"),
    "heal": ("holy/heal-aoe", "ground", "own"),
    "burn": ("fire/fire-ring", "ground", "own"),
    "sleep": ("status/sleep", "body", "own"),
    "stunned": ("status/stunned", "body", "own"),
    "confused": ("status/confused", "body", "own"),
    "charmed": ("status/charmed", "body", "own"),
}

LICENSE = """The pixel art effects in this folder were made with pixelfx
(https://github.com/patch-gg/pixelfx), rendered as sprite sheets by its tools/render.mjs and baked
into a grey atlas by tools/pixelfx_pack.py.

MIT License

Copyright (c) 2026 Patch
Copyright (c) 2026 Hugo Duprez

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def grey(frame):
    """A frame as grey + alpha (each pixel's brightness as seen, Rec. 601) and its colours' tint: the
    mean hue of its coloured pixels, at full brightness."""
    px = frame.load()
    w, h = frame.size
    out = Image.new("LA", (w, h))
    po = out.load()
    tr = tg = tb = tw = 0.0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            v = int(round(0.299 * r + 0.587 * g + 0.114 * b))
            po[x, y] = (v, a)
            top = max(r, g, b)
            if a > 0 and top > 0 and 50 <= v <= 205:
                k = a / 255.0
                tr, tg, tb, tw = tr + k * r / top, tg + k * g / top, tb + k * b / top, tw + k
    return out, (tr, tg, tb, tw)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python tools/pixelfx_pack.py <pixelfx render --sheet output dir>")
    src = sys.argv[1]
    dst = os.path.join(ROOT, "assets", "fx", "pixelfx")
    os.makedirs(dst, exist_ok=True)
    effects, rects = {}, []
    for key in sorted(EFFECTS):
        fid, place, tinting = EFFECTS[key]
        name = fid.split("/")[-1]
        base = os.path.join(src, *fid.split("/"), name)
        with open(base + ".json", encoding="utf-8") as f:
            meta = json.load(f)["meta"]["pixelfx"]
        sheet = Image.open(base + ".png").convert("RGBA")
        w, h = meta["frameSize"]
        cols, n, fps = meta["columns"], meta["frames"], meta["fps"]
        ax, ay = meta["pivot"]
        act = meta.get("act") or {}
        if place == "strike" and act.get("targets"):
            ax += act["targets"][0]
        step = 2 if n > HALVE_OVER else 1
        frames, tsum = [], [0.0, 0.0, 0.0, 0.0]
        for f in range(0, n, step):
            x, y = (f % cols) * w, (f // cols) * h
            fr = sheet.crop((x, y, x + w, y + h))
            bb = fr.getchannel("A").getbbox()
            if not bb:
                frames.append(None)
                continue
            img, t = grey(fr.crop(bb))
            for i in range(4):
                tsum[i] += t[i]
            r = {"key": key, "img": img, "ox": bb[0], "oy": bb[1]}
            frames.append(r)
            rects.append(r)
        tw = max(1e-6, tsum[3])
        tint = [tsum[0] / tw, tsum[1] / tw, tsum[2] / tw]
        top = max(tint) or 1
        tint = [c / top for c in tint]
        effects[key] = {"id": fid, "place": place, "typed": tinting == "typed", "fps": fps / step,
                        "loop": meta["loop"], "ax": ax, "ay": ay, "tint": tint, "frames": frames}
    # shelves, tallest first, across as many pages as it takes
    rects.sort(key=lambda r: (-r["img"].size[1], -r["img"].size[0]))
    pages, page, sx, sy, shelf = [], None, 0, 0, 0
    for r in rects:
        rw, rh = r["img"].size
        if page is None or sx + rw + PAD > PAGE:
            sx, sy, shelf = 0, sy + shelf, 0
        if page is None or sy + rh + PAD > PAGE:
            page = Image.new("LA", (PAGE, PAGE), (0, 0))
            pages.append(page)
            sx, sy, shelf = 0, 0, 0
        page.paste(r["img"], (sx, sy))
        r["page"], r["x"], r["y"] = len(pages), sx, sy
        sx += rw + PAD
        shelf = max(shelf, rh + PAD)
    for old in os.listdir(dst):
        if old.endswith(".png"):
            os.remove(os.path.join(dst, old))
    for i, p in enumerate(pages):
        p.save(os.path.join(dst, "atlas_%d.png" % (i + 1)), optimize=True)
    with open(os.path.join(dst, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(LICENSE)
    out = os.path.join(ROOT, "data", "raid_pixelfx.lua")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- The raid's pixel art effects, made with pixelfx (github.com/patch-gg/pixelfx, MIT) and baked by\n")
        f.write("-- tools/pixelfx_pack.py into a grey atlas (assets/fx/pixelfx/atlas_<page>.png): per key how it is\n")
        f.write("-- placed on its target, its fps, loop, anchor pixel (ax, ay), whether the move's type recolours it\n")
        f.write("-- (typed) and its own tint; f holds each frame as page, x, y, w, h in the atlas and ox, oy where\n")
        f.write("-- it sits in the effect's frame (page 0: an empty frame). Drawn for a 38-px character (src/fx.lua).\n")
        f.write("return {\n")
        f.write("  PAGES = %d,\n" % len(pages))
        for key in sorted(effects):
            e = effects[key]
            nums = []
            for r in e["frames"]:
                if r is None:
                    nums.append("0,0,0,0,0,0,0")
                else:
                    rw, rh = r["img"].size
                    nums.append("%d,%d,%d,%d,%d,%d,%d" % (r["page"], r["x"], r["y"], rw, rh, r["ox"], r["oy"]))
            f.write('  %s = { id = "%s", place = "%s", typed = %s, fps = %g, loop = %s, ax = %d, ay = %d,\n'
                    % (key, e["id"], e["place"], "true" if e["typed"] else "false", e["fps"],
                       "true" if e["loop"] else "false", e["ax"], e["ay"]))
            f.write("    tint = { %.3f, %.3f, %.3f }, n = %d,\n" % (e["tint"][0], e["tint"][1], e["tint"][2],
                                                                  len(e["frames"])))
            f.write("    f = { %s } },\n" % ", ".join(nums))
        f.write("}\n")
    used = sum(r["img"].size[0] * r["img"].size[1] for r in rects)
    print("baked %d effects, %d frames -> %d page(s) of %d (%.0f%% full) and %s"
          % (len(effects), len(rects), len(pages), PAGE, 100.0 * used / (len(pages) * PAGE * PAGE),
             os.path.relpath(out, ROOT)))


if __name__ == "__main__":
    main()
