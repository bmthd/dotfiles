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

# Setup Claude Code settings
echo "📦 Setting up Claude Code configuration..."
mkdir -p "$HOME/.claude/skills"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.claude/settings.json -o "$HOME/.claude/settings.json"

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
for skill in $(curl -fsSL https://api.github.com/repos/bmthd/dotfiles/contents/.agents/skills | jq -r '.[].name'); do
  mkdir -p "$HOME/.claude/skills/$skill" "$HOME/.config/opencode/skills/$skill"
  curl -fsSL "https://raw.githubusercontent.com/bmthd/dotfiles/main/.agents/skills/$skill/SKILL.md" \
    -o "$HOME/.claude/skills/$skill/SKILL.md"
  cp "$HOME/.claude/skills/$skill/SKILL.md" "$HOME/.config/opencode/skills/$skill/SKILL.md"
  echo "✓ $skill skill installed"
done

# Install third-party skills
npx skills add obra/superpowers -y -g -a claude-code -a opencode
echo "✓ superpowers skills installed"

echo ""
echo "✨ Installation complete!"
echo ""
echo "Installed versions:"
mise list
echo ""
echo "Please restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
