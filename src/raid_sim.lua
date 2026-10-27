-- The raid's turns (pure: no engine, no drawing; tests/raid_sim_test.lua drives it with a fake
-- adapter). The four against the boss: each turn the members' picks and the boss's move run in
-- priority then speed order; the boss's single-target moves fall on one member at random, its spread
-- moves - and its G-Max move, on its script's turns - on all four. A member knocked out sits the next
-- turn out, cheering the team on, and comes back at full HP after it (Sword / Shield's); every
-- knock-out counts. The raid is won when the boss falls, lost at RAID.FAINTS knock-outs or when the
-- RAID.TURNS-th turn ends (the storm).
--   sim = Sim.new{ boss, members, adapter, rng, rules, words }
--     boss: + gmax (a move: spread, gmaxEffect), shields (HP shares a barrier goes up at), segments,
--           script (data/raid_rules.lua SCRIPTS' list)
--     rules: data/raid_rules.lua N.RAID (TURNS, FAINTS, SHIELD_DMG, BREAK_DROP, ITEM_PRIORITY,
--            CHEER, POUCH) ; words: data/raid_gmax.lua WORDS
--   sim:turn(choices) -> events     choices[i] = { move = slot } | { item = id, target = j }
--   sim:canAct(i) ; sim:pouchLeft(id) ; sim.turnNo ; sim.faints ; sim.over ("win" | "faints" |
--   "storm" | nil)
-- Each event has `kind` and `text` (shown in order); kinds: use, miss, damage (target, amount, hp),
-- effect, crit, stage, status, heal, cant, faint, back, residual, fail, shield (up / hit / break:
-- `left`, `max`), cheer, item, field, over.
-- adapter: damage(att, def, move, spread) -> dmg, info ; hits(att, def, move) -> bool ;
--   speed(b) -> n ; effectiveness(type, def) -> mult

local Sim = {}
Sim.__index = Sim

local max, min, floor = math.max, math.min, math.floor

local STAT_WORD = { attack = "Attack", defense = "Defense", spAtk = "Sp. Atk", spDef = "Sp. Def",
  speed = "Speed", accuracy = "accuracy", evasion = "evasiveness" }
local STATUS_TEXT = {
  SLP = "%s fell asleep!", PAR = "%s is paralyzed! It may be unable to move!", PSN = "%s was poisoned!",
  TOX = "%s was badly poisoned!", BRN = "%s was burned!", FRZ = "%s was frozen solid!",
}
-- the types a status cannot take (Gen 3: Fire is not burned, Poison and Steel not poisoned, Ice
-- not frozen)
local STATUS_IMMUNE = { BRN = { [10] = true }, PSN = { [3] = true, [8] = true }, TOX = { [3] = true, [8] = true },
  FRZ = { [15] = true } }
Sim.STATUS_TEXT = STATUS_TEXT

-- the cheers' words: what each does to the team
Sim.CHEER_TEXT = {
  heal = "The team's HP was restored!",
  attack = "The team's Attack and Sp. Atk rose!",
  defense = "The team's Defense and Sp. Def rose!",
  speed = "The team's Speed rose!",
  shield = "The cheer broke through the barrier!",
  nothing = "But nothing happened...",
}
Sim.ITEM_NAME = { potion = "Potion", full_heal = "Full Heal", revive = "Revive" }

function Sim.new(o)
  local self = setmetatable({}, Sim)
  self.boss = o.boss
  self.members = o.members
  self.A = o.adapter
  self.rng = o.rng or function(lo, hi) return lo + floor(math.random() * (hi - lo + 1)) end
  self.rules = o.rules or { TURNS = 10, FAINTS = 4 }
  self.words = o.words or {}
  self.turnNo, self.faints, self.over = 1, 0, nil
  for _, m in ipairs(self.members) do m.down = 0 end
  local b = self.boss
  b.shieldsUsed, b.veil, b.critUp = {}, 0, 0
  -- the raid's own pouch, shared by the team for this raid
  self.pouch = {}
  for _, it in ipairs(self.rules.POUCH or {}) do
    self.pouch[it.id] = { id = it.id, n = it.n, heal = it.heal }
  end
  return self
end

local function hpOf(b) return tonumber(b.mon.hp) or 0 end
local function maxHpOf(b) return max(1, tonumber(b.mon.maxHp) or 1) end
local function alive(b) return hpOf(b) > 0 end
local function fill(text, boss, mon)
  return ((text or ""):gsub("{BOSS}", boss and boss.name or ""):gsub("{MON}", mon and mon.name or ""))
end

-- on the field: alive and not sitting out
function Sim:present(i)
  local m = self.members[i]
  return m ~= nil and alive(m) and (m.down or 0) == 0
end
function Sim:canAct(i) return not self.over and self:present(i) end
function Sim:pouchLeft(id) local it = self.pouch[id]; return it and it.n or 0 end

-- ------- effects

function Sim:stage(ev, b, stat, n)
  b.stages[stat] = b.stages[stat] or 0
  local was = b.stages[stat]
  local now = max(-6, min(6, was + n))
  b.stages[stat] = now
  local word = STAT_WORD[stat] or stat
  local text
  if now == was then
    text = ("%s's %s won't go any %s!"):format(b.name, word, n > 0 and "higher" or "lower")
  elseif n >= 2 then text = ("%s's %s rose sharply!"):format(b.name, word)
  elseif n > 0 then text = ("%s's %s rose!"):format(b.name, word)
  elseif n <= -2 then text = ("%s's %s harshly fell!"):format(b.name, word)
  else text = ("%s's %s fell!"):format(b.name, word) end
  ev[#ev + 1] = { kind = "stage", who = b, stat = stat, n = now - was, text = text }
end

-- a major status: false (and no words when quiet) when it does not take
function Sim:status(ev, b, st, quiet)
  local immune = STATUS_IMMUNE[st]
  if b.status or (immune and (immune[b.type1] or immune[b.type2 or -1])) then
    if not quiet then ev[#ev + 1] = { kind = "fail", text = "But it failed!" } end
    return false
  end
  b.status = st
  if st == "SLP" then b.sleep = self.rng(2, 5) end
  if st == "TOX" then b.tox = 0 end
  ev[#ev + 1] = { kind = "status", who = b, status = st, text = STATUS_TEXT[st]:format(b.name) }
  return true
end

-- what a move does besides its damage (dealt: the damage it did), on its user or its target:
--   stages (+ self), status, chance, heal - from the move's Gen 3 effect;
--   foeStages / selfStages, statusChance, drain - from a newer move's extra (the National Dex's)
function Sim:side(ev, att, def, mv, damaging, dealt)
  local s = mv.side
  if not s then
    if not damaging then ev[#ev + 1] = { kind = "fail", text = "But nothing happened!" } end
    return
  end
  if s.drain and dealt and dealt > 0 and alive(att) then
    local amt = floor(dealt * math.abs(s.drain) / 100 + 0.5)
    if amt > 0 then
      if s.drain > 0 then
        att.mon.hp = min(maxHpOf(att), hpOf(att) + amt)
        ev[#ev + 1] = { kind = "heal", who = att, hp = att.mon.hp, text = ("%s had its energy drained!"):format(def.name) }
      else
        amt = self:capAtShield(att, amt)
        att.mon.hp = max(0, hpOf(att) - amt)
        ev[#ev + 1] = { kind = "residual", who = att, amount = amt, hp = att.mon.hp,
          text = ("%s was damaged by the recoil!"):format(att.name) }
        if att.boss then self:checkShield(ev) end
        if not alive(att) then self:fainted(ev, att) end
      end
    end
  end
  -- `chance` gates the stat changes (and a Gen 3 effect's status); `statusChance` its own status
  local lucky = not (s.chance and s.chance > 0 and self.rng(1, 100) > s.chance)
  local target = s.self and att or def
  if s.heal and alive(target) then
    local before = hpOf(target)
    target.mon.hp = min(maxHpOf(target), before + floor(maxHpOf(target) * s.heal))
    if target.mon.hp == before then
      ev[#ev + 1] = { kind = "fail", text = ("%s's HP is full!"):format(target.name) }
    else
      ev[#ev + 1] = { kind = "heal", who = target, hp = target.mon.hp, text = ("%s regained health!"):format(target.name) }
    end
  end
  if lucky then
    if s.stages and alive(target) then
      for stat, n in pairs(s.stages) do self:stage(ev, target, stat, n) end
    end
    if s.selfStages and alive(att) then
      for stat, n in pairs(s.selfStages) do self:stage(ev, att, stat, n) end
    end
    if s.foeStages and alive(def) and def ~= att then
      for stat, n in pairs(s.foeStages) do self:stage(ev, def, stat, n) end
    end
  end
  if s.status then
    if s.statusChance then
      if alive(def) and def ~= att and self.rng(1, 100) <= s.statusChance then self:status(ev, def, s.status, true) end
    elseif lucky and alive(target) then
      self:status(ev, target, s.status, damaging)
    end
  end
end

-- a battler down: the boss (won), or a member (it sits the next turn out; every knock-out counts)
function Sim:fainted(ev, b)
  ev[#ev + 1] = { kind = "faint", who = b, text = ("%s fainted!"):format(b.name) }
  if b.boss then
    self.over = "win"
    return
  end
  self.faints = self.faints + 1
  b.down = 2
  b.status, b.sleep, b.tox, b.trap = nil, nil, nil, nil
  if self.faints >= (self.rules.FAINTS or 4) then self.over = "faints" end
end

-- ------- the barrier

-- the HP the boss cannot be taken below until its next barrier has risen: that barrier's threshold
-- (as Sword / Shield: the hit that reaches it stops there, the rest lost, and the barrier goes up);
-- nil when no barrier is left to come
-- a threshold's HP, in whole HP: the floor and the barrier's check use this one number (comparing
-- shares instead left 252 / 360 a hair above 0.7, so the barrier never rose and the boss was held
-- there for good)
local function thresholdHp(b, t) return math.floor(maxHpOf(b) * t + 0.5) end
function Sim:shieldFloor()
  local b = self.boss
  for _, t in ipairs(b.shields or {}) do
    if not b.shieldsUsed[t] then return thresholdHp(b, t) end
  end
  return nil
end

-- damage `cut` to the boss held at its next barrier's threshold (another battler's untouched)
function Sim:capAtShield(who, cut)
  if not (who and who.boss) then return cut end
  local f = self:shieldFloor()
  if f then cut = min(cut, max(0, hpOf(who) - f)) end
  return cut
end

-- after the boss is hurt: a barrier for the first threshold its HP has passed (one at a time)
function Sim:checkShield(ev)
  local b = self.boss
  if b.shield or not alive(b) then return end
  for _, t in ipairs(b.shields or {}) do
    if not b.shieldsUsed[t] and hpOf(b) <= thresholdHp(b, t) then
      b.shieldsUsed[t] = true
      local n = b.segments or 2
      b.shield = { left = n, max = n }
      ev[#ev + 1] = { kind = "shield", step = "up", who = b, left = n, max = n,
        text = ("A mysterious barrier appeared in front of %s!"):format(b.name) }
      return
    end
  end
end

function Sim:breakShield(ev)
  local b = self.boss
  b.shield = nil
  ev[#ev + 1] = { kind = "shield", step = "break", who = b, left = 0, max = 0,
    text = ("The mysterious barrier around %s disappeared!"):format(b.name) }
  local drop = self.rules.BREAK_DROP or -2
  self:stage(ev, b, "defense", drop)
  self:stage(ev, b, "spDef", drop)
  -- (its HP held at the next threshold meanwhile: that barrier now)
  self:checkShield(ev)
end

-- ------- a move

-- the battler skips its move (asleep, frozen, paralysed): true
function Sim:held(ev, b)
  if b.status == "SLP" then
    b.sleep = (b.sleep or 1) - 1
    if b.sleep > 0 then
      ev[#ev + 1] = { kind = "cant", who = b, text = ("%s is fast asleep."):format(b.name) }
      return true
    end
    b.status, b.sleep = nil, nil
    ev[#ev + 1] = { kind = "status", who = b, status = nil, text = ("%s woke up!"):format(b.name) }
  elseif b.status == "FRZ" then
    if self.rng(1, 5) ~= 1 then
      ev[#ev + 1] = { kind = "cant", who = b, text = ("%s is frozen solid!"):format(b.name) }
      return true
    end
    b.status = nil
    ev[#ev + 1] = { kind = "status", who = b, status = nil, text = ("%s thawed out!"):format(b.name) }
  elseif b.status == "PAR" and self.rng(1, 4) == 1 then
    ev[#ev + 1] = { kind = "cant", who = b, text = ("%s is paralyzed! It can't move!"):format(b.name) }
    return true
  end
  return false
end

-- the damage a hit on the boss does through its barrier and veil; a hit breaks a segment
function Sim:throughBoss(ev, def, dmg)
  if not def.boss then return dmg end
  if (def.veil or 0) > 0 then dmg = floor(dmg / 2) end
  if def.shield then
    dmg = floor(dmg * (self.rules.SHIELD_DMG or 0.25))
    def.shield.left = def.shield.left - 1
    ev[#ev + 1] = { kind = "shield", step = "hit", who = def, left = def.shield.left, max = def.shield.max }
  end
  return max(1, dmg)
end

-- a G-Max move's effect on those it hit (`hit`)
function Sim:gmaxEffect(ev, att, mv, hit)
  local e = mv.gmaxEffect
  if not e or not alive(att) then return end
  local W = self.words
  if e.kind == "status" then
    for _, m in ipairs(hit) do
      if alive(m) then self:status(ev, m, e.list[self.rng(1, #e.list)], true) end
    end
  elseif e.kind == "drowsy" then
    for _, m in ipairs(hit) do
      if alive(m) and self.rng(1, 100) <= (e.chance or 50) then
        if W.drowsy then ev[#ev + 1] = { kind = "status", who = m, text = fill(W.drowsy, att, m) } end
        self:status(ev, m, "SLP", true)
      end
    end
  elseif e.kind == "stages" then
    for _, m in ipairs(hit) do
      if alive(m) then for stat, n in pairs(e.foe or {}) do self:stage(ev, m, stat, n) end end
    end
  elseif e.kind == "pp" then
    for _, m in ipairs(hit) do
      for _, mvm in ipairs(m.moves or {}) do mvm.pp = max(0, (mvm.pp or 0) - (e.n or 2)) end
    end
    ev[#ev + 1] = { kind = "field", who = att, text = fill(W.pp or "The team's moves lost PP!", att) }
  elseif e.kind == "veil" then
    att.veil = e.turns or 5
    ev[#ev + 1] = { kind = "field", who = att, text = fill(W.veil or "{BOSS} is protected by a veil!", att) }
  elseif e.kind == "heal" then
    att.mon.hp = min(maxHpOf(att), hpOf(att) + floor(maxHpOf(att) / (e.frac or 6)))
    ev[#ev + 1] = { kind = "heal", who = att, hp = att.mon.hp, text = fill(W.heal or "{BOSS}'s HP was restored!", att) }
  elseif e.kind == "cure" then
    if att.status then
      att.status, att.sleep, att.tox = nil, nil, nil
      ev[#ev + 1] = { kind = "status", who = att, text = fill(W.cure or "{BOSS}'s status returned to normal!", att) }
    end
  elseif e.kind == "crit" then
    att.critUp = (att.critUp or 0) + (e.n or 1)
    ev[#ev + 1] = { kind = "field", who = att, text = fill(W.crit or "{BOSS} is getting pumped!", att) }
  elseif e.kind == "field" then
    if not self.field then
      self.field = { turns = e.turns or 4, frac = e.frac or 6, spare = e.spareNum, spareName = e.spare }
      local t = W.field and W.field[e.spare]
      ev[#ev + 1] = { kind = "field", who = att, fieldType = e.spare, text = t or "The team was surrounded!" }
    end
  elseif e.kind == "trap" then
    for _, m in ipairs(hit) do
      if alive(m) and not m.trap then
        m.trap, m.trapFrac = e.turns or 4, e.frac or 8
        ev[#ev + 1] = { kind = "status", who = m, text = fill(W.trap or "{MON} became trapped!", att, m) }
      end
    end
  end
end

function Sim:use(ev, att, mv, targets)
  if not alive(att) or self.over then return end
  if self:held(ev, att) then return end
  ev[#ev + 1] = { kind = "use", who = att, move = mv, gmax = mv.isGmax == true,
    text = ("%s used %s!"):format(att.name, mv.name) }
  if not att.boss then mv.pp = max(0, (mv.pp or 1) - 1) end
  -- a status move on its user
  if mv.status and mv.side and mv.side.self then
    self:side(ev, att, att, mv, false)
    return
  end
  local spread = #targets > 1
  local hit = {}
  for _, def in ipairs(targets) do
    if self.over then return end
    if alive(def) then
      if not self.A.hits(att, def, mv) then
        ev[#ev + 1] = { kind = "miss", who = att, target = def, text = ("%s avoided the attack!"):format(def.name) }
      elseif mv.status then
        self:side(ev, att, def, mv, false)
      else
        local dmg, info = self.A.damage(att, def, mv, spread)
        info = info or {}
        local eff = tonumber(info.effectiveness) or 1
        if eff == 0 then
          ev[#ev + 1] = { kind = "effect", eff = 0, target = def, text = ("It doesn't affect %s..."):format(def.name) }
        else
          local hadShield = def.shield ~= nil
          dmg = self:throughBoss(ev, def, max(1, dmg))
          dmg = self:capAtShield(def, min(hpOf(def), dmg))
          def.mon.hp = hpOf(def) - dmg
          hit[#hit + 1] = def
          ev[#ev + 1] = { kind = "damage", who = att, target = def, amount = dmg, hp = def.mon.hp, move = mv }
          if info.critical then ev[#ev + 1] = { kind = "crit", target = def, text = "A critical hit!" } end
          if eff > 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's super effective!" }
          elseif eff < 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's not very effective..." } end
          if alive(def) then
            self:side(ev, att, def, mv, true, dmg)
            if def.boss and hadShield and def.shield and def.shield.left <= 0 then self:breakShield(ev) end
            if def.boss then self:checkShield(ev) end
          else
            self:fainted(ev, def)
            if not self.over and mv.side and mv.side.drain then self:side(ev, att, def, mv, true, dmg) end
          end
        end
      end
    end
  end
  if mv.gmaxEffect and #hit > 0 and not self.over then self:gmaxEffect(ev, att, mv, hit) end
end

-- ------- cheers and the pouch

-- a member sitting out cheers the team on: one of rules.CHEER by weight (the barrier one only while
-- a barrier stands)
function Sim:cheer(ev, m)
  ev[#ev + 1] = { kind = "cheer", who = m, text = ("%s is cheering the team on!"):format(m.name) }
  local list, total = {}, 0
  for _, c in ipairs(self.rules.CHEER or {}) do
    if c.id ~= "shield" or self.boss.shield then
      list[#list + 1] = c
      total = total + (c.w or 1)
    end
  end
  if total <= 0 then return end
  local roll, pick = self.rng(1, total), nil
  for _, c in ipairs(list) do
    roll = roll - (c.w or 1)
    if roll <= 0 then pick = c.id; break end
  end
  local team = {}
  for i = 1, #self.members do if self:present(i) then team[#team + 1] = self.members[i] end end
  local quiet = {}
  if pick == "heal" then
    for _, t in ipairs(team) do
      t.mon.hp, t.status, t.sleep, t.tox = maxHpOf(t), nil, nil, nil
      quiet[#quiet + 1] = { kind = "heal", who = t, hp = t.mon.hp }
    end
  elseif pick == "attack" or pick == "defense" or pick == "speed" then
    local stats = pick == "attack" and { "attack", "spAtk" } or (pick == "defense" and { "defense", "spDef" } or { "speed" })
    for _, t in ipairs(team) do
      for _, s in ipairs(stats) do t.stages[s] = min(6, (t.stages[s] or 0) + 1) end
    end
  elseif pick == "shield" and self.boss.shield then
    ev[#ev + 1] = { kind = "cheer", who = m, cheer = pick, text = Sim.CHEER_TEXT.shield }
    self:breakShield(ev)
    return
  end
  ev[#ev + 1] = { kind = "cheer", who = m, cheer = pick, text = Sim.CHEER_TEXT[pick or "nothing"] }
  for _, q in ipairs(quiet) do ev[#ev + 1] = q end
end

-- an item from the pouch on a member (used up only when it does something)
function Sim:useItem(ev, user, id, target)
  local it = self.pouch[id]
  if not it or it.n <= 0 then return end
  local name = Sim.ITEM_NAME[id] or id
  ev[#ev + 1] = { kind = "item", who = user, item = id, text = ("%s used a %s on %s!"):format(user.name, name, target.name) }
  local worked = false
  if id == "revive" then
    if (target.down or 0) > 0 then
      target.down = 0
      target.mon.hp = floor(maxHpOf(target) / 2)
      for k in pairs(target.stages) do target.stages[k] = 0 end
      ev[#ev + 1] = { kind = "back", who = target, hp = target.mon.hp, text = ("%s was revived!"):format(target.name) }
      worked = true
    end
  elseif (target.down or 0) == 0 and alive(target) then
    if id == "potion" and hpOf(target) < maxHpOf(target) then
      target.mon.hp = min(maxHpOf(target), hpOf(target) + floor(maxHpOf(target) * (it.heal or 0.5)))
      ev[#ev + 1] = { kind = "heal", who = target, hp = target.mon.hp, text = ("%s's HP was restored."):format(target.name) }
      worked = true
    elseif id == "full_heal" and target.status then
      target.status, target.sleep, target.tox = nil, nil, nil
      ev[#ev + 1] = { kind = "status", who = target, text = ("%s was cured of its status problem."):format(target.name) }
      worked = true
    end
  end
  if worked then it.n = it.n - 1
  else ev[#ev + 1] = { kind = "fail", text = "But it had no effect..." } end
end

-- ------- a turn

-- the boss's script: whether `kind` is due on this turn (every / from), or (hpBelow) its HP share
function Sim:due(kind)
  for _, s in ipairs(self.boss.script or {}) do
    if s.kind == kind then
      if s.every then
        local from = s.from or 1
        if self.turnNo >= from and (self.turnNo - from) % s.every == 0 then return s end
      elseif s.hpBelow then
        if not self.boss.auraUsed and hpOf(self.boss) / maxHpOf(self.boss) < s.hpBelow then return s end
      end
    end
  end
  return nil
end

-- the boss's move this turn: its G-Max move when its script says, else one of its moves at random
function Sim:bossMove()
  local b = self.boss
  if b.gmax and self:due("gmax") then return b.gmax end
  local mv = b.moves
  if #mv == 0 then return b.gmax end
  return mv[self.rng(1, #mv)]
end

-- whom a move falls on: the boss for the members; for the boss, a spread move every member on the
-- field, else one of them at random
function Sim:targetsFor(att, mv)
  if not att.boss then return { self.boss } end
  local list = {}
  for i = 1, #self.members do
    if self:present(i) then list[#list + 1] = self.members[i] end
  end
  if mv.spread or #list <= 1 then return list end
  return { list[self.rng(1, #list)] }
end

-- the end of the turn: the field and traps, poison and burns, the veil, the boss's extras, then
-- those sitting out come back
function Sim:endTurn(ev)
  local W = self.words
  local b = self.boss
  local team = {}
  for i = 1, #self.members do if self:present(i) then team[#team + 1] = self.members[i] end end
  local function hurt(who, cut, text)
    if self.over or not alive(who) then return end
    cut = self:capAtShield(who, min(hpOf(who), max(1, cut)))
    if cut <= 0 then return end
    who.mon.hp = hpOf(who) - cut
    ev[#ev + 1] = { kind = "residual", who = who, amount = cut, hp = who.mon.hp, text = text }
    if not alive(who) then self:fainted(ev, who)
    elseif who.boss then self:checkShield(ev) end
  end
  -- a G-Max field over the team
  local f = self.field
  if f then
    for _, m in ipairs(team) do
      if not (f.spare and (m.type1 == f.spare or m.type2 == f.spare)) then
        local t = W.fieldHurt and W.fieldHurt[f.spareName] or "{MON} is hurt!"
        hurt(m, floor(maxHpOf(m) / f.frac), fill(t, b, m))
      end
    end
    f.turns = f.turns - 1
    if f.turns <= 0 then self.field = nil end
  end
  for _, m in ipairs(team) do
    if (m.trap or 0) > 0 then
      hurt(m, floor(maxHpOf(m) / (m.trapFrac or 8)), fill(W.trapHurt or "{MON} is hurt by the trap!", b, m))
      m.trap = m.trap - 1
    end
  end
  -- poison and burns
  local all = { b }
  for _, m in ipairs(team) do all[#all + 1] = m end
  for _, x in ipairs(all) do
    local st = x.status
    if not self.over and alive(x) and (st == "PSN" or st == "BRN" or st == "TOX") then
      local cut
      if st == "TOX" then
        x.tox = (x.tox or 0) + 1
        cut = floor(maxHpOf(x) * x.tox / 16)
      else
        cut = floor(maxHpOf(x) / 8)
      end
      hurt(x, cut, st == "BRN" and ("%s was hurt by its burn!"):format(x.name) or ("%s was hurt by poison!"):format(x.name))
    end
  end
  if self.over then return end
  if (b.veil or 0) > 0 then
    b.veil = b.veil - 1
    if b.veil == 0 then ev[#ev + 1] = { kind = "field", who = b, text = fill(W.veilEnd or "{BOSS}'s veil wore off!", b) } end
  end
  -- the boss's extras: wiping the team's stat changes, its aura flaring when weakened
  if self:due("wipe") then
    for _, m in ipairs(team) do for k in pairs(m.stages) do m.stages[k] = 0 end end
    for k, v in pairs(b.stages) do if v < 0 then b.stages[k] = 0 end end
    ev[#ev + 1] = { kind = "field", who = b, text = ("%s nullified the stat changes affecting the team!"):format(b.name) }
  end
  if self:due("statup") then
    b.auraUsed = true
    ev[#ev + 1] = { kind = "field", who = b, text = ("%s's aura flared to life!"):format(b.name) }
    for _, s in ipairs({ "attack", "spAtk", "defense", "spDef" }) do self:stage(ev, b, s, 1) end
  end
  -- those who sat this turn out come back
  for _, m in ipairs(self.members) do
    if (m.down or 0) > 0 then
      m.down = m.down - 1
      if m.down == 0 then
        m.mon.hp = maxHpOf(m)
        for k in pairs(m.stages) do m.stages[k] = 0 end
        ev[#ev + 1] = { kind = "back", who = m, hp = m.mon.hp, text = ("%s is back in the fight!"):format(m.name) }
      end
    end
  end
end

function Sim:turn(choices)
  local ev = {}
  if self.over then return ev end
  local acts = {}
  local itemPri = self.rules.ITEM_PRIORITY or 6
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    if self:canAct(i) and c then
      if c.item and self.members[c.target or i] then
        acts[#acts + 1] = { who = m, item = c.item, target = self.members[c.target or i], pri = itemPri,
          tie = self.rng(1, 65536) }
      elseif c.move and m.moves[c.move] then
        local mv = m.moves[c.move]
        acts[#acts + 1] = { who = m, mv = mv, pri = mv.priority or 0, tie = self.rng(1, 65536) }
      end
    elseif (m.down or 0) == 1 then
      -- sitting out this turn: it cheers in its place
      acts[#acts + 1] = { who = m, cheer = true, pri = 0, tie = self.rng(1, 65536) }
    end
  end
  local bmv = self:bossMove()
  if bmv then acts[#acts + 1] = { who = self.boss, mv = bmv, pri = bmv.priority or 0, tie = self.rng(1, 65536) } end
  for _, a in ipairs(acts) do a.speed = self.A.speed(a.who) end
  table.sort(acts, function(a, b)
    if a.pri ~= b.pri then return a.pri > b.pri end
    if a.speed ~= b.speed then return a.speed > b.speed end
    return a.tie < b.tie
  end)
  for _, a in ipairs(acts) do
    if self.over then break end
    if a.cheer then
      if (a.who.down or 0) > 0 then self:cheer(ev, a.who) end
    elseif a.item then
      if alive(a.who) and (a.who.down or 0) == 0 then self:useItem(ev, a.who, a.item, a.target) end
    elseif alive(a.who) and (a.who.boss or (a.who.down or 0) == 0) then
      self:use(ev, a.who, a.mv, self:targetsFor(a.who, a.mv))
    end
  end
  if not self.over then self:endTurn(ev) end
  if not self.over then
    self.turnNo = self.turnNo + 1
    if self.turnNo > (self.rules.TURNS or 10) then self.over = "storm" end
  end
  if self.over then
    local text
    if self.over == "win" then text = ("You defeated %s!"):format(self.boss.name)
    elseif self.over == "storm" then text = ("The storm around %s grew too strong!"):format(self.boss.name)
    else text = "Too many Pok\195\169mon fainted..." end
    ev[#ev + 1] = { kind = "over", outcome = self.over, text = text }
    if self.over ~= "win" then
      ev[#ev + 1] = { kind = "over", outcome = self.over, text = "You were blown out of the den!" }
    end
  end
  return ev
end

return Sim
