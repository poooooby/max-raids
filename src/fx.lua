-- The raid's move effects, drawn in code over the den in its own 3D space (no art):
--   * every effect lives at world points (metres, the den's: y up, the party toward +z) and is
--     projected through the den's camera each frame (deps.Scene.project), so it scales with depth and
--     holds still as the camera moves
--   * three layers, by depth: "back" (the ground and what stands behind the boss: drawn before the
--     boss), "mid" (between the boss and the party: before the members), "front" (over everything);
--     the den calls Fx.drawLayer for the first two (Sc.onBack / Sc.onMid), the raid Fx.draw after
--   * shaders for fire, rock, energy beams, glowing orbs, smoke / dust and walls of water or sand;
--     world particles (sparks, embers, dust, smoke, debris, drops, leaves, shards, bubbles, twinkles,
--     wisps, coins, rings) with gravity, drag and a bounce on the ground; decals on the ground
--     (scorch, cracks, frost, wet)
--   * an impact: the type's hit at the target, a flash, and Fx.onImpact(anchor, power, type, big) for
--     the raid (its hit-stop, the camera's jab and shake, the target flashing and knocked back)
-- An anchor is { X, Y (its middle), Z, h (its height), foot (its ground's height), boss, i, frac
-- (the share of its HP the move takes; nil = no damage) }.
--   Fx = fx({ Scene = Sc }) ; Fx.move(spec, typeName, fromAnchor, targetAnchors, now, big)
--   Fx.charge(anchor, now, dur) ; Fx.update(now) ; Fx.drawLayer(G, layer, now) ; Fx.draw(G, w, h, now)

return function(deps)
  deps = deps or {}
  local Fx = {}
  local Sc = deps.Scene
  local sin, cos, pi, max, min, floor, abs, sqrt = math.sin, math.cos, math.pi, math.max, math.min, math.floor,
    math.abs, math.sqrt
  local G = love and love.graphics

  local function rnd(seed, k) return (sin(seed * 12.9898 + k * 78.233) * 43758.5453) % 1 end
  local function smooth(e0, e1, x)
    local t = min(1, max(0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
  end

  -- a world point on screen: x, y and pixels per metre there (nil behind the eye)
  local function P(X, Y, Z)
    if not (Sc and Sc.project) then return nil end
    local x, y, d = Sc.project(X, Y, Z)
    if not x then return nil end
    return x, y, Sc.cam.F / d
  end
  Fx.P = P

  -- which layer a depth draws in (see the header)
  local function layerOf(Z)
    local pz = Sc and Sc.PAD and Sc.PAD.z or -9.2
    if Z < pz - 0.6 then return "back" elseif Z < -1.6 then return "mid" end
    return "front"
  end
  Fx.layerOf = layerOf

  local TINT = {
    FIRE = { 1, 0.45, 0.12 }, WATER = { 0.3, 0.62, 1 }, ELECTRIC = { 1, 0.88, 0.25 }, GRASS = { 0.4, 0.85, 0.3 },
    ICE = { 0.6, 0.9, 1 }, ROCK = { 0.72, 0.58, 0.38 }, GROUND = { 0.8, 0.62, 0.36 }, POISON = { 0.72, 0.32, 0.88 },
    PSYCHIC = { 1, 0.38, 0.72 }, DARK = { 0.45, 0.22, 0.55 }, GHOST = { 0.55, 0.38, 0.9 }, DRAGON = { 0.45, 0.4, 1 },
    FAIRY = { 1, 0.6, 0.85 }, FIGHTING = { 1, 0.5, 0.2 }, FLYING = { 0.8, 0.9, 1 }, BUG = { 0.65, 0.88, 0.25 },
    STEEL = { 0.82, 0.88, 0.95 }, NORMAL = { 1, 0.96, 0.88 },
  }
  Fx.TINT = TINT

  -- ------- shaders (made on first use; nil where the device cannot: plain shapes stand in)

  local NOISE = [[
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0; float a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
  return v;
}
]]
  -- fire: flames rising off the rect's foot (tc 0..1 across it, y down)
  local FIRE_GLSL = NOISE .. [[
extern number time;
extern number seed;
extern number aspect;
extern number blaze;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float h = 1.0 - tc.y;
  float side = abs(tc.x - 0.5) * 2.0;
  vec2 q = vec2(tc.x * aspect * 2.2 + seed, tc.y * 2.2 + time * 1.7);
  float n = fbm(q);
  float n2 = fbm(q * 2.1 + vec2(seed * 0.5, time * 0.9));
  float flame = clamp(n * 1.35 + n2 * 0.45 - h * 1.55 + 0.25 - blaze * side * side * (0.9 + 0.8 * h), 0.0, 1.0);
  flame *= smoothstep(1.0, 0.82, side) * mix(1.0, smoothstep(1.0, 0.55, side), blaze);
  vec3 col = mix(vec3(0.45, 0.02, 0.0), vec3(1.0, 0.36, 0.04), smoothstep(0.05, 0.4, flame));
  col = mix(col, vec3(1.0, 0.78, 0.25), smoothstep(0.4, 0.72, flame));
  col = mix(col, vec3(1.0, 0.98, 0.8), smoothstep(0.78, 1.0, flame));
  return vec4(col, smoothstep(0.02, 0.3, flame) * color.a);
}
]]
  -- rock: noise on the screen position over the colour drawn
  local ROCK_GLSL = NOISE .. [[
extern number scale;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = sc / scale;
  float n = fbm(p);
  float pits = smoothstep(0.62, 0.7, fbm(p * 2.7 + 3.1));
  return vec4(color.rgb * (0.7 + 0.55 * n - 0.25 * pits), color.a);
}
]]
  -- an energy beam (tc.x along it, tc.y across): a white core, a turbulent body flowing along
  local BEAM_GLSL = NOISE .. [[
extern number time;
extern vec3 tint;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float v = abs(tc.y - 0.5) * 2.0;
  float n = fbm(vec2(tc.x * 7.0 - time * 10.0, tc.y * 2.5 + time * 1.3));
  float n2 = fbm(vec2(tc.x * 15.0 - time * 16.0, tc.y * 5.0 - time));
  float body = 1.0 - smoothstep(0.25 + 0.5 * n, 0.95, v);
  float core = 1.0 - smoothstep(0.0, 0.22 + 0.12 * n2, v);
  float streak = smoothstep(0.55, 0.8, n2) * (1.0 - v);
  vec3 col = mix(tint * (0.6 + 0.6 * n), vec3(1.0), clamp(core + streak * 0.5, 0.0, 1.0));
  float a = clamp(body * (0.55 + 0.45 * n) + core + streak * 0.4, 0.0, 1.0) * color.a;
  return vec4(col, a);
}
]]
  -- a glowing orb (tc 0..1 over its square): a hot core, a swirling body, a soft halo
  local ORB_GLSL = NOISE .. [[
extern number time;
extern vec3 tint;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = tc * 2.0 - 1.0;
  float r = length(p);
  float c = cos(time * 1.7); float s = sin(time * 1.7);
  vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
  float n = fbm(q * 2.4 + vec2(0.0, -time * 1.5));
  float body = 1.0 - smoothstep(0.3 + 0.25 * n, 0.62 + 0.18 * n, r);
  float core = 1.0 - smoothstep(0.0, 0.3, r);
  float halo = 1.0 - smoothstep(0.0, 1.0, r);
  halo = halo * halo * 0.55;
  vec3 col = mix(tint * (0.7 + 0.6 * n), vec3(1.0), core * 0.85);
  return vec4(col, clamp(body * (0.6 + 0.5 * n) + halo + core, 0.0, 1.0) * color.a);
}
]]
  -- a puff of smoke or dust (tc 0..1 over its square, turned by the draw): a lumpy edge, lit from above
  local PUFF_GLSL = NOISE .. [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = tc * 2.0 - 1.0;
  float r = length(p);
  float n = fbm(tc * 3.2);
  float edge = r + (n - 0.5) * 0.7;
  float a = (1.0 - smoothstep(0.3, 1.0, edge)) * color.a;
  return vec4(color.rgb * (0.7 + 0.5 * n - 0.2 * p.y), a);
}
]]
  -- a wall of water or sand rolling forward (tc.x across, tc.y top to foot): a broken crest, spray,
  -- foam, depth darkening, glints
  local WALL_GLSL = NOISE .. [[
extern number time;
extern number aspect;
extern vec3 deep;
extern vec3 shallow;
extern vec3 foam;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float x = tc.x * aspect;
  vec2 q = vec2(x * 2.2, tc.y * 2.0 - time * 1.1);
  float w = fbm(q * 1.6 + vec2(time * 0.4, 0.0));
  float n = fbm(q + vec2(0.0, w * 1.5));
  float crest = 0.16 + 0.07 * sin(x * 4.0 + time * 4.0) + 0.05 * sin(x * 9.0 - time * 6.0) + (n - 0.5) * 0.18;
  float body = smoothstep(crest - 0.015, crest + 0.02, tc.y);
  float spray = (1.0 - smoothstep(0.0, 0.12, crest - tc.y)) * smoothstep(0.6, 0.85, fbm(vec2(x * 6.0, tc.y * 9.0 - time * 3.0)));
  float d = clamp((tc.y - crest) / max(0.05, 1.0 - crest), 0.0, 1.0);
  vec3 col = mix(shallow, deep, smoothstep(0.0, 0.8, d)) + (n - 0.5) * 0.25;
  float fo = smoothstep(0.5, 0.75, n) * (1.0 - smoothstep(0.0, 0.35, d)) + (1.0 - smoothstep(0.0, 0.06, d)) * body;
  float glint = pow(max(0.0, n - 0.55) * 2.2, 3.0);
  col = mix(col, foam, clamp(fo, 0.0, 1.0)) + glint * 0.6;
  return vec4(col, max(body * (0.82 + 0.18 * d), spray) * color.a);
}
]]
  local shaders = { tried = false }
  local SOURCES = { fire = FIRE_GLSL, rock = ROCK_GLSL, beam = BEAM_GLSL, orb = ORB_GLSL, puff = PUFF_GLSL,
    wall = WALL_GLSL }
  local function shader(name)
    if not shaders.tried then
      shaders.tried = true
      if G then
        for k, src in pairs(SOURCES) do
          local ok, s = pcall(G.newShader, src)
          if ok then shaders[k] = s end
        end
        local okI, img = pcall(function()
          local d = love.image.newImageData(1, 1)
          d:setPixel(0, 0, 1, 1, 1, 1)
          return G.newImage(d)
        end)
        if okI then shaders.texel = img end
        -- a soft round sprite (a glow, a spark's head)
        local okS, soft = pcall(function()
          local d = love.image.newImageData(64, 64)
          d:mapPixel(function(x, y)
            local dx, dy = (x + 0.5) / 32 - 1, (y + 0.5) / 32 - 1
            local a = max(0, 1 - sqrt(dx * dx + dy * dy))
            return 1, 1, 1, a * a * (3 - 2 * a)
          end)
          local im = G.newImage(d)
          im:setFilter("linear", "linear")
          return im
        end)
        if okS then shaders.soft = soft end
      end
    end
    return shaders[name]
  end
  Fx.shader = shader

  -- real fire in a rect (x, y top-left, w, h); false when the shader is out
  local function fireRect(G2, x, y, w, h, now, seed, alpha, blaze)
    local sh, tx = shader("fire"), shaders.texel
    if not (sh and tx) then return false end
    sh:send("time", now)
    sh:send("seed", seed or 0)
    sh:send("aspect", w / max(1, h))
    sh:send("blaze", blaze or 0)
    G2.setShader(sh)
    G2.setColor(1, 1, 1, alpha or 1)
    G2.draw(tx, x, y, 0, w, h)
    G2.setShader()
    return true
  end
  Fx.fireRect = fireRect

  -- a filled polygon shaded as rock; plain without the shader
  local function rockPoly(G2, pts, scale)
    local sh = shader("rock")
    if sh then
      sh:send("scale", max(1, scale or 20))
      G2.setShader(sh)
    end
    G2.polygon("fill", pts)
    G2.setShader()
  end
  Fx.rockPoly = rockPoly

  -- a soft glow at (x, y), r px out (the caller sets the blend)
  local function glowAt(G2, x, y, r, cr, cg, cb, a)
    if a <= 0 or r <= 0 then return end
    local img = shader("soft")
    G2.setColor(cr, cg, cb, a)
    if img then G2.draw(img, x, y, 0, r / 32, r / 32, 32, 32)
    else G2.circle("fill", x, y, r * 0.5, 20) end
  end

  -- an orb of energy r px out at (x, y); its soft glow without the shader
  local function orbAt(G2, x, y, r, tc, a, now)
    if a <= 0 or r <= 0 then return end
    local sh, tx = shader("orb"), shaders.texel
    if sh and tx then
      sh:send("time", now)
      sh:send("tint", tc)
      G2.setShader(sh)
      G2.setColor(1, 1, 1, a)
      G2.draw(tx, x - r, y - r, 0, r * 2, r * 2)
      G2.setShader()
    else
      glowAt(G2, x, y, r * 1.4, tc[1], tc[2], tc[3], a * 0.7)
      glowAt(G2, x, y, r * 0.6, 1, 1, 1, a)
    end
  end

  -- ------- a strip mesh, filled each draw (beams, rings, walls, claw strokes)

  local STRIP_MAX = 160
  local strip = { mesh = nil, v = {} }
  local function stripReady()
    if strip.mesh == nil then
      local ok, m = pcall(G.newMesh, STRIP_MAX, "strip", "stream")
      strip.mesh = ok and m or false
      for i = 1, STRIP_MAX do strip.v[i] = { 0, 0, 0, 0, 1, 1, 1, 1 } end
      shader("soft")
      if strip.mesh and shaders.texel then strip.mesh:setTexture(shaders.texel) end
    end
    return strip.mesh or nil
  end
  local function sv(i, x, y, u, v, r, g, b, a)
    local t = strip.v[i]
    t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = x, y, u, v, r, g, b, a
  end
  local function stripDraw(G2, n)
    local m = strip.mesh
    if not m or n < 3 then return end
    m:setVertices(strip.v, 1, n)
    m:setDrawRange(1, n)
    G2.draw(m)
  end

  -- a tapered band from (x1, y1) w1 px across to (x2, y2) w2 px across, tc.x along, tc.y across
  local function band(G2, x1, y1, w1, x2, y2, w2, r, g, b, a)
    if not stripReady() then return false end
    local dx, dy = x2 - x1, y2 - y1
    local l = sqrt(dx * dx + dy * dy) + 1e-6
    local nx, ny = -dy / l, dx / l
    sv(1, x1 + nx * w1 * 0.5, y1 + ny * w1 * 0.5, 0, 0, r, g, b, a)
    sv(2, x1 - nx * w1 * 0.5, y1 - ny * w1 * 0.5, 0, 1, r, g, b, a)
    sv(3, x2 + nx * w2 * 0.5, y2 + ny * w2 * 0.5, 1, 0, r, g, b, a)
    sv(4, x2 - nx * w2 * 0.5, y2 - ny * w2 * 0.5, 1, 1, r, g, b, a)
    stripDraw(G2, 4)
    return true
  end

  -- a soft ring on screen (rx, ry its radii, w px thick): bright along its middle, faded both sides
  local RING_N = 40
  local function screenRing(G2, x, y, rx, ry, w, cr, cg, cb, a)
    if a <= 0 or rx <= 0 or not stripReady() then return end
    for half = 0, 1 do
      local n = 0
      for k = 0, RING_N do
        local th = 2 * pi * k / RING_N
        local c, s = cos(th), sin(th)
        local ri = half == 0 and -w * 0.5 or 0
        local ro = half == 0 and 0 or w * 0.5
        local ai = half == 0 and 0 or a
        local ao = half == 0 and a or 0
        n = n + 1; sv(n, x + c * (rx + ri), y + s * (ry + ri * ry / rx), 0, 0, cr, cg, cb, ai)
        n = n + 1; sv(n, x + c * (rx + ro), y + s * (ry + ro * ry / rx), 0, 0, cr, cg, cb, ao)
      end
      stripDraw(G2, n)
    end
  end

  -- a soft ring on the ground about (X, Z) at height Y, R metres out, W metres wide
  local function groundRing(G2, X, Y, Z, R, W, cr, cg, cb, a)
    if a <= 0 or R <= 0 or not stripReady() then return end
    for half = 0, 1 do
      local n = 0
      local ok = true
      for k = 0, RING_N do
        local th = 2 * pi * k / RING_N
        local c, s = cos(th), sin(th)
        local r1 = half == 0 and max(0, R - W * 0.5) or R
        local r2 = half == 0 and R or R + W * 0.5
        local x1, y1 = P(X + c * r1, Y, Z + s * r1)
        local x2, y2 = P(X + c * r2, Y, Z + s * r2)
        if not (x1 and x2) then ok = false; break end
        n = n + 1; sv(n, x1, y1, 0, 0, cr, cg, cb, half == 0 and 0 or a)
        n = n + 1; sv(n, x2, y2, 0, 0, cr, cg, cb, half == 0 and a or 0)
      end
      if ok then stripDraw(G2, n) end
    end
  end

  -- a filled patch on the ground (an uneven disc), as a fan of projected points
  local patch = {}
  local function groundPatch(G2, X, Y, Z, R, seed, cr, cg, cb, a)
    if a <= 0 then return end
    local n = 0
    for k = 0, 17 do
      local th = 2 * pi * k / 18
      local rr = R * (0.75 + 0.45 * rnd(seed, k))
      local x, y = P(X + cos(th) * rr, Y, Z + sin(th) * rr)
      if not x then return end
      patch[n + 1], patch[n + 2] = x, y
      n = n + 2
    end
    for i = n + 1, #patch do patch[i] = nil end
    G2.setColor(cr, cg, cb, a)
    pcall(G2.polygon, "fill", patch)
  end

  -- ------- particles in the world

  local KINDS = {
    spark = { g = 7, drag = 1.2, bounce = 0.35, add = true },
    inspark = { g = 0, drag = 0, add = true },
    ember = { g = -1.4, drag = 1.6, add = true },
    glow = { g = 0, drag = 3, add = true },
    light = { g = 0, drag = 0, add = true },
    dust = { g = -0.25, drag = 2.2, puff = true },
    smoke = { g = -0.9, drag = 1.6, puff = true },
    wisp = { g = -0.7, drag = 1.2, puff = true },
    debris = { g = 9.8, drag = 0.2, bounce = 0.3 },
    chunk = { g = 9.8, drag = 0.1, bounce = 0.2 },
    drop = { g = 9.8, drag = 0.4 },
    leaf = { g = 1.2, drag = 2.5 },
    shard = { g = 9.8, drag = 0.3, bounce = 0.25 },
    bubble = { g = -0.8, drag = 1.5 },
    twinkle = { g = -0.2, drag = 1.5, add = true },
    ring = { g = 0, drag = 0, add = true },
    gring = { g = 0, drag = 0, add = true, ground = true },
    streak = { g = 0, drag = 0.3, add = true },
    heart = { g = -0.4, drag = 1.5 },
    coin = { g = 9.8, drag = 0.3, bounce = 0.45 },
  }
  local parts, pool = {}, {}
  Fx.MAX_PARTS = 900
  local seedN = 0
  local function emit(kind, X, Y, Z, vx, vy, vz, life, size, cr, cg, cb, a)
    if #parts >= Fx.MAX_PARTS then return nil end
    local p = table.remove(pool) or {}
    seedN = seedN + 1
    p.kind, p.X, p.Y, p.Z, p.vx, p.vy, p.vz = kind, X, Y, Z, vx or 0, vy or 0, vz or 0
    p.age, p.life, p.size = 0, life or 1, size or 0.1
    p.r, p.g, p.b, p.a = cr or 1, cg or 1, cb or 1, a or 1
    p.seed = seedN * 7.31
    p.rot = rnd(p.seed, 1) * 2 * pi
    p.spin = (rnd(p.seed, 2) - 0.5) * 12
    p.floor, p.home, p.w, p.grow = 0, nil, nil, nil
    parts[#parts + 1] = p
    return p
  end
  Fx.emit = emit

  -- n particles burst from (X, Y, Z): speed sp (+- half), mostly up by up (0..1), spread all round
  local function burstOf(kind, n, X, Y, Z, sp, up, life, size, cr, cg, cb, a, floorY)
    for k = 1, n do
      seedN = seedN + 1
      local s = seedN * 3.7
      local th = rnd(s, 1) * 2 * pi
      local el = (rnd(s, 2) * 2 - 1) * (1 - up) + up * (0.3 + 0.7 * rnd(s, 3))
      local hor = sqrt(max(0, 1 - el * el))
      local v = sp * (0.5 + rnd(s, 4))
      local p = emit(kind, X, Y, Z, cos(th) * hor * v, el * v, sin(th) * hor * v * 0.8 + sp * 0.15,
        life * (0.6 + 0.8 * rnd(s, 5)), size * (0.6 + 0.8 * rnd(s, 6)), cr, cg, cb, a)
      if p then p.floor = floorY or 0 end
    end
  end

  local function stepParts(dt)
    for i = #parts, 1, -1 do
      local p = parts[i]
      p.age = p.age + dt
      if p.age >= p.life then
        parts[i] = parts[#parts]
        parts[#parts] = nil
        pool[#pool + 1] = p
      else
        local K = KINDS[p.kind]
        if p.home then
          -- drawn in to an anchor, faster as it goes
          local A = p.home
          local dx, dy, dz = A.X - p.X, A.Y - p.Y, A.Z - p.Z
          local d = sqrt(dx * dx + dy * dy + dz * dz) + 1e-3
          local sp = 4 + 14 * p.age
          local k = min(1, dt * 5)
          p.vx = p.vx + (dx / d * sp - p.vx) * k
          p.vy = p.vy + (dy / d * sp - p.vy) * k
          p.vz = p.vz + (dz / d * sp - p.vz) * k
          if d < 0.35 then p.age = p.life end
        else
          local dr = max(0, 1 - K.drag * dt)
          p.vx, p.vy, p.vz = p.vx * dr, p.vy * dr - K.g * dt, p.vz * dr
        end
        p.X, p.Y, p.Z = p.X + p.vx * dt, p.Y + p.vy * dt, p.Z + p.vz * dt
        if K.bounce and p.Y < p.floor then
          p.Y = p.floor
          if p.vy < 0 then
            p.vy = -p.vy * K.bounce
            p.vx, p.vz = p.vx * 0.55, p.vz * 0.55
            p.spin = p.spin * 0.5
          end
        end
        p.rot = p.rot + p.spin * dt
      end
    end
  end

  local chunkPts = {}
  local function drawPart(G2, p, x, y, k)
    local u = p.age / p.life
    local kind = p.kind
    local s = p.size * k
    if kind == "spark" or kind == "inspark" then
      local x2, y2 = P(p.X - p.vx * 0.04, p.Y - p.vy * 0.04, p.Z - p.vz * 0.04)
      if not x2 then return end
      local a = p.a * (1 - u)
      local heat = 1 - u
      G2.setLineWidth(max(1, s))
      G2.setColor(p.r + (1 - p.r) * heat * 0.8, p.g + (1 - p.g) * heat * 0.6, p.b + (1 - p.b) * heat * 0.3, a)
      G2.line(x, y, x2, y2)
      if s > 1.5 then glowAt(G2, x, y, s * 4, p.r, p.g, p.b, a * 0.35) end
    elseif kind == "ember" then
      local fl = 0.6 + 0.4 * sin(p.age * 30 + p.seed)
      glowAt(G2, x, y, s * 3 * (1 - u * 0.5), p.r, p.g, p.b, p.a * (1 - u) * fl)
      glowAt(G2, x, y, s * 1.1, 1, 0.95, 0.7, p.a * (1 - u) * fl)
    elseif kind == "glow" or kind == "light" then
      local g = 1 + (p.grow or 0.6) * u
      glowAt(G2, x, y, s * g, p.r, p.g, p.b, p.a * (1 - u) * (1 - u))
    elseif kind == "twinkle" then
      local tw = (0.55 + 0.45 * sin(p.age * 22 + p.seed)) * p.a * (1 - u)
      glowAt(G2, x, y, s * 2.5, p.r, p.g, p.b, tw * 0.6)
      G2.setColor(1, 1, 1, tw)
      G2.push()
      G2.translate(x, y)
      G2.rotate(p.rot * 0.2)
      G2.ellipse("fill", 0, 0, s * 1.6, s * 0.18, 10)
      G2.ellipse("fill", 0, 0, s * 0.18, s * 1.6, 10)
      G2.pop()
    elseif kind == "ring" then
      local e = 1 - (1 - u) * (1 - u)
      local r = s * (0.15 + 0.85 * e)
      screenRing(G2, x, y, r, r * (p.flat or 1), max(1, (p.w or 0.2) * k * (1 - u)), p.r, p.g, p.b, p.a * (1 - u))
    elseif kind == "gring" then
      local e = 1 - (1 - u) * (1 - u)
      groundRing(G2, p.X, p.Y, p.Z, p.size * (0.1 + 0.9 * e), (p.w or 0.3) * (1 - u * 0.6), p.r, p.g, p.b, p.a * (1 - u))
    elseif kind == "streak" then
      local x2, y2 = P(p.X - p.vx * 0.09, p.Y - p.vy * 0.09, p.Z - p.vz * 0.09)
      if not x2 then return end
      G2.setLineWidth(max(1, s))
      G2.setColor(p.r, p.g, p.b, p.a * sin(u * pi))
      G2.line(x, y, x2, y2)
    elseif KINDS[kind].puff then
      local sz = s * (1 + 1.8 * u)
      local a = p.a * (1 - u) ^ 1.4 * min(1, p.age / 0.06)
      local sh, tx = shader("puff"), shaders.texel
      if sh and tx then
        G2.setShader(sh)
        G2.setColor(p.r, p.g, p.b, a)
        G2.draw(tx, x, y, p.rot * 0.15, sz * 2, sz * 2, 0.5, 0.5)
        G2.setShader()
      else
        glowAt(G2, x, y, sz * 1.6, p.r, p.g, p.b, a)
      end
    elseif kind == "debris" or kind == "chunk" or kind == "shard" then
      local n = kind == "shard" and 3 or 6
      for j = 0, n - 1 do
        local th = p.rot + j * 2 * pi / n
        local rr = s * (kind == "shard" and (j == 0 and 1.8 or 0.55) or (0.65 + 0.45 * rnd(p.seed, j)))
        chunkPts[j * 2 + 1], chunkPts[j * 2 + 2] = x + cos(th) * rr, y + sin(th) * rr * 0.85
      end
      for j = n * 2 + 1, #chunkPts do chunkPts[j] = nil end
      local a = p.a * min(1, (1 - u) * 4)
      if kind == "shard" then
        G2.setColor(p.r, p.g, p.b, a * 0.8)
        G2.polygon("fill", chunkPts)
        G2.setColor(1, 1, 1, a)
        G2.setLineWidth(1)
        G2.polygon("line", chunkPts)
      else
        G2.setColor(p.r, p.g, p.b, a)
        rockPoly(G2, chunkPts, max(2, s * 0.6))
        G2.setColor(min(1, p.r * 1.35), min(1, p.g * 1.35), min(1, p.b * 1.35), a * 0.8)
        G2.polygon("fill", chunkPts[1], chunkPts[2], chunkPts[3], chunkPts[4], x, y)
      end
    elseif kind == "drop" then
      local x2, y2 = P(p.X - p.vx * 0.025, p.Y - p.vy * 0.025, p.Z - p.vz * 0.025)
      if not x2 then return end
      local a = p.a * (1 - u * u)
      G2.setLineWidth(max(1, s))
      G2.setColor(p.r, p.g, p.b, a * 0.75)
      G2.line(x, y, x2, y2)
      G2.setColor(1, 1, 1, a * 0.8)
      G2.circle("fill", x, y, max(0.6, s * 0.35), 8)
    elseif kind == "leaf" then
      G2.push()
      G2.translate(x, y)
      G2.rotate(p.rot)
      local fl = abs(cos(p.age * 7 + p.seed))
      local a = p.a * (1 - u * u)
      G2.setColor(p.r * 0.75, p.g * 0.75, p.b * 0.75, a)
      G2.ellipse("fill", 0, 0, s, s * 0.42 * (0.3 + 0.7 * fl), 12)
      G2.setColor(min(1, p.r * 1.2), min(1, p.g * 1.15), p.b, a)
      G2.ellipse("fill", -s * 0.1, -s * 0.06 * fl, s * 0.7, s * 0.2 * (0.3 + 0.7 * fl), 12)
      G2.pop()
    elseif kind == "bubble" then
      local a = p.a * (1 - u)
      local r = s * (1 + 0.1 * sin(p.age * 14 + p.seed))
      G2.setColor(p.r, p.g, p.b, a * 0.25)
      G2.circle("fill", x, y, r, 16)
      G2.setColor(min(1, p.r + 0.3), min(1, p.g + 0.3), min(1, p.b + 0.3), a * 0.8)
      G2.setLineWidth(max(1, r * 0.12))
      G2.circle("line", x, y, r, 16)
      G2.setColor(1, 1, 1, a)
      G2.circle("fill", x - r * 0.35, y - r * 0.35, r * 0.22, 8)
    elseif kind == "heart" then
      local a = p.a * (1 - u)
      G2.setColor(p.r, p.g, p.b, a)
      G2.circle("fill", x - s * 0.42, y, s * 0.5, 12)
      G2.circle("fill", x + s * 0.42, y, s * 0.5, 12)
      G2.polygon("fill", x - s * 0.9, y + s * 0.15, x + s * 0.9, y + s * 0.15, x, y + s * 1.1)
    elseif kind == "coin" then
      local a = p.a * min(1, (1 - u) * 4)
      local sx = abs(cos(p.rot))
      G2.setColor(0.75, 0.55, 0.12, a)
      G2.ellipse("fill", x, y, max(0.8, s * sx), s, 16)
      G2.setColor(1, 0.85, 0.3, a)
      G2.ellipse("fill", x - s * 0.1 * sx, y - s * 0.08, max(0.6, s * 0.75 * sx), s * 0.78, 16)
      if sx > 0.85 then glowAt(G2, x - s * 0.3, y - s * 0.4, s * 1.4, 1, 1, 0.8, a * 0.7) end
    end
  end

  local function drawParts(G2, layer)
    -- the alpha-blended first, the added after
    for pass = 1, 2 do
      G2.setBlendMode(pass == 1 and "alpha" or "add")
      for i = 1, #parts do
        local p = parts[i]
        local K = KINDS[p.kind]
        if (K.add and 2 or 1) == pass and ((K.ground and "back") or layerOf(p.Z)) == layer then
          local x, y, k = P(p.X, p.Y, p.Z)
          if x then drawPart(G2, p, x, y, k) end
        end
      end
    end
    G2.setBlendMode("alpha")
    G2.setLineWidth(1)
  end

  -- ------- the ground's marks: scorch, cracks, frost, wet (they fade over their last 40%)

  local decals = {}
  function Fx.decal(kind, X, Y, Z, R, now, life)
    decals[#decals + 1] = { kind = kind, X = X, Y = (Y or 0) + 0.012, Z = Z, R = R, t0 = now, life = life or 3.5,
      seed = now * 11.3 + #decals }
  end
  local crackPts = {}
  local function drawDecals(G2, now)
    for _, d in ipairs(decals) do
      local u = (now - d.t0) / d.life
      if u >= 0 and u < 1 then
        local a = u < 0.6 and 1 or (1 - (u - 0.6) / 0.4)
        local grow = min(1, (now - d.t0) / 0.12)
        if d.kind == "scorch" then
          groundPatch(G2, d.X, d.Y, d.Z, d.R * grow, d.seed, 0.06, 0.035, 0.02, 0.62 * a)
          groundPatch(G2, d.X, d.Y, d.Z, d.R * 0.5 * grow, d.seed + 1, 0.02, 0.01, 0.0, 0.5 * a)
          G2.setBlendMode("add")
          groundPatch(G2, d.X, d.Y, d.Z, d.R * 0.35 * grow, d.seed + 2, 0.9, 0.3, 0.05, 0.5 * a * max(0, 1 - u * 3))
          G2.setBlendMode("alpha")
        elseif d.kind == "wet" then
          groundPatch(G2, d.X, d.Y, d.Z, d.R * grow, d.seed, 0.05, 0.08, 0.12, 0.45 * a)
        elseif d.kind == "frost" then
          groundPatch(G2, d.X, d.Y, d.Z, d.R * grow, d.seed, 0.8, 0.92, 1, 0.42 * a)
          groundPatch(G2, d.X, d.Y, d.Z, d.R * 0.55 * grow, d.seed + 1, 0.95, 1, 1, 0.35 * a)
        elseif d.kind == "crack" then
          groundPatch(G2, d.X, d.Y, d.Z, d.R * 0.4 * grow, d.seed, 0.08, 0.06, 0.05, 0.55 * a)
          G2.setColor(0.05, 0.04, 0.03, 0.85 * a)
          for j = 1, 9 do
            local th = rnd(d.seed, j) * 2 * pi
            local n = 0
            local okC = true
            local cx, cz = d.X, d.Z
            for s = 0, 5 do
              local rr = d.R * grow * s / 5 * (0.7 + 0.5 * rnd(d.seed, j + 20))
              local jit = (rnd(d.seed, j * 7 + s) - 0.5) * 0.5
              local x, y = P(cx + cos(th + jit) * rr, d.Y, cz + sin(th + jit) * rr)
              if not x then okC = false; break end
              crackPts[n + 1], crackPts[n + 2] = x, y
              n = n + 2
            end
            for q = n + 1, #crackPts do crackPts[q] = nil end
            if okC and n >= 4 then
              local _, _, k = P(d.X, d.Y, d.Z)
              G2.setLineWidth(max(1, (k or 40) * 0.035))
              G2.line(crackPts)
            end
          end
          G2.setLineWidth(1)
        end
      end
    end
  end

  -- ------- short effects at a point: an impact's bloom, fire, electric arcs

  local spots = {}
  local function spot(kind, X, Y, Z, s, now, dur, tc, power)
    seedN = seedN + 1
    spots[#spots + 1] = { kind = kind, X = X, Y = Y, Z = Z, s = s, t0 = now, dur = dur, tc = tc, p = power or 0.5,
      seed = seedN * 5.1 }
  end

  -- a jagged line between two world points (midpoint displacement), projected into pts
  local boltW = {}
  local function jagged(out, x1, y1, z1, x2, y2, z2, seed, rough, levels)
    -- world points first
    local W = boltW
    W[1], W[2], W[3], W[4], W[5], W[6] = x1, y1, z1, x2, y2, z2
    local n = 2
    for lv = 1, levels do
      local m = {}
      local idx = 0
      for i = 1, n - 1 do
        local a, b = (i - 1) * 3, i * 3
        local ax, ay, az, bx, by, bz = W[a + 1], W[a + 2], W[a + 3], W[b + 1], W[b + 2], W[b + 3]
        local len = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
        local off = len * rough
        m[idx + 1], m[idx + 2], m[idx + 3] = ax, ay, az
        m[idx + 4] = (ax + bx) / 2 + (rnd(seed, lv * 31 + i) - 0.5) * off
        m[idx + 5] = (ay + by) / 2 + (rnd(seed, lv * 37 + i) - 0.5) * off * 0.5
        m[idx + 6] = (az + bz) / 2 + (rnd(seed, lv * 41 + i) - 0.5) * off
        idx = idx + 6
      end
      local e = (n - 1) * 3
      m[idx + 1], m[idx + 2], m[idx + 3] = W[e + 1], W[e + 2], W[e + 3]
      n = n * 2 - 1
      for i = 1, n * 3 do W[i] = m[i] end
    end
    local c = 0
    for i = 1, n do
      local x, y = P(W[i * 3 - 2], W[i * 3 - 1], W[i * 3])
      if not x then return 0 end
      out[c + 1], out[c + 2] = x, y
      c = c + 2
    end
    for i = c + 1, #out do out[i] = nil end
    return c
  end
  -- a lightning line drawn glowing (three passes, the caller's blend "add")
  local function glowLine(G2, pts, w, tc, a)
    G2.setLineJoin("bevel")
    G2.setLineWidth(w * 5)
    G2.setColor(tc[1], tc[2], tc[3], 0.12 * a)
    G2.line(pts)
    G2.setLineWidth(w * 2.2)
    G2.setColor(tc[1], tc[2], tc[3], 0.45 * a)
    G2.line(pts)
    G2.setLineWidth(max(1, w * 0.8))
    G2.setColor(1, 1, 1, a)
    G2.line(pts)
  end

  local arcPts = {}
  local function drawSpot(G2, e, now)
    local u = (now - e.t0) / e.dur
    if u < 0 or u > 1 then return end
    local x, y, k = P(e.X, e.Y, e.Z)
    if not x then return end
    local tc = e.tc
    if e.kind == "bloom" then
      -- the impact's light: a hard white core, the type's orb swelling, a ring
      G2.setBlendMode("add")
      local r = e.s * k * (0.18 + 0.42 * (1 - (1 - u) ^ 3)) * (0.8 + 0.5 * e.p)
      orbAt(G2, x, y, r, tc, (1 - u) ^ 2 * 0.85, now)
      glowAt(G2, x, y, r * 0.55, 1, 1, 1, (1 - u) ^ 4 * 0.7)
      G2.setBlendMode("alpha")
    elseif e.kind == "fire" then
      local w, h = e.s * k * 1.2 * (0.7 + 0.5 * u), e.s * k * 1.5 * (1 - u * 0.4)
      if not fireRect(G2, x - w / 2, y - h * 0.8, w, h, now * 1.3 + e.seed, e.seed, (1 - u) ^ 0.7, 1) then
        G2.setBlendMode("add")
        glowAt(G2, x, y, w, 1, 0.45, 0.1, 1 - u)
        G2.setBlendMode("alpha")
      end
    elseif e.kind == "arcs" then
      G2.setBlendMode("add")
      local flick = floor(now * 24)
      for j = 1, 4 do
        if rnd(e.seed + flick, j) > 0.25 then
          local s1, s2 = e.seed + flick * 3 + j, e.seed + flick * 5 + j * 2
          local r = e.s * 0.6
          local a1, a2 = rnd(s1, 1) * 2 * pi, rnd(s2, 1) * 2 * pi
          local n = jagged(arcPts, e.X + cos(a1) * r, e.Y + (rnd(s1, 2) - 0.5) * r * 1.6, e.Z + sin(a1) * r * 0.3,
            e.X + cos(a2) * r, e.Y + (rnd(s2, 2) - 0.5) * r * 1.6, e.Z + sin(a2) * r * 0.3, s1, 0.5, 3)
          if n >= 4 then glowLine(G2, arcPts, max(1, k * 0.03), tc, 1 - u) end
        end
      end
      G2.setBlendMode("alpha")
    elseif e.kind == "psy" then
      G2.setBlendMode("add")
      for j = 0, 2 do
        local f = u * 1.3 - j * 0.15
        if f > 0 and f < 1 then
          local r = e.s * k * (0.3 + 1.0 * f)
          screenRing(G2, x, y, r, r * 0.8, max(1, k * 0.08 * (1 - f)), tc[1], tc[2], tc[3], 0.8 * (1 - f))
          screenRing(G2, x + r * 0.03, y, r * 1.02, r * 0.82, max(1, k * 0.04 * (1 - f)), 0.5, 0.8, 1, 0.4 * (1 - f))
        end
      end
      G2.setBlendMode("alpha")
    elseif e.kind == "lines" then
      -- speed lines closing on the point (a blow about to land)
      G2.setBlendMode("add")
      G2.setLineWidth(max(1, k * 0.02))
      for j = 1, 16 do
        local th = rnd(e.seed, j) * 2 * pi
        local r1 = e.s * k * (1.6 - 1.1 * u) * (0.8 + 0.4 * rnd(e.seed, j + 9))
        local r0 = r1 + e.s * k * (0.5 + 0.3 * rnd(e.seed, j + 4))
        G2.setColor(1, 1, 1, 0.55 * sin(u * pi))
        G2.line(x + cos(th) * r0, y + sin(th) * r0, x + cos(th) * r1, y + sin(th) * r1)
      end
      G2.setBlendMode("alpha")
    end
  end

  -- ------- a type's hit at an anchor (power 0..1+)

  local function hitPoint(T)
    -- on the side it is struck from: toward the camera
    return T.X, T.Y, T.Z + (T.boss and min(1.4, T.h * 0.2) or 0.3)
  end
  function Fx.hit(typeName, T, power, now, big)
    local tc = TINT[typeName] or TINT.NORMAL
    local X, Y, Z = hitPoint(T)
    local s = min(T.h, 3.2) * (big and 1.25 or 1)
    local p = power or 0.5
    local foot = T.foot or 0
    spot("bloom", X, Y, Z, s, now, 0.32 + 0.12 * p, tc, p)
    local rg = emit("ring", X, Y, Z, 0, 0, 0, 0.3 + 0.1 * p, s * (0.55 + 0.5 * p), tc[1], tc[2], tc[3], 0.75)
    if rg then rg.w = s * 0.07 end
    local gr = emit("gring", T.X, foot + 0.02, T.Z, 0, 0, 0, 0.55, s * (1.2 + 1.2 * p), tc[1], tc[2], tc[3], 0.6)
    if gr then gr.w = s * 0.25 end
    burstOf("spark", floor(10 + 22 * p), X, Y, Z, 3.5 + 4 * p, 0.25, 0.45, 0.025 * s, tc[1], tc[2], tc[3], 1, foot)
    local t = typeName
    if t == "FIRE" then
      spot("fire", X, Y - s * 0.1, Z, s * 0.8, now, 0.85, tc, p)
      burstOf("ember", 22, X, Y, Z, 2.2, 0.6, 1.1, 0.03 * s, 1, 0.45, 0.1, 1, foot)
      burstOf("smoke", 6, X, Y + s * 0.3, Z, 0.7, 0.8, 1.4, 0.25 * s, 0.18, 0.15, 0.14, 0.55, foot)
      Fx.decal("scorch", T.X, foot, T.Z, s * 0.55, now)
    elseif t == "WATER" then
      burstOf("drop", 34, X, Y, Z, 4.5, 0.55, 1.0, 0.035 * s, 0.55, 0.8, 1, 0.9, foot)
      burstOf("dust", 7, X, Y, Z, 1.2, 0.3, 0.8, 0.22 * s, 0.75, 0.88, 1, 0.45, foot)
      Fx.decal("wet", T.X, foot, T.Z, s * 0.6, now)
    elseif t == "ELECTRIC" then
      spot("arcs", X, Y, Z, s, now, 0.5, tc, p)
      burstOf("spark", 18, X, Y, Z, 6, 0.2, 0.35, 0.02 * s, 1, 0.95, 0.5, 1, foot)
      emit("light", X, Y, Z, 0, 0, 0, 0.18, s * 6, 1, 0.95, 0.6, 0.35)
    elseif t == "GRASS" or t == "BUG" then
      burstOf("leaf", 16, X, Y, Z, 3, 0.4, 1.3, 0.09 * s, tc[1] * 0.8, tc[2], tc[3] * 0.6, 1, foot)
      burstOf("twinkle", 8, X, Y, Z, 1.4, 0.3, 0.8, 0.04 * s, 0.7, 1, 0.5, 0.8, foot)
    elseif t == "ICE" then
      burstOf("shard", 18, X, Y, Z, 4.5, 0.4, 1.0, 0.06 * s, 0.75, 0.92, 1, 1, foot)
      burstOf("dust", 8, X, Y, Z, 1.2, 0.2, 1.0, 0.24 * s, 0.85, 0.95, 1, 0.5, foot)
      Fx.decal("frost", T.X, foot, T.Z, s * 0.6, now)
    elseif t == "ROCK" or t == "GROUND" then
      burstOf("debris", 14, X, Y, Z, 4, 0.55, 1.6, 0.06 * s, 0.52, 0.42, 0.32, 1, foot)
      burstOf("dust", t == "GROUND" and 14 or 8, T.X, foot + s * 0.15, T.Z, 1.6, 0.4, 1.4, 0.3 * s,
        0.6, 0.5, 0.38, 0.6, foot)
      Fx.decal("crack", T.X, foot, T.Z, s * 0.7, now)
    elseif t == "POISON" then
      burstOf("bubble", 16, X, Y, Z, 1.5, 0.7, 1.3, 0.05 * s, 0.75, 0.35, 0.9, 0.9, foot)
      burstOf("smoke", 8, X, Y, Z, 0.9, 0.5, 1.3, 0.25 * s, 0.5, 0.2, 0.6, 0.5, foot)
    elseif t == "PSYCHIC" then
      spot("psy", X, Y, Z, s, now, 0.7, tc, p)
      burstOf("twinkle", 10, X, Y, Z, 1.8, 0.2, 0.8, 0.04 * s, 1, 0.5, 0.8, 0.8, foot)
    elseif t == "DARK" or t == "GHOST" then
      burstOf("wisp", 12, X, Y, Z, 1.3, 0.4, 1.3, 0.22 * s, t == "DARK" and 0.12 or 0.25, 0.05, t == "DARK" and 0.18 or 0.35,
        0.65, foot)
      burstOf("ember", 10, X, Y, Z, 1.6, 0.5, 0.9, 0.03 * s, tc[1], tc[2], tc[3], 1, foot)
    elseif t == "DRAGON" then
      burstOf("ember", 18, X, Y, Z, 3, 0.3, 0.9, 0.035 * s, 0.55, 0.45, 1, 1, foot)
      spot("psy", X, Y, Z, s * 0.8, now, 0.5, tc, p)
    elseif t == "FAIRY" then
      burstOf("twinkle", 20, X, Y, Z, 2.4, 0.4, 1.1, 0.05 * s, 1, 0.65, 0.88, 1, foot)
    elseif t == "FLYING" then
      burstOf("streak", 14, X, Y, Z, 7, 0.1, 0.35, 0.02 * s, 0.9, 0.95, 1, 0.9, foot)
      burstOf("dust", 6, T.X, foot + 0.1, T.Z, 2.2, 0.1, 0.8, 0.22 * s, 0.85, 0.85, 0.82, 0.4, foot)
    elseif t == "STEEL" then
      burstOf("spark", 22, X, Y, Z, 7, 0.3, 0.6, 0.022 * s, 1, 0.92, 0.6, 1, foot)
    else
      -- fighting, normal: a blast of dust at the feet
      burstOf("dust", 8, T.X, foot + 0.1, T.Z, 2, 0.15, 0.9, 0.26 * s, 0.7, 0.62, 0.52, 0.5, foot)
    end
  end

  -- ------- the screen's flash, the G-Max charge

  local flashes = {}
  local function flash(tc, a, dur, now)
    flashes[#flashes + 1] = { r = tc[1], g = tc[2], b = tc[3], a = a, dur = dur, t0 = now }
  end
  Fx.flash = flash

  local charge = nil
  function Fx.charge(A, now, dur) if A then charge = { A = A, t0 = now, dur = dur or 1.6, acc = 0 } end end
  function Fx.charging(now) return charge ~= nil and now - charge.t0 < charge.dur end

  local RED = { 1, 0.15, 0.3 }
  local function stepCharge(now, dt)
    local c = charge
    if not c then return end
    local u = (now - c.t0) / c.dur
    if u > 1 then charge = nil; return end
    local A = c.A
    -- red energy streaking in from all round
    c.acc = c.acc + dt * (60 + 120 * u)
    while c.acc >= 1 do
      c.acc = c.acc - 1
      seedN = seedN + 1
      local s = seedN * 1.37
      local th, el = rnd(s, 1) * 2 * pi, (rnd(s, 2) - 0.3) * 1.2
      local d = A.h * (1.2 + 0.8 * rnd(s, 3))
      local dx, dy, dz = cos(th) * cos(el), sin(el), sin(th) * cos(el) * 0.6
      local sp = d / (0.25 + 0.2 * rnd(s, 4))
      local hot = rnd(s, 5) > 0.7
      emit("inspark", A.X + dx * d, A.Y + dy * d, A.Z + dz * d, -dx * sp, -dy * sp, -dz * sp, d / sp, 0.03 * A.h,
        1, hot and 0.7 or 0.12, hot and 0.8 or 0.3, 0.9)
    end
    if rnd(now, 3) > 0.9 then spot("arcs", A.X, A.Y, A.Z + 0.5, A.h * 0.9, now, 0.12, RED, 0.5) end
  end
  local function drawCharge(G2, w, h, now)
    local c = charge
    local u = (now - c.t0) / c.dur
    local a = sin(min(1, u) * pi)
    G2.setColor(0.4, 0.0, 0.05, 0.4 * a)
    G2.rectangle("fill", 0, 0, w, h)
  end
  local function drawChargeOrb(G2, now)
    local c = charge
    local u = (now - c.t0) / c.dur
    local x, y, k = P(c.A.X, c.A.Y, c.A.Z + 0.6)
    if not x then return end
    G2.setBlendMode("add")
    local r = c.A.h * k * (0.12 + 0.35 * u) * (1 + 0.08 * sin(now * 30))
    orbAt(G2, x, y, r, RED, min(1, u * 2) * (u > 0.92 and (1 - u) / 0.08 or 1), now)
    G2.setBlendMode("alpha")
  end

  -- ------- moves acted out (data/raid_move_fx.lua): Fx.move(spec, typeName, from, targets, now, big)
  -- Each kind has a length and an impact (seconds): at the impact the targets take its type's hit
  -- (multi strikes, shots, a wave pass each in turn). Returns impact, length.

  Fx.KIND = {
    beam = { 0.95, 0.35 }, shot = { 0.85, 0.55 }, drop = { 1.0, 0.65 }, slab = { 1.7, 0.95 }, slam = { 0.75, 0.4 },
    slash = { 0.65, 0.3 }, bite = { 0.7, 0.35 }, bolt = { 0.75, 0.2 }, wave = { 1.25, 0.7 }, rings = { 0.9, 0.5 },
    powder = { 1.1, 0.6 }, self = { 0.9, nil }, drain = { 1.3, 0.3 }, spikes = { 0.9, 0.42 }, multi = { 0.35, 0.18 },
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
    seedN = seedN + 1
    local m = { spec = spec, kind = kind, key = key, type = TINT[typeName] and typeName or "NORMAL", from = from,
      targets = targets or {}, t0 = now, len = len * k, impact = impact and impact * k or nil, big = big or spec.big,
      gmax = big, landed = {}, acc = 0, seed = seedN * 13.7 + now }
    m.tc = TINT[m.type]
    moves[#moves + 1] = m
    return m.impact, m.len
  end

  -- a target takes the blow: its type's hit, a flash, the raid's impact
  local function land(m, T, share, now, quiet)
    local p = (T.frac and min(1, 0.3 + T.frac * 1.8) or 0.18) * (share or 1) + (m.gmax and 0.3 or (m.big and 0.12 or 0))
    p = min(1.3, p)
    if not quiet then Fx.hit(m.type, T, p, now, m.big) end
    -- (one flash a move, however many it falls on)
    if p > 0.4 and not quiet and not m.flashed then
      m.flashed = true
      flash(m.tc, 0.12 + 0.18 * min(1, p), 0.1 + 0.12 * p, now) end
    if Fx.onImpact then pcall(Fx.onImpact, T, p, m.type, m.big) end
  end
  local function landOnce(m, key, T, share, now)
    if m.landed[key] then return end
    m.landed[key] = true
    land(m, T, share, now)
  end

  -- where a move leaves its user: a little in front of its middle, toward the targets
  local function mouth(m)
    local f = m.from
    if f.boss then return f.X, f.Y + f.h * 0.12, f.Z + min(1.5, f.h * 0.25) end
    return f.X, f.Y + f.h * 0.1, f.Z - 0.25
  end
  -- a target's point to aim at
  local function aimAt(T) return hitPoint(T) end

  -- a shot's place: the k-th of n in flight (g 0..1 along), a little arc
  local function shotPos(m, T, g, k)
    local x1, y1, z1 = mouth(m)
    local x2, y2, z2 = aimAt(T)
    local d = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
    local side = (rnd(m.seed, k) - 0.5) * d * 0.15 * sin(g * pi)
    return x1 + (x2 - x1) * g + side, y1 + (y2 - y1) * g + d * 0.12 * sin(g * pi), z1 + (z2 - z1) * g
  end
  local SHOT_GAP = 0.09

  -- the wall's depth now (wave): from in front of the boss to past the party
  local function wallZ(m, t)
    local pz = Sc and Sc.PAD.z or -9.2
    local z0, z1 = pz + 2.5, 0.9
    local imp = m.impact or m.len
    if t <= imp then return z0 + (z1 - z0) * (t / imp) end
    return z1 + (t - imp) / (m.len - imp) * 1.8
  end
  local function wallH(m) return (m.big and 3.3 or 2.5) end
  local WALL = {
    water = { deep = { 0.02, 0.17, 0.4 }, shallow = { 0.35, 0.75, 1 }, foam = { 0.95, 0.98, 1 } },
    ground = { deep = { 0.3, 0.22, 0.14 }, shallow = { 0.72, 0.6, 0.42 }, foam = { 0.86, 0.8, 0.68 } },
  }

  local dropPos   -- (below: what falls, its place now)

  -- each frame: what a move sets off (particles, its hits)
  local function stepMove(m, now, dt)
    local t = now - m.t0
    local imp = m.impact or m.len
    local kind, spec, tc = m.kind, m.spec, m.tc
    local fx, fy, fz = mouth(m)
    m.acc = m.acc + dt
    local tick = m.acc >= 1 / 60
    if tick then m.acc = 0 end
    if kind == "beam" then
      if t < imp then
        if tick then emit("glow", fx, fy, fz, 0, 0, 0, 0.25, m.from.h * 0.12, tc[1], tc[2], tc[3], 0.6) end
      elseif t < m.len * 0.8 then
        for ti, T in ipairs(m.targets) do
          landOnce(m, ti, T, 1, now)
          local X, Y, Z = aimAt(T)
          if tick then
            burstOf("spark", 2, X, Y, Z, 5, 0.3, 0.35, 0.025 * min(3, T.h), tc[1], tc[2], tc[3], 1, T.foot)
            if rnd(now, ti) > 0.7 then burstOf("smoke", 1, X, Y, Z, 1, 0.6, 0.8, 0.18 * min(3, T.h), 0.3, 0.28, 0.27, 0.4, T.foot) end
          end
        end
      end
    elseif kind == "shot" then
      local n = spec.n or 1
      local fly = max(0.15, imp - (n - 1) * SHOT_GAP)
      for ti, T in ipairs(m.targets) do
        for k = 1, n do
          local g = (t - (k - 1) * SHOT_GAP) / fly
          if g >= 1 then landOnce(m, ti * 100 + k, T, 1 / sqrt(n), now)
          elseif g > 0 and tick then
            local x, y, z = shotPos(m, T, g, k)
            local sh = spec.shape or "ball"
            if sh == "rock" then emit("dust", x, y, z, 0, 0, 0, 0.5, 0.12, 0.55, 0.47, 0.38, 0.4)
            elseif m.type == "FIRE" then emit("ember", x, y, z, 0, 0.3, 0, 0.5, 0.05, 1, 0.5, 0.1, 1)
            elseif sh ~= "coin" and sh ~= "apple" then emit("glow", x, y, z, 0, 0, 0, 0.3, 0.25, tc[1], tc[2], tc[3], 0.5) end
          end
        end
      end
    elseif kind == "drop" and m.key ~= "slab" then
      local n = (spec.shape == "rock" or spec.shape == "coin") and (spec.n or 3) or 1
      for ti, T in ipairs(m.targets) do
        if t >= imp then
          if not m.landed[ti] then
            local foot = T.foot or 0
            if spec.shape == "coin" then
              burstOf("coin", 24, T.X, foot + 0.3, T.Z, 3.5, 0.6, 1.6, 0.09, 1, 1, 1, 1, foot)
            else
              burstOf("chunk", 10, T.X, foot + 0.3, T.Z, 4, 0.6, 1.5, 0.12 * min(2, T.h), 0.5, 0.41, 0.32, 1, foot)
            end
            burstOf("dust", 12, T.X, foot + 0.15, T.Z, 2.4, 0.15, 1.4, 0.32 * min(2, T.h), 0.62, 0.53, 0.42, 0.6, foot)
            Fx.decal("crack", T.X, foot, T.Z, min(2.5, T.h) * 0.8, now)
          end
          landOnce(m, ti, T, 1, now)
        elseif tick and t > imp * 0.3 then
          -- a trail behind what falls
          for k = 1, n do
            local x, y, z = dropPos(m, T, t, k)
            if spec.shape == "rock" or spec.shape == "slab" then emit("dust", x, y + 0.3, z, 0, 0.5, 0, 0.4, 0.15, 0.5, 0.45, 0.38, 0.3)
            elseif spec.shape ~= "coin" and spec.shape ~= "apple" then
              emit("glow", x, y + 0.2, z, 0, 0, 0, 0.3, 0.4, tc[1], tc[2], tc[3], 0.5)
            end
          end
        end
      end
    elseif m.key == "slab" then
      if t >= imp and not m.slabLanded then
        m.slabLanded = true
        for ti, T in ipairs(m.targets) do land(m, T, 1, now, true) end
        flash({ 0.9, 0.75, 0.55 }, 0.22, 0.25, now)
        local b = m.box
        if b then
          for j = 1, 26 do
            local xx = b.x0 + (b.x1 - b.x0) * rnd(m.seed, j)
            emit("dust", xx, 0.2, b.z1 + 0.2, (rnd(m.seed, j + 3) - 0.5) * 6, 0.5 + rnd(m.seed, j + 5), 2 + 3 * rnd(m.seed, j + 7),
              1.8, 0.45 + 0.3 * rnd(m.seed, j + 9), 0.6, 0.52, 0.42, 0.7)
          end
          for j = 1, 3 do
            Fx.decal("crack", b.x0 + (b.x1 - b.x0) * (j - 0.5) / 3, 0, (b.z0 + b.z1) / 2 + 1, 2.2, now, 4)
          end
          local gr = emit("gring", (b.x0 + b.x1) / 2, 0.03, (b.z0 + b.z1) / 2, 0, 0, 0, 0.8, (b.x1 - b.x0) * 0.8, 0.9, 0.75, 0.55, 0.7)
          if gr then gr.w = 1.2 end
        end
      end
      if t >= imp + 0.38 and not m.shattered then
        -- it breaks up
        m.shattered = true
        local b = m.box
        if b then
          for j = 1, 30 do
            local xx = b.x0 + (b.x1 - b.x0) * rnd(m.seed, j + 40)
            local zz = b.z0 + (b.z1 - b.z0) * rnd(m.seed, j + 50)
            local p = emit("chunk", xx, b.h * rnd(m.seed, j + 60), zz, (rnd(m.seed, j + 70) - 0.5) * 5, 2 + 4 * rnd(m.seed, j + 80),
              1 + 3 * rnd(m.seed, j + 90), 1.6, 0.18 + 0.25 * rnd(m.seed, j + 100), 0.5, 0.42, 0.33, 1)
            if p then p.floor = 0 end
          end
          for j = 1, 14 do
            emit("dust", b.x0 + (b.x1 - b.x0) * rnd(m.seed, j + 120), b.h * 0.5, b.z1, (rnd(m.seed, j + 130) - 0.5) * 3, 1, 1.5,
              2, 0.6, 0.62, 0.55, 0.45, 0.6)
          end
        end
      end
    elseif kind == "slam" or kind == "multi" then
      local n = kind == "multi" and (spec.n or 3) or 1
      for k = 1, n do
        local at = kind == "multi" and ((k - 1) / n * m.len * 0.85 + m.len * 0.05 + 0.1) or imp
        for ti, T in ipairs(m.targets) do
          if t >= at - 0.14 and not m.landed["l" .. ti .. k] then
            m.landed["l" .. ti .. k] = true
            local X, Y, Z = aimAt(T)
            spot("lines", X, Y, Z, min(3, T.h), now, 0.16, tc, 0.5)
          end
          if t >= at then landOnce(m, ti * 100 + k, T, n > 1 and 0.6 or 1, now) end
        end
      end
    elseif kind == "slash" or kind == "bite" or kind == "rings" or kind == "bolt" or kind == "powder" or kind == "spikes" then
      for ti, T in ipairs(m.targets) do
        if kind == "spikes" and t >= imp * 0.6 and not m.landed["e" .. ti] then
          m.landed["e" .. ti] = true
          local foot = T.foot or 0
          burstOf("debris", 12, T.X, foot + 0.1, T.Z, 3.5, 0.75, 1.2, 0.07 * min(2.5, T.h), 0.5, 0.42, 0.32, 1, foot)
          burstOf("dust", 10, T.X, foot + 0.1, T.Z, 1.8, 0.3, 1.2, 0.28 * min(2.5, T.h), 0.6, 0.52, 0.42, 0.55, foot)
          Fx.decal("crack", T.X, foot, T.Z, min(2.5, T.h) * 0.75, now)
        end
        if kind == "powder" and t < imp and tick then
          local g = t / imp
          local X, Y, Z = aimAt(T)
          local x, y, z = fx + (X - fx) * g, fy + (Y - fy) * g, fz + (Z - fz) * g
          local sh = spec.shape
          if sh == "heart" then
            emit("heart", x, y, z, (rnd(now, ti) - 0.5), 0.3, 0.5, 1.0, 0.07, 1, 0.45, 0.65, 0.95)
          else
            local c = sh == "sand" and { 0.8, 0.68, 0.45 } or sh == "smoke" and { 0.32, 0.32, 0.36 }
              or sh == "gas" and { 0.6, 0.3, 0.75 } or { 0.85, 0.85, 0.55 }
            emit("dust", x, y, z, (rnd(now, ti) - 0.5) * 1.5, (rnd(now, ti + 2) - 0.5), 1, 1.3,
              0.25 + 0.25 * rnd(now, ti + 3), c[1], c[2], c[3], 0.6)
            if sh == "spore" or not sh then emit("twinkle", x, y, z, 0, 0.2, 0.4, 0.8, 0.03, 0.9, 1, 0.5, 0.7) end
          end
        end
        if kind == "bolt" and t >= imp and not m.landed[ti] then
          emit("light", T.X, T.Y + 2, T.Z, 0, 0, 0, 0.25, 9, 1, 0.95, 0.65, 0.5)
          flash({ 1, 1, 0.85 }, 0.2, 0.1, now)
          Fx.decal("scorch", T.X, T.foot or 0, T.Z, min(2.5, T.h) * 0.5, now)
        end
        if t >= imp then landOnce(m, ti, T, 1, now) end
      end
    elseif kind == "drain" then
      for ti, T in ipairs(m.targets) do
        if t >= imp then
          if not m.landed[ti] then
            local X, Y, Z = aimAt(T)
            for j = 1, 10 do
              local p = emit("glow", X, Y, Z, (rnd(m.seed, j) - 0.5) * 4, 1 + 2 * rnd(m.seed, j + 1), (rnd(m.seed, j + 2) - 0.5) * 3,
                2, 0.22, 0.45, 1, 0.45, 0.9)
              if p then p.home = m.from; p.grow = 0 end
            end
          end
          landOnce(m, ti, T, 1, now)
        end
      end
      if t > m.len * 0.7 and not m.healed then
        m.healed = true
        burstOf("twinkle", 12, m.from.X, m.from.Y, m.from.Z + 0.3, 1.2, 0.6, 1, 0.05 * min(3, m.from.h), 0.5, 1, 0.5, 1, m.from.foot)
        emit("glow", m.from.X, m.from.Y, m.from.Z + 0.3, 0, 0, 0, 0.5, m.from.h * 0.6, 0.4, 1, 0.4, 0.4)
      end
    elseif kind == "self" then
      local f = m.from
      if not m.started then
        m.started = true
        local gr = emit("gring", f.X, (f.foot or 0) + 0.02, f.Z, 0, 0, 0, 0.7, f.h * 0.9, tc[1], tc[2], tc[3], 0.8)
        if gr then gr.w = f.h * 0.2 end
      end
      if tick and t < m.len * 0.75 then
        seedN = seedN + 1
        local th = rnd(seedN, 1) * 2 * pi
        local r = f.h * 0.35
        emit("glow", f.X + cos(th) * r, (f.foot or 0) + 0.05, f.Z + sin(th) * r * 0.6, 0, f.h * 1.6, 0, 0.6, f.h * 0.07,
          tc[1], tc[2], tc[3], 0.8)
        if rnd(seedN, 2) > 0.6 then
          emit("twinkle", f.X + cos(th) * r * 0.8, f.Y, f.Z + 0.3, 0, f.h * 0.8, 0, 0.6, f.h * 0.03, 1, 1, 1, 0.8)
        end
      end
    elseif kind == "wave" then
      local sh = spec.shape
      if sh == "water" or sh == "ground" or sh == "fire" or not sh then
        local z = wallZ(m, t)
        -- spray along the crest
        if tick and t < m.len * 0.85 then
          local H = wallH(m)
          for j = 1, 3 do
            seedN = seedN + 1
            local x = (rnd(seedN, 1) - 0.5) * 16
            if sh == "fire" then emit("ember", x, H * (0.2 + 0.7 * rnd(seedN, 4)), z, (rnd(seedN, 5) - 0.5) * 1.5, 1 + 2 * rnd(seedN, 6), 1, 0.9, 0.05, 1, 0.5, 0.1, 1)
            elseif sh == "ground" then emit("dust", x, H, z + 0.2, 0, 0.6, 1.5, 1, 0.45, 0.62, 0.5, 0.36, 0.5)
            else emit("drop", x, H, z + 0.1, (rnd(seedN, 2) - 0.5), 2 + rnd(seedN, 3) * 2, 2.5, 0.8, 0.05, 0.6, 0.85, 1, 0.9) end
          end
        end
        for ti, T in ipairs(m.targets) do
          if z >= T.Z then
            if not m.landed[ti] and sh ~= "fire" and sh ~= "ground" then
              burstOf("drop", 30, T.X, 1.2, T.Z + 0.3, 5, 0.75, 1, 0.06, 0.6, 0.85, 1, 0.9, 0)
            end
            landOnce(m, ti, T, 1, now)
          end
        end
      elseif sh == "wind" then
        if tick and t < m.len * 0.8 then
          for j = 1, 4 do
            seedN = seedN + 1
            local pz = Sc and Sc.PAD.z or -9.2
            local z = pz + 2 + rnd(seedN, 1) * 9
            emit("streak", -9, 0.2 + rnd(seedN, 2) * 3, z, 18 + rnd(seedN, 3) * 8, (rnd(seedN, 4) - 0.5) * 2, 1, 1.1, 0.02,
              0.92, 0.96, 1, 0.7)
          end
          if rnd(now, 5) > 0.6 then emit("dust", (rnd(now, 6) - 0.5) * 8, 0.2, -2 + rnd(now, 7) * 2, 6, 0.3, 0.5, 1, 0.4, 0.8, 0.78, 0.72, 0.35) end
        end
        for ti, T in ipairs(m.targets) do if t >= imp then landOnce(m, ti, T, 1, now) end end
      else
        -- sound, light: rings rolling out of the user
        if t < imp and (m.lastRing or -1) + 0.12 <= t then
          m.lastRing = t
          local rg = emit("ring", fx, fy, fz, 0, 0, 0, 0.7, 7, tc[1], tc[2], tc[3], sh == "light" and 0.45 or 0.5)
          if rg then rg.w = 0.35; rg.flat = 0.75 end
          local gr = emit("gring", m.from.X, (m.from.foot or 0) + 0.03, m.from.Z, 0, 0, 0, 0.9, 11, tc[1], tc[2], tc[3], 0.5)
          if gr then gr.w = 0.7 end
        end
        if sh == "light" and t >= imp and not m.lit then
          m.lit = true
          emit("light", fx, fy, fz, 0, 0, 0, 0.5, 14, 1, 0.97, 0.85, 0.35)
          flash({ 1, 1, 0.92 }, 0.3, 0.25, now)
        end
        for ti, T in ipairs(m.targets) do if t >= imp then landOnce(m, ti, T, 1, now) end end
      end
    end
  end

  -- ------- drawing a move (in a layer)

  local function drawBeam(G2, m, t, now, layer)
    local imp = m.impact or m.len
    for _, T in ipairs(m.targets) do
      if (T.boss and "mid" or "front") == layer then
        local x1, y1, z1 = mouth(m)
        local x2, y2, z2 = aimAt(T)
        local grow = smooth(0, 1, t / imp)
        local thin = t > m.len * 0.7 and max(0, 1 - (t - m.len * 0.7) / (m.len * 0.3)) or 1
        local ex, ey, ez = x1 + (x2 - x1) * grow, y1 + (y2 - y1) * grow, z1 + (z2 - z1) * grow
        local a1, b1, k1 = P(x1, y1, z1)
        local a2, b2, k2 = P(ex, ey, ez)
        if a1 and a2 then
          local W = (m.from.boss and 0.55 or 0.22) * (m.big and 1.6 or 1) * thin * (1 + 0.06 * sin(now * 45))
          G2.setBlendMode("add")
          local sh = shader("beam")
          if sh and stripReady() then
            sh:send("time", now)
            sh:send("tint", m.tc)
            G2.setShader(sh)
            G2.setColor(1, 1, 1, 1)
            band(G2, a1, b1, W * k1 * 2.4, a2, b2, W * k2 * 2.4, 1, 1, 1, 0.35)
            band(G2, a1, b1, W * k1, a2, b2, W * k2, 1, 1, 1, 1)
            G2.setShader()
          else
            G2.setLineWidth(max(2, W * k2))
            G2.setColor(m.tc[1], m.tc[2], m.tc[3], 0.7)
            G2.line(a1, b1, a2, b2)
            G2.setLineWidth(max(1, W * k2 * 0.35))
            G2.setColor(1, 1, 1, 1)
            G2.line(a1, b1, a2, b2)
            G2.setLineWidth(1)
          end
          orbAt(G2, a1, b1, W * k1 * 1.6 * (0.9 + 0.1 * sin(now * 30)), m.tc, thin, now)
          if grow >= 1 then orbAt(G2, a2, b2, W * k2 * 2.6 * (0.85 + 0.15 * sin(now * 37)), m.tc, thin, now) end
          G2.setBlendMode("alpha")
        end
      end
    end
  end

  local function drawShots(G2, m, t, now, layer)
    local spec = m.spec
    local n = spec.n or 1
    local imp = m.impact or m.len
    local fly = max(0.15, imp - (n - 1) * SHOT_GAP)
    local sh = spec.shape or "ball"
    for _, T in ipairs(m.targets) do
      for k = 1, n do
        local g = (t - (k - 1) * SHOT_GAP) / fly
        if g > 0 and g < 1 then
          local X, Y, Z = shotPos(m, T, g, k)
          if layerOf(Z) == layer then
            local x, y, kk = P(X, Y, Z)
            if x then
              local R = (m.from.boss and 0.4 or 0.18) * (spec.big and 1.8 or 1) * (m.big and 1.4 or 1)
              local r = R * kk
              if sh == "rock" then
                for j = 0, 5 do
                  local th = now * 6 + k + j * pi / 3
                  local rr = r * (0.7 + 0.4 * rnd(m.seed + k, j))
                  chunkPts[j * 2 + 1], chunkPts[j * 2 + 2] = x + cos(th) * rr, y + sin(th) * rr
                end
                for j = 13, #chunkPts do chunkPts[j] = nil end
                G2.setColor(0.5, 0.41, 0.32, 1)
                rockPoly(G2, chunkPts, max(2, r * 0.5))
              elseif sh == "apple" then
                G2.setColor(0.55, 0.08, 0.08, 1)
                G2.circle("fill", x, y, r, 24)
                G2.setColor(0.85, 0.2, 0.15, 1)
                G2.circle("fill", x - r * 0.15, y - r * 0.15, r * 0.8, 24)
                G2.setColor(1, 0.9, 0.85, 0.8)
                G2.circle("fill", x - r * 0.4, y - r * 0.4, r * 0.18, 10)
                G2.setColor(0.3, 0.6, 0.2, 1)
                G2.ellipse("fill", x + r * 0.3, y - r * 1.05, r * 0.35, r * 0.14, 10)
              elseif sh == "coin" then
                local sx = abs(cos(now * 12 + k))
                G2.setColor(0.75, 0.55, 0.12, 1)
                G2.ellipse("fill", x, y, max(1, r * sx), r, 16)
                G2.setColor(1, 0.85, 0.3, 1)
                G2.ellipse("fill", x - r * 0.1 * sx, y - r * 0.08, max(0.8, r * 0.75 * sx), r * 0.78, 16)
              elseif sh == "leaf" then
                G2.push()
                G2.translate(x, y)
                G2.rotate(now * 10 + k)
                G2.setColor(0.25, 0.6, 0.2, 1)
                G2.ellipse("fill", 0, 0, r * 1.3, r * 0.45, 14)
                G2.setColor(0.5, 0.9, 0.35, 1)
                G2.ellipse("fill", -r * 0.15, -r * 0.08, r * 0.9, r * 0.2, 14)
                G2.pop()
              elseif sh == "blade" then
                -- a crescent of air
                G2.setBlendMode("add")
                G2.push()
                G2.translate(x, y)
                G2.rotate(now * 3 + k)
                G2.setLineWidth(max(1, r * 0.35))
                G2.setColor(0.85, 0.95, 1, 0.45)
                G2.arc("line", "open", 0, 0, r * 1.5, -1.1, 1.1, 18)
                G2.setLineWidth(max(1, r * 0.12))
                G2.setColor(1, 1, 1, 0.95)
                G2.arc("line", "open", 0, 0, r * 1.5, -0.9, 0.9, 18)
                G2.pop()
                G2.setBlendMode("alpha")
              else
                G2.setBlendMode("add")
                orbAt(G2, x, y, r * 1.6, m.tc, 1, now + k)
                if sh == "star" or sh == "shuriken" then
                  G2.push()
                  G2.translate(x, y)
                  G2.rotate(now * 9 + k)
                  G2.setColor(1, 1, 1, 0.9)
                  for j = 0, (sh == "star" and 4 or 3) do
                    G2.rotate(2 * pi / (sh == "star" and 5 or 4))
                    G2.ellipse("fill", r * 0.6, 0, r * 0.7, r * 0.12, 10)
                  end
                  G2.pop()
                end
                G2.setBlendMode("alpha")
              end
            end
          end
        end
      end
    end
  end

  -- what falls (drop): its place now
  function dropPos(m, T, t, k)
    local spec = m.spec
    local n = (spec.shape == "rock" or spec.shape == "coin") and (spec.n or 3) or 1
    local imp = m.impact or m.len
    local lag = n > 1 and rnd(m.seed, k + 7) * 0.12 or 0
    local ff = min(1, max(0, (t - lag) / (imp - lag * 0.5)))
    local ox = n > 1 and (rnd(m.seed, k) - 0.5) * min(3, T.h) * 0.9 or 0
    local oz = n > 1 and (rnd(m.seed, k + 3) - 0.5) * 0.6 or 0
    local foot = T.foot or 0
    local top = foot + 9
    local land = T.boss and T.Y or foot + 0.35
    return T.X + ox, top + (land - top) * ff * ff, T.Z + oz + 0.3, ff
  end
  local function drawDrops(G2, m, t, now, layer)
    local spec = m.spec
    local n = (spec.shape == "rock" or spec.shape == "coin") and (spec.n or 3) or 1
    local imp = m.impact or m.len
    for _, T in ipairs(m.targets) do
      local foot = T.foot or 0
      if layer == "back" and t < imp + 0.1 then
        -- its shadow, gathering
        local f = min(1, t / imp)
        groundPatch(G2, T.X, foot + 0.01, T.Z, min(3, T.h) * 0.5 * (0.4 + 0.6 * f) * (m.big and 1.4 or 1), m.seed, 0, 0, 0, 0.45 * f)
      end
      if t < imp then
        for k = 1, n do
          local X, Y, Z = dropPos(m, T, t, k)
          if layerOf(Z) == layer then
            local x, y, kk = P(X, Y, Z)
            if x then
              local R = min(3, T.h) * (n > 1 and 0.22 or 0.42) * (m.big and 1.4 or 1)
              local r = R * kk
              local sh = spec.shape
              if sh == "rock" or sh == "slab" then
                for j = 0, 6 do
                  local th = now * 2 + j * 2 * pi / 7
                  local rr = r * (0.7 + 0.45 * rnd(m.seed + k, j))
                  chunkPts[j * 2 + 1], chunkPts[j * 2 + 2] = x + cos(th) * rr, y + sin(th) * rr * 0.9
                end
                for j = 15, #chunkPts do chunkPts[j] = nil end
                G2.setColor(0.48, 0.4, 0.31, 1)
                rockPoly(G2, chunkPts, max(2, r * 0.35))
                G2.setColor(0.7, 0.6, 0.48, 0.6)
                G2.polygon("fill", chunkPts[1], chunkPts[2], chunkPts[3], chunkPts[4], chunkPts[5], chunkPts[6], x, y)
              elseif sh == "coin" then
                local sx = abs(cos(now * 12 + k))
                G2.setColor(0.75, 0.55, 0.12, 1)
                G2.ellipse("fill", x, y, max(1, r * 0.6 * sx), r * 0.6, 16)
                G2.setColor(1, 0.85, 0.3, 1)
                G2.ellipse("fill", x, y - r * 0.05, max(0.8, r * 0.45 * sx), r * 0.45, 16)
              elseif sh == "apple" then
                G2.setColor(0.55, 0.08, 0.08, 1)
                G2.circle("fill", x, y, r, 28)
                G2.setColor(0.85, 0.2, 0.15, 1)
                G2.circle("fill", x - r * 0.15, y - r * 0.15, r * 0.8, 28)
                G2.setColor(1, 0.9, 0.85, 0.8)
                G2.circle("fill", x - r * 0.4, y - r * 0.4, r * 0.16, 10)
              else
                -- a fist, a foot, a body coming down: a falling star of the type's energy, its streak above it
                G2.setBlendMode("add")
                local x0, y0 = P(X, Y + 2.5, Z)
                if x0 then band(G2, x0, y0, r * 0.3, x, y, r * 1.6, m.tc[1], m.tc[2], m.tc[3], 0.35) end
                orbAt(G2, x, y, r * 1.5, m.tc, 1, now)
                G2.setBlendMode("alpha")
              end
            end
          end
        end
      end
    end
  end

  -- the slab: one great block of rock over everyone it falls on
  local slabPts = {}
  local function face(G2, pts, cr, cg, cb, a, scale)
    G2.setColor(cr, cg, cb, a)
    rockPoly(G2, pts, scale)
  end
  local function drawSlab(G2, m, t, now, layer)
    local imp = m.impact or m.len
    if not m.box then
      local x0, x1, zs, hmax = math.huge, -math.huge, 0, 0
      for _, T in ipairs(m.targets) do
        x0, x1 = min(x0, T.X), max(x1, T.X)
        zs, hmax = zs + T.Z, max(hmax, T.h)
      end
      if #m.targets == 0 then return end
      local cz = zs / #m.targets
      local pad = 1.2 + hmax * 0.5
      m.box = { x0 = x0 - pad, x1 = x1 + pad, z0 = cz - 1.4, z1 = cz + 1.1, h = (m.big and 2.1 or 1.7) }
    end
    local b = m.box
    if layer == "back" and t < imp then
      -- its shadow spreading
      local f = min(1, t / imp)
      local a = 0.55 * f * f
      local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
      local hw, hd = (b.x1 - b.x0) / 2 * (0.5 + 0.5 * f), (b.z1 - b.z0) / 2 * (0.5 + 0.5 * f)
      local p1x, p1y = P(cx - hw, 0.01, cz - hd)
      local p2x, p2y = P(cx + hw, 0.01, cz - hd)
      local p3x, p3y = P(cx + hw, 0.01, cz + hd)
      local p4x, p4y = P(cx - hw, 0.01, cz + hd)
      if p1x and p2x and p3x and p4x then
        G2.setColor(0, 0, 0, a)
        G2.polygon("fill", p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
      end
    end
    if layer ~= "front" or m.shattered then return end
    -- its height: falling (faster as it comes), then a jolt as it bites into the ground
    local top = 11
    local yb
    if t < imp then
      local f = t / imp
      yb = top * (1 - f * f * f)
    else
      local v = t - imp
      yb = -0.12 * min(1, v / 0.08) + 0.04 * sin(v * 40) * max(0, 1 - v / 0.3)
    end
    local x0, x1, z0, z1, y0, y1 = b.x0, b.x1, b.z0, b.z1, yb, yb + b.h
    local eye = Sc and Sc.eye or { 0, 1, 6 }
    local _, _, kk = P((x0 + x1) / 2, y1, z1)
    local scale = max(4, (kk or 40) * 0.55)
    local function pt(i, X, Y, Z)
      local x, y = P(X, Y, Z)
      if not x then return false end
      slabPts[i * 2 - 1], slabPts[i * 2] = x, y
      return true
    end
    for i = 9, #slabPts do slabPts[i] = nil end
    local RC = { 0.4, 0.34, 0.28 }
    -- (only the faces turned to the eye)
    if eye[2] > y1 and pt(1, x0, y1, z0) and pt(2, x1, y1, z0) and pt(3, x1, y1, z1) and pt(4, x0, y1, z1) then
      face(G2, slabPts, RC[1] * 1.15, RC[2] * 1.15, RC[3] * 1.15, 1, scale)
    end
    if eye[1] > x1 and pt(1, x1, y1, z1) and pt(2, x1, y1, z0) and pt(3, x1, y0, z0) and pt(4, x1, y0, z1) then
      face(G2, slabPts, RC[1] * 0.55, RC[2] * 0.55, RC[3] * 0.55, 1, scale)
    end
    if eye[1] < x0 and pt(1, x0, y1, z0) and pt(2, x0, y1, z1) and pt(3, x0, y0, z1) and pt(4, x0, y0, z0) then
      face(G2, slabPts, RC[1] * 0.55, RC[2] * 0.55, RC[3] * 0.55, 1, scale)
    end
    if pt(1, x0, y1, z1) and pt(2, x1, y1, z1) and pt(3, x1, y0, z1) and pt(4, x0, y0, z1) then
      face(G2, slabPts, RC[1] * 0.8, RC[2] * 0.8, RC[3] * 0.8, 1, scale)
      -- its top edge catching the light, and cracks across its face (opening once it has landed)
      G2.setColor(0.85, 0.78, 0.66, 0.7)
      G2.setLineWidth(max(1, scale * 0.15))
      G2.line(slabPts[1], slabPts[2], slabPts[3], slabPts[4])
      local open = t >= imp and min(1, (t - imp) / 0.3) or 0.15
      G2.setColor(0.12, 0.09, 0.07, 0.9)
      G2.setLineWidth(max(1, scale * (0.12 + 0.2 * open)))
      for j = 1, 4 do
        local fx0 = x0 + (x1 - x0) * (j / 5 + (rnd(m.seed, j) - 0.5) * 0.08)
        local n = 0
        local ok = true
        for s = 0, 4 do
          local yy = y1 - (y1 - y0) * (s / 4) * open
          local xx = fx0 + (rnd(m.seed, j * 10 + s) - 0.5) * (x1 - x0) * 0.06
          local x, y = P(xx, yy, z1 + 0.001)
          if not x then ok = false; break end
          crackPts[n + 1], crackPts[n + 2] = x, y
          n = n + 2
        end
        for q = n + 1, #crackPts do crackPts[q] = nil end
        if ok and n >= 4 then G2.line(crackPts) end
      end
      G2.setLineWidth(1)
    end
  end

  -- claw strokes raked across the target
  local function drawSlash(G2, m, t, now, layer)
    local imp = m.impact or m.len
    for _, T in ipairs(m.targets) do
      local X, Y, Z = aimAt(T)
      if layerOf(Z) == layer and stripReady() then
        local x, y, k = P(X, Y, Z)
        if x then
          local S = min(3, T.h) * k * (m.big and 1.3 or 1)
          G2.setBlendMode("add")
          for j = 0, 2 do
            local g = smooth(0, 1, (t - j * 0.05) / imp)
            local fade = t > imp + 0.05 and max(0, 1 - (t - imp - 0.05) / 0.3) or 1
            if g > 0 and fade > 0 then
              local ax, ay = x - S * 0.45 + j * S * 0.22, y - S * 0.55
              local bx, by = ax + S * 0.55, ay + S * 1.05
              local cx, cy = (ax + bx) / 2 + S * 0.18, (ay + by) / 2 - S * 0.05
              for pass = 1, 2 do
                local W = pass == 1 and S * 0.09 or S * 0.03
                local cr, cg, cb = pass == 1 and m.tc[1] or 1, pass == 1 and m.tc[2] or 1, pass == 1 and m.tc[3] or 1
                local n = 0
                local N = 14
                for q = 0, N do
                  local s = q / N * g
                  local u1 = 1 - s
                  local px = u1 * u1 * ax + 2 * u1 * s * cx + s * s * bx
                  local py = u1 * u1 * ay + 2 * u1 * s * cy + s * s * by
                  local s2 = min(1, s + 0.01)
                  local v1 = 1 - s2
                  local qx = v1 * v1 * ax + 2 * v1 * s2 * cx + s2 * s2 * bx
                  local qy = v1 * v1 * ay + 2 * v1 * s2 * cy + s2 * s2 * by
                  local dx, dy = qx - px, qy - py
                  local l = sqrt(dx * dx + dy * dy) + 1e-6
                  local nx, ny = -dy / l, dx / l
                  local w = W * sin(pi * (q / N)) + 0.5
                  local a = (pass == 1 and 0.6 or 1) * fade * (0.35 + 0.65 * q / N)
                  n = n + 1; sv(n, px + nx * w, py + ny * w, 0, 0, cr, cg, cb, a)
                  n = n + 1; sv(n, px - nx * w, py - ny * w, 0, 1, cr, cg, cb, a)
                end
                G2.setColor(1, 1, 1, 1)
                stripDraw(G2, n)
              end
            end
          end
          G2.setBlendMode("alpha")
        end
      end
    end
  end

  -- fangs closing on it
  local function drawBite(G2, m, t, now, layer)
    local imp = m.impact or m.len
    for _, T in ipairs(m.targets) do
      local X, Y, Z = aimAt(T)
      if layerOf(Z) == layer then
        local x, y, k = P(X, Y, Z)
        if x then
          local S = min(3, T.h) * k * (m.big and 1.3 or 1)
          local c = min(1, t / imp)
          c = c * c
          local gap = S * 0.5 * (1 - c)
          local a = t < m.len * 0.75 and 1 or max(0, 1 - (t - m.len * 0.75) / (m.len * 0.25))
          local shake = t > imp and sin(t * 70) * S * 0.02 * max(0, 1 - (t - imp) / 0.2) or 0
          G2.setBlendMode("add")
          glowAt(G2, x, y - gap - S * 0.15, S * 0.9, m.tc[1], m.tc[2], m.tc[3], 0.35 * a)
          glowAt(G2, x, y + gap + S * 0.15, S * 0.9, m.tc[1], m.tc[2], m.tc[3], 0.35 * a)
          G2.setBlendMode("alpha")
          local W = S * 0.95
          for row = -1, 1, 2 do
            local base = y + row * (gap + S * 0.3) + shake
            for j = 0, 4 do
              local fx0 = x - W / 2 + j * W / 5
              local fw = W / 5
              local len = S * (0.26 + ((j == 0 or j == 4) and 0.06 or 0)) * (1 - abs(j - 2) * 0.12)
              local tipX, tipY = fx0 + fw * 0.5 + row * fw * 0.08, base - row * len
              G2.setColor(0.72, 0.7, 0.68, a)
              G2.polygon("fill", fx0, base, fx0 + fw, base, tipX, tipY)
              G2.setColor(0.98, 0.97, 0.95, a)
              G2.polygon("fill", fx0 + fw * 0.15, base, fx0 + fw * 0.62, base, tipX, tipY)
            end
            G2.setColor(0.35, 0.08, 0.1, a * 0.85)
            G2.rectangle("fill", x - W / 2, base + (row < 0 and -S * 0.06 or 0), W, S * 0.06)
          end
        end
      end
    end
  end

  -- lightning from the sky
  local skyPts = {}
  local function drawBolt(G2, m, t, now, layer)
    if layer ~= "front" then return end
    local imp = m.impact or m.len
    if t < imp - 0.06 then
      -- the air charging: a flicker high above
      return
    end
    local v = t - imp
    local flick = (floor(now * 22) % 3 ~= 1) and 1 or 0.35
    local a = (v < 0.35 and 1 or max(0, 1 - (v - 0.35) / 0.25)) * flick
    if a <= 0 then return end
    G2.setBlendMode("add")
    for ti, T in ipairs(m.targets) do
      local seed = m.seed + ti * 9 + floor(now * 18)
      local X, Y, Z = aimAt(T)
      local _, _, k = P(X, Y, Z)
      local w = max(1.2, (k or 40) * 0.05 * (m.big and 1.5 or 1))
      local n = jagged(skyPts, X + (rnd(seed, 1) - 0.5) * 3, Y + 16, Z - 2, X, Y, Z, seed, 0.38, 5)
      if n >= 4 then glowLine(G2, skyPts, w, m.tc, a) end
      for b = 1, 2 do
        local i = 2 + floor(rnd(seed, b + 3) * (#skyPts / 2 - 4))
        local bx0, by0 = skyPts[i * 2 - 1], skyPts[i * 2]
        if bx0 then
          -- a short fork off it, on screen
          local ex, ey = bx0 + (rnd(seed, b + 7) - 0.5) * w * 40, by0 + w * (12 + 18 * rnd(seed, b + 9))
          G2.setLineWidth(max(1, w * 0.5))
          G2.setColor(m.tc[1], m.tc[2], m.tc[3], 0.6 * a)
          G2.line(bx0, by0, (bx0 + ex) / 2 + (rnd(seed, b + 11) - 0.5) * w * 10, (by0 + ey) / 2, ex, ey)
        end
      end
      local x, y = P(X, Y, Z)
      if x then glowAt(G2, x, y, w * 30, m.tc[1], m.tc[2], m.tc[3], 0.6 * a) end
    end
    G2.setBlendMode("alpha")
    G2.setLineWidth(1)
  end

  -- rings sent at it
  local function drawRings(G2, m, t, now, layer)
    local imp = m.impact or m.len
    local fx, fy, fz = mouth(m)
    local sh = m.spec.shape
    for _, T in ipairs(m.targets) do
      local X, Y, Z = aimAt(T)
      for j = 0, 3 do
        local g = (t / imp) * 1.0 - j * 0.14
        if g > 0 and g < 1.15 then
          local gg = min(1, g)
          local px, py, pz = fx + (X - fx) * gg, fy + (Y - fy) * gg, fz + (Z - fz) * gg
          if layerOf(pz) == layer then
            local x, y, k = P(px, py, pz)
            if x then
              local R = min(3, T.h) * (0.3 + 0.35 * gg) * k
              local a = (g > 1 and max(0, 1 - (g - 1) / 0.15) or 1) * (0.5 + 0.5 * gg)
              if sh == "dark" then
                screenRing(G2, x, y, R, R * 0.85, max(1, R * 0.25), 0.1, 0.02, 0.15, 0.7 * a)
                G2.setBlendMode("add")
                screenRing(G2, x, y, R, R * 0.85, max(1, R * 0.06), 0.5, 0.2, 0.7, 0.6 * a)
              elseif sh == "eye" then
                G2.setBlendMode("add")
                screenRing(G2, x, y, R, R * 0.45, max(1, R * 0.12), 1, 0.3, 0.35, a)
                glowAt(G2, x, y, R * 0.5, 1, 0.25, 0.3, a)
              else
                G2.setBlendMode("add")
                screenRing(G2, x, y, R, R * 0.85, max(1, R * 0.16), m.tc[1], m.tc[2], m.tc[3], 0.8 * a)
                screenRing(G2, x, y, R * 1.04, R * 0.89, max(1, R * 0.05), 1, 1, 1, 0.5 * a)
              end
              G2.setBlendMode("alpha")
            end
          end
        end
      end
    end
  end

  -- points erupting from the ground round it
  local function drawSpikes(G2, m, t, now, layer)
    local imp = m.impact or m.len
    local sh = m.spec.shape
    local up = smooth(imp * 0.6, imp, t)
    local sink = t > m.len * 0.75 and smooth(m.len * 0.75, m.len, t) or 0
    if up <= 0 then return end
    for ti, T in ipairs(m.targets) do
      local foot = T.foot or 0
      local S = min(2.5, T.h) * (m.big and 1.3 or 1)
      for j = 1, 7 do
        local th = (j / 7) * 2 * pi + rnd(m.seed + ti, j)
        local rr = S * (0.25 + 0.3 * rnd(m.seed + ti, j + 10))
        local X, Z = T.X + cos(th) * rr, T.Z + sin(th) * rr * 0.7
        if layerOf(Z) == layer then
          local H = S * (0.6 + 0.5 * rnd(m.seed + ti, j + 20)) * up
          local base = foot - H * sink
          local r = S * 0.11
          local lean = (rnd(m.seed + ti, j + 30) - 0.5) * S * 0.25 + cos(th) * S * 0.12
          local ax, ay = P(X + lean, base + H, Z)
          local lx, ly = P(X - r, base, Z)
          local rx, ry = P(X + r, base, Z)
          local fx, fy, k = P(X, base, Z + r * 0.8)
          if ax and lx and rx and fx then
            local c1, c2
            if sh == "steel" then c1, c2 = { 0.82, 0.86, 0.92 }, { 0.42, 0.46, 0.52 }
            elseif sh == "root" then c1, c2 = { 0.5, 0.36, 0.2 }, { 0.28, 0.19, 0.1 }
            else c1, c2 = { 0.62, 0.52, 0.4 }, { 0.36, 0.29, 0.22 } end
            local sc = max(2, k * 0.08)
            G2.setColor(c1[1], c1[2], c1[3], 1)
            rockPoly(G2, { lx, ly, fx, fy, ax, ay }, sc)
            G2.setColor(c2[1], c2[2], c2[3], 1)
            rockPoly(G2, { fx, fy, rx, ry, ax, ay }, sc)
            if sh == "steel" then
              G2.setBlendMode("add")
              G2.setColor(1, 1, 1, 0.6)
              G2.setLineWidth(max(1, k * 0.015))
              G2.line(fx, fy, ax, ay)
              G2.setBlendMode("alpha")
              G2.setLineWidth(1)
            end
          end
        end
      end
    end
  end

  -- a wall rolling over the party (water, sand, fire)
  local function drawWall(G2, m, t, now, layer)
    local sh = m.spec.shape or "water"
    local z = wallZ(m, t)
    if layerOf(z) ~= layer then return end
    local imp = m.impact or m.len
    local a = t <= imp and min(1, t / 0.15) or max(0, 1 - (t - imp) / (m.len - imp))
    if a <= 0 or not stripReady() then return end
    local H = wallH(m) * (0.85 + 0.15 * min(1, t / imp))
    local XW = 10
    local N = 20
    local n = 0
    for i = 0, N do
      local X = -XW + 2 * XW * i / N
      local zz = z + sin(i * 0.9 + now * 3) * 0.12
      local tx, ty = P(X, H, zz)
      local bx, by = P(X, 0, zz)
      if not (tx and bx) then return end
      n = n + 1; sv(n, tx, ty, i / N, 0, 1, 1, 1, 1)
      n = n + 1; sv(n, bx, by, i / N, 1, 1, 1, 1, 1)
    end
    local S
    if sh == "fire" then
      S = shader("fire")
      if S then
        S:send("time", now)
        S:send("seed", m.seed % 10)
        S:send("aspect", 2 * XW / H)
        S:send("blaze", 0)
      end
    else
      S = shader("wall")
      if S then
        local C = WALL[sh] or WALL.water
        S:send("time", now)
        S:send("aspect", 2 * XW / H * 0.35)
        S:send("deep", C.deep)
        S:send("shallow", C.shallow)
        S:send("foam", C.foam)
      end
    end
    if S then
      G2.setShader(S)
      G2.setColor(1, 1, 1, a)
      stripDraw(G2, n)
      G2.setShader()
    else
      for i = 1, n do strip.v[i][5], strip.v[i][6], strip.v[i][7] = sh == "fire" and 1 or 0.3, sh == "fire" and 0.45 or 0.6, sh == "fire" and 0.1 or 1 end
      G2.setColor(1, 1, 1, 0.7 * a)
      stripDraw(G2, n)
    end
  end

  -- the user's aura (a stat raised): a column of light
  local function drawSelf(G2, m, t, now, layer)
    local f = m.from
    if layerOf(f.Z + 0.3) ~= layer then return end
    local a = sin(min(1, t / m.len) * pi)
    local x1, y1, k1 = P(f.X, f.foot or 0, f.Z + 0.3)
    local x2, y2, k2 = P(f.X, (f.foot or 0) + f.h * 1.5, f.Z + 0.3)
    if not (x1 and x2) then return end
    G2.setBlendMode("add")
    local sh = shader("beam")
    if sh and stripReady() then
      sh:send("time", now * 0.5)
      sh:send("tint", m.tc)
      G2.setShader(sh)
      band(G2, x1, y1, f.h * 0.9 * k1, x2, y2, f.h * 0.5 * k2, 1, 1, 1, 0.35 * a)
      G2.setShader()
    end
    local x, y, k = P(f.X, f.Y, f.Z + 0.3)
    if x then glowAt(G2, x, y, f.h * k * 0.9, m.tc[1], m.tc[2], m.tc[3], 0.35 * a) end
    G2.setBlendMode("alpha")
  end

  local function drawMove(G2, m, now, layer)
    local t = now - m.t0
    if t < 0 or t > m.len then return end
    local kind = m.kind
    if kind == "beam" then drawBeam(G2, m, t, now, layer)
    elseif kind == "shot" then drawShots(G2, m, t, now, layer)
    elseif kind == "drop" and m.key ~= "slab" then drawDrops(G2, m, t, now, layer)
    elseif m.key == "slab" then drawSlab(G2, m, t, now, layer)
    elseif kind == "slash" then drawSlash(G2, m, t, now, layer)
    elseif kind == "bite" then drawBite(G2, m, t, now, layer)
    elseif kind == "bolt" then drawBolt(G2, m, t, now, layer)
    elseif kind == "rings" then drawRings(G2, m, t, now, layer)
    elseif kind == "spikes" then drawSpikes(G2, m, t, now, layer)
    elseif kind == "self" then drawSelf(G2, m, t, now, layer)
    elseif kind == "wave" then
      local sh = m.spec.shape
      if sh == "water" or sh == "ground" or sh == "fire" or not sh then drawWall(G2, m, t, now, layer) end
    end
  end

  local drawLasting, stepField   -- (below: what lasts)

  -- ------- the clock

  local last = nil
  function Fx.update(now)
    local dt = last and min(0.05, max(0, now - last)) or 0
    last = now
    if dt > 0 then
      stepCharge(now, dt)
      stepField(now, dt)
      for i = 1, #moves do
        local m = moves[i]
        stepMove(m, now, dt)
      end
      stepParts(dt)
    end
    for i = #moves, 1, -1 do
      if now - moves[i].t0 > moves[i].len + 0.05 then table.remove(moves, i) end
    end
    for i = #spots, 1, -1 do if now - spots[i].t0 > spots[i].dur then table.remove(spots, i) end end
    for i = #decals, 1, -1 do if now - decals[i].t0 > decals[i].life then table.remove(decals, i) end end
    for i = #flashes, 1, -1 do if now - flashes[i].t0 > flashes[i].dur then table.remove(flashes, i) end end
  end

  function Fx.clear()
    for i = #moves, 1, -1 do moves[i] = nil end
    for i = #parts, 1, -1 do pool[#pool + 1] = parts[i]; parts[i] = nil end
    for i = #spots, 1, -1 do spots[i] = nil end
    for i = #decals, 1, -1 do decals[i] = nil end
    for i = #flashes, 1, -1 do flashes[i] = nil end
    charge, last = nil, nil
    if Fx.setLasting then Fx.setLasting(nil, nil, false, nil, 0) end
  end

  function Fx.busy(now)
    for _, m in ipairs(moves) do if now - m.t0 <= m.len then return true end end
    return false
  end
  function Fx.stats() return { parts = #parts, moves = #moves, spots = #spots, decals = #decals } end

  -- ------- drawing by layer

  function Fx.drawLayer(G2, layer, now)
    if not Sc then return end
    G2.push("all")
    if layer == "back" then drawDecals(G2, now) end
    for _, m in ipairs(moves) do drawMove(G2, m, now, layer) end
    drawLasting(G2, layer, now)
    if layer == "mid" and charge then drawChargeOrb(G2, now) end
    for _, e in ipairs(spots) do
      if layerOf(e.Z) == layer then drawSpot(G2, e, now) end
    end
    drawParts(G2, layer)
    G2.pop()
  end

  -- the front layer, then the screen's own: the G-Max charge's wash, the flashes
  function Fx.draw(G2, w, h, now)
    if not Sc then return end
    Fx.drawLayer(G2, "front", now)
    G2.push("all")
    if charge then drawCharge(G2, w, h, now) end
    G2.setBlendMode("add")
    for _, f in ipairs(flashes) do
      local u = (now - f.t0) / f.dur
      if u >= 0 and u < 1 then
        G2.setColor(f.r, f.g, f.b, f.a * (1 - u) * (1 - u))
        G2.rectangle("fill", 0, 0, w, h)
      end
    end
    G2.pop()
  end
  -- (the raid's first pass drew the moves here; they are in the layers now)
  function Fx.drawMoves() end

  -- ------- what lasts, in the den: the G-Max field round the party, the boss's veil, its barrier.
  -- The raid sets them each frame (Fx.setLasting); the barrier's moments come as events
  -- (Fx.barrierUp / barrierHit / barrierBreak).

  local lasting = { field = nil, boss = nil, veil = false, shield = nil, fieldT0 = nil, acc = 0 }
  local barrier = { upT = nil, hitT = nil, breakT = nil }
  function Fx.setLasting(field, boss, veil, shield, now)
    if field ~= lasting.field then lasting.fieldT0 = now end
    lasting.field, lasting.boss, lasting.veil, lasting.shield = field, boss, veil and true or false, shield
  end
  function Fx.barrierUp(now) barrier.upT = now end
  function Fx.barrierHit(now) barrier.hitT = now end
  function Fx.barrierBreak(A, now)
    barrier.breakT = now
    if not A then return end
    -- the dome bursts: red shards and sparks flung out, a flash
    local R = A.h * 0.6
    for j = 1, 40 do
      seedN = seedN + 1
      local th, ph = rnd(seedN, 1) * 2 * pi, (rnd(seedN, 2) - 0.3) * pi * 0.8
      local nx, ny, nz = cos(ph) * cos(th), sin(ph), cos(ph) * sin(th)
      local p = emit("shard", A.X + nx * R, A.Y + ny * R, A.Z + nz * R, nx * 5, ny * 4 + 2, nz * 5 + 1, 1.3, 0.12,
        1, 0.35, 0.5, 1)
      if p then p.floor = A.foot or 0 end
    end
    burstOf("spark", 30, A.X, A.Y, A.Z + R * 0.5, 7, 0.2, 0.6, 0.04, 1, 0.3, 0.5, 1, A.foot)
    emit("light", A.X, A.Y, A.Z + R, 0, 0, 0, 0.35, A.h * 2.5, 1, 0.3, 0.5, 0.5)
    flash({ 1, 0.3, 0.45 }, 0.3, 0.25, now)
  end

  -- the party's middle and the ring a field stands on round it
  local FIELD = { CX = 0, CZ = -1.0, RX = 5.0, RZ = 2.3 }
  local function ringAt(th) return FIELD.CX + cos(th) * FIELD.RX, FIELD.CZ + sin(th) * FIELD.RZ end

  -- a band standing on the field's ring from angle a0 to a1, H tall, through a shader set up by the
  -- caller (tc.x along it, tc.y top to foot)
  local function ringWall(G2, a0, a1, H, wob, now)
    if not stripReady() then return end
    local N = 24
    local n = 0
    for i = 0, N do
      local th = a0 + (a1 - a0) * i / N
      local X, Z = ringAt(th)
      local h = H * (1 + wob * sin(th * 5 + now * 2))
      local tx, ty = P(X, h, Z)
      local bx, by = P(X, 0, Z)
      if not (tx and bx) then return end
      n = n + 1; sv(n, tx, ty, i / N, 0, 1, 1, 1, 1)
      n = n + 1; sv(n, bx, by, i / N, 1, 1, 1, 1, 1)
    end
    stripDraw(G2, n)
  end

  -- vines: tapered green strokes rising off the ring and curling, swaying
  local function drawVines(G2, now, back, a)
    if not stripReady() then return end
    for j = 1, 14 do
      local th = (j / 14) * 2 * pi + 0.2
      if (sin(th) < 0) == back then
        local X0, Z0 = ringAt(th)
        local H = 1.8 + 1.0 * rnd(7, j)
        local n = 0
        local ok = true
        local N = 14
        for q = 0, N do
          local f = q / N
          local curl = f * f * 1.6
          local sway = sin(now * 1.6 + j) * 0.25 * f
          local X = X0 - cos(th) * curl * 0.5 + sway
          local Y = f * H * (1 - 0.25 * f) + sin(f * 3) * 0.1
          local Z = Z0 - sin(th) * curl * 0.3
          local x, y, k = P(X, Y, Z)
          if not x then ok = false; break end
          local w = max(1, 0.13 * k * (1 - f * 0.85))
          n = n + 1; sv(n, x - w, y, 0, 0, 0.16, 0.42, 0.12, a)
          n = n + 1; sv(n, x + w, y, 0, 0, 0.32, 0.7, 0.22, a)
        end
        if ok then
          G2.setColor(1, 1, 1, 1)
          stripDraw(G2, n)
        end
        -- a leaf or two along it
        for l = 1, 2 do
          local f = 0.35 + 0.3 * l
          local x, y, k = P(X0 - cos(th) * f * f * 0.8 + sin(now * 1.6 + j) * 0.25 * f, f * H * 0.85, Z0)
          if x then
            G2.push()
            G2.translate(x, y)
            G2.rotate((l == 1 and -0.7 or 0.8) + sin(now * 2 + j) * 0.15)
            G2.setColor(0.22, 0.55, 0.16, a)
            G2.ellipse("fill", k * 0.12, 0, k * 0.14, k * 0.055, 12)
            G2.setColor(0.4, 0.78, 0.3, a)
            G2.ellipse("fill", k * 0.1, -k * 0.012, k * 0.1, k * 0.022, 12)
            G2.pop()
          end
        end
      end
    end
  end

  -- stones orbiting the party, tumbling
  local function drawStones(G2, now, back, a)
    for j = 1, 16 do
      local th = (j / 16) * 2 * pi + now * 0.35
      if (sin(th) < 0) == back then
        local X, Z = ringAt(th)
        local Y = 0.5 + 1.5 * rnd(11, j) + 0.15 * sin(now * 2 + j)
        local x, y, k = P(X, Y, Z)
        if x then
          local r = (0.3 + 0.35 * rnd(13, j)) * k
          -- its shadow on the ground
          local sx, sy = P(X, 0.01, Z)
          if sx then
            G2.setColor(0, 0, 0, 0.25 * a)
            G2.ellipse("fill", sx, sy, r * 0.8, r * 0.2, 12)
          end
          for q = 0, 5 do
            local an = now * (0.8 + rnd(17, j)) + q * pi / 3
            local rr = r * (0.7 + 0.45 * rnd(19 + j, q))
            chunkPts[q * 2 + 1], chunkPts[q * 2 + 2] = x + cos(an) * rr, y + sin(an) * rr * 0.85
          end
          for q = 13, #chunkPts do chunkPts[q] = nil end
          G2.setColor(0.42, 0.34, 0.27, a)
          rockPoly(G2, chunkPts, max(2, r * 0.4))
          G2.setColor(0.62, 0.52, 0.4, a * 0.7)
          G2.polygon("fill", chunkPts[1], chunkPts[2], chunkPts[3], chunkPts[4], chunkPts[5], chunkPts[6], x, y)
        end
      end
    end
  end

  local function drawField(G2, layer, now)
    local kind = lasting.field
    if not kind or layer == "back" then return end
    local back = layer == "mid"
    local a = min(1, (now - (lasting.fieldT0 or now)) / 0.6)
    local a0, a1 = back and pi or 0, back and 2 * pi or pi
    if kind == "FIRE" then
      local S = shader("fire")
      if S then
        S:send("time", now)
        S:send("seed", back and 3 or 7)
        S:send("aspect", 9)
        S:send("blaze", 0)
        G2.setShader(S)
        G2.setColor(1, 1, 1, 0.92 * a)
        ringWall(G2, a0, a1, back and 2.2 or 1.2, 0.18, now)
        G2.setShader()
      end
    elseif kind == "WATER" then
      local S = shader("wall")
      if S then
        local C = WALL.water
        S:send("time", now * 1.6)
        S:send("aspect", 3)
        S:send("deep", C.deep)
        S:send("shallow", C.shallow)
        S:send("foam", C.foam)
        G2.setShader(S)
        G2.setColor(1, 1, 1, 0.8 * a)
        ringWall(G2, a0, a1, back and 1.8 or 1.0, 0.2, now)
        G2.setShader()
      end
    elseif kind == "GRASS" then
      drawVines(G2, now, back, a)
    elseif kind == "ROCK" then
      drawStones(G2, now, back, a)
    end
  end
  function stepField(now, dt)
    local kind = lasting.field
    if not kind then return end
    lasting.acc = lasting.acc + dt * 30
    while lasting.acc >= 1 do
      lasting.acc = lasting.acc - 1
      seedN = seedN + 1
      local th = rnd(seedN, 1) * 2 * pi
      local X, Z = ringAt(th)
      if kind == "FIRE" then
        emit("ember", X, 0.5 + rnd(seedN, 2), Z, (rnd(seedN, 3) - 0.5) * 0.5, 1 + rnd(seedN, 4) * 1.5, 0, 1.2, 0.04,
          1, 0.5, 0.1, 1)
        if rnd(seedN, 5) > 0.8 then emit("smoke", X, 1.4, Z, 0, 0.6, 0, 2, 0.4, 0.15, 0.12, 0.11, 0.35) end
      elseif kind == "WATER" then
        local tx, tz = -sin(th) * 3, cos(th) * 1.4
        emit("drop", X, 0.6 + rnd(seedN, 2) * 0.6, Z, tx, 1.5 + rnd(seedN, 3) * 2, tz, 0.7, 0.04, 0.6, 0.85, 1, 0.8)
      elseif kind == "GRASS" then
        if rnd(seedN, 2) > 0.85 then emit("leaf", X, 1.5, Z, 0, 0, 0, 2, 0.08, 0.35, 0.8, 0.3, 1) end
      elseif kind == "ROCK" then
        if rnd(seedN, 2) > 0.9 then emit("dust", X, 0.15, Z, 0, 0.3, 0, 1.4, 0.35, 0.55, 0.47, 0.38, 0.35) end
      end
    end
  end

  -- the veil: a pale shimmering sphere round the boss, bands of light turning on it
  local veilPts = {}
  local function drawVeil(G2, now)
    local A = lasting.boss
    if not (A and lasting.veil) then return end
    local R = A.h * 0.58
    local x, y, k = P(A.X, A.Y, A.Z)
    if not x then return end
    G2.setBlendMode("add")
    screenRing(G2, x, y, R * k, R * k * 1.05, R * k * 0.25, 0.55, 0.85, 1, 0.4 + 0.1 * sin(now * 2))
    screenRing(G2, x, y, R * k * 0.98, R * k * 1.03, max(1, R * k * 0.04), 0.85, 0.97, 1, 0.6)
    glowAt(G2, x, y, R * k * 2, 0.5, 0.8, 1, 0.12)
    G2.setLineWidth(max(1, k * 0.025))
    for b = 0, 2 do
      local tilt = 0.5 + b * 0.55
      local spin = now * (0.5 + 0.2 * b) + b * 2
      local n = 0
      for q = 0, 32 do
        local th = spin + q / 32 * 2 * pi
        local cx, cz = cos(th) * R, sin(th) * R
        local py, pz = sin(tilt) * cz, cos(tilt) * cz
        local sx, sy = P(A.X + cx, A.Y + py, A.Z + pz)
        if not sx then n = 0; break end
        veilPts[n + 1], veilPts[n + 2] = sx, sy
        n = n + 2
      end
      for q = n + 1, #veilPts do veilPts[q] = nil end
      if n >= 4 then
        G2.setColor(0.7, 0.95, 1, 0.45)
        G2.line(veilPts)
      end
    end
    G2.setBlendMode("alpha")
    G2.setLineWidth(1)
  end

  -- the barrier: a dome of hexagons round the boss; the cells facing away fade, the rim glows
  -- (fresnel), a band of light runs up it; a hit ripples out from the front
  local hexPts = {}
  local function drawBarrier(G2, now)
    local A = lasting.boss
    local sh = lasting.shield
    if not (A and sh and sh.left and sh.left > 0 and Sc.eye) then return end
    local share = sh.max and sh.max > 0 and sh.left / sh.max or 1
    local up = barrier.upT and min(1, max(0, now - barrier.upT) / 0.5) or 1
    local R = A.h * 0.6
    local eye = Sc.eye
    local ex, ey, ez = eye[1] - A.X, eye[2] - A.Y, eye[3] - A.Z
    local el = sqrt(ex * ex + ey * ey + ez * ez)
    ex, ey, ez = ex / el, ey / el, ez / el
    local hitU = barrier.hitT and (now - barrier.hitT) / 0.6 or 2
    local cx, cy, k0 = P(A.X, A.Y, A.Z)
    if not cx then return end
    G2.setBlendMode("add")
    glowAt(G2, cx, cy, R * k0 * 1.9, 1, 0.2, 0.4, 0.2 * up * (0.6 + 0.4 * share))
    local ROWS = 11
    G2.setLineWidth(max(1, k0 * 0.03))
    for row = 0, ROWS - 1 do
      local ph = -pi / 2 * 0.92 + (row + 0.5) / ROWS * pi * 0.92
      local cosP = cos(ph)
      local nC = max(3, floor(22 * cosP + 0.5))
      for c = 0, nC - 1 do
        local th = (c + (row % 2) * 0.5) / nC * 2 * pi + now * 0.05
        local nx, ny, nz = cosP * cos(th), sin(ph), cosP * sin(th)
        local d = nx * ex + ny * ey + nz * ez
        if d > 0.02 then
          local fres = 1 - d
          local band = max(0, 1 - abs(((now * 0.35) % 1.4 - 0.2) - (ny + 1) / 2) * 6)
          local rip = 0
          if hitU < 1 then
            local ang = math.acos(min(1, d))
            rip = max(0, 1 - abs(ang - hitU * 2.2) * 3) * (1 - hitU)
          end
          local a = (0.18 + 0.7 * fres * fres + 0.3 * band + 0.9 * rip) * up * (0.45 + 0.55 * share)
          local tx, tz = -sin(th), cos(th)
          local bx, by, bz = -sin(ph) * cos(th), cosP, -sin(ph) * sin(th)
          local cr = 0.5 * pi / ROWS
          local okH = true
          for q = 0, 5 do
            local an = q * pi / 3 + pi / 6
            local ca, sa = cos(an) * cr, sin(an) * cr
            local px, py, pz = nx + tx * ca + bx * sa, ny + by * sa, nz + tz * ca + bz * sa
            local l = sqrt(px * px + py * py + pz * pz)
            local sx, sy = P(A.X + px / l * R, A.Y + py / l * R * 1.08, A.Z + pz / l * R)
            if not sx then okH = false; break end
            hexPts[q * 2 + 1], hexPts[q * 2 + 2] = sx, sy
          end
          if okH then
            G2.setColor(1, 0.22, 0.42, a * 0.16)
            G2.polygon("fill", hexPts)
            G2.setColor(1, 0.45 + 0.4 * rip, 0.6 + 0.3 * rip, a)
            G2.polygon("line", hexPts)
          end
        end
      end
    end
    G2.setBlendMode("alpha")
    G2.setLineWidth(1)
  end

  function drawLasting(G2, layer, now)
    drawField(G2, layer, now)
    if layer == "mid" then
      drawVeil(G2, now)
      drawBarrier(G2, now)
    end
  end

  -- (the first pass's screen-space drawing; the raid sets what lasts with Fx.setLasting now)
  function Fx.drawField() end
  function Fx.drawVeil() end
  function Fx.drawBarrier() end


  return Fx
end
