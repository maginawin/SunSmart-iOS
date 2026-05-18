# EFC Auto Restore 修复开发计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** EFC Edit 页面新增关联组后，SAVE 同步成功时，对所有 group 页面支持 `AUTO` 的 Profile group 自动发送等价 group 页 `AUTO` 的 Light LC On 控制，让设备恢复到对应 Profile 的 Auto 状态。

**架构：** 在 EFC 同步 planner 中把“Auto restore”建模为一个普通 `EmergencyFireControllerSyncTask`，复用现有同步页发送和失败处理流程。任务在当前激活模式的关联灯组 subscription 和 trigger scene 写入之后生成，避免 `Trigger Scene` 里的 `LightLightnessSet` 再次覆盖恢复状态。

**技术栈：** Swift、UIKit、NordicSigMeshSDK、现有 `SyncDevicesViewController` / `EmergencyFireControllerSyncPlanner` 同步框架。

---

## 文件结构

- 修改：`SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
  - 新增 `EmergencyFireControllerSyncTaskKind.autoRestore`，用于展示和识别恢复任务。
- 修改：`SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - 新增 Auto restore task 生成逻辑。
  - 调整 `makeItems()` 顺序：控制器任务 -> 激活模式关联任务 -> 激活模式 Auto restore 任务 -> cleanup。
  - Auto restore 对当前激活模式的全部关联 group 生成，不按 `occupancyType` 过滤。
- 修改：`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 为 `autoRestore` 提供展示文案，避免同步页显示原始 enum 字符串。
  - 确认 group 地址 task 能使用 `data.bindNode` 作为发送上下文。
- 视情况修改：`SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift`
  - 该专用同步页直接发送 `task.messageHandles`，理论上无需结构性修改；只需确认新增 task 顺序和空消息处理不受影响。
- 不修改：group 页 Auto 逻辑。
  - `GroupViewController.autoBtnAction` 仍是行为参照，不把逻辑迁移到 UI controller。

## Group Profile Auto 支持范围分析

当前 group 页面使用 `GroupViewController` 展示所有 group profile。`setupUI()` 无条件创建 `autoBtn`，`autoBtnAction(sender:)` 无 profile type guard，实际发送：

```swift
MeshAPI.sendMessage(
    message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0),
    address: group.address.address
)
```

组列表双击菜单 `GroupsViewController.groupHandleDoubleTap(_:)` 也对所有 group 提供 `AUTO` 菜单项，发送 `LightLCLightOnOffSetUnacknowledged(true)` 到 group 地址。

因此按现有 UI 行为，以下所有 `Profile.ProfileType` 都支持 Auto 入口：

| Profile | rawValue | group 页面 Auto | 备注 |
| --- | ---: | --- | --- |
| `occupancy_daylight` | 1 | 支持 | Auto 后 daylight harvesting 已校准时不立即本地估算亮度 |
| `vacancy_daylight` | 2 | 支持 | Auto 后 daylight harvesting 已校准时不立即本地估算亮度 |
| `occupancy` | 3 | 支持 | Auto 后按 Light LC On 状态更新本地亮度 |
| `vacancy` | 4 | 支持 | Auto 后按 Light LC On 状态更新本地亮度 |
| `daylight` | 5 | 支持 | Auto 状态 UI 只对 daylight 展示传感器控制状态 |
| `manualControl` | 6 | 支持 | group 页面仍显示 Auto 按钮，不能按 profile 排除 |
| `proximityLighting` | 7 | 支持 | group 页面仍显示 Auto 按钮 |
| `proximityLightingWithPhotocell` | 8 | 支持 | group 页面仍显示 Auto 按钮 |

结论：EFC SAVE 的 Auto restore 范围应与 group 页面一致，对当前激活模式的所有关联 group 发送 Auto，而不是只对 `occupancyType == true` 的 group 发送。

## 任务 1：给 EFC 同步任务增加 Auto Restore 类型

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`

- [ ] **Step 1: 添加 task kind**

在 `EmergencyFireControllerSyncTaskKind` 中新增：

```swift
case autoRestore = "Auto Restore"
```

建议位置放在 `triggerScene` 后面、cleanup 前面：

```swift
case triggerScene = "Trigger Scene"
case autoRestore = "Auto Restore"
case deleteCleanup = "Delete Cleanup"
```

- [ ] **Step 2: 静态检查**

运行：

```bash
rg -n "autoRestore|EmergencyFireControllerSyncTaskKind" SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

预期：只能看到新增 enum case，暂时还没有生成逻辑。

## 任务 2：在 planner 中生成 Auto Restore task

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`

- [ ] **Step 1: 调整 `makeItems()` 顺序**

当前顺序：

```swift
items.append(contentsOf: try makeActiveModeAssociateItems())
items.append(contentsOf: try makeActiveModeCleanupItems())
```

改为：

```swift
items.append(contentsOf: try makeActiveModeAssociateItems())
items.append(contentsOf: try makeActiveModeAutoRestoreItems())
items.append(contentsOf: try makeActiveModeCleanupItems())
```

这样 Auto restore 会在所有当前激活组的订阅和保留场景写入之后执行。

- [ ] **Step 2: 新增 `makeActiveModeAutoRestoreItems()`**

添加在 `makeActiveModeAssociateItems()` 后面：

```swift
func makeActiveModeAutoRestoreItems() throws -> [EmergencyFireControllerSyncItem] {
    guard activeMode != nil, let settings = data.activeModeSettings else {
        return []
    }

    return settings.associateGroupAddresses.compactMap { address in
        guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
            return nil
        }
        let task = makeAutoRestoreTask(group: group)
        return EmergencyFireControllerSyncItem(name: group.name, iconName: "group_auto", address: group.address.address, tasks: [task])
    }
}
```

- [ ] **Step 3: 新增 `makeAutoRestoreTask(group:)`**

添加在 `makeAssociateTasks(...)` 附近：

```swift
private func makeAutoRestoreTask(group: Group) -> EmergencyFireControllerSyncTask {
    let message = LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)
    return EmergencyFireControllerSyncTask(
        title: "AUTO",
        kind: .autoRestore,
        address: group.address.address,
        messageHandles: [
            MeshMessageHandle(message: message, address: group.address.address)
        ]
    )
}
```

设计点：

- 使用用户可见 group 地址，和 group 页 Auto 一致。
- 使用 `.default` transition 和 `delay: 0`，和 `GroupViewController.autoBtnAction` 一致。
- task 的 `address` 使用 group 地址，message handle 也使用 group 地址；同步页已有 `nodeForEmergencyFireControllerTask(... ) ?? data.bindNode` fallback，可用 EFC 绑定节点作为任务上下文。

- [ ] **Step 4: 搜索确认没有重复恢复命令**

运行：

```bash
rg -n "LightLCLightOnOffSetUnacknowledged\\(true" SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Group/Controller/GroupViewController.swift
```

预期：新增 planner 中的 Auto restore、EFC Monitor 的 Stop 恢复、group 页 Auto 均可见；Edit SAVE 不直接在 VC 发命令。

## 任务 3：同步页显示 Auto Restore

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 更新显示文案**

在 `emergencyFireControllerTaskDisplayName(_:,data:)` 的 switch 中加入：

```swift
case .autoRestore:
    return "AUTO"
```

建议放在 `.triggerScene` 之后。

- [ ] **Step 2: 确认 task context 不需要新增节点解析**

确认当前逻辑保持：

```swift
private func nodeForEmergencyFireControllerTask(_ task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData) -> Node? {
    MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address) ?? data.bindNode
}
```

Auto restore 的 `task.address` 是 group 地址，不会解析到 node，会 fallback 到 `data.bindNode`。这符合当前 `DeviceOperationType.configuration(node:type:)` 的结构要求；真正发送地址来自 `task.messageHandles`。

- [ ] **Step 3: 确认成功判断无需改动**

确认 `DeviceOperationType.isSuccessful` 中 EFC 分支保持：

```swift
case .emergencyFireController(let task, _):
    return !task.isUnsupported
```

原因：Auto restore 是 unacknowledged group command，不能依赖 node 属性回读判断；发送完成且 handle 未失败即视为同步任务成功。

## 任务 4：检查专用 EFC 同步页兼容性

**Files:**
- Read/Modify if needed: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift`

- [ ] **Step 1: 确认发送路径**

确认 `send(taskIndex:tasks:)` 仍直接发送：

```swift
MeshProxyMessageCommand.shared.addMessage(messageHandles: task.messageHandles, progressBack: nil)
```

Auto restore 有非空 `messageHandles`，因此不会走 local-only 成功分支。

- [ ] **Step 2: 若 UI 展示需要文案，复用 enum raw value**

如果专用同步页直接显示 `task.kind.rawValue`，新增 `.autoRestore = "Auto Restore"` 已足够，不额外修改 UI。

- [ ] **Step 3: 确认新增 task 不影响删除 cleanup**

Auto restore 只由 `makeItems()` 生成，`makeDeleteCleanupItems()` 不调用 `makeActiveModeAutoRestoreItems()`，删除流程不会发送 Auto。

## 任务 5：验证命令顺序

**Files:**
- Modify only if necessary: `docs/260518_1730_efc_save_command_sequence.md`

- [ ] **Step 1: 用静态阅读验证 planner 顺序**

检查 `EmergencyFireControllerSyncPlanner.makeItems()` 最终顺序必须是：

```swift
items.append(controller item)
items.append(contentsOf: try makeActiveModeAssociateItems())
items.append(contentsOf: try makeActiveModeAutoRestoreItems())
items.append(contentsOf: try makeActiveModeCleanupItems())
```

- [ ] **Step 2: 预期 SAVE 同步命令顺序**

更新后的顺序应为：

1. EFC 控制器自身任务：
   - `Scene Publication`
   - `LC Publication`
   - `Mode`
   - `Resend`
   - `Restore Delay`
2. 当前激活模式关联灯组任务：
   - 每个灯节点 `Scene Group`
   - 每个灯节点 `Trigger Scene`
   - 每个灯节点 `LC Group`
3. 当前激活模式 Auto restore：
   - 每个当前激活关联组发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 到 group 地址。
4. Pending cleanup：
   - `LC Cleanup`

- [ ] **Step 3: 如修改命令顺序分析文档，追加“修复后顺序”小节**

不要覆盖原始分析结论；追加修复后的差异即可。

## 任务 6：编译验证

**Files:**
- No source modification expected.

- [ ] **Step 1: 运行 SunSmart iPhoneOS Debug 编译**

按项目要求直接运行，不包 `/bin/zsh -lc`，不做 shell 重定向：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 2: 如果编译失败，按错误定位**

重点看：

- `EmergencyFireControllerSyncTaskKind` switch 是否有遗漏。
- `LightLCLightOnOffSetUnacknowledged` initializer 参数是否与 NordicSigMeshSDK 当前签名一致。
- `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 是否可用于 group 地址发送。

## 任务 7：实机/模拟业务验证

**Files:**
- No source modification expected.

- [ ] **Step 1: 准备复现环境**

使用 PID `0x2131` EFC 设备，确保：

- EFC 已绑定真实节点。
- 至少有一个当前激活模式关联 group。
- group 内至少有一个已 keybind 且在线的灯节点。

- [ ] **Step 2: 执行原问题路径**

操作：

1. 进入 EFC Edit 页面。
2. 在 `Associate With Group(s)` 新增占用感应组。
3. 点击 `SAVE`。
4. 等待同步页成功。

预期：

- 同步页出现或执行 `AUTO` / `Auto Restore` 任务。
- 同步成功后，关联 group 设备自动恢复到对应 Profile 的 Auto 状态。
- 不需要再手动进入 group 页点击 `AUTO`。

- [ ] **Step 3: 验证所有 group profile 的 Auto restore 范围**

操作：

1. 分别选择以下 profile 的 group 作为 EFC 关联组并保存：`occupancy_daylight`、`vacancy_daylight`、`occupancy`、`vacancy`、`daylight`、`manualControl`、`proximityLighting`、`proximityLightingWithPhotocell`。
2. 每次 SAVE 同步成功后观察同步页任务和设备状态。

预期：

- 每个关联 group 都生成 Auto restore。
- 每个关联 group 都发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 到该 group 地址。

- [ ] **Step 4: 验证删除/清理场景**

操作：

1. 删除 EFC 配置。
2. 或从关联组中移除 group 后同步 cleanup。

预期：

- 删除 cleanup 不发送 Auto restore。

## 风险与约束

- Auto restore 是 group-address unacknowledged 命令，无法用单个 node 属性严格确认最终 profile 状态；同步成功只能证明命令发送流程完成。
- 如果设备固件要求通过 EFC 内部 publish group 恢复，而不是用户 group 地址恢复，需要把 `makeAutoRestoreTask(group:)` 的 address 改为 `publishGroup.address.address`，但这与当前用户补充的“模拟 group 页 Auto 按钮”不一致，暂不采用。
- 当前计划不改 UI 入口，不改 group 页，不改 EFC vendor 参数协议。

## 自检

- 需求覆盖：新增关联组 SAVE 后自动恢复对应 Profile Auto 状态，由 Auto restore task 覆盖。
- 顺序覆盖：Auto restore 在 `Trigger Scene` 和 `LC Group` 之后，避免被亮度写入覆盖。
- 范围控制：Auto restore 范围与 group 页面 Auto 入口一致，覆盖所有 group profile；只改 EFC 同步 planner、task kind、同步页展示，不重构同步架构。
- 验证覆盖：包含静态顺序检查、iPhoneOS Debug 编译、实机业务路径验证。
