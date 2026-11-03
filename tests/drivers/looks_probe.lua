-- Driver: the looks a move takes from what it does, in a raid - a multi-hit move landing each hit
-- (Bullet Seed's volley, Double Kick's two strikes, the bar stepping down at each), Fly taking its
-- user off the field for its charging turn and back as it strikes, Swords Dance an aura, Giga Drain
-- its orbs. Member 1: Bullet Seed, Fly, Double Kick, Swords Dance in that order over the turns;
-- member 2: Giga Drain; member 3 Spore (the boss asleep: pixelfx's sleep loop), member 4 Water Gun
-- (its splash). Logs each look, every blow's HP and every pixel art sheet played; shots l*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/looks_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local clock = love.timer.getTime
  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log(ok and "ok  " or "FAIL", what)
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
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
  for _, sp in ipairs({ "SPECIES_BRELOOM", "SPECIES_SHIFTRY", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, Bt, Fx = X.raid, X._test.battle, X._test.fx
  X.open(os.getenv("PROBE_BOSS") or "SNORLAX_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local r = R.current()
  local function movesOf(keys)
    local out = {}
    for _, k in ipairs(keys) do
      local mv = assert(Bt.move(k), k)
      mv.pp, mv.maxPp = 30, 30
      out[#out + 1] = mv
    end
    return out
  end
  local m1, m2 = r.members[1], r.members[2]
  m1.b.moves = movesOf({ "BULLET_SEED", "FLY", "DOUBLE_KICK", "SWORDS_DANCE" })
  m2.b.moves = movesOf({ "GIGA_DRAIN" })
  r.members[3].b.moves = movesOf({ "SPORE" })
  r.members[4].b.moves = movesOf({ "WATER_GUN" })
  -- every pixel art sheet played, by key; a shot at the first of each
  local played, shotSheet = {}, {}
  local realSheet = Fx.sheet
  Fx.sheet = function(key, ...)
    played[key] = (played[key] or 0) + 1
    local e = realSheet(key, ...)
    if e and not shotSheet[key] then shotSheet[key] = R.current().t + 0.25 end
    return e
  end
  -- the boss only stands there, so the turns' order and HP are the team's
  r.boss.moves = movesOf({ "SPLASH" })
  r.boss.script = nil
  -- every blow: whom, its HP then
  local blows = {}
  local realImpact = Fx.onImpact
  Fx.onImpact = function(T, p, ...)
    blows[#blows + 1] = { who = T.b and T.b.name or "?", hp = T.hp }
    return realImpact(T, p, ...)
  end
  local plan = { 1, 2, nil, 3, 4 }
  local turn, lastPhase, seenEv = 0, nil, nil
  local looks, awayMax, awayShot = {}, 0, false
  local deadline = clock() + 200
  while clock() < deadline and X.state().active and turn <= #plan do
    local cur = R.current()
    if not cur then break end
    if cur.phase == "command" and lastPhase ~= "command" then turn = turn + 1 end
    lastPhase = cur.phase
    local e = cur.events and cur.events[cur.evI]
    if e and e ~= seenEv then
      seenEv = e
      if e.kind == "use" and cur.anim then
        local a = cur.anim
        looks[#looks + 1] = { who = e.who.name, move = e.move and e.move.key, kind = a.spec[1], n = a.spec.n,
          last = a.last, blows0 = #blows }
        log(("turn %d: %s %s -> look %s n=%s last=%s"):format(turn, e.who.name, tostring(e.move and e.move.key),
          tostring(a.spec[1]), tostring(a.spec.n), tostring(a.last)))
      elseif e.kind == "hits" then
        log(("turn %d: %s"):format(turn, e.text))
      elseif e.kind == "status" and e.charge then
        log(("turn %d: charge %s semi=%s"):format(turn, e.text, tostring(e.semi)))
      end
    end
    if m1.away then
      local u = R.memberAway(m1)
      if u > awayMax then awayMax = u end
      if u >= 1 and not awayShot then awayShot = true; U.wait(10); shot("l02_flown") end
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      if cur.cmd.menu == "main" then R.choose("fight")
      else
        local pick = cur.cmd.actor == 1 and plan[turn] or 1
        R.choose("move" .. (pick or 1))
      end
    end
    for key, at in pairs(shotSheet) do
      if at ~= true and cur.t >= at then shotSheet[key] = true; shot("l1_" .. key) end
    end
    -- the volley's middle
    if turn == 1 and cur.anim and cur.anim.started and not cur.shotVolley and cur.t > cur.anim.at + 0.25 then
      cur.shotVolley = true
      shot("l01_volley")
    end
    U.wait(1)
  end
  Fx.onImpact = realImpact
  Fx.sheet = realSheet
  local keys = {}
  for k, n in pairs(played) do keys[#keys + 1] = k .. " x" .. n end
  table.sort(keys)
  log("sheets: " .. table.concat(keys, ", "))
  check(played.spark and played.sleep and played.splash, "pixel art: Bullet Seed's sparks, the boss's sleep, Water Gun's splash")
  -- each multi-hit move's look landed every hit, the HP stepping down at each
  local function blowsFor(i)
    local L = looks[i]
    local nextStart = looks[i + 1] and looks[i + 1].blows0 or #blows
    local out = {}
    for k = L.blows0 + 1, nextStart do out[#out + 1] = blows[k] end
    return out
  end
  for i, L in ipairs(looks) do
    local bs = blowsFor(i)
    local hps = {}
    for _, b in ipairs(bs) do hps[#hps + 1] = tostring(b.hp) end
    log(("  %s %s: %d blows, hp %s"):format(L.who, tostring(L.move), #bs, table.concat(hps, " > ")))
    if L.move == "BULLET_SEED" or L.move == "DOUBLE_KICK" then
      local down = #bs >= 2
      for k = 2, #bs do down = down and (tonumber(bs[k].hp) or 0) < (tonumber(bs[k - 1].hp) or 0) end
      check(L.n and L.n >= 2 and #bs == L.n and down, L.move .. ": a blow per hit, the bar lower at each")
    end
    if L.move == "SWORDS_DANCE" then check(L.kind == "self", "Swords Dance: an aura round its user") end
    if L.move == "GIGA_DRAIN" then check(L.kind == "drain", "Giga Drain: its orbs drawn back") end
  end
  check(awayMax >= 1, "Fly: off the field on its charging turn")
  check(not m1.away, "Fly: back once it struck")
  X.close()
  log(fails == 0 and "ALL OK" or ("FAILURES " .. fails))
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
