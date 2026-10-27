-- Driver: the rewards (src/rewards.lua RAID.REWARD) and National Dex Gen 3's Exp. Candies. Rolls
-- PROBE_ROLLS raids' drops for a boss of each tier and logs them; gives a 5★ raid's into the bag;
-- uses each Exp. Candy on a Pokemon (its level and Exp. before and after); saves the candies' Bag
-- icons, 8x, as candy_<id>.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/rewards_probe.lua love .

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 12)
  U.wait(20)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local Rw = X._test.rewards
  local ids = Rw.candyIds()
  check(ids ~= nil and ids.EXP_CANDY_XL ~= nil, "National Dex's Exp. Candies are there")
  local rng = function(lo, hi) return math.random(lo, hi) end
  local rolls = tonumber(os.getenv("PROBE_ROLLS")) or 4
  for _, key in ipairs({ "MEOWTH_4", "APPLETUN_2", "GRIMMSNARL_2", "CENTISKORCH_2", "DURALUDON_2" }) do
    for i = 1, rolls do
      local parts = {}
      for _, it in ipairs(Rw.rollItems(key, rng)) do
        parts[#parts + 1] = ("%s x%d"):format(Rw.itemName(it.id), it.n)
      end
      log(("%s roll %d: %s"):format(key, i, table.concat(parts, ", ")))
    end
  end
  -- a 5★ raid's rewards, given into the bag
  local out = Rw.give({ key = "DURALUDON_2" }, rng)
  local parts = {}
  for _, it in ipairs(out.items) do parts[#parts + 1] = ("%s x%d"):format(it.name, it.n) end
  log("given:", table.concat(parts, ", "))
  check(#out.items >= 5, "a 5★ raid gives its candies and TMs at least")
  -- each candy on the Torchic
  local mon = s0.party[1]
  for _, size in ipairs({ "XS", "S", "M", "L", "XL" }) do
    local id = ids and ids["EXP_CANDY_" .. size]
    if id then
      Bag.add(s0.bag, id, 1)
      local lv0, exp0 = mon.level, mon.exp
      local ok, kind, text = ItemUse.useField(s0, s0.bag, id, 1)
      log(("Exp. Candy %s on Torchic: %s %s, Lv %s -> %s, Exp %s -> %s: %s"):format(size, tostring(ok), tostring(kind),
        tostring(lv0), tostring(mon.level), tostring(exp0), tostring(mon.exp), tostring(text):gsub("\n", " ")))
      check(ok == true and (mon.exp or 0) > (exp0 or 0), "Exp. Candy " .. size .. " gives Exp.")
    end
  end
  -- the Party menu's steps after a candy that levels up (and past an evolution level): the candy's
  -- words, then the stat growth, then (no moves to learn at these levels or learned) the evolution
  do
    local PM = require("src.ui.game3.party_menu")
    check(PM._ndxCandy == true, "National Dex's candy steps are on the Party menu")
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 14)
    local tor = s0.party[#s0.party]
    local id = ids and ids.EXP_CANDY_M
    Bag.add(s0.bag, id, 1)
    local ok, kind, text = ItemUse.useField(s0, s0.bag, id, #s0.party)
    log(("Exp. Candy M on a Lv 14 Torchic: %s, now Lv %d"):format(tostring(ok), tor.level))
    PM._bag, PM._party, PM.cursor = s0.bag, s0.party, #s0.party
    local returned = false
    PM.showMessage(text, function() returned = true end)
    -- (the candy's words dismissed, as a press would)
    local dismiss = PM._messageOnDismiss or PM._onDismiss
    if PM.dismissMessage then pcall(PM.dismissMessage) end
    log("after its words: Party menu mode", tostring(PM.mode), "stat growth for it", tostring(PM._statGrowthMon == tor))
    check(PM.mode == "stat_growth" and PM._statGrowthMon == tor, "the candy's words lead into the stat growth")
    local done = PM._statGrowthDone
    if done then pcall(done) end
    U.wait(5)
    local Stack = require("src.ui.game3.stack")
    local evo = Stack.top and Stack.top()
    log("after the stat growth: top of the stack", tostring(evo and (evo.id or evo.name)), "mode", tostring(PM.mode),
      "returned", tostring(returned))
    -- on through its words (a new move, ...) to the evolution
    local Scene = require("src.ui.game3.evolution_scene")
    for step = 1, 30 do
      if Scene.isOpen() then break end
      log(("  step %d: mode %s, words %q"):format(step, tostring(PM.mode), tostring(PM._messageText or ""):gsub("\n", " ")))
      if PM.mode == "message" and PM.dismissMessage then pcall(PM.dismissMessage)
      elseif PM.mode == "yesno" and PM._yesNoCallback then
        -- (No: keep its moves; then "stop learning?" Yes)
        local cb = PM._yesNoCallback
        local prompt = tostring(PM._yesNoPrompt or "")
        PM._yesNoCallback = nil
        log("    asked:", (prompt:gsub("%s+", " ")))
        pcall(cb, prompt:lower():find("stop") ~= nil)
      end
      U.wait(3)
    end
    log("the evolution scene opened:", tostring(Scene.isOpen()), "learned:", (function()
      local t = {}
      for _, mv in ipairs(tor.moves or {}) do t[#t + 1] = tostring(type(mv) == "table" and (mv.id or mv.name) or mv) end
      return table.concat(t, ",")
    end)())
    check(Scene.isOpen(), "a candy past its evolution level starts the evolution")
    local _ = dismiss
  end
  -- the candies' icons, 8x
  local ndxSrc = love.filesystem.read("mods/national_dex_gen3/src/exp_candies.lua")
  local Cand = ndxSrc and load(ndxSrc)()
  if Cand then
    for _, c in ipairs(Cand.LIST) do
      local d = Cand.iconData(c)
      local big = love.image.newImageData(24 * 8, 24 * 8)
      big:mapPixel(function(x, y)
        local r, g, b, a = d:getPixel(math.floor(x / 8), math.floor(y / 8))
        if a == 0 then return 0.85, 0.9, 0.95, 1 end
        return r, g, b, a
      end)
      local f = io.open(dir .. "/candy_" .. c.id .. ".png", "wb")
      if f then f:write(big:encode("png"):getString()); f:close() end
    end
    log("icons saved")
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
