#!/usr/bin/env bash
# `setup:npm-registry`: route npm installs through the Takumi Guard proxy.
# Placed by the setup:scripts task in .mise.toml; see the comment there.
set -e
# Point npm at Takumi Guard (https://npm.flatt.tech/), a proxy that refuses to
# serve packages it knows to be malicious. Anonymous mode ("Tier A") needs no
# account: blocking only, no audit log.
#
# This covers the part of the supply chain that pinning cannot. The mise `npm:`
# tools resolve to a pinned version and Renovate holds new ones back, but the
# postinstall hooks in .mise.toml shell out to `npx ctx7@latest` and `npx skills
# add`, which always fetch the newest package at run time. The proxy is the only
# control that sits in front of those.
#
# It is written to ~/.npmrc, not exported as NPM_CONFIG_REGISTRY, so that a
# project-level .npmrc (a work repo on a private registry) still wins — npm
# reads env vars at a higher precedence than any .npmrc file.
NPMRC="$HOME/.npmrc"
REGISTRY="https://npm.flatt.tech/"
touch "$NPMRC"
current="$(sed -n 's/^registry=//p' "$NPMRC" | tail -1)"
case "$current" in
    "$REGISTRY")
        echo "✓ npm registry already points at Takumi Guard"
        ;;
    ""|https://registry.npmjs.org*)
        # No registry line, or still the npm default: safe to (re)write.
        tmp="$(mktemp)"
        grep -v '^registry=' "$NPMRC" > "$tmp" || true
        printf 'registry=%s\n' "$REGISTRY" >> "$tmp"
        cat "$tmp" > "$NPMRC"
        rm -f "$tmp"
        echo "✓ npm registry set to Takumi Guard ($REGISTRY)"
        ;;
    *)
        # Somebody pointed ~/.npmrc at a registry of their own; leave it alone.
        echo "⚠ ~/.npmrc already uses a custom registry ($current); leaving it unchanged"
        exit 1
        ;;
esac
