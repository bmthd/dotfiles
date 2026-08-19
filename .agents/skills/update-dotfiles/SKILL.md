---
name: update-dotfiles
description: Use when the user wants to modify the bmthd/dotfiles repository (mise tools, install.sh, docs, the skills that still live here) and open a PR from ANY terminal, even one where the repo is not checked out. Thin wrapper over update-repo. Invoke as /update-dotfiles <change>.
argument-hint: <change to make>
---

# Update Dotfiles

Shorthand for the `update-repo` skill with the target fixed to
`github.com/bmthd/dotfiles`.

Follow `update-repo` exactly, with two adjustments:

- **Do not parse a repository out of `args`.** The target is always
  `bmthd/dotfiles`; the whole of `args` is the change to make. If `args` is empty,
  ask the user what to change.
- Apply the repository notes below when editing.

`update-repo` lives in [`bmthd/skills`](https://github.com/bmthd/skills) and the
`setup:skills` mise task installs it alongside this skill. If it is missing, install
it with `npx skills add bmthd/skills -s update-repo -y -g -a claude-code`.

## Repository notes

- **Most skills are no longer here.** The portable ones moved to `bmthd/skills` —
  change them there. What remains under `.agents/skills/` is `update-dotfiles`
  itself and `cognitive-rhythm-writing`, a vendored gist.
- **Setup logic lives in `.mise.toml`**, not `install.sh`. `install.sh` is only a
  bootstrapper (install mise → place the config → `mise install` → `mise run setup`).
  Changes to tools, environment, or setup steps belong in `.mise.toml`.
- **CI runs `mise ls`, `mise tasks ls`, ShellCheck, `bash -n` and `zsh -n`.** Editing
  `.mise.toml` or any shell script means the config must still parse and the scripts
  must stay ShellCheck-clean under both shells.
- **Adding a third-party skill**: add an `install_skills` line to the `setup:skills`
  task rather than copying the skill into this repo. Gists work too, via their `.git`
  clone URL — see the `japanese-tech-writing` line for the reason the page URL fails.
