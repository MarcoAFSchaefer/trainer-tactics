#!/usr/bin/env python3
"""Check a mod's lang/*.lua against lang/en.lua: missing keys, extra keys,
and %-directives that do not match. Usage: check_lang.py <mod folder>..."""
import re, sys, os, lupa

def load(path):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    src = open(path, encoding="utf-8").read()
    return lua.execute(src)

def walk(t, prefix=""):
    out = {}
    for k in t.keys():
        v = t[k]
        key = prefix + str(k)
        if hasattr(v, "keys"):
            out.update(walk(v, key + "."))
        else:
            out[key] = v
    return out

def directives(s):
    return sorted(re.findall(r"%[-0-9.]*[sdfx]", s)) if isinstance(s, str) else []

bad = 0
for folder in sys.argv[1:]:
    en = walk(load(os.path.join(folder, "lang", "en.lua")))
    for code in ("es", "pt", "ja"):
        path = os.path.join(folder, "lang", code + ".lua")
        other = walk(load(path))
        missing = [k for k in en if k not in other and not k.startswith("TYPES.")]
        extra = [k for k in other if k not in en and not k.startswith("TYPES.")]
        mism = [k for k in en if k in other and directives(en[k]) != directives(other[k])]
        for name, items in (("missing", missing), ("extra", extra), ("directives differ", mism)):
            if items:
                bad += 1
                print(f"{folder} {code}: {name}: {', '.join(sorted(items))}")
    print(f"{folder}: {len(en)} keys checked")
sys.exit(1 if bad else 0)
