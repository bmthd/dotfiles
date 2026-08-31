#!/usr/bin/env bash
# `setup:update-notice`: install the shell-startup dotfiles update
# notification. Placed by the setup:scripts task in .mise.toml; see the comment
# there.
#
# The notice itself is .dotfiles/update-notice.sh, which this fetches; the two
# are different scripts with the same name in different directories.
RAW_BASE="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/bmthd/dotfiles/${DOTFILES_REF:-main}}"
DOTFILES_CONFIG_DIR="$HOME/.config/dotfiles"
UPDATE_NOTICE="$DOTFILES_CONFIG_DIR/update-notice.sh"
mkdir -p "$DOTFILES_CONFIG_DIR"
if curl -fsSL "$RAW_BASE/.dotfiles/update-notice.sh" -o "$UPDATE_NOTICE"; then
    bash "$UPDATE_NOTICE" install
    echo "✓ Dotfiles update notification installed"
else
    echo "⚠ Failed to install dotfiles update notification"
    exit 1
fi
