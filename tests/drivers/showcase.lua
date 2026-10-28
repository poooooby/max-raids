-- Driver: a showcase to record, in real time. Set up first (a team of six at Lv 70, the first badge,
-- a den on Route 104 holding a 4★ Charizard, the overworld at its default zoom), then it waits for
-- "." (the play key) and plays: out of Rustboro's gym, the dens awaken (the shake, the words), the
-- route and a walk up to the den, the den screen, the raid - the intro, G-Max Wildfire on the four,
-- on the first turn Blaziken Dynamaxing and Gardevoir's Light Screen over the team, the team's
-- strongest moves, Charizard falling on the third turn - an Ultra Ball that catches it, the rewards card,
-- back on the field. Emerald (Rustboro); FireRed runs from Pewter.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/showcase.lua love .
-- (SHOWCASE_BOSS another boss; the catch is an Ultra Ball that always holds - SHOWCASE_CATCH=0 leaves it)

local GYMS = { "RUSTBORO_CITY_GYM", "PEWTER_CITY_GYM" }
local ROUTES = { "ROUTE104", "ROUTE_2" }

local function body(game, log)
  local U = require("tests.drivers.util")
  -- (SHOT_DIR set: a few frames saved along the way, to check a dry run - each save stalls the game a
  -- moment, so leave it unset for a recording)
  local shotDir = os.getenv("SHOT_DIR")
  local function shot(name) if shotDir then U.shot(game, shotDir .. "/" .. name .. ".png") end end
  local clock = love.timer.getTime
  -- (SHOWCASE_HITCH=<ms>: every frame slower than that logged, with what the raid was doing)
  local hitchMs = tonumber(os.getenv("SHOWCASE_HITCH"))
  if hitchMs then
    -- (and every slow resource made, with who asked)
    local function timed(lib, name)
      local f = lib and lib[name]
      if not f then return end
      lib[name] = function(...)
        local t0 = clock()
        local a, b, c = f(...)
        local ms = (clock() - t0) * 1000
        if ms > 8 then
          local tb = debug.traceback("", 2)
          local where = {}
          for line in tb:gmatch("[^\n]+") do
            if line:find("max_raids") or line:find("national_dex") or line:find("g9") then where[#where + 1] = line:gsub("^%s+", "") end
            if #where >= 3 then break end
          end
          log(("  SLOW %s %.1f ms <- %s"):format(name, ms, table.concat(where, " <- ")))
        end
        return a, b, c
      end
    end
    for _, n in ipairs({ "newFont", "newImage", "newShader", "newCanvas", "newMesh" }) do timed(love.graphics, n) end
    timed(love.sound, "newDecoder"); timed(love.sound, "newSoundData"); timed(love.audio, "newSource")
    timed(love.image, "newImageData"); timed(love.filesystem, "newFileData")
    -- (the frame's samples from LuaJIT's profiler: where a slow frame's time went)
    local okP, prof = pcall(require, "jit.profile")
    local samples = {}
    if okP and prof then
      prof.start("li1", function(th, n)
        local k = prof.dumpstack(th, "pl <", 6)
        samples[k] = (samples[k] or 0) + n
      end)
    end
    -- (the frame's update, draw and present, timed)
    local parts = { update = 0, draw = 0, present = 0 }
    local function timePart(lib, name, key)
      local f = lib[name]
      lib[name] = function(...)
        local t0 = clock()
        f(...)
        parts[key] = parts[key] + (clock() - t0) * 1000
      end
    end
    timePart(love, "update", "update"); timePart(love, "draw", "draw"); timePart(love.graphics, "present", "present")
    local wait0, last = U.wait, nil
    U.wait = function(n)
      for _ = 1, n or 1 do
        samples = {}
        parts.update, parts.draw, parts.present = 0, 0, 0
        wait0(1)
        local now = clock()
        if last and (now - last) * 1000 > 150 then
          log(("  PARTS update %.1f draw %.1f present %.1f"):format(parts.update, parts.draw, parts.present))
        end
        if last and (now - last) * 1000 > hitchMs and (now - last) * 1000 > 150 then
          local rows = {}
          for k, v in pairs(samples) do rows[#rows + 1] = { k, v } end
          table.sort(rows, function(a, b) return a[2] > b[2] end)
          for i = 1, math.min(6, #rows) do log(("  SAMPLE %d ms: %s"):format(rows[i][2], rows[i][1])) end
        end
        if last and (now - last) * 1000 > hitchMs then
          local X0 = game.mods and game.mods.exports and game.mods.exports.max_raids
          local c = X0 and X0.raid and X0.raid.current()
          local e = c and c.events and c.events[c.evI]
          log(("HITCH %.1f ms: phase %s, menu %s, event %s %s"):format((now - last) * 1000, c and c.phase or "-",
            c and c.cmd and c.cmd.menu or "-", e and e.kind or "-", e and e.text or ""))
        end
        last = now
      end
    end
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  -- real time, whatever the frame rate
  local function secs(s)
    local t0 = clock()
    while clock() - t0 < s do U.wait(1) end
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Message = require("src.ui.game3.message")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Profile = require("src.core.game3.profile")
  local Warp = require("src.core.game3.warp")
  local Zoom = require("src.render.Zoom")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local s0 = Runtime.getSession()

  -- the team
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_GARDEVOIR", "SPECIES_SALAMENCE", "SPECIES_METAGROSS",
    "SPECIES_SWAMPERT", "SPECIES_SCEPTILE" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  -- Gardevoir guards the team with Light Screen (its last slot); Blaziken, holding the Energy on the
  -- first turn, Dynamaxes at Dynamax Level 10
  local okL, ls = pcall(require("src.core.game3.battle.moves").get, "LIGHT_SCREEN")
  if okL and type(ls) == "table" then
    local g = s0.party[2]
    g.moves[4], g.pp[4], g.maxPp[4] = ls.numId or "LIGHT_SCREEN", tonumber(ls.pp) or 30, tonumber(ls.pp) or 30
  else
    log("no Light Screen")
  end
  local nd = game.mods.exports and game.mods.exports.national_dex_gen3
  if nd and nd.dynamax then nd.dynamax.setLevel(s0.party[1], 10) end
  pcall(Bag.add, s0.bag, C:id("items", "ITEM_ULTRA_BALL"), 5)
  -- no wild Pokemon, no trainer stepping out, the default zoom (in memory only: options.lua untouched)
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").checkLineOfSight = function() return nil end
  local function fit() Zoom.offset = 0 end
  fit()

  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not (X and X.dens) then log("FAIL max_raids not loaded"); return end
  local Dn, R = X.dens, X.raid
  local maps = game.data and game.data.maps or {}
  local gym, route
  for id in pairs(maps) do
    if type(id) == "string" then
      for _, g in ipairs(GYMS) do if id:sub(-#g) == g then gym = id end end
      for _, rt in ipairs(ROUTES) do if id:sub(-#rt) == rt and not id:find("UNDERWATER") then route = id end end
    end
  end
  log("gym", tostring(gym), "route", tostring(route))
  if not (gym and route) then log("FAIL no gym or route"); return end

  local function goTo(mapId, x, y, facing)
    local Field = require("src.core.game3.field")
    local ok, res, why = pcall(Map.load, Field._mod, Field._game or game, mapId, { x = x, y = y, facing = facing or "down" })
    if not ok or (res == nil and why) then log("Map.load", mapId, "failed:", tostring(ok and why or res)); return false end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing or "down" end
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(20)
    fit()
    return true
  end

  -- the route's dens placed beforehand (awake for the moment), one of them Charizard's, with a
  -- straight walkable approach of a few tiles to it
  Dn.setAwake(true)
  goTo(route, math.floor((maps[route].width or 20) / 2), math.floor((maps[route].height or 20) / 2))
  waitFor(function() return Dn.forMap(route) ~= nil end, 600)
  U.wait(30)
  local list = Dn.forMap(route) or {}
  local den, approach
  local STEPS = 5
  local DIRS = { { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }
  for _, d in ipairs(list) do
    for _, dir in ipairs(DIRS) do
      local okLine = true
      for k = 1, STEPS do
        local cx, cy = d.x + dir[1] * k, d.y + dir[2] * k
        if not Collision.isWalkable(cx, cy) then okLine = false; break end
      end
      if okLine then den, approach = d, { x = d.x + dir[1] * STEPS, y = d.y + dir[2] * STEPS, face = dir[3] }; break end
    end
    if den then break end
  end
  if not den then log("FAIL no den with a clear approach on", route); return end
  den.active, den.done, den.stars, den.boss, den.day = true, nil, 4, os.getenv("SHOWCASE_BOSS") or "CHARIZARD_4", Dn.today()
  log(("den at %d,%d; the walk from %d,%d going %s"):format(den.x, den.y, approach.x, approach.y, approach.face))
  Dn.setAwake(false)

  -- in the gym, a few steps above its door, the first badge won
  goTo(gym, 0, 0)
  local def = Map.currentDef and Map.currentDef()
  local exit
  for _, w in ipairs(def and def.warps or {}) do
    if not exit or tonumber(w.y) > tonumber(exit.y) then exit = w end
  end
  local ex, ey = tonumber(exit.x), tonumber(exit.y)
  local sy = ey
  for k = 1, 3 do if Collision.isWalkable(ex, ey - k) then sy = ey - k else break end end
  goTo(gym, ex, sy, "down")
  local okP, P = pcall(Profile.forSession, nil)
  local t = Flags.forVersion(okP and P and P.id or nil)
  local b = t and t.BADGES and t.BADGES[1]
  Flags.setFlag(Space.getStore(), nil, type(b) == "table" and b.flag or b, true)
  -- (a Repel's worth of steps: no wild Pokemon on the walk through the route's grass - the team's
  -- Lv 70 lead keeps every one away, as the game's Repel)
  require("src.core.game3.field_semantics").setVar(s0, "repelSteps", 250)
  U.wait(60)
  fit()

  -- the play key
  log("READY - start recording, then press . to play")
  print("[showcase] READY - press . (period) in the game window to play")
  -- (SHOWCASE_AUTO=1: no key, for a dry run)
  if os.getenv("SHOWCASE_AUTO") ~= "1" then
    while not love.keyboard.isDown(".") do U.wait(1) end
    while love.keyboard.isDown(".") do U.wait(1) end
  end
  log("playing")
  secs(1.0)

  -- out of the gym
  local before = Map.current
  while Map.current == before do U.hold(game, "down", 4) end
  fit()
  -- the awakening: the shake, then the words (each read a moment, then A)
  waitFor(function() return Message.isOpen() end, 1800)
  shot("s01_words")
  for _ = 1, 4 do
    if not Message.isOpen() then break end
    waitFor(function() return Message._waiting or not Message.isOpen() end, 900)
    secs(1.6)
    U.tap(game, "a")
    secs(0.3)
  end
  waitFor(function() return Dn.awake() and not require("src.core.game3.field").isLocked() end, 600)
  secs(1.2)

  -- to the route (the game's fade), then the walk up to the den
  Warp.request(nil, game, route, approach.x, approach.y, approach.face, {})
  waitFor(function() return Map.current == route end, 900)
  fit()
  secs(1.5)
  local dx, dy = den.x - approach.x, den.y - approach.y
  local steps = math.abs(dx) + math.abs(dy) - 1
  local dir = approach.face
  local target = { x = approach.x + (dx ~= 0 and (dx > 0 and steps or -steps) or 0),
    y = approach.y + (dy ~= 0 and (dy > 0 and steps or -steps) or 0) }
  local guard = 0
  while (Player.cellX ~= target.x or Player.cellY ~= target.y) and guard < 400 do
    U.hold(game, dir, 2)
    guard = guard + 1
  end
  U.wait(12)
  secs(0.6)
  shot("s02_at_den")
  U.tap(game, "a")
  waitFor(function() return X.state().active end, 300)

  -- the den screen: a look, then START
  secs(3.0)
  shot("s03_den_screen")
  for _ = 1, 2 do U.tap(game, "down"); secs(0.45) end
  secs(0.8)
  U.tap(game, "a")
  waitFor(function() return X.state().phase == "intro" end, 300)

  -- the raid: each member picks its strongest moves (a different one each turn); Charizard falls on
  -- the third turn
  local turn, lastPhase = 0, nil
  local function bestMoves(b)
    local list2 = {}
    for k, mv in ipairs(b and b.moves or {}) do
      if (tonumber(mv.power) or 0) > 0 then list2[#list2 + 1] = { k = k, p = tonumber(mv.power) or 0 } end
    end
    table.sort(list2, function(a, c) return a.p > c.p end)
    return list2
  end
  local deadline = clock() + 300
  while X.state().active and clock() < deadline do
    local cur = R.current()
    if not cur then break end
    if cur.phase == "command" and lastPhase ~= "command" then
      turn = turn + 1
      log("turn", turn)
      if turn == 2 then shot("s04_turn2") end
    end
    lastPhase = cur.phase
    if cur.phase == "command" and turn >= 3 and cur.boss and cur.boss.mon then
      cur.boss.mon.hp = math.min(cur.boss.mon.hp, 1)
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      local m = cur.members[cur.cmd.actor]
      secs(0.7)
      R.choose("fight")
      secs(0.6)
      local actor = cur.cmd.actor
      local opts = bestMoves(m and m.b)
      local pick = opts[((turn - 1) % math.max(1, math.min(2, #opts))) + 1]
      local k = pick and pick.k or 1
      local guardTeam = false
      -- turn 1: member 2 puts up Light Screen; member 1 Dynamaxes
      if turn == 1 and actor == 2 then
        for i, mv in ipairs(m.b.moves) do if mv.name == "Light Screen" then k, guardTeam = i, true end end
      end
      if turn == 1 and actor == 1 and cur.sim.canDynamax and cur.sim:canDynamax(1) then
        R.choose("dynamax")
        secs(1.2)
      end
      if R.current() and R.current().cmd then R.current().cmd.cursor = k end
      secs(0.5)
      R.choose("move" .. k)
      -- a team move asks first (the arrow on all four): a look, then confirm
      local c2 = R.current() and R.current().cmd
      if c2 and c2.menu == "target" then
        secs(1.2)
        local tk = 1
        if not guardTeam then
          for i, row in ipairs(c2.moveList or {}) do if row.live ~= false then tk = i; break end end
        end
        R.choose("move" .. tk)
      end
      secs(0.2)
    elseif cur.phase == "catch" then
      secs(2.0)
      shot("s045_catch")
      if os.getenv("SHOWCASE_CATCH") ~= "0" then
        -- a sure catch: the real throw at the Master Ball's odds, the Ultra Ball's look kept
        local Rw = X._test and X._test.rewards
        if Rw and not Rw._showcaseSure then
          local real = Rw.throw
          Rw._showcaseSure = true
          Rw.throw = function(key, level, ball, ...)
            local sure = {}
            for k2, v in pairs(ball or {}) do sure[k2] = v end
            sure.mult = 0
            return real(key, level, sure, ...)
          end
        end
        R.catchChoose("catch")
        secs(1.5)
        local bi = 1
        local cc = R.current() and R.current().cmd
        for i, bl in ipairs(cc and cc.balls or {}) do
          if tostring(bl.name):upper():find("ULTRA") then bi = i end
        end
        if cc then cc.ball = bi end
        secs(1.0)
        R.pickBall(bi)
        waitFor(function() return not R.current() or R.current().phase == "rewards" end, 20000)
      else
        if cur.cmd then cur.cmd.cursor = 2 end
        secs(0.8)
        R.catchChoose("leave")
      end
    elseif cur.phase == "rewards" then
      secs(2.0)
      shot("s05_rewards")
      secs(4.0)
      R.endRewards()
      waitFor(function() return not X.state().active end, 3000)
    else
      U.wait(1)
    end
  end
  fit()
  secs(3.0)
  shot("s06_field")
  log("done")
end

return function(game)
  local dir = os.getenv("SHOT_DIR")
  local logFile = dir and io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
