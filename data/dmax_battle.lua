-- Dynamax in the game's own battles (src/dmax.lua): the Max Moves and G-Max Moves registered as the
-- engine's moves, what each does besides its damage, who may Dynamax, and the rules against a
-- Dynamaxed Pokemon. The moves' power is set at each use from the base move's (src/battle.lua
-- Bt.maxPower); the rows here carry a stand-in.
--   index     the move's number (past the National Dex's 355..777)
--   effect    17 (the cart's EFFECT_ALWAYS_HIT: never misses, but not a target out of reach - Fly,
--             Dig, Dive - as Sword / Shield's Max Moves); Max Guard 111 (EFFECT_PROTECT: Protect's
--             own chain)
--   flags     0: not stopped by Protect (src/dmax.lua deals a quarter through it), no contact, no
--             King's Rock, no Mirror Move
--   label     the move menu's name where the battle's own is too long for its cell
-- EVIDENCE: Bulbapedia "Max Move" / "G-Max Move" (names, effects); Serebii "Dynamax" (3 turns,
-- HP x 1.5 + 0.05 a Dynamax Level, the rules against a Dynamaxed Pokemon).
local D = {}

D.INDEX = 900

-- type name -> the Max Move (in its battle name, Gen 3 capitals); `label` for the move menu
D.MAX = {
  NORMAL = { name = "MAX STRIKE" },
  FIGHTING = { name = "MAX KNUCKLE" },
  FLYING = { name = "MAX AIRSTREAM", label = "MAX AIRSTRM" },
  POISON = { name = "MAX OOZE" },
  GROUND = { name = "MAX QUAKE" },
  ROCK = { name = "MAX ROCKFALL" },
  BUG = { name = "MAX FLUTTERBY", label = "MAX FLUTTER" },
  GHOST = { name = "MAX PHANTASM" },
  STEEL = { name = "MAX STEELSPIKE", label = "MAX STEELSPK" },
  FIRE = { name = "MAX FLARE" },
  WATER = { name = "MAX GEYSER" },
  GRASS = { name = "MAX OVERGROWTH", label = "MAX OVERGRW" },
  ELECTRIC = { name = "MAX LIGHTNING", label = "MAX LIGHTNIN" },
  PSYCHIC = { name = "MAX MINDSTORM", label = "MAX MINDSTRM" },
  ICE = { name = "MAX HAILSTORM", label = "MAX HAILSTRM" },
  DRAGON = { name = "MAX WYRMWIND" },
  DARK = { name = "MAX DARKNESS" },
  FAIRY = { name = "MAX STARFALL" },
}
D.MAX_ORDER = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }

D.GUARD = { name = "MAX GUARD" }

-- G-Max move id (data/raid_gmax.lua MOVES; the National Dex's GMAX) -> its battle name and label
D.GMAX = {
  VINE_LASH = { name = "G-MAX VINE LASH", label = "G-VINE LASH" },
  WILDFIRE = { name = "G-MAX WILDFIRE", label = "G-WILDFIRE" },
  CANNONADE = { name = "G-MAX CANNONADE", label = "G-CANNONADE" },
  BEFUDDLE = { name = "G-MAX BEFUDDLE", label = "G-BEFUDDLE" },
  VOLT_CRASH = { name = "G-MAX VOLT CRASH", label = "G-VOLT CRASH" },
  GOLD_RUSH = { name = "G-MAX GOLD RUSH", label = "G-GOLD RUSH" },
  CHI_STRIKE = { name = "G-MAX CHI STRIKE", label = "G-CHI STRIKE" },
  TERROR = { name = "G-MAX TERROR", label = "G-TERROR" },
  FOAM_BURST = { name = "G-MAX FOAM BURST", label = "G-FOAM BURST" },
  RESONANCE = { name = "G-MAX RESONANCE", label = "G-RESONANCE" },
  CUDDLE = { name = "G-MAX CUDDLE", label = "G-CUDDLE" },
  REPLENISH = { name = "G-MAX REPLENISH", label = "G-REPLENISH" },
  MALODOR = { name = "G-MAX MALODOR", label = "G-MALODOR" },
  MELTDOWN = { name = "G-MAX MELTDOWN", label = "G-MELTDOWN" },
  DRUM_SOLO = { name = "G-MAX DRUM SOLO", label = "G-DRUM SOLO" },
  FIREBALL = { name = "G-MAX FIREBALL", label = "G-FIREBALL" },
  HYDROSNIPE = { name = "G-MAX HYDROSNIPE", label = "G-HYDROSNIPE" },
  WIND_RAGE = { name = "G-MAX WIND RAGE", label = "G-WIND RAGE" },
  GRAVITAS = { name = "G-MAX GRAVITAS", label = "G-GRAVITAS" },
  STONESURGE = { name = "G-MAX STONESURGE", label = "G-STONESURGE" },
  VOLCALITH = { name = "G-MAX VOLCALITH", label = "G-VOLCALITH" },
  TARTNESS = { name = "G-MAX TARTNESS", label = "G-TARTNESS" },
  SWEETNESS = { name = "G-MAX SWEETNESS", label = "G-SWEETNESS" },
  SANDBLAST = { name = "G-MAX SANDBLAST", label = "G-SANDBLAST" },
  STUN_SHOCK = { name = "G-MAX STUN SHOCK", label = "G-STUN SHOCK" },
  CENTIFERNO = { name = "G-MAX CENTIFERNO", label = "G-CENTIFERNO" },
  SMITE = { name = "G-MAX SMITE", label = "G-SMITE" },
  SNOOZE = { name = "G-MAX SNOOZE", label = "G-SNOOZE" },
  FINALE = { name = "G-MAX FINALE", label = "G-FINALE" },
  STEELSURGE = { name = "G-MAX STEELSURGE", label = "G-STEELSURGE" },
  DEPLETION = { name = "G-MAX DEPLETION", label = "G-DEPLETION" },
  ONE_BLOW = { name = "G-MAX ONE BLOW", label = "G-ONE BLOW" },
  RAPID_FLOW = { name = "G-MAX RAPID FLOW", label = "G-RAPID FLOW" },
}
D.GMAX_ORDER = { "VINE_LASH", "WILDFIRE", "CANNONADE", "BEFUDDLE", "VOLT_CRASH", "GOLD_RUSH", "CHI_STRIKE",
  "TERROR", "FOAM_BURST", "RESONANCE", "CUDDLE", "REPLENISH", "MALODOR", "MELTDOWN", "DRUM_SOLO", "FIREBALL",
  "HYDROSNIPE", "WIND_RAGE", "GRAVITAS", "STONESURGE", "VOLCALITH", "TARTNESS", "SWEETNESS", "SANDBLAST",
  "STUN_SHOCK", "CENTIFERNO", "SMITE", "SNOOZE", "FINALE", "STEELSURGE", "DEPLETION", "ONE_BLOW", "RAPID_FLOW" }

-- the plain Max Moves' weather and terrain (the stat changes are data/raid_gmax.lua MAX's): the
-- engine's weather kinds (effects/weather.lua) with the game's own words, the National Dex's terrain
-- kinds (its words src/dmax.lua's); `anim` the cart's own animation of that weather (B_ANIM_*_CONTINUES),
-- played as the Max Move sets it, as the turn's end plays it
D.WEATHER = {
  FIRE = { kind = "SUNNY", text = "STRINGID_SUNLIGHTGOTBRIGHT", anim = "SUN_CONTINUES" },
  WATER = { kind = "RAINY", text = "STRINGID_STARTEDTORAIN", anim = "RAIN_CONTINUES" },
  ROCK = { kind = "SANDSTORM", text = "STRINGID_SANDSTORMBREWED", anim = "SANDSTORM_CONTINUES" },
  ICE = { kind = "HAIL", text = "STRINGID_STARTEDHAIL", anim = "HAIL_CONTINUES" },
}
D.TERRAIN = {
  ELECTRIC = { kind = "ELECTRIC" }, GRASS = { kind = "GRASSY" }, PSYCHIC = { kind = "PSYCHIC" },
  FAIRY = { kind = "MISTY" },
}

-- a G-Max field's look on a Pokemon it hurts, as it starts and each turn as its words show: the cart's
-- trapped-in-a-vortex animation (B_ANIM_TURN_TRAP) of a move of its kind - Fire Spin (83), Whirlpool
-- (250), Sand Tomb (328), Wrap (35) by the field's type; Centiferno and Sandblast bind as those do
D.TRAP_LOOK = { FIRE = 83, WATER = 250, ROCK = 328, GRASS = 35, CENTIFERNO = 83, SANDBLAST = 328 }

-- the option's GYMS & LEAGUE: the trainer classes (the profile's names, TRAINER_CLASS_ left off)
-- where Sword / Shield's Power Spots stand - the Gym Leaders, the Elite Four, the Champion - and the
-- rivals: Emerald's RIVAL (May / Brendan, Wally), FireRed / LeafGreen's RIVAL_EARLY / RIVAL_LATE,
-- Ruby / Sapphire's POKEMON_TRAINER_3 (May / Brendan); the RS_ ones are FireRed's Hoenn classes
D.LEAGUE = {
  LEADER = true, ELITE_FOUR = true, CHAMPION = true,
  RS_LEADER = true, RS_ELITE_FOUR = true, RS_CHAMPION = true,
  RIVAL = true, RIVAL_EARLY = true, RIVAL_LATE = true, POKEMON_TRAINER_3 = true,
}

-- a League trainer's ace's Dynamax Level (HP x2)
D.FOE_LEVEL = 10

-- the battles no one Dynamaxes in, whatever the option (the battle state's flags / kinds)
D.NEVER = { "link", "pokedude", "oldManTutorial", "safari", "ghostBattle", "trainerTower", "eReader",
  "battleTower", "frontierTrainer", "facility", "multi", "towerLinkMulti", "recordedLink" }
D.NEVER_KINDS = { "firstBattle", "tutorial", "multi", "recordedLink", "link" }

-- squashed move ids (lower case letters and digits) that fail against a Dynamaxed Pokemon, and
-- those that strike one twice as hard
D.FAIL_VS_DMAX = {
  lowkick = true, grassknot = true, heatcrash = true, heavyslam = true,
  encore = true, disable = true, torment = true, instruct = true, skillswap = true, entrainment = true,
  roar = true, whirlwind = true,
}
D.ANTI_DMAX = { behemothblade = true, behemothbash = true, dynamaxcannon = true }
-- forced out by these (the Dynamaxed one stays in)
D.DRAG = { dragontail = true, circlethrow = true }
-- Max Guard keeps these off as well (moves that strike through Protect)
D.GUARD_PIERCE = { feint = true, shadowforce = true, phantomforce = true, hyperspacehole = true,
  hyperspacefury = true }

-- the G-Max Moves that ignore the target's abilities (as Sunsteel Strike: WoobleDex's list)
D.MOLD = { "DRUM_SOLO", "FIREBALL", "HYDROSNIPE" }

-- how long it lasts
D.TURNS = 3

return D
