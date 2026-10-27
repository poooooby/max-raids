-- Driver: the Dynamax Crystal's legendary raid. Two crystals in the bag; a quiet den (shot k01: the
-- crystal over EXIT), the crystal used (k02: a legendary's silhouette, 5 stars), put away and used
-- again from an active den (k03), START (the crystal spent, k04 the intro), the raid closed; the den
-- left as it was; a Poke Ball always catching a legendary; the legendary list (logged).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/crystal_probe.lua love .

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
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  local X = game.mods.exports.max_raids
  local R, Dy = X.raid, X._test.dyna
  local nd = game.mods.exports.national_dex_gen3
  local id = nd and nd.dynamax and nd.dynamax.ids.DYNAMAX_CRYSTAL
  check(id ~= nil, "National Dex has the Dynamax Crystal (" .. tostring(id) .. ")")
  if not id then return end
  local legends = Dy.legends()
  local names = {}
  for _, slot in ipairs(legends) do names[#names + 1] = tostring(Dy.idOf(slot)) end
  log(("legendary Pokemon (%d): %s"):format(#legends, table.concat(names, ", ")))
  check(#legends > 20, "the legendary list")

  Bag.add(s0.bag, id, 2)
  check(R.crystals() == 2, "two crystals in the bag")
  -- a quiet den
  local quiet = { active = false, x = 0, y = 0 }
  R.openDen(quiet)
  U.wait(40)
  shot("k01_quiet")
  check(R.useCrystal(), "the crystal used at a quiet den")
  U.wait(40)
  shot("k02_legend")
  local key = R.current().key
  local b = X._test.dyna.record(key)
  log("legendary:", key, b and b.name, b and b.stars)
  check(b and b.legend and b.stars == 5, "a 5-star legendary raid")
  check(R.putCrystalAway() and R.current().key == nil, "put away: the quiet den again")
  R.close()
  U.wait(20)
  -- an active den: the crystal over START, START spends it
  local den = { active = true, boss = "DYNA:ZIGZAGOON:2", stars = 2, x = 0, y = 0 }
  R.openDen(den)
  U.wait(30)
  check(R.useCrystal(), "the crystal used at an active den")
  U.wait(30)
  shot("k03_active_legend")
  R.denStart()
  check(R.crystals() == 1, "START spends one crystal")
  waitFor(function() local c = R.current(); return c and c.phase == "intro" end, 6000)
  U.wait(240)
  shot("k04_intro")
  local cur = R.current()
  log("raid boss:", cur and cur.boss and cur.boss.name, cur and cur.boss and cur.boss.mon.level)
  R.close()
  U.wait(30)
  check(den.active == true and not den.done, "the den left as it was")
  -- a legendary is always caught
  local Rw = X._test.rewards
  Bag.add(s0.bag, C:require("items", "ITEM_POKE_BALL"), 20)
  local caught = 0
  for _ = 1, 10 do
    local ok, got = pcall(Rw.throw, key, 60, { item = C:require("items", "ITEM_POKE_BALL"), mult = 1 },
      function(lo, hi) return hi end)
    if ok and got then caught = caught + 1 end
  end
  check(caught == 10, "a Poke Ball catches a legendary every time (" .. caught .. "/10, the worst rolls)")
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
