"""The Dynamax scene's sounds as one audio atlas: assets/dmax/sounds.ogg + data/dmax_sounds.lua.

The [DBK] Dynamax plugin's animation plays Pokemon Essentials' sound effects (Battle recall, Battle
throw, Anim/Psych Up, Anim/Earth1, Anim/Explosion3) and the Deluxe Battle Kit's DX Action. Each is
decoded to 44.1 kHz stereo 16-bit (ffmpeg), its silent tail trimmed (below TAIL_DB), and laid end to
end with GAP_S of silence between (no clip's edge bleeds into the next once Vorbis-encoded); the
whole encoded once (Vorbis q5). The Lua file gives each clip's first sample and sample count.

    python -I tools/dmax_sound_atlas.py "<Pokemon Essentials v21.1>" "<Deluxe Battle Kit v21.1>"
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE, CHANNELS = 44100, 2
GAP_S = 0.25
TAIL_DB = -60.0

# key -> (which folder, path under it)
CLIPS = [
    ("recall", "essentials", "Audio/SE/Battle recall.ogg"),
    ("throw", "essentials", "Audio/SE/Battle throw.ogg"),
    ("psych_up", "essentials", "Audio/SE/Anim/Psych Up.ogg"),
    ("earth1", "essentials", "Audio/SE/Anim/Earth1.ogg"),
    ("explosion3", "essentials", "Audio/SE/Anim/Explosion3.ogg"),
    ("dx_action", "dbk", "Audio/SE/DX Action.ogg"),
]


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-acodec", "pcm_s16le", "-ar", str(RATE),
         "-ac", str(CHANNELS), "-"],
        check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, dtype=np.int16).reshape(-1, CHANNELS)


def trim_tail(pcm):
    floor = 32767 * (10 ** (TAIL_DB / 20))
    loud = np.nonzero(np.abs(pcm).max(axis=1) > floor)[0]
    if len(loud) == 0:
        return pcm[:1]
    # (a few milliseconds kept past the last sound above the floor)
    return pcm[: min(len(pcm), loud[-1] + int(RATE * 0.02))]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    roots = {"essentials": sys.argv[1], "dbk": sys.argv[2]}
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    gap = np.zeros((int(RATE * GAP_S), CHANNELS), dtype=np.int16)
    parts, rows, at = [gap], [], len(gap)
    for key, root, rel in CLIPS:
        pcm = trim_tail(decode(os.path.join(roots[root], rel)))
        rows.append((key, at, len(pcm), rel))
        parts += [pcm, gap]
        at += len(pcm) + len(gap)
    whole = np.concatenate(parts)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "atlas.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(CHANNELS)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(whole.tobytes())
        out = os.path.join(repo, "assets", "dmax", "sounds.ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    lua = [
        "-- The Dynamax scene's sounds, one audio atlas (assets/dmax/sounds.ogg; tools/dmax_sound_atlas.py",
        "-- writes both): each clip's first sample and sample count at `rate`, `channels` channels. From",
        "-- Pokemon Essentials v21.1 (Audio/SE) and the Deluxe Battle Kit (Audio/SE/DX Action), as the",
        "-- [DBK] Dynamax plugin's Dynamax animation plays them.",
        "return {",
        "  rate = %d, channels = %d, samples = %d," % (RATE, CHANNELS, len(whole)),
        "  clips = {",
    ]
    for key, start, count, rel in rows:
        lua.append('    %s = { start = %d, count = %d },  -- %s' % (key, start, count, rel))
    lua += ["  },", "}", ""]
    with open(os.path.join(repo, "data", "dmax_sounds.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lua))
    for key, start, count, rel in rows:
        print("%-11s %7.3f s at %7.3f s" % (key, count / RATE, start / RATE))
    print("atlas %.2f s, %d bytes" % (len(whole) / RATE, os.path.getsize(out)))


if __name__ == "__main__":
    main()
