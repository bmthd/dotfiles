# /dotfiles pr — リポジトリを変更して PR を作る

対象を `github.com/bmthd/dotfiles` に固定した `pr-anywhere` スキルの短縮形。
リポジトリがチェックアウトされていない端末を含め、どこからでも動く。

`pr-anywhere` に忠実に従う。ただし2点だけ変える。

- **`args` からリポジトリを読み取らない。** 対象は常に `bmthd/dotfiles` であり、
  `pr` の後ろは全部が変更内容。何も続かなければ何を変えるか聞く
- 下の編集メモを適用する

`pr-anywhere` は [`bmthd/skills`](https://github.com/bmthd/skills) にあり、
`setup:skills` の mise タスクがこのスキルと一緒に入れる。無ければ
`npx skills add bmthd/skills -s pr-anywhere -y -g -a claude-code` で入れる。

## 編集メモ

先に [SKILL.ja.md](SKILL.ja.md) のリポジトリ前提知識を読むこと。加えて:

- **サードパーティのスキルを追加するとき**: スキルをこのリポジトリにコピーするのではなく、
  `setup:skills` タスクに `install_skills` の行を足す。gist も `.git` の clone URL を使えば
  動く — ページ URL が失敗する理由は `japanese-tech-writing` の行を参照
- **`.mise.toml` やシェルスクリプトを編集したら**、config がパースでき、スクリプトが
  bash と zsh の両方で ShellCheck をクリアしている必要がある。push 前にローカルで CI と
  同じものを流す:

  ```bash
  bash -n install.sh .dotfiles/*.sh .claude/statusline.sh \
    .dotfiles/git-hooks/dispatch .dotfiles/git-hooks/install.sh
  zsh -n install.sh
  shellcheck install.sh .claude/statusline.sh .dotfiles/*.sh \
    .dotfiles/git-hooks/* .githooks/pre-commit tests/*.sh
  bash tests/update-notice-test.sh && bash tests/statusline-test.sh
  bash tests/mise-pins-test.sh && bash tests/install-order-test.sh && bash tests/git-hooks-test.sh
  bash tests/apply-test.sh && bash tests/skill-link-test.sh
  mise ls >/dev/null && mise tasks ls >/dev/null
  ```

- **`mise ls` が通ることは `.mise.toml` が正しいことを意味しない。** `[tools]` の各行は
  `version` しか持たないツールも含めて、すべて 1 行のインラインテーブルで書く
  (`node = { version = "latest" }`)。これが崩れる経路が 2 つあり、どちらも無言で壊れる。
  `[tools.<name>]` のサブテーブルは `[tools]` を終わらせるため、以降の平坦なキーは
  新しいツールではなくそのツールのキーになる。そして `mise fmt` は配列を含む
  インラインテーブルを改行で分解し、mise は読めるが TOML 1.0 パーサが読めない
  TOML 1.1 の構文にしてしまう。**このファイルに `mise fmt` をかけないこと。**
  どちらも `bash tests/mise-pins-test.sh` が検出する — 上のチェック一覧に含まれ、CI でも
  走り、このリポジトリの pre-commit フックでもある (clone しただけでは有効にならない。
  [`.githooks/pre-commit`](../../../.githooks/pre-commit) の冒頭を参照)

- **このスキル自体を編集するとき**: 各ファイルと `.ja.md` の対を同じコミットで揃える。
  食い違った翻訳は翻訳が無いより悪い
