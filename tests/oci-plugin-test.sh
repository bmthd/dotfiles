#!/usr/bin/env bash
# Verify that setup:oci-plugin migrates the legacy asdf checkout to vfox
# without reinstalling an already-correct plugin.
#
# The task is a one-line delegation to this script, so the script is what gets
# run here — the same file setup:scripts places on a machine.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
task_script="$repo/.dotfiles/setup/oci-plugin.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "plugins ls --urls" ]]; then
  [[ -z "${PLUGIN_URL:-}" ]] || printf 'oci  %s  HEAD abc123\n' "$PLUGIN_URL"
elif [[ "${1:-}" == "plugins" && "${2:-}" == "install" ]]; then
  printf '%s\n' "$*" >> "$CALL_LOG"
else
  echo "unexpected mise invocation: $*" >&2
  exit 1
fi
SH
chmod +x "$tmp/bin/mise"

run_case() {
  local plugin_url="$1"
  local expected="$2"
  : > "$tmp/calls"
  PATH="$tmp/bin:$PATH" PLUGIN_URL="$plugin_url" CALL_LOG="$tmp/calls" bash "$task_script" >/dev/null
  if [[ "$(cat "$tmp/calls")" != "$expected" ]]; then
    echo "✗ plugin URL $plugin_url produced the wrong install command" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $(cat "$tmp/calls")" >&2
    exit 1
  fi
}

vfox_url="https://github.com/jdx/vfox-oci.git"
run_case "https://github.com/mise-plugins/mise-oci.git" "plugins install --force oci $vfox_url"
run_case "git@github.com:mise-plugins/mise-oci.git" "plugins install --force oci $vfox_url"
run_case "https://example.com/custom-oci-plugin.git" "plugins install --force oci $vfox_url"
run_case "https://github.com/jdx/vfox-oci-fork.git" "plugins install --force oci $vfox_url"
run_case "" "plugins install oci $vfox_url"
run_case "$vfox_url" ""
run_case "git@github.com:jdx/vfox-oci.git" ""

bump_workflow="$repo/.github/workflows/bump-tools.yml"
if ! grep -q 'mise run --skip-tools setup:oci-plugin' "$bump_workflow"; then
  echo "✗ bump-tools does not use the same OCI vfox migration as installed machines" >&2
  exit 1
fi

echo "OCI plugin tests passed"
