-- The command phase's HUD, after Sword / Shield's: the four in the order they choose down the top
-- left (each its party icon, a thought bubble while it waits or a tick once its command is in, its
-- HP), and the one choosing now in the lower left (its icon, name and gender, level, HP bar and
-- numbers, the EXP bar), on a white panel with a slanted right edge.
--   Bh.drawOrder(G, w, h, members, cmd, t) ; Bh.drawRows(G, w, h, rows, t) (the turn's) ;
--   Bh.drawPanel(G, w, h, m, foot)  (foot: its bottom edge, h by default)
--   members[i].info = { name, level, hp, maxHp, gender ("M" / "F" / ""), exp (0..1), icon }

return function(mod, deps)
  local Bh = {}
  local max, min, floor, sin = math.max, math.min, math.floor, math.sin

  -- sizes in the window's height, measured off a 1784 x 998 capture
  Bh.ORDER = { TOP = 0.025, W = 0.23, H = 0.078, PITCH = 0.097, NOW = 0.02 }
  Bh.PANEL = { H = 0.138, W = 0.556, SLANT = 0.045 }

  local fonts = {}
  local function font(px)
    px = max(6, floor(px + 0.5))
    if not fonts[px] then
      local ok, f = pcall(love.graphics.newFont, px)
      fonts[px] = ok and f or love.graphics.getFont()
    end
    return fonts[px]
  end

  local drawPixel = deps.drawPixel or function(...) return love.graphics.draw(...) end

  -- a party icon (32 x 32, two frames) at (x, y) top left, s across; frame by the clock
  local function icon(G, ic, x, y, s, t)
    if not (ic and ic.image) then return end
    local f = (ic.frames or 1) > 1 and (floor((t or 0) * 4) % 2) or 0
    local q = ic.quads and ic.quads[f]
    local k = s / (ic.w or 32)
    G.setColor(1, 1, 1, 1)
    if q then drawPixel(ic.image, q, x, y, 0, k, k) else drawPixel(ic.image, x, y, 0, k, k) end
  end

  -- an HP bar: a dark track with a thin edge, the fill green / yellow / red by the share left
  local function hpBar(G, x, y, w, hh, share)
    share = max(0, min(1, share or 1))
    G.setColor(0.18, 0.18, 0.2, 1)
    G.rectangle("fill", x - 1, y - 1, w + 2, hh + 2)
    G.setColor(0.42, 0.42, 0.45, 1)
    G.rectangle("fill", x, y, w, hh)
    if share > 0.5 then G.setColor(0.2, 0.86, 0.3, 1)
    elseif share > 0.2 then G.setColor(0.98, 0.78, 0.15, 1)
    else G.setColor(0.95, 0.25, 0.2, 1) end
    G.rectangle("fill", x, y, w * share, hh)
  end

  -- the thought bubble (still choosing; its dots ripple while it is this one's turn)
  local function bubble(G, cx, cy, s, now, t)
    G.setLineWidth(max(1, s * 0.09))
    G.setColor(1, 1, 1, 1)
    G.ellipse("fill", cx, cy, s, s * 0.72, 28)
    G.setColor(0.45, 0.45, 0.48, 1)
    G.ellipse("line", cx, cy, s, s * 0.72, 28)
    G.circle("line", cx - s * 0.85, cy + s * 0.75, s * 0.14, 10)
    G.circle("line", cx - s * 1.1, cy + s * 1.0, s * 0.08, 8)
    for k = -1, 1 do
      local lift = now and (sin(t * 6 - k * 1.2) * 0.5 + 0.5) * s * 0.12 or 0
      G.circle("fill", cx + k * s * 0.38, cy - lift, s * 0.11, 10)
    end
    G.setLineWidth(1)
  end

  -- the tick: a green disc with a white check
  local function tick(G, cx, cy, s)
    G.setColor(0.2, 0.75, 0.35, 1)
    G.circle("fill", cx, cy, s, 28)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(max(1.5, s * 0.22))
    G.setLineJoin("miter")
    G.line(cx - s * 0.45, cy + s * 0.02, cx - s * 0.1, cy + s * 0.38, cx + s * 0.5, cy - s * 0.35)
    G.setLineWidth(1)
  end

  -- the action a member chose, as the game marks it once the turn plays: a target with a burst for a
  -- move that hits, a yin-yang for one that does not
  local function actionIcon(G, kind, cx, cy, s)
    G.setLineWidth(max(1, s * 0.11))
    G.setColor(0.45, 0.45, 0.48, 1)
    if kind == "item" then
      -- a bag: its body, its flap, a handle
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", cx - s * 0.8, cy - s * 0.45, s * 1.6, s * 1.25, s * 0.25, s * 0.25)
      G.setColor(0.45, 0.45, 0.48, 1)
      G.rectangle("line", cx - s * 0.8, cy - s * 0.45, s * 1.6, s * 1.25, s * 0.25, s * 0.25)
      G.arc("line", "open", cx, cy - s * 0.45, s * 0.4, math.pi, 2 * math.pi, 16)
      G.line(cx - s * 0.8, cy + s * 0.15, cx + s * 0.8, cy + s * 0.15)
    elseif kind == "status" then
      G.setColor(1, 1, 1, 1)
      G.circle("fill", cx, cy, s, 32)
      G.setColor(0.45, 0.45, 0.48, 1)
      G.arc("fill", "open", cx, cy, s, -math.pi / 2, math.pi / 2, 24)
      G.setColor(1, 1, 1, 1)
      G.circle("fill", cx, cy + s / 2, s / 2, 20)
      G.setColor(0.45, 0.45, 0.48, 1)
      G.circle("fill", cx, cy - s / 2, s / 2, 20)
      G.circle("line", cx, cy, s, 32)
    else
      local tx, ty = cx - s * 0.35, cy + s * 0.25
      for k = 1, 3 do G.circle("line", tx, ty, s * (0.24 + 0.24 * (k - 1)), 24) end
      local pts = {}
      local bx, by = cx + s * 0.45, cy - s * 0.4
      for i = 0, 15 do
        local a = -math.pi / 2 + i * math.pi / 8
        local rr = (i % 2 == 0) and s * 0.5 or s * 0.26
        pts[#pts + 1], pts[#pts + 2] = bx + rr * math.cos(a), by + rr * math.sin(a)
      end
      G.setColor(1, 1, 1, 1)
      G.polygon("fill", pts)
      G.setColor(0.45, 0.45, 0.48, 1)
      G.polygon("line", pts)
    end
    G.setLineWidth(1)
  end
  Bh.actionIcon = actionIcon

  -- the mark of a member's pick: "status" for a move that does no damage, else "fight"
  function Bh.actionOf(m, choice)
    if choice and choice.item then return "item" end
    local mv = choice and choice.move and m.b and m.b.moves[choice.move]
    return (mv and mv.status) and "status" or "fight"
  end

  -- one row of the list: the box, the icon, the mark (`mark`: "wait", "now", "done", "fight",
  -- "status"), the HP bar
  local function row(G, h, i, m, mark, slot, wide, t)
    local O = Bh.ORDER
    local info = m.info or {}
    local bw = h * (O.W + (wide and O.NOW or 0))
    local by, bh = h * (O.TOP + (slot - 1) * O.PITCH), h * O.H
    G.setColor(0.1, 0.1, 0.12, 0.9)
    G.rectangle("fill", 0, by + h * 0.004, bw + h * 0.005, bh)
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, by, bw, bh)
    if mark == "now" then
      G.setColor(0.93, 0.18, 0.42, 1)
      G.rectangle("fill", 0, by, h * 0.008, bh)
    end
    icon(G, info.icon, h * 0.02, by + (bh - h * 0.07) / 2, h * 0.07, mark == "now" and t or 0)
    local cx, cy = bw - h * 0.065, by + bh * 0.38
    if mark == "done" then tick(G, cx, cy, h * 0.022)
    elseif mark == "fight" or mark == "status" or mark == "item" then actionIcon(G, mark, cx, cy, h * 0.026)
    else bubble(G, cx, cy, h * 0.03, mark == "now", t or 0) end
    hpBar(G, bw - h * 0.108, by + bh * 0.8, h * 0.1, h * 0.009,
      info.maxHp and info.maxHp > 0 and info.hp / info.maxHp or 1)
  end

  -- during the turn: only the members the words are about, from the top (each with its action)
  --   rows = { { i, m, kind = "fight" | "status" }, ... }
  function Bh.drawRows(G, w, h, rows, t)
    G.push("all")
    for slot, rw in ipairs(rows) do row(G, h, rw[1], rw[2], rw.kind or "fight", slot, false, t) end
    G.pop()
  end

  function Bh.drawOrder(G, w, h, members, cmd, t)
    local O = Bh.ORDER
    G.push("all")
    for i, m in ipairs(members) do
      local now = cmd and cmd.actor == i
      local c = cmd and cmd.chosen and cmd.chosen[i]
      -- (a dark edge on the right and foot, the white box, a pink stripe on the one choosing; once its
      -- command is in, the mark of its action)
      local mark = now and "now" or "wait"
      if c then mark = Bh.actionOf(m, c) end
      row(G, h, i, m, mark, i, now, t)
    end
    G.pop()
  end

  function Bh.drawPanel(G, w, h, m, foot)
    if not m then return end
    local info = m.info or {}
    local P = Bh.PANEL
    local ph, pw, sl = h * P.H, h * P.W, h * P.SLANT
    local bottom = foot or h
    local py = bottom - ph
    local u = h / 998
    G.push("all")
    -- the shadow along the slanted edge, then the white panel (a lighter grey toward its right)
    G.setColor(0.05, 0.05, 0.07, 0.55)
    G.polygon("fill", 0, py - 3 * u, pw + 6 * u, py - 3 * u, pw - sl + 6 * u, bottom, 0, bottom)
    G.setColor(0.98, 0.98, 0.98, 1)
    G.polygon("fill", 0, py, pw, py, pw - sl, bottom, 0, bottom)
    G.setColor(0.9, 0.9, 0.92, 1)
    G.polygon("fill", pw * 0.62, py, pw, py, pw - sl, bottom, pw * 0.62 - sl, bottom)
    icon(G, info.icon, h * 0.012, py + (ph - h * 0.085) / 2, h * 0.085, 0)
    local x0, x1 = h * 0.115, h * 0.49
    -- the name and gender
    local fName = font(h * 0.028)
    G.setFont(fName)
    G.setColor(0.1, 0.1, 0.12, 1)
    local name = info.name or "?"
    G.print(name, x0, py + h * 0.012)
    -- the gender drawn (the default face has no sign for it): a ring with an arrow or a cross
    local gs = h * 0.008
    local gx, gy = x0 + fName:getWidth(name) + h * 0.006 + gs, py + h * 0.012 + fName:getHeight() * 0.58
    G.setLineWidth(max(1.5, h * 0.003))
    if info.gender == "M" then
      G.setColor(0.2, 0.5, 0.95, 1)
      G.circle("line", gx, gy, gs, 16)
      local ax, ay = gx + gs * 1.9, gy - gs * 1.9
      G.line(gx + gs * 0.7, gy - gs * 0.7, ax, ay)
      G.line(ax - gs * 0.9, ay, ax, ay, ax, ay + gs * 0.9)
    elseif info.gender == "F" then
      G.setColor(0.95, 0.3, 0.45, 1)
      G.circle("line", gx, gy - gs * 0.5, gs, 16)
      G.line(gx, gy + gs * 0.5, gx, gy + gs * 1.7)
      G.line(gx - gs * 0.6, gy + gs * 1.1, gx + gs * 0.6, gy + gs * 1.1)
    end
    G.setLineWidth(1)
    -- the level: "Lv." small, the number large, against the bar's right end
    local fNum, fLv = font(h * 0.036), font(h * 0.022)
    local lv = tostring(info.level or 1)
    G.setColor(0.1, 0.1, 0.12, 1)
    G.setFont(fNum)
    local nw = fNum:getWidth(lv)
    G.print(lv, x1 - nw, py + h * 0.006)
    G.setFont(fLv)
    G.print("Lv.", x1 - nw - fLv:getWidth("Lv.") - h * 0.002, py + h * 0.006 + fNum:getHeight() - fLv:getHeight() - h * 0.004)
    -- the HP bar and numbers
    local hp, mhp = tonumber(info.hp) or 0, tonumber(info.maxHp) or 0
    hpBar(G, x0, py + h * 0.052, x1 - x0, h * 0.011, mhp > 0 and hp / mhp or 1)
    G.setFont(fNum)
    G.setColor(0.1, 0.1, 0.12, 1)
    G.print(("%d/%d"):format(hp, mhp), x0, py + h * 0.07)
    -- the EXP bar
    local ex, ew = h * 0.328, x1 - h * 0.328
    G.setColor(0.32, 0.32, 0.35, 1)
    G.rectangle("fill", ex, py + h * 0.077, ew, h * 0.007)
    G.setColor(0.3, 0.72, 1, 1)
    G.rectangle("fill", ex, py + h * 0.077, ew * max(0, min(1, info.exp or 0)), h * 0.007)
    G.pop()
  end

  return Bh
end
