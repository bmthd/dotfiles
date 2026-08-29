# dotfiles

[English](README.md) | 日本語

新しいマシンに開発環境を入れるための dotfiles。
コマンド 1 本で CLI ツール一式と、Claude Code / Codex / OpenCode / Cursor の設定が揃います。

## Install

パイプ先のシェルを検出して、対応する設定ファイル (`~/.zshrc` / `~/.bashrc`) に mise の有効化を追記します。

```zsh
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | zsh
```

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

終わったらシェルを再起動するか、`source ~/.zshrc`（bash なら `source ~/.bashrc`）で PATH が通ります。

## 入るもの

- **CLI ツール** — node, bun, pnpm, uv, gh, ghq, jq, wrangler など（一覧は [`.mise.toml`](.mise.toml) の `[tools]`）
- **Claude Code** — 本体、`settings.json`（既存があればマージ）、ステータスライン
- **エージェントスキル** — Claude Code / OpenCode / Cursor の 3 つに同じものを導入
- **プラグイン** — Codex、および公式プラグイン (TypeScript LSP)
- **npm レジストリ** — マルウェアを遮断する [Takumi Guard](https://npm.flatt.tech/) プロキシ経由に変更

セットアップはいつでも mise タスクとして再実行できます。

```bash
mise run setup   # フルセットアップ
mise tasks       # 個別のタスク一覧
```

## Update

対話シェルの起動時に、1 日 1 回 `main` を確認します。
インストール時のリビジョンより新しいコミットがあれば通知しますが、自動更新はしません。

通知には、そのリビジョン間に入ったコミットの件名が新しい順に最大 5 件並びます。
`main` はスカッシュマージしか受け付けないので、件名 1 行が PR 1 本にそのまま対応します。
件名は GitHub の compare API から取ります。取得に失敗しても（オフライン、レート制限、`jq` が PATH に無いなど）通知そのものは出ます。リビジョンの範囲だけになります。

更新は `/dotfiles apply` を使ってください。
差分を見て、取り込む変更とローカルに残す差分を切り分けてから適用します（[`.agents/skills/dotfiles`](.agents/skills/dotfiles/SKILL.ja.md)）。
このスキルは Claude Code に限らず、`mise run setup:skills` が対象にしているエージェントすべてに入ります。

`install.sh` の再実行でも更新できますが、こちらは `~/.config/mise/config.toml` などをリモートの内容で上書きします。
端末ごとに固定したバージョンや、その端末だけのツール・設定がある場合は失われます。

スキルの更新は `npx skills update` です。取得される Markdown はエージェントのコンテキストに直接入るので、内容を確認してから実行してください。

## 構成

セットアップのロジックはすべて mise に集約されています。

| ファイル | 役割 |
| --- | --- |
| [`install.sh`](install.sh) | ブートストラップのみ。mise の導入、設定ファイルの配置、シェル連携の追記 |
| [`.mise.toml`](.mise.toml) | ツール定義 (`[tools]`) とセットアップタスク (`[tasks]`)。グローバル設定として配置される |
| [`mise.lock`](mise.lock) | 実際に入るバージョンとチェックサム |
| [`.agents/skills`](.agents/skills) | このリポジトリ専用のスキル。汎用のものは [bmthd/skills](https://github.com/bmthd/skills) に分離 |
| [`renovate.json`](renovate.json) | GitHub Actions の更新 PR の方針 |

ツールのバージョンは `mise upgrade` ではなく、毎日走る [`bump-tools.yml`](.github/workflows/bump-tools.yml) が `mise.lock` を進めることで上がります。
手元で先に進めたい場合は `mise lock --bump --minimum-release-age 2d --global`。

このバージョン管理は、npm レジストリのプロキシと合わせてサプライチェーン対策を兼ねています。
仕組みと、`bump-tools.yml` の初回セットアップ手順は [docs/supply-chain.ja.md](docs/supply-chain.ja.md) に分けてあります。

## License

MIT
