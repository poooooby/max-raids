-- Driver: PERFORMANCE - the option shows the engine's frame profiler (its F3 overlay) while a den is
-- open, with the raid's parts as sections, the slowest frames listed at the top right with what the
-- raid was doing; put away when the den closes, and with the option off. A raid opened (its first
-- frame, the den built, is a slow one), a turn played, the slowest frames logged.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/perf_overlay_probe.lua love .

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
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  U.wait(10)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R = X.raid
  local FP = require("src.core.FrameProfiler")
  local loader = game.mods
  local function setOption(on)
    loader.modOptions.max_raids = loader.modOptions.max_raids or {}
    loader.modOptions.max_raids.perf_overlay = on
  end

  check(FP.enabled ~= true, "off by default: no overlay")
  setOption(true)
  U.wait(5)
  check(FP.enabled ~= true, "PERFORMANCE on, on the field: no overlay")
  R.openDen({ x = 1, y = 1, active = true, stars = 4, boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4", day = 0 })
  U.wait(5)
  check(FP.enabled == true, "PERFORMANCE on, the den screen: the overlay shown")
  R.close()
  U.wait(5)
  check(FP.enabled == false, "the den closed: the overlay put away")

  X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  waitFor(function() local c = R.current(); return c and c.phase == "command" and not c.say end, 20000)
  U.wait(60)
  local have = {}
  for _, name in ipairs(FP.sections()) do have[name] = true end
  log("sections:", table.concat(FP.sections(), ", "))
  for _, name in ipairs({ "raid update", "raid draw", "raid 3d", "raid scene", "raid fx", "raid hud", "raid pad" }) do
    check(have[name] == true, "section " .. name)
  end
  -- a turn: each member its first move
  for _ = 1, 4 do
    local c = R.current()
    if not (c and c.phase == "command" and c.cmd and c.cmd.actor) then break end
    R.choose("fight")
    R.choose("move1")
    local c2 = R.current() and R.current().cmd
    if c2 and c2.menu == "target" then R.choose("move1") end
    U.wait(2)
  end
  waitFor(function() local c = R.current(); return not c or (c.phase == "command" and not c.say) end, 30000)
  -- (a slow frame made for certain: one raid update held 25 ms - the raid itself may make none now)
  local realUpdate, held = R.update, false
  R.update = function(...)
    if not held then
      held = true
      local t0 = love.timer.getTime()
      while love.timer.getTime() - t0 < 0.025 do end
    end
    return realUpdate(...)
  end
  U.wait(40)
  R.update = realUpdate
  local spikes = FP.spikeList()
  local raidSpike = false
  for i, sp in ipairs(spikes) do
    if i <= 6 then log(("spike %.1f ms %s"):format(sp.total, tostring(sp.ctx))) end
    if tostring(sp.ctx):find("raid ", 1, true) then raidSpike = true end
  end
  check(#spikes > 0, "slow frames recorded (" .. #spikes .. ")")
  check(raidSpike, "a slow frame labelled with the raid's doings")
  setOption(false)
  U.wait(5)
  check(FP.enabled == false, "PERFORMANCE off in a raid: the overlay put away")
  X.close()
  U.wait(20)
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
