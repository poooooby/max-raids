-- Max Raid dens on the routes. Each outdoor route gets one or two dens the first time the player is
-- on it, at open spots picked from the map itself (seeded by the save's trainer id and the map, so
-- they come out the same; saved once chosen, so they never move). Each day a den rolls again:
-- active (a boss from the star tiers the badges allow) or quiet. A den is an object of the
-- engine's (mod.world:spawnNpc: drawn and collided like any NPC; not saved, so spawned again
-- after a load); an active one has a beam of light rising from it (a field actor). Pressing A on
-- a den (the world.talk hook) opens it (deps.open(den)).
--   Dn = dens(mod, { N, Bosses, open, T })
--   Dn.pick(view, seed) -> { {x, y}, ... }   (pure: view = { w, h, open(x, y), warps })
--   Dn.roll(den, day, badges, rng)           (pure: rerolls a den for a day)
--   Dn.ensure() ; Dn.registerSprites() ; Dn.install(hooks) ; Dn.today() ; Dn.badges()

return function(mod, deps)
  local N, Bosses = deps.N, deps.Bosses
  local D = N.RAID.DENS
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs
  local Dn = {}

  -- the words' language (src/i18n.lua; deps.T): English as it is without it
  local function plainWords(s, ...) if select("#", ...) > 0 then return s:format(...) end return s end
  local T = (deps and deps.T) or setmetatable({ mark = function(s) return s end, c = function(_, s, ...) return plainWords(s, ...) end,
    game = plainWords, t = plainWords }, { __call = function(_, s, ...) return plainWords(s, ...) end })
  -- the den's sprites: active / spent (assets/den/), drawn over grass (no grass in front of it yet)
  Dn.SPRITE = { active = "MAX_RAIDS_DEN", spent = "MAX_RAIDS_DEN_SPENT" }
  -- the sprites are 16 x 16, one tile. Gen 3 draws the anchor's row 12 px down the tile, so row 12
  -- puts the den on its own tile exactly
  Dn.SIZE = 16
  Dn.ANCHOR_Y = 12
  -- the placement rules' version: a map's dens saved under an older one are placed again
  Dn.PLACE_V = 5

  -- ------- a seeded generator (pure: an LCG over 32 bits, exact in doubles)

  local function seedOf(str)
    local h = 2166136261
    for i = 1, #str do h = (h * 31 + str:byte(i)) % 4294967296 end
    return h
  end
  Dn.seedOf = seedOf
  function Dn.rng(seed)
    local s = (tonumber(seed) or 1) % 4294967296
    -- a few steps first: an LCG's first draw from neighbouring seeds rises almost in step
    for _ = 1, 4 do s = (1664525 * s + 1013904223) % 4294967296 end
    return function(lo, hi)
      s = (1664525 * s + 1013904223) % 4294967296
      local u = s / 4294967296
      if lo then return lo + floor(u * (hi - lo + 1)) end
      return u
    end
  end

  -- ------- placement (pure)

  -- open spots for dens. view = { w, h, warps = { {x, y} },
  --   open(x, y)      walkable, not water, nothing standing on it
  --   grass(x, y)     wild-encounter grass (only for a pass's optional grass radius)
  --   reserved(x, y)  where an NPC or trainer walks or stands, a trainer's line of sight, a
  --                   cutscene's trigger tile
  --   ground(x, y)    the map's plain ground or grass - not a trail, sand, flowers, a bridge;
  --                   nil: any
  --   water(x, y)     calm surfable water: not a dive spot, a current or a waterfall }
  -- A den never pinches a path (the ground round it open), stands on plain ground or grass, and
  -- neither it nor the four cells the player talks to it from are reserved. The passes try the best
  -- spots first: D.PASSES = { { open = radius of open ground, ground = radius of plain ground,
  -- grass = (optional) radius kept clear of grass } or { water = radius of calm water round it } ...
  -- }. The seed decides how many dens and where.
  function Dn.pick(view, seed)
    local rnd = Dn.rng(seed)
    local count = rnd(D.MIN, D.MAX)
    local out = {}
    local grass = view.grass or function() return false end
    local reserved = view.reserved or function() return false end
    local ground = view.ground or function() return true end
    local water = view.water or function() return false end
    local function fits(x, y, pass)
      if pass.water then
        -- a larger body of calm water: every cell within pass.water of it
        local r = pass.water
        for dy = -r, r do
          for dx = -r, r do
            if not water(x + dx, y + dy) then return false end
          end
        end
      else
        local r = pass.open
        for dy = -r, r do
          for dx = -r, r do
            if not view.open(x + dx, y + dy) then return false end
          end
        end
        -- plain ground under it and round it (pass.ground cells): on no trail, nor against one
        local gr = pass.ground or 0
        for dy = -gr, gr do
          for dx = -gr, gr do
            if not ground(x + dx, y + dy) then return false end
          end
        end
      end
      local g = pass.grass
      if g then
        for dy = -g, g do
          for dx = -g, g do
            if grass(x + dx, y + dy) then return false end
          end
        end
      end
      if reserved(x, y) or reserved(x + 1, y) or reserved(x - 1, y) or reserved(x, y + 1) or reserved(x, y - 1) then
        return false
      end
      for _, w in ipairs(view.warps or {}) do
        if abs(w.x - x) + abs(w.y - y) < D.WARP_GAP then return false end
      end
      for _, p in ipairs(out) do
        if abs(p.x - x) + abs(p.y - y) < D.SPREAD then return false end
      end
      return true
    end
    local x0, x1 = D.EDGE, view.w - 1 - D.EDGE
    local y0, y1 = D.EDGE, view.h - 1 - D.EDGE
    if x1 < x0 or y1 < y0 then return out end
    for _, pass in ipairs(D.PASSES) do
      for _ = 1, D.TRIES do
        if #out >= count then break end
        local x, y = rnd(x0, x1), rnd(y0, y1)
        if fits(x, y, pass) then out[#out + 1] = { x = x, y = y, pass = pass.name } end
      end
      if #out >= count then break end
    end
    return out
  end

  -- the tiers a den may roll with this many badges
  function Dn.starsFor(badges)
    local pick = N.RAID.BADGE_STARS[1].stars
    for _, row in ipairs(N.RAID.BADGE_STARS) do
      if (badges or 0) >= row.min then pick = row.stars end
    end
    return pick
  end

  -- the bosses of a tier (the roster's order), built once
  local tiers = nil
  function Dn.tier(stars)
    if not tiers then
      tiers = {}
      for _, key in ipairs(Bosses.ORDER or {}) do
        local b = Bosses[key]
        if b then
          tiers[b.stars] = tiers[b.stars] or {}
          table.insert(tiers[b.stars], key)
        end
      end
    end
    return tiers[stars] or {}
  end

  -- a den for a new day: active or quiet, its tier, its beam and boss (pure but for `pickDyna`):
  -- purple (D.RARE of them) a Gigantamax boss of the tier, else red, pickDyna(stars, rnd) -> a
  -- Pokemon of the route Dynamaxed (src/dyna.lua); a route with none is purple
  function Dn.roll(den, day, badges, rnd, pickDyna)
    den.day = day
    den.done = nil
    den.active = rnd() < D.ACTIVE
    if not den.active then den.stars, den.boss, den.rare = nil, nil, nil; return den end
    local tiersOk = Dn.starsFor(badges)
    den.stars = tiersOk[rnd(1, #tiersOk)]
    den.rare = rnd() < (D.RARE or 0)
    den.boss = nil
    if not den.rare and pickDyna then den.boss = pickDyna(den.stars, rnd) end
    if not den.boss then
      den.rare = true
      local list = Dn.tier(den.stars)
      den.boss = list[rnd(1, max(1, #list))]
    end
    return den
  end

  -- a den's day, in one place: quiet (not active), live (active, its raid still to come) or done
  -- (won or left by Run: spent until the next roll)
  function Dn.isLive(den) return den and den.active == true and not den.done or false end

  -- ------- the engine's side (guarded: headless loads skip it)

  -- an engine module (found ones kept: a mod's require makes garbage each call)
  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m then return m end
    local ok
    ok, m = pcall(require, name)
    m = ok and type(m) == "table" and m or nil
    engineMods[name] = m
    return m
  end

  local function session()
    local R = engine("src.core.game3.runtime")
    return R and R.getSession and R.getSession() or nil
  end

  -- the day number, turning over at 12am: the cart's clock on Ruby / Sapphire / Emerald (the
  -- device's time plus what the player set in the game - the clock National Dex Gen 3's
  -- time-of-day rules read too), the device's local date on FireRed / LeafGreen (Rtc.hostInfo, as
  -- National Dex's device clock). A map's dens roll again for a new day when it is next entered.
  function Dn.today()
    local Rtc = engine("src.core.game3.rtc")
    local s = session()
    -- (the cart's clock unless National Dex Gen 3's CLOCK SOURCE is Device, which the time of day
    -- then follows too: the dens turn over with it, at the device's midnight)
    local src = Dn.clockSource or (deps.clockSource and deps.clockSource())
    if src ~= "device" and Rtc and Rtc.enabled and s and Rtc.enabled(s) and Rtc.calcLocalTime then
      local ok, t = pcall(Rtc.calcLocalTime, s)
      if ok and type(t) == "table" and tonumber(t.days) then return tonumber(t.days) end
    end
    local info = Rtc and Rtc.hostInfo and select(2, pcall(Rtc.hostInfo, nil))
    if type(info) == "table" and info.year then
      return floor(os.time({ year = 2000 + info.year, month = info.month, day = info.day, hour = 12 }) / 86400)
    end
    -- (no host clock: the local date too - os.time() / 86400 would turn over at UTC's midnight)
    local d = os.date("*t")
    return floor(os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
  end

  -- gym badges held (the version's badge flags)
  function Dn.badges()
    local Flags = engine("src.core.game3.scripting.flags")
    local Space = engine("src.core.game3.scripting.space")
    local Profile = engine("src.core.game3.profile")
    local store = Space and Space.getStore and Space.getStore()
    if not (Flags and store and Profile) then return 0 end
    local ok, P = pcall(Profile.forSession, nil)
    local okT, t = pcall(Flags.forVersion, ok and P and P.id or nil)
    local list = okT and t and t.BADGES or Flags.BADGES or {}
    local n = 0
    for _, b in ipairs(list) do
      local flag = type(b) == "table" and b.flag or b
      local okF, set = pcall(Flags.getFlag, store, nil, flag)
      if okF and set then n = n + 1 end
    end
    return min(8, n)
  end

  local function trainerId()
    local s = session()
    return s and (s.trainerId or s.id or s.playerId) or 0
  end

  -- the dens saved for a map: { { x, y, day, active, stars, boss, done }, ... } (nil: not yet chosen)
  local function saved()
    local all = mod.save:get("dens")
    if type(all) ~= "table" then all = {}; mod.save:set("dens", all) end
    return all
  end
  function Dn.forMap(mapId) return saved()[mapId] end

  -- a route: the map type ROUTE (3) or OCEAN_ROUTE (6) - never a town (1), a city (2), underwater
  -- (5) or indoors - and never the Safari Zone (its areas, and its entrance on Route 121)
  Dn.ROUTE_TYPES = { [3] = true, [6] = true }
  local function isRoute(mapId, def)
    if type(mapId) ~= "string" or mapId:find("SAFARI", 1, true) then return false end
    local mt = def and tonumber(def.mapType)
    if mt then return Dn.ROUTE_TYPES[mt] == true end
    return mapId:find("ROUTE", 1, true) ~= nil
  end
  Dn.isRoute = isRoute

  -- the cells kept free of dens on the current map: every object's wander area (its start, ±
  -- rangeX / rangeY, + RESERVE_PAD); for a trainer, its lines of sight from anywhere in that area,
  -- all four ways (it may turn), sight + SIGHT_PAD long; every cutscene trigger tile (+ RESERVE_PAD)
  local function reservedOf(mapId, def)
    local Objects = engine("src.core.game3.objects")
    local Sight = engine("src.core.game3.trainer_sight")
    local set = {}
    local function mark(x, y) set[x .. "," .. y] = true end
    local function box(x0, y0, x1, y1)
      for y = y0, y1 do for x = x0, x1 do mark(x, y) end end
    end
    local pad, spad = D.RESERVE_PAD, D.SIGHT_PAD
    for _, lid in ipairs(Objects and Objects._order or {}) do
      local eo = Objects._byId and Objects._byId[lid]
      local d = eo and eo.def
      if eo and d and not d.runtime then
        local sx = tonumber(d.x) or tonumber(eo.cellX) or 0
        local sy = tonumber(d.y) or tonumber(eo.cellY) or 0
        local rx = tonumber(eo.rangeX or d.rangeX) or 0
        local ry = tonumber(eo.rangeY or d.rangeY) or 0
        box(sx - rx - pad, sy - ry - pad, sx + rx + pad, sy + ry + pad)
        local trainer = Sight and Sight.isTrainerType and Sight.isTrainerType(eo)
        local sight = tonumber(eo.sight or d.sight or d.trainerRange) or 0
        if trainer and sight > 0 then
          local reach = sight + spad
          for cy = sy - ry, sy + ry do
            for cx = sx - rx, sx + rx do
              for k = 1, reach do
                mark(cx + k, cy); mark(cx - k, cy); mark(cx, cy + k); mark(cx, cy - k)
              end
            end
          end
        end
      end
    end
    local events = def and def.coordEvents
    if not events then
      local Space = engine("src.core.game3.scripting.space")
      local ev = Space and Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
      events = ev and ev.coordEvents
    end
    for _, ev in ipairs(type(events) == "table" and events or {}) do
      local x, y = tonumber(ev.x), tonumber(ev.y)
      if x and y then box(x - pad, y - pad, x + pad, y + pad) end
    end
    return set
  end

  -- the current map's view for placing dens, through the engine's collision (the active map)
  local function viewOf(mapId, def)
    local C = engine("src.core.game3.collision")
    local Objects = engine("src.core.game3.objects")
    local Enc = engine("src.core.game3.encounters")
    if not (C and def) then return nil end
    -- water a den keeps off: dive spots, currents, waterfalls
    local roughWater = {}
    local MB = engine("src.core.game3.mb")
    for _, name in ipairs({ "DEEP_WATER", "EASTWARD_CURRENT", "WESTWARD_CURRENT", "NORTHWARD_CURRENT",
      "SOUTHWARD_CURRENT", "WATERFALL", "NO_SURFACING" }) do
      local ok, id = pcall(function() return MB and MB.id(name) end)
      if ok and id then roughWater[id] = true end
    end
    local warps = {}
    for _, w in ipairs(def.warps or {}) do warps[#warps + 1] = { x = w.x, y = w.y } end
    local reserved = reservedOf(mapId, def)
    -- the plain ground: the commonest metatile among the open, grassless cells
    local plain = nil
    local lay = C._mapDef and C._mapDef.midLayout
    if lay and lay.midAt then
      local counts, best, bestN = {}, nil, 0
      local w, h = tonumber(def.width) or 0, tonumber(def.height) or 0
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          if C.isWalkable(x, y) and not (C.isWater and C.isWater(x, y)) and not (C.isGrass and C.isGrass(x, y)) then
            local m = lay:midAt(x, y)
            local n = (counts[m] or 0) + 1
            counts[m] = n
            if n > bestN then best, bestN = m, n end
          end
        end
      end
      -- (grass counts as ground too: the den is drawn over it)
      if best ~= nil then
        plain = function(x, y)
          if not C.inBounds(x, y) then return false end
          return lay:midAt(x, y) == best or (C.isGrass and C.isGrass(x, y)) or false
        end
      end
    end
    return {
      w = tonumber(def.width) or 0, h = tonumber(def.height) or 0, warps = warps,
      open = function(x, y)
        if not (C.inBounds(x, y) and C.isWalkable(x, y)) then return false end
        if C.isWater and C.isWater(x, y) then return false end
        if C.warpAt and C.warpAt(x, y) then return false end
        if Objects and Objects.at and Objects.at(x, y) then return false end
        return true
      end,
      water = function(x, y)
        if not (C.inBounds(x, y) and C.isWater and C.isWater(x, y)) then return false end
        local beh = C.behavior and C.behavior(x, y)
        if beh == nil or (C.isSurfable and not C.isSurfable(beh)) then return false end
        if roughWater[beh] then return false end
        if C.warpAt and C.warpAt(x, y) then return false end
        if Objects and Objects.at and Objects.at(x, y) then return false end
        return true
      end,
      grass = function(x, y)
        if not C.inBounds(x, y) then return false end
        if C.isGrass and C.isGrass(x, y) then return true end
        if Enc and Enc.terrainAt then
          local ok, t = pcall(Enc.terrainAt, x, y)
          if ok and t == "land" then return true end
        end
        return false
      end,
      reserved = function(x, y) return reserved[x .. "," .. y] == true end,
      reservedSet = reserved,
      ground = plain,
    }
  end
  Dn.viewOf = viewOf

  -- spawned this field session: [mapId][i] = the object's id
  local spawned = {}
  local function alive(mapId, id)
    local Objects = engine("src.core.game3.objects")
    for _, def in ipairs(Objects and Objects.runtimeByMap and Objects.runtimeByMap[mapId] or {}) do
      if def.id == id then return true end
    end
    return false
  end

  -- (another mod's den may name its own sprites: { active, spent })
  local function spriteFor(den)
    local own = den.sprite
    if type(own) == "table" then
      if Dn.isLive(den) then return own.active or Dn.SPRITE.active end
      return own.spent or own.active or Dn.SPRITE.spent
    end
    return Dn.isLive(den) and Dn.SPRITE.active or Dn.SPRITE.spent
  end
  Dn.spriteFor = spriteFor

  -- ------- another mod's dens (src/raid_api.lua): a place of its choosing on any map, its own beam
  -- and boss. Registered each boot and held here; each one's day saved under "extDens"[key] =
  -- { day, done, boss } (the boss only when its mod's function chose it for the day)
  local extMaps, extByKey, extSpawned = {}, {}, {}
  local function extSaved()
    local all = mod.save:get("extDens")
    return type(all) == "table" and all or {}
  end
  local function extStore(den)
    local all = extSaved()
    all[den.ext.key] = { day = den.day, done = den.done and true or nil, boss = den.rolled and den.boss or nil }
    mod.save:set("extDens", all)
  end
  local function extDespawn(key)
    local id = extSpawned[key]
    extSpawned[key] = nil
    if id and mod.world and mod.world.removeRuntimeNpc then pcall(mod.world.removeRuntimeNpc, mod.world, id) end
  end
  function Dn.removeExt(key)
    local den = extByKey[key]
    if not den then return false end
    extByKey[key] = nil
    local list = extMaps[den.map] or {}
    for i = #list, 1, -1 do if list[i] == den then table.remove(list, i) end end
    extDespawn(key)
    return true
  end
  -- den = { map, x, y, active, boss | bossFn(ctx) -> key, beamStyle | false, sprite, refresh "daily" |
  -- "never", awake, ext = { key, mod, den, rewards, onEnd } }; its saved day taken up again
  function Dn.addExt(den)
    local key = den.ext.key
    Dn.removeExt(key)
    local st = extSaved()[key]
    if type(st) == "table" then
      den.day, den.done = st.day, st.done == true or nil
      if den.bossFn and type(st.boss) == "string" then den.boss, den.rolled = st.boss, true end
    end
    extByKey[key] = den
    extMaps[den.map] = extMaps[den.map] or {}
    table.insert(extMaps[den.map], den)
    Dn.pending = true
    return den
  end
  function Dn.extDen(key) return extByKey[key] end
  -- a change from its mod (active, boss, beam, sprite, rewards, onEnd; done = false: live again now)
  function Dn.updateExt(key, patch)
    local den = extByKey[key]
    if not den then return false end
    for k, v in pairs(patch) do
      if k == "rewards" or k == "onEnd" then den.ext[k] = v
      elseif k == "done" then den.done = v and true or nil
      else den[k] = v end
    end
    if patch.done ~= nil or patch.boss ~= nil then
      if patch.boss ~= nil then den.rolled = nil end
      extStore(den)
    end
    Dn.pending = true
    return true
  end

  -- a cell another mod's den may stand on: in the map, walkable or water, no warp, no object
  local function extCellOk(x, y)
    local C = engine("src.core.game3.collision")
    if not C then return true end
    if C.inBounds and not C.inBounds(x, y) then return false end
    if not (C.isWalkable(x, y) or (C.isWater and C.isWater(x, y))) then return false end
    if C.warpAt and C.warpAt(x, y) then return false end
    local Objects = engine("src.core.game3.objects")
    if Objects and Objects.at and Objects.at(x, y) then return false end
    return true
  end

  -- the map's dens from other mods: their day (a new day: live again, and their mod's function asked
  -- for the day's boss - "never": once), spawned (again after a load), hidden while one asks for the
  -- awakening and it has not come
  local function ensureExt(mapId)
    local list = extMaps[mapId]
    if not (list and #list > 0) then return false end
    local today = Dn.today()
    local retry = false
    for i, den in ipairs(list) do
      local key = den.ext.key
      local fresh = den.day == nil or (den.refresh ~= "never" and den.day ~= today)
      if fresh then den.day, den.done = today, nil end
      -- (its mod's function asked for the day's boss: on a new day, or when the one it chose is no
      -- longer known - a boss its function made, not yet made again since the game started)
      local ask = den.bossFn and ((fresh and (den.refresh ~= "never" or not den.rolled))
        or not (type(den.boss) == "string" and Bosses[den.boss]))
      if ask then
        local badges = Dn.badges()
        local rnd = Dn.rng(seedOf(tostring(trainerId()) .. ":" .. key .. ":" .. tostring(today)))
        local ctx = { day = today, badges = badges, stars = Dn.starsFor(badges), map = mapId, rng = rnd }
        local ok, k = pcall(den.bossFn, ctx)
        if ok and type(k) == "string" then den.boss, den.rolled = k, true
        elseif not ok then mod.log:warn("den %s: its boss function failed: %s", key, tostring(k)) end
      end
      if fresh or ask then extStore(den) end
      local id = extSpawned[key]
      if den.awake and not Dn.awake() then
        if id then extDespawn(key) end
      elseif not (id and alive(mapId, id)) then
        if not extCellOk(den.x, den.y) then
          if not den.warned then
            den.warned = true
            mod.log:warn("den %s: no place for it at %s (%d, %d): a walkable or water cell with no warp or object is needed",
              key, mapId, den.x, den.y)
          end
        else
          local newId, why = mod.world:spawnNpc(mapId, { x = den.x, y = den.y, sprite = spriteFor(den),
            movement = "MOVEMENT_TYPE_FACE_DOWN", facing = "down" })
          if newId then extSpawned[key] = newId
          elseif tostring(why):find("overworld", 1, true) then retry = true
          else mod.log:warn("den %s (#%d on %s) not placed: %s", key, i, mapId, tostring(why)) end
        end
      else
        local h = mod.world:npc(mapId, id)
        if h and h.setAppearance then pcall(h.setAppearance, h, spriteFor(den)) end
      end
    end
    if retry then return nil end
    return true
  end

  -- the current map's dens: ours on a route (once the region has awoken) and other mods' on any map,
  -- all of them only while RAID DENS is on; true when done, false when there is nothing to do here,
  -- nil to try again (the field not running yet)
  local ensureRoute
  function Dn.ensure()
    if mod.options:get("dens") == false then return false end
    local M = engine("src.core.game3.map")
    local mapId = M and M.current
    local def = M and M.currentDef and M.currentDef()
    if not (mapId and def) then return false end
    -- (ours none until the region has awoken: the first badge, then Dn.awaken's shake and words)
    local a = false
    if Dn.awake() and isRoute(mapId, def) then a = ensureRoute(mapId, def) end
    local b = ensureExt(mapId)
    if a == nil or b == nil then return nil end
    return (a or b) and true or false
  end

  -- a route's own dens: chosen (once), rolled for today, spawned (again after a load)
  ensureRoute = function(mapId, def)
    local all = saved()
    local list = all[mapId]
    -- (placed under older rules: chosen again under these)
    if list and list.v ~= Dn.PLACE_V then list = nil end
    if not list then
      local view = viewOf(mapId, def)
      if not view then return false end
      list = { v = Dn.PLACE_V }
      local nres = 0
      for _ in pairs(view.reservedSet or {}) do nres = nres + 1 end
      Dn.placedWith = Dn.placedWith or {}
      Dn.placedWith[mapId] = nres
      for _, p in ipairs(Dn.pick(view, seedOf(tostring(trainerId()) .. ":" .. mapId))) do
        list[#list + 1] = { x = p.x, y = p.y, pass = p.pass }
      end
      all[mapId] = list
      mod.save:set("dens", all)
    end
    local today, badges = Dn.today(), nil
    local retry = false
    for i, den in ipairs(list) do
      if den.day ~= today then
        badges = badges or Dn.badges()
        local Dy = deps.Dyna
        Dn.roll(den, today, badges, Dn.rng(seedOf(tostring(trainerId()) .. ":" .. mapId .. ":" .. i .. ":" .. today)),
          Dy and function(stars, rnd) return Dy.pick(mapId, stars, rnd) end or nil)
      end
      spawned[mapId] = spawned[mapId] or {}
      local id = spawned[mapId][i]
      if not (id and alive(mapId, id)) then
        local newId, why = mod.world:spawnNpc(mapId, { x = den.x, y = den.y, sprite = spriteFor(den),
          movement = "MOVEMENT_TYPE_FACE_DOWN", facing = "down" })
        if newId then spawned[mapId][i] = newId
        elseif tostring(why):find("overworld", 1, true) then retry = true
        else mod.log:warn("den %s #%d not placed: %s", mapId, i, tostring(why)) end
      else
        local h = mod.world:npc(mapId, id)
        if h and h.setAppearance then pcall(h.setAppearance, h, spriteFor(den)) end
      end
    end
    if retry then return nil end
    return true
  end

  -- ------- the dens awaken: none before the first gym badge. Back outside with it (the gym left,
  -- or the next time the player is outdoors with the field free), once: the screen shakes as the
  -- game's own quakes do (the field camera swung from a task, as the ShakeScreen / ShakeCamera
  -- specials), then the words; the player held meanwhile (Field.lock). Saved as "densAwake".
  Dn.AWAKEN = {
    -- the shake: px across / up, swings, frames a swing (60 a second)
    SHAKE = { X = 3, Y = 4, SWINGS = 40, FRAMES = 3 }, SE = "SE_M_EARTHQUAKE",
    WAIT_S = 0.6,   -- outdoors this long first (the warp's fade over)
    -- a watchdog: the shake past SHAKE_MAX_S goes on to the words; the words' box gone this long
    -- without their script ending, the awakening ends (the player never left held)
    SHAKE_MAX_S = 4, QUIET_MAX_S = 3,
    -- (English; the field's message box draws them in the game's font: T.game where shown)
    WORDS = {
      T.mark("A powerful force shakes the region..."),
      T.mark("Pillars of light are rising from\nPOKéMON DENS along the routes!"),
    },
  }
  Dn.OUTDOOR_TYPES = { [1] = true, [2] = true, [3] = true, [6] = true }

  function Dn.awake() return mod.save:get("densAwake") == true end
  -- (drivers) awake or not, without the shake
  function Dn.setAwake(on) mod.save:set("densAwake", on and true or nil) end

  local function outdoors(mapId, def)
    if type(mapId) ~= "string" then return false end
    local mt = def and tonumber(def.mapType)
    if mt then return Dn.OUTDOOR_TYPES[mt] == true end
    return mapId:find("ROUTE", 1, true) ~= nil or mapId:find("TOWN", 1, true) ~= nil or mapId:find("CITY", 1, true) ~= nil
  end

  -- whether the field is free: nothing locking the player, no menu or message up
  local function fieldFree()
    local Field = engine("src.core.game3.field")
    local Stack = engine("src.ui.game3.stack")
    local Message = engine("src.ui.game3.message")
    if Field and Field.isLocked and Field.isLocked() then return false end
    if Stack and Stack.busy and Stack.busy() then return false end
    if Message and Message.isOpen and Message.isOpen() then return false end
    return true
  end

  -- each field step: the awakening, when it is due (the first badge, outdoors, the field free)
  local outsideFor = 0
  local watch = nil   -- the awakening under way: { stage = "shake" | "words", t, quiet, words, finish }
  -- the awakening's watchdog, each field step while it runs
  local function watchAwaken(dt)
    local w = watch
    if not w then return end
    local A = Dn.AWAKEN
    w.t = w.t + dt
    if w.stage == "shake" and w.t > A.SHAKE_MAX_S then
      mod.log:warn("dens: the awakening's shake did not finish; going on to its words")
      w.words()
    elseif w.stage == "words" then
      local Message = engine("src.ui.game3.message")
      local open = Message and Message.isOpen and Message.isOpen()
      w.quiet = open and 0 or (w.quiet + dt)
      if w.quiet > A.QUIET_MAX_S then
        mod.log:warn("dens: the awakening's words never ended; the player let go")
        w.finish()
      end
    end
  end
  function Dn.stepAwaken(dt)
    if Dn.awakening then watchAwaken(dt or 1 / 60); return end
    if Dn.awake() or mod.options:get("dens") == false then return end
    local M = engine("src.core.game3.map")
    local mapId = M and M.current
    local def = M and M.currentDef and M.currentDef()
    if not (outdoors(mapId, def) and fieldFree()) then outsideFor = 0; return end
    outsideFor = outsideFor + (dt or 1 / 60)
    if outsideFor < Dn.AWAKEN.WAIT_S then return end
    if Dn.badges() < 1 then return end
    Dn.awaken()
  end

  -- the awakening itself (drivers call it straight)
  function Dn.awaken(onDone)
    if Dn.awakening then return false end
    local Field = engine("src.core.game3.field")
    local FieldView = engine("src.core.game3.field_view")
    local Task = engine("src.core.game3.task")
    local Audio = engine("src.core.game3.audio")
    local A = Dn.AWAKEN
    if Field and Field.lock then
      local okL, err = pcall(Field.lock, "max_raids_awaken")
      if not okL then
        mod.log:warn("dens: the awakening could not hold the player (%s); the dens wake quietly", tostring(err))
        mod.save:set("densAwake", true)
        Dn.pending = true
        if onDone then onDone() end
        return true
      end
    end
    Dn.awakening = true
    local finished = false
    local function finish()
      if finished then return end
      finished, watch = true, nil
      if FieldView then FieldView.cameraPanX, FieldView.cameraPanY = 0, 0 end
      mod.save:set("densAwake", true)
      Dn.awakening = false
      if Field and Field.unlock then pcall(Field.unlock, "max_raids_awaken") end
      Dn.pending = true
      if onDone then onDone() end
    end
    local spoken = false
    local function words()
      if spoken then return end
      spoken = true
      if watch then watch.stage, watch.quiet = "words", 0 end
      if FieldView then FieldView.cameraPanX, FieldView.cameraPanY = 0, 0 end
      local rows = {}
      for _, t in ipairs(A.WORDS) do rows[#rows + 1] = { "text", T.game(t) } end
      local ok, err = mod.world:queueScript(rows, { onDone = function() finish() end })
      if not ok then
        mod.log:warn("dens: the awakening's words could not show: %s", tostring(err))
        finish()
      end
    end
    watch = { stage = "shake", t = 0, quiet = 0, words = words, finish = finish }
    if Audio and Audio.playSe then pcall(Audio.playSe, A.SE) end
    if not (FieldView and Task and Task.spawn) then words(); return true end
    local S = A.SHAKE
    local frame, left, cx, cy = 0, S.SWINGS, S.X, S.Y
    Task.spawn(function()
      frame = frame + 1
      -- (the watchdog went on without it)
      if spoken then return true end
      if frame % S.FRAMES == 0 then
        left = left - 1
        cx, cy = -cx, -cy
        -- (it eases off over its last third)
        local k = math.min(1, left / (S.SWINGS / 3))
        FieldView.cameraPanX, FieldView.cameraPanY = floor(cx * k + 0.5), floor(cy * k + 0.5)
        if left <= 0 then
          FieldView.cameraPanX, FieldView.cameraPanY = 0, 0
          words()
          return true
        end
      end
      return false
    end)
    return true
  end

  -- a den done (won, or the day's raid used): its look turns quiet
  function Dn.finish(den)
    den.done = true
    -- (another mod's den: its own saved day; one opened for a single raid: nothing to keep)
    if den.ext and den.ext.key and extByKey[den.ext.key] == den then extStore(den)
    elseif den.transient then return
    else mod.save:set("dens", saved()) end
    Dn.ensure()
  end

  -- the den an object id belongs to
  function Dn.byObject(id)
    for key, oid in pairs(extSpawned) do
      if oid == id and extByKey[key] then return extByKey[key], extByKey[key].map, key end
    end
    for mapId, ids in pairs(spawned) do
      for i, oid in pairs(ids) do
        if oid == id then
          local list = saved()[mapId]
          return list and list[i], mapId, i
        end
      end
    end
    return nil
  end

  -- ------- the art (registered at load)

  function Dn.registerSprites()
    local reg = mod.content and mod.content.sprites
    if not reg then return false end
    local base = (mod.path or "mods/max_raids") .. "/assets/den/"
    local function one(id, file)
      local ok, err = pcall(reg.register, reg, id, { image = base .. file, frames = 1,
        frameWidth = Dn.SIZE, frameHeight = Dn.SIZE, anchorX = Dn.SIZE / 2, anchorY = Dn.ANCHOR_Y })
      if not ok then mod.log:warn("den sprite %s not registered: %s", id, tostring(err)) end
    end
    for kind, id in pairs(Dn.SPRITE) do one(id, "den_" .. kind .. ".png") end
    return true
  end

  -- ------- the beam over an active den: a field actor (drawn in the field's own pass, world px)

  local beams = {}
  local NONE = {}
  -- the beam's columns: a unit-square strip fading in over its foot's FOOT px (out of the pit), whole
  -- up to FADE of its height and fading out to its top (vertex colours; the draw's colour tints
  -- it). Made once, at the first draw
  Dn.BEAM = { H = 160, FADE = 0.45, FOOT = 7 }
  local beamMesh
  local function beamColumn(G, x, y, w, h)
    if beamMesh == nil then
      local f = 1 - Dn.BEAM.FADE
      local g = 1 - Dn.BEAM.FOOT / Dn.BEAM.H
      local ok, m = pcall(G.newMesh, {
        { 0, 0, 0, 0, 1, 1, 1, 0 }, { 1, 0, 1, 0, 1, 1, 1, 0 },
        { 0, f * 0.5, 0, 0, 1, 1, 1, 0.35 }, { 1, f * 0.5, 1, 0, 1, 1, 1, 0.35 },
        { 0, f, 0, 0, 1, 1, 1, 1 }, { 1, f, 1, 0, 1, 1, 1, 1 },
        { 0, g, 0, 1, 1, 1, 1, 1 }, { 1, g, 1, 1, 1, 1, 1, 1 },
        { 0, 1, 0, 1, 1, 1, 1, 0 }, { 1, 1, 1, 1, 1, 1, 1, 0 },
      }, "strip", "static")
      beamMesh = ok and m or false
    end
    if beamMesh then
      G.draw(beamMesh, x, y, 0, w, h)
    else
      G.rectangle("fill", x, y, w, h)
    end
  end
  -- the beams' looks: red (a Dynamax Pokemon), purple (the rare beam, a Gigantamax one); another
  -- mod's den its own (src/raid_api.lua: these fields, over red's). color the glow, core the column's
  -- heart, spark the sparks rising in it; height px, width a factor on the glow's, sparks how many,
  -- flicker how much it flickers (0 steady)
  Dn.BEAM_STYLE = {
    red = { color = { 1, 0.2, 0.35 }, core = { 1, 0.92, 0.95 }, spark = { 1, 0.95, 0.95 }, height = 160, width = 1,
      sparks = 10, flicker = 1 },
    purple = { color = { 0.8, 0.35, 1 }, core = { 1, 0.92, 0.95 }, spark = { 1, 0.95, 0.95 }, height = 160, width = 1,
      sparks = 10, flicker = 1 },
  }
  local function beamActor(key, den, i)
    local a = beams[key]
    if not a then
      a = { kind = "max_raids_beam", i = 92000 + i, elevation = 3, oamPriority = 1 }
      a.draw = function(self, camX, camY)
        local G = love and love.graphics
        if not G then return end
        Dn.beamDraws = (Dn.beamDraws or 0) + 1
        local st = self.style
        local t = love.timer and love.timer.getTime() or 0
        local x = floor(self.x + 8 - camX)
        -- from inside the pit, the tile's middle
        local y = floor(self.y + 8 - camY)
        local c, core, sp = st.color, st.core, st.spark
        local pr, pg, pb, pa = G.getColor()
        local hgt = st.height
        -- a soft glow round the column, then its body, then a white-hot core, flickering; each
        -- fades out toward its top
        local flick = 1 - 0.15 * st.flicker + 0.15 * st.flicker * math.sin(t * 9)
        for k = 0, 3 do
          local w = (9 - k * 2 + math.sin(t * 5 + k) * 0.5) * st.width
          G.setColor(c[1], c[2], c[3], (0.14 + 0.1 * k) * flick)
          beamColumn(G, x - w, y - hgt, w * 2, hgt)
        end
        G.setColor(core[1], core[2], core[3], 0.85 * flick)
        beamColumn(G, x - st.width, y - hgt, 2 * st.width, hgt)
        -- sparks rising in it
        for k = 1, st.sparks do
          local u = (t * 0.35 + k * 0.137) % 1
          G.setColor(sp[1], sp[2], sp[3], 0.8 * (1 - u))
          G.rectangle("fill", x - floor(4 * st.width) + ((k * 37) % floor(9 * st.width + 0.5)), y - u * hgt, 1, 2)
        end
        G.setColor(pr, pg, pb, pa)
      end
      beams[key] = a
    end
    a.x, a.y, a.sortY, a.stars = den.x * 16, den.y * 16, den.y * 16 + 15.5, den.stars
    if den.beamStyle then
      a.style = den.beamStyle
    else
      -- (a den rolled before beams told the two apart: by its boss)
      local rare = den.rare
      if rare == nil then rare = not (type(den.boss) == "string" and den.boss:sub(1, 5) == "DYNA:") end
      a.style = rare and Dn.BEAM_STYLE.purple or Dn.BEAM_STYLE.red
    end
    a.rare = a.style == Dn.BEAM_STYLE.purple
    return a
  end

  -- ------- hooks

  function Dn.install()
    -- A on a den
    mod.hooks:wrap("world.talk", function(next, game, eo)
      local id = eo and eo.def and eo.def.id
      local den = id and Dn.byObject(id)
      if den then
        if deps.open then pcall(deps.open, den) end
        return
      end
      return next(game, eo)
    end)
    -- the beams: added to the field's actors each frame (engine internals)
    local FieldEffects = engine("src.core.game3.field_effects")
    if FieldEffects and type(FieldEffects.collectActors) == "function" and not FieldEffects._maxRaidsWrapped then
      local orig = FieldEffects.collectActors
      FieldEffects.collectActors = function(actors, camX, camY, ...)
        orig(actors, camX, camY, ...)
        -- (require, not package.loaded: a mod's package.loaded is not the engine's)
        local M = engine("src.core.game3.map")
        local mapId = M and M.current
        local list = mapId and spawned[mapId] and saved()[mapId] or nil
        local ext = mapId and extMaps[mapId] or nil
        if ext and #ext == 0 then ext = nil end
        if (list or ext) and type(actors) == "table" then
          -- the engine's grass cover over an object's lower half: never over a den, whose
          -- sprite fills its tile
          local n = #actors
          local j = 0
          for k = 1, n do
            local a = actors[k]
            local keep = true
            if type(a) == "table" and a.kind == "field_effect_npc_grass" and a.x and a.y then
              local cx, cy = floor(a.x / 16), floor(a.y / 16)
              for _, den in ipairs(list or NONE) do
                if den.x == cx and den.y == cy then
                  keep = false
                  break
                end
              end
              for _, den in ipairs(keep and ext or NONE) do
                if den.x == cx and den.y == cy and extSpawned[den.ext.key] then
                  keep = false
                  break
                end
              end
            end
            if keep then
              j = j + 1
              actors[j] = a
            end
          end
          for k = j + 1, n do actors[k] = nil end
          for i, den in ipairs(list or NONE) do
            if Dn.isLive(den) then
              actors[#actors + 1] = beamActor(mapId .. ":" .. i, den, i)
            end
          end
          -- (another mod's: beam = false draws none)
          for i, den in ipairs(ext or NONE) do
            if den.beamStyle ~= false and Dn.isLive(den) and extSpawned[den.ext.key] then
              actors[#actors + 1] = beamActor("x:" .. den.ext.key, den, 500 + i)
            end
          end
        end
      end
      FieldEffects._maxRaidsWrapped = true
    end
    -- the dens appear on entering a route (and after a load, once the field runs)
    if mod.events and mod.events.on then
      mod.events:on("map.entered", function() Dn.pending = true end)
    end
    Dn.pending = true
    mod.hooks:wrap("input.step", function(next, game, dt, ...)
      local res = next(game, dt, ...)
      do
        local ok, err = pcall(Dn.stepAwaken, tonumber(dt))
        if not ok then mod.log:warn("dens: the awakening: %s", tostring(err)) end
      end
      if Dn.pending then
        local ok, done = pcall(Dn.ensure)
        if not ok then mod.log:warn("dens: %s", tostring(done)) Dn.pending = false
        elseif done ~= nil then Dn.pending = false end
      end
      return res
    end)
  end

  return Dn
end
