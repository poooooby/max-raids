-- Max Raids: Sword / Shield's Max Raid Battles on the Gen 3 games, with National Dex Gen 3's
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
    -- where the battle pad goes: over the den on the main screen, or the device's second screen
    -- (the main screen then keeps the whole den)
    { key = "battle_pad", label = "BATTLE PAD", type = "choice", default = "main",
      choices = { { "MAIN SCREEN", "main" }, { "SECOND SCREEN", "second" } } },
    -- dens on the routes (off: none spawn; those already chosen stay saved)
    { key = "dens", label = "RAID DENS", type = "toggle", default = true },
  })

  local N = loadSibling(mod, "data/raid_rules.lua")
  local Bosses = loadSibling(mod, "data/raid_bosses.lua")
  local Sprites = loadSibling(mod, "data/raid_sprites.lua")
  local HD = loadSibling(mod, "src/hd.lua")
  local makeRender3d = loadSibling(mod, "src/render3d.lua")
  local makeScene = loadSibling(mod, "src/raid_scene.lua")
  local makePad = loadSibling(mod, "src/pad.lua")
  local makeRaid = loadSibling(mod, "src/raid.lua")
  local makePadHide = loadSibling(mod, "src/pad_hide.lua")
  local makeDens = loadSibling(mod, "src/dens.lua")
  if not (N and Bosses and Sprites and makeScene and makePad and makeRaid) then
    mod.log:error("Max Raids is missing files; it stays off -- reinstall the mod")
    return
  end
  if HD then mod.hd = HD end

  local Scene = nil
  do
    local ok, sc = pcall(makeScene, mod, { Render3d = makeRender3d })
    if ok and type(sc) == "table" then Scene = sc else mod.log:warn("the den failed to build: %s", tostring(sc)) end
  end
  local Pad = makePad(mod, {})
  local PadHide = makePadHide and makePadHide(mod) or nil

  local function padOnSecond()
    return mod.options:get("battle_pad") == "second"
  end

  -- ------- the layer over the field (the engine's Gen 3 UI stack): it pauses the field, takes the
  -- pad and keyboard, and is updated outside the draw (where the den renders); it paints black in
  -- the 240x160 pass, the raid itself is drawn over the whole window from render.hud

  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  if not (okStack and type(Stack) == "table") then Stack = nil end
  local LAYER_ID = "max_raids"
  local Raid
  local Layer = { isMenu = true }
  function Layer.handleInput(input) if Raid then Raid.input(input) end end
  function Layer.update(dt) if Raid then Raid.update(dt) end end
  function Layer.draw()
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 240, 160)
      G.setColor(1, 1, 1, 1)
    end
  end

  Raid = makeRaid(mod, { N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene, Pad = Pad, HD = HD,
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

  -- ------- dens on the routes: A on one opens its den screen (src/dens.lua)
  local Dens = nil
  if makeDens then
    local ok, dn = pcall(makeDens, mod, { N = N, Bosses = Bosses, open = function(den) return Raid.openDen(den) end })
    if ok and type(dn) == "table" then
      Dens = dn
      Dens.registerSprites()
      local okI, err = pcall(Dens.install)
      if not okI then mod.log:warn("dens not installed: %s", tostring(err)) end
    else
      mod.log:warn("dens failed to build: %s", tostring(dn))
    end
  end

  -- the raid over the whole window, after the engine's own HUD
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local res = next(game, viewport)
    local up = Raid.active()
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
    return res
  end)

  -- taps and clicks on the battle pad (the main window's)
  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if Raid.active() and type(ev) == "table" and Raid.pointer(ev) then return true end
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
  mod.exports.dens = Dens
  mod.exports._test = { scene = Scene, pad = Pad, rules = N, dens = Dens }
  mod.log:info("Max Raids ready (%d bosses)", #(Bosses.ORDER or {}))
end
