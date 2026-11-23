-- Dynamax with Kanto Gear's BATTLE VIEW on GEAR / FULL GEAR: Galar Rising's own Max Move pad in the
-- Gear's place (src/dmax_pad.lua). The Gear's options stood in for (_test.gearOptions), so it runs
-- with or without the Gear installed. Roxanne's battle, a G-Max Charizard:
--   COMBINED SCREEN (the main window, room under the game's picture): no pad in the plain move menu;
--   R brings it (v01), its DYNAMAX pill puts Dynamax back and away; its first Max Move tapped is
--   chosen; the next turn, Dynamaxed, it is up at once (v02); Back gives it back.
--   SEPARATE SCREENS (a second display stood in for): the pad pushed there (v03 a frame), a tap on
--   it picks the move.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/gear_view_probe.lua love .
local U = require("tests.drivers.util")

-- a point of the game's UI (240 x 160) on the screen: where the Dynamax UI saw it go (WoobleView's
-- uiMap), else the engine's fit
local function uiScreen(Tt, nx, ny)
  local ui = Tt.dmaxUi.uiNow
  if ui and ui.live then
    local Y = (ui.banded and ny < ui.split) and ui.topY or ui.y0
    return ui.x0 + nx * ui.sx, Y + ny * ui.sy
  end
  local Viewport = require("src.render.GameViewport")
  local Display = require("src.core.game3.display")
  local vw, vh = Viewport.dimensions()
  local sx, ox, oy, _, _, sy = Display.fit(vw, vh)
  return ox + nx * sx, oy + ny * (sy or sx)
end

local function body(game, log)
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
  love.window.setMode(720, 1000, { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Trainers = require("src.core.game3.scripting.trainers")
  local Bag = require("src.core.game3.bag")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local Tt = X._test
  local Dm = Tt.dmax
  local P = Tt.dmaxPad and Tt.dmaxPad()
  check(P ~= nil, "the Max Move pad built")
  if not P then return end
  local nd = game.mods.exports.national_dex_gen3
  local dx = nd and nd.dynamax
  local session = Runtime.getSession()
  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end
  session.party = {}
  Party.giveMon(session, sp("CHARIZARD"), 50)
  Party.giveMon(session, sp("GARDEVOIR"), 50)
  local zard = session.party[1]
  zard.moves = { mv("FLAMETHROWER"), mv("SLASH"), mv("GROWL"), mv("WING_ATTACK") }
  zard.pp, zard.maxPp = { 15, 20, 40, 35 }, { 15, 20, 40, 35 }
  if dx then dx.setLevel(zard, 10); dx.setFactor(zard, true) end
  Bag.add(session.bag, Tt.band.index, 1)

  -- (the Gear's options stood in for: its battle on its own screen, COMBINED SCREEN)
  Tt.gearOptions({ battle_view = "gear", display_mode = "combined" })
  check(P.gearView(), "the Gear's BATTLE VIEW on GEAR")

  local by = C.trainers.byName
  local tid = by.TRAINER_ROXANNE_1 or by.TRAINER_ROXANNE or by.TRAINER_LEADER_BROCK
  local ok = BattleBridge.start(Runtime._mod, game, Trainers.foeFromId(tid), { wild = false, trainerId = tid })
  check(ok == true, "Roxanne's battle starts")
  waitFor(function() return Battle.isActive() end, 3000)
  local function atCommand() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
  local lastTap, f = 0, 0
  local function pump()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 10 then lastTap = f U.tap(game, "a") return true end
    return false
  end
  local function toCommand()
    for _ = 1, 6000 do
      if atCommand() or not Battle.isActive() then break end
      if Tt.dmaxUi.sceneOn() and (Tt.dmaxUi.sceneT() or 0) > 0.5 then Tt.dmaxUi.skipScene() end
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
    return Ui._mode == "moves"
  end
  check(toCommand(), "her battle's command menu")
  local st = Battle.getState()
  local function sturdy()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 999, 999 end
    if st.enemy and st.enemy.mon then st.enemy.mon.maxHp, st.enemy.mon.hp = 999, 999 end
  end
  sturdy()

  -- a tap on one of the pad's buttons in the window (its rect + the button's place in it)
  local W = Tt.pad.sWhere
  local function cellOf(id)
    if id == "back" then return W.back end
    if id == "dynamax" then return W.dynamax end
    for _, c in ipairs(W.cells) do if c.id == id then return c end end
    return nil
  end
  local function tapPad(id)
    local c = cellOf(id)
    local R = P.rect
    if not (c and c.w and c.w > 0 and R.on) then log("  no " .. id .. " on the pad") return false end
    local x, y = R.x + c.x + c.w / 2, R.y + c.y + c.h / 2
    game:pointerEvent("pressed", "mouse", "mouse", x, y)
    U.wait(2)
    game:pointerEvent("released", "mouse", "mouse", x, y)
    U.wait(8)
    return true
  end

  -- ------- COMBINED SCREEN
  check(toMoves(), "the move menu")
  U.wait(10)
  check(not P.shown(), "no pad in the plain move menu (the Gear keeps its screen)")
  -- (the DYNAMAX button: over the move menu while the battle draws its bar; with no bar - as the
  -- Gear's GEAR views leave it, stood in for here - across the bar's middle, 1.5x; a tap there picks)
  do
    local UI = Tt.dmaxUi
    local p0 = UI.buttonPlace()
    check(not p0.bar and p0.x == UI.BUTTON.x and p0.y == UI.BUTTON.y and p0.k == 1,
      "the DYNAMAX button over the move menu while the bar is drawn")
    shot("v00a_button_menu")
    local vis = Ui.bottomUIVisible
    Ui.bottomUIVisible = function() return false end
    U.wait(6)
    local pl = UI.buttonPlace()
    log(("  no bar: the button at %.1f,%.1f x%.2f (a pixel %d screen pixels, the game's %.2f)"):format(pl.x, pl.y, pl.k,
      pl.n, pl.s))
    check(pl.bar and pl.n == math.floor(pl.s + 1e-6) + 1 and pl.y > 112,
      "no bar: the button across the bar's middle, one screen pixel bigger a pixel")
    shot("v00b_button_bar")
    local B = UI.BUTTON
    local nx, ny = pl.x + B.w * pl.k / 2, pl.y + B.h * pl.k / 2
    local wx, wy = uiScreen(Tt, nx, ny)
    log(("  the tap at %.0f,%.0f (the UI mapped by %s)"):format(wx, wy, UI.uiNow.live and "WoobleView" or "the engine's fit"))
    game:pointerEvent("pressed", "mouse", "mouse", wx, wy)
    game:pointerEvent("released", "mouse", "mouse", wx, wy)
    U.wait(6)
    check(Dm.sel[0] == true, "no bar: a tap on it there picks Dynamax")
    Dm.sel[0] = nil
    Ui.bottomUIVisible = vis
    U.wait(6)
  end
  U.tap(game, "r")
  U.wait(10)
  check(Dm.sel[0] == true and P.shown(), "R: Dynamax picked, our pad up in the Gear's place")
  check(P.where() == "main" and P.rect.on, "on the main window (" .. ("%d,%d %dx%d"):format(P.rect.x, P.rect.y,
    P.rect.w, P.rect.h) .. ")")
  -- (the window split as the Gear splits it - LAYOUT auto, a tall window: stacked - the game kept in
  -- its game rect, the pad in its rect)
  local Viewport = require("src.render.GameViewport")
  local vw, vh = Viewport.dimensions()
  local fw, fh = Viewport.fullDimensions()
  local S = P.split
  log(("  split: game %d,%d %dx%d, the Gear's %d,%d %dx%d; the game's viewport %dx%d of %dx%d"):format(
    S.game.x, S.game.y, S.game.w, S.game.h, S.gear.x, S.gear.y, S.gear.w, S.gear.h, vw, vh, fw, fh))
  check(S.on and vh == S.game.h and vh < fh, "the game kept in the Gear's game rect (not the whole window)")
  check(P.rect.y == S.gear.y and P.rect.h == S.gear.h, "the pad in the Gear's rect")
  check(Ui.bottomUIVisible() == false, "the battle's own menu kept away meanwhile (as under the Gear)")
  local names = {}
  for i, r in ipairs(P.view.cmd.moveList) do names[i] = r.name .. (r.max and "*" or "") end
  log("  the pad's moves: " .. table.concat(names, ", "))
  check(P.view.cmd.moveList[1] and P.view.cmd.moveList[1].name:find("WILDFIRE", 1, true) ~= nil,
    "its first move G-Max Wildfire")
  shot("v01_pad_combined")
  -- (its DYNAMAX pill: put back, the pad away; R again)
  check(tapPad("dynamax"), "the pad's DYNAMAX pill tapped")
  U.wait(6)
  check(Dm.sel[0] == nil and not P.shown(), "Dynamax put back: the pad gone, the Gear's again")
  U.wait(4)
  do
    local _, vh2 = Viewport.dimensions()
    local _, fh2 = Viewport.fullDimensions()
    check(not P.split.on and vh2 == fh2, "the window the game's (or the Gear's) again once it goes")
    check(Ui.bottomUIVisible() ~= false, "the battle's own menu back once it goes")
  end
  U.tap(game, "r")
  U.wait(10)
  check(P.shown(), "R again: the pad back")
  -- (G-Max Wildfire tapped on the pad: chosen, the Dynamax first)
  check(tapPad("move1"), "G-Max Wildfire tapped on the pad")
  check(toCommand(), "the next turn's command menu")
  check(st.player.__mrDmax ~= nil, "Charizard Dynamaxed from the pad's tap")
  sturdy()
  -- (Dynamaxed: the pad up at once in the move menu; Back gives it back)
  check(toMoves(), "the move menu, Dynamaxed")
  U.wait(10)
  check(P.shown(), "Dynamaxed: the pad up without R")
  shot("v02_pad_dynamaxed")
  check(tapPad("back"), "the pad's Back tapped")
  U.wait(10)
  check(Ui._mode == "menu" and not P.shown(), "Back: the command menu, the pad gone")

  -- ------- SEPARATE SCREENS: a second display stood in for
  Tt.gearOptions({ battle_view = "full", display_mode = "separate" })
  local S2 = P.S2
  local queue, last, pushes = {}, nil, 0
  S2.bridge = {
    detected = function() return true end, available = function() return true end,
    setEnabled = function() end,
    push = function(data) pushes = pushes + 1; last = data:clone(); return true end,
    pollTouch = function() return table.remove(queue, 1) end,
  }
  check(toMoves(), "the move menu, separate screens")
  U.wait(10)
  check(P.shown() and P.where() == "second", "the pad on the second screen")
  local t0 = pushes
  waitFor(function() return pushes >= t0 + 2 end, 600)
  check(pushes > t0, "frames pushed to the second screen (" .. pushes .. ")")
  if last then
    local fd = last:encode("png")
    local fh = io.open(dir .. "/v03_pad_second.png", "wb")
    if fh then fh:write(fd:getString()); fh:close() end
  end
  -- (Max Airstream - its fourth - tapped there)
  local c = cellOf("move4")
  if c then
    local x, y = math.floor(c.x + c.w / 2), math.floor(c.y + c.h / 2)
    queue[#queue + 1] = ("down,%d,%d"):format(x, y)
    queue[#queue + 1] = ("up,%d,%d"):format(x, y)
  end
  local said = false
  local ad = Battle._adapter
  local pushEvent = ad.pushEvent
  ad.pushEvent = function(self, ev, ...)
    if type(ev) == "table" and ev.kind == "msg" and tostring(ev.text):find("AIRSTREAM", 1, true) then said = true end
    return pushEvent(self, ev, ...)
  end
  check(toCommand(), "the turn after the second screen's tap")
  check(said, "Max Airstream used from the second screen")
  ad.pushEvent = pushEvent
  S2.bridge = nil
  -- ------- FULLSCREEN SWAP: the pad the whole screen, as the Gear's swap; PHONE / BROWSER (and
  -- SEPARATE with no display): the Gear's combined split, its defaults; none on COMPANION
  local Viewport2 = require("src.render.GameViewport")
  for _, mode in ipairs({ "fullscreen", "phone" }) do
    Tt.gearOptions({ battle_view = "gear", display_mode = mode })
    check(toMoves(), mode .. ": the move menu")
    if not st.player.__mrDmax then U.tap(game, "r") end
    U.wait(10)
    local fw2, fh2 = Viewport2.fullDimensions()
    log(("  %s: the pad %d,%d %dx%d; split %s"):format(mode, P.rect.x, P.rect.y, P.rect.w, P.rect.h, tostring(P.split.on)))
    if mode == "fullscreen" then
      check(P.shown() and P.rect.on and not P.split.on and P.rect.full and (P.rect.w == fw2 or P.rect.h == fh2),
        "fullscreen: the pad the whole screen (its shape kept)")
    else
      local _, vh3 = Viewport2.dimensions()
      check(P.shown() and P.rect.on and P.split.on and vh3 < fh2 and P.rect.y == P.split.gear.y,
        "phone: the game pushed up, the pad under it (the Gear's split)")
    end
    shot("v04_pad_" .. mode)
    U.tap(game, "b")
    U.wait(20)
    if Ui._mode == "moves" then U.tap(game, "b") U.wait(20) end
  end
  Tt.gearOptions({ battle_view = "standard", display_mode = "combined" })
  check(toMoves(), "COMPANION: the move menu")
  if not st.player.__mrDmax then U.tap(game, "r") end
  U.wait(10)
  check(not P.shown(), "COMPANION: no pad (the battle's own menu, the Gear's touch controls)")
  Tt.gearOptions(nil)
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
