# /dotfiles apply

`.dotfiles/apply.sh` が決定論的な更新処理の唯一の正とする。
英語版を正とし、日本語版はその構造と意味を対応させる。
この手順は、スクリプトが決められない判断とユーザーへの説明を担う。

## 1. checkout を用意する

fetch はスクリプトが行うが、スクリプト自身を含む checkout の取得はできないため、この手順は担当者が行う。

```bash
ghq get -u github.com/bmthd/dotfiles || git clone https://github.com/bmthd/dotfiles "$REPO"
```

`ghq` は shim として PATH にありながら失敗することがある（`No version is set for shim: ghq`）。
`git clone` の fallback は飾りではない。
この手順が失敗したまま更新を報告しない。

## 2. plan を作成する

その checkout から、次を実行する。

```bash
.dotfiles/apply.sh plan --json
```

`plan` はこの端末に対して読み取り専用である。remote ref の fetch は checkout 内の remote-tracking ref を書くだけで、管理対象の file には触れない。
出力される単一の JSON document を、現在の inventory として扱う。

top-level の field は次のとおりである。

- `mode`：`inventory` なら apply の可否を判断できる。`no-base` ならできない。
- `fetch`：`ok` なら remote ref を更新できた。`failed` なら更新できていない。`skipped` は `--remote-ref` が設定済みの remote を指していない場合。
- `fetchError`：fetch が失敗した場合のその内容。
- `baseRevision` と `remoteRevision`：この inventory に使った revision。
- `files`：`repositoryPath`、`localPath`、`state` を持つ entry。
- `legacyMiseConfig`：`~/.config/mise/config.toml`（conf.d 移行前の配置先）の `path` と `state`。

`fetch` が `ok` でない inventory は、現在の remote ではなく、この checkout が最後に fetch した内容を表している。
その inventory を現在のものとして報告せず、その事実をユーザーへ伝える。古い `origin/main` に対する inventory は、error ではなく「更新は無い」に見える形で失敗する。

エージェントの判断が必要なのは `conflict`、`needs-decision`、そして `legacyMiseConfig` の `needs-review` だけである。
それ以外の state、その merge、validation、backup、task、rollback、revision の処理はスクリプトに任せる。

`no-base` の plan は安全に適用できない。
ユーザーに次の進め方を確認し、その plan に対しては `apply` を実行しない。

## 3. 判断待ちを解消する

`conflict` または `needs-decision` の各 entry について、ローカルの内容がこの端末に今も必要か、古い残骸かを判断する。
conflict は機械的に片側を選ばず、設定の意味に基づいて解決する。

得られている文脈だけでは選べない場合、影響を受ける path と選択肢をユーザーへ示し、決定を得る。
判断待ちが残っている間は `apply` を実行しない。

`legacyMiseConfig` の `needs-review` も同様に `apply` を止める。
このファイルはリポジトリのコピーにローカルの変更が乗ったものであり、conf.d より優先される。放置すれば更新は shadow されたままになり、丸ごと退避すれば端末側で足した内容が失われる。
`~/.config/mise/conf.d/10-dotfiles.toml` との差分をユーザーへ示し、端末固有の部分だけを `config.toml` に残したうえで、新しい plan を作成する。
`DOTFILES_MIGRATE_MISE_CONFIG=1` での再実行は、ファイルに残したい内容がないとユーザーが確認したときだけにする。
それ以外の state に対応は要らない。`migratable` はスクリプトが backup へ退避し、`unrelated`、`destination`、`absent` は移行するものがない。

ユーザーが確認したローカル変更だけを行い、新しい plan を作成する。
この手順は、`mode` が `inventory` であり、どの file の state も `conflict` と `needs-decision` ではなく、`legacyMiseConfig.state` が `needs-review` でもなくなったときに完了する。

## 4. 確認して適用する

安全な plan と解決済みの判断をユーザーへ要約し、この端末を更新する明示的な確認を得る。

```bash
.dotfiles/apply.sh apply --json
```

result JSON は次のように読む。

- `result: "applied"`：スクリプトが更新を完了した。
- `result: "failed"` または `"rolled-back"`：更新の成功を報告できない。
- `apply` は自身の fetch が失敗した場合、確認できていない remote に合わせて端末を更新せず、実行そのものを拒否する。
- `backupPath`：スクリプトが作成した場合の backup の場所。
- `error`：失敗の詳細。ユーザーが対応できるだけの内容を報告する。

## 5. 報告する

script result、利用可能な場合の適用 revision、backup path、すべてのローカル判断とその理由、未解決のユーザー確認事項または失敗を報告する。

最後に実行した command の JSON を反映し、`result` が `applied` でない限り更新成功と書かないとき、この手順は完了する。
