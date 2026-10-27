-- The battle pad: Gen 5's command menu - FIGHT (red), ITEM (yellow), FLEE (blue) - on a dark
-- panel. By default it sits in the main window's lower right over the den; with BATTLE PAD on the
-- second screen it is drawn into that display's frame instead (src/screen2.lua), and the main
-- window keeps the whole den. FIGHT and ITEM stand greyed until the battle is in.
--   Pad.draw(G, w, h, r) -> the panel's rect (window pixels) ; Pad.hit(x, y) -> "fight" | "item" |
--   "flee" | "panel" | nil (against the last draw) ; Pad.drawFull(G, w, h, r) (a whole screen)

return function(mod, deps)
  local Pad = {}
  local max, min = math.max, math.min

  -- the last draw's places (window pixels), filled again each draw
  local where = { panel = {}, fight = {}, item = {}, flee = {} }
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

  -- a Gen 5 command button: a rounded slab in its colour, a lighter top half, the word
  local function button(G, t, rgb, word, live, u)
    local k = live and 1 or 0.45
    G.setColor(rgb[1] * 0.45 * k, rgb[2] * 0.45 * k, rgb[3] * 0.45 * k, 1)
    G.rectangle("fill", t.x, t.y + 3 * u, t.w, t.h, 10 * u, 10 * u)
    G.setColor(rgb[1] * k, rgb[2] * k, rgb[3] * k, 1)
    G.rectangle("fill", t.x, t.y, t.w, t.h, 10 * u, 10 * u)
    G.setColor(1, 1, 1, live and 0.25 or 0.1)
    G.rectangle("fill", t.x + 5 * u, t.y + 4 * u, t.w - 10 * u, t.h * 0.42, 8 * u, 8 * u)
    local f = font(min(t.h * 0.42, t.w * 0.18))
    G.setFont(f)
    local fy = t.y + (t.h - f:getHeight()) / 2
    G.setColor(0, 0, 0, 0.5)
    G.printf(word, t.x + 1, fy + 1, t.w, "center")
    G.setColor(1, 1, 1, live and 1 or 0.6)
    G.printf(word, t.x, fy, t.w, "center")
  end

  -- the menu inside a rect
  local function menu(G, x, y, w, h, r)
    local u = h / 180
    G.setColor(0.12, 0.13, 0.17, 0.92)
    G.rectangle("fill", x, y, w, h, 12 * u, 12 * u)
    G.setColor(0.18, 0.2, 0.26, 1)
    G.rectangle("fill", x + 6 * u, y + 6 * u, w - 12 * u, h - 12 * u, 9 * u, 9 * u)
    local live = r and r.phase == "command" and false
    local fx, fw = x + w * 0.1, w * 0.8
    rset(where.fight, fx, y + h * 0.12, fw, h * 0.44)
    local by = where.fight.y + where.fight.h + 12 * u
    local bh = min(h * 0.26, y + h - by - 10 * u)
    rset(where.item, x + w * 0.06, by, w * 0.41, bh)
    rset(where.flee, x + w * 0.53, by, w * 0.41, bh)
    button(G, where.fight, { 0.86, 0.2, 0.18 }, "FIGHT", live, u)
    button(G, where.item, { 0.9, 0.72, 0.12 }, "ITEM", live, u)
    button(G, where.flee, { 0.2, 0.45, 0.9 }, "FLEE", true, u)
  end

  -- on the main window: a panel in the lower right, about a third of the width
  function Pad.draw(G, w, h, r)
    local pw = min(w * 0.34, h * 0.62)
    local ph = pw * 0.7
    local px, py = w - pw - h * 0.03, h - ph - h * 0.03
    rset(where.panel, px, py, pw, ph)
    menu(G, px, py, pw, ph, r)
    return where.panel
  end

  -- filling a whole screen (the second display's frame)
  function Pad.drawFull(G, w, h, r)
    rset(where.panel, 0, 0, w, h)
    G.setColor(0.08, 0.09, 0.12, 1)
    G.rectangle("fill", 0, 0, w, h)
    menu(G, 0, 0, w, h, r)
  end

  function Pad.hit(x, y)
    if not inRect(x, y, where.panel) then return nil end
    if inRect(x, y, where.fight) then return "fight" end
    if inRect(x, y, where.item) then return "item" end
    if inRect(x, y, where.flee) then return "flee" end
    return "panel"
  end

  return Pad
end
