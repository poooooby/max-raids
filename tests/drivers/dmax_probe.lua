-- Driver: Dynamax in the game's own battles (src/dmax.lua, src/dmax_ui.lua), end to end. A party of
-- Charizard (Gigantamax Factor, Dynamax Level 10) and Gardevoir, the Dynamax Band in the Bag; Roxanne
-- (a Gym Leader: GYMS & LEAGUE allows it) with her Pokemon made sturdy so the battle lasts:
--   FIGHT, R: Dynamax picked (START too; R never FireRed's Help) (the button, the Max Moves' names), a move: the Dynamax first, HP and max
--   HP x2.0, G-Max Wildfire's field on her side, its chip at the turn's end; three turns, then over
--   (HP back to its share); the battle left: the party's max HP its own again.
--   A wild battle under GYMS & LEAGUE: no Dynamax. Shots d*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dmax_probe.lua love .

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
  local Moves = require("src.core.game3.battle.moves")
  local Trainers = require("src.core.game3.scripting.trainers")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local Tt = X._test
  local Dm = Tt.dmax
  check(Dm ~= nil and Dm.installed, "Dynamax installed")
  if not Dm then return end
  local nd = game.mods.exports.national_dex_gen3
  local dx = nd and nd.dynamax
  check(dx ~= nil, "National Dex's Dynamax marks")

  local session = Runtime.getSession()
  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end
  session.party = {}
  Party.giveMon(session, sp("CHARIZARD"), 50)
  Party.giveMon(session, sp("GARDEVOIR"), 50)
  local zard = session.party[1]
  zard.moves = { mv("FLAMETHROWER"), mv("SLASH"), mv("GROWL"), mv("WING_ATTACK") }
  zard.pp = { 15, 20, 40, 35 }
  zard.maxPp = { 15, 20, 40, 35 }
  if dx then dx.setLevel(zard, 10); dx.setFactor(zard, true) end
  local baseMax = zard.maxHp
  -- (PROBE_FIT=1: WoobleView's Battle Fit and 3D Sizing on - the energy then placed by its
  -- battlerRect, wherever it draws the Pokemon)
  local wvx = game.mods.exports["gen3-hd-sprites"]
  if os.getenv("PROBE_FIT") == "1" and wvx then
    pcall(wvx.setFit, true)
    pcall(wvx.setRealSizes, true)
    log("  WoobleView: Battle Fit " .. tostring(wvx.fitEnabled and wvx.fitEnabled()))
    -- (PROBE_FILL=1: Fill Screen and the 3D Battle Scene too - the foe's HP box then placed over
    -- the highest head; its line and the zoom logged through the Dynamax)
    if os.getenv("PROBE_FILL") == "1" then
      pcall(wvx.setFill, true)
      pcall(wvx.setScene, true)
      log("  WoobleView: Fill " .. tostring(wvx.fillEnabled()) .. ", Scene " .. tostring(wvx.sceneEnabled()))
    end
  end
  local function boxLog(label)
    local core = wvx and wvx._core and wvx._core()
    local fit = core and core.fit
    if fit then
      log(("  box %s: boxBottom %s boxDy %s zoom %s headBox %s held %s"):format(label, tostring(fit.boxBottom),
        tostring(fit.boxDy), tostring(fit.z), tostring(fit.headBox), tostring(core.hudHeld)))
    end
  end
  local band = Tt.band
  Bag.add(session.bag, band.index, 1)
  check(Bag.has(session.bag, band.index, 1), "the Dynamax Band in the Bag")
  Tt.dmaxMode("league")

  -- (every battle message, logged)
  local push = Ui.push
  Ui.push = function(text, ...)
    log("  msg: " .. tostring(text):gsub("\n", " / "))
    return push(text, ...)
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
  local function toCommand(limit)
    -- (the battle opens after the field's transition: FireRed's trainers take longer)
    waitFor(function() return Battle.isActive() end, 3000)
    for _ = 1, limit or 6000 do
      if atCommand() or not Battle.isActive() then break end
      if not pump() then U.wait(1) end
    end
    return atCommand()
  end

  -- ------- the foe's side: a Gym Leader's ace Dynamaxes (her party cut to one: Lapras, last and so
  -- her ace, Gigantamaxing - the raids' art has its form), once, only while the player has the band
  local function foeSection()
    local UI = Tt.dmaxUi
    -- (POWER SPOTS: a wild battle on a route with an active den allows it, away from one not)
    if Tt.dens and Tt.dmaxMode then
      Tt.dmaxMode("spots")
      local live = Tt.dens.liveHere
      for _, here in ipairs({ true, false }) do
        Tt.dens.liveHere = function() return here end
        local okS = BattleBridge.startWild(Runtime._mod, game, { species = sp("ZIGZAGOON"), level = 3 }, {})
        check(okS == true and toCommand(), "spots: a wild battle " .. (here and "by a den" or "away from dens"))
        local stS = Battle.getState()
        check(stS and stS.__mr and (stS.__mr.allowed == here) and not stS.__mr.foe,
          "spots: Dynamax " .. (here and "allowed by an active den" or "not away from one") .. ", never the wild foe")
        Battle.abort("run")
        waitFor(function() return not Battle.isActive() end, 600)
        U.wait(30)
      end
      Tt.dens.liveHere = live
      Tt.dmaxMode(nil)
    end
    local by2 = C.trainers.byName
    local tid2 = by2.TRAINER_ROXANNE_1 or by2.TRAINER_ROXANNE or by2.TRAINER_LEADER_BROCK
    local foe = Trainers.foeFromId(tid2)
    local ace = foe.party[#foe.party]
    ace.species = sp("LAPRAS")
    ace.moves = { mv("ICE_BEAM"), mv("BODY_SLAM"), mv("PROTECT"), mv("GROWL") }
    foe.party = { ace }
    foe.species, foe.level, foe.moves = ace.species, ace.level, ace.moves
    for _, m in ipairs(session.party) do m.hp = m.maxHp end
    if dx then dx.setFactor(zard, false) end
    local ok, err = BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = tid2 })
    check(ok == true, "foe: her battle starts " .. tostring(err or ""))
    check(toCommand(), "foe: its command menu")
    local st = Battle.getState()
    local S = st and st.__mr
    check(S and S.foe and S.ace == 1, "foe: a Gym Leader's battle, her ace the last (" .. tostring(S and S.ace) .. ")")
    local can, why = Dm.foeCan(st, st.enemy)
    check(can, "foe: her ace may Dynamax (" .. tostring(why) .. ")")
    do
      local hb = Dm.hasBand
      Dm.hasBand = function() return false end
      local c2, w2 = Dm.foeCan(st, st.enemy)
      Dm.hasBand = hb
      check(not c2 and w2 == "band", "foe: not while the player has no band (" .. tostring(w2) .. ")")
    end
    local said = {}
    do
      local ad = Battle._adapter
      local pushEvent = ad.pushEvent
      ad.pushEvent = function(self, ev, ...)
        if type(ev) == "table" and ev.kind == "msg" then
          said[#said + 1] = tostring(ev.text)
          log("  says: " .. tostring(ev.text):gsub("\n", " / "))
        end
        return pushEvent(self, ev, ...)
      end
    end
    local baseMax = st.enemy.mon.maxHp
    -- (the player: Growl, no Dynamax; her Lapras Dynamaxes as the turn begins)
    for _ = 1, 6 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    U.tap(game, "down")
    U.wait(8)
    U.tap(game, "a")
    local SM = UI.SM
    local marks = { { SM.SLIDE + 0.3, "f01_trainer" }, { SM.BAND + 0.35, "f02_band" }, { SM.GROW + 0.4, "f03_grow" },
      { SM.ROAR + 0.1, "f04_roar" } }
    local nextMark, sceneFoe, scenes0 = 1, nil, UI.scenes
    for _ = 1, 4000 do
      if UI.sceneOn() and UI.sceneT() then
        if sceneFoe == nil then sceneFoe = UI.sceneFoe and UI.sceneFoe() end
        local t = UI.sceneT()
        if nextMark <= #marks and t >= marks[nextMark][1] then
          shot(marks[nextMark][2])
          nextMark = nextMark + 1
        end
        U.wait(1)
      else
        if atCommand() or not Battle.isActive() then break end
        if not pump() then U.wait(1) end
      end
    end
    local rec = st.enemy.__mrDmax
    check(UI.scenes == scenes0 + 1 and sceneFoe == true, "foe: her Dynamax scene played, mirrored")
    check(rec ~= nil, "foe: her Lapras Dynamaxed")
    check(rec and rec.gmax ~= nil, "foe: Gigantamaxed (" .. tostring(rec and rec.gmax) .. ")")
    check(st.enemy.mon.maxHp == math.floor(baseMax * 2.0), ("foe: max HP x2.0 at Level 10: %d -> %d"):format(baseMax,
      st.enemy.mon.maxHp))
    check(S.foeUsed and not S.used, "foe: once for her side; the player's still to use")
    check(Dm.can(st, st.player), "foe: Charizard may still Dynamax")
    local maxUsed = false
    for _, s in ipairs(said) do if s:find("MAX", 1, true) and s:find("used", 1, true) then maxUsed = true end end
    check(maxUsed, "foe: her move a Max Move")
    local v = Dm.vis[1]
    check(v and v.foe and v.art and v.art.front, "foe: drawn as the raid boss's G-Max front")
    U.wait(40)
    check(v and (v.k or 1) > 1.3, "foe: drawn giant (" .. tostring(v and v.k) .. ")")
    log(("  foe energy: placed by %s, motes %d; mark %s"):format(tostring(UI.lastEnergy), UI.energyCount() or 0,
      UI.lastMark and ("%s,%s"):format(tostring(UI.lastMark[5]), tostring(UI.lastMark[6])) or "none"))
    check((UI.energyCount() or 0) > 0, "foe: red energy off her giant")
    log(("  foe drawn: %s, kept under the top by %.2f"):format(v and v.nat and ("%.0f,%.0f-%.0f,%.0f"):format(v.nat[1],
      v.nat[2], v.nat[3], v.nat[4]) or "none", v and v.capK or 1))
    check(v and v.nat and v.nat[2] >= 1, "foe: its head on the field, under its top")
    shot("f05_giant")
    -- (the player's Charizard Dynamaxes too, its own once)
    for _ = 1, 6 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    U.tap(game, "r")
    U.wait(6)
    check(Dm.sel[0] == true, "foe: the player picks Dynamax against her giant")
    U.tap(game, "down")
    U.wait(8)
    U.tap(game, "a")
    local UI2 = UI
    if waitFor(function() return UI2.sceneOn() and (UI2.sceneT() or 0) > 0.5 end, 900) then
      check(st.player.__mrDmax ~= nil and st.enemy.__mrDmax ~= nil, "foe: both giants at once")
      U.tap(game, "b")
    else
      check(false, "foe: the player's Dynamax scene")
    end
    waitFor(function() return not UI2.sceneOn() end, 200)
    -- (her giant drawn on while Charizard's blow plays - the battle has worked out her faint
    -- already - until her faint's own animation)
    local Anim = require("src.core.game3.battle.anim")
    local faintMon, fainted = Anim.faintMon, false
    Anim.faintMon = function(id, ...)
      if id == 1 then fainted = true end
      return faintMon(id, ...)
    end
    local minK, frames, bothShot = 9, 0, false
    for _ = 1, 900 do
      if fainted or atCommand() or not Battle.isActive() then break end
      local v1 = Dm.vis[1]
      if v1 then minK = math.min(minK, v1.k or 1) end
      frames = frames + 1
      if frames == 40 and not bothShot then bothShot = true shot("f06_both") end
      if not pump() then U.wait(1) end
    end
    Anim.faintMon = faintMon
    log(("  foe after the player's Dynamax: %d frames, smallest drawn %.2f, fainted %s"):format(frames, minK,
      tostring(fainted)))
    check(minK > 1.3, "foe: drawn giant until her faint plays (" .. ("%.2f"):format(minK) .. ")")
    toCommand()
    Battle.abort("run")
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(30)
  end
  if os.getenv("PROBE_FOE_ONLY") == "1" then
    foeSection()
    log(("%d failures"):format(fails))
    return
  end

  -- ------- a wild battle: not under GYMS & LEAGUE
  local okW = BattleBridge.startWild(Runtime._mod, game, { species = sp("ZIGZAGOON"), level = 3 }, {})
  check(okW == true, "a wild battle starts")
  check(toCommand(), "its command menu")
  local st = Battle.getState()
  check(st and st.__mr and not st.__mr.allowed, "GYMS & LEAGUE: no Dynamax in a wild battle")
  Battle.abort("run")
  waitFor(function() return not Battle.isActive() end, 600)
  U.wait(60)

  -- ------- Roxanne
  -- (each version's first Gym Leader)
  local by = C.trainers.byName
  local tid = by.TRAINER_ROXANNE_1 or by.TRAINER_ROXANNE or by.TRAINER_LEADER_BROCK
  local foe = Trainers.foeFromId(tid)
  local ok, err = BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = tid })
  check(ok == true, "Roxanne's battle starts " .. tostring(err or ""))
  check(toCommand(), "her battle's command menu")
  st = Battle.getState()
  check(st.__mr and st.__mr.allowed, "GYMS & LEAGUE: a Gym Leader's battle allows it")
  do
    local ad = Battle._adapter
    local pushEvent = ad.pushEvent
    ad.pushEvent = function(self, ev, ...)
      if type(ev) == "table" and ev.kind == "msg" then log("  says: " .. tostring(ev.text):gsub("\n", " / ")) end
      return pushEvent(self, ev, ...)
    end
  end
  local can, why = Dm.can(st, st.player)
  check(can, "Charizard may Dynamax (" .. tostring(why) .. ")")
  -- (her Pokemon sturdy: the battle lasts past the three turns)
  local function sturdy()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 999, 999 end
    if st.enemy and st.enemy.mon then st.enemy.mon.maxHp, st.enemy.mon.hp = 999, 999 end
  end
  sturdy()
  U.tap(game, "a")
  U.wait(20)
  check(Ui._mode == "moves", "FIGHT: the move menu")
  U.tap(game, "r")
  U.wait(10)
  check(Dm.sel[0] == true, "R: Dynamax picked")
  local okHelp, Help = pcall(require, "src.ui.game3.help_system")
  check(not (okHelp and Help.isOpen and Help.isOpen()), "R: no Help System over the battle")
  local list = Dm.maxMovesOf(st.player, {})
  local names = {}
  for i = 1, 4 do names[i] = Moves.displayName(list[i]) end
  log("  Max Moves: " .. table.concat(names, ", "))
  check(names[1] == "G-MAX WILDFIRE" and names[3] == "MAX GUARD" and names[4] == "MAX AIRSTREAM",
    "Flamethrower -> G-Max Wildfire, Growl -> Max Guard, Wing Attack -> Max Airstream")
  U.wait(20)
  shot("d01_moves_dynamax")
  boxLog("before")
  U.tap(game, "start")
  U.wait(6)
  check(Dm.sel[0] == nil, "START: put back (START works as R)")
  -- a tap on the button picks it as R does (its middle, the game's 240 x 160 taken to the window)
  do
    local B = Tt.dmaxUi.BUTTON
    local wx, wy = uiScreen(Tt, B.x + B.w / 2, B.y + B.h / 2)
    game:pointerEvent("pressed", "mouse", "mouse", wx, wy)
    game:pointerEvent("released", "mouse", "mouse", wx, wy)
    U.wait(6)
    check(Dm.sel[0] == true, "a tap on DYNAMAX picks it")
  end
  U.tap(game, "a")
  -- the turn: the Dynamax first - its scene (shot through its parts, never pressed through), then
  -- the giant on the field
  local UI = Tt.dmaxUi
  local SM = UI.SM
  local scenes0 = UI.scenes
  local marks = { { SM.RECALL, "s01_tint" }, { SM.RECALL + 0.15, "s02_recall" }, { SM.BAND + 0.35, "s03_band" },
    { SM.BURST - 0.02, "s04_swell" }, { SM.BURST + 0.06, "s05_burst" }, { SM.LAND + 0.04, "s06_land" },
    { SM.OPEN + 0.15, "s07_open" }, { SM.GROW + 0.35, "s08_grow" }, { SM.ROAR + 0.1, "s09_roar" },
    { SM.HOLD, "s10_hold" } }
  local nextMark, sceneFrames, sceneHeld = 1, 0, false
  local grownShot, giantSeen = false, false
  for _ = 1, 4000 do
    local v = Dm.vis[0]
    if UI.sceneOn() and UI.sceneT() then
      sceneFrames = sceneFrames + 1
      local t = UI.sceneT()
      if t > SM.SLIDE and t < SM.OUT and require("src.core.game3.battle.anim").busy() then sceneHeld = true end
      if nextMark <= #marks and t >= marks[nextMark][1] then
        shot(marks[nextMark][2])
        nextMark = nextMark + 1
      end
      U.wait(1)
    else
      if v and (v.k or 1) > 1.45 then giantSeen = true end
      if giantSeen and not grownShot then U.wait(10) shot("d02_giant") grownShot = true end
      if atCommand() then break end
      if not pump() then U.wait(1) end
    end
  end
  log(("  the Dynamax scene: %d frames, %d of %d shots"):format(sceneFrames, nextMark - 1, #marks))
  check(UI.scenes == scenes0 + 1, "the Dynamax scene played")
  log(("  the scene's sounds: %d clips from the atlas (made in %.1f ms), the last %s"):format(UI.soundCount(),
    UI.warmMs or -1, tostring(UI.lastClip)))
  check(UI.soundCount() == 6 and UI.lastClip == "explosion3", "the scene played the plugin's own sounds")
  check(nextMark > #marks, "the scene went through all its parts")
  check(sceneHeld, "the battle held while it played")
  check((UI.patternDraws or 0) > 0, "the Dynamax pattern drawn (" .. tostring(UI.patternDraws) .. " passes)")
  local rec = st.player.__mrDmax
  check(rec ~= nil, "Charizard is Dynamaxed")
  check(st.player.mon.maxHp == math.floor(baseMax * 2.0), ("max HP x2.0 at Level 10: %d -> %d"):format(baseMax,
    st.player.mon.maxHp))
  check(giantSeen, "drawn giant")
  local d = st.enemySide and st.enemySide.__ndx
  check(d and d.mrField and d.mrField.type == "FIRE", "G-Max Wildfire: her side surrounded by fire")
  check(rec and rec.turns == 2, "two turns left")
  check(Dm.vis[0] and Dm.vis[0].flashT ~= nil, "G-Max Wildfire flashed red as it struck")
  -- (where its energy sheds: where WoobleView drew Charizard's body this frame, else where the battle did)
  do
    local wv = game.mods.exports["gen3-hd-sprites"]
    local x0, y0, x1, y1
    if wv and wv.battlerRect then x0, y0, x1, y1 = wv.battlerRect("player") end
    local v = Dm.vis[0]
    log(("  body: WoobleView's box %s; the battle's %s"):format(
      x0 and ("%d,%d-%d,%d"):format(x0, y0, x1, y1) or "none",
      v and v.nat and ("%.0f,%.0f-%.0f,%.0f"):format(v.nat[1], v.nat[2], v.nat[3], v.nat[4]) or "none"))
    check(x0 ~= nil or (v and v.nat ~= nil), "the giant's body is known for its energy")
    log("  energy placed by: " .. tostring(Tt.dmaxUi.lastEnergy) .. ", motes " .. tostring(Tt.dmaxUi.energyCount()))
    check((Tt.dmaxUi.energyCount() or 0) > 0, "red energy shedding off the giant")
    -- (the electricity: bolts come and go fast - watched over a second)
    local seen = 0
    local boltShot = false
    for _ = 1, 90 do
      seen = math.max(seen, Tt.dmaxUi.boltCount() or 0)
      if not boltShot and (Tt.dmaxUi.boltCount() or 0) > 0 then
        boltShot = true
        shot("d03c_bolt")
        local b = Tt.dmaxUi._bolt(1)
        if b then
          log(("  bolt: from %.0f,%.0f to %.0f,%.0f, width %.1f, %.2f of %.2f s"):format(b.xs[1], b.ys[1], b.xs[#b.xs],
            b.ys[#b.ys], b.width or 0, b.t, b.life))
        end
      end
      U.wait(1)
    end
    check(seen > 0, "red electricity crackling off it (" .. seen .. " at once)")
    -- (the Bag and the party screen over the battle: none of it shows there - WoobOS's glass ones
    -- and the game's own, its Battle Menus switched off)
    local PartyMenu = require("src.ui.game3.party_menu")
    local opts = game.mods and game.mods.modOptions
    local function screensOver(label)
      U.tap(game, "right")
      U.wait(8)
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "bag" end, 120)
      U.wait(30)
      check(Ui._mode == "bag", label .. ": the Bag opens over the battle")
      log(("  %s bag: motes %d, bolts %d"):format(label, Tt.dmaxUi.energyCount() or 0, Tt.dmaxUi.boltCount() or 0))
      check((Tt.dmaxUi.energyCount() or 0) == 0 and (Tt.dmaxUi.boltCount() or 0) == 0,
        label .. ": no energy or electricity over the Bag")
      shot("d03b_bag_" .. label)
      for _ = 1, 6 do
        if Ui._mode == "menu" then break end
        U.tap(game, "b")
        U.wait(30)
      end
      check(Ui._mode == "menu", label .. ": back from the Bag")
      U.tap(game, "left")
      U.wait(8)
      U.tap(game, "down")
      U.wait(8)
      U.tap(game, "a")
      waitFor(function() return PartyMenu.isOpen and PartyMenu.isOpen() end, 120)
      U.wait(30)
      log(("  %s party: open %s, mode %s, motes %d, bolts %d"):format(label,
        tostring(PartyMenu.isOpen and PartyMenu.isOpen()), tostring(Ui._mode), Tt.dmaxUi.energyCount() or 0,
        Tt.dmaxUi.boltCount() or 0))
      check(PartyMenu.isOpen and PartyMenu.isOpen(), label .. ": the party screen opens over the battle")
      check((Tt.dmaxUi.energyCount() or 0) == 0 and (Tt.dmaxUi.boltCount() or 0) == 0,
        label .. ": no energy or electricity over the party screen")
      shot("d03d_party_" .. label)
      for _ = 1, 6 do
        if Ui._mode == "menu" and not PartyMenu.isOpen() then break end
        U.tap(game, "b")
        U.wait(30)
      end
      check(Ui._mode == "menu", label .. ": back from the party screen")
      -- (the cursor back on FIGHT)
      U.wait(30)
      Ui._actionCursor[Ui._active or 0] = 1
      Ui._menuIndex = 1
    end
    screensOver("woobos")
    if opts then
      opts.woob_os = opts.woob_os or {}
      local was = opts.woob_os.menuBattle
      opts.woob_os.menuBattle = false
      screensOver("cart")
      opts.woob_os.menuBattle = was
    end
    -- (the party screen as the battle opens it itself - a faint's or a shift's switch - without its
    -- "party" mode)
    do
      local mode0 = Ui._mode
      Ui.openPartyMenu(st, 0, { onSelect = function() end })
      U.wait(30)
      log(("  battle's own party screen: open %s, mode %s, motes %d, bolts %d"):format(tostring(PartyMenu.isOpen()),
        tostring(Ui._mode), Tt.dmaxUi.energyCount() or 0, Tt.dmaxUi.boltCount() or 0))
      check(PartyMenu.isOpen() and Ui._mode ~= "party", "the battle's own party screen, not in its party mode")
      check((Tt.dmaxUi.energyCount() or 0) == 0 and (Tt.dmaxUi.boltCount() or 0) == 0,
        "no energy or electricity over the battle's own party screen")
      shot("d03e_party_battle")
      PartyMenu.close()
      Ui._mode = mode0
      U.wait(30)
      check(not PartyMenu.isOpen(), "the battle's own party screen closed")
    end
    -- (the cursor on FIGHT, whatever the screens left it on: the battle remembers it)
    U.wait(30)
    Ui._actionCursor[Ui._active or 0] = 1
    Ui._menuIndex = 1
    local lm = Tt.dmaxUi.lastMark
    if lm then
      log(("  mark: box %s,%s bar %s,%s -> mark %s,%s"):format(tostring(lm[1]), tostring(lm[2]), tostring(lm[3]),
        tostring(lm[4]), tostring(lm[5]), tostring(lm[6])))
    end
  end
  shot("d03_after_turn1")
  boxLog("Dynamaxed")
  do
    local core = wvx and wvx._core and wvx._core()
    if core and core.hudHeld ~= nil then check(core.hudHeld > 0, "WoobleView's HUD held while the giant is out") end
  end
  -- turns 2 and 3: the first move
  local fieldShot, lookShot, resT = false, false, nil
  local said = {}
  do
    local ad = Battle._adapter
    local pushEvent = ad.pushEvent
    ad.pushEvent = function(self, ev, ...)
      if type(ev) == "table" and ev.kind == "msg" then said[#said + 1] = tostring(ev.text) end
      return pushEvent(self, ev, ...)
    end
  end
  local function heard(pat)
    for _, s in ipairs(said) do if s:find(pat) then return true end end
    return false
  end
  local PROTECT = mv("PROTECT")
  -- (her choice made for her: turn 2 Protect - the Max Move strikes through for a quarter -, turn 3
  -- Tackle - into Max Guard)
  local Commands = require("src.core.game3.battle.commands")
  local enemyAction = Commands.enemyAction
  local forced = nil
  Commands.enemyAction = function(...)
    if forced then return { kind = "move", move = forced, slot = 1, user = "enemy", battler = 1 } end
    return enemyAction(...)
  end
  for turn = 2, 3 do
    sturdy()
    forced = turn == 2 and PROTECT or mv("TACKLE")
    -- (FIGHT until the move menu is up: a press while the battle settles is lost)
    for _ = 1, 6 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    if Ui._mode ~= "moves" then
      log(("  turn %d: mode %s, phase %s, cursor %s, party open %s, bag open %s"):format(turn, tostring(Ui._mode),
        tostring(Battle._phase), tostring(Ui._cursor or Ui._menuCursor), tostring(require("src.ui.game3.party_menu").isOpen()),
        tostring(require("src.ui.game3.bag_menu").isOpen())))
      shot("d0x_turn" .. turn .. "_stuck")
    end
    check(Ui._mode == "moves", "turn " .. turn .. ": the move menu")
    -- (turn 3: Growl's slot, Max Guard)
    if turn == 3 then U.tap(game, "down") U.wait(6) end
    U.tap(game, "a")
    waitFor(function() return Battle.isActive() end, 900)
    for _ = 1, 6000 do
      if atCommand() or not Battle.isActive() then break end
      -- (the turn's end: G-Max Wildfire's words, as the box shows them)
      -- (the flames on her Pokemon as the turn ends, before the words)
      if Battle._phase == "residuals" then resT = (resT or 0) + 1 else resT = nil end
      if not lookShot and resT == 14 then
        lookShot = true
        shot("d05a_field_look")
      end
      if not fieldShot and Battle._phase == "residuals" and Ui.dialogPending and Ui.dialogPending() then
        fieldShot = true
        U.wait(40)
        shot("d05_field_words")
      end
      if not pump() then U.wait(1) end
    end
    log(("  turn %d: Dynamaxed %s, max HP %d"):format(turn, tostring(st.player.__mrDmax ~= nil), st.player.mon.maxHp))
    boxLog("turn " .. turn)
  end
  forced = nil
  Commands.enemyAction = enemyAction
  check(heard("couldn't fully protect"), "her Protect: the Max Move through it for a quarter")
  check(heard("MAX GUARD"), "Growl as Max Guard")
  -- (her AI may switch instead of attacking)
  check(heard("protected itself") or heard("withdrew"), "Max Guard keeps her Tackle off (or she switched)")
  check(st.player.__mrDmax == nil, "over after three turns")
  check(st.player.mon.maxHp == baseMax, "max HP its own again: " .. tostring(st.player.mon.maxHp))
  check(st.__mr.used, "used for the battle")
  check(not Dm.can(st, st.player), "not again this battle")
  U.wait(30)
  shot("d04_after")
  boxLog("after")
  do
    local core = wvx and wvx._core and wvx._core()
    if core and core.hudHeld ~= nil then check(core.hudHeld == 0, "WoobleView's HUD let go once it is over") end
  end
  Battle.abort("run")
  waitFor(function() return not Battle.isActive() end, 600)
  U.wait(30)
  check(session.party[1].maxHp == baseMax, "the party's Charizard: its own max HP after the battle")

  -- ------- a double battle (Tate & Liza): one of the two, once; Charizard without its factor this
  -- time (a plain Dynamax: its own picture, bigger and red; Flamethrower as Max Flare: sunlight)
  local tl = by.TRAINER_TATE_AND_LIZA_1 or by.TRAINER_TATE_AND_LIZA
  if tl then
    if dx then dx.setFactor(zard, false) end
    session.party[1].hp = session.party[1].maxHp
    session.party[2].hp = session.party[2].maxHp
    local foe2 = Trainers.foeFromId(tl)
    local okD, errD = BattleBridge.start(Runtime._mod, game, foe2, { wild = false, trainerId = tl })
    check(okD == true, "Tate & Liza's battle starts " .. tostring(errD or ""))
    check(toCommand(), "its command menu")
    st = Battle.getState()
    check(st and st.double, "a double battle")
    check(st.__mr and st.__mr.allowed, "Gym Leaders: allowed")
    sturdy()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 999, 999 end
    -- battler 0: FIGHT, R, the first move, its target
    U.wait(30)
    for _ = 1, 5 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    local S0 = require("src.core.game3.battle.state").battler(st, 0)
    local can0, why0 = Dm.can(st, S0)
    log(("  doubles: mode %s, active %s, can %s %s"):format(tostring(Ui._mode), tostring(Ui._active),
      tostring(can0), tostring(why0)))
    U.tap(game, "r")
    U.wait(6)
    check(Dm.sel[0] == true, "doubles: the first picks Dynamax")
    U.tap(game, "a")
    U.wait(20)
    if Ui._mode == "target" then U.tap(game, "a") U.wait(20) end
    -- battler 2: no Dynamax for it this turn
    waitFor(function() return Ui._mode == "menu" and (Ui._active or 0) == 2 end, 300)
    local b2 = E_battler and E_battler(st, 2) or require("src.core.game3.battle.state").battler(st, 2)
    check(not Dm.can(st, b2), "doubles: the second may not while the first has")
    for _ = 1, 5 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      waitFor(function() return Ui._mode == "moves" end, 40)
    end
    check(Ui._mode == "moves", "doubles: the second's move menu")
    U.tap(game, "r")
    U.wait(6)
    check(Dm.sel[2] == nil, "doubles: R does nothing for the second")
    U.tap(game, "a")
    U.wait(20)
    if Ui._mode == "target" then U.tap(game, "a") U.wait(20) end
    -- (its scene skipped with B a moment in)
    local UI = Tt.dmaxUi
    if waitFor(function() return UI.sceneOn() and (UI.sceneT() or 0) > 0.6 end, 900) then
      U.tap(game, "b")
      local n = 0
      while UI.sceneOn() and n < 300 do U.wait(1) n = n + 1 end
      log(("  doubles: the scene skipped, gone %d frames after B"):format(n))
      check(n < 60, "doubles: B skips the Dynamax scene")
    else
      check(false, "doubles: the Dynamax scene played")
    end
    toCommand()
    local b0 = require("src.core.game3.battle.state").battler(st, 0)
    check(b0 and b0.__mrDmax ~= nil, "doubles: the first Dynamaxed")
    check(b0 and b0.__mrDmax and b0.__mrDmax.gmax == nil, "doubles: without the factor, a plain Dynamax")
    check(st.weather == "SUNNY", "Max Flare: the sunlight turned harsh (" .. tostring(st.weather) .. ")")
    U.wait(30)
    do
      local v = Dm.vis[0]
      local pb = v and v.picBox
      log(("  doubles energy: picture box %s outline points %s; drawn %s; placed by %s"):format(
        pb and ("%d,%d-%d,%d"):format(pb[1], pb[2], pb[3], pb[4]) or "none", pb and pb.edges and tostring(#pb.edges) or "-",
        v and v.nat and ("%.0f,%.0f-%.0f,%.0f"):format(v.nat[1], v.nat[2], v.nat[3], v.nat[4]) or "none",
        tostring(Tt.dmaxUi.lastEnergy)))
      check(pb ~= nil, "doubles: the giant's own picture measured for its outline")
      local wv = game.mods.exports["gen3-hd-sprites"]
      local spec = wv and wv.tagOf and v and v.picImg and wv.tagOf(v.picImg)
      if spec then
        local keys = {}
        for k2, val in pairs(spec) do keys[#keys + 1] = k2 .. "=" .. (type(val) == "table" and "{" .. table.concat(
          (function() local o = {} for _, x in ipairs(val) do o[#o + 1] = tostring(x) end return o end)(), ",") .. "}"
          or tostring(val)) end
        log("  doubles: its WoobleView tag " .. table.concat(keys, " "))
        local iw, ih = v.picImg:getDimensions()
        log(("  doubles: its picture %dx%d, a %s"):format(iw, ih, v.picImg:typeOf("Canvas") and "Canvas" or "Image"))
        local a0, b0, c0, d0 = wv.battlerRect(0)
        local a1, b1, c1, d1 = wv.battlerRect("player")
        log(("  doubles: WoobleView's box for 0: %s; for the player's side: %s"):format(
          a0 and ("%d,%d-%d,%d"):format(a0, b0, c0, d0) or "none", a1 and ("%d,%d-%d,%d"):format(a1, b1, c1, d1) or "none"))
      else
        log("  doubles: its picture has no WoobleView tag")
      end
    end
    shot("d06_doubles")
    check(not Dm.can(st, b2), "doubles: once a battle")
    Battle.abort("run")
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(30)
    check(session.party[1].maxHp == baseMax, "after the double battle: its own max HP")
  end
  foeSection()
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
