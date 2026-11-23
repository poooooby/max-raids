-- Driver: the terrains' effect on a raid's damage, through the raid's own adapter (the engine's
-- Damage.calc with WoobleDex's terrain rules; the sim's `field` as it passes it). Mean damage over
-- many rolls on the boss, no crits:
--   Thunderbolt from a grounded member: x1.3 on Electric Terrain, as it is on Grassy
--   Dragon Claw on the (grounded) boss: x0.5 on Misty Terrain
--   Earthquake: as it is on Grassy here (Gen 8's halving is not in WoobleDex's rules)
-- and the sim's own Grassy heal and Psychic priority block (tests/raid_sim_test.lua has the rest).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/terrain_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(960, 640, { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_MANECTRIC", "SPECIES_SALAMENCE", "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end
  s0.party[1].moves = { mv("THUNDERBOLT"), mv("BITE"), mv("QUICK_ATTACK"), mv("ROAR") }
  s0.party[2].moves = { mv("DRAGON_CLAW"), mv("EARTHQUAKE"), mv("FLY"), mv("ROAR") }
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  X.open(os.getenv("PROBE_BOSS") or "SNORLAX_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local cur = R.current()
  local sim, A, boss = cur.sim, cur.adapter, cur.boss
  local m1, m2 = cur.members[1].b, cur.members[2].b
  local nd = game.mods.exports.national_dex_gen3
  check(nd ~= nil and nd.battle ~= nil, "WoobleDex's battle exports (its terrain rules)")

  -- mean damage of `mv` from `att` on the boss over N rolls, the terrain `kind` on the sim's field
  local N = 60
  local function mean(att, mvx, kind)
    local f = sim.ndx
    f.terrain, f.terrainTurns = kind, kind and 5 or nil
    local total, hits = 0, 0
    for _ = 1, N do
      local dmg = A.damage(att, boss, mvx, false, { weather = sim.weather, turn = sim.turnNo, field = sim:ndxField(), noCrit = true })
      if dmg and dmg > 0 then total, hits = total + dmg, hits + 1 end
    end
    f.terrain, f.terrainTurns = nil, nil
    return hits > 0 and total / hits or 0
  end
  local function ratio(att, mvx, kind)
    local base = mean(att, mvx, nil)
    local on = mean(att, mvx, kind)
    log(("  %s on %s: %.1f -> %.1f (x%.2f)"):format(mvx.name, tostring(kind), base, on, base > 0 and on / base or 0))
    return base > 0 and on / base or 0
  end
  local function near(x, want) return math.abs(x - want) < 0.08 end
  local tbolt, bite = m1.moves[1], m1.moves[2]
  local dclaw, quake = m2.moves[1], m2.moves[2]
  check(near(ratio(m1, tbolt, "ELECTRIC"), 1.3), "Electric Terrain: a grounded Electric move x1.3")
  check(near(ratio(m1, tbolt, "GRASSY"), 1.0), "Grassy Terrain: Thunderbolt as it is")
  check(near(ratio(m1, bite, "ELECTRIC"), 1.0), "Electric Terrain: a Dark move as it is")
  check(near(ratio(m2, dclaw, "MISTY"), 0.5), "Misty Terrain: a Dragon move on the grounded boss halved")
  check(near(ratio(m2, dclaw, "PSYCHIC"), 1.0), "Psychic Terrain: Dragon Claw as it is")
  -- (Salamence flies: off the ground, its Dragon move takes no Misty cut... the cut is the target's;
  -- its own typed boost: a Flying type gets no Electric boost - Manectric's Thunderbolt did)
  local m2t1 = m2.type1
  log(("  Salamence's types %s/%s, grounded %s"):format(tostring(m2.type1), tostring(m2.type2), tostring(sim:grounded(m2))))
  check(not sim:grounded(m2), "Salamence is off the ground (Flying)")
  check(sim:grounded(m1) and sim:grounded(boss), "Manectric and the boss are grounded")
  -- the sim's own: Grassy heals a grounded member at the turn's end, Psychic blocks Quick Attack
  local ev = {}
  sim.ndx.terrain, sim.ndx.terrainTurns = "GRASSY", 5
  m1.mon.hp = math.floor(m1.mon.maxHp / 2)
  local hp0 = m1.mon.hp
  sim:endTurn(ev)
  log(("  Grassy Terrain's heal: %d -> %d of %d"):format(hp0, m1.mon.hp, m1.mon.maxHp))
  check(m1.mon.hp > hp0, "Grassy Terrain heals the grounded member at the turn's end")
  sim.ndx.terrain, sim.ndx.terrainTurns = "PSYCHIC", 5
  local hpB = boss.mon.hp
  local ev2 = sim:turn({ { move = 3 }, { move = 2 }, { move = 1 }, { move = 1 } })
  local blocked = false
  for _, e in ipairs(ev2) do if e.text and e.text:find("Psychic Terrain") then blocked = true end end
  check(blocked, "Psychic Terrain: Quick Attack on the grounded boss is blocked")
  log(("%d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
