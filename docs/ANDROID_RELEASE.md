# Android 发布指南

应用内更新使用 `release/android/` 下的正式包和清单。每次发布使用新的语义化版本和更高的 Android 构建号，并沿用现有发布证书，以便用户覆盖安装。

公开版本从 `0.1.0+1` 开始；`0.x` 为测试阶段，在 GitHub 标记为 Pre-release。
构建号从 `pubspec.yaml` 统一读取，每次发布递增，与 Actions 运行次数无关。
已安装较高构建号的内部版本不能直接覆盖安装这个构建号为 1 的公开测试版，
内部版本继续沿用原开发仓库的升级渠道。

## 1. 准备版本、签名和更新说明

1. 确认工作区内容属于本次发布。在 [pubspec.yaml](../pubspec.yaml) 更新版本，例如 `0.1.0+1`。前半部分是 Android `versionName`，后半部分是 `versionCode`，须大于此前公开发布的构建号。
2. 确认本机签名配置可用。首次配置时，将 [key.properties.example](../android/key.properties.example) 复制到 `android/key.properties`，填写密钥库位置、别名及密码。密钥库与配置文件留在 Git 忽略范围内，并单独保管。
3. 更新 [CHANGELOG](../CHANGELOG.md)，并写好 `release/android/0.1.0/notes.md`。客户端会直接渲染该 Markdown，内容以用户可感知的变化为主。发布命令会检查更新说明是否为空。

## 2. 构建并归档

在 Git 工作区根目录运行，将示例地址换成实际的公开 HTTPS 发布目录。

```bash
make android-release FKNOTES_RELEASE_BASE_URL=https://example.com/releases/fknotes
```

脚本在独立临时目录构建，从原目录读取签名配置。静态分析与全量测试通过后，分别生成通用 APK 和 ARM64 APK，再检查版本、ABI 与各架构 Flutter 库中的开发者主目录路径。两包使用同一个构建号。通过检查后才归档并生成 SHA-256 与更新清单。

```text
release/android/
├── latest.json
└── <版本>/
    ├── fknotes-<版本>.apk
    ├── fknotes-<版本>.apk.sha256
    ├── fknotes-<版本>-arm64-v8a.apk
    ├── fknotes-<版本>-arm64-v8a.apk.sha256
    └── notes.md
```

| 参数 | 默认值与用途 |
| --- | --- |
| `FKNOTES_RELEASE_BASE_URL` | 必填。用于生成 APK 和更新说明的公开 HTTPS 地址 |
| `FKNOTES_UPDATE_MANIFEST_URL` | `<发布目录>/latest.json`。编译进客户端的更新清单地址 |
| `FKNOTES_UPDATE_MANDATORY` | `false`。严重安全问题或旧客户端无法使用时才启用 |
| `FKNOTES_RELEASE_DATE` | 构建当天。可用 `YYYY-MM-DD` 覆盖 |

启用应用内更新的构建会嵌入清单地址。更换发布地址时，确认客户端配置与清单上传位置一致，再完整构建。普通开发构建默认关闭应用内更新。

## 3. 验收并上传

- 核对包名 `com.fknotes.app`、版本号、构建号、上一版证书，以及 `INTERNET` 和 `REQUEST_INSTALL_PACKAGES` 权限。
- 校验两个 APK 的文件大小和 SHA-256。实测值、旁路校验文件与 `latest.json` 应一致。

```bash
(cd release/android/0.1.0 && shasum -a 256 -c *.apk.sha256)
```

1. 上传完整版本目录。用未登录的客户端确认更新说明与两个 APK 地址可以访问。
2. 最后上传 `latest.json`，启用该版本更新。版本目录使用不可变缓存，清单使用短缓存或禁用缓存。
3. 用上一正式版在真机验证发现更新、下载、校验和覆盖安装。最终安装由 Android 系统安装器确认。

**回滚。** 将线上 `latest.json` 恢复到上一稳定版本，阻止继续分发问题版本。已升级设备需要更高构建号的修复版。已公开的版本目录保留原件，修复版使用新的版本号和构建号。

## 清单与安装校验

| 字段 | 约定 |
| --- | --- |
| `app` | 固定为 `fknotes` |
| `version`、`versionCode` | 版本名与两个 APK 共用的构建号 |
| `releaseDate`、`mandatory` | 发布日期与强制更新标记 |
| `changelog` | 该版本 `notes.md` 的 HTTPS 地址 |
| `artifacts` | `android-universal` 与 `android-arm64-v8a`，各含 HTTPS `url`、字节数 `size`、64 位小写十六进制 `sha256` |

清单由脚本生成。ARM64 设备优先选择小包，其余设备使用通用包。安装前原生层校验私有缓存位置、文件长度、哈希、包名、签名及严格递增的构建号。需要安装权限时，客户端引导至 Android 的“安装未知应用”设置。更新提示和进度的展示规则见 [设计规范](../DESIGN.md#检查更新)。

## GitHub Release

[tag 工作流](../.github/workflows/release.yml)是独立的发布渠道，按 ABI 构建 APK 和 AAB，并将产物及 `SHA256SUMS.txt` 上传到 GitHub Release。应用内更新使用上面的 `release/android/` 流程。

CI 从 `pub.dev` 下载锁定版本的依赖，并保留 `--enforce-lockfile` 哈希校验。静态分析、两组分片测试与 Android 签名构建在 Ubuntu 上运行。测试与分析并行，分析通过即可打包，发布必须等待所有测试和构建成功。界面测试验证布局与交互，不做跨平台逐像素截图比较。

首次使用在仓库的 Actions Secrets 配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD` 和 `ANDROID_KEY_ALIAS`。如需在这些产物中启用应用内更新，设置仓库变量 `FKNOTES_UPDATE_MANIFEST_URL`。

准备好测试版后，推送 `v0.1.0` tag 会触发首次构建。工作流要求 tag 去掉 `v`
后与 `pubspec.yaml` 的版本名一致，并读取其中的构建号；首次发布即为 `0.1.0+1`。
所有 `v0.*` 以及包含 `-beta.1` 等预发布后缀的 tag 都标记为 Pre-release。
无预发布后缀的 `v1.0.0` 及以后版本按正式版发布。跨渠道覆盖安装前，
应检查最终产物的构建号和签名。
