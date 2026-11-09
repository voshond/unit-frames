#!/usr/bin/env bash
# Install / reinstall the addons into the WoW Forever client.
#
# Every top-level folder <Name>/ that contains <Name>.toc is an addon
# (UnitFrames, UnitFrames_Workbench, ...).
#
# Usage:
#   scripts/install.sh [addon...]              # remove old copies, copy fresh ones into AddOns/
#   scripts/install.sh --link [addon...]       # remove old copies, symlink AddOns/<name> -> repo folder
#   scripts/install.sh --uninstall [addon...]  # remove from AddOns/ (SavedVariables in WTF/ are kept)
#   scripts/install.sh --host arch [addon...]  # the same on another machine over SSH (copy or --uninstall)
#
# Without addon names, all addons in the repo are handled. --host takes an
# SSH destination (a host alias from your SSH config, or user@host) with
# key-based login; WOW_DIR is then a path on that machine. --link needs the
# repo on the client machine, so it only works locally.
#
# Environment overrides:
#   WOW_DIR     WoW client dir (default: Forever under Faugus/battlenet)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WOW_DIR="${WOW_DIR:-/mnt/data02/Games/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}"
ADDONS_DIR="$WOW_DIR/Interface/AddOns"

die() { echo "error: $*" >&2; exit 1; }

HOST=""

# Runs a command here, or on $HOST over SSH with its arguments quoted.
on_target() {
	if [[ -n "$HOST" ]]; then
		ssh -o BatchMode=yes "$HOST" "$(printf '%q ' "$@")"
	else
		"$@"
	fi
}

where() {
	if [[ -n "$HOST" ]]; then echo "$HOST:$1"; else echo "$1"; fi
}

repo_addons() {
	local dir name
	for dir in "$REPO_DIR"/*/; do
		name="$(basename "$dir")"
		[[ -f "$dir/$name.toc" ]] && echo "$name"
	done
}

# Exit status: 0 removed, 1 nothing there, 2 something else is in the way.
REMOVE_SCRIPT='
if [[ -L "$1" ]]; then rm -- "$1"
elif [[ -d "$1" ]]; then rm -rf -- "$1"
elif [[ -e "$1" ]]; then exit 2
else exit 1
fi'

remove_existing() {
	local target="$1" result=0
	on_target bash -c "$REMOVE_SCRIPT" remove "$target" || result=$?
	case "$result" in
		0) return 0 ;;
		1) return 1 ;;
		2) die "$(where "$target") exists but is not a directory or symlink, refusing to touch it" ;;
		*) die "could not check $(where "$target") (exit $result)" ;;
	esac
}

mode="copy"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--link) mode="link"; shift ;;
		--uninstall) mode="uninstall"; shift ;;
		--host)
			[[ -n "${2:-}" && "$2" != -* ]] || die "--host needs an SSH destination, e.g. --host arch"
			HOST="$2"; shift 2 ;;
		-h|--help) sed -n '2,22p' "$0"; exit 0 ;;
		-*) die "unknown option: $1 (see --help)" ;;
		*) break ;;
	esac
done

[[ -z "$HOST" || "$mode" != "link" ]] || die "--link only works locally; use plain copies with --host"
if [[ -n "$HOST" ]]; then
	on_target true || die "cannot reach $HOST over SSH (key-based login is required)"
fi
on_target test -d "$WOW_DIR" || die "WoW dir not found: $(where "$WOW_DIR")"
on_target mkdir -p "$ADDONS_DIR"

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
		echo "removed  $(where "$target")"
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
			if [[ -n "$HOST" ]]; then
				# -s keeps the spaces and parentheses in the client path away from the remote shell.
				rsync -a -s -e "ssh -o BatchMode=yes" "$source_dir/" "$HOST:$target/"
			else
				rsync -a "$source_dir/" "$target/"
			fi
			echo "copied   $name -> $(where "$target")"
			;;
	esac
done

[[ "$mode" == "uninstall" ]] || echo "done. In game: /reload (restart the client if you added new files to a .toc)"
