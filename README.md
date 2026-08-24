# check-gcloud-adc

Google Cloud の Application Default Credentials (ADC) トークンの有効性と必要スコープを定期的にチェックし、無効・スコープ不足の場合に macOS 通知を送信するツールです。通知をクリックすると再認証が実行され、ブラウザで認証できます。

## 仕組み

- `gcloud auth application-default print-access-token` でトークンの有効性を確認
- さらに `tokeninfo` でスコープを検査し、必要スコープ (既定は `calendar.readonly` / `drive.readonly` を含む superset) が欠けていれば無効として扱う
- 無効・スコープ不足の場合、macOS のネイティブ通知を送信（1 回のみ、再認証まで重複しない）
- 通知クリックで再認証を実行（専用の Chrome ウィンドウが開いて認証）
  - ADC: `gcloud auth application-default login --scopes=<必要スコープ>` — 必要スコープを常に付与するため、他の `gcloud auth application-default login`（スコープ無し）に上書きされても復旧できる
  - 名前付きアカウント: `gcloud auth login --update-adc <account>`
- `brew services` により 5 分間隔で自動実行

### 再認証に使うブラウザ

再認証は**専用プロファイルの Chrome ウィンドウ**で行う。既定ブラウザに任せると「最後に使ったウィンドウ / プロファイル」に認証タブが生えるため、どのプロファイルで認証したかがブレるうえ、終わってもタブが残るのを避けるため。

- `--user-data-dir` を固定パス（既定 `${XDG_CACHE_HOME:-~/.cache}/check-gcloud-adc/browser-profile`）にした Chrome インスタンスで開く。普段使いの Chrome とは別プロセス・別プロファイルなので、既存ウィンドウを再利用しない。
- プロファイルのディレクトリは残るので、Google のログインセッションは次回の再認証に引き継がれる。作り直したいときはディレクトリごと削除する。
- gcloud が終わったら、その `--user-data-dir` を持つプロセスだけを終了させる。gcloud が途中で落ちた場合もウィンドウは残らない。

gcloud へは `$BROWSER` と、`PATH` に差し込んだ `open` の 2 経路で渡している。前者は gcloud が使う Python の `webbrowser` モジュールが、後者は `open <url>` を直に叩く実装が拾う。

Safari を使わないのは、Safari 17+ のプロファイルを CLI や AppleScript から指定する手段が無く、「どのプロファイルで開くか」を固定できないため。`open -na Safari` も複数インスタンスにはならず、既存ウィンドウを前面化するだけになる。

| 環境変数 | 既定 | 用途 |
|---|---|---|
| `CHECK_GCLOUD_ADC_BROWSER` | Google Chrome の実行ファイル | Chromium 系の別ブラウザ（Brave、Edge、Chrome Canary 等）の実行ファイルパス。**空文字を設定すると専用ウィンドウを使わず、既定ブラウザに任せる** |
| `CHECK_GCLOUD_ADC_BROWSER_PROFILE` | `${XDG_CACHE_HOME:-~/.cache}/check-gcloud-adc/browser-profile` | プロファイルの置き場所 |

Chrome が見つからない場合は自動的に既定ブラウザにフォールバックする。

### 必要スコープの設定

既定では以下の superset を要求・付与する（`calendar.readonly` / `drive.readonly` は Google Meet の議事録取得などに必要。`drive.file` はツールが作成した Google Sheets 等のファイルを作成・編集するために必要で、アプリが作成したファイルのみに限定される最小権限）。

```
openid
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/cloud-platform
https://www.googleapis.com/auth/calendar.readonly
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/drive.file
```

環境変数 `CHECK_GCLOUD_ADC_SCOPES`（カンマまたは空白区切り）で上書きできる。`brew services` で使う場合はサービスの環境に設定する。

### チェック対象アカウントの絞り込み

既定では `gcloud auth list` に出る全アカウントのトークンをチェックする。特定のアカウントだけをチェックしたい（使っていないアカウントの通知を止めたい）場合は、許可リストを指定する。指定されたアカウントだけがチェック対象になり、それ以外は無視される（ADC のチェックは許可リストと無関係に常に行う）。

解決順は次のとおり:

1. 環境変数 `CHECK_GCLOUD_ADC_ACCOUNTS`（カンマまたは空白区切り）
2. 設定ファイル `${XDG_CONFIG_HOME:-~/.config}/check-gcloud-adc/accounts`（1 行 1 アカウント、`#` 以降はコメント、空行無視）
3. どちらも無ければ全アカウント（従来の挙動）

`brew services` で使う場合は、Formula に個人情報を書かずに済む設定ファイル方式が便利。

```bash
mkdir -p ~/.config/check-gcloud-adc
cat > ~/.config/check-gcloud-adc/accounts <<'EOF'
# トークンチェック対象アカウント (1 行 1 件)
me@example.com
EOF
```

## インストール

```bash
brew install delphinus/check-gcloud-adc/check-gcloud-adc
```

### 前提条件

- macOS
- [Google Cloud SDK](https://cloud.google.com/sdk) (`gcloud` コマンド)


## 使い方

### サービスとして実行（推奨）

```bash
# サービスを開始（5 分間隔で自動実行）
brew services start check-gcloud-adc

# ステータス確認
brew services info check-gcloud-adc

# サービスを停止
brew services stop check-gcloud-adc
```

### 手動で実行

```bash
check-gcloud-adc
```

### テスト・トラブルシューティング

```bash
# テスト通知を送信（ADC チェックをスキップ）
check-gcloud-adc --test

# 通知設定を開いて状態をリセット（通知が出ない場合に）
check-gcloud-adc --reset
```

### URL スキーム

通知をクリックする代わりに、URL スキームで直接アクションを実行できます。

```bash
# 再認証（専用の Chrome ウィンドウが開き、終わると閉じます）
open check-gcloud-adc://reauth

# リポジトリを開く
open check-gcloud-adc://open-repo
```

### ログ

サービス実行時のログは以下に出力されます。

```
$(brew --prefix)/var/log/check-gcloud-adc/output.log
$(brew --prefix)/var/log/check-gcloud-adc/error.log
```

## 開発

```bash
# ビルド
make build

# クリーンアップ
make clean
```

### リリース

タグをプッシュすると GitHub Actions が自動でリリースを作成し、Formula を更新します。

```bash
git tag v0.2.0
git push origin v0.2.0
```

## ライセンス

MIT
