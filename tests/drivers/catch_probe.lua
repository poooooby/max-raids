-- Driver: the catch (the choice, the ball box, the throw step by step), the rewards card and the end
-- card. Opens PROBE_BOSS (default CHARIZARD_4), goes straight to the catch, throws the Great Ball (the
-- box's second) with the roll made sure; PROBE_FAIL=1 the roll stood in for a miss.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald --   POKEPORT_DRIVER=mods/max_raids/tests/drivers/catch_probe.lua love .

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached")
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON", "SPECIES_MUDKIP", "SPECIES_RALTS" }) do
      Party.giveMon(s0, C:require("species", sp), 30)
    end
  end
  local Bag = require("src.core.game3.bag")
  for _, k in ipairs({ "ITEM_POKE_BALL", "ITEM_GREAT_BALL", "ITEM_ULTRA_BALL", "ITEM_MASTER_BALL" }) do
    pcall(Bag.add, s0.bag, C:id("items", k), 5)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids is not loaded"); return end
  local ok, why = X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  log("open:", tostring(ok), tostring(why))
  if not waitFor(function() return X.state().phase == "command" end, 20000) then log("FAIL no commands"); return end
  local R = X.raid
  local fails = 0
  local function check(c, what) if not c then fails = fails + 1 end; log((c and "ok   " or "FAIL ") .. what) end
  local function after(s)
    local t0 = X.state().t or 0
    waitFor(function() return (X.state().t or 0) >= t0 + s end, 8000)
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  -- PROBE_FAIL=1: the throw fails (the roll stood in for)
  local Rw = X._test.rewards
  if Rw then
    local real = Rw.throw
    if os.getenv("PROBE_FAIL") == "1" then
      Rw.throw = function() return false, nil end
    else
      -- (a sure catch: the real throw with the Master Ball's odds, the ball thrown kept)
      Rw.throw = function(key, level, ball, rng)
        local sure = {}
        for k, v in pairs(ball) do sure[k] = v end
        sure.mult = 0
        return real(key, level, sure, rng)
      end
    end
  end
  R.startCatch()
  after(0.9)
  shot("c01_choice")
  check(X.state().phase == "catch", "the choice is up")
  U.tap(game, "a")
  U.wait(4)
  after(0.2)
  shot("c02_ballbox")
  local cur = R.current()
  log("balls:", #cur.cmd.balls)
  for i, b in ipairs(cur.cmd.balls) do log("  ", i, b.name, b.n, b.desc) end
  U.tap(game, "right")
  U.wait(4)
  after(0.2)
  shot("c03_ballbox_next")
  -- the ball shown is the one thrown (the Great Ball here); the roll stood in for a catch, or a miss
  log("throwing:", cur.cmd.balls[cur.cmd.ball].name)
  U.tap(game, "a")
  U.wait(2)
  check(X.state().phase == "throw", "Use throws it")
  local M = R.throwTimes()
  local t0 = cur.throw.t0
  local marks = { { 0.6, "c10_hold" }, { M.fly + 0.45, "c11_fly" }, { M.at + 0.08, "c12_flash" }, { M.suck + 0.5, "c13_suck" },
    { M.close + 0.1, "c14_close" }, { M.turn + 0.25, "c14b_turn" }, { M.fall + 0.3, "c15_fall" }, { M.land + 0.08, "c16_land" }, { M.check + 0.6, "c17_check1" },
    { M.check + 1.6, "c18_check2" }, { M.done + 0.25, "c19_flare" }, { M.shrink + 0.35, "c20_shrink" },
    { M.gotcha + 0.5, "c21_gotcha" }, { M.gotcha + 1.6, "c22_words" } }
  for _, m in ipairs(marks) do
    waitFor(function() return not R.current() or X.state().phase ~= "throw" or (X.state().t or 0) - t0 >= m[1] end, 8000)
    if X.state().phase ~= "throw" then break end
    shot(m[2])
  end
  waitFor(function() return X.state().phase == "rewards" end, 30000)
  check(X.state().phase == "rewards", "the rewards card")
  after(1.2)
  shot("c30_card")
  for _ = 1, 3 do U.tap(game, "down"); U.wait(3) end
  after(0.1)
  shot("c31_card_down")
  U.tap(game, "b")
  U.wait(3)
  after(0.1)
  shot("c32_card_next")
  U.tap(game, "a")
  U.wait(3)
  check(X.state().phase == "outro", "Next: the end card")
  after(0.6)
  shot("c40_outro")
  after(0.85)
  shot("c41_iris")
  waitFor(function() return X.state().phase ~= "outro" end, 8000)
  log("after the end card:", tostring(X.state().phase), tostring(X.state().active))
  log(("%d failures"):format(fails))
  if X.state().active then X.close() end
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
