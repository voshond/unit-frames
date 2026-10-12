#!/usr/bin/env bash
# Populate a fresh checkout with the existing libraries for tests and releases.
# Never replace a developer's library copies. No game installation is needed.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for destination in "$repo_dir/UnitFrames/Libs" "$repo_dir/UnitFrames_Media/Libs"; do
	if [[ -e "$destination" || -L "$destination" ]]; then
		echo "Already exists: $destination. Use a fresh checkout; existing libraries are not replaced." >&2
		exit 1
	fi
done

test_libs_tmp="$(mktemp -d)"
trap 'rm -rf -- "$test_libs_tmp"' EXIT

fetch_tree() {
	local repository="$1" revision="$2" destination="$3"
	mkdir -p "$destination"
	curl --fail --silent --show-error --location --retry 3 --max-time 120 \
		"https://codeload.github.com/$repository/tar.gz/$revision" -o "$test_libs_tmp/source.tar.gz"
	tar -xzf "$test_libs_tmp/source.tar.gz" -C "$destination" --strip-components=1 \
		--exclude='*/tests' --exclude='*/utils' --exclude='*/.*'
}

# Match the versions recorded in the existing local Libs/VERSIONS.md.
fetch_tree WoWUIDev/Ace3 40f4cc1356ae7fcc0cf71fc0a19dc7d50d6ae6c2 "$test_libs_tmp/ace3"
fetch_tree oUF-wow/oUF a1f9df774263d00e0feedca40200065f06e14eda "$test_libs_tmp/oUF"
fetch_tree p3lim-wow/LibEditMode 550a52e7a0a56649d962c3fa2ceccaf50c3c77ed "$test_libs_tmp/LibEditMode"
rm -f -- "$test_libs_tmp/oUF/oUF.toc" "$test_libs_tmp/LibEditMode/LibEditMode.toc"
sed -i 's/@project-version@/14.2.0/' "$test_libs_tmp/oUF/ouf.lua"

mkdir -p "$test_libs_tmp/LibSharedMedia-3.0"
lsm_source='https://repos.curseforge.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0'
for file in LibSharedMedia-3.0.lua lib.xml; do
	curl --fail --silent --show-error --location --retry 3 --max-time 120 \
		"$lsm_source/$file?p=176" -o "$test_libs_tmp/LibSharedMedia-3.0/$file"
done
(
	cd "$test_libs_tmp/LibSharedMedia-3.0"
	sha256sum --check <<'CHECKSUMS'
ea359e44eae4355c51a49a69960c878889ee26adac9d72d1362c22a3db6af6d0  LibSharedMedia-3.0.lua
bd4f30d101a13ffb915114f6cd2d510fee506bca333f35387b3e08f238d85f8c  lib.xml
CHECKSUMS
)

# Stage everything first, so failed downloads leave the checkout alone.
mkdir -p "$test_libs_tmp/core" "$test_libs_tmp/media"
for library in LibStub CallbackHandler-1.0 AceDB-3.0; do
	cp -a "$test_libs_tmp/ace3/$library" "$test_libs_tmp/core/"
done
for library in oUF LibEditMode LibSharedMedia-3.0; do
	cp -a "$test_libs_tmp/$library" "$test_libs_tmp/core/"
done
for library in LibStub CallbackHandler-1.0 LibSharedMedia-3.0; do
	cp -a "$test_libs_tmp/core/$library" "$test_libs_tmp/media/"
done
mv "$test_libs_tmp/core" "$repo_dir/UnitFrames/Libs"
mv "$test_libs_tmp/media" "$repo_dir/UnitFrames_Media/Libs"
echo 'Pinned test libraries installed. Existing game addons were not touched.'
