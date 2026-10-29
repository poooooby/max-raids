-- Driver: Wilds of Hoenn's wandering Pokemon cannot start a battle while a den or raid is up. Its
-- battles wait while its EnginePatch.fieldBusy() is true (the engine's Hud.busy: any layer on the
-- UI stack, ours included); the engine's field (Field.update) does not run meanwhile either. Asked on
-- the field, then through a raid - the den screen, the intro, the commands, the catch, the rewards -
-- and after it closes.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/woh_probe.lua love .

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(120)
  -- (a team to raid with: a new game has none)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON", "SPECIES_MUDKIP", "SPECIES_RALTS" }) do
      Party.giveMon(s0, C:require("species", sp), 30)
    end
  end
  local ex = game.mods and game.mods.exports
  local X = ex and ex.max_raids
  local W = ex and ex.wilds_of_hoenn
  if not X then log("FAIL max_raids not loaded"); return end
  if not (W and W.enginePatch and W.enginePatch.fieldBusy) then log("FAIL Wilds of Hoenn not loaded"); return end
  local EP = W.enginePatch
  local Field = require("src.core.game3.field")
  -- (the engine's field updates counted: Field.update runs only while the field does)
  local updates, realUpdate = 0, Field.update
  Field.update = function(...) updates = updates + 1; return realUpdate(...) end
  local function fieldTicks() return updates end
  local u0 = updates
  U.wait(20)
  log("on the field: fieldBusy", tostring(EP.fieldBusy()), "field updates in 20 frames", updates - u0)
  local stages = {}
  local function ask(stage)
    local busy = EP.fieldBusy()
    stages[#stages + 1] = stage
    check(busy == true, ("%s: Wilds of Hoenn holds its battles (fieldBusy %s)"):format(stage, tostring(busy)))
  end
  -- the den screen (a den stood in for: the raid opens on it as A on a den does)
  local R = X.raid
  local den = { x = 1, y = 1, active = true, stars = 4, boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4", day = 0 }
  if R.openDen then
    R.openDen(den)
    U.wait(20)
    ask("the den screen")
    local f0 = fieldTicks()
    U.wait(30)
    if f0 ~= nil then check(fieldTicks() == f0, "the engine's field stands still under the den screen") end
    if R.close then R.close() end
    U.wait(20)
  end
  X.open(den.boss)
  waitFor(function() return X.state().phase == "intro" end, 2000)
  ask("the intro")
  waitFor(function() return X.state().phase == "command" end, 20000)
  ask("the commands")
  if X.state().active then
    R.startCatch()
    U.wait(10)
    ask("the catch")
    if R.startRewards then R.startRewards(); U.wait(10); ask("the rewards card") end
  else
    log("FAIL the raid closed before its catch")
    fails = fails + 1
  end
  X.close()
  waitFor(function() return not X.state().active end, 600)
  U.wait(30)
  log("after the raid: fieldBusy", tostring(EP.fieldBusy()))
  check(EP.fieldBusy() == false, "after the raid: the field free again")
  Field.update = realUpdate
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
