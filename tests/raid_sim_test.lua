-- The raid's turns, headless: src/raid_sim.lua with a fake adapter (fixed damage, every move hits).
--   luajit tests/raid_sim_test.lua   (from the repo root)

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local Sim = assert(loadstring(read("src/raid_sim.lua"), "@src/raid_sim.lua"))()

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

-- a seeded generator
local function rngOf(seed)
  local s = seed
  return function(lo, hi)
    s = (1103515245 * s + 12345) % 2147483648
    return lo + s % (hi - lo + 1)
  end
end

local function stages() return { attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0, accuracy = 0, evasion = 0 } end
local function mv(name, o)
  o = o or {}
  return { name = name, power = o.power or 50, status = o.status or false, priority = o.priority or 0,
    spread = o.spread or false, side = o.side, pp = 10, maxPp = 10, type = o.type or 0, accuracy = 100 }
end
local function battler(name, hp, speed, moves, boss)
  return { name = name, mon = { hp = hp, maxHp = hp, speed = speed }, stages = stages(), moves = moves,
    boss = boss, type1 = 0 }
end

-- the fake adapter: damage is the move's power (x2 when `double` names the target), all moves hit
local function adapter(o)
  o = o or {}
  return {
    damage = function(att, def, m) return m.power, { effectiveness = (o.eff and o.eff[def.name]) or 1 } end,
    hits = function() return o.miss ~= true end,
    speed = function(b) return b.mon.speed end,
    effectiveness = function() return 1 end,
  }
end
local function team(n, hp, speeds)
  local t = {}
  for i = 1, n do t[i] = battler("M" .. i, hp or 100, speeds and speeds[i] or 50, { mv("Tackle", { power = 10 }) }) end
  return t
end
local function all(n) local c = {} for i = 1, n do c[i] = { move = 1 } end return c end
local function kinds(ev) local k = {} for _, e in ipairs(ev) do k[#k + 1] = e.kind end return table.concat(k, ",") end

-- order: by speed, the boss among them
do
  local boss = battler("Boss", 1000, 60, { mv("Hit", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = team(4, 100, { 10, 90, 40, 70 }), adapter = adapter(), rng = rngOf(1) }
  local ev = s:turn(all(4))
  local order = {}
  for _, e in ipairs(ev) do if e.kind == "use" then order[#order + 1] = e.who.name end end
  check(table.concat(order, " ") == "M2 M4 Boss M3 M1", "speed order: " .. table.concat(order, " "))
  check(boss.mon.hp == 960, "four hits of 10 on the boss")
  check(s.turnNo == 2, "the turn moves on")
end

-- priority before speed
do
  local boss = battler("Boss", 1000, 200, { mv("Hit", { power = 1 }) }, true)
  local m = team(1, 100, { 10 })
  m[1].moves[1] = mv("Quick Attack", { power = 10, priority = 1 })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(2) }
  local ev = s:turn(all(1))
  local first
  for _, e in ipairs(ev) do if e.kind == "use" then first = first or e.who.name end end
  check(first == "M1", "priority goes first")
end

-- the boss falls: won, and nothing after it
do
  local boss = battler("Boss", 15, 1, { mv("Hit", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = team(4, 100, { 50, 40, 30, 20 }), adapter = adapter(), rng = rngOf(3) }
  local ev = s:turn(all(4))
  check(s.over == "win", "the boss down: won")
  check(ev[#ev].kind == "over" and ev[#ev].outcome == "win", "the last event says so")
  local uses = 0
  for _, e in ipairs(ev) do if e.kind == "use" then uses = uses + 1 end end
  check(uses == 2, "no move after the boss falls (" .. uses .. ")")
end

-- a member down sits the next turn out and comes back at full HP; every knock-out counts
do
  local boss = battler("Boss", 100000, 100, { mv("Crush", { power = 200 }) }, true)
  local s = Sim.new{ boss = boss, members = team(1, 100), adapter = adapter(), rng = rngOf(4),
    rules = { TURNS = 10, FAINTS = 4 } }
  s:turn(all(1))
  check(s.faints == 1 and not s:canAct(1), "knocked out: it cannot act next turn")
  local ev = s:turn(all(1))
  check(kinds(ev):find("back") ~= nil and s.members[1].mon.hp == 100, "back at full HP after a turn out")
  check(s:canAct(1), "and acts again")
end

-- four knock-outs: lost
do
  local boss = battler("Boss", 100000, 100, { mv("Quake", { power = 500, spread = true }) }, true)
  local s = Sim.new{ boss = boss, members = team(4, 100), adapter = adapter(), rng = rngOf(5),
    rules = { TURNS = 10, FAINTS = 4 } }
  local ev = s:turn(all(4))
  check(s.over == "faints", "a spread move knocks out all four: lost")
  local hit = 0
  for _, e in ipairs(ev) do if e.kind == "damage" then hit = hit + 1 end end
  check(hit == 4, "the spread move hit every member (" .. hit .. ")")
  check(ev[#ev].text == "You were blown out of the den!", "blown out")
end

-- the storm: ten turns
do
  local boss = battler("Boss", 1000000, 1, { mv("Tap", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = team(4, 1000), adapter = adapter(), rng = rngOf(6),
    rules = { TURNS = 10, FAINTS = 4 } }
  local n = 0
  while not s.over and n < 20 do s:turn(all(4)); n = n + 1 end
  check(s.over == "storm" and n == 10, ("the storm after ten turns (%s after %d)"):format(tostring(s.over), n))
end

-- status: sleep skips moves, a stat drop clamps at -6, a type immune to poison stays clean
do
  local boss = battler("Boss", 100000, 1, { mv("Sleep Powder", { status = true, power = 0, side = { status = "SLP" } }) }, true)
  local m = team(1, 1000, { 50 })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(7) }
  s:turn(all(1))
  check(m[1].status == "SLP", "put to sleep")
  local ev = s:turn(all(1))
  check(kinds(ev):find("cant") ~= nil, "asleep: it cannot move")

  local boss2 = battler("Boss", 100000, 1, { mv("Screech", { status = true, power = 0, side = { stages = { defense = -2 } } }) }, true)
  local m2 = team(1, 1000)
  local s2 = Sim.new{ boss = boss2, members = m2, adapter = adapter(), rng = rngOf(8), rules = { TURNS = 20, FAINTS = 4 } }
  for _ = 1, 5 do s2:turn(all(1)) end
  check(m2[1].stages.defense == -6, "Defense held at -6")

  local boss3 = battler("Boss", 100000, 1, { mv("Toxic", { status = true, power = 0, side = { status = "TOX" } }) }, true)
  local m3 = team(1, 1000)
  m3[1].type1 = 8
  local s3 = Sim.new{ boss = boss3, members = m3, adapter = adapter(), rng = rngOf(9) }
  local ev3 = s3:turn(all(1))
  check(m3[1].status == nil and kinds(ev3):find("fail") ~= nil, "a Steel type is not poisoned")
end

-- poison bites at the turn's end, toxic harder each turn
do
  local boss = battler("Boss", 100000, 1, { mv("Toxic", { status = true, power = 0, side = { status = "TOX" } }) }, true)
  local m = team(1, 1600)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(10) }
  s:turn({})
  local after1 = m[1].mon.hp
  s:turn({})
  check(after1 == 1500 and m[1].mon.hp == 1300, ("toxic 1/16 then 2/16 (%d, %d)"):format(after1, m[1].mon.hp))
end

-- an immunity: no damage, the words for it
do
  local boss = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = team(1), adapter = adapter({ eff = { Boss = 0 } }), rng = rngOf(11) }
  local ev = s:turn(all(1))
  check(boss.mon.hp == 1000 and kinds(ev):find("effect") ~= nil, "no effect on an immune boss")
end

-- a newer move's extra (the National Dex's): src/battle.lua turns it into a side the sim runs
do
  local N = assert(loadstring(read("data/raid_rules.lua"), "@data/raid_rules.lua"))()
  local mod = { log = { warn = function() end } }
  local Bt = assert(loadstring(read("src/battle.lua"), "@src/battle.lua"))()(mod, { N = N, Bosses = {}, Sprites = {} })
  local workUp = Bt.extraSide({ kind = "status", self = { attack = 1, spAtk = 1 }, chance = 100 })
  check(workUp and workUp.self and workUp.selfStages.attack == 1 and workUp.chance == nil, "Work Up: its user, no chance roll")
  local fang = Bt.extraSide({ kind = "hit", ailment = "BURN", ailmentChance = 10 })
  check(fang and fang.status == "BRN" and fang.statusChance == 10, "Fire Fang: a 10% burn")
  local closeCombat = Bt.extraSide({ kind = "hit", self = { defense = -1, spDef = -1 }, chance = 100 })
  check(closeCombat and not closeCombat.self and closeCombat.selfStages.defense == -1, "Close Combat lowers its user's")

  local boss = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  local m = team(1, 100, { 50 })
  m[1].moves[1] = mv("Work Up", { status = true, power = 0, side = workUp })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(12) }
  s:turn(all(1))
  check(m[1].stages.attack == 1 and m[1].stages.spAtk == 1 and boss.stages.attack == 0, "Work Up raises its user's Attack and Sp. Atk")

  local boss2 = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  local m2 = team(1, 100, { 50 })
  m2[1].mon.hp = 50
  m2[1].moves[1] = mv("Drain Punch", { power = 40, side = { drain = 50 } })
  local s2 = Sim.new{ boss = boss2, members = m2, adapter = adapter(), rng = rngOf(13) }
  s2:turn(all(1))
  check(m2[1].mon.hp == 69, ("drains half the damage (50 + 20 - 1: %d)"):format(m2[1].mon.hp))

  local boss3 = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  local m3 = team(1, 100, { 50 })
  m3[1].moves[1] = mv("Brave Bird", { power = 60, side = { drain = -33 } })
  local s3 = Sim.new{ boss = boss3, members = m3, adapter = adapter(), rng = rngOf(14) }
  s3:turn(all(1))
  check(m3[1].mon.hp == 79, ("recoil a third of the damage (100 - 20 - 1: %d)"):format(m3[1].mon.hp))
end

-- ------- the raid's own rules (data/raid_rules.lua)
local RULES = assert(loadstring(read("data/raid_rules.lua"), "@data/raid_rules.lua"))().RAID

-- the barrier: up at its threshold, a quarter damage, a segment a hit, broken with Def / Sp. Def -2
do
  local boss = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.shields, boss.segments = { 0.7 }, 2
  local m = team(1, 1000, { 50 })
  m[1].moves[1] = mv("Slam", { power = 400 })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(21), rules = RULES }
  local ev = s:turn(all(1))
  check(boss.shield and boss.shield.left == 2, "a barrier of two at 70%")
  check(kinds(ev):find("shield") ~= nil, "the barrier's words")
  s:turn(all(1))
  check(boss.mon.hp == 500 and boss.shield.left == 1, ("a quarter through it, a segment off (hp %d)"):format(boss.mon.hp))
  local ev3 = s:turn(all(1))
  check(boss.shield == nil and boss.stages.defense == -2 and boss.stages.spDef == -2, "broken: Def and Sp. Def -2")
  local broke = false
  for _, e in ipairs(ev3) do if e.kind == "shield" and e.step == "break" then broke = true end end
  check(broke, "the barrier's break is an event")
end

-- the G-Max move on its script's turns, on all four, its effect after
do
  local boss = battler("Boss", 100000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.gmax = mv("G-Max Volt Crash", { power = 5, spread = true })
  boss.gmax.isGmax = true
  boss.gmax.gmaxEffect = { kind = "status", list = { "PAR" } }
  boss.script = RULES.SCRIPTS.basic
  local m = team(4, 1000)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(22), rules = RULES }
  local ev1 = s:turn(all(4))
  local early = false
  for _, e in ipairs(ev1) do if e.kind == "use" and e.gmax then early = true end end
  check(not early, "turn 1: no G-Max (the basic script's from turn 2)")
  local ev2 = s:turn(all(4))
  local gm, para = false, 0
  for _, e in ipairs(ev2) do
    if e.kind == "use" and e.gmax then gm = true end
    if e.kind == "status" and e.status == "PAR" then para = para + 1 end
  end
  check(gm and para == 4, ("turn 2: G-Max on all four, all paralysed (%d)"):format(para))
end

-- a G-Max field hurts every member not of its type at the turn's end, for its turns
do
  local boss = battler("Boss", 100000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.gmax = mv("G-Max Wildfire", { power = 1, spread = true })
  boss.gmax.gmaxEffect = { kind = "field", turns = 4, frac = 6, spare = "FIRE", spareNum = 10 }
  boss.script = { { kind = "gmax", every = 99, from = 1 } }
  local m = team(2, 600)
  m[2].type1 = 10
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(23), rules = RULES,
    words = { fieldHurt = { FIRE = "{MON} burns" } } }
  s:turn(all(2))
  check(m[1].mon.hp == 600 - 1 - 100 and m[2].mon.hp == 600 - 1, ("1/6 to the non-Fire one only (%d, %d)"):format(m[1].mon.hp, m[2].mon.hp))
  for _ = 1, 4 do s:turn(all(2)) end
  check(s.field == nil, "the field runs out")
end

-- a member sitting out cheers; the pouch: a Potion, a Revive back at once (the knock-out counted)
do
  local boss = battler("Boss", 100000, 1, { mv("Crush", { power = 200 }) }, true)
  local m = team(2, 100, { 50, 40 })
  local rules = {}
  for k, v in pairs(RULES) do rules[k] = v end
  rules.CHEER = { { id = "attack", w = 1 } }
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(24), rules = rules }
  -- (the boss hits one at random: play until someone is down)
  local n = 0
  while s.faints == 0 and n < 10 do s:turn(all(2)); n = n + 1 end
  local downI = (m[1].down or 0) > 0 and 1 or 2
  local upI = 3 - downI
  local ev = s:turn({ [upI] = { move = 1 } })
  local cheered = false
  for _, e in ipairs(ev) do if e.kind == "cheer" and e.cheer == "attack" then cheered = true end end
  check(cheered, "the one sitting out cheers (Attack up)")
  check(s:pouchLeft("revive") == 1, "a Revive in the pouch")
  boss.moves[1].power = 0
  boss.moves[1].status, boss.moves[1].side = true, nil
  local before = s.faints
  -- a fresh knock-out to revive
  m[upI].mon.hp = 0
  s:fainted({}, m[upI])
  m[downI].down, m[downI].mon.hp = 0, 100
  s:turn({ [downI] = { item = "revive", target = upI } })
  check(m[upI].down == 0 and m[upI].mon.hp == 50 and s.faints == before + 1, "a Revive: back at half HP, the faint counted")
  check(s:pouchLeft("revive") == 0, "the Revive is used up")
  m[downI].mon.hp = 20
  s:turn({ [downI] = { item = "potion", target = downI } })
  check(m[downI].mon.hp == 70 and s:pouchLeft("potion") == 1, ("a Potion: half the HP (%d)"):format(m[downI].mon.hp))
end

-- the wipe and the aura
do
  local boss = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.script = { { kind = "wipe", every = 1, from = 1 }, { kind = "statup", hpBelow = 0.5, once = true } }
  local m = team(1, 1000, { 50 })
  m[1].moves[1] = mv("Swords Dance", { status = true, power = 0, side = { stages = { attack = 2 }, self = true } })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(25), rules = RULES }
  s:turn(all(1))
  check(m[1].stages.attack == 0, "the wipe clears the team's raised stats")
  boss.mon.hp = 400
  s:turn(all(1))
  check(boss.stages.attack == 1 and boss.stages.defense == 1, "the aura at half HP: +1 all round")
  s:turn(all(1))
  check(boss.stages.attack == 1, "only once")
end

-- the catch's chance and the reward rolls (src/rewards.lua's pure parts; no engine here)
do
  local N = assert(loadstring(read("data/raid_rules.lua"), "@data/raid_rules.lua"))()
  local store = {}
  local mod = { log = { warn = function() end }, save = { get = function(_, k) return store[k] end, set = function(_, k, v) store[k] = v end } }
  local Rw = assert(loadstring(read("src/rewards.lua"), "@src/rewards.lua"))()(mod, { N = N, Bosses = {}, Sprites = {} })
  check(Rw.chance(1, 1) == 90 and Rw.chance(5, 1) == 30, "the tier's chance with a Poke Ball")
  check(Rw.chance(3, 1.5) == 90 and Rw.chance(1, 2) == 100, "a Great / Ultra Ball's multiplier, held to 100")
  check(Rw.chance(5, 0) == 100, "a Master Ball never misses")
  local rng = rngOf(31)
  local seenLow, seenHigh = false, false
  for _ = 1, 200 do
    for _, it in ipairs(Rw.rollItems(1, 1, rng)) do
      if it.name == "ITEM_PP_MAX" or it.name == "ITEM_BIG_PEARL" then seenHigh = true end
      seenLow = true
    end
  end
  check(seenLow and not seenHigh, "a 1-star raid rolls only its tier's items")
  local most = 0
  for _ = 1, 200 do
    local n = 0
    for _, it in ipairs(Rw.rollItems(5, 3, rng)) do n = n + it.n end
    most = math.max(most, n)
  end
  check(most > 4, ("a 5-star raid with both bonuses rolls more (%d)"):format(most))
end

-- the same seed, the same turn
do
  local function run()
    local boss = battler("Boss", 1000, 50, { mv("A", { power = 5 }), mv("B", { power = 7 }) }, true)
    local s = Sim.new{ boss = boss, members = team(4, 100, { 50, 50, 50, 50 }), adapter = adapter(), rng = rngOf(42) }
    local out = {}
    for _ = 1, 3 do
      for _, e in ipairs(s:turn(all(4))) do out[#out + 1] = e.kind .. ":" .. (e.text or e.amount or "") end
    end
    return table.concat(out, "|")
  end
  check(run() == run(), "a seed plays the same")
end

print(("%d/%d checks passed  (max_raids sim)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
