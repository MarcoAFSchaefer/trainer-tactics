-- i18n.lua: the mod's text in four languages, and fonts that can draw it.
--
-- Each language is a file in lang/ (en.lua, es.lua, pt.lua, ja.lua) returning
-- a table of key -> text. English is the reference: a key another language
-- does not have falls back to English, and a key English does not have shows
-- itself, so a missing entry is visible instead of breaking the panel.
--
-- Values may be strings or tables (lists of names, for example). Strings with
-- %-directives are used with string.format by the caller.
--
-- Fonts: LÖVE's default face draws Latin text only. Every font made here gets
-- fallbacks for the rest: the Japanese face bundled in fonts/ (Noto Sans JP,
-- cut down to kana and the characters these mods use; SIL Open Font License,
-- see fonts/OFL.txt), then the game's own wide pixel face for anything else,
-- when the game has it.
--
-- This file is the same in Trainer Desk, Trainer Lens and Trainer Pilot; each
-- mod keeps its own copy so that none depends on another.
return function(mod, getLanguage)
  local I = { LANGUAGES = { "en", "es", "pt", "ja" } }
  local known = { en = true, es = true, pt = true, ja = true }
  local catalogs = {}

  local function catalog(code)
    if catalogs[code] == nil then
      catalogs[code] = false
      local source = mod.read and mod:read("lang/" .. code .. ".lua")
      if source then
        local chunk = load(source, "@" .. tostring(mod.id or "mod") .. "/lang/" .. code .. ".lua")
        local ok, t = pcall(chunk or error)
        if ok and type(t) == "table" then catalogs[code] = t end
      end
    end
    return catalogs[code] or nil
  end

  -- The language chosen now; anything unknown counts as English.
  function I.language()
    local code = getLanguage and getLanguage() or "en"
    return known[code] and code or "en"
  end

  -- T(key): the text for key in the chosen language.
  function I.T(key)
    local here = catalog(I.language())
    local value = here and here[key]
    if value == nil then
      local en = catalog("en")
      value = en and en[key]
    end
    if value == nil then return key end
    return value
  end

  -- F(key, ...): T(key) formatted; a broken translation falls back to English.
  function I.F(key, ...)
    local text = I.T(key)
    local ok, out = pcall(string.format, tostring(text), ...)
    if ok then return out end
    local en = catalog("en")
    ok, out = pcall(string.format, tostring(en and en[key] or key), ...)
    return ok and out or tostring(text)
  end

  -- Every key of a language, for checks.
  function I.catalog(code) return catalog(code) end

  ---------------------------------------------------------------------------
  -- Fonts
  ---------------------------------------------------------------------------
  local G = love.graphics
  local jaData, jaFonts = nil, {}
  local function japanese(size)
    if jaFonts[size] == nil then
      jaFonts[size] = false
      if jaData == nil then
        jaData = false
        local bytes = mod.read and mod:read("fonts/NotoSansJP-subset.ttf")
        if bytes then
          local ok, data = pcall(love.filesystem.newFileData, bytes, "NotoSansJP-subset.ttf")
          if ok then jaData = data end
        end
      end
      if jaData then
        local ok, f = pcall(G.newFont, jaData, size)
        if ok then jaFonts[size] = f end
      end
    end
    return jaFonts[size] or nil
  end

  -- The game's own wide face, for anything ours lacks (kanji in game names, say).
  local wideMissing, wide = false, {}
  local function gameFace(size)
    if wideMissing then return nil end
    if wide[size] == nil then
      local ok, f = pcall(G.newFont, "assets/fonts/plainpixel/PlainPixel-Regular.ttf", size)
      if not ok then wideMissing = true return nil end
      wide[size] = f
    end
    return wide[size]
  end

  local cache = {}
  -- font(size): LÖVE's default face at that size, able to draw Japanese too.
  function I.font(size)
    local f = cache[size]
    if f then return f end
    f = G.newFont(size)
    local chain = {}
    chain[#chain + 1] = japanese(size)
    chain[#chain + 1] = gameFace(size)
    if #chain > 0 and f.setFallbacks then pcall(f.setFallbacks, f, unpack(chain)) end
    cache[size] = f
    return f
  end

  return I
end
