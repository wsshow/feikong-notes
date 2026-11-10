# 接收 Android 系统分享

在其他应用选择“分享 → 非空笔记”，查看摘要后点击“保存为新笔记”。内容保存到普通笔记并打开现有编辑器；原来打开的笔记不会被替换。首次启动和应用已经运行时使用相同流程，Debug 与正式包均注册分享入口。

## 内容与限制

- 文字、网页链接，以及图片、音频、视频、PDF 等文件；支持一次分享多个附件和“图片＋说明文字”。
- 网页仅保存发送方提供的文字、标题和链接，不自动访问网址或抓取正文。
- 文本文件按 MIME 或 `.txt`、`.text`、`.log`、`.md`、`.markdown` 扩展名识别。符合内联条件的文件写入可编辑正文，富 Markdown 转成 Delta，普通文字按原文保存。转换细节见[编辑器](editor.md#markdown-导入)。
- 文本文件支持 UTF-8（含 BOM）及带 BOM 的 UTF-16 大小端编码，保留中文、换行与链接；多文件分享按原顺序插入正文或附件，分享说明仍在最前面。
- 正文与文本文件共用 100,000 个 UTF-16 字符的导入额度。空文件、仅含空白、超过剩余额度、含二进制控制字符或无法可靠解码的文件完整保留为附件，不截断、不猜测编码、不丢弃原文件。
- 可解码且不超过 20 MB 的图片沿用现有图片处理与缩略图流程。支持的音视频显示为已有媒体卡片；其他格式及无法解码的图片保留为文件附件，点击可交给其他应用打开。
- 每次最多 20 个文件，单文件最多 100 MB，总文件大小最多 200 MB；文字最多 100,000 个 UTF-16 字符。标题最多保留 500 个字符。
- 最多暂存 8 次尚未处理的分享；达到限制时提示先处理已有内容再重新分享。未获读取授权、文件缺失、超限或中断的分享不会只保存其中一部分。

## 生命周期与安全

1. `MainActivity` / `DebugMainActivity` 以 `singleTask` 接收 `ACTION_SEND` 和 `ACTION_SEND_MULTIPLE`。同一 Flutter 导航栈继续使用，Activity 状态恢复不会重放已处理的启动 Intent。
2. 原生单线程队列读取 `EXTRA_TEXT`、`EXTRA_SUBJECT`、`EXTRA_STREAM`，兼容仅有 HTML 或 ClipData 的发送方；避免把网页分享预览缩略图当附件。
3. 文件仅从有明确读取授权的外部 `content://` URI 读取。拒绝 `file://`、本应用的 Provider 和任意路径；原文件名仅用于显示，落盘名称由应用生成。复制时按实际字节计数，不依赖发送方申报的大小。
4. 原始分享存放于 Android `noBackupFilesDir/incoming_shares`，不进入笔记备份或云同步。开启应用锁时，内容先暂存，等待解锁后才展示确认面板。接收过程中不记录正文或文件名到日志。
5. 确认后附件复制进现有 `notes/*` 管理目录，笔记图与附件元数据在一次 SQLite 事务中保存。新笔记 ID 固定为该次分享 ID；保存后、清理暂存前进程退出，重试不会重复创建笔记。
6. 导入失败会清理本次新建的附件文件，保留原暂存供重试。保存后清理暂存；取消只清理当前分享。中断的原生复制在恢复后提示重新分享，不生成不完整笔记。
7. 文件附件使用范围限定为 `notes/files/` 的 FileProvider，通过用户点击、临时只读授权交给外部应用，不自动执行文件。

## 验证

- Flutter：`flutter test --no-pub test/incoming_share_service_test.dart test/incoming_share_coordinator_test.dart test/shared_note_import_service_test.dart`
- Android JVM：在 `android/` 下运行 `./gradlew :app:testDebugUnitTest --tests com.fknotes.app.IncomingShareInboxTest`。使用 Robolectric，不需要操作模拟器界面。
- 自动化覆盖编码与额度、Markdown 转换、混合顺序、文件回退、分享队列、锁定、幂等和失败重试。
- 真机验收覆盖浏览器链接、单图和多图、PDF、音频，以及冷启动、后台、前台、应用锁和取消分享。

实现依据：[Android 接收分享数据](https://developer.android.com/develop/ui/compose/sharing/receive)、[ContentResolver 安全](https://developer.android.com/privacy-and-security/risks/content-resolver)、[不可信文件名](https://developer.android.com/privacy-and-security/risks/untrustworthy-contentprovider-provided-filename)。
