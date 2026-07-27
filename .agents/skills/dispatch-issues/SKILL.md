---
name: dispatch-issues
description: Use when the user wants to search or triage GitHub Issues with gh, choose actionable issues, or prepare parallel issue work for subagents.
argument-hint: <issue search or dispatch instruction>
---

# Dispatch Issues

Find actionable GitHub Issues with `gh`, let the user choose what to pursue, then
act as a commander to dispatch independent issue work to subagents in parallel.

## Required Sub-Skill

- **REQUIRED:** Use `commander` once issue work is selected. The commander never
  performs hands-on implementation, tests, commits, pushes, or issue edits.

## Steps

### 1. Parse the Request

Read `args`. If empty, ask what repository, labels, keywords, or issue type to
search. Extract:

- Repository scope; default to the current GitHub repo only if unambiguous.
- Search filters: labels, milestone, assignee, state, keywords, limit.
- Selection mode: user-selected by default; automatic only if explicitly asked.
- Dispatch intent: triage only, implementation, review, documentation, or another
  user-specified outcome.

### 2. Preflight

```bash
gh auth status
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner + " " + .defaultBranchRef.name'
```

If auth fails, stop and ask the user to authenticate. Use read-only `gh issue`
commands during discovery. Do not edit issues, labels, assignments, projects, or
comments unless the user explicitly asks for that state change — the one standing
exception is a dispatched agent reporting a dead end on its own issue (step 5).

### 2b. Verify the baseline (do not skip)

Issues are written against a tree. The checkout you are sitting in may not be
that tree. Dispatching parallel agents onto the wrong baseline wastes every one
of them, so establish the baseline **before** step 5.

```bash
git status -sb
git log --oneline -1
git fetch origin --quiet
git log --oneline -1 origin/main
git merge-base --is-ancestor HEAD origin/main && echo "on main" || echo "DIVERGED"
```

Then **spot-check the issue bodies against the tree**. Issues cite file paths and
line numbers; resolve two or three of them:

```bash
wc -l <files the issues cite>
grep -n '<exact snippet quoted in the issue>' <file>
```

Stop and ask the user when any of these hold:

- **Detached HEAD**, or HEAD diverged from `origin/main`.
- A cited file is missing, or its length is far from what the issue implies.
- A cited symbol/snippet does not exist (the feature lives on an unmerged branch).
- Issue line numbers are off by more than a couple of lines.

Line numbers that are merely shifted are fine — but **tell each subagent the
corrected line** ("the issue says 583; on this branch it is 582"), or it will
edit the wrong place.

### 2c. Preserve unreferenced commits before switching

If HEAD is detached with commits that no branch contains, switching away leaves
them reachable only via reflog, where `gc` will eventually take them. Give them a
name **before** creating the work branch:

```bash
git branch --contains <sha>          # empty output = nothing points at it
git branch wip/detached-<short-sha> <sha>
git checkout -b <work-branch> origin/main
```

Report the rescue branch to the user. Never `reset`, `rebase`, or delete it.

### 3. Discover Candidate Issues

Start broad, then inspect promising issues:

```bash
gh issue list --state open --limit 30
gh issue list --state open --search 'is:issue is:open no:assignee' --limit 30
gh issue list --state open --label 'help wanted' --limit 30
gh issue view <number> --comments --json number,title,body,labels,assignees,comments,url,state
```

Adapt filters to the repository vocabulary (`bug`, `enhancement`, `good first
issue`, `priority`, `needs-triage`). Inspect comments before classifying; labels
alone are not enough.

### 4. Classify Actionability

| Verdict | Criteria |
|---|---|
| `actionable` | Concrete desired outcome, bounded scope, enough context, open, not blocked, likely verifiable. |
| `needs clarification` | Goal is plausible but product intent, reproduction, or acceptance criteria are missing. |
| `blocked` | Marked blocked, assigned to someone else where assignment appears to mean ownership, depends on external access, or needs maintainer decision. |
| `not parallel-safe` | Reserved for true sequencing: the issue needs another selected issue's outcome before it can start. Touching the same files is **not** enough to land here — overlapping work is dispatched in parallel and reconciled at merge time. |

Report candidates with issue number, URL, title, rationale, likely touched area,
verification signal, and risks. Ask the user which issues to dispatch unless the
request explicitly authorized automatic selection.

### 5. Dispatch Through Commander

After issue selection, switch into commander behavior:

- Decompose selected issues into independent units.
- Choose an isolation mode (see below) before writing any prompt.
- Dispatch independent units in parallel in one message.
- Put issue context, relevant comments, scope, constraints, and report format in
  each prompt.
- Verify subagent reports read-only before claiming completion.

#### Choose the isolation mode first

| Units | Mode | Why |
|---|---|---|
| 1–2, clearly disjoint files | Shared tree, file partitioning | No merge step, no `pnpm install` per unit. |
| **3+, or any file overlap** | **Worktree isolation** (`isolation: "worktree"`) | Agents work unconstrained; conflicts are resolved once, at the end. |

Default to worktree isolation as soon as there are three or more units. File
partitioning looks cheaper but it taxes every agent:

- You must forbid `fmt` / `lint --fix` / `check` / `build` repo-wide, because
  they rewrite files other agents are mid-edit.
- Units that share a file get pushed to a later wave instead of running now.
- One agent needing a file outside its lane stalls and has to report back.

Worktree isolation costs a dependency install per worktree and a merge at the
end. That is usually the better trade — and the user often expects it, so say
which mode you picked rather than letting them assume.

#### Commit policy depends on the mode

- **Shared tree:** forbid commits. Changes land in one tree; the user reviews the
  combined diff.
- **Worktree isolation:** local commits on the agent's own worktree branch are
  **required** — uncommitted work in a worktree cannot be integrated. Forbid
  `push` and PR creation, and forbid switching to or modifying `main` / the work
  branch / any rescue branch.

Either way, `gh issue` labels, assignments, and closures stay forbidden unless the
user asked for that state change.

`gh issue comment` has one standing exception. **When a unit ends without a
PR-ready result — blocked, root cause not found, tests not green, a product
decision needed — the agent must not finish silently.** It posts its findings to
the issue with `gh issue comment <n>`, in Japanese, covering:

- what it established (分かったこと),
- what it tried (試したこと),
- the evidence behind both (numbers, failing output, screenshots),
- why the work did not reach a PR,
- the options it recommends next.

When the work does reach a PR, no comment is needed — `Closes #N` in the PR body
covers it. A transcript is not a report: an investigation that never lands on the
issue is lost the moment the agent exits.

#### Other constraints worth putting in every prompt

- **Dev server ports are machine-global.** Assign each agent its own port
  (5181, 5182, …) and tell it to shut the server down. Otherwise the second agent
  to start silently binds elsewhere or fails.
- **The baseline numbers.** Give the pre-change test count and type-check status
  from step 2b, so the agent can tell its own regressions from pre-existing ones.
- **The corrected line numbers** when they drifted from the issue body.
- **Overlap is expected, not forbidden.** Tell each agent that other agents may
  be editing the same files right now. That is never a reason to stall, ask
  permission, or narrow the fix — the conflict is resolved when the branches
  merge.
- **Minimal diffs**, precisely because of that overlap: no drive-by reformatting,
  no unrelated cleanups, the smallest change that closes the issue. Sprawl is
  what makes the merge unreadable, not the overlap itself.
- **The fallback report.** If the unit will not reach a PR, the agent comments
  its findings on the issue in Japanese rather than ending on a shrug.

Use this dispatch prompt shape:

```text
Objective: <what done looks like for issue #N>
Issue context: <number, URL, title, labels, body summary, relevant comments>
Baseline: <branch, HEAD sha, test count, type-check status, corrected line refs>
Environment: <worktree-isolated or shared tree; install step; allowed commands;
assigned dev-server port>
Scope: <files/areas allowed, files/areas not allowed, state-changing limits>
Shared files: <other units running now and the files they may also touch; overlap
is expected — keep the diff minimal, do not stall on it>
Constraints: <commit policy for this mode; no pushes, PRs, labels, assignments,
or closures; if the unit does not reach a PR-ready result, comment the findings
on issue #N in Japanese with `gh issue comment`>
Report format: files changed, commands run with results, risks, blockers,
open questions, and verification evidence.
```

## Quick Reference

| Need | Action |
|---|---|
| Find issues | `gh issue list` with repo-specific labels/search. |
| Confirm context | `gh issue view <n> --comments --json ...`. |
| Check the baseline | `git status -sb`, `git log --oneline -1 origin/main`, resolve cited lines. |
| Decide actionability | Use concrete outcome, bounded scope, context, verification, and blockers. |
| Dispatch work | Use `commander`; delegate hands-on work, keep verification read-only. |
| Handle file overlap | Dispatch anyway under worktree isolation; resolve the conflict at merge time. |
| Close out a dead end | `gh issue comment <n>` in Japanese: findings, attempts, evidence, why no PR, next options. |

## Red Flags

- You selected issues automatically without explicit authorization.
- You ignored issue comments that may contain maintainer decisions or duplicates.
- You have not checked that the cited files and lines exist in *this* checkout.
- HEAD is detached, or diverged from `origin/main`, and you dispatched anyway.
- Three or more units are going into one shared tree.
- You serialized a unit, dropped it, or asked the user to pick one, because two
  agents might edit the same files.
- An agent ended with neither a PR nor a comment on its issue.
- You are doing implementation work yourself while claiming commander mode.
- A subagent prompt lacks issue context, scope, constraints, or report format.

## Common Mistakes

- **Treating labels as truth:** comments can supersede labels. Inspect promising
  issues with `gh issue view --comments`.
- **Trusting the checkout:** the tree an issue was written against and the tree
  you are in are different claims. A feature described in an issue can live on an
  unmerged branch, in which case its "actionable" issues have nothing to edit.
  Verify in step 2b, before selection — a candidate list built on the wrong tree
  is wrong in ways the user cannot see.
- **Treating file overlap as a blocker:** two issues touching one file is a merge
  to perform, not a reason to serialize the units, drop one, or make the user
  choose. Dispatch both, isolate them in worktrees, reconcile at the end.
- **Letting a dead end die in the transcript:** a unit that produced no PR still
  produced knowledge. If it is not on the issue, the next agent starts from
  zero.
- **Reaching for file partitioning by reflex:** it is the right call for two
  units and a tax on every unit beyond that. Pick the mode deliberately and tell
  the user which one you picked.
- **Forbidding commits under worktree isolation:** the work then has no way back.
  Require local commits on the agent's own branch; forbid pushes and PRs instead.
- **Dispatching too early:** show candidates and get selection unless automatic
  selection was explicitly authorized.
- **Under-specifying prompts:** subagents start cold. Include issue context,
  constraints, other selected issues, and exact report fields.
