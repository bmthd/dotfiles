# /dotfiles apply — この端末に更新を適用する

`install.sh` と `mise run setup` は **リモートの内容でローカルを上書きする**前提で
書かれている。端末ごとの事情 (手で編集した設定、その端末だけのツール、手で足した
フック) はリポジトリ側に存在しないので、素直に再実行すると黙って消える。

mise の設定だけは例外で、それは注意深さではなく構造によるもの。リポジトリ側のコピーは
`~/.config/mise/conf.d/10-dotfiles.toml` に置かれ、`~/.config/mise/config.toml` は端末側に
開けてあるため、上書きされるファイルの中にユーザーのものが最初から入っていない。
以下の話は、所有ではなくマージで作られる Claude Code の設定にはそのまま当てはまる。

ここでやるべきは、**上書きする前に「取り込む変更」と「守るローカル差分」を分離すること**。
差分を見ずに `install.sh` を流したら意味がない。

## 上書きハザード表

再実行で何が起きるか。ここが判断の全体像。

| 対象 | 素直に再実行すると | 扱い |
|---|---|---|
| `~/.config/mise/conf.d/10-dotfiles.toml` | リポジトリの `.mise.toml` で **curl 全上書き** | **上書きしてよい** (ステップ 4)。端末固有の状態を持たないのでマージするものが無い |
| `~/.config/mise/config.toml` | **書き込まれない。** 端末専用で、mise は conf.d の後に読むのでこちらが勝つ | 触らない。conf.d 分離より前に入れた端末にはリポジトリのコピーが残っている。一度だけ移行する (ステップ 4) |
| `~/.claude/settings.json` | `jq -s '.[0] * .[1]'` で deep merge、**衝突時はリモート優先**。配列 (`permissions.allow` 等) は連結ではなく**置換** | **要手動適用** (ステップ 5)。残る最大の危険地帯。リポジトリ側に差分が無ければ触らない |
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
cat ~/.config/mise/config.toml 2>/dev/null            # この端末専用の mise 設定
git -C "$REPO" show "$INSTALLED:.claude/statusline.sh" | diff - ~/.claude/statusline.sh
```

`config.toml` は diff ではなく通読する。対応するものがリポジトリ側に無く、書いてある内容は
定義上すべて端末固有だから。conf.d 分離より前に入れた端末では、ここにリポジトリのコピーが
入っている。その移行はステップ 4 で行う。

出てきた差分は一つずつ「なぜそうなっているか」をユーザーに確認する。ピン留めされた
バージョン、その端末専用のツール、無効化された設定は **事故ではなく意図**であることが多い。
消す前に必ず聞く。聞けない状況では **ローカルを残す側に倒し**、確認事項として最後の報告に残す。

### 3. バックアップを取る

適用前に必ず。復元コマンドをユーザーに伝えられる状態にしておく。

```bash
BK=~/.config/dotfiles/backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
cp ~/.config/mise/config.toml ~/.claude/settings.json ~/.claude/statusline.sh "$BK/" 2>/dev/null
cp ~/.config/mise/conf.d/10-dotfiles.toml "$BK/" 2>/dev/null
```

### 4. mise config の fragment を置き換える

**ここに 3-way マージは無い。** リポジトリの設定は端末固有のものを何も持たない conf.d
fragment なので、まるごと取る。端末固有のピン留め・追加ツール・ローカルの `[settings]` は
`~/.config/mise/config.toml` に置く。mise は conf.d の後にこのファイルを読み、
このリポジトリはそこに一切書き込まない。

```bash
mise ls --installed | awk '{print $1}' | sort > "$W/tools.before"   # 配置前に取っておく
mkdir -p ~/.config/mise/conf.d
git -C "$REPO" show origin/main:.mise.toml > ~/.config/mise/conf.d/10-dotfiles.toml
git -C "$REPO" show origin/main:mise.lock  > ~/.config/mise/mise.lock
```

`mise.lock` も一緒に取る。fragment の `latest` を実際のバージョンに変えているのはこれで、
mise はグローバルの lockfile をファイル名ではなく config ディレクトリに紐付けるため、
`~/.config/mise/mise.lock` の 1 本が conf.d 側にも効く。

**conf.d 分離より前に入れた端末は、ここで一度だけ移行する。** その端末の
`~/.config/mise/config.toml` にはまだリポジトリのコピーが入っている。これを放置すると、
置き換わったはずの上書きより悪い。config.toml は conf.d より優先され、`[tasks]` は
マージではなくまるごと置換されるため、古いコピーがこちらのタスクを永久に隠し続ける。

```bash
grep -q 'raw.githubusercontent.com/bmthd/dotfiles' ~/.config/mise/config.toml 2>/dev/null &&
    mv ~/.config/mise/config.toml "$BK/config.toml.pre-conf.d"
```

退避したファイルと新しい fragment を diff し、**端末固有の部分だけを、空になった
`config.toml` に書き戻す**。差分には upstream の更新とローカルの改変が混ざっているので、
ステップ 2 の棚卸しと突き合わせて一つずつ判断する。従来の 3-way マージと同じ作業だが、
更新のたびではなく端末につき一度で終わる点が違う。

```bash
diff "$BK/config.toml.pre-conf.d" ~/.config/mise/conf.d/10-dotfiles.toml
```

`install.sh` がやるのは、安全だと証明できる範囲だけ。配置しようとしているコピーと同一か、
`~/.config/dotfiles/revision` が指すリビジョンの `.mise.toml` と同一のとき (= ローカルで
何も足されていないとき) だけ移行し、それ以外は**その場に残して**その旨を表示する。
これは意図的なもの。あのスクリプトでは直後に `mise install` と `mise run setup` が走るため、
バージョンを固定している config.toml を退避すると、警告を読む前にピン留めが無効化された
状態で lockfile 側のバージョンが入ってしまう。端末固有の側を書き戻すのはこの手順の仕事で、
ブートストラッパの仕事ではない。

その後、**パースだけでなく中身を検証する**。`mise ls` の exit 0 は当てにならない。

```bash
mise cfg   # conf.d/10-dotfiles.toml が並び、config.toml があればその後に来る
mise tasks ls >/dev/null || echo "!! config が壊れた。バックアップから戻す"
mise ls --installed | awk '{print $1}' | sort | diff "$W/tools.before" -
mise run --skip-tools setup:oci-plugin
mise install
```

`setup:oci-plugin` は `mise install` より先に実行する。古い環境では asdf 版 OCI
プラグインが mise の `oci` という名前で残っている。現在の mise は同じ名前を vfox
として解決するため、そのままでは Bash 製プラグインを Lua として読み込んで失敗する。
このタスクは旧 checkout だけを置き換え、vfox 導入後は何もしない。

TOML としてパースできることと mise の設定として正しいことは別物。**config に書いたツールが
`mise ls` に現れているか**を確認する。`[tools.xxx]` のサブテーブル見出しは、それ以降の平坦な
キーを全部自分の子として吸い込むため、後続のツールが丸ごと無効化されうる。`mise install` が
「all tools are installed」と即答するのに `command -v` で見つからない、
`No version is set for shim: <tool>` が出る、といった症状はこれ。**端末側の作業ではなく
リポジトリ側のバグ。** 端末側で勝手に直さず、`/dotfiles pr` で報告する。

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

ローカル改変があれば `$INSTALLED` を祖先にした 3-way マージで扱う。

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

**`setup:skills` はソースが失敗しても成功として終わる。** タスクの各行は
`install_skills` を通り、エラーを握り潰して
`⚠ <label> skills installation failed (continuing)` と出すだけ。タスク自体は exit 0 で
終わるため、何も入らなかったソースと成功したソースが区別できない。タスクの出力から
この警告を拾い、各ソースが実際に入ったか確認する。

```bash
npx skills list -g
```

失敗したソースは手で流し直す。transient な失敗であることが多い。

```bash
npx skills add <ソース> -y -g -a claude-code -a opencode -a cursor
```

**upstream で削除・改名されたスキルは残り続ける。** `npx skills` は非対話モードでは
削除を拒否して警告を出すだけなので、改名すると古い名前が新しい名前の隣に残る。
同じ仕事を主張するスキルが2つある状態は、どちらか一方だけより悪い。警告と
`npx skills list -g` を突き合わせて残骸を消す。

```bash
npx skills remove <古い名前> -g -y
```

### 7. リビジョンを記録して報告する

ここを忘れると、次のシェル起動でまた「更新があります」と言われる。

```bash
git -C "$REPO" rev-parse origin/main > ~/.config/dotfiles/revision
```

`update-notice.sh` はステップ 1 の diff に含まれていたときだけ取り直せばよい。

```bash
git -C "$REPO" show origin/main:.dotfiles/update-notice.sh > ~/.config/dotfiles/update-notice.sh
```

通知は `bmthd/skills` も見ている。そちらのリビジョンはステップ 6 の
`mise run setup:skills` が記録するので、通常は何もしなくてよい。タスクを流さず
`npx skills add` でソースを入れ直しただけのときは自分で記録する。**上の取り直しより後で
実行すること** — 古いスクリプトには `record` サブコマンドが無く、黙って無視される。

```bash
bash ~/.config/dotfiles/update-notice.sh record skills
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
| 差分を見る前に `install.sh` を流した | `~/.claude/settings.json` が既にリモート優先でマージされている。バックアップから戻して最初から |
| `ghq get` / `fetch` の失敗を無視した | 古い `origin/main` を新しいと誤認して判断する |
| 祖先が取れないのに `statusline.sh` の 3-way を続けた | `bad object`。force-push を疑い、祖先なしモードに切り替える |
| リポジトリ由来の `~/.config/mise/config.toml` を放置した | conf.d より優先され `[tasks]` をまるごと置換するので、タスクが古いコピーのまま凍る |
| 現在の `main` とローカルを比べてローカル差分を判定した | リポジトリの更新を「ローカル改変」として捨てる |
| 衝突マーカーを残して配置した | mise が config をパースできず全ツールが落ちる |
| `config.toml` ではなく `conf.d/10-dotfiles.toml` を手で編集した | 次の更新で上書きされる。端末固有の変更は `config.toml` に書く |
| 検証を `mise ls` の exit code で済ませた | ツールが丸ごと無効化されていても素通りする |
| `--skip-deps` なしで `setup:codex` を実行した | `setup:claude` 経由で `settings.json` が上書きされる |
| `setup:skills` の exit 0 をスキルが入った証拠にした | 何も入らなかったソースと成功したソースが区別できない |
| `permissions.allow` をリモートの配列で置換した | その端末で許可していたコマンドが全部プロンプトに戻る |
| ローカルのピン留めを「古いから」と `latest` に戻した | ピン留めには理由がある。確認せずに外さない |
| ローカル差分を確認も報告もせず捨てた | 端末が壊れた理由が誰にも分からなくなる |
| revision ファイル (dotfiles / skills) の更新を忘れた | 更新済みなのに毎日通知が出続ける |
