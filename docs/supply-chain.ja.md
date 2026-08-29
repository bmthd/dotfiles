# サプライチェーン対策

[English](supply-chain.md) | 日本語

対策は 4 層に分かれ、それぞれ守る範囲が違います。

| 層 | 手段 | 守る範囲 |
| --- | --- | --- |
| バージョン | `mise.lock` + `--minimum-release-age 2d` | publish 直後の 2 日間 |
| 成果物 | `mise.lock` のチェックサム | 検証済みバージョンの差し替え・再 publish |
| パッケージ | `~/.npmrc` の [Takumi Guard](https://npm.flatt.tech/) プロキシ | npm 経由すべて。特にロックできない実行時の `npx ctx7@latest` / `npx skills add` |
| Action のソース | `pinact` が検証する完全な commit SHA | GitHub Actions の release tag の移動や侵害 |

## バージョン: `latest` 宣言 + ロックファイル

`.mise.toml` の `[tools]` は `latest` を宣言していますが、`latest` がそのまま入るわけではありません。
mise は fuzzy な指定よりロックファイルのバージョンを優先するため、実際に入るのは `mise.lock` が決めたバージョンです。

ロックファイルは [`bump-tools.yml`](../.github/workflows/bump-tools.yml) が毎日進めます。

```bash
mise lock --bump --minimum-release-age 2d
```

`--minimum-release-age` は公開から 2 日経っていないリリースを候補から外します。
侵害されたリリースが取り込まれるのは publish 直後の数時間なので、この待機だけでその時間帯を丸ごと回避できます。
レビューではなくこのフラグが安全性を担保しているため、PR は作らず main に直接コミットします。

このフラグは `latest` のような fuzzy な指定にのみ効きます。バージョンを `.mise.toml` 側で固定しない理由がこれです。

ロックファイルは必須です。取得に失敗した場合 `install.sh` は中断します。
`latest` のまま `mise install` すると待機期間を迂回して最新版が入ってしまうためです。
ロックされていないツールの混入と、`[tools]` が 1 行のインラインテーブルで書かれていない行は [`tests/mise-pins-test.sh`](../tests/mise-pins-test.sh) が検出します。
後者はツールが黙って消えるのを防ぐためのものです。`[tools.<name>]` のサブテーブルは `[tools]` を終わらせるため、それ以降の平坦なキーは新しいツールではなくそのツールのキーになります。
このテストは CI と、リンクすれば [`.githooks`](../.githooks) の pre-commit フックの両方から走ります。

## Action のソース: 不変な commit SHA

[`.github/workflows`](../.github/workflows) 以下の `uses:` は、すべて 40 文字の完全な commit SHA に固定します。
行末には release tag をコメントとして残すため、実行時に可変な tag を信頼せず、レビューでは元のバージョンを読めます。

二つの経路で `pinact` がこの状態を維持します。
CI の `pinact run -check -verify-comment` は、未固定の参照に加えて、SHA とバージョンコメントの不整合も拒否します。
global pre-commit dispatcher は staged workflow に pinact を実行してから、従来どおり repository 固有の pre-commit hook へ処理を渡します。
pinact は index の一時コピーを修正し、生成した blob だけを index に戻すため、未 stage の編集や部分 stage の内容が commit に混ざりません。
同じ修正を working tree へ安全に適用できる場合は反映し、競合する未 stage 編集は変更せずに残します。

pinact 自体も mise の管理対象であり、`mise.lock` が checksum とバージョンを固定します。
その lock entry は、ほかのツールと同じ日次の `--minimum-release-age 2d` gate を通って更新されます。

## パッケージ: npm レジストリのプロキシ

プロキシが効くのは `~/.npmrc` を書いた時点以降だけなので、`install.sh` は `mise install` より前に `mise run --skip-tools setup:npm-registry` を実行します。
`--skip-tools` を落とすと `mise run` 自体がツール一式を先に入れてしまい、順序が逆転します。
パッケージは問題なく入るため失敗が表に出ません ([`tests/install-order-test.sh`](../tests/install-order-test.sh) が検出します)。

レジストリは環境変数ではなく `~/.npmrc` に書くため、プライベートレジストリを使うプロジェクトはリポジトリ側の `.npmrc` で上書きできます。
既に独自のレジストリが設定されている場合、セットアップはそれを変更しません。

## 対象外: スキル

`npx skills add` が取得する Markdown は各エージェントのコンテキストに直接入るため、プロンプトインジェクションの経路になり得ます。
しかし skills CLI にリビジョン固定の手段がありません。`npx skills update` は差分を確認してから実行してください。

## bump-tools.yml のセットアップ（初回のみ）

main は ruleset `main-guardrails` で保護されており、`pull_request` ルールが直接 push を禁止しています。
既定の `GITHUB_TOKEN` は bypass に登録できません（GitHub Actions を bypass actor にできるのは Organization 所有のリポジトリだけで、ここは User 所有のため）。
GitHub App なら登録できるので、App のトークンを使います。

1. [GitHub App を作成](https://github.com/settings/apps/new)する。Repository permissions は **Contents: Read and write** のみ。Webhook は不要
2. 作成後、Client ID を控え、Private key を生成してダウンロードする
3. その App をこのリポジトリに install する
4. リポジトリの Secrets に登録する
   - `BUMP_APP_CLIENT_ID` — 手順 2 の Client ID
   - `BUMP_APP_PRIVATE_KEY` — ダウンロードした `.pem` の中身
5. Settings > Rules > `main-guardrails` の Bypass list に、作成した App を Integration として追加する

`workflow_dispatch` から手動実行して、push まで通ることを確認してください。
