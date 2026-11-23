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
  -- ------- the words' language (src/i18n.lua): set before the options are defined, so their labels
  -- are in it; a change labels them again at once
  local makeI18n = loadSibling(mod, "src/i18n.lua")
  local I18n = makeI18n and makeI18n({
    read = function(path) return mod:read(path) end,
    cache = mod.cache,
    log = function(fmt, ...) mod.log:warn(fmt, ...) end,
  }) or nil
  local function plainWords(s, ...) if select("#", ...) > 0 then return s:format(...) end return s end
  local T = I18n or setmetatable({ mark = function(s) return s end, c = function(_, s, ...) return plainWords(s, ...) end,
    game = plainWords, cgame = function(_, s, ...) return plainWords(s, ...) end, t = plainWords,
    setLanguage = function() return "en" end, language = function() return "en" end, refresh = function() end },
    { __call = function(_, s, ...) return plainWords(s, ...) end })
  local function language()
    local v = mod.options:get("language")
    return v ~= nil and v or "en"
  end
  T.setLanguage(language())

  local function defineOptions()
    local schema = {
      -- Kanto Gear's display options decide where the battle pad goes (as PlayNav's K-GEAR): its
      -- SEPARATE SCREENS puts it on the second screen, FULLSCREEN / COMBINED keep it on the main one;
      -- without the Gear, a second display when one is there. Off: BATTLE PAD below decides.
      { key = "kanto_gear", label = "KANTO GEAR", type = "toggle", default = true },
      -- where the battle pad goes: over the den on the main screen, or the device's second screen
      -- (the main screen then keeps the whole den)
      { key = "battle_pad", label = "BATTLE PAD", type = "choice", default = "main",
        choices = { { "MAIN SCREEN", "main" }, { "SECOND SCREEN", "second" } },
        visible_if = { key = "kanto_gear", equals = false } },
      -- the bosses' strength: Solo raises their HP and attacks for a team of four of the player's own
      -- (data/raid_rules.lua RAID.SOLO), Sword / Shield keeps the games' own numbers
      { key = "difficulty", label = "RAID DIFFICULTY", type = "choice", default = "solo",
        choices = { { "SOLO", "solo" }, { "SWORD / SHIELD", "swsh" } } },
      -- how a move does on the boss, under its button: basic words ("Super effective"), full the
      -- multiplier (2x, 1/2x), or nothing
      { key = "move_info", label = "MOVE INFO", type = "choice", default = "basic",
        choices = { { "BASIC", "basic" }, { "FULL", "full" }, { "OFF", "off" } } },
      -- dens on the routes (off: none spawn; those already chosen stay saved)
      { key = "dens", label = "RAID DENS", type = "toggle", default = true },
      -- Dynamax in the game's own battles (src/dmax.lua), with the Dynamax Band: the Gym Leaders',
      -- the Elite Four's, the Champion's and the rivals' battles; those and any battle on a route
      -- with an active den (Sword / Shield's Power Spots); every trainer's; every battle; or none.
      -- The League's trainers Dynamax their last Pokemon wherever the player may
      { key = "dynamax", label = "DYNAMAX", type = "choice", default = "league",
        choices = { { "GYMS & LEAGUE", "league" }, { "POWER SPOTS", "spots" }, { "ALL TRAINERS", "trainers" },
          { "ALL BATTLES", "all" }, { "OFF", "off" } } },
      -- the engine's frame-time readout with the raid's parts, and the slowest frames with what the
      -- raid was doing, shown while a den is open: for reporting slowdowns
      { key = "perf_overlay", label = "PERF.OVERLAY", type = "toggle", default = false },
      -- the language of the mod's own words (data/lang/<code>.lua); CUSTOM: the player's own file
      -- (mod_cache/max_raids/lang_custom.lua in the game's save folder, written on first choosing it)
      { key = "language", label = "LANGUAGE", type = "choice", default = "en",
        choices = { { "ENGLISH", "en" }, { "にほんご", "ja" }, { "PORTUGUÊS", "pt" }, { "ESPAÑOL", "es" },
          { "DEUTSCH", "de" }, { "CUSTOM", "custom" } } },
    }
    -- the labels and choices in the language (the LANGUAGE row's choices are each language's own name)
    for _, row in ipairs(schema) do
      row.label = T.cgame("option", row.label)
      if row.key ~= "language" then
        for _, choice in ipairs(row.choices or {}) do choice[1] = T.cgame("choice", choice[1]) end
      end
    end
    mod.options:define(schema)
  end
  defineOptions()
  mod.events:on("mod.options_changed", function(ev)
    if not (ev and ev.mod == mod.id and ev.key == "language") then return end
    T.setLanguage(language())
    defineOptions()
  end)

  local N = loadSibling(mod, "data/raid_rules.lua")
  local Bosses = loadSibling(mod, "data/raid_bosses.lua")
  local Sprites = loadSibling(mod, "data/raid_sprites.lua")
  local Gmax = loadSibling(mod, "data/raid_gmax.lua")
  local MaxPower = loadSibling(mod, "data/raid_maxpower.lua")
  local TeamMoves = loadSibling(mod, "data/raid_team_moves.lua")
  local Phases = loadSibling(mod, "data/raid_phases.lua")
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
  local PixelFx = loadSibling(mod, "data/raid_pixelfx.lua")
  local Sounds = loadSibling(mod, "data/raid_sounds.lua")
  local makeRaid = loadSibling(mod, "src/raid.lua")
  local makePadHide = loadSibling(mod, "src/pad_hide.lua")
  local makeDens = loadSibling(mod, "src/dens.lua")
  local makeScreen2 = loadSibling(mod, "src/screen2.lua")
  local makeDen = loadSibling(mod, "src/den_screen.lua")
  local makePick = loadSibling(mod, "src/pc_pick.lua")
  local makeDyna = loadSibling(mod, "src/dyna.lua")
  local makeApi = loadSibling(mod, "src/raid_api.lua")
  local makeAchievements = loadSibling(mod, "src/achievements.lua")
  local AchievementData = loadSibling(mod, "data/raid_achievements.lua")
  local DmaxData = loadSibling(mod, "data/dmax_battle.lua")
  local DmaxSounds = loadSibling(mod, "data/dmax_sounds.lua")
  local makeDmaxRules = loadSibling(mod, "src/dmax_rules.lua")
  local makeDmax = loadSibling(mod, "src/dmax.lua")
  local makeDmaxUi = loadSibling(mod, "src/dmax_ui.lua")
  local makeDmaxPad = loadSibling(mod, "src/dmax_pad.lua")
  local makeBattleWeather = loadSibling(mod, "src/battle_weather.lua")
  if not (N and Bosses and Sprites and makeScene and makePad and makeRaid) then
    mod.log:error("Galar Rising is missing files; it stays off -- reinstall the mod")
    return
  end
  if HD then mod.hd = HD end
  -- the battle's words in the language too (src/raid_sim.lua's events)
  if type(Sim) == "table" then Sim.T = T end
  -- Japanese in the raid's own fonts: LOVE's default face draws Latin only, so every font the raid
  -- makes takes the engine's Plain Pixel (kana and CJK) as a fallback, at its size (as PlayNav's
  -- src/cjk.lua); without the file, Latin as before
  local CJK_PATH = "assets/fonts/plainpixel/PlainPixel-Regular.ttf"
  local cjkFonts, cjkMissing = {}, false
  local function cjk(font, px)
    if cjkMissing or not (font and font.setFallbacks) then return font end
    local key = math.floor((px or 12) + 0.5)
    local fb = cjkFonts[key]
    if not fb then
      local ok, f = pcall(love.graphics.newFont, CJK_PATH, key)
      if not ok or not f then
        cjkMissing = true
        mod.log:warn("no %s (%s): Japanese words draw as boxes; reinstall the game to restore it", CJK_PATH, tostring(f))
        return font
      end
      fb = f
      cjkFonts[key] = fb
    end
    pcall(font.setFallbacks, font, fb)
    return font
  end

  local Scene = nil
  do
    local ok, sc = pcall(makeScene, mod, { Render3d = makeRender3d, T = T })
    if ok and type(sc) == "table" then Scene = sc else mod.log:warn("the den failed to build: %s", tostring(sc)) end
  end
  local Pad = makePad(mod, { T = T, cjk = cjk })
  local Rewards = nil
  if makeRewards then
    local ok, rw = pcall(makeRewards, mod, { N = N, Bosses = Bosses, Sprites = Sprites, T = T })
    if ok and type(rw) == "table" then Rewards = rw else mod.log:warn("the raid's rewards failed to build: %s", tostring(rw)) end
  end
  local Battle = nil
  local difficultyForced = nil -- (drivers: _test.difficulty("solo" | "swsh"))
  local moveInfoForced = nil -- (drivers: _test.moveInfo("basic" | "full" | "off"))
  if makeBattle then
    -- (the National Dex's exports: what its newer moves do besides their damage)
    local function dex()
      local ok, d = pcall(mod.find, mod, "national_dex_gen3")
      return ok and type(d) == "table" and d.exports or nil
    end
    local ok, bt = pcall(makeBattle, mod, { N = N, Bosses = Bosses, Sprites = Sprites, Gmax = Gmax, MaxPower = MaxPower,
      TeamMoves = TeamMoves, dex = dex, T = T, difficulty = function() return difficultyForced or mod.options:get("difficulty") end })
    if ok and type(bt) == "table" then Battle = bt else mod.log:warn("the raid's battle failed to build: %s", tostring(bt)) end
    -- (the rewards read the TMs' moves through it)
    if Battle and Rewards then Rewards.battle = Battle end
  end
  -- the red dens' Dynamax Pokemon: the route's, as boss records under "DYNA:" keys
  local Dyna = nil
  if makeDyna then
    local ok, dy = pcall(makeDyna, mod, { N = N, Bosses = Bosses, Sprites = Sprites,
      typeName = Battle and Battle.typeName or nil, T = T })
    if ok and type(dy) == "table" then
      Dyna = dy
      Dyna.install()
    else
      mod.log:warn("the Dynamax dens failed to build: %s", tostring(dy))
    end
  end
  -- the raid API (src/raid_api.lua): other mods' bosses, dens and raids; its boss records under
  -- "EXT:" keys
  local Api = nil
  if makeApi then
    local ok, api = pcall(makeApi, mod, { N = N, Bosses = Bosses, Sprites = Sprites, Dyna = Dyna, Battle = Battle,
      Rewards = Rewards, Gmax = Gmax })
    if ok and type(api) == "table" then
      Api = api
      Api.install()
    else
      mod.log:warn("the raid API failed to build: %s", tostring(api))
    end
  end
  local BattlerHud =makeBattlerHud and makeBattlerHud(mod, { drawPixel = HD and HD.drawPixel or nil, T = T, cjk = cjk }) or nil
  local PadHide = makePadHide and makePadHide(mod) or nil
  -- the den screen's PC: the game's boxes, to choose a Pokemon from
  local Pick = nil
  if makePick then
    local ok, pk = pcall(makePick, mod, { T = T })
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
    -- (mod.game until the HUD has drawn: the dens roll from input.step, which can come first)
    local game = lastGame or mod.game
    local loader = game and game.mods
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
  local giftRows = nil   -- (the awakening's gift: the Dynamax Band's script rows; set with Dynamax below)
  local Layer = { isMenu = true }
  function Layer.handleInput(input) if Raid then Raid.input(input) end end
  function Layer.update(dt)
    if Raid then
      -- (a fault in the raid closes it, back to the field, rather than leaving the player stuck)
      local ok, err = pcall(Raid.update, dt)
      if not ok then
        mod.log:warn("the raid failed and was closed (please report this with the log): %s", tostring(err))
        pcall(Raid.close)
      end
    end
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

  -- Recomp Achievements (optional): the raids' achievements are registered with it and the moments
  -- the raid notes are reported. Without it, nothing.
  local Achievements = nil
  if makeAchievements and AchievementData then
    local ok, a = pcall(makeAchievements, mod, { data = AchievementData, T = T,
      stars = function(key) local b = Bosses[key]; return b and b.stars or nil end })
    if ok and type(a) == "table" then
      if a.install() then Achievements = a end
    else
      mod.log:warn("achievements: the module failed to build (%s)", tostring(a))
    end
  end

  Raid = makeRaid(mod, { T = T, cjk = cjk, N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene, Pad = Pad, HD = HD, Phases = Phases,
    BattlerHud = BattlerHud, Battle = Battle, Sim = type(Sim) == "table" and Sim or nil, Gmax = Gmax, TeamMoves = TeamMoves,
    Rewards = Rewards, Fx = makeFx and makeFx({ Scene = Scene, Sheets = PixelFx,
      read = function(path) return mod:read(path) end }) or nil, MoveFx = MoveFx, Sounds = Sounds,
    makeDen = makeDen, Pick = Pick, Dyna = Dyna, MusicData = MusicData,
    Music = (function()
      if not makeMusic then return nil end
      local okA, AudioM = pcall(require, "src.core.game3.audio")
      local ok, m = pcall(makeMusic, mod, { data = MusicData, Audio = okA and AudioM or nil })
      return ok and m or nil
    end)(),
    note = function(what, ...) if Achievements then Achievements.note(what, ...) end end,
    -- a won raid: its den is done for the day
    onEnd = function(den, outcome, raid)
      if outcome == "fled" and Achievements then Achievements.note("ran") end
      -- (won, or left by Run: spent for the day - not by a Dynamax Crystal's legendary raid, which
      -- leaves the den as it was)
      if raid and raid.legend then return end
      if (outcome == "win" or outcome == "fled") and den and Dens and Dens.finish then pcall(Dens.finish, den) end
    end,
    -- (a raid's start and its end: told to the mod whose raid it was, and as events for any mod)
    onRaidStart = function(info, ext) if Api then Api.started(info, ext) end end,
    onRaidEnd = function(info, ext) if Api then Api.ended(info, ext) end end,
    padOnSecond = padOnSecond,
    moveInfo = function() return moveInfoForced or mod.options:get("move_info") end,
    onOpen = function()
      -- (CUSTOM's file read again, so an edit shows at the next den)
      pcall(T.refresh)
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
    -- (the day follows National Dex Gen 3's CLOCK SOURCE: Device -> the device's date. Its own
    -- export first; an older National Dex has none, and its option is read from the loader)
    local function clockSource()
      local nd = mod:find("national_dex_gen3")
      local fn = nd and nd.exports and nd.exports.clockSource
      if type(fn) == "function" then
        local okC, v = pcall(fn)
        if okC and v ~= nil then return v end
      end
      return modOption("national_dex_gen3", "clock_source")
    end
    local ok, dn = pcall(makeDens, mod, { N = N, Bosses = Bosses, Dyna = Dyna, open = function(den) return Raid.openDen(den) end, T = T,
      clockSource = clockSource, gift = function() return giftRows and giftRows() or nil end })
    if ok and type(dn) == "table" then
      Dens = dn
      Dens.registerSprites()
      local okI, err = pcall(Dens.install)
      if not okI then mod.log:warn("dens not installed: %s", tostring(err)) end
    else
      mod.log:warn("dens failed to build: %s", tostring(dn))
    end
  end

  -- ------- Dynamax in the game's own battles (src/dmax.lua, src/dmax_ui.lua): the Max Moves and the
  -- Dynamax Band registered now, as the National Dex registers its own; the battle's wraps at
  -- game.ready, after the National Dex's
  local Dmax, DmaxUi, DmaxPad = nil, nil, nil
  local BattleWeather = nil  -- (src/battle_weather.lua: the weather and terrain over the game's own battles)
  local dmaxForced = nil  -- (drivers: _test.dmaxMode("league" | "trainers" | "all" | "off"))
  local BAND = { id = "DYNAMAX_BAND", name = "DYNAMAX BAND", index = 959 }
  if DmaxData and makeDmaxRules and makeDmax and makeDmaxUi and Battle then
    local function dexExports()
      local ok, d = pcall(mod.find, mod, "national_dex_gen3")
      return ok and type(d) == "table" and d.exports or nil
    end
    local okD, dm = pcall(function()
      local rules = makeDmaxRules({ data = DmaxData })
      return makeDmax(mod, { data = DmaxData, rules = rules, battle = Battle, gmax = Gmax, T = T, dex = dexExports,
        mode = function() return dmaxForced or mod.options:get("dynamax") or "league" end, bandIndex = BAND.index,
        bosses = Bosses, spot = function() return Dens ~= nil and Dens.liveHere ~= nil and Dens.liveHere() end })
    end)
    if okD and type(dm) == "table" then
      Dmax = dm
      local n = Dmax.register()
      if mod.log then mod.log:info("dynamax: %d moves registered", n) end
      local okB, errB = pcall(function()
        mod.content.items:register(BAND.id, { id = BAND.id, name = BAND.name, index = BAND.index, price = 0,
          pocket = "KEY_ITEMS", importance = 1,
          description = "A band that lets\nPokemon Dynamax\nin battle." })
      end)
      if not okB then mod.log:warn("dynamax: the Dynamax Band not registered (%s)", tostring(errB)) end
      local okU, ui = pcall(makeDmaxUi, mod, { dmax = Dmax, bosses = Bosses, sprites = Sprites, T = T,
        bigCry = function(species) return Raid and Raid.bigCry and Raid.bigCry(species) end,
        fx = function() return Raid and Raid.Fx end, sounds = DmaxSounds })
      if okU and type(ui) == "table" then
        DmaxUi = ui
        Dmax.onDynamax = ui.onDynamax
        -- (our Max Move pad in Kanto Gear's place while a Dynamax move is chosen: src/dmax_pad.lua)
        if makeDmaxPad then
          local okP, pad = pcall(makeDmaxPad, mod, { dmax = Dmax, ui = ui, Pad = Pad, battle = Battle, T = T,
            gearOption = function(key) return gearOption(key) end, makeScreen2 = makeScreen2 })
          if okP and type(pad) == "table" then
            DmaxPad = pad
            ui.padStep = function() return pad.step() end
          else
            mod.log:warn("dynamax: its move pad failed to build: %s", tostring(pad))
          end
        end
        if makeBattleWeather then
          local okW, bw = pcall(makeBattleWeather, mod, { ui = ui, dex = dexExports })
          if okW and type(bw) == "table" then BattleWeather = bw
          else mod.log:warn("the battles' weather failed to build: %s", tostring(bw)) end
        end
      else
        mod.log:warn("dynamax: its battle screen failed to build: %s", tostring(ui))
      end
      -- the band: given at the dens' awakening (its words, then the gift), and to a save already
      -- awake without it the next time it loads; once (save "dmaxBand")
      local function bag()
        local okR, Runtime = pcall(require, "src.core.game3.runtime")
        local s = okR and Runtime.getSession and Runtime.getSession()
        local okB, Bag = pcall(require, "src.core.game3.bag")
        return s and s.bag, okB and Bag or nil
      end
      local function hasBand()
        local b, Bag = bag()
        if not (b and Bag) then return false end
        local okH, has = pcall(Bag.has, b, BAND.index, 1)
        return okH and has == true
      end
      -- (the band put in the Bag here: a Gen 3 script has no give_item; its words follow the shake's)
      giftRows = function()
        if hasBand() then return nil end
        local b, Bag = bag()
        if not (b and Bag) then return nil end
        local okA, added = pcall(Bag.add, b, BAND.index, 1)
        if not (okA and added) then return nil end
        mod.save:set("dmaxBand", true)
        return {
          { "text", T.game("The light gathers around your wrist...") },
          { "text", T.game("You obtained a DYNAMAX BAND!") },
        }
      end
      local function grantOnLoad()
        if mod.save:get("dmaxBand") or not (Dens and Dens.awake and Dens.awake()) or hasBand() then return end
        local b, Bag = bag()
        if not (b and Bag) then return end
        local okA, added = pcall(Bag.add, b, BAND.index, 1)
        if okA and added then
          mod.save:set("dmaxBand", true)
          mod.log:info("dynamax: the Dynamax Band given (the dens were already awake)")
        end
      end
      mod.events:on("save.loaded", function() pcall(grantOnLoad) end)
      mod.events:on("game.ready", function()
        pcall(grantOnLoad)
        local okI, errI = pcall(Dmax.install)
        if not okI then mod.log:warn("dynamax: not installed (%s)", tostring(errI)) end
        if DmaxUi then
          local okUi, errUi = pcall(DmaxUi.install)
          if not okUi then mod.log:warn("dynamax: its battle screen not installed (%s)", tostring(errUi)) end
          pcall(DmaxUi.installBagIcon, BAND.index)
        end
      end)
    else
      mod.log:warn("dynamax failed to build: %s", tostring(dm))
    end
  end

  -- ------- OmniUI (1Jamie's omni_ui, optional; loaded by game.ready): the Dynamax button, the Max
  -- Moves on its move cards and a giant's mark on its battle deck (src/dmax_ui.lua), the den's PC
  -- on its box screen (src/pc_pick.lua), through its public API
  mod.events:on("game.ready", function()
    local okO, errO = pcall(function()
      local found = mod.find and mod:find("omni_ui")
      local api = type(found) == "table" and found.exports or nil
      if type(api) ~= "table" or type(api.onPostRender) ~= "function" then return end
      local hooked = false
      local function overlayOn() return modOption("omni_ui", "overlay") == true end
      if DmaxUi and DmaxUi.omniInstall(api, overlayOn) then hooked = true end
      if Pick and Pick.omniInstall(api, overlayOn) then hooked = true end
      if hooked then mod.log:info("OmniUI: the Dynamax button, Max Moves, marks and the den's PC on its screens") end
    end)
    if not okO then mod.log:warn("OmniUI hookup failed: %s", tostring(errO)) end
  end)

  -- ------- PERF.OVERLAY: the engine's frame profiler (its F3 overlay) shown, the raid's parts timed
  -- as its sections (a push / pop that returns at once while it is off), the raid's doings added to
  -- its slow-frame label, and the slowest frames listed at the top right
  local okFP, FP = pcall(require, "src.core.FrameProfiler")
  if not (okFP and type(FP) == "table" and FP.push and FP.pop) then FP = nil end
  local perfOn = false
  local slowText, slowAt = "", -1
  -- (the Lua heap at the raid's draw, this frame and the last: a fall between them is a collection
  -- finished in the frame, "gc" on its label)
  local heapNow, heapBefore = 0, 0
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
      if raid and heapNow < heapBefore - 512 then raid = raid .. " gc" end
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

  local cloudWarned = false
  -- the raid over the whole window, after the engine's own HUD
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    lastGame = game or lastGame
    local res = next(game, viewport)
    -- (PERF.OVERLAY: the engine's overlay up while a den is open - the den screen through the
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
    -- (the red energy shed off a giant in the game's own battle, at the window's resolution)
    if DmaxUi and not up then
      local G = love.graphics
      G.push("all")
      G.origin()
      G.setScissor()
      G.setShader()
      -- (the battle's weather and terrain, as long as they last, under all of it)
      if BattleWeather then
        local okW, errW = pcall(BattleWeather.draw, viewport)
        if not okW and not cloudWarned then
          cloudWarned = true
          mod.log:warn("the battle's weather failed to draw: %s", tostring(errW))
        end
      end
      local okC, errC = pcall(DmaxUi.drawEnergy, viewport)
      -- (and the Dynamax scene over the whole battle while it plays; the Max Move pad in Kanto Gear's
      -- place on this screen) - with OmniUI's overlay, after its own draw instead (below)
      if not DmaxUi.omniOn() then
        local okS, errS = pcall(DmaxUi.drawScene, viewport)
        if not okS then okC, errC = false, errS end
        -- (the DYNAMAX button where the battle's bar would be, when it draws none: at this resolution)
        local okB, errB = pcall(DmaxUi.drawButtonHud)
        if not okB then okC, errC = false, errB end
      end
      if DmaxPad then
        local okD, errD = pcall(DmaxPad.drawMain, viewport)
        if not okD then okC, errC = false, errD end
      end
      G.pop()
      if not okC and not cloudWarned then
        cloudWarned = true
        mod.log:warn("dynamax: its energy or its scene failed to draw: %s", tostring(errC))
      end
    end
    if FP and FP.enabled then
      heapBefore, heapNow = heapNow, collectgarbage("count")
      local G = love.graphics
      local w = type(viewport) == "table" and viewport.width or G.getWidth()
      local h = type(viewport) == "table" and viewport.height or G.getHeight()
      pcall(drawSlowFrames, G, w, h)
    end
    return res
  end)

  -- OmniUI's overlay (1Jamie's omni_ui) draws its battle deck after every render.hud below its own
  -- (priority 100); this one is outside it: the Max Moves put in the Pokemon's place for its draw
  -- (its move cards read them as it draws), then the Dynamax scene and the DYNAMAX button over it
  -- (src/dmax_ui.lua's OmniUI section)
  local omniWarned = false
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    if not (DmaxUi and DmaxUi.omniOn()) then return next(game, viewport) end
    DmaxUi.noteViewport(viewport)
    local okS, swapped = pcall(DmaxUi.omniSwapIn)
    local ok, res = pcall(next, game, viewport)
    if okS and swapped then pcall(DmaxUi.omniSwapOut) end
    local err = not ok and res or nil
    if not Raid.active() then
      local G = love.graphics
      G.push("all")
      G.origin()
      G.setScissor()
      G.setShader()
      local okD, errD = pcall(DmaxUi.drawScene, viewport)
      if okD then okD, errD = pcall(DmaxUi.drawButtonHud) end
      G.pop()
      if not okD then err = err or errD end
    end
    if err and not omniWarned then
      omniWarned = true
      mod.log:warn("dynamax: drawing with OmniUI failed: %s", tostring(err))
    end
    if ok then return res end
  end, 110)

  -- taps and clicks on the battle pad (the main window's)
  -- (the game kept in Kanto Gear's game rect while our Max Move pad holds the Gear's: src/dmax_pad.lua)
  mod.hooks:wrap("render.viewport", function(next, context)
    local available = next(context)
    if DmaxPad then
      local ok, rect = pcall(DmaxPad.viewport, available, context)
      if ok and rect then return rect end
    end
    return available
  end)

  -- (the battle's own menu kept away while our pad has it, as the Gear's GEAR view keeps it away:
  -- the engine's battle.bottom_ui_visible, which the Gear and WoobleView both read)
  mod.hooks:wrap("battle.bottom_ui_visible", function(next, st, ...)
    if DmaxPad and DmaxPad.shown() then return false end
    return next(st, ...)
  end)

  -- (and our pad drawn in the Gear's rect, over the window, once the game's rect is in place)
  mod.hooks:wrap("render.window", function(next, game, context)
    local r = next(game, context)
    if DmaxPad then
      local ok, err = pcall(DmaxPad.drawWindow)
      if not ok and not cloudWarned then
        cloudWarned = true
        mod.log:warn("dynamax: its move pad failed to draw: %s", tostring(err))
      end
    end
    return r
  end)

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if Raid.active() and not Raid.summaryUp() and type(ev) == "table" and Raid.pointer(ev) then return true end
    -- (the DYNAMAX button in the game's own battle)
    if DmaxPad and not Raid.active() then
      local okD, tookD = pcall(DmaxPad.pointer, ev)
      if okD and tookD then return true end
    end
    if DmaxUi and not Raid.active() then
      local okP, took = pcall(DmaxUi.pointer, ev)
      if okP and took then return true end
    end
    return next(game, ev)
  end)

  -- the Dynamax scene at the game's own speed: the game's speed-up runs several of its steps a frame,
  -- and the scene steps with them (its parts and its sounds) - 1x while it plays, the black's lift too
  mod.hooks:wrap("core.logic_speed", function(next, game, ...)
    if DmaxUi and DmaxUi.sceneOn and DmaxUi.sceneOn() then return 1 end
    return next(game, ...)
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
        -- (and while a Dynamax move is chosen with the Gear's battle on its screen: our pad has it)
        shown = function() return Raid.active() or (DmaxPad ~= nil and DmaxPad.shown()) end,
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
  -- the words' language ("en" ...; drivers: setLanguage(code) as the option does)
  mod.exports.language = function() return T.language() end
  mod.exports.setLanguage = function(code) local v = T.setLanguage(code); defineOptions(); return v end
  mod.exports.T = T
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
  mod.exports.achievements = Achievements
  -- the raid API for other mods (docs/RAID_API.md): connect(mod) -> a handle for its bosses, dens
  -- and raids
  if Api then
    Api.dens, Api.raid = Dens, Raid
    mod.exports.apiVersion = Api.VERSION
    mod.exports.supports = function(name) return Api.supports(name) end
    mod.exports.connect = function(m, opts) return Api.connect(m, opts) end
  end
  mod.exports._test = { scene = Scene, pad = Pad, rules = N, dens = Dens, battlerHud = BattlerHud, battle = Battle, sim = Sim,
    rewards = Rewards, fx = Raid and Raid.Fx or nil, screen2 = Screen2, sounds = Sounds, pick = Pick, dyna = Dyna, api = Api,
    padSecond = function(on) padForced = on end, difficulty = function(v) difficultyForced = v end,
    moveInfo = function(v) moveInfoForced = v end,
    gearOptions = function(t) gearForced = t end, padWanted = function() return padWanted() end,
    dmax = Dmax, dmaxUi = DmaxUi, dmaxPad = function() return DmaxPad end, dmaxMode = function(v) dmaxForced = v end, band = BAND,
    battleWeather = function() return BattleWeather end }
  mod.log:info("Galar Rising ready (%d bosses)", #(Bosses.ORDER or {}))
end
