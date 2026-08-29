#!/usr/bin/env bash
# Tests the global git hooks installed by setup:git-hooks.
#
# Three properties matter and none is visible from reading the scripts:
#
#   1. a new worktree gets its mise config trusted, so shells started there do
#      not fail with "Config files ... are not trusted"
#   2. a plain clone does NOT — that is where the supply-chain risk lives
#   3. the repository's own .git/hooks still runs; core.hooksPath replaces
#      git's hook search path rather than extending it, so a dispatcher that
#      forgot to forward would silently disable lefthook, pre-commit and
#      friends in every repository on the machine
#
# mise is stubbed: the hook only has to invoke it correctly. The global git
# config is redirected so the test never touches the real one.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/mise" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MISE_CALL_LOG"
STUB
chmod +x "$work/bin/mise"
export PATH="$work/bin:$PATH"
export MISE_CALL_LOG="$work/mise-calls.log"
export GIT_CONFIG_GLOBAL="$work/gitconfig"
: > "$MISE_CALL_LOG"
: > "$GIT_CONFIG_GLOBAL"

hooks="$work/hooks"
GIT_HOOKS_DIR="$hooks" bash "$repo_root/.dotfiles/git-hooks/install.sh" > /dev/null

if [[ "$(git config --global --get core.hooksPath)" != "$hooks" ]]; then
  echo "✗ install.sh did not point core.hooksPath at $hooks" >&2
  exit 1
fi

# Every client-side hook has to be linked, or it stops running everywhere.
for hook in pre-commit prepare-commit-msg commit-msg post-checkout post-merge \
            pre-push pre-rebase post-rewrite; do
  if [[ ! -x "$hooks/$hook" ]]; then
    echo "✗ install.sh does not link the $hook hook" >&2
    exit 1
  fi
done

# `git init` fires reference-transaction before the git dir exists, so the
# dispatcher's own `git rev-parse` fails there. It must stay silent rather than
# leaking "fatal: not a git repository" into every git command on the machine.
git init -q "$work/repo" 2> "$work/init-stderr"
if [[ -s "$work/init-stderr" ]]; then
  echo "✗ the dispatcher wrote to stderr during git init:" >&2
  cat "$work/init-stderr" >&2
  exit 1
fi

cd "$work/repo"
printf '[env]\nFOO = "bar"\n' > .mise.toml
git add -A
git -c user.email=t@example.com -c user.name=t commit -qm init

# A hook of the repository's own, to prove forwarding.
mkdir -p .git/hooks
printf '#!/bin/sh\ntouch "%s/own-hook-ran"\n' "$work" > .git/hooks/post-checkout
chmod +x .git/hooks/post-checkout

git worktree add -q -b wt "$work/wt"

if ! grep -q "trust .*$work/wt/.mise.toml" "$MISE_CALL_LOG"; then
  echo "✗ post-checkout did not trust the new worktree's config" >&2
  echo "  mise calls: $(cat "$MISE_CALL_LOG")" >&2
  exit 1
fi

if [[ ! -e "$work/own-hook-ran" ]]; then
  echo "✗ the repository's own .git/hooks/post-checkout was not forwarded to" >&2
  exit 1
fi

: > "$MISE_CALL_LOG"
git clone -q "$work/repo" "$work/clone"

if grep -q trust "$MISE_CALL_LOG"; then
  echo "✗ a plain clone was trusted; only worktrees may be" >&2
  echo "  mise calls: $(cat "$MISE_CALL_LOG")" >&2
  exit 1
fi

# git-dir keeps differing from git-common-dir for the rest of a worktree's
# life, so checking only that would trust every branch checked out in it.
: > "$MISE_CALL_LOG"
rm -f "$work/own-hook-ran"
git -C "$work/wt" checkout -q -b other

# Guard against the assertion below passing because the hook never ran at all.
if [[ ! -e "$work/own-hook-ran" ]]; then
  echo "✗ post-checkout did not fire on an ordinary checkout; the test proves nothing" >&2
  exit 1
fi

if grep -q trust "$MISE_CALL_LOG"; then
  echo "✗ an ordinary checkout inside a worktree was trusted" >&2
  echo "  mise calls: $(cat "$MISE_CALL_LOG")" >&2
  exit 1
fi

# A core.hooksPath somebody else set must survive: taking it over would
# disable whatever lives there.
git config --global core.hooksPath "$work/theirs"
GIT_HOOKS_DIR="$hooks" bash "$repo_root/.dotfiles/git-hooks/install.sh" > /dev/null

if [[ "$(git config --global --get core.hooksPath)" != "$work/theirs" ]]; then
  echo "✗ install.sh overwrote an existing core.hooksPath" >&2
  exit 1
fi

# ~/.config/git/hooks is a conventional location, so the directory may already
# hold somebody's own hooks. Replacing those would destroy exactly what the
# dispatcher exists to preserve.
theirs="$work/preexisting"
mkdir -p "$theirs"
printf '#!/bin/sh\nexit 0\n' > "$theirs/pre-commit"
chmod +x "$theirs/pre-commit"
GIT_HOOKS_DIR="$theirs" bash "$repo_root/.dotfiles/git-hooks/install.sh" > /dev/null

if [[ -L "$theirs/pre-commit" ]]; then
  echo "✗ install.sh replaced a pre-existing hook with its own symlink" >&2
  exit 1
fi

if [[ ! -L "$theirs/post-checkout" ]]; then
  echo "✗ install.sh skipped hooks it had no reason to skip" >&2
  exit 1
fi

echo "git hook tests passed"
