#!/usr/bin/env bash
# Test the exact tagged files using the current test launcher and local libraries.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
tag="${1:?Version tag required}"
[[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || exit 1
git rev-parse --verify "refs/tags/$tag^{commit}" >/dev/null
tag_tests_tmp="$(mktemp -d)"
trap 'rm -rf -- "$tag_tests_tmp"' EXIT
git archive "refs/tags/$tag" | tar -x -C "$tag_tests_tmp"
for addon in UnitFrames UnitFrames_Media; do
	if [[ ! -e "$tag_tests_tmp/$addon/Libs" && -d "$repo_dir/$addon/Libs" ]]; then
		cp -a "$repo_dir/$addon/Libs" "$tag_tests_tmp/$addon/Libs"
	fi
done
# Reuse the fetched wow-ui-testing library; fetch-wut.sh replaces it if the tag pins another.
if [[ -d "$repo_dir/.wut" && -f "$tag_tests_tmp/.wut-version" ]]; then
	cp -a "$repo_dir/.wut" "$tag_tests_tmp/.wut"
fi
bash "$repo_dir/scripts/run-tests.sh" "$tag_tests_tmp"

