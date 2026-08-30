# dotfiles

English | [日本語](README.ja.md)

Dotfiles for setting up development machines and keeping them that way.
One command installs the CLI toolchain and configures Claude Code, Codex, OpenCode, and Cursor.

## Why

Setting up a new machine is the easy half.
The harder half is keeping several of them — work, personal, a host, a VPS, a throwaway sandbox — in a state worth trusting months later, without a human holding in their head what is installed where, what has gone stale, and where the environments have drifted apart.
Updating is rarely difficult; remembering that something is due is what gets skipped.

So the goals are:

- **Continuous maintenance, not just first-time setup.** Automating the initial install is the smaller half of the problem; the environments that already exist have to stay maintainable for years.
- **Updates that do not depend on memory.** Whether an update exists is detected, not recalled. The machine says so; the human decides when to act on it.
- **Reproducibility across machines.** No machine chases upstream on its own. Versions are resolved once, centrally, and each machine follows that resolved state through Git and a lockfile — so two machines updated a week apart still land on the same thing.
- **Frequent updates without blind trust.** Raising the update frequency must not amount to trusting every new upstream release on sight. Staying current and staying deliberate is one tradeoff, not two independent goals.

The mechanisms below — a lockfile, checksums, a release-age delay, immutable references, a registry proxy — are the current answer to those goals, not the goals themselves.

## Install

The installer detects the shell it is piped into and appends the mise activation to the matching config file (`~/.zshrc` or `~/.bashrc`).

```zsh
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | zsh
```

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

Afterwards, restart the shell or run `source ~/.zshrc` (`source ~/.bashrc` for bash) to put everything on `PATH`.

## What you get

- **CLI tools** — node, bun, pnpm, uv, gh, ghq, jq, wrangler, and more (see `[tools]` in [`.mise.toml`](.mise.toml))
- **Claude Code** — the binary itself, `settings.json` (merged into an existing one), and the status line
- **Agent skills** — the same set installed for Claude Code, OpenCode, and Cursor
- **Plugins** — Codex, plus the official plugins (TypeScript LSP)
- **npm registry** — routed through [Takumi Guard](https://npm.flatt.tech/), a proxy that refuses known-malicious packages
- **Global git hooks** — trust mise configs in new worktrees and pin staged GitHub Actions references before commit, while preserving repository hooks and partial staging ([`.dotfiles/git-hooks`](.dotfiles/git-hooks))

The setup can be re-run at any time as a mise task.

```bash
mise run setup   # full setup
mise tasks       # list the individual tasks
```

## Update

Interactive shells check `main` once a day — this repository and [`bmthd/skills`](https://github.com/bmthd/skills), the two whose contents this setup installs.
If either has commits newer than the revision recorded at install time, you get a notice — nothing updates itself.

Update with `/dotfiles apply`.
It diffs against the installed revision and separates what to pull in from what to keep local ([`.agents/skills/dotfiles`](.agents/skills/dotfiles/SKILL.md)), and reinstalls the skills on the way through.

When only the skills moved, `mise run setup:skills` is the entire update: skills hold no per-machine state, so there is nothing to merge.

Re-running `install.sh` also updates the machine, and still overwrites `~/.claude/settings.json` and `~/.claude/statusline.sh`.
The mise config is no longer among them: the repository's copy goes to `~/.config/mise/conf.d/10-dotfiles.toml`, and `~/.config/mise/config.toml` is left to the machine — mise loads it after `conf.d/`, so a pin or a machine-only tool written there overrides the repository's copy and survives every re-run.

A machine installed before that split still has the repository's copy in `config.toml`.
`install.sh` migrates it only when it can prove nothing was added locally — the file is identical either to the copy being installed or to the `.mise.toml` of the revision it was installed from.
Otherwise it leaves the file exactly where it is, so pins keep working, and says what to do (`/dotfiles apply`, or `DOTFILES_MIGRATE_MISE_CONFIG=1` to migrate anyway).

Third-party skill sources are deliberately not watched: they move on their own schedule, mostly for reasons unrelated to the skills installed from them. Update those with `npx skills update`. The Markdown it fetches goes straight into an agent's context, so review the diff before running it.

## Layout

All of the setup logic lives in mise.

| File | Role |
| --- | --- |
| [`install.sh`](install.sh) | Bootstrap only: install mise, place the config files, wire up the shell |
| [`.mise.toml`](.mise.toml) | Tool definitions (`[tools]`) and setup tasks (`[tasks]`), installed to `~/.config/mise/conf.d/10-dotfiles.toml` |
| [`mise.lock`](mise.lock) | The versions and checksums that actually get installed, installed to `~/.config/mise/mise.lock` |
| [`.agents/skills`](.agents/skills) | Skills specific to this repository; the general-purpose ones live in [bmthd/skills](https://github.com/bmthd/skills) |
| [`renovate.json`](renovate.json) | Update policy for GitHub Actions PRs |
| [`.githooks`](.githooks) | A repository pre-commit hook guarding the `[tools]` block; the global dispatcher runs pinact first and then forwards here |

Tool versions move when the daily [`bump-tools.yml`](.github/workflows/bump-tools.yml) advances `mise.lock`, not through `mise upgrade`.
To get ahead locally: `mise lock --bump --minimum-release-age 2d --global`.

How that resolve-centrally-and-follow structure doubles as the supply-chain defense, and the one-time setup for `bump-tools.yml`, are in [docs/supply-chain.md](docs/supply-chain.md).

## License

MIT
