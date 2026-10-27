-- Driver: the battle pad on the second screen (src/screen2.lua): the display stood in for (it keeps
-- the frames pushed, saved as PNGs, and hands back taps), the quad's commands, a held button, the
-- moves, the pouch, Back, a pick; then the main screen's pad (the emblems).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald --   POKEPORT_DRIVER=mods/max_raids/tests/drivers/screen2_probe.lua love .

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
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON", "SPECIES_MUDKIP", "SPECIES_RALTS" }) do
      Party.giveMon(s0, C:require("species", sp), 30)
    end
  end
  local Bag = require("src.core.game3.bag")
  for _, k in ipairs({ "ITEM_POKE_BALL", "ITEM_GREAT_BALL", "ITEM_ULTRA_BALL" }) do
    pcall(Bag.add, s0.bag, C:id("items", k), 5)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids is not loaded"); return end
  local ok, why = X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  log("open:", tostring(ok), tostring(why))
  local R = X.raid
  local fails = 0
  local function check(c, what) if not c then fails = fails + 1 end; log((c and "ok   " or "FAIL ") .. what) end
  local function after(s)
    local t0 = X.state().t or 0
    waitFor(function() return (X.state().t or 0) >= t0 + s end, 8000)
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  -- the display stood in for: it keeps the last frame pushed and hands back queued taps
  local S2 = X._test.screen2
  local queue, last, pushes = {}, nil, 0
  S2.bridge = {
    detected = function() return true end, available = function() return true end,
    setEnabled = function() end,
    push = function(data, w, h) pushes = pushes + 1; last = data:clone(); return true end,
    pollTouch = function() return table.remove(queue, 1) end,
  }
  local function frame(name)
    local t0 = pushes
    waitFor(function() return pushes >= t0 + 2 end, 600)
    if last then
      local fd = last:encode("png")
      local f = io.open(dir .. "/" .. name .. ".png", "wb")
      if f then f:write(fd:getString()); f:close() end
      log("frame", name, last:getWidth() .. "x" .. last:getHeight())
    else
      log("FAIL no frame", name)
    end
  end
  local function tap(id, up)
    local t = nil
    local W = X._test.pad.sWhere
    if id == "back" then t = W.back else for _, c in ipairs(W.cells) do if c.id == id then t = c end end end
    if not t then log("FAIL no cell", id); return end
    local x, y = math.floor(t.x + t.w / 2), math.floor(t.y + t.h / 2)
    queue[#queue + 1] = ("down,%d,%d"):format(x, y)
    if up ~= false then queue[#queue + 1] = ("up,%d,%d"):format(x, y) end
  end
  X._test.padSecond(true)
  if not waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000) then log("FAIL no commands"); return end
  after(0.3)
  frame("q01_commands")
  shot("q01_main")
  check(S2.state.pushes > 0, "frames pushed to the second screen")
  U.tap(game, "down")
  U.wait(3)
  frame("q02_cursor_pokemon")
  -- a finger held on Bag: pressed in
  tap("bag", false)
  frame("q03_held_bag")
  queue[#queue + 1] = "cancel,0,0"
  frame("q03b_let_go")
  -- Fight: the moves
  tap("fight")
  waitFor(function() return X.state().menu == "moves" end, 300)
  check(X.state().menu == "moves", "a tap on Fight opens the moves")
  frame("q04_moves")
  tap("back")
  waitFor(function() return X.state().menu == "main" end, 300)
  check(X.state().menu == "main", "Back")
  tap("bag")
  waitFor(function() return X.state().menu == "items" end, 300)
  frame("q05_items")
  tap("back")
  waitFor(function() return X.state().menu == "main" end, 300)
  tap("fight")
  waitFor(function() return X.state().menu == "moves" end, 300)
  frame("q05b_moves_again")
  tap("move1")
  waitFor(function() return X.state().actor == 2 end, 300)
  check(X.state().actor == 2, "a move picked: the next member")
  frame("q06_second_member")
  -- the catch on the second screen: Catch / Don't Catch, the ball box, a ball thrown
  R.startCatch()
  after(0.9)
  frame("q10_catch_choice")
  shot("q10_catch_main")
  tap("catch")
  waitFor(function() return R.current().cmd.menu == "ballbox" end, 300)
  check(R.current().cmd.menu == "ballbox", "Catch opens the ball box")
  frame("q11_ballbox")
  tap("right")
  waitFor(function() return R.current().cmd.ball == 2 end, 300)
  check(R.current().cmd.ball == 2, "the right arrow: the next ball")
  frame("q12_ballbox_next")
  tap("use", false)
  frame("q13_use_held")
  queue[#queue + 1] = "cancel,0,0"
  tap("back")
  waitFor(function() return R.current().cmd.menu == "catchq" end, 300)
  check(R.current().cmd.menu == "catchq", "Back to Catch / Don't Catch")
  tap("catch")
  waitFor(function() return R.current().cmd.menu == "ballbox" end, 300)
  frame("q13b_ballbox_again")
  tap("use")
  waitFor(function() return X.state().phase == "throw" end, 300)
  check(X.state().phase == "throw", "Use throws the ball")
  after(1.0)
  frame("q14_during_throw")
  -- the main screen's pad as it stands with the second screen off (the emblems)
  do
    -- (out of the throw: a fresh raid for the main screen's pad)
    X.close()
    U.wait(10)
    X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
    -- (a raid after a catch: nothing of the last one's shake carries over)
    U.wait(5)
    local sh = X._test.scene._shake
    -- (a shake left from the last raid would sit ahead of the new clock)
    check(sh ~= nil and not (sh.amp > 0 and sh.t0 > (X.state().t or 0)), "the new raid starts with no carried shake")
    log("shake after reopening:", sh and sh.amp, sh and sh.t0, "clock", X.state().t)
    after(1.5)
    shot("q09_reopen_intro")
    waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  end
  X._test.padSecond(false)
  after(0.3)
  shot("q07_main_pad")
  U.tap(game, "down"); U.wait(2); U.tap(game, "down"); U.wait(2); U.tap(game, "down"); U.wait(2)
  after(0.2)
  shot("q08_main_pad_run")
  log("pushes:", pushes)
  log(("%d failures"):format(fails))
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
