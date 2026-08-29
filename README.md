# dotfiles

English | [日本語](README.ja.md)

Dotfiles for setting up a development machine.
One command installs the CLI toolchain and configures Claude Code, Codex, OpenCode, and Cursor.

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

The setup can be re-run at any time as a mise task.

```bash
mise run setup   # full setup
mise tasks       # list the individual tasks
```

## Update

Interactive shells check `main` once a day.
If there are commits newer than the revision recorded at install time, you get a notice — nothing updates itself.

The notice lists the subjects of the commits in that range, newest first, up to five.
`main` only ever takes squash merges, so one subject line is one PR.
Subjects come from GitHub's compare API; when that call cannot be made — offline, rate limited, `jq` not yet on PATH — the notice still appears, just with the revision range alone.

Update with `/dotfiles apply`.
It diffs against the installed revision and separates what to pull in from what to keep local ([`.agents/skills/dotfiles`](.agents/skills/dotfiles/SKILL.md)).
The skill is not Claude Code specific: it goes to every agent `mise run setup:skills` targets.

Re-running `install.sh` also updates the machine, but it overwrites `~/.config/mise/config.toml` and friends with whatever is on the remote — losing pinned versions, machine-local tools, and hand-edited settings.

Skills update with `npx skills update`. The Markdown it fetches goes straight into an agent's context, so review the diff before running it.

## Layout

All of the setup logic lives in mise.

| File | Role |
| --- | --- |
| [`install.sh`](install.sh) | Bootstrap only: install mise, place the config files, wire up the shell |
| [`.mise.toml`](.mise.toml) | Tool definitions (`[tools]`) and setup tasks (`[tasks]`), installed as the global config |
| [`mise.lock`](mise.lock) | The versions and checksums that actually get installed |
| [`.agents/skills`](.agents/skills) | Skills specific to this repository; the general-purpose ones live in [bmthd/skills](https://github.com/bmthd/skills) |
| [`renovate.json`](renovate.json) | Update policy for GitHub Actions PRs |

Tool versions move when the daily [`bump-tools.yml`](.github/workflows/bump-tools.yml) advances `mise.lock`, not through `mise upgrade`.
To get ahead locally: `mise lock --bump --minimum-release-age 2d --global`.

This version management, together with the npm registry proxy, doubles as the supply-chain defense.
How it works, and the one-time setup for `bump-tools.yml`, are in [docs/supply-chain.md](docs/supply-chain.md).

## License

MIT
