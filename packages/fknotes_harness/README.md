# fknotes_harness

FKNotes 的私有纯 Dart 智能体运行内核。在线与本地模型实现相同 `ModelPort`，应用注入 `RunStore`、`RunAuthorizer` 与领域工具，不依赖 Flutter 或供应商 SDK。

- `HarnessRuntime.start/get/watch/enqueue/steer/approve/pause/resume/cancel/retry` 管理任务；`enqueue` 创建带独立回复与统计的后继对话轮次，`steer` 只在显式插队时调整当前任务。`recover` 不自动重跑中断任务，但会恢复已提交且前序已结束的排队轮次。
- 模型适配器输出 `ModelText`、`ModelActivity` 和一个 `ModelCompleted`。终止事件之前的工具参数不得执行；取消必须关闭适配器自己的网络/推理请求。
- 写工具必须声明恢复策略、提供无副作用的 `prepare` 和稳定预览；事务内提交操作回执，`recover` 返回已完成结果。`ToolContext.ensureActive` 在提交前检查运行代次与权限。
- `RunStore.save` 是 revision 比较并交换；任务保存完整历史、审批、修改预览、父子关系和检查点。应用适配负责加密、数据库迁移及备份边界；`MemoryRunStore` 仅用于测试。
- 已授权的写操作默认自动执行，可通过 `RunScope.requireApproval` 开启逐次审批；两种模式都保存预览、执行方式和回执。旧任务缺少此字段时保留逐次审批。用户审批绑定预览摘要和有效期；不确定的外部写入始终进入 `needsReconciliation`。
- `amendApproval` 生成新操作与新预览，不能沿用旧批准；`reconcile` 记录用户核实的外部结果后暂停，不立即重放调用。`protectHistory` 只保护历史并暂停，不授予模型访问权限。
- 仅安全且可修正的领域错误可标记 `HarnessException.toolObservation`，返回模型重新规划；权限、密钥、数据损坏和未知外部执行不能伪装成普通观察。
- 独立只读工具有界并行；写工具顺序执行；子 Agent 只读、共享根任务预算并继承取消。

验证：在本目录运行 `dart pub get`、`dart analyze`、`dart test`。测试使用确定性模型与工具，不调用真实在线服务。

应用接入、操作入口与设备验证边界见 [维护文档](../../docs/fknotes-harness.md)。
