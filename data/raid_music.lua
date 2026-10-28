-- The raids' music (assets/music/, from Lucidious89's [DBK] Raid Battles: its Basic and Max sets,
-- Sword / Shield's tracks). Each track's loop is its file's own LOOPSTART / LOOPLENGTH (samples), as
-- Pokemon Essentials plays them; src/raid_music.lua loops it there.
-- Which plays (the plugin's RaidType.rb and Battle Setup.rb, mapped onto ours):
--   the den screen   SET's adventure (the plugin's Raid Adventure / Dynamax Adventure lair map)
--   the battle       SET's battle (v1); a Dynamax Crystal's legendary raid the Max set's legend (v2:
--                    the plugin's rank-7 raids and an Adventure's final boss); Eternatus its own (v3)
--   the catch        SET's capture, from the ask until the ball clicks
-- SET: a red den (a Pokemon of the route, Dynamaxed) "basic"; a purple den (Gigantamax) and a
-- legendary raid "max". (The plugin's Basic battle v2, for its rank-7 raids, has no place here.)
local M = {}

M.TRACKS = {
  basic_adventure = { file = "assets/music/basic_adventure.ogg", loopStart = 305222, loopLength = 2520772, gain = 0.88 },
  basic_battle = { file = "assets/music/basic_battle.ogg", loopStart = 608580, loopLength = 4519599, gain = 0.60 },
  basic_capture = { file = "assets/music/basic_capture.ogg", loopStart = 1195098, loopLength = 1071746, gain = 0.64 },
  max_adventure = { file = "assets/music/max_adventure.ogg", loopStart = 842233, loopLength = 3837443, gain = 0.74 },
  max_battle = { file = "assets/music/max_battle.ogg", loopStart = 962313, loopLength = 2309551, gain = 1.00 },
  max_battle_legend = { file = "assets/music/max_battle_legend.ogg", loopStart = 842233, loopLength = 3837443, gain = 1.00 },
  max_battle_eternatus = { file = "assets/music/max_battle_eternatus.ogg", loopStart = 494726, loopLength = 4277283, gain = 0.68 },
  max_capture = { file = "assets/music/max_capture.ogg", loopStart = 1610182, loopLength = 142972, gain = 0.79 },
}

-- Eternatus' National Dex number (its own battle track)
M.ETERNATUS = 890

-- each track's `gain`: brought to the game's own music as heard (-19.5 dB RMS, measured through its
-- player: PlayNav's tests/drivers/music_level_probe.lua) from its own (music_probe.lua's loudness:
-- the first 20 s), never above 1; the game's music volume times that times MIX, faded over FADE_S
-- on a change
M.TARGET_DB = -19.5
M.MIX = 1
M.FADE_S = 0.8

return M
