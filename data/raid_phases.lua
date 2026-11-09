-- The raid's two state machines, as data: its phases and the command menus. src/raid.lua runs them:
-- Rd.go(phase) is the only way a phase changes, Rd.setMenu(menu) the only way a menu does; each
-- change is checked against `to` here (a move not listed is logged, never refused) and kept in the
-- raid's trail (Rd.state().trail). tests/raid_phases_test.lua checks this file against raid.lua and
-- the drivers.
--
-- PHASES[name]:
--   to       the phases it may go to (closing the raid is always allowed)
--   warm     the sounds are baked ahead in it (Rd.stepWarm)
--   team     the team's lasting effects are drawn (screens, Safeguard, guards: Rd.teamState)
--   hud      the battle HUD is drawn (the boss's block, the order list, the panel)
--   fx       the moves' effects and the G-Max field are drawn
--   input / pointer / second   true: raid.lua has a handler for buttons / taps on the main screen /
--            presses on the second screen in this phase; false: they are ignored in it
--   ask      the band asks a question here (Rd.ask: yes / no, or words to read)
--
-- MENUS[name] (r.cmd.menu, the command phase's and the catch's):
--   ids      what Rd.choose takes in it: a set of ids; `slots` true takes "move1".."move4"
--   back     where Back goes: a menu, "from" (the menu it was opened from), "member" (the member
--            before, its pick undone) or false (Back does nothing there)

local P = {}

P.PHASES = {
  den     = { to = { intro = true }, warm = true,
              input = true, pointer = true, second = false },
  intro   = { to = { command = true }, warm = true, team = true, hud = true, fx = true,
              input = false, pointer = false, second = false },
  command = { to = { battle = true, leaveq = true }, warm = true, team = true, hud = true, fx = true,
              input = true, pointer = true, second = true },
  leaveq  = { to = { command = true, blown = true }, team = true, hud = true, fx = true, ask = true,
              input = true, pointer = true, second = true },
  blown   = { to = {}, team = true, hud = true, fx = true,
              input = false, pointer = true, second = false },
  battle  = { to = { command = true, catch = true }, team = true, hud = true, fx = true,
              input = true, pointer = true, second = true },
  catch   = { to = { throw = true, rewards = true }, hud = true, fx = true,
              input = true, pointer = true, second = true },
  throw   = { to = { rewards = true }, fx = true,
              input = false, pointer = false, second = false },
  rewards = { to = { outro = true },
              input = true, pointer = true, second = true },
  outro   = { to = { after = true }, team = true, fx = true,
              input = false, pointer = true, second = false },
  after   = { to = {}, fx = true, ask = true,
              input = true, pointer = true, second = true },
}

P.MENUS = {
  main    = { ids = { fight = true, bag = true, run = true, pokemon = true, back = true }, back = "member" },
  moves   = { ids = { dynamax = true, back = true }, slots = true, back = "main" },
  items   = { ids = { back = true }, slots = true, back = "main" },
  target  = { ids = { back = true }, slots = true, back = "from" },
  yesno   = { ids = {}, slots = true, back = false },
  catchq  = { ids = {}, back = false },
  ballbox = { ids = {}, back = "catchq" },
}

return P
