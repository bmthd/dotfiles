#!/bin/bash

echo "🚀 Installing development tools..."

# Detect which shell this script is running under (bash or zsh).
# Run with `| bash` or `| zsh` to choose which shell to configure.
if [ -n "$ZSH_VERSION" ]; then
    CURRENT_SHELL="zsh"
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    CURRENT_SHELL="bash"
    SHELL_CONFIG="$HOME/.bashrc"
else
    CURRENT_SHELL="bash"
    SHELL_CONFIG="$HOME/.bashrc"
fi
echo "🐚 Configuring for $CURRENT_SHELL ($SHELL_CONFIG)"

# Install mise
if ! command -v mise &> /dev/null; then
    echo "📦 Installing mise..."
    if ! curl https://mise.run | sh; then
        echo "⚠ mise installation failed; skipping"
    fi

    # Add mise to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
else
    echo "✓ mise is already installed"
fi

# Download mise config
echo "📦 Setting up mise configuration..."
mkdir -p "$HOME/.config/mise"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.mise.toml -o "$HOME/.config/mise/config.toml" \
  || echo "⚠ Failed to download mise config"
# Note: .mise.toml uses @playwright/cli (playwright-cli is deprecated)

# Activate mise for this session
if command -v mise &> /dev/null; then
    eval "$(mise activate "$CURRENT_SHELL")" || true

    # Install jq first so it's available for later steps
    echo "📦 Installing jq..."
    mise install jq 2>/dev/null || echo "⚠ Failed to install jq via mise"

    # Install remaining tools via mise
    echo "📦 Installing all tools via mise..."
    mise install || echo "⚠ Some mise tools failed to install (continuing)"
fi

# Setup shell integration for the detected shell
if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q 'mise activate' "$SHELL_CONFIG" 2>/dev/null; then
        echo "" >> "$SHELL_CONFIG"
        echo "# mise activation" >> "$SHELL_CONFIG"
        echo "eval \"\$(mise activate $CURRENT_SHELL)\"" >> "$SHELL_CONFIG"
        echo "✓ Added mise activation to $SHELL_CONFIG"
    else
        echo "✓ mise activation already in $SHELL_CONFIG"
    fi
fi

# Install Claude Code via the official installer (not mise/npm, which cannot
# complete the native binary postinstall)
if ! command -v claude &> /dev/null; then
    echo "📦 Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        export PATH="$HOME/.local/bin:$PATH"
        echo "✓ Claude Code installed"
    else
        echo "⚠ Claude Code installation failed; skipping"
    fi
else
    echo "✓ Claude Code is already installed"
fi

# Setup Claude Code settings
echo "📦 Setting up Claude Code configuration..."
mkdir -p "$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REMOTE_SETTINGS="$(mktemp)"
if curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.claude/settings.json -o "$REMOTE_SETTINGS"; then
    if [ -f "$CLAUDE_SETTINGS" ] && command -v jq &> /dev/null; then
        # Deep-merge remote settings into existing ones (remote wins on conflicts)
        MERGED_SETTINGS="$(mktemp)"
        if jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS" "$REMOTE_SETTINGS" > "$MERGED_SETTINGS" 2>/dev/null; then
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
fi
rm -f "$REMOTE_SETTINGS"
if curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.claude/statusline.sh -o "$HOME/.claude/statusline.sh"; then
    chmod +x "$HOME/.claude/statusline.sh"
    echo "✓ Claude Code status line installed"
else
    echo "⚠ Failed to download Claude Code status line"
fi

# Setup OpenCode
echo "📦 Setting up OpenCode configuration..."
mkdir -p "$HOME/.config/opencode/skills"

# Install skills via the `skills` CLI — one mechanism for every source.
# Own skills live in this repo's .agents/skills/; third-party skills come from
# their upstream repos. grill-me pulls only grill-me + its grilling dependency.
# Update any of them later with `npx skills update`.
echo "📦 Installing skills..."
install_skills() {
    local label="$1"; shift
    npx skills add "$@" -y -g -a claude-code -a opencode 2>/dev/null \
      && echo "✓ $label skills installed" \
      || echo "⚠ $label skills installation failed (continuing)"
}
install_skills "own" bmthd/dotfiles
install_skills "superpowers" obra/superpowers
install_skills "grill-me" mattpocock/skills -s grill-me -s grilling

# Install official Codex plugin for Claude Code
echo "📦 Setting up Codex plugin..."
if command -v claude &> /dev/null; then
    claude plugin marketplace add openai/codex-plugin-cc 2>/dev/null \
      && claude plugin install codex@openai-codex -s user 2>/dev/null \
      && echo "✓ Codex plugin installed" \
      || echo "⚠ Codex plugin installation failed (continuing)"
else
    echo "⚠ claude not found on PATH; skipping Codex plugin installation"
fi

echo ""
echo "✨ Installation complete!"
echo ""
echo "Installed versions:"
if command -v mise &> /dev/null; then
    mise list || true
fi
echo ""
echo "Please restart your shell or run: source $SHELL_CONFIG"
