#!/usr/bin/env bash
# Regression tests for the backend security policy in mise-pins-test.sh.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

write_config() {
    cat > "$fixture/.mise.toml" <<'EOF'
[tools]
node = { version = "latest" }
github-cli = { version = "latest" }
"npm:pnpm" = { version = "latest" }

[settings]
locked_verify_provenance = true
EOF
}

write_valid_lock() {
    cat > "$fixture/mise.lock" <<'EOF'
[[tools.node]]
version = "24.0.0"
backend = "core:node"

[tools.node."platforms.linux-x64"]
checksum = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

[tools.node."platforms.macos-arm64"]
checksum = "sha256:2222222222222222222222222222222222222222222222222222222222222222"

[[tools.github-cli]]
version = "2.0.0"
backend = "aqua:cli/cli"

[tools.github-cli."platforms.linux-x64"]
checksum = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
provenance = "github-attestations"

[tools.github-cli."platforms.macos-arm64"]
checksum = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
provenance = "github-attestations"

[[tools."npm:pnpm"]]
version = "10.0.0"
backend = "npm:pnpm"
EOF
}

assert_passes() {
    local description="$1"
    if ! output="$(bash "$repo/tests/mise-pins-test.sh" "$fixture" 2>&1)"; then
        printf 'FAIL: %s unexpectedly failed\n%s\n' "$description" "$output" >&2
        exit 1
    fi
}

assert_fails_with() {
    local description="$1"
    local expected="$2"
    if output="$(bash "$repo/tests/mise-pins-test.sh" "$fixture" 2>&1)"; then
        printf 'FAIL: %s unexpectedly passed\n' "$description" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected"* ]]; then
        printf 'FAIL: %s did not report %q\n%s\n' "$description" "$expected" "$output" >&2
        exit 1
    fi
}

write_config
write_valid_lock
assert_passes "valid tracked and explicitly allowlisted backends"

write_config
write_valid_lock
sed -i.bak 's/locked_verify_provenance = true/locked_verify_provenance = false/' "$fixture/.mise.toml"
rm "$fixture/.mise.toml.bak"
assert_fails_with "disabled install-time provenance verification" "locked_verify_provenance must be true"

write_config
write_valid_lock
sed -i.bak '/sha256:1111111111111111111111111111111111111111111111111111111111111111/d' "$fixture/mise.lock"
rm "$fixture/mise.lock.bak"
assert_fails_with "missing checksum" "node (core:node) platform linux-x64 violates checksum-required policy"

write_config
write_valid_lock
sed -i.bak 's/sha256:1111111111111111111111111111111111111111111111111111111111111111/sha256:garbage/' "$fixture/mise.lock"
rm "$fixture/mise.lock.bak"
assert_fails_with "malformed checksum" "node (core:node) platform linux-x64 violates checksum-required policy: malformed checksum"

write_config
write_valid_lock
sed -i.bak '/provenance = "github-attestations"/d' "$fixture/mise.lock"
rm "$fixture/mise.lock.bak"
assert_fails_with "provenance regression" "github-cli (aqua:cli/cli) platform linux-x64 violates provenance-required policy"

write_config
write_valid_lock
sed -i.bak 's/backend = "aqua:cli\/cli"/backend = "github:cli\/cli"/' "$fixture/mise.lock"
rm "$fixture/mise.lock.bak"
assert_fails_with "provenance backend regression" "github-cli (github:cli/cli) violates provenance-required policy: expected backend aqua:cli/cli"

write_config
write_valid_lock
cat >> "$fixture/.mise.toml" <<'EOF'
"cargo:unreviewed" = { version = "latest" }
EOF
cat >> "$fixture/mise.lock" <<'EOF'

[[tools."cargo:unreviewed"]]
version = "1.0.0"
backend = "cargo:unreviewed"
EOF
assert_fails_with "unreviewed version-only backend" "cargo:unreviewed (cargo:unreviewed) has no backend security policy"

# The fixture holds no docs/ directory, so the documented-coverage check has
# nothing to compare against and must skip rather than fail. Give it a page that
# disagrees with the fixture lockfile and confirm it speaks up.
write_config
write_valid_lock
mkdir -p "$fixture/docs"
cat > "$fixture/docs/supply-chain.md" <<'EOF'
<!-- coverage:checksum:start -->
`core:node`
`aqua:cli/cli`
<!-- coverage:checksum:end -->
<!-- coverage:version-only:start -->
`npm:pnpm`
<!-- coverage:version-only:end -->
<!-- coverage:no-checksum:start -->
`npm:pnpm`
<!-- coverage:no-checksum:end -->
<!-- coverage:provenance:start -->
`aqua:cli/cli`
<!-- coverage:provenance:end -->
<!-- coverage:unproxied-version-only:start -->
<!-- coverage:unproxied-version-only:end -->
EOF
assert_passes "coverage lists matching the lockfile"

sed -i.bak '/core:node/d' "$fixture/docs/supply-chain.md"
rm "$fixture/docs/supply-chain.md.bak"
assert_fails_with "backend missing from the documented coverage" \
    "coverage:checksum does not list core:node"

write_config
write_valid_lock
cat > "$fixture/docs/supply-chain.md" <<'EOF'
nothing documented here
EOF
assert_fails_with "coverage block removed from the page" \
    "has no coverage:checksum block to check"

rm -rf "$fixture/docs"
assert_passes "page absent, coverage check skipped"

echo "mise backend policy tests passed"
