-- Driver: every move the game has, and the look the raid gives it (raid.lua Rd.specOf) - its own
-- (data/raid_move_fx.lua MOVES), one taken from what it does (Rd.lookOf), a team move's (its side
-- event's), or only its type's default (DEFAULT) - and whether a pixel art effect plays with it.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/looks_audit.lua love .
-- Writes <SHOT_DIR>/looks_audit.txt.

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
  local Bt, R = X._test.battle, X.raid
  local MoveFx = R.MoveFx or {}
  -- (the kinds that land with a pixel art effect; the types that add theirs - src/fx.lua landSheets)
  local SHEET_KIND = { slash = true, slam = true, multi = true, bite = true }
  local SHEET_TYPE = { ELECTRIC = true, WATER = true, POISON = true }
  local count = { own = 0, derived = 0, team = 0, type = 0 }
  local byKind, typeOnly, sheet = {}, {}, 0
  local total = 0
  for id = 1, 900 do
    local ok, m = pcall(Bt.move, id)
    if ok and m and m.name and m.name ~= "" and m.num == id then
      total = total + 1
      local spec = R.specOf(m)
      local src
      if m.team and m.status then src = "team"
      elseif (MoveFx.MOVES or {})[m.key or ""] then src = "own"
      elseif R.lookOf(m) then src = "derived"
      else src = "type" end
      count[src] = count[src] + 1
      byKind[spec[1]] = (byKind[spec[1]] or 0) + 1
      if src == "type" then typeOnly[#typeOnly + 1] = ("%4d %-16s %-9s %s"):format(id, m.name, m.typeName or "?", spec[1]) end
      if not m.status and (SHEET_KIND[spec[1]] or (spec[1] == "powder" and spec.shape == "spore") or SHEET_TYPE[m.typeName or ""]) then
        sheet = sheet + 1
      end
    end
  end
  local f = io.open(dir .. "/looks_audit.txt", "w")
  f:write(("%d moves: %d their own look, %d one from what they do, %d team moves (their own event looks), %d their type's default\n"):format(
    total, count.own, count.derived, count.team, count.type))
  f:write(("%d damaging moves land with a pixel art effect\n\n-- by kind:\n"):format(sheet))
  local kinds = {}
  for k in pairs(byKind) do kinds[#kinds + 1] = k end
  table.sort(kinds)
  for _, k in ipairs(kinds) do f:write(("%-8s %d\n"):format(k, byKind[k])) end
  f:write("\n-- only their type's default:\n")
  for _, l in ipairs(typeOnly) do f:write(l, "\n") end
  f:close()
  log(("%d moves: own %d, derived %d, team %d, type default %d; pixel art on %d"):format(total, count.own, count.derived,
    count.team, count.type, sheet))
  for _, k in ipairs(kinds) do log(("  %-8s %d"):format(k, byKind[k])) end
end

return function(game)
  local ok, err = xpcall(function() body(game, function(...) print("[driver]", ...) end) end, debug.traceback)
  if not ok then print("[driver] DRIVER ERROR:", tostring(err)) end
  print("[driver] DONE")
  love.event.quit()
end
