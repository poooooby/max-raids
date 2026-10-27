-- Driver: the boss's G-Max move on one target and its plain spread move on all four; the giant's cry
-- pitch (Rd.bigCry), the genders (EEVEE_3: G-Max Cuddle's infatuation), g00 the Dynamax cloud.
-- PROBE_LEVEL the four's level (70). Boss PROBE_BOSS
-- (HATTERENE_2: G-Max Smite, Dazzling Gleam); its moves narrowed to its spread move so each plain turn
-- uses it. Logs every boss move with whom it struck and what followed (statuses, confusion); shoots
-- g01 the spread move landing, g02 the G-Max move landing, g03 the confusion after it.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/gmax_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local clock = love.timer.getTime
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), tonumber(os.getenv("PROBE_LEVEL")) or 70)
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  X.open(os.getenv("PROBE_BOSS") or "HATTERENE_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local boss = R.current().boss
  for i, m in ipairs(R.current().members) do log(("member %d %s: move1 %s"):format(i, m.b.name, m.b.moves[1] and m.b.moves[1].name or "-")) end
  log(("boss %s, G-Max %s (spread %s)"):format(boss.name, boss.gmax and boss.gmax.name or "-", tostring(boss.gmax and boss.gmax.spread)))
  local spreadMove = nil
  for _, mv in ipairs(boss.moves) do
    log(("  %s spread %s"):format(mv.name, tostring(mv.spread)))
    if mv.spread and not mv.status and not spreadMove then spreadMove = mv end
  end
  check(boss.gmax and not boss.gmax.spread, "the G-Max move has one target")
  -- a Dynamax Pokemon's cry: pitched down (the engine's cry Source)
  local Audio = require("src.core.game3.audio")
  R.bigCry(C:require("species", "SPECIES_PIKACHU"))
  local src = Audio._crySource
  log("giant cry pitch:", src and src.getPitch and src:getPitch() or "no source")
  log(("boss gender %s; the four: %s %s %s %s"):format(tostring(boss.gender), R.current().members[1].b.gender,
    R.current().members[2].b.gender, R.current().members[3].b.gender, R.current().members[4].b.gender))
  U.wait(10)
  shot("g00_cloud")
  if spreadMove then boss.moves = { spreadMove } end
  -- PROBE_FORCE_GMAX=1: its G-Max move every turn
  if os.getenv("PROBE_FORCE_GMAX") == "1" and boss.gmax then boss.moves = { boss.gmax } end
  -- Gravity in the engine's damage: a Ground move on a Flying type (Salamence, member 4) is nothing
  -- without it and real with it
  local Bt = X._test.battle
  local ad = R.current().adapter
  local eq = Bt.move("EARTHQUAKE")
  local att, def = R.current().members[3].b, R.current().members[4].b
  if eq and ad then
    local d0, i0 = ad.damage(att, def, eq, false, {})
    local d1, i1 = ad.damage(att, def, eq, false, { gravity = true })
    log(("Earthquake on %s: %s (eff %s); under Gravity %s (eff %s)"):format(def.name, tostring(d0), tostring(i0 and i0.effectiveness),
      tostring(d1), tostring(i1 and i1.effectiveness)))
    check((i0 and i0.effectiveness) == 0 and (i1 and i1.effectiveness or 0) > 0 and (d1 or 0) > 0 and def.type2 == 2,
      "Gravity: the Ground move reaches the Flying type, its types restored")
  end
  local sawSpread, sawGmax = 0, nil
  local shots = { spread = "g01_spread", gmax = "g02_gmax", confused = "g03_confused" }
  for turn = 1, 4 do
    if not X.state().active then break end
    local c = R.current().cmd
    -- (each its first move; a move asking whom - an ally or the whole team - takes the first it can)
    local guard = 0
    while c and c.actor and guard < 20 do
      guard = guard + 1
      R.choose("fight")
      -- (the first move it may use: Torment bars the one it used last)
      local pickN = 1
      for k, row in ipairs(R.current().cmd.moveList or {}) do
        if row.live ~= false then pickN = k; break end
      end
      R.choose("move" .. pickN)
      c = R.current().cmd
      if c and c.menu == "target" then
        for k, row in ipairs(c.moveList or {}) do
          if row.live ~= false then R.choose("move" .. k); break end
        end
        c = R.current().cmd
      end
      U.wait(1)
    end
    local seen, current, struck = {}, nil, {}
    local deadline = clock() + 60
    while clock() < deadline do
      local cr = R.current()
      if not cr then break end
      local e = cr.events and cr.events[cr.evI]
      if e and not seen[e] then
        seen[e] = true
        if e.kind == "use" then
          if current then log(("  %s struck %d: %s"):format(current.name, #struck, table.concat(struck, ", "))) end
          current, struck = e.who.boss and e.move or nil, {}
        elseif current and e.kind == "damage" and e.target and not e.target.boss then
          struck[#struck + 1] = e.target.name
          local key = current.isGmax and "gmax" or "spread"
          if shots[key] then
            local t0 = cr.t
            waitFor(function() return R.current().t >= t0 + 0.35 end, 3000)
            shot(shots[key]); shots[key] = nil
          end
        elseif (e.kind == "status" and e.torment) or (e.kind == "side" and e.what == "gravity") then
          log("  ", e.text)
          if e.what == "gravity" and e.up then
            local t0 = cr.t
            waitFor(function() return R.current().t >= t0 + 0.8 end, 3000)
            shot("g04_gravity")
          end
        elseif e.kind == "status" and e.attract then
          log("  ", e.text)
          if shots.confused then shot(shots.confused); shots.confused = nil end
        elseif e.kind == "status" and e.confused then
          log("  ", e.text)
          if shots.confused then shot(shots.confused); shots.confused = nil end
        elseif e.kind == "status" and e.text then
          log("  ", e.text)
        end
      end
      if cr.phase == "command" and not cr.say and cr.cmd and cr.cmd.actor and next(seen) then break end
      if not X.state().active then break end
      U.wait(1)
    end
    if current then
      log(("  %s struck %d: %s"):format(current.name, #struck, table.concat(struck, ", ")))
      if current.isGmax then sawGmax = #struck elseif current.spread then sawSpread = math.max(sawSpread, #struck) end
    end
    log("turn", turn, "done")
  end
  if spreadMove then check(sawSpread >= 2, "the boss's spread move struck the party (" .. sawSpread .. ")")
  else log("(no spread move on this boss)") end
  if sawGmax ~= nil then check(sawGmax == 1, "the G-Max move struck one (" .. tostring(sawGmax) .. ")")
  else log("(its Max move did not come up)") end
  X.close()
  U.wait(10)
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
