#!/usr/bin/env bash
# Build and inspect a real archive in a disposable tagged repository.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$release_test_tmp"' EXIT
fixture="$release_test_tmp/repo"
mkdir -p "$fixture/scripts"
for addon in UnitFrames UnitFrames_Workbench UnitFrames_Media UnitFrames_ClickGrid; do
	cp -a "$repo_dir/$addon" "$fixture/"
done
cp "$repo_dir/LICENSE" "$fixture/"
cp "$repo_dir/scripts/release.sh" "$repo_dir/scripts/validate-release.lua" \
	"$repo_dir/scripts/publish-curseforge.sh" "$fixture/scripts/"
cd "$fixture"
git init -q
git config user.name 'Release test'
git config user.email 'release-test@example.invalid'
# Libraries are separate build inputs, as in the real repo.
git add LICENSE scripts UnitFrames UnitFrames_Workbench UnitFrames_Media UnitFrames_ClickGrid
git reset -q -- UnitFrames/Libs UnitFrames_Media/Libs
git -c core.hooksPath=/dev/null commit -qm 'Release fixture'
git tag v0.0.0-beta.1

# Dirty and untracked runtime files must not leak into the tagged archive.
cp scripts/release.sh UnitFrames/untracked.sh
cp scripts/release.sh UnitFrames/Core/Init.lua
bash scripts/release.sh v0.0.0-beta.1 "$release_test_tmp/output" >/dev/null
archive="$release_test_tmp/output/UnitFrames-v0.0.0-beta.1.zip"
unzip -tq "$archive" >/dev/null
mkdir -p "$release_test_tmp/unpacked"
unzip -q "$archive" -d "$release_test_tmp/unpacked"
[[ "$(find "$release_test_tmp/unpacked" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 4 ]]
[[ ! -e "$release_test_tmp/unpacked/UnitFrames/untracked.sh" ]]
cmp "$release_test_tmp/unpacked/UnitFrames/Core/Init.lua" <(git show v0.0.0-beta.1:UnitFrames/Core/Init.lua)
cp LICENSE "$release_test_tmp/unpacked/"
luajit scripts/validate-release.lua "$release_test_tmp/unpacked" 0.0.0-beta.1 >/dev/null
(
	cd "$release_test_tmp/output"
	sha256sum --check UnitFrames-v0.0.0-beta.1.zip.sha256 >/dev/null
)

if bash scripts/release.sh v0.0.0-beta.1 "$release_test_tmp/output" >/dev/null 2>&1; then
	echo 'Release script overwrote an existing artifact.' >&2; exit 1
fi
if bash scripts/release.sh ../../invalid "$release_test_tmp/output" >/dev/null 2>&1; then
	echo 'Release script accepted an invalid version tag.' >&2; exit 1
fi
mv UnitFrames/Libs/LibStub/LibStub.lua "$release_test_tmp/LibStub.lua"
if bash scripts/release.sh v0.0.0-beta.1 "$release_test_tmp/missing-library" >/dev/null 2>&1; then
	echo 'Release script packaged a missing dependency.' >&2; exit 1
fi
mv "$release_test_tmp/LibStub.lua" UnitFrames/Libs/LibStub/LibStub.lua

# Missing transitive XML files or license notices must fail validation.
mv "$release_test_tmp/unpacked/UnitFrames/Libs/oUF/elements/health.lua" "$release_test_tmp/health.lua"
if luajit scripts/validate-release.lua "$release_test_tmp/unpacked" 0.0.0-beta.1 >/dev/null 2>&1; then
	echo 'Validator accepted a missing XML dependency.' >&2; exit 1
fi
mv "$release_test_tmp/health.lua" "$release_test_tmp/unpacked/UnitFrames/Libs/oUF/elements/health.lua"
mv "$release_test_tmp/unpacked/UnitFrames_Media/Fonts/RobotoCondensed-OFL.txt" "$release_test_tmp/OFL.txt"
if luajit scripts/validate-release.lua "$release_test_tmp/unpacked" 0.0.0-beta.1 >/dev/null 2>&1; then
	echo 'Validator accepted a missing font license.' >&2; exit 1
fi

export CF_PROJECT_ID=123 CF_GAME_VERSION_IDS=456,789
export CF_CHANGELOG=$'Quoted "notes"\nsecond line'
metadata="$(bash scripts/publish-curseforge.sh --dry-run "$archive" v0.0.0-beta.1)"
jq -e '.releaseType == "beta" and .gameVersions == [456,789] and .changelog == "Quoted \"notes\"\nsecond line"' <<< "$metadata" >/dev/null
for tag in v0.0.0-alpha.1 v0.0.0; do
	metadata="$(bash scripts/publish-curseforge.sh --dry-run "$archive" "$tag")"
	if [[ "$tag" == *alpha* ]]; then expected=alpha; else expected=release; fi
	jq -e --arg type "$expected" '.releaseType == $type' <<< "$metadata" >/dev/null
done
if CF_GAME_VERSION_IDS='1,garbage' bash scripts/publish-curseforge.sh --dry-run "$archive" v0.0.0 >/dev/null 2>&1; then
	echo 'Uploader accepted an invalid game-version list.' >&2; exit 1
fi
echo 'Release packaging and CurseForge metadata checks passed.'

