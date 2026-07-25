---
name: fix-pr
description: Use when the user wants to make a GitHub pull request mergeable, resolve PR review comments, failing checks, merge conflicts, or update a branch from main. Invoke as /fix-pr [PR_NUMBER] [--auto].
argument-hint: [PR_NUMBER] [--auto]
---

# Fix PR

Bring a GitHub pull request to a mergeable state without guessing about review feedback.

## Steps

### 1. Identify the PR

Read `args`.

- If `args` contains a PR number, use it.
- Otherwise, if the current conversation clearly names the working PR, use that PR.
- Otherwise, run `gh pr view --json number,url,headRefName,baseRefName` from the current repo to identify the PR for the current branch.
- If no PR can be identified, ask the user for the PR number and stop.

Set `auto=true` only when `args` contains `--auto`.

### 2. Inspect Before Editing

Collect the current state:

```bash
gh pr view <PR> --json number,title,url,state,isDraft,mergeStateStatus,reviewDecision,headRefName,baseRefName,comments,reviews,reviewThreads,statusCheckRollup
gh pr checks <PR>
git status --short
```

Also inspect failing check logs with `gh run view --log-failed` when a failing run is available.

Do not modify unrelated dirty files. If local changes directly conflict with required fixes, ask the user how to proceed.

Before editing, ensure the worktree is on the PR head branch:

- If already on `headRefName`, continue.
- If not on `headRefName` and there are unrelated local changes, ask before switching branches.
- Otherwise check out the PR branch with the repository's normal workflow, such as `gh pr checkout <PR>`.
- Never commit or push to a branch other than the PR `headRefName`.

### 3. Review Comment Policy

Review comments are not automatically correct.

If there are actionable review comments and `--auto` was NOT provided, output a table and wait for user confirmation before editing code:

| Comment | Proposed action | Reason | Risk |
|---|---|---|---|
| `<file:line summary>` | accept / reject / investigate | `<why>` | low / medium / high |

If `--auto` was provided, handle comments autonomously:

- Apply clearly correct requested changes.
- Investigate ambiguous suggestions before editing.
- Do not apply technically wrong suggestions; explain why in the final report.
- Prefer minimal fixes over broad refactors.

### 4. Make It Mergeable

Work through blockers in this order:

1. Requested changes and unresolved review threads.
2. Failing required checks.
3. Branch out of date with base.
4. Merge conflicts.
5. Missing local verification.

For each code or behavior fix, follow test-driven-development when feasible: reproduce the failure first, make the smallest fix, then verify it passes.

Use normal non-interactive commands. If the branch needs updating from base, first confirm you are on the PR head branch. Prefer the repository's documented merge/rebase convention. If no convention exists, prefer a non-rewriting merge from the base branch. Do not rebase, force-push, or otherwise rewrite published PR history without explicit user approval.

### 5. Verify and Push

Run targeted tests or checks that cover the fixes. If the repo has an obvious full validation command and it is reasonable to run, run it too.

Before pushing, inspect:

```bash
git status --short
git diff
```

Only commit and push when there are intentional local changes that need to be sent to the PR branch. Use the repo's commit style. If no changes are needed, skip commit/push and report the current PR state.

### 6. Re-check PR State

After pushing, re-run:

```bash
gh pr checks <PR>
gh pr view <PR> --json mergeStateStatus,reviewDecision,statusCheckRollup
```

If checks are still pending, report that the PR is waiting on CI. If checks fail, continue investigating unless blocked by permissions, missing secrets, flaky external services, or user policy.

If `reviewDecision` remains `CHANGES_REQUESTED` or required threads remain unresolved after fixes, do not call the PR mergeable. Report that reviewer action is still required. If appropriate for the repo workflow, leave a concise PR comment explaining rejected review suggestions with technical reasons.

## Output

When finished, report:

- PR URL.
- Fixes made.
- Verification run and results.
- Remaining blockers, if any.
- Review suggestions intentionally rejected, with reasons.

## Common Mistakes

- Do not edit before presenting the review-comment table unless `--auto` was passed.
- Do not assume a review suggestion is correct.
- Do not force-push, rebase, or rewrite PR history unless the user explicitly approves it or the repo's instructions require it.
- Do not claim mergeable until `gh pr view` and `gh pr checks` confirm it, or clearly state what is still pending.
