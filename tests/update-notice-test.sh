#!/usr/bin/env bash

set -euo pipefail

# macOS ships bash 3.2, whose `[[ $s == *"..."* ]]` does not reliably match a
# multibyte pattern — it silently reports "no match" and an assertion written
# that way passes without testing anything. Match with grep -F instead.
contains() { printf '%s' "$2" | grep -qF -- "$1"; }
assert_contains() {
  contains "$1" "$2" || { printf 'expected to find %s in:\n%s\n' "$1" "$2" >&2; exit 1; }
}
assert_lacks() {
  contains "$1" "$2" && { printf 'expected NOT to find %s in:\n%s\n' "$1" "$2" >&2; exit 1; }
  return 0
}

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

config_dir="$test_dir/config"
fake_git="$test_dir/git"
fake_curl="$test_dir/curl"
compare_json="$test_dir/compare.json"

cat > "$fake_git" <<'EOF'
#!/usr/bin/env bash
printf '%s\trefs/heads/main\n' "${DOTFILES_TEST_REMOTE_REVISION}"
EOF
chmod +x "$fake_git"

# Stands in for `curl -fsSL ... /compare/<base>...<head>`. Exporting
# DOTFILES_TEST_COMPARE_FAIL makes it exit non-zero the way real curl does on an
# HTTP error, so the fallback path can be tested without a network.
cat > "$fake_curl" <<'EOF'
#!/usr/bin/env bash
[ -n "${DOTFILES_TEST_COMPARE_FAIL:-}" ] && exit 22
cat "${DOTFILES_TEST_COMPARE_JSON}"
EOF
chmod +x "$fake_curl"

# Seven commits, so the five-commit cap has something to trim.
cat > "$compare_json" <<'EOF'
{
  "status": "ahead",
  "total_commits": 7,
  "commits": [
    { "commit": { "message": "feat: 1 番目 (#41)\n\nbody line" } },
    { "commit": { "message": "feat: 2 番目 (#42)" } },
    { "commit": { "message": "feat: 3 番目 (#43)" } },
    { "commit": { "message": "feat: 4 番目 (#44)" } },
    { "commit": { "message": "feat: 5 番目 (#45)" } },
    { "commit": { "message": "fix: 6 番目 (#46)" } },
    { "commit": { "message": "docs: 7 番目 (#47)" } }
  ]
}
EOF

export DOTFILES_CONFIG_DIR="$config_dir"
export DOTFILES_GIT_BIN="$fake_git"
export DOTFILES_CURL_BIN="$fake_curl"
export DOTFILES_TEST_COMPARE_JSON="$compare_json"
export DOTFILES_TEST_REMOTE_REVISION="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# shellcheck disable=SC1091
source "$(dirname "$0")/../.dotfiles/update-notice.sh"

bash "$(dirname "$0")/../.dotfiles/update-notice.sh" install
[ "$(cat "$config_dir/revision")" = "$DOTFILES_TEST_REMOTE_REVISION" ]

export DOTFILES_TEST_REMOTE_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

if command -v jq >/dev/null 2>&1; then
  output="$(dotfiles_update_notice_check)"
  assert_contains "dotfiles の更新があります" "$output"
  assert_contains "/dotfiles apply" "$output"
  assert_contains "curl -fsSL" "$output"
  # Newest first, capped at five, with the remainder counted.
  assert_contains "  • docs: 7 番目 (#47)" "$output"
  assert_contains "  • feat: 3 番目 (#43)" "$output"
  assert_lacks "feat: 2 番目" "$output"
  assert_contains "ほか 2 件" "$output"
  # Only the subject line, never the squash-merge body.
  assert_lacks "body line" "$output"

  # An empty range must not print an empty details block.
  printf '0\n' > "$config_dir/last-update-check"
  output="$(DOTFILES_TEST_COMPARE_JSON=/dev/null dotfiles_update_notice_check)"
  assert_contains "dotfiles の更新があります" "$output"
  assert_lacks "ほか" "$output"
else
  echo "jq が無いので更新内容の表示テストはスキップ" >&2
fi

# The notice degrades to the revision range alone when the compare call fails.
printf '0\n' > "$config_dir/last-update-check"
export DOTFILES_TEST_COMPARE_FAIL=1
output="$(dotfiles_update_notice_check)"
unset DOTFILES_TEST_COMPARE_FAIL
assert_contains "dotfiles の更新があります" "$output"
assert_contains "/dotfiles apply" "$output"
assert_contains "curl -fsSL" "$output"
assert_lacks "番目" "$output"

# ...and the same when jq is missing, which is the case on a shell that starts
# before mise has put it on PATH.
printf '0\n' > "$config_dir/last-update-check"
DOTFILES_JQ_BIN="$test_dir/absent-jq"
output="$(dotfiles_update_notice_check)"
# shellcheck disable=SC2034  # read by the sourced update-notice.sh, not by this file
DOTFILES_JQ_BIN="jq"
assert_contains "dotfiles の更新があります" "$output"
assert_lacks "番目" "$output"

printf '%s\n' "$(date +%s)" > "$config_dir/last-update-check"
if dotfiles_update_notice_check | grep -q 'dotfiles の更新があります'; then
  echo "check interval was ignored" >&2
  exit 1
fi

echo "update notice tests passed"
