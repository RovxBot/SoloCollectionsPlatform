from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from common import ADDON, ROOT


class MountActionTests(unittest.TestCase):
    def test_shared_mount_shortcuts_and_journal_adapter(self):
        lua = next((path for name in ("lua5.1", "luajit", "lua5.4", "lua")
                    if (path := shutil.which(name))), None)
        if not lua:
            self.skipTest("Lua interpreter is not installed")
        result = subprocess.run(
            [lua, str(ROOT / "tools/collections/tests/lua/mount_actions_harness.lua"), str(ADDON)],
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_random_spell_overlay_preserves_all_existing_spell_records(self):
        spec = importlib.util.spec_from_file_location(
            "random_mount_builder", ROOT / "tools/dbc/build_random_mount_spell.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        # Synthetic records exercise the flight restriction and unrelated fields.
        rows = []
        for spell_id in (458, 32235, 60025):
            row = [spell_id + index for index in range(builder.SPELL_FIELDS)]
            row[0] = spell_id
            row[8] = 0x04000000
            rows.append(row)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.dbc"
            output = Path(directory) / "output.dbc"
            builder.write_dbc(source, rows, bytearray(b"\0"))
            builder.build_spell(source, output, 123)
            actual, _ = builder.read_dbc(output, builder.SPELL_FIELDS, builder.SPELL_RECORD_SIZE)
        self.assertEqual(rows, [row for row in actual if row[0] != builder.SPELL_ID])
        self.assertEqual(1, sum(row[0] == builder.SPELL_ID for row in actual))

    def test_both_mount_journal_views_use_the_shared_shortcut(self):
        toc = (ADDON / "SoloCollections.toc").read_text()
        self.assertLess(toc.index("Core\\MountActions.lua"), toc.index("UI\\Mounts.lua"))
        mounts = (ADDON / "UI/Mounts.lua").read_text()
        adapter = (ADDON / "UI/DragonUI/CollectionsBridge.lua").read_text()
        self.assertIn("SC.MountActions.Pickup(record and record.id)", mounts)
        self.assertIn("SC.MountActions.PickupRandom()", mounts)
        self.assertIn("SC.MountActions.Pickup(entry.collectionId)", adapter)


if __name__ == "__main__":
    unittest.main()
