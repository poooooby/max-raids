-- Driver: LANGUAGE. In each language (PROBE_LANGS, default ja,pt,es,de,custom) the den screen, the
-- commands, the moves, a turn's words, the catch's choice and the rewards card are shot
-- (<lang>_1den .. <lang>_6card); the words checked translated (not the English) and no error.
-- CUSTOM: its file written to the mod's cache with every line, an edit read at the next den.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/max_raids/tests/drivers/language_probe.lua love .

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
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s0 = Runtime.getSession()
  if #(s0.party or {}) == 0 then
    for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_ZIGZAGOON", "SPECIES_WINGULL", "SPECIES_RALTS" }) do
      Party.giveMon(s0, C:require("species", sp), 60)
    end
  end
  pcall(Bag.add, s0, C:require("items", "ITEM_ULTRA_BALL"), 5)
  U.wait(10)
  local X = game.mods.exports.max_raids
  local R = X.raid
  local T = X.T
  local boss = os.getenv("PROBE_BOSS") or "CHARIZARD_4"
  local langs = {}
  for code in (os.getenv("PROBE_LANGS") or "ja,pt,es,de,custom"):gmatch("[%w_]+") do langs[#langs + 1] = code end

  -- every character of every language drawable: the raid's font (LOVE's default face) or its
  -- fallback (the engine's Plain Pixel)
  do
    local face = love.graphics.newFont(16)
    local okP, pp = pcall(love.graphics.newFont, "assets/fonts/plainpixel/PlainPixel-Regular.ttf", 16)
    check(okP, "the fallback font loads")
    for _, code in ipairs({ "ja", "pt", "es", "de" }) do
      local src = love.filesystem.read("mods/max_raids/data/lang/" .. code .. ".lua")
      local t = src and load(src, "@" .. code, "t", {})
      t = t and t()
      local missing, seen = {}, {}
      for _, v in pairs(type(t) == "table" and t or {}) do
        if type(v) == "string" then
          local k = 1
          while k <= #v do
            local b0 = v:byte(k)
            local len = b0 < 192 and 1 or b0 < 224 and 2 or b0 < 240 and 3 or 4
            local ch = v:sub(k, k + len - 1)
            k = k + len
            if b0 >= 32 and not seen[ch] then
              seen[ch] = true
              if not (face:hasGlyphs(ch) or (okP and pp:hasGlyphs(ch))) then missing[#missing + 1] = ch end
            end
          end
        end
      end
      check(#missing == 0, code .. ": every character drawable (" .. #missing .. " not: " .. table.concat(missing, " ") .. ")")
    end
  end

  for _, code in ipairs(langs) do
    check(X.setLanguage(code) == code, code .. ": set")
    check(T("Leave the den?") ~= "Leave the den?" or code == "custom", code .. ": its words (" .. T("Leave the den?") .. ")")
    -- the den screen
    check(R.openDen({ active = true, boss = boss, stars = 4 }), code .. ": the den screen opens")
    U.wait(40)
    shot(code .. "_1den")
    R.denStart()
    waitFor(function() local c = R.current(); return c and c.phase == "command" and not c.say end, 20000)
    check(R.current() and R.current().phase == "command", code .. ": the commands")
    U.wait(10)
    shot(code .. "_2commands")
    R.choose("fight")
    U.wait(10)
    shot(code .. "_3moves")
    -- a turn: each member its first move
    for _ = 1, 4 do
      local c = R.current()
      if not (c and c.phase == "command") then break end
      if c.cmd.menu ~= "moves" then R.choose("fight"); U.wait(2) end
      R.choose("move1")
      U.wait(4)
      c = R.current()
      for k = 1, 4 do
        c = R.current()
        if not (c and c.cmd and c.cmd.menu == "target") then break end
        R.choose("move" .. k)
        U.wait(4)
      end
    end
    do local c = R.current(); log(code .. ": after the picks", c and c.phase, c and c.cmd and c.cmd.menu, c and c.say) end
    local said = nil
    waitFor(function() local c = R.current(); said = c and c.say; return said ~= nil and c.phase == "battle" end, 900)
    U.wait(30)
    shot(code .. "_4turn")
    check(said ~= nil, code .. ": a turn's words (" .. tostring(said) .. ")")
    if code == "ja" then check(said and said:find("[\128-\255]") ~= nil, "ja: the turn's words in Japanese") end
    R.startCatch()
    U.wait(30)
    shot(code .. "_5catch")
    R.catchChoose("leave")
    waitFor(function() local c = R.current(); return c and c.phase == "rewards" end, 900)
    U.wait(90)
    shot(code .. "_6card")
    if X.state().active then X.close() end
    waitFor(function() return not X.state().active end, 300)
    U.wait(20)
  end

  -- CUSTOM: an edit read at the next den
  do
    X.setLanguage("custom")
    local fs = require("src.core.SaveData").persistenceFs(love.filesystem)
    local path = "mod_cache/max_raids/lang_custom.lua"
    local src = fs.read(path)
    check(type(src) == "string" and src:find('["Leave the den?"]', 1, true) ~= nil, "custom: the file written with its lines")
    if src then
      local edited, n = src:gsub('%["Leave the den%?"%] = "[^"]*"', '["Leave the den?"] = "Out of here?"')
      log("custom: edit lines", n, "write", tostring(fs.write(path, edited)))
      log("custom: written back", tostring((fs.read(path) or ""):find("Out of here?", 1, true)), "language", X.language())
      R.openDen({ active = true, boss = boss, stars = 4 })
      U.wait(5)
      check(T("Leave the den?") == "Out of here?", "custom: an edit read at the next den")
      X.close()
      fs.write(path, src)
    end
  end
  X.setLanguage("en")
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
