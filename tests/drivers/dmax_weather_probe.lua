-- Driver: a Max Move's weather in the game's own battle, as the cart runs it. Roxanne (her Pokemon
-- made sturdy, so none faints); Charizard Dynamaxes: turn 1 Flamethrower as Max Flare - harsh sunlight, its words, and
-- at the turn's end the cart's own "sunlight is strong" with its SUN_CONTINUES animation; turn 2 its
-- damage worked out in sun (Damage.calc's weatherKind); Ice Beam as Max Hailstorm - hail in the sun's
-- place, and at the turn's end the cart's hail: its words, HAIL_CONTINUES, the foe buffeted (a Rock
-- type: hail spares only Ice). Then a terrain (Max Mindstorm) - WoobleDex's field, its words.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dmax_weather_probe.lua love .

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
  local Anim = require("src.core.game3.battle.anim")
  local Damage = require("src.core.game3.battle.damage")
  local Trainers = require("src.core.game3.scripting.trainers")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local X = game.mods.exports.max_raids
  local Tt = X._test
  local Dm = Tt.dmax
  local session = Runtime.getSession()
  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end
  session.party = {}
  Party.giveMon(session, sp("CHARIZARD"), 50)
  local zard = session.party[1]
  zard.moves = { mv("FLAMETHROWER"), mv("ICE_BEAM"), mv("PSYCHIC"), mv("SLASH") }
  zard.pp = { 15, 10, 15, 20 }
  zard.maxPp = { 15, 10, 15, 20 }
  local dx = game.mods.exports.national_dex_gen3 and game.mods.exports.national_dex_gen3.dynamax
  if dx then dx.setLevel(zard, 10); dx.setFactor(zard, false) end
  Bag.add(session.bag, Tt.band.index, 1)
  Tt.dmaxMode("league")

  -- what the battle says and which of its general animations play
  local said, generals = {}, {}
  local launch = Anim.launchGeneral
  Anim.launchGeneral = function(name, ...)
    generals[#generals + 1] = tostring(name)
    return launch(name, ...)
  end
  local calc = Damage.calc
  local weatherSeen = {}
  Damage.calc = function(att, def, move, opts, ...)
    -- (the hit passes the weather as `weather`, the effective kind; Damage.calc reads either)
    local w = type(opts) == "table" and (opts.weatherKind or opts.weather) or nil
    if w then weatherSeen[#weatherSeen + 1] = tostring(w) end
    return calc(att, def, move, opts, ...)
  end
  local function heard(pat, from)
    for i = from or 1, #said do if said[i]:find(pat) then return true end end
    return false
  end
  local function played(name, from)
    for i = from or 1, #generals do if generals[i] == name then return true end end
    return false
  end

  local lastTap, f = 0, 0
  local function pump()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 10 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function atCommand() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
  local function toCommand()
    waitFor(function() return Battle.isActive() end, 3000)
    for _ = 1, 8000 do
      if atCommand() or not Battle.isActive() then break end
      if not pump() then U.wait(1) end
    end
    return atCommand()
  end
  local by = C.trainers.byName
  local tid = by.TRAINER_ROXANNE_1 or by.TRAINER_ROXANNE or by.TRAINER_LEADER_BROCK
  -- (PROBE_SCENE=1: WoobleView's 3D Battle Scene on before the battle - it builds the scene as one opens)
  if os.getenv("PROBE_SCENE") == "1" then
    local w = game.mods.exports["gen3-hd-sprites"]
    -- (on a route - the scene is the map's: WoobleView's own tests/drivers/scene_battle.lua sets up so)
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local px, py = 10, 10
    pcall(Map.load, nil, game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", { x = px, y = py, facing = "down" })
    session.x, session.y = px, py
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY, Player.facing = px, py, "down"
    U.wait(40)
    if w and w.setScene then
      pcall(w.setFill, true)
      pcall(w.setScene, true)
    end
  end
  local ok = BattleBridge.start(Runtime._mod, game, Trainers.foeFromId(tid), { wild = false, trainerId = tid })
  check(ok == true and toCommand(), "Roxanne's battle, its command menu")
  local st = Battle.getState()
  local function sturdy()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 9999, 9999 end
    if st.enemy and st.enemy.mon then st.enemy.mon.maxHp, st.enemy.mon.hp = 9999, 9999 end
  end
  do
    local ad = Battle._adapter
    local pushEvent = ad.pushEvent
    ad.pushEvent = function(self, ev, ...)
      if type(ev) == "table" and ev.kind == "msg" then
        said[#said + 1] = tostring(ev.text):gsub("\n", " ")
        log("  says: " .. said[#said])
      end
      return pushEvent(self, ev, ...)
    end
  end
  -- a turn: FIGHT, the slot's move (R first on turn 1), the turn played to the next command
  local sceneFrames = 0
  local function turn(slot, dynamax, watch)
    sturdy()
    for _ = 1, 6 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    if dynamax then U.tap(game, "r"); U.wait(6) end
    -- (the move cursor put on the slot: the game remembers it from the turn before)
    Ui._moveIndex = slot
    U.wait(4)
    U.tap(game, "a")
    U.wait(10)
    for _ = 1, 600 do
      if Tt.dmaxUi.sceneOn() then
        if not watch then U.tap(game, "b") break end
        -- (played whole: its frames counted, the driver stepping 1/60 s a frame)
        while Tt.dmaxUi.sceneOn() and sceneFrames < 3000 do sceneFrames = sceneFrames + 1; U.wait(1) end
        break
      end
      U.wait(1)
    end
    return toCommand()
  end

  -- turn 1: Max Flare, the battle at 4x - the Dynamax scene still at 1x
  -- (every category at 4x, as the game's own speed button sets it: the battle's menus count as menus)
  local GameSpeed = require("src.core.GameSpeed")
  local speed0 = {}
  for _, c in ipairs(GameSpeed.CATEGORIES) do
    local k = GameSpeed.optionKey(c)
    speed0[k] = game.options[k]
    game.options[k] = 4
  end
  -- (a driver run holds the speed at 1x with the override a held fast-forward uses: let go of it,
  -- so the options' 4x is the one asked - main's core.logic_speed wrap)
  local override0 = game.speedOverride
  game.speedOverride = nil
  log(("  the battle's speed: %sx (category %s, locked %s, override %s, allowed %s, option %s)"):format(
    tostring(game:logicSpeed()), tostring(game:speedCategory()), tostring(game:speedLocked()),
    tostring(game.speedOverride), table.concat(GameSpeed.allowed(), "/"), tostring(game.options.speedBattle)))
  local s1, g1 = #said + 1, #generals + 1
  check(turn(1, true, true), "turn 1 played")
  local SM, SC = Tt.dmaxUi.SM, Tt.dmaxUi.SCENE
  local want = (SM.END + SC.BACK) * 60
  log(("  the Dynamax scene: %d frames at 4x (%.0f at 1x)"):format(sceneFrames, want))
  check(sceneFrames >= want * 0.9, "the Dynamax scene at 1x while the battle runs at 4x")
  check(game:logicSpeed() == 4, "the battle back at 4x after it")
  for k, v in pairs(speed0) do game.options[k] = v end
  game.speedOverride = override0
  log("  weather " .. tostring(st.weather) .. ", " .. tostring(st.weatherTurns) .. " turns; general animations: "
    .. table.concat(generals, ", ", g1))
  check(st.player.__mrDmax ~= nil, "Charizard Dynamaxed")
  check(heard("MAX FLARE", s1) and heard("sunlight got bright", s1), "Max Flare: \"The sunlight got bright!\"")
  check(heard("sunlight is strong", s1), "the turn's end: the cart's \"The sunlight is strong.\"")
  local suns = 0
  for i = g1, #generals do if generals[i] == "SUN_CONTINUES" then suns = suns + 1 end end
  check(suns >= 2, "SUN_CONTINUES as Max Flare sets it and again at the turn's end (" .. suns .. ")")
  check(st.weather ~= nil and (st.weatherTurns or 0) == 4, "sun, four turns left")
  local BW = Tt.battleWeather()
  U.wait(20)
  local sceneOn = os.getenv("PROBE_SCENE") == "1"
  check(BW and BW.last.weather == "SUN" and (sceneOn or BW.last.drew > 0), "our overlay: the sun drawn over the battle ("
    .. tostring(BW and BW.last.weather) .. ", " .. tostring(BW and BW.last.drew) .. " frames)")
  shot("x01_sun")
  -- turn 2: its damage in sun; Ice Beam as Max Hailstorm
  local s2, g2 = #said + 1, #generals + 1
  for k in pairs(weatherSeen) do weatherSeen[k] = nil end
  sturdy()
  local hp0 = st.enemy.mon.hp
  check(turn(2, false), "turn 2 played")
  local sunHits = false
  for _, w in ipairs(weatherSeen) do if w == "SUN" then sunHits = true end end
  check(sunHits, "turn 2: the damage worked out in sun (" .. table.concat(weatherSeen, ",") .. ")")
  check(heard("MAX HAILSTORM", s2) and heard("hail", s2), "Max Hailstorm: the hail starts")
  check(heard("buffeted by the hail", s2) or heard("pelted by HAIL", s2), "the turn's end: the foe buffeted by the hail")
  check(played("HAIL_CONTINUES", g2), "the turn's end: its HAIL_CONTINUES animation")
  log(("  the foe's HP: %d -> %d"):format(hp0, st.enemy.mon.hp))
  U.wait(20)
  check(BW and BW.last.weather == "HAIL", "our overlay: hail now (" .. tostring(BW and BW.last.weather) .. ")")
  shot("x02_hail")
  -- turn 3: Psychic as Max Mindstorm - Psychic Terrain (WoobleDex's field; Max Lightning would do
  -- nothing to her Ground type: a Max Move that does not affect its target sets nothing)
  local s3 = #said + 1
  check(turn(3, false), "turn 3 played")
  local fld = st.__ndxField
  log("  terrain " .. tostring(fld and fld.terrain) .. ", " .. tostring(fld and fld.terrainTurns) .. " turns")
  check(fld and fld.terrain == "PSYCHIC", "Max Mindstorm: Psychic Terrain")
  check(heard("weird", s3) or heard("psychic", s3) or heard("Psychic", s3), "its words")
  U.wait(20)
  check(BW and BW.last.terrain == "PSYCHIC" and (sceneOn or BW.last.pads >= 2), "our overlay: Psychic Terrain under both ("
    .. tostring(BW and BW.last.terrain) .. ", " .. tostring(BW and BW.last.pads) .. " places)")
  shot("x03_terrain")
  -- (each weather and terrain put on the battle in turn, for the shots)
  for _, w in ipairs({ "RAINY", "SANDSTORM", "SUNNY", "HAIL" }) do
    st.weather, st.weatherTurns = w, 5
    -- (the last one faded out on the wall's clock: the driver steps faster than it)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 1.2 do U.wait(1) end
    shot("x1_" .. w:lower())
  end
  st.weather = nil
  for _, k in ipairs({ "ELECTRIC", "GRASSY", "MISTY", "PSYCHIC" }) do
    if fld then fld.terrain, fld.terrainTurns = k, 5 end
    -- (the last one faded out on the wall's clock: the driver steps faster than it)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 1.2 do U.wait(1) end
    shot("x2_" .. k:lower())
  end
  -- the battle's bar hidden (Kanto Gear's GEAR views, OmniUI): the terrain under the player down to
  -- the picture's foot, not cut at the cart's text box
  do
    if fld then fld.terrain, fld.terrainTurns = "GRASSY", 5 end
    local ask = Ui.bottomUIVisible
    Ui.bottomUIVisible = function() return false end
    U.wait(40)
    log("  the bar hidden: the field down to row " .. tostring(BW.last.barRow))
    check(sceneOn or BW.last.barRow == 160, "the battle's bar hidden: the overlay down to the picture's foot")
    shot("x5_no_bar_grassy")
    Ui.bottomUIVisible = ask
    U.wait(10)
    log("  the bar back: the field down to row " .. tostring(BW.last.barRow))
  end
  -- WoobleView's 3D Battle Scene draws the battle's weather and terrain itself (its
  -- battleWeatherDrawn): our overlay stands down there, and is back once the scene is off
  local wvx = game.mods.exports["gen3-hd-sprites"]
  if os.getenv("PROBE_SCENE") == "1" and wvx and type(wvx.battleWeatherDrawn) == "function" then
    local function realWait(sec) local t0 = love.timer.getTime(); while love.timer.getTime() - t0 < sec do U.wait(1) end end
    st.weather, st.weatherTurns = "RAINY", 5
    if fld then fld.terrain, fld.terrainTurns = "GRASSY", 5 end
    realWait(1.5)
    local d0 = BW.last.drew
    U.wait(60)
    log(("  WoobleView's scene: on %s, battleWeatherDrawn %s; our overlay drew %d frames meanwhile"):format(
      tostring(wvx.sceneEnabled and wvx.sceneEnabled()), tostring(wvx.battleWeatherDrawn()), BW.last.drew - d0))
    check(wvx.battleWeatherDrawn() == true and BW.last.drew == d0, "WoobleView's 3D scene: its weather and terrain, ours stood down")
    shot("x4_3d_rain_grassy")
    st.weather = "HAIL"
    realWait(1.5)
    shot("x4_3d_hail")
    st.weather = "SUNNY"
    if fld then fld.terrain = "ELECTRIC" end
    realWait(1.5)
    shot("x4_3d_sun_electric")
    pcall(wvx.setScene, false)
    realWait(0.5)
    local d1 = BW.last.drew
    U.wait(30)
    check(BW.last.drew > d1, "the scene off: our overlay back")
  else
    log("  WoobleView's 3D scene not checked (PROBE_SCENE=1, a WoobleView with battleWeatherDrawn)")
  end
  -- the garbage a call makes (the collector stopped): our weather overlay with rain and Grassy
  -- Terrain up, the DYNAMAX button's and the Omni swap's per-frame parts
  do
    st.weather, st.weatherTurns = "RAINY", 5
    if fld then fld.terrain, fld.terrainTurns = "GRASSY", 5 end
    U.wait(30)
    local function kbPerCall(fn, n)
      fn()
      collectgarbage("collect")
      collectgarbage("stop")
      local before = collectgarbage("count")
      for _ = 1, n do fn() end
      local after = collectgarbage("count")
      collectgarbage("restart")
      return (after - before) / n
    end
    local UI = Tt.dmaxUi
    local G = love.graphics
    local function overlay() G.push("all"); BW.draw(nil); G.pop() end
    local function button() G.push("all"); pcall(UI.drawButtonHud); G.pop() end
    local function swap() if UI.omniSwapIn() then UI.omniSwapOut() end end
    local rows = { { "the weather overlay (rain, grass)", overlay }, { "the DYNAMAX button", button },
      { "the Omni move swap", swap }, { "the button's place (the battle's bar kept from its draw)",
        function() UI.buttonPlace() end }, { "OmniUI's overlay asked", function() UI.omniOn() end } }
    if os.getenv("PROBE_GC_PARTS") == "1" then
      local Rules = require("src.core.game3.battle.rules")
      local dex = game.mods.exports.national_dex_gen3
      local wv = game.mods.exports["gen3-hd-sprites"]
      local parts = {
        { "  Rules.weather.kind", function() Rules.weather.kind(st.weather) end },
        { "  WoobleDex terrainOf", function() pcall(dex.battle.terrainOf, st) end },
        { "  WoobleView battleWeatherDrawn", function() if wv.battleWeatherDrawn then pcall(wv.battleWeatherDrawn) end end },
        { "  WoobleView barTop", function() if wv.barTop then pcall(wv.barTop) end end },
        { "  WoobleView battlerRect", function() pcall(wv.battlerRect, "player") end },
        { "  screenOver", function() UI.screenOver() end },
        { "  uiPoint", function() UI.uiPoint(0, 112) end },
        { "  noteUiMap", function() UI.noteUiMap() end },
        { "  bottomShown", function() UI.bottomShown() end },
        { "  push / pop", function() G.push("all"); G.pop() end },
      }
      for _, p in ipairs(parts) do rows[#rows + 1] = p end
    end
    for _, row in ipairs(rows) do
      local kb = kbPerCall(row[2], 200)
      log(("  garbage: %s %.3f KB a call"):format(row[1], kb))
      check(kb < 0.1, "no garbage a frame (under 0.1 KB): " .. row[1])
    end
  end
  Anim.launchGeneral, Damage.calc = launch, calc
  Battle.abort("run")
  waitFor(function() return not Battle.isActive() end, 600)
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
