-- Driver: the catch with no Poke Balls. Catch says so ("You don't have any Poke Balls..."); the words
-- are put away - back to Catch / Don't Catch, on Don't Catch - by a tap (where Catch was: it must not
-- say it again), by B, and by a press on the second screen; then Don't Catch goes to the rewards.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/no_balls_probe.lua love .

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
  if #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON" }) do Party.giveMon(s0, C:require("species", sp), 30) end
  end
  U.wait(10)
  local X = game.mods.exports.max_raids
  local R = X.raid
  X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  waitFor(function() local c = R.current(); return c and c.phase == "command" and not c.say end, 20000)
  R.startCatch()
  local r = R.current()
  r.cmd.balls, r.cmd.cursor = {}, 1
  U.wait(20)
  local W = R.catchWhere
  local cx, cy = W.catch.x + W.catch.w / 2, W.catch.y + W.catch.h / 2
  check(W.catch.w ~= nil, "the choice drawn (Catch at " .. math.floor(cx) .. ", " .. math.floor(cy) .. ")")
  local function sayUp() return R.current().say ~= nil end
  local function tapAt(x, y)
    R.pointer({ x = x, y = y, phase = "pressed" })
    U.wait(2)
    R.pointer({ x = x, y = y, phase = "released" })
    U.wait(2)
  end

  R.catchChoose("catch")
  U.wait(30)
  check(sayUp(), "Catch with no balls: the words")
  tapAt(cx, cy)
  check(not sayUp(), "a tap where Catch was: the words put away, not said again")
  check(R.current().phase == "catch" and R.current().cmd.menu == "catchq" and R.current().cmd.cursor == 2,
    "back to the choice, on Don't Catch")

  R.catchChoose("catch")
  U.wait(30)
  tapAt(5, 5)
  check(not sayUp(), "a tap anywhere: the words put away")

  R.catchChoose("catch")
  U.wait(30)
  U.tap(game, "b")
  U.wait(3)
  check(not sayUp(), "B: the words put away")

  R.catchChoose("catch")
  U.wait(30)
  U.tap(game, "a")
  U.wait(3)
  check(not sayUp() and R.current().cmd.cursor == 2, "A: the words put away, on Don't Catch")

  R.catchChoose("catch")
  U.wait(30)
  R.secondPress("catch", false)
  R.secondPress("catch", true)
  U.wait(3)
  check(not sayUp(), "a press on the second screen: the words put away")

  R.catchChoose("leave")
  U.wait(5)
  check(R.current().phase == "rewards", "Don't Catch: the rewards")
  X.close()
  U.wait(10)
  log(("%d failures"):format(fails))
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
