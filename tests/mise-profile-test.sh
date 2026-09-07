#!/usr/bin/env bash
# Tests that a profile fragment removes exactly the tools it names, asking mise
# rather than reasoning about the file.
#
# tests/mise-pins-test.sh already checks the fragments as text: no [tools] of
# their own, and every disable_tools name matched against a tool .mise.toml
# declares. What text cannot check is whether mise agrees — that `[settings]
# disable_tools` in a merged fragment is still how a tool is refused, and that
# the name mise matches on is the key in [tools] rather than the backend it
# resolves through (`oci` and `vfox:oci` are both plausible, and only one
# works). A wrong answer to either is silent: the profile parses, the machine
# installs, and the tools it was supposed to leave out are simply there.
#
# On a machine the fragment sits in ~/.config/mise/conf.d/ beside the common
# config. Here MISE_ENV loads it from the checkout instead, which is a different
# route to the same merge and the only one available to a repository.
#
# Needs mise on PATH, so it runs in the mise job rather than alongside the shell
# tests. Run it by hand with:
#   bash tests/mise-profile-test.sh

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v mise > /dev/null 2>&1; then
    echo "✗ needs mise on PATH"
    exit 1
fi

# A copy rather than the checkout itself, so this neither depends on nor changes
# whether the developer has trusted their own working tree. mise resolves every
# tool from the lockfile, which makes the two `mise ls` calls below offline.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
cp "$repo/.mise.toml" "$repo/mise.lock" "$work_dir/"
cp "$repo"/.mise.*.toml "$work_dir/"

mise_ls() {
    (
        cd "$work_dir"
        MISE_TRUSTED_CONFIG_PATHS="$work_dir" MISE_ENV="$1" mise ls 2> /dev/null | awk '{ print $1 }' | sort
    )
}

# MISE_ENV= (empty) is the plain common config: what a machine on the default
# profile installs.
if ! baseline="$(mise_ls '')" || [ -z "$baseline" ]; then
    echo "✗ \`mise ls\` listed no tools for the common config; the rest of this"
    echo "  test would compare two empty lists and pass on anything"
    exit 1
fi

failures=0
for fragment in "$repo"/.mise.*.toml; do
    [ -e "$fragment" ] || continue
    profile="${fragment##*/.mise.}"
    profile="${profile%.toml}"

    # The names the fragment says it refuses. Read with the same TOML parser the
    # other tests use so a quoting or continuation difference cannot make this
    # test read a different list than mise does.
    if python3 -c 'import tomllib' 2> /dev/null; then
        py=(python3)
    elif command -v uv > /dev/null 2>&1; then
        py=(uv run --quiet --python 3.12 python)
    else
        echo "✗ needs Python 3.11+ (for tomllib) or uv on PATH"
        exit 1
    fi
    expected="$("${py[@]}" -c '
import sys, tomllib
config = tomllib.load(open(sys.argv[1], "rb"))
for name in sorted(config.get("settings", {}).get("disable_tools", [])):
    print(name)
' "$fragment")"

    actual="$(comm -23 <(printf '%s\n' "$baseline") <(mise_ls "$profile"))"

    if [ "$actual" != "$expected" ]; then
        echo "✗ the $profile profile does not drop what it says it drops"
        echo "  disable_tools names: ${expected//$'\n'/ }"
        echo "  tools mise actually dropped: ${actual//$'\n'/ }"
        failures=$((failures + 1))
        continue
    fi

    # Dropping is all it may do. A fragment that added a tool would add one no
    # lockfile in this repository pins, which is the failure the text checks in
    # tests/mise-pins-test.sh exist to prevent — this is the same rule seen from
    # mise's side, where an [env] or a [tasks] block could reach it too.
    added="$(comm -13 <(printf '%s\n' "$baseline") <(mise_ls "$profile"))"
    if [ -n "$added" ]; then
        echo "✗ the $profile profile adds tools: ${added//$'\n'/ }"
        echo "  a profile may only subtract; an added tool would not be in mise.lock"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures profile failure(s)"
    exit 1
fi

echo "mise profile tests passed"
