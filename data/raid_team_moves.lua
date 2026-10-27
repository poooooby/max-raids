-- The moves that work on the team in a raid (Sword / Shield's raids are multi battles: the four on one
-- side). Keyed by the move's id squashed (LIGHT_SCREEN -> lightscreen). src/raid_sim.lua runs them;
-- src/battle.lua puts the row on the move (`team`).
--   kind = "screen"    screen = "reflect" | "light" | "veil", turns; a hit on the side the screen
--                      covers (physical / special / both) takes SCREEN_K, not on a critical hit;
--                      needs = "hail" fails without hail (the raid has no weather)
--   kind = "side"      flag = "safeguard" (no major status from the other side) | "mist" (no stat drops
--                      from the other side) | "tailwind" (Speed x2), turns
--   kind = "guard"     guard = "wide" (spread moves) | "quick" (moves of priority over 0) | "mat" (damaging
--                      moves; only on the user's first turn out) | "crafty" (status moves): for the team,
--                      this turn
--   kind = "protect"   the user, this turn; `contact` what touching it costs the attacker: hurt (1 / n of
--                      its max HP), status, stages; damagingOnly: status moves get through
--   kind = "endure"    the user keeps 1 HP this turn
--   kind = "redirect"  the boss's single-target moves fall on the user this turn
--   kind = "help"      an ally's move this turn x1.5 (ally: the player picks whom)
--   kind = "heal"      frac of each healed one's max HP: team (the user and its allies) or ally (one
--                      picked; orFoe - Pollen Puff - may be aimed at the boss instead, an attack); cure:
--                      major status too
--   kind = "cure"      the team's major status cured
--   kind = "wish"      at the end of the next turn the user's place heals frac of the user's max HP
--   kind = "sacrifice" the user faints (Healing Wish / Lunar Dance: no one switches in, and a fainted
--                      member comes back at full HP anyway); the boss's fails
--   kind = "boost"     stages on: team (user and allies), allies (not the user), ally (one picked),
--                      grass (every Grass type on the field, the boss too); ability = only those with one
--   kind = "none"      nothing to do in a raid (Ally Switch: there are no places to swap)
-- Protect-like moves (protect, Max Guard) used in a row succeed 1 in 3^n; a Max or G-Max Move strikes
-- through protect and the turn's guards for a quarter of its damage (Max Guard stops it whole).
-- EVIDENCE: Bulbapedia's pages for each move (Gen 8 effects; doubles: screens 2732 / 4096, Wide Guard,
-- Quick Guard, Mat Block, Crafty Shield; Howl affecting allies from Gen 8; Coaching), Bulbapedia
-- "Max Move" (protection pierced for 1/4) and "Max Raid Battle" (a multi battle). Lucky Chant, Lunar
-- Blessing and Dragon Cheer are not in Sword / Shield and are left out.
local T = {}

T.SCREEN_K = 2732 / 4096
T.MOVES = {
  reflect = { kind = "screen", screen = "reflect", turns = 5 },
  lightscreen = { kind = "screen", screen = "light", turns = 5 },
  auroraveil = { kind = "screen", screen = "veil", turns = 5, needs = "hail" },
  safeguard = { kind = "side", flag = "safeguard", turns = 5 },
  mist = { kind = "side", flag = "mist", turns = 5 },
  tailwind = { kind = "side", flag = "tailwind", turns = 4 },
  wideguard = { kind = "guard", guard = "wide" },
  quickguard = { kind = "guard", guard = "quick" },
  matblock = { kind = "guard", guard = "mat" },
  craftyshield = { kind = "guard", guard = "crafty" },
  protect = { kind = "protect" },
  detect = { kind = "protect" },
  kingsshield = { kind = "protect", damagingOnly = true, contact = { stages = { attack = -1 } } },
  spikyshield = { kind = "protect", contact = { hurt = 8 } },
  banefulbunker = { kind = "protect", contact = { status = "PSN" } },
  obstruct = { kind = "protect", damagingOnly = true, contact = { stages = { defense = -2 } } },
  endure = { kind = "endure" },
  followme = { kind = "redirect" },
  ragepowder = { kind = "redirect" },
  helpinghand = { kind = "help", ally = true },
  lifedew = { kind = "heal", team = true, frac = 0.25 },
  junglehealing = { kind = "heal", team = true, frac = 0.25, cure = true },
  healpulse = { kind = "heal", ally = true, frac = 0.5 },
  floralhealing = { kind = "heal", ally = true, frac = 0.5 },
  pollenpuff = { kind = "heal", ally = true, frac = 0.5, orFoe = true },
  aromatherapy = { kind = "cure" },
  healbell = { kind = "cure" },
  wish = { kind = "wish", frac = 0.5 },
  healingwish = { kind = "sacrifice" },
  lunardance = { kind = "sacrifice" },
  howl = { kind = "boost", team = true, stages = { attack = 1 } },
  coaching = { kind = "boost", allies = true, stages = { attack = 1, defense = 1 } },
  aromaticmist = { kind = "boost", ally = true, stages = { spDef = 1 } },
  decorate = { kind = "boost", ally = true, stages = { attack = 2, spAtk = 2 } },
  gearup = { kind = "boost", team = true, ability = { PLUS = true, MINUS = true }, stages = { attack = 1, spAtk = 1 } },
  magneticflux = { kind = "boost", team = true, ability = { PLUS = true, MINUS = true }, stages = { defense = 1, spDef = 1 } },
  flowershield = { kind = "boost", grass = true, stages = { defense = 1 } },
  allyswitch = { kind = "none" },
}

-- the moves that strike every Pokemon round the user - the boss and the user's allies - in Sword /
-- Shield (its "all adjacent Pokemon"; Gen 3's MOVE_TARGET_FOES_AND_ALLY has only Earthquake, Magnitude,
-- Explosion, Self-Destruct and Teeter Dance: Surf hit only the foes until Gen 4). Bt.move marks them
-- `friendly` with any move whose target is FOES_AND_ALLY. EVIDENCE: Bulbapedia's pages ("may affect
-- all adjacent Pokemon" / "hits all adjacent Pokemon"), Pokemon Showdown's moves (target allAdjacent).
T.FRIENDLY = {
  surf = true, earthquake = true, magnitude = true, explosion = true, selfdestruct = true, teeterdance = true,
  bulldoze = true, discharge = true, lavaplume = true, sludgewave = true, searingshot = true,
  petalblizzard = true, boomburst = true, paraboliccharge = true, sparklingaria = true, mindblown = true,
  brutalswing = true, synchronoise = true, mistyexplosion = true, corrosivegas = true,
}

-- the words
T.WORDS = {
  screenUp = { reflect = "Reflect made {SIDE} stronger against physical moves!",
    light = "Light Screen made {SIDE} stronger against special moves!",
    veil = "Aurora Veil made {SIDE} stronger against physical and special moves!" },
  screenEnd = { reflect = "{SIDE_CAP}'s Reflect wore off!", light = "{SIDE_CAP}'s Light Screen wore off!",
    veil = "{SIDE_CAP}'s Aurora Veil wore off!" },
  sideUp = { safeguard = "{SIDE_CAP} cloaked itself in a mystical veil!", mist = "{SIDE_CAP} became shrouded in mist!",
    tailwind = "The Tailwind blew from behind {SIDE}!" },
  sideEnd = { safeguard = "{SIDE_CAP} is no longer protected by Safeguard!", mist = "{SIDE_CAP} is no longer protected by mist!",
    tailwind = "{SIDE_CAP}'s Tailwind petered out!" },
  guardUp = { wide = "Wide Guard protected the team!", quick = "Quick Guard protected the team!",
    mat = "{MON} intends to flip up a mat and block incoming attacks!", crafty = "Crafty Shield protected the team!" },
  guarded = { wide = "Wide Guard protected {MON}!", quick = "Quick Guard protected {MON}!",
    mat = "{MON} was blocked by the kicked-up mat!", crafty = "Crafty Shield protected {MON}!" },
  protect = "{MON} protected itself!",
  pierced = "{MON} couldn't fully protect itself and got hurt!",
  safeguarded = "{MON} is protected by Safeguard!",
  misted = "{MON} is protected by the mist!",
  endure = "{MON} braced itself!",
  endured = "{MON} endured the hit!",
  redirect = "{MON} became the center of attention!",
  help = "{MON} is ready to help {ALLY}!",
  heal = "{MON}'s HP was restored.",
  cure = "The team's status problems were cured!",
  wish = "{MON} made a wish!",
  wishTrue = "{MON}'s wish came true!",
  sacrifice = "{MON} gave itself up for the team!",
  hurt = "{MON} was hurt!",
  bell = "A bell chimed!",
  aroma = "A soothing aroma wafted through the area!",
  blown = "{SIDE_CAP}'s protections were blown away!",
}

return T
