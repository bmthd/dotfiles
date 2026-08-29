#!/usr/bin/env bash
# Tests for the [tools] section of .mise.toml and its lockfile.
#
# Tools are declared as "latest", but mise.lock is what actually decides the
# installed version: a locked version wins over a fuzzy selector. That makes the
# lockfile the security boundary, so these tests guard it.
#
#   1. every [tools] entry is a single-line inline table — see the style note
#      below, which is also what keeps a tool from being silently swallowed by
#      a [tools.<name>] table
#   2. every declared tool has a locked version — an unlocked one resolves to
#      whatever was published minutes ago, skipping the release-age gate
#   3. no unknown option key on a tool entry
#   4. nothing is locked that is no longer declared
#
# Run it from a git hook via .githooks/pre-commit, or by hand:
#   bash tests/mise-pins-test.sh

set -euo pipefail

# Defaults to the repo this script lives in; .githooks/pre-commit passes a
# temp dir holding the *staged* .mise.toml and mise.lock instead.
repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# tomllib landed in Python 3.11 and macOS still ships 3.9, so fall back to uv —
# one of the tools this repo declares — rather than failing on a stock Mac.
if python3 -c 'import tomllib' 2>/dev/null; then
    py=(python3)
elif command -v uv >/dev/null 2>&1; then
    py=(uv run --quiet --python 3.12 python)
else
    echo "✗ needs Python 3.11+ (for tomllib) or uv on PATH"
    exit 1
fi

# --- 1. style ---------------------------------------------------------------
# Checked on the raw text, before any TOML parse, because the failure this
# guards against produces a file that a TOML 1.0 parser cannot read at all.
#
# Every entry in [tools] must be `name = { ... }` on one line. Two ways that
# breaks, both silent:
#
#   * a [tools.<name>] table ends the [tools] table, so any bare key after one
#     becomes a key of *that tool* instead of a new tool. Ten tools were never
#     installed that way.
#   * `mise fmt` splits an inline table containing an array across lines once
#     the line passes ~80 characters. The result is a multi-line inline table:
#     TOML 1.1 syntax, which mise reads but no TOML 1.0 parser will, and which
#     `mise fmt` then starts reordering. Never run `mise fmt` on this file.
style_failures=0
in_tools=0
while IFS= read -r line; do
    case "$line" in
        "[tools]") in_tools=1; continue ;;
        "[tools."*)
            echo "✗ ${line}: sub-table form; write it as a one-line inline table inside [tools] instead"
            style_failures=$((style_failures + 1))
            continue
            ;;
        "["*) in_tools=0; continue ;;
    esac
    [ "$in_tools" = 1 ] || continue
    case "$line" in
        ""|"#"*) continue ;;
        *"= { "*" }") ;;
        *"= {"*)
            echo "✗ ${line}: inline table split across lines (\`mise fmt\` does this); join it back onto one line"
            style_failures=$((style_failures + 1))
            ;;
        *)
            echo "✗ ${line}: write every tool as an inline table, e.g. \`name = { version = \"latest\" }\`"
            style_failures=$((style_failures + 1))
            ;;
    esac
done < "$repo/.mise.toml"

if [ "$style_failures" -gt 0 ]; then
    echo
    echo "$style_failures style failure(s) in [tools]"
    exit 1
fi

# --- 2-4. lockfile ----------------------------------------------------------
"${py[@]}" - "$repo" <<'PY'
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


# Every entry is an inline table (the style check above enforces that), but
# accept a bare string too so this reports a real problem rather than crashing.
declared = {}
for name, value in config["tools"].items():
    declared[name] = value if isinstance(value, str) else value.get("version")

# 2. every declared tool is locked to a concrete version
for name in declared:
    entry = lock.get("tools", {}).get(name)
    if entry is None:
        fail(f"{name} is declared but absent from mise.lock; run `mise lock --bump --minimum-release-age 2d`")
        continue
    for e in (entry if isinstance(entry, list) else [entry]):
        version = e.get("version")
        if not version or version in ("latest", "lts"):
            fail(f"{name} is locked to {version!r} rather than an exact version")

# 3. nothing but a known option on a tool entry — a typo here is accepted by
# TOML and ignored by mise, so postinstall/depends would just never run.
tool_options = {
    "version", "postinstall", "depends", "os", "install_env", "tools", "backend",
}
for name, value in config["tools"].items():
    if not isinstance(value, dict):
        continue
    for key in value:
        if key not in tool_options:
            fail(f"{key!r} is not an option mise understands on tool {name!r}")

# 4. the lockfile carries nothing that was dropped from the config
for name in lock.get("tools", {}):
    if name not in declared:
        fail(f"{name} is locked but no longer declared in .mise.toml")

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print(f"✓ {len(declared)} tools declared as inline tables, all locked")
PY
