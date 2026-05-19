# Battery Power Switch Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为直接添加的 Battery Power Switch 实现 Scene / Brightness Profile 保存、同步、失败状态和重新同步。

**Architecture:** 继续复用现有 `DeviceSwitchData` 和 `PJEightKeySwitchData` 作为 UI desired config；在 `PJEightKeySwitchRepository` 增加 BPS 专属同步元数据。同步命令通过现有 `SyncDevicesViewController` 执行，新增 BPS sync type 和 action type，按 reset、key config、target model subscription、removed group unsubscription 的顺序发送。

**Tech Stack:** Swift、UIKit、SQLite.swift、NordicSigMeshSDK、Bluetooth Mesh Config/Vendor messages、Xcode workspace `SunSmart.xcworkspace`。

---

## 文件结构

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  - 负责 BPS metadata 表结构、迁移、读写 sync state/hash/version。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 保存 metadata 到 runtime model，提供 `needsBatteryPowerSwitchSync`、desired hash、BPS key config 和 target subscription helper。
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 直接添加 BPS 时创建内部 virtual group；增加 BPS target capability model helper。
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 新增 BPS action type 的 message handles。
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 新增 BPS sync type，生成有序步骤，并在同步结束时回传结果。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - Edit 保存时生成 pending desired config，保存后进入 BPS 同步。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - sync issue 时从详情页触发重新同步，并在成功后刷新标题和状态。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - 暴露同步状态给详情页。
- Verify only unless missing: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify only unless missing: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Verify only unless missing: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`

不新增 Swift 文件，避免手工维护四个品牌 target 的 `project.pbxproj` source membership。

---

### Task 1: BPS 同步元数据持久化

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 在 `PJEightKeySwitchRepository.swift` 增加 sync state 类型**

在 `PJEightKeySwitchRepository` 内部加入 `SyncStateStorage`，raw value 固定为数据库值：

```swift
enum SyncStateStorage: Int {
    case synced = 0
    case pending = 1
    case failed = 2
}
```

- [ ] **Step 2: 扩展 `Metadata`**

将 `Metadata` 扩展为包含同步字段，并提供新建默认值：

```swift
struct Metadata {
    let panelType: PJEightKeySwitchPanelDefinition.PanelType
    let moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State
    let syncState: SyncStateStorage
    let desiredConfigVersion: Int
    let desiredConfigHash: String
    let appliedConfigHash: String
    let lastSyncFailedReason: String?
    let lastSyncedAt: Int64?

    init(panelType: PJEightKeySwitchPanelDefinition.PanelType) {
        self.panelType = panelType
        self.moreSettingsState = .default
        self.syncState = .pending
        self.desiredConfigVersion = 0
        self.desiredConfigHash = ""
        self.appliedConfigHash = ""
        self.lastSyncFailedReason = nil
        self.lastSyncedAt = nil
    }
}
```

保留现有调用所需的 initializer，接收 `panelType` 和 `moreSettingsState` 时其余字段用默认值。

- [ ] **Step 3: 扩展 SQLite columns 并迁移旧库**

在 `ExpressionKey` 增加：

```swift
static let syncState = Expression<Int>("syncState")
static let desiredConfigVersion = Expression<Int>("desiredConfigVersion")
static let desiredConfigHash = Expression<String>("desiredConfigHash")
static let appliedConfigHash = Expression<String>("appliedConfigHash")
static let lastSyncFailedReason = Expression<String?>("lastSyncFailedReason")
static let lastSyncedAt = Expression<Int64?>("lastSyncedAt")
```

在 `create` builder 中加列；在 `initDatabase()` 的 `columnDefinitions` 迁移中分别 `addColumn`，默认值：

- `syncState`: `SyncStateStorage.synced.rawValue`
- `desiredConfigVersion`: `0`
- `desiredConfigHash`: `""`
- `appliedConfigHash`: `""`
- `lastSyncFailedReason`: nil
- `lastSyncedAt`: nil

- [ ] **Step 4: 更新 save/read**

`save(_:)` 写入所有新字段。`metadata(for:)` 读取所有新字段；如果旧数据缺字段或 raw value 异常，fallback 到 `.synced`，避免旧库启动崩溃。

- [ ] **Step 5: 更新 `PJEightKeySwitchData` runtime 属性**

在 `PJEightKeySwitchData` 增加对应属性，默认值与 repository 一致。`convenience init(baseSwitchData:metadata:)` 和 `copy()` 需要复制这些字段。

- [ ] **Step 6: 增加同步判断属性**

在 `PJEightKeySwitchData` 增加：

```swift
var needsBatteryPowerSwitchSync: Bool {
    syncState != .synced || desiredConfigHash != appliedConfigHash
}
```

如果 enum 定义在 repository 内部不方便公开，改为在 `PJEightKeySwitchData.swift` 定义 app 内部 enum，并让 repository 复用同一个类型。

- [ ] **Step 7: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "feat: persist battery power switch sync metadata"
```

---

### Task 2: 直接添加后创建内部 virtual group

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 增加 BPS link group helper**

在 `MeshNetworkManager` extension 中增加 helper，只为 BPS 创建一个 virtual group：

```swift
@discardableResult
func ensureBatteryPowerSwitchLinkGroup(_ switchData: DeviceSwitchData) -> Bool {
    if switchData.linkGroupAddress != nil {
        return true
    }
    guard let meshUUID = meshNetwork?.uuid.uuidString,
          MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID).count >= 1 else {
        return false
    }
    guard let group = try? MeshAPI.createGroup(name: switchData.name + "-Group", isVirtual: true) else {
        return false
    }
    switchData.linkGroupAddress = group.address.address
    switchData.subLinkGroupAddress = nil
    return true
}
```

- [ ] **Step 2: 在 `createDefaultSwitch(forBatteryPowerSwitch:)` 中使用 helper**

创建 `newSwitch` 后立即调用 `ensureBatteryPowerSwitchLinkGroup(newSwitch)`。如果失败，仍创建 switch 数据但保留 `linkGroupAddress == nil`，后续 Edit 保存时再次尝试，并将 sync state 保持 pending。

- [ ] **Step 3: 保存初始 desired hash**

创建 `PJEightKeySwitchData` 后设置：

- `syncState = .pending`
- `desiredConfigVersion = 1`
- `desiredConfigHash = newSwitch.batteryPowerSwitchDesiredConfigHash(appKeyIndex: currentApplicationKey.index)`
- `appliedConfigHash = ""`

如果此时 helper 分配 group 失败，hash 中使用空 group 标记，Edit 保存时重新生成。

- [ ] **Step 4: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "feat: allocate battery power switch virtual group"
```

---

### Task 3: Profile 配置和 target capability helper

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 在 `PJEightKeySwitchData` 增加 desired hash**

hash 使用稳定字符串，不依赖 dictionary 顺序。字段顺序固定为：

```swift
func batteryPowerSwitchDesiredConfigHash(appKeyIndex: KeyIndex) -> String {
    [
        "panel=\(eightKeyPanelType.rawValue)",
        "enabled=\(enabled)",
        "link=\(linkGroupAddress?.hex ?? "nil")",
        "groups=\(bindGroupAddresses.sorted().map(\.hex).joined(separator: ","))",
        "unbind=\(unbindGroupAddresses.sorted().map(\.hex).joined(separator: ","))",
        "sceneA=\(sceneANumber.map(String.init) ?? "nil")",
        "sceneB=\(sceneBNumber.map(String.init) ?? "nil")",
        "sceneC=\(sceneCNumber.map(String.init) ?? "nil")",
        "sceneD=\(sceneDNumber.map(String.init) ?? "nil")",
        "reporting=\(moreSettingsState.periodicReporting.rawValue)",
        "led=\(moreSettingsState.ledIndicatorEnabled)",
        "appKey=\(appKeyIndex)"
    ].joined(separator: "|")
}
```

如果 `PanelType` 没有 `rawValue`，使用本地 switch 映射：scene 为 `scene8Key`，brightness 为 `brightness8Key`。

- [ ] **Step 2: 增加 BPS key config builder**

在 `PJEightKeySwitchData` 增加：

```swift
func batteryPowerSwitchKeyConfigurations(appKeyIndex: KeyIndex) -> [BatteryPowerSwitchKeyConfiguration] {
    guard let address = linkGroupAddress else { return [] }
    let step: Int16 = 13107
    let up = [
        BatteryPowerSwitchKeyConfiguration(button: 4, trigger: .click, type: .levelDelta, level: step, address: address, appKeyIndex: appKeyIndex),
        BatteryPowerSwitchKeyConfiguration(button: 4, trigger: .press, type: .levelMove, level: step, address: address, appKeyIndex: appKeyIndex),
        BatteryPowerSwitchKeyConfiguration(button: 4, trigger: .pressRelease, type: .levelMove, level: 0, address: address, appKeyIndex: appKeyIndex)
    ]
    let down = [
        BatteryPowerSwitchKeyConfiguration(button: 5, trigger: .click, type: .levelDelta, level: -step, address: address, appKeyIndex: appKeyIndex),
        BatteryPowerSwitchKeyConfiguration(button: 5, trigger: .press, type: .levelMove, level: -step, address: address, appKeyIndex: appKeyIndex),
        BatteryPowerSwitchKeyConfiguration(button: 5, trigger: .pressRelease, type: .levelMove, level: 0, address: address, appKeyIndex: appKeyIndex)
    ]
    let onAuto = [
        BatteryPowerSwitchKeyConfiguration(button: 6, trigger: .click, type: .onOffSet, value: 1, address: address, appKeyIndex: appKeyIndex),
        BatteryPowerSwitchKeyConfiguration(button: 6, trigger: .press, type: .lightCtrlOnOff, value: 1, address: address, appKeyIndex: appKeyIndex)
    ]
    let off = [
        BatteryPowerSwitchKeyConfiguration(button: 7, trigger: .click, type: .onOffSet, value: 0, address: address, appKeyIndex: appKeyIndex)
    ]
    return batteryPowerSwitchProfileConfigurations(address: address, appKeyIndex: appKeyIndex) + up + down + onAuto + off
}
```

再增加私有 helper：

- Scene Profile：button 0...3 只在对应 scene 已选择时生成 `.sceneRecall`。
- Brightness Profile：button 0...3 生成 `.lightnessSet`，level 分别为 `65535`、`49151`、`32767`、`16383`。

- [ ] **Step 3: 增加 capability models helper**

在 `Node` extension 增加：

```swift
var batteryPowerSwitchCapabilityModels: [Model] {
    let ids: [UInt16] = [
        .genericOnOffServerModelId,
        .genericLevelServerModelId,
        .sceneServerModelId,
        .lightLightnessServerModelId,
        .lightLCServerModelId
    ]
    return elements.flatMap(\.models).filter { model in
        model.isBluetoothSIGAssigned && ids.contains(UInt16(model.modelIdentifier))
    }
}
```

如果 `modelIdentifier` 已是 `UInt16`，去掉 `UInt16(...)` 包装。

- [ ] **Step 4: 增加 target subscription handles**

在 `Node` extension 增加两个 helper：

```swift
func getBatteryPowerSwitchSubscriptionMessageHandles(group: Group) -> [MeshMessageHandle] {
    batteryPowerSwitchCapabilityModels.compactMap { model in
        guard !model.isSubscribed(to: group) else { return nil }
        let message = ConfigModelSubscriptionAdd(group: group, to: model) ?? ConfigModelSubscriptionVirtualAddressAdd(group: group, to: model)
        return message.map { MeshMessageHandle(message: $0, address: primaryUnicastAddress) }
    }
}

func getBatteryPowerSwitchUnsubscriptionMessageHandles(group: Group) -> [MeshMessageHandle] {
    batteryPowerSwitchCapabilityModels.compactMap { model in
        guard model.isSubscribed(to: group) else { return nil }
        let message = ConfigModelSubscriptionDelete(group: group, from: model) ?? ConfigModelSubscriptionVirtualAddressDelete(group: group, from: model)
        return message.map { MeshMessageHandle(message: $0, address: primaryUnicastAddress) }
    }
}
```

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "feat: build battery power switch profile config"
```

---

### Task 4: 接入同步任务模型

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 扩展 `ActionType`**

新增 action：

```swift
case batteryPowerSwitchReset(switchData: PJEightKeySwitchData)
case batteryPowerSwitchKeyConfig(switchData: PJEightKeySwitchData)
case batteryPowerSwitchTargetSubscription(switchData: PJEightKeySwitchData, group: Group, unsubscribe: Bool)
```

- [ ] **Step 2: 在 `DeviceOperationType.messageHandles` 生成 BPS 消息**

在 `.configuration` 分支增加：

- `.batteryPowerSwitchReset`：使用 BPS node 的 `sunricherVendorModel` 发送 `SunricherVendorSet(function: .batteryPowerSwitchResetDefaults)`。
- `.batteryPowerSwitchKeyConfig`：对 `batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 每个 config 生成 `SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(config))`。
- `.batteryPowerSwitchTargetSubscription`：`unsubscribe == false` 时对 group nodes 调 `getBatteryPowerSwitchSubscriptionMessageHandles(group:)`；`unsubscribe == true` 时调 `getBatteryPowerSwitchUnsubscriptionMessageHandles(group:)`。

所有 BPS vendor message 的 model 必须是 BPS 节点自己的 vendor model；target subscription message 的 address 是 target node primary address。

- [ ] **Step 3: 在 `DeviceOperationType.isSuccessful` 放行 BPS action**

在 `.configuration` 的 switch 中对三个 BPS action 返回 `true`。实际成败由 `resultMessageHandles` 决定；不依赖设备端可读状态。

- [ ] **Step 4: 扩展 `SyncDevicesViewController.SyncType`**

新增：

```swift
case batteryPowerSwitch(_ switchData: PJEightKeySwitchData)
```

- [ ] **Step 5: 在 `setupDataSource()` 生成有序步骤**

新增 `case .batteryPowerSwitch(let switchData)`，只创建一个 `SyncDevicesModel`，address 使用 `switchData.proxyNodeAddress`。步骤固定为：

1. `Reset`：一个 task，`.batteryPowerSwitchReset`。
2. `Configure buttons`：一个 task，`.batteryPowerSwitchKeyConfig`。
3. `Subscribe target groups`：每个 selected target group 一个 task，`.batteryPowerSwitchTargetSubscription(unsubscribe: false)`。
4. `Unsubscribe removed groups`：每个 unbind group 一个 task，`.batteryPowerSwitchTargetSubscription(unsubscribe: true)`。

这些 task 放在同一个 device model 的 `steps` 中，依赖 `getNextHandleModel()` 的现有顺序保证 reset 先于 config，config 先于 subscriptions。

- [ ] **Step 6: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: add battery power switch sync tasks"
```

---

### Task 5: Edit 保存后进入 BPS 同步

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: 保存前确保 link group**

在 `submitAction()` 构建 `switchData` 后，若 `hasRealDeviceLink(switchData)` 为 true，调用：

```swift
guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
    XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
    return
}
```

- [ ] **Step 2: 保存 desired sync metadata**

保存前设置：

```swift
let desiredHash = switchData.batteryPowerSwitchDesiredConfigHash(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index)
switchData.desiredConfigHash = desiredHash
switchData.desiredConfigVersion += 1
switchData.syncState = .pending
switchData.lastSyncFailedReason = nil
```

不要修改 `appliedConfigHash`。

- [ ] **Step 3: 替换 real device 的模拟激活弹窗**

`hasRealDeviceLink(switchData)` 为 true 时，不再调用模拟 `presentActivationAlert` 作为最终流程，改为 push：

```swift
let syncVC = SyncDevicesViewController(type: .batteryPowerSwitch(switchData))
syncVC.syncSuccessCallback = { [weak self] _ in
    switchData.markBatteryPowerSwitchSyncSucceeded()
    self?.persistSwitchData(switchData)
    self?.switchSavedAction?(switchData)
    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
}
syncVC.backActionCallback = { [weak self] result in
    if result.contains(where: { !$0.failedOperationTypes.isEmpty }) {
        switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed")
        self?.persistSwitchData(switchData)
        self?.switchSavedAction?(switchData)
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
    }
}
navigationController?.pushViewController(syncVC, animated: true)
```

把 `markBatteryPowerSwitchSyncSucceeded()` 和 `markBatteryPowerSwitchSyncFailed(reason:)` 放在 `PJEightKeySwitchData`，分别设置 `syncState/appliedHash/lastSyncedAt/lastSyncFailedReason`。

- [ ] **Step 4: 保持标题更新**

`switchSavedAction?(switchData)` 在保存 desired config 后仍要调用一次，确保详情页标题立即更新。同步成功或失败后再调用一次，确保状态刷新。

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "feat: sync battery power switch after edit save"
```

---

### Task 6: 列表和详情页显示 sync issue 并支持重新同步

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 合并 display status 判断**

在 `PJEightKeySwitchData.displayStatus` 中，将 `needsBatteryPowerSwitchSync` 纳入 sync issue：

```swift
if isBound && (needSyncData || needsBatteryPowerSwitchSync) {
    return .syncIssueBoundSwitch
}
```

- [ ] **Step 2: 暴露详情页同步状态**

在 `PJEightKeySwitchMonitorViewModel` 增加：

```swift
var needsBatteryPowerSwitchSync: Bool {
    switchData.needsBatteryPowerSwitchSync
}
```

- [ ] **Step 3: 详情页触发 re-sync**

在 `PJEightKeySwitchMonitorVC.refreshMonitor()` 开头判断：

```swift
guard !viewModel.needsBatteryPowerSwitchSync else {
    pushBatteryPowerSwitchSync(reSync: true)
    return
}
```

新增 `pushBatteryPowerSwitchSync(reSync:)`，创建 `SyncDevicesViewController(type: .batteryPowerSwitch(viewModel.switchData), reSync: reSync)`，成功/失败回调与 Edit 页一致。

- [ ] **Step 4: 成功后刷新 UI**

同步成功后：

- 更新 `viewModel.switchData`。
- 更新 `title`。
- 调用 `updateUI()`。
- 通知 `switchsRefreshNotificationName`。

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: show battery power switch sync issue"
```

---

### Task 7: Add / OTA 连接限制回归检查

**Files:**
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Verify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/NetworkConnection.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`

- [ ] **Step 1: 检查直接添加成功后断开 BPS**

Run:

```bash
rg -n "disconnectBatteryPowerSwitchNodes|disconnectProxy\\(node:" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: classic 和 professional add flow 都在 add finish 后对 `isBatteryPowerSwitch` 节点调用 `disconnectProxy(node:)`。

- [ ] **Step 2: 检查 BLE Direct OTA 成功后断开 BPS**

Run:

```bash
rg -n "disconnectBatteryPowerSwitchNodes|disconnectProxy\\(node:" SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift
```

Expected: BLE OTA 成功列表中的 BPS 节点调用 `disconnectProxy(node:)`。

- [ ] **Step 3: 检查自动 Proxy 过滤 Low Power**

Run:

```bash
rg -n "shouldSkipAutomaticProxy|lowPower == \\.enabled|features\\?\\.lowPower" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/NetworkConnection.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift
```

Expected: 自动 Proxy 和 `connectProxy(node:)` 都拒绝 Low Power enabled 节点。

- [ ] **Step 4: 若任一检查缺失，补齐最小改动**

只在缺失时修改对应文件；不要重写 add/OTA 流程。补齐后运行完整 build。

- [ ] **Step 5: Commit**

如果没有改动，跳过 commit。如果有改动：

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift
git commit -m "fix: disconnect battery power switch after direct flows"
```

---

### Task 8: 最终验证

**Files:**
- Verify all modified files.

- [ ] **Step 1: 静态检查关键约束**

Run:

```bash
rg -n "longPress|longRelease|lightCtrlOnOff.*0|batteryPowerSwitchResetDefaults|batteryPowerSwitchKeyConfig|BatteryPowerSwitchKeyConfiguration" SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Space
```

Expected:

- BPS profile config 不使用 `.longPress` 或 `.longRelease`。
- OFF 不使用 `.lightCtrlOnOff` value 0。
- 存在 reset defaults 和 key config 消息。

- [ ] **Step 2: 检查 sync state 写入点**

Run:

```bash
rg -n "desiredConfigHash|appliedConfigHash|syncState|markBatteryPowerSwitchSync" SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- Edit 保存会写 desired hash/version/pending。
- 同步成功会写 applied hash/synced。
- 同步失败会写 failed/reason。
- 直接添加会写 pending desired metadata。

- [ ] **Step 3: 运行最终编译**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 汇总未自动化的手工验证**

在最终回复中列出需要真机 Mesh 验证的点：

- 直接添加 `0x2A01` 后默认 Scene Profile。
- 直接添加 `0x2A02` 后默认 Brightness Profile。
- Add 成功后 App 断开 BPS BLE。
- Edit 保存后通过其它 Proxy 同步 BPS。
- reset 失败、key config 失败、subscription 失败时 UI 显示 sync issue。
- sync issue 入口重试后从 reset 开始完整重放。
- target group 移除后旧 group 不再响应。

---

## 自检

- Spec coverage: 本计划覆盖直接添加、内部 virtual group、Profile 映射、BPS key config、target capability model 订阅、sync state/hash、失败 UI、重新同步和连接限制。
- Scope: 不实现虚拟设备，不实现后台静默重试，不扩展 SDK 接口。
- Type consistency: 计划中的 `PJEightKeySwitchData`、`PJEightKeySwitchRepository`、`SyncDevicesViewController.SyncType`、`ActionType` 命名在各任务中保持一致。
- Test reality: 当前工程未发现测试 target，因此计划以小步编译、`rg` 约束检查和真机 Mesh 手工验证为主。
