# Supply-chain defense

English | [日本語](supply-chain.ja.md)

The defense is four layers, each covering a different range.

| Layer | Mechanism | Covers |
| --- | --- | --- |
| Version | `mise.lock` + `--minimum-release-age 2d` | the first two days after publish |
| Artifact integrity | checksums in `mise.lock` | bytes that differ from the locked artifact, **on the backends that record one** — see [coverage](#coverage-which-tools-get-what) |
| Artifact provenance | backend verification + `locked_verify_provenance` | supported artifacts whose recorded provenance no longer verifies |
| Package | the [Takumi Guard](https://npm.flatt.tech/) proxy in `~/.npmrc` | everything through npm, especially the run-time `npx ctx7@latest` / `npx skills add` that cannot be locked |
| Action source | full commit SHAs verified by `pinact` | movement or compromise of a GitHub Actions release tag |

## Version: `latest` declarations plus a lockfile

`[tools]` in `.mise.toml` declares `latest`, but `latest` is not what gets installed.
A locked version always wins over a fuzzy selector in mise, so what actually lands is whatever `mise.lock` decided.

The lockfile is advanced daily by [`bump-tools.yml`](../.github/workflows/bump-tools.yml).

```bash
mise lock --bump --minimum-release-age 2d
```

`--minimum-release-age` drops any release younger than two days from consideration.
A compromised release is picked up in the first few hours after publish, so this wait alone avoids that window entirely.
Because the flag — not review — is what makes this safe, the workflow commits straight to main rather than opening a PR.

The flag only applies to fuzzy selectors like `latest`. That is exactly why the versions in `.mise.toml` are not pinned there.

The lockfile is mandatory: `install.sh` aborts if it cannot be fetched.
Running `mise install` against bare `latest` would bypass the waiting period and pull the newest release.
It is installed to `~/.config/mise/mise.lock` while the config it locks sits in `~/.config/mise/conf.d/10-dotfiles.toml`: mise keys a global lockfile to the config directory rather than to one file name, so the single lockfile still pins every tool the fragment declares.
[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) catches any tool that slips in unlocked, and any `[tools]` entry not written as a single-line inline table.
That second check is what keeps a tool from being silently dropped: a `[tools.<name>]` sub-table ends the `[tools]` table, so every plain key after one becomes a key of that tool instead of a new tool.
It runs both in CI and, once linked, as the pre-commit hook in [`.githooks`](../.githooks).

## Artifact: backend policy in the lockfile

[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) applies an explicit policy to every locked backend.
The same policy function runs against the working tree in CI and against staged `.mise.toml` and `mise.lock` files in the pre-commit hook.
Its regression suite covers the valid policy and failures for a missing or malformed checksum, provenance or backend regression, an unreviewed version-only backend, and a coverage list on this page that has drifted from the lockfile.

The policy requires `linux-x64` and `macos-arm64` checksums for every currently used `core:`, `aqua:`, and `github:` backend.
It leaves additional platform variants intact and checks the two platforms this repository installs on: GitHub Actions Linux x64 and local macOS arm64.
mise documents full asset tracking for aqua and github, and checksum support for some core tools; every core tool currently selected here supplies both required checksums.

The following exceptions are exact tool/backend pairs with reasons, rather than backend-wide wildcards:

<!-- coverage:no-checksum:start -->
- `cargo:similarity-ts`: cargo lock entries are version-only.
- `npm:@antfu/ni`, `npm:@openai/codex`, `npm:@playwright/cli`, `npm:ctx7`, `npm:difit`, `npm:pnpm`, and `npm:wrangler`: npm lock entries are version-only.
- `vfox:oci`: this vfox backend plugin currently records only the version.
<!-- coverage:no-checksum:end -->

A newly added version-only or partial backend fails until a maintainer assigns it a checksum policy or adds a reason-specific exception.

### Coverage: which tools get what

Checksum protection is a property of the backend, not of mise. Saying "every tool this repository installs is checksum-verified" would be wrong for nearly half of them, so here is the split as `mise.lock` actually records it.

These record a checksum for the two platforms this repository installs on, `linux-x64` and `macos-arm64`.
That is the pair the policy requires and the pair the check below verifies; the other platform variants in the lockfile are left intact and are not asserted here:

<!-- coverage:checksum:start -->
`aqua:anomalyco/opencode`, `aqua:astral-sh/uv`, `aqua:cli/cli`, `aqua:cloudflare/cloudflared`, `aqua:jqlang/jq`, `aqua:modem-dev/hunk`, `aqua:suzuki-shunsuke/pinact`, `aqua:x-motemen/ghq`, `core:bun`, `core:node`, `github:rtk-ai/rtk`
<!-- coverage:checksum:end -->

These record nothing but a version and a backend — the list above's complement, and the same set as the allowlisted exceptions:

<!-- coverage:version-only:start -->
`cargo:similarity-ts`, `npm:@antfu/ni`, `npm:@openai/codex`, `npm:@playwright/cli`, `npm:ctx7`, `npm:difit`, `npm:pnpm`, `npm:wrangler`, `vfox:oci`
<!-- coverage:version-only:end -->

And these additionally carry verified provenance in the lockfile:

<!-- coverage:provenance:start -->
`aqua:astral-sh/uv`, `aqua:cli/cli`, `aqua:jqlang/jq`, `aqua:suzuki-shunsuke/pinact`
<!-- coverage:provenance:end -->

[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) checks these four lists against `mise.lock` on every CI run, so a backend that gains or loses a checksum fails here rather than quietly making this page a lie.

A checksum establishes integrity relative to the value in `mise.lock`; it does not establish who built or published those bytes.
For authenticity, mise records verified provenance when a backend and release provide it.
The policy currently requires `github-attestations` on every recorded platform asset for `github-cli`, `jq`, `pinact`, and `uv`, because those tools already provide that provenance.
Each expectation is also bound to its current exact aqua backend, so switching the upstream identity requires policy review.
Removing or changing one of those entries is treated as a regression.

`.mise.toml` sets `locked_verify_provenance = true`, so installation re-runs cryptographic provenance verification instead of trusting the lockfile's prior verification result.
This guarantee applies only to artifacts for which mise and the upstream release provide provenance; it does not add provenance to the checksum-only tools or the explicit version-only exceptions.

## Action source: immutable commit SHAs

Every `uses:` reference under [`.github/workflows`](../.github/workflows) is pinned to a full 40-character commit SHA.
The release tag remains in an end-of-line comment, so a review still shows the recognizable version without trusting that mutable tag at run time.

`pinact` performs both enforcement paths.
CI runs `pinact run -check -verify-comment`, which rejects an unpinned reference and a SHA whose version comment no longer matches.
The global pre-commit dispatcher runs pinact first for staged workflow files, then forwards to the repository's own pre-commit hook as before.
It pins a temporary copy of the index and writes the resulting blobs back to the index, so unrelated unstaged edits and partial staging do not leak into the commit.
When the same fix applies cleanly to the working tree, the hook mirrors it there; a conflicting unstaged edit is left untouched.

pinact itself is a mise-managed tool and is checksum-pinned in `mise.lock`.
Its lock entry advances through the same daily `--minimum-release-age 2d` gate as the rest of the toolchain.

## Package: the npm registry proxy

The proxy only takes effect once `~/.npmrc` is written, so `install.sh` runs `mise run --skip-tools setup:npm-registry` before `mise install`.
Drop `--skip-tools` and `mise run` installs the whole toolchain first, inverting the order.
The packages still install fine, so the failure never surfaces ([`tests/install-order-test.sh`](../tests/install-order-test.sh) catches it).

The registry goes into `~/.npmrc` rather than an environment variable, so a project on a private registry can still override it with its own `.npmrc`.
If a custom registry is already configured, the setup leaves it alone.

### What the proxy does not reach

`~/.npmrc` is read by npm, pnpm and bun (1.0.28 and later), which covers every `npm:` tool and the run-time `npx` calls that cannot be locked.
It has no effect on the backends that never talk to the npm registry: `cargo:` resolves crates.io through cargo's own config, and `github:`, `aqua:` and `core:` download release assets straight from the upstream host.

For most of those the checksum layer stands in for it — the bytes are pinned in `mise.lock`.
Two tools fall through both, having neither a proxy in front of them nor a checksum behind them, and are held by the locked version alone:

<!-- coverage:unproxied-version-only:start -->
`cargo:similarity-ts`, `vfox:oci`
<!-- coverage:unproxied-version-only:end -->

## Not covered: skills

The Markdown that `npx skills add` fetches goes straight into every agent's context, which makes it a prompt-injection channel.
The skills CLI has no way to pin a revision. Review the diff before running `npx skills update`.

## One-time setup for bump-tools.yml

main is protected by the `main-guardrails` ruleset, whose `pull_request` rule forbids direct pushes.
The default `GITHUB_TOKEN` cannot be registered as a bypass actor (GitHub Actions can only be one on organization-owned repositories, and this one belongs to a user).
A GitHub App can, so the workflow uses an App token.

1. [Create a GitHub App](https://github.com/settings/apps/new). Repository permissions: **Contents: Read and write** only. No webhook.
2. Note the Client ID, then generate and download a private key.
3. Install the App on this repository.
4. Register the repository secrets:
   - `BUMP_APP_CLIENT_ID` — the Client ID from step 2
   - `BUMP_APP_PRIVATE_KEY` — the contents of the downloaded `.pem`
5. Add the App as an Integration in the Bypass list of Settings > Rules > `main-guardrails`.

Trigger the workflow manually from `workflow_dispatch` and confirm that the push goes through.
