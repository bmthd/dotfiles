# Supply-chain defense

English | [日本語](supply-chain.ja.md)

The defense is four layers, each covering a different range.

| Layer | Mechanism | Covers |
| --- | --- | --- |
| Version | `mise.lock` + `--minimum-release-age 2d` | the first two days after publish |
| Artifact | checksums in `mise.lock` | substitution or re-publish of a verified version |
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
[`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) catches any tool that slips in unlocked, and any `[tools]` entry not written as a single-line inline table.
That second check is what keeps a tool from being silently dropped: a `[tools.<name>]` sub-table ends the `[tools]` table, so every plain key after one becomes a key of that tool instead of a new tool.
It runs both in CI and, once linked, as the pre-commit hook in [`.githooks`](../.githooks).

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
