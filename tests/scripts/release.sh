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
cp "$repo_dir/LICENSE" "$repo_dir/.gitignore" "$fixture/"
cp "$repo_dir/scripts/release.sh" "$repo_dir/scripts/validate-release.lua" \
	"$repo_dir/scripts/build-info.sh" "$repo_dir/scripts/build-dev.sh" \
	"$repo_dir/scripts/publish-curseforge.sh" "$repo_dir/scripts/test-tag.sh" "$fixture/scripts/"
cp "$repo_dir/tests/fixtures/stub-runner/run-tests.sh" "$fixture/scripts/"
mkdir -p "$fixture/tests"
cp "$repo_dir/tests/fixtures/stub-runner/pass" "$fixture/tests/marker"
cd "$fixture"
git init -q
git config user.name 'Release test'
git config user.email 'release-test@example.invalid'
# Libraries are separate build inputs, as in the real repo.
git add .gitignore LICENSE scripts tests UnitFrames UnitFrames_Workbench UnitFrames_Media UnitFrames_ClickGrid
git reset -q -- UnitFrames/Libs UnitFrames_Media/Libs
git -c core.hooksPath=/dev/null commit -qm 'Release fixture'
git tag v0.0.0-beta.1
git tag 1.0.0

# Development staging uses HEAD, includes local edits, and leaves source TOCs alone.
bash scripts/build-dev.sh "$release_test_tmp/dev-clean" >/dev/null
dev_commit="$(git rev-parse HEAD)"
dev_version="dev-$(git rev-parse --short=12 HEAD)"
luajit scripts/validate-release.lua "$release_test_tmp/dev-clean" "$dev_version" development "$dev_commit" >/dev/null
git diff --exit-code
if bash scripts/build-dev.sh "$release_test_tmp/dev-clean" >/dev/null 2>&1; then
	echo 'Development build overwrote an existing directory.' >&2; exit 1
fi

# Dirty and untracked runtime files must not leak into the tagged archive.
cp scripts/release.sh UnitFrames/untracked.sh
printf '\n-- Local development changes\n' >> UnitFrames/Core/Init.lua
cp "$repo_dir/tests/fixtures/stub-runner/fail" tests/marker
bash scripts/build-dev.sh "$release_test_tmp/dev-dirty" >/dev/null
luajit scripts/validate-release.lua "$release_test_tmp/dev-dirty" "$dev_version-dirty" development "$dev_commit" >/dev/null
cmp UnitFrames/Core/Init.lua "$release_test_tmp/dev-dirty/UnitFrames/Core/Init.lua"
# Release provenance must come from the tag even when HEAD has moved on.
git -c core.hooksPath=/dev/null commit --allow-empty -qm 'Move HEAD beyond the release tags'
# Recovery must test tagged code, excluding dirty working files.
export HOOK_TEST_LOG="$release_test_tmp/tag-test-runs"
bash scripts/test-tag.sh 1.0.0
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 1 ]]
[[ ! -e "$(< "$HOOK_TEST_LOG")" ]]
bash scripts/release.sh v0.0.0-beta.1 "$release_test_tmp/output" >/dev/null
archive="$release_test_tmp/output/UnitFrames-v0.0.0-beta.1.zip"
unzip -tq "$archive" >/dev/null
mkdir -p "$release_test_tmp/unpacked"
unzip -q "$archive" -d "$release_test_tmp/unpacked"
[[ "$(find "$release_test_tmp/unpacked" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 4 ]]
[[ ! -e "$release_test_tmp/unpacked/UnitFrames/untracked.sh" ]]
cmp "$release_test_tmp/unpacked/UnitFrames/Core/Init.lua" <(git show v0.0.0-beta.1:UnitFrames/Core/Init.lua)
cp LICENSE "$release_test_tmp/unpacked/"
luajit scripts/validate-release.lua "$release_test_tmp/unpacked" 0.0.0-beta.1 release "$dev_commit" >/dev/null
(
	cd "$release_test_tmp/output"
	sha256sum --check UnitFrames-v0.0.0-beta.1.zip.sha256 >/dev/null
)

# Plain version tags must build an installable archive too.
bash scripts/release.sh 1.0.0 "$release_test_tmp/plain" >/dev/null
unzip -q "$release_test_tmp/plain/UnitFrames-1.0.0.zip" -d "$release_test_tmp/plain-unpacked"
cp LICENSE "$release_test_tmp/plain-unpacked/"
luajit scripts/validate-release.lua "$release_test_tmp/plain-unpacked" 1.0.0 release "$dev_commit" >/dev/null

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
for tag in v0.0.0-alpha.1 v0.0.0 v0.0.0+build-metadata 1.0.0 1.0.0-alpha.1 1.0.0-beta.1; do
	metadata="$(bash scripts/publish-curseforge.sh --dry-run "$archive" "$tag")"
	case "$tag" in *alpha*) expected=alpha ;; *beta*) expected=beta ;; *) expected=release ;; esac
	jq -e --arg type "$expected" '.releaseType == $type' <<< "$metadata" >/dev/null
done
if CF_GAME_VERSION_IDS='1,garbage' bash scripts/publish-curseforge.sh --dry-run "$archive" v0.0.0 >/dev/null 2>&1; then
	echo 'Uploader accepted an invalid game-version list.' >&2; exit 1
fi
metadata="$(CF_PRERELEASE=true bash scripts/publish-curseforge.sh --dry-run "$archive" v0.0.0)"
jq -e '.releaseType == "beta"' <<< "$metadata" >/dev/null

# Verify the real upload path and version guard with an offline transport.
mkdir -p "$release_test_tmp/bin"
cp "$repo_dir/tests/fixtures/release/curl" "$release_test_tmp/bin/curl"
chmod +x "$release_test_tmp/bin/curl"
export PATH="$release_test_tmp/bin:$PATH" CF_API_TOKEN=offline-test-token
export CF_TEST_UPLOAD_LOG="$release_test_tmp/uploads" CF_TEST_METADATA="$release_test_tmp/metadata.json"
[[ "$(bash scripts/publish-curseforge.sh "$archive" v0.0.0)" == 42 ]]
jq -e '.changelog == "Quoted \"notes\"\nsecond line" and .releaseType == "release"' "$CF_TEST_METADATA" >/dev/null
if CF_TEST_MISSING_VERSION=true bash scripts/publish-curseforge.sh "$archive" v0.0.0 >/dev/null 2>&1; then
	echo 'Uploader ignored a missing game-version ID.' >&2; exit 1
fi
[[ "$(wc -l < "$CF_TEST_UPLOAD_LOG")" -eq 1 ]]
if CF_TEST_UPLOAD_FAIL=true bash scripts/publish-curseforge.sh "$archive" v0.0.0 >/dev/null 2>&1; then
	echo 'Uploader ignored a failed upload.' >&2; exit 1
fi
[[ "$(wc -l < "$CF_TEST_UPLOAD_LOG")" -eq 2 ]]
echo 'Release packaging and CurseForge metadata checks passed.'
