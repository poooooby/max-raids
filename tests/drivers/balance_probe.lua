-- Driver: raid balance. A strong team - Lv PROBE_LEVEL (default 70), fully evolved (Blaziken, Swampert,
-- Sceptile, Gardevoir), IVs 31, 252-EV spreads - plays whole raids against PROBE_BOSSES (default a 4★
-- and three 5★), PROBE_RUNS each (default 3), every member using its strongest move with PP left.
-- Logs each raid's outcome, its turns, the knock-outs and the boss's HP left. The raid's clock runs
-- fast (Rd.SPEED) and the words are hurried.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/balance_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached")
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  local level = tonumber(os.getenv("PROBE_LEVEL")) or 70
  -- the team: species, EVs
  local TEAM = {
    { "SPECIES_BLAZIKEN", { atk = 252, spa = 252, hp = 6 } },
    { "SPECIES_SWAMPERT", { hp = 252, atk = 252, spa = 6 } },
    { "SPECIES_SCEPTILE", { spa = 252, spe = 252, hp = 6 } },
    { "SPECIES_GARDEVOIR", { spa = 252, spe = 252, hp = 6 } },
  }
  s0.party = {}
  for _, row in ipairs(TEAM) do
    Party.giveMon(s0, C:require("species", row[1]), level)
    local mon = s0.party[#s0.party]
    mon.ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
    mon.evs = { hp = row[2].hp or 0, atk = row[2].atk or 0, def = row[2].def or 0, spe = row[2].spe or 0,
      spa = row[2].spa or 0, spd = row[2].spd or 0 }
    mon.hp = nil
    Pokemon.applyStats(mon)
    mon.hp = mon.maxHp
    local names = {}
    for _, mv in ipairs(mon.moves or {}) do names[#names + 1] = tostring(type(mv) == "table" and (mv.id or mv.name) or mv) end
    log(("team: %s Lv %d  HP %d Atk %d Def %d SpA %d SpD %d Spe %d  moves %s"):format(row[1], level, mon.maxHp,
      mon.attack, mon.defense, mon.spAtk, mon.spDef, mon.speed, table.concat(names, ",")))
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R = X.raid
  R.SPEED = tonumber(os.getenv("PROBE_SPEED")) or 8
  local bosses = {}
  for w in (os.getenv("PROBE_BOSSES") or "CHARIZARD_4,DURALUDON_2,SNORLAX_2,URSHIFU_4"):gmatch("[^,]+") do bosses[#bosses + 1] = w end
  local runs = tonumber(os.getenv("PROBE_RUNS")) or 3
  local summary = {}
  for _, key in ipairs(bosses) do
    local wins = 0
    for run = 1, runs do
      -- (the team back to full between raids: they fight as copies, but to be sure)
      for _, mon in ipairs(s0.party) do mon.hp = mon.maxHp; mon.status = nil end
      local ok, why = X.open(key)
      if not ok then log("FAIL open", key, tostring(why)); break end
      local cur = R.current()
      local b = cur.boss
      local bossLine = ("%s Lv %d HP %d"):format(key, b.mon.level or 0, b.mon.maxHp or 0)
      waitFor(function() return X.state().phase == "command" end, 20000)
      if run == 1 then
        -- the team as the den draws it (big sprites whole, heads and all)
        local Sc = X._test.scene
        if Sc then Sc.shot("field", 0) end
        U.wait(20)
        for i, m in ipairs(R.current().members) do
          local d = m.draw or {}
          local qx, qy, qw, qh = 0, 0, 0, 0
          if d.quad then qx, qy, qw, qh = d.quad:getViewport() end
          log(("member %d: hd tag %s, picture %dx%d, cell %s, opaque box %s"):format(i, tostring(d.hd), qw, qh,
            tostring(d.cell), d.box and table.concat({ math.floor(d.box[1]), math.floor(d.box[2]), math.floor(d.box[3]),
            math.floor(d.box[4]) }, ",") or "?"))
        end
        U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/max_raids") .. "/team_" .. key .. ".png")
        for i = 1, 4 do
          if Sc then Sc.shot("member", 0, i) end
          U.wait(10)
          U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/max_raids") .. "/team_" .. key .. "_m" .. i .. ".png")
        end
      end
      local turns, outcome, hpLeft, faints = 0, nil, nil, 0
      local guard = 0
      while X.state().active and guard < 200000 do
        guard = guard + 1
        local ph = X.state().phase
        local c = R.current()
        if ph == "command" then
          local m = c.members[c.cmd.actor]
          -- its strongest move with PP left (by power; a status move only if nothing else)
          local slot, best = 1, -1
          for k, mv in ipairs(m.b.moves) do
            local pw = tonumber(mv.power) or 0
            if (mv.pp or 0) > 0 and pw > best then slot, best = k, pw end
          end
          R.choose("fight"); R.choose("move" .. slot)
          if X.state().phase == "battle" then turns = turns + 1 end
        elseif ph == "battle" then
          R.playEvents(true)
          U.wait(1)
        elseif ph == "catch" or ph == "throw" or ph == "rewards" or ph == "outro" or ph == "after" then
          outcome = "win"
          break
        else
          U.wait(1)
        end
        if c and c.sim then
          hpLeft = c.boss.mon.hp / math.max(1, c.boss.mon.maxHp)
          faints = c.sim.faints or faints
          if c.sim.over then outcome = outcome or c.sim.over end
        end
      end
      if outcome == "win" then wins = wins + 1 end
      log(("%s run %d: %s in %d turns, %d knock-outs, boss HP left %d%%"):format(bossLine, run, tostring(outcome or "?"),
        turns, faints, math.floor((hpLeft or 0) * 100 + 0.5)))
      if X.state().active then X.close() end
      U.wait(10)
    end
    summary[#summary + 1] = ("%s: %d of %d won"):format(key, wins, runs)
  end
  for _, line in ipairs(summary) do log("SUMMARY", line) end
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
