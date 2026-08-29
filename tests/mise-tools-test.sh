#!/usr/bin/env bash

set -euo pipefail

config="$(cd "$(dirname "$0")/.." && pwd)/.mise.toml"
tool_list="$(mktemp)"
trap 'rm -f "$tool_list"' EXIT

mise ls --json > "$tool_list"

python3 - "$config" "$tool_list" <<'PY'
import json
import os
import sys

config = os.path.realpath(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as file:
    tools = json.load(file)

flat_tools = {
    "ghq",
    "jq",
    "uv",
    "cargo:similarity-ts",
    "npm:@antfu/ni",
    "npm:@openai/codex",
    "opencode",
    "oci",
    "cloudflared",
    "wrangler",
}
wrong_source = []
for tool in sorted(flat_tools):
    versions = tools.get(tool, [])
    if not any(
        os.path.realpath(version.get("source", {}).get("path", "")) == config
        for version in versions
    ):
        wrong_source.append(tool)

assert not wrong_source, (
    "tools not declared by this .mise.toml: " + ", ".join(wrong_source)
)
PY

echo "mise tool declarations passed"
