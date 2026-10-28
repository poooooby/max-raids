-- Dynamax Raids' bosses: the Giga Megas pack's forms (data/raid_sprites.lua, tools/raid_pack.py), and
-- only those. Per pack key:
--   national  the species' National Dex number (its cry falls back to the game's when the pack's
--             is missing; never used to look the boss up in the game - most are not in it)
--   name      shown name (the form's own "Giga X" is the card's subtitle)
--   types     modern types (the pack's where its form sets them, else the species'); a type the
--             game lacks takes the modern chart in raids (data/raid_types.lua)
--   stars     tier, by the Giga BaseStats' total (1★ under 590 .. 5★ from 635)
--   moves     move names, looked up in the game first, else in data/raid_moves.lua (PlayNav's own
--             records of later moves, at their modern type and power)
--   gmax      its G-Max move (data/raid_gmax.lua); nil = a plain Max Move by its moves' types
--   script    the boss's extras (data/raid_rules.lua SCRIPTS)
-- Moves are hand-picked: three attacks of its types and one status move it uses on the party.
return {
  ORDER = {
    "MEOWTH_4", "PIKACHU_18", "EEVEE_3", "BUTTERFREE_2", "GARBODOR_2", "KINGLER_2", "DREDNAW_2",
    "APPLETUN_2", "FLAPPLE_2", "ALCREMIE_64", "CORVIKNIGHT_2", "COPPERAJAH_2", "GENGAR_3",
    "TOXTRICITY_4", "TOXTRICITY_5",
    "GRIMMSNARL_2", "ORBEETLE_2", "MACHAMP_2", "COALOSSAL_2", "HATTERENE_2", "SANDACONDA_2",
    "VENUSAUR_3",
    "CENTISKORCH_2", "GRENINJA_4", "CINDERACE_2", "RILLABOOM_2", "INTELEON_2", "BLASTOISE_3",
    "CHARIZARD_4", "LAPRAS_2",
    "DURALUDON_2", "SNORLAX_2", "URSHIFU_4", "URSHIFU_5", "MARSHADOW_1", "MELMETAL_2", "ETERNATUS_2",
  },
  -- 1★
  MEOWTH_4 = { national = 52, name = "Meowth", types = { "NORMAL" }, stars = 1,
    moves = { "SLASH", "BITE", "PAY_DAY", "SCREECH" }, gmax = "GOLD_RUSH", script = "basic" },
  PIKACHU_18 = { national = 25, name = "Pikachu", types = { "ELECTRIC" }, stars = 1,
    moves = { "THUNDERBOLT", "QUICK_ATTACK", "IRON_TAIL", "THUNDER_WAVE" }, gmax = "VOLT_CRASH", script = "basic" },
  EEVEE_3 = { national = 133, name = "Eevee", types = { "NORMAL" }, stars = 1,
    moves = { "TAKE_DOWN", "BITE", "SWIFT", "SAND_ATTACK" }, gmax = "CUDDLE", script = "basic" },
  BUTTERFREE_2 = { national = 12, name = "Butterfree", types = { "BUG", "FLYING" }, stars = 1,
    moves = { "BUG_BUZZ", "PSYBEAM", "GUST", "SLEEP_POWDER" }, gmax = "BEFUDDLE", script = "basic" },
  GARBODOR_2 = { national = 569, name = "Garbodor", types = { "STEEL", "POISON" }, stars = 1,
    moves = { "SLUDGE_BOMB", "IRON_HEAD", "BODY_SLAM", "TOXIC" }, gmax = "MALODOR", script = "basic" },
  KINGLER_2 = { national = 99, name = "Kingler", types = { "WATER" }, stars = 1,
    moves = { "CRABHAMMER", "METAL_CLAW", "STOMP", "HARDEN" }, gmax = "FOAM_BURST", script = "basic" },
  DREDNAW_2 = { national = 834, name = "Drednaw", types = { "WATER", "ROCK" }, stars = 1,
    moves = { "ROCK_SLIDE", "WATERFALL", "CRUNCH", "BODY_SLAM" }, gmax = "STONESURGE", script = "basic" },
  -- 2★
  APPLETUN_2 = { national = 842, name = "Appletun", types = { "GRASS", "DRAGON" }, stars = 2,
    moves = { "APPLE_ACID", "DRAGON_PULSE", "GIGA_DRAIN", "GROWTH" }, gmax = "SWEETNESS", script = "strong" },
  FLAPPLE_2 = { national = 841, name = "Flapple", types = { "GRASS", "DRAGON" }, stars = 2,
    moves = { "GRAV_APPLE", "DRAGON_BREATH", "WING_ATTACK", "GROWTH" }, gmax = "TARTNESS", script = "strong" },
  ALCREMIE_64 = { national = 869, name = "Alcremie", types = { "FAIRY" }, stars = 2,
    moves = { "DAZZLING_GLEAM", "DRAINING_KISS", "PSYCHIC", "SWEET_KISS" }, gmax = "FINALE", script = "strong" },
  CORVIKNIGHT_2 = { national = 823, name = "Corviknight", types = { "FLYING", "STEEL" }, stars = 2,
    moves = { "BRAVE_BIRD", "IRON_HEAD", "DRILL_PECK", "SCARY_FACE" }, gmax = "WIND_RAGE", script = "strong" },
  COPPERAJAH_2 = { national = 879, name = "Copperajah", types = { "WATER", "STEEL" }, stars = 2,
    moves = { "HEAVY_SLAM", "PLAY_ROUGH", "SUPERPOWER", "STOMP" }, gmax = "STEELSURGE", script = "strong" },
  GENGAR_3 = { national = 94, name = "Gengar", types = { "GHOST", "POISON" }, stars = 2,
    moves = { "SHADOW_BALL", "SLUDGE_BOMB", "DARK_PULSE", "HYPNOSIS" }, gmax = "TERROR", script = "strong" },
  TOXTRICITY_4 = { national = 849, name = "Toxtricity", types = { "ELECTRIC", "POISON" }, stars = 2,
    moves = { "OVERDRIVE", "POISON_JAB", "SPARK", "LEER" }, gmax = "STUN_SHOCK", script = "strong" },
  TOXTRICITY_5 = { national = 849, name = "Toxtricity", types = { "ELECTRIC", "POISON" }, stars = 2,
    moves = { "OVERDRIVE", "VENOSHOCK", "SHOCK_WAVE", "TOXIC" }, gmax = "STUN_SHOCK", script = "strong" },
  -- 3★
  GRIMMSNARL_2 = { national = 861, name = "Grimmsnarl", types = { "DARK", "FAIRY" }, stars = 3,
    moves = { "SPIRIT_BREAK", "FALSE_SURRENDER", "HAMMER_ARM", "BULK_UP" }, gmax = "SNOOZE", script = "strong" },
  ORBEETLE_2 = { national = 826, name = "Orbeetle", types = { "BUG", "PSYCHIC" }, stars = 3,
    moves = { "PSYCHIC", "BUG_BUZZ", "PSYBEAM", "AGILITY" }, gmax = "GRAVITAS", script = "strong" },
  MACHAMP_2 = { national = 68, name = "Machamp", types = { "FIGHTING" }, stars = 3,
    moves = { "CROSS_CHOP", "DYNAMIC_PUNCH", "ROCK_SLIDE", "BULK_UP" }, gmax = "CHI_STRIKE", script = "strong" },
  COALOSSAL_2 = { national = 839, name = "Coalossal", types = { "ROCK", "FIRE" }, stars = 3,
    moves = { "FLAMETHROWER", "ROCK_SLIDE", "ANCIENT_POWER", "SMOKESCREEN" }, gmax = "VOLCALITH", script = "strong" },
  HATTERENE_2 = { national = 858, name = "Hatterene", types = { "PSYCHIC", "FAIRY" }, stars = 3,
    moves = { "PSYCHIC", "DAZZLING_GLEAM", "MYSTICAL_FIRE", "CALM_MIND" }, gmax = "SMITE", script = "strong" },
  SANDACONDA_2 = { national = 844, name = "Sandaconda", types = { "GROUND", "FLYING" }, stars = 3,
    moves = { "EARTHQUAKE", "DRILL_RUN", "ROCK_SLIDE", "GLARE" }, gmax = "SANDBLAST", script = "strong" },
  VENUSAUR_3 = { national = 3, name = "Venusaur", types = { "GRASS", "POISON" }, stars = 3,
    moves = { "RAZOR_LEAF", "SLUDGE_BOMB", "BODY_SLAM", "SLEEP_POWDER" }, gmax = "VINE_LASH", script = "strong" },
  -- 4★
  CENTISKORCH_2 = { national = 851, name = "Centiskorch", types = { "FIRE", "BUG" }, stars = 4,
    moves = { "FIRE_LASH", "LEECH_LIFE", "CRUNCH", "FLAMETHROWER" }, gmax = "CENTIFERNO", script = "fierce" },
  GRENINJA_4 = { national = 658, name = "Greninja", types = { "WATER", "DARK" }, stars = 4,
    moves = { "WATER_SHURIKEN", "DARK_PULSE", "NIGHT_SLASH", "AERIAL_ACE" }, script = "fierce" },
  CINDERACE_2 = { national = 815, name = "Cinderace", types = { "FIRE" }, stars = 4,
    moves = { "PYRO_BALL", "HIGH_JUMP_KICK", "ZEN_HEADBUTT", "AGILITY" }, gmax = "FIREBALL", script = "fierce" },
  RILLABOOM_2 = { national = 812, name = "Rillaboom", types = { "GRASS" }, stars = 4,
    moves = { "DRUM_BEATING", "WOOD_HAMMER", "BODY_SLAM", "GROWTH" }, gmax = "DRUM_SOLO", script = "fierce" },
  INTELEON_2 = { national = 818, name = "Inteleon", types = { "WATER" }, stars = 4,
    moves = { "SNIPE_SHOT", "ICE_BEAM", "AIR_SLASH", "AGILITY" }, gmax = "HYDROSNIPE", script = "fierce" },
  BLASTOISE_3 = { national = 9, name = "Blastoise", types = { "WATER" }, stars = 4,
    moves = { "HYDRO_PUMP", "ICE_BEAM", "FLASH_CANNON", "BITE" }, gmax = "CANNONADE", script = "fierce" },
  CHARIZARD_4 = { national = 6, name = "Charizard", types = { "FIRE", "FLYING" }, stars = 4,
    moves = { "FLAMETHROWER", "AIR_SLASH", "DRAGON_PULSE", "SCARY_FACE" }, gmax = "WILDFIRE", script = "fierce" },
  LAPRAS_2 = { national = 131, name = "Lapras", types = { "WATER", "ICE" }, stars = 4,
    moves = { "SURF", "ICE_BEAM", "BODY_SLAM", "CONFUSE_RAY" }, gmax = "RESONANCE", script = "fierce" },
  -- 5★
  DURALUDON_2 = { national = 884, name = "Duraludon", types = { "STEEL", "DRAGON" }, stars = 5,
    moves = { "FLASH_CANNON", "DRAGON_PULSE", "THUNDERBOLT", "METAL_SOUND" }, gmax = "DEPLETION", script = "fierce" },
  SNORLAX_2 = { national = 143, name = "Snorlax", types = { "NORMAL", "GRASS" }, stars = 5,
    moves = { "BODY_SLAM", "HEAVY_SLAM", "SEED_BOMB", "CRUNCH" }, gmax = "REPLENISH", script = "fierce" },
  URSHIFU_4 = { national = 892, name = "Urshifu", types = { "FIGHTING", "DARK" }, stars = 5,
    moves = { "WICKED_BLOW", "CLOSE_COMBAT", "SUCKER_PUNCH", "BULK_UP" }, gmax = "ONE_BLOW", script = "fierce" },
  URSHIFU_5 = { national = 892, name = "Urshifu", types = { "FIGHTING", "WATER" }, stars = 5,
    moves = { "SURGING_STRIKES", "CLOSE_COMBAT", "AQUA_JET", "BULK_UP" }, gmax = "RAPID_FLOW", script = "fierce" },
  MARSHADOW_1 = { national = 802, name = "Marshadow", types = { "FIGHTING", "GHOST" }, stars = 5,
    moves = { "SPECTRAL_THIEF", "CLOSE_COMBAT", "SHADOW_SNEAK", "BULK_UP" }, script = "fierce" },
  MELMETAL_2 = { national = 809, name = "Melmetal", types = { "STEEL" }, stars = 5,
    moves = { "DOUBLE_IRON_BASH", "THUNDER_PUNCH", "SUPERPOWER", "ACID_ARMOR" }, gmax = "MELTDOWN", script = "fierce" },
  ETERNATUS_2 = { national = 890, name = "Eternatus", types = { "POISON", "DRAGON" }, stars = 5,
    moves = { "DYNAMAX_CANNON", "SLUDGE_BOMB", "FLAMETHROWER", "COSMIC_POWER" }, gmax = "ETERNABEAM", script = "fierce" },
}
