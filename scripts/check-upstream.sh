#!/usr/bin/env bash
# Reports whether the pinned Blizzard source and embedded libraries match upstream.
#
# Usage:
#   bash scripts/check-upstream.sh
#
# Reads the wow-ui-source pin from .github/workflows/tests.yml and the library
# commits from scripts/setup-test-libs.sh (the tracked pins CI and releases
# build from); asks upstream with plain git. LibSharedMedia comes from WowAce
# SVN and is not checked.
# In GitHub Actions it also writes step outputs (source_behind, source_latest,
# libs_behind, libs_report) and the job summary. Always exits 0 on a completed check.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libs="$repo_dir/scripts/setup-test-libs.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

die() { echo "error: $*" >&2; exit 1; }

source_pin() {
	awk '/repository: Gethe\/wow-ui-source/ { found = 1; next } found && /ref:/ { print $2; exit }' \
		"$repo_dir/.github/workflows/tests.yml"
}

library_pin() {
	sed -n "s|^fetch_tree $1 \([0-9a-f]*\) .*|\1|p" "$libs"
}

# The newest numeric release tag and its commit: "<tag> <sha>".
latest_release() {
	local refs tag sha
	refs="$(git ls-remote --tags "$1")"
	tag="$(sed -n 's|.*refs/tags/\([0-9][0-9.]*\)$|\1|p' <<<"$refs" | sort -V | tail -n 1)"
	[[ -n "$tag" ]] || die "no release tags in $1"
	sha="$(awk -v ref="refs/tags/$tag^{}" '$2 == ref { print $1 }' <<<"$refs")"
	[[ -n "$sha" ]] || sha="$(awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }' <<<"$refs")"
	echo "$tag $sha"
}

pinned_source="$(source_pin)"
[[ -n "$pinned_source" ]] || die "no Gethe/wow-ui-source ref in tests.yml"
latest_source="$(git ls-remote https://github.com/Gethe/wow-ui-source.git refs/heads/forever | cut -f1)"
[[ -n "$latest_source" ]] || die "cannot read the forever branch of Gethe/wow-ui-source"

pinned_ouf="$(library_pin oUF-wow/oUF)"
pinned_lem="$(library_pin p3lim-wow/LibEditMode)"
pinned_ace="$(library_pin WoWUIDev/Ace3)"
[[ -n "$pinned_ouf" && -n "$pinned_lem" && -n "$pinned_ace" ]] || die "cannot read library pins from $libs"
ouf_release="$(latest_release https://github.com/oUF-wow/oUF.git)"
lem_release="$(latest_release https://github.com/p3lim-wow/LibEditMode.git)"
read -r ouf_tag latest_ouf <<<"$ouf_release"
read -r lem_tag latest_lem <<<"$lem_release"
git clone -q --bare --filter=blob:none --single-branch --branch master https://github.com/WoWUIDev/Ace3.git "$tmp/Ace3"
git -C "$tmp/Ace3" cat-file -e "$pinned_ace^{commit}" 2>/dev/null || die "pinned Ace3 commit $pinned_ace is not on master"
latest_ace="$(git -C "$tmp/Ace3" rev-parse HEAD)"
ace_changes="$(git -C "$tmp/Ace3" rev-list --count "$pinned_ace..HEAD" -- LibStub CallbackHandler-1.0 AceDB-3.0)"

source_behind=false
[[ "$pinned_source" == "$latest_source" ]] || source_behind=true
report=()
status() { [[ "$1" == "$2" ]] && echo "current" || echo "behind"; }
report+=("| oUF | \`${pinned_ouf:0:7}\` | \`$ouf_tag\` @ \`${latest_ouf:0:7}\` | $(status "$pinned_ouf" "$latest_ouf") |")
report+=("| LibEditMode | \`${pinned_lem:0:7}\` | \`$lem_tag\` @ \`${latest_lem:0:7}\` | $(status "$pinned_lem" "$latest_lem") |")
ace_status=current
[[ "$ace_changes" == 0 ]] || ace_status="behind ($ace_changes library commits)"
report+=("| Ace3 (LibStub, CallbackHandler, AceDB) | \`${pinned_ace:0:7}\` | \`master\` @ \`${latest_ace:0:7}\` | $ace_status |")
libs_behind=false
for line in "${report[@]}"; do
	if [[ "$line" != *"| current |" ]]; then libs_behind=true; fi
done

table="| Dependency | Pinned | Upstream | Status |
|---|---|---|---|
| wow-ui-source (Forever) | \`${pinned_source:0:8}\` | \`${latest_source:0:8}\` | $(status "$pinned_source" "$latest_source") |
$(printf '%s\n' "${report[@]}")"
echo "$table"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	{
		echo "source_behind=$source_behind"
		echo "source_latest=$latest_source"
		echo "libs_behind=$libs_behind"
		echo "libs_report<<UPSTREAM_REPORT"
		printf '| Library | Pinned | Upstream | Status |\n|---|---|---|---|\n'
		printf '%s\n' "${report[@]}"
		echo "UPSTREAM_REPORT"
	} >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	printf '## Upstream drift\n\n%s\n' "$table" >> "$GITHUB_STEP_SUMMARY"
fi
