#!/usr/bin/env bash
# Tests the ordering guarantee install.sh makes about the npm registry.
#
# setup:npm-registry writes ~/.npmrc so that every `npm:` tool and every
# `npx`-based postinstall resolves through the malware-blocking proxy. That is
# only worth anything if it runs before the tools are installed, and the failure
# mode is invisible: the packages install fine, just from the wrong registry.
#
#   1. the task is invoked with --skip-tools — `mise run` installs the whole
#      tool set before running any task, so without the flag the invocation
#      itself is what installs the tools it was meant to precede
#   2. the invocation still comes before `mise install`

set -euo pipefail

install_sh="$(cd "$(dirname "$0")/.." && pwd)/install.sh"

registry_line="$(grep -n 'mise run .*setup:npm-registry' "$install_sh" | head -1)"
if [[ -z "$registry_line" ]]; then
  echo "✗ install.sh never runs setup:npm-registry" >&2
  exit 1
fi

if [[ "$registry_line" != *"--skip-tools"* ]]; then
  echo "✗ setup:npm-registry is run without --skip-tools, so mise installs every" >&2
  echo "  tool before the task can point npm at the proxy" >&2
  exit 1
fi

install_line="$(grep -n '^\s*mise install' "$install_sh" | head -1)"
if [[ -z "$install_line" ]]; then
  echo "✗ install.sh never runs mise install" >&2
  exit 1
fi

if (( ${registry_line%%:*} >= ${install_line%%:*} )); then
  echo "✗ setup:npm-registry runs at or after mise install" >&2
  exit 1
fi

echo "install order tests passed"
