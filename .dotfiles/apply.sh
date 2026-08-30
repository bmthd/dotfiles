#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: apply.sh plan|apply [--home HOME] [--repo REPO] [--remote-ref REF] [--mise-config PATH] [--mise-lock PATH] [--json]
EOF
  exit 2
}

# Where the repository's mise files belong, and how to recognise the copy an
# older installation left in config.toml. Shared with install.sh rather than
# restated here: this script had its own copy of those rules, missed the conf.d
# split install.sh had already made, and wrote the repository's config back over
# the machine's own config.toml (#71). Read from this script's directory, not
# from --repo, so the rules always come from the checkout being run.
# shellcheck source=.dotfiles/mise-layout.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mise-layout.sh"

command_name="${1:-}"
case "$command_name" in
  plan|apply) shift ;;
  *) usage ;;
esac

home="$HOME"
repo="$(pwd)"
remote_ref="origin/main"
mise_config=""
mise_lock=""
json=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --home)
      [ "$#" -ge 2 ] || usage
      home="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || usage
      repo="$2"
      shift 2
      ;;
    --remote-ref)
      [ "$#" -ge 2 ] || usage
      remote_ref="$2"
      shift 2
      ;;
    --mise-config)
      [ "$#" -ge 2 ] || usage
      mise_config="$2"
      shift 2
      ;;
    --mise-lock)
      [ "$#" -ge 2 ] || usage
      mise_lock="$2"
      shift 2
      ;;
    --json)
      json=true
      shift
      ;;
    *) usage ;;
  esac
done

if [ -z "$mise_config" ]; then
  mise_config="$(dotfiles_mise_config_path "$home")"
fi
# Independent of --mise-config on purpose. The lockfile is keyed to the config
# directory, so deriving it from the config path puts it inside conf.d/, where
# mise never looks for it.
if [ -z "$mise_lock" ]; then
  mise_lock="$(dotfiles_mise_lock_path "$home")"
fi
legacy_mise_config="$(dotfiles_legacy_mise_config_path "$home")"

# Refresh the remote-tracking ref this run compares against. Without it the
# whole run is silently wrong rather than failing: every file compares against
# whatever this checkout last fetched, comes out `identical`, and the run
# reports "no updates" for an origin/main that moved days ago.
#
# This keeps `plan` read-only in the sense that matters — fetching writes only
# remote-tracking refs inside the checkout and touches no managed local file.
#
# Acquiring a missing checkout is deliberately not done here: this script is
# part of the checkout, so by the time it runs the clone already exists. That
# step belongs to the caller (see .agents/skills/dotfiles/apply.md).
fetch_state='skipped'
fetch_error=''
fetch_remote=''
fetch_branch=''
case "$remote_ref" in
  */*)
    fetch_remote="${remote_ref%%/*}"
    fetch_branch="${remote_ref#*/}"
    ;;
esac

if [ -n "$fetch_remote" ] && git -C "$repo" config --get "remote.${fetch_remote}.url" >/dev/null; then
  # An explicit refspec so the ref that is fetched is the ref that is read
  # below, whatever the checkout's configured refspec happens to be.
  if fetch_error="$(git -C "$repo" fetch "$fetch_remote" \
    "+refs/heads/${fetch_branch}:refs/remotes/${fetch_remote}/${fetch_branch}" 2>&1 >/dev/null)"; then
    fetch_state='ok'
    fetch_error=''
  else
    fetch_state='failed'
  fi
fi

if ! remote_revision="$(git -C "$repo" rev-parse --verify "${remote_ref}^{commit}")"; then
  printf 'cannot resolve remote ref %s in %s\n' "$remote_ref" "$repo" >&2
  exit 1
fi

revision_file="$home/.config/dotfiles/revision"
base_revision=""
if [ -f "$revision_file" ]; then
  base_revision="$(<"$revision_file")"
fi

has_base=false
if [ -n "$base_revision" ] && git -C "$repo" cat-file -e "${base_revision}^{commit}" 2>/dev/null; then
  has_base=true
fi

repository_paths=(
  '.mise.toml'
  'mise.lock'
  '.claude/settings.json'
  '.claude/statusline.sh'
  '.dotfiles/update-notice.sh'
)
local_paths=(
  "$mise_config"
  "$mise_lock"
  "$home/.claude/settings.json"
  "$home/.claude/statusline.sh"
  "$home/.config/dotfiles/update-notice.sh"
)

for local_path in "${local_paths[@]}"; do
  if [ -L "$local_path" ] || { [ -e "$local_path" ] && [ ! -f "$local_path" ]; }; then
    printf 'managed target is not a regular file: %s\n' "$local_path" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
transaction_active=false
transaction_committed=false
transaction_phase='inactive'

cleanup_transaction() {
  local exit_code="$1"

  trap - EXIT INT TERM
  if [ "$transaction_active" = true ] && [ "$transaction_committed" != true ] \
    && [ "$transaction_phase" != 'committing' ] && [ "$transaction_phase" != 'rolling-back' ]; then
    if ! rollback; then
      printf 'rollback after unexpected exit failed for: %s\n' "$rollback_error_summary" >&2
    fi
  fi
  rm -rf "$work_dir"
  exit "$exit_code"
}

trap 'exit_code=$?; cleanup_transaction "$exit_code"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
files_file="$work_dir/files.jsonl"

blob_for() {
  git -C "$repo" rev-parse --verify "$1:$2" 2>/dev/null || true
}

text_merge_state() {
  local repository_path="$1"
  local local_path="$2"
  local base_file="$work_dir/base-$3"
  local remote_file="$work_dir/remote-$3"

  git -C "$repo" show "${base_revision}:${repository_path}" > "$base_file"
  git -C "$repo" show "${remote_revision}:${repository_path}" > "$remote_file"

  if git merge-file -p "$local_path" "$base_file" "$remote_file" >/dev/null; then
    printf '%s' 'auto-merge'
  else
    case "$?" in
      1) printf '%s' 'conflict' ;;
      *) printf '%s' 'needs-decision' ;;
    esac
  fi
}

for index in "${!repository_paths[@]}"; do
  repository_path="${repository_paths[$index]}"
  local_path="${local_paths[$index]}"

  if [ "$has_base" != true ]; then
    state='needs-decision'
  elif [ ! -e "$local_path" ]; then
    if [ -n "$(blob_for "$remote_revision" "$repository_path")" ]; then
      state='missing-local'
    else
      state='identical'
    fi
  else
    base_blob="$(blob_for "$base_revision" "$repository_path")"
    remote_blob="$(blob_for "$remote_revision" "$repository_path")"
    local_blob="$(git hash-object "$local_path")"

    if [ -z "$base_blob" ] || [ -z "$remote_blob" ]; then
      state='needs-decision'
    elif [ "$local_blob" = "$remote_blob" ]; then
      state='identical'
    elif [ "$local_blob" = "$base_blob" ]; then
      state='unchanged-local'
    elif [ "$remote_blob" = "$base_blob" ]; then
      state='unchanged-remote'
    elif [ "$repository_path" = '.claude/settings.json' ]; then
      state='auto-merge'
    else
      state="$(text_merge_state "$repository_path" "$local_path" "$index")"
    fi
  fi

  jq -n \
    --arg state "$state" \
    --arg repository_path "$repository_path" \
    --arg local_path "$local_path" \
    '{state: $state, repositoryPath: $repository_path, localPath: $local_path}' >> "$files_file"
done
files="$(jq -s '.' "$files_file")"

# The pre-conf.d copy in ~/.config/mise/config.toml. It is not a managed target
# — nothing is ever written to it — but it outranks conf.d, so as long as it
# holds the repository's old copy every update staged into conf.d is shadowed
# and the machine keeps running the tasks of the revision it was installed at.
# install.sh has moved it aside since the split; this script did not, which left
# `apply` unable to migrate the machines it exists to serve (#71).
base_mise_blob=''
if [ "$has_base" = true ]; then
  base_mise_blob="$(blob_for "$base_revision" '.mise.toml')"
fi
remote_mise_blob="$(blob_for "$remote_revision" '.mise.toml')"

legacy_state='absent'
if [ "$legacy_mise_config" = "$mise_config" ]; then
  # config.toml was named as the destination, so there is nothing to displace.
  legacy_state='destination'
elif [ -L "$legacy_mise_config" ] || { [ -e "$legacy_mise_config" ] && [ ! -f "$legacy_mise_config" ]; }; then
  legacy_state='unrelated'
elif dotfiles_is_repository_mise_config "$legacy_mise_config"; then
  legacy_blob="$(git hash-object "$legacy_mise_config")"
  if dotfiles_migration_is_forced; then
    legacy_state='migratable'
  elif [ -n "$base_mise_blob" ] && [ "$legacy_blob" = "$base_mise_blob" ]; then
    legacy_state='migratable'
  elif [ -n "$remote_mise_blob" ] && [ "$legacy_blob" = "$remote_mise_blob" ]; then
    legacy_state='migratable'
  else
    # Moving it would protect the bytes but not the behaviour: a `node =
    # { version = "22.11.0" }` written on top of the old copy stops applying the
    # moment the file moves, and `mise install` runs a few steps later. An
    # unprovable file is left exactly where it is, and the apply refuses.
    legacy_state='needs-review'
  fi
elif [ -e "$legacy_mise_config" ]; then
  # A config.toml written for this machine — the file's job from now on.
  legacy_state='unrelated'
fi

if [ "$has_base" = true ]; then
  mode='inventory'
else
  mode='no-base'
fi

emit_inventory() {
if "$json"; then
  jq -n \
    --arg mode "$mode" \
    --arg fetch "$fetch_state" \
    --arg fetch_error "$fetch_error" \
    --arg base_revision "$base_revision" \
    --arg remote_revision "$remote_revision" \
    --arg legacy_path "$legacy_mise_config" \
    --arg legacy_state "$legacy_state" \
    --argjson files "$files" \
    '{mode: $mode, fetch: $fetch, fetchError: $fetch_error, baseRevision: $base_revision,
      remoteRevision: $remote_revision, files: $files,
      legacyMiseConfig: {path: $legacy_path, state: $legacy_state}}'
else
  printf 'mode: %s\nfetch: %s\nbase revision: %s\nremote revision: %s\n' \
    "$mode" "$fetch_state" "${base_revision:-<none>}" "$remote_revision"
  if [ -n "$fetch_error" ]; then
    printf 'fetch error: %s\n' "$fetch_error"
  fi
  jq -r '.[] | "\(.state): \(.repositoryPath) -> \(.localPath)"' <<<"$files"
  printf 'legacy mise config: %s (%s)\n' "$legacy_mise_config" "$legacy_state"
fi
}

emit_apply_result() {
  local result="$1"
  local backup_path="$2"
  local error="$3"

  if "$json"; then
    jq -n \
      --arg mode "$mode" \
      --arg fetch "$fetch_state" \
      --arg fetch_error "$fetch_error" \
      --arg base_revision "$base_revision" \
      --arg remote_revision "$remote_revision" \
      --arg result "$result" \
      --arg backup_path "$backup_path" \
      --arg error "$error" \
      --arg legacy_path "$legacy_mise_config" \
      --arg legacy_state "$legacy_state" \
      --argjson files "$files" \
      '{mode: $mode, fetch: $fetch, fetchError: $fetch_error, baseRevision: $base_revision,
        remoteRevision: $remote_revision, files: $files, result: $result,
        backupPath: $backup_path, error: $error,
        legacyMiseConfig: {path: $legacy_path, state: $legacy_state}}'
  else
    printf 'result: %s\nbackup: %s\n' "$result" "${backup_path:-<none>}"
    if [ -n "$error" ]; then
      printf 'error: %s\n' "$error"
    fi
  fi
}

if [ "$command_name" = plan ]; then
  emit_inventory
  exit 0
fi

# A failed fetch is fatal here even though `plan` only reports it: applying
# means running the setup tasks and advancing the recorded revision, and doing
# that against a possibly stale remote records an update that never happened.
if [ "$fetch_state" = failed ]; then
  fetch_failure_error="cannot apply after a failed fetch of $remote_ref; the inventory may be stale: $fetch_error"
  printf '%s\n' "$fetch_failure_error" >&2
  emit_apply_result 'failed' '' "$fetch_failure_error"
  exit 1
fi

if [ "$has_base" != true ]; then
  printf 'cannot apply without a readable base revision\n' >&2
  emit_apply_result 'failed' '' 'cannot apply without a readable base revision'
  exit 1
fi

if jq -e 'any(.[]; .state == "conflict" or .state == "needs-decision")' <<<"$files" >/dev/null; then
  printf 'cannot apply while merge conflicts need a decision\n' >&2
  emit_apply_result 'failed' '' 'cannot apply while merge conflicts need a decision'
  exit 1
fi

# Same refusal as a merge conflict, for the same reason: the script cannot tell
# which half of the file is the machine's, and applying anyway would either
# drop a local pin or leave the update shadowed by the old copy.
if [ "$legacy_state" = 'needs-review' ]; then
  legacy_error="$legacy_mise_config still holds this repository's copy with local changes on top; review it, keep only the machine-local part, or re-run with DOTFILES_MIGRATE_MISE_CONFIG=1"
  printf '%s\n' "$legacy_error" >&2
  emit_apply_result 'failed' '' "$legacy_error"
  exit 1
fi

stage_dir="$work_dir/stage"
stage_paths=(
  "$stage_dir/mise/10-dotfiles.toml"
  "$stage_dir/mise/mise.lock"
  "$stage_dir/.claude/settings.json"
  "$stage_dir/.claude/statusline.sh"
  "$stage_dir/.config/dotfiles/update-notice.sh"
)
mkdir -p "$stage_dir"
for index in "${!repository_paths[@]}"; do
  repository_path="${repository_paths[$index]}"
  local_path="${local_paths[$index]}"
  state="$(jq -r ".[$index].state" <<<"$files")"
  stage_path="${stage_paths[$index]}"
  mkdir -p "$(dirname "$stage_path")"

  case "$state" in
    identical|unchanged-remote)
      if [ -e "$local_path" ]; then
        cp "$local_path" "$stage_path"
      fi
      ;;
    unchanged-local|missing-local)
      git -C "$repo" show "${remote_revision}:${repository_path}" > "$stage_path"
      ;;
    auto-merge)
      if [ "$repository_path" = '.claude/settings.json' ]; then
        remote_path="$work_dir/remote-settings.json"
        git -C "$repo" show "${remote_revision}:${repository_path}" > "$remote_path"
        jq --arg prefer local -f "$repo/.dotfiles/merge-settings.jq" \
          "$local_path" "$remote_path" > "$stage_path"
      else
        base_path="$work_dir/base-stage-$index"
        remote_path="$work_dir/remote-stage-$index"
        git -C "$repo" show "${base_revision}:${repository_path}" > "$base_path"
        git -C "$repo" show "${remote_revision}:${repository_path}" > "$remote_path"
        git merge-file -p "$local_path" "$base_path" "$remote_path" > "$stage_path"
      fi
      ;;
    *)
      printf 'cannot stage %s in state %s\n' "$repository_path" "$state" >&2
      emit_apply_result 'failed' '' "cannot stage $repository_path in state $state"
      exit 1
      ;;
  esac
done

mise_bin="${DOTFILES_APPLY_MISE_BIN:-mise}"

# Run mise the way this machine runs it: the global config is config.toml plus
# every fragment in conf.d/, with the lockfile beside them in the config
# directory. XDG_CONFIG_HOME is pinned alongside HOME because mise resolves that
# directory from XDG_CONFIG_HOME, and every path this script manages is under
# $home/.config — without it a machine with XDG_CONFIG_HOME set elsewhere would
# have its files updated here and its tools installed from a config over there.
run_mise() {
  HOME="$home" XDG_CONFIG_HOME="$home/.config" "$mise_bin" "$@" >&2
}

# Parse-check one staged fragment on its own, before anything is written.
# MISE_GLOBAL_CONFIG_FILE replaces the whole global config set with this single
# file, which is what isolation means here — and exactly why nothing that
# installs may use it: it also moves the lockfile mise looks for next to the
# named file, so pointing it at conf.d/10-dotfiles.toml would send mise looking
# for conf.d/mise.lock.
validate_staged_mise_config() {
  HOME="$home" XDG_CONFIG_HOME="$home/.config" MISE_GLOBAL_CONFIG_FILE="$1" "$mise_bin" tasks ls >/dev/null &&
    HOME="$home" XDG_CONFIG_HOME="$home/.config" MISE_GLOBAL_CONFIG_FILE="$1" "$mise_bin" ls >/dev/null
}

# The same two commands against the machine's real global config, once the
# staged files are in place.
validate_applied_mise_config() {
  HOME="$home" XDG_CONFIG_HOME="$home/.config" "$mise_bin" tasks ls >/dev/null &&
    HOME="$home" XDG_CONFIG_HOME="$home/.config" "$mise_bin" ls >/dev/null
}

validate_files() {
  local settings_path="$1"
  local statusline_path="$2"
  local notice_path="$3"

  jq empty "$settings_path" >/dev/null &&
    bash -n "$statusline_path" &&
    bash -n "$notice_path"
}

if ! validate_files "${stage_paths[2]}" "${stage_paths[3]}" "${stage_paths[4]}" ||
  ! validate_staged_mise_config "${stage_paths[0]}"; then
  printf 'staged configuration validation failed\n' >&2
  emit_apply_result 'failed' '' 'staged configuration validation failed'
  exit 1
fi

# Set before the backup directory exists so that rollback, which may run from
# the EXIT trap at any point after that, always finds them defined.
legacy_migrated=false
legacy_backup_file=''

backup_root="$home/.config/dotfiles/backups"
mkdir -p "$backup_root"
backup_path="$backup_root/$(date +%Y%m%d%H%M%S)-$$"
mkdir "$backup_path"
manifest_file="$backup_path/manifest.jsonl"
for index in "${!local_paths[@]}"; do
  local_path="${local_paths[$index]}"
  backup_file="$backup_path/$index"
  if [ -e "$local_path" ]; then
    cp -p "$local_path" "$backup_file"
    jq -n --arg local_path "$local_path" --arg backup_path "$backup_file" \
      '{localPath: $local_path, present: true, backupPath: $backup_path}' >> "$manifest_file"
  else
    jq -n --arg local_path "$local_path" \
      '{localPath: $local_path, present: false, backupPath: ""}' >> "$manifest_file"
  fi
done
jq -s '.' "$manifest_file" > "$backup_path/manifest.json"
rm "$manifest_file"
legacy_backup_file="$backup_path/legacy-config.toml"
transaction_active=true
transaction_phase='active'

rollback() {
  local index local_path backup_file present
  # A half-applied rollback is worse than either end state, and the signal that
  # would interrupt it has already been accounted for by the caller. Drop INT
  # and TERM for the duration; every caller exits afterwards, so nothing needs
  # them restored.
  trap '' INT TERM
  rollback_error_summary=''
  for index in "${!local_paths[@]}"; do
    local_path="${local_paths[$index]}"
    backup_file="$backup_path/$index"
    if ! present="$(jq -r ".[$index].present" "$backup_path/manifest.json")"; then
      rollback_error_summary="${rollback_error_summary}${rollback_error_summary:+, }$local_path"
      continue
    fi
    if [ "$present" = true ]; then
      if ! mkdir -p "$(dirname "$local_path")" || ! cp -p "$backup_file" "$local_path"; then
        rollback_error_summary="${rollback_error_summary}${rollback_error_summary:+, }$local_path"
      fi
    else
      if ! rm -f -- "$local_path"; then
        rollback_error_summary="${rollback_error_summary}${rollback_error_summary:+, }$local_path"
      fi
    fi
  done
  # Put a migrated config.toml back last: while it is in place it outranks
  # conf.d, so restoring it before the managed targets would briefly give the
  # machine the old copy on top of the new fragment.
  if [ "$legacy_migrated" = true ]; then
    if cp -p "$legacy_backup_file" "$legacy_mise_config"; then
      legacy_migrated=false
    else
      rollback_error_summary="${rollback_error_summary}${rollback_error_summary:+, }$legacy_mise_config"
    fi
  fi
  [ -z "$rollback_error_summary" ]
}

# Move the pre-conf.d copy out of the way, into this transaction's backup
# directory so that a rollback can put it back. Only ever called for a
# `migratable` inventory; every other state was settled before any writes.
migrate_legacy_mise_config() {
  [ "$legacy_state" = 'migratable' ] && [ -f "$legacy_mise_config" ] || return 0
  mv "$legacy_mise_config" "$legacy_backup_file" || return 1
  legacy_migrated=true
}

apply_stage() {
  local index local_path stage_path
  for index in "${!local_paths[@]}"; do
    local_path="${local_paths[$index]}"
    stage_path="${stage_paths[$index]}"
    mkdir -p "$(dirname "$local_path")" || return 1
    cp "$stage_path" "$local_path" || return 1
  done
}

rollback_with_error() {
  local error="$1"
  transaction_phase='rolling-back'
  if ! rollback; then
    error="$error; rollback failed for: $rollback_error_summary"
  fi
  transaction_active=false
  transaction_phase='rolled-back'
  printf '%s\n' "$error" >&2
  emit_apply_result 'rolled-back' "$backup_path" "$error"
  exit 1
}

# True once the revision file holds the revision this run is installing. Read
# from disk on purpose: the replacement is a single `mv`, and a signal arriving
# the instant it returns is delivered before any variable could record it.
revision_is_committed() {
  [ -f "$revision_file" ] || return 1
  [ "$(cat "$revision_file" 2>/dev/null)" = "$remote_revision" ]
}

# Tear down an interrupted transaction that never committed, then exit. Shared
# by the two phases that can be interrupted with work already applied.
interrupt_rollback() {
  local exit_code="$1"
  local error='transaction interrupted; external side effects may remain'

  transaction_phase='rolling-back'
  if ! rollback; then
    error="$error; rollback failed for: $rollback_error_summary"
  fi
  transaction_active=false
  transaction_phase='rolled-back'
  printf '%s\n' "$error" >&2
  emit_apply_result 'rolled-back' "$backup_path" "$error"
  exit "$exit_code"
}

# Signals are never deferred and resumed. A handler that records a flag and
# returns depends on bash resuming the function the signal interrupted, which
# it does not do reliably once the interruption lands inside a function call —
# the commit was silently lost on Linux while the same code worked on macOS.
# Every branch below settles the transaction and exits from the handler.
handle_signal() {
  local exit_code="$1"

  case "$transaction_phase" in
    committing)
      if revision_is_committed; then
        # The replacement landed. Finish the commit rather than tearing down a
        # transaction that is, on disk, already complete.
        transaction_committed=true
        transaction_phase='committed'
        emit_apply_result 'applied' "$backup_path" ''
        exit "$exit_code"
      fi
      interrupt_rollback "$exit_code"
      ;;
    active)
      interrupt_rollback "$exit_code"
      ;;
    *)
      exit "$exit_code"
      ;;
  esac
}

trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

if ! migrate_legacy_mise_config; then
  rollback_with_error "failed to move $legacy_mise_config aside"
fi

if ! apply_stage; then
  rollback_with_error 'failed to apply staged configuration'
fi

# The post-apply check is what the staged one cannot be: mise resolving the
# machine's whole global config, with the fragment just written in it and the
# old copy out of the way. Anything that only shows up in that combination —
# a conf.d fragment that a leftover config.toml contradicts — fails here, while
# the transaction can still be rolled back.
if ! validate_files "${local_paths[2]}" "${local_paths[3]}" "${local_paths[4]}" ||
  ! validate_applied_mise_config; then
  rollback_with_error 'post-apply configuration validation failed'
fi

if ! run_mise run --skip-tools setup:oci-plugin; then
  rollback_with_error 'mise run --skip-tools setup:oci-plugin failed; external side effects may remain'
fi
if ! run_mise install; then
  rollback_with_error 'mise install failed; external side effects may remain'
fi
if ! run_mise run setup:skills; then
  rollback_with_error 'mise run setup:skills failed; external side effects may remain'
fi
if ! run_mise run --skip-deps setup:codex; then
  rollback_with_error 'mise run --skip-deps setup:codex failed; external side effects may remain'
fi
if ! run_mise run --skip-deps setup:claude-plugins; then
  rollback_with_error 'mise run --skip-deps setup:claude-plugins failed; external side effects may remain'
fi

write_revision() {
  local revision_dir revision_temp

  revision_dir="$(dirname "$revision_file")"
  mkdir -p "$revision_dir" || return 1
  revision_temp="$(mktemp "$revision_dir/.revision.XXXXXX")" || return 1
  if ! printf '%s\n' "$remote_revision" > "$revision_temp"; then
    rm -f "$revision_temp"
    return 1
  fi
  if ! mv -f "$revision_temp" "$revision_file"; then
    rm -f "$revision_temp"
    return 1
  fi
}

transaction_phase='committing'
if ! write_revision; then
  transaction_phase='active'
  rollback_with_error 'failed to update revision; external side effects may remain'
fi
transaction_committed=true
transaction_phase='committed'
emit_apply_result 'applied' "$backup_path" ''
