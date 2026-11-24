-- panel.lua: the advice shown. A Trainer Desk panel with everything (the two
-- switches, the best play, every move with its numbers, what the foe can do
-- and how each team mate would fare), and a small box on the battle screen
-- with the best play only.
return function(env)
  local G = love.graphics
  local T, F = env.T, env.F
  local floor, max, min = math.floor, math.max, math.min
  local Panel = { W = 480, H = 432 }

  local fonts = {}
  local function font(size)
    size = max(8, floor(size + 0.5))
    if not fonts[size] then fonts[size] = env.font(size) end
    return fonts[size]
  end
  local function hex(v) return { tonumber(v:sub(1, 2), 16) / 255, tonumber(v:sub(3, 4), 16) / 255, tonumber(v:sub(5, 6), 16) / 255 } end
  local C = { bg = hex("0f1216"), card = hex("1b1f26"), line = hex("2f3742"), text = hex("e6ebf2"), muted = hex("9aa5b4"),
    accent = hex("4f9cf7"), go = hex("2f9e58"), warn = hex("d1912a"), bad = hex("d0524a"), off = hex("252b34") }
  function Panel.theme(colors)
    if type(colors) ~= "table" then return end
    C.bg, C.card, C.off = colors.panel or C.bg, colors.dock or C.card, colors.tabActive or C.off
    C.text, C.muted, C.accent = colors.textActive or C.text, colors.text or C.muted, colors.accent or C.accent
  end

  local kx, ky, kf, hits = 1, 1, 1, {}
  local function color(c, a) G.setColor(c[1], c[2], c[3], a or 1) end
  local function box(x, y, w, h, c, r)
    color(c)
    G.rectangle("fill", floor(x * kx), floor(y * ky), floor(w * kx + 0.5), floor(h * ky + 0.5), (r or 5) * kf, (r or 5) * kf)
  end
  local function shorten(f, str, room)
    str = tostring(str)
    if f:getWidth(str) <= room then return str end
    local list = {}
    for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list + 1] = ch end
    while #list > 0 and f:getWidth(table.concat(list) .. "..") > room do list[#list] = nil end
    return table.concat(list) .. ".."
  end
  local function line(str, x, y, c, size, room, align)
    local f = font(size * kf)
    G.setFont(f); color(c)
    room = max(1, room * kx)
    str = shorten(f, str, room)
    local px = x * kx
    if align == "right" then px = px + room - f:getWidth(str) end
    G.print(str, floor(px), floor(y * ky))
  end
  local function toggle(label, x, y, w, value, action)
    box(x, y, w, 24, C.card)
    line(label, x + 8, y + 5, C.text, 12, w - 58)
    local sw, sh = 36 * kf, 18 * kf
    local sx, sy = (x + w) * kx - sw - 8 * kf, y * ky + (24 * ky - sh) / 2
    color(value and C.accent or C.line)
    G.rectangle("fill", sx, sy, sw, sh, sh / 2, sh / 2)
    color(C.text)
    G.circle("fill", value and sx + sw - sh / 2 or sx + sh / 2, sy + sh / 2, sh / 2 - 3 * kf)
    hits[#hits + 1] = { x = x * kx, y = y * ky, w = w * kx, h = 24 * ky, action = action }
  end
  local function notes(list)
    local names, out = T("NOTES"), {}
    for _, code in ipairs(list or {}) do
      out[#out + 1] = type(names) == "table" and names[code] or code
    end
    return table.concat(out, " · ")
  end
  local function range(lo, hi)
    if lo == hi then return lo .. "%" end
    return lo .. "-" .. hi .. "%"
  end
  local function dot(x, y, c)
    color(c)
    G.circle("fill", x * kx, y * ky, 4 * kf)
  end

  function Panel.draw(clock, w, h)
    hits = {}
    w, h = tonumber(w) or Panel.W, tonumber(h) or Panel.H
    kx, ky = max(0.6, min(2.4, w / Panel.W)), max(0.6, min(2.4, h / Panel.H))
    kf = max(0.75, min(1.5, min(kx, ky)))
    G.push("all")
    color(C.bg); G.rectangle("fill", 0, 0, w, h)
    toggle(T("AUTO"), 10, 8, 228, env.get("auto"), function() env.set("auto", not env.get("auto")) end)
    toggle(T("ADVISOR"), 242, 8, 228, env.get("advisor"), function() env.set("advisor", not env.get("advisor")) end)
    local v = env.view(clock)
    if not v then
      line(T("NO_BATTLE"), 14, 60, C.muted, 12, 452)
      line(T("NO_BATTLE_2"), 14, 80, C.muted, 11, 452)
      G.pop()
      return
    end
    -- the best play
    box(10, 40, 460, 46, C.card)
    line(T("BEST_LABEL"), 18, 44, C.accent, 9, 200)
    line(v.me .. "  >  " .. v.foeName, 220, 44, C.muted, 9, 242, "right")
    line(v.headline, 18, 56, C.text, 15, 300)
    line(T(v.faster and "YOU_FIRST" or "FOE_FIRST"), 320, 60, v.faster and C.go or C.warn, 10, 142, "right")
    local y = 90
    if v.danger or v.heal then
      line(T(v.danger and "DANGER" or "HEAL_HINT"), 14, y, v.danger and C.bad or C.warn, 10, 452)
      y = y + 15
    end
    -- your moves
    line(T("YOUR_MOVES"), 14, y, C.muted, 9, 200); line(T("OF_FOE_HP"), 250, y, C.muted, 9, 220, "right")
    y = y + 13
    for _, row in ipairs(v.moves) do
      box(10, y, 460, 22, row.best and C.off or C.card)
      if row.best then dot(20, y + 11, C.accent) end
      line(row.name, 30, y + 4, row.unusable and C.line or C.text, 12, 130)
      line(row.damaging and range(row.lo, row.hi) or "-", 160, y + 4, row.unusable and C.line or C.text, 12, 70, "right")
      line(row.acc .. "%", 236, y + 5, C.muted, 10, 36, "right")
      line(notes(row.notes), 282, y + 5, C.muted, 10, 182)
      y = y + 24
    end
    -- the foe
    y = y + 4
    line(v.foeName, 14, y, C.muted, 9, 200); line(T("OF_YOUR_HP"), 250, y, C.muted, 9, 220, "right")
    y = y + 13
    for index, row in ipairs(v.foe) do
      if index > 4 then break end
      box(10, y, 460, 20, C.card)
      line(row.name, 18, y + 4, C.text, 11, 200)
      line(row.status and "-" or range(row.lo, row.hi), 300, y + 4, row.hi >= 100 and C.bad or C.text, 11, 162, "right")
      y = y + 22
    end
    -- the team
    if #v.bench > 0 and y < Panel.H - 40 then
      y = y + 4
      line(T("TEAM"), 14, y, C.muted, 9, 200); line(T("GIVES_TAKES"), 250, y, C.muted, 9, 220, "right")
      y = y + 13
      for _, row in ipairs(v.bench) do
        if y > Panel.H - 22 then break end
        box(10, y, 460, 20, row.best and C.off or C.card)
        if row.best then dot(20, y + 10, C.accent) end
        line(row.name, 30, y + 4, C.text, 11, 150)
        line(T(row.faster and "FASTER" or "SLOWER") .. (row.survives and "" or (" · " .. T("RISKY"))), 184, y + 5,
          row.survives and C.muted or C.warn, 10, 130)
        line(F("GIVE_TAKE", row.give, row.take), 300, y + 4, C.text, 11, 162, "right")
        y = y + 22
      end
    end
    G.pop()
  end

  function Panel.pointer(action, x, y)
    if action ~= "down" then return end
    for i = #hits, 1, -1 do
      local at = hits[i]
      if x >= at.x and x < at.x + at.w and y >= at.y and y < at.y + at.h then at.action() return end
    end
  end

  -- The best play, small, on the battle screen: between the foe's box and the menu.
  function Panel.drawOverlay(v, viewport)
    local s = tonumber(viewport.scale) or 1
    local gx, gy = tonumber(viewport.gameX) or 0, tonumber(viewport.gameY) or 0
    local gw = tonumber(viewport.gameWidth) or 240 * s
    local lines = { { v.headline, C.text } }
    local shownMoves = 0
    for _, row in ipairs(v.moves) do
      if row.damaging and not row.unusable and not row.best and shownMoves < 2 then
        shownMoves = shownMoves + 1
        lines[#lines + 1] = { row.name .. " " .. range(row.lo, row.hi), C.muted }
      elseif row.best and row.damaging then
        lines[1][1] = v.headline .. " " .. range(row.lo, row.hi)
      end
    end
    if v.danger then lines[#lines + 1] = { T("DANGER_SHORT"), C.bad }
    elseif v.heal then lines[#lines + 1] = { T("HEAL_SHORT"), C.warn } end
    G.push("all")
    local f = font(max(10, 4.5 * s))
    G.setFont(f)
    local pad, lh = max(3, 2 * s), f:getHeight()
    local w = 0
    for _, l in ipairs(lines) do w = max(w, f:getWidth(l[1])) end
    w = min(w, gw * 0.55)
    local x, y = gx + 3 * s, gy + 50 * s
    color(C.bg, 0.82)
    G.rectangle("fill", x, y, w + pad * 2, lh * #lines + pad * 2, 3 * s, 3 * s)
    color(C.accent); G.rectangle("fill", x, y, max(1, s), lh * #lines + pad * 2)
    for i, l in ipairs(lines) do
      color(l[2])
      G.print(shorten(f, l[1], w), floor(x + pad), floor(y + pad + (i - 1) * lh))
    end
    G.pop()
  end
  return Panel
end
