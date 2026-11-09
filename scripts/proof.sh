#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ ! -f UnitFrames/Libs/LibStub/LibStub.lua ]]; then
	echo 'Test libraries are missing. Run bash scripts/setup-test-libs.sh first.' >&2
	exit 1
fi
command -v rsvg-convert >/dev/null || echo 'rsvg-convert not found: writing SVG only.' >&2
command -v magick >/dev/null || command -v convert >/dev/null \
	|| echo 'ImageMagick not found: addon textures render as placeholders.' >&2
exec luajit tests/proof/run.lua "$@"
