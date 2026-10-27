"""Bake Max Raids' bosses from the Giga Megas pack (Pokemon Essentials format) into PlayNav's assets.

The pack is read straight from its zip, never unpacked:
  Graphics/Pokemon/Front[ shiny]/<KEY>.png   an animated strip, frames side by side, each as wide
                                              as the strip is tall (96..120 px); some strips are
                                              past 4096 px, wider than a phone GPU's texture limit
  Graphics/Pokemon/Back[ shiny]/<KEY>.png    the same from behind (a player's Gigantamaxed Pokemon)
  Graphics/Pokemon/Icons[ shiny]/<KEY>.png    the party icon, two frames
  Audio/SE/Cries/<KEY>.ogg                    the cry
  PBS/pokemon_forms_gmax_megas_Gen_9_Pack.txt [SPECIES,form] FormName, BaseStats (HP, Atk, Def,
                                              Spe, SpA, SpD - Essentials' order), Types (some
                                              forms; the rest keep the species'), Height, ...
  PBS/pokemon_metrics_gmax_megas_Gen_9_Pack.txt FrontSprite x,y / ShadowSprite x,y,size /
                                              AnimationSpeed (frames held; 2 when absent)
Out:
  assets/bosses/<KEY>.png, <KEY>_shiny.png   the strip re-wrapped into a grid at most MAX_W wide
  assets/bosses/backs/<KEY>.png, _shiny.png  the back strip, the same way (row: back = { frames,
                                           cell, cols, rows })
  assets/bosses/icons/<KEY>.png, <KEY>_shiny.png
  assets/bosses/cries/<KEY>.ogg
  data/raid_sprites.lua                    per key: frames, cell w / h, cols / rows, speed, the
                                           metrics, height, base stats, pack types, form name

  python tools/raid_pack.py "<path>/2.0 Giga Megas Pack Gen 9.zip"
"""
import io
import os
import re
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAX_W = 2048
STAT_ORDER = ("hp", "atk", "def", "spe", "spa", "spd")


def blocks(text):
    """PBS sections: { "SPECIES_form": { key: value } }"""
    out, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"\[(\w+),(\d+)\]", line)
        if m:
            cur = out.setdefault(f"{m.group(1)}_{m.group(2)}", {})
            continue
        m = re.match(r"(\w+)\s*=\s*(.*)", line)
        if m and cur is not None:
            cur[m.group(1)] = m.group(2).strip()
    return out


def ints(s):
    return [int(v) for v in s.split(",")]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def grid(strip):
    """frames as wide as the strip is tall; a strip whose width is not a whole number of them
    (CORVIKNIGHT_2, 12117 x 248: 49 frames rescaled to a 247.3 px pitch) is cut at i * w / n,
    n = round(w / h), each frame centred in a square cell"""
    w, h = strip.size
    frames = max(1, round(w / h))
    pitch = w / frames
    cols = max(1, min(frames, MAX_W // h))
    rows = (frames + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * h, rows * h), (0, 0, 0, 0))
    for i in range(frames):
        x0, x1 = round(i * pitch), round((i + 1) * pitch)
        frame = strip.crop((x0, 0, x1, h))
        dx = (h - (x1 - x0)) // 2
        sheet.paste(frame, ((i % cols) * h + dx, (i // cols) * h))
    return sheet, frames, h, cols, rows


def main(argv):
    if len(argv) != 2:
        raise SystemExit(__doc__)
    z = zipfile.ZipFile(argv[1])
    names = z.namelist()

    def find(suffix):
        hits = [n for n in names if n.replace("\\", "/").endswith(suffix)]
        return hits[0] if hits else None

    def read_text(suffix):
        n = find(suffix)
        return z.read(n).decode("utf-8", "replace") if n else ""

    forms = blocks(read_text("PBS/pokemon_forms_gmax_megas_Gen_9_Pack.txt"))
    metrics = blocks(read_text("PBS/pokemon_metrics_gmax_megas_Gen_9_Pack.txt"))
    keys = sorted(os.path.splitext(n.split("/")[-1])[0] for n in names
                  if "/Graphics/Pokemon/Front/" in n and n.endswith(".png"))

    out_dir = os.path.join(ROOT, "assets", "bosses")
    os.makedirs(os.path.join(out_dir, "icons"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "cries"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "backs"), exist_ok=True)

    rows_lua = []
    for key in keys:
        entry = {}
        for shiny in (False, True):
            folder = "Front shiny" if shiny else "Front"
            n = find(f"Graphics/Pokemon/{folder}/{key}.png")
            if not n:
                if not shiny:
                    raise SystemExit(f"{key}: no front strip")
                continue
            strip = Image.open(io.BytesIO(z.read(n))).convert("RGBA")
            sheet, frames, cell, cols, rows = grid(strip)
            sheet.save(os.path.join(out_dir, f"{key}{'_shiny' if shiny else ''}.png"), optimize=True)
            if not shiny:
                entry.update(frames=frames, cell=cell, cols=cols, rows=rows)
            else:
                entry["shiny"] = True
            back = find(f"Graphics/Pokemon/{'Back shiny' if shiny else 'Back'}/{key}.png")
            if back:
                bstrip = Image.open(io.BytesIO(z.read(back))).convert("RGBA")
                bsheet, bframes, bcell, bcols, brows = grid(bstrip)
                bsheet.save(os.path.join(out_dir, "backs", f"{key}{'_shiny' if shiny else ''}.png"), optimize=True)
                if not shiny:
                    entry["back"] = (bframes, bcell, bcols, brows)
            icon = find(f"Graphics/Pokemon/{'Icons shiny' if shiny else 'Icons'}/{key}.png")
            if icon:
                Image.open(io.BytesIO(z.read(icon))).convert("RGBA").save(
                    os.path.join(out_dir, "icons", f"{key}{'_shiny' if shiny else ''}.png"), optimize=True)
        cry = find(f"Audio/SE/Cries/{key}.ogg")
        if cry:
            with open(os.path.join(out_dir, "cries", f"{key}.ogg"), "wb") as f:
                f.write(z.read(cry))
            entry["cry"] = True
        f = forms.get(key, {})
        m = metrics.get(key, {})
        parts = [f"frames = {entry['frames']}", f"cell = {entry['cell']}",
                 f"cols = {entry['cols']}", f"rows = {entry['rows']}"]
        speed = ints(m["AnimationSpeed"]) if "AnimationSpeed" in m else [2]
        parts.append("speed = { " + ", ".join(str(v) for v in speed) + " }")
        if "FrontSprite" in m:
            parts.append("front = { " + ", ".join(str(v) for v in ints(m["FrontSprite"])) + " }")
        if "ShadowSprite" in m:
            parts.append("shadow = { " + ", ".join(str(v) for v in ints(m["ShadowSprite"])) + " }")
        if "BaseStats" in f:
            stats = ints(f["BaseStats"])
            parts.append("base = { " + ", ".join(f"{k} = {v}" for k, v in zip(STAT_ORDER, stats)) + " }")
        if "Types" in f:
            parts.append("types = { " + ", ".join(lua_str(t.strip()) for t in f["Types"].split(",")) + " }")
        if "Height" in f:
            parts.append(f"height = {float(f['Height'])}")
        if "FormName" in f:
            parts.append(f"form = {lua_str(f['FormName'])}")
        if entry.get("back"):
            bf, bc, bco, bro = entry["back"]
            parts.append(f"back = {{ frames = {bf}, cell = {bc}, cols = {bco}, rows = {bro} }}")
        if entry.get("shiny"):
            parts.append("shiny = true")
        if entry.get("cry"):
            parts.append("cry = true")
        rows_lua.append(f"  {key} = {{ " + ", ".join(parts) + " },")
        print(f"{key}: {entry['frames']} frames of {entry['cell']} px, {entry['cols']}x{entry['rows']}")

    head = ("-- Generated by tools/raid_pack.py from the Giga Megas pack (Gen 9 Pack format): Max Raids'\n"
            "-- bosses. Per key: frames, cell (px, square), cols / rows of assets/bosses/<key>.png, speed\n"
            "-- (AnimationSpeed: frames held, Essentials' units), front / shadow (the metrics), base\n"
            "-- (the Giga BaseStats), types (when the form sets them), height (m), form (its name), back\n"
            "-- (assets/bosses/backs/<key>.png's frames, cell, cols / rows: a player's Gigantamaxed one).\n")
    with open(os.path.join(ROOT, "data", "raid_sprites.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(head + "return {\n" + "\n".join(rows_lua) + "\n}\n")
    print(f"{len(keys)} bosses")


if __name__ == "__main__":
    main(sys.argv)
