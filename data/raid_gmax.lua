-- The bosses' G-Max moves (data/raid_bosses.lua `gmax`). In a raid the boss uses its G-Max move on
-- its script's turns (data/raid_rules.lua SCRIPTS) instead of a plain move, on all four at once.
--   type     the move's type
--   power    a fixed power (Sword / Shield's 160 for the moves that have one), else nil: the Max Move
--            band of the boss's strongest move of that type (POWER_BANDS), or 130 without one
--   effect   what it does besides its damage, as the sim runs it (src/raid_sim.lua):
--     { kind = "field", turns, frac, spare }   each turn's end every member not of `spare` loses
--                                              1 / frac of its HP (Wildfire, Cannonade, Vine Lash,
--                                              Volcalith)
--     { kind = "trap", turns, frac }           the members hit lose 1 / frac a turn (Centiferno,
--                                              Sandblast)
--     { kind = "status", list }                each member hit takes one of `list` at random
--     { kind = "drowsy", chance }              each member hit falls asleep, chance %, (Snooze's
--                                              drowsiness next turn, on the spot here)
--     { kind = "stages", foe = { stat = n } }  the members' stats
--     { kind = "pp", n }                       each member's moves lose n PP (Depletion: the last
--                                              move's in the game)
--     { kind = "veil", turns }                 the boss's damage taken halved (Aurora Veil)
--     { kind = "heal", frac }                  the boss heals 1 / frac (Finale)
--     { kind = "cure" }                        the boss's status cured (Sweetness)
--     { kind = "crit", n }                     the boss's critical-hit stage up (Chi Strike)
--     nil                                      none in a raid (Stealth Rock / Steelsurge hit a
--                                              Pokemon switching in; Gravity, Torment, no escape,
--                                              infatuation, the Max move's protection pierced)
-- EVIDENCE: Bulbapedia "G-Max Move" and each move's page (effects, the 160-power moves);
-- Serebii "Max Moves" (the power bands). The raid adaptations (the fields hit the party, the
-- confusion and infatuation moves plain) are ours.
local G = {}

-- the Max Move power from the base move's: { up to this power, max power }; Fighting and Poison
-- moves take the lower column (Serebii)
G.POWER_BANDS = {
  { 40, 90, 70 }, { 50, 100, 75 }, { 60, 110, 80 }, { 70, 120, 85 }, { 100, 130, 90 },
  { 140, 140, 95 }, { 9999, 150, 100 },
}

G.MOVES = {
  GOLD_RUSH = { type = "NORMAL" },
  VOLT_CRASH = { type = "ELECTRIC", effect = { kind = "status", list = { "PAR" } } },
  CUDDLE = { type = "NORMAL" },
  BEFUDDLE = { type = "BUG", effect = { kind = "status", list = { "SLP", "PSN", "PAR" } } },
  MALODOR = { type = "POISON", effect = { kind = "status", list = { "PSN" } } },
  FOAM_BURST = { type = "WATER", effect = { kind = "stages", foe = { speed = -2 } } },
  STONESURGE = { type = "WATER" },
  SWEETNESS = { type = "GRASS", effect = { kind = "cure" } },
  TARTNESS = { type = "GRASS", effect = { kind = "stages", foe = { evasion = -1 } } },
  FINALE = { type = "FAIRY", effect = { kind = "heal", frac = 6 } },
  STEELSURGE = { type = "STEEL" },
  MELTDOWN = { type = "STEEL" },
  TERROR = { type = "GHOST" },
  STUN_SHOCK = { type = "ELECTRIC", effect = { kind = "status", list = { "PSN", "PAR" } } },
  SNOOZE = { type = "DARK", effect = { kind = "drowsy", chance = 50 } },
  SMITE = { type = "FAIRY" },
  GRAVITAS = { type = "PSYCHIC" },
  CHI_STRIKE = { type = "FIGHTING", effect = { kind = "crit", n = 1 } },
  VOLCALITH = { type = "ROCK", effect = { kind = "field", turns = 4, frac = 6, spare = "ROCK" } },
  SANDBLAST = { type = "GROUND", effect = { kind = "trap", turns = 4, frac = 8 } },
  VINE_LASH = { type = "GRASS", effect = { kind = "field", turns = 4, frac = 6, spare = "GRASS" } },
  DRUM_SOLO = { type = "GRASS", power = 160 },
  CENTIFERNO = { type = "FIRE", effect = { kind = "trap", turns = 4, frac = 8 } },
  FIREBALL = { type = "FIRE", power = 160 },
  WILDFIRE = { type = "FIRE", effect = { kind = "field", turns = 4, frac = 6, spare = "FIRE" } },
  HYDROSNIPE = { type = "WATER", power = 160 },
  CANNONADE = { type = "WATER", effect = { kind = "field", turns = 4, frac = 6, spare = "WATER" } },
  RESONANCE = { type = "ICE", effect = { kind = "veil", turns = 5 } },
  DEPLETION = { type = "DRAGON", effect = { kind = "pp", n = 2 } },
  REPLENISH = { type = "NORMAL" },
  WIND_RAGE = { type = "FLYING" },
  ONE_BLOW = { type = "DARK" },
  RAPID_FLOW = { type = "WATER" },
  -- Eternatus' own (its Eternamax form's signature, not a G-Max move): Dragon 160
  ETERNABEAM = { type = "DRAGON", power = 160, name = "Eternabeam" },
}

-- the plain Max Moves, by the type of the move they come from (a Dynamax boss's, and a G-Max boss's
-- without a G-Max move of its own): name, and effect as above (+ { kind = "boost", self = { stat = n } }:
-- the boss's own stats). Weather and terrain (Max Flare, Geyser, Hailstorm, Rockfall, Overgrowth,
-- Lightning, Mindstorm, Starfall) do nothing in a raid here: the sim has no weather or terrain.
-- EVIDENCE: Bulbapedia "Max Move" (each move's effect).
G.MAX = {
  NORMAL = { name = "Max Strike", effect = { kind = "stages", foe = { speed = -1 } } },
  FIGHTING = { name = "Max Knuckle", effect = { kind = "boost", self = { attack = 1 } } },
  FLYING = { name = "Max Airstream", effect = { kind = "boost", self = { speed = 1 } } },
  POISON = { name = "Max Ooze", effect = { kind = "boost", self = { spAtk = 1 } } },
  GROUND = { name = "Max Quake", effect = { kind = "boost", self = { spDef = 1 } } },
  ROCK = { name = "Max Rockfall" },
  BUG = { name = "Max Flutterby", effect = { kind = "stages", foe = { spAtk = -1 } } },
  GHOST = { name = "Max Phantasm", effect = { kind = "stages", foe = { defense = -1 } } },
  STEEL = { name = "Max Steelspike", effect = { kind = "boost", self = { defense = 1 } } },
  FIRE = { name = "Max Flare" },
  WATER = { name = "Max Geyser" },
  GRASS = { name = "Max Overgrowth" },
  ELECTRIC = { name = "Max Lightning" },
  PSYCHIC = { name = "Max Mindstorm" },
  ICE = { name = "Max Hailstorm" },
  DRAGON = { name = "Max Wyrmwind", effect = { kind = "stages", foe = { attack = -1 } } },
  DARK = { name = "Max Darkness", effect = { kind = "stages", foe = { spDef = -1 } } },
  FAIRY = { name = "Max Starfall" },
}

-- the words when an effect takes hold (src/raid_sim.lua fills {BOSS} / {MON})
G.WORDS = {
  field = {
    FIRE = "The team was surrounded by fire!", WATER = "The team got caught in a vortex of water!",
    GRASS = "The team got trapped with vines!", ROCK = "The team was surrounded by rocks!",
  },
  fieldHurt = {
    FIRE = "{MON} is burning up within G-Max Wildfire's flames!",
    WATER = "{MON} is hurt by G-Max Cannonade's vortex!",
    GRASS = "{MON} is hurt by G-Max Vine Lash's ferocious beating!",
    ROCK = "{MON} is hurt by the rocks thrown out by G-Max Volcalith!",
  },
  trap = "{MON} became trapped!",
  trapHurt = "{MON} is hurt by the trap!",
  veil = "{BOSS} is protected by a shimmering veil!",
  veilEnd = "{BOSS}'s veil wore off!",
  pp = "The team's moves lost PP!",
  heal = "{BOSS}'s HP was restored!",
  cure = "{BOSS}'s status returned to normal!",
  crit = "{BOSS} is getting pumped!",
  drowsy = "{MON} grew drowsy!",
}

return G
