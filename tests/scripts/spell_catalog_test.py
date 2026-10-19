import copy
import csv
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("spell_catalog", ROOT / "scripts/spell_catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class SpellCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pin = catalog.pinned_source()
        fixture = json.loads(catalog.FIXTURE.read_text())
        cls.tables = fixture["tables"]
        cls.manifest = catalog.read_manifest(cls.pin)
        cls.report = catalog.compile_catalog(cls.tables, cls.pin)

    def test_priest_dots_and_channels_use_forever_records(self):
        catalog.validate_evidence(self.tables)
        included = {row["id"]: row for row in self.report["included"]}
        excluded = {row["id"]: row for row in self.report["excluded"]}
        self.assertEqual(included[589]["school"], 32)
        self.assertEqual(included[2944]["aura"], 53)
        self.assertEqual(included[14914]["periodMs"], 2000)
        for spell_id in (15407, 755):
            self.assertNotIn(spell_id, included)
            self.assertEqual(excluded[spell_id]["reason"], "channel")
        self.assertNotIn(139, included)

    def test_classification_does_not_depend_on_english_names(self):
        tables = dict(self.tables)
        tables["SpellName"] = [{"ID": row["ID"], "Name_lang": "غير إنجليزي"} for row in self.tables["SpellName"]]
        renamed = catalog.compile_catalog(tables, self.pin)
        self.assertEqual(catalog.lua_catalog(self.report), catalog.lua_catalog(renamed))

    def test_resource_effects_and_class_masks_generate_runtime_metadata(self):
        included = {row["id"]: row for row in self.report["included"]}
        self.assertEqual(included[172]["family"], included[6222]["family"])
        self.assertEqual(included[980]["family"], included[1014]["family"])
        self.assertEqual(self.report["builders"][1082], 1)
        self.assertIn(2098, self.report["finishers"])
        self.assertTrue(included[1978]["projectile"])

    def test_periodic_candidates_have_a_disposition(self):
        expected = {int(row["SpellID"]) for row in self.tables["SpellEffect"]
            if int(row["DifficultyID"]) == 0 and int(row["EffectAura"]) in (3, 53, 89, 23, 227)}
        included = {row["id"] for row in self.report["included"]}
        excluded = {row["id"] for row in self.report["excluded"]}
        self.assertFalse(included & excluded)
        self.assertEqual(expected, included | excluded)

    def test_new_spells_are_discovered_from_effects(self):
        tables = dict(self.tables)
        for table, field in (("SpellEffect", "SpellID"), ("SpellMisc", "SpellID"), ("SpellInterrupts", "SpellID"), ("SkillLineAbility", "Spell")):
            rows = copy.deepcopy([row for row in self.tables[table] if row[field] == "589"])
            for index, row in enumerate(rows):
                row[field] = "9999999"
                row["ID"] = str(9999999 + index)
            tables[table] = self.tables[table] + rows
        included = {row["id"] for row in catalog.compile_catalog(tables, self.pin)["included"]}
        self.assertIn(9999999, included)

    def test_schema_changes_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing columns"):
            catalog.parse_table("SpellMisc", b"ID,SpellID\n1,589\n")

    def test_server_must_confirm_exact_requested_build(self):
        headers = 'HTTP/2 200\ncontent-disposition: attachment; filename="SpellEffect.1.60.1.70450.csv"\n'
        catalog.validate_download("SpellEffect", "1.60.1.70450", headers)
        with self.assertRaisesRegex(ValueError, "did not confirm"):
            catalog.validate_download("SpellEffect", "1.60.1.99999", headers)
        with self.assertRaisesRegex(ValueError, "did not confirm"):
            catalog.validate_download("SpellEffect", "1.60.1.70450", headers + 'HTTP/2 200\ncontent-type: text/html\n')

    def test_workflow_and_toc_mismatches_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflows = root / ".github/workflows"
            workflows.mkdir(parents=True)
            (root / "UnitFrames").mkdir()
            toc = root / "UnitFrames/UnitFrames.toc"
            toc.write_text("## Interface: 16001\n")
            pin = f'repository: Gethe/wow-ui-source\nref: {self.pin["uiCommit"]} # Forever {self.pin["build"]}\n'
            for workflow in ("tests", "release"):
                (workflows / f"{workflow}.yml").write_text(pin)
            self.assertEqual(self.pin, catalog.pinned_source(root))
            toc.write_text("## Interface: 16002\n")
            with self.assertRaisesRegex(ValueError, "TOC interface"):
                catalog.pinned_source(root)
            toc.write_text("## Interface: 16001\n")
            (workflows / "release.yml").write_text(pin.replace(self.pin["uiCommit"], "f" * 40))
            with self.assertRaisesRegex(ValueError, "pins disagree"):
                catalog.pinned_source(root)

    def test_build_mismatch_and_modified_inputs_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            catalog.read_snapshot({**self.pin, "build": "1.60.1.99999"})
        original_data, original_cache = catalog.DATA, catalog.CACHE
        with tempfile.TemporaryDirectory() as directory:
            try:
                catalog.DATA = Path(directory)
                catalog.CACHE = Path(directory) / "cache"
                destination = catalog.CACHE / self.pin["build"]
                destination.mkdir(parents=True)
                manifest = copy.deepcopy(self.manifest)
                for name in catalog.TABLES:
                    output = io.StringIO()
                    writer = csv.DictWriter(output, fieldnames=sorted(catalog.TABLES[name]))
                    writer.writeheader()
                    writer.writerows(self.tables[name])
                    raw = output.getvalue().encode()
                    manifest["tables"][name]["sha256"] = catalog.digest(raw)
                    manifest["tables"][name]["rows"] = len(self.tables[name])
                    if name == "SpellEffect":
                        raw += b"\n"
                    (destination / f"{name}.csv.gz").write_bytes(catalog.gzip.compress(raw, mtime=0))
                (catalog.DATA / "manifest.json").write_text(catalog.canonical(manifest))
                with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                    catalog.read_snapshot(self.pin)
            finally:
                catalog.DATA, catalog.CACHE = original_data, original_cache

    def test_changed_channel_evidence_requires_review(self):
        tables = dict(self.tables)
        tables["SpellInterrupts"] = copy.deepcopy(self.tables["SpellInterrupts"])
        for row in tables["SpellInterrupts"]:
            if row["SpellID"] == "15407":
                row["ChannelInterruptFlags_0"] = "0"
                row["ChannelInterruptFlags_1"] = "0"
        with self.assertRaisesRegex(ValueError, "channel evidence changed"):
            catalog.validate_evidence(tables)

    def test_generation_is_independent_of_input_order(self):
        reversed_tables = {name: list(reversed(rows)) for name, rows in self.tables.items()}
        self.assertEqual(self.report, catalog.compile_catalog(reversed_tables, self.pin))


if __name__ == "__main__":
    unittest.main()
