# CLAUDE.md

## リリース手順

リリースは CI (GitHub Actions) で完結する。ローカルからリリースしない。

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

タグを push すると `.github/workflows/release.yml` が以下を自動実行する:
- ユニバーサルバイナリのビルド
- テスト
- GitHub Release の作成 & tarball アップロード
- Homebrew Formula の更新 & main への push

### 禁止事項

- ローカルから `gh release create` / `gh release upload` を実行しない
- `make build-universal` はローカルテスト用。リリースバイナリは CI が作る
