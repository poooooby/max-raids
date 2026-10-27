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
  local Battle, Sim = deps.Battle, deps.Sim
  local R = N.RAID
  local floor, max, min = math.floor, math.max, math.min

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
      r.bossShow = false
      local i = memberIndex(about)
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

  -- a blow felt (Fx.onImpact): the raid's clock held a moment, the camera jabbed and shaken, the one
  -- struck flashing white and thrown back - all by the blow's power (0..1+, from the HP it takes)
  Rd.IMPACT = { STOP_S = 0.045, STOP_PER = 0.09, KICK = 1.5, KICK_PER = 4.5, SHAKE = 0.04, SHAKE_PER = 0.2 }
  function Rd.impact(T, power)
    if not r then return end
    local I = Rd.IMPACT
    local p = power or 0.5
    r.lastImpact = r.t
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
  if Fx then Fx.onImpact = function(T, power) Rd.impact(T, power) end end
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
        if who and x.kind == "damage" and x.amount then
          local most = max(1, tonumber(who.mon and who.mon.maxHp) or 1)
          seen[who].frac = (seen[who].frac or 0) + x.amount / most
        end
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
        if p then p.frac = t.frac; tg[#tg + 1] = p end
      end
      if from then Fx.move(a.spec, a.type, from, tg, r.t, a.gmax) end
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
    end
    if e.kind == "faint" and not e.who.boss then r.shownFaints = (r.shownFaints or 0) + 1 end
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
      if (e.kind == "damage" or e.kind == "residual") and Scene and not (r.lastImpact and r.t - r.lastImpact < 1.5) then
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

  -- the throw: FLY the arc, SUCK the boss drawn in, DROP to its feet, SPINS slow wobbles of SPIN s
  -- each (the foot fixed, the top circling: a cone, LEAN radians off upright), SHRINK the caught ball
  -- shrinking down; BALL_M its diameter in the scene's units at the boss (a member stands 1.1): a
  -- giant ball, on screen about the size of the party near the camera
  Rd.THROW = { FLY = 0.8, SUCK = 0.6, DROP = 0.4, SPIN = 1.3, SPINS = 3, LEAN = 0.32, SHRINK = 0.5,
    BALL_M = 2.2 }
  local BALL_RGB = {
    ITEM_POKE_BALL = { 0.9, 0.15, 0.15 }, ITEM_GREAT_BALL = { 0.2, 0.45, 0.95 }, ITEM_ULTRA_BALL = { 0.95, 0.8, 0.15 },
    ITEM_MASTER_BALL = { 0.55, 0.25, 0.75 }, ITEM_PREMIER_BALL = { 0.95, 0.95, 0.95 }, ITEM_LUXURY_BALL = { 0.15, 0.15, 0.18 },
    ITEM_NET_BALL = { 0.2, 0.75, 0.75 }, ITEM_DIVE_BALL = { 0.3, 0.6, 0.95 }, ITEM_NEST_BALL = { 0.55, 0.8, 0.2 },
    ITEM_REPEAT_BALL = { 0.95, 0.5, 0.15 }, ITEM_TIMER_BALL = { 0.95, 0.95, 0.95 },
  }

  -- the choice: the balls the bag holds (three at most), and not catching it
  function Rd.startCatch()
    r.phase = "catch"
    r.events, r.rows, r.bossShow = nil, {}, true
    if r.boss then r.boss.shieldShown = nil end
    local balls = Rewards.balls()
    local b = Bosses[r.key]
    r.cmd = { menu = "balls", cursor = 1, moveList = {}, chosen = {} }
    for i = 1, min(3, #balls) do
      local bl = balls[i]
      r.cmd.moveList[i] = { name = bl.name, chip = "Ball", right = "x" .. bl.n, rgb = BALL_RGB[bl.key],
        live = true, ball = bl, eff = nil }
      r.cmd.moveList[i].chip = ("%d%%"):format(Rewards.chance(b and b.stars or 1, bl.mult))
    end
    r.cmd.moveList[#r.cmd.moveList + 1] = { name = "Don't catch", chip = "Leave", right = "",
      rgb = { 0.5, 0.5, 0.55 }, live = true, leave = true }
    if Scene then Scene.shot("field", 0.8) end
    if #balls == 0 then
      Rd.say("You don't have any Pok\195\169 Balls...")
    else
      Rd.say(("Will you try to catch %s?"):format(b and b.name or "it"))
    end
    return true
  end

  -- a row of the choice picked: the throw, or straight to the rewards
  function Rd.pickBall(slot)
    if not (r and r.phase == "catch") then return false end
    local row = r.cmd.moveList[slot or 0]
    if not row then return false end
    if row.leave or not row.ball then return Rd.startRewards() end
    local level = r.boss and r.boss.mon.level or 20
    local caught, info = Rewards.throw(r.key, level, row.ball, r.rng)
    r.throw = { t0 = r.t, caught = caught, info = type(info) == "table" and info or nil, ball = row.ball,
      rgb = BALL_RGB[row.ball.key] or BALL_RGB.ITEM_POKE_BALL, said = {} }
    r.phase = "throw"
    r.say = nil
    -- (past the party onto the boss's pad: the ball's arc, the drop to its feet, the wobbles)
    if Scene then Scene.shot("catch", 0.6) end
    return true
  end

  -- the throw's timeline (update step): the arc, the boss drawn in, the drop, the wobbles, the outcome
  local function throwTimes()
    local T = Rd.THROW
    local inAt = T.FLY
    local dropAt = inAt + T.SUCK
    local spinAt = dropAt + T.DROP
    local endAt = spinAt + T.SPIN * T.SPINS
    return inAt, dropAt, spinAt, endAt
  end
  Rd.throwTimes = throwTimes
  local function stepThrow()
    local T, th = Rd.THROW, r.throw
    local u = r.t - th.t0
    local inAt, dropAt, _, endAt = throwTimes()
    -- the boss drawn into the ball, then (broken free) out again and gone
    if u < inAt then r.shrink = 1
    elseif u < dropAt then r.shrink = 1 - (u - inAt) / T.SUCK
    else r.shrink = 0 end
    local b = Bosses[r.key]
    local name = b and b.name or "It"
    if u >= endAt and not th.said.out then
      th.said.out = true
      if th.caught then
        Rd.say(("Gotcha! %s was caught!"):format(name))
      else
        Rd.say(("Oh no! %s broke free!"):format(name))
        th.burstAt = r.t
      end
    end
    if th.burstAt then
      local v = r.t - th.burstAt
      r.shrink = v < 0.4 and (v / 0.4) or math.max(0, 1 - (v - 1.6) / 0.6)
    end
    local holdUntil = endAt + T.SHRINK + (#(r.say or "") / Rd.MSG.CPS) + 1.0 + (th.caught and 0 or 2.2)
    if th.caught and th.info and th.info.toPC and u >= holdUntil and not th.said.pc then
      th.said.pc = true
      th.pcAt = u
      Rd.say(("%s was sent to the PC."):format(name))
    end
    if not th.caught and u >= endAt + 2.0 and not th.said.gone then
      th.said.gone = true
      Rd.say(("%s disappeared..."):format(name))
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

  function Rd.endRewards()
    if not (r and r.phase == "rewards") or r.t - (r.rewardsT or 0) < 0.5 then return false end
    return Rd.startAfter()
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

  function Rd.input(input)
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
      local n = #r.cmd.moveList
      if input:wasPressed("up") then r.cmd.cursor = (r.cmd.cursor - 2) % n + 1
      elseif input:wasPressed("down") then r.cmd.cursor = r.cmd.cursor % n + 1
      elseif input:wasPressed("a") then Rd.pickBall(r.cmd.cursor)
      elseif input:wasPressed("b") then Rd.pickBall(n) end
    elseif r.phase == "rewards" then
      if input:wasPressed("a") or input:wasPressed("b") then Rd.endRewards() end
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
  function Rd.pointer(ev)
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
      if ev.phase == "released" then Rd.endRewards() end
      return true
    end
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
    if r and r.phase == "catch" and Pad and not deps.padOnSecond() then
      local hit = Pad.hit(ev.x, ev.y, "balls")
      if hit and hit ~= "panel" then
        local slot = tonumber(hit:match("^move(%d)$") or "")
        if slot then r.cmd.cursor = slot end
        if ev.phase == "released" then
          if hit == "back" then Rd.pickBall(#r.cmd.moveList) elseif slot then Rd.pickBall(slot) end
        end
      end
      return hit ~= nil
    end
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
      G.polygon("fill", starPts)
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
    if r.phase == "rewards" or r.phase == "after" or (r.throw and (r.shrink or 1) < 0.5) then a = 0 end
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
    end
    if Scene then Scene.draw(G, 0, 0, w, h, r.t, img and bossPic or nil, memberPicsShown) end
    if Fx and r.phase ~= "rewards" then
      local LB = Scene and Scene.lastBoss
      if r.fieldShown then Fx.drawField(G, w, h, r.t, r.fieldShown) end
      if r.boss and (r.boss.veil or 0) > 0 and not r.throw then Fx.drawVeil(G, LB, r.t) end
      local sh = r.boss and r.boss.shieldShown
      if sh and not r.throw then Fx.drawBarrier(G, LB, r.t, sh.left, sh.max) end
      Fx.drawMoves(G, r.t)
      Fx.draw(G, w, h, r.t)
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
      if Pad and not deps.padOnSecond() then Pad.draw(G, w, h, r) end
    elseif r.phase == "throw" then
      Rd.drawThrow(G, w, h)
    elseif r.phase == "rewards" then
      Rd.drawRewards(G, w, h)
    elseif r.phase == "after" then
      if r.ask and r.ask.kind == "yesno" and Pad and not deps.padOnSecond() then Pad.draw(G, w, h, r) end
    end
  end

  -- a ball standing on its foot (x, foot): its top in the ball's colour, the white bottom, the black
  -- band and button. lean tips it about its foot; tilt (-1..1) bows the band as its top comes toward
  -- (+) or goes away from (-) the camera - together a wobble round a cone
  local function drawBall(G, x, foot, rad, lean, tilt, rgb)
    G.push()
    G.translate(x, foot)
    G.rotate(lean or 0)
    G.translate(0, -rad)
    G.setColor(1, 1, 1, 1)
    G.circle("fill", 0, 0, rad, 40)
    G.setColor(rgb[1], rgb[2], rgb[3], 1)
    -- the coloured top, down to the band (bowed by the tilt)
    local bow = rad * 0.32 * (tilt or 0)
    local pts = {}
    for k = 0, 24 do
      local a = math.pi + k * math.pi / 24
      pts[#pts + 1], pts[#pts + 2] = math.cos(a) * rad, math.sin(a) * rad
    end
    for k = 24, 0, -1 do
      local a = k * math.pi / 24
      pts[#pts + 1], pts[#pts + 2] = -math.cos(a) * rad, math.sin(a) * bow
    end
    -- (upright, the band straight: a plain half; tipped, the bowed shape)
    if math.abs(bow) < rad * 0.03 then
      G.arc("fill", "pie", 0, 0, rad, math.pi, 2 * math.pi, 32)
    else
      local ok, tris = pcall(love.math.triangulate, pts)
      if ok then for _, tr in ipairs(tris) do G.polygon("fill", tr) end
      else G.arc("fill", "pie", 0, 0, rad, math.pi, 2 * math.pi, 32) end
    end
    G.setColor(0.08, 0.08, 0.1, 1)
    G.setLineWidth(max(1, rad * 0.12))
    local band = {}
    for k = 0, 24 do
      local a = k * math.pi / 24
      band[#band + 1], band[#band + 2] = -math.cos(a) * rad, math.sin(a) * bow
    end
    G.line(band)
    G.circle("line", 0, 0, rad, 40)
    local by = bow
    G.setColor(1, 1, 1, 1)
    G.circle("fill", 0, by, rad * 0.26, 20)
    G.setColor(0.08, 0.08, 0.1, 1)
    G.circle("line", 0, by, rad * 0.26, 20)
    G.circle("line", 0, by, rad * 0.14, 16)
    G.setLineWidth(1)
    G.pop()
  end

  -- the throw: a giant ball (half a person, at the boss's distance) arcs from the foot of the screen,
  -- takes the boss in (a red flash), drops to its feet and wobbles slowly round a cone, three times;
  -- caught, it clicks and shrinks down with a burst of stars
  function Rd.drawThrow(G, w, h)
    local th = r.throw
    if not th then return end
    local T = Rd.THROW
    local u = r.t - th.t0
    local inAt, dropAt, spinAt, endAt = throwTimes()
    local LB = Scene and Scene.lastBoss
    local tx, ty = LB and LB.x or w / 2, LB and LB.y or h * 0.45
    local feet = LB and (LB.y + LB.h * 0.5) or h * 0.7
    -- its size: BALL_M scene units at the boss's distance (the boss's drawn height is its size x a member's)
    local ppm = LB and LB.h and LB.h / ((Scene.MEMBER_H or 1.1) * Rd.sizeOf(r.key)) or h * 0.06
    local rad = ppm * T.BALL_M / 2
    local x, foot, lean, tilt, k = tx, ty + rad, 0, 0, 1
    if u < inAt then
      -- from near the camera: larger, settling to its size
      local f = u / inAt
      k = 1 + 1.6 * (1 - f)
      x = w * 0.5 + (tx - w * 0.5) * f
      foot = h * 1.1 + (ty + rad - h * 1.1) * f - h * 0.3 * math.sin(math.pi * f)
      lean = f * 9
    elseif u < dropAt then
      local f = (u - inAt) / T.SUCK
      G.setColor(1, 0.25, 0.3, 0.55 * (1 - f))
      G.circle("fill", tx, ty, rad * (1.4 + 2.5 * f), 40)
    elseif u < spinAt then
      local f = (u - dropAt) / T.DROP
      foot = ty + rad + (feet - ty - rad) * f * f
    else
      foot = feet
      if u < endAt then
        -- the wobble: the top circles round, slowly, SPINS times
        local phi = (u - spinAt) / T.SPIN * 2 * math.pi
        local ease = math.sin(math.min(1, (u - spinAt) / 0.3) * math.pi / 2)
        lean = T.LEAN * ease * math.sin(phi)
        tilt = ease * math.cos(phi)
      end
    end
    -- broken free: the ball bursts open and is gone
    if th.burstAt then
      local v = r.t - th.burstAt
      if v < 0.5 then
        G.setColor(1, 1, 1, 0.8 * (1 - v / 0.5))
        G.circle("fill", x, foot - rad, rad * (1 + v * 6), 40)
      end
      return
    end
    -- caught: it shrinks down after the click
    if th.said.out and th.caught then
      local v = u - endAt
      k = math.max(0.3, 1 - 0.7 * math.min(1, v / T.SHRINK))
      for s = 0, 5 do
        local a = s * math.pi / 3 + v * 2
        local d = rad * k * (1.3 + v * 2.5)
        G.setColor(1, 0.9, 0.3, math.max(0, 1 - v))
        drawStars(G, 1, x + math.cos(a) * d + rad * 0.25, foot - rad * k + math.sin(a) * d, rad * 0.5)
      end
    end
    drawBall(G, x, foot, rad * k, lean, tilt, th.rgb)
  end

  -- the rewards card: what was caught, the items, each of the four's Exp, levels, moves and EVs
  function Rd.drawRewards(G, w, h)
    local out = r.rewards
    if not out then return end
    G.setColor(0, 0, 0, 0.55)
    G.rectangle("fill", 0, 0, w, h)
    local cw = min(w * 0.86, h * 1.15)
    local fT, fB, fS = font(h * 0.045), font(h * 0.03), font(h * 0.024)
    local lineH = fB:getHeight() * 1.25
    local rows = #out.items + #out.team * 2 + 4
    local ch = min(h * 0.92, lineH * rows + h * 0.12)
    local cx, cy = (w - cw) / 2, (h - ch) / 2
    G.setColor(0.13, 0.13, 0.15, 0.97)
    G.rectangle("fill", cx, cy, cw, ch, h * 0.02, h * 0.02)
    G.setColor(0.93, 0.18, 0.42, 1)
    G.rectangle("fill", cx, cy, cw, h * 0.075, h * 0.02, h * 0.02)
    G.rectangle("fill", cx, cy + h * 0.05, cw, h * 0.025)
    G.setFont(fT)
    G.setColor(1, 1, 1, 1)
    G.printf("Rewards", cx, cy + (h * 0.075 - fT:getHeight()) / 2, cw, "center")
    local x, y = cx + h * 0.04, cy + h * 0.1
    G.setFont(fB)
    local th = r.throw
    if th and th.caught then
      G.setColor(1, 0.85, 0.3, 1)
      local b = Bosses[r.key]
      G.print(("%s was caught!"):format(b and b.name or "It"), x, y)
      y = y + lineH
    end
    local bonus = {}
    if out.firstWin then bonus[#bonus + 1] = "first win x2" end
    if r.sim and r.sim.faints == 0 then bonus[#bonus + 1] = "no knock-outs x1.5" end
    if #bonus > 0 then
      G.setFont(fS)
      G.setColor(0.6, 0.85, 1, 1)
      G.print("Bonus: " .. table.concat(bonus, ", "), x, y)
      y = y + lineH
      G.setFont(fB)
    end
    for _, it in ipairs(out.items) do
      G.setColor(1, 1, 1, 1)
      G.print(("%s  x%d"):format(it.name, it.n), x, y)
      y = y + lineH
    end
    y = y + lineH * 0.3
    local stat = Rewards and Rewards.STAT_WORD[out.evStat or "hp"] or ""
    for _, tm in ipairs(out.team) do
      G.setFont(fB)
      G.setColor(1, 1, 1, 1)
      local line = ("%s  +%d Exp."):format(tm.name, tm.exp or 0)
      if tm.to and tm.from and tm.to > tm.from then line = line .. ("  Lv. %d -> %d"):format(tm.from, tm.to) end
      G.print(line, x, y)
      y = y + lineH
      G.setFont(fS)
      G.setColor(0.75, 0.75, 0.8, 1)
      local sub = {}
      if (tm.evs or 0) > 0 then sub[#sub + 1] = ("+%d %s EVs"):format(tm.evs, stat) end
      if #sub > 0 then G.print("   " .. table.concat(sub, "   "), x, y) end
      y = y + lineH * 0.9
    end
    G.setFont(fS)
    G.setColor(0.7, 0.7, 0.75, 1)
    G.printf("A: Continue", cx, cy + ch - fS:getHeight() * 1.6, cw - h * 0.04, "right")
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
    view.ask = r and r.ask and r.ask.kind or nil
    view.aside = r and r.aside or nil
    return view
  end

  return Rd
end
