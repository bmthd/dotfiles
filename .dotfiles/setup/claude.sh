#!/usr/bin/env bash
# `setup:claude`: install Claude Code plus its settings.json and status line.
# Placed by the setup:scripts task in .mise.toml; see the comment there.

# Install Claude Code via the official installer (not mise/npm, which cannot
# complete the native binary postinstall)
if ! command -v claude &> /dev/null; then
    echo "📦 Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        echo "✓ Claude Code installed"
    else
        echo "⚠ Claude Code installation failed; skipping"
    fi
else
    echo "✓ Claude Code is already installed"
fi

echo "📦 Setting up Claude Code configuration..."
RAW_BASE="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/bmthd/dotfiles/${DOTFILES_REF:-main}}"
mkdir -p "$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REMOTE_SETTINGS="$(mktemp)"
if curl -fsSL "$RAW_BASE/.claude/settings.json" -o "$REMOTE_SETTINGS"; then
    if [ -f "$CLAUDE_SETTINGS" ] && command -v jq &> /dev/null; then
        # Deep-merge settings, preserving array order (remote wins on scalars)
        MERGED_SETTINGS="$(mktemp)"
        if jq -s --arg prefer remote '
          def m($a; $b; $has_a; $has_b):
            if ($a | type) == "object" and ($b | type) == "object" then
              reduce ($b | keys_unsorted[]) as $k
                ($a; .[$k] = m($a[$k]; $b[$k]; $a | has($k); true))
            elif ($a | type) == "array" and ($b | type) == "array" then
              reduce (($a + $b)[]) as $item
                ([]; if index($item) == null then . + [$item] else . end)
            elif $prefer == "local" and $has_a then $a
            elif $prefer == "remote" and $has_b then $b
            elif $has_a then $a
            else $b
            end;
          m(.[0]; .[1]; true; true)
        ' "$CLAUDE_SETTINGS" "$REMOTE_SETTINGS" > "$MERGED_SETTINGS" 2>/dev/null; then
            mv "$MERGED_SETTINGS" "$CLAUDE_SETTINGS"
            echo "✓ Merged Claude Code settings into existing $CLAUDE_SETTINGS"
        else
            rm -f "$MERGED_SETTINGS"
            echo "⚠ Failed to merge settings; keeping existing $CLAUDE_SETTINGS unchanged"
        fi
    else
        mv "$REMOTE_SETTINGS" "$CLAUDE_SETTINGS"
        echo "✓ Installed Claude Code settings to $CLAUDE_SETTINGS"
    fi
else
    echo "⚠ Failed to download Claude Code settings"
    rm -f "$REMOTE_SETTINGS"
    exit 1
fi
rm -f "$REMOTE_SETTINGS"

if curl -fsSL "$RAW_BASE/.claude/statusline.sh" -o "$HOME/.claude/statusline.sh"; then
    chmod +x "$HOME/.claude/statusline.sh"
    echo "✓ Claude Code status line installed"
else
    echo "⚠ Failed to download Claude Code status line"
    exit 1
fi
