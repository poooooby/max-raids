-- Driver: the den screen (src/den_screen.lua) and its PC (src/pc_pick.lua). A party of six and two
-- Pokemon in the PC; the den screen opened on a 4★ den: the slots, the cursor on START, a slot's menu
-- (PARTY / PC / BACK), the party list, a party Pokemon put in a slot (and one another slot holds:
-- swapped), the PC (the game's boxes) with our SELECT / SUMMARY / BACK, the summary, BACK, SELECT
-- (the boxed one in the slot), START (the raid begins with it); then a quiet den. Shots p*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/den_screen_probe.lua love .

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR",
    "SPECIES_AGGRON", "SPECIES_SALAMENCE" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  -- two in the PC (a full party sends them there)
  for _, sp in ipairs({ "SPECIES_METAGROSS", "SPECIES_MILOTIC" }) do
    Party.giveMonToPlayer(s0, C:require("species", sp), 62)
  end
  local storage = Storage.ensure(s0)
  local boxed = {}
  for s = 1, 30 do local m = storage.boxes[storage.currentBox or 1].mons[s]; if m then boxed[#boxed + 1] = m end end
  log("party", #s0.party, "boxed", #boxed)
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R, Pick = X.raid, X._test.pick
  local Den = R.Den
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function press(key) U.tap(game, key); U.wait(4) end

  check(R.openDen({ active = true, boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4", stars = 4 }), "the den screen opens")
  local r = R.current()
  waitFor(function() return r.t > 0.5 end, 300)
  check(#Den.members(r) == 4, "the first four of the party in the slots")
  shot("p01_den")
  press("down"); press("down")
  check(r.cursor == 5, "down twice: the cursor on START")
  shot("p02_cursor_start")
  press("up"); press("right")
  check(r.cursor == 4, "up, right: slot 4")
  press("a")
  check(r.denMenu and r.denMenu.slot == 4, "A on a slot: its menu")
  shot("p03_slot_menu")
  press("a")
  check(r.denParty ~= nil, "PARTY: the party list")
  shot("p04_party_list")
  -- Salamander (6th) into slot 4
  for _ = 1, 6 do if r.denParty.cursor ~= 6 then press("down") end end
  press("a")
  check(r.slots[4] and r.slots[4].mon == s0.party[6], "the sixth into slot 4")
  -- Blaziken (in slot 1) into slot 2: swapped
  Den.openMenu(r, 2); Den.menuChoose(r, "party"); Den.pickParty(r, 1)
  check(r.slots[2].mon == s0.party[1] and r.slots[1].mon == s0.party[2], "one another slot holds: swapped")
  U.wait(4)
  shot("p05_after_party")

  -- the PC
  if Pick and Pick.available() and #boxed > 0 then
    Den.openMenu(r, 3)
    U.wait(2)
    r.denMenu.cursor = 2
    press("a")
    check(Pick.isOpen() and r.aside, "PC: the game's boxes, the den screen aside")
    waitFor(function() local B = require("src.ui.game3.box_storage_ui"); return B.open and not B.isPresentationBusy() end, 300)
    U.wait(20)
    shot("p06_pc")
    -- (the cursor starts on slot 1, where the first boxed one is)
    Pick.press("a"); U.wait(4)
    check(Pick.state() and Pick.state().menu ~= nil, "A on a boxed Pokemon: SELECT / SUMMARY / BACK")
    shot("p07_pc_menu")
    Pick.press("down"); U.wait(2)
    Pick.press("a")
    local Summary = require("src.ui.game3.summary_menu")
    waitFor(function() return Pick.state() and Pick.state().summary end, 120)
    U.wait(40)
    check(Pick.state() and Pick.state().summary, "SUMMARY: the game's summary")
    shot("p08_pc_summary")
    U.tap(game, "b")
    waitFor(function() return Pick.state() and not Pick.state().summary end, 300)
    U.wait(20)
    check(Pick.state() and Pick.state().menu ~= nil, "back from the summary: the menu again")
    Pick.press("down"); U.wait(2)
    Pick.press("a"); U.wait(4)
    check(Pick.state() and Pick.state().menu == nil, "BACK: the menu closes")
    shot("p09_pc_back")
    -- B and the game's own blocked: A on the box name does nothing
    Pick.press("a"); U.wait(2)
    Pick.press("a"); U.wait(4)   -- SELECT
    waitFor(function() return not Pick.isOpen() end, 300)
    check(not Pick.isOpen() and not r.aside, "SELECT: the PC closes, the den screen back")
    check(r.slots[3] and r.slots[3].mon == boxed[1], "the boxed one in slot 3")
    U.wait(10)
    shot("p10_after_pc")
    local _ = Summary
  else
    log("FAIL no PC (or nothing boxed)")
    fails = fails + 1
  end

  -- START: the raid with them
  r.cursor = 5
  check(R.denStart(), "START goes in")
  local ms = R.current().members
  check(ms and ms[3] and ms[3].orig == boxed[1], "the boxed one fights in slot 3")
  waitFor(function() return (X.state().t or 0) >= 6 end, 3000)
  shot("p11_raid")
  X.close()
  U.wait(10)
  -- a quiet den
  R.openDen({ active = false })
  U.wait(20)
  shot("p12_quiet")
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
