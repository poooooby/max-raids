-- Driver: every move the game has (Gen 3's 354 and National Dex Gen 3's newer ones), as the raid sim
-- would run it. Lists each move whose Gen 3 effect or National Dex extra does something besides plain
-- damage and has no side effect in the raid (so it would do nothing), and the effect names behind them.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/move_audit.lua love .
-- Writes <SHOT_DIR>/move_audit.txt.

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local X = game.mods.exports.max_raids
  local Bt = X._test.battle
  local EffectIds = require("src.core.game3.battle.effect_ids")
  local Moves = require("src.core.game3.battle.moves")
  local name = {}
  for k, v in pairs(EffectIds) do if type(v) == "number" and not name[v] then name[v] = k end end

  -- effects the engine's damage or the sim's own rules already carry (the move needs no side)
  local PLAIN = {}
  for _, k in ipairs({ "HIT", "ALWAYS_HIT", "HIGH_CRITICAL", "QUICK_ATTACK", "VITAL_THROW", "FALSE_SWIPE", "SONICBOOM",
    "DRAGON_RAGE", "LEVEL_DAMAGE", "PSYWAVE", "SUPER_FANG", "FLAIL", "RETURN", "FRUSTRATION", "MAGNITUDE", "ERUPTION",
    "LOW_KICK", "HIDDEN_POWER", "WEATHER_BALL", "FACADE", "REVENGE", "SMELLINGSALT", "EARTHQUAKE", "GUST", "TWISTER",
    "THUNDER", "ENDEAVOR", "COUNTER", "MIRROR_COAT", "PURSUIT", "EXPLOSION", "SECRET_POWER", "PRESENT", "SNORE",
    "BEAT_UP", "FOCUS_PUNCH", "PAY_DAY", "KNOCK_OFF", "BRICK_BREAK", "RAPID_SPIN", "ROLLOUT", "FURY_CUTTER",
    "SKY_UPPERCUT", "WEATHER_BALL", "SPLASH" }) do PLAIN[k] = true end

  local rows, missing, byEffect = {}, {}, {}
  local total, withSide = 0, 0
  for id = 1, 900 do
    local ok, m = pcall(Bt.move, id)
    if ok and m and m.name and m.name ~= "" and m.num == id then
      total = total + 1
      local e = name[tonumber(m.ref.effect)] or tostring(m.ref.effect)
      local keys = {}
      for k in pairs(m.side or {}) do keys[#keys + 1] = k end
      table.sort(keys)
      rows[#rows + 1] = ("%4d %-16s %-26s %s"):format(id, m.name, e, table.concat(keys, ","))
      if m.side then withSide = withSide + 1
      elseif not PLAIN[e] and not m.team then
        missing[#missing + 1] = ("%4d %-16s %s"):format(id, m.name, e)
        byEffect[e] = (byEffect[e] or 0) + 1
      end
    end
  end
  local f = io.open(dir .. "/move_audit.txt", "w")
  f:write(("%d moves, %d with a side effect, %d with an effect and none\n\n"):format(total, withSide, #missing))
  f:write("-- with no side effect and an effect the sim does not carry:\n")
  for _, l in ipairs(missing) do f:write(l, "\n") end
  f:write("\n-- by effect:\n")
  local names = {}
  for k in pairs(byEffect) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do f:write(("%-26s %d\n"):format(k, byEffect[k])) end
  f:write("\n-- every move:\n")
  for _, l in ipairs(rows) do f:write(l, "\n") end
  f:close()
  log(("%d moves, %d with a side effect, %d unhandled"):format(total, withSide, #missing))
  for _, k in ipairs(names) do log(("  %-26s %d"):format(k, byEffect[k])) end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/max_raids"
  local ok, err = xpcall(function() body(game, function(...) print("[driver]", ...) end) end, debug.traceback)
  if not ok then print("[driver] DRIVER ERROR:", tostring(err)) end
  print("[driver] DONE")
  love.event.quit()
end
