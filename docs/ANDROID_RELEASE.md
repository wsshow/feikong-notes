# Android 发布指南

Android 在线更新全部使用 GitHub：Actions 构建与验证，Releases 托管安装包和更新说明，`updates` 分支保存应用读取的更新清单。无需另配下载服务器。

公开版本从 `0.1.0+1` 开始；`0.x` 与带预发布后缀的 tag 标记为 Pre-release，同样进入当前更新渠道。每次发布必须递增 `pubspec.yaml` 的构建号，并沿用同一发布证书。已安装较高构建号的内部版本无法直接覆盖安装构建号为 1 的公开测试版。

## 首次配置

在仓库 Actions Secrets 配置：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

仓库和 Release 资源须公开，Actions 需要 `contents: write` 权限，并允许发布任务写入 `updates` 分支。工作流首次发布时自动创建该分支，不需要开启 GitHub Pages。客户端不需要 GitHub Token。

默认清单地址：

```text
https://raw.githubusercontent.com/wsshow/feikong-notes/updates/android/latest.json
```

Actions 根据当前仓库自动生成地址，无需设置 `FKNOTES_UPDATE_MANIFEST_URL` 仓库变量。直接通过 Flutter 编译时也默认使用上述地址；如需关闭更新，可显式传入 `--dart-define=FKNOTES_UPDATE_MANIFEST_URL=`。Fork 构建应指定自己的地址，或使用下文的 Make 参数。

## 发布版本

1. 更新 [pubspec.yaml](../pubspec.yaml) 的版本名和构建号，例如 `0.1.1+2`。
2. 更新 [CHANGELOG](../CHANGELOG.md)，并提交 `docs/releases/<版本名>.md`。该文件同时作为 GitHub Release 正文和应用内 Markdown 更新说明。
3. 提交并推送代码，再推送与版本名一致的 tag，例如：

```bash
git tag v0.1.1
git push origin v0.1.1
```

[tag 工作流](../.github/workflows/release.yml)校验版本、发布说明、发布脚本、格式与静态分析，执行两组分片测试，构建签名通用 APK、ARM64 / ARM32 / x86_64 APK 和 AAB。依赖从 `pub.dev` 下载，保留锁文件哈希校验。APK 和 AAB 检查 Flutter 库中的开发者主目录路径。

所有检查通过后，工作流生成并上传：

```text
fknotes-<版本>+<构建号>-universal-release.apk
fknotes-<版本>+<构建号>-arm64-v8a-release.apk
fknotes-<版本>+<构建号>-armeabi-v7a-release.apk
fknotes-<版本>+<构建号>-x86_64-release.apk
fknotes-<版本>+<构建号>-release.aab
notes.md
latest.json
SHA256SUMS.txt
```

清单中的安装包和说明链接固定到该版本的 Release。Release 发布成功后，工作流读取已发布的 `latest.json`，再提交到 `updates/android/latest.json`，使客户端发现新版本。这个入口兼容当前 0.x 测试版，不依赖 GitHub 的 Latest Release 选择。

发布任务串行运行，较低构建号不能覆盖较高构建号的清单。重跑已发布版本时复用线上清单，不替换公开 APK；相同构建号不允许对应不同清单。若 Release 已成功但清单提交失败，可重跑发布任务。若公开 Release 缺少清单，须修复该发布或使用新版本，不能把不完整资源推送到更新入口。

可选仓库变量 `FKNOTES_UPDATE_MANDATORY=true` 会将本次清单标为必须更新，默认 `false`。仅在确有需要时设置，并在发布后恢复。

## 本地构建与验收

本地构建用于验收，公开发布统一由 tag 工作流完成。首次本地签名配置见 [key.properties.example](../android/key.properties.example)，密钥库及 `android/key.properties` 不进入版本控制。

```bash
make android-release
# Fork 仓库：
make android-release FKNOTES_GITHUB_REPOSITORY=owner/repository
```

脚本在临时目录运行分析与全量测试，构建通用和 ARM64 APK，检查版本、ABI 与开发者路径，然后归档到 `release/android/<版本>/`。与 CI 共用清单生成器、GitHub URL 和产物命名；该命令不上传文件或推进在线清单。`FKNOTES_RELEASE_DATE=YYYY-MM-DD` 和 `FKNOTES_UPDATE_MANDATORY=true|false` 可覆盖本地清单字段。

验收时确认：

- 包名为 `com.fknotes.app`，构建号递增，签名证书与上一版本一致。
- 在下载目录运行 `shasum -a 256 -c SHA256SUMS.txt`，所有文件通过校验。
- 未登录时能访问清单、更新说明和安装包。
- 用上一正式版在真机检查更新、下载、校验，并由 Android 系统安装器确认覆盖安装。

## 清单与安装校验

| 字段 | 约定 |
| --- | --- |
| `app` | 固定为 `fknotes` |
| `version`、`versionCode` | 版本名与所有 APK 共用的构建号 |
| `releaseDate`、`mandatory` | 发布日期与必须更新标记 |
| `changelog` | 该版本 Release 中 `notes.md` 的 HTTPS 地址 |
| `artifacts` | 必含 `android-universal`、`android-arm64-v8a`；CI 另含 `android-armeabi-v7a`、`android-x86_64`。每项包含 HTTPS `url`、字节数 `size` 和 SHA-256 |

客户端按设备 ABI 优先选择分包，无匹配项时使用通用包。安装前原生层检查私有缓存位置、长度、哈希、包名、签名及严格递增的构建号。安装权限与进度展示规则见 [设计规范](../DESIGN.md#检查更新)。

**回滚分发：** 手动将 `updates/android/latest.json` 恢复为此前 Release 中的清单，阻止继续推荐问题版本；保留已公开安装包。已升级设备仍需要更高构建号的修复版。首次迁移时，已经安装且未配置 GitHub 清单的旧客户端需要手动安装新版，或通过原渠道分发迁移版本。
