#!/usr/bin/env bash
# Tests that the installation is pinned to one revision, and that every
# revision resolution that crosses the network is bounded in time.
#
# The two belong together because they are the same operation seen from two
# sides: install.sh asks the network "what commit is main?" once and installs
# everything from the answer, and update-notice.sh asks the same question daily
# to decide whether to notify. Both answers arrive over a link that may be
# slow, captive, or gone.
#
# What can regress silently here:
#
#   1. a new download added to install.sh or .mise.toml written against `main`
#      directly — the file installs fine, it just comes from a different commit
#      than everything around it, and the revision recorded for this machine
#      then describes an installation that never existed
#   2. a network call written without a timeout — nothing fails, terminals just
#      start hanging for whoever is behind a captive portal

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
install_sh="$repo/install.sh"
mise_toml="$repo/.mise.toml"
hooks_install="$repo/.dotfiles/git-hooks/install.sh"
notice="$repo/.dotfiles/update-notice.sh"

fail() {
  printf '✗ %s\n' "$1" >&2
  exit 1
}

# --- install.sh resolves the revision once, up front ------------------------

resolve_line="$(grep -n 'api.github.com/repos/.*commits' "$install_sh" || true)"
[[ -n "$resolve_line" ]] ||
  fail "install.sh never resolves the repository to a commit SHA"
[[ "$(printf '%s\n' "$resolve_line" | wc -l)" -eq 1 ]] ||
  fail "install.sh resolves a commit SHA more than once; it must be resolved once and reused"

# The whole installation waits on this one call.
grep -q -- '--max-time' <(sed -n "$(( ${resolve_line%%:*} - 4 )),$(( ${resolve_line%%:*} + 1 ))p" "$install_sh") ||
  fail "install.sh resolves the revision without --max-time; a hung request hangs the installation"

grep -qE '^export DOTFILES_RAW_BASE(=|$)' "$install_sh" ||
  fail "install.sh does not export DOTFILES_RAW_BASE, so the mise setup tasks cannot share its revision"

# The recorded revision is the merge base `/dotfiles apply` uses, so it has to
# be the resolved SHA rather than whatever main points at afterwards.
grep -qE '^export DOTFILES_REVISION(=|$)' "$install_sh" ||
  fail "install.sh does not export DOTFILES_REVISION, so ~/.config/dotfiles/revision would record the head instead of the installed commit"

# DOTFILES_REF is the documented escape hatch for installing another ref.
grep -q 'DOTFILES_REF' "$install_sh" ||
  fail "install.sh has no DOTFILES_REF escape hatch"

# --- nothing fetches from a moving ref --------------------------------------

for f in "$install_sh" "$mise_toml" "$hooks_install"; do
  if grep -n 'raw.githubusercontent.com/bmthd/dotfiles/main/' "$f"; then
    fail "$(basename "$f") downloads from main directly; use the pinned base URL"
  fi
done

# Every repository download in install.sh goes through the one base URL.
# shellcheck disable=SC2016  # the literal text "$DOTFILES_RAW_BASE" is what is searched for
downloads="$(grep -c 'curl .*\$DOTFILES_RAW_BASE/' "$install_sh" || true)"
[[ "$downloads" -ge 3 ]] ||
  fail "install.sh fetches only $downloads file(s) through \$DOTFILES_RAW_BASE; expected the mise config, the lockfile and the update notice"

# The setup tasks run under install.sh's environment, but also stand alone.
task_bases="$(grep -c 'DOTFILES_RAW_BASE:-' "$mise_toml" || true)"
[[ "$task_bases" -ge 3 ]] ||
  fail ".mise.toml has $task_bases task(s) taking their base URL from DOTFILES_RAW_BASE; expected setup:git-hooks, setup:update-notice and setup:claude"

grep -q 'DOTFILES_RAW_BASE:-' "$hooks_install" ||
  fail "the git hook installer does not honour DOTFILES_RAW_BASE, so dispatch would come from a different revision"

# --- every network call in the update notice is bounded ---------------------

# This file is sourced by every interactive shell, so an unbounded request is a
# terminal that will not open. Backslash continuations are joined first: both
# calls are written across several lines.
joined="$(sed -e :a -e '/\\$/N; s/\\\n//; ta' "$notice")"
# shellcheck disable=SC2016  # likewise: this greps for the variable's name in the source
calls="$(printf '%s\n' "$joined" | grep -F '$DOTFILES_CURL_BIN" -' || true)"
[[ -n "$calls" ]] ||
  fail "found no curl invocation in update-notice.sh; this check has stopped checking anything"
while IFS= read -r line; do
  case "$line" in
    *--max-time*) ;;
    *) fail "update-notice.sh makes a network call without --max-time: $line" ;;
  esac
done <<< "$calls"

# `git ls-remote` takes no timeout — git's connect and read timeouts are unset
# by default — which is why the remote revision moved to the API.
if grep -n '^[^#]*ls-remote' "$notice"; then
  fail "update-notice.sh still uses git ls-remote, which cannot be given a timeout"
fi

echo "revision pinning tests passed"
