# ML Kit Text Recognition 1.0.2 — 中文 SwiftPM 接入

来源为 `https://pub.dev/api/archives/google_mlkit_text_recognition-1.0.2.tar.gz`，归档 SHA-256 为 `3c74697ee8cdcd10d82a98bc60ff0107251f1d44aa385e6056a8031fed86ba6d`。MIT 许可保留在 LICENSE，上游说明保留在 UPSTREAM_README.md。仅收录运行时 Dart、Android、iOS 源码、包清单与许可（不收录上游未被 SwiftPM 声明的 OCR 资源副本，资源改由校验和固定的构建脚本下载），不修改 Pub 缓存。

上游 1.0.2 的 iOS Swift 包只链接拉丁文字识别；请求 Chinese 时会静默回退拉丁文字识别。本项目对这两处打补丁：

- Package.swift 显式依赖同版本 `google-mlkit-swiftpm` 9.0.2 的 MLKitTextRecognitionChinese 产品。
- Swift 插件对中文模块采用必需导入，移除中文分支的拉丁文字回退。缺失中文依赖会在编译时失败。

`upstream-sha256.json` 记录引入时原文件摘要，`chinese-spm.patch` 可以在上游归档对应路径上通过 `patch -p1` 重放。Dart 协议与 Android 实现保持上游原样。iOS 的 SwiftPM 二进制来自社区维护的 d-date/google-mlkit-swiftpm 重打包仓库，不把它描述为 Google 官方的模拟器二进制发布。

中文/拉丁模型资源由 tool/prepare_ios_ocr_resources.py 从该版本发布资源下载并校验 SHA-256 后打包；静态 SDK 的隐私清单原样保留。源码依赖及二进制校验和还由提交的 Package.resolved 和上游包清单锁定。

升级时重新对比本补丁、许可证和资源校验值，运行 `flutter test integration_test/ios_ocr_smoke_test.dart -d <模拟器 ID>`，同时检查 Android 构建和 iOS 未签名归档。不能只以编译通过替代中文识别验证。
