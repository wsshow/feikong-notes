# 开发指南

当前开发与发布验收以 Android 手机为主。产品范围见[产品说明](../PRODUCT.md)，专题文档见[文档索引](README.md)。

## 环境与运行

准备 Flutter 3.47.2（与发布 CI 一致）、Android Studio、Android SDK 36、JDK 17 和 Make。正式归档另外需要 Git、Python 3、GitHub CLI（`gh`）、`unzip` 和 `shasum`，从 Git 工作区运行发布命令。`gh` 需登录具有仓库写权限的账号，以读取 Release 草稿。

```bash
make doctor
make devices
make run-android DEVICE=emulator-5554
```

将示例设备 ID 换成实际值。依赖由运行目标获取。首次构建 Android 时会下载原生运行库，MNN 下载与校验方式见[本地语言模型](local-llm.md#原生运行库)。

## 构建与验证

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

### 更新说明

更新说明维护在版本 tag 对应的 GitHub Release 草稿中，仓库不保存逐版本说明文件。人工正文使用中文，建议以 `# 非空笔记 <版本>` 开头，按实际内容分为“新增”“修复”“改进”，省略空分组；每条描述用户可感知的结果，必要时补充兼容性或升级注意事项，不以提交列表或对比链接代替说明。

打 tag 前根据上一个已发布版本到目标提交的变更整理草稿。没有对应草稿或正文为空时，脚本自动提取提交记录，并标注“未经人工整理”；这是兼容路径，提交标题保持原文，不自动推测用户收益或翻译英文。Release 正文、下载附件 `notes.md` 与应用内更新说明复用同一份解析结果。

可先只读解析并预览说明（不创建 Release、不打 tag、不上传）：

```bash
python3 tool/release_notes.py --tag v0.1.1 --target HEAD --output dist/release-notes.md
python3 -m unittest discover -s tool -p 'test_*release*.py'
```

替换示例版本和目标提交；Fork 仓库加 `--repository owner/repository`。提交记录回退要求完整 Git 历史与已发布 tag；浅克隆先获取完整历史，并通过 `git fetch origin --tags` 补齐 tag。网络或权限错误会终止解析，不会静默生成备用说明。

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

其他平台工程用于开发验证。iOS 正在适配，最低部署版本为 iOS 15.0；构建通过不代表功能已经完成设备验收。

iOS 使用 macOS、Xcode 和 CocoaPods。项目将 Flutter 插件统一交给 CocoaPods 管理，保留 ML Kit、sherpa 的原生依赖和 Podfile 中的权限宏；暂不启用 Flutter 的 Swift Package Manager 插件迁移。提交 `ios/Podfile.lock` 固定原生依赖。

```bash
# 使用与 pubspec.lock 一致的源，避免本机镜像配置触发重新解析。
PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign --no-pub
```

以上命令生成未签名的 `build/ios/iphoneos/Runner.app`，无需连接设备。`make ios-archive IOS_ARCHIVE_ARGS="--unsigned"` 进一步检查无签名归档。安装设备前须为 Runner 和 ShareExtension 配置同一 Team 和 App Group，再执行签名归档或 `make run-ios DEVICE=<设备 ID>`；不将 Team、证书或 provisioning profile 写入仓库。当前固定的 ML Kit 原生库不支持 Apple Silicon 的 ARM64 模拟器，因此不能用模拟器构建替代 ARM64 真机目标的编译检查。

完整无设备检查使用 `make check-ios`。检查内容、当前证据和后续设备验收清单见 [iOS 适配与验收](ios-development.md)。
