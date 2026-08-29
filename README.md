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
- [`.agents/skills`](.agents/skills) — このリポジトリ専用のスキルのみ。汎用の
  スキルは [bmthd/skills](https://github.com/bmthd/skills) に分離しました
  (`npx skills add bmthd/skills`)。
- [`mise.lock`](mise.lock) — `[tools]` の各バージョンに対応するダウンロード URL
  とチェックサム。`install.sh` が `~/.config/mise/mise.lock` に配置します。
- [`renovate.json`](renovate.json) — 更新 PR の方針。

## サプライチェーン対策

ツールは `latest` ではなく厳密なバージョンで固定しています。新しいバージョンが
どのマシンに届くかを決めるのは上流の publish ではなく Renovate です。対策は 3 層
に分かれ、それぞれ守る範囲が違います。

| 層 | 手段 | 守る範囲 |
| --- | --- | --- |
| バージョン | `.mise.toml` のピン留め + Renovate の `minimumReleaseAge: 2 days` | publish 直後の 2 日間（侵害されたリリースが取り込まれる時間帯）を回避 |
| 成果物 | `mise.lock` のチェックサム | 検証済みバージョンの差し替え・再 publish。npm 以外の 9 ツールが対象 |
| パッケージ | `~/.npmrc` の [Takumi Guard](https://npm.flatt.tech/) プロキシ | npm 経由すべて。特にピン留めできない実行時の `npx ctx7@latest` / `npx skills add` |

Renovate の更新は週 1 回の PR にまとめています。ツールのバージョンを変更したら
`mise lock` を実行して `mise.lock` を更新してください。CI (`tests/mise-pins-test.sh`)
がピン留めの漏れとロックファイルのずれを検出します。

npm レジストリは環境変数ではなく `~/.npmrc` に書くため、プライベートレジストリを
使うプロジェクトはリポジトリ側の `.npmrc` で上書きできます。既に独自のレジストリが
設定されている場合、セットアップはそれを変更しません。

**スキルは対象外です。** `npx skills add` が取得する Markdown は各エージェントの
コンテキストに直接入るため、プロンプトインジェクションの経路になり得ますが、
skills CLI にリビジョン固定の手段がありません。`npx skills update` は差分を確認
してから実行してください。

## Update

セットアップはいつでも mise タスクとして再実行できます。

```bash
mise run setup           # フルセットアップ
mise run setup:npm-registry    # npm を Takumi Guard プロキシ経由にする
mise run setup:claude    # Claude Code 本体・settings.json・ステータスライン
mise run setup:skills    # エージェントスキル (Claude Code / OpenCode / Cursor)
mise run setup:codex     # Claude Code 用 Codex プラグイン
mise run setup:claude-plugins  # 公式プラグイン (TypeScript LSP)
```

ツール本体のバージョンは固定されているため、`mise upgrade` ではなく Renovate の
PR で更新します。手元で先に進めたい場合は `mise upgrade --bump` で `.mise.toml` の
ピンを書き換え、`mise lock` でロックファイルを追従させてください。

スキルの更新は `npx skills update` ですが、上記のとおり内容を確認してから実行して
ください。

対話シェルの起動時には、1 日に 1 回まで dotfiles の `main` ブランチを確認します。
インストール時に記録した revision より新しいコミットがあれば通知しますが、自動更新はしません。
通知された場合は、次のコマンドで更新できます。

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

ghq で clone を管理する場合は `ghq get -u github.com/bmthd/dotfiles` で更新できます。

## License

MIT
