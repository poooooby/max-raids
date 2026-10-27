-- Driver: a Max Raid opened straight from the field (no den yet): the intro's shots, then FLEE.
-- Gives a party of four (a National Dex Gen 4+ species among them), opens PROBE_BOSS (default
-- CHARIZARD_4), shoots the close-up, the pull back, the roar, "appeared!", over the first member's
-- shoulder, then taps FLEE on the pad and checks the layer and the boss's sheet are gone.
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
  for _, at in ipairs({ { 0.6, "r01_close" }, { 2.5, "r02_pullback" }, { 3.75, "r03_roar" },
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
