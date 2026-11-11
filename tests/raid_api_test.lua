-- The raid API (src/raid_api.lua) over a stand-in engine: a spec's shape and its codes, the boss
-- records under EXT keys (a species, a pack form, a mod's own art), the overrides reaching the
-- boss (src/battle.lua), the rewards added or replacing the roll (src/rewards.lua), other mods'
-- dens (src/dens.lua: spawned on any map, their day, a boss function, the beam's look, done and
-- live again), and the handle's calls never throwing.
--   luajit tests/raid_api_test.lua   (from the repo root)

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

-- ------- a stand-in engine (slot = National Dex number)

local NAMES = { [25] = "PIKACHU", [150] = "MEWTWO", [6] = "CHARIZARD" }
local Pokemon = {
  national = function(s) return NAMES[s] and s or nil end,
  speciesFromNational = function(n) return NAMES[n] and n or nil end,
  name = function(s) return NAMES[s] end,
  keyName = function(s) return NAMES[s] end,
  types = function(s) return s == 150 and { 14, 14 } or s == 6 and { 10, 2 } or { 13, 13 } end,
  stats = function() return { hp = 100, atk = 100, def = 100, spe = 100, spa = 100, spd = 100 } end,
  dexEntry = function(s) return { heightM = s == 150 and 2.0 or 0.4 } end,
  evolutions = function() return {} end,
  movesAtLevel = function() return { 1 } end,
  abilities = function() return { 46, 0 } end,
}
local MOVES = {
  TACKLE = { id = "TACKLE", numId = 1, power = 40, type = 0, accuracy = 100, pp = 35 },
  PSYCHIC = { id = "PSYCHIC", numId = 94, power = 90, type = 14, accuracy = 100, pp = 10 },
  RECOVER = { id = "RECOVER", numId = 105, power = 0, type = 0, accuracy = 0, pp = 10 },
}
MOVES[1] = MOVES.TACKLE
local ITEMS = { ITEM_LEFTOVERS = 200, ITEM_MASTER_BALL = 1, ITEM_RARE_CANDY = 68 }
package.loaded["src.core.game3.pokemon"] = Pokemon
package.loaded["src.core.game3.battle.moves"] = { get = function(ref) return MOVES[ref] end }
package.loaded["src.core.game3.runtime"] = { getSession = function() return { version = "emerald" } end }
package.loaded["src.core.game3.constants"] = { of = function()
  return { id = function(_, kind, name) return kind == "items" and ITEMS[name] or nil end }
end }
-- the field: a 20 x 20 map, walkable but for a wall at x = 5, a warp at (2, 2)
local spawnedNpcs, removed = {}, {}
local runtime = {}
local M = { current = "EM_ROUTE101", currentDef = function() return { width = 20, height = 20 } end }
package.loaded["src.core.game3.map"] = M
package.loaded["src.core.game3.collision"] = {
  inBounds = function(x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWalkable = function(x) return x ~= 5 end,
  isWater = function() return false end,
  warpAt = function(x, y) return x == 2 and y == 2 or nil end,
}
package.loaded["src.core.game3.objects"] = { at = function() return nil end, runtimeByMap = runtime }

local store = {}
local opts = { dens = true }
local logged = {}
local mod = {
  id = "max_raids",
  save = { get = function(_, k) return store[k] end, set = function(_, k, v) store[k] = v end },
  options = { get = function(_, k) return opts[k] end },
  log = { warn = function(_, fmt, ...) logged[#logged + 1] = fmt:format(...) end, info = function() end },
  find = function() return nil end,
  world = {
    spawnNpc = function(_, mapId, def)
      local id = "npc" .. (#spawnedNpcs + 1)
      spawnedNpcs[#spawnedNpcs + 1] = { id = id, map = mapId, def = def }
      runtime[mapId] = runtime[mapId] or {}
      table.insert(runtime[mapId], { id = id })
      return id
    end,
    removeRuntimeNpc = function(_, id) removed[#removed + 1] = id; return true end,
    npc = function() return { setAppearance = function() end } end,
  },
}

local N = loadFile("data/raid_rules.lua")
local Bosses = loadFile("data/raid_bosses.lua")
local Sprites = loadFile("data/raid_sprites.lua")
local Gmax = loadFile("data/raid_gmax.lua")
local TN = { [0] = "NORMAL", [2] = "FLYING", [10] = "FIRE", [13] = "ELECTRIC", [14] = "PSYCHIC" }
local Dy = loadstring(read("src/dyna.lua"), "@src/dyna.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites,
  typeName = function(n) return TN[n] or "NORMAL" end })
Dy.install()
local Bt = loadstring(read("src/battle.lua"), "@src/battle.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites, Gmax = Gmax,
  difficulty = function() return "swsh" end })
local Rw = loadstring(read("src/rewards.lua"), "@src/rewards.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites })
Rw.battle = Bt
local Api = loadstring(read("src/raid_api.lua"), "@src/raid_api.lua")()(mod, { N = N, Bosses = Bosses, Sprites = Sprites,
  Dyna = Dy, Battle = Bt, Rewards = Rw, Gmax = Gmax })
Api.install()
local Dn = loadstring(read("src/dens.lua"), "@src/dens.lua")()(mod, { N = N, Bosses = Bosses, Dyna = Dy })
Api.dens = Dn
local function rngOf(seed)
  local s = seed
  return function(lo, hi)
    s = (1103515245 * s + 12345) % 2147483648
    if not lo then return s / 2147483648 end
    return lo + s % (hi - lo + 1)
  end
end

-- ------- connecting

local files = { ["raid/boss.png"] = "PNG", ["raid/cry.ogg"] = "OGG" }
local provider = { id = "story", read = function(_, path) return files[path] end }
local h = Api.connect(provider)
check(type(h) == "table" and h.id == "story", "connect(mod): a handle named for the mod")
check(Api.connect(provider) == h, "connecting again: the same handle")
check(Api.connect("bad id!") == nil, "a bad id: refused")
check(Api.supports("dens") and Api.supports("art") and not Api.supports("teleport"), "supports: what it has")

-- ------- the spec's shape

local function code(...) local v, c = ...; return v == nil and c or "ok" end
check(code(h:boss("x", nil)) == "bad_spec", "no spec: bad_spec")
check(code(h:boss("x", { stars = 3 })) == "bad_species", "no species or form: bad_species")
check(code(h:boss("x", { species = "PIKACHU", form = "CHARIZARD_4" })) == "bad_species", "both: bad_species")
check(code(h:boss("x", { species = "PIKACHU" })) == "bad_stars", "a species with no stars: bad_stars")
check(code(h:boss("x", { species = "PIKACHU", stars = 6 })) == "bad_stars", "6 stars: bad_stars")
check(code(h:boss("x", { form = "NOT_A_FORM" })) == "bad_form", "an unknown form: bad_form")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, level = 101 })) == "bad_level", "level 101: bad_level")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, moves = { "A", "B", "C", "D", "E" } })) == "bad_move", "5 moves: bad_move")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, nature = "GRUMPY" })) == "bad_nature", "an unknown nature: bad_nature")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, ivs = { hp = 32 } })) == "bad_ivs", "an IV of 32: bad_ivs")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, catch = "maybe" })) == "bad_catch", "catch \"maybe\": bad_catch")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, music = "jazz" })) == "bad_music", "music \"jazz\": bad_music")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, gmax = "NOPE" })) == "bad_gmax", "an unknown G-Max move: bad_gmax")
check(code(h:boss("x", { species = "PIKACHU", stars = 3, art = { sheet = "raid/boss.png" } })) == "bad_art", "art without its frames: bad_art")
check(code(h:boss("x", { form = "CHARIZARD_4", art = { sheet = "a", cell = 64, frames = 1 } })) == "bad_art", "art with a form: bad_art")
check(code(h:boss("bad name", { species = "PIKACHU", stars = 3 })) == "bad_name", "a name with a space: bad_name")

-- ------- a species boss

local key = h:boss("mewtwo", { species = "MEWTWO", stars = 5, level = 70, moves = { "PSYCHIC", "RECOVER" },
  ability = "Pressure", nature = "TIMID", ivs = 31, item = "LEFTOVERS", shiny = false, hp = 1.5, catch = "sure",
  music = "legend", turns = 12, faints = 3, name = "Armored Mewtwo" })
check(key == "EXT:story:mewtwo", "a boss's key: EXT:<mod>:<name>")
local b, sp = Bosses[key], Sprites[key]
check(b and sp, "Bosses / Sprites answer for it")
check(b.slot == 150 and b.national == 150 and b.stars == 5 and b.name == "Armored Mewtwo", "its species, stars and name")
check(b.dyna == true and sp.dyna == true and b.music == "legend" and b.catch == "sure", "the game's sprite, Dynamaxed; its music and catch")
check(b.item == 200 and b.turns == 12 and b.faints == 3 and b.legend == nil, "its item by name, its turns and knock-outs")
check(h:check("mewtwo") == true, "check by its name: resolves")
local boss = Bt.boss(key, rngOf(1))
check(boss.mon.level == 70, "Bt.boss: its level")
local allMax = true
for _, k in ipairs(Bt.IV_STATS) do allMax = allMax and boss.mon.ivs[k] == 31 end
check(allMax, "Bt.boss: its IVs")
check(boss.ability == "PRESSURE" and boss.item == 200, "Bt.boss: its ability by name and its held item")
check(#boss.moves == 2 and boss.moves[1].key == "PSYCHIC", "Bt.boss: its moves")
local plain = h:boss("mewtwo_plain", { species = 150, stars = 5, level = 70, ivs = 31, nature = "HARDY" })
local pb = Bt.boss(plain, rngOf(1))
check(Bosses[plain].slot == 150, "a species by National Dex number")
check(boss.mon.speed > pb.mon.speed and boss.mon.attack < pb.mon.attack and boss.mon.spAtk == pb.mon.spAtk,
  "Timid: Speed up, Attack down, Sp. Atk the same")
check(math.abs(boss.mon.maxHp / pb.mon.maxHp - 1.5) < 0.01, "hp 1.5: half again the HP")
check(Bt.natureId("timid") == 10 and Bt.natureFactor(10, "spe") == 1.1 and Bt.natureFactor(10, "atk") == 0.9, "natures: Timid +Spe -Atk")

-- a move the game lacks: found when first used, the boss unknown
local bad = h:boss("ghost", { species = "PIKACHU", stars = 2, moves = { "NOT_A_MOVE" } })
check(bad ~= nil and Bosses[bad] == nil, "a move the game lacks: the boss unknown at its use")
local ok2, c2 = h:check("ghost")
check(ok2 == nil and c2 == "bad_move", "check: bad_move")
check(h:check("nobody") == nil, "check of an unknown boss: nil")
local unknownSpecies = h:boss("missingno", { species = "MISSINGNO", stars = 1 })
check(Bosses[unknownSpecies] == nil and select(2, h:check("missingno")) == "bad_species", "an unknown species: bad_species")

-- ------- a pack form

local zard = h:boss("zard", { form = "CHARIZARD_4", level = 55 })
local zb, zs = Bosses[zard], Sprites[zard]
check(zb.form == "CHARIZARD_4" and zb.stars == Bosses.CHARIZARD_4.stars and zb.gmax == Bosses.CHARIZARD_4.gmax,
  "a form: the pack's record, its stars and G-Max move")
check(zs.cell == Sprites.CHARIZARD_4.cell and zb.gmaxFactor == true and zb.music == "max", "...its sheet, the factor, the Max music")
check(Bt.boss(zard, rngOf(2)).mon.level == 55, "...its level")
check(rawget(Bosses, "CHARIZARD_4").level == nil, "the pack's own record untouched")

-- ------- a mod's own art

local art = h:boss("art", { species = 25, stars = 3, art = { sheet = "raid/boss.png", cell = 96, frames = 8, cols = 4,
  speed = 3, height = 9, cry = "raid/cry.ogg", cloud = "red" } })
local ab, as = Bosses[art], Sprites[art]
check(as.art and as.cell == 96 and as.frames == 8 and as.cols == 4 and as.speed[1] == 3 and as.height == 9, "art: its frames and height")
check(as.read("raid/boss.png") == "PNG" and as.cryPath == "raid/cry.ogg" and as.cry == true, "art: read from its mod's files, its cry")
check(as.redCloud == true and ab.dyna == nil and ab.slot == 25, "art: the red cloud, not the game's sprite, its species kept")
check(ab.shiny == false, "art without a shiny sheet: never shiny")
check(h:check("art") == true, "check: its files read")
files["raid/boss.png"] = nil
check(select(2, h:check("art")) == "bad_art", "check: a sheet that can't be read is bad_art")
files["raid/boss.png"] = "PNG"

-- ------- rewards

local list, money = Rw.custom({ mode = "replace", items = { { "MASTER_BALL", 1 }, { 68, 3 }, { "NOT_AN_ITEM", 1 } }, money = 500 },
  { { id = 99, n = 1 } }, {}, function(...) logged[#logged + 1] = string.format(...) end)
check(#list == 2 and list[1].id == 1 and list[2].id == 68 and list[2].n == 3 and money == 500, "replace: its items and money only")
check(logged[#logged]:find("NOT_AN_ITEM", 1, true) ~= nil, "an item the game lacks: left out, warned")
local list2 = Rw.custom({ items = { { "ITEM_RARE_CANDY", 2 } }, roll = function(ctx) return { { "LEFTOVERS", ctx.stars } } end },
  { { id = 99, n = 1 } }, { stars = 4 })
check(#list2 == 3 and list2[1].id == 99 and list2[2].id == 68 and list2[3].id == 200 and list2[3].n == 4, "add: the roll, its items, its roll(ctx)")
local list3 = Rw.custom({ mode = "replace", roll = function() error("boom") end }, {}, {}, function() end)
check(#list3 == 0, "a roll that fails: nothing, no error")
check(Rw.itemOf("Master Ball") == 1 and Rw.itemOf("ITEM_MASTER_BALL") == 1 and Rw.itemOf(68) == 68 and Rw.itemOf("NOPE") == nil, "items by name or number")

-- ------- dens

check(code(h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4 })) == "unknown_boss", "a den with no boss: unknown_boss")
check(code(h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4, boss = key, beam = { color = { 2, 0, 0 } } })) == "bad_beam", "a colour over 1: bad_beam")
check(code(h:den("d1", { map = "EM_ROUTE101", x = -1, y = 4, boss = key })) == "bad_cell", "a cell off the map: bad_cell")
check(code(h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4, boss = key, refresh = "weekly" })) == "bad_refresh", "refresh weekly: bad_refresh")
check(code(h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4, boss = key, rewards = { mode = "all" } })) == "bad_rewards", "rewards mode all: bad_rewards")
local ended = {}
check(h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4, boss = "mewtwo", beam = { color = { 0.2, 1, 0.5 }, height = 200, sparks = 0 },
  sprite = { active = "STORY_DEN" }, rewards = { mode = "replace", items = { { "MASTER_BALL", 1 } } },
  onEnd = function(info) ended[#ended + 1] = info end }) == true, "a den: added")
local den = Dn.extDen("story:d1")
check(den and den.boss == key and den.beamStyle.color[2] == 1 and den.beamStyle.height == 200 and den.beamStyle.sparks == 0
  and den.beamStyle.width == 1, "the den: its boss by name, its beam over red's")
check(Dn.spriteFor(den) == "STORY_DEN", "its own sprite")
-- (not a route, not awake: ours would not appear; another mod's does)
M.current = "EM_PETALBURG_CITY"
check(h:den("d2", { map = "EM_PETALBURG_CITY", x = 5, y = 3, boss = key }) == true, "a den in a town")
check(h:den("d3", { map = "EM_PETALBURG_CITY", x = 7, y = 3, boss = key, awake = true, beam = false }) == true, "a den that waits for the awakening")
check(Dn.ensure() == true, "ensure on the town: done")
local placed = {}
for _, n in ipairs(spawnedNpcs) do placed[n.def.x .. "," .. n.def.y] = n end
check(placed["5,3"] == nil, "a den on a wall: not placed")
check(logged[#logged]:find("no place for it", 1, true) ~= nil, "...and the mod told why")
check(placed["7,3"] == nil, "a den waiting for the awakening: not yet")
Dn.setAwake(true)
check(Dn.ensure() == true and #spawnedNpcs == 1 and spawnedNpcs[1].def.x == 7, "awake: it appears")
check(Dn.byObject(spawnedNpcs[1].id) == Dn.extDen("story:d3"), "byObject: the den of the object")
M.current = "EM_ROUTE101"
opts.dens = false
check(Dn.ensure() == false, "RAID DENS off: no dens at all")
opts.dens = true
local before = #spawnedNpcs
Dn.ensure()
local d1npc = spawnedNpcs[#spawnedNpcs]
check(#spawnedNpcs >= before + 1 and d1npc.def.x == 3 and d1npc.def.sprite == "STORY_DEN", "on its route: spawned with its sprite")
check(den.day ~= nil and Dn.isLive(den), "its day set, live")
-- done: spent, saved; a new day: live again
Dn.finish(den)
check(den.done and store.extDens["story:d1"].done == true, "finished: done, saved under extDens")
local st = h:denState("d1")
check(st.live == false and st.done == true and st.boss == key, "denState: spent")
check(h:setDen("d1", { done = false }) == true and Dn.isLive(den), "setDen done = false: live again")
check(h:setDen("d1", { active = false }) == true and not Dn.isLive(den), "setDen active = false: quiet")
check(code(h:setDen("d1", { x = 4 })) == "bad_spec", "setDen of its place: refused")
check(code(h:setDen("nope", { active = true })) == "unknown_den", "setDen of an unknown den: unknown_den")
h:setDen("d1", { active = true })
den.done, den.day = true, "1999-01-01"
Dn.ensure()
check(not den.done and den.day ~= "1999-01-01", "a new day: live again")
-- refresh never: done stays done
h:den("once", { map = "EM_ROUTE101", x = 8, y = 8, boss = key, refresh = "never" })
local once = Dn.extDen("story:once")
Dn.ensure()
Dn.finish(once)
once.day = "1999-01-01"
Dn.ensure()
check(once.done == true, "refresh never: still done on a new day")
-- a boss function: asked each day, its spec registered
local asked = 0
h:den("daily", { map = "EM_ROUTE101", x = 9, y = 9, boss = function(ctx)
  asked = asked + 1
  return { species = "PIKACHU", stars = math.max(1, ctx.stars[1]) }
end })
Dn.ensure()
local daily = Dn.extDen("story:daily")
check(asked == 1 and daily.boss == "EXT:story:daily_day" and Bosses[daily.boss] ~= nil, "a boss function: asked, its spec registered for the day")
Dn.ensure()
check(asked == 1, "...not asked again the same day")
check(store.extDens["story:daily"].boss == "EXT:story:daily_day", "...its choice saved")
-- the saved day taken up again (a new game session)
local saved = store.extDens["story:d1"]
h:removeDen("d1")
check(Dn.extDen("story:d1") == nil and #removed >= 1, "removeDen: gone, its object removed")
h:den("d1", { map = "EM_ROUTE101", x = 3, y = 4, boss = key })
check(Dn.extDen("story:d1").day == saved.day, "added again: its saved day taken up")

-- ------- calls never throw

local okAll = pcall(function()
  h:boss(nil, nil); h:boss({}, {}); h:den(nil, nil); h:den("z", { map = 1 }); h:setDen(nil, nil)
  h:removeDen(nil); h:denState(nil); h:open(nil); h:check(nil)
end)
check(okAll, "bad calls: nil and a code, never an error")
check(code(h:open(key)) == "no_raid", "open with no raid running: no_raid")

print(("%d/%d checks passed  (max_raids raid api)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
