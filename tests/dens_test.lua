-- Dens, the pure parts: placement (seeded, open ground, clear of warps / edges / each other) and
-- the daily roll (active share, tiers by badges, a boss of the tier).
--   luajit tests/dens_test.lua   (from the repo root)

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function loadFile(path) return assert(loadstring(read(path), "@" .. path))() end

local N = loadFile("data/raid_rules.lua")
local Bosses = loadFile("data/raid_bosses.lua")
local mod = { save = { get = function() return nil end, set = function() end }, log = { warn = function() end },
  options = { get = function() return true end } }
local Dn = loadstring(read("src/dens.lua"), "@src/dens.lua")()(mod, { N = N, Bosses = Bosses })

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

-- a 40 x 30 field, walkable but for a pond and a wall, a warp at (5, 5)
local W, H = 40, 30
local function walkable(x, y)
  if x < 0 or y < 0 or x >= W or y >= H then return false end
  if x >= 10 and x <= 14 and y >= 10 and y <= 14 then return false end   -- the pond
  if x == 25 then return false end                                       -- the wall
  return true
end
local view = { w = W, h = H, open = walkable, warps = { { x = 5, y = 5 } } }
local D = N.RAID.DENS

for seed = 1, 200 do
  local a = Dn.pick(view, seed)
  local b = Dn.pick(view, seed)
  local same = #a == #b
  for i = 1, #a do same = same and a[i].x == b[i].x and a[i].y == b[i].y end
  if seed <= 3 then check(same, "the same seed, the same dens") end
  check(#a >= D.MIN and #a <= D.MAX, "1 or 2 dens a route (" .. #a .. ")")
  for i, p in ipairs(a) do
    local open = true
    for dy = -1, 1 do for dx = -1, 1 do open = open and walkable(p.x + dx, p.y + dy) end end
    check(open, "a den's 3x3 is open")
    check(p.x >= D.EDGE and p.y >= D.EDGE and p.x <= W - 1 - D.EDGE and p.y <= H - 1 - D.EDGE, "clear of the edge")
    check(math.abs(p.x - 5) + math.abs(p.y - 5) >= D.WARP_GAP, "clear of the warp")
    for j = i + 1, #a do
      check(math.abs(p.x - a[j].x) + math.abs(p.y - a[j].y) >= D.SPREAD, "two dens spread apart")
    end
  end
end

-- grass, a trainer's lines, an NPC's walk, a cutscene tile: dens keep off all of them
local G = {}                              -- grass: a band x 2..37, y 18..21
for y = 18, 21 do for x = 2, 37 do G[x .. "," .. y] = true end end
local Rv = {}
local function mark(x, y) Rv[x .. "," .. y] = true end
for k = 1, 6 do mark(30, 4 + k); mark(30 + k, 4); mark(30 - k, 4); mark(30, 4 - k) end   -- a trainer at (30, 4), sight 5 + 1
for y = 7, 11 do for x = 18, 22 do mark(x, y) end end                                    -- an NPC wandering 19..21 x 8..10
mark(8, 25)                                                                              -- a cutscene tile
local rich = { w = W, h = H, open = walkable, warps = view.warps,
  grass = function(x, y) return G[x .. "," .. y] == true end,
  reserved = function(x, y) return Rv[x .. "," .. y] == true end }
local passes, onGrass = {}, 0
for seed = 1, 300 do
  for _, p in ipairs(Dn.pick(rich, seed)) do
    passes[p.pass] = (passes[p.pass] or 0) + 1
    if rich.grass(p.x, p.y) then onGrass = onGrass + 1 end
    local talkFree = not (rich.reserved(p.x, p.y) or rich.reserved(p.x + 1, p.y) or rich.reserved(p.x - 1, p.y)
      or rich.reserved(p.x, p.y + 1) or rich.reserved(p.x, p.y - 1))
    check(talkFree, "neither the den nor where it's talked to from is a trainer's line, an NPC's walk or a cutscene tile")
    local pass
    for _, ps in ipairs(N.RAID.DENS.PASSES) do if ps.name == p.pass then pass = ps end end
    local ok = pass ~= nil
    for dy = -pass.open, pass.open do for dx = -pass.open, pass.open do ok = ok and walkable(p.x + dx, p.y + dy) end end
    check(ok, "the ground round it open (it pinches no path)")
  end
end
check(onGrass > 0, "dens may stand in grass (" .. onGrass .. ")")
print(("  passes used: clear %d, tight %d, last %d; in grass %d"):format(passes.clear or 0, passes.tight or 0,
  passes.last or 0, onGrass))

-- water: a den out on a larger body (7x7 of calm water round it), never in a channel
local function lakeView(lake)
  return { w = W, h = H, warps = {},
    open = function() return false end,          -- no land anywhere: only the water pass can fit
    water = lake }
end
local bigLake = function(x, y) return x >= 5 and x <= 30 and y >= 5 and y <= 24 end
local onWater = 0
for seed = 1, 100 do
  for _, p in ipairs(Dn.pick(lakeView(bigLake), seed)) do
    onWater = onWater + 1
    check(p.pass == "water", "a den on the lake comes from the water pass")
    local ok = true
    for dy = -3, 3 do for dx = -3, 3 do ok = ok and bigLake(p.x + dx, p.y + dy) end end
    check(ok, "calm water all round it")
  end
end
check(onWater > 0, "dens out on a lake (" .. onWater .. ")")
local channel = function(x, y) return y >= 10 and y <= 14 end   -- 5 wide: too narrow
local inChannel = 0
for seed = 1, 100 do inChannel = inChannel + #Dn.pick(lakeView(channel), seed) end
check(inChannel == 0, "never in a channel 5 wide")

-- which maps: routes and ocean routes, never towns, cities, underwater or the Safari Zone
check(Dn.isRoute("EM_ROUTE101", { mapType = 3 }), "a route")
check(Dn.isRoute("EM_ROUTE124", { mapType = 6 }), "an ocean route")
check(not Dn.isRoute("EM_PETALBURG_CITY", { mapType = 2 }), "not a city")
check(not Dn.isRoute("EM_LITTLEROOT_TOWN", { mapType = 1 }), "not a town")
check(not Dn.isRoute("EM_UNDERWATER_ROUTE124", { mapType = 5 }), "not underwater")
check(not Dn.isRoute("EM_SAFARI_ZONE_NORTH", { mapType = 3 }), "not the Safari Zone")
check(not Dn.isRoute("EM_ROUTE121_SAFARI_ZONE_ENTRANCE", { mapType = 8 }), "not the Safari Zone's entrance")
check(not Dn.isRoute("EM_ROUTE104_MR_BRINEYS_HOUSE", { mapType = 8 }), "not a house on a route")

-- a cramped map: no den rather than a bad one
local tiny = Dn.pick({ w = 6, h = 6, open = function() return true end, warps = {} }, 9)
check(#tiny == 0, "a map too small for a den gets none")

-- the daily roll
local actives, total = 0, 2000
for i = 1, total do
  local den = Dn.roll({}, 100, 0, Dn.rng(i))
  if den.active then
    actives = actives + 1
    check(den.stars == 1 or den.stars == 2, "0 badges: 1 or 2 stars")
    check(Bosses[den.boss] and Bosses[den.boss].stars == den.stars, "a boss of the den's tier")
  else
    check(den.boss == nil, "a quiet den has no boss")
  end
  check(den.day == 100, "rolled for the day")
end
local share = actives / total
check(math.abs(share - D.ACTIVE) < 0.05, ("about %d%% active (%.1f%%)"):format(D.ACTIVE * 100, share * 100))
for i = 1, 300 do
  local den = Dn.roll({}, 1, 8, Dn.rng(i))
  if den.active then check(den.stars >= 4, "8 badges: 4 or 5 stars") end
end
for _, stars in ipairs({ 1, 2, 3, 4, 5 }) do check(#Dn.tier(stars) > 0, "tier " .. stars .. " has bosses") end
check(Dn.seedOf("123:EM_ROUTE101") == Dn.seedOf("123:EM_ROUTE101"), "seeds are stable")
check(Dn.seedOf("123:EM_ROUTE101") ~= Dn.seedOf("124:EM_ROUTE101"), "another trainer, another seed")

print(("%d/%d checks passed  (max_raids dens)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
