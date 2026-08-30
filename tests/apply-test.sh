#!/usr/bin/env bash

set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/.dotfiles/apply.sh"
merge_settings="$(dirname "$script")/merge-settings.jq"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

repo="$test_dir/repo"
home="$test_dir/home"
mise_config="$home/custom/mise.toml"
managed_targets=(
  "$mise_config"
  "$(dirname "$mise_config")/mise.lock"
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
  if bash "$script" apply --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json >/dev/null 2>&1; then
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

inventory="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json)"
printf '%s' "$inventory" | jq -e \
  --arg base "$base_revision" \
  --arg remote "$remote_revision" \
  --arg local "$mise_config" \
  '.mode == "inventory"
   and .baseRevision == $base
   and .remoteRevision == $remote
   and (.files | length == 5
                  and any(.[]; .repositoryPath == ".mise.toml"
                                 and .localPath == $local
                                 and .state == "unchanged-local"))' >/dev/null

printf '%s\n' 'dddddddddddddddddddddddddddddddddddddddd' > "$home/.config/dotfiles/revision"
no_base="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json)"
printf '%s' "$no_base" | jq -e \
  '.mode == "no-base"
   and .baseRevision == "dddddddddddddddddddddddddddddddddddddddd"
   and ([.files[].state] | all(. == "needs-decision"))' >/dev/null
assert_no_base_apply_does_not_write

rm "$home/.config/dotfiles/revision" "$home/.config/dotfiles/update-notice.sh"
missing_revision="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json)"
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

conflict_inventory="$(bash "$script" plan --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json)"
printf '%s' "$conflict_inventory" | jq -e \
  'any(.files[]; .repositoryPath == ".claude/statusline.sh" and .state == "conflict")' >/dev/null

before_conflict_apply="$(snapshot_managed_targets)"
if bash "$script" apply --home "$home" --repo "$repo" --remote-ref HEAD --mise-config "$mise_config" --json >/dev/null 2>&1; then
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
fake_mise="$transaction_dir/fake-mise"
mise_log="$transaction_dir/mise.log"

mkdir -p "$transaction_dir"
cat > "$fake_mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MISE_LOG"
[ -n "${MISE_CONFIG_FILE:-}" ] && [ -f "$MISE_CONFIG_FILE" ]
if grep -q 'invalid-toml' "$MISE_CONFIG_FILE"; then
  exit 2
fi
if [ "${MISE_FAIL_AT:-}" = "$*" ]; then
  exit 42
fi
EOF
chmod +x "$fake_mise"

setup_transaction_fixture() {
  rm -rf "$transaction_repo" "$transaction_home" "$mise_log"
  mkdir -p "$transaction_repo/.claude" "$transaction_repo/.dotfiles" \
    "$transaction_home/custom" "$transaction_home/.claude" \
    "$transaction_home/.config/dotfiles"
  git -C "$transaction_repo" init -q
  git -C "$transaction_repo" config user.email test@example.com
  git -C "$transaction_repo" config user.name test

  printf '%s\n' '[tools]' 'node = "20"' > "$transaction_repo/.mise.toml"
  printf '%s\n' 'base-lock' > "$transaction_repo/mise.lock"
  printf '%s\n' '{"base":true}' > "$transaction_repo/.claude/settings.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo base-statusline' > "$transaction_repo/.claude/statusline.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo base-notice' > "$transaction_repo/.dotfiles/update-notice.sh"
  git -C "$transaction_repo" add .
  git -C "$transaction_repo" commit -qm base
  transaction_base_revision="$(git -C "$transaction_repo" rev-parse HEAD)"

  printf '%s\n' '[tools]' 'node = "22"' > "$transaction_repo/.mise.toml"
  printf '%s\n' 'remote-lock' > "$transaction_repo/mise.lock"
  printf '%s\n' '{"base":true,"remote":true}' > "$transaction_repo/.claude/settings.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo remote-statusline' > "$transaction_repo/.claude/statusline.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo remote-notice' > "$transaction_repo/.dotfiles/update-notice.sh"
  git -C "$transaction_repo" add .
  git -C "$transaction_repo" commit -qm remote
  transaction_remote_revision="$(git -C "$transaction_repo" rev-parse HEAD)"

  cp "$transaction_repo/.mise.toml" "$transaction_mise_config"
  git -C "$transaction_repo" show "${transaction_base_revision}:mise.lock" > "$transaction_home/custom/mise.lock"
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
    "$transaction_home/custom/mise.lock" \
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
if rollback_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" MISE_FAIL_AT='install' \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --json 2>"$transaction_dir/rollback.err")"; then
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

# This fails if malformed staged TOML is allowed to reach HOME or create a
# backup.  The fake parser only accepts the config file passed through the
# configurable MISE_CONFIG_FILE seam.
setup_transaction_fixture
printf '%s\n' 'invalid-toml' > "$transaction_repo/.mise.toml"
git -C "$transaction_repo" add .mise.toml
git -C "$transaction_repo" commit -qm invalid-remote-mise
before_invalid_stage="$(snapshot_transaction_targets)"
if invalid_stage_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --json 2>"$transaction_dir/invalid-stage.err")"; then
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
success_result="$(DOTFILES_APPLY_MISE_BIN="$fake_mise" MISE_LOG="$mise_log" \
  bash "$script" apply --home "$transaction_home" --repo "$transaction_repo" --remote-ref HEAD \
  --mise-config "$transaction_mise_config" --json)"
printf '%s' "$success_result" | jq -e \
  --arg remote "$transaction_remote_revision" \
  '.result == "applied" and .remoteRevision == $remote and (.backupPath | type == "string" and length > 0)' >/dev/null
[ "$(<"$transaction_home/.config/dotfiles/revision")" = "$transaction_remote_revision" ] || {
  echo 'successful apply did not advance revision' >&2
  exit 1
}
[ "$(<"$transaction_mise_config")" = $'[tools]\nnode = "22"' ] || {
  echo '--mise-config did not receive the staged config' >&2
  exit 1
}
expected_mise_log=$'tasks ls\nls\ntasks ls\nls\nrun --skip-tools setup:oci-plugin\ninstall\nrun setup:skills\nrun --skip-deps setup:codex\nrun --skip-deps setup:claude-plugins'
[ "$(<"$mise_log")" = "$expected_mise_log" ] || {
  printf 'unexpected mise invocation order:\n%s\n' "$(<"$mise_log")" >&2
  exit 1
}

echo "apply tests passed"
