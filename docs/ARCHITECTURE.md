# Architecture

```
trainer_tactics/
  brain.lua   the decision: scores for moves and switches (no side effects)
  main.lua    options, auto battle driver, advisor overlay, Desk panel, API
  panel.lua   drawing of the panel and of the battle-screen box
  i18n.lua, lang/, fonts/
```

## The brain

`Brain.evaluate(opts)` reads the live battle state (`battle.getState()`, the adapter for abilities) and returns moves, the foe's threat, the bench and `best`.

**Damage** is `battle.damage.calc(attacker, defender, move, { forceCrit = false, forceRoll = 85 | 100, weather, adapter, st })`: the game's function, lowest and highest roll. Then: 0 against Levitate / Volt Absorb / Water Absorb / Flash Fire for their type and against Wonder Guard unless super effective; multi-hit moves scaled (2-5 hits, double hits, Triple Kick).

**Speed** is `engine.speedOf` (stages, paralysis, items); a move with priority goes first.

**Move scores**

| Case | Score |
| --- | --- |
| Certain knock-out (lowest roll) | 200 + accuracy (+20 when it lands first, + up to 5 for PP) |
| Possible knock-out | 100 x expected share + 40 x accuracy |
| Other attacks | 100 x expected share of the foe's HP (expected = average roll x accuracy), at least 6 |
| Two-turn moves x0.5 (Fly/Dig x0.7), recharge x0.6, Focus Punch x0.3, slower and in danger x0.6 | |
| Explosion | 150 only as a certain knock-out under 30% HP, else last resort |
| Sleep 85, paralysis 60 (30 when already faster), Toxic 40, burn 45 vs physical foes, confusion/Leech Seed/Yawn 30 | only when the foe has no status and is not immune; x accuracy; x0.2 when in danger and slower |
| Set-up 50-60 | stage under +2, a matching attack, at least 3 turns to live |
| Recover-like 90-110, Rest 80 | under half (a third) HP and the heal outpaces the foe |

With `fast = true` (Trainer Pilot) non-attacks are worth nothing while an attack can hurt, except healing.

**Switching** is never advised when `engine.canSwitch` says the one out is held in place. Otherwise it is considered when the one out is in danger (unless it knocks out first) or its best score is under 25. Each team mate gets `give` (best expected damage, % of foe HP) and `take` (the foe's strongest hit, % of its HP), `survives` (one hit coming in, two if slower) and `matchup = give - 0.6 x take`. A surviving one more than 30 points better than the one out scores `100 + min(60, difference)`: above plain attacks, below certain knock-outs.

## Auto battle

On every `input.step`, when on and Trainer Pilot is not running: the shift prompt (A or B), the party menu (cursor on the planned team mate, A), then by `BattleAPI:snapshot().prompt`: `advance`/`locked` tap A; `menu` submits `fight` or `party`; `moves` submits the slot; `target` the first foe standing. An open choice outside the shift prompt is never answered. Thirty refused submissions in a row turn auto battle off.

## Showing

The view (names and percentages) is rebuilt at most every 0.3 s. `render.hud` draws the box when the prompt is `menu` or `moves`, advice is on, auto is off and Pilot is not running.

The two switches are kept in the mod cache as `auto` and `advisor` ("<on>,<option when set>").
