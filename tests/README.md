# Tests

`tests/main.lua` is a LÖVE program with a small stand-in battle (types, damage, speed, menus). It checks the brain's choices, auto battle through the menus, and saves screenshots of the panel and the battle-screen box.

```
cd tests
TACTICS_MOD=../trainer_tactics TEST_LANG=en xvfb-run -a -s "-screen 0 1280x800x24" love .
```

The run ends with `ALL TACTICS CHECKS PASSED`. The stand-in damage is not the game's formula: real numbers need the game.
