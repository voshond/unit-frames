#!/usr/bin/env bash
set -euo pipefail
[[ -f "$1/tests/marker" ]]
printf '%s\n' "$1" >> "$HOOK_TEST_LOG"
[[ "$(< "$1/tests/marker")" == pass ]]

