# 智能体使用与维护

首页“本地助手”与编辑器共用 `fknotes-harness`，支持笔记检索、总结、改写、提取待办和多篇笔记整理。任务会记录模型返回的思考、工具、来源和执行结果。

## 使用和配置

1. 在“智能体设置”选择本地模型，或添加在线服务。在线服务需要 Base URL、协议、模型 ID 和用户自己的 Key，支持 Chat Completions、Responses 和 Anthropic Messages。
2. 按模型实际能力设置工具、图片、搜索和长度限制。连接测试发送短合成文本，最多输出 64 tokens，可能产生供应商费用。
3. 聊天顶部模型栏可搜索和切换已保存模型。草稿保留，已启动任务继续使用绑定的模型。运行中的模型和 MCP 配置需要先暂停任务再修改。
4. 生成时可写下一条消息或在输入框停止当前任务。“任务记录”提供暂停、恢复、核实外部结果和撤销笔记修改。

| 配置 | 行为 |
| --- | --- |
| 服务与模型 | 一个服务最多保存 100 个模型，共用协议、地址和 Key。每个模型独立保存能力和长度。可通过接口搜索多选，也可用换行或逗号手动批量填写 |
| 模型发现 | 请求当前服务的模型列表。Chat Completions / Responses 使用 `GET {base}/models`，Anthropic 使用 `GET {base}/v1/models` 和分页游标。限 20 秒、20 页、5000 项，每页 2 MiB。列表仅用于发现标识 |
| 上下文与输出 | 支持整数、K 和 M，1K 为 1024 tokens。上下文范围 1024–2097152，输出为小于上下文的正数。任务预算、供应商限制和本地资源约束分别生效 |
| 修改审批 | 默认自动执行已授权写入。在设置中关闭“跳过逐次审批”后，每次先审阅差异。修改提案或笔记版本变化时生成新预览 |

v2 模型配置通过 `serviceId` 共用凭据，读取 v1 时保留模型 ID、选择与已有任务绑定。批量保存原子替换同一服务的模型，失败时恢复原 Key。删除单个模型保留服务凭据，删除整个服务需确认。

## 权限和隐私

- 本地和在线模型通过同一运行时执行，模型能力决定可用工具。默认本地推理和关闭联网工具。启用联网工具后，界面单独标明数据可能离开设备。
- 在线请求由客户端直连用户配置的服务。端点使用 HTTPS，回环地址可用 HTTP。URL 内的凭据及跨域重定向会被拒绝。HTTP MCP 使用同一任务授权，按配置执行工具。
- 普通任务访问普通笔记。隐私任务使用本次系统认证，仅访问隐私空间；锁定或退出后授权撤销。在线上下文包含隐私笔记时，输入框上方持续显示说明。详见[隐私工作区](private-workspace.md)。
- Key 保存在系统安全存储。任务仅保存凭据引用，敏感载荷写入独立的 AES-GCM 加密任务库 `fknotes-agent.db`。普通和隐私历史及统计按空间隔离。
- 备份携带去除执行授权的对话快照。恢复笔记库会更换数据代次，旧任务无法继续写入恢复后的库。归档边界见[备份与手动云同步](cloud-sync.md#备份范围)。

## 架构和代码

```text
聊天 / 编辑器 / 任务记录
  → AgentService → HarnessRuntime
    ├── ModelPort → 本地引擎 / 在线协议
    ├── 工具执行 → NoteRepository / HTTP MCP
    └── RunStore → 检查点、审批、回执与有序事件
```

| 位置 | 职责 |
| --- | --- |
| [纯 Dart 内核](../packages/fknotes_harness/README.md) / [运行时](../packages/fknotes_harness/lib/src/runtime.dart) | ReAct 循环、任务调度、审批、检查点和恢复 |
| [AgentService](../lib/agent/agent_service.dart) / [任务卡片](../lib/widgets/agent_task_card.dart) | 绑定配置与授权、订阅任务和撤销 |
| [在线适配](../lib/agent/online_model_adapter.dart) / [HTTP 边界](../lib/agent/agent_http_client.dart) / [本地适配](../lib/agent/local_model_adapter.dart) | 模型能力、流式事件、取消、限流和续传 |
| [笔记工具](../lib/agent/note_tools.dart) / [MCP](../lib/agent/mcp_tools.dart) / [笔记仓库](../lib/services/note_repository.dart) | 参数校验、风险分级、预览、事务写入和回执 |
| [编辑器驱动](../lib/agent/editor_agent_driver.dart) / [加密任务库](../lib/agent/encrypted_run_store.dart) / [安全存储](../lib/agent/credential_vault.dart) | 选区插入与撤销、版本比较和设备绑定密钥 |

## 执行约定

- **排队和补充。** `enqueue` 保存独立的后继轮次。显式插队使用 `steer`，在安全检查点生效。页面关闭后任务可以继续，进程终止后从检查点恢复。
- **结构化调用。** 模型适配器交付完整且经过校验的工具参数。思考正文、工具事件和供应商续传字段分开保存，续传字段限同一模型使用。上下文压缩保留调用与结果的配对、来源和未完成操作。
- **预览与落盘。** 执行前保存稳定 `operationId`、预览及执行意图。审批绑定参数摘要、笔记修订和有效期。已授权写入按自动或手动审批模式记录回执。旧任务缺少审批字段时按逐次审批恢复。
- **幂等和撤销。** 笔记修改与回执在同一事务提交，恢复时先核对回执。结果未知的外部操作进入 `needsReconciliation`，核实后再决定后续动作。取消传递到模型、工具和子任务；已提交修改通过版本校验后单独撤销。
- **预算和权限。** 默认最多 20 次模型请求、64,000 tokens 和 10 分钟活跃时间。单请求 90 秒，可重试错误最多重试两次。压缩和只读子任务共享总预算，子任务最多并发两个、委派深度一级。工具和内置任务模板都受同一权限检查。
- **统计和流式展示。** `roundCount` 统计主循环轮次，重试与压缩计入请求预算。每个结构化调用计入 `toolCallCount`，供应商工具按稳定 ID 去重生命周期事件。文本和思考片段合并后再持久化。
- **接入约束。** 新模型实现 `ModelPort`，新工具声明 Schema、权限、风险和恢复策略，预览阶段保持无副作用。安全且可修正的领域错误可作为 `toolObservation` 返回。供应商工具与搜索按模型能力和网络授权开放，SSE 体积独立于 token 预算受限。

## 验收

通用检查见[开发指南](development.md#本地验证)。重点回归三类协议的流式调用、取消、续传和错误脱敏，以及授权隔离、并发编辑、写入去重、备份和恢复。

```bash
flutter test test/agent_workflow_test.dart test/agent_note_tools_test.dart test/agent_model_adapter_test.dart test/agent_mcp_test.dart
(cd packages/fknotes_harness && dart test)
```

自动化使用合成流、临时 SQLite 和本机 HTTP MCP 服务。供应商模型兼容性、费用和限流需用授权测试 Key 验证。移动端需验收安全存储、推理取消、后台锁定和进程重启恢复。
