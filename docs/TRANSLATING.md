# Translating

Trainer Desk, Trainer Lens, Trainer Pilot and Trainer Controls share one way of handling text. Each mod has:

- `i18n.lua`: picks the language from the mod's **Language** option, looks texts up, and makes fonts that can draw Japanese. The file is the same in every Trainer mod.
- `lang/en.lua`, `lang/es.lua`, `lang/pt.lua`, `lang/ja.lua`: one Lua table of texts per language.
- `fonts/NotoSansJP-subset.ttf`: Noto Sans JP cut down to kana, CJK punctuation, full-width forms and every character in the mods' `lang/ja.lua` files.

## How texts are looked up

Code asks for a key: `T("key")` returns the text, `F("key", ...)` formats it with `string.format`. Values can also be tables (lists of names, the texts of every stop reason).

- English (`en.lua`) is the reference and has every key.
- A key another language lacks falls back to English.
- A key English lacks shows as the key itself, so a mistake is visible instead of breaking a panel.
- `F` falls back to the English text if a translation's `%` directives do not fit the values.

Names that come from the game (Pokémon, moves, items, abilities, places) are not translated by Desk, Lens and Pilot: they come from the player's game, in its own language. Trainer Controls and Trainer Journey are the exceptions: their texts name moves, items and places, written by hand in each language (Spanish and Japanese use the names of those versions of the games; Portuguese keeps the English names).

## Changing a translation

1. Edit the text in `lang/<code>.lua`. Keep every `%d`/`%s` of the English text, in the same order.
2. Check the files against English:

   ```
   pip install lupa
   python3 tools/check_lang.py <mod folder>
   ```

   It lists keys that are missing or extra, and texts whose `%` directives differ from English.
3. If you changed Japanese text, rebuild the font so every character is in it (needs `fonttools` and the full Noto Sans JP Regular TTF):

   ```
   python3 tools/build_font.py NotoSansJP-Regular.ttf trainer_tactics/fonts/NotoSansJP-subset.ttf trainer_tactics/lang/ja.lua
   ```

   Trainer Controls keeps its own subset, built from its own `ja.lua`.

4. Look at the panels in that language: the tests take screenshots with `TEST_LANG=<code>` (see tests/README.md). Text that is too long is cut with ".." or, on some lines, wraps onto the next one.

## Adding a language

Add `lang/<code>.lua` with every key of `en.lua`, add the code to `known` and `LANGUAGES` in `i18n.lua` (in every mod), and add a choice to the `language` option in `main.lua`. The game's options menu draws choice labels with its own font, so keep them in plain capital letters without accents.

## Fonts

LÖVE's default face draws Latin text. Every font a mod makes goes through `I.font(size)`, which adds two fallbacks: the bundled Japanese face, then the game's own wide pixel face (`assets/fonts/plainpixel/PlainPixel-Regular.ttf`, when the game has it) for anything else.
