-- Galar Rising's achievements, reported to the recomp_achievements framework (provider "max_raids")
-- when it is installed; without it every call here is a no-op.
--
--   A.note(event, ...)  the moments the raid code reports (a den opened, a raid won, a Dynamax, a
--                       catch, a Run); a one-off moment is kept as a flag in the save, so a sweep
--                       awards it even if the framework's save was not up when it happened
--   A.sweep()           what the save's win counts hold (raids won, bosses, stars, a crystal's
--                       raid), recomputed idempotently; runs when the framework's save is ready
--                       (an older save is credited) and after each win
--
-- deps: data (data/raid_achievements.lua), stars(key) -> a boss key's star tier, wins() -> the
-- save's wins table (tests; else mod.save "wins").

return function(mod, deps)
  local A = {}
  local data = deps.data

  local ach, handle
  local ready = false
  local earned = {}     -- id -> true once the framework has it
  local lastValue = {}  -- id -> the last progress sent
  local defs = {}
  for _, row in ipairs(data.list) do defs[row.id] = row end

  -- ---------------------------------------------------------------- the framework

  local function warn(fmt, ...)
    if mod.log and mod.log.warn then mod.log:warn(fmt, ...) end
  end

  local function find()
    local other = mod.find and mod:find("recomp_achievements")
    local api = other and other.exports
    if not (api and api.connect and api.supports) then return nil end
    local major = tonumber(tostring(api.apiVersion):match("^(%d+)"))
    if major ~= 1 or not api.supports("register_many") or not api.supports("progress") then return nil end
    return api
  end

  -- true while achievements are being tracked (framework found, ids registered)
  function A.active() return handle ~= nil end
  function A.isReady() return ready end

  function A.install()
    if handle then return true end
    ach = find()
    if not ach then return false end
    local okC, h = pcall(ach.connect, mod)
    if not (okC and h) then
      warn("achievements: could not connect to recomp_achievements (%s)", tostring(h))
      return false
    end
    local list = {}
    for i, row in ipairs(data.list) do
      local def = {}
      for k, v in pairs(row) do def[k] = v end
      list[i] = def
    end
    local okR, count, errors = pcall(h.registerMany, h, list)
    if not okR then
      warn("achievements: registration failed (%s)", tostring(count))
      return false
    end
    for _, e in ipairs(errors or {}) do
      warn("achievements: a definition was refused (%s: %s)", tostring(e.code), tostring(e.msg or e.message))
    end
    handle = h
    if mod.log and mod.log.info then mod.log:info("achievements: %d registered with recomp_achievements", tonumber(count) or 0) end
    if mod.events and mod.events.on and ach.events and ach.events.ready then
      mod.events:on(ach.events.ready, function()
        ready = true
        earned, lastValue = {}, {}
        A.sweep()
      end)
    end
    return true
  end

  -- ---------------------------------------------------------------- reporting

  local function unlock(id)
    if not handle or earned[id] then return end
    if not defs[id] then return end
    local ok, res, code = pcall(handle.unlock, handle, id)
    if ok and (res == true or code == "already_unlocked") then earned[id] = true end
  end

  local function progress(id, n)
    if not handle or earned[id] then return end
    local def = defs[id]
    if not def then return end
    n = math.max(0, math.min(math.floor(tonumber(n) or 0), def.goal or 0))
    if lastValue[id] == n then return end
    local ok, res, code = pcall(handle.setProgress, handle, id, n)
    if ok and res == true then
      lastValue[id] = n
      if def.goal and n >= def.goal then earned[id] = true end
    elseif ok and code == "already_unlocked" then
      earned[id] = true
    end
  end

  -- ---------------------------------------------------------------- one-off moments

  local function counts()
    if not (mod.save and mod.save.get) then return nil end
    local c = mod.save:get("achievements")
    if type(c) ~= "table" then c = {} end
    c.flags = c.flags or {}
    return c
  end

  -- a one-off moment: kept in the save so a sweep awards it even if the framework's save was not
  -- up when it happened
  local function mark(id)
    local c = counts()
    if c and not c.flags[id] then
      c.flags[id] = true
      mod.save:set("achievements", c)
    end
    unlock(id)
  end

  -- ---------------------------------------------------------------- the sweep

  local function isPackKey(key) return type(key) == "string" and key:sub(1, 5) ~= "DYNA:" end

  local function winsTable()
    if deps.wins then return deps.wins() or {} end
    local w = mod.save and mod.save.get and mod.save:get("wins")
    return type(w) == "table" and w or {}
  end

  -- the wins the save holds: every raid won, and against which bosses
  local function sweepWins()
    local total, packs, fiveStar, crystal = 0, 0, false, false
    for key, n in pairs(winsTable()) do
      n = tonumber(n) or 0
      if n > 0 and type(key) == "string" then
        total = total + n
        if isPackKey(key) then packs = packs + 1 end
        if (tonumber(deps.stars and deps.stars(key)) or 0) >= 5 then fiveStar = true end
        if key:sub(-2) == ":L" then crystal = true end
      end
    end
    if total >= 1 then unlock("first_raid") end
    progress("den_delver", total)
    if packs >= 1 then unlock("giant_slayer") end
    progress("gallery", packs)
    if fiveStar then unlock("five_star") end
    if crystal then unlock("crystal_clear") end
  end

  function A.sweep()
    if not (handle and ready) then return false end
    pcall(sweepWins)
    local c = counts()
    if c then
      for id in pairs(c.flags) do unlock(id) end
    end
    return true
  end

  -- ---------------------------------------------------------------- the moments

  local EVENTS = {}

  -- a den's screen opened (any den, quiet or not)
  EVENTS.den = function() mark("first_den") end

  -- a member Dynamaxed; gmax: with its Gigantamax factor
  EVENTS.dynamax = function(gmax)
    mark("go_big")
    if gmax then mark("gigantamax") end
  end

  -- a raid won, its rewards given (the save's win counts hold it): raid = the raid
  EVENTS.won = function(raid)
    local sim = raid and raid.sim
    if sim and (tonumber(sim.faints) or 0) == 0 then mark("untouched") end
    local quick = data.QUICK
    local stars = tonumber(deps.stars and raid and deps.stars(raid.key)) or 0
    if sim and quick and stars >= quick.MIN_STARS and (tonumber(sim.turnNo) or math.huge) <= quick.TURNS then
      mark("quick_work")
    end
    A.sweep()
  end

  -- the boss caught; shiny: it was a shiny raid
  EVENTS.caught = function(shiny)
    mark("gotcha_giant")
    if shiny then mark("shiny_raider") end
  end

  -- Run, answered Yes: blown out of the den
  EVENTS.ran = function() mark("blown_away") end

  -- a note never throws into the game; without the framework it does nothing at all
  function A.note(event, ...)
    if not handle then return end
    local fn = EVENTS[event]
    if not fn then return end
    pcall(fn, ...)
  end

  A.EVENTS = EVENTS
  A.defs = defs
  return A
end
