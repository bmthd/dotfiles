# /dotfiles pr — change the repository and open a PR

Shorthand for the `pr-anywhere` skill with the target fixed to
`github.com/bmthd/dotfiles`. Works from any terminal, including one where the
repository is not checked out.

Follow `pr-anywhere` exactly, with two adjustments:

- **Do not parse a repository out of `args`.** The target is always `bmthd/dotfiles`;
  everything after `pr` is the change to make. If nothing follows, ask the user what
  to change.
- Apply the editing notes below.

`pr-anywhere` lives in [`bmthd/skills`](https://github.com/bmthd/skills) and the
`setup:skills` mise task installs it alongside this skill. If it is missing, install it
with `npx skills add bmthd/skills -s pr-anywhere -y -g -a claude-code`.

## Editing notes

Read the repository facts in [SKILL.md](SKILL.md) first. In addition:

- **Adding a third-party skill**: add an `install_skills` line to the `setup:skills`
  task rather than copying the skill into this repository. Gists work too, via their
  `.git` clone URL — see the `japanese-tech-writing` line for why the page URL fails.
- **Editing `.mise.toml` or any shell script** means the config must still parse and
  the scripts must stay ShellCheck-clean under both bash and zsh. Run the CI checks
  locally before pushing:

  ```bash
  bash -n install.sh .dotfiles/update-notice.sh .claude/statusline.sh \
    .dotfiles/git-hooks/dispatch .dotfiles/git-hooks/install.sh
  zsh -n install.sh
  shellcheck install.sh .claude/statusline.sh .dotfiles/update-notice.sh \
    .dotfiles/git-hooks/* .githooks/pre-commit tests/*.sh
  bash tests/update-notice-test.sh && bash tests/statusline-test.sh
  bash tests/mise-pins-test.sh && bash tests/install-order-test.sh && bash tests/git-hooks-test.sh
  mise ls >/dev/null && mise tasks ls >/dev/null
  ```

- **`mise ls` passing does not mean `.mise.toml` is correct.** Every entry in
  `[tools]` is a single-line inline table — `node = { version = "latest" }` — and has
  to stay one, including a tool whose only option is `version`. Two ways that breaks,
  both silent: a `[tools.<name>]` sub-table ends the `[tools]` table, so any bare key
  after one becomes a key of *that tool* instead of a new tool; and `mise fmt` splits
  an inline table containing an array across lines, producing TOML 1.1 syntax that
  mise reads but no TOML 1.0 parser does. **Never run `mise fmt` on this file.**
  `bash tests/mise-pins-test.sh` catches both — it is in the check list above, runs in
  CI, and is this repository's pre-commit hook, which cloning does not enable (see the
  header of [`.githooks/pre-commit`](../../../.githooks/pre-commit)).

- **Editing this skill**: keep each file and its `.ja.md` twin in sync in the same
  commit. Divergence is worse than no translation.
