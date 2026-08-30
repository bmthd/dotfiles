#!/usr/bin/env bash
# Tests the ordering guarantee install.sh makes about the npm registry.
#
# setup:npm-registry writes ~/.npmrc so that every `npm:` tool and every
# `npx`-based postinstall resolves through the malware-blocking proxy. That is
# only worth anything if it runs before the tools are installed, and the failure
# mode is invisible: the packages install fine, just from the wrong registry.
#
#   1. the task is invoked with --skip-tools — `mise run` installs the whole
#      tool set before running any task, so without the flag the invocation
#      itself is what installs the tools it was meant to precede
#   2. the invocation still comes before `mise install`
#
# It also guards install.sh against the three ways it used to lie about failure:
# an unguarded `curl | sh`, downloads written straight to their destination, and
# a success message printed no matter what happened.

set -euo pipefail

install_sh="$(cd "$(dirname "$0")/.." && pwd)/install.sh"

registry_line="$(grep -n 'mise run .*setup:npm-registry' "$install_sh" | head -1)"
if [[ -z "$registry_line" ]]; then
  echo "✗ install.sh never runs setup:npm-registry" >&2
  exit 1
fi

if [[ "$registry_line" != *"--skip-tools"* ]]; then
  echo "✗ setup:npm-registry is run without --skip-tools, so mise installs every" >&2
  echo "  tool before the task can point npm at the proxy" >&2
  exit 1
fi

install_line="$(grep -n '^\s*mise install' "$install_sh" | head -1)"
if [[ -z "$install_line" ]]; then
  echo "✗ install.sh never runs mise install" >&2
  exit 1
fi

if (( ${registry_line%%:*} >= ${install_line%%:*} )); then
  echo "✗ setup:npm-registry runs at or after mise install" >&2
  exit 1
fi

# Existing machines may still have the old asdf OCI plugin checked out under
# mise's `oci` plugin name. Current mise resolves that name through vfox, so the
# stale checkout must be replaced before tool installation starts.
oci_plugin_line="$(grep -n 'mise run .*setup:oci-plugin' "$install_sh" | head -1 || true)"
if [[ -z "$oci_plugin_line" ]]; then
  echo "✗ install.sh never refreshes the OCI plugin" >&2
  exit 1
fi

if [[ "$oci_plugin_line" != *"--skip-tools"* ]]; then
  echo "✗ setup:oci-plugin is run without --skip-tools, so the stale plugin" >&2
  echo "  breaks tool installation before the migration task can run" >&2
  exit 1
fi

if (( ${oci_plugin_line%%:*} >= ${install_line%%:*} )); then
  echo "✗ setup:oci-plugin runs at or after mise install" >&2
  exit 1
fi

# --- the mise installer is piped into a shell, so it needs both halves of the
# --- pipeline to be trustworthy ---------------------------------------------
# Without -f, curl hands an HTTP error page to `sh`; and because the exit status
# of a pipeline is the last command's, `sh` shrugging at that HTML reads as
# success unless pipefail is in effect for the pipeline.
mise_run_line="$(grep -n 'curl.*mise\.run' "$install_sh" | head -1 || true)"
if [[ -z "$mise_run_line" ]]; then
  echo "✗ install.sh never installs mise from mise.run" >&2
  exit 1
fi

if [[ "$mise_run_line" != *"-fsSL"* ]]; then
  echo "✗ the mise.run download is missing -fsSL, so an HTTP error page gets" >&2
  echo "  piped into a shell instead of aborting" >&2
  exit 1
fi

if ! grep -vE '^\s*#' "$install_sh" | grep -q 'set -o pipefail'; then
  echo "✗ install.sh never enables pipefail, so a failed curl in \`curl | sh\`" >&2
  echo "  is masked by the exit status of the shell it feeds" >&2
  exit 1
fi

# --- downloads must not be written straight to their destination -------------
# `curl -f -o dest` creates dest and may partially fill it before it gives up on
# an error response. For mise.lock that is the dangerous case: a zero-byte
# lockfile still counts as "a lockfile exists", so a later `mise install`
# resolves `latest` with neither the release-age gate nor checksum verification.
if grep -qE 'curl[^|]*-o "[^"]*/\.config/mise/' "$install_sh"; then
  echo "✗ a mise config download writes directly into ~/.config/mise; a failed" >&2
  echo "  curl leaves a truncated config.toml or an empty mise.lock behind" >&2
  exit 1
fi

# The repository's config lands in conf.d/ so that config.toml stays free for
# the machine; the lockfile still sits directly in ~/.config/mise. Both have to
# arrive via a temp file, so both destinations are checked by name.
# shellcheck disable=SC2016  # these are the literal strings grepped for in
# install.sh, not values to expand here
for destination in '$DOTFILES_CONF_D/10-dotfiles.toml' '$HOME/.config/mise/mise.lock'; do
  if ! grep -qF "_TMP\" \"$destination\"" "$install_sh"; then
    echo "✗ $destination is not moved into place from a temp file after a" >&2
    echo "  successful download" >&2
    exit 1
  fi
done

# --- a partial install must not report success -------------------------------
# Every step below the lockfile deliberately continues on failure so one broken
# piece does not leave the machine unconfigured. That is only honest if the
# summary and the exit code say what happened; otherwise the script prints
# "Installation complete!" and exits 0 with nothing installed.
if ! grep -q 'record_failure()' "$install_sh"; then
  echo "✗ install.sh has no failure tally, so recovered failures vanish" >&2
  exit 1
fi

# Each warning about a step that carried on must be followed by the line that
# counts it, or the tally silently under-reports.
unrecorded="$(awk '
  pending { if ($0 !~ /record_failure/) print "    line " pending; pending = 0 }
  /echo "⚠/ { pending = NR }
  END { if (pending) print "    line " pending }
' "$install_sh")"
if [[ -n "$unrecorded" ]]; then
  echo "✗ install.sh warns about a failure without recording it, at:" >&2
  echo "$unrecorded" >&2
  exit 1
fi

if ! grep -qE 'FAILURES" -ne 0 \]; then' "$install_sh"; then
  echo "✗ install.sh never exits non-zero when steps failed" >&2
  exit 1
fi

complete_line="$(grep -n 'Installation complete' "$install_sh" | head -1)"
guard_line="$(grep -nE 'FAILURES" -eq 0 \]; then' "$install_sh" | head -1)"
if [[ -z "$guard_line" ]] || (( ${guard_line%%:*} >= ${complete_line%%:*} )); then
  echo "✗ the success message is printed unconditionally" >&2
  exit 1
fi

echo "install order tests passed"
