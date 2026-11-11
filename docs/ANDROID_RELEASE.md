# Android 发布指南

Android 在线更新全部使用 GitHub：Actions 构建与验证，Releases 托管安装包和更新说明，`updates` 分支保存应用读取的更新清单。无需另配下载服务器。

公开版本从 `0.1.0+1` 开始；`0.x` 与带预发布后缀的 tag 标记为 Pre-release，同样进入当前更新渠道。每次发布必须递增 `pubspec.yaml` 的构建号，并沿用同一发布证书。已安装较高构建号的内部版本无法直接覆盖安装构建号为 1 的公开测试版。

## 首次配置

在仓库 Actions Secrets 配置：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

仓库和 Release 资源须公开，发布任务的 Actions Token 需要 `contents: write` 权限，以读取草稿、发布资源并写入 `updates` 分支。工作流首次发布时自动创建该分支，不需要开启 GitHub Pages。客户端不需要 GitHub Token。

默认清单地址：

```text
https://raw.githubusercontent.com/wsshow/feikong-notes/updates/android/latest.json
```

Actions 根据当前仓库自动生成地址，无需设置 `FKNOTES_UPDATE_MANIFEST_URL` 仓库变量。直接通过 Flutter 编译时也默认使用上述地址；如需关闭更新，可显式传入 `--dart-define=FKNOTES_UPDATE_MANIFEST_URL=`。Fork 构建应指定自己的地址，或使用下文的 Make 参数。

## 发布版本

### 已发布分包的版本号限制

0.2.0 发布后的产物核验发现：Flutter 的 `--split-per-abi` 会给 APK 的实际 `versionCode` 添加 ABI 偏移，而当前更新清单仍使用 `pubspec.yaml` 的构建号。已核对 ARM64 包：0.1.0 为 `2001`，0.2.0 为 `2002`；0.2.0 的 `latest.json` 则为 `2`。二者不能直接用于同一套更新比较和安装校验，因此当前不能将分包的应用内更新视为已验证可用。

现阶段从 GitHub Release 手动下载与已安装版本**同架构**的 APK 升级。已校验上述两个 ARM64 包的包名、签名证书一致，实际版本号递增；这只是安装条件检查，不代替设备上的升级与数据保留验收。不要卸载旧应用来处理版本号问题，升级前先导出应用内备份。

下一次 Android 发布前，必须统一 APK / AAB 与更新清单中的实际版本号，并选择高于所有已发布 APK 实际版本号的新构建号，增加产物版本号校验。不能仅把构建号从 `2` 改为 `3`，也不能为修正此问题覆盖已公开的 0.2.0 安装包或校验文件。

### 准备与触发

1. 更新 [pubspec.yaml](../pubspec.yaml) 的版本名和构建号，例如 `0.1.1+2`。
2. 在 GitHub Releases 中为目标 tag（例如 `v0.1.1`）保存草稿，根据上一个发布 tag 到目标提交的变更撰写面向用户的中文正文。正文格式见[开发与构建](development.md#更新说明)。仓库不再提交逐版本说明文件，`CHANGELOG.md` 仅作为 Release 入口。
3. 完成校验并提交代码。取得本次推送、打 tag 和发布的明确授权后，再推送代码及与版本名一致的 tag，例如：

```bash
git tag v0.1.1
git push origin v0.1.1
```

[tag 工作流](../.github/workflows/release.yml)校验版本、发布脚本、格式与静态分析，执行两组分片测试，构建签名通用 APK、ARM64 / ARM32 / x86_64 APK 和 AAB。依赖从 `pub.dev` 下载，保留锁文件哈希校验。APK 和 AAB 检查 Flutter 库中的开发者主目录路径。

在锁定依赖后，先运行 `flutter build apk --release --config-only` 生成 Release 专用插件注册文件，并确认锁文件未变化，再使用 `--no-pub` 构建 APK / AAB；否则 Flutter 会保留包含开发依赖 `integration_test` 的注册文件，导致 Release Java 编译失败。

发布同时调用 iOS 无签名构建与归档检查，全部通过后才公开 Release。此流程无需 Apple 签名账号，检查后额外打包实验性未签名 IPA，附带[自行签名安装教程](ios-installation.md)、权限模板和构建信息；用户仍需自行签名，不能直接安装，也不能把构建检查视为 iPhone 真机验收。

### 恢复未完成的发布

已有 tag 的发布被取消或需要修正打包流程时，可从最新 `main` 手动运行 `release.yml`，输入原 tag：

```bash
gh workflow run release.yml --ref main -f tag=v0.2.0
```

此路径保留原 tag：所有平台应用都检出该 tag 的源码，打包脚本和安装教程取本次工作流固定提交。iOS 的 `ios-build-info.json` 记录两者；改动应用代码应使用新版本，不借此替换已发布应用。所有检查通过才发布，已公开的 Release 重跑仍保留原正文和资源。

### 说明来源与兼容路径

发布任务通过 `tool/release_notes.py` 分页读取 GitHub Releases，并以 tag 精确匹配当前版本：

- 对应草稿有正文：读取正文作为本次发布说明。
- 没有对应 Release，或对应草稿正文为空：从 Git 历史生成备用说明，使用中文标题并明确标注自动生成、未经人工整理，逐条展示提交短哈希和原始标题。
- 备用说明的起点是当前目标提交历史中最近的已发布版本 tag（包括 Pre-release），排除草稿、未发布 tag、其他分支上的版本和当前 tag。范围为该 tag 之后到目标提交；首次发布无可用起点时使用截至目标提交的完整历史；范围为空时明确说明没有新增提交。
- 查询失败、权限不足、浅克隆或缺少已发布 tag 时终止，不把这些错误视为没有草稿。CI 获取完整历史和 tag；本地需登录具有仓库写权限的 `gh` 账号并补齐历史和 tag。
- 当前版本已经发布：重跑保留原正文与资源，并复用线上清单；已发布正文为空则报错，不生成替代内容。

解析后的正文同时用于 GitHub Release 页面、`notes.md` 附件和应用内更新说明。发布已有草稿时也会用该正文更新 Release，确保空草稿的备用说明与附件一致；说明仅落盘到临时目录或忽略的构建目录。首次创建与发布草稿均按相同规则标记 `0.x` 和带后缀版本为 Pre-release。

草稿只在发布任务开始时读取一次；不要在任务运行中手动发布或修改该草稿。人工正文以该次快照为准。GitHub 的草稿访问规则见 [List releases](https://docs.github.com/en/rest/releases/releases#list-releases)。

所有检查通过后，工作流生成并上传：

```text
fknotes-<版本>+<构建号>-universal-release.apk
fknotes-<版本>+<构建号>-arm64-v8a-release.apk
fknotes-<版本>+<构建号>-armeabi-v7a-release.apk
fknotes-<版本>+<构建号>-x86_64-release.apk
fknotes-<版本>+<构建号>-release.aab
notes.md
latest.json
fknotes-<版本>-ios-unsigned.ipa
ios-installation.md
ios-build-info.json
ios-signing-entitlements.plist
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

准备已登录的 GitHub CLI（`gh`）及完整 Git 历史和 tag。脚本先在原始工作区解析一次更新说明，本地备用范围截至 `HEAD`；随后把正文传入不含 `.git` 的临时构建目录，避免构建期间再次读取草稿。确保准备归档的代码已提交，否则备用说明不包含未提交的改动。

脚本在临时目录运行分析与全量测试，构建通用和 ARM64 APK，检查版本、ABI 与开发者路径，然后归档到 `release/android/<版本>/`。与 CI 共用说明解析器、清单生成器、GitHub URL 和产物命名；该命令只读取 GitHub，不上传文件或推进在线清单。`FKNOTES_RELEASE_DATE=YYYY-MM-DD` 和 `FKNOTES_UPDATE_MANDATORY=true|false` 可覆盖本地清单字段。

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
