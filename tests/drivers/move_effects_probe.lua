-- Driver: the Gen 3 moves' and National Dex Gen 3's newer moves' effects through the real engine's
-- damage and move data: a member with real moves against a boss that does nothing, the sim run turn
-- by turn (no screens). Absorb / Drain Punch heal, Double-Edge / Wave Crash recoil, a multi-hit string,
-- Hyper Beam's recharge, a charge turn, Outrage, Fake Out, weather, Dream Eater, a type chart check.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/move_effects_probe.lua love .

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

  -- a fresh duel: the member with `moves` (names) against a boss whose own move does nothing
  local function duel(moves, o)
    o = o or {}
    -- (seeded: every run plays the same)
    love.math.setRandomSeed(o.seed or 7)
    local rng = o.rng or function(lo, hi) return love.math.random(lo, hi) end
    local mem = Bt.member(mon)
    mem.moves = {}
    for i, name in ipairs(moves) do mem.moves[i] = assert(Bt.move(name), name) end
    mem.maxMoves = {}
    mem.mon.hp, mem.mon.maxHp = 300, 300
    mem.mon.speed = 999
    local boss = Bt.boss("MACHAMP_2", rng)
    boss.mon.hp, boss.mon.maxHp = 100000, 100000
    boss.moves = { assert(Bt.move("SPLASH")) }
    boss.gmax, boss.script = nil, {}
    boss.shield, boss.shields, boss.segments = nil, nil, nil
    if o.bossTypes then boss.type1, boss.type2 = o.bossTypes[1], o.bossTypes[2] end
    local sim = Sim.new{ boss = boss, members = { mem }, adapter = Bt.adapter(rng), rng = rng, rules = { TURNS = 30, FAINTS = 4 } }
    boss.shield = nil
    return sim, boss, mem
  end
  local function texts(ev) local t = {} for _, e in ipairs(ev) do if e.text then t[#t + 1] = e.text end end return table.concat(t, " | ") end
  local function count(ev, kind) local n = 0 for _, e in ipairs(ev) do if e.kind == kind then n = n + 1 end end return n end
  local function has(ev, text) return texts(ev):find(text, 1, true) ~= nil end
  local function turn(sim, slot) return sim:turn({ { move = slot or 1 } }) end

  -- the data the audit found missing
  for _, n in ipairs({ "ABSORB", "DRAIN_PUNCH", "HORN_LEECH", "DOUBLE_EDGE", "WAVE_CRASH", "FURY_ATTACK", "HYPER_BEAM",
    "GIGA_IMPACT", "SOLAR_BEAM", "OUTRAGE", "FAKE_OUT", "RAIN_DANCE", "DREAM_EATER", "SURF", "EARTHQUAKE" }) do
    local m = Bt.move(n)
    check(m ~= nil, n .. " is a move")
  end
  local ab = Bt.move("ABSORB")
  check(ab.side and ab.side.drain == 50, "Absorb drains half")
  local dp = Bt.move("DRAIN_PUNCH")
  check(dp.side and dp.side.drain == 50, "Drain Punch (a newer move) drains half")
  local de, wc = Bt.move("DOUBLE_EDGE"), Bt.move("WAVE_CRASH")
  check(de.side and de.side.drain == -33 and wc.side and wc.side.drain == -33, "Double-Edge and Wave Crash recoil a third")

  -- drain
  do
    local sim, boss, m = duel({ "ABSORB", "DRAIN_PUNCH" })
    m.mon.hp = 100
    local ev = turn(sim)
    local dealt = 100000 - boss.mon.hp
    check(dealt > 0 and m.mon.hp == math.min(300, 100 + math.floor(dealt / 2 + 0.5)), ("Absorb: %d dealt, healed to %d"):format(dealt, m.mon.hp))
    check(count(ev, "heal") == 1 and has(ev, "energy drained"), "...announced")
    m.mon.hp = 100
    local b0 = boss.mon.hp
    local evd = turn(sim, 2)
    local d2 = b0 - boss.mon.hp
    check(d2 > 0 and m.mon.hp > 100, ("Drain Punch: %d dealt, healed to %d (%s)"):format(d2, m.mon.hp, texts(evd)))
  end

  -- recoil
  do
    local sim, boss, m = duel({ "DOUBLE_EDGE", "WAVE_CRASH" })
    m.mon.hp, m.mon.maxHp = 300, 300
    turn(sim)
    local dealt = 100000 - boss.mon.hp
    check(dealt > 0 and 300 - m.mon.hp == math.floor(dealt * 33 / 100 + 0.5), ("Double-Edge: %d dealt, %d recoil"):format(dealt, 300 - m.mon.hp))
  end

  -- multi-hit
  do
    local sim, boss, m = duel({ "FURY_ATTACK" }, { rng = function(lo, hi) return lo end })
    local ev = turn(sim)
    local n = count(ev, "damage")
    check(n >= 2 and n <= 5, "Fury Attack struck " .. n .. " times")
    check(has(ev, "Hit " .. n .. " times"), "...counted")
  end

  -- Dream Eater
  do
    local sim, boss, m = duel({ "DREAM_EATER" })
    local ev = turn(sim)
    check(has(ev, "doesn't affect") and boss.mon.hp == 100000, "Dream Eater fails on an awake boss")
    boss.status, boss.sleep = "SLP", 5
    m.mon.hp = 100
    turn(sim)
    check(boss.mon.hp < 100000 and m.mon.hp > 100, "...and works on a sleeping one")
  end

  -- Hyper Beam: recharge
  do
    local sim, boss, m = duel({ "HYPER_BEAM", "GIGA_IMPACT" })
    turn(sim)
    check(m.recharge and not sim:canAct(1), "Hyper Beam: must recharge")
    local ev = sim:turn({})
    check(has(ev, "must recharge"), "...the next turn is lost")
    check(sim:canAct(1), "...then it chooses again")
  end

  -- a charge turn
  do
    local sim, boss, m = duel({ "SOLAR_BEAM" })
    local ev = turn(sim)
    check(boss.mon.hp == 100000 and m.lock, "Solar Beam: a turn to charge (" .. texts(ev) .. ")")
    local ev2 = sim:turn({})
    check(boss.mon.hp < 100000 and not m.lock, "...the second turn strikes")
  end

  -- Outrage
  do
    local sim, boss, m = duel({ "OUTRAGE" })
    local turns = 0
    repeat
      if turns == 0 then turn(sim) else sim:turn({}) end
      turns = turns + 1
    until not m.lock or turns > 5
    check(turns == 2 or turns == 3, "Outrage: " .. turns .. " turns")
    check(m.confused ~= nil, "...then confused")
  end

  -- Fake Out
  do
    local sim, boss, m = duel({ "FAKE_OUT" })
    turn(sim)
    local b1 = boss.mon.hp
    check(b1 < 100000, "Fake Out lands on the first turn")
    local ev = turn(sim)
    check(boss.mon.hp == b1 and has(ev, "failed"), "...and fails on the second")
  end

  -- weather: the engine's damage with and without the rain (fixed rolls, no crits)
  do
    local sim, boss, m = duel({ "RAIN_DANCE", "SURF" })
    turn(sim)
    check(sim.weather == "RAIN", "Rain Dance: rain")
    local A = Bt.adapter(function(lo, hi) return hi end)
    local surf = m.moves[2]
    local dry = A.damage(m, boss, surf, false, {})
    local wet = A.damage(m, boss, surf, false, { weather = "RAIN" })
    local sun = A.damage(m, boss, surf, false, { weather = "SUN" })
    check(wet > dry and sun < dry, ("Surf: rain %d, clear %d, sun %d"):format(wet, dry, sun))
  end

  -- type matchups: Water on Fire is super effective, Water on Grass not very, Electric on Ground nothing
  do
    local sim, boss, m = duel({ "SURF" }, { bossTypes = { 10, nil } })
    local ev = turn(sim)
    check(has(ev, "super effective"), "Water on a Fire boss: super effective")
    sim, boss, m = duel({ "SURF" }, { bossTypes = { 12, nil } })
    ev = turn(sim)
    check(has(ev, "not very effective"), "Water on a Grass boss: not very effective")
    sim, boss, m = duel({ "EARTHQUAKE" }, { bossTypes = { 2, nil } })
    ev = turn(sim)
    check(has(ev, "doesn't affect") and boss.mon.hp == 100000, "Ground on a Flying boss: no effect")
  end

  -- the type chart in the damage itself (fixed rolls): Water x2 on Fire, x0.5 on Grass, x1 on Fighting;
  -- a move keeps its own type (none turned Electric)
  do
    local A = Bt.adapter(function(lo, hi) return hi end)
    local _, boss, m = duel({ "SURF", "FLAMETHROWER", "EARTHQUAKE" })
    local function dmgOn(slot, t1)
      boss.type1, boss.type2 = t1, nil
      local d, info = A.damage(m, boss, m.moves[slot], false, {})
      return d, info
    end
    local neutral = dmgOn(1, 1)
    local onFire = dmgOn(1, 10)
    local onGrass = dmgOn(1, 12)
    check(math.abs(onFire - 2 * neutral) <= 2 and math.abs(onGrass - neutral / 2) <= 2,
      ("Surf: Fighting %d, Fire %d, Grass %d"):format(neutral, onFire, onGrass))
    local fn = dmgOn(2, 1)
    local fw = dmgOn(2, 11)
    local fg = dmgOn(2, 12)
    check(math.abs(fw - fn / 2) <= 2 and math.abs(fg - 2 * fn) <= 2,
      ("Flamethrower (with STAB): Fighting %d, Water %d, Grass %d"):format(fn, fw, fg))
    local eqSteel = dmgOn(3, 8)
    local eqN = dmgOn(3, 1)
    check(math.abs(eqSteel - 2 * eqN) <= 2, ("Earthquake: Fighting %d, Steel %d"):format(eqN, eqSteel))
  end

  -- the National Dex's rules through the real damage (fixed rolls)
  do
    local A = Bt.adapter(function(lo, hi) return hi end)
    local sim, boss, m = duel({ "HEX", "FLAMETHROWER", "TACKLE", "THUNDERBOLT", "GYRO_BALL", "FINAL_GAMBIT" })
    for _, k in ipairs({ "HEX", "TAR_SHOT", "TRICK_OR_TREAT", "ELECTRIC_TERRAIN", "WONDER_ROOM", "GYRO_BALL", "FINAL_GAMBIT",
      "SURGING_STRIKES", "STEALTH_ROCK", "LASER_FOCUS", "SOAK" }) do
      local mv = Bt.move(k)
      check(mv and mv.side and mv.side.rule ~= nil, k .. " carries its rule (" .. tostring(mv and mv.side and mv.side.rule) .. ")")
    end
    boss.type1, boss.type2 = 1, nil
    local function d(slot, o) local x, info = A.damage(m, boss, m.moves[slot], false, o or { turn = 1 }); return x, info end
    local hex0 = d(1)
    boss.status = "PAR"
    local hex1 = d(1)
    boss.status = nil
    check(math.abs(hex1 - 2 * hex0) <= 2, ("Hex doubles on a statused boss (%d -> %d)"):format(hex0, hex1))
    local f0 = d(2)
    boss.__ndxTarShot = true
    local f1 = d(2)
    boss.__ndxTarShot = nil
    check(math.abs(f1 - 2 * f0) <= 2, ("Tar Shot: Fire hits twice as hard (%d -> %d)"):format(f0, f1))
    boss.__ndxType3 = 7
    local t0, ti = d(3)
    check(A.effectiveness(0, boss) == 0, "Trick-or-Treat's Ghost type: Normal moves no longer reach it")
    boss.__ndxType3 = nil
    local e0 = d(4, { turn = 1, field = {} })
    local e1 = d(4, { turn = 1, field = { terrain = "ELECTRIC", terrainTurns = 5 } })
    check(e1 > e0 * 1.2, ("Electric Terrain powers Thunderbolt (%d -> %d)"):format(e0, e1))
    boss.mon.defense, boss.mon.spDef = 300, 80
    local w0 = d(2, { turn = 1, field = {} })
    local w1 = d(2, { turn = 1, field = { wonderRoom = 5 } })
    check(w1 < w0, ("Wonder Room swaps Defense and Sp. Def (%d -> %d)"):format(w0, w1))
    m.mon.speed, boss.mon.speed = 50, 400
    local g = d(5)
    m.mon.speed = 400
    local g2 = d(5)
    check(g > g2 * 2, ("Gyro Ball: harder when the user is slower (%d vs %d)"):format(g, g2))
    m.mon.hp = 123
    local fg = d(6)
    check(fg == 123, "Final Gambit: damage equal to the user's HP (" .. fg .. ")")
    m.__ndxLaserFocus = 1
    local _, li = d(3, { turn = 2 })
    m.__ndxLaserFocus = nil
    check(li.critical == true, "Laser Focus: the next turn's move is a critical hit")
  end

  -- Stealth Rock on a Fire / Flying member coming back: half its HP
  do
    local sim, boss, m = duel({ "TACKLE" })
    m.type1, m.type2 = 10, 2
    sim.sides.team.hazards.stealthRock = true
    m.mon.hp = 0
    sim:fainted({}, m)
    sim:turn({})
    sim:turn({})
    check(m.mon.hp == 150, "Stealth Rock: x4 on Fire / Flying, half its HP (" .. m.mon.hp .. ")")
  end

  -- Surging Strikes: three blows, every one a critical hit
  do
    local sim, boss, m = duel({ "SURGING_STRIKES" })
    local ev = turn(sim)
    local crits = 0
    for _, e in ipairs(ev) do if e.kind == "crit" then crits = crits + 1 end end
    check(count(ev, "damage") == 3 and crits == 3, ("Surging Strikes: %d blows, %d critical"):format(count(ev, "damage"), crits))
  end

  -- Gen 3's own moves through the real engine
  do
    for _, k in ipairs({ "METRONOME", "SUBSTITUTE", "PRESENT", "BEAT_UP", "ROLLOUT", "SLEEP_TALK", "TRANSFORM",
      "BRICK_BREAK", "ENCORE", "PERISH_SONG", "BATON_PASS", "STOCKPILE", "MIRROR_MOVE", "COPYCAT" }) do
      local mv = Bt.move(k)
      check(mv and mv.side and (mv.side.g3 or mv.side.rule) ~= nil, k .. " is carried out (" .. tostring(mv and mv.side and (mv.side.g3 or mv.side.rule)) .. ")")
    end
    -- Metronome calls a real move
    local sim, boss, m = duel({ "METRONOME" })
    local ev = turn(sim)
    local uses = 0
    for _, e in ipairs(ev) do if e.kind == "use" and e.who == m then uses = uses + 1 end end
    check(uses == 2, "Metronome: then the move it called (" .. texts(ev) .. ")")
    -- Counter: twice the physical damage it took this turn
    sim, boss, m = duel({ "COUNTER" }, { rng = function(lo, hi) return lo end })
    boss.moves = { assert(Bt.move("TACKLE")) }
    boss.mon.speed = 9999
    m.mon.speed = 1
    local hp0 = m.mon.hp
    local b0 = boss.mon.hp
    turn(sim)
    local took = hp0 - m.mon.hp
    check(took > 0 and b0 - boss.mon.hp == 2 * took, ("Counter: took %d, struck back %d"):format(took, b0 - boss.mon.hp))
    -- Substitute takes the boss's Tackle
    sim, boss, m = duel({ "SUBSTITUTE" })
    boss.moves = { assert(Bt.move("TACKLE")) }
    ev = turn(sim)
    check(m.mon.hp == 300 - 75 and has(ev, "substitute"), "Substitute: a quarter of the HP, the Tackle on it")
    -- Transform into the boss
    sim, boss, m = duel({ "TRANSFORM" })
    boss.moves = { assert(Bt.move("CROSS_CHOP")), assert(Bt.move("BULK_UP")) }
    turn(sim)
    check(m.transformed and m.type1 == boss.type1 and m.moves[1].name == boss.moves[1].name and m.moves[1].pp == 5,
      "Transform: the boss's type and moves, 5 PP each")
    -- Rollout: double each turn
    sim, boss, m = duel({ "ROLLOUT" }, { rng = function(lo, hi) return lo end })
    turn(sim)
    local r1 = 100000 - boss.mon.hp
    sim:turn({})
    local r2 = 100000 - boss.mon.hp - r1
    check(r2 > r1 * 1.6, ("Rollout: %d, then %d"):format(r1, r2))
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
