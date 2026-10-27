-- Driver: a Max Raid opened straight from the field (no den yet): the intro's shots, the commands,
-- then Run.
-- Gives a party of four (a National Dex Gen 4+ species among them), opens PROBE_BOSS (default
-- CHARIZARD_4), shoots the close-up, the pull back, the roar, "appeared!", over the first member's
-- shoulder; walks the commands (a pick, the selection moving, B back, all four in, the next
-- turn: r07-r10; Pokemon's summary and B out of it: r11-r12); then taps Run on the pad and checks the layer and the boss's sheet are gone.
--   SHOT_DIR=<dir> SHOT_W=1280 SHOT_H=720 POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/raid_probe.lua love .

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
  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log((ok and "ok   " or "FAIL ") .. what)
    return ok
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of("emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 30)
    local lucario = Pokemon.speciesFromNational and Pokemon.speciesFromNational(448)
    log("Lucario's slot (National Dex Gen 3):", tostring(lucario))
    if lucario then Party.giveMon(s0, lucario, 30) end
    Party.giveMon(s0, C:require("species", "SPECIES_RALTS"), 30)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not check(X ~= nil, "max_raids is loaded") then return end
  local key = os.getenv("PROBE_BOSS") or "CHARIZARD_4"
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local TCb = package.loaded["src.core.TouchControls"]
  local before = type(TCb) == "table" and TCb.enabled or nil
  log("engine touch pad before the raid: enabled", tostring(before))
  local ok, why = X.open(key)
  check(ok == true, "the raid opens: " .. tostring(why))
  local Stack = require("src.ui.game3.stack")
  check(Stack.has and Stack.has("max_raids"), "its layer is up")
  log("song:", tostring(X.state().song))
  for _, at in ipairs({ { 0.6, "r01_close" }, { 2.5, "r02_pullback" }, { 3.75, "r03_roar" }, { 4.15, "r04a_typing" },
    { 5.2, "r04_appeared" }, { 7.6, "r05_member" } }) do
    waitFor(function() return (X.state().t or 0) >= at[1] end, 6000)
    shot(at[2])
  end
  check(X.state().phase == "command", "the intro hands over to the commands")
  -- the engine's touch pad stands down while the raid's pad is on the main screen
  local okTC, TC = pcall(require, "src.core.TouchControls")
  if okTC and type(TC) == "table" then
    log("engine touch pad during the raid: enabled", tostring(TC.enabled))
    check(TC.enabled == false, "the engine's touch pad is hidden during the raid")
  end
  -- the commands: each member in turn, the selection moving, B stepping back
  local R = X.raid
  local function after(s) local t0 = X.state().t or 0; waitFor(function() return (X.state().t or 0) >= t0 + s end, 6000) end
  local st = X.state()
  check(st.turn == 1 and st.actor == 1 and st.chosen == 0, ("turn 1, the first member choosing (turn %s actor %s chosen %s)")
    :format(tostring(st.turn), tostring(st.actor), tostring(st.chosen)))
  after(0.3)
  shot("r07_cmd_first")
  U.tap(game, "down")
  U.wait(4)
  check(X.state().cursor == 2, "down moves the selection to Pokemon")
  shot("r08_cmd_cursor")
  U.tap(game, "up")
  U.wait(2)
  U.tap(game, "a")
  U.wait(4)
  check(X.state().menu == "moves" and X.state().actor == 1, "A on Fight opens the moves")
  after(0.3)
  shot("r09a_moves")
  U.tap(game, "a")
  U.wait(4)
  check(X.state().actor == 2 and X.state().chosen == 1, "A on a move: the second member's turn")
  after(0.8)
  shot("r09_cmd_second")
  U.tap(game, "b")
  U.wait(4)
  check(X.state().actor == 1 and X.state().chosen == 0, "B steps back to the first, its pick undone")
  local function pick() R.choose("fight"); R.choose("move1") end
  pick(); pick(); pick()
  after(0.8)
  check(X.state().actor == 4 and X.state().chosen == 3, "three in, the fourth choosing")
  shot("r10_cmd_fourth")
  pick()
  check(X.state().phase == "battle", "all four in: the turn is fought")
  -- the turn's events, logged; shots as the first move lands and as the first hit drains a bar
  local cur = R.current()
  for i, e in ipairs(cur and cur.events or {}) do
    log(("  event %d %s %s%s"):format(i, e.kind, e.text or "", e.amount and (" -" .. e.amount .. " -> " .. tostring(e.hp)) or ""))
  end
  local bossHp0 = cur and cur.boss and cur.boss.mon.hp
  waitFor(function() local c = R.current(); return not c or (c.events and c.evI >= 1) end, 6000)
  after(0.4)
  shot("r10a_turn_use")
  waitFor(function() local c = R.current(); local e = c and c.events and c.events[c.evI]; return not c or (e and e.kind == "damage") end, 6000)
  after(0.3)
  shot("r10b_turn_hit")
  -- a member hit (its row at the top left, the boss's block away)
  local function memberHit()
    local c = R.current()
    local e = c and c.events and c.events[c.evI]
    return not c or not c.events or (e and e.kind == "damage" and e.target and not e.target.boss)
  end
  if waitFor(memberHit, 6000) and R.current() and R.current().events then
    after(0.3)
    shot("r10d_member_hit")
  end
  waitFor(function() return not X.state().active or X.state().phase == "command" end, 20000)
  if not X.state().active then
    log("the raid ended in its first turn")
  else
    st = X.state()
    check(st.turn == 2 and st.actor ~= nil and st.chosen == 0, ("then the next turn's commands (turn %s actor %s)"):format(tostring(st.turn), tostring(st.actor)))
    after(0.8)
    -- the boss's status tag (PROBE_TAG=BRN etc.: set for the shot)
    local tag = os.getenv("PROBE_TAG")
    if tag and R.current() and R.current().boss then R.current().boss.status = tag end
    shot("r10c_turn2")
    -- Pokemon: the game's summary of the member choosing; B closes it and the raid takes no B
    local first = st.actor
    pick()
    after(0.8)
    local second = X.state().actor
    R.cursorTo(2)
    U.tap(game, "a")
    waitFor(function() return X.state().summary end, 120)
    check(X.state().summary, "Pokemon opens the summary")
    check(Stack.has and Stack.has("summary"), "the summary's layer is up")
    U.wait(30)
    shot("r11_summary")
    U.tap(game, "b")
    waitFor(function() return not X.state().summary end, 600)
    U.wait(10)
    st = X.state()
    check(not st.summary and st.actor == second and st.chosen == 1,
      ("B closes it; the same member's turn (actor %s chosen %s, first %s)"):format(tostring(st.actor), tostring(st.chosen), tostring(first)))
    shot("r12_after_summary")
    -- PROBE_FULL=1: play the raid to its end (every member's first move with PP), the words hurried
    if os.getenv("PROBE_FULL") == "1" then
      local turns = 0
      while X.state().active and turns < 40 do
        if X.state().phase == "command" then
          local c = R.current()
          local m = c.members[c.cmd.actor]
          local slot = 1
          for k, mv in ipairs(m.b.moves) do if (mv.pp or 0) > 0 then slot = k; break end end
          R.choose("fight"); R.choose("move" .. slot)
          if X.state().phase == "battle" then
            turns = turns + 1
            for _, e in ipairs(R.current().events or {}) do if e.text then log(("  t%d %s"):format(turns, e.text)) end end
          end
        elseif X.state().phase == "battle" then
          R.playEvents(true)
        end
        U.wait(1)
      end
      log("full raid: turns", turns, "active after", tostring(X.state().active))
      check(not X.state().active, "the raid ends (won, or blown out)")
      return log(("%d failures"):format(fails))
    end
  end
  -- FLEE on the pad: a touch (PROBE_TOUCH=1) or a click
  local w = X._test.pad.where.flee
  if check(w and w.w, "the pad's FLEE is placed") then
    local x, y = w.x + w.w / 2, w.y + w.h / 2
    if os.getenv("PROBE_TOUCH") == "1" then
      love.touchpressed("probe", x, y, 0, 0, 1); U.wait(2); love.touchreleased("probe", x, y, 0, 0, 1); U.wait(4)
    else
      love.mousepressed(x, y, 1, false, 1); U.wait(2); love.mousereleased(x, y, 1, false, 1); U.wait(4)
    end
    log("after the FLEE press: active", tostring(X.state().active))
    check(not X.state().active, "FLEE on the pad closes the raid")
  end
  if X.state().active then X.close() end
  U.wait(10)
  check(not X.state().active, "closed")
  check(not (Stack.has and Stack.has("max_raids")), "the layer is gone")
  check(X.state().loaded == nil, "the boss's sheet released")
  U.wait(4)
  if okTC and type(TC) == "table" then
    log("engine touch pad after: enabled", tostring(TC.enabled))
    check(TC.enabled == before, "the engine's touch pad is back as it was")
  end
  shot("r06_field")
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
