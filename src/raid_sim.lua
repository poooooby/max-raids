-- The raid's turns (pure: no engine, no drawing; tests/raid_sim_test.lua drives it with a fake
-- adapter). The four against the boss: each turn the members' picks and the boss's move run in
-- priority then speed order; the boss's single-target moves fall on one member at random, its spread
-- moves on all four. A member knocked out sits the next turn out and comes back at full HP after it
-- (Sword / Shield's); every knock-out counts. The raid is won when the boss falls, lost at
-- RAID.FAINTS knock-outs or when the RAID.TURNS-th turn ends (the storm).
--   sim = Sim.new{ boss, members, adapter, rng, rules }
--   sim:turn(choices) -> events     choices[i] = { move = slot } for each member that can act
--   sim:canAct(i) ; sim.turnNo ; sim.faints ; sim.over ("win" | "faints" | "storm" | nil)
-- Each event has `kind` and `text` (shown in order); kinds: use, miss, damage (target, amount, hp),
-- effect (super / weak / none), crit, stage, status, heal, cant, faint, back, residual, over.
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

function Sim.new(o)
  local self = setmetatable({}, Sim)
  self.boss = o.boss
  self.members = o.members
  self.A = o.adapter
  self.rng = o.rng or function(lo, hi) return lo + floor(math.random() * (hi - lo + 1)) end
  self.rules = o.rules or { TURNS = 10, FAINTS = 4 }
  self.turnNo, self.faints, self.over = 1, 0, nil
  for _, m in ipairs(self.members) do m.down = 0 end
  return self
end

local function hpOf(b) return tonumber(b.mon.hp) or 0 end
local function maxHpOf(b) return max(1, tonumber(b.mon.maxHp) or 1) end
local function alive(b) return hpOf(b) > 0 end

-- on the field: alive and not sitting out
function Sim:present(i)
  local m = self.members[i]
  return m ~= nil and alive(m) and (m.down or 0) == 0
end
function Sim:canAct(i) return not self.over and self:present(i) end

local function hasType(b, t) return b.type1 == t or b.type2 == t end

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
    local amt = math.floor(dealt * math.abs(s.drain) / 100 + 0.5)
    if amt > 0 then
      if s.drain > 0 then
        att.mon.hp = min(maxHpOf(att), hpOf(att) + amt)
        ev[#ev + 1] = { kind = "heal", who = att, hp = att.mon.hp, text = ("%s had its energy drained!"):format(def.name) }
      else
        att.mon.hp = max(0, hpOf(att) - amt)
        ev[#ev + 1] = { kind = "residual", who = att, amount = amt, hp = att.mon.hp,
          text = ("%s was damaged by the recoil!"):format(att.name) }
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
  b.status, b.sleep, b.tox = nil, nil, nil
  if self.faints >= (self.rules.FAINTS or 4) then self.over = "faints" end
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

function Sim:use(ev, att, mv, targets)
  if not alive(att) or self.over then return end
  if self:held(ev, att) then return end
  ev[#ev + 1] = { kind = "use", who = att, move = mv, text = ("%s used %s!"):format(att.name, mv.name) }
  if not att.boss then mv.pp = max(0, (mv.pp or 1) - 1) end
  -- a status move on its user
  if mv.status and mv.side and mv.side.self then
    self:side(ev, att, att, mv, false)
    return
  end
  local spread = #targets > 1
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
          dmg = min(hpOf(def), max(1, dmg))
          def.mon.hp = hpOf(def) - dmg
          ev[#ev + 1] = { kind = "damage", who = att, target = def, amount = dmg, hp = def.mon.hp, move = mv }
          if info.critical then ev[#ev + 1] = { kind = "crit", target = def, text = "A critical hit!" } end
          if eff > 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's super effective!" }
          elseif eff < 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's not very effective..." } end
          if alive(def) then self:side(ev, att, def, mv, true, dmg)
          else
            self:fainted(ev, def)
            if not self.over and mv.side and mv.side.drain then self:side(ev, att, def, mv, true, dmg) end
          end
        end
      end
    end
  end
end

-- ------- a turn

-- the boss's move this turn: one of its moves at random
function Sim:bossMove()
  local mv = self.boss.moves
  if #mv == 0 then return nil end
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

function Sim:turn(choices)
  local ev = {}
  if self.over then return ev end
  local acts = {}
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    local mv = c and c.move and m.moves[c.move]
    if self:canAct(i) and mv then acts[#acts + 1] = { who = m, mv = mv, tie = self.rng(1, 65536) } end
  end
  local bmv = self:bossMove()
  if bmv then acts[#acts + 1] = { who = self.boss, mv = bmv, tie = self.rng(1, 65536) } end
  for _, a in ipairs(acts) do a.speed = self.A.speed(a.who) end
  table.sort(acts, function(a, b)
    if (a.mv.priority or 0) ~= (b.mv.priority or 0) then return (a.mv.priority or 0) > (b.mv.priority or 0) end
    if a.speed ~= b.speed then return a.speed > b.speed end
    return a.tie < b.tie
  end)
  for _, a in ipairs(acts) do
    if self.over then break end
    if alive(a.who) and (a.who.boss or (a.who.down or 0) == 0) then
      self:use(ev, a.who, a.mv, self:targetsFor(a.who, a.mv))
    end
  end
  -- the end of the turn: poison and burns, then those sitting out come back
  if not self.over then
    local all = { self.boss }
    for i = 1, #self.members do if self:present(i) then all[#all + 1] = self.members[i] end end
    for _, b in ipairs(all) do
      if self.over then break end
      local st = b.status
      if alive(b) and (st == "PSN" or st == "BRN" or st == "TOX") then
        local cut
        if st == "TOX" then
          b.tox = (b.tox or 0) + 1
          cut = max(1, floor(maxHpOf(b) * b.tox / 16))
        else
          cut = max(1, floor(maxHpOf(b) / 8))
        end
        cut = min(hpOf(b), cut)
        b.mon.hp = hpOf(b) - cut
        ev[#ev + 1] = { kind = "residual", who = b, amount = cut, hp = b.mon.hp,
          text = st == "BRN" and ("%s was hurt by its burn!"):format(b.name) or ("%s was hurt by poison!"):format(b.name) }
        if not alive(b) then self:fainted(ev, b) end
      end
    end
  end
  if not self.over then
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
