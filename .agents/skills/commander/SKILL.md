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
Only a real ordering dependency — one unit needs another's result before it can
start — forces sequencing. Units that merely touch the same files are still
independent: dispatch them together and reconcile at merge time.

### 2. Dispatch subagents

Subagents start cold — they have none of your context. Every dispatch prompt must
be self-contained and include:

- **Objective**: what done looks like, concretely
- **Context**: relevant file paths, decisions already made, constraints
- **Scope**: what NOT to touch
- **Shared files**: which other units are running now and what they may also
  touch — overlap is expected, never a reason to stall, ask permission, or
  narrow the fix — plus the standing instruction to keep the diff minimal (no
  drive-by reformatting, no unrelated cleanups) so the merge stays readable
- **Report format**: what to send back (files changed, test results, open questions)
- **Fallback report**: what to do if the unit will not reach a deliverable —
  report the findings instead of finishing silently (see step 5)

Dispatch independent units in parallel in a single message. Use `SendMessage` to
continue an existing agent with its context intact instead of re-spawning for
follow-ups on the same unit.

Pick an isolation mode before writing prompts. With three or more units, or any
overlap in the files they touch, default to `isolation: "worktree"` — each agent
gets its own checkout and can run formatters, builds, and tests at full speed
without wrecking another agent's in-flight edits. Worktrees are how you let
overlapping work run in parallel, not a way to avoid the overlap: the units still
land on the same files and you still merge them at the end. Under worktree
isolation, require each agent to **commit to its own worktree branch**
(uncommitted work in a worktree cannot be integrated) while still forbidding
pushes and PRs. Machine-global resources — dev-server ports especially — still
collide across worktrees, so assign them per agent.

### 3. Review each report

The subagent's report is a claim, not a fact. Verify it read-only: read the
changed files, check `git diff`. Compare against the objective you set in step 2.

### 4. Follow up on gaps

If a report reveals a gap or a bug, dispatch a fix — to the same agent via
`SendMessage` when its context helps, or a fresh one with the failure details
included. Never patch it yourself.

### 5. Integrate and report

Integration is yours to *direct*, not to perform. Merging worktree branches,
resolving conflicts, and re-running the suite afterwards are hands-on work: the
Iron Law covers them exactly as it covers the original edits. Dispatch an
integration agent with the branch list, the merge order you chose, how to settle
the conflicts you expect, and the verification it must produce. Then check its
report read-only, the same as any other.

When all units pass review, summarize for the user: what was done, by which
agents, what you verified, and anything left open. Subagent output is not shown
to the user — relay what matters.

Units that reached no deliverable belong in that summary, not omitted from it. A
dead end still produced knowledge — what it established, what it tried, the
evidence behind both, why it stopped short, what to try next — and that knowledge
dies with the transcript unless you relay it. When the unit belongs to a GitHub
Issue, `dispatch-issues` governs and the agent comments those findings on the
issue in Japanese with `gh issue comment`; otherwise they go in the summary.

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
- **Overlapping files are not a blocker**: two units editing one file is a merge
  to perform, not a reason to serialize them, drop one, or make the user choose.
  Dispatch both under worktree isolation and reconcile at the end — and tell each
  agent the overlap exists, so it keeps its diff minimal instead of stalling.
- **File partitioning is not free**: it buys you a merge-free shared tree by
  banning repo-wide `fmt` / `lint --fix` / `check` / `build` for everyone, and it
  holds only while no two units share a file. Once they do, the answer is
  worktree isolation, never deferring a unit. Past two units it is usually the
  cheaper mode anyway, even counting the merge.
- **Verify the ground before dispatching**: a detached HEAD, a branch diverged
  from `main`, or a task written against code that is not in this checkout will
  waste every agent at once. Read `git status -sb` and `git log --oneline -1`,
  and resolve a few of the file/line references the task cites, first.
- **Unreferenced commits vanish quietly**: before moving HEAD, check
  `git branch --contains <sha>`. If nothing points at it, create a rescue branch
  and tell the user.
- **Verification is your job**: subagents overstate success. "Tests pass" in a
  report means nothing until you have seen the evidence (paste of test output,
  or your own read-only check).
