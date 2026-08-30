---
name: dotfiles
description: bmthd/dotfiles のセットアップを扱うときに使う。リポジトリ自体 (mise のツール、install.sh、ドキュメント、そこに残るスキル) を変更して PR を出す場合と、シェルが「dotfiles の更新があります」と表示した後にこの端末へ更新を適用する場合の両方。/dotfiles pr <変更内容> または /dotfiles apply として呼び出す。
argument-hint: pr <変更内容> | apply
---

# Dotfiles

[`bmthd/dotfiles`](https://github.com/bmthd/dotfiles) に対する2方向の作業。
向きが逆なので混同してはいけない。`pr` は全端末に効くリポジトリを変更し、
`apply` はこの端末をリポジトリに合わせる。

| サブコマンド | 向き | 参照 |
|---|---|---|
| `pr <変更内容>` | リポジトリ ← 変更を PR として提出 | [pr.ja.md](pr.ja.md) |
| `apply` | この端末 ← リポジトリ | [apply.ja.md](apply.ja.md) |

**何かする前に必ずサブコマンドのファイルを読む。** どちらの手順も詳細で、
即興で進めて安全なものではない。

## 振り分け

- `args` が `pr` で始まる — 残りが変更内容。何も続かなければ何を変えるか聞く
- `args` が `apply` で始まる (または空で、更新通知への反応として呼ばれた) — apply の手順を読む
- どちらでもなく意図が不明なとき: どちらか聞く。カレントディレクトリから推測しない。
  dotfiles のチェックアウト内にいることは `pr` を望んでいる証拠にならない

## リポジトリの前提知識

両方のサブコマンドがこれに依存する。

- **セットアップのロジックは `.mise.toml` にある**。`install.sh` ではない。
  `install.sh` はブートストラップのみ (mise を入れる → config を配置する →
  `mise install` → `mise run setup`)。ツール・環境・セットアップ手順の変更は
  `.mise.toml` に入れる
- **`.mise.toml` は `~/.config/mise/conf.d/10-dotfiles.toml` に配置される**。mise が
  グローバル設定の一部として読むため、タスクはどのディレクトリからでも実行できる。
  `~/.config/mise/config.toml` は端末側に開けてあり、conf.d より優先される。
  この配置（両方の配置先と、移行前のコピーの見分け方）は
  [`.dotfiles/mise-layout.sh`](../../../.dotfiles/mise-layout.sh) に一度だけ定義され、
  `install.sh` と `.dotfiles/apply.sh` の両方がそれを読む。配置する側にパスを
  書き直さないこと
- **ほとんどのスキルはこのリポジトリには無い**。汎用のものは
  [`bmthd/skills`](https://github.com/bmthd/skills) に移した。`.agents/skills/` に残るのは
  このリポジトリに対してしか意味を持たない `dotfiles` スキルだけ。サードパーティのスキルは
  vendoring せず `setup:skills` タスクが upstream から入れる
- **CI (`.github/workflows/quality.yml`) が実行するのは** `mise ls`、`mise tasks ls`、
  ShellCheck、`bash -n`、`zsh -n`、`tests/` 配下のスクリプト
