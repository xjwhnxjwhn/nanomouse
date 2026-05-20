# mac 目录说明

本目录仍然被主工程使用，但本目录不是独立入口。

唯一允许使用的 Xcode 工程入口是：

`/Users/zhangxiangqing/Desktop/ipt/nanomouse/ios/Hamster.xcodeproj`

## 规则

- `mac/gui/SCT.xcodeproj` 是历史遗留独立工程，不要把它作为构建、调试、验证或修改入口。
- 如果任务涉及 mac target，必须使用 `ios/Hamster.xcodeproj` 中的 `SCT` target。
- `mac/gui/SCT` 下面的源码仍然被 `ios/Hamster.xcodeproj` 引用，它只是物理文件位置，不代表独立 app。
- 所有 `xcodebuild` 命令必须显式使用 `-project ios/Hamster.xcodeproj`。
- 除非用户明确要求，不要在 `mac/gui` 或 `mac/gui/SCT.xcodeproj` 中新增文件。

正确示例：

```sh
xcodebuild -project ios/Hamster.xcodeproj -scheme SCT -configuration Debug -destination 'platform=macOS' build
```

错误示例：

```sh
xcodebuild -project mac/gui/SCT.xcodeproj -scheme SCT build
```
