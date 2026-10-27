-- The battle pad: Sword / Shield's command stack - Fight, Pokemon, Bag, Run - as pills down the main
-- window's lower right. Each is white with black words and its emblem in colour at its right end;
-- the selected one is black with white words and a brighter emblem, and a white chevron points at
-- it from the left. With BATTLE PAD on the second screen it is drawn into that display's frame
-- instead (Pad.drawFull). Pokemon shows the summary (no switching in a Max Raid).
--   Pad.draw(G, w, h, r) -> the stack's rect (window pixels) ; Pad.drawFull(G, w, h, r)
--   Pad.hit(x, y) -> "fight" | "pokemon" | "bag" | "run" | "panel" | nil (against the last draw)
--   Pad.ITEMS (the order) ; Pad.live(id)

return function(mod, deps)
  local Pad = {}
  local max, min, cos, sin, pi = math.max, math.min, math.cos, math.sin, math.pi

  -- the commands, top to bottom: id, words, the emblem's colour
  Pad.ITEMS = {
    { id = "fight", word = "Fight", rgb = { 0.93, 0.18, 0.42 } },
    { id = "pokemon", word = "Pok\195\169mon", rgb = { 0.33, 0.8, 0.52 } },
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
    move1 = {}, move2 = {}, move3 = {}, move4 = {}, back = {} }
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
  local EMBLEM = {
    fight = function(G, cx, cy, s)
      burst(G, cx, cy, s, 8, 0.62)
      ball(G, cx + s * 0.05, cy + s * 0.05, s * 0.36)
    end,
    pokemon = function(G, cx, cy, s) ball(G, cx, cy, s * 0.9) end,
    bag = function(G, cx, cy, s)
      local bw, bh = s * 1.4, s * 1.25
      G.rectangle("line", cx - bw / 2, cy - bh / 2 + s * 0.15, bw, bh, s * 0.3, s * 0.3)
      G.arc("line", "open", cx, cy - bh / 2 + s * 0.15, s * 0.35, pi, 2 * pi, 16)
      G.line(cx - bw / 2, cy + s * 0.05, cx + bw / 2, cy + s * 0.05)
      G.rectangle("line", cx - s * 0.2, cy - s * 0.05, s * 0.4, s * 0.28, s * 0.06, s * 0.06)
    end,
    run = function(G, cx, cy, s)
      G.circle("line", cx + s * 0.35, cy - s * 0.65, s * 0.2, 16)
      G.line(cx + s * 0.2, cy - s * 0.35, cx - s * 0.15, cy + s * 0.2)          -- the body
      G.line(cx - s * 0.15, cy + s * 0.2, cx + s * 0.35, cy + s * 0.55, cx + s * 0.25, cy + s * 0.95)
      G.line(cx - s * 0.15, cy + s * 0.2, cx - s * 0.55, cy + s * 0.45, cx - s * 0.85, cy + s * 0.35)
      G.line(cx + s * 0.1, cy - s * 0.2, cx + s * 0.55, cy - s * 0.05, cx + s * 0.75, cy - s * 0.35)
      G.line(cx + s * 0.1, cy - s * 0.2, cx - s * 0.3, cy - s * 0.3, cx - s * 0.5, cy - s * 0.05)
      for k = 0, 2 do                                                             -- speed lines
        local y = cy - s * 0.4 + k * s * 0.3
        G.line(cx - s * 1.0, y, cx - s * 0.65 + k * s * 0.08, y)
      end
    end,
  }

  -- one pill: white (black when selected), the words, the emblem at its right end
  local function pill(G, t, item, selected, live, u)
    local rad = t.h / 2
    -- a soft shadow under it
    G.setColor(0, 0, 0, 0.25)
    G.rectangle("fill", t.x + 2 * u, t.y + 3 * u, t.w, t.h, rad, rad)
    if selected then G.setColor(0.05, 0.05, 0.06, 1) else G.setColor(1, 1, 1, 1) end
    G.rectangle("fill", t.x, t.y, t.w, t.h, rad, rad)
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
    EMBLEM[item.id](G, ex, ey, s)
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
    if selected then G.setColor(0.05, 0.05, 0.06, 1) else G.setColor(1, 1, 1, 1) end
    G.rectangle("fill", t.x, t.y, t.w, t.h, rad, rad)
    local c = mv.rgb or { 0.6, 0.6, 0.6 }
    if selected then
      G.setColor(c[1], c[2], c[3], 0.9)
      G.setLineWidth(max(1.5, t.h * 0.035))
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
    rset(where.panel, right - pw - ph * 0.45, b.y, pw + ph * 0.45, bottom - b.y)
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
      for i = 1, 4 do if inRect(x, y, where["move" .. i]) then return "move" .. i end end
      return "panel"
    end
    for _, item in ipairs(Pad.ITEMS) do
      if inRect(x, y, where[item.id]) then return item.id end
    end
    return "panel"
  end

  return Pad
end
