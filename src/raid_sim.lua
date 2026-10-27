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
--   sim:turn(choices) -> events     choices[i] = { move = slot, dmax = true? } | { item = id, target = j }
--   sim:canAct(i) ; sim:pouchLeft(id) ; sim.turnNo ; sim.faints ; sim.over ("win" | "faints" |
--   "storm" | nil) ; sim:canDynamax(i) ; sim.energy (who holds the Dynamax Energy) ; sim.money
-- Dynamax (Sword / Shield's raids): each turn one member holds the Dynamax Energy - slot 1 first,
-- then the next each turn, skipping one that has Dynamaxed, cannot (m.canDmax false) or is out; none
-- while one is Dynamaxed. Only the holder may Dynamax, at the turn's start: its HP and max HP x
-- m.dmaxMult (its Dynamax Level's), its moves their Max forms (m.maxMoves) for three turns, then it
-- reverts keeping its HP's share (at once if it faints). Each member once a raid. Max Guard (a
-- status move's Max form) protects from every move but the piercing G-Max ones, failing more
-- the more it is used in a row. Against a Dynamaxed target (the boss always) weight moves and
-- Encore / Disable / Instruct / Roar / Whirlwind fail; Behemoth Blade / Bash and Dynamax Cannon
-- deal double.
-- Team moves (data/raid_team_moves.lua, on a move as `team`; the raid is a multi battle, the four one
-- side, the boss the other): each side has its screens (reflect / light / veil: the adapter cuts the
-- damage, 2732 / 4096 for the team, 1 / 2 for the boss alone), safeguard, mist, tailwind (Speed x2),
-- the turn's guards (wide / quick / mat / crafty), the turn's centre of attention (redirect) and a
-- wish. Protect and its kin, Endure and Max Guard share a run that fails more the more they are used
-- in a row. Max and G-Max Moves strike through protect and the guards for a quarter of the damage
-- (Max Guard stops them; G-Max One Blow / Rapid Flow go through everything). Ally moves take the
-- choice's `target` (a member's slot; Pollen Puff "boss" for an attack).
-- Each event has `kind` and `text` (shown in order); kinds: use, miss, damage (target, amount, hp),
-- effect, crit, stage, status, heal, cant, faint, back, residual, fail, shield (up / hit / break:
-- `left`, `max`), cheer, item, field, over, dynamax / dynamaxEnd (who, hp, maxHp), guard (who;
-- blocked, pierced), side (side "team" | "boss", what, up = true | false: a screen, safeguard, mist,
-- tailwind, wide / quick / mat / crafty, redirect, wish, help (target)).
-- adapter: damage(att, def, move, spread, opts) -> dmg, info (opts: reflect, lightScreen,
--   doubleScreens, helped) ; hits(att, def, move) -> bool ; speed(b) -> n ;
--   effectiveness(type, def) -> mult ; abilityName(b) -> "PLUS" | ... | nil (optional)

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
  self.tw = o.teamWords or {}
  self.turnNo, self.faints, self.over = 1, 0, nil
  for _, m in ipairs(self.members) do m.down, m.outSince = 0, 1 end
  local b = self.boss
  b.shieldsUsed, b.veil, b.critUp, b.outSince = {}, 0, 0, 1
  self.sides = { team = Sim.newSide(), boss = Sim.newSide() }
  -- the raid's own pouch, shared by the team for this raid
  self.pouch = {}
  for _, it in ipairs(self.rules.POUCH or {}) do
    self.pouch[it.id] = { id = it.id, n = it.n, heal = it.heal }
  end
  -- Dynamax: who holds the Energy, who has used it, who is Dynamaxed; coins picked up
  self.energyFrom, self.energy, self.dmaxUsed, self.dmaxActive = 1, nil, {}, nil
  self.money, self.coinUses = 0, 0
  self:giveEnergy()
  return self
end

local function hpOf(b) return tonumber(b.mon.hp) or 0 end
local function maxHpOf(b) return max(1, tonumber(b.mon.maxHp) or 1) end
local function alive(b) return hpOf(b) > 0 end
-- a move's id squashed: "LOW_KICK" -> "lowkick"
local function squash(key) return type(key) == "string" and key:lower():gsub("[^%w]", "") or "" end
-- the boss is always Dynamaxed
local function isDmax(b) return b.boss or b.dmax ~= nil end
Sim.WEIGHT = { lowkick = true, grassknot = true, heatcrash = true, heavyslam = true }
Sim.NO_DMAX = { encore = true, disable = true, instruct = true, roar = true, whirlwind = true }
Sim.ANTI_DMAX = { behemothblade = true, behemothbash = true, dynamaxcannon = true }
local function fill(text, boss, mon)
  return ((text or ""):gsub("{BOSS}", boss and boss.name or ""):gsub("{MON}", mon and mon.name or ""))
end

-- ------- the two sides

-- what lasts on one side: screens, safeguard, mist, tailwind (turns left); the turn's guards and
-- centre of attention; a wish waiting
function Sim.newSide()
  return { reflect = 0, light = 0, veil = 0, safeguard = 0, mist = 0, tailwind = 0, guards = {}, redirect = nil,
    wish = nil }
end
Sim.SIDE_TURNS = { "reflect", "light", "veil", "safeguard", "mist", "tailwind" }
local function sideKey(b) return b.boss and "boss" or "team" end
function Sim:sideOf(b) return self.sides[sideKey(b)] end
local function foes(a, b) return sideKey(a) ~= sideKey(b) end
-- those on a side's field (the boss, or the members present)
function Sim:onSide(key)
  if key == "boss" then return alive(self.boss) and { self.boss } or {} end
  return self:team()
end
-- the boss's veil as the drawing reads it (b.veil: Aurora Veil's turns on its side)
function Sim:syncVeil() self.boss.veil = self.sides.boss.veil end

-- a team move's words: {MON}, {BOSS}, {ALLY}, {SIDE} / {SIDE_CAP} (the user's side)
function Sim:tword(key, sub, who, ally)
  local t = self.tw.WORDS and self.tw.WORDS[key]
  if type(t) == "table" then t = t[sub] end
  if type(t) ~= "string" then return nil end
  local key2 = who and sideKey(who) or "team"
  local side = key2 == "team" and "your team" or self.boss.name
  local cap = key2 == "team" and "Your team" or self.boss.name
  return (t:gsub("{SIDE_CAP}", cap):gsub("{SIDE}", side):gsub("{BOSS}", self.boss.name or "")
    :gsub("{MON}", who and who.name or ""):gsub("{ALLY}", ally and ally.name or ""))
end

-- on the field: alive and not sitting out
function Sim:present(i)
  local m = self.members[i]
  return m ~= nil and alive(m) and (m.down or 0) == 0
end
function Sim:canAct(i) return not self.over and self:present(i) end
function Sim:pouchLeft(id) local it = self.pouch[id]; return it and it.n or 0 end

-- ------- Dynamax

local function eligible(self, i)
  local m = self.members[i]
  return m ~= nil and not self.dmaxUsed[i] and m.canDmax ~= false and self:present(i)
end
-- the turn's Dynamax Energy: to the next member in turn order able to use it (none while one is
-- Dynamaxed)
function Sim:giveEnergy()
  self.energy = nil
  if self.over or self.dmaxActive then return end
  local n = #self.members
  for k = 0, n - 1 do
    local i = (self.energyFrom - 1 + k) % n + 1
    if eligible(self, i) then
      self.energy = i
      self.energyFrom = i % n + 1
      return
    end
  end
end
function Sim:canDynamax(i)
  return not self.over and self.energy == i and eligible(self, i)
end

function Sim:dynamax(ev, m, i)
  local mult = m.dmaxMult or (1.5 + 0.05 * (m.dmaxLevel or 0))
  local base = maxHpOf(m)
  m.mon.maxHp = floor(base * mult)
  m.mon.hp = max(1, floor(hpOf(m) * mult))
  m.dmax = { turns = 3, mult = mult, baseMax = base }
  self.dmaxUsed[i], self.dmaxActive, self.energy = true, m, nil
  ev[#ev + 1] = { kind = "dynamax", who = m, hp = m.mon.hp, maxHp = m.mon.maxHp, gmax = m.gmaxId ~= nil,
    text = ("%s %s!"):format(m.name, m.gmaxId and "Gigantamaxed" or "Dynamaxed") }
end

-- back to its own size: its HP keeps its share of the max (quiet: fainted, no words)
function Sim:undynamax(ev, m, quiet)
  local d = m.dmax
  if not d then return end
  local cur, top = hpOf(m), maxHpOf(m)
  m.mon.maxHp = d.baseMax
  if cur > 0 then m.mon.hp = max(1, min(d.baseMax, floor(cur * d.baseMax / top + 0.5))) else m.mon.hp = 0 end
  m.dmax = nil
  if self.dmaxActive == m then self.dmaxActive = nil end
  ev[#ev + 1] = { kind = "dynamaxEnd", who = m, hp = m.mon.hp, maxHp = m.mon.maxHp,
    text = not quiet and ("%s returned to its normal size!"):format(m.name) or nil }
end

-- ------- effects

-- (by: who caused it - a drop from the other side is stopped by the side's mist)
function Sim:stage(ev, b, stat, n, by)
  if n < 0 and by and foes(by, b) and self:sideOf(b).mist > 0 then
    if not b.mistSaid then
      b.mistSaid = true
      ev[#ev + 1] = { kind = "fail", who = b, text = self:tword("misted", nil, b) or ("%s is protected by the mist!"):format(b.name) }
    end
    return
  end
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

-- a major status: false (and no words when quiet) when it does not take (by: who caused it - from the
-- other side, the side's Safeguard stops it)
function Sim:status(ev, b, st, quiet, by)
  if by and foes(by, b) and self:sideOf(b).safeguard > 0 and not b.status then
    if not quiet then
      ev[#ev + 1] = { kind = "fail", who = b, text = self:tword("safeguarded", nil, b) or ("%s is protected by Safeguard!"):format(b.name) }
    end
    return false
  end
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
      for stat, n in pairs(s.stages) do self:stage(ev, target, stat, n, att) end
    end
    if s.selfStages and alive(att) then
      for stat, n in pairs(s.selfStages) do self:stage(ev, att, stat, n) end
    end
    if s.foeStages and alive(def) and def ~= att then
      for stat, n in pairs(s.foeStages) do self:stage(ev, def, stat, n, att) end
    end
  end
  if s.status then
    if s.statusChance then
      if alive(def) and def ~= att and self.rng(1, 100) <= s.statusChance then self:status(ev, def, s.status, true, att) end
    elseif lucky and alive(target) then
      self:status(ev, target, s.status, damaging, att)
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
  if b.dmax then self:undynamax(ev, b, true) end
  b.guard, b.guardRun, b.endure, b.helped = nil, nil, nil, nil
  if self.sides.team.redirect == b then self.sides.team.redirect = nil end
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

-- the damage a hit on the boss does through its barrier; a hit breaks a segment (its veil is a screen
-- on its side, cut by the adapter)
function Sim:throughBoss(ev, def, dmg)
  if not def.boss then return dmg end
  if def.shield then
    dmg = floor(dmg * (self.rules.SHIELD_DMG or 0.25))
    def.shield.left = def.shield.left - 1
    ev[#ev + 1] = { kind = "shield", step = "hit", who = def, left = def.shield.left, max = def.shield.max }
  end
  return max(1, dmg)
end

-- the members on the field
function Sim:team()
  local t = {}
  for i = 1, #self.members do if self:present(i) then t[#t + 1] = self.members[i] end end
  return t
end

-- a G-Max / Max move's effect on those it hit (`hit`): the boss's on the team, or one of the team's
-- on the boss, its raising and healing on the whole team
function Sim:gmaxEffect(ev, att, mv, hit)
  local e = mv.gmaxEffect
  if not e or not alive(att) then return end
  local W = self.words
  if not att.boss then
    local b = self.boss
    if e.kind == "boost" then
      for _, m in ipairs(self:team()) do for stat, n in pairs(e.self or {}) do self:stage(ev, m, stat, n) end end
      return
    elseif e.kind == "veil" then
      -- (G-Max Resonance: Aurora Veil on the team's side)
      self.sides.team.veil = e.turns or 5
      ev[#ev + 1] = { kind = "side", side = "team", what = "veil", up = true, who = att,
        text = W.teamVeil or "The team is protected by a shimmering veil!" }
      return
    elseif e.kind == "heal" then
      for _, m in ipairs(self:team()) do
        if hpOf(m) < maxHpOf(m) then
          m.mon.hp = min(maxHpOf(m), hpOf(m) + floor(maxHpOf(m) / (e.frac or 6)))
          ev[#ev + 1] = { kind = "heal", who = m, hp = m.mon.hp }
        end
      end
      ev[#ev + 1] = { kind = "field", who = att, text = W.teamHeal or "The team's HP was restored!" }
      return
    elseif e.kind == "cure" then
      for _, m in ipairs(self:team()) do m.status, m.sleep, m.tox = nil, nil, nil end
      ev[#ev + 1] = { kind = "field", who = att, text = W.teamCure or "The team's status returned to normal!" }
      return
    elseif e.kind == "crit" then
      for _, m in ipairs(self:team()) do m.critUp = (m.critUp or 0) + (e.n or 1) end
      ev[#ev + 1] = { kind = "field", who = att, text = W.teamCrit or "The team is getting pumped!" }
      return
    elseif e.kind == "field" then
      if not self.bossField then
        self.bossField = { turns = e.turns or 4, frac = e.frac or 6, spare = e.spareNum, spareName = e.spare }
        local t = W.fieldFoe and W.fieldFoe[e.spare]
        -- (foeField: round the boss - the team's own field look is fieldType's)
        ev[#ev + 1] = { kind = "field", who = att, foeField = e.spare, text = fill(t or "{BOSS} was surrounded!", b) }
      end
      return
    elseif e.kind == "pp" then
      -- (the boss's moves have no PP to lose)
      return
    elseif e.kind == "defog" then
      self:blowAway(ev, "boss", att)
      return
    elseif e.kind == "coins" then
      self.coinUses = self.coinUses + 1
      self.money = self.money + (tonumber(att.mon.level) or 1) * 100 * min(3, self.coinUses)
      ev[#ev + 1] = { kind = "field", who = att, text = W.coins or "Coins were scattered everywhere!" }
      return
    end
    -- status, drowsy, stages, trap: on those it hit (the boss), as below
  elseif e.kind == "defog" then
    self:blowAway(ev, "team", att)
    return
  elseif e.kind == "coins" then
    return
  end
  if e.kind == "status" then
    for _, m in ipairs(hit) do
      if alive(m) then self:status(ev, m, e.list[self.rng(1, #e.list)], true, att) end
    end
  elseif e.kind == "drowsy" then
    for _, m in ipairs(hit) do
      if alive(m) and not m.status and self:sideOf(m).safeguard <= 0 and self.rng(1, 100) <= (e.chance or 50) then
        if W.drowsy then ev[#ev + 1] = { kind = "status", who = m, text = fill(W.drowsy, att, m) } end
        self:status(ev, m, "SLP", true, att)
      end
    end
  elseif e.kind == "stages" then
    for _, m in ipairs(hit) do
      if alive(m) then for stat, n in pairs(e.foe or {}) do self:stage(ev, m, stat, n, att) end end
    end
  elseif e.kind == "boost" then
    for stat, n in pairs(e.self or {}) do self:stage(ev, att, stat, n) end
  elseif e.kind == "pp" then
    for _, m in ipairs(hit) do
      for _, mvm in ipairs(m.moves or {}) do mvm.pp = max(0, (mvm.pp or 0) - (e.n or 2)) end
    end
    ev[#ev + 1] = { kind = "field", who = att, text = fill(W.pp or "The team's moves lost PP!", att) }
  elseif e.kind == "veil" then
    self.sides.boss.veil = e.turns or 5
    self:syncVeil()
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

-- a side's protections blown away (G-Max Wind Rage): its screens, Safeguard and mist
function Sim:blowAway(ev, key, by)
  local sd = self.sides[key]
  local any = false
  for _, k in ipairs({ "reflect", "light", "veil", "safeguard", "mist" }) do
    if sd[k] > 0 then sd[k], any = 0, true end
  end
  self:syncVeil()
  if any then
    local who = key == "boss" and self.boss or nil
    ev[#ev + 1] = { kind = "side", side = key, what = "blown", up = false, who = by,
      text = self:tword("blown", nil, who or { name = "", boss = nil }) or self.words.defog
        or "The veil around the target was blown away!" }
  end
end

-- a protect-like move (Max Guard, Protect and its kin, Endure): the run in a row fails 1 in 3, 9, ...
local function guardRoll(self, att)
  att.guardedThisTurn = true
  local n = att.guardRun or 0
  if n == 0 or self.rng(1, 3 ^ min(n, 6)) == 1 then
    att.guardRun = n + 1
    return true
  end
  att.guardRun = 0
  return false
end

-- what stops `mv` reaching def (before its hit): nil, or "block" / "pierce" (a Max Move's quarter)
-- with the event to show
function Sim:stopped(att, mv, def)
  if mv.pierce or not foes(att, def) then return nil end
  if def.guard == "max" then return "block", { kind = "guard", who = def, blocked = true, max = true,
    text = fill(self.words.guard or "{MON} protected itself!", self.boss, def) } end
  local how, what = nil, nil
  if def.guard == "protect" and not (def.protectRow and def.protectRow.damagingOnly and mv.status) then
    how, what = "protect", "protect"
  else
    local g = self:sideOf(def).guards
    if g.wide and mv.spread then how, what = "guard", "wide"
    elseif g.quick and (mv.priority or 0) > 0 then how, what = "guard", "quick"
    elseif g.mat and not mv.status then how, what = "guard", "mat"
    elseif g.crafty and mv.status then how, what = "guard", "crafty" end
  end
  if not how then return nil end
  if mv.isGmax and not mv.status then
    return "pierce", { kind = "guard", who = def, pierced = true, what = what,
      text = self:tword("pierced", nil, def) or ("%s couldn't fully protect itself and got hurt!"):format(def.name) }
  end
  local text
  if how == "protect" then text = self:tword("protect", nil, def) or ("%s protected itself!"):format(def.name)
  else text = self:tword("guarded", what, def) or ("%s was protected!"):format(def.name) end
  return "block", { kind = "guard", who = def, blocked = true, what = what, text = text }
end

-- a blocked contact move on Spiky Shield / King's Shield / Baneful Bunker / Obstruct
function Sim:contactCost(ev, att, def, mv)
  local c = def.guard == "protect" and def.protectRow and def.protectRow.contact
  if not (c and mv.contact and alive(att)) then return end
  if c.hurt then
    local cut = self:capAtShield(att, min(hpOf(att), max(1, floor(maxHpOf(att) / c.hurt))))
    if cut > 0 then
      att.mon.hp = hpOf(att) - cut
      ev[#ev + 1] = { kind = "residual", who = att, amount = cut, hp = att.mon.hp,
        text = self:tword("hurt", nil, att) or ("%s was hurt!"):format(att.name) }
      if not alive(att) then self:fainted(ev, att) elseif att.boss then self:checkShield(ev) end
    end
  end
  if c.status and alive(att) then self:status(ev, att, c.status, true, def) end
  if c.stages and alive(att) then
    for stat, n in pairs(c.stages) do self:stage(ev, att, stat, n, def) end
  end
end

-- one of the team moves (data/raid_team_moves.lua row T) by att; target: the ally picked
function Sim:teamMove(ev, att, mv, T, target)
  local key = sideKey(att)
  local sd = self.sides[key]
  local function fail() ev[#ev + 1] = { kind = "fail", text = "But it failed!" } end
  local function allies(withSelf)
    local l = {}
    for _, b in ipairs(self:onSide(key)) do if withSelf or b ~= att then l[#l + 1] = b end end
    return l
  end
  local kind = T.kind
  if kind == "screen" then
    if T.needs == "hail" and self.weather ~= "hail" then return fail() end
    if sd[T.screen] > 0 then return fail() end
    sd[T.screen] = T.turns or 5
    self:syncVeil()
    ev[#ev + 1] = { kind = "side", side = key, what = T.screen, up = true, who = att, text = self:tword("screenUp", T.screen, att) }
  elseif kind == "side" then
    if sd[T.flag] > 0 then return fail() end
    sd[T.flag] = T.turns or 5
    ev[#ev + 1] = { kind = "side", side = key, what = T.flag, up = true, who = att, text = self:tword("sideUp", T.flag, att) }
  elseif kind == "guard" then
    if T.guard == "mat" and att.outSince ~= self.turnNo then return fail() end
    sd.guards[T.guard] = true
    ev[#ev + 1] = { kind = "side", side = key, what = T.guard, up = true, who = att, text = self:tword("guardUp", T.guard, att) }
  elseif kind == "protect" then
    if not guardRoll(self, att) then return fail() end
    att.guard, att.protectRow = "protect", T
    ev[#ev + 1] = { kind = "guard", who = att, protect = true, text = self:tword("protect", nil, att) or ("%s protected itself!"):format(att.name) }
  elseif kind == "endure" then
    if not guardRoll(self, att) then return fail() end
    att.endure = true
    ev[#ev + 1] = { kind = "side", side = key, what = "endure", up = true, who = att, text = self:tword("endure", nil, att) }
  elseif kind == "redirect" then
    if att.boss then return fail() end
    sd.redirect = att
    ev[#ev + 1] = { kind = "side", side = key, what = "redirect", up = true, who = att, text = self:tword("redirect", nil, att) }
  elseif kind == "help" then
    if not (target and target ~= att and alive(target) and not foes(att, target) and (target.down or 0) == 0) then return fail() end
    target.helped = true
    ev[#ev + 1] = { kind = "side", side = key, what = "help", up = true, who = att, target = target,
      text = self:tword("help", nil, att, target) }
  elseif kind == "heal" then
    local list
    if T.team then list = allies(true)
    elseif target and target ~= att and alive(target) and not foes(att, target) and (target.down or 0) == 0 then list = { target }
    else return fail() end
    local any = false
    for _, b in ipairs(list) do
      local before = hpOf(b)
      if before < maxHpOf(b) then
        b.mon.hp = min(maxHpOf(b), before + floor(maxHpOf(b) * (T.frac or 0.25) + 0.5))
        ev[#ev + 1] = { kind = "heal", who = b, hp = b.mon.hp, text = self:tword("heal", nil, b) or ("%s's HP was restored."):format(b.name) }
        any = true
      end
      if T.cure and b.status then
        b.status, b.sleep, b.tox = nil, nil, nil
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s's status returned to normal!"):format(b.name) }
        any = true
      end
    end
    if not any then return fail() end
  elseif kind == "cure" then
    local k = squash(mv.key)
    ev[#ev + 1] = { kind = "side", side = key, what = "cure", up = true, who = att,
      text = self:tword(k == "healbell" and "bell" or "aroma") }
    for _, b in ipairs(allies(true)) do
      if b.status then
        b.status, b.sleep, b.tox = nil, nil, nil
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s's status returned to normal!"):format(b.name) }
      end
    end
  elseif kind == "wish" then
    if sd.wish then return fail() end
    local slot = nil
    for i, m in ipairs(self.members) do if m == att then slot = i end end
    sd.wish = { turns = 2, amount = max(1, floor(maxHpOf(att) * (T.frac or 0.5))), slot = slot, name = att.name }
    ev[#ev + 1] = { kind = "side", side = key, what = "wish", up = true, who = att, text = self:tword("wish", nil, att) }
  elseif kind == "sacrifice" then
    if att.boss then return fail() end
    ev[#ev + 1] = { kind = "side", side = key, what = "sacrifice", up = true, who = att, text = self:tword("sacrifice", nil, att) }
    att.mon.hp = 0
    ev[#ev + 1] = { kind = "residual", who = att, amount = 0, hp = 0 }
    self:fainted(ev, att)
  elseif kind == "boost" then
    local list = {}
    if T.grass then
      for _, k in ipairs({ "team", "boss" }) do
        for _, b in ipairs(self:onSide(k)) do if b.type1 == 12 or b.type2 == 12 then list[#list + 1] = b end end
      end
    elseif T.team then list = allies(true)
    elseif T.allies then list = allies(false)
    elseif target and target ~= att and alive(target) and not foes(att, target) and (target.down or 0) == 0 then list = { target } end
    if T.ability then
      local keep = {}
      for _, b in ipairs(list) do
        local ab = self.A.abilityName and self.A.abilityName(b)
        if ab and T.ability[ab] then keep[#keep + 1] = b end
      end
      list = keep
    end
    if #list == 0 then return fail() end
    for _, b in ipairs(list) do
      for _, stat in ipairs({ "attack", "defense", "spAtk", "spDef", "speed" }) do
        local n = T.stages[stat]
        if n then self:stage(ev, b, stat, n, att) end
      end
    end
  else
    ev[#ev + 1] = { kind = "fail", text = "But nothing happened!" }
  end
end

-- whether a team move goes to work as one (Pollen Puff aimed at a foe is an attack)
local function asTeamMove(att, mv, target)
  local T = mv.team
  if not T or mv.isMax then return nil end
  if T.orFoe and (target == nil or foes(att, target)) then return nil end
  return T
end

function Sim:use(ev, att, mv, targets, ally)
  if not alive(att) or self.over then return end
  if self:held(ev, att) then return end
  ev[#ev + 1] = { kind = "use", who = att, move = mv, gmax = mv.isGmax == true,
    text = ("%s used %s!"):format(att.name, mv.name) }
  -- (a Max Move spends its base move's PP)
  if not att.boss then
    local pm = mv.base or mv
    pm.pp = max(0, (pm.pp or 1) - 1)
    if mv.base then mv.pp = pm.pp end
  end
  self.boss.mistSaid = nil
  for _, m in ipairs(self.members) do m.mistSaid = nil end
  -- Max Guard: up until the turn ends
  if mv.guard then
    if guardRoll(self, att) then
      att.guard = "max"
      ev[#ev + 1] = { kind = "guard", who = att, max = true, text = fill(self.words.guard or "{MON} protected itself!", self.boss, att) }
    else
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    end
    return
  end
  -- a team move (screens, guards, heals, ...)
  local T = asTeamMove(att, mv, ally or targets[1])
  if T then return self:teamMove(ev, att, mv, T, ally) end
  -- a status move on its user
  if mv.status and mv.side and mv.side.self then
    self:side(ev, att, att, mv, false)
    return
  end
  local spread = #targets > 1
  local hit = {}
  local key = squash(mv.key)
  for _, def in ipairs(targets) do
    if self.over then return end
    local stop, sev = nil, nil
    if alive(def) then stop, sev = self:stopped(att, mv, def) end
    if stop == "block" then
      ev[#ev + 1] = sev
      self:contactCost(ev, att, def, mv)
    elseif alive(def) and isDmax(def) and (Sim.WEIGHT[key] or Sim.NO_DMAX[key]) then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    elseif alive(def) then
      if not self.A.hits(att, def, mv) then
        ev[#ev + 1] = { kind = "miss", who = att, target = def, text = ("%s avoided the attack!"):format(def.name) }
      elseif mv.status then
        self:side(ev, att, def, mv, false)
      else
        -- (the target side's screens; Helping Hand on the user)
        local sd = self:sideOf(def)
        local dmg, info = self.A.damage(att, def, mv, spread, { reflect = sd.reflect > 0 or sd.veil > 0,
          lightScreen = sd.light > 0 or sd.veil > 0, doubleScreens = not def.boss, helped = att.helped or nil })
        info = info or {}
        local eff = tonumber(info.effectiveness) or 1
        if eff == 0 then
          ev[#ev + 1] = { kind = "effect", eff = 0, target = def, text = ("It doesn't affect %s..."):format(def.name) }
        else
          local hadShield = def.shield ~= nil
          if Sim.ANTI_DMAX[key] and isDmax(def) then dmg = dmg * 2 end
          if stop == "pierce" then dmg = floor(dmg / 4) end
          dmg = self:throughBoss(ev, def, max(1, dmg))
          dmg = self:capAtShield(def, min(hpOf(def), dmg))
          local endured = false
          if def.endure and dmg >= hpOf(def) and hpOf(def) > 1 then dmg, endured = hpOf(def) - 1, true end
          def.mon.hp = hpOf(def) - dmg
          hit[#hit + 1] = def
          ev[#ev + 1] = { kind = "damage", who = att, target = def, amount = dmg, hp = def.mon.hp, move = mv }
          if stop == "pierce" then ev[#ev + 1] = sev end
          if endured then
            ev[#ev + 1] = { kind = "side", side = sideKey(def), what = "endured", up = true, who = def,
              text = self:tword("endured", nil, def) or ("%s endured the hit!"):format(def.name) }
          end
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
      target.down, target.outSince = 0, self.turnNo + 1
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
-- (a team's centre of attention - Follow Me, Rage Powder - draws the boss's single-target moves)
function Sim:targetsFor(att, mv)
  if not att.boss then return { self.boss } end
  local list = {}
  for i = 1, #self.members do
    if self:present(i) then list[#list + 1] = self.members[i] end
  end
  if mv.spread or #list <= 1 then return list end
  local rd = self.sides.team.redirect
  if rd and alive(rd) and (rd.down or 0) == 0 then return { rd } end
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
  -- one of the team's G-Max fields round the boss
  local bf = self.bossField
  if bf then
    if not (bf.spare and (b.type1 == bf.spare or b.type2 == bf.spare)) then
      local t = W.fieldFoeHurt and W.fieldFoeHurt[bf.spareName] or "{BOSS} is hurt!"
      hurt(b, floor(maxHpOf(b) / bf.frac), fill(t, b))
    end
    bf.turns = bf.turns - 1
    if bf.turns <= 0 then self.bossField = nil end
  end
  local trapped = { b }
  for _, m in ipairs(team) do trapped[#trapped + 1] = m end
  for _, m in ipairs(trapped) do
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
  -- a wish comes true at the end of the turn after it was made, on whoever stands in its place
  for _, key in ipairs({ "team", "boss" }) do
    local w = self.sides[key].wish
    if w then
      w.turns = w.turns - 1
      if w.turns <= 0 then
        self.sides[key].wish = nil
        local who = key == "boss" and b or (w.slot and self:present(w.slot) and self.members[w.slot]) or nil
        if who and alive(who) and hpOf(who) < maxHpOf(who) then
          who.mon.hp = min(maxHpOf(who), hpOf(who) + w.amount)
          ev[#ev + 1] = { kind = "heal", who = who, hp = who.mon.hp, wish = true,
            text = self:tword("wishTrue", nil, { name = w.name }) or ("%s's wish came true!"):format(w.name) }
        end
      end
    end
  end
  -- the sides' screens, Safeguard, mist and tailwind run down
  for _, key in ipairs({ "team", "boss" }) do
    local sd = self.sides[key]
    for _, k in ipairs(Sim.SIDE_TURNS) do
      if sd[k] > 0 then
        sd[k] = sd[k] - 1
        if sd[k] == 0 then
          local who = key == "boss" and b or { name = "", boss = nil }
          local text
          if k == "veil" and key == "boss" then text = fill(W.veilEnd or "{BOSS}'s veil wore off!", b)
          else
            text = self:tword((k == "reflect" or k == "light" or k == "veil") and "screenEnd" or "sideEnd", k, who)
              or (k == "veil" and W.teamVeilEnd) or nil
          end
          ev[#ev + 1] = { kind = "side", side = key, what = k, up = false, who = who.boss and b or nil, text = text }
        end
      end
    end
    -- the turn's guards and centre of attention
    sd.guards, sd.redirect = {}, nil
  end
  self:syncVeil()
  -- a protect-like move lasts the turn; a turn without one starts the count again; Helping Hand and
  -- Endure the turn
  local everyone = { b }
  for _, m in ipairs(self.members) do everyone[#everyone + 1] = m end
  for _, m in ipairs(everyone) do
    if not m.guardedThisTurn then m.guardRun = 0 end
    m.guard, m.guardedThisTurn, m.protectRow, m.endure, m.helped = nil, nil, nil, nil, nil
  end
  -- a Dynamaxed member's third turn ends: back to its own size
  local d = self.dmaxActive
  if d and d.dmax then
    d.dmax.turns = d.dmax.turns - 1
    if d.dmax.turns <= 0 then self:undynamax(ev, d) end
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
        m.mon.hp, m.outSince = maxHpOf(m), self.turnNo + 1
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
  -- Dynamax first, before anyone moves
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    if c and c.dmax and c.move and self:canDynamax(i) then self:dynamax(ev, m, i) end
  end
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    if self:canAct(i) and c then
      if c.item and self.members[c.target or i] then
        acts[#acts + 1] = { who = m, item = c.item, target = self.members[c.target or i], pri = itemPri,
          tie = self.rng(1, 65536) }
      elseif c.move and m.moves[c.move] then
        -- (Dynamaxed: the move's Max form)
        local mv = (m.dmax and m.maxMoves and m.maxMoves[c.move]) or m.moves[c.move]
        -- (an ally move's pick: a member's slot, or "boss")
        local ally = type(c.target) == "number" and self.members[c.target] or nil
        acts[#acts + 1] = { who = m, mv = mv, ally = ally, pri = mv.priority or 0, tie = self.rng(1, 65536) }
      end
    elseif (m.down or 0) == 1 then
      -- sitting out this turn: it cheers in its place
      acts[#acts + 1] = { who = m, cheer = true, pri = 0, tie = self.rng(1, 65536) }
    end
  end
  local bmv = self:bossMove()
  if bmv then acts[#acts + 1] = { who = self.boss, mv = bmv, pri = bmv.priority or 0, tie = self.rng(1, 65536) } end
  -- (Tailwind doubles its side's Speed)
  for _, a in ipairs(acts) do a.speed = self.A.speed(a.who) * (self:sideOf(a.who).tailwind > 0 and 2 or 1) end
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
      self:use(ev, a.who, a.mv, self:targetsFor(a.who, a.mv), a.ally)
    end
  end
  if not self.over then self:endTurn(ev) end
  if not self.over then
    self.turnNo = self.turnNo + 1
    if self.turnNo > (self.rules.TURNS or 10) then self.over = "storm" end
  end
  -- the next turn's Dynamax Energy
  self:giveEnergy()
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
