#!/usr/bin/env bash
# Tests setup:codex preserves an existing Codex configuration while disabling
# the startup update prompt. Run with: bash tests/codex-setup-test.sh

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

mkdir -p "$temp/home/.codex"
cat > "$temp/home/.codex/config.toml" <<'EOF'
model = "gpt-6.1-sol"

[tui]
screen_reader_detection_done = true
EOF

HOME="$temp/home" PATH="/usr/bin:/bin" /usr/bin/env bash "$repo/.dotfiles/setup/codex.sh" >/dev/null

config="$temp/home/.codex/config.toml"
python3 - "$config" <<'PY'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text().splitlines()
table = next(i for i, line in enumerate(lines) if line == "[tui]")

if lines[0] != 'model = "gpt-6.1-sol"':
    raise SystemExit("✗ setup:codex changed the existing model setting")
if "check_for_update_on_startup = false" not in lines[:table]:
    raise SystemExit("✗ setup:codex did not disable Codex startup update checks at the top level")
PY

echo "✓ setup:codex preserves existing configuration and disables startup update checks"
