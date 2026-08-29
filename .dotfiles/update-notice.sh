#!/usr/bin/env bash

# Source this file from an interactive shell to periodically compare the
# installed dotfiles revision with the remote main branch. It only notifies;
# installing updates remains an explicit user action.

DOTFILES_CONFIG_DIR="${DOTFILES_CONFIG_DIR:-$HOME/.config/dotfiles}"
DOTFILES_REMOTE="${DOTFILES_REMOTE:-https://github.com/bmthd/dotfiles.git}"
DOTFILES_GIT_BIN="${DOTFILES_GIT_BIN:-git}"
DOTFILES_UPDATE_CHECK_INTERVAL="${DOTFILES_UPDATE_CHECK_INTERVAL:-86400}"

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

dotfiles_update_notice_check() {
    local revision_file last_check_file installed_revision remote_revision now last_check
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
    printf '更新するには: curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | %s\n' "${SHELL:-bash}"
    printf 'ローカルの clone は: ghq get -u github.com/bmthd/dotfiles\n'
    printf 'この端末の設定を残したまま更新するには: claude で /dotfiles apply\n\n'
}

if [ "${1:-}" = "install" ]; then
    dotfiles_update_notice_install
    exit $?
fi

case $- in
    *i*) dotfiles_update_notice_check ;;
esac
