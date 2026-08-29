#!/usr/bin/env bash
# Tests for the [tools] section of .mise.toml and its lockfile.
#
# Tools are declared as "latest", but mise.lock is what actually decides the
# installed version: a locked version wins over a fuzzy selector. That makes the
# lockfile the security boundary, so these tests guard it.
#
#   1. every declared tool has a locked version — an unlocked one resolves to
#      whatever was published minutes ago, skipping the release-age gate
#   2. a bare `tool = "version"` key written after a [tools.<name>] table, which
#      TOML silently nests under that tool instead of registering a new one
#   3. nothing is locked that is no longer declared

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$repo" <<'PY'
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
config = tomllib.loads((repo / ".mise.toml").read_text())
lock = tomllib.loads((repo / "mise.lock").read_text())

failures = 0


def fail(message):
    global failures
    failures += 1
    print(f"✗ {message}")


# A tool is either `name = "version"` or a [tools.name] table with a `version`.
declared = {}
for name, value in config["tools"].items():
    declared[name] = value if isinstance(value, str) else value.get("version")

# 1. every declared tool is locked to a concrete version
for name in declared:
    entry = lock.get("tools", {}).get(name)
    if entry is None:
        fail(f"{name} is declared but absent from mise.lock; run `mise lock --bump --minimum-release-age 2d`")
        continue
    for e in (entry if isinstance(entry, list) else [entry]):
        version = e.get("version")
        if not version or version in ("latest", "lts"):
            fail(f"{name} is locked to {version!r} rather than an exact version")

# 2. no tool has been swallowed by a [tools.<name>] table. Options mise
# understands on a tool table are known; anything else is a stray tool key.
tool_options = {
    "version", "postinstall", "depends", "os", "install_env", "tools", "backend",
}
for name, value in config["tools"].items():
    if not isinstance(value, dict):
        continue
    for key in value:
        if key not in tool_options:
            fail(
                f"{key!r} is nested under [tools.{name}] instead of being its own "
                f"tool; move it above the first [tools.<name>] table"
            )

# 3. the lockfile carries nothing that was dropped from the config
for name in lock.get("tools", {}):
    if name not in declared:
        fail(f"{name} is locked but no longer declared in .mise.toml")

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print(f"✓ {len(declared)} tools declared, all locked, none nested")
PY
