# CLAUDE.md

`max_raids` (Max Raids), a Lua mod for **gen1recomp** (engine checkout `~\Documents\GitHub\gen1recomp`,
LÖVE 11.5). The repo is `~\Documents\GitHub\max-raids`, installed into the engine as a directory
junction `gen1recomp/mods/max_raids` -> this repo. **Gen 3 only** (Emerald, FireRed, LeafGreen, Ruby,
Sapphire). **Depends on `national_dex_gen3`** (`~\Documents\GitHub\national_dex_gen3`) for modern species,
moves, the Fairy type (id 18) and abilities. Permission `engine_internals`.

Sword / Shield's Max Raid Battles: a giant Gigantamax boss (the Giga Megas pack, 37 forms) against four
of the party in a 3D den, on a layer of the mod's own over the field, drawn at window resolution. Split
out of PlayNav (`~\Documents\GitHub\g1r-ds-touch`) on 2026-10-26 (Wooble); the plan is
`~\.claude\plans\id-like-to-see-iterative-hummingbird.md`.

## Decisions (Wooble)

- **One screen.** Everything is on the main window. Option BATTLE PAD (`battle_pad`, main | second)
  sends the command menu to the device's second screen, like Kanto Gear, and leaves the main window
  the whole den. The second-screen path isn't built yet: port PlayNav's `surface.lua` async readback,
  `main.lua` 1667-1709 and `second_gate.lua`.
- **Dens in the overworld,** generated on routes: 1–2 per outdoor route, seeded per save, saved once
  chosen, refreshing daily. Star tiers open with badges.
- **Party.** The player picks 4 at the den. They fight as **simulated copies** (full HP, real stats and
  moves); the save changes only by the rewards.
- **Rewards.** Catch the boss (one throw), items, EVs, Exp.
- **Bosses.** Only the Giga Megas pack's forms, with full animation, cries, attack motions by type, and
  engine-drawn shader field effects.
- **Camera.** Low and close, pointed up at the giant. Party Pokémon stand where the trainers stand in
  Sword / Shield. The intro: close on the party, pull back down to the ground looking up the boss, the
  roar (cry, burst, shake), "X appeared!", then over the first member's shoulder. Reference: Wooble's
  `Downloads\maxraidref.mp4` and the cave image in the PlayNav session.
- **Kanto Gear stands down** while a raid is up. Never touch Kanto Gear's code: use only its public
  modules API.

## Map

- `main.lua`
  - Options; `loadSibling` (a mod can't `require` its own files: `mod:read` + `load`).
  - Builds the modules.
  - **The layer:** `Stack.push("max_raids", Layer, { hideBelow = true, fullscreen = true })` on open,
    `Stack.pop` on close. `Layer = { isMenu, handleInput, update, draw }`. `draw` paints black in the
    240x160 pass. `update(dt)` is the engine's update, outside the draw; the den renders there.
  - **`render.hud` wrap:** after `next`, draws `Raid.draw(G, vp.width, vp.height)` over the whole window,
    and calls `PadHide:apply` every frame.
  - **`input.pointer` wrap:** taps and clicks go to `Raid.pointer`; returns true when the pad takes one.
  - **Kanto Gear:** `mod:find("kanto_gear").exports.modules.register{ id = "max_raids", available =
    false (no Store tile), open = false, shown = Raid.active }`. The Gear's `anyShown()` makes it stand
    down entirely while `shown()` is true.
  - **Exports:** `open(key)`, `close()`, `state()`, `bosses()`, `raid`, `_test{ scene, pad, rules }`.
- `src/raid.lua` (Rd), the controller.
  - **The boss.** `Rd.load(key)` loads `assets/bosses/<KEY>.png`, the quads per frame, and the opaque
    box of frame 1 measured on the CPU (the feet). `Rd.release()` frees it; one boss in memory at a time.
    `Rd.frameAt(key, t)` animates it: AnimationSpeed × `ANIM_UNIT_S` 1/20 s a frame.
  - **Its cry:** `Rd.cry(key)` plays the pack's `.ogg` at `Audio._sfxVolume`.
  - **The four.** `Rd.lineup()` takes the first 4 party mons that aren't eggs, from
    `Runtime.getSession().party`.
  - **Their pictures** come from `Pokemon.monBackPic(mon)`, **fetched in `Rd.update`, never in a draw**.
    g9-battle-sprites-gen3 redraws the frame into a canvas on each call, and a setCanvas inside a draw
    breaks Android. The opaque box is read back once through a dpiscale-1 canvas, also in update.
  - **The intro** timeline is `Rd.INTRO`, fired through `once()`. Music is the first of `Rd.SONGS` the
    game has (`Audio.songs()`, `fadeOutAndPlay`); `Audio.restoreMapSong()` on close.
  - **The HUD:** boss name, shape-drawn stars (the default font has no ★), HP bar, and a Gen 5 dialogue
    box that types out and keeps clear of the pad.
  - **Input:** `Rd.input` (B flees), `Rd.pointer`.
- `src/dens.lua` (Dn), dens on the routes.
  - **Pure parts** (tested headless by `tests/dens_test.lua`):
    - `Dn.pick(view, seed)`: 1–2 spots, `DENS.EDGE` in from the border, `WARP_GAP` from warps and
      `SPREAD` apart. A map too small gets none.
      - The view: `{ w, h, warps, open(x, y), grass(x, y), reserved(x, y), ground(x, y), water(x, y) }`.
      - **Always** (Wooble 2026-10-26): neither the den nor the four cells the player talks to it from
        is reserved. Grass is allowed: the den is drawn over it.
      - **The passes** (`DENS.PASSES`), tried best first:
        - `clear`: 5×5 open, plain ground or grass 1 cell round;
        - `tight`: 3×3 open, the same;
        - `last`: 3×3 open, plain ground or grass needed only under the den itself.
        - `water` (Wooble 2026-10-26: water is fine on a larger body), tried after `clear`: every cell
          within `water` 3 (a 7×7) is calm water, so never a channel or a narrow river.
        - A pass may still set `grass`, a radius kept clear of grass; none does now.
    - `Dn.roll(den, day, badges, rng)`: active `DENS.ACTIVE` (70%) of days, a tier from `BADGE_STARS`
      by badges, then a boss of that tier.
    - `Dn.rng(seed)`: an LCG warmed four steps, because its first draw from neighbouring seeds rose
      almost in step. `Dn.seedOf(str)` hashes a string seed.
  - **Which maps** (`Dn.isRoute`, Wooble 2026-10-26: no towns, no Safari Zone). The map type is ROUTE (3) or
    OCEAN_ROUTE (6) (`Dn.ROUTE_TYPES`): never a town (1), a city (2), underwater (5) or indoors; and no
    map id with SAFARI (the zone's areas are type 3). Without a map type, a map id with ROUTE.
  - **Placement.** Spots are chosen once from the active map (`Dn.viewOf(mapId, def)`), seeded by
    trainer id + map id, and saved in `mod.save "dens"[mapId] = { v, {x, y, pass, day, active, stars,
    boss, done} }`.
    - `open`: `Collision.isWalkable`, not `isWater`, not `warpAt`, nothing at `Objects.at`.
    - `water`: `Collision.isWater`, a surfable behaviour (`isSurfable`), not DEEP_WATER (dive spots),
      a current, a waterfall or NO_SURFACING (`roughWater`, by `MB.id`), no warp, no object.
    - `grass`: `Collision.isGrass`, or `Encounters.terrainAt == "land"`.
    - `ground`: `Collision._mapDef.midLayout:midAt(x, y)` equals the map's commonest open, grassless
      metatile, or the cell is grass. On Emerald that metatile is `0x1`; the trails are `0x121`,
      `0x124`, `0x129`.
    - `reserved` (`reservedOf`), over the map's own objects (`Objects._order` / `_byId`, runtime ones left
      out):
      - every object's wander box: start ± `rangeX` / `rangeY`, + `RESERVE_PAD`;
      - for a trainer (`TrainerSight.isTrainerType`): from every cell of that box, all four directions
        (it may turn), `sight` (`eo.sight` / `def.trainerRange`) + `SIGHT_PAD` long;
      - the map's `coordEvents` tiles (cutscene triggers), + `RESERVE_PAD`.
    - `list.v ~= Dn.PLACE_V` (now 5): a map placed under older rules is placed again.
    - Each saved den is `{ x, y, pass, day, active, stars, boss, done }`.
  - **The day.** A den re-rolls when `den.day ~= Dn.today()`: the cart's RTC days on Ruby, Sapphire and
    Emerald, the device date otherwise.
  - **Spawning.** `mod.world:spawnNpc` with one of two sprites, Wooble's art in `assets/den/`
    (32×32, anchor 16, `Dn.ANCHOR_Y` 31):
    - `MAX_RAIDS_DEN` / `MAX_RAIDS_DEN_SPENT`, files `den_active.png` / `den_spent.png`;
      `Dn.spriteFor(den)` picks by state.
    - **Measured in the engine** (a red marker drawn by the actor, 2026-10-26): Gen 3 draws an object
      lower than `SpriteRenderer:getScreenOrigin` suggests. With anchorY 31 the den's bottom row
      sat on the tile's MIDDLE (y + 8), so the grass cover (the tile's bottom 8 rows) fell wholly
      below it. 23 puts its bottom row on the tile's foot.
    - The beam's foot is at the pit, 11 px above the den's foot (`self.y - 3`).
    - Again after a load: the alive check scans `Objects.runtimeByMap[mapId]` for the object's id.
    - The npc handle's `setAppearance` swaps active and spent.
    - `Dn.ensure()` runs from `input.step` while `Dn.pending` is set (by `map.entered`), and returns nil
      to retry until the field runs.
  - **A on a den.** The `world.talk` hook finds the den by object id (`Dn.byObject`) and calls
    `deps.open(den)` = `Raid.openDen`.
  - **The beam.** A field actor added by wrapping `FieldEffects.collectActors`: a solid column with a
    glow and sparks, red from 3★, purple below. `Dn.beamDraws` counts its draws for the probe.
  - **Grass: open.** For now the den is drawn over grass (Wooble 2026-10-26). Tried and dropped:
    the engine's grass field effect (`tall_grass` / `long_grass` front rows, as the NPC feet cover)
    drawn in front of a den lowered to the tile's foot (anchorY 23) - it looked worse; and before
    that, grass versions of the den's sprite (removed from assets/den/). The engine still draws its NPC
    grass cover (`collectActors` section 2) over the den's own cell's bottom 8 rows, which at
    anchorY 31 sits below the den.
  - **Done.** `Dn.finish(den)` marks a den done (the spent look).
  - **Badges.** `Flags.forVersion(Profile.forSession(nil).id).BADGES` flags, read with
    `Flags.getFlag(store)`.
- The den screen (`raid.lua`, phase "den").
  - `Rd.openDen(den)` puts the layer up. A quiet den just says so.
  - It shows the boss as a black silhouette with a red rim (a silhouette shader), its stars and types,
    and the party to pick up to four from; the first four start ticked.
  - START (`Rd.denStart`) begins the intro with them; BACK leaves.
  - Up / down, A toggles, START, B; taps on the rows and buttons (`Rd.denWhere`).
  - Presses are ignored for `DEN_ARM_S` (0.25 s) after it opens: the A that opened it was toggling the
    first row.
- `src/raid_scene.lua` (Sc), the den in 3D, built in code in metres.
  - **Geometry:** a plateau (superellipse rim, cliff), the cave floor, walls with a tunnel mouth and a
    ceiling, stalagmites and stalactites, boulders, the boss's pad (metal, a glowing ring, rim lights).
  - **Lighting** per vertex: `lit()`, an ambient, a key light from the upper left, the pad's warm glow,
    fog.
  - **Camera shots:** `Sc.shot(name | "member" i | pose, dur)` eases eye, look-at and FOV
    (smootherstep). Shots are `field`, `close`, `reveal`, `boss` and `wide`; `memberShot(i)` is over
    a shoulder. `Sc.shake(amp, dur)`, `Sc.burst()` (the roar), `Sc.setTime(t)`.
  - **Drawing over the 3D, in 2D at projected points:** the light shaft; the motes (one mesh moved by
    a vertex shader, no `VertexPosition` in its format, see Conventions); the boss (`drawBoss`: shadow,
    pad glow, a red silhouette-shader halo and outline, wisps, swirling streaks, sparks); the members
    (`drawMember`: one pixel scale for all, `MEMBER_PIC_H` 1.75 m per 64-px pic, shadow, breath);
    the vignette. `Sc.drawFlat` is the fallback without 3D.
  - **Sizes.** Boss size = `MEMBER_H` 1.1 × `Rd.sizeOf(key)` (6.5–8.5 by the pack's Height,
    `data/raid_rules.lua` SIZE). Pad at z −9.2, r 3.4. Members in an arc at z −0.75 / −1.25.
- `src/render3d.lua` + `src/g3d/` (copied from PlayNav; g3d is MIT). A colour+depth canvas per size,
  `prepare(scene, setup)` in update, `draw` places the picture.
- `src/pad.lua`, the battle pad.
  - FIGHT / ITEM / FLEE, Gen 5 colours. FIGHT and ITEM are greyed until the battle exists.
  - `Pad.draw(G, w, h, r)` draws it in the lower right and returns its rect. `Pad.drawFull` fills a
    whole screen, for the second-screen path. `Pad.hit(x, y)` tests against the last draw;
    `Pad.where`.
- `src/hd.lua`: `HD.drawPixel` draws nearest or sharp-bilinear pixel art at any scale (from PlayNav).
- `src/pad_hide.lua`: hides the engine's TouchControls while a raid's pad is on the main screen, and
  restores **exactly the previous `enabled`**. The PlayNav original re-read the options, which left a
  pad turned on by a launch flag off.
- `data/raid_sprites.lua` (generated by `tools/raid_pack.py`): per pack key, frames, cell, grid,
  AnimationSpeed, the FrontSprite / ShadowSprite metrics, the Giga BaseStats (Essentials order HP, Atk,
  Def, Spe, SpA, SpD), types, height and form name.
- `data/raid_bosses.lua`: `ORDER`; per key `national`, `name`, modern `types`, `stars` (tiers by Giga
  stat total), `moves` (names), `gmax`, `script`. Move names need checking against national_dex_gen3's
  ids (`Moves.numForName`).
- `data/raid_rules.lua` (`N.RAID` + `EVIDENCE`, classes verified / inferred / ours): turns 10, faints 4,
  shield ×0.25, break −2, the STARS table, segments, cheer, pouch, rewards, scripts, SIZE.
- `assets/bosses/`: 37 sheets (normal and shiny, grids ≤ 2048 px wide; Corviknight re-cut from a
  247.3-px pitch), `icons/`, `cries/`. `tools/raid_pack.py "<…>\2.0 Giga Megas Pack Gen 9.zip"` rebuilds
  them, reading the zip directly. Credits are in README and `assets/credits.txt`.

## Engine facts that matter

- **National Dex Gen 3** (`exports.slotOf(idOrDex)`, after its `game.ready`):
  - **Species.** `Pokemon.speciesFromNational(dex)` gives the slot (Lucario = 512). Slots run dex + 64
    for #387+, and `Pokemon.types` / `Pokemon.stats` take them. `Constants.of(v):require("species",
    "SPECIES_CINDERACE")` does **not** know the new species.
  - **Moves.** 419 moves at indices 355+: `Moves.get(name)`, `Moves.numForName`. Category stays split
    by type, Gen 3's rule; there's no per-move physical/special split. Its move extras (stat changes,
    drain, hits) are private: keep our own table for the boss moves that need them.
  - **Fairy** is type 18 in the engine's chart.
  - **Abilities.** The real ones apply through `Damage.base`, but only when `opts.adapter` is set.
  - There are **no Max or G-Max moves and no Gigantamax forms**; ours.
- **Damage.** `src/core/game3/battle/damage.lua` `Damage.calc(att, def, move, opts)`.
  - `move` can be a table; `opts.power` / `opts.moveType` override; `rng(lo, hi)`;
    `forceCrit` / `noCrit`; `weatherKind`.
  - Pass a real `Adapter.new(st, say)` (`battle/adapter.lua:124`, `st = { player, enemy, weather,
    badges = {}, rng }`). Look `Damage.calc` up from the module each call: wraps are applied after load.
  - Our loop applies itself:
    - the immunity abilities (Levitate, Wonder Guard, Volt/Water Absorb, Flash Fire);
    - the `battle.damage` abilities (Adaptability, Filter, Multiscale…);
    - accuracy (`Ctx:accuracyCheck`'s formula with `Rules.ACCURACY_STAGE`).
- **Battlers.** `State.makeBattler(mon)` holds the **same** table as the party mon: pass copies.
- **Dens.**
  - Place: `mod.world:spawnNpc(mapId, {x, y, sprite, movement})` gives depth and collision, but isn't
    saved: re-spawn per map load.
  - Art: `mod.content.sprites:register(id, {image, frameWidth, frameHeight, anchorX, anchorY})`.
  - A press: the `world.talk` hook (don't call `next` to take it).
  - The beam: an actor added by wrapping `FieldEffects.collectActors` (see
    `wilds-of-hoenn/lib/engine_patch.lua:340`).
  - Cells: `mod.world:mapOverview()` (`isWalkableCell`, `isWarpTileCell`) and
    `Dataset.isOutdoorMapType`.
  - Map ids: `EM_ROUTE101`, `FR_ROUTE_1`, …
- **Day.** `Rtc.calcLocalTime(s).days` on Ruby, Sapphire and Emerald; the device date on FireRed and
  LeafGreen (`national_dex_gen3/src/clock.lua`). Save: `mod.save:get` / `set`.
- **Audio.**
  - Cries: `Audio.playCry(slot)`; national_dex_gen3 plays #387+ from its pack.
  - Songs: `Audio.songs()[name]`. FireRed/LeafGreen `MUS_VS_LEGEND` / `MUS_VS_MEWTWO`; Ruby/Sapphire
    `MUS_VS_REGI` / `MUS_VS_KYOGRE_GROUDON`; Emerald adds `MUS_VS_RAYQUAZA`.
- **Kanto Gear's modules API** gives a Store tile plus stand-down only; **it can't host another mod's
  panel**. A second-screen pad has to push its own frames (`ctx.secondScreen` from a `render.compose`
  wrap: `push(imageData, w, h, 0, "secondary")` then `release()`, `pollTouch()` → "action,x,y").

## Conventions

- **Never `setCanvas` inside a draw** (Android draws the rest of the frame small in a corner). Render in
  update (`Layer.update` → `Rd.update` → `Scene.prepare`); the draw only places. Canvases read back to
  measure use `{ dpiscale = 1 }`.
- **A mesh with custom vertex attributes must not also declare `VertexPosition`.** The attribute
  declared alongside it read as zeros in LÖVE 11.5 (found on PlayNav's rain).
- **Uniforms:** send them only when they change; a number rather than a table where possible (a table
  `send` makes garbage each frame).
- **Garbage:** no `{ f() }` or `{ ... }` table constructors in per-frame code. The Thor runs LuaJIT
  with the JIT off.
- **Never `error()` in a callback:** `mod.log:warn` with a remediation.
- **Comments say what the code does,** with no attribution or history quotes. `.modkitignore` names
  every file under tests/ and tools/ one by one, plus CLAUDE.md and README.md.

## Loop

```sh
cd ~/Documents/GitHub/gen1recomp
python tools/modkit.py validate mods/max_raids --base imported
python tools/modkit.py lint mods/max_raids
SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 PROBE_TOUCH=1 \
POKEPORT_DRIVER=mods/max_raids/tests/drivers/raid_probe.lua \
timeout -k 5 300 "/c/Program Files/LOVE/love.exe" . 2>&1 | grep -E "^\[driver\]|max_raids"
```

Close Wooble's game first: two engine instances share caches. The probe opens a raid from the field
(`exports.open`, `PROBE_BOSS`), shoots the intro, taps FLEE, and checks the layer, the sheet and the
engine pad are back as they were.

The dens have a headless test and an engine probe:

```sh
cd ~/Documents/GitHub/max-raids && luajit tests/dens_test.lua    # placement and the daily roll
# in gen1recomp: POKEPORT_DRIVER=mods/max_raids/tests/drivers/dens_probe.lua (same env as above)
```

`dens_probe`:
- **Stubs** for its run, since walking the routes started a battle and a trainer's dialogue took the A
  press:
  - wild encounters (`Encounters.onStep`);
  - trainer sight (`TrainerSight.checkLineOfSight`).
- **Loads routes** with `Map.load(nil, game, mapId, {x, y, facing})` plus the session's and Player's
  cells. `U.teleport` is Gen 1 only.
- **No dens** in Petalburg City, Littleroot Town or the Safari Zone (checked first).
- **Logs** each route's dens (Routes 101-104, 110, 119, 124), shoots each water den (`w_*`, the den's
  own cell left out of the water check: it holds the den), then makes the first one active and
  stands the player under it, facing up.
- **A den in a reserved cell** logs the cells, `Dn.placedWith[mapId]` (the reserved count when it was
  placed) and the objects near it. Seen once on Route 110 (2026-10-26), not again in four runs: open.
- **Presses** A for the den screen, toggles a member, then START for the intro, and closes.
- **A new day** then re-rolls that den in place.

**Engine gotcha:** inside a mod, `package.loaded` is not the engine's table. Look engine modules up
with `require`. The beam used `package.loaded["src.core.game3.map"]`, got nil, and drew nothing.

## Status (2026-10-26)

- **Done.**
  - Phase 0, the bootstrap: the layer, the full-window draw, the 3D den and intro, the pad with FLEE,
    the Kanto Gear stand-down, the engine pad hidden and restored.
  - Phase 1, the dens: placement, the daily roll by badges, the den sprites and beam, A opening the den
    screen, picking four, START into the intro.
- **Open from Phase 1.** A won raid should call `Dn.finish(den)`; that comes with the win in Phase 2.
  A fled raid leaves the den active, as in the games.
- **Next.** Phase 2, the battle slice (`battle.lua` adapter over the engine,
  `raid_sim.lua` pure loop, HUD, FIGHT flow). Then Phase 3: G-Max effects and shaders, rewards and the
  catch, the second-screen pad, the other games. Then Phase 4: polish and the Thor.
- **Known.** The 4th member stands behind the pad in a 16:9 window; space the members, or place the pad,
  with the battle HUD.
