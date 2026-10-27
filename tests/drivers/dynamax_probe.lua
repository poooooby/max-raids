-- Driver: the team's Dynamax in a raid. Party: Charizard (G-Max Factor, Dynamax Level 10), Gardevoir,
-- Metagross, Salamence; boss PROBE_BOSS (SNORLAX_2). Turn 1: member 1 holds the Energy, Fight ->
-- DYNAMAX -> its first move (shots m01 the list lit, m02..m04 the growing, m05 giant on its turn, m06
-- its G-Max Move), the next turns' Max Moves until it reverts (m07), the HUD's marks, the Energy
-- passing on (logged). Then a catch's Dynamax marks through Rewards.throw (logged).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dynamax_probe.lua love .

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
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  local nd = game.mods.exports.national_dex_gen3
  local Dx = nd and nd.dynamax
  check(Dx ~= nil, "National Dex's Dynamax is there")
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_CHARIZARD", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  if Dx then Dx.setFactor(s0.party[1], true); Dx.setLevel(s0.party[1], 10) end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  X.open(os.getenv("PROBE_BOSS") or "SNORLAX_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local cur = R.current()
  local m1 = cur.members[1].b
  log(("member 1: %s canDmax %s level %s gmax %s mult %s"):format(m1.name, tostring(m1.canDmax), tostring(m1.dmaxLevel),
    tostring(m1.gmaxId), tostring(m1.dmaxMult)))
  for i, mv in ipairs(m1.moves) do
    local mx = m1.maxMoves[i]
    log(("  %s (%s %d) -> %s %d"):format(mv.name, mv.typeName, mv.power or 0, mx.name, mx.power or 0))
  end
  check(cur.sim.energy == 1, "turn 1: slot 1 holds the Energy")
  -- member 1: Fight, DYNAMAX, its first damaging move
  R.choose("fight")
  U.wait(4)
  check(R.choose("dynamax"), "DYNAMAX toggles on")
  U.wait(20)
  shot("m01_list")
  local slot = 1
  for i, mv in ipairs(m1.moves) do if not mv.status and mv.typeName == "FIRE" then slot = i; break end end
  R.choose("move" .. slot)
  for _ = 2, 4 do
    local c = R.current().cmd
    if c and c.actor then R.choose("fight"); R.choose("move1") end
  end
  -- the transformation
  waitFor(function() local e = R.current().events; return e and e[R.current().evI] and e[R.current().evI].kind == "dynamax" end, 3000)
  -- (on the raid's own clock: a driver runs faster than the wall's)
  local t0 = R.current().t
  local function at(s) waitFor(function() return R.current().t >= t0 + s end, 4000) end
  at(0.45); shot("m02_charge")
  at(1.3); shot("m03_grow")
  at(1.9); shot("m04_giant")
  check(m1.dmax ~= nil and m1.mon.maxHp > 0, ("Dynamaxed: HP %d/%d"):format(m1.mon.hp, m1.mon.maxHp))
  local sheet = R.current().members[1].gmaxSheet
  check(sheet and sheet.key == "CHARIZARD_4", "its Gigantamax form's back sheet: " .. tostring(sheet and sheet.key))
  -- its G-Max Move
  local seenMax = false
  local deadline = clock() + 40
  while clock() < deadline and not seenMax do
    local c = R.current()
    local e = c.events and c.events[c.evI]
    if e and e.kind == "use" and e.who == m1 then
      log("member 1 used", e.move.name)
      secs(1.6); shot("m05_gmax")
      seenMax = true
    end
    U.wait(1)
  end
  check(seenMax, "its G-Max Move")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  shot("m06_hud")
  check(R.current().sim.energy == nil, "no Energy while it is Dynamaxed")
  -- two more turns: Max Moves, then back to its size
  local reverted = false
  for _ = 1, 3 do
    local c = R.current().cmd
    local guard = 0
    while c and c.actor and guard < 20 do
      guard = guard + 1
      R.choose("fight"); R.choose("move1")
      c = R.current().cmd
      -- (a move asking whom: the first it can)
      if c and c.menu == "target" then
        for k, row in ipairs(c.moveList or {}) do
          if row.live ~= false then R.choose("move" .. k); break end
        end
        c = R.current().cmd
      end
    end
    deadline = clock() + 40
    while clock() < deadline and X.state().active do
      local cc = R.current()
      local e = cc.events and cc.events[cc.evI]
      if e and e.kind == "dynamaxEnd" and not reverted then
        reverted = true
        secs(0.5); shot("m07_revert")
      end
      if cc.phase == "command" and not cc.say then break end
      U.wait(1)
    end
    if not X.state().active then break end
  end
  check(reverted and m1.dmax == nil, "back to its size after three turns")
  log("Energy now with", tostring(R.current() and R.current().sim and R.current().sim.energy))
  X.close()
  U.wait(30)

  -- a catch's marks: a Gigantamax boss's catch carries the factor and a level for its stars
  local Rw = X._test.rewards
  local Bag = require("src.core.game3.bag")
  Bag.add(s0.bag, C:require("items", "ITEM_MASTER_BALL"), 2)
  local ball = { item = C:require("items", "ITEM_MASTER_BALL"), mult = 0 }
  for _, key in ipairs({ "CHARIZARD_4", "DYNA:ZIGZAGOON:2" }) do
    local okT, caught, info = pcall(Rw.throw, key, 40, ball, function(lo, hi) return math.random(lo, hi) end)
    local mon = okT and caught and info and info.mon
    if mon and Dx then
      log(("caught %s: Dynamax Level %d, G-Max Factor %s"):format(key, Dx.level(mon), tostring(Dx.hasFactor(mon))))
      if key == "CHARIZARD_4" then check(Dx.hasFactor(mon) and Dx.level(mon) >= 4 and Dx.level(mon) <= 5, "a 4-star G-Max catch: the factor, level 4-5")
      else check(not Dx.hasFactor(mon) and Dx.level(mon) >= 2 and Dx.level(mon) <= 3, "a 2-star Dynamax catch: level 2-3, no factor") end
    else
      check(false, "caught " .. key .. " (" .. tostring(caught) .. " " .. tostring(info) .. ")")
    end
  end
  local items = Rw.rollItems("CHARIZARD_4", function(lo, hi) return math.random(lo, hi) end)
  local dc = 0
  for _, it in ipairs(items) do if Dx and it.id == Dx.ids.DYNAMAX_CANDY then dc = it.n end end
  check(dc == 1, "a 4-star raid drops one Dynamax Candy")
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
