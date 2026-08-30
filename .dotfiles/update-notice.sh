#!/usr/bin/env bash

# Source this file from an interactive shell to periodically compare the
# revisions installed on this machine with the remote main branches they came
# from. It only notifies; installing updates remains an explicit user action.

DOTFILES_CONFIG_DIR="${DOTFILES_CONFIG_DIR:-$HOME/.config/dotfiles}"
DOTFILES_UPDATE_CHECK_INTERVAL="${DOTFILES_UPDATE_CHECK_INTERVAL:-86400}"

# Both the remote head and the list of what changed come from the GitHub API,
# so that every network call this file makes goes through curl and can be given
# the same timeout. This runs at the start of every interactive shell: the one
# thing it must never do is make opening a terminal wait on the network.
DOTFILES_API="${DOTFILES_API:-https://api.github.com/repos}"
DOTFILES_CURL_BIN="${DOTFILES_CURL_BIN:-curl}"
DOTFILES_JQ_BIN="${DOTFILES_JQ_BIN:-jq}"
DOTFILES_UPDATE_MAX_COMMITS="${DOTFILES_UPDATE_MAX_COMMITS:-5}"

# The repositories this machine follows, one per line:
#
#   name|owner/repo|revision file|what to do when the revision file is missing
#
# `name` is what the notice prints and what `record` takes. Only repositories
# whose contents this repo installs belong here: the third-party skill sources
# in `setup:skills` move on their own schedule and for reasons unrelated to the
# skills actually installed from them, so watching them would mean a daily
# notice about commits that change nothing here.
#
# The missing-file policy differs on purpose. `seed` fills the file in with the
# current head and says nothing, which is how an already-installed machine picks
# up a newly watched repository. dotfiles cannot do that: its revision file is
# not just a marker but the common ancestor `/dotfiles apply` 3-way merges
# against, and inventing one would make apply believe this machine already
# carries repository changes it has never seen. So a missing dotfiles revision
# stays `skip` — silent, the way it has always been.
dotfiles_update_notice_watchlist() {
    printf '%s\n' \
        "dotfiles|bmthd/dotfiles|$DOTFILES_CONFIG_DIR/revision|skip" \
        "skills|bmthd/skills|$DOTFILES_CONFIG_DIR/revisions/bmthd-skills|seed"
}

# The head of main, as a bare SHA.
#
# This was `git ls-remote`, which takes no timeout: git's own connect and read
# timeouts are unset by default, so behind a captive portal or on a dying Wi-Fi
# link the fetch hangs, and with it the shell that sourced this file. The
# commits API with `Accept: application/vnd.github.sha` answers with the same
# SHA in plain text, needs no jq, and takes --max-time like the compare call.
dotfiles_update_notice_remote_revision() {
    command -v "$DOTFILES_CURL_BIN" >/dev/null 2>&1 || return 1

    local revision
    revision="$("$DOTFILES_CURL_BIN" -fsSL --max-time 5 \
        -H 'Accept: application/vnd.github.sha' \
        "$DOTFILES_API/$1/commits/main" 2>/dev/null)" || return 1
    revision="${revision%%[[:space:]]*}"
    # An error body would otherwise be written to a revision file as if it were
    # a commit, and every later comparison against it would report an update.
    case "$revision" in
        ''|*[!0-9a-f]*) return 1 ;;
    esac
    printf '%s\n' "$revision"
}

# What install.sh recorded as the revision it installed from, for the watched
# repository named here. install.sh resolves bmthd/dotfiles to one commit and
# fetches every file from it, so that SHA — not whatever main points at by the
# time this runs — is what this machine actually carries, and it is what
# `/dotfiles apply` needs as its merge base. Empty when this is not running as
# part of an installation, in which case the head is the best answer available.
dotfiles_update_notice_pinned_revision() {
    case "$1" in
        dotfiles) printf '%s' "${DOTFILES_REVISION:-}" ;;
    esac
}

# Record what this machine has installed, for one watched repository or (with
# no argument) all of them. Call it right after installing from that repository.
#
# install.sh passes the commit it pinned the installation to, and that is what
# gets recorded. The skills CLI has no such thing — `skills add` takes no ref —
# so for bmthd/skills "the head at install time" remains the most honest answer
# available, and the remote head is used.
#
# Networking failures are deliberately not fatal. This runs as the tail of a
# setup task, and an offline machine should still finish setting itself up.
dotfiles_update_notice_record() {
    local want="${1:-}" name slug revision_file policy revision matched=""

    while IFS='|' read -r name slug revision_file policy; do
        [ -n "$name" ] || continue
        [ -z "$want" ] || [ "$want" = "$name" ] || continue
        matched="yes"
        revision="$(dotfiles_update_notice_pinned_revision "$name")"
        [ -n "$revision" ] ||
            revision="$(dotfiles_update_notice_remote_revision "$slug")" || continue
        mkdir -p "${revision_file%/*}"
        printf '%s\n' "$revision" > "$revision_file"
    done <<EOF
$(dotfiles_update_notice_watchlist)
EOF

    if [ -n "$want" ] && [ -z "$matched" ]; then
        printf 'update-notice: 監視対象ではありません: %s\n' "$want" >&2
        return 1
    fi
    return 0
}

# List the commit subjects between the installed revision and the remote head,
# newest first. main only ever gains squash merges, so one subject is one PR and
# the subject line alone says what changed.
#
# This is best effort by design. It needs curl and jq, which arrive with mise and
# may not be on PATH yet at shell startup, and it can be refused by the API
# (rate limit, or a base revision made unreachable by a force push). Every one of
# those cases returns non-zero and the caller falls back to printing just the
# revision range — the notification itself never depends on this succeeding.
dotfiles_update_notice_summary() {
    local slug="$1" base="$2" head="$3" response

    command -v "$DOTFILES_CURL_BIN" >/dev/null 2>&1 || return 1
    command -v "$DOTFILES_JQ_BIN" >/dev/null 2>&1 || return 1

    # --max-time keeps a slow or hanging API off the critical path of an
    # interactive shell starting up.
    response="$("$DOTFILES_CURL_BIN" -fsSL --max-time 5 \
        -H 'Accept: application/vnd.github+json' \
        "$DOTFILES_API/$slug/compare/$base...$head" 2>/dev/null)" || return 1

    # total_commits is the honest count; commits[] is capped at 250 by the API.
    # shellcheck disable=SC2016  # $total and $max are jq variables, not shell ones
    printf '%s' "$response" | "$DOTFILES_JQ_BIN" -er \
        --argjson max "$DOTFILES_UPDATE_MAX_COMMITS" '
          (.total_commits // (.commits | length)) as $total
        | ([.commits[] | .commit.message | split("\n")[0]] | reverse) as $subjects
        | if ($subjects | length) == 0 then empty else
            ($subjects[:$max][] | "  • " + .),
            (if $total > $max then "  ほか \($total - $max) 件" else empty end)
          end
    ' 2>/dev/null
}

# What to actually run, given which repositories moved (a space-separated list
# of watch-list names).
#
# The skill leads whenever dotfiles itself changed, because it is the only path
# that merges rather than overwrites: install.sh replaces the shared files
# wholesale, which costs this machine whatever local edits it carries. It also
# reinstalls the skills on the way through, so it covers both repositories in
# one pass. It names no agent — the skill is installed into every agent
# .mise.toml supports, and that list grows, so any list spelled out here would
# go stale.
dotfiles_update_notice_remedy() {
    case " $1 " in
        *" dotfiles "*)
            printf '\n更新するには: 使っている AI エージェントで /dotfiles apply\n'
            printf '  端末固有の設定を残したまま取り込む\n'
            printf '入れ直すには: curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | %s\n' "${SHELL:-bash}"
            printf 'ローカルの clone は: ghq get -u github.com/bmthd/dotfiles\n\n'
            ;;
        *)
            # Skills hold no per-machine state, so there is nothing to merge and
            # reinstalling from the source is the entire update. The task is also
            # what records the new revision, which is what stops this notice from
            # firing again tomorrow.
            printf '\n更新するには: mise run setup:skills\n'
            printf '  スキルは端末固有の設定を持たないので入れ直してよい\n\n'
            ;;
    esac
}

dotfiles_update_notice_check() {
    local last_check_file now last_check
    local name slug revision_file policy installed_revision remote_revision summary
    local announced="" changed=""

    last_check_file="$DOTFILES_CONFIG_DIR/last-update-check"
    now="$(date +%s)"
    last_check="$(cat "$last_check_file" 2>/dev/null || true)"
    case "$last_check" in
        ''|*[!0-9]*) ;;
        *)
            [ $((now - last_check)) -ge "$DOTFILES_UPDATE_CHECK_INTERVAL" ] || return 0
            ;;
    esac

    mkdir -p "$DOTFILES_CONFIG_DIR"
    printf '%s\n' "$now" > "$last_check_file"

    while IFS='|' read -r name slug revision_file policy; do
        [ -n "$name" ] || continue
        remote_revision="$(dotfiles_update_notice_remote_revision "$slug")" || continue

        if [ ! -r "$revision_file" ]; then
            if [ "$policy" = "seed" ]; then
                mkdir -p "${revision_file%/*}"
                printf '%s\n' "$remote_revision" > "$revision_file"
            fi
            continue
        fi

        installed_revision="$(cat "$revision_file")"
        [ "$installed_revision" = "$remote_revision" ] && continue

        # One header for however many repositories moved: two full notices at
        # shell startup is a wall, and the remedy below covers them together.
        if [ -z "$announced" ]; then
            printf '\n🔔 更新があります\n'
            announced="yes"
        fi
        printf '\n%s (%s → %s)\n' "$name" "${installed_revision:0:7}" "${remote_revision:0:7}"
        summary="$(dotfiles_update_notice_summary "$slug" "$installed_revision" "$remote_revision")" || summary=""
        [ -n "$summary" ] && printf '%s\n' "$summary"
        changed="$changed $name"
    done <<EOF
$(dotfiles_update_notice_watchlist)
EOF

    [ -n "$announced" ] || return 0
    dotfiles_update_notice_remedy "$changed"
}

case "${1:-}" in
    install)
        dotfiles_update_notice_record
        exit $?
        ;;
    record)
        dotfiles_update_notice_record "${2:-}"
        exit $?
        ;;
esac

case $- in
    *i*) dotfiles_update_notice_check ;;
esac
