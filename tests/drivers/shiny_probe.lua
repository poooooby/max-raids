-- Driver: a shiny raid boss (Rd.FORCE_SHINY): its shiny sheet from the start, the sparkle after its
-- entrance (s01 the G-Max one PROBE_BOSS, CHARIZARD_4; s02 a route one, DYNA:ZIGZAGOON:2), and the
-- catch made shiny or not as the raid rolled it (Rewards.throw, Pokemon.isShiny; gender and IVs kept).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/shiny_probe.lua love .

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 50)
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  R.FORCE_SHINY = true
  for i, key in ipairs({ os.getenv("PROBE_BOSS") or "CHARIZARD_4", "DYNA:ZIGZAGOON:2" }) do
    X.open(key)
    waitFor(function() local c = R.current(); return c and c.phase == "intro" end, 3000)
    local cur = R.current()
    check(cur and cur.shiny == true, key .. ": rolled shiny (forced)")
    waitFor(function() local c = R.current(); return c and (c.t or 0) >= R.INTRO.SHINY_AT + 0.35 end, 20000)
    shot(("s0%d_sparkle"):format(i))
    waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
    shot(("s0%d_battle"):format(i))
    X.close()
    U.wait(20)
  end
  R.FORCE_SHINY = nil
  -- the catch: shiny when the raid was, not when it was not
  local Rw = X._test.rewards
  Bag.add(s0.bag, C:require("items", "ITEM_MASTER_BALL"), 4)
  local ball = { item = C:require("items", "ITEM_MASTER_BALL"), mult = 0 }
  local rng = function(lo, hi) return math.random(lo, hi) end
  for _, want in ipairs({ true, false, true }) do
    local okT, caught, info = pcall(Rw.throw, "DYNA:ZIGZAGOON:2", 30, ball, rng, nil, "F", want)
    local mon = okT and caught and info and info.mon
    if mon then
      local sh = Pokemon.isShiny(mon)
      local g = Pokemon.gender(Pokemon.speciesOf(mon), mon.personality)
      log(("caught shiny %s (wanted %s), gender %s, personality %08x"):format(tostring(sh), tostring(want), g, mon.personality))
      check(sh == want and g == "F", ("the catch: shiny %s as rolled, its gender kept"):format(tostring(want)))
      -- (with the isShiny override set aside: the personality alone says the same)
      local keep = mon.isShiny
      mon.isShiny = nil
      check(Pokemon.isShiny(mon) == want, "... by its personality too")
      mon.isShiny = keep
    else
      check(false, "caught (" .. tostring(caught) .. " " .. tostring(info) .. ")")
    end
  end
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
