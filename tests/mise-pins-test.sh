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
#   5. tracked backends have checksums for macOS arm64 and Linux x64
#   6. known provenance-capable artifacts cannot lose recorded provenance
#   7. every version-only or partial backend is explicitly allowlisted
#
# Run it from a git hook via .githooks/pre-commit, or by hand:
#   bash tests/mise-pins-test.sh

set -euo pipefail

# Defaults to the repo this script lives in; .githooks/pre-commit passes a
# temp dir holding the *staged* .mise.toml and mise.lock instead.
check_setup=true
if [ "$#" -gt 0 ]; then
    check_setup=false
fi
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
"${py[@]}" - "$repo" "$check_setup" <<'PY'
import re
import json
import subprocess
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
check_setup = sys.argv[2] == "true"
config = tomllib.loads((repo / ".mise.toml").read_text())
lock = tomllib.loads((repo / "mise.lock").read_text())

failures = 0

# mise documents full asset tracking for aqua/github and checksum support for
# some core tools. Every currently used tool in these backend families resolves
# assets for both platforms below, so a missing entry is a policy failure.
CHECKSUM_BACKEND_PREFIXES = ("aqua:", "core:", "github:")
REQUIRED_PLATFORMS = ("linux-x64", "macos-arm64")

# These backends cannot currently give this repository a checksum for the
# installed artifact. Keep the exception tied to both tool and backend: a new
# version-only tool or a backend change must be reviewed instead of passing by
# prefix. Reasons are kept beside the exception for maintainers and docs.
VERSION_ONLY_ALLOWLIST = {
    "cargo:similarity-ts": ("cargo:similarity-ts", "cargo lock entries record versions only"),
    "npm:@antfu/ni": ("npm:@antfu/ni", "npm lock entries record versions only"),
    "npm:@openai/codex": ("npm:@openai/codex", "npm lock entries record versions only"),
    "npm:@playwright/cli": ("npm:@playwright/cli", "npm lock entries record versions only"),
    "npm:ctx7": ("npm:ctx7", "npm lock entries record versions only"),
    "npm:difit": ("npm:difit", "npm lock entries record versions only"),
    "npm:pnpm": ("npm:pnpm", "npm lock entries record versions only"),
    "oci": ("vfox:oci", "this vfox backend plugin records versions only"),
    "wrangler": ("npm:wrangler", "npm lock entries record versions only"),
}

# These tools currently publish GitHub attestations and mise records successful
# verification for every resolved asset. Requiring the recorded value prevents
# a release/backend change from silently reducing the established guarantee.
PROVENANCE_REQUIRED = {
    "github-cli": ("aqua:cli/cli", "github-attestations"),
    "jq": ("aqua:jqlang/jq", "github-attestations"),
    "uv": ("aqua:astral-sh/uv", "github-attestations"),
}


def fail(message):
    global failures
    failures += 1
    print(f"✗ {message}")


# Every entry is an inline table (the style check above enforces that), but
# accept a bare string too so this reports a real problem rather than crashing.
declared = {}
for name, value in config["tools"].items():
    declared[name] = value if isinstance(value, str) else value.get("version")

if config.get("settings", {}).get("locked_verify_provenance") is not True:
    fail(".mise.toml [settings].locked_verify_provenance must be true")

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

# 5-7. backend security policy
for name, raw_entries in lock.get("tools", {}).items():
    entries = raw_entries if isinstance(raw_entries, list) else [raw_entries]
    for entry in entries:
        backend = entry.get("backend", "")
        tracked = backend.startswith(CHECKSUM_BACKEND_PREFIXES)
        if tracked:
            for platform in REQUIRED_PLATFORMS:
                metadata = entry.get(f"platforms.{platform}")
                if not isinstance(metadata, dict) or not metadata.get("checksum"):
                    fail(
                        f"{name} ({backend}) platform {platform} violates "
                        "checksum-required policy: checksum is missing"
                    )
                elif not re.fullmatch(
                    r"(?:sha256|blake3):[0-9a-f]{64}", metadata["checksum"]
                ):
                    fail(
                        f"{name} ({backend}) platform {platform} violates "
                        f"checksum-required policy: malformed checksum {metadata['checksum']!r}"
                    )
        else:
            allowed = VERSION_ONLY_ALLOWLIST.get(name)
            if allowed is None or allowed[0] != backend:
                fail(
                    f"{name} ({backend}) has no backend security policy; "
                    "add checksum enforcement or a reviewed reason-specific allowlist entry"
                )

        provenance_policy = PROVENANCE_REQUIRED.get(name)
        if provenance_policy:
            expected_backend, expected_provenance = provenance_policy
            if backend != expected_backend:
                fail(
                    f"{name} ({backend}) violates provenance-required policy: "
                    f"expected backend {expected_backend}"
                )
            platform_entries = {
                key.removeprefix("platforms."): value
                for key, value in entry.items()
                if key.startswith("platforms.") and isinstance(value, dict)
            }
            for platform, metadata in platform_entries.items():
                actual = metadata.get("provenance")
                if actual != expected_provenance:
                    fail(
                        f"{name} ({backend}) platform {platform} violates "
                        f"provenance-required policy: expected {expected_provenance}, "
                        f"got {actual!r}"
                    )

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print(f"✓ {len(declared)} tools declared as inline tables, all locked")

if not check_setup:
    sys.exit(0)

# 8. setup:claude must preserve both array order and scalar priority. Extract
# the real jq program from the task so this exercises the expression mise runs.
claude_setup = config["tasks"]["setup:claude"]["run"]
jq_match = re.search(
    r"jq -s --arg prefer remote '(.+?)' \"\$CLAUDE_SETTINGS\" \"\$REMOTE_SETTINGS\"",
    claude_setup,
    re.DOTALL,
)
if jq_match is None:
    fail("setup:claude must pass prefer=remote to its embedded jq merge")
else:
    local_settings = {
        "permissions": {"allow": ["Bash(local:*)", "Read"], "defaultMode": "ask"},
        "hooks": {"PreToolUse": [{"matcher": "local"}]},
        "nullable": None,
    }
    remote_settings = {
        "permissions": {"allow": ["Read", "Bash(remote:*)"], "defaultMode": "auto"},
        "hooks": {"PreToolUse": [{"matcher": "remote"}]},
        "statusLine": {"type": "command"},
        "nullable": 1,
    }
    jq_program = jq_match.group(1)
    for preference, expected_mode in (("remote", "auto"), ("local", "ask")):
        result = subprocess.run(
            ["jq", "-s", "--arg", "prefer", preference, jq_program],
            input=json.dumps(local_settings) + "\n" + json.dumps(remote_settings) + "\n",
            text=True,
            capture_output=True,
            check=True,
        )
        merged = json.loads(result.stdout)
        if merged["permissions"]["allow"] != [
            "Bash(local:*)",
            "Read",
            "Bash(remote:*)",
        ]:
            fail(f"settings merge with prefer={preference} must union arrays without reordering")
        if merged["hooks"]["PreToolUse"] != [
            {"matcher": "local"},
            {"matcher": "remote"},
        ]:
            fail(f"settings merge with prefer={preference} must preserve hook order")
        if merged["permissions"]["defaultMode"] != expected_mode:
            fail(f"settings merge with prefer={preference} selected the wrong scalar")
        if merged["statusLine"] != {"type": "command"}:
            fail(f"settings merge with prefer={preference} lost a remote-only key")
        expected_nullable = 1 if preference == "remote" else None
        if merged["nullable"] != expected_nullable:
            fail(f"settings merge with prefer={preference} mishandled an explicit null")

# 9. Tasks that establish setup's security and correctness preconditions must
# fail closed. Optional installers remain deliberately outside this policy.
fatal_task_modes = {
    "setup:oci-plugin": "set -eo pipefail",
    "setup:npm-registry": "set -e",
}
for task_name, mode in fatal_task_modes.items():
    if not config["tasks"][task_name]["run"].lstrip().startswith(mode):
        fail(f"{task_name} must start with {mode!r}")

fatal_messages = (
    ("setup:npm-registry", "~/.npmrc already uses a custom registry"),
    ("setup:git-hooks", "Failed to download the git hook installer"),
    ("setup:update-notice", "Failed to install dotfiles update notification"),
    ("setup:claude", "Failed to download Claude Code settings"),
    ("setup:claude", "Failed to download Claude Code status line"),
)
for task_name, message in fatal_messages:
    script = config["tasks"][task_name]["run"]
    pattern = rf'echo "⚠ {re.escape(message)}[^\n]*\n(?:\s*rm[^\n]*\n)?\s*exit 1'
    if re.search(pattern, script) is None:
        fail(f"{task_name} must exit non-zero after reporting {message!r}")

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print("✓ setup settings merge and fail-close policies verified")
PY
