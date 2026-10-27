-- Max Raid dens on the routes. Each outdoor route gets one or two dens the first time the player is
-- on it, at open spots picked from the map itself (seeded by the save's trainer id and the map, so
-- they come out the same; saved once chosen, so they never move). Each day a den rolls again:
-- active (a boss from the star tiers the badges allow) or quiet. A den is an object of the
-- engine's (mod.world:spawnNpc: drawn and collided like any NPC; not saved, so spawned again
-- after a load); an active one has a beam of light rising from it (a field actor). Pressing A on
-- a den (the world.talk hook) opens it (deps.open(den)).
--   Dn = dens(mod, { N, Bosses, open })
--   Dn.pick(view, seed) -> { {x, y}, ... }   (pure: view = { w, h, open(x, y), warps })
--   Dn.roll(den, day, badges, rng)           (pure: rerolls a den for a day)
--   Dn.ensure() ; Dn.registerSprites() ; Dn.install(hooks) ; Dn.today() ; Dn.badges()

return function(mod, deps)
  local N, Bosses = deps.N, deps.Bosses
  local D = N.RAID.DENS
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs
  local Dn = {}
  -- the den's sprites: active / spent (assets/den/), drawn over grass (no grass in front of it yet)
  Dn.SPRITE = { active = "MAX_RAIDS_DEN", spent = "MAX_RAIDS_DEN_SPENT" }
  -- the sprite's anchor: Gen 3 draws its bottom row on the tile's middle, clear of the engine's grass
  -- cover (the tile's bottom 8 rows); 23 would put it on the tile's foot
  Dn.ANCHOR_Y = 31
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

  -- a den for a new day: active or quiet, its tier and boss (pure)
  function Dn.roll(den, day, badges, rnd)
    den.day = day
    den.done = nil
    den.active = rnd() < D.ACTIVE
    if not den.active then den.stars, den.boss = nil, nil; return den end
    local tiersOk = Dn.starsFor(badges)
    den.stars = tiersOk[rnd(1, #tiersOk)]
    local list = Dn.tier(den.stars)
    den.boss = list[rnd(1, max(1, #list))]
    return den
  end

  -- ------- the engine's side (guarded: headless loads skip it)

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  local function session()
    local R = engine("src.core.game3.runtime")
    return R and R.getSession and R.getSession() or nil
  end

  -- the day number: the cart's clock on Ruby / Sapphire / Emerald, the device's date elsewhere
  function Dn.today()
    local Rtc = engine("src.core.game3.rtc")
    local s = session()
    if Rtc and Rtc.enabled and s and Rtc.enabled(s) and Rtc.calcLocalTime then
      local ok, t = pcall(Rtc.calcLocalTime, s)
      if ok and type(t) == "table" and tonumber(t.days) then return tonumber(t.days) end
    end
    local info = Rtc and Rtc.hostInfo and select(2, pcall(Rtc.hostInfo, nil))
    if type(info) == "table" and info.year then
      return floor(os.time({ year = 2000 + info.year, month = info.month, day = info.day, hour = 12 }) / 86400)
    end
    return floor(os.time() / 86400)
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

  local function spriteFor(den)
    return (den.active and not den.done) and Dn.SPRITE.active or Dn.SPRITE.spent
  end
  Dn.spriteFor = spriteFor

  -- the current map's dens: chosen (once), rolled for today, spawned (again after a load); true when
  -- done, false when there is nothing to do here, nil to try again (the field not running yet)
  function Dn.ensure()
    if mod.options:get("dens") == false then return false end
    -- (none until the region has awoken: the first badge, then Dn.awaken's shake and words)
    if not Dn.awake() then return false end
    local M = engine("src.core.game3.map")
    local mapId = M and M.current
    local def = M and M.currentDef and M.currentDef()
    if not (mapId and def and isRoute(mapId, def)) then return false end
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
        Dn.roll(den, today, badges, Dn.rng(seedOf(tostring(trainerId()) .. ":" .. mapId .. ":" .. i .. ":" .. today)))
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
    WORDS = {
      "A powerful force shakes the region...",
      "Pillars of light are rising from\nPOKéMON DENS along the routes!",
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
  function Dn.stepAwaken(dt)
    if Dn.awake() or Dn.awakening or mod.options:get("dens") == false then return end
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
    Dn.awakening = true
    if Field and Field.lock then Field.lock("max_raids_awaken") end
    local function finish()
      mod.save:set("densAwake", true)
      Dn.awakening = false
      if Field and Field.unlock then pcall(Field.unlock, "max_raids_awaken") end
      Dn.pending = true
      if onDone then onDone() end
    end
    local function words()
      local rows = {}
      for _, t in ipairs(A.WORDS) do rows[#rows + 1] = { "text", t } end
      local ok, err = mod.world:queueScript(rows, { onDone = function() finish() end })
      if not ok then
        mod.log:warn("dens: the awakening's words could not show: %s", tostring(err))
        finish()
      end
    end
    if Audio and Audio.playSe then pcall(Audio.playSe, A.SE) end
    if not (FieldView and Task and Task.spawn) then words(); return true end
    local S = A.SHAKE
    local frame, left, cx, cy = 0, S.SWINGS, S.X, S.Y
    Task.spawn(function()
      frame = frame + 1
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
    mod.save:set("dens", saved())
    Dn.ensure()
  end

  -- the den an object id belongs to
  function Dn.byObject(id)
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
        frameWidth = 32, frameHeight = 32, anchorX = 16, anchorY = Dn.ANCHOR_Y })
      if not ok then mod.log:warn("den sprite %s not registered: %s", id, tostring(err)) end
    end
    for kind, id in pairs(Dn.SPRITE) do one(id, "den_" .. kind .. ".png") end
    return true
  end

  -- ------- the beam over an active den: a field actor (drawn in the field's own pass, world px)

  local beams = {}
  local function beamActor(mapId, den, i)
    local key = mapId .. ":" .. i
    local a = beams[key]
    if not a then
      a = { kind = "max_raids_beam", i = 92000 + i, elevation = 3, oamPriority = 1 }
      a.draw = function(self, camX, camY)
        local G = love and love.graphics
        if not G then return end
        Dn.beamDraws = (Dn.beamDraws or 0) + 1
        local t = love.timer and love.timer.getTime() or 0
        local x = floor(self.x + 8 - camX)
        -- from the pit, 11 px above the den's foot (the tile's middle)
        local y = floor(self.y - 3 - camY)
        local hot = (self.stars or 1) >= 3
        local cr, cg, cb = hot and 1 or 0.8, hot and 0.2 or 0.35, hot and 0.35 or 1
        local pr, pg, pb, pa = G.getColor()
        local hgt = 160
        -- a soft glow round the column, then its body, then a white-hot core, flickering
        local flick = 0.85 + 0.15 * math.sin(t * 9)
        for k = 0, 3 do
          local w = 9 - k * 2 + math.sin(t * 5 + k) * 0.5
          G.setColor(cr, cg, cb, (0.14 + 0.1 * k) * flick)
          G.rectangle("fill", x - w, y - hgt, w * 2, hgt)
        end
        G.setColor(1, 0.92, 0.95, 0.85 * flick)
        G.rectangle("fill", x - 1, y - hgt, 2, hgt)
        -- sparks rising in it
        for k = 1, 10 do
          local u = (t * 0.35 + k * 0.137) % 1
          G.setColor(1, 0.95, 0.95, 0.8 * (1 - u))
          G.rectangle("fill", x - 4 + ((k * 37) % 9), y - u * hgt, 1, 2)
        end
        G.setColor(pr, pg, pb, pa)
      end
      beams[key] = a
    end
    a.x, a.y, a.sortY, a.stars = den.x * 16, den.y * 16, den.y * 16 + 15.5, den.stars
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
        local list = mapId and spawned[mapId] and saved()[mapId]
        if list then
          for i, den in ipairs(list) do
            if den.active and not den.done and type(actors) == "table" then
              actors[#actors + 1] = beamActor(mapId, den, i)
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
