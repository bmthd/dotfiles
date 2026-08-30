# dotfiles

[English](README.md) | 日本語

開発マシンに環境を入れ、そのまま維持し続けるための dotfiles。
コマンド 1 本で CLI ツール一式と、Claude Code / Codex / OpenCode / Cursor の設定が揃います。

## Why

新しいマシンを立ち上げるのは簡単な方の半分です。
難しいのは、仕事用・プライベート用・ホスト・VPS・使い捨ての検証環境といった複数のマシンを、数か月後も信用できる状態に保つことです。
どこに何が入っていて、何が古くなっていて、環境間でどう食い違っているかを、人間が覚えていなくても済むようにしたい。
更新作業そのものが難しいことは稀で、放置されるのは「そろそろ更新しないと」と思い出す側です。

そのため、次のことを重視しています。

- **初回セットアップだけでなく、継続的な維持** — 最初の導入を自動化するのは問題の小さい方の半分で、すでにある環境を何年も維持できることの方が本題です。
- **記憶に依存しない更新** — 更新があるかどうかは、思い出すのではなく検出します。マシンが知らせ、人間はいつ適用するかだけを決めます。
- **環境間の再現性** — 各マシンが個別に upstream を追いかけることはしません。バージョンは中央で一度だけ解決し、各マシンは Git と lockfile を通してその解決済みの状態へ追従します。1 週間ずれて更新した 2 台でも、行き着く先は同じです。
- **更新しやすさと、無条件に信用しないこと** — 更新頻度を上げることが、新しい upstream release を見た瞬間に信用することになってはいけません。最新に追従することと慎重であることは、2 つの独立した目標ではなく 1 つのトレードオフです。

以下に出てくる lockfile、checksum、release age、immutable reference、registry proxy といった仕組みは、この目標に対する現時点の答えであって、目標そのものではありません。

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
- **グローバル git フック** — 新しい worktree の mise config を trust し、repository hook と部分 stage を維持したまま、commit 前に staged GitHub Actions 参照を pin する ([`.dotfiles/git-hooks`](.dotfiles/git-hooks))

セットアップはいつでも mise タスクとして再実行できます。

```bash
mise run setup   # フルセットアップ
mise tasks       # 個別のタスク一覧
```

## Update

対話シェルの起動時に、1 日 1 回 `main` を確認します。
見ているのは、このリポジトリと [`bmthd/skills`](https://github.com/bmthd/skills) の 2 つ。どちらもこのセットアップが中身をインストールしているものです。
インストール時のリビジョンより新しいコミットがあれば通知しますが、自動更新はしません。

更新は `/dotfiles apply` を使ってください。
差分を見て、取り込む変更とローカルに残す差分を切り分けてから適用します（[`.agents/skills/dotfiles`](.agents/skills/dotfiles/SKILL.ja.md)）。
途中でスキルも入れ直すので、両方まとめて片付きます。

スキルだけが動いていたときは `mise run setup:skills` で終わりです。
スキルは端末固有の設定を持たないので、マージするものがありません。

`install.sh` の再実行でも更新できます。いまも上書きされるのは `~/.claude/settings.json` と `~/.claude/statusline.sh` です。
mise の設定はもう含まれません。リポジトリ側のコピーは `~/.config/mise/conf.d/10-dotfiles.toml` に置かれ、`~/.config/mise/config.toml` は端末側に開けてあります。mise は `conf.d/` の後にこちらを読むので、ここに書いたピン留めや端末専用ツールはリポジトリ側を上書きし、再実行しても残ります。

この分離より前に入れた端末には、まだ `config.toml` にリポジトリのコピーが残っています。
`install.sh` がこれを移行するのは、ローカルで何も足されていないと証明できるときだけです（配置しようとしているコピーと同一か、インストール元リビジョンの `.mise.toml` と同一か）。
それ以外はファイルをその場に残すので、ピン留めは効いたままです。そのうえで次にすべきこと（`/dotfiles apply`、または移行を強行する `DOTFILES_MIGRATE_MISE_CONFIG=1`）を表示します。

サードパーティのスキルソースは、あえて監視していません。
それぞれ独自のペースで動いていて、その多くはここに入れているスキルとは関係のない変更だからです。
これらの更新は `npx skills update` です。取得される Markdown はエージェントのコンテキストに直接入るので、内容を確認してから実行してください。

## 構成

セットアップのロジックはすべて mise に集約されています。

| ファイル | 役割 |
| --- | --- |
| [`install.sh`](install.sh) | ブートストラップのみ。mise の導入、設定ファイルの配置、シェル連携の追記 |
| [`.mise.toml`](.mise.toml) | ツール定義 (`[tools]`) とセットアップタスク (`[tasks]`)。`~/.config/mise/conf.d/10-dotfiles.toml` に配置される |
| [`mise.lock`](mise.lock) | 実際に入るバージョンとチェックサム。`~/.config/mise/mise.lock` に配置される |
| [`.agents/skills`](.agents/skills) | このリポジトリ専用のスキル。汎用のものは [bmthd/skills](https://github.com/bmthd/skills) に分離 |
| [`renovate.json`](renovate.json) | GitHub Actions の更新 PR の方針 |
| [`.githooks`](.githooks) | `[tools]` を守る repository 固有の pre-commit フック。global dispatcher は先に pinact を実行してからここへ処理を渡す |

ツールのバージョンは `mise upgrade` ではなく、毎日走る [`bump-tools.yml`](.github/workflows/bump-tools.yml) が `mise.lock` を進めることで上がります。
手元で先に進めたい場合は `mise lock --bump --minimum-release-age 2d --global`。

中央で解決して各マシンが追従するこの構造がサプライチェーン対策を兼ねる仕組みと、`bump-tools.yml` の初回セットアップ手順は [docs/supply-chain.ja.md](docs/supply-chain.ja.md) に分けてあります。

## License

MIT
