-- Driver: where a raid frame's Lua time and garbage go, part by part, in each of its busy states -
-- the commands, a G-Max move playing (its effects at their height), the catch mid-wobble, the
-- rewards card - and whole frames (update + draw) in each. For each part: the time per call and the
-- Lua heap it allocates per call with the collector stopped (what a low-power device's GC sweeps
-- every frame). On the desktop the ratios carry to the Thor, the absolute times do not.
-- Each figure has a budget (BUDGET below, KB of garbage a call / ms a call); one over it is a FAIL,
-- so a change that makes a frame churn shows here. PERF_STRICT=0 logs without failing.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/perf_parts.lua love .

-- garbage (KB) and time (ms) a call may take before it fails; the frame totals are what matters
local BUDGET = {
  ["frame (update + draw)"] = { kb = 96, ms = 12 },
  ["Rd.update (1/60)"] = { kb = 48, ms = 6 },
  ["Rd.draw (whole window)"] = { kb = 64, ms = 8 },
  ["Scene.prepare (the 3D den)"] = { kb = 8, ms = 4 },
  ["Scene.draw (den + sprites)"] = { kb = 16, ms = 4 },
  ["Fx.update"] = { kb = 16, ms = 2 },
  ["Fx.draw (front layer + screen)"] = { kb = 32, ms = 4 },
  ["Fx.drawLayer back + mid"] = { kb = 32, ms = 4 },
  ["Pad.draw (main screen)"] = { kb = 16, ms = 2 },
  ["Pad.drawSecond (960x840)"] = { kb = 24, ms = 4 },
  ["Screen2.update (the push)"] = { kb = 24, ms = 6 },
  ["BattlerHud.drawOrder + panel"] = { kb = 12, ms = 2 },
  ["Rd.drawThrow"] = { kb = 32, ms = 4 },
  ["Rd.drawRewards"] = { kb = 16, ms = 3 },
}

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
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
  local R = X.raid
  local T = X._test
  local Sc, Fx, Pad, Hud, S2 = T.scene, T.fx, T.pad, T.battlerHud, T.screen2
  local strict = os.getenv("PERF_STRICT") ~= "0"
  local fails = 0
  local G = love.graphics
  local W, H = 1280, 720
  local canvas = G.newCanvas(W, H, { dpiscale = 1 })
  local second = G.newCanvas(960, 840, { dpiscale = 1 })
  -- a draw into a canvas of the window's size (as the raid draws over the window)
  local function into(c, f)
    G.push("all")
    G.origin()
    G.setCanvas(c)
    G.clear(0, 0, 0, 1)
    f(G)
    G.setCanvas()
    G.pop()
  end
  local clock = love.timer.getTime

  -- time and garbage per call, the collector held meanwhile; checked against its budget
  local function measure(label, f, n)
    n = n or 60
    f() -- (once first: lazily made fonts, meshes, shaders are not per-frame cost)
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    local t0 = clock()
    for _ = 1, n do f() end
    local dt = (clock() - t0) * 1000 / n
    local kb = (collectgarbage("count") - kb0) / n
    collectgarbage("restart")
    local b = BUDGET[label]
    local over = b and (kb > b.kb or dt > b.ms)
    if over and strict then fails = fails + 1 end
    log(("%s%-34s %7.3f ms %8.2f KB garbage a call%s"):format(over and "FAIL " or "     ", label, dt, kb,
      b and ("   (budget %d KB, %d ms)"):format(b.kb, b.ms) or ""))
  end

  -- frames a second, live: the raid running as it plays for `seconds` of wall time - the frames
  -- counted and the slowest one (a driver run is not held to 60, so on the desktop this is the
  -- headroom; on the Thor the real figure). FPS_MIN below fails it.
  -- (the desktop holds a run to its display's 60 with vsync: a little under it passes; a single frame
  -- longer than two of them, a hitch, fails)
  local FPS_MIN = tonumber(os.getenv("PERF_FPS_MIN")) or 57
  local HITCH_MS = tonumber(os.getenv("PERF_HITCH_MS")) or 34
  local function fps(label, seconds)
    seconds = seconds or 2
    local t0 = clock()
    local last, worst, n = t0, 0, 0
    while clock() - t0 < seconds do
      U.wait(1)
      local now = clock()
      worst = math.max(worst, now - last)
      last = now
      n = n + 1
    end
    local f = n / (clock() - t0)
    local low = f < FPS_MIN or worst * 1000 > HITCH_MS
    if low and strict then fails = fails + 1 end
    log(("%s%-34s %7.1f fps, slowest frame %.1f ms%s"):format(low and "FAIL " or "     ", "fps: " .. label, f, worst * 1000,
      ("   (at least %d, no frame over %d ms)"):format(FPS_MIN, HITCH_MS)))
  end

  -- every part of a frame, in the state the raid is in now
  local function parts(state, opts)
    opts = opts or {}
    local r = R.current()
    log(("---- %s (phase %s, particles %s)"):format(state, tostring(r and r.phase),
      tostring(Fx and Fx.stats and Fx.stats().parts)))
    -- (the draws hold the clock: the same frame drawn again and again)
    measure("Rd.draw (whole window)", function() into(canvas, function(g) R.draw(g, W, H) end) end)
    measure("Scene.draw (den + sprites)", function()
      into(canvas, function(g) Sc.draw(g, 0, 0, W, H, r.t, nil, nil) end)
    end)
    if Fx then
      measure("Fx.drawLayer back + mid", function()
        into(canvas, function(g) Fx.drawLayer(g, "back", r.t); Fx.drawLayer(g, "mid", r.t) end)
      end)
      measure("Fx.draw (front layer + screen)", function() into(canvas, function(g) Fx.draw(g, W, H, r.t) end) end)
    end
    if opts.pad and Pad then
      measure("Pad.draw (main screen)", function() into(canvas, function(g) Pad.draw(g, W, H, r) end) end)
      measure("Pad.drawSecond (960x840)", function() into(second, function(g) Pad.drawSecond(g, 960, 840, r, nil) end) end)
    end
    if opts.hud and Hud and r.cmd then
      measure("BattlerHud.drawOrder + panel", function()
        into(canvas, function(g)
          Hud.drawOrder(g, W, H, r.members, r.cmd, r.t)
          Hud.drawPanel(g, W, H, r.cmd.actor and r.members[r.cmd.actor])
        end)
      end)
    end
    if opts.throw then measure("Rd.drawThrow", function() into(canvas, function(g) R.drawThrow(g, W, H) end) end) end
    if opts.rewards then measure("Rd.drawRewards", function() into(canvas, function(g) R.drawRewards(g, W, H) end) end) end
    measure("Scene.prepare (the 3D den)", function() Sc.prepare(r.t) end, 30)
    -- (these advance the raid: last)
    if Fx then measure("Fx.update", function() Fx.update(r.t + 1 / 60) end) end
    if opts.update ~= false then
      measure("Rd.update (1/60)", function() R.update(1 / 60) end, 30)
      measure("frame (update + draw)", function()
        R.update(1 / 60)
        into(canvas, function(g) R.draw(g, W, H) end)
      end, 30)
    end
  end

  local ok, why = X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  log("open:", tostring(ok), tostring(why))
  if not waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000) then
    log("FAIL no commands"); return
  end
  U.wait(30)
  fps("the commands")
  parts("the commands", { pad = true, hud = true })

  -- the second screen's push (a display stood in for: frames taken and dropped)
  if S2 then
    T.padSecond(true)
    S2.bridge = { detected = function() return true end, available = function() return true end,
      setEnabled = function() end, push = function() return true end, pollTouch = function() return nil end }
    log("---- the second screen")
    measure("Screen2.update (the push)", function()
      S2.state.pushAt = -1   -- (due every call)
      S2.update()
    end, 30)
    T.padSecond(false)
    S2.bridge = false
  end

  -- a G-Max move at its height: Wildfire's wall of fire over the party, and a slab after it
  local a = R.testLook({ "wave", shape = "fire" }, "FIRE", "boss", { 1, 2, 3, 4 }, true, 0.3)
  if a then
    local t0 = X.state().t
    waitFor(function() return (X.state().t or 0) >= t0 + (a.at - t0) + (a.impact or 0.5) * 0.6 end, 4000)
    fps("a G-Max move playing", 1)
    parts("a G-Max move (Wildfire) at its height", { update = false })
    R.testLook({ "drop", shape = "slab" }, "ROCK", "boss", { 1, 2, 3, 4 }, false, 0.3)
    local t1 = X.state().t
    waitFor(function() return (X.state().t or 0) >= t1 + 1.2 end, 4000)
    parts("the slab breaking up")
  end

  -- the catch mid-wobble, then the card
  R.startCatch()
  U.wait(5)
  R.pickBall(1)
  local M = R.throwTimes()
  local th0 = R.current().throw and R.current().throw.t0 or 0
  waitFor(function() return (X.state().t or 0) - th0 >= M.fly + 0.2 end, 8000)
  fps("the catch (throw to wobbles)", 2)
  waitFor(function() return (X.state().t or 0) - th0 >= M.check + 0.6 end, 8000)
  parts("the catch, wobbling in its crater", { throw = true, update = false })
  waitFor(function() return X.state().phase == "rewards" end, 30000)
  U.wait(30)
  fps("the rewards card", 1)
  parts("the rewards card", { rewards = true, update = false })
  X.close()
  log(("%d over budget"):format(fails))
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
