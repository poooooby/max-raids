-- A Max Raid's den (src/training/raid.lua) on the top screen: a cave built here in 3D - a raised
-- rock plateau with a cliff falling away at its front, the boss's round metal pad with a glowing
-- ring at its back, rough cave walls round it with a dark tunnel mouth, stalagmites and
-- stalactites, boulders - lit per vertex (a cool ambient, a shaft of light from the upper left,
-- the pad's warm glow, fog with distance). Over the picture, in 2D at projected points: the light
-- shaft, motes drifting in it (one mesh moved by a shader), the boss (the pack's frames, a red
-- outline, red wisps over its head, streaks swirling round it, sparks), then the party from behind
-- with their shadows. The camera sits behind and above the party looking down at the pad, with a
-- slow sway; Sc.shot eases it between poses (the intro's close-up, the reveal, over a member's
-- shoulder, in on the boss), Sc.shake jolts it, Sc.burst sets off the boss's roar.
--
-- Drawn by src/render3d.lua: Sc.prepare renders from the training layer's update (never inside the
-- engine's draw); Sc.draw places it. Without a 3D device the same camera paints a flat version.
--   Sc = raid_scene(mod, { Render3d })

return function(mod, deps)
  local Sc = { failed = false, why = nil }
  local sqrt, sin, cos, tan, rad, pi, floor = math.sqrt, math.sin, math.cos, math.tan, math.rad, math.pi, math.floor
  local min, max, abs = math.min, math.max, math.abs

  -- the den, in metres (y up, the camera looking down -z)
  --   PLAT      the plateau: its middle, half widths (x, z), the cliff's foot
  --   PAD       the boss's pad: middle, radius, height
  --   MEMBERS   the party's feet, left to right (a slight arc)
  --   CAVE      the walls: their middle, radius, foot and top
  Sc.PLAT = { cx = 0, cz = -5.4, rx = 9.6, rz = 7.0, foot = -4.5 }
  Sc.PAD = { x = 0, z = -9.2, r = 3.4, h = 0.22 }
  Sc.MEMBERS = { { x = -3.1, z = -0.75 }, { x = -1.05, z = -1.25 }, { x = 1.05, z = -1.25 }, { x = 3.1, z = -0.75 } }
  Sc.MEMBER_H = 1.1          -- a member's height (the boss's size is against it)
  -- a member's sprite: one scale for all (a 64-px pic's height in metres), so each keeps its own
  -- size against the others
  Sc.MEMBER_PIC_H = 1.75
  Sc.CAVE = { cx = 0, cz = -9, r = 25, y0 = -4.5, y1 = 19 }
  Sc.EYE = { 0, 1.15, 6.6 }    -- the battle's eye (fog is measured from here)
  Sc.ASPECT = 1.5
  Sc.NEAR, Sc.FAR = 0.05, 200
  Sc.CLEAR = { 0.03, 0.035, 0.04 }
  -- where the light comes from: the shaft (upper left, behind), the pad's glow
  Sc.LIGHT = { amb = { 0.3, 0.3, 0.31 }, key = { -10, 15, -11 }, keyRGB = { 0.85, 0.9, 0.84 },
    pad = { 1.0, 0.62, 0.34 }, padReach = 4.2, fog = { 0.05, 0.055, 0.06 }, fogFrom = 16, fogSpan = 60, fogMax = 0.6 }

  -- ------- the camera

  local cam = { m = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }, F = 200, CX = 128, CY = 96 }
  local eye = { Sc.EYE[1], Sc.EYE[2], Sc.EYE[3] }
  Sc.cam, Sc.eye = cam, eye

  local function lookAt(c, ex, ey, ez, tx, ty, tz)
    local zx, zy, zz = ex - tx, ey - ty, ez - tz
    local l = sqrt(zx * zx + zy * zy + zz * zz)
    zx, zy, zz = zx / l, zy / l, zz / l
    local xx, xy, xz = zz, 0, -zx
    l = sqrt(xx * xx + xz * xz)
    xx, xz = xx / l, xz / l
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
    local m = c.m
    m[1], m[2], m[3], m[4] = xx, xy, xz, -(xx * ex + xy * ey + xz * ez)
    m[5], m[6], m[7], m[8] = yx, yy, yz, -(yx * ex + yy * ey + yz * ez)
    m[9], m[10], m[11], m[12] = zx, zy, zz, -(zx * ex + zy * ey + zz * ez)
  end

  local function project(X, Y, Z)
    local m = cam.m
    local vx = m[1] * X + m[2] * Y + m[3] * Z + m[4]
    local vy = m[5] * X + m[6] * Y + m[7] * Z + m[8]
    local d = -(m[9] * X + m[10] * Y + m[11] * Z + m[12])
    if d < 1e-3 then return nil, nil, d end
    return cam.CX + vx * cam.F / d, cam.CY - vy * cam.F / d, d
  end
  Sc.project = project

  local function viewMatrix(out)
    local m = cam.m
    for i = 1, 12 do out[i] = m[i] end
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
  end
  local function projectionMatrix(out, ex, ey, ew, eh)
    local n, f = Sc.NEAR, Sc.FAR
    local l, r = (ex - cam.CX) / cam.F * n, (ex + ew - cam.CX) / cam.F * n
    local t, b = (cam.CY - ey) / cam.F * n, (cam.CY - (ey + eh)) / cam.F * n
    out[1], out[2], out[3], out[4] = 2 * n / (r - l), 0, (r + l) / (r - l), 0
    out[5], out[6], out[7], out[8] = 0, 2 * n / (t - b), (t + b) / (t - b), 0
    out[9], out[10], out[11], out[12] = 0, 0, -(f + n) / (f - n), -2 * f * n / (f - n)
    out[13], out[14], out[15], out[16] = 0, 0, -1, 0
    return out
  end

  -- shots: the camera eases from wherever it is to a pose (eye, look-at, vertical field of view)
  -- over a time, smoothly, then holds there; a slow sway rides on top, and a shake when asked
  --   field   the battle's view: low behind the party, looking up at the boss
  --   close   the party up close (the raid's first shot)
  --   reveal  pulled back and down to the ground, looking up the whole height of the boss
  --   boss    in under the boss (an announcement, its Max / G-Max move)
  --   wide    back and up (a shield going up or breaking)
  --   member  over a member's shoulder toward the boss (Sc.memberShot(i))
  Sc.SHOTS = {
    field = { eye = { 0, 1.15, 6.6 }, look = { 0, 4.2, -9 }, fov = 54 },
    close = { eye = { 0, 1.7, 3.2 }, look = { 0, 0.45, -1.4 }, fov = 46 },
    reveal = { eye = { 0, 1.0, 9.0 }, look = { 0, 4.6, -10 }, fov = 58 },
    boss = { eye = { 0, 1.5, 2.0 }, look = { 0, 6.4, -10 }, fov = 52 },
    wide = { eye = { 0, 2.4, 10.5 }, look = { 0, 3.8, -9 }, fov = 58 },
  }
  local memberPose = { eye = { 0, 0, 0 }, look = { 0, 0, 0 }, fov = 50 }
  function Sc.memberShot(i)
    local m = Sc.MEMBERS[i] or Sc.MEMBERS[1]
    local P = Sc.PAD
    -- behind it and a little to the side away from the middle, low; it fills the near corner and
    -- the boss towers past it
    local side = m.x <= 0 and 1 or -1
    memberPose.eye[1], memberPose.eye[2], memberPose.eye[3] = m.x + side * 1.5, 1.25, m.z + 3.9
    memberPose.look[1], memberPose.look[2], memberPose.look[3] = P.x - side * 0.7, 3.3, P.z
    memberPose.fov = 58
    return memberPose
  end

  local clock = 0
  function Sc.setTime(t) clock = t or 0 end

  local function copyPose(dst, src)
    dst.eye[1], dst.eye[2], dst.eye[3] = src.eye[1], src.eye[2], src.eye[3]
    dst.look[1], dst.look[2], dst.look[3] = src.look[1], src.look[2], src.look[3]
    dst.fov = src.fov
  end
  local cur = { eye = { 0, 0, 0 }, look = { 0, 0, 0 }, fov = 50 }
  local from = { eye = { 0, 0, 0 }, look = { 0, 0, 0 }, fov = 50 }
  local to = { eye = { 0, 0, 0 }, look = { 0, 0, 0 }, fov = 50 }
  local move = { t0 = 0, dur = 0, name = "field" }
  copyPose(cur, Sc.SHOTS.field)
  copyPose(from, Sc.SHOTS.field)
  copyPose(to, Sc.SHOTS.field)

  -- the camera to a shot (a name, "member" with i, or a pose) over dur seconds (0: a cut)
  function Sc.shot(name, dur, i)
    local pose = name == "member" and Sc.memberShot(i) or (type(name) == "table" and name) or Sc.SHOTS[name]
    if not pose then return false end
    copyPose(from, cur)
    copyPose(to, pose)
    move.t0, move.dur, move.name, move.i = clock, dur or 0, type(name) == "string" and name or "pose", i
    return true
  end
  function Sc.shotName() return move.name, move.i end
  function Sc.shotDone() return move.dur <= 0 or clock - move.t0 >= move.dur end

  local shake = { amp = 0, t0 = 0, dur = 0 }
  function Sc.shake(amp, dur) shake.amp, shake.t0, shake.dur = amp or 0.15, clock, dur or 0.6 end

  local rect = { 0, 0, 256, 192 }
  local function place()
    local u = move.dur > 0 and min(1, max(0, (clock - move.t0) / move.dur)) or 1
    local k = u * u * u * (u * (u * 6 - 15) + 10)
    for j = 1, 3 do
      cur.eye[j] = from.eye[j] + (to.eye[j] - from.eye[j]) * k
      cur.look[j] = from.look[j] + (to.look[j] - from.look[j]) * k
    end
    cur.fov = from.fov + (to.fov - from.fov) * k
    -- the sway: a slow drift side to side and a breath up and down
    local sx, sy = 0.12 * sin(clock * 0.21), 0.05 * sin(clock * 0.33)
    -- the shake: a quick jitter dying away
    local hx, hy = 0, 0
    local st = clock - shake.t0
    if shake.amp > 0 and st < shake.dur then
      local a = shake.amp * (1 - st / shake.dur)
      hx, hy = a * sin(st * 71), a * sin(st * 53 + 1.3)
    end
    local ex, ey, ez = cur.eye[1] + sx + hx, cur.eye[2] + sy + hy, cur.eye[3]
    eye[1], eye[2], eye[3] = ex, ey, ez
    lookAt(cam, ex, ey, ez, cur.look[1] + sx * 0.3 + hx, cur.look[2] + hy, cur.look[3])
    -- a 3:2 view fitted to the rect: by its height on a wider rect, by its width on a taller one
    local ew, eh = rect[3], rect[4]
    local tv = tan(rad(cur.fov) / 2)
    if ew / eh > Sc.ASPECT then cam.F = (eh / 2) / tv else cam.F = (ew / 2) / (tv * Sc.ASPECT) end
    cam.CX, cam.CY = rect[1] + ew / 2, rect[2] + eh / 2
  end
  Sc.place = place
  function Sc.setRect(ex, ey, ew, eh) rect[1], rect[2], rect[3], rect[4] = ex, ey, ew, eh end

  -- ------- light

  local function hash(i, k) return (sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end
  local function hash3(x, y, z) return (sin(x * 31.7 + y * 17.3 + z * 7.1) * 43758.5453) % 1 end
  -- smooth value noise over x, z (a lumpy rock)
  local function noise(x, z)
    local xi, zi = floor(x), floor(z)
    local fx, fz = x - xi, z - zi
    fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
    local a, b = hash3(xi, 0, zi), hash3(xi + 1, 0, zi)
    local c, d = hash3(xi, 0, zi + 1), hash3(xi + 1, 0, zi + 1)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz
  end
  Sc.noise = noise

  -- a vertex's colour: the surface's own (r, g, b) under the den's light, with normal n
  local function lit(x, y, z, nx, ny, nz, r, g, b)
    local L = Sc.LIGHT
    local kx, ky, kz = L.key[1] - x, L.key[2] - y, L.key[3] - z
    local kl = sqrt(kx * kx + ky * ky + kz * kz)
    local key = max(0, (nx * kx + ny * ky + nz * kz) / kl) * 1.15 / (1 + kl * kl / 900)
    local P = Sc.PAD
    local px, py, pz = x - P.x, (y - 0.6) * 1.4, z - P.z
    local pad = 1.3 / (1 + (px * px + py * py + pz * pz) / (L.padReach * L.padReach)) ^ 1.4
    local grime = 0.7 + 0.42 * hash3(x, y, z)
    local cr = (L.amb[1] + L.keyRGB[1] * key + L.pad[1] * pad) * grime * r
    local cg = (L.amb[2] + L.keyRGB[2] * key + L.pad[2] * pad) * grime * g
    local cb = (L.amb[3] + L.keyRGB[3] * key + L.pad[3] * pad) * grime * b
    -- fog: the far rock fades into the dark
    local dx, dy, dz = x - Sc.EYE[1], y - Sc.EYE[2], z - Sc.EYE[3]
    local f = min(L.fogMax, max(0, (sqrt(dx * dx + dy * dy + dz * dz) - L.fogFrom) / L.fogSpan))
    cr = cr + (L.fog[1] - cr) * f
    cg = cg + (L.fog[2] - cg) * f
    cb = cb + (L.fog[3] - cb) * f
    return min(1, cr), min(1, cg), min(1, cb)
  end
  Sc.lit = lit

  -- ------- pictures, drawn once into canvases (in the update step) and read back

  local function picture(w, h, draw)
    local G = love.graphics
    local c = G.newCanvas(w, h, { dpiscale = 1 })
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.clear(0, 0, 0, 0)
    draw(G, w, h)
    G.pop()
    local img = G.newImage(c:newImageData())
    c:release()
    img:setFilter("linear", "linear")
    img:setWrap("repeat", "repeat")
    return img
  end

  -- rock: mottled grey-brown, darker blotches, light grit, a few cracks (tiles both ways)
  local function rock(base, seed)
    return picture(128, 128, function(G, w, h)
      G.setColor(base[1], base[2], base[3], 1)
      G.rectangle("fill", 0, 0, w, h)
      for i = 1, 60 do
        local t = hash(i + seed, 1)
        G.setColor(t * 0.18, t * 0.17, t * 0.15, 0.25)
        local x, y, rr = w * hash(i + seed, 2), h * hash(i + seed, 3), 5 + 18 * hash(i + seed, 4)
        for ddx = -1, 1 do for ddy = -1, 1 do G.circle("fill", x + ddx * w, y + ddy * h, rr, 18) end end
      end
      for i = 1, 700 do
        local t = hash(i + seed, 5)
        G.setColor(0.5 + 0.4 * t, 0.48 + 0.38 * t, 0.44 + 0.34 * t, 0.22)
        G.rectangle("fill", w * hash(i + seed, 6), h * hash(i + seed, 7), 1.2, 1.2)
      end
      G.setColor(0.04, 0.04, 0.04, 0.55)
      G.setLineWidth(1)
      for i = 1, 6 do
        local x, y = w * hash(i + seed, 8), h * hash(i + seed, 9)
        local pts = { x, y }
        for k = 1, 5 do
          x = x + 6 + 10 * hash(i * 9 + k + seed, 10)
          y = y + (hash(i * 9 + k + seed, 11) - 0.5) * 14
          pts[#pts + 1], pts[#pts + 2] = x, y
        end
        G.line(pts)
      end
    end)
  end

  -- the pad's metal: brushed bands
  local function metal()
    return picture(64, 64, function(G, w, h)
      G.setColor(0.62, 0.62, 0.64, 1)
      G.rectangle("fill", 0, 0, w, h)
      for i = 0, h - 1, 2 do
        G.setColor(1, 1, 1, 0.04 + 0.06 * hash(i, 12))
        G.rectangle("fill", 0, i, w, 1)
      end
    end)
  end

  local function white()
    return picture(4, 4, function(G, w, h) G.setColor(1, 1, 1, 1); G.rectangle("fill", 0, 0, w, h) end)
  end

  -- ------- geometry (g3d's triangles: x, y, z, u, v, nx, ny, nz, r, g, b, a)

  local function vtx(x, y, z, u, v, r, g, b, a) return { x, y, z, u, v, 0, 1, 0, r, g, b, a or 1 } end
  local function lv(x, y, z, u, v, nx, ny, nz, r, g, b, a)
    local cr, cg, cb = lit(x, y, z, nx, ny, nz, r, g, b)
    return vtx(x, y, z, u, v, cr, cg, cb, a)
  end
  local function tri(out, a, b, c) out[#out + 1] = a; out[#out + 1] = b; out[#out + 1] = c end
  local function quad(out, a, b, c, d) tri(out, a, b, c); tri(out, a, c, d) end

  -- the plateau's rim at angle a: an irregular, squarish outline (its front nearly straight)
  local function rimAt(a)
    local P = Sc.PLAT
    local c, s = cos(a), sin(a)
    -- a superellipse (squarer than an ellipse), roughened
    local e = 0.55
    local x = P.rx * (abs(c) ^ e) * (c < 0 and -1 or 1)
    local z = P.rz * (abs(s) ^ e) * (s < 0 and -1 or 1)
    local j = 0.88 + 0.2 * noise(a * 3.1, 7.3) + 0.06 * sin(a * 11)
    return P.cx + x * j, P.cz + z * j
  end

  local scene = nil
  local R = nil
  local function renderer()
    if R then return R end
    R = deps.Render3d(mod, { name = "the raid den", camera = { view = viewMatrix, projection = projectionMatrix } })
    return R
  end
  function Sc.available()
    if Sc.failed then return false, Sc.why end
    if not deps.Render3d then return false, "no renderer" end
    local ok, why = renderer().available()
    if not ok then Sc.why = why end
    return ok, why
  end
  function Sc.resetScene() scene = nil end

  local ROCK = { 0.82, 0.76, 0.68 }       -- the plateau's top, dusty
  local WALL = { 0.6, 0.62, 0.62 }        -- the cave, cooler

  local function build()
    local lib = renderer().g3d()
    local pieces = {}
    local function add(verts, img, pass, name)
      if #verts >= 3 then pieces[#pieces + 1] = { model = lib.newModel(verts, img), pass = pass, name = name } end
    end
    local plain = white()
    local P, PD, C = Sc.PLAT, Sc.PAD, Sc.CAVE
    local N = 40

    -- the cave floor below the plateau, far and dim
    do
      local v = {}
      local y = P.foot
      for z = -40, 14, 3 do
        for x = -42, 42, 3 do
          local function V(xx, zz)
            local yy = y + 0.4 * noise(xx * 0.3, zz * 0.3)
            return lv(xx, yy, zz, xx / 4, zz / 4, 0, 1, 0, ROCK[1] * 0.7, ROCK[2] * 0.7, ROCK[3] * 0.7)
          end
          quad(v, V(x, z + 3), V(x + 3, z + 3), V(x + 3, z), V(x, z))
        end
      end
      add(v, rock({ 0.45, 0.42, 0.38 }, 30), 2, "floor")
    end

    -- the plateau's top: rings from its middle out to the rim, gently bumpy away from the pad
    do
      local v = {}
      local RINGS = 6
      local function topY(x, z)
        local dpx, dpz = x - PD.x, z - PD.z
        local nearPad = min(1, sqrt(dpx * dpx + dpz * dpz) / (PD.r + 1.2))
        return 0.06 * (noise(x * 0.9, z * 0.9) - 0.5) * nearPad
      end
      local function at(ring, i)
        local a = 2 * pi * i / N
        local rx, rz = rimAt(a)
        local k = ring / RINGS
        local x, z = P.cx + (rx - P.cx) * k, P.cz + (rz - P.cz) * k
        return x, topY(x, z), z
      end
      for ring = 0, RINGS - 1 do
        for i = 0, N - 1 do
          local x1, y1, z1 = at(ring, i)
          local x2, y2, z2 = at(ring, i + 1)
          local x3, y3, z3 = at(ring + 1, i + 1)
          local x4, y4, z4 = at(ring + 1, i)
          local function V(x, y, z) return lv(x, y, z, x / 3, z / 3, 0, 1, 0, ROCK[1], ROCK[2], ROCK[3]) end
          if ring == 0 then tri(v, V(x1, y1, z1), V(x4, y4, z4), V(x3, y3, z3))
          else quad(v, V(x1, y1, z1), V(x4, y4, z4), V(x3, y3, z3), V(x2, y2, z2)) end
        end
      end
      add(v, rock({ 0.5, 0.46, 0.4 }, 0), 2, "plateau")
    end

    -- the cliff: from the rim down to the floor, bulging and ragged
    do
      local v = {}
      local ROWS = 4
      local function at(i, row)
        local a = 2 * pi * i / N
        local rx, rz = rimAt(a)
        local k = row / ROWS
        local y = P.foot * k
        local bulge = (0.35 * sin(k * pi) + 0.25 * k) * (0.6 + 0.8 * noise(a * 5, row * 1.7))
        local ox, oz = rx - P.cx, rz - P.cz
        local l = sqrt(ox * ox + oz * oz)
        return rx + ox / l * bulge, y, rz + oz / l * bulge, ox / l, oz / l
      end
      for i = 0, N - 1 do
        for row = 0, ROWS - 1 do
          local function V(ii, rr)
            local x, y, z, nx, nz = at(ii, rr)
            return lv(x, y, z, (ii / N) * 24, -y / 2.5, nx, 0.15, nz, WALL[1] * 0.9, WALL[2] * 0.88, WALL[3] * 0.85)
          end
          quad(v, V(i, row), V(i + 1, row), V(i + 1, row + 1), V(i, row + 1))
        end
      end
      add(v, rock({ 0.4, 0.38, 0.35 }, 60), 2, "cliff")
    end

    -- the cave walls: a broken ring round the back and sides, lumpy, with a ceiling closing over
    -- the far half and a dark tunnel mouth at the back right
    do
      local v = {}
      local A0, A1, SEG, ROWS = rad(150), rad(390), 56, 12
      local function mouth(a, y)
        -- the tunnel: a dark, rounded hole at about 300 degrees
        local da = (a - rad(303)) / rad(12)
        local dy = (y - (C.y0 + 4.5)) / 4.5
        return da * da + dy * dy < 1
      end
      local function at(i, row)
        local a = A0 + (A1 - A0) * i / SEG
        local k = row / ROWS
        local y = C.y0 + (C.y1 - C.y0) * k
        local r = C.r * (0.9 + 0.22 * noise(a * 4, k * 3)) - k * k * 6
        return C.cx + r * cos(a), y, C.cz + r * sin(a), -cos(a), -sin(a), a
      end
      for i = 0, SEG - 1 do
        for row = 0, ROWS - 1 do
          local function V(ii, rr)
            local x, y, z, nx, nz, a = at(ii, rr)
            local k = mouth(a, y) and 0.08 or 1
            return lv(x, y, z, ii / SEG * 18, -y / 3, nx, 0.2, nz, WALL[1] * k, WALL[2] * k, WALL[3] * k)
          end
          quad(v, V(i, row), V(i, row + 1), V(i + 1, row + 1), V(i + 1, row))
        end
      end
      -- the ceiling: from the walls' top inward and up, dark
      local cy = C.y1
      for i = 0, SEG - 1 do
        local function T(ii, k)
          local a = A0 + (A1 - A0) * ii / SEG
          local r = (C.r - 6) * (1 - k * 0.85)
          local x, z = C.cx + r * cos(a), C.cz + r * sin(a)
          return lv(x, cy + k * 5, z, ii / SEG * 18, k * 4, 0, -1, 0, 0.3, 0.3, 0.32)
        end
        quad(v, T(i, 0), T(i, 1), T(i + 1, 1), T(i + 1, 0))
      end
      add(v, rock({ 0.42, 0.42, 0.42 }, 90), 2, "walls")
    end

    -- stalagmites (up from the floor and the plateau) and stalactites (down from the ceiling),
    -- and a few boulders on the plateau
    do
      local v = {}
      local function cone(x, y, z, r, h, down)
        local n = 7
        local tip = down and (y - h) or (y + h)
        for i = 0, n - 1 do
          local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
          local j0, j1 = 0.8 + 0.4 * hash(i + x * 3, z), 0.8 + 0.4 * hash(i + 1 + x * 3, z)
          local x0, z0 = x + r * j0 * cos(a0), z + r * j0 * sin(a0)
          local x1, z1 = x + r * j1 * cos(a1), z + r * j1 * sin(a1)
          local am = (a0 + a1) / 2
          local nx, nz = cos(am), sin(am)
          tri(v, lv(x0, y, z0, 0, 1, nx, 0.3, nz, WALL[1], WALL[2], WALL[3]),
            lv(x1, y, z1, 1, 1, nx, 0.3, nz, WALL[1], WALL[2], WALL[3]),
            lv(x + 0.06 * r, tip, z, 0.5, 0, nx, 0.6, nz, WALL[1], WALL[2], WALL[3]))
        end
      end
      local f = P.foot
      for _, s in ipairs({ { -9.5, f, -11, 0.9, 5.2 }, { -7.2, f, -15, 1.1, 7 }, { -12.5, f, -5, 0.8, 4.6 },
        { -14, f, -12, 1.2, 6.2 }, { 10.5, f, -12.5, 0.9, 4.8 }, { 13, f, -6, 0.7, 3.4 }, { 8.6, f, -16, 1.3, 7.6 },
        { 11.5, f, -1, 0.6, 2.8 }, { -11, f, 1, 0.6, 2.6 }, { 6.9, 0, -9.8, 0.35, 1.5 }, { -6.6, 0, -9.2, 0.3, 1.1 },
        { 7.6, 0, -7.6, 0.22, 0.8 }, { -2.5, f, -18, 1.4, 9 }, { 3.5, f, -19, 1.2, 8 } }) do
        cone(s[1], s[2], s[3], s[4], s[5])
      end
      for _, s in ipairs({ { -6, 15, -14, 0.9, 4 }, { 4, 15, -16, 1.1, 5 }, { 9, 14.5, -9, 0.7, 3 },
        { -10, 14.5, -6, 0.8, 3.5 }, { 0.5, 16, -19, 1.3, 6 } }) do
        cone(s[1], s[2], s[3], s[4], s[5], true)
      end
      -- boulders: lumpy eight-sided rocks
      local function boulder(x, z, r)
        local y = 0
        local pts = {}
        for i = 0, 7 do
          local a = 2 * pi * i / 8
          local rr = r * (0.8 + 0.4 * hash(i + x, z))
          pts[i] = { x + rr * cos(a), y, z + rr * sin(a) * 0.8 }
        end
        local top = { x, y + r * 1.1, z }
        for i = 0, 7 do
          local a, b = pts[i], pts[(i + 1) % 8]
          local am = 2 * pi * (i + 0.5) / 8
          tri(v, lv(a[1], a[2], a[3], 0, 1, cos(am), 0.5, sin(am), WALL[1], WALL[2], WALL[3]),
            lv(b[1], b[2], b[3], 1, 1, cos(am), 0.5, sin(am), WALL[1], WALL[2], WALL[3]),
            lv(top[1], top[2], top[3], 0.5, 0, cos(am), 0.9, sin(am), WALL[1], WALL[2], WALL[3]))
        end
      end
      boulder(-7.0, 0.8, 0.8)
      boulder(6.6, -1.6, 0.55)
      boulder(-5.6, -8.6, 0.45)
      add(v, rock({ 0.44, 0.43, 0.42 }, 120), 2, "rocks")
    end

    -- the pad: a metal disc on a short drum, a glowing ring inset in its top, lights round its rim
    do
      local v = {}
      local n, r, h = 36, PD.r, PD.h
      for i = 0, n - 1 do
        local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
        local c0, s0, c1, s1 = cos(a0), sin(a0), cos(a1), sin(a1)
        local function M(x, y, z, u, vv, nx, ny, nz, k)
          return lv(x, y, z, u, vv, nx, ny, nz, 0.78 * k, 0.78 * k, 0.8 * k)
        end
        -- the top
        tri(v, M(PD.x, h, PD.z, 0.5, 0.5, 0, 1, 0, 1), M(PD.x + r * c1, h, PD.z + r * s1, 1, 1, 0, 1, 0, 1),
          M(PD.x + r * c0, h, PD.z + r * s0, 0, 1, 0, 1, 0, 1))
        -- the side
        quad(v, M(PD.x + r * c0, h, PD.z + r * s0, 0, 0, c0, 0, s0, 0.8), M(PD.x + r * c1, h, PD.z + r * s1, 1, 0, c1, 0, s1, 0.8),
          M(PD.x + r * c1, 0, PD.z + r * s1, 1, 1, c1, 0, s1, 0.5), M(PD.x + r * c0, 0, PD.z + r * s0, 0, 1, c0, 0, s0, 0.5))
      end
      add(v, metal(), 2, "pad")
      -- the glowing parts: the inset ring and the rim lights (lit by themselves)
      local g = {}
      local r0, r1, y = r * 0.8, r * 0.88, h + 0.004
      for i = 0, n - 1 do
        local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
        quad(g, vtx(PD.x + r0 * cos(a0), y, PD.z + r0 * sin(a0), 0, 0, 1, 0.78, 0.55),
          vtx(PD.x + r0 * cos(a1), y, PD.z + r0 * sin(a1), 1, 0, 1, 0.78, 0.55),
          vtx(PD.x + r1 * cos(a1), y, PD.z + r1 * sin(a1), 1, 1, 1, 0.9, 0.75),
          vtx(PD.x + r1 * cos(a0), y, PD.z + r1 * sin(a0), 0, 1, 1, 0.9, 0.75))
      end
      for i = 0, 11 do
        local a = 2 * pi * (i + 0.5) / 12
        local c, s = cos(a), sin(a)
        local tx, tz = -s * 0.16, c * 0.16
        local x, z = PD.x + (r + 0.006) * c, PD.z + (r + 0.006) * s
        quad(g, vtx(x - tx, h * 0.35, z - tz, 0, 0, 1, 0.85, 0.6), vtx(x + tx, h * 0.35, z + tz, 1, 0, 1, 0.85, 0.6),
          vtx(x + tx, h * 0.7, z + tz, 1, 1, 1, 0.95, 0.8), vtx(x - tx, h * 0.7, z - tz, 0, 1, 1, 0.95, 0.8))
      end
      add(g, plain, 2, "pad light")
    end

    return { clear = Sc.CLEAR, pieces = pieces }
  end

  function Sc.scene()
    if scene or Sc.failed then return scene end
    local ok, s = pcall(build)
    if ok and s then scene = s else
      Sc.failed, Sc.why = true, "the den did not build (" .. tostring(s) .. ")"
      if mod.log then mod.log:warn("Max Raids: %s; drawn flat", Sc.why) end
    end
    return scene
  end

  -- ------- update

  local function setup(tg)
    Sc.setRect(tg.ex, tg.ey, tg.ew, tg.eh)
    place()
  end
  function Sc.prepare(t)
    if t then clock = t end
    if not Sc.available() then return false end
    local sc = Sc.scene()
    if not sc then return false end
    return renderer().prepare(sc, setup)
  end

  -- ------- the 2D over the picture

  local G = love and love.graphics

  -- a soft disc of added light (a fan mesh)
  local glowMesh = nil
  local function glow(G2, x, y, rx, ry, cr, cg, cb, a)
    if not glowMesh then
      local vv = { { 0, 0, 0.5, 0.5, 1, 1, 1, 1 } }
      for i = 0, 24 do
        local t = 2 * pi * i / 24
        vv[#vv + 1] = { cos(t), sin(t), 0, 0, 1, 1, 1, 0 }
      end
      glowMesh = G2.newMesh(vv, "fan", "static")
    end
    G2.setBlendMode("add")
    G2.setColor(cr, cg, cb, a)
    G2.draw(glowMesh, x, y, 0, rx, ry)
    G2.setBlendMode("alpha")
  end

  -- the light shaft: a wedge of added light from the upper left down onto the plateau
  local shaftMesh = nil
  local function shaft(G2, ex, ey, ew, eh)
    local x0, y0 = project(-11, 16, -13)
    local x1, y1 = project(-4.2, 0, -6)
    if not (x0 and x1) then return end
    if not shaftMesh then
      shaftMesh = G2.newMesh({ { 0, 0, 0, 0, 0.75, 0.9, 0.85, 0.16 }, { 0, 0, 0, 0, 0.75, 0.9, 0.85, 0.16 },
        { 0, 0, 0, 0, 0.75, 0.9, 0.85, 0 }, { 0, 0, 0, 0, 0.75, 0.9, 0.85, 0 } }, "fan", "stream")
    end
    local w0, w1 = eh * 0.06, eh * 0.26
    shaftMesh:setVertex(1, x0 - w0, y0, 0, 0, 0.75, 0.9, 0.85, 0.2)
    shaftMesh:setVertex(2, x0 + w0, y0, 0, 0, 0.75, 0.9, 0.85, 0.2)
    shaftMesh:setVertex(3, x1 + w1, y1, 0, 0, 0.75, 0.9, 0.85, 0)
    shaftMesh:setVertex(4, x1 - w1, y1, 0, 0, 0.75, 0.9, 0.85, 0)
    G2.setBlendMode("add")
    G2.setColor(1, 1, 1, 1)
    G2.draw(shaftMesh)
    G2.setBlendMode("alpha")
  end

  -- the motes: MOTES specks drifting up through the cave, twinkling, thickest in the shaft;
  -- one static mesh moved by a vertex shader (no Lua a speck), plain circles without it
  Sc.MOTES = 60
  local MOTE_SHADER = [[
varying mediump float vA;
varying mediump vec2 vC;
#ifdef VERTEX
attribute highp vec4 MoteA;   // x seed, y seed, speed, size
attribute highp vec4 MoteB;   // corner x (-1 / 1), corner y (-1 / 1), twinkle phase, warm (0 / 1)
uniform highp vec4 rect;      // ex, ey, ew, eh
uniform highp float moteT;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  highp float yy = 1.0 - fract(MoteA.y + moteT * MoteA.z);
  // the cloud leans to the left, where the shaft falls
  highp float xx = fract(MoteA.x + 0.02 * sin(moteT * 0.7 + MoteB.z * 6.0));
  xx = xx * xx * 0.85 + 0.03;
  highp vec2 p = vec2(rect.x + xx * rect.z, rect.y + yy * rect.w * 0.85);
  highp float s = MoteA.w * rect.w / 160.0;
  p += vec2(MoteB.x, MoteB.y) * s;
  vC = vec2(MoteB.x, MoteB.y);
  vA = (0.35 + 0.65 * (0.5 + 0.5 * sin(moteT * 2.3 + MoteB.z * 40.0))) * smoothstep(0.0, 0.15, yy) * smoothstep(1.0, 0.8, yy);
  return transform_projection * vec4(p, 0.0, 1.0);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  // a soft round glow, bright at its middle
  mediump float r = max(0.0, 1.0 - dot(vC, vC));
  return vec4(color.rgb, color.a * vA * r * r);
}
#endif
]]
  local moteMesh, moteShader, moteFailed = nil, nil, false
  local moteRect, sentRect = { 0, 0, 0, 0 }, {}
  local function motesBuild(G2)
    if moteFailed then return false end
    if moteMesh then return true end
    local ok = pcall(function()
      local v = {}
      for i = 1, Sc.MOTES do
        local a = { hash(i, 31), hash(i, 32), 0.01 + 0.025 * hash(i, 33), 0.5 + 0.9 * hash(i, 34) }
        local warm = hash(i, 36) > 0.86 and 1 or 0
        for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, -1 }, { 1, 1 }, { -1, 1 } }) do
          local r, g, b = 0.8, 1, 0.92
          if warm == 1 then r, g, b = 1, 0.75, 0.4 end
          v[#v + 1] = { a[1], a[2], a[3], a[4], c[1], c[2], hash(i, 35), warm, r, g, b, 1 }
        end
      end
      moteMesh = G2.newMesh({ { "MoteA", "float", 4 }, { "MoteB", "float", 4 }, { "VertexColor", "float", 4 } },
        v, "triangles", "static")
      moteShader = G2.newShader(MOTE_SHADER)
    end)
    if not ok then moteFailed, moteMesh, moteShader = true, nil, nil end
    return ok
  end
  local function changed(cur, sent)
    local d = false
    for i = 1, #cur do if sent[i] ~= cur[i] then sent[i], d = cur[i], true end end
    return d
  end
  local function motesDraw(G2)
    if changed(moteRect, sentRect) then moteShader:send("rect", moteRect) end
    moteShader:send("moteT", clock % 1000)
    G2.setShader(moteShader)
    G2.setBlendMode("add")
    G2.setColor(1, 1, 1, 1)
    G2.draw(moteMesh)
    G2.setBlendMode("alpha")
    G2.setShader()
  end
  local function motes(G2, ex, ey, ew, eh)
    moteRect[1], moteRect[2], moteRect[3], moteRect[4] = ex, ey, ew, eh
    if motesBuild(G2) and pcall(motesDraw, G2) then return end
    G2.setShader()
    G2.setBlendMode("alpha")
    for i = 1, 30 do
      local yy = 1 - (hash(i, 32) + clock * 0.02) % 1
      G2.setColor(0.8, 1, 0.9, 0.5)
      G2.circle("fill", ex + hash(i, 31) ^ 2 * ew * 0.85, ey + yy * eh * 0.85, 0.6, 6)
    end
  end

  -- a sprite in one flat colour (its outline passes): alpha kept, colour replaced
  local SIL = [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(color.rgb, color.a * step(0.5, Texel(tex, tc).a));
}
]]
  local silShader, silFailed = nil, false
  local function sil()
    if silShader or silFailed then return silShader end
    local ok, s = pcall(G.newShader, SIL)
    if ok then silShader = s else silFailed = true end
    return silShader
  end

  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return G.draw(...)
  end

  -- the boss on its pad: pic = { image, quad, cell, box = { x0, y0, x1, y1 } (in the cell) },
  -- size = its height against a member's
  local OUT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }
  function Sc.bossAt(size, boxH)
    local PD = Sc.PAD
    local x, y, d = project(PD.x, PD.h, PD.z)
    if not x then return nil end
    local hpx = Sc.MEMBER_H * (size or 3.5) * cam.F / d
    return x, y, hpx
  end
  local function drawBoss(G2, pic, size, t)
    if not (pic and pic.image) then return end
    local box = pic.box
    local bw, bh = box[3] - box[1], box[4] - box[2]
    local x, y, hpx = Sc.bossAt(size, bh)
    if not x then return end
    local k = hpx / bh
    local ox, oy = (box[1] + box[3]) / 2, box[4]
    -- its shadow and the pad's glow under it
    G2.setColor(0, 0, 0, 0.45)
    G2.ellipse("fill", x, y, bw * k * 0.42, bw * k * 0.09, 32)
    glow(G2, x, y, bw * k * 0.6, bw * k * 0.14, 1, 0.6, 0.35, 0.35)
    -- the red aura: a wide dark-red glow pass, then the bright outline, then the sprite
    local s = sil()
    if s then
      G2.setShader(s)
      local o1 = max(1.5, k * 2.2)
      local pulse = 0.7 + 0.3 * sin(t * 4)
      G2.setColor(0.45, 0.0, 0.02, 0.45 * pulse)
      for _, dd in ipairs(OUT) do G2.draw(pic.image, pic.quad, x + dd[1] * o1 * 1.8, y + dd[2] * o1 * 1.8, 0, k, k, ox, oy) end
      G2.setColor(1, 0.12, 0.12, 0.95)
      for _, dd in ipairs(OUT) do G2.draw(pic.image, pic.quad, x + dd[1] * o1 * 0.6, y + dd[2] * o1 * 0.6, 0, k, k, ox, oy) end
      G2.setShader()
    end
    G2.setColor(1, 1, 1, 1)
    drawPixel(pic.image, pic.quad, x, y, 0, k, k, ox, oy)
    -- red wisps curling over its head
    local hx, hy = x, y - bh * k
    for w = 1, 2 do
      local side = w == 1 and -1 or 1
      for i = 0, 6 do
        local u = i / 6
        local px = hx + side * bw * k * (0.12 + 0.1 * u) + sin(t * 1.6 + u * 4 + w) * bw * k * 0.05
        local py = hy - bh * k * (0.02 + 0.16 * u)
        local rr = bw * k * (0.06 - 0.03 * u) * (1 + 0.15 * sin(t * 3 + i))
        G2.setColor(0.55 + 0.25 * (1 - u), 0.02, 0.06, 0.75 * (1 - u * 0.6))
        G2.circle("fill", px, py, rr, 14)
      end
    end
    -- streaks swirling round its body (arcs on an ellipse, each with a fading tail)
    G2.setLineWidth(max(1, k * 1.2))
    local cx, cy = x, y - bh * k * 0.5
    local rx, ry = bw * k * 0.62, bh * k * 0.18
    for j = 0, 2 do
      local a0 = t * (1.4 + 0.3 * j) + j * 2.1
      for sgm = 0, 9 do
        local a1, a2 = a0 - sgm * 0.09, a0 - (sgm + 1) * 0.09
        local front = sin(a1) > 0
        G2.setColor(1, 0.1, 0.12, (1 - sgm / 10) * (front and 0.9 or 0.35))
        G2.line(cx + rx * cos(a1), cy + ry * sin(a1) + (j - 1) * bh * k * 0.18,
          cx + rx * cos(a2), cy + ry * sin(a2) + (j - 1) * bh * k * 0.18)
      end
    end
    -- sparks rising off it
    for i = 1, 22 do
      local u = (hash(i, 51) + t * (0.25 + 0.3 * hash(i, 52))) % 1
      local px = x + (hash(i, 53) - 0.5) * bw * k * 1.1
      local py = y - u * bh * k * 1.15
      G2.setColor(1, 0.25 + 0.3 * hash(i, 54), 0.1, (1 - u) * 0.9)
      G2.rectangle("fill", px, py, max(1, k * 1.2), max(1, k * 1.2))
    end
  end

  -- a member's feet on screen and its height in px
  function Sc.memberAt(i)
    local m = Sc.MEMBERS[i]
    if not m then return nil end
    local x, y, d = project(m.x, 0, m.z)
    if not x then return nil end
    return x, y, Sc.MEMBER_H * cam.F / d
  end
  local function drawMember(G2, i, pic, t)
    if not (pic and pic.image) then return end
    local x, y, hpx = Sc.memberAt(i)
    if not x then return end
    local box = pic.box
    local bw = box[3] - box[1]
    -- one scale for every member (a 64-px pic is MEMBER_PIC_H tall), not each fitted to a height
    local k = hpx * (Sc.MEMBER_PIC_H / Sc.MEMBER_H) / (pic.cell or 64)
    G2.setColor(0, 0, 0, 0.5)
    G2.ellipse("fill", x, y, bw * k * 0.42, bw * k * 0.1, 24)
    -- a slow breath
    local b = 1 + 0.015 * sin(t * 2.4 + i * 1.3)
    G2.setColor(1, 1, 1, 1)
    if pic.quad then drawPixel(pic.image, pic.quad, x, y, 0, k, k * b, (box[1] + box[3]) / 2, box[4])
    else drawPixel(pic.image, x, y, 0, k, k * b, (box[1] + box[3]) / 2, box[4]) end
  end

  -- the roar: a white flash, streaks of energy bursting out of the boss's middle, a shockwave
  -- ring running over the ground from the pad, a red wash fading (Sc.burst at the clock's now)
  Sc.BURST_S = 1.6
  local burst = { t0 = nil }
  function Sc.burst() burst.t0 = clock end
  function Sc.bursting() return burst.t0 ~= nil and clock - burst.t0 < Sc.BURST_S end
  local function drawBurst(G2, ex, ey, ew, eh, bx, by, size)
    if not burst.t0 then return end
    local u = (clock - burst.t0) / Sc.BURST_S
    if u < 0 or u >= 1 then return end
    -- the ground's ring
    local P = Sc.PAD
    local rr = P.r * (1 + 9 * u)
    local cx, cy, d = project(P.x, 0.05, P.z)
    if cx then
      local rx = rr * cam.F / d
      G2.setLineWidth(max(1, eh * 0.012 * (1 - u)))
      G2.setColor(1, 0.35, 0.55, 0.85 * (1 - u))
      G2.ellipse("line", cx, cy, rx, rx * 0.22, 48)
    end
    -- the streaks: out from the boss's middle, long and fast, pink and red
    if bx then
      G2.setBlendMode("add")
      for i = 1, 42 do
        local a = 2 * pi * hash(i, 71) + 0.3 * sin(i)
        local sp = 0.5 + hash(i, 72)
        local r0 = size * (0.1 + 1.8 * u * sp)
        local r1 = r0 + size * (0.25 + 0.5 * hash(i, 73)) * (1 - u * 0.6)
        local hot = hash(i, 74) > 0.6
        G2.setColor(hot and 1 or 0.95, hot and 0.75 or 0.18, hot and 0.9 or 0.45, 0.9 * (1 - u))
        G2.setLineWidth(max(1, size * (0.012 + 0.02 * hash(i, 75)) * (1 - u)))
        G2.line(bx + cos(a) * r0, by + sin(a) * r0 * 0.8, bx + cos(a) * r1, by + sin(a) * r1 * 0.8)
      end
      glow(G2, bx, by, size * (0.6 + 1.6 * u), size * (0.5 + 1.2 * u), 1, 0.2, 0.45, 0.6 * (1 - u))
      G2.setBlendMode("alpha")
    end
    -- the red wash, and the flash at the start
    G2.setColor(0.6, 0.0, 0.15, 0.35 * (1 - u))
    G2.rectangle("fill", ex, ey, ew, eh)
    if u < 0.2 then
      G2.setColor(1, 1, 1, 0.85 * (1 - u / 0.2))
      G2.rectangle("fill", ex, ey, ew, eh)
    end
  end

  -- the edges darkened
  local vigMesh = nil
  local function vignette(G2, ex, ey, ew, eh)
    if not vigMesh then
      local v, rings = {}, { { 0.0, 0 }, { 0.6, 0 }, { 0.95, 0.4 }, { 1.4, 0.85 }, { 2.2, 0.85 } }
      local n = 24
      for r = 1, #rings - 1 do
        local a, b = rings[r], rings[r + 1]
        for i = 0, n - 1 do
          local t0, t1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
          local function P(ring, th) return { ring[1] * cos(th), ring[1] * sin(th), 0, 0, 0, 0, 0, ring[2] } end
          v[#v + 1] = P(a, t0); v[#v + 1] = P(b, t0); v[#v + 1] = P(b, t1)
          v[#v + 1] = P(a, t0); v[#v + 1] = P(b, t1); v[#v + 1] = P(a, t1)
        end
      end
      vigMesh = G2.newMesh(v, "triangles", "static")
    end
    G2.setColor(1, 1, 1, 1)
    G2.draw(vigMesh, ex + ew / 2, ey + eh / 2, 0, ew / 2 * 1.05, eh / 2 * 1.05)
  end

  -- the flat version (no 3D): the plateau's top and the pad as polygons under the same camera
  function Sc.drawFlat(G2, ex, ey, ew, eh)
    Sc.setRect(ex, ey, ew, eh)
    place()
    G2.setColor(Sc.CLEAR[1] * 2, Sc.CLEAR[2] * 2, Sc.CLEAR[3] * 2, 1)
    G2.rectangle("fill", ex, ey, ew, eh)
    local pts = {}
    for i = 0, 39 do
      local x, z = rimAt(2 * pi * i / 40)
      local sx, sy = project(x, 0, z)
      if sx then pts[#pts + 1], pts[#pts + 2] = sx, sy end
    end
    if #pts >= 6 then
      G2.setColor(0.36, 0.33, 0.29, 1)
      G2.polygon("fill", pts)
    end
    local PD = Sc.PAD
    local x, y, d = project(PD.x, PD.h, PD.z)
    if x then
      G2.setColor(0.5, 0.5, 0.52, 1)
      G2.ellipse("fill", x, y, PD.r * cam.F / d, PD.r * cam.F / d * 0.3, 32)
    end
  end

  -- the den over ex, ey, ew, eh at clock t: boss = { image, quad, box, size } (or nil),
  -- members = list of { image, quad, box } (nil skips a place)
  function Sc.draw(G2, ex, ey, ew, eh, t, boss, members)
    clock = t or clock
    local ok = false
    if Sc.available() and scene then ok = renderer().draw(G2, scene, ex, ey, ew, eh) end
    if not ok then Sc.drawFlat(G2, ex, ey, ew, eh) else
      Sc.setRect(ex, ey, ew, eh)
      place()
    end
    shaft(G2, ex, ey, ew, eh)
    if boss then drawBoss(G2, boss, boss.size, clock) end
    for i = 1, #Sc.MEMBERS do
      if members and members[i] then drawMember(G2, i, members[i], clock) end
    end
    motes(G2, ex, ey, ew, eh)
    if burst.t0 then
      local bx, by, hpx = Sc.bossAt(boss and boss.size)
      drawBurst(G2, ex, ey, ew, eh, bx, by and hpx and by - hpx * 0.5, hpx or eh * 0.5)
    end
    vignette(G2, ex, ey, ew, eh)
    G2.setColor(1, 1, 1, 1)
  end

  return Sc
end
