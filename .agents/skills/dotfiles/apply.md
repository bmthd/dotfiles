# /dotfiles apply

`.dotfiles/apply.sh` is the source of truth for the deterministic update work.
This English file is authoritative; keep the Japanese file as its structural and semantic mirror.
This procedure supplies the judgment and communication the script cannot make.

## 1. Create a plan

From the fetched dotfiles checkout, run:

```bash
.dotfiles/apply.sh plan --json
```

`plan` is read-only.
Treat its single JSON document as the current inventory.

The top-level fields are:

- `mode`: `inventory` permits an apply decision; `no-base` does not.
- `baseRevision` and `remoteRevision`: revisions used for this inventory.
- `files`: entries with `repositoryPath`, `localPath`, and `state`.

Only `conflict` and `needs-decision` require agent judgment.
The script owns every other state and its merge, validation, backup, task, rollback, and revision behavior.

A `no-base` plan cannot be applied safely.
Ask the user how to proceed; do not run `apply` for that plan.

## 2. Resolve the decision queue

For every `conflict` or `needs-decision` entry, determine whether the local content is still needed on this machine or is obsolete.
Resolve a conflict by its setting's meaning, not by choosing a side mechanically.

When the available context does not establish that choice, present the affected paths and alternatives to the user and obtain a decision.
Do not run `apply` while any decision remains unresolved.

Make only a user-confirmed local change, then create a fresh plan.
This step is complete only when `mode` is `inventory` and no file has state `conflict` or `needs-decision`.

## 3. Confirm and apply

Summarize the safe plan and the resolved decisions for the user, then obtain explicit confirmation to update this machine.

```bash
.dotfiles/apply.sh apply --json
```

Read the result JSON:

- `result: "applied"` means the script completed the update.
- `result: "failed"` or `"rolled-back"` means no successful update may be reported.
- `backupPath` identifies the backup when the script created one.
- `error` records the failure details; report it verbatim enough for the user to act on it.

## 4. Report

Report the script result, the applied revision when available, the backup path, every local decision and its reason, and any unresolved user question or failure.

This procedure is complete only when the final report reflects the JSON returned by the last command and states no successful apply unless `result` is `applied`.
