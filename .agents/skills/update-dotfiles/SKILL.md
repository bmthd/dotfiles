---
name: update-dotfiles
description: Use when the user wants to modify the bmthd/dotfiles repository (skills, install.sh, mise tools, shellrc, docs) and open a PR from ANY terminal, even one where the repo is not checked out. Clones via ghq if absent, always branches off fresh main, and opens a PR. Invoke as /update-dotfiles <change>.
argument-hint: <change to make>
---

# Update Dotfiles

Make a change to the `bmthd/dotfiles` repository and open a pull request, from any
terminal. Always works in the ghq-managed clone so behaviour is identical everywhere
and never disturbs whatever checkout you happen to be sitting in.

Repository: `github.com/bmthd/dotfiles`

## Steps (follow strictly)

### 1. Get the change to make

Read the requested change from `args`. If empty, ask the user what to change.

### 2. Preflight: gh auth and ghq

```bash
# GitHub CLI must be authenticated (needed for the PR)
gh auth status
```

If `gh auth status` fails, STOP and tell the user to run `! gh auth login`, then wait.

```bash
# Ensure ghq is installed; install via mise if missing
command -v ghq || mise use -g ghq@latest
```

If `mise use -g ghq@latest` fails to resolve, fall back to `mise use -g ubi:x-motemen/ghq`.

### 3. Get (clone or update) the repository

```bash
# Clones if absent, fast-forwards if already present (idempotent)
ghq get -u github.com/bmthd/dotfiles

# Resolve the absolute path and enter it
repo="$(ghq list --full-path --exact github.com/bmthd/dotfiles)"
cd "$repo"
```

### 4. Sync main and create a branch

Always branch off fresh `main` — never edit `main` directly, never push to `main`.

```bash
git switch main
git pull --ff-only
git switch -c "<type>/<slug>"
```

- `<type>`: `feat` / `fix` / `refactor` / `docs` / `chore` (match the change)
- `<slug>`: short kebab-case summary, e.g. `feat/add-ripgrep`, `fix/install-typo`

If the branch already exists from a prior run, pick a new slug (append `-2`, etc.).

### 5. Apply the edit

Make the change the user requested using the normal edit tools. Keep it focused —
one logical change per PR. For skill edits, the source of truth is
`.agents/skills/<name>/SKILL.md` (install.sh distributes it to `~/.claude/skills`
and `~/.config/opencode/skills`).

### 6. Commit

Follow the repo's Conventional Commits style (see `git log`). 

```bash
git add -A
git commit -m "<type>: <summary>"
```

### 7. Push and open the PR

```bash
git push -u origin "<branch>"
gh pr create --fill --base main
```

Use `--fill` or pass an explicit `--title` / `--body` summarising the change.
bmthd owns the repo, so push directly to an origin branch — no fork.

### 8. Report

Output the PR URL returned by `gh pr create`.

## Gotchas

- **gh not authenticated**: step 7 fails cryptically. Always verify with `gh auth status` in step 2 first.
- **Never touch the current checkout**: even if invoked from inside a dotfiles checkout, work in the ghq clone. This keeps behaviour identical on every terminal and avoids disturbing uncommitted work.
- **`command -v ghq` is checked by exit code**: `|| mise use ...` only installs when truly missing.
- **`git pull --ff-only`**: fails loudly if the local clone diverged from origin (e.g. leftover commits on main). If it fails, `git reset --hard origin/main` after confirming there is nothing to keep.
- **Branch already exists**: `git switch -c` fails. Reuse it (`git switch <branch>`) only if it is yours and clean, otherwise choose a new slug.