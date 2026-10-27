-- The raid's battle on the engine: the battlers (the four as deep copies of the party's Pokemon, the
-- boss from the Giga Megas pack's stats at its tier's level), the moves (the engine's records, the
-- National Dex's among them), and the maths the simulation asks for - the engine's own damage
-- (Damage.calc with an adapter, so the National Dex's abilities and move rules apply), Gen 3
-- accuracy and speed, effectiveness, and what a move does besides its damage (by its Gen 3 effect).
-- src/raid_sim.lua runs the turns over this; nothing here touches the save.
--   Bt = battle(mod, { N, Bosses, Sprites, Gmax, dex })   dex() -> national_dex_gen3's exports (moveExtra);
--   Gmax = data/raid_gmax.lua
--   Bt.member(mon) -> battler ; Bt.boss(key, rng) -> battler ; Bt.adapter(rng) -> the sim's adapter
--   Bt.TYPE_RGB[name] ; Bt.typeName(num)

return function(mod, deps)
  local N, Bosses, Sprites, Gmax = deps.N, deps.Bosses, deps.Sprites, deps.Gmax or { MOVES = {}, POWER_BANDS = {} }
  local TeamMoves = deps.TeamMoves or { MOVES = {} }
  local R = N.RAID
  local floor, max, min = math.floor, math.max, math.min
  local Bt = {}

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local Damage = engine("src.core.game3.battle.damage")
  local Moves = engine("src.core.game3.battle.moves")
  local Types = engine("src.core.game3.battle.types")
  local State = engine("src.core.game3.battle.state")
  local AdapterMod = engine("src.core.game3.battle.adapter")
  local Rules = engine("src.core.game3.battle.rules")
  local EffectIds = engine("src.core.game3.battle.effect_ids")
  local Pokemon = engine("src.core.game3.pokemon")
  local Progression = engine("src.core.game3.progression")
  local HeldItems = engine("src.core.game3.battle.held_items")

  -- ------- types

  Bt.TYPE_NAMES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
    "MYSTERY", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }
  -- the types' colours (the modern games')
  Bt.TYPE_RGB = {
    NORMAL = { 0.62, 0.62, 0.55 }, FIGHTING = { 0.8, 0.27, 0.22 }, FLYING = { 0.55, 0.62, 0.95 },
    POISON = { 0.62, 0.33, 0.7 }, GROUND = { 0.85, 0.7, 0.4 }, ROCK = { 0.72, 0.64, 0.33 },
    BUG = { 0.6, 0.72, 0.15 }, GHOST = { 0.43, 0.35, 0.6 }, STEEL = { 0.6, 0.65, 0.74 },
    MYSTERY = { 0.45, 0.6, 0.6 }, FIRE = { 0.95, 0.5, 0.2 }, WATER = { 0.3, 0.55, 0.95 },
    GRASS = { 0.4, 0.75, 0.3 }, ELECTRIC = { 0.97, 0.8, 0.15 }, PSYCHIC = { 0.97, 0.35, 0.52 },
    ICE = { 0.45, 0.82, 0.85 }, DRAGON = { 0.42, 0.3, 0.95 }, DARK = { 0.42, 0.33, 0.28 },
    FAIRY = { 0.93, 0.55, 0.75 },
  }
  function Bt.typeName(num) return Bt.TYPE_NAMES[tonumber(num) or 0] or "NORMAL" end
  function Bt.typeNum(name)
    if Progression and Progression.typeIndexFor then
      local ok, n = pcall(Progression.typeIndexFor, name)
      if ok and tonumber(n) then return tonumber(n) end
    end
    for k, v in pairs(Bt.TYPE_NAMES) do if v == name then return k end end
    return 0
  end

  -- "AIR SLASH" -> "Air Slash"
  local function titled(s)
    s = tostring(s or ""):gsub("_", " "):lower()
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  Bt.titled = titled

  -- ------- moves

  -- the effect ids by name (the engine's table) and back
  local EFFECT_NAME = {}
  for name, id in pairs(EffectIds or {}) do if type(id) == "number" then EFFECT_NAME[id] = name end end
  local STAT_KEY = { ATTACK = "attack", DEFENSE = "defense", SPEED = "speed", SPECIAL_ATTACK = "spAtk",
    SPECIAL_DEFENSE = "spDef", ACCURACY = "accuracy", EVASION = "evasion" }
  local MAJOR = { SLEEP = "SLP", TOXIC = "TOX", POISON = "PSN", PARALYZE = "PAR", WILL_O_WISP = "BRN" }
  local MAJOR_HIT = { POISON_HIT = "PSN", BURN_HIT = "BRN", FREEZE_HIT = "FRZ", PARALYZE_HIT = "PAR" }
  local MULTI_UP = {
    BULK_UP = { attack = 1, defense = 1 }, CALM_MIND = { spAtk = 1, spDef = 1 },
    DRAGON_DANCE = { attack = 1, speed = 1 }, COSMIC_POWER = { defense = 1, spDef = 1 },
  }

  -- what a move does besides its damage, from its Gen 3 effect:
  --   { stages = { [stat] = n }, self = true (stages on the user), status = "PAR", chance = 0..100,
  --     heal = share }
  local function sideOf(effect, chance)
    local name = EFFECT_NAME[tonumber(effect) or -1]
    if not name then return nil end
    if MULTI_UP[name] then return { stages = MULTI_UP[name], self = true } end
    if MAJOR[name] then return { status = MAJOR[name] } end
    if MAJOR_HIT[name] then return { status = MAJOR_HIT[name], chance = chance } end
    if name == "RESTORE_HP" then return { heal = 0.5, self = true } end
    -- a stat raised or lowered: NAME_UP / _DOWN (one stage), _UP_2 / _DOWN_2 (two), and
    -- NAME_UP_HIT / _DOWN_HIT (an attack's chance of one stage)
    local function cut(suffix)
      if name:sub(-#suffix) == suffix then return name:sub(1, -#suffix - 1) end
      return nil
    end
    for _, row in ipairs({ { "_UP_HIT", 1, true }, { "_DOWN_HIT", -1, true }, { "_UP_2", 2 }, { "_DOWN_2", -2 },
      { "_UP", 1 }, { "_DOWN", -1 } }) do
      local stat = cut(row[1])
      if stat and STAT_KEY[stat] then
        return { stages = { [STAT_KEY[stat]] = row[2] }, self = row[2] > 0, chance = row[3] and chance or nil }
      end
    end
    return nil
  end
  Bt.sideOf = sideOf

  -- a newer move's extra as the National Dex carries it out (its exports.moveExtra) -> a side:
  --   foeStages / selfStages, status (+ statusChance), chance (the stat changes'), heal, drain (% of
  --   the damage dealt; negative = recoil)
  local AILMENT = { BURN = "BRN", FREEZE = "FRZ", PARALYSIS = "PAR", POISON = "PSN", SLEEP = "SLP", TOXIC = "TOX" }
  local function extraSide(e)
    if type(e) ~= "table" then return nil end
    local s = {}
    if type(e.foe) == "table" and next(e.foe) then s.foeStages = e.foe end
    if type(e.self) == "table" and next(e.self) then s.selfStages = e.self end
    if e.ailment and AILMENT[e.ailment] then s.status, s.statusChance = AILMENT[e.ailment], tonumber(e.ailmentChance) end
    if tonumber(e.chance) and tonumber(e.chance) < 100 then s.chance = tonumber(e.chance) end
    if tonumber(e.heal) and (e.healTarget or "self") == "self" then s.heal = tonumber(e.heal) / 100; s.self = true end
    if tonumber(e.drain) then s.drain = tonumber(e.drain) end
    -- (a status move touching only its user goes on the user)
    if e.kind == "status" and s.selfStages and not s.foeStages and not s.status then s.self = true end
    if not next(s) then return nil end
    return s
  end
  Bt.extraSide = extraSide
  local function dexExtra(m)
    local dex = deps.dex and deps.dex()
    if not (dex and dex.moveExtra) then return nil end
    local ok, e = pcall(dex.moveExtra, m.numId or m.id)
    if not (ok and e) then ok, e = pcall(dex.moveExtra, m.id) end
    return ok and e or nil
  end

  Bt.ALIAS = { HIGH_JUMP_KICK = "HI_JUMP_KICK" }

  -- a move as the simulation and the menu use it (nil when the game has no such move)
  local SPREAD = 8 + 32       -- MOVE_TARGET_BOTH | MOVE_TARGET_FOES_AND_ALLY
  local bitlib = rawget(_G, "bit")
  if not bitlib then
    local ok, b = pcall(require, "bit")
    bitlib = ok and b or nil
  end
  function Bt.move(ref, pp, maxPp)
    if not Moves then return nil end
    -- (later names for Gen 3 moves)
    if type(ref) == "string" and Bt.ALIAS[ref] then ref = Bt.ALIAS[ref] end
    local ok, m = pcall(Moves.get, ref)
    -- (the game's own names run some words together: ANCIENTPOWER)
    if not (ok and type(m) == "table") and type(ref) == "string" and ref:find("_") then
      ok, m = pcall(Moves.get, (ref:gsub("_", "")))
    end
    if not (ok and type(m) == "table") then return nil end
    local name = m.id
    if Moves.displayName then
      local okN, n = pcall(Moves.displayName, m.numId or ref)
      if okN and type(n) == "string" and not n:find("^%-+$") then name = n end
    end
    local power = tonumber(m.power) or 0
    local key = type(ref) == "string" and ref:upper() or (type(m.id) == "string" and m.id:upper():gsub(" ", "_") or nil)
    return {
      ref = m, num = m.numId, name = titled(name), type = tonumber(m.type) or 0,
      key = key, team = key and TeamMoves.MOVES[Bt.squash(key)] or nil,
      contact = bitlib and bitlib.band(tonumber(m.flags) or 0, 1) ~= 0 or false,
      typeName = Bt.typeName(m.type), power = power, accuracy = tonumber(m.accuracy) or 0,
      priority = tonumber(m.priority) or 0, status = power == 0,
      spread = bitlib and (bitlib.band(tonumber(m.target) or 0, SPREAD) ~= 0) or false,
      -- (MOVE_TARGET_FOES_AND_ALLY, or Sword / Shield's all-adjacent list: Surf, Earthquake ... strike the
      -- user's allies too)
      friendly = (bitlib and bitlib.band(tonumber(m.target) or 0, 32) ~= 0)
        or (key ~= nil and TeamMoves.FRIENDLY ~= nil and TeamMoves.FRIENDLY[Bt.squash(key)] == true) or false,
      side = extraSide(dexExtra(m)) or sideOf(m.effect, tonumber(m.secondaryChance) or 0),
      pp = pp or tonumber(m.pp) or 10, maxPp = maxPp or tonumber(m.pp) or 10,
    }
  end

  -- ------- battlers

  local function deepCopy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do c[k] = deepCopy(v, seen) end
    return setmetatable(c, getmetatable(t))
  end
  Bt.copy = deepCopy

  local function typesOf(species)
    if Pokemon and Pokemon.types then
      local ok, t = pcall(Pokemon.types, species)
      if ok and type(t) == "table" then return t[1], t[2] end
    end
    return 0, nil
  end

  -- one of the four: a deep copy of the party's Pokemon (the save is never touched)
  function Bt.member(mon)
    local copy = deepCopy(mon)
    local b
    if State and State.makeBattler then
      local ok, made = pcall(State.makeBattler, copy, "player", { id = 0 })
      if ok and type(made) == "table" then b = made end
    end
    if not b then
      local species = Pokemon and Pokemon.speciesOf and select(2, pcall(Pokemon.speciesOf, copy)) or copy.species
      local t1, t2 = typesOf(species)
      b = { mon = copy, species = species, type1 = t1, type2 = t2 ~= t1 and t2 or nil, side = "player",
        stages = { attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0, accuracy = 0, evasion = 0 },
        status = copy.status }
    end
    b.side = "player"
    b.name = "?"
    if Pokemon and Pokemon.displayName then
      local ok, n = pcall(Pokemon.displayName, copy)
      if ok and type(n) == "string" then b.name = titled(n) end
    end
    b.status = (type(b.status) == "string" and b.status ~= "" and b.status ~= "NONE") and b.status or nil
    -- its gender ("M" / "F" / "U"), for G-Max Cuddle's infatuation
    b.gender = Bt.genderOf(b.species or copy.species, copy.personality)
    b.moves = {}
    for i = 1, 4 do
      local ref = copy.moves and copy.moves[i]
      if ref and ref ~= 0 then
        local mv = Bt.move(ref, copy.pp and tonumber(copy.pp[i]), copy.maxPp and tonumber(copy.maxPp[i]))
        if mv then b.moves[#b.moves + 1] = mv end
      end
    end
    -- Dynamax (the National Dex's marks on the Pokemon): whether it can, its Dynamax Level, its
    -- G-Max Move when it has the factor and the form; each move's Max form for when it does
    local dx = Bt.dynamax()
    b.canDmax = true
    b.dmaxLevel = 0
    if dx then
      local okC, can = pcall(dx.canDynamax, copy)
      b.canDmax = not okC or can ~= false
      local okL, lv = pcall(dx.level, copy)
      b.dmaxLevel = okL and tonumber(lv) or 0
      local okG, gm = pcall(dx.canGigantamax, copy)
      if okG and gm then
        local okM, id = pcall(dx.gmaxMoveOf, copy)
        b.gmaxId = okM and id or nil
      end
      local okH, mult = pcall(dx.hpMult, b.dmaxLevel)
      b.dmaxMult = okH and tonumber(mult) or nil
    end
    b.dmaxMult = b.dmaxMult or (1.5 + 0.05 * b.dmaxLevel)
    b.maxMoves = {}
    for i, mv in ipairs(b.moves) do b.maxMoves[i] = Bt.maxOf(mv, b.gmaxId) end
    return b
  end

  -- a species' gender for a personality (the engine's Pokemon.gender: "M" / "F" / "U")
  function Bt.genderOf(species, personality)
    if not (Pokemon and Pokemon.gender and species) then return "U" end
    local ok, g = pcall(Pokemon.gender, species, personality or 0)
    return ok and (g == "M" or g == "F") and g or "U"
  end

  -- the National Dex's Dynamax (exports.dynamax), or nil on an older one
  function Bt.dynamax()
    local dex = deps.dex and deps.dex()
    return dex and type(dex.dynamax) == "table" and dex.dynamax or nil
  end

  -- a stat at a level (Gen 3's formula; HP its own), from a base, an IV, no EVs, neutral nature
  local function stat(base, iv, level, hp)
    local core = floor((2 * base + iv) * level / 100)
    return hp and (core + level + 10) or (core + 5)
  end

  -- a raid boss's IVs (Sword / Shield's): `perfect` of the six at 31, chosen at random, the rest 0-31;
  -- without a roll (a preview) the first `perfect` in order at 31, the rest 15
  Bt.IV_STATS = { "hp", "atk", "def", "spe", "spa", "spd" }
  function Bt.rollIvs(perfect, rng)
    local ivs = {}
    local order = {}
    for i, k in ipairs(Bt.IV_STATS) do
      ivs[k] = rng and rng(0, 31) or 15
      order[i] = k
    end
    if rng then
      for i = #order, 2, -1 do
        local j = rng(1, i)
        order[i], order[j] = order[j], order[i]
      end
    end
    for i = 1, min(#order, perfect or 0) do ivs[order[i]] = 31 end
    return ivs
  end

  -- the boss: its base stats (the pack's Giga ones; a Dynamax boss its species') at a level in its
  -- tier's band, its IVs (Bt.rollIvs) and HP x hpMult
  function Bt.boss(key, rng)
    local b, sp = Bosses[key], Sprites[key]
    if not (b and sp) then return nil end
    local T = R.STARS[b.stars] or R.STARS[1]
    local level = rng and rng(T.lv[1], T.lv[2]) or T.lv[1]
    local base = sp.base or {}
    local ivs = Bt.rollIvs(T.perfect or 0, rng)
    local hp = floor(stat(base.hp or 80, ivs.hp, level, true) * (T.hpMult or 1))
    -- (a Dynamax boss carries its own species: a form is a species of its own)
    local species = b.slot or (Pokemon and Pokemon.speciesFromNational and select(2, pcall(Pokemon.speciesFromNational, b.national))) or nil
    local mon = {
      species = tonumber(species) or 0, speciesId = tonumber(species) or 0, level = level, hp = hp, maxHp = hp,
      attack = stat(base.atk or 80, ivs.atk, level), defense = stat(base.def or 80, ivs.def, level),
      spAtk = stat(base.spa or 80, ivs.spa, level), spDef = stat(base.spd or 80, ivs.spd, level),
      speed = stat(base.spe or 80, ivs.spe, level),
      ivs = ivs,
      evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
      personality = 0, ability = 0, abilityId = 0, friendship = 255,
    }
    -- its gender, rolled by its species' ratio (kept by the catch: Rw.throw)
    local gp = rng and rng(0, 255) or 0
    mon.genderRoll = gp
    mon.atk, mon.def, mon.spa, mon.spd, mon.spe = mon.attack, mon.defense, mon.spAtk, mon.spDef, mon.speed
    local types = b.types or { "NORMAL" }
    local t1, t2 = Bt.typeNum(types[1]), types[2] and Bt.typeNum(types[2]) or nil
    local boss = {
      mon = mon, species = mon.species, type1 = t1, type2 = (t2 ~= t1) and t2 or nil, side = "enemy", id = 1,
      ability = 0, stages = { attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0, accuracy = 0, evasion = 0 },
      name = b.name, boss = true, key = key, moves = {},
    }
    boss.gender = Bt.genderOf(mon.species, gp)
    if b.moves then
      for _, name in ipairs(b.moves) do
        local mv = Bt.move(name, 99, 99)
        if mv then boss.moves[#boss.moves + 1] = mv
        else mod.log:warn("raid boss %s: the game has no move %s", key, tostring(name)) end
      end
    elseif b.slot and Pokemon and Pokemon.movesAtLevel then
      -- (a Dynamax boss: the moves a wild one of its level knows)
      local ok, ids = pcall(Pokemon.movesAtLevel, b.slot, level)
      for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
        local mv = tonumber(id) and tonumber(id) > 0 and Bt.move(tonumber(id), 99, 99)
        if mv then boss.moves[#boss.moves + 1] = mv end
      end
    end
    -- the raid's own: its barriers (its tier's HP shares; the segments from its base Def + Sp. Def),
    -- its script, its G-Max move
    boss.shields = T.shields or {}
    local S = R.SEGMENTS or { BASE = 2, PER = 60, MIN = 2, MAX = 8 }
    boss.segments = max(S.MIN, min(S.MAX, S.BASE + floor(((base.def or 80) + (base.spd or 80)) / S.PER)))
    boss.script = R.SCRIPTS and R.SCRIPTS[b.script or "basic"] or {}
    boss.gmax = Bt.gmaxMove(b.gmax, boss) or Bt.maxMove(boss)
    return boss
  end

  -- a Max Move's power from its base move's: the move's own (data/raid_maxpower.lua), 100 for a move
  -- with no power of its own, else its power's band (Gmax.POWER_BANDS; Fighting and Poison the lower
  -- column)
  local MaxPower = deps.MaxPower or {}
  local function squash(key) return type(key) == "string" and key:lower():gsub("[^%w]", "") or nil end
  Bt.squash = squash
  function Bt.maxPower(power, typeName, key)
    local own = key and MaxPower[squash(key)]
    if own then return own end
    power = tonumber(power) or 0
    if power <= 1 then return 100 end
    for _, row in ipairs(Gmax.POWER_BANDS or {}) do
      if power < row[1] then return (typeName == "FIGHTING" or typeName == "POISON") and row[3] or row[2] end
    end
    return 130
  end

  -- the boss's G-Max move (data/raid_gmax.lua) as the sim runs it: one target (a Max Move's), never
  -- missing; its power fixed, else the band of the boss's strongest move of its type
  function Bt.gmaxMove(id, boss)
    local g = id and Gmax.MOVES and Gmax.MOVES[id]
    if not g then return nil end
    local power = g.power
    if not power then
      local best, bestMv = 0, nil
      for _, mv in ipairs(boss.moves or {}) do
        if mv.typeName == g.type and not mv.status and mv.power > best then best, bestMv = mv.power, mv end
      end
      power = bestMv and Bt.maxPower(best, g.type, bestMv.key) or 130
    end
    local t = Bt.typeNum(g.type)
    local effect = nil
    if g.effect then
      effect = {}
      for k, v in pairs(g.effect) do effect[k] = v end
      if effect.spare then effect.spareNum = Bt.typeNum(effect.spare) end
    end
    return {
      name = g.name or ("G-Max " .. titled(id)), type = t, typeName = g.type, power = power, accuracy = 0, key = id,
      priority = 0, status = false, spread = false, isGmax = true, gmaxEffect = effect, pierce = g.pierce, pp = 99, maxPp = 99,
      ref = { id = "MAX_RAIDS_GMAX_" .. id, numId = 0, power = power, type = t, accuracy = 0, pp = 1, effect = 0,
        priority = 0, target = 8, flags = 0, secondaryChance = 0 },
    }
  end

  -- a plain Max Move (Gmax.MAX) from the boss's strongest damaging move (a move of its own type
  -- counting half again): its type, the Max power band of its power, one target, never missing;
  -- drawn as that move (isMax, baseKey)
  function Bt.maxMove(boss)
    local best, bestScore = nil, -1
    for _, mv in ipairs(boss.moves or {}) do
      if not mv.status then
        local stab = (mv.type == boss.type1 or (boss.type2 ~= nil and mv.type == boss.type2)) and 1.5 or 1
        local score = (mv.power or 0) * stab
        if score > bestScore then best, bestScore = mv, score end
      end
    end
    if not best then return nil end
    return Bt.maxOf(best)
  end

  -- the Max form of one move (a Dynamaxed Pokemon's): a damaging move the Max Move of its type
  -- (Gmax.MAX: name, effect) at its Max power, or the G-Max Move when gmaxId's type is the move's
  -- (its fixed power, else the move's Max power); a status move Max Guard (+4, protects). Never
  -- misses; spends the base move's PP (`base`); one target
  function Bt.maxOf(mv, gmaxId)
    if mv.status then
      return {
        name = "Max Guard", type = 0, typeName = "NORMAL", power = 0, accuracy = 0, key = "MAX_GUARD",
        priority = 4, status = true, guard = true, spread = false, isGmax = true, isMax = true, base = mv,
        pp = mv.pp, maxPp = mv.maxPp,
        ref = { id = "MAX_RAIDS_MAX_GUARD", numId = 0, power = 0, type = 0, accuracy = 0, pp = 1, effect = 0,
          priority = 4, target = 16, flags = 0, secondaryChance = 0 },
      }
    end
    local g = gmaxId and Gmax.MOVES and Gmax.MOVES[gmaxId]
    if g and g.type == mv.typeName then
      local gm = Bt.gmaxMove(gmaxId, { moves = { mv } })
      if gm then
        gm.spread, gm.base, gm.baseKey, gm.pp, gm.maxPp = false, mv, mv.key, mv.pp, mv.maxPp
        if not g.power then
          gm.power = Bt.maxPower(mv.power, mv.typeName, mv.key)
          gm.ref.power = gm.power
        end
        return gm
      end
    end
    local row = Gmax.MAX and Gmax.MAX[mv.typeName] or {}
    local power = Bt.maxPower(mv.power, mv.typeName, mv.key)
    local t = mv.type
    return {
      name = row.name or ("Max " .. titled(mv.typeName)), type = t, typeName = mv.typeName, power = power,
      accuracy = 0, key = "MAX_" .. mv.typeName, baseKey = mv.key, priority = 0, status = false, spread = false,
      isGmax = true, isMax = true, gmaxEffect = row.effect, base = mv, pp = mv.pp, maxPp = mv.maxPp,
      ref = { id = "MAX_RAIDS_MAX_" .. mv.typeName, numId = 0, power = power, type = t, accuracy = 0, pp = 1,
        effect = 0, priority = 0, target = 8, flags = 0, secondaryChance = 0 },
    }
  end

  -- ------- the simulation's adapter

  -- the abilities that stop a move outright (applied here: the engine's own run in its battle script)
  local IMMUNE = { LEVITATE = 4, VOLT_ABSORB = 13, WATER_ABSORB = 11, FLASH_FIRE = 10 }

  function Bt.adapter(rng)
    rng = rng or function(lo, hi) return love.math.random(lo, hi) end
    local st = { wild = true, badges = {}, kinds = {}, rng = rng }
    local engineAdapter = nil
    if AdapterMod and AdapterMod.new then
      local ok, ad = pcall(AdapterMod.new, st)
      if ok then engineAdapter = ad end
    end
    local A = { rng = rng }

    local function abilityName(b)
      if not engineAdapter or b.boss then return nil end
      local ok, a = pcall(engineAdapter.abilityOf, engineAdapter, b)
      return ok and type(a) == "string" and a:upper():gsub(" ", "_") or nil
    end
    A.abilityName = abilityName

    -- the type multiplier of a move on a battler (1, 2, 0.5, 0 ...)
    function A.effectiveness(moveType, def)
      if Types and Types.effectiveness then
        local ok, m = pcall(Types.effectiveness, moveType, def.type1, def.type2 or def.type1)
        if ok and tonumber(m) then return tonumber(m) end
      end
      return 1
    end

    -- the damage of att's move on def: dmg, info (effectiveness, critical); 0 for an immunity
    -- (under Gravity a Ground move reaches a Flying type or one with Levitate: the target's Flying
    -- type set aside for the hit - the engine's chart then reads its other type alone)
    local GROUND, FLYING = 4, 2
    function A.damage(att, def, mv, spread, o)
      o = o or {}
      if o.gravity and mv.type == GROUND and (def.type1 == FLYING or def.type2 == FLYING) then
        local t1, t2 = def.type1, def.type2
        if t1 == FLYING then def.type1 = (t2 ~= nil and t2 ~= FLYING) and t2 or 0 end
        if def.type2 == FLYING then def.type2 = nil end
        local okD, dmg, info = pcall(A.damage, att, def, mv, spread, { reflect = o.reflect, lightScreen = o.lightScreen,
          doubleScreens = o.doubleScreens, helped = o.helped, gravity = false })
        def.type1, def.type2 = t1, t2
        if okD then return dmg, info end
        return 1, { effectiveness = 1 }
      end
      local ab = abilityName(def)
      if ab and IMMUNE[ab] == mv.type and not (o.gravity and ab == "LEVITATE") then
        return 0, { effectiveness = 0, immuneBy = ab }
      end
      if ab == "WONDER_GUARD" and A.effectiveness(mv.type, def) <= 1 then return 0, { effectiveness = 0, immuneBy = ab } end
      if not Damage then return 1, { effectiveness = 1 } end
      st.player, st.enemy = att.side == "player" and att or def, att.side == "player" and def or att
      -- (a Dynamaxed Pokemon's Choice item does nothing)
      local heldBack = nil
      if att.dmax and HeldItems and HeldItems.of then
        local okH, he = pcall(HeldItems.of, att, "damage", st)
        if okH and HeldItems.HOLD and he == HeldItems.HOLD.CHOICE_BAND then heldBack, att.item = att.item, 0 end
      end
      -- (the target side's screens; Helping Hand: the engine's own x1.5)
      local helpedWas = att.expHelpingHand
      if o.helped then att.expHelpingHand = true end
      -- (a spread move's cut is the sim's: Sword / Shield's 3 / 4, not Gen 3's half)
      local ok, dmg, info = pcall(Damage.calc, att, def, mv.ref, { adapter = engineAdapter, st = st, rng = rng,
        weather = st.weather, highCrit = (att.critUp or 0) > 0 or nil,
        reflect = o.reflect or nil, lightScreen = o.lightScreen or nil, doubleScreens = o.doubleScreens or nil })
      att.expHelpingHand = helpedWas
      if heldBack ~= nil then att.item = heldBack end
      if not ok then
        mod.log:warn("raid damage failed (%s): %s", tostring(mv.name), tostring(dmg))
        return 1, { effectiveness = 1 }
      end
      info = type(info) == "table" and info or {}
      -- (the engine's own `effectiveness` is its chart's scaled product: the multiplier from the chart)
      local flags = info.typeFlags
      if (flags and flags.immune) or info.effectiveness == 0 then info.effectiveness = 0
      else info.effectiveness = A.effectiveness(mv.type, def) end
      return max(0, floor(tonumber(dmg) or 0)), info
    end

    -- a confused battler hitting itself: a 40-power typeless physical blow on itself (the engine's
    -- Damage.base, as its own battle does)
    function A.confusionHit(b)
      if not (Damage and Damage.base) then return nil end
      local ok, dmg = pcall(Damage.base, b, b, { power = 40, type = 0, effect = 0 }, { power = 40, moveType = 0,
        adapter = engineAdapter })
      return ok and tonumber(dmg) and max(1, floor(dmg)) or nil
    end

    -- Gen 3's accuracy check (the engine's formula: stages, the move's accuracy)
    local ACC = Rules and Rules.ACCURACY_STAGE
    -- (gravity: x5/3, G-Max Gravitas)
    function A.hits(att, def, mv, gravity)
      if (mv.accuracy or 0) <= 0 then return true end
      local buff = max(-6, min(6, (att.stages.accuracy or 0) - (def.stages.evasion or 0)))
      local r = ACC and ACC[buff] or { 1, 1 }
      local calc = floor(r[1] * mv.accuracy / r[2])
      if gravity then calc = floor(calc * 5 / 3) end
      return rng(1, 100) <= calc
    end

    -- speed with its stage, paralysis quartering it
    function A.speed(b)
      local s = tonumber(b.mon.speed) or 1
      if Damage and Damage.applyStage then
        local ok, v = pcall(Damage.applyStage, s, b.stages.speed or 0)
        if ok and tonumber(v) then s = tonumber(v) end
      end
      if b.status == "PAR" then s = floor(s / 4) end
      return s
    end
    return A
  end

  return Bt
end
