#!/usr/bin/env bash

set -euo pipefail

: "${APP_SLUG:?APP_SLUG is required}"

if git diff --quiet -- mise.lock; then
  echo "No tool updates eligible today."
  exit 0
fi

updates="$(awk '
  FNR == 1 { source++ }
  /^\[\[tools\./ {
    tool = $0
    sub(/^\[\[tools\./, "", tool)
    sub(/\]\]$/, "", tool)
    gsub(/"/, "", tool)
  }
  /^version = / {
    version = $0
    sub(/^version = "/, "", version)
    sub(/"$/, "", version)
    if (source == 1) {
      previous[tool] = version
    } else if (previous[tool] != version) {
      printf "%s %s → %s\n", tool, previous[tool], version
    }
  }
' <(git show HEAD:mise.lock) mise.lock)"

if [ -n "$updates" ]; then
  update_count="$(printf '%s\n' "$updates" | wc -l | tr -d ' ')"
else
  update_count=0
fi

if [ "$update_count" -eq 1 ]; then
  subject="chore(deps): bump $updates"
elif [ "$update_count" -gt 1 ]; then
  subject="chore(deps): bump $update_count locked tool versions"
else
  subject="chore(deps): update locked tool metadata"
  updates="No tool version changes."
fi

body="$(printf 'Updated tool versions:\n%s\n\nResolved by mise lock --bump --minimum-release-age 2d.' "$updates")"
git config user.name "${APP_SLUG}[bot]"
git config user.email "${APP_SLUG}[bot]@users.noreply.github.com"
git add mise.lock
git commit -m "$subject" -m "$body"
