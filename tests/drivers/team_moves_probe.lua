-- Driver: the team moves in a raid. Party: four with Light Screen / Reflect, Safeguard / Mist, Wide
-- Guard / Protect, Tailwind / Follow Me / Helping Hand / Life Dew; boss PROBE_BOSS (SNORLAX_2).
-- Turn 1: Light Screen, Safeguard, Wide Guard, Tailwind (shots t01..t04 as each goes up, t05 what lasts
-- at the next commands); turn 2: Reflect, Mist, Protect, Follow Me (t06..t09); turn 3: Helping Hand's
-- target menu (t10) on member 1; Life Dew (t11). Logs every side event and the sides' turns left.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/team_moves_probe.lua love .

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
  local Moves = require("src.core.game3.battle.moves")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  local SETS = {
    { "SPECIES_ALAKAZAM", { "LIGHT_SCREEN", "REFLECT", "PSYCHIC", "SURF" } },
    { "SPECIES_BLISSEY", { "SAFEGUARD", "MIST", "WISH" } },
    { "SPECIES_HITMONTOP", { "WIDE_GUARD", "PROTECT", "QUICK_GUARD" } },
    { "SPECIES_TOGEKISS", { "TAILWIND", "FOLLOW_ME", "HELPING_HAND", "LIFE_DEW" } },
  }
  for i, row in ipairs(SETS) do
    local okS, sp = pcall(C.require, C, "species", row[1])
    Party.giveMon(s0, okS and sp or C:require("species", "SPECIES_PIKACHU"), 60)
    local mon = s0.party[i]
    mon.moves, mon.pp, mon.maxPp = {}, {}, {}
    for k, name in ipairs(row[2]) do
      local okM, m = pcall(Moves.get, name)
      if okM and type(m) == "table" then
        mon.moves[k], mon.pp[k], mon.maxPp[k] = m.numId or name, tonumber(m.pp) or 10, tonumber(m.pp) or 10
      else
        log("no move", name)
      end
    end
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R = X.raid
  X.open(os.getenv("PROBE_BOSS") or "SNORLAX_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local cur = R.current()
  for i, m in ipairs(cur.members) do
    local names = {}
    for _, mv in ipairs(m.b.moves) do names[#names + 1] = mv.name .. (mv.team and ("[" .. mv.team.kind .. "]") or "") .. (" t" .. tostring(mv.ref and mv.ref.target)) .. (mv.friendly and "*" or "") end
    log(("member %d %s: %s"):format(i, m.b.name, table.concat(names, ", ")))
  end
  -- a member's move by its name (a target for an ally move)
  local function pickMove(name, target)
    local c = R.current().cmd
    local b = c and c.actor and R.current().members[c.actor].b
    if not b then return false end
    local slot = 1
    for k, mv in ipairs(b.moves) do if mv.name == name then slot = k end end
    R.choose("fight")
    R.choose("move" .. slot)
    if R.current().cmd.menu == "target" then
      if target == "shot" then return true end
      if not target then
        for k, row in ipairs(R.current().cmd.moveList or {}) do
          if row.live ~= false then target = k; break end
        end
      end
      R.choose("move" .. (target or 1))
    end
    return true
  end
  -- play the turn's events, shooting `shots[what]` 0.7 s (the raid's clock) after each side event
  local function playTurn(shots)
    local seen = {}
    local deadline = clock() + 60
    while clock() < deadline do
      local c = R.current()
      if not c then break end
      local e = c.events and c.events[c.evI]
      if e and not seen[e] then
        seen[e] = true
        if e.kind == "damage" and e.who and not e.who.boss and e.target then
          log(("hit %s -> %s %d%s"):format(e.who.name, e.target.name, e.amount or 0, e.target.boss and "" or " (an ally)"))
          if not e.target.boss and shots.friendly then
            local t0 = c.t
            waitFor(function() return R.current().t >= t0 + 0.5 end, 4000)
            shot(shots.friendly)
            shots.friendly = nil
          end
        end
        if e.kind == "side" or e.kind == "guard" then
          log(("event %s %s %s: %s"):format(e.kind, tostring(e.what), tostring(e.up), tostring(e.text)))
          local name = shots[e.what or (e.protect and "protect") or ""]
          if name then
            local t0 = c.t
            waitFor(function() return R.current().t >= t0 + 0.7 end, 4000)
            shot(name)
            shots[e.what or "protect"] = nil
          end
        end
      end
      if c.phase == "command" and not c.say and c.cmd and c.cmd.actor and next(seen) then break end
      if not X.state().active then break end
      U.wait(1)
    end
  end
  local function sides()
    local sd = R.current().sim.sides.team
    return ("light %d reflect %d safeguard %d mist %d tailwind %d"):format(sd.light, sd.reflect, sd.safeguard, sd.mist, sd.tailwind)
  end

  -- turn 1 (Light Screen's target screen: the arrow on all four)
  pickMove("Light Screen", "shot")
  U.wait(20)
  shot("t00_team_pick")
  local arrows = 0
  for _, row in ipairs(R.current().cmd.moveList or {}) do if row.hit then arrows = arrows + 1 end end
  check(R.current().cmd.allPick == "team" and arrows == 4, "Light Screen: the arrow on all four (" .. arrows .. ")")
  R.choose("move1")
  pickMove("Safeguard"); pickMove("Wide Guard"); pickMove("Tailwind")
  playTurn({ light = "t01_light_screen", safeguard = "t02_safeguard", wide = "t03_wide_guard", tailwind = "t04_tailwind" })
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  shot("t05_lasting")
  log("after turn 1:", sides())
  check(R.current().sim.sides.team.light == 4, "Light Screen: four turns left after its first")
  -- turn 2
  pickMove("Reflect"); pickMove("Mist"); pickMove("Protect"); pickMove("Follow Me")
  playTurn({ reflect = "t06_reflect", mist = "t07_mist", protect = "t08_protect", redirect = "t09_follow_me" })
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  log("after turn 2:", sides())
  -- turn 3: Surf's target screen (the arrow on the three allies, the user immune), Helping Hand's
  pickMove("Surf", "shot")
  U.wait(20)
  shot("t14_surf_pick")
  -- the same on the second screen (its display stood in for: the last frame pushed)
  local S2 = X._test.screen2
  local last = nil
  local keep = S2.bridge
  S2.bridge = { detected = function() return true end, available = function() return true end, setEnabled = function() end,
    push = function(data) last = data:clone(); return true end, pollTouch = function() return nil end }
  X._test.padSecond(true)
  U.wait(40)
  if last then
    local f = io.open(dir .. "/t14b_surf_second.png", "wb")
    if f then f:write(last:encode("png"):getString()); f:close() end
    log("frame t14b_surf_second", last:getWidth() .. "x" .. last:getHeight())
  else
    log("FAIL no second-screen frame")
  end
  -- a finger on one of Surf's allies: every one it reaches (the boss too) pressed together
  if X._test.pad and X._test.pad.drawSecond and R.current then
    local c = love.graphics.newCanvas(960, 840, { dpiscale = 1 })
    love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(0, 0, 0, 1)
    X._test.pad.drawSecond(love.graphics, 960, 840, R.current(), "move2")
    love.graphics.setCanvas(); love.graphics.pop()
    local f = io.open(dir .. "/t14c_surf_second_held.png", "wb")
    if f then f:write(c:newImageData():encode("png"):getString()); f:close() end
    log("frame t14c_surf_second_held")
  end
  X._test.padSecond(false)
  S2.bridge = keep
  U.wait(5)
  local hits, userHit = 0, false
  for k, row in ipairs(R.current().cmd.moveList or {}) do
    if row.hit then hits = hits + 1; if k == 1 then userHit = true end end
  end
  check(R.current().cmd.allPick == "spread" and hits == 3 and not userHit, "Surf: the arrow on the three allies, not its user")
  R.choose("move2")
  pickMove("Wish"); pickMove("Quick Guard")
  pickMove("Helping Hand", "shot")
  U.wait(20)
  shot("t10_target")
  check(R.current().cmd.menu == "target", "Helping Hand asks whom")
  local live = {}
  for i, row in ipairs(R.current().cmd.moveList or {}) do live[#live + 1] = ("%d %s %s"):format(i, row.name, tostring(row.live)) end
  log("targets:", table.concat(live, " | "))
  R.choose("move1")
  local hpBefore = {}
  for k, m in ipairs(R.current().members) do hpBefore[k] = m.b.mon.hp end
  playTurn({ help = "t11_helping_hand", wish = "t12_wish", quick = "t13_quick_guard", friendly = "t15_surf_allies" })
  log("Surf turn HP:", hpBefore[2], "->", R.current().members[2].b.mon.hp, "|", hpBefore[3], "->", R.current().members[3].b.mon.hp)
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  -- turn 4: Life Dew
  pickMove("Psychic"); pickMove("Safeguard"); pickMove("Protect"); pickMove("Life Dew")
  playTurn({})
  log("after turn 4:", sides())
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
