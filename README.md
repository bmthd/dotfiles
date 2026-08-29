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
- [`mise.lock`](mise.lock) — 実際にインストールされるバージョンとチェックサム。
  `install.sh` が `~/.config/mise/mise.lock` に配置します。
- [`renovate.json`](renovate.json) — GitHub Actions の更新 PR の方針。

## サプライチェーン対策

`[tools]` の宣言は `latest` ですが、`latest` がそのまま入るわけではありません。
mise は fuzzy な指定よりロックファイルのバージョンを優先するため、実際に入るのは
`mise.lock` が決めたバージョンです。この 2 つの組み合わせが対策の中心にあります。

ロックファイルは
[`bump-tools.yml`](.github/workflows/bump-tools.yml) が毎日進めます。

```bash
mise lock --bump --minimum-release-age 2d
```

`--minimum-release-age` は公開から 2 日経っていないリリースを候補から外します。
侵害されたリリースが取り込まれるのは publish 直後の数時間なので、この待機だけで
その時間帯を丸ごと回避できます。レビューではなくこのフラグが安全性を担保している
ため、PR は作らず main に直接コミットします。なお、このフラグは `latest` のような
fuzzy な指定にのみ効きます。バージョンをここで固定しない理由がこれです。

### bump-tools.yml のセットアップ（初回のみ）

main は ruleset `main-guardrails` で保護されており、`pull_request` ルールが直接
push を禁止しています。既定の `GITHUB_TOKEN` は bypass に登録できません
（GitHub Actions を bypass actor にできるのは Organization 所有のリポジトリだけで、
ここは User 所有のため）。GitHub App なら登録できるので、App のトークンを使います。

1. [GitHub App を作成](https://github.com/settings/apps/new)する。Repository
   permissions は **Contents: Read and write** のみ。Webhook は不要
2. 作成後、Client ID を控え、Private key を生成してダウンロードする
3. その App をこのリポジトリに install する
4. リポジトリの Secrets に登録する
   - `BUMP_APP_CLIENT_ID` — 手順 2 の Client ID
   - `BUMP_APP_PRIVATE_KEY` — ダウンロードした `.pem` の中身
5. Settings > Rules > `main-guardrails` の Bypass list に、作成した App を
   Integration として追加する

`workflow_dispatch` から手動実行して、push まで通ることを確認してください。

対策は 3 層に分かれ、それぞれ守る範囲が違います。

| 層 | 手段 | 守る範囲 |
| --- | --- | --- |
| バージョン | `mise.lock` + `--minimum-release-age 2d` | publish 直後の 2 日間 |
| 成果物 | `mise.lock` のチェックサム | 検証済みバージョンの差し替え・再 publish |
| パッケージ | `~/.npmrc` の [Takumi Guard](https://npm.flatt.tech/) プロキシ | npm 経由すべて。特にロックできない実行時の `npx ctx7@latest` / `npx skills add` |

ロックファイルは必須です。取得に失敗した場合 `install.sh` は中断します。`latest`
のまま `mise install` すると待機期間を迂回して最新版が入ってしまうためです。

CI ([`tests/mise-pins-test.sh`](tests/mise-pins-test.sh)) が、ロックされていない
ツールの混入を検出します。

プロキシが効くのは `~/.npmrc` を書いた時点以降だけなので、`install.sh` は
`mise install` より前に `mise run --skip-tools setup:npm-registry` を実行します。
`--skip-tools` を落とすと `mise run` 自体がツール一式を先に入れてしまい、順序が
逆転します。パッケージは問題なく入るため失敗が表に出ません
([`tests/install-order-test.sh`](tests/install-order-test.sh) が検出します)。

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

ツール本体のバージョンは `mise.lock` が決めるため、`mise upgrade` ではなく毎日の
`bump-tools.yml` が更新します。手元で先に進めたい場合は
`mise lock --bump --minimum-release-age 2d --global` を実行してください。

スキルの更新は `npx skills update` ですが、上記のとおり内容を確認してから実行して
ください。

ただし `install.sh` の再実行と `mise run setup` は、リモートの内容で
`~/.config/mise/config.toml` などを上書きします。端末ごとにピン留めしたバージョンや
その端末だけのツール、手で足した設定がある場合は、Claude Code で
`/dotfiles apply` を実行してください。インストール済みリビジョンとの差分を見て、
取り込む変更とローカルに残す差分を切り分けてから適用します
(スキル: [`.agents/skills/dotfiles`](.agents/skills/dotfiles/SKILL.ja.md))。

対話シェルの起動時には、1 日に 1 回まで dotfiles の `main` ブランチを確認します。
インストール時に記録した revision より新しいコミットがあれば通知しますが、自動更新はしません。
ロックファイルの更新も main へのコミットなので、ツールに更新があった日は通知が出ます。
通知された場合は、次のコマンドで更新できます。

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

ghq で clone を管理する場合は `ghq get -u github.com/bmthd/dotfiles` で更新できます。

## License

MIT
