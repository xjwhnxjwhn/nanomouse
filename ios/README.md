# 鼠输入法（NanoMouse）

一款基于「[中州韻輸入法引擎／Rime Input Method Engine](https://github.com/rime/librime)」的
iOS 版本输入法.

# License

MIT 许可。

# 如何编译运行

在 1.0 版本，很多伙伴 `clone` 项目后都无法直接运行，多数问题是被被卡在 `librime`
的编译下了，于是新版本将这步省略了。

目前 [LibrimeKit](https://github.com/imfuxiao/LibrimeKit) 项目，只用来作为
[librime](https://github.com/rime/librime) 的编译项目，并使用 `Github Action`
将依赖的 Framework 编译并发布 Release。大家可以下载编译好的 Framework
使用，无需在为了编译环境而困扰。

> 感谢 @amorphobia 为 LibrimeKit 提交的 Github Action 配置

1. 下载编译后的 Framework

```sh
make framework
```

2. 下载内置方案

```sh
make schema
```

3. XCode 打开项目并运行

```sh
xed .
```

# 第三方库

鼠输入法（NanoMouse）的功能的开发离不开这些开源项目：

- [librime](https://github.com/rime/librime) (BSD License)
- [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit.git) (MIT License)

- [Runestone](https://github.com/simonbs/Runestone.git) (MIT License)
- [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages.git) (MIT
  License)
- [ProgressHUD](https://github.com/relatedcode/ProgressHUD) (MIT License)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT License)
- [Yams](https://github.com/jpsim/Yams) (MIT License)
- [GCDWebServer](https://github.com/swisspol/GCDWebServer)

# 致谢

感谢 TF 版本交流群中的 @一梦浮生，@CZ36P9z9
等等伙伴对测试版本的反馈与帮助，也感谢 @王牌饼干 为输入法制作的工具。

# 捐赠

TODO: 后续补充

### AppStore

TODO: 后续补充
