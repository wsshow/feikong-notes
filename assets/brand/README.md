# 非空笔记品牌资产

这里维护小象便签 Logo 的原始图片，以及由它生成的启动器图标和启动页标志。品牌资产与应用内操作图标是两套独立资源。

这些品牌素材由 FKNotes 项目自行创作，母版和生成资源均采用项目的
[MIT License](../../LICENSE)。其他素材的来源与许可见[素材说明](../README.md)。

完整方形画布用于各平台启动器图标；应用内和启动页使用居中裁切版本，保证小尺寸下主体仍然清晰。Android 自适应图标保留原图安全留白，以适配圆形、圆角矩形等系统蒙版。

源文件：

- `fknotes_logo_source.png`：项目自建的 512×512 原始母版，不做手工修改
- `fknotes_icon.png`：生成的 1024×1024 完整应用图标
- `fknotes_mark.png`：生成的 1024×1024 居中裁切品牌标志

替换母版后，在仓库根目录运行：

```sh
./tool/generate_app_icons.sh
```

脚本会统一生成 Android、iOS、macOS、Web、Windows 图标，以及 Android/iOS 启动资源。不要单独手工修改生成的 PNG 或 ICO。
