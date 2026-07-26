#!/usr/bin/env bash

set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

config_dir="$test_dir/config"
fake_git="$test_dir/git"

cat > "$fake_git" <<'EOF'
#!/usr/bin/env bash
printf '%s\trefs/heads/main\n' "${DOTFILES_TEST_REMOTE_REVISION}"
EOF
chmod +x "$fake_git"

export DOTFILES_CONFIG_DIR="$config_dir"
export DOTFILES_GIT_BIN="$fake_git"
export DOTFILES_TEST_REMOTE_REVISION="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# shellcheck disable=SC1091
source "$(dirname "$0")/../.dotfiles/update-notice.sh"

bash "$(dirname "$0")/../.dotfiles/update-notice.sh" install
[[ "$(< "$config_dir/revision")" == "$DOTFILES_TEST_REMOTE_REVISION" ]]

export DOTFILES_TEST_REMOTE_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
output="$(dotfiles_update_notice_check)"
[[ "$output" == *"dotfiles の更新があります"* ]]
[[ "$output" == *"curl -fsSL"* ]]

printf '%s\n' "$(date +%s)" > "$config_dir/last-update-check"
if dotfiles_update_notice_check | grep -q 'dotfiles の更新があります'; then
  echo "check interval was ignored" >&2
  exit 1
fi

echo "update notice tests passed"
