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
--   "storm" | nil) ; sim:canDynamax(i) ; sim.money
-- Dynamax: any member may Dynamax while no other is Dynamaxed - one that has not yet, can
-- (m.canDmax not false) and is on the field; one at a time (the first to choose it in a turn), at
-- the turn's start: its HP and max HP x
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
  -- (the battle state the National Dex's rules read; a stand-in adapter gets one)
  self.A.st = self.A.st or {}
  self.rng = o.rng or function(lo, hi) return lo + floor(math.random() * (hi - lo + 1)) end
  self.rules = o.rules or { TURNS = 10, FAINTS = 4 }
  self.words = o.words or {}
  self.tw = o.teamWords or {}
  self.turnNo, self.faints, self.over = 1, 0, nil
  for _, m in ipairs(self.members) do m.down, m.outSince = 0, 1 end
  local b = self.boss
  b.shieldsUsed, b.veil, b.critUp, b.outSince = {}, 0, 0, 1
  self.sides = { team = Sim.newSide(), boss = Sim.newSide() }
  -- the National Dex's field: terrain, Trick / Wonder / Magic Room
  self.ndx = {}
  -- the raid's own pouch, shared by the team for this raid
  self.pouch = {}
  for _, it in ipairs(self.rules.POUCH or {}) do
    self.pouch[it.id] = { id = it.id, n = it.n, heal = it.heal }
  end
  -- Dynamax: who holds the Energy, who has used it, who is Dynamaxed; coins picked up
  self.dmaxUsed, self.dmaxActive = {}, nil
  self.money, self.coinUses = 0, 0
  return self
end

local function hpOf(b) return tonumber(b.mon.hp) or 0 end
local function maxHpOf(b) return max(1, tonumber(b.mon.maxHp) or 1) end
local function alive(b) return hpOf(b) > 0 end
-- whether a battler may be healed (Heal Block)
local function canHeal(b) return (b.__ndxHealBlock or 0) <= 0 end
-- a move's id squashed: "LOW_KICK" -> "lowkick"
local function squash(key) return type(key) == "string" and key:lower():gsub("[^%w]", "") or "" end
-- the boss is always Dynamaxed
local function isDmax(b) return b.boss or b.dmax ~= nil end
Sim.WEIGHT = { lowkick = true, grassknot = true, heatcrash = true, heavyslam = true }
Sim.NO_DMAX = { encore = true, disable = true, instruct = true, roar = true, whirlwind = true }
Sim.ANTI_DMAX = { behemothblade = true, behemothbash = true, dynamaxcannon = true }
Sim.FIRST_TURN = { fakeout = true, firstimpression = true }
Sim.SPREAD_K = 3072 / 4096
Sim.SELF_KO = { explosion = true, selfdestruct = true, mistyexplosion = true }
Sim.HALF_COST = { mindblown = true, steelbeam = true, chloroblast = true }
local function fill(text, boss, mon)
  return ((text or ""):gsub("{BOSS}", boss and boss.name or ""):gsub("{MON}", mon and mon.name or ""))
end

-- ------- the two sides

-- what lasts on one side: screens, safeguard, mist, tailwind (turns left); the turn's guards and
-- centre of attention; a wish waiting
function Sim.newSide()
  return { reflect = 0, light = 0, veil = 0, safeguard = 0, mist = 0, tailwind = 0, luckyChant = 0, guards = {},
    redirect = nil, wish = nil, hazards = {} }
end
Sim.SIDE_TURNS = { "reflect", "light", "veil", "safeguard", "mist", "tailwind", "luckyChant" }
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
-- (a member locked into a move - a charge's second turn, a rampage - or recharging does not choose)
function Sim:canAct(i)
  if self.over or not self:present(i) then return false end
  local m = self.members[i]
  return not (m.lock or m.recharge)
end
function Sim:pouchLeft(id) local it = self.pouch[id]; return it and it.n or 0 end

-- ------- Dynamax

local function eligible(self, i)
  local m = self.members[i]
  return m ~= nil and not self.dmaxUsed[i] and m.canDmax ~= false and self:present(i)
end
-- whether member i may Dynamax now: any member not yet Dynamaxed this raid, while no one is giant
function Sim:canDynamax(i)
  return not self.over and self.dmaxActive == nil and eligible(self, i)
end

function Sim:dynamax(ev, m, i)
  local mult = m.dmaxMult or (1.5 + 0.05 * (m.dmaxLevel or 0))
  local base = maxHpOf(m)
  m.mon.maxHp = floor(base * mult)
  m.mon.hp = max(1, floor(hpOf(m) * mult))
  m.dmax = { turns = 3, mult = mult, baseMax = base }
  -- (a Choice item's hold is let go)
  m.choiced = nil
  self.dmaxUsed[i], self.dmaxActive = true, m
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

-- (by: who caused it - a drop from any other, an ally's spread move too, is stopped by the side's mist)
function Sim:stage(ev, b, stat, n, by)
  if n < 0 and by and by ~= b and self:sideOf(b).mist > 0 then
    if not b.mistSaid then
      b.mistSaid = true
      ev[#ev + 1] = { kind = "fail", who = b, text = self:tword("misted", nil, b) or ("%s is protected by the mist!"):format(b.name) }
    end
    return
  end
  b.stages[stat] = b.stages[stat] or 0
  -- (Simple doubles every change)
  if b.raidAbility == "SIMPLE" then n = n * 2 end
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
-- other side or an ally's spread move, the side's Safeguard stops it)
function Sim:status(ev, b, st, quiet, by)
  if by and by ~= b and self:sideOf(b).safeguard > 0 and not b.status then
    if not quiet then
      ev[#ev + 1] = { kind = "fail", who = b, text = self:tword("safeguarded", nil, b) or ("%s is protected by Safeguard!"):format(b.name) }
    end
    return false
  end
  local immune = STATUS_IMMUNE[st]
  -- (Misty Terrain keeps every status off a grounded Pokemon, Electric Terrain sleep; Insomnia sleep)
  local terrain = self.terrain and self:terrain()
  local kept = terrain and self:grounded(b) and (terrain == "MISTY" or (terrain == "ELECTRIC" and st == "SLP"))
  if st == "SLP" and (b.raidAbility == "INSOMNIA" or (self.uproar and alive(self.uproar))) then kept = true end
  if b.status or kept or (immune and (immune[b.type1] or immune[b.type2 or -1])) then
    if not quiet then ev[#ev + 1] = { kind = "fail", text = "But it failed!" } end
    return false
  end
  b.status = st
  if st == "SLP" then b.sleep = self.rng(2, 5) end
  if st == "TOX" then b.tox = 0 end
  ev[#ev + 1] = { kind = "status", who = b, status = st, text = STATUS_TEXT[st]:format(b.name) }
  return true
end

-- draining (heal a share of the damage dealt) and recoil (lose a share of it): the share is s.drain %
function Sim:drain(ev, att, def, s, dealt)
  if s.drain and dealt and dealt > 0 and alive(att) then
    local amt = floor(dealt * math.abs(s.drain) / 100 + 0.5)
    if amt > 0 then
      if s.drain > 0 then
        if not canHeal(att) then return end
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
  self:drain(ev, att, def, s, dealt)
  -- the effects that act on more than a stat or a status
  if self:specials(ev, att, def, mv, s, damaging) == false then return end
  -- `chance` gates the stat changes (and a Gen 3 effect's status); `statusChance` its own status
  local lucky = not (s.chance and s.chance > 0 and self.rng(1, 100) > s.chance)
  local target = s.self and att or def
  if s.heal and alive(target) and canHeal(target) then
    local before = hpOf(target)
    local share = s.heal
    if s.weatherHeal then share = self.weather == "SUN" and 2 / 3 or self.weather and 1 / 4 or 1 / 2 end
    if s.sandHeal and self.weather == "SAND" then share = s.sandHeal end
    target.mon.hp = min(maxHpOf(target), before + floor(maxHpOf(target) * share))
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

-- a hurt that spends HP of its own: att loses `cut` (held up by the barrier), the words `text`
function Sim:selfHurt(ev, att, cut, text)
  cut = self:capAtShield(att, min(hpOf(att), max(1, cut)))
  att.mon.hp = hpOf(att) - cut
  ev[#ev + 1] = { kind = "residual", who = att, amount = cut, hp = att.mon.hp, text = text }
  if att.boss then self:checkShield(ev) end
  if not alive(att) then self:fainted(ev, att) end
end

-- the Gen 3 effects beyond stat changes, statuses, draining and healing (Battle.EFFECT_SIDE): returns
-- false when the move is spent (it failed)
function Sim:specials(ev, att, def, mv, s, damaging)
  -- a Gen 3 status move (Stockpile, Substitute, Disable ...); Defense Curl doubles Rollout after
  if s.g3 and not damaging then
    local r = self:g3Status(ev, att, def, mv, s.g3)
    if r == false then return false end
  end
  if s.curl then att.curled = true end
  -- a status move with the National Dex's rule
  if s.rule and not damaging then
    local r = self:statusRule(ev, att, def, mv, s.rule)
    if r == false then return false end
  end
  -- Focus Energy: critical hits more likely
  if s.focus then
    att.critUp = 2
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s is getting pumped!"):format(att.name) }
  end
  -- Belly Drum: half the user's HP for the Attack stat at +6
  if s.bellyDrum then
    if hpOf(att) <= floor(maxHpOf(att) / 2) or (att.stages.attack or 0) >= 6 then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    self:selfHurt(ev, att, floor(maxHpOf(att) / 2), ("%s cut its own HP and maximized its Attack!"):format(att.name))
    att.stages.attack = 6
    ev[#ev + 1] = { kind = "stage", who = att, stat = "attack", n = 6, text = ("%s's Attack was maximized!"):format(att.name) }
  end
  -- Haze: every stat change on the field gone
  if s.haze then
    for _, b in ipairs(self.members) do for k in pairs(b.stages) do b.stages[k] = 0 end end
    for k in pairs(self.boss.stages) do self.boss.stages[k] = 0 end
    ev[#ev + 1] = { kind = "field", who = att, text = "All stat changes were eliminated!" }
  end
  -- Rest: full HP, two turns asleep, a status cured
  if s.rest then
    if hpOf(att) >= maxHpOf(att) or att.status == "SLP" then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    att.status, att.tox = "SLP", nil
    att.sleep = 3
    att.mon.hp = maxHpOf(att)
    ev[#ev + 1] = { kind = "heal", who = att, hp = att.mon.hp, text = ("%s slept and became healthy!"):format(att.name) }
  end
  -- Leech Seed: the target loses 1/8 of its HP each turn, healing the seeder (not a Grass type)
  if s.seed then
    local grass = 12
    if not alive(def) or def.seeded or def.type1 == grass or def.type2 == grass then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    def.seeded = att
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s was seeded!"):format(def.name) }
  end
  -- Pain Split: the two share their HP out evenly
  if s.painSplit then
    local avg = floor((hpOf(att) + hpOf(def)) / 2)
    local cut = hpOf(def) - avg
    if cut > 0 then cut = self:capAtShield(def, cut); def.mon.hp = hpOf(def) - cut
    else def.mon.hp = min(maxHpOf(def), avg) end
    att.mon.hp = min(maxHpOf(att), avg)
    ev[#ev + 1] = { kind = "heal", who = att, hp = att.mon.hp, text = "The battlers shared their pain!" }
    if def.boss then self:checkShield(ev) end
  end
  -- Trap: the target is held and hurt for 4-5 turns
  if s.trap and damaging and alive(def) and (def.trap or 0) == 0 then
    def.trap, def.trapFrac = self.rng(4, 5), 8
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s was trapped!"):format(def.name) }
  end
  -- Confusion (a hit's chance, or the move's own)
  if s.confuse and alive(def) and def ~= att then
    if self.rng(1, 100) <= s.confuse then
      if not self:confuse(ev, def, att) and not damaging then
        ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      end
    elseif not damaging then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    end
  end
  -- Flinching: a Dynamax Pokemon (the boss) cannot be flinched; the target must not have moved yet
  if s.flinch and alive(def) and not isDmax(def) and def.actedTurn ~= self.turnNo and self.rng(1, 100) <= s.flinch then
    def.flinched = true
  end
  -- Tri Attack: a burn, paralysis or freeze
  if s.tri and alive(def) and self.rng(1, 100) <= s.tri then
    self:status(ev, def, ({ "BRN", "PAR", "FRZ" })[self.rng(1, 3)], true, att)
  end
  -- weather: five turns of rain, sun, sandstorm or hail
  if s.weather then
    if self.weather == s.weather then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    self.weather, self.weatherTurns = s.weather, 5
    ev[#ev + 1] = { kind = "field", who = att, weather = s.weather, text = Sim.WEATHER_TEXT[s.weather].up }
  end
  -- Attract: infatuation (a male and a female only)
  if s.attract then
    if not self:attract(ev, def, att) then ev[#ev + 1] = { kind = "fail", text = "But it failed!" } end
  end
  -- Curse: a Ghost pays half its HP to curse the foe (a quarter of the foe's HP a turn); anything
  -- else trades Speed for Attack and Defense
  if s.curse then
    if att.type1 == 7 or att.type2 == 7 then
      if def.cursed or not alive(def) then
        ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
        return false
      end
      self:selfHurt(ev, att, floor(maxHpOf(att) / 2), ("%s cut its own HP and laid a curse on %s!"):format(att.name, def.name))
      def.cursed = true
    else
      self:stage(ev, att, "speed", -1)
      self:stage(ev, att, "attack", 1)
      self:stage(ev, att, "defense", 1)
    end
  end
  -- Nightmare: a sleeping target loses a quarter of its HP each turn it sleeps
  if s.nightmare then
    if def.status ~= "SLP" or def.nightmare then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    def.nightmare = true
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s began having a nightmare!"):format(def.name) }
  end
  -- Lock-On and Mind Reader: the user's next move cannot miss
  if s.lockOn and alive(def) then
    att.lockOn = def
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s took aim at %s!"):format(att.name, def.name) }
  end
  -- Ingrain: roots that restore 1/16 of the user's HP each turn
  if s.ingrain then
    if att.ingrained then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
    att.ingrained = true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s planted its roots!"):format(att.name) }
  end
  -- Refresh: the user's paralysis, poison or burn cured
  if s.refresh then
    if att.status == "PSN" or att.status == "TOX" or att.status == "BRN" or att.status == "PAR" then
      att.status, att.tox = nil, nil
      ev[#ev + 1] = { kind = "status", who = att, status = nil, text = ("%s's status returned to normal!"):format(att.name) }
    else
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return false
    end
  end
  -- Memento: the user faints after lowering the foe's stats
  if s.userFaints and alive(att) then
    -- (the stat drops come first)
    local after = s.stages
    if after then for stat, n in pairs(after) do self:stage(ev, def, stat, n, att) end end
    att.mon.hp = 0
    ev[#ev + 1] = { kind = "residual", who = att, amount = 0, hp = 0 }
    self:fainted(ev, att)
    return false
  end
  return true
end

-- ------- a battler's lock: one move it is held to, of one kind (b.lock.kind) -
--   charge   a move's charging turn; released on its next turn (Fly, Solar Beam, Geomancy)
--   rollout  Rollout / Ice Ball growing (b.lock.rollout, the next hit's step)
--   uproar   Uproar's turns (the field's sim.uproar its holder: no one sleeps)
--   bide     Bide's two turns (stored, from)
--   encore   Encore's turns, on the target's last move
--   rampage  Outrage and kin, 2-3 turns, then confused
Sim.LOCK_KINDS = { charge = true, rollout = true, uproar = true, bide = true, encore = true, rampage = true }

-- b's lock when it is of that kind
local function lockOf(b, kind)
  local L = b.lock
  return L and L.kind == kind and L or nil
end
Sim.lockOf = lockOf

-- b's lock let go (and the uproar with it, when b holds it); keepEncore: an Encore stays (a flinch
-- or a turn lost to sleep ends a charge, a Rollout or a rampage, not an Encore)
function Sim:unlock(b, keepEncore)
  local L = b.lock
  if not L or (keepEncore and L.kind == "encore") then return end
  b.lock = nil
  if self.uproar == b then self.uproar = nil end
end

-- the raid's outcome: the first one set holds, but the boss falling outranks a knock-out or the storm
-- in the same moment (a recoil's 4th knock-out on the blow that felled the boss is a win)
local OUTCOME_RANK = { win = 3, faints = 2, storm = 1 }
function Sim:endWith(outcome)
  if not self.over or (OUTCOME_RANK[outcome] or 0) > (OUTCOME_RANK[self.over] or 0) then self.over = outcome end
end

-- a battler down: the boss (won), or a member (it sits the next turn out; every knock-out counts)
function Sim:fainted(ev, b)
  ev[#ev + 1] = { kind = "faint", who = b, text = ("%s fainted!"):format(b.name) }
  if self.noteFainted then self:noteFainted(b) end
  if b.boss then
    self:endWith("win")
    return
  end
  self.faints = self.faints + 1
  if b.dmax then self:undynamax(ev, b, true) end
  b.guard, b.guardRun, b.endure, b.helped, b.confused, b.attract, b.torment = nil, nil, nil, nil, nil, nil, nil
  self:unlock(b)
  b.recharge, b.semi, b.flinched, b.seeded, b.critUp = nil, nil, nil, nil, nil
  b.__ndxAquaRing, b.__ndxSaltCure, b.__ndxOctolock, b.__ndxMagnetRise, b.__ndxHealBlock = nil, nil, nil, nil, nil
  b.__ndxStat, b.__ndxGrounded, b.__ndxType3, b.__ndxTarShot, b.__ndxGlaiveRush = nil, nil, nil, nil, nil
  b.perish, b.yawn, b.destinyBond, b.grudge, b.substituteHP, b.taunt, b.disabled = nil, nil, nil, nil, nil, nil, nil
  b.raging, b.furyCutter, b.stockpile, b.expCharged, b.imprison, b.curled = nil, nil, nil, nil, nil, nil
  b.choiced = nil
  if self.uproar == b then self.uproar = nil end
  -- (whoever loved it: it has left the field)
  if self.boss.attract == b then self.boss.attract = nil end
  if self.sides.team.redirect == b then self.sides.team.redirect = nil end
  b.down = 2
  b.status, b.sleep, b.tox, b.trap = nil, nil, nil, nil
  if self.faints >= (self.rules.FAINTS or 4) then self:endWith("faints") end
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
function Sim:held(ev, b, mv)
  if b.flinched then
    b.flinched, b.semi = nil, nil
    self:unlock(b, true)
    ev[#ev + 1] = { kind = "cant", who = b, text = ("%s flinched and couldn't move!"):format(b.name) }
    return true
  end
  if b.status == "SLP" then
    b.sleep = (b.sleep or 1) - 1
    if b.sleep > 0 then
      ev[#ev + 1] = { kind = "cant", who = b, ail = "SLP", text = ("%s is fast asleep."):format(b.name) }
      -- (Snore and Sleep Talk are used asleep)
      local g = mv and mv.side and mv.side.g3
      if g == "SNORE" or g == "SLEEP_TALK" then return false end
      return true
    end
    b.status, b.sleep = nil, nil
    ev[#ev + 1] = { kind = "status", who = b, status = nil, text = ("%s woke up!"):format(b.name) }
  elseif b.status == "FRZ" then
    if self.rng(1, 5) ~= 1 then
      ev[#ev + 1] = { kind = "cant", who = b, ail = "FRZ", text = ("%s is frozen solid!"):format(b.name) }
      return true
    end
    b.status = nil
    ev[#ev + 1] = { kind = "status", who = b, status = nil, text = ("%s thawed out!"):format(b.name) }
  end
  -- confused (G-Max Smite, Gold Rush): 2-5 turns, a 1 in 3 chance each turn to strike itself instead
  -- (Gen 7 on), a 40-power typeless physical blow (the adapter's confusionHit)
  if b.confused then
    b.confused = b.confused - 1
    if b.confused <= 0 then
      b.confused = nil
      ev[#ev + 1] = { kind = "status", who = b, text = ("%s snapped out of its confusion!"):format(b.name) }
    else
      ev[#ev + 1] = { kind = "cant", who = b, confused = true, text = ("%s is confused!"):format(b.name) }
      if self.rng(1, 3) == 1 then
        local cut = (self.A.confusionHit and self.A.confusionHit(b)) or max(1, floor(maxHpOf(b) / 8))
        cut = self:capAtShield(b, min(hpOf(b), cut))
        b.mon.hp = hpOf(b) - cut
        ev[#ev + 1] = { kind = "residual", who = b, amount = cut, hp = b.mon.hp,
          text = "It hurt itself in its confusion!" }
        if not alive(b) then self:fainted(ev, b) elseif b.boss then self:checkShield(ev) end
        return true
      end
    end
  end
  -- in love (G-Max Cuddle): while the one it loves is on the field, half the time it cannot move
  if b.attract then
    local by = b.attract
    if not alive(by) or (by.down or 0) > 0 then
      b.attract = nil
    else
      ev[#ev + 1] = { kind = "cant", who = b, attract = true, text = ("%s is in love with %s!"):format(b.name, by.name) }
      if self.rng(1, 100) <= 50 then
        ev[#ev + 1] = { kind = "cant", who = b, attract = true, text = ("%s is immobilized by love!"):format(b.name) }
        return true
      end
    end
  end
  if b.status == "PAR" and self.rng(1, 4) == 1 then
    ev[#ev + 1] = { kind = "cant", who = b, ail = "PAR", text = ("%s is paralyzed! It can't move!"):format(b.name) }
    return true
  end
  return false
end

-- Torment (G-Max Meltdown): not the same move twice in a row until it leaves the field; a Dynamax
-- Pokemon is immune (the boss always)
function Sim:torment(ev, b)
  if not alive(b) or b.torment or isDmax(b) or (b.down or 0) > 0 then return false end
  b.torment = true
  ev[#ev + 1] = { kind = "status", who = b, torment = true,
    text = fill(self.words.torment or "{MON} was subjected to torment!", self.boss, b) }
  return true
end
-- whether a tormented battler is barred from `mv` now (its last move, and it has another to use)
function Sim:tormented(b, mv)
  if not b.torment or isDmax(b) or not b.lastMove then return false end
  local pm = mv.base or mv
  if pm ~= b.lastMove then return false end
  for _, other in ipairs(b.moves or {}) do
    if other ~= pm and (other.pp or 0) > 0 then return true end
  end
  return false
end

-- Gravity (G-Max Gravitas) over the whole field for `turns`
Sim.NO_GRAVITY = { fly = true, bounce = true, skydrop = true, splash = true, highjumpkick = true, hijumpkick = true,
  jumpkick = true, magnetrise = true, telekinesis = true, flyingpress = true, floatyfall = true }
function Sim:setGravity(ev, by, turns)
  if (self.gravity or 0) > 0 then return false end
  self.gravity = turns
  ev[#ev + 1] = { kind = "side", side = "field", what = "gravity", up = true, who = by,
    text = self.words.gravity or "Gravity intensified!" }
  return true
end

-- infatuation (by: who it falls for): only between a male and a female ("M" / "F", the battlers'
-- `gender`), never the genderless; an Oblivious Pokemon is immune; Safeguard does not stop it
function Sim:attract(ev, b, by)
  if not (alive(b) and by and alive(by)) or b.attract or (b.down or 0) > 0 then return false end
  local g1, g2 = b.gender, by.gender
  if not ((g1 == "M" and g2 == "F") or (g1 == "F" and g2 == "M")) then return false end
  if self.A.abilityName and self.A.abilityName(b) == "OBLIVIOUS" then return false end
  b.attract = by
  ev[#ev + 1] = { kind = "status", who = b, attract = true,
    text = fill(self.words.attract or "{MON} fell in love!", self.boss, b) }
  return true
end

-- confusion (by: who caused it - the other side's Safeguard stops it)
function Sim:confuse(ev, b, by)
  if not alive(b) or b.confused or (b.down or 0) > 0 then return false end
  if self:terrain() == "MISTY" and self:grounded(b) then return false end
  if by and by ~= b and self:sideOf(b).safeguard > 0 then return false end
  b.confused = self.rng(2, 5)
  ev[#ev + 1] = { kind = "status", who = b, confused = true,
    text = fill(self.words.confused or "{MON} became confused!", self.boss, b) }
  return true
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
-- the boss and every member, on the field or not
function Sim:everyone()
  local t = { self.boss }
  for _, m in ipairs(self.members) do t[#t + 1] = m end
  return t
end

function Sim:team()
  local t = {}
  for i = 1, #self.members do if self:present(i) then t[#t + 1] = self.members[i] end end
  return t
end

-- a G-Max / Max move's effect on those it hit (`hit`): the boss's on the team, or one of the team's
-- on the boss, its raising and healing on the whole team
-- (a Max / G-Max Move has one target: `hit` is that one; scope "foes" reaches every opponent on the
-- field; confuse confuses them all besides)
function Sim:gmaxEffect(ev, att, mv, hit)
  local e = mv.gmaxEffect
  if not e or not alive(att) then return end
  if e.scope == "foes" then hit = self:onSide(att.boss and "team" or "boss") end
  if e.kind == "gravity" then self:setGravity(ev, att, e.turns or 5)
  else self:gmaxMain(ev, att, mv, hit, e) end
  if e.torment and not self.over and alive(att) then
    for _, m in ipairs(self:onSide(att.boss and "team" or "boss")) do self:torment(ev, m) end
  end
  if e.confuse and not self.over and alive(att) then
    for _, m in ipairs(self:onSide(att.boss and "team" or "boss")) do self:confuse(ev, m, att) end
  end
  if e.attract and not self.over and alive(att) then
    for _, m in ipairs(self:onSide(att.boss and "team" or "boss")) do self:attract(ev, m, att) end
  end
end

function Sim:gmaxMain(ev, att, mv, hit, e)
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
    -- (the last move each used loses n PP)
    for _, m in ipairs(hit) do
      local last = m.lastMove
      if last and alive(m) then
        local cut = min(last.pp or 0, e.n or 2)
        last.pp = (last.pp or 0) - cut
        if cut > 0 then
          ev[#ev + 1] = { kind = "field", who = m,
            text = ("%s's %s lost %d PP!"):format(m.name, last.name or "move", cut) }
        end
      end
    end
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
-- (an ally's spread move too: Protect, Max Guard and the side's guards stand against it)
function Sim:stopped(att, mv, def)
  if mv.pierce or att == def then return nil end
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
    if T.needs == "hail" and self.weather ~= "HAIL" then return fail() end
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

-- ------- the National Dex's rules (its src/move_rules.lua, src/move_field.lua carried out here)
--
-- A newer move with a rule (Bt.move: `mv.side.rule`) runs it as National Dex Gen 3 does in the
-- engine's battle. The power, stats and type rules (Hex, Gyro Ball, Foul Play, Electrify ...) live in
-- its Damage.calc wraps, which read the battle state the adapter hands them (`A.st`: the turn, the
-- field) and the battlers' own marks (`__ndx*`); the sim keeps those marks up. The rest - the field,
-- the sides' hazards, the status moves, what follows a hit - is here.

local T_ = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16,
  DARK = 17, FAIRY = 18 }
Sim.TYPE = T_
Sim.TYPE_NAME = { [0] = "Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel", "???",
  "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark", "Fairy" }

Sim.TERRAIN = {
  MISTY_TERRAIN = { kind = "MISTY", up = "Mist swirled around the battlefield!", down = "The mist disappeared from the battlefield." },
  GRASSY_TERRAIN = { kind = "GRASSY", up = "Grass grew to cover the battlefield!", down = "The grass disappeared from the battlefield." },
  ELECTRIC_TERRAIN = { kind = "ELECTRIC", up = "An electric current ran across the battlefield!", down = "The electricity disappeared from the battlefield." },
  PSYCHIC_TERRAIN = { kind = "PSYCHIC", up = "The battlefield got weird!", down = "The weirdness disappeared from the battlefield!" },
}
local TERRAIN_DOWN = {}
for _, t in pairs(Sim.TERRAIN) do TERRAIN_DOWN[t.kind] = t.down end
-- the field's own timers: their words when they end
Sim.FIELD_END = { trickRoom = "The twisted dimensions returned to normal!",
  wonderRoom = "Wonder Room wore off, and Defense and Sp. Def stats returned to normal!",
  magicRoom = "Magic Room wore off, and held items' effects returned to normal!" }
-- the sound moves (Throat Chop bars them)
Sim.SOUND = {}
for _, k in ipairs({ "alluringvoice", "boomburst", "bugbuzz", "chatter", "clangingscales", "clangoroussoul", "confide",
  "disarmingvoice", "echoedvoice", "eeriespell", "grasswhistle", "growl", "healbell", "howl", "hypervoice", "metalsound",
  "nobleroar", "overdrive", "partingshot", "perishsong", "psychicnoise", "relicsong", "roar", "round", "screech", "sing",
  "snarl", "snore", "sparklingaria", "supersonic", "torchsong", "uproar" }) do Sim.SOUND[k] = true end

-- the field the National Dex's damage rules read (`st.__ndxField`): the terrain, Wonder Room, Gravity
function Sim:ndxField()
  local f = self.ndx
  f.gravity = (self.gravity or 0) > 0 and self.gravity or nil
  return f
end
function Sim:terrain()
  local f = self.ndx
  return (f.terrainTurns or 0) > 0 and f.terrain or nil
end

-- on the ground: terrains, Toxic Spikes and Sticky Web touch only these
function Sim:grounded(b)
  if b.__ndxGrounded or (self.gravity or 0) > 0 then return true end
  if b.semi or (b.__ndxMagnetRise or 0) > 0 then return false end
  if b.type1 == T_.FLYING or b.type2 == T_.FLYING or b.__ndxType3 == T_.FLYING then return false end
  if self.A.abilityName and self.A.abilityName(b) == "LEVITATE" then return false end
  return true
end

Sim.canHeal = function(_, b) return canHeal(b) end

function Sim:hasType(b, t) return b.type1 == t or b.type2 == t or b.__ndxType3 == t end

-- the battler's side for the National Dex's marks ("player" / "enemy")
local function ndxSide(b) return b.side or (b.boss and "enemy" or "player") end

-- a heal of `amt` (none under Heal Block); the event's words
function Sim:healFor(ev, b, amt, text)
  if not alive(b) or not canHeal(b) or hpOf(b) >= maxHpOf(b) then return false end
  b.mon.hp = min(maxHpOf(b), hpOf(b) + max(1, floor(amt)))
  ev[#ev + 1] = { kind = "heal", who = b, hp = b.mon.hp, text = text or ("%s regained health!"):format(b.name) }
  return true
end

-- a stat's value with the National Dex's overrides (Power Split, Power Trick, Speed Swap)
local function statOf(b, k)
  local over = b.__ndxStat
  return tonumber(over and over[k]) or tonumber(b.mon[k]) or 0
end

-- what runs into a member coming back onto the field: its side's hazards
function Sim:entry(ev, m)
  local hz = self:sideOf(m).hazards
  if not alive(m) then return end
  if hz.stealthRock then
    local eff = self.A.effectiveness and self.A.effectiveness(T_.ROCK, m) or 1
    local cut = max(1, floor(maxHpOf(m) * eff / 8))
    self:selfHurt(ev, m, cut, ("Pointed stones dug into %s!"):format(m.name))
    if not alive(m) then return end
  end
  if (hz.spikes or 0) > 0 and self:grounded(m) then
    local div = ({ 8, 6, 4 })[min(3, hz.spikes)]
    self:selfHurt(ev, m, floor(maxHpOf(m) / div), ("%s was hurt by the spikes!"):format(m.name))
    if not alive(m) then return end
  end
  if (hz.toxicSpikes or 0) > 0 and self:grounded(m) then
    if self:hasType(m, T_.POISON) then
      hz.toxicSpikes = nil
      ev[#ev + 1] = { kind = "side", side = sideKey(m), what = "toxicSpikes", up = false,
        text = ("The poison spikes disappeared from around %s's feet!"):format(m.name) }
    elseif not self:hasType(m, T_.STEEL) then
      self:status(ev, m, hz.toxicSpikes >= 2 and "TOX" or "PSN", true)
    end
  end
  if hz.stickyWeb and self:grounded(m) then
    ev[#ev + 1] = { kind = "status", who = m, text = ("%s was caught in a sticky web!"):format(m.name) }
    self:stage(ev, m, "speed", -1)
  end
end

-- before the move is used: true when it fails (Sucker Punch with nothing coming, Last Resort ...)
function Sim:ruleFails(att, mv, targets, act)
  local rule = mv.side and mv.side.rule
  if not rule then return false end
  local def = targets[1]
  if rule == "SUCKER_PUNCH" then
    -- (the target must be about to attack: it has not moved, and its move this turn hits)
    if not def or def.__ndxMovedTurn == self.turnNo then return true end
    local next = self.pendingMove and self.pendingMove[def]
    return not (next and not next.status)
  elseif rule == "FIRST_IMPRESSION" then
    return att.outSince ~= self.turnNo
  elseif rule == "LAST_RESORT" then
    local used, n = att.__ndxUsedMoves or {}, 0
    for _, m in ipairs(att.moves or {}) do
      if m ~= mv then
        n = n + 1
        if not used[m] then return true end
      end
    end
    return n == 0
  elseif rule == "BURN_UP" then return not self:hasType(att, T_.FIRE)
  elseif rule == "DOUBLE_SHOCK" then return not self:hasType(att, T_.ELECTRIC)
  elseif rule == "SYNCHRONOISE" then
    if not def then return true end
    for _, t in ipairs({ att.type1, att.type2 or -1, att.__ndxType3 or -1 }) do
      if t >= 0 and self:hasType(def, t) then return false end
    end
    return true
  elseif rule == "GIGATON_HAMMER" then return att.lastMove == mv
  elseif rule == "FLING" then return (tonumber(att.item) or 0) == 0
  elseif rule == "NATURAL_GIFT" then return not (self.A.isBerry and self.A.isBerry(att.item))
  elseif rule == "BELCH" then return not att.ateBerry
  elseif rule == "METAL_BURST" then
    return (tonumber(att.lastPhysicalDamageTaken) or 0) <= 0 and (tonumber(att.lastSpecialDamageTaken) or 0) <= 0
  elseif rule == "SHELL_TRAP" then return (tonumber(att.lastPhysicalDamageTaken) or 0) <= 0
  elseif rule == "STEEL_ROLLER" then return self:terrain() == nil
  end
  return false
end

-- before a hit on def: "fail" | "miss" | "priority" (Psychic Terrain) | nil
function Sim:ruleBefore(ev, att, def, mv)
  local rule = mv.side and mv.side.rule
  if att.__ndxPowder == self.turnNo and mv.type == T_.FIRE then
    ev[#ev + 1] = { kind = "status", who = att, text = ("When the flame touched the powder on %s, it exploded!"):format(att.name) }
    self:selfHurt(ev, att, floor(maxHpOf(att) / 4), nil)
    return "fail"
  end
  if def == att then return nil end
  if self:terrain() == "PSYCHIC" and (mv.priority or 0) > 0 and foes(att, def) and self:grounded(def) then
    ev[#ev + 1] = { kind = "fail", text = ("%s is protected by the Psychic Terrain!"):format(def.name) }
    return "priority"
  end
  if rule == "SPECTRAL_THIEF" then
    local any = false
    for _, k in ipairs({ "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }) do
      local sv = def.stages[k] or 0
      if sv > 0 then
        def.stages[k] = 0
        att.stages[k] = min(6, (att.stages[k] or 0) + sv)
        any = true
      end
    end
    if any then ev[#ev + 1] = { kind = "stage", who = att, text = ("%s stole the target's boosted stats!"):format(att.name) } end
  end
  return nil
end

-- what follows a hit that landed on def (dealt: its damage; up: def still standing)
function Sim:ruleAfter(ev, att, def, mv, dealt)
  local rule = mv.side and mv.side.rule
  if not rule then return end
  local up = alive(def)
  if rule == "CLEAR_SMOG" and up then
    local any = false
    for k, v in pairs(def.stages) do if v ~= 0 then def.stages[k] = 0; any = true end end
    if any then ev[#ev + 1] = { kind = "stage", who = def, text = ("%s's stat changes were removed!"):format(def.name) } end
  elseif rule == "FELL_STINGER" and not up and alive(att) then
    self:stage(ev, att, "attack", 3)
  elseif rule == "FINAL_GAMBIT" and alive(att) then
    att.mon.hp = 0
    ev[#ev + 1] = { kind = "residual", who = att, amount = 0, hp = 0 }
    self:fainted(ev, att)
  elseif rule == "SPARKLING_ARIA" and up and def.status == "BRN" then
    def.status = nil
    ev[#ev + 1] = { kind = "status", who = def, status = nil, text = ("%s's burn was healed!"):format(def.name) }
  elseif rule == "WAKE_UP_SLAP" and up and def.status == "SLP" then
    def.status, def.sleep = nil, nil
    ev[#ev + 1] = { kind = "status", who = def, status = nil, text = ("%s woke up!"):format(def.name) }
  elseif rule == "BURN_UP" or rule == "DOUBLE_SHOCK" then
    local t = rule == "BURN_UP" and T_.FIRE or T_.ELECTRIC
    if att.type2 == t then att.type2 = nil
    elseif att.type1 == t then att.type1, att.type2 = att.type2 or T_.MYSTERY, nil end
    ev[#ev + 1] = { kind = "status", who = att,
      text = rule == "BURN_UP" and ("%s burned itself out!"):format(att.name) or ("%s used up all of its electricity!"):format(att.name) }
  elseif rule == "GLAIVE_RUSH" then
    att.__ndxGlaiveRush = true
  elseif rule == "DIRE_CLAW" and up and self.rng(1, 100) <= 50 then
    self:status(ev, def, ({ "PSN", "PAR", "SLP" })[self.rng(1, 3)], true, att)
  elseif rule == "FLING" or rule == "NATURAL_GIFT" then
    att.item = 0
  elseif (rule == "BUG_BITE" or rule == "PLUCK" or rule == "INCINERATE") and up and self.A.isBerry and self.A.isBerry(def.item) then
    def.item = 0
    ev[#ev + 1] = { kind = "status", who = def,
      text = rule == "INCINERATE" and ("%s's berry was burned up!"):format(def.name) or ("%s stole and ate %s's berry!"):format(att.name, def.name) }
  elseif rule == "CORE_ENFORCER" and up and def.__ndxMovedTurn == self.turnNo and not def.abilitySuppressed then
    def.abilitySuppressed, def.raidAbility = true, nil
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s's ability was suppressed!"):format(def.name) }
  elseif rule == "PLASMA_FISTS" then
    self.A.st.__ndxIonDeluge = self.turnNo
    ev[#ev + 1] = { kind = "field", who = att, text = "A deluge of ions showers the battlefield!" }
  elseif rule == "EERIE_SPELL" and up then
    local last = def.lastMove
    if last and (last.pp or 0) > 0 then
      local before = last.pp
      last.pp = max(0, last.pp - 3)
      ev[#ev + 1] = { kind = "status", who = def, text = ("%s's %s lost %d PP!"):format(def.name, last.name, before - last.pp) }
    end
  elseif rule == "STEEL_ROLLER" or rule == "ICE_SPINNER" then
    self:endTerrain(ev)
  elseif rule == "SALT_CURE" and up and not def.__ndxSaltCure then
    def.__ndxSaltCure = true
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s is being salt cured!"):format(def.name) }
  elseif rule == "THROAT_CHOP" and up then
    def.__ndxThroatChop = 2
  elseif (rule == "SMACK_DOWN" or rule == "THOUSAND_ARROWS") and up and not self:grounded(def) then
    def.__ndxGrounded = true
    if def.semi then def.semi = nil; self:unlock(def, true) end
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s fell straight down!"):format(def.name) }
  elseif rule == "MORTAL_SPIN" then
    local hz = self:sideOf(att).hazards
    hz.stealthRock, hz.spikes, hz.toxicSpikes, hz.stickyWeb = nil, nil, nil, nil
    att.trap, att.seeded = nil, nil
    if up then self:status(ev, def, "PSN", true, att) end
  elseif rule == "CEASELESS_EDGE" then
    local hz = self:sideOf(def).hazards
    if (hz.spikes or 0) < 3 then
      hz.spikes = (hz.spikes or 0) + 1
      ev[#ev + 1] = { kind = "side", side = sideKey(def), what = "spikes", up = true, who = att,
        text = ("Spikes were scattered around %s's feet!"):format(def.boss and def.name or "your team") }
    end
  elseif rule == "STONE_AXE" then
    local hz = self:sideOf(def).hazards
    if not hz.stealthRock then
      hz.stealthRock = true
      ev[#ev + 1] = { kind = "side", side = sideKey(def), what = "stealthRock", up = true, who = att,
        text = ("Pointed stones float in the air around %s!"):format(def.boss and def.name or "your team") }
    end
  end
end

function Sim:endTerrain(ev)
  local f = self.ndx
  if (f.terrainTurns or 0) > 0 then
    ev[#ev + 1] = { kind = "field", who = self.boss, terrain = false, text = TERRAIN_DOWN[f.terrain] }
    f.terrain, f.terrainTurns = nil, nil
  end
end

-- a status move with a rule: false when it failed
function Sim:statusRule(ev, att, def, mv, rule)
  local function fail() ev[#ev + 1] = { kind = "fail", text = "But it failed!" }; return false end
  local own, foe = self:sideOf(att), att.boss and self.sides.team or self.sides.boss
  local foeName = att.boss and "your team" or self.boss.name
  local ownName = att.boss and self.boss.name or "your team"
  local f = self.ndx
  local target = def ~= att and def or nil
  local function fieldTimer(key, turns, upText)
    if (f[key] or 0) > 0 then
      f[key] = nil
      ev[#ev + 1] = { kind = "field", who = att, room = key, up = false, text = Sim.FIELD_END[key] }
    else
      f[key] = turns
      ev[#ev + 1] = { kind = "field", who = att, room = key, up = true, text = upText }
    end
    return true
  end
  local function stats(b, list, n)
    for _, k in ipairs(list) do self:stage(ev, b, k, n, att) end
  end
  local function room(b, list)
    for _, k in ipairs(list) do if (b.stages[k] or 0) < 6 then return true end end
    return false
  end
  -- ---- hazards
  if rule == "STEALTH_ROCK" then
    if foe.hazards.stealthRock then return fail() end
    foe.hazards.stealthRock = true
    ev[#ev + 1] = { kind = "side", side = att.boss and "team" or "boss", what = "stealthRock", up = true, who = att,
      text = ("Pointed stones float in the air around %s!"):format(foeName) }
  elseif rule == "SPIKES" then
    if (foe.hazards.spikes or 0) >= 3 then return fail() end
    foe.hazards.spikes = (foe.hazards.spikes or 0) + 1
    ev[#ev + 1] = { kind = "side", side = att.boss and "team" or "boss", what = "spikes", up = true, who = att,
      text = ("Spikes were scattered around %s's feet!"):format(foeName) }
  elseif rule == "TOXIC_SPIKES" then
    if (foe.hazards.toxicSpikes or 0) >= 2 then return fail() end
    foe.hazards.toxicSpikes = (foe.hazards.toxicSpikes or 0) + 1
    ev[#ev + 1] = { kind = "side", side = att.boss and "team" or "boss", what = "toxicSpikes", up = true, who = att,
      text = ("Poison spikes were scattered around %s's feet!"):format(foeName) }
  elseif rule == "STICKY_WEB" then
    if foe.hazards.stickyWeb then return fail() end
    foe.hazards.stickyWeb = true
    ev[#ev + 1] = { kind = "side", side = att.boss and "team" or "boss", what = "stickyWeb", up = true, who = att,
      text = ("A sticky web spreads out under %s's feet!"):format(foeName) }
  elseif rule == "DEFOG" then
    for _, sd in ipairs({ own, foe }) do
      local hz = sd.hazards
      hz.stealthRock, hz.spikes, hz.toxicSpikes, hz.stickyWeb = nil, nil, nil, nil
    end
    self:blowAway(ev, att.boss and "team" or "boss", att)
    self:endTerrain(ev)
    if target then self:stage(ev, target, "evasion", -1, att) end
  elseif rule == "COURT_CHANGE" then
    local a, b = self.sides.team, self.sides.boss
    for _, k in ipairs({ "reflect", "light", "veil", "safeguard", "mist", "tailwind", "luckyChant", "hazards" }) do
      a[k], b[k] = b[k], a[k]
    end
    self:syncVeil()
    ev[#ev + 1] = { kind = "field", who = att, text = ("%s swapped the battle effects affecting each side!"):format(att.name) }
  elseif rule == "LUCKY_CHANT" then
    if (own.luckyChant or 0) > 0 then return fail() end
    own.luckyChant = 5
    ev[#ev + 1] = { kind = "side", side = sideKey(att), what = "luckyChant", up = true, who = att,
      text = ("The Lucky Chant shielded %s from critical hits!"):format(ownName) }
  -- ---- the field
  elseif rule == "TRICK_ROOM" then
    return fieldTimer("trickRoom", 5, ("%s twisted the dimensions!"):format(att.name))
  elseif rule == "WONDER_ROOM" then
    return fieldTimer("wonderRoom", 5, "It created a bizarre area in which Defense and Sp. Def stats are swapped!")
  elseif rule == "MAGIC_ROOM" then
    return fieldTimer("magicRoom", 5, "It created a bizarre area in which Pok\195\169mon's held items lose their effects!")
  elseif rule == "GRAVITY" then
    if not self:setGravity(ev, att, 5) then return fail() end
    for _, b in ipairs(self:team()) do
      if b.semi then
        b.semi = nil
        self:unlock(b, true)
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s fell from the sky due to the gravity!"):format(b.name) }
      end
    end
  elseif rule == "FAIRY_LOCK" then
    ev[#ev + 1] = { kind = "field", who = att, text = "No one will be able to run away during the next turn!" }
  elseif Sim.TERRAIN[rule] then
    local t = Sim.TERRAIN[rule]
    if self:terrain() == t.kind then return fail() end
    f.terrain, f.terrainTurns = t.kind, 5
    ev[#ev + 1] = { kind = "field", who = att, terrain = t.kind, text = t.up }
  elseif rule == "ION_DELUGE" then
    self.A.st.__ndxIonDeluge = self.turnNo
    ev[#ev + 1] = { kind = "field", who = att, text = "A deluge of ions showers the battlefield!" }
  elseif rule == "ROTOTILLER" or rule == "FLOWER_SHIELD" then
    local any = false
    local all = { self.boss }
    for _, m in ipairs(self:team()) do all[#all + 1] = m end
    for _, b in ipairs(all) do
      if self:hasType(b, T_.GRASS) and (rule == "FLOWER_SHIELD" or self:grounded(b)) then
        any = true
        stats(b, rule == "ROTOTILLER" and { "attack", "spAtk" } or { "defense" }, 1)
      end
    end
    if not any then return fail() end
  -- ---- the user
  elseif rule == "AQUA_RING" then
    if att.__ndxAquaRing then return fail() end
    att.__ndxAquaRing = true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s surrounded itself with a veil of water!"):format(att.name) }
  elseif rule == "MAGNET_RISE" then
    if (att.__ndxMagnetRise or 0) > 0 or att.ingrained or (self.gravity or 0) > 0 then return fail() end
    att.__ndxMagnetRise = 5
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s levitated with electromagnetism!"):format(att.name) }
  elseif rule == "GEOMANCY" then
    if lockOf(att, "charge") and att.lock.mv == mv then
      self:unlock(att)
      stats(att, { "spAtk", "spDef", "speed" }, 2)
    else
      att.lock = { kind = "charge", mv = mv, release = true }
      ev[#ev + 1] = { kind = "status", who = att, text = ("%s is absorbing power!"):format(att.name) }
    end
  elseif rule == "LASER_FOCUS" then
    att.__ndxLaserFocus = self.turnNo
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s concentrated intensely!"):format(att.name) }
  elseif rule == "TAKE_HEART" then
    if att.status then
      att.status, att.sleep, att.tox = nil, nil, nil
      ev[#ev + 1] = { kind = "status", who = att, status = nil, text = ("%s's status returned to normal!"):format(att.name) }
    end
  elseif rule == "POWER_TRICK" then
    local a, d = statOf(att, "attack"), statOf(att, "defense")
    att.__ndxStat = att.__ndxStat or {}
    att.__ndxStat.attack, att.__ndxStat.defense = d, a
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s switched its Attack and Defense!"):format(att.name) }
  elseif rule == "CLANGOROUS_SOUL" or rule == "FILLET_AWAY" then
    local cost = rule == "CLANGOROUS_SOUL" and floor(maxHpOf(att) / 3) or floor(maxHpOf(att) / 2)
    local list = rule == "CLANGOROUS_SOUL" and { "attack", "defense", "spAtk", "spDef", "speed" } or { "attack", "spAtk", "speed" }
    if hpOf(att) <= cost or not room(att, list) then return fail() end
    self:selfHurt(ev, att, cost, nil)
    stats(att, list, rule == "CLANGOROUS_SOUL" and 1 or 2)
  elseif rule == "NO_RETREAT" then
    local list = { "attack", "defense", "spAtk", "spDef", "speed" }
    if att.__ndxNoRetreat or not room(att, list) then return fail() end
    att.__ndxNoRetreat = true
    stats(att, list, 1)
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s can no longer escape because it used No Retreat!"):format(att.name) }
  elseif rule == "STUFF_CHEEKS" then
    if not (self.A.isBerry and self.A.isBerry(att.item)) or (att.stages.defense or 0) >= 6 then return fail() end
    att.item, att.ateBerry = 0, true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s ate its berry!"):format(att.name) }
    self:stage(ev, att, "defense", 2)
  elseif rule == "ACUPRESSURE" then
    local open = {}
    for _, k in ipairs({ "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }) do
      if (att.stages[k] or 0) < 6 then open[#open + 1] = k end
    end
    if #open == 0 then return fail() end
    self:stage(ev, att, open[self.rng(1, #open)], 2)
  elseif rule == "REVIVAL_BLESSING" then
    -- (a member sitting out after a knock-out is back at once, at half its HP)
    local who
    for _, m in ipairs(self.members) do if (m.down or 0) > 0 and m ~= att then who = m; break end end
    if not who then return fail() end
    who.down, who.outSince = 0, self.turnNo + 1
    who.mon.hp = max(1, floor(maxHpOf(who) / 2))
    for k in pairs(who.stages) do who.stages[k] = 0 end
    ev[#ev + 1] = { kind = "back", who = who, hp = who.mon.hp, text = ("%s was revived and is ready to fight again!"):format(who.name) }
    self:entry(ev, who)
  elseif rule == "SHED_TAIL" or rule == "CHILLY_RECEPTION" then
    -- (they leave the field for another: no one to come in during a raid)
    return fail()
  -- ---- the target
  elseif not target then
    return fail()
  elseif rule == "PARTING_SHOT" then
    -- (it would leave the field after: no one to come in during a raid, so it fails as the
    -- National Dex's does without a Pokemon to switch to)
    return fail()
  elseif rule == "WORRY_SEED" or rule == "ENTRAINMENT" or rule == "SIMPLE_BEAM" or rule == "GASTRO_ACID" then
    if rule == "GASTRO_ACID" then
      if target.abilitySuppressed then return fail() end
      target.abilitySuppressed, target.raidAbility = true, nil
      ev[#ev + 1] = { kind = "status", who = target, text = ("%s's ability was suppressed!"):format(target.name) }
    else
      local name = rule == "WORRY_SEED" and "INSOMNIA" or rule == "SIMPLE_BEAM" and "SIMPLE"
        or (self.A.abilityName and self.A.abilityName(att))
      if not name or target.raidAbility == name then return fail() end
      target.raidAbility = name
      if name == "INSOMNIA" and target.status == "SLP" then target.status, target.sleep = nil, nil end
      ev[#ev + 1] = { kind = "status", who = target,
        text = ("%s acquired %s!"):format(target.name, (name:lower():gsub("_", " "):gsub("^%l", string.upper))) }
    end
  elseif rule == "DOODLE" then
    local name = target.raidAbility or (self.A.abilityName and self.A.abilityName(target))
    if not name or name == "WONDER_GUARD" then return fail() end
    for _, b in ipairs(self:onSide(sideKey(att))) do b.raidAbility = name end
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s acquired %s!"):format(att.name, name) }
  elseif rule == "SOAK" or rule == "MAGIC_POWDER" then
    local t = rule == "SOAK" and T_.WATER or T_.PSYCHIC
    if target.type1 == t and target.type2 == nil then return fail() end
    target.type1, target.type2, target.__ndxType3 = t, nil, nil
    ev[#ev + 1] = { kind = "status", who = target,
      text = ("%s transformed into the %s type!"):format(target.name, t == T_.WATER and "Water" or "Psychic") }
  elseif rule == "REFLECT_TYPE" then
    if target.type1 == T_.MYSTERY and target.type2 == nil then return fail() end
    att.type1, att.type2, att.__ndxType3 = target.type1, target.type2, target.__ndxType3
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s's type became the same as %s's!"):format(att.name, target.name) }
  elseif rule == "TRICK_OR_TREAT" or rule == "FORESTS_CURSE" then
    local t = rule == "TRICK_OR_TREAT" and T_.GHOST or T_.GRASS
    if self:hasType(target, t) then return fail() end
    target.__ndxType3 = t
    ev[#ev + 1] = { kind = "status", who = target,
      text = ("%s type was added to %s!"):format(t == T_.GHOST and "Ghost" or "Grass", target.name) }
  elseif rule == "TAR_SHOT" then
    if target.__ndxTarShot then return fail() end
    target.__ndxTarShot = true
    self:stage(ev, target, "speed", -1, att)
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s became weaker to fire!"):format(target.name) }
  elseif rule == "ELECTRIFY" then
    if target.__ndxMovedTurn == self.turnNo then return fail() end
    target.__ndxElectrified = self.turnNo
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s's moves have been electrified!"):format(target.name) }
  elseif rule == "POWER_SPLIT" or rule == "GUARD_SPLIT" then
    local keys = rule == "POWER_SPLIT" and { "attack", "spAtk" } or { "defense", "spDef" }
    att.__ndxStat, target.__ndxStat = att.__ndxStat or {}, target.__ndxStat or {}
    for _, k in ipairs(keys) do
      local avg = floor((statOf(att, k) + statOf(target, k)) / 2)
      att.__ndxStat[k], target.__ndxStat[k] = avg, avg
    end
    ev[#ev + 1] = { kind = "status", who = att,
      text = ("%s shared its %s with the target!"):format(att.name, rule == "POWER_SPLIT" and "power" or "guard") }
  elseif rule == "POWER_SWAP" or rule == "GUARD_SWAP" or rule == "HEART_SWAP" then
    local keys = rule == "POWER_SWAP" and { "attack", "spAtk" } or rule == "GUARD_SWAP" and { "defense", "spDef" }
      or { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
    for _, k in ipairs(keys) do att.stages[k], target.stages[k] = target.stages[k] or 0, att.stages[k] or 0 end
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s switched stat changes with the target!"):format(att.name) }
  elseif rule == "SPEED_SWAP" then
    local a, b = statOf(att, "speed"), statOf(target, "speed")
    att.__ndxStat, target.__ndxStat = att.__ndxStat or {}, target.__ndxStat or {}
    att.__ndxStat.speed, target.__ndxStat.speed = b, a
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s switched Speed with the target!"):format(att.name) }
  elseif rule == "TOPSY_TURVY" then
    local any = false
    for k, v in pairs(target.stages) do if v ~= 0 then target.stages[k] = -v; any = true end end
    if not any then return fail() end
    ev[#ev + 1] = { kind = "stage", who = target, text = ("%s's stat changes were all reversed!"):format(target.name) }
  elseif rule == "STRENGTH_SAP" then
    if (target.stages.attack or 0) <= -6 then return fail() end
    local amount = statOf(target, "attack")
    if self.A.applyStage then amount = self.A.applyStage(amount, target.stages.attack or 0) end
    self:stage(ev, target, "attack", -1, att)
    self:healFor(ev, att, amount)
  elseif rule == "VENOM_DRENCH" then
    if not (target.status == "PSN" or target.status == "TOX") then return fail() end
    stats(target, { "attack", "spAtk", "speed" }, -1)
  elseif rule == "CAPTIVATE" then
    local g1, g2 = att.gender, target.gender
    if not ((g1 == "M" and g2 == "F") or (g1 == "F" and g2 == "M")) then return fail() end
    self:stage(ev, target, "spAtk", -2, att)
  elseif rule == "POWDER" then
    target.__ndxPowder = self.turnNo
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s is covered in powder!"):format(target.name) }
  elseif rule == "PSYCHO_SHIFT" then
    local st = att.status
    if not st or target.status then return fail() end
    if not self:status(ev, target, st, true, att) then return fail() end
    att.status, att.sleep, att.tox = nil, nil, nil
    ev[#ev + 1] = { kind = "status", who = att, status = nil, text = ("%s transferred its status to %s!"):format(att.name, target.name) }
  elseif rule == "MIRACLE_EYE" then
    if target.__ndxMiracleEye then return fail() end
    target.__ndxMiracleEye = true
    target.stages.evasion = min(0, target.stages.evasion or 0)
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s was identified!"):format(target.name) }
  elseif rule == "PURIFY" then
    if not target.status then return fail() end
    target.status, target.sleep, target.tox = nil, nil, nil
    ev[#ev + 1] = { kind = "status", who = target, status = nil, text = ("%s's status returned to normal!"):format(target.name) }
    self:healFor(ev, att, maxHpOf(att) / 2)
  elseif rule == "OCTOLOCK" then
    if target.__ndxOctolock then return fail() end
    target.__ndxOctolock = att
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s can no longer escape!"):format(target.name) }
  elseif rule == "HEAL_BLOCK" then
    if (target.__ndxHealBlock or 0) > 0 then return fail() end
    target.__ndxHealBlock = 5
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s was prevented from healing!"):format(target.name) }
  else
    return nil
  end
  return true
end

-- the end of the turn's share of the rules: the field's and sides' timers, each battler's marks
function Sim:ruleEndTurn(ev, all)
  local f = self.ndx
  for _, x in ipairs(all) do
    if not self.over and alive(x) then
      if x.__ndxAquaRing then self:healFor(ev, x, maxHpOf(x) / 16, ("A veil of water restored %s's HP!"):format(x.name)) end
      if self:terrain() == "GRASSY" and self:grounded(x) then
        self:healFor(ev, x, maxHpOf(x) / 16, ("%s is healed by the grassy terrain!"):format(x.name))
      end
      if x.__ndxSaltCure then
        local div = (self:hasType(x, T_.WATER) or self:hasType(x, T_.STEEL)) and 4 or 8
        self:selfHurt(ev, x, floor(maxHpOf(x) / div), ("%s is being hurt by Salt Cure!"):format(x.name))
      end
      local octo = x.__ndxOctolock
      if octo and alive(x) then
        if not alive(octo) or (octo.down or 0) > 0 then x.__ndxOctolock = nil
        else
          self:stage(ev, x, "defense", -1, octo)
          self:stage(ev, x, "spDef", -1, octo)
        end
      end
      for _, key in ipairs({ "__ndxMagnetRise", "__ndxHealBlock", "__ndxThroatChop" }) do
        if (x[key] or 0) > 0 then
          x[key] = x[key] - 1
          if x[key] <= 0 then
            x[key] = nil
            if key == "__ndxMagnetRise" then
              ev[#ev + 1] = { kind = "status", who = x, text = ("%s's electromagnetism wore off!"):format(x.name) }
            elseif key == "__ndxHealBlock" then
              ev[#ev + 1] = { kind = "status", who = x, text = ("%s's Heal Block wore off!"):format(x.name) }
            end
          end
        end
      end
    end
  end
  if self.over then return end
  for _, key in ipairs({ "trickRoom", "wonderRoom", "magicRoom" }) do
    if (f[key] or 0) > 0 then
      f[key] = f[key] - 1
      if f[key] <= 0 then
        f[key] = nil
        ev[#ev + 1] = { kind = "field", who = self.boss, room = key, up = false, text = Sim.FIELD_END[key] }
      end
    end
  end
  if (f.terrainTurns or 0) > 0 then
    f.terrainTurns = f.terrainTurns - 1
    if f.terrainTurns <= 0 then
      f.terrainTurns = 1
      self:endTerrain(ev)
    end
  end
end

-- the bookkeeping the National Dex's rules read, as its battle events keep it: who moved this turn
-- and with what (Payback, Bolt Beak, Last Resort, Gigaton Hammer, the Fusion moves, Echoed Voice)
function Sim:noteMoved(att, mv)
  local st = self.A.st
  att.__ndxMovedTurn = self.turnNo
  att.__ndxGlaiveRush = nil
  att.__ndxUsedMoves = att.__ndxUsedMoves or {}
  att.__ndxUsedMoves[mv.base or mv] = true
  local rule = mv.side and mv.side.rule
  if not st then return end
  -- (the other Fusion move after this one in the same turn doubles)
  if rule == "FUSION_FLARE" or rule == "FUSION_BOLT" then st.__ndxFusion = { turn = self.turnNo, rule = rule } end
end

-- before the move's damage: Echoed Voice's count, one more for each turn in a row it is used
function Sim:noteEcho(mv)
  local st = self.A.st
  if not (st and mv.side and mv.side.rule == "ECHOED_VOICE") then return end
  local e = st.__ndxEcho
  if e and e.turn == self.turnNo then return end
  if e and e.turn == self.turnNo - 1 then e.turn, e.count = self.turnNo, min(5, e.count + 1)
  else st.__ndxEcho = { turn = self.turnNo, count = 1 } end
end

-- a hit's damage noted (Assurance, Metal Burst, Shell Trap, Rage Fist)
function Sim:noteHurt(def, att, mv, dmg)
  if dmg <= 0 then return end
  def.damageTakenThisTurn = (def.damageTakenThisTurn or 0) + dmg
  local phys = self.A.isPhysical and self.A.isPhysical(mv.type)
  if phys then def.lastPhysicalDamageTaken = dmg else def.lastSpecialDamageTaken = dmg end
  local st = self.A.st
  if st then
    st.__ndxHits = st.__ndxHits or setmetatable({}, { __mode = "k" })
    st.__ndxHits[def.mon] = (st.__ndxHits[def.mon] or 0) + 1
  end
end

-- a faint noted (Retaliate, Last Respects)
function Sim:noteFainted(b)
  local st = self.A.st
  if not st then return end
  local side = ndxSide(b)
  st.__ndxFainted = st.__ndxFainted or {}
  st.__ndxFainted[side] = self.turnNo
  st.__ndxFaintCount = st.__ndxFaintCount or {}
  st.__ndxFaintCount[side] = (st.__ndxFaintCount[side] or 0) + 1
end

-- ------- the rest of Gen 3's moves (the engine's own battle: effects/*.lua, engine.lua call_moves)
--
-- A move's side `g3` names its effect; the numbers are the engine's (Gen 3's), Dynamax's own rules
-- on top (a Dynamax Pokemon - the boss - shrugs off Perish Song, Destiny Bond, Encore, Disable).

-- moves no caller may pick (the engine's FORBIDDEN_TO_COPY: Metronome, Struggle, Sketch, Mimic,
-- Counter, Mirror Coat, Protect, Detect, Endure, Destiny Bond, Sleep Talk, Thief, Follow Me, Snatch,
-- Helping Hand, Covet, Trick, Focus Punch)
Sim.NO_CALL = {}
for _, k in ipairs({ "metronome", "struggle", "sketch", "mimic", "counter", "mirrorcoat", "protect", "detect", "endure",
  "destinybond", "sleeptalk", "thief", "followme", "snatch", "helpinghand", "covet", "trick", "focuspunch",
  "assist", "mirrormove", "copycat", "naturepower" }) do Sim.NO_CALL[k] = true end
-- Sleep Talk never picks these (nor a move with a charging turn)
Sim.NO_SLEEP_TALK = { sleeptalk = true, focuspunch = true, uproar = true, bide = true, assist = true, mirrormove = true,
  metronome = true, copycat = true }
-- Nature Power by the terrain (no terrain: Tri Attack, as in a building in Sword / Shield)
Sim.NATURE_POWER = { ELECTRIC = "THUNDERBOLT", GRASSY = "ENERGY_BALL", MISTY = "MOONBLAST", PSYCHIC = "PSYCHIC" }
Sim.CAMOUFLAGE = { ELECTRIC = T_.ELECTRIC, GRASSY = T_.GRASS, MISTY = T_.FAIRY, PSYCHIC = T_.PSYCHIC }

local function g3Of(mv) return mv.side and mv.side.g3 end

-- where a charging move takes its user (Fly and Bounce up, Dig under, Dive in the water, Phantom
-- Force away), what still reaches it there, and what hits it twice as hard
Sim.SEMI_KIND = { fly = "air", bounce = "air", dig = "ground", dive = "water", phantomforce = "vanish",
  shadowforce = "vanish" }
Sim.REACH = {
  air = { gust = 2, twister = 2, thunder = 1, skyuppercut = 1, smackdown = 1, thousandarrows = 1, hurricane = 1 },
  ground = { earthquake = 2, magnitude = 2, fissure = 1 },
  water = { surf = 2, whirlpool = 2 },
}

-- why a battler cannot pick a move now (Torment, Disable, Taunt, Imprison): the word, or nil
function Sim:barredWhy(b, mv)
  if self:tormented(b, mv) then return "Torment" end
  if self:choiceLocked(b, mv) then return self:itemName(b.item) end
  local pm = mv.base or mv
  if b.disabled and b.disabled.mv == pm then return "Disable" end
  if (b.taunt or 0) > 0 and pm.status then return "Taunt" end
  local key = squash(pm.key)
  if key ~= "" then
    for _, x in ipairs(self:everyone()) do
      if x.imprison and foes(x, b) and alive(x) then
        for _, m in ipairs(x.moves or {}) do if squash(m.key) == key then return "Imprison" end end
      end
    end
  end
  return nil
end

-- a copy of a move for another battler's slot (Mimic, Sketch, Transform): `pp` PP
local function moveCopy(mv, pp)
  local c = {}
  for k, v in pairs(mv.base or mv) do c[k] = v end
  c.pp, c.maxPp = pp or c.maxPp, pp or c.maxPp
  return c
end
function Sim:putMove(b, slot, mv)
  b.moves[slot] = mv
  if b.maxMoves and self.A.maxOf then b.maxMoves[slot] = self.A.maxOf(mv, b.gmaxId) end
end

-- an item gone (Knock Off, Fling, a berry eaten): kept for Recycle
local function loseItem(b)
  local it = tonumber(b.item) or 0
  if it ~= 0 then b.consumed = it end
  b.item = 0
end

-- the move a caller calls (Metronome, Assist, Sleep Talk, Nature Power, Mirror Move, Copycat):
-- the move, or nil (it fails)
function Sim:calledMove(att, mv, def)
  local g = g3Of(mv)
  local pick = function(list)
    if #list == 0 then return nil end
    return list[self.rng(1, #list)]
  end
  if g == "METRONOME" then
    return self.A.randomMove and self.A.randomMove(Sim.NO_CALL, self.rng)
  elseif g == "ASSIST" then
    local list = {}
    for _, m in ipairs(self.members) do
      if m ~= att then
        for _, x in ipairs(m.moves or {}) do if not Sim.NO_CALL[squash(x.key)] then list[#list + 1] = x end end
      end
    end
    return pick(list)
  elseif g == "SLEEP_TALK" then
    local list = {}
    for _, x in ipairs(att.moves or {}) do
      if x ~= mv and not Sim.NO_SLEEP_TALK[squash(x.key)] and not (x.side and x.side.charge) then list[#list + 1] = x end
    end
    return pick(list)
  elseif g == "NATURE_POWER" then
    local name = Sim.NATURE_POWER[self:terrain() or ""] or "TRI_ATTACK"
    return self.A.moveByKey and self.A.moveByKey(name)
  elseif g == "MIRROR_MOVE" then
    -- (Mirror Move: the target's last move; Copycat: the last move anyone used)
    local last = squash(mv.key) == "copycat" and self.lastUsed or (def and def.lastMove)
    if not last or Sim.NO_CALL[squash(last.key)] or last.isMax or last.isGmax then return nil end
    return last
  end
  return nil
end

-- before a Gen 3 move is used: true (with its words) when it fails
function Sim:g3Fails(ev, att, mv, targets)
  local g = g3Of(mv)
  if not g then return false end
  local def = targets[1]
  local function no(text) ev[#ev + 1] = { kind = "fail", text = text or "But it failed!" }; return true end
  if g == "FOCUS_PUNCH" and (att.damageTakenThisTurn or 0) > 0 then
    return no(("%s lost its focus and couldn't move!"):format(att.name))
  elseif (g == "SNORE" or g == "SLEEP_TALK") and att.status ~= "SLP" then return no()
  elseif g == "SPIT_UP" and (att.stockpile or 0) <= 0 then return no(("But it failed to spit up a thing!"):format())
  elseif g == "SWALLOW" and (att.stockpile or 0) <= 0 then return no(("But it failed to swallow a thing!"):format())
  elseif (g == "BATON_PASS" or g == "TELEPORT" or g == "ROAR") then return no()
  elseif g == "PERISH_SONG" then
    local any = false
    for _, b in ipairs(self:everyone()) do if alive(b) and not isDmax(b) and not b.perish and (b.down or 0) == 0 then any = true end end
    if not any then return no() end
  elseif (g == "DISABLE" or g == "ENCORE" or g == "SPITE" or g == "MIMIC" or g == "SKETCH") then
    if not (def and def.lastMove) then return no() end
  end
  return false
end

-- the power a Gen 3 move hits with this time (Rollout, Fury Cutter, Present, Spit Up): a number,
-- "heal" (Present healing the target), or nil (its own)
function Sim:g3Power(att, def, mv)
  local g = g3Of(mv)
  if g == "ROLLOUT" then
    local n = lockOf(att, "rollout") and att.lock.rollout or 1
    local p = (tonumber(mv.power) or 30) * 2 ^ (n - 1)
    if att.curled then p = p * 2 end
    return p
  elseif g == "FURY_CUTTER" then
    local n = att.furyCutter or 0
    return min(160, (tonumber(mv.power) or 10) * 2 ^ n)
  elseif g == "PRESENT" then
    local r = self.rng(1, 100)
    if r <= 40 then return 40 elseif r <= 70 then return 80 elseif r <= 80 then return 120 end
    return "heal"
  elseif g == "SPIT_UP" then
    return 100 * (att.stockpile or 1)
  end
  return nil
end

-- what follows a Gen 3 move's hit (landed: it struck, dealt its damage)
function Sim:g3After(ev, att, def, mv, landed)
  local g = g3Of(mv)
  if not g then return end
  local up = alive(def)
  if g == "ROLLOUT" then
    local L = lockOf(att, "rollout")
    if not landed then
      if L then self:unlock(att) end
    elseif not att.lock then att.lock = { kind = "rollout", mv = mv, rollout = 2 }
    elseif L then
      L.rollout = L.rollout + 1
      if L.rollout > 5 then self:unlock(att) end
    end
  elseif g == "FURY_CUTTER" then
    att.furyCutter = landed and min(4, (att.furyCutter or 0) + 1) or 0
  elseif g == "SPIT_UP" then
    att.stockpile = 0
  elseif g == "RAGE" then
    att.raging = landed or nil
  elseif g == "UPROAR" then
    local L = lockOf(att, "uproar")
    if not att.lock then
      att.lock = { kind = "uproar", mv = mv, turns = self.rng(1, 4), uproar = true }
      self.uproar = att
      ev[#ev + 1] = { kind = "field", who = att, text = ("%s caused an uproar!"):format(att.name) }
      for _, b in ipairs(self:everyone()) do
        if b.status == "SLP" and alive(b) then
          b.status, b.sleep = nil, nil
          ev[#ev + 1] = { kind = "status", who = b, status = nil, text = ("The uproar woke %s!"):format(b.name) }
        end
      end
    elseif L then
      L.turns = L.turns - 1
      if L.turns <= 0 then
        self:unlock(att)
        ev[#ev + 1] = { kind = "field", who = att, text = ("%s calmed down."):format(att.name) }
      end
    end
  elseif not landed then
    return
  elseif g == "KNOCK_OFF" and up and (tonumber(def.item) or 0) ~= 0 then
    loseItem(def)
    ev[#ev + 1] = { kind = "status", who = def, text = ("%s knocked off %s's item!"):format(att.name, def.name) }
  elseif g == "THIEF" and up and (tonumber(def.item) or 0) ~= 0 and (tonumber(att.item) or 0) == 0 then
    att.item, def.item = def.item, 0
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s stole %s's item!"):format(att.name, def.name) }
  elseif g == "RAPID_SPIN" and alive(att) then
    local hz = self:sideOf(att).hazards
    hz.spikes, hz.stealthRock, hz.toxicSpikes, hz.stickyWeb = nil, nil, nil, nil
    att.trap, att.seeded = nil, nil
  elseif g == "SMELLINGSALT" and up and def.status == "PAR" then
    def.status = nil
    ev[#ev + 1] = { kind = "status", who = def, status = nil, text = ("%s was cured of paralysis."):format(def.name) }
  elseif g == "PAY_DAY" and not att.boss then
    self.money = (self.money or 0) + (tonumber(att.mon.level) or 1) * 5
    ev[#ev + 1] = { kind = "status", who = att, coins = true, text = "Coins scattered everywhere!" }
  end
end

-- a Gen 3 status move: false when it failed
function Sim:g3Status(ev, att, def, mv, g)
  local function fail() ev[#ev + 1] = { kind = "fail", text = "But it failed!" }; return false end
  local target = def ~= att and def or nil
  if g == "STOCKPILE" then
    if (att.stockpile or 0) >= 3 then
      ev[#ev + 1] = { kind = "fail", text = ("%s can't stockpile any more!"):format(att.name) }
      return false
    end
    att.stockpile = (att.stockpile or 0) + 1
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s stockpiled %d!"):format(att.name, att.stockpile) }
  elseif g == "SWALLOW" then
    local n = att.stockpile or 0
    att.stockpile = 0
    if not self:healFor(ev, att, maxHpOf(att) * ({ 0.25, 0.5, 1 })[min(3, n)]) then return fail() end
  elseif g == "CHARGE" then
    att.expCharged = 2
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s began charging power!"):format(att.name) }
  elseif g == "CONVERSION" then
    local list = {}
    for _, m in ipairs(att.moves or {}) do
      local t = m.type
      if t and t ~= T_.MYSTERY and not self:hasType(att, t) and squash(m.key) ~= "curse" then list[#list + 1] = t end
    end
    if #list == 0 then return fail() end
    local t = list[self.rng(1, #list)]
    att.type1, att.type2, att.__ndxType3 = t, nil, nil
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s transformed into the %s type!"):format(att.name, Sim.TYPE_NAME[t] or "?") }
  elseif g == "CONVERSION_2" then
    local hitBy = att.lastHitType
    if not hitBy then return fail() end
    local list = {}
    for t = 0, 18 do
      if t ~= T_.MYSTERY and not self:hasType(att, t) then
        local e = self.A.effectiveness and self.A.effectiveness(hitBy, { type1 = t }) or 1
        if e < 1 then list[#list + 1] = t end
      end
    end
    if #list == 0 then return fail() end
    local t = list[self.rng(1, #list)]
    att.type1, att.type2, att.__ndxType3 = t, nil, nil
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s transformed into the %s type!"):format(att.name, Sim.TYPE_NAME[t] or "?") }
  elseif g == "CAMOUFLAGE" then
    local t = Sim.CAMOUFLAGE[self:terrain() or ""] or T_.NORMAL
    if att.type1 == t and att.type2 == nil then return fail() end
    att.type1, att.type2, att.__ndxType3 = t, nil, nil
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s transformed into the %s type!"):format(att.name, Sim.TYPE_NAME[t] or "?") }
  elseif g == "DESTINY_BOND" then
    att.destinyBond = true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s is trying to take its foe down with it!"):format(att.name) }
  elseif g == "GRUDGE" then
    att.grudge = true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s wants its target to bear a grudge!"):format(att.name) }
  elseif g == "IMPRISON" then
    if att.imprison then return fail() end
    att.imprison = true
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s sealed any moves its target shares with it!"):format(att.name) }
  elseif g == "MAGIC_COAT" then
    att.magicCoat = self.turnNo
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s shrouded itself with Magic Coat!"):format(att.name) }
  elseif g == "SNATCH" then
    att.snatch = self.turnNo
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s waits for a target to make a move!"):format(att.name) }
  elseif g == "MUD_SPORT" or g == "WATER_SPORT" then
    local key = g == "MUD_SPORT" and "mudSport" or "waterSport"
    if (self.ndx[key] or 0) > 0 then return fail() end
    self.ndx[key] = 5
    ev[#ev + 1] = { kind = "field", who = att,
      text = g == "MUD_SPORT" and "Electricity's power was weakened!" or "Fire's power was weakened!" }
  elseif g == "SUBSTITUTE" then
    local cost = floor(maxHpOf(att) / 4)
    if (att.substituteHP or 0) > 0 then
      ev[#ev + 1] = { kind = "fail", text = ("%s already has a substitute!"):format(att.name) }
      return false
    end
    if hpOf(att) <= cost then
      ev[#ev + 1] = { kind = "fail", text = "But it does not have enough HP left to make a substitute!" }
      return false
    end
    self:selfHurt(ev, att, cost, nil)
    att.substituteHP = cost
    ev[#ev + 1] = { kind = "status", who = att, substitute = true, text = ("%s put in a substitute!"):format(att.name) }
  elseif g == "PERISH_SONG" then
    ev[#ev + 1] = { kind = "field", who = att, text = "All Pok\195\169mon that heard the song will faint in three turns!" }
    for _, b in ipairs(self:everyone()) do
      if alive(b) and not isDmax(b) and not b.perish and (b.down or 0) == 0 then b.perish = 4 end
    end
  elseif g == "RECYCLE" then
    if not att.consumed or (tonumber(att.item) or 0) ~= 0 then return fail() end
    att.item, att.consumed = att.consumed, nil
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s found its item!"):format(att.name) }
  elseif g == "BIDE" then
    local L = lockOf(att, "bide")
    if L then
      L.turns = L.turns - 1
      if L.turns > 0 then
        ev[#ev + 1] = { kind = "status", who = att, text = ("%s is storing energy!"):format(att.name) }
      else
        local stored, from = L.stored or 0, L.from or self.boss
        self:unlock(att)
        ev[#ev + 1] = { kind = "status", who = att, text = ("%s unleashed its energy!"):format(att.name) }
        if stored <= 0 or not alive(from) then return fail() end
        local dmg = self:capAtShield(from, min(hpOf(from), self:throughBoss(ev, from, stored * 2)))
        from.mon.hp = hpOf(from) - dmg
        ev[#ev + 1] = { kind = "damage", who = att, target = from, amount = dmg, hp = from.mon.hp, move = mv }
        if not alive(from) then self:fainted(ev, from) elseif from.boss then self:checkShield(ev) end
      end
    else
      att.lock = { kind = "bide", mv = mv, bide = true, turns = 2, stored = 0 }
      ev[#ev + 1] = { kind = "status", who = att, text = ("%s is storing energy!"):format(att.name) }
    end
  -- ---- on the target
  elseif not target then
    return fail()
  elseif g == "DISABLE" then
    if isDmax(target) or target.disabled then return fail() end
    target.disabled = { mv = target.lastMove, turns = self.rng(2, 5) }
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s's %s was disabled!"):format(target.name, target.lastMove.name) }
  elseif g == "ENCORE" then
    if isDmax(target) or target.boss or target.lock or (target.lastMove.pp or 0) <= 0 then return fail() end
    target.lock = { kind = "encore", mv = target.lastMove, encore = true, turns = self.rng(2, 6) }
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s received an encore!"):format(target.name) }
  elseif g == "TAUNT" then
    if (target.taunt or 0) > 0 then return fail() end
    target.taunt = 2
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s fell for the taunt!"):format(target.name) }
  elseif g == "TORMENT" then
    if not self:torment(ev, target) then return fail() end
  elseif g == "SPITE" then
    local last = target.lastMove
    if (last.pp or 0) <= 0 then return fail() end
    local cut = min(last.pp, self.rng(2, 5))
    last.pp = last.pp - cut
    ev[#ev + 1] = { kind = "status", who = target, text = ("It reduced the PP of %s's %s by %d!"):format(target.name, last.name, cut) }
  elseif g == "MIMIC" or g == "SKETCH" then
    local last = target.lastMove
    if last.isMax or last.isGmax or Sim.NO_CALL[squash(last.key)] and squash(last.key) ~= "metronome" then return fail() end
    for _, m in ipairs(att.moves) do if squash(m.key) == squash(last.key) then return fail() end end
    local slot
    for i, m in ipairs(att.moves) do if m == (mv.base or mv) then slot = i end end
    if not slot then return fail() end
    self:putMove(att, slot, moveCopy(last, g == "MIMIC" and 5 or nil))
    ev[#ev + 1] = { kind = "status", who = att,
      text = (g == "MIMIC" and "%s learned %s!" or "%s sketched %s!"):format(att.name, last.name) }
  elseif g == "TRANSFORM" then
    if att.transformed then return fail() end
    att.transformed = true
    att.type1, att.type2, att.__ndxType3 = target.type1, target.type2, target.__ndxType3
    att.__ndxStat = {}
    for _, k in ipairs({ "attack", "defense", "spAtk", "spDef", "speed" }) do att.__ndxStat[k] = statOf(target, k) end
    for k, v in pairs(target.stages) do att.stages[k] = v end
    att.moves = {}
    att.maxMoves = {}
    for i, m in ipairs(target.moves or {}) do self:putMove(att, i, moveCopy(m, 5)) end
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s transformed into %s!"):format(att.name, target.name) }
  elseif g == "PSYCH_UP" then
    for k, v in pairs(target.stages) do att.stages[k] = v end
    ev[#ev + 1] = { kind = "stage", who = att, text = ("%s copied %s's stat changes!"):format(att.name, target.name) }
  elseif g == "ROLE_PLAY" then
    local name = target.raidAbility or (self.A.abilityName and self.A.abilityName(target))
    if not name or name == "WONDER_GUARD" then return fail() end
    att.raidAbility = name
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s copied %s's ability!"):format(att.name, target.name) }
  elseif g == "SKILL_SWAP" then
    local a = att.raidAbility or (self.A.abilityName and self.A.abilityName(att))
    local b = target.raidAbility or (self.A.abilityName and self.A.abilityName(target))
    if not (a and b) or a == "WONDER_GUARD" or b == "WONDER_GUARD" then return fail() end
    att.raidAbility, target.raidAbility = b, a
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s swapped Abilities with its target!"):format(att.name) }
  elseif g == "TRICK" then
    local a, b = tonumber(att.item) or 0, tonumber(target.item) or 0
    if a == 0 and b == 0 then return fail() end
    att.item, target.item = b, a
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s switched items with its target!"):format(att.name) }
  elseif g == "MEAN_LOOK" then
    if target.meanLooked then return fail() end
    target.meanLooked = true
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s can no longer escape!"):format(target.name) }
  elseif g == "FORESIGHT" then
    target.expIdentified = true
    target.stages.evasion = min(0, target.stages.evasion or 0)
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s was identified!"):format(target.name) }
  elseif g == "YAWN" then
    if target.status or target.yawn or self:sideOf(target).safeguard > 0 then return fail() end
    target.yawn = 2
    ev[#ev + 1] = { kind = "status", who = target, text = ("%s made %s drowsy!"):format(att.name, target.name) }
  else
    return nil
  end
  return true
end

-- the end of the turn's share of Gen 3's: Perish Song's count, Yawn, Charge, the Sports, Taunt, Disable
function Sim:g3EndTurn(ev)
  for _, b in ipairs(self:everyone()) do
    if not self.over and alive(b) then
      if b.yawn then
        b.yawn = b.yawn - 1
        if b.yawn <= 0 then
          b.yawn = nil
          if not b.status then self:status(ev, b, "SLP", true) end
        end
      end
      if b.perish then
        b.perish = b.perish - 1
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s's perish count fell to %d."):format(b.name, b.perish) }
        if b.perish <= 0 then
          b.perish = nil
          b.mon.hp = 0
          ev[#ev + 1] = { kind = "residual", who = b, amount = 0, hp = 0 }
          self:fainted(ev, b)
        end
      end
    end
    if b.expCharged then
      b.expCharged = b.expCharged - 1
      if b.expCharged <= 0 then b.expCharged = nil end
    end
    if (b.taunt or 0) > 0 then
      b.taunt = b.taunt - 1
      if b.taunt <= 0 then
        b.taunt = nil
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s's taunt wore off!"):format(b.name) }
      end
    end
    if b.disabled then
      b.disabled.turns = b.disabled.turns - 1
      if b.disabled.turns <= 0 then
        b.disabled = nil
        ev[#ev + 1] = { kind = "status", who = b, text = ("%s is no longer disabled!"):format(b.name) }
      end
    end
  end
  for _, key in ipairs({ "mudSport", "waterSport" }) do
    local f = self.ndx
    if (f[key] or 0) > 0 then
      f[key] = f[key] - 1
      if f[key] <= 0 then
        f[key] = nil
        ev[#ev + 1] = { kind = "field", who = self.boss,
          text = key == "mudSport" and "The effects of Mud Sport have faded." or "The effects of Water Sport have faded." }
      end
    end
  end
end

Sim.WEATHER_TEXT = {
  RAIN = { up = "It started to rain!", down = "The rain stopped." },
  SUN = { up = "The sunlight turned harsh!", down = "The sunlight faded." },
  SAND = { up = "A sandstorm kicked up!", down = "The sandstorm subsided." },
  HAIL = { up = "It started to hail!", down = "The hail stopped." },
}
-- the words of a charge turn, by move
Sim.CHARGE_TEXT = { solarbeam = "%s absorbed light!", razorwind = "%s made a whirlwind!", skullbash = "%s tucked in its head!",
  skyattack = "%s became cloaked in a harsh light!", fly = "%s flew up high!", dig = "%s burrowed its way under the ground!",
  dive = "%s hid underwater!", bounce = "%s sprang up!", phantomforce = "%s vanished instantly!",
  shadowforce = "%s vanished instantly!", solarblade = "%s absorbed light!", electroshot = "%s absorbed electricity!",
  meteorbeam = "%s is overflowing with space power!" }
-- how many times a multi-hit move strikes: 2-5 (35 / 35 / 15 / 15 %), a fixed count, or Triple Kick's three
function Sim:hitCount(mv)
  local h = mv.side and mv.side.hits
  if h == "multi" then
    local r = self.rng(1, 100)
    return r <= 35 and 2 or r <= 70 and 3 or r <= 85 and 4 or 5
  elseif h == "triple" then return 3
  elseif type(h) == "number" then return h end
  return 1
end

-- (locked: true - a move the sim makes it use, a charge's release, a rampage; "called" - a move
-- another called: Metronome, Sleep Talk ...)
function Sim:use(ev, att, mv, targets, ally, locked)
  if not alive(att) or self.over then return end
  if locked ~= "called" then
    if self:held(ev, att, mv) then att.semi = nil; self:unlock(att, true); return end
    -- tormented: not the move it used last; Disable, Taunt, Imprison
    if self:tormented(att, mv) then
      ev[#ev + 1] = { kind = "cant", who = att, torment = true,
        text = ("%s can't use the same move twice in a row due to the torment!"):format(att.name) }
      return
    end
    local why = self:barredWhy(att, mv)
    if why then
      ev[#ev + 1] = { kind = "cant", who = att, text = ("%s can't use %s because of %s!"):format(att.name, mv.name, why) }
      return
    end
  end
  ev[#ev + 1] = { kind = "use", who = att, move = mv, gmax = mv.isGmax == true,
    text = ("%s used %s!"):format(att.name, mv.name) }
  -- (the move it last used: G-Max Depletion takes its PP, Torment bars it; a called move is not it)
  if locked ~= "called" then att.lastMove = mv.base or mv end
  -- (Choice Band: the move it keeps to from now on)
  if locked ~= "called" and not att.dmax and not att.choiced and self:heldOf(att) == "CHOICE_BAND" then
    att.choiced = mv.base or mv
  end
  -- under Gravity the moves that leave the ground fail
  if (self.gravity or 0) > 0 and Sim.NO_GRAVITY[squash(mv.key)] then
    ev[#ev + 1] = { kind = "fail", text = ("%s can't use %s because of gravity!"):format(att.name, mv.name) }
    return
  end
  -- (a Max Move spends its base move's PP)
  if not att.boss and not locked then
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
  -- Fake Out and First Impression work only on the user's first turn out
  if Sim.FIRST_TURN[squash(mv.key)] and att.outSince ~= self.turnNo then
    ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    return
  end
  -- Throat Chop: no sound moves for two turns; the National Dex's moves that fail first (Sucker
  -- Punch with nothing coming, Last Resort, Burn Up without the Fire type ...)
  if (att.__ndxThroatChop or 0) > 0 and Sim.SOUND[squash(mv.key)] then
    ev[#ev + 1] = { kind = "fail", text = ("The effects of Throat Chop prevent %s from using sound moves!"):format(att.name) }
    return
  end
  if self:ruleFails(att, mv, targets) then
    ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    return
  end
  if self:g3Fails(ev, att, mv, targets) then return end
  -- a move that calls another (Metronome, Assist, Sleep Talk, Nature Power, Mirror Move, Copycat)
  local g = mv.side and mv.side.g3
  if g == "METRONOME" or g == "ASSIST" or g == "SLEEP_TALK" or g == "NATURE_POWER" or g == "MIRROR_MOVE" then
    local called = self:calledMove(att, mv, targets[1] or self.boss)
    if not called then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      return
    end
    return self:use(ev, att, called, self:targetsFor(att, called), nil, "called")
  end
  -- (Copycat's: the last move anyone used)
  self.lastUsed = mv.base or mv
  self:noteEcho(mv)
  -- a team move (screens, guards, heals, ...)
  local T = asTeamMove(att, mv, ally or targets[1])
  if T then return self:teamMove(ev, att, mv, T, ally) end
  -- a status move on its user
  if mv.status and mv.side and mv.side.self then
    -- (Snatch: a foe waiting for it takes the move for itself)
    for _, x in ipairs(self:everyone()) do
      if x.snatch == self.turnNo and foes(x, att) and alive(x) then
        x.snatch = nil
        ev[#ev + 1] = { kind = "status", who = x, text = ("%s snatched %s's move!"):format(x.name, att.name) }
        self:side(ev, x, x, mv, false)
        return
      end
    end
    self:side(ev, att, att, mv, false)
    return
  end
  local key = squash(mv.key)
  local sd0 = mv.side
  -- a move with a turn to charge: this turn only gathers (out of reach for Fly, Dig, Dive, Bounce), the
  -- member then releases it on its own next turn (the boss strikes at once)
  -- (in the sun Solar Beam and Solar Blade need no charge, nor Electro Shot in the rain)
  local quick = ((key == "solarbeam" or key == "solarblade") and self.weather == "SUN")
    or (key == "electroshot" and self.weather == "RAIN")
  if sd0 and sd0.charge and not quick and not att.boss and not att.dmax and not (locked == true and lockOf(att, "charge")) then
    att.lock = { kind = "charge", mv = mv, release = true }
    if sd0.semi then att.semi = Sim.SEMI_KIND[key] or true end
    ev[#ev + 1] = { kind = "status", who = att, charge = true, semi = att.semi, move = mv,
      text = (Sim.CHARGE_TEXT[key] or "%s is charging up!"):format(att.name) }
    if sd0.chargeStages then
      for stat, n in pairs(sd0.chargeStages) do self:stage(ev, att, stat, n) end
    end
    return
  end
  if locked == true and lockOf(att, "charge") then att.semi = nil; self:unlock(att) end
  -- Future Sight and Doom Desire: the hit lands at the end of the turn after next
  if sd0 and sd0.future then
    self.pending = self.pending or {}
    local def = targets[1]
    for _, p in ipairs(self.pending) do
      if p.def == def then
        ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
        return
      end
    end
    self.pending[#self.pending + 1] = { att = att, def = def, mv = mv, turns = 3 }
    ev[#ev + 1] = { kind = "status", who = att, text = ("%s foresaw an attack!"):format(att.name) }
    return
  end
  local spread = #targets > 1
  local hit, dealtAll = {}, 0
  -- (Lock-On: this move cannot miss)
  local aimed = att.lockOn
  att.lockOn = nil
  for _, def in ipairs(targets) do
    if self.over then return end
    local stop, sev = nil, nil
    -- (Feint, Hyperspace Hole and a vanished Phantom Force go through Protect; Feint lifts it)
    local through = mv.side and (mv.side.vanish or mv.side.rule == "FEINT" or mv.side.rule == "HYPERSPACE_HOLE")
    if through and def.guard == "protect" and mv.side.rule == "FEINT" then
      def.guard = nil
      ev[#ev + 1] = { kind = "status", who = def, text = ("%s fell for the feint!"):format(def.name) }
    end
    if alive(def) and not (through and def.guard ~= "max") then stop, sev = self:stopped(att, mv, def) end
    if stop == "block" then
      ev[#ev + 1] = sev
      self:contactCost(ev, att, def, mv)
    elseif alive(def) and isDmax(def) and (Sim.WEIGHT[key] or Sim.NO_DMAX[key] or (mv.side and mv.side.ohko)) then
      ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
    elseif alive(def) and mv.side and mv.side.needSleep and def.status ~= "SLP" then
      ev[#ev + 1] = { kind = "effect", eff = 0, target = def, text = ("It doesn't affect %s..."):format(def.name) }
    elseif alive(def) then
      if self:ruleBefore(ev, att, def, mv) then
        -- (stopped before the hit: Powder, Psychic Terrain)
      elseif def.semi and not att.semi and not (Sim.REACH[def.semi] and Sim.REACH[def.semi][key]) then
        ev[#ev + 1] = { kind = "miss", who = att, target = def, text = ("%s avoided the attack!"):format(def.name) }
      elseif aimed ~= def and (not self.A.hits(att, def, mv, (self.gravity or 0) > 0, self.weather) or self:itemDodge(def, mv)) then
        ev[#ev + 1] = { kind = "miss", who = att, target = def, text = ("%s avoided the attack!"):format(def.name) }
        -- Jump Kick and Hi Jump Kick: a miss costs the user half its max HP
        if mv.side and mv.side.missRecoil and alive(att) then
          self:selfHurt(ev, att, floor(maxHpOf(att) / 2), ("%s kept going and crashed!"):format(att.name))
        end
        self:g3After(ev, att, def, mv, false)
      elseif mv.status and (def.substituteHP or 0) > 0 and foes(att, def) then
        -- (a substitute takes no status moves)
        ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
      elseif mv.status and def.magicCoat == self.turnNo and foes(att, def) then
        -- (Magic Coat bounces it back)
        ev[#ev + 1] = { kind = "status", who = def, text = ("%s bounced the %s back!"):format(def.name, mv.name) }
        self:side(ev, def, att, mv, false)
      elseif mv.status then
        self:side(ev, att, def, mv, false)
      else
        -- (the target side's screens; Helping Hand on the user)
        local sd = self:sideOf(def)
        -- (Brick Break shatters the target side's screens first)
        if mv.side and mv.side.g3 == "BRICK_BREAK" and (sd.reflect > 0 or sd.light > 0 or sd.veil > 0) then
          sd.reflect, sd.light, sd.veil = 0, 0, 0
          self:syncVeil()
          ev[#ev + 1] = { kind = "side", side = sideKey(def), what = "reflect", up = false, who = att,
            text = "It shattered the barrier!" }
        end
        -- (a move reaching one mid-Fly, Dig or Dive hits it twice as hard: Gust, Earthquake, Surf)
        local reach = def.semi and Sim.REACH[def.semi] and Sim.REACH[def.semi][key]
        local nHits, landed, total = self:hitCount(mv), 0, 0
        local triple = mv.side and mv.side.hits == "triple"
        -- (Beat Up: one blow from each of the team on the field without a status, the user among them)
        local beat = nil
        if mv.side and mv.side.g3 == "BEAT_UP" and not att.boss then
          beat = {}
          for _, m in ipairs(self:team()) do if not m.status then beat[#beat + 1] = m end end
          if #beat == 0 then beat = { att } end
          nHits = #beat
        end
        local g3power = self:g3Power(att, def, mv)
        for n = 1, nHits do
          if not alive(def) or self.over then break end
          -- (Triple Kick: each kick checks its accuracy again, and hits harder)
          if n > 1 and triple and not self.A.hits(att, def, mv, (self.gravity or 0) > 0, self.weather) then break end
          -- (Present: a fifth of the time it heals the target instead)
          if g3power == "heal" then
            if not self:healFor(ev, def, maxHpOf(def) / 4) then
              ev[#ev + 1] = { kind = "fail", text = ("%s couldn't receive the gift!"):format(def.name) }
            end
            break
          end
          local striker = beat and beat[n] or att
          if beat then ev[#ev + 1] = { kind = "status", who = striker, text = ("%s's attack!"):format(striker.name) } end
          local dmg, info = self.A.damage(striker, def, mv, spread, { reflect = sd.reflect > 0 or sd.veil > 0,
            lightScreen = sd.light > 0 or sd.veil > 0, doubleScreens = not def.boss, helped = att.helped or nil,
            gravity = (self.gravity or 0) > 0 or nil, weather = self.weather, turn = self.turnNo, field = self:ndxField(),
            magicRoom = (self.ndx.magicRoom or 0) > 0 or nil, noCrit = (sd.luckyChant or 0) > 0 or nil,
            mudSport = (self.ndx.mudSport or 0) > 0 or nil, waterSport = (self.ndx.waterSport or 0) > 0 or nil,
            power = triple and (tonumber(mv.power) or 10) * n or (beat and 10) or (type(g3power) == "number" and g3power) or nil })
          info = info or {}
          local eff = tonumber(info.effectiveness) or 1
          -- (Counter, Mirror Coat, Endeavor with nothing to answer)
          if info.failed then
            ev[#ev + 1] = { kind = "fail", text = "But it failed!" }
            break
          end
          if eff == 0 then
            ev[#ev + 1] = { kind = "effect", eff = 0, target = def, text = ("It doesn't affect %s..."):format(def.name) }
            break
          end
          local hadShield = def.shield ~= nil
          -- (a move striking more than one: Sword / Shield's 3 / 4)
          if spread then dmg = floor(dmg * Sim.SPREAD_K) end
          if Sim.ANTI_DMAX[key] and isDmax(def) then dmg = dmg * 2 end
          if reach == 2 then dmg = dmg * 2 end
          if stop == "pierce" then dmg = floor(dmg / 4) end
          -- (a one-hit knockout)
          if mv.side and mv.side.ohko then dmg = hpOf(def) end
          -- (a substitute takes the hit while it lasts, and nothing else lands)
          if (def.substituteHP or 0) > 0 and def ~= att then
            dmg = min(def.substituteHP, max(1, dmg))
            def.substituteHP = def.substituteHP - dmg
            landed, total = landed + 1, total + dmg
            ev[#ev + 1] = { kind = "status", who = def, text = ("The substitute took damage for %s!"):format(def.name) }
            if def.substituteHP <= 0 then
              def.substituteHP = nil
              ev[#ev + 1] = { kind = "status", who = def, substitute = false, text = ("%s's substitute faded!"):format(def.name) }
            end
            goto nextHit
          end
          dmg = self:throughBoss(ev, def, max(1, dmg))
          dmg = self:capAtShield(def, min(hpOf(def), dmg))
          local endured, banded = false, nil
          if def.endure and dmg >= hpOf(def) and hpOf(def) > 1 then dmg, endured = hpOf(def) - 1, true end
          if not endured and not (mv.side and mv.side.ohko) then
            banded = self:focusBand(def, dmg)
            if banded then dmg = hpOf(def) - 1 end
          end
          def.mon.hp = hpOf(def) - dmg
          dealtAll = dealtAll + dmg
          self:noteHurt(def, att, mv, dmg)
          def.lastHitType = mv.type
          -- (Bide stores what it takes)
          local bide = lockOf(def, "bide")
          if bide then bide.stored, bide.from = (bide.stored or 0) + dmg, att end
          if n == 1 then hit[#hit + 1] = def end
          landed, total = landed + 1, total + dmg
          ev[#ev + 1] = { kind = "damage", who = att, target = def, amount = dmg, hp = def.mon.hp, move = mv }
          if stop == "pierce" and n == 1 then ev[#ev + 1] = sev end
          if endured or banded then
            ev[#ev + 1] = { kind = "side", side = sideKey(def), what = "endured", up = true, who = def,
              text = banded or self:tword("endured", nil, def) or ("%s endured the hit!"):format(def.name) }
          end
          if info.critical then ev[#ev + 1] = { kind = "crit", target = def, text = "A critical hit!" } end
          if n == 1 then
            if mv.side and mv.side.ohko then ev[#ev + 1] = { kind = "effect", eff = 1, target = def, text = "It's a one-hit KO!" }
            elseif eff > 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's super effective!" }
            elseif eff < 1 then ev[#ev + 1] = { kind = "effect", eff = eff, target = def, text = "It's not very effective..." } end
          end
          if alive(def) then
            -- (Rage builds)
            if def.raging then self:stage(ev, def, "attack", 1) end
            self:side(ev, att, def, mv, true, dmg)
            if def.boss and hadShield and def.shield and def.shield.left <= 0 then self:breakShield(ev) end
            if def.boss then self:checkShield(ev) end
          else
            -- (a drain or recoil on the blow that knocks it out counts too)
            if mv.side then self:drain(ev, att, def, mv.side, dmg) end
            -- (Grudge: the move that did it loses all its PP; Destiny Bond takes the attacker too,
            -- unless it is Dynamaxed)
            if def.grudge then
              local pm = mv.base or mv
              pm.pp = 0
              ev[#ev + 1] = { kind = "status", who = att, text = ("%s's %s lost all its PP due to the grudge!"):format(att.name, pm.name) }
            end
            local bond = def.destinyBond and alive(att) and not isDmax(att) and att ~= def
            self:fainted(ev, def)
            if bond and not self.over then
              ev[#ev + 1] = { kind = "status", who = def, text = ("%s took its attacker down with it!"):format(def.name) }
              att.mon.hp = 0
              ev[#ev + 1] = { kind = "residual", who = att, amount = 0, hp = 0 }
              self:fainted(ev, att)
            end
          end
          ::nextHit::
        end
        if landed > 0 and not self.over then self:ruleAfter(ev, att, def, mv, total) end
        if not self.over then self:g3After(ev, att, def, mv, landed > 0) end
        if landed > 1 and not self.over then
          ev[#ev + 1] = { kind = "hits", target = def, n = landed, text = ("Hit %d times!"):format(landed) }
        end
      end
    end
  end
  if mv.gmaxEffect and #hit > 0 and not self.over then self:gmaxEffect(ev, att, mv, hit) end
  -- King's Rock and Shell Bell
  if #hit > 0 then self:itemAfterMove(ev, att, mv, hit, dealtAll) end
  -- Hyper Beam and kin: the user must recharge next turn; Outrage and kin: 2-3 turns on one move, then
  -- confused (a member's own, never a Dynamaxed one's)
  local sd1 = mv.side
  if sd1 and not att.boss and not att.dmax and alive(att) and not self.over then
    if sd1.recharge and #hit > 0 and self.dmaxActive ~= att then att.recharge = true end
    if sd1.rampage then
      local L = lockOf(att, "rampage")
      if not att.lock then
        att.lock = { kind = "rampage", mv = mv, turns = self.rng(1, 2) }
      elseif L then
        L.turns = L.turns - 1
        if L.turns <= 0 then
          self:unlock(att)
          self:confuse(ev, att)
        end
      end
    end
  end
  -- Explosion / Self-Destruct / Misty Explosion: the member that used it faints, hit or not; Mind
  -- Blown / Steel Beam cost it half its max HP (the boss is spared both)
  if not att.boss and alive(att) and not self.over then
    if Sim.SELF_KO[key] then
      att.mon.hp = 0
      ev[#ev + 1] = { kind = "residual", who = att, amount = 0, hp = 0 }
      self:fainted(ev, att)
    elseif Sim.HALF_COST[key] then
      local cut = min(hpOf(att), math.ceil(maxHpOf(att) / 2))
      att.mon.hp = hpOf(att) - cut
      ev[#ev + 1] = { kind = "residual", who = att, amount = cut, hp = att.mon.hp,
        text = ("%s cut its own HP!"):format(att.name) }
      if not alive(att) then self:fainted(ev, att) end
    end
  end
end

-- ------- held items (Gen 3's, as the engine's battle/held_items.lua; the damage items - type boosts,
-- Choice Band, Scope Lens ... - are the engine's damage's own)

Sim.PINCH_STAT = { ATTACK_UP = "attack", DEFENSE_UP = "defense", SPEED_UP = "speed", SP_ATTACK_UP = "spAtk",
  SP_DEFENSE_UP = "spDef" }
Sim.CONFUSE_FLAVOR = { CONFUSE_SPICY = 0, CONFUSE_DRY = 1, CONFUSE_SWEET = 2, CONFUSE_BITTER = 3, CONFUSE_SOUR = 4 }
Sim.FLAVOR_WORD = { [0] = "spicy", "dry", "sweet", "bitter", "sour" }
Sim.CURE_ITEM = { CURE_PAR = { PAR = true }, CURE_SLP = { SLP = true }, CURE_PSN = { PSN = true, TOX = true },
  CURE_BRN = { BRN = true }, CURE_FRZ = { FRZ = true } }
Sim.CURE_TEXT = { CURE_PAR = "%s's %s cured paralysis!", CURE_SLP = "%s's %s woke it from its sleep!",
  CURE_PSN = "%s's %s cured poison!", CURE_BRN = "%s's %s healed its burn!", CURE_FRZ = "%s's %s defrosted it!" }
local PROBLEM = { PSN = "poison", TOX = "poison", SLP = "sleep", PAR = "paralysis", BRN = "burn", FRZ = "ice" }
local PINCH_ORDER = { "attack", "defense", "speed", "spAtk", "spDef" }

-- a battler's held item: its hold effect's name, parameter and item (the adapter's held), nil without
-- one or under Magic Room
function Sim:heldOf(b)
  if not self.A.held or (tonumber(b.item) or 0) == 0 or (self.ndx.magicRoom or 0) > 0 then return nil end
  return self.A.held(b)
end
function Sim:itemName(item) return self.A.itemName and self.A.itemName(item) or "item" end

-- an item's heal (`amt` HP): false when there is nothing to heal
function Sim:itemHeal(ev, b, amt, text)
  if not canHeal(b) or hpOf(b) >= maxHpOf(b) then return false end
  b.mon.hp = min(maxHpOf(b), hpOf(b) + max(1, floor(amt)))
  ev[#ev + 1] = { kind = "heal", who = b, hp = b.mon.hp, held = true, text = text }
  return true
end

-- the curing items (a status berry, Persim, Lum, Mental Herb, White Herb): true when it worked, the
-- item used up
function Sim:itemCure(ev, b, he, item)
  local name, s, text = self:itemName(item), b.status, nil
  if Sim.CURE_ITEM[he] then
    if not (s and Sim.CURE_ITEM[he][s]) then return false end
    if s == "SLP" then b.nightmare = nil end
    b.status, b.sleep, b.tox = nil, nil, nil
    text = Sim.CURE_TEXT[he]:format(b.name, name)
  elseif he == "CURE_CONFUSION" then
    if not b.confused then return false end
    b.confused = nil
    text = ("%s's %s snapped it out of confusion!"):format(b.name, name)
  elseif he == "CURE_ATTRACT" then
    if not b.attract then return false end
    b.attract = nil
    text = ("%s's %s cured its love problem!"):format(b.name, name)
  elseif he == "CURE_STATUS" then
    if not s and not b.confused then return false end
    local word = s and PROBLEM[s] or "confusion"
    local both = s ~= nil and b.confused ~= nil
    if s == "SLP" then b.nightmare = nil end
    b.status, b.sleep, b.tox, b.confused = nil, nil, nil, nil
    text = both and ("%s's %s normalized its status!"):format(b.name, name)
      or ("%s's %s cured its %s problem!"):format(b.name, name, word)
  elseif he == "RESTORE_STATS" then
    local any = false
    for k, v in pairs(b.stages) do if v < 0 then b.stages[k], any = 0, true end end
    if not any then return false end
    text = ("%s's %s returned its stats to normal!"):format(b.name, name)
  else
    return false
  end
  ev[#ev + 1] = { kind = "status", who = b, held = true, text = text }
  loseItem(b)
  return true
end

-- what a held item does on its own, after each action (moveTurn) and at the turn's end: the HP berries
-- at half HP, the confusing berries, Leftovers (the turn's end only), the pinch berries, Leppa and the
-- cures; true when one did something
function Sim:itemNormal(ev, b, moveTurn)
  if self.over or not alive(b) or (b.down or 0) > 0 then return false end
  local he, p, item = self:heldOf(b)
  if not he then return false end
  local hp, top, name = hpOf(b), maxHpOf(b), self:itemName(item)
  p = tonumber(p) or 0
  if he == "RESTORE_HP" then
    if hp <= floor(top / 2) and self:itemHeal(ev, b, p, ("%s's %s restored its health!"):format(b.name, name)) then
      loseItem(b)
      return true
    end
  elseif he == "LEFTOVERS" then
    if not moveTurn then
      return self:itemHeal(ev, b, top / 16, ("%s restored a little HP using its %s!"):format(b.name, name))
    end
  elseif Sim.CONFUSE_FLAVOR[he] then
    if hp <= floor(top / 2) and self:itemHeal(ev, b, top / max(1, p), ("%s's %s restored its health!"):format(b.name, name)) then
      local flavor = Sim.CONFUSE_FLAVOR[he]
      if self.A.dislikes and self.A.dislikes(b, flavor) then
        ev[#ev + 1] = { kind = "status", who = b, text = ("For %s, the %s was too %s!"):format(b.name, name, Sim.FLAVOR_WORD[flavor]) }
        if not (self.A.abilityName and self.A.abilityName(b) == "OWN_TEMPO") then self:confuse(ev, b) end
      end
      loseItem(b)
      return true
    end
  elseif Sim.PINCH_STAT[he] then
    local stat = Sim.PINCH_STAT[he]
    if hp <= floor(top / max(1, p)) and (b.stages[stat] or 0) < 6 then
      local n0 = #ev
      self:stage(ev, b, stat, 1)
      if ev[n0 + 1] then ev[n0 + 1].text = ("Using its %s, %s's %s rose!"):format(name, b.name, STAT_WORD[stat]) end
      loseItem(b)
      return true
    end
  elseif he == "CRITICAL_UP" then
    if hp <= floor(top / max(1, p)) and (b.critUp or 0) < 2 then
      b.critUp = 2
      ev[#ev + 1] = { kind = "status", who = b, held = true, text = ("%s used its %s to get pumped!"):format(b.name, name) }
      loseItem(b)
      return true
    end
  elseif he == "RANDOM_STAT_UP" then
    if hp <= floor(top / max(1, p)) then
      local open = {}
      for _, s in ipairs(PINCH_ORDER) do if (b.stages[s] or 0) < 6 then open[#open + 1] = s end end
      if #open > 0 then
        local stat = open[self.rng(1, #open)]
        local n0 = #ev
        self:stage(ev, b, stat, 2)
        if ev[n0 + 1] then ev[n0 + 1].text = ("Using its %s, %s's %s rose sharply!"):format(name, b.name, STAT_WORD[stat]) end
        loseItem(b)
        return true
      end
    end
  elseif he == "RESTORE_PP" then
    for _, mv in ipairs(b.moves or {}) do
      if (mv.pp or 1) == 0 then
        mv.pp = min(mv.maxPp or p, p)
        ev[#ev + 1] = { kind = "status", who = b, held = true, text = ("%s's %s restored %s's PP!"):format(b.name, name, mv.name) }
        loseItem(b)
        return true
      end
    end
  else
    return self:itemCure(ev, b, he, item)
  end
  return false
end

-- every battler on the field, the boss first
function Sim:itemsAll(ev, moveTurn)
  for _, x in ipairs(self:everyone()) do
    if self.over then return end
    self:itemNormal(ev, x, moveTurn)
  end
end

-- the hit that would knock `def` out: Focus Band's chance to hang on at 1 HP (its words, or nil)
function Sim:focusBand(def, dmg)
  if dmg < hpOf(def) then return nil end
  local he, p, item = self:heldOf(def)
  if he ~= "FOCUS_BAND" or self.rng(0, 99) >= (tonumber(p) or 0) then return nil end
  return ("%s hung on using its %s!"):format(def.name, self:itemName(item))
end

-- a move's accuracy against BrightPowder / Lax Incense: true when the item makes it miss
function Sim:itemDodge(def, mv)
  if (mv.accuracy or 0) <= 0 then return false end
  local he, p = self:heldOf(def)
  return he == "EVASION_UP" and self.rng(1, 100) <= (tonumber(p) or 0)
end

-- after a move that dealt `dealt`: King's Rock's flinch on whom it hit (a move the flag allows), Shell
-- Bell's heal of its share
function Sim:itemAfterMove(ev, att, mv, hit, dealt)
  if self.over or not alive(att) then return end
  local he, p, item = self:heldOf(att)
  if he == "FLINCH" and mv.kingsRock then
    for _, def in ipairs(hit) do
      if alive(def) and not isDmax(def) and def.actedTurn ~= self.turnNo and self.rng(0, 99) < (tonumber(p) or 0) then
        def.flinched = true
      end
    end
  elseif he == "SHELL_BELL" and dealt > 0 then
    self:itemHeal(ev, att, dealt / max(1, tonumber(p) or 8), ("%s restored a little HP using its %s!"):format(att.name, self:itemName(item)))
  end
end

-- Choice Band: the move it first used it keeps to while it holds the band (not while Dynamaxed)
function Sim:choiceLocked(b, mv)
  local c = b.choiced
  -- (out of PP its other moves come back: the raid has no Struggle to fall back on)
  if not c or b.dmax or (mv.base or mv) == c or (c.pp or 1) <= 0 then return false end
  if self:heldOf(b) ~= "CHOICE_BAND" then return false end
  for _, m in ipairs(b.moves or {}) do if m == c then return true end end
  return false
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
  -- (a lock - Rollout, Bide, Uproar - goes on; never one Disable, Taunt, Imprison or a grudge bars)
  if b.lock then return b.lock.mv end
  local list = {}
  for _, m in ipairs(b.moves) do
    if (m.pp == nil or m.pp > 0) and not self:barredWhy(b, m) then list[#list + 1] = m end
  end
  if #list == 0 then list = b.moves end
  if #list == 0 then return b.gmax end
  return list[self.rng(1, #list)]
end

-- whom a move falls on: the boss for the members; for the boss, a spread move every member on the
-- field, else one of them at random
-- (a team's centre of attention - Follow Me, Rage Powder - draws the boss's single-target moves)
-- (a member's move that hits its allies too - Surf, Earthquake, Discharge ...: `friendly` - falls on
-- the boss and every other member on the field, never on its user)
function Sim:targetsFor(att, mv)
  if not att.boss then
    if not mv.friendly then return { self.boss } end
    local list = { self.boss }
    for i = 1, #self.members do
      local m = self.members[i]
      if m ~= att and self:present(i) then list[#list + 1] = m end
    end
    return list
  end
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
  -- (ail: the status that hurt it, for its look)
  local function hurt(who, cut, text, ail)
    if self.over or not alive(who) then return end
    cut = self:capAtShield(who, min(hpOf(who), max(1, cut)))
    if cut <= 0 then return end
    who.mon.hp = hpOf(who) - cut
    ev[#ev + 1] = { kind = "residual", who = who, amount = cut, hp = who.mon.hp, text = text, ail = ail }
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
      -- (counted down first: the hurt may knock it out, which lets the trap go)
      m.trap = m.trap - 1
      hurt(m, floor(maxHpOf(m) / (m.trapFrac or 8)), fill(W.trapHurt or "{MON} is hurt by the trap!", b, m))
    end
  end
  -- the held items (Leftovers, berries), before Leech Seed and poison as Gen 3's turn's end
  self:itemsAll(ev, false)
  if self.over then return end
  -- Leech Seed: 1/8 of the seeded one's HP to whoever planted it
  for _, x in ipairs(trapped) do
    local by = x.seeded
    if by and not self.over and alive(x) then
      if not alive(by) or (by.down or 0) > 0 then
        x.seeded = nil
      else
        local cut = self:capAtShield(x, min(hpOf(x), max(1, floor(maxHpOf(x) / 8))))
        x.mon.hp = hpOf(x) - cut
        ev[#ev + 1] = { kind = "residual", who = x, amount = cut, hp = x.mon.hp, text = ("%s's health is sapped by Leech Seed!"):format(x.name) }
        if not alive(x) then self:fainted(ev, x) elseif x.boss then self:checkShield(ev) end
        if not self.over and alive(by) and canHeal(by) then
          by.mon.hp = min(maxHpOf(by), hpOf(by) + cut)
          ev[#ev + 1] = { kind = "heal", who = by, hp = by.mon.hp, text = ("%s regained health!"):format(by.name) }
        end
      end
    end
  end
  -- a curse and a nightmare take a quarter of the HP; roots restore a sixteenth
  for _, x in ipairs(trapped) do
    if not self.over and alive(x) then
      if x.cursed then hurt(x, floor(maxHpOf(x) / 4), ("%s is afflicted by the curse!"):format(x.name)) end
      if x.nightmare then
        if x.status == "SLP" then hurt(x, floor(maxHpOf(x) / 4), ("%s is locked in a nightmare!"):format(x.name))
        else x.nightmare = nil end
      end
      if x.ingrained and alive(x) and canHeal(x) and hpOf(x) < maxHpOf(x) then
        x.mon.hp = min(maxHpOf(x), hpOf(x) + max(1, floor(maxHpOf(x) / 16)))
        ev[#ev + 1] = { kind = "heal", who = x, hp = x.mon.hp, text = ("%s absorbed nutrients with its roots!"):format(x.name) }
      end
    end
  end
  -- the National Dex's marks: Aqua Ring, Grassy Terrain, Salt Cure, Octolock, the rooms and terrain
  self:ruleEndTurn(ev, trapped)
  if self.over then return end
  self:g3EndTurn(ev)
  if self.over then return end
  -- Future Sight and Doom Desire land two turns on
  for k = #(self.pending or {}), 1, -1 do
    local p = self.pending[k]
    p.turns = p.turns - 1
    if p.turns <= 0 and not self.over then
      table.remove(self.pending, k)
      local def = p.def
      if def and alive(def) and (def.down or 0) == 0 then
        local dmg, info = self.A.damage(p.att, def, p.mv, false, { weather = self.weather })
        info = info or {}
        if (tonumber(info.effectiveness) or 1) == 0 or dmg <= 0 then
          ev[#ev + 1] = { kind = "effect", eff = 0, target = def, text = ("It doesn't affect %s..."):format(def.name) }
        else
          dmg = self:capAtShield(def, min(hpOf(def), self:throughBoss(ev, def, max(1, dmg))))
          def.mon.hp = hpOf(def) - dmg
          ev[#ev + 1] = { kind = "damage", who = p.att, target = def, amount = dmg, hp = def.mon.hp, move = p.mv,
            text = ("%s took the %s attack!"):format(def.name, p.mv.name) }
          if not alive(def) then self:fainted(ev, def) elseif def.boss then self:checkShield(ev) end
        end
      end
    end
  end
  -- weather: sandstorm and hail chip away, and it runs down
  if self.weather and not self.over then
    local kind = self.weather
    local spared = ({ SAND = { [5] = true, [4] = true, [8] = true }, HAIL = { [15] = true } })[kind]
    if spared then
      for _, x in ipairs(trapped) do
        if not self.over and alive(x) and not (spared[x.type1] or spared[x.type2 or -1]) then
          hurt(x, floor(maxHpOf(x) / 16), kind == "SAND" and ("%s is buffeted by the sandstorm!"):format(x.name)
            or ("%s is pelted by the hail!"):format(x.name))
        end
      end
    end
    self.weatherTurns = (self.weatherTurns or 1) - 1
    if self.weatherTurns <= 0 and not self.over then
      ev[#ev + 1] = { kind = "field", who = b, weather = false, text = Sim.WEATHER_TEXT[kind].down }
      self.weather, self.weatherTurns = nil, nil
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
      hurt(x, cut, st == "BRN" and ("%s was hurt by its burn!"):format(x.name) or ("%s was hurt by poison!"):format(x.name), st)
    end
  end
  if self.over then return end
  -- the held items once more (a berry for what the turn's end took; Leftovers only the once)
  self:itemsAll(ev, true)
  if self.over then return end
  -- a wish comes true at the end of the turn after it was made, on whoever stands in its place
  for _, key in ipairs({ "team", "boss" }) do
    local w = self.sides[key].wish
    if w then
      w.turns = w.turns - 1
      if w.turns <= 0 then
        self.sides[key].wish = nil
        local who = key == "boss" and b or (w.slot and self:present(w.slot) and self.members[w.slot]) or nil
        if who and alive(who) and canHeal(who) and hpOf(who) < maxHpOf(who) then
          who.mon.hp = min(maxHpOf(who), hpOf(who) + w.amount)
          ev[#ev + 1] = { kind = "heal", who = who, hp = who.mon.hp, wish = true,
            text = self:tword("wishTrue", nil, { name = w.name }) or ("%s's wish came true!"):format(w.name) }
        end
      end
    end
  end
  -- Gravity runs down
  if (self.gravity or 0) > 0 then
    self.gravity = self.gravity - 1
    if self.gravity == 0 then
      ev[#ev + 1] = { kind = "side", side = "field", what = "gravity", up = false,
        text = W.gravityEnd or "Gravity returned to normal!" }
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
    m.flinched = nil
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
        -- (its side's hazards meet it)
        self:entry(ev, m)
        if self.over then return end
      end
    end
  end
end

function Sim:turn(choices)
  local ev = {}
  if self.over then return ev end
  -- (this turn's hurts start again: Assurance, Metal Burst, Shell Trap)
  for _, b in ipairs(self:everyone()) do
    b.damageTakenThisTurn, b.lastPhysicalDamageTaken, b.lastSpecialDamageTaken = nil, nil, nil
  end
  local acts = {}
  local itemPri = self.rules.ITEM_PRIORITY or 6
  -- Dynamax first, before anyone moves
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    if c and c.dmax and c.move and self:canDynamax(i) then self:dynamax(ev, m, i) end
  end
  for i, m in ipairs(self.members) do
    local c = choices and choices[i]
    if self:present(i) and (m.recharge or m.lock) then
      -- (recharging, or locked into a move: no choice this turn)
      if m.recharge then
        acts[#acts + 1] = { who = m, recharge = true, pri = 0, tie = self.rng(1, 65536) }
      else
        local lmv = m.lock.mv
        acts[#acts + 1] = { who = m, mv = lmv, locked = true, pri = lmv.priority or 0, tie = self.rng(1, 65536) }
      end
    elseif self:canAct(i) and c then
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
  -- (Tailwind doubles its side's Speed; under Trick Room the slower move first)
  -- (Macho Brace halves the holder's Speed; Quick Claw: one roll a turn, and those whose claw it
  -- beats move first among their priority)
  local claw = nil
  for _, a in ipairs(acts) do
    a.speed = self.A.speed(a.who) * (self:sideOf(a.who).tailwind > 0 and 2 or 1)
    local he, p = self:heldOf(a.who)
    if he == "MACHO_BRACE" then a.speed = floor(a.speed / 2)
    elseif he == "QUICK_CLAW" then
      claw = claw or self.rng(0, 0xFFFF)
      a.quick = claw < floor(0xFFFF * (tonumber(p) or 0) / 100)
    end
  end
  local twisted = (self.ndx.trickRoom or 0) > 0
  table.sort(acts, function(a, b)
    if a.pri ~= b.pri then return a.pri > b.pri end
    if (a.quick or false) ~= (b.quick or false) then return a.quick == true end
    if a.speed ~= b.speed then
      if twisted then return a.speed < b.speed end
      return a.speed > b.speed
    end
    return a.tie < b.tie
  end)
  -- (what each is about to use: Sucker Punch reads it)
  self.pendingMove = {}
  for _, a in ipairs(acts) do if a.mv then self.pendingMove[a.who] = a.mv end end
  for _, a in ipairs(acts) do
    if self.over then break end
    if a.cheer then
      if (a.who.down or 0) > 0 then self:cheer(ev, a.who) end
    elseif a.item then
      if alive(a.who) and (a.who.down or 0) == 0 then self:useItem(ev, a.who, a.item, a.target) end
    elseif a.recharge then
      a.who.recharge = nil
      if alive(a.who) and (a.who.down or 0) == 0 then
        ev[#ev + 1] = { kind = "cant", who = a.who, text = ("%s must recharge!"):format(a.who.name) }
      end
    elseif alive(a.who) and (a.who.boss or (a.who.down or 0) == 0) then
      a.who.actedTurn = self.turnNo
      local g = a.mv.side and a.mv.side.g3
      if g ~= "DESTINY_BOND" then a.who.destinyBond = nil end
      if g ~= "GRUDGE" then a.who.grudge = nil end
      if g ~= "RAGE" then a.who.raging = nil end
      if g ~= "FURY_CUTTER" then a.who.furyCutter = nil end
      self:use(ev, a.who, a.mv, self:targetsFor(a.who, a.mv), a.ally, a.locked or (a.who.boss and a.who.lock and true) or nil)
      self:noteMoved(a.who, a.mv)
      -- (an Encore runs down; out of PP it ends)
      local L = a.who.lock
      if a.locked and L and L.kind == "encore" then
        L.turns = L.turns - 1
        if L.turns <= 0 or (L.mv.pp or 0) <= 0 then
          self:unlock(a.who)
          ev[#ev + 1] = { kind = "status", who = a.who, text = ("%s's encore ended!"):format(a.who.name) }
        end
      end
    end
    -- the held items after each action (a berry at half HP, a cure)
    if not self.over then self:itemsAll(ev, true) end
  end
  if not self.over then self:endTurn(ev) end
  if not self.over then
    self.turnNo = self.turnNo + 1
    if self.turnNo > (self.rules.TURNS or 10) then self:endWith("storm") end
  end
  if self.over then
    local text
    if self.over == "win" then text = ("You defeated %s!"):format(self.boss.name)
    elseif self.over == "storm" then text = ("The storm around %s grew too strong!"):format(self.boss.name)
    else text = "Too many Pok\195\169mon fainted..." end
    ev[#ev + 1] = { kind = "over", outcome = self.over, text = text }
    -- a member still giant shrinks back before the catch
    if self.over == "win" and self.dmaxActive then self:undynamax(ev, self.dmaxActive) end
    if self.over ~= "win" then
      ev[#ev + 1] = { kind = "over", outcome = self.over, text = "You were blown out of the den!" }
    end
  end
  return ev
end

return Sim
