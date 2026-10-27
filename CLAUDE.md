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

- **One screen.** Everything is on the main window; the battle pad may go to the device's second
  screen (src/screen2.lua), leaving the main window the whole den.
  - Option KANTO GEAR (`kanto_gear`, on by default; 2026-10-27, Wooble: "the switch for second screen,
    following KG's display options, same as PlayNav"): `padWanted` in main.lua reads the Gear's
    DISPLAY MODE as PlayNav's `gearOption` does (`lastGame.mods`: the loader's record - nil when the
    Gear is not installed, disabled or failed - its stored options, else its schema default):
    `separate` -> the second screen; `fullscreen` / `combined` / `phone` -> the main one; no Gear ->
    the second screen when one is detected. Off: BATTLE PAD (`battle_pad`, main | second, shown only
    then: `visible_if kanto_gear == false`). The pad goes there only while a display is detected
    (`padOnSecond`). Drivers: `_test.gearOptions(t | false | nil)` (a stand-in Gear, no Gear, the
    real one), `_test.padWanted()`; `tests/drivers/gear_option_probe.lua`.
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
  - **The battle** (`setupBattle` in `begin`): each member's `m.b` is its battler (src/battle.lua, a
    deep copy) and `m.mon` the copy from then on; `r.boss`, `r.adapter`, `r.sim` (src/raid_sim.lua).
  - **The commands** (after the intro, `Rd.startCommand`): `r.cmd = { actor, cursor, chosen, menu }`;
    each member the sim lets act (`sim:canAct`) chooses in party order (`Rd.choose(id)`: Run leaves,
    Pokemon opens the summary, Fight opens the moves - `menu` "moves", `Rd.moveList` fills
    `r.cmd.moveList` in the update step (effectiveness on the boss) - and a move "moveN" (PP left) is
    taken, `chosen[i] = { move = N }`, the next member's turn beginning, the camera easing over its
    shoulder in `SWAP_S`; Bag opens the pouch - `menu` "items" (`Rd.POUCH_ORDER`, counts less this
    turn's picks; greyed once empty, `r.cmd.bagEmpty`) - then whom it is for - "target" (the four with
    their HP; a Revive only on one sitting out, the others on one on the field) - `chosen[i] = { item,
    target }`). B (`Rd.back`): target -> items -> commands, moves -> commands, else the member before,
    its pick undone. Up / down move `cursor`, A picks; a press on a
    pill moves the selection there and letting go picks it. All in: `Rd.fight()` runs the turn
    (`sim:turn`) and phase "battle" plays its events. No one able to choose (all sitting out): the
    boss's turn at once. `Rd.state()` gives `turn`, `actor`, `cursor`, `chosen` (a count), `menu`,
    `summary`.
  - **The turn's events** (`Rd.playEvents`, `Rd.EVENT`): one at a time - words typed in the band and
    held `HOLD_S` (A hurries them once typed); a member's "use" eases the camera behind it
    (`member` shot); the boss's (Wooble 2026-10-26: on the boss and whom it attacks) looks ahead to the
    members its move falls on (`Rd.targetsAhead`: hit, missed or touched, up to the next move) - one:
    the `target` shot on it, several: `spread`, none: `boss`; an event with `hp` sets that battler's `dispTarget`, and the bars ease there
    (`dispHp`, `HP_S`), with a shake. A hit lands with no words: the band steps aside while the bar
    drains. What shows, from Wooble's capture "battle reference UI-flow.mp4" (2026-10-26; Sword /
    Shield): none of the command UI (order list, panel, pad) in the turn; `showFor(e)` - the boss's
    block (`r.bossShow`, faded through `r.bossA` at `FADE`) while the words are about the boss (its
    moves, a member's move at it, a hit on it, its status, the end), else that member's row alone at
    the top left (`r.rows`, `Bh.drawRows`: its icon, its action's mark `r.actions[i]`, its HP draining) -
    a member's move on itself (Work Up) is about the member; "fail" keeps what was shown.
    The last event done: the next turn, or (`sim.over`)
    `deps.onEnd(den, outcome)` - main marks a won den done (`Dens.finish`) - then a loss closes the
    raid and a win goes to the catch.
  - **The catch** (`Rd.startCatch`, phase "catch"; Sword / Shield's: one throw after a win, any ball
    in the bag, used up - checked against iMore / PokeCommunity's raid guides 2026-10-26): the pad's
    list (`menu` "balls") of up to three balls the bag holds, each with its chance as its chip, and
    "Don't catch"; B or Back leaves it. `Rd.pickBall` throws (src/rewards.lua `Rw.throw` decides at
    once), phase "throw" (`Rd.THROW`, `Rd.stepThrow` in the update; Wooble 2026-10-26): the `catch`
    shot (past the party onto the boss's pad), a giant ball (`BALL_M` 2.2 scene units at the boss -
    a member stands 1.1 -, sized through `Scene.lastBoss`, where drawBoss put the boss) arcs in from
    the screen's foot, larger near the camera; the boss is drawn into it (`bossPic.shrink`, raid_scene
    drawBoss' red-glow path), it drops to the boss's feet and wobbles slowly round a cone `SPINS` 3
    times (`SPIN` 1.3 s each: its foot fixed, its top circling - `lean` tips it about its foot, `tilt`
    bows its band toward / away from the camera, `drawBall`); caught: "Gotcha!", the giant ball
    shrinks down (`SHRINK`) with stars; else a burst, "broke free", "disappeared"; "sent to the PC"
    when the party was full. Once thrown at, the boss stays drawn in (`r.shrink`) and its block is
    gone.
  - **The rewards** (`Rd.startRewards`, phase "rewards"; `Rw.give`): a card over the dimmed den -
    what was caught, the bonuses, the items, each of the four's Exp (levels) and EVs; A, B or a tap
    (`Rd.endRewards`, after 0.5 s) goes on.
  - **After the raid** (`Rd.startAfter`, phase "after"; Wooble 2026-10-26): each of the four that
    levelled, in party order (`partyIndex`), one by one - its evolution first (`Evolution.levelTarget`;
    the engine's `EvolutionScene.start`, the raid standing aside: `r.aside`, as for the summary; its
    `onDone` result "evolved" | "stopped"), then its new moves (`LearnMove.beginQueue` on the levels
    gained - less the last when it evolved: the scene teaches the new form that level's moves - with
    the raid's askers: `Rd.ask` msg = the words in the band, A / a tap once typed (`Rd.answer`);
    yesno = Yes / No on the pad (menu "yesno"); which move to forget = the game's summary in
    "select_move" mode, its slot passed on as the engine's party menu does). The queue done, the raid
    closes. `Rd.state()` gives `ask`, `aside`.
  - **The summary** (`Rd.summary`, Wooble 2026-10-26): the game's own (`SummaryMenu.openMenu`, which
    hands Emerald / R/S their own screens) on the four, from the one choosing, so L / R step through
    them; `context = "factory"` keeps it read only (that context is the only one the engine checks
    before swapping moves). It pushes its own layer ("summary") over ours; while `r.summary` the raid
    draws nothing, takes no input or pointer, and the engine's touch pad comes back (main's
    `render.hud` / `input.pointer` ask `Raid.summaryUp()`). Its `onClose` sets `r.skipInput`, so the B
    that closed it does not also step the commands back.
  - **The HUD:** the boss's block (`Rd.BOSS_HUD`, sizes in the window's height off the capture): the
    name large, white with a pink glow, a status tag after it (`STATUS_TAG`: BURNED orange, PARALYZED
    yellow, POISONED purple, ASLEEP grey, FROZEN cyan, each with a drawn sign), the HP bar (green /
    yellow / red) on a dark track; no stars or turn count in battle (the game shows neither). The message
    band (`Rd.MSG`, Wooble 2026-10-26, from a Sword / Shield capture: dark gray across the whole width
    near the foot, slanted lighter ends, white words typed out at `CPS` 40; sizes in the screen's
    height). The pad is not
    drawn, nor tapped, while a message shows: the commands come once it has gone, as in the game.
  - **Input:** `Rd.input` (the den screen; the commands: up / down, A, B back; the turn: A hurries the words), `Rd.pointer` (the pad's pills, from its last draw).
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
  - **The awakening** (2026-10-27, Wooble: dens gated behind the first gym): `Dn.ensure` places and
    spawns nothing until `Dn.awake()` (save "densAwake"). `Dn.stepAwaken` (each input.step) waits for
    the first badge, an outdoor map (`OUTDOOR_TYPES` 1 town / 2 city / 3 route / 6 ocean route: the
    gym left) and the field free (`Field.isLocked`, `Stack.busy`, `Message.isOpen`) for `WAIT_S` 0.6,
    then `Dn.awaken`: the player held (`Field.lock("max_raids_awaken")`), SE_M_EARTHQUAKE, the field
    camera swung from a `Task` as the engine's ShakeScreen / ShakeCamera specials do
    (`FieldView.cameraPanX / Y`, `AWAKEN.SHAKE` 3 x 4 px, 40 swings of 3 frames, easing off over the
    last third), then `AWAKEN.WORDS` through `mod.world:queueScript` text rows ("A powerful force
    shakes the region..." / "Pillars of light are rising from POKéMON DENS along the routes!"), then
    saved awake, the player free, the map's dens ensured. A save with a badge already awakens on its
    next free outdoor moment. `Dn.setAwake(on)` for drivers (dens_probe sets it for its run and puts
    it back). Driver `tests/drivers/awaken_probe.lua` (no badge: nothing on a route; the badge set in
    the first gym on its exit: nothing indoors; out of the door: the shake, the words, awake, the
    route's dens; Emerald, FireRed, Ruby - Ruby types slower).
- The den screen (`src/den_screen.lua`, Den = `Rd.Den`, raid phase "den"; 2026-10-27, Wooble, after
  Sword / Shield's den screen).
  - `Rd.openDen(den)` puts the layer up; `Den.open(r)` fills `r.slots[1..4]` ({ mon, name, level })
    with the party's first four that can fight (no eggs, HP > 0). A quiet den says so, with EXIT.
  - Look (`Den.LOOK`, sizes in u = h / 360): a red panel cut on a slant (SLANT_TOP 0.67 / SLANT_FOOT
    0.42 of the width) with faint dark stripes; the stars white top left; a badge per type (its colour
    square, the name on a dark slanted plate, `Battle.TYPE_RGB`); the boss's black silhouette
    (nearest, a silhouette shader, `Rd.bossBox` its opaque box); the rule at the foot ("The battle
    ends when" on a dark red band). On the pale panel: the four slots two by two (the game's party
    icon, two frames bobbing while selected; the name in title case, one size for all four that fits),
    START and EXIT as pills near the foot, the selected one black with a chevron.
  - The cursor: `r.cursor` 1..4 the slots (1 2 / 3 4), 5 START, 6 EXIT. A on a slot opens its menu
    (`r.denMenu`; PARTY / PC / BACK, `Den.MENU`, left of the slots at the slot's row): PARTY lists the
    party (`r.denParty`: icon, name, level, the slot it is in, fainted dimmed and refused); a Pokemon
    put in a slot another slot holds swaps the two (`Den.put`). START (`Rd.denStart`) begins with the
    slots in order (`Den.members`); EXIT or B leaves. Taps: `Den.where` (slots, menu, party rows,
    START, EXIT; a tap off an open menu closes it).
  - PC (`src/pc_pick.lua`, Pick, main's `_test.pick`): the game's own Storage System
    (`box_storage_ui`, opened in its withdraw mode) with its `handleInput` / `draw` swapped while
    up: A on a boxed Pokemon opens our SELECT / SUMMARY / BACK, drawn with the game's window frame,
    font and arrow (`Window.stdFrame / printPx / cursorPx`, where its own action menu sits); SELECT
    puts it in the slot and closes the PC (`Box.close`, SE_PC_OFF); SUMMARY the game's summary of the
    box (context "factory", read only), back to the menu; BACK closes the menu. A on the box's name,
    PARTY POKEMON or an empty slot, and SELECT / START, are taken away (no box menu, no drawer, no
    move: the save is never changed); CLOSE BOX and B close as the game does. The den screen stands
    aside (`r.aside`) meanwhile. A boxed Pokemon fights as a copy like any other (the after-raid
    steps sort it last: `partyIndex` 99).
  - After a raid: the rewards give no Exp. (as Sword / Shield), so `Rd.startAfter`'s evolution and
    move steps (`levelFrom / levelTo`) are not reached today; they work on a boxed Pokemon all the
    same. Driver `tests/drivers/after_probe.lua` (`PROBE_BOSS`, SNORLAX_2 to have the boss strike):
    a raid won with a boxed Pokemon in slot 1 - the party and the box identical field by field
    after, though every copy took damage; then the steps forced on the boxed Torchic: it evolves in
    its box slot, the "delete a move?" question and the game's move picker (summary `select_move`)
    replace a move on it, the party untouched.
  - Its buttons are the battle pad's (2026-10-27, Wooble: "modernize like the battle pad"): `face`
    draws `Pad.face` (brushed, gloss, bevel; dark and pressed in while selected, a rim in its colour,
    a soft shadow while it stands up), `Den.ACCENT` per button (START green, EXIT red, PARTY blue, PC
    purple, BACK grey, the slots and party rows the den's red with its colour corner), words bold
    (drawn twice), the pad's chevron; the pale panel carries the pad backdrop's faint hexagon grid
    and drifting light streaks (`panels(G, w, h, t)`).
  - Presses are ignored for `DEN_ARM_S` (0.25 s) after it opens (the A that opened it).
  - START (2026-10-27, Wooble): `Rd.denStart` sets `r.starting` - the den screen fades to black over
    `Rd.DEN_FADE.OUT` 0.45 s, holds `BLACK` 0.25 (`stepStarting` from Rd.update), then `begin` and the
    raid fades in over `IN` 0.7 (`r.fadeIn`, drawn over `Rd.drawMain`) with the intro's clock held at
    0 meanwhile, so the camera's pull-back starts on a clear screen; presses are ignored while it
    fades. Drivers wait for phase "intro" after `denStart`.
  - Driver `tests/drivers/showcase.lua` (to record, real time): set up (six at Lv 70, the first badge,
    a den on Route 104 / Route 2 made Charizard's with a straight five-tile approach, the zoom at FIT
    in memory), then waits for "." (`SHOWCASE_AUTO=1` skips it), and plays: out of the first gym,
    the awakening, the route (the game's fade) and the walk to the den, the den screen and START,
    the raid (strongest moves, Charizard falls on turn 3), Don't Catch (`SHOWCASE_CATCH=1` throws),
    the rewards card, the field. `SHOWCASE_BOSS`, `SHOT_DIR` (a few frames).
  - Driver `tests/drivers/den_screen_probe.lua` (a party of six, two boxed: the slots, the menu, the
    party list, a swap, the PC, its menu, the summary, BACK, SELECT, START with the boxed one in
    slot 3, a quiet den; shots p01..p12).
- `src/raid_scene.lua` (Sc), the den in 3D, built in code in metres.
  - **Geometry:** a plateau (superellipse rim, cliff), the cave floor, walls with a tunnel mouth and a
    ceiling, stalagmites and stalactites, boulders, the boss's pad (metal, a glowing ring, rim lights).
  - **Lighting** per vertex: `lit()`, an ambient, a key light from the upper left, the pad's warm glow,
    fog.
  - **Camera shots:** `Sc.shot(name | "member" i | pose, dur)` eases eye, look-at and FOV
    (smootherstep). Shots are `field`, `close`, `reveal`, `boss`, `wide` and `spread` (all four and
    the boss, nearer than wide); `targetShot(i, T)` (Wooble 2026-10-26: almost directly behind the
    member, a low angle up at the boss - the member large, the boss towering, the others mostly out
    past the sides): `Sc.TARGET` while the boss attacks it (aimed a little lower, LOOK_Y 3.5, so the
    member stands clear of the message band over the screen's foot), `Sc.CHOOSE` for its own turn -
    choosing, its moves - via `memberShot(i)` (no band: aimed higher, the boss whole); BACK 3.6 / 3.4
    (Wooble: pulled back so more of the member is in shot). `Sc.shake(amp, dur)`, `Sc.burst()` (the roar), `Sc.setTime(t)`.
  - **Drawing over the 3D, in 2D at projected points:** the light shaft; the motes (one mesh moved by
    a vertex shader, no `VertexPosition` in its format, see Conventions); the boss (`drawBoss`: shadow,
    pad glow, a red silhouette-shader halo and outline, wisps, swirling streaks, sparks); the members
    (`drawMember`: one pixel scale for all, `MEMBER_PIC_H` 1.75 m per 64-px pic, shadow, breath);
    the vignette. `Sc.drawFlat` is the fallback without 3D.
  - **Sizes.** Boss size = `MEMBER_H` 1.1 × `Rd.sizeOf(key)` (6.5–8.5 by the pack's Height,
    `data/raid_rules.lua` SIZE). Pad at z −9.2, r 3.4. Members in an arc at z −0.75 / −1.25.
- `src/render3d.lua` + `src/g3d/` (copied from PlayNav; g3d is MIT). A colour+depth canvas per size,
  `prepare(scene, setup)` in update, `draw` places the picture.
- `src/pad.lua`, the battle pad (Wooble 2026-10-26, from a Sword / Shield capture): `Pad.ITEMS` Fight /
  Pokemon / Bag / Run as pills down the lower right (`Pad.LOOK`, sizes in the window's height: 0.326 x
  0.092 on a 0.108 pitch, 0.012 from the edge and foot). White with black words, each emblem drawn in
  lines in its colour at the right end (Fight a burst round a ball, Pokemon a ball, Bag a backpack, Run
  a runner); the selected one black with white words, a thin rim in its colour (ours: it vanished
  against the dark den) and a white chevron edged black at its left. Pokemon opens the summary
  (no switching in a raid). `Pad.draw(G, w, h, r)` (the selection is `r.cmd.cursor`) returns
  the stack's rect; `Pad.drawFull` fills a whole screen for the second-screen path; `Pad.hit(x, y)` ->
  an id, "panel" or nil, against the last draw; `Pad.where` (`where.flee` = `where.run`).
- `src/battle.lua` (Bt), the battle on the engine: `Bt.member(mon)` (a deep copy through
  `State.makeBattler`, its four moves with their PP), `Bt.boss(key, rng)` (the pack's Giga base stats
  at a level in its tier's band, the tier's IVs, HP x `hpMult`, its types by name, ability none),
  `Bt.move(ref)` (the engine's record via `Moves.get`; name title-cased, type, power, accuracy,
  priority, `spread` from the target bits 8 / 32, and `side`: what it does besides damage), and
  `Bt.adapter(rng)` for the sim - `damage` (the engine's `Damage.calc` with an `Adapter.new` over a
  minimal st: `badges = {}` so no badge boosts, `wild`; the National Dex's ability and move-rule wraps
  apply; the immunity abilities Levitate / Volt Absorb / Water Absorb / Flash Fire / Wonder Guard
  checked first; `info.effectiveness` set to the chart's multiplier - the engine's is a scaled
  product), `hits` (Gen 3's accuracy with `Rules.ACCURACY_STAGE`), `speed` (stage, paralysis),
  `effectiveness`. A move's `side`: the National Dex's `extra` first (`exports.moveExtra`, through
  `deps.dex`; `Bt.extraSide`: foe / self stages, ailment + chance, heal, drain / recoil), else its Gen 3
  effect by name (`EffectIds`: `X_UP` / `_DOWN` / `_2` / `_HIT`, Bulk Up and kin, sleep, poison,
  toxic, paralysis, Will-O-Wisp, the burn / freeze / paralysis / poison hits, Recover).
- `src/raid_sim.lua` (Sim), the turns, pure (`tests/raid_sim_test.lua`, a fake adapter): priority then
  speed, a random tie-break; the boss once a turn, a random move, a spread move on every member on the
  field, else one at random; sleep 2-5 turns, freeze thaws 1 in 5, paralysis 1 in 4; poison / burn
  1/8, toxic n/16 at the turn's end; stat stages held to +-6; Gen 3's status immunities by type; a
  knocked-out member sits the next turn out and comes back at full HP (`down` 2), every knock-out
  counted; `over` "win" | "faints" (`RAID.FAINTS`) | "storm" (`RAID.TURNS`).
  The raid's own rules (Phase 3, 2026-10-26; data/raid_rules.lua): the barrier (`boss.shields` the
  tier's HP shares, `boss.segments`; `checkShield` after each hit on the boss, one at a time; a hit
  through it does `SHIELD_DMG` and breaks a segment, `throughBoss`; the last one broken: Def / Sp. Def
  `BREAK_DROP`; events "shield" up / hit / break with `left` / `max`); the boss's script (`due`: the
  G-Max move instead of a plain one on its turns, on all four; at the turn's end the wipe of the
  team's stat changes and, once below its HP share, the aura's +1 all round); the G-Max effects
  (`gmaxEffect`: data/raid_gmax.lua's field over the team for its turns, traps, statuses, drowsiness,
  stat drops, PP, the boss's veil halving damage, heal, cure, crit); a member sitting out cheers
  in its speed slot (`cheer`: `RAID.CHEER` by weight, the barrier-breaker only while one stands);
  the pouch (`RAID.POUCH`, `ITEM_PRIORITY` first: Potion half the HP, Full Heal, Revive back at once
  at half HP, the knock-out still counted; used up only when it works). Its events carry their
  words (English).
- `src/rewards.lua` (Rw), after a win, on the engine: `Rw.balls()` (RAID.CATCH.BALLS the bag holds,
  `Bag.get`), `Rw.chance(stars, mult)` (pure: the tier's % x the ball's; Master 0 = always),
  `Rw.throw(key, level, ball, rng)` (the ball out of the bag, the roll, `Party.giveMonToPlayer` - the
  PC when the party is full -, `mon.pokeball`, `Dex.registerCapture`), `Rw.give(r, rng)` (the save's
  "wins" per boss: x FIRST_WIN_MULT the first time, x NO_FAINT_MULT with no knock-out; `rollItems`
  from RAID.REWARD.POOL by tier into the bag, `Bag.add`; to each of the four's OWN Pokemon -
  `m.orig`, kept by setupBattle -: the boss's Exp, `Experience.gainFor` (one participant) x the
  multiplier, `Experience.apply`, a friendship step a level - `m.levelFrom / levelTo` for the
  after-raid evolutions and moves -; the tier's EVs in the boss's best base stat, 252 / 510).
- `src/fx.lua` (Fx) + `data/raid_move_fx.lua`, the moves acted out (Wooble 2026-10-26: each boss move
  as its description says it plays out - Max Rockfall's slab in his capture). Data: `MOVES` (the 99
  moves the bosses use), `GMAX` (the 34 G-Max moves), `DEFAULT` by type (the party's moves) ->
  `{ kind, shape, n, big }`, kinds beam, shot, drop (slab: one great slab of rock over the whole
  group, `Fx.drawSlab`), slam, slash, bite, bolt, wave (water / fire / ground / wind / sound /
  light), rings, powder, self (an aura, arrows up), drain, spikes, multi. `Fx.move(spec, type, from,
  targets, now, big)` plays one (`Fx.KIND`: length and impact; a G-Max x `GMAX_K`); at the impact
  each target gets its type's hit (`Fx.hit`, 18 effects). Lasting: `drawField` (the G-Max field
  along the party's feet), `drawVeil`, `drawBarrier` (a hex dome while the shield stands), and
  `Fx.charge` (the G-Max charge: a red wash, streaks into the boss). Shaders, made on first use
  (`Fx.shader`; drawn shapes stand in without them): fire (`fireRect`: fbm noise rising through a
  fire ramp, on a stretched white texel - the fire wave, field and hits) and rock (`rockPoly`: noise on
  screen position - the slab). raid.lua: `Rd.scheduleMove` at a "use" (whom it falls on, the
  events up to the next move; the look starts once the words are typed, a G-Max move after
  `GMAX_CHARGE_S` of charge: the boss shot, its cry, the roar's burst), `Rd.stepMove` (starts it with
  the band aside, the G-Max blow's camera, the boss's lunge `r.lunge` -> `bossPic.lunge` for slam /
  multi / bite / slash), the use event lasting until the impact. `Bt.ALIAS` (HIGH_JUMP_KICK ->
  HI_JUMP_KICK) and a retry without underscores (ANCIENTPOWER) find the Gen 3 names. Probe
  `PROBE_GMAX=1` makes the boss use its G-Max move every turn (its later checks then fail: the
  party is knocked about); shots r10f-h.
- `src/battler_hud.lua` (Bh), the command phase's HUD, same capture: `Bh.drawOrder` - the four down the
  top left in choosing order (`Bh.ORDER`), white boxes with a dark edge, the party icon, a thought
  bubble while waiting (its dots ripple on the one choosing, which is wider with a pink stripe) or,
  once its command is in, the mark of its action (Wooble: as the game; `Bh.actionOf`, `Bh.actionIcon`:
  a target with a burst for a move that hits, a yin-yang for a status move), its HP bar;
  `Bh.drawRows` - the same rows during the turn, only the members the words are about; `Bh.drawPanel` - the one choosing in the lower left
  (`Bh.PANEL`): a white panel with a slanted right edge, icon, name, gender drawn as a sign (the
  default face has none), "Lv." + level, HP bar (green / yellow / red), "hp/max", the EXP bar.
  Fed by `m.info` (raid.lua `memberInfo`, the update step: `Pokemon.displayName`, `SummaryData.gender`,
  `Pokemon.monIcon`, `mon.hp / maxHp / level`, `SummaryData.expProgress`).
- `src/hd.lua`: `HD.drawPixel` draws nearest or sharp-bilinear pixel art at any scale (from PlayNav).
- `src/pad_hide.lua`: hides the engine's TouchControls while a raid's pad is on the main screen, and
  restores **exactly the previous `enabled`**. The PlayNav original re-read the options, which left a
  pad turned on by a launch flag off.
- `data/raid_sprites.lua` (generated by `tools/raid_pack.py`): per pack key, frames, cell, grid,
  AnimationSpeed, the FrontSprite / ShadowSprite metrics, the Giga BaseStats (Essentials order HP, Atk,
  Def, Spe, SpA, SpD), types, height and form name.
- `data/raid_gmax.lua`: the bosses' 34 G-Max moves (type, a fixed 160 power where the game has one,
  else `POWER_BANDS` from the boss's strongest move of that type - `Bt.maxPower`; the effect as the
  sim runs it; the effects meaningless without switching - Stealth Rock, Gravity, Torment ... - plain)
  and `WORDS` for their messages. `Bt.gmaxMove` builds the move (on all four, never missing; a move
  table `ref` for `Damage.calc`); `Bt.boss` also sets `shields`, `segments`
  (`RAID.SEGMENTS` from base Def + Sp. Def) and `script`.
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
(`exports.open`, `PROBE_BOSS`), shoots the intro, walks the commands (a pick, the selection moving, B back, all four in, the next turn; r07-r10; the summary and B out of it, r11-r12), taps Run (`where.flee`), and checks the layer, the sheet and the
engine pad are back as they were.

The dens have a headless test and an engine probe:

```sh
cd ~/Documents/GitHub/max-raids && luajit tests/dens_test.lua    # placement and the daily roll
luajit tests/raid_sim_test.lua   # the turns: order, faints, the storm, statuses, extras
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
- **Presses** A for the den screen, puts the fifth party Pokemon in slot 2 (PARTY), then START for the
  intro, and closes.
- **Underwater Route 124** fails "got its dens" (seen 2026-10-27, on the commit before the den screen
  too): open.
- **A new day** then re-rolls that den in place.

**Engine gotcha:** inside a mod, `package.loaded` is not the engine's table. Look engine modules up
with `require`. The beam used `package.loaded["src.core.game3.map"]`, got nil, and drew nothing.

## Status (2026-10-26)

- **Done.**
  - Phase 0, the bootstrap: the layer, the full-window draw, the 3D den and intro, the pad with FLEE,
    the Kanto Gear stand-down, the engine pad hidden and restored.
  - Phase 1, the dens: placement, the daily roll by badges, the den sprites and beam, A opening the den
    screen, picking four, START into the intro.
  - Phase 2, the battle slice (2026-10-26): src/battle.lua, src/raid_sim.lua, the move menu, the turn's
    events, win / loss; a won den is done for the day (`Dn.finish`). A fled or lost raid leaves the den
    active, as in the games.
- **Needs national_dex_gen3's `exports.moveExtra`** (committed there 2026-10-26, ac6a7e6, its CHANGELOG
  [Unreleased]; not yet released): without it its newer status moves (Work Up ...) do "nothing".
  - Phase 3a, the raid's rules (2026-10-26): barriers (drawn as Wooble's capture shows: red slanted
    pills under the boss's bar, grey once broken, gone with the last), G-Max moves and their effects,
    the boss's scripts, cheers, the pouch (Bag -> item -> target).
  - Phase 3b, the catch and rewards (2026-10-26).
  - Phase 3c, the moves acted out (2026-10-26, first pass; polish later: Wooble).
- **The move looks' polish** (Wooble 2026-10-26: "not as cartoonish, detailed, work well in 3D, true
  impact felt"; first pass 764dcb1, the rework after it). `src/fx.lua` (`makeFx({ Scene })`):
  - **3D:** every effect sits at world points (metres) and is projected each frame (`Fx.P` = `Sc.project`
    + px per metre `Sc.cam.F / d`). Anchors from `Rd.placeOf(b)`: `{ X, Y (middle), Z, h, foot, boss,
    i, frac }` (boss on `Sc.PAD`, height `MEMBER_H * Rd.sizeOf`; a member at `Sc.MEMBERS[i]`, h
    `MEMBER_H`). Three layers by depth (`Fx.layerOf`): back (ground, behind the boss: drawn before it,
    `Sc.onBack`), mid (between boss and party, `Sc.onMid`), front (`Fx.draw`, after the den) - so a
    wall behind the party passes under them, a beam to the boss leaves from behind its member.
  - **Detail:** shaders fire (`blaze` 1 shapes a single blaze, 0 a wall), rock, beam (strip mesh),
    orb, puff (smoke / dust), wall (water / sand: crest, spray, foam, depth); one stream strip mesh
    (`band`, `screenRing`, `groundRing`, claw strokes, walls); world particles (`KINDS`: spark, ember,
    glow, light, dust, smoke, wisp, debris, chunk, drop, leaf, shard, bubble, twinkle, ring, gring,
    streak, heart, coin; gravity, drag, ground bounce, `home` for drain), ground decals (scorch, wet,
    frost, crack), spots (bloom, fire, electric arcs, psychic rings, speed lines). `Fx.hit(type, T,
    power, now, big)` per type. The slab is a 3D box (visible faces, rock shaded, cracks opening) that
    lands quietly (no blooms under it), throws dust, then shatters into chunks.
  - **Impact:** `Fx.onImpact(T, power)` -> `Rd.impact` (`Rd.IMPACT`): hit-stop (`r.hitStop`, the
    raid's clock x0.06), `Sc.kick` (a FOV jab), `Sc.shake` (a weaker one no longer cuts a stronger),
    `Sc.hit(which, p)` (white silhouette + knockback on the boss / member, `HIT_FLASH_S`, `KNOCK_S`).
    Power from the HP the move takes (`scheduleMove` sums each target's damage events into `frac`);
    a miss only jolts. One type-coloured flash a move. The damage event's own shake is skipped within
    1.5 s of a look's blow.
  - Driver `tests/drivers/fx_probe.lua` (26 cases through `R.testLook(spec, type, user, onto, gmax,
    frac)`, `PROBE_ONLY=a,b`; shots before / at / after each blow; logs particle counts, `Fx.stats`).
  - What lasts, in 3D too: `Fx.setLasting(field, bossAnchor, veil, shield, now)` from `Rd.draw` each
    frame; the G-Max field on a ring round the party (`FIELD` CX 0 CZ -1 RX 5 RZ 2.3; its back half in
    mid, its front half in front): fire and a water vortex as walls through the fire / wall shaders
    (`ringWall`), vines curling up (strips + leaves), stones orbiting with shadows; the veil a shimmer
    sphere with turning bands; the barrier a dome of hexagons on a sphere (only cells facing the eye,
    fresnel rim, a band climbing it, a hit's ripple from the front: `Fx.barrierUp / barrierHit /
    barrierBreak` from the shield events - a break bursts it into red shards with a flash, a shake and
    a jab). fx_probe `PROBE_ONLY=lasting` shoots them.
  - Fainting (Wooble 2026-10-26: "shrink down and be taken off the field"): a member's faint event sets
    `m.faintT` (a red light at it), its comeback (`back`) `m.backT`; `Rd.memberShrink(m)` (FAINT_S 0.7,
    BACK_S 0.5) goes to the pic as `shrink`, and raid_scene's drawMember draws it red, shrinking about
    its middle and lifting, no shadow, gone at 0; back it grows in the same way. fx_probe
    `PROBE_ONLY=faint`.
- **The catch, the card and the end card** (Wooble's capture max-catch-reward-screen-end-card.mp4 and two
  screenshots, 2026-10-26; the capture has no ball choice):
  - The choice: two pills at the lower right, Catch / Don't Catch (`Rd.catchChoose`), then the ball box
    (`r.cmd.menu` "ballbox"): a black bar with left / right arrows, the ball's bag icon, its name
    (plural) and xN, every ball the bag holds in turn (`Rd.catchBall`), its description
    (`Rewards.itemDesc`, the engine's ItemsData.info), Use (`Rd.pickBall()` throws the one shown).
    No chance shown. Taps: `Rd.catchPointer` / `Rd.catchWhere`.
  - The throw (`Rd.THROW`, marks `Rd.throwTimes()`, pose `Rd.ballNow(u)`): held up behind the party,
    an arc to the boss, a flash, it opens and the boss goes in on streaks of light, shuts, falls,
    lands in a crater (dust, chunks, rings, a crack, a shake and jab; `th.rocks` drawn with `Fx.rock`
    before / behind it by depth), three slow wobbles round a cone with its button lit; caught: the
    button flares, a flash, the giant ball shrinks into the real one (the thrown ball's colours) whose
    button glows green with sparkles, "Gotcha!"; broken free: it bursts (`Fx.barrierBreak`). The ball is
    `Fx.drawBall` (src/fx.lua): a lit sphere mesh (orthographic about its middle; lean / phi / spin,
    `open` swings the lid on its hinge, `dyna` 1 the pink energy with a checker and a grid of light,
    0 the real ball; button glow). A magenta cast over the den meanwhile.
  - The card (`Rd.drawRewards`, `Rd.CARD`): amber with slanted bands, a black bar and title tab ("You
    caught X!" / "You defeated X!" - the second a guess), the stars popping in, the boss on the left,
    the items (bag icons via `Rd.itemIcon`: FireRed's bag pictures, else Emerald's), a cursor
    (`Rd.cardMove`, `r.rw`), a scroll bar past six, Next. Exp / EVs are given but not listed (the
    game's card lists items only).
  - The end card: Next -> phase "outro" (`Rd.OUTRO`): the den once more (wide, the boss gone), a circle
    closing to black (`Rd.drawIris`), then the evolutions / moves over black.
  - Driver `tests/drivers/catch_probe.lua` (the roll made sure; `PROBE_FAIL=1` a miss).
- **Performance and garbage** (2026-10-27, as PlayNav's perf drivers): `tests/drivers/perf_parts.lua` - in
  each busy state (the commands, a G-Max move at its height, the slab breaking up, the catch
  mid-wobble, the rewards card) the time and the Lua garbage a call (collector stopped) of
  Rd.draw, Scene.draw / prepare, Fx.drawLayer / draw / update, Pad.draw / drawSecond, the HUD,
  Rd.drawThrow / drawRewards, Screen2.update (a display stood in for), Rd.update and whole frames;
  each against `BUDGET` (FAIL over it; PERF_STRICT=0 logs only); and FPS live per state (vsync holds
  the desktop to 60: at least `PERF_FPS_MIN` 57, no frame over `PERF_HITCH_MS` 34). Baseline
  2026-10-27 (desktop): frames 0.5-0.9 ms and ~20-26 KB garbage; the pad 9 KB, the quad 11 KB (a
  reused `Pad.faceOpts` / size table and the Run figure's points cut ~2.5 KB each), the push 12 KB;
  60 fps, slowest frame ~26 ms (in a G-Max move / the throw).
- **gen3-hd-sprites' party pictures** (2026-10-27, Wooble: still cut off): it hands out a 64 x 64 stand-in
  cropped for the battle and tags it with the whole frame (`exports.tagOf`: texture, quad, scale);
  `memberPics` draws the tag's frame (`Rd.hdTagOf`, `cell` = 64 / scale), as PlayNav does.
- **Rewards as Sword / Shield's** (2026-10-26; Serebii's den tables, EVIDENCE "RAID.REWARD"):
  `RAID.REWARD` - Exp. Candies always (1★ XS x5 + S, 2★ S x5 + M, 3★ M x5 + L, 4★ M x2 + L x3,
  5★ L x2 + XL; National Dex Gen 3 registers them, `exports.expCandies`; Rare Candies stand in
  without), TMs 1 / 1 / 2 / 3 / 3 (Gen 3's 289..338, damaging, of the boss's types first:
  `Rw.tmsFor`, read through `Rw.battle` = src/battle.lua), two berries at 80% each from a pool,
  Nugget / Big Pearl / Star Piece (Big Nugget and Rare Bone stand-ins) at 20-50% each by tier, a Rare
  Candy at 25%, a PP Max for the Bottle Cap at 1-3% from 3★. No Dynamax Candy, no Exp. or EVs straight
  to the four (so the after-raid evolutions / moves no longer arise; the code stays). Names on the
  card: "TM38 Fire Blast", "Exp. Candy XL" (`Rw.itemName`). Driver `tests/drivers/rewards_probe.lua`;
  sim test checks the spread (with an even generator: rngOf's low bits bias % rolls).
- **The party's pictures whole** (2026-10-26, Wooble: big sprites cut off at the top): `memberPics` took
  a 64 x 64 corner of the back pic; a sprite mod paints a big Pokemon on a canvas larger than the 64 x 64
  it reports (g9-battle-sprites-gen3), so the head was cut. Now the provider's own quad when it gives
  one, else the whole image; the scale stays one for every member (`cell` = the size it reports), so a
  big one stands taller. balance_probe shoots its team (team_<boss>*.png).
- **Balance** (2026-10-26): `tests/drivers/balance_probe.lua` plays whole raids with a strong team
  (PROBE_LEVEL, default 70: Blaziken, Swampert, Sceptile, Gardevoir, IVs 31, 252-EV spreads, each using
  its strongest move) against PROBE_BOSSES, PROBE_RUNS each, the raid's clock fast-forwarded
  (`Rd.SPEED`, drivers only; 1 in play). At 5★ x3.0 HP it won every 5★ in 3-8 turns with at most one
  knock-out; now x5.0: 4-10 turns, 0-1 knock-outs (Snorlax 7 / 9 / 10). The levels stay the game's
  (Serebii: 5★ 55-60; 65-70 is Crown Tundra's Dynamax Adventures, not dens). A Lv 30 team against
  the 4★ Charizard (46-50) is wiped by its G-Max move - the level gap, as the game.
- **The other versions** (2026-10-26): FireRed and Ruby checked (LeafGreen / Sapphire share their code):
  the raid (songs by version: Mewtwo's theme / Regi's), the catch (each version's ball words, its caught
  fanfare), the dens (FireRed's routes are `FR_ROUTE_1` ..., Hoenn's `RU_ROUTE101` ...; towns and the
  Safari Zone get none). Drivers take POKEPORT_VERSION for their constants; dens_probe reads the
  game's own route / town names, loads maps through `Field._mod / Field._game` (as the engine's warps),
  presses through FireRed's intro first, never walks into the Safari Zone (its mode would carry
  through the run; `Dn.isRoute` is asked instead) and shoots every place it sends the player
  (`at_<map>.png`).
- **The music's hand-offs** (Wooble: no overlap): caught - the battle's song fades out at the ball's
  click (`fadeOutBgm(4)`), the caught fanfare plays alone, the caught song starts once it has played
  (`waitSe`, as the engine's catch_seq); the raid's close fades into the field's song
  (`fadeOutAndPlay(specialMapSong())`) rather than cutting. catch_probe logs every music call by name.
- **The battle pad on the second screen** (BATTLE PAD: SECOND SCREEN; 2026-10-26, Wooble: a quad like
  Kanto Gear's, our buttons, a modern background, pressed in when selected): `src/screen2.lua` (S2) on
  the engine's SecondScreen bridge (the Android display or the desktop companion): from the raid
  layer's update (never in a draw) it draws `Pad.drawSecond` into a 960x840 canvas, reads it back
  without a stall (requestImageData / pollImageData, else newImageData), pushes it ("secondary") at
  most 30 a second and releases the pixels; taps come back by pollTouch (down holds a button - pressed
  in, the selection on it -, up on it picks: `Rd.secondPress(id, released)`, which ticks SE_SELECT).
  `padOnSecond()` (main) = the option AND the display detected, so without one the pad stays on the
  main screen. `Pad.drawSecond`: a navy-to-magenta background (a gradient mesh, the band's ring, a
  hexagon grid fading upward, drifting light streaks), a header (who is choosing / what to choose,
  Back at its right), a 2 x 2 grid: Fight / Pokemon / Bag / Run (emblem over words), the moves (type
  chip, name, PP, how it does on the boss), the pouch, the targets, Yes / No; between commands the four
  with their HP. `quadButton`: a light face lit from above with a drop shadow; selected or held it sits
  lower, no shadow, a dark lip inside its top (selected also black with a rim in its colour).
  `Pad.hitSecond`, `Pad.sWhere`. Driver `tests/drivers/screen2_probe.lua` (the display stood in for:
  frames saved as PNGs, taps queued; `_test.padSecond(on)` forces the option, `_test.screen2.bridge`).
  The catch is there too when the pad is (2026-10-26): Catch / Don't Catch as two wide buttons, then the
  ball box (big left / right buttons, the ball's dark card with its bag icon via `Pad.itemIcon` = the
  raid's `Rd.itemIcon`, name, xN, "n of N", its words, Use; Back in the header); `Rd.secondPress` takes
  catch / leave / left / right / use / back; the main screen then draws no choice and takes no taps.
- **Each raid's scene starts clean** (2026-10-26, Wooble saw the camera shake wildly on a raid opened right
  after a catch): the shake ran on `st = clock - t0`, and a new raid's clock starts at 0, so a shake
  from the last raid (the catch's landing, t0 ~25 s) had st < 0 and an amplitude growing with it.
  Now a shake not yet begun does nothing (`st >= 0`), and `begin` calls `Sc.resetEffects()` (clock 0,
  shake, jab, struck battlers, the roar's burst). screen2_probe checks it on a raid reopened after a throw.
- **Textured buttons** (Wooble: modern, texture instead of flat): `Pad.face(G, x, y, w, h, rad, o)` - a
  shader-drawn rounded face: a lit gradient (light, or dark when selected), a brushed grain, a gloss
  over the upper half, a bevel (lit top, shaded foot; pressed: turned over, a shadow inside its top),
  `tint` of its colour, `corner` a slanted wedge in its colour (the quad's buttons); plain fills
  without shaders. Used by the command pills, the list pills, the quad and the catch's pills.
- **The emblems** (Wooble: closer to the references): Fight's ball centred in its burst; Run an
  outlined running figure (no speed lines) (`runFigure`: its limbs stroked in the colour, then again thinner in the
  button's face colour, one outline round the whole; `EMBLEM.run(G, cx, cy, s, bg)`).
- **Sound** (2026-10-26): `data/raid_sounds.lua` - Gen 3's own effects by SE name through `Audio.playSe`
  (`Rd.se`), so the game's settings and pack apply; every name checked against the engine's
  se_ids.lua. A move's look starts with its sound (`Sounds.moveSe(spec, type)`: a beam / plain shot by
  type, else its shape, else its kind; the G-Max charge SE_M_CHARGE with the cry); its blow plays the
  battle's hit by effectiveness (`T.eff`, read ahead from the "effect" events; once a moment) and, for
  what lands hard, `LAND` once a move; damage events the look covered are marked `looked` (no second
  sound or shake); the events (faint, back, item, heal, cheer, stages up / down, status, field,
  shield up / hit / break; a hit with no look). The catch as the engine's catch_seq: throw, open,
  BALL_TRADE drawing it in, the click shut, the landing's quake, a BALL per wobble, the click, and the
  version's caught fanfare then caught song (`Rd.caughtFanfare`, the battle profile's sounds);
  broken free BALL_OPEN, gone SE_FLEE. The menus tick SE_SELECT when a press or tap moves a cursor or
  picks (`uiKey` before / after `Rd.input` / `Rd.pointer`). raid_probe and catch_probe log every SE.
  A `Sounds` entry may be a list: the first name the version has (`seName`; FireRed's SE_BALL_CLICK is
  Emerald's SE_RG_BALL_CLICK - the click was silent on Emerald, as it is in the engine's own catch).
- **Sounds baked ahead and kept** (2026-10-27, Wooble: a hitch after the big moves): the engine bakes an
  SE on its first play (its synth, 2-20 ms) and the samples (~1 MB of Lua heap a second of sound) set off
  its full collection - 53 ms at Wildfire's Heat Wave, 109 ms at the slab's Earthquake + hit. Its own
  cache of samples is 34 s (`Audio.SE_RAW_MAX_FRAMES`, least recently used out; all 70 raid sounds are
  130 s), so one raid's overran it. `Rd.stepWarm` (each Rd.update, phases `Rd.WARM.PHASES` den /
  command, the intro only with no den screen) queues `warmList()` one at a time through
  `Audio.prewarmSe` (the engine's Warm, which spreads a bake over frames) - the boss's G-Max and moves
  with their LAND, the hits, the events, the party's moves (the whole party on the den screen), the
  catch - and keeps each (`keptSource`: `Audio._buildSeSoundData` at master 1 -> a static Source,
  16-bit, outside the Lua heap; rebuilt if the game's MONO changes). `Rd.se` plays a kept sound as the
  engine does (`playKept`: the SE's player slot stopped, cloned while playing, `_sfxVolume`, entered in
  `_seSources` / `_seByPlayer` / `_seMeta` as its fanfares are, so stopSe / isSePlaying / waitSe /
  suspension apply); a sound pack's own effect (`ModAudio.sfxKey`) and anything not kept go through
  `Audio.playSe`, kept from its bake after. Kept sounds last for the session (at most the 70). Den
  screen: 28 sounds in ~5 s, slowest frame 28 ms. Drivers: `hitch_probe.lua` (frame by frame through
  the boss's G-Max and first move; HITCH lines with the time in each wrapped part; `PROBE_COLD=1` none
  baked ahead), `se_bake_probe.lua` (each sound's bake time, length and heap). What remains in a battle:
  a ~25-40 ms frame every few seconds, the engine's full collection of the frames' garbage.
- **HP drains as the blow lands:** `scheduleMove` keeps each target's HP after the move (`hp`); at its
  impact `Rd.impact` sets the bar's target and shows its card (all the members a move hits, together;
  a damage event for a member already shown keeps the cards).
  - The bite (2026-10-26, Wooble: a jump from the Giga Pokemon, a silhouette of jagged teeth snapping over
    the target): `drawBite` / `jaw` - two dark jaws (a dome above, a lower one, their mouth line curving
    to meet at the corners), jagged teeth with two long fangs, lit along their edges in the move's
    colour, a dark-red aura; they loom in open, snap shut at the impact (accelerating), shudder and
    pull away. The boss crouches, leaps (`r.jump` -> `pic.jump`: risen 0.28 of its height, stretched;
    squashed on landing; its shadow stays on the ground and shrinks) and lands as they close.
  - Earthquake (a "wave" of shape "ground"; 2026-10-26, Wooble: the ground shakes and cracks, the party
    shaking with it): no wall. `stepQuake` / `drawQuake` (back layer): jagged cracks (`quakePath`: a
    main line from in front of the boss to each target, three branches) racing across the ground (lit
    broken edges, a dark gap, a deep glow), dust and chips at their heads; each target hit as its crack
    reaches it. `Fx.onQuake(seconds, big)` -> the raid: `Scene.shake` for the whole move and
    `Scene.quake` (drawMember jolts every member side to side and bounces it, easing off; reset with the
    scene). The cracks are `hold`: they stay past the move's length until `Fx.settle(now)` - the raid
    calls it at the next "use" / "over" event and at the commands - then fade over `Fx.SETTLE_S` 0.8.
    fx_probe settles after each case (shots `_4held`, `_5settling`).
  - Open: the ground wave is gone (Earthquake above); the sand cloud (G-Max Sandblast) is a powder
    and the ground wave are plain; Thor performance unmeasured (particles capped at
    `Fx.MAX_PARTS` 900).
- **Next after that.** Sound;
  the second-screen pad; FireRed / LeafGreen / Ruby / Sapphire. Then Phase 4:
  polish and the Thor. Weather moves (the video's sandstorm) are not in the sim.
- **Not in the sim yet:** confusion, flinch, multi-hit (Surging Strikes' three), Spectral Thief's
  theft, the battle.damage hook's abilities (Adaptability, Filter ...: the engine runs them in its own
  hit script), held items' end-of-turn effects, critical-hit stages beyond the engine's own roll.
- **Known.** The 4th member stands behind the pad in a 16:9 window; space the members, or place the pad,
  with the battle HUD.
