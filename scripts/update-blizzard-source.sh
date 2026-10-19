#!/usr/bin/env bash
# Pins tests and releases to a wow-ui-source Forever commit, syncs the local
# Blizzard source checkout to it and regenerates the API snapshot.
#
# Usage:
#   bash scripts/update-blizzard-source.sh [commit]
#
# commit: a full SHA (default: the newest commit of the forever branch).
# SOURCE_DIR overrides the checkout (default: examples/wow-ui-source-forever).
# An existing folder that is not a git checkout is never replaced.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${SOURCE_DIR:-$repo_dir/examples/wow-ui-source-forever}"
url=https://github.com/Gethe/wow-ui-source.git

die() { echo "error: $*" >&2; exit 1; }

commit="${1:-$(git ls-remote "$url" refs/heads/forever | cut -f1)}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "expected a full commit SHA, got '$commit'"
if [[ -e "$source_dir" && ! -d "$source_dir/.git" ]]; then
	die "$source_dir is not a git checkout; move it aside once and rerun"
fi
if [[ ! -d "$source_dir/.git" ]]; then
	git init -q "$source_dir"
	git -C "$source_dir" remote add origin "$url"
fi
git -C "$source_dir" fetch -q --depth 1 origin "$commit"
git -C "$source_dir" checkout -q --detach FETCH_HEAD
version="$(tr -d '[:space:]' < "$source_dir/version.txt")"

for workflow in tests release; do
	sed -i -E "/repository: Gethe\/wow-ui-source/,/ref:/ s|ref: [0-9a-f]{40}( # .*)?$|ref: $commit # Forever $version|" \
		"$repo_dir/.github/workflows/$workflow.yml"
done
(cd "$repo_dir" && luajit scripts/api-snapshot.lua "$source_dir")
python3 -B "$repo_dir/scripts/spell_catalog.py" --update --source "$source_dir"
echo "Pinned wow-ui-source $commit (Forever $version)"
