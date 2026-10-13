#!/usr/bin/env bash
# Shared entry point for CI, release tests and manual verification.
#   bash scripts/run-tests.sh [--times] [-j [N]] [repository directory]
#   --times   report how long the release check and each spec file took
#   -j [N]    run spec files in N parallel processes (default: one per CPU)
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_args=()
times=
target=
while [[ $# -gt 0 ]]; do
	case "$1" in
		--times) times=1; runner_args+=(--times) ;;
		-j|--jobs)
			runner_args+=(-j)
			if [[ "${2:-}" =~ ^[0-9]+$ ]]; then runner_args+=("$2"); shift; fi
			;;
		-*) echo "Unknown option: $1" >&2; exit 2 ;;
		*) target="$1" ;;
	esac
	shift
done
cd "${target:-$repo_dir}"
if ! command -v luajit >/dev/null; then
	echo 'LuaJIT is required to run tests. Install luajit and retry.' >&2
	exit 1
fi
if [[ ! -f UnitFrames/Libs/LibStub/LibStub.lua || ! -f UnitFrames_Media/Libs/LibStub/LibStub.lua ]]; then
	echo 'Test libraries are missing. See DEVELOPMENT.md; on a fresh checkout, run bash scripts/setup-test-libs.sh.' >&2
	exit 1
fi
if [[ -f tests/scripts/release.sh ]]; then
	started=$SECONDS
	bash tests/scripts/release.sh
	if [[ -n "$times" ]]; then echo "Release check: $((SECONDS - started))s"; fi
fi
exec luajit tests/run.lua ${runner_args[@]+"${runner_args[@]}"}
