# Dotfiles

最新の開発ツールを簡単にセットアップするための dotfiles です。

## インストールされるツール

- **[mise](https://mise.jdx.dev/)** - 開発ツールのバージョン管理
- **[Node.js](https://nodejs.org/)** (latest) - JavaScript ランタイム
- **[pnpm](https://pnpm.io/)** (latest) - 高速なパッケージマネージャー
- **[Bun](https://bun.sh/)** (latest) - 高速な JavaScript ランタイム & ツールキット
- **[GitHub CLI](https://cli.github.com/)** (latest) - GitHub の公式 CLI
- **[ni](https://github.com/antfu/ni)** (latest) - パッケージマネージャーの統一インターフェース
- **[Playwright CLI](https://playwright.dev/)** (latest) - ブラウザ自動化ツール

## クイックスタート

```bash
# リポジトリをクローン
git clone https://github.com/bmthd/dotfiles.git
cd dotfiles

# インストールを実行
./install.sh

# シェルを再起動または設定を再読み込み
source ~/.bashrc  # または source ~/.zshrc
```

## インストール内容

### 自動セットアップ

`install.sh` は以下を自動的に行います：

1. mise のインストール
2. mise 経由で node, pnpm, bun, gh の最新版をインストール
3. npm 経由で ni と playwright-cli をグローバルインストール
4. シェル設定ファイルに mise の自動起動設定を追加

### 設定ファイル

- **`.mise.toml`** - mise の設定（ツールのバージョン指定、自動インストール設定）
- **`.shellrc`** - シェル設定のスニペット（手動で追加する場合の参考）

## 使い方

### ツールの確認

```bash
# インストールされているツールの一覧
mise list

# 各ツールのバージョン確認
node --version
pnpm --version
bun --version
gh --version
```

### パッケージマネージャーの統一操作（ni）

`ni` を使うと、プロジェクトのパッケージマネージャーを自動判定して操作できます：

```bash
ni          # npm install / pnpm install / yarn install を自動判定
nr dev      # npm run dev / pnpm dev / yarn dev を自動判定
nlx vite    # npx vite / pnpm dlx vite / yarn dlx vite を自動判定
```

### Playwright の使用

```bash
# ブラウザのインストール
playwright install

# テストの実行
playwright test
```

## カスタマイズ

### ツールのバージョンを変更

`.mise.toml` を編集してバージョンを指定できます：

```toml
[tools]
node = "20.0.0"  # 特定のバージョンを指定
pnpm = "latest"  # 最新版を使用
```

### プロジェクト固有の設定

各プロジェクトディレクトリに `.mise.toml` を配置することで、プロジェクト固有のツールバージョンを管理できます。

## ライセンス

MIT
