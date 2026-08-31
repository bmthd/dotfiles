#!/usr/bin/env bash
# `setup:skills`: install agent skills for Claude Code, OpenCode, and Cursor.
# Placed by the setup:scripts task in .mise.toml; see the comment there.
#
# The `npx skills add` calls below must resolve through the Takumi Guard proxy,
# which is why the task declares setup:npm-registry as a dependency rather than
# relying on the order of the parent task's depends list.

# Skill directories for each agent CLI (Cursor reads ~/.agents/skills)
mkdir -p "$HOME/.claude/skills" "$HOME/.config/opencode/skills" "$HOME/.agents/skills"

# Install skills via the `skills` CLI — one mechanism for every source.
# Own skills live in bmthd/skills, split out of the dotfiles repository so they
# can be shared on their own. What stays in that repository's .agents/skills/ is
# what does not belong anywhere else: the dotfiles skill, which only makes sense
# against it. Third-party skills come from their upstream repos. productivity
# pulls all skills from Matt Pocock's upstream productivity skills folder.
# mathbullet contributes html and explain, the two skills html's SKILL.md
# recommends using together. The other two it recommends, japanese-tech-writing
# and cognitive-rhythm-writing, are published as gists and are fetched from
# there directly. Skills cross-reference each other by name, so all four
# resolve once they share an agent's skills directory.
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
    npx skills add "$@" -y -g -a claude-code -a opencode -a cursor 2>/dev/null \
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
# japanese-tech-writing and cognitive-rhythm-writing are Keiichiro Shikano's
# (k16shikano) gists:
# https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d
# https://gist.github.com/k16shikano/eb2929f13ed19c97188393d297be8432
# Use the .git clone URL, not the page URL: the skills CLI source parser
# mistakes gist.github.com for github.com and the page URL 404s.
install_skills "japanese-tech-writing" https://gist.github.com/fd287c3133457c4fd8f5601d34aa817d.git
install_skills "cognitive-rhythm-writing" https://gist.github.com/eb2929f13ed19c97188393d297be8432.git

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
