#!/usr/bin/env bash
# Regenerate .dotfiles/apm/apm.lock.yaml from apm.yml beside it.
#
#   bash .dotfiles/apm/relock.sh            # lock new entries, keep the rest
#   bash .dotfiles/apm/relock.sh --update   # re-resolve every entry to upstream HEAD
#   bash .dotfiles/apm/relock.sh --check    # fail if the lockfile is out of date
#
# Machines install with `apm install -g --frozen`, and frozen mode replays the
# deployments the lockfile records as well as its commits. `apm lock` writes no
# deployments, so the lockfile has to come from a real user-scope install. That
# install runs against a throwaway HOME, which is what keeps it from touching
# this machine's ~/.claude and ~/.agents and makes the recorded paths the same
# on every machine.
#
# --update is what .github/workflows/bump-skills.yml runs weekly. Without it,
# the existing lockfile is installed from as-is, so editing the manifest and
# re-locking moves only the entries that changed.

set -euo pipefail

mode="${1:-}"
case "$mode" in
    ""|--update|--check) ;;
    *) echo "usage: $0 [--update|--check]" >&2; exit 2 ;;
esac

dir="$(cd "$(dirname "$0")" && pwd)"
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT
mkdir -p "$home/.apm"
cp "$dir/apm.yml" "$home/.apm/apm.yml"
if [ "$mode" != "--update" ] && [ -f "$dir/apm.lock.yaml" ]; then
    cp "$dir/apm.lock.yaml" "$home/.apm/apm.lock.yaml"
fi

# APM_HOME and the agent config overrides would send the install somewhere
# other than the throwaway HOME; the cache stays shared, it is content-addressed.
if [ "$mode" = "--check" ]; then
    # --frozen: fail rather than resolve an entry the lockfile does not have.
    (cd "$home" && env -u APM_HOME -u CLAUDE_CONFIG_DIR -u CODEX_HOME HOME="$home" apm install -g --frozen)
    exit 0
fi

(cd "$home" && env -u APM_HOME -u CLAUDE_CONFIG_DIR -u CODEX_HOME HOME="$home" apm install -g)
cp "$home/.apm/apm.lock.yaml" "$dir/apm.lock.yaml"
