-- Driver: dens on the routes. Boots Emerald, walks onto several routes (Map.load) and logs the dens
-- each gets (chosen from the map, the same after asking again), makes the first one active, stands
-- the player under it facing up and presses A: the den screen opens (shot), a member is toggled,
-- START goes into the raid (shot), FLEE comes back. Then a new day re-rolls the dens without
-- moving them. Shots of the field show the den sprite and its beam.
--   SHOT_DIR=<dir> SHOT_W=1280 SHOT_H=720 POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/dens_probe.lua love .

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
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log((ok and "ok   " or "FAIL ") .. what)
    return ok
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "TORCHIC", "ZIGZAGOON", "WINGULL", "RALTS", "POOCHYENA" }) do
      Party.giveMon(s0, C:require("species", "SPECIES_" .. sp), 25)
    end
  end
  -- no wild Pokemon and no trainer spotting the player for the run
  local Enc = require("src.core.game3.encounters")
  Enc.onStep = function() return nil end
  local Sight = require("src.core.game3.trainer_sight")
  Sight.checkLineOfSight = function() return nil end
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not check(X ~= nil and X.dens ~= nil, "max_raids and its dens are loaded") then return end
  local Dn = X.dens
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function goTo(mapId, x, y, facing)
    local ok, err = pcall(Map.load, nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if not ok then log("Map.load", mapId, "failed:", tostring(err)); return false end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing or "down" end
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(20)
    return true
  end

  -- dens on a few routes
  local first
  -- no dens in a town, a city or the Safari Zone
  for _, nm in ipairs({ { "EM_PETALBURG_CITY", 10, 10 }, { "EM_LITTLEROOT_TOWN", 10, 10 }, { "EM_SAFARI_ZONE_SOUTH", 30, 30 } }) do
    if goTo(nm[1], nm[2], nm[3]) then
      Dn.ensure()
      U.wait(5)
      check(Dn.forMap(nm[1]) == nil, nm[1] .. " gets no dens")
    end
  end
  for _, mapId in ipairs({ "EM_ROUTE101", "EM_ROUTE102", "EM_ROUTE103", "EM_ROUTE104", "EM_ROUTE110", "EM_ROUTE119",
    "EM_ROUTE124" }) do
    if goTo(mapId, 8, 8) then
      waitFor(function() return Dn.forMap(mapId) ~= nil end, 120)
      local list = Dn.forMap(mapId)
      local parts = {}
      for i, d in ipairs(list or {}) do
        parts[#parts + 1] = ("(%d,%d) %s%s"):format(d.x, d.y, d.active and "active" or "quiet",
          d.active and (" " .. tostring(d.boss) .. " " .. tostring(d.stars) .. "*") or "")
        if not first and i == 1 then first = { mapId = mapId, den = d } end
      end
      log(mapId, "dens:", #(list or {}), table.concat(parts, "; "))
      check(list ~= nil, mapId .. " got its dens")
      -- each den against the engine's own view of the map
      local view = Dn.viewOf(mapId, Map.currentDef())
      local nres = 0
      for _ in pairs(view.reservedSet) do nres = nres + 1 end
      for i, d in ipairs(list or {}) do
        local talk = view.reserved(d.x, d.y) or view.reserved(d.x + 1, d.y) or view.reserved(d.x - 1, d.y)
          or view.reserved(d.x, d.y + 1) or view.reserved(d.x, d.y - 1)
        local near = false
        for dy = -1, 1 do for dx = -1, 1 do near = near or view.grass(d.x + dx, d.y + dy) end end
        log(("  den %d at (%d,%d) pass %s; grass next to it %s; reserved cells on the map %d"):format(
          i, d.x, d.y, tostring(d.pass), tostring(near), nres))
        log(("  den %d sprite %s"):format(i, Dn.spriteFor(d)))
        if d.pass == "water" then
          local ok = true
          -- (the den's own cell holds the den now)
          for dy = -3, 3 do
            for dx = -3, 3 do ok = ok and (dx == 0 and dy == 0 or view.water(d.x + dx, d.y + dy)) end
          end
          check(ok, mapId .. " den " .. i .. " is out on a larger body of calm water")
        end
        if talk then
          local hit = {}
          for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            if view.reserved(d.x + c[1], d.y + c[2]) then hit[#hit + 1] = (d.x + c[1]) .. "," .. (d.y + c[2]) end
          end
          log("  reserved now: " .. table.concat(hit, " ") .. "; reserved cells when placed "
            .. tostring(Dn.placedWith and Dn.placedWith[mapId]))
          local Objects = require("src.core.game3.objects")
          for _, lid in ipairs(Objects._order or {}) do
            local eo = Objects._byId and Objects._byId[lid]
            local df = eo and eo.def
            if df and not df.runtime then
              local sx, sy = tonumber(df.x) or 0, tonumber(df.y) or 0
              if math.abs(sx - d.x) + math.abs(sy - d.y) <= 12 then
                log(("    object %s at (%d,%d) range %s,%s sight %s gfx %s"):format(tostring(lid), sx, sy,
                  tostring(eo.rangeX or df.rangeX), tostring(eo.rangeY or df.rangeY),
                  tostring(eo.sight or df.sight or df.trainerRange), tostring(df.graphicsId or df.graphics)))
              end
            end
          end
        end
        check(not talk, mapId .. " den " .. i .. " is clear of trainers' lines, NPCs' walks and cutscene tiles")
      end
      -- the map's walkable, grassless ground by metatile: the commonest few, and what each den is on
      local Coll = require("src.core.game3.collision")
      local lay = Coll._mapDef and Coll._mapDef.midLayout
      if lay and lay.midAt then
        local counts, total = {}, 0
        for y = 0, view.h - 1 do
          for x = 0, view.w - 1 do
            if view.open(x, y) and not view.grass(x, y) then
              local m = lay:midAt(x, y)
              counts[m] = (counts[m] or 0) + 1
              total = total + 1
            end
          end
        end
        local top = {}
        for m, c in pairs(counts) do top[#top + 1] = { m, c } end
        table.sort(top, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(8, #top) do parts[#parts + 1] = ("0x%x:%d"):format(top[i][1], top[i][2]) end
        log("  ground metatiles (of " .. total .. "): " .. table.concat(parts, " "))
        for i, d in ipairs(list or {}) do log(("  den %d stands on 0x%x"):format(i, lay:midAt(d.x, d.y))) end
      end
      for i, d in ipairs(list or {}) do
        if d.pass == "water" then
          goTo(mapId, d.x, d.y + 2, "up")
          U.wait(20)
          shot("w_" .. mapId .. "_" .. i)
        end
      end
      if list and list[1] then
        goTo(mapId, list[1].x, list[1].y + 2, "up")
        U.wait(20)
        shot("p_" .. mapId)
      end
    end
  end
  if not check(first ~= nil, "a den to visit") then return end

  -- the first den, made active for the run, the player under it facing up
  local mapId, den = first.mapId, first.den
  local was = { x = den.x, y = den.y }
  den.active, den.done, den.stars, den.boss = true, nil, 4, "CHARIZARD_4"
  goTo(mapId, den.x, den.y + 1, "up")
  Dn.ensure()
  U.wait(30)
  log("beam draws so far:", tostring(Dn.beamDraws))
  check((Dn.beamDraws or 0) > 0, "the active den's beam is drawn")

  shot("d01_den_field")
  U.tap(game, "a")
  waitFor(function() return X.state().active end, 120)
  check(X.state().active and X.state().phase == "den", "A on the den opens its den screen")
  U.wait(10)
  shot("d02_den_screen")
  local R = X.raid
  R.denToggle(2)
  U.wait(4)
  shot("d03_den_toggled")
  check(R.denStart(), "START goes in")
  waitFor(function() return (X.state().t or 0) >= 5.2 end, 3000)
  shot("d04_raid")
  X.close()
  U.wait(10)
  check(not X.state().active, "back on the field")

  -- a new day: the den rolls again where it stands
  den.day = (den.day or 0) - 1
  Dn.ensure()
  check(den.x == was.x and den.y == was.y and den.day == Dn.today(), "a new day re-rolls the den in place")
  local again = Dn.forMap(mapId)
  check(again and again[1] == den, "the same den, saved")
  shot("d05_field_after")
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
