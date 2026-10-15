#!/usr/bin/env bash
# Shared build metadata helpers, sourced by development/release tooling.

dev_build_info() {
	build_commit="$(git -C "$repo_dir" rev-parse HEAD)"
	build_version="dev-$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
	if [[ -n "$(git -C "$repo_dir" status --porcelain --untracked-files=normal)" ]]; then
		build_version+='-dirty'
	fi
}

stamp_build_info() {
	local root="$1" version="$2" channel="$3" commit="$4" addon toc
	shift 4
	for addon in "$@"; do
		toc="$root/$addon/$addon.toc"
		sed -i -E "/^## X-Build-(Channel|Commit):/d; s/^## Version:.*/## Version: $version/" "$toc"
		# Append metadata as well, so recovery builds can package older tags.
		printf '\n## X-Build-Channel: %s\n## X-Build-Commit: %s\n' "$channel" "$commit" >> "$toc"
	done
}
