-- Driver: the battle camera over each member's head, aimed at the boss. A party of a tall, a small
-- and two middling Pokemon (PROBE_TEAM, species names); for each member's own shot, the boss's shot
-- on it, its attack's and the party's spread: where its head lands up the screen (25-35% wanted,
-- more for one too tall to sit lower) and the boss's middle (the screen's middle). Shots cam_*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/camera_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  local team = os.getenv("PROBE_TEAM") or "WAILORD,TORCHIC,GARDEVOIR,STEELIX"
  for sp in team:gmatch("[^,]+") do Party.giveMon(s0, C:require("species", "SPECIES_" .. sp), 50) end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, Sc = X.raid, X._test.scene
  X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  if not waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000) then
    log("FAIL no commands"); X.close(); return
  end
  U.wait(30)
  local fails = 0
  local function up(x, y, z)
    local _, sy = Sc.project(x, y, z)
    if not sy then return -1 end
    return 1 - sy / (2 * Sc.cam.CY)
  end
  local function measure(label, name, i, lo, hi)
    Sc.shot(name, 0, i)
    U.wait(4)
    local who = i
    if not who then
      local t = 0
      for k = 1, 4 do if Sc.memberTopNow(k) > t then t, who = Sc.memberTopNow(k), k end end
    end
    local m = Sc.memberPos(who)
    local top = Sc.memberTopNow(who)
    local head = up(m.x, top, m.z)
    local bx, by, bz = Sc.bossMiddle()
    local mid = up(bx, by, bz)
    local eyeOver = Sc.eye[2] > top
    local ok = head >= lo - 0.01 and head <= hi + 0.01 and math.abs(mid - 0.5) < 0.03 and eyeOver
    if not ok then fails = fails + 1 end
    log(("%s %s: member %d top %.2f m, eye y %.2f, head %.0f%% up, boss middle %.0f%%"):format(
      ok and "ok  " or "FAIL", label, who, top, Sc.eye[2], 100 * head, 100 * mid))
    shot("cam_" .. label)
  end
  log(("boss size %.2f, tops %.2f %.2f %.2f %.2f"):format(Sc.bossSize, Sc.memberTop[1] or -1, Sc.memberTop[2] or -1,
    Sc.memberTop[3] or -1, Sc.memberTop[4] or -1))
  for i = 1, 4 do
    -- (one too tall to sit at 30% from BACK_MIN goes to HEAD_MAX; one too small stays at least HEAD_MIN)
    measure("member" .. i, "member", i, Sc.CHOOSE.HEAD_MIN, Sc.CHOOSE.HEAD_MAX)
    measure("target" .. i, "target", i, Sc.TARGET.HEAD_MIN, Sc.TARGET.HEAD_MAX)
    measure("attack" .. i, "attack", i, Sc.ATTACK.HEAD_MIN, Sc.ATTACK.HEAD_MAX)
  end
  -- (the party: the tallest's head at HEAD or higher - all four must fit across)
  measure("spread", "spread", nil, Sc.PARTY.HEAD, 0.6)
  -- (the shots are aimed again every frame while a member grows giant: solving them makes no garbage)
  Sc.giant[1] = 0.5
  local function solveAll(n)
    for _ = 1, n do
      for i = 1, 4 do Sc.targetShot(i, Sc.CHOOSE); Sc.targetShot(i) end
      Sc.partyShot()
    end
  end
  -- (once first: the JIT's traces are heap objects too)
  solveAll(100)
  collectgarbage("collect")
  collectgarbage("stop")
  local kb0 = collectgarbage("count")
  solveAll(100)
  local per = (collectgarbage("count") - kb0) * 1024 / 900
  collectgarbage("restart")
  Sc.giant[1] = 0
  local gOk = per < 16
  if not gOk then fails = fails + 1 end
  log(("%s the shots' solve: %.1f bytes of garbage a call"):format(gOk and "ok  " or "FAIL", per))
  X.close()
  log(fails == 0 and "PASS camera" or ("FAIL camera: " .. fails))
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
