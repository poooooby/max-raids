-- Galar Rising's achievements over a stand-in recomp_achievements: the definitions (the framework's
-- limits, the counts, the Quick Work numbers the text names), what each moment and the save's win
-- counts award, a save that is not up yet, and a framework that fails.
--   luajit tests/achievements_test.lua   (from the repo root)

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function loadFile(path) return assert(loadstring(read(path), "@" .. path))() end

local passed, failed = 0, 0
local function check(ok, what)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. what) end
end

local data = loadFile("data/raid_achievements.lua")
local make = loadFile("src/achievements.lua")

-- ------------------------------------------------------------------ the definitions

do
  local ids, points, hidden, counters = {}, 0, {}, {}
  for _, row in ipairs(data.list) do
    check(not ids[row.id], row.id .. ": a unique id")
    ids[row.id] = row
    points = points + row.points
    check(#row.id <= 48 and row.id:match("^[a-z0-9_%-]+$") ~= nil, row.id .. ": an id the framework takes")
    check(#row.title >= 1 and #row.title <= 32, row.id .. ": a title of 32 or fewer")
    check(#row.description >= 1 and #row.description <= 160, row.id .. ": a description of 160 or fewer")
    check(row.points >= 0 and row.points <= 100 and row.points % 1 == 0, row.id .. ": points 0..100")
    check(row.category and #row.category <= 16, row.id .. ": a category of 16 or fewer")
    check(not (row.title .. row.description):find("[^\32-\126]"), row.id .. ": plain ASCII text")
    check(row.goal == nil or (row.goal >= 1 and row.goal % 1 == 0 and row.unit ~= nil), row.id .. ": a goal with its unit")
    if row.hidden then hidden[#hidden + 1] = row.id end
    if row.goal then counters[row.id] = row.goal end
  end
  check(#data.list == 14, "14 achievements")
  check(points == 175, "175 points in all")
  table.sort(hidden)
  check(#hidden == 2 and hidden[1] == "blown_away" and hidden[2] == "quick_work", "Quick Work and Blown Away are hidden")
  check(counters.den_delver == 25 and counters.gallery == 10, "the two counters: 25 raids, 10 bosses")
  local q = data.QUICK
  local qd = ids.quick_work.description
  check(qd:find(q.MIN_STARS .. "-star", 1, true) and qd:find(q.TURNS .. " turns", 1, true),
    "Quick Work's text names its own numbers (" .. q.MIN_STARS .. "-star, " .. q.TURNS .. " turns)")
end

-- ------------------------------------------------------------------ a stand-in framework

-- opts.saveUp = false: the framework's save is not up (unlock answers no_save); opts.broken: its calls error
local function world(opts)
  opts = opts or {}
  local W = { unlocks = {}, progress = {}, earned = {}, store = {}, handlers = {}, registered = nil, saveUp = opts.saveUp ~= false }
  local goals = {}
  local handle = {}
  function handle.registerMany(_, list)
    W.registered = list
    for _, d in ipairs(list) do goals[d.id] = d.goal end
    return #list, {}
  end
  function handle.unlock(_, id)
    if opts.broken then error("boom") end
    W.unlocks[#W.unlocks + 1] = id
    if not W.saveUp then return nil, "no_save", "no save" end
    if W.earned[id] then return nil, "already_unlocked", "" end
    W.earned[id] = true
    return true
  end
  function handle.setProgress(_, id, n)
    if opts.broken then error("boom") end
    W.progress[id] = n
    if goals[id] and n >= goals[id] then W.earned[id] = true end
    return true
  end
  local api = { apiVersion = "1.2.0", events = { ready = "ach.ready" } }
  function api.supports() return true end
  function api.connect() return handle end
  local mod = { log = { info = function() end, warn = function() end } }
  function mod.find(_, id)
    if id == "recomp_achievements" and not opts.absent then return { exports = api } end
  end
  mod.save = {
    get = function(_, key) return W.store[key] end,
    set = function(_, key, v) W.store[key] = v end,
  }
  mod.events = { on = function(_, name, fn) W.handlers[name] = fn end }
  W.mod = mod
  W.ready = function() W.saveUp = true; if W.handlers["ach.ready"] then W.handlers["ach.ready"]() end end
  W.count = function(id) local n = 0; for _, u in ipairs(W.unlocks) do if u == id then n = n + 1 end end; return n end
  return W
end

local STARS = { MACHAMP_2 = 3, GRIMMSNARL_2 = 3, CHARIZARD_4 = 4, DURALUDON_2 = 5, MEOWTH_4 = 1,
  ["DYNA:RATICATE:1"] = 1, ["DYNA:MEWTWO:5:L"] = 5, ["DYNA:ONIX:5"] = 5 }

local function build(opts)
  local W = world(opts)
  local A = make(W.mod, { data = data, stars = function(key) return STARS[key] end,
    wins = function() return W.store.wins end })
  return W, A
end

-- ------------------------------------------------------------------ install

do
  local W, A = build({ absent = true })
  check(A.install() == false and not A.active(), "no framework: not installed")
  A.note("den"); A.note("won", { key = "MACHAMP_2", sim = { faints = 0, turnNo = 3 } })
  check(next(W.store) == nil and #W.unlocks == 0, "no framework: a note does nothing, not even a save write")
end

do
  local W, A = build()
  check(A.install() and A.active(), "the framework found: installed")
  check(W.registered and #W.registered == 14, "all 14 registered")
  check(W.registered[6].goal == 25 and W.registered[6].unit == "RAIDS", "a counter registered with its goal and unit")
  W.registered[1].title = "changed"
  check(data.list[1].title == "Into the Den", "the registered rows are copies")
end

-- ------------------------------------------------------------------ the moments

do
  local W, A = build()
  A.install(); W.ready()
  A.note("den")
  check(W.count("first_den") == 1, "a den opened: Into the Den")
  A.note("dynamax", false)
  check(W.count("go_big") == 1 and W.count("gigantamax") == 0, "a Dynamax: Go Big only")
  A.note("dynamax", true)
  check(W.count("gigantamax") == 1, "a Gigantamax: Gigantamax!")
  A.note("caught", false)
  check(W.count("gotcha_giant") == 1 and W.count("shiny_raider") == 0, "a catch: Gotcha, Giant! only")
  A.note("caught", true)
  check(W.count("shiny_raider") == 1, "a shiny catch: Shiny Raider")
  A.note("ran")
  check(W.count("blown_away") == 1, "Run: Blown Away")
  A.note("den"); A.note("dynamax", true); A.note("ran")
  check(W.count("first_den") == 1 and W.count("gigantamax") == 1 and W.count("blown_away") == 1,
    "a moment already awarded is not asked for again")
  check(W.store.achievements and W.store.achievements.flags.first_den and W.store.achievements.flags.blown_away,
    "the one-off moments are kept in the save")
  A.note("nonsense")
end

-- ------------------------------------------------------------------ a raid won

do
  local function won(key, faints, turn)
    local W, A = build()
    A.install(); W.ready()
    W.store.wins = { [key] = 1 }
    A.note("won", { key = key, sim = { faints = faints, turnNo = turn } })
    return W
  end
  local W = won("MACHAMP_2", 0, 3)
  check(W.count("untouched") == 1, "no knock-out: Untouched")
  check(W.count("quick_work") == 1, "a 3-star in 3 turns: Quick Work")
  check(W.count("first_raid") == 1 and W.count("giant_slayer") == 1, "the win is the first and a Gigantamax boss's")
  W = won("MACHAMP_2", 1, 3)
  check(W.count("untouched") == 0 and W.count("quick_work") == 1, "a knock-out: no Untouched, Quick Work stands")
  W = won("MACHAMP_2", 0, 4)
  check(W.count("quick_work") == 0 and W.count("untouched") == 1, "4 turns: no Quick Work")
  W = won("MEOWTH_4", 0, 2)
  check(W.count("quick_work") == 0, "a 1-star in 2 turns: no Quick Work (3 stars at least)")
  W = won("DYNA:ONIX:5", 2, 3)
  check(W.count("quick_work") == 1 and W.count("five_star") == 1 and W.count("giant_slayer") == 0,
    "a red 5-star in 3 turns: Quick Work and Five-Star General, not Giant Slayer")
  W = won("DYNA:MEWTWO:5:L", 0, 6)
  check(W.count("crystal_clear") == 1 and W.count("five_star") == 1, "a crystal's legendary raid: Crystal Clear (and 5 stars)")
  W = won("DYNA:RATICATE:1", 0, 6)
  check(W.count("crystal_clear") == 0 and W.count("five_star") == 0 and W.count("giant_slayer") == 0, "a red 1-star: none of them")
  W = won("CHARIZARD_4", 0, 4)
  check(W.count("five_star") == 0, "a 4-star: not Five-Star General")
end

-- ------------------------------------------------------------------ the save's win counts

do
  local W, A = build()
  A.install()
  W.store.wins = { MACHAMP_2 = 3, GRIMMSNARL_2 = 1, ["DYNA:RATICATE:1"] = 20, CHARIZARD_4 = 0 }
  W.ready()
  check(W.count("first_raid") == 1, "an older save: its first win counted when the save loads")
  check(W.progress.den_delver == 24, "...24 raids won of 25")
  check(W.progress.gallery == 2, "...2 different Gigantamax bosses (a red den's boss is not one, nor a boss with no win)")
  check(W.count("giant_slayer") == 1, "...a Gigantamax boss defeated")
  A.note("won", { key = "MACHAMP_2", sim = { faints = 1, turnNo = 9 } })
  check(W.progress.den_delver == 24, "a sweep is idempotent while the wins are the same")
  W.store.wins.MACHAMP_2 = 4
  A.note("won", { key = "MACHAMP_2", sim = { faints = 1, turnNo = 9 } })
  check(W.progress.den_delver == 25 and W.earned.den_delver, "the 25th win: Den Delver done")
  local before = #W.progress
  A.sweep()
  check(W.progress.den_delver == 25, "a counter that is done is left alone")
  local gal = {}
  for i = 1, 12 do gal["BOSS" .. i] = 1; STARS["BOSS" .. i] = 3 end
  W.store.wins = gal
  A.sweep()
  check(W.progress.gallery == 10 and W.earned.gallery, "12 bosses: the counter stops at its goal of 10 and is done")
end

-- ------------------------------------------------------------------ a save that is not up yet

do
  local W, A = build({ saveUp = false })
  A.install()
  A.note("dynamax", true)
  check(W.store.achievements and W.store.achievements.flags.go_big and W.store.achievements.flags.gigantamax,
    "before the framework's save is up: the moments are kept in the save")
  check(not W.earned.go_big, "...and not awarded yet")
  A.sweep()
  check(not W.earned.go_big, "a sweep before the save is ready does nothing")
  W.ready()
  check(W.earned.go_big and W.earned.gigantamax, "when its save is ready: awarded")
  W.ready()
  check(W.count("go_big") == 3, "(asked at the note, the first ready and the second: the framework answers already unlocked)")
end

-- ------------------------------------------------------------------ a framework that fails

do
  local W, A = build({ broken = true })
  A.install(); W.ready()
  local ok = pcall(function()
    A.note("den"); A.note("dynamax", true); A.note("won", { key = "MACHAMP_2", sim = { faints = 0, turnNo = 3 } })
    A.note("caught", true); A.note("ran"); A.sweep()
  end)
  check(ok, "a framework that errors never throws into the game")
  A.note("won", nil)
  A.note("won", {})
  check(true, "a raid with nothing in it is no error")
end

print(("%d/%d checks passed  (max_raids achievements)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
