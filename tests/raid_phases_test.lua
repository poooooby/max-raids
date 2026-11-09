-- The raid's phases and menus (data/raid_phases.lua) against src/raid.lua and the drivers: every
-- `to` and Back names a real phase or menu; every phase says whether buttons, taps and the second
-- screen are handled, and raid.lua's handlers agree; raid.lua changes phase and menu only through
-- Rd.go / Rd.setMenu and only to known names; every phase and menu a driver compares is known.
--   luajit tests/raid_phases_test.lua   (from the repo root)

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

local P = assert(loadstring(read("data/raid_phases.lua"), "@data/raid_phases.lua"))()
local PH, MENUS = P.PHASES, P.MENUS

-- ------------------------------------------------------------------ the data itself

local FLAGS = { "input", "pointer", "second" }
for name, row in pairs(PH) do
  check(type(row.to) == "table", name .. ": has `to`")
  for to in pairs(row.to or {}) do check(PH[to] ~= nil, name .. " -> " .. to .. ": a known phase") end
  for _, k in ipairs(FLAGS) do
    check(type(row[k]) == "boolean", name .. ": `" .. k .. "` is true or false")
  end
end
-- every phase reachable from den or intro (the two ways in)
do
  local seen, queue = { den = true, intro = true }, { "den", "intro" }
  while #queue > 0 do
    local name = table.remove(queue)
    for to in pairs(PH[name].to) do
      if not seen[to] then seen[to] = true; queue[#queue + 1] = to end
    end
  end
  for name in pairs(PH) do check(seen[name], name .. ": reachable from den or intro") end
end
for name, row in pairs(MENUS) do
  check(type(row.ids) == "table", name .. ": has `ids`")
  local b = row.back
  check(b == false or b == "from" or b == "member" or MENUS[b] ~= nil, name .. ": Back goes somewhere known")
end

-- ------------------------------------------------------------------ src/raid.lua against it

local src = read("src/raid.lua")
local code = src:gsub("%-%-[^\n]*", "")   -- (comments out)

-- (a line assigning r.phase: it on the left of a lone `=`; Rd.go's own line is the one allowed)
local sets = {}
for line in code:gmatch("[^\n]+") do
  local lhs = line:match("^%s*([^=]-)%s*=[^=]")
  if lhs and lhs:find("r%.phase") then sets[#sets + 1] = line end
end
check(#sets == 1 and sets[1]:find("r%.phaseT"), "raid.lua sets r.phase only in Rd.go (" .. #sets .. " places)")
for name in code:gmatch("Rd%.go%(\"([%w_]+)\"%)") do
  check(PH[name] ~= nil, "Rd.go(\"" .. name .. "\"): a phase in the data")
end
for name in code:gmatch("Rd%.setMenu%(\"([%w_]+)\"") do
  check(MENUS[name] ~= nil, "Rd.setMenu(\"" .. name .. "\"): a menu in the data")
end
for name in code:gmatch("menu%s*=%s*\"([%w_]+)\"") do
  check(MENUS[name] ~= nil, "menu = \"" .. name .. "\": a menu in the data")
end
for name in code:gmatch("r%.phase%s*[=~]=%s*\"([%w_]+)\"") do
  check(PH[name] ~= nil, "r.phase compared to \"" .. name .. "\": a phase in the data")
end

-- the handlers raid.lua defines, by table: `function INPUT.x(` and `INPUT.x, INPUT.y = ...`
local function handlers(tbl)
  local have = {}
  for name in code:gmatch("function " .. tbl .. "%.([%w_]+)%(") do have[name] = true end
  for line in code:gmatch("[^\n]+") do
    local lhs = line:match("^%s*(" .. tbl .. "%.[%w_%., ]-)%s*=[^=]")
    if lhs then for name in lhs:gmatch(tbl .. "%.([%w_]+)") do have[name] = true end end
  end
  return have
end
for flag, tbl in pairs({ input = "INPUT", pointer = "POINTER", second = "SECOND" }) do
  local have = handlers(tbl)
  for name, row in pairs(PH) do
    check((row[flag] == true) == (have[name] == true),
      ("%s: `%s` %s in the data, %s in raid.lua"):format(name, flag, tostring(row[flag]), have[name] and "handled" or "not handled"))
  end
end

-- ------------------------------------------------------------------ the drivers' names

local function driverFiles()
  local p = io.popen('dir /b "tests\\drivers\\*.lua" 2>nul')
  local list = {}
  if p then
    for line in p:lines() do list[#list + 1] = line:gsub("%s+$", "") end
    p:close()
  end
  if #list == 0 then
    p = io.popen("ls tests/drivers/*.lua 2>/dev/null")
    if p then
      for line in p:lines() do list[#list + 1] = line:match("([^/\\]+)$") end
      p:close()
    end
  end
  return list
end
local files = driverFiles()
check(#files > 10, "found the drivers (" .. #files .. ")")
local phaseRefs, menuRefs = 0, 0
for _, f in ipairs(files) do
  local s = read("tests/drivers/" .. f)
  -- (game.phase is the engine's, not the raid's)
  for lhs, name in s:gmatch("([%w_%.%(%)]*)phase%s*[=~]=%s*\"([%w_]+)\"") do
    if not lhs:find("game%.$") and name ~= "boot" and name ~= "pressed" and name ~= "released" then
      phaseRefs = phaseRefs + 1
      check(PH[name] ~= nil, f .. ": phase \"" .. name .. "\" is a phase in the data")
    end
  end
  for name in s:gmatch("menu%s*[=~]=%s*\"([%w_]+)\"") do
    menuRefs = menuRefs + 1
    check(MENUS[name] ~= nil, f .. ": menu \"" .. name .. "\" is a menu in the data")
  end
end
check(phaseRefs > 50 and menuRefs > 20, ("the drivers' compares found (%d phases, %d menus)"):format(phaseRefs, menuRefs))

print(("%d/%d checks passed  (max_raids phases)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
