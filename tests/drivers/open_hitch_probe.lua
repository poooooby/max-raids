-- Driver: what opening a raid costs - the battlefield's build (its textures drawn, its meshes made:
-- Scene.scene), and frame by frame from X.open through the intro (the first frames compile the sky's
-- shaders and render the 3D the first time). Logs the build's time and every frame over HITCH_MS.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/open_hitch_probe.lua love .

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
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR" }) do
    Party.giveMon(s0, C:require("species", sp), 70)
  end
  U.wait(30)
  local X = game.mods.exports.max_raids
  local Sc = X._test.scene
  local HITCH = tonumber(os.getenv("HITCH_MS")) or 25
  -- the build alone, timed (then put back so the raid builds it as it would)
  -- (not with PROBE_WARM: its textures would then be made already)
  if os.getenv("PROBE_WARM") ~= "1" then
    Sc.resetScene()
    local t0 = clock()
    local sc = Sc.scene()
    log(("the battlefield's build: %.1f ms (%d pieces)"):format((clock() - t0) * 1000, sc and #sc.pieces or 0))
    Sc.resetScene()
  end
  -- PROBE_WARM=1: the den screen's warm-up first (as a raid opened from a den does), each step timed
  if os.getenv("PROBE_WARM") == "1" then
    local step, done = 0, false
    while not done and step < 40 do
      step = step + 1
      local tw = clock()
      done = Sc.warm()
      log(("warm step %d: %.1f ms"):format(step, (clock() - tw) * 1000))
      U.wait(1)
    end
  end
  -- frames from the open through the intro
  local frames, worst, over = 0, 0, {}
  local R = X.raid
  -- PROBE_DEN=1: the real way in - the den screen, START, the fade through black (each frame noted
  -- black or not: the den's fade out held, or the raid's fade in still whole)
  local function black()
    local c = R.current()
    if not c then return false end
    if c.starting then return c.t - c.starting.t0 >= R.DEN_FADE.OUT end
    return (c.fadeIn or 0) >= R.DEN_FADE.IN * 0.98
  end
  if os.getenv("PROBE_DEN") == "1" then
    R.openDen({ active = true, boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4", stars = 4 })
    waitFor(function() local c = R.current(); return c and c.phase == "den" and c.t > 1.5 end, 2000)
    R.denStart()
  end
  local last = clock()
  if os.getenv("PROBE_DEN") ~= "1" then X.open(os.getenv("PROBE_BOSS") or "CHARIZARD_4") end
  local deadline = clock() + 20
  while clock() < deadline do
    U.wait(1)
    local now = clock()
    local ms = (now - last) * 1000
    last = now
    frames = frames + 1
    if ms > worst then worst = ms end
    local cur = X.raid.current()
    local dark = black()
    if ms > HITCH then
      over[#over + 1] = ("frame %d %.1f ms (phase %s, t %.2f)%s"):format(frames, ms, cur and cur.phase or "-",
        cur and cur.t or 0, dark and " - under black" or " - SEEN")
    end
    if cur and cur.phase == "command" then break end
  end
  log(("open to commands: %d frames, slowest %.1f ms, %d over %d ms"):format(frames, worst, #over, HITCH))
  for _, l in ipairs(over) do log("  HITCH " .. l) end
  X.close()
  U.wait(10)
end

return function(game)
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  love.event.quit()
end
