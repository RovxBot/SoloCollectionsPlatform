#!/usr/bin/env python3
"""Run collection contracts and portable native tests without a Core/server build."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "tests/native"


def main() -> int:
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "test_wardrobe_projection_contract",
         "test_phase9_outfit_contract", "test_p0_security_contract", "test_phase8_appearance_service_contract",
         "test_phase6_mount_unlock_contract"],
        cwd=ROOT / "tests", env=environment,
    )
    if result.returncode:
        return result.returncode
    compiler = shutil.which("g++") or shutil.which("clang++")
    if not compiler:
        print("A C++20 compiler is required for the portable native checks.", file=sys.stderr)
        return 2
    targets = re.findall(r"add_executable\(\s*(\w+)\s+([^)]*)\)",
                         (NATIVE / "CMakeLists.txt").read_text())
    if not targets:
        print("No native test targets were found.", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="solo-collections-check-") as directory:
        for name, block in targets:
            output = Path(directory) / name
            sources = [str((NATIVE / source).resolve()) for source in block.split()]
            command = [compiler, "-std=c++20", "-O2", "-Wall", "-Wextra", "-Wpedantic",
                       "-Werror", "-I", str(ROOT / "src"), *sources, "-o", str(output)]
            result = subprocess.run(command, env=environment)
            if result.returncode:
                return result.returncode
            result = subprocess.run([str(output)], env=environment)
            if result.returncode:
                return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
