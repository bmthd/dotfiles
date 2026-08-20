#!/usr/bin/env bash
# Tests for .claude/statusline.sh, focused on the context gauge.

set -euo pipefail

statusline="$(dirname "$0")/../.claude/statusline.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

failures=0

# Run the status line with the given JSON payload and strip ANSI escapes so the
# assertions can match on plain text.
render() {
  printf '%s' "$1" | bash "$statusline" | sed $'s/\033\\[[0-9;]*m//g'
}

expect_contains() {
  local label="$1" payload="$2" needle="$3" output
  output="$(render "$payload")"
  if [[ "$output" == *"$needle"* ]]; then
    echo "✓ $label"
  else
    echo "✗ $label: expected '$needle' in '$output'" >&2
    failures=$((failures + 1))
  fi
}

expect_missing() {
  local label="$1" payload="$2" needle="$3" output
  output="$(render "$payload")"
  if [[ "$output" != *"$needle"* ]]; then
    echo "✓ $label"
  else
    echo "✗ $label: did not expect '$needle' in '$output'" >&2
    failures=$((failures + 1))
  fi
}

base='"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}'

# The pre-calculated percentage is what /context shows, so it wins.
expect_contains "uses context_window.used_percentage" \
  "{$base,\"context_window\":{\"used_percentage\":42,\"context_window_size\":200000}}" \
  "████░░░░░░ 42%"

# Fractional percentages round down rather than breaking the integer maths.
expect_contains "floors a fractional percentage" \
  "{$base,\"context_window\":{\"used_percentage\":23.9,\"context_window_size\":200000}}" \
  "██░░░░░░░░ 23%"

# 300k tokens of a 1M window is 30%, not a pinned-then-collapsing gauge.
# exceeds_200k_tokens is true here precisely because it is a fixed 200k
# threshold, and it must not be mistaken for the window size.
expect_contains "scales to the extended context window" \
  "{$base,\"exceeds_200k_tokens\":true,\"context_window\":{\"context_window_size\":1000000,\"used_percentage\":null,\"current_usage\":{\"input_tokens\":100000,\"cache_creation_input_tokens\":50000,\"cache_read_input_tokens\":150000,\"output_tokens\":9000}}}" \
  "███░░░░░░░ 30%"

# current_usage is null right after /compact; the gauge just disappears.
expect_missing "hides the gauge when usage is unavailable" \
  "{$base,\"context_window\":{\"used_percentage\":null,\"current_usage\":null}}" \
  "%"

# --- transcript fallback (Claude Code versions without .context_window) -----
transcript="$test_dir/transcript.jsonl"
usage() { # type isSidechain cache_read
  printf '{"type":"%s","isSidechain":%s,"message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$1" "$2" "$3"
}
{
  usage assistant false 120000
  usage assistant true 4000   # a subagent turn, appended after the main one
} > "$transcript"

# A subagent's context is not this conversation's context.
expect_contains "ignores sidechain usage records" \
  "{$base,\"transcript_path\":\"$transcript\"}" \
  "██████░░░░ 60%"

expect_missing "hides the gauge without any usage source" \
  "{$base,\"transcript_path\":\"$test_dir/missing.jsonl\"}" \
  "%"

if [ "$failures" -ne 0 ]; then
  echo "$failures statusline test(s) failed" >&2
  exit 1
fi
echo "statusline tests passed"
