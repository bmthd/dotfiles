#!/usr/bin/env bash
# `setup:claude-plugins`: install official Anthropic plugins for Claude Code
# (TypeScript LSP). Placed by the setup:scripts task in .mise.toml; see the
# comment there.
echo "📦 Setting up official Claude Code plugins..."
if ! command -v claude &> /dev/null; then
    echo "⚠ claude not found on PATH; skipping official plugin installation"
    exit 0
fi

# 公式マーケットプレイスは登録済みでも add は失敗しないが、念のため結果を握り潰す
claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true

# インストール対象の公式プラグイン。増やす場合はここに追記する
OFFICIAL_PLUGINS=(
    typescript-lsp
)
for plugin in "${OFFICIAL_PLUGINS[@]}"; do
    claude plugin install "$plugin@claude-plugins-official" -s user 2>/dev/null \
      && echo "✓ $plugin installed" \
      || echo "⚠ $plugin installation failed (continuing)"
done
