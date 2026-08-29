#!/usr/bin/env bash
# Installs the global git hooks (see dispatch) and points core.hooksPath at
# them. Run by the `setup:git-hooks` mise task, which downloads this script
# rather than keeping it inline in .mise.toml.
#
# Works both from a checkout — dispatch is picked up from alongside this
# script — and standalone, where it is downloaded from the repository.
set -uo pipefail

HOOKS_DIR="${GIT_HOOKS_DIR:-$HOME/.config/git/hooks}"
DISPATCH_URL="https://raw.githubusercontent.com/bmthd/dotfiles/main/.dotfiles/git-hooks/dispatch"
PINACT_STAGED_URL="https://raw.githubusercontent.com/bmthd/dotfiles/main/.dotfiles/git-hooks/pinact-staged"
# Identifies a dispatch this script wrote, so a re-run refreshes its own files
# and only its own.
MARKER="bmthd/dotfiles global git hook dispatcher"
PINACT_MARKER="bmthd/dotfiles staged pinact helper"

# githooks(5), including the server-side and p4 hooks. core.hooksPath replaces
# git's hook search path rather than extending it, so a name missing here is a
# hook that no longer runs anywhere on the machine — forwarding one that never
# fires costs nothing in comparison.
HOOK_NAMES=(
    applypatch-msg pre-applypatch post-applypatch
    pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
    pre-rebase post-checkout post-merge pre-push
    pre-receive update proc-receive post-receive post-update
    reference-transaction push-to-checkout pre-auto-gc post-rewrite
    sendemail-validate fsmonitor-watchman post-index-change
    p4-changelist p4-prepare-changelist p4-post-changelist p4-pre-submit
)

mkdir -p "$HOOKS_DIR"

# ~/.config/git/hooks is a conventional place to keep hooks, so it may already
# hold somebody's own. Overwriting those would destroy exactly what dispatch
# exists to preserve, so a file that is not ours is left alone.
if [ -e "$HOOKS_DIR/dispatch" ] && ! grep -q "$MARKER" "$HOOKS_DIR/dispatch" 2> /dev/null; then
    echo "⚠ $HOOKS_DIR/dispatch exists and was not written by this script; aborting"
    exit 1
fi
if [ -e "$HOOKS_DIR/pinact-staged" ] &&
    ! grep -q "$PINACT_MARKER" "$HOOKS_DIR/pinact-staged" 2> /dev/null; then
    echo "⚠ $HOOKS_DIR/pinact-staged exists and was not written by this script; aborting"
    exit 1
fi

local_dispatch="$(cd "$(dirname "$0")" && pwd)/dispatch"
if [ -f "$local_dispatch" ]; then
    cp "$local_dispatch" "$HOOKS_DIR/dispatch"
elif ! curl -fsSL "$DISPATCH_URL" -o "$HOOKS_DIR/dispatch"; then
    echo "⚠ Failed to download the git hook dispatcher"
    exit 1
fi
chmod +x "$HOOKS_DIR/dispatch"

local_pinact_staged="$(cd "$(dirname "$0")" && pwd)/pinact-staged"
if [ -f "$local_pinact_staged" ]; then
    cp "$local_pinact_staged" "$HOOKS_DIR/pinact-staged"
elif ! curl -fsSL "$PINACT_STAGED_URL" -o "$HOOKS_DIR/pinact-staged"; then
    echo "⚠ Failed to download the staged pinact helper"
    exit 1
fi
chmod +x "$HOOKS_DIR/pinact-staged"

skipped=()
for hook in "${HOOK_NAMES[@]}"; do
    target="$HOOKS_DIR/$hook"
    if { [ -e "$target" ] || [ -L "$target" ]; } && [ "$(readlink "$target")" != dispatch ]; then
        skipped+=("$hook")
        continue
    fi
    ln -sfn dispatch "$target"
done

if [ ${#skipped[@]} -gt 0 ]; then
    echo "⚠ Left ${#skipped[@]} pre-existing hook(s) in place: ${skipped[*]}"
    echo "  They keep running, but repository-local hooks of the same name will not."
    case " ${skipped[*]} " in
        *" post-checkout "*)
            echo "  post-checkout is one of them, so new worktrees will NOT be trusted"
            echo "  automatically; merge $HOOKS_DIR/dispatch into your own hook by hand."
            ;;
    esac
fi

current="$(git config --global --get core.hooksPath || true)"
case "$current" in
    "" | "$HOOKS_DIR")
        git config --global core.hooksPath "$HOOKS_DIR"
        echo "✓ Global git hooks installed to $HOOKS_DIR"
        ;;
    *)
        # Somebody already points core.hooksPath somewhere of their own;
        # taking it over would disable whatever lives there.
        echo "⚠ core.hooksPath already set to $current; leaving it unchanged"
        echo "  (hooks staged in $HOOKS_DIR but not active)"
        ;;
esac
