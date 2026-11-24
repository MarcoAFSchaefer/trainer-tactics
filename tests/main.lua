-- Checks for Trainer Tactics: a small stand-in battle (types, damage, speed)
-- for the brain, and stand-in battle menus for the auto battle.
local OUT = os.getenv("TEST_OUT") or "/tmp/tactics_out"
local DIR = os.getenv("TACTICS_MOD")
local G = love.graphics
local function reader(dir) return function(name) local f = io.open(dir .. "/" .. name, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end end
function love.errorhandler(msg) print("HARNESS ERROR", msg, debug.traceback()); return function() return 1 end end
local function check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end; print("ok  " .. msg) end

function love.load()
  os.execute("mkdir -p " .. OUT)
  local CHART = { WATER = { FIRE = 2, WATER = 0.5, GRASS = 0.5, GROUND = 2 }, FIRE = { GRASS = 2, WATER = 0.5, FIRE = 0.5 },
    GRASS = { WATER = 2, FIRE = 0.5, GRASS = 0.5, GROUND = 2 }, ELECTRIC = { WATER = 2, GROUND = 0, GRASS = 0.5 },
    GROUND = { FIRE = 2, ELECTRIC = 2, GRASS = 0.5 }, NORMAL = {} }
  local EFFECT = { SLEEP = 1, EXPLOSION = 7, ATTACK_UP_2 = 50, RESTORE_HP = 32, RECHARGE = 80, PARALYZE = 67, TOXIC = 33, OHKO = 38 }
  local MOVES = {
    [1] = { name = "Tackle", power = 40, type = "NORMAL", accuracy = 100, effect = 0 },
    [2] = { name = "Surf", power = 95, type = "WATER", accuracy = 100, effect = 0 },
    [3] = { name = "Hydro Pump", power = 120, type = "WATER", accuracy = 80, effect = 0 },
    [4] = { name = "Earthquake", power = 100, type = "GROUND", accuracy = 100, effect = 0 },
    [5] = { name = "Sleep Powder", power = 0, type = "GRASS", accuracy = 75, effect = 1 },
    [6] = { name = "Razor Leaf", power = 55, type = "GRASS", accuracy = 95, effect = 0 },
    [7] = { name = "Flamethrower", power = 95, type = "FIRE", accuracy = 100, effect = 0 },
    [8] = { name = "Recover", power = 0, type = "NORMAL", accuracy = 100, effect = 32 },
    [9] = { name = "Thunderbolt", power = 95, type = "ELECTRIC", accuracy = 100, effect = 0 },
    [10] = { name = "Swords Dance", power = 0, type = "NORMAL", accuracy = 0, effect = 50 },
    [11] = { name = "Quick Attack", power = 40, type = "NORMAL", accuracy = 100, effect = 0, priority = 1 },
  }
  local function eff(t, b)
    local m = 1
    for _, d in ipairs({ b.type1, b.type2 }) do m = m * ((CHART[t] or {})[d] or 1) end
    return m
  end
  package.preload["src.core.game3.battle.effect_ids"] = function() return EFFECT end
  package.preload["src.core.game3.battle.moves"] = function() return { get = function(id) return MOVES[id] end } end
  package.preload["src.core.game3.battle.types"] = function() return { name = function(id) return id end,
    isPhysical = function(t) return t == "NORMAL" or t == "GROUND" end } end
  package.preload["src.core.game3.battle.damage"] = function() return { calc = function(att, def, move, opts)
    local m = type(move) == "table" and move or MOVES[move]
    local e = eff(m.type, def)
    local stage = 1 + 0.5 * (att.stages and att.stages.attack or 0)
    return math.floor(m.power * (att.mon.atk or 10) / 10 * e * stage * opts.forceRoll / 100), { effectiveness = e, moveType = m.type }
  end } end
  package.preload["src.core.game3.battle.state"] = function() return { makeBattler = function(mon, side)
    return { mon = mon, side = side, type1 = mon.t1, type2 = mon.t2, stages = { attack = 0, spAtk = 0, speed = 0 }, status = mon.status } end } end
  package.preload["src.core.game3.battle.engine"] = function() return { speedOf = function(b) return b.mon.speed end } end
  package.preload["src.core.game3.pokemon"] = function() return { moveName = function(id) return MOVES[id] and MOVES[id].name end,
    speciesOf = function(mon) return mon.species end, isEgg = function() return false end } end
  local st, active = nil, false
  local Battle = { isActive = function() return active end, getState = function() return st end,
    _adapter = { abilityOf = function(_, b) return b.mon.ability end } }
  package.preload["src.core.game3.battle"] = function() return Battle end
  package.preload["src.core.game3.battle.init"] = function() return Battle end
  local snap, sent, accept = nil, {}, true
  package.preload["src.battle.game3.BattleAPI"] = function() return { new = function() return {
    snapshot = function() return snap end,
    submit = function(_, intent) sent[#sent + 1] = intent; return accept or nil end } end } end
  local Choice, Message, PartyMenu = { open = false }, { waiting = false }, { open = false }
  Choice.isOpen = function() return Choice.open end
  Message.isWaiting = function() return Message.waiting end
  package.preload["src.ui.game3.choice"] = function() return Choice end
  package.preload["src.ui.game3.message"] = function() return Message end
  package.preload["src.ui.game3.party_menu"] = function() return PartyMenu end

  local function mon(name, t1, t2, hp, speed, atk, moves, extra)
    local m = { nickname = name, species = name, t1 = t1, t2 = t2, hp = hp, maxHp = hp, speed = speed, atk = atk, attack = atk, spAtk = atk,
      moves = moves, pp = { 10, 10, 10, 10 } }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
  end
  local State = require("src.core.game3.battle.state")
  local session = { party = {} }
  local function battle(mine, foe, bench)
    session.party = { mine }
    for _, b in ipairs(bench or {}) do session.party[#session.party + 1] = b end
    st = { player = State.makeBattler(mine, "player"), enemy = State.makeBattler(foe, "enemy"), wild = false }
    active = true
  end

  local panels, cache, warns, taps = {}, {}, {}, {}
  local pilot = { exports = { bot = { running = false } } }
  local dock = { exports = { dock = { api = 1, active = function() return true end,
    register = function(def) panels[def.id] = def end, unregister = function(id) panels[id] = nil end, theme = function() return { colors = {} } end } } }
  local registered = {}
  local controls = { exports = { controls = { api = 1, register = function(def) registered[def.id] = def; return true end } } }
  local read = reader(DIR)
  local mod = { id = "trainer_tactics", generation = 3, options_ = {}, hooks_ = {}, events_ = {}, exports = {} }
  mod.read = function(_, n) return read(n) end
  mod.options = { define = function(_, s) for _, row in ipairs(s) do if mod.options_[row.key] == nil then mod.options_[row.key] = row.default end end
    if os.getenv("TEST_LANG") then mod.options_.language = os.getenv("TEST_LANG") end end,
    get = function(_, k) return mod.options_[k] end }
  mod.hooks = { wrap = function(_, n, f) mod.hooks_[n] = f end }
  mod.events = { on = function(_, n, f) mod.events_[n] = f end }
  mod.log = { warn = function(_, f, ...) warns[#warns + 1] = f:format(...); print("WARN", warns[#warns]) end }
  mod.cache = { read = function(_, k) return cache[k] end, write = function(_, k, v) cache[k] = v; return true end }
  mod.input = { tap = function(_, _, btn) taps[#taps + 1] = btn end }
  mod.find = function(id) return ({ trainer_desk = dock, trainer_controls = controls, trainer_pilot = pilot })[id] end
  assert(loadstring(read("main.lua"), "@trainer_tactics/main.lua"))()(mod)
  local game = { session = session }
  mod.events_["game.ready"]({ game = game })
  local api = mod.exports.tactics
  local D = mod.exports.debug
  local function steps(n) for _ = 1, n or 1 do mod.hooks_["input.step"](function() end, game, 1 / 60) end end
  local function update() mod.hooks_["core.update"](function() end, game, 1 / 60) end
  local function row(advice, slot) for _, r in ipairs(advice.moves) do if r.slot == slot then return r end end end

  -- the brain
  battle(mon("Blastoise", "WATER", nil, 150, 80, 10, { 1, 2, 3, 4 }), mon("Arcanine", "FIRE", nil, 150, 90, 8, { 7, 1 }))
  local a = api.evaluate({})
  check(a and a.best.kind == "move" and a.best.slot == 2, "a sure knock-out with the accurate move (Surf) beats the stronger, shakier one: slot " .. tostring(a.best.slot))
  check(row(a, 2).kill == "sure" and row(a, 3).kill == "sure" and row(a, 1).kill == nil, "knock-outs are told apart")
  check(a.faster == false and a.danger == false, "speed and danger are read")
  st.enemy.mon.hp = 400
  a = api.evaluate({})
  check(a.best.slot == 3 or a.best.slot == 4 or a.best.slot == 2, "with no knock-out, the most expected damage")
  check(row(a, 3).score < row(a, 2).score + 30, "accuracy is weighed in")
  -- immunities
  battle(mon("Golem", "GROUND", nil, 150, 40, 10, { 4, 1 }), mon("Gengar", "NORMAL", nil, 120, 100, 8, { 1 }, { ability = "LEVITATE" }))
  a = api.evaluate({})
  check(row(a, 1).max == 0 and a.best.slot == 2, "Earthquake does nothing to Levitate: the other move is chosen")
  battle(mon("Raichu", "ELECTRIC", nil, 120, 100, 10, { 9, 1 }), mon("Sandslash", "GROUND", nil, 150, 60, 8, { 4 }))
  a = api.evaluate({})
  check(row(a, 1).notes[1] == "IMMUNE" and a.best.slot == 2, "no Thunderbolt into a Ground type")
  -- status moves
  battle(mon("Venusaur", "GRASS", nil, 160, 80, 10, { 5, 6, 1 }), mon("Snorlax", "NORMAL", nil, 500, 30, 5, { 1 }))
  a = api.evaluate({})
  check(a.best.slot == 1, "a healthy foe with no status and no knock-out in sight: put it to sleep")
  st.enemy.status = "SLP"
  a = api.evaluate({}); check(a.best.slot == 2, "already asleep: attack")
  st.enemy.status = nil
  a = api.evaluate({ fast = true }); check(a.best.slot == 2, "in a hurry (training): attack, no status")
  a = api.evaluate({ ban = function(_, id) return id == 6 end })
  check(row(a, 2).banned and a.best.slot ~= 2, "a forbidden move is never chosen")
  check(api.bestMove({ fast = true }) == 2, "bestMove gives the slot")
  -- healing and set-up
  battle(mon("Starmie", "WATER", nil, 200, 110, 6, { 2, 8 }), mon("Rhydon", "NORMAL", nil, 900, 40, 5, { 1 }))
  st.player.mon.hp = 60
  a = api.evaluate({}); check(a.best.slot == 2, "low HP against a weak hitter: Recover")
  st.player.mon.hp = 200
  a = api.evaluate({}); check(a.best.slot == 1, "at full HP it attacks")
  battle(mon("Scyther", "NORMAL", nil, 200, 110, 6, { 1, 10 }), mon("Chansey", "NORMAL", nil, 900, 40, 2, { 1 }))
  a = api.evaluate({}); check(a.best.slot == 2, "time to set up against a wall: Swords Dance")
  st.player.stages.attack = 2
  a = api.evaluate({}); check(a.best.slot == 1, "boosted enough: attack")
  -- switching
  local char = mon("Charizard", "FIRE", nil, 150, 100, 10, { 7, 1 })
  local venu = mon("Venusaur", "GRASS", nil, 180, 80, 10, { 6, 1 })
  local gole = mon("Golem", "GROUND", nil, 180, 40, 10, { 4 })
  battle(char, mon("Blastoise", "WATER", nil, 300, 120, 10, { 2 }), { gole, venu })
  a = api.evaluate({})
  check(a.danger and a.best.kind == "switch" and a.best.mon == venu, "about to be knocked out by Surf: switch to the one that resists it")
  check(api.evaluate({ allowed = function(i) return i ~= 3 end }).best.kind == "move", "not to a team mate that is not allowed")
  require("src.core.game3.battle.engine").canSwitch = function() return false end
  a = api.evaluate({}); check(a.trapped and a.best.kind == "move", "held in place: no switch is advised, it fights")
  require("src.core.game3.battle.engine").canSwitch = nil
  a = api.evaluate({})
  st.enemy.mon.hp = 20
  a = api.evaluate({}); check(a.best.kind == "move", "but with a knock-out in hand... it is slower, the foe hits first")
  st.player.mon.moves = { 7, 11 }
  a = api.evaluate({}); check(a.best.kind == "move" and a.best.slot == 2, "a priority move that knocks out is taken instead of switching")
  st.enemy.mon.hp = 300; st.player.mon.moves = { 7, 1 }
  check(api.bestSwitch({}) == venu, "after a faint: the best matchup comes in")
  check(api.shift({ foeMon = mon("Blastoise", "WATER", nil, 300, 120, 10, { 2 }) }) == venu, "before the trainer's Water type: change to Grass")
  check(api.shift({ foeMon = mon("Rattata", "NORMAL", nil, 30, 20, 2, { 1 }) }) == nil, "before a weak one: stay")
  -- guessing the foe's moves
  mod.options_.foe_moves = "guess"
  battle(char, mon("Blastoise", "WATER", nil, 300, 120, 10, { 1 }), {})
  a = api.evaluate({}); check(a.threat.moves[1].guessed and a.threat.max > 100, "guessed moves: an attack of its own type")
  mod.options_.foe_moves = "all"
  a = api.evaluate({}); check(a.threat.max < 100, "known moves: only Tackle")

  -- the panel and the overlay
  local lang = os.getenv("TEST_LANG") or "en"
  update()
  local panel = panels["trainer_tactics.tactics"]
  check(panel ~= nil and registered["trainer_tactics.auto"] and registered["trainer_tactics.advisor"], "the panel is docked and two actions go to Trainer Controls")
  local function shot(name, w, h, fn)
    local c = G.newCanvas(w, h)
    G.setCanvas(c); G.clear(0.3, 0.5, 0.3, 1)
    local depth = G.getStackDepth(); fn(); check(G.getStackDepth() == depth, "stack balanced: " .. name)
    G.setCanvas()
    local f = io.open(OUT .. "/" .. name .. "-" .. lang .. ".png", "wb"); f:write(c:newImageData():encode("png"):getString()); f:close()
  end
  local clock = 10
  battle(char, mon("Blastoise", "WATER", nil, 300, 120, 10, { 2, 1 }), { gole, venu })
  snap = { prompt = "menu", revision = 1 }
  shot("panel-switch", 480, 432, function() panel.draw(clock, 480, 432) end)
  clock = clock + 1
  battle(mon("Venusaur", "GRASS", nil, 160, 80, 10, { 5, 6, 1, 8 }), mon("Snorlax", "NORMAL", nil, 500, 30, 5, { 1, 4 }), { char })
  shot("panel-moves", 480, 432, function() panel.draw(clock, 480, 432) end)
  shot("panel-narrow", 300, 560, function() panel.draw(clock, 300, 560) end)
  love.timer.getTime = function() return clock end
  local hud = mod.hooks_["render.hud"]
  local vp = { gameX = 0, gameY = 0, gameWidth = 720, gameHeight = 480, scale = 3 }
  shot("overlay", 720, 480, function() hud(function() end, game, vp) end)
  active = false; clock = clock + 1
  shot("panel-idle", 480, 432, function() panel.draw(clock, 480, 432) end)

  -- auto battle
  panel.draw(clock, 480, 432); panel.pointer("down", 100, 20)
  check(D.settings.auto == true and cache.auto == "1,0", "the panel switch turns auto battle on, remembered")
  battle(mon("Blastoise", "WATER", nil, 150, 80, 10, { 1, 2 }), mon("Arcanine", "FIRE", nil, 100, 90, 8, { 7 }))
  snap = { prompt = "menu", revision = 1 }; sent = {}
  steps(12); check(sent[1] and sent[1].kind == "menu" and sent[1].choice == "fight", "auto: FIGHT")
  snap = { prompt = "moves", revision = 2 }
  steps(12); check(sent[#sent].kind == "move" and sent[#sent].slot == 2, "auto: the best move")
  snap = { prompt = "advance", revision = 3 }; taps = {}
  steps(10); check(taps[1] == "a", "auto: text is advanced")
  Choice.open = true; taps = {}; local before = #sent
  steps(40); check(#taps == 0 and #sent == before, "a question (new move, nickname) is left to the player")
  Choice.open = false
  -- switching through the party menu
  battle(char, mon("Blastoise", "WATER", nil, 300, 120, 10, { 2 }), { gole, venu })
  snap = { prompt = "menu", revision = 4 }; sent = {}
  steps(12); check(sent[1].choice == "party", "auto: in danger it opens the party")
  PartyMenu.open, PartyMenu._party, PartyMenu.cursor = true, session.party, 1; taps = {}
  steps(25); check(PartyMenu.cursor == 3 and taps[1] == "a", "and picks the team mate the advice named")
  PartyMenu.open = false
  -- a refused switch (trapped) is not asked for again
  accept = false; snap = { prompt = "menu", revision = 5 }; sent = {}
  steps(12); accept = true; steps(12)
  check(sent[#sent].choice == "fight", "a switch the game refuses: fight instead")
  -- after a faint
  battle(char, mon("Blastoise", "WATER", nil, 300, 120, 10, { 2 }), { gole, venu })
  char.hp = 0; PartyMenu.open, PartyMenu.cursor = true, 1; taps = {}
  steps(25); check(PartyMenu.cursor == 3 and taps[1] == "a", "after a faint the best matchup is sent")
  PartyMenu.open = false; char.hp = 150
  -- the trainer's next one
  battle(char, mon("Rattata", "NORMAL", nil, 1, 20, 2, { 1 }), { gole, venu })
  Battle._phase, Battle._shiftEnemyIdx = "shift_prompt", 2
  st.foeParty = { st.enemy.mon, mon("Blastoise", "WATER", nil, 300, 120, 10, { 2 }) }
  Choice.open = true; taps = {}
  steps(20); check(taps[1] == "a", "\"Will you switch?\" before a bad matchup: yes")
  Battle._shiftEnemyIdx = 1; st.foeParty[1] = mon("Rattata", "NORMAL", nil, 30, 20, 2, { 1 }); taps = {}
  battle(char, st.foeParty[1], { gole, venu }); st.foeParty = { st.enemy.mon }
  steps(20); check(taps[1] == "b", "before a weak one: no")
  Battle._phase, Choice.open = nil, false
  -- Trainer Pilot playing: Tactics keeps its hands off
  pilot.exports.bot.running = true
  snap = { prompt = "menu", revision = 9 }; sent = {}
  steps(30); check(#sent == 0, "while Trainer Pilot runs, auto battle does nothing")
  pilot.exports.bot.running = false
  registered["trainer_tactics.auto"].run(); check(D.settings.auto == false, "the Trainer Controls action switches auto off")
  sent = {}; steps(30); check(#sent == 0, "off: nothing is done")
  check(#warns == 0, "nothing was logged")
  print("ALL TACTICS CHECKS PASSED")
  love.event.quit(0)
end
