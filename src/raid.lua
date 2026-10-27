-- A Max Raid (Sword / Shield's Max Raid Battles, on the Gen 3 games): a giant Gigantamax boss from
-- the Giga Megas pack (data/raid_bosses.lua over data/raid_sprites.lua, baked by tools/raid_pack.py)
-- against four of the party, in the 3D den (src/raid_scene.lua) on a layer of its own over the
-- field (src/layer.lua), drawn at the window's resolution.
--
-- This file is the raid's controller: the boss's pictures and cry (one boss in memory at a time,
-- released when the raid closes), the four who fight (copies of the party's Pokemon; their back
-- pictures fetched in the update step - an animated sprite mod redraws them into a canvas, which
-- must never happen inside a draw), the intro, the HUD and the battle pad.
--   Rd = raid(mod, { N, Bosses, Sprites, Scene, Pad, HD, padOnSecond, onOpen, onClose })
--   Rd.open(key) ; Rd.close() ; Rd.active() ; Rd.update(dt) ; Rd.input(input) ; Rd.pointer(ev)
--   Rd.draw(G, w, h) ; Rd.state()

return function(mod, deps)
  local N, Bosses, Sprites, Scene, Pad = deps.N, deps.Bosses, deps.Sprites, deps.Scene, deps.Pad
  local R = N.RAID
  local floor, max, min = math.floor, math.max, math.min

  local Rd = { N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene }
  -- an animation frame lasts AnimationSpeed of these (the pack's metrics, Essentials' units)
  Rd.ANIM_UNIT_S = 1 / 20

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local Pokemon = engine("src.core.game3.pokemon")
  local Runtime = engine("src.core.game3.runtime")
  local Audio = engine("src.core.game3.audio")

  local function drawPixel(...)
    local HD = deps.HD
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  Rd.drawPixel = drawPixel

  -- ------- the bosses

  function Rd.boss(key)
    local b, sp = Bosses[key], Sprites[key]
    if type(b) ~= "table" or type(sp) ~= "table" then return nil end
    return b, sp
  end

  -- the boss's size against a member's: by its height (data/raid_rules.lua SIZE)
  function Rd.sizeOf(key)
    local sp = Sprites[key]
    local S = R.SIZE
    local u = ((sp and sp.height or S.H0) - S.H0) / (S.H1 - S.H0)
    return S.MIN + (S.MAX - S.MIN) * max(0, min(1, u))
  end

  -- a picture of the mod's: the Image, and (keep = true) its ImageData too, for measuring
  local function imageOf(path, keep)
    if not (love and love.graphics and mod.read) then return nil end
    local data
    local ok, img = pcall(function()
      local bytes = mod:read(path)
      if not bytes then return nil end
      data = love.image.newImageData(love.filesystem.newFileData(bytes, path:match("[^/]+$")))
      local i = love.graphics.newImage(data)
      i:setFilter("nearest", "nearest")
      return i
    end)
    if not ok then mod.log:warn("raid picture %s failed to load: %s", path, tostring(img)) end
    if not keep and data then pcall(data.release, data) end
    return ok and img or nil, keep and data or nil
  end
  Rd.imageOf = imageOf

  -- the opaque part of a w x h region of image data at (x, y): x0, y0, x1, y1 in the region
  local function boxOf(data, x, y, w, h)
    local x0, y0, x1, y1 = w, h, -1, -1
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        local _, _, _, a = data:getPixel(x + xx, y + yy)
        if a > 0.1 then
          if xx < x0 then x0 = xx end
          if xx > x1 then x1 = xx end
          if yy < y0 then y0 = yy end
          if yy > y1 then y1 = yy end
        end
      end
    end
    if x1 < x0 then return { 0, 0, w, h } end
    return { x0, y0, x1 + 1, y1 + 1 }
  end
  Rd.boxOf = boxOf

  -- the loaded boss: { key, sheet, quads, cell, box, sp, b, cry }
  local loaded = nil
  function Rd.release()
    if not loaded then return end
    if loaded.sheet and loaded.sheet.release then pcall(loaded.sheet.release, loaded.sheet) end
    if loaded.cry and loaded.cry.release then pcall(loaded.cry.release, loaded.cry) end
    loaded = nil
  end
  function Rd.load(key, shiny)
    if loaded and loaded.key == key and loaded.shiny == (shiny == true) then return loaded end
    Rd.release()
    local b, sp = Rd.boss(key)
    if not b then return nil end
    local sheet, data = imageOf("assets/bosses/" .. key .. ((shiny and sp.shiny) and "_shiny" or "") .. ".png", true)
    if not sheet then return nil end
    -- its feet and width from the first frame (the pad stands it there)
    local box = data and boxOf(data, 0, 0, sp.cell, sp.cell) or { 0, 0, sp.cell, sp.cell }
    if data then pcall(data.release, data) end
    local quads = {}
    local sw, sh = sheet:getDimensions()
    for i = 1, sp.frames do
      local c, r0 = (i - 1) % sp.cols, floor((i - 1) / sp.cols)
      quads[i] = love.graphics.newQuad(c * sp.cell, r0 * sp.cell, sp.cell, sp.cell, sw, sh)
    end
    loaded = { key = key, shiny = shiny == true, sheet = sheet, quads = quads, cell = sp.cell, sp = sp, b = b, box = box }
    return loaded
  end
  function Rd.loadedKey() return loaded and loaded.key or nil end

  -- the frame shown at time t (seconds): image, quad, cell
  function Rd.frameAt(key, t)
    local L = Rd.load(key)
    if not L then return nil end
    local unit = (L.sp.speed and L.sp.speed[1] or 2) * Rd.ANIM_UNIT_S
    local i = floor((t or 0) / unit) % #L.quads + 1
    return L.sheet, L.quads[i], L.cell
  end

  -- the effects volume the game is set to (0..1)
  local function sfxGain()
    if Audio and type(Audio._sfxVolume) == "number" then return Audio._sfxVolume end
    return 1
  end

  -- the boss's cry: the pack's .ogg, at the game's effects volume
  function Rd.cry(key)
    local L = Rd.load(key)
    if not (L and L.sp.cry and love and love.audio and love.sound) then return false end
    if not L.cry then
      local ok, sd = pcall(function()
        local bytes = mod:read("assets/bosses/cries/" .. key .. ".ogg")
        return bytes and love.sound.newSoundData(love.filesystem.newFileData(bytes, key .. ".ogg"))
      end)
      if not (ok and sd) then return false end
      L.cry = sd
    end
    local g = sfxGain()
    if g <= 0 then return true end
    local ok, src = pcall(love.audio.newSource, L.cry, "static")
    if not ok then return false end
    pcall(src.setVolume, src, min(1, g))
    pcall(src.play, src)
    return true
  end

  -- ------- the four who fight

  local function party()
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    return s and s.party or {}
  end
  local function isEgg(mon)
    if Pokemon and Pokemon.isEgg then
      local ok, egg = pcall(Pokemon.isEgg, mon)
      if ok then return egg == true end
    end
    return type(mon) == "table" and mon.isEgg == true
  end

  -- the first four of the party that are not eggs (the den screen will let the player pick)
  function Rd.lineup()
    local out = {}
    for _, mon in ipairs(party()) do
      if #out >= 4 then break end
      if not isEgg(mon) then out[#out + 1] = { mon = mon } end
    end
    return out
  end

  -- a member's back picture now (an animated sprite mod answers each call with the moment's
  -- frame, redrawing it into a canvas: so only from the update step)
  local function backPicOf(mon)
    if not Pokemon then return nil end
    local fn = Pokemon.monBackPic or Pokemon.backPic
    local ok, pic = pcall(fn, mon)
    if ok and type(pic) == "table" and pic.image then return pic end
    ok, pic = pcall(Pokemon.monFrontPic or Pokemon.frontPic, mon)
    if ok and type(pic) == "table" and pic.image then return pic end
    return nil
  end

  -- the opaque box of a picture, read back through a canvas (update step only), in its own units
  local function opaqueBox(image, quad)
    local G = love.graphics
    local iw, ih = image:getDimensions()
    local qx, qy, qw, qh = 0, 0, iw, ih
    if quad then qx, qy, qw, qh = quad:getViewport() end
    local ok, data = pcall(function()
      local c = G.newCanvas(qw, qh, { dpiscale = 1 })
      G.push("all")
      G.setCanvas(c)
      G.origin()
      G.setShader()
      G.setBlendMode("alpha")
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      if quad then G.draw(image, quad, 0, 0) else G.draw(image, 0, 0) end
      G.pop()
      local d = c:newImageData()
      c:release()
      return d
    end)
    if not (ok and data) then return { 0, 0, qw, qh } end
    local pw, ph = data:getDimensions()
    local b = boxOf(data, 0, 0, pw, ph)
    data:release()
    local kx, ky = qw / pw, qh / ph
    return { b[1] * kx, b[2] * ky, b[3] * kx, b[4] * ky }
  end

  -- each member's picture as the den draws it, refreshed in the update step:
  -- { image, quad, box, cell } (box in the quad's units; cell the pic's height, 64)
  local function memberPics(r)
    for _, m in ipairs(r.members) do
      local pic = backPicOf(m.mon)
      if pic then
        local img = pic.image
        local w, h = pic.w or 64, pic.h or 64
        m.draw = m.draw or {}
        local d = m.draw
        d.image = img
        if not d.quad or d.qw ~= w or d.qh ~= h or d.src ~= img then
          d.quad = love.graphics.newQuad(0, 0, w, h, img:getDimensions())
          d.qw, d.qh, d.src = w, h, img
        end
        d.cell = h
        if not d.box then d.box = opaqueBox(img, d.quad) end
      end
    end
  end

  -- ------- open and close

  local r = nil
  function Rd.active() return r ~= nil end
  function Rd.current() return r end

  -- the boss's music: the first of these the game has
  Rd.SONGS = { "MUS_VS_RAYQUAZA", "MUS_VS_MEWTWO", "MUS_VS_REGI", "MUS_VS_LEGEND", "MUS_RG_VS_LEGEND", "MUS_VS_CHAMPION" }
  local function playSong(names)
    if not (Audio and Audio.songs) then return nil end
    local ok, songs = pcall(Audio.songs)
    if not (ok and type(songs) == "table") then return nil end
    for _, name in ipairs(names) do
      local id = songs[name]
      if id then
        if Audio.fadeOutAndPlay then pcall(Audio.fadeOutAndPlay, id) elseif Audio.playSong then pcall(Audio.playSong, id) end
        return name
      end
    end
    return nil
  end

  -- the raid itself begins: the intro from the close-up on the party
  local function begin(members)
    r.phase, r.t, r.members, r.cues, r.hud = "intro", 0, members, {}, 0
    r.say = nil
    if Scene then
      Scene.setTime(0)
      Scene.shot("close", 0)
    end
    r.song = playSong(Rd.SONGS)
  end

  -- straight into a raid (drivers, tests): no den screen
  function Rd.open(key, opts)
    if r then return false, "busy" end
    if not Rd.boss(key) then return false, "unknown boss" end
    if not Rd.load(key) then return false, "no pictures" end
    r = { key = key, den = opts and opts.den }
    begin((opts and opts.members) or Rd.lineup())
    if deps.onOpen then deps.onOpen(r) end
    return true
  end

  -- ------- the den screen: what a den holds today, and the four who go in

  -- the party as the den screen lists it (eggs left out): { mon, name, level }
  local function roster()
    local out = {}
    for _, mon in ipairs(party()) do
      if not isEgg(mon) then
        local name = "?"
        if Pokemon and Pokemon.displayName then
          local ok, n = pcall(Pokemon.displayName, mon)
          if ok and type(n) == "string" then name = n end
        end
        out[#out + 1] = { mon = mon, name = name, level = tonumber(mon.level) or 1 }
      end
    end
    return out
  end

  -- the den screen takes no presses for this long after it opens
  Rd.DEN_ARM_S = 0.25

  function Rd.openDen(den)
    if r then return false, "busy" end
    if type(den) ~= "table" then return false, "no den" end
    local list = roster()
    r = { phase = "den", den = den, key = den.active and not den.done and den.boss or nil, t = 0,
      party = list, picked = {}, cursor = 1, cues = {}, hud = 0 }
    for i = 1, min(4, #list) do r.picked[i] = true end
    if r.key and not Rd.load(r.key) then r.key = nil end
    if deps.onOpen then deps.onOpen(r) end
    return true
  end

  local function pickedCount()
    local n = 0
    for _, on in pairs(r.picked) do if on then n = n + 1 end end
    return n
  end

  -- a party row toggled in or out (at most four)
  function Rd.denToggle(i)
    if not (r and r.phase == "den" and r.party[i]) then return false end
    if r.picked[i] then r.picked[i] = nil
    elseif pickedCount() < 4 then r.picked[i] = true
    else return false end
    return true
  end

  -- from the den screen into the raid with the four picked (party order)
  function Rd.denStart()
    if not (r and r.phase == "den" and r.key) then return false end
    local members = {}
    for i, row in ipairs(r.party) do
      if r.picked[i] and #members < 4 then members[#members + 1] = { mon = row.mon } end
    end
    if #members == 0 then return false end
    begin(members)
    return true
  end

  function Rd.close()
    if not r then return false end
    r = nil
    Rd.release()
    if Audio then
      if Audio.restoreMapSong then pcall(Audio.restoreMapSong)
      elseif Audio.changeMusicToDefault then pcall(Audio.changeMusicToDefault) end
    end
    if deps.onClose then deps.onClose() end
    return true
  end

  function Rd.flee() return Rd.close() end

  -- ------- the intro (Sword / Shield's raid opening, with the party where the trainers stand):
  -- close on the party, then the camera pulls back and down to the ground and tilts up the boss's
  -- whole height; it roars (its cry, a burst of energy, a shake), "X appeared!", the HUD comes in,
  -- and the camera swings over the first member's shoulder for its command (seconds from opening)

  Rd.INTRO = { REVEAL_AT = 1.3, REVEAL_S = 2.4, ROAR_AT = 3.6, SAY_AT = 4.0, HUD_S = 0.5,
    MEMBER_AT = 6.0, MEMBER_S = 1.2, DONE = 7.2 }
  local function once(name, at)
    if r.cues[name] or r.t < at then return false end
    r.cues[name] = true
    return true
  end
  function Rd.say(text) if r then r.say, r.sayT = text, r.t end end

  function Rd.update(dt)
    if not r then return end
    dt = min(0.1, dt or 0)
    r.t = r.t + dt
    -- the den screen: no den in 3D yet
    if r.phase == "den" then return end
    if Scene then Scene.setTime(r.t) end
    if r.phase == "intro" then
      local I = Rd.INTRO
      if once("reveal", I.REVEAL_AT) and Scene then Scene.shot("reveal", I.REVEAL_S) end
      if once("roar", I.ROAR_AT) then
        Rd.cry(r.key)
        if Scene then Scene.burst(); Scene.shake(0.22, 1.0) end
      end
      if once("say", I.SAY_AT) then
        local b = Bosses[r.key]
        Rd.say((b and b.name or "The boss") .. " appeared!")
      end
      if r.cues.say then r.hud = min(1, r.hud + dt / I.HUD_S) end
      if once("member", I.MEMBER_AT) and Scene then Scene.shot("member", I.MEMBER_S, 1) end
      if r.t >= I.DONE then
        r.phase = "command"
        r.say = nil
      end
    end
    -- the members' pictures and the den's render: here, outside any draw
    memberPics(r)
    if Scene and Scene.prepare then Scene.prepare(r.t) end
  end

  -- ------- input

  function Rd.input(input)
    if not r then return end
    if r.phase == "den" then
      -- (the press that opened the den is still down on its first frames: not a toggle)
      if r.t < Rd.DEN_ARM_S then return end
      local n = #r.party
      if input:wasPressed("up") and n > 0 then r.cursor = (r.cursor - 2) % n + 1
      elseif input:wasPressed("down") and n > 0 then r.cursor = r.cursor % n + 1
      elseif input:wasPressed("a") then Rd.denToggle(r.cursor)
      elseif input:wasPressed("start") then Rd.denStart()
      elseif input:wasPressed("b") then Rd.close() end
      return
    end
    if input:wasPressed("b") then Rd.flee() end
  end

  -- the den screen's places (window pixels), from its last draw
  local denWhere = { rows = {}, start = {}, back = {} }
  Rd.denWhere = denWhere
  local function inRect(x, y, t) return t and t.w and x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h end

  -- a pointer on the window (input.pointer): true when the den screen or the pad took it
  function Rd.pointer(ev)
    if r and r.phase == "den" then
      if ev.phase == "released" and r.t >= Rd.DEN_ARM_S then
        if inRect(ev.x, ev.y, denWhere.start) then Rd.denStart()
        elseif inRect(ev.x, ev.y, denWhere.back) then Rd.close()
        else
          for i, row in ipairs(denWhere.rows) do
            if inRect(ev.x, ev.y, row) then r.cursor = i; Rd.denToggle(i) end
          end
        end
      end
      return true
    end
    if not (r and Pad) or deps.padOnSecond() then return false end
    local hit = Pad.hit(ev.x, ev.y)
    if ev.phase == "released" and hit == "flee" then Rd.flee() end
    return hit ~= nil
  end

  -- ------- drawing (window pixels)

  local fonts = {}
  local function font(px)
    px = max(6, floor(px + 0.5))
    local f = fonts[px]
    if not f then
      local ok, made = pcall(love.graphics.newFont, px)
      f = ok and made or love.graphics.getFont()
      fonts[px] = f
    end
    return f
  end
  Rd.font = font

  -- n stars drawn as shapes (the default font has no star glyph), right-aligned at x, centred on y
  local starPts = {}
  local function drawStars(G, n, x, y, size)
    for k = 1, n do
      local cx = x - (k - 0.5) * size * 1.1
      for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rr = (i % 2 == 0) and size * 0.5 or size * 0.21
        starPts[i * 2 + 1], starPts[i * 2 + 2] = cx + rr * math.cos(a), y + rr * math.sin(a)
      end
      G.polygon("fill", starPts)
    end
  end
  Rd.drawStars = drawStars

  local bossPic, memberPicsShown = {}, {}

  -- the HUD over the den: the boss's name, stars and HP bar at the top (fading in with r.hud),
  -- the dialogue box at the foot (Gen 5's: white, rounded, a blue-grey frame), clear of the pad
  local function drawHud(G, w, h, padRect)
    local b = Bosses[r.key]
    if not b then return end
    local u = h / 360
    local a = r.hud or 0
    if a > 0 then
      local bw = min(w * 0.55, 520 * u)
      local bx, by = (w - bw) / 2, 10 * u
      G.setFont(font(15 * u))
      G.setColor(0, 0, 0, 0.6 * a)
      G.printf(b.name, bx + 1, by + 1, bw, "center")
      G.setColor(1, 1, 1, a)
      G.printf(b.name, bx, by, bw, "center")
      G.setColor(1, 0.85, 0.3, a)
      drawStars(G, b.stars, bx + bw, by + 9 * u, 9 * u)
      local hy = by + 21 * u
      G.setColor(0, 0, 0, 0.6 * a)
      G.rectangle("fill", bx - 2 * u, hy - 2 * u, bw + 4 * u, 9 * u, 3 * u, 3 * u)
      G.setColor(0.25, 0.9, 0.35, a)
      G.rectangle("fill", bx, hy, bw * (r.hpShown or 1), 5 * u, 2 * u, 2 * u)
    end
    if r.say then
      local bh = 46 * u
      local bx, by = 12 * u, h - bh - 12 * u
      local bw = w - 24 * u
      if padRect then bw = max(160 * u, padRect.x - bx - 10 * u) end
      G.setColor(0.32, 0.42, 0.55, 0.95)
      G.rectangle("fill", bx, by, bw, bh, 9 * u, 9 * u)
      G.setColor(0.98, 0.98, 0.97, 1)
      G.rectangle("fill", bx + 3 * u, by + 3 * u, bw - 6 * u, bh - 6 * u, 7 * u, 7 * u)
      local n = floor((r.t - (r.sayT or 0)) * 40)
      local str = n >= #r.say and r.say or r.say:sub(1, n)
      G.setFont(font(17 * u))
      G.setColor(0.2, 0.2, 0.22, 1)
      G.printf(str, bx + 16 * u, by + (bh - 17 * u * 1.2) / 2, bw - 32 * u, "left")
    end
  end

  -- the den screen: a dark red backdrop; the boss as a black silhouette with a red rim, its stars
  -- and types; the party to pick from (up to four, ticked), START and BACK. A quiet den says so.
  local function rset(t, x, y, ww, hh) t.x, t.y, t.w, t.h = x, y, ww, hh; return t end
  local function button(G, t, rgb, word, u, live)
    local k = live and 1 or 0.45
    G.setColor(rgb[1] * 0.45 * k, rgb[2] * 0.45 * k, rgb[3] * 0.45 * k, 1)
    G.rectangle("fill", t.x, t.y + 3 * u, t.w, t.h, 8 * u, 8 * u)
    G.setColor(rgb[1] * k, rgb[2] * k, rgb[3] * k, 1)
    G.rectangle("fill", t.x, t.y, t.w, t.h, 8 * u, 8 * u)
    G.setFont(font(t.h * 0.45))
    G.setColor(1, 1, 1, live and 1 or 0.6)
    G.printf(word, t.x, t.y + (t.h - t.h * 0.45 * 1.2) / 2, t.w, "center")
  end
  local silShader, silFailed = nil, false
  local function silhouette()
    if silShader or silFailed then return silShader end
    local ok, s = pcall(love.graphics.newShader, [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(color.rgb, color.a * step(0.5, Texel(tex, tc).a));
}
]])
    if ok then silShader = s else silFailed = true end
    return silShader
  end

  local function drawDen(G, w, h)
    local u = h / 360
    -- backdrop
    G.setColor(0.07, 0.03, 0.05, 1)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(0.35, 0.03, 0.08, 0.6)
    G.circle("fill", w * 0.3, h * 0.55, h * 0.45, 48)
    local key = r.key
    G.setFont(font(20 * u))
    G.setColor(1, 1, 1, 1)
    if not key then
      G.printf("The den is quiet.", 0, h * 0.4, w, "center")
      G.setFont(font(14 * u))
      G.setColor(0.8, 0.8, 0.85, 1)
      G.printf("Nothing stirs here today. Come back tomorrow.", 0, h * 0.4 + 30 * u, w, "center")
      rset(denWhere.back, w / 2 - 70 * u, h * 0.7, 140 * u, 34 * u)
      rset(denWhere.start, 0, 0, 0, 0)
      for i = #denWhere.rows, 1, -1 do denWhere.rows[i] = nil end
      button(G, denWhere.back, { 0.2, 0.45, 0.9 }, "BACK", u, true)
      return
    end
    -- the boss: a red rim, then its silhouette
    local img, q, cell = Rd.frameAt(key, r.t)
    if img and loaded then
      local box = loaded.box
      local bh = box[4] - box[2]
      local k = (h * 0.7) / bh
      local cx, fy = w * 0.3, h * 0.88
      local ox, oy = (box[1] + box[3]) / 2, box[4]
      -- the rim and the body in flat colours (a silhouette shader: the sprite's alpha, one colour)
      local s = silhouette()
      if s then G.setShader(s) end
      G.setColor(0.9, 0.1, 0.18, 1)
      for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 1.5, 1.5 }, { -1.5, 1.5 }, { 1.5, -1.5 }, { -1.5, -1.5 } }) do
        G.draw(img, q, cx + d[1] * u, fy + d[2] * u, 0, k, k, ox, oy)
      end
      G.setColor(0, 0, 0, 1)
      G.draw(img, q, cx, fy, 0, k, k, ox, oy)
      G.setShader()
    end
    local b = Bosses[key]
    local px = w * 0.58
    G.setFont(font(22 * u))
    G.setColor(1, 1, 1, 1)
    G.print("Max Raid Battle", px, 24 * u)
    G.setColor(1, 0.85, 0.3, 1)
    drawStars(G, b.stars, px + b.stars * 18 * u, 66 * u, 16 * u)
    G.setFont(font(13 * u))
    G.setColor(0.85, 0.85, 0.9, 1)
    G.print(table.concat(b.types, " / "), px, 82 * u)
    G.setFont(font(14 * u))
    G.setColor(1, 1, 1, 1)
    G.print(("Choose up to four  (%d)"):format(pickedCount()), px, 108 * u)
    -- the party
    local rowH = 28 * u
    for i = #denWhere.rows, #r.party + 1, -1 do denWhere.rows[i] = nil end
    for i, row in ipairs(r.party) do
      local t = denWhere.rows[i] or {}
      denWhere.rows[i] = rset(t, px, 130 * u + (i - 1) * (rowH + 4 * u), w * 0.36, rowH)
      local on = r.picked[i]
      G.setColor(on and 0.75 or 0.22, on and 0.18 or 0.22, on and 0.25 or 0.28, 1)
      G.rectangle("fill", t.x, t.y, t.w, t.h, 6 * u, 6 * u)
      if i == r.cursor then
        G.setColor(1, 1, 1, 0.9)
        G.setLineWidth(2 * u)
        G.rectangle("line", t.x, t.y, t.w, t.h, 6 * u, 6 * u)
      end
      G.setFont(font(13 * u))
      G.setColor(1, 1, 1, 1)
      G.print(row.name, t.x + 10 * u, t.y + 6 * u)
      G.printf("Lv" .. row.level, t.x, t.y + 6 * u, t.w - 10 * u, "right")
    end
    local by = h - 50 * u
    rset(denWhere.start, px, by, w * 0.17, 34 * u)
    rset(denWhere.back, px + w * 0.19, by, w * 0.17, 34 * u)
    button(G, denWhere.start, { 0.2, 0.7, 0.3 }, "START", u, pickedCount() > 0)
    button(G, denWhere.back, { 0.2, 0.45, 0.9 }, "BACK", u, true)
  end

  function Rd.draw(G, w, h)
    if not r then return end
    if r.phase == "den" then return drawDen(G, w, h) end
    local img, q = Rd.frameAt(r.key, r.t)
    if img and loaded then
      bossPic.image, bossPic.quad, bossPic.box, bossPic.size = img, q, loaded.box, Rd.sizeOf(r.key)
    end
    for i = 1, 4 do
      local m = r.members[i]
      memberPicsShown[i] = m and m.draw or nil
    end
    if Scene then Scene.draw(G, 0, 0, w, h, r.t, img and bossPic or nil, memberPicsShown) end
    local padRect = nil
    if Pad and not deps.padOnSecond() then padRect = Pad.draw(G, w, h, r) end
    drawHud(G, w, h, padRect)
  end

  -- ------- for drivers

  local view = {}
  function Rd.state()
    view.active = r ~= nil
    view.key = r and r.key or nil
    view.t = r and r.t or nil
    view.phase = r and r.phase or nil
    view.loaded = Rd.loadedKey()
    view.song = r and r.song or nil
    return view
  end

  return Rd
end
