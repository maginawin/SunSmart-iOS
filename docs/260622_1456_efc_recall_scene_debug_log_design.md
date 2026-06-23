# EFC Recall Scene Debug Log 设计

## 背景

EFC 设备会通过 recall 固定 Scene ID 通知 App 状态变化。当前 App 侧已经有 `EmergencyFireControllerSceneEventManager` 将 `SceneRecall` / `SceneRecallUnacknowledged` 转换为 EFC 状态事件，但现有日志无法稳定区分两类问题：

- 设备端没有发出 recall scene，或手机没有收到。
- App 已收到 recall scene，但 EFC 业务匹配、解析或 UI 更新链路没有命中。

本次目标是在 Debug 模式下补充最小诊断日志，让测试现场可以直接从控制台判断 App 收到了哪些 recall scene、目标地址是什么、scene ID 是什么、是否属于特殊 scene。

## 当前链路

1. SDK 解码 mesh message 后，通过 `MeshNetworkDelegate.meshNetworkManager(_:didReceiveMessage:sentFrom:to:)` 通知 App。
2. App 多个可见页面将收到的 message 转发给 `EmergencyFireControllerSceneEventManager.dispatch(message:source:destination:)`。
3. `EmergencyFireControllerSceneEventManager` 从 `SceneRecall` / `SceneRecallUnacknowledged` 提取 scene number。
4. EFC 保留 scene 当前为：
   - `0xFF20`: Power loss / emergency trigger
   - `0xFF21`: Fire alarm trigger
   - `0xFF22`: Restore
5. App 再按 EFC 绑定节点 source 与内部 publish group destination 匹配 controller，并发出 UI 状态事件。

## 设计目标

- Debug 模式下，SDK 层能打印所有成功解码并准备通知 App 的 `SceneRecall` / `SceneRecallUnacknowledged`。
- 日志必须包含 source、target/destination、scene ID、是否 special scene、是否 event trigger scene、是否 EFC 已知 scene。
- App 层日志继续说明 EFC 业务是否 matched / ignored，必要时增强 ignored 原因。
- 不改变任何协议解析、匹配规则、UI 状态更新、AppKey、action config 或同步任务。

## 推荐方案

采用两层日志。

### SDK 接收层日志

在 SDK 已经成功解码 `MeshMessage` 并准备通知 `MeshNetworkDelegate` 的通用接收层，对以下消息打印 Debug-only 日志：

- `SceneRecall`
- `SceneRecallUnacknowledged`

日志建议格式：

```text
[Scene Recall RX] type=SceneRecallUnacknowledged source=0x1201 target=0xC123 scene=0xFF20 special=true eventTrigger=true efc=powerLossTrigger
```

字段说明：

- `type`: recall message 类型。
- `source`: 设备发出 recall 的元素地址。
- `target`: recall 目标地址，EFC 正常应为内部 publish group。
- `scene`: recall scene ID，十六进制四位显示。
- `special`: `SceneNumber.isSpecialScene`。
- `eventTrigger`: `SceneNumber.isEventTriggerScene`。
- `efc`: 仅对 `0xFF20` / `0xFF21` / `0xFF22` 标出 `powerLossTrigger` / `fireAlarmTrigger` / `restore`，其他 scene 标为 `none`。

这层日志用于回答：App/SDK 是否已经收到设备发出的 recall scene。

### App EFC 解析层日志

保留 `EmergencyFireControllerSceneEventManager` 当前 `[EFC Scene] matched/ignored` 语义，并补齐可读性：

- scene number 统一输出为 `0x%04X`。
- matched 日志包含 controller、source、target、scene、state。
- ignored 日志尽量输出原因维度，例如 source 不匹配、target/publish group 不匹配、未找到绑定 controller。

日志建议格式：

```text
[EFC Scene] matched controller=EFC1 source=0x1201 target=0xC123 scene=0xFF20 state=powerLossTriggered
[EFC Scene] ignored reason=noMatchingController source=0x1201 target=0xC123 scene=0xFF20
```

这层日志用于回答：SDK 已收到 recall 后，App EFC 业务是否成功识别并触发 UI 事件。

## 排查判定规则

- 没有 `[Scene Recall RX]`：优先怀疑设备未 recall、手机未收到 mesh 消息、proxy filter / subscription / BLE 连接链路问题。
- 有 `[Scene Recall RX]`，没有 `[EFC Scene] matched`：优先怀疑 App 业务匹配问题，例如 target 不是 EFC 内部 publish group、source 不是绑定 EFC 节点或 manager 未激活。
- 有 `[EFC Scene] matched`，但 UI 未更新：优先排查 UI 事件通知、页面监听或状态渲染链路。

## 非目标

- 不修改 EFC scene ID。
- 不修改 `EmergencyFireControllerSceneEventManager` 的匹配策略。
- 不修改 `DeviceEmerFireData+Sync.swift`、`LinkedEmerFireConfig.swift`、`0x4D/07 action config` 或 `app_idx`。
- 不新增用户可见文案，不涉及国际化。
- 不修改 target 配置、资源或依赖。

## 验证方案

1. 静态检查：确认 SDK recall 日志只在 Debug 模式输出。
2. 静态检查：确认日志只覆盖 `SceneRecall` / `SceneRecallUnacknowledged`，不会打印所有 mesh message。
3. 静态检查：确认 App EFC 日志仍只在 `EmergencyFireControllerSceneEventManager` 内表达 matched / ignored，不改变事件派发结果。
4. 代码格式检查：运行 `git diff --check`。
5. SDK 构建：运行本地 SDK iPhoneOS build。
6. App 构建：运行 SunSmart iPhoneOS build。

## 风险与约束

- SDK 层日志会覆盖所有 recall scene，不只 EFC；但只在 Debug 输出，且字段能区分普通 scene 与 special/event trigger scene。
- App 当前 `MeshLibManager.manager.showLogs` 只控制 SDK LoggerDelegate 的分类日志。如果 recall 日志走 SDK logger，需要确保 Debug 场景下不会被默认空 `showLogs` 过滤掉；推荐此诊断日志使用明确的 Debug-only 输出，或同步放在不会被 `showLogs` 静默吞掉的位置。
- 当前工作区已有其他未提交 EFC link 改动，本任务实施时需要保持 diff 聚焦。
