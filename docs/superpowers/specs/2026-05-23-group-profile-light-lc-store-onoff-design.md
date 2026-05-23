# Group Profile SAVE Light LC Store OnOff 设计

## 背景

Group profile 修改后保存时，当前同步流程会先禁用支持 PIR 控制的传感器，最后再按目标 profile 状态启用传感器。这部分由 `ProfileSensorProtectionContext` 在 `SyncDevicesViewController(type: .group(...))` 中插入前置 `pir_disable` 和后置 `pir_enabled` 任务。

现状分析显示：

- 传感器保护任务发送的是 `NodeSyncData.pirEnabled(false/true)`，不是 standby 控制命令。
- profile 同步任务中的 `ProfileType.lightControlStore` 会在 `SceneStore` 前发送 `LightLCLightOnOffSet(false)`。
- `LightLCLightOnOffSet(false)` 是 Light LC Server 的即时控制命令，会让 Light LC 状态机向 Off 方向变化；如果 standby level 为 0%，视觉表现就是灯关闭。
- 在 group profile SAVE 配置过程中发送这个命令不安全，应默认不发送。

## 目标

- Group profile SAVE 过程中默认不发送 `LightLCLightOnOffSet(false)`。
- 保留 `SceneStore`，确保 profile scene 仍会保存。
- 保留未来扩展点：后续如果产品需要，可以在 UI 中增加开关控制是否在 store 前发送 `LightLCLightOnOffSet(false)`。
- 继续保留现有传感器前置禁用、后置启用流程，不改变 `pirEnabled(false/true)` 任务。
- 改动聚焦在 profile store 消息生成，不调整其它 profile 参数、资源、本地化、target 配置或依赖。

## 非目标

- 不新增 UI 开关。
- 不改变 `LightLCLightOnOffSet(false)` 的协议语义。
- 不移除 sensor protection 的 `pir_disable` / `pir_enabled` 任务。
- 不修改 standby level、manual override timeout、Light LC mode 或 occupancy mode 的同步判断。
- 不调整数据库结构或导入导出格式。

## 推荐方案

在 `ProfileType.lightControlStore` 对应的数据模型中增加布尔属性，例如 `turnOffBeforeStore`，默认值为 `false`。

消息生成时：

- 当 `turnOffBeforeStore == false`：只发送 `SceneStore(sceneNumber)`。
- 当 `turnOffBeforeStore == true`：先发送 `LightLCLightOnOffSet(false)`，再发送 `SceneStore(sceneNumber)`。

当前所有 group profile SAVE 同步任务默认使用 `false`，因此不会关灯。未来 UI 开关只需要将用户选择传入该属性，不需要重新设计消息层。

## 备选方案

### 直接删除关灯命令

在 `ProfileType.lightControlStore` 中直接移除 `LightLCLightOnOffSet(false)`，只保留 `SceneStore`。

优点是改动最小。缺点是缺少明确扩展点，如果后续需要恢复可选发送，需要再修改数据模型和任务生成路径。

### 只在 group profile SAVE 过滤

保留 `ProfileType.lightControlStore` 当前行为，在 `SyncDevicesViewController` 的 group profile SAVE 路径中过滤掉 `LightLCLightOnOffSet(false)`。

优点是影响范围较窄。缺点是逻辑分散，消息语义仍然隐藏在过滤代码里，未来 UI 开关接入不自然，也容易漏掉其它 profile SAVE 入口。

## 架构与数据流

1. `ProfileSettingsViewController.saveAction()` 保存 group profile，并在需要同步时进入 `SyncDevicesViewController(type: .group(...))`。
2. `SyncDevicesViewController` 根据 `node.getSyncData(type: .group(...))` 创建 profile 同步任务。
3. `Node.getNodeSyncProfiles(group:)` 判断哪些 `ProfileType` 需要同步，其中包含 `lightControlStore` 用于保存 profile scene。
4. `SyncDeviceStepTaskModel.operationType.messageHandles` 调用 `ProfileType.getMessageHandles(node:)` 生成实际 Mesh 消息。
5. `lightControlStore` 根据 `turnOffBeforeStore` 决定是否插入 `LightLCLightOnOffSet(false)`。
6. 默认路径不插入关灯命令，仅执行 `SceneStore`。

## 错误处理与兼容性

- 如果设备不支持 `lightLCSceneSetupModel`，保持现有行为：不生成 store 消息。
- 如果未来 `turnOffBeforeStore == true` 且设备缺少 `lightLCModel`，只发送 `SceneStore`，不因无法发送关灯命令阻断保存。
- `ProfileType` 的成功判断不需要新增检查；`lightControlStore` 当前成功判断依赖 scene store 相关状态，不应把 Light LC OnOff 状态作为成功条件。
- 已有传感器保护失败兜底逻辑保持不变。

## 测试计划

- 源码检查：确认 `ProfileType.lightControlStore` 默认值为不发送 `LightLCLightOnOffSet(false)`。
- 源码检查：确认 `SceneStore(sceneNumber)` 仍然生成。
- 源码检查：确认当前 group profile SAVE 任务创建路径未显式传入 `turnOffBeforeStore: true`。
- 源码检查：确认 `pir_disable` / `pir_enabled` 传感器保护任务未被移除。
- 编译验证 `SunSmart` scheme。

## 自审结果

- 无占位符、TODO 或未决需求。
- 范围聚焦在 group profile SAVE 配置过程中避免关灯。
- 已明确区分 sensor protection 的 PIR 命令和真正会导致关灯的 Light LC OnOff 命令。
- 已保留未来 UI 开关扩展点，同时当前默认行为为不发送关灯命令。
