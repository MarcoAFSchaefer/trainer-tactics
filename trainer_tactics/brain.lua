-- brain.lua: what to do this turn.
--
-- Given the battle as it stands, every option is given a score:
--   * a damaging move: the share of the foe's remaining HP it is expected to
--     take (the game's own damage formula, lowest and highest roll, no
--     critical hit, times its accuracy). A certain knock-out is worth more than
--     anything else; among those, the most accurate wins.
--   * a status, set-up or healing move: a fixed worth for what it does, when
--     the situation makes it pay (the foe has no status yet, there is time to
--     set up, HP is low and the heal outpaces the foe).
--   * switching: when the one out is in danger or cannot hurt, each team mate
--     is weighed by what it would give and take; a clearly better one that
--     survives coming in outranks a plain attack.
-- The highest score is the advice. Nothing here touches the battle.
return function(env)
  local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
  local Brain = {}

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
  end
  local E = {} -- effect ids, filled once
  local function modules()
    local M = {
      Damage = req("src.core.game3.battle.damage"), Moves = req("src.core.game3.battle.moves"),
      State = req("src.core.game3.battle.state"), Engine = req("src.core.game3.battle.engine"),
      Types = req("src.core.game3.battle.types"), Pokemon = req("src.core.game3.pokemon"),
      Battle = req("src.core.game3.battle"),
    }
    local ids = req("src.core.game3.battle.effect_ids")
    if ids and not E.loaded then
      for k, v in pairs(ids) do if type(v) == "number" then E[k] = v end end
      E.loaded = true
    end
    return M.Damage and M.Moves and M or nil
  end

  local TWO_TURN = { "RAZOR_WIND", "SKY_ATTACK", "SKULL_BASH", "SOLAR_BEAM" }
  local SETUP = { ATTACK_UP = { "attack", 1 }, ATTACK_UP_2 = { "attack", 2 }, SPECIAL_ATTACK_UP = { "spAtk", 1 },
    SPECIAL_ATTACK_UP_2 = { "spAtk", 2 }, DRAGON_DANCE = { "attack", 1 }, BULK_UP = { "attack", 1 }, CALM_MIND = { "spAtk", 1 } }
  local HEALS = { "RESTORE_HP", "SOFTBOILED", "MORNING_SUN", "SYNTHESIS", "MOONLIGHT" }
  local ABSORB = { LEVITATE = "GROUND", VOLT_ABSORB = "ELECTRIC", WATER_ABSORB = "WATER", FLASH_FIRE = "FIRE" }
  local function is(effect, name) return effect ~= nil and E[name] ~= nil and effect == E[name] end
  local function anyOf(effect, names)
    for _, name in ipairs(names) do if is(effect, name) then return true end end
    return false
  end

  local function hpOf(b) return max(0, tonumber(b.mon and b.mon.hp) or 0) end
  local function maxHpOf(b) return max(1, tonumber(b.mon and b.mon.maxHp) or 1) end
  local function statusOf(b)
    local s = b and (b.status or (b.mon and b.mon.status))
    if s == 0 or s == "" then return nil end
    return s
  end
  local function abilityOf(M, ctx, b)
    local name = ctx.adapter and try(ctx.adapter.abilityOf, ctx.adapter, b)
    if type(name) == "string" then return name:upper():gsub("%s+", "_") end
    return nil
  end
  local function typeName(M, id)
    local name = M.Types and try(M.Types.name, id)
    return type(name) == "string" and name:upper() or nil
  end

  -- A mon's moves: { slot, id, def, pp }.
  local function movesOf(M, mon)
    local out = {}
    for slot = 1, 4 do
      local id = type(mon.moves) == "table" and mon.moves[slot]
      if type(id) == "table" then id = id.id or id.move end
      if id and id ~= 0 and id ~= "" then
        local def = try(M.Moves.get, id)
        if type(def) == "table" then
          out[#out + 1] = { slot = slot, id = id, def = def, pp = type(mon.pp) == "table" and tonumber(mon.pp[slot]) or 0 }
        end
      end
    end
    return out
  end
  Brain.movesOf = function(mon) local M = modules(); return M and movesOf(M, mon) or {} end

  -- Lowest and highest damage of a move, with no critical hit; plus the
  -- effectiveness (0, 0.25 ... 4). Abilities that soak a type up make it 0.
  local function damage(M, ctx, att, def, move)
    local opts = { forceCrit = false, weather = ctx.st and ctx.st.weather, adapter = ctx.adapter, st = ctx.st }
    opts.forceRoll = 85
    local lo, info = try(M.Damage.calc, att, def, move, opts)
    opts.forceRoll = 100
    local hi = try(M.Damage.calc, att, def, move, opts)
    lo, hi = tonumber(lo) or 0, tonumber(hi) or 0
    info = type(info) == "table" and info or {}
    local eff = tonumber(info.effectiveness) or 1
    local record = type(move) == "table" and move or try(M.Moves.get, move) or {}
    local moveType = typeName(M, info.moveType or record.type)
    local ability = abilityOf(M, ctx, def)
    if ability and moveType and (ABSORB[ability] == moveType or (ability == "WONDER_GUARD" and eff <= 1 and hi > 0)) then
      return 0, 0, 0
    end
    local effect = tonumber(record.effect)
    if is(effect, "MULTI_HIT") then lo, hi = lo * 2, hi * 5
    elseif is(effect, "DOUBLE_HIT") or is(effect, "TWINEEDLE") then lo, hi = lo * 2, hi * 2
    elseif is(effect, "TRIPLE_KICK") then lo, hi = lo * 3, hi * 6 end
    return lo, hi, eff
  end

  local function speedOf(M, ctx, b)
    local v = M.Engine and try(M.Engine.speedOf, b, ctx.st, ctx.adapter)
    return tonumber(v) or tonumber(b.mon and (b.mon.speed or b.mon.spe)) or 0
  end
  local function priorityOf(def) return tonumber(def.priority) or 0 end
  local function accuracyOf(def)
    local acc = tonumber(def.accuracy) or 100
    return (acc <= 0 or acc > 100) and 100 or acc
  end

  -- What the foe may use: its real moves, or one plain attack per type of its
  -- own when the player prefers not to look.
  local function foeMoves(M, ctx, foe)
    if ctx.opts.foeMoves ~= "guess" then
      local list = {}
      for _, mv in ipairs(movesOf(M, foe.mon)) do
        if mv.pp > 0 or type(foe.mon.pp) ~= "table" then list[#list + 1] = mv end
      end
      return list
    end
    local list = {}
    for _, t in ipairs({ foe.type1, foe.type2 }) do
      if t then list[#list + 1] = { id = 0, guessed = true, def = { effect = 0, power = 80, type = t, accuracy = 100, id = "GUESS" } } end
    end
    return list
  end
  -- The worst the foe can do to a battler: { max, avg, move }.
  local function threat(M, ctx, foe, target)
    local out = { max = 0, avg = 0, moves = {} }
    for _, mv in ipairs(foeMoves(M, ctx, foe)) do
      if (tonumber(mv.def.power) or 0) > 0 then
        local lo, hi, eff = damage(M, ctx, foe, target, mv.guessed and mv.def or mv.id)
        local avg = (lo + hi) / 2 * accuracyOf(mv.def) / 100
        out.moves[#out.moves + 1] = { id = mv.id, def = mv.def, min = lo, max = hi, eff = eff, guessed = mv.guessed }
        if hi > out.max then out.max, out.move = hi, mv end
        if avg > out.avg then out.avg = avg end
      else
        out.moves[#out.moves + 1] = { id = mv.id, def = mv.def, min = 0, max = 0, eff = 1, status = true }
      end
    end
    return out
  end

  local function turns(hp, perTurn)
    if perTurn <= 0 then return 99 end
    return ceil(hp / perTurn)
  end

  -- Scores every move of the one out. Returns the rows (all four slots that
  -- hold a move) and the best one.
  local function scoreMoves(M, ctx, me, foe, foeThreat, meFaster)
    local rows, best = {}, nil
    local foeHp, myHp = max(1, hpOf(foe)), hpOf(me)
    local myFrac = myHp / maxHpOf(me)
    local danger = foeThreat.max >= myHp            -- the foe may knock the one out down this turn
    local foeTurns = turns(myHp, foeThreat.avg)     -- turns the one out has left
    local list = movesOf(M, me.mon)
    -- the plain attacking pace, for moves that only pay over several turns
    local pace = 0
    for _, mv in ipairs(list) do
      if (tonumber(mv.def.power) or 0) > 0 and mv.pp > 0 then
        local lo, hi = damage(M, ctx, me, foe, mv.id)
        pace = max(pace, (lo + hi) / 2 * accuracyOf(mv.def) / 100)
      end
    end
    local myTurns = turns(foeHp, pace)
    local hasPhysical, hasSpecial = false, false
    for _, mv in ipairs(list) do
      if (tonumber(mv.def.power) or 0) > 0 and M.Types and M.Types.isPhysical then
        if try(M.Types.isPhysical, mv.def.type) then hasPhysical = true else hasSpecial = true end
      end
    end
    local foeStatus, myStatus = statusOf(foe), statusOf(me)

    for _, mv in ipairs(list) do
      local def = mv.def
      local effect, power, acc = tonumber(def.effect), tonumber(def.power) or 0, accuracyOf(def)
      local row = { slot = mv.slot, id = mv.id, def = def, pp = mv.pp, acc = acc, notes = {}, score = 0, min = 0, max = 0, eff = 1 }
      local function note(code) row.notes[#row.notes + 1] = code end
      local first = priorityOf(def) > 0 or (priorityOf(def) == 0 and meFaster)
      if mv.pp <= 0 then
        note("NO_PP"); row.unusable = true
      elseif ctx.opts.ban and ctx.opts.ban(me.mon, mv.id) then
        note("BANNED"); row.unusable = true; row.banned = true
      elseif power > 0 or is(effect, "OHKO") then
        local lo, hi, eff = damage(M, ctx, me, foe, mv.id)
        row.min, row.max, row.eff = lo, hi, eff
        if is(effect, "OHKO") then
          row.score = eff == 0 and 0 or 30
          note("OHKO")
        elseif hi <= 0 then
          note(eff == 0 and "IMMUNE" or "FAILS")
        else
          local expected = (lo + hi) / 2 * acc / 100
          local frac = min(1, expected / foeHp)
          if lo >= foeHp then
            row.kill = "sure"; note("KO")
            row.score = 200 + acc + (first and 20 or 0) + min(5, mv.pp)
          elseif hi >= foeHp then
            row.kill = "maybe"; note("KO_MAYBE")
            row.score = 100 * frac + 40 * acc / 100
          else
            row.score = 100 * frac
          end
          local sure = row.kill == "sure"
          if anyOf(effect, TWO_TURN) and not (is(effect, "SOLAR_BEAM") and ctx.st and tostring(ctx.st.weather):upper():find("SUN")) then
            note("CHARGE"); row.score = row.score * 0.5
          elseif is(effect, "SEMI_INVULNERABLE") then
            note("CHARGE"); row.score = row.score * 0.7
          elseif is(effect, "RECHARGE") and not sure then
            note("RECHARGE"); row.score = row.score * 0.6
          elseif is(effect, "EXPLOSION") then
            note("FAINTS")
            row.score = (sure and myFrac < 0.3) and 150 or 0.5
            row.lastResort = row.score < 1
          elseif is(effect, "FOCUS_PUNCH") and foeStatus ~= "SLP" then
            row.score = row.score * 0.3
          elseif is(effect, "DREAM_EATER") and foeStatus ~= "SLP" then
            row.score = 0; note("FAILS")
          elseif is(effect, "SNORE") and myStatus ~= "SLP" then
            row.score = 0; note("FAILS")
          elseif is(effect, "FUTURE_SIGHT") or is(effect, "BIDE") then
            row.score = row.score * 0.5
          elseif is(effect, "RECOIL") or is(effect, "DOUBLE_EDGE") then
            note("RECOIL"); row.score = row.score - 3
          end
          -- any attack that lands is worth more than a move that does nothing now
          if row.score > 0 and not row.lastResort then row.score = max(row.score, 6) end
          if acc < 100 then note("MISS") end
          if first and sure then note("FIRST") end
          -- hit first and hard enough to be knocked out before attacking
          if danger and not first and not sure then row.score = row.score * 0.6 end
        end
      else
        -- no damage: worth something only when the situation calls for it
        local worth = 4
        local quick = ctx.opts.fast and pace > 0
        if is(effect, "SLEEP") then worth = foeStatus and 0 or 85; note("STATUS")
        elseif is(effect, "PARALYZE") then
          worth = foeStatus and 0 or (meFaster and 30 or 60); note("STATUS")
          local _, _, eff = damage(M, ctx, me, foe, { effect = 0, power = 40, type = def.type, accuracy = 100, id = "PROBE" })
          if typeName(M, def.type) == "ELECTRIC" and eff == 0 then worth = 0 end
        elseif is(effect, "TOXIC") or is(effect, "POISON") then
          local t1, t2 = typeName(M, foe.type1), typeName(M, foe.type2)
          local immune = t1 == "POISON" or t2 == "POISON" or t1 == "STEEL" or t2 == "STEEL"
          worth = (foeStatus or immune) and 0 or (myTurns >= 3 and (is(effect, "TOXIC") and 40 or 25) or 8); note("STATUS")
        elseif is(effect, "WILL_O_WISP") then
          local fire = typeName(M, foe.type1) == "FIRE" or typeName(M, foe.type2) == "FIRE"
          local physical = (tonumber(foe.mon.attack) or 0) >= (tonumber(foe.mon.spAtk) or 0)
          worth = (foeStatus or fire) and 0 or (physical and 45 or 15); note("STATUS")
        elseif is(effect, "CONFUSE") then worth = 30; note("STATUS")
        elseif is(effect, "LEECH_SEED") then
          local grass = typeName(M, foe.type1) == "GRASS" or typeName(M, foe.type2) == "GRASS"
          worth = (grass or foe.expSeeded or foe.leechSeed) and 0 or 30; note("STATUS")
        elseif is(effect, "YAWN") then worth = foeStatus and 0 or 30; note("STATUS")
        elseif is(effect, "SPEED_UP_2") then
          worth = (not meFaster and foeTurns >= 3 and (me.stages and me.stages.speed or 0) < 2) and 40 or 4; note("SETUP")
        elseif is(effect, "DEFENSE_UP_2") or is(effect, "SPECIAL_DEFENSE_UP_2") then worth = foeTurns >= 3 and 15 or 4; note("SETUP")
        elseif anyOf(effect, HEALS) then
          note("HEAL")
          local heal = maxHpOf(me) / 2
          if myFrac < 0.5 and foeThreat.avg < heal * 0.9 and foeThreat.max < myHp + heal then worth = myFrac < 0.35 and 110 or 90 else worth = 3 end
          quick = false
        elseif is(effect, "REST") then
          note("HEAL")
          worth = (myFrac < 0.35 and turns(maxHpOf(me), foeThreat.avg) >= 4) and 80 or 3
          quick = false
        elseif is(effect, "SLEEP_TALK") then worth = myStatus == "SLP" and 60 or 0
        else
          for name, what in pairs(SETUP) do
            if is(effect, name) then
              note("SETUP")
              local stage = me.stages and me.stages[what[1]] or 0
              local useful = (what[1] == "attack" and hasPhysical) or (what[1] == "spAtk" and hasSpecial)
              worth = (useful and stage < 2 and foeTurns >= 3 and myTurns >= 2) and (what[2] == 2 and 60 or 50) or 5
            end
          end
        end
        if worth > 4 and not anyOf(effect, HEALS) and not is(effect, "REST") then
          worth = worth * acc / 100
          -- no time for it when the next hit may be the last
          if danger and not meFaster then worth = worth * 0.2 end
        end
        if quick then worth = min(worth, 2) end
        row.score = worth
      end
      rows[#rows + 1] = row
      if not row.unusable and (not best or row.score > best.score) then best = row end
    end
    return rows, best, pace
  end

  -- The battle seen from the one out. opts: foeMoves ("all" | "guess"),
  -- ban(mon, moveId), allowed(partyIndex), fast (no time for status moves),
  -- battler (in doubles, which of the two is choosing).
  function Brain.evaluate(opts)
    local M = modules()
    if not M then return nil end
    local st = M.Battle and try(M.Battle.getState)
    if type(st) ~= "table" then return nil end
    local me, foe = opts.battler or st.player, st.enemy
    -- the trainer's next one, before it is out
    if opts.foeMon and M.State then foe = try(M.State.makeBattler, opts.foeMon, "enemy", { id = 1 }) or foe end
    if not (me and foe and me.mon and foe.mon) then return nil end
    local ctx = { st = st, adapter = M.Battle._adapter, opts = opts }
    local out = { me = me, foe = foe, wild = st.wild == true, double = st.double == true }
    local mySpeed, foeSpeed = speedOf(M, ctx, me), speedOf(M, ctx, foe)
    out.faster = mySpeed > foeSpeed
    out.mySpeed, out.foeSpeed = mySpeed, foeSpeed
    out.threat = threat(M, ctx, foe, me)
    out.moves, out.bestMove, out.pace = scoreMoves(M, ctx, me, foe, out.threat, out.faster)
    out.danger = out.threat.max >= hpOf(me)

    -- team mates: what each would give and take
    out.bench = {}
    local party = type(opts.party) == "table" and opts.party or {}
    local foeHp = max(1, hpOf(foe))
    local function inBattle(mon)
      if mon == me.mon or (st.player and mon == st.player.mon) then return true end
      for _, b in pairs(type(st.battlers) == "table" and st.battlers or {}) do
        if type(b) == "table" and b.side == "player" and b.mon == mon then return true end
      end
      return false
    end
    for index, mon in ipairs(party) do
      local alive = type(mon) == "table" and (tonumber(mon.hp) or 0) > 0
      local egg = M.Pokemon and try(M.Pokemon.isEgg, mon) == true
      if alive and not egg and not inBattle(mon) and (not opts.allowed or opts.allowed(index)) then
        local b = M.State and try(M.State.makeBattler, mon, "player", { id = 0 })
        if type(b) == "table" then
          local give = 0
          for _, mv in ipairs(movesOf(M, mon)) do
            if (tonumber(mv.def.power) or 0) > 0 and mv.pp > 0 and not (opts.ban and opts.ban(mon, mv.id)) then
              local lo, hi = damage(M, ctx, b, foe, mv.id)
              give = max(give, (lo + hi) / 2 * accuracyOf(mv.def) / 100)
            end
          end
          local take = threat(M, ctx, foe, b)
          local hp = max(1, tonumber(mon.hp) or 1)
          local faster = speedOf(M, ctx, b) > foeSpeed
          local row = { index = index, mon = mon, give = min(100, floor(give / foeHp * 100)), take = floor(take.max / hp * 100), faster = faster }
          -- it is hit once coming in, and once more if it is slower
          row.survives = row.take * (faster and 1 or 2) < 100
          row.matchup = row.give - row.take * 0.6
          out.bench[#out.bench + 1] = row
        end
      end
    end
    table.sort(out.bench, function(a, b) return a.matchup > b.matchup end)

    -- stay or go
    local myGive = min(100, out.pace / foeHp * 100)
    local sureKill = out.bestMove and out.bestMove.kill == "sure"
    if out.danger and not out.faster and not (sureKill and priorityOf(out.bestMove.def) > 0) then myGive = myGive * 0.3 end
    local myTake = out.threat.max / max(1, hpOf(me)) * 100
    out.matchup = myGive - min(100, myTake) * 0.6
    local stuck = not out.bestMove or out.bestMove.score < 25
    local pick = out.bench[1]
    -- held in place (binding moves, Mean Look, Arena Trap...): the game says no
    out.trapped = M.Engine ~= nil and try(M.Engine.canSwitch, st, ctx.adapter, me) == false
    if pick and not opts.noSwitch and not out.trapped and (stuck or (out.danger and not (sureKill and (out.faster or priorityOf(out.bestMove.def) > 0)))) then
      local better
      for _, row in ipairs(out.bench) do
        if row.survives and row.matchup > out.matchup + 30 then better = row break end
      end
      if better then
        better.score = 100 + min(60, better.matchup - out.matchup)
        if not out.bestMove or better.score > out.bestMove.score then out.switch = better end
      end
    end
    if out.switch then out.best = { kind = "switch", index = out.switch.index, mon = out.switch.mon, row = out.switch }
    elseif out.bestMove then out.best = { kind = "move", slot = out.bestMove.slot, row = out.bestMove } end
    return out
  end

  -- Whether to change before the trainer's next one (foeMon) comes out:
  -- the team mate, or nil to stay.
  function Brain.shift(opts)
    local advice = Brain.evaluate(opts)
    if not advice then return nil end
    for _, row in ipairs(advice.bench) do
      if row.survives and row.matchup > advice.matchup + 30 then return row, advice end
    end
    return nil, advice
  end

  -- Who to send when the one out has fainted or the trainer brings its next
  -- one (foeMon): the best matchup, preferring one that survives coming in.
  function Brain.bestSwitch(opts)
    local advice = Brain.evaluate(opts)
    if not advice then return nil end
    local pick
    for _, row in ipairs(advice.bench) do
      if row.survives then pick = row break end
    end
    pick = pick or advice.bench[1]
    return pick, advice
  end

  -- The slot to use, or nil when nothing can be used.
  function Brain.bestMove(opts)
    local advice = Brain.evaluate(opts)
    local row = advice and advice.bestMove
    -- nothing worth anything (or the numbers could not be had): no opinion
    if not row or row.score <= 0 then return nil, advice end
    return row.slot, advice
  end
  return Brain
end
