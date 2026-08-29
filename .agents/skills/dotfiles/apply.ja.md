# /dotfiles apply — この端末に更新を適用する

`install.sh` と `mise run setup` は **リモートの内容でローカルを上書きする**前提で
書かれている。端末ごとの事情 (ピン留めしたバージョン、その端末だけのツール、手で足した
フック) はリポジトリ側に存在しないので、素直に再実行すると黙って消える。

ここでやるべきは、**上書きする前に「取り込む変更」と「守るローカル差分」を分離すること**。
差分を見ずに `install.sh` を流したら意味がない。

## 上書きハザード表

再実行で何が起きるか。ここが判断の全体像。

| 対象 | 素直に再実行すると | 扱い |
|---|---|---|
| `~/.config/mise/config.toml` | リポジトリの `.mise.toml` で **curl 全上書き** | **要 3-way マージ** (ステップ 4)。最大の危険地帯 |
| `~/.claude/settings.json` | `jq -s '.[0] * .[1]'` で deep merge、**衝突時はリモート優先**。配列 (`permissions.allow` 等) は連結ではなく**置換** | **要手動適用** (ステップ 5)。リポジトリ側に差分が無ければ触らない |
| `~/.claude/statusline.sh` | **curl 全上書き** | ローカル改変が無ければ上書きで可。あれば 3-way |
| `~/.config/dotfiles/update-notice.sh` | curl 全上書き | 端末固有の設定を持たないので上書きで可 |
| `~/.bashrc` / `~/.zshrc` | `grep` ガード付き追記 | 冪等。放置で可 |
| スキル / プラグイン | `npx skills add -g`、`claude plugin install` | 冪等。ただし `mise run` の `depends` に注意 (ステップ 6) |
| インストール済みツール | `mise install` はマージ後の config を読む | **config を守れてもツールが有効とは限らない**。ステップ 4 で確認する |

## 手順

### 1. 差分の基準 (共通祖先) を確保する

`~/.config/dotfiles/revision` のリビジョンを共通祖先にして、リポジトリの更新とローカル改変を
切り分ける。**この祖先オブジェクトが手に入るかどうかが手順全体の前提**なので最初に確定させる。

```bash
INSTALLED="$(cat ~/.config/dotfiles/revision 2>/dev/null)"
REPO="$(ghq root 2>/dev/null || echo ~/ghq)/github.com/bmthd/dotfiles"
ghq get -u github.com/bmthd/dotfiles || git clone https://github.com/bmthd/dotfiles "$REPO"
git -C "$REPO" fetch origin main
git -C "$REPO" cat-file -e "$INSTALLED^{commit}" 2>/dev/null && echo "BASE OK"
```

**`ghq get` と `fetch` の失敗を握り潰さない。** `ghq` は shim が PATH にあっても動かないことが
ある (`No version is set for shim: ghq`)。失敗したら `git clone` に切り替える。fetch が済んで
いないと古い `origin/main` を新しいと誤認して判断する。

**`BASE OK` が出ないときの分岐:**

- `main` が force-push (rebase) されると、**インストール済みリビジョンがリモートから消える**。
  `fatal: bad object` はこれ。`git fetch` の出力に `(forced update)` があれば確定
- 手元の別のチェックアウトにオブジェクトが残っていることがある。
  `git -C <候補> cat-file -e "$INSTALLED^{commit}"` で探し、見つかればそれを **読み取り専用で**
  `REPO` に使う (ブランチ切替・commit・push はしない)
- どこにも無い / revision ファイル自体が無い場合は **祖先なしモード**に落ちる。3-way は使えない。
  ローカルの各ファイルを `origin/main` と直接 diff し、**差分を一件も自動適用せず**、
  一件ずつ「リポジトリの更新か、この端末の改変か」をユーザーに確認して決める

祖先が取れたら、リポジトリ側が何を変えたかを見る。

```bash
git -C "$REPO" diff --stat "$INSTALLED" origin/main
```

### 2. ローカル差分を棚卸しする

「この端末で何が独自か」を、リポジトリの **インストール時点** の内容と比べて出す。
現在の `main` と比べるとリポジトリの更新とローカル改変が混ざり、更新を改変と誤認して捨てる。

```bash
git -C "$REPO" show "$INSTALLED:.mise.toml"           | diff - ~/.config/mise/config.toml
git -C "$REPO" show "$INSTALLED:.claude/statusline.sh" | diff - ~/.claude/statusline.sh
```

出てきた差分は一つずつ「なぜそうなっているか」をユーザーに確認する。ピン留めされた
バージョン、その端末専用のツール、無効化された設定は **事故ではなく意図**であることが多い。
消す前に必ず聞く。聞けない状況では **ローカルを残す側に倒し**、確認事項として最後の報告に残す。

### 3. バックアップを取る

適用前に必ず。復元コマンドをユーザーに伝えられる状態にしておく。

```bash
BK=~/.config/dotfiles/backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
cp ~/.config/mise/config.toml ~/.claude/settings.json ~/.claude/statusline.sh "$BK/" 2>/dev/null
```

### 4. mise config を 3-way マージする

curl での上書きは**しない**。作業ファイルはスクラッチ領域に置く (`$W`)。

```bash
git -C "$REPO" show "$INSTALLED:.mise.toml" > "$W/base"     # 共通の祖先
git -C "$REPO" show  "origin/main:.mise.toml" > "$W/theirs" # 新しいリポジトリ側
cp ~/.config/mise/config.toml                  "$W/ours"    # この端末
git merge-file -p "$W/ours" "$W/base" "$W/theirs" > "$W/merged"
```

衝突箇所には `<<<<<<<` マーカーが残る。**マーカーを残したまま配置しない** (mise が config を
読めなくなる)。衝突は一つずつ意味を見て解決する。

- ローカルがバージョンをピン留め、リポジトリが `latest` → ピン留めの理由を確認。理由が生きていれば残す
- リポジトリが新ツール / `depends` などを追加 → 取り込む
- ローカルが `[settings]` を変更 (例: `experimental = true`) → ローカルを残す
- リポジトリがツールを削除 → その端末で使っているなら残す。使っていなければ削除に従う

**マーカーが無くても取りこぼしは起こる。** 双方向に diff して、意図した通りか確認する。

```bash
diff "$W/ours" "$W/merged"    # リポジトリの更新が入ったか
diff "$W/theirs" "$W/merged"  # ローカル差分が残ったか
```

配置したら、**パースだけでなく中身を検証する**。`mise ls` の exit 0 は当てにならない。

```bash
mise ls --installed | awk '{print $1}' | sort > "$W/tools.before"   # 配置前に取っておく
cp "$W/merged" ~/.config/mise/config.toml
mise tasks ls >/dev/null || echo "!! config が壊れた。バックアップから戻す"
mise ls --installed | awk '{print $1}' | sort | diff "$W/tools.before" -
mise install
```

TOML としてパースできることと mise の設定として正しいことは別物。**config に書いたツールが
`mise ls` に現れているか**を確認する。`[tools.xxx]` のサブテーブル見出しは、それ以降の平坦な
キーを全部自分の子として吸い込むため、後続のツールが丸ごと無効化されうる。`mise install` が
「all tools are installed」と即答するのに `command -v` で見つからない、
`No version is set for shim: <tool>` が出る、といった症状はこれ。**マージのせいではなく
リポジトリ側の既存バグのことがある。** その場合は端末側で勝手に直さず、`/dotfiles pr` で報告する。

### 5. Claude Code の設定はリポジトリ差分だけを適用する

`~/.claude/settings.json` はコピーではなく**マージ結果**なので 3-way が効かない。
リポジトリ側が何を変えたかを見て、その変更**だけ**を手で入れる。

```bash
git -C "$REPO" diff "$INSTALLED" origin/main -- .claude/settings.json
```

**差分が無ければ何もしない** (このケースが多い)。差分があるときの原則:

- リポジトリが**追加**したキー / 権限エントリ → ローカルに追加する
- リポジトリが**変更**した値で、ローカルが同じキーを独自に持つ → ローカルを優先し、ユーザーに伝える
- `permissions.allow` などの配列 → 置換ではなく**和集合**にする。ローカルのエントリを落とさない
- 編集後は `jq . ~/.claude/settings.json >/dev/null` で JSON として妥当なことを確認する

`statusline.sh` はステップ 2 で差分が無ければ `origin/main` の内容にする。raw URL の curl では
なく fetch 済みの clone から取る (CDN の反映ラグを避けるため)。**実行ビットとテストを忘れない。**

```bash
git -C "$REPO" show origin/main:.claude/statusline.sh > ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
bash -n ~/.claude/statusline.sh && bash "$REPO/tests/statusline-test.sh"
```

ローカル改変があれば mise config と同じ 3-way マージで扱う。

### 6. 残りのタスクを流す

**`mise run setup:codex` と `mise run setup:claude-plugins` は `depends = ["setup:claude"]` を
持つ。** そのまま実行すると `setup:claude` が走り、`settings.json` が remote 優先の deep merge で
上書きされ、`permissions.allow` が置換される。ステップ 5 でやったことが台無しになる。
`--skip-deps` が必須。

```bash
mise run setup:skills
mise run --skip-deps setup:codex
mise run --skip-deps setup:claude-plugins
```

`mise run setup` (全部) と `mise run setup:claude` は **使わない**。

`npx skills update` は **`-g` が無いとプロジェクトスキルを見に行き、no-op で正常終了する**
(`No project skills to update.`)。このスキルが扱うのはグローバルスキルなので `-g` を付ける。
直前に `setup:skills` が全ソースを入れ直しているなら実質重複なので、省いてよい。

```bash
npx skills update -g -y   # 実行するなら -g
```

upstream から消えたスキルの削除警告が出ることがある。非対話モードでは削除されないので、
重複インストールが無いことだけ確認して先へ進む。

### 7. リビジョンを記録して報告する

ここを忘れると、次のシェル起動でまた「更新があります」と言われる。

```bash
git -C "$REPO" rev-parse origin/main > ~/.config/dotfiles/revision
```

`update-notice.sh` はステップ 1 の diff に含まれていたときだけ取り直せばよい。

```bash
git -C "$REPO" show origin/main:.dotfiles/update-notice.sh > ~/.config/dotfiles/update-notice.sh
```

通知が実際に止まったかを確認する。

```bash
rm -f ~/.config/dotfiles/last-update-check
bash -c 'source ~/.config/dotfiles/update-notice.sh; dotfiles_update_notice_check'  # 無出力なら解消
```

最後にユーザーへ報告する。**4 は省略しない** — 判断を代行した分の説明責任がここにある。

1. 取り込んだ変更
2. 意図的に残したローカル差分とその理由
3. バックアップの場所と復元方法
4. 本来ユーザーに確認すべきだった項目 — 聞けずにローカル優先で倒したもの、
   リポジトリ側のバグとして報告が必要なもの

## 止まって手順に戻るサイン

| サイン | 何が起きるか |
|---|---|
| 差分を見る前に `install.sh` を流した | ローカルの mise config は既に消えている。バックアップから戻して最初から |
| `ghq get` / `fetch` の失敗を無視した | 古い `origin/main` を新しいと誤認して判断する |
| 祖先が取れないのに 3-way を続けた | `bad object`。force-push を疑い、祖先なしモードに切り替える |
| 現在の `main` とローカルを比べてローカル差分を判定した | リポジトリの更新を「ローカル改変」として捨てる |
| 衝突マーカーを残して配置した | mise が config をパースできず全ツールが落ちる |
| 検証を `mise ls` の exit code で済ませた | ツールが丸ごと無効化されていても素通りする |
| `--skip-deps` なしで `setup:codex` を実行した | `setup:claude` 経由で `settings.json` が上書きされる |
| `permissions.allow` をリモートの配列で置換した | その端末で許可していたコマンドが全部プロンプトに戻る |
| ローカルのピン留めを「古いから」と `latest` に戻した | ピン留めには理由がある。確認せずに外さない |
| ローカル差分を確認も報告もせず捨てた | 端末が壊れた理由が誰にも分からなくなる |
| revision ファイルの更新を忘れた | 更新済みなのに毎日通知が出続ける |
