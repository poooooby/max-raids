-- The battle pad: Sword / Shield's command stack - Fight, Pokemon, Bag, Run - as pills down the main
-- window's lower right. Each is white with black words and its emblem in colour at its right end;
-- the selected one is black with white words and a brighter emblem, and a white chevron points at
-- it from the left. With BATTLE PAD on the second screen it is drawn into that display's frame
-- instead (Pad.drawFull). Pokemon shows the summary (no switching in a Max Raid).
--   Pad.draw(G, w, h, r) -> the stack's rect (window pixels) ; Pad.drawFull(G, w, h, r)
--   Pad.hit(x, y) -> "fight" | "bag" | "run" | "panel" | nil (against the last draw)
--   Pad.secondMove(menu, cursor, n, dir) -> the cursor after a D-pad press on the second screen
--   Pad.ITEMS (the order) ; Pad.live(id)

return function(mod, deps)
  local Pad = {}
  local max, min, cos, sin, pi = math.max, math.min, math.cos, math.sin, math.pi

  -- the commands, top to bottom: id, words, the emblem's colour
  -- (no Pokemon button: Wooble 2026-10-27 - Fight, Bag, Run)
  Pad.ITEMS = {
    { id = "fight", word = "Fight", rgb = { 0.93, 0.18, 0.42 } },
    { id = "bag", word = "Bag", rgb = { 0.96, 0.66, 0.33 } },
    { id = "run", word = "Run", rgb = { 0.74, 0.48, 0.96 } },
  }
    local LIVE = { fight = true, pokemon = true, bag = true, run = true }
  function Pad.live(id) return LIVE[id] == true end

  -- sizes in the window's height, measured off a 1784 x 998 capture: pills 325 x 92 on a 108 pitch,
  -- 12 in from the right edge and the foot; the chevron 55 wide reaching 37 left of a pill
  Pad.LOOK = { W = 0.326, H = 0.092, PITCH = 0.108, EDGE = 0.012, ARROW = 0.037, TEXT = 0.04 }

  -- the last draw's places (window pixels), filled again each draw; `flee` is `run` (older drivers)
  local where = { panel = {}, fight = {}, pokemon = {}, bag = {}, run = {},
    move1 = {}, move2 = {}, move3 = {}, move4 = {}, back = {}, dynamax = {} }
  where.flee = where.run
  Pad.where = where
  local function rset(t, x, y, w, h) t.x, t.y, t.w, t.h = x, y, w, h; return t end
  local function inRect(x, y, t) return t.w and x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h end

  local fonts = {}
  local function font(px)
    px = max(6, math.floor(px + 0.5))
    if not fonts[px] then
      local ok, f = pcall(love.graphics.newFont, px)
      fonts[px] = ok and f or love.graphics.getFont()
    end
    return fonts[px]
  end

  -- ------- the emblems, drawn in lines about (cx, cy) with radius s

  local pts = {}
  local function burst(G, cx, cy, s, n, inner)
    for i = 0, n * 2 - 1 do
      local a = -pi / 2 + i * pi / n
      local rr = (i % 2 == 0) and s or s * inner
      pts[i * 2 + 1], pts[i * 2 + 2] = cx + rr * cos(a), cy + rr * sin(a)
    end
    for i = n * 4 + 1, #pts do pts[i] = nil end
    G.polygon("line", pts)
  end
  local function ball(G, cx, cy, s)
    G.circle("line", cx, cy, s, 32)
    G.line(cx - s, cy, cx - s * 0.32, cy)
    G.line(cx + s * 0.32, cy, cx + s, cy)
    G.circle("line", cx, cy, s * 0.32, 20)
  end
  -- a running figure as an outlined silhouette: its limbs as thick strokes in the colour, then the
  -- same strokes thinner in the button's face colour (bg), which leaves one outline round the whole
  local RUN_JOINTS = {
    -- the body and legs, the arms (pairs of points as fractions of s), the head
    { 0.22, -0.4, -0.06, 0.16 },                                 -- torso
    { -0.06, 0.16, 0.3, 0.42, 0.18, 0.86 },                      -- front leg
    { -0.06, 0.16, -0.4, 0.4, -0.78, 0.28 },                     -- back leg
    { 0.18, -0.3, 0.48, -0.08, 0.72, -0.34 },                    -- front arm
    { 0.16, -0.32, -0.18, -0.2, -0.46, 0.02 },                   -- back arm
  }
  local runPts = {}
  local function runFigure(G, cx, cy, s, widthK, extra)
    for _, j in ipairs(RUN_JOINTS) do
      local w = s * (j == RUN_JOINTS[1] and 0.34 or 0.24) * widthK + extra * 2
      G.setLineWidth(max(1, w))
      -- (one table for every limb, every frame: no garbage)
      for q = 1, #j do runPts[q] = (q % 2 == 1) and (cx + j[q] * s) or (cy + j[q] * s) end
      for q = #j + 1, #runPts do runPts[q] = nil end
      G.line(runPts)
      for q = 1, #j, 2 do G.circle("fill", cx + j[q] * s, cy + j[q + 1] * s, w / 2, 16) end
    end
    G.circle("fill", cx + 0.36 * s, cy - 0.72 * s, s * 0.21 + extra, 20)
  end
  local EMBLEM = {
    fight = function(G, cx, cy, s)
      -- the burst, and a ball right in its middle
      burst(G, cx, cy, s, 8, 0.66)
      ball(G, cx, cy, s * 0.4)
    end,
    pokemon = function(G, cx, cy, s) ball(G, cx, cy, s * 0.9) end,
    bag = function(G, cx, cy, s)
      local bw, bh = s * 1.4, s * 1.25
      G.rectangle("line", cx - bw / 2, cy - bh / 2 + s * 0.15, bw, bh, s * 0.3, s * 0.3)
      G.arc("line", "open", cx, cy - bh / 2 + s * 0.15, s * 0.35, pi, 2 * pi, 16)
      G.line(cx - bw / 2, cy + s * 0.05, cx + bw / 2, cy + s * 0.05)
      G.rectangle("line", cx - s * 0.2, cy - s * 0.05, s * 0.4, s * 0.28, s * 0.06, s * 0.06)
    end,
    run = function(G, cx, cy, s, bg)
      local r, g, b, a = G.getColor()
      local lw = G.getLineWidth()
      -- the outline (the colour, a stroke wider), then the face colour inside it
      runFigure(G, cx, cy, s, 1, lw)
      local f = bg or { 1, 1, 1 }
      G.setColor(f[1], f[2], f[3], 1)
      runFigure(G, cx, cy, s, 1, 0)
      G.setColor(r, g, b, a)
      G.setLineWidth(lw)
    end,
  }
  Pad.EMBLEM = EMBLEM

  -- ------- a button's face, textured: a rounded rect drawn by a shader - a lit gradient, a fine
  -- brushed grain, a gloss over its upper half, a bevel (lit along the top, shaded along the foot;
  -- pressed, turned over, with a shadow inside its top) and, where asked, a slanted corner in its
  -- colour. Plain fills stand in where the device has no shaders.
  --   Pad.face(G, x, y, w, h, rad, { dark, pressed, accent = rgb, corner = true, tint = 0..1 })
  local FACE_GLSL = [[
extern vec2 size;
extern number radius;
extern vec3 top;
extern vec3 bottom;
extern vec3 accent;
extern number pressed;
extern number corner;
extern number tint;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float sdRound(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = tc * size;
  vec2 c = size * 0.5;
  float d = sdRound(p - c, c, radius);
  float a = 1.0 - smoothstep(-0.8, 0.8, d);
  if (a <= 0.0) discard;
  float y = tc.y;
  vec3 col = mix(top, bottom, smoothstep(0.05, 1.0, y));
  col = mix(col, accent, tint * (0.35 + 0.65 * tc.x) * 0.5);
  // brushed: fine slanting lines and a grain
  float lines = sin((p.x + p.y * 0.55) * 1.3) * 0.5 + 0.5;
  float grain = hash(floor(p * 0.75));
  col *= 0.965 + 0.03 * lines + 0.035 * (grain - 0.5);
  // its corner in the colour, slanted, with a light seam along the cut
  if (corner > 0.5) {
    float k = tc.x + (1.0 - tc.y) * 0.0 + tc.y * 0.42;
    float cut = 0.3 - k;
    if (cut > 0.0) col = mix(col, accent * (1.0 - 0.25 * y), 0.92);
    col += (1.0 - smoothstep(0.0, 0.012, abs(cut))) * 0.35;
  }
  // a gloss over the upper half (not when pressed)
  col += (1.0 - smoothstep(0.0, 0.48, y)) * 0.12 * (1.0 - pressed);
  // the bevel: the band just inside the edge, light at the top and shade at the foot (turned over
  // when pressed)
  float band = 1.0 - clamp(-d / max(2.0, size.y * 0.07), 0.0, 1.0);
  float side = (y < 0.5) ? 1.0 : -1.0;
  col += band * side * mix(0.2, -0.28, pressed);
  col -= pressed * (1.0 - smoothstep(0.0, 0.22, y)) * 0.22;
  return vec4(clamp(col, 0.0, 1.0), a * color.a);
}
]]
  local faceShader, faceTexel, faceTried = nil, nil, false
  local function faceReady()
    if not faceTried then
      faceTried = true
      local G = love.graphics
      local ok, sh = pcall(G.newShader, FACE_GLSL)
      if ok then faceShader = sh end
      local okI, img = pcall(function()
        local d = love.image.newImageData(1, 1)
        d:setPixel(0, 0, 1, 1, 1, 1)
        return G.newImage(d)
      end)
      if okI then faceTexel = img end
    end
    return faceShader and faceTexel
  end
  local LIGHT_TOP, LIGHT_BOTTOM = { 1, 1, 1 }, { 0.82, 0.84, 0.89 }
  local DARK_TOP, DARK_BOTTOM = { 0.22, 0.22, 0.27 }, { 0.03, 0.03, 0.05 }
  local GREY = { 0.6, 0.6, 0.62 }
  local faceSize = { 0, 0 }   -- (reused: a table a call would be garbage every frame)
  -- the options as one reused table (a table literal at each call was garbage every frame):
  --   Pad.face(G, x, y, w, h, rad, Pad.faceOpts(dark, pressed, accent, corner, tint))
  local faceOpts = {}
  function Pad.faceOpts(dark, pressed, accent, corner, tint)
    faceOpts.dark, faceOpts.pressed, faceOpts.accent = dark or false, pressed or false, accent
    faceOpts.corner, faceOpts.tint, faceOpts.alpha = corner or false, tint or 0, nil
    return faceOpts
  end
  local NO_OPTS = {}
  local BALL_RED = { 0.9, 0.2, 0.3 }
  function Pad.face(G, x, y, w, h, rad, o)
    o = o or NO_OPTS
    if not faceReady() then
      if o.dark then G.setColor(0.05, 0.05, 0.06, 1) else G.setColor(1, 1, 1, 1) end
      G.rectangle("fill", x, y, w, h, rad, rad)
      return
    end
    local sh = faceShader
    faceSize[1], faceSize[2] = w, h
    sh:send("size", faceSize)
    sh:send("radius", min(rad, w / 2, h / 2))
    sh:send("top", o.dark and DARK_TOP or LIGHT_TOP)
    sh:send("bottom", o.dark and DARK_BOTTOM or LIGHT_BOTTOM)
    sh:send("accent", o.accent or GREY)
    sh:send("pressed", o.pressed and 1 or 0)
    sh:send("corner", o.corner and 1 or 0)
    sh:send("tint", o.tint or 0)
    G.setShader(sh)
    G.setColor(1, 1, 1, o.alpha or 1)
    G.draw(faceTexel, x, y, 0, w, h)
    G.setShader()
  end

  -- one pill: white (black when selected), the words, the emblem at its right end
  local function pill(G, t, item, selected, live, u)
    local rad = t.h / 2
    -- a soft shadow under it
    G.setColor(0, 0, 0, 0.25)
    G.rectangle("fill", t.x + 2 * u, t.y + 3 * u, t.w, t.h, rad, rad)
    Pad.face(G, t.x, t.y, t.w, t.h, rad, Pad.faceOpts(selected, false, item.rgb, false, selected and 0.25 or 0.12))
    local c = item.rgb
    -- the selected one keeps a thin rim in its colour, so it reads against the dark den
    if selected then
      G.setColor(c[1], c[2], c[3], 0.85)
      G.setLineWidth(max(1.5, t.h * 0.035))
      G.rectangle("line", t.x, t.y, t.w, t.h, rad, rad)
    end
    local s = t.h * 0.36
    local ex, ey = t.x + t.w - t.h * 0.62, t.y + t.h / 2
    G.setLineWidth(max(1, t.h * (selected and 0.06 or 0.05)))
    G.setLineJoin("bevel")
    local k = live and 1 or 0.45
    if selected then G.setColor(c[1], c[2], c[3], 1) else G.setColor(c[1], c[2], c[3], 0.85 * k) end
    EMBLEM[item.id](G, ex, ey, s, selected and { 0.05, 0.05, 0.06 } or { 1, 1, 1 })
    G.setLineWidth(1)
    local f = font(t.h * 0.44)
    G.setFont(f)
    local tx, ty = t.x + t.h * 0.36, t.y + (t.h - f:getHeight()) / 2
    if selected then G.setColor(1, 1, 1, 1)
    elseif live then G.setColor(0.08, 0.08, 0.1, 1)
    else G.setColor(0.6, 0.6, 0.62, 1) end
    -- (bold: the default face drawn twice, a pixel apart)
    G.print(item.word, tx, ty)
    G.print(item.word, tx + max(1, u * 0.8), ty)
  end

  -- the chevron at the selected pill's left: white with a black edge
  local function chevron(G, t, u)
    local hh = t.h * 0.34
    local x1 = t.x - t.h * 0.4
    local x2 = t.x + t.h * 0.02
    local cy = t.y + t.h / 2
    G.setLineJoin("miter")
    G.setColor(0, 0, 0, 1)
    G.setLineWidth(t.h * 0.2)
    G.line(x1, cy - hh, x2, cy, x1, cy + hh)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(t.h * 0.1)
    G.line(x1, cy - hh, x2, cy, x1, cy + hh)
    G.setLineWidth(1)
    G.setLineJoin("bevel")
  end

  -- the stack: pills of pw x ph, its foot at bottom, its right edge at right
  local function stack(G, right, bottom, pw, ph, pitch, r)
    local n = #Pad.ITEMS
    local top = bottom - ph - (n - 1) * pitch
    rset(where.panel, right - pw - ph * 0.45, top, pw + ph * 0.45, bottom - top)
    local cur = r and r.cmd and r.cmd.cursor or 1
    local u = ph / 92
    for i, item in ipairs(Pad.ITEMS) do
      local t = rset(where[item.id], right - pw, top + (i - 1) * pitch, pw, ph)
      -- (Bag greyed once the pouch is empty)
      local live = LIVE[item.id] and not (item.id == "bag" and r and r.cmd and r.cmd.bagEmpty)
      pill(G, t, item, i == cur, live, u)
    end
    chevron(G, where[Pad.ITEMS[cur].id], u)
  end

  -- ------- the moves (after Fight): r.cmd.moveList = { { name, typeName, rgb, pp, maxPp, eff }, ... }
  -- each a pill as the commands' (wider: MOVE_W), its type in a chip of the type's colour, the name,
  -- the PP at the right and how it does on the boss under the name; a Back tab above for touch

  Pad.MOVE_W = 0.42
  local EFF_WORD = { super = "Super effective", weak = "Not very effective", none = "No effect" }
  local EFF_RGB = { super = { 0.2, 0.75, 0.3 }, weak = { 0.55, 0.55, 0.6 }, none = { 0.9, 0.25, 0.25 } }

  local function movePill(G, t, mv, selected, u)
    local rad = t.h / 2
    G.setColor(0, 0, 0, 0.25)
    G.rectangle("fill", t.x + 2 * u, t.y + 3 * u, t.w, t.h, rad, rad)
    local c = mv.rgb or { 0.6, 0.6, 0.6 }
    Pad.face(G, t.x, t.y, t.w, t.h, rad, Pad.faceOpts(selected, false, c, false, selected and 0.25 or 0.1))
    if selected then
      G.setColor(c[1], c[2], c[3], 0.9)
      G.setLineWidth(max(1.5, t.h * 0.035))
      G.rectangle("line", t.x, t.y, t.w, t.h, rad, rad)
      G.setLineWidth(1)
    end
    -- (a Max form: the Dynamax red round it, glowing)
    if mv.max then
      local pulse = 0.65 + 0.35 * sin((love.timer and love.timer.getTime() or 0) * 5)
      G.setColor(0.95, 0.12, 0.3, 0.35 * pulse)
      G.setLineWidth(max(3, t.h * 0.12))
      G.rectangle("line", t.x, t.y, t.w, t.h, rad, rad)
      G.setColor(1, 0.3, 0.45, 0.95)
      G.setLineWidth(max(1.5, t.h * 0.04))
      G.rectangle("line", t.x, t.y, t.w, t.h, rad, rad)
      G.setLineWidth(1)
    end
    -- (a list row: a move - chip its type, `right` its PP - or the pouch's item / a target: `chip`
    -- its own words, `live` whether it can be picked)
    local live
    if mv.live ~= nil then live = mv.live else live = (mv.pp or 0) > 0 end
    -- the type chip
    local cw, ch = t.h * 1.05, t.h * 0.42
    local cx, cy = t.x + t.h * 0.3, t.y + (t.h - ch) / 2
    G.setColor(c[1], c[2], c[3], live and 1 or 0.5)
    G.rectangle("fill", cx, cy, cw, ch, ch / 2, ch / 2)
    local fc = font(ch * 0.62)
    G.setFont(fc)
    G.setColor(1, 1, 1, 1)
    local chip = mv.chip or ((mv.typeName or ""):sub(1, 1) .. (mv.typeName or ""):sub(2):lower())
    G.printf(chip, cx, cy + (ch - fc:getHeight()) / 2, cw, "center")
    -- the PP's width first: the name shrinks to fit before it
    local fp = font(t.h * 0.28)
    local ppText = mv.right or ("%d/%d"):format(mv.pp or 0, mv.maxPp or 0)
    local ppLeft = t.x + t.w - t.h * 0.42 - fp:getWidth(ppText)
    -- the name, and under it how it does on the boss
    local nx = cx + cw + t.h * 0.18
    local room = ppLeft - nx - t.h * 0.15
    local size = t.h * 0.36
    local fn = font(size)
    if fn:getWidth(mv.name or "?") > room then
      size = max(t.h * 0.22, size * room / fn:getWidth(mv.name or "?"))
      fn = font(size)
    end
    G.setFont(fn)
    if selected then G.setColor(1, 1, 1, 1) elseif live then G.setColor(0.08, 0.08, 0.1, 1) else G.setColor(0.6, 0.6, 0.62, 1) end
    local ny = t.y + t.h * 0.12
    G.print(mv.name or "?", nx, ny)
    G.print(mv.name or "?", nx + max(1, u * 0.8), ny)
    if mv.eff and EFF_WORD[mv.eff] then
      local e = EFF_RGB[mv.eff]
      G.setFont(font(t.h * 0.22))
      G.setColor(e[1], e[2], e[3], 1)
      G.print(EFF_WORD[mv.eff], nx, t.y + t.h * 0.6)
    end
    -- the PP
    G.setFont(fp)
    if selected then G.setColor(0.85, 0.85, 0.88, 1) else G.setColor(0.25, 0.25, 0.28, 1) end
    if not live then G.setColor(0.9, 0.25, 0.25, 1) end
    G.printf(ppText, t.x, t.y + (t.h - fp:getHeight()) / 2, t.w - t.h * 0.42, "right")
  end

  -- the Dynamax mark (assets/ui/icon_dynamax.png, 34 x 34), loaded once (false: not there, the drawn
  -- cloud stands in)
  local markImg = nil
  local function dynamaxMark()
    if markImg ~= nil then return markImg or nil end
    markImg = false
    local ok, img = pcall(function()
      local bytes = mod and mod.read and mod:read("assets/ui/icon_dynamax.png")
      if not bytes then return nil end
      local i = love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, "icon_dynamax.png")))
      i:setFilter("nearest", "nearest")
      return i
    end)
    if ok and img then markImg = img end
    return markImg or nil
  end
  Pad.dynamaxMark = dynamaxMark

  -- ------- the DYNAMAX button, Sword / Shield's: a hot-pink rim over a dark crimson band round a deep
  -- magenta face, the Dynamax mark, and the word in slanted heavy letters - pale pink at their top
  -- to hot pink at their foot, outlined dark crimson. On the main screen a round button (the mark
  -- above, the word across it, as the game's); on the second screen the same as a pill.

  Pad.DMAX_RGB = {
    rim = { 1, 0.24, 0.47 }, band = { 0.5, 0.03, 0.16 }, face = { 0.22, 0.02, 0.11 }, faceLit = { 0.36, 0.05, 0.2 },
    line = { 1, 0.45, 0.65 }, glow = { 1, 0.18, 0.45 }, ink = { 0.3, 0.0, 0.09 },
    top = { 1, 0.94, 0.96 }, foot = { 1, 0.36, 0.58 },
  }

  -- the word's gradient down its letters, by their vertices' y (LOVE hands text over transformed: the
  -- ends are sent in that space)
  local GRAD = [[
varying float ly;
#ifdef VERTEX
vec4 position(mat4 tp, vec4 vp) { ly = vp.y; return tp * vp; }
#endif
#ifdef PIXEL
extern float y0;
extern float y1;
extern vec3 c0;
extern vec3 c1;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float t = clamp((ly - y0) / max(1.0, y1 - y0), 0.0, 1.0);
  return vec4(mix(c0, c1, t), Texel(tex, tc).a * color.a);
}
#endif
]]
  local gradShader = nil
  local function grad()
    if gradShader == nil then
      local ok, s = pcall(love.graphics.newShader, GRAD)
      gradShader = ok and s or false
    end
    return gradShader or nil
  end

  -- "DYNAMAX" centred on (cx, cy), `size` px, at most `maxW` wide: slanted, heavy, outlined, graded
  function Pad.dynamaxWord(G, cx, cy, size, maxW, alpha)
    local C = Pad.DMAX_RGB
    local word = "DYNAMAX"
    local f = font(size)
    local slant = 0.2
    if maxW and f:getWidth(word) * 1.08 > maxW then f = font(size * maxW / (f:getWidth(word) * 1.08)) end
    G.setFont(f)
    local w, hh = f:getWidth(word), f:getHeight()
    local o = max(1, f:getHeight() * 0.07)
    G.push()
    G.translate(cx, cy)
    G.shear(-slant, 0)
    local x, y = -w / 2, -hh / 2
    -- the outline: the word all round in the ink, thick
    G.setColor(C.ink[1], C.ink[2], C.ink[3], alpha or 1)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }) do
      G.print(word, x + d[1] * o * 1.6, y + d[2] * o * 1.6)
      G.print(word, x + d[1] * o * 1.6 + o * 0.5, y + d[2] * o * 1.6)
    end
    -- the letters, heavy (twice, a hair apart), pale to hot pink down them
    local s = grad()
    if s then
      G.setShader(s)
      -- (LOVE transforms a text's vertices before the shader sees them: the ends in that space)
      local _, ya = G.transformPoint(0, y + hh * 0.25)
      local _, yb = G.transformPoint(0, y + hh * 0.85)
      s:send("y0", ya)
      s:send("y1", yb)
      s:send("c0", C.top)
      s:send("c1", C.foot)
      G.setColor(1, 1, 1, alpha or 1)
    else
      G.setColor(1, 0.75, 0.85, alpha or 1)
    end
    G.print(word, x, y)
    G.print(word, x + o * 0.5, y)
    G.setShader()
    G.pop()
  end

  -- the mark, `size` px across, centred on (cx, cy) (the drawn cloud without the picture)
  local function markAt(G, cx, cy, size, alpha)
    local img = dynamaxMark()
    if img then
      local iw = img:getWidth()
      local k = size / iw
      G.setColor(1, 1, 1, alpha or 1)
      G.draw(img, cx, cy, 0, k, k, iw / 2, img:getHeight() / 2)
    else
      local s = size * 0.18
      G.setColor(1, 1, 1, alpha or 1)
      G.circle("fill", cx - s, cy + s * 0.2, s, 12)
      G.circle("fill", cx, cy - s * 0.35, s * 1.15, 12)
      G.circle("fill", cx + s, cy + s * 0.2, s, 12)
    end
  end

  -- the second screen's: a pill, w x h at (x, y); lit (toggled on): glowing, brighter
  function Pad.drawDynamaxPill(G, x, y, w, h, on)
    local C = Pad.DMAX_RGB
    local t = love.timer and love.timer.getTime() or 0
    local rad = h / 2
    if on then
      local pulse = 0.55 + 0.45 * sin(t * 6)
      for k = 3, 1, -1 do
        local e = h * 0.1 * k
        G.setColor(C.glow[1], C.glow[2], C.glow[3], 0.16 * pulse)
        G.rectangle("fill", x - e, y - e, w + e * 2, h + e * 2, rad + e, rad + e)
      end
    end
    local dim = on and 1 or 0.82
    G.setColor(C.rim[1] * dim, C.rim[2] * dim, C.rim[3] * dim, 1)
    G.rectangle("fill", x, y, w, h, rad, rad)
    local b1 = h * 0.08
    G.setColor(C.band)
    G.rectangle("fill", x + b1, y + b1, w - b1 * 2, h - b1 * 2, rad - b1, rad - b1)
    local b2 = h * 0.16
    G.setColor(C.face)
    G.rectangle("fill", x + b2, y + b2, w - b2 * 2, h - b2 * 2, rad - b2, rad - b2)
    -- (a lighter top on the face, and a thin pink line inside the band)
    G.setColor(C.faceLit[1], C.faceLit[2], C.faceLit[3], 0.7)
    G.rectangle("fill", x + b2 + h * 0.1, y + b2 + h * 0.04, w - b2 * 2 - h * 0.2, (h - b2 * 2) * 0.38, (h - b2 * 2) * 0.19, (h - b2 * 2) * 0.19)
    G.setColor(C.line[1], C.line[2], C.line[3], on and 0.9 or 0.55)
    G.setLineWidth(max(1, h * 0.03))
    G.rectangle("line", x + b2, y + b2, w - b2 * 2, h - b2 * 2, rad - b2, rad - b2)
    G.setLineWidth(1)
    markAt(G, x + h * 0.62, y + h / 2, h * 0.78, on and 1 or 0.85)
    Pad.dynamaxWord(G, x + h * 1.05 + (w - h * 1.35) / 2, y + h / 2, h * 0.52, w - h * 1.45, on and 1 or 0.9)
  end

  -- the main screen's: a round button of radius R about (cx, cy) - the mark in its top half, the word
  -- across its middle and past its sides
  function Pad.drawDynamaxRound(G, cx, cy, R, on)
    local C = Pad.DMAX_RGB
    local t = love.timer and love.timer.getTime() or 0
    if on then
      local pulse = 0.55 + 0.45 * sin(t * 6)
      for k = 3, 1, -1 do
        G.setColor(C.glow[1], C.glow[2], C.glow[3], 0.15 * pulse)
        G.circle("fill", cx, cy, R * (1 + 0.1 * k), 48)
      end
    end
    local dim = on and 1 or 0.82
    G.setColor(C.rim[1] * dim, C.rim[2] * dim, C.rim[3] * dim, 1)
    G.circle("fill", cx, cy, R, 48)
    G.setColor(C.band)
    G.circle("fill", cx, cy, R * 0.9, 48)
    -- the face: darker at its edge, lit toward its middle
    for k = 0, 4 do
      local u = k / 4
      G.setColor(C.face[1] + (C.faceLit[1] - C.face[1]) * u, C.face[2] + (C.faceLit[2] - C.face[2]) * u,
        C.face[3] + (C.faceLit[3] - C.face[3]) * u, 1)
      G.circle("fill", cx, cy, R * (0.8 - 0.42 * u), 48)
    end
    G.setColor(C.line[1], C.line[2], C.line[3], on and 0.9 or 0.55)
    G.setLineWidth(max(1, R * 0.035))
    G.circle("line", cx, cy, R * 0.8, 48)
    G.setLineWidth(1)
    markAt(G, cx, cy - R * 0.4, R * 0.72, on and 1 or 0.9)
    Pad.dynamaxWord(G, cx, cy + R * 0.18, R * 0.46, R * 2.5, on and 1 or 0.92)
  end

  local function moveStack(G, right, bottom, pw, ph, pitch, r)
    local list = r.cmd.moveList or {}
    local n = max(1, #list)
    local top = bottom - ph - (n - 1) * pitch
    -- the Back tab above them
    local bw, bh = ph * 1.6, ph * 0.5
    local b = rset(where.back, right - bw, top - bh - ph * 0.22, bw, bh)
    G.setColor(0.08, 0.08, 0.1, 0.92)
    G.rectangle("fill", b.x, b.y, b.w, b.h, bh / 2, bh / 2)
    G.setFont(font(bh * 0.55))
    G.setColor(1, 1, 1, 1)
    G.printf("Back", b.x, b.y + (bh - font(bh * 0.55):getHeight()) / 2, b.w, "center")
    -- DYNAMAX, a round button left of it, while this member holds the Dynamax Energy (lit once on)
    local left, ptop = right - pw - ph * 0.45, b.y
    if r.cmd.canDmax then
      local R = ph * 0.82
      local cx, cy = b.x - R * 1.35, b.y + bh - R * 0.9
      local d = rset(where.dynamax, cx - R * 1.25, cy - R, R * 2.5, R * 2)
      Pad.drawDynamaxRound(G, cx, cy, R, r.cmd.dmax == true)
      left, ptop = min(left, d.x), min(ptop, d.y)
    else
      rset(where.dynamax, 0, 0, 0, 0)
    end
    rset(where.panel, left, ptop, right - left, bottom - ptop)
    local cur = r.cmd.cursor or 1
    local u = ph / 92
    for i = 1, 4 do
      local t = where["move" .. i]
      if list[i] then
        rset(t, right - pw, top + (i - 1) * pitch, pw, ph)
        movePill(G, t, list[i], i == cur, u)
      else
        rset(t, 0, 0, 0, 0)
      end
    end
    if list[cur] then chevron(G, where["move" .. cur], u) end
  end

  -- on the main window, in the lower right
  function Pad.draw(G, w, h, r)
    local L = Pad.LOOK
    G.push("all")
    if r and r.cmd and r.cmd.menu and r.cmd.menu ~= "main" then
      moveStack(G, w - h * L.EDGE, h - h * L.EDGE, h * Pad.MOVE_W, h * L.H, h * L.PITCH, r)
    else
      stack(G, w - h * L.EDGE, h - h * L.EDGE, h * L.W, h * L.H, h * L.PITCH, r)
    end
    G.pop()
    return where.panel
  end

  -- filling a whole screen (the second display's frame): the stack centred and as large as fits
  function Pad.drawFull(G, w, h, r)
    G.push("all")
    G.setColor(0.08, 0.09, 0.12, 1)
    G.rectangle("fill", 0, 0, w, h)
    local L = Pad.LOOK
    local k = min(h * 0.9 / (L.H + 3 * L.PITCH), w * 0.8 / (L.W + L.H * 0.45))
    local pw, ph, pitch = L.W * k, L.H * k, L.PITCH * k
    local total = ph + 3 * pitch
    if r and r.cmd and r.cmd.menu and r.cmd.menu ~= "main" then
      moveStack(G, (w + pw * Pad.MOVE_W / L.W + ph * 0.45) / 2, (h + total) / 2, pw * Pad.MOVE_W / L.W, ph, pitch, r)
    else
      stack(G, (w + pw + ph * 0.45) / 2, (h + total) / 2, pw, ph, pitch, r)
    end
    G.pop()
  end

  -- (a list menu - "moves", "items", "target": "move1".."move4" for its rows, or "back")
  function Pad.hit(x, y, menu)
    if not inRect(x, y, where.panel) then return nil end
    if menu and menu ~= "main" then
      if inRect(x, y, where.back) then return "back" end
      if inRect(x, y, where.dynamax) then return "dynamax" end
      for i = 1, 4 do if inRect(x, y, where["move" .. i]) then return "move" .. i end end
      return "panel"
    end
    for _, item in ipairs(Pad.ITEMS) do
      if inRect(x, y, where[item.id]) then return item.id end
    end
    return "panel"
  end

  -- ------- the second screen: the commands as a quad (Kanto Gear's shape, the raid's own buttons)
  -- over a background of its own - a deep navy to Dynamax magenta, light streaks, a faint hexagon
  -- grid and the band's ring. A header names who is choosing; the four commands (or the moves, the
  -- pouch, the targets, Yes / No) fill a 2 x 2 grid of large buttons, each its emblem over its words.
  -- The selected button (and one held under a finger) is pressed in: lower, its shadow gone, a dark
  -- inner edge along its top.
  --   Pad.drawSecond(G, w, h, r, held) ; Pad.hitSecond(x, y) -> an id as Pad.hit's, or nil

  local sWhere = { cells = {}, back = {}, dynamax = {} }
  Pad.sWhere = sWhere

  local bgMesh, bgW, bgH = nil, 0, 0
  local function secondBackground(G, w, h, t)
    if not bgMesh or bgW ~= w or bgH ~= h then
      bgW, bgH = w, h
      local ok, m = pcall(G.newMesh, {
        { 0, 0, 0, 0, 0.05, 0.06, 0.13, 1 }, { w, 0, 0, 0, 0.07, 0.07, 0.16, 1 },
        { w, h, 0, 0, 0.32, 0.04, 0.22, 1 }, { 0, h, 0, 0, 0.18, 0.04, 0.2, 1 } }, "fan", "static")
      bgMesh = ok and m or false
    end
    if bgMesh then
      G.setColor(1, 1, 1, 1)
      G.draw(bgMesh)
    else
      G.setColor(0.08, 0.06, 0.15, 1)
      G.rectangle("fill", 0, 0, w, h)
    end
    -- the band's ring, large and faint, low on the right
    G.setLineWidth(max(2, h * 0.03))
    G.setColor(1, 0.2, 0.45, 0.08)
    G.circle("line", w * 0.82, h * 0.95, h * 0.55, 64)
    G.setLineWidth(max(1, h * 0.008))
    G.setColor(1, 0.35, 0.6, 0.12)
    G.circle("line", w * 0.82, h * 0.95, h * 0.42, 64)
    -- a hexagon grid, fading toward the top
    local cell = h * 0.07
    G.setLineWidth(1)
    for row = 0, math.ceil(h / (cell * 0.87)) do
      local y = row * cell * 0.87
      local a = 0.06 * (y / h)
      if a > 0.005 then
        G.setColor(1, 0.4, 0.7, a)
        for col = -1, math.ceil(w / (cell * 1.5)) do
          local x = (col + (row % 2) * 0.5) * cell * 1.5
          for i = 0, 5 do
            local a0, a1 = i * pi / 3, (i + 1) * pi / 3
            G.line(x + cos(a0) * cell * 0.5, y + sin(a0) * cell * 0.5, x + cos(a1) * cell * 0.5, y + sin(a1) * cell * 0.5)
          end
        end
      end
    end
    -- light streaks, slanting and drifting
    G.setBlendMode("add")
    for i = 0, 6 do
      local x0 = ((i * 0.19 + (t or 0) * 0.02) % 1.3 - 0.15) * w
      G.setColor(1, 0.45, 0.75, 0.035 + 0.02 * (i % 3))
      G.polygon("fill", x0, 0, x0 + w * 0.05, 0, x0 - w * 0.2, h, x0 - w * 0.25, h)
    end
    G.setBlendMode("alpha")
  end

  -- a large button: rounded, a light face lit from above with a soft shadow; pressed (only while a
  -- finger or button holds it), it sits lower with no shadow and a dark edge inside its top; sel (the
  -- cursor on it) turns it black with a rim in its colour, standing up
  local function quadButton(G, t, rgb, sel, pressed, live, drawIcon, word, sub, iconY)
    local rad = min(t.w, t.h) * 0.16
    local depth = t.h * 0.045
    local down = pressed and depth or 0
    local x, y, w, h = t.x, t.y + down, t.w, t.h
    if down == 0 then
      G.setColor(0, 0, 0, 0.35)
      G.rectangle("fill", x + depth * 0.4, y + depth, w, h, rad, rad)
    end
    -- the face (textured; pressed, its bevel turned over and a shadow inside its top)
    local c = rgb or { 0.6, 0.6, 0.6 }
    Pad.face(G, x, y, w, h, rad, Pad.faceOpts(sel, pressed, c, true, sel and 0.2 or 0.06))
    G.setColor(c[1], c[2], c[3], sel and 1 or 0.9)
    G.setLineWidth(max(2, h * 0.025))
    G.rectangle("line", x + h * 0.012, y + h * 0.012, w - h * 0.024, h - h * 0.024, rad, rad)
    -- the emblem, the words (and a line under them)
    local k = live and 1 or 0.45
    if drawIcon then
      G.setLineWidth(max(1.5, h * 0.03))
      G.setLineJoin("bevel")
      G.setColor(c[1], c[2], c[3], k)
      drawIcon(G, x + w / 2, y + h * (iconY or 0.4), h * 0.22, sel and { 0.07, 0.07, 0.09 } or { 0.95, 0.95, 0.96 })
    end
    -- (words alone: as large as the button's height allows, held in by its width)
    local f = font(drawIcon and h * 0.17 or (sub and h * 0.2 or min(h * 0.34, w * 0.06)))
    G.setFont(f)
    if sel then G.setColor(1, 1, 1, 1) elseif live then G.setColor(0.08, 0.08, 0.1, 1) else G.setColor(0.6, 0.6, 0.62, 1) end
    local ty = drawIcon and (iconY and (y + h * 0.5 - f:getHeight() / 2) or (y + h * 0.7))
      or (y + h * (sub and 0.28 or 0.5) - f:getHeight() / 2)
    local word2 = word or "?"
    if f:getWidth(word2) > w * 0.9 then
      f = font(h * 0.17 * w * 0.9 / f:getWidth(word2))
      G.setFont(f)
    end
    G.printf(word2, x, ty, w, "center")
    G.printf(word2, x + 1, ty, w, "center")
    if sub then
      local fs = font(h * 0.13)
      G.setFont(fs)
      if sel then G.setColor(0.8, 0.8, 0.85, 1) else G.setColor(0.3, 0.3, 0.35, 1) end
      G.printf(sub, x, y + h * 0.62, w, "center")
    end
    G.setLineWidth(1)
  end

  -- a chip of the move's type above its words
  local function typeChip(rgb, name)
    return function(G, cx, cy, s, _)
      local cw, ch = s * 2.6, s * 0.95
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.rectangle("fill", cx - cw / 2, cy - ch / 2, cw, ch, ch / 2, ch / 2)
      local f = font(ch * 0.62)
      G.setFont(f)
      G.setColor(1, 1, 1, 1)
      G.printf(name or "", cx - cw / 2, cy - f:getHeight() / 2, cw, "center")
    end
  end

  function Pad.drawSecond(G, w, h, r, held)
    G.push("all")
    secondBackground(G, w, h, r and r.t or 0)
    -- the header: who is choosing (or what is going on)
    local hh = h * 0.13
    G.setColor(0, 0, 0, 0.55)
    G.rectangle("fill", 0, 0, w, hh)
    G.setColor(1, 0.25, 0.5, 1)
    G.rectangle("fill", 0, hh - h * 0.008, w, h * 0.008)
    local fh = font(hh * 0.42)
    G.setFont(fh)
    G.setColor(1, 1, 1, 1)
    local c = r and r.cmd
    local cmdUp = r and r.phase == "command" and c and not r.say
    local ask = r and (r.phase == "after" or r.phase == "leaveq") and r.ask and r.ask.kind == "yesno"
    local catchUp = r and r.phase == "catch" and c and (c.menu == "catchq" or c.menu == "ballbox")
    local title
    if cmdUp then
      local m = c.actor and r.members and r.members[c.actor]
      local nm = m and m.b and m.b.name or "your Pok\195\169mon"
      -- (the moves need no title: the grid says what it is)
      if c.menu == "moves" then title = ""
      elseif c.menu == "items" then title = "Choose an item"
      elseif c.menu == "target" then
        local mv = c.moveSlot and m and m.b and m.b.moves[c.moveSlot]
        title = mv and ("Use %s on whom?"):format(mv.name) or "Use it on whom?"
      else title = ("What will %s do?"):format(nm) end
    elseif ask then title = r.phase == "leaveq" and "Leave the den?" or "Yes or no?"
    elseif catchUp then
      title = c.menu == "ballbox" and "Choose a Pok\195\169 Ball" or "Will you catch it?"
    else title = "Max Raid Battle" end
    G.print(title, h * 0.04, (hh - fh:getHeight()) / 2)
    for i = #sWhere.cells, 1, -1 do sWhere.cells[i] = nil end
    rset(sWhere.back, 0, 0, 0, 0)
    rset(sWhere.dynamax, 0, 0, 0, 0)
    local pad = h * 0.045
    local gx, gy, gw, gh = pad, hh + pad, w - pad * 2, h - hh - pad * 2
    local cw, ch = (gw - pad) / 2, (gh - pad) / 2
    local function cell(i) return gx + ((i - 1) % 2) * (cw + pad), gy + math.floor((i - 1) / 2) * (ch + pad) end
    if catchUp and c.menu == "catchq" then
      -- Catch / Don't Catch: two wide buttons
      local bh = (gh - pad) / 2
      local balls = c.balls or {}
      local rows = { { id = "catch", word = "Catch", rgb = { 0.93, 0.18, 0.42 }, icon = EMBLEM.pokemon, live = #balls > 0 },
        { id = "leave", word = "Don't Catch", rgb = { 0.55, 0.55, 0.6 }, live = true } }
      for i, row in ipairs(rows) do
        local t = { x = gx, y = gy + (i - 1) * (bh + pad), w = gw, h = bh, id = row.id }
        sWhere.cells[i] = t
        quadButton(G, t, row.rgb, c.cursor == i, held == row.id, row.live, row.icon, row.word)
      end
    elseif catchUp then
      -- the ball box: < the ball (its icon, name, how many) >, its words, Use
      local balls = c.balls or {}
      local bl = balls[c.ball or 1]
      local bw2, bh2 = hh * 2.2, hh * 0.66
      local b = rset(sWhere.back, w - bw2 - h * 0.03, (hh - bh2) / 2, bw2, bh2)
      Pad.face(G, b.x, b.y + (held == "back" and bh2 * 0.06 or 0), b.w, b.h, bh2 / 2, Pad.faceOpts(false, held == "back"))
      local fb = font(bh2 * 0.5)
      G.setFont(fb)
      G.setColor(0.08, 0.08, 0.1, 1)
      G.printf("Back", b.x, b.y + (bh2 - fb:getHeight()) / 2 + (held == "back" and bh2 * 0.06 or 0), b.w, "center")
      -- the arrows and the ball between them
      local rowH = gh * 0.42
      local aw = rowH * 0.62
      local arrows = { { id = "left", x = gx }, { id = "right", x = gx + gw - aw } }
      for i, a in ipairs(arrows) do
        local t = { x = a.x, y = gy, w = aw, h = rowH, id = a.id }
        sWhere.cells[#sWhere.cells + 1] = t
        local down = held == a.id and rowH * 0.045 or 0
        if down == 0 then
          G.setColor(0, 0, 0, 0.35)
          G.rectangle("fill", t.x + 3, t.y + 5, t.w, t.h, aw * 0.2, aw * 0.2)
        end
        Pad.face(G, t.x, t.y + down, t.w, t.h, aw * 0.2, Pad.faceOpts(false, held == a.id))
        local cx, cy, sz = t.x + t.w / 2, t.y + down + t.h / 2, aw * 0.22
        G.setColor(0.1, 0.1, 0.12, 1)
        if i == 1 then G.polygon("fill", cx - sz, cy, cx + sz * 0.7, cy - sz * 1.1, cx + sz * 0.7, cy + sz * 1.1)
        else G.polygon("fill", cx + sz, cy, cx - sz * 0.7, cy - sz * 1.1, cx - sz * 0.7, cy + sz * 1.1) end
      end
      local px, pw2 = gx + aw + pad, gw - (aw + pad) * 2
      Pad.face(G, px, gy, pw2, rowH, rowH * 0.12, Pad.faceOpts(true, false, bl and bl.rgb or BALL_RED, false, 0.15))
      if bl then
        local is = rowH * 0.42
        if Pad.itemIcon then Pad.itemIcon(G, bl.item, px + pw2 / 2 - is / 2, gy + rowH * 0.08, is, bl.rgb) end
        local nm = bl.name or "?"
        if (bl.n or 1) > 1 and not nm:match("s$") then nm = nm .. "s" end
        local fn = font(rowH * 0.17)
        G.setFont(fn)
        G.setColor(1, 1, 1, 1)
        G.printf(nm, px, gy + rowH * 0.56, pw2, "center")
        local fc = font(rowH * 0.13)
        G.setFont(fc)
        G.setColor(0.8, 0.8, 0.85, 1)
        G.printf("\195\151" .. tostring(bl.n or 0) .. ("   %d of %d"):format(c.ball or 1, #balls), px, gy + rowH * 0.78, pw2, "center")
        -- its words
        local dy = gy + rowH + pad * 0.6
        local dh = gh * 0.3
        G.setColor(1, 1, 1, 0.92)
        G.rectangle("fill", gx, dy, gw, dh, dh * 0.12, dh * 0.12)
        local fd = font(dh * 0.17)
        G.setFont(fd)
        G.setColor(0.1, 0.1, 0.12, 1)
        G.printf(bl.desc or "", gx + dh * 0.15, dy + dh * 0.12, gw - dh * 0.3, "left")
      end
      -- Use
      local uy = gy + rowH + pad * 1.2 + gh * 0.3
      local t = { x = gx + gw * 0.15, y = uy, w = gw * 0.7, h = gy + gh - uy, id = "use" }
      sWhere.cells[#sWhere.cells + 1] = t
      quadButton(G, t, { 0.93, 0.18, 0.42 }, true, held == "use", bl ~= nil, nil, "Use")
    elseif cmdUp and c.menu == "main" then
      -- Fight large across the top; Bag and Run side by side under it
      for i, item in ipairs(Pad.ITEMS) do
        local x, y, ww = gx, gy, gw
        if i > 1 then x, y = cell(i + 1); ww = cw end
        local t = { x = x, y = y, w = ww, h = ch, id = item.id }
        sWhere.cells[i] = t
        local live = LIVE[item.id] and not (item.id == "bag" and c.bagEmpty)
        quadButton(G, t, item.rgb, c.cursor == i, held == item.id, live, EMBLEM[item.id], item.word)
      end
    elseif cmdUp or ask then
      -- a list: the moves (type chip, name, PP), the pouch, the targets, Yes / No
      local list = c and c.moveList or {}
      for i = 1, min(4, #list) do
        local mv = list[i]
        local x, y = cell(i)
        local t = { x = x, y = y, w = cw, h = ch, id = "move" .. i }
        sWhere.cells[i] = t
        local live
        if mv.live ~= nil then live = mv.live else live = (mv.pp or 0) > 0 end
        local sub = mv.right or (mv.maxPp and ("PP %d/%d"):format(mv.pp or 0, mv.maxPp or 0)) or nil
        local icon = nil
        if mv.typeName and not mv.chip then
          icon = typeChip(mv.rgb or { 0.6, 0.6, 0.6 }, (mv.typeName:sub(1, 1) .. mv.typeName:sub(2):lower()))
        end
        local subIn = nil
        if not icon then subIn = sub end
        quadButton(G, t, mv.rgb, c.cursor == i, held == t.id, live, icon, mv.name, subIn, icon and 0.24 or nil)
        if mv.max then
          -- (a Max form: the Dynamax red round it)
          local down = held == t.id and ch * 0.045 or 0
          local rad = min(t.w, t.h) * 0.16
          local pulse = 0.65 + 0.35 * sin((r and r.t or 0) * 5)
          G.setColor(0.95, 0.12, 0.3, 0.3 * pulse)
          G.setLineWidth(max(3, ch * 0.06))
          G.rectangle("line", x, y + down, cw, ch, rad, rad)
          G.setColor(1, 0.3, 0.45, 1)
          G.setLineWidth(max(2, ch * 0.02))
          G.rectangle("line", x, y + down, cw, ch, rad, rad)
          G.setLineWidth(1)
        end
        if icon then
          -- a move: its PP, and how it does on the boss, under its name
          local down = held == t.id and ch * 0.045 or 0
          local fs = font(ch * 0.12)
          G.setFont(fs)
          if c.cursor == i then G.setColor(0.8, 0.8, 0.85, 1) else G.setColor(0.3, 0.3, 0.35, 1) end
          if not live then G.setColor(0.9, 0.25, 0.25, 1) end
          if sub then G.printf(sub, x, y + down + ch * 0.66, cw, "center") end
          local EW = { super = "Super effective", weak = "Not very effective", none = "No effect" }
          local ER = { super = { 0.2, 0.75, 0.3 }, weak = { 0.55, 0.55, 0.6 }, none = { 0.9, 0.25, 0.25 } }
          if mv.eff and EW[mv.eff] then
            local e = ER[mv.eff]
            G.setFont(font(ch * 0.1))
            G.setColor(e[1], e[2], e[3], 1)
            G.printf(EW[mv.eff], x, y + down + ch * 0.8, cw, "center")
          end
        end
      end
      if not ask then
        -- Back, in the header's right end
        local bw, bh = hh * 2.2, hh * 0.66
        local b = rset(sWhere.back, w - bw - h * 0.03, (hh - bh) / 2, bw, bh)
        G.setColor(held == "back" and 0.75 or 1, held == "back" and 0.75 or 1, held == "back" and 0.78 or 1, 1)
        G.rectangle("fill", b.x, b.y + (held == "back" and bh * 0.06 or 0), b.w, b.h, bh / 2, bh / 2)
        local fb = font(bh * 0.5)
        G.setFont(fb)
        G.setColor(0.08, 0.08, 0.1, 1)
        G.printf("Back", b.x, b.y + (bh - fb:getHeight()) / 2 + (held == "back" and bh * 0.06 or 0), b.w, "center")
        -- DYNAMAX left of it, while this member holds the Dynamax Energy
        if c and c.menu == "moves" and c.canDmax then
          -- (in the room between the title and Back)
          local titleEnd = h * 0.04 + fh:getWidth(title) + h * 0.03
          local dh = hh * 0.82
          local dw = min(dh * 4.4, b.x - h * 0.03 - titleEnd)
          local d = rset(sWhere.dynamax, b.x - dw - h * 0.03, (hh - dh) / 2, dw, dh)
          Pad.drawDynamaxPill(G, d.x, d.y + (held == "dynamax" and dh * 0.05 or 0), d.w, d.h, c.dmax == true)
        end
      end
    else
      -- between commands: the four and how they stand
      local fm = font(h * 0.05)
      for i = 1, 4 do
        local m = r and r.members and r.members[i]
        local x, y = cell(i)
        G.setColor(1, 1, 1, 0.08)
        G.rectangle("fill", x, y, cw, ch, ch * 0.12, ch * 0.12)
        if m and m.b then
          G.setFont(fm)
          G.setColor(1, 1, 1, 0.9)
          G.printf(m.b.name or "?", x, y + ch * 0.3, cw, "center")
          local most = max(1, tonumber(m.b.mon and m.b.mon.maxHp) or 1)
          local f = max(0, min(1, (m.b.dispHp or m.b.mon.hp or 0) / most))
          local bx, by, bw2, bh2 = x + cw * 0.12, y + ch * 0.6, cw * 0.76, ch * 0.08
          G.setColor(0, 0, 0, 0.5)
          G.rectangle("fill", bx, by, bw2, bh2, bh2 / 2, bh2 / 2)
          if f > 0.5 then G.setColor(0.3, 0.85, 0.4, 1) elseif f > 0.2 then G.setColor(0.95, 0.75, 0.2, 1) else G.setColor(0.9, 0.25, 0.25, 1) end
          G.rectangle("fill", bx, by, bw2 * f, bh2, bh2 / 2, bh2 / 2)
        end
      end
    end
    G.pop()
  end

  -- the D-pad on the second screen moves by where the buttons are, not down a list: the commands
  -- are Fight across the top (1) over Bag (2) and Run (3); a list (moves, the pouch, whom, Yes / No)
  -- fills a 2 x 2 grid in reading order (1 2 / 3 4). A press toward no button stays.
  function Pad.secondMove(menu, cursor, n, dir)
    cursor = cursor or 1
    if menu == "main" then
      if dir == "up" then return 1
      elseif dir == "down" then return cursor == 1 and 2 or cursor
      elseif dir == "left" then return cursor == 3 and 2 or cursor
      elseif dir == "right" then return cursor == 2 and 3 or cursor end
      return cursor
    end
    local col, row = (cursor - 1) % 2, math.floor((cursor - 1) / 2)
    local to = cursor
    if dir == "left" and col == 1 then to = cursor - 1
    elseif dir == "right" and col == 0 then to = cursor + 1
    elseif dir == "up" and row == 1 then to = cursor - 2
    elseif dir == "down" and row == 0 then to = cursor + 2 end
    if to < 1 or to > (n or 4) then return cursor end
    return to
  end

  function Pad.hitSecond(x, y)
    if inRect(x, y, sWhere.back) then return "back" end
    if inRect(x, y, sWhere.dynamax) then return "dynamax" end
    for _, t in ipairs(sWhere.cells) do
      if inRect(x, y, t) then return t.id end
    end
    return nil
  end

  return Pad
end
