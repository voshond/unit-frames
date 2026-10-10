#!/usr/bin/env bash
# Install / reinstall the addons into the WoW Forever beta client.
#
# Every top-level folder <Name>/ that contains <Name>.toc is an addon
# (UnitFrames, UnitFrames_Workbench, ...).
#
# Usage:
#   scripts/install.sh [addon...]              # remove old copies, copy fresh ones into AddOns/
#   scripts/install.sh --link [addon...]       # remove old copies, symlink AddOns/<name> -> repo folder
#   scripts/install.sh --uninstall [addon...]  # remove from AddOns/ (SavedVariables in WTF/ are kept)
#
# Without addon names, all addons in the repo are handled.
#
# Environment overrides:
#   WOW_DIR     WoW client dir (default: Forever beta under Faugus/battlenet)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WOW_DIR="${WOW_DIR:-/mnt/data02/Games/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_}"
ADDONS_DIR="$WOW_DIR/Interface/AddOns"

die() { echo "error: $*" >&2; exit 1; }

repo_addons() {
	local dir name
	for dir in "$REPO_DIR"/*/; do
		name="$(basename "$dir")"
		[[ -f "$dir/$name.toc" ]] && echo "$name"
	done
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
	--link) mode="link"; shift ;;
	--uninstall) mode="uninstall"; shift ;;
	-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
	-*) die "unknown option: $1 (see --help)" ;;
esac

[[ -d "$WOW_DIR" ]] || die "WoW dir not found: $WOW_DIR"
mkdir -p "$ADDONS_DIR"

mapfile -t available < <(repo_addons)
[[ ${#available[@]} -gt 0 ]] || die "no addon folders (<Name>/<Name>.toc) in $REPO_DIR"
if [[ $# -gt 0 ]]; then
	addons=("$@")
else
	addons=("${available[@]}")
fi

for name in "${addons[@]}"; do
	[[ -n "$name" && "$name" != */* && "$name" != .* ]] || die "invalid addon name: '$name'"
	[[ " ${available[*]} " == *" $name "* ]] || die "unknown addon '$name' (available: ${available[*]})"
	source_dir="$REPO_DIR/$name"
	target="$ADDONS_DIR/$name"

	if remove_existing "$target"; then
		echo "removed  $target"
	fi
	case "$mode" in
		uninstall)
			echo "uninstalled $name"
			;;
		link)
			ln -s "$source_dir" "$target"
			echo "linked   $target -> $source_dir"
			;;
		copy)
			rsync -a "$source_dir/" "$target/"
			echo "copied   $name"
			;;
	esac
done

[[ "$mode" == "uninstall" ]] || echo "done. In game: /reload (restart the client if you added new files to a .toc)"
