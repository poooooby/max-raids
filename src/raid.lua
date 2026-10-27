-- A Max Raid (Sword / Shield's Max Raid Battles, on the Gen 3 games): a giant Gigantamax boss from
-- the Giga Megas pack (data/raid_bosses.lua over data/raid_sprites.lua, baked by tools/raid_pack.py)
-- against four of the party, in the 3D den (src/raid_scene.lua) on a layer of its own over the
-- field (src/layer.lua), drawn at the window's resolution.
--
-- This file is the raid's controller: the boss's pictures and cry (one boss in memory at a time,
-- released when the raid closes), the four who fight (copies of the party's Pokemon; their back
-- pictures fetched in the update step - an animated sprite mod redraws them into a canvas, which
-- must never happen inside a draw), the intro, the HUD and the battle pad.
--   Rd = raid(mod, { N, Bosses, Sprites, Scene, Pad, HD, padOnSecond, onOpen, onClose })
--   Rd.open(key) ; Rd.close() ; Rd.active() ; Rd.update(dt) ; Rd.input(input) ; Rd.pointer(ev)
--   Rd.draw(G, w, h) ; Rd.state()

return function(mod, deps)
  local N, Bosses, Sprites, Scene, Pad = deps.N, deps.Bosses, deps.Sprites, deps.Scene, deps.Pad
  local BattlerHud = deps.BattlerHud
  local Rewards = deps.Rewards
  local Fx, MoveFx = deps.Fx, deps.MoveFx
  local Sounds = deps.Sounds
  local Battle, Sim = deps.Battle, deps.Sim
  local R = N.RAID
  local floor, max, min = math.floor, math.max, math.min
  local sin, cos, pi, sqrt = math.sin, math.cos, math.pi, math.sqrt

  local Rd = { N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene, Fx = Fx }
  -- an animation frame lasts AnimationSpeed of these (the pack's metrics, Essentials' units)
  Rd.ANIM_UNIT_S = 1 / 20

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local Pokemon = engine("src.core.game3.pokemon")
  local Runtime = engine("src.core.game3.runtime")
  local Audio = engine("src.core.game3.audio")
  local Summary = engine("src.core.game3.summary_data")

  local function drawPixel(...)
    local HD = deps.HD
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  Rd.drawPixel = drawPixel

  -- ------- the bosses

  function Rd.boss(key)
    local b, sp = Bosses[key], Sprites[key]
    if type(b) ~= "table" or type(sp) ~= "table" then return nil end
    return b, sp
  end

  -- the boss's size against a member's: by its height (data/raid_rules.lua SIZE)
  function Rd.sizeOf(key)
    local sp = Sprites[key]
    local S = R.SIZE
    local u = ((sp and sp.height or S.H0) - S.H0) / (S.H1 - S.H0)
    return S.MIN + (S.MAX - S.MIN) * max(0, min(1, u))
  end

  -- a picture of the mod's: the Image, and (keep = true) its ImageData too, for measuring
  local function imageOf(path, keep)
    if not (love and love.graphics and mod.read) then return nil end
    local data
    local ok, img = pcall(function()
      local bytes = mod:read(path)
      if not bytes then return nil end
      data = love.image.newImageData(love.filesystem.newFileData(bytes, path:match("[^/]+$")))
      local i = love.graphics.newImage(data)
      i:setFilter("nearest", "nearest")
      return i
    end)
    if not ok then mod.log:warn("raid picture %s failed to load: %s", path, tostring(img)) end
    if not keep and data then pcall(data.release, data) end
    return ok and img or nil, keep and data or nil
  end
  Rd.imageOf = imageOf

  -- the opaque part of a w x h region of image data at (x, y): x0, y0, x1, y1 in the region
  local function boxOf(data, x, y, w, h)
    local x0, y0, x1, y1 = w, h, -1, -1
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        local _, _, _, a = data:getPixel(x + xx, y + yy)
        if a > 0.1 then
          if xx < x0 then x0 = xx end
          if xx > x1 then x1 = xx end
          if yy < y0 then y0 = yy end
          if yy > y1 then y1 = yy end
        end
      end
    end
    if x1 < x0 then return { 0, 0, w, h } end
    return { x0, y0, x1 + 1, y1 + 1 }
  end
  Rd.boxOf = boxOf

  -- the loaded boss: { key, sheet, quads, cell, box, sp, b, cry }
  local loaded = nil
  function Rd.release()
    if not loaded then return end
    if loaded.sheet and loaded.sheet.release then pcall(loaded.sheet.release, loaded.sheet) end
    if loaded.cry and loaded.cry.release then pcall(loaded.cry.release, loaded.cry) end
    loaded = nil
  end
  function Rd.load(key, shiny)
    if loaded and loaded.key == key and loaded.shiny == (shiny == true) then return loaded end
    Rd.release()
    local b, sp = Rd.boss(key)
    if not b then return nil end
    local sheet, data = imageOf("assets/bosses/" .. key .. ((shiny and sp.shiny) and "_shiny" or "") .. ".png", true)
    if not sheet then return nil end
    -- its feet and width from the first frame (the pad stands it there)
    local box = data and boxOf(data, 0, 0, sp.cell, sp.cell) or { 0, 0, sp.cell, sp.cell }
    if data then pcall(data.release, data) end
    local quads = {}
    local sw, sh = sheet:getDimensions()
    for i = 1, sp.frames do
      local c, r0 = (i - 1) % sp.cols, floor((i - 1) / sp.cols)
      quads[i] = love.graphics.newQuad(c * sp.cell, r0 * sp.cell, sp.cell, sp.cell, sw, sh)
    end
    loaded = { key = key, shiny = shiny == true, sheet = sheet, quads = quads, cell = sp.cell, sp = sp, b = b, box = box }
    return loaded
  end
  function Rd.loadedKey() return loaded and loaded.key or nil end

  -- the frame shown at time t (seconds): image, quad, cell
  function Rd.frameAt(key, t)
    local L = Rd.load(key)
    if not L then return nil end
    local unit = (L.sp.speed and L.sp.speed[1] or 2) * Rd.ANIM_UNIT_S
    local i = floor((t or 0) / unit) % #L.quads + 1
    return L.sheet, L.quads[i], L.cell
  end

  -- the effects volume the game is set to (0..1)
  local function sfxGain()
    if Audio and type(Audio._sfxVolume) == "number" then return Audio._sfxVolume end
    return 1
  end

  -- the boss's cry: the pack's .ogg, at the game's effects volume
  function Rd.cry(key)
    local L = Rd.load(key)
    if not (L and L.sp.cry and love and love.audio and love.sound) then return false end
    if not L.cry then
      local ok, sd = pcall(function()
        local bytes = mod:read("assets/bosses/cries/" .. key .. ".ogg")
        return bytes and love.sound.newSoundData(love.filesystem.newFileData(bytes, key .. ".ogg"))
      end)
      if not (ok and sd) then return false end
      L.cry = sd
    end
    local g = sfxGain()
    if g <= 0 then return true end
    local ok, src = pcall(love.audio.newSource, L.cry, "static")
    if not ok then return false end
    pcall(src.setVolume, src, min(1, g))
    pcall(src.play, src)
    return true
  end

  -- ------- the four who fight

  local function party()
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    return s and s.party or {}
  end
  local function isEgg(mon)
    if Pokemon and Pokemon.isEgg then
      local ok, egg = pcall(Pokemon.isEgg, mon)
      if ok then return egg == true end
    end
    return type(mon) == "table" and mon.isEgg == true
  end

  -- the first four of the party that are not eggs (the den screen will let the player pick)
  function Rd.lineup()
    local out = {}
    for _, mon in ipairs(party()) do
      if #out >= 4 then break end
      if not isEgg(mon) then out[#out + 1] = { mon = mon } end
    end
    return out
  end

  -- a member's back picture now (an animated sprite mod answers each call with the moment's
  -- frame, redrawing it into a canvas: so only from the update step)
  local function backPicOf(mon)
    if not Pokemon then return nil end
    local fn = Pokemon.monBackPic or Pokemon.backPic
    local ok, pic = pcall(fn, mon)
    if ok and type(pic) == "table" and pic.image then return pic end
    ok, pic = pcall(Pokemon.monFrontPic or Pokemon.frontPic, mon)
    if ok and type(pic) == "table" and pic.image then return pic end
    return nil
  end

  -- the opaque box of a picture, read back through a canvas (update step only), in its own units
  local function opaqueBox(image, quad)
    local G = love.graphics
    local iw, ih = image:getDimensions()
    local qx, qy, qw, qh = 0, 0, iw, ih
    if quad then qx, qy, qw, qh = quad:getViewport() end
    local ok, data = pcall(function()
      local c = G.newCanvas(qw, qh, { dpiscale = 1 })
      G.push("all")
      G.setCanvas(c)
      G.origin()
      G.setShader()
      G.setBlendMode("alpha")
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      if quad then G.draw(image, quad, 0, 0) else G.draw(image, 0, 0) end
      G.pop()
      local d = c:newImageData()
      c:release()
      return d
    end)
    if not (ok and data) then return { 0, 0, qw, qh } end
    local pw, ph = data:getDimensions()
    local b = boxOf(data, 0, 0, pw, ph)
    data:release()
    local kx, ky = qw / pw, qh / ph
    return { b[1] * kx, b[2] * ky, b[3] * kx, b[4] * ky }
  end

  -- each member's picture as the den draws it, refreshed in the update step:
  -- { image, quad, box, cell } (box in the quad's units; cell the pic's height, 64)
  -- what the HUD shows of a member (the update step): name, level, HP, gender, EXP share, icon
  local function memberInfo(m)
    local mon = m.mon
    local info = m.info or {}
    m.info = info
    if not info.name then
      local name = "?"
      if Pokemon and Pokemon.displayName then
        local ok, n = pcall(Pokemon.displayName, mon)
        if ok and type(n) == "string" then name = n end
      end
      info.name = name
      if Summary and Summary.gender then
        local ok, g = pcall(Summary.gender, mon)
        info.gender = ok and g or ""
      end
      if Pokemon and Pokemon.monIcon then
        local ok, ic = pcall(Pokemon.monIcon, mon)
        if ok and type(ic) == "table" then info.icon = ic end
      end
    end
    info.level = tonumber(mon.level) or 1
    info.maxHp = tonumber(mon.maxHp) or 0
    info.hp = m.b and floor((m.b.dispHp or 0) + 0.5) or (tonumber(mon.hp) or 0)
    info.exp = 0
    if Summary and Summary.expProgress then
      local okG, gr = pcall(function() return Pokemon.growthRate(Pokemon.speciesOf(mon)) end)
      local ok, e = pcall(Summary.expProgress, mon, okG and gr or nil)
      if ok and type(e) == "table" then info.exp = tonumber(e.progressPercent) or 0 end
    end
  end
  Rd.memberInfo = memberInfo

  local function memberPics(r)
    for _, m in ipairs(r.members) do
      memberInfo(m)
      local pic = backPicOf(m.mon)
      if pic then
        local img = pic.image
        local w, h = pic.w or 64, pic.h or 64
        m.draw = m.draw or {}
        local d = m.draw
        d.image = img
        if not d.quad or d.qw ~= w or d.qh ~= h or d.src ~= img then
          d.quad = love.graphics.newQuad(0, 0, w, h, img:getDimensions())
          d.qw, d.qh, d.src = w, h, img
        end
        d.cell = h
        if not d.box then d.box = opaqueBox(img, d.quad) end
      end
    end
  end

  -- ------- open and close

  local r = nil
  function Rd.active() return r ~= nil end
  function Rd.current() return r end

  -- the boss's music: the first of these the game has
  Rd.SONGS = { "MUS_VS_RAYQUAZA", "MUS_VS_MEWTWO", "MUS_VS_REGI", "MUS_VS_LEGEND", "MUS_RG_VS_LEGEND", "MUS_VS_CHAMPION" }
  local function playSong(names)
    if not (Audio and Audio.songs) then return nil end
    local ok, songs = pcall(Audio.songs)
    if not (ok and type(songs) == "table") then return nil end
    for _, name in ipairs(names) do
      local id = songs[name]
      if id then
        if Audio.fadeOutAndPlay then pcall(Audio.fadeOutAndPlay, id) elseif Audio.playSong then pcall(Audio.playSong, id) end
        return name
      end
    end
    return nil
  end

  -- the battle: the four as copies (src/battle.lua), the boss at its tier, the turns (src/raid_sim.lua);
  -- each member's `b` is its battler and its `mon` the copy from then on (the HUD and the summary
  -- show the raid's HP, never the save's)
  local function setupBattle(members)
    if not (Battle and Sim) then return end
    local gen = love and love.math and love.math.newRandomGenerator(os.time())
    local rng = function(lo, hi) return gen and gen:random(lo, hi) or math.random(lo, hi) end
    r.rng = rng
    r.boss = Battle.boss(r.key, rng)
    local list = {}
    for i, m in ipairs(members) do
      m.orig = m.mon
      m.b = Battle.member(m.mon)
      m.mon = m.b.mon
      m.b.dispHp, m.b.dispTarget = tonumber(m.mon.hp) or 0, tonumber(m.mon.hp) or 0
      list[i] = m.b
    end
    if not r.boss then return end
    r.boss.dispHp, r.boss.dispTarget = r.boss.mon.hp, r.boss.mon.hp
    r.adapter = Battle.adapter(rng)
    r.sim = Sim.new{ boss = r.boss, members = list, adapter = r.adapter, rng = rng, rules = R,
      words = deps.Gmax and deps.Gmax.WORDS or nil }
  end

  -- the raid itself begins: the intro from the close-up on the party
  local function begin(members)
    r.phase, r.t, r.members, r.cues, r.hud = "intro", 0, members, {}, 0
    r.say = nil
    setupBattle(members)
    if Scene then
      Scene.setTime(0)
      Scene.shot("close", 0)
    end
    r.song = playSong(Rd.SONGS)
  end

  -- straight into a raid (drivers, tests): no den screen
  function Rd.open(key, opts)
    if r then return false, "busy" end
    if not Rd.boss(key) then return false, "unknown boss" end
    if not Rd.load(key) then return false, "no pictures" end
    r = { key = key, den = opts and opts.den }
    if Fx then Fx.clear() end
    begin((opts and opts.members) or Rd.lineup())
    if deps.onOpen then deps.onOpen(r) end
    return true
  end

  -- ------- the den screen: what a den holds today, and the four who go in

  -- the party as the den screen lists it (eggs left out): { mon, name, level }
  local function roster()
    local out = {}
    for _, mon in ipairs(party()) do
      if not isEgg(mon) then
        local name = "?"
        if Pokemon and Pokemon.displayName then
          local ok, n = pcall(Pokemon.displayName, mon)
          if ok and type(n) == "string" then name = n end
        end
        out[#out + 1] = { mon = mon, name = name, level = tonumber(mon.level) or 1 }
      end
    end
    return out
  end

  -- the den screen takes no presses for this long after it opens
  Rd.DEN_ARM_S = 0.25

  function Rd.openDen(den)
    if r then return false, "busy" end
    if type(den) ~= "table" then return false, "no den" end
    local list = roster()
    r = { phase = "den", den = den, key = den.active and not den.done and den.boss or nil, t = 0,
      party = list, picked = {}, cursor = 1, cues = {}, hud = 0 }
    for i = 1, min(4, #list) do r.picked[i] = true end
    if r.key and not Rd.load(r.key) then r.key = nil end
    if deps.onOpen then deps.onOpen(r) end
    return true
  end

  local function pickedCount()
    local n = 0
    for _, on in pairs(r.picked) do if on then n = n + 1 end end
    return n
  end

  -- a party row toggled in or out (at most four)
  function Rd.denToggle(i)
    if not (r and r.phase == "den" and r.party[i]) then return false end
    if r.picked[i] then r.picked[i] = nil
    elseif pickedCount() < 4 then r.picked[i] = true
    else return false end
    return true
  end

  -- from the den screen into the raid with the four picked (party order)
  function Rd.denStart()
    if not (r and r.phase == "den" and r.key) then return false end
    local members = {}
    for i, row in ipairs(r.party) do
      if r.picked[i] and #members < 4 then members[#members + 1] = { mon = row.mon } end
    end
    if #members == 0 then return false end
    begin(members)
    return true
  end

  function Rd.close()
    if not r then return false end
    r = nil
    if Fx then Fx.clear() end
    Rd.release()
    if Audio then
      if Audio.restoreMapSong then pcall(Audio.restoreMapSong)
      elseif Audio.changeMusicToDefault then pcall(Audio.changeMusicToDefault) end
    end
    if deps.onClose then deps.onClose() end
    return true
  end

  function Rd.flee() return Rd.close() end

  -- ------- the intro (Sword / Shield's raid opening, with the party where the trainers stand):
  -- close on the party, then the camera pulls back and down to the ground and tilts up the boss's
  -- whole height; it roars (its cry, a burst of energy, a shake), "X appeared!", the HUD comes in,
  -- and the camera swings over the first member's shoulder for its command (seconds from opening)

  Rd.INTRO = { REVEAL_AT = 1.3, REVEAL_S = 2.4, ROAR_AT = 3.6, SAY_AT = 4.0, HUD_S = 0.5,
    MEMBER_AT = 6.0, MEMBER_S = 1.2, DONE = 7.2 }
  local function once(name, at)
    if r.cues[name] or r.t < at then return false end
    r.cues[name] = true
    return true
  end
  function Rd.say(text) if r then r.say, r.sayT = text, r.t end end

  function Rd.update(dt)
    if not r then return end
    dt = min(0.1, dt or 0)
    -- a blow's hit-stop: the raid's clock all but held for a moment (real time)
    if (r.hitStop or 0) > 0 then
      r.hitStop = r.hitStop - dt
      dt = dt * 0.06
    end
    r.t = r.t + dt
    -- the den screen: no den in 3D yet
    if r.phase == "den" then return end
    if Scene then Scene.setTime(r.t) end
    if r.phase == "intro" then
      local I = Rd.INTRO
      if once("reveal", I.REVEAL_AT) and Scene then Scene.shot("reveal", I.REVEAL_S) end
      if once("roar", I.ROAR_AT) then
        Rd.cry(r.key)
        if Scene then Scene.burst(); Scene.shake(0.22, 1.0) end
      end
      if once("say", I.SAY_AT) then
        local b = Bosses[r.key]
        Rd.say((b and b.name or "The boss") .. " appeared!")
      end
      if r.cues.say then r.hud = min(1, r.hud + dt / I.HUD_S) end
      if once("member", I.MEMBER_AT) and Scene then Scene.shot("member", I.MEMBER_S, 1) end
      if r.t >= I.DONE then
        r.say = nil
        Rd.startCommand(true)
      end
    end
    if r.phase == "battle" then Rd.playEvents() end
    if r.phase == "outro" then
      local O = Rd.OUTRO
      if r.t >= r.outroT + O.HOLD + O.CLOSE + O.BLACK then
        r.irisDone = true
        Rd.startAfter()
        if not r then return end
      end
    end
    if r and r.phase == "throw" and Rd.stepThrow then Rd.stepThrow() end
    if r and Rd.stepMove then Rd.stepMove() end
    if r and Fx then Fx.update(r.t) end
    if not r then return end
    -- the HP bars drain (or fill) toward what the events have shown so far
    local function ease(b)
      if not (b and b.dispHp) then return end
      local step = max(1, tonumber(b.mon.maxHp) or 1) * dt / Rd.EVENT.HP_S
      local d = (b.dispTarget or 0) - b.dispHp
      if math.abs(d) <= step then b.dispHp = b.dispTarget else b.dispHp = b.dispHp + (d > 0 and step or -step) end
    end
    ease(r.boss)
    for _, m in ipairs(r.members) do ease(m.b) end
    if r.boss and r.boss.dispHp then r.hpShown = r.boss.dispHp / max(1, r.boss.mon.maxHp) end
    -- the boss's block: always outside the turn; in it, while the words are about the boss
    local want = (r.phase ~= "battle" or r.bossShow) and 1 or 0
    local cur = r.bossA or 1
    r.bossA = cur + max(-1, min(1, (want - cur) * 1)) * min(1, dt * Rd.EVENT.FADE)
    if r.phase == "command" and r.cmd then
      if r.cmd.menu ~= "main" then Rd.moveList() elseif Rd.bagEmpty then r.cmd.bagEmpty = Rd.bagEmpty() end
    end
    -- the members' pictures and the den's render: here, outside any draw
    memberPics(r)
    if Scene and Scene.prepare then Scene.prepare(r.t) end
  end

  -- ------- the commands: each member in turn (the order list down the top left) picks from the pad;
  -- once all have, the turn is fought. B steps back to the one before, undoing its pick.

  Rd.SWAP_S = 0.6     -- the camera to the next member's shoulder
  local function canAct(i)
    if r.sim then return r.sim:canAct(i) end
    local m = r.members[i]
    return m ~= nil and (tonumber(m.mon and m.mon.hp) or 1) > 0
  end
  local function nextActor(from)
    for i = from, #r.members do
      if canAct(i) and r.cmd.chosen[i] == nil then return i end
    end
    return nil
  end
  local function toMember(i, cut)
    if Scene and i then Scene.shot("member", cut and 0 or Rd.SWAP_S, i) end
  end

  -- a new turn's commands (fresh: the intro has the camera there already)
  function Rd.startCommand(fresh)
    if not r then return false end
    r.turn = (r.turn or 0) + 1
    r.phase = "command"
    r.cmd = { chosen = {}, cursor = 1, menu = "main" }
    if r.sim and not r.sim.field then r.fieldShown = nil end
    if r.boss then
      local sh = r.boss.shield
      r.boss.shieldShown = sh and sh.left > 0 and { left = sh.left, max = sh.max } or nil
    end
    r.cmd.actor = nextActor(1)
    r.say = nil
    -- (no one able to choose - all sitting out: the boss's turn alone)
    if not r.cmd.actor then return Rd.fight() end
    if not fresh then toMember(r.cmd.actor) end
    return true
  end

  function Rd.cursorTo(i)
    if not (r and r.phase == "command" and Pad and Pad.ITEMS[i]) then return false end
    r.cmd.cursor = i
    return true
  end

  -- the game's own summary of the member choosing (L / R through the four), over the raid; read
  -- only (context "factory": no moves swapped). The raid stands aside until it closes.
  function Rd.summary()
    if not (r and r.phase == "command" and r.cmd.actor) or r.summary then return false end
    local SummaryMenu = engine("src.ui.game3.summary_menu")
    if not (SummaryMenu and SummaryMenu.openMenu) then return false end
    local mons = {}
    for i, m in ipairs(r.members) do mons[i] = m.mon end
    local raid = r
    raid.summary = true
    local ok, err = pcall(SummaryMenu.openMenu, mons, r.cmd.actor, {
      context = "factory",
      -- (the press that closed it is not the raid's: one input step skipped)
      onClose = function() raid.summary, raid.skipInput = false, true end,
    })
    if not ok then
      raid.summary = false
      mod.log:warn("the summary could not open: %s", tostring(err))
      return false
    end
    return true
  end
  function Rd.summaryUp() return r ~= nil and (r.summary == true or r.aside == true) end

  -- the pouch's items in the Bag's order, and how many of each are left once this turn's picks
  -- are taken out
  Rd.POUCH_ORDER = { "potion", "full_heal", "revive" }
  local function pouchFree(id)
    local n = r.sim and r.sim:pouchLeft(id) or 0
    for _, c in pairs(r.cmd and r.cmd.chosen or {}) do if c.item == id then n = n - 1 end end
    return n
  end
  local function bagEmpty()
    for _, id in ipairs(Rd.POUCH_ORDER) do if pouchFree(id) > 0 then return false end end
    return true
  end

  Rd.bagEmpty = bagEmpty

  -- whether a pouch item can go on member j now: a Revive on one sitting out, the others on one on
  -- the field
  local function canTake(id, j)
    local m = r.members[j]
    if not (m and m.b and r.sim) then return false end
    if id == "revive" then return (m.b.down or 0) > 0 end
    return r.sim:present(j)
  end

  -- the next member's turn, or the fight
  local function nextOrFight()
    local c = r.cmd
    local nxt = nextActor(c.actor + 1)
    c.cursor, c.menu, c.item = 1, "main", nil
    if nxt then
      c.actor = nxt
      toMember(nxt)
    else
      c.actor = nil
      Rd.fight()
    end
  end

  -- the member choosing now picks: Run leaves; Pokemon shows its summary; Fight its moves; Bag the
  -- pouch, then whom to use it on. In a list menu "moveN" is its N-th row.
  function Rd.choose(id)
    if not (r and r.phase == "command" and r.cmd.actor) or r.summary then return false end
    if id == "run" then return Rd.flee() end
    if id == "pokemon" then return Rd.summary() end
    local c = r.cmd
    if id == "fight" then
      c.menu, c.cursor = "moves", 1
      Rd.moveList()
      return true
    end
    if id == "bag" then
      if bagEmpty() then return false end
      c.menu, c.cursor = "items", 1
      Rd.moveList()
      return true
    end
    if id == "back" then return Rd.back() end
    local slot = type(id) == "string" and tonumber(id:match("^move(%d)$"))
    if not slot then return false end
    local row = c.moveList and c.moveList[slot]
    if not row or row.live == false then return false end
    if c.menu == "items" then
      c.item, c.menu, c.cursor = row.id, "target", 1
      Rd.moveList()
      return true
    elseif c.menu == "target" then
      c.chosen[c.actor] = { item = c.item, target = row.member }
      nextOrFight()
      return true
    end
    local b = r.members[c.actor] and r.members[c.actor].b
    local mv = b and b.moves[slot]
    if not mv or (mv.pp or 0) <= 0 then return false end
    c.chosen[c.actor] = { move = slot }
    nextOrFight()
    return true
  end

  -- the list menu's rows for the member choosing (the update step: effectiveness asks the engine):
  -- its moves, the pouch's items, or the four to use one on
  local function effOf(m)
    if m == 0 then return "none" elseif m > 1 then return "super" elseif m < 1 then return "weak" end
    return nil
  end
  local function hpRgb(share)
    if share > 0.5 then return { 0.2, 0.75, 0.3 } elseif share > 0.2 then return { 0.9, 0.7, 0.1 } end
    return { 0.9, 0.25, 0.2 }
  end
  function Rd.moveList()
    local c = r and r.cmd
    local b = c and c.actor and r.members[c.actor] and r.members[c.actor].b
    if not b then return end
    c.bagEmpty = bagEmpty()
    c.moveList = c.moveList or {}
    local list = c.moveList
    for i = 1, 4 do
      local row = list[i] or {}
      for k in pairs(row) do row[k] = nil end
      list[i] = row
      if c.menu == "items" then
        local id = Rd.POUCH_ORDER[i]
        if id then
          local n = pouchFree(id)
          row.id, row.name, row.chip, row.right = id, Sim and Sim.ITEM_NAME[id] or id, "Item", "x" .. n
          row.rgb, row.live = { 0.35, 0.6, 0.85 }, n > 0
        else
          list[i] = nil
        end
      elseif c.menu == "target" then
        local m = r.members[i]
        if m and m.b then
          local hp, mhp = tonumber(m.b.mon.hp) or 0, max(1, tonumber(m.b.mon.maxHp) or 1)
          row.member, row.name = i, m.b.name
          row.chip, row.right = (m.b.down or 0) > 0 and "Out" or "HP", ("%d/%d"):format(hp, mhp)
          row.rgb, row.live = hpRgb(hp / mhp), canTake(c.item, i)
        else
          list[i] = nil
        end
      else
        local mv = b.moves[i]
        if mv then
          row.name, row.typeName, row.pp, row.maxPp = mv.name, mv.typeName, mv.pp, mv.maxPp
          row.rgb = Battle and Battle.TYPE_RGB[mv.typeName] or nil
          if not mv.status and r.adapter and r.boss then row.eff = effOf(r.adapter.effectiveness(mv.type, r.boss)) end
        else
          list[i] = nil
        end
      end
    end
  end

  -- ------- the turn: the simulation runs it at once; its events then play one by one - the words
  -- typed in the band, the camera on whoever moves, the bars draining as each hit lands

  Rd.EVENT = { HOLD_S = 0.7, DAMAGE_S = 0.65, HP_S = 0.6, CAM_S = 0.5, FADE = 10 }
  local function memberIndex(b)
    for i, m in ipairs(r.members) do if m.b == b then return i end end
    return nil
  end

  function Rd.fight()
    if not (r and r.sim) then return false end
    local choices = {}
    for i, c in pairs(r.cmd and r.cmd.chosen or {}) do choices[i] = c end
    r.actions = {}
    for i, c in pairs(choices) do
      r.actions[i] = BattlerHud and BattlerHud.actionOf(r.members[i], c) or "fight"
    end
    r.events = r.sim:turn(choices)
    r.evI, r.evT, r.evDur = 0, r.t, 0
    r.bossShow, r.rows = false, {}
    r.phase = "battle"
    return true
  end

  -- what the words are about, as the game shows it: the boss's block for the boss (its moves, a hit
  -- on it, its status), else the member's row at the top left (its action, its HP); a member's move
  -- at the boss is about the boss, one on itself about the member. "fail" keeps what was shown.
  local function aboutOf(e)
    if e.kind == "fail" then return nil end
    if e.kind == "over" then return r.boss end
    if e.kind == "use" then
      if e.who.boss then return r.boss end
      local mv = e.move
      if mv and mv.status and mv.side and mv.side.self then return e.who end
      return r.boss
    end
    return e.target or e.who
  end
  local function showFor(e)
    local about = aboutOf(e)
    if not about then return end
    if about.boss then
      r.bossShow, r.rows = true, {}
    else
      local i = memberIndex(about)
      if e.kind == "damage" and not r.bossShow and r.rows then
        for _, row in ipairs(r.rows) do if row[1] == i then return end end
      end
      r.bossShow = false
      r.rows = i and { { i, r.members[i], kind = r.actions and r.actions[i] or "fight" } } or {}
    end
  end

  -- ------- a move acted out (src/fx.lua, data/raid_move_fx.lua): after its words, the band steps aside
  -- and its look plays from the user to whoever it falls on; its hit lands at the impact. A G-Max
  -- move charges first (the boss's cry, the roar's burst, red energy streaking in). The boss lunges
  -- for its strikes.

  Rd.GMAX_CHARGE_S = 1.5
  local LUNGE = { slam = true, multi = true, bite = true, slash = true }

  -- a battler's place in the den (src/fx.lua's anchor): its middle, height and ground, in metres
  local function placeOf(b)
    if not (Scene and Scene.PAD) then return nil end
    if b.boss then
      local P = Scene.PAD
      local h = Scene.MEMBER_H * (Rd.sizeOf(r.key) or 3.5)
      return { X = P.x, Y = P.h + h * 0.5, Z = P.z, h = h, foot = P.h, boss = true }
    end
    local i = memberIndex(b)
    local m = i and Scene.MEMBERS[i]
    if not m then return nil end
    return { X = m.x, Y = Scene.MEMBER_H * 0.5, Z = m.z, h = Scene.MEMBER_H, foot = 0, i = i }
  end
  Rd.placeOf = placeOf

  -- a sound by its SE name (data/raid_sounds.lua), through the game's own player
  function Rd.se(id)
    if not (id and Audio and Audio.playSe) then return false end
    local ok, played = pcall(Audio.playSe, id)
    return ok and played
  end

  -- a blow felt (Fx.onImpact): the raid's clock held a moment, the camera jabbed and shaken, the one
  -- struck flashing white and thrown back - all by the blow's power (0..1+, from the HP it takes)
  Rd.IMPACT = { STOP_S = 0.045, STOP_PER = 0.09, KICK = 1.5, KICK_PER = 4.5, SHAKE = 0.04, SHAKE_PER = 0.2 }
  function Rd.impact(T, power, key)
    if not r then return end
    local I = Rd.IMPACT
    local p = power or 0.5
    r.lastImpact = r.t
    -- its sound: what lands hard, once a move; the hit by how it does, once a moment (a spread move
    -- lands on all four together)
    if Sounds then
      if key and Sounds.LAND[key] and r.landSeAt ~= r.anim then
        r.landSeAt = r.anim
        Rd.se(Sounds.LAND[key])
      end
      if T.frac and (r.hitSeT or -1) + 0.05 < r.t then
        r.hitSeT = r.t
        local eff = T.eff or 1
        Rd.se(eff > 1 and Sounds.HIT.super or eff < 1 and Sounds.HIT.weak or Sounds.HIT.plain)
      end
    end
    -- its bar drains now, as the blow lands: the boss's block, or the members' cards at the top left
    -- (all the move hits, together)
    if T.b and T.hp then
      T.b.dispTarget = T.hp
      if T.b.boss then
        r.bossShow = true
      else
        local i = memberIndex(T.b)
        if i then
          if r.bossShow then r.bossShow, r.rows = false, {} end
          r.rows = r.rows or {}
          local have = false
          for _, row in ipairs(r.rows) do if row[1] == i then have = true end end
          if not have then r.rows[#r.rows + 1] = { i, r.members[i], kind = r.actions and r.actions[i] or "fight" } end
          table.sort(r.rows, function(x, y) return x[1] < y[1] end)
        end
      end
    end
    if not T.frac then
      -- (it missed, or did no harm: a small jolt only)
      if Scene then Scene.shake(I.SHAKE * 0.5, 0.2) end
      return
    end
    r.hitStop = max(r.hitStop or 0, I.STOP_S + I.STOP_PER * min(1, p))
    if Scene then
      if Scene.kick then Scene.kick(I.KICK + I.KICK_PER * min(1, p), 0.25 + 0.2 * p) end
      Scene.shake(I.SHAKE + I.SHAKE_PER * p, 0.3 + 0.35 * p)
      if Scene.hit then Scene.hit(T.boss and "boss" or T.i, min(1, p)) end
    end
  end
  if Fx then Fx.onImpact = function(T, power, _, _, key) Rd.impact(T, power, key) end end
  if Fx and Scene then
    Scene.onBack = function(G2) if r and r.phase ~= "rewards" then Fx.drawLayer(G2, "back", r.t) end end
    Scene.onMid = function(G2) if r and r.phase ~= "rewards" then Fx.drawLayer(G2, "mid", r.t) end end
  end

  function Rd.specOf(mv)
    if not (MoveFx and mv) then return { "slam" } end
    if mv.isGmax then return MoveFx.GMAX[mv.key or ""] or { "wave", shape = "light" } end
    return MoveFx.MOVES[mv.key or ""] or MoveFx.DEFAULT[mv.typeName or "NORMAL"] or { "slam" }
  end

  -- at a use: whom it falls on (the events up to the next move), when its look starts
  function Rd.scheduleMove(e)
    if not Fx then return end
    local mv = e.move
    local spec = Rd.specOf(mv)
    local targets = {}
    if spec[1] ~= "self" then
      local list = r.events or {}
      local seen = {}
      for j = r.evI + 1, #list do
        local x = list[j]
        if x.kind == "use" or x.kind == "over" or x.kind == "cheer" or x.kind == "item" then break end
        local who = x.target or ((x.kind == "status" or x.kind == "stage") and x.who ~= e.who and x.who) or nil
        if who and not seen[who] then seen[who] = { b = who }; targets[#targets + 1] = seen[who] end
        -- (how hard it lands on each: the share of its HP the move takes)
        -- (its hits are felt in its look: their own events make no second sound or shake)
        if x.kind == "damage" and spec[1] ~= "self" then x.looked = true end
        if who and x.kind == "damage" and x.amount then
          local most = max(1, tonumber(who.mon and who.mon.maxHp) or 1)
          seen[who].frac = (seen[who].frac or 0) + x.amount / most
          seen[who].hp = x.hp
        end
        if who and x.kind == "effect" and x.eff then seen[who].eff = x.eff end
      end
    end
    local words = #(e.text or "") / Rd.MSG.CPS + 0.25
    local gmax = mv and mv.isGmax
    local at = r.t + words + (gmax and Rd.GMAX_CHARGE_S or 0)
    local K = Fx.KIND[(spec[1] == "drop" and spec.shape == "slab") and "slab" or spec[1]] or Fx.KIND.slam
    local len = K[1] * (gmax and Fx.GMAX_K or 1)
    if spec[1] == "multi" then len = K[1] * (spec.n or 3) + 0.2 end
    r.anim = { at = at, spec = spec, user = e.who, targets = targets, type = mv and mv.typeName or "NORMAL",
      gmax = gmax, chargeAt = gmax and (r.t + words) or nil, len = len,
      impact = K[2] and K[2] * (gmax and Fx.GMAX_K or 1) or len }
  end

  -- each frame: the G-Max charge, the look's start, the boss's lunge
  function Rd.stepMove()
    local a = r.anim
    if not a then r.lunge = 0; return end
    if a.chargeAt and not a.charged and r.t >= a.chargeAt then
      a.charged = true
      r.say = nil
      local LB = Scene and Scene.lastBoss
      if Scene then Scene.shot("boss", 0.5); Scene.burst(); Scene.shake(0.2, 1.0) end
      Rd.cry(r.key)
      if Sounds then Rd.se(Sounds.GMAX_CHARGE) end
      local _ = LB
      Fx.charge(placeOf(a.user), r.t, Rd.GMAX_CHARGE_S)
    end
    if not a.started and r.t >= a.at then
      a.started = true
      r.say = nil
      -- (a G-Max move: back to whom it falls on for the blow)
      if a.gmax and Scene then
        if #a.targets > 1 then Scene.shot("spread", 0.3)
        elseif a.targets[1] and memberIndex(a.targets[1].b) then Scene.shot("target", 0.3, memberIndex(a.targets[1].b)) end
      end
      local from = placeOf(a.user)
      local tg = {}
      for _, t in ipairs(a.targets) do
        local p = placeOf(t.b)
        if p then p.frac, p.hp, p.b, p.eff = t.frac, t.hp, t.b, t.eff; tg[#tg + 1] = p end
      end
      if from then Fx.move(a.spec, a.type, from, tg, r.t, a.gmax) end
      if Sounds then Rd.se(Sounds.moveSe(a.spec, a.type)) end
    end
    -- the boss rears and lunges into its strikes
    r.lunge = 0
    if a.started and a.user.boss and LUNGE[a.spec[1]] then
      local u = (r.t - a.at) / math.max(0.1, a.impact)
      if u >= 0 and u <= 1.4 then r.lunge = math.sin(math.min(1, u) * math.pi) end
    end
    if r.t > a.at + a.len + 0.2 then r.anim = nil end
  end

  -- (drivers) a look played now, outside any turn: spec (a table, or a move's key), the user (the boss,
  -- or a member's place), whom it falls on (members' places, or "boss"), frac (the HP each loses)
  function Rd.testLook(spec, typeName, user, onto, gmax, frac)
    if not (r and Fx) then return nil end
    if type(spec) == "string" then spec = (gmax and MoveFx.GMAX[spec]) or MoveFx.MOVES[spec] or { "slam" } end
    local function battler(w) if w == "boss" then return r.boss end return r.members[w] and r.members[w].b end
    local targets = {}
    for _, w in ipairs(onto or {}) do
      local b = battler(w)
      if b then targets[#targets + 1] = { b = b, frac = frac } end
    end
    local K = Fx.KIND[(spec[1] == "drop" and spec.shape == "slab") and "slab" or spec[1]] or Fx.KIND.slam
    local len = K[1] * (gmax and Fx.GMAX_K or 1)
    if spec[1] == "multi" then len = K[1] * (spec.n or 3) + 0.2 end
    r.anim = { at = r.t + (gmax and Rd.GMAX_CHARGE_S or 0), spec = spec, user = battler(user), targets = targets,
      type = typeName or "NORMAL", gmax = gmax, chargeAt = gmax and r.t or nil, len = len,
      impact = K[2] and K[2] * (gmax and Fx.GMAX_K or 1) or len }
    return r.anim
  end

  -- the members a boss's move at events[k] falls on: those hit, missed or touched by it, up to the
  -- next move
  function Rd.targetsAhead(k)
    local out, seen = {}, {}
    local list = r.events or {}
    for j = k + 1, #list do
      local e = list[j]
      if e.kind == "use" or e.kind == "over" or e.kind == "cheer" or e.kind == "item" then break end
      local who = e.target or ((e.kind == "status" or e.kind == "stage") and e.who) or nil
      local i = who and not who.boss and memberIndex(who)
      if i and not seen[i] then seen[i] = true; out[#out + 1] = i end
    end
    table.sort(out)
    return out
  end

  local function startEvent(e)
    local E = Rd.EVENT
    r.evT = r.t
    showFor(e)
    if e.fieldType then r.fieldShown = e.fieldType end
    -- the barrier's pills follow the events (gone once broken)
    if e.kind == "shield" and r.boss then
      r.boss.shieldShown = e.step ~= "break" and { left = e.left, max = e.max } or nil
      if e.step == "hit" and Scene then Scene.shake(0.06, 0.25) end
      if Fx then
        if e.step == "up" then Fx.barrierUp(r.t)
        elseif e.step == "hit" then Fx.barrierHit(r.t)
        elseif e.step == "break" then
          Fx.barrierBreak(placeOf(r.boss), r.t)
          if Scene then Scene.shake(0.25, 0.6); if Scene.kick then Scene.kick(4, 0.4) end end
        end
      end
    end
    if e.kind == "faint" and not e.who.boss then r.shownFaints = (r.shownFaints or 0) + 1 end
    if Sounds then
      local E2 = Sounds.EVENT
      if e.kind == "faint" then Rd.se(E2.faint)
      elseif e.kind == "back" then Rd.se(E2.back)
      elseif e.kind == "item" then Rd.se(E2.item)
      elseif e.kind == "heal" then Rd.se(E2.heal)
      elseif e.kind == "cheer" then Rd.se(E2.cheer)
      elseif e.kind == "stage" then Rd.se((e.n or 0) >= 0 and E2.up or E2.down)
      elseif e.kind == "status" and e.status then Rd.se(Sounds.STATUS[e.status])
      elseif e.kind == "field" and e.fieldType then Rd.se(Sounds.FIELD[e.fieldType])
      elseif e.kind == "shield" then
        Rd.se(e.step == "up" and E2.shieldUp or e.step == "break" and E2.shieldBreak or E2.shieldHit)
      elseif (e.kind == "damage" or e.kind == "residual") and not e.looked then
        -- (a hit with no look of its own: poison, a trap, the field)
        Rd.se(Sounds.HIT.plain)
      end
    end
    -- a member fainting is taken off the field (it shrinks away, red); one coming back grows in
    if (e.kind == "faint" or e.kind == "back") and not e.who.boss then
      local i = memberIndex(e.who)
      local m = i and r.members[i]
      if m then
        if e.kind == "faint" then m.faintT, m.backT = r.t, nil else m.backT = r.t end
        local A = placeOf(e.who)
        if Fx and A then
          if e.kind == "faint" then
            Fx.emit("light", A.X, A.Y, A.Z + 0.3, 0, 0, 0, 0.5, A.h * 2.5, 1, 0.2, 0.25, 0.45)
          else
            Fx.emit("light", A.X, A.Y, A.Z + 0.3, 0, 0, 0, 0.5, A.h * 2.5, 1, 1, 1, 0.45)
          end
        end
      end
    end
    if e.kind == "use" then Rd.scheduleMove(e) end
    if e.kind == "use" then
      local i = memberIndex(e.who)
      if Scene then
        if i then Scene.shot("member", E.CAM_S, i)
        else
          -- the boss's move: the camera on it and whom it falls on - one member, or all of them
          local hit = Rd.targetsAhead(r.evI)
          if #hit > 1 then Scene.shot("spread", E.CAM_S)
          elseif #hit == 1 then Scene.shot("target", E.CAM_S, hit[1])
          else Scene.shot("boss", E.CAM_S) end
        end
      end
      if i then r.focus = i end
    end
    local hit = e.target or e.who
    if e.hp and hit then
      hit.dispTarget = e.hp
      local i = memberIndex(hit)
      if i then r.focus = i end
      if (e.kind == "damage" or e.kind == "residual") and Scene and not e.looked then
        Scene.shake(hit.boss and 0.08 or 0.14, 0.4)
      end
    end
    if e.text then
      Rd.say(e.text)
      r.evDur = #e.text / Rd.MSG.CPS + E.HOLD_S
      -- (a move's use lasts until its look has landed)
      if e.kind == "use" and r.anim then r.evDur = max(r.evDur, r.anim.at - r.t + (r.anim.impact or r.anim.len) + 0.15) end
    else
      -- (a hit lands with no words: the band steps aside while the bar drains)
      r.say = nil
      r.evDur = E.DAMAGE_S
    end
  end

  -- the end of the raid's last words: the den's outcome (deps.onEnd), then back to the field
  local function finish()
    local outcome = r.sim and r.sim.over
    if deps.onEnd then pcall(deps.onEnd, r.den, outcome, r) end
    if outcome == "win" and Rewards then return Rd.startCatch() end
    Rd.close()
  end

  -- ------- the catch (Sword / Shield's: one throw after the win, a ball the player picks) and the
  -- rewards card (src/rewards.lua does the giving)

  -- the throw, as Sword / Shield's (Wooble's capture max-catch-reward-screen-end-card.mp4): the giant
  -- ball held up behind the party (HOLD), hurled in an arc at the boss (FLY), a flash as it reaches it
  -- (FLASH), it opens (OPEN) and the boss is drawn in on streaks of light (SUCK), shuts (CLOSE), drops
  -- to the ground (FALL) and lands in a crater of thrown-up rocks (SETTLE), then three checks: each a
  -- slow wobble round a cone with its button lit (CHECK each). Caught: the button flares, a flash, and
  -- the giant ball shrinks into the real one (SHRINK), whose button lights green with sparkles
  -- (GOTCHA). Broken free: it bursts. BALL_M its diameter in metres (a member stands 1.1), SMALL_M the
  -- real ball's.
  Rd.THROW = { HOLD = 1.2, FLY = 0.85, FLASH = 0.25, OPEN = 0.3, SUCK = 1.3, CLOSE = 0.25, FALL = 0.55,
    SETTLE = 0.5, TURN = 0.45, AIM_SPIN = 1.2, AIM_LEAN = 0.15, CHECK = 1.3, CHECKS = 3, LEAN = 0.3, FLARE = 0.35, SHRINK = 0.65, GOTCHA = 1.2,
    BALL_M = 2.2, SMALL_M = 0.4 }
  local BALL_RGB = {
    ITEM_POKE_BALL = { 0.9, 0.15, 0.15 }, ITEM_GREAT_BALL = { 0.2, 0.45, 0.95 }, ITEM_ULTRA_BALL = { 0.95, 0.8, 0.15 },
    ITEM_MASTER_BALL = { 0.55, 0.25, 0.75 }, ITEM_PREMIER_BALL = { 0.95, 0.95, 0.95 }, ITEM_LUXURY_BALL = { 0.15, 0.15, 0.18 },
    ITEM_NET_BALL = { 0.2, 0.75, 0.75 }, ITEM_DIVE_BALL = { 0.3, 0.6, 0.95 }, ITEM_NEST_BALL = { 0.55, 0.8, 0.2 },
    ITEM_REPEAT_BALL = { 0.95, 0.5, 0.15 }, ITEM_TIMER_BALL = { 0.95, 0.95, 0.95 },
  }

  -- the choice, as Sword / Shield's (Wooble's screenshots): two pills at the lower right, Catch and
  -- Don't Catch; Catch opens the ball box - the ball's name, how many, left / right through every ball
  -- the bag holds, its description, Use. No chance is shown.
  function Rd.startCatch()
    r.phase = "catch"
    r.events, r.rows, r.bossShow = nil, {}, true
    if r.boss then r.boss.shieldShown = nil end
    local balls = Rewards.balls()
    for _, bl in ipairs(balls) do bl.desc = Rewards.itemDesc and Rewards.itemDesc(bl.item) or "" end
    r.cmd = { menu = "catchq", cursor = 1, balls = balls, ball = 1, chosen = {}, moveList = {} }
    if Scene then Scene.shot("field", 0.8) end
    if #balls == 0 then r.cmd.cursor = 2 end
    return true
  end

  -- Catch (the ball box), Don't Catch (on to the rewards)
  function Rd.catchChoose(which)
    if not (r and r.phase == "catch") then return false end
    if which == "catch" then
      if #r.cmd.balls == 0 then
        Rd.say("You don't have any Pok\195\169 Balls...")
        return false
      end
      r.say = nil
      r.cmd.menu = "ballbox"
      return true
    end
    return Rd.startRewards()
  end
  function Rd.catchBack()
    if r and r.phase == "catch" and r.cmd.menu == "ballbox" then r.cmd.menu = "catchq"; return true end
    return false
  end
  function Rd.catchBall(d)
    if not (r and r.phase == "catch") then return end
    local n = #r.cmd.balls
    if n > 0 then r.cmd.ball = (r.cmd.ball - 1 + d) % n + 1 end
  end

  -- a ball thrown (i: its place in the box; the one shown when nil)
  function Rd.pickBall(i)
    if not (r and r.phase == "catch") then return false end
    local ball = r.cmd.balls[i or r.cmd.ball]
    if not ball then return false end
    local level = r.boss and r.boss.mon.level or 20
    local caught, info = Rewards.throw(r.key, level, ball, r.rng)
    r.throw = { t0 = r.t, caught = caught, info = type(info) == "table" and info or nil, ball = ball,
      rgb = BALL_RGB[ball.key] or BALL_RGB.ITEM_POKE_BALL, said = {}, cues = {}, acc = 0 }
    r.phase = "throw"
    r.say = nil
    -- (behind the party, the ball held up toward the boss)
    if Scene then Scene.shot("field", 0.5) end
    return true
  end

  local catchWhere = { catch = {}, leave = {}, left = {}, right = {}, use = {}, panel = {} }
  Rd.catchWhere = catchWhere
  local function rsetC(t, x, y, w, h) t.x, t.y, t.w, t.h = x, y, w, h; return t end

  local function catchPill(G, t, word, sel, live)
    local rad = t.h / 2
    G.setColor(0, 0, 0, 0.25)
    G.rectangle("fill", t.x + 2, t.y + 3, t.w, t.h, rad, rad)
    if Pad and Pad.face then
      Pad.face(G, t.x, t.y, t.w, t.h, rad, { dark = sel })
    else
      if sel then G.setColor(0.04, 0.04, 0.05, 1) else G.setColor(1, 1, 1, 1) end
      G.rectangle("fill", t.x, t.y, t.w, t.h, rad, rad)
    end
    local f = Rd.font(t.h * 0.5)
    G.setFont(f)
    if sel then G.setColor(1, 1, 1, 1) elseif live then G.setColor(0.08, 0.08, 0.1, 1) else G.setColor(0.6, 0.6, 0.62, 1) end
    G.printf(word, t.x, t.y + (t.h - f:getHeight()) / 2, t.w, "center")
    if sel then
      local hh, x1, x2, cy = t.h * 0.34, t.x - t.h * 0.62, t.x - t.h * 0.16, t.y + t.h / 2
      G.setLineJoin("miter")
      G.setColor(0, 0, 0, 1)
      G.setLineWidth(t.h * 0.2)
      G.line(x1, cy - hh, x2, cy, x1, cy + hh)
      G.setColor(1, 1, 1, 1)
      G.setLineWidth(t.h * 0.1)
      G.line(x1, cy - hh, x2, cy, x1, cy + hh)
      G.setLineWidth(1)
    end
  end

  function Rd.drawCatch(G, w, h)
    local c = r.cmd
    if not c then return end
    G.push("all")
    if c.menu == "catchq" then
      local pw, ph, pitch = h * 0.37, h * 0.066, h * 0.08
      local right, bottom = w - h * 0.012, h - h * 0.03
      local t1 = rsetC(catchWhere.catch, right - pw, bottom - ph - pitch, pw, ph)
      local t2 = rsetC(catchWhere.leave, right - pw, bottom - ph, pw, ph)
      rsetC(catchWhere.panel, t1.x - ph * 0.5, t1.y, pw + ph * 0.5, bottom - t1.y)
      catchPill(G, t1, "Catch", c.cursor == 1, #c.balls > 0)
      catchPill(G, t2, "Don't Catch", c.cursor == 2, true)
    else
      local bl = c.balls[c.ball]
      local pw = min(w * 0.6, h * 0.72)
      local px, py, pb = w - pw - h * 0.005, h * 0.6, h * 0.97
      local hh = h * 0.075
      rsetC(catchWhere.panel, px, py, pw, pb - py)
      G.setColor(0, 0, 0, 0.3)
      G.rectangle("fill", px + 3, py + 4, pw, pb - py)
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", px, py, pw, pb - py)
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", px, py, pw, hh)
      -- the arrows
      local ax = hh * 0.55
      G.setColor(1, 1, 1, 1)
      G.polygon("fill", px + ax * 0.6, py + hh / 2, px + ax * 1.15, py + hh * 0.25, px + ax * 1.15, py + hh * 0.75)
      G.polygon("fill", px + pw - ax * 0.6, py + hh / 2, px + pw - ax * 1.15, py + hh * 0.25, px + pw - ax * 1.15, py + hh * 0.75)
      rsetC(catchWhere.left, px, py, hh * 1.4, hh)
      rsetC(catchWhere.right, px + pw - hh * 1.4, py, hh * 1.4, hh)
      if bl then
        -- its icon, name (plural, as the box says), how many
        local is = hh * 0.62
        Rd.itemIcon(G, bl.item, px + hh * 1.45, py + (hh - is) / 2, is, BALL_RGB[bl.key])
        local fN = Rd.font(hh * 0.46)
        G.setFont(fN)
        G.setColor(1, 1, 1, 1)
        local nm = bl.name or "?"
        if (bl.n or 1) > 1 and not nm:match("s$") then nm = nm .. "s" end
        G.printf(nm, px, py + (hh - fN:getHeight()) / 2, pw, "center")
        local fC = Rd.font(hh * 0.38)
        G.setFont(fC)
        G.printf("\195\151" .. tostring(bl.n or 0), px, py + (hh - fC:getHeight()) / 2, pw - hh * 1.5, "right")
        -- the description
        local fD = Rd.font(h * 0.04)
        G.setFont(fD)
        G.setColor(0.1, 0.1, 0.12, 1)
        G.printf(bl.desc or "", px + h * 0.035, py + hh + h * 0.022, pw - h * 0.07, "left")
      end
      -- Use
      local uw, uh = pw * 0.48, h * 0.058
      local u = rsetC(catchWhere.use, px + (pw - uw) / 2 + uh * 0.3, pb - uh - h * 0.03, uw, uh)
      catchPill(G, u, "Use", true, true)
    end
    G.pop()
  end

  -- a pointer on the choice (true when it took it)
  function Rd.catchPointer(ev)
    local c = r and r.cmd
    if not (c and r.phase == "catch") then return false end
    local W = catchWhere
    local function hit(t) return t.w and ev.x >= t.x and ev.x <= t.x + t.w and ev.y >= t.y and ev.y <= t.y + t.h end
    if c.menu == "catchq" then
      if hit(W.catch) then
        c.cursor = 1
        if ev.phase == "released" then Rd.catchChoose("catch") end
        return true
      elseif hit(W.leave) then
        c.cursor = 2
        if ev.phase == "released" then Rd.catchChoose("leave") end
        return true
      end
      return false
    end
    if ev.phase == "released" then
      if hit(W.left) then Rd.catchBall(-1)
      elseif hit(W.right) then Rd.catchBall(1)
      elseif hit(W.use) then Rd.pickBall()
      elseif not hit(W.panel) then Rd.catchBack() end
    end
    return true
  end

  -- caught: the version's own fanfare (the engine's battle profile, as its catch plays it), then its
  -- caught song under the words and the card
  function Rd.caughtFanfare()
    local Profile = engine("src.core.game3.battle.profile")
    local ok, prof = pcall(function() return Profile.get(nil) end)
    local snd = ok and prof and prof.sounds
    if not (snd and Audio and Audio.resolveSong) then return end
    local intro, song = Audio.resolveSong(snd.caughtIntro), Audio.resolveSong(snd.caught)
    if intro then pcall(Audio.playSe, intro) end
    local raid = r
    if song and Audio.waitSe and Audio.playSong then
      pcall(Audio.waitSe, intro, function() if r == raid then pcall(Audio.playSong, song) end end)
    end
  end

  -- the throw's marks (seconds from its start)
  local function throwTimes()
    local T = Rd.THROW
    local m = {}
    m.fly = T.HOLD
    m.at = m.fly + T.FLY
    m.open = m.at + T.FLASH
    m.suck = m.open + T.OPEN
    m.close = m.suck + T.SUCK
    m.turn = m.close + T.CLOSE
    m.fall = m.turn + T.TURN
    m.land = m.fall + T.FALL
    m.check = m.land + T.SETTLE
    m.done = m.check + T.CHECK * T.CHECKS
    m.shrink = m.done + T.FLARE
    m.small = m.shrink + T.SHRINK
    m.gotcha = m.small + 0.2
    return m
  end
  Rd.throwTimes = throwTimes

  -- the den's places for it (metres): held near the eye, in front of the boss, on the ground
  local function throwPlaces()
    local P = Scene and Scene.PAD or { x = 0, z = -9.2, h = 0.2 }
    local bh = (Scene and Scene.MEMBER_H or 1.1) * Rd.sizeOf(r.key)
    local R = Rd.THROW.BALL_M / 2
    -- (it takes the boss in from off to its side, its mouth turned to it, so the boss stays in view)
    return { X = -1.7, Y = 1.9, Z = 2.4 }, { X = P.x - bh * 0.42 - R * 1.2, Y = P.h + bh * 0.45, Z = P.z + 3.2 },
      { X = P.x, Y = R, Z = P.z + 2.2 }, R, bh
  end

  local function smoothstep(e0, e1, x)
    local t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
  end

  -- where the ball is now and how it stands: X, Y, Z (its middle), radius (m), and its pose
  function Rd.ballNow(u)
    local T, M = Rd.THROW, throwTimes()
    local H, B, Gr, R = throwPlaces()
    local o = { dyna = 1, open = 0, lean = 0, phi = 0, spin = 0, button = 0, bright = 0 }
    local X, Y, Z, rad = H.X, H.Y, H.Z, R
    if u < M.fly then
      -- held up: a slow bob, turning a little
      Y = H.Y + 0.08 * sin(u * 3)
      o.spin = -0.6 + 0.15 * sin(u * 1.7)
      o.lean = 0.25
      o.phi = 2.4
    elseif u < M.at then
      local f = (u - M.fly) / T.FLY
      local e = f * f * (3 - 2 * f)
      X, Y, Z = H.X + (B.X - H.X) * e, H.Y + (B.Y - H.Y) * e + 2.8 * sin(pi * e), H.Z + (B.Z - H.Z) * e
      -- tumbling on its way, coming round to aim its mouth at the boss as it arrives
      local aim = smoothstep(0.55, 1, f)
      o.spin = (-0.6 + f * 7) * (1 - aim) + T.AIM_SPIN * aim
      o.lean = 0.25 * (1 - aim) + T.AIM_LEAN * aim
      o.phi = 2.4 * (1 - aim) + pi * aim
    elseif u < M.fall then
      -- side on to the boss, its mouth toward it: open, the boss drawn in, shut; then it turns in the
      -- air to face the camera
      X, Y, Z = B.X, B.Y, B.Z
      if u < M.suck then o.open = (u - M.open) / T.OPEN
      elseif u < M.close then o.open = 1
      else o.open = 1 - (u - M.close) / T.CLOSE end
      o.open = max(0, min(1, o.open))
      o.bright = u < M.open and (1 - (u - M.at) / T.FLASH) * 0.6 or 0
      -- (upright, its front - where it opens - turned to the boss; the lid lifts up and back)
      local turn = u >= M.turn and smoothstep(0, 1, (u - M.turn) / T.TURN) or 0
      o.spin = T.AIM_SPIN * (1 - turn)
      o.lean = T.AIM_LEAN * (1 - turn)
      o.phi = pi
      Y = B.Y + 0.25 * sin(turn * pi)
    elseif u < M.land then
      -- the drop: straight down, faster and faster, onto the ground in front of the pad
      local f = (u - M.fall) / T.FALL
      local ff = f * f * f
      X, Y, Z = B.X + (Gr.X - B.X) * f, B.Y + (Gr.Y - B.Y) * ff, B.Z + (Gr.Z - B.Z) * f
    else
      -- (on the ground: its foot stays put, the ball turns about it - an inverted cone)
      o.anchor = true
      X, Y, Z = Gr.X, Gr.Y, Gr.Z
      if u < M.check then
        -- settling: a jolt as it bites into the ground
        local v = (u - M.land) / T.SETTLE
        o.lean = 0.12 * sin(v * pi * 3) * (1 - v)
        o.phi = 0
      elseif u < M.done then
        -- the checks: a slow wobble round a cone, its button lit through each
        local c = (u - M.check) / T.CHECK
        local f = c - floor(c)
        local ease = sin(min(1, f * 1.2) * pi)
        o.lean = T.LEAN * ease
        o.phi = f * 2 * pi + floor(c) * 0.7
        o.button = sin(f * pi)
      end
      if r.throw and r.throw.caught and u >= M.done then
        o.button = 1
        if u < M.shrink then
          o.bright = (u - M.done) / T.FLARE * 0.7
        elseif u < M.small then
          local s = (u - M.shrink) / T.SHRINK
          local e = s * s * (3 - 2 * s)
          rad = R + (T.SMALL_M / 2 - R) * e
          Y = rad
          o.dyna = 1 - e
          o.bright = 0.7 * (1 - e)
          o.button = 1 - e
        else
          rad = T.SMALL_M / 2
          Y = rad
          o.dyna = 0
          -- caught: the real ball's button glowing green
          local g = (u - M.gotcha) / T.GOTCHA
          o.button = (g > 0 and g < 1) and sin(g * pi) or 0
          o.buttonRGB = { 0.35, 1, 0.45 }
        end
      end
    end
    return X, Y, Z, rad, o
  end

  -- the throw's timeline (update step): cues for the camera, effects and words; the outcome
  local function stepThrow()
    local T, th = Rd.THROW, r.throw
    local u = r.t - th.t0
    local M = throwTimes()
    local H, B, Gr, R, bh = throwPlaces()
    local function once(k, at)
      if th.cues[k] or u < at then return false end
      th.cues[k] = true
      return true
    end
    -- the boss: drawn in through the open ball
    if u < M.suck then r.shrink = 1
    elseif u < M.close then r.shrink = 1 - (u - M.suck) / T.SUCK
    else r.shrink = 0 end
    local b = Bosses[r.key]
    local name = b and b.name or "It"
    local Ga = { X = Gr.X, Y = Gr.Y, Z = Gr.Z, h = R * 2, foot = 0 }
    if Sounds then
      local C = Sounds.CATCH
      if once("seThrow", M.fly) then Rd.se(C.throw) end
      if once("seOpen", M.open) then Rd.se(C.open) end
      if once("seSuck", M.suck) then Rd.se(C.suck) end
      if once("seClose", M.close + T.CLOSE * 0.6) then Rd.se(C.close) end
      if once("seLand", M.land) then Rd.se(C.land) end
      for k = 1, T.CHECKS do
        if once("seWob" .. k, M.check + (k - 1) * T.CHECK) then Rd.se(C.wobble) end
      end
      if th.caught and once("seClick", M.done) then Rd.se(C.click) end
      if not th.caught and once("seBurst", M.done) then Rd.se(C.burst) end
      if th.caught and once("seFanfare", M.gotcha) then Rd.caughtFanfare() end
    end
    if once("at", M.at) then
      -- it reaches the boss: a flash, the camera close on it
      if Fx then
        Fx.flash({ 1, 0.85, 1 }, 0.7, 0.35, r.t)
        Fx.emit("light", B.X, B.Y, B.Z + 1, 0, 0, 0, 0.5, bh * 2, 1, 0.4, 0.8, 0.6)
      end
      if Scene then
        local P = Scene.PAD
        Scene.shot({ eye = { B.X - 0.4, B.Y - 0.3, B.Z + 5.4 }, look = { P.x - bh * 0.08, B.Y + bh * 0.08, P.z },
          fov = 60 }, 0.15)
        Scene.shake(0.12, 0.4)
      end
    end
    if once("closed", M.close + T.CLOSE * 0.6) and Fx then
      Fx.flash({ 1, 0.6, 0.2 }, 0.45, 0.3, r.t)
    end
    if once("fall", M.fall) and Scene then Scene.shot("catch", T.FALL) end
    if once("land", M.land) then
      -- it lands: the ground thrown up round it
      if Fx then
        Fx.emit("light", Gr.X, 0.5, Gr.Z + R, 0, 0, 0, 0.35, R * 5, 1, 0.85, 0.5, 0.5)
        for k = 1, 3 do
          local p = Fx.emit("gring", Gr.X, 0.03, Gr.Z, 0, 0, 0, 0.7 + k * 0.15, R * (2.2 + k), 1, 0.8, 0.5, 0.6)
          if p then p.w = 0.6 end
        end
        for j = 1, 26 do
          local a = j / 26 * 2 * pi
          Fx.emit("dust", Gr.X + cos(a) * R, 0.2, Gr.Z + sin(a) * R * 0.7, cos(a) * 4, 0.6 + (j % 3) * 0.4,
            sin(a) * 3, 1.6, 0.5, 0.95, 0.78, 0.45, 0.6)
        end
        for j = 1, 18 do
          local a = j / 18 * 2 * pi + 0.3
          local p = Fx.emit("chunk", Gr.X + cos(a) * R * 0.9, 0.3, Gr.Z + sin(a) * R * 0.6, cos(a) * 3.5,
            3 + (j % 4), sin(a) * 2.5, 1.4, 0.12 + 0.06 * (j % 3), 0.5, 0.4, 0.3, 1)
          if p then p.floor = 0 end
        end
        Fx.decal("crack", Gr.X, 0, Gr.Z, R * 2.2, r.t, 30)
      end
      if Scene then
        Scene.shake(0.35, 0.6)
        if Scene.kick then Scene.kick(5, 0.4) end
      end
      -- the crater's rocks, round where it lies
      th.rocks = {}
      for j = 1, 9 do
        local a = (j / 9) * 2 * pi + 0.35 * sin(j * 2.3)
        local d = R * (1.05 + 0.25 * ((j * 7) % 3) / 2)
        th.rocks[j] = { X = Gr.X + cos(a) * d * 1.15, Z = Gr.Z + sin(a) * d * 0.75, size = 0.55 + 0.35 * ((j * 5) % 4) / 3,
          seed = j * 3.7 }
      end
    end
    -- the energy streaming off its sides while it is giant, the light drawn in from the boss
    if Fx then
      th.acc = th.acc + max(0, r.t - (th.lastT or r.t)) * 40
      th.lastT = r.t
      local X, Y, Z, rad, o = Rd.ballNow(u)
      while th.acc >= 1 do
        th.acc = th.acc - 1
        if o.dyna > 0.5 and u < M.small then
          local side = (th.acc * 7919 % 2 < 1) and -1 or 1
          local jx = (math.random() - 0.5) * 0.4
          Fx.emit("wisp", X + side * rad * 0.95, Y + (math.random() - 0.3) * rad * 0.8, Z + 0.3,
            side * (0.6 + math.random()), 0.6 + math.random(), jx, 0.7, rad * 0.22, 1, 0.25, 0.7, 0.55)
          Fx.emit("ember", X + side * rad, Y + (math.random() - 0.5) * rad, Z + 0.3, side * 1.5, 1.2, 0, 0.6,
            0.05, 1, 0.4, 0.85, 1)
        end
        if u >= M.suck and u < M.close then
          -- streaks of light from the boss into the ball
          local bx = B.X + (math.random() - 0.5) * bh * 0.8
          local by = B.Y + (math.random() - 0.5) * bh * 0.9
          local p = Fx.emit("inspark", bx, by, B.Z - 0.8, 0, 0, 0, 1.2, 0.06, 1, 0.45, 0.75, 1)
          if p then p.home = { X = X, Y = Y, Z = Z + 0.2 } end
        end
      end
    end
    if th.caught then
      if once("flare", M.shrink) and Fx then
        Fx.flash({ 1, 1, 1 }, 0.75, 0.4, r.t)
        Fx.emit("light", Gr.X, Gr.Y, Gr.Z + R, 0, 0, 0, 0.5, R * 6, 1, 0.5, 0.85, 0.7)
      end
      if once("small", M.small) and Scene then
        Scene.shot({ eye = { Gr.X + 0.5, 0.9, Gr.Z + 3.8 }, look = { Gr.X, 0.25, Gr.Z }, fov = 42 }, 0.9)
      end
      if once("gotcha", M.gotcha) and Fx then
        for j = 1, 10 do
          local p = Fx.emit("twinkle", Gr.X + (j - 5.5) * 0.04, 0.4, Gr.Z + 0.25, (j - 5.5) * 0.08, 0.6 + (j % 3) * 0.2, 0,
            1.4, 0.04, 1, 0.95, 0.4, 1)
          if p then p.grow = 0 end
        end
      end
      if once("say", M.gotcha + 0.3) then Rd.say(("Gotcha! %s was caught!"):format(name)) end
    elseif once("burst", M.done) then
      Rd.say(("Oh no! %s broke free!"):format(name))
      th.burstAt = r.t
      if Fx then
        Fx.barrierBreak({ X = Gr.X, Y = Gr.Y, Z = Gr.Z, h = R * 2, foot = 0 }, r.t)
        Fx.flash({ 1, 0.5, 0.8 }, 0.28, 0.3, r.t)
      end
      if Scene then
        Scene.shot("field", 0.6)
        Scene.shake(0.25, 0.5)
      end
    end
    local _ = Ga
    if th.burstAt then
      local v = r.t - th.burstAt
      r.shrink = v < 0.4 and (v / 0.4) or max(0, 1 - (v - 1.6) / 0.6)
    end
    local endAt = th.caught and (M.gotcha + 0.3) or M.done
    th.said.out = u >= endAt
    local holdUntil = endAt + (#(r.say or "") / Rd.MSG.CPS) + 1.2 + (th.caught and 0 or 2.2)
    if th.caught and th.info and th.info.toPC and u >= holdUntil and not th.said.pc then
      th.said.pc = true
      th.pcAt = u
      Rd.say(("%s was sent to the PC."):format(name))
    end
    if not th.caught and u >= M.done + 2.0 and not th.said.gone then
      th.said.gone = true
      Rd.say(("%s disappeared..."):format(name))
      if Sounds then Rd.se(Sounds.CATCH.gone) end
    end
    local doneAt = holdUntil + (th.pcAt and 1.6 or 0)
    if u >= doneAt then Rd.startRewards() end
  end
  Rd.stepThrow = stepThrow

  -- the rewards, given (src/rewards.lua), then shown on a card until A or a tap
  function Rd.startRewards()
    r.phase = "rewards"
    r.say = nil
    r.shrink = r.throw and r.throw.caught and 0 or r.shrink
    local ok, out = pcall(Rewards.give, r, r.rng)
    if not ok then mod.log:warn("raid rewards failed: %s", tostring(out)); out = { items = {}, team = {} } end
    r.rewards = out
    r.rewardsT = r.t
    return true
  end

  -- Next on the card: the end card (the den once more, the circle closing), then what follows
  function Rd.endRewards()
    if not (r and r.phase == "rewards") or r.t - (r.rewardsT or 0) < 0.5 then return false end
    r.phase = "outro"
    r.outroT = r.t
    r.say = nil
    r.bossGone = true
    if Scene then Scene.shot("wide", 0) end
    return true
  end

  -- ------- after the raid: in party order, each of the four that levelled - its evolution (the
  -- engine's scene, the raid standing aside), then its new moves (the engine's LearnMove: its words
  -- in the band, Yes / No on the pad, which to forget in the game's summary), one by one

  local function partyIndex(mon)
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    for i, p in ipairs(s and s.party or {}) do if p == mon then return i end end
    return 99
  end

  -- the words in the band, then (A / a tap once typed) cb; or Yes / No on the pad
  function Rd.ask(t)
    r.ask = t
    Rd.say(t.text or "")
    if t.kind == "yesno" then
      r.cmd = { menu = "yesno", cursor = 1, chosen = {}, moveList = {
        { name = "Yes", chip = "", right = "", rgb = { 0.2, 0.75, 0.35 }, live = true, yes = true },
        { name = "No", chip = "", right = "", rgb = { 0.85, 0.3, 0.3 }, live = true, yes = false },
      } }
    end
  end
  function Rd.answer(yes)
    local t = r and r.ask
    if not t then return false end
    if t.kind == "msg" and r.say and (r.t - (r.sayT or 0)) * Rd.MSG.CPS < #r.say then return false end
    r.ask, r.say = nil, nil
    if t.cb then t.cb(yes) end
    return true
  end

  function Rd.startAfter()
    r.phase = "after"
    r.say = nil
    local q = {}
    for _, m in ipairs(r.members) do
      if m.orig and (m.levelTo or 0) > (m.levelFrom or 0) then q[#q + 1] = m end
    end
    table.sort(q, function(a, b) return partyIndex(a.orig) < partyIndex(b.orig) end)
    r.afterQ = q
    Rd.afterStep(1)
    return true
  end

  function Rd.afterStep(i)
    if not r then return end
    local m = r.afterQ and r.afterQ[i]
    if not m then return Rd.close() end
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    local Evolution = engine("src.core.game3.evolution")
    local target = Evolution and Evolution.levelTarget and select(2, pcall(Evolution.levelTarget, m.orig, s)) or nil
    local Scene3 = engine("src.ui.game3.evolution_scene")
    if tonumber(target) and Scene3 and Scene3.start then
      r.aside = true
      local raid = r
      local ok = pcall(Scene3.start, m.orig, target, { session = s, bag = s and s.bag, canStop = true,
        savedSong = Audio and Audio._mapSong,
        onDone = function(result)
          raid.aside, raid.skipInput = false, true
          -- (evolved, the scene taught the new form its moves at this level)
          if r == raid then Rd.afterMoves(i, result == "evolved") end
        end })
      if ok then return end
      r.aside = false
    end
    Rd.afterMoves(i, false)
  end

  function Rd.afterMoves(i, evolved)
    local m = r.afterQ[i]
    local levels = {}
    for lv = (m.levelFrom or 0) + 1, (m.levelTo or 0) - (evolved and 1 or 0) do levels[#levels + 1] = lv end
    local LearnMove = engine("src.core.game3.battle.learn_move")
    if #levels == 0 or not (LearnMove and LearnMove.beginQueue) then return Rd.afterStep(i + 1) end
    local name = m.b and m.b.name or "?"
    local raid = r
    local function nextOne() if r == raid then Rd.afterStep(i + 1) end end
    local ok = pcall(LearnMove.beginQueue, m.orig, levels, {
      displayName = name,
      pushMsg = function(text, cb) Rd.ask({ kind = "msg", text = text, cb = cb }) end,
      askYesNo = function(a, b)
        local cb = (type(a) == "function") and a or b
        local prompt = (type(a) == "string") and a or (r and r.say) or ""
        Rd.ask({ kind = "yesno", text = prompt, cb = function(yes) if cb then cb(yes == true) end end })
      end,
      askForget = function(a, b, c)
        local cb = (type(b) == "function") and b or c
        local SummaryMenu = engine("src.ui.game3.summary_menu")
        if not (SummaryMenu and SummaryMenu.openMenu) then if cb then cb(nil) end return end
        raid.aside = true
        SummaryMenu.openMenu({ m.orig }, 1, { mode = "select_move", moveToLearn = LearnMove._moveId,
          onSelectMove = function(slot)
            raid.aside, raid.skipInput = false, true
            if cb then cb(slot) end
          end })
      end,
      onDone = nextOne,
    })
    if not ok then nextOne() end
  end

  function Rd.playEvents(skip)
    if not (r and r.phase == "battle" and r.events) then return end
    if not skip and r.t - r.evT < r.evDur then return end
    r.evI = r.evI + 1
    local e = r.events[r.evI]
    if e then return startEvent(e) end
    r.events = nil
    if r.sim and r.sim.over then return finish() end
    for _, m in ipairs(r.members) do if m.b then m.b.dispTarget = m.b.mon.hp end end
    if r.boss then r.boss.dispTarget = r.boss.mon.hp end
    Rd.startCommand()
  end

  -- back: from the moves to the commands, else to the member before, its pick undone
  function Rd.back()
    if not (r and r.phase == "command" and r.cmd.actor) then return false end
    if r.cmd.menu == "target" then
      r.cmd.menu, r.cmd.cursor, r.cmd.item = "items", 1, nil
      Rd.moveList()
      return true
    end
    if r.cmd.menu == "moves" or r.cmd.menu == "items" then
      r.cmd.menu, r.cmd.cursor = "main", 1
      return true
    end
    for i = r.cmd.actor - 1, 1, -1 do
      if canAct(i) then
        r.cmd.chosen[i] = nil
        r.cmd.actor, r.cmd.cursor, r.cmd.menu = i, 1, "main"
        toMember(i)
        return true
      end
    end
    return false
  end

  -- ------- input

  local function uiKey()
    if not r then return "" end
    local c = r.cmd or {}
    return table.concat({ r.phase or "", tostring(c.menu), tostring(c.cursor), tostring(c.ball), tostring(c.actor),
      tostring(r.rw and r.rw.cursor), tostring(r.cursor), tostring(r.ask) }, "|")
  end
  local function uiTick(before)
    if Sounds and r and uiKey() ~= before then Rd.se(Sounds.UI.move) end
  end
  local inputInner
  function Rd.input(input)
    local before = uiKey()
    local res = inputInner(input)
    uiTick(before)
    return res
  end
  function inputInner(input)
    if not r or r.summary or r.aside then return end
    if r.skipInput then r.skipInput = nil; return end
    if r.phase == "den" then
      -- (the press that opened the den is still down on its first frames: not a toggle)
      if r.t < Rd.DEN_ARM_S then return end
      local n = #r.party
      if input:wasPressed("up") and n > 0 then r.cursor = (r.cursor - 2) % n + 1
      elseif input:wasPressed("down") and n > 0 then r.cursor = r.cursor % n + 1
      elseif input:wasPressed("a") then Rd.denToggle(r.cursor)
      elseif input:wasPressed("start") then Rd.denStart()
      elseif input:wasPressed("b") then Rd.close() end
      return
    end
    if r.phase == "command" and Pad then
      local moves = r.cmd.menu ~= "main"
      local n = moves and max(1, #(r.cmd.moveList or {})) or #Pad.ITEMS
      if input:wasPressed("up") then r.cmd.cursor = (r.cmd.cursor - 2) % n + 1
      elseif input:wasPressed("down") then r.cmd.cursor = r.cmd.cursor % n + 1
      elseif input:wasPressed("a") then Rd.choose(moves and ("move" .. r.cmd.cursor) or Pad.ITEMS[r.cmd.cursor].id)
      elseif input:wasPressed("b") then Rd.back() end
    elseif r.phase == "catch" then
      if r.cmd.menu == "catchq" then
        if input:wasPressed("up") or input:wasPressed("down") then r.cmd.cursor = 3 - r.cmd.cursor
        elseif input:wasPressed("a") then Rd.catchChoose(r.cmd.cursor == 1 and "catch" or "leave")
        elseif input:wasPressed("b") then r.cmd.cursor = 2 end
      else
        if input:wasPressed("left") then Rd.catchBall(-1)
        elseif input:wasPressed("right") then Rd.catchBall(1)
        elseif input:wasPressed("a") then Rd.pickBall()
        elseif input:wasPressed("b") then Rd.catchBack() end
      end
    elseif r.phase == "rewards" then
      local onNext = r.rw and r.rewards and r.rw.cursor > #(r.rewards.items or {})
      if input:wasPressed("up") then Rd.cardMove(-1)
      elseif input:wasPressed("down") then Rd.cardMove(1)
      elseif input:wasPressed("a") then
        if onNext or not r.rw then Rd.endRewards() else Rd.cardMove(1) end
      elseif input:wasPressed("b") then Rd.cardMove(99) end
    elseif r.phase == "after" and r.ask then
      if r.ask.kind == "yesno" then
        if input:wasPressed("up") or input:wasPressed("down") then r.cmd.cursor = 3 - r.cmd.cursor
        elseif input:wasPressed("a") then Rd.answer(r.cmd.cursor == 1)
        elseif input:wasPressed("b") then Rd.answer(false) end
      elseif input:wasPressed("a") or input:wasPressed("b") then
        Rd.answer()
      end
    elseif r.phase == "battle" and input:wasPressed("a") then
      -- A hurries the words: once typed, on to the next
      if r.say and (r.t - (r.sayT or 0)) * Rd.MSG.CPS >= #r.say then Rd.playEvents(true) end
    end
  end

  -- the den screen's places (window pixels), from its last draw
  local denWhere = { rows = {}, start = {}, back = {} }
  Rd.denWhere = denWhere
  local function inRect(x, y, t) return t and t.w and x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h end

  -- a pointer on the window (input.pointer): true when the den screen or the pad took it
  local pointerInner
  function Rd.pointer(ev)
    local before = uiKey()
    local res = pointerInner(ev)
    uiTick(before)
    return res
  end
  function pointerInner(ev)
    if r and r.phase == "den" then
      if ev.phase == "released" and r.t >= Rd.DEN_ARM_S then
        if inRect(ev.x, ev.y, denWhere.start) then Rd.denStart()
        elseif inRect(ev.x, ev.y, denWhere.back) then Rd.close()
        else
          for i, row in ipairs(denWhere.rows) do
            if inRect(ev.x, ev.y, row) then r.cursor = i; Rd.denToggle(i) end
          end
        end
      end
      return true
    end
    if r and r.phase == "rewards" then
      local W = Rd.cardWhere
      if inRect(ev.x, ev.y, W.next) then
        Rd.cardMove(99)
        if ev.phase == "released" then Rd.endRewards() end
      else
        for _, row in ipairs(W.rows) do
          if inRect(ev.x, ev.y, row) and r.rw then r.rw.cursor = row.i end
        end
      end
      return true
    end
    if r and r.phase == "outro" then return true end
    if r and r.phase == "after" then
      if r.summary or r.aside then return false end
      if r.ask and r.ask.kind == "yesno" and Pad then
        local hit = Pad.hit(ev.x, ev.y, "yesno")
        local slot = hit and tonumber(hit:match("^move(%d)$") or "")
        if slot then r.cmd.cursor = slot end
        if ev.phase == "released" then
          if slot then Rd.answer(slot == 1) elseif hit == "back" then Rd.answer(false) end
        end
      elseif ev.phase == "released" then
        Rd.answer()
      end
      return true
    end
    if r and r.phase == "catch" then return Rd.catchPointer(ev) end
    if not (r and Pad) or deps.padOnSecond() or r.phase ~= "command" or r.say or r.summary then return false end
    local hit = Pad.hit(ev.x, ev.y, r.cmd.menu)
    if hit and hit ~= "panel" then
      -- a press moves the selection onto the pill; letting go picks it
      local slot = hit:match("^move(%d)$")
      if slot then r.cmd.cursor = tonumber(slot) end
      if r.cmd.menu == "main" then
        for i, item in ipairs(Pad.ITEMS) do
          if item.id == hit then r.cmd.cursor = i end
        end
      end
      if ev.phase == "released" then Rd.choose(hit) end
    end
    return hit ~= nil
  end

  -- a press on the second screen's pad (src/screen2.lua): down puts the selection on it, up picks
  function Rd.secondPress(id, released)
    if not (r and id) then return end
    local before = uiKey()
    local slot = tonumber(id:match("^move(%d)$") or "")
    if r.phase == "command" and r.cmd and not r.say and not r.summary then
      if slot then r.cmd.cursor = slot end
      if r.cmd.menu == "main" then
        for i, item in ipairs(Pad.ITEMS) do if item.id == id then r.cmd.cursor = i end end
      end
      if released then Rd.choose(id) end
    elseif r.phase == "after" and r.ask and r.ask.kind == "yesno" and slot then
      r.cmd.cursor = slot
      if released then Rd.answer(slot == 1) end
    end
    uiTick(before)
  end

  -- ------- drawing (window pixels)

  local fonts = {}
  local function font(px)
    px = max(6, floor(px + 0.5))
    local f = fonts[px]
    if not f then
      local ok, made = pcall(love.graphics.newFont, px)
      f = ok and made or love.graphics.getFont()
      fonts[px] = f
    end
    return f
  end
  Rd.font = font

  -- n stars drawn as shapes (the default font has no star glyph), right-aligned at x, centred on y
  local starPts = {}
  local function drawStars(G, n, x, y, size)
    for k = 1, n do
      local cx = x - (k - 0.5) * size * 1.1
      for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rr = (i % 2 == 0) and size * 0.5 or size * 0.21
        starPts[i * 2 + 1], starPts[i * 2 + 2] = cx + rr * math.cos(a), y + rr * math.sin(a)
      end
      -- (a concave shape: drawn as ten triangles from its middle, not one polygon)
      for i = 0, 9 do
        local j = (i + 1) % 10
        G.polygon("fill", cx, y, starPts[i * 2 + 1], starPts[i * 2 + 2], starPts[j * 2 + 1], starPts[j * 2 + 2])
      end
    end
  end
  Rd.drawStars = drawStars

  local bossPic, memberPicsShown = {}, {}

  -- the message band (Sword / Shield's): dark gray across the whole width near the foot, the words
  -- white, typed out at CPS characters a second. Sizes in the screen's height (`h`), the margin in its
  -- width, measured off a 1784 x 998 capture: the band 172 tall with 23 under it, the words' left
  -- edge 160 in, about 48 px type in the band's upper part
  Rd.MSG = { BAND_H = 0.172, GAP = 0.023, TEXT = 0.048, LEFT = 0.09, TOP = 0.16, CPS = 40,
    RGBA = { 0.2, 0.2, 0.2, 0.93 } }

  -- the HUD over the den: the boss's name, stars and HP bar at the top (fading in with r.hud) and
  -- the message band
  -- the boss's block (Sword / Shield's, sizes in the window's height off a 1782 x 998 capture): the
  -- name large and white with a pink glow, its status in a tag beside it, the HP bar under it on a
  -- dark track. It shows while the words are about the boss (r.bossShow, eased into r.bossA).
  Rd.BOSS_HUD = { NAME = 0.058, NAME_Y = 0.028, BAR_Y = 0.116, BAR_W = 0.513, BAR_H = 0.008 }
  local STATUS_TAG = {
    BRN = { "BURNED", { 0.95, 0.45, 0.15 } }, PAR = { "PARALYZED", { 0.85, 0.7, 0.1 } },
    PSN = { "POISONED", { 0.6, 0.3, 0.75 } }, TOX = { "POISONED", { 0.6, 0.3, 0.75 } },
    SLP = { "ASLEEP", { 0.55, 0.55, 0.6 } }, FRZ = { "FROZEN", { 0.35, 0.75, 0.9 } },
  }
  local glowOff = { { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 }, { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } }
  local function drawHud(G, w, h)
    local b = Bosses[r.key]
    if not b then return end
    local a = (r.hud or 0) * (r.bossA or 1)
    -- (no boss block once it is in the ball or gone, nor over the rewards and what follows)
    if r.phase == "rewards" or r.phase == "after" or r.phase == "throw" or r.phase == "outro" then a = 0 end
    if a > 0.01 then
      local B = Rd.BOSS_HUD
      local f = font(h * B.NAME)
      G.setFont(f)
      local name = b.name
      local nw = f:getWidth(name)
      local nx, ny = (w - nw) / 2, h * B.NAME_Y
      local k = h / 998
      G.setColor(1, 0.15, 0.45, 0.28 * a)
      for _, d in ipairs(glowOff) do G.print(name, nx + d[1] * 2 * k, ny + d[2] * 2 * k) end
      G.setColor(1, 1, 1, a)
      G.print(name, nx, ny)
      G.print(name, nx + max(1, k), ny)
      -- its status in a tag after the name
      local st = r.boss and r.boss.status and STATUS_TAG[r.boss.status]
      if st then
        local tf = font(h * 0.02)
        local tw, th = tf:getWidth(st[1]) + h * 0.03, h * 0.026
        local tx, ty = nx + nw + h * 0.008, ny + f:getHeight() * 0.62 - th / 2
        local c = st[2]
        G.setColor(c[1], c[2], c[3], a)
        G.rectangle("fill", tx, ty, tw, th, th * 0.3, th * 0.3)
        -- its sign, drawn: a flame, a bolt, a drop, a "z", a flake
        G.setColor(1, 1, 1, a)
        local sx, sy, ss = tx + h * 0.012, ty + th / 2, th * 0.32
        local code = r.boss.status
        if code == "BRN" then
          G.polygon("fill", sx, sy - ss, sx + ss * 0.7, sy + ss * 0.2, sx + ss * 0.45, sy + ss * 0.85,
            sx - ss * 0.45, sy + ss * 0.85, sx - ss * 0.7, sy + ss * 0.2)
        elseif code == "PAR" then
          G.polygon("fill", sx + ss * 0.2, sy - ss, sx - ss * 0.6, sy + ss * 0.15, sx, sy + ss * 0.15,
            sx - ss * 0.2, sy + ss, sx + ss * 0.6, sy - ss * 0.15, sx, sy - ss * 0.15)
        elseif code == "PSN" or code == "TOX" then
          G.circle("fill", sx, sy + ss * 0.25, ss * 0.6, 12)
          G.polygon("fill", sx, sy - ss, sx + ss * 0.52, sy + ss * 0.05, sx - ss * 0.52, sy + ss * 0.05)
        elseif code == "SLP" then
          G.setLineWidth(max(1, ss * 0.3))
          G.line(sx - ss * 0.6, sy - ss * 0.7, sx + ss * 0.6, sy - ss * 0.7, sx - ss * 0.6, sy + ss * 0.7, sx + ss * 0.6, sy + ss * 0.7)
          G.setLineWidth(1)
        else
          G.setLineWidth(max(1, ss * 0.25))
          for q = 0, 2 do
            local ang = q * math.pi / 3
            G.line(sx - math.cos(ang) * ss, sy - math.sin(ang) * ss, sx + math.cos(ang) * ss, sy + math.sin(ang) * ss)
          end
          G.setLineWidth(1)
        end
        G.setFont(tf)
        G.print(st[1], tx + h * 0.024, ty + (th - tf:getHeight()) / 2)
      end
      -- the bar: green / yellow / red over a dark track
      local bw, bh = h * B.BAR_W, h * B.BAR_H
      local bx, by = (w - bw) / 2, h * B.BAR_Y
      local share = max(0, min(1, r.hpShown or 1))
      G.setColor(0.3, 0.3, 0.33, 0.9 * a)
      G.rectangle("fill", bx, by, bw, bh)
      if share > 0.5 then G.setColor(0.2, 0.9, 0.3, a)
      elseif share > 0.2 then G.setColor(0.98, 0.78, 0.15, a)
      else G.setColor(0.95, 0.25, 0.2, a) end
      G.rectangle("fill", bx, by, bw * share, bh)
      -- the barrier: slanted pills under the bar, red while they stand, grey once broken (from the
      -- right); none at all once every one is broken
      local sh = r.boss and r.boss.shieldShown
      if sh and sh.left > 0 and sh.max > 0 then
        local pw, gap, ph = bw * 0.078, bw * 0.009, bh * 1.6
        local total = sh.max * pw + (sh.max - 1) * gap
        local px, py = (w - total) / 2, by + bh + h * 0.007
        local slant = ph * 0.35
        for k = 1, sh.max do
          local x0 = px + (k - 1) * (pw + gap)
          if k <= sh.left then G.setColor(0.95, 0.2, 0.45, a) else G.setColor(0.45, 0.45, 0.48, a) end
          G.polygon("fill", x0 + slant, py, x0 + pw, py, x0 + pw - slant, py + ph, x0, py + ph)
        end
      end
    end
    if r.say then
      local M = Rd.MSG
      local bh = h * M.BAND_H
      local by = h - bh - h * M.GAP
      local c = M.RGBA
      G.setColor(c[1], c[2], c[3], c[4])
      G.rectangle("fill", 0, by, w, bh)
      -- its ends: slanted, a shade lighter
      G.setColor(1, 1, 1, 0.05)
      G.polygon("fill", 0, by, h * 0.055, by, h * 0.022, by + bh, 0, by + bh)
      G.polygon("fill", w - h * 0.05, by, w, by, w, by + bh, w - h * 0.085, by + bh)
      local n = floor((r.t - (r.sayT or 0)) * M.CPS)
      -- (never cut inside a character: past any UTF-8 continuation bytes)
      while n < #r.say and n > 0 do
        local byte = r.say:byte(n + 1)
        if byte < 128 or byte >= 192 then break end
        n = n + 1
      end
      local str = n >= #r.say and r.say or r.say:sub(1, n)
      local lx = w * M.LEFT
      G.setFont(font(h * M.TEXT))
      G.setColor(1, 1, 1, 1)
      G.printf(str, lx, by + bh * M.TOP, w - 2 * lx, "left")
    end
  end

  -- the den screen: a dark red backdrop; the boss as a black silhouette with a red rim, its stars
  -- and types; the party to pick from (up to four, ticked), START and BACK. A quiet den says so.
  local function rset(t, x, y, ww, hh) t.x, t.y, t.w, t.h = x, y, ww, hh; return t end
  local function button(G, t, rgb, word, u, live)
    local k = live and 1 or 0.45
    G.setColor(rgb[1] * 0.45 * k, rgb[2] * 0.45 * k, rgb[3] * 0.45 * k, 1)
    G.rectangle("fill", t.x, t.y + 3 * u, t.w, t.h, 8 * u, 8 * u)
    G.setColor(rgb[1] * k, rgb[2] * k, rgb[3] * k, 1)
    G.rectangle("fill", t.x, t.y, t.w, t.h, 8 * u, 8 * u)
    G.setFont(font(t.h * 0.45))
    G.setColor(1, 1, 1, live and 1 or 0.6)
    G.printf(word, t.x, t.y + (t.h - t.h * 0.45 * 1.2) / 2, t.w, "center")
  end
  local silShader, silFailed = nil, false
  local function silhouette()
    if silShader or silFailed then return silShader end
    local ok, s = pcall(love.graphics.newShader, [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(color.rgb, color.a * step(0.5, Texel(tex, tc).a));
}
]])
    if ok then silShader = s else silFailed = true end
    return silShader
  end

  local function drawDen(G, w, h)
    local u = h / 360
    -- backdrop
    G.setColor(0.07, 0.03, 0.05, 1)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(0.35, 0.03, 0.08, 0.6)
    G.circle("fill", w * 0.3, h * 0.55, h * 0.45, 48)
    local key = r.key
    G.setFont(font(20 * u))
    G.setColor(1, 1, 1, 1)
    if not key then
      G.printf("The den is quiet.", 0, h * 0.4, w, "center")
      G.setFont(font(14 * u))
      G.setColor(0.8, 0.8, 0.85, 1)
      G.printf("Nothing stirs here today. Come back tomorrow.", 0, h * 0.4 + 30 * u, w, "center")
      rset(denWhere.back, w / 2 - 70 * u, h * 0.7, 140 * u, 34 * u)
      rset(denWhere.start, 0, 0, 0, 0)
      for i = #denWhere.rows, 1, -1 do denWhere.rows[i] = nil end
      button(G, denWhere.back, { 0.2, 0.45, 0.9 }, "BACK", u, true)
      return
    end
    -- the boss: a red rim, then its silhouette
    local img, q, cell = Rd.frameAt(key, r.t)
    if img and loaded then
      local box = loaded.box
      local bh = box[4] - box[2]
      local k = (h * 0.7) / bh
      local cx, fy = w * 0.3, h * 0.88
      local ox, oy = (box[1] + box[3]) / 2, box[4]
      -- the rim and the body in flat colours (a silhouette shader: the sprite's alpha, one colour)
      local s = silhouette()
      if s then G.setShader(s) end
      G.setColor(0.9, 0.1, 0.18, 1)
      for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 1.5, 1.5 }, { -1.5, 1.5 }, { 1.5, -1.5 }, { -1.5, -1.5 } }) do
        G.draw(img, q, cx + d[1] * u, fy + d[2] * u, 0, k, k, ox, oy)
      end
      G.setColor(0, 0, 0, 1)
      G.draw(img, q, cx, fy, 0, k, k, ox, oy)
      G.setShader()
    end
    local b = Bosses[key]
    local px = w * 0.58
    G.setFont(font(22 * u))
    G.setColor(1, 1, 1, 1)
    G.print("Max Raid Battle", px, 24 * u)
    G.setColor(1, 0.85, 0.3, 1)
    drawStars(G, b.stars, px + b.stars * 18 * u, 66 * u, 16 * u)
    G.setFont(font(13 * u))
    G.setColor(0.85, 0.85, 0.9, 1)
    G.print(table.concat(b.types, " / "), px, 82 * u)
    G.setFont(font(14 * u))
    G.setColor(1, 1, 1, 1)
    G.print(("Choose up to four  (%d)"):format(pickedCount()), px, 108 * u)
    -- the party
    local rowH = 28 * u
    for i = #denWhere.rows, #r.party + 1, -1 do denWhere.rows[i] = nil end
    for i, row in ipairs(r.party) do
      local t = denWhere.rows[i] or {}
      denWhere.rows[i] = rset(t, px, 130 * u + (i - 1) * (rowH + 4 * u), w * 0.36, rowH)
      local on = r.picked[i]
      G.setColor(on and 0.75 or 0.22, on and 0.18 or 0.22, on and 0.25 or 0.28, 1)
      G.rectangle("fill", t.x, t.y, t.w, t.h, 6 * u, 6 * u)
      if i == r.cursor then
        G.setColor(1, 1, 1, 0.9)
        G.setLineWidth(2 * u)
        G.rectangle("line", t.x, t.y, t.w, t.h, 6 * u, 6 * u)
      end
      G.setFont(font(13 * u))
      G.setColor(1, 1, 1, 1)
      G.print(row.name, t.x + 10 * u, t.y + 6 * u)
      G.printf("Lv" .. row.level, t.x, t.y + 6 * u, t.w - 10 * u, "right")
    end
    local by = h - 50 * u
    rset(denWhere.start, px, by, w * 0.17, 34 * u)
    rset(denWhere.back, px + w * 0.19, by, w * 0.17, 34 * u)
    button(G, denWhere.start, { 0.2, 0.7, 0.3 }, "START", u, pickedCount() > 0)
    button(G, denWhere.back, { 0.2, 0.45, 0.9 }, "BACK", u, true)
  end

  -- a member's size on the field (1 standing, 0 gone): fainted, it shrinks away over FAINT_S; back,
  -- it grows in over BACK_S
  Rd.FAINT_S, Rd.BACK_S = 0.7, 0.5
  function Rd.memberShrink(m)
    if m.backT and r.t >= m.backT then return min(1, (r.t - m.backT) / Rd.BACK_S) end
    if m.faintT and r.t >= m.faintT then return max(0, 1 - (r.t - m.faintT) / Rd.FAINT_S) end
    return 1
  end

  function Rd.draw(G, w, h)
    if not r or r.summary or r.aside then return end
    if r.phase == "den" then return drawDen(G, w, h) end
    local img, q = Rd.frameAt(r.key, r.t)
    if img and loaded then
      bossPic.image, bossPic.quad, bossPic.box, bossPic.size = img, q, loaded.box, Rd.sizeOf(r.key)
      -- (drawn into the ball once thrown at: caught, or broken free and gone)
      bossPic.shrink = r.throw and (r.shrink or 1) or 1
      bossPic.lunge = r.lunge or 0
    end
    for i = 1, 4 do
      local m = r.members[i]
      memberPicsShown[i] = m and m.draw or nil
      if m and m.draw then m.draw.shrink = Rd.memberShrink(m) end
    end
    if Fx then
      local b = r.boss
      Fx.setLasting(r.phase ~= "rewards" and r.fieldShown or nil, b and placeOf(b) or nil,
        b and (b.veil or 0) > 0 and not r.throw, b and not r.throw and b.shieldShown or nil, r.t)
    end
    if Scene then Scene.draw(G, 0, 0, w, h, r.t, img and not r.bossGone and bossPic or nil, memberPicsShown) end
    if Fx and r.phase ~= "rewards" then
      local LB = Scene and Scene.lastBoss
      Fx.drawMoves(G, r.t)
      Fx.draw(G, w, h, r.t)
    end
    -- (the throw under the band, so the words stay clear of the ball and its crater)
    if r.phase == "throw" then Rd.drawThrow(G, w, h) end
    if r.phase == "outro" then
      local O = Rd.OUTRO
      Rd.drawIris(G, w, h, min(1, max(0, (r.t - r.outroT - O.HOLD) / O.CLOSE)))
    elseif r.phase == "after" and r.irisDone then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, w, h)
    end
    drawHud(G, w, h)
    -- the commands: the order down the top left, the one choosing in the lower left, the pad (only
    -- once a message has gone, as the game)
    if r.phase == "command" and not r.say then
      if BattlerHud then
        BattlerHud.drawOrder(G, w, h, r.members, r.cmd, r.t)
        BattlerHud.drawPanel(G, w, h, r.cmd.actor and r.members[r.cmd.actor])
      end
      if Pad and not deps.padOnSecond() then Pad.draw(G, w, h, r) end
    elseif r.phase == "battle" and BattlerHud and r.rows and #r.rows > 0 then
      BattlerHud.drawRows(G, w, h, r.rows, r.t)
    elseif r.phase == "catch" then
      if not r.say then Rd.drawCatch(G, w, h) end
    elseif r.phase == "rewards" then
      Rd.drawRewards(G, w, h)
    elseif r.phase == "after" then
      if r.ask and r.ask.kind == "yesno" and Pad and not deps.padOnSecond() then Pad.draw(G, w, h, r) end
    end
  end

  -- the throw drawn: the crater's rocks behind it, the ball (src/fx.lua's, in 3D), the rocks before it;
  -- while the boss goes in, streaks of light from it into the open ball; a magenta cast over the den
  function Rd.drawThrow(G, w, h)
    local th = r.throw
    if not (th and Fx and Fx.P) then return end
    local u = r.t - th.t0
    local M = throwTimes()
    G.push("all")
    G.setBlendMode("add")
    G.setColor(0.35, 0.02, 0.22, 0.25)
    G.rectangle("fill", 0, 0, w, h)
    G.setBlendMode("alpha")
    local X, Y, Z, rad, o = Rd.ballNow(u)
    local x, y, k = Fx.P(X, Y, Z)
    local ux, uy = sin(o.lean or 0) * cos(o.phi or 0), cos(o.lean or 0)
    if o.anchor then
      -- its foot on the ground, the middle leaning out over it
      local fx, fy, fk = Fx.P(X, 0, Z)
      if fx then x, y, k = fx + ux * rad * fk, fy - uy * rad * fk, fk end
    end
    if th.rocks then
      for _, rk in ipairs(th.rocks) do if rk.Z < Z then Fx.rock(G, rk.X, 0, rk.Z, rk.size, rk.seed) end end
    end
    if u >= M.suck and u < M.close + 0.1 then
      -- the boss drawn in: streaks from its body to the ball
      local LB = Scene and Scene.lastBoss
      if LB and x then
        G.setBlendMode("add")
        local f = (u - M.suck) / Rd.THROW.SUCK
        for j = 1, 14 do
          local sx = LB.x + (((j * 37) % 11) / 10 - 0.5) * LB.h * 0.7
          local sy = LB.y + (((j * 53) % 13) / 12 - 0.5) * LB.h * 0.8
          local ph = (f * 2.5 + j * 0.13) % 1
          local mx, my = x + sin(o.spin or 0) * rad * k * 0.6, y
          local hx, hy = sx + (mx - sx) * ph, sy + (my - sy) * ph
          local tx, ty = sx + (mx - sx) * max(0, ph - 0.35), sy + (my - sy) * max(0, ph - 0.35)
          G.setLineWidth(max(1, rad * k * 0.06 * (1 - ph * 0.5)))
          G.setColor(1, 0.45 + 0.4 * ((j % 3) / 2), 0.8, 0.75)
          G.line(tx, ty, hx, hy)
        end
        G.setBlendMode("alpha")
        G.setLineWidth(1)
      end
    end
    local bv = th.burstAt and (r.t - th.burstAt) or nil
    if x and not (bv and bv > 0.3) then
      o.now = r.t
      o.rgb = th.rgb
      if bv then
        -- broken free: it bursts open, flaring, and is gone
        o.open = min(1, bv / 0.15)
        o.bright = 0.6
        o.alpha = 1 - bv / 0.3
        o.lean, o.button = 0, 0
      end
      Fx.drawBall(G, x, y, rad * k, o)
    end
    if th.rocks then
      for _, rk in ipairs(th.rocks) do if rk.Z >= Z then Fx.rock(G, rk.X, 0, rk.Z, rk.size, rk.seed) end end
    end
    G.pop()
  end

  -- ------- the rewards card (Sword / Shield's): "You caught X!" in a black bar, the boss's stars, the
  -- boss on the left, the items down the right (icon, name, x count) with a cursor and a scroll bar,
  -- Next at the foot; then the end card: the den once more, a circle closing to black

  Rd.CARD = { ROWS = 6, ROW_H = 0.081, LIST_X = 0.53, LIST_W = 0.4, LIST_Y = 0.3, IN_S = 0.35, STAR_S = 0.12 }
  local cardWhere = { rows = {}, next = {} }
  Rd.cardWhere = cardWhere

  -- an item's bag icon (24 px), size px across: the FireRed bag's pictures, else Emerald's, else a dot
  local function itemIcon(G, id, x, y, size, rgb)
    local BC = engine("src.ui.game3.bag_chrome")
    local img = BC and BC.iconImage and select(2, pcall(BC.iconImage, id)) or nil
    if type(img) == "userdata" then
      G.setColor(1, 1, 1, 1)
      G.draw(img, x, y, 0, size / 24, size / 24)
      return
    end
    local RB = engine("src.ui.game3.rse.bag_chrome")
    if RB and RB.drawItemIcon and RB.manifest and select(2, pcall(RB.manifest)) then
      G.push()
      G.translate(x, y)
      G.scale(size / 24, size / 24)
      local ok = pcall(RB.drawItemIcon, id, 0, 0)
      G.pop()
      if ok then return end
    end
    local c = rgb or { 0.35, 0.55, 0.9 }
    G.setColor(c[1], c[2], c[3], 1)
    G.circle("fill", x + size / 2, y + size / 2, size * 0.38, 16)
  end
  Rd.itemIcon = itemIcon

  local function chevron(G, x, y, s)
    G.setColor(0, 0, 0, 1)
    G.setLineWidth(max(2, s * 0.32))
    G.line(x - s * 0.45, y - s * 0.55, x + s * 0.2, y, x - s * 0.45, y + s * 0.55)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(max(1, s * 0.14))
    G.line(x - s * 0.45, y - s * 0.55, x + s * 0.2, y, x - s * 0.45, y + s * 0.55)
    G.setLineWidth(1)
  end

  function Rd.drawRewards(G, w, h)
    local out = r.rewards
    if not out then return end
    local C = Rd.CARD
    local v = r.t - (r.rewardsT or r.t)
    local a = min(1, v / C.IN_S)
    G.push("all")
    -- the background: amber, lighter toward the top, broad slanted bands
    G.setColor(0.97, 0.66, 0.1, a)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 0.8, 0.25, 0.35 * a)
    G.rectangle("fill", 0, 0, w, h * 0.45)
    for s = 0, 5 do
      local x0 = w * (0.12 + s * 0.2)
      G.setColor(1, 0.85, 0.35, (s % 2 == 0 and 0.18 or 0.1) * a)
      G.polygon("fill", x0, 0, x0 + w * 0.09, 0, x0 - w * 0.12, h, x0 - w * 0.21, h)
    end
    -- the purple strip along the foot
    G.setColor(0.6, 0.26, 0.62, a)
    G.rectangle("fill", 0, h * 0.92, w, h * 0.08)
    G.setColor(0.45, 0.12, 0.45, 0.6 * a)
    G.polygon("fill", w * 0.05, h * 0.955, w * 0.3, h * 0.945, w * 0.32, h * 0.95, w * 0.07, h * 0.962)
    -- the black bar and the title tab
    local b = Bosses[r.key]
    local name = b and b.name or "It"
    local th = r.throw
    local title = (th and th.caught) and ("You caught %s!"):format(name) or ("You defeated %s!"):format(name)
    G.setColor(0, 0, 0, a)
    G.rectangle("fill", 0, 0, w, h * 0.06)
    G.polygon("fill", w * 0.43, h * 0.06, w, h * 0.06, w, h * 0.125, w * 0.46, h * 0.125)
    local fT = font(h * 0.042)
    G.setFont(fT)
    G.setColor(1, 1, 1, a)
    G.printf(title, w * 0.47, h * 0.093 - fT:getHeight() / 2, w * 0.52, "center")
    -- the boss's stars, popping in one by one
    local stars = b and b.stars or 1
    local ss = h * 0.058
    for i = 1, stars do
      local pop = min(1, max(0, (v - C.IN_S - (i - 1) * C.STAR_S) / 0.15))
      if pop > 0 then
        local sz = ss * (pop < 1 and (1.4 - 0.4 * pop) or 1)
        local cx = w * (C.LIST_X + C.LIST_W * 0.5) + (i - (stars + 1) / 2) * ss * 1.1
        G.setColor(1, 1, 1, a * pop)
        Rd.drawStars(G, 1, cx + sz * 0.55, h * 0.19, sz)
      end
    end
    -- the boss on the left, large, still moving
    local img, q = Rd.frameAt(r.key, r.t)
    if img and loaded and loaded.box then
      local box = loaded.box
      local bw, bh2 = box[3] - box[1], box[4] - box[2]
      local k = min(h * 0.62 / bh2, w * 0.4 / bw)
      local bob = h * 0.008 * sin(r.t * 2)
      G.setColor(1, 1, 1, a)
      local HD = mod.hd
      local draw = HD and HD.drawPixel or G.draw
      draw(img, q, w * 0.24, h * 0.56 + bob, 0, k, k, (box[1] + box[3]) / 2, (box[2] + box[4]) / 2)
    end
    -- the items
    local items = out.items or {}
    r.rw = r.rw or { cursor = 1, top = 1 }
    local rw = r.rw
    local n = #items
    local rows = C.ROWS
    if rw.cursor <= n then
      if rw.cursor < rw.top then rw.top = rw.cursor end
      if rw.cursor > rw.top + rows - 1 then rw.top = rw.cursor - rows + 1 end
    end
    local lx, lw, rh = w * C.LIST_X, w * C.LIST_W, h * C.ROW_H
    local fR = font(h * 0.03)
    G.setFont(fR)
    for i = 1, #cardWhere.rows do cardWhere.rows[i] = nil end
    for j = 0, rows - 1 do
      local i = rw.top + j
      local it = items[i]
      if not it then break end
      local ry = h * C.LIST_Y + j * rh
      local sel = rw.cursor == i
      local cy = ry + rh * 0.5
      if sel then
        G.setColor(0, 0, 0, a)
        G.rectangle("fill", lx, cy - rh * 0.36, lw, rh * 0.72, rh * 0.36, rh * 0.36)
        chevron(G, lx - rh * 0.3, cy, rh * 0.4)
      end
      itemIcon(G, it.id, lx + rh * 0.35, cy - rh * 0.3, rh * 0.6)
      G.setColor(sel and 1 or 1, sel and 1 or 1, sel and 1 or 1, a)
      if not sel then G.setColor(1, 1, 1, a) end
      G.print(it.name or "?", lx + rh * 1.05, cy - fR:getHeight() / 2)
      G.print("\195\151", lx + lw * 0.78, cy - fR:getHeight() / 2)
      G.printf(tostring(it.n or 1), lx + lw * 0.8, cy - fR:getHeight() / 2, lw * 0.16, "right")
      cardWhere.rows[j + 1] = { x = lx, y = ry, w = lw, h = rh, i = i }
    end
    -- the scroll bar
    if n > rows then
      local sx, sy, sh = lx + lw + w * 0.012, h * C.LIST_Y + rh * 0.15, rh * rows - rh * 0.3
      G.setColor(0, 0, 0, 0.25 * a)
      G.rectangle("fill", sx, sy, w * 0.004, sh)
      local tH = sh * rows / n
      local tY = sy + (sh - tH) * (rw.top - 1) / max(1, n - rows)
      G.setColor(0.1, 0.1, 0.1, a)
      G.rectangle("fill", sx - w * 0.001, tY, w * 0.006, tH)
    end
    -- Next
    local nx, ny, nw, nh = lx + lw * 0.12, h * 0.845, lw * 0.76, h * 0.058
    local onNext = rw.cursor > n
    G.setColor(onNext and 0 or 1, onNext and 0 or 1, onNext and 0 or 1, a)
    G.rectangle("fill", nx, ny, nw, nh, nh / 2, nh / 2)
    if onNext then chevron(G, nx - nh * 0.32, ny + nh / 2, nh * 0.42) end
    G.setColor(onNext and 1 or 0, onNext and 1 or 0, onNext and 1 or 0, a)
    G.printf("Next", nx, ny + nh / 2 - fR:getHeight() / 2, nw, "center")
    cardWhere.next.x, cardWhere.next.y, cardWhere.next.w, cardWhere.next.h = nx, ny, nw, nh
    G.pop()
  end

  -- the card's cursor: up / down over the items and Next
  function Rd.cardMove(d)
    if not (r and r.rewards) then return end
    r.rw = r.rw or { cursor = 1, top = 1 }
    local n = #(r.rewards.items or {}) + 1
    r.rw.cursor = max(1, min(n, r.rw.cursor + d))
  end

  -- the end card: back to the den, then a circle closing on the middle to black
  Rd.OUTRO = { HOLD = 1.1, CLOSE = 0.75, BLACK = 0.35 }
  function Rd.drawIris(G, w, h, f)
    if f <= 0 then return end
    G.push("all")
    G.setColor(0, 0, 0, 1)
    if f >= 1 then G.rectangle("fill", 0, 0, w, h); G.pop(); return end
    local R0 = sqrt(w * w + h * h) / 2 + 2
    local ri = R0 * (1 - f) * (1 - f * 0.15)
    local cx, cy = w / 2, h / 2
    local N = 72
    for i = 0, N - 1 do
      local a0, a1 = i / N * 2 * pi, (i + 1) / N * 2 * pi
      G.polygon("fill", cx + cos(a0) * ri, cy + sin(a0) * ri, cx + cos(a0) * R0 * 1.2, cy + sin(a0) * R0 * 1.2,
        cx + cos(a1) * R0 * 1.2, cy + sin(a1) * R0 * 1.2, cx + cos(a1) * ri, cy + sin(a1) * ri)
    end
    G.pop()
  end


  -- ------- for drivers

  local view = {}
  function Rd.state()
    view.active = r ~= nil
    view.key = r and r.key or nil
    view.t = r and r.t or nil
    view.phase = r and r.phase or nil
    view.loaded = Rd.loadedKey()
    view.song = r and r.song or nil
    view.summary = r and r.summary == true or false
    view.turn = r and r.turn or nil
    view.actor = r and r.cmd and r.cmd.actor or nil
    view.cursor = r and r.cmd and r.cmd.cursor or nil
    local n = 0
    if r and r.cmd then for _ in pairs(r.cmd.chosen) do n = n + 1 end end
    view.chosen = n
    view.menu = r and r.cmd and r.cmd.menu or nil
    view.caught = r and r.throw and r.throw.caught or nil
    view.rewards = r and r.rewards or nil
    view.cardCursor = r and r.rw and r.rw.cursor or nil
    view.ask = r and r.ask and r.ask.kind or nil
    view.aside = r and r.aside or nil
    return view
  end

  return Rd
end
