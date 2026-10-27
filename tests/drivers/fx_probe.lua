-- Driver: the move looks one by one (src/fx.lua), each shot as it comes, as it lands and after.
-- Opens PROBE_BOSS (default CHARIZARD_4), waits for the commands, then plays each case through
-- R.testLook with the camera on whom it falls on. PROBE_ONLY=<name>[,<name>] plays only those.
--   SHOT_DIR=<dir> SHOT_W=1280 SHOT_H=720 POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/fx_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached")
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON", "SPECIES_MUDKIP", "SPECIES_RALTS" }) do
      Party.giveMon(s0, C:require("species", sp), 30)
    end
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids is not loaded"); return end
  local ok, why = X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4")
  log("open:", tostring(ok), tostring(why))
  if not waitFor(function() return X.state().phase == "command" end, 20000) then log("FAIL no commands"); return end
  local R = X.raid
  local Sc = X._test.scene
  local function after(s)
    local t0 = X.state().t or 0
    waitFor(function() return (X.state().t or 0) >= t0 + s end, 8000)
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  -- the cases: name, spec, type, user, onto, gmax
  local ALL = { 1, 2, 3, 4 }
  local CASES = {
    { "beam", { "beam" }, "FIRE", "boss", { 2 } },
    { "slab", { "drop", shape = "slab" }, "ROCK", "boss", ALL, true },
    { "bolt", { "bolt" }, "ELECTRIC", "boss", { 3 } },
    { "wave_water", { "wave", shape = "water" }, "WATER", "boss", ALL },
    { "wave_fire", { "wave", shape = "fire" }, "FIRE", "boss", ALL },
    { "wave_ground", { "wave", shape = "ground" }, "GROUND", "boss", ALL },
    { "wave_light", { "wave", shape = "light" }, "FAIRY", "boss", ALL, true },
    { "wave_wind", { "wave", shape = "wind" }, "FLYING", "boss", ALL },
    { "slash", { "slash" }, "DARK", "boss", { 1 } },
    { "bite", { "bite" }, "DARK", "boss", { 2 } },
    { "shot_ball", { "shot", shape = "ball" }, "GHOST", "boss", { 2 } },
    { "shot_rock", { "shot", shape = "rock", n = 3 }, "ROCK", "boss", { 3 } },
    { "shot_star", { "shot", shape = "star", n = 3 }, "NORMAL", "boss", { 2 } },
    { "spikes", { "spikes" }, "GROUND", "boss", { 2 } },
    { "spikes_steel", { "spikes", shape = "steel" }, "STEEL", "boss", { 3 } },
    { "drop_rock", { "drop", shape = "rock", n = 3 }, "ROCK", "boss", { 1 } },
    { "drop_fist", { "drop", shape = "fist" }, "FIGHTING", "boss", { 2 } },
    { "rings", { "rings", shape = "psychic" }, "PSYCHIC", "boss", { 4 } },
    { "powder", { "powder", shape = "spore" }, "GRASS", "boss", { 2 } },
    { "drain", { "drain" }, "GRASS", "boss", { 2 } },
    { "self", { "self" }, "DRAGON", "boss", {} },
    { "slam", { "slam", shape = "body" }, "NORMAL", "boss", { 2 } },
    { "multi", { "multi", shape = "fist", n = 4 }, "FIGHTING", "boss", { 3 } },
    { "m_beam", { "beam" }, "ICE", 2, { "boss" } },
    { "m_slam", { "slam", shape = "body" }, "FIGHTING", 3, { "boss" } },
    { "m_shot", { "shot", shape = "ball" }, "WATER", 1, { "boss" } },
  }
  local only = {}
  for w in (os.getenv("PROBE_ONLY") or ""):gmatch("[^,]+") do only[w] = true end
  for _, c in ipairs(CASES) do
    if next(only) == nil or only[c[1]] then
      local name, spec, ty, user, onto, gmax = c[1], c[2], c[3], c[4], c[5], c[6]
      -- the camera on whom it falls on (as the raid frames it)
      if type(user) == "number" then Sc.shot("member", 0, user)
      elseif #onto > 1 then Sc.shot("spread", 0)
      elseif onto[1] then Sc.shot("target", 0, onto[1])
      else Sc.shot("boss", 0) end
      local a = R.testLook(spec, ty, user, onto, gmax, 0.35)
      if not a then log("FAIL", name, "did not start"); break end
      local start = a.at - (X.state().t or 0)
      local imp = a.impact or a.len
      log(("case %s: start in %.2f, impact %.2f, length %.2f"):format(name, start, imp, a.len))
      if gmax then after(0.8); shot("fx_" .. name .. "_0charge") end
      after(math.max(0, start - (gmax and 0.8 or 0)) + imp * 0.6)
      shot("fx_" .. name .. "_1before")
      after(imp * 0.4 + 0.04)
      shot("fx_" .. name .. "_2impact")
      after(0.25)
      shot("fx_" .. name .. "_3after")
      local st = X._test.fx and X._test.fx.stats and X._test.fx.stats()
      if st then log(("  parts %d spots %d decals %d"):format(st.parts, st.spots, st.decals)) end
      after(math.max(0.3, a.len - imp - 0.25) + 0.6)
    end
  end
  -- what lasts: each G-Max field round the party, the veil, the barrier (up, hit, broken)
  if next(only) == nil or only.lasting then
    local cur = R.current()
    local Fx = X._test.fx
    Sc.shot("spread", 0)
    for _, f in ipairs({ "FIRE", "WATER", "GRASS", "ROCK" }) do
      cur.fieldShown = f
      after(1.0)
      shot("fx_field_" .. f)
    end
    cur.fieldShown = nil
    Sc.shot("boss", 0)
    cur.boss.veil = 3
    after(0.6)
    shot("fx_veil")
    cur.boss.veil = 0
    Sc.shot("field", 0)
    cur.boss.shieldShown = { left = 5, max = 5 }
    Fx.barrierUp(X.state().t)
    after(0.8)
    shot("fx_barrier")
    Fx.barrierHit(X.state().t)
    cur.boss.shieldShown = { left = 2, max = 5 }
    after(0.2)
    shot("fx_barrier_hit")
    cur.boss.shieldShown = nil
    Fx.barrierBreak(R.placeOf(cur.boss), X.state().t)
    after(0.15)
    shot("fx_barrier_break")
  end
  -- a member fainting: shrinking away, gone; then back in the fight
  if next(only) == nil or only.faint then
    local cur = R.current()
    Sc.shot("spread", 0)
    local m = cur.members[2]
    m.faintT, m.backT = X.state().t, nil
    after(0.25)
    shot("fx_faint_1shrink")
    after(0.6)
    shot("fx_faint_2gone")
    m.backT = X.state().t
    after(0.25)
    shot("fx_faint_3back")
  end
  X.close()
  log("done")
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
