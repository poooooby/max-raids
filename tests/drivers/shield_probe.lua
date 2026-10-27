-- Driver: the boss's barrier, end to end. A 4★ Charizard (barriers at 70% and 30% of its HP) set just
-- above 70%, turns of Fight played for real: every barrier event of the battle (up / hit / break, the
-- segments left), the damage through it against without, the HUD's pills (shieldShown), the barrier
-- wall handed to Fx.setLasting, the sounds (Rd.se), Def / Sp. Def after a break. Shots b*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/shield_probe.lua love .

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
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
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
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 55)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, T = X.raid, X._test
  local Fx = T.fx

  -- what was heard, and what the barrier wall was handed
  local heard = {}
  local realSe = R.se
  R.se = function(id, ...)
    local name = type(id) == "table" and id[1] or id
    heard[#heard + 1] = tostring(name)
    return realSe(id, ...)
  end
  local wallSeen, wallMax = 0, nil
  if Fx and Fx.setLasting then
    local real = Fx.setLasting
    Fx.setLasting = function(field, at, veil, shield, t, ...)
      if shield and shield.left and shield.left > 0 then wallSeen = wallSeen + 1; wallMax = shield.max end
      return real(field, at, veil, shield, t, ...)
    end
  end

  check(X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4"), "the raid opens")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local r = R.current()
  local boss = r.boss
  log(("boss: %s, HP %d, barriers at %s, %d segments"):format(boss.name, boss.mon.maxHp,
    table.concat(boss.shields or {}, " / "), boss.segments or 0))
  check(#(boss.shields or {}) == 2 and (boss.segments or 0) >= 2, "a 4★ boss has two barriers, segments from its defences")
  -- just above 70%
  boss.mon.hp = math.floor(boss.mon.maxHp * 0.72)
  boss.dispHp, boss.dispTarget = boss.mon.hp, boss.mon.hp

  local seen = { up = 0, hit = 0, ["break"] = 0 }
  local lastEvents = nil
  local throughShield, open = {}, {}
  local shots = {}
  local turns, lastPhase = 0, nil
  local deadline = love.timer.getTime() + 240
  while love.timer.getTime() < deadline and X.state().active do
    local cur = R.current()
    if not cur then break end
    -- each turn's events, once: the barrier's, and the damage dealt to the boss with it up or not
    if cur.events and cur.events ~= lastEvents then
      lastEvents = cur.events
      local up = cur.boss.shieldShown ~= nil or (cur.boss.shield ~= nil)
      local inBarrier = false
      for _, e in ipairs(cur.events) do
        if e.kind == "shield" then
          seen[e.step] = seen[e.step] + 1
          log(("  turn %d: barrier %s, %d of %d left"):format(turns, e.step, e.left or 0, e.max or 0))
          if e.step == "hit" then inBarrier = true end
        elseif e.kind == "damage" and e.target == cur.boss then
          if inBarrier then throughShield[#throughShield + 1] = e.amount else open[#open + 1] = e.amount end
          inBarrier = false
        elseif e.kind == "stage" and e.who == cur.boss then
          log(("  turn %d: the boss's %s %+d"):format(turns, tostring(e.stat), e.n or 0))
        end
      end
      local _ = up
    end
    if cur.phase == "command" and lastPhase ~= "command" then
      turns = turns + 1
      local sh = cur.boss.shield
      log(("turn %d: boss HP %d%%, barrier %s, the HUD's pills %s"):format(turns,
        math.floor(100 * cur.boss.mon.hp / cur.boss.mon.maxHp), sh and (sh.left .. "/" .. sh.max) or "none",
        cur.boss.shieldShown and (cur.boss.shieldShown.left .. "/" .. cur.boss.shieldShown.max) or "none"))
      check((sh == nil) == (cur.boss.shieldShown == nil) and (not sh or cur.boss.shieldShown.left == sh.left),
        "turn " .. turns .. ": the pills show the barrier as it stands")
      if sh and not shots.up then shots.up = true; U.wait(20); shot("b01_barrier_up") end
    end
    lastPhase = cur.phase
    -- the moment a hit lands on it, and the break
    if cur.phase == "battle" and cur.boss.shieldShown and cur.boss.shield and cur.boss.shield.left < cur.boss.shield.max
      and not shots.hit then
      shots.hit = true; shot("b02_barrier_hit")
    end
    if seen["break"] > 0 and not shots.brk and cur.phase == "battle" then
      shots.brk = true; U.wait(10); shot("b03_barrier_break")
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      if cur.cmd.menu == "main" then R.choose("fight") else R.choose("move1") end
    end
    if cur.phase == "catch" or cur.phase == "outro" or turns > 9 or seen["break"] >= 2 then break end
    U.wait(2)
  end
  local function avg(t) local s = 0; for _, v in ipairs(t) do s = s + v end; return #t > 0 and s / #t or 0 end
  log(("damage to the boss: %d hits through the barrier, avg %.1f; %d without, avg %.1f"):format(#throughShield,
    avg(throughShield), #open, avg(open)))
  log("sounds:", table.concat(heard, " "))
  local function heardOf(name) for _, h in ipairs(heard) do if h == name then return true end end return false end
  check(seen.up >= 1, "the barrier went up past 70%")
  check(seen.hit >= 1, "hits took segments off it")
  check(seen["break"] >= 1, "it broke")
  check(#throughShield > 0 and avg(throughShield) < avg(open), "a hit through it does less")
  check(wallSeen > 0, "the barrier wall drawn while it stands (Fx.setLasting)")
  check(heardOf("SE_M_BARRIER") and heardOf("SE_ICE_CRACK") and heardOf("SE_ICE_BREAK"), "its sounds: up, hit, break")
  local st = R.current() and R.current().boss and R.current().boss.stages
  log("the boss's stages now: Def", tostring(st and st.defense), "Sp. Def", tostring(st and st.spDef))
  if X.state().active then X.close() end
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
