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
  local Battle, Sim = deps.Battle, deps.Sim
  local R = N.RAID
  local floor, max, min = math.floor, math.max, math.min

  local Rd = { N = N, Bosses = Bosses, Sprites = Sprites, Scene = Scene }
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
  function Rd.summaryUp() return r ~= nil and r.summary == true end

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
    -- the barrier's pills follow the events (gone once broken)
    if e.kind == "shield" and r.boss then
      r.boss.shieldShown = e.step ~= "break" and { left = e.left, max = e.max } or nil
      if e.step == "hit" and Scene then Scene.shake(0.06, 0.25) end
    end
    if e.kind == "faint" and not e.who.boss then r.shownFaints = (r.shownFaints or 0) + 1 end
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
      if (e.kind == "damage" or e.kind == "residual") and Scene then
        Scene.shake(hit.boss and 0.08 or 0.14, 0.4)
      end
    end
    if e.text then
      Rd.say(e.text)
      r.evDur = #e.text / Rd.MSG.CPS + E.HOLD_S
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
    Rd.close()
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
    if not r or r.summary then return end
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
    if not r or r.summary then return end
    if r.phase == "den" then return drawDen(G, w, h) end
    local img, q = Rd.frameAt(r.key, r.t)
    if img and loaded then
      bossPic.image, bossPic.quad, bossPic.box, bossPic.size = img, q, loaded.box, Rd.sizeOf(r.key)
    end
    for i = 1, 4 do
      local m = r.members[i]
      memberPicsShown[i] = m and m.draw or nil
    end
    if Scene then Scene.draw(G, 0, 0, w, h, r.t, img and bossPic or nil, memberPicsShown) end
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
    end
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
    return view
  end

  return Rd
end
