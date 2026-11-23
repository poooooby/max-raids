-- Driver: the README's pictures of Dynamax in the game's own battles. In Rustboro / Pewter Gym, with
-- WoobleView's Battle Fit, Fill Screen and 3D Battle Scene on: Roxanne / Brock, the ace made a
-- Gigantamax Coalossal (Dynamax Level 10); the player's Charizard (Gigantamax Factor, Level 10) and
-- Gardevoir. Her ace Dynamaxes on its first turn (its scene skipped), then Charizard's Dynamax scene
-- is shot through its parts (scene_*.png), and both giants standing on the field (both_*.png).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/readme_shots.lua love .

local GYMS = { "RUSTBORO_CITY_GYM", "PEWTER_CITY_GYM" }

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local W, H = tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720
  love.window.setMode(W, H, { resizable = true, highdpi = false, vsync = 0 })
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
  local Trainers = require("src.core.game3.scripting.trainers")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local X = game.mods.exports.max_raids
  local Tt = X._test
  local Dm = Tt.dmax
  local UI = Tt.dmaxUi
  local nd = game.mods.exports.national_dex_gen3
  local dx = nd and nd.dynamax
  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end
  if game.mods.modOptions then
    game.mods.modOptions.omni_ui = game.mods.modOptions.omni_ui or {}
    game.mods.modOptions.omni_ui.overlay = false
  end

  -- WoobleView's 3D scene
  local wvx = game.mods.exports["gen3-hd-sprites"]
  if wvx then
    pcall(wvx.setFit, true)
    pcall(wvx.setRealSizes, true)
    pcall(wvx.setFill, true)
    pcall(wvx.setScene, true)
    log("  WoobleView: Fit " .. tostring(wvx.fitEnabled and wvx.fitEnabled()) .. ", Fill " ..
      tostring(wvx.fillEnabled and wvx.fillEnabled()) .. ", Scene " .. tostring(wvx.sceneEnabled and wvx.sceneEnabled()))
  else
    log("  no WoobleView")
  end

  -- the gym
  local maps = game.data and game.data.maps or {}
  local gym
  for id in pairs(maps) do
    if type(id) == "string" then
      for _, g in ipairs(GYMS) do if id:sub(-#g) == g then gym = id end end
    end
  end
  log("gym", tostring(gym))
  if gym then
    local Field = require("src.core.game3.field")
    local ok, res, why = pcall(Map.load, Field._mod, Field._game or game, gym, { x = 5, y = 5, facing = "up" })
    if not ok or (res == nil and why) then log("Map.load failed:", tostring(ok and why or res)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = 5, 5, "up" end
    Player.cellX, Player.cellY, Player.px, Player.py = 5, 5, 80, 80
    U.wait(30)
  end

  -- the party, the band
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, sp("CHARIZARD"), 50)
  Party.giveMon(session, sp("GARDEVOIR"), 50)
  local zard = session.party[1]
  zard.moves = { mv("FLAMETHROWER"), mv("SLASH"), mv("GROWL"), mv("WING_ATTACK") }
  zard.pp = { 15, 20, 40, 35 }
  zard.maxPp = { 15, 20, 40, 35 }
  if dx then dx.setLevel(zard, 10); dx.setFactor(zard, true) end
  Bag.add(session.bag, Tt.band.index, 1)
  Tt.dmaxMode("league")

  -- the Leader, her ace a Gigantamax Coalossal
  local by = C.trainers.byName
  local tid = by.TRAINER_ROXANNE_1 or by.TRAINER_ROXANNE or by.TRAINER_LEADER_BROCK
  local foe = Trainers.foeFromId(tid)
  local ace = foe.party[#foe.party]
  -- (Coalossal is WoobleDex's: its slot through speciesFromNational, its moves at its level)
  local Pokemon = require("src.core.game3.pokemon")
  ace.species = Pokemon.speciesFromNational(839) or sp("LAPRAS")
  ace.level = 48
  local okM, learned = pcall(Pokemon.movesAtLevel, ace.species, ace.level)
  ace.moves = okM and type(learned) == "table" and #learned > 0 and learned or
    { mv("ROCK_SLIDE") or mv("ROCK_THROW"), mv("PROTECT"), mv("GROWL"), mv("TACKLE") }
  log("ace", tostring(ace.species), "moves", table.concat(ace.moves, ","))
  foe.party = { ace }
  foe.species, foe.level, foe.moves = ace.species, ace.level, ace.moves
  local ok, err = BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = tid })
  log("battle", tostring(ok), tostring(err))

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
  local function toCommand(limit)
    waitFor(function() return Battle.isActive() end, 3000)
    for _ = 1, limit or 6000 do
      if atCommand() or not Battle.isActive() then break end
      if not pump() then U.wait(1) end
    end
    return atCommand()
  end
  local function toMoves()
    for _ = 1, 6 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
  end
  log("command", tostring(toCommand()))
  local st = Battle.getState()
  -- (sturdy enough to stand through Max Rockfall - three digits still, so the HP box reads)
  st.player.mon.maxHp, st.player.mon.hp = 480, 480
  st.enemy.mon.maxHp, st.enemy.mon.hp = 600, 600

  -- turn 1: Growl; her ace Dynamaxes, its scene skipped
  toMoves()
  U.tap(game, "down"); U.wait(8); U.tap(game, "a")
  for _ = 1, 3000 do
    if UI.sceneOn() and (UI.sceneT() or 0) > 0.6 then U.tap(game, "b") end
    if atCommand() or not Battle.isActive() then break end
    if not pump() then U.wait(1) end
  end
  log("foe giant", tostring(st.enemy.__mrDmax ~= nil), "gmax", tostring(st.enemy.__mrDmax and st.enemy.__mrDmax.gmax))
  for _, b in ipairs({ st.player, st.enemy }) do b.mon.hp = b.mon.maxHp end

  -- turn 2: Charizard Dynamaxes; its scene shot through its parts
  toMoves()
  U.tap(game, "r"); U.wait(6)
  shot("menu_dynamax")
  U.tap(game, "a")
  local SM = UI.SM
  local marks = { { SM.RECALL + 0.15, "scene_recall" }, { SM.BAND + 0.35, "scene_band" }, { SM.BURST + 0.06, "scene_burst" },
    { SM.OPEN + 0.15, "scene_open" }, { SM.GROW + 0.25, "scene_grow1" }, { SM.GROW + 0.5, "scene_grow2" },
    { SM.ROAR + 0.1, "scene_roar" }, { SM.ROAR + 0.4, "scene_roar2" }, { SM.HOLD, "scene_hold" } }
  local nextMark = 1
  local giantSeen = false
  for _ = 1, 4000 do
    local v = Dm.vis[0]
    if UI.sceneOn() and UI.sceneT() then
      local t = UI.sceneT()
      if nextMark <= #marks and t >= marks[nextMark][1] then
        shot(marks[nextMark][2])
        nextMark = nextMark + 1
      end
      U.wait(1)
    else
      if v and (v.k or 1) > 1.45 and not giantSeen then giantSeen = true; U.wait(10); shot("both_move") end
      if atCommand() then break end
      if not pump() then U.wait(1) end
    end
  end
  log("player giant", tostring(st.player.__mrDmax ~= nil), "scene shots", nextMark - 1)
  for _, b in ipairs({ st.player, st.enemy }) do b.mon.hp = b.mon.maxHp end
  U.wait(30)
  shot("both_command")
  U.wait(45)
  shot("both_command2")
  toMoves()
  U.wait(20)
  shot("both_moves")
  U.tap(game, "b"); U.wait(10)
  Battle.abort("run")
  waitFor(function() return not Battle.isActive() end, 600)
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
