-- Driver: Galar Rising's achievements against the real recomp_achievements. The 14 are registered
-- under mod:max_raids; a den opened awards Into the Den; a raid played - a Dynamax with the
-- Gigantamax factor, the win, a sure catch of a shiny - awards Go Big, Gigantamax!, Raid Rookie,
-- Untouched, Quick Work, Giant Slayer, Gotcha, Giant! and Shiny Raider; a Run awards Blown Away; the
-- win counts a save holds (a crystal's legendary raid, a 5-star) award Crystal Clear and Five-Star
-- General on a sweep. Shots a*.png (the unlock pop-ups over the raid).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/ach_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
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
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
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
  local ach = game.mods.exports.recomp_achievements
  local X = game.mods.exports.max_raids
  if not (ach and X) then log("FAIL recomp_achievements and max_raids must both be installed"); return end
  local R = X.raid
  local nd = game.mods.exports.national_dex_gen3
  local Dx = nd and nd.dynamax

  -- Charizard with the Gigantamax factor first, then three more
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_CHARIZARD", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  if Dx then Dx.setFactor(s0.party[1], true); Dx.setLevel(s0.party[1], 10) end
  for _, k in ipairs({ "ITEM_POKE_BALL", "ITEM_ULTRA_BALL" }) do pcall(Bag.add, s0.bag, C:id("items", k), 5) end
  U.wait(30)

  local function key(id) return "mod:max_raids:" .. id end
  local function got(id) return ach.isUnlocked(key(id)) == true end
  local function value(id)
    local row = ach.get(key(id))
    local v = row and row.progress
    if type(v) == "table" then v = v.value or v[1] end
    return v
  end

  -- ------------------------------------------------------------ registered
  check(X.achievements and X.achievements.active(), "the module is connected to the framework")
  local rows = ach.list({ source = "mod:max_raids" })
  check(#rows == 14, "14 registered under mod:max_raids (" .. tostring(#rows) .. ")")
  local hidden = 0
  for _, row in ipairs(rows) do if row.hidden then hidden = hidden + 1 end end
  check(hidden == 2, "two of them hidden")
  for _, id in ipairs({ "first_den", "first_raid", "quick_work", "blown_away" }) do
    check(not got(id), id .. " is not earned yet")
  end

  -- ------------------------------------------------------------ a den opened
  check(R.openDen({ active = false }), "a quiet den opened")
  waitFor(function() return R.current() and R.current().t > 0.4 end, 300)
  U.wait(30)
  check(got("first_den"), "Into the Den")
  secs(0.8)
  shot("a01_den")
  X.close()
  waitFor(function() return not X.state().active end, 600)

  -- ------------------------------------------------------------ a raid: Dynamax, the win, the catch
  R.FORCE_SHINY = true
  R.SPEED = 8
  local den = { active = true, boss = "MACHAMP_2", stars = 3 }
  check(R.openDen(den), "a 3-star den opened")
  waitFor(function() return R.current() and R.current().t > 0.4 end, 300)
  R.denStart()
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  U.wait(20)
  local cur = R.current()
  local m1 = cur.members[1].b
  check(m1.canDmax ~= false and m1.gmaxId ~= nil, "member 1 can Dynamax, with its Gigantamax factor")
  -- a damaging single-target move for each member
  local function pick(m)
    local slot
    for k, mv in ipairs(m.b.moves) do
      if (mv.pp or 0) > 0 and (mv.power or 0) > 0 and not mv.friendly and not mv.spread and not mv.team then slot = k; break end
    end
    return slot or 1
  end
  R.choose("fight"); U.wait(4)
  check(R.choose("dynamax"), "member 1: DYNAMAX")
  R.choose("move" .. pick(cur.members[1]))
  local guard = 0
  while X.state().phase == "command" and guard < 40 do
    guard = guard + 1
    local c = R.current()
    local m = c.cmd and c.members[c.cmd.actor]
    if c.cmd.menu == "main" and m then
      R.choose("fight"); U.wait(2)
      R.choose("move" .. pick(m))
    end
    U.wait(2)
  end
  check(X.state().phase == "battle", "all four in: the turn plays")
  waitFor(function()
    if X.state().phase == "battle" then R.playEvents(true) end
    return X.state().phase ~= "battle"
  end, 6000)
  check(got("go_big") and got("gigantamax"), "Go Big and Gigantamax!")
  check(not got("first_raid"), "no win yet")

  -- the win, as after a real one (its last words up when the catch begins)
  R.say("Machamp fainted!")
  R.startCatch()
  U.wait(40)
  check(got("first_raid"), "Raid Rookie")
  check(got("untouched"), "Untouched")
  check(got("quick_work"), "Quick Work (3 stars, " .. tostring(R.current().sim.turnNo) .. " turns)")
  check(got("giant_slayer"), "Giant Slayer")
  check(not got("gotcha_giant"), "not caught yet")
  check(value("den_delver") == 1, "Den Delver at 1 of 25 (" .. tostring(value("den_delver")) .. ")")
  secs(1.0)
  shot("a02_win")

  -- a sure catch (the Master Ball's odds), the raid's shiny kept
  local Rw = X._test.rewards
  local real = Rw.throw
  Rw.throw = function(...)
    local a = { ... }
    local sure = {}
    for k, v in pairs(a[3]) do sure[k] = v end
    sure.mult = 0
    a[3] = sure
    return real(unpack(a, 1, 7))
  end
  waitFor(function() return X.state().phase == "catch" end, 600)
  check(R.pickBall(1), "a ball thrown")
  waitFor(function() return X.state().phase == "rewards" end, 6000)
  U.wait(30)
  check(got("gotcha_giant"), "Gotcha, Giant!")
  check(got("shiny_raider"), "Shiny Raider")
  secs(0.8)
  shot("a03_caught")
  Rw.throw = real
  R.FORCE_SHINY = nil
  X.close()
  waitFor(function() return not X.state().active end, 1200)
  U.wait(10)

  -- ------------------------------------------------------------ Run
  check(not got("blown_away"), "not blown away yet")
  den = { active = true, boss = "CHARIZARD_4", stars = 4 }
  R.openDen(den)
  waitFor(function() return R.current() and R.current().t > 0.4 end, 300)
  R.denStart()
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  U.wait(20)
  R.choose("run")
  U.wait(10)
  U.tap(game, "up"); U.wait(4)
  U.tap(game, "a"); U.wait(4)
  check(R.current() and R.current().phase == "blown", "Yes: blown out of the den")
  waitFor(function() return not X.state().active end, 1200)
  U.wait(20)
  check(got("blown_away"), "Blown Away")

  -- ------------------------------------------------------------ the win counts a save holds
  check(not got("crystal_clear") and not got("five_star"), "no 5-star win yet, no crystal's raid")
  Rw.give({ key = "DYNA:MEWTWO:5:L", sim = {} }, function(lo, hi) return lo end)
  check(not got("crystal_clear"), "the win is counted, not yet swept")
  X.achievements.sweep()
  U.wait(10)
  check(got("crystal_clear"), "Crystal Clear (a legendary raid won, from the save's win counts)")
  check(got("five_star"), "Five-Star General (the same win: 5 stars)")

  local earned, points = 0, 0
  for _, row in ipairs(ach.list({ source = "mod:max_raids", unlocked = true })) do
    earned = earned + 1
    points = points + (row.points or 0)
  end
  log(("earned %d of 14, %d points"):format(earned, points))
  check(earned == 12, "12 earned (Den Delver and Gigantamax Gallery still to come)")
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
