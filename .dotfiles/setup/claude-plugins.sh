#!/usr/bin/env bash
# `setup:claude-plugins`: install Claude Code plugins — official Anthropic ones
# (TypeScript LSP) and pstack. Placed by the setup:scripts task in .mise.toml;
# see the comment there.
echo "📦 Setting up Claude Code plugins..."
if ! command -v claude &> /dev/null; then
    echo "⚠ claude not found on PATH; skipping plugin installation"
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

# pstack is published by Cursor, in the cursor/plugins marketplace. Its Claude
# Code tree is generated upstream from the Cursor plugin and carries the
# poteto-agent and comment-sicko subagents that poteto-mode and no-comments
# delegate to, which is why nothing else installs them for Claude Code. The
# other agents get the same skills from setup:skills.
#
# SECURITY: like a skill, a plugin is unpinned Markdown loaded straight into an
# agent's context; treat `claude plugin update` as a change to review.
claude plugin marketplace add cursor/plugins 2>/dev/null || true
if claude plugin install pstack@cursor-plugins -s user 2>/dev/null; then
    echo "✓ pstack installed"
    # Machines set up before the plugin existed carry pstack in Claude Code the
    # old way: skills symlinked into ~/.claude/skills and the two subagents
    # copied into ~/.claude/agents. Left there, Claude Code shows each skill
    # twice, bare and as /pstack:<name>, so take them off — only now that the
    # plugin is in place, so a failed install never leaves Claude Code with
    # neither. The names come from the installed plugin rather than the skills
    # CLI's lock file, which does not record every skill it installs. Unlink by
    # hand, and only symlinks into ~/.agents/skills: `skills remove -a
    # claude-code` deletes that shared canonical copy as well, taking the skills
    # away from the agents setup:skills still installs them for. node is there
    # because claude is. On a machine without the old install this is a no-op.
    pstack_dir="$(claude plugin list --json 2>/dev/null | node -e '
let input = "";
process.stdin.on("data", (chunk) => (input += chunk)).on("end", () => {
    const plugin = JSON.parse(input).find((p) => p.id === "pstack@cursor-plugins");
    if (plugin) console.log(plugin.installPath);
});' 2>/dev/null)"
    if [ -n "$pstack_dir" ] && [ -d "$pstack_dir/skills" ]; then
        for skill in "$pstack_dir"/skills/*/; do
            name="$(basename "$skill")"
            link="$HOME/.claude/skills/$name"
            if [ -L "$link" ] && [[ "$(readlink "$link")" == *".agents/skills/$name" ]]; then
                rm -f "$link"
            fi
        done
    fi
    rm -f "$HOME/.claude/agents/poteto-agent.md" "$HOME/.claude/agents/comment-sicko.md"
else
    echo "⚠ pstack installation failed (continuing)"
fi
