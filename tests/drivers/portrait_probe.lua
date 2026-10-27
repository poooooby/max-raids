-- Driver: the raid on a portrait screen (a phone held upright, PROBE_W x PROBE_H, 540 x 1170). Shots
-- p01 the den screen, p02 the commands, p03 the moves (opened by a tap on Fight where the pad is
-- drawn - Rd.uiBox's band), p04 a turn's words, p05 the catch, p06 the rewards card.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/portrait_probe.lua love .

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
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local W, H = tonumber(os.getenv("PROBE_W")) or 540, tonumber(os.getenv("PROBE_H")) or 1170
  love.window.setMode(W, H, { resizable = true, highdpi = true })
  U.wait(4)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  local X = game.mods.exports.max_raids
  local R, Pad = X.raid, X._test.pad
  log("window", love.graphics.getWidth(), love.graphics.getHeight())
  R.openDen({ active = true, boss = "CHARIZARD_4", stars = 4, x = 0, y = 0 })
  U.wait(60)
  shot("p01_den")
  R.denStart()
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  U.wait(20)
  shot("p02_commands")
  local cur = R.current()
  log(("ui band %s, card %s"):format(tostring(cur.uiBand), tostring(cur.uiCard)))
  check((cur.uiBand or 0) > 0, "a portrait screen: the UI's foot shifted down")
  -- a tap on Fight where it is drawn
  local f = Pad.where.fight
  local fx, fy = f.x + f.w / 2, f.y + f.h / 2 + (cur.uiBand or 0)
  R.pointer({ x = fx, y = fy, phase = "pressed", id = "mouse" })
  R.pointer({ x = fx, y = fy, phase = "released", id = "mouse" })
  U.wait(20)
  check(cur.cmd.menu == "moves", "a tap on Fight (at its drawn place) opens the moves")
  shot("p03_moves")
  for _ = 1, 4 do
    local c = R.current().cmd
    if c and c.actor then R.choose("fight"); R.choose("move1") end
  end
  waitFor(function() local c = R.current(); return c and c.say end, 2000)
  U.wait(30)
  shot("p04_words")
  R.current().sim.over = "win"
  R.startCatch()
  U.wait(40)
  shot("p05_catch")
  R.startRewards()
  U.wait(80)
  shot("p06_rewards")
  R.close()
  log(("%d failures"):format(fails))
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
