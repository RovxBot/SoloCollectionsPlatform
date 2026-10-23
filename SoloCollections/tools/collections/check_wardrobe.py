#!/usr/bin/env python3
"""Check the active wardrobe without accessing a server or game installation."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tools/collections/tests"
SUITES = [
    "test_addon_contract", "test_bridge_contract", "test_sc2_client_contract",
    "test_wardrobe_camera_set_contract", "test_wardrobe_behavior", "test_mount_actions",
]


def main() -> int:
    lua = next((path for name in ("lua5.1", "luajit", "lua5.4", "lua") if (path := shutil.which(name))), None)
    compiler = next((path for name in ("luac5.1", "luac5.4", "luac") if (path := shutil.which(name))), None)
    if not lua or not compiler:
        print("A Lua interpreter and luac are required for wardrobe validation.", file=sys.stderr)
        return 2
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for path in sorted((ROOT / "addon/SoloCollections").rglob("*.lua")):
        result = subprocess.run([compiler, "-p", str(path)], env=environment)
        if result.returncode:
            return result.returncode
    print(f"Lua syntax passed using {Path(compiler).name}.", flush=True)
    return subprocess.run(
        [sys.executable, "-m", "unittest", *SUITES], cwd=TESTS, env=environment,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
