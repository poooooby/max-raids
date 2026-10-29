-- The den screen, after Sword / Shield's: on the left a red panel cut on a slant - the stars, the
-- boss's types, its black silhouette, the battle's rule at the foot; on the right, on a pale panel,
-- the four who go in (party icon and name, two by two) and under them START and EXIT (the selected
-- pill black with a chevron). A slot chosen opens a menu beside it - PARTY (the party listed to pick
-- from), PC (the game's boxes, src/pc_pick.lua: SELECT / SUMMARY / BACK), BACK. A Pokemon put in a
-- slot that another slot holds swaps the two. A quiet den says so, with EXIT.
--   Den = den_screen(mod, { Rd, Bosses, Battle, Pick, Pad })
--   Den.open(r)  the slots from the party (the first four that can fight)
--   Den.input(r, input) ; Den.pointer(r, ev) ; Den.draw(G, w, h, r)
--   Den.members(r) -> { { mon }, ... } in slot order ; Den.where (the last draw's rects)
--   (drivers) Den.openMenu(r, i) ; Den.menuChoose(r, "party" | "pc" | "back") ; Den.pickParty(r, j)
--             Den.put(r, i, mon)

return function(mod, deps)
  local Rd, Bosses, Battle, Pick, Pad = deps.Rd, deps.Bosses, deps.Battle, deps.Pick, deps.Pad
  local floor, max, min = math.floor, math.max, math.min
  local Den = {}

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
  local Pokemon = engine("src.core.game3.pokemon")
  local Runtime = engine("src.core.game3.runtime")
  local Audio = engine("src.core.game3.audio")
  local SeIds = engine("src.core.game3.se_ids")

  -- sizes in the window's height (u = h / 360) and width, measured off a 1144 x 610 capture
  Den.LOOK = {
    RED = { 0.96, 0.36, 0.38 }, RED_DARK = { 0.86, 0.22, 0.27, 0.45 },
    PALE_TOP = { 0.95, 0.95, 0.99 }, PALE_FOOT = { 0.86, 0.87, 0.96 },
    SLANT_TOP = 0.67, SLANT_FOOT = 0.42,   -- the red panel's edge across the top and the foot
    RULE_BAND = { 0.55, 0.06, 0.1, 0.95 },
    RULE = { "The battle ends when", "Pokémon faint four times or", "the battle lasts for 10 turns" },
  }
  Den.MENU = { "PARTY", "PC", "BACK" }

  -- a portrait screen's ground past the den screen's box (top .. top + bh of an h tall screen): the
  -- red panel carried on from its edge above and below, the pale one beside it
  function Den.ground(G, w, h, top, bh)
    local L = Den.LOOK
    G.setColor(L.PALE_TOP)
    G.rectangle("fill", 0, 0, w, top)
    G.setColor(L.PALE_FOOT)
    G.rectangle("fill", 0, top + bh, w, h - top - bh)
    G.setColor(L.RED[1], L.RED[2], L.RED[3], 1)
    G.rectangle("fill", 0, 0, w * L.SLANT_TOP, top)
    G.rectangle("fill", 0, top + bh, w * L.SLANT_FOOT, h - top - bh)
  end

  local function se(name)
    local id = SeIds and SeIds[name]
    if id and Audio and Audio.playSe then pcall(Audio.playSe, id) end
  end
  local function session() return Runtime and Runtime.getSession and Runtime.getSession() or nil end

  local function isEgg(mon)
    if Pokemon and Pokemon.isEgg then
      local ok, egg = pcall(Pokemon.isEgg, mon)
      if ok then return egg == true end
    end
    return type(mon) == "table" and mon.isEgg == true
  end
  -- its name as Sword / Shield writes it ("Rillaboom"; the game's are in capitals)
  local function nameOf(mon)
    if Pokemon and Pokemon.displayName then
      local ok, n = pcall(Pokemon.displayName, mon)
      if ok and type(n) == "string" then
        return (n:lower():gsub("^%l", string.upper):gsub("([%s%-%.])(%l)", function(a, b) return a .. b:upper() end))
      end
    end
    return "?"
  end
  local function canFight(mon) return mon ~= nil and not isEgg(mon) and (tonumber(mon.hp) or 1) > 0 end
  local function entry(mon) return { mon = mon, name = nameOf(mon), level = tonumber(mon.level) or 1 } end

  -- the party, eggs left out: { mon, name, level }
  local function roster()
    local out = {}
    local s = session()
    for _, mon in ipairs(s and s.party or {}) do
      if not isEgg(mon) then out[#out + 1] = entry(mon) end
    end
    return out
  end

  function Den.open(r)
    r.party = roster()
    r.slots = {}
    for _, row in ipairs(r.party) do
      if #r.slots >= 4 then break end
      if canFight(row.mon) then r.slots[#r.slots + 1] = row end
    end
    r.cursor, r.denMenu, r.denParty = 1, nil, nil
  end

  function Den.members(r)
    local out = {}
    for i = 1, 4 do
      local s = r.slots and r.slots[i]
      if s then out[#out + 1] = { mon = s.mon } end
    end
    return out
  end
  local function filled(r)
    for i = 1, 4 do if r.slots[i] then return true end end
    return false
  end

  -- a Pokemon into slot i; one another slot holds swaps with what i held
  function Den.put(r, i, mon)
    if not (r.slots and i >= 1 and i <= 4 and canFight(mon)) then return false end
    for j = 1, 4 do
      local s = r.slots[j]
      if j ~= i and s and s.mon == mon then
        r.slots[j] = r.slots[i]
        break
      end
    end
    r.slots[i] = entry(mon)
    -- (its sounds to bake ahead too: the list made again, those kept passed over)
    r.warm = nil
    return true
  end

  function Den.openMenu(r, i)
    if not (r.key and i >= 1 and i <= 4) then return false end
    r.cursor, r.denMenu, r.denParty = i, { slot = i, cursor = 1 }, nil
    return true
  end

  function Den.menuChoose(r, what)
    local m = r.denMenu
    if not m then return false end
    if what == "party" then
      r.denParty = { slot = m.slot, cursor = 1 }
      for j, row in ipairs(r.party) do
        if r.slots[m.slot] and row.mon == r.slots[m.slot].mon then r.denParty.cursor = j end
      end
      return true
    elseif what == "pc" then
      if not (Pick and Pick.available()) then return false end
      local raid, slot = r, m.slot
      r.aside = true
      local ok = Pick.open(session(), {
        onSelect = function(mon) Den.put(raid, slot, mon) end,
        -- (the press that closed it is not the den screen's: one input step skipped)
        onClose = function() raid.aside, raid.skipInput, raid.denMenu = false, true, nil end,
      })
      if not ok then r.aside = false end
      return ok
    end
    r.denMenu = nil
    return true
  end

  function Den.pickParty(r, j)
    local p, row = r.denParty, r.party[j]
    if not (p and row and canFight(row.mon)) then return false end
    Den.put(r, p.slot, row.mon)
    r.denParty, r.denMenu = nil, nil
    return true
  end

  -- ------- the pad
  -- the cursor: 1..4 the slots (1 2 / 3 4), 5 START, 6 EXIT, 7 the Dynamax Crystal (over START, while
  -- the bag holds one or one is in use)
  local UP = { 1, 2, 1, 2, 3, 5, 3 }
  local DOWN = { 3, 4, 5, 5, 6, 6, 5 }
  local SIDE = { 2, 1, 4, 3, 5, 6, 7 }
  local function crystalShown(r) return r.legend or (Rd.crystals and Rd.crystals() > 0) end
  Den.crystalShown = crystalShown
  -- the crystal: in use, put away; else used
  function Den.crystal(r)
    if r.legend then return Rd.putCrystalAway() end
    if not Rd.useCrystal() then se("SE_FAILURE"); return false end
    return true
  end

  function Den.input(r, input)
    local function pressed(k) return input:wasPressed(k) end
    if not r.key then
      -- (a quiet den: the crystal, if any, over EXIT)
      local crystal = crystalShown(r)
      if r.cursor ~= 7 or not crystal then r.cursor = 6 end
      if crystal and (pressed("up") or pressed("down")) then r.cursor = r.cursor == 7 and 6 or 7
      elseif pressed("a") then if r.cursor == 7 then Den.crystal(r) else Rd.close() end
      elseif pressed("b") then Rd.close() end
      return
    end
    local p = r.denParty
    if p then
      local n = #r.party
      if pressed("up") and n > 0 then p.cursor = (p.cursor - 2) % n + 1
      elseif pressed("down") and n > 0 then p.cursor = p.cursor % n + 1
      elseif pressed("a") then if not Den.pickParty(r, p.cursor) then se("SE_FAILURE") end
      elseif pressed("b") then r.denParty = nil end
      return
    end
    local m = r.denMenu
    if m then
      local n = #Den.MENU
      if pressed("up") then m.cursor = (m.cursor - 2) % n + 1
      elseif pressed("down") then m.cursor = m.cursor % n + 1
      elseif pressed("a") then Den.menuChoose(r, Den.MENU[m.cursor]:lower())
      elseif pressed("b") then r.denMenu = nil end
      return
    end
    local c = r.cursor or 1
    local crystal = crystalShown(r)
    if c == 7 and not crystal then c = 5 end
    if pressed("up") then r.cursor = (c == 5 and crystal) and 7 or UP[c]
    elseif pressed("down") then r.cursor = ((c == 3 or c == 4) and crystal) and 7 or DOWN[c]
    elseif pressed("left") or pressed("right") then r.cursor = SIDE[c]
    elseif pressed("a") then
      if c <= 4 then Den.openMenu(r, c)
      elseif c == 5 then if not Rd.denStart() then se("SE_FAILURE") end
      elseif c == 7 then Den.crystal(r)
      else Rd.close() end
    elseif pressed("start") then Rd.denStart()
    elseif pressed("b") then Rd.close() end
  end

  -- ------- touch: the rects of the last draw (window pixels)
  local where = { slots = {}, start = {}, exit = {}, menu = {}, party = {}, partyBack = {}, crystal = {} }
  Den.where = where
  local function inRect(x, y, t) return t and t.w and x >= t.x and x <= t.x + t.w and y >= t.y and y <= t.y + t.h end
  local function rset(t, x, y, w, h) t.x, t.y, t.w, t.h = x, y, w, h; return t end
  local function clear(list) for i = #list, 1, -1 do list[i] = nil end end

  function Den.pointer(r, ev)
    if ev.phase ~= "released" then return true end
    local x, y = ev.x, ev.y
    if inRect(x, y, where.crystal) and not (r.denParty or r.denMenu) then
      r.cursor = 7
      Den.crystal(r)
      return true
    end
    if not r.key then
      if inRect(x, y, where.exit) then Rd.close() end
      return true
    end
    if r.denParty then
      for j, t in ipairs(where.party) do
        if inRect(x, y, t) then
          r.denParty.cursor = j
          if not Den.pickParty(r, j) then se("SE_FAILURE") end
          return true
        end
      end
      if inRect(x, y, where.partyBack) then r.denParty = nil end
      return true
    end
    if r.denMenu then
      for k, t in ipairs(where.menu) do
        if inRect(x, y, t) then
          r.denMenu.cursor = k
          Den.menuChoose(r, Den.MENU[k]:lower())
          return true
        end
      end
      r.denMenu = nil   -- (a tap elsewhere closes it)
      return true
    end
    for i, t in ipairs(where.slots) do
      if inRect(x, y, t) then Den.openMenu(r, i); return true end
    end
    if inRect(x, y, where.start) then
      r.cursor = 5
      if not Rd.denStart() then se("SE_FAILURE") end
    elseif inRect(x, y, where.exit) then
      r.cursor = 6
      Rd.close()
    end
    return true
  end

  -- ------- drawing

  -- (raid.lua's fonts; looked up at the call, as raid.lua sets Rd.font after building this)
  local function font(px) return Rd.font(px) end
  local silShader, silFailed = nil, false
  local function silhouette()
    if silShader or silFailed then return silShader end
    local ok, s = pcall(love.graphics.newShader, [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(color.rgb, color.a * step(0.5, Texel(tex, tc).a));
}
]])
    if ok then silShader = s else silFailed = true end
    return silShader
  end

  -- a party icon (the game's, two frames: the second while chosen, as the party menu bobs it)
  local function drawIcon(G, mon, cx, cy, size, live, t)
    if not (Pokemon and Pokemon.monIcon) then return end
    local ok, e = pcall(Pokemon.monIcon, mon)
    if not (ok and type(e) == "table" and e.image) then return end
    local frame = (live and floor(t * 6) % 2 == 1) and 1 or 0
    local q = e.quads and (e.quads[frame] or e.quads[0])
    local k = size / (e.h or 32)
    pcall(e.image.setFilter, e.image, "nearest", "nearest")
    G.setColor(1, 1, 1, 1)
    if q then G.draw(e.image, q, cx, cy, 0, k, k, (e.w or 32) / 2, (e.h or 32) / 2)
    else G.draw(e.image, cx, cy, 0, k, k, (e.w or 32) / 2, (e.h or 32) / 2) end
  end

  -- the buttons' colours (the battle pad's textured face takes one as its tint and its rim)
  Den.ACCENT = {
    START = { 0.2, 0.75, 0.38 }, EXIT = { 0.9, 0.28, 0.34 }, PARTY = { 0.25, 0.55, 0.95 },
    PC = { 0.62, 0.38, 0.92 }, BACK = { 0.55, 0.56, 0.62 }, SLOT = { 0.92, 0.25, 0.4 },
    CRYSTAL = { 1, 0.24, 0.47 },
  }

  -- a face as the battle pad's (src/pad.lua Pad.face: brushed, a gloss, a bevel; dark when
  -- selected, pressed in), a soft shadow under it while it stands up, a rim in its colour
  local function face(G, t, rad, sel, accent, u, corner)
    if not sel then
      G.setColor(0.25, 0.25, 0.45, 0.22)
      G.rectangle("fill", t.x + 2 * u, t.y + 3 * u, t.w, t.h, rad, rad)
    end
    local y = t.y + (sel and 2 * u or 0)
    if Pad and Pad.face then
      Pad.face(G, t.x, y, t.w, t.h, rad, Pad.faceOpts(sel, sel, accent, corner, sel and 0.25 or 0.1))
    else
      if sel then G.setColor(0.08, 0.08, 0.1, 1) else G.setColor(1, 1, 1, 1) end
      G.rectangle("fill", t.x, y, t.w, t.h, rad, rad)
    end
    if sel and accent then
      G.setColor(accent[1], accent[2], accent[3], 0.9)
      G.setLineWidth(max(1.5, t.h * 0.05))
      G.rectangle("line", t.x, y, t.w, t.h, rad, rad)
    end
    return y
  end

  -- the chevron before the selected one: black with a white stroke inside, as the battle pad's
  local function chevron(G, t)
    local hh = t.h * 0.2
    if Pad and Pad.chevronAt then return Pad.chevronAt(G, t.x - t.h * 0.1 - hh * 0.3, t.y + t.h / 2, hh) end
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(t.h * 0.09)
    G.line(t.x - t.h * 0.3, t.y + t.h * 0.3, t.x - t.h * 0.1, t.y + t.h / 2, t.x - t.h * 0.3, t.y + t.h * 0.7)
  end

  -- a pill: the face, the words bold (the default face twice, a pixel apart), a chevron when selected
  local function pill(G, t, word, sel, u, live, accent, alone)
    local y = face(G, t, t.h / 2, sel, accent or Den.ACCENT[word] or Den.ACCENT.BACK, u)
    if sel and not alone then chevron(G, t) end
    local f = font(t.h * 0.46)
    G.setFont(f)
    if sel then G.setColor(1, 1, 1, live == false and 0.5 or 1)
    else G.setColor(0.08, 0.08, 0.1, live == false and 0.4 or 1) end
    local ty = y + (t.h - f:getHeight()) / 2
    G.printf(word, t.x, ty, t.w, "center")
    G.printf(word, t.x + max(1, u * 0.8), ty, t.w, "center")
  end

  -- the types' icons (assets/ui/types/<TYPE>.png: a white sign on a disc of its colour), loaded once
  -- each (false: not there, the colour's disc and the initial stand in)
  local typeIcons = {}
  local function typeIcon(typeName)
    local key = (typeName or ""):upper()
    if typeIcons[key] == nil then
      typeIcons[key] = false
      local ok, img = pcall(function()
        local bytes = mod:read("assets/ui/types/" .. key .. ".png")
        if not bytes then return nil end
        local i = love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, key .. ".png")))
        i:setFilter("linear", "linear")
        return i
      end)
      if ok and img then typeIcons[key] = img end
    end
    return typeIcons[key] or nil
  end

  -- a type's badge: its icon, the name on a dark slanted plate behind it
  local function typeBadge(G, x, y, u, typeName)
    local rgb = Battle and Battle.TYPE_RGB and Battle.TYPE_RGB[typeName] or { 0.6, 0.6, 0.6 }
    local h = 22 * u
    local d = h * 1.3
    local f = font(13 * u)
    local word = typeName:upper()
    local tw = f:getWidth(word) + 26 * u
    G.setColor(0.3, 0.27, 0.28, 0.92)
    G.polygon("fill", x + h * 0.6, y, x + h + tw, y, x + h + tw - h * 0.3, y + h, x + h * 0.6, y + h)
    local cx, cy = x + h / 2, y + h / 2
    local img = typeIcon(typeName)
    if img then
      local k = d / img:getWidth()
      G.setColor(0, 0, 0, 0.25)
      G.circle("fill", cx + u, cy + 1.5 * u, d / 2, 32)
      G.setColor(1, 1, 1, 1)
      G.draw(img, cx, cy, 0, k, k, img:getWidth() / 2, img:getHeight() / 2)
    else
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.circle("fill", cx, cy, d / 2, 32)
      G.setColor(1, 1, 1, 1)
      G.setFont(font(14 * u))
      G.printf(word:sub(1, 1), x, y + (h - font(14 * u):getHeight()) / 2, h, "center")
    end
    G.setFont(f)
    G.setColor(1, 1, 1, 1)
    G.print(word, x + h + 10 * u, y + (h - f:getHeight()) / 2)
    return tw + h
  end

  -- the panels: the red one on the left (with the den's dark stripes), the pale one over its right
  local function panels(G, w, h, t)
    local L = Den.LOOK
    G.setColor(L.RED[1], L.RED[2], L.RED[3], 1)
    G.rectangle("fill", 0, 0, w, h)
    local c = L.RED_DARK
    G.setColor(c[1], c[2], c[3], c[4])
    -- (the den's emblem, a broad X and a beam, faint in the red)
    local cx, cy, s = w * 0.2, h * 0.42, h * 0.5
    G.polygon("fill", cx - s * 1.1, cy - s * 0.15, cx + s * 0.2, cy - s * 0.95, cx + s * 0.45, cy - s * 0.7, cx - s * 0.75, cy + s * 0.25)
    G.polygon("fill", cx - s * 0.2, cy - s * 0.55, cx + s * 0.05, cy - s * 0.8, cx + s * 1.2, cy + s * 0.75, cx + s * 0.9, cy + s * 1.0)
    G.polygon("fill", cx - s * 1.0, cy + s * 0.9, cx + s * 0.1, cy + s * 0.1, cx + s * 0.35, cy + s * 0.35, cx - s * 0.6, cy + s * 1.2)
    G.setColor(1, 1, 1, 0.06)
    G.polygon("fill", w * 0.12, h * 0.42, w * 0.55, h * 0.36, w * 0.55, h * 0.44, w * 0.12, h * 0.46)
    -- the pale panel, lighter at the top
    local x0, x1 = w * L.SLANT_TOP, w * L.SLANT_FOOT
    local pt, pf = L.PALE_TOP, L.PALE_FOOT
    local steps = 8
    for k = 0, steps - 1 do
      local a, b = k / steps, (k + 1) / steps
      local e = (a + b) / 2
      G.setColor(pt[1] + (pf[1] - pt[1]) * e, pt[2] + (pf[2] - pt[2]) * e, pt[3] + (pf[3] - pt[3]) * e, 1)
      G.polygon("fill", x0 + (x1 - x0) * a, h * a, w, h * a, w, h * b, x0 + (x1 - x0) * b, h * b)
    end
    -- its texture, as the battle pad's backdrop: a faint hexagon grid deepening toward the foot,
    -- light streaks slanting across and drifting (kept right of the slant)
    local cell = h * 0.07
    local cos, sin, pi = math.cos, math.sin, math.pi
    G.setLineWidth(1)
    for row = 0, math.ceil(h / (cell * 0.87)) do
      local yy = row * cell * 0.87
      local a = 0.1 * (yy / h)
      if a > 0.008 then
        G.setColor(0.45, 0.4, 0.75, a)
        local edge = x0 + (x1 - x0) * (yy / h)
        for col = 0, math.ceil(w / (cell * 1.5)) do
          local xx = (col + (row % 2) * 0.5) * cell * 1.5
          if xx - cell * 0.5 > edge then
            for k = 0, 5 do
              local a0, a1 = k * pi / 3, (k + 1) * pi / 3
              G.line(xx + cos(a0) * cell * 0.5, yy + sin(a0) * cell * 0.5, xx + cos(a1) * cell * 0.5, yy + sin(a1) * cell * 0.5)
            end
          end
        end
      end
    end
    G.setBlendMode("add")
    for k = 0, 4 do
      local s0 = x1 + ((k * 0.23 + (t or 0) * 0.015) % 1) * (w - x1)
      G.setColor(0.35, 0.3, 0.5, 0.05 + 0.02 * (k % 2))
      G.polygon("fill", s0 + w * 0.08, 0, s0 + w * 0.11, 0, s0 + w * 0.02, h, s0 - w * 0.01, h)
    end
    G.setBlendMode("alpha")
  end

  local function drawLeft(G, w, h, u, r)
    local b = Bosses[r.key]
    -- the stars, white, from the top left
    G.setColor(1, 1, 1, 1)
    local size = 26 * u
    Rd.drawStars(G, b.stars, 22 * u + b.stars * size * 1.1, 42 * u, size)
    -- (a Dynamax Crystal's: a legendary Pokemon, said under the stars)
    if r.legend then
      G.setFont(font(14 * u))
      G.setColor(1, 0.85, 0.9, 1)
      G.print("A LEGENDARY POK\195\137MON", 22 * u, 60 * u)
    end
    -- its types
    local ty = 84 * u
    for _, t in ipairs(b.types or {}) do
      typeBadge(G, 22 * u, ty, u, t)
      ty = ty + 28 * u
    end
    -- the silhouette: black, nearest, whole, on the panel's middle
    local img, q = Rd.frameAt(r.key, r.t)
    local box = Rd.bossBox and Rd.bossBox()
    if img and box then
      local bw, bh = box[3] - box[1], box[4] - box[2]
      local k = min((h * 0.36) / bh, (w * 0.26) / bw)
      local cx, cy = w * 0.24, h * 0.56
      local s = silhouette()
      if s then G.setShader(s) end
      pcall(img.setFilter, img, "nearest", "nearest")
      G.setColor(0, 0, 0, 1)
      G.draw(img, q, cx, cy, 0, k, k, (box[1] + box[3]) / 2, (box[2] + box[4]) / 2)
      G.setShader()
    end
    -- the rule at the foot
    -- (one slanted plate behind all its lines, as wide as the longest)
    local L = Den.LOOK
    local f = font(13 * u)
    G.setFont(f)
    local lh, pad = f:getHeight() * 1.1, 6 * u
    local bandH = pad * 2 + lh * (#L.RULE - 1) + f:getHeight()
    local bandY = h - 78 * u
    local bw = 0
    for _, line in ipairs(L.RULE) do bw = max(bw, f:getWidth(line)) end
    bw = bw + 30 * u
    local c = L.RULE_BAND
    G.setColor(c[1], c[2], c[3], c[4])
    G.polygon("fill", 0, bandY, bw + bandH * 0.3, bandY, bw, bandY + bandH, 0, bandY + bandH)
    G.setColor(1, 1, 1, 1)
    for i, line in ipairs(L.RULE) do G.print(line, 14 * u, bandY + pad + (i - 1) * lh) end
  end

  -- the slots, two by two: the icon and the name (a soft card behind, ringed while the cursor is on it)
  local function drawSlots(G, w, h, u, r)
    local x0, x1 = w * 0.6, w * 0.97
    local cw, ch = (x1 - x0 - 12 * u) / 2, 40 * u
    local y0 = h * 0.3
    local busy = r.denMenu or r.denParty
    -- (one size for the four names: the largest at which every one fits its card)
    local px = 15 * u
    for i = 1, 4 do
      local s = r.slots[i]
      if s then
        local room = cw - ch * 1.1 - 8 * u
        local wd = font(px):getWidth(s.name)
        if wd > room then px = px * room / wd end
      end
    end
    local nameFont = font(px)
    for i = 1, 4 do
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local t = rset(where.slots[i] or {}, x0 + col * (cw + 12 * u), y0 + row * (ch + 10 * u), cw, ch)
      where.slots[i] = t
      local on = (r.cursor == i and not r.denParty) or (r.denMenu and r.denMenu.slot == i)
      -- (the battle pad's face: dark and pressed in while chosen, its corner in the den's red)
      local fy = face(G, t, 10 * u, on and true or false, Den.ACCENT.SLOT, u, true)
      local s = r.slots[i]
      local f = font(15 * u)
      G.setFont(f)
      if s then
        drawIcon(G, s.mon, t.x + ch * 0.62, fy + ch * 0.48, ch * 0.95, on and not busy, r.t)
        f = nameFont
        G.setFont(f)
        if on then G.setColor(1, 1, 1, 1) else G.setColor(0.08, 0.08, 0.1, 1) end
        local ty = fy + (ch - f:getHeight()) / 2
        G.print(s.name, t.x + ch * 1.15, ty)
        G.print(s.name, t.x + ch * 1.15 + max(1, u * 0.7), ty)
      else
        if on then G.setColor(0.8, 0.8, 0.85, 1) else G.setColor(0.45, 0.46, 0.55, 1) end
        G.print("—", t.x + ch * 0.5, fy + (ch - f:getHeight()) / 2)
      end
    end
  end

  -- the slot's menu, left of the slots level with the chosen slot's row (the slot stays ringed)
  local function drawMenu(G, w, h, u, r)
    -- (put away while the party list is up: the list stands where it was)
    local m = r.denMenu
    if not m or r.denParty then clear(where.menu); return end
    local s = where.slots[m.slot]
    local pw, ph = w * 0.12, 30 * u
    local x = where.slots[1].x - pw - 22 * u
    local y = s.y
    -- (an opaque card with a shadow, room on its left for the chevron)
    local cx0, cy0 = x - 28 * u, y - 10 * u
    local cw, chh = pw + 38 * u, #Den.MENU * (ph + 6 * u) + 14 * u
    G.setColor(0.2, 0.2, 0.35, 0.3)
    G.rectangle("fill", cx0 + 3 * u, cy0 + 5 * u, cw, chh, 14 * u, 14 * u)
    G.setColor(0.86, 0.87, 0.95, 1)
    G.rectangle("fill", cx0, cy0, cw, chh, 14 * u, 14 * u)
    for k = #where.menu, #Den.MENU + 1, -1 do where.menu[k] = nil end
    for k, word in ipairs(Den.MENU) do
      local t = rset(where.menu[k] or {}, x, y + (k - 1) * (ph + 6 * u), pw, ph)
      where.menu[k] = t
      pill(G, t, word, m.cursor == k, u)
    end
  end

  -- the party to pick from: a card over the pale panel, a row a Pokemon (icon, name, level);
  -- fainted ones dimmed (the slots show who is where)
  local function drawParty(G, w, h, u, r)
    local p = r.denParty
    clear(where.party)
    rset(where.partyBack, 0, 0, 0, 0)
    if not p then return end
    local x, y, cw = w * 0.56, h * 0.1, w * 0.41
    local rowH = 34 * u
    local ch = 40 * u + #r.party * (rowH + 4 * u) + 46 * u
    G.setColor(0, 0, 0, 0.25)
    G.rectangle("fill", x + 3 * u, y + 4 * u, cw, ch, 12 * u, 12 * u)
    G.setColor(0.97, 0.97, 1, 1)
    G.rectangle("fill", x, y, cw, ch, 12 * u, 12 * u)
    G.setFont(font(15 * u))
    G.setColor(0.1, 0.1, 0.12, 1)
    G.print(("Who goes in slot %d?"):format(p.slot), x + 16 * u, y + 12 * u)
    for j, row in ipairs(r.party) do
      local t = rset(where.party[j] or {}, x + 10 * u, y + 40 * u + (j - 1) * (rowH + 4 * u), cw - 20 * u, rowH)
      where.party[j] = t
      local sel = p.cursor == j
      local live = canFight(row.mon)
      local fy = face(G, t, rowH / 2, sel, Den.ACCENT.SLOT, u)
      drawIcon(G, row.mon, t.x + rowH * 0.62, fy + rowH * 0.48, rowH * 0.95, sel and live, r.t)
      local f = font(14 * u)
      G.setFont(f)
      local ink = sel and 1 or 0.08
      G.setColor(ink, ink, ink, live and 1 or 0.4)
      local ty = fy + (rowH - f:getHeight()) / 2
      G.print(row.name, t.x + rowH * 1.25, ty)
      G.print(row.name, t.x + rowH * 1.25 + max(1, u * 0.7), ty)
      local right = live and ("Lv. " .. row.level) or "Fainted"
      G.printf(right, t.x, ty, t.w - 16 * u, "right")
    end
    local back = rset(where.partyBack, x + cw - 110 * u, y + ch - 38 * u, 96 * u, 28 * u)
    pill(G, back, "BACK", false, u)
  end

  function Den.draw(G, w, h, r)
    local u = h / 360
    panels(G, w, h, r.t)
    -- the Dynamax Crystal's pill (how many the bag holds; "Put it away" while one is in use)
    local function crystalPill(y, sel)
      if not crystalShown(r) then rset(where.crystal, 0, 0, 0, 0); return end
      local t = rset(where.crystal, w * 0.62, y, w * 0.34, 34 * u)
      local word = r.legend and "PUT IT AWAY" or ("DYNAMAX CRYSTAL x%d"):format(Rd.crystals())
      pill(G, t, word, sel, u, true, Den.ACCENT.CRYSTAL)
    end
    if not r.key then
      G.setFont(font(22 * u))
      G.setColor(1, 1, 1, 1)
      G.printf("The den is quiet.", 0, h * 0.36, w * 0.5, "center")
      G.setFont(font(14 * u))
      local more = crystalShown(r) and "\nA Dynamax Crystal could call\na legendary Pok\195\169mon here." or ""
      G.printf("Nothing stirs here today.\nCome back tomorrow." .. more, 0, h * 0.36 + 34 * u, w * 0.5, "center")
      clear(where.slots)
      rset(where.start, 0, 0, 0, 0)
      local t = rset(where.exit, w * 0.62, h - 70 * u, w * 0.34, 34 * u)
      -- (the screen's one button without a crystal: lit, no chevron)
      pill(G, t, "EXIT", r.cursor ~= 7, u, nil, nil, not crystalShown(r))
      crystalPill(h - 114 * u, r.cursor == 7)
      return
    end
    drawLeft(G, w, h, u, r)
    drawSlots(G, w, h, u, r)
    -- START and EXIT near the foot, the crystal over them
    local bx, bw2, bh = w * 0.62, w * 0.34, 34 * u
    local ts = rset(where.start, bx, h - 104 * u, bw2, bh)
    local te = rset(where.exit, bx, h - 60 * u, bw2, bh)
    local menus = r.denMenu or r.denParty
    pill(G, ts, "START", r.cursor == 5 and not menus, u, filled(r))
    pill(G, te, "EXIT", r.cursor == 6 and not menus, u)
    crystalPill(h - 148 * u, r.cursor == 7 and not menus)
    drawMenu(G, w, h, u, r)
    drawParty(G, w, h, u, r)
  end

  return Den
end
