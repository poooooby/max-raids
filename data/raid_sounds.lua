-- The raid's sounds: Gen 3's own effects (the engine's SE ids, src/core/game3/se_ids.lua), played
-- through Audio.playSe, so they follow the game's sound settings and pack.
--   MOVE      a move's look as it starts: by kind, its shape, its type (S.moveSe picks)
--   HIT       a blow landing, by how it does (the battle's own three)
--   EVENT     the battle's events (src/raid_sim.lua's kinds)
--   CATCH     the throw's moments, as the engine's catch plays them (battle/catch_seq.lua)
--   UI        the menus
local S = {}

S.KIND = {
  beam = "SE_M_HYPER_BEAM", shot = "SE_M_SWIFT", drop = "SE_M_ROCK_THROW", slam = "SE_M_TAKE_DOWN",
  slash = "SE_M_CUT", bite = "SE_M_BITE", bolt = "SE_M_THUNDERBOLT", wave = "SE_M_SURF", rings = "SE_M_PSYBEAM",
  powder = "SE_M_POISON_POWDER", self = "SE_M_STAT_INCREASE", drain = "SE_M_GIGA_DRAIN", spikes = "SE_M_EARTHQUAKE",
  multi = "SE_M_COMET_PUNCH",
}
S.SHAPE = {
  water = "SE_M_SURF", fire = "SE_M_HEAT_WAVE", ground = "SE_M_EARTHQUAKE", wind = "SE_M_GUST",
  sound = "SE_M_UPROAR", light = "SE_M_MOONLIGHT", eye = "SE_M_CONFUSE_RAY", psychic = "SE_M_PSYBEAM",
  dark = "SE_M_FAINT_ATTACK", spore = "SE_M_POISON_POWDER", gas = "SE_M_TOXIC", smoke = "SE_M_HAZE",
  sand = "SE_M_SAND_ATTACK", heart = "SE_M_ATTRACT", fist = "SE_M_MEGA_KICK", kick = "SE_M_JUMP_KICK",
  foot = "SE_M_MEGA_KICK", body = "SE_M_TAKE_DOWN", head = "SE_M_HEADBUTT", horn = "SE_M_HORN_ATTACK",
  claw = "SE_M_SCRATCH", leaf = "SE_M_RAZOR_WIND", coin = "SE_M_PAY_DAY", star = "SE_M_SWIFT",
  rock = "SE_M_ROCK_THROW", blade = "SE_M_RAZOR_WIND", apple = "SE_M_ROCK_THROW", steel = "SE_M_HARDEN",
  root = "SE_M_BIND", shuriken = "SE_M_BUBBLE", slab = "SE_M_ROCK_THROW",
}
-- a beam's and a plain shot's sound by its type
S.BEAM = {
  FIRE = "SE_M_FLAMETHROWER", WATER = "SE_M_HYDRO_PUMP", ICE = "SE_M_BLIZZARD", GRASS = "SE_M_SOLAR_BEAM",
  ELECTRIC = "SE_M_THUNDERBOLT", PSYCHIC = "SE_M_PSYBEAM", DRAGON = "SE_M_DRAGON_RAGE", POISON = "SE_M_TOXIC",
  BUG = "SE_M_STRING_SHOT", DARK = "SE_M_FAINT_ATTACK", GHOST = "SE_M_NIGHTMARE",
}
S.SHOT = {
  FIRE = "SE_M_EMBER", WATER = "SE_M_BUBBLE_BEAM", ICE = "SE_M_ICY_WIND", GRASS = "SE_M_RAZOR_WIND",
  ELECTRIC = "SE_M_THUNDER_WAVE", GHOST = "SE_M_NIGHTMARE", POISON = "SE_M_TOXIC", PSYCHIC = "SE_M_PSYBEAM2",
  DARK = "SE_M_FAINT_ATTACK", FAIRY = "SE_M_MOONLIGHT",
}
-- what lands hard has its own sound over the hit's
S.LAND = { slab = "SE_M_EARTHQUAKE", drop = "SE_M_STRENGTH", spikes = "SE_M_EARTHQUAKE" }
S.GMAX_CHARGE = "SE_M_CHARGE"

S.HIT = { super = "SE_SUPER_EFFECTIVE", plain = "SE_EFFECTIVE", weak = "SE_NOT_EFFECTIVE" }

S.EVENT = {
  faint = "SE_FAINT", back = "SE_BALL_OPEN", item = "SE_USE_ITEM", heal = "SE_M_MILK_DRINK",
  cheer = "SE_M_ENCORE", up = "SE_M_STAT_INCREASE", down = "SE_M_STAT_DECREASE",
  shieldUp = "SE_M_BARRIER", shieldHit = "SE_ICE_CRACK", shieldBreak = "SE_ICE_BREAK",
}
S.STATUS = { BRN = "SE_M_EMBER", PSN = "SE_M_TOXIC", TOX = "SE_M_TOXIC", PAR = "SE_M_THUNDER_WAVE",
  SLP = "SE_M_YAWN", FRZ = "SE_M_ICY_WIND" }
S.FIELD = { FIRE = "SE_M_FLAME_WHEEL", WATER = "SE_M_WHIRLPOOL", GRASS = "SE_M_BIND", ROCK = "SE_M_ROCK_THROW" }

S.CATCH = {
  -- (a list: the first this game has - FireRed's SE_BALL_CLICK is SE_RG_BALL_CLICK in Emerald)
  throw = "SE_BALL_THROW", open = "SE_BALL_OPEN", suck = "SE_BALL_TRADE",
  close = { "SE_BALL_CLICK", "SE_RG_BALL_CLICK", "SE_BALL" },
  land = "SE_M_EARTHQUAKE", bounce = "SE_BALL_BOUNCE_1", wobble = "SE_BALL",
  click = { "SE_BALL_CLICK", "SE_RG_BALL_CLICK", "SE_BALL" },
  burst = "SE_BALL_OPEN", gone = "SE_FLEE",
}
S.UI = { move = "SE_SELECT", pick = "SE_SELECT" }

-- the sound for a move's look: spec = data/raid_move_fx.lua's { kind, shape }, typeName its type
function S.moveSe(spec, typeName)
  local kind, shape = spec[1], spec.shape
  if kind == "drop" and shape == "slab" then return S.SHAPE.slab end
  if kind == "beam" then return S.BEAM[typeName or ""] or S.KIND.beam end
  if kind == "shot" and (shape == nil or shape == "ball") then return S.SHOT[typeName or ""] or S.KIND.shot end
  return (shape and S.SHAPE[shape]) or S.KIND[kind] or "SE_EFFECTIVE"
end

return S
