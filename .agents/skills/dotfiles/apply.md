# /dotfiles apply

`.dotfiles/apply.sh` is the source of truth for the deterministic update work.
This English file is authoritative; keep the Japanese file as its structural and semantic mirror.
This procedure supplies the judgment and communication the script cannot make.

## 1. Secure the checkout

The script fetches, but it cannot obtain a checkout it is part of, so that step is yours:

```bash
ghq get -u github.com/bmthd/dotfiles || git clone https://github.com/bmthd/dotfiles "$REPO"
```

`ghq` can be on PATH as a shim and still fail (`No version is set for shim: ghq`), so the
`git clone` fallback is not decoration.
Do not report an update when this step failed.

## 2. Create a plan

From that checkout, run:

```bash
.dotfiles/apply.sh plan --json
```

`plan` is read-only for this machine: it fetches the remote ref, which writes only
remote-tracking refs inside the checkout, and touches no managed file.
Treat its single JSON document as the current inventory.

The top-level fields are:

- `mode`: `inventory` permits an apply decision; `no-base` does not.
- `fetch`: `ok` when the remote ref was refreshed; `failed` when it was not; `skipped`
  when `--remote-ref` names no configured remote.
- `fetchError`: the fetch failure, when there was one.
- `baseRevision` and `remoteRevision`: revisions used for this inventory.
- `files`: entries with `repositoryPath`, `localPath`, and `state`.
- `legacyMiseConfig`: `path` and `state` for `~/.config/mise/config.toml`, the pre-`conf.d` location of this repository's mise config.

A `fetch` other than `ok` means the inventory describes whatever this checkout last
fetched, not the current remote.
Report that to the user instead of reporting the inventory as current — an inventory
built on a stale `origin/main` fails by looking like "no updates", not by erroring.

Only `conflict`, `needs-decision`, and a `legacyMiseConfig` state of `needs-review` require agent judgment.
The script owns every other state and its merge, validation, backup, task, rollback, and revision behavior.

A `no-base` plan cannot be applied safely.
Ask the user how to proceed; do not run `apply` for that plan.

## 3. Resolve the decision queue

For every `conflict` or `needs-decision` entry, determine whether the local content is still needed on this machine or is obsolete.
Resolve a conflict by its setting's meaning, not by choosing a side mechanically.

When the available context does not establish that choice, present the affected paths and alternatives to the user and obtain a decision.
Do not run `apply` while any decision remains unresolved.

A `legacyMiseConfig` state of `needs-review` blocks `apply` in the same way.
That file is this repository's own copy with local changes written on top, and it outranks `conf.d`: leaving it keeps every update shadowed, while moving it wholesale would drop whatever the machine added to it.
Show the user how it differs from `~/.config/mise/conf.d/10-dotfiles.toml`, keep only the machine-local part in `config.toml`, and create a fresh plan.
Re-run with `DOTFILES_MIGRATE_MISE_CONFIG=1` only when the user confirms that nothing in the file is still wanted.
The other states need nothing: `migratable` is the script's to move aside into the backup, and `unrelated`, `destination`, and `absent` mean there is nothing to migrate.

Make only a user-confirmed local change, then create a fresh plan.
This step is complete only when `mode` is `inventory`, no file has state `conflict` or `needs-decision`, and `legacyMiseConfig.state` is not `needs-review`.

## 4. Confirm and apply

Summarize the safe plan and the resolved decisions for the user, then obtain explicit confirmation to update this machine.

```bash
.dotfiles/apply.sh apply --json
```

Read the result JSON:

- `result: "applied"` means the script completed the update.
- `result: "failed"` or `"rolled-back"` means no successful update may be reported.
- `apply` refuses to run at all when its own fetch failed, rather than update this
  machine against a remote it could not confirm.
- `backupPath` identifies the backup when the script created one.
- `error` records the failure details; report it verbatim enough for the user to act on it.

## 5. Report

Report the script result, the applied revision when available, the backup path, every local decision and its reason, and any unresolved user question or failure.

This procedure is complete only when the final report reflects the JSON returned by the last command and states no successful apply unless `result` is `applied`.
