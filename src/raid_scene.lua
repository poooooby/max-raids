-- A Max Raid's den (src/raid.lua) on the top screen, Sword / Shield's battlefield: a barren plain of
-- rose-red dust under a night sky, crags and boulders round its sides and back, built here in 3D
-- (lit per vertex - a dim violet ambient, a cool key from above, the Dynamax energy's pink round the
-- boss's feet, a violet haze with distance) and drawn by src/render3d.lua with its sky left clear;
-- behind it, in 2D: the night sky (dark above, a violet haze at the horizon), stars, the aurora's
-- curtains (a shader: rays drifting, hues shifting through violet, magenta, blue and green, a
-- bright hem fading up), a mist along the horizon. Over it: the Dynamax portal (a vortex turning in
-- the sky above the boss's head, a shader on a projected disc), the pink energy pillars round its
-- feet, the boss (the pack's frames, a red outline, the three-part cloud over its head, streaks
-- swirling round it, sparks), then the party from behind with their shadows, specks of energy
-- drifting up. The camera sits behind and above the party looking up at the boss, with a slow sway;
-- Sc.shot eases it between poses (the intro's close-up, the reveal, over a member's shoulder, in on
-- the boss), Sc.shake jolts it, Sc.burst sets off the boss's roar.
--
-- Drawn by src/render3d.lua: Sc.prepare renders from the training layer's update (never inside the
-- engine's draw); Sc.draw places it. Without a 3D device the same camera paints a flat version.
--   Sc = raid_scene(mod, { Render3d })

return function(mod, deps)
  local Sc = { failed = false, why = nil }
  local sqrt, sin, cos, tan, rad, pi, floor = math.sqrt, math.sin, math.cos, math.tan, math.rad, math.pi, math.floor
  local min, max, abs = math.min, math.max, math.abs

  -- the battlefield, in metres (y up, the camera looking down -z)
  --   PAD       where the boss stands: middle, radius of its energy, height
  --   MEMBERS   the party's feet, left to right (a slight arc)
  Sc.PAD = { x = 0, z = -9.2, r = 3.4, h = 0.02 }
  -- the plain: its reach from the boss's feet; the crags in a ring between cragNear and cragFar
  -- (none in front), boulders between boulderNear and boulderFar, stones on the battle's ground
  Sc.ARENA = { r = 140, CRAGS = 38, cragNear = 21, cragFar = 48, BOULDERS = 52, boulderNear = 11, boulderFar = 30,
    STONES = 170 }
  Sc.MEMBERS = { { x = -3.1, z = -0.75 }, { x = -1.05, z = -1.25 }, { x = 1.05, z = -1.25 }, { x = 3.1, z = -0.75 } }
  -- the members drawn mirrored: right of the boss (a back pic faces up and to the right)
  Sc.MEMBER_FLIP = { [3] = true, [4] = true }
  Sc.MEMBER_H = 1.1          -- a member's height (the boss's size is against it)
  -- a member's sprite: one scale for all (a 64-px pic's height in metres), so each keeps its own
  -- size against the others
  Sc.MEMBER_PIC_H = 1.75
  Sc.EYE = { 0, 1.15, 6.6 }    -- the battle's eye (fog is measured from here)
  Sc.ASPECT = 1.5
  Sc.PORTRAIT_CY = 0.42
  Sc.NEAR, Sc.FAR = 0.05, 200
  -- (the 3D picture's sky left clear: the night sky is drawn behind it)
  Sc.CLEAR = { 0, 0, 0, 0 }
  -- the light: a dim violet ambient, a cool key from high in front (the aurora's), the Dynamax energy
  -- round the boss's feet, a violet haze with distance
  Sc.LIGHT = { amb = { 0.34, 0.22, 0.32 }, key = { 8, 40, 30 }, keyRGB = { 0.62, 0.55, 0.78 },
    pad = { 1.0, 0.3, 0.55 }, padReach = 7.5, fog = { 0.36, 0.13, 0.32 }, fogFrom = 18, fogSpan = 75, fogMax = 0.82 }

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
  --   member  a member's own turn (choosing, moving): the target shot on it (Sc.memberShot(i))
  --   target  the boss attacking one member: almost directly behind it, low, looking up at the boss
  --           (Sc.targetShot(i))
  --   spread  the boss attacking all four: every member and the boss at once, nearer than wide
  --   catch   the throw: past the party, low, on the boss's pad (the ball has the stage to itself)
  Sc.SHOTS = {
    field = { eye = { 0, 1.15, 6.6 }, look = { 0, 4.2, -9 }, fov = 54 },
    close = { eye = { 0, 1.7, 3.2 }, look = { 0, 0.45, -1.4 }, fov = 46 },
    reveal = { eye = { 0, 1.0, 9.0 }, look = { 0, 4.6, -10 }, fov = 58 },
    boss = { eye = { 0, 1.5, 2.0 }, look = { 0, 6.4, -10 }, fov = 52 },
    wide = { eye = { 0, 2.4, 10.5 }, look = { 0, 3.8, -9 }, fov = 58 },
    spread = { eye = { 0, 2.3, 8.2 }, look = { 0, 2.9, -8 }, fov = 62 },
    catch = { eye = { 0, 1.5, -2.4 }, look = { 0, 1.9, -9.2 }, fov = 58 },
  }
  -- almost directly behind the member, low, looking up past it at the boss: the member large in the
  -- foreground, the boss towering over it, the others mostly out past the sides
  -- TARGET while the boss attacks (the message band covers the screen's foot: aimed a little lower,
  -- so the member stands clear of it); CHOOSE for the member's own turn (no band: the boss whole)
  Sc.TARGET = { SIDE = 0.3, UP = 0.65, BACK = 3.6, LOOK_X = 0.7, LOOK_Y = 3.5, FOV = 56 }
  Sc.CHOOSE = { SIDE = 0.3, UP = 0.65, BACK = 3.4, LOOK_X = 0.7, LOOK_Y = 4.4, FOV = 54 }
  local targetPose = { eye = { 0, 0, 0 }, look = { 0, 0, 0 }, fov = 60 }
  -- a Dynamaxed member: drawn GIANT times its size (Sc.giant[i] 0..1, eased by the raid), and its
  -- shots pulled back and up by GIANT_SHOT x that so the giant stays in frame
  Sc.GIANT = 2.6
  Sc.GIANT_SHOT = { BACK = 5.0, UP = 1.8, LOOK_Y = 1.4 }
  Sc.giant = {}

  -- a member's place now: Sc.MEMBERS, until one grows giant - then the line is laid out again by width
  -- (each its SLOT_W, a giant's times its size; centred on the pad), so no two overlap whoever it is.
  -- A giant also stands GIANT_BACK further back. Eased with Sc.giant, so the others slide aside as it
  -- grows.
  Sc.SLOT_W, Sc.GIANT_BACK, Sc.SLOT_GAP = 2.05, 0.9, 0.35
  -- each member's picture's width in metres at its own size (its opaque box against MEMBER_PIC_H; set
  -- by its draw), so a wide one gets the room it takes
  Sc.memberWidth = {}
  local placed = { { x = 0, z = 0 }, { x = 0, z = 0 }, { x = 0, z = 0 }, { x = 0, z = 0 } }
  function Sc.memberPos(i)
    local n = #Sc.MEMBERS
    local any = false
    for k = 1, n do if (Sc.giant[k] or 0) > 0 then any = true end end
    local base = Sc.MEMBERS[i] or Sc.MEMBERS[1]
    if not any then return base end
    local widths, total = {}, 0
    for k = 1, n do
      local scale = 1 + ((Sc.GIANT or 1) - 1) * (Sc.giant[k] or 0)
      local own = Sc.memberWidth[k] or Sc.SLOT_W * 0.7
      widths[k] = math.max(Sc.SLOT_W, own * scale + Sc.SLOT_GAP)
      total = total + widths[k]
    end
    local x = -total / 2 + (Sc.MEMBERS[1].x + Sc.MEMBERS[n].x) / 2
    for k = 1, n do
      local p = placed[k]
      p.x = x + widths[k] / 2
      p.z = (Sc.MEMBERS[k].z or 0) - Sc.GIANT_BACK * (Sc.giant[k] or 0)
      x = x + widths[k]
    end
    return placed[i] or base
  end

  function Sc.targetShot(i, T)
    local m = Sc.memberPos(i)
    local P = Sc.PAD
    T = T or Sc.TARGET
    local g, GS = Sc.giant[i] or 0, Sc.GIANT_SHOT
    -- (a touch off its middle, toward the outside)
    local side = m.x <= 0 and -1 or 1
    targetPose.eye[1], targetPose.eye[2], targetPose.eye[3] = m.x + side * T.SIDE, T.UP + GS.UP * g, m.z + T.BACK + GS.BACK * g
    targetPose.look[1], targetPose.look[2], targetPose.look[3] = m.x * T.LOOK_X, T.LOOK_Y + GS.LOOK_Y * g, P.z
    targetPose.fov = T.FOV
    return targetPose
  end

  -- a member's own turn - choosing, moving - is framed the same way, so it is plain which one it is
  function Sc.memberShot(i) return Sc.targetShot(i, Sc.CHOOSE) end

  local clock = 0
  function Sc.setTime(t) clock = t or 0 end
  -- a new raid: what the last one set going (a shake, a jab, a battler struck, the roar's burst) is
  -- dropped - each raid's clock starts again from 0
  function Sc.resetEffects()
    clock = 0
    if Sc._shake then Sc._shake.amp = 0 end
    if Sc._kick then Sc._kick.deg = 0 end
    if Sc._struck then for k in pairs(Sc._struck) do Sc._struck[k] = nil end end
    if Sc._burst then Sc._burst.t0 = nil end
    if Sc._quake then Sc._quake.amp = 0 end
  end

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
    local pose = (name == "member" and Sc.memberShot(i)) or (name == "target" and Sc.targetShot(i))
      or (type(name) == "table" and name) or Sc.SHOTS[name]
    if not pose then return false end
    copyPose(from, cur)
    copyPose(to, pose)
    move.t0, move.dur, move.name, move.i = clock, dur or 0, type(name) == "string" and name or "pose", i
    return true
  end
  function Sc.shotName() return move.name, move.i end
  function Sc.shotDone() return move.dur <= 0 or clock - move.t0 >= move.dur end

  local shake = { amp = 0, t0 = 0, dur = 0 }
  Sc._shake = shake
  function Sc.shake(amp, dur)
    -- (a stronger shake takes over; a weaker one under way is left be)
    local st = clock - shake.t0
    local now = shake.amp > 0 and st >= 0 and st < shake.dur and shake.amp * (1 - st / shake.dur) or 0
    if (amp or 0.15) < now then return end
    shake.amp, shake.t0, shake.dur = amp or 0.15, clock, dur or 0.6
  end
  -- a blow's jab: the view narrows by deg degrees at once and eases back over dur
  local kick = { deg = 0, t0 = 0, dur = 0 }
  Sc._kick = kick
  function Sc.kick(deg, dur) kick.deg, kick.t0, kick.dur = deg or 3, clock, dur or 0.35 end
  -- the ground shaking (an earthquake): every member jolted about on it for dur, easing off
  local quake = { amp = 0, t0 = 0, dur = 0 }
  Sc._quake = quake
  function Sc.quake(amp, dur) quake.amp, quake.t0, quake.dur = amp or 1, clock, dur or 1 end
  local function quakeNow()
    local st = clock - quake.t0
    if quake.amp <= 0 or st < 0 or st > quake.dur then return 0, st end
    local u = st / quake.dur
    return quake.amp * (u < 0.1 and u / 0.1 or (1 - (u - 0.1) / 0.9)), st
  end
  -- a battler struck ("boss" or a member's place): it flashes white and is knocked back, by power
  local struck = {}
  Sc._struck = struck
  function Sc.hit(which, power) struck[which] = { t0 = clock, p = power or 0.5 } end
  Sc.HIT_FLASH_S, Sc.KNOCK_S = 0.16, 0.4
  -- white 0..1, knock 0..1 (out and back) for a battler now
  local function struckNow(which)
    local h = struck[which]
    if not h then return 0, 0, 0 end
    local st = clock - h.t0
    if st < 0 or st > Sc.KNOCK_S then return 0, 0, 0 end
    local white = st < Sc.HIT_FLASH_S and (1 - st / Sc.HIT_FLASH_S) or 0
    local u = st / Sc.KNOCK_S
    local knock = (u < 0.15 and u / 0.15 or (1 - (u - 0.15) / 0.85) ^ 2) * h.p
    return white * min(1, 0.5 + h.p), knock, st
  end

  local rect = { 0, 0, 256, 192 }
  local function place()
    local u = move.dur > 0 and min(1, max(0, (clock - move.t0) / move.dur)) or 1
    local k = u * u * u * (u * (u * 6 - 15) + 10)
    for j = 1, 3 do
      cur.eye[j] = from.eye[j] + (to.eye[j] - from.eye[j]) * k
      cur.look[j] = from.look[j] + (to.look[j] - from.look[j]) * k
    end
    cur.fov = from.fov + (to.fov - from.fov) * k
    local kt = clock - kick.t0
    local kf = 0
    if kick.deg > 0 and kt >= 0 and kt < kick.dur then
      kf = kick.deg * (kt < 0.03 and kt / 0.03 or (1 - (kt - 0.03) / (kick.dur - 0.03)) ^ 2)
    end
    -- the sway: a slow drift side to side and a breath up and down
    local sx, sy = 0.12 * sin(clock * 0.21), 0.05 * sin(clock * 0.33)
    -- the shake: a quick jitter dying away
    local hx, hy = 0, 0
    local st = clock - shake.t0
    -- (a shake not yet begun - a clock set back - does nothing)
    if shake.amp > 0 and st >= 0 and st < shake.dur then
      local a = shake.amp * (1 - st / shake.dur)
      hx, hy = a * sin(st * 71), a * sin(st * 53 + 1.3)
    end
    local ex, ey, ez = cur.eye[1] + sx + hx, cur.eye[2] + sy + hy, cur.eye[3]
    eye[1], eye[2], eye[3] = ex, ey, ez
    lookAt(cam, ex, ey, ez, cur.look[1] + sx * 0.3 + hx, cur.look[2] + hy, cur.look[3])
    -- a 3:2 view fitted to the rect: by its height on a wider rect, by its width on a taller one
    local ew, eh = rect[3], rect[4]
    local tv = tan(rad(max(10, cur.fov - kf)) / 2)
    if ew / eh > Sc.ASPECT then cam.F = (eh / 2) / tv else cam.F = (ew / 2) / (tv * Sc.ASPECT) end
    cam.CX, cam.CY = rect[1] + ew / 2, rect[2] + eh / 2
    -- (a portrait screen: the 3:2 view a little above the middle, clear of the UI at the foot)
    if ew / eh < 1 then cam.CY = rect[2] + eh * Sc.PORTRAIT_CY end
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

  -- ------- geometry (g3d's triangles: x, y, z, u, v, nx, ny, nz, r, g, b, a)

  local function vtx(x, y, z, u, v, r, g, b, a) return { x, y, z, u, v, 0, 1, 0, r, g, b, a or 1 } end
  local function lv(x, y, z, u, v, nx, ny, nz, r, g, b, a)
    local cr, cg, cb = lit(x, y, z, nx, ny, nz, r, g, b)
    return vtx(x, y, z, u, v, cr, cg, cb, a)
  end
  local function tri(out, a, b, c) out[#out + 1] = a; out[#out + 1] = b; out[#out + 1] = c end
  local function quad(out, a, b, c, d) tri(out, a, b, c); tri(out, a, c, d) end

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

  local GROUND = { 0.86, 0.5, 0.52 }      -- the arena's dust, rose under the energy's light
  local CRAG = { 0.9, 0.52, 0.44 }        -- the rocks, a red-brown

  -- the ground's dust: reddish grit, darker blotches, pebbles lit from above, a web of fine cracks,
  -- pale dust drifts (tiles both ways)
  local function dirt()
    return picture(256, 256, function(G, w, h)
      G.setColor(0.8, 0.72, 0.7, 1)
      G.rectangle("fill", 0, 0, w, h)
      local function wrap(fn) for ddx = -1, 1 do for ddy = -1, 1 do fn(ddx * w, ddy * h) end end end
      for i = 1, 90 do
        local t = hash(i, 41)
        G.setColor(0.45 + 0.2 * t, 0.36 + 0.15 * t, 0.36 + 0.14 * t, 0.22)
        local x, y, rr = w * hash(i, 42), h * hash(i, 43), 8 + 30 * hash(i, 44)
        wrap(function(ox, oy) G.ellipse("fill", x + ox, y + oy, rr, rr * (0.5 + 0.5 * hash(i, 45)), 20) end)
      end
      for i = 1, 40 do
        G.setColor(1, 0.92, 0.88, 0.1)
        local x, y, rr = w * hash(i, 46), h * hash(i, 47), 10 + 26 * hash(i, 48)
        wrap(function(ox, oy) G.ellipse("fill", x + ox, y + oy, rr * 1.6, rr * 0.5, 20) end)
      end
      -- cracks: branching dark lines, each with a pale lip
      G.setLineWidth(1.4)
      for i = 1, 14 do
        local x, y = w * hash(i, 50), h * hash(i, 51)
        local ang = hash(i, 52) * 2 * pi
        local pts = { x, y }
        for k = 1, 9 do
          ang = ang + (hash(i * 13 + k, 53) - 0.5) * 1.2
          x, y = x + cos(ang) * (5 + 9 * hash(i * 13 + k, 54)), y + sin(ang) * (5 + 9 * hash(i * 13 + k, 55))
          pts[#pts + 1], pts[#pts + 2] = x, y
        end
        G.setColor(1, 0.9, 0.86, 0.18)
        G.push(); G.translate(0.8, 0.8); G.line(pts); G.pop()
        G.setColor(0.18, 0.1, 0.1, 0.6)
        G.line(pts)
      end
      -- pebbles: a shadow, the stone, its lit top
      for i = 1, 140 do
        local x, y, rr = w * hash(i, 56), h * hash(i, 57), 1 + 3.2 * hash(i, 58) ^ 2
        G.setColor(0.1, 0.05, 0.05, 0.45)
        G.ellipse("fill", x + rr * 0.4, y + rr * 0.5, rr, rr * 0.7, 10)
        local t = hash(i, 59)
        G.setColor(0.42 + 0.25 * t, 0.3 + 0.18 * t, 0.28 + 0.16 * t, 1)
        G.ellipse("fill", x, y, rr, rr * 0.75, 10)
        G.setColor(1, 0.9, 0.85, 0.35)
        G.ellipse("fill", x - rr * 0.25, y - rr * 0.3, rr * 0.45, rr * 0.3, 8)
      end
      -- fine grit
      for i = 1, 2200 do
        local t = hash(i, 60)
        G.setColor(0.55 + 0.45 * t, 0.45 + 0.4 * t, 0.42 + 0.4 * t, 0.28)
        G.rectangle("fill", w * hash(i, 61), h * hash(i, 62), 1.2, 1.2)
      end
    end)
  end

  -- the crags' face: worn layers across, deep crevices down, lichen-dark streaks and grit
  local function cragTex()
    return picture(256, 256, function(G, w, h)
      G.setColor(0.82, 0.7, 0.64, 1)
      G.rectangle("fill", 0, 0, w, h)
      for row = 0, 15 do
        local y = row * h / 16
        G.setColor(0.35, 0.24, 0.22, 0.12 + 0.12 * hash(row, 63))
        G.rectangle("fill", 0, y, w, 3 + 6 * hash(row, 64))
        G.setColor(1, 0.92, 0.86, 0.1)
        G.rectangle("fill", 0, y + 7, w, 2)
      end
      for i = 1, 26 do
        local x = w * hash(i, 65)
        local pts = { x, 0 }
        for k = 1, 12 do
          x = x + (hash(i * 7 + k, 66) - 0.5) * 9
          pts[#pts + 1], pts[#pts + 2] = x, k * h / 12
        end
        G.setLineWidth(1 + 3 * hash(i, 67))
        G.setColor(0.12, 0.06, 0.06, 0.55)
        G.line(pts)
        G.setLineWidth(1)
        G.setColor(1, 0.9, 0.85, 0.15)
        G.push(); G.translate(2, 0); G.line(pts); G.pop()
      end
      for i = 1, 70 do
        G.setColor(0.2, 0.12, 0.12, 0.2)
        local x, y = w * hash(i, 68), h * hash(i, 69)
        G.ellipse("fill", x, y, 3 + 10 * hash(i, 70), 8 + 24 * hash(i, 71), 14)
      end
      for i = 1, 1500 do
        local t = hash(i, 72)
        G.setColor(0.5 + 0.5 * t, 0.42 + 0.45 * t, 0.4 + 0.42 * t, 0.25)
        G.rectangle("fill", w * hash(i, 73), h * hash(i, 74), 1.3, 1.3)
      end
    end)
  end

  -- the arena's ground height: flat where the battle stands, a gentle swell of dunes beyond
  local function groundY(x, z)
    local dx, dz = x - Sc.PAD.x, z - Sc.PAD.z
    local d = sqrt(dx * dx + dz * dz)
    local out = max(0, min(1, (d - 16) / 30))
    return 0.04 * (noise(x * 0.8, z * 0.8) - 0.5) + out * (1.6 * noise(x * 0.08, z * 0.08) + 0.6 * noise(x * 0.25, z * 0.25))
  end
  Sc.groundY = groundY

  -- the textures, drawn once (Sc.warm draws them ahead, a step a frame)
  local tex = { dirt = nil, crag = nil }
  local function dirtTex() tex.dirt = tex.dirt or dirt(); return tex.dirt end
  local function cragImg() tex.crag = tex.crag or cragTex(); return tex.crag end

  -- (made by Sc.warm a piece at a time: build pauses at `pause()` while it runs as warm's coroutine)
  local buildCo = nil
  local function pause()
    if buildCo and coroutine.running() == buildCo then coroutine.yield() end
  end

  local function build()
    local lib = renderer().g3d()
    local pieces = {}
    local function add(verts, img, pass, name)
      if #verts >= 3 then pieces[#pieces + 1] = { model = lib.newModel(verts, img), pass = pass, name = name } end
    end
    local PD = Sc.PAD
    local A = Sc.ARENA

    -- the ground: rings from the boss's feet out to the far haze
    do
      local v = {}
      local SEG = 72
      local radii = { 0 }
      local r = 1.2
      while r < A.r do radii[#radii + 1] = r; r = r * 1.18 + 0.6 end
      radii[#radii + 1] = A.r
      local function V(ri, i)
        local rr = radii[ri]
        local a = 2 * pi * i / SEG
        local x, z = PD.x + rr * cos(a), PD.z + rr * sin(a)
        local y = groundY(x, z)
        -- (the dust darker in hollows, lighter on the rises)
        local k = 0.86 + 0.28 * noise(x * 0.35 + 3, z * 0.35)
        return lv(x, y, z, x / 5, z / 5, 0, 1, 0, GROUND[1] * k, GROUND[2] * k, GROUND[3] * k)
      end
      for ri = 1, #radii - 1 do
        for i = 0, SEG - 1 do
          if ri == 1 then tri(v, V(1, i), V(2, i + 1), V(2, i))
          else quad(v, V(ri, i), V(ri, i + 1), V(ri + 1, i + 1), V(ri + 1, i)) end
        end
      end
      add(v, dirtTex(), 2, "ground")
    end
    pause()

    -- the crags and boulders: lumpy rounded spires, layered, with crevices (rings of vertices pushed
    -- in and out by noise), and low boulders
    do
      local v = {}
      local function crag(x, z, rb, h, seed, lean)
        local SEG, ROWS = 14, 11
        local y0 = groundY(x, z) - 0.3
        local function at(i, row)
          local a = 2 * pi * i / SEG
          local t = row / ROWS
          -- (rounded toward the top, bulging in lumps, ridged in layers, a crevice here and there)
          -- (a rounded dome: wide up most of its height, curving in over the top)
          local shape = (1 - t ^ 3.2) ^ 0.45 * (0.7 + 0.55 * noise(a * 1.7 + seed, t * 2.2 + seed))
            * (1 + 0.18 * sin(t * pi * 1.3 + seed))
          local ridge = 1 + 0.06 * sin(t * 15 + seed) + 0.05 * sin(a * 5 + seed * 3)
          local crev = 1 - 0.18 * max(0, sin(a * 3 + seed * 1.7) - 0.75) * 4
          local rr = rb * shape * ridge * crev
          if row == ROWS then rr = 0 end
          local lx = lean * t * t * h * 0.15
          return x + rr * cos(a) + lx, y0 + h * t, z + rr * sin(a), cos(a), 0.25 + 0.6 * t, sin(a), a
        end
        for i = 0, SEG - 1 do
          for row = 0, ROWS - 1 do
            local function P(ii, rr2)
              local px, py, pz, nx, ny, nz, a = at(ii, rr2)
              local shade = 0.8 + 0.35 * noise(a * 3 + seed, py * 0.6)
              return lv(px, py, pz, (ii / SEG) * rb * 1.6, -py / 3, nx, ny, nz,
                CRAG[1] * shade, CRAG[2] * shade, CRAG[3] * shade)
            end
            quad(v, P(i, row), P(i + 1, row), P(i + 1, row + 1), P(i, row + 1))
          end
        end
      end
      -- the ring of crags round the sides and the back (angles from the boss: 90 is toward the party)
      for k = 1, A.CRAGS do
        local u = (k - 0.5) / A.CRAGS
        local ang = rad(110 + 320 * u) + (hash(k, 81) - 0.5) * 0.12
        local dist = A.cragNear + (A.cragFar - A.cragNear) * hash(k, 82)
        local x, z = PD.x + dist * cos(ang), PD.z + dist * sin(ang)
        -- (none in the party's view of the boss: the front stays open)
        if not (z > PD.z + 4 and abs(x) < 16) then
          local h = 3 + 6.5 * hash(k, 83) * (dist / A.cragFar)
          crag(x, z, 2.2 + 3.2 * hash(k, 84), h, k * 3.7, (hash(k, 85) - 0.5) * 2)
          -- a smaller one beside it
          if hash(k, 86) > 0.45 then
            crag(x + 2.5 * cos(ang + 1.4), z + 2.5 * sin(ang + 1.4), 1 + 1.3 * hash(k, 87), h * 0.55, k * 5.1, 0)
          end
        end
        if k % 6 == 0 then pause() end
      end
      -- boulders scattered round the arena's edge and the sides near the party
      for k = 1, A.BOULDERS do
        local ang = 2 * pi * hash(k, 88)
        local dist = A.boulderNear + (A.boulderFar - A.boulderNear) * hash(k, 89)
        local x, z = PD.x + dist * cos(ang), PD.z + dist * sin(ang)
        if not (z > PD.z + 3 and abs(x) < 9) and not (abs(x) < 7 and z > -14 and z < 8) then
          crag(x, z, 0.5 + 1.1 * hash(k, 90), 0.6 + 1.6 * hash(k, 91), k * 2.3 + 40, 0)
        end
        if k % 12 == 0 then pause() end
      end
      pause()
      add(v, cragImg(), 2, "rocks")
    end
    pause()

    -- pebbles and stones on the battle's ground (small flat lumps)
    do
      local v = {}
      for k = 1, A.STONES do
        local ang = 2 * pi * hash(k, 92)
        local dist = 4 + 18 * hash(k, 93)
        local x, z = PD.x + dist * cos(ang), PD.z + dist * sin(ang)
        local r = 0.06 + 0.22 * hash(k, 94) ^ 2
        local y = groundY(x, z)
        local top = { x, y + r * 0.45, z }
        local n = 8
        for i = 0, n - 1 do
          local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
          local j0, j1 = 0.8 + 0.4 * hash(k * 9 + i, 95), 0.8 + 0.4 * hash(k * 9 + i + 1, 95)
          tri(v, lv(x + r * j0 * cos(a0), y, z + r * j0 * sin(a0), 0, 1, cos(a0), 0.4, sin(a0), CRAG[1], CRAG[2], CRAG[3]),
            lv(x + r * j1 * cos(a1), y, z + r * j1 * sin(a1), 1, 1, cos(a1), 0.4, sin(a1), CRAG[1], CRAG[2], CRAG[3]),
            lv(top[1], top[2], top[3], 0.5, 0, 0, 1, 0, CRAG[1] * 1.1, CRAG[2] * 1.1, CRAG[3] * 1.1))
        end
      end
      add(v, cragImg(), 2, "stones")
    end

    return { clear = Sc.CLEAR, pieces = pieces }
  end

  function Sc.scene()
    if scene or Sc.failed then return scene end
    local ok, s = pcall(build)
    if ok and s then scene = s else
      Sc.failed, Sc.why = true, "the den did not build (" .. tostring(s) .. ")"
      if mod.log then mod.log:warn("Galar Rising: %s; drawn flat", Sc.why) end
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

  -- the motes: MOTES specks of energy drifting up over the plain, twinkling;
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
          local r, g, b = 0.95, 0.6, 1
          if warm == 1 then r, g, b = 1, 0.4, 0.7 end
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

  -- ------- the sky behind the arena (2D, under the 3D picture, whose own sky is left clear): a night
  -- sky dark at the top to a violet haze at the horizon, stars, the aurora's curtains, a pale mist
  -- along the horizon

  Sc.SKY = { top = { 0.015, 0.01, 0.045 }, mid = { 0.09, 0.03, 0.14 }, horizon = { 0.42, 0.14, 0.36 }, STARS = 260 }
  local skyMesh = nil
  local skyV = {}
  for i = 1, 6 do skyV[i] = { 0, 0, 0, 0, 1, 1, 1, 1 } end
  local function horizonY()
    local x, y = project(eye[1], eye[2], eye[3] - 2000)
    return y
  end
  -- (top of the rect dark, a violet band part way down, the haze at the horizon and below it)
  local function skyGradient(G2, ex, ey, ew, eh, hy)
    local S = Sc.SKY
    hy = hy or (ey + eh * 0.5)
    local top = min(ey, hy - eh * 0.2)
    local my = top + (hy - top) * 0.55
    local function set(i, x, y, c)
      local t = skyV[i]
      t[1], t[2], t[5], t[6], t[7], t[8] = x, y, c[1], c[2], c[3], 1
    end
    set(1, ex, top, S.top); set(2, ex + ew, top, S.top)
    set(3, ex, my, S.mid); set(4, ex + ew, my, S.mid)
    set(5, ex, hy, S.horizon); set(6, ex + ew, hy, S.horizon)
    if not skyMesh then skyMesh = G2.newMesh(skyV, "strip", "stream") else skyMesh:setVertices(skyV) end
    G2.setColor(1, 1, 1, 1)
    G2.draw(skyMesh)
    G2.setColor(S.horizon[1], S.horizon[2], S.horizon[3], 1)
    if hy < ey + eh then G2.rectangle("fill", ex, hy, ew, ey + eh - hy) end
  end

  -- the stars: directions over the far half of the sky, projected each frame (fixed at infinity)
  local starDir, starPts = nil, {}
  local function stars(G2, ex, ey, ew, eh, hy)
    if not starDir then
      starDir = {}
      for i = 1, Sc.SKY.STARS do
        local az = rad(-120 + 240 * hash(i, 101)) - pi / 2
        local el = math.asin(0.06 + 0.94 * hash(i, 102) ^ 0.8)
        starDir[i] = { cos(el) * cos(az), math.sin(el), cos(el) * sin(az), 0.35 + 0.65 * hash(i, 103) ^ 2, hash(i, 104) }
        starPts[i] = { 0, 0, 1, 1, 1, 0 }
      end
    end
    local n = 0
    for i = 1, #starDir do
      local d = starDir[i]
      local x, y = project(eye[1] + d[1] * 500, eye[2] + d[2] * 500, eye[3] + d[3] * 500)
      if x and y < (hy or 1e9) - 2 and x > ex and x < ex + ew and y > ey then
        n = n + 1
        local p = starPts[n]
        local tw = 0.55 + 0.45 * sin(clock * (1.5 + 3 * d[5]) + i)
        local cool = d[5] > 0.7
        p[1], p[2], p[3], p[4], p[5], p[6] = x, y, cool and 0.75 or 1, cool and 0.85 or 0.95, 1, d[4] * tw
      end
    end
    for i = n + 1, #starPts do starPts[i][6] = 0 end
    G2.setPointSize(max(1, eh / 300))
    G2.setColor(1, 1, 1, 1)
    if n > 0 then G2.points(starPts) end
    -- a few bright ones with a soft glow
    for i = 1, min(n, 18) do
      local p = starPts[i]
      if starDir[i][4] > 0.75 then glow(G2, p[1], p[2], eh * 0.006, eh * 0.006, 0.8, 0.85, 1, 0.35 * p[6]) end
    end
  end

  -- the aurora: curtains on rings round the arena (behind and to the sides), each a strip of columns
  -- whose foot and top wave in time; the shader lights rays along them, shifts their hue through
  -- violet, magenta, blue and green, and fades them up their height (added light)
  Sc.AURORA = {
    { r = 70, a0 = 175, a1 = 365, foot = 2, top = 52, amp = 6, speed = 0.17, hue = 0.0, bright = 1.9 },
    { r = 56, a0 = 195, a1 = 345, foot = 4, top = 40, amp = 5, speed = -0.23, hue = 0.33, bright = 1.5 },
    { r = 90, a0 = 160, a1 = 380, foot = 1, top = 70, amp = 8, speed = 0.11, hue = 0.62, bright = 1.4 },
    COLS = 96,
  }
  local AURORA_SHADER = [[
extern float auT;
extern float hueOff;
extern float bright;
vec3 pal(float h) {
  // violet -> magenta -> deep blue -> teal-green -> violet, blended round a loop (ominous: deep,
  // violet the most of it)
  vec3 c0 = vec3(0.55, 0.18, 0.95);
  vec3 c1 = vec3(1.0, 0.22, 0.68);
  vec3 c2 = vec3(0.22, 0.38, 1.0);
  vec3 c3 = vec3(0.16, 0.95, 0.62);
  float x = fract(h) * 5.0;
  if (x < 1.0) return mix(c0, c1, smoothstep(0.0, 1.0, x));
  if (x < 2.0) return mix(c1, c0, smoothstep(1.0, 2.0, x));
  if (x < 3.0) return mix(c0, c2, smoothstep(2.0, 3.0, x));
  if (x < 4.0) return mix(c2, c3, smoothstep(3.0, 4.0, x));
  return mix(c3, c0, smoothstep(4.0, 5.0, x));
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float u = tc.x;
  float v = tc.y;
  // rays: fine streaks drifting along, folded by a slower wave
  float fold = sin(u * 3.1 + auT * 0.35) * 1.6 + sin(u * 7.3 - auT * 0.55) * 0.6;
  float rays = 0.5 + 0.32 * sin(u * 38.0 + fold * 2.0 + auT * 1.1) + 0.18 * sin(u * 91.0 - auT * 2.3);
  rays = pow(clamp(rays, 0.0, 1.0), 1.3);
  // up the curtain: a bright hem at its foot, fading to nothing at its top
  float hem = smoothstep(0.0, 0.05, v) * (0.45 + 0.55 * exp(-v * 3.5)) * pow(1.0 - v, 0.9);
  // the light breathing along it
  float breath = 0.55 + 0.45 * sin(u * 2.0 - auT * 0.4 + hueOff * 6.0);
  float h = fract(u * 0.42 + auT * 0.045 + hueOff + v * 0.22);
  vec3 col = pal(h) * (0.6 + 0.4 * (1.0 - v));
  float a = rays * hem * breath * bright * color.a;
  return vec4(col * a, a);
}
]]
  local auroraShader, auroraFailed = nil, false
  local auroraMeshes, auroraV = {}, {}
  local function aurora(G2, ex, ey, ew, eh)
    if auroraFailed then return end
    if not auroraShader then
      local ok, s = pcall(G2.newShader, AURORA_SHADER)
      if not ok then auroraFailed = true; return end
      auroraShader = s
    end
    local A = Sc.AURORA
    local PD = Sc.PAD
    local N = A.COLS
    G2.setShader(auroraShader)
    G2.setBlendMode("add", "premultiplied")
    G2.setColor(1, 1, 1, 1)
    auroraShader:send("auT", clock % 1000)
    for c = 1, #A do
      local C = A[c]
      local V = auroraV[c]
      if not V then
        V = {}
        for i = 1, (N + 1) * 2 do V[i] = { 0, 0, 0, 0, 1, 1, 1, 1 } end
        auroraV[c] = V
      end
      local lastX, lastY, lastTX, lastTY = ex, ey + eh * 0.5, ex, ey
      for i = 0, N do
        local f = i / N
        local ang = rad(C.a0 + (C.a1 - C.a0) * f)
        -- (the curtain sways in and out, its foot and its top ripple)
        local sway = C.amp * sin(f * 9 + clock * C.speed * 4) + C.amp * 0.5 * sin(f * 23 - clock * C.speed * 7)
        local r = C.r + sway
        local x, z = PD.x + r * cos(ang), PD.z + r * sin(ang)
        local foot = C.foot + 2 * sin(f * 13 + clock * 0.3 + c)
        local top = C.top + 6 * sin(f * 5 - clock * 0.25 + c * 2) + 3 * sin(f * 17 + clock * 0.6)
        local bx, by = project(x, foot, z)
        local tx, ty = project(x, top, z)
        if bx and tx then lastX, lastY, lastTX, lastTY = bx, by, tx, ty end
        local vb, vt = V[i * 2 + 1], V[i * 2 + 2]
        local u = f * (C.a1 - C.a0) / 60 + c * 1.7
        vb[1], vb[2], vb[3], vb[4] = lastX, lastY, u, 0
        vt[1], vt[2], vt[3], vt[4] = lastTX, lastTY, u, 1
      end
      local m = auroraMeshes[c]
      if not m then m = G2.newMesh(V, "strip", "stream"); auroraMeshes[c] = m else m:setVertices(V) end
      auroraShader:send("hueOff", C.hue)
      auroraShader:send("bright", C.bright)
      G2.draw(m)
    end
    G2.setShader()
    G2.setBlendMode("alpha")
  end

  local function horizonMist(G2, ex, ey, ew, eh, hy)
    if not hy then return end
    -- a pale band of mist where the aurora meets the land, cooler above, rose below
    glow(G2, ex + ew * 0.5, hy - eh * 0.04, ew * 0.85, eh * 0.16, 0.45, 0.6, 0.75, 0.42)
    glow(G2, ex + ew * 0.3, hy - eh * 0.03, ew * 0.4, eh * 0.1, 0.75, 0.75, 0.9, 0.3)
    glow(G2, ex + ew * 0.72, hy - eh * 0.03, ew * 0.4, eh * 0.1, 0.9, 0.6, 0.85, 0.3)
    glow(G2, ex + ew * 0.5, hy + eh * 0.02, ew * 0.9, eh * 0.08, 0.95, 0.4, 0.6, 0.3)
  end

  -- ------- over the boss: the Dynamax portal - a vast vortex of violet and magenta cloud turning in
  -- the sky above its head, bright round its eye, its arms radiating out and thinning into the night;
  -- a horizontal disc in the world (a grid projected each frame), drawn by a shader in its polar
  -- coordinates
  Sc.PORTAL = { UP = 1.0, LIFT = 1.4, R_K = 2.3, R_MIN = 11, GRID = 18, SPIN = 0.22 }
  local PORTAL_SHADER = [[
extern float poT;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.1) + 0.15 * vnoise(p * 4.3); }
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p = tc * 2.0 - 1.0;
  float r = length(p);
  if (r > 1.0) return vec4(0.0);
  float a = atan(p.y, p.x);
  // the spiral: the angle wound by the log of the radius, turning in time
  float sw = a + log(r + 0.04) * 2.6 - poT;
  float arms = 0.5 + 0.5 * sin(sw * 3.0);
  // billowing cloud along the arms
  vec2 q = vec2(cos(sw) * r * 3.0, sin(sw) * r * 3.0) + vec2(poT * 0.15, 0.0);
  float cloud = fbm(q * 1.6 + vec2(r * 2.0, 0.0));
  float body = smoothstep(0.25, 0.85, arms * 0.6 + cloud * 0.7);
  // waves radiating outward from the eye
  float wave = 0.5 + 0.5 * sin(r * 22.0 - poT * 4.5 + cloud * 3.0);
  // the eye: a dark heart ringed bright magenta
  float eyeRing = exp(-pow((r - 0.14) / 0.05, 2.0));
  float heart = smoothstep(0.12, 0.0, r);
  // thinning to nothing at its edge
  float fade = pow(1.0 - smoothstep(0.35, 1.0, r), 1.3);
  vec3 deep = vec3(0.16, 0.03, 0.22);
  vec3 violet = vec3(0.48, 0.12, 0.62);
  vec3 magenta = vec3(1.0, 0.28, 0.66);
  vec3 col = mix(deep, violet, body);
  col = mix(col, magenta, body * (0.35 + 0.4 * wave) * (1.0 - smoothstep(0.2, 0.8, r)));
  col += magenta * eyeRing * 1.2;
  col = mix(col, vec3(0.06, 0.0, 0.1), heart * 0.85);
  float alpha = (0.35 + 0.65 * body) * fade + eyeRing * 0.8 + heart * 0.9;
  alpha *= color.a;
  return vec4(col * clamp(alpha, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
]]
  local portalShader, portalFailed, portalMesh = nil, false, nil
  local portalV = {}
  -- the portal's grid mesh and its triangles (made once)
  function Sc._portalInit(G2)
    local GN = Sc.PORTAL.GRID
    for i = 1, (GN + 1) * (GN + 1) do portalV[i] = { 0, 0, 0, 0, 1, 1, 1, 1 } end
    local map = {}
    for j = 0, GN - 1 do
      for i = 0, GN - 1 do
        local a = j * (GN + 1) + i + 1
        local b, c, d = a + 1, a + GN + 1, a + GN + 2
        map[#map + 1] = a; map[#map + 1] = b; map[#map + 1] = d
        map[#map + 1] = a; map[#map + 1] = d; map[#map + 1] = c
      end
    end
    portalMesh = G2.newMesh(portalV, "triangles", "stream")
    portalMesh:setVertexMap(map)
  end
  local function portal(G2, size)
    if portalFailed then return end
    local PO = Sc.PORTAL
    local GN = PO.GRID
    if not portalShader then
      local ok, s = pcall(G2.newShader, PORTAL_SHADER)
      if not ok then portalFailed = true; return end
      portalShader = s
      Sc._portalInit(G2)
    end
    if not portalMesh then return end
    local PD = Sc.PAD
    local h = Sc.MEMBER_H * (size or 3.5)
    local Y = h * PO.UP + PO.LIFT
    local Rr = max(PO.R_MIN, h * PO.R_K)
    -- (turned in the plane: the spin carried in the shader's clock)
    for j = 0, GN do
      for i = 0, GN do
        local u, v = i / GN, j / GN
        local x, z = PD.x + (u * 2 - 1) * Rr, PD.z + (v * 2 - 1) * Rr
        local sx, sy = project(x, Y, z)
        local t = portalV[j * (GN + 1) + i + 1]
        -- (a point behind the eye: folded onto the eye's middle, its triangles collapsing)
        if not sx then sx, sy = cam.CX, cam.CY - 4000 end
        t[1], t[2], t[3], t[4] = sx, sy, u, v
      end
    end
    portalMesh:setVertices(portalV)
    portalShader:send("poT", (clock * PO.SPIN * 2 * pi) % (2 * pi * 100))
    G2.setShader(portalShader)
    G2.setBlendMode("alpha", "premultiplied")
    G2.setColor(1, 1, 1, 1)
    G2.draw(portalMesh)
    G2.setShader()
    G2.setBlendMode("alpha")
    -- its light falling on the boss below: a faint violet bloom
    local cx, cy, d = project(PD.x, Y, PD.z)
    if cx then glow(G2, cx, cy, Rr * cam.F / d * 0.9, Rr * cam.F / d * 0.35, 0.6, 0.2, 0.7, 0.18) end
  end

  -- pink energy pillars rising from the ground round the boss's feet, flickering
  Sc.PILLARS = 9
  local function pillars(G2, size, front)
    local PD = Sc.PAD
    local h = Sc.MEMBER_H * (size or 3.5)
    for i = 1, Sc.PILLARS do
      local ang = 2 * pi * (i + 0.3 * hash(i, 111)) / Sc.PILLARS
      local inFront = sin(ang) > 0
      if inFront == front then
        local rr = PD.r * (0.7 + 0.6 * hash(i, 112))
        local x, z = PD.x + rr * cos(ang), PD.z + rr * sin(ang)
        local life = (clock * (0.25 + 0.2 * hash(i, 113)) + hash(i, 114)) % 1
        local a = sin(life * pi) ^ 2 * (0.55 + 0.45 * sin(clock * 9 + i * 3))
        local top = h * (0.25 + 0.55 * hash(i, 115)) * (0.6 + 0.4 * sin(life * pi))
        local bx, by, bd = project(x, 0, z)
        local tx, ty = project(x, top, z)
        if bx and tx and a > 0.02 then
          local w = 0.3 * cam.F / bd
          G2.setBlendMode("add")
          G2.setColor(1, 0.3, 0.62, a * 0.75)
          G2.polygon("fill", bx - w, by, bx + w, by, tx + w * 0.15, ty, tx - w * 0.15, ty)
          G2.setColor(1, 0.85, 0.95, a * 0.7)
          G2.polygon("fill", bx - w * 0.3, by, bx + w * 0.3, by, tx, ty)
          G2.setBlendMode("alpha")
          glow(G2, bx, by, w * 4, w * 1.2, 1, 0.35, 0.65, a * 0.5)
        end
      end
    end
    -- (and the energy pooled on the ground under it, once)
    if not front then
      local gx, gy, gd = project(PD.x, 0.02, PD.z)
      if gx then
        local R = PD.r * 1.6 * cam.F / gd
        glow(G2, gx, gy, R, R * 0.25, 1, 0.25, 0.55, 0.55 + 0.1 * sin(clock * 2))
      end
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
  -- the Dynamax cloud (Sword / Shield's): a three-part halo over its head - three long, lumpy dark-red
  -- cloud banks, each curving along a ring round it (ARC of it, small gaps between them), turning
  -- slowly; thin at their ends, the far side smaller and dimmer, each lump churning, a small puff
  -- breaking off each bank's end. (hx, hy) the top of its head, w its width on screen, a its
  -- strength; gmax: a Gigantamax one's, lit pinker. Sc.CLOUD holds the numbers (LUMP a lump's
  -- radius x w).
  Sc.CLOUD = { RING_W = 0.56, RING_UP = 0.3, RING_FLAT = 0.32, SPIN = 0.3, ARC = 1.3, LUMP = 0.085, LUMPS = 15,
    DARK = { 0.2, 0.0, 0.02 }, BODY = { 0.48, 0.01, 0.05 }, LIT = { 0.78, 0.08, 0.13 }, SHINE = { 1, 0.38, 0.38 },
    GMAX_LIT = { 1, 0.24, 0.38 } }
  local lumpX, lumpY, lumpR, lumpD = {}, {}, {}, {}
  -- one bank: its lumps laid out (lumpX / Y / R / D), then drawn in four passes - the shadow under,
  -- the body, the light on top, a shine - so the bank reads as one cloud with a lumpy top
  local function cloudBank(G2, n, a, lit)
    local C = Sc.CLOUD
    for pass = 1, 4 do
      local col = pass == 1 and C.DARK or pass == 2 and C.BODY or pass == 3 and lit or C.SHINE
      for q = 1, n do
        local r, depth = lumpR[q], lumpD[q]
        local ox, oy, sk = 0, 0, 1
        if pass == 1 then ox, oy, sk = r * 0.1, r * 0.22, 1.05
        elseif pass == 3 then ox, oy, sk = -r * 0.08, -r * 0.22, 0.6
        elseif pass == 4 then ox, oy, sk = -r * 0.16, -r * 0.38, 0.22 end
        local dk = 0.55 + 0.45 * depth
        local alpha = a * (pass == 4 and 0.3 or 1) * (pass >= 3 and (0.5 + 0.5 * depth) or 1)
        if r > 0.5 and (pass < 4 or q % 3 == 2) then
          G2.setColor(col[1] * dk, col[2] * dk, col[3] * dk, alpha)
          G2.circle("fill", lumpX[q] + ox, lumpY[q] + oy, r * sk, 18)
        end
      end
    end
  end
  local cloudOrder = { {}, {}, {} }
  function Sc.dynaCloud(G2, hx, hy, w, t, a, gmax)
    if a <= 0 or w <= 0 then return end
    local C = Sc.CLOUD
    local rx = w * C.RING_W
    local ry = rx * C.RING_FLAT
    local cy = hy - w * C.RING_UP
    local lit = gmax and C.GMAX_LIT or C.LIT
    local N = C.LUMPS
    -- the far banks first (by their middles)
    for j = 0, 2 do
      local o = cloudOrder[j + 1]
      o.ang = t * C.SPIN + j * 2 * pi / 3
      o.depth, o.j = (sin(o.ang) + 1) / 2, j
    end
    table.sort(cloudOrder, function(p, q) return p.depth < q.depth end)
    for _, o in ipairs(cloudOrder) do
      local seed = o.j * 7 + 3
      local bob = sin(t * 1.3 + o.j * 2) * w * 0.01
      for q = 1, N do
        local f = (q - 1) / (N - 1) - 0.5
        -- (along the ring; every other lump higher and the sizes uneven, so its top is lumpy; thin
        -- at both ends)
        local th = o.ang + f * C.ARC + (hash(seed, q) - 0.5) * 0.06
        local depth = (sin(th) + 1) / 2
        local near = 0.7 + 0.4 * depth
        local taper = 1 - 1.5 * f * f
        local r = w * C.LUMP * near * taper * (0.75 + 0.45 * hash(seed, q + 40)) * (1 + 0.06 * sin(t * 2.1 + q * 1.7))
        local lift = ((q % 2 == 0) and 0.45 or 0) + (hash(seed, q + 20) - 0.5) * 0.5
        lumpX[q] = hx + cos(th) * rx
        lumpY[q] = cy + sin(th) * ry + bob - r * lift + sin(t * 1.4 + q * 1.3 + seed) * r * 0.08
        lumpR[q], lumpD[q] = r, depth
      end
      cloudBank(G2, N, a, lit)
      -- a small puff breaking off the bank's leading end and fading as it rises
      local u = (t * 0.4 + o.j * 0.33) % 1
      local th = o.ang + 0.5 * C.ARC
      local pr = w * C.LUMP * 0.5 * (1 - u)
      if pr > 0.5 then
        G2.setColor(C.BODY[1], C.BODY[2], C.BODY[3], a * (1 - u) * 0.8)
        G2.circle("fill", hx + cos(th + 0.25 * u) * rx, cy + sin(th + 0.25 * u) * ry - w * C.LUMP * (1 + 3 * u), pr, 12)
      end
    end
  end

  local function drawBoss(G2, pic, size, t)
    if not (pic and pic.image) then return end
    local box = pic.box
    local bw, bh = box[3] - box[1], box[4] - box[2]
    local x, y, hpx = Sc.bossAt(size, bh)
    if not x then return end
    local k = hpx / bh
    local ox, oy = (box[1] + box[3]) / 2, box[4]
    -- an attack's lunge (pic.lunge 0..1): it rears up and toward the party
    local lunge = pic.lunge or 0
    if lunge > 0 then
      k = k * (1 + 0.1 * lunge)
      y = y + hpx * 0.04 * lunge
    end
    -- struck: knocked back (smaller, a jolt aside), flashing white over its sprite below
    local white, knock, kst = struckNow("boss")
    if knock > 0 then
      k = k * (1 - 0.05 * knock)
      x = x + sin(kst * 80) * hpx * 0.025 * knock
      y = y - hpx * 0.02 * knock
    end
    -- a leap (pic.jump: up, or below 0 a crouch / the landing's squash): risen off its pad, stretched
    -- in the air, squashed on the ground
    local jump = pic.jump or 0
    local jx = 1
    local groundY = y
    if jump > 0 then
      y = y - hpx * 0.28 * jump
      jx = 1 - 0.04 * jump
    elseif jump < 0 then
      jx = 1 - 0.3 * jump
    end
    -- where it stands on screen, for the raid's throw (its middle and height)
    Sc.lastBoss = Sc.lastBoss or {}
    Sc.lastBoss.x, Sc.lastBoss.y, Sc.lastBoss.h = x, y - bh * k * 0.5, bh * k
    -- being caught: drawn into the ball (pic.shrink 1 -> 0, about its middle, a red glow)
    local shrink = pic.shrink or 1
    if shrink < 1 then
      if shrink <= 0.01 then return end
      local cy = y - bh * k * 0.5
      local ks = k * shrink
      local s = sil()
      if s then
        G2.setShader(s)
        G2.setColor(1, 0.25, 0.3, 0.85 * shrink)
        for _, dd in ipairs(OUT) do G2.draw(pic.image, pic.quad, x + dd[1] * 2, cy + dd[2] * 2, 0, ks, ks, ox, (box[2] + box[4]) / 2) end
        G2.setShader()
      end
      G2.setColor(1, 0.75, 0.75, shrink)
      drawPixel(pic.image, pic.quad, x, cy, 0, ks, ks, ox, (box[2] + box[4]) / 2)
      G2.setColor(1, 1, 1, 1)
      return
    end
    -- its shadow and the pad's glow under it
    -- (on the ground, smaller while it is in the air)
    local sk = jump > 0 and (1 - 0.35 * jump) or 1
    G2.setColor(0, 0, 0, 0.45 * sk)
    G2.ellipse("fill", x, groundY, bw * k * 0.42 * sk, bw * k * 0.09 * sk, 32)
    glow(G2, x, groundY, bw * k * 0.6, bw * k * 0.14, 1, 0.6, 0.35, 0.35)
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
    drawPixel(pic.image, pic.quad, x, y, 0, k * jx, k / jx, ox, oy)
    if white > 0 and s then
      G2.setShader(s)
      G2.setBlendMode("add")
      G2.setColor(1, 1, 1, 0.55 * white)
      G2.draw(pic.image, pic.quad, x, y, 0, k, k, ox, oy)
      G2.setBlendMode("alpha")
      G2.setShader()
    end
    -- the Dynamax cloud circling over its head
    Sc.dynaCloud(G2, x, y - bh * k, math.min(bw, bh * 1.2) * k, t, 1, pic.gmax)
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

  -- a Dynamaxed member's aura, as the boss's (a wide dark-red glow, the bright outline, swirling
  -- streaks, rising sparks) at strength g; its cloud is drawn over its sprite (Sc.dynaCloud)
  function Sc.memberAura(G2, pic, x, y, k, fx, t, g)
    local box = pic.box
    local bw, bh = box[3] - box[1], box[4] - box[2]
    local ox, oy = (box[1] + box[3]) / 2, box[4]
    local s = sil()
    if s then
      G2.setShader(s)
      local o1 = max(1.5, k * 2.2)
      local pulse = 0.7 + 0.3 * sin(t * 4)
      G2.setColor(0.45, 0.0, 0.02, 0.45 * pulse * g)
      for _, dd in ipairs(OUT) do
        if pic.quad then G2.draw(pic.image, pic.quad, x + dd[1] * o1 * 1.8, y + dd[2] * o1 * 1.8, 0, k * fx, k, ox, oy)
        else G2.draw(pic.image, x + dd[1] * o1 * 1.8, y + dd[2] * o1 * 1.8, 0, k * fx, k, ox, oy) end
      end
      G2.setColor(1, 0.12, 0.12, 0.95 * g)
      for _, dd in ipairs(OUT) do
        if pic.quad then G2.draw(pic.image, pic.quad, x + dd[1] * o1 * 0.6, y + dd[2] * o1 * 0.6, 0, k * fx, k, ox, oy)
        else G2.draw(pic.image, x + dd[1] * o1 * 0.6, y + dd[2] * o1 * 0.6, 0, k * fx, k, ox, oy) end
      end
      G2.setShader()
    end
    -- streaks swirling round its body
    G2.setLineWidth(max(1, k * 1.2))
    local cx, cy = x, y - bh * k * 0.5
    local rx, ry = bw * k * 0.62, bh * k * 0.18
    for j = 0, 2 do
      local a0 = t * (1.4 + 0.3 * j) + j * 2.1
      for sgm = 0, 9 do
        local a1, a2 = a0 - sgm * 0.09, a0 - (sgm + 1) * 0.09
        G2.setColor(1, 0.1, 0.12, (1 - sgm / 10) * (sin(a1) > 0 and 0.9 or 0.35) * g)
        G2.line(cx + rx * cos(a1), cy + ry * sin(a1) + (j - 1) * bh * k * 0.18,
          cx + rx * cos(a2), cy + ry * sin(a2) + (j - 1) * bh * k * 0.18)
      end
    end
    G2.setLineWidth(1)
    -- sparks rising off it
    for i = 1, 14 do
      local u = (hash(i, 61) + t * (0.25 + 0.3 * hash(i, 62))) % 1
      G2.setColor(1, 0.25 + 0.3 * hash(i, 64), 0.1, (1 - u) * 0.9 * g)
      G2.rectangle("fill", x + (hash(i, 63) - 0.5) * bw * k * 1.1, y - u * bh * k * 1.15, max(1, k * 1.2), max(1, k * 1.2))
    end
  end

  -- a member's feet on screen and its height in px
  function Sc.memberAt(i)
    local m = Sc.MEMBERS[i] and Sc.memberPos(i)
    if not m then return nil end
    local x, y, d = project(m.x, 0, m.z)
    if not x then return nil end
    return x, y, Sc.MEMBER_H * cam.F / d
  end
  local function drawMember(G2, i, pic, t)
    if not (pic and pic.image) then return end
    -- (its width at its own size, for the line's spacing: Sc.memberPos)
    if pic.box then Sc.memberWidth[i] = (pic.box[3] - pic.box[1]) / (pic.cell or 64) * Sc.MEMBER_PIC_H end
    local x, y, hpx = Sc.memberAt(i)
    if not x then return end
    local box = pic.box
    local bw = box[3] - box[1]
    -- one scale for every member (a 64-px pic is MEMBER_PIC_H tall), not each fitted to a height
    local k = hpx * (Sc.MEMBER_PIC_H / Sc.MEMBER_H) / (pic.cell or 64)
    -- (a back pic faces up and to the right: those right of the boss are mirrored to face it)
    local fx = Sc.MEMBER_FLIP[i] and -1 or 1
    -- fainted: taken off the field - it turns red and shrinks away about its middle, lifting a little
    -- (pic.shrink 1 -> 0; back in the fight, 0 -> 1 the same way)
    local shrink = pic.shrink or 1
    if shrink < 1 then
      if shrink <= 0.01 then return end
      local midY = (box[2] + box[4]) / 2
      local ks = k * shrink * shrink
      local cy = y - (box[4] - midY) * k - hpx * 0.15 * (1 - shrink)
      local ox = (box[1] + box[3]) / 2
      local s = sil()
      if s then
        G2.setShader(s)
        G2.setBlendMode("add")
        G2.setColor(1, 0.2, 0.25, 0.7 * shrink)
        for _, dd in ipairs(OUT) do
          if pic.quad then G2.draw(pic.image, pic.quad, x + dd[1] * 2, cy + dd[2] * 2, 0, ks * fx, ks, ox, midY)
          else G2.draw(pic.image, x + dd[1] * 2, cy + dd[2] * 2, 0, ks * fx, ks, ox, midY) end
        end
        G2.setBlendMode("alpha")
        G2.setShader()
      end
      G2.setColor(1, 0.55 + 0.45 * shrink, 0.55 + 0.45 * shrink, shrink)
      if pic.quad then drawPixel(pic.image, pic.quad, x, cy, 0, ks * fx, ks, ox, midY)
      else drawPixel(pic.image, x, cy, 0, ks * fx, ks, ox, midY) end
      G2.setColor(1, 1, 1, 1)
      return
    end
    -- Dynamaxed: giant (pic.giant 0..1), its red aura round it, G-Max clouds over a Gigantamax one
    local g = pic.giant or 0
    if g > 0 then k = k * (1 + (Sc.GIANT - 1) * g) end
    G2.setColor(0, 0, 0, 0.5)
    G2.ellipse("fill", x, y, bw * k * 0.42, bw * k * 0.1, 24)
    if g > 0 then Sc.memberAura(G2, pic, x, y, k, fx, t, g) end
    -- a slow breath
    local b = 1 + 0.015 * sin(t * 2.4 + i * 1.3)
    -- struck: thrown back toward the camera (larger, lower, a jolt aside), flashing white
    local white, knock, kst = struckNow(i)
    local kx, kb = k, k * b
    local sx, sy = x, y
    if knock > 0 then
      kx, kb = kx * (1 + 0.06 * knock), kb * (1 - 0.06 * knock)
      sx = sx + sin(kst * 90) * hpx * 0.05 * knock
      sy = sy + hpx * 0.05 * knock
    end
    -- the ground shaking: jolted side to side, bounced up off it
    local qa, qst = quakeNow()
    if qa > 0 then
      sx = sx + sin(qst * 47 + i * 1.9) * hpx * 0.05 * qa
      sy = sy - math.abs(sin(qst * 31 + i * 2.7)) * hpx * 0.04 * qa
    end
    G2.setColor(1, 1, 1, 1)
    local ox, oy = (box[1] + box[3]) / 2, box[4]
    if pic.quad then drawPixel(pic.image, pic.quad, sx, sy, 0, kx * fx, kb, ox, oy)
    else drawPixel(pic.image, sx, sy, 0, kx * fx, kb, ox, oy) end
    local s = white > 0 and sil()
    if s then
      G2.setShader(s)
      G2.setBlendMode("add")
      G2.setColor(1, 1, 1, 0.9 * white)
      if pic.quad then G2.draw(pic.image, pic.quad, sx, sy, 0, kx * fx, kb, ox, oy)
      else G2.draw(pic.image, sx, sy, 0, kx * fx, kb, ox, oy) end
      G2.setBlendMode("alpha")
      G2.setShader()
    end
    -- Dynamaxed: the cloud circling over its head (over the sprite)
    if g > 0 then
      local top = sy - (box[4] - box[2]) * kb
      Sc.dynaCloud(G2, sx, top, math.min(box[3] - box[1], (box[4] - box[2]) * 1.2) * kx, t + i * 1.7, g, pic.gmax)
    end
  end

  -- the roar: a white flash, streaks of energy bursting out of the boss's middle, a shockwave
  -- ring running over the ground from the pad, a red wash fading (Sc.burst at the clock's now)
  Sc.BURST_S = 1.6
  local burst = { t0 = nil }
  Sc._burst = burst
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

  -- the flat version (no 3D): the plain from the horizon down in its dust colour, under the same sky
  function Sc.drawFlat(G2, ex, ey, ew, eh)
    Sc.setRect(ex, ey, ew, eh)
    place()
    local hy = horizonY() or (ey + eh * 0.5)
    G2.setColor(0.42, 0.2, 0.24, 1)
    G2.rectangle("fill", ex, hy, ew, max(0, ey + eh - hy))
    G2.setColor(0.6, 0.3, 0.34, 1)
    local near = hy + (ey + eh - hy) * 0.35
    G2.rectangle("fill", ex, near, ew, max(0, ey + eh - near))
  end

  -- the den over ex, ey, ew, eh at clock t: boss = { image, quad, box, size } (or nil),
  -- members = list of { image, quad, box } (nil skips a place)
  function Sc.draw(G2, ex, ey, ew, eh, t, boss, members)
    clock = t or clock
    Sc.setRect(ex, ey, ew, eh)
    place()
    -- the night behind it all: sky, stars, the aurora, the mist on the horizon
    local hy = horizonY()
    skyGradient(G2, ex, ey, ew, eh, hy)
    stars(G2, ex, ey, ew, eh, hy)
    aurora(G2, ex, ey, ew, eh)
    horizonMist(G2, ex, ey, ew, eh, hy)
    local ok = false
    if Sc.available() and scene then ok = renderer().draw(G2, scene, ex, ey, ew, eh) end
    if not ok then Sc.drawFlat(G2, ex, ey, ew, eh) end
    -- the portal over the boss, the energy at its feet
    local size = boss and boss.size or 3.5
    portal(G2, size)
    pillars(G2, size, false)
    -- (the move effects' back layer: the ground and what stands behind the boss; their middle layer
    -- between the boss and the party: Sc.onBack / Sc.onMid, set by the raid)
    if Sc.onBack then Sc.onBack(G2) end
    if boss then drawBoss(G2, boss, boss.size, clock) end
    pillars(G2, size, true)
    if Sc.onMid then Sc.onMid(G2) end
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

  -- the battlefield made ahead, a step each call (outside any draw): the dust's texture, the crags',
  -- the meshes a part at a time, then the sky's shaders - so the raid's first frame does not do it
  -- all at once. true once all done. Sc.warmAll does every step now (the raid calls it while the
  -- screen is black between the den screen and the raid).
  local warmStep = 0
  function Sc.warm()
    if warmStep >= 4 or not (love and love.graphics) then return true end
    local G2 = love.graphics
    -- (the meshes: the build resumed until it is done, a part each call)
    if warmStep == 2 and not scene and not Sc.failed then
      if not buildCo then buildCo = coroutine.create(build) end
      local ok, res = coroutine.resume(buildCo)
      if coroutine.status(buildCo) == "dead" then
        if ok and res then scene = res else
          Sc.failed, Sc.why = true, "the den did not build (" .. tostring(res) .. ")"
          if mod.log then mod.log:warn("Galar Rising: %s; drawn flat", Sc.why) end
        end
        buildCo = nil
        warmStep = 3
      end
      return false
    end
    warmStep = warmStep + 1
    pcall(function()
      if warmStep == 1 then dirtTex()
      elseif warmStep == 2 then cragImg()
      elseif warmStep == 3 then Sc.scene()
      elseif warmStep == 4 then
        if not auroraShader and not auroraFailed then
          local ok, sh = pcall(G2.newShader, AURORA_SHADER)
          if ok then auroraShader = sh else auroraFailed = true end
        end
        if not portalShader and not portalFailed then
          local ok, sh = pcall(G2.newShader, PORTAL_SHADER)
          if ok then portalShader = sh; Sc._portalInit(G2) else portalFailed = true end
        end
        motesBuild(G2)
      end
    end)
    return warmStep >= 4
  end

  function Sc.warmAll()
    for _ = 1, 200 do if Sc.warm() then return true end end
    return false
  end

  return Sc
end
