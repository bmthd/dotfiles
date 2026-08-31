# /dotfiles pr — リポジトリを変更して PR を作る

対象を `github.com/bmthd/dotfiles` に固定した `pr-anywhere` スキルの短縮形。
リポジトリがチェックアウトされていない端末を含め、どこからでも動く。

`pr-anywhere` に忠実に従う。ただし3点だけ変える。

- **`args` からリポジトリを読み取らない。** 対象は常に `bmthd/dotfiles` であり、
  `pr` の後ろは全部が変更内容。何も続かなければ何を変えるか聞く
- push の前に GitHub アカウントを下記のとおり確認する
- 下の編集メモを適用する

`pr-anywhere` は [`bmthd/skills`](https://github.com/bmthd/skills) にあり、
`setup:skills` の mise タスクがこのスキルと一緒に入れる。無ければ
`npx skills add bmthd/skills -s pr-anywhere -y -g -a claude-code` で入れる。

## push 前にアカウントを確認する

このリポジトリは個人のものだが、入っている端末はそうとは限らない。会社の端末では
`gh` は会社アカウントでサインインしており、push はそのアカウントを担いでいく。この
取り違えは見た目の問題でも、後から取り消せるものでもない。会社の身元が個人リポジトリ
上の公開された作者記録になり、そのアカウントはここに write 権限を持たないので `gh` は
まず fork して同じ PR に辿り着く。結果、会社アカウントの下に PR より長く残る fork が
できる。

だから **最初の push の前に** — まだ何も公開されていない最後の地点で — PR を開くこと
になるアカウントを読む:

```bash
gh api user --jq .login
```

- `bmthd` — 作者本人のアカウント。確認を挟まず進む
- それ以外の login — そこで止める。どのアカウントかをユーザーに伝え、そのアカウントで
  push し PR を作ってよいか明示的な確認を取る。回答が無いうちは push しない。作らな
  かった PR に取り下げは要らない
- コマンド自体が失敗した (`gh` が無い、未認証、ネットワーク無し) — 許可ではなく不一致
  として扱い、コマンドの出力を報告して同じ確認を取る。読めなかったアカウントは一致した
  アカウントではない

判定に `gh api user` を使うのは、これが `gh` が実際に振る舞うアカウント — 環境の
`GH_TOKEN` に上書きされたものも含めて — を名指しするから。`gh auth status` は複数
アカウントを並べるだけでどれが効くかを決めず、`git config user.email` はコミットの
author であって PR を開くアカウントではない。会社の端末ではこの 2 つは普通にずれる。

## 編集メモ

先に [SKILL.ja.md](SKILL.ja.md) のリポジトリ前提知識を読むこと。加えて:

- **サードパーティのスキルを追加するとき**: スキルをこのリポジトリにコピーするのではなく、
  [`.dotfiles/setup/skills.sh`](../../../.dotfiles/setup/skills.sh) に `install_skills` の
  行を足す。gist も `.git` の clone URL を使えば動く — ページ URL が失敗する理由は
  `japanese-tech-writing` の行を参照
- **セットアップタスクの中身を変えるとき**は `.mise.toml` ではなく
  `.dotfiles/setup/<name>.sh` を編集する。`.mise.toml` のタスクはスクリプトへの 1 行の
  委譲であり、そのまま保つ。タスクを *新設* するときは同じコミットで 3 つ必要 —
  スクリプト、タスク、そして端末にそれを届ける `setup:scripts` の `SCRIPTS=(...)` への
  スクリプト名の追加。3 つとも `bash tests/setup-facade-test.sh` が検査する
- **`.mise.toml` やシェルスクリプトを編集したら**、config がパースでき、スクリプトが
  bash と zsh の両方で ShellCheck をクリアしている必要がある。push 前にローカルで CI と
  同じものを流す:

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
