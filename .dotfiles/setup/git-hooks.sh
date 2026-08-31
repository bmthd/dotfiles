#!/usr/bin/env bash
# `setup:git-hooks`: install the global git hooks that trust mise configs in
# new worktrees. Placed by the setup:scripts task in .mise.toml; see the
# comment there.
RAW_BASE="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/bmthd/dotfiles/${DOTFILES_REF:-main}}"
INSTALLER="$(mktemp)"
# The installer downloads dispatch and pinact-staged itself, so hand it the
# same base rather than letting it fall back to main on its own.
export DOTFILES_RAW_BASE="$RAW_BASE"
if curl -fsSL "$RAW_BASE/.dotfiles/git-hooks/install.sh" -o "$INSTALLER"; then
    bash "$INSTALLER"
else
    echo "⚠ Failed to download the git hook installer"
    rm -f "$INSTALLER"
    exit 1
fi
rm -f "$INSTALLER"
