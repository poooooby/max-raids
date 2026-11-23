-- Dynamax in the game's own battles, the parts with no engine (src/dmax_rules.lua): which battles
-- allow it under each option, the moves registered, which Max Move a move becomes and its power,
-- and the HP sums.
--   luajit tests/dmax_test.lua   (from the repo root)

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function loadFile(path) return assert(loadstring(read(path), "@" .. path))() end

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

local D = loadFile("data/dmax_battle.lua")
local Gmax = loadFile("data/raid_gmax.lua")
local MaxPower = loadFile("data/raid_maxpower.lua")
local R = loadFile("src/dmax_rules.lua")({ data = D })
R.setGmaxTypes(Gmax.MOVES)
local mod = { log = { warn = function() end, info = function() end } }
local Bt = loadstring(read("src/battle.lua"), "@src/battle.lua")()(mod, { N = {}, Bosses = {}, Sprites = {}, Gmax = Gmax,
  MaxPower = MaxPower })

-- ------- the moves registered
local rows, byKey = R.rows()
check(#rows == 18 + 1 + 33 + 2, "18 Max Moves, Max Guard, 33 G-Max Moves, the Dynamax and its end: " .. #rows)
local seen, idx = {}, {}
for _, r in ipairs(rows) do
  check(not seen[r.id], "one row a move: " .. r.id)
  seen[r.id] = true
  idx[r.index] = (idx[r.index] or 0) + 1
  check(r.index >= 900 and r.index < 1024, r.id .. ": a number past the National Dex's, under 1024")
  check(#r.label <= 12, r.id .. ": its menu name fits a cell (" .. r.label .. ")")
  check(type(r.type) == "string" and r.type ~= "", r.id .. ": a type")
end
for n, c in pairs(idx) do check(c == 1, "one move a number: " .. n) end
check(byKey.MAX_FIRE.effect == 17 and byKey.MAX_FIRE.flags == 0, "a Max Move never misses, and Protect does not stop it")
check(byKey.MAX_GUARD.effect == 111 and byKey.MAX_GUARD.priority == 4, "Max Guard is Protect's effect at +4")
check(byKey.WILDFIRE.type == "FIRE" and byKey.STEELSURGE.type == "STEEL", "the G-Max Moves take their types")
for _, id in ipairs(D.GMAX_ORDER) do check(Gmax.MOVES[id] ~= nil, id .. " is one of data/raid_gmax.lua's") end

-- ------- which battles
local function facts(t)
  return { wild = t.wild, classes = t.classes or {}, flags = t.flags or {}, kinds = t.kinds or {} }
end
local leader = facts({ classes = { "LEADER" } })
local hiker = facts({ classes = { "HIKER" } })
local wild = facts({ wild = true })
check(R.battleAllows("league", leader), "GYMS & LEAGUE: a Gym Leader")
for _, c in ipairs({ "ELITE_FOUR", "CHAMPION", "RIVAL", "RIVAL_EARLY", "RIVAL_LATE", "POKEMON_TRAINER_3",
    "RS_LEADER" }) do
  check(R.battleAllows("league", facts({ classes = { c } })), "GYMS & LEAGUE: " .. c)
end
check(not R.battleAllows("league", hiker), "GYMS & LEAGUE: not a Hiker")
check(R.battleAllows("league", facts({ classes = { "HIKER", "LEADER" } })), "GYMS & LEAGUE: a Leader as the second trainer")
check(not R.battleAllows("league", wild), "GYMS & LEAGUE: not a wild battle")
check(R.battleAllows("trainers", hiker) and not R.battleAllows("trainers", wild), "ALL TRAINERS: a Hiker, no wild")
check(R.battleAllows("all", wild) and R.battleAllows("all", hiker), "ALL BATTLES: wild too")
check(not R.battleAllows("off", leader) and not R.battleAllows(nil, leader), "OFF: never")
for _, f in ipairs({ "link", "safari", "oldManTutorial", "pokedude", "battleTower", "facility", "multi" }) do
  check(not R.battleAllows("all", facts({ classes = { "LEADER" }, flags = { [f] = true } })), "never in a " .. f .. " battle")
end
check(not R.battleAllows("all", facts({ wild = true, kinds = { firstBattle = true } })), "never in the first battle")

-- ------- Power Spots: the League's battles anywhere, any battle on a route with an active den
local function spot(t) local f = facts(t) f.spot = true return f end
check(R.battleAllows("spots", leader), "POWER SPOTS: a Gym Leader")
check(not R.battleAllows("spots", hiker), "POWER SPOTS: not a Hiker away from a den")
check(not R.battleAllows("spots", wild), "POWER SPOTS: not a wild battle away from a den")
check(R.battleAllows("spots", spot({ classes = { "HIKER" } })), "POWER SPOTS: a Hiker on a den's route")
check(R.battleAllows("spots", spot({ wild = true })), "POWER SPOTS: a wild battle on a den's route")
check(not R.battleAllows("spots", spot({ wild = true, flags = { safari = true } })), "POWER SPOTS: never in the Safari Zone")
check(not R.battleAllows("league", spot({ classes = { "HIKER" } })), "GYMS & LEAGUE: a den's route changes nothing")

-- ------- the foe's ace: a League trainer's, where the option allows
check(R.foeAllows("league", leader), "the foe: a Gym Leader's ace")
check(R.foeAllows("league", facts({ classes = { "ELITE_FOUR" } })) and R.foeAllows("league", facts({ classes = { "RIVAL_LATE" } })),
  "the foe: the Elite Four's, a rival's")
check(not R.foeAllows("trainers", hiker) and not R.foeAllows("all", hiker), "the foe: never a Hiker's, whatever the option")
check(not R.foeAllows("all", wild), "the foe: never a wild one")
check(not R.foeAllows("off", leader), "the foe: not with the option OFF")
check(R.foeAllows("spots", leader) and R.foeAllows("trainers", leader), "the foe: a Leader's under POWER SPOTS and ALL TRAINERS")
check(not R.foeAllows("league", facts({ classes = { "LEADER" }, flags = { link = true } })), "the foe: never in a link battle")
check(R.aceIndex({ { species = 74 }, { species = 299 } }) == 2, "the ace: the last Pokemon")
check(R.aceIndex({ { species = 74 }, { species = 299 }, { species = 0 } }) == 2, "the ace: an empty slot after it left out")
check(R.aceIndex({ { species = 74 }, { species = 1, isEgg = true } }) == 1, "the ace: never an egg")
check(R.aceIndex({}) == nil and R.aceIndex(nil) == nil, "the ace: none in no party")

-- ------- which Max Move
local function mv(t)
  return { status = (t.power or 0) == 0, power = t.power or 0, typeName = t.typeName, type = t.type or 0, key = t.key,
    pp = 10, maxPp = 10 }
end
local key, power = R.maxKey(mv({ power = 90, typeName = "FIRE", key = "FLAMETHROWER" }), nil, Bt)
check(key == "MAX_FIRE" and power == 130, "Flamethrower -> Max Flare 130: " .. tostring(key) .. " " .. tostring(power))
key, power = R.maxKey(mv({ power = 90, typeName = "FIRE", key = "FLAMETHROWER" }), "WILDFIRE", Bt)
check(key == "WILDFIRE" and power == 130, "with the factor -> G-Max Wildfire (Flamethrower's power)")
key = R.maxKey(mv({ power = 90, typeName = "WATER", key = "SURF" }), "WILDFIRE", Bt)
check(key == "MAX_WATER", "a move of another type stays its Max Move")
key, power = R.maxKey(mv({ power = 0, typeName = "NORMAL", key = "GROWL" }), "WILDFIRE", Bt)
check(key == "MAX_GUARD", "a status move -> Max Guard")
key, power = R.maxKey(mv({ power = 80, typeName = "GRASS", key = "RAZOR_LEAF" }), "DRUM_SOLO", Bt)
check(key == "DRUM_SOLO" and power == 160, "G-Max Drum Solo is 160 whatever the move")
key, power = R.maxKey(mv({ power = 60, typeName = "FIGHTING", key = "BRICK_BREAK" }), nil, Bt)
check(key == "MAX_FIGHTING" and power == 80, "Fighting takes the lower column (60 -> 80)")
key, power = R.maxKey(mv({ power = 25, typeName = "GRASS", key = "BULLET_SEED" }), nil, Bt)
check(power == 130, "Bullet Seed's own Max power (130)")

-- ------- HP
local hp, mx = R.up(100, 120, 1.5)
check(hp == 150 and mx == 180, "x1.5: 100 / 120 -> 150 / 180")
hp, mx = R.up(100, 120, 2.0)
check(hp == 200 and mx == 240, "x2 at Dynamax Level 10")
check(R.down(150, 180, 120) == 100, "back: the same share")
check(R.down(1, 180, 120) == 1, "back: still standing at 1")
check(R.down(0, 180, 120) == 0, "back: fainted stays fainted")
check(R.down(180, 180, 120) == 120, "back: full stays full")
hp, mx = R.up(0, 120, 1.5)
check(hp == 0 and mx == 180, "a fainted one's max only")
hp = R.up(1, 120, 1.5)
check(hp == 1, "1 HP stays standing")

print(("dmax_test: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
