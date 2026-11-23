-- Driver: the weather overlay stays off the screens after a catch. A wild battle with hail set on it,
-- a Master Ball thrown: while the catch's Pokedex page, the nickname question and the naming screen
-- are up (the game's own, or WoobOS's in their place), our weather overlay draws nothing; it draws
-- again in the next battle. Also: the game's UI stack is empty in a plain battle (the overlay takes
-- any layer on it as a screen over the battle).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/catch_weather_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(960, 640, { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Stack = require("src.ui.game3.stack")
  local Naming = require("src.ui.game3.naming")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local X = game.mods.exports.max_raids
  local Tt = X._test
  local BW = Tt.battleWeather()
  check(BW ~= nil, "the battles' weather overlay is there")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, C.species.byName["SPECIES_CHARIZARD"], 50)
  local ball = C:require("items", "ITEM_MASTER_BALL")
  check(ball ~= nil, "the Master Ball's item id " .. tostring(ball))
  Bag.add(session.bag, ball, 3)
  Tt.dmaxMode("all")
  -- (PROBE_WOOB_CATCH=0: WoobOS's capture scene off for this run - the game's own Pokedex page and
  -- naming screen instead; the loader's option, read live)
  if os.getenv("PROBE_WOOB_CATCH") == "0" and game.mods and game.mods.modOptions then
    game.mods.modOptions.woob_os = game.mods.modOptions.woob_os or {}
    game.mods.modOptions.woob_os.menuCatch = false
  end
  local woob = game.mods.exports.woob_os
  log("  WoobOS: " .. tostring(woob ~= nil))

  local lastTap, f = 0, 0
  local function pump(key)
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 10 then
      lastTap = f
      U.tap(game, key or "a")
      return true
    end
    return false
  end
  local function atCommand() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
  local function toCommand()
    waitFor(function() return Battle.isActive() end, 3000)
    for _ = 1, 6000 do
      if atCommand() or not Battle.isActive() then break end
      if not pump() then U.wait(1) end
    end
    return atCommand()
  end
  local function screensUp()
    local woobScene = woob and woob._test and woob._test.shell and woob._test.shell.sceneOpen and woob._test.shell.sceneOpen()
    return Ui._caughtDexScene ~= nil or Naming.isOpen() or woobScene == true or #(Stack._layers or {}) > 0
  end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName["SPECIES_ZIGZAGOON"], level = 3 }, {})
  check(ok == true and toCommand(), "a wild battle, its command menu")
  log("  the UI stack in the battle: " .. tostring(#(Stack._layers or {})) .. " layers")
  check(#(Stack._layers or {}) == 0, "the game's UI stack is empty in a plain battle")
  local st = Battle.getState()
  st.weather, st.weatherTurns = "HAIL", 5
  U.wait(40)
  local d0 = BW.last.drew
  U.wait(30)
  check(BW.last.drew > d0, "hail drawn over the battle (" .. (BW.last.drew - d0) .. " frames)")
  shot("c01_hail")
  -- the Master Ball, as the Bag's pick hands it to the battle
  Ui._pendingCommand = { kind = "bag", itemId = ball, user = "player" }
  Ui._mode = "none"
  local sawScreens, drewOver, framesOver = false, 0, 0
  local overAt, drewAfterOver, overFrames = nil, 0, 0
  local clock = love.timer.getTime
  local press = 0
  for _ = 1, 6000 do
    if not Battle.isActive() then break end
    -- (the battle decided: the overlay fades out - past its fade, on the wall's clock, it draws no more)
    local CatchSeq = require("src.core.game3.battle.catch_seq")
    local decided = st.over or (CatchSeq.catchResult and CatchSeq.catchResult() ~= nil)
    if decided and not overAt then overAt = clock(); shot("c01b_over") end
    if overAt and not screensUp() and clock() - overAt > 1 then
      local before = BW.last.drew
      U.wait(1)
      if BW.last.drew > before then drewAfterOver = drewAfterOver + 1 end
      overFrames = overFrames + 1
    end
    if screensUp() then
      if not sawScreens then
        sawScreens = true
        U.wait(20)
        shot("c02_caught_screen")
        d0 = BW.last.drew
      end
      framesOver = framesOver + 1
      if framesOver == 120 then shot("c03_caught_later") end
      -- (WoobOS's page is its own to press through: what matters is measured by now)
      if framesOver >= 400 then break end
      -- (through the screens: B in the naming screen leaves it; A everywhere else - WoobOS's scene
      -- sets no prompt of the battle's)
      press = press + 1
      if press % 12 == 0 then U.tap(game, Naming.isOpen() and "b" or "a") end
      U.wait(1)
    elseif not pump() then
      U.wait(1)
    end
  end
  drewOver = sawScreens and (BW.last.drew - d0) or 0
  log(("  after the battle was decided: %d frames watched before the screens, the overlay drew %d"):format(overFrames, drewAfterOver))
  check(overAt ~= nil and drewAfterOver == 0, "the overlay gone once the battle is decided")
  log(("  the catch's screens: seen %s, up %d frames, our overlay drew %d frames over them"):format(
    tostring(sawScreens), framesOver, drewOver))
  check(sawScreens, "the catch's Pokedex page / naming came up")
  check(drewOver == 0, "nothing of the weather drawn over them")
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
