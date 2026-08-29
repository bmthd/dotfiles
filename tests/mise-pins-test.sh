#!/usr/bin/env bash
# Tests for the [tools] section of .mise.toml and its lockfile.
#
# Guards three things that have gone wrong or would go unnoticed:
#   1. a tool drifting back to "latest", which would defeat minimumReleaseAge
#   2. a bare `tool = "version"` key written after a [tools.<name>] table, which
#      TOML silently nests under that tool instead of registering a new one
#   3. mise.lock falling out of sync with the pins, which leaves the bumped
#      version installed without checksum verification

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
pins = {}
for name, value in config["tools"].items():
    if isinstance(value, str):
        pins[name] = value
    else:
        pins[name] = value.get("version")

# 1. every tool is pinned
for name, version in pins.items():
    if version in (None, "latest", "lts"):
        fail(f"{name} is not pinned to an exact version (got {version!r})")

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

# 3. the lockfile agrees with the pins
for name, version in pins.items():
    entry = lock.get("tools", {}).get(name)
    if entry is None:
        fail(f"{name} is pinned to {version} but missing from mise.lock")
        continue
    locked = {e["version"] for e in (entry if isinstance(entry, list) else [entry])}
    if version not in locked:
        fail(
            f"{name} is pinned to {version} but mise.lock has {sorted(locked)}; "
            f"run `mise lock` and commit the result"
        )

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print(f"✓ {len(pins)} tools pinned, none nested, lockfile in sync")
PY
