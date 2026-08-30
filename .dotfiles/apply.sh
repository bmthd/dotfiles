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

files_file="$(mktemp)"
trap 'rm -f "$files_file"' EXIT
for index in "${!repository_paths[@]}"; do
  repository_path="${repository_paths[$index]}"
  local_path="${local_paths[$index]}"

  if [ "$has_base" != true ]; then
    state='needs-decision'
  elif [ ! -e "$local_path" ]; then
    state='missing-local'
  else
    base_blob="$(git -C "$repo" rev-parse "${base_revision}:${repository_path}")"
    remote_blob="$(git -C "$repo" rev-parse "${remote_revision}:${repository_path}")"
    local_blob="$(git hash-object "$local_path")"

    if [ "$local_blob" = "$remote_blob" ]; then
      state='identical'
    elif [ "$local_blob" = "$base_blob" ]; then
      state='unchanged-local'
    elif [ "$remote_blob" = "$base_blob" ]; then
      state='unchanged-remote'
    else
      state='needs-decision'
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

if [ "$command_name" = apply ]; then
  if [ "$has_base" != true ]; then
    printf 'cannot apply without a readable base revision\n' >&2
  else
    printf 'apply is not implemented yet\n' >&2
  fi
  exit 1
fi
