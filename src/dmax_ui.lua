-- Dynamax in the game's own battles, what shows (src/dmax.lua runs it): the move menu, the
-- DYNAMAX button, the giant on the field. Through wraps of the engine's battle screen:
--   Ui.handleInput    R (START too) in the move menu picks Dynamax (or puts it back); the menu then
--                     works on the Max Moves, SELECT's move swap left alone
--   Help.update       FireRed / LeafGreen's Help System leaves R alone while the button shows
--   Anim.launchGeneral  a G-Max field's / binding's vortex look as the cart move of its kind
--   Ui.draw           the move menu showing the Max Moves (their short names); the giant drawn
--                     bigger and red, a Gigantamax one as its form's animated back
--   Ui.sidePic        that form's picture in the Pokemon's place
--   Anim.launchMove   the Dynamax's look starts the growth (and the giant's cry), its end the shrink
--   Anim.scriptForMove  the two looks: Growth's and Minimize's
--   Anim.tweenHp      the size follows the HP bar's max (so it holds with the animations off)
--   Anim.faintMon     a faint puts it back to its size
--   battle.overlay    the button and the HP box's mark, at the game's 240 x 160
local floor, max, min = math.floor, math.max, math.min

return function(mod, deps)
  local Dm = deps.dmax
  local Bosses, Sprites = deps.bosses or {}, deps.sprites or {}
  local T = deps.T or setmetatable({ game = function(s) return s end }, { __call = function(_, s) return s end })
  local U = {
    GROW_S = 0.6,          -- the growth and the shrink
    K = 1.5,               -- how much bigger
    TINT_RGB = { 1, 0.15, 0.35 },   -- the red over a Dynamax Pokemon
    -- its red breathing: from MIN to MAX and back every S seconds, never off (Gigantamax too)
    BREATH = { MIN = 0.14, MAX = 0.42, S = 2.4 },
    GMAX_H = 92,           -- a Gigantamax form's height in the game's pixels
    ANIM_UNIT_S = 1 / 20,  -- the pack's frame unit (as the raid's)
    BUTTON = { x = 2, y = 98, w = 54, h = 13 },
    TEXT_Y = -1,           -- the word's draw row from the card's top (the small font's glyphs sit low)
    -- the R key beside it (the touch pad's picture, its key cap: 0..1 of the image)
    RKEY = { x = 59, y = 98, w = 22, h = 13 },
    -- a Max Move's red flash: the giant pulsing red, a red wash over the field (FLASH_S long)
    FLASH_S = 0.45, FLASH_COEFF = 0.7, WASH = { 1, 0.12, 0.3, 0.32 },
    -- the red energy shed off a giant (window px, drawn after the frame): RATE motes a second from
    -- points on its outline, each rising RISE of the body's height a second (pushed OUT of its
    -- width outward), swaying SWAY, for LIFE seconds, SIZE of the body's height across (MIN_PX at
    -- least), in one of COLORS; at most MAX at once
    ENERGY = { RATE = 30, RISE = { 0.16, 0.38 }, OUT = 0.06, SWAY = 0.025, LIFE = { 0.7, 1.3 },
      SIZE = { 0.012, 0.028 }, MIN_PX = 1.5, MAX = 240,
      -- (drawn over the battle's light grounds as they are, not added: added light goes white there)
      COLORS = { { 0.95, 0.08, 0.22 }, { 1, 0.3, 0.42 }, { 0.75, 0.02, 0.14 }, { 1, 0.5, 0.6 } } },
    -- red electricity crackling off it: a bolt every EVERY seconds from a point on its outline,
    -- outward LEN of the body's height in SEGS jagged steps (JAG of a step aside), lasting LIFE,
    -- flickering; a red GLOW line under a hot CORE one, WIDTH of the body's height (1 px at least)
    SPARK = { EVERY = { 0.05, 0.18 }, LIFE = { 0.09, 0.18 }, LEN = { 0.14, 0.3 }, SEGS = 6, JAG = 1.0,
      WIDTH = 0.01, MAX = 24, GLOW = { 0.9, 0.02, 0.14 }, GLOW_A = 0.75, CORE = { 1, 0.38, 0.52 } },
    RKEY_SRC = { 0, 0.30, 1, 0.40 },
    -- the HP box's mark, inside the box: its top level with the HP bar's outline (barTop rows into the
    -- bar's tiles), midway across between the box's left edge (frameLeft into its picture: the
    -- same on every cart, singles and doubles) and the bar's; x / y the bar's place when none is drawn
    MARK = { frameLeft = 9, barTop = 1, x = 24, y = 16, s = 7 },
    DOUBLES_K = 0.8,       -- a giant in a double battle this much smaller (the foes' boxes above it)
    LOOK = { DYNAMAX = 74, UNDYNAMAX = 107 },   -- Growth, Minimize
  }
  Dm.ui = U

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local E = {}
  local function engine()
    if E.Ui then return E end
    E.Ui = req("src.core.game3.battle.ui")
    E.Anim = req("src.core.game3.battle.anim")
    E.Moves = req("src.core.game3.battle.moves")
    E.State = req("src.core.game3.battle.state")
    E.Battle = req("src.core.game3.battle")
    E.Font = req("src.ui.game3.frlg_font")
    E.Audio = req("src.core.game3.audio")
    E.Pokemon = req("src.core.game3.pokemon")
    E.Se = req("src.core.game3.se_ids")
    return E
  end

  -- ------- pictures

  local function imageData(path)
    if not (love and love.image and mod.read) then return nil end
    local ok, d = pcall(function()
      local bytes = mod:read(path)
      return bytes and love.image.newImageData(love.filesystem.newFileData(bytes, path:match("[^/]+$")))
    end)
    return ok and d or nil
  end
  local function image(path)
    local d = imageData(path)
    if not d then return nil end
    local ok, img = pcall(love.graphics.newImage, d)
    if not ok then return nil end
    img:setFilter("nearest", "nearest")
    return img
  end
  local icon, iconTried = nil, false
  local function iconImage()
    if not iconTried then iconTried = true icon = image("assets/dmax/icon_dynamax.png") end
    return icon
  end
  -- the engine's own R key cap (its touch pad's picture: the key across the middle of a 256 square)
  local rKey, rKeyTried, rKeyQuad = nil, false, nil
  local function rKeyImage()
    if rKeyTried then return rKey end
    rKeyTried = true
    local ok, img = pcall(love.graphics.newImage, "assets/touch/r.png")
    if not ok or not img then return nil end
    img:setFilter("linear", "linear")
    local w, h = img:getDimensions()
    local K = U.RKEY_SRC
    rKeyQuad = love.graphics.newQuad(K[1] * w, K[2] * h, K[3] * w, K[4] * h, w, h)
    rKey = img
    return rKey
  end

  -- a picture's opaque box (x0, y0, x1, y1, its right and bottom edges past the last pixel) and up
  -- to EDGE_N points on its outline (opaque, a side open), each { u, v } across / down that box
  -- (0..1): where the energy sheds from. From image data over a w x h region at (rx, ry)
  local EDGE_N = 120
  local function opaqueAt(data, rx, ry, w, h, xx, yy)
    if xx < 0 or yy < 0 or xx >= w or yy >= h then return false end
    local _, _, _, al = data:getPixel(rx + xx, ry + yy)
    return al > 0.05
  end
  local function boxAndEdges(data, rx, ry, w, h)
    local x0, y0, x1, y1 = w, h, -1, -1
    local all = {}
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        if opaqueAt(data, rx, ry, w, h, xx, yy) then
          if xx < x0 then x0 = xx end
          if yy < y0 then y0 = yy end
          if xx > x1 then x1 = xx end
          if yy > y1 then y1 = yy end
          if not (opaqueAt(data, rx, ry, w, h, xx - 1, yy) and opaqueAt(data, rx, ry, w, h, xx + 1, yy)
              and opaqueAt(data, rx, ry, w, h, xx, yy - 1) and opaqueAt(data, rx, ry, w, h, xx, yy + 1)) then
            all[#all + 1] = xx
            all[#all + 1] = yy
          end
        end
      end
    end
    if x1 < 0 then return 0, 0, w, h, nil end
    local bw, bh = x1 + 1 - x0, y1 + 1 - y0
    local n = #all / 2
    local edges = {}
    local step = math.max(1, n / EDGE_N)
    local i = 1
    while i <= n and #edges < EDGE_N do
      local j = floor(i)
      edges[#edges + 1] = { (all[2 * j - 1] + 0.5 - x0) / bw, (all[2 * j] + 0.5 - y0) / bh }
      i = i + step
    end
    return x0, y0, x1 + 1, y1 + 1, #edges > 0 and edges or nil
  end
  -- the same for a picture the game hands out (no image data of its own: drawn once to a canvas
  -- and read back - the update step only, never a draw); kept by picture
  local measured = setmetatable({}, { __mode = "k" })
  function U.measure(img)
    local m = measured[img]
    if m ~= nil then return m or nil end
    local ok, r = pcall(function()
      -- (a picture WoobleView draws from a texture of its own - a sprite mod's full-resolution
      -- frame - is measured on that frame: the low-res stand-in is not what shows)
      local okW, W = pcall(mod.find, mod, "gen3-hd-sprites")
      local wx = okW and type(W) == "table" and W.exports or nil
      local spec = wx and type(wx.tagOf) == "function" and wx.tagOf(img) or nil
      local src, quad = img, nil
      if type(spec) == "table" and spec.texture then src, quad = spec.texture, spec.quad end
      local w, h = src:getDimensions()
      if quad and quad.getViewport then
        local _, _, qw, qh = quad:getViewport()
        w, h = qw, qh
      end
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setShader()
      love.graphics.setBlendMode("alpha")
      love.graphics.origin()
      love.graphics.setColor(1, 1, 1, 1)
      if quad then love.graphics.draw(src, quad, 0, 0) else love.graphics.draw(src, 0, 0) end
      love.graphics.pop()
      local d = c:newImageData()
      c:release()
      local x0, y0, x1, y1, edges = boxAndEdges(d, 0, 0, w, h)
      d:release()
      -- (onTexture: the box is the full-resolution frame's, not the low-res picture's)
      return { x0, y0, x1, y1, edges = edges, onTexture = src ~= img }
    end)
    measured[img] = ok and r or false
    return ok and r or nil
  end

  -- the pack key of a G-Max move's form (data/raid_bosses.lua gmax; the species' own first)
  local function packKeyOf(gid, species)
    local nat = nil
    if E.Pokemon and E.Pokemon.national then
      local ok, n = pcall(E.Pokemon.national, species)
      if ok then nat = n end
    end
    local pick
    for _, key in ipairs(Bosses.ORDER or {}) do
      local rec, sp = Bosses[key], Sprites[key]
      if rec and sp and sp.back and rec.gmax == gid and (not pick or rec.national == nat) then pick = key end
    end
    return pick
  end

  -- a Gigantamax form's back sheet as one Image a frame (the engine draws a whole picture), made a
  -- frame or two at a time as they are first wanted; its opaque box from frame 1
  local arts = {}
  function U.artFor(gid, species, shiny)
    local id = tostring(gid) .. (shiny and ":s" or "")
    local a = arts[id]
    if a ~= nil then return a or nil end
    engine()
    local key = packKeyOf(gid, species)
    local sp = key and Sprites[key]
    local B = sp and sp.back
    if not B then arts[id] = false return nil end
    local data = imageData("assets/bosses/backs/" .. key .. ((shiny and sp.shiny) and "_shiny" or "") .. ".png")
    if not data then arts[id] = false return nil end
    local x0, y0, x1, y1, edges = boxAndEdges(data, 0, 0, B.cell, B.cell)
    a = { data = data, B = B, key = key, frames = {}, box = { x0, y0, x1, y1 }, edges = edges,
      speed = (sp.speed and sp.speed[1]) or 2, entry = {} }
    arts[id] = a
    return a
  end
  local function frameOf(a, i)
    local f = a.frames[i]
    if f then return f end
    local B = a.B
    local c, r = (i - 1) % B.cols, floor((i - 1) / B.cols)
    local ok, img = pcall(function()
      local d = love.image.newImageData(B.cell, B.cell)
      d:paste(a.data, 0, 0, c * B.cell, r * B.cell, B.cell, B.cell)
      local im = love.graphics.newImage(d)
      im:setFilter("nearest", "nearest")
      d:release()
      return im
    end)
    if not ok then return nil end
    a.frames[i] = img
    -- (WoobleView: the frame drawn as the player's battler - at the window's resolution, fitted and
    -- sized as it fits a sprite mod's, its body box reported for the energy it sheds)
    local okW, W = pcall(mod.find, mod, "gen3-hd-sprites")
    local wx = okW and type(W) == "table" and W.exports or nil
    if wx and type(wx.tag) == "function" then
      a.spec = a.spec or { side = "player", body = { a.box[1], a.box[2], a.box[3], a.box[4] }, top = a.box[2],
        lowPivot = { 32, 32 } }
      pcall(wx.tag, img, a.spec)
    end
    return img
  end
  -- the frame to show now: made in order, at most two a call
  local function frameNow(a, now)
    local n = a.B.frames
    local want = floor(now / (a.speed * U.ANIM_UNIT_S)) % n + 1
    if a.frames[want] then return a.frames[want] end
    local made = 0
    for i = 1, n do
      if not a.frames[i] and made < 2 then frameOf(a, i) made = made + 1 end
      if a.frames[want] then return a.frames[want] end
    end
    for i = want, 1, -1 do if a.frames[i] then return a.frames[i] end end
    return a.frames[1]
  end

  -- ------- the giant: its size eased toward what it wants

  local function vis(id) return Dm.vis[id] end
  local function grow(v, want, now)
    if v.want == want then return end
    v.from, v.want, v.t0 = v.k or 1, want, now
  end
  local function stepK(v, now)
    if not v.t0 then v.k = v.want or 1 return v.k end
    local u = min(1, (now - v.t0) / U.GROW_S)
    u = u * u * (3 - 2 * u)
    v.k = (v.from or 1) + ((v.want or 1) - (v.from or 1)) * u
    if u >= 1 then v.t0 = nil end
    return v.k
  end

  -- ------- the move menu on the Max Moves

  local cache = { mon = nil, base = {}, max = {}, saved = {} }
  local function activeBattler(st)
    if not st then return nil end
    if st.double then return E.State.battler(st, E.Ui._active or 0) end
    return st.player
  end
  -- the battler whose move menu shows Max Moves now, and those moves (cached by its four)
  local function maxView(st)
    local b = activeBattler(st)
    if not (b and b.mon and b.mon.moves) then return nil end
    local id = E.State.idOf(b)
    if not (b.__mrDmax or Dm.sel[id]) then return nil end
    local mon = b.mon
    local same = cache.mon == mon
    for i = 1, 4 do if cache.base[i] ~= mon.moves[i] then same = false end end
    if not same then
      cache.mon = mon
      for i = 1, 4 do cache.base[i] = mon.moves[i] end
      Dm.maxMovesOf(b, cache.max)
    end
    return b, cache.max
  end
  local labels = false
  local function swapIn(mon, list)
    for i = 1, 4 do cache.saved[i] = mon.moves[i]; mon.moves[i] = list[i] end
  end
  local function swapOut(mon)
    for i = 1, 4 do mon.moves[i] = cache.saved[i] end
  end
  -- (the move menu, and a doubles move's target after it: both on the Max Moves - one target)
  local function moveMode() return E.Ui._mode == "moves" or E.Ui._mode == "target" end

  -- ------- the wraps

  function U.install()
    for k in pairs(E) do E[k] = nil end
    engine()
    local Ui, Anim, Moves = E.Ui, E.Anim, E.Moves
    if not (Ui and Anim and Moves) then return false end
    if Ui.__mrDmax then return true end
    Ui.__mrDmax = true

    -- the short names in the move menu
    local displayName = Moves.displayName
    Moves.displayName = function(mv, ...)
      if labels then
        local row = Dm.byNum[tonumber(mv) or -1]
        if row then return row.label end
      end
      return displayName(mv, ...)
    end

    -- R (or START) picks Dynamax in the move menu; the menu then works on the Max Moves
    local handleInput = Ui.handleInput
    Ui.handleInput = function(input, ...)
      local st = Ui._st
      if not (st and st.__mr and st.__mr.allowed and input and moveMode()) then return handleInput(input, ...) end
      local b = activeBattler(st)
      local id = b and E.State.idOf(b)
      if b and not b.__mrDmax and E.Ui._mode == "moves" and (input:wasPressed("start") or input:wasPressed("r")) then
        if Dm.sel[id] then
          Dm.sel[id] = nil
        elseif Dm.can(st, b) then
          Dm.sel[id] = true
        else
          return handleInput(input, ...)
        end
        if E.Audio and E.Audio.playSe and E.Se then pcall(E.Audio.playSe, E.Se.SE_SELECT) end
        return true
      end
      local vb, list = maxView(st)
      if not vb then return handleInput(input, ...) end
      if input:wasPressed("select") then return true end
      swapIn(vb.mon, list)
      local ok, r = pcall(handleInput, input, ...)
      swapOut(vb.mon)
      if not ok then error(r, 0) end
      -- (backed out of the move menu: Dynamax picked no more)
      if not vb.__mrDmax and E.Ui._mode == "menu" then Dm.sel[id] = nil end
      return r
    end

    -- the move menu on the Max Moves; the giant's size, colour and form
    local draw = Ui.draw
    local drawing = false
    local sidePic = Ui.sidePic
    local now = 0
    -- (the picture each giant is drawn with this frame: its form's, or its own - noted so the draw
    -- that places it is known, for the energy it sheds)
    Ui.sidePic = function(back, ign, picSp, form, shiny, personality, mon, ...)
      if drawing and mon then
        for _, v in pairs(Dm.vis) do
          if v.mon == mon and (v.k or 1) > 1.01 then
            if back and v.art and v.k > 1 + (U.K - 1) * 0.5 then
              local img = frameNow(v.art, now)
              if img then
                v.art.entry.image = img
                v.picImg, v.picArt = img, true
                return v.art.entry
              end
            end
            local entry = sidePic(back, ign, picSp, form, shiny, personality, mon, ...)
            v.picImg, v.picArt = entry and entry.image or nil, false
            return entry
          end
        end
      end
      return sidePic(back, ign, picSp, form, shiny, personality, mon, ...)
    end
    -- the draw that places a giant's picture: its box on the battle's canvas, through the transform
    -- (a shake, a lunge) - where the energy sheds from when WoobleView doesn't say where it drew it
    local catching, frameNo = false, 0
    local realDraw = nil
    local function noteDraw(v, img, x, y, sx, sy, ox, oy)
      local iw, ih = img:getDimensions()
      local bx0, by0, bx1, by1 = 0, 0, iw, ih
      if v.picArt and v.art then
        bx0, by0, bx1, by1 = v.art.box[1], v.art.box[2], v.art.box[3], v.art.box[4]
      elseif v.picBox and v.picBoxOf == img and not v.picBox.onTexture then
        bx0, by0, bx1, by1 = v.picBox[1], v.picBox[2], v.picBox[3], v.picBox[4]
      end
      local G = love.graphics
      local ax, ay = G.transformPoint(x + (bx0 - ox) * sx, y + (by0 - oy) * sy)
      local bx, by = G.transformPoint(x + (bx1 - ox) * sx, y + (by1 - oy) * sy)
      local r = v.nat or {}
      v.nat = r
      r[1], r[2], r[3], r[4] = min(ax, bx), min(ay, by), max(ax, bx), max(ay, by)
      v.natFrame = frameNo
    end
    local function catcher(img, x, y, rot, sx, sy, ox, oy, ...)
      if catching and type(x) == "number" then
        for _, v in pairs(Dm.vis) do
          if v.picImg ~= nil and v.picImg == img then
            pcall(noteDraw, v, img, x, y, tonumber(sx) or 1, tonumber(sy) or tonumber(sx) or 1, tonumber(ox) or 0,
              tonumber(oy) or 0)
          end
        end
      end
      return realDraw(img, x, y, rot, sx, sy, ox, oy, ...)
    end
    function U.frameNo() return frameNo end
    local saved = {}
    Ui.draw = function(w, h, ...)
      local st = Ui._st
      if not (st and st.__mr and st.__mr.allowed) then return draw(w, h, ...) end
      now = love.timer and love.timer.getTime() or 0
      frameNo = frameNo + 1
      -- (the giants: size, red, the form's offsets; put back after the draw)
      local n = 0
      local dk = st.double and U.DOUBLES_K or 1
      local any = false
      for id, v in pairs(Dm.vis) do
        local k0 = stepK(v, now)
        if k0 > 1.01 then any = true end
        local k = 1 + (k0 - 1) * dk
        local p = k0 ~= 1 and Anim.present(id)
        if p then
          n = n + 1
          local s = saved[n] or {}
          saved[n] = s
          s.p, s.sx, s.sy, s.ox, s.oy, s.bc, s.bcol = p, p.sx, p.sy, p.ox, p.oy, p.blendCoeff, p.blendColor
          local gm = v.art and k0 > 1 + (U.K - 1) * 0.5
          if gm then
            local A = v.art
            local hgt = max(1, A.box[4] - A.box[2])
            local sc = U.GMAX_H * dk / hgt * (k0 / U.K)
            local bx = (A.box[1] + A.box[3]) / 2
            p.sx, p.sy = (p.sx or 1) * sc, (p.sy or 1) * sc
            p.ox = (p.ox or 0) - (bx - 32) * sc
            p.oy = (p.oy or 0) + 32 - (A.box[4] - 32) * sc
          else
            p.sx, p.sy = (p.sx or 1) * k, (p.sy or 1) * k
            p.oy = (p.oy or 0) - 32 * (k - 1)
          end
          -- (red that breathes, never off, as it grows; a blend the battle itself set - a hit's
          -- flash, a status - is left alone)
          if (tonumber(p.blendCoeff) or 0) <= 0 then
            local B = U.BREATH
            local br = B.MIN + (B.MAX - B.MIN) * (0.5 + 0.5 * math.sin(now * 2 * math.pi / B.S))
            p.blendCoeff = br * min(1, (k0 - 1) / (U.K - 1))
            p.blendColor = U.TINT_RGB
          end
          -- (a Max Move: the giant pulses red as it strikes, its form too)
          local fu = v.flashT and (now - v.flashT) / U.FLASH_S
          if fu and fu < 1 then
            p.blendCoeff = U.FLASH_COEFF * (1 - fu) * (0.6 + 0.4 * math.cos(fu * 18))
            p.blendColor = U.TINT_RGB
          end
        end
      end
      local vb, list = nil, nil
      if moveMode() then vb, list = maxView(st) end
      drawing = true
      if vb then swapIn(vb.mon, list) labels = true end
      local G = love.graphics
      if any then
        realDraw = G.draw
        catching = true
        G.draw = catcher
      end
      local ok, r = pcall(draw, w, h, ...)
      if any then
        G.draw = realDraw
        catching = false
      end
      if vb then swapOut(vb.mon) labels = false end
      drawing = false
      for i = n, 1, -1 do
        local s = saved[i]
        local p = s.p
        p.sx, p.sy, p.ox, p.oy, p.blendCoeff, p.blendColor = s.sx, s.sy, s.ox, s.oy, s.bc, s.bcol
        s.p = nil
      end
      if not ok then error(r, 0) end
      return r
    end

    -- the two looks: Growth's for the Dynamax, Minimize's for its end
    local scriptFor = Anim.scriptForMove
    Anim.scriptForMove = function(moveId, ...)
      local row = Dm.byNum[tonumber(moveId) or -1]
      if row and row.internal then return scriptFor(U.LOOK[row.key] or 74, ...) end
      return scriptFor(moveId, ...)
    end
    -- the Dynamax's look starts the growth and the giant's cry; its end's look the shrink
    local launch = Anim.launchMove
    Anim.launchMove = function(moveId, opts, ...)
      local row = Dm.byNum[tonumber(moveId) or -1]
      if row and row.internal and type(opts) == "table" then
        local id = opts.attackerId
        local v = id ~= nil and Dm.vis[id]
        local t = love.timer and love.timer.getTime() or 0
        if v and row.key == "DYNAMAX" then
          grow(v, U.K, t)
          if deps.bigCry and v.species then pcall(deps.bigCry, v.species) end
        elseif v and row.key == "UNDYNAMAX" then
          grow(v, 1, t)
        end
      elseif type(opts) == "table" and opts.attackerId ~= nil and not opts.miss then
        -- (a Dynamaxed Pokemon's move - a Max Move, drawn as its base move: the red flash with it)
        local v = Dm.vis[opts.attackerId]
        if v and (v.want or 1) > 1 then
          local t = love.timer and love.timer.getTime() or 0
          v.flashT, U.washT = t, t
        end
      end
      return launch(moveId, opts, ...)
    end
    -- the size follows the HP bar's max: the Dynamax max, or the base one
    local tween = Anim.tweenHp
    Anim.tweenHp = function(id, from, to, maxHp, ...)
      local v = Dm.vis[id]
      if v and maxHp then
        local t = love.timer and love.timer.getTime() or 0
        if maxHp == v.dynMax then grow(v, U.K, t) elseif maxHp == v.baseMax then grow(v, 1, t) end
      end
      return tween(id, from, to, maxHp, ...)
    end
    -- the trapped-in-a-vortex look takes the trapping move's number: a G-Max one's (Centiferno,
    -- Sandblast: their binding is the engine's) shown as the cart move of its kind
    local launchGeneral = Anim.launchGeneral
    if launchGeneral then
      Anim.launchGeneral = function(name, opts, ...)
        if name == "TURN_TRAP" and type(opts) == "table" then
          local row = Dm.byNum[tonumber(opts.animArg) or -1]
          local look = row and Dm.data and Dm.data.TRAP_LOOK[row.key]
          if look then
            opts.animArg = look
            if type(opts.ctx) == "table" then opts.ctx.animArg = look end
          end
        end
        return launchGeneral(name, opts, ...)
      end
    end
    -- FireRed / LeafGreen open their Help System on L or R: while the DYNAMAX button shows, R is its
    -- (L still opens the Help)
    local okH, Help = pcall(require, "src.ui.game3.help_system")
    if okH and type(Help) == "table" and type(Help.update) == "function" and not Help.__mrDmax then
      Help.__mrDmax = true
      local helpUpdate = Help.update
      Help.update = function(game, ...)
        local input = type(game) == "table" and game.input or nil
        if not Help.open and input and input.wasPressed and input:wasPressed("r") and not input:wasPressed("l")
            and U.buttonShown() then
          return false
        end
        return helpUpdate(game, ...)
      end
    end

    -- (the update step: a giant's own picture measured, once a picture: its box and outline)
    local Battle = E.Battle
    if Battle and type(Battle.update) == "function" and not Battle.__mrDmaxUi then
      Battle.__mrDmaxUi = true
      local update = Battle.update
      Battle.update = function(...)
        local a, b = update(...)
        for _, v in pairs(Dm.vis) do
          local img = v.picImg
          if img and not v.picArt and v.picBoxOf ~= img then
            v.picBox, v.picBoxOf = U.measure(img), img
          end
        end
        return a, b
      end
    end

    local faint = Anim.faintMon
    if faint then
      Anim.faintMon = function(id, ...)
        local v = Dm.vis[id]
        if v then v.want, v.k, v.t0 = 1, 1, nil end
        return faint(id, ...)
      end
    end

    -- the giant's mark on its HP box: the box's top left noted as the engine draws it (only inside
    -- Healthbox.draw, as the National Dex's type badges), the mark drawn at its top right after it
    local Chrome = req("src.ui.game3.battle_chrome")
    local Healthbox = req("src.core.game3.battle.healthbox")
    if Chrome and Healthbox and type(Healthbox.draw) == "function" then
      local inside, boxX, boxY, barX, barY = 0, nil, nil, nil, nil
      local function note(x, y) if inside > 0 then boxX, boxY = x, y end end
      -- (and its HP bar: the mark sits beside it)
      local dbar = Chrome.drawHpBar
      if type(dbar) == "function" then
        Chrome.drawHpBar = function(x, y, ...)
          if inside > 0 and barX == nil then barX, barY = x, y end
          return dbar(x, y, ...)
        end
      end
      local dp, dd = Chrome.drawPlayerBox, Chrome.drawDoublesBox
      if type(dp) == "function" then
        Chrome.drawPlayerBox = function(x, y, ...) note(x, y) return dp(x, y, ...) end
      end
      if type(dd) == "function" then
        Chrome.drawDoublesBox = function(isPlayer, x, y, ...)
          if isPlayer then note(x, y) end
          return dd(isPlayer, x, y, ...)
        end
      end
      local hdraw = Healthbox.draw
      Healthbox.draw = function(side, battler, o, ...)
        inside = inside + 1
        boxX, barX, barY = nil, nil, nil
        local ok, a, b2 = pcall(hdraw, side, battler, o, ...)
        inside = inside - 1
        if not ok then error(a, 0) end
        if inside == 0 and boxX and type(battler) == "table" and battler.__mrDmax then
          local img = iconImage()
          if img then
            love.graphics.setColor(1, 1, 1, 1)
            local M = U.MARK
            -- (its top level with the HP bar's; across, midway between the box's left edge and the
            -- bar's; without a bar drawn - HP as text - where the bar would be)
            local left = boxX + M.frameLeft
            local bx, by = barX or (boxX + M.x), barY or (boxY + M.y)
            local mx = floor((left + bx) / 2 - M.s / 2 + 0.5)
            local my = by + M.barTop
            U.lastMark = U.lastMark or {}
            U.lastMark[1], U.lastMark[2], U.lastMark[3], U.lastMark[4], U.lastMark[5], U.lastMark[6] =
              boxX, boxY, barX, barY, mx, my
            love.graphics.draw(img, mx, my, 0, M.s / img:getWidth(), M.s / img:getHeight())
          end
        end
        return a, b2
      end
    end

    -- the button and its R key (in the move menu, while Dynamax may be picked)
    if mod.hooks and mod.hooks.wrap then
      mod.hooks:wrap("battle.overlay", function(next, st, ...)
        local r = next(st, ...)
        if st and st.__mr and st.__mr.allowed then
          pcall(U.drawWash)
          pcall(U.drawOverlay, st)
        end
        return r
      end)
    end
    return true
  end

  -- a Max Move's red wash over the field (above the text box), fading over FLASH_S
  function U.drawWash()
    if not U.washT then return end
    local u = ((love.timer and love.timer.getTime() or 0) - U.washT) / U.FLASH_S
    if u >= 1 or u < 0 then U.washT = nil return end
    local W = U.WASH
    local G = love.graphics
    G.setColor(W[1], W[2], W[3], W[4] * (1 - u) * (1 - u))
    G.rectangle("fill", 0, 0, 240, 112)
    G.setColor(1, 1, 1, 1)
  end

  -- WoobleView, when it is there and reports where it drew each battler (exports.battlerRect -
  -- whatever its fit, 3D Sizing or 3D world made of it)
  local wv = nil
  local function woobleView()
    if wv == nil then
      local ok, m = pcall(mod.find, mod, "gen3-hd-sprites")
      wv = ok and type(m) == "table" and m.exports and type(m.exports.battlerRect) == "function" and m.exports or false
    end
    return wv or nil
  end
  -- WoobleView's HUD held while a giant is out (or shrinking back): its camera pulls back for the
  -- giant, the foe's HP box stays put (exports.holdHud); let go once none is, or the battle is over
  local holding = false
  local function holdHud(on)
    if on == holding then return end
    holding = on
    local okW, W = pcall(mod.find, mod, "gen3-hd-sprites")
    local wx = okW and type(W) == "table" and W.exports or nil
    if wx and type(wx.holdHud) == "function" then pcall(wx.holdHud, "max_raids", on) end
  end

  -- the energy's motes: one pool, its records kept (no tables a frame); `live` the first n
  local motes, live = {}, 0
  for i = 1, U.ENERGY.MAX do motes[i] = { x = 0, y = 0, vx = 0, vy = 0, t = 0, life = 1, size = 1, c = 1, ph = 0 } end
  local spawnAcc = {}
  local function rnd(a, b) return a + (b - a) * math.random() end
  local function spawn(v, x0, y0, x1, y1, strength)
    if live >= #motes then return end
    local E2 = U.ENERGY
    local w, h = x1 - x0, y1 - y0
    local u, vv
    local edges = (v.picArt and v.art and v.art.edges) or (v.picBox and v.picBox.edges)
    if edges then
      local e = edges[math.random(#edges)]
      u, vv = e[1], e[2]
    else
      u, vv = math.random(), rnd(0, 0.7)
    end
    live = live + 1
    local m = motes[live]
    m.x, m.y = x0 + u * w, y0 + vv * h
    m.vx = (u - 0.5) * 2 * E2.OUT * w
    m.vy = -rnd(E2.RISE[1], E2.RISE[2]) * h
    m.t, m.life = 0, rnd(E2.LIFE[1], E2.LIFE[2])
    m.size = max(E2.MIN_PX, rnd(E2.SIZE[1], E2.SIZE[2]) * h) * (0.6 + 0.4 * strength)
    m.c, m.ph, m.sway = math.random(#E2.COLORS), math.random() * 6.28, E2.SWAY * w
  end
  function U.energyCount() return live end

  -- the electricity's bolts: one pool, each its points kept (SEGS + 1 of them)
  local bolts, boltsLive = {}, 0
  for i = 1, U.SPARK.MAX do
    local b = { t = 0, life = 1, xs = {}, ys = {} }
    for j = 1, U.SPARK.SEGS + 1 do b.xs[j], b.ys[j] = 0, 0 end
    bolts[i] = b
  end
  local sparkT = {}
  local function bolt(v, x0, y0, x1, y1)
    if boltsLive >= #bolts then return end
    local S = U.SPARK
    local w, h = x1 - x0, y1 - y0
    local u, vv
    local edges = (v.picArt and v.art and v.art.edges) or (v.picBox and v.picBox.edges)
    if edges then
      local e = edges[math.random(#edges)]
      u, vv = e[1], e[2]
    else
      u, vv = math.random(), rnd(0, 0.8)
    end
    boltsLive = boltsLive + 1
    local b = bolts[boltsLive]
    b.t, b.life = 0, rnd(S.LIFE[1], S.LIFE[2])
    -- (outward from the body's middle, give or take)
    local ang = math.atan2(vv - 0.5, u - 0.5) + rnd(-0.7, 0.7)
    local len = rnd(S.LEN[1], S.LEN[2]) * h
    local dx, dy = math.cos(ang), math.sin(ang)
    local sx, sy = x0 + u * w, y0 + vv * h
    local step = len / S.SEGS
    for j = 0, S.SEGS do
      local off = (j == 0) and 0 or rnd(-1, 1) * S.JAG * step
      b.xs[j + 1] = sx + dx * step * j - dy * off
      b.ys[j + 1] = sy + dy * step * j + dx * off
    end
    b.width = max(1, S.WIDTH * h)
  end
  function U.boltCount() return boltsLive end
  -- (drivers: the first live bolt's points and width)
  function U._bolt(i) local b = bolts[i or 1] return b and i ~= nil and i <= boltsLive and b or (boltsLive > 0 and b or nil) end

  local lastFrame = -1   -- (the battle's draw count at the last frame the energy drew)

  -- a giant's body on the window this frame: WoobleView's report, else the battle's own draw
  local function bodyNow(st, id, v, viewport)
    -- (drawn by the battle this frame at all: else nothing - hidden, fainted, a screen over it)
    if v.natFrame ~= U.frameNo() then return nil end
    local W = woobleView()
    if W then
      local x0, y0, x1, y1 = W.battlerRect(st.double and id or (id % 2 == 0 and "player" or "enemy"))
      if x0 then return x0, y0, x1, y1, "woobleview" end
    end
    if not v.nat then return nil end
    local okV, Viewport = pcall(require, "src.render.GameViewport")
    local okD, Display = pcall(require, "src.core.game3.display")
    local G = love.graphics
    local vw = type(viewport) == "table" and viewport.width or G.getWidth()
    local vh = type(viewport) == "table" and viewport.height or G.getHeight()
    if okV and Viewport.dimensions then vw, vh = Viewport.dimensions() end
    if not (okD and Display.fit) then return nil end
    local sx, ox, oy, _, _, sy = Display.fit(vw, vh)
    sy = sy or sx
    local n = v.nat
    return ox + n[1] * sx, oy + n[2] * sy, ox + n[3] * sx, oy + n[4] * sy, "battle"
  end

  -- each frame, after it (main.lua's render.hud): the HUD's hold, then the energy - motes shed from
  -- each giant's outline, rising, swaying and fading, and red electricity crackling off it, at the
  -- window's resolution
  function U.drawEnergy(viewport)
    engine()
    local st = E.Ui and E.Ui._st
    local active = st and st.__mr and st.__mr.allowed and E.Battle and E.Battle.isActive and E.Battle.isActive()
    local giant = false
    if active then
      for _, v in pairs(Dm.vis) do
        if (v.want or 1) > 1 or (v.k or 1) > 1.001 then giant = true end
      end
    end
    holdHud(giant and true or false)
    -- (only over the battle as it shows: not while the bag or the party - or any screen the
    -- battle's own draw gave way to - is over it; what was in the air then is gone)
    local fresh = U.frameNo() ~= lastFrame
    lastFrame = U.frameNo()
    local mode = E.Ui and E.Ui._mode
    if not (active and fresh) or mode == "bag" or mode == "party" then live, boltsLive = 0, 0 return end
    local dt = min(0.1, love.timer and love.timer.getDelta() or 1 / 60)
    local E2 = U.ENERGY
    -- (new motes off each giant drawn this frame)
    for id, v in pairs(Dm.vis) do
      local k = v.k or 1
      if k > 1.01 then
        local x0, y0, x1, y1, from = bodyNow(st, id, v, viewport)
        if x0 then
          U.lastEnergy = from
          local strength = min(1, (k - 1) / (U.K - 1))
          local acc = (spawnAcc[id] or 0) + E2.RATE * strength * dt
          while acc >= 1 do
            spawn(v, x0, y0, x1, y1, strength)
            acc = acc - 1
          end
          spawnAcc[id] = acc
          -- (and now and then a bolt of red electricity)
          local tleft = (sparkT[id] or 0) - dt
          if tleft <= 0 then
            bolt(v, x0, y0, x1, y1)
            local S = U.SPARK
            tleft = rnd(S.EVERY[1], S.EVERY[2]) / max(0.2, strength)
          end
          sparkT[id] = tleft
        end
      end
    end
    -- (the bolts age; one gone is swapped with the last live one)
    local bi = 1
    while bi <= boltsLive do
      local b = bolts[bi]
      b.t = b.t + dt
      if b.t >= b.life then
        bolts[bi], bolts[boltsLive] = bolts[boltsLive], b
        boltsLive = boltsLive - 1
      else
        bi = bi + 1
      end
    end
    -- (the motes move and fade; one gone is swapped with the last live one)
    local i = 1
    while i <= live do
      local m = motes[i]
      m.t = m.t + dt
      if m.t >= m.life then
        motes[i], motes[live] = motes[live], m
        live = live - 1
      else
        m.x = m.x + (m.vx + math.cos(m.ph + m.t * 5) * m.sway) * dt
        m.y = m.y + m.vy * dt
        m.vx = m.vx * (1 - 0.8 * dt)
        i = i + 1
      end
    end
    if live == 0 and boltsLive == 0 then return end
    local G = love.graphics
    G.setBlendMode("alpha")
    for j = 1, live do
      local m = motes[j]
      local u = m.t / m.life
      local a = (u < 0.15 and u / 0.15 or (1 - (u - 0.15) / 0.85)) * 0.9
      local c = E2.COLORS[m.c]
      local r = m.size * (1 - 0.4 * u)
      G.setColor(c[1], c[2], c[3], a * 0.25)
      G.circle("fill", m.x, m.y, r * 2.2, 10)
      G.setColor(c[1], c[2], c[3], a)
      G.circle("fill", m.x, m.y, r, 8)
    end
    -- (the bolts: a red glow under a hot core, flickering as they go)
    local S = U.SPARK
    G.setLineJoin("miter")
    for j = 1, boltsLive do
      local b = bolts[j]
      -- (whole for most of its life, fading at the end; flickering throughout)
      local u = b.t / b.life
      local a = (u < 0.6 and 1 or (1 - u) / 0.4) * (0.75 + 0.25 * math.random())
      local xs, ys = b.xs, b.ys
      G.setLineWidth(b.width * 3)
      G.setColor(S.GLOW[1], S.GLOW[2], S.GLOW[3], a * S.GLOW_A)
      for q = 1, S.SEGS do G.line(xs[q], ys[q], xs[q + 1], ys[q + 1]) end
      G.setLineWidth(b.width)
      G.setColor(S.CORE[1], S.CORE[2], S.CORE[3], a)
      for q = 1, S.SEGS do G.line(xs[q], ys[q], xs[q + 1], ys[q + 1]) end
    end
    G.setLineWidth(1)
    G.setColor(1, 1, 1, 1)
  end

  -- whether the DYNAMAX button shows now: a battle that allows it, the move menu, the one choosing
  -- not yet Dynamaxed and able (or already picked)
  function U.buttonShown()
    local Ui = E.Ui
    local st = Ui and Ui._st
    if not (st and st.__mr and st.__mr.allowed and Ui._mode == "moves") then return false end
    if not (E.Battle and E.Battle.isActive and E.Battle.isActive()) then return false end
    local b = activeBattler(st)
    if not b or b.__mrDmax then return false end
    return Dm.sel[E.State.idOf(b)] == true or (Dm.can(st, b)) == true
  end

  function U.drawOverlay(st)
    local G = love.graphics
    if E.Ui._mode ~= "moves" then return end
    local b = activeBattler(st)
    if not b or b.__mrDmax then return end
    local id = E.State.idOf(b)
    local on = Dm.sel[id] and true or false
    if not on and not Dm.can(st, b) then return end
    local B = U.BUTTON
    G.setColor(0, 0, 0, 0.55)
    G.rectangle("fill", B.x + 1, B.y + 1, B.w, B.h, 3, 3)
    if on then G.setColor(0.93, 0.2, 0.42, 1) else G.setColor(0.55, 0.08, 0.16, 1) end
    G.rectangle("fill", B.x, B.y, B.w, B.h, 3, 3)
    G.setColor(1, 1, 1, on and 1 or 0.55)
    G.rectangle("line", B.x + 0.5, B.y + 0.5, B.w - 1, B.h - 1, 3, 3)
    local img = iconImage()
    local iconR = B.x + 2
    if img then
      G.setColor(1, 1, 1, 1)
      G.draw(img, B.x + 2, B.y + 1, 0, 11 / img:getWidth(), 11 / img:getHeight())
      iconR = B.x + 14
    end
    -- (the word centred on the card; clear of the icon when it would reach it)
    if E.Font and E.Font.draw then
      local text = T.game("DYNAMAX")
      local tw = 40
      if E.Font.measure then
        local okW, w = pcall(E.Font.measure, text, { small = true })
        if okW and tonumber(w) then tw = tonumber(w) end
      end
      local tx = B.x + (B.w - tw) / 2
      if tx < iconR then tx = iconR + (B.x + B.w - iconR - tw) / 2 end
      E.Font.draw(text, floor(tx + 0.5), B.y + U.TEXT_Y, { small = true, colors = E.Font.COLOR.WHITE })
    end
    -- the R shoulder button beside it, as the touch pad draws its own: a soft pill and the key cap
    local R = U.RKEY
    local key = rKeyImage()
    if key then
      local rh = R.h * 1.08
      local rw = R.w * 1.08
      G.setColor(1, 1, 1, on and 0.45 or 0.3)
      G.rectangle("fill", R.x + (R.w - rw) / 2, R.y + (R.h - rh) / 2, rw, rh, rh * 0.32, rh * 0.32)
      G.setColor(1, 1, 1, 1)
      local _, _, qw, qh = rKeyQuad:getViewport()
      G.draw(key, rKeyQuad, R.x, R.y, 0, R.w / qw, R.h / qh)
      -- (its letter white over the cap's own grey one, so it reads at this size)
      if E.Font and E.Font.draw then
        local lw = 5
        if E.Font.measure then
          local okW, w = pcall(E.Font.measure, "R", { small = true })
          if okW and tonumber(w) then lw = tonumber(w) end
        end
        E.Font.draw("R", floor(R.x + (R.w - lw) / 2 + 0.5), R.y + U.TEXT_Y,
          { small = true, colors = E.Font.COLOR.WHITE })
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- a tap (input.pointer, main.lua): on the DYNAMAX button or its R key while they show, as R. The tap's
  -- place in the game's picture (window units) taken to the battle's 240 x 160 as the game fits it
  function U.pointer(ev)
    if type(ev) ~= "table" or ev.phase ~= "pressed" or not ev.insideGame then return false end
    engine()
    local Ui = E.Ui
    local st = Ui and Ui._st
    if not (st and st.__mr and st.__mr.allowed and Ui._mode == "moves") then return false end
    if not (E.Battle and E.Battle.isActive and E.Battle.isActive()) then return false end
    local okV, Viewport = pcall(require, "src.render.GameViewport")
    local okD, Display = pcall(require, "src.core.game3.display")
    if not (okV and okD and Viewport.dimensions and Display.fit) then return false end
    local vw, vh = Viewport.dimensions()
    local sx, ox, oy, _, _, sy = Display.fit(vw, vh)
    if not (sx and sx > 0) then return false end
    local nx, ny = (ev.gameX - ox) / sx, (ev.gameY - oy) / (sy or sx)
    local B, R = U.BUTTON, U.RKEY
    local onCard = nx >= B.x and ny >= B.y and nx <= B.x + B.w and ny <= B.y + B.h
    local onKey = nx >= R.x and ny >= R.y and nx <= R.x + R.w and ny <= R.y + R.h
    if not (onCard or onKey) then return false end
    local b = activeBattler(st)
    if not b or b.__mrDmax then return false end
    local id = E.State.idOf(b)
    if Dm.sel[id] then Dm.sel[id] = nil
    elseif Dm.can(st, b) then Dm.sel[id] = true
    else return false end
    if E.Audio and E.Audio.playSe and E.Se then pcall(E.Audio.playSe, E.Se.SE_SELECT) end
    return true
  end

  -- the Dynamax Band's Bag icon: its picture (48 x 48, the art's double size) halved to the Bag's
  -- 24 x 24 once, on the CPU; drawn through both Bags' icon calls (FireRed / LeafGreen's, Ruby /
  -- Sapphire / Emerald's) for its number, as the National Dex draws its own items'
  local bandIcon, bandTried = nil, false
  local function bandImage()
    if bandTried then return bandIcon end
    bandTried = true
    local d = imageData("assets/dmax/dynamax_band.png")
    if not d then return nil end
    local w, h = d:getDimensions()
    local k = max(1, floor(w / 24))
    local ok, img = pcall(function()
      local out = love.image.newImageData(24, 24)
      for y = 0, 23 do
        for x = 0, 23 do
          if x * k < w and y * k < h then out:setPixel(x, y, d:getPixel(x * k, y * k)) end
        end
      end
      local im = love.graphics.newImage(out)
      im:setFilter("nearest", "nearest")
      return im
    end)
    d:release()
    bandIcon = ok and img or nil
    return bandIcon
  end
  function U.installBagIcon(index)
    local okF, Frlg = pcall(require, "src.ui.game3.bag_chrome")
    if okF and type(Frlg) == "table" and type(Frlg.drawItemIcon) == "function" and not Frlg.__mrBand then
      Frlg.__mrBand = true
      local orig = Frlg.drawItemIcon
      Frlg.drawItemIcon = function(itemId, px, py, scale, ...)
        if tonumber(itemId) == index then
          local img = bandImage()
          if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, px or 0, py or 0, 0, scale or 1, scale or 1)
            return true
          end
        end
        return orig(itemId, px, py, scale, ...)
      end
    end
    local okR, Rse = pcall(require, "src.ui.game3.rse.bag_chrome")
    if okR and type(Rse) == "table" and type(Rse.drawItemIcon) == "function" and not Rse.__mrBand then
      Rse.__mrBand = true
      local orig = Rse.drawItemIcon
      Rse.drawItemIcon = function(idx, x, y, rotation, ox, oy, ...)
        if tonumber(idx) == index then
          local img = bandImage()
          if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, x, y, rotation or 0, 1, 1, ox or 0, oy or 0)
            return
          end
        end
        return orig(idx, x, y, rotation, ox, oy, ...)
      end
    end
  end

  -- a Dynamax begun (src/dmax.lua): the form's art ready for the growth
  function U.onDynamax(rec, b)
    engine()
    local v = Dm.vis[rec.id]
    if not v then return end
    v.mon = rec.mon
    v.species = E.Pokemon and E.Pokemon.speciesOf and select(2, pcall(E.Pokemon.speciesOf, rec.mon)) or rec.mon.species
    if rec.gmax then
      local shiny = E.Pokemon and E.Pokemon.isShiny and select(2, pcall(E.Pokemon.isShiny, rec.mon)) == true
      v.art = U.artFor(rec.gmax, v.species, shiny)
      if v.art then frameOf(v.art, 1) end
    end
  end

  return U
end
