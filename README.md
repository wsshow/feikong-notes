<p align="center">
  <img src="assets/brand/fknotes_mark.png" width="128" height="128" alt="非空笔记 Logo">
</p>

<h1 align="center">非空笔记 · Feikong Notes</h1>

<p align="center">
  本地优先的多媒体笔记，让文字、声音和灵感有处安放。
</p>

<p align="center">
  无需账号 · 多媒体记录 · 本地 AI · 自选同步
</p>

<p align="center">
  <a href="#主要功能">主要功能</a> ·
  <a href="#获取与体验">获取与体验</a> ·
  <a href="#数据与隐私">数据与隐私</a> ·
  <a href="#从源码运行">从源码运行</a> ·
  <a href="LICENSE">MIT License</a>
</p>

非空笔记是一款基于 Flutter 构建的笔记应用。打开即可记录，笔记与附件默认保存在设备上。
你可以用文字、图片或录音留下想法，通过搜索、标签和日历找回内容，
再按需使用设备端识别、笔记助手和自己配置的云存储。

## 主要功能

| 场景 | 能做什么 |
| --- | --- |
| 随手记录 | 富文本编辑、自动保存、撤销，以及图片、录音、视频和文件引用 |
| 找回内容 | 按标题、正文、标签与附件文字搜索，通过标签分组、日历和提醒回顾笔记 |
| 图片与语音 | 在设备端识别图片文字、转写录音、实时听写和朗读笔记 |
| 笔记助手 | 使用本地模型，或连接自己配置的在线模型，辅助摘要、改写、整理与笔记问答 |
| 整理与分享 | 独立文件库、附件预览、接收 Android 系统分享，以及生成笔记分享图 |
| 数据管理 | 应用锁、独立认证的隐私工作区、完整备份恢复，以及手动 S3 / WebDAV 同步 |

支持中文、英文和多套主题。完整功能范围见[产品说明](PRODUCT.md)。

## 获取与体验

目前可通过[源码运行](#从源码运行)体验。公开安装包发布后，会放在本仓库的 GitHub Releases，
并附带 SHA-256 校验文件。首次公开版本为 `0.1.0+1`。

- **主要平台：Android 手机。** 仓库内的 iOS、macOS、Windows、Linux 和 Web 工程用于开发验证，尚未作为正式支持平台交付。
- **本地 AI：优先使用 Android ARM64 设备。** 语言模型需要额外下载，存储和内存要求因模型而异；应用内提供模型体积和内存建议。
- **基础记录无需配置 AI。** 可以先记录和整理笔记，再选择本地模型、在线模型或云同步。
- **同步由你控制。** S3 / WebDAV 需要自行配置并手动触发；双端修改冲突时，由你选择保留的数据版本。

模型与设备要求见[本地语言模型](docs/local-llm.md)，同步方式见[备份与手动云同步](docs/cloud-sync.md)。

## 数据与隐私

本地优先是应用的数据组织方式。使用前，也请了解当前测试版的边界：

| 项目 | 当前行为 |
| --- | --- |
| 笔记与附件 | 默认存储在应用私有目录，无需注册账号 |
| 应用锁与隐私工作区 | 通过系统认证保护应用内访问；笔记数据库与附件未额外做应用级加密 |
| 备份与同步快照 | 完整归档未加密，可包含隐私笔记；生成或导出含隐私内容的备份、上传这类快照前需要认证 |
| 在线 AI 与联网工具 | 按配置和授权访问外部服务；发送的上下文会交由对应服务处理 |
| 密钥与同步凭据 | 在线模型 API Key 使用系统安全存储；当前云同步凭据仍保存在应用私有配置文件中 |

图片文字识别目前使用随应用打包的 **Google ML Kit**。图片与识别结果在设备端处理，
但 SDK 会发送性能与使用指标，详见 [Google 官方说明](https://developers.google.com/ml-kit/terms)。
当前尚未实现可靠的遥测关闭方案或完成 OCR 引擎替换。

模型下载、配置了更新地址的构建、用户启用的在线服务等也会产生网络请求。
更多细节见[产品数据原则](PRODUCT.md#数据与隐私)、[隐私工作区](docs/private-workspace.md)和[智能体说明](docs/fknotes-harness.md)。

## 从源码运行

### 环境

- Flutter **3.47.2**，与发布 CI 一致，使用其自带的 Dart SDK。
- Android SDK **36**、JDK **17** 和 Make。
- 一台开启 USB 调试的 Android 手机，或 Android 模拟器。

下载或克隆本仓库后，进入包含 `pubspec.yaml` 的项目根目录：

```bash
# 检查环境并安装锁定的依赖
flutter doctor
flutter pub get --enforce-lockfile

# 查看设备；将下一条命令中的示例 ID 替换为实际设备 ID
flutter devices
make run-android DEVICE=emulator-5554
```

首次 Android 构建会下载并校验固定版本的 MNN 原生运行库，需要网络连接。
普通 Debug 构建无需配置项目的正式发布签名。
开发流程和常见命令见[开发指南](docs/development.md)。

### 本地检查

在项目根目录运行：

```bash
flutter pub get --enforce-lockfile
(cd packages/fknotes_harness && dart pub get --enforce-lockfile)
dart format --output=none --set-exit-if-changed lib test packages/fknotes_harness/lib packages/fknotes_harness/test
flutter analyze --no-pub
flutter test --no-pub
(cd packages/fknotes_harness && dart analyze && dart test)
git diff --check
```

签名、APK / AAB 构建、版本标签和发布流程见 [Android 发布指南](docs/ANDROID_RELEASE.md)。

## 文档导航

| 想了解什么 | 从这里开始 |
| --- | --- |
| 产品定位与功能范围 | [产品说明](PRODUCT.md) |
| 页面交互、主题与视觉规范 | [设计规范](DESIGN.md) |
| 开发环境与代码结构 | [开发指南](docs/development.md) |
| 本地模型和笔记助手 | [本地语言模型](docs/local-llm.md) · [智能体说明](docs/fknotes-harness.md) |
| 数据管理与恢复 | [隐私工作区](docs/private-workspace.md) · [备份与手动云同步](docs/cloud-sync.md) |
| 其他功能专题 | [完整文档索引](docs/README.md) |

## 反馈与贡献

欢迎通过本仓库的 Issues 反馈问题、提出建议，或提交 Pull Request。

- **报告问题：** 请提供应用版本、设备型号、Android 版本、复现步骤和预期行为；涉及本地模型时，附上模型名称。
- **提交改动：** 说明解决的问题与验证方式。较大的功能或架构调整，建议先通过 Issue 讨论范围。
- **保护个人数据：** 截图和日志请先脱敏，不要公开真实笔记、完整备份、API Key、同步凭据或本机个人路径。

## 许可与致谢

项目原创代码、文档和自建视觉素材采用 [MIT License](LICENSE)，
包括 `packages/fknotes_harness`。素材来源与许可范围见[素材说明](assets/README.md)。

感谢以下项目及其他依赖为非空笔记提供支持：

- **Flutter Quill：** 富文本编辑基础；[兼容补丁与上游来源](third_party/flutter_quill/README.md)，[MIT 许可](third_party/flutter_quill/LICENSE)。
- **Lucide / Feather：** 操作图标；[来源说明](third_party/lucide/README.md)，[ISC / MIT 许可](third_party/lucide/LICENSE)。
- **Adobe 思源宋体：** 纸张主题字体；[来源说明](assets/fonts/source_han_serif/README.md)，[SIL OFL 1.1 许可](assets/fonts/source_han_serif/LICENSE.txt)。

第三方代码、字体、原生运行库和模型继续遵循各自的许可证或服务条款，
不因本项目采用 MIT 而变更。
