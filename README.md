# check-gcloud-adc

Google Cloud の Application Default Credentials (ADC) トークンの有効性を定期的にチェックし、期限切れの場合に macOS 通知を送信するツールです。通知をクリックすると WezTerm で再認証用のタブが開きます。

## 仕組み

- `gcloud auth application-default print-access-token` を実行してトークンの有効性を確認
- トークンが無効な場合、macOS のネイティブ通知を送信（1 回のみ、再認証まで重複しない）
- 通知クリックで `gcloud auth login --update-adc` を WezTerm 内で実行
- `brew services` により 5 分間隔で自動実行

## インストール

```bash
brew install delphinus/check-gcloud-adc/check-gcloud-adc
```

### 前提条件

- macOS
- [Google Cloud SDK](https://cloud.google.com/sdk) (`gcloud` コマンド)
- [WezTerm](https://wezfurlong.org/wezterm/)（通知クリック時の再認証に使用）

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
# WezTerm で再認証
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
