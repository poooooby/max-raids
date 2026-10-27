-- Max Raids' numbers (src/training/raid_sim.lua, src/training/raid.lua). Sword / Shield's Max Raid
-- Battles where they are documented; ours where they are not (no official source gives the
-- shield's thresholds, its damage cut, or a 5★ HP multiplier). EVIDENCE classifies each group
-- (dotted key path) as Super Training's rules file does: verified / measured / inferred /
-- placeholder, plus "ours" for numbers of PlayNav's own design.
local N = {}

N.RAID = {
  TURNS = 10,                 -- the storm: a raid ends lost when its 10th turn ends
  FAINTS = 4,                 -- knock-outs in all, the same member counting each time
  SHIELD_DMG = 0.25,          -- a hit's damage while the shield stands
  BREAK_DROP = -2,            -- Def and Sp. Def stages when the shield breaks
  ITEM_PRIORITY = 6,          -- items go before moves
  -- per tier: the boss's level band, HP multiplier, IVs (DVs on Gen 1 / 2: half), HP thresholds
  -- for its shields, the EVs a win gives, the bag size it drops, and the turns a medal allows
  STARS = {
    [1] = { lv = { 15, 20 }, hpMult = 1.4, iv = 10, shields = { 0.5 }, ev = 4, bag = "s", medalTurns = 6 },
    [2] = { lv = { 25, 30 }, hpMult = 1.6, iv = 15, shields = { 0.5 }, ev = 8, bag = "m", medalTurns = 7 },
    [3] = { lv = { 35, 40 }, hpMult = 1.9, iv = 20, shields = { 0.7, 0.3 }, ev = 12, bag = "m", medalTurns = 7 },
    [4] = { lv = { 45, 50 }, hpMult = 2.5, iv = 25, shields = { 0.7, 0.3 }, ev = 20, bag = "l", medalTurns = 8 },
    [5] = { lv = { 55, 60 }, hpMult = 3.0, iv = 31, shields = { 0.7, 0.3 }, ev = 32, bag = "l", medalTurns = 8 },
  },
  -- shield segments: BASE + floor((base Def + base Sp. Def) / PER), within MIN..MAX
  SEGMENTS = { BASE = 2, PER = 60, MIN = 2, MAX = 8 },
  -- a fainted member cheers on the turn it sits out: one of these, by weight
  CHEER = {
    { id = "heal", w = 16 },        -- the team's HP and status restored
    { id = "attack", w = 16 },      -- the team's Attack and Sp. Atk +1
    { id = "defense", w = 16 },     -- the team's Defense and Sp. Def +1
    { id = "speed", w = 16 },       -- the team's Speed +1
    { id = "shield", w = 16 },      -- breaks the boss's shield (only while one stands)
    { id = "nothing", w = 20 },
  },
  -- the raid's own pouch, shared by the team for one raid; never the real bag
  POUCH = {
    { id = "potion", n = 2, heal = 0.5 },
    { id = "full_heal", n = 1 },
    { id = "revive", n = 1 },       -- a sitting-out member back now (its faint still counts)
  },
  -- rewards on a win
  REWARD = { NO_FAINT_MULT = 1.5, FIRST_WIN_MULT = 2, ITEM_ROLLS = { 1, 3 } },
  -- a boss's extras, run in order at the end of each turn
  SCRIPTS = {
    basic = { { kind = "shield" }, { kind = "gmax", every = 3, from = 2 } },
    strong = { { kind = "shield" }, { kind = "gmax", every = 2, from = 2 }, { kind = "wipe", every = 4, from = 4 } },
    fierce = { { kind = "shield" }, { kind = "gmax", every = 2, from = 1 }, { kind = "wipe", every = 3, from = 3 },
      { kind = "statup", hpBelow = 0.5, once = true } },
  },
  -- the boss's size against a member's: by its height, within MIN..MAX
  SIZE = { MIN = 6.5, MAX = 8.5, H0 = 14, H1 = 43 },
  -- the star tiers a den may roll, by the gym badges held (the highest row whose min is reached)
  BADGE_STARS = {
    { min = 0, stars = { 1, 2 } },
    { min = 2, stars = { 1, 2, 3 } },
    { min = 4, stars = { 2, 3, 4 } },
    { min = 6, stars = { 3, 4, 5 } },
    { min = 8, stars = { 4, 5 } },
  },
  -- dens on the routes: how many a route gets (seeded), how often one is active on a day, and
  -- where one may stand: EDGE cells in from the map's border, WARP_GAP cells from any warp, SPREAD
  -- cells from the route's other den, never reserved (src/dens.lua). Grass is fine: the den is drawn
  -- over it. PASSES are tried in order, best first - open = the radius of open ground
  -- round it (2: a 5x5, so it never narrows a path), ground = the radius that must be the map's
  -- ground or grass (no trail, sand, flowers, bridge; 0: the den's own cell); water = the radius of calm
  -- water round a den out on the water (3: a 7x7, a larger body, never a channel); RESERVE_PAD cells round
  -- an NPC's or a trainer's wander area, SIGHT_PAD past a trainer's sight
  DENS = { MIN = 1, MAX = 2, ACTIVE = 0.7, EDGE = 3, WARP_GAP = 4, SPREAD = 8, TRIES = 400,
    PASSES = {
      { name = "clear", open = 2, ground = 1 },
      { name = "water", water = 3 },
      { name = "tight", open = 1, ground = 1 },
      { name = "last", open = 1, ground = 0 },
    },
    RESERVE_PAD = 1, SIGHT_PAD = 1 },
}

N.EVIDENCE = {
  ["RAID.TURNS"] = { class = "verified", source = "Serebii Max Raid Battles; Pokemon.com raid tips: the storm ends the raid after 10 turns", confidence = "high" },
  ["RAID.FAINTS"] = { class = "verified", source = "Serebii; GamerGuides; Pokemon.com: 4 knock-outs in all end the raid", confidence = "high" },
  ["RAID.SHIELD_DMG"] = { class = "ours", source = "the games greatly reduce damage through the barrier, by an unpublished formula (Bulbapedia Max Raid Battle); a quarter is ours", confidence = "medium" },
  ["RAID.BREAK_DROP"] = { class = "verified", source = "Pokemon.com; GameSpot: breaking the barrier sharply lowers the boss's Defense and Sp. Def", confidence = "medium" },
  ["RAID.ITEM_PRIORITY"] = { class = "ours", source = "items before moves, as the main games run the bag; raids have no bag", confidence = "high" },
  ["RAID.STARS"] = { class = "inferred", source = "levels by tier: Serebii (15-20 .. 55-60); HP x1.4 / 1.6 / 1.9 / 2.5 for 1-4★: Bulbapedia Max Raid Battle; 5★ x3.0, the thresholds, IVs, EVs, bags and medal turns are ours; shields: none at 1-2★ in the games (one here, to teach it), one at 3-4★, two at 5★ (Bulbapedia, Pokemon.com)", confidence = "medium" },
  ["RAID.SEGMENTS"] = { class = "ours", source = "the games: 2 to 8 segments, by the boss's defensive stats (Bulbapedia, Serebii); this formula is ours", confidence = "medium" },
  ["RAID.CHEER"] = { class = "verified", source = "Serebii: cheer heals, raises a stat, sets a screen or breaks the barrier, about 16% each, nothing 20%; the screens are a Defense / Sp. Def raise here", confidence = "medium" },
  ["RAID.POUCH"] = { class = "ours", source = "raids in the games have no bag; ITEM is ours", confidence = "high" },
  ["RAID.REWARD"] = { class = "ours", source = "Super Training rewards, ours", confidence = "high" },
  ["RAID.SCRIPTS"] = { class = "inferred", source = "the games: the boss may act more than once a turn (a Max Move, a wave cancelling the players' stat changes); how often is not published (Pokemon.com, GamerGuides, Serebii); these schedules are ours", confidence = "medium" },
  ["RAID.SIZE"] = { class = "ours", source = "the boss drawn 6.5 to 8.5 times a member's height (Sword / Shield's giants tower over the party)", confidence = "high" },
  ["RAID.BADGE_STARS"] = { class = "ours", source = "Wooble 2026-10-26: star tiers open with gym badges; Sword / Shield gates them by badges too, with other cut-offs", confidence = "medium" },
  ["RAID.DENS"] = { class = "ours", source = "Wooble 2026-10-26: dens generated on the routes, seeded per save, refreshing daily", confidence = "high" },
}

return N
