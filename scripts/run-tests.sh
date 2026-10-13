#!/usr/bin/env bash
# Shared entry point for CI, release tests and manual verification.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$repo_dir}"
if ! command -v luajit >/dev/null; then
	echo 'LuaJIT is required to run tests. Install luajit and retry.' >&2
	exit 1
fi
if [[ ! -f UnitFrames/Libs/LibStub/LibStub.lua || ! -f UnitFrames_Media/Libs/LibStub/LibStub.lua ]]; then
	echo 'Test libraries are missing. See DEVELOPMENT.md; on a fresh checkout, run bash scripts/setup-test-libs.sh.' >&2
	exit 1
fi
if [[ -f tests/scripts/release.sh ]]; then bash tests/scripts/release.sh; fi
exec luajit tests/run.lua
