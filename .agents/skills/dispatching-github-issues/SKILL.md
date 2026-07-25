---
name: dispatching-github-issues
description: Use when the user wants GitHub Issues searched with gh and selected issue work orchestrated through commander-style parallel subagents, especially when dry-run validation is required before execution.
argument-hint: <issue search or dispatch instruction>
---

# Dispatching GitHub Issues

Find actionable GitHub Issues with `gh`, let the user choose what to pursue, then
act as a commander to validate and dispatch independent work to subagents in
parallel. The guarantee is evidence-based: do not claim the workflow is ready
until dry-run subagents have validated the selected work without modifying state.

## Required Sub-Skills

- **REQUIRED:** Use `commander` once issue work is selected. The commander never
  performs hands-on implementation, tests, commits, pushes, or issue edits.
- **REQUIRED WHEN CREATING OR EDITING THIS SKILL:** Use `writing-skills` and run
  dry-run subagent scenarios before shipping changes.

## Steps

### 1. Parse the Request

Read `args`. If empty, ask what repository, labels, keywords, or issue type to
search. Extract:

- Repository scope; default to the current GitHub repo only if unambiguous.
- Search filters: labels, milestone, assignee, state, keywords, limit.
- Selection mode: user-selected by default; automatic only if explicitly asked.
- Dispatch intent: dry-run validation only, or dry-run followed by implementation.

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
| `blocked` | Marked blocked, assigned in a way that matters, depends on external access, or needs maintainer decision. |
| `not parallel-safe` | Actionable alone but likely overlaps selected work or needs shared sequencing. |

Report candidates with issue number, URL, title, rationale, likely touched area,
verification signal, and risks. Ask the user which issues to dispatch unless the
request explicitly authorized automatic selection.

### 5. Validate with Dry-Run Subagents

Before implementation dispatch, send one dry-run subagent per selected issue in
parallel. The dry-run is mandatory even when the issue looks obvious.

Use this prompt shape:

```text
You are validating a GitHub Issue task in dry-run mode.

Issue: <number, URL, title, labels, body summary, relevant comments>
User instruction: <original instruction and selection constraints>
Scope: inspect only. Do not modify files. Do not run state-changing commands.
Do not commit, push, open PRs, edit issues, assign labels, or leave comments.

Tasks:
1. Inspect the repo and issue context enough to judge feasibility.
2. Decide whether the issue is actionable from available information.
3. Identify likely files or components involved.
4. Propose the smallest correct implementation approach.
5. Identify verification commands or manual checks for a real implementation.
6. Identify overlap with the other selected issues listed here: <issue list>.
7. Confirm no files or remote state were changed.

Return:
- Verdict: actionable / needs clarification / blocked / not parallel-safe
- Confidence:
- Evidence inspected:
- Proposed approach:
- Likely files touched:
- Verification plan:
- Risks or questions:
- State-change confirmation:
```

### 6. Gate the Dispatch

Only proceed to commander implementation dispatch when every selected issue has a
dry-run report and each report is `actionable` or intentionally accepted by the
user despite risks. If any report is `needs clarification`, `blocked`, or `not
parallel-safe`, stop and summarize the blocker instead of powering through.

### 7. Commander Implementation Dispatch

When implementation is authorized, switch into commander behavior:

- Decompose selected issues into independent units.
- Dispatch independent units in parallel in one message.
- Never allow two parallel agents to touch the same likely files.
- Put issue context, dry-run findings, scope, and report format in each prompt.
- Verify subagent reports read-only before claiming completion.

## Quick Reference

| Need | Action |
|---|---|
| Find issues | `gh issue list` with repo-specific labels/search. |
| Confirm context | `gh issue view <n> --comments --json ...`. |
| Decide actionability | Use concrete outcome, bounded scope, context, verification, and blockers. |
| Validate workflow | Parallel dry-run subagents, one per selected issue. |
| Implement | Use `commander`; delegate hands-on work, keep verification read-only. |

## Red Flags

- You are about to skip dry-run because the issue is "obvious".
- You selected issues automatically without explicit authorization.
- You ignored issue comments that may contain maintainer decisions or duplicates.
- Two parallel agents may edit the same files.
- You are claiming the workflow is guaranteed without actual dry-run reports.
- You are doing implementation work yourself while claiming commander mode.

## Common Mistakes

- **Treating labels as truth:** comments can supersede labels. Inspect promising
  issues with `gh issue view --comments`.
- **Confusing actionable with parallel-safe:** an issue can be clear but still
  conflict with another selected task.
- **Over-promising dry-run:** dry-run validates feasibility and orchestration, not
  final correctness. Report the evidence and residual risks.
- **Under-specifying prompts:** subagents start cold. Include issue context,
  constraints, other selected issues, and exact report fields.
