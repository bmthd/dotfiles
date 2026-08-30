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

echo "apply tests passed"
