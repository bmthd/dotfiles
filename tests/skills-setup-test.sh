#!/usr/bin/env bash
# Tests setup:skills rebuilds the skill store in a staging home and swaps it
# in only on complete success. Run with: bash tests/skills-setup-test.sh
#
# `npx` is stubbed: the stub emulates `skills add` by deriving one skill name
# per source (the -s name when one is given, otherwise the source's last path
# segment), writing it into $HOME/.agents/skills, appending it to
# $HOME/.agents/.skill-lock.json, and linking it into $HOME/.claude/skills
# when claude-code is among the -a agents. Setting SKILLS_STUB_FAIL to a
# substring of a source makes that source's install fail.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

stub_bin="$temp/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/npx" <<'EOF'
#!/usr/bin/env bash
# Stub of `npx skills add <source> ...`: see the header of the test file.
[ "$1" = "skills" ] && [ "$2" = "add" ] || exit 1
source_arg="$3"; shift 3
name=""
agents=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-s" ] && [ -z "$name" ]; then name="$arg"; fi
    if [ "$prev" = "-a" ]; then agents="$agents $arg"; fi
    prev="$arg"
done
if [ -n "${SKILLS_STUB_FAIL:-}" ]; then
    case "$source_arg" in
        *"$SKILLS_STUB_FAIL"*) echo "stub: forced failure for $source_arg" >&2; exit 1 ;;
    esac
fi
if [ -z "$name" ] || [ "$name" = "*" ]; then
    name="${source_arg##*/}"
fi
mkdir -p "$HOME/.agents/skills/$name"
printf 'stub skill %s from %s\n' "$name" "$source_arg" > "$HOME/.agents/skills/$name/SKILL.md"
printf '%s\n' "$name" >> "$HOME/.agents/.skill-lock.json"
case "$agents" in
    *claude-code*)
        mkdir -p "$HOME/.claude/skills"
        ln -sfn "../../.agents/skills/$name" "$HOME/.claude/skills/$name"
        ;;
esac
EOF
chmod +x "$stub_bin/npx"

seed_home() {
    local home="$1"
    mkdir -p "$home/.agents/skills/stale-skill" "$home/.claude/skills/hand-placed"
    printf 'stale\n' > "$home/.agents/skills/stale-skill/SKILL.md"
    printf 'old-lock\n' > "$home/.agents/.skill-lock.json"
    ln -s "../../.agents/skills/stale-skill" "$home/.claude/skills/stale-skill"
    printf 'mine\n' > "$home/.claude/skills/hand-placed/SKILL.md"
    printf 'registry=https://npm.flatt.tech/\n' > "$home/.npmrc"
}

fail() { echo "✗ $1" >&2; exit 1; }

# --- success: the staging build replaces the old installation ---------------
home_ok="$temp/home-ok"
seed_home "$home_ok"
HOME="$home_ok" PATH="$stub_bin:/usr/bin:/bin" bash "$repo/.dotfiles/setup/skills.sh" >/dev/null

[ ! -e "$home_ok/.agents/skills/stale-skill" ] || fail "stale skill survived a successful setup:skills"
[ ! -L "$home_ok/.claude/skills/stale-skill" ] || fail "stale Claude Code symlink survived a successful setup:skills"
[ -f "$home_ok/.agents/skills/skills/SKILL.md" ] || fail "own skills (bmthd/skills) were not installed"
[ -f "$home_ok/.agents/skills/yomiyasu/SKILL.md" ] || fail "yomiyasu was not installed"
[ -f "$home_ok/.agents/skills/playwright-cli/SKILL.md" ] || fail "playwright-cli was not installed by setup:skills"
[ -f "$home_ok/.agents/skills/difit/SKILL.md" ] || fail "difit was not installed by setup:skills"
[ -L "$home_ok/.claude/skills/yomiyasu" ] || fail "Claude Code symlink for an installed skill is missing"
[ "$(readlink "$home_ok/.claude/skills/yomiyasu")" = "../../.agents/skills/yomiyasu" ] \
    || fail "Claude Code symlink does not point into the swapped-in store"
[ -f "$home_ok/.claude/skills/hand-placed/SKILL.md" ] || fail "a hand-placed skill in ~/.claude/skills was removed"
grep -qx "yomiyasu" "$home_ok/.agents/.skill-lock.json" || fail ".skill-lock.json was not replaced with the staging build's"
if grep -qx "old-lock" "$home_ok/.agents/.skill-lock.json"; then
    fail ".skill-lock.json still carries the previous installation's content"
fi
echo "✓ setup:skills swaps in a complete staging build and drops stale skills"

# --- failure: the previous installation is left byte-identical ---------------
home_ng="$temp/home-ng"
seed_home "$home_ng"
before="$(cd "$home_ng" && find . -type f -exec md5sum {} + | sort && find . -type l | sort)"
if HOME="$home_ng" PATH="$stub_bin:/usr/bin:/bin" SKILLS_STUB_FAIL="yomiyasu" \
    bash "$repo/.dotfiles/setup/skills.sh" >/dev/null 2>&1; then
    fail "setup:skills exited zero although a source failed"
fi
after="$(cd "$home_ng" && find . -type f -exec md5sum {} + | sort && find . -type l | sort)"
[ "$before" = "$after" ] || fail "a failed setup:skills changed the existing installation"
echo "✓ setup:skills leaves the previous installation untouched when a source fails"

# --- no staging home is left behind either way -------------------------------
if find "$home_ok" "$home_ng" -maxdepth 1 -name ".skills-staging.*" | grep -q .; then
    fail "a staging home was left behind"
fi
echo "✓ setup:skills cleans up its staging home"
