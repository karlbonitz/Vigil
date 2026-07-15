#!/usr/bin/env python3
"""Headless smoke test: load Vantage under a stubbed WoW API (real Lua 5.1 via
lupa) and drive a fake session per class. Usage: python3 tests/run.py"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CLASS_CONFIGS = [
    # hard-kick class: full cue -> range -> flash -> wasted paths.
    # bossCode "ready": hard kicks ignore CC immunity — a boss's interruptible
    # cast still cues (only SOFT stops suppress on immune targets).
    {"class": "SHAMAN", "className": "Shaman", "spell": "Earth Shock",
     "label": "SHOCK", "hardKick": True, "bossCode": "ready",
     "cooldowns": {"Earth Shock": [0, 0]}},
    # soft-CC class: FEAR cue, boss immunity suppression -> aware tier
    {"class": "PRIEST", "className": "Priest", "spell": "Psychic Scream",
     "label": "FEAR", "hardKick": False, "bossCode": "aware",
     "cooldowns": {"Psychic Scream": [0, 0], "Shackle Undead": [0, 0]}},
]


def toc_files():
    files = []
    with open(os.path.join(ROOT, "Vantage.toc")) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            files.append(line.replace("\\", "/"))
    return files


def lua_table(rt, obj):
    """Recursively convert a python dict/list into a lua table."""
    if isinstance(obj, dict):
        t = rt.table()
        for k, v in obj.items():
            t[k] = lua_table(rt, v)
        return t
    if isinstance(obj, (list, tuple)):
        t = rt.table()
        for i, v in enumerate(obj, 1):
            t[i] = lua_table(rt, v)
        return t
    return obj


def run_class(cfg):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()

    with open(os.path.join(ROOT, "tests", "wow_stub.lua")) as fh:
        rt.execute(fh.read())

    g.CLASS_CONFIG = lua_table(rt, cfg)

    # cooldown map must live in Harness (scenario copies it, but set both ways)
    load_file = g.Harness.LoadAddonFile
    ns = rt.table()
    for f in toc_files():
        try:
            load_file(os.path.join(ROOT, f), ns)
        except lua51.LuaError as e:
            print(f"FAIL [{cfg['class']}] loading {f}:\n{e}")
            return False

    # expose the private addon namespace to the scenario's assertions
    g.Vantage = ns

    try:
        with open(os.path.join(ROOT, "tests", "scenario.lua")) as fh:
            result = rt.execute(fh.read())
        print(f"OK   {result}")
        return True
    except lua51.LuaError as e:
        print(f"FAIL scenario [{cfg['class']}]:\n{e}")
        printed = g.Harness.printed
        n = len(printed)
        if n:
            print("  last chat output:")
            for i in range(max(1, n - 5), n + 1):
                print(f"    {printed[i]}")
        return False


def main():
    ok = True
    for cfg in CLASS_CONFIGS:
        ok = run_class(cfg) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
