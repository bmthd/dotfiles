#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: apply.sh plan|apply [--home HOME] [--repo REPO] [--remote-ref REF] [--mise-config PATH] [--json]
EOF
  exit 2
}

command_name="${1:-}"
case "$command_name" in
  plan|apply) shift ;;
  *) usage ;;
esac

home="$HOME"
repo="$(pwd)"
remote_ref="origin/main"
mise_config=""
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
    --json)
      json=true
      shift
      ;;
    *) usage ;;
  esac
done

if [ -z "$mise_config" ]; then
  mise_config="$home/.config/mise/config.toml"
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
  "$(dirname "$mise_config")/mise.lock"
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

if [ "$has_base" = true ]; then
  mode='inventory'
else
  mode='no-base'
fi

emit_inventory() {
if "$json"; then
  jq -n \
    --arg mode "$mode" \
    --arg base_revision "$base_revision" \
    --arg remote_revision "$remote_revision" \
    --argjson files "$files" \
    '{mode: $mode, baseRevision: $base_revision, remoteRevision: $remote_revision, files: $files}'
else
  printf 'mode: %s\nbase revision: %s\nremote revision: %s\n' \
    "$mode" "${base_revision:-<none>}" "$remote_revision"
  jq -r '.[] | "\(.state): \(.repositoryPath) -> \(.localPath)"' <<<"$files"
fi
}

emit_apply_result() {
  local result="$1"
  local backup_path="$2"
  local error="$3"

  if "$json"; then
    jq -n \
      --arg mode "$mode" \
      --arg base_revision "$base_revision" \
      --arg remote_revision "$remote_revision" \
      --arg result "$result" \
      --arg backup_path "$backup_path" \
      --arg error "$error" \
      --argjson files "$files" \
      '{mode: $mode, baseRevision: $base_revision, remoteRevision: $remote_revision,
        files: $files, result: $result, backupPath: $backup_path, error: $error}'
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

stage_dir="$work_dir/stage"
stage_paths=(
  "$stage_dir/mise/config.toml"
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

validate_paths() {
  local config_path="$1"
  local settings_path="$2"
  local statusline_path="$3"
  local notice_path="$4"

  jq empty "$settings_path" >/dev/null &&
    bash -n "$statusline_path" &&
    bash -n "$notice_path" &&
    HOME="$home" MISE_CONFIG_FILE="$config_path" "$mise_bin" tasks ls >/dev/null &&
    HOME="$home" MISE_CONFIG_FILE="$config_path" "$mise_bin" ls >/dev/null
}

if ! validate_paths "${stage_paths[0]}" "${stage_paths[2]}" "${stage_paths[3]}" "${stage_paths[4]}"; then
  printf 'staged configuration validation failed\n' >&2
  emit_apply_result 'failed' '' 'staged configuration validation failed'
  exit 1
fi

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
  [ -z "$rollback_error_summary" ]
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

if ! apply_stage; then
  rollback_with_error 'failed to apply staged configuration'
fi

if ! validate_paths "$mise_config" "${local_paths[2]}" "${local_paths[3]}" "${local_paths[4]}"; then
  rollback_with_error 'post-apply configuration validation failed'
fi

run_mise() {
  HOME="$home" MISE_CONFIG_FILE="$mise_config" "$mise_bin" "$@" >&2
}

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
