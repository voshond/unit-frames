import argparse
import csv
import gzip
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

from spell_catalog import canonical, digest, pinned_source, validate_download


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/forever-atlases"
CACHE = ROOT / "examples/forever-atlases"
OUTPUT = ROOT / "tests/proof/atlases.lua"
SOURCE_GLOBS = ("UnitFrames*/**/*.lua", "UnitFrames/Libs/oUF/elements/*.lua")
TABLES = {
    "UiTextureAtlas": {"ID", "FileDataID", "AtlasWidth", "AtlasHeight"},
    "UiTextureAtlasMember": {"ID", "CommittedName", "UiTextureAtlasID", "Width", "Height", "CommittedLeft", "CommittedRight", "CommittedTop", "CommittedBottom", "UiTextureAtlasElementID", "CommittedFlags"},
    "UiTextureAtlasElement": {"ID", "Name"},
}
TILES_VERTICALLY, TILES_HORIZONTALLY = 2, 4
LITERAL = re.compile(r"""(["'])([^"'\s\\]*-[^"'\s\\]*)\1""")
CONCATENATION = re.compile(r"""(["'])([^"'\s\\]+-)\1\s*\.\.\s*[\w.:\[\]()]+(?:\s*\.\.\s*(["'])([^"'\s\\]*)\3)?""")


def table_url(name, build):
    return f"https://wago.tools/db2/{name}/csv?build={build}&locale=enUS"


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


def download(pin):
    tables, records, compressed = {}, {}, {}
    for name in TABLES:
        url = table_url(name, pin["build"])
        with tempfile.TemporaryDirectory() as directory:
            headers = Path(directory) / "headers"
            raw = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "90", "--dump-header", str(headers), url])
            validate_download(name, pin["build"], headers.read_text())
        tables[name] = parse_table(name, raw)
        compressed[name] = gzip.compress(raw, mtime=0)
        records[name] = {"url": url, "filename": f"{name}.{pin['build']}.csv", "sha256": digest(raw), "rows": len(tables[name])}
        print(f"Fetched {name}: {len(tables[name])} records", file=sys.stderr)
    return tables, {"build": pin["build"], "format": 1, "tables": records}, compressed


def read_manifest(pin):
    manifest = json.loads((DATA / "manifest.json").read_text())
    if manifest.get("format") != 1 or manifest.get("build") != pin["build"]:
        raise ValueError("atlas snapshot does not match the pinned Forever build; run --update")
    if set(manifest["tables"]) != set(TABLES):
        raise ValueError("atlas snapshot table set changed; run --update")
    for name in TABLES:
        record = manifest["tables"][name]
        if record["url"] != table_url(name, pin["build"]) or record.get("filename") != f"{name}.{pin['build']}.csv":
            raise ValueError(f"{name}: source does not match the pinned build")
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


def source_files(root=ROOT):
    if not (root / "UnitFrames/Libs/oUF/elements").is_dir():
        raise ValueError("oUF is missing; run scripts/setup-test-libs.sh first")
    files = set()
    for pattern in SOURCE_GLOBS:
        for path in root.glob(pattern):
            relative = path.relative_to(root).as_posix()
            if "/Libs/" not in relative or relative.startswith("UnitFrames/Libs/oUF/elements/"):
                files.add(path)
    return sorted(files)


def atlas_uses(root=ROOT):
    literals, patterns = set(), set()
    for path in source_files(root):
        text = path.read_text(encoding="utf-8")
        if not re.search("atlas", text, re.I):
            continue
        literals.update(match[2].lower() for match in LITERAL.finditer(text))
        for match in CONCATENATION.finditer(text):
            patterns.add(re.escape(match[2].lower()) + r"[a-z]+" + re.escape((match[4] or "").lower()))
    return literals, re.compile("|".join(sorted(patterns))) if patterns else None


def preferred_member(members):
    def rank(member):
        name = member["CommittedName"].lower()
        return (name.endswith("-2x"), not name.endswith("-c60"), int(member["ID"]))
    return min(members, key=rank)


def compile_atlases(tables, root=ROOT):
    atlases = {row["ID"]: row for row in tables["UiTextureAtlas"]}
    members = defaultdict(list)
    for row in tables["UiTextureAtlasMember"]:
        members[row["UiTextureAtlasElementID"]].append(row)
    literals, pattern = atlas_uses(root)
    selected = {}
    for element in tables["UiTextureAtlasElement"]:
        name = element["Name"]
        lower = name.lower()
        if not members[element["ID"]] or (lower not in literals and not (pattern and pattern.fullmatch(lower))):
            continue
        member = preferred_member(members[element["ID"]])
        atlas = atlases[member["UiTextureAtlasID"]]
        width, height = int(atlas["AtlasWidth"]), int(atlas["AtlasHeight"])
        flags = int(member["CommittedFlags"])
        selected[name] = {
            "file": int(atlas["FileDataID"]),
            "width": int(member["Width"]),
            "height": int(member["Height"]),
            "left": int(member["CommittedLeft"]) / width,
            "right": int(member["CommittedRight"]) / width,
            "top": int(member["CommittedTop"]) / height,
            "bottom": int(member["CommittedBottom"]) / height,
            "tilesH": bool(flags & TILES_HORIZONTALLY),
            "tilesV": bool(flags & TILES_VERTICALLY),
        }
    if not selected:
        raise ValueError("no atlas used by the addon was found in the client tables")
    return selected


def lua_atlases(atlases, build):
    lines = ["return {", f'\tbuild = "{build}",', "\tatlases = {"]
    for name in sorted(atlases, key=str.lower):
        info = atlases[name]
        fields = [f'file = {info["file"]}', f'width = {info["width"]}', f'height = {info["height"]}']
        fields += [f"{key} = {info[key]:.12g}" for key in ("left", "right", "top", "bottom")]
        fields += [f'{key} = {"true" if info[key] else "false"}' for key in ("tilesH", "tilesV")]
        lines.append(f'\t\t["{name}"] = {{ ' + ", ".join(fields) + " },")
    return "\n".join(lines + ["\t},", "}", ""])


def main():
    global CACHE
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--check-pin", action="store_true")
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()
    CACHE = args.cache.resolve()
    if args.update and (args.check or args.fetch or args.check_pin):
        parser.error("--update cannot be combined with validation or --fetch")
    if args.check_pin and (args.check or args.fetch):
        parser.error("--check-pin cannot be combined with --check or --fetch")
    pin = pinned_source()
    if args.update:
        tables, manifest, compressed = download(pin)
    else:
        manifest = read_manifest(pin)
        if args.check_pin:
            if f'build = "{pin["build"]}"' not in OUTPUT.read_text():
                raise ValueError("generated atlas table build does not match the source pin")
            print(f'Forever {pin["build"]}: atlas table pin verified')
            return
        if args.fetch:
            tables, fetched, compressed = download(pin)
            if fetched != manifest:
                raise ValueError("downloaded tables do not match the committed checksums; review with --update")
            write_cache(pin, compressed)
        else:
            tables, manifest = read_snapshot(pin)
    atlases = compile_atlases(tables)
    output = lua_atlases(atlases, pin["build"])
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != output:
            raise ValueError(f"stale generated artifact: {OUTPUT.relative_to(ROOT)}")
    else:
        if args.update:
            DATA.mkdir(parents=True, exist_ok=True)
            write_cache(pin, compressed)
            (DATA / "manifest.json").write_text(canonical(manifest))
        OUTPUT.write_text(output)
    print(f'Forever {pin["build"]}: {len(atlases)} atlases')


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
