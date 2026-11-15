#!/usr/bin/env bash
# `setup:skills`: install agent skills for Claude Code, OpenCode, Cursor,
# Codex, and Gemini CLI.
# Placed by the setup:scripts task in .mise.toml; see the comment there.
#
# Two installers, split by whose skills they are:
#
#   * own skills (bmthd/skills, and the dotfiles skill in this repository) go
#     through the `skills` CLI and track HEAD — the shell-startup update notice
#     is what tells a machine they have moved;
#   * third-party skills go through APM, pinned to the commits recorded in
#     .dotfiles/apm/apm.lock.yaml. The manifest beside it says why each one is
#     there and why APM.
#
# The `npx skills` calls below must resolve through the Takumi Guard proxy,
# which is why the task declares setup:npm-registry as a dependency rather than
# relying on the order of the parent task's depends list.

# Skill directories for each agent CLI. Cursor, Codex and Gemini CLI are
# "universal" agents to the skills CLI: they all read ~/.agents/skills, which is
# also where it puts a skill for OpenCode, so the one directory covers all four
# and only Claude Code gets a tree of its own (symlinks into ~/.agents/skills).
# APM's `claude` and `agent-skills` targets write the same two directories.
mkdir -p "$HOME/.claude/skills" "$HOME/.config/opencode/skills" "$HOME/.agents/skills"

RAW_BASE="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/bmthd/dotfiles/${DOTFILES_REF:-main}}"

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

# --- Third-party skills (APM) -------------------------------------------------
# Machines set up before APM have these from the skills CLI, which leaves a
# symlink in ~/.claude/skills that APM refuses to deploy over. Remove what the
# skills CLI installed from a source APM now owns; its lock file names the
# source of each skill. Matching on sources rather than skill names also takes
# out the ones APM no longer installs (playwright-cli's `dev`, hunk's
# extensions). Once migrated nothing matches and this is a no-op.
remove_skills_cli_copies() {
    local lock="$HOME/.agents/.skill-lock.json"
    local owned='["obra/superpowers","mattpocock/skills","stablyai/orca","modem-dev/hunk","humanlayer/skills","anthropics/claude-plugins-community","cloudflare/security-audit-skill","cursor/plugins","nanaism/yomiyasu","GoogleChrome/modern-web-guidance","microsoft/playwright-cli","yoshiko-pg/difit"]'
    [ -r "$lock" ] && command -v jq >/dev/null 2>&1 || return 0
    local name legacy=()
    while IFS= read -r name; do
        legacy+=("$name")
    done < <(jq -r --argjson owned "$owned" \
        '.skills // {} | to_entries[] | select((.value.source | ascii_downcase) as $s | $owned | map(ascii_downcase) | index($s)) | .key' \
        "$lock")
    [ "${#legacy[@]}" -gt 0 ] || return 0
    npx skills remove "${legacy[@]}" -g -y >/dev/null 2>&1 \
      && echo "✓ Moved ${#legacy[@]} skill(s) from the skills CLI to APM" \
      || echo "⚠ Failed to remove skills-CLI copies of APM-managed skills (continuing)"
}

# ~/.apm is the APM user scope, and its manifest and lockfile are replaced from
# this repository on every run: a skill added there by hand would be dropped
# from the manifest here, so add it to .dotfiles/apm/apm.yml instead. Copies,
# not symlinks — APM refuses to write through a symlinked lockfile.
#
# `--frozen` installs exactly what the lockfile records and fails instead of
# resolving anything it does not, so an entry added to the manifest without
# re-locking cannot quietly pull upstream HEAD.
if command -v apm >/dev/null 2>&1; then
    APM_DIR="$HOME/.apm"
    mkdir -p "$APM_DIR"
    fetched=0
    for file in apm.yml apm.lock.yaml; do
        # Through a temp file, so a failed download never leaves a manifest
        # that disagrees with its lockfile.
        tmp="$(mktemp)"
        if curl -fsSL --max-time 30 "$RAW_BASE/.dotfiles/apm/$file" -o "$tmp"; then
            mv "$tmp" "$APM_DIR/$file.new"
            fetched=$((fetched + 1))
        else
            rm -f "$tmp"
        fi
    done
    if [ "$fetched" -eq 2 ]; then
        mv "$APM_DIR/apm.yml.new" "$APM_DIR/apm.yml"
        mv "$APM_DIR/apm.lock.yaml.new" "$APM_DIR/apm.lock.yaml"
        remove_skills_cli_copies
        apm install -g --frozen \
          && echo "✓ third-party skills installed (APM)" \
          || echo "⚠ third-party skills installation failed (continuing)"
    else
        rm -f "$APM_DIR/apm.yml.new" "$APM_DIR/apm.lock.yaml.new"
        echo "⚠ Failed to download the APM manifest (continuing)"
    fi
else
    echo "⚠ apm not found; skipping third-party skills (run \`mise install\` first)"
fi

# yomiyasu's SKILL.md warns that other Japanese style skills active alongside it
# make its output erratic, so it replaced the two that used to be installed
# here, japanese-tech-writing and cognitive-rhythm-writing. Dropping their
# install lines does not take them off a machine that already has them, so
# remove them explicitly; on a machine without them this is a no-op.
npx skills remove japanese-tech-writing cognitive-rhythm-writing -g -y >/dev/null 2>&1 || true
# mathbullet's html and explain skills used to be installed here and were
# dropped; remove them from machines that still carry them, for the same reason.
npx skills remove html explain -g -y >/dev/null 2>&1 || true

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
