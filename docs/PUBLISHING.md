# Publishing

How this mod gets to players: as a GitHub release, listed in the Gen1Recomp mod index (the launcher's **Find mods** tab).

## 1. The repository

The repository must be public on GitHub. Once it exists:

- The repository is `https://github.com/MarcoAFSchaefer/trainer-tactics`. `manifest.json` names it in `"github"` (the launcher uses it for updates and "Other versions"), and so does the index entry.

## 2. Releases

`.github/workflows/release.yml` publishes a release whenever a tag `v<version>` is pushed:

```
git tag v1.2.3
git push origin v1.2.3
```

The tag must match `version` in `manifest.json`, or the workflow stops. The release gets `<id>-<version>.zip` with the mod's files at the archive root (what the launcher and the index look for), and the notes are that version's section of CHANGELOG.md.

## 3. The index entry

The index is <https://github.com/bryanthaboi/gen1recomp-mod-index>. An entry is one folder, `mods/<Author>@<id>/`, holding `meta.json`, `description.md` and optionally `thumbnail.png` or `thumbnail.jpg` (2 MB at most). Nothing else may be in it.

This repository keeps its entry ready in `index/`. To submit it, either use the index's submission helper (<https://bryanthaboi.github.io/gen1recomp-mod-index/>), or fork the index, copy the folder into `mods/`, and open a pull request. The index's CI checks the schema, that the release zip downloads, the Lua inside it against the game's sandbox, and its blocklist.

After the first listing, new versions need no pull request: the index reads the repository's releases every night. Open one only to change the listing itself (description, categories, thumbnail).

## What the sandbox scan will report

- `load`: used to load the mod's own files (`i18n.lua`, `brain.lua`, `panel.lua`, `lang/*.lua`). Reported for review, not blocking.

## Before each release

- Run the tests in every language (`TEST_LANG=en|es|pt|ja`, see tests/README.md).
- `python3 tools/check_lang.py <mod folder>` passes.
- Bump `version` in `manifest.json`, add the CHANGELOG section, commit, tag.
