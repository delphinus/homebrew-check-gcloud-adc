# check-gcloud-adc

Google Cloud の Application Default Credentials (ADC) トークンの有効性と必要スコープを定期的にチェックし、無効・スコープ不足の場合に macOS 通知を送信するツールです。通知をクリックすると再認証が実行され、ブラウザで認証できます。

## 仕組み

- `gcloud auth application-default print-access-token` でトークンの有効性を確認
- さらに `tokeninfo` でスコープを検査し、必要スコープ (既定は `calendar.readonly` / `drive.readonly` を含む superset) が欠けていれば無効として扱う
- 無効・スコープ不足の場合、macOS のネイティブ通知を送信（1 回のみ、再認証まで重複しない）
- 通知クリックで再認証を実行（ブラウザが開いて認証）
  - ADC: `gcloud auth application-default login --scopes=<必要スコープ>` — 必要スコープを常に付与するため、他の `gcloud auth application-default login`（スコープ無し）に上書きされても復旧できる
  - 名前付きアカウント: `gcloud auth login --update-adc <account>`
- `brew services` により 5 分間隔で自動実行

### 必要スコープの設定

既定では以下の superset を要求・付与する（`calendar.readonly` / `drive.readonly` は Google Meet の議事録取得などに必要）。

```
openid
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/cloud-platform
https://www.googleapis.com/auth/calendar.readonly
https://www.googleapis.com/auth/drive.readonly
```

環境変数 `CHECK_GCLOUD_ADC_SCOPES`（カンマまたは空白区切り）で上書きできる。`brew services` で使う場合はサービスの環境に設定する。

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
# 再認証（ブラウザが開きます）
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
