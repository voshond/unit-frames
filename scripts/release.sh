#!/usr/bin/env bash
# Package the exact tagged source with already-populated embedded libraries.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
tag="${1:?Usage: bash scripts/release.sh vX.Y.Z [output-directory]}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
	echo 'Expected a version tag such as v0.1.0 or v0.1.0-beta.1.' >&2
	exit 1
fi
git rev-parse --verify "refs/tags/$tag^{commit}" >/dev/null
version="${tag#v}"
output_dir="${2:-$repo_dir/.release}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
archive="$output_dir/UnitFrames-$tag.zip"
if [[ -e "$archive" || -e "$archive.sha256" ]]; then
	echo "Release artifact already exists: $archive" >&2
	exit 1
fi
for tool in git tar zip luajit sha256sum; do command -v "$tool" >/dev/null; done
for addon in UnitFrames UnitFrames_Media; do
	if [[ ! -f "$addon/Libs/LibStub/LibStub.lua" ]]; then
		echo 'Embedded libraries are missing. On a fresh checkout, run bash scripts/setup-test-libs.sh.' >&2
		exit 1
	fi
done

release_tmp="$(mktemp -d)"
trap 'rm -rf -- "$release_tmp"' EXIT
addons=(UnitFrames UnitFrames_Workbench UnitFrames_Media UnitFrames_ClickGrid)
# Only committed addon files from this tag are shipped; no working-tree extras.
git archive "refs/tags/$tag" LICENSE "${addons[@]}" | tar -x -C "$release_tmp"
for addon in UnitFrames UnitFrames_Media; do
	if [[ -e "$release_tmp/$addon/Libs" ]]; then
		echo "Tagged source already contains $addon/Libs; refusing to mix dependency sources." >&2
		exit 1
	fi
	cp -a "$repo_dir/$addon/Libs" "$release_tmp/$addon/Libs"
done
for addon in "${addons[@]}"; do
	sed -i -E "s/^## Version:.*/## Version: $version/" "$release_tmp/$addon/$addon.toc"
done
if [[ -n "$(find "$release_tmp" -type l -print -quit)" ]]; then
	echo 'Release bundles may not contain symlinks.' >&2
	exit 1
fi
luajit "$repo_dir/scripts/validate-release.lua" "$release_tmp" "$version"
(
	cd "$release_tmp"
	zip -Xqr "$release_tmp/bundle.zip" "${addons[@]}"
)
mv "$release_tmp/bundle.zip" "$archive"
(
	cd "$output_dir"
	sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)
echo "Built $archive"

