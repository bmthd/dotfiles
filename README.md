# Dotfiles

開発ツールの自動セットアップ用 dotfiles

## Install

利用しているシェルに合わせてインストールコマンドを選んでください。
パイプ先のシェル (`bash` / `zsh`) を検出し、対応する設定ファイル
(`~/.bashrc` / `~/.zshrc`) に mise の有効化を追記します。

### zsh を使っている場合

```zsh
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | zsh
```

### bash を使っている場合

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

インストール後はシェルを再起動するか、`source ~/.zshrc`（bash の場合は
`source ~/.bashrc`）を実行すると各ツールに PATH が通ります。

## 構成

セットアップのロジックはすべて mise に集約されています。

- [`install.sh`](install.sh) — ブートストラップのみ。mise のインストール、
  `.mise.toml` の `~/.config/mise/config.toml` への配置、シェル連携の追記を行い、
  残りは `mise install` と `mise run setup` に委譲します。
- [`.mise.toml`](.mise.toml) — ツール定義 (`[tools]`) とセットアップタスク
  (`[tasks]`)。グローバル設定として配置されるため、タスクはどのディレクトリ
  からでも実行できます。

## Update

セットアップはいつでも mise タスクとして再実行できます。

```bash
mise run setup           # フルセットアップ
mise run setup:claude    # Claude Code 本体・settings.json・ステータスライン
mise run setup:skills    # エージェントスキル (Claude Code / OpenCode / Cursor)
mise run setup:codex     # Claude Code 用 Codex プラグイン
```

ツール本体の更新は `mise upgrade`、スキルの更新は `npx skills update` で行えます。

## License

MIT
