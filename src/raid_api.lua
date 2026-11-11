-- The raid API: other mods' own raids (docs/RAID_API.md). A mod connects (Api.connect(mod) -> a
-- handle named for its id) and then, through the handle:
--   h:boss(name, spec) -> key       a boss of its own: any species (the game's sprite, Dynamaxed red),
--                                   one of the pack's forms, or its own animated sheet; its stars,
--                                   level, moves, ability, nature, IVs, held item, shininess, HP,
--                                   catch, music, script, turns and knock-outs
--   h:den(id, def) / h:setDen / h:removeDen / h:denState
--                                   a den where it likes on any map (src/dens.lua): its beam's look,
--                                   its sprites, its boss (or a function choosing one each day), its
--                                   rewards and its ending
--   h:open(keyOrSpec, opts)         a raid now (a script, an item, a person), its den screen or not
--   h:check(key)                    whether a boss resolves (once the game's data is up)
-- Every call returns its value or true, or nil, code, message; none throws. A boss's key is
-- "EXT:<mod id>:<name>": Bosses[key] / Sprites[key] answer for it (built at its first use, when
-- the game's species and moves are known), so the rest of the raid reads it as any other.
--   Api = raidApi(mod, { N, Bosses, Sprites, Dyna, Battle, Rewards, Gmax })
--   Api.install() ; Api.connect(modOrId, opts) ; Api.supports(name) ; Api.started(info, ext) ;
--   Api.ended(info, ext) ; Api.dens / Api.raid set by main once built

return function(mod, deps)
  local Bosses, Sprites = deps.Bosses, deps.Sprites
  local R = deps.N and deps.N.RAID or {}
  local floor = math.floor
  local Api = { VERSION = "1.0.0", PREFIX = "EXT:" }
  Api.CAPS = { bosses = true, dens = true, open = true, art = true, rewards = true, events = true }

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  local entries = {}      -- [key] = { key, mod, name, spec, read, rec, sp, why }
  local handles = {}      -- [mod id] = handle

  local function fail(code, msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    return nil, code, msg
  end
  local function isInt(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
  local function isNum(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end
  local function okName(s) return type(s) == "string" and #s >= 1 and #s <= 48 and s:match("^[%w_%-]+$") ~= nil end
  local function shallow(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
  end

  -- ------- the boss's spec, checked for its shape at once (the game's data may not be up yet:
  -- species, moves and items are checked when it is first used, or by h:check)

  local MUSIC = { basic = true, max = true, legend = true }
  local IV_KEYS = { hp = true, atk = true, def = true, spe = true, spa = true, spd = true }
  local function checkSpec(spec)
    if type(spec) ~= "table" then return fail("bad_spec", "the boss's spec must be a table") end
    local n = (spec.species ~= nil and 1 or 0) + (spec.form ~= nil and 1 or 0)
    if n ~= 1 then return fail("bad_species", "give a species, or one of the pack's forms (form), not both") end
    if spec.species ~= nil and not (okName(spec.species) or isInt(spec.species, 1, 2000)) then
      return fail("bad_species", "species: an id (\"PIKACHU\", \"RATICATE_ALOLA\") or a National Dex number")
    end
    if spec.form ~= nil then
      local b, sp = rawget(Bosses, spec.form), rawget(Sprites, spec.form)
      if type(spec.form) ~= "string" or type(b) ~= "table" or type(sp) ~= "table" then
        return fail("bad_form", "form: one of Galar Rising's pack keys (exports.bosses()), not %s", tostring(spec.form))
      end
      if spec.art ~= nil then return fail("bad_art", "art goes with a species, not a form") end
    end
    if spec.stars ~= nil and not isInt(spec.stars, 1, 5) then return fail("bad_stars", "stars: 1 to 5") end
    if spec.species ~= nil and spec.stars == nil then return fail("bad_stars", "stars: 1 to 5 (needed with a species)") end
    if spec.level ~= nil and not isInt(spec.level, 1, 100) then return fail("bad_level", "level: 1 to 100") end
    if spec.name ~= nil and (type(spec.name) ~= "string" or #spec.name == 0 or #spec.name > 24) then
      return fail("bad_name", "name: up to 24 characters")
    end
    if spec.moves ~= nil then
      if type(spec.moves) ~= "table" or #spec.moves < 1 or #spec.moves > 4 then return fail("bad_move", "moves: 1 to 4 of them") end
      for _, m in ipairs(spec.moves) do
        if not (type(m) == "string" or isInt(m, 1, 5000)) then return fail("bad_move", "a move: its name (\"THUNDERBOLT\") or number") end
      end
    end
    if spec.ability ~= nil and not (type(spec.ability) == "string" and spec.ability:match("^[%a_ %-']+$")) then
      return fail("bad_ability", "ability: its name (\"PRESSURE\")")
    end
    if spec.nature ~= nil and not (deps.Battle and deps.Battle.natureId and deps.Battle.natureId(spec.nature)) then
      return fail("bad_nature", "nature: its name (\"TIMID\") or 0 to 24")
    end
    if spec.ivs ~= nil then
      if type(spec.ivs) == "table" then
        for k, v in pairs(spec.ivs) do
          if not (IV_KEYS[k] and isInt(v, 0, 31)) then return fail("bad_ivs", "ivs: { hp, atk, def, spe, spa, spd } each 0 to 31") end
        end
      elseif not isInt(spec.ivs, 0, 31) then return fail("bad_ivs", "ivs: 0 to 31, or a table by stat") end
    end
    if spec.item ~= nil and not (type(spec.item) == "string" or isInt(spec.item, 1, 5000)) then
      return fail("bad_item", "item: its name (\"LEFTOVERS\") or number")
    end
    if spec.shiny ~= nil and not (type(spec.shiny) == "boolean" or isInt(spec.shiny, 1, 1000000)) then
      return fail("bad_shiny", "shiny: true, false, or the odds (1 in n)")
    end
    if spec.hp ~= nil and not isNum(spec.hp, 0.1, 10) then return fail("bad_hp", "hp: a factor, 0.1 to 10") end
    if spec.catch ~= nil and not (spec.catch == false or spec.catch == "roll" or spec.catch == "sure") then
      return fail("bad_catch", "catch: \"roll\", \"sure\" or false")
    end
    if spec.music ~= nil and not MUSIC[spec.music] then return fail("bad_music", "music: \"basic\", \"max\" or \"legend\"") end
    if spec.script ~= nil and not (R.SCRIPTS and R.SCRIPTS[spec.script]) then
      return fail("bad_script", "script: \"basic\", \"strong\" or \"fierce\"")
    end
    if spec.gmax ~= nil and not (deps.Gmax and deps.Gmax.MOVES and deps.Gmax.MOVES[spec.gmax]) then
      return fail("bad_gmax", "gmax: a G-Max move's id (\"WILDFIRE\")")
    end
    if spec.gmaxFactor ~= nil and type(spec.gmaxFactor) ~= "boolean" then return fail("bad_spec", "gmaxFactor: true or false") end
    if spec.turns ~= nil and not isInt(spec.turns, 1, 99) then return fail("bad_rules", "turns: 1 to 99") end
    if spec.faints ~= nil and not isInt(spec.faints, 1, 99) then return fail("bad_rules", "faints: 1 to 99") end
    if spec.types ~= nil then
      if type(spec.types) ~= "table" or #spec.types < 1 or #spec.types > 2 then return fail("bad_types", "types: one or two type names") end
      for _, t in ipairs(spec.types) do if type(t) ~= "string" then return fail("bad_types", "types: one or two type names") end end
    end
    local art = spec.art
    if art ~= nil then
      if type(art) ~= "table" then return fail("bad_art", "art must be a table") end
      if type(art.sheet) ~= "string" then return fail("bad_art", "art.sheet: the sheet's path in your mod") end
      if not isInt(art.cell, 8, 1024) then return fail("bad_art", "art.cell: a frame's size in px (square), 8 to 1024") end
      if not isInt(art.frames, 1, 400) then return fail("bad_art", "art.frames: 1 to 400") end
      if art.cols ~= nil and not isInt(art.cols, 1, 400) then return fail("bad_art", "art.cols: 1 to 400") end
      if art.speed ~= nil and not isNum(art.speed, 0.1, 60) then return fail("bad_art", "art.speed: frames' length in 1/20 s, 0.1 to 60") end
      if art.height ~= nil and not isNum(art.height, 0.1, 100) then return fail("bad_art", "art.height: metres") end
      for _, k in ipairs({ "shiny", "cry", "icon" }) do
        if art[k] ~= nil and type(art[k]) ~= "string" then return fail("bad_art", "art.%s: a path in your mod", k) end
      end
      if art.cloud ~= nil and art.cloud ~= "red" and art.cloud ~= "pink" then return fail("bad_art", "art.cloud: \"red\" or \"pink\"") end
    end
    return true
  end
  Api.checkSpec = checkSpec

  -- ------- the boss's record, built at its first use

  local function speciesSlot(v)
    local Dy = deps.Dyna
    if not Dy then return nil end
    if type(v) == "string" then return Dy.slotOfId((v:upper():gsub("^SPECIES_", ""))) end
    local Pk = engine("src.core.game3.pokemon")
    if not (Pk and Pk.speciesFromNational) then return nil end
    local ok, s0 = pcall(Pk.speciesFromNational, v)
    if not (ok and tonumber(s0)) then return nil end
    -- (the base form: the engine answers a number with the last form registered)
    local okK, id = pcall(Pk.keyName, s0)
    local slot = okK and type(id) == "string" and Dy.slotOfId(id) or tonumber(s0)
    return Dy.nationalOf(slot) == v and slot or tonumber(s0)
  end

  local function build(e)
    local spec, Dy = e.spec, deps.Dyna
    local rec, sp
    if spec.form then
      rec, sp = shallow(rawget(Bosses, spec.form)), shallow(rawget(Sprites, spec.form))
      rec.form = spec.form
      rec.gmaxFactor = spec.gmaxFactor ~= false
      rec.music = spec.music or "max"
    else
      local slot = speciesSlot(spec.species)
      local id = slot and Dy and Dy.idOf(slot)
      local dkey = id and Dy.key(id, spec.stars)
      local dr, ds = dkey and Dy.record(dkey), dkey and Dy.sprite(dkey)
      if not (dr and ds) then return nil, nil, "bad_species", ("the game has no species %s"):format(tostring(spec.species)) end
      rec, sp = shallow(dr), shallow(ds)
      rec.legend = nil
      rec.gmaxFactor = spec.gmaxFactor == true
      if spec.art then
        local a = spec.art
        rec.dyna = nil
        sp = { art = true, slot = slot, base = ds.base, height = a.height or ds.height, cell = a.cell, frames = a.frames,
          cols = a.cols or a.frames, speed = { a.speed or 2 }, sheet = a.sheet, shinySheet = a.shiny, cryPath = a.cry,
          cry = a.cry ~= nil, iconPath = a.icon, shiny = a.shiny ~= nil, redCloud = a.cloud == "red", read = e.read,
          provider = e.mod }
        rec.music = spec.music or "max"
        -- (no shiny sheet: never shiny, unless the mod says so)
        if not a.shiny and spec.shiny == nil then rec.shiny = false end
      else
        rec.music = spec.music or "basic"
      end
    end
    rec.stars = spec.stars or rec.stars
    rec.name = spec.name or rec.name
    rec.types = spec.types and shallow(spec.types) or rec.types
    if spec.moves then
      rec.moves = {}
      for i, m in ipairs(spec.moves) do
        if deps.Battle and deps.Battle.move and not deps.Battle.move(m, 99, 99) then
          return nil, nil, "bad_move", ("the game has no move %s"):format(tostring(m))
        end
        rec.moves[i] = type(m) == "string" and m:upper():gsub("[%s%-]+", "_") or m
      end
    end
    if spec.item ~= nil then
      local id = deps.Rewards and deps.Rewards.itemOf and deps.Rewards.itemOf(spec.item)
      if not id then return nil, nil, "bad_item", ("the game has no item %s"):format(tostring(spec.item)) end
      rec.item = id
    end
    rec.level, rec.ability, rec.nature, rec.hp = spec.level, spec.ability, spec.nature, spec.hp
    rec.ivs = type(spec.ivs) == "table" and shallow(spec.ivs) or spec.ivs
    if spec.shiny ~= nil then rec.shiny = spec.shiny end
    rec.catch = spec.catch
    if spec.catch == nil then rec.catch = "roll" end
    rec.script = spec.script or rec.script
    rec.gmax = spec.gmax or rec.gmax
    rec.turns, rec.faints = spec.turns, spec.faints
    rec.ext = { mod = e.mod, name = e.name }
    rec.key = e.key
    return rec, sp
  end

  local function resolve(e)
    if e.rec == nil then
      local ok, rec, sp, code, why = pcall(build, e)
      if ok and rec then
        e.rec, e.sp = rec, sp
      else
        e.rec, e.sp = false, false
        e.code, e.why = ok and code or "error", ok and why or tostring(rec)
        mod.log:warn("raid boss %s: %s (%s)", e.key, tostring(e.why), tostring(e.code))
      end
    end
    return e.rec or nil, e.sp or nil
  end

  -- Bosses[key] / Sprites[key] answer for EXT keys (as src/dyna.lua's for DYNA keys)
  function Api.install()
    local function hook(t, which)
      if type(t) ~= "table" then return end
      local mt = getmetatable(t) or {}
      local prev = mt.__index
      mt.__index = function(tbl, k)
        local e = type(k) == "string" and entries[k]
        if e then
          local rec, sp = resolve(e)
          if which == 1 then return rec end
          return sp
        end
        if type(prev) == "function" then return prev(tbl, k) end
        if type(prev) == "table" then return prev[k] end
        return nil
      end
      setmetatable(t, mt)
    end
    hook(Bosses, 1)
    hook(Sprites, 2)
  end

  -- ------- dens

  local function checkColor(c)
    if type(c) ~= "table" then return false end
    for i = 1, 3 do if not isNum(c[i], 0, 1) then return false end end
    return true
  end
  -- a den's beam: nil (red), false (none), "red" / "purple", or fields over red's
  local function beamStyle(beam)
    local Dn = Api.dens
    local base = Dn and Dn.BEAM_STYLE and Dn.BEAM_STYLE.red or {}
    if beam == nil or beam == "red" then return base end
    if beam == false then return false end
    if beam == "purple" then return Dn and Dn.BEAM_STYLE and Dn.BEAM_STYLE.purple or base end
    if type(beam) ~= "table" then return fail("bad_beam", "beam: false, \"red\", \"purple\" or a table of its look") end
    for _, k in ipairs({ "color", "core", "spark" }) do
      if beam[k] ~= nil and not checkColor(beam[k]) then return fail("bad_beam", "beam.%s: { r, g, b }, each 0 to 1", k) end
    end
    if beam.height ~= nil and not isNum(beam.height, 16, 400) then return fail("bad_beam", "beam.height: 16 to 400 px") end
    if beam.width ~= nil and not isNum(beam.width, 0.25, 4) then return fail("bad_beam", "beam.width: 0.25 to 4") end
    if beam.sparks ~= nil and not isInt(beam.sparks, 0, 40) then return fail("bad_beam", "beam.sparks: 0 to 40") end
    if beam.flicker ~= nil and not isNum(beam.flicker, 0, 2) then return fail("bad_beam", "beam.flicker: 0 to 2") end
    local st = {}
    for k, v in pairs(base) do st[k] = v end
    for _, k in ipairs({ "color", "core", "spark" }) do if beam[k] then st[k] = { beam[k][1], beam[k][2], beam[k][3] } end end
    for _, k in ipairs({ "height", "width", "sparks", "flicker" }) do if beam[k] ~= nil then st[k] = beam[k] end end
    return st
  end
  Api.beamStyle = beamStyle

  local function checkRewards(rw)
    if rw == nil then return true end
    if type(rw) ~= "table" then return fail("bad_rewards", "rewards must be a table") end
    if rw.mode ~= nil and rw.mode ~= "add" and rw.mode ~= "replace" then return fail("bad_rewards", "rewards.mode: \"add\" or \"replace\"") end
    if rw.items ~= nil then
      if type(rw.items) ~= "table" then return fail("bad_rewards", "rewards.items: a list of { item, n }") end
      for _, row in ipairs(rw.items) do
        if type(row) ~= "table" or not (type(row[1]) == "string" or isInt(row[1], 1, 5000)) or (row[2] ~= nil and not isInt(row[2], 1, 999)) then
          return fail("bad_rewards", "rewards.items: each { \"ITEM_NAME\" or number, n 1 to 999 }")
        end
      end
    end
    if rw.money ~= nil and not isInt(rw.money, 0, 999999) then return fail("bad_rewards", "rewards.money: 0 to 999999") end
    if rw.roll ~= nil and type(rw.roll) ~= "function" then return fail("bad_rewards", "rewards.roll: a function") end
    return true
  end
  Api.checkRewards = checkRewards

  -- ------- the handle

  local Handle = {}
  Handle.__index = Handle

  -- a boss key a mod may name: its own boss's name, or any key the raid knows (EXT, DYNA, the pack's)
  local function keyOf(h, ref)
    if type(ref) ~= "string" then return nil end
    if entries[ref] then return ref end
    local own = Api.PREFIX .. h.id .. ":" .. ref
    if entries[own] then return own end
    if rawget(Bosses, ref) ~= nil or (deps.Dyna and deps.Dyna.is(ref)) then return ref end
    return nil
  end

  function Handle:boss(name, spec)
    local ok, r1, r2, r3 = pcall(function()
      if not okName(name) then return fail("bad_name", "a boss's name: letters, digits, _ and -, up to 48") end
      local good, code, msg = checkSpec(spec)
      if not good then return nil, code, msg end
      local key = Api.PREFIX .. self.id .. ":" .. name
      local copy = shallow(spec)
      if spec.art then copy.art = shallow(spec.art) end
      if spec.moves then copy.moves = shallow(spec.moves) end
      entries[key] = { key = key, mod = self.id, name = name, spec = copy, read = self.read }
      return key
    end)
    if not ok then return fail("error", tostring(r1)) end
    return r1, r2, r3
  end

  -- whether a boss resolves now (its species, moves, item and art in the game): true, or nil, code, msg
  function Handle:check(ref)
    local key = keyOf(self, ref)
    if not key then return fail("unknown_boss", "no boss %s", tostring(ref)) end
    local e = entries[key]
    if e then
      e.rec, e.sp = nil, nil
      local rec, sp = resolve(e)
      if not rec then return nil, e.code, e.why end
      if sp.art then
        for _, p in ipairs({ sp.sheet, sp.shinySheet, sp.cryPath, sp.iconPath }) do
          local okR, bytes = pcall(sp.read, p)
          if p and not (okR and bytes) then return fail("bad_art", "%s can't be read from %s", p, self.id) end
        end
      end
      return true
    end
    return Bosses[key] and true or fail("unknown_boss", "no boss %s", key)
  end

  local function denKey(h, id) return h.id .. ":" .. id end

  function Handle:den(id, def)
    local ok, r1, r2, r3 = pcall(function()
      local Dn = Api.dens
      if not Dn then return fail("no_dens", "the dens are not running") end
      if not okName(id) then return fail("bad_name", "a den's id: letters, digits, _ and -, up to 48") end
      if type(def) ~= "table" then return fail("bad_spec", "the den's def must be a table") end
      if type(def.map) ~= "string" or def.map == "" then return fail("bad_map", "map: the map's id (\"EM_ROUTE101\")") end
      if not (isInt(def.x, 0, 4095) and isInt(def.y, 0, 4095)) then return fail("bad_cell", "x, y: the den's cell") end
      local boss, bossFn = nil, nil
      if type(def.boss) == "function" then
        local fn, me = def.boss, self
        bossFn = function(ctx)
          local v = fn(ctx)
          if type(v) == "table" then
            local k = me:boss(id .. "_day", v)
            return k
          end
          return keyOf(me, v)
        end
      elseif def.boss ~= nil then
        boss = keyOf(self, def.boss)
        if not boss then return fail("unknown_boss", "boss: a key from h:boss, your boss's name, or a key the raid knows") end
      else
        return fail("unknown_boss", "boss: a key, or a function(ctx) choosing one each day")
      end
      local style, code, msg = beamStyle(def.beam)
      if style == nil then return nil, code, msg end
      if def.sprite ~= nil and not (type(def.sprite) == "table" and type(def.sprite.active) == "string"
        and (def.sprite.spent == nil or type(def.sprite.spent) == "string")) then
        return fail("bad_sprite", "sprite: { active = id, spent = id } of sprites your mod registered")
      end
      if def.refresh ~= nil and def.refresh ~= "daily" and def.refresh ~= "never" then
        return fail("bad_refresh", "refresh: \"daily\" or \"never\"")
      end
      if def.active ~= nil and type(def.active) ~= "boolean" then return fail("bad_spec", "active: true or false") end
      if def.awake ~= nil and type(def.awake) ~= "boolean" then return fail("bad_spec", "awake: true or false") end
      local good, c2, m2 = checkRewards(def.rewards)
      if not good then return nil, c2, m2 end
      if def.onEnd ~= nil and type(def.onEnd) ~= "function" then return fail("bad_spec", "onEnd: a function") end
      local key = denKey(self, id)
      Dn.addExt({ map = def.map, x = def.x, y = def.y, active = def.active ~= false, boss = boss, bossFn = bossFn,
        beamStyle = style, sprite = def.sprite and shallow(def.sprite) or nil, refresh = def.refresh or "daily",
        awake = def.awake == true,
        ext = { key = key, mod = self.id, den = id, rewards = def.rewards, onEnd = def.onEnd } })
      return true
    end)
    if not ok then return fail("error", tostring(r1)) end
    return r1, r2, r3
  end

  -- a change to a den: active, boss, beam, sprite, rewards, onEnd; done = false makes it live again now
  function Handle:setDen(id, patch)
    local ok, r1, r2, r3 = pcall(function()
      local Dn = Api.dens
      if not (Dn and type(id) == "string" and Dn.extDen(denKey(self, id))) then return fail("unknown_den", "no den %s", tostring(id)) end
      if type(patch) ~= "table" then return fail("bad_spec", "the patch must be a table") end
      local out = {}
      for k, v in pairs(patch) do
        if k == "active" or k == "done" then
          if type(v) ~= "boolean" then return fail("bad_spec", "%s: true or false", k) end
          out[k] = v
        elseif k == "boss" then
          local key = keyOf(self, v)
          if not key then return fail("unknown_boss", "no boss %s", tostring(v)) end
          out.boss = key
        elseif k == "beam" then
          local style, code, msg = beamStyle(v)
          if style == nil then return nil, code, msg end
          out.beamStyle = style
        elseif k == "sprite" then
          if not (type(v) == "table" and type(v.active) == "string") then return fail("bad_sprite", "sprite: { active, spent }") end
          out.sprite = shallow(v)
        elseif k == "rewards" then
          local good, code, msg = checkRewards(v)
          if not good then return nil, code, msg end
          out.rewards = v
        elseif k == "onEnd" then
          if v ~= nil and type(v) ~= "function" then return fail("bad_spec", "onEnd: a function") end
          out.onEnd = v
        else
          return fail("bad_spec", "a den's %s can't be changed (remove it and add it again)", tostring(k))
        end
      end
      Dn.updateExt(denKey(self, id), out)
      return true
    end)
    if not ok then return fail("error", tostring(r1)) end
    return r1, r2, r3
  end

  function Handle:removeDen(id)
    local Dn = Api.dens
    if not (Dn and type(id) == "string" and Dn.removeExt(denKey(self, id))) then return fail("unknown_den", "no den %s", tostring(id)) end
    return true
  end

  -- a den's state: { live, active, done, day, boss }
  function Handle:denState(id)
    local Dn = Api.dens
    local den = Dn and type(id) == "string" and Dn.extDen(denKey(self, id))
    if not den then return fail("unknown_den", "no den %s", tostring(id)) end
    return { live = Dn.isLive(den), active = den.active == true, done = den.done == true, day = den.day, boss = den.boss }
  end

  -- a raid now: opts = { denScreen (true: the den screen first), rewards, onEnd }
  function Handle:open(ref, opts)
    local ok, r1, r2, r3 = pcall(function()
      local Rd = Api.raid
      if not Rd then return fail("no_raid", "the raid is not running") end
      opts = opts or {}
      if type(opts) ~= "table" then return fail("bad_spec", "opts must be a table") end
      local key
      if type(ref) == "table" then
        local k, code, msg = self:boss("open", ref)
        if not k then return nil, code, msg end
        key = k
      else
        key = keyOf(self, ref)
      end
      if not key then return fail("unknown_boss", "no boss %s", tostring(ref)) end
      local good, code, msg = checkRewards(opts.rewards)
      if not good then return nil, code, msg end
      if opts.onEnd ~= nil and type(opts.onEnd) ~= "function" then return fail("bad_spec", "onEnd: a function") end
      if Rd.active and Rd.active() then return fail("busy", "a raid is already open") end
      if not (Bosses[key] and Sprites[key]) then
        local e = entries[key]
        return fail(e and e.code or "unknown_boss", e and e.why or ("no boss " .. key))
      end
      local ext = { mod = self.id, rewards = opts.rewards, onEnd = opts.onEnd }
      local opened, why
      if opts.denScreen == false then
        opened, why = Rd.open(key, { ext = ext })
      else
        opened, why = Rd.openDen({ active = true, boss = key, ext = ext, transient = true })
      end
      if not opened then return fail("busy", tostring(why or "the raid could not open")) end
      return true
    end)
    if not ok then return fail("error", tostring(r1)) end
    return r1, r2, r3
  end

  -- ------- connecting

  -- a mod's handle: connect(mod) (its own `mod`: its id and its files), or connect(id, { read =
  -- function(path) -> bytes })
  function Api.connect(m, opts)
    local id, read
    if type(m) == "table" and type(m.id) == "string" then
      id = m.id
      if type(m.read) == "function" then read = function(path) return m:read(path) end end
    elseif type(m) == "string" then
      id = m
    end
    if type(opts) == "table" and type(opts.read) == "function" then read = opts.read end
    if not okName(id) then return fail("bad_mod", "connect(mod): your mod, or its id") end
    local h = handles[id]
    if not h then
      h = setmetatable({ id = id }, Handle)
      handles[id] = h
    end
    h.read = read or function() return nil end
    return h
  end

  function Api.supports(name) return Api.CAPS[name] == true end

  -- the raid's start and end (src/raid.lua): the raid's own mod told, and the events for any mod
  local function emit(name, info)
    if mod.events and mod.events.emit then pcall(mod.events.emit, mod.events, "mod.max_raids." .. name, info) end
  end
  function Api.started(info, ext)
    if info then emit("raid_start", info) end
  end
  function Api.ended(info, ext)
    if not info then return end
    if ext and type(ext.onEnd) == "function" then
      local ok, err = pcall(ext.onEnd, info)
      if not ok then mod.log:warn("raid onEnd of %s failed: %s", tostring(ext.mod), tostring(err)) end
    end
    emit("raid_end", info)
  end

  -- (tests) forget every mod's bosses and handles
  function Api.forget() entries, handles = {}, {} end
  return Api
end
