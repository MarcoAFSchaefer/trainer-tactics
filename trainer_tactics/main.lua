-- Trainer Tactics: a battle brain that advises or plays.
--
-- brain.lua weighs every option of the turn with the game's own damage
-- formula. This file is the rest:
--   * the advisor: the best play and its numbers, drawn on the battle screen
--     while the player chooses, and in full in a Trainer Desk panel;
--   * auto battle: the same advice carried out through the battle menus (fight,
--     which move, switching, who comes in after a faint, text advanced). It
--     never answers questions that are the player's: learning a move, a
--     nickname, evolution;
--   * an API other mods can ask (Trainer Pilot does, for its own battles).
-- Items are not used: healing in battle is suggested, never done.
return function(mod)
  if mod.generation ~= nil and mod.generation ~= 3 then return end
  local floor, max, min = math.floor, math.max, math.min
  local function load_(name, ...)
    return assert(load(assert(mod:read(name)), "@trainer_tactics/" .. name))()(...)
  end

  mod.options:define({
    { key = "language", label = "LANGUAGE", type = "choice", default = "en",
      choices = { { "ENGLISH", "en" }, { "ESPANOL", "es" }, { "PORTUGUES", "pt" }, { "JAPANESE", "ja" } },
      description = "Language of the advisor and its panel." },
    { key = "auto", label = "AUTO BATTLE", type = "toggle", default = false,
      description = "Tactics plays your battles: moves and switches. The Tactics panel has the same switch." },
    { key = "advisor", label = "ADVICE ON THE BATTLE SCREEN", type = "toggle", default = true,
      description = "Shows the best play on the battle screen while you choose. The Tactics panel has the same switch." },
    { key = "foe_moves", label = "FOE MOVES", type = "choice", default = "all",
      choices = { { "KNOWN", "all" }, { "GUESSED", "guess" } },
      description = "KNOWN reads the foe's real moves. GUESSED assumes one plain attack of each of its types instead." },
  })
  local function option(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if ok then return value end
    return nil
  end
  local I18n = load_("i18n.lua", mod, function() return option("language") end)
  local T, F = I18n.T, I18n.F
  local Brain = load_("brain.lua", {})

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
  end

  -- A switch that the mod option sets and the panel may change; the panel's
  -- choice holds until the option itself is changed again.
  local settings, optionSeen = {}, {}
  local function setSwitch(key, on)
    settings[key] = on and true or false
    if mod.cache and mod.cache.write then
      mod.cache:write(key, (settings[key] and "1" or "0") .. "," .. (option(key) and "1" or "0"))
    end
  end
  for _, key in ipairs({ "auto", "advisor" }) do
    local saved = mod.cache and mod.cache.read and mod.cache:read(key)
    local on, from = tostring(saved or ""):match("^([01]),([01])$")
    local now = option(key) and "1" or "0"
    if on and from == now then settings[key] = on == "1" else settings[key] = option(key) == true end
    optionSeen[key] = option(key) == true
  end
  local function syncOptions()
    for _, key in ipairs({ "auto", "advisor" }) do
      local now = option(key) == true
      if now ~= optionSeen[key] then optionSeen[key] = now; setSwitch(key, now) end
    end
  end

  local game
  local function session()
    return (game and game.session) or nil
  end

  ---------------------------------------------------------------------------
  -- Advice, with names, for showing
  ---------------------------------------------------------------------------
  local function moveName(id)
    local P = req("src.core.game3.pokemon")
    local name = P and try(P.moveName, id)
    return type(name) == "string" and name or tostring(id)
  end
  local function monName(mon)
    if type(mon) ~= "table" then return "?" end
    if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
    local P = req("src.core.game3.pokemon")
    local species = P and try(P.speciesOf, mon)
    local name = P and (try(P.speciesName, species) or try(P.nameOf, species) or try(P.name, species))
    return type(name) == "string" and name or (type(mon.name) == "string" and mon.name or "?")
  end
  local function evaluate(extra)
    local s = session()
    local opts = { foeMoves = option("foe_moves"), party = s and s.party or {} }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local ok, advice = pcall(Brain.evaluate, opts)
    if not ok then
      if not settings.warned then settings.warned = true; mod.log:warn("advice failed: %s", tostring(advice)) end
      return nil
    end
    return advice
  end
  -- The same advice as plain rows for the panel and the overlay.
  local function view(advice)
    if not advice then return nil end
    local foeHp = max(1, tonumber(advice.foe.mon.hp) or 1)
    local myHp = max(1, tonumber(advice.me.mon.hp) or 1)
    local function pct(v, of) return min(999, floor(v / of * 100 + 0.5)) end
    local v = { moves = {}, foe = {}, bench = {}, faster = advice.faster, danger = advice.danger,
      me = monName(advice.me.mon), foeName = monName(advice.foe.mon) }
    for _, row in ipairs(advice.moves) do
      v.moves[#v.moves + 1] = { slot = row.slot, name = moveName(row.id), lo = pct(row.min, foeHp), hi = pct(row.max, foeHp),
        acc = row.acc, notes = row.notes, score = row.score, damaging = row.max > 0, unusable = row.unusable,
        best = advice.best and advice.best.kind == "move" and advice.best.slot == row.slot }
    end
    for _, row in ipairs(advice.threat.moves) do
      v.foe[#v.foe + 1] = { name = row.guessed and T("GUESSED_MOVE") or moveName(row.id), guessed = row.guessed, def = row.def,
        lo = pct(row.min, myHp), hi = pct(row.max, myHp), status = row.status }
    end
    table.sort(v.foe, function(a, b) return a.hi > b.hi end)
    for _, row in ipairs(advice.bench) do
      v.bench[#v.bench + 1] = { name = monName(row.mon), give = row.give, take = row.take, faster = row.faster,
        survives = row.survives, best = advice.best and advice.best.kind == "switch" and advice.best.mon == row.mon }
    end
    if advice.best and advice.best.kind == "switch" then
      v.headline = F("BEST_SWITCH", monName(advice.best.mon))
    elseif advice.best then
      v.headline = F("BEST_MOVE", moveName(advice.best.row.id))
    else
      v.headline = T("NO_MOVE")
    end
    -- healing is never done here, only pointed out
    local frac = myHp / max(1, tonumber(advice.me.mon.maxHp) or 1)
    v.heal = frac < 0.3 and not (advice.best and advice.best.row and advice.best.row.kill == "sure")
    return v
  end

  ---------------------------------------------------------------------------
  -- The battle, read and driven
  ---------------------------------------------------------------------------
  local api, intentId = nil, 0
  local run = { ticks = 0, lastTap = -100, lastSubmit = -100 }
  local function modules()
    local Battle = req("src.core.game3.battle")
    if not Battle then return nil end
    return { Battle = Battle, Core = req("src.core.game3.battle.init"), BattleAPI = req("src.battle.game3.BattleAPI"),
      Choice = req("src.ui.game3.choice"), Message = req("src.ui.game3.message"), PartyMenu = req("src.ui.game3.party_menu") }
  end
  local function battleState(h)
    if not (h and try(h.Battle.isActive) == true) then return nil end
    local st = try(h.Battle.getState)
    return type(st) == "table" and st or nil
  end
  local function tap(button, gap)
    if run.ticks - run.lastTap < (gap or 8) then return false end
    run.lastTap = run.ticks
    pcall(mod.input.tap, mod.input, game, button)
    return true
  end
  local function submit(snap, intent)
    intentId = intentId + 1
    intent.id, intent.revision = intentId, snap.revision
    local ok = api:submit(intent)
    run.fails = ok and 0 or (run.fails or 0) + 1
    return ok
  end
  -- Another mod is playing (Trainer Pilot): it asks for advice itself.
  local function pilotBusy()
    local other = mod.find and mod.find("trainer_pilot")
    local bot = other and other.exports and other.exports.bot
    return type(bot) == "table" and bot.running == true
  end
  local function chooser(st, snap)
    if st.double and snap and snap.active == 2 and type(st.battlers) == "table" then return st.battlers[2] or st.player end
    return st.player
  end

  local function autoTick()
    local h = modules()
    local st = battleState(h)
    if not st then run.battle = nil return end
    if st.safari or st.tutorial then return end
    api = api or (h.BattleAPI and try(h.BattleAPI.new, game))
    if not api then return end
    if run.battle ~= st then run.battle, run.plan, run.shiftFor, run.fails, run.noSwitch = st, nil, nil, 0, nil end
    local core = (h.Core and h.Core._phase) and h.Core or h.Battle
    local choiceOpen = h.Choice and try(h.Choice.isOpen) == true
    if core._phase == "shift_prompt" then
      -- "Will you switch your Pokémon?" before the trainer's next one
      if choiceOpen then
        local foe = type(st.foeParty) == "table" and st.foeParty[core._shiftEnemyIdx or 0] or nil
        if run.shiftFor ~= (foe or true) then
          run.shiftFor = foe or true
          local s = session()
          local ok, pick = pcall(Brain.shift, { foeMoves = option("foe_moves"), party = s and s.party or {}, foeMon = foe })
          run.plan = ok and pick and pick.mon or nil
        end
        tap(run.plan and "a" or "b", 15)
      elseif h.Message and try(h.Message.isWaiting) == true then
        tap("a", 6)
      end
      return
    end
    -- any other question is the player's: a new move, a nickname
    if choiceOpen then return end
    local menu = h.PartyMenu
    if menu and menu.open == true then
      local party = type(menu._party) == "table" and menu._party or {}
      local active = st.player and st.player.mon
      local target = run.plan
      if not target then
        if active and (tonumber(active.hp) or 0) > 0 then tap("b", 20) return end
        -- the one out fainted: the best of who is left
        local s = session()
        local ok, pick = pcall(Brain.bestSwitch, { foeMoves = option("foe_moves"), party = s and s.party or {} })
        target = ok and pick and pick.mon or nil
        run.plan = target
      end
      local choice
      for slot, mon in ipairs(party) do
        if mon == target and (tonumber(mon.hp) or 0) > 0 then choice = slot end
      end
      if not choice then
        for slot, mon in ipairs(party) do
          if (tonumber(mon.hp) or 0) > 0 and mon ~= active and not choice then choice = slot end
        end
      end
      if not choice then return end
      run.menuWasOpen = true
      if menu.cursor ~= choice then menu.cursor = choice end
      tap("a", 20)
      return
    end
    if run.menuWasOpen then run.menuWasOpen, run.plan = false, nil end
    local snap = try(api.snapshot, api)
    if type(snap) ~= "table" then return end
    if snap.prompt == "advance" then
      tap("a", 6)
    elseif snap.prompt == "locked" then
      tap("a", 20)
    elseif snap.prompt == "menu" or snap.prompt == "moves" or snap.prompt == "target" then
      if run.ticks - run.lastSubmit < 10 then return end
      run.lastSubmit = run.ticks
      if (run.fails or 0) > 30 then
        -- the menus are not answering: hand the battle back
        setSwitch("auto", false)
        mod.log:warn("auto battle stopped: the battle menu did not accept the choice")
        return
      end
      if snap.prompt == "target" then
        local target = 1
        for _, id in ipairs({ 1, 3 }) do
          local foe = id == 1 and st.enemy or (st.battlers and st.battlers[id])
          if foe and foe.mon and (tonumber(foe.mon.hp) or 0) > 0 and not (st.absent and st.absent[id]) then target = id break end
        end
        return submit(snap, { kind = "target", target = target })
      end
      local advice = evaluate({ battler = chooser(st, snap), noSwitch = run.noSwitch or st.double })
      local best = advice and advice.best
      if snap.prompt == "menu" then
        if best and best.kind == "switch" then
          run.plan = best.mon
          -- a switch the game refuses (trapped) is not asked for twice
          if not submit(snap, { kind = "menu", choice = "party" }) then run.plan, run.noSwitch = nil, true end
        else
          submit(snap, { kind = "menu", choice = "fight" })
        end
      else
        local slot = advice and advice.bestMove and advice.bestMove.slot
        if not slot then
          -- nothing scored: anything that still has PP keeps the battle going
          for _, row in ipairs(advice and advice.moves or {}) do
            if row.pp > 0 then slot = slot or row.slot end
          end
        end
        submit(snap, { kind = "move", slot = slot or 1 })
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Panel and overlay
  ---------------------------------------------------------------------------
  local shown, shownAt
  local function current(clock)
    clock = tonumber(clock) or 0
    if shown == nil or clock - (shownAt or -1) >= 0.3 or clock < (shownAt or 0) then
      shownAt = clock
      local h = modules()
      local st = battleState(h)
      shown = false
      if st and not st.safari then
        api = api or (h.BattleAPI and try(h.BattleAPI.new, game))
        local snap = api and try(api.snapshot, api)
        local v = view(evaluate({ battler = chooser(st, snap) }))
        if v then
          v.choosing = type(snap) == "table" and (snap.prompt == "menu" or snap.prompt == "moves")
          shown = v
        end
      end
    end
    return shown or nil
  end
  local Panel = load_("panel.lua", { T = T, F = F, font = I18n.font, view = current,
    get = function(key) return settings[key] end, set = setSwitch })

  mod.hooks:wrap("render.hud", function(nextHook, g, viewport)
    nextHook(g, viewport)
    if not (game and settings.advisor and not settings.auto and type(viewport) == "table") or pilotBusy() then return end
    local ok, err = pcall(function()
      local v = current(love.timer.getTime())
      if v and v.choosing then Panel.drawOverlay(v, viewport) end
    end)
    if not ok and not settings.warnedDraw then settings.warnedDraw = true; mod.log:warn("advisor: %s", tostring(err)) end
  end, 880)

  mod.hooks:wrap("input.step", function(nextHook, g, ...)
    if game then
      run.ticks = run.ticks + 1
      if settings.auto and not pilotBusy() then
        local ok, err = pcall(autoTick)
        if not ok then
          setSwitch("auto", false)
          mod.log:warn("auto battle stopped: %s", tostring(err))
        end
      end
    end
    return nextHook(g, ...)
  end, 880)

  -- Trainer Desk panel, and two actions for Trainer Controls, when they are there.
  local docked, controlsDone
  local function syncDock()
    local other = mod.find and mod.find("trainer_desk")
    local dock = other and other.exports and other.exports.dock
    dock = type(dock) == "table" and dock.api == 1 and dock.active() and dock or nil
    local language = tostring(option("language"))
    if docked and (docked.api ~= dock or docked.language ~= language) then
      pcall(docked.api.unregister, "trainer_tactics.tactics")
      docked = nil
    end
    if dock and not docked then
      dock.register({ id = "trainer_tactics.tactics", title = T("TITLE"), width = Panel.W, height = Panel.H, pixel = 1,
        responsive = true, interval = 0.25, side = "right", pointer = Panel.pointer,
        draw = function(clock, w, h)
          if dock.theme then Panel.theme(dock.theme().colors) end
          Panel.draw(clock, w, h)
        end })
      docked = { api = dock, language = language }
    end
    local controls = mod.find and mod.find("trainer_controls")
    local capi = controls and controls.exports and controls.exports.controls
    if type(capi) == "table" and capi.api == 1 and controlsDone ~= capi then
      controlsDone = capi
      capi.register({ id = "trainer_tactics.auto", label = function() return T("ACTION_AUTO") end,
        run = function() setSwitch("auto", not settings.auto) end })
      capi.register({ id = "trainer_tactics.advisor", label = function() return T("ACTION_ADVISOR") end,
        run = function() setSwitch("advisor", not settings.advisor) end })
    end
  end
  mod.hooks:wrap("core.update", function(nextHook, g, dt)
    if game then pcall(syncOptions); pcall(syncDock) end
    return nextHook(g, dt)
  end, 880)
  mod.hooks:wrap("core.quit_to_launcher", function(nextHook)
    if docked then pcall(docked.api.unregister, "trainer_tactics.tactics") end
    game, api, docked, shown = nil, nil, nil, nil
    return nextHook()
  end, 880)
  mod.events:on("game.ready", function(payload)
    game, api, shown = payload and payload.game, nil, nil
  end)

  ---------------------------------------------------------------------------
  -- For other mods.
  --   bestMove{ battler, ban = function(mon, moveId), fast = true } -> slot or nil
  --   shift{ foeMon, allowed = function(partyIndex) } -> mon or nil
  --   bestSwitch{ allowed } -> mon or nil
  --   evaluate{ ... } -> the whole advice
  ---------------------------------------------------------------------------
  local function withParty(opts)
    local s = session()
    local full = { foeMoves = option("foe_moves"), party = s and s.party or {} }
    for k, v in pairs(type(opts) == "table" and opts or {}) do full[k] = v end
    return full
  end
  mod.exports = mod.exports or {}
  mod.exports.tactics = {
    api = 1,
    evaluate = function(opts) local ok, a = pcall(Brain.evaluate, withParty(opts)); return ok and a or nil end,
    bestMove = function(opts) local ok, slot = pcall(Brain.bestMove, withParty(opts)); return ok and slot or nil end,
    shift = function(opts) local ok, row = pcall(Brain.shift, withParty(opts)); return ok and row and row.mon or nil end,
    bestSwitch = function(opts) local ok, row = pcall(Brain.bestSwitch, withParty(opts)); return ok and row and row.mon or nil end,
    auto = function() return settings.auto end,
  }
  mod.exports.debug = { brain = Brain, panel = Panel, settings = settings, set = setSwitch, view = function() shown = nil; return current(0) end }
end
