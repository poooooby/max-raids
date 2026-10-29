-- The den screen's PC: the game's own Pokemon Storage System (src/ui/game3/box_storage_ui.lua), opened
-- to choose a Pokemon from a box and nothing else. Its boxes, cursor, wallpapers, box switching and
-- closing are the game's; while it is up its input passes through a filter here:
--   A on a boxed Pokemon     our menu, in the game's window frame and font: SELECT / SUMMARY / BACK
--                            (SELECT: it is chosen and the PC closes; SUMMARY: the game's summary,
--                            read only, then back to the menu; BACK: the menu closes)
--   A on the box's name, on PARTY POKEMON, on an empty slot, SELECT, START: nothing (no box menu,
--                            no party drawer, no move - the save is never changed here)
--   everything else          the game's (moving, L / R and the edges switch boxes, B or CLOSE BOX close)
--   Pick = pc_pick(mod) ; Pick.open(session, { onSelect = function(mon), onClose = function() })
--   Pick.isOpen() ; Pick.state() (drivers) ; Pick.press(key) (drivers: a key through the filter)

return function(mod)
  -- an engine module (found ones kept: a mod's require makes garbage each call)
  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m then return m end
    local ok
    ok, m = pcall(require, name)
    m = ok and type(m) == "table" and m or nil
    engineMods[name] = m
    return m
  end
  local Box = engine("src.ui.game3.box_storage_ui")
  local Storage = engine("src.core.game3.storage")
  local Window = engine("src.ui.game3.window")
  local SummaryMenu = engine("src.ui.game3.summary_menu")
  local Audio = engine("src.core.game3.audio")
  local SeIds = engine("src.core.game3.se_ids")

  local Pick = {}
  Pick.ACTIONS = { "SELECT", "SUMMARY", "BACK" }
  local st = nil   -- { session, onSelect, onClose, menu = { cursor, mon, box, slot } | nil, summary }
  local origInput, origDraw = nil, nil

  local function se(name)
    local id = SeIds and SeIds[name]
    if id and Audio and Audio.playSe then pcall(Audio.playSe, id) end
  end

  -- the input with some presses taken away (the game's code reads input:wasPressed(key))
  local function without(input, blocked)
    return setmetatable({ wasPressed = function(self, key)
      if blocked[key] then return false end
      return input:wasPressed(key)
    end }, { __index = input })
  end

  local function boxedAt(slot)
    local storage = Storage and Storage.ensure(st.session)
    local box = storage and storage.boxes[storage.currentBox or 1]
    return box and box.mons[slot], storage and storage.currentBox or 1
  end

  -- the game's summary of the boxed Pokemon (the box's others with it, L / R through them), read only
  local function summary()
    local m = st.menu
    local storage = Storage and Storage.ensure(st.session)
    local box = storage and storage.boxes[m.box]
    if not (box and SummaryMenu and SummaryMenu.openMenu) then return end
    local mons, at = {}, 1
    for s = 1, (Storage.IN_BOX_COUNT or 30) do
      local mon = box.mons[s]
      if mon then
        mons[#mons + 1] = mon
        if s == m.slot then at = #mons end
      end
    end
    local open = st
    open.summary = true
    local ok = pcall(SummaryMenu.openMenu, mons, at, { session = open.session, context = "factory",
      onClose = function() open.summary = false; open.skip = true end })
    if not ok then open.summary = false end
  end

  local BLOCK_ALL = { a = true, select = true, start = true }
  local BLOCK_MENUS = { select = true, start = true }

  local function filter(input)
    if not (st and Box.open) then return origInput(input) end
    if st.skip then st.skip = nil; return end
    local m = st.menu
    if m then
      local n = #Pick.ACTIONS
      if input:wasPressed("up") then m.cursor = (m.cursor - 2) % n + 1; se("SE_SELECT")
      elseif input:wasPressed("down") then m.cursor = m.cursor % n + 1; se("SE_SELECT")
      elseif input:wasPressed("b") then st.menu = nil; se("SE_SELECT")
      elseif input:wasPressed("a") then
        local act = Pick.ACTIONS[m.cursor]
        se("SE_SELECT")
        if act == "SELECT" then
          local mon, cb = m.mon, st.onSelect
          st.menu, st.picked = nil, true
          Pick.close()
          if cb then cb(mon) end
        elseif act == "SUMMARY" then summary()
        else st.menu = nil end
      end
      return
    end
    if Box.mode ~= "browse" then return origInput(input) end
    local slot = Box.cursorSlot
    if input:wasPressed("a") then
      if slot == -20 then return origInput(input) end   -- (CLOSE BOX)
      if slot and slot >= 1 and slot <= 30 then
        local mon, boxId = boxedAt(slot)
        if mon then
          st.menu = { cursor = 1, mon = mon, box = boxId, slot = slot }
          se("SE_SELECT")
        end
      end
      return origInput(without(input, BLOCK_ALL))
    end
    return origInput(without(input, BLOCK_MENUS))
  end

  -- the menu, as the game's own action menu draws (its frame, its font, the arrow)
  local function draw(...)
    origDraw(...)
    if not (st and st.menu and Window) then return end
    local menuLeft, menuTop, textLeft = 13, 5, 114
    local th = #Pick.ACTIONS * 2
    pcall(function()
      Window.stdFrame(Window.template(menuLeft, menuTop, 10, th))
      for i, act in ipairs(Pick.ACTIONS) do
        local y = (menuTop * 8 + 2) + (i - 1) * 16
        if i == st.menu.cursor then Window.cursorPx(textLeft - 8, y) end
        Window.printPx(act, textLeft, y)
      end
    end)
  end

  function Pick.available() return Box ~= nil and Box.show ~= nil and Storage ~= nil end
  function Pick.isOpen() return st ~= nil end
  function Pick.state() return st end

  function Pick.open(session, opts)
    if st or not Pick.available() or Box.open then return false end
    st = { session = session, onSelect = opts and opts.onSelect, onClose = opts and opts.onClose }
    origInput, origDraw = Box.handleInput, Box.draw
    Box.handleInput, Box.draw = filter, draw
    local open = st
    local ok, err = pcall(Box.show, { session = session, subMode = "withdraw", onClose = function()
      -- (the game closed it: B, CLOSE BOX, or our SELECT)
      if st ~= open then return end
      Box.handleInput, Box.draw = origInput, origDraw
      st = nil
      if open.onClose then open.onClose(open.picked) end
    end })
    if not ok then
      Box.handleInput, Box.draw = origInput, origDraw
      st = nil
      mod.log:warn("the PC could not open: %s", tostring(err))
      return false
    end
    return true
  end

  -- closed as the game closes it (its leaving sound), the filter taken off
  function Pick.close()
    if not (st and Box.open) then return false end
    se("SE_PC_OFF")
    pcall(Box.close)
    return true
  end

  -- (drivers) a key pressed through the filter, as one input step
  function Pick.press(key)
    if not st then return false end
    local fake = { wasPressed = function(_, k) return k == key end, isDown = function(_, k) return k == key end }
    Box.handleInput(fake)
    return true
  end

  return Pick
end
