#!/usr/bin/env bash
# `setup:codex`: install the official Codex plugin for Claude Code. Placed by
# the setup:scripts task in .mise.toml; see the comment there.
codex_config="$HOME/.codex/config.toml"

mkdir -p "$(dirname "$codex_config")"
codex_config_tmp="$(mktemp "${codex_config}.XXXXXX")"
if [ -f "$codex_config" ]; then
    awk '
        /^[[:space:]]*\[/ && !inserted {
            print "check_for_update_on_startup = false"
            inserted = 1
        }
        !inserted && /^[[:space:]]*check_for_update_on_startup[[:space:]]*=/ {
            print "check_for_update_on_startup = false"
            inserted = 1
            next
        }
        { print }
        END {
            if (!inserted) print "check_for_update_on_startup = false"
        }
    ' "$codex_config" > "$codex_config_tmp"
else
    printf '%s\n' 'check_for_update_on_startup = false' > "$codex_config_tmp"
fi
mv "$codex_config_tmp" "$codex_config"

echo "✓ Disabled Codex startup update checks"
echo "📦 Setting up Codex plugin..."
if command -v claude &> /dev/null; then
    claude plugin marketplace add openai/codex-plugin-cc 2>/dev/null \
      && claude plugin install codex@openai-codex -s user 2>/dev/null \
      && echo "✓ Codex plugin installed" \
      || echo "⚠ Codex plugin installation failed (continuing)"
else
    echo "⚠ claude not found on PATH; skipping Codex plugin installation"
fi
