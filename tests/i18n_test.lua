-- src/i18n.lua and the language files: the lookup, fallbacks, numbered directives, contexts, the
-- game font's letters, CUSTOM (its file written, read, its base); data/lang/template.lua current
-- (tools/i18n_keys.lua), each language complete, nothing stale, every directive and {FIELD} kept.
--   luajit tests/i18n_test.lua   (from the repo root)

local fails, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then fails = fails + 1; print("FAIL " .. what) end
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local makeI18n = assert(loadfile("src/i18n.lua"))()

-- a stand-in mod: files by path, a cache in memory
local files = {
  ["data/lang/es.lua"] = 'return { ["Fight"] = "Luchar", ["%s used %s!"] = "¡%s usó %s!",'
    .. ' ["%s gave %s to %s."] = "%3$s recibió %2$s de %1$s.", ["menu|Back"] = "Atrás", ["Back"] = "Volver",'
    .. ' ["Too many %s"] = "%s %s %s", ["Field {MON}"] = "Campo {MON}", ["Mão"] = "Mão" }',
  ["data/lang/pt.lua"] = 'return { ["Hand"] = "Mão" }',
  ["data/lang/template.lua"] = 'return { ["Fight"] = "Fight", ["Run"] = "Run", GAME_FONT = { ["Run"] = true } }',
}
local cache = { files = {} }
function cache:read(k) return self.files[k] end
function cache:write(k, v) self.files[k] = v; return true end
local logs = {}
local I = makeI18n({ read = function(p) return files[p] end, cache = cache,
  log = function(fmt, ...) logs[#logs + 1] = fmt:format(...) end })

check(I("Fight") == "Fight", "English: as it is")
check(I("%s used %s!", "A", "B") == "A used B!", "English: filled")
check(I.setLanguage("xx") == "en", "an unknown language is English")
I.setLanguage("es")
check(I("Fight") == "Luchar", "Spanish: its line")
check(I("Run") == "Run", "Spanish: a line it lacks falls back to the English")
check(I("%s used %s!", "A", "B") == "¡A usó B!", "Spanish: filled")
check(I("%s gave %s to %s.", "A", "B", "C") == "C recibió B de A.", "numbered directives reorder")
check(I("Too many %s", "x") == "Too many x", "more directives than the English: the English")
check(I.c("menu", "Back") == "Atrás", "a context's own line")
check(I.c("other", "Back") == "Volver", "a context it lacks: the plain English's line")
check(I.t("Field {MON}") == "Campo {MON}", "I.t is the call")
check(I.mark("Fight") == "Fight", "mark returns the English")
I.setLanguage("pt")
check(I("Hand") == "Mão", "Portuguese in a LOVE font keeps ã")
check(I.game("Hand") == "Mao", "the game's font: ã drawn as a")
check(I.cgame("option", "Hand") == "Mao", "cgame: a context and the game's font")

-- CUSTOM: written from the template the first time, then read; base for the rest
I.setLanguage("custom")
local written = cache.files["lang_custom.lua"]
check(type(written) == "string" and written:find('["Fight"] = "Fight"', 1, true) ~= nil, "CUSTOM: the file written from the template")
check(written and not written:find("GAME_FONT", 1, true), "CUSTOM: the template's GAME_FONT list left out")
check(I("Fight") == "Fight", "CUSTOM: its lines (English to begin)")
cache.files["lang_custom.lua"] = 'return { base = "es", strings = { ["Run"] = "¡Corre!" } }'
I.refresh()
check(I("Run") == "¡Corre!", "CUSTOM: an edited line, read again")
check(I("Fight") == "Luchar", "CUSTOM: a line it lacks from its base")
check(I("%s used %s!", "A", "B") == "¡A usó B!", "CUSTOM: the base's format")
cache.files["lang_custom.lua"] = 'return { strings = { ["Run"] = '
I.refresh()
check(I("Run") == "Run", "CUSTOM: an unreadable file is English")
check(#logs > 0 and logs[#logs]:find("could not be read", 1, true) ~= nil, "CUSTOM: an unreadable file is logged")
cache.files["lang_custom.lua"] = 'os.exit(1) return {}'
I.refresh()
check(I("Run") == "Run", "CUSTOM: a file reaching for the environment is refused")
I.setLanguage("en")

-- the real files
local K = assert(loadfile("tools/i18n_keys.lua"))()
local C = K.collect()
check(#C.bad == 0, "the scanner read every call (" .. table.concat(C.bad, "; ") .. ")")
check(#C.list > 100, "the scanner found the words (" .. #C.list .. ")")
check(readFile(K.TEMPLATE) == K.render(C), K.TEMPLATE .. " is current (run luajit tools/i18n_keys.lua)")
for _, code in ipairs(K.LANGS) do
  local r = K.checkLang(C, code)
  check(not r.unreadable, code .. ": readable")
  if not r.unreadable then
    check(#r.missing == 0, ("%s: every line (%d missing: %s)"):format(code, #r.missing, table.concat(r.missing, " | "):sub(1, 400)))
    check(#r.stale == 0, ("%s: no stale lines (%s)"):format(code, table.concat(r.stale, " | "):sub(1, 400)))
    check(#r.broken == 0, ("%s: directives and fields kept (%s)"):format(code, table.concat(r.broken, " | "):sub(1, 400)))
  end
end
-- Japanese in the game's font: kana (and the font's own marks) only, no kanji
do
  local src = readFile("data/lang/ja.lua")
  local ja = src and load(src, "@ja", "t", {})
  ja = ja and ja()
  local tpl = load(readFile(K.TEMPLATE), "@template", "t", {})()
  local bad = {}
  if type(ja) == "table" then
    for key in pairs(tpl.GAME_FONT or {}) do
      local v = ja[key]
      if type(v) == "string" then
        for cp in v:gmatch("[\xE4-\xE9][\x80-\xBF][\x80-\xBF]") do bad[#bad + 1] = key; break end
      end
    end
  end
  check(#bad == 0, "ja: the game font's lines in kana only (" .. table.concat(bad, " | ") .. ")")
end

print(("%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
