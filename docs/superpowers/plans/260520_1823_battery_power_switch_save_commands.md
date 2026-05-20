# Battery Power Switch SAVE Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仅针对 PID `0x2A01`、`0x2A02` 的 Battery Power Switch，在 Add 阶段写入默认 switch configuration，并让后续 SAVE 按 switch configuration、group add、group remove 的业务顺序下发命令。

**Architecture:** Add 流程复用现有 append messages 阶段发送默认 BPS own configuration，并把配置成败独立于 provisioning 成败持久化到 `PJEightKeySwitchData`。SAVE 流程保留现有 SyncDevices 页面，但为 `.batteryPowerSwitch` 使用专用 section 顺序和严格依赖等待，确保 own configuration 先于 group add/remove。SDK 只补齐 append message 的 fail-fast 与失败回调，避免 BPS 配置失败后继续下发后续配置。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、MeshFastAddDeviceManager、SyncDevicesViewController、xcodebuild。

---

## 文件结构

- 修改 `../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
  - 负责 append message 失败回调和 `continuous == false` 时的 fail-fast。
- 创建 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 负责 PID 限定、默认 BPS switch 数据准备、默认 own configuration handles 生成、同步状态持久化。
- 修改 `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Classic Add 阶段追加默认 BPS configuration，并在 Add success 时保存 synced/failed 状态。
- 修改 `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Professional Add 阶段追加默认 BPS configuration，并在 Add success 时保存 synced/failed 状态。
- 修改 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - BPS SAVE 时强制 own configuration before group add before group remove；严格等待依赖成功。
- 修改 `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 保证 BPS target group subscription 使用差异语义，不强制重发未变化 group。

## Task 1: SDK Append Message Fail-Fast

**Files:**
- Modify: `../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`

- [ ] **Step 1: 增加 append 失败处理 helper**

在 `sendAppendMessages()` 前加入：

```swift
private func failCurrentAppendMessageAndContinueOrFinish() {
    guard !appendMessages.isEmpty else {
        deviceAddSuccessHandle()
        return
    }

    let messageHandle = appendMessages.removeFirst()
    deviceAppendFailedMessageBack?(messageHandle)

    if messageHandle.continuous {
        sendAppendMessages()
    } else {
        appendMessages.removeAll()
        deviceAddSuccessHandle()
    }
}
```

- [ ] **Step 2: 替换 append mode 下 busy 重试耗尽逻辑**

在 `handleSendResult` 的 `case .failure`、`case .busy`、`guard configRetryCount < maxRetryCount else` 分支中，将 append mode 原逻辑：

```swift
if self.appendMessages.count > 0 {
    self.appendMessages.removeFirst()
}
self.sendAppendMessages()
```

替换为：

```swift
self.failCurrentAppendMessageAndContinueOrFinish()
```

保留 keybind mode 的 `deviceAddFailHandle(error: .busy)`。

- [ ] **Step 3: 替换 append mode 下普通失败逻辑**

在 `handleSendResult` 的非 busy 失败分支中，将 append mode 原逻辑：

```swift
if self.appendMessages.count > 0 {
    self.appendMessages.removeFirst()
}
self.sendAppendMessages()
```

替换为：

```swift
self.failCurrentAppendMessageAndContinueOrFinish()
```

保留 keybind mode 的 `deviceAddFailHandle(error: .configFail)`。

- [ ] **Step 4: 替换 sendAppendMessages throw 失败逻辑**

在 `sendAppendMessages()` 的 `catch` 中，将原逻辑：

```swift
appendMessages.removeFirst()
sendAppendMessages()
```

替换为：

```swift
failCurrentAppendMessageAndContinueOrFinish()
```

保留 `AccessError.modelNotBoundToAppKey` 的现有分支。

- [ ] **Step 5: 静态检查 SDK helper**

Run:

```bash
rg -n "failCurrentAppendMessageAndContinueOrFinish|deviceAppendFailedMessageBack|messageHandle.continuous" ../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift
```

Expected: 能看到 helper 定义、失败回调调用、`continuous` 分支，以及三个调用点。

- [ ] **Step 6: Commit SDK change**

```bash
git -C ../../../nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift
git -C ../../../nordic-sig-mesh-sdk commit -m "fix: fail fast append messages"
```

## Task 2: Add Default BPS Configuration Helper

**Files:**
- Create: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: 创建 helper 文件**

新增文件内容：

```swift
//
//  BatteryPowerSwitchAddConfiguration.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum BatteryPowerSwitchAddConfiguration {

    static func isSupportedAddNode(_ node: Node) -> Bool {
        guard node.isBatteryPowerSwitch else {
            return false
        }
        switch node.productIdentifier {
        case 0x2A01, 0x2A02:
            return true
        default:
            return false
        }
    }

    static func prepareSwitchData(for node: Node) -> PJEightKeySwitchData? {
        guard isSupportedAddNode(node) else {
            return nil
        }
        guard let switchData = MeshNetworkManager.instance
            .createDefaultSwitch(forBatteryPowerSwitch: node)?
            .batteryPowerSwitchData else {
            return nil
        }
        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index)
            markFailed(switchData, reason: "group_address_insufficient_message".localizedString)
            return switchData
        }

        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index)
        persist(switchData)
        return switchData
    }

    static func defaultConfigurationMessageHandles(for switchData: PJEightKeySwitchData, node: Node) -> [MeshMessageHandle] {
        guard isSupportedAddNode(node),
              node.primaryUnicastAddress == switchData.proxyNodeAddress,
              let vendorModel = node.sunricherVendorModel,
              let switchGroup = switchData.linkGroup else {
            return []
        }

        let resetHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchResetDefaults),
            model: vendorModel
        )
        resetHandle.continuous = false

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        let keyConfigHandles = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
            let handle = MeshMessageHandle(
                message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)),
                model: vendorModel
            )
            handle.continuous = false
            return handle
        }

        let publicationHandles = node.getBatteryPowerSwitchPublicationMessageHandles(
            switchGroup: switchGroup,
            includeExisting: true
        )
        publicationHandles.forEach { $0.continuous = false }

        return [resetHandle] + keyConfigHandles + publicationHandles
    }

    static func markSucceeded(_ switchData: PJEightKeySwitchData) {
        switchData.markBatteryPowerSwitchSyncSucceeded()
        persist(switchData)
    }

    static func markFailed(_ switchData: PJEightKeySwitchData, reason: String?) {
        switchData.markBatteryPowerSwitchSyncFailed(reason: reason)
        persist(switchData)
    }

    private static func persist(_ switchData: PJEightKeySwitchData) {
        switchData.save()
        PJEightKeySwitchRepository.shared.save(switchData)
    }
}
```

- [ ] **Step 2: 静态检查 helper**

Run:

```bash
rg -n "BatteryPowerSwitchAddConfiguration|0x2A01|0x2A02|batteryPowerSwitchResetDefaults|includeExisting: true" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected: 能看到 PID 限定、reset、publication force full 配置。

- [ ] **Step 3: Commit helper**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "feat: add battery switch add configuration helper"
```

## Task 3: Classic Add Uses Default BPS Configuration

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: 增加 Add 阶段 BPS 状态缓存**

在 `private var addSuccessNodes: [Node] = []` 附近加入：

```swift
private var batteryPowerSwitchAddConfigurations: [Address: PJEightKeySwitchData] = [:]
private var failedBatteryPowerSwitchAddConfigurationAddresses: Set<Address> = []
```

- [ ] **Step 2: 在 appendMessagesBack 中追加默认 BPS configuration**

在 `appendMessagesBack` closure 内、`appendCompletion(appendMessages)` 前加入：

```swift
if BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node),
   let switchData = BatteryPowerSwitchAddConfiguration.prepareSwitchData(for: node) {
    batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
    let handles = BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(for: switchData, node: node)
    if handles.isEmpty {
        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
    } else {
        appendMessages.append(contentsOf: handles)
    }
}
```

- [ ] **Step 3: 增加 appendMessageFailedBack**

在 `appendMessageSuccessBack` closure 后、`addSuccess` closure 前加入：

```swift
} appendMessageFailedBack: { [weak self] messageHandle in
    guard let self else { return }
    guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
        return
    }
    if self.batteryPowerSwitchAddConfigurations[address] != nil {
        self.failedBatteryPowerSwitchAddConfigurationAddresses.insert(address)
    }
```

注意闭包边界应保持 `MeshAPI.startFastAddDevices` 参数顺序为 `appendMessageSuccessBack`、`appendMessageFailedBack`、`addSuccess`。

- [ ] **Step 4: 增加 Add success 状态落盘 helper**

在 `disconnectBatteryPowerSwitchNodes(_:)` 附近加入：

```swift
private func finalizeBatteryPowerSwitchAddConfiguration(for node: Node) {
    guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) else {
        return
    }
    guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress]
        ?? MeshNetworkManager.instance.createDefaultSwitch(forBatteryPowerSwitch: node)?.batteryPowerSwitchData else {
        return
    }

    if failedBatteryPowerSwitchAddConfigurationAddresses.contains(node.primaryUnicastAddress) {
        BatteryPowerSwitchAddConfiguration.markFailed(switchData, reason: "sync_failed".localizedString)
    } else {
        BatteryPowerSwitchAddConfiguration.markSucceeded(switchData)
    }

    batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
    failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
}
```

- [ ] **Step 5: 在 addSuccess 中使用 helper**

将 `addSuccess` 内现有 BPS 创建逻辑：

```swift
if node.isBatteryPowerSwitch {
    MeshNetworkManager.instance.createDefaultSwitch(forBatteryPowerSwitch: node)
}
```

替换为：

```swift
if node.isBatteryPowerSwitch {
    finalizeBatteryPowerSwitchAddConfiguration(for: node)
}
```

- [ ] **Step 6: 静态检查 Classic Add**

Run:

```bash
rg -n "batteryPowerSwitchAddConfigurations|failedBatteryPowerSwitchAddConfigurationAddresses|appendMessageFailedBack|finalizeBatteryPowerSwitchAddConfiguration|BatteryPowerSwitchAddConfiguration" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: 能看到缓存属性、append 成功/失败记录、Add success finalize。

- [ ] **Step 7: Commit Classic Add change**

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
git commit -m "feat: configure battery switch during classic add"
```

## Task 4: Professional Add Uses Default BPS Configuration

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 增加 Add 阶段 BPS 状态缓存**

在 `private var addSuccessNodes: [Node] = []` 附近加入：

```swift
private var batteryPowerSwitchAddConfigurations: [Address: PJEightKeySwitchData] = [:]
private var failedBatteryPowerSwitchAddConfigurationAddresses: Set<Address> = []
```

- [ ] **Step 2: 在 appendMessagesBack 中追加默认 BPS configuration**

在 `appendMessagesBack` closure 内、`appendCompletion(appendMessages)` 前加入：

```swift
if BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node),
   let switchData = BatteryPowerSwitchAddConfiguration.prepareSwitchData(for: node) {
    batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
    let handles = BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(for: switchData, node: node)
    if handles.isEmpty {
        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
    } else {
        appendMessages.append(contentsOf: handles)
    }
}
```

- [ ] **Step 3: 增加 appendMessageFailedBack**

在 `appendMessageSuccessBack` closure 后、`addSuccess` closure 前加入：

```swift
} appendMessageFailedBack: { [weak self] messageHandle in
    guard let self else { return }
    guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
        return
    }
    if self.batteryPowerSwitchAddConfigurations[address] != nil {
        self.failedBatteryPowerSwitchAddConfigurationAddresses.insert(address)
    }
```

- [ ] **Step 4: 增加 Add success 状态落盘 helper**

在 `disconnectBatteryPowerSwitchNodes(_:)` 附近加入：

```swift
private func finalizeBatteryPowerSwitchAddConfiguration(for node: Node) {
    guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) else {
        return
    }
    guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress]
        ?? MeshNetworkManager.instance.createDefaultSwitch(forBatteryPowerSwitch: node)?.batteryPowerSwitchData else {
        return
    }

    if failedBatteryPowerSwitchAddConfigurationAddresses.contains(node.primaryUnicastAddress) {
        BatteryPowerSwitchAddConfiguration.markFailed(switchData, reason: "sync_failed".localizedString)
    } else {
        BatteryPowerSwitchAddConfiguration.markSucceeded(switchData)
    }

    batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
    failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
}
```

- [ ] **Step 5: 在 addSuccess 中使用 helper**

将 `addSuccess` 内现有 BPS 创建逻辑：

```swift
if node.isBatteryPowerSwitch {
    MeshNetworkManager.instance.createDefaultSwitch(forBatteryPowerSwitch: node)
}
```

替换为：

```swift
if node.isBatteryPowerSwitch {
    finalizeBatteryPowerSwitchAddConfiguration(for: node)
}
```

- [ ] **Step 6: 静态检查 Professional Add**

Run:

```bash
rg -n "batteryPowerSwitchAddConfigurations|failedBatteryPowerSwitchAddConfigurationAddresses|appendMessageFailedBack|finalizeBatteryPowerSwitchAddConfiguration|BatteryPowerSwitchAddConfiguration" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: 能看到缓存属性、append 成功/失败记录、Add success finalize。

- [ ] **Step 7: Commit Professional Add change**

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "feat: configure battery switch during professional add"
```

## Task 5: BPS SAVE Target Group Uses Differential Handles

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 确认任务生成不强制 includeExisting**

在 `makeBatteryPowerSwitchTargetGroupModel` 中，确保代码为：

```swift
let handles = unsubscribe
    ? node.getBatteryPowerSwitchUnsubscriptionMessageHandles(switchGroup: switchGroup)
    : node.getBatteryPowerSwitchSubscriptionMessageHandles(switchGroup: switchGroup)
```

- [ ] **Step 2: 确认实际下发不强制 includeExisting**

在 `DeviceOperationType.messageHandles` 的 `.batteryPowerSwitchTargetSubscription` 分支中，确保代码为：

```swift
case .batteryPowerSwitchTargetSubscription(let switchData, _, let unsubscribe):
    messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: unsubscribe))
```

在 `.configuration` 的 `.enOceanSwitch` 分支中，确保 BPS 分流代码为：

```swift
if switchData.batteryPowerSwitchData != nil {
    messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: false))
    break
}
```

- [ ] **Step 3: 静态检查 includeExisting**

Run:

```bash
rg -n "batteryPowerSwitchTargetSubscription|getBatteryPowerSwitchSubscriptionMessageHandles\\(switchGroup: switchGroup, includeExisting: true\\)|getBatteryPowerSwitchTargetSubscriptionMessageHandles\\(switchData: switchData, unsubscribe: false, includeExisting: true\\)" SunSmart/Main/Space
```

Expected: 不再出现 BPS target subscription 使用 `includeExisting: true`；reset 后 model publication 的 `includeExisting: true` 不在本检查范围内。

- [ ] **Step 4: Commit differential target group change**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: sync battery switch target group differences"
```

## Task 6: BPS SAVE Execution Order

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 让 BPS configuration section 先执行设备再执行 group**

在 `appendBatteryPowerSwitchItems(...)` 创建 `switchDeviceModel` 前加入：

```swift
section.prefersDevicesBeforeGroups = true
```

- [ ] **Step 2: BPS 类型按 configuration section 再 remove section 追加**

在 `setupDataSource()` 末尾当前统一追加 section 的代码前，加入 BPS 专用分支：

```swift
let appendSectionIfNeeded: (SyncDevicesSectionModel) -> Void = { section in
    if section.groups.count > 0 || section.devices.count > 0 || section.switchProxy != nil {
        self.sections.append(section)
    }
}

if case .batteryPowerSwitch = self.type {
    appendSectionIfNeeded(configurationSection)
    appendSectionIfNeeded(removeSection)
} else {
    appendSectionIfNeeded(removeSection)
    appendSectionIfNeeded(configurationSection)
}
```

并移除原来的重复 section 追加代码：

```swift
if removeSection.groups.count > 0 || removeSection.devices.count > 0 || removeSection.switchProxy != nil {
    self.sections.append(removeSection)
}
if configurationSection.groups.count > 0 || configurationSection.devices.count > 0 || configurationSection.switchProxy != nil {
    self.sections.append(configurationSection)
}
```

- [ ] **Step 3: 依赖未成功时不调度当前 step**

在 `getNextHandleModel()` 中，将 step 依赖判断改为：

```swift
if step.relevanceStepModels.contains(where: { $0.state == .failed }) {
    continue
}
if step.relevanceStepModels.contains(where: { $0.state != .successful }) {
    continue
}
```

保留 task 级 `relevanceTaskModels` 失败判断不变。

- [ ] **Step 4: 静态检查执行顺序代码**

Run:

```bash
rg -n "appendSectionIfNeeded|case \\.batteryPowerSwitch|prefersDevicesBeforeGroups = true|relevanceStepModels.contains\\(where: \\{ \\$0.state != \\.successful \\}\\)" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: 能看到 BPS section 顺序、devices-before-groups 和依赖成功等待。

- [ ] **Step 5: Commit BPS SAVE ordering**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: order battery switch save commands"
```

## Task 7: Verification

**Files:**
- Verify only.

- [ ] **Step 1: 检查 BPS PID 限定**

Run:

```bash
rg -n "0x2A01|0x2A02|BatteryPowerSwitchAddConfiguration" SunSmart/Main/Device SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: Add 默认配置 helper 只针对 `0x2A01`、`0x2A02`；现有 `Node.isBatteryPowerSwitch` 常量仍为这两个 PID。

- [ ] **Step 2: 检查 SDK working tree**

Run:

```bash
git -C ../../../nordic-sig-mesh-sdk status --short
```

Expected: 没有未提交的计划内 SDK 改动；如果还有 `MeshProxyMessageCommand.swift` 或 ACK matching 测试未提交，它们属于既有工作，不能回滚。

- [ ] **Step 3: 检查 App working tree**

Run:

```bash
git status --short
```

Expected: 只剩用户已有未提交文件或后续任务明确保留的文件；本计划实现文件已按任务提交。

- [ ] **Step 4: App 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 最终 diff 检查**

Run:

```bash
git diff --check
git -C ../../../nordic-sig-mesh-sdk diff --check
```

Expected: 两条命令均无输出。

- [ ] **Step 6: Manual QA checklist**

在可连接真实设备或等效测试环境时验证：

- Add `0x2A01`，默认 Scene Profile configuration 成功后，Switch 列表不显示未同步。
- Add `0x2A02`，默认 Brightness Profile configuration 成功后，Switch 列表不显示未同步。
- 让默认 BPS append configuration 中任一 ACK 超时或失败，设备仍在 Add success list，Switch 列表显示未同步。
- Brightness Profile 未变化，新增 group A，只下发 group A configuration。
- Brightness Profile 未变化，删除 group A，只下发 remove A group。
- Brightness Profile 未变化，新增 group A 且删除 group B，先下发 group A configuration，再下发 remove group B。
- Profile 切换或 Scene Profile scene 关联变化时，先下发 switch configuration，再下发 group add，最后下发 group remove。

## Plan Self-Review

- Spec 覆盖：Add 默认配置、PID 限定、配置失败但 Add 成功、SAVE 命令顺序、scene 关联变化、非 BPS 不受影响均有任务覆盖。
- 文档内容完整：每个代码修改步骤都有目标文件、代码片段、检查命令和预期结果。
- 类型一致：计划中使用的 `PJEightKeySwitchData`、`MeshMessageHandle.continuous`、`appendMessageFailedBack`、`SyncDevicesSectionModel.prefersDevicesBeforeGroups`、`BatteryPowerSwitchAddConfiguration` 在任务内定义或为现有类型。
