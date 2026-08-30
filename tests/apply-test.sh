#!/usr/bin/env bash

set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/.dotfiles/apply.sh"
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

echo "apply tests passed"
