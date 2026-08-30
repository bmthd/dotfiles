#!/bin/bash

# Thin bootstrapper: installs mise, places the mise config, and hands the
# rest of the setup over to mise (`mise install` + `mise run setup`).
# All tool definitions and setup logic live in .mise.toml.

echo "🚀 Bootstrapping dotfiles..."

# Every step below keeps going on failure so that one broken piece does not
# leave the rest of the machine unconfigured. That is only honest if the script
# says so at the end, hence the tally: each recovered failure is recorded here
# and reported, with a non-zero exit, once everything else has run.
FAILURES=0
FAILED_ITEMS=""

record_failure() {
    FAILURES=$((FAILURES + 1))
    FAILED_ITEMS="${FAILED_ITEMS}  - $1
"
}

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

# Resolve the repository to one commit, once, and install everything from it.
#
# Every file below — the mise config, the lockfile that pins its tools, the
# update notice, and the files the setup tasks in .mise.toml fetch — used to be
# downloaded from `main` independently. A merge landing mid-installation was
# therefore enough to produce a machine whose config.toml, mise.lock and
# statusline came from three different commits, with nothing saying so. Worse,
# `~/.config/dotfiles/revision` (written at the end of this script) is the
# common ancestor that `/dotfiles apply` 3-way merges against: if it names a
# commit no single installed file came from, the merge base is a fiction.
#
# Set DOTFILES_REF to install from another branch, tag, or commit — it is
# resolved to a SHA the same way, so the pin holds for debugging installs too.
DOTFILES_REPO="${DOTFILES_REPO:-bmthd/dotfiles}"
DOTFILES_REF="${DOTFILES_REF:-main}"

# `Accept: application/vnd.github.sha` makes the commits API answer with the
# bare SHA as text, so this needs no jq — mise has not installed one yet at this
# point. --max-time because the whole installation waits on this one call, and a
# captive portal or a half-dead link would otherwise hang it indefinitely.
echo "📌 Resolving $DOTFILES_REPO@$DOTFILES_REF..."
DOTFILES_REVISION="$(curl -fsSL --max-time 10 \
    -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/$DOTFILES_REPO/commits/$DOTFILES_REF" 2> /dev/null)" \
    || DOTFILES_REVISION=""
case "$DOTFILES_REVISION" in
    "" | *[!0-9a-f]*) DOTFILES_REVISION="" ;;
esac

# Unresolvable is a warning, not an abort — unlike the missing lockfile below.
# The lockfile is a security control: without it the two-day release-age gate is
# silently bypassed, so continuing would install something weaker than promised.
# Here, falling back to the branch name installs exactly what every release
# before this one installed; only the atomicity guarantee is lost, and it is
# lost loudly. The API is also the one unauthenticated GitHub endpoint here with
# a 60-per-hour limit, so a shared NAT or a busy CI runner can exhaust it — that
# must not be able to make the installer refuse to run.
if [ -n "$DOTFILES_REVISION" ]; then
    echo "✓ Installing from ${DOTFILES_REVISION:0:7}"
else
    # Recorded, not fatal. The installation still runs to the end, but an
    # unpinned install is a degraded one — the summary and the exit code are
    # the only places that can say so, and staying silent here is exactly the
    # "half-broken but exit 0" behaviour the tally was added to remove. The
    # record_failure call sits directly under the warning because
    # tests/install-order-test.sh pairs the two by adjacency.
    echo "⚠ Could not resolve $DOTFILES_REF to a commit SHA; falling back to it as a ref."
    record_failure "revision pinning (fell back to $DOTFILES_REF)"
    echo "  Files are fetched individually, so a push during this installation"
    echo "  can leave this machine on a mix of commits."
fi

# The single source of every download URL below. Exported because the setup
# tasks in .mise.toml fetch from the repository too and must use this same
# revision; `mise run` passes the environment through to them.
DOTFILES_RAW_BASE="https://raw.githubusercontent.com/$DOTFILES_REPO/${DOTFILES_REVISION:-$DOTFILES_REF}"
export DOTFILES_RAW_BASE
# Read by update-notice.sh's `install`, which records what this machine carries.
export DOTFILES_REVISION

# Install mise
if ! command -v mise &> /dev/null; then
    echo "📦 Installing mise..."
    # pipefail is set inside a subshell rather than globally: the exit status of
    # `curl | sh` is `sh`'s, so without it a 404 page piped into a shell that
    # happily does nothing would read as success. Scoping it to this pipeline
    # keeps the rest of the script's behaviour untouched, and both bash and zsh
    # accept `set -o pipefail`.
    if ! (set -o pipefail; curl -fsSL https://mise.run | sh); then
        echo "⚠ mise installation failed; skipping"
        record_failure "mise installation"
    fi

    # Add mise to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
else
    echo "✓ mise is already installed"
fi

# Download mise config (tools + setup tasks)
echo "📦 Setting up mise configuration..."
mkdir -p "$HOME/.config/mise"
# Downloads land in a temp file and are moved into place only once curl has
# succeeded. `curl -f -o dest` still creates (and partially fills) dest before it
# gives up on an error response, so writing straight to the destination turns a
# failed download into a truncated config that later runs would happily read.
MISE_CONFIG_TMP="$(mktemp)"
if curl -fsSL "$DOTFILES_RAW_BASE/.mise.toml" -o "$MISE_CONFIG_TMP"; then
    mv "$MISE_CONFIG_TMP" "$HOME/.config/mise/config.toml"
else
    rm -f "$MISE_CONFIG_TMP"
    echo "⚠ Failed to download mise config"
    record_failure "mise config download"
fi

# The lockfile that goes with it, and this one is not optional. config.toml
# declares every tool as `latest`; the lockfile is what turns that into an exact
# version and checksum. Without it `mise install` would resolve `latest` at run
# time and install whatever was published minutes ago, skipping the two-day
# release-age gate entirely — so a missing lockfile is a failure, not a warning.
# mise never creates a global lockfile on its own (only `mise lock --global`
# does), which is why it ships with the repo.
# Same temp-file dance, and here it is the whole point: an empty
# ~/.config/mise/mise.lock left behind by a failed download is worse than none at
# all, because a later `mise install` would find a lockfile, pin nothing, and
# resolve `latest` with neither the release-age gate nor checksum verification.
MISE_LOCK_TMP="$(mktemp)"
if curl -fsSL "$DOTFILES_RAW_BASE/mise.lock" -o "$MISE_LOCK_TMP"; then
    mv "$MISE_LOCK_TMP" "$HOME/.config/mise/mise.lock"
else
    rm -f "$MISE_LOCK_TMP"
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
    mise run --skip-tools setup:npm-registry || {
        echo "⚠ Failed to configure npm registry (continuing)"
        record_failure "npm registry configuration"
    }

    # Current mise resolves OCI through vfox. Replace the legacy asdf plugin
    # that older dotfiles installations left under the same plugin name before
    # mise tries to load it as Lua.
    echo "📦 Configuring OCI plugin..."
    mise run --skip-tools setup:oci-plugin || {
        echo "⚠ Failed to configure OCI plugin (continuing)"
        record_failure "OCI plugin configuration"
    }

    # Install all tools via mise
    echo "📦 Installing all tools via mise..."
    mise install || {
        echo "⚠ Some mise tools failed to install (continuing)"
        record_failure "mise install"
    }

    # Run the setup tasks defined in .mise.toml
    # (Claude Code + settings, agent skills, Codex plugin)
    echo "📦 Running setup tasks via mise..."
    mise run setup || {
        echo "⚠ Some setup tasks failed (continuing)"
        record_failure "mise run setup"
    }
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
    if curl -fsSL "$DOTFILES_RAW_BASE/.dotfiles/update-notice.sh" -o "$UPDATE_NOTICE"; then
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
        record_failure "dotfiles update notification"
    fi
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "✨ Installation complete!"
else
    echo "✗ Installation finished with $FAILURES failed step(s):"
    printf '%s' "$FAILED_ITEMS"
fi
echo ""
echo "Installed versions:"
if command -v mise &> /dev/null; then
    mise list || true
fi
echo ""
echo "Please restart your shell or run: source $SHELL_CONFIG"

# Exit last so that a partial install still prints everything above, but never
# reports success: CI and humans alike only have the exit code to go on.
if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
