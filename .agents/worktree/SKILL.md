---
name: worktree
description: Create a new git branch and worktree at ../{repo}.worktrees/{slug}, then open it in VS Code. Use when the user wants to start isolated work on a new branch without switching the main checkout. Invoke as /worktree <branch-name>.
argument-hint: <branch-name>
---

# Worktree

Create a new branch and worktree from the specified branch name, then open it in VS Code.

## Steps (follow strictly)

### 1. Validate arguments

Get the branch name from `args`. If no branch name is provided, ask the user.

### 2. Get repository information

```bash
# Get the repository root
git rev-parse --show-toplevel

# Get the repository name (directory name)
basename "$(git rev-parse --show-toplevel)"
```

### 3. Compute the slug

Generate a worktree directory name (slug) from the branch name.

- Replace `/` with `-`
- Replace other special characters (spaces, `:`, etc.) with `-`

Example: `feature/add-button` -> `feature-add-button`

### 4. Determine the worktree path

```
{repo_root}/../{repo_name}.worktrees/{slug}
```

Example: if the repository is at `/home/user/yamada-ui`
-> `/home/user/yamada-ui.worktrees/feature-add-button`

### 5. Check branch existence and create the worktree

Choose the command based on the branch state.

```bash
# Check if branch exists locally
git branch --list "{branch_name}"

# Check if branch exists on remote
git ls-remote --heads origin "{branch_name}"
```

| Local  | Remote | Command |
|--------|--------|---------|
| No     | No     | `git worktree add "{path}" -b "{branch}"` |
| No     | Yes    | `git fetch origin "{branch}" && git worktree add "{path}" --track -b "{branch}" "origin/{branch}"` |
| Yes    | -      | `git worktree add "{path}" "{branch}"` |

- **Neither local nor remote**: create a new branch with `-b`
- **Remote only**: `git fetch` first, then create as a tracking branch with `--track -b`
- **Local exists**: check out the existing branch without `-b` (regardless of remote state)

### 6. Open in VS Code

```bash
code "{worktree_path}"
```

### 7. Report completion

Tell the user the worktree path and branch name that were created.

## Gotchas

- **Worktree path already exists**: `git worktree add` will fail. Confirm with the user before running `rm -rf`, or use a different slug.
- **No need to get the repo name from remote URL**: `basename $(git rev-parse --show-toplevel)` is sufficient.
- **Use absolute paths, not relative**: always pass absolute paths to `git worktree add`.
- **`git ls-remote` is checked by output, not exit code**: determine "branch does not exist on remote" by whether stdout is empty, not by the exit code.
