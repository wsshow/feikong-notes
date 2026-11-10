# 开发指南

当前开发与发布验收以 Android 手机为主。产品范围见[产品说明](../PRODUCT.md)，专题文档见[文档索引](README.md)。

## 环境与运行

准备 Flutter 3.47.2（与发布 CI 一致）、Android Studio、Android SDK 36、JDK 17 和 Make。正式归档另外需要 Git、Python 3、`unzip` 和 `shasum`，从 Git 工作区运行发布命令。

```bash
make doctor
make devices
make run-android DEVICE=emulator-5554
```

将示例设备 ID 换成实际值。依赖由运行目标获取。首次构建 Android 时会下载原生运行库，MNN 下载与校验方式见[本地语言模型](local-llm.md#原生运行库)。

## 本地验证

在项目根目录执行。单独获取 Harness 的开发依赖，供根目录分析与核心包测试使用。

```bash
flutter pub get
(cd packages/fknotes_harness && dart pub get)
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

| 命令 | 用途 |
| --- | --- |
| `make help` | 查看完整目标和参数 |
| `make check` | 格式化源码，再运行静态分析与测试 |
| `make debug` / `make apk-debug-split` | 构建通用或按 ABI 拆分的 Debug APK，输出到 `dist/` |
| `make clean` | 清理构建缓存和 `dist/` |

正式归档使用 [Android 发布流程](ANDROID_RELEASE.md)。签名、构建产物、数据库、备份和本地缓存应留在 Git 忽略范围内。修改数据库时同步检查旧版本迁移与恢复路径。

## 覆盖安装进行真机诊断

需要保留已有笔记和模型时，可以用原 Release 证书签一个仅供诊断的 ARM64 Debug APK。先准备本机发布签名，并将示例版本和构建号换成真机对应值。

```bash
make debug-overlay BUILD_NAME=1.2.3 BUILD_NUMBER=2040
adb install -r -t dist/fknotes-1.2.3+2040-arm64-v8a-diagnostic-debug.apk
```

覆盖安装要求包名和签名一致，且构建号不低于已装版本。诊断包仅供本机排查。诊断结束后，使用同证书、构建号不低于诊断包的正式 APK 覆盖安装。

## 代码位置

| 路径 | 职责 |
| --- | --- |
| `lib/pages/`、`lib/widgets/`、`lib/providers/` | 页面、组件和状态 |
| `lib/editor/`、`lib/models/`、`lib/services/` | 编辑会话、数据模型、仓储和设备服务 |
| `lib/agent/`、`packages/fknotes_harness/` | 应用适配与纯 Dart 智能体内核 |
| `lib/theme/`、`lib/experience/` | 主题语义和主题专属渲染 |
| `android/`、`native/`、`test/` | Android 原生接入、共享原生代码和测试 |

其他平台工程用于开发验证。iOS 构建使用 macOS 和 Xcode，在 Runner 中配置签名后执行 `make ios`。
