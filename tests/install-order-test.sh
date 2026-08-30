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
for destination in '$MISE_CONFIG_DEST' '$MISE_LOCK_DEST'; do
  if ! grep -qF "_TMP\" \"$destination\"" "$install_sh"; then
    echo "✗ $destination is not moved into place from a temp file after a" >&2
    echo "  successful download" >&2
    exit 1
  fi
done

# --- one definition of where the mise files go -------------------------------
# install.sh and .dotfiles/apply.sh both place these files, and for a while they
# disagreed: install.sh had moved the repository's config to conf.d/ while
# apply.sh kept writing it back to config.toml, and apply.sh derived the
# lockfile path from whichever config path it was given (#71). Both now read
# .dotfiles/mise-layout.sh, and neither may spell a ~/.config/mise path out
# again — that duplication is the bug, not its symptom.
layout_sh="$(dirname "$install_sh")/.dotfiles/mise-layout.sh"
apply_sh="$(dirname "$install_sh")/.dotfiles/apply.sh"

for placer in "$install_sh" "$apply_sh"; do
  if ! grep -q 'mise-layout\.sh' "$placer"; then
    echo "✗ $(basename "$placer") does not read the shared layout rules in" >&2
    echo "  .dotfiles/mise-layout.sh, so its paths can drift again" >&2
    exit 1
  fi
  if grep -nE '\$\{?(HOME|home)\}?/\.config/mise' "$placer" >&2; then
    echo "✗ the lines above spell out a ~/.config/mise path instead of asking" >&2
    echo "  .dotfiles/mise-layout.sh for it" >&2
    exit 1
  fi
done

for rule in dotfiles_mise_config_path dotfiles_mise_lock_path \
  dotfiles_legacy_mise_config_path dotfiles_is_repository_mise_config \
  dotfiles_migration_is_forced; do
  if ! grep -q "^$rule()" "$layout_sh"; then
    echo "✗ .dotfiles/mise-layout.sh no longer defines $rule" >&2
    exit 1
  fi
done

# The lockfile is keyed by mise to the config directory, so a layout that
# derives it from the config path puts it inside conf.d/, where mise never
# looks. That is how --mise-config stopped being a usable workaround.
if [ "$(bash -c '. "$1"; dotfiles_mise_lock_path /h' _ "$layout_sh")" != '/h/.config/mise/mise.lock' ] ||
  [ "$(bash -c '. "$1"; dotfiles_mise_config_path /h' _ "$layout_sh")" != '/h/.config/mise/conf.d/10-dotfiles.toml' ]; then
  echo "✗ the shared layout no longer puts the config in conf.d/ and the" >&2
  echo "  lockfile beside config.toml" >&2
  exit 1
fi

# install.sh is piped into bash *or* zsh, and it sources this file, so the
# fragment has to behave identically under both.
for shell in bash zsh; do
  command -v "$shell" > /dev/null || continue
  # shellcheck disable=SC2016  # the body is run by $shell, not expanded here
  if ! "$shell" -c '. "$1"; dotfiles_mise_config_path /h > /dev/null' _ "$layout_sh"; then
    echo "✗ .dotfiles/mise-layout.sh does not work under $shell, which" >&2
    echo "  install.sh is documented to be piped into" >&2
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
