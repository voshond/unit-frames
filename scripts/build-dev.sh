#!/usr/bin/env bash
# Stage current working files and dependencies with a commit-based dev version.
# Usage: bash scripts/build-dev.sh [new-output-directory]
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/build-info.sh"
dev_build_info
if [[ $# -gt 0 ]]; then
	# Refuse existing destinations; never merge a dev build into source or a client.
	mkdir -- "$1"
	output_dir="$(cd "$1" && pwd)"
else
	mkdir -p "$repo_dir/.build"
	output_dir="$(mktemp -d "$repo_dir/.build/$build_version.XXXXXX")"
fi
addons=(UnitFrames UnitFrames_Workbench UnitFrames_Media UnitFrames_ClickGrid)
for addon in "${addons[@]}"; do
	cp -a "$repo_dir/$addon" "$output_dir/"
done
stamp_build_info "$output_dir" "$build_version" development "$build_commit" "${addons[@]}"
cp "$repo_dir/LICENSE" "$output_dir/"
luajit "$repo_dir/scripts/validate-release.lua" "$output_dir" "$build_version" development "$build_commit"
echo "Built $build_version in $output_dir"
