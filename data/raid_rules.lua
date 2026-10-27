-- Max Raids' numbers (src/training/raid_sim.lua, src/training/raid.lua). Sword / Shield's Max Raid
-- Battles where they are documented; ours where they are not (no official source gives the
-- shield's thresholds or its damage cut). EVIDENCE classifies each group
-- (dotted key path) as Super Training's rules file does: verified / measured / inferred /
-- placeholder, plus "ours" for numbers of PlayNav's own design.
local N = {}

N.RAID = {
  TURNS = 10,                 -- the storm: a raid ends lost when its 10th turn ends
  FAINTS = 4,                 -- knock-outs in all, the same member counting each time
  SHIELD_DMG = 0.25,          -- a hit's damage while the shield stands
  BREAK_DROP = -2,            -- Def and Sp. Def stages when the shield breaks
  ITEM_PRIORITY = 6,          -- items go before moves
  -- per tier: the boss's level band, HP multiplier, how many of its IVs are 31 (the rest 0-31; the
  -- caught Pokemon keeps them), HP thresholds for its shields, the EVs a win gives, the bag size it
  -- drops, and the turns a medal allows
  STARS = {
    [1] = { lv = { 15, 20 }, hpMult = 1.4, perfect = 1, shields = { 0.5 }, ev = 4, bag = "s", medalTurns = 6 },
    [2] = { lv = { 25, 30 }, hpMult = 1.6, perfect = 2, shields = { 0.5 }, ev = 8, bag = "m", medalTurns = 7 },
    [3] = { lv = { 35, 40 }, hpMult = 1.9, perfect = 3, shields = { 0.7, 0.3 }, ev = 12, bag = "m", medalTurns = 7 },
    [4] = { lv = { 45, 50 }, hpMult = 2.5, perfect = 4, shields = { 0.7, 0.3 }, ev = 20, bag = "l", medalTurns = 8 },
    [5] = { lv = { 55, 60 }, hpMult = 3.0, perfect = 4, shields = { 0.7, 0.3 }, ev = 32, bag = "l", medalTurns = 8 },
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
  -- rewards on a win: the items rolled from POOL (rows a tier may roll: { item, from stars, most of
  -- it }, ITEM_ROLLS picks, +1 from 4 stars), the boss's Exp to each of the four (the Gen 3 formula,
  -- one participant), the tier's EVs in the boss's best base stat; x NO_FAINT_MULT with no knock-out,
  -- x FIRST_WIN_MULT the first time that boss is beaten
  -- rewards on a win, as Sword / Shield's dens give them (Serebii's den tables, e.g. Den #18), every
  -- tier its own spread; Gen 3 stand-ins where it lacks the item (see EVIDENCE "RAID.REWARD"):
  --   CANDIES   Exp. Candies, always, by tier (National Dex Gen 3 registers them: EXP_CANDY_XS..XL)
  --   TMS       how many TMs (Sword / Shield's TRs: single-use, as Gen 3's TMs are), always, of the
  --             boss's types where it has enough damaging ones, else any damaging TM
  --   BERRIES   N berries, each at CHANCE %, from POOL (two kinds at most)
  --   TREASURES each of ITEMS at CHANCE[tier] %: Nugget, and Big Pearl / Star Piece for the Big Nugget
  --             and Rare Bone Gen 3 lacks
  --   RARE_CANDY its chance %; CAP the Bottle Cap's chance by tier, as a PP Max (no Hyper Training)
  -- No Dynamax Candy (no Dynamax levels), no Exp. or EVs straight to the four (Sword / Shield gives none)
  REWARD = {
    CANDIES = {
      [1] = { { "XS", 5 }, { "S", 1 } },
      [2] = { { "S", 5 }, { "M", 1 } },
      [3] = { { "M", 5 }, { "L", 1 } },
      [4] = { { "M", 2 }, { "L", 3 } },
      [5] = { { "L", 2 }, { "XL", 1 } },
    },
    TMS = { 1, 1, 2, 3, 3 },
    BERRIES = { N = 2, CHANCE = 80, POOL = { "ITEM_POMEG_BERRY", "ITEM_KELPSY_BERRY", "ITEM_QUALOT_BERRY",
      "ITEM_HONDEW_BERRY", "ITEM_GREPA_BERRY", "ITEM_TAMATO_BERRY", "ITEM_LUM_BERRY", "ITEM_SITRUS_BERRY",
      "ITEM_LEPPA_BERRY" } },
    TREASURES = { CHANCE = { 20, 25, 30, 35, 50 }, ITEMS = { "ITEM_NUGGET", "ITEM_BIG_PEARL", "ITEM_STAR_PIECE" } },
    RARE_CANDY = 25,
    CAP = { CHANCE = { 0, 0, 1, 2, 3 }, ITEM = "ITEM_PP_MAX" },
    -- (without National Dex's candies: Rare Candies, this many by tier)
    CANDY_STAND_IN = { 1, 1, 2, 3, 4 },
  },
  -- the catch after a win: a chance by the tier, times the ball's (the engine's catch multipliers:
  -- Great 1.5, Ultra 2; Master never misses); the balls offered in BALLS' order, those the bag holds
  CATCH = {
    CHANCE = { [1] = 90, [2] = 75, [3] = 60, [4] = 45, [5] = 30 },
    BALLS = {
      { "ITEM_POKE_BALL", 1 }, { "ITEM_GREAT_BALL", 1.5 }, { "ITEM_ULTRA_BALL", 2 }, { "ITEM_MASTER_BALL", 0 },
      { "ITEM_PREMIER_BALL", 1 }, { "ITEM_LUXURY_BALL", 1 }, { "ITEM_NET_BALL", 1 }, { "ITEM_DIVE_BALL", 1 },
      { "ITEM_NEST_BALL", 1 }, { "ITEM_REPEAT_BALL", 1 }, { "ITEM_TIMER_BALL", 1 },
    },
  },
  -- a boss's extras, run in order at the end of each turn
  SCRIPTS = {
    basic = { { kind = "shield" }, { kind = "gmax", every = 3, from = 2 } },
    strong = { { kind = "shield" }, { kind = "gmax", every = 2, from = 2 }, { kind = "wipe", every = 4, from = 4 } },
    fierce = { { kind = "shield" }, { kind = "gmax", every = 2, from = 1 }, { kind = "wipe", every = 3, from = 3 },
      { kind = "statup", hpBelow = 0.5, once = true } },
  },
  -- the boss's size against a member's: by its height, within MIN..MAX
  SIZE = { MIN = 6.5, MAX = 8.5, H0 = 14, H1 = 43 },
  -- the star tiers a den may roll, by the gym badges held (the highest row whose min is reached);
  -- Sword / Shield's ranges
  BADGE_STARS = {
    { min = 0, stars = { 1 } },
    { min = 1, stars = { 1, 2 } },
    { min = 3, stars = { 1, 2, 3 } },
    { min = 4, stars = { 2, 3 } },
    { min = 5, stars = { 3, 4 } },
    { min = 7, stars = { 3, 4, 5 } },
  },
  -- dens on the routes: how many a route gets (seeded), how often one is active on a day, and
  -- where one may stand: EDGE cells in from the map's border, WARP_GAP cells from any warp, SPREAD
  -- cells from the route's other den, never reserved (src/dens.lua). Grass is fine: the den is drawn
  -- over it. PASSES are tried in order, best first - open = the radius of open ground
  -- round it (2: a 5x5, so it never narrows a path), ground = the radius that must be the map's
  -- ground or grass (no trail, sand, flowers, bridge; 0: the den's own cell); water = the radius of calm
  -- water round a den out on the water (3: a 7x7, a larger body, never a channel); RESERVE_PAD cells round
  -- an NPC's or a trainer's wander area, SIGHT_PAD past a trainer's sight
  -- RARE: the share of active dens with a purple beam (a Gigantamax boss); the rest are red, a
  -- Pokemon of the route Dynamaxed
  DENS = { MIN = 1, MAX = 2, ACTIVE = 0.7, RARE = 0.1, EDGE = 3, WARP_GAP = 4, SPREAD = 8, TRIES = 400,
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
  ["RAID.STARS"] = { class = "inferred", source = "levels by tier: Serebii (15-20 .. 55-60); HP x1.4 / 1.6 / 1.9 / 2.5 / 3.0 for 1-5★: Bulbapedia Max Raid Battle (5★ x3 also a solo-clear guide, note.com pagepoteto); perfect IVs 1 / 2 / 3 / 4 / 4: Bulbapedia, GameWith; the thresholds, EVs, bags and medal turns are ours; shields: none at 1-2★ in the games (one here, to teach it), one at 3-4★, two at 5★ (Bulbapedia, Pokemon.com)", confidence = "medium" },
  ["RAID.REWARD"] = { class = "inferred", source = "Serebii, Sword / Shield Max Raid den listings (den18): Exp. Candy XS x5 + S x1 (1★), S x5 + M x1 (2★), M x5 + L x1 (3★), M x2 + L x3 (4★), L x2 + XL x1 (5★); Dynamax Candy 1-2; TRs 1 / 1 / 2 / 3 / 3 at 100%; two berries at 80%; Big Nugget / Nugget / Rare Bone 20-50% each by tier; Rare Candy 25%; Bottle Cap 1-3% from 3★. Gen 3 stand-ins ours (TMs for TRs; Big Pearl / Star Piece for Big Nugget / Rare Bone; PP Max for the Bottle Cap; no Dynamax Candy)", confidence = "medium" },
  ["RAID.SEGMENTS"] = { class = "ours", source = "the games: 2 to 8 segments, by the boss's defensive stats (Bulbapedia, Serebii); this formula is ours", confidence = "medium" },
  ["RAID.CHEER"] = { class = "verified", source = "Serebii: cheer heals, raises a stat, sets a screen or breaks the barrier, about 16% each, nothing 20%; the screens are a Defense / Sp. Def raise here", confidence = "medium" },
  ["RAID.POUCH"] = { class = "ours", source = "raids in the games have no bag; ITEM is ours", confidence = "high" },
  ["RAID.REWARD"] = { class = "ours", source = "the games give Exp. Candies, TRs, berries and the like from raids; this pool (Gen 3's items) and the multipliers are ours; the Exp is Gen 3's formula (engine Experience.gainFor)", confidence = "medium" },
  ["RAID.CATCH"] = { class = "inferred", source = "the games: one throw after a win, the ball the player picks, the chance by the boss (Serebii Max Raid Battles); the tier chances are ours, the ball multipliers the engine's (battle/catching.lua BALL_BONUS)", confidence = "medium" },
  ["RAID.SCRIPTS"] = { class = "inferred", source = "the games: the boss may act more than once a turn (a Max Move, a wave cancelling the players' stat changes); how often is not published (Pokemon.com, GamerGuides, Serebii); these schedules are ours", confidence = "medium" },
  ["RAID.SIZE"] = { class = "ours", source = "the boss drawn 6.5 to 8.5 times a member's height (Sword / Shield's giants tower over the party)", confidence = "high" },
  ["RAID.DENS.RARE"] = { class = "inferred", source = "Sword / Shield: a den's beam is red (its common pool) or purple (its rare pool, where the Gigantamax Pokemon are); ~10% purple by players' counts (GameFAQs), no datamined figure", confidence = "low" },
  ["RAID.BADGE_STARS"] = { class = "verified", source = "Sword / Shield's star range by badges (0: 1, 1-2: 1-2, 3: 1-3, 4: 2-3, 5-6: 3-4, 7-8: 3-5; Smogon's SwSh shiny hunting guide); the pick within a range is even (the game weights per den)", confidence = "medium" },
  ["RAID.DENS"] = { class = "ours", source = "Wooble 2026-10-26: dens generated on the routes, seeded per save, refreshing daily", confidence = "high" },
}

return N
