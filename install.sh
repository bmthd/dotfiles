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

# Activate mise for this session
eval "$(mise activate bash)"

# Install tools via mise
echo "📦 Installing node, pnpm, bun, gh, and similarity via mise..."
mise install node@latest
mise install pnpm@latest
mise install bun@latest
mise install github-cli@latest
mise install github:mizchi/similarity@latest

# Set installed versions as global defaults
mise use -g node@latest
mise use -g pnpm@latest
mise use -g bun@latest
mise use -g github-cli@latest
mise use -g github:mizchi/similarity@latest

# Install ni and playwright globally
echo "📦 Installing ni and playwright-cli..."
npm install -g @antfu/ni
npm install -g playwright-cli

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

echo ""
echo "✨ Installation complete!"
echo ""
echo "Installed versions:"
mise list
echo ""
echo "Please restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
