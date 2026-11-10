# AGENTS.md

本文件适用于整个仓库，为在此项目中工作的编码助手提供约定。默认使用中文沟通，代码标识符沿用现有英文命名。

## 项目与文档

非空笔记（Feikong Notes / `fknotes`）是本地优先的 Flutter 多媒体笔记应用，支持富文本、附件、语音、OCR、本地与在线 AI。当前主要交付和验收平台是 Android 手机；其他平台工程用于开发验证，不代表全部功能已经支持。

开始修改前，阅读相关实现、测试及专题文档：

- `README.md`：项目介绍、环境与常用检查。
- `PRODUCT.md`：功能范围与数据原则。
- `DESIGN.md`：界面与交互规范；修改 UI 时必读相关章节。
- `docs/development.md`：开发流程与代码位置。
- `docs/README.md`：专题文档索引，按任务读取编辑器、主题、隐私、同步或模型文档。
- `docs/ANDROID_RELEASE.md`：仅在涉及 Android 构建和发布时读取。

文档描述与实现不一致时，先核实原因；不要把尚未实现或未经设备验证的能力写成已支持。

## 代码结构与边界

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart`、`lib/app.dart` | 启动与应用装配 |
| `lib/pages/`、`lib/widgets/` | 页面与可复用组件 |
| `lib/providers/` | 应用状态与控制器，沿用 Provider 模式 |
| `lib/models/`、`lib/services/` | 数据模型、仓储、持久化与设备服务 |
| `lib/editor/` | 编辑会话、文档转换与编辑操作 |
| `lib/agent/` | 智能体的应用适配、模型接入、权限与工具 |
| `packages/fknotes_harness/` | 纯 Dart 智能体内核及独立测试 |
| `lib/theme/`、`lib/experience/` | 主题语义与主题专属渲染 |
| `lib/l10n/` | 中英文 ARB 和生成的本地化代码 |
| `android/`、`native/` | Android 集成与共享原生推理桥接 |
| `test/`、`tool/` | 应用测试与开发、构建、发布脚本 |
| `third_party/` | 随仓库维护的第三方代码与许可 |

沿用现有分层，将持久化和设备调用放在服务层，避免在 Widget 中新增重复的业务实现。`fknotes_harness` 保持纯 Dart，不引入 Flutter 或模型供应商 SDK；应用通过既有端口接入。

## 实现约定

- 保持修改聚焦任务，保留工作区已有改动，避免顺带重构或整库格式化。遵循 `analysis_options.yaml` 与邻近代码风格。
- 笔记正文的规范存储格式是 Quill Delta JSON。Markdown 用于粘贴、导入导出和模型输出边界；不要以 Markdown 往返转换替代无损文档编辑。编辑器变更需关注选区、中文输入法组合输入、撤销重做与自动保存。
- UI 颜色通过 `context.appColors` 和主题语义获取；新增界面不使用静态 `AppColors` 常量。复用 `AppIcon`、既有菜单和反馈组件，遵循 `DESIGN.md`。主题切换需保留页面与编辑状态。
- 新增用户可见文案同步维护 `lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb`，沿用本地化访问方式。执行 `flutter gen-l10n` 更新 `lib/l10n/generated/`，不要直接手改生成文件。
- 修改数据库结构或归档格式时，检查旧数据迁移、备份恢复与失败回滚路径；不可仅验证全新安装。
- 保持公开笔记与隐私工作区的访问边界，避免让搜索、预览、AI 上下文或导出绕过现有认证与授权。不要将应用锁描述为数据库或附件加密。
- 不将真实笔记、备份、API Key、同步凭据、签名文件或个人路径写入源码、日志样例和测试夹具。测试使用合成数据及确定性的模型、工具替身，避免调用真实在线服务。
- 依赖升级应有明确任务依据。保留锁文件和 `pubspec.yaml` 中带兼容性说明的版本固定与 overrides；不要为通过检查随意升级或删除限制。
- Flutter Quill 的项目补丁位于 `third_party/flutter_quill/`，不要修改机器上的 Pub 缓存。修改第三方代码前阅读对应 README，保留来源和许可证，并使补丁可复现。
- 涉及本地模型或原生桥接时，检查取消、资源释放和平台支持边界；设备推理、麦克风、系统认证等行为需要相应设备验证，单元测试不能替代真机结论。

## 环境与命令

当前仓库使用 Flutter **3.47.2** 及其自带 Dart SDK、Android SDK **36**、JDK **17** 和 Make。后续版本以 `pubspec.yaml` 与发布 CI 配置为准。

在仓库根目录准备依赖：

```bash
flutter pub get --enforce-lockfile
(cd packages/fknotes_harness && dart pub get --enforce-lockfile)
```

运行 Android（用实际设备 ID 替换示例值）：

```bash
flutter devices
make run-android DEVICE=emulator-5554
```

首次 Android 构建会下载并校验固定版本的 MNN 原生运行库。完整 Make 目标用 `make help` 查看；`make check` 会格式化源码，需要只读检查时使用以下命令。

## 验证

根据改动范围选择检查：纯文档修改核对内容、路径和差异；行为变更运行相关测试，必要时补充回归用例；公共组件、数据层或跨模块变更扩大到完整检查。

```bash
# 只检查格式，不改写文件
dart format --output=none --set-exit-if-changed lib test packages/fknotes_harness/lib packages/fknotes_harness/test
flutter analyze --no-pub
flutter test --no-pub
(cd packages/fknotes_harness && dart analyze && dart test)
git diff --check
```

定向运行应用测试可使用 `flutter test --no-pub test/<相关文件>_test.dart`。涉及发布脚本时运行 `python3 -m unittest discover -s tool -p 'test_*release*.py'`。UI 变更按相关设计要求检查窄屏、大字体、键盘、安全区和主题表现。

功能、交互或数据边界变化时同步更新相关文档。因环境或设备不足无法完成检查时明确说明，不声称测试通过。

## 提交与交付

- 每个完成且可独立回滚的单元，完成必要校验后主动提交。只暂存本次文件；同一文件含无关改动时仅暂存本次相关区块。检查 `git diff --check`、`git diff --cached --check` 和 staged diff，不提交半成品或无关修改。
- 使用 Conventional Commits：`<type>(<scope>): <summary>`，scope 可省略；type/scope 用小写英文，摘要可用中文。常用类型为 `feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`build`、`ci`、`style`、`chore`、`revert`。
- 未经本次明确授权，不重写已发布历史，不 push、创建/移动标签或发布版本；修正使用新提交。
- 打 tag 前，按上一个发布 tag 到目标提交的实际变更，在 GitHub Release 草稿中写好面向用户的中文更新说明；所有发布渠道复用该正文，仓库不保留逐版本说明文件。说明须简洁、排版规范，不以提交列表或对比链接代替。
- 当前发布流程尚未迁移到上述草稿约定：`.github/workflows/release.yml` 仍依赖 `docs/releases/<版本>.md`。执行下一次发布任务时，需先迁移说明来源和相关校验，同步更新[开发指南](docs/development.md)与 [Android 发布指南](docs/ANDROID_RELEASE.md)，再移除仓库中的逐版本说明文件；不能只删除文件而破坏现有构建。
- 最终用中文说明完成内容、验证结果、未验证范围及提交哈希；事实与推测分开，文件引用可定位。
