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
  bash -n install.sh .dotfiles/update-notice.sh .claude/statusline.sh
  zsh -n install.sh
  shellcheck install.sh .claude/statusline.sh .dotfiles/update-notice.sh tests/*.sh
  bash tests/update-notice-test.sh && bash tests/statusline-test.sh
  mise ls >/dev/null && mise tasks ls >/dev/null
  ```

- **`mise ls` が通ることは `.mise.toml` が正しいことを意味しない。** `[tools.xxx]` の
  サブテーブル見出しは、それ以降の平坦なキーをすべて自分の子として吸い込み、後続の
  ツールを黙って無効化する。既存のサブテーブルの周辺にツールを足すときは、exit code
  ではなくパース結果を確認する:

  ```bash
  python3 -c "import tomllib; print(list(tomllib.load(open('.mise.toml','rb'))['tools']))"
  ```

  平坦な `name = "version"` の行は、最初の `[tools.xxx]` 見出しより前にまとめて置く

- **このスキル自体を編集するとき**: 各ファイルと `.ja.md` の対を同じコミットで揃える。
  食い違った翻訳は翻訳が無いより悪い
