-- Driver: Run (raid.lua Rd.askLeave / blowOut). From a den: Run asks "Leave the den?" with Yes / No
-- (No to start); No puts the commands back as they were; Run again, Yes: blown out of the den (the
-- gust, the words, white), back on the field, the den spent for the day. The question on the second
-- screen too (its D-pad left / right). Shots r*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/run_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local clock = love.timer.getTime
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function secs(s) local t0 = clock(); while clock() - t0 < s do U.wait(1) end end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
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
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 55)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, T = X.raid, X._test
  local den = { active = true, boss = "CHARIZARD_4", stars = 4 }

  local function toCommands()
    R.openDen(den)
    waitFor(function() return R.current() and R.current().t > 0.4 end, 300)
    R.denStart()
    waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
    U.wait(20)
  end
  toCommands()

  -- Run: the question, No to start
  check(R.choose("run"), "Run")
  U.wait(30)
  local r = R.current()
  check(r.phase == "leaveq" and r.cmd.menu == "yesno" and r.cmd.cursor == 2, "it asks, No selected")
  secs(1.2)
  shot("r01_question")
  -- No: the commands back
  U.tap(game, "a")
  U.wait(10)
  check(r.phase == "command" and r.cmd.menu == "main" and r.cmd.actor ~= nil, "No: the commands as they were")
  -- on the second screen: the question there, the D-pad across
  T.padSecond(true)
  local S2 = T.screen2
  if S2 then
    S2.bridge = { detected = function() return true end, available = function() return true end,
      setEnabled = function() end, push = function() return true end, pollTouch = function() return nil end }
  end
  R.choose("run")
  U.wait(10)
  U.tap(game, "left"); U.wait(4)
  check(r.cmd.cursor == 1, "second screen: left onto Yes")
  U.tap(game, "right"); U.wait(4)
  check(r.cmd.cursor == 2, "second screen: right back onto No")
  if S2 and T.pad and T.pad.drawSecond then
    local c = love.graphics.newCanvas(960, 840, { dpiscale = 1 })
    love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(0, 0, 0, 1)
    T.pad.drawSecond(love.graphics, 960, 840, r, nil)
    love.graphics.setCanvas(); love.graphics.pop()
    local d = c:newImageData()
    local f = io.open(dir .. "/r02_second_question.png", "wb")
    if f then f:write(d:encode("png"):getString()); f:close() end
    log("shot r02_second_question (drawn)")
  end
  U.tap(game, "b"); U.wait(10)
  T.padSecond(false)
  if S2 then S2.bridge = false end
  check(r.phase == "command", "B: No")

  -- Yes: blown out, the den spent
  R.choose("run")
  U.wait(10)
  U.tap(game, "up"); U.wait(4)
  check(r.cmd.cursor == 1, "up onto Yes")
  U.tap(game, "a")
  U.wait(4)
  check(r.phase == "blown", "Yes: blown out of the den")
  secs(0.5)
  shot("r03_blown")
  secs(0.8)
  shot("r04_blown_white")
  waitFor(function() return not X.state().active end, 1200)
  check(not X.state().active, "back on the field")
  check(den.done == true, "the den spent for the day")
  log(("%d failures"):format(fails))
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
