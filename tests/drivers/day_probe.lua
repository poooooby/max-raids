-- Driver: the dens' day (src/dens.lua Dn.today / stepDay). The day number this game uses (the cart's
-- clock on Ruby / Sapphire / Emerald, the device's local date on FireRed / LeafGreen) against the
-- device's; then midnight passing with the player standing on a route (Dn.today stood in for, a day
-- on): the map's dens roll again within DAY_CHECK_S, without a map change.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/day_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local clock = love.timer.getTime
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Rtc = require("src.core.game3.rtc")
  require("src.core.game3.encounters").onStep = function() return nil end
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not (X and X.dens) then log("FAIL max_raids not loaded"); return end
  local Dn = X.dens
  local s0 = Runtime.getSession()

  -- which clock
  local d = os.date("*t")
  local deviceDay = math.floor(os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
  local cart = Rtc.enabled and Rtc.enabled(s0)
  local t = cart and Rtc.calcLocalTime(s0) or nil
  log(("today %d; the cart's clock %s%s; the device's local day %d (%s)"):format(Dn.today(), tostring(cart),
    t and (" (day %d, %02d:%02d)"):format(t.days or -1, t.hours or -1, t.minutes or -1) or "", deviceDay,
    os.date("%Y-%m-%d %H:%M")))

  -- National Dex Gen 3's CLOCK SOURCE: with the cart's clock set 3 hours behind the device (the wall
  -- clock set off at the start), Device turns the dens' day over at the device's midnight, In-game at
  -- the cart's. (Run at 1 am to see the two differ: POKEPORT_RTC=2026-10-28T01:00:00.)
  if cart then
    local keep = s0.localTimeOffset and Rtc.copyTime(s0.localTimeOffset) or nil
    local info = Rtc.hostInfo(s0)
    local dc = Rtc.getDayCount(info)
    local h = info.hour - 3
    local days = dc
    if h < 0 then h, days = h + 24, dc - 1 end
    Rtc.calcLocalTimeOffset(s0, days, h, info.minute, info.second)
    local c = Rtc.calcLocalTime(s0)
    Dn.clockSource = "game"
    local onGame = Dn.today()
    Dn.clockSource = "device"
    local onDevice = Dn.today()
    Dn.clockSource = nil
    local devDay = math.floor(os.time({ year = 2000 + info.year, month = info.month, day = info.day, hour = 12 }) / 86400)
    log(("the cart 3 h behind: %02d:%02d day %d; In-game -> %d, Device -> %d (the device's day %d)"):format(
      c.hours, c.minutes, c.days, onGame, onDevice, devDay))
    check(onGame == c.days, "In-game: the cart's day")
    check(onDevice == devDay, "Device: the device's own day, whatever the cart's clock says")
    -- the same through National Dex Gen 3's stored option, as a player sets it (no override)
    local ndx = game.mods.exports and game.mods.exports.national_dex_gen3
    check(ndx ~= nil and type(ndx.clockSource) == "function", "National Dex Gen 3 exports its CLOCK SOURCE")
    local opts = game.mods and game.mods.modOptions
    if opts then
      opts.national_dex_gen3 = opts.national_dex_gen3 or {}
      local was = opts.national_dex_gen3.clock_source
      opts.national_dex_gen3.clock_source = "device"
      check(Dn.today() == devDay, "the option set to Device: the device's own day")
      opts.national_dex_gen3.clock_source = "game"
      check(Dn.today() == c.days, "the option set to In-game: the cart's day")
      opts.national_dex_gen3.clock_source = was
    end
    if keep then s0.localTimeOffset = keep end
  end
  if not cart then check(Dn.today() == deviceDay, "no cart clock: the device's local date") end

  -- on a route with its dens
  local was = Dn.awake()
  Dn.setAwake(true)
  local route
  for id in pairs(game.data and game.data.maps or {}) do
    if type(id) == "string" and (id:match("ROUTE_?104$") or id:match("ROUTE_?2$")) and not id:find("UNDERWATER") then route = id end
  end
  local def = game.data.maps[route]
  local Field = require("src.core.game3.field")
  pcall(Map.load, Field._mod, Field._game or game, route, { x = math.floor(def.width / 2), y = math.floor(def.height / 2), facing = "down" })
  Player.cellX, Player.cellY = math.floor(def.width / 2), math.floor(def.height / 2)
  waitFor(function() return Dn.forMap(route) ~= nil end, 600)
  U.wait(60)
  local list = Dn.forMap(route) or {}
  check(#list > 0, "the route has its dens")
  local before = {}
  for i, den in ipairs(list) do before[i] = { day = den.day, boss = den.boss, active = den.active } end
  log("dens rolled for day", tostring(list[1] and list[1].day))

  -- midnight: the engine's clock stepped (POKEPORT_RTC fixes it; Rtc.advance moves it) from 23:59
  -- over 12am, the map entered again
  -- (as the player arrives: the game's warp, out to a town and back)
  local Warp = require("src.core.game3.warp")
  local town
  for id in pairs(game.data.maps) do
    if type(id) == "string" and (id:match("PETALBURG_CITY$") or id:match("VIRIDIAN_CITY$")) then town = id end
  end
  local function warpTo(id, x, y)
    Warp.request(nil, game, id, x, y, "down", {})
    waitFor(function() return Map.current == id and not Warp.isBusy() end, 1200)
    U.wait(60)
  end
  local function reenter()
    local td = game.data.maps[town]
    warpTo(town, math.floor(td.width / 2), math.floor(td.height / 2))
    warpTo(route, math.floor(def.width / 2), math.floor(def.height / 2))
  end
  local function clockNow()
    local c = Rtc.enabled and Rtc.enabled(s0) and Rtc.calcLocalTime(s0)
    local h = Rtc.hostInfo(nil)
    return c and ("the cart %02d:%02d:%02d day %d"):format(c.hours, c.minutes, c.seconds or 0, c.days)
      or ("the device %02d:%02d:%02d"):format(h.hour, h.minute, h.second or 0)
  end
  if Rtc.fixedActive and not Rtc.fixedActive() then log("(run with POKEPORT_RTC=2026-10-27T23:59:00 for the midnight check)") end
  local d0 = Dn.today()
  log(("before: %s, today %d"):format(clockNow(), d0))
  Rtc.advance(0, 59)
  reenter()
  log(("59 s on: %s, today %d"):format(clockNow(), Dn.today()))
  check(Dn.today() == d0 and list[1].day == d0, "23:59:59: still the same day, the dens as they were")
  Rtc.advance(0, 2)
  reenter()
  log(("2 s more: %s, today %d"):format(clockNow(), Dn.today()))
  check(Dn.today() == d0 + 1, "00:00:01: a new day")
  check(list[1].day == d0 + 1, "the map entered again: its dens rolled for the new day")
  for i, den in ipairs(list) do
    log(("  den %d: %s -> %s"):format(i, before[i].active and tostring(before[i].boss) or "quiet",
      den.active and tostring(den.boss) or "quiet"))
  end
  Dn.setAwake(was)
  log(("%d failures"):format(fails))
end

return function(game)
  local log = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  love.event.quit()
end
