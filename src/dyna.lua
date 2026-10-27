-- Dynamax dens: a red-beam den holds a Pokemon of its route, Dynamaxed (Sword / Shield's common
-- pool; the purple beam's Gigantamax bosses are data/raid_bosses.lua). The route's Pokemon are
-- every species its wild encounters can give - the engine's tables (grass, water, Rock Smash, the
-- rods) and, with Modern Spawns on, its tables and every pool behind each slot (COMPLETE's extended
-- rolls) - and the den's stars choose how far along its line it is: as found at 1-2★, one
-- evolution on at 3★, the last at 4-5★ (Sword / Shield's dens: the higher stars the evolved forms).
-- A Dynamax boss is keyed "DYNA:<species id>:<stars>" (the id tells forms apart: RATICATE_ALOLA);
-- Dy.install makes Bosses[key] / Sprites[key]
-- answer for such keys (name, types, stars, slot / base stats, height), so everything that reads
-- a boss by key reads these too.
--   Dy = dyna(mod, { N, Bosses, Sprites, typeName })
--   Dy.install() ; Dy.key(id, stars) ; Dy.parse(key) -> id, stars ; Dy.is(key)
--   Dy.routeSpecies(mapId) -> { slot, ... } ; Dy.pick(mapId, stars, rnd) -> key | nil
--   Dy.stageFor(slot, stars, rnd) -> slot   (pure over Dy.evolutionsOf)

return function(mod, deps)
  local Bosses, Sprites = deps.Bosses, deps.Sprites
  local Dy = {}
  Dy.PREFIX = "DYNA:"

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  -- "BULBASAUR" / "Mr. Mime" -> "Bulbasaur" / "Mr. Mime"
  local function titled(s)
    s = tostring(s or ""):gsub("_", " "):lower()
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end

  -- (a legendary Pokemon's raid, by a Dynamax Crystal: ":L" after the stars)
  function Dy.key(id, stars, legend) return ("%s%s:%d%s"):format(Dy.PREFIX, id, stars, legend and ":L" or "") end
  function Dy.is(key) return type(key) == "string" and key:sub(1, #Dy.PREFIX) == Dy.PREFIX end
  -- -> the species id ("RATICATE", "RATICATE_ALOLA"), stars, legendary
  function Dy.parse(key)
    if not Dy.is(key) then return nil end
    local id, s, l = key:match("^DYNA:([%w_]+):(%d)(:?L?)$")
    return id, tonumber(s), l == ":L"
  end

  -- ------- species facts (the engine's; the National Dex's #387+ and its forms registered into the
  -- same tables, each form a species of its own reporting its base's National Dex number)

  local function P() return engine("src.core.game3.pokemon") end
  local function dex()
    local ok, d = pcall(mod.find, mod, "national_dex_gen3")
    return ok and type(d) == "table" and type(d.exports) == "table" and d.exports or nil
  end
  function Dy.nationalOf(slot)
    local Pk = P()
    local ok, n = pcall(Pk and Pk.national or error, slot)
    return ok and tonumber(n) or nil
  end
  -- a species' id that tells its forms apart (the National Dex's, else the cart's name)
  function Dy.idOf(slot)
    local d = dex()
    if d and d.idOfSlot then
      local ok, id = pcall(d.idOfSlot, slot)
      if ok and type(id) == "string" then return id end
    end
    local Pk = P()
    local ok, id = pcall(Pk and Pk.keyName or error, slot)
    return ok and type(id) == "string" and id or nil
  end
  Dy.CART_SCAN = 1500
  local cartSlot = {}
  function Dy.slotOfId(id)
    local d = dex()
    if d and d.slotOf and d.idOfSlot then
      -- (only its own species: asked for a cart one, "RATICATE", it answers with a form of it)
      local ok, s = pcall(d.slotOf, id)
      local okI, back = pcall(d.idOfSlot, ok and s or -1)
      if ok and tonumber(s) and okI and back == id then return tonumber(s) end
    end
    -- a cart species: the lowest slot of that name that is not one of the National Dex's (the
    -- engine's name lookup answers with the last registered - a form: RATICATE -> Alolan Raticate)
    if cartSlot[id] ~= nil then return cartSlot[id] or nil end
    local Pk = P()
    local found = false
    if Pk and Pk.keyName then
      for s = 1, Dy.CART_SCAN do
        local okK, k = pcall(Pk.keyName, s)
        if okK and k == id then
          local own = d and d.idOfSlot and select(2, pcall(d.idOfSlot, s))
          if type(own) ~= "string" or own == id then found = s; break end
        end
      end
    end
    cartSlot[id] = found
    return found or nil
  end

  -- the species a slot evolves into (any method), each once
  function Dy.evolutionsOf(slot)
    local Pk = P()
    local ok, rows = pcall(Pk and Pk.evolutions or error, slot)
    local out, seen = {}, {}
    for _, row in ipairs(ok and type(rows) == "table" and rows or {}) do
      local t = tonumber(row.target) or (row.species and Pk.speciesFromName and select(2, pcall(Pk.speciesFromName, row.species)))
      t = tonumber(t)
      if t and t > 0 and t ~= slot and not seen[t] and Dy.nationalOf(t) then
        seen[t] = true
        out[#out + 1] = t
      end
    end
    return out
  end

  -- how far along its line a den's species is at these stars: as found (1-2), one on (3), the last (4-5);
  -- a branching line (Eevee, Wurmple) takes a branch at random
  Dy.STAGE_STEPS = { [1] = 0, [2] = 0, [3] = 1, [4] = 9, [5] = 9 }
  function Dy.stageFor(slot, stars, rnd)
    local steps = Dy.STAGE_STEPS[stars] or 0
    local s = slot
    for _ = 1, steps do
      local next = Dy.evolutionsOf(s)
      if #next == 0 then break end
      s = next[#next == 1 and 1 or rnd(1, #next)]
    end
    return s
  end

  -- ------- the route's Pokemon

  -- a species id from a Modern Spawns / registry id ("ZIGZAGOON", "national_dex_gen3:SPRIGATITO")
  local function slotFromId(id)
    if tonumber(id) then return tonumber(id) end
    local reg = mod.content and mod.content.pokemon
    if reg and reg.get then
      local ok, rec = pcall(reg.get, reg, id)
      if ok and type(rec) == "table" and tonumber(rec.index) then return tonumber(rec.index) end
    end
    return Dy.slotOfId(id)
  end

  -- the map's ids to try: as the game names it, and the versions' prefixed forms
  local function idsFor(mapId)
    local out = { mapId }
    local bare = tostring(mapId):gsub("^EM_", ""):gsub("^FR_", ""):gsub("^LG_", "")
    for _, p in ipairs({ "", "EM_", "FR_" }) do
      local k = p .. bare
      if k ~= mapId then out[#out + 1] = k end
    end
    return out
  end

  local function engineTable(mapId)
    local Enc = engine("src.core.game3.encounters")
    if not Enc then return nil end
    for _, id in ipairs(idsFor(mapId)) do
      local t = nil
      if Enc.tableFor then
        local ok, v = pcall(Enc.tableFor, id)
        if ok and type(v) == "table" then t = v end
      end
      t = t or (type(Enc._tables) == "table" and Enc._tables[id]) or nil
      if t then return t end
    end
    return nil
  end

  local function spawnsApi()
    local ok, ms = pcall(mod.find, mod, "modern_spawns")
    local api = ok and type(ms) == "table" and ms.exports or nil
    if not (api and type(api.tableFor) == "function") then return nil end
    local okA, on = pcall(api.isActive or function() return false end)
    return okA and on and api or nil
  end
  Dy.SPAWN_TERRAINS = { "land", "water", "fish.good", "fish.super" }

  local cache = {}   -- mapId -> { sig, list }
  function Dy.routeSpecies(mapId)
    if not mapId then return {} end
    local api = spawnsApi()
    local sig = "engine"
    if api then
      local okM, mode = pcall(api.spawnMode or function() return "?" end)
      local okS, seed = pcall(api.seed or function() return 0 end)
      sig = "ms:" .. tostring(okM and mode) .. ":" .. tostring(okS and seed)
    end
    local c = cache[mapId]
    if c and c.sig == sig then return c.list end
    local list, seen = {}, {}
    local function add(slot)
      slot = tonumber(slot)
      if slot and slot > 0 and not seen[slot] and Dy.nationalOf(slot) then
        seen[slot] = true
        list[#list + 1] = slot
      end
    end
    local t = engineTable(mapId)
    local spawned = false
    if api then
      for _, id in ipairs(idsFor(mapId)) do
        for _, terrain in ipairs(Dy.SPAWN_TERRAINS) do
          local okT, tab = pcall(api.tableFor, id, terrain)
          tab = okT and type(tab) == "table" and tab or nil
          local okP, pools = false, nil
          if api.poolFor then okP, pools = pcall(api.poolFor, id, terrain) end
          pools = okP and type(pools) == "table" and pools or nil
          for i, slot in ipairs(tab and tab.slots or {}) do
            spawned = true
            add(slotFromId(slot.species))
            for _, sid in ipairs(pools and pools[i] or {}) do add(slotFromId(sid)) end
          end
        end
        if spawned then break end
      end
    end
    -- the engine's: everything without Modern Spawns; with it, what it leaves alone (Rock Smash, the
    -- Old Rod)
    if t then
      local kinds = spawned and { "rocks" } or { "land", "water", "rocks", "fishing" }
      for _, kind in ipairs(kinds) do
        for _, slot in ipairs(t[kind] and t[kind].slots or {}) do add(slot.species) end
      end
      if spawned and t.fishing and t.fishing.slots then
        for i = 1, 2 do add(t.fishing.slots[i] and t.fishing.slots[i].species) end
      end
    end
    table.sort(list)
    cache[mapId] = { sig = sig, list = list }
    return list
  end

  -- a Dynamax boss for a den on this map at these stars (nil when the route has no wild Pokemon)
  function Dy.pick(mapId, stars, rnd)
    local list = Dy.routeSpecies(mapId)
    if #list == 0 then return nil end
    local slot = Dy.stageFor(list[rnd(1, #list)], stars, rnd)
    local id = Dy.idOf(slot)
    return id and Dy.key(id, stars) or nil
  end

  -- ------- legendary Pokemon (a Dynamax Crystal's raid, as the Max Lair's)

  -- the cart's legendary and mythical Pokemon, by National Dex number; the National Dex's own come from
  -- its listSpecies (legendary or mythical)
  Dy.CART_LEGENDS = { 144, 145, 146, 150, 151, 243, 244, 245, 249, 250, 251, 377, 378, 379, 380, 381, 382, 383,
    384, 385, 386 }
  Dy.LEGEND_STARS = 5
  -- every legendary and mythical Pokemon that can Dynamax: { slot, ... }
  function Dy.legends()
    local out, seen = {}, {}
    local d = dex()
    local dx = d and d.dynamax
    local function add(slot)
      slot = tonumber(slot)
      if not slot or seen[slot] then return end
      if dx and dx.canDynamax and select(2, pcall(dx.canDynamax, slot)) == false then return end
      seen[slot] = true
      out[#out + 1] = slot
    end
    -- (the cart's own species of a number: the National Dex's forms report their base's number - the
    -- engine's speciesFromNational(144) answers Galarian Articuno)
    local Pk = P()
    local want = {}
    for _, n in ipairs(Dy.CART_LEGENDS) do want[n] = true end
    for s = 1, Dy.CART_SCAN do
      local okN, n = pcall(Pk and Pk.national or error, s)
      if okN and want[tonumber(n) or -1] then
        local own = d and d.idOfSlot and select(2, pcall(d.idOfSlot, s))
        if type(own) ~= "string" then
          want[n] = nil
          add(s)
        end
      end
    end
    if d and d.listSpecies then
      local ok, list = pcall(d.listSpecies)
      for _, r in ipairs(ok and type(list) == "table" and list or {}) do
        if r.legendary or r.mythical then add(r.slot) end
      end
    end
    table.sort(out)
    return out
  end
  -- a legendary Pokemon's raid key, one at random (rnd(lo, hi))
  function Dy.pickLegend(rnd)
    local list = Dy.legends()
    if #list == 0 then return nil end
    local id = Dy.idOf(list[rnd(1, #list)])
    return id and Dy.key(id, Dy.LEGEND_STARS, true) or nil
  end

  -- ------- boss records for DYNA keys

  local records, sprites = {}, {}
  local function record(key)
    if records[key] ~= nil then return records[key] or nil end
    local id, stars, legend = Dy.parse(key)
    local slot = id and Dy.slotOfId(id)
    local nat = slot and Dy.nationalOf(slot)
    local Pk = P()
    if not (slot and nat and Pk) then records[key] = false; return nil end
    local okN, name = pcall(Pk.name, slot)
    local okT, types = pcall(Pk.types, slot)
    types = okT and type(types) == "table" and types or { 0, 0 }
    local tn = deps.typeName or function() return "NORMAL" end
    local names = { tn(types[1]) }
    if types[2] and types[2] ~= types[1] then names[2] = tn(types[2]) end
    local rec = { national = nat, slot = slot, name = titled(okN and name or "?"), types = names, stars = stars,
      script = legend and "fierce" or (stars >= 5 and "strong" or "basic"), dyna = true, legend = legend or nil }
    records[key] = rec
    return rec
  end
  local function sprite(key)
    if sprites[key] ~= nil then return sprites[key] or nil end
    local b = record(key)
    local Pk = P()
    if not (b and Pk) then sprites[key] = false; return nil end
    local okS, base = pcall(Pk.stats, b.slot)
    local okD, entry = pcall(Pk.dexEntry, b.slot)
    local sp = { dyna = true, slot = b.slot, base = okS and type(base) == "table" and base or {},
      height = okD and type(entry) == "table" and tonumber(entry.heightM) or nil, cry = false }
    sprites[key] = sp
    return sp
  end
  Dy.record, Dy.sprite = record, sprite

  -- Bosses[key] / Sprites[key] answer for DYNA keys (ORDER and the pack's keys as they are)
  function Dy.install()
    local function hook(t, fn)
      if type(t) ~= "table" then return end
      local mt = getmetatable(t) or {}
      local prev = mt.__index
      mt.__index = function(tbl, k)
        if Dy.is(k) then return fn(k) end
        if type(prev) == "function" then return prev(tbl, k) end
        if type(prev) == "table" then return prev[k] end
        return nil
      end
      setmetatable(t, mt)
    end
    hook(Bosses, record)
    hook(Sprites, sprite)
  end

  -- (drivers / tests)
  function Dy.forget() records, sprites, cache, cartSlot = {}, {}, {}, {} end
  return Dy
end
