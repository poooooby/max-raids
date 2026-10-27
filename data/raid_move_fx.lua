-- How each move looks in a raid (src/fx.lua plays them): every move the bosses use and their G-Max
-- moves, each acted out from what its in-game description says it does (Wooble 2026-10-26: "the
-- moves for the boss should mirror the description", as the game's Max Rockfall drops a huge slab
-- on the Pokemon). Any other move (the party's) takes its type's default (DEFAULT).
--   { kind, shape?, n?, big? }
--   kind   beam    a stream / ray from the user to the target
--          shot    something hurled at the target (shape: ball, star, coin, leaf, shuriken, apple, rock)
--          drop    something falling from above onto the target (shape: rock, apple, slab, fist, foot,
--                  coin)
--          slam    the user charges in and strikes (shape: body, fist, head, claw, horn, kick)
--          slash   blades / claws raked across the target
--          bite    jaws closing on it
--          bolt    lightning striking from above
--          wave    a wall rolling over the whole party (shape: water, fire, sound, light, wind, ground)
--          rings   rings / waves of power sent at it (shape: psychic, sound, eye, dark)
--          powder  a cloud drifting over it (shape: spore, gas, smoke, sand, heart)
--          self    an aura round the user (a stat raised)
--          drain   orbs drawn out of the target into the user
--          spikes  points erupting from the ground under it
--          multi   n quick strikes in a row
--   n      how many (shots, strikes); big: larger than the move's usual
local F = {}

F.MOVES = {
  ACID_ARMOR = { "self" },                              -- melts into liquid: Defense up
  AERIAL_ACE = { "slash" },                             -- an extremely fast slash
  AGILITY = { "self" },                                 -- relaxes and lightens itself
  AIR_SLASH = { "shot", shape = "blade", n = 3 },       -- blades of air
  ANCIENT_POWER = { "shot", shape = "rock", n = 3 },    -- prehistoric rocks hurled
  APPLE_ACID = { "shot", shape = "apple" },             -- an acidic apple flung
  AQUA_JET = { "slam", shape = "body" },                -- lunges wrapped in water
  BITE = { "bite" },
  BODY_SLAM = { "slam", shape = "body", big = true },   -- drops its whole body on it
  BRAVE_BIRD = { "slam", shape = "body", big = true },  -- tucks its wings and charges
  BUG_BUZZ = { "rings", shape = "sound" },              -- a damaging sound wave
  BULK_UP = { "self" },
  CALM_MIND = { "self" },
  CLOSE_COMBAT = { "multi", shape = "fist", n = 4 },    -- fights up close, no guard
  CONFUSE_RAY = { "rings", shape = "eye" },             -- a sinister ray
  COSMIC_POWER = { "self" },
  CRABHAMMER = { "slam", shape = "claw", big = true },  -- a huge pincer hammered down
  CROSS_CHOP = { "slash" },                             -- a double chop, forearms crossed
  CRUNCH = { "bite", big = true },
  DARK_PULSE = { "rings", shape = "dark" },             -- a horrible aura of dark thoughts
  DAZZLING_GLEAM = { "wave", shape = "light" },         -- a powerful flash
  DOUBLE_IRON_BASH = { "multi", shape = "fist", n = 2 },-- spins, punches twice with its hex nut
  DRAGON_BREATH = { "beam" },                           -- an incredible blast of breath
  DRAGON_PULSE = { "beam", big = true },                -- a shock wave from its open mouth
  DRAINING_KISS = { "drain" },                          -- steals HP with a kiss
  DRILL_PECK = { "slam", shape = "horn" },              -- a corkscrewing beak
  DRILL_RUN = { "slam", shape = "horn" },               -- rotates its body like a drill
  DRUM_BEATING = { "spikes", shape = "root" },          -- its drum sends roots into the target
  DYNAMAX_CANNON = { "beam", big = true },              -- a beam from its core
  DYNAMIC_PUNCH = { "slam", shape = "fist", big = true },
  EARTHQUAKE = { "wave", shape = "ground" },            -- a quake over everything round it
  FALSE_SURRENDER = { "slash" },                        -- bows as if to surrender, then stabs with its hair
  FIRE_LASH = { "slash" },                              -- a whip of fire
  FLAMETHROWER = { "beam" },                            -- an intense blast of fire
  FLASH_CANNON = { "beam" },                            -- all its light energy at once
  GIGA_DRAIN = { "drain" },                             -- a nutrient-draining attack
  GLARE = { "rings", shape = "eye" },                   -- the pattern on its belly
  GRAV_APPLE = { "drop", shape = "apple", big = true }, -- an apple dropped from high above
  GROWTH = { "self" },
  GUST = { "wave", shape = "wind" },                    -- a gust whipped up by its wings
  HAMMER_ARM = { "slam", shape = "fist", big = true },  -- swings its strong, heavy fist down
  HARDEN = { "self" },
  HEAVY_SLAM = { "drop", shape = "body", big = true },  -- slams into it with its heavy body
  HIGH_JUMP_KICK = { "slam", shape = "kick" },          -- leaps up and knees it
  HYDRO_PUMP = { "beam", big = true },                  -- a huge volume of water
  HYPNOSIS = { "rings", shape = "psychic" },            -- hypnotic suggestion
  ICE_BEAM = { "beam" },                                -- an icy-cold beam
  IRON_HEAD = { "slam", shape = "head" },               -- a steel-hard head
  IRON_TAIL = { "slam", shape = "body" },               -- a steel-hard tail
  LEECH_LIFE = { "drain" },                             -- sucks its blood
  LEER = { "rings", shape = "eye" },                    -- an intimidating leer
  METAL_CLAW = { "slash" },                             -- claws like steel
  METAL_SOUND = { "rings", shape = "sound" },           -- a horrible sound like metal scraping
  MYSTICAL_FIRE = { "shot", shape = "ball", n = 3 },    -- special fire from its mouth
  NIGHT_SLASH = { "slash" },                            -- slashes the instant an opening appears
  OVERDRIVE = { "wave", shape = "sound" },              -- twangs a guitar or bass
  PAY_DAY = { "shot", shape = "coin", n = 5 },          -- coins hurled at it
  PLAY_ROUGH = { "multi", shape = "fist", n = 3 },      -- plays rough with it
  POISON_JAB = { "slam", shape = "horn" },              -- a toxic tentacle or arm stabs it
  PSYBEAM = { "beam" },                                 -- a peculiar ray
  PSYCHIC = { "rings", shape = "psychic", big = true }, -- a strong telekinetic force
  PYRO_BALL = { "shot", shape = "ball", big = true },   -- a small stone ignited and kicked
  QUICK_ATTACK = { "slam", shape = "body" },            -- lunges so fast it is almost invisible
  RAZOR_LEAF = { "shot", shape = "leaf", n = 5 },       -- sharp-edged leaves
  ROCK_SLIDE = { "drop", shape = "rock", n = 4 },       -- large boulders hurled down
  SAND_ATTACK = { "powder", shape = "sand" },           -- sand hurled in its face
  SCARY_FACE = { "rings", shape = "eye" },              -- a scary face
  SCREECH = { "rings", shape = "sound" },               -- an earsplitting screech
  SEED_BOMB = { "shot", shape = "ball", n = 3 },        -- a barrage of hard-shelled seeds
  SHADOW_BALL = { "shot", shape = "ball", big = true }, -- a shadowy blob
  SHADOW_SNEAK = { "slam", shape = "body" },            -- extends its shadow and strikes from behind
  SHOCK_WAVE = { "bolt" },                              -- a jolt of electricity that never misses
  SLASH = { "slash" },
  SLEEP_POWDER = { "powder", shape = "spore" },         -- sleep-inducing dust
  SLUDGE_BOMB = { "shot", shape = "ball", n = 2 },      -- unsanitary sludge hurled
  SMOKESCREEN = { "powder", shape = "smoke" },          -- a cloud of smoke or ink
  SNIPE_SHOT = { "beam" },                              -- a shot at it from afar
  SPARK = { "slam", shape = "body" },                   -- an electrically charged tackle
  SPECTRAL_THIEF = { "drain" },                         -- hides in its shadow, steals its boosts
  SPIRIT_BREAK = { "slam", shape = "fist", big = true },-- an overwhelming strike
  STOMP = { "drop", shape = "foot" },                   -- a big foot stomps down
  SUCKER_PUNCH = { "slam", shape = "fist" },            -- strikes first
  SUPERPOWER = { "slam", shape = "body", big = true },  -- all its power, a hefty blow
  SURF = { "wave", shape = "water" },                   -- a big wave crashes down
  SURGING_STRIKES = { "multi", shape = "fist", n = 3 }, -- three flowing water strikes
  SWEET_KISS = { "powder", shape = "heart" },           -- a sweet kiss
  SWIFT = { "shot", shape = "star", n = 5 },            -- star-shaped rays
  TAKE_DOWN = { "slam", shape = "body" },               -- a reckless, full-body charge
  THUNDERBOLT = { "bolt", big = true },                 -- a strong electric blast
  THUNDER_PUNCH = { "slam", shape = "fist" },           -- an electrified punch
  THUNDER_WAVE = { "bolt" },                            -- a weak electric charge
  TOXIC = { "powder", shape = "gas" },                  -- badly poisons it
  VENOSHOCK = { "shot", shape = "ball", n = 2 },        -- a special poisonous liquid
  WATERFALL = { "slam", shape = "body", big = true },   -- charges at it, may flinch
  WATER_SHURIKEN = { "shot", shape = "shuriken", n = 3 }, -- throwing stars of water
  WICKED_BLOW = { "slam", shape = "fist", big = true }, -- a strike mastering the Dark style
  WING_ATTACK = { "slash" },                            -- strikes with wings spread
  WOOD_HAMMER = { "slam", shape = "body", big = true }, -- slams its rugged body
  ZEN_HEADBUTT = { "slam", shape = "head" },            -- focuses its will on its head
}

-- the G-Max moves (data/raid_gmax.lua), from what each does: on the one Pokemon it strikes (a Max
-- Move has one target), larger
F.GMAX = {
  GOLD_RUSH = { "drop", shape = "coin", n = 8 },        -- coins rain on the targets
  VOLT_CRASH = { "bolt", n = 3 },                       -- lightning strikes everyone
  CUDDLE = { "powder", shape = "heart" },               -- a cuddle of affection
  BEFUDDLE = { "powder", shape = "spore" },             -- befuddling scales and spores
  MALODOR = { "powder", shape = "gas" },                -- the reek of garbage poisons them
  FOAM_BURST = { "shot", shape = "ball", n = 6 },       -- a burst of foam
  STONESURGE = { "spikes", shape = "rock" },            -- sharp stones rise round them
  SWEETNESS = { "drop", shape = "apple" },              -- sweet nectar pours down
  TARTNESS = { "powder", shape = "gas" },               -- a tart acid spray
  FINALE = { "rings", shape = "light" },                -- a finale of cream
  STEELSURGE = { "spikes", shape = "steel" },           -- sharp steel spikes rise round them
  MELTDOWN = { "beam" },                                -- molten metal blasted at them
  TERROR = { "rings", shape = "dark" },                 -- shadows that hold them in place
  STUN_SHOCK = { "bolt", n = 3 },                       -- a numbing, poisonous shock
  SNOOZE = { "powder", shape = "spore" },               -- a yawn that makes them drowsy
  SMITE = { "bolt", n = 3 },                            -- a punishing light from above
  GRAVITAS = { "drop", shape = "slab" },                -- gravity crushes them down
  CHI_STRIKE = { "drop", shape = "fist" },              -- a giant fist from the sky
  VOLCALITH = { "drop", shape = "slab" },               -- a slab of rock crashes down (as Max Rockfall)
  SANDBLAST = { "powder", shape = "sand" },             -- a sandstorm traps them
  VINE_LASH = { "slash" },                              -- huge vines lash them
  DRUM_SOLO = { "spikes", shape = "root" },             -- a drum beat sends roots up
  CENTIFERNO = { "beam", big = true },                  -- a vortex of fire traps it
  FIREBALL = { "shot", shape = "ball", n = 1, big = true }, -- a giant fireball kicked
  WILDFIRE = { "beam", big = true },                    -- flames engulf it (then round the team)
  HYDROSNIPE = { "beam" },                              -- a sniper's shot of water
  CANNONADE = { "beam", big = true },                   -- a vortex of water
  RESONANCE = { "rings", shape = "sound" },             -- an aurora's melody
  DEPLETION = { "beam" },                               -- dragon energy saps their PP
  REPLENISH = { "rings", shape = "light" },             -- restoring energy
  WIND_RAGE = { "shot", shape = "blade", n = 4, big = true }, -- a raging wind
  ONE_BLOW = { "slam", shape = "fist", big = true },    -- one fearsome blow
  RAPID_FLOW = { "multi", shape = "fist", n = 4 },      -- a flurry of flowing strikes
  ETERNABEAM = { "beam", big = true },                  -- its full power, a beam
}

-- a move not in the tables: by its type, a strike for the types Gen 3 counts physical, else a
-- shot or beam
F.DEFAULT = {
  NORMAL = { "slam", shape = "body" }, FIGHTING = { "slam", shape = "fist" }, FLYING = { "slash" },
  POISON = { "shot", shape = "ball" }, GROUND = { "spikes", shape = "rock" }, ROCK = { "drop", shape = "rock", n = 3 },
  BUG = { "slam", shape = "horn" }, GHOST = { "shot", shape = "ball" }, STEEL = { "slam", shape = "head" },
  FIRE = { "beam" }, WATER = { "beam" }, GRASS = { "shot", shape = "leaf", n = 4 }, ELECTRIC = { "bolt" },
  PSYCHIC = { "rings", shape = "psychic" }, ICE = { "beam" }, DRAGON = { "beam" }, DARK = { "bite" },
  FAIRY = { "rings", shape = "light" }, MYSTERY = { "slam", shape = "body" },
}

return F
