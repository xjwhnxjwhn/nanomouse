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

## 自动发布流程

仓库已配置 GitHub Actions：`.github/workflows/upload-apple-assets.yml`。

当 `main` 分支里的 `zips/**` 更新后，GitHub 会自动触发 workflow：

1. GitHub 正常接收这次 push，GitHub raw 兜底源随之更新。
2. Actions 在 macOS runner 上 checkout 当前仓库。
3. 脚本读取这次 push 中变更的 `zips/` 文件，只把对应资源上传到 CloudKit Production。

上传源头是 Actions checkout 下来的仓库文件，也就是这次 push 后的 `zips/` 内容；不是从 GitHub raw 再下载一遍。

首次启用自动上传前，需要在 GitHub 仓库设置里添加 repository secret：

- Name: `CLOUDKIT_USER_TOKEN`
- Value: CloudKit Console 生成的 user token

本地执行 `xcrun cktool save-token --type user --method keychain` 保存的是本机 Keychain，GitHub Actions 读不到；自动上传必须使用 GitHub Secret。

## 手动发布流程

通常不需要手动执行。只有在 Actions 失败、想重传全部资源、或想先传 Development 验证时，才手动跑脚本。

本机首次使用 `cktool` 前保存用户 token：

```bash
xcrun cktool save-token --type user --method keychain
```

首次接入新的 `NanomouseAssetPackage` 记录类型时，建议顺序是：

1. 先导入 Development schema。
2. 在 CloudKit Console 中把 Development schema 部署到 Production。
3. 再上传 Production 真实资源。

schema 导入使用的是 CloudKit `management token`，不是上传记录用的 `user token`。首次使用前先保存 management token：

```bash
xcrun cktool save-token --type management --method keychain
```

然后导入 Development schema：

```bash
scripts/import_apple_asset_schema.py --environment development
```

这个脚本只允许导入 Development schema。它会先导出当前环境已有 schema，再把 `cloudkit/nanomouse-asset-record-type.ckdb` 中的 `NanomouseAssetPackage` 追加进去，最后 validate/import。它不会用单独的新 schema 覆盖整个容器；如果当前环境已经存在 `NanomouseAssetPackage`，脚本会直接跳过。Production 只能从 CloudKit Console 的 Deploy Schema Changes 部署。

上传 Development 环境验证：

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

不传 `--git-base/--git-head` 时，脚本会读取 `zips/manifest.json` 并上传其中列出的所有包。Actions 自动上传时会传入 git range，因此只上传发生变化的包。

对于不在 manifest 中的额外资源，脚本会自动检查并上传：

- `zenz-v3.1-xsmall-Q5_K_M.gguf`
- `zenz-v3.1-small-Q5_K_M.gguf`
- `predict_traditional.db`

`predict_traditional.db` 需要手动放入 `zips/` 后才会上传；如果不存在，App 会继续使用 GitHub release 兜底下载繁体官方联想库。

## 注意

- CloudKit schema 需要部署到 Production，否则 App Store 发行版读不到记录。
- Public Database 资源是公开读，适合 zip、词库、模型这类公开下载内容。
- 键盘扩展不直接下载资源。主 App 下载后写入 App Group，键盘扩展只读取本地结果。
