# Supply-chain defense

English | [日本語](supply-chain.ja.md)

The defense is four layers, each covering a different range.

| Layer | Mechanism | Covers |
| --- | --- | --- |
| Version | `mise.lock` + `--minimum-release-age 2d` | the first two days after publish |
| Artifact integrity | checksums in `mise.lock` | bytes that differ from the locked artifact |
| Artifact provenance | backend verification + `locked_verify_provenance` | supported artifacts whose recorded provenance no longer verifies |
| Package | the [Takumi Guard](https://npm.flatt.tech/) proxy in `~/.npmrc` | everything through npm, especially the run-time `npx ctx7@latest` / `npx skills add` that cannot be locked |

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
[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) catches any tool that slips in unlocked, and any `[tools]` entry not written as a single-line inline table.
That second check is what keeps a tool from being silently dropped: a `[tools.<name>]` sub-table ends the `[tools]` table, so every plain key after one becomes a key of that tool instead of a new tool.
It runs both in CI and, once linked, as the pre-commit hook in [`.githooks`](../.githooks).

## Artifact: backend policy in the lockfile

[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) applies an explicit policy to every locked backend.
The same policy function runs against the working tree in CI and against staged `.mise.toml` and `mise.lock` files in the pre-commit hook.
Its regression suite covers the valid policy and failures for a missing or malformed checksum, provenance or backend regression, and an unreviewed version-only backend.

The policy requires `linux-x64` and `macos-arm64` checksums for every currently used `core:`, `aqua:`, and `github:` backend.
It leaves additional platform variants intact and checks the two platforms this repository installs on: GitHub Actions Linux x64 and local macOS arm64.
mise documents full asset tracking for aqua and github, and checksum support for some core tools; every core tool currently selected here supplies both required checksums.

The following exceptions are exact tool/backend pairs with reasons, rather than backend-wide wildcards:

- `cargo:similarity-ts`: cargo lock entries are version-only.
- `npm:@antfu/ni`, `npm:@openai/codex`, `npm:@playwright/cli`, `npm:ctx7`, `npm:difit`, `npm:pnpm`, and `npm:wrangler`: npm lock entries are version-only.
- `vfox:oci`: this vfox backend plugin currently records only the version.

A newly added version-only or partial backend fails until a maintainer assigns it a checksum policy or adds a reason-specific exception.

A checksum establishes integrity relative to the value in `mise.lock`; it does not establish who built or published those bytes.
For authenticity, mise records verified provenance when a backend and release provide it.
The policy currently requires `github-attestations` on every recorded platform asset for `github-cli`, `jq`, and `uv`, because those tools already provide that provenance.
Each expectation is also bound to its current exact aqua backend, so switching the upstream identity requires policy review.
Removing or changing one of those entries is treated as a regression.

`.mise.toml` sets `locked_verify_provenance = true`, so installation re-runs cryptographic provenance verification instead of trusting the lockfile's prior verification result.
This guarantee applies only to artifacts for which mise and the upstream release provide provenance; it does not add provenance to the checksum-only tools or the explicit version-only exceptions.

## Package: the npm registry proxy

The proxy only takes effect once `~/.npmrc` is written, so `install.sh` runs `mise run --skip-tools setup:npm-registry` before `mise install`.
Drop `--skip-tools` and `mise run` installs the whole toolchain first, inverting the order.
The packages still install fine, so the failure never surfaces ([`tests/install-order-test.sh`](../tests/install-order-test.sh) catches it).

The registry goes into `~/.npmrc` rather than an environment variable, so a project on a private registry can still override it with its own `.npmrc`.
If a custom registry is already configured, the setup leaves it alone.

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
