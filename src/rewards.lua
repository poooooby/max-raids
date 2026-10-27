-- After a won raid: the catch and the rewards (data/raid_rules.lua RAID.CATCH / RAID.REWARD), on the
-- engine. The catch: one throw of a ball the bag holds (used up), a chance by the tier times the
-- ball's; caught, the boss's species at its level joins the party (or the PC), registered caught in
-- the Pokedex, in that ball. The rewards: Sword / Shield's drops by tier, into the bag - Exp. Candies
-- (National Dex Gen 3's), TMs of the boss's types, berries, treasures, a Rare Candy, a PP Max for the
-- Bottle Cap (RAID.REWARD); nothing straight to the four who fought.
--   Rw = rewards(mod, { N, Bosses, Sprites }) ; Rw.battle = src/battle.lua's (for the TMs' moves)
--   Rw.balls() -> { { item, name, n, mult }, ... } ; Rw.chance(stars, mult) (pure)
--   Rw.throw(key, level, ball, rng, ivs) -> caught, { name, toPC } | why   (ivs: the boss's, kept)
--   Rw.rollItems(key, rng) -> { { id, n }, ... } ; Rw.give(r, rng) -> { items, firstWin }

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
    -- a TM by its number and move, as Sword / Shield names its TRs ("TM42 Facade")
    local n = tonumber(id)
    if n and n >= 289 and n <= 338 and Pokemon and Pokemon.moveFromTmItem and Rw.battle and Rw.battle.move then
      local okM, move = pcall(Pokemon.moveFromTmItem, n)
      local okB, mv = pcall(Rw.battle.move, move)
      if okM and okB and type(mv) == "table" and mv.name then return ("TM%02d %s"):format(n - 288, mv.name) end
    end
    if ItemsData and ItemsData.displayName then
      local ok, nm = pcall(ItemsData.displayName, id)
      if ok and type(nm) == "string" and nm ~= "" then
        nm = nm:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
        -- (the sizes and initials stay capitals: Exp. Candy XS / XL, PP Max)
        nm = nm:gsub("%f[%w]Xs%f[%W]", "XS"):gsub("%f[%w]Xl%f[%W]", "XL"):gsub("%f[%w]Pp%f[%W]", "PP")
          :gsub("%f[%w]Tm(%d+)", "TM%1"):gsub("%f[%w]Hp%f[%W]", "HP")
        return nm
      end
    end
    return "?"
  end
  -- an item's words in the bag (one line)
  function Rw.itemDesc(id)
    if not (ItemsData and ItemsData.info) then return "" end
    local ok, info = pcall(ItemsData.info, id)
    local d = ok and type(info) == "table" and info.description or ""
    if type(d) ~= "string" then return "" end
    return (d:gsub("\n", " "):gsub("%s+", " "))
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
  function Rw.throw(key, level, ball, rng, ivs)
    local s = session()
    local b = Bosses[key]
    if not (s and b and ball) then return false, "no session" end
    if Bag and Bag.remove then pcall(Bag.remove, s.bag, ball.item, 1) end
    local roll = rng and rng(1, 100) or math.random(1, 100)
    if roll > Rw.chance(b.stars, ball.mult) then return false, "broke free" end
    -- (a Dynamax boss carries its own species, its form among them)
    local species = b.slot or (Pokemon and Pokemon.speciesFromNational and select(2, pcall(Pokemon.speciesFromNational, b.national)))
    species = tonumber(species)
    if not (species and Party and Party.giveMonToPlayer) then return false, "no species" end
    local ok, code, mon = pcall(Party.giveMonToPlayer, s, species, level)
    if not ok or code == Party.MON_CANT_GIVE or not mon then return false, "no room" end
    mon.pokeball = ball.item
    -- (it keeps the boss's IVs, as Sword / Shield's raid Pokemon do)
    if type(ivs) == "table" then
      mon.ivs = mon.ivs or {}
      for k, v in pairs(ivs) do mon.ivs[k] = v end
      if Pokemon and Pokemon.applyStats then pcall(Pokemon.applyStats, mon, s) end
      mon.hp = mon.maxHp or mon.hp
    end
    if Dex and Dex.registerCapture and s.dex then pcall(Dex.registerCapture, s.dex, species, s, mon.personality) end
    local name = b.name
    if Pokemon and Pokemon.displayName then
      local okN, n = pcall(Pokemon.displayName, mon)
      if okN and type(n) == "string" then name = n end
    end
    return true, { name = name, toPC = code == Party.MON_GIVEN_TO_PC, mon = mon }
  end

  -- ------- the rewards

  -- the Exp. Candies' item numbers (National Dex Gen 3's: EXP_CANDY_XS..XL), or nil without them
  local function candyIds()
    local ok, d = pcall(mod.find, mod, "national_dex_gen3")
    local ids = ok and type(d) == "table" and d.exports and d.exports.expCandies
    return type(ids) == "table" and ids or nil
  end
  Rw.candyIds = candyIds

  -- Gen 3's TMs (items 289..338 in every version) that teach a damaging move: { { id, typeName } }
  local tmList = nil
  local function tms()
    if tmList then return tmList end
    tmList = {}
    local Bt = Rw.battle
    if not (Pokemon and Pokemon.moveFromTmItem and Bt and Bt.move) then return tmList end
    for id = 289, 338 do
      local okM, move = pcall(Pokemon.moveFromTmItem, id)
      local okB, mv = pcall(Bt.move, move)
      if okM and move and okB and type(mv) == "table" and not mv.status and (tonumber(mv.power) or 0) > 0 then
        tmList[#tmList + 1] = { id = id, typeName = mv.typeName }
      end
    end
    return tmList
  end

  -- n TMs, all different: of the boss's types first, then any damaging one
  function Rw.tmsFor(types, n, rng)
    local list = tms()
    local mine, rest = {}, {}
    local want = {}
    for _, t in ipairs(types or {}) do want[t] = true end
    for _, t in ipairs(list) do
      if want[t.typeName] then mine[#mine + 1] = t else rest[#rest + 1] = t end
    end
    local out = {}
    local function take(from)
      while #out < n and #from > 0 do
        local i = rng(1, #from)
        out[#out + 1] = from[i].id
        table.remove(from, i)
      end
    end
    take(mine)
    take(rest)
    return out
  end

  -- a won raid's drops, rolled (no bag yet): { { id = number, n }, ... } in the card's order -
  -- the Exp. Candies, the TMs, the berries, the treasures, a Rare Candy, a PP Max
  function Rw.rollItems(key, rng)
    local P = R.REWARD
    local b = Bosses[key] or { stars = 1 }
    local stars = math.max(1, math.min(5, b.stars or 1))
    local out = {}
    local function add(id, n)
      if not id or (n or 0) <= 0 then return end
      for _, it in ipairs(out) do if it.id == id then it.n = it.n + n; return end end
      out[#out + 1] = { id = id, n = n }
    end
    local candies = candyIds()
    if candies then
      for _, row in ipairs(P.CANDIES[stars] or {}) do add(candies["EXP_CANDY_" .. row[1]], row[2]) end
    else
      add(Rw.itemId("ITEM_RARE_CANDY"), P.CANDY_STAND_IN[stars] or 1)
    end
    for _, id in ipairs(Rw.tmsFor(b.types, P.TMS[stars] or 1, rng)) do add(id, 1) end
    local pool = {}
    for _, name in ipairs(P.BERRIES.POOL) do pool[#pool + 1] = name end
    for _ = 1, P.BERRIES.N do
      if #pool > 0 and rng(1, 100) <= P.BERRIES.CHANCE then
        local i = rng(1, #pool)
        add(Rw.itemId(pool[i]), 1)
        table.remove(pool, i)
      end
    end
    for _, name in ipairs(P.TREASURES.ITEMS) do
      if rng(1, 100) <= (P.TREASURES.CHANCE[stars] or 0) then add(Rw.itemId(name), 1) end
    end
    if rng(1, 100) <= P.RARE_CANDY then add(Rw.itemId("ITEM_RARE_CANDY"), 1) end
    if rng(1, 100) <= (P.CAP.CHANCE[stars] or 0) then add(Rw.itemId(P.CAP.ITEM), 1) end
    return out
  end

  -- the wins against each boss (save "wins": key -> count)
  local function countWin(key)
    local wins = mod.save:get("wins")
    if type(wins) ~= "table" then wins = {} end
    local first = (wins[key] or 0) == 0
    wins[key] = (wins[key] or 0) + 1
    mod.save:set("wins", wins)
    return first
  end

  -- a won raid's rewards, into the bag: r = the raid (key)
  function Rw.give(r, rng)
    rng = rng or function(lo, hi) return math.random(lo, hi) end
    local s = session()
    local out = { items = {} }
    out.firstWin = countWin(r.key)
    for _, it in ipairs(Rw.rollItems(r.key, rng)) do
      if s and Bag and Bag.add then
        local ok, placed = pcall(Bag.add, s.bag, it.id, it.n)
        if ok and placed ~= false then out.items[#out.items + 1] = { id = it.id, name = Rw.itemName(it.id), n = it.n } end
      end
    end
    return out
  end

  return Rw
end
