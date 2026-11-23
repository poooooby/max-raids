-- The Dynamax scene's sounds, one audio atlas (assets/dmax/sounds.ogg; tools/dmax_sound_atlas.py
-- writes both): each clip's first sample and sample count at `rate`, `channels` channels. From
-- Pokemon Essentials v21.1 (Audio/SE) and the Deluxe Battle Kit (Audio/SE/DX Action), as the
-- [DBK] Dynamax plugin's Dynamax animation plays them.
return {
  rate = 44100, channels = 2, samples = 529601,
  clips = {
    recall = { start = 11025, count = 20599 },  -- Audio/SE/Battle recall.ogg
    throw = { start = 42649, count = 30288 },  -- Audio/SE/Battle throw.ogg
    psych_up = { start = 83962, count = 91495 },  -- Audio/SE/Anim/Psych Up.ogg
    earth1 = { start = 186482, count = 35420 },  -- Audio/SE/Anim/Earth1.ogg
    explosion3 = { start = 232927, count = 97536 },  -- Audio/SE/Anim/Explosion3.ogg
    dx_action = { start = 341488, count = 177088 },  -- Audio/SE/DX Action.ogg
  },
}
