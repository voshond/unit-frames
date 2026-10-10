#!/usr/bin/env bash
# Install / reinstall the addon into the WoW Forever beta client.
#
# Usage:
#   scripts/install.sh              # remove old copy, copy fresh build into AddOns/
#   scripts/install.sh --link       # remove old copy, symlink AddOns/<name> -> repo (live editing, just /reload)
#   scripts/install.sh --uninstall  # remove the addon from AddOns/ (SavedVariables in WTF/ are kept)
#
# Environment overrides:
#   WOW_DIR     WoW client dir (default: Forever beta under Faugus/battlenet)
#   ADDON_NAME  addon folder name (default: derived from the .toc in the repo root)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WOW_DIR="${WOW_DIR:-/mnt/data02/Games/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_}"
ADDONS_DIR="$WOW_DIR/Interface/AddOns"

# Repo files that are not part of the shipped addon
EXCLUDES=(
	.git .github .claude docs scripts
	.gitattributes .gitignore .editorconfig .luacheckrc .pkgmeta
	'*.md'
)

die() { echo "error: $*" >&2; exit 1; }

detect_addon_name() {
	shopt -s nullglob
	local tocs=("$REPO_DIR"/*.toc)
	shopt -u nullglob
	[[ ${#tocs[@]} -gt 0 ]] || die "no .toc file in $REPO_DIR (set ADDON_NAME or add <Name>.toc)"
	local name
	name="$(basename "${tocs[0]}" .toc)"
	# Strip flavor suffixes like _Mainline / _Camelot / _Forever
	local suffix
	for suffix in _Mainline _Camelot _Forever _Standard _Vanilla _Classic; do
		name="${name%"$suffix"}"
	done
	echo "$name"
}

remove_existing() {
	local target="$1"
	if [[ -L "$target" ]]; then
		rm "$target"
	elif [[ -d "$target" ]]; then
		rm -rf -- "$target"
	elif [[ -e "$target" ]]; then
		die "$target exists but is not a directory or symlink, refusing to touch it"
	else
		return 1
	fi
}

mode="copy"
case "${1:-}" in
	"") ;;
	--link) mode="link" ;;
	--uninstall) mode="uninstall" ;;
	-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
	*) die "unknown option: $1 (see --help)" ;;
esac

[[ -d "$WOW_DIR" ]] || die "WoW dir not found: $WOW_DIR"
mkdir -p "$ADDONS_DIR"

ADDON_NAME="${ADDON_NAME:-$(detect_addon_name)}"
[[ -n "$ADDON_NAME" && "$ADDON_NAME" != */* && "$ADDON_NAME" != .* ]] || die "invalid ADDON_NAME: '$ADDON_NAME'"
TARGET="$ADDONS_DIR/$ADDON_NAME"

if remove_existing "$TARGET"; then
	echo "removed  $TARGET"
fi

case "$mode" in
	uninstall)
		echo "uninstalled $ADDON_NAME"
		;;
	link)
		ln -s "$REPO_DIR" "$TARGET"
		echo "linked   $TARGET -> $REPO_DIR"
		;;
	copy)
		rsync_args=(-a)
		for e in "${EXCLUDES[@]}"; do rsync_args+=(--exclude "$e"); done
		rsync "${rsync_args[@]}" "$REPO_DIR/" "$TARGET/"
		echo "copied   $REPO_DIR -> $TARGET"
		;;
esac

[[ "$mode" == "uninstall" ]] || echo "done. In game: /reload (or restart the client if you added new files to the .toc)"
