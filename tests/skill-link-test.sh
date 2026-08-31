#!/usr/bin/env bash
# Tests the skill linking that setup:skills does instead of copying this
# repository's own skills onto the machine.
#
# What matters, and what none of it looks like from reading the script:
#
#   1. both agent directories end up pointing at the checkout, so editing an
#      installed skill file edits the repository's working tree
#   2. the skills CLI's lock entry is dropped, or the next `npx skills update`
#      silently puts a copy back where the link was
#   3. a copy already on the machine is only deleted when it is identical to
#      the checkout; one that differs is kept, because nothing else has it
#   4. without a checkout the script fails rather than half-linking, which is
#      what makes the mise task fall back to `skills add`
#
# ghq and git are stubbed: the script only has to invoke them correctly.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
linker="$repo_root/.dotfiles/link-skills.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git_bin="$(command -v git)"

# A real checkout: the linker reads the revision this machine installed from
# out of it, so an older copy has to be recognisable as one.
checkout="$work/ghq/github.com/bmthd/dotfiles"
mkdir -p "$checkout/.agents/skills/dotfiles"
printf 'skill body\n' > "$checkout/.agents/skills/dotfiles/SKILL.md"
git -C "$checkout" init --quiet
git -C "$checkout" add -A
git -C "$checkout" -c user.email=test@example.com -c user.name=test \
  commit --quiet --no-gpg-sign -m 'skill'
installed_revision="$(git -C "$checkout" rev-parse HEAD)"

mkdir -p "$work/bin"
cat > "$work/bin/ghq" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  root) [[ -n "${GHQ_STUB_ROOT:-}" ]] && printf '%s\n' "$GHQ_STUB_ROOT" ;;
  list) [[ -n "${GHQ_STUB_ROOT:-}" ]] && printf '%s\n' "$GHQ_STUB_ROOT/github.com/bmthd/dotfiles" ;;
  get) printf '%s\n' "get $*" >> "$GHQ_CALL_LOG" ;;
esac
STUB
# Only `clone` is stubbed — the linker's other git calls read the checkout and
# have to be the real thing.
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALL_LOG"
[[ "$1" = clone ]] && exit 1
exec "$GIT_BIN" "$@"
STUB
chmod +x "$work/bin/ghq" "$work/bin/git"
export PATH="$work/bin:$PATH"
export GHQ_CALL_LOG="$work/ghq-calls.log"
export GIT_CALL_LOG="$work/git-calls.log"
export GIT_BIN="$git_bin"
: > "$GHQ_CALL_LOG"
: > "$GIT_CALL_LOG"

home="$work/home"
run_linker() {
  HOME="$home" GHQ_STUB_ROOT="$work/ghq" bash "$linker"
}

fail() {
  printf '✗ %s\n' "$1" >&2
  exit 1
}

# Copies the linker decided not to delete.
kept_aside() {
  local aside
  shopt -s nullglob
  for aside in "$home/.agents/skills/"dotfiles.local.*; do
    printf '%s\n' "$aside"
  done
  shopt -u nullglob
}

# 1. A machine that never had the skill: both directories link to the checkout.
mkdir -p "$home"
run_linker > "$work/first.log"

universal="$home/.agents/skills/dotfiles"
claude="$home/.claude/skills/dotfiles"
[[ -L "$universal" ]] || fail "$universal is not a symlink"
[[ -L "$claude" ]] || fail "$claude is not a symlink"
[[ "$(readlink "$universal")" = "$checkout/.agents/skills/dotfiles" ]] ||
  fail "$universal points at $(readlink "$universal")"
[[ "$(readlink "$claude")" = "$checkout/.agents/skills/dotfiles" ]] ||
  fail "$claude points at $(readlink "$claude")"

# An edit made through the link is an edit to the checkout — the whole point.
printf 'edited through the link\n' >> "$universal/SKILL.md"
grep -q 'edited through the link' "$checkout/.agents/skills/dotfiles/SKILL.md" ||
  fail 'editing the installed skill did not reach the checkout'
sed -i '/edited through the link/d' "$checkout/.agents/skills/dotfiles/SKILL.md"

# 2. Re-running changes nothing and does not clone again.
run_linker > "$work/second.log"
[[ "$(readlink "$universal")" = "$checkout/.agents/skills/dotfiles" ]] ||
  fail 're-running replaced the link'
grep -q '^clone' "$GIT_CALL_LOG" && fail 'a checkout was cloned although one was present'


# 3. The lock entry is dropped so `npx skills update` leaves the link alone.
cat > "$home/.agents/.skill-lock.json" <<'LOCK'
{
  "version": 3,
  "skills": {
    "dotfiles": { "source": "bmthd/dotfiles" },
    "pr-anywhere": { "source": "bmthd/skills" }
  },
  "dismissed": {}
}
LOCK
run_linker > /dev/null
jq -e '.skills | has("dotfiles") | not' "$home/.agents/.skill-lock.json" > /dev/null ||
  fail 'the dotfiles lock entry survived'
jq -e '.skills | has("pr-anywhere")' "$home/.agents/.skill-lock.json" > /dev/null ||
  fail 'an entry the skills CLI still owns was dropped'

# 4. A copy identical to the checkout is replaced; the link is what remains.
rm -rf "$universal"
cp -r "$checkout/.agents/skills/dotfiles" "$universal"
run_linker > /dev/null
[[ -L "$universal" ]] || fail 'an identical copy was not replaced by a link'
[[ -z "$(kept_aside)" ]] || fail 'an identical copy was kept aside instead of removed'

# 5. A copy from the revision this machine installed from is an installed copy
#    too, however far the checkout has moved since — the state every machine is
#    in the first time this runs.
mkdir -p "$home/.config/dotfiles"
printf '%s\n' "$installed_revision" > "$home/.config/dotfiles/revision"
rm -rf "$universal"
cp -r "$checkout/.agents/skills/dotfiles" "$universal"
printf 'a commit made since\n' >> "$checkout/.agents/skills/dotfiles/SKILL.md"
run_linker > /dev/null
[[ -L "$universal" ]] || fail 'a copy of the installed revision was not replaced by a link'
[[ -z "$(kept_aside)" ]] || fail 'a copy of the installed revision was kept aside'

# 6. A copy that matches no revision is kept: it may be the only place that
#    edit exists.
rm -rf "$universal"
cp -r "$checkout/.agents/skills/dotfiles" "$universal"
printf 'local edit\n' >> "$universal/SKILL.md"
run_linker > "$work/aside.log"
[[ -L "$universal" ]] || fail 'a differing copy left no link behind'
aside="$(kept_aside | head -n 1)"
[[ -n "$aside" ]] || fail 'a differing copy was deleted'
grep -q 'local edit' "$aside/SKILL.md" || fail "the kept copy lost its edit ($aside)"
grep -q "$aside" "$work/aside.log" || fail 'the kept copy was not reported'
rm -rf "$aside"

# 7. No checkout anywhere: ghq is asked, the clone is attempted, and the
#    failure is loud — that is the signal setup:skills falls back on.
empty_home="$work/empty-home"
mkdir -p "$empty_home"
: > "$GIT_CALL_LOG"
if HOME="$empty_home" GHQ_STUB_ROOT="$work/nowhere" bash "$linker" > "$work/missing.log" 2>&1; then
  fail 'the linker succeeded without a checkout'
fi
grep -q 'get github.com/bmthd/dotfiles' "$GHQ_CALL_LOG" || fail 'ghq get was never attempted'
grep -q 'clone .*https://github.com/bmthd/dotfiles' "$GIT_CALL_LOG" ||
  fail 'the git clone fallback was never attempted'
[[ ! -e "$empty_home/.agents/skills/dotfiles" ]] || fail 'a half-linked skill was left behind'

# 8. An explicit checkout wins over whatever ghq would have found.
other="$work/other/dotfiles"
mkdir -p "$other/.agents/skills/dotfiles"
printf 'other body\n' > "$other/.agents/skills/dotfiles/SKILL.md"
explicit_home="$work/explicit-home"
mkdir -p "$explicit_home"
HOME="$explicit_home" GHQ_STUB_ROOT="$work/ghq" DOTFILES_REPO="$other" bash "$linker" > /dev/null
[[ "$(readlink "$explicit_home/.agents/skills/dotfiles")" = "$other/.agents/skills/dotfiles" ]] ||
  fail 'DOTFILES_REPO was ignored'

echo "✓ skill linking"
