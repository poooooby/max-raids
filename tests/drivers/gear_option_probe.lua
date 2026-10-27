-- Driver: KANTO GEAR (main.lua padWanted). On, the battle pad follows Kanto Gear's DISPLAY MODE
-- (separate -> the second screen; fullscreen / combined / phone -> the main one; no Gear -> a second
-- display when one is there); off, BATTLE PAD decides. A stand-in Gear's options through
-- _test.gearOptions; max_raids' own options changed in memory only (put back after, never saved).
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/gear_option_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local T = X._test
  local loader = game.mods
  local mine = loader.modOptions and loader.modOptions.max_raids
  if not mine then loader.modOptions = loader.modOptions or {}; loader.modOptions.max_raids = {}; mine = loader.modOptions.max_raids end
  local was = { kanto_gear = mine.kanto_gear, battle_pad = mine.battle_pad }
  local S2 = T.screen2
  local realDetected = S2 and S2.detected

  -- the real Gear, as it is installed here
  T.gearOptions(nil)
  log("this install: KANTO GEAR", tostring(mine.kanto_gear), "- the pad on the second screen:", tostring(T.padWanted()))

  mine.kanto_gear = true
  T.gearOptions({ display_mode = "separate" })
  check(T.padWanted() == true, "KANTO GEAR on, the Gear on SEPARATE SCREENS: the second screen")
  for _, m in ipairs({ "combined", "fullscreen", "phone" }) do
    T.gearOptions({ display_mode = m })
    check(T.padWanted() == false, "KANTO GEAR on, the Gear on " .. m .. ": the main screen")
  end
  T.gearOptions(false)
  if S2 then
    S2.detected = function() return true end
    check(T.padWanted() == true, "KANTO GEAR on, no Gear, a second display: the second screen")
    S2.detected = function() return false end
    check(T.padWanted() == false, "KANTO GEAR on, no Gear, no second display: the main screen")
    S2.detected = realDetected
  end
  mine.kanto_gear = false
  T.gearOptions({ display_mode = "separate" })
  mine.battle_pad = "main"
  check(T.padWanted() == false, "KANTO GEAR off, BATTLE PAD main (the Gear on separate): the main screen")
  mine.battle_pad = "second"
  check(T.padWanted() == true, "KANTO GEAR off, BATTLE PAD second: the second screen")

  mine.kanto_gear, mine.battle_pad = was.kanto_gear, was.battle_pad
  T.gearOptions(nil)
  log(("%d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR")
  local logFile = dir and io.open(dir .. "/driver.log", "w")
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
