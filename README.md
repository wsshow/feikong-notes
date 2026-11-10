# 非空笔记（FKNotes）

一款本地优先的多媒体笔记应用。打开即可记录，无需账号。笔记和附件默认保存在设备上。

**当前阶段**　准备发布首个开源测试版 `0.1.0`，发布验收面向 Android 手机。

## 能做什么

- **记录与查找**　富文本、图片、录音、视频和文件引用，支持搜索、标签、日历和提醒。
- **设备端处理**　图片文字识别、录音转写、实时听写和朗读均在本机运行。
- **整理与分享**　独立文件管理器、本地预览、接收 Android 系统分享，以及生成笔记分享图。
- **笔记助手**　使用本地模型，或配置自己的在线模型和 API Key。在线服务会处理发送给它的内容。
- **管理数据**　应用锁和独立认证的隐私工作区，支持完整备份、恢复，以及手动 S3 / WebDAV 同步。

## 快速运行

准备 Flutter 3.47.2（与发布 CI 一致）、Android SDK 36、JDK 17 和 Make。连接 Android 设备或启动模拟器后，在项目根目录运行：

```bash
make doctor
make devices
make run-android DEVICE=emulator-5554
```

将示例设备 ID 换成 `make devices` 列出的值。环境设置和提交前检查见[开发指南](docs/development.md)。

## Android 发布

公开版本从 `0.1.0+1` 开始，`0.x` 发布在 GitHub 标记为测试版（Pre-release）。
版本记录见 [CHANGELOG](CHANGELOG.md)。

正式 APK、SHA-256 校验文件和更新说明归档到 `release/android/<版本>/`，更新清单位于 `release/android/latest.json`。签名、构建、验收和上传顺序见 [Android 发布指南](docs/ANDROID_RELEASE.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [产品说明](PRODUCT.md) | 功能范围、平台边界和数据原则 |
| [设计规范](DESIGN.md) | 导航、页面交互、视觉和验收要求 |
| [开发指南](docs/development.md) | 开发环境、调试、测试和代码位置 |
| [文档索引](docs/README.md) | 编辑器、资料管理、模型、隐私和主题等专题 |

## 许可

项目原创代码、文档及自建视觉素材采用 [MIT License](LICENSE)，包括
`packages/fknotes_harness`。素材来源与许可范围见[素材说明](assets/README.md)。

第三方代码、字体、原生运行库和模型继续遵循各自的许可证或服务条款，
不因本项目采用 MIT 而变更。仓库内保留了 [Flutter Quill](third_party/flutter_quill/LICENSE)、
[Lucide / Feather](third_party/lucide/LICENSE) 和
[思源宋体](assets/fonts/source_han_serif/LICENSE.txt) 的原始许可。
