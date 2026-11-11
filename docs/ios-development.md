# iOS 适配与验收

iOS 当前处于适配阶段，尚未作为正式支持平台发布。本阶段保留与 Android 相同的笔记格式、模型文件校验、隐私授权和默认 M4A 录音；暂不进行真机验收。

## 本地检查

需要 macOS、Xcode（含 iOS SDK）、Flutter 3.47.2、CocoaPods 和 Python 3。最低部署目标为 iOS 15.0。插件采用 CocoaPods，Dart 与原生依赖分别锁定在 `pubspec.lock` 和 `ios/Podfile.lock`。LiteRT-LM 使用 `third_party/litert_lm` 中固定 0.14.0 的官方 Swift 包装层与校验和锁定的 iOS 二进制；插件仍由 CocoaPods 管理。不要通过升级依赖或修改 Pub 缓存绕过构建错误。

```bash
make check-ios
```

该目标会按锁文件获取依赖，执行只读格式检查、静态分析、应用及 Harness 测试、原生音频/分享/提醒回归、原生文案与 SDK 源码一致性检查、CocoaPods deployment 安装、未签名 Release 构建和原生能力打包检查，并生成隐私声明清单。不会连接设备、写入签名账号或发布应用。

`.github/workflows/ios.yml` 在相关 Pull Request 或手动触发时执行同一目标，再验证无签名归档。工作流无需签名密钥，只有仓库读取权限；本地检查通过不代表远端 CI 已运行。

单独检查已构建的产物：

```bash
python3 tool/verify_ios_bundle.py build/ios/iphoneos/Runner.app
python3 -m unittest discover -s tool -p 'test_ios_*.py'
```

打包检查确认 iPhone ARM64、MNN 实际 LLM 实现及 FFI 导出、sherpa 离线/流式识别与 TTS 创建/销毁导出、中文 OCR 资源和权限用途声明。符号检查使用 dyld 加载器导出表，避免将 dSYM 中存在但运行时不可查找的接口误判为可用；归档保留全局导出名供 Dart FFI 查找。它不能证明模型能加载、权限弹窗正常或推理质量合格。

当前 ML Kit 固定原生库缺少 Apple Silicon ARM64 模拟器支持；主机音频回归使用 macOS AVFoundation 编译并执行与 Runner 相同的解码代码，不依赖模拟器，也不等于 iPhone 音频验收。

## 已完成的代码与构建检查

| 能力 | 当前证据 | 仍需验证 |
| --- | --- | --- |
| iOS 构建 | 未签名 ARM64 Release 构建通过，原生 Pod 锁定 | 签名安装、冷启动与升级安装 |
| 录音转写输入 | 两端保留 M4A / AAC；iOS AVFoundation 转 16 kHz、16 bit、单声道 WAV；合成 M4A 单/双声道、失败、取消、原文件保留测试 | 麦克风、真实编码、来电/蓝牙中断、长音频及取消中途解码 |
| 模型与备份导入 | 文件类型满足 iOS 插件契约，保留校验及取消流程 | Files / iCloud Drive 下载中的文件、大模型文件、多文件选择 |
| 文件与备份另存 | iOS Files 导出，成功/取消独立返回；临时副本清理；Flutter 通道回归 | 原生选择器交互、后台切换、失败磁盘、隐私认证后的导出 |
| OCR | 中文识别 Pod 与模型资源已打包 | 中文照片/截图、方向、错误反馈及离线识别 |
| 语音识别与朗读 | sherpa iOS 原生库及创建/销毁符号已打包；麦克风权限宏开启 | SenseVoice、Zipformer、Kokoro 的真实加载、识别/合成和音频路由 |
| LiteRT-LM | 0.14.0 Swift SDK、Metal/CPU、文本/图像/音频、流式输出、取消、卸载及指标接入；未签名构建和运行库生命周期符号检查通过 | 模型实际加载、多模态输出、GPU 回退、长上下文、内存压力 |
| MNN | LLM 实现及 FFI 已链接，通用引擎测试保留 | CPU/Metal、文本/图像、取消、内存压力和后台释放 |
| 编辑器图片拖入 | iOS UIDropInteraction 复用 Delta 插入协议；10 张 / 单张 20 MB；流式复制、回收临时文件、锁定/遮挡/非当前路由拒绝导入 | 跨应用拖拽、拖入位置、iPad 多窗口手势与安全区 |
| 系统分享接收 | 独立 Share Extension + App Group 收件箱；文字、链接和附件；原子入队、限额、取消、损坏项可丢弃；复用解锁后确认导入 | 签名后的 App Group、Safari/照片/Files 分享、扩展被系统终止、磁盘不足 |
| 笔记提醒 | UserNotifications 权限、每篇一条、修改/删除、恢复暂停及重新调度、冷/热启动待跳转；只读 SQLite 与路由回归通过 | 通知投递、点击、拒绝权限、时区/系统时间变化、64 条容量 |
| 数据与在线助手 | 共用数据、权限和协议层测试 | Android ↔ iOS 备份、同步冲突、Keychain、系统认证与联网 |

LiteRT-LM 在 iOS 中为进程内运行，不能像 Android 独立服务一样隔离原生崩溃。SDK 0.14.0 的 Swift 对话 API 未公开逐请求 `maxNewTokens` 设置；目前与现有 Android 接入一样由引擎上下文容量、EOS 与请求超时约束，不声称严格逐请求 token 上限。

iOS 提醒始终显示通用内容，不把标题、正文或隐私空间信息存进系统通知。新增提醒超过 64 条原生待调度容量时，编辑器解释原因并回滚；从 Android 恢复更多提醒时安排最近 64 条，后续在前台同步补充。长期不打开应用时，超出窗口的提醒不会自动补排。提醒点击继续通过应用锁与隐私空间授权，过期、已删除或已修改的通知不导航。

分享扩展只暂存输入，不读取笔记数据库或凭据，不自动启动主应用。用户打开应用并解锁后确认保存，保留原有幂等导入与普通笔记空间边界。每批最多 20 个附件、单文件 100 MB、合计 200 MB、正文 10 万 UTF-16 单位，最多暂存 8 批；中断的临时批次在一小时后清理。附件使用流式复制，完成 manifest 后才原子入队。文件附件的外部打开使用 iOS 文档预览/操作菜单。

签名时在 Xcode 项目级配置 `FKNOTES_BUNDLE_ID`（默认 `com.fknotes.app`），Runner 和 ShareExtension 使用同一个 Team；两个 App ID 都启用同一 `FKNOTES_APP_GROUP`（默认 `group.$(FKNOTES_BUNDLE_ID)`）。扩展标识自动为主应用 ID 加 `.ShareExtension`。未签名构建只能检查扩展打包与配置一致，不能证明共享容器可用。

## iOS 后台行为

进入 hidden / paused 时取消前台计算；权限弹窗引起的短暂 inactive 不取消推理和下载。系统挂起前的释放仍需设备实测，尤其是正在原生初始化的大模型。

| 能力 | 离开前台时 | 返回后 |
| --- | --- | --- |
| 本地助手 | 取消生成并卸载模型，释放推理占用 | 用户再次发起时加载 |
| 模型下载 | 立即关闭请求，保留已写入 `.part` 文件 | 用户继续下载，沿用 Range 与完整性校验 |
| 音频转写 / 结束后精修 | 取消解码或识别，保留原始 M4A；不把中断标记为完成 | 用户重新发起转写 |
| 实时听写 | 停止采集和识别，不再启动精修；保留已识别和当前部分文字 | 文字留在输入框，可继续编辑或重新听写 |
| 录音 | 沿用编辑器的暂停与自动保存 | 用户决定继续或完成录音 |
| 朗读 / 音频 / 视频 | 停止朗读与音频；视频沿用页面暂停 | 用户手动播放 |
| 云同步 / 在线请求 | 沿用手动触发与现有网络错误处理，无后台常驻保证 | 网络超时后可重试；冲突规则不变 |

前台租约、HTTP 中断保留断点、推理取消/卸载以及听写保留文字有自动回归；音频路由、系统挂起和实际原生资源回收继续留待真机验收。

## 数据与系统界面

- 启动时将应用的 Application Support 根目录标记为不参与系统备份；分享收件箱同样排除。笔记跨设备迁移继续使用应用的手动备份/同步，不能依赖 iCloud 系统恢复保留这些数据。
- 沿用 Keychain `unlocked_this_device` 保存凭据，设备锁定时不可读，不随备份迁移到其他设备。恢复到新设备后重新填写在线服务凭据；Keychain 的卸载保留行为由系统管理。
- 本机文件沿用 iOS 文件保护，并显式设置受管根目录的 `completeUntilFirstUserAuthentication`。这不等于应用层数据库或附件加密，应用锁仍是访问控制。
- 失去活动状态时先覆盖原生窗口；回到前台并绘制含认证门禁的 Flutter 帧后解除遮挡，避免应用切换器提前截取笔记。该时序有通道回归，真实系统快照仍需设备验收。
- 分享扩展与提醒使用应用所选中英文，恢复/启动时同步原生偏好；系统权限提示使用系统对该应用选择的语言。

## 归档与发布准备

无需设备或账号的归档检查：

```bash
make ios-archive IOS_ARCHIVE_ARGS="--unsigned"
```

产物位于 `build/ios/archive/Runner.xcarchive`，不导出可安装 IPA。脚本固定依赖、检查主应用及分享扩展、原生能力和隐私资源，生成 `build/ios/privacy-report.json`。`--dry-run` 可先查看构建参数。

后续具备签名账号时，可本地导出签名 IPA；以下 ID 均为占位示例，应替换为账号中实际注册的值：

```bash
make ios-archive IOS_ARCHIVE_ARGS="--team TEAMID1234 --bundle-id com.example.notes --export-method app-store-connect --build-name 1.0.0 --build-number 1"
```

主应用与扩展共用 Team，App Group 默认 `group.<bundle-id>`，也可通过 `--app-group` 显式指定。需预先在开发者账号为两个 App ID 启用共享组并准备签名；不把账号、证书或 profile 提交到仓库。脚本只本地归档/导出，校验新生成 IPA 与签名，不上传 TestFlight 或 App Store。签名、安装、升级、TestFlight 和商店资料尚未验收。

系统权限文案和应用名称由中英文 ARB 生成 `InfoPlist.strings`；修改后运行 `flutter gen-l10n` 与 `python3 tool/generate_ios_localizations.py`。局域网权限用途用于用户配置的同步/模型服务，ATS 仅声明本地网络例外。

主应用与分享扩展包含自身代码的隐私清单，声明偏好与共享组、受管/用户选择的文件元数据，以及主应用的本地耗时计量。理由对应 Apple 的[必需理由 API 定义](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。主应用的空采集列表仅描述本项目代码，不能代表全部 SDK。

静态链接的 ML Kit SDK 原始隐私清单会原样保存在独立资源 bundle 中，避免 CocoaPods 链接时丢失。其声明包含设备标识、诊断等类别，发布前须根据实际 SDK 行为核对商店隐私回答。`privacy-report.json` 汇总所有打包声明并列出无内嵌清单的 framework（目前包括 LiteRT-LM、sherpa、PDFium 等）；该清单是审查输入，不能替代 SDK 行为核实或 Apple 审核。部分原生库使用文件/时间 API，仍需与上游核实适用理由和 SDK 隐私打包要求，完成后才能认定具备上架条件；不伪造供应商声明或修改其二进制签名。

各功能已分别提交。未经设备实测的能力继续标为待验收，不把打包检查写成“已完整支持”。

## 设备验收门槛（暂不执行）

- 覆盖最低支持系统与当前系统，以及较低/较高内存 iPhone；大模型按实测维护设备能力范围。
- 编辑器验证中文组合输入、长按拖选、复制粘贴、撤销重做、自动保存、侧滑返回、键盘、安全区、大字体和各主题。
- 合成测试数据完成 Android → iOS → Android 备份恢复；校验附件、文件库、隐私标记、提醒及对话快照；覆盖恢复失败回滚与同步冲突。
- 分别断网验证 OCR、转写、听写、TTS、本地模型；记录加载耗时、首 token 耗时、速度、峰值内存、温升及取消资源释放。
- 测试锁屏、切后台、强制终止后恢复、权限拒绝/撤回、认证中断；分享与通知入口不得绕过应用锁和隐私空间认证。
