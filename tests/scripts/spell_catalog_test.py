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

    def test_library_pin_and_toc_mismatches_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "lib"
            (library / "clientdata").mkdir(parents=True)
            (root / "UnitFrames").mkdir()
            toc = root / "UnitFrames/UnitFrames.toc"
            toc.write_text("## Interface: 16001\n")
            pin_file = library / "clientdata/forever.json"
            with self.assertRaisesRegex(ValueError, "fetch-wut"):
                catalog.pinned_source(root, library)
            pin = {"build": self.pin["build"], "interface": self.pin["interface"],
                   "wowUiSource": {"commit": self.pin["uiCommit"]}}
            pin_file.write_text(json.dumps(pin))
            self.assertEqual(self.pin, catalog.pinned_source(root, library))
            toc.write_text("## Interface: 16002\n")
            with self.assertRaisesRegex(ValueError, "TOC interface"):
                catalog.pinned_source(root, library)
            toc.write_text("## Interface: 16001\n")
            pin_file.write_text(json.dumps({**pin, "wowUiSource": {"commit": "short"}}))
            with self.assertRaisesRegex(ValueError, "exact Forever source pin"):
                catalog.pinned_source(root, library)

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


class BuffCatalogTests(unittest.TestCase):
    extras = {"hot": ((408120,),), "proc": ((408514,), (401859, 401877)), "external": ((10060,),), "raid": ((14752,),)}

    @classmethod
    def setUpClass(cls):
        cls.pin = catalog.pinned_source()
        cls.tables = json.loads(catalog.FIXTURE.read_text())["tables"]
        cls.buffs = catalog.compile_buffs(cls.tables, cls.pin, cls.extras)
        cls.families = cls.buffs["families"]
        cls.by_id = {spell_id: root for root, family in cls.families.items() for spell_id in family["ids"]}

    def test_skill_line_and_raid_flagged_ranks_share_one_family(self):
        rejuvenation = self.families[774]
        self.assertEqual(("DRUID", "hot"), (rejuvenation["class"], rejuvenation["kind"]))
        self.assertTrue({774, 1058, 25299, 417057, 417068} <= set(rejuvenation["ids"]))
        self.assertEqual(436937, max(self.families[8936]["ids"]))
        self.assertIn(425268, self.families[139]["ids"])
        self.assertIn(417057, self.buffs["raidInCombat"])
        self.assertNotIn(774, self.buffs["raidInCombat"])

    def test_heals_and_absorbs_are_classified_from_effects(self):
        expected = {17: "absorb", 139: "hot", 774: "hot", 8936: "hot", 408124: "hot", 408521: "hot"}
        self.assertEqual(expected, {root: self.families[root]["kind"] for root in expected})
        self.assertEqual(17, self.by_id[10901])

    def test_shared_class_masks_split_by_school_and_aura(self):
        self.assertNotIn(27813, self.by_id)
        self.assertNotEqual(self.by_id[10060], self.by_id[14752])

    def test_self_and_pet_absorbs_are_not_heals(self):
        self.assertNotIn(543, self.by_id)
        self.assertNotIn(7812, self.by_id)

    def test_curated_extras_expand_from_their_roots(self):
        self.assertEqual(("hot", [408120]), (self.families[408120]["kind"], self.families[408120]["ids"]))
        self.assertEqual([974, 408514], self.families[408514]["ids"])
        self.assertEqual(401859, self.by_id[401877])
        self.assertEqual("proc", self.families[401859]["kind"])
        with self.assertRaisesRegex(ValueError, "curated buff roots"):
            catalog.compile_buffs(self.tables, self.pin, {"hot": ((9999999,),)})

    def test_lua_output_lists_families_and_lookups(self):
        output = catalog.lua_buffs(self.buffs)
        self.assertIn('[774] = { name = "Rejuvenation", class = "DRUID", kind = "hot", ids = { 774, 1058, 25299, 417057', output)
        self.assertIn("[417068] = 774,", output)
        self.assertIn("[417057] = true,", output)

    def test_buff_generation_is_independent_of_input_order(self):
        reversed_tables = {name: list(reversed(rows)) for name, rows in self.tables.items()}
        self.assertEqual(self.buffs, catalog.compile_buffs(reversed_tables, self.pin, self.extras))


if __name__ == "__main__":
    unittest.main()
