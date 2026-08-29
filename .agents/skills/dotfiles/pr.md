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
  bash -n install.sh .dotfiles/update-notice.sh .claude/statusline.sh
  zsh -n install.sh
  shellcheck install.sh .claude/statusline.sh .dotfiles/update-notice.sh tests/*.sh
  bash tests/update-notice-test.sh && bash tests/statusline-test.sh
  mise ls >/dev/null && mise tasks ls >/dev/null
  ```

- **`mise ls` passing does not mean `.mise.toml` is correct.** A `[tools.xxx]`
  sub-table heading swallows every plain key that follows it into that tool's table,
  silently disabling the rest. Adding tools around an existing sub-table requires
  checking the parsed result, not just the exit code:

  ```bash
  python3 -c "import tomllib; print(list(tomllib.load(open('.mise.toml','rb'))['tools']))"
  ```

  Keep every plain `name = "version"` entry above the first `[tools.xxx]` heading.

- **Editing this skill**: keep each file and its `.ja.md` twin in sync in the same
  commit. Divergence is worse than no translation.
