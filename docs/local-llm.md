# 本地语言模型

在“设置 → 本地模型”下载、导入、切换或移除语言模型。推理在设备上运行。聊天与笔记助手按所选模型的能力提供文本、图片或音频输入，联网工具与在线模型的授权另见[智能体说明](fknotes-harness.md)。

## 引擎和模型

| 引擎 | 运行环境 | 内置模型示例 |
| --- | --- | --- |
| MNN 3.6.0 | Android ARM64、iOS ARM64 | MiniCPM5 1B、Qwen3.5 2B、Qwen3-VL 4B / 8B、MiniCPM-V 4 |
| LiteRT-LM 0.14 | Android ARM64，使用应用内独立进程 | Gemma 4 E2B IT、Gemma 4 E4B IT |

内置模型固定仓库版本、文件长度和 SHA-256。下载按配置选择官方源或镜像，支持续传。文件全部校验后才切换到可用版本。模型列表、体积、内存建议、输入能力和采样配置以[模型定义](../lib/services/language_model_service.dart)及应用内模型详情为准。

## 调用与资源

```text
聊天 / 编辑器 / 智能体
  → LocalAssistantService
  → LocalLlmCoordinator
  → RoutingLocalLlmEngine
    ├── MnnLocalLlmEngine → FFI → C++ bridge
    └── LiteRtLmEngine → Android 通道 → 独立推理进程
```

- `LocalAssistantService` 协调模型加载、取消和卸载。同一时间运行一个生成任务，并与听写、转写、朗读协调资源。生成结束后空闲两分钟卸载，后台或内存压力下提前释放。
- 服务默认加载参数为 4096 token、2–4 个线程，思考模式关闭。Android 优先选用 OpenCL，iOS 上 MNN 优先选用 Metal。引擎能力和运行时探测决定实际可用后端。
- 图片导入校验格式与分辨率、修正方向并缩放到最长边 2048，保存为 JPEG。单图上限 20 MB、4000 万像素。会话每次生成最多携带最近四张图片和一个音频附件。
- 附件从应用私有目录解析，原生端复核文件与输入能力。多模态预填充按模型处理实际图像或音频。编辑器插入结果可以一次撤销。
- 模型及推理缓存独立于笔记备份。对话快照的导出规则见[备份与手动云同步](cloud-sync.md#备份范围)。

| 代码 | 职责 |
| --- | --- |
| [请求与事件](../lib/models/local_llm.dart) | 能力、请求、流式事件、状态和指标 |
| [应用入口](../lib/services/local_assistant_service.dart) / [运行协调器](../lib/services/local_llm/local_llm_coordinator.dart) | 模型选择、单任务状态和生命周期 |
| [引擎路由](../lib/services/local_llm/routing_local_llm_engine.dart) | 按模型描述选择 MNN 或 LiteRT-LM |
| [MNN 桥接](../native/mnn/fknotes_mnn_bridge.cpp) / [LiteRT-LM 服务](../android/app/src/main/kotlin/com/fknotes/app/LiteRtLmService.kt) | 原生推理、附件处理和取消 |

## 原生运行库

Android Gradle / CMake 与 iOS Xcode 使用 [prepare_mnn_runtime.sh](../tool/prepare_mnn_runtime.sh) 下载固定版本的 MNN 压缩包，校验 SHA-256 后解压到构建缓存。更新 MNN 时同步更新两端校验值，检查桥接头文件和 ABI，再重新构建。LiteRT-LM 依赖版本维护在 [Android Gradle 配置](../android/app/build.gradle.kts)。

## 验收

通用命令见[开发指南](development.md#本地验证)。引擎路由、后端选择、加载和取消可单独回归：

```bash
flutter test test/routing_local_llm_engine_test.dart test/local_assistant_backend_policy_test.dart test/local_llm_coordinator_test.dart test/litert_lm_engine_test.dart
```

真机检查覆盖下载续传、校验和移除，文本及支持的图文或音频输入，取消、切换模型、后台释放与资源冲突。记录首 token 耗时、生成速度、峰值内存，并检查低内存设备的提示。MNN 运行库变更后分别验收 Android 和 iOS ARM64。
