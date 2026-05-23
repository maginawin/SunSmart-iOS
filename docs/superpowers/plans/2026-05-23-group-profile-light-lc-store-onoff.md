# Group Profile Light LC Store OnOff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group profile SAVE 过程中默认不再发送 `LightLCLightOnOffSet(false)`，避免配置时关灯，同时保留未来 UI 开关可控制该行为的扩展点。

**Architecture:** 在 `ProfileType.lightControlStore` 上增加 `turnOffBeforeStore` 布尔关联值，默认 `false`。消息生成层根据该值决定是否在 `SceneStore` 前插入 `LightLCLightOnOffSet(false)`；当前所有既有调用保持默认值，因此 group profile SAVE 默认不关灯。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace、现有 Mesh sync 任务模型。

---

## 文件结构

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - 修改 `ProfileType.lightControlStore` enum case，增加 `turnOffBeforeStore: Bool = false`。
  - 保持现有 `syncProfile.append(.lightControlStore(sceneNumber: profileScene.sceneNumber))` 调用不显式传值，让默认值生效。
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 修改 `ProfileType.getMessageHandles(node:)` 中 `lightControlStore` 的 switch case。
  - 仅当 `turnOffBeforeStore == true` 时发送 `LightLCLightOnOffSet(false)`。
  - 始终保留 `SceneStore(sceneNumber)`。
- Verify only: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 确认 `.lightControlStore` 的 title/success switch 使用忽略关联值的匹配方式，不需要业务改动。
- Verify only: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 确认 sensor protection 的 `pir_disable` / `pir_enabled` 插入逻辑不变。

## 约束

- 不新增 UI 开关。
- 不修改传感器保护任务。
- 不修改 `manualOverrideTimeout`、standby level、Light LC mode、occupancy mode 的同步逻辑。
- 不新增 Auth 信息。
- 不处理 `user-temp/`。
- 不格式化无关文件。
- 构建验证优先直接运行 `xcodebuild`，不使用 shell 包装或重定向日志。

### Task 1: 给 lightControlStore 增加默认关闭开关

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: 确认当前 enum case 和调用点**

Run:

```bash
rg -n "case lightControlStore|lightControlStore\\(" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `SunSmart/Common/Data/Node+SyncData.swift` 中存在 `case lightControlStore(sceneNumber: SceneNumber)`。
- `SunSmart/Common/Data/Node+SyncData.swift` 中存在 `syncProfile.append(.lightControlStore(sceneNumber: profileScene.sceneNumber))`。
- `SunSmart/Common/Data/Node+MessageHandles.swift` 中存在 `case .lightControlStore(let sceneNumber):`。

- [ ] **Step 2: 修改 ProfileType.lightControlStore case**

将 `SunSmart/Common/Data/Node+SyncData.swift` 中的 enum case：

```swift
/// 灯光数据缓存到场景
case lightControlStore(sceneNumber: SceneNumber)
```

替换为：

```swift
/// 灯光数据缓存到场景
case lightControlStore(sceneNumber: SceneNumber, turnOffBeforeStore: Bool = false)
```

- [ ] **Step 3: 确认既有调用继续使用默认值**

Run:

```bash
rg -n "lightControlStore\\(" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `syncProfile.append(.lightControlStore(sceneNumber: profileScene.sceneNumber))` 仍存在。
- 没有任何当前 group profile SAVE 路径传入 `turnOffBeforeStore: true`。

### Task 2: 按 turnOffBeforeStore 控制是否发送 LightLCLightOnOffSet(false)

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`

- [ ] **Step 1: 修改 lightControlStore 消息生成**

将 `ProfileType.getMessageHandles(node:)` 中的：

```swift
case .lightControlStore(let sceneNumber):
    if let controlSceneSetupModel = node.lightLCSceneSetupModel {
        if let lightLCModel = node.lightLCModel {
            messageHandles.append(MeshMessageHandle(message: LightLCLightOnOffSet(false), model: lightLCModel))
        }
        messageHandles.append(MeshMessageHandle(message: SceneStore(sceneNumber), model: controlSceneSetupModel))
    }
```

替换为：

```swift
case .lightControlStore(let sceneNumber, let turnOffBeforeStore):
    if let controlSceneSetupModel = node.lightLCSceneSetupModel {
        if turnOffBeforeStore, let lightLCModel = node.lightLCModel {
            messageHandles.append(MeshMessageHandle(message: LightLCLightOnOffSet(false), model: lightLCModel))
        }
        messageHandles.append(MeshMessageHandle(message: SceneStore(sceneNumber), model: controlSceneSetupModel))
    }
```

- [ ] **Step 2: 确认默认路径不会发送关灯命令**

Run:

```bash
rg -n "LightLCLightOnOffSet\\(false\\)|turnOffBeforeStore|case \\.lightControlStore" SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/Node+SyncData.swift
```

Expected:

- `LightLCLightOnOffSet(false)` 只在 `if turnOffBeforeStore` 条件块内出现。
- `ProfileType.lightControlStore` 默认值是 `turnOffBeforeStore: Bool = false`。

### Task 3: 检查现有 switch 匹配与 sensor protection 不变

**Files:**
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: 检查所有 lightControlStore 匹配点**

Run:

```bash
rg -n "lightControlStore" SunSmart
```

Expected:

- 除 `Node+SyncData.swift` enum case、默认调用点、`Node+MessageHandles.swift` 消息生成外，其它 switch 中如果存在 `case .lightControlStore:`，应继续作为忽略关联值的匹配方式使用。
- 不应出现必须手动传 `turnOffBeforeStore` 的编译级遗漏。

- [ ] **Step 2: 确认 sensor protection 任务未被改动**

Run:

```bash
rg -n "profileSensorProtectionDisable|profileSensorTargetEnable|pir_disable|pir_enabled|NodeSyncData\\.pirEnabled\\(false\\)|NodeSyncData\\.pirEnabled\\(true\\)" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `ProfileSensorProtectionContext.preDisableDeviceModel()` 仍创建 `profileSensorProtectionDisable` 任务。
- `ProfileSensorProtectionContext.postTargetStateDeviceModel()` 仍创建 `profileSensorTargetEnable` 任务。
- `profileSensorProtectionDisable` 仍映射到 `NodeSyncData.pirEnabled(false)`。
- `profileSensorTargetEnable` 仍映射到 `NodeSyncData.pirEnabled(true)`。

### Task 4: 编译验证并提交实现

**Files:**
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Common/Data/Node+MessageHandles.swift`

- [ ] **Step 1: 查看实现 diff**

Run:

```bash
git diff -- SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift
```

Expected:

- `Node+SyncData.swift` 只修改 `lightControlStore` enum case 的关联值。
- `Node+MessageHandles.swift` 只让 `LightLCLightOnOffSet(false)` 受 `turnOffBeforeStore` 控制。
- `SceneStore(sceneNumber)` 仍在 `lightControlStore` 分支中无条件生成。

- [ ] **Step 2: 编译 SunSmart scheme**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- 如果出现与本改动无关的现有签名或环境问题，记录完整错误并停止，不做无关修复。

- [ ] **Step 3: 提交实现**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift
git commit -m "fix: avoid turning off lights before profile store"
```

Expected:

- 生成一个只包含两个 Swift 文件改动的提交。

## 自审结果

- Spec 覆盖：Task 1 和 Task 2 实现默认不发送 `LightLCLightOnOffSet(false)` 并保留未来 UI 传参扩展点；Task 3 确认 sensor protection 不变；Task 4 覆盖源码 diff 与编译验证。
- 占位符扫描：没有待补实现项，所有改动步骤均给出具体文件、代码片段、命令和期望结果。
- 类型一致性：`turnOffBeforeStore` 在 enum case、switch 绑定和验证命令中名称一致；默认值为 `false`。
