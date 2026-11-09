-- The translatable words (src/i18n.lua's keys), collected from the code and data, written as
-- data/lang/template.lua (English -> English, by source): the list a translator copies and the
-- custom file's lines. Run from the repo root:
--
--   luajit tools/i18n_keys.lua           writes data/lang/template.lua
--   luajit tools/i18n_keys.lua --check   lists what each data/lang/<code>.lua lacks / has stale /
--                                        breaks (directives, {FIELDS}); exits 1 on any
--
-- Found: T("..."), T.mark("..."), T.game("..."), T.c("ctx", "..."), T.cgame("ctx", "...") with one
-- double-quoted literal each (a context makes the key "ctx|English"); main.lua's option labels
-- ("option|X") and choices ("choice|X"); the data tables in DATA. Keys from T.game / T.cgame are
-- drawn with the game's own font: Japanese there is kana only (GAME_FONT in the template).

local K = {}

K.CODE = { "main.lua" }
K.SRC_DIR = "src"
-- data tables shown through T at their use: file, then a path of fields ("*" any key; a trailing
-- "*" collects every string under it); `fields` keeps only those keys of the rows reached
K.DATA = {
  { file = "data/raid_gmax.lua", path = { "WORDS" } },
  { file = "data/raid_team_moves.lua", path = { "WORDS" } },
  -- (the achievements framework's pop-up and list: its font may be the game's, so kana there)
  { file = "data/raid_achievements.lua", path = { "list", "*" }, fields = { "title", "description", "unit", "category" },
    game = true },
}
K.LANGS = { "ja", "pt", "es", "de" }
K.TEMPLATE = "data/lang/template.lua"

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function listSrc()
  local out = {}
  local p = io.popen('ls "' .. K.SRC_DIR .. '"')
  if p then
    for name in p:lines() do
      if name:match("%.lua$") and name ~= "i18n.lua" then out[#out + 1] = K.SRC_DIR .. "/" .. name end
    end
    p:close()
  end
  table.sort(out)
  return out
end

-- the Lua string literal starting at i (a double quote): its value and the index after it
local function literalAt(s, i)
  local j = i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" or c == "\n" then return nil end
    if c == "\\" then j = j + 2
    elseif c == '"' then break
    else j = j + 1 end
  end
  local chunk = load("return " .. s:sub(i, j))
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  if not ok or type(v) ~= "string" then return nil end
  return v, j + 1
end

-- strip comments so commented-out calls are not keys (strings kept as they are)
local function stripComments(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c or d == "\n" then break
        else j = j + 1 end
      end
      out[#out + 1] = s:sub(i, j)
      i = j + 1
    elseif s:sub(i, i + 1) == "--" then
      local long = s:match("^%-%-%[(=*)%[", i)
      if long then
        local close = s:find("]" .. long .. "]", i, true)
        i = close and close + #long + 2 or n + 1
      else
        local nl = s:find("\n", i, true)
        i = nl or n + 1
      end
    elseif s:match("^%[=*%[", i) then
      local eq = s:match("^%[(=*)%[", i)
      local close = s:find("]" .. eq .. "]", i, true)
      local j = close and close + #eq + 1 or n
      out[#out + 1] = s:sub(i, j)
      i = j + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local CALLS = {
  { pat = "%f[%w_%.]T%s*%(%s*\"", ctx = false, game = false },
  { pat = "%f[%w_%.]T%.t%s*%(%s*\"", ctx = false, game = false },
  { pat = "%f[%w_%.]T%.mark%s*%(%s*\"", ctx = false, game = false },
  { pat = "%f[%w_%.]T%.game%s*%(%s*\"", ctx = false, game = true },
  { pat = "%f[%w_%.]T%.c%s*%(%s*\"", ctx = true, game = false },
  { pat = "%f[%w_%.]T%.cgame%s*%(%s*\"", ctx = true, game = true },
}

-- keys: list of { key, source, game }; seen[key] = entry
local function collector()
  local C = { list = {}, seen = {}, bad = {} }
  function C.add(key, source, game)
    local e = C.seen[key]
    if e then
      if game then e.game = true end
      return
    end
    e = { key = key, source = source, game = game or false }
    C.seen[key] = e
    C.list[#C.list + 1] = e
  end
  return C
end

local function scanCode(C, path)
  local raw = readFile(path)
  if not raw then C.bad[#C.bad + 1] = path .. ": missing"; return end
  local s = stripComments(raw)
  for _, call in ipairs(CALLS) do
    local init = 1
    while true do
      local a, b = s:find(call.pat, init)
      if not a then break end
      local q = b -- the opening quote
      local v, after = literalAt(s, q)
      if not v then
        C.bad[#C.bad + 1] = ("%s: an unreadable literal at byte %d"):format(path, q)
        init = b + 1
      else
        if call.ctx then
          local q2 = s:find('"', after, true)
          local between = q2 and s:sub(after, q2 - 1)
          local v2, after2 = nil, nil
          if between and between:match("^%s*,%s*$") then v2, after2 = literalAt(s, q2) end
          if v2 then
            C.add(v .. "|" .. v2, path, call.game)
            after = after2
          end
          -- (T.c("ctx", variable): the variable's words are collected where they are written)
        else
          C.add(v, path, call.game)
        end
        init = after
      end
    end
  end
end

-- main.lua's option rows: their labels and choices (the LANGUAGE row's choices are names)
local function scanOptions(C)
  local s = stripComments(readFile("main.lua") or "")
  local a = s:find("local function defineOptions", 1, true)
  local b = a and s:find("mod.options:define(schema)", a, true)
  if not (a and b) then C.bad[#C.bad + 1] = "main.lua: no defineOptions"; return end
  local block = s:sub(a, b)
  local starts = {}
  for p in block:gmatch("(){ key = \"") do starts[#starts + 1] = p end
  for i, p in ipairs(starts) do
    local row = block:sub(p, (starts[i + 1] or #block + 1) - 1)
    local key = row:match('key = "([%w_]+)"')
    local label = row:match('label = "([^"]+)"')
    if label then C.add("option|" .. label, "main.lua", true) end
    local choices = row:match("choices = (%b{})")
    if choices and key ~= "language" then
      for word in choices:gmatch('{%s*"([^"]+)"%s*,') do C.add("choice|" .. word, "main.lua", true) end
    end
  end
end

local function walk(C, node, path, k, fields, source, game)
  if k > #path then
    local function all(t)
      if type(t) == "string" then C.add(t, source, game)
      elseif type(t) == "table" then
        local keys = {}
        for kk in pairs(t) do keys[#keys + 1] = kk end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        for _, kk in ipairs(keys) do
          if not fields or type(t[kk]) ~= "string" or (function() for _, f in ipairs(fields) do if f == kk then return true end end end)() then
            all(t[kk])
          end
        end
      end
    end
    all(node)
    return
  end
  if type(node) ~= "table" then return end
  local step = path[k]
  if step == "*" then
    local keys = {}
    for kk in pairs(node) do keys[#keys + 1] = kk end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    for _, kk in ipairs(keys) do walk(C, node[kk], path, k + 1, fields, source, game) end
  else
    walk(C, node[step], path, k + 1, fields, source, game)
  end
end

local function scanData(C, d)
  local src = readFile(d.file)
  local chunk = src and load(src, "@" .. d.file)
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  if not ok or type(t) ~= "table" then C.bad[#C.bad + 1] = d.file .. ": could not be loaded"; return end
  walk(C, t, d.path, 1, d.fields, d.file, d.game)
end

function K.collect()
  local C = collector()
  scanOptions(C)
  for _, path in ipairs(K.CODE) do scanCode(C, path) end
  for _, path in ipairs(listSrc()) do scanCode(C, path) end
  for _, d in ipairs(K.DATA) do scanData(C, d) end
  return C
end

function K.render(C)
  local out = {
    "-- Galar Rising's words (generated by tools/i18n_keys.lua; do not edit by hand).",
    "-- A language is data/lang/<code>.lua: the same keys, each mapped to its translation:",
    "--   [\"English\"] = \"translation\",",
    "-- \"ctx|English\" keys are English with a context (option labels, choices ...): translate the",
    "-- part after the bar. Keep %s / %d (or number them: \"%2$s ... %1$s\") and {MON}-style fields.",
    "-- GAME_FONT lists the keys drawn with the game's own Gen 3 font: Japanese there in kana only.",
    "return {",
  }
  local last
  for _, e in ipairs(C.list) do
    if e.source ~= last then
      out[#out + 1] = "  -- " .. e.source
      last = e.source
    end
    out[#out + 1] = ("  [%q] = %q,"):format(e.key, e.key)
  end
  out[#out + 1] = "  GAME_FONT = {"
  for _, e in ipairs(C.list) do
    if e.game then out[#out + 1] = ("    [%q] = true,"):format(e.key) end
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  return table.concat(out, "\n"):gsub("\\\n", "\\n") .. "\n"
end

-- the directives of a format string, in order (%% skipped)
local function directives(s)
  local list = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%([%d%$%-%.]*[sdif])") do list[#list + 1] = spec end
  return list
end
function K.formatOk(english, translated)
  local src, dst = directives(english), directives(translated)
  local numbered = 0
  for _, d in ipairs(dst) do if d:find("%$") then numbered = numbered + 1 end end
  if numbered == 0 then return #dst == #src end
  if numbered ~= #dst then return false end
  local used = {}
  for _, d in ipairs(dst) do
    local n = tonumber(d:match("^(%d+)%$"))
    if not n or n < 1 or n > #src then return false end
    used[n] = true
  end
  for n = 1, #src do if not used[n] then return false end end
  return true
end
local function fields(s)
  local list = {}
  for f in s:gmatch("{[%u_]+}") do list[#list + 1] = f end
  table.sort(list)
  return table.concat(list, " ")
end
function K.fieldsOk(english, translated) return fields(english) == fields(translated) end

-- a language file's problems: { missing = {...}, stale = {...}, broken = {...} }
function K.checkLang(C, code)
  local path = "data/lang/" .. code .. ".lua"
  local src = readFile(path)
  local chunk = src and load(src, "@" .. path, "t", {})
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  local res = { missing = {}, stale = {}, broken = {}, unreadable = not (ok and type(t) == "table") }
  if res.unreadable then return res end
  for _, e in ipairs(C.list) do
    local v = t[e.key]
    if type(v) ~= "string" then
      res.missing[#res.missing + 1] = e.key
    else
      local english = e.key:match("^[%w_]+|(.*)$") or e.key
      if not K.formatOk(english, v) then res.broken[#res.broken + 1] = e.key .. "  (its %s / %d)"
      elseif not K.fieldsOk(english, v) then res.broken[#res.broken + 1] = e.key .. "  (its {FIELDS})" end
    end
  end
  for k in pairs(t) do
    if type(k) == "string" and not C.seen[k] then res.stale[#res.stale + 1] = k end
  end
  table.sort(res.stale)
  return res
end

if arg and arg[0] and arg[0]:match("i18n_keys%.lua$") then
  local C = K.collect()
  for _, b in ipairs(C.bad) do io.stderr:write("warn: ", b, "\n") end
  if arg[1] == "--check" then
    local bad = 0
    local current = readFile(K.TEMPLATE)
    if current ~= K.render(C) then
      print(K.TEMPLATE .. " is out of date: run luajit tools/i18n_keys.lua")
      bad = bad + 1
    end
    for _, code in ipairs(K.LANGS) do
      local r = K.checkLang(C, code)
      if r.unreadable then
        print(code .. ": unreadable"); bad = bad + 1
      else
        print(("%s: %d missing, %d stale, %d broken"):format(code, #r.missing, #r.stale, #r.broken))
        for _, k in ipairs(r.missing) do print("  missing  " .. k) end
        for _, k in ipairs(r.stale) do print("  stale    " .. k) end
        for _, k in ipairs(r.broken) do print("  broken   " .. k) end
        bad = bad + #r.missing + #r.stale + #r.broken
      end
    end
    os.exit(bad == 0 and 0 or 1)
  else
    local f = assert(io.open(K.TEMPLATE, "wb"))
    f:write(K.render(C))
    f:close()
    local game = 0
    for _, e in ipairs(C.list) do if e.game then game = game + 1 end end
    print(("%s: %d keys (%d in the game's font)"):format(K.TEMPLATE, #C.list, game))
  end
end

return K
