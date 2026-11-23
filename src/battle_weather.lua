-- The weather and the terrain over the game's own battles, as long as they last: the cart shows its
-- weather only in its animation at each turn's end, and a terrain (WoobleDex's) not at all. Drawn at
-- the window's resolution from main's render.hud, over the battle's field (the game's picture down
-- to the top of its bar), clipped to it:
--   RAIN   streaks slanting down          SUN    a warm light, a glow and rays from the top left
--   SAND   dust streaking across, a haze  HAIL   ice falling, drifting
--   a terrain: the ground lit in its colour under each Pokemon on the field (its feet: WoobleView's
--   box when it reports one, else the battle's own places), breathing, with its pieces about it -
--   ELECTRIC sparks, GRASSY blades, MISTY mist, PSYCHIC motes rising.
-- Each fades in as it comes and out as it goes (one to another: the old out, the new in). Every piece
-- at a fixed spot by its index, moving on the clock: nothing made a frame.
-- Not drawn while a screen of the battle's (the Bag, the party, a summary) is over it, nor during the
-- Dynamax scene, nor in a raid; and not where WoobleView's 3D scene draws the battle's weather and
-- terrain itself (its exports.battleWeatherDrawn()).
--   BW = battle_weather(mod, { ui = DmaxUi, dex = function() -> national_dex_gen3 exports })
--   BW.draw(viewport) ; BW.last (drivers: { weather, terrain, pads, drew })

return function(mod, deps)
  local U = deps.ui
  local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

  local BW = {
    -- a piece's spot: [0, 1) from its seed and index
    FADE_S = 0.6,
    -- (the cart's battle grounds are light: the pieces laid over them, deep enough to show)
    RAIN = { N = 80, PER = { 0.55, 0.85 }, LEN = 0.09, SLANT = 0.025, W = 0.004, C = { 0.42, 0.58, 0.9 }, A = 0.6,
      WASH = { 0.16, 0.22, 0.36, 0.18 } },
    HAIL = { N = 55, PER = { 1.1, 1.6 }, DRIFT = 0.05, SIZE = 0.012, C = { 0.88, 0.96, 1 }, A = 0.95,
      RIM = { 0.4, 0.55, 0.72 },
      WASH = { 0.72, 0.86, 1, 0.1 } },
    SAND = { N = 80, PER = { 0.9, 1.4 }, LEN = 0.14, W = 0.006, C = { 0.9, 0.74, 0.48 }, A = 0.55,
      WASH = { 0.78, 0.6, 0.34, 0.22 } },
    SUN = { WASH = { 1, 0.7, 0.36, 0.12 }, RAYS = 5, RAY_A = 0.1, GLOW = { 1, 0.86, 0.55, 0.35 } },
    TERRAIN = {
      ELECTRIC = { 1, 0.88, 0.22 }, GRASSY = { 0.36, 0.92, 0.38 }, MISTY = { 1, 0.62, 0.86 },
      PSYCHIC = { 0.8, 0.42, 1 },
      -- the lit ground: an ellipse PAD of the Pokemon's width across, FLAT as deep, laid over the
      -- ground in rings of A each (deepest in the middle); PIECES about each; ELECTRIC's sparks over
      -- a dark RIM
      PAD = 1.5, FLAT = 0.28, A = 0.12, PIECES = 14, RIM = { 0.5, 0.38, 0.05 },
    },
    -- the battle's own places (the cart's sprite centres, its 64-pixel pictures): the feet FEET
    -- pixels under a player's centre, FOE_FEET under a foe's
    FEET = 30, FOE_FEET = 26, PIC = 64,
  }
  BW.last = { weather = nil, terrain = nil, pads = 0, drew = 0, barRow = 112 }

  local E = {}
  local function engine()
    if E.Battle then return E end
    local function req(n) local ok, m = pcall(require, n); return ok and type(m) == "table" and m or nil end
    E.Battle = req("src.core.game3.battle")
    E.Rules = req("src.core.game3.battle.rules")
    E.Coords = req("src.core.game3.battle.anim_coords")
    E.State = req("src.core.game3.battle.state")
    return E
  end
  local wv = nil
  local function woobleView()
    if wv == nil then
      local ok, m = pcall(mod.find, mod, "gen3-hd-sprites")
      wv = ok and type(m) == "table" and type(m.exports) == "table" and m.exports or false
    end
    return wv or nil
  end

  local function rnd(seed, k) return (sin(seed * 12.9898 + k * 78.233) * 43758.5453) % 1 end
  local function perOf(R, j, seed) return R[1] + (R[2] - R[1]) * rnd(seed, j) end

  -- what shows: the kind now, since when; the last one, fading since when
  local shown = {
    weather = { kind = nil, t0 = 0, was = nil, off = 0 },
    terrain = { kind = nil, t0 = 0, was = nil, off = 0 },
  }
  local function follow(s, kind, now)
    if kind ~= s.kind then
      if s.kind then s.was, s.off = s.kind, now end
      s.kind, s.t0 = kind, now
    end
  end
  local function inA(s, now) return min(1, (now - s.t0) / BW.FADE_S) end
  local function outA(s, now)
    if not s.was then return 0 end
    local a = 1 - (now - s.off) / BW.FADE_S
    if a <= 0 then s.was = nil return 0 end
    return a
  end

  -- the field: the game's picture down to its bar's top - the cart's at row 112, WoobleView's own
  -- bar's where it says (exports.barTop), the picture's foot when the battle draws no bar (Kanto
  -- Gear's GEAR views, OmniUI, our Max Move pad)
  BW.BAR_TOP = 112
  local R = { x = 0, y = 0, w = 1, h = 1 }
  local function barRow()
    if U.bottomShown and not U.bottomShown() then return 160 end
    local W = woobleView()
    if W and type(W.barTop) == "function" then
      local ok, row = pcall(W.barTop)
      if ok and tonumber(row) then return tonumber(row) end
    end
    return BW.BAR_TOP
  end
  local function field(viewport)
    local x0, y0 = U.uiPoint(0, 0)
    local row = barRow()
    BW.last.barRow = row
    local x1, y1 = U.uiPoint(240, row)
    if not x0 then return false end
    if type(viewport) == "table" and tonumber(viewport.gameWidth) then
      -- (WoobleView's Fill Screen docks the UI: the battle's picture is the game's whole rect)
      local gx, gy, gw = tonumber(viewport.gameX) or 0, tonumber(viewport.gameY) or 0, tonumber(viewport.gameWidth)
      x0, x1, y0 = min(x0, gx), max(x1, gx + gw), min(y0, gy)
    end
    R.x, R.y, R.w, R.h = x0, y0, max(1, x1 - x0), max(1, y1 - y0)
    return true
  end

  -- ------- the weather

  local function drawWeather(G, kind, a, now)
    local D = BW[kind]
    if not D or a <= 0 then return end
    local x0, y0, W, H = R.x, R.y, R.w, R.h
    local C = D.WASH
    if kind == "SUN" then
      G.setBlendMode("add")
      G.setColor(C[1], C[2], C[3], C[4] * a * (0.85 + 0.15 * sin(now * 1.3)))
      G.rectangle("fill", x0, y0, W, H)
      local g = D.GLOW
      for i = 6, 1, -1 do
        G.setColor(g[1], g[2], g[3], g[4] * a * 0.18)
        G.circle("fill", x0 + W * 0.1, y0, H * 0.75 * i / 6, 32)
      end
      for q = 1, D.RAYS do
        local f = (q - 0.5) / D.RAYS
        local sway = 0.03 * sin(now * 0.4 + q * 1.7)
        local bx = x0 + W * (-0.05 + 1.2 * (f + sway))
        local hw = H * (0.07 + 0.06 * rnd(31, q))
        G.setColor(1, 0.86, 0.56, D.RAY_A * a * (0.7 + 0.3 * sin(now * 0.9 + q)))
        G.polygon("fill", x0 + W * 0.1, y0, bx - hw, y0 + H * 1.05, bx + hw, y0 + H * 1.05)
      end
      G.setBlendMode("alpha")
      return
    end
    G.setColor(C[1], C[2], C[3], C[4] * a)
    G.rectangle("fill", x0, y0, W, H)
    if kind == "RAIN" then
      G.setLineWidth(max(1, H * D.W))
      G.setColor(D.C[1], D.C[2], D.C[3], D.A * a)
      local len, sl = H * D.LEN, H * D.SLANT
      for j = 1, D.N do
        local u = (now / perOf(D.PER, j, 1) + rnd(2, j)) % 1
        local x = x0 + (W + sl) * rnd(3, j) - sl * u
        local y = y0 - len + (H + len) * u
        G.line(x, y, x + sl * 0.3, y - len)
      end
    elseif kind == "HAIL" then
      for j = 1, D.N do
        local u = (now / perOf(D.PER, j, 11) + rnd(12, j)) % 1
        local s = max(1.5, H * D.SIZE * (0.7 + 0.6 * rnd(13, j)))
        local x = x0 + W * rnd(14, j) + W * D.DRIFT * u
        local y = y0 - s + (H + 2 * s) * u
        G.setColor(D.C[1], D.C[2], D.C[3], D.A * a)
        G.polygon("fill", x, y - s, x + s * 0.8, y, x, y + s, x - s * 0.8, y)
        G.setLineWidth(1)
        G.setColor(D.RIM[1], D.RIM[2], D.RIM[3], D.A * a * 0.8)
        G.polygon("line", x, y - s, x + s * 0.8, y, x, y + s, x - s * 0.8, y)
        G.setColor(1, 1, 1, a * 0.9)
        G.rectangle("fill", x - s * 0.25, y - s * 0.45, s * 0.35, s * 0.35)
      end
    elseif kind == "SAND" then
      G.setLineWidth(max(1, H * D.W))
      local len = W * D.LEN
      for j = 1, D.N do
        local u = (now / perOf(D.PER, j, 21) + rnd(22, j)) % 1
        local x = x0 - len + (W + 2 * len) * u
        local y = y0 + H * (0.15 + 0.85 * rnd(23, j))
        G.setColor(D.C[1], D.C[2], D.C[3], D.A * a * sin(u * pi))
        G.line(x, y, x - len, y + H * 0.01)
      end
    end
    G.setLineWidth(1)
  end

  -- ------- the terrain: where each Pokemon on the field stands

  local pads = {}
  for i = 1, 4 do pads[i] = { x = 0, y = 0, w = 0 } end
  local nPads = 0
  local function addPad(x, y, w)
    nPads = nPads + 1
    local p = pads[nPads]
    p.x, p.y, p.w = x, y, w
  end
  local WV_KEYS = { [0] = "player", [1] = "enemy" }
  local function findPads(st)
    nPads = 0
    local W = woobleView()
    for id = 0, (st.double and 3 or 1) do
      local b = E.State and E.State.battler and E.State.battler(st, id)
      local mon = b and b.mon
      if mon and (tonumber(mon.hp) or 0) > 0 then
        local x0, y0, x1, y1
        if W and W.battlerRect then
          local ok, a1, b1, c1, d1 = pcall(W.battlerRect, st.double and id or WV_KEYS[id])
          if ok and a1 then x0, y0, x1, y1 = a1, b1, c1, d1 end
        end
        if x0 then
          addPad((x0 + x1) / 2, y1, x1 - x0)
        else
          local c = E.Coords and E.Coords.coords and E.Coords.coords(st, id)
          local cx, cy = c and (c.x or c[1]), c and (c.y or c[2])
          if not cx then
            local t = st.double and E.Coords and E.Coords.DOUBLES or E.Coords and E.Coords.SINGLES
            local p = t and t[id]
            cx, cy = p and (p.x or p[1]), p and (p.y or p[2])
          end
          if cx and cy then
            local feet = cy + (id % 2 == 0 and BW.FEET or BW.FOE_FEET)
            local sx, sy, k = U.uiPoint(cx, feet)
            if sx then addPad(sx, sy, BW.PIC * 0.7 * k) end
          end
        end
      end
    end
    return nPads
  end
  local function ellipseGlow(G, x, y, rx, ry, cr, cg, cb, a)
    for i = 6, 1, -1 do
      G.setColor(cr, cg, cb, a)
      G.ellipse("fill", x, y, rx * i / 6, ry * i / 6, 28)
    end
  end
  local function drawTerrain(G, kind, a, now)
    local T = BW.TERRAIN
    local C = T[kind]
    if not C or a <= 0 then return end
    for i = 1, nPads do
      local p = pads[i]
      local rx = p.w * T.PAD * 0.5
      local ry = rx * T.FLAT
      ellipseGlow(G, p.x, p.y, rx, ry, C[1], C[2], C[3], T.A * a * (0.8 + 0.2 * sin(now * 1.6 + i)))
      for j = 1, T.PIECES do
        local an = 2 * pi * rnd(41 + i, j)
        local rr = 0.35 + 0.65 * rnd(51 + i, j)
        local px, py = p.x + cos(an) * rx * rr, p.y + sin(an) * ry * rr
        if kind == "ELECTRIC" then
          local u = (now * (1.6 + rnd(61, j)) + rnd(62 + i, j)) % 1
          if u < 0.22 then
            local f = 1 - u / 0.22
            local s = rx * 0.12
            local Rm = T.RIM
            G.setLineWidth(max(2, rx * 0.04))
            G.setColor(Rm[1], Rm[2], Rm[3], a * f * 0.8)
            G.line(px, py, px + s * 0.4, py - s * 0.7, px + s * 0.7, py - s * 0.2, px + s * 1.1, py - s * 0.6)
            G.setLineWidth(max(1, rx * 0.02))
            G.setColor(C[1], C[2], C[3], a * f)
            G.line(px, py, px + s * 0.4, py - s * 0.7, px + s * 0.7, py - s * 0.2, px + s * 1.1, py - s * 0.6)
          end
        elseif kind == "GRASSY" then
          local h = ry * (0.5 + 0.5 * rnd(71 + i, j))
          local sway = rx * 0.03 * sin(now * 1.8 + j)
          G.setLineWidth(max(1, rx * 0.025))
          G.setColor(C[1] * 0.8, C[2] * 0.85, C[3] * 0.7, a * 0.85)
          G.line(px, py, px + sway, py - h)
          G.line(px + rx * 0.02, py, px + rx * 0.05 + sway, py - h * 0.75)
        elseif kind == "MISTY" then
          local u = (now * 0.15 + rnd(81 + i, j)) % 1
          G.setColor(C[1], C[2], C[3], a * 0.3 * sin(u * pi))
          G.ellipse("fill", px + rx * 0.2 * sin(u * 2 * pi), py - ry * 0.3, rx * 0.22, ry * 0.5, 20)
        elseif kind == "PSYCHIC" then
          local u = (now * 0.3 + rnd(91 + i, j)) % 1
          G.setColor(C[1], C[2], C[3], a * 0.8 * sin(u * pi))
          G.circle("fill", px + rx * 0.04 * sin(now * 2 + j), py - ry * 3 * u, max(1, rx * 0.025), 10)
        end
      end
    end
    G.setBlendMode("alpha")
    G.setLineWidth(1)
  end

  local function terrainOf(st)
    local dx = deps.dex and deps.dex()
    local B = dx and dx.battle
    if B and type(B.terrainOf) == "function" then
      local ok, k = pcall(B.terrainOf, st)
      if ok then return k end
    end
    local f = st.__ndxField
    return f and (f.terrainTurns or 0) > 0 and f.terrain or nil
  end

  function BW.draw(viewport)
    engine()
    local L = BW.last
    local Battle = E.Battle
    local st = Battle and Battle.isActive and Battle.isActive() and Battle.getState and Battle.getState() or nil
    local now = love.timer and love.timer.getTime() or 0
    if not st then
      follow(shown.weather, nil, now)
      follow(shown.terrain, nil, now)
      shown.weather.was, shown.terrain.was = nil, nil
      L.weather, L.terrain = nil, nil
      return
    end
    local wk = E.Rules and E.Rules.weather and E.Rules.weather.kind and E.Rules.weather.kind(st.weather) or nil
    local tk = terrainOf(st)
    follow(shown.weather, wk, now)
    follow(shown.terrain, tk, now)
    L.weather, L.terrain = wk, tk
    if not (shown.weather.kind or shown.weather.was or shown.terrain.kind or shown.terrain.was) then return end
    if (U.screenOver and U.screenOver()) or (U.sceneOn and U.sceneOn()) then return end
    local W = woobleView()
    if W and type(W.battleWeatherDrawn) == "function" then
      local ok, drawn = pcall(W.battleWeatherDrawn)
      if ok and drawn then return end
    end
    if U.noteUiMap then pcall(U.noteUiMap) end
    if not field(viewport) then return end
    local G = love.graphics
    G.push("all")
    G.origin()
    G.setShader()
    G.setScissor(floor(R.x), floor(R.y), math.ceil(R.w), math.ceil(R.h))
    L.pads = findPads(st)
    local tS = shown.terrain
    if tS.kind then drawTerrain(G, tS.kind, inA(tS, now), now) end
    if tS.was then drawTerrain(G, tS.was, outA(tS, now), now) end
    local wS = shown.weather
    if wS.kind then drawWeather(G, wS.kind, inA(wS, now), now) end
    if wS.was then drawWeather(G, wS.was, outA(wS, now), now) end
    G.pop()
    L.drew = L.drew + 1
  end

  return BW
end
