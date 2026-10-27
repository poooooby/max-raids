-- Dynamax dens over a stand-in engine: the route's Pokemon (the engine's tables; Modern Spawns'
-- tables and COMPLETE pools when it is on), how far along its line the stars take it, the boss
-- records under DYNA keys, and the plain Max Move built from a boss's moves.
--   luajit tests/dyna_test.lua   (from the repo root)

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

-- species (slot = national here): Poochyena 261 -> Mightyena 262; Zigzagoon 263 -> Linoone 264;
-- Wurmple 265 -> Silcoon 266 -> Beautifly 267 / Cascoon 268 -> Dustox 269; Magikarp 129 -> Gyarados
-- 130; Geodude 74 -> Graveler 75 -> Golem 76; Sprigatito 906 (Modern Spawns' pool only)
local EVOS = {
  [261] = { { method = 4, param = 18, target = 262 } }, [263] = { { method = 4, param = 20, target = 264 } },
  [265] = { { method = 4, param = 7, target = 266 }, { method = 4, param = 7, target = 268 } },
  [266] = { { method = 4, param = 10, target = 267 } }, [268] = { { method = 4, param = 10, target = 269 } },
  [129] = { { method = 4, param = 20, target = 130 } }, [74] = { { method = 4, param = 25, target = 75 } },
  [75] = { { method = 5, param = 0, target = 76 } },
}
local NAMES = { [261] = "POOCHYENA", [262] = "MIGHTYENA", [263] = "ZIGZAGOON", [264] = "LINOONE", [906] = "SPRIGATITO" }
local Pokemon = {
  national = function(s) return tonumber(s) end,
  speciesFromNational = function(n) return tonumber(n) end,
  evolutions = function(s) return EVOS[s] or {} end,
  name = function(s) return NAMES[s] or ("MON" .. s) end,
  types = function(s) return s == 261 and { 17, 17 } or { 0, 0 } end,
  stats = function() return { hp = 35, atk = 55, def = 35, spe = 35, spa = 30, spd = 30 } end,
  dexEntry = function() return { heightM = 0.5 } end,
  speciesFromName = function(id)
    for k, v in pairs(NAMES) do if v == id then return k end end
    return tonumber(tostring(id):match("^MON(%d+)$"))
  end,
  keyName = function(s) return NAMES[s] or ("MON" .. s) end,
}
local function fakeTables()
  return {
    EM_ROUTE101 = {
      land = { slots = { { species = 261 }, { species = 263 }, { species = 265 }, { species = 263 } } },
      water = { slots = { { species = 129 } } },
      rocks = { slots = { { species = 74 } } },
      fishing = { slots = { { species = 129 }, { species = 129 }, { species = 118 } } },
    },
  }
end
package.loaded["src.core.game3.pokemon"] = Pokemon
package.loaded["src.core.game3.encounters"] = { _tables = fakeTables() }

local spawns = nil   -- a stand-in Modern Spawns, when set
local mod = {
  content = { pokemon = { get = function(_, id) local s = Pokemon.speciesFromName(id); return s and { index = s } or nil end } },
  find = function(_, id) if id == "modern_spawns" and spawns then return { exports = spawns } end end,
  log = { warn = function() end },
}
local N = loadFile("data/raid_rules.lua")
local Bosses, Sprites = { ORDER = {} }, {}
local TN = { [0] = "NORMAL", [17] = "DARK" }
local Dy = loadstring(read("src/dyna.lua"), "@src/dyna.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites,
  typeName = function(n) return TN[n] or "NORMAL" end })
Dy.install()

local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end
local function rngOf(seed)
  local s = seed
  return function(lo, hi)
    s = (1103515245 * s + 12345) % 2147483648
    if not lo then return s / 2147483648 end
    return lo + s % (hi - lo + 1)
  end
end

-- the engine's tables: grass, water, Rock Smash, the rods, each species once
local list = Dy.routeSpecies("EM_ROUTE101")
check(#list == 6, "every species on the route once (" .. #list .. ")")
for _, s in ipairs({ 261, 263, 265, 129, 74, 118 }) do check(has(list, s), "the route has " .. s) end
check(#Dy.routeSpecies("ROUTE101") == 6, "found by the map's bare name too")
check(#Dy.routeSpecies("EM_ROUTE999") == 0, "no table: nothing")

-- stages by stars
local r = rngOf(7)
check(Dy.stageFor(261, 1, r) == 261 and Dy.stageFor(261, 2, r) == 261, "1-2 stars: as found")
check(Dy.stageFor(261, 3, r) == 262, "3 stars: one on")
check(Dy.stageFor(74, 3, r) == 75 and Dy.stageFor(74, 5, r) == 76, "4-5 stars: the last of the line")
check(Dy.stageFor(118, 5, r) == 118, "no evolution: itself")
local branch = {}
for i = 1, 60 do branch[Dy.stageFor(265, 5, rngOf(i))] = true end
check(branch[267] and branch[269] and not branch[265], "a branching line takes either branch to its end")

-- picks and records
local seen = {}
for i = 1, 200 do
  local key = Dy.pick("EM_ROUTE101", 1, rngOf(i))
  local id, stars = Dy.parse(key)
  local slot = Dy.slotOfId(id)
  check(stars == 1 and has(list, slot), "a 1-star pick is a route species as found")
  seen[slot] = true
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
check(n == #list, "every route species can be picked (" .. n .. ")")
check(Dy.pick("EM_ROUTE999", 3, rngOf(1)) == nil, "a route with no wild Pokemon: no pick")
local b = Bosses["DYNA:POOCHYENA:4"]
check(b and b.name == "Poochyena" and b.stars == 4 and b.types[1] == "DARK" and #b.types == 1 and b.dyna
  and b.slot == 261 and b.national == 261, "Bosses[DYNA key]: name, stars, types, species")
check(Sprites["DYNA:POOCHYENA:4"] and Sprites["DYNA:POOCHYENA:4"].base.atk == 55, "Sprites[DYNA key]: base stats")
-- a form (the National Dex's: a species of its own, its base's number) keeps its form
local formMod = mod.find
mod.find = function(self, id)
  if id == "national_dex_gen3" then
    return { exports = {
      idOfSlot = function(s) return s == 1100 and "RATICATE_ALOLA" or nil end,
      slotOf = function(x) return x == "RATICATE_ALOLA" and 1100 or nil end } }
  end
  return formMod(self, id)
end
local realNat = Pokemon.national
Pokemon.national = function(s) return s == 1100 and 20 or realNat(s) end
check(Dy.idOf(1100) == "RATICATE_ALOLA", "a form's id")
local fb = Bosses["DYNA:RATICATE_ALOLA:3"]
check(fb and fb.slot == 1100 and fb.national == 20, "a form's record: its own species, its base's number")
mod.find, Pokemon.national = formMod, realNat
check(Bosses.ORDER and #Bosses.ORDER == 0 and Bosses.CHARIZARD_4 == nil, "the pack's keys untouched")

-- Modern Spawns on (COMPLETE): its table and every pool behind each slot, plus the engine's Rock
-- Smash and Old Rod
spawns = {
  isActive = function() return true end, spawnMode = function() return "complete" end, seed = function() return 5 end,
  tableFor = function(id, terrain)
    if id ~= "EM_ROUTE101" then return nil end
    if terrain == "land" then return { slots = { { species = "ZIGZAGOON" }, { species = "POOCHYENA" } } } end
    return nil
  end,
  poolFor = function(id, terrain)
    if id == "EM_ROUTE101" and terrain == "land" then return { [1] = { "ZIGZAGOON", "SPRIGATITO" } } end
    return nil
  end,
}
local ms = Dy.routeSpecies("EM_ROUTE101")
check(has(ms, 263) and has(ms, 261), "Modern Spawns: its table's species")
check(has(ms, 906), "Modern Spawns: a slot's extended roll (its pool)")
check(has(ms, 74) and has(ms, 129), "Modern Spawns: the engine's Rock Smash and Old Rod kept")
check(not has(ms, 265), "Modern Spawns: the cart's replaced grass species gone")
check(not has(ms, 118), "Modern Spawns: the Good / Super Rod are its own")

-- the plain Max Move: the strongest damaging move's type and power band
local Gmax = loadFile("data/raid_gmax.lua")
local Bt = loadstring(read("src/battle.lua"), "@src/battle.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites, Gmax = Gmax })
local mv = Bt.maxMove({ moves = {
  { status = true, power = 0, typeName = "NORMAL", type = 0, key = "GROWL" },
  { status = false, power = 40, typeName = "DARK", type = 17, key = "BITE" },
  { status = false, power = 75, typeName = "FIRE", type = 10, key = "FIRE_FANG" },
} })
check(mv and mv.name == "Max Flare" and mv.typeName == "FIRE" and mv.power == 130, "Max Flare from Fire Fang (75 -> 130)")
check(mv.spread and mv.isGmax and mv.isMax and mv.baseKey == "FIRE_FANG", "on all four, drawn as Fire Fang")
local knuckle = Bt.maxMove({ moves = { { status = false, power = 60, typeName = "FIGHTING", type = 1, key = "BRICK_BREAK" } } })
check(knuckle.power == 80 and knuckle.gmaxEffect.kind == "boost", "Max Knuckle: the lower column, raises its Attack")
check(Bt.maxMove({ moves = { { status = true, power = 0, typeName = "NORMAL" } } }) == nil, "no damaging move: none")
local starfall = Bt.maxMove({ type1 = 11, type2 = 18, moves = {
  { status = false, power = 120, typeName = "NORMAL", type = 0, key = "DOUBLE_EDGE" },
  { status = false, power = 90, typeName = "FAIRY", type = 18, key = "PLAY_ROUGH" },
} })
check(starfall.name == "Max Starfall", "a move of its own type first (Azumarill: Play Rough over Double-Edge)")

-- raid IVs: Sword / Shield's perfect count by stars, the rest 0-31; HP x3 at 5 stars
local PERFECT = { 1, 2, 3, 4, 4 }
for stars = 1, 5 do
  check(N.RAID.STARS[stars].perfect == PERFECT[stars], stars .. " stars: " .. PERFECT[stars] .. " perfect IVs")
  local spread = {}
  for i = 1, 200 do
    local ivs = Bt.rollIvs(PERFECT[stars], rngOf(i * 7 + stars))
    local n31, ok = 0, true
    for _, k in ipairs(Bt.IV_STATS) do
      local v = ivs[k]
      ok = ok and v >= 0 and v <= 31
      if v == 31 then n31 = n31 + 1 else spread[k] = true end
    end
    check(ok and n31 >= PERFECT[stars], "IVs 0-31, at least the perfect ones at 31")
  end
  local n = 0
  for _ in pairs(spread) do n = n + 1 end
  check(n == 6, "which IVs are perfect varies")
end
check(N.RAID.STARS[5].hpMult == 3.0, "5 stars: HP x3")
local preview = Bt.rollIvs(2)
check(preview.hp == 31 and preview.atk == 31 and preview.def == 15, "a preview: the first ones perfect, the rest 15")

print(("%d/%d checks passed  (max_raids dyna)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
