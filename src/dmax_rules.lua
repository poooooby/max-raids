-- Dynamax in the game's own battles, the parts that need no engine (tests/dmax_test.lua): which
-- battles allow it, the Max Moves' rows to register, which Max Move a move becomes, and the HP
-- sums. src/dmax.lua runs it in the battle.
--   R.rows()                        every move to register: { key, id, name, label, index, type,
--                                   power, accuracy, pp, effect, priority, target, flags }
--   R.battleAllows(mode, facts)     the option against one battle: facts = { wild, classes = { name },
--                                   flags = { link = true ... }, kinds = { firstBattle = true ... } }
--   R.maxKey(mv, gmaxId, Bt)        the Max Move a move (src/battle.lua Bt.move) becomes: its key in
--                                   R.rows() and its power
--   R.up(hp, maxHp, mult)           HP and max HP once Dynamaxed
--   R.down(hp, dynMax, baseMax)     HP once it ends (its share kept; 1 at least while standing)
return function(deps)
  local D = deps.data
  local R = { data = D }
  local floor, max = math.floor, math.max

  function R.squash(key) return type(key) == "string" and key:lower():gsub("[^%w]", "") or "" end

  local rows, byKey = nil, nil
  function R.rows()
    if rows then return rows, byKey end
    rows, byKey = {}, {}
    local n = D.INDEX
    local function add(key, row)
      row.key, row.index = key, n
      row.id = "MR_" .. key
      row.label = row.label or row.name
      row.accuracy = row.accuracy or 0
      row.pp = row.pp or 10
      row.priority = row.priority or 0
      row.flags = row.flags or 0
      rows[#rows + 1], byKey[key] = row, row
      n = n + 1
    end
    for _, t in ipairs(D.MAX_ORDER) do
      local m = D.MAX[t]
      add("MAX_" .. t, { name = m.name, label = m.label, type = t, power = 100, effect = 17, target = 0 })
    end
    add("MAX_GUARD", { name = D.GUARD.name, type = "NORMAL", power = 0, effect = 111, priority = 4, target = 16 })
    for _, id in ipairs(D.GMAX_ORDER) do
      local g = D.GMAX[id]
      add(id, { name = g.name, label = g.label, type = g.type or "NORMAL", power = 100, effect = 17, target = 0,
        gmax = true })
    end
    -- (the Dynamax itself and its end: no move of their own, their looks)
    add("DYNAMAX", { name = "DYNAMAX", type = "NORMAL", power = 0, effect = 0, target = 16, internal = true })
    add("UNDYNAMAX", { name = "DYNAMAX", type = "NORMAL", power = 0, effect = 0, target = 16, internal = true })
    return rows, byKey
  end

  -- the G-Max moves' types from data/raid_gmax.lua (the rows' registration needs them)
  function R.setGmaxTypes(moves)
    for id, g in pairs(D.GMAX) do
      local m = moves and moves[id]
      if m and m.type then g.type = m.type end
    end
    rows, byKey = nil, nil
  end

  local function any(list, set)
    for _, k in ipairs(list) do if set and set[k] then return true end end
    return false
  end

  function R.battleAllows(mode, facts)
    if mode ~= "league" and mode ~= "trainers" and mode ~= "all" then return false end
    facts = facts or {}
    if any(D.NEVER, facts.flags) or any(D.NEVER_KINDS, facts.kinds) then return false end
    if facts.wild then return mode == "all" end
    if mode == "league" then
      for _, c in ipairs(facts.classes or {}) do
        if c and D.LEAGUE[c] then return true end
      end
      return false
    end
    return true
  end

  function R.maxKey(mv, gmaxId, Bt)
    if not mv then return nil end
    local mx = Bt.maxOf(mv, gmaxId)
    if not mx then return nil end
    local key = mx.key
    if mx.guard then key = "MAX_GUARD" end
    return key, mx.power or 0, mx
  end

  function R.up(hp, maxHp, mult)
    hp, maxHp, mult = tonumber(hp) or 0, max(1, tonumber(maxHp) or 1), tonumber(mult) or 1.5
    local newMax = floor(maxHp * mult)
    local newHp = hp > 0 and max(1, floor(hp * mult)) or 0
    return newHp, newMax
  end

  function R.down(hp, dynMax, baseMax)
    hp, dynMax, baseMax = tonumber(hp) or 0, max(1, tonumber(dynMax) or 1), max(1, tonumber(baseMax) or 1)
    if hp <= 0 then return 0 end
    return math.min(baseMax, max(1, floor(hp * baseMax / dynMax + 0.5)))
  end

  return R
end
