#!/usr/bin/env bash

set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/.dotfiles/apply.sh"
merge_settings="$(dirname "$script")/merge-settings.jq"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

repo="$test_dir/repo"
home="$test_dir/home"
mise_config="$home/custom/mise.toml"
mise_lock="$home/custom/mise.lock"
managed_targets=(
  "$mise_config"
  "$mise_lock"
  "$home/.claude/settings.json"
  "$home/.claude/statusline.sh"
  "$home/.config/dotfiles/update-notice.sh"
)

snapshot_managed_targets() {
  local target
  for target in "${managed_targets[@]}"; do
    if [ -e "$target" ]; then
      printf 'present %s %s\n' "$target" "$(git hash-object "$target")"
    else
      printf 'absent %s\n' "$target"
    fi
  done
}

assert_no_base_apply_does_not_write() {
  local before after
  before="$(snapshot_managed_targets)"
  if bash "$script" apply --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json >/dev/null 2>&1; then
    echo 'apply accepted no-base inventory' >&2
    exit 1
  fi
  after="$(snapshot_managed_targets)"
  [ "$after" = "$before" ] || {
    printf 'no-base apply changed managed targets:\nbefore:\n%s\nafter:\n%s\n' "$before" "$after" >&2
    exit 1
  }
}

mkdir -p "$repo" "$home/custom" "$home/.claude" "$home/.config/dotfiles"

# A wrong scalar preference or non-stable array merge must change this result.
printf '%s\n' \
  '{"array":["local","shared"],"nested":{"array":["nested-local"],"scalar":"local"},"scalar":"local"}' \
  > "$test_dir/local-settings.json"
printf '%s\n' \
  '{"array":["shared","remote"],"nested":{"array":["nested-remote"],"scalar":"remote","remoteOnly":true},"scalar":"remote","remoteOnly":true}' \
  > "$test_dir/remote-settings.json"

local_settings_merge="$(jq --arg prefer local -f "$merge_settings" "$test_dir/local-settings.json" "$test_dir/remote-settings.json")"
printf '%s' "$local_settings_merge" | jq -e \
  '.array == ["local", "shared", "remote"]
   and .nested.array == ["nested-local", "nested-remote"]
   and .nested.scalar == "local"
   and .scalar == "local"
   and .nested.remoteOnly == true
   and .remoteOnly == true' >/dev/null

remote_settings_merge="$(jq --arg prefer remote -f "$merge_settings" "$test_dir/local-settings.json" "$test_dir/remote-settings.json")"
printf '%s' "$remote_settings_merge" | jq -e \
  '.array == ["local", "shared", "remote"]
   and .nested.array == ["nested-local", "nested-remote"]
   and .nested.scalar == "remote"
   and .scalar == "remote"' >/dev/null

git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test

mkdir -p "$repo/.claude" "$repo/.dotfiles"
printf '%s\n' 'base-mise' > "$repo/.mise.toml"
printf '%s\n' 'base-lock' > "$repo/mise.lock"
printf '%s\n' '{"base":true}' > "$repo/.claude/settings.json"
printf '%s\n' '#!/usr/bin/env bash' 'echo base-statusline' > "$repo/.claude/statusline.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo base-notice' > "$repo/.dotfiles/update-notice.sh"
git -C "$repo" add .
git -C "$repo" commit -qm base
base_revision="$(git -C "$repo" rev-parse HEAD)"

printf '%s\n' 'remote-mise' > "$repo/.mise.toml"
git -C "$repo" add .mise.toml
git -C "$repo" commit -qm remote
remote_revision="$(git -C "$repo" rev-parse HEAD)"

cp "$repo/mise.lock" "$home/custom/mise.lock"
printf '%s\n' 'base-mise' > "$mise_config"
cp "$repo/.claude/settings.json" "$home/.claude/settings.json"
cp "$repo/.claude/statusline.sh" "$home/.claude/statusline.sh"
mkdir -p "$home/.config/dotfiles"
cp "$repo/.dotfiles/update-notice.sh" "$home/.config/dotfiles/update-notice.sh"
printf '%s\n' "$base_revision" > "$home/.config/dotfiles/revision"

inventory="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json)"
printf '%s' "$inventory" | jq -e \
  --arg base "$base_revision" \
  --arg remote "$remote_revision" \
  --arg local "$mise_config" \
  '.mode == "inventory"
   and .fetch == "skipped"
   and .fetchError == ""
   and .baseRevision == $base
   and .remoteRevision == $remote
   and (.files | length == 5
                  and any(.[]; .repositoryPath == ".mise.toml"
                                 and .localPath == $local
                                 and .state == "unchanged-local"))' >/dev/null

printf '%s\n' 'dddddddddddddddddddddddddddddddddddddddd' > "$home/.config/dotfiles/revision"
no_base="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json)"
printf '%s' "$no_base" | jq -e \
  '.mode == "no-base"
   and .baseRevision == "dddddddddddddddddddddddddddddddddddddddd"
   and ([.files[].state] | all(. == "needs-decision"))' >/dev/null
assert_no_base_apply_does_not_write

rm "$home/.config/dotfiles/revision" "$home/.config/dotfiles/update-notice.sh"
missing_revision="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json)"
printf '%s' "$missing_revision" | jq -e \
  '.mode == "no-base"
   and .baseRevision == ""
   and ([.files[].state] | all(. == "needs-decision"))' >/dev/null
assert_no_base_apply_does_not_write

printf '%s\n' "$base_revision" > "$home/.config/dotfiles/revision"
printf '%s\n' '#!/usr/bin/env bash' 'echo remote-statusline' > "$repo/.claude/statusline.sh"
git -C "$repo" add .claude/statusline.sh
git -C "$repo" commit -qm remote-statusline
printf '%s\n' '#!/usr/bin/env bash' 'echo local-statusline' > "$home/.claude/statusline.sh"

conflict_inventory="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json)"
printf '%s' "$conflict_inventory" | jq -e \
  'any(.files[]; .repositoryPath == ".claude/statusline.sh" and .state == "conflict")' >/dev/null

before_conflict_apply="$(snapshot_managed_targets)"
if bash "$script" apply --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --mise-lock "$mise_lock" --json >/dev/null 2>&1; then
  echo 'apply accepted a text merge conflict' >&2
  exit 1
fi
after_conflict_apply="$(snapshot_managed_targets)"
[ "$after_conflict_apply" = "$before_conflict_apply" ] || {
  printf 'conflicted apply changed managed targets:\nbefore:\n%s\nafter:\n%s\n' "$before_conflict_apply" "$after_conflict_apply" >&2
  exit 1
}
[ "$(tail -n 1 "$home/.claude/statusline.sh")" = 'echo local-statusline' ] || {
  echo 'apply overwrote local text at a merge conflict' >&2
  exit 1
}

transaction_dir="$test_dir/transaction"
transaction_repo="$transaction_dir/repo"
transaction_home="$transaction_dir/home"
transaction_mise_config="$transaction_home/custom/selected-mise.toml"
transaction_mise_lock="$transaction_home/custom/mise.lock"
fake_mise="$transaction_dir/fake-mise"
mise_log="$transaction_dir/mise.log"
fake_bin="$transaction_dir/bin"
restore_log="$transaction_dir/restore.log"

mkdir -p "$transaction_dir" "$fake_bin"
# MISE_GLOBAL_CONFIG_FILE names one file and replaces the whole global config
# with it, so it is set only while a staged fragment is being parse-checked in
# isolation. Every other call reads the machine's real global config, which
# here means whatever apply wrote to the selected --mise-config;
# MISE_EFFECTIVE_CONFIG is how this double is told where that is.
cat > "$fake_mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'HOME=%s XDG=%s CONFIG=%s ARGS=%s\n' \
  "$HOME" "${XDG_CONFIG_HOME:-<none>}" "${MISE_GLOBAL_CONFIG_FILE:-<none>}" "$*" >> "$MISE_LOG"
config="${MISE_GLOBAL_CONFIG_FILE:-${MISE_EFFECTIVE_CONFIG:-}}"
[ -n "$config" ] && [ -f "$config" ]
if grep -q 'invalid-toml' "$config"; then
  exit 2
fi
if [ "${MISE_FAIL_POST_VALIDATE:-}" = true ] && [ "$*" = 'tasks ls' ] \
  && [ -z "${MISE_GLOBAL_CONFIG_FILE:-}" ]; then
  exit 33
fi
if [ "${MISE_SIGNAL_AT:-}" = "$*" ]; then
  kill -TERM "$PPID"
fi
if [ "${MISE_FAIL_AT:-}" = "$*" ]; then
  exit 42
fi
EOF
chmod +x "$fake_mise"

cat > "$fake_bin/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source_path=''
for argument in "$@"; do
  case "$argument" in
    -*) ;;
    *) source_path="$argument"; break ;;
  esac
done
destination_path="${!#}"
if [[ "$source_path" == */backups/* ]] && [ -n "${DOTFILES_RESTORE_LOG:-}" ]; then
  printf '%s\n' "$destination_path" >> "$DOTFILES_RESTORE_LOG"
fi
if [ "${DOTFILES_FAIL_RESTORE_INDEX:-}" = "${source_path##*/}" ] && [[ "$source_path" == */backups/* ]]; then
  exit 43
fi
exec /bin/cp "$@"
EOF
chmod +x "$fake_bin/cp"

cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${DOTFILES_FAIL_REVISION_MOVE:-}" = true ]; then
  exit 44
fi
/bin/mv "$@"
move_status=$?
if [ "${DOTFILES_SIGNAL_AFTER_REVISION_MOVE:-}" = true ] && [ "$move_status" -eq 0 ]; then
  kill -TERM "$PPID"
fi
exit "$move_status"
EOF
chmod +x "$fake_bin/mv"

# The repository's own copy carries the raw.githubusercontent.com URL its setup
# tasks fetch from, and that is the marker the shared layout rules use to tell a
# copy of this repository from a config.toml written for one machine.
transaction_base_mise=$'# from https://raw.githubusercontent.com/bmthd/dotfiles\n[tools]\nnode = "20"'
transaction_remote_mise=$'# from https://raw.githubusercontent.com/bmthd/dotfiles\n[tools]\nnode = "22"'
transaction_legacy_config="$transaction_home/.config/mise/config.toml"

write_legacy_mise_config() {
  mkdir -p "$(dirname "$transaction_legacy_config")"
  printf '%s\n' "$1" > "$transaction_legacy_config"
}

legacy_state_of() {
  bash "$script" plan --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
    --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json |
    jq -r '.legacyMiseConfig.state'
}

setup_transaction_fixture() {
  rm -rf "$transaction_repo" "$transaction_home" "$mise_log" "$restore_log"
  mkdir -p "$transaction_repo/.claude" "$transaction_repo/.dotfiles" \
    "$transaction_home/custom" "$transaction_home/.claude" \
    "$transaction_home/.config/dotfiles"
  git -C "$transaction_repo" init -q
  git -C "$transaction_repo" config user.email test@example.com
  git -C "$transaction_repo" config user.name test

  printf '%s\n' "$transaction_base_mise" > "$transaction_repo/.mise.toml"
  printf '%s\n' 'base-lock' > "$transaction_repo/mise.lock"
  printf '%s\n' '{"base":true}' > "$transaction_repo/.claude/settings.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo base-statusline' > "$transaction_repo/.claude/statusline.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo base-notice' > "$transaction_repo/.dotfiles/update-notice.sh"
  git -C "$transaction_repo" add .
  git -C "$transaction_repo" commit -qm base
  transaction_base_revision="$(git -C "$transaction_repo" rev-parse HEAD)"

  printf '%s\n' "$transaction_remote_mise" > "$transaction_repo/.mise.toml"
  printf '%s\n' 'remote-lock' > "$transaction_repo/mise.lock"
  printf '%s\n' '{"base":true,"remote":true}' > "$transaction_repo/.claude/settings.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo remote-statusline' > "$transaction_repo/.claude/statusline.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo remote-notice' > "$transaction_repo/.dotfiles/update-notice.sh"
  git -C "$transaction_repo" add .
  git -C "$transaction_repo" commit -qm remote
  transaction_remote_revision="$(git -C "$transaction_repo" rev-parse HEAD)"

  cp "$transaction_repo/.mise.toml" "$transaction_mise_config"
  git -C "$transaction_repo" show "${transaction_base_revision}:mise.lock" > "$transaction_mise_lock"
  git -C "$transaction_repo" show "${transaction_base_revision}:.claude/settings.json" > "$transaction_home/.claude/settings.json"
  git -C "$transaction_repo" show "${transaction_base_revision}:.claude/statusline.sh" > "$transaction_home/.claude/statusline.sh"
  git -C "$transaction_repo" show "${transaction_base_revision}:.dotfiles/update-notice.sh" > "$transaction_home/.config/dotfiles/update-notice.sh"
  git -C "$transaction_repo" show "${transaction_base_revision}:.mise.toml" > "$transaction_mise_config"
  printf '%s\n' "$transaction_base_revision" > "$transaction_home/.config/dotfiles/revision"
}

snapshot_transaction_targets() {
  local target
  for target in \
    "$transaction_mise_config" \
    "$transaction_mise_lock" \
    "$transaction_home/.claude/settings.json" \
    "$transaction_home/.claude/statusline.sh" \
    "$transaction_home/.config/dotfiles/update-notice.sh"; do
    if [ -e "$target" ]; then
      printf 'present %s %s\n' "$target" "$(git hash-object "$target")"
    else
      printf 'absent %s\n' "$target"
    fi
  done
}

# This fails if apply does not restore every overwritten byte sequence, remove
# newly-created targets, keep the revision, and preserve an absence manifest.
setup_transaction_fixture
rm "$transaction_home/.config/dotfiles/update-notice.sh"
before_rollback="$(snapshot_transaction_targets)"
if rollback_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" MISE_FAIL_AT='install' \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/rollback.err")"; then
  echo 'apply accepted a failing mise install' >&2
  exit 1
fi
printf '%s' "$rollback_result" | jq -e \
  --arg base "$transaction_base_revision" \
  '.result == "rolled-back" and (.backupPath | type == "string" and length > 0) and (.error | type == "string" and length > 0)' >/dev/null
rollback_backup_path="$(printf '%s' "$rollback_result" | jq -r '.backupPath')"
[ -f "$rollback_backup_path/manifest.json" ] || {
  echo 'rollback did not leave a backup manifest' >&2
  exit 1
}
jq -e --arg path "$transaction_home/.config/dotfiles/update-notice.sh" \
  'any(.[]; .localPath == $path and .present == false)' "$rollback_backup_path/manifest.json" >/dev/null
after_rollback="$(snapshot_transaction_targets)"
[ "$after_rollback" = "$before_rollback" ] || {
  printf 'rollback did not restore all managed targets:\nbefore:\n%s\nafter:\n%s\n' "$before_rollback" "$after_rollback" >&2
  exit 1
}
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_base_revision" ] || {
  echo 'rollback advanced revision' >&2
  exit 1
}

# This fails if one restore error stops rollback before every remaining target
# has been attempted.  Target 0 is deliberately left unrestored; 1-4 must
# still be restored and the structured error must name the failed path.
setup_transaction_fixture
before_partial_rollback="$(snapshot_transaction_targets)"
if partial_rollback_result="$(PATH="$fake_bin:$PATH" DOTFILES_RESTORE_LOG="$restore_log" DOTFILES_FAIL_RESTORE_INDEX=0 \
  DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" MISE_FAIL_AT='install' \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/partial-rollback.err")"; then
  echo 'apply accepted a failing mise install with restore failure' >&2
  exit 1
fi
printf '%s' "$partial_rollback_result" | jq -e --arg path "$transaction_mise_config" \
  '.result == "rolled-back" and (.error | contains($path))' >/dev/null
expected_restore_log=$(printf '%s\n' \
  "$transaction_mise_config" \
  "$transaction_mise_lock" \
  "$transaction_home/.claude/settings.json" \
  "$transaction_home/.claude/statusline.sh" \
  "$transaction_home/.config/dotfiles/update-notice.sh")
[ "$(<"$restore_log")" = "$expected_restore_log" ] || {
  printf 'rollback did not attempt every target:\n%s\n' "$(<"$restore_log")" >&2
  exit 1
}
[ "$(<"$transaction_mise_config")" = "$transaction_remote_mise" ] || {
  echo 'injected restore failure did not leave target 0 applied' >&2
  exit 1
}
for target in \
  "$transaction_mise_lock" \
  "$transaction_home/.claude/settings.json" \
  "$transaction_home/.claude/statusline.sh" \
  "$transaction_home/.config/dotfiles/update-notice.sh"; do
  printf '%s' "$before_partial_rollback" | grep -F "present $target $(git hash-object "$target")" >/dev/null || {
    echo "rollback did not restore $target after an earlier error" >&2
    exit 1
  }
done

# This fails if post-apply validation is not a transaction boundary.  The fake
# parser accepts the staged config but rejects the selected config after it is
# copied into HOME, so all target bytes and the initially absent target must be
# restored.
setup_transaction_fixture
rm "$transaction_home/.config/dotfiles/update-notice.sh"
before_post_validation="$(snapshot_transaction_targets)"
if post_validation_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  MISE_FAIL_POST_VALIDATE=true \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/post-validation.err")"; then
  echo 'apply accepted malformed post-apply TOML' >&2
  exit 1
fi
printf '%s' "$post_validation_result" | jq -e \
  '.result == "rolled-back" and (.error | contains("post-apply configuration validation failed"))' >/dev/null
[ "$(snapshot_transaction_targets)" = "$before_post_validation" ] || {
  echo 'post-apply validation did not restore all managed targets' >&2
  exit 1
}
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_base_revision" ] || {
  echo 'post-apply validation advanced revision' >&2
  exit 1
}

# This fails if an interrupt during a long-running setup task bypasses the
# transaction cleanup and leaves managed files applied with the old revision.
setup_transaction_fixture
rm "$transaction_home/.config/dotfiles/update-notice.sh"
before_interrupt="$(snapshot_transaction_targets)"
if interrupt_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" MISE_SIGNAL_AT='install' \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/interrupt.err")"; then
  echo 'apply accepted an interrupt during mise install' >&2
  exit 1
fi
printf '%s' "$interrupt_result" | jq -e \
  '.result == "rolled-back" and (.error | contains("interrupted"))' >/dev/null
[ "$(snapshot_transaction_targets)" = "$before_interrupt" ] || {
  echo 'interrupt did not rollback all managed targets' >&2
  exit 1
}
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_base_revision" ] || {
  echo 'interrupt advanced revision' >&2
  exit 1
}

# This fails if an atomic revision replacement error leaves applied targets or
# truncates the old revision.  The test intercepts only mv after all tasks.
setup_transaction_fixture
before_revision_failure="$(snapshot_transaction_targets)"
revision_before="$(<"$transaction_home/.config/dotfiles/revision")"
if revision_failure_result="$(PATH="$fake_bin:$PATH" DOTFILES_FAIL_REVISION_MOVE=true \
  DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/revision.err")"; then
  echo 'apply accepted a failing atomic revision replacement' >&2
  exit 1
fi
printf '%s' "$revision_failure_result" | jq -e \
  '.result == "rolled-back" and (.error | contains("failed to update revision"))' >/dev/null
[ "$(snapshot_transaction_targets)" = "$before_revision_failure" ] || {
  echo 'revision update failure did not rollback all managed targets' >&2
  exit 1
}
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$revision_before" ] || {
  echo 'revision update failure damaged the previous revision' >&2
  exit 1
}

# This fails if TERM is handled between a successful revision replacement and
# the transaction commit marker.  The wrapper replaces revision first, signals
# the parent before returning, and the outcome must still be internally
# consistent.  This implementation chooses a fully committed outcome.
setup_transaction_fixture
if revision_signal_result="$(PATH="$fake_bin:$PATH" DOTFILES_SIGNAL_AFTER_REVISION_MOVE=true \
  DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/revision-signal.err")"; then
  echo 'apply accepted TERM immediately after revision replacement' >&2
  exit 1
fi
printf '%s' "$revision_signal_result" | jq -e \
  '.result == "applied" and .error == ""' >/dev/null
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_remote_revision" ] || {
  echo 'revision signal did not leave the new revision committed' >&2
  exit 1
}
transaction_repository_paths=(
  '.mise.toml'
  'mise.lock'
  '.claude/settings.json'
  '.claude/statusline.sh'
  '.dotfiles/update-notice.sh'
)
transaction_target_paths=(
  "$transaction_mise_config"
  "$transaction_mise_lock"
  "$transaction_home/.claude/settings.json"
  "$transaction_home/.claude/statusline.sh"
  "$transaction_home/.config/dotfiles/update-notice.sh"
)
for index in 0 1 2 3 4; do
  [ "$(git hash-object "${transaction_target_paths[$index]}")" = "$(git -C "$transaction_repo" rev-parse "${transaction_remote_revision}:${transaction_repository_paths[$index]}")" ] || {
    echo "revision signal left target $index inconsistent with revision" >&2
    exit 1
  }
done

# This fails if dangling symlinks are treated as absent and followed while
# applying staged output.  A safe implementation rejects the target before it
# can create the dangling referent or a backup transaction.
setup_transaction_fixture
dangling_target="$transaction_home/dangling-mise-target"
rm "$transaction_mise_config"
ln -s "$dangling_target" "$transaction_mise_config"
if DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json >/dev/null 2>"$transaction_dir/dangling.err"; then
  echo 'apply accepted a dangling managed symlink' >&2
  exit 1
fi
[ -L "$transaction_mise_config" ] && [ ! -e "$dangling_target" ] && [ ! -e "$transaction_home/.config/dotfiles/backups" ] || {
  echo 'dangling managed symlink was mutated before rejection' >&2
  exit 1
}

# This fails if malformed staged TOML is allowed to reach HOME or create a
# backup.  The fake parser only accepts the config file passed through the
# configurable MISE_CONFIG_FILE seam.
setup_transaction_fixture
printf '%s\n' 'invalid-toml' > "$transaction_repo/.mise.toml"
git -C "$transaction_repo" add .mise.toml
git -C "$transaction_repo" commit -qm invalid-remote-mise
before_invalid_stage="$(snapshot_transaction_targets)"
if invalid_stage_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/invalid-stage.err")"; then
  echo 'apply accepted malformed staged TOML' >&2
  exit 1
fi
printf '%s' "$invalid_stage_result" | jq -e \
  '.result == "failed" and .backupPath == "" and (.error | contains("staged configuration validation failed"))' >/dev/null
[ "$(snapshot_transaction_targets)" = "$before_invalid_stage" ] || {
  echo 'staged validation wrote a managed target' >&2
  exit 1
}
[ ! -e "$transaction_home/.config/dotfiles/backups" ] || {
  echo 'staged validation created a backup' >&2
  exit 1
}

# This fails if the selected --mise-config is ignored, task invocation order or
# flags drift, or revision is advanced before the full transaction succeeds.
setup_transaction_fixture
success_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json)"
printf '%s' "$success_result" | jq -e \
  --arg remote "$transaction_remote_revision" \
  '.result == "applied" and .remoteRevision == $remote and (.backupPath | type == "string" and length > 0)' >/dev/null
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_remote_revision" ] || {
  echo 'successful apply did not advance revision' >&2
  exit 1
}
[ "$(<"$transaction_mise_config")" = "$transaction_remote_mise" ] || {
  echo '--mise-config did not receive the staged config' >&2
  exit 1
}
grep -vF "HOME=$transaction_home XDG=$transaction_home/.config " "$mise_log" >/dev/null && {
  printf 'mise inherited a HOME or config directory other than --home:\n%s\n' "$(<"$mise_log")" >&2
  exit 1
}
expected_mise_args=$'tasks ls\nls\ntasks ls\nls\nrun --skip-tools setup:oci-plugin\ninstall\nrun setup:skills\nrun --skip-deps setup:codex\nrun --skip-deps setup:claude-plugins'
[ "$(sed 's/^.* ARGS=//' "$mise_log")" = "$expected_mise_args" ] || {
  printf 'mise did not receive the selected HOME/config or expected task order:\n%s\n' "$(<"$mise_log")" >&2
  exit 1
}
# Only the two staged parse-checks may name a single config file. Everything
# from the post-apply validation onwards has to resolve the machine's real
# global config — config.toml plus conf.d, with the lockfile in the config
# directory — because MISE_GLOBAL_CONFIG_FILE would also move the lockfile mise
# looks for next to the named file.
expected_staged_mise_args=$'tasks ls\nls'
[ "$(grep -vF 'CONFIG=<none> ' "$mise_log" | sed 's/^.* ARGS=//')" = "$expected_staged_mise_args" ] || {
  printf 'more than the staged parse-check pinned a single config file:\n%s\n' "$(<"$mise_log")" >&2
  exit 1
}
expected_post_mise_args=$'tasks ls\nls\nrun --skip-tools setup:oci-plugin\ninstall\nrun setup:skills\nrun --skip-deps setup:codex\nrun --skip-deps setup:claude-plugins'
[ "$(grep -F 'CONFIG=<none> ' "$mise_log" | sed 's/^.* ARGS=//')" = "$expected_post_mise_args" ] || {
  printf 'post-apply mise calls did not resolve the real global config:\n%s\n' "$(<"$mise_log")" >&2
  exit 1
}

# --- the conf.d layout -------------------------------------------------------
# This fails if the defaults drift back to the pre-conf.d layout: the
# repository's copy belongs in conf.d/10-dotfiles.toml, and the lockfile beside
# config.toml rather than wherever the config path happens to point (#71).
default_home="$test_dir/default-home"
mkdir -p "$default_home/.config/dotfiles"
printf '%s\n' "$base_revision" > "$default_home/.config/dotfiles/revision"
default_plan="$(bash "$script" plan --home "$default_home" --repo "$repo" --remote-ref HEAD --json)"
printf '%s' "$default_plan" | jq -e \
  --arg config "$default_home/.config/mise/conf.d/10-dotfiles.toml" \
  --arg lock "$default_home/.config/mise/mise.lock" \
  'any(.files[]; .repositoryPath == ".mise.toml" and .localPath == $config)
   and any(.files[]; .repositoryPath == "mise.lock" and .localPath == $lock)' >/dev/null || {
  printf 'default placement is not the conf.d layout:\n%s\n' "$default_plan" >&2
  exit 1
}

# Choosing a config path must not drag the lockfile along with it: mise keys the
# global lockfile to the config directory, so a derived path lands in conf.d/
# where mise never looks for it.
selected_plan="$(bash "$script" plan --home "$default_home" --repo "$repo" --remote-ref HEAD \
  --mise-config "$default_home/.config/mise/conf.d/10-dotfiles.toml" --json)"
printf '%s' "$selected_plan" | jq -e \
  --arg lock "$default_home/.config/mise/mise.lock" \
  'any(.files[]; .repositoryPath == "mise.lock" and .localPath == $lock)' >/dev/null || {
  printf '--mise-config moved the lockfile with it:\n%s\n' "$selected_plan" >&2
  exit 1
}

# --- the pre-conf.d config.toml ----------------------------------------------
# A config.toml written for the machine carries none of this repository, so it
# is none of this script's business and must survive an apply untouched.
setup_transaction_fixture
write_legacy_mise_config $'[tools]\nripgrep = "latest"'
[ "$(legacy_state_of)" = 'unrelated' ] || {
  echo 'a hand-written config.toml was claimed as a copy of this repository' >&2
  exit 1
}

# The repository's own old copy, unchanged since the revision it was installed
# from: provably nothing of the machine's on top, so apply moves it aside — into
# the transaction backup, not into oblivion — and the conf.d fragment it was
# shadowing takes effect.
setup_transaction_fixture
write_legacy_mise_config "$transaction_base_mise"
[ "$(legacy_state_of)" = 'migratable' ] || {
  echo 'an unmodified copy of the repository config was not migratable' >&2
  exit 1
}
migrate_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json)"
printf '%s' "$migrate_result" | jq -e '.result == "applied"' >/dev/null
migrate_backup_path="$(printf '%s' "$migrate_result" | jq -r '.backupPath')"
[ ! -e "$transaction_legacy_config" ] || {
  echo 'apply left the old copy in config.toml, still shadowing conf.d' >&2
  exit 1
}
[ "$(<"$migrate_backup_path/legacy-config.toml")" = "$transaction_base_mise" ] || {
  echo 'apply did not keep the displaced config.toml in the backup' >&2
  exit 1
}

# The same file with the machine's own changes on top cannot be split by a
# script. Moving it would silently drop a pin before `mise install` runs, so
# apply refuses in the same way it refuses a merge conflict, and touches
# nothing.
setup_transaction_fixture
legacy_with_local_pin="$transaction_base_mise"$'\nripgrep = "14.1.0"'
write_legacy_mise_config "$legacy_with_local_pin"
[ "$(legacy_state_of)" = 'needs-review' ] || {
  echo 'a locally modified copy of the repository config was not held back' >&2
  exit 1
}
before_legacy_refusal="$(snapshot_transaction_targets)"
if legacy_refusal="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/legacy.err")"; then
  echo 'apply accepted a config.toml that still shadows conf.d' >&2
  exit 1
fi
printf '%s' "$legacy_refusal" | jq -e --arg path "$transaction_legacy_config" \
  '.result == "failed" and .backupPath == "" and (.error | contains($path))' >/dev/null
[ "$(<"$transaction_legacy_config")" = "$legacy_with_local_pin" ] || {
  echo 'the refused apply modified config.toml anyway' >&2
  exit 1
}
[ "$(snapshot_transaction_targets)" = "$before_legacy_refusal" ] || {
  echo 'the refused apply wrote a managed target' >&2
  exit 1
}

# The escape hatch, for a file whose local half has already been dealt with by
# hand. It is the same variable install.sh honours, because both read it from
# the shared layout rules.
[ "$(DOTFILES_MIGRATE_MISE_CONFIG=1 legacy_state_of)" = 'migratable' ] || {
  echo 'DOTFILES_MIGRATE_MISE_CONFIG=1 did not force the migration' >&2
  exit 1
}

# A rollback has to undo the migration too, or a failed apply leaves the machine
# without the config.toml it started with.
setup_transaction_fixture
write_legacy_mise_config "$transaction_base_mise"
if legacy_rollback="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_EFFECTIVE_CONFIG="$transaction_mise_config" \
  MISE_FAIL_AT='install' \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --mise-lock "$transaction_mise_lock" --json 2>"$transaction_dir/legacy-rollback.err")"; then
  echo 'apply accepted a failing mise install while migrating config.toml' >&2
  exit 1
fi
printf '%s' "$legacy_rollback" | jq -e '.result == "rolled-back"' >/dev/null
[ "$(<"$transaction_legacy_config")" = "$transaction_base_mise" ] || {
  echo 'rollback did not restore the displaced config.toml' >&2
  exit 1
}

# This fails if the script reads origin/main without fetching it first: the
# stale clone then reports the commit it was cloned at as the current remote
# revision, and a run against a moved origin/main looks like "no updates".
fetch_dir="$test_dir/fetch"
upstream="$fetch_dir/upstream"
checkout="$fetch_dir/checkout"
fetch_home="$fetch_dir/home"
fetch_mise_config="$fetch_home/custom/mise.toml"
fetch_mise_lock="$fetch_home/custom/mise.lock"

fetch_managed_targets=(
  "$fetch_mise_config"
  "$fetch_mise_lock"
  "$fetch_home/.claude/settings.json"
  "$fetch_home/.claude/statusline.sh"
  "$fetch_home/.config/dotfiles/update-notice.sh"
)

snapshot_fetch_targets() {
  local target
  for target in "${fetch_managed_targets[@]}"; do
    if [ -e "$target" ]; then
      printf 'present %s %s\n' "$target" "$(git hash-object "$target")"
    else
      printf 'absent %s\n' "$target"
    fi
  done
}

mkdir -p "$upstream/.claude" "$upstream/.dotfiles" \
  "$fetch_home/custom" "$fetch_home/.claude" "$fetch_home/.config/dotfiles"
git -C "$upstream" init -q -b main
git -C "$upstream" config user.email test@example.com
git -C "$upstream" config user.name test
printf '%s\n' '[tools]' 'node = "20"' > "$upstream/.mise.toml"
printf '%s\n' 'base-lock' > "$upstream/mise.lock"
printf '%s\n' '{"base":true}' > "$upstream/.claude/settings.json"
printf '%s\n' '#!/usr/bin/env bash' 'echo base-statusline' > "$upstream/.claude/statusline.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo base-notice' > "$upstream/.dotfiles/update-notice.sh"
git -C "$upstream" add .
git -C "$upstream" commit -qm base
fetch_base_revision="$(git -C "$upstream" rev-parse HEAD)"

git clone -q "$upstream" "$checkout"
cp "$checkout/.mise.toml" "$fetch_mise_config"
cp "$checkout/mise.lock" "$fetch_mise_lock"
cp "$checkout/.claude/settings.json" "$fetch_home/.claude/settings.json"
cp "$checkout/.claude/statusline.sh" "$fetch_home/.claude/statusline.sh"
cp "$checkout/.dotfiles/update-notice.sh" "$fetch_home/.config/dotfiles/update-notice.sh"
printf '%s\n' "$fetch_base_revision" > "$fetch_home/.config/dotfiles/revision"

printf '%s\n' '[tools]' 'node = "22"' > "$upstream/.mise.toml"
git -C "$upstream" add .mise.toml
git -C "$upstream" commit -qm moved
fetch_moved_revision="$(git -C "$upstream" rev-parse HEAD)"

fetched_inventory="$(bash "$script" plan --home "$fetch_home" --repo "$checkout" \
  --mise-config "$fetch_mise_config" --mise-lock "$fetch_mise_lock" --json)"
printf '%s' "$fetched_inventory" | jq -e \
  --arg remote "$fetch_moved_revision" \
  '.fetch == "ok"
   and .fetchError == ""
   and .remoteRevision == $remote
   and any(.files[]; .repositoryPath == ".mise.toml" and .state == "unchanged-local")' >/dev/null

# This fails if a fetch failure is swallowed: the inventory is then built from
# the last successful fetch while claiming to describe the current remote.
git -C "$upstream" commit -q --allow-empty -m unreachable
git -C "$checkout" remote set-url origin "$fetch_dir/missing-upstream"

failed_fetch_inventory="$(bash "$script" plan --home "$fetch_home" --repo "$checkout" \
  --mise-config "$fetch_mise_config" --mise-lock "$fetch_mise_lock" --json)"
printf '%s' "$failed_fetch_inventory" | jq -e \
  --arg remote "$fetch_moved_revision" \
  '.fetch == "failed"
   and (.fetchError | type == "string" and length > 0)
   and .remoteRevision == $remote' >/dev/null

before_failed_fetch_apply="$(snapshot_fetch_targets)"
if failed_fetch_apply="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" \
  bash "$script" apply --home "$fetch_home" --repo "$checkout" \
  --mise-config "$fetch_mise_config" --mise-lock "$fetch_mise_lock" --json 2>"$fetch_dir/failed-fetch.err")"; then
  echo 'apply accepted a failed fetch' >&2
  exit 1
fi
printf '%s' "$failed_fetch_apply" | jq -e \
  '.fetch == "failed" and .result == "failed" and (.error | contains("failed fetch"))' >/dev/null
[ "$(snapshot_fetch_targets)" = "$before_failed_fetch_apply" ] || {
  echo 'apply after a failed fetch changed managed targets' >&2
  exit 1
}
[ "$(<"$fetch_home/.config/dotfiles/revision")" = "$fetch_base_revision" ] || {
  echo 'apply after a failed fetch advanced revision' >&2
  exit 1
}

echo "apply tests passed"
