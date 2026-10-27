-- Driver: the dens' awakening (src/dens.lua Dn.awaken / stepAwaken). A new game with no badge: on a
-- route no awakening and no dens. In the first gym on its exit with the first badge given: nothing
-- indoors. Out of the door into the city: the screen shakes, then the words; the region saved
-- awake; on a route the dens appear. Shots a*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/awaken_probe.lua love .

local GYMS = { "RUSTBORO_CITY_GYM", "PEWTER_CITY_GYM" }

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local FieldView = require("src.core.game3.field_view")
  local Message = require("src.ui.game3.message")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Profile = require("src.core.game3.profile")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 20) end
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").checkLineOfSight = function() return nil end
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not (X and X.dens) then log("FAIL max_raids not loaded"); return end
  local Dn = X.dens
  local was = Dn.awake()
  Dn.setAwake(false)

  local function goTo(mapId, x, y, facing)
    local Field = require("src.core.game3.field")
    local ok, res, why = pcall(Map.load, Field._mod, Field._game or game, mapId, { x = x, y = y, facing = facing or "down" })
    if not ok or (res == nil and why) then log("Map.load", mapId, "failed:", tostring(ok and why or res)); return false end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing or "down" end
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(20)
    return true
  end
  local maps = game.data and game.data.maps or {}
  local gym, route
  for id in pairs(maps) do
    if type(id) == "string" then
      for _, g in ipairs(GYMS) do if id:sub(-#g) == g then gym = id end end
      if not route and id:match("ROUTE_?10[24]$") or (not route and id:match("ROUTE_?2$")) then route = id end
    end
  end
  log("gym", tostring(gym), "route", tostring(route))
  local function badgeFlag()
    local okP, P = pcall(Profile.forSession, nil)
    local t = Flags.forVersion(okP and P and P.id or nil)
    local b = t and t.BADGES and t.BADGES[1]
    return type(b) == "table" and b.flag or b
  end

  -- no badge: on a route, nothing
  if route then
    local def = maps[route]
    goTo(route, math.floor((def and def.width or 20) / 2), math.floor((def and def.height or 20) / 2))
    U.wait(90)
    check(not Dn.awake() and not Dn.awakening, "no badge: no awakening on a route")
    check(Dn.forMap(route) == nil, "no badge: no dens chosen on a route")
    shot("a01_route_no_badge")
  end

  -- the gym, on its exit, with the first badge
  if not gym then log("FAIL no gym map"); return end
  goTo(gym, 0, 0)
  local def = Map.currentDef and Map.currentDef()
  log("gym def: mapType", tostring(def and def.mapType), "kind", tostring(def and def.kind), "type", tostring(def and def.type))
  local exit
  for _, w in ipairs(def and def.warps or {}) do
    if not exit or tonumber(w.y) > tonumber(exit.y) then exit = w end
  end
  log("gym exit", exit and exit.x, exit and exit.y)
  goTo(gym, tonumber(exit.x), tonumber(exit.y), "down")
  Flags.setFlag(Space.getStore(), nil, badgeFlag(), true)
  check(Dn.badges() >= 1, "the first badge set")
  U.wait(90)
  check(not Dn.awakening and not Dn.awake(), "in the gym: no awakening yet")
  shot("a02_gym_exit")
  -- out of the door
  local before = Map.current
  U.hold(game, "down", 20)
  waitFor(function() return Map.current ~= before end, 600)
  log("left the gym into", tostring(Map.current))
  do
    local d2 = Map.currentDef and Map.currentDef()
    log("its def: mapType", tostring(d2 and d2.mapType), "kind", tostring(d2 and d2.kind), "type", tostring(d2 and d2.type))
  end
  local panned, shots = false, 0
  waitFor(function()
    if (FieldView.cameraPanX or 0) ~= 0 or (FieldView.cameraPanY or 0) ~= 0 then
      panned = true
      if shots < 2 then shots = shots + 1; shot("a03_shake_" .. shots) ; U.wait(6) end
    end
    return Message.isOpen()
  end, 900)
  check(panned, "out of the gym: the screen shakes")
  check(Message.isOpen(), "then the words")
  U.wait(60)
  shot("a04_words_1")
  local function msgState(label)
    local rs = package.loaded["src.ui.game3.rs.field_auto_scroll_message"]
    local Stack = require("src.ui.game3.stack")
    local top = Stack.top and Stack.top()
    log(("  %s: open %s waiting %s page %s/%s rsOwns %s stack %s top %s locked %s"):format(label,
      tostring(Message.open), tostring(Message._waiting), tostring(Message._page), tostring(Message._pages and #Message._pages),
      tostring(rs and rs.ownsFrame and rs.ownsFrame()), tostring(Stack.busy()), tostring(top and top.id),
      tostring(require("src.core.game3.field").isLocked())))
  end
  msgState("first words")
  U.tap(game, "a"); U.wait(30)
  msgState("after A")
  if Message.isOpen() then U.tap(game, "a"); U.wait(60); shot("a05_words_2") end
  msgState("after A again")
  -- (Ruby types slower: A until the words are gone)
  for _ = 1, 80 do if Message.isOpen() then U.tap(game, "a"); U.wait(20) end end
  msgState("at the end")
  waitFor(function() return Dn.awake() end, 300)
  check(Dn.awake(), "the region awake (saved)")
  check(not require("src.core.game3.field").isLocked(), "the player free again")

  -- on a route: dens
  if route then
    local d = maps[route]
    goTo(route, math.floor((d and d.width or 20) / 2), math.floor((d and d.height or 20) / 2))
    U.wait(60)
    local list = Dn.forMap(route)
    check(list ~= nil and #list > 0, "awake: the route has its dens")
    shot("a06_route_awake")
  end
  Dn.setAwake(was)
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
