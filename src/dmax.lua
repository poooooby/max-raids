-- Dynamax in the game's own battles (option DYNAMAX): the player's side may Dynamax one Pokemon a
-- battle, with a Dynamax Band in the Bag, in the battles the option names (src/dmax_rules.lua); a
-- League trainer Dynamaxes its last Pokemon there, once, while the player has the band.
-- It works on the engine's battle from outside, through wraps installed at game.ready:
--   Commands.playerAction       a move chosen while Dynamax is picked (or on) is its Max Move; the
--                               slot stays, so the base move pays the PP
--   Engine.planTurnFromActions  the Dynamax itself, an action of its own before the first move (the
--                               foe's ace's too, its AI's move made its Max Move there)
--   / planTurnActions           (singles / doubles); Encore, Disable, Torment and Choice's lock off
--   Engine.resolveMove          the Dynamax action (HP and max HP x the Dynamax Level's), a base
--                               move turned to its Max Move; the look: the base move's
--   Hit.run                     the Max Move's power from the base move's, a quarter through Protect,
--                               then its effects (stats on a side, weather, terrain, the G-Max ones)
--   Damage.calc                 that quarter, the veil (G-Max Resonance), the anti-Dynamax moves
--   Engine.forEachTarget        the moves that fail on a Dynamaxed Pokemon; never flinching
--   Engine.performSwitch        never forced out (Roar, Whirlwind, Dragon Tail, Circle Throw)
--   Engine.moveEndBookkeeping   the last move used is the base move (Mirror Move, Mimic, Spite)
--   Engine.switchOutEffects     the Dynamax ends at a switch
--   Engine.switchInEffects      G-Max Steelsurge's spikes
--   Engine.checkEnd, Battle     every Dynamax undone before the party is written back
--   .start's onDone, the faint
--   Experience.apply            a level gained while Dynamaxed
--   Residuals                   the 3 turns' end ("mr_dynamax"), the G-Max fields ("mr_gmax_field")
-- Every wrap passes straight through outside a battle with the option off.
local floor, max, min = math.floor, math.max, math.min

return function(mod, deps)
  local D = deps.data
  local R = deps.rules
  local Bt = deps.battle
  local Gmax = deps.gmax or {}
  local function plain(s, ...) if select("#", ...) > 0 then return s:format(...) end return s end
  local T = deps.T or setmetatable({ game = plain, cgame = function(_, s, ...) return plain(s, ...) end },
    { __call = function(_, s, ...) return plain(s, ...) end })
  local dex = deps.dex or function() return nil end
  local modeOf = deps.mode or function() return "league" end
  local Dm = { vis = {}, sel = {}, installed = false, data = D }

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local function warn(fmt, ...) if mod.log then mod.log:warn(fmt, ...) end end

  -- ------- the moves

  local rows, byKey = nil, nil
  local byNum = {}        -- registered number -> row
  Dm.byNum = byNum
  function Dm.register()
    if R.setGmaxTypes then R.setGmaxTypes(Gmax.MOVES) end
    rows, byKey = R.rows()
    local moves = mod.content and mod.content.moves
    if not moves then return 0 end
    local n = 0
    for _, row in ipairs(rows) do
      local ok, err = pcall(function()
        moves:register(row.id, { id = row.id, name = row.name, index = row.index, type = row.type, power = row.power,
          accuracy = row.accuracy, pp = row.pp, effect = row.effect, secondaryChance = 0, target = row.target,
          priority = row.priority, flags = row.flags })
      end)
      if ok then
        n = n + 1
        byNum[row.index] = row
      else
        warn("dynamax: %s not registered (%s)", row.id, tostring(err))
      end
    end
    return n
  end
  function Dm.num(key) local row = byKey and byKey[key] return row and row.index or nil end
  function Dm.isMax(num) local row = byNum[tonumber(num) or -1] return row ~= nil and not row.internal end

  -- ------- the engine

  local E = {}
  local function engine()
    if E.Engine then return E end
    E.Engine = req("src.core.game3.battle.engine")
    E.State = req("src.core.game3.battle.state")
    E.Commands = req("src.core.game3.battle.commands")
    E.Moves = req("src.core.game3.battle.moves")
    E.Battle = req("src.core.game3.battle")
    E.Anim = req("src.core.game3.battle.anim")
    E.Experience = req("src.core.game3.battle.experience")
    E.Hit = req("src.core.game3.battle.effects.hit")
    E.Damage = req("src.core.game3.battle.damage")
    E.Residuals = req("src.core.game3.battle.residuals")
    E.Rules = req("src.core.game3.battle.rules")
    E.Secondary = req("src.core.game3.battle.effects.secondary")
    E.Hazards = req("src.core.game3.battle.effects.hazards")
    E.Profile = req("src.core.game3.battle.profile")
    E.Kinds = req("src.core.game3.battle.kinds")
    E.Types = req("src.core.game3.battle.types")
    E.ModBattle = req("src.core.game3.battle.mod_registries")
    E.Bag = req("src.core.game3.bag")
    E.Runtime = req("src.core.game3.runtime")
    E.Items = req("src.core.game3.items_data")
    E.Audio = req("src.core.game3.audio")
    E.Pokemon = req("src.core.game3.pokemon")
    return E
  end
  Dm.E = E

  local STRUGGLE = 165
  local function numOf(mv)
    if type(mv) == "table" then mv = mv.numId or mv.id end
    local n = tonumber(mv)
    if n then return n end
    if type(mv) == "string" and E.Moves and E.Moves.numForName then
      local ok, v = pcall(E.Moves.numForName, mv)
      if ok then return tonumber(v) end
    end
    return nil
  end
  local function battlerOf(st, who)
    if type(who) == "table" then return E.State.occupant(st, who) or who end
    if type(who) == "number" then return E.State.battler(st, who) end
    if type(who) == "string" and st then return st[who] end
    return nil
  end
  local function idOf(b) local ok, id = pcall(E.State.idOf, b) return ok and id or nil end
  local function nameOf(ad, b)
    local ok, n = pcall(E.State.prefixedName, ad._st, b)
    if ok and n then return n end
    return ad:displayName(b)
  end
  local function dx() local d = dex() return d and d.dynamax or nil end
  -- WoobleDex's battle field (its exports.battle, 1.19.3 on): terrains, Gravity, hazards, Aurora Veil,
  -- moves that ignore abilities, the Move Split's classes; an older one has none (our own below)
  local function bx() local d = dex() local b = d and d.battle return type(b) == "table" and b or nil end
  -- words to the battle's box: broken at the spaces into lines that fit its width (the game's font
  -- measured; else 26 letters), two lines a page ("\p" between pages, as the game's own); a text
  -- already broken is kept
  local Font = nil
  local function widthOf(s)
    if Font == nil then
      local ok, f = pcall(require, "src.ui.game3.frlg_font")
      Font = ok and type(f) == "table" and f.measure and f or false
    end
    if Font then
      local ok, w = pcall(Font.measure, s)
      if ok and tonumber(w) then return tonumber(w) end
    end
    return #s * 7.7
  end
  Dm.BOX_W = 200
  local function wrap(text)
    text = tostring(text or "")
    if text:find("\n", 1, true) then return text end
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if line ~= "" and widthOf(try) > Dm.BOX_W then lines[#lines + 1] = line; line = word else line = try end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local out = ""
    for i, l in ipairs(lines) do
      if i == 1 then out = l elseif i % 2 == 0 then out = out .. "\n" .. l else out = out .. "\\p" .. l end
    end
    return out
  end
  Dm.wrap = wrap

  -- the battle box's words that differ by type (the game's font: each its own line to translate)
  local function fieldWords(t, name)
    if t == "FIRE" then return T.game("%s was surrounded by fire!", name) end
    if t == "WATER" then return T.game("%s got caught in a vortex of water!", name) end
    if t == "GRASS" then return T.game("%s got trapped with vines!", name) end
    return T.game("%s was surrounded by rocks!", name)
  end
  local function fieldHurtWords(t, name)
    if t == "FIRE" then return T.game("%s is burning up within G-Max Wildfire's flames!", name) end
    if t == "WATER" then return T.game("%s is hurt by G-Max Cannonade's vortex!", name) end
    if t == "GRASS" then return T.game("%s is hurt by G-Max Vine Lash's ferocious beating!", name) end
    return T.game("%s is hurt by the rocks thrown out by G-Max Volcalith!", name)
  end
  local function terrainWords(kind)
    if kind == "ELECTRIC" then return T.game("An electric current ran\nacross the battlefield!") end
    if kind == "GRASSY" then return T.game("Grass grew to cover\nthe battlefield!") end
    if kind == "PSYCHIC" then return T.game("The battlefield\ngot weird!") end
    return T.game("Mist swirled around\nthe battlefield!")
  end

  -- ------- who may: the battle (once, at its start) and the Pokemon

  local function classNameOf(st, class)
    if class == nil or not (E.Profile and E.Profile.classNameOf) then return nil end
    local ok, n = pcall(E.Profile.classNameOf, E.Profile.of(st), class)
    if not ok or type(n) ~= "string" then return nil end
    return (n:gsub("^TRAINER_CLASS_", ""))
  end
  function Dm.factsOf(st)
    local classes = {}
    classes[#classes + 1] = classNameOf(st, st.trainerClass)
    if st.trainerB then classes[#classes + 1] = classNameOf(st, st.trainerB.class) end
    local kinds = type(st.kinds) == "table" and st.kinds or {}
    -- (a route with an active den here: POWER SPOTS)
    local spot = false
    if deps.spot then
      local ok, yes = pcall(deps.spot)
      spot = ok and yes == true
    end
    return { wild = st.wild and true or false, classes = classes, flags = st, kinds = kinds, spot = spot }
  end
  -- the battle's Dynamax state: whether the player's side may (allowed), whether the foe's ace does
  -- (foe), each side's once a battle (used, foeUsed), the Dynamaxes of the battle (list)
  function Dm.stateOf(st)
    if type(st) ~= "table" then return nil end
    local S = st.__mr
    if S then return S end
    local facts = Dm.factsOf(st)
    local mode = modeOf()
    S = { allowed = R.battleAllows(mode, facts), foe = R.foeAllows and R.foeAllows(mode, facts) or false,
      used = false, foeUsed = false, list = {}, turn = 0 }
    S.ace = S.foe and R.aceIndex and R.aceIndex(st.foeParty) or nil
    st.__mr = S
    return S
  end

  function Dm.bandId()
    local idx = deps.bandIndex
    return idx
  end
  function Dm.hasBand()
    if deps.hasBand then return deps.hasBand() end
    local s = E.Runtime and E.Runtime.getSession and E.Runtime.getSession()
    local bag = s and s.bag
    local id = Dm.bandId()
    if not (bag and id and E.Bag and E.Bag.has) then return false end
    local ok, has = pcall(E.Bag.has, bag, id, 1)
    return ok and has and true or false
  end

  -- whether b may Dynamax now (why not, as a word, for drivers)
  function Dm.can(st, b)
    local S = Dm.stateOf(st)
    if not (S and S.allowed) then return false, "battle" end
    if S.used then return false, "used" end
    if not b or b.side ~= "player" or b.__mrDmax then return false, "battler" end
    if E.State.isFainted(b) then return false, "fainted" end
    if st.double and E.Kinds and E.Kinds.controllerOf then
      local ok, who = pcall(E.Kinds.controllerOf, st, idOf(b))
      if ok and who and who ~= "player" then return false, "partner" end
    end
    local id = idOf(b)
    for other in pairs(Dm.sel) do if other ~= id then return false, "another" end end
    if b.expLockedMove or (b.expRechargeTurns or 0) > 0 or (b.expBideTurns or 0) > 0 then return false, "locked" end
    local d = dx()
    if d and d.canDynamax then
      local ok, yes = pcall(d.canDynamax, b.mon)
      if ok and yes == false then return false, "species" end
    end
    if not Dm.hasBand() then return false, "band" end
    return true
  end

  -- whether the foe's b Dynamaxes now: a League trainer's ace (its party's last), on the field, the
  -- foe's side not yet Dynamaxed this battle, and only while the player has the band too
  function Dm.foeCan(st, b)
    local S = Dm.stateOf(st)
    if not (S and S.allowed and S.foe and S.ace) then return false, "battle" end
    if S.foeUsed then return false, "used" end
    if not b or b.side ~= "enemy" or b.__mrDmax then return false, "battler" end
    if b.partyIndex ~= S.ace then return false, "not the ace" end
    if E.State.isFainted(b) then return false, "fainted" end
    if b.expLockedMove or (b.expRechargeTurns or 0) > 0 or (b.expBideTurns or 0) > 0 then return false, "locked" end
    local d = dx()
    if d and d.canDynamax then
      local ok, yes = pcall(d.canDynamax, b.mon)
      if ok and yes == false then return false, "species" end
    end
    if not Dm.hasBand() then return false, "band" end
    return true
  end

  -- a foe's ace Gigantamaxes when the raids' art has its species' Gigantamax form (data/raid_bosses.lua
  -- gmax): that form's G-Max Move, kept on its Pokemon for the battle (mon.__mrGmax)
  function Dm.foeGmaxOf(mon)
    local Bosses = deps.bosses
    if not (Bosses and Bosses.ORDER and mon and E.Pokemon and E.Pokemon.national) then return nil end
    local ok, nat = pcall(E.Pokemon.national, mon.species)
    if not ok or not nat then return nil end
    for _, key in ipairs(Bosses.ORDER) do
      local rec = Bosses[key]
      if rec and rec.gmax and tonumber(rec.national) == tonumber(nat) then return rec.gmax, key end
    end
    return nil
  end

  -- ------- a Pokemon's Max Moves

  local function gmaxIdOf(mon)
    if mon and mon.__mrGmax then return mon.__mrGmax end
    local d = dx()
    if not (d and d.canGigantamax and d.gmaxMoveOf) then return nil end
    local ok, yes = pcall(d.canGigantamax, mon)
    if not (ok and yes) then return nil end
    local ok2, id = pcall(d.gmaxMoveOf, mon)
    return ok2 and id or nil
  end
  Dm.gmaxIdOf = gmaxIdOf
  local function levelOf(mon)
    local d = dx()
    if not (d and d.level) then return 0 end
    local ok, v = pcall(d.level, mon)
    return ok and tonumber(v) or 0
  end
  local function multOf(mon, foe)
    local d = dx()
    local lvl = foe and (D.FOE_LEVEL or 10) or levelOf(mon)
    if d and d.hpMult then
      local ok, v = pcall(d.hpMult, lvl)
      if ok and tonumber(v) then return tonumber(v) end
    end
    return 1.5 + 0.05 * lvl
  end

  -- the Max Move a base move becomes for b: its number, its power, Bt.maxOf's record
  function Dm.maxOf(b, base)
    local num = numOf(base)
    if not num or num == 0 or num == STRUGGLE then return num, nil, nil end
    if byNum[num] then return num, nil, nil end
    local mv = Bt.move(num)
    if not mv then return num, nil, nil end
    local key, power, mx = R.maxKey(mv, b and gmaxIdOf(b.mon) or nil, Bt)
    local n = key and Dm.num(key)
    if not n then return num, nil, nil end
    return n, power, mx
  end
  -- b's four as Max Moves (for the move menu): into `out`, reused
  function Dm.maxMovesOf(b, out)
    out = out or {}
    local mon = b and b.mon
    for i = 1, 4 do
      local mv = mon and mon.moves and mon.moves[i]
      if mv and mv ~= 0 and mv ~= "" then out[i] = (Dm.maxOf(b, mv)) or mv else out[i] = mv end
    end
    return out
  end

  -- ------- the Dynamax and its end

  local function visOf(id)
    local v = Dm.vis[id]
    if not v then v = { k = 1, want = 1 } Dm.vis[id] = v end
    return v
  end
  Dm.visOf = visOf

  function Dm.dynamax(st, ad, b)
    local mon = b.mon
    local S = Dm.stateOf(st)
    local baseMax = tonumber(mon.maxHp) or 1
    local foe = b.side == "enemy"
    local mult = multOf(mon, foe)
    local hp0 = tonumber(mon.hp) or 0
    local hp, dynMax = R.up(hp0, baseMax, mult)
    mon.maxHp, mon.hp = dynMax, hp
    local rec = { mon = mon, baseMax = baseMax, dynMax = dynMax, mult = mult, turns = D.TURNS,
      gmax = gmaxIdOf(mon), id = idOf(b) }
    b.__mrDmax = rec
    S.list[#S.list + 1] = rec
    if foe then S.foeUsed = true else S.used = true end
    rec.foe = foe
    -- (Encore, Disable, Torment and a Choice item's lock end; a Dynamaxed Pokemon takes none)
    b.expEncoreMove, b.expEncoreTurns, b.expEncoreSlot = nil, nil, nil
    b.expDisabledMove, b.expDisabledTurns = nil, nil
    b.expTormented, b.torment = nil, nil
    b.choicedMove = nil
    local v = visOf(rec.id)
    v.dynMax, v.baseMax, v.gmax, v.species, v.mon = dynMax, baseMax, rec.gmax, mon.species, mon
    if Dm.onDynamax then pcall(Dm.onDynamax, rec, b) end
    return rec
  end

  -- the Dynamax over: HP back to its share of the base max; `quiet` for a switch / faint / the end;
  -- `keepLook` (a faint): the giant drawn on until the faint's own animation (Anim.faintMon) - the
  -- battle works the turn out before it plays, so it is still giant while the blow that felled it shows
  function Dm.revert(st, ad, b, rec, quiet, keepLook)
    rec = rec or (b and b.__mrDmax)
    if not rec then return end
    local mon = rec.mon
    if rec.done then return end
    rec.done = true
    local hp0 = tonumber(mon.hp) or 0
    local hp = R.down(hp0, rec.dynMax, rec.baseMax)
    mon.maxHp, mon.hp = rec.baseMax, hp
    if b and b.__mrDmax == rec then b.__mrDmax = nil end
    if not quiet and ad and b then
      ad:pushEvent({ kind = "move", moveId = Dm.num("UNDYNAMAX"), attacker = b.side, target = b.side,
        attackerId = idOf(b), targetId = idOf(b), turn = 0 })
      ad:say(T.game("%s's Dynamax\nended!", nameOf(ad, b)))
      ad:pushEvent({ kind = "hp", side = b.side, battler = idOf(b), from = hp, to = hp, maxHp = rec.baseMax })
    elseif quiet and rec.id ~= nil and not keepLook then
      local v = Dm.vis[rec.id]
      if v then v.want, v.k = 1, 1 end
    end
  end

  -- every Dynamax of the battle undone (before the party is written back)
  function Dm.revertAll(st, quiet)
    local S = st and st.__mr
    if not S then return end
    for _, rec in ipairs(S.list) do
      if not rec.done then
        local b = nil
        if st.player and st.player.__mrDmax == rec then b = st.player end
        if not b and E.State then
          for id = 0, 3 do
            local bb = E.State.battler(st, id)
            if bb and bb.__mrDmax == rec then b = bb end
          end
        end
        Dm.revert(st, nil, b, rec, true)
      end
    end
  end

  -- the Dynamax action (its own action, before the first move): its words and look, the HP
  local function dynamaxAction(user, ad, st, out)
    out = out or {}
    local b = battlerOf(st, user)
    local prevSay = ad._say
    local mark = ad:eventMark()
    ad._say = function(text) out[#out + 1] = text end
    local anim = { moveId = Dm.num("DYNAMAX"), user = b, target = b, hits = {}, heals = {}, faints = {},
      missed = false, statusOnly = true }
    if b and not E.State.isFainted(b) and not b.__mrDmax and not st.over then
      local before = tonumber(b.mon.hp) or 0
      ad:say(T.game("%s is Dynamaxing!", nameOf(ad, b)))
      ad:pushEvent({ kind = "move", moveId = Dm.num("DYNAMAX"), attacker = b.side, target = b.side,
        attackerId = idOf(b), targetId = idOf(b), turn = 0 })
      local rec = Dm.dynamax(st, ad, b)
      ad:pushEvent({ kind = "hp", side = b.side, battler = idOf(b), from = before, to = b.mon.hp, maxHp = rec.dynMax })
    end
    for k in pairs(Dm.sel) do Dm.sel[k] = nil end
    return E.Engine.finishResolve(ad, st, out, anim, mark, prevSay, true)
  end

  -- the Dynamax action row, before the turn's first move
  local function insertAction(actions, b, id)
    if type(actions) ~= "table" then return end
    local row = { kind = "move", user = b, target = b, battler = id, move = Dm.num("DYNAMAX"), slot = nil,
      mrDynamax = true }
    for i, a in ipairs(actions) do
      if a.kind == "move" and not a.mrDynamax then table.insert(actions, i, row) return end
    end
    actions[#actions + 1] = row
  end

  -- ------- the Max Moves' effects (after the hit)

  local function foesOf(st, b)
    local ok, list = pcall(E.State.foes, st, b)
    if ok and type(list) == "table" then return list end
    return { b.side == "player" and st.enemy or st.player }
  end
  local function sideOf(st, b)
    local out = { b }
    local ok, p = pcall(E.State.partner, st, b)
    if ok and p and not E.State.isFainted(p) then out[2] = p end
    return out
  end
  local function typeNumOf(name) return Bt.typeNum and Bt.typeNum(name) or nil end
  local function hasType(ad, b, name)
    local t = typeNumOf(name)
    if not t then return false end
    local ok, r = pcall(ad.hasType, ad, b, t)
    return ok and r or false
  end
  local function stage(M, who, stat, n)
    if not (E.Secondary and who and not E.State.isFainted(who)) then return end
    pcall(E.Secondary.changeStat, M.adapter, who, stat, n, { allowPtr = true, user = who == M.user })
  end
  local function field(st)
    st.__ndxField = st.__ndxField or {}
    return st.__ndxField
  end
  local function sideData(side)
    side.__ndx = side.__ndx or {}
    return side.__ndx
  end
  local function inflict(M, who, status)
    if not (E.ModBattle and E.ModBattle.inflict) or E.State.isFainted(who) then return end
    pcall(E.ModBattle.inflict, M, who, status, { secondary = true })
  end
  local function confuse(M, who)
    if not E.Secondary or E.State.isFainted(who) then return end
    local prev = M.target
    M.target = who
    pcall(E.Secondary.set, M, "CONFUSION", false, false, false)
    M.target = prev
  end

  local function gmaxEffect(M, gid, rec)
    local ad, st, user = M.adapter, M.st, M.user
    local g = Gmax.MOVES and Gmax.MOVES[gid] or {}
    local fx = g.effect or {}
    local foes = foesOf(st, user)
    if fx.kind == "field" then
      -- (each turn's end, 1/6 to the foes not of its type, 4 turns: "mr_gmax_field")
      local side = ad:foeSide(user)
      if side and not sideData(side).mrField then
        sideData(side).mrField = { type = g.type, turns = fx.turns or 4, frac = fx.frac or 6, spare = fx.spare, id = gid }
        local t = M.target or foes[1]
        -- (its look on each foe it surrounds, then the words)
        for _, f in ipairs(foes) do
          if not E.State.isFainted(f) and not hasType(ad, f, fx.spare) then
            ad:playAnim("general", "TURN_TRAP", f, f, D.TRAP_LOOK[g.type] or 83)
          end
        end
        if t then ad:say(wrap(fieldWords(g.type, nameOf(ad, t)))) end
      end
    elseif fx.kind == "trap" then
      local t = M.target
      if t and not E.State.isFainted(t) and (t.expTrapTurns or 0) <= 0 then
        t.expTrapTurns, t.expTrapMove, t.expTrapSource, t.wrapped = fx.turns or 4, M.mnum, user, true
        t.__mrTrapFrac = fx.frac or 8
        ad:say(T.game("%s became trapped!", nameOf(ad, t)))
      end
    elseif fx.kind == "status" then
      for _, f in ipairs(foes) do
        local list = fx.list or {}
        local s = list[#list == 1 and 1 or (ad:roll(1, #list))]
        if s then inflict(M, f, s) end
      end
    elseif fx.kind == "drowsy" then
      local t = M.target
      if t and not E.State.isFainted(t) and not ad:status(t) and ad:roll(1, 100) <= (fx.chance or 50)
          and (t.expYawnTurns or 0) <= 0 then
        t.expYawnTurns, t.yawnTurns = 2, 2
        ad:say(T.game("%s grew drowsy!", nameOf(ad, t)))
      end
    elseif fx.kind == "stages" then
      for _, f in ipairs(foes) do
        for stat, n in pairs(fx.foe or {}) do stage(M, f, stat, n) end
      end
    elseif fx.kind == "pp" then
      local t = M.target
      local last = t and numOf(t.lastMoveId or t.lastMove)
      if last and t.mon and t.mon.moves and t.mon.pp then
        for i = 1, 4 do
          if numOf(t.mon.moves[i]) == last and (tonumber(t.mon.pp[i]) or 0) > 0 then
            t.mon.pp[i] = max(0, (tonumber(t.mon.pp[i]) or 0) - (fx.n or 2))
            ad:say(T.game("%s's PP was\nreduced!", nameOf(ad, t)))
            break
          end
        end
      end
    elseif fx.kind == "gravity" then
      local B = bx()
      if B and B.startGravity then
        B.startGravity(ad, fx.turns or 5)
      else
        local f = field(st)
        if (f.gravity or 0) <= 0 then
          f.gravity = fx.turns or 5
          ad:say(T.cgame("battle", "Gravity intensified!"))
        end
      end
    elseif fx.kind == "veil" then
      -- (WoobleDex's Aurora Veil, its damage and its end; else ours)
      local side = ad:ownSide(user)
      local B = bx()
      if side and B and B.startAuroraVeil then
        B.startAuroraVeil(ad, side, fx.turns or 5)
      elseif side and (sideData(side).mrVeil or 0) <= 0 then
        sideData(side).mrVeil = fx.turns or 5
        ad:say(T.game("Aurora Veil made your team\nstronger against attacks!"))
      end
    elseif fx.kind == "heal" then
      for _, a in ipairs(sideOf(st, user)) do
        if not E.State.isFainted(a) and ad:hp(a) < ad:maxHp(a) then
          ad:heal(a, max(1, floor(ad:maxHp(a) / (fx.frac or 6))))
          ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = a })
        end
      end
    elseif fx.kind == "cure" then
      for _, a in ipairs(sideOf(st, user)) do
        if not E.State.isFainted(a) and ad:status(a) then
          ad:clearStatus(a)
          ad:say(T.game("%s's status returned\nto normal!", nameOf(ad, a)))
        end
      end
    elseif fx.kind == "crit" then
      local side = ad:ownSide(user)
      if side then
        local d = sideData(side)
        d.mrCrit = min(3, (d.mrCrit or 0) + (fx.n or 1))
        ad:say(T.game("Your team is getting\npumped!"))
      end
    elseif fx.kind == "defog" then
      local side = ad:foeSide(user)
      if side then
        side.expReflectTurns, side.expLightScreenTurns, side.expSafeguardTurns, side.expMistTurns = 0, 0, 0, 0
        if side.__ndx then side.__ndx.auroraVeil = nil end
      end
      local B = bx()
      for _, s in ipairs({ ad:ownSide(user), ad:foeSide(user) }) do
        if s and E.Hazards and E.Hazards.clear then pcall(E.Hazards.clear, s) end
        if s and B and B.clearHazards then B.clearHazards(s) end
        if s and s.__ndx then
          s.__ndx.stealthRock, s.__ndx.toxicSpikes, s.__ndx.stickyWeb, s.__ndx.mrSteelsurge = nil, nil, nil, nil
        end
      end
      local f = st.__ndxField
      if f then f.terrainTurns = 0 end
      ad:say(T.game("The opposing side's barriers\nwere blown away!"))
    elseif fx.kind == "coins" then
      local lvl = tonumber(user.mon and user.mon.level) or 50
      rec.coins = min(3, (rec.coins or 0) + 1)
      st.payDayCoins = min(0xFFFF, (st.payDayCoins or 0) + lvl * 100 * rec.coins)
      ad:say(T.game("Coins were scattered\neverywhere!"))
    end
    local B = bx()
    if gid == "STONESURGE" and B and B.setHazard then
      local side = ad:foeSide(user)
      if side then B.setHazard(ad, side, "stealthRock") end
    elseif gid == "STONESURGE" then
      local side = ad:foeSide(user)
      if side and not sideData(side).stealthRock then
        sideData(side).stealthRock = true
        ad:say(T.game("Pointed stones float in the air\naround the foe's team!"))
      end
    elseif gid == "STEELSURGE" then
      local side = ad:foeSide(user)
      if side and not sideData(side).mrSteelsurge then
        sideData(side).mrSteelsurge = true
        ad:say(T.game("Sharp-pointed pieces of steel\nstarted floating around the foe!"))
      end
    elseif gid == "TERROR" then
      for _, f in ipairs(foes) do
        if not E.State.isFainted(f) and not f.expTrapped then
          f.expTrapped, f.expTrappedBy = true, user
          ad:say(T.game("%s can no longer\nescape!", nameOf(ad, f)))
        end
      end
    elseif gid == "REPLENISH" then
      for _, a in ipairs(sideOf(st, user)) do
        local lost = a.expLostItem or a.lostItem
        if lost and (tonumber(a.item) or 0) == 0 and ad:roll(1, 2) == 1 then
          a.item, a.expLostItem, a.lostItem = lost, nil, nil
          if a.mon then a.mon.heldItem = lost end
          ad:say(T.game("%s found one\nof its berries!", nameOf(ad, a)))
        end
      end
    end
    if fx.confuse then for _, f in ipairs(foes) do confuse(M, f) end end
    if fx.attract then
      for _, f in ipairs(foes) do
        local prev = M.target
        M.target = f
        pcall(E.Secondary.set, M, "ATTRACT", false, false, false)
        M.target = prev
      end
    end
    if fx.torment then
      for _, f in ipairs(foes) do
        if not E.State.isFainted(f) and not f.__mrDmax and not f.expTormented then
          f.expTormented, f.torment = true, true
          ad:sayText("STRINGID_PKMNSUBJECTEDTOTORMENT", { def = f })
        end
      end
    end
  end

  local function maxEffect(M, mx, rec)
    local ad, st, user = M.adapter, M.st, M.user
    if mx.isGmax and mx.key and Gmax.MOVES and Gmax.MOVES[mx.key] and not mx.isMax then
      return gmaxEffect(M, mx.key, rec)
    end
    local typeName = mx.typeName
    local w = D.WEATHER[typeName]
    if w then
      local cur = E.Rules and E.Rules.weather and E.Rules.weather.kind and E.Rules.weather.kind(st.weather)
      if not (cur and cur == E.Rules.weather.kind(w.kind)) then
        ad:setWeather(w.kind, 5)
        ad:sayText(w.text)
        if w.anim then ad:playAnim("general", w.anim, nil, nil) end
      end
    end
    local t = D.TERRAIN[typeName]
    local B = bx()
    if t and B and B.startTerrain then
      B.startTerrain(ad, t.kind, user)
    elseif t then
      local f = field(st)
      if not ((f.terrainTurns or 0) > 0 and f.terrain == t.kind) then
        f.terrain, f.terrainTurns = t.kind, 5
        ad:say(terrainWords(t.kind))
      end
    end
    local fx = mx.gmaxEffect
    if fx and fx.kind == "boost" then
      for _, a in ipairs(sideOf(st, user)) do
        for stat, n in pairs(fx.self or {}) do stage(M, a, stat, n) end
      end
    elseif fx and fx.kind == "stages" then
      for _, f in ipairs(foesOf(st, user)) do
        for stat, n in pairs(fx.foe or {}) do stage(M, f, stat, n) end
      end
    end
  end

  -- ------- the wraps

  local quarter = false  -- (a Max Move through Protect: Damage.calc takes a quarter)
  local veilOn = nil     -- (the target's side has G-Max Resonance's veil)
  local doubleOn = false -- (an anti-Dynamax move on a Dynamaxed target)

  -- (a battle where Dynamax may happen; every other battle runs as the game's own)
  local function isOn(st) return type(st) == "table" and st.__mr ~= nil and st.__mr.allowed end

  local CHARGE_EFFECTS = { [39] = true, [75] = true, [145] = true, [151] = true, [155] = true }
  local function rewriteLooks(out, b)
    local anim = out and out._anim
    local events = anim and anim.events
    if not events then return end
    local mon = b and b.mon
    for _, ev in ipairs(events) do
      if ev.kind == "move" and byNum[tonumber(ev.moveId) or -1] and not byNum[tonumber(ev.moveId)].internal then
        local slot = ev.__mrSlot
        local base = slot and mon and mon.moves and mon.moves[slot]
        if byNum[tonumber(ev.moveId)].key == "MAX_GUARD" then base = 182 end
        if base then
          ev.moveId = numOf(base) or ev.moveId
          local okM, def = pcall(E.Moves.get, ev.moveId)
          if okM and def and CHARGE_EFFECTS[tonumber(def.effect) or -1] then ev.turn = 1 end
        end
      end
    end
    if anim.moveId and byNum[tonumber(anim.moveId) or -1] then anim.maxMoveId = anim.moveId end
  end

  function Dm.install()
    -- (the engine's modules looked up afresh: a new game may have loaded them again)
    for k in pairs(E) do E[k] = nil end
    engine()
    if not (E.Engine and E.State and E.Commands and E.Moves and E.Battle) then
      warn("dynamax: the engine's battle was not found; Dynamax stays off")
      return false
    end
    if E.Engine.__mrDmax then Dm.installed = true return true end
    E.Engine.__mrDmax = true
    Dm.installed = true
    local Engine, State, Commands = E.Engine, E.State, E.Commands
    -- (G-Max Drum Solo, Fireball and Hydrosnipe ignore the target's abilities: WoobleDex's list)
    local B = bx()
    if B and B.addMoldMove then
      for _, key in ipairs(D.MOLD) do
        local n = Dm.num(key)
        if n then B.addMoldMove(n) end
      end
    end

    -- a battle's start: its state; its end: every Dynamax undone before the write-back
    local start = E.Battle.start
    E.Battle.start = function(opts, ...)
      if Dm.ui and Dm.ui.dropGiants then pcall(Dm.ui.dropGiants) end
      for k in pairs(Dm.vis) do Dm.vis[k] = nil end
      for k in pairs(Dm.sel) do Dm.sel[k] = nil end
      local a, b2, c = start(opts, ...)
      local st = E.Battle._st
      if st then Dm.stateOf(st) end
      local cb = E.Battle._onDone
      if cb then
        E.Battle._onDone = function(result, st2, ...)
          pcall(Dm.revertAll, st2 or st, true)
          if Dm.ui and Dm.ui.dropGiants then pcall(Dm.ui.dropGiants) end
          for k in pairs(Dm.vis) do Dm.vis[k] = nil end
          return cb(result, st2, ...)
        end
      end
      return a, b2, c
    end

    -- the move chosen: its Max Move when Dynamax is picked or on (the slot kept: the base move's PP)
    local playerAction = Commands.playerAction
    Commands.playerAction = function(st, menuIndex, moveSlot, battlerId, targetId, ...)
      local act = playerAction(st, menuIndex, moveSlot, battlerId, targetId, ...)
      if not (isOn(st) and type(act) == "table" and act.kind == "move") then return act end
      local b = battlerOf(st, battlerId ~= nil and battlerId or "player")
      if not b then return act end
      local id = idOf(b)
      local picked = Dm.sel[id] and Dm.can(st, b)
      if not (picked or b.__mrDmax) then return act end
      local n = Dm.maxOf(b, act.move)
      if n and n ~= numOf(act.move) then
        act.move = n
        local okM, def = pcall(E.Moves.get, n)
        if okM and def and act.targetType ~= nil then act.targetType = tonumber(def.target) or act.targetType end
      end
      if picked then act.dynamax = true end
      return act
    end

    -- the foe's chosen move: its Max Move while Dynamaxed, and when its ace Dynamaxes now (the
    -- action marked, its G-Max form chosen); a Max Move has one target. True when it Dynamaxes now
    local function foeMove(st, b, act)
      if not (b and type(act) == "table" and act.kind == "move" and b.mon) then return false end
      local now = false
      if not b.__mrDmax then
        if not Dm.foeCan(st, b) then return false end
        now = true
        if b.mon.__mrGmax == nil then b.mon.__mrGmax = Dm.foeGmaxOf(b.mon) or false end
      end
      local n = Dm.maxOf(b, act.move)
      if n and n ~= numOf(act.move) then
        act.move = n
        local okM, def = pcall(E.Moves.get, n)
        if okM and def then
          if act.targetType ~= nil then act.targetType = tonumber(def.target) or act.targetType end
          -- (a double battle: one of the player's on the field, the one it aimed at when it still stands)
          if st.double and (tonumber(def.target) or 0) == 0 then
            local t = act.target ~= nil and E.State.battler(st, act.target) or nil
            if not t or t.side ~= "player" or E.State.isFainted(t) then
              local pick = nil
              for _, id in ipairs({ 0, 2 }) do
                local pb = E.State.battler(st, id)
                if pb and not E.State.isFainted(pb) and not (st.absent and st.absent[id]) and (pick == nil or math.random() < 0.5) then
                  pick = id
                end
              end
              if pick ~= nil then act.target = pick end
            end
          end
        end
      end
      if now then
        act.dynamax = true
        b.expEncoreMove, b.expEncoreTurns, b.expDisabledMove, b.choicedMove = nil, nil, nil, nil
      end
      return now
    end
    Dm._foeMove = foeMove

    -- the turn: the Dynamax first
    local planFrom = Engine.planTurnFromActions
    Engine.planTurnFromActions = function(st, ad, playerAct, enemyAct, ...)
      local b = nil
      if isOn(st) and not st.double and type(playerAct) == "table" and playerAct.kind == "move" and playerAct.dynamax then
        b = st.player
        if b and Dm.can(st, b) then
          b.expEncoreMove, b.expEncoreTurns, b.expDisabledMove, b.choicedMove = nil, nil, nil, nil
        else
          b = nil
        end
      end
      -- (the foe's ace, its move chosen)
      local fb = nil
      if isOn(st) and not st.double and type(enemyAct) == "table" and st.enemy and foeMove(st, st.enemy, enemyAct) then
        fb = st.enemy
      end
      local actions, x = planFrom(st, ad, playerAct, enemyAct, ...)
      if b then insertAction(actions, b, 0) end
      if fb then insertAction(actions, fb, 1) end
      return actions, x
    end
    local planActions = Engine.planTurnActions
    if planActions then
      Engine.planTurnActions = function(st, ad, chosen, ...)
        local b, bid = nil, nil
        if isOn(st) and type(chosen) == "table" then
          for id = 0, 3 do
            local act = chosen[id]
            if not b and type(act) == "table" and act.kind == "move" and act.dynamax then
              local bb = State.battler(st, id)
              if bb and Dm.can(st, bb) then
                b, bid = bb, id
                bb.expEncoreMove, bb.expEncoreTurns, bb.expDisabledMove, bb.choicedMove = nil, nil, nil, nil
              end
            end
          end
        end
        -- (the foe's: its ace's Dynamax, the Max Moves of a Dynamaxed one)
        local fb, fid = nil, nil
        if isOn(st) and type(chosen) == "table" then
          for _, id in ipairs({ 1, 3 }) do
            local bb = State.battler(st, id)
            if bb and foeMove(st, bb, chosen[id]) and not fb then fb, fid = bb, id end
          end
        end
        local actions, x = planActions(st, ad, chosen, ...)
        if b then insertAction(actions, b, bid) end
        if fb then insertAction(actions, fb, fid) end
        return actions, x
      end
    end

    -- the Dynamax action; a Dynamaxed Pokemon's move as its Max Move, drawn as the base move
    local resolve = Engine.resolveMove
    Engine.resolveMove = function(user, target, moveId, slot, ad, st, out, opts, ...)
      if not isOn(st) then return resolve(user, target, moveId, slot, ad, st, out, opts, ...) end
      local num = numOf(moveId)
      if num and num == Dm.num("DYNAMAX") then return dynamaxAction(user, ad, st, out) end
      local b = battlerOf(st, user)
      local rec = b and b.__mrDmax
      if not rec or (opts and opts.called) then return resolve(user, target, moveId, slot, ad, st, out, opts, ...) end
      if num and not byNum[num] and slot then
        local n = Dm.maxOf(b, moveId)
        if n then moveId = n end
      end
      -- (the National Dex's Move Split: a Max Move is physical or special as its base move is - its
      -- class read by number, so the base move's put on the Max Move's number for this use)
      if slot and b.mon and b.mon.moves then
        local base, maxN = numOf(b.mon.moves[slot]), numOf(moveId)
        local B = bx()
        if base and maxN and byNum[maxN] then
          if B and B.setMoveClass and B.moveClass then
            B.setMoveClass(maxN, B.moveClass(base))
          else
            local hub = E.Types and E.Types.__ndxSplit
            if hub and type(hub.classes) == "table" then hub.classes[maxN] = hub.classes[base] end
          end
        end
      end
      local mark = ad:eventMark()
      local r = resolve(user, target, moveId, slot, ad, st, out, opts, ...)
      -- (the anim events: the base move's look; the slot read back as the move was used)
      local events = ad:events()
      for i = mark + 1, #events do
        local ev = events[i]
        if ev.kind == "move" and byNum[tonumber(ev.moveId) or -1] then ev.__mrSlot = slot end
      end
      rewriteLooks(r or out, b)
      -- (Max Guard up: it stops more than Protect, until the turn's end)
      if numOf(moveId) == Dm.num("MAX_GUARD") and b.expProtected then b.__mrMaxGuard = true end
      return r
    end

    -- the Max Move's hit: its power, a quarter through Protect, its effects
    local Hit = E.Hit
    local hitRun = Hit and Hit.run
    if hitRun then
      Hit.run = function(M, ...)
        local row = M and byNum[tonumber(M.mnum) or -1]
        local st = M and M.st
        if not (row and isOn(st) and not row.internal) then
          if M and M.target and M.target.__mrDmax and M.st and isOn(M.st) and M.move then
            doubleOn = D.ANTI_DMAX[R.squash(tostring(M.move.id or ""))] or false
            veilOn = M.adapter and M.adapter:ownSide(M.target)
            local r = hitRun(M, ...)
            doubleOn, veilOn = false, nil
            return r
          end
          if M and M.target and M.st and isOn(M.st) and M.adapter then
            veilOn = M.adapter:ownSide(M.target)
            local r = hitRun(M, ...)
            veilOn = nil
            return r
          end
          return hitRun(M, ...)
        end
        local user = M.user
        local base = M.slot and user and user.mon and user.mon.moves and user.mon.moves[M.slot]
        local mv = base and Bt.move(numOf(base))
        local mx = nil
        if mv then
          local _, power, rec = R.maxKey(mv, gmaxIdOf(user.mon), Bt)
          mx = rec
          if power and power > 0 then M.move.power = power end
        end
        local t = M.target
        -- (the Max Moves are not stopped by Protect - flags 0 - but strike through it for a quarter;
        -- One Blow and Rapid Flow whole; Max Guard stops all but those two)
        local protected = t and t ~= user and t.expProtected and true or false
        local pierce = row.key == "ONE_BLOW" or row.key == "RAPID_FLOW"
        if t and t.__mrMaxGuard and not pierce then
          M:attackString()
          M:ppReduce()
          M.anim.statusOnly = true
          M.adapter:sayText("STRINGID_PKMNPROTECTEDITSELF", { def = t })
          return
        end
        quarter = protected and not pierce
        veilOn = M.adapter:ownSide(t)
        local ok, err = pcall(hitRun, M, ...)
        quarter, veilOn = false, nil
        if not ok then error(err, 0) end
        if protected and not pierce and (M.hitsLanded or 0) > 0 then
          M.adapter:say(T.game("%s couldn't fully protect\nitself and got hurt!", nameOf(M.adapter, t)))
        end
        if mx and ((M.hitsLanded or 0) > 0 or (M.hpDealt or 0) > 0) then
          local okE, errE = pcall(maxEffect, M, mx, user.__mrDmax or {})
          if not okE then warn("dynamax: %s's effect failed: %s", tostring(row.id), tostring(errE)) end
        end
      end
    end

    -- the damage: a quarter through Protect; the veil halves it; the anti-Dynamax moves double it
    local calc = E.Damage and E.Damage.calc
    if calc then
      E.Damage.calc = function(att, def, moveId, o, ...)
        if not (quarter or veilOn or doubleOn) then return calc(att, def, moveId, o, ...) end
        local dmg, info = calc(att, def, moveId, o, ...)
        if type(dmg) == "number" and dmg > 0 then
          if doubleOn then dmg = dmg * 2 end
          local sd = veilOn and veilOn.__ndx
          if sd and (sd.mrVeil or 0) > 0 and not (info and info.critical) then dmg = max(1, floor(dmg / 2)) end
          if quarter then dmg = max(1, floor(dmg / 4)) end
        end
        return dmg, info
      end
    end

    -- the moves that fail on a Dynamaxed Pokemon; no flinching while Dynamaxed
    local forEach = Engine.forEachTarget
    Engine.forEachTarget = function(M, body, ...)
      if not (M and isOn(M.st)) then return forEach(M, body, ...) end
      local wrapped = body
      if type(body) == "function" then
        wrapped = function(M2, ...)
          local t = M2.target
          if t and t ~= M2.user and t.__mrDmax and M2.move then
            local key = R.squash(tostring(M2.move.id or ""))
            if D.FAIL_VS_DMAX[key] or tonumber(M2.move.effect) == 38 then
              M2:attackString()
              M2:ppReduce()
              M2.anim.statusOnly = true
              M2.failed = true
              M2.adapter:sayText("STRINGID_BUTITFAILED")
              return
            end
          end
          -- (Destiny Bond never takes a Dynamaxed Pokemon down with it)
          local db, db2 = nil, nil
          if t and M2.user and M2.user.__mrDmax then db, db2 = t.expDestinyBond, t.destinyBond t.expDestinyBond, t.destinyBond = nil, nil end
          local r = body(M2, ...)
          if db ~= nil or db2 ~= nil then t.expDestinyBond, t.destinyBond = db, db2 end
          return r
        end
      end
      local r = forEach(M, wrapped, ...)
      for _, b in ipairs(M.adapter:activeBattlers() or {}) do
        if b.__mrDmax then b.flinched, b.expFlinched = nil, nil end
      end
      return r
    end

    -- never forced out while Dynamaxed
    local performSwitch = Engine.performSwitch
    Engine.performSwitch = function(st, ad, side, slot, opts, ...)
      if isOn(st) and type(opts) == "table" and opts.reason == "roar" then
        local out = type(side) == "table" and side or (st and st[side])
        if out and out.__mrDmax then return nil end
      end
      return performSwitch(st, ad, side, slot, opts, ...)
    end

    -- the last move used: the base move (Mirror Move, Mimic, Spite and Disable look at it)
    local bookkeeping = Engine.moveEndBookkeeping
    Engine.moveEndBookkeeping = function(M, ...)
      local r = bookkeeping(M, ...)
      if M and M.user and isOn(M.st) and byNum[tonumber(M.mnum) or -1] and M.slot then
        local base = M.user.mon and M.user.mon.moves and M.user.mon.moves[M.slot]
        if base then
          if M.user.lastMoveId ~= nil then M.user.lastMoveId = base end
          if M.user.lastMove ~= nil then M.user.lastMove = base end
        end
      end
      return r
    end

    -- a switch ends it (quietly: the Pokemon is going back)
    local switchOut = Engine.switchOutEffects
    Engine.switchOutEffects = function(st, ad, b, ...)
      if isOn(st) and b and b.__mrDmax then Dm.revert(st, ad, b, nil, true) end
      return switchOut(st, ad, b, ...)
    end

    -- G-Max Steelsurge: a Pokemon coming in on that side is cut by steel (by type, as Stealth Rock)
    local switchIn = Engine.switchInEffects
    Engine.switchInEffects = function(st, ad, b, opts, ...)
      local r = switchIn(st, ad, b, opts, ...)
      if isOn(st) and b and ad and type(opts) == "table" and opts.spikes and not st.over and not E.State.isFainted(b) then
        local side = ad:ownSide(b)
        if side and side.__ndx and side.__ndx.mrSteelsurge then
          local eff = 1
          if E.Types and E.Types.typeCalc then
            local okT, _, _, e = pcall(E.Types.typeCalc, typeNumOf("STEEL"), b.type1, b.type2, nil, true)
            if okT then eff = tonumber(e) or 1 end
          end
          ad:applyHpLoss(b, max(1, floor(ad:maxHp(b) * eff / 8)))
          ad:say(T.game("The sharp steel bit into\n%s!", nameOf(ad, b)))
        end
      end
      return r
    end

    -- the battle decided: every Dynamax undone (before the evolutions and the write-back)
    local checkEnd = Engine.checkEnd
    Engine.checkEnd = function(st, ad, ...)
      local r = checkEnd(st, ad, ...)
      if isOn(st) and st.over then pcall(Dm.revertAll, st, true) end
      return r
    end

    -- a level gained while Dynamaxed: worked out on the base HP, then Dynamaxed again
    local Exp = E.Experience
    local apply = Exp and Exp.apply
    if apply then
      Exp.apply = function(mon, amount, ...)
        local st = E.Battle and E.Battle._st
        local S = st and st.__mr
        local rec = nil
        if S then for _, r0 in ipairs(S.list) do if r0.mon == mon and not r0.done then rec = r0 end end end
        if not rec then return apply(mon, amount, ...) end
        mon.hp, mon.maxHp = R.down(mon.hp, rec.dynMax, rec.baseMax), rec.baseMax
        local result = apply(mon, amount, ...)
        rec.baseMax = tonumber(mon.maxHp) or rec.baseMax
        mon.hp, mon.maxHp = R.up(mon.hp, rec.baseMax, rec.mult)
        rec.dynMax = mon.maxHp
        local v = Dm.vis[rec.id]
        if v then v.dynMax, v.baseMax = rec.dynMax, rec.baseMax end
        for _, s in ipairs(type(result) == "table" and result.steps or {}) do
          if s.maxHp then s.hp, s.maxHp = R.up(s.hp or 0, s.maxHp, rec.mult) end
        end
        return result
      end
    end

    -- a faint ends it
    if mod.events and mod.events.on then
      mod.events:on("battle.fainted", function(ev)
        local b = ev and ev.battler
        local st = ev and ev.battle
        if b and b.__mrDmax and isOn(st) then Dm.revert(st, nil, b, nil, true, true) end
      end)
    end

    -- the turn's end: the Dynamax's 3 turns, the G-Max fields' damage
    local Res, RulesE = E.Residuals, E.Rules
    if Res and Res.register and RulesE and type(RulesE.POST_PHASES_ORDER) == "table" and not RulesE.__mrDmax then
      RulesE.__mrDmax = true
      table.insert(RulesE.POST_PHASES_ORDER, "mr_dynamax")
      Res.register("mr_dynamax", function(ctx)
        local ad = ctx and ctx.adapter
        local st = ad and ad._st
        if not isOn(st) then return end
        for _, b in ipairs(ad:activeBattlers() or {}) do
          local rec = b.__mrDmax
          if rec and not rec.done then
            rec.turns = rec.turns - 1
            if rec.turns <= 0 then Dm.revert(st, ad, b, rec, false) end
          end
          if b.__mrMaxGuard then b.__mrMaxGuard = nil end
        end
        for _, side in ipairs({ st.playerSide, st.enemySide }) do
          local d = side and side.__ndx
          if d and (d.mrVeil or 0) > 0 then
            d.mrVeil = d.mrVeil - 1
            if d.mrVeil <= 0 then
              ad:say(side == st.playerSide and T.game("Your team's Aurora Veil\nwore off!") or T.game("The foe's Aurora Veil\nwore off!"))
            end
          end
        end
      end)
      if type(RulesE.FIELD_PHASES_ORDER) == "table" then
        table.insert(RulesE.FIELD_PHASES_ORDER, "mr_gmax_field")
        Res.register("mr_gmax_field", function(ctx)
          local ad = ctx and ctx.adapter
          local st = ad and ad._st
          if not isOn(st) then return end
          for _, side in ipairs({ st.playerSide, st.enemySide }) do
            local d = side and side.__ndx
            local f = d and d.mrField
            if f then
              for _, b in ipairs(ad:activeBattlers() or {}) do
                if ad:ownSide(b) == side and not E.State.isFainted(b) and not hasType(ad, b, f.spare) then
                  -- (the field's look on it again, as its words show)
                  ad:playAnim("general", "TURN_TRAP", b, b, D.TRAP_LOOK[f.type] or 83)
                  ad:say(wrap(fieldHurtWords(f.type, nameOf(ad, b))))
                  ad:applyHpLoss(b, max(1, floor(ad:maxHp(b) / f.frac)))
                end
              end
              f.turns = f.turns - 1
              if f.turns <= 0 then d.mrField = nil end
            end
          end
        end)
      end
    end

    -- the crit stage of a side G-Max Chi Strike raised
    if mod.hooks and mod.hooks.wrap then
      pcall(function()
        -- (the side's raised stage on top of the attacker's own: Gen 3's chances by stage)
        local CHANCE = { 16, 8, 4, 3, 2 }
        mod.hooks:wrap("battle.crit", function(next, c, ...)
          local att = type(c) == "table" and c.attacker or nil
          local st = type(c) == "table" and c.battle or nil
          local ad = E.Battle and E.Battle._adapter
          if att and isOn(st) and ad then
            local side = ad:ownSide(att)
            local d = side and side.__ndx
            if d and (d.mrCrit or 0) > 0 then
              local s = min(4, (tonumber(c.stage) or 0) + d.mrCrit)
              return ad:roll(1, CHANCE[s + 1]) == 1
            end
          end
          return next(c, ...)
        end)
      end)
    end
    return true
  end

  return Dm
end
