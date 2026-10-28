-- Driver: the raids' music (src/raid_music.lua). Which track plays on the den screen, in the battle and
-- at the catch for a red den (DYNA:ZIGZAGOON:2: Basic), a purple one (CHARIZARD_4: Max), a legendary
-- raid (Max legend) and Eternatus; that the game's own music is faded under it; a loop crossing its
-- loop point (the voice's sample position wraps to the loop's start); and each file's loudness (RMS of
-- its first 20 s, dB) against data/raid_music.lua's MIX.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/music_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local clock = love.timer.getTime
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function secs(s) local t0 = clock(); while clock() - t0 < s do U.wait(1) end end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  local M = R.music_
  check(M ~= nil, "the music player is there")
  -- what each kind of raid plays
  for _, row in ipairs({ { "DYNA:ZIGZAGOON:2", nil, "basic_adventure", "basic_battle", "basic_capture" },
    { "CHARIZARD_4", nil, "max_adventure", "max_battle", "max_capture" },
    { "DYNA:ZIGZAGOON:5:L", true, "max_adventure", "max_battle_legend", "max_capture" },
    { "ETERNATUS_2", nil, "max_adventure", "max_battle_eternatus", "max_capture" } }) do
    local d, b, c = R.musicFor("den", row[1], row[2]), R.musicFor("battle", row[1], row[2]), R.musicFor("capture", row[1], row[2])
    check(d == row[3] and b == row[4] and c == row[5], ("%s: den %s, battle %s, capture %s"):format(row[1], d, b, c))
  end
  -- the den screen, then the raid: the tracks as they play
  R.openDen({ active = true, boss = "DYNA:ZIGZAGOON:2", stars = 2 })
  secs(1.2)
  check(M.playing() == "basic_adventure", "the den screen: " .. tostring(M.playing()))
  local Audio = require("src.core.game3.audio")
  log("the game's music meanwhile:", tostring(Audio._bgmFadeTarget or Audio._currentSong or Audio.current and Audio.current()))
  R.denStart()
  waitFor(function() local c = R.current(); return c and c.phase == "intro" end, 2000)
  secs(1)
  check(M.playing() == "basic_battle", "the raid: " .. tostring(M.playing()))
  -- a loop's seam: the voice moved to a second before its loop's end, then played past it
  local v = M._cur and M._cur()
  if v then
    v.dec:seek((v.loopEnd - v.rate) / v.rate)
    v.pos = v.loopEnd - v.rate
    secs(2.5)
    log(("past the loop's end: position %d (loop %d..%d)"):format(v.pos, v.t.loopStart, v.loopEnd))
    check(v.pos > v.t.loopStart and v.pos < v.t.loopStart + v.rate * 3, "the loop wrapped to its start")
  else
    check(false, "a voice to look at")
  end
  X.close()
  secs(1.2)
  check(M.playing() == nil, "closed: the raid's music faded away")
  -- each file's loudness
  local D = M._data
  for _, name in ipairs({ "basic_adventure", "basic_battle", "basic_capture", "max_adventure", "max_battle",
    "max_battle_legend", "max_battle_eternatus", "max_capture" }) do
    local rms = M._loudness and M._loudness(name, 20)
    if rms then
      local played = rms + 20 * math.log10(D.MIX * (D.TRACKS[name].gain or 1))
      log(("loudness %-22s %.1f dB RMS, %.1f dB as played (gain %.2f)"):format(name, rms, played, D.TRACKS[name].gain or 1))
    end
  end
  log(("%d failures"):format(fails))
end

return function(game)
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  love.event.quit()
end
