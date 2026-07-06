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

echo "📦 Setting up RTK hooks..."
if command -v rtk &> /dev/null; then
  rtk init -g --auto-patch || echo "⚠ RTK Claude Code hook setup failed"
  rtk init -g --opencode --auto-patch || echo "⚠ RTK OpenCode hook setup failed"
  echo "✓ RTK hooks installed"
else
  echo "⚠ rtk not found on PATH; skipping hook setup"
fi

# Install all skills from .agents/skills/
echo "📦 Installing skills..."
if command -v jq &> /dev/null; then
    SKILLS=$(curl -fsSL https://api.github.com/repos/bmthd/dotfiles/contents/.agents/skills 2>/dev/null | jq -r '.[].name' 2>/dev/null) || SKILLS=""
    if [ -n "$SKILLS" ]; then
        for skill in $SKILLS; do
            mkdir -p "$HOME/.claude/skills/$skill" "$HOME/.config/opencode/skills/$skill"
            if curl -fsSL "https://raw.githubusercontent.com/bmthd/dotfiles/main/.agents/skills/$skill/SKILL.md" \
                -o "$HOME/.claude/skills/$skill/SKILL.md" 2>/dev/null; then
                cp "$HOME/.claude/skills/$skill/SKILL.md" "$HOME/.config/opencode/skills/$skill/SKILL.md"
                echo "✓ $skill skill installed"
            else
                echo "⚠ Failed to install $skill skill"
            fi
        done
    else
        echo "⚠ Could not fetch skills list from GitHub"
    fi
else
    echo "⚠ jq not found; skipping skills installation"
fi

# Install third-party skills
npx skills add obra/superpowers -y -g -a claude-code -a opencode 2>/dev/null \
  && echo "✓ superpowers skills installed" \
  || echo "⚠ superpowers skills installation failed (continuing)"

# Install grill-me (and its grilling dependency) via the official `gh skill`
# command (gh >= 2.92.0). This keeps mattpocock/skills as the source of truth:
# `gh skill install` injects source-tracking metadata so `gh skill update` can
# later pull upstream changes. grill-me's body is just "Run a /grilling session",
# so grilling must be installed alongside it. Exact paths skip full-tree
# discovery. --scope user maps to ~/.claude/skills and ~/.config/opencode/skills.
echo "📦 Installing grill-me skills..."
if command -v gh &> /dev/null; then
    for agent in claude-code opencode; do
        gh skill install mattpocock/skills skills/productivity/grill-me --agent "$agent" --scope user --force 2>/dev/null \
          && gh skill install mattpocock/skills skills/productivity/grilling --agent "$agent" --scope user --force 2>/dev/null \
          && echo "✓ grill-me skills installed for $agent" \
          || echo "⚠ grill-me skills installation failed for $agent (continuing)"
    done
else
    echo "⚠ gh not found on PATH; skipping grill-me skills installation"
fi

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
