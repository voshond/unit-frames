import argparse
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from collections import defaultdict


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/forever-spells"
CACHE = ROOT / "examples/forever-spells"
OUTPUT = ROOT / "UnitFrames/Tracking/DotCatalog.lua"
FIXTURE = ROOT / "tests/fixtures/dot_source.json"
TABLES = {
    "SpellEffect": {"ID", "SpellID", "DifficultyID", "Effect", "EffectAura", "EffectAuraPeriod", "EffectBasePointsF", "EffectTriggerSpell", "ImplicitTarget_0", "ImplicitTarget_1", "EffectPointsPerResource", "EffectBonusCoefficient", "BonusCoefficientFromAP", "EffectRealPointsPerLevel", "EffectMiscValue_0"},
    "SpellMisc": {"ID", "SpellID", "DifficultyID", "Attributes_0", "Attributes_1", "DurationIndex", "SchoolMask", "Speed", "LaunchDelay"},
    "SpellDuration": {"ID", "Duration", "MaxDuration", "DurationPerResource"},
    "SpellInterrupts": {"ID", "SpellID", "DifficultyID", "ChannelInterruptFlags_0", "ChannelInterruptFlags_1"},
    "SkillLineAbility": {"ID", "Spell", "ClassMask", "SupercedesSpell"},
    "SpellName": {"ID", "Name_lang"},
    "SpellClassOptions": {"ID", "SpellID", "SpellClassSet", "SpellClassMask_0", "SpellClassMask_1", "SpellClassMask_2", "SpellClassMask_3"},
    "SpellPower": {"ID", "SpellID", "PowerType", "ManaCost", "OptionalCost"},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def pinned_source(root=ROOT):
    pins = []
    for workflow in ("tests", "release"):
        content = (root / f".github/workflows/{workflow}.yml").read_text()
        match = re.search(r"repository: Gethe/wow-ui-source\s+ref: ([0-9a-f]{40}) # Forever (1\.60\.\d+\.\d+)", content)
        if not match:
            raise ValueError(f"missing exact Forever source pin in {workflow}.yml")
        pins.append(match.groups())
    if pins[0] != pins[1]:
        raise ValueError("tests and release Forever source pins disagree")
    interface = re.search(r"^## Interface: (\d+)$", (root / "UnitFrames/UnitFrames.toc").read_text(), re.M)
    major, minor, patch, _ = map(int, pins[0][1].split("."))
    expected = major * 10000 + minor * 100 + patch
    if not interface or int(interface[1]) != expected:
        raise ValueError("TOC interface does not match the pinned Forever build")
    return {"uiCommit": pins[0][0], "build": pins[0][1], "interface": expected}


def parse_table(name, raw):
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    missing = TABLES[name] - set(reader.fieldnames or [])
    if missing:
        raise ValueError(f"{name}: missing columns {sorted(missing)}")
    rows = list(reader)
    ids = [int(row["ID"]) for row in rows]
    if not rows or len(ids) != len(set(ids)):
        raise ValueError(f"{name}: empty table or duplicate IDs")
    return rows


def download(pin, source=None):
    if source is not None:
        version = (source / "version.txt").read_text().strip()
        commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if version != pin["build"] or commit != pin["uiCommit"]:
            raise ValueError("local Forever UI checkout does not match the workflow pin")
    tables, records, compressed = {}, {}, {}
    for name in TABLES:
        url = f"https://wago.tools/db2/{name}/csv?build={pin['build']}&locale=enUS"
        with tempfile.TemporaryDirectory() as directory:
            headers = Path(directory) / "headers"
            raw = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "90", "--dump-header", str(headers), url])
            validate_download(name, pin["build"], headers.read_text())
        rows = parse_table(name, raw)
        tables[name] = rows
        compressed[name] = gzip.compress(raw, mtime=0)
        records[name] = {"url": url, "filename": f"{name}.{pin['build']}.csv", "sha256": digest(raw), "rows": len(rows)}
        print(f"Fetched {name}: {len(rows)} records", file=sys.stderr)
    return tables, {**pin, "format": 1, "tables": records}, compressed


def validate_download(name, build, headers):
    responses = re.split(r"(?=HTTP/\S+ \d{3})", headers)
    final = responses[-1]
    expected = f'{name}.{build}.csv'
    disposition = re.search(r"^content-disposition:\s*(.+)$", final, re.I | re.M)
    if not disposition or f'filename="{expected}"' not in disposition[1]:
        raise ValueError(f"{name}: server did not confirm the requested build {build}")


def read_manifest(pin):
    manifest = json.loads((DATA / "manifest.json").read_text())
    if manifest.get("format") != 1 or any(manifest.get(key) != value for key, value in pin.items()):
        raise ValueError("spell snapshot does not match the pinned Forever source; run --update")
    if set(manifest["tables"]) != set(TABLES):
        raise ValueError("spell snapshot table set changed; run --update")
    for name in TABLES:
        record = manifest["tables"][name]
        expected_url = f"https://wago.tools/db2/{name}/csv?build={pin['build']}&locale=enUS"
        if record["url"] != expected_url:
            raise ValueError(f"{name}: source URL does not match the pinned build")
        if record.get("filename") != f"{name}.{pin['build']}.csv":
            raise ValueError(f"{name}: download build provenance is missing")
        if not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) or record["rows"] <= 0:
            raise ValueError(f"{name}: invalid checksum or row count")
    return manifest


def read_snapshot(pin):
    manifest = read_manifest(pin)
    tables = {}
    for name in TABLES:
        record = manifest["tables"][name]
        raw = gzip.decompress((CACHE / pin["build"] / f"{name}.csv.gz").read_bytes())
        if digest(raw) != record["sha256"]:
            raise ValueError(f"{name}: checksum mismatch")
        tables[name] = parse_table(name, raw)
        if len(tables[name]) != record["rows"]:
            raise ValueError(f"{name}: row count mismatch")
    return tables, manifest


def write_cache(pin, compressed):
    directory = CACHE / pin["build"]
    directory.mkdir(parents=True, exist_ok=True)
    for name, content in compressed.items():
        (directory / f"{name}.csv.gz").write_bytes(content)


def fixture_data(tables, pin):
    spells = {589, 2944, 14914, 15407, 755, 10, 172, 6222, 980, 1014, 1082, 2098, 1079, 1943, 1978, 139}
    selected = {}
    for name, rows in tables.items():
        if name == "SpellDuration":
            continue
        key = "Spell" if name == "SkillLineAbility" else "ID" if name == "SpellName" else "SpellID"
        selected[name] = sorted([{field: row[field] for field in TABLES[name]} for row in rows if int(row[key]) in spells], key=lambda row: int(row["ID"]))
    durations = {int(row["DurationIndex"]) for row in selected["SpellMisc"]}
    selected["SpellDuration"] = sorted([{field: row[field] for field in TABLES["SpellDuration"]} for row in tables["SpellDuration"] if int(row["ID"]) in durations], key=lambda row: int(row["ID"]))
    return {**pin, "tables": selected}


def default_rows(rows, key):
    result = {}
    for row in rows:
        if int(row.get("DifficultyID", 0)) != 0:
            continue
        value = int(row[key])
        if value in result:
            raise ValueError(f"duplicate default record for {key}={value}")
        result[value] = row
    return result


def validate_evidence(tables):
    effects = defaultdict(list)
    for row in tables["SpellEffect"]:
        if int(row["DifficultyID"]) == 0:
            effects[int(row["SpellID"])].append(row)
    for spell_id, aura, period in ((589, 3, 3000), (2944, 53, 3000), (14914, 3, 2000)):
        matches = [row for row in effects[spell_id] if int(row["EffectAura"]) == aura]
        if len(matches) != 1 or any(int(matches[0][field]) != expected for field, expected in
                (("Effect", 6), ("EffectAuraPeriod", period), ("ImplicitTarget_0", 6), ("ImplicitTarget_1", 0))):
            raise ValueError(f"Forever periodic-effect evidence changed for spell {spell_id}; review classification rules")
    misc = default_rows(tables["SpellMisc"], "SpellID")
    interrupts = default_rows(tables["SpellInterrupts"], "SpellID")
    for spell_id in (15407, 755, 10):
        if not int(misc[spell_id]["Attributes_1"]) & 0x44 or not any(int(interrupts[spell_id][key]) for key in
                ("ChannelInterruptFlags_0", "ChannelInterruptFlags_1")):
            raise ValueError(f"Forever channel evidence changed for spell {spell_id}; review classification rules")


def compile_catalog(tables, pin):
    misc = default_rows(tables["SpellMisc"], "SpellID")
    durations = default_rows(tables["SpellDuration"], "ID")
    interrupts = default_rows(tables["SpellInterrupts"], "SpellID")
    names = {int(row["ID"]): row["Name_lang"] for row in tables["SpellName"]}
    classes = default_rows(tables["SpellClassOptions"], "SpellID")
    abilities = defaultdict(list)
    for row in tables["SkillLineAbility"]:
        abilities[int(row["Spell"])].append(row)
    effects = defaultdict(list)
    for row in tables["SpellEffect"]:
        if int(row["DifficultyID"]) == 0:
            effects[int(row["SpellID"])].append(row)
    included, excluded, builders = [], [], {}
    for spell_id, rows in sorted(effects.items()):
        awarded = sum(float(row["EffectBasePointsF"]) for row in rows if int(row["Effect"]) == 30 and int(row["EffectMiscValue_0"]) == 4)
        if awarded > 0 and spell_id in abilities:
            builders[spell_id] = awarded
        periodic = [row for row in rows if int(row["EffectAura"]) in (3, 53, 89, 23, 227)]
        if not periodic:
            continue
        info = misc.get(spell_id)
        channel = interrupts.get(spell_id, {})
        duration = durations.get(int(info["DurationIndex"]), {}) if info else {}
        record = {"id": spell_id, "name": names.get(spell_id, ""), "effects": [int(row["ID"]) for row in sorted(periodic, key=lambda row: int(row["ID"]))]}
        reason = None
        if not info:
            reason = "missing-spell-metadata"
        elif int(info["Attributes_1"]) & 0x44 or any(int(channel.get(key, 0)) for key in ("ChannelInterruptFlags_0", "ChannelInterruptFlags_1")):
            reason = "channel"
        elif int(info["Attributes_0"]) & 0x40:
            reason = "passive"
        elif spell_id not in abilities:
            reason = "not-a-skill-line-ability"
        elif len(periodic) != 1:
            reason = "multiple-periodic-effects"
        elif int(periodic[0]["EffectAura"]) not in (3, 53):
            reason = "triggered-or-percent-periodic-effect"
        elif int(periodic[0]["Effect"]) != 6 or int(periodic[0]["ImplicitTarget_0"]) != 6 or int(periodic[0]["ImplicitTarget_1"]) != 0:
            reason = "not-a-direct-enemy-debuff"
        elif int(duration.get("Duration", 0)) <= 0 or int(periodic[0]["EffectAuraPeriod"]) <= 0:
            reason = "missing-finite-duration-or-period"
        if reason:
            excluded.append({**record, "reason": reason})
            continue
        effect = periodic[0]
        class_mask = 0
        for ability in abilities[spell_id]:
            class_mask |= int(ability["ClassMask"])
        included.append({**record, "school": int(info["SchoolMask"]), "classMask": class_mask,
            "durationMs": int(duration["Duration"]), "maxDurationMs": int(duration["MaxDuration"]),
            "durationPerResourceMs": int(duration["DurationPerResource"]),
            "periodMs": int(effect["EffectAuraPeriod"]), "aura": int(effect["EffectAura"]),
            "basePoints": float(effect["EffectBasePointsF"]),
            "pointsPerResource": float(effect["EffectPointsPerResource"]),
            "spellPowerCoefficient": float(effect["EffectBonusCoefficient"]),
            "attackPowerCoefficient": float(effect["BonusCoefficientFromAP"]),
            "pointsPerLevel": float(effect["EffectRealPointsPerLevel"]),
            "projectile": float(info["Speed"]) > 0 or float(info["LaunchDelay"]) > 0,
            "supercedes": sorted({int(row["SupercedesSpell"]) for row in abilities[spell_id]} - {0})})
    if not included:
        raise ValueError("no supported DoTs found")
    families = defaultdict(list)
    for spell in included:
        row = classes.get(spell["id"], {})
        masks = tuple(int(row.get(f"SpellClassMask_{index}", 0)) for index in range(4))
        key = (int(row.get("SpellClassSet", 0)), *masks, spell["school"], spell["aura"]) if any(masks) else (spell["id"],)
        families[key].append(spell)
    for family in families.values():
        family_id = min(spell["id"] for spell in family)
        for spell in family:
            spell["family"] = family_id
    finishers = sorted({int(row["SpellID"]) for row in tables["SpellPower"]
        if int(row["PowerType"]) == 4 and int(row["ManaCost"]) > 0 and int(row["SpellID"]) in abilities})
    return {**pin, "included": included, "excluded": excluded, "builders": builders, "finishers": finishers}


def lua_catalog(report):
    lines = ["local _, ns = ...", "", "ns.DotCatalog = {", f'\tbuild = "{report["build"]}",',
        f'\tinterface = {report["interface"]},', f'\tuiCommit = "{report["uiCommit"]}",', "\tspells = {"]
    for spell in report["included"]:
        fields = []
        for key in ("family", "school", "classMask", "durationMs", "maxDurationMs", "durationPerResourceMs", "periodMs", "aura", "basePoints", "pointsPerResource", "spellPowerCoefficient", "attackPowerCoefficient", "pointsPerLevel"):
            fields.append(f"{key} = {spell[key]:.12g}")
        fields.append("projectile = " + ("true" if spell["projectile"] else "false"))
        fields.append("supercedes = { " + ", ".join(map(str, spell["supercedes"])) + " }")
        lines.append(f'\t\t[{spell["id"]}] = {{ ' + ", ".join(fields) + " },")
    lines.extend(["\t},", "\tbuilders = {"])
    for spell_id, points in sorted(report["builders"].items()):
        lines.append(f"\t\t[{spell_id}] = {points:.12g},")
    lines.extend(["\t},", "\tfinishers = {"])
    for spell_id in report["finishers"]:
        lines.append(f"\t\t[{spell_id}] = true,")
    return "\n".join(lines + ["\t},", "}", ""])


def main():
    global CACHE
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--check-pin", action="store_true")
    parser.add_argument("--source", type=Path, default=ROOT / "examples/wow-ui-source-forever")
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()
    CACHE = args.cache.resolve()
    if args.update and (args.check or args.fetch or args.check_pin):
        parser.error("--update cannot be combined with validation or --fetch")
    if args.check_pin and (args.check or args.fetch):
        parser.error("--check-pin cannot be combined with --check or --fetch")
    pin = pinned_source()
    if args.source.exists():
        version = (args.source / "version.txt").read_text().strip()
        commit = subprocess.check_output(["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip()
        if version != pin["build"] or commit != pin["uiCommit"]:
            raise ValueError("local Forever UI checkout does not match the workflow pin")
    if args.update:
        tables, manifest, compressed = download(pin, args.source)
    else:
        manifest = read_manifest(pin)
        if args.check_pin:
            output = OUTPUT.read_text()
            for key, value in pin.items():
                expected = f'{key} = "{value}"' if isinstance(value, str) else f"{key} = {value}"
                if expected not in output:
                    raise ValueError(f"generated catalogue {key} does not match the source pin")
            fixture = json.loads(FIXTURE.read_text())
            if any(fixture[key] != value for key, value in pin.items()):
                raise ValueError("spell fixtures do not match the source pin")
            print(f'Forever {pin["build"]}: catalogue and fixture pins verified')
            return
        if args.fetch:
            tables, fetched, compressed = download(pin)
            if fetched != manifest:
                raise ValueError("downloaded tables do not match the committed checksums; review with --update")
            write_cache(pin, compressed)
        else:
            tables, manifest = read_snapshot(pin)
    validate_evidence(tables)
    report = compile_catalog(tables, pin)
    audit = CACHE / pin["build"] / "catalog.json"
    artifacts = {OUTPUT: lua_catalog(report), FIXTURE: canonical(fixture_data(tables, pin))}
    if args.check:
        for path, expected in artifacts.items():
            if not path.exists() or path.read_text() != expected:
                raise ValueError(f"stale generated artifact: {path.relative_to(ROOT)}")
    else:
        if args.update:
            DATA.mkdir(parents=True, exist_ok=True)
            write_cache(pin, compressed)
            (DATA / "manifest.json").write_text(canonical(manifest))
        for path, content in artifacts.items():
            path.write_text(content)
    audit.write_text(canonical(report))
    print(f'Forever {pin["build"]}: {len(report["included"])} DoT ranks, {len(report["excluded"])} exclusions')


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
