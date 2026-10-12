#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
existing="$(git config --get core.hooksPath || true)"
if [[ -n "$existing" && "$existing" != .githooks ]]; then
	echo "Existing core.hooksPath is $existing; integrate .githooks/pre-push there instead of replacing it." >&2
	exit 1
fi
if [[ -z "$existing" && -e "$(git rev-parse --git-path hooks/pre-push)" ]]; then
	echo 'An existing pre-push hook was found. Integrate .githooks/pre-push there instead of replacing it.' >&2
	exit 1
fi
chmod +x .githooks/pre-push
git config --local core.hooksPath .githooks
echo 'Pre-push tests enabled for this checkout.'

