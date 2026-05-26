# Apple 资源分发

## 目标

中国大陆用户不再把 GitHub 作为按需资源的主下载源。App 会按以下顺序下载：

1. CloudKit Public Database 中的 `NanomouseAssetPackage` 记录。
2. GitHub raw `zips/`，作为兜底和开发调试源。

iOS 26+ 的 Apple-hosted Background Assets 需要 App Store Connect asset pack 配套，后续可作为第一优先级加入；当前先用 CloudKit Public Database 覆盖所有支持系统。

## CloudKit 记录结构

Database: `public`

Record Type: `NanomouseAssetPackage`

字段：

- `id`: String，例如 `rime-predict`
- `fileName`: String，例如 `rime-predict.zip`
- `title`: String
- `publishedAt`: String，保持 `zips/manifest.json` 中的日期格式
- `sha256`: String
- `minSharedSupportVersion`: String，可为空
- `asset`: Asset，对应 zip/db/gguf 文件

App 会优先按 `id` 查找记录，查不到时再按 `fileName` 查找。

## 发布流程

每次更新 `zips/` 后必须做两件事：

1. 正常提交并 push，让 GitHub raw 兜底源更新。
2. 用脚本上传同一批资源到 CloudKit Public Database。

首次使用 `cktool` 前保存用户 token：

```bash
xcrun cktool save-token --type user --method keychain
```

先上传 Development 环境验证：

```bash
scripts/upload_apple_asset_packages.py \
  --environment development
```

确认 App 可以从 CloudKit 下载后，再上传 Production 环境，供 App Store/TestFlight 发行版使用：

```bash
scripts/upload_apple_asset_packages.py \
  --environment production
```

脚本默认从 `ios/Hamster.xcodeproj` 的 Hamster scheme 读取 `DEVELOPMENT_TEAM`。如果 Xcode 工程里没有 Team ID，再手动追加 `--team-id <Apple Developer Team ID>`。

脚本会读取 `zips/manifest.json` 并上传其中列出的所有包。对于不在 manifest 中的额外资源，脚本会自动检查并上传：

- `zenz-v3.1-xsmall-Q5_K_M.gguf`
- `zenz-v3.1-small-Q5_K_M.gguf`
- `predict_traditional.db`

`predict_traditional.db` 需要手动放入 `zips/` 后才会上传；如果不存在，App 会继续使用 GitHub release 兜底下载繁体官方联想库。

## 注意

- CloudKit schema 需要部署到 Production，否则 App Store 发行版读不到记录。
- Public Database 资源是公开读，适合 zip、词库、模型这类公开下载内容。
- 键盘扩展不直接下载资源。主 App 下载后写入 App Group，键盘扩展只读取本地结果。
