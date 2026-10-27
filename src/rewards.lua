-- After a won raid: the catch and the rewards (data/raid_rules.lua RAID.CATCH / RAID.REWARD), on the
-- engine. The catch: one throw of a ball the bag holds (used up), a chance by the tier times the
-- ball's; caught, the boss's species at its level joins the party (or the PC), registered caught in
-- the Pokedex, in that ball. The rewards: items into the bag, the boss's Exp to each of the four
-- who fought (their own Pokemon, not the raid's copies; levels with their stats - new moves and
-- evolutions follow after the raid, src/raid.lua), the tier's EVs in the boss's best base stat; x NO_FAINT_MULT with no knock-out, x
-- FIRST_WIN_MULT the first time that boss is beaten (save "wins").
--   Rw = rewards(mod, { N, Bosses, Sprites })
--   Rw.balls() -> { { item, name, n, mult }, ... } ; Rw.chance(stars, mult) (pure)
--   Rw.throw(key, level, ball, rng) -> caught, { name, toPC } | why
--   Rw.give(r) -> { items, team, evStat, ev, mult, firstWin }

return function(mod, deps)
  local N, Bosses, Sprites = deps.N, deps.Bosses, deps.Sprites
  local R = N.RAID
  local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
  local Rw = {}

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local Runtime = engine("src.core.game3.runtime")
  local Constants = engine("src.core.game3.constants")
  local Bag = engine("src.core.game3.bag")
  local ItemsData = engine("src.core.game3.items_data")
  local Party = engine("src.core.game3.party")
  local Dex = engine("src.core.game3.dex")
  local Pokemon = engine("src.core.game3.pokemon")
  local Experience = engine("src.core.game3.battle.experience")

  local function session() return Runtime and Runtime.getSession and Runtime.getSession() or nil end

  -- an item's number for this game from its constant's name
  function Rw.itemId(name)
    local s = session()
    if not (Constants and Constants.of) then return nil end
    local version = s and s.version or "emerald"
    local okC, C = pcall(Constants.of, version)
    if not okC or not C then return nil end
    local ok, id = pcall(C.id, C, "items", name)
    return ok and tonumber(id) or nil
  end
  function Rw.itemName(id)
    if ItemsData and ItemsData.displayName then
      local ok, n = pcall(ItemsData.displayName, id)
      if ok and type(n) == "string" and n ~= "" then
        return (n:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
      end
    end
    return "?"
  end
  local function bagCount(id)
    local s = session()
    if not (Bag and Bag.get and s and s.bag and id) then return 0 end
    local ok, n = pcall(Bag.get, s.bag, id)
    return ok and tonumber(n) or 0
  end

  -- ------- the catch

  -- the chance of the throw (%): the tier's times the ball's; a Master Ball (mult 0) never misses
  function Rw.chance(stars, mult)
    if mult == 0 then return 100 end
    return min(100, floor((R.CATCH.CHANCE[stars] or 50) * (mult or 1) + 0.5))
  end

  -- the balls the bag holds, in CATCH.BALLS' order
  function Rw.balls()
    local out = {}
    for _, row in ipairs(R.CATCH.BALLS) do
      local id = Rw.itemId(row[1])
      local n = id and bagCount(id) or 0
      if n > 0 then out[#out + 1] = { item = id, key = row[1], name = Rw.itemName(id), n = n, mult = row[2] } end
    end
    return out
  end

  -- the throw: the ball used up, the roll; caught, the boss's species at `level` in that ball
  function Rw.throw(key, level, ball, rng)
    local s = session()
    local b = Bosses[key]
    if not (s and b and ball) then return false, "no session" end
    if Bag and Bag.remove then pcall(Bag.remove, s.bag, ball.item, 1) end
    local roll = rng and rng(1, 100) or math.random(1, 100)
    if roll > Rw.chance(b.stars, ball.mult) then return false, "broke free" end
    local species = Pokemon and Pokemon.speciesFromNational and select(2, pcall(Pokemon.speciesFromNational, b.national))
    species = tonumber(species)
    if not (species and Party and Party.giveMonToPlayer) then return false, "no species" end
    local ok, code, mon = pcall(Party.giveMonToPlayer, s, species, level)
    if not ok or code == Party.MON_CANT_GIVE or not mon then return false, "no room" end
    mon.pokeball = ball.item
    if Dex and Dex.registerCapture and s.dex then pcall(Dex.registerCapture, s.dex, species, s, mon.personality) end
    local name = b.name
    if Pokemon and Pokemon.displayName then
      local okN, n = pcall(Pokemon.displayName, mon)
      if okN and type(n) == "string" then name = n end
    end
    return true, { name = name, toPC = code == Party.MON_GIVEN_TO_PC, mon = mon }
  end

  -- ------- the rewards

  local STAT_FROM_BASE = { hp = "hp", atk = "atk", def = "def", spe = "spe", spa = "spa", spd = "spd" }
  Rw.STAT_WORD = { hp = "HP", atk = "Attack", def = "Defense", spe = "Speed", spa = "Sp. Atk", spd = "Sp. Def" }

  -- the boss's best base stat (its EV yield here)
  function Rw.evStat(key)
    local sp = Sprites[key]
    local best, bestV = "hp", -1
    for k, v in pairs(sp and sp.base or {}) do
      if STAT_FROM_BASE[k] and v > bestV then best, bestV = k, v end
    end
    return best
  end

  -- the items a win rolls (pure but for its dice): { { name = "ITEM_X", n }, ... }, merged
  function Rw.rollItems(stars, mult, rng)
    local P = R.REWARD
    local pool = {}
    for _, row in ipairs(P.POOL or {}) do if stars >= row[2] then pool[#pool + 1] = row end end
    local picks = rng(P.ITEM_ROLLS[1], P.ITEM_ROLLS[2]) + (stars >= 4 and 1 or 0)
    local got, order = {}, {}
    for _ = 1, picks do
      local row = pool[rng(1, #pool)]
      if row then
        local n = rng(1, max(1, min(row[3], ceil(stars / 2)))) * 1
        n = max(1, floor(n * mult + 0.5))
        if not got[row[1]] then got[row[1]] = 0; order[#order + 1] = row[1] end
        got[row[1]] = got[row[1]] + n
      end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = { name = k, n = got[k] } end
    return out
  end

  -- EVs into one stat of a Pokemon, held to 252 a stat and 510 in all (Super Training's caps), its
  -- HP moving by the change in its maximum
  local function addEvs(mon, stat, n)
    if not (Pokemon and Pokemon.evsOf) then return 0 end
    local ok, evs = pcall(Pokemon.evsOf, mon)
    if not ok or type(evs) ~= "table" then return 0 end
    local total = 0
    for _, v in pairs(evs) do total = total + (tonumber(v) or 0) end
    local add = max(0, min(n, 252 - (evs[stat] or 0), 510 - total))
    if add == 0 then return 0 end
    evs[stat] = (evs[stat] or 0) + add
    local oldMax, oldHp = tonumber(mon.maxHp) or 0, tonumber(mon.hp) or 0
    if Pokemon.applyStats then pcall(Pokemon.applyStats, mon) end
    local newMax = tonumber(mon.maxHp) or oldMax
    mon.hp = max(oldHp > 0 and 1 or 0, min(newMax, oldHp + (newMax - oldMax)))
    return add
  end

  -- Exp to a Pokemon: its levels (stats with them) and a friendship step a level -> gained,
  -- fromLevel, toLevel. Its new moves and an evolution come after the raid, one by one (raid.lua)
  local function addExp(mon, amount)
    if not (Experience and Experience.apply) then return 0, mon.level, mon.level end
    local ok, res = pcall(Experience.apply, mon, amount)
    if not ok or type(res) ~= "table" then return 0, mon.level, mon.level end
    local from, to = tonumber(res.fromLevel) or mon.level, tonumber(res.toLevel) or mon.level
    for _ = from + 1, to do
      if Pokemon and Pokemon.adjustFriendship then
        pcall(Pokemon.adjustFriendship, mon, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL or 0, {})
      end
    end
    return tonumber(res.gained) or amount, from, to
  end

  -- the first win against a boss (save "wins": key -> count), counted
  local function countWin(key)
    local wins = mod.save:get("wins")
    if type(wins) ~= "table" then wins = {} end
    local first = (wins[key] or 0) == 0
    wins[key] = (wins[key] or 0) + 1
    mod.save:set("wins", wins)
    return first
  end

  -- a won raid's rewards, given: r = the raid (key, boss, members with `orig`, sim)
  function Rw.give(r, rng)
    rng = rng or function(lo, hi) return math.random(lo, hi) end
    local s = session()
    local b = Bosses[r.key] or { stars = 1 }
    local out = { items = {}, team = {} }
    out.firstWin = countWin(r.key)
    local mult = 1
    if r.sim and r.sim.faints == 0 then mult = mult * (R.REWARD.NO_FAINT_MULT or 1) end
    if out.firstWin then mult = mult * (R.REWARD.FIRST_WIN_MULT or 1) end
    out.mult = mult
    -- items
    for _, it in ipairs(Rw.rollItems(b.stars, mult, rng)) do
      local id = Rw.itemId(it.name)
      if id and s and Bag and Bag.add then
        local ok, placed = pcall(Bag.add, s.bag, id, it.n)
        if ok and placed ~= false then out.items[#out.items + 1] = { id = id, name = Rw.itemName(id), n = it.n } end
      end
    end
    -- Exp and EVs to the four's own Pokemon
    local level = r.boss and r.boss.mon and r.boss.mon.level or 20
    local species = r.boss and r.boss.mon and r.boss.mon.species
    local exp = 0
    if Experience and Experience.gainFor and species and species > 0 then
      local ok, e = pcall(Experience.gainFor, species, level, { participants = 1 })
      exp = ok and tonumber(e) or 0
    end
    if exp <= 0 then exp = floor(200 * level / 7) end
    exp = floor(exp * mult)
    local T = R.STARS[b.stars] or R.STARS[1]
    out.evStat, out.ev = Rw.evStat(r.key), T.ev or 0
    for _, m in ipairs(r.members) do
      local mon = m.orig
      if mon then
        local gained, from, to = addExp(mon, exp)
        local evs = addEvs(mon, out.evStat, out.ev)
        m.levelFrom, m.levelTo = from, to
        out.team[#out.team + 1] = { name = m.b and m.b.name or "?", exp = gained, from = from, to = to,
          evs = evs, icon = m.info and m.info.icon }
      end
    end
    return out
  end

  return Rw
end
