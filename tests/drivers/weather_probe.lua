-- Driver: the weather and the terrain in a raid. Charizard Dynamaxes on turn 1 and its Fire move is
-- Max Flare: the sun's event plays (its words, its sound), the field's record shows it (src/raid.lua
-- startEvent -> Fx), the sim holds it five turns. Then each weather and terrain is put on the field's
-- record in turn and shot from the wide view, one after another (the last fading as the next comes).
-- Shots w*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/weather_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local fails = 0
  local function check(ok, what) if not ok then fails = fails + 1 end; log((ok and "ok   " or "FAIL ") .. what) end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_CHARIZARD", "SPECIES_GARDEVOIR", "SPECIES_METAGROSS", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local R, Sc = X.raid, X._test.scene
  X.open(os.getenv("PROBE_BOSS") or "SNORLAX_2")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local cur = R.current()
  local m1 = cur.members[1].b
  -- member 1: Fight, DYNAMAX, its Fire move (Max Flare); the others their first
  R.choose("fight")
  U.wait(4)
  check(R.choose("dynamax"), "DYNAMAX on")
  local slot = nil
  for i, mv in ipairs(m1.moves) do if not mv.status and mv.typeName == "FIRE" then slot = i; break end end
  check(slot ~= nil, "Charizard has a Fire move")
  log("  its Max Move: " .. tostring(slot and m1.maxMoves[slot].name))
  R.choose("move" .. (slot or 1))
  for _ = 2, 4 do
    local c = R.current().cmd
    if c and c.actor then R.choose("fight"); R.choose("move1") end
  end
  -- the sun's event as it plays
  local seen = waitFor(function()
    local c = R.current()
    local e = c.events and c.events[c.evI]
    return e and e.kind == "field" and e.weather == "SUN"
  end, 6000)
  check(seen, "Max Flare's sunlight plays as an event")
  log("  its words: " .. tostring(seen and R.current().events[R.current().evI].text))
  U.wait(60)
  local f = R.current().sideFx and R.current().sideFx.field
  check(f and f.weather == "SUN", "the field shows the sun (" .. tostring(f and f.weather) .. ")")
  shot("w01_sun_event")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  check(R.current().sim.weather == "SUN" and (R.current().sim.weatherTurns or 0) == 4,
    "the sim: sun, four turns left (" .. tostring(R.current().sim.weatherTurns) .. ")")
  U.wait(30)
  shot("w02_sun_command")
  -- each in turn on the field's record, from the wide view
  Sc.shot("wide", 0.01)
  local function show(what, kind)
    local c = R.current()
    local fr = c.sideFx.field
    if fr[what] and fr[what] ~= kind then fr[what .. "Was"], fr[what .. "Off"] = fr[what], c.t end
    fr[what], fr[what .. "T"] = kind, c.t
  end
  local function clear(what)
    local c = R.current()
    local fr = c.sideFx.field
    if fr[what] then fr[what .. "Was"], fr[what .. "Off"], fr[what] = fr[what], c.t, nil end
  end
  for _, k in ipairs({ "RAIN", "SAND", "HAIL", "SUN" }) do
    show("weather", k)
    U.wait(90)
    shot("w1_" .. k:lower())
    log("  screen washes so far: " .. tostring(X.raid.Fx and X.raid.Fx.washes))
  end
  clear("weather")
  for _, k in ipairs({ "ELECTRIC", "GRASSY", "MISTY", "PSYCHIC" }) do
    show("terrain", k)
    U.wait(90)
    shot("w2_" .. k:lower())
  end
  -- (rain over Grassy Terrain, over a member's shoulder)
  show("weather", "RAIN")
  show("terrain", "GRASSY")
  Sc.shot("member", 0.01, 1)
  U.wait(90)
  shot("w3_rain_grassy_member")
  -- the garbage a call makes (the collector stopped): the raid's effects' layers and its screen part
  -- with rain over Grassy Terrain up
  do
    local Fx = R.Fx
    local t = R.current().t
    local G = love.graphics
    local function kbPerCall(fn, n)
      fn()
      collectgarbage("collect")
      collectgarbage("stop")
      local before = collectgarbage("count")
      for _ = 1, n do fn() end
      local after = collectgarbage("count")
      collectgarbage("restart")
      return (after - before) / n
    end
    local W, H = G.getDimensions()
    for _, layer in ipairs({ "back", "mid" }) do
      local kb = kbPerCall(function() G.push("all"); Fx.drawLayer(G, layer, t); G.pop() end, 100)
      log(("  garbage: Fx.drawLayer %s %.3f KB a call"):format(layer, kb))
    end
    local kb0 = kbPerCall(function() G.push("all"); Fx.draw(G, W, H, t); G.pop() end, 100)
    log(("  garbage: Fx.draw (front + screen) %.3f KB a call"):format(kb0))
    -- (the same with no weather or terrain: what the weather adds)
    local fr = R.current().sideFx.field
    local wk, tk = fr.weather, fr.terrain
    fr.weather, fr.terrain, fr.weatherWas, fr.terrainWas = nil, nil, nil, nil
    local base = 0
    for _, layer in ipairs({ "back", "mid" }) do
      base = base + kbPerCall(function() G.push("all"); Fx.drawLayer(G, layer, t); G.pop() end, 100)
    end
    base = base + kbPerCall(function() G.push("all"); Fx.draw(G, W, H, t); G.pop() end, 100)
    fr.weather, fr.terrain = wk, tk
    local with = 0
    for _, layer in ipairs({ "back", "mid" }) do
      with = with + kbPerCall(function() G.push("all"); Fx.drawLayer(G, layer, t); G.pop() end, 100)
    end
    with = with + kbPerCall(function() G.push("all"); Fx.draw(G, W, H, t); G.pop() end, 100)
    log(("  garbage: the raid's effects %.3f KB a frame with rain and grass, %.3f without"):format(with, base))
    check(with - base < 0.05, "the weather and terrain add no garbage a frame")
  end
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
