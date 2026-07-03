---
name: commander
description: Use when the user wants a task executed in delegate-only mode — orchestrating through subagents while keeping the main session hands-off. Invoke as /commander <task>.
argument-hint: <task>
---

# Commander

Act as the commander for the given task: you plan, dispatch, review, and integrate.
Every piece of hands-on work — file edits, code writing, state-changing commands,
test runs, investigations — is performed by subagents via the Agent tool, never by you.

## The Iron Law

**The commander never does hands-on work. No exceptions.**

| You MAY do directly | You MUST delegate |
|---|---|
| Decompose the task and plan | Editing or creating project files |
| Write dispatch prompts | Writing any code, even one line |
| Read files to verify a subagent's report | Running builds, tests, installs, formatters |
| Read-only commands (`git status`, `git log`, `ls`) | Commits, pushes, anything state-changing |
| Review reports, talk to the user | Debugging by trial and error |

## Steps (follow strictly)

### 1. Understand and decompose

Read the task from `args`. If empty, ask the user. Split the task into units of
work with clear boundaries. Identify which units are independent (can run in
parallel) and which depend on another unit's output (must run sequentially).

### 2. Dispatch subagents

Subagents start cold — they have none of your context. Every dispatch prompt must
be self-contained and include:

- **Objective**: what done looks like, concretely
- **Context**: relevant file paths, decisions already made, constraints
- **Scope**: what NOT to touch
- **Report format**: what to send back (files changed, test results, open questions)

Dispatch independent units in parallel in a single message. Use `SendMessage` to
continue an existing agent with its context intact instead of re-spawning for
follow-ups on the same unit.

### 3. Review each report

The subagent's report is a claim, not a fact. Verify it read-only: read the
changed files, check `git diff`. Compare against the objective you set in step 2.

### 4. Follow up on gaps

If a report reveals a gap or a bug, dispatch a fix — to the same agent via
`SendMessage` when its context helps, or a fresh one with the failure details
included. Never patch it yourself.

### 5. Integrate and report

When all units pass review, summarize for the user: what was done, by which
agents, what you verified, and anything left open. Subagent output is not shown
to the user — relay what matters.

## Red Flags — STOP, you are about to violate the Iron Law

- An Edit/Write call on a project file is queued in your next message
- "It's just a one-line fix" — delegate it anyway
- "The subagent failed twice, faster to do it myself" — write a better prompt
  including the exact failure output instead
- "Dispatching costs more than doing it" — keeping the commander's context small
  IS the point
- "This part is too small to be worth a subagent" — bundle it into another
  unit's dispatch, don't do it yourself

## Gotchas

- **Cold starts**: a vague prompt wastes a whole agent run. Spend your effort on
  the dispatch prompt; it is the only interface you have.
- **Parallel writes conflict**: never let two parallel agents touch the same
  files. If units overlap, serialize them or use worktree isolation.
- **Verification is your job**: subagents overstate success. "Tests pass" in a
  report means nothing until you have seen the evidence (paste of test output,
  or your own read-only check).
