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
  check(boss.mon.hp == 700, ("the hit that crosses 70%% stops there, the rest lost (hp %d)"):format(boss.mon.hp))
  s:turn(all(1))
  check(boss.mon.hp == 600 and boss.shield.left == 1, ("a quarter through it, a segment off (hp %d)"):format(boss.mon.hp))
  local ev3 = s:turn(all(1))
  check(boss.shield == nil and boss.stages.defense == -2 and boss.stages.spDef == -2, "broken: Def and Sp. Def -2")
  local broke = false
  for _, e in ipairs(ev3) do if e.kind == "shield" and e.step == "break" then broke = true end end
  check(broke, "the barrier's break is an event")
end

-- the threshold holds: a blow far past it stops there (no knock-out through a barrier to come), and
-- so does poison at the turn's end, the barrier rising
do
  local boss = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.shields, boss.segments = { 0.7, 0.3 }, 2
  local m = team(1, 1000, { 50 })
  m[1].moves[1] = mv("Slam", { power = 5000 })
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(23), rules = RULES }
  s:turn(all(1))
  check(boss.mon.hp == 700 and boss.shield ~= nil and not s.over,
    ("a blow of 5000 on 1000 HP: held at 70%%, the barrier up, no knock-out (hp %d)"):format(boss.mon.hp))

  local boss2 = battler("Boss", 1000, 1, { mv("Tap", { power = 1 }) }, true)
  boss2.shields, boss2.segments = { 0.7 }, 2
  boss2.mon.hp, boss2.status = 720, "PSN"
  local m2 = team(1, 1000, { 50 })
  m2[1].moves[1] = mv("Growl", { status = true })
  local s2 = Sim.new{ boss = boss2, members = m2, adapter = adapter(), rng = rngOf(24), rules = RULES }
  s2:turn(all(1))
  check(boss2.mon.hp == 700 and boss2.shield ~= nil,
    ("poison past 70%% held there, the barrier up (hp %d)"):format(boss2.mon.hp))

  -- an HP whose 70% is not whole (360: 252): held there and the barrier rises (a share compared
  -- against 0.7 never did, and the boss could not be hurt again)
  local boss3 = battler("Boss", 360, 1, { mv("Tap", { power = 1 }) }, true)
  boss3.shields, boss3.segments = { 0.7, 0.3 }, 2
  local m3 = team(1, 1000, { 50 })
  m3[1].moves[1] = mv("Slam", { power = 5000 })
  local s3 = Sim.new{ boss = boss3, members = m3, adapter = adapter(), rng = rngOf(25), rules = RULES }
  s3:turn(all(1))
  check(boss3.mon.hp == 252 and boss3.shield ~= nil, ("360 HP: held at 252, the barrier up (hp %d)"):format(boss3.mon.hp))
  for _ = 1, 4 do s3:turn(all(1)) end
  check(boss3.mon.hp < 252, ("and hurt again through and past it (hp %d)"):format(boss3.mon.hp))
end

-- the G-Max move on its script's turns: one target struck, its effect on every opponent (Volt Crash
-- paralyzes them all)
do
  local boss = battler("Boss", 100000, 1, { mv("Tap", { power = 1 }) }, true)
  boss.gmax = mv("G-Max Volt Crash", { power = 5, spread = false })
  boss.gmax.isGmax = true
  boss.gmax.gmaxEffect = { kind = "status", list = { "PAR" }, scope = "foes" }
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
  local struck = 0
  for _, e in ipairs(ev2) do if e.kind == "damage" and e.who == boss and e.move == boss.gmax then struck = struck + 1 end end
  check(gm and struck == 1 and para == 4, ("turn 2: G-Max on one, all four paralysed (%d struck, %d)"):format(struck, para))
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
  -- the drops (Sword / Shield's spread): item ids stood in by their names, the candies National Dex's
  Rw.itemId = function(name) return name end
  mod.find = function() return { exports = { expCandies = { EXP_CANDY_XS = "XS", EXP_CANDY_S = "S",
    EXP_CANDY_M = "M", EXP_CANDY_L = "L", EXP_CANDY_XL = "XL" } } } end
  local Bs = { ONE = { stars = 1, types = { "NORMAL" } }, FIVE = { stars = 5, types = { "STEEL" } } }
  Rw = assert(loadstring(read("src/rewards.lua"), "@src/rewards.lua"))()(mod, { N = N, Bosses = Bs, Sprites = {} })
  Rw.itemId = function(name) return name end
  -- (rates need an even generator: the test's rngOf takes an LCG's low bits, patterned for % rolls)
  math.randomseed(31)
  local rng = function(lo, hi) return math.random(lo, hi) end
  local function count(items)
    local c = {}
    for _, it in ipairs(items) do c[it.id] = (c[it.id] or 0) + it.n end
    return c
  end
  local one = count(Rw.rollItems("ONE", rng))
  check(one.XS == 5 and one.S == 1 and not one.L, "a 1-star raid: Exp. Candy XS x5 and S x1")
  local five = count(Rw.rollItems("FIVE", rng))
  check(five.L == 2 and five.XL == 1, "a 5-star raid: Exp. Candy L x2 and XL x1")
  local seen = { berry = 0, nugget = 0, rare = 0, ppmax = 0, ppmax1 = 0 }
  local runs = 2000
  for _ = 1, runs do
    local c = count(Rw.rollItems("FIVE", rng))
    for id in pairs(c) do if tostring(id):find("BERRY", 1, true) then seen.berry = seen.berry + c[id] end end
    if c.ITEM_NUGGET then seen.nugget = seen.nugget + 1 end
    if c.ITEM_RARE_CANDY then seen.rare = seen.rare + 1 end
    if c.ITEM_PP_MAX then seen.ppmax = seen.ppmax + 1 end
    if count(Rw.rollItems("ONE", rng)).ITEM_PP_MAX then seen.ppmax1 = seen.ppmax1 + 1 end
  end
  local function near(v, want, tol) return math.abs(v / runs - want) <= tol end
  check(near(seen.berry, 1.6, 0.1), ("berries: two at 80%% each (%.2f a raid)"):format(seen.berry / runs))
  check(near(seen.nugget, 0.5, 0.05), ("a 5-star Nugget at 50%% (%.2f)"):format(seen.nugget / runs))
  check(near(seen.rare, 0.25, 0.04), ("a Rare Candy at 25%% (%.2f)"):format(seen.rare / runs))
  check(near(seen.ppmax, 0.03, 0.015) and seen.ppmax1 == 0, ("the Bottle Cap's PP Max: 3%% at 5 stars (%.3f), never at 1"):format(seen.ppmax / runs))
end

-- ------- Dynamax (the team's): the Energy, the HP, Max Moves, Max Guard, the rules against a giant
local Gmax = assert(loadstring(read("data/raid_gmax.lua"), "@data/raid_gmax.lua"))()
local MaxPower = assert(loadstring(read("data/raid_maxpower.lua"), "@data/raid_maxpower.lua"))()
local Ndm = assert(loadstring(read("data/raid_rules.lua"), "@data/raid_rules.lua"))()
local Btm = assert(loadstring(read("src/battle.lua"), "@src/battle.lua"))()({ log = { warn = function() end } },
  { N = Ndm, Bosses = {}, Sprites = {}, Gmax = Gmax, MaxPower = MaxPower })
-- a member ready to Dynamax: its moves' Max forms, its level's HP multiplier
local function dmaxTeam(n, hp, level, moveList, gmaxId)
  local t = team(n, hp)
  for _, m in ipairs(t) do
    if moveList then m.moves = moveList() end
    m.dmaxLevel, m.dmaxMult, m.gmaxId = level or 0, 1.5 + 0.05 * (level or 0), gmaxId
    m.maxMoves = {}
    for i, x in ipairs(m.moves) do m.maxMoves[i] = Btm.maxOf(x, gmaxId) end
  end
  return t
end
local function tackle() return { { name = "Tackle", key = "TACKLE", power = 40, type = 0, typeName = "NORMAL", status = false,
  priority = 0, pp = 35, maxPp = 35, accuracy = 100 } } end

-- Max powers: the bands, the moves off them
do
  check(Btm.maxPower(40, "NORMAL", "TACKLE") == 90 and Btm.maxPower(44, "NORMAL") == 90, "under 45: 90")
  check(Btm.maxPower(45, "FIRE") == 100 and Btm.maxPower(75, "FIRE") == 130 and Btm.maxPower(110, "FIRE") == 140
    and Btm.maxPower(150, "FIRE") == 150, "the bands' edges")
  check(Btm.maxPower(90, "FIGHTING") == 90 and Btm.maxPower(40, "POISON") == 70, "Fighting / Poison's column")
  check(Btm.maxPower(25, "GRASS", "BULLET_SEED") == 130 and Btm.maxPower(0, "NORMAL", "RETURN") == 130
    and Btm.maxPower(0, "FIGHTING", "SEISMIC_TOSS") == 75, "the moves off the bands")
  check(Btm.maxPower(0, "NORMAL", "SUPER_FANG") == 100, "no power of its own: 100")
  local guard = Btm.maxOf({ name = "Growl", key = "GROWL", power = 0, status = true, pp = 40, maxPp = 40 })
  check(guard.guard and guard.priority == 4 and guard.name == "Max Guard", "a status move: Max Guard, +4")
  local flare = Btm.maxOf({ name = "Ember", key = "EMBER", power = 40, type = 10, typeName = "FIRE", pp = 25, maxPp = 25 })
  check(flare.name == "Max Flare" and flare.power == 90 and flare.accuracy == 0 and not flare.spread, "Ember -> Max Flare 90, never misses")
  local wild = Btm.maxOf({ name = "Flamethrower", key = "FLAMETHROWER", power = 90, type = 10, typeName = "FIRE", pp = 15, maxPp = 15 }, "WILDFIRE")
  check(wild.name == "G-Max Wildfire" and wild.power == 130 and wild.gmaxEffect.kind == "field", "the factor: Flamethrower -> G-Max Wildfire")
  local fb = Btm.maxOf({ name = "Ember", key = "EMBER", power = 40, type = 10, typeName = "FIRE", pp = 25, maxPp = 25 }, "FIREBALL")
  check(fb.power == 160, "G-Max Fireball's own 160")
  local other = Btm.maxOf({ name = "Air Slash", key = "AIR_SLASH", power = 75, type = 2, typeName = "FLYING", pp = 15, maxPp = 15 }, "WILDFIRE")
  check(other.name == "Max Airstream", "a move of another type stays a Max Move")
end

-- who may Dynamax: any member not yet Dynamaxed, on the field, while no one is giant; one a turn
do
  local boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  local m = dmaxTeam(4, 100, 0, tackle)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(7) }
  check(s:canDynamax(1) and s:canDynamax(2) and s:canDynamax(3) and s:canDynamax(4), "turn 1: any of the four may")
  -- the third Dynamaxes on turn 1, not the first
  local c = all(4)
  c[3].dmax = true
  local ev = s:turn(c)
  check(ev[1].kind == "dynamax" and ev[1].who == m[3], "the third Dynamaxes on turn 1")
  check(not s:canDynamax(1) and not s:canDynamax(2) and not s:canDynamax(4), "no one else while it is giant")
  s:turn(all(4)); s:turn(all(4))
  check(m[3].dmax == nil, "three turns on, it is its own size")
  check(s:canDynamax(1) and s:canDynamax(2) and s:canDynamax(4) and not s:canDynamax(3),
    "then any of the others may, never the one that has")
  -- two choosing it in one turn: the first in party order grows, the other only attacks
  local c2 = all(4)
  c2[2].dmax, c2[4].dmax = true, true
  local ev2 = s:turn(c2)
  local grew = {}
  for _, e in ipairs(ev2) do if e.kind == "dynamax" then grew[#grew + 1] = e.who end end
  check(#grew == 1 and grew[1] == m[2] and m[4].dmax == nil, "one at a time: two asking, the first grows")
  -- one out cannot
  local m2 = dmaxTeam(4, 100, 0, tackle)
  m2[2].mon.hp = 0
  m2[2].down = 1
  local s2 = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), members = m2, adapter = adapter(), rng = rngOf(8) }
  check(not s2:canDynamax(2) and s2:canDynamax(3), "one out cannot, the others can")
end

-- Dynamaxing: HP x the level's, the Max forms, three turns, back with its HP's share, once each
do
  local boss = battler("Boss", 100000, 1, { mv("Hit", { power = 20 }) }, true)
  local m = dmaxTeam(4, 100, 10, tackle)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(9) }
  local c = all(4)
  c[1].dmax = true
  local ev = s:turn(c)
  check(ev[1].kind == "dynamax" and ev[1].who == m[1], "it Dynamaxes before anyone moves")
  check(m[1].dmax and m[1].mon.maxHp == 200, "HP x2 at Dynamax Level 10 (" .. m[1].mon.maxHp .. ")")
  local maxUse
  for _, e in ipairs(ev) do if e.kind == "use" and e.who == m[1] then maxUse = e.move end end
  check(maxUse and maxUse.name == "Max Strike" and boss.mon.hp < 100000, "its Tackle is Max Strike")
  check(m[1].moves[1].pp == 34, "the Max Move spends Tackle's PP")
  check(not s:canDynamax(2), "no one else while one is Dynamaxed")
  s:turn(all(4)); s:turn(all(4))
  check(m[1].dmax == nil and m[1].mon.maxHp == 100, "after three turns: its own size")
  check(m[1].mon.hp > 0 and m[1].mon.hp <= 100, "its HP back to its share (" .. m[1].mon.hp .. ")")
  check(s:canDynamax(2) and not s:canDynamax(1), "free again, never to the one that has used it")
  -- a share: 150 of 200 -> 75 of 100
  local m2 = dmaxTeam(1, 100, 10, tackle)
  local s3 = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 50 }) }, true), members = m2, adapter = adapter(), rng = rngOf(1) }
  local c3 = all(1); c3[1].dmax = true
  s3:turn(c3)
  s3:undynamax({}, m2[1])
  check(m2[1].mon.hp == 75 and m2[1].mon.maxHp == 100, "150 / 200 -> 75 / 100 (" .. m2[1].mon.hp .. ")")
  -- the Dynamax Level's HP: Lv 0 x1.5
  local m4 = dmaxTeam(1, 100, 0, tackle)
  local s4 = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), members = m4, adapter = adapter(), rng = rngOf(2) }
  local c4 = all(1); c4[1].dmax = true
  s4:turn(c4)
  check(m4[1].mon.maxHp == 150, "Dynamax Level 0: x1.5")
end

-- fainting while Dynamaxed: back to its size at once
do
  local boss = battler("Boss", 100000, 99, { mv("Smash", { power = 400 }) }, true)
  local m = dmaxTeam(1, 100, 0, tackle)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(3) }
  local c = all(1); c[1].dmax = true
  local ev = s:turn(c)
  check(m[1].dmax == nil and m[1].mon.maxHp == 100 and (m[1].down or 0) > 0 and s.dmaxActive == nil,
    "fainted: its own size, sitting out")
  local quietEnd = false
  for _, e in ipairs(ev) do if e.kind == "dynamaxEnd" and e.text == nil then quietEnd = true end end
  check(quietEnd, "a quiet return (the faint says it)")
end

-- Max Guard: the boss's move is stopped; One Blow strikes through; in a row it may fail
do
  local function guardTeam()
    return dmaxTeam(1, 100, 0, function() return { { name = "Growl", key = "GROWL", power = 0, status = true,
      priority = 0, pp = 40, maxPp = 40, accuracy = 100, type = 0, typeName = "NORMAL" } } end)
  end
  local m = guardTeam()
  local boss = battler("Boss", 100000, 200, { mv("Hit", { power = 30 }) }, true)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(4) }
  local c = all(1); c[1].dmax = true
  local ev = s:turn(c)
  local blocked = false
  for _, e in ipairs(ev) do if e.kind == "guard" and e.blocked then blocked = true end end
  check(blocked and m[1].mon.hp == 150, "Max Guard first (+4) and the boss's hit stopped")
  local m2 = guardTeam()
  local pierce = { name = "G-Max One Blow", power = 30, status = false, priority = 0, spread = false, pp = 99, maxPp = 99,
    type = 17, accuracy = 0, pierce = true }
  local s2 = Sim.new{ boss = battler("Boss", 100000, 200, { pierce }, true), members = m2, adapter = adapter(), rng = rngOf(5) }
  local c2 = all(1); c2[1].dmax = true
  s2:turn(c2)
  check(m2[1].mon.hp == 120, "G-Max One Blow strikes through Max Guard")
  -- in a row: some fail
  local fails = 0
  for seed = 1, 60 do
    local m3 = guardTeam()
    local s3 = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), members = m3, adapter = adapter(), rng = rngOf(seed) }
    local c3 = all(1); c3[1].dmax = true
    s3:turn(c3)
    for _, e in ipairs(s3:turn(all(1))) do if e.kind == "fail" then fails = fails + 1 end end
  end
  check(fails > 20 and fails < 60, "Max Guard twice in a row: about 2 in 3 fail (" .. fails .. " / 60)")
end

-- the team's Max Moves: Max Airstream raises the whole team's Speed, Max Strike drops the boss's
do
  local function airMoves() return { { name = "Air Slash", key = "AIR_SLASH", power = 75, type = 2, typeName = "FLYING",
    status = false, priority = 0, pp = 15, maxPp = 15, accuracy = 95 } } end
  local m = dmaxTeam(4, 100, 0, airMoves)
  local s = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), members = m, adapter = adapter(), rng = rngOf(6) }
  local c = all(4); c[1].dmax = true
  s:turn(c)
  check(m[1].stages.speed == 1 and m[3].stages.speed == 1, "Max Airstream: the team's Speed +1")
  local m2 = dmaxTeam(1, 100, 0, tackle)
  local boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  local s2 = Sim.new{ boss = boss, members = m2, adapter = adapter(), rng = rngOf(6) }
  local c2 = all(1); c2[1].dmax = true
  s2:turn(c2)
  check(boss.stages.speed == -1, "Max Strike: the boss's Speed -1")
end

-- the team's G-Max Moves on the boss: Wildfire's flames round it, Finale heals the team, Gold Rush's coins
do
  local function fireMoves() return { { name = "Flamethrower", key = "FLAMETHROWER", power = 90, type = 10, typeName = "FIRE",
    status = false, priority = 0, pp = 15, maxPp = 15, accuracy = 100 } } end
  local m = dmaxTeam(1, 100, 0, fireMoves, "WILDFIRE")
  local boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(7) }
  local c = all(1); c[1].dmax = true
  local ev = s:turn(c)
  local burned = false
  for _, e in ipairs(ev) do if e.kind == "residual" and e.who == boss then burned = true end end
  check(s.bossField and burned, "G-Max Wildfire: the boss burns at the turn's end")
  local function normalMoves() return { { name = "Pay Day", key = "PAY_DAY", power = 40, type = 0, typeName = "NORMAL",
    status = false, priority = 0, pp = 20, maxPp = 20, accuracy = 100 } } end
  local m2 = dmaxTeam(1, 100, 0, normalMoves, "GOLD_RUSH")
  m2[1].mon.level = 30
  local s2 = Sim.new{ boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), members = m2, adapter = adapter(), rng = rngOf(8) }
  local c2 = all(1); c2[1].dmax = true
  s2:turn(c2); s2:turn(all(1)); s2:turn(all(1))
  check(s2.money == 3000 + 6000 + 9000, "Gold Rush: level x 100, x2, x3 (" .. s2.money .. ")")
end

-- against a Dynamaxed target: weight moves and Roar fail, Behemoth Blade doubles
do
  local function oneMove(key, power, status)
    return function() return { { name = key, key = key, power = power, type = 0, typeName = "NORMAL", status = status or false,
      priority = 0, pp = 10, maxPp = 10, accuracy = 100 } } end
  end
  local m = dmaxTeam(1, 100, 0, oneMove("LOW_KICK", 60))
  local boss = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  local s = Sim.new{ boss = boss, members = m, adapter = adapter(), rng = rngOf(9) }
  s:turn(all(1))
  check(boss.mon.hp == 100000, "Low Kick on the Dynamaxed boss fails")
  local m2 = dmaxTeam(1, 100, 0, oneMove("BEHEMOTH_BLADE", 100))
  local boss2 = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  Sim.new{ boss = boss2, members = m2, adapter = adapter(), rng = rngOf(9) }:turn(all(1))
  check(boss2.mon.hp == 100000 - 200, "Behemoth Blade: double on a Dynamax Pokemon")
  local m3 = dmaxTeam(1, 100, 0, oneMove("ROAR", 0, true))
  local boss3 = battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true)
  local ev3 = Sim.new{ boss = boss3, members = m3, adapter = adapter(), rng = rngOf(9) }:turn(all(1))
  local failed3 = false
  for _, e in ipairs(ev3) do if e.kind == "fail" then failed3 = true end end
  check(failed3, "Roar fails on a Dynamax Pokemon")
  -- the boss's Heavy Slam on a Dynamaxed member fails too
  local m4 = dmaxTeam(1, 100, 0, tackle)
  local slam = mv("Heavy Slam", { power = 80 }); slam.key = "HEAVY_SLAM"
  local s4 = Sim.new{ boss = battler("Boss", 100000, 1, { slam }, true), members = m4, adapter = adapter(), rng = rngOf(10) }
  local c4 = all(1); c4[1].dmax = true
  s4:turn(c4)
  check(m4[1].mon.hp == 150, "the boss's Heavy Slam fails on a Dynamaxed member")
end

-- ------- team moves (data/raid_team_moves.lua)
local TM = assert(loadstring(read("data/raid_team_moves.lua"), "@data/raid_team_moves.lua"))()
-- a team move as Bt.move makes it: its row on `team`, its priority
local TM_PRI = { protect = 4, detect = 4, spikyshield = 4, kingsshield = 4, endure = 4, helpinghand = 5,
  wideguard = 3, quickguard = 3, craftyshield = 3, followme = 2, ragepowder = 2 }
local function tm(key, o)
  o = o or {}
  local k = key:lower():gsub("[^%w]", "")
  return { name = key, key = key, team = TM.MOVES[k], power = o.power or 0, status = (o.power or 0) == 0,
    priority = TM_PRI[k] or 0, spread = false, pp = 10, maxPp = 10, type = o.type or 0, accuracy = 0 }
end
-- the screen-aware fake: a move's `physical` side cut by reflect, the other by light screen (2732 /
-- 4096 doubled, else half); Helping Hand x1.5
local function screenAdapter()
  local A = adapter()
  A.damage = function(att, def, m, spread, o)
    o = o or {}
    local d = m.power
    if o.helped then d = math.floor(d * 1.5) end
    if (m.physical and o.reflect) or (not m.physical and o.lightScreen) then
      d = o.doubleScreens and math.floor(d * 2732 / 4096) or math.floor(d / 2)
    end
    return d, { effectiveness = 1 }
  end
  A.abilityName = function(b) return b.ability end
  return A
end
local function newSim(boss, m, seed) return Sim.new{ boss = boss, members = m, adapter = screenAdapter(), rng = rngOf(seed),
  teamWords = TM, rules = { TURNS = 20, FAINTS = 4 } } end
local function has(ev, pred) for _, e in ipairs(ev) do if pred(e) then return e end end return nil end
local function pick(slot, target) return { move = slot, target = target } end

-- the rows: every kind known, the SwSh list
do
  local known = { screen = 1, side = 1, guard = 1, protect = 1, endure = 1, redirect = 1, help = 1, heal = 1, cure = 1,
    wish = 1, sacrifice = 1, boost = 1, none = 1 }
  local n = 0
  for k, row in pairs(TM.MOVES) do
    n = n + 1
    check(known[row.kind] ~= nil, "team move " .. k .. ": a known kind")
  end
  check(n >= 35, "the team moves: " .. n)
  check(math.abs(TM.SCREEN_K - 0.667) < 0.001, "a screen in a multi battle: 2732 / 4096")
end

-- screens: Light Screen cuts the boss's special hit to 2732 / 4096 for five turns; Reflect leaves it
do
  local m = team(2, 1000, { 50, 50 })
  m[1].moves = { tm("LIGHT_SCREEN") }
  local boss = battler("Boss", 100000, 1, { mv("Beam", { power = 90, spread = true }) }, true)
  local s = newSim(boss, m, 30)
  local ev = s:turn({ pick(1), { move = 1 } })
  check(has(ev, function(e) return e.kind == "side" and e.what == "light" and e.up end) ~= nil, "Light Screen goes up")
  check(m[2].mon.hp == 1000 - 45, "Light Screen: 90 -> 60 on the team, x3/4 spread -> 45 (" .. m[2].mon.hp .. ")")
  for _ = 1, 3 do s:turn({ { move = 1 }, { move = 1 } }) end
  check(s.sides.team.light == 1, "Light Screen: one turn left after four")
  local ev5 = s:turn({ { move = 1 }, { move = 1 } })
  check(s.sides.team.light == 0 and has(ev5, function(e) return e.kind == "side" and e.what == "light" and not e.up end) ~= nil,
    "Light Screen wears off after five turns")
  local m2 = team(1, 1000)
  m2[1].moves = { tm("REFLECT") }
  local s2 = newSim(battler("Boss", 100000, 1, { mv("Beam", { power = 90 }) }, true), m2, 31)
  s2:turn({ pick(1) })
  check(m2[1].mon.hp == 910, "Reflect does nothing for a special hit")
  local m3 = team(1, 1000)
  m3[1].moves = { tm("AURORA_VEIL") }
  local ev3 = newSim(battler("Boss", 100000, 1, { mv("Beam", { power = 90 }) }, true), m3, 32):turn({ pick(1) })
  check(has(ev3, function(e) return e.kind == "fail" end) ~= nil, "Aurora Veil fails without hail")
  -- a second Light Screen while one is up fails
  local m4 = team(1, 1000)
  m4[1].moves = { tm("LIGHT_SCREEN") }
  local s4 = newSim(battler("Boss", 100000, 1, { mv("Beam", { power = 1 }) }, true), m4, 33)
  s4:turn({ pick(1) })
  check(has(s4:turn({ pick(1) }), function(e) return e.kind == "fail" end) ~= nil, "Light Screen twice: fails")
  -- the boss's own Light Screen: half (it stands alone)
  local m5 = team(1, 1000, { 1 })
  m5[1].moves = { mv("Beam", { power = 100 }) }
  local boss5 = battler("Boss", 100000, 50, { tm("LIGHT_SCREEN") }, true)
  newSim(boss5, m5, 34):turn({ pick(1) })
  check(boss5.mon.hp == 100000 - 50, "the boss's Light Screen: half (" .. (100000 - boss5.mon.hp) .. ")")
  -- G-Max Wind Rage blows the team's screens away
  local m6 = team(1, 1000)
  m6[1].moves = { tm("REFLECT") }
  local rage = { name = "G-Max Wind Rage", power = 10, spread = true, isGmax = true, status = false, priority = 0, type = 2,
    accuracy = 0, pp = 99, maxPp = 99, gmaxEffect = { kind = "defog" } }
  local s6 = newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 1 }) }, true), m6, 35)
  s6:turn({ pick(1) })
  s6.boss.moves = { rage }
  s6:turn({ pick(1) })
  check(s6.sides.team.reflect == 0, "G-Max Wind Rage: the team's Reflect blown away")
end

-- Safeguard stops the boss's status; Mist its stat drops; Tailwind doubles the team's Speed
do
  local m = team(2, 1000)
  m[1].moves = { tm("SAFEGUARD") }
  local toxic = mv("Toxic", { status = true, power = 0 }); toxic.side = { status = "TOX" }
  local s = newSim(battler("Boss", 100000, 1, { toxic }, true), m, 40)
  s:turn({ pick(1), { move = 1 } }); s:turn({ { move = 1 }, { move = 1 } })
  check(not m[1].status and not m[2].status, "Safeguard: no Toxic on the team")
  local m2 = team(2, 1000)
  m2[1].moves = { tm("MIST") }
  local growl = mv("Growl", { status = true, power = 0, spread = true }); growl.side = { stages = { attack = -1 } }
  newSim(battler("Boss", 100000, 1, { growl }, true), m2, 41):turn({ pick(1), { move = 1 } })
  check(m2[2].stages.attack == 0, "Mist: Growl does nothing")
  local m3 = team(2, 1000, { 10, 10 })
  m3[1].moves = { tm("TAILWIND") }
  local s3 = newSim(battler("Boss", 100000, 15, { mv("Hit", { power = 1 }) }, true), m3, 42)
  s3:turn({ pick(1), { move = 1 } })
  local ev = s3:turn({ pick(1), { move = 1 } })
  local firstUse = has(ev, function(e) return e.kind == "use" end)
  check(firstUse and firstUse.who ~= s3.boss, "Tailwind: the team (10 x 2) moves before the boss (15)")
end

-- guards: Wide Guard stops a spread move, a G-Max move strikes through for a quarter; Quick Guard a
-- priority move; Crafty Shield a status move; Mat Block only on the first turn out
do
  local m = team(2, 1000)
  m[1].moves = { tm("WIDE_GUARD") }
  local s = newSim(battler("Boss", 100000, 1, { mv("Surf", { power = 80, spread = true }) }, true), m, 50)
  s:turn({ pick(1), { move = 1 } })
  check(m[1].mon.hp == 1000 and m[2].mon.hp == 1000, "Wide Guard: the spread move stopped")
  -- (a G-Max move has one target: Wide Guard, for spread moves, does not stand against it)
  local gmax = { name = "G-Max Hydrosnipe", power = 80, spread = false, isGmax = true, status = false, priority = 0, type = 11,
    accuracy = 0, pp = 99, maxPp = 99 }
  local m2 = team(2, 1000)
  m2[1].moves = { tm("WIDE_GUARD") }
  m2[2].moves = { mv("Wait", { power = 0, status = true }) }
  newSim(battler("Boss", 100000, 1, { gmax }, true), m2, 51):turn({ pick(1), { move = 1 } })
  local lost = (1000 - m2[1].mon.hp) + (1000 - m2[2].mon.hp)
  check(lost == 80 and (m2[1].mon.hp == 1000 or m2[2].mon.hp == 1000), "a G-Max move: one target, past Wide Guard (" .. lost .. ")")
  local m3 = team(2, 1000)
  m3[1].moves = { tm("QUICK_GUARD") }
  local quick = mv("Quick Attack", { power = 40, priority = 1 })
  newSim(battler("Boss", 100000, 1, { quick }, true), m3, 52):turn({ pick(1), { move = 1 } })
  check(m3[1].mon.hp == 1000 and m3[2].mon.hp == 1000, "Quick Guard: the priority move stopped")
  local m4 = team(2, 1000)
  m4[1].moves = { tm("CRAFTY_SHIELD") }
  local toxic = mv("Toxic", { status = true, power = 0 }); toxic.side = { status = "TOX" }
  newSim(battler("Boss", 100000, 1, { toxic }, true), m4, 53):turn({ pick(1), { move = 1 } })
  check(not m4[1].status and not m4[2].status, "Crafty Shield: the status move stopped")
  local m5 = team(2, 1000)
  m5[1].moves = { tm("MAT_BLOCK") }
  local s5 = newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 30, spread = true }) }, true), m5, 54)
  s5:turn({ pick(1), { move = 1 } })
  check(m5[2].mon.hp == 1000, "Mat Block on the first turn: stopped")
  local ev5 = s5:turn({ pick(1), { move = 1 } })
  check(has(ev5, function(e) return e.kind == "fail" end) ~= nil and m5[2].mon.hp == 978, "Mat Block after the first turn: fails")
end

-- Protect: the user safe, a Max move through for a quarter, Spiky Shield hurting the boss's contact
-- move; Endure keeps 1 HP
do
  local m = team(1, 1000)
  m[1].moves = { tm("PROTECT") }
  newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 300 }) }, true), m, 60):turn({ pick(1) })
  check(m[1].mon.hp == 1000, "Protect: the hit stopped")
  local maxHit = { name = "Max Strike", power = 400, spread = false, isGmax = true, isMax = true, status = false, priority = 0,
    type = 0, accuracy = 0, pp = 99, maxPp = 99 }
  local m2 = team(1, 1000)
  m2[1].moves = { tm("PROTECT") }
  newSim(battler("Boss", 100000, 1, { maxHit }, true), m2, 61):turn({ pick(1) })
  check(m2[1].mon.hp == 900, "a Max move through Protect: a quarter")
  local m3 = team(1, 1000)
  m3[1].moves = { tm("SPIKY_SHIELD") }
  local bite = mv("Bite", { power = 60 }); bite.contact = true
  local boss3 = battler("Boss", 8000, 1, { bite }, true)
  newSim(boss3, m3, 62):turn({ pick(1) })
  check(m3[1].mon.hp == 1000 and boss3.mon.hp == 7000, "Spiky Shield: the biting boss loses 1/8")
  local m4 = team(1, 100)
  m4[1].moves = { tm("ENDURE") }
  local ev4 = newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 500 }) }, true), m4, 63):turn({ pick(1) })
  check(m4[1].mon.hp == 1 and has(ev4, function(e) return e.what == "endured" end) ~= nil, "Endure: 1 HP left")
end

-- Follow Me draws every single-target move; Helping Hand x1.5
do
  local hits = {}
  for seed = 1, 20 do
    local m = team(4, 1000, { 50, 50, 50, 50 })
    m[2].moves = { tm("FOLLOW_ME") }
    newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 10 }) }, true), m, seed):turn({ { move = 1 }, pick(1), { move = 1 }, { move = 1 } })
    for i = 1, 4 do if m[i].mon.hp < 1000 then hits[i] = (hits[i] or 0) + 1 end end
  end
  check((hits[2] or 0) == 20 and not hits[1] and not hits[3] and not hits[4], "Follow Me: every hit on its user")
  local m = team(2, 1000, { 60, 40 })
  m[1].moves = { tm("HELPING_HAND") }
  m[2].moves = { mv("Hit", { power = 100 }) }
  local boss = battler("Boss", 100000, 1, { mv("Tap", { power = 1 }) }, true)
  newSim(boss, m, 70):turn({ pick(1, 2), { move = 1 } })
  check(boss.mon.hp == 100000 - 150, "Helping Hand: the ally's hit x1.5 (" .. (100000 - boss.mon.hp) .. ")")
end

-- heals: Life Dew the team a quarter, Heal Pulse an ally half, Pollen Puff an ally or the boss, Heal
-- Bell the team's status, Wish the next turn, Healing Wish the user fainting
do
  local m = team(3, 1000)
  for _, x in ipairs(m) do x.mon.hp = 500 end
  m[1].moves = { tm("LIFE_DEW") }
  newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m, 80):turn({ pick(1), { move = 1 }, { move = 1 } })
  check(m[1].mon.hp == 750 and m[3].mon.hp == 750, "Life Dew: the team +1/4")
  local m2 = team(2, 1000)
  m2[2].mon.hp = 300
  m2[1].moves = { tm("HEAL_PULSE") }
  newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m2, 81):turn({ pick(1, 2), { move = 1 } })
  check(m2[2].mon.hp == 800, "Heal Pulse: the ally +1/2")
  local m3 = team(2, 1000)
  m3[2].mon.hp = 300
  m3[1].moves = { tm("POLLEN_PUFF", { power = 90 }) }
  m3[2].moves = { mv("Wait", { power = 0, status = true }) }
  local boss3 = battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true)
  local s3 = newSim(boss3, m3, 82)
  s3:turn({ pick(1, 2), { move = 1 } })
  check(m3[2].mon.hp == 800 and boss3.mon.hp == 100000, "Pollen Puff on an ally: heals it")
  s3:turn({ pick(1, "boss"), { move = 1 } })
  check(boss3.mon.hp == 100000 - 90, "Pollen Puff on the boss: an attack")
  local m4 = team(2, 1000)
  m4[1].status, m4[2].status = "PSN", "BRN"
  m4[1].moves = { tm("HEAL_BELL") }
  newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m4, 83):turn({ pick(1), { move = 1 } })
  check(not m4[1].status and not m4[2].status, "Heal Bell: the team's status cured")
  local m5 = team(1, 1000)
  m5[1].moves = { tm("WISH"), mv("Hit", { power = 1 }) }
  local s5 = newSim(battler("Boss", 100000, 1, { mv("Hit", { power = 600 }) }, true), m5, 84)
  s5:turn({ pick(1) })
  check(m5[1].mon.hp == 400, "Wish: nothing the turn it is made")
  s5.boss.moves = { mv("Tap", { power = 0, status = true }) }
  s5:turn({ pick(2) })
  check(m5[1].mon.hp == 900, "Wish: half its max HP at the next turn's end (" .. m5[1].mon.hp .. ")")
  local m6 = team(2, 1000)
  m6[1].moves = { tm("HEALING_WISH") }
  local s6 = newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m6, 85)
  s6:turn({ pick(1), { move = 1 } })
  check(m6[1].mon.hp == 0 and s6.faints == 1, "Healing Wish: the user faints (a faint counted)")
end

-- boosts: Howl the team, Coaching the allies, Decorate one ally, Gear Up those with Plus / Minus, Flower
-- Shield the Grass types
do
  local function one(key, target, setup)
    local m = team(3, 1000)
    m[1].moves = { tm(key) }
    if setup then setup(m) end
    newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m, 90):turn({ pick(1, target), { move = 1 }, { move = 1 } })
    return m
  end
  local h = one("HOWL")
  check(h[1].stages.attack == 1 and h[3].stages.attack == 1, "Howl: the user and allies +1 Attack")
  local c = one("COACHING")
  check(c[1].stages.attack == 0 and c[2].stages.attack == 1 and c[2].stages.defense == 1, "Coaching: the allies, not the user")
  local d = one("DECORATE", 3)
  check(d[3].stages.attack == 2 and d[3].stages.spAtk == 2 and d[2].stages.attack == 0, "Decorate: one ally +2 / +2")
  local g = one("GEAR_UP", nil, function(m) m[2].ability = "PLUS" end)
  check(g[2].stages.attack == 1 and g[1].stages.attack == 0, "Gear Up: only Plus / Minus")
  local f = one("FLOWER_SHIELD", nil, function(m) m[3].type1 = 12 end)
  check(f[3].stages.defense == 1 and f[1].stages.defense == 0, "Flower Shield: the Grass types")
end

-- friendly fire: a member's Surf hits the boss and its allies, never itself; Wide Guard and Protect
-- stand against an ally's too; Explosion faints its user, Mind Blown costs half its HP
do
  local surf = mv("Surf", { power = 90, spread = true }); surf.friendly = true
  local m = team(3, 1000, { 90, 10, 10 })
  m[1].moves = { surf }
  m[2].moves = { mv("Wait", { power = 0, status = true }) }
  m[3].moves = { mv("Wait", { power = 0, status = true }) }
  local boss = battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true)
  local s = newSim(boss, m, 100)
  s:turn({ pick(1), pick(1), pick(1) })
  check(boss.mon.hp == 100000 - 67 and m[2].mon.hp == 933 and m[3].mon.hp == 933 and m[1].mon.hp == 1000,
    "Surf: the boss and both allies (x3/4 each), not its user")
  local m2 = team(3, 1000, { 10, 90, 10 })
  local surf2 = mv("Surf", { power = 90, spread = true }); surf2.friendly = true
  m2[1].moves = { surf2 }
  m2[2].moves = { tm("WIDE_GUARD") }
  m2[3].moves = { mv("Wait", { power = 0, status = true }) }
  newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m2, 101):turn({ pick(1), pick(1), pick(1) })
  check(m2[2].mon.hp == 1000 and m2[3].mon.hp == 1000, "an ally's Wide Guard stops the Surf on the team")
  local m3 = team(2, 1000, { 90, 10 })
  local boom = mv("Explosion", { power = 250, spread = true }); boom.friendly = true; boom.key = "EXPLOSION"
  m3[1].moves = { boom }
  m3[2].moves = { tm("PROTECT") }
  local s3 = newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m3, 102)
  s3:turn({ pick(1), pick(1) })
  check(m3[1].mon.hp == 0 and s3.faints == 1 and m3[2].mon.hp == 1000, "Explosion: its user faints, Protect keeps the ally safe")
  local m4 = team(1, 1000)
  local blown = mv("Mind Blown", { power = 150, spread = true }); blown.friendly = true; blown.key = "MIND_BLOWN"
  m4[1].moves = { blown }
  newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m4, 103):turn({ pick(1) })
  check(m4[1].mon.hp == 500, "Mind Blown: half its max HP")
  -- Safeguard stands against an ally's Discharge paralysis too
  local m5 = team(2, 1000, { 90, 10 })
  local dis = mv("Discharge", { power = 80, spread = true }); dis.friendly = true; dis.side = { status = "PAR", statusChance = 100 }
  m5[1].moves = { tm("SAFEGUARD") }
  m5[2].moves = { dis }
  local s5 = newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), m5, 104)
  s5:turn({ pick(1), pick(1) })
  s5:turn({ pick(1), pick(1) })
  check(m5[1].status == nil, "Safeguard: no paralysis from an ally's Discharge")
end

-- a G-Max effect on the target alone (Snooze); Smite confuses every opponent; confusion strikes
-- itself now and then and wears off; Depletion takes the last move's PP; the boss's plain spread
-- move still hits all four, each for 3 / 4
do
  local snooze = mv("G-Max Snooze", { power = 1 }); snooze.isGmax = true
  snooze.gmaxEffect = { kind = "drowsy", chance = 100 }
  local m = team(4, 1000)
  local boss = battler("Boss", 100000, 1, { snooze }, true)
  newSim(boss, m, 120):turn(all(4))
  local asleep = 0
  for _, x in ipairs(m) do if x.status == "SLP" then asleep = asleep + 1 end end
  check(asleep == 1, "G-Max Snooze: only the one struck grows drowsy (" .. asleep .. ")")
  local smite = mv("G-Max Smite", { power = 1 }); smite.isGmax = true
  smite.gmaxEffect = { kind = "none", confuse = true }
  local m2 = team(4, 1000)
  newSim(battler("Boss", 100000, 1, { smite }, true), m2, 121):turn(all(4))
  local conf = 0
  for _, x in ipairs(m2) do if x.confused then conf = conf + 1 end end
  check(conf == 4, "G-Max Smite: every opponent confused (" .. conf .. ")")
  -- confusion: over 40 seeded turns some self-hits, and it wears off within five
  local selfHits, cleared = 0, 0
  for seed = 1, 40 do
    local c = team(1, 1000)
    local sc = newSim(battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true), c, seed)
    c[1].confused = 3
    for _ = 1, 3 do
      for _, e in ipairs(sc:turn(all(1))) do
        if e.kind == "residual" and e.who == c[1] then selfHits = selfHits + 1 end
      end
    end
    if not c[1].confused then cleared = cleared + 1 end
  end
  check(selfHits > 5 and selfHits < 40 and cleared == 40, ("confusion: self-hits %d, cleared %d / 40"):format(selfHits, cleared))
  local depl = mv("G-Max Depletion", { power = 1 }); depl.isGmax = true
  depl.gmaxEffect = { kind = "pp", n = 2 }
  local m3 = team(1, 1000, { 50 })
  m3[1].moves = { mv("Tackle", { power = 10 }), mv("Ember", { power = 10 }) }
  local s3 = newSim(battler("Boss", 100000, 1, { depl }, true), m3, 122)
  s3:turn({ pick(2) })
  check(m3[1].moves[2].pp == 7 and m3[1].moves[1].pp == 10, "G-Max Depletion: the last move used loses 2 PP")
  local m4 = team(4, 1000)
  local quake = mv("Earthquake", { power = 100, spread = true })
  local ev4 = newSim(battler("Boss", 100000, 1, { quake }, true), m4, 123):turn(all(4))
  local hits4 = 0
  for _, e in ipairs(ev4) do if e.kind == "damage" and e.target and not e.target.boss and e.amount == 75 then hits4 = hits4 + 1 end end
  check(hits4 == 4, "the boss's Earthquake: all four, 75 each (" .. hits4 .. ")")
end

-- G-Max Cuddle: every opponent of the other gender falls in love (not the genderless, not one of
-- the same gender, not Oblivious); in love, half its turns lost; it ends when the one it loves leaves
do
  local cuddle = mv("G-Max Cuddle", { power = 1 }); cuddle.isGmax = true
  cuddle.gmaxEffect = { kind = "none", attract = true }
  local m = team(4, 1000)
  m[1].gender, m[2].gender, m[3].gender, m[4].gender = "M", "F", "U", "M"
  m[4].ability = "OBLIVIOUS"
  local boss = battler("Boss", 100000, 1, { cuddle }, true)
  boss.gender = "F"
  newSim(boss, m, 130):turn(all(4))
  check(m[1].attract == boss and not m[2].attract and not m[3].attract and not m[4].attract,
    "G-Max Cuddle: the male falls in love; the female, the genderless and the Oblivious one do not")
  local lost = 0
  for seed = 1, 40 do
    local c = team(1, 1000)
    local b2 = battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true)
    local sc = newSim(b2, c, seed)
    c[1].attract = b2
    for _, e in ipairs(sc:turn(all(1))) do if e.kind == "cant" and e.text and e.text:find("immobilized") then lost = lost + 1 end end
  end
  check(lost > 8 and lost < 32, "in love: about half its turns lost (" .. lost .. " / 40)")
  -- a member's Cuddle on the boss: over when that member faints
  local m2 = team(2, 1000, { 90, 10 })
  m2[1].gender = "M"
  local cud2 = mv("G-Max Cuddle", { power = 1 }); cud2.isGmax = true; cud2.gmaxEffect = { kind = "none", attract = true }
  m2[1].moves = { cud2 }
  local boss2 = battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true)
  boss2.gender = "F"
  local s2 = newSim(boss2, m2, 131)
  s2:turn({ pick(1), pick(1) })
  check(boss2.attract == m2[1], "a member's Cuddle: the boss in love with it")
  m2[1].mon.hp = 0
  s2:fainted({}, m2[1])
  check(boss2.attract == nil, "... until that member leaves the field")
end

-- G-Max Meltdown: every opponent tormented (not the same move twice in a row; a Dynamax Pokemon -
-- the boss - immune); G-Max Gravitas: Gravity five turns (accuracy x5/3 asked of the adapter, the
-- airborne moves failing, the ground reaching Flying types through the adapter's `gravity`)
do
  local melt = mv("G-Max Meltdown", { power = 1 }); melt.isGmax = true
  melt.gmaxEffect = { kind = "none", torment = true }
  local m = team(2, 1000, { 90, 90 })
  local a1, a2 = mv("Tackle", { power = 10 }), mv("Ember", { power = 10 })
  m[1].moves = { a1, a2 }
  local boss = battler("Boss", 100000, 1, { melt }, true)
  local s = newSim(boss, m, 140)
  s:turn({ pick(1), pick(1) })
  check(m[1].torment and m[2].torment, "G-Max Meltdown: both tormented")
  check(s:tormented(m[1], a1) and not s:tormented(m[1], a2), "tormented: Tackle again barred, Ember free")
  local ev = s:turn({ pick(1), pick(1) })
  check(has(ev, function(e) return e.kind == "cant" and e.torment and e.who == m[1] end) ~= nil,
    "Tackle twice in a row: it cannot")
  check(not s:tormented(m[2], m[2].moves[1]), "one with no other move: not barred (Struggle in the games)")
  local m2 = team(1, 1000)
  local melt2 = mv("G-Max Meltdown", { power = 1 }); melt2.isGmax = true; melt2.gmaxEffect = { kind = "none", torment = true }
  m2[1].moves = { melt2 }
  local boss2 = battler("Boss", 100000, 1, { mv("Tap", { power = 0, status = true }) }, true)
  newSim(boss2, m2, 141):turn({ pick(1) })
  check(not boss2.torment, "the boss (Dynamaxed) is not tormented")
  -- Gravity
  local grav = mv("G-Max Gravitas", { power = 1 }); grav.isGmax = true
  grav.gmaxEffect = { kind = "gravity", turns = 5 }
  local m3 = team(1, 1000, { 90 })
  local fly = mv("Fly", { power = 90 }); fly.key = "FLY"
  local quake = mv("Earthquake", { power = 100 }); quake.key = "EARTHQUAKE"
  m3[1].moves = { fly, quake }
  local seen = {}
  local A = screenAdapter()
  local baseHits, baseDmg = A.hits, A.damage
  A.hits = function(att, def, mv2, g) seen.hitsGravity = seen.hitsGravity or g; return baseHits(att, def, mv2) end
  A.damage = function(att, def, mv2, spread, o) if o and o.gravity then seen.dmgGravity = true end return baseDmg(att, def, mv2, spread, o) end
  local boss3 = battler("Boss", 100000, 1, { grav }, true)
  local s3 = Sim.new{ boss = boss3, members = m3, adapter = A, rng = rngOf(142), teamWords = TM, rules = { TURNS = 20, FAINTS = 4 } }
  s3:turn({ pick(2) })
  check(s3.gravity == 4, "G-Max Gravitas: Gravity, four turns left after its first (" .. tostring(s3.gravity) .. ")")
  s3.boss.moves = { mv("Hit", { power = 1, accuracy = 100 }) }
  local ev3 = s3:turn({ pick(1) })
  check(has(ev3, function(e) return e.kind == "fail" and e.text and e.text:find("gravity") end) ~= nil, "Fly fails under Gravity")
  s3:turn({ pick(2) })
  check(seen.hitsGravity and seen.dmgGravity, "accuracy and the Ground move's reach told to the adapter")
  for _ = 1, 3 do s3:turn({ pick(2) }) end
  check((s3.gravity or 0) == 0, "Gravity wears off after five turns")
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
