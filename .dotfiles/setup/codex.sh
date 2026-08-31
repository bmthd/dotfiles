#!/usr/bin/env bash
# `setup:codex`: install the official Codex plugin for Claude Code. Placed by
# the setup:scripts task in .mise.toml; see the comment there.
echo "📦 Setting up Codex plugin..."
if command -v claude &> /dev/null; then
    claude plugin marketplace add openai/codex-plugin-cc 2>/dev/null \
      && claude plugin install codex@openai-codex -s user 2>/dev/null \
      && echo "✓ Codex plugin installed" \
      || echo "⚠ Codex plugin installation failed (continuing)"
else
    echo "⚠ claude not found on PATH; skipping Codex plugin installation"
fi
