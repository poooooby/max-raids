-- Driver: held items in the raid through the real engine's item data and damage: the hold effects
-- the adapter reads (Leftovers, Sitrus Berry, Lum Berry, Choice Band, Focus Band, Quick Claw ...), their
-- names, Leftovers and a Sitrus Berry in a turn, Lum curing a status, Choice Band's power and hold,
-- Charcoal's boost, Magic Room.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/held_items_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
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
  local X = game.mods.exports.max_raids
  local Bt, Sim = X._test.battle, X._test.sim
  s0.party = {}
  Party.giveMon(s0, C:require("species", "SPECIES_BLAZIKEN"), 70)
  local mon = s0.party[1]
  local function item(name) return C:require("items", name) end

  -- a fresh duel: the member holding `held` with `moves` against a boss whose move is `bossMove`
  local function duel(held, moves, o)
    o = o or {}
    love.math.setRandomSeed(o.seed or 7)
    local rng = o.rng or function(lo, hi) return love.math.random(lo, hi) end
    mon.item = held and item(held) or 0
    local mem = Bt.member(mon)
    mem.moves = {}
    for i, name in ipairs(moves or { "TACKLE" }) do mem.moves[i] = assert(Bt.move(name), name) end
    mem.maxMoves = {}
    mem.mon.hp, mem.mon.maxHp = 300, 300
    mem.mon.speed = o.speed or 999
    local boss = Bt.boss("MACHAMP_2", rng)
    boss.mon.hp, boss.mon.maxHp = 100000, 100000
    boss.moves = { assert(Bt.move(o.bossMove or "SPLASH")) }
    boss.gmax, boss.script = nil, {}
    boss.shield, boss.shields, boss.segments = nil, nil, nil
    if o.bossSpeed then boss.mon.speed = o.bossSpeed end
    local A = Bt.adapter(rng)
    local sim = Sim.new{ boss = boss, members = { mem }, adapter = A, rng = rng, rules = { TURNS = 30, FAINTS = 4 } }
    return sim, boss, mem, A
  end
  local function texts(ev) local t = {} for _, e in ipairs(ev) do if e.text then t[#t + 1] = e.text end end return table.concat(t, " | ") end
  local function has(ev, text) return texts(ev):find(text, 1, true) ~= nil end

  -- what the adapter reads off each item
  do
    local want = { ITEM_LEFTOVERS = "LEFTOVERS", ITEM_SITRUS_BERRY = "RESTORE_HP", ITEM_LUM_BERRY = "CURE_STATUS",
      ITEM_CHOICE_BAND = "CHOICE_BAND", ITEM_FOCUS_BAND = "FOCUS_BAND", ITEM_QUICK_CLAW = "QUICK_CLAW",
      ITEM_BRIGHT_POWDER = "EVASION_UP", ITEM_KINGS_ROCK = "FLINCH", ITEM_SHELL_BELL = "SHELL_BELL",
      ITEM_WHITE_HERB = "RESTORE_STATS", ITEM_LEPPA_BERRY = "RESTORE_PP", ITEM_LIECHI_BERRY = "ATTACK_UP",
      ITEM_MACHO_BRACE = "MACHO_BRACE", ITEM_FIGY_BERRY = "CONFUSE_SPICY", ITEM_CHARCOAL = "FIRE_POWER" }
    local _, _, _, A = duel()
    for name, he in pairs(want) do
      local got, p = A.held({ item = item(name), mon = mon })
      check(got == he, ("%s holds %s (%s, %s) %q"):format(name, he, tostring(got), tostring(p), A.itemName(item(name))))
    end
  end

  -- Leftovers: a sixteenth at the turn's end
  do
    local sim, _, m = duel("ITEM_LEFTOVERS")
    m.mon.hp = 100
    local ev = sim:turn({ { move = 1 } })
    check(m.mon.hp == 100 + math.floor(300 / 16) and has(ev, "using its Leftovers"), ("Leftovers: %d HP (%s)"):format(m.mon.hp, texts(ev)))
  end

  -- a Sitrus Berry after the boss's blow takes it under half
  do
    local sim, _, m = duel("ITEM_SITRUS_BERRY", nil, { bossMove = "CROSS_CHOP", bossSpeed = 9999, speed = 1 })
    m.mon.hp = 160
    local ev = sim:turn({ { move = 1 } })
    check(m.item == 0 and has(ev, "Sitrus Berry restored its health"), "Sitrus Berry eaten: " .. texts(ev))
  end

  -- Lum Berry against a paralysing move
  do
    local sim, _, m = duel("ITEM_LUM_BERRY", nil, { bossMove = "THUNDER_WAVE", bossSpeed = 9999, speed = 1 })
    local ev = sim:turn({ { move = 1 } })
    check(m.status == nil and m.item == 0 and has(ev, "Lum Berry cured"), "Lum Berry: " .. texts(ev))
  end

  -- Choice Band: x1.5 physical damage through the engine, and the hold
  do
    local fixed = function(lo, hi) return hi end
    local _, boss, m, A = duel(nil, { "CRUSH_CLAW", "FLAMETHROWER" }, { rng = fixed })
    local plain = A.damage(m, boss, m.moves[1], false, {})
    local sim2, boss2, m2, A2 = duel("ITEM_CHOICE_BAND", { "CRUSH_CLAW", "FLAMETHROWER" }, { rng = fixed })
    local banded = A2.damage(m2, boss2, m2.moves[1], false, {})
    check(math.abs(banded - plain * 1.5) <= plain * 0.05 + 2, ("Choice Band: %d -> %d"):format(plain, banded))
    sim2:turn({ { move = 1 } })
    check(sim2:barredWhy(m2, m2.moves[2]) == "Choice Band", "Choice Band holds it to Crush Claw (" .. tostring(sim2:barredWhy(m2, m2.moves[2])) .. ")")
    -- Charcoal: Fire moves x1.1
    local _, b3, m3, A3 = duel("ITEM_CHARCOAL", { "FLAMETHROWER" }, { rng = fixed })
    local _, b4, m4, A4 = duel(nil, { "FLAMETHROWER" }, { rng = fixed })
    local c1, c0 = A3.damage(m3, b3, m3.moves[1], false, {}), A4.damage(m4, b4, m4.moves[1], false, {})
    check(c1 > c0, ("Charcoal: Flamethrower %d -> %d"):format(c0, c1))
  end

  -- Magic Room: Leftovers do nothing
  do
    local sim, _, m = duel("ITEM_LEFTOVERS")
    m.mon.hp = 100
    sim.ndx.magicRoom = 3
    sim:turn({ { move = 1 } })
    check(m.mon.hp == 100, "Magic Room: no Leftovers")
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
