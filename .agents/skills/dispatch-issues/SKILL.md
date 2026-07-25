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
comments unless the user explicitly asks for that state change.

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
| `not parallel-safe` | Actionable alone but likely overlaps selected work or needs shared sequencing. |

Report candidates with issue number, URL, title, rationale, likely touched area,
verification signal, and risks. Ask the user which issues to dispatch unless the
request explicitly authorized automatic selection.

### 5. Dispatch Through Commander

After issue selection, switch into commander behavior:

- Decompose selected issues into independent units.
- Dispatch independent units in parallel in one message.
- Never allow two parallel agents to touch the same likely files.
- If selected issues overlap, serialize them or ask the user to choose one first.
- Put issue context, relevant comments, scope, constraints, and report format in
  each prompt.
- In each implementation prompt, explicitly forbid commits, pushes, PRs, issue
  edits, labels, assignments, and comments unless the user requested those state
  changes.
- Verify subagent reports read-only before claiming completion.

Use this dispatch prompt shape:

```text
Objective: <what done looks like for issue #N>
Issue context: <number, URL, title, labels, body summary, relevant comments>
Scope: <files/areas allowed, files/areas not allowed, state-changing limits>
Parallel safety: <other selected issues and known overlap constraints>
Constraints: <no commits/pushes/PRs/issue edits unless explicitly requested>
Report format: files changed, commands run with results, risks, blockers,
open questions, and verification evidence.
```

## Quick Reference

| Need | Action |
|---|---|
| Find issues | `gh issue list` with repo-specific labels/search. |
| Confirm context | `gh issue view <n> --comments --json ...`. |
| Decide actionability | Use concrete outcome, bounded scope, context, verification, and blockers. |
| Dispatch work | Use `commander`; delegate hands-on work, keep verification read-only. |

## Red Flags

- You selected issues automatically without explicit authorization.
- You ignored issue comments that may contain maintainer decisions or duplicates.
- Two parallel agents may edit the same files.
- You are doing implementation work yourself while claiming commander mode.
- A subagent prompt lacks issue context, scope, constraints, or report format.

## Common Mistakes

- **Treating labels as truth:** comments can supersede labels. Inspect promising
  issues with `gh issue view --comments`.
- **Confusing actionable with parallel-safe:** an issue can be clear but still
  conflict with another selected task.
- **Dispatching too early:** show candidates and get selection unless automatic
  selection was explicitly authorized.
- **Under-specifying prompts:** subagents start cold. Include issue context,
  constraints, other selected issues, and exact report fields.
