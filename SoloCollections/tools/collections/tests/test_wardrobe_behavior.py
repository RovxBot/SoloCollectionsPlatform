from __future__ import annotations

import shutil
import subprocess
import unittest

from common import ADDON, ROOT


class WardrobeBehaviorTests(unittest.TestCase):
    def run_harness(self, name: str) -> None:
        lua = shutil.which("lua5.1") or shutil.which("lua")
        if not lua:
            self.skipTest("Lua interpreter is not installed")
        result = subprocess.run(
            [lua, str(ROOT / "tools/collections/tests/lua" / name), str(ADDON)],
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_quote_confirmation_and_delayed_replies(self):
        self.run_harness("wardrobe_quote_harness.lua")


if __name__ == "__main__":
    unittest.main()
