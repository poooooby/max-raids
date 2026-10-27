-- The battle pad on the device's second screen (BATTLE PAD: SECOND SCREEN): the engine's
-- SecondScreen bridge (src/render/SecondScreen.lua: the Android second display, or the desktop
-- companion window). Each update step - never inside a draw, where switching to a canvas breaks
-- Android - the pad (src/pad.lua Pad.drawSecond) is drawn into a canvas of its own and read back
-- without stalling the GPU (requestImageData / pollImageData where LOVE has them, as Kanto Gear and
-- PlayNav do; else the blocking read), then pushed; its taps come back through pollTouch in the
-- pushed frame's pixels. Kanto Gear stands down meanwhile (main.lua's store module).
--   S2 = screen2(mod, { Pad, raid = Raid, on = function() -> bool, press = function(id, released) })
--   S2.update(now) ; S2.active() ; S2.bridge (a stand-in for drivers; false = none)

return function(mod, deps)
  local S2 = { W = 960, H = 840, FPS = 30, STALE_S = 1.0 }
  local Pad = deps.Pad
  local state = { canvas = nil, pending = nil, pushAt = -1, held = nil, enabled = false, retryAt = 0,
    shown = false, pushes = 0 }
  S2.state = state

  local real = nil
  local function bridge()
    if S2.bridge ~= nil then return S2.bridge or nil end
    if real == nil then
      local ok, SS = pcall(require, "src.render.SecondScreen")
      real = ok and type(SS) == "table" and SS or false
    end
    return real or nil
  end
  local function call(SS, name, ...)
    local f = SS[name]
    if type(f) ~= "function" then return nil end
    local ok, a, b, c = pcall(f, ...)
    if ok then return a, b, c end
    return nil
  end

  -- the display is there (the pad goes to it only then; without it, the main screen keeps the pad)
  function S2.detected()
    local SS = bridge()
    return SS ~= nil and call(SS, "detected") == true
  end

  -- up when the option says so, a raid is on and the display is there
  function S2.active()
    if not (deps.on and deps.on()) then return false end
    local raid = deps.raid
    if not (raid and raid.active and raid.active()) then return false end
    local SS = bridge()
    return SS ~= nil and call(SS, "detected") == true
  end

  local function parse(str)
    if type(str) ~= "string" then return nil end
    local action, x, y = str:match("^%s*(%a+)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
    if not action then return nil end
    return action:lower(), tonumber(x), tonumber(y)
  end

  -- a finger on the frame: down holds a button (pressed in, the selection on it), up on the same
  -- button picks it, off it or cancelled lets go
  function S2.touch(action, x, y)
    local hit = Pad.hitSecond(x, y)
    if action == "down" then
      state.held = hit
      if hit and deps.press then deps.press(hit, false) end
    elseif action == "move" then
      if state.held and hit ~= state.held then state.held = nil end
    elseif action == "up" then
      local was = state.held
      state.held = nil
      if was and hit == was and deps.press then deps.press(was, true) end
    else
      state.held = nil
    end
  end

  local function drawFrame(r)
    local G = love.graphics
    if not state.canvas then
      local ok, c = pcall(G.newCanvas, S2.W, S2.H, { dpiscale = 1 })
      if not ok then return nil end
      state.canvas = c
    end
    G.push("all")
    G.origin()
    G.setCanvas(state.canvas)
    G.clear(0, 0, 0, 1)
    local ok, err = pcall(Pad.drawSecond, G, S2.W, S2.H, r, state.held)
    G.setCanvas()
    G.pop()
    if not ok then mod.log:warn("second screen draw failed: %s", tostring(err)) end
    return state.canvas
  end

  -- one frame out, its pixels freed at once (the bridge copies them)
  local function push(SS, data)
    local shown = call(SS, "push", data, S2.W, S2.H, 0x000000, "secondary")
    if data and data.release then pcall(data.release, data) end
    state.shown = shown ~= false and shown ~= nil
    state.pushes = state.pushes + 1
  end

  function S2.update(now)
    if not S2.active() then
      state.held, state.pending, state.enabled = nil, nil, false
      return false
    end
    local SS = bridge()
    now = now or (love.timer and love.timer.getTime() or 0)
    -- (Android posts work for every enable call: once on the way in, then once a second only while
    -- frames are not getting through)
    if not state.enabled or (not state.shown and now >= state.retryAt) then
      call(SS, "setEnabled", true)
      state.enabled, state.retryAt = true, now + 1
    end
    for _ = 1, 64 do
      local ev = call(SS, "pollTouch")
      if not ev then break end
      local action, x, y = parse(ev)
      if action and x and y then S2.touch(action, x, y) end
    end
    -- a frame read back since the last step goes out now
    local p = state.pending
    if p then
      local ok, data = pcall(p.src.pollImageData, p.src)
      if not ok then state.pending = nil
      elseif data then state.pending = nil; push(SS, data)
      elseif now - p.at > S2.STALE_S then
        state.pending = nil
        if state.canvas and state.canvas.release then pcall(state.canvas.release, state.canvas) end
        state.canvas = nil
      end
    end
    if state.pending or now - state.pushAt < 1 / S2.FPS then return true end
    local avail = call(SS, "available")
    if avail == false then return true end
    state.pushAt = now
    local raid = deps.raid
    local src = drawFrame(raid and raid.current and raid.current())
    if not src then return true end
    if src.requestImageData and src.pollImageData then
      local ok, started = pcall(src.requestImageData, src)
      if ok and started ~= false then
        state.pending = { src = src, at = now }
        return true
      end
    end
    local ok, data = pcall(src.newImageData, src)
    if ok and data then push(SS, data) end
    return true
  end

  return S2
end
