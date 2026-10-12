#!/usr/bin/env bash
# Upload an already-built archive; --dry-run emits metadata without contacting CF.
set -euo pipefail
dry_run=false
if [[ "${1:-}" == --dry-run ]]; then dry_run=true; shift; fi
archive="${1:?ZIP archive required}"
tag="${2:?Version tag required}"
[[ -f "$archive" ]] || { echo "Missing archive: $archive" >&2; exit 1; }
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || exit 1
project_id="${CF_PROJECT_ID:?Set CF_PROJECT_ID to the registered CurseForge project ID}"
version_ids="${CF_GAME_VERSION_IDS:?Set CF_GAME_VERSION_IDS to compatible CurseForge numeric game-version IDs, comma-separated}"
[[ "$project_id" =~ ^[1-9][0-9]*$ ]] || exit 1
[[ "$version_ids" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || exit 1
case "$tag" in
	*-alpha*) release_type=alpha ;;
	*-*) release_type=beta ;;
	*) if [[ "${CF_PRERELEASE:-false}" == true ]]; then release_type=beta; else release_type=release; fi ;;
esac
metadata="$(jq -n --arg name "UnitFrames $tag" --arg type "$release_type" \
	--arg changelog "${CF_CHANGELOG:-See the GitHub release for $tag.}" \
	--argjson versions "[$version_ids]" \
	'{displayName:$name, releaseType:$type, changelog:$changelog, changelogType:"markdown", gameVersions:$versions}')"
if "$dry_run"; then printf '%s\n' "$metadata"; exit 0; fi
: "${CF_API_TOKEN:?Set the CurseForge upload API token}"
cf_api='https://wow.curseforge.com/api'
# Confirm configured IDs exist; do not infer game flavour from the TOC number.
versions="$(curl --fail --silent --show-error --max-time 60 \
	-H "X-Api-Token: $CF_API_TOKEN" "$cf_api/game/versions")"
if ! jq -e --argjson ids "[$version_ids]" \
	'([.[].id]) as $known | all($ids[]; . as $id | $known | index($id) != null)' \
	<<< "$versions" >/dev/null; then
	echo 'Configured CurseForge game-version IDs were not found. Check Forever support before publishing.' >&2
	exit 1
fi
# No automatic upload retry: an accepted upload must not be duplicated.
response="$(curl --fail --silent --show-error --max-time 180 \
	-H "X-Api-Token: $CF_API_TOKEN" \
	-F "metadata=$metadata" -F "file=@$archive;type=application/zip" \
	"$cf_api/projects/$project_id/upload-file")"
jq -e '.id | numbers' <<< "$response"

