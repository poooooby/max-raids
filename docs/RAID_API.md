# Galar Rising — Raid API (v1.0.0)

Another Gen1Recomp mod can add raids of its own through this API:

- a den at a place it chooses, on any map;
- the den's beam colour and look, and its sprites;
- the raid's Pokémon: any species, one of Galar Rising's 37 Gigantamax forms, or the mod's own
  animated sprite sheet;
- its star level, level, moves, ability, nature, IVs, held item, shininess, HP, catch and music;
- the rewards, added to the usual roll or replacing it;
- what happens when it ends.

A mod can also start a raid at any moment, for example from a script, an item or a person.

Everything here runs on the player's machine. Nothing is sent anywhere.

## 1. Declare the dependency

```json
"optional_dependencies": ["max_raids@>=0.6.0"]
```

This makes the loader run Galar Rising before your mod when it is installed. Your mod still loads
without it. Use `"dependencies"` instead if your mod makes no sense without raids.

## 2. Find the API and check the version

```lua
return function(mod)
  local found = mod.find("max_raids")
  if not found or not found.exports.connect then return end        -- not installed, or too old
  local raids = found.exports
  local major = tonumber(tostring(raids.apiVersion):match("^(%d+)"))
  if major ~= 1 then return end                                     -- written for 1.x
  local h = raids.connect(mod)                                      -- your handle
```

`raids.supports(name)` returns true for `bosses`, `dens`, `open`, `art`, `rewards` and `events`.

`raids.connect(mod)` gives your mod its handle. Your bosses and dens are kept apart from every other
mod's by your mod's id. Your handle reads art files from your own mod's folder through `mod:read`.

Every handle call returns its value (or `true`), or `nil, code, message`. No call throws for an
ordinary mistake. Log the message: it says what to fix.

Register your bosses and dens **every time the game starts**. They aren't saved; only a den's day is
(spent or not, and the boss chosen for that day).

## 3. Bosses

```lua
local key, code, msg = h:boss("ember_king", {
  species = "CHARIZARD",          -- an id ("RATICATE_ALOLA") or a National Dex number; or form = ...
  stars = 4,                      -- 1 to 5: the barriers, the catch odds, the badge-free tier
  name = "Ember King",            -- shown in place of the species' name (up to 24 characters)
  level = 60,                     -- else the tier's band
  moves = { "FLAMETHROWER", "AIR_SLASH", "DRAGON_PULSE", "ROOST" },   -- 1 to 4; else a wild one's
  ability = "SOLAR_POWER",        -- else none (raid bosses have none)
  nature = "MODEST",              -- else neutral
  ivs = 31,                       -- all six, or { hp = 31, spa = 31 }; else the tier's roll
  item = "CHARCOAL",              -- a held item, by name or number
  shiny = false,                  -- true / false, or the odds as a number (1 in n); else 1 in 4096
  hp = 1.5,                       -- a factor on top of the tier's (and RAID DIFFICULTY's)
  catch = "roll",                 -- "roll" (the tier's odds), "sure", or false (no catch)
  music = "max",                  -- "basic", "max" or "legend"
  script = "strong",              -- "basic", "strong" or "fierce": how often it uses its Max Move
  gmax = "WILDFIRE",              -- a G-Max Move for its Max Move turns; else from its best move
  gmaxFactor = false,             -- the Gigantamax Factor on the one caught
  turns = 10, faints = 4,         -- when the raid is lost
  types = { "FIRE", "DRAGON" },   -- else the species'
})
-- key == "EXT:<your mod id>:ember_king"
```

Give exactly one of `species` or `form`:

- **`species`** draws the game's own sprite of that species as a red Dynamax boss. A star level is
  needed.
- **`form`** is one of Galar Rising's Gigantamax bosses (`raids.bosses()` lists them, such as
  `"CHARIZARD_4"`). It keeps that form's animation, cry, stars and G-Max Move. Your fields replace
  any of them.

A boss's name is letters, digits, `_` and `-`, up to 48. Registering the same name again replaces
the boss.

The species, the moves and the item are checked the first time the boss is used, because the game's
data may not be loaded while mods load. To check them yourself once the game is up, call
`h:check("ember_king")`. It returns `true`, or `nil, code, message`.

### Your own art

```lua
h:boss("crystal_onix", { species = "ONIX", stars = 3, art = {
  sheet = "assets/raid/crystal_onix.png",          -- in your mod's folder
  cell = 192, frames = 40, cols = 10,              -- square frames, left to right, top to bottom
  speed = 2,                                       -- each frame's length in 1/20 s
  height = 8.8,                                    -- metres: how big it stands (6.5-8.5 x a member's size)
  shiny = "assets/raid/crystal_onix_shiny.png",    -- optional; without it, never shiny
  cry = "assets/raid/crystal_onix.ogg",            -- optional; else its species' cry, deepened
  icon = "assets/raid/crystal_onix_icon.png",      -- optional; two square frames side by side
  cloud = "pink",                                  -- the cloud over it: "pink" (Gigantamax) or "red"
} })
```

The art needs a `species` for its types, stats and catch. The boss's feet are measured from the
first frame's opaque pixels, so leave space under the feet blank. Galar Rising's own sheets in
`assets/bosses/` are a good model.

## 4. Dens

```lua
h:den("lake_den", {
  map = "EM_ROUTE120", x = 21, y = 34,     -- a walkable or water cell, no warp and no person on it
  boss = "ember_king",                     -- your boss's name, its key, or any key the raid knows
  beam = { color = { 0.3, 1, 0.6 },        -- the glow (each 0-1)
           core = { 1, 1, 1 },             -- the column's heart
           spark = { 0.8, 1, 0.9 },        -- the sparks rising in it
           height = 200, width = 1.5,      -- 16-400 px; 0.25-4 x the usual
           sparks = 16, flicker = 0.5 },   -- 0-40; 0 (steady) to 2
  sprite = { active = "MYMOD_DEN", spent = "MYMOD_DEN_SPENT" },   -- optional: sprites you registered
  refresh = "daily",                       -- "daily": live again each day; "never": once beaten, gone quiet
  active = true,                           -- false: quiet ("nothing here") until you set it
  awake = false,                           -- true: hidden until the first badge's awakening
  rewards = { ... },                       -- see 5
  onEnd = function(info) ... end,          -- see 6
})
```

- `beam` may also be `"red"`, `"purple"` or `false` (no beam). Fields you leave out keep the red
  beam's look.
- Your den appears on any map, a town or indoors as well as a route. RAID DENS OFF hides every den,
  yours too. The first-badge awakening waits only for dens that ask for it (`awake = true`).
- A cell that's blocked when the map loads is skipped, and the log says why.

For a different boss each day, pass a function as `boss`. It is asked once a day with
`ctx = { day, badges, stars, map, rng }`, where `stars` lists the tiers the player's badges allow
and `rng(lo, hi)` is seeded by the save and day. Return a key, a boss's name, or a boss spec table
(registered as `<den id>_day`):

```lua
boss = function(ctx)
  local list = { "ember_king", "crystal_onix" }
  return list[ctx.rng(1, #list)]
end
```

Change a den later with `h:setDen(id, patch)`. The patch can hold `active`, `boss`, `beam`,
`sprite`, `rewards`, `onEnd`, or `done = false` (live again now). `h:removeDen(id)` takes it away.
`h:denState(id)` gives `{ live, active, done, day, boss }`.

## 5. Rewards

```lua
rewards = {
  mode = "add",                                  -- "add" to the tier's roll, or "replace" it
  items = { { "MASTER_BALL", 1 }, { 68, 3 } },   -- by name or number, n 1-999
  money = 5000,
  roll = function(ctx) return { { "RARE_CANDY", ctx.stars } } end,
}
```

- `roll` is called at the win with `ctx = { key, stars, rng, firstWin, faints, turns }`.
- An item the game doesn't have is left out, and the log says which.
- The rewards card lists every row.
- Rewards go on a den (`h:den`) or a single raid (`h:open`), not on a boss.

## 6. When a raid ends

`onEnd(info)` is called once, as the raid closes and the player is back on the field:

| Field | |
|---|---|
| `outcome` | `"win"`, `"faints"` (four knock-outs), `"storm"` (out of turns), `"fled"` (Run), or `"closed"` |
| `caught` | whether the boss was caught; `mon` is the Pokémon given (party or PC) |
| `key`, `mod`, `den` | the boss's key, your mod's id, the den's id (nil for `h:open`) |
| `turns`, `faints`, `shiny` | how the raid went |
| `items` | the rewards card's rows `{ id, n, name, money }` |

Every raid, any mod's or Galar Rising's own, is also announced as an event that any mod can listen
for, with the same `info`:

```lua
mod.events:on("mod.max_raids.raid_start", function(info) ... end)
mod.events:on("mod.max_raids.raid_end", function(info) ... end)
```

## 7. A raid now

```lua
local ok, code = h:open("ember_king", { denScreen = true, rewards = { ... }, onEnd = function(info) end })
```

- `denScreen = true` (the default) opens the den screen first, so the player picks their four.
- `false` goes straight into the raid with the first four of the party.
- You can pass a boss spec table in place of a key.
- `busy` means a raid is already open.

## 8. How it fits the rest

- A win counts toward Raid Rookie, Den Delver, Untouched, Quick Work, Gotcha and Shiny Raider. It
  never counts toward Giant Slayer, the Gigantamax Gallery, Five-Star General or Crystal Clear.
- RAID DIFFICULTY applies to your bosses: Solo raises their HP and attacks and makes every catch
  sure.
- A Dynamax Crystal used at your den gives a legendary raid instead, and your rewards and `onEnd`
  stand aside for it.

## Codes

`bad_spec`, `bad_name`, `bad_species`, `bad_form`, `bad_stars`, `bad_level`, `bad_move`,
`bad_ability`, `bad_nature`, `bad_ivs`, `bad_item`, `bad_shiny`, `bad_hp`, `bad_catch`,
`bad_music`, `bad_script`, `bad_gmax`, `bad_rules`, `bad_types`, `bad_art`, `bad_map`,
`bad_cell`, `bad_beam`, `bad_sprite`, `bad_refresh`, `bad_rewards`, `unknown_boss`,
`unknown_den`, `busy`, `no_raid`, `no_dens`, `bad_mod`, `error`.
