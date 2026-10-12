#!/usr/bin/env bash
# Exercise the actual hook against a disposable Git repo with a tiny test runner.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hook_test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$hook_test_tmp"' EXIT
export HOOK_TEST_LOG="$hook_test_tmp/runs"
mkdir -p "$hook_test_tmp/repo/scripts" "$hook_test_tmp/repo/tests" "$hook_test_tmp/repo/.githooks"
cp "$repo_dir/tests/fixtures/pre-push/run-tests.sh" "$hook_test_tmp/repo/scripts/"
cp "$repo_dir/scripts/install-hooks.sh" "$hook_test_tmp/repo/scripts/"
cp "$repo_dir/.githooks/pre-push" "$hook_test_tmp/repo/.githooks/"
cp "$repo_dir/tests/fixtures/pre-push/pass" "$hook_test_tmp/repo/tests/marker"
cd "$hook_test_tmp/repo"
git init -q
git config user.name 'Hook test'
git config user.email 'hook-test@example.invalid'
git add .
git -c core.hooksPath=/dev/null commit -qm 'Passing fixture'
passing="$(git rev-parse HEAD)"
zero=0000000000000000000000000000000000000000

bash scripts/install-hooks.sh >/dev/null
[[ "$(git config --local core.hooksPath)" == .githooks ]]
bash scripts/install-hooks.sh >/dev/null

# A dirty failing file must not replace the passing commit being pushed.
cp "$repo_dir/tests/fixtures/pre-push/fail" tests/marker
printf 'refs/heads/main %s refs/heads/main %s\nrefs/tags/test %s refs/tags/test %s\n' \
	"$passing" "$zero" "$passing" "$zero" | bash .githooks/pre-push >/dev/null
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 1 ]]
snapshot="$(< "$HOOK_TEST_LOG")"
[[ ! -e "$snapshot" ]]

# A failing pushed commit must stop the push, even with a passing working file.
git add tests/marker
git -c core.hooksPath=/dev/null commit -qm 'Failing fixture'
failing="$(git rev-parse HEAD)"
cp "$repo_dir/tests/fixtures/pre-push/pass" tests/marker
if printf 'refs/heads/main %s refs/heads/main %s\n' "$failing" "$passing" \
	| bash .githooks/pre-push > "$hook_test_tmp/failure.log" 2>&1; then
	echo 'Hook allowed a failing commit.' >&2
	exit 1
fi
grep -q 'Push stopped: tests failed' "$hook_test_tmp/failure.log"
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 2 ]]

# Branch deletion and an empty push must not invoke the suite.
printf '(delete) %s refs/heads/main %s\n' "$zero" "$passing" | bash .githooks/pre-push
bash .githooks/pre-push < /dev/null
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 2 ]]

# Exercise Git's real hook invocation, including its exported Git environment.
git init --bare -q "$hook_test_tmp/remote.git"
git push "$hook_test_tmp/remote.git" "$passing:refs/heads/passing" > "$hook_test_tmp/push.log" 2>&1
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 3 ]]
if git push "$hook_test_tmp/remote.git" "$failing:refs/heads/failing" > "$hook_test_tmp/push.log" 2>&1; then
	echo 'Git pushed a failing commit despite the hook.' >&2
	exit 1
fi
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 4 ]]
[[ "$(git --git-dir="$hook_test_tmp/remote.git" rev-parse refs/heads/passing)" == "$passing" ]]
if git --git-dir="$hook_test_tmp/remote.git" show-ref --verify --quiet refs/heads/failing; then
	echo 'Failing ref reached the remote.' >&2
	exit 1
fi

git config --local core.hooksPath custom-hooks
if bash scripts/install-hooks.sh > "$hook_test_tmp/install.log" 2>&1; then
	echo 'Installer replaced a custom hook configuration.' >&2
	exit 1
fi
[[ "$(git config --local core.hooksPath)" == custom-hooks ]]
git config --local --unset core.hooksPath
cp .githooks/pre-push .git/hooks/pre-push
if bash scripts/install-hooks.sh > "$hook_test_tmp/install.log" 2>&1; then
	echo 'Installer bypassed an existing pre-push hook.' >&2
	exit 1
fi
echo 'Pre-push integration checks passed.'
