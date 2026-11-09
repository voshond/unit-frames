#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/proof-publish.sh [--dry-run] [--out DIR] SCENARIO_FILTER...

Renders the UI proof scenarios whose names contain a filter, commits their
PNGs to the orphan `ui-proof` branch under <current branch>/ and prints
Markdown image links pinned to that commit, for a pull request body.

  --dry-run   create the commit locally but do not push it
  --out DIR   keep the rendered files in DIR (default: a temporary folder)
EOF
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

proof_branch=ui-proof
push=1
out_dir=
filters=()
while (($#)); do
	case "$1" in
		--dry-run) push=0 ;;
		--out) out_dir="$2"; shift ;;
		-h|--help) usage; exit 0 ;;
		*) filters+=("$1") ;;
	esac
	shift
done
if ((${#filters[@]} == 0)); then
	usage >&2
	exit 2
fi

branch="$(git symbolic-ref --short HEAD)"
head_sha="$(git rev-parse --short HEAD)"
slug="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if [[ -z "$out_dir" ]]; then
	out_dir="$(mktemp -d)"
	trap 'rm -rf "$out_dir"' EXIT
fi
mkdir -p "$out_dir"
rm -f "$out_dir"/*.png

UF_PROOF_DIR="$out_dir" bash scripts/proof.sh "${filters[@]}" >&2

shopt -s nullglob
pngs=("$out_dir"/*.png)
if ((${#pngs[@]} == 0)); then
	echo "No PNGs rendered for: ${filters[*]}" >&2
	exit 1
fi

parent=
if git fetch --quiet origin "$proof_branch" 2>/dev/null; then
	parent="$(git rev-parse FETCH_HEAD)"
fi

index_file="$(mktemp)"
rm -f "$index_file"
export GIT_INDEX_FILE="$index_file"
if [[ -n "$parent" ]]; then
	git read-tree "$parent"
else
	git read-tree --empty
fi
git rm -r --cached --quiet --ignore-unmatch -- "$branch"
for png in "${pngs[@]}"; do
	blob="$(git hash-object -w "$png")"
	git update-index --add --cacheinfo "100644,$blob,$branch/$(basename "$png")"
done
tree="$(git write-tree)"
rm -f "$index_file"
unset GIT_INDEX_FILE

commit="$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "Proof for $branch at $head_sha")"
if ((push)); then
	git push --quiet origin "$commit:refs/heads/$proof_branch"
else
	echo "Dry run: proof commit $commit not pushed." >&2
fi

echo "### UI proof"
echo
echo "Rendered by \`scripts/proof-publish.sh\` from \`$head_sha\`."
echo
for png in "${pngs[@]}"; do
	name="$(basename "$png" .png)"
	echo "**$name**"
	echo
	echo "![$name](https://raw.githubusercontent.com/$slug/$commit/$branch/$name.png)"
	echo
done
