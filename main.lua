-- Galar Rising: Sword / Shield's Max Raid Battles on the Gen 3 games, with National Dex Gen 3's
-- species, moves, Fairy type and abilities. A giant Gigantamax boss (the Giga Megas pack) against
-- four of the party in a 3D den, on a layer of its own over the field, drawn at the window's
-- resolution.
--
--   main.lua            options, the modules, the layer, the hooks (render.hud draws the raid over
--                       the whole window; input.pointer feeds the battle pad), exports
--   src/raid.lua        the raid's controller (boss pictures and cry, the four, intro, HUD, pad)
--   src/raid_scene.lua  the den in 3D (src/render3d.lua over the vendored g3d) and the sprites
--   src/pad.lua         the battle pad (FIGHT / ITEM / FLEE)
--   src/hd.lua          crisp pixel-art drawing at any scale
--   src/pad_hide.lua    the engine's touch pad hidden while a raid is up
--   data/               the bosses (raid_bosses.lua, raid_sprites.lua generated), the rules

-- A mod's own files load as chunks through mod:read; require() cannot see them.
local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  mod.options:define({
    -- Kanto Gear's display options decide where the battle pad goes (as PlayNav's K-GEAR): its
    -- SEPARATE SCREENS puts it on the second screen, FULLSCREEN / COMBINED keep it on the main one;
    -- without the Gear, a second display when one is there. Off: BATTLE PAD below decides.
    { key = "kanto_gear", label = "KANTO GEAR", type = "toggle", default = true },
    -- where the battle pad goes: over the den on the main screen, or the device's second screen
    -- (the main screen then keeps the whole den)
    { key = "battle_pad", label = "BATTLE PAD", type = "choice", default = "main",
      choices = { { "MAIN SCREEN", "main" }, { "SECOND SCREEN", "second" } },
      visible_if = { key = "kanto_gear", equals = false } },
    -- dens on the routes (off: none spawn; those already chosen stay saved)
    { key = "dens", label = "RAID DENS", type = "toggle", default = true },
    -- the engine's frame-time readout with the raid's parts, and the slowest frames with what the
    -- raid was doing, shown while a den is open: for reporting slowdowns
    { key = "perf_overlay", label = "PERFORMANCE", type = "toggle", default = false },
  })

  local N = loadSibling(mod, "data/raid_rules.lua")
  local Bosses = loadSibling(mod, "data/raid_bosses.lua")
  local Sprites = loadSibling(mod, "data/raid_sprites.lua")
  local Gmax = loadSibling(mod, "data/raid_gmax.lua")
  local MaxPower = loadSibling(mod, "data/raid_maxpower.lua")
  local TeamMoves = loadSibling(mod, "data/raid_team_moves.lua")
  local MusicData = loadSibling(mod, "data/raid_music.lua")
  local makeMusic = loadSibling(mod, "src/raid_music.lua")
  local HD = loadSibling(mod, "src/hd.lua")
  local makeRender3d = loadSibling(mod, "src/render3d.lua")
  local makeScene = loadSibling(mod, "src/raid_scene.lua")
  local makePad = loadSibling(mod, "src/pad.lua")
  local makeBattlerHud = loadSibling(mod, "src/battler_hud.lua")
  local makeBattle = loadSibling(mod, "src/battle.lua")
  local Sim = loadSibling(mod, "src/raid_sim.lua")
  local makeRewards = loadSibling(mod, "src/rewards.lua")
  local makeFx = loadSibling(mod, "src/fx.lua")
  local MoveFx = loadSibling(mod, "data/raid_move_fx.lua")
  local Sounds = loadSibling(mod, "data/raid_sounds.lua")
  local makeRaid = loadSibling(mod, "src/raid.lua")
  local makePadHide = loadSibling(mod, "src/pad_hide.lua")
  local makeDens = loadSibling(mod, "src/dens.lua")
  local makeScreen2 = loadSibling(mod, "src/screen2.lua")
  local makeDen = loadSibling(mod, "src/den_screen.lua")
  local makePick = loadSibling(mod, "src/pc_pick.lua")
  local makeDyna = loadSibling(mod, "src/dyna.lua")
  if not (N and Bosses and Sprites and makeScene and makePad and makeRaid) then
    mod.log:error("Galar Rising is missing files; it stays off -- reinstall the mod")
    return
  end
  if HD then mod.hd = HD end

  local Scene = nil
  do
    local ok, sc = pcall(makeScene, mod, { Render3d = makeRender3d })
    if ok and type(sc) == "table" then Scene = sc else mod.log:warn("the den failed to build: %s", tostring(sc)) end
  end
  local Pad = makePad(mod, {})
  local Rewards = nil
  if makeRewards then
    local ok, rw = pcall(makeRewards, mod, { N = N, Bosses = Bosses, Sprites = Sprites })
    if ok and type(rw) == "table" then Rewards = rw else mod.log:warn("the raid's rewards failed to build: %s", tostring(rw)) end
  end
  local Battle = nil
  if makeBattle then
    -- (the National Dex's exports: what its newer moves do besides their damage)
    local function dex()
      local ok, d = pcall(mod.find, mod, "national_dex_gen3")
      return ok and type(d) == "table" and d.exports or nil
    end
    local ok, bt = pcall(makeBattle, mod, { N = N, Bosses = Bosses, Sprites = Sprites, Gmax = Gmax, MaxPower = MaxPower,
      TeamMoves = TeamMoves, dex = dex })
    if ok and type(bt) == "table" then Battle = bt else mod.log:warn("the raid's battle failed to build: %s", tostring(bt)) end
    -- (the rewards read the TMs' moves through it)
    if Battle and Rewards then Rewards.battle = Battle end
  end
  -- the red dens' Dynamax Pokemon: the route's, as boss records under "DYNA:" keys
  local Dyna = nil
  if makeDyna then
    local ok, dy = pcall(makeDyna, mod, { N = N, Bosses = Bosses, Sprites = Sprites,
      typeName = Battle and Battle.typeName or nil })
    if ok and type(dy) == "table" then
      Dyna = dy
      Dyna.install()
    else
      mod.log:warn("the Dynamax dens failed to build: %s", tostring(dy))
    end
  end
  local BattlerHud = makeBattlerHud and makeBattlerHud(mod, { drawPixel = HD and HD.drawPixel or nil }) or nil
  local PadHide = makePadHide and makePadHide(mod) or nil
  -- the den screen's PC: the game's boxes, to choose a Pokemon from
  local Pick = nil
  if makePick then
    local ok, pk = pcall(makePick, mod)
    if ok and type(pk) == "table" then Pick = pk else mod.log:warn("the den's PC failed to build: %s", tostring(pk)) end
  end

  -- the pad on the second screen: chosen, and the display there (else it stays on the main one)
  local padForced = nil   -- (drivers: _test.padSecond)
  -- one of Kanto Gear's options, read from the loader as the engine's own options:get does (stored,
  -- else its default); nil when the Gear is not installed, disabled or failed (as PlayNav reads it)
  local lastGame = nil   -- (the game, from the hooks)
  local gearForced = nil -- (drivers: _test.gearOptions(t), a stand-in Gear's options; false = no Gear)
  -- (any mod's option the same way: modOption(id, key))
  local function modOption(id, key)
    local loader = lastGame and lastGame.mods
    local rec = loader and loader.mods and loader.mods[id]
    if not rec or rec.state == "disabled" or rec.state == "failed" then return nil end
    local stored = loader.modOptions and loader.modOptions[id]
    local v = stored and stored[key]
    if v == nil then
      for _, row in ipairs(loader.optionSchemas and loader.optionSchemas[id] or {}) do
        if row.key == key then v = row.default end
      end
    end
    return v
  end
  local function gearOption(key)
    if gearForced ~= nil then return gearForced and gearForced[key] or nil end
    return modOption("kanto_gear", key)
  end
  -- the battle pad on the second screen: KANTO GEAR on follows the Gear's DISPLAY MODE (SEPARATE
  -- SCREENS -> second; FULLSCREEN, COMBINED, PHONE -> main; no Gear -> second when a display is
  -- there), off follows BATTLE PAD
  local Screen2 = nil
  local function padWanted()
    if padForced ~= nil then return padForced end
    if mod.options:get("kanto_gear") ~= false then
      local mode = gearOption("display_mode")
      if mode ~= nil then return mode == "separate" end
      return Screen2 ~= nil and Screen2.detected() == true
    end
    return mod.options:get("battle_pad") == "second"
  end
  local function padOnSecond()
    return padWanted() and Screen2 ~= nil and Screen2.detected()
  end

  -- ------- the layer over the field (the engine's Gen 3 UI stack): it pauses the field, takes the
  -- pad and keyboard, and is updated outside the draw (where the den renders); it paints black in
  -- the 240x160 pass, the raid itself is drawn over the whole window from render.hud

  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  if not (okStack and type(Stack) == "table") then Stack = nil end
  local LAYER_ID = "max_raids"
  local Raid
  local Dens = nil
  local Layer = { isMenu = true }
  function Layer.handleInput(input) if Raid then Raid.input(input) end end
  function Layer.update(dt)
    if Raid then Raid.update(dt) end
    -- (the second screen's frame: drawn here, outside any draw)
    if Screen2 then
      local ok, err = pcall(Screen2.update)
      if not ok then mod.log:warn("second screen failed: %s", tostring(err)) end
    end
  end
  function Layer.draw()
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 240, 160)
      G.setColor(1, 1, 1, 1)
    end
  end

  Raid = makeRaid(mod, { N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene, Pad = Pad, HD = HD,
    BattlerHud = BattlerHud, Battle = Battle, Sim = type(Sim) == "table" and Sim or nil, Gmax = Gmax, TeamMoves = TeamMoves,
    Rewards = Rewards, Fx = makeFx and makeFx({ Scene = Scene }) or nil, MoveFx = MoveFx, Sounds = Sounds,
    makeDen = makeDen, Pick = Pick, Dyna = Dyna, MusicData = MusicData,
    Music = (function()
      if not makeMusic then return nil end
      local okA, AudioM = pcall(require, "src.core.game3.audio")
      local ok, m = pcall(makeMusic, mod, { data = MusicData, Audio = okA and AudioM or nil })
      return ok and m or nil
    end)(),
    -- a won raid: its den is done for the day
    onEnd = function(den, outcome, raid)
      -- (won, or left by Run: spent for the day - not by a Dynamax Crystal's legendary raid, which
      -- leaves the den as it was)
      if raid and raid.legend then return end
      if (outcome == "win" or outcome == "fled") and den and Dens and Dens.finish then pcall(Dens.finish, den) end
    end,
    padOnSecond = padOnSecond,
    onOpen = function()
      if Stack then
        local ok, err = pcall(Stack.push, LAYER_ID, Layer, { hideBelow = true, fullscreen = true })
        if not ok then mod.log:warn("the raid's layer could not open: %s", tostring(err)) end
      end
    end,
    onClose = function()
      if Stack then pcall(Stack.pop, LAYER_ID) end
    end,
  })

  if makeScreen2 then
    local ok, s2 = pcall(makeScreen2, mod, { Pad = Pad, raid = Raid, on = padWanted,
      press = function(id, released) return Raid.secondPress(id, released) end })
    if ok and type(s2) == "table" then Screen2 = s2 else mod.log:warn("the second screen failed to build: %s", tostring(s2)) end
  end

  -- ------- dens on the routes: A on one opens its den screen (src/dens.lua)
  if makeDens then
    -- (the day follows National Dex Gen 3's CLOCK SOURCE: Device -> the device's date)
    local ok, dn = pcall(makeDens, mod, { N = N, Bosses = Bosses, Dyna = Dyna, open = function(den) return Raid.openDen(den) end,
      clockSource = function() return modOption("national_dex_gen3", "clock_source") end })
    if ok and type(dn) == "table" then
      Dens = dn
      Dens.registerSprites()
      local okI, err = pcall(Dens.install)
      if not okI then mod.log:warn("dens not installed: %s", tostring(err)) end
    else
      mod.log:warn("dens failed to build: %s", tostring(dn))
    end
  end

  -- ------- PERFORMANCE: the engine's frame profiler (its F3 overlay) shown, the raid's parts timed
  -- as its sections (a push / pop that returns at once while it is off), the raid's doings added to
  -- its slow-frame label, and the slowest frames listed at the top right
  local okFP, FP = pcall(require, "src.core.FrameProfiler")
  if not (okFP and type(FP) == "table" and FP.push and FP.pop) then FP = nil end
  local perfOn = false
  local slowText, slowAt = "", -1
  if FP then
    local function timed(tbl, key, name)
      local f = type(tbl) == "table" and tbl[key]
      if type(f) ~= "function" then return end
      local push, pop = FP.push, FP.pop
      local function out(...) pop(name); return ... end
      tbl[key] = function(...) push(name); return out(f(...)) end
    end
    timed(Raid, "update", "raid update")
    timed(Raid, "draw", "raid draw")
    timed(Raid, "stepWarm", "raid sounds")
    timed(Scene, "prepare", "raid 3d")
    timed(Scene, "draw", "raid scene")
    local Fx = Raid.Fx
    timed(Fx, "update", "raid fx")
    timed(Fx, "draw", "raid fx")
    timed(Fx, "drawLayer", "raid fx")
    timed(BattlerHud, "drawOrder", "raid hud")
    timed(BattlerHud, "drawPanel", "raid hud")
    timed(BattlerHud, "drawRows", "raid hud")
    timed(Pad, "draw", "raid pad")
    timed(Pad, "drawSecond", "raid pad")
    timed(Screen2, "update", "raid 2nd screen")
    local engineLabel = FP.context
    FP.context = function()
      local base = engineLabel and engineLabel() or nil
      local raid = Raid.active() and Raid.perfLabel and Raid.perfLabel() or nil
      if raid then return base and (base .. " " .. raid) or raid end
      return base
    end
  end
  -- the slowest frames (the engine's spike list), a line each and its largest sections
  local function drawSlowFrames(G, w, h)
    local now = love.timer.getTime()
    if now - slowAt >= 0.5 then
      slowAt = now
      local lines = { "slowest frames" }
      for i, sp in ipairs(FP.spikeList and FP.spikeList() or {}) do
        if i > 6 then break end
        lines[#lines + 1] = ("%5.1f ms  %s"):format(sp.total or 0, tostring(sp.ctx))
        local secs = {}
        for _, e in ipairs(sp.secs or {}) do secs[#secs + 1] = e end
        table.sort(secs, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for k = 1, math.min(4, #secs) do parts[#parts + 1] = ("%s %.1f"):format(secs[k][1], secs[k][2]) end
        lines[#lines + 1] = "    " .. table.concat(parts, ", ")
      end
      slowText = table.concat(lines, "\n")
    end
    local k = math.max(1, math.floor(h / 540))
    local font = G.getFont()
    local bw = math.floor(w / k * 0.5)
    local _, wrapped = font:getWrap(slowText, bw - 8)
    G.push("all")
    G.origin()
    G.scale(k)
    local x = w / k - bw - 4
    G.setColor(0, 0, 0, 0.6)
    G.rectangle("fill", x, 4, bw, font:getHeight() * #wrapped + 8)
    G.setColor(1, 1, 1, 1)
    G.printf(slowText, x + 4, 8, bw - 8, "left")
    G.pop()
  end

  -- the raid over the whole window, after the engine's own HUD
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    lastGame = game or lastGame
    local res = next(game, viewport)
    -- (PERFORMANCE: the engine's overlay up while a den is open - the den screen through the
    -- rewards -, put away when it closes; each den's numbers and slowest frames begin afresh)
    if FP then
      local want = mod.options:get("perf_overlay") == true and Raid.active() == true
      if want ~= perfOn then
        perfOn = want
        pcall(FP.setEnabled, want)
      end
    end
    -- (the raid's music: fed and faded every frame, a raid up or not - a fade out runs past its close)
    if Raid and Raid.music_ then pcall(Raid.music_.update, love.timer and love.timer.getDelta() or 1 / 60) end
    -- (the game's summary over the raid: it draws itself, with the engine's touch pad)
    local up = Raid.active() and not Raid.summaryUp()
    if PadHide then pcall(PadHide.apply, PadHide, up and not padOnSecond(), game) end
    if up then
      local G = love.graphics
      local w = type(viewport) == "table" and viewport.width or G.getWidth()
      local h = type(viewport) == "table" and viewport.height or G.getHeight()
      G.push("all")
      G.origin()
      G.setScissor()
      G.setShader()
      G.setBlendMode("alpha")
      local ok, err = pcall(Raid.draw, G, w, h)
      G.pop()
      if not ok then mod.log:warn("raid draw failed: %s", tostring(err)) end
    end
    if FP and FP.enabled then
      local G = love.graphics
      local w = type(viewport) == "table" and viewport.width or G.getWidth()
      local h = type(viewport) == "table" and viewport.height or G.getHeight()
      pcall(drawSlowFrames, G, w, h)
    end
    return res
  end)

  -- taps and clicks on the battle pad (the main window's)
  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if Raid.active() and not Raid.summaryUp() and type(ev) == "table" and Raid.pointer(ev) then return true end
    return next(game, ev)
  end)

  -- ------- Kanto Gear: while a raid is up the Gear stands down entirely (its panel, its second
  -- screen, its touches), through its public third-party modules API - a module whose shown()
  -- is true makes it step aside (kanto_gear runtime/modules.lua anyShown). The module is never
  -- available, so it has no tile in the Silph Store; nothing of the Gear's own code is touched.
  do
    local gear = mod.find and mod:find("kanto_gear")
    local modules = gear and gear.exports and gear.exports.modules
    if modules and modules.api == 1 and type(modules.register) == "function" then
      local okReg, registered, why = pcall(modules.register, {
        id = "max_raids", label = "MAX RAIDS", category = "GAMES", accent = "red",
        description = { "Max Raid Battles in dens on the routes." },
        -- a red den with a beam (drawn only if a tile ever shows)
        icon = function(x, y)
          local G = love.graphics
          G.setColor(0.85, 0.15, 0.2, 1)
          G.rectangle("fill", x + 10, y + 2, 4, 14)
          G.setColor(0.35, 0.3, 0.28, 1)
          G.ellipse("fill", x + 12, y + 19, 10, 4)
          G.setColor(1, 1, 1, 1)
        end,
        available = function() return false end,
        open = function() return false end,
        shown = function() return Raid.active() end,
      })
      if okReg and registered == true then
        mod.log:info("Kanto Gear stands down while a raid is up (store module, no tile)")
      else
        mod.log:warn("Kanto Gear module registration refused: %s", tostring(okReg and why or registered))
      end
    end
  end

  -- ------- exports

  mod.exports.raid = Raid
  mod.exports.open = function(key, opts) return Raid.open(key, opts) end
  mod.exports.close = function() return Raid.close() end
  mod.exports.state = function() return Raid.state() end
  mod.exports.bosses = function() return Bosses.ORDER end
  -- whether the battle pad is on the second display now (a raid open past its den screen, the pad
  -- sent there): a mod sharing the display (NaviPlay) stands down meanwhile. Cheap: the flag the
  -- pad's last update step left, so it can be asked every frame
  mod.exports.secondScreenShown = function()
    return Screen2 ~= nil and Screen2.state.on == true and Raid ~= nil and Raid.active() == true
  end
  mod.exports.dens = Dens
  mod.exports._test = { scene = Scene, pad = Pad, rules = N, dens = Dens, battlerHud = BattlerHud, battle = Battle, sim = Sim,
    rewards = Rewards, fx = Raid and Raid.Fx or nil, screen2 = Screen2, sounds = Sounds, pick = Pick, dyna = Dyna,
    padSecond = function(on) padForced = on end,
    gearOptions = function(t) gearForced = t end, padWanted = function() return padWanted() end }
  mod.log:info("Galar Rising ready (%d bosses)", #(Bosses.ORDER or {}))
end
