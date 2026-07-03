# Dotfiles

開発ツールの自動セットアップ用 dotfiles

## Install

利用しているシェルに合わせてインストールコマンドを選んでください。
パイプ先のシェル (`bash` / `zsh`) を検出し、対応する設定ファイル
(`~/.bashrc` / `~/.zshrc`) に mise の有効化を追記します。

### zsh を使っている場合

```zsh
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | zsh
```

### bash を使っている場合

```bash
curl -fsSL https://raw.githubusercontent.com/bmthd/dotfiles/main/install.sh | bash
```

インストール後はシェルを再起動するか、`source ~/.zshrc`（bash の場合は
`source ~/.bashrc`）を実行すると各ツールに PATH が通ります。

## License

MIT
