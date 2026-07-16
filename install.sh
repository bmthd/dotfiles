#!/bin/bash

# Thin bootstrapper: installs mise, places the mise config, and hands the
# rest of the setup over to mise (`mise install` + `mise run setup`).
# All tool definitions and setup logic live in .mise.toml.

echo "🚀 Bootstrapping dotfiles..."

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

# Download mise config (tools + setup tasks)
echo "📦 Setting up mise configuration..."
mkdir -p "$HOME/.config/mise"
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.mise.toml -o "$HOME/.config/mise/config.toml" \
  || echo "⚠ Failed to download mise config"

if command -v mise &> /dev/null; then
    # Activate mise for this session
    eval "$(mise activate "$CURRENT_SHELL")" || true

    # Install all tools via mise
    echo "📦 Installing all tools via mise..."
    mise install || echo "⚠ Some mise tools failed to install (continuing)"

    # Run the setup tasks defined in .mise.toml
    # (Claude Code + settings, agent skills, Codex plugin)
    echo "📦 Running setup tasks via mise..."
    mise run setup || echo "⚠ Some setup tasks failed (continuing)"
fi

# Setup shell integration for the detected shell
if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q 'mise activate' "$SHELL_CONFIG" 2>/dev/null; then
        {
            echo ""
            echo "# mise activation"
            echo "eval \"\$(mise activate $CURRENT_SHELL)\""
        } >> "$SHELL_CONFIG"
        echo "✓ Added mise activation to $SHELL_CONFIG"
    else
        echo "✓ mise activation already in $SHELL_CONFIG"
    fi
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
