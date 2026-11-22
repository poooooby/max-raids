-- Driver: Dynamax in the game's own battles (src/dmax.lua, src/dmax_ui.lua), end to end. A party of
-- Charizard (Gigantamax Factor, Dynamax Level 10) and Gardevoir, the Dynamax Band in the Bag; Roxanne
-- (a Gym Leader: GYMS & LEAGUE allows it) with her Pokemon made sturdy so the battle lasts:
--   FIGHT, R: Dynamax picked (START too; R never FireRed's Help) (the button, the Max Moves' names), a move: the Dynamax first, HP and max
--   HP x2.0, G-Max Wildfire's field on her side, its chip at the turn's end; three turns, then over
--   (HP back to its share); the battle left: the party's max HP its own again.
--   A wild battle under GYMS & LEAGUE: no Dynamax. Shots d*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dmax_probe.lua love .

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
    local Viewport = require("src.render.GameViewport")
    local Display = require("src.core.game3.display")
    local vw, vh = Viewport.dimensions()
    local sx, ox, oy, _, _, sy = Display.fit(vw, vh)
    local B = Tt.dmaxUi.BUTTON
    local wx, wy = ox + (B.x + B.w / 2) * sx, oy + (B.y + B.h / 2) * (sy or sx)
    game:pointerEvent("pressed", "mouse", "mouse", wx, wy)
    game:pointerEvent("released", "mouse", "mouse", wx, wy)
    U.wait(6)
    check(Dm.sel[0] == true, "a tap on DYNAMAX picks it")
  end
  U.tap(game, "a")
  -- the turn: the Dynamax first
  local grownShot, giantSeen = false, false
  for _ = 1, 4000 do
    local v = Dm.vis[0]
    if v and (v.k or 1) > 1.45 then giantSeen = true end
    if giantSeen and not grownShot then U.wait(10) shot("d02_giant") grownShot = true end
    if atCommand() then break end
    if not pump() then U.wait(1) end
  end
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
    -- (the Bag over the battle: none of it shows there)
    U.tap(game, "right")
    U.wait(8)
    U.tap(game, "a")
    waitFor(function() return Ui._mode == "bag" end, 120)
    U.wait(20)
    check(Ui._mode == "bag", "the Bag opens over the battle")
    check((Tt.dmaxUi.energyCount() or 0) == 0 and (Tt.dmaxUi.boltCount() or 0) == 0,
      "no energy or electricity over the Bag")
    shot("d03b_bag")
    for _ = 1, 6 do
      if Ui._mode == "menu" then break end
      U.tap(game, "b")
      U.wait(30)
    end
    check(Ui._mode == "menu", "back from the Bag")
    U.tap(game, "left")
    U.wait(8)
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
