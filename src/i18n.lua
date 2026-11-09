-- The mod's own words in the LANGUAGE option's language (English, Japanese, Portuguese, Spanish,
-- German, or CUSTOM: the player's own file).
--
-- Keyed by the ENGLISH text, as Wilds of Hoenn's lib/i18n.lua: a call site keeps its English,
--
--   T("%s used %s!", name, move)
--
-- and a language file (data/lang/<code>.lua: `return { ["English"] = "translation", ... }`) maps
-- it. A line a language lacks falls back to the English. The same English with two meanings
-- takes a context: T.c("menu", "Back") looks up "menu|Back" first, then "Back".
--
-- Words in data tables (G-Max words, achievements ...) are English in the table and translated
-- where they are shown (T(W.field.FIRE)); a table of words in code marks each one with T.mark
-- (it returns the English as it is) so tools/i18n_keys.lua finds it.
--
-- A translation's format directives fill in argument order; another order numbers them
-- POSIX-style ("%2$s ... %1$s"). A translation with more directives than the English, or numbers
-- out of range or on only some, is not used (the English is). {MON}-style fields are the call
-- site's and are kept as they are.
--
-- CUSTOM reads `lang_custom.lua` from the mod's cache folder (mod_cache/max_raids/ beside the saves),
-- written the first time CUSTOM is chosen: `return { base = "en", strings = { ["English"] = "..." } }`,
-- every line set to the base language's. A line it lacks falls back to the base, then English.
-- It is read again at every den, so an edit shows without restarting.
--
-- Text drawn with the game's own Gen 3 font (option labels, the field's message box, the PC's
-- menu) goes through T.game: its font has no ã / õ, which are drawn as a / o.
--
--   I = i18n({ read = mod:read, cache = mod.cache, log = fn })

return function(deps)
  deps = deps or {}
  local I = {}

  I.LANGUAGES = { "en", "ja", "pt", "es", "de", "custom" }
  -- the option's choices, each in its own language (CUSTOM in the game's capitals)
  I.NAMES = { en = "ENGLISH", ja = "にほんご", pt = "PORTUGUÊS", es = "ESPAÑOL", de = "DEUTSCH", custom = "CUSTOM" }
  I.CUSTOM_FILE = "lang_custom.lua"
  I.TEMPLATE = "data/lang/template.lua"

  local FONT_FALLBACK = { ["ã"] = "a", ["õ"] = "o", ["Ã"] = "A", ["Õ"] = "O" }

  local current = "en"
  local files = {}      -- [code] = table | false (missing)
  local custom          -- { base = code, strings = table } | nil

  -- a data file: a chunk with nothing in its environment, returning a table
  local function loadData(source, name)
    if type(source) ~= "string" then return nil, "missing" end
    local env = {}
    local chunk, err = load(source, "@" .. name, "t", env)
    if not chunk then return nil, err end
    if setfenv then setfenv(chunk, env) end
    local ok, data = pcall(chunk)
    if not ok then return nil, data end
    if type(data) ~= "table" then return nil, "it does not return a table" end
    return data
  end
  I.loadData = loadData

  local function log(fmt, ...)
    if deps.log then pcall(deps.log, fmt, ...) end
  end

  local function strings(t)
    local out = {}
    for k, v in pairs(t) do
      if type(k) == "string" and type(v) == "string" then out[k] = v end
    end
    return out
  end

  local function shipped(code)
    if code == "en" or code == "custom" then return nil end
    local hit = files[code]
    if hit == nil then
      local source = deps.read and deps.read("data/lang/" .. code .. ".lua")
      local data, err = loadData(source, "data/lang/" .. code .. ".lua")
      if not data then log("data/lang/%s.lua could not be read (%s): its lines stay English; reinstall the mod", code, tostring(err)) end
      hit = data and strings(data) or false
      files[code] = hit
    end
    return hit or nil
  end

  local function known(code)
    for _, c in ipairs(I.LANGUAGES) do if c == code then return true end end
    return false
  end

  -- the template's lines in `base` (English where it has none), as a custom file's source
  local function templateSource(base)
    local source = deps.read and deps.read(I.TEMPLATE)
    local keys = source and loadData(source, I.TEMPLATE)
    if type(keys) ~= "table" then return nil end
    local list = {}
    for k, v in pairs(keys) do if type(k) == "string" and type(v) == "string" then list[#list + 1] = k end end
    table.sort(list)
    local lang = shipped(base) or {}
    local out = {
      "-- Galar Rising's words, yours to change (LANGUAGE: CUSTOM). Each line is",
      "--   [\"the English\"] = \"what to show\",",
      "-- Change the right side only. A line taken out shows the base language's words. %s, %d",
      "-- and {MON}-style fields are filled in by the game; keep them (\"%2$s ... %1$s\" changes their order).",
      "-- Read again at every den, so a change shows the next time you open one.",
      "-- base: the language for lines missing here: en, ja, pt, es or de.",
      "return {",
      ("  base = %q,"):format(base),
      "  strings = {",
    }
    for _, k in ipairs(list) do
      out[#out + 1] = ("    [%q] = %q,"):format(k, lang[k] or k)
    end
    out[#out + 1] = "  },"
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
  end

  --- Reads the custom file again (writing it from the template first when there is none).
  function I.refresh()
    if current ~= "custom" then return end
    local cache = deps.cache
    local source
    if cache and cache.read then
      local ok, got = pcall(cache.read, cache, I.CUSTOM_FILE)
      source = ok and type(got) == "string" and got or nil
    end
    if not source then
      source = templateSource("en")
      if source and cache and cache.write then
        local ok, res, err = pcall(cache.write, cache, I.CUSTOM_FILE, source)
        if ok and res then
          log("LANGUAGE CUSTOM: wrote %s to edit", I.customPath())
        else
          log("LANGUAGE CUSTOM: %s could not be written (%s): English shows", I.customPath(), tostring(ok and err or res))
        end
      end
    end
    local data, err = loadData(source, I.CUSTOM_FILE)
    if not data then
      log("LANGUAGE CUSTOM: %s could not be read (%s): fix the file or delete it for a fresh one", I.customPath(), tostring(err))
      custom = nil
      return
    end
    local base = type(data.base) == "string" and known(data.base) and data.base ~= "custom" and data.base or "en"
    custom = { base = base, strings = strings(type(data.strings) == "table" and data.strings or {}) }
  end

  --- Where the custom file is, for the log (the folder that holds the game's saves: the game's own
  --- folder when it runs portable, else the system's save folder for it).
  function I.customPath()
    return "mod_cache/max_raids/" .. I.CUSTOM_FILE .. " (in the folder that holds your saves)"
  end

  --- Sets the language (anything unknown -> English).
  function I.setLanguage(code)
    current = known(code) and code or "en"
    if current == "custom" then I.refresh() else custom = nil end
    return current
  end

  function I.language() return current end

  local function lookup(key, english)
    local t, s
    if current == "custom" then
      if custom then
        s = custom.strings[key]
        if s == nil and key ~= english then s = custom.strings[english] end
        if s ~= nil then return s end
        t = shipped(custom.base)
      end
    else
      t = shipped(current)
    end
    if not t then return nil end
    s = t[key]
    if s == nil and key ~= english then s = t[english] end
    return s
  end

  -- the directives of a format string, in order (%% skipped)
  local function directives(s)
    local list = {}
    for spec in s:gsub("%%%%", ""):gmatch("%%([%d%$%-%.]*[sdif])") do list[#list + 1] = spec end
    return list
  end

  -- a translation's format usable with the English's arguments, else nil
  local okFormat = {}
  local function formatOf(english, translated)
    local key = english .. "\0" .. translated
    local hit = okFormat[key]
    if hit ~= nil then return hit or nil end
    local src, dst = directives(english), directives(translated)
    local numbered = 0
    for _, d in ipairs(dst) do if d:find("%$") then numbered = numbered + 1 end end
    local ok
    if numbered == 0 then
      ok = #dst <= #src
    elseif numbered == #dst then
      ok = true
      for _, d in ipairs(dst) do
        local n = tonumber(d:match("^(%d+)%$"))
        if not n or n < 1 or n > #src then ok = false end
      end
    else
      ok = false
    end
    okFormat[key] = ok and translated or false
    return ok and translated or nil
  end

  local function fill(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return fmt end
    if not fmt:find("%%%d+%$") then return string.format(fmt, ...) end
    local args = { ... }
    return (fmt:gsub("%%(%d+)%$([%-%.%d]*[sdif])", function(i, spec)
      return string.format("%" .. spec, args[tonumber(i)])
    end))
  end

  local function say(key, english, ...)
    if english == nil then return "" end
    if current ~= "en" then
      local s = lookup(key, english)
      if s then
        local fmt = formatOf(english, s)
        if fmt then return fill(fmt, ...) end
      end
    end
    return fill(english, ...)
  end

  --- I.mark(english) -> english: a word in a table, translated where it is shown.
  function I.mark(english) return english end
  --- I.c(context, english, ...): "<context>|<english>" first.
  function I.c(context, english, ...) return say(context .. "|" .. english, english, ...) end
  --- I.game(english, ...): for the game's own font (ã / õ drawn as a / o).
  function I.game(english, ...)
    return (say(english, english, ...):gsub("[\xC3][\x83\x95\xA3\xB5]", FONT_FALLBACK))
  end
  --- I.cgame(context, english, ...): both (the option labels: "option" / "choice").
  function I.cgame(context, english, ...)
    return (say(context .. "|" .. english, english, ...):gsub("[\xC3][\x83\x95\xA3\xB5]", FONT_FALLBACK))
  end

  setmetatable(I, { __call = function(_, english, ...) return say(english, english, ...) end })
  I.t = function(english, ...) return say(english, english, ...) end
  return I
end
