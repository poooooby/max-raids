-- Driver: the raid API (src/raid_api.lua) on the real engine, through a stand-in mod "probe_mod"
-- that reads its files from ours. It makes a boss of its own art (the pack's Charizard sheet read
-- through the art path) at level 60 with fixed moves, a Modest nature, IVs of 31 and Leftovers, a
-- sure catch; a den on Route 101 with a green beam and its rewards replaced by a Master Ball. The
-- den appears (before the awakening: another mod's den does not wait for it unless asked), its
-- beam is drawn, A opens its den screen, the raid is won and the boss caught (its level, nature
-- and IVs), the card shows the one row, onEnd and the raid_end event are told, the den is spent and
-- made live again. Then h:open straight into a raid of a boss that can't be caught: no catch, the
-- card. Shots api_*.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/api_probe.lua love .

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
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what); return ok end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Pk = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Coll = require("src.core.game3.collision")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  pcall(Bag.add, s0.bag, C:require("items", "ITEM_ULTRA_BALL"), 5)
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").checkLineOfSight = function() return nil end
  local X = game.mods.exports.max_raids
  local R = X.raid
  local Dn = X.dens
  if not check(type(X.connect) == "function" and X.apiVersion == "1.0.0", "the API is exported (apiVersion 1.0.0)") then return end
  check(X.supports("dens") and X.supports("art"), "supports dens and art")
  Dn.setAwake(false)

  -- the events any mod can listen for
  local heard = {}
  local ev = game.mods.events
  if ev and ev.on then
    ev:on("mod.max_raids.raid_start", function(info) heard[#heard + 1] = { "start", info } end)
    ev:on("mod.max_raids.raid_end", function(info) heard[#heard + 1] = { "end", info } end)
  end

  -- the stand-in mod: its files are ours
  local h = X.connect("probe_mod", { read = function(path) return love.filesystem.read("mods/max_raids/" .. path) end })
  check(type(h) == "table", "connect: a handle")
  local zsp = R.Sprites.CHARIZARD_4
  local key, code, msg = h:boss("art_zard", { species = "CHARIZARD", stars = 3, level = 60, name = "Ember King",
    moves = { "FLAMETHROWER", "WING_ATTACK" }, nature = "MODEST", ivs = 31, item = "LEFTOVERS", catch = "sure", shiny = false,
    art = { sheet = "assets/bosses/CHARIZARD_4.png", cell = zsp.cell, frames = zsp.frames, cols = zsp.cols,
      speed = zsp.speed and zsp.speed[1] or 2, height = 20, icon = "assets/bosses/icons/CHARIZARD_4.png" } })
  log("boss", tostring(key), tostring(code), tostring(msg))
  check(key == "EXT:probe_mod:art_zard", "its boss's key")
  local ok, c2, m2 = h:check("art_zard")
  check(ok == true, "check: the boss resolves, its art read (" .. tostring(c2) .. " " .. tostring(m2) .. ")")

  -- Route 101: a cell for the den with one below for the player
  local mapId = "EM_ROUTE101"
  local Field = require("src.core.game3.field")
  local function goTo(m, x, y, facing)
    local okL, res, why = pcall(Map.load, Field._mod, Field._game or game, m, { x = x, y = y, facing = facing })
    if not okL or (res == nil and why) then log("Map.load failed", tostring(okL and why or res)); return false end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(20)
    return true
  end
  goTo(mapId, 10, 10, "down")
  local def = Map.currentDef()
  local Objects = require("src.core.game3.objects")
  local spot
  local w, hgt = tonumber(def.width) or 20, tonumber(def.height) or 20
  for y = 4, hgt - 4 do
    for x = 4, w - 4 do
      local function free(cx, cy)
        return Coll.isWalkable(cx, cy) and not Coll.isWater(cx, cy) and not Coll.warpAt(cx, cy) and not Objects.at(cx, cy)
      end
      if not spot and free(x, y) and free(x, y + 1) then spot = { x = x, y = y } end
    end
  end
  if not check(spot ~= nil, "a free cell on Route 101") then return end
  local ended = {}
  check(h:den("green", { map = mapId, x = spot.x, y = spot.y, boss = "art_zard",
    beam = { color = { 0.25, 1, 0.45 }, core = { 0.9, 1, 0.9 }, height = 190, sparks = 16 },
    rewards = { mode = "replace", items = { { "MASTER_BALL", 1 } } },
    onEnd = function(info) ended[#ended + 1] = info end }) == true, "a den with a green beam")
  goTo(mapId, spot.x, spot.y + 1, "up")
  Dn.ensure()
  U.wait(30)
  local den = Dn.extDen("probe_mod:green")
  check(den and Dn.isLive(den), "its den is live (the region not yet awake)")
  check((Dn.beamDraws or 0) > 0, "its beam is drawn")
  check(den.beamStyle and den.beamStyle.color[2] == 1 and den.beamStyle.height == 190, "...green, 190 px")
  shot("api_01_den_field")
  U.tap(game, "a")
  waitFor(function() return X.state().active end, 120)
  check(X.state().active and X.state().phase == "den", "A on its den opens the den screen")
  U.wait(20)
  local r = R.current()
  check(r and r.key == key and r.ext and r.ext.mod == "probe_mod", "the den screen holds its boss and its mod")
  check(R.loadedKey() == key, "its art is loaded")
  shot("api_02_den_screen")
  check(R.denStart(), "START")
  waitFor(function() local c = R.current(); return c and c.phase == "command" and not c.say end, 20000)
  r = R.current()
  check(r and r.boss and r.boss.mon.level == 60 and r.boss.item and r.boss.item > 0, "the boss: level 60, holding its item")
  check(r and #r.boss.moves == 2 and r.boss.moves[1].key == "FLAMETHROWER", "...its moves")
  check(r and r.sim and r.song ~= nil, "the battle is up")
  shot("api_03_raid")
  -- the boss at 1 HP, no barrier: the team's first blows win
  r.boss.mon.hp, r.boss.shields = 1, {}
  for _ = 1, 4 do
    local c = R.current()
    if not (c and c.phase == "command") then break end
    if c.cmd.menu ~= "moves" then R.choose("fight"); U.wait(2) end
    R.choose("move1")
    U.wait(4)
    for k = 1, 4 do
      c = R.current()
      if not (c and c.cmd and c.cmd.menu == "target") then break end
      R.choose("move" .. k)
      U.wait(4)
    end
  end
  waitFor(function() local c = R.current(); return c and c.phase == "catch" end, 6000)
  check(X.state().phase == "catch", "won: the catch")
  r = R.current()
  check(r.outcome == "win", "its outcome: win")
  R.catchChoose("catch")
  U.wait(4)
  R.pickBall()
  waitFor(function() local c = R.current(); return c and c.phase == "rewards" end, 6000)
  r = R.current()
  check(r and r.throw and r.throw.caught, "the catch is sure")
  local mon = r and r.throw and r.throw.info and r.throw.info.mon
  if mon then
    local all31 = true
    for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do all31 = all31 and mon.ivs and mon.ivs[k] == 31 end
    log("caught: level", mon.level, "nature", Pk.natureId(mon.personality))
    check(mon.level == 60 and Pk.natureId(mon.personality) == 15 and all31, "caught: level 60, Modest, IVs 31")
  else
    check(false, "the caught Pokemon")
  end
  local rows = r and r.rewards and r.rewards.items or {}
  check(#rows == 1 and rows[1].id == C:require("items", "ITEM_MASTER_BALL") and rows[1].n == 1, "the card: one Master Ball, the roll replaced")
  U.wait(40)
  shot("api_04_card")
  R.endRewards()
  waitFor(function() return not X.state().active end, 3000)
  check(not X.state().active, "back on the field")
  local info = ended[1]
  check(info and info.outcome == "win" and info.caught and info.mon == mon and info.den == "green" and info.mod == "probe_mod",
    "onEnd: win, caught, the Pokemon, its den and mod")
  local heardEnd = nil
  for _, e in ipairs(heard) do if e[1] == "end" then heardEnd = e[2] end end
  check(#heard >= 2 and heard[1][1] == "start" and heardEnd and heardEnd.key == key, "the raid_start and raid_end events")
  local st = h:denState("green")
  check(st and st.done and not st.live, "its den is spent")
  U.wait(10)
  shot("api_05_spent")
  check(h:setDen("green", { done = false }) and h:denState("green").live, "setDen done = false: live again")

  -- straight into a raid that can't be caught
  check(h:boss("nocatch", { species = 25, stars = 2, level = 30, catch = false }) ~= nil, "a boss that can't be caught")
  check(h:open("nocatch", { denScreen = false, rewards = { items = { { "RARE_CANDY", 2 } } } }) == true, "h:open, no den screen")
  waitFor(function() local c = R.current(); return c and c.phase == "command" and not c.say end, 20000)
  r = R.current()
  check(r and r.key == "EXT:probe_mod:nocatch", "the raid is its boss's")
  r.boss.mon.hp, r.boss.shields = 1, {}
  for _ = 1, 4 do
    local c = R.current()
    if not (c and c.phase == "command") then break end
    if c.cmd.menu ~= "moves" then R.choose("fight"); U.wait(2) end
    R.choose("move1")
    U.wait(4)
    for k = 1, 4 do
      c = R.current()
      if not (c and c.cmd and c.cmd.menu == "target") then break end
      R.choose("move" .. k)
      U.wait(4)
    end
  end
  local sawCatch = false
  waitFor(function()
    local c = R.current()
    if c and c.phase == "catch" then sawCatch = true end
    return c and c.phase == "rewards"
  end, 6000)
  check(X.state().phase == "rewards" and not sawCatch, "won: straight to the card, no catch")
  rows = R.current().rewards.items
  local candy = false
  for _, row in ipairs(rows) do if row.id == C:require("items", "ITEM_RARE_CANDY") and row.n >= 2 then candy = true end end
  check(#rows > 1 and candy, "the card: the roll and two Rare Candies added")
  U.wait(30)
  shot("api_06_nocatch_card")
  X.close()
  waitFor(function() return not X.state().active end, 300)
  check(h:removeDen("green") == true and Dn.extDen("probe_mod:green") == nil, "removeDen")
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
