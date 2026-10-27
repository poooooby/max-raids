-- Driver: frame by frame through a big move from cold - G-Max Wildfire over the four, then the slab -
-- each frame's wall time, whether the hit-stop held the raid's clock, the Lua heap and where the
-- time went (the raid's update / draw, Fx, the scene, wrapped where they are called through their
-- tables). Any frame over HITCH_MS is listed with what ran in it.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/hitch_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, T = X.raid, X._test
  local HITCH_MS = tonumber(os.getenv("PERF_HITCH_MS")) or 25
  local clock = love.timer.getTime

  -- time spent in each wrapped function this frame
  local spent, calls = {}, {}
  local function wrap(tbl, name, label)
    local f = tbl and tbl[name]
    if type(f) ~= "function" then return end
    tbl[name] = function(...)
      local t0 = clock()
      local a, b, c, d = f(...)
      spent[label] = (spent[label] or 0) + (clock() - t0)
      return a, b, c, d
    end
  end
  wrap(R, "update", "Rd.update")
  wrap(R, "draw", "Rd.draw")
  wrap(R, "impact", "Rd.impact")
  wrap(R, "se", "Rd.se")
  wrap(T.fx, "update", "Fx.update")
  wrap(T.fx, "draw", "Fx.draw")
  wrap(T.fx, "drawLayer", "Fx.drawLayer")
  wrap(T.scene, "prepare", "Scene.prepare")
  wrap(T.scene, "draw", "Scene.draw")
  wrap(T.scene, "hit", "Scene.hit")
  local Audio = package.loaded["src.core.game3.audio"] or package.loaded["src.audio"]
  if Audio then wrap(Audio, "playSe", "Audio.playSe") end
  local origSe = Audio and Audio.playSe
  if Audio then
    local f = Audio.playSe
    Audio.playSe = function(id, ...) calls[#calls + 1] = "se " .. tostring(id); return f(id, ...) end
  end
  local _ = origSe

  if os.getenv("PROBE_COLD") == "1" then R.stepWarm = function() end end
  -- the den screen first, as a raid begins: how long its sounds take to bake there, its slowest frame
  if os.getenv("PROBE_COLD") ~= "1" then
    R.openDen({ active = true, boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4" })
    local t0, last, worst, n = clock(), clock(), 0, 0
    for _ = 1, 1200 do
      local w = R.warmState()
      if w and w.done then break end
      U.wait(1)
      local now = clock()
      worst = math.max(worst, now - last)
      last, n = now, n + 1
    end
    local w = R.warmState()
    log(("the den screen: %s of %s sounds kept in %d frames (%.2f s), slowest frame %.1f ms"):format(
      tostring(w and w.kept), tostring(w and #w.list), n, clock() - t0, worst * 1000))
    R.close()
    U.wait(10)
  end
  local ok, why = X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  log("open:", tostring(ok), tostring(why))
  if not waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000) then
    log("FAIL no commands"); return
  end
  U.wait(30)

  -- the raid's sounds baking ahead (Rd.stepWarm): until the list is through or the cache is full
  if os.getenv("PROBE_COLD") ~= "1" then
    local t0, last, worst = clock(), clock(), 0
    for _ = 1, 1200 do
      local w = R.warmState()
      if w and w.done then break end
      U.wait(1)
      local now = clock()
      worst = math.max(worst, now - last)
      last = now
    end
    local w = R.warmState()
    log(("sounds baked ahead: %s kept of %s in %.1f s (slowest frame %.1f ms)"):format(
      tostring(w and w.kept), tostring(w and #w.list), clock() - t0, worst * 1000))
    if w then log("  " .. table.concat(w.list, " ")) end
  end

  local function trace(label, seconds)
    log("---- " .. label)
    local t0 = clock()
    local last = t0
    local n, worst, hitches, stopFrames = 0, 0, 0, 0
    local kb0 = collectgarbage("count")
    while clock() - t0 < seconds do
      for k in pairs(spent) do spent[k] = nil end
      for i = #calls, 1, -1 do calls[i] = nil end
      local kbA = collectgarbage("count")
      U.wait(1)
      local now = clock()
      local dt = (now - last) * 1000
      last = now
      n = n + 1
      local r = R.current()
      local stop = r and (r.hitStop or 0) > 0
      if stop then stopFrames = stopFrames + 1 end
      worst = math.max(worst, dt)
      local kb = collectgarbage("count")
      if dt > HITCH_MS then
        hitches = hitches + 1
        local parts = {}
        for k, v in pairs(spent) do if v * 1000 >= 0.5 then parts[#parts + 1] = ("%s %.1f"):format(k, v * 1000) end end
        table.sort(parts)
        log(("  HITCH frame %d at %.2f s: %.1f ms (raid t %.2f, hitStop %s, heap %+.0f KB%s) %s %s"):format(n,
          now - t0, dt, r and r.t or -1, tostring(stop), kb - kbA, kb < kbA and " (GC ran)" or "",
          table.concat(parts, ", "), table.concat(calls, " ")))
      end
    end
    log(("  %d frames, %.1f fps, slowest %.1f ms, %d over %d ms, %d frames in hit-stop, heap %+.0f KB"):format(n,
      n / (clock() - t0), worst, hitches, HITCH_MS, stopFrames, collectgarbage("count") - kb0))
  end

  -- the boss's own G-Max move over the four, then its first move on one, each twice; the sounds each
  -- plays, kept or not (PROBE_COLD=1: the looks before anything is baked, for the stall it was)
  local boss = R.current().boss
  local S = T.sounds
  local looks = {}
  if boss and boss.gmax then
    looks[#looks + 1] = { name = "G-Max " .. tostring(boss.gmax.name or boss.gmax.key), mv = boss.gmax, onto = { 1, 2, 3, 4 }, gmax = true }
  end
  if boss and boss.moves and boss.moves[1] then
    looks[#looks + 1] = { name = tostring(boss.moves[1].name or boss.moves[1].key), mv = boss.moves[1], onto = { 2 } }
  end
  for pass = 1, 2 do
    for _, L in ipairs(looks) do
      local spec = R.specOf(L.mv)
      local se = S.moveSe(spec, L.mv.typeName)
      local land = S.LAND[spec.shape or ""] or S.LAND[spec[1] or ""]
      log(("%s: %s %s, sounds %s (kept %s)%s"):format(L.name, tostring(spec[1]), tostring(spec.shape), tostring(se),
        tostring(R.keptSound(se)), land and (", " .. land .. " (kept " .. tostring(R.keptSound(land)) .. ")") or ""))
      R.testLook(spec, L.mv.typeName, "boss", L.onto, L.gmax, 0.3)
      trace(L.name .. (pass == 1 and " (first time)" or " (again)"), 4)
    end
  end
  X.close()
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local logFile = io.open(dir .. "/driver.log", "w")
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
