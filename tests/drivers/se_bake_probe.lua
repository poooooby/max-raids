-- Driver: how long the engine takes to bake each sound the raid plays (data/raid_sounds.lua), cold -
-- the stall a first Audio.playSe costs - and its length in the engine's cache.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/se_bake_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  local S = X and X._test.sounds
  if not S then log("FAIL no sounds table (_test.sounds)"); return end
  local Audio = require("src.core.game3.audio")
  local Warm = require("src.core.game3.warm")
  local Mix = require("src.core.game3.m4a_mix")
  local ids, seen = {}, {}
  local function walk(t)
    for _, v in pairs(t) do
      if type(v) == "string" and v:match("^SE_") and not seen[v] then seen[v] = true; ids[#ids + 1] = v
      elseif type(v) == "table" then walk(v) end
    end
  end
  walk(S)
  table.sort(ids)
  for _ = 1, 3000 do
    if Audio.isReady() then break end
    U.wait(1)
  end
  log("audio ready:", tostring(Audio.isReady()))
  local clock = love.timer.getTime
  local total, frames = 0, 0
  local cap = Audio.SE_RAW_MAX_FRAMES
  Audio.SE_RAW_MAX_FRAMES = math.huge
  collectgarbage("collect")
  local kb0 = collectgarbage("count")
  for _, id in ipairs(ids) do
    local t0 = clock()
    local warmed = Audio.prewarmSe(id, 1)
    Warm.flush("se:" .. tostring(require("src.core.game3.se_ids").resolve(id)))
    local wms = (clock() - t0) * 1000
    t0 = clock()
    Audio.playSe(id)
    local ms = (clock() - t0) * 1000
    t0 = clock()
    Audio.playSe(id)
    local ms2 = (clock() - t0) * 1000
    log(("  prewarm %s %.1f ms, resolve %s, play cold %.1f ms, again %.1f ms"):format(tostring(warmed), wms,
      tostring(require("src.core.game3.se_ids").resolve(id)), ms, ms2))
    total = total + ms
    local e = Audio._seRaw and Audio._seRaw[require("src.core.game3.se_ids").resolve(id)]
    local n = e and e.frames or 0
    frames = frames + n
    log(("%-22s %6.1f ms  %5.2f s"):format(id, ms, n / Mix.SAMPLE_RATE))
  end
  collectgarbage("collect")
  local kb = collectgarbage("count") - kb0
  log(("%d sounds, %.0f ms in all, %.1f s of sound (cache holds %.1f s); heap +%.1f MB, %.0f KB a second of sound"):format(
    #ids, total, frames / Mix.SAMPLE_RATE, cap / Mix.SAMPLE_RATE, kb / 1024, kb / math.max(1, frames / Mix.SAMPLE_RATE)))
  Audio.SE_RAW_MAX_FRAMES = cap
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
