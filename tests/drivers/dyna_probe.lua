-- Driver: the red dens' Dynamax Pokemon. On a route (PROBE_ROUTE, Route 104 / Route 2 by default):
-- the map's id, Modern Spawns on or off, the route's species (src/dyna.lua routeSpecies) and picks at
-- each star; the dens rolled there (purple / red); then a Dynamax raid (PROBE_KEY, else a 3-star
-- pick): the den screen's silhouette, the intro, a Max Move. Shots y*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dyna_probe.lua love .

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
  local function secs(s) local t0 = clock(); while clock() - t0 < s do U.wait(1) end end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(90)
  require("src.core.game3.encounters").onStep = function() return nil end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 40)
  end
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not (X and X._test.dyna and X.dens) then log("FAIL max_raids / its Dynamax dens not loaded"); return end
  local Dy, Dn, R = X._test.dyna, X.dens, X.raid
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end

  -- the route
  local want = os.getenv("PROBE_ROUTE")
  local route
  for id in pairs(game.data and game.data.maps or {}) do
    if type(id) == "string" and not id:find("UNDERWATER") then
      if want and id == want then route = id
      elseif not want and (id:match("ROUTE_?104$") or id:match("ROUTE_?2$")) and not route then route = id end
    end
  end
  local def = game.data.maps[route]
  local Field = require("src.core.game3.field")
  pcall(Map.load, Field._mod, Field._game or game, route, { x = math.floor(def.width / 2), y = math.floor(def.height / 2), facing = "down" })
  Player.cellX, Player.cellY = math.floor(def.width / 2), math.floor(def.height / 2)
  U.wait(30)
  local ms = game.mods.exports.modern_spawns
  local msOn = ms and ms.isActive and ms.isActive()
  log(("map %s (current %s); Modern Spawns %s%s"):format(tostring(route), tostring(Map.current),
    ms and "installed" or "absent", msOn and (", on, " .. tostring(ms.spawnMode and ms.spawnMode())) or ", off"))
  local list = Dy.routeSpecies(Map.current)
  local names = {}
  for _, slot in ipairs(list) do names[#names + 1] = tostring(Dy.idOf(slot) or slot) end
  log(("route species (%d): %s"):format(#list, table.concat(names, ", ")))
  check(#list > 0, "the route has wild Pokemon")
  local rng = Dn.rng(12345)
  local pick3
  for stars = 1, 5 do
    local row = {}
    for _ = 1, 6 do
      local key = Dy.pick(Map.current, stars, rng)
      local b = key and X._test.dyna.record(key)
      row[#row + 1] = b and (Dy.parse(key)) or ("unresolved " .. tostring(key))
      if stars == 3 and not pick3 then pick3 = key end
    end
    log(("  %d stars: %s"):format(stars, table.concat(row, ", ")))
  end

  -- the dens here, rolled today
  local was = Dn.awake()
  Dn.setAwake(true)
  waitFor(function() return Dn.forMap(Map.current) ~= nil end, 600)
  for i, den in ipairs(Dn.forMap(Map.current) or {}) do
    log(("den %d: %s, %s stars, %s beam, boss %s"):format(i, den.active and "active" or "quiet", tostring(den.stars),
      den.rare and "purple" or "red", tostring(den.boss)))
  end
  Dn.setAwake(was)

  -- a Dynamax raid
  local key = os.getenv("PROBE_KEY") or pick3
  log("raid", tostring(key))
  check(key ~= nil, "a Dynamax boss to fight")
  if not key then return end
  local _, stars = Dy.parse(key)
  check(R.openDen({ active = true, boss = key, stars = stars, rare = false, x = 0, y = 0 }), "the den screen opens")
  secs(0.6)
  shot("y1_den")
  R.denStart()
  waitFor(function() local c = R.current(); return c and c.phase == "intro" end, 6000)
  secs(1.6)
  shot("y2_intro")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  shot("y3_command")
  local cur = R.current()
  local boss = cur and cur.boss
  do
    local rec = X._test.dyna.record(key)
    local t = Pokemon.types(rec and rec.slot)
    log(("record: slot %s, national %s, engine types %s/%s, name %s"):format(tostring(rec and rec.slot),
      tostring(rec and rec.national), tostring(t[1]), tostring(t[2]), tostring(rec and rec.name)))
    local nd = game.mods.exports.national_dex_gen3
    if nd and os.getenv("PROBE_IDS") then
      for _, q in ipairs({ "RATICATE", "RATICATE_ALOLA", "RATTATA" }) do
        local s = nd.slotOf(q)
        log(("  dex slotOf(%s) = %s, idOfSlot(that) = %s; engine speciesFromName = %s"):format(q, tostring(s),
          tostring(s and nd.idOfSlot(s)), tostring(Pokemon.speciesFromName(q))))
      end
      for _, s in ipairs({ 19, 20, 1176 }) do
        local tt = Pokemon.types(s)
        log(("  slot %d: dex id %s, keyName %s, national %s, types %s/%s"):format(s, tostring(nd.idOfSlot(s)),
          tostring(Pokemon.keyName(s)), tostring(Pokemon.national(s)), tostring(tt[1]), tostring(tt[2])))
      end
    end
  end
  if boss then
    local mv = {}
    for _, m in ipairs(boss.moves or {}) do mv[#mv + 1] = m.name end
    log(("boss %s Lv %s, types %s/%s, moves: %s; Max Move: %s %s (%s)"):format(boss.name, tostring(boss.mon.level),
      tostring(boss.type1), tostring(boss.type2), table.concat(mv, ", "), tostring(boss.gmax and boss.gmax.name),
      tostring(boss.gmax and boss.gmax.power), tostring(boss.gmax and boss.gmax.typeName)))
    check(#(boss.moves or {}) > 0, "the boss knows moves at its level")
    check(boss.gmax and boss.gmax.isMax, "it has a Max Move")
  end
  -- turns of Fight until its Max Move is used
  local seenEv, maxShot = nil, false
  local deadline = clock() + 120
  while clock() < deadline and X.state().active and not maxShot do
    cur = R.current()
    if not cur then break end
    local e = cur.events and cur.events[cur.evI]
    if e and e ~= seenEv then
      seenEv = e
      if e.kind == "use" and e.gmax then
        log("used", e.move and e.move.name)
        secs(1.9)
        shot("y4_maxmove")
        maxShot = true
      end
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      if cur.cmd.menu == "main" then R.choose("fight") else R.choose("move1") end
    end
    U.wait(1)
  end
  check(maxShot, "the Max Move was used")
  X.close()
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
