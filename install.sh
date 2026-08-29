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

# The lockfile that goes with it, and this one is not optional. config.toml
# declares every tool as `latest`; the lockfile is what turns that into an exact
# version and checksum. Without it `mise install` would resolve `latest` at run
# time and install whatever was published minutes ago, skipping the two-day
# release-age gate entirely — so a missing lockfile is a failure, not a warning.
# mise never creates a global lockfile on its own (only `mise lock --global`
# does), which is why it ships with the repo.
if ! curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/mise.lock -o "$HOME/.config/mise/mise.lock"; then
    echo "✗ Failed to download mise lockfile."
    echo "  Aborting: installing without it would bypass the release-age gate"
    echo "  and pull unverified latest versions."
    exit 1
fi

if command -v mise &> /dev/null; then
    # Activate mise for this session
    eval "$(mise activate "$CURRENT_SHELL")" || true

    # Point npm at the malware-blocking proxy before anything is installed:
    # the `npm:` tools and the postinstall hooks that call `npx` all resolve
    # through it.
    #
    # --skip-tools is what makes "before" true. `mise run` installs the entire
    # tool set before it runs any task, whether or not the task needs it, so
    # without the flag this line pulls every `npm:` tool from the default
    # registry and only then writes ~/.npmrc — exactly backwards. The task body
    # is plain shell (touch/sed/grep), so skipping the tools costs it nothing.
    echo "📦 Configuring npm registry..."
    mise run --skip-tools setup:npm-registry || echo "⚠ Failed to configure npm registry (continuing)"

    # Current mise resolves OCI through vfox. Replace the legacy asdf plugin
    # that older dotfiles installations left under the same plugin name before
    # mise tries to load it as Lua.
    echo "📦 Configuring OCI plugin..."
    mise run --skip-tools setup:oci-plugin || echo "⚠ Failed to configure OCI plugin (continuing)"

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

    UPDATE_NOTICE="$HOME/.config/dotfiles/update-notice.sh"
    mkdir -p "$HOME/.config/dotfiles"
    if curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/.dotfiles/update-notice.sh -o "$UPDATE_NOTICE"; then
        if ! grep -q 'dotfiles/update-notice.sh' "$SHELL_CONFIG" 2>/dev/null; then
            {
                echo ""
                echo "# dotfiles update notification"
                echo "source \"$UPDATE_NOTICE\""
            } >> "$SHELL_CONFIG"
            echo "✓ Added dotfiles update notification to $SHELL_CONFIG"
        fi
        bash "$UPDATE_NOTICE" install
    else
        echo "⚠ Failed to install dotfiles update notification"
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
