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
for destination in '$MISE_CONFIG_DEST' '$MISE_LOCK_DEST' '$PROFILE_CONFIG_DEST'; do
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
  dotfiles_migration_is_forced dotfiles_profiles dotfiles_default_profile \
  dotfiles_profile_is_known dotfiles_profile_record_path \
  dotfiles_profile_repository_path dotfiles_profile_config_path; do
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

# --- profiles ----------------------------------------------------------------
# The default profile is the whole of the common config and has no fragment of
# its own, so it must resolve to an empty path rather than to a file name that
# does not exist. Every other profile is a fragment sorted after 10-dotfiles.
layout_call() {
  bash -c '. "$1"; shift; "$@"' _ "$layout_sh" "$@"
}

default_profile="$(layout_call dotfiles_default_profile)"
if [ -n "$(layout_call dotfiles_profile_repository_path "$default_profile")" ] ||
  [ -n "$(layout_call dotfiles_profile_config_path /h "$default_profile")" ]; then
  echo "✗ the default profile ($default_profile) resolves to a fragment; it is" >&2
  echo "  the common config itself and has nothing to place" >&2
  exit 1
fi

if [ "$(layout_call dotfiles_profile_config_path /h work)" != '/h/.config/mise/conf.d/20-dotfiles-work.toml' ] ||
  [ "$(layout_call dotfiles_profile_repository_path work)" != '.mise.work.toml' ] ||
  [ "$(layout_call dotfiles_profile_record_path /h)" != '/h/.config/dotfiles/profile' ]; then
  echo "✗ the shared layout no longer places a profile fragment beside" >&2
  echo "  conf.d/10-dotfiles.toml, or records the profile under ~/.config/dotfiles" >&2
  exit 1
fi

# The two halves of a profile are its name in the layout list and its file in
# the repository. Either one alone is silent: a name with no file makes
# install.sh accept DOTFILES_PROFILE and then fail to download anything, and a
# file no name knows about is never installed and never cleaned up on a switch.
repo_root="$(dirname "$install_sh")"
for profile in $(layout_call dotfiles_profiles); do
  repository_path="$(layout_call dotfiles_profile_repository_path "$profile")"
  [ -n "$repository_path" ] || continue
  if [ ! -f "$repo_root/$repository_path" ]; then
    echo "✗ profile $profile is offered by .dotfiles/mise-layout.sh but $repository_path" >&2
    echo "  is not in the repository, so installing it would place nothing" >&2
    exit 1
  fi
  # install.sh only removes a fragment it can recognise as this repository's, so
  # one without the marker would survive every later profile switch.
  if ! bash -c '. "$1"; dotfiles_is_repository_mise_config "$2"' _ "$layout_sh" "$repo_root/$repository_path"; then
    echo "✗ $repository_path carries no raw.githubusercontent.com/bmthd/dotfiles marker," >&2
    echo "  so switching away from the $profile profile would leave it in conf.d" >&2
    exit 1
  fi
done

for fragment in "$repo_root"/.mise.*.toml; do
  [ -e "$fragment" ] || continue
  profile="${fragment##*/.mise.}"
  profile="${profile%.toml}"
  if ! bash -c '. "$1"; dotfiles_profile_is_known "$2"' _ "$layout_sh" "$profile"; then
    echo "✗ .mise.$profile.toml is in the repository but $profile is not a profile" >&2
    echo "  .dotfiles/mise-layout.sh offers, so nothing ever installs it" >&2
    exit 1
  fi
done

# install.sh is piped into bash *or* zsh, and it sources this file, so the
# fragment has to behave identically under both. The profile helpers matter
# most here: they are the ones written as a `case` that falls through to no
# output, and an empty result is what tells a caller there is nothing to place.
for shell in bash zsh; do
  command -v "$shell" > /dev/null || continue
  # shellcheck disable=SC2016  # the body is run by $shell, not expanded here
  if ! "$shell" -c '. "$1"; dotfiles_mise_config_path /h > /dev/null' _ "$layout_sh"; then
    echo "✗ .dotfiles/mise-layout.sh does not work under $shell, which" >&2
    echo "  install.sh is documented to be piped into" >&2
    exit 1
  fi
  # shellcheck disable=SC2016  # the body is run by $shell, not expanded here
  shell_profiles="$("$shell" -c '
    . "$1"
    for profile in $(dotfiles_profiles); do
      printf "%s:%s:%s\n" "$profile" \
        "$(dotfiles_profile_repository_path "$profile")" \
        "$(dotfiles_profile_config_path /h "$profile")"
      dotfiles_profile_is_known "$profile" || printf "%s is not known to itself\n" "$profile"
    done
    dotfiles_profile_is_known nonexistent-profile && printf "unknown profile accepted\n"
    :' _ "$layout_sh")"
  if [ -z "$shell_profiles" ] || [ "${shell_profiles#*not known}" != "$shell_profiles" ] ||
    [ "${shell_profiles#*accepted}" != "$shell_profiles" ]; then
    echo "✗ the profile rules do not resolve the same way under $shell:" >&2
    echo "$shell_profiles" >&2
    exit 1
  fi
  if [ -n "${previous_shell_profiles+set}" ] && [ "$shell_profiles" != "$previous_shell_profiles" ]; then
    echo "✗ the profile rules resolve differently under $shell than under the" >&2
    echo "  shell before it, so install.sh installs a different machine" >&2
    echo "  depending on which one it was piped into" >&2
    exit 1
  fi
  previous_shell_profiles="$shell_profiles"
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
