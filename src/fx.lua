-- The raid's move effects, drawn in code over the den (window pixels; no art):
--   * a hit: a short effect by the move's type where it lands (Fx.hit), larger for a G-Max move
--   * the G-Max charge: the screen washed red, energy streaking into the boss (Fx.charge)
--   * what lasts: a G-Max field round the party (flames, a vortex, vines, rocks: Fx.drawField), the
--     boss's veil (Fx.drawVeil), its barrier while it stands (Fx.drawBarrier)
-- Fx.update(now) drops what has finished; Fx.draw(G, now) draws the hits and the charge.
--   Fx = fx() ; Fx.hit(typeName, x, y, size, big, now) ; Fx.charge(x, y, size, now, dur)

return function()
  local Fx = {}
  local sin, cos, pi, max, min, floor, abs = math.sin, math.cos, math.pi, math.max, math.min, math.floor, math.abs

  Fx.HIT_S = 0.7           -- a hit's effect
  local live = {}          -- the hits playing: { kind, t0, x, y, s, big, seed }
  local charge = nil       -- the G-Max charge: { x, y, s, t0, dur }

  local function rnd(seed, k) return (sin(seed * 12.9898 + k * 78.233) * 43758.5453) % 1 end

  -- a flame: a teardrop pointing up, its base at (x, y), h tall
  local function flame(G, x, y, w, h)
    G.polygon("fill", x - w, y, x - w * 0.6, y - h * 0.45, x, y - h, x + w * 0.6, y - h * 0.45, x + w, y)
    G.circle("fill", x, y, w, 12)
  end
  -- an n-point star, outer r, inner ir
  local starPts = {}
  local function star(G, x, y, r, ir, n, rot)
    for i = 0, n * 2 - 1 do
      local a = (rot or 0) + i * pi / n
      local rr = (i % 2 == 0) and r or ir
      starPts[i * 2 + 1], starPts[i * 2 + 2] = x + cos(a) * rr, y + sin(a) * rr
    end
    for i = n * 4 + 1, #starPts do starPts[i] = nil end
    G.polygon("fill", starPts)
  end
  -- a jagged bolt from (x1, y1) to (x2, y2)
  local function bolt(G, x1, y1, x2, y2, seed, jag)
    local pts = { x1, y1 }
    local n = 6
    for k = 1, n - 1 do
      local f = k / n
      local nx, ny = -(y2 - y1), x2 - x1
      local l = math.sqrt(nx * nx + ny * ny) + 1e-6
      local off = (rnd(seed, k) - 0.5) * jag
      pts[#pts + 1] = x1 + (x2 - x1) * f + nx / l * off
      pts[#pts + 1] = y1 + (y2 - y1) * f + ny / l * off
    end
    pts[#pts + 1], pts[#pts + 1] = x2, y2
    G.line(pts)
  end

  -- each type's effect: draw(G, u (0..1), x, y (the target's middle), s (its height), seed)
  local DRAW = {}
  DRAW.FIRE = function(G, u, x, y, s, seed)
    if Fx.fireRect and Fx.fireRect(G, x - s * 0.6, y - s * 0.9, s * 1.2, s * 1.4, u * 2 + seed, seed, 1 - u * u) then return end
    for k = 1, 9 do
      local a = rnd(seed, k)
      local fx = x + (a - 0.5) * s * 0.9
      local fy = y + s * 0.4 - u * s * (0.5 + 0.6 * rnd(seed, k + 20))
      local h = s * (0.35 + 0.3 * rnd(seed, k + 40)) * (1 - u * 0.5)
      G.setColor(1, 0.45 + 0.3 * a, 0.1, 0.85 * (1 - u))
      flame(G, fx, fy, h * 0.3, h)
      G.setColor(1, 0.9, 0.4, 0.8 * (1 - u))
      flame(G, fx, fy, h * 0.14, h * 0.55)
    end
  end
  DRAW.WATER = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1, s * 0.04))
    G.setColor(0.4, 0.7, 1, 0.8 * (1 - u))
    G.ellipse("line", x, y + s * 0.3, s * (0.2 + 0.7 * u), s * (0.06 + 0.2 * u), 32)
    for k = 1, 12 do
      local a = rnd(seed, k) * 2 * pi
      local d = s * 0.7 * u
      local dx, dy = x + cos(a) * d, y + sin(a) * d * 0.6 - s * 0.6 * u * (1 - u) * 2
      G.setColor(0.55, 0.8, 1, 0.9 * (1 - u))
      G.circle("fill", dx, dy, s * 0.05 * (1 - u * 0.5), 10)
    end
    G.setLineWidth(1)
  end
  DRAW.ELECTRIC = function(G, u, x, y, s, seed)
    local flick = (floor(u * 14) % 2 == 0) and 1 or 0.4
    G.setColor(1, 0.95, 0.3, 0.35 * (1 - u) * flick)
    G.circle("fill", x, y, s * 0.6, 24)
    G.setLineWidth(max(1.5, s * 0.035))
    for k = 1, 4 do
      G.setColor(1, 1, 0.55, (1 - u) * flick)
      bolt(G, x + (rnd(seed, k) - 0.5) * s * 0.5, y - s * 0.9, x + (rnd(seed, k + 9) - 0.5) * s * 0.4, y + s * 0.4,
        seed + floor(u * 10) + k, s * 0.25)
    end
    G.setLineWidth(1)
  end
  DRAW.GRASS = function(G, u, x, y, s, seed)
    for k = 1, 12 do
      local a = rnd(seed, k) * 2 * pi + u * 4
      local d = s * (0.1 + 0.6 * u)
      local lx, ly = x + cos(a) * d, y + sin(a) * d * 0.7
      G.push()
      G.translate(lx, ly)
      G.rotate(a + u * 6)
      G.setColor(0.35, 0.8, 0.3, 0.9 * (1 - u))
      G.ellipse("fill", 0, 0, s * 0.09, s * 0.035, 12)
      G.pop()
    end
  end
  DRAW.ICE = function(G, u, x, y, s, seed)
    G.setColor(0.85, 0.97, 1, 0.5 * (1 - u))
    G.circle("fill", x, y, s * 0.5 * u + s * 0.1, 24)
    for k = 1, 10 do
      local a = rnd(seed, k) * 2 * pi
      local d = s * 0.75 * u
      local cx, cy = x + cos(a) * d, y + sin(a) * d
      local r = s * 0.1 * (1 - u * 0.4)
      G.setColor(0.7, 0.92, 1, 0.95 * (1 - u))
      G.polygon("fill", cx + cos(a) * r * 1.8, cy + sin(a) * r * 1.8, cx + cos(a + 2.2) * r, cy + sin(a + 2.2) * r,
        cx + cos(a - 2.2) * r, cy + sin(a - 2.2) * r)
    end
  end
  DRAW.ROCK = function(G, u, x, y, s, seed)
    for k = 1, 7 do
      local fx = x + (rnd(seed, k) - 0.5) * s * 0.9
      local land = y + s * (0.2 + 0.3 * rnd(seed, k + 3))
      local fy = land - (1 - min(1, u * 1.8 + rnd(seed, k + 7) * 0.2)) * s * 1.6
      local r = s * (0.08 + 0.07 * rnd(seed, k + 11))
      G.setColor(0.55, 0.42, 0.28, u < 0.85 and 1 or (1 - u) / 0.15)
      G.polygon("fill", fx - r, fy, fx - r * 0.4, fy - r, fx + r * 0.7, fy - r * 0.7, fx + r, fy + r * 0.2, fx + r * 0.2, fy + r)
    end
  end
  DRAW.GROUND = function(G, u, x, y, s, seed)
    for k = 1, 10 do
      local a = (k / 10) * 2 * pi
      local d = s * 0.6 * u
      G.setColor(0.65, 0.5, 0.3, 0.55 * (1 - u))
      G.circle("fill", x + cos(a) * d, y + s * 0.35 + sin(a) * d * 0.25, s * (0.12 + 0.12 * u), 16)
    end
    DRAW.ROCK(G, min(1, u * 1.2), x, y + s * 0.1, s * 0.6, seed + 5)
  end
  DRAW.POISON = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1, s * 0.02))
    for k = 1, 10 do
      local bx = x + (rnd(seed, k) - 0.5) * s * 0.9
      local by = y + s * 0.4 - (u + rnd(seed, k + 5) * 0.3) * s * 0.9
      local r = s * (0.05 + 0.06 * rnd(seed, k + 9)) * (1 + u * 0.5)
      G.setColor(0.65, 0.3, 0.8, 0.6 * (1 - u))
      G.circle("fill", bx, by, r, 14)
      G.setColor(0.9, 0.7, 1, 0.8 * (1 - u))
      G.circle("line", bx, by, r, 14)
    end
    G.setLineWidth(1)
  end
  DRAW.PSYCHIC = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1.5, s * 0.03))
    for k = 0, 2 do
      local f = (u * 1.4 - k * 0.2)
      if f > 0 and f < 1 then
        G.setColor(1, 0.4, 0.75, 0.9 * (1 - f))
        G.ellipse("line", x, y, s * 0.8 * f, s * 0.55 * f, 32)
      end
    end
    G.setLineWidth(1)
  end
  DRAW.DARK = function(G, u, x, y, s, seed)
    G.setLineWidth(max(2, s * 0.06))
    for k = 0, 2 do
      local f = min(1, max(0, u * 2 - k * 0.25))
      if f > 0 then
        local ox = (k - 1) * s * 0.25
        G.setColor(0.3, 0.1, 0.4, 0.95 * (1 - u))
        G.arc("line", "open", x + ox - s * 0.2, y - s * 0.2, s * 0.6, -0.2, -0.2 + 1.5 * f, 20)
      end
    end
    G.setLineWidth(1)
  end
  DRAW.GHOST = function(G, u, x, y, s, seed)
    for k = 1, 6 do
      local a = rnd(seed, k) * 2 * pi + u * 5
      local d = s * (0.5 - 0.4 * u)
      local wx, wy = x + cos(a) * d, y + sin(a) * d * 0.7
      G.setColor(0.55, 0.35, 0.8, 0.7 * (1 - u))
      G.circle("fill", wx, wy, s * 0.09, 14)
      G.setColor(0.35, 0.2, 0.55, 0.5 * (1 - u))
      G.circle("fill", wx - cos(a) * s * 0.08, wy - sin(a) * s * 0.06, s * 0.06, 12)
    end
  end
  DRAW.DRAGON = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1.5, s * 0.04))
    local pts = {}
    for k = 0, 30 do
      local f = k / 30
      local a = f * 4 * pi + u * 6
      local r = s * 0.7 * f * (0.4 + u)
      pts[#pts + 1], pts[#pts + 2] = x + cos(a) * r, y + sin(a) * r * 0.7
    end
    G.setColor(0.45, 0.35, 1, 0.9 * (1 - u))
    G.line(pts)
    G.setColor(0.8, 0.5, 1, 0.4 * (1 - u))
    G.circle("fill", x, y, s * 0.3 * (1 - u), 20)
    G.setLineWidth(1)
  end
  DRAW.FAIRY = function(G, u, x, y, s, seed)
    for k = 1, 10 do
      local a = rnd(seed, k) * 2 * pi
      local d = s * 0.65 * (0.3 + u)
      local tw = 0.6 + 0.4 * sin(u * 20 + k)
      G.setColor(1, 0.65, 0.85, (1 - u) * tw)
      star(G, x + cos(a) * d, y + sin(a) * d * 0.8, s * 0.08, s * 0.025, 4, u * 3)
    end
  end
  DRAW.FIGHTING = function(G, u, x, y, s, seed)
    local r = s * (0.3 + 0.5 * u)
    G.setColor(1, 0.55, 0.15, 0.85 * (1 - u))
    star(G, x, y, r, r * 0.45, 8, 0.3)
    G.setColor(1, 0.95, 0.7, 0.9 * (1 - u))
    star(G, x, y, r * 0.55, r * 0.25, 8, 0.3)
  end
  DRAW.FLYING = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1.5, s * 0.03))
    for k = 0, 3 do
      local f = min(1, max(0, u * 1.6 - k * 0.15))
      G.setColor(0.9, 0.95, 1, 0.85 * (1 - u))
      G.arc("line", "open", x - s * 0.5 + f * s * 0.6, y - s * 0.3 + k * s * 0.2, s * 0.35, -1.2, 0.6, 16)
    end
    G.setLineWidth(1)
  end
  DRAW.BUG = function(G, u, x, y, s, seed)
    G.setLineWidth(max(1, s * 0.025))
    for k = 1, 12 do
      local a = rnd(seed, k) * 2 * pi
      local d0, d1 = s * 0.9 * (1 - u), s * 0.9 * (1 - u) + s * 0.18
      G.setColor(0.6, 0.85, 0.2, 0.9 * (1 - u * 0.7))
      G.line(x + cos(a) * d0, y + sin(a) * d0, x + cos(a) * d1, y + sin(a) * d1)
    end
    G.setLineWidth(1)
  end
  DRAW.STEEL = function(G, u, x, y, s, seed)
    DRAW.ICE(G, u, x, y, s, seed)
    G.setLineWidth(max(1, s * 0.03))
    G.setColor(1, 1, 1, 0.8 * (1 - u))
    for k = 0, 3 do
      local a = k * pi / 4 + u
      G.line(x - cos(a) * s * 0.6, y - sin(a) * s * 0.6, x + cos(a) * s * 0.6, y + sin(a) * s * 0.6)
    end
    G.setLineWidth(1)
  end
  DRAW.NORMAL = function(G, u, x, y, s, seed)
    local r = s * (0.25 + 0.45 * u)
    G.setColor(1, 1, 1, 0.9 * (1 - u))
    star(G, x, y, r, r * 0.4, 6, u)
  end
  local TINT = {
    FIRE = { 1, 0.5, 0.15 }, WATER = { 0.3, 0.6, 1 }, ELECTRIC = { 1, 0.9, 0.2 }, GRASS = { 0.35, 0.8, 0.3 },
    ICE = { 0.6, 0.9, 1 }, ROCK = { 0.65, 0.5, 0.3 }, GROUND = { 0.75, 0.6, 0.35 }, POISON = { 0.65, 0.3, 0.8 },
    PSYCHIC = { 1, 0.4, 0.75 }, DARK = { 0.35, 0.2, 0.45 }, GHOST = { 0.5, 0.35, 0.8 }, DRAGON = { 0.45, 0.35, 1 },
    FAIRY = { 1, 0.6, 0.85 }, FIGHTING = { 1, 0.5, 0.2 }, FLYING = { 0.8, 0.9, 1 }, BUG = { 0.6, 0.85, 0.2 },
    STEEL = { 0.8, 0.85, 0.9 }, NORMAL = { 1, 1, 1 },
  }
  Fx.TINT = TINT

  -- ------- the API

  local seedN = 0
  function Fx.hit(typeName, x, y, s, big, now)
    seedN = seedN + 1
    live[#live + 1] = { kind = DRAW[typeName] and typeName or "NORMAL", t0 = now, x = x, y = y,
      s = s * (big and 1.6 or 1), big = big, seed = seedN * 7.3 }
  end
  function Fx.charge(x, y, s, now, dur) charge = { x = x, y = y, s = s, t0 = now, dur = dur or 1.6 } end
  function Fx.charging(now) return charge ~= nil and now - charge.t0 < charge.dur end
  function Fx.clear() for i = #live, 1, -1 do live[i] = nil end; charge = nil end

  function Fx.update(now)
    if Fx.landMoves then Fx.landMoves(now) end
    for i = #live, 1, -1 do
      if now - live[i].t0 > Fx.HIT_S * (live[i].big and 1.4 or 1) then table.remove(live, i) end
    end
    if charge and now - charge.t0 > charge.dur then charge = nil end
  end

  -- the G-Max charge: a red wash rising, streaks pulled into the boss, sparks; under the hits
  local function drawCharge(G, w, h, now)
    local c = charge
    local u = (now - c.t0) / c.dur
    local a = sin(min(1, u) * pi)
    G.setColor(0.55, 0.0, 0.08, 0.45 * a)
    G.rectangle("fill", 0, 0, w, h)
    G.setLineWidth(max(1.5, h * 0.004))
    for k = 1, 22 do
      local ang = rnd(c.t0, k) * 2 * pi
      local phase = (u * 2.2 + rnd(c.t0, k + 30)) % 1
      local d0 = max(w, h) * 0.75 * (1 - phase)
      local d1 = d0 + h * 0.12
      G.setColor(1, 0.25 + 0.4 * rnd(c.t0, k + 60), 0.35, 0.8 * a * (1 - phase * 0.5))
      G.line(c.x + cos(ang) * d0, c.y + sin(ang) * d0, c.x + cos(ang) * d1, c.y + sin(ang) * d1)
    end
    G.setLineWidth(1)
    G.setColor(1, 0.35, 0.45, 0.35 * a)
    G.circle("fill", c.x, c.y, c.s * (0.3 + 0.2 * sin(now * 18)), 32)
  end

  function Fx.draw(G, w, h, now)
    G.push("all")
    if charge then drawCharge(G, w, h, now) end
    G.setBlendMode("alpha")
    for _, e in ipairs(live) do
      local u = (now - e.t0) / (Fx.HIT_S * (e.big and 1.4 or 1))
      if u >= 0 and u <= 1 then
        -- a flash at the moment it lands, tinted by the type, then its effect
        if u < 0.25 then
          local tc = TINT[e.kind] or TINT.NORMAL
          G.setColor(tc[1], tc[2], tc[3], 0.35 * (1 - u / 0.25))
          G.circle("fill", e.x, e.y, e.s * 0.75, 32)
        end
        DRAW[e.kind](G, u, e.x, e.y, e.s, e.seed)
      end
    end
    G.pop()
  end

  -- ------- what lasts

  -- a G-Max field over the party: along the foot of the screen, by its type
  function Fx.drawField(G, w, h, now, kind)
    if not kind then return end
    G.push("all")
    local base = h * 0.98
    if kind == "FIRE" and Fx.fireRect and Fx.fireRect(G, 0, base - h * 0.22, w, h * 0.24, now, 7, 0.85) then
      -- (real fire along the party's feet)
    elseif kind == "FIRE" then
      for k = 0, 22 do
        local x = (k + 0.5) / 22 * w
        local fl = 0.75 + 0.25 * sin(now * 7 + k * 1.7)
        local fh = h * (0.12 + 0.07 * sin(now * 3 + k)) * fl
        G.setColor(1, 0.35, 0.08, 0.55)
        flame(G, x, base, w / 44 * 1.6, fh)
        G.setColor(1, 0.8, 0.3, 0.55)
        flame(G, x, base, w / 44 * 0.7, fh * 0.55)
      end
    elseif kind == "WATER" then
      G.setLineWidth(max(2, h * 0.006))
      for k = 0, 5 do
        local y = base - h * (0.02 + k * 0.03)
        local pts = {}
        for i = 0, 40 do
          local x = i / 40 * w
          pts[#pts + 1], pts[#pts + 2] = x, y + sin(i * 0.6 + now * (3 + k) + k) * h * 0.012
        end
        G.setColor(0.35, 0.65, 1, 0.5 - k * 0.06)
        G.line(pts)
      end
    elseif kind == "GRASS" then
      G.setLineWidth(max(2, h * 0.008))
      for k = 0, 9 do
        local x0 = (k + 0.5) / 10 * w
        local pts = {}
        for i = 0, 12 do
          local f = i / 12
          pts[#pts + 1] = x0 + sin(f * 5 + now * 2 + k) * w * 0.02
          pts[#pts + 1] = base - f * h * (0.2 + 0.05 * sin(now + k))
        end
        G.setColor(0.25, 0.65, 0.2, 0.75)
        G.line(pts)
        G.setColor(0.4, 0.85, 0.3, 0.75)
        G.ellipse("fill", pts[#pts - 1], pts[#pts], w * 0.012, h * 0.01, 10)
      end
    elseif kind == "ROCK" then
      for k = 0, 14 do
        local x = (k + 0.5) / 15 * w + sin(k * 3.1) * w * 0.02
        local r = h * (0.03 + 0.02 * ((k * 7) % 3))
        local y = base - r * 0.6 + sin(now * 2 + k) * h * 0.004
        G.setColor(0.45, 0.35, 0.25, 0.85)
        G.polygon("fill", x - r, y, x - r * 0.5, y - r, x + r * 0.6, y - r * 0.8, x + r, y, x, y + r * 0.4)
      end
    end
    G.pop()
  end

  -- the boss's veil: a pale shimmer round it
  function Fx.drawVeil(G, LB, now)
    if not LB then return end
    G.push("all")
    G.setLineWidth(max(1.5, LB.h * 0.008))
    for k = 0, 2 do
      local a = 0.25 + 0.15 * sin(now * 2 + k * 2)
      G.setColor(0.7, 0.95, 1, a)
      G.ellipse("line", LB.x, LB.y, LB.h * (0.5 + k * 0.04), LB.h * (0.58 + k * 0.04), 48)
    end
    G.pop()
  end

  -- its barrier while it stands: a hexagon dome of light round it, dimmer as segments break
  function Fx.drawBarrier(G, LB, now, left, most)
    if not (LB and left and left > 0) then return end
    G.push("all")
    local share = most and most > 0 and left / most or 1
    local rx, ry = LB.h * 0.55, LB.h * 0.62
    G.setColor(1, 0.25, 0.45, 0.12 + 0.08 * share)
    G.ellipse("fill", LB.x, LB.y, rx, ry, 48)
    G.setLineWidth(max(1, LB.h * 0.005))
    local cell = LB.h * 0.11
    for row = -6, 6 do
      for col = -6, 6 do
        local cx = LB.x + (col + (row % 2) * 0.5) * cell * 1.5
        local cy = LB.y + row * cell * 0.87
        local nx, ny = (cx - LB.x) / rx, (cy - LB.y) / ry
        if nx * nx + ny * ny < 1 then
          local tw = 0.5 + 0.5 * sin(now * 3 + row + col * 1.7)
          G.setColor(1, 0.45, 0.6, (0.15 + 0.25 * tw) * (0.5 + 0.5 * share))
          local pts = {}
          for i = 0, 5 do
            pts[#pts + 1], pts[#pts + 2] = cx + cos(i * pi / 3) * cell * 0.5, cy + sin(i * pi / 3) * cell * 0.5
          end
          G.polygon("line", pts)
        end
      end
    end
    G.setColor(1, 0.5, 0.65, 0.6 * share)
    G.ellipse("line", LB.x, LB.y, rx, ry, 48)
    G.pop()
  end

  -- ------- shaders: fire (rising noise through a fire ramp, on a stretched white texel: tc 0..1 across
  -- the rect, y down) and rock (noise on screen position over the colour drawn), made on first use;
  -- nil where the device cannot (then the drawn shapes stand in)
  local shaders = { tried = false }
  local FIRE_GLSL = [[
extern number time;
extern number seed;
extern number aspect;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0; float a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
  return v;
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float h = 1.0 - tc.y;
  vec2 q = vec2(tc.x * aspect * 2.2 + seed, tc.y * 2.2 + time * 1.7);
  float n = fbm(q);
  float n2 = fbm(q * 2.1 + vec2(seed * 0.5, time * 0.9));
  float flame = n * 1.35 + n2 * 0.45 - h * 1.55 + 0.25;
  flame = clamp(flame, 0.0, 1.0);
  vec3 col = mix(vec3(0.45, 0.02, 0.0), vec3(1.0, 0.36, 0.04), smoothstep(0.05, 0.4, flame));
  col = mix(col, vec3(1.0, 0.78, 0.25), smoothstep(0.4, 0.72, flame));
  col = mix(col, vec3(1.0, 0.98, 0.8), smoothstep(0.78, 1.0, flame));
  float a = smoothstep(0.02, 0.3, flame) * color.a;
  return vec4(col, a);
}
]]
  local ROCK_GLSL = [[
extern number scale;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0; float a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.07; a *= 0.5; }
  return v;
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = sc / scale;
  float n = fbm(p);
  float pits = smoothstep(0.62, 0.7, fbm(p * 2.7 + 3.1));
  float shade = 0.7 + 0.55 * n - 0.25 * pits;
  return vec4(color.rgb * shade, color.a);
}
]]
  local function shader(name)
    if not shaders.tried then
      shaders.tried = true
      local ok1, f = pcall(love.graphics.newShader, FIRE_GLSL)
      if ok1 then shaders.fire = f end
      local ok2, r = pcall(love.graphics.newShader, ROCK_GLSL)
      if ok2 then shaders.rock = r end
      local okI, img = pcall(function()
        local d = love.image.newImageData(1, 1)
        d:setPixel(0, 0, 1, 1, 1, 1)
        return love.graphics.newImage(d)
      end)
      if okI then shaders.texel = img end
    end
    return shaders[name]
  end
  Fx.shader = shader

  -- real fire in a rect (x, y top-left, w, h): flames rising off its foot; false when the shader is out
  local function fireRect(G, x, y, w, h, now, seed, alpha)
    local sh, tx = shader("fire"), shaders.texel
    if not (sh and tx) then return false end
    sh:send("time", now)
    sh:send("seed", seed or 0)
    sh:send("aspect", w / math.max(1, h))
    G.setShader(sh)
    G.setColor(1, 1, 1, alpha or 1)
    G.draw(tx, x, y, 0, w, h)
    G.setShader()
    return true
  end
  Fx.fireRect = fireRect

  -- a filled polygon shaded as rock (noise over its colour); plain without the shader
  local function rockPoly(G, pts, scale)
    local sh = shader("rock")
    if sh then
      sh:send("scale", math.max(1, scale or 20))
      G.setShader(sh)
    end
    G.polygon("fill", pts)
    G.setShader()
  end
  Fx.rockPoly = rockPoly

  -- ------- moves acted out (data/raid_move_fx.lua): Fx.move(spec, typeName, from, targets, now, big)
  -- from = { x, y, s } (the user's middle and height), targets = { { x, y, s }, ... }. Each kind has a
  -- length and an impact (seconds): at the impact every target gets its type's hit (Fx.hit). Returns
  -- impact, length.

  Fx.KIND = {
    beam = { 0.9, 0.35 }, shot = { 0.85, 0.55 }, drop = { 1.0, 0.65 }, slab = { 1.5, 0.95 }, slam = { 0.7, 0.4 },
    slash = { 0.6, 0.3 }, bite = { 0.65, 0.35 }, bolt = { 0.7, 0.18 }, wave = { 1.1, 0.6 }, rings = { 0.9, 0.5 },
    powder = { 1.1, 0.6 }, self = { 0.9, nil }, drain = { 1.2, 0.3 }, spikes = { 0.85, 0.4 }, multi = { 0.35, 0.18 },
  }
  Fx.GMAX_K = 1.35          -- a G-Max move plays this much longer
  local moves = {}

  function Fx.move(spec, typeName, from, targets, now, big)
    local kind = spec[1] or "slam"
    local key = (kind == "drop" and spec.shape == "slab") and "slab" or kind
    local K = Fx.KIND[key] or Fx.KIND.slam
    local len, impact = K[1], K[2]
    if kind == "multi" then
      local n = spec.n or 3
      len, impact = K[1] * n + 0.2, K[2]
    end
    local k = big and Fx.GMAX_K or 1
    local m = { spec = spec, kind = kind, key = key, type = typeName or "NORMAL", from = from, targets = targets,
      t0 = now, len = len * k, impact = impact and impact * k or nil, big = big or spec.big, hits = 0, seed = now * 13.7 }
    moves[#moves + 1] = m
    return m.impact, m.len
  end

  -- a shape at (x, y), r across, in the type's colour
  local function shapeAt(G, shape, x, y, r, rot, tc, a)
    G.push()
    G.translate(x, y)
    G.rotate(rot or 0)
    if shape == "star" or shape == "shuriken" then
      if shape == "star" then G.setColor(1, 0.95, 0.4, a) else G.setColor(tc[1], tc[2], tc[3], a) end
      star(G, 0, 0, r, r * 0.42, shape == "star" and 5 or 4, 0)
    elseif shape == "coin" then
      G.setColor(1, 0.82, 0.25, a)
      G.ellipse("fill", 0, 0, r * 0.8, r, 16)
      G.setColor(0.8, 0.6, 0.1, a)
      G.ellipse("line", 0, 0, r * 0.55, r * 0.75, 16)
    elseif shape == "leaf" then
      G.setColor(0.35, 0.8, 0.3, a)
      G.ellipse("fill", 0, 0, r, r * 0.38, 14)
    elseif shape == "blade" then
      G.setColor(0.9, 0.97, 1, a)
      G.arc("fill", "pie", 0, 0, r, -0.5, 0.5, 10)
    elseif shape == "apple" then
      G.setColor(0.85, 0.2, 0.2, a)
      G.circle("fill", 0, 0, r, 24)
      G.setColor(0.3, 0.6, 0.2, a)
      G.ellipse("fill", r * 0.3, -r * 1.05, r * 0.35, r * 0.15, 10)
    elseif shape == "rock" then
      G.setColor(0.55, 0.43, 0.3, a)
      G.polygon("fill", -r, 0, -r * 0.5, -r, r * 0.6, -r * 0.8, r, r * 0.1, r * 0.3, r, -r * 0.6, r * 0.8)
    else
      G.setColor(tc[1], tc[2], tc[3], a)
      G.circle("fill", 0, 0, r, 24)
      G.setColor(min(1, tc[1] + 0.35), min(1, tc[2] + 0.35), min(1, tc[3] + 0.35), a)
      G.circle("fill", -r * 0.3, -r * 0.3, r * 0.4, 16)
    end
    G.pop()
  end

  -- what falls from above: a rock, an apple, a fist, a foot, a body, coins, or a great slab
  local function fallingThing(G, shape, x, y, s, tc, a)
    if shape == "slab" then
      -- a great slab of rock, tilted, its underside dark
      local w, h = s * 1.5, s * 0.75
      G.push()
      G.translate(x, y)
      G.rotate(0.12)
      G.setColor(0.42, 0.33, 0.24, a)
      G.polygon("fill", -w / 2, -h / 2, w / 2, -h * 0.62, w * 0.55, h / 2, -w * 0.52, h * 0.55)
      G.setColor(0.6, 0.5, 0.36, a)
      G.polygon("fill", -w / 2, -h / 2, w / 2, -h * 0.62, w * 0.4, -h * 0.3, -w * 0.42, -h * 0.22)
      G.setColor(0.3, 0.23, 0.16, a)
      G.setLineWidth(max(1, s * 0.02))
      G.line(-w * 0.2, -h * 0.4, -w * 0.05, 0, -w * 0.18, h * 0.4)
      G.line(w * 0.25, -h * 0.5, w * 0.15, h * 0.1)
      G.setLineWidth(1)
      G.pop()
    elseif shape == "fist" or shape == "foot" or shape == "body" or shape == "kick" or shape == "claw" or shape == "horn" then
      local r = s * (shape == "fist" and 0.45 or 0.55)
      G.setColor(tc[1] * 0.7 + 0.3, tc[2] * 0.7 + 0.3, tc[3] * 0.7 + 0.3, a * 0.9)
      G.ellipse("fill", x, y, r, r * (shape == "foot" and 0.55 or 0.85), 28)
      G.setColor(1, 1, 1, a * 0.35)
      G.ellipse("fill", x - r * 0.25, y - r * 0.3, r * 0.4, r * 0.25, 16)
    else
      shapeAt(G, shape, x, y, s * 0.18, 0, tc, a)
    end
  end

  -- a great slab of rock over everyone it falls on (Max Rockfall's): its shadow spreading, then it
  -- drops (fast at the end), lands with a dust cloud and cracks, sinks and fades
  function Fx.drawSlab(G, m, u, imp, now)
    local x0, x1, ys, s = math.huge, -math.huge, 0, 0
    for _, t in ipairs(m.targets) do
      x0, x1 = min(x0, t.x - t.s * 0.5), max(x1, t.x + t.s * 0.5)
      ys, s = ys + t.y + t.s * 0.45, max(s, t.s)
    end
    local land = ys / #m.targets
    local cx, w = (x0 + x1) / 2, (x1 - x0) * 1.15 + s * 0.4
    local thick = s * 0.75
    local fall = min(1, u / imp)
    G.setColor(0, 0, 0, 0.45 * fall)
    G.ellipse("fill", cx, land, w * 0.55 * (0.4 + 0.6 * fall), s * 0.16 * (0.4 + 0.6 * fall), 40)
    local after = u >= imp and (u - imp) / (1 - imp) or 0
    local top = land - s * 3.2
    local y = u < imp and (top + (land - top) * fall * fall * fall) or (land + thick * 0.25 * after)
    local a = u < imp and 1 or max(0, 1 - after * 1.4)
    if a > 0 then
      local lean = 0.06
      -- its front face and its top, a lighter band along the edge
      local fx0, fx1 = cx - w / 2, cx + w / 2
      G.setColor(0.36, 0.29, 0.22, a)
      Fx.rockPoly(G, { fx0, y - thick, fx1, y - thick - w * lean, fx1, y - w * lean, fx0, y }, s * 0.18)
      G.setColor(0.55, 0.46, 0.35, a)
      Fx.rockPoly(G, { fx0, y - thick, fx0 + w * 0.08, y - thick * 1.45, fx1 + w * 0.06, y - thick * 1.45 - w * lean,
        fx1, y - thick - w * lean }, s * 0.18)
      G.setColor(0.22, 0.17, 0.12, a)
      G.setLineWidth(max(1, s * 0.025))
      G.line(fx0 + w * 0.3, y - thick * 0.95, fx0 + w * 0.34, y - thick * 0.5, fx0 + w * 0.28, y - thick * 0.1)
      G.line(fx0 + w * 0.68, y - thick - w * lean * 0.7, fx0 + w * 0.64, y - thick * 0.4)
      G.setLineWidth(1)
    end
    if u >= imp then
      -- the dust cloud rolling out from under it, rocks thrown up
      for k = 1, 14 do
        local d = (k / 14 - 0.5) * w * (1 + after * 0.6)
        G.setColor(0.62, 0.53, 0.42, 0.55 * (1 - after))
        G.circle("fill", cx + d, land - s * 0.1 - after * s * 0.3 * rnd(m.seed, k), s * (0.12 + 0.3 * after) * (0.7 + 0.5 * rnd(m.seed, k + 3)), 16)
      end
    end
  end

  local function drawMove(G, m, now)
    local u = (now - m.t0) / m.len
    if u < 0 or u > 1 then return end
    local tc = TINT[m.type] or TINT.NORMAL
    local f, imp = m.from, (m.impact or m.len) / m.len
    local spec = m.spec
    local scale = m.big and 1.5 or 1
    if m.kind == "drop" and spec.shape == "slab" and #m.targets > 0 then
      return Fx.drawSlab(G, m, u, imp, now)
    end
    for ti, t in ipairs(m.targets) do
      local seed = m.seed + ti * 3.1
      if m.kind == "beam" then
        -- a stream from the user's middle to the target, growing to it, flickering, fading
        local grow = min(1, u / imp)
        local fade = u > 0.75 and (1 - (u - 0.75) / 0.25) or 1
        local ex, ey = f.x + (t.x - f.x) * grow, f.y + (t.y - f.y) * grow
        local wdt = t.s * 0.16 * scale * (0.85 + 0.15 * sin(now * 40 + ti))
        G.setLineWidth(wdt * 2.2)
        G.setColor(tc[1], tc[2], tc[3], 0.35 * fade)
        G.line(f.x, f.y, ex, ey)
        G.setLineWidth(wdt)
        G.setColor(tc[1], tc[2], tc[3], 0.9 * fade)
        G.line(f.x, f.y, ex, ey)
        G.setLineWidth(wdt * 0.35)
        G.setColor(1, 1, 1, 0.9 * fade)
        G.line(f.x, f.y, ex, ey)
        G.setLineWidth(1)
      elseif m.kind == "shot" then
        local n = spec.n or 1
        for k = 1, n do
          local delay = (k - 1) * 0.08
          local g = (u - delay) / max(0.05, imp - delay * 0.5)
          if g > 0 and g < 1 then
            local x = f.x + (t.x - f.x) * g + (rnd(seed, k) - 0.5) * t.s * 0.4 * sin(g * pi)
            local y = f.y + (t.y - f.y) * g - t.s * 0.5 * sin(g * pi)
            local r = t.s * 0.1 * scale * (spec.big and 2 or 1) * (0.7 + 0.6 * g)
            shapeAt(G, spec.shape or "ball", x, y, r, now * 8 + k, tc, 1)
          end
        end
      elseif m.kind == "drop" then
        -- a shadow growing under the target, then the thing falling onto it, a dust ring as it lands
        local land = t.y + t.s * 0.45
        local fall = min(1, u / imp)
        local n = (spec.shape == "rock" or spec.shape == "coin") and (spec.n or 3) or 1
        G.setColor(0, 0, 0, 0.35 * fall)
        G.ellipse("fill", t.x, land, t.s * 0.6 * fall * scale, t.s * 0.14 * fall * scale, 24)
        for k = 1, n do
          local ox = n > 1 and (rnd(seed, k) - 0.5) * t.s * 0.9 or 0
          local lag = n > 1 and rnd(seed, k + 7) * 0.12 or 0
          local ff = min(1, max(0, (u - lag) / imp))
          if u < imp + 0.15 then
            local top = t.y - t.s * 2.6
            local y = top + (t.y - top) * ff * ff
            fallingThing(G, spec.shape or "rock", t.x + ox, y, t.s * scale, tc, 1)
          end
        end
        if u >= imp then
          local v = (u - imp) / (1 - imp)
          G.setColor(0.7, 0.6, 0.45, 0.6 * (1 - v))
          G.setLineWidth(max(1, t.s * 0.04))
          G.ellipse("line", t.x, land, t.s * (0.4 + 1.1 * v) * scale, t.s * (0.1 + 0.25 * v) * scale, 32)
          G.setLineWidth(1)
          if spec.shape == "slab" and v < 0.6 then
            fallingThing(G, "slab", t.x, t.y + t.s * 0.05, t.s * scale, tc, 1 - v / 0.6)
          end
        end
      elseif m.kind == "slam" or m.kind == "multi" then
        -- the strikes land on it: the striking shape closing in, then an impact star
        local n = m.kind == "multi" and (spec.n or 3) or 1
        for k = 1, n do
          local at = m.kind == "multi" and ((k - 1) / n * 0.85 + 0.05) or imp
          local v = (u - at) / 0.25
          if v >= -0.6 and v <= 1 then
            local jx = n > 1 and (rnd(seed, k) - 0.5) * t.s * 0.5 or 0
            local jy = n > 1 and (rnd(seed, k + 3) - 0.5) * t.s * 0.4 or 0
            if v < 0 then
              local c = 1 + v / 0.6
              fallingThing(G, spec.shape or "fist", t.x + jx + (f.x - t.x) * (1 - c) * 0.3,
                t.y + jy + (f.y - t.y) * (1 - c) * 0.3, t.s * 0.55 * scale, tc, c * 0.8)
            else
              G.setColor(1, 1, 1, 0.9 * (1 - v))
              star(G, t.x + jx, t.y + jy, t.s * (0.3 + 0.35 * v) * scale, t.s * 0.12 * scale, 8, 0.4)
            end
          end
        end
      elseif m.kind == "slash" then
        G.setLineWidth(max(2, t.s * 0.045 * scale))
        for k = 0, 2 do
          local g = min(1, max(0, (u - k * 0.06) / imp))
          if g > 0 and u < 0.85 then
            local x0, y0 = t.x - t.s * 0.5 + k * t.s * 0.22, t.y - t.s * 0.55
            local x1, y1 = x0 + t.s * 0.5, y0 + t.s * 1.0
            G.setColor(1, 1, 1, 0.95 * (1 - max(0, u - 0.5) / 0.35))
            G.line(x0, y0, x0 + (x1 - x0) * g, y0 + (y1 - y0) * g)
            G.setColor(tc[1], tc[2], tc[3], 0.5 * (1 - u))
            G.line(x0 + 3, y0, x0 + 3 + (x1 - x0) * g, y0 + (y1 - y0) * g)
          end
        end
        G.setLineWidth(1)
      elseif m.kind == "bite" then
        -- fangs: an upper and a lower row closing on it
        local c = min(1, u / imp)
        local gap = t.s * 0.55 * (1 - c) * scale
        local wdt = t.s * 0.9 * scale
        local a = u < 0.8 and 1 or (1 - (u - 0.8) / 0.2)
        G.setColor(0.98, 0.98, 1, a)
        for k = 0, 3 do
          local x0 = t.x - wdt / 2 + k * wdt / 4
          G.polygon("fill", x0, t.y - gap - t.s * 0.25, x0 + wdt / 4, t.y - gap - t.s * 0.25, x0 + wdt / 8, t.y - gap)
          G.polygon("fill", x0, t.y + gap + t.s * 0.25, x0 + wdt / 4, t.y + gap + t.s * 0.25, x0 + wdt / 8, t.y + gap)
        end
      elseif m.kind == "bolt" then
        local flick = (floor(u * 16) % 2 == 0) and 1 or 0.45
        local a = (u < 0.75 and 1 or (1 - (u - 0.75) / 0.25)) * flick
        G.setColor(1, 1, 0.6, 0.25 * a)
        G.rectangle("fill", t.x - t.s * 0.25 * scale, -10, t.s * 0.5 * scale, t.y + 10)
        G.setLineWidth(max(2, t.s * 0.05 * scale))
        G.setColor(1, 0.95, 0.35, a)
        bolt(G, t.x + (rnd(seed, 1) - 0.5) * t.s * 0.3, -10, t.x, t.y, seed + floor(u * 8), t.s * 0.45)
        G.setLineWidth(max(1, t.s * 0.02 * scale))
        G.setColor(1, 1, 1, a)
        bolt(G, t.x + (rnd(seed, 1) - 0.5) * t.s * 0.3, -10, t.x, t.y, seed + floor(u * 8), t.s * 0.45)
        G.setLineWidth(1)
      elseif m.kind == "rings" then
        G.setLineWidth(max(1.5, t.s * 0.035 * scale))
        for k = 0, 3 do
          local g = u * 1.3 - k * 0.12
          if g > 0 and g < 1 then
            local x, y = f.x + (t.x - f.x) * g, f.y + (t.y - f.y) * g
            local r = t.s * (0.2 + 0.4 * g) * scale
            if spec.shape == "eye" then
              G.setColor(1, 0.3, 0.3, 0.9 * (1 - g))
              G.ellipse("line", x, y, r, r * 0.45, 24)
              G.circle("fill", x, y, r * 0.18, 12)
            else
              G.setColor(tc[1], tc[2], tc[3], 0.9 * (1 - g))
              G.ellipse("line", x, y, r, r * 0.8, 28)
            end
          end
        end
        G.setLineWidth(1)
      elseif m.kind == "powder" then
        for k = 1, 16 do
          local g = min(1, u / imp + rnd(seed, k) * 0.2)
          local x = f.x + (t.x - f.x) * g + (rnd(seed, k + 5) - 0.5) * t.s * (0.4 + 0.8 * g)
          local y = f.y + (t.y - f.y) * g + (rnd(seed, k + 9) - 0.5) * t.s * 0.6 * g + sin(now * 3 + k) * t.s * 0.05
          local a = 0.75 * (u < 0.7 and 1 or (1 - (u - 0.7) / 0.3))
          if spec.shape == "heart" then
            G.setColor(1, 0.5, 0.7, a)
            G.circle("fill", x - t.s * 0.03, y, t.s * 0.035, 10)
            G.circle("fill", x + t.s * 0.03, y, t.s * 0.035, 10)
            G.polygon("fill", x - t.s * 0.065, y + t.s * 0.01, x + t.s * 0.065, y + t.s * 0.01, x, y + t.s * 0.08)
          else
            local c
            if spec.shape == "sand" then c = { 0.8, 0.68, 0.45 }
            elseif spec.shape == "smoke" then c = { 0.45, 0.45, 0.5 }
            elseif spec.shape == "gas" then c = { 0.6, 0.35, 0.75 }
            else c = { 0.85, 0.85, 0.6 } end
            G.setColor(c[1], c[2], c[3], a)
            G.circle("fill", x, y, t.s * (0.05 + 0.06 * rnd(seed, k + 13)) * scale, 12)
          end
        end
      elseif m.kind == "drain" then
        -- a hit, then orbs drawn from the target back into the user
        for k = 1, 8 do
          local g = (u - 0.3 - k * 0.05) / 0.55
          if g > 0 and g < 1 then
            local x = t.x + (f.x - t.x) * g + sin(g * pi * 2 + k) * t.s * 0.2
            local y = t.y + (f.y - t.y) * g - sin(g * pi) * t.s * 0.4
            G.setColor(0.5, 1, 0.5, 0.9 * (1 - g * 0.5))
            G.circle("fill", x, y, t.s * 0.05, 12)
          end
        end
      elseif m.kind == "spikes" then
        local base = t.y + t.s * 0.45
        local g = min(1, max(0, (u - imp * 0.6) / (imp * 0.4)))
        local a = u < 0.8 and 1 or (1 - (u - 0.8) / 0.2)
        for k = -3, 3 do
          local x = t.x + k * t.s * 0.16
          local hgt = t.s * (0.5 + 0.35 * rnd(seed, k + 4)) * g * scale
          if spec.shape == "root" then G.setColor(0.45, 0.32, 0.18, a)
          elseif spec.shape == "steel" then G.setColor(0.75, 0.8, 0.88, a)
          else G.setColor(0.58, 0.46, 0.32, a) end
          G.polygon("fill", x - t.s * 0.07, base, x + t.s * 0.07, base, x + (rnd(seed, k) - 0.5) * t.s * 0.1, base - hgt)
        end
      end
    end
    -- round the user alone: an aura rising (a stat raised); a wave over the whole party
    if m.kind == "self" then
      local a = sin(u * pi)
      G.setColor(tc[1], tc[2], tc[3], 0.3 * a)
      G.ellipse("fill", f.x, f.y, f.s * 0.6, f.s * 0.7, 32)
      G.setLineWidth(max(1.5, f.s * 0.02))
      for k = 1, 6 do
        local x = f.x + (k - 3.5) * f.s * 0.15
        local y = f.y + f.s * 0.4 - ((u * 1.5 + k * 0.17) % 1) * f.s
        G.setColor(1, 1, 1, 0.8 * a)
        G.line(x, y, x, y - f.s * 0.12)
        G.line(x - f.s * 0.04, y - f.s * 0.08, x, y - f.s * 0.12, x + f.s * 0.04, y - f.s * 0.08)
      end
      G.setLineWidth(1)
    elseif m.kind == "wave" then
      local W, H = G.getWidth(), G.getHeight()
      local a = u < 0.8 and 1 or (1 - (u - 0.8) / 0.2)
      if spec.shape == "sound" or spec.shape == "light" then
        G.setLineWidth(max(2, H * 0.006))
        for k = 0, 3 do
          local g = u * 1.4 - k * 0.15
          if g > 0 and g < 1 then
            G.setColor(tc[1], tc[2], tc[3], 0.8 * (1 - g) * a)
            G.ellipse("line", f.x, f.y, W * 0.9 * g, H * 0.6 * g, 48)
          end
        end
        G.setLineWidth(1)
      else
        local c
        if spec.shape == "fire" then c = { 1, 0.45, 0.1 }
        elseif spec.shape == "ground" then c = { 0.6, 0.45, 0.3 }
        elseif spec.shape == "wind" then c = { 0.85, 0.92, 1 }
        else c = { 0.3, 0.6, 1 } end
        local ylead = H * (0.3 + 0.8 * min(1, u / imp))
        local depth = H * 0.22
        if spec.shape == "fire" and Fx.fireRect(G, 0, ylead - depth * 2.6, W, depth * 2.8, now, m.seed, a) then
          -- (a wall of real fire rolling toward the camera)
        elseif spec.shape == "fire" then
          -- a wall of flames rolling toward the camera, a glow behind it
          G.setColor(1, 0.4, 0.1, 0.3 * a)
          G.rectangle("fill", 0, ylead - depth * 1.4, W, depth * 1.4)
          for i = 0, 30 do
            local x = (i + 0.5) / 30 * W
            local fh = depth * (1 + 0.45 * sin(now * 9 + i * 1.9))
            G.setColor(1, 0.35 + 0.2 * sin(i), 0.08, 0.8 * a)
            flame(G, x, ylead, W / 50, fh)
            G.setColor(1, 0.85, 0.35, 0.8 * a)
            flame(G, x, ylead, W / 110, fh * 0.55)
          end
        elseif spec.shape == "wind" then
          G.setLineWidth(max(2, H * 0.005))
          for i = 1, 26 do
            local y = ylead - depth * (rnd(m.seed, i))
            local x0 = ((rnd(m.seed, i + 40) + u * 1.5) % 1.2 - 0.2) * W
            G.setColor(0.9, 0.95, 1, 0.7 * a)
            G.line(x0, y, x0 + W * 0.18, y + sin(i) * H * 0.01)
          end
        else
          -- a body of water (or a front of dust) with a curling crest and foam
          local c
          if spec.shape == "ground" then c = { 0.55, 0.42, 0.28 } else c = { 0.25, 0.55, 1 } end
          local n = 40
          for i = 0, n - 1 do
            local x0, x1 = i / n * W, (i + 1) / n * W
            local y0 = ylead + sin(i * 0.45 + now * 7) * H * 0.025
            local y1 = ylead + sin((i + 1) * 0.45 + now * 7) * H * 0.025
            G.setColor(c[1], c[2], c[3], 0.65 * a)
            G.polygon("fill", x0, y0 - depth, x1, y1 - depth, x1, y1, x0, y0)
            G.setColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.8, 0.5 * a)
            G.polygon("fill", x0, y0 - depth * 0.35, x1, y1 - depth * 0.35, x1, y1, x0, y0)
          end
          for i = 1, 24 do
            local x = rnd(m.seed, i) * W
            local y = ylead - depth + sin(now * 6 + i) * H * 0.02
            G.setColor(1, 1, 1, 0.7 * a)
            G.circle("fill", x, y, H * (0.008 + 0.01 * rnd(m.seed, i + 9)), 10)
          end
          G.setColor(1, 1, 1, 0.75 * a)
          G.setLineWidth(max(2, H * 0.006))
          local crest = {}
          for i = 0, n do crest[#crest + 1] = i / n * W; crest[#crest + 1] = ylead - depth + sin(i * 0.45 + now * 7) * H * 0.025 end
          G.line(crest)
        end
        G.setLineWidth(1)
      end
    end
  end

  -- each move's hits at its impact (from Fx.update)
  local function landMoves(now)
    for i = #moves, 1, -1 do
      local m = moves[i]
      if m.impact and m.hits == 0 and now - m.t0 >= m.impact then
        m.hits = 1
        for _, t in ipairs(m.targets) do Fx.hit(m.type, t.x, t.y, t.s, m.big, now) end
      end
      if now - m.t0 > m.len then table.remove(moves, i) end
    end
  end
  Fx.landMoves = landMoves
  function Fx.drawMoves(G, now)
    G.push("all")
    for _, m in ipairs(moves) do drawMove(G, m, now) end
    G.pop()
  end
  function Fx.busy(now)
    for _, m in ipairs(moves) do if now - m.t0 <= m.len then return true end end
    return false
  end
  local clearHits = Fx.clear
  function Fx.clear() clearHits(); for i = #moves, 1, -1 do moves[i] = nil end end

  return Fx
end
