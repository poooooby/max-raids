-- Galar Rising's own Max Move pad where Kanto Gear's battle screen was, while the player chooses a
-- Dynamax move. With the Gear's BATTLE VIEW on GEAR or FULL GEAR its own move cards show the base
-- moves (they read the Pokemon's own four); so while Dynamax is picked, or a Dynamaxed Pokemon of
-- the player's chooses its move or its target, the Gear stands down (main.lua's store module,
-- shown() - its public modules API) and this pad is drawn in its place: the raid pad's second
-- screen look (src/pad.lua Pad.drawSecond) on a state of this battle's own - the four Max / G-Max
-- Moves (type, PP, how each does on the foe, the Dynamax red), the DYNAMAX pill while it may still
-- be put back, Back; the foes for a double battle's target. Given back the moment that choice is
-- over. Where: the Gear's second screen (its DISPLAY MODE separate, a display there: pushed as the
-- raids' pad is, src/screen2.lua), else the room the game's picture leaves in the window. A tap is
-- the battle's own button press (src/dmax_ui.lua U.press): the cursor and the pad never disagree.
--   P = dmaxPad(mod, { dmax, ui, Pad, battle, T, gearOption = function(key), makeScreen2 })
--   P.wanted() ; P.step(now) (the update step) ; P.drawMain(viewport) (render.hud) ; P.pointer(ev)
local floor, max, min = math.floor, math.max, math.min

return function(mod, deps)
  local Dm, U, Pad, Bt = deps.dmax, deps.ui, deps.Pad, deps.battle
  local T = deps.T or setmetatable({}, { __call = function(_, s) return s end })
  local P = { MIN_ROOM = 0.22, OVERLAY = 0.46 }

  local E = {}
  local function engine()
    if E.Ui then return E end
    local function req(name)
      local ok, m = pcall(require, name)
      return ok and type(m) == "table" and m or nil
    end
    E.Ui = req("src.core.game3.battle.ui")
    E.Battle = req("src.core.game3.battle")
    E.State = req("src.core.game3.battle.state")
    E.Moves = req("src.core.game3.battle.moves")
    E.Types = req("src.core.game3.battle.types")
    return E
  end

  local function gearOption(key)
    if not deps.gearOption then return nil end
    local ok, v = pcall(deps.gearOption, key)
    return ok and v or nil
  end
  -- Kanto Gear's battle on its own screen: its move cards there, not the battle's
  function P.gearView()
    local v = gearOption("battle_view")
    return v == "gear" or v == "full"
  end

  local function chooser(st)
    if not st then return nil end
    if st.double then return E.State.battler(st, E.Ui._active or 0) end
    return st.player
  end
  -- the player choosing a Dynamax move or its target now (the Gear's battle view on its screen)
  function P.wanted()
    if not P.gearView() then return false end
    engine()
    local Ui = E.Ui
    local st = Ui and Ui._st
    if not (st and st.__mr and st.__mr.allowed and E.Battle and E.Battle.isActive and E.Battle.isActive()) then
      return false
    end
    local mode = Ui._mode
    if mode ~= "moves" and mode ~= "target" then return false end
    if U.sceneOn and U.sceneOn() then return false end
    local b = chooser(st)
    if not (b and b.side == "player" and b.mon) then return false end
    local okI, id = pcall(E.State.idOf, b)
    return (okI and Dm.sel[id] == true) or b.__mrDmax ~= nil
  end

  -- ------- the state the raid pad draws (its fields as src/raid.lua keeps them), reused

  local TARGET_RGB = { 0.93, 0.18, 0.42 }
  local rows = { {}, {}, {}, {} }
  local list = {}
  local targets = {}
  local view = { phase = "command", t = 0, padHi = true, say = nil,
    cmd = { menu = "moves", cursor = 1, moveList = list, canDmax = false, dmax = false, actor = 1, dmaxCenter = true },
    members = { { b = { name = "" } } } }
  P.view = view

  local function effOf(num, st)
    local foe = st and (st.double and nil or st.enemy)
    if not (foe and E.Types and E.Types.typeCalc and Bt and Bt.typeNum) then return nil end
    local row = Dm.byNum[num]
    if not row or row.key == "MAX_GUARD" or row.key == "GUARD" then return nil end
    local t = Bt.typeNum(row.type)
    if not t then return nil end
    local ok, _, _, e = pcall(E.Types.typeCalc, t, foe.type1, foe.type2, nil, true)
    e = ok and tonumber(e) or nil
    if not e then return nil end
    if e == 0 then return "none" elseif e > 1 then return "super" elseif e < 1 then return "weak" end
    return nil
  end

  local maxNums = {}
  local function build(st, b)
    local Ui = E.Ui
    local c = view.cmd
    local okI, id = pcall(E.State.idOf, b)
    for i = #list, 1, -1 do list[i] = nil end
    if Ui._mode == "target" then
      -- the foes it may strike: one button each
      c.menu = "items"
      local n = 0
      for _, tid in ipairs({ 1, 3 }) do
        local fb = E.State.battler(st, tid)
        if fb and not E.State.isFainted(fb) and not (st.absent and st.absent[tid]) then
          n = n + 1
          targets[n] = tid
          local r = rows[n]
          for k in pairs(r) do r[k] = nil end
          local okN, nm = pcall(E.State.prefixedName, st, fb)
          r.name = okN and nm or (fb.mon and fb.mon.nickname) or "?"
          r.note, r.live, r.rgb = nil, true, TARGET_RGB
          list[n] = r
          if Ui._target and Ui._target.cursor == tid then c.cursor = n end
        end
      end
      for i = n + 1, 4 do targets[i] = nil end
      c.canDmax = false
      return
    end
    c.menu = "moves"
    Dm.maxMovesOf(b, maxNums)
    local mon = b.mon
    for i = 1, 4 do
      local num = maxNums[i]
      local base = mon.moves and mon.moves[i]
      if num and num ~= 0 and base and base ~= 0 then
        local r = rows[i]
        local row = Dm.byNum[tonumber(num) or -1]
        local def = nil
        if not row and E.Moves and E.Moves.get then
          local okM, d = pcall(E.Moves.get, num)
          def = okM and d or nil
        end
        r.name = row and row.name or (E.Moves.displayName and E.Moves.displayName(num)) or tostring(num)
        r.typeName = row and row.type or (def and Bt and Bt.typeName and Bt.typeName(def.type)) or nil
        r.rgb = (Bt and Bt.TYPE_RGB and r.typeName and Bt.TYPE_RGB[r.typeName]) or { 0.6, 0.6, 0.6 }
        r.pp = mon.pp and mon.pp[i] or 0
        r.maxPp = (mon.maxPp and mon.maxPp[i]) or nil
        if not r.maxPp and E.Moves and E.Moves.get then
          local okB, bd = pcall(E.Moves.get, base)
          r.maxPp = okB and bd and tonumber(bd.pp) or r.pp
        end
        r.live = (r.pp or 0) > 0
        r.max = row ~= nil
        r.eff = row and effOf(num, st) or nil
        r.note, r.chip, r.itemId = nil, nil, nil
        list[#list + 1] = r
      end
    end
    c.cursor = Ui._moveIndex or 1
    c.canDmax = not b.__mrDmax
    c.dmax = okI and Dm.sel[id] == true or false
  end

  -- ------- a press: the battle's own button (src/dmax_ui.lua U.press), the cursor put there first

  function P.press(id)
    engine()
    local Ui = E.Ui
    if not (Ui and P.wanted()) then return false end
    if id == "dynamax" then return U.press("r") end
    if id == "back" then return U.press("b") end
    local k = type(id) == "string" and tonumber(id:match("^move(%d)$")) or nil
    if not k then return false end
    if view.cmd.menu == "items" then
      local tid = targets[k]
      if tid == nil or not Ui._target then return false end
      Ui._target.cursor = tid
    else
      Ui._moveIndex = k
    end
    return U.press("a")
  end

  -- ------- the second screen: the raids' pusher (src/screen2.lua) on this pad

  local S2 = nil
  local function where()
    if gearOption("display_mode") == "separate" and S2 and S2.detected() then return "second" end
    return "main"
  end
  P.where = function() return where() end
  if deps.makeScreen2 then
    local fakeRaid = {
      active = function() return P.wanted() end,
      current = function() return view end,
    }
    local ok, s2 = pcall(deps.makeScreen2, mod, {
      Pad = { drawSecond = Pad.drawSecond, hitSecond = Pad.hitSecond },
      raid = fakeRaid,
      on = function() return gearOption("display_mode") == "separate" end,
      press = function(id, released) if released then P.press(id) end end,
    })
    if ok and type(s2) == "table" then S2 = s2 end
  end
  P.S2 = S2

  -- each update step: the pad's state from the battle; pushed to the second screen when it is there
  local shownNow = false
  function P.step(now)
    engine()
    shownNow = P.wanted()
    if shownNow then
      local st = E.Ui._st
      local b = chooser(st)
      if b then pcall(build, st, b) end
      view.t = now or (love.timer and love.timer.getTime() or 0)
    end
    if S2 then pcall(S2.update, now) end
    return shownNow
  end
  function P.shown() return shownNow end

  -- ------- the main window. With the Gear's DISPLAY MODE combined, the window split as the Gear
  -- splits it (kanto_gear core/theme.lua THEME:windowLayout, from its own options: LAYOUT, SECONDARY
  -- SIZE, BOTTOM SAFE AREA, PRIMARY VIEW): the game kept in the Gear's game rect (render.viewport,
  -- as the Gear reserves it - so Fill Screen fills only that), the pad in the Gear's rect. Else in
  -- the room under (or beside) the game's picture, else over its foot

  local rect = { x = 0, y = 0, w = 0, h = 0, on = false }
  P.rect = rect
  local split = { game = { x = 0, y = 0, w = 0, h = 0 }, gear = { x = 0, y = 0, w = 0, h = 0 }, on = false }
  P.split = split
  local function share(size, fallback)
    local n = tonumber(size)
    return max(20, min(80, n or fallback)) / 100
  end
  -- the Gear's combined layout over a w x h window at (bx, by): into `split`; false for none
  -- (COMBINED: the Gear's own options; PHONE / BROWSER, or SEPARATE SCREENS with no second display
  -- there - the Gear's screen somewhere we cannot draw: the same split with its defaults, LAYOUT
  -- auto; FULLSCREEN SWAP: none, the pad takes the whole screen as the Gear's swap does)
  function P.layoutFor(bx, by, width, height)
    split.on = false
    local dm = gearOption("display_mode")
    local combined = dm == "combined"
    if not (combined or dm == "phone" or (dm == "separate" and where() == "main")) then return false end
    local mode = combined and gearOption("combined_layout") or "auto"
    if mode == "auto" then mode = width >= height and "side" or "stacked" elseif mode == "large" then mode = "overlay" end
    local safe = combined and max(0, min(50, tonumber(gearOption("bottom_safe_area")) or 0)) or 0
    height = max(1, height - floor(height * safe / 100))
    local gap = max(2, floor(min(width, height) * 0.01))
    local size = combined and gearOption("secondary_size") or nil
    local g, r = split.game, split.gear
    if mode == "stacked" then
      local gh = floor((height - gap) * share(size, 36))
      g.x, g.y, g.w, g.h = 0, 0, width, height - gh - gap
      r.x, r.y, r.w, r.h = 0, g.h + gap, width, gh
    elseif mode == "side" then
      local gw = floor((width - gap) * share(size, 34))
      g.x, g.y, g.w, g.h = 0, 0, width - gw - gap, height
      r.x, r.y, r.w, r.h = g.w + gap, 0, gw, height
    elseif mode == "overlay" then
      local gh = floor(height * share(size, 42))
      local gw = min(floor(width * (tonumber(size) and share(size, 42) or 0.38)), floor(gh * 160 / 144))
      local corner = gearOption("overlay_corner")
      local left = corner == "top_left" or corner == "bottom_left"
      local top = corner == "top_left" or corner == "top_right"
      g.x, g.y, g.w, g.h = 0, 0, width, height
      r.x, r.y, r.w, r.h = left and gap or width - gw - gap, top and gap or height - gh - gap, gw, gh
    else
      return false
    end
    -- (PRIMARY VIEW on the Gear: the two swapped, as the Gear swaps them)
    if combined and gearOption("combined_primary") == "gear" and mode ~= "overlay" then
      g.x, g.y, g.w, g.h, r.x, r.y, r.w, r.h = r.x, r.y, r.w, r.h, g.x, g.y, g.w, g.h
    end
    g.x, g.y, r.x, r.y = g.x + bx, g.y + by, r.x + bx, r.y + by
    split.on = true
    return true
  end
  -- the game's place while the pad holds the Gear's (main.lua's render.viewport wrap): its rect, or
  -- nil to leave the window's as it is
  local vpOut = { x = 0, y = 0, width = 1, height = 1, capture = true }
  function P.viewport(available, context)
    if not (shownNow and where() == "main") then split.on = false return nil end
    local bx = type(available) == "table" and tonumber(available.x) or 0
    local by = type(available) == "table" and tonumber(available.y) or 0
    local bw = type(available) == "table" and tonumber(available.width) or (context and context.width) or 0
    local bh = type(available) == "table" and tonumber(available.height) or (context and context.height) or 0
    if bw < 8 or bh < 8 or not P.layoutFor(bx, by, bw, bh) then return nil end
    local g = split.game
    vpOut.x, vpOut.y, vpOut.width, vpOut.height = g.x, g.y, g.w, g.h
    return vpOut
  end

  local held = nil
  local function placeOn(viewport)
    -- (the Gear's own rect, the game kept in its game rect)
    if split.on then
      local r = split.gear
      rect.x, rect.y, rect.w, rect.h = r.x, r.y, r.w, r.h
      return
    end
    local G = love.graphics
    local vw = type(viewport) == "table" and viewport.width or G.getWidth()
    local vh = type(viewport) == "table" and viewport.height or G.getHeight()
    local okV, Viewport = pcall(require, "src.render.GameViewport")
    if okV and type(Viewport) == "table" and Viewport.dimensions then vw, vh = Viewport.dimensions() end
    -- (FULLSCREEN SWAP: the whole screen, as the Gear's swap to its own screen - the pad kept to the
    -- second screen's shape, centred, its dark ground over the rest)
    rect.full = nil
    if gearOption("display_mode") == "fullscreen" then
      local aspect = S2 and S2.W / S2.H or (960 / 840)
      local w, h = vw, vw / aspect
      if h > vh then w, h = vh * aspect, vh end
      rect.x, rect.y, rect.w, rect.h = floor((vw - w) / 2), floor((vh - h) / 2), floor(w), floor(h)
      rect.full, rect.fw, rect.fh = true, vw, vh
      return
    end
    local okD, Display = pcall(require, "src.core.game3.display")
    local sx, ox, oy, sy = 1, 0, 0, nil
    if okD and Display and Display.fit then
      local a, b, c, _, _, f = Display.fit(vw, vh)
      sx, ox, oy, sy = a or 1, b or 0, c or 0, f
    end
    sy = sy or sx
    local gx1, gy1 = ox + 240 * sx, oy + 160 * sy
    local below, right = vh - gy1, vw - gx1
    if below >= vh * P.MIN_ROOM then
      rect.x, rect.y, rect.w, rect.h = 0, gy1, vw, below
    elseif right >= vw * P.MIN_ROOM then
      rect.x, rect.y, rect.w, rect.h = gx1, 0, right, vh
    else
      local h = floor(vh * P.OVERLAY)
      rect.x, rect.y, rect.w, rect.h = 0, vh - h, vw, h
    end
  end
  local function paint()
    if rect.w < 8 or rect.h < 8 then return end
    rect.on = true
    local G = love.graphics
    G.push("all")
    G.origin()
    if rect.full then
      G.setColor(0.05, 0.03, 0.09, 1)
      G.rectangle("fill", 0, 0, rect.fw, rect.fh)
      G.setColor(1, 1, 1, 1)
    end
    G.translate(rect.x, rect.y)
    G.setScissor(rect.x, rect.y, rect.w, rect.h)
    local ok, err = pcall(Pad.drawSecond, G, rect.w, rect.h, view, held)
    G.pop()
    if not ok and mod.log then mod.log:warn("dynamax pad draw failed: %s", tostring(err)) end
  end
  -- render.hud (the game's own space): the pad when the window is not split as the Gear's
  function P.drawMain(viewport)
    if split.on then return end
    rect.on = false
    if not shownNow or where() ~= "main" then held = nil return end
    placeOn(viewport)
    paint()
  end
  -- render.window (the window's space, the game's rect already drawn): the pad in the Gear's rect
  function P.drawWindow()
    if not split.on then return end
    rect.on = false
    if not shownNow then held = nil return end
    placeOn(nil)
    paint()
  end

  -- a tap or click on it (input.pointer, window units): down holds a button, up on it presses it
  function P.pointer(ev)
    if type(ev) ~= "table" or not rect.on or not shownNow then return false end
    local x, y = tonumber(ev.x), tonumber(ev.y)
    if not (x and y) then return false end
    local inside = x >= rect.x and y >= rect.y and x <= rect.x + rect.w and y <= rect.y + rect.h
    if not inside then
      if ev.phase == "released" then held = nil end
      return false
    end
    local hit = Pad.hitSecond(x - rect.x, y - rect.y)
    if hit == "panel" then hit = nil end
    if ev.phase == "pressed" then
      held = hit
    elseif ev.phase == "released" then
      local was = held
      held = nil
      if was and hit == was then P.press(was) end
    elseif ev.phase == "moved" then
      if held and hit ~= held then held = nil end
    end
    return true
  end

  return P
end
