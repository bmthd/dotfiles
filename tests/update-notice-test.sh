#!/usr/bin/env bash

set -euo pipefail

# Assert through grep -F rather than a bare `[[ $s == *"..."* ]]`: when one of
# these fails it prints what was actually produced, which is what you need to
# see when the notice is assembled from several printf calls.
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
fake_curl="$test_dir/curl"
compare_dotfiles="$test_dir/compare-dotfiles.json"
compare_skills="$test_dir/compare-skills.json"

skills_revision_file="$config_dir/revisions/bmthd-skills"

# One fake for both API calls — the head of main (`/commits/main`) and the list
# of what changed (`/compare/...`) — because both now go through curl. It
# answers per repository, since the point of the watch list is that the two
# repositories move independently.
#
# It also asserts the timeout: every call this file makes runs at the start of
# an interactive shell, so a request without --max-time is a terminal that hangs
# on a captive portal. A fake that merely tolerated its absence would let that
# regress silently.
# Exporting DOTFILES_TEST_COMPARE_FAIL makes it exit non-zero the way real curl
# does on an HTTP error, so the fallback path can be tested without a network.
cat > "$fake_curl" <<'EOF'
#!/usr/bin/env bash
url=""
timed=""
for arg in "$@"; do
  case "$arg" in
    --max-time) timed="yes" ;;
    http*) url="$arg" ;;
  esac
done
if [ -z "$timed" ]; then
  printf 'curl called without --max-time: %s\n' "$url" >&2
  exit 1
fi
case "$url" in
  */commits/main)
    case "$url" in
      *skills*) printf '%s\n' "${DOTFILES_TEST_REV_SKILLS}" ;;
      *)        printf '%s\n' "${DOTFILES_TEST_REV_DOTFILES}" ;;
    esac
    exit 0
    ;;
esac
[ -n "${DOTFILES_TEST_COMPARE_FAIL:-}" ] && exit 22
case "$url" in
  *skills*) cat "${DOTFILES_TEST_COMPARE_SKILLS}" ;;
  *)        cat "${DOTFILES_TEST_COMPARE_DOTFILES}" ;;
esac
EOF
chmod +x "$fake_curl"

# Seven commits, so the five-commit cap has something to trim.
cat > "$compare_dotfiles" <<'EOF'
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

cat > "$compare_skills" <<'EOF'
{
  "status": "ahead",
  "total_commits": 1,
  "commits": [
    { "commit": { "message": "feat: スキルを追加 (#7)" } }
  ]
}
EOF

export DOTFILES_CONFIG_DIR="$config_dir"
export DOTFILES_CURL_BIN="$fake_curl"
export DOTFILES_TEST_COMPARE_DOTFILES="$compare_dotfiles"
export DOTFILES_TEST_COMPARE_SKILLS="$compare_skills"
export DOTFILES_TEST_REV_DOTFILES="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export DOTFILES_TEST_REV_SKILLS="1111111111111111111111111111111111111111"

notice="$(dirname "$0")/../.dotfiles/update-notice.sh"

# shellcheck disable=SC1090
source "$notice"

# Nothing has been checked yet, so let every check below actually run.
due() { printf '0\n' > "$config_dir/last-update-check"; }

# `install` records every watched repository.
bash "$notice" install
[ "$(cat "$config_dir/revision")" = "$DOTFILES_TEST_REV_DOTFILES" ]
[ "$(cat "$skills_revision_file")" = "$DOTFILES_TEST_REV_SKILLS" ]

# `record <name>` records that one and leaves the others alone.
export DOTFILES_TEST_REV_SKILLS="2222222222222222222222222222222222222222"
export DOTFILES_TEST_REV_DOTFILES="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
bash "$notice" record skills
[ "$(cat "$skills_revision_file")" = "$DOTFILES_TEST_REV_SKILLS" ]
[ "$(cat "$config_dir/revision")" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]

# install.sh pins the whole installation to one commit and passes it in
# DOTFILES_REVISION. That commit — not the head of main, which may have moved
# while the installation ran — is what must land in the revision file: it is the
# common ancestor `/dotfiles apply` 3-way merges against, so a value no
# installed file came from would make the merge base a fiction.
pinned="cccccccccccccccccccccccccccccccccccccccc"
DOTFILES_REVISION="$pinned" bash "$notice" install
[ "$(cat "$config_dir/revision")" = "$pinned" ] || {
  printf 'expected the pinned revision, got %s\n' "$(cat "$config_dir/revision")" >&2
  exit 1
}
# The pin covers dotfiles only: `skills add` takes no ref, so bmthd/skills is
# still recorded at whatever its head was at install time.
[ "$(cat "$skills_revision_file")" = "$DOTFILES_TEST_REV_SKILLS" ]

# Without a pin — `mise run setup:update-notice` on its own — nothing has been
# resolved, and the head remains the most honest answer available.
bash "$notice" install
[ "$(cat "$config_dir/revision")" = "$DOTFILES_TEST_REV_DOTFILES" ]

# An answer that is not a SHA — a rate-limit body, a captive portal's login
# page — must not be recorded as one. Written to a revision file it would never
# match a real commit again, and the notice would fire every day forever.
rm -f "$skills_revision_file"
DOTFILES_TEST_REV_SKILLS="<html>rate limited</html>" bash "$notice" record skills
[ ! -e "$skills_revision_file" ] || {
  printf 'a non-SHA response was recorded: %s\n' "$(cat "$skills_revision_file")" >&2
  exit 1
}

# Back to the state the checks below compare against.
printf '%s\n' "$DOTFILES_TEST_REV_SKILLS" > "$skills_revision_file"
printf '%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$config_dir/revision"

# A name that is not on the watch list is a typo, not a silent no-op.
if bash "$notice" record nosuchrepo 2>/dev/null; then
  echo "record accepted an unknown repository" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  # Both repositories moved: one header, one block each, and the skill — which
  # reinstalls the skills on its way through — is the single remedy.
  export DOTFILES_TEST_REV_SKILLS="3333333333333333333333333333333333333333"
  due
  output="$(dotfiles_update_notice_check)"
  assert_contains "🔔 更新があります" "$output"
  assert_contains "dotfiles (aaaaaaa → bbbbbbb)" "$output"
  assert_contains "skills (2222222 → 3333333)" "$output"
  assert_contains "/dotfiles apply" "$output"
  assert_contains "curl -fsSL" "$output"
  assert_lacks "mise run setup:skills" "$output"
  # Newest first, capped at five, with the remainder counted.
  assert_contains "  • docs: 7 番目 (#47)" "$output"
  assert_contains "  • feat: 3 番目 (#43)" "$output"
  assert_lacks "feat: 2 番目" "$output"
  assert_contains "ほか 2 件" "$output"
  assert_contains "  • feat: スキルを追加 (#7)" "$output"
  # Only the subject line, never the squash-merge body.
  assert_lacks "body line" "$output"
  # The header is printed once, not once per repository.
  [ "$(printf '%s' "$output" | grep -cF '🔔')" = "1" ]

  # Skills alone moved: no dotfiles block, and the remedy is the task that
  # reinstalls them (and records the new revision), not the merge procedure.
  printf '%s\n' "$DOTFILES_TEST_REV_DOTFILES" > "$config_dir/revision"
  printf '%s\n' "$DOTFILES_TEST_REV_SKILLS" > "$skills_revision_file"
  export DOTFILES_TEST_REV_SKILLS="4444444444444444444444444444444444444444"
  due
  output="$(dotfiles_update_notice_check)"
  assert_contains "skills (3333333 → 4444444)" "$output"
  assert_lacks "dotfiles (" "$output"
  assert_contains "mise run setup:skills" "$output"
  assert_lacks "/dotfiles apply" "$output"

  # An empty range must not print an empty details block.
  printf '%s\n' "3333333333333333333333333333333333333333" > "$skills_revision_file"
  due
  output="$(DOTFILES_TEST_COMPARE_SKILLS=/dev/null dotfiles_update_notice_check)"
  assert_contains "skills (3333333 → 4444444)" "$output"
  assert_lacks "ほか" "$output"
else
  echo "jq が無いので更新内容の表示テストはスキップ" >&2
fi

printf '%s\n' "$DOTFILES_TEST_REV_SKILLS" > "$skills_revision_file"
printf '%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$config_dir/revision"

# The notice degrades to the revision range alone when the compare call fails.
due
# export, not a `DOTFILES_TEST_COMPARE_FAIL=1 output=$(...)` prefix: that form
# assigns in this shell without exporting, so the fake curl — an external
# command — would never see the flag and this case would silently pass while
# testing the success path.
export DOTFILES_TEST_COMPARE_FAIL=1
output="$(dotfiles_update_notice_check)"
unset DOTFILES_TEST_COMPARE_FAIL
assert_contains "dotfiles (aaaaaaa → bbbbbbb)" "$output"
assert_contains "/dotfiles apply" "$output"
assert_lacks "番目" "$output"

# ...and the same when jq is missing, which is the case on a shell that starts
# before mise has put it on PATH.
due
DOTFILES_JQ_BIN="$test_dir/absent-jq"
output="$(dotfiles_update_notice_check)"
# shellcheck disable=SC2034  # read by the sourced update-notice.sh, not by this file
DOTFILES_JQ_BIN="jq"
assert_contains "dotfiles (aaaaaaa → bbbbbbb)" "$output"
assert_lacks "番目" "$output"

# A machine that predates a newly watched repository has no revision file for
# it. Seed it silently — announcing every commit since the repository began
# would be noise, and there is nothing here that a merge could lose.
rm -f "$skills_revision_file"
due
output="$(dotfiles_update_notice_check)"
assert_lacks "skills (" "$output"
[ "$(cat "$skills_revision_file")" = "$DOTFILES_TEST_REV_SKILLS" ]

# The dotfiles revision file is the common ancestor `/dotfiles apply` merges
# against, so a missing one must stay silent rather than be invented — while
# the other repositories are still checked.
rm -f "$config_dir/revision"
printf '%s\n' "3333333333333333333333333333333333333333" > "$skills_revision_file"
due
output="$(dotfiles_update_notice_check)"
assert_lacks "dotfiles (" "$output"
assert_contains "skills (3333333 → 4444444)" "$output"
[ ! -e "$config_dir/revision" ]

printf '%s\n' "$(date +%s)" > "$config_dir/last-update-check"
if dotfiles_update_notice_check | grep -q '更新があります'; then
  echo "check interval was ignored" >&2
  exit 1
fi

echo "update notice tests passed"
