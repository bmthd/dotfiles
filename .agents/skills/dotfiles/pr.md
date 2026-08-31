# /dotfiles pr — change the repository and open a PR

Shorthand for the `pr-anywhere` skill with the target fixed to
`github.com/bmthd/dotfiles`. Works from any terminal, including one where the
repository is not checked out.

Follow `pr-anywhere` exactly, with three adjustments:

- **Do not parse a repository out of `args`.** The target is always `bmthd/dotfiles`;
  everything after `pr` is the change to make. If nothing follows, ask the user what
  to change.
- Confirm the GitHub account before pushing, as below.
- Apply the editing notes below.

`pr-anywhere` lives in [`bmthd/skills`](https://github.com/bmthd/skills) and the
`setup:skills` mise task installs it alongside this skill. If it is missing, install it
with `npx skills add bmthd/skills -s pr-anywhere -y -g -a claude-code`.

## Confirm the account before pushing

This repository is personal, but the machines it is installed on are not: on a work
machine `gh` is signed in to a company account, and that account is the one a push
would carry. The mistake is not cosmetic and not undoable — the company identity
becomes a public authorship record on a personal repository, and since that account
has no write access here, `gh` reaches the same PR by forking first, leaving a fork
under the company account that outlives the PR.

So read the account that would open the PR **before the first push**, which is the
last point where nothing is public yet:

```bash
gh api user --jq .login
```

- `bmthd` — the author's own account. Proceed without asking.
- Any other login — stop. Tell the user which account it is and obtain explicit
  confirmation to push and open the PR as that account. Do not push while the
  question is unanswered; there is no PR to withdraw if it is never created.
- The command fails (`gh` absent, not authenticated, no network) — treat it as a
  mismatch, not as permission: report what the command said and ask the same
  question. An account that cannot be read is not a matching one.

`gh api user` is the check rather than the alternatives because it names the account
`gh` will actually act as, including one imposed by `GH_TOKEN` in the environment.
`gh auth status` can list several accounts without settling which one applies, and
`git config user.email` describes the commit author, not the account opening the PR —
on a work machine those two routinely differ.

## Editing notes

Read the repository facts in [SKILL.md](SKILL.md) first. In addition:

- **Adding a third-party skill**: add an `install_skills` line to
  [`.dotfiles/setup/skills.sh`](../../../.dotfiles/setup/skills.sh) rather than copying
  the skill into this repository. Gists work too, via their `.git` clone URL — see the
  `japanese-tech-writing` line for why the page URL fails.
- **Changing what a setup task does** means editing `.dotfiles/setup/<name>.sh`, not
  `.mise.toml`: a task there is a one-line delegation to its script and stays that way.
  A *new* task needs three things in the same commit — the script, the task, and the
  script's name in the `SCRIPTS=(...)` list of `setup:scripts`, which is what puts it on
  a machine. `bash tests/setup-facade-test.sh` checks all three.
- **Editing `.mise.toml` or any shell script** means the config must still parse and
  the scripts must stay ShellCheck-clean under both bash and zsh. Run the CI checks
  locally before pushing:

  ```bash
  bash -n install.sh .dotfiles/update-notice.sh .claude/statusline.sh \
    .dotfiles/git-hooks/dispatch .dotfiles/git-hooks/install.sh .dotfiles/setup/*.sh
  zsh -n install.sh
  shellcheck install.sh .claude/statusline.sh .dotfiles/update-notice.sh \
    .dotfiles/git-hooks/* .dotfiles/setup/*.sh .githooks/pre-commit tests/*.sh
  bash tests/update-notice-test.sh && bash tests/statusline-test.sh
  bash tests/mise-pins-test.sh && bash tests/install-order-test.sh && bash tests/git-hooks-test.sh
  bash tests/setup-facade-test.sh && bash tests/oci-plugin-test.sh && bash tests/revision-pinning-test.sh
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
