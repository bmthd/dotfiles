---
name: merge-queue
description: Use when the user hands you several PR numbers and wants them merged unattended — emulates a GitHub Merge Queue locally, resolving merge blockers (approval, out-of-date branch, conflicts, simple CI failures) autonomously so they can walk away. Gates up front and stops if nothing is auto-mergeable. Invoke as /merge-queue <pr-numbers>.
argument-hint: <pr-numbers...>
---

# Merge Queue

Take a set of pull requests, queue them, and drive each one to a merged state the way
GitHub's Merge Queue would — sequentially, always against the freshest base. Resolve the
things that block a merge **one at a time and autonomously**: approve, update the branch,
resolve simple conflicts, fix simple CI failures. The caller is handing this off and
leaving; your job is to finish everything you safely can and leave a clean report of
whatever genuinely needs a human.

## The Deal (read before doing anything)

- **Gate first, work second.** Assess every PR before you touch any of them. If **none**
  are mergeable-now or auto-resolvable, STOP and ask the user — do not start half-work.
- **Don't block on lunch.** Once at least one PR is actionable, proceed without asking for
  confirmation. A PR that turns out to need human judgment is *deferred to the final
  report*, not a reason to halt the whole run.
- **Autonomy has a boundary.** You resolve *mechanical* blockers. Anything requiring a
  product/logic decision — a semantic merge conflict, a real test failure, marking a draft
  ready — is deferred, never guessed at.
- **Everything here is outward-facing and hard to undo** (approvals, pushes, merges). The
  PR numbers in `args` are the authorization to merge *those* PRs and nothing else.

## Steps (follow strictly)

### 1. Parse input and preflight

Read PR numbers from `args` (space/comma separated). If empty, ask which PRs. Then:

```bash
gh auth status          # must be authenticated
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner, .defaultBranchRef.name'
```

Work in a **clean checkout of this repo** (no uncommitted changes — `git status` clean).
If the working tree is dirty, STOP and tell the user; you must not stash their work.

### 2. Assess every PR (the gate)

For each PR, pull the state in one shot:

```bash
gh pr view <n> --json number,title,isDraft,mergeable,mergeStateStatus,reviewDecision,\
headRefName,baseRefName,statusCheckRollup,author,url
```

Map `mergeStateStatus` + review state to a class:

| State | Meaning | Class |
|---|---|---|
| `CLEAN` | up to date, approved, checks green | **Merge now** |
| `BEHIND` | branch out of date with base | **Auto-resolve** → update branch |
| `BLOCKED` (only missing approval) | needs a review | **Auto-resolve** → approve |
| `UNSTABLE` / failing checks | a check is red | **Inspect** (§4.3) — simple fix or defer |
| `DIRTY` | merge conflict | **Inspect** (§4.2) — simple resolve or defer |
| `DRAFT` / `isDraft` | draft PR | **Defer** — human marks it ready |
| `UNKNOWN` | GitHub still computing | re-poll a few times before classifying |

Print a one-line-per-PR summary of the classification (this is the plan the user sees
before walking away).

**Gate decision:** if every PR lands in **Defer** (nothing is Merge-now or Auto-resolve),
STOP. Report why each is blocked and ask the user how to proceed. Otherwise continue.

### 3. Order the queue

Process PRs sharing a base branch **sequentially**, in the order given (respect explicit
dependencies if the user stated any). Sequential is the whole point: each PR is brought
up to date *after* the previous one merges, so you are always testing the real combined
result — exactly what a merge queue does. Different base branches are independent lanes.

### 4. Drive each PR to merged

For the current PR, resolve blockers **one at a time**, re-checking state after each fix
(a fix often changes `mergeStateStatus`). Loop until CLEAN or deferred.

#### 4.1 Out of date (`BEHIND`)
```bash
gh pr update-branch <n>          # merges base into the PR branch server-side
```
Then wait for checks to re-run (§4.4). If update-branch itself reports a conflict, treat
as §4.2.

#### 4.2 Conflict (`DIRTY`)
Resolve locally against the current base:
```bash
git fetch origin
git switch <headRefName> && git pull
git merge origin/<baseRefName>
```
- **Simple** — conflicts only in lockfiles / generated files (regenerate them), or trivial
  non-overlapping hunks: resolve, commit, `git push`.
- **Semantic** — overlapping edits to real source/logic: **defer**. Abort (`git merge
  --abort`), record it for the report. Do not guess at intent.

#### 4.3 Failing CI (`UNSTABLE` / red checks)
```bash
gh pr checks <n>                 # see which check failed
```
Only **simple, mechanical** failures are in scope:
- Formatting / lint autofix (`mise run fmt`, `prettier -w`, `eslint --fix`, `cargo fmt`,
  `gofmt` — whatever the repo uses), commit and push.
- Stale generated files / lockfiles → regenerate, push.
- A single obviously-flaky check → re-run **once** (`gh run rerun --failed`).

Everything else — real unit/integration failures, type errors needing code changes,
security scans — is **defer**. You are not debugging product logic here.

#### 4.4 Missing approval (`BLOCKED` on review)
```bash
gh pr review <n> --approve -b "Approved via merge-queue"
```
If you are the PR author you cannot self-approve, and branch protection may require another
party — in that case **defer** (record "needs approval from someone else").

#### 4.5 Merge
When the PR is CLEAN, merge with the repo's convention (check `git log` / repo settings;
default squash):
```bash
gh pr merge <n> --squash --delete-branch
git switch <baseRefName> && git pull --ff-only   # refresh local base for the next PR
```

### 5. Advance the queue

After a merge, re-assess the **remaining** PRs from §2 — the merge you just did usually
puts the next one `BEHIND` or, occasionally, `DIRTY`. Continue until the queue is empty.

### 6. Report

Give the user a single summary they can read after lunch:
- ✅ Merged (with PR numbers/links)
- 🔧 Auto-resolved and merged, with *what* you did (approved / updated / fixed lint / …)
- ⏭️ Deferred — each with the concrete blocker and the human action needed
- Anything you re-ran or pushed to their branches

## Red Flags — STOP or DEFER, do not power through

- **You are about to resolve a conflict in real source code by choosing a side.** Defer.
- **A test failed and you are editing product code to make it pass.** Out of scope — defer.
- **Tempted to mark a draft "ready" or dismiss a requested change.** That is the human's
  call — defer.
- **`--force` / `--admin` / bypassing branch protection.** Never. If protection blocks the
  merge, that is a deliberate gate — defer it.
- **Nothing was actionable but you started editing anyway.** The gate in §2 means STOP.

## Gotchas

- **Dirty working tree**: this skill pushes commits and switches branches. Refuse to run
  if `git status` isn't clean — you must never stash or clobber the user's local work.
- **Self-approval is impossible**: GitHub rejects approving your own PR. In a solo repo the
  approval blocker is unresolvable autonomously — surface it rather than looping.
- **`mergeStateStatus` lags**: after any push/update it goes `UNKNOWN` while GitHub
  recomputes. Poll a few times (short sleeps) before deciding it's blocked.
- **`UNSTABLE` can still be mergeable**: it means a *non-required* check is red. If required
  checks are green and policy allows, it may merge as-is — don't "fix" a check that isn't
  actually gating.
- **Sequential, not parallel**: never update/merge two PRs on the same base concurrently —
  you'd be testing a combination that won't exist. One at a time, re-based after each merge.
- **Re-run flaky once, not forever**: a check that fails twice is not flaky. Defer it.
