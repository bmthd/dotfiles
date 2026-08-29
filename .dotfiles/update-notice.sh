#!/usr/bin/env bash

# Source this file from an interactive shell to periodically compare the
# installed dotfiles revision with the remote main branch. It only notifies;
# installing updates remains an explicit user action.

DOTFILES_CONFIG_DIR="${DOTFILES_CONFIG_DIR:-$HOME/.config/dotfiles}"
DOTFILES_REMOTE="${DOTFILES_REMOTE:-https://github.com/bmthd/dotfiles.git}"
DOTFILES_GIT_BIN="${DOTFILES_GIT_BIN:-git}"
DOTFILES_UPDATE_CHECK_INTERVAL="${DOTFILES_UPDATE_CHECK_INTERVAL:-86400}"

# Used only to list what changed, via the compare API. Kept separate from
# DOTFILES_REMOTE because that one is a git URL, not an API endpoint.
DOTFILES_API="${DOTFILES_API:-https://api.github.com/repos/bmthd/dotfiles}"
DOTFILES_CURL_BIN="${DOTFILES_CURL_BIN:-curl}"
DOTFILES_JQ_BIN="${DOTFILES_JQ_BIN:-jq}"
DOTFILES_UPDATE_MAX_COMMITS="${DOTFILES_UPDATE_MAX_COMMITS:-5}"

dotfiles_update_notice_remote_revision() {
    command -v "$DOTFILES_GIT_BIN" >/dev/null 2>&1 || return 1

    local revision
    revision="$("$DOTFILES_GIT_BIN" ls-remote "$DOTFILES_REMOTE" refs/heads/main 2>/dev/null)" || return 1
    revision="${revision%%[[:space:]]*}"
    [ -n "$revision" ] || return 1
    printf '%s\n' "$revision"
}

dotfiles_update_notice_install() {
    local revision
    revision="$(dotfiles_update_notice_remote_revision)" || return 0

    mkdir -p "$DOTFILES_CONFIG_DIR"
    printf '%s\n' "$revision" > "$DOTFILES_CONFIG_DIR/revision"
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
    local base="$1" head="$2" response

    command -v "$DOTFILES_CURL_BIN" >/dev/null 2>&1 || return 1
    command -v "$DOTFILES_JQ_BIN" >/dev/null 2>&1 || return 1

    # --max-time keeps a slow or hanging API off the critical path of an
    # interactive shell starting up.
    response="$("$DOTFILES_CURL_BIN" -fsSL --max-time 5 \
        -H 'Accept: application/vnd.github+json' \
        "$DOTFILES_API/compare/$base...$head" 2>/dev/null)" || return 1

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

dotfiles_update_notice_check() {
    local revision_file last_check_file installed_revision remote_revision now last_check summary
    revision_file="$DOTFILES_CONFIG_DIR/revision"
    last_check_file="$DOTFILES_CONFIG_DIR/last-update-check"

    [ -r "$revision_file" ] || return 0
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
    remote_revision="$(dotfiles_update_notice_remote_revision)" || return 0
    installed_revision="$(cat "$revision_file")"
    [ "$installed_revision" = "$remote_revision" ] && return 0

    printf '\n🔔 dotfiles の更新があります (%s → %s)\n' \
        "${installed_revision:0:7}" "${remote_revision:0:7}"
    summary="$(dotfiles_update_notice_summary "$installed_revision" "$remote_revision")" || summary=""
    [ -n "$summary" ] && printf '\n%s\n\n' "$summary"
    # The skill leads because it is the only path that merges rather than
    # overwrites: install.sh replaces the shared files wholesale, which costs
    # this machine whatever local edits it carries. It names no agent — the
    # skill is installed into every agent .mise.toml supports, and that list
    # grows, so any list spelled out here would go stale.
    printf '更新するには: 使っている AI エージェントで /dotfiles apply\n'
    printf '  端末固有の設定を残したまま取り込む\n'
    printf '入れ直すには: curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | %s\n' "${SHELL:-bash}"
    printf 'ローカルの clone は: ghq get -u github.com/bmthd/dotfiles\n\n'
}

if [ "${1:-}" = "install" ]; then
    dotfiles_update_notice_install
    exit $?
fi

case $- in
    *i*) dotfiles_update_notice_check ;;
esac
