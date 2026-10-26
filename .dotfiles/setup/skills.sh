#!/usr/bin/env bash
# `setup:skills`: install agent skills for Claude Code, OpenCode, Cursor,
# Codex, and Gemini CLI.
# Placed by the setup:scripts task in .mise.toml; see the comment there.
#
# The `npx skills add` calls below must resolve through the Takumi Guard proxy,
# which is why the task declares setup:npm-registry as a dependency rather than
# relying on the order of the parent task's depends list.

# Skill directories for each agent CLI. Cursor, Codex and Gemini CLI are
# "universal" agents to the skills CLI: they all read ~/.agents/skills, which is
# also where it puts a skill for OpenCode, so the one directory covers all four
# and only Claude Code gets a tree of its own (symlinks into ~/.agents/skills).
# That is why adding gemini-cli below needs no new mkdir: nothing lands in
# ~/.gemini.
mkdir -p "$HOME/.claude/skills" "$HOME/.config/opencode/skills" "$HOME/.agents/skills"

# Install skills via the `skills` CLI — one mechanism for every source.
# Own skills live in bmthd/skills, split out of the dotfiles repository so they
# can be shared on their own. What stays in that repository's .agents/skills/ is
# what does not belong anywhere else: the dotfiles skill, which only makes sense
# against it. Third-party skills come from their upstream repos. productivity
# pulls all skills from Matt Pocock's upstream productivity skills folder.
# mathbullet contributes html and explain, two of the skills html's SKILL.md
# recommends using together. The other two it recommends, k16shikano's
# japanese-tech-writing and cognitive-rhythm-writing gists, are deliberately not
# installed; see the yomiyasu line below.
# Update any of them later with `npx skills update`.
#
# SECURITY: these are the one dependency here that nothing checks. A skill is
# Markdown that is loaded straight into every agent's context, so a compromised
# one is a prompt-injection channel, not just a malicious package — and the
# skills CLI has no way to pin a revision (`skills add` takes no ref, and the
# skills-lock.json restore path is experimental and project-scoped). Treat
# `npx skills update` as a change to review, not to run unattended.
echo "📦 Installing skills..."
install_skills() {
    local label="$1"; shift
    npx skills add "$@" -y -g -a claude-code -a opencode -a cursor -a codex -a gemini-cli 2>/dev/null \
      && echo "✓ $label skills installed" \
      || echo "⚠ $label skills installation failed (continuing)"
}
install_skills "own" bmthd/skills
# the dotfiles skill (pr / apply) targets the dotfiles repository, so it still
# lives there
install_skills "dotfiles-local" bmthd/dotfiles
install_skills "superpowers" obra/superpowers
install_skills "productivity" https://github.com/mattpocock/skills/tree/main/skills/productivity -s '*'
install_skills "mathbullet" mathbullet/skills -s html -s explain
# Orca (the parallel-agent ADE) ships its skills in the app's own repo. The CLI
# itself is not installable here — it comes from the desktop app, or over the
# SSH relay on a VPS — but the skills teach an agent to drive it, so install
# them all and let the ones for absent features simply never trigger.
install_skills "orca" stablyai/orca -s '*'
# hunk ships four skills; only hunk-review drives a review session from an agent
install_skills "hunk" modem-dev/hunk -s hunk-review
# show-me teaches an agent to answer with a diagram, a call tree or a small HTML
# view instead of a wall of prose. humanlayer publishes it as a Claude Code
# plugin — the repository is a marketplace and each skill sits at
# plugins/<name>/skills/<name>/ — but the skills CLI finds it from the
# repository root all the same, so the plain owner/repo source works and every
# agent gets it, not just Claude Code. The selector is what matters here: the
# marketplace carries several unrelated plugins.
install_skills "show-me" humanlayer/skills -s show-me
# eli5 answers a question with an HTML picture explainer — big visuals, few
# words, no assumed background. Anthropic publishes it in the community plugin
# marketplace, which is a marketplace of references first: its manifest lists a
# few thousand plugins that live in other repositories, and only a handful,
# eli5 among them, are vendored in the repository itself. Source the plugin's
# own skills directory rather than the repository root, so what is installed is
# that one plugin and not whatever else the marketplace happens to carry.
install_skills "eli5" https://github.com/anthropics/claude-plugins-community/tree/main/eli5/skills -s eli5
# security-audit is Cloudflare's source-first audit workflow (recon, coverage
# ledger, isolated hunters, independent verifiers). It stays in guidance mode
# unless a full audit is explicitly asked for, so loading it on an ordinary
# security question does not start writing report files. Its two validators
# are zero-dependency Node scripts (fs/path only) that run from the skill
# directory.
install_skills "security-audit" cloudflare/security-audit-skill -s security-audit
# pstack: Claude Code gets it as a plugin (setup:claude-plugins installs it
# from the cursor/plugins marketplace, agents included), so the skills CLI
# installs it for every other agent only — linking it into ~/.claude/skills
# as well would show Claude Code each skill twice, once bare and once as
# /pstack:<name>. Take all of them: poteto-mode is the entry point and its
# inline Principles index navigates to the 21 principle-* skills by name, so a
# subset leaves it pointing at skills that are not there.
npx skills add https://github.com/cursor/plugins/tree/main/pstack/skills -s '*' \
    -y -g -a opencode -a cursor -a codex -a gemini-cli 2>/dev/null \
  && echo "✓ pstack skills installed" \
  || echo "⚠ pstack skills installation failed (continuing)"
# yomiyasu rewrites AI-flavoured Japanese by restoring who-did-what sentence
# structure rather than swapping banned words:
# https://zenn.dev/algoartis/articles/0b1c731881b25c
# The repository carries the same SKILL.md twice, at its root and under
# skills/yomiyasu/, so select it by name to get one copy.
install_skills "yomiyasu" nanaism/yomiyasu -s yomiyasu
# yomiyasu's SKILL.md warns that other Japanese style skills active alongside it
# make its output erratic, so it replaces the two that used to be installed
# here, japanese-tech-writing and cognitive-rhythm-writing. Dropping their
# install lines does not take them off a machine that already has them, so
# remove them explicitly; on a machine without them this is a no-op.
npx skills remove japanese-tech-writing cognitive-rhythm-writing -g -y >/dev/null 2>&1 || true

# Record which revision of bmthd/skills this machine now carries, so the
# shell-startup notice can tell when that repository has moved on. `skills add`
# takes no ref, so the head at this moment is the closest thing to "the revision
# we installed" that exists — and recording it here is also what stops the
# notice from firing again once an update has been applied.
#
# On a first install the notice script is not in place yet (setup:update-notice
# puts it there, and mise may run the two in either order). That is harmless:
# its own install step records every watched repository.
UPDATE_NOTICE="$HOME/.config/dotfiles/update-notice.sh"
if [ -r "$UPDATE_NOTICE" ]; then
    bash "$UPDATE_NOTICE" record skills || echo "⚠ Failed to record the skills revision (continuing)"
fi
