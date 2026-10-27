-- Driver: a G-Max field over the team (PROBE_FIELD, FIRE by default: Wildfire's "burning up"), shot
-- over time from the wide view and over a member's shoulder, to see it move across the four.
-- Shots g*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/field_probe.lua love .

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
  local R, Sc = X.raid, X._test.scene
  X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  -- turns of Fight; the camera's shot at each effect resolving on a member (the field's burn at the
  -- turn's end, a G-Max move's status) - one member after another
  local realShot = Sc.shot
  local lastShot = nil
  Sc.shot = function(name, dur, i, ...)
    lastShot = tostring(type(name) == "table" and "pose" or name) .. (i and (" " .. i) or "")
    return realShot(name, dur, i, ...)
  end
  local seenEv, n, shotsTaken = nil, 0, 0
  local deadline = clock() + 150
  local turns, lastPhase = 0, nil
  while clock() < deadline and X.state().active and turns <= 5 do
    local cur = R.current()
    if not cur then break end
    if cur.phase == "command" and lastPhase ~= "command" then turns = turns + 1 end
    lastPhase = cur.phase
    local e = cur.events and cur.events[cur.evI]
    if e and e ~= seenEv then
      seenEv = e
      if e.kind == "residual" or e.kind == "status" or e.kind == "stage" then
        U.wait(2)
        local who = e.target or e.who
        log(("turn %d: %s on %s -> camera %s"):format(turns, e.kind, tostring(who and who.name), tostring(lastShot)))
        if e.kind == "residual" and shotsTaken < 4 then
          shotsTaken = shotsTaken + 1
          U.wait(20)
          shot("g2" .. shotsTaken .. "_residual")
        end
      end
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      if cur.cmd.menu == "main" then R.choose("fight") else R.choose("move1") end
    end
    U.wait(1)
  end
  Sc.shot = realShot
  X.close()
  log("done")
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
