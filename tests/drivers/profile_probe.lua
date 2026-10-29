-- Driver: a whole raid recorded as a timeline (AppleCake, tests/lib/AppleCake: Chrome's trace format)
-- - every frame's engine update / draw / present, and inside them the raid's own parts (Rd.update and
-- its steps, the 3D den's prepare and draw, the effects, the HUD, the pad, the second screen's push,
-- the music), the Lua heap and the particles as counters, the raid's phases and each collection of
-- the heap as marks. Played in real time: the intro, three turns (member 1 Dynamaxes on the first,
-- the boss's HP down to 1 on the third), the catch with an Ultra Ball, the rewards, the field.
-- Open the file in https://ui.perfetto.dev (or chrome://tracing): W / S zoom, A / D pan.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_DRIVER_PACED=1 \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/profile_probe.lua love .
-- POKEPORT_JIT=0: the interpreter only, as the Thor runs (the nearest the desktop comes to it).
-- PROFILE_SECOND=1: the pad on a second screen (a display stood in for: frames drawn and pushed, dropped).
-- PROFILE_DEN=1: opened through the den screen (PROFILE_DEN_S seconds on it, then START), as a player does.
-- PROBE_BOSS (CHARIZARD_4); PROFILE_GMAX=1: the boss's G-Max move every turn.
-- The trace: <SHOT_DIR>/max_raids_profile.json (and the save directory's copy).

local TRACE = "max_raids_profile.json"

local function body(game, log)
  local U = require("tests.drivers.util")
  local clock = love.timer.getTime
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function secs(s)
    local t0 = clock()
    while clock() - t0 < s do U.wait(1) end
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  pcall(Bag.add, s0.bag, C:id("items", "ITEM_ULTRA_BALL"), 5)
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, T = X.raid, X._test

  -- the profiler (the driver's own: nothing of it is in the package)
  local okAC, AC = pcall(require, "mods.max_raids.tests.lib.AppleCake")
  if not okAC then log("FAIL AppleCake did not load: " .. tostring(AC)); return end
  AC = AC(true)
  AC.beginSession(TRACE, "Galar Rising" .. (jit and jit.status() and "" or " (JIT off)"))
  AC.setBuffer(true)
  log("jit:", tostring(jit and jit.status()))

  -- a function timed as a zone of its name; its profile table reused (a nested call gets its own)
  local wrapped = {}
  local function zone(tbl, key, name, named)
    local f = tbl and tbl[key]
    if type(f) ~= "function" then log("(not found: " .. name .. ")"); return end
    local p, busy = nil, false
    local function done(prof, own, ...)
      prof:stop()
      if own then busy = false end
      return ...
    end
    tbl[key] = function(...)
      local own = not busy
      -- (named: the first argument shown, a zone of its own each call)
      if named then own = false end
      local prof = AC.profile(name, named and { arg = tostring((...)) } or nil, own and p or nil)
      if own then p, busy = prof, true end
      return done(prof, own, f(...))
    end
    wrapped[#wrapped + 1] = { tbl, key, f }
  end
  -- the engine's frame
  zone(love, "update", "engine update")
  zone(love, "draw", "engine draw")
  zone(love.graphics, "present", "present (GPU, vsync)")
  -- the raid's parts
  zone(R, "update", "Rd.update")
  zone(R, "stepWarm", "Rd.stepWarm (sounds baked)")
  zone(R, "stepMove", "Rd.stepMove")
  zone(R, "playEvents", "Rd.playEvents")
  zone(R, "stepBossPic", "Rd.stepBossPic")
  zone(R, "draw", "Rd.draw")
  zone(R, "drawMain", "Rd.drawMain")
  zone(R, "drawCatch", "Rd.drawCatch")
  zone(R, "drawThrow", "Rd.drawThrow")
  zone(R, "drawRewards", "Rd.drawRewards")
  zone(T.scene, "prepare", "Scene.prepare (3D)")
  zone(T.scene, "draw", "Scene.draw")
  zone(T.fx, "update", "Fx.update")
  zone(T.fx, "draw", "Fx.draw (front)")
  zone(T.fx, "drawLayer", "Fx.drawLayer (back / mid)")
  zone(T.fx, "drawMoves", "Fx.drawMoves")
  zone(T.pad, "draw", "Pad.draw")
  zone(T.pad, "drawSecond", "Pad.drawSecond")
  zone(T.battlerHud, "drawOrder", "Hud.drawOrder")
  zone(T.battlerHud, "drawPanel", "Hud.drawPanel")
  zone(T.battlerHud, "drawRows", "Hud.drawRows")
  zone(T.screen2, "update", "Screen2.update (push)")
  zone(R.music_, "update", "music")
  zone(T.fx, "move", "Fx.move (a look starts)")
  -- what a slow frame is made of: resources made, sounds baked, played, decoded
  for _, k in ipairs({ "newShader", "newMesh", "newImage", "newCanvas", "newFont", "newImageData", "newSpriteBatch" }) do
    zone(love.graphics, k, "love.graphics." .. k)
  end
  for _, k in ipairs({ "newSoundData", "newDecoder" }) do zone(love.sound, k, "love.sound." .. k) end
  zone(love.audio, "newSource", "love.audio.newSource")
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and type(Audio) == "table" then
    for _, k in ipairs({ "playSe", "playCry", "prewarmSe", "_buildSeSoundData", "fadeOutBgm", "fadeOutAndPlay", "playBgm", "waitSe" }) do
      if type(Audio[k]) == "function" then zone(Audio, k, "Audio." .. k, true) end
    end
  end

  if os.getenv("PROFILE_SECOND") == "1" and T.screen2 then
    T.padSecond(true)
    T.screen2.bridge = { detected = function() return true end, available = function() return true end,
      setEnabled = function() end, push = function() return true end, pollTouch = function() return nil end }
  end

  -- each frame: the heap and the particles as counters, a collection and the raid's phase as marks
  local heapArg, partArg, warmArg = {}, {}, {}
  local heapC, partC, warmC
  local lastKb, lastPhase, frames = collectgarbage("count"), nil, 0
  local function sample()
    frames = frames + 1
    local kb = collectgarbage("count")
    heapArg.KB = kb
    heapC = AC.counter("Lua heap", heapArg, heapC)
    if kb < lastKb - 64 then AC.mark("GC (" .. math.floor(lastKb - kb) .. " KB freed)", "p") end
    lastKb = kb
    if frames % 6 == 0 and T.fx and T.fx.stats then
      partArg.parts = T.fx.stats().parts
      partC = AC.counter("particles", partArg, partC)
      local w = R.warmState and R.warmState()
      if w then
        warmArg.at, warmArg.of, warmArg.kept = w.i or 0, #(w.list or {}), w.kept or 0
        warmC = AC.counter("sounds warmed", warmArg, warmC)
      end
    end
    local cur = R.current and R.current()
    local ph = cur and cur.phase or "field"
    if ph ~= lastPhase then AC.mark("phase: " .. ph, "p"); lastPhase = ph end
    if frames % 120 == 0 then AC.flush() end
  end
  local function run(s, pred)
    local t0 = clock()
    while clock() - t0 < s do
      U.wait(1)
      sample()
      if pred and pred() then return true end
    end
    return false
  end

  local boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4"
  AC.mark("open " .. boss, "p")
  if os.getenv("PROFILE_DEN") == "1" then
    -- through the den screen, as a player comes: PROFILE_DEN_S (3) seconds on it, then START
    R.openDen({ x = 1, y = 1, active = true, stars = 4, boss = boss, day = 0 })
    run(tonumber(os.getenv("PROFILE_DEN_S")) or 3)
    R.denStart()
  else
    X.open(boss)
  end
  if os.getenv("PROFILE_GMAX") == "1" then
    run(2, function() local c = R.current(); return c and c.boss end)
    local b = R.current() and R.current().boss
    if b and b.gmax then b.moves = { b.gmax } end
  end
  run(30, function() local c = R.current(); return c and c.phase == "command" and not c.say end)

  local function bestMove(b)
    local k, best = 1, -1
    for i, mv in ipairs(b and b.moves or {}) do
      local p = tonumber(mv.power) or 0
      if p > best then k, best = i, p end
    end
    return k
  end
  local turn, seenCmd = 0, false
  local deadline = clock() + 240
  while X.state().active and clock() < deadline do
    local cur = R.current()
    if not cur then break end
    if cur.phase == "command" and not seenCmd then
      seenCmd = true
      turn = turn + 1
      AC.mark("turn " .. turn, "p")
      local w = R.warmState and R.warmState()
      if turn == 1 and w and R.keptSound then
        local miss = {}
        for _, name in ipairs(w.list or {}) do if not R.keptSound(name) then miss[#miss + 1] = tostring(name) end end
        log("not kept:", table.concat(miss, " "))
      end
      log("turn", turn, w and ("sounds warmed %d of %d, kept %d%s"):format(w.i or 0, #(w.list or {}), w.kept or 0, w.done and ", done" or "") or "")
    elseif cur.phase ~= "command" then
      seenCmd = false
    end
    if cur.phase == "command" and turn >= 3 and cur.boss and cur.boss.mon then
      cur.boss.mon.hp = math.min(cur.boss.mon.hp, 1)
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      local actor = cur.cmd.actor
      local m = cur.members[actor]
      run(0.5)
      R.choose("fight")
      run(0.4)
      if turn == 1 and actor == 1 and cur.sim.canDynamax and cur.sim:canDynamax(1) then
        R.choose("dynamax")
        run(0.4)
      end
      local k = bestMove(m and m.b)
      if R.current() and R.current().cmd then R.current().cmd.cursor = k end
      run(0.3)
      R.choose("move" .. k)
      local c2 = R.current() and R.current().cmd
      if c2 and c2.menu == "target" then
        run(0.4)
        local tk = 1
        for i, row in ipairs(c2.moveList or {}) do if row.live ~= false then tk = i; break end end
        R.choose("move" .. tk)
      end
      run(0.2)
    elseif cur.phase == "catch" then
      run(1.5)
      R.catchChoose("catch")
      run(1.0)
      local bi = 1
      local cc = R.current() and R.current().cmd
      for i, bl in ipairs(cc and cc.balls or {}) do
        if tostring(bl.name):upper():find("ULTRA") then bi = i end
      end
      if cc then cc.ball = bi end
      run(0.6)
      R.pickBall(bi)
      run(25, function() return not R.current() or R.current().phase == "rewards" end)
    elseif cur.phase == "rewards" then
      run(3)
      R.endRewards()
      run(15, function() return not X.state().active end)
    else
      run(1 / 60)
    end
  end
  run(2)
  AC.mark("done", "p")

  for i = #wrapped, 1, -1 do local w = wrapped[i]; w[1][w[2]] = w[3] end
  if os.getenv("PROFILE_SECOND") == "1" and T.screen2 then T.padSecond(false); T.screen2.bridge = false end
  AC.endSession()
  log(("%d frames over %d turns"):format(frames, turn))
  local data = love.filesystem.read(TRACE)
  local dir = os.getenv("SHOT_DIR")
  if data and dir then
    local f = io.open(dir .. "/" .. TRACE, "wb")
    if f then f:write(data); f:close(); log("trace:", dir .. "/" .. TRACE, ("%.1f MB"):format(#data / 1048576)) end
  else
    log("trace:", love.filesystem.getSaveDirectory() .. "/" .. TRACE, data and "" or "(MISSING)")
  end
end

return function(game)
  local log = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  love.event.quit()
end
