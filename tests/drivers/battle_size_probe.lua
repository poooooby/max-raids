-- Driver: an ordinary wild battle (not a raid), to see whether Dynamax Raids changes how it is drawn.
-- A Route 101 battle against PROBE_SPECIES (default ZIGZAGOON, then WAILORD), shot at the command
-- menu; the enemy's front pic as the engine hands it out (its size, a gen3-hd-sprites tag) logged.
-- Run with max_raids on, and compare against the same with it off. Shots n*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/battle_size_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of("emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 20)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  log("max_raids loaded:", tostring(X ~= nil))
  -- PROBE_SUMMARY=1: first a raid with the game's summary opened in it and closed (Wooble
  -- 2026-10-27: after that, ordinary battles drew their Pokemon twice too large)
  if X and os.getenv("PROBE_SUMMARY") == "1" then
    Party.giveMon(s0, C:require("species", "SPECIES_GARDEVOIR"), 40)
    X.open("CHARIZARD_4")
    waitFor(function() return X.state().phase == "command" and not X.raid.current().say end, 20000)
    log("raid up; the summary:", tostring(X.raid.summary()))
    U.wait(120)
    log("shot", U.shot(game, dir .. "/n_0_summary.png") and "ok" or "MISSING")
    for _ = 1, 6 do U.tap(game, "b"); U.wait(20) end
    log("summary closed:", tostring(not X.raid.summaryUp()))
    X.close()
    U.wait(60)
  end
  for _, name in ipairs({ os.getenv("PROBE_SPECIES") or "ZIGZAGOON", "WAILORD" }) do
    local sp = C.species.byName["SPECIES_" .. name]
    local ok, why = BattleBridge.startWild(Runtime._mod, game, { species = sp, level = 10 }, {})
    log("battle against", name, tostring(ok), tostring(why))
    local tap = 0
    for f = 1, 2400 do
      if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
      if Ui.dialogPending and Ui.dialogPending() and f - tap >= 14 then U.tap(game, "a"); tap = f else U.wait(1) end
    end
    U.wait(40)
    -- the enemy's front pic as handed out now
    local foe = Battle._state and Battle._state.enemy
    local mon = foe and (foe.mon or foe)
    local okP, pic = pcall(Pokemon.monFrontPic, mon)
    if okP and type(pic) == "table" then
      local iw, ih = pic.image and pic.image:getDimensions()
      log(("  enemy front pic: image %sx%s, w %s h %s, quad %s, scale %s, frames %s"):format(tostring(iw), tostring(ih),
        tostring(pic.w), tostring(pic.h), tostring(pic.quad ~= nil), tostring(pic.scale or pic.k), tostring(pic.frames)))
    else
      log("  enemy front pic: none", tostring(pic))
    end
    log("shot", U.shot(game, dir .. "/n_" .. name:lower() .. ".png") and "ok" or "MISSING")
    Battle.abort("run")
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(60)
  end
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
