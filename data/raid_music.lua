-- The raids' music (assets/music/): eight original tracks made for Galar Rising, a "basic" set and
-- a "max" set. Each track's loop is its file's own
-- LOOPSTART / LOOPLENGTH (samples, 48 kHz), found where the song repeats, on the beat, with a 0.6 s
-- crossfade into the loop's start baked in before its end; src/raid_music.lua loops it there.
-- Which plays:
--   the den screen   SET's adventure
--   the battle       SET's battle; a Dynamax Crystal's legendary raid max_battle_legend; Eternatus its own
--   the catch        SET's capture, from the ask until the ball clicks
-- SET: a red den (a Pokemon of the route, Dynamaxed) "basic"; a purple den (Gigantamax) and a
-- legendary raid "max".
local M = {}

M.TRACKS = {
  basic_adventure = { file = "assets/music/basic_adventure.ogg", loopStart = 1267200, loopLength = 2879904, gain = 0.69 },
  basic_battle = { file = "assets/music/basic_battle.ogg", loopStart = 3038400, loopLength = 3560736, gain = 0.86 },
  basic_capture = { file = "assets/music/basic_capture.ogg", loopStart = 2889600, loopLength = 3482976, gain = 0.78 },
  max_adventure = { file = "assets/music/max_adventure.ogg", loopStart = 2851200, loopLength = 2879568, gain = 0.73 },
  max_battle = { file = "assets/music/max_battle.ogg", loopStart = 576000, loopLength = 4053072, gain = 1.00 },
  max_battle_legend = { file = "assets/music/max_battle_legend.ogg", loopStart = 753600, loopLength = 3014112, gain = 0.84 },
  max_battle_eternatus = { file = "assets/music/max_battle_eternatus.ogg", loopStart = 2256000, loopLength = 5154672, gain = 0.67 },
  max_capture = { file = "assets/music/max_capture.ogg", loopStart = 811200, loopLength = 3332832, gain = 0.99 },
}

-- Eternatus' National Dex number (its own battle track)
M.ETERNATUS = 890

-- each track's `gain`: brought to the game's own music as heard (-19.5 dB RMS, measured through its
-- player: PlayNav's tests/drivers/music_level_probe.lua) from its loop's own RMS, never above 1;
-- the game's music volume times that times MIX, faded over FADE_S on a change
M.TARGET_DB = -19.5
M.MIX = 1
M.FADE_S = 0.8

return M
