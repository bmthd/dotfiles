#!/usr/bin/env bash
# Open (or refresh) the weekly skills PR from the lockfile that
# .dotfiles/apm/relock.sh --update just rewrote.
#
# Unlike mise.lock, which bump-tools.yml pushes straight to main because
# `--minimum-release-age` is its safety property, a skill revision has no
# release age to wait out: the review is the gate. So this goes through a PR,
# and the body links one compare view per repository that moved — the diff a
# reviewer actually needs, since the lockfile itself is mostly hashes.

set -euo pipefail
# sort and join must agree on collation.
export LC_ALL=C

: "${APP_SLUG:?APP_SLUG is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

lock=.dotfiles/apm/apm.lock.yaml
branch=bump-skills

if git diff --quiet -- "$lock"; then
    echo "No skill updates this week."
    exit 0
fi

# One "owner/repo commit" line per repository: entries from the same
# repository were resolved in the same run and share a commit.
commits() {
    awk '
        /^- repo_url: / { repo = $3 }
        /^  resolved_commit: / { print repo, $2 }
    ' | sort -u
}

changes="$(join <(git show "HEAD:$lock" | commits) <(commits < "$lock") \
    | awk '$2 != $3 { printf "- [%s](https://github.com/%s/compare/%s...%s)\n", $1, $1, $2, $3 }')"
added="$(join -v 2 <(git show "HEAD:$lock" | commits) <(commits < "$lock") | awk '{ printf "- %s (new)\n", $1 }')"
summary="$(printf '%s\n%s\n' "$changes" "$added" | sed '/^$/d')"
[ -n "$summary" ] || summary="No repository moved; only lockfile metadata changed."

count="$(printf '%s\n' "$changes" | sed '/^$/d' | wc -l | tr -d ' ')"
subject="chore(skills): bump $count skill source(s)"
body="Skill sources whose locked commit moved:

$summary

Resolved by \`.dotfiles/apm/relock.sh --update\`. Read each compare view before merging: these files load straight into every agent's context."

git config user.name "${APP_SLUG}[bot]"
git config user.email "${APP_SLUG}[bot]@users.noreply.github.com"
git switch -C "$branch"
git add "$lock"
git commit -m "$subject" -m "$body"
git push --force origin "$branch"

existing="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"
if [ -n "$existing" ]; then
    gh pr edit "$existing" --title "$subject" --body "$body"
else
    gh pr create --base main --head "$branch" --title "$subject" --body "$body"
fi
