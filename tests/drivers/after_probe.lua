-- Driver: what a raid leaves behind. (1) A raid won with a boxed Pokemon among the four (put in slot 1
-- from the PC), Don't Catch, the rewards: the party and the box exactly as they were (every field of
-- every Pokemon, the order). (2) The after-raid steps (evolution, then moves at the new levels) on a
-- boxed Pokemon - the rewards give no Exp., so the game no longer reaches them; here the levels are
-- set by hand: it evolves where it is (still in the box, the party untouched) and the move picker
-- runs. Shots f*.png.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/after_probe.lua love .

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  s0.party = {}
  for _, sp in ipairs({ "SPECIES_SWAMPERT", "SPECIES_SCEPTILE", "SPECIES_GARDEVOIR", "SPECIES_AGGRON",
    "SPECIES_SALAMENCE", "SPECIES_METAGROSS" }) do
    Party.giveMon(s0, C:require("species", sp), 60)
  end
  -- a Torchic in the PC (a full party sends it there), one level short of Combusken
  Party.giveMonToPlayer(s0, C:require("species", "SPECIES_TORCHIC"), 15)
  local storage = Storage.ensure(s0)
  local boxId = storage.currentBox or 1
  local boxed, boxSlot
  for s = 1, 30 do
    local m = storage.boxes[boxId].mons[s]
    if m then boxed, boxSlot = m, s; break end
  end
  if not boxed then log("FAIL nothing boxed"); return end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.max_raids
  if not X then log("FAIL max_raids not loaded"); return end
  local R = X.raid

  -- a Pokemon as text: every field, sorted, nested tables in; functions and pictures left out
  local function dump(v, depth, seen)
    depth, seen = depth or 0, seen or {}
    local t = type(v)
    if t == "table" then
      if seen[v] or depth > 4 then return "<loop>" end
      seen[v] = true
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local parts = {}
      for _, k in ipairs(keys) do
        local x = v[k]
        local tx = type(x)
        if tx ~= "function" and tx ~= "userdata" and tx ~= "thread" then
          parts[#parts + 1] = tostring(k) .. "=" .. dump(x, depth + 1, seen)
        end
      end
      seen[v] = nil
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
  end
  local function snapshot()
    local out = { party = {}, ids = {} }
    for i, m in ipairs(s0.party) do out.party[i], out.ids[i] = dump(m), m end
    out.boxed = dump(storage.boxes[boxId].mons[boxSlot])
    out.boxedRef = storage.boxes[boxId].mons[boxSlot]
    return out
  end
  local function differs(a, b, label)
    local n = 0
    for i = 1, math.max(#a.party, #b.party) do
      if a.ids[i] ~= b.ids[i] then n = n + 1; log("  " .. label .. ": party slot " .. i .. " is another Pokemon")
      elseif a.party[i] ~= b.party[i] then
        n = n + 1
        -- (the first field that differs)
        local x, y = a.party[i], b.party[i]
        local k = 1
        while k <= #x and x:sub(k, k) == y:sub(k, k) do k = k + 1 end
        log("  " .. label .. ": party slot " .. i .. " changed near: " .. x:sub(math.max(1, k - 40), k + 40))
        log("     now: " .. y:sub(math.max(1, k - 40), k + 40))
      end
    end
    if a.boxedRef ~= b.boxedRef then n = n + 1; log("  " .. label .. ": the box slot holds another Pokemon")
    elseif a.boxed ~= b.boxed then n = n + 1; log("  " .. label .. ": the boxed Pokemon changed") end
    return n
  end

  -- (1) a raid won with the boxed one in slot 1
  local before = snapshot()
  check(R.openDen({ active = true, boss = os.getenv("PROBE_BOSS") or "MEOWTH_4", stars = 1 }), "the den screen opens")
  local r = R.current()
  waitFor(function() return r.t > 0.4 end, 300)
  R.Den.put(r, 1, boxed)
  check(R.denStart(), "START with the boxed Torchic in slot 1")
  -- (START fades to black first: the raid begins behind it)
  waitFor(function() return X.state().phase == "intro" end, 600)
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  shot("f01_command")
  -- (a first turn played out - the boss strikes the copies - then the boss on its last HP)
  local turns, commands, lastPhase = 0, 0, nil
  while R.current() and R.current().phase ~= "catch" and turns < 3000 do
    local cur = R.current()
    if cur.phase == "command" and lastPhase ~= "command" then commands = commands + 1 end
    lastPhase = cur.phase
    local hurtNow = false
    for _, mm in ipairs(cur.members or {}) do
      if mm.mon and mm.orig and (tonumber(mm.mon.hp) or 0) < (tonumber(mm.orig.hp) or 0) then hurtNow = true end
    end
    if (hurtNow or commands >= 8) and cur.phase == "command" and cur.boss and cur.boss.mon then
      cur.boss.mon.hp = math.min(cur.boss.mon.hp, 1)
    end
    if cur.phase == "command" and cur.cmd and cur.cmd.actor and not cur.say then
      if cur.cmd.menu == "main" then R.choose("fight") else R.choose("move1") end
    end
    U.wait(2)
    turns = turns + 1
  end
  check(R.current() and R.current().phase == "catch", "the raid won")
  do
    local hurt = 0
    for _, mm in ipairs(R.current().members) do
      if mm.mon and mm.orig and (tonumber(mm.mon.hp) or 0) < (tonumber(mm.orig.hp) or 0) then hurt = hurt + 1 end
    end
    log("members hurt in the raid (their copies):", hurt, "turns of commands:", commands)
    for i, mm in ipairs(R.current().members) do
      log(("  member %d: copy hp %s / battler hp %s / disp %s, the save's %s / %s"):format(i, tostring(mm.mon and mm.mon.hp),
        tostring(mm.b and mm.b.hp), tostring(mm.b and mm.b.dispHp), tostring(mm.orig and mm.orig.hp), tostring(mm.orig and mm.orig.maxHp)))
    end
  end
  shot("f02_won")
  R.catchChoose("leave")
  waitFor(function() return R.current() and R.current().phase == "rewards" end, 3000)
  U.wait(30)
  R.endRewards()
  waitFor(function() return not X.state().active end, 3000)
  check(not X.state().active, "back on the field")
  local after = snapshot()
  check(differs(before, after, "after the raid") == 0, "the party and the box exactly as they were (every field, the order)")

  -- (2) the after-raid steps on the boxed one: levels set by hand (no Exp. comes from a raid)
  local ok = X.open(os.getenv("PROBE_BOSS") or "MEOWTH_4", { members = { { mon = boxed }, { mon = s0.party[1] } } })
  check(ok, "a raid with the boxed Torchic")
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local before2 = snapshot()
  local cur = R.current()
  local m = cur.members[1]
  check(m.orig == boxed, "member 1 is the boxed one")
  -- (Lv 16: Combusken; its moves from 16)
  boxed.level = 16
  pcall(function() boxed.exp = Pokemon.expForLevel and Pokemon.expForLevel(boxed.species, 16) or boxed.exp end)
  m.levelFrom, m.levelTo = 15, 16
  R.startAfter()
  local Scene3 = require("src.ui.game3.evolution_scene")
  waitFor(function() return Scene3.isOpen and Scene3.isOpen() end, 300)
  check(Scene3.isOpen and Scene3.isOpen(), "the evolution scene opens on the boxed one")
  U.wait(120)
  shot("f03_evolving")
  -- (through the scene and any words or questions: A)
  local presses = 0
  while X.state().active and presses < 400 do
    U.tap(game, "a"); U.wait(12)
    presses = presses + 1
    if presses == 30 then shot("f04_during") end
    local rr = R.current()
    if rr and rr.ask and presses % 10 == 0 then log("  asked:", tostring(rr.say)) end
  end
  shot("f05_after")
  check(not X.state().active, "the steps run through to the field")
  local sp = boxed.species
  local name = select(2, pcall(Pokemon.displayName, boxed))
  log("the boxed one is now", tostring(name), "species", tostring(sp), "level", tostring(boxed.level))
  check(storage.boxes[boxId].mons[boxSlot] == boxed, "still in its box slot")
  check(tostring(name):upper():find("COMBUSKEN") ~= nil, "it evolved (Combusken)")
  local after2 = snapshot()
  local n = 0
  for i = 1, #before2.party do if before2.ids[i] ~= after2.ids[i] or before2.party[i] ~= after2.party[i] then n = n + 1 end end
  check(n == 0 and #before2.party == #after2.party, "the party untouched by it")

  -- (3) the move picker: the boxed Combusken from Lv 16 to 28 (no evolution), its moves full
  local function moveIds(mon)
    local t = {}
    for i = 1, 4 do t[i] = tostring(mon.moves and mon.moves[i]) end
    return table.concat(t, ",")
  end
  ok = X.open(os.getenv("PROBE_BOSS") or "MEOWTH_4", { members = { { mon = boxed }, { mon = s0.party[1] } } })
  waitFor(function() return X.state().phase == "command" and not R.current().say end, 20000)
  local before3 = snapshot()
  local movesBefore = moveIds(boxed)
  m = R.current().members[1]
  boxed.level = 28
  pcall(function() boxed.exp = Pokemon.expForLevel and Pokemon.expForLevel(boxed.species, 28) or boxed.exp end)
  m.levelFrom, m.levelTo = 16, 28
  R.startAfter()
  local asked, picker = 0, false
  local SummaryMenu = require("src.ui.game3.summary_menu")
  presses = 0
  while X.state().active and presses < 600 do
    local rr = R.current()
    if rr and rr.ask and rr.ask.kind == "yesno" and not rr.askedSeen then
      rr.askedSeen = true
      asked = asked + 1
      log("  asked:", (tostring(rr.say):gsub("\n", " ")))
      if asked == 1 then shot("f06_learn_question") end
    end
    if rr and rr.aside and not picker then
      picker = true
      U.wait(30)
      shot("f07_move_picker")
    end
    U.tap(game, "a"); U.wait(10)
    presses = presses + 1
  end
  local movesAfter = moveIds(boxed)
  log("moves before", movesBefore, "after", movesAfter)
  check(asked > 0, "the move questions asked")
  check(picker, "the move picker (the game's summary) opened on the boxed one")
  check(movesAfter ~= movesBefore, "a move replaced on the boxed one")
  check(storage.boxes[boxId].mons[boxSlot] == boxed, "still in its box slot")
  local after3 = snapshot()
  n = 0
  for i = 1, #before3.party do if before3.ids[i] ~= after3.ids[i] or before3.party[i] ~= after3.party[i] then n = n + 1 end end
  check(n == 0 and #before3.party == #after3.party, "the party untouched by it")
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
