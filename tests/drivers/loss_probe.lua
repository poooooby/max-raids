-- Driver: a lost raid. From a den, three knock-outs already counted and the four at 1 HP, so the
-- boss's first blow loses the raid; the turn's events played through Rd.update itself (each call
-- checked for an error) until the raid closes: back on the field, the den left active.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/loss_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
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
  for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_MUDKIP", "SPECIES_TREECKO", "SPECIES_RALTS" }) do
    Party.giveMon(s0, C:require("species", sp), 10)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R = X.raid
  local den = { active = true, boss = "CHARIZARD_4", stars = 4 }
  R.openDen(den)
  waitFor(function() return R.current() and R.current().t > 0.4 end, 300)
  R.denStart()
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  check(X.state().phase == "command", "the commands (" .. tostring(X.state().phase) .. ")")
  if X.state().phase ~= "command" then return end
  local r = R.current()
  -- the raid one knock-out from lost
  r.sim.faints = (r.sim.rules.FAINTS or 4) - 1
  for _, m in ipairs(r.members) do m.b.mon.hp = 1 end
  local outcome
  -- the four choose their first move
  for _ = 1, 8 do
    local c = r.cmd
    if r.phase ~= "command" or not c or not c.actor then break end
    if c.menu == "main" then R.choose("fight") else R.choose("move1") end
    if c.menu == "target" then R.choose("move1") end
  end
  check(r.phase == "battle", "the turn is played (" .. tostring(r.phase) .. ")")
  -- the events, through Rd.update itself
  local errors, frames = 0, 0
  while R.current() and frames < 6000 do
    local ok, err = pcall(R.update, 1 / 30)
    if not ok then
      errors = errors + 1
      log("update error:", tostring(err))
      break
    end
    outcome = r.sim and r.sim.over or outcome
    frames = frames + 1
  end
  log("outcome", tostring(outcome), "after", frames, "updates")
  check(errors == 0, "Rd.update ran the lost raid's events with no error")
  check(outcome == "faints", "the raid was lost to knock-outs")
  check(not X.state().active, "the raid closed: back on the field")
  check(not den.done, "the den left active (a loss does not spend it)")
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
