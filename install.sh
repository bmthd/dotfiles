#!/bin/bash

set -e

echo "🚀 Installing development tools..."

# Install mise
if ! command -v mise &> /dev/null; then
    echo "📦 Installing mise..."
    curl https://mise.run | sh

    # Add mise to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
else
    echo "✓ mise is already installed"
fi

# Download mise config
echo "📦 Setting up mise configuration..."
mkdir -p "$HOME/.config/mise"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.mise.toml -o "$HOME/.config/mise/config.toml"
# Note: .mise.toml uses @playwright/cli (playwright-cli is deprecated)

# Activate mise for this session
eval "$(mise activate bash)"

# Install tools via mise
echo "📦 Installing all tools via mise..."
mise install

# Setup shell integration
SHELL_CONFIG=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
fi

if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q 'mise activate' "$SHELL_CONFIG" 2>/dev/null; then
        echo "" >> "$SHELL_CONFIG"
        echo "# mise activation" >> "$SHELL_CONFIG"
        echo 'eval "$(mise activate bash)"' >> "$SHELL_CONFIG"
        echo "✓ Added mise activation to $SHELL_CONFIG"
    else
        echo "✓ mise activation already in $SHELL_CONFIG"
    fi
fi

# Setup Claude Code settings and skills
echo "📦 Setting up Claude Code configuration..."
mkdir -p "$HOME/.claude/skills"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.claude/settings.json -o "$HOME/.claude/settings.json"

# Install worktree skill for Claude Code
mkdir -p "$HOME/.claude/skills/worktree"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.agents/skills/worktree/SKILL.md -o "$HOME/.claude/skills/worktree/SKILL.md"
echo "✓ worktree skill installed for Claude"

# Install difit skills for Claude Code
npx skills add yoshiko-pg/difit
echo "✓ difit skills installed for Claude"

# Link playwright-cli skill from installed @playwright/cli package
PLAYWRIGHT_CLI_SKILLS=$(mise exec -- node -e "console.log(require.resolve('@playwright/cli/package.json'))" 2>/dev/null | xargs dirname)/skills/playwright-cli
if [ -d "$PLAYWRIGHT_CLI_SKILLS" ]; then
    ln -sfn "$PLAYWRIGHT_CLI_SKILLS" "$HOME/.claude/skills/playwright-cli"
    echo "✓ playwright-cli skill linked"
else
    echo "⚠ playwright-cli skill not found, skipping"
fi

# Setup OpenCode skills
echo "📦 Setting up OpenCode configuration..."
mkdir -p "$HOME/.config/opencode/skills/worktree"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.agents/skills/worktree/SKILL.md -o "$HOME/.config/opencode/skills/worktree/SKILL.md"
echo "✓ worktree skill installed for OpenCode"

# Install difit skills for OpenCode
npx skills add yoshiko-pg/difit
echo "✓ difit skills installed for OpenCode"

echo ""
echo "✨ Installation complete!"
echo ""
echo "Installed versions:"
mise list
echo ""
echo "Please restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
