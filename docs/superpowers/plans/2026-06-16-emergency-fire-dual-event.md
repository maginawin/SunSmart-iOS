# Emergency Fire Dual Event Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Emergency Fire Controller 添加虚拟设备、Edit 虚拟设备、Edit 真实设备页面迁移为 Fire Alarm 与 Power Loss 双事件同时配置，并使用 SDK v2 同步三种 state。

**Architecture:** 先移除 App 配置层的旧 `workMode` 事实来源，让 `powerLossSettings` 与 `fireAlarmSettings` 同时有效，再把编辑页 state/table 改为单一 group 选择和统一 event end 配置。同步 planner 以两个 trigger state 和一个 restore state 生成 vendor action/resend，并以 group address 去重关联任务。

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, existing `DeviceEmerFireStore`, `LinkedEmerFireEditVC`, `SyncDevicesViewController`, iPhoneOS `xcodebuild`.

---

## File Structure

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
  - 配置模型事实来源、默认值、restore action type、SDK action/resend 派生。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - EFC 数据对象的 settings 访问、pending cleanup 合并、controller sync task 生成。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - 关联灯组与 cleanup 任务规划，按 group 去重，去掉 active mode 依赖。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`
  - 编辑页状态、默认值、范围 clamp、group 冲突判断、保存配置生成。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift`
  - 新页面 row 枚举和 section/card 分组。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
  - 页面 rows、cells、group picker、action type picker。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - 保存前校验、LINK/LINKED 底部状态、创建/保存流程保持。
- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`
  - save/create 后 sync dirty 判断使用新配置结构。
- `SunSmart.xcodeproj/project.pbxproj`
  - 仅当新增 Swift 文件时同步 target source 列表。

资源规则：实施中先搜索现有 assets 和现有 cell 资源。缺少图片资源时暂停并向用户确认，不新增自绘 SVG、临时图片或手动画图。

---

### Task 1: Update Configuration Model

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`

- [ ] **Step 1: Remove `workMode` as configuration state**

Open `LinkedEmerFireConfig.swift` and delete `EmergencyFireControllerWorkMode` from the desired configuration model. Keep mode-like concepts only where needed for pending cleanup keys.

Replace the configuration struct with this shape:

```swift
enum EmergencyFireControllerFunction: String, Codable, CaseIterable, Equatable {
    case powerLossEmergency
    case fireAlarmEmergency
}

enum EmergencyFireRestoreActionType: String, Codable, Equatable {
    case restoreAuto
    case setBrightness
    case none
}

struct EmergencyFireControllerRestoreSettings: Codable, Equatable {
    var actionType: EmergencyFireRestoreActionType
    var brightness: Int
    var resumingSeconds: UInt8
    var sendCount: UInt16

    static let defaultValue = EmergencyFireControllerRestoreSettings(
        actionType: .restoreAuto,
        brightness: 100,
        resumingSeconds: 2,
        sendCount: 2
    )
}

struct EmergencyFireControllerConfiguration: Codable, Equatable {
    var powerLossSettings: EmergencyFireControllerModeSettings
    var fireAlarmSettings: EmergencyFireControllerModeSettings
    var restoreSettings: EmergencyFireControllerRestoreSettings

    static let defaultValue = EmergencyFireControllerConfiguration(
        powerLossSettings: .powerLossDefaultValue,
        fireAlarmSettings: .fireAlarmDefaultValue,
        restoreSettings: .defaultValue
    )
}
```

Expected: `EmergencyFireControllerConfiguration` no longer stores `workMode`.

- [ ] **Step 2: Split mode settings defaults**

In `EmergencyFireControllerModeSettings`, replace `defaultValue` with explicit defaults:

```swift
static let powerLossDefaultValue = EmergencyFireControllerModeSettings(
    associateGroupAddresses: [],
    triggerBrightness: 10,
    triggerIntervalSeconds: 5,
    triggerCount: 0xFFFF,
    pendingUnassociateGroupAddresses: []
)

static let fireAlarmDefaultValue = EmergencyFireControllerModeSettings(
    associateGroupAddresses: [],
    triggerBrightness: 100,
    triggerIntervalSeconds: 5,
    triggerCount: 0xFFFF,
    pendingUnassociateGroupAddresses: []
)
```

Remove per-mode restore fields from this struct:

```swift
var stopIntervalSeconds: UInt16
var stopCount: UInt16
var restoreDelaySeconds: UInt8
var restoreActionPreset: EmergencyFireControllerActionPreset?
```

Expected: trigger settings contain only associated groups, trigger brightness, trigger resend interval/count, action preset, and pending cleanup.

- [ ] **Step 3: Implement derived configuration helpers**

Add these helpers to `EmergencyFireControllerConfiguration`:

```swift
var enabled: Bool { true }

var activeLightLCGroupAddresses: Set<Address> {
    Set(powerLossSettings.associateGroupAddresses + fireAlarmSettings.associateGroupAddresses)
}

var hasPendingCleanup: Bool {
    !powerLossSettings.pendingUnassociateGroupAddresses.isEmpty ||
    !fireAlarmSettings.pendingUnassociateGroupAddresses.isEmpty
}

var hasSyncIntent: Bool {
    !activeLightLCGroupAddresses.isEmpty || hasPendingCleanup
}

func resendParameters(for state: EmergencyFireControllerState) -> EmergencyFireResendParameters {
    switch state {
    case .emergencyTrigger:
        return .init(
            stateIndex: state.sdkStateIndex,
            intervalSeconds: powerLossSettings.triggerIntervalSeconds,
            count: powerLossSettings.triggerCount
        )
    case .fireTrigger:
        return .init(
            stateIndex: state.sdkStateIndex,
            intervalSeconds: fireAlarmSettings.triggerIntervalSeconds,
            count: fireAlarmSettings.triggerCount
        )
    case .restore:
        return .init(
            stateIndex: state.sdkStateIndex,
            intervalSeconds: 5,
            count: restoreSettings.sendCount
        )
    }
}

func restoreDelaySeconds() -> UInt8 {
    restoreSettings.resumingSeconds
}
```

Expected: resend and restore delay no longer depend on `workMode`.

- [ ] **Step 4: Implement action derivation**

Update `action(for:)` to use both trigger settings and the restore settings:

```swift
private func action(for state: EmergencyFireControllerState) -> EmergencyFireAction? {
    switch state {
    case .emergencyTrigger:
        return powerLossSettings.triggerActionPreset?.sdkAction
            ?? .lightness(Self.lightness(from: powerLossSettings.triggerBrightness))
    case .fireTrigger:
        return fireAlarmSettings.triggerActionPreset?.sdkAction
            ?? .lightness(Self.lightness(from: fireAlarmSettings.triggerBrightness))
    case .restore:
        switch restoreSettings.actionType {
        case .restoreAuto:
            return .lightControlOnOff(1)
        case .setBrightness:
            return .lightness(Self.lightness(from: restoreSettings.brightness))
        case .none:
            return .invalid
        }
    }
}
```

Expected: restore no longer emits CTL color-temperature control.

- [ ] **Step 5: Update default clear configuration**

In `DeviceEmerFireData.clearMonitoringConfiguration()`, replace construction of `EmergencyFireControllerConfiguration(workMode:...)` with:

```swift
configuration = .defaultValue
```

Expected: the file compiles after `workMode` is removed.

- [ ] **Step 6: Run targeted search**

Run:

```bash
rg -n "workMode|activeSettings|activeLightLCGroupAddresses|restoreDelaySeconds|stopCount|stopIntervalSeconds" SunSmart/Main/Device/Device1.5/FireAlarm
```

Expected: remaining `workMode` hits are only in files not yet migrated by later tasks; `LinkedEmerFireConfig.swift` should not have `configuration.workMode`.

- [ ] **Step 7: Commit model changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift
git commit -m "Refactor emergency fire configuration model"
```

Expected: commit succeeds.

---

### Task 2: Update Edit State and Validation

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`

- [ ] **Step 1: Replace old toggle state**

In `LinkedEmerFireEditState`, remove:

```swift
var enablePowerLossEmergency = true
var enableFireAlarmEmergency = false
var powerLossResuming = 2
var powerLossSendCount = 2
var fireAlarmResuming = 2
var fireAlarmSendCount = 2
```

Add:

```swift
var associatedGroupAddresses: [UInt16] = []
var fireAlarmBrightness = 100
var powerLossBrightness = 10
var triggerIntervalSeconds = 5
var restoreActionType: EmergencyFireRestoreActionType = .restoreAuto
var restoreBrightness = 100
var restoreResumingSeconds = 2
var restoreSendCount = 2
```

Expected: state has one global group selection and one restore action configuration.

- [ ] **Step 2: Update `apply(config:)`**

Replace the old workMode-derived assignment with:

```swift
configuration = config.configuration
associatedGroupAddresses = Array(configuration.activeLightLCGroupAddresses).sorted()
fireAlarmBrightness = configuration.fireAlarmSettings.triggerBrightness
powerLossBrightness = configuration.powerLossSettings.triggerBrightness
triggerIntervalSeconds = Int(configuration.powerLossSettings.triggerIntervalSeconds)
restoreActionType = configuration.restoreSettings.actionType
restoreBrightness = configuration.restoreSettings.brightness
restoreResumingSeconds = Int(configuration.restoreSettings.resumingSeconds)
restoreSendCount = Int(configuration.restoreSettings.sendCount)
normalizeStepperValues()
```

Expected: loading any EFC uses the union group selection and dual event values.

- [ ] **Step 3: Replace stepper normalization**

Implement:

```swift
private func normalizeStepperValues() {
    fireAlarmBrightness = min(max(fireAlarmBrightness, 10), 100)
    powerLossBrightness = min(max(powerLossBrightness, 1), 100)
    triggerIntervalSeconds = min(max(triggerIntervalSeconds, 1), 10)
    restoreBrightness = min(max(restoreBrightness, 1), 100)
    restoreResumingSeconds = min(max(restoreResumingSeconds, 0), 120)
    restoreSendCount = min(max(restoreSendCount, 1), 5)
}
```

Expected: state-level values follow the confirmed ranges.

- [ ] **Step 4: Replace group selection helpers**

Replace row-specific group helpers with global versions:

```swift
func groupText() -> String {
    groupNames(for: associatedGroupAddresses)
}

func selectedGroupAddresses() -> [UInt16] {
    associatedGroupAddresses
}

func updateSelectedGroupAddresses(_ addresses: [UInt16]) {
    let sortedAddresses = addresses.sorted()
    associatedGroupAddresses = sortedAddresses
    configuration.powerLossSettings.associateGroupAddresses = sortedAddresses
    configuration.fireAlarmSettings.associateGroupAddresses = sortedAddresses
}
```

Expected: one UI selection writes both Power Loss and Fire Alarm settings.

- [ ] **Step 5: Replace disabled group calculation**

Implement a single disabled set:

```swift
func disabledAssociatedGroupAddresses() -> Set<UInt16> {
    guard let meshUUID, let meshNetworkId else { return [] }
    let devices = DeviceEmerFireStore.shared.loadDevices(meshUUID: meshUUID, meshNetworkId: meshNetworkId)
    let scopedDevices = devices.filter { device in
        if let spaceId {
            return device.spaceId == spaceId
        }
        return true
    }

    return Set(
        scopedDevices
            .filter { $0.id != deviceId }
            .flatMap {
                $0.configuration.powerLossSettings.associateGroupAddresses +
                $0.configuration.fireAlarmSettings.associateGroupAddresses
            }
    )
}
```

Expected: any same-space Power Loss or Fire Alarm occupation disables the group.

- [ ] **Step 6: Replace conflict validation**

Implement:

```swift
func conflictingAssociatedGroupNames() -> [String] {
    let conflictAddresses = disabledAssociatedGroupAddresses().intersection(associatedGroupAddresses)
    return conflictAddresses
        .sorted()
        .compactMap { address in
            MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name
        }
}
```

Expected: save guard catches conflicts even if selection UI misses disabled state.

- [ ] **Step 7: Replace stepper setters**

Update `setStepperValue(for:value:)` to clamp and write:

```swift
case .fireAlarmBrightness:
    fireAlarmBrightness = min(max(value, 10), 100)
    configuration.fireAlarmSettings.triggerBrightness = fireAlarmBrightness
case .powerLossBrightness:
    powerLossBrightness = min(max(value, 1), 100)
    configuration.powerLossSettings.triggerBrightness = powerLossBrightness
case .triggerInterval:
    triggerIntervalSeconds = min(max(value, 1), 10)
    configuration.powerLossSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
    configuration.fireAlarmSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
case .restoreBrightness:
    restoreBrightness = min(max(value, 1), 100)
    configuration.restoreSettings.brightness = restoreBrightness
case .restoreResuming:
    restoreResumingSeconds = min(max(value, 0), 120)
    configuration.restoreSettings.resumingSeconds = UInt8(restoreResumingSeconds)
case .restoreSendCount:
    restoreSendCount = min(max(value, 1), 5)
    configuration.restoreSettings.sendCount = UInt16(restoreSendCount)
```

Expected: both trigger states share the interval value.

- [ ] **Step 8: Add restore action setter**

Add:

```swift
func updateRestoreActionType(_ actionType: EmergencyFireRestoreActionType) {
    restoreActionType = actionType
    configuration.restoreSettings.actionType = actionType
}
```

Expected: table action cell can update restore action without reaching into configuration internals.

- [ ] **Step 9: Update `makeConfig()`**

Before constructing `LinkedEmerFireConfig`, sync state into configuration:

```swift
configuration.powerLossSettings.associateGroupAddresses = associatedGroupAddresses
configuration.fireAlarmSettings.associateGroupAddresses = associatedGroupAddresses
configuration.powerLossSettings.triggerBrightness = powerLossBrightness
configuration.fireAlarmSettings.triggerBrightness = fireAlarmBrightness
configuration.powerLossSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
configuration.fireAlarmSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
configuration.restoreSettings.actionType = restoreActionType
configuration.restoreSettings.brightness = restoreBrightness
configuration.restoreSettings.resumingSeconds = UInt8(restoreResumingSeconds)
configuration.restoreSettings.sendCount = UInt16(restoreSendCount)
```

Expected: saved config always reflects visible UI.

- [ ] **Step 10: Run targeted search**

Run:

```bash
rg -n "enablePowerLossEmergency|enableFireAlarmEmergency|updateEmergencySelection|clearAssociatedGroups|powerLossResuming|fireAlarmResuming|powerLossSendCount|fireAlarmSendCount" SunSmart/Main/Device/Device1.5/FireAlarm
```

Expected: no hits in `LinkedEmerFireEditState.swift`.

- [ ] **Step 11: Commit edit state changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift
git commit -m "Update emergency fire edit state"
```

Expected: commit succeeds.

---

### Task 3: Update Edit Rows and Table UI

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`

- [ ] **Step 1: Replace row enum**

Replace `LinkedEmerFireEditRow` cases with:

```swift
enum LinkedEmerFireEditRow: Int, CaseIterable {
    case name
    case reportToGateway
    case associatedGroups
    case eventOccursHeader
    case fireAlarmBrightness
    case powerLossBrightness
    case triggerInterval
    case eventEndsHeader
    case restoreAction
    case restoreBrightness
    case restoreResuming
    case restoreSendCount
}
```

Expected: no toggle or old instruction rows remain.

- [ ] **Step 2: Update card groups**

Replace `CardGroup` with:

```swift
enum CardGroup {
    case name
    case report
    case groups
    case eventOccursHeader
    case eventOccurs
    case eventEndsHeader
    case eventEnds
}
```

Map rows:

```swift
case .name:
    return .name
case .reportToGateway:
    return .report
case .associatedGroups:
    return .groups
case .eventOccursHeader:
    return .eventOccursHeader
case .fireAlarmBrightness, .powerLossBrightness, .triggerInterval:
    return .eventOccurs
case .eventEndsHeader:
    return .eventEndsHeader
case .restoreAction, .restoreBrightness, .restoreResuming, .restoreSendCount:
    return .eventEnds
```

Expected: visual grouping matches the new page.

- [ ] **Step 3: Add action type configuration struct**

In `LinkedEmerFireEditRow.swift`, keep `LinkedEmerFireStepperConfiguration` and add:

```swift
struct LinkedEmerFireRestoreActionOption {
    let title: String
    let actionType: EmergencyFireRestoreActionType
}
```

Expected: table UI has a typed option model.

- [ ] **Step 4: Replace `visibleRows`**

In `LinkedEmerFireEditVC+Table.swift`, implement:

```swift
private var visibleRows: [LinkedEmerFireEditRow] {
    var rows: [LinkedEmerFireEditRow] = [
        .name,
        .reportToGateway,
        .associatedGroups,
        .eventOccursHeader,
        .fireAlarmBrightness,
        .powerLossBrightness,
        .triggerInterval,
        .eventEndsHeader,
        .restoreAction
    ]
    if state.restoreActionType == .setBrightness {
        rows.append(.restoreBrightness)
    }
    rows.append(contentsOf: [
        .restoreResuming,
        .restoreSendCount
    ])
    return rows
}
```

Expected: restore brightness is conditional.

- [ ] **Step 5: Render section headers**

For `.eventOccursHeader` and `.eventEndsHeader`, use `EmerFireInfoCell` or a new lightweight local header cell only if existing `EmerFireInfoCell` cannot render title + detail without bullets. Configure:

```swift
case .eventOccursHeader:
    cell.configure(
        title: "When The Emergency Event Occurs:",
        lines: ["Fire emergency take higher priority."],
        cardPosition: cardPosition(for: row)
    )
case .eventEndsHeader:
    cell.configure(
        title: "When The Emergency Event Ends:",
        lines: ["Execution will only begin after all emergency events have ceased."],
        cardPosition: cardPosition(for: row)
    )
```

Expected: no old multi-step instruction text remains.

- [ ] **Step 6: Render global group row**

Replace `.powerLossGroups` / `.fireAlarmGroups` with:

```swift
case .associatedGroups:
    let cell: EmerFireSelectionCell = tableView.dequeueReusableCell(for: indexPath)
    cell.configure(
        title: "Associate With Group(s)".localizedString,
        value: state.groupText(),
        cardPosition: cardPosition(for: row)
    )
    return cell
```

Expected: only one group picker row appears.

- [ ] **Step 7: Render steppers**

Use `state.stepperConfiguration(for:)` for:

```swift
case .fireAlarmBrightness, .powerLossBrightness, .triggerInterval, .restoreBrightness, .restoreResuming, .restoreSendCount:
    let cell: EmerFireStepperCell = tableView.dequeueReusableCell(for: indexPath)
    let config = state.stepperConfiguration(for: row)
    cell.configure(title: config.title, value: config.value, range: config.range, suffix: config.suffix, cardPosition: cardPosition(for: row))
    cell.valueDidChange = { [weak self] value in
        self?.state.setStepperValue(for: row, value: value)
    }
    return cell
```

Expected: existing plus/minus/slider resources are reused.

- [ ] **Step 8: Render restore action type**

Implement `restoreAction` using existing button/radio resources. First search:

```bash
rg --files SunSmart/Assets.xcassets | rg 'select|radio|check|un'
```

If suitable selected/unselected images exist, create a small UITableViewCell in `LinkedEmerFireEditVC+Table.swift` using those image names. If no suitable resources exist, stop and ask the user to upload resources.

Cell behavior:

```swift
cell.configure(
    selected: state.restoreActionType,
    options: [
        .init(title: "Restore AUTO", actionType: .restoreAuto),
        .init(title: "Set Brightness to", actionType: .setBrightness),
        .init(title: "None", actionType: .none)
    ],
    cardPosition: cardPosition(for: row)
)
cell.selectionDidChange = { [weak self] actionType in
    guard let self else { return }
    self.state.updateRestoreActionType(actionType)
    self.tableView.reloadData()
}
```

Expected: default selected action is Restore AUTO; selecting Set Brightness to reveals restore brightness.

- [ ] **Step 9: Update group picker selection**

In `didSelectRowAt`, replace old group cases with:

```swift
case .associatedGroups:
    let controller = PJDeviceGroupSelectionViewController(
        context: .init(
            title: "select_group(s)".localizedString,
            groups: DeviceEmerFireStore.shared.selectableGroups(),
            selectedGroupAddresses: state.selectedGroupAddresses(),
            disabledGroupAddresses: state.disabledAssociatedGroupAddresses(),
            disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type.".localizedString
        )
    ) { [weak self] addresses in
        self?.state.updateSelectedGroupAddresses(addresses)
        self?.tableView.reloadRows(at: [indexPath], with: .none)
    }
    navigationController?.pushViewController(controller, animated: true)
```

Expected: group selection applies to both functions.

- [ ] **Step 10: Update title**

In `LinkedEmerFireEditVC.setupNavigation()`, use:

```swift
title = "Emer&Fire Controler"
```

Expected: matches Figma spelling unless a localized key already exists for the exact title.

- [ ] **Step 11: Run targeted search**

Run:

```bash
rg -n "powerLossGroups|fireAlarmGroups|powerLossInstructions|fireAlarmInstructions|powerRestoreInstructions|fireAlarmStopInstructions|powerLossEmergency|fireAlarmEmergency" SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift
```

Expected: no hits.

- [ ] **Step 12: Commit UI row changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
git commit -m "Update emergency fire edit layout"
```

Expected: commit succeeds.

---

### Task 4: Update Sync Planner for Dual Events

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift` if display text references removed fields.

- [ ] **Step 1: Replace settings accessors**

In `DeviceEmerFireData+Sync.swift`, replace mode-based accessors with function-based accessors:

```swift
func settings(for function: EmergencyFireControllerFunction) -> EmergencyFireControllerModeSettings {
    switch function {
    case .powerLossEmergency:
        return configuration.powerLossSettings
    case .fireAlarmEmergency:
        return configuration.fireAlarmSettings
    }
}

func updateSettings(_ settings: EmergencyFireControllerModeSettings, for function: EmergencyFireControllerFunction) {
    switch function {
    case .powerLossEmergency:
        configuration.powerLossSettings = settings
    case .fireAlarmEmergency:
        configuration.fireAlarmSettings = settings
    }
}
```

Expected: no accessor accepts `.allDisabled`.

- [ ] **Step 2: Update `hasSyncableConfiguration`**

Use:

```swift
var hasSyncableConfiguration: Bool {
    configuration.hasSyncIntent
}
```

Expected: sync status considers both functions and pending cleanup.

- [ ] **Step 3: Update pending changes merge**

In `mergePendingChanges(from:to:)`, keep the same cleanup behavior but iterate functions:

```swift
EmergencyFireControllerFunction.allCases.forEach { function in
    let oldSettings = oldConfiguration.settings(for: function)
    let newSettings = newConfiguration.settings(for: function)
    mergePendingChanges(
        for: function,
        oldSettings: oldSettings,
        newSettings: newSettings,
        newDesiredGroups: newDesiredGroups,
        noLongerDesiredGroups: noLongerDesiredGroups
    )
}
```

Add this helper to `EmergencyFireControllerConfiguration` in Task 1 if not already present:

```swift
func settings(for function: EmergencyFireControllerFunction) -> EmergencyFireControllerModeSettings {
    switch function {
    case .powerLossEmergency:
        return powerLossSettings
    case .fireAlarmEmergency:
        return fireAlarmSettings
    }
}
```

Expected: pending cleanup records removed groups per function.

- [ ] **Step 4: Update task pending type**

In `EmergencyFireControllerSyncPlan.swift`, change `pendingModes: [EmergencyFireControllerWorkMode]` to:

```swift
let pendingFunctions: [EmergencyFireControllerFunction]
```

Update initializer parameter names accordingly:

```swift
pendingFunctions: [EmergencyFireControllerFunction] = []
```

Expected: sync tasks no longer mention work modes.

- [ ] **Step 5: Update `clearPending(for:)`**

Use:

```swift
guard !task.pendingFunctions.isEmpty else { return }

task.pendingFunctions.forEach { function in
    guard let groupAddress = task.pendingGroupAddress else { return }
    var settings = settings(for: function)
    if task.clearsUnassociatePending {
        settings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
    }
    updateSettings(settings, for: function)
}
save(meshUUID: meshUUID, networkId: subnetworkId)
```

Expected: local pending cleanup clears per function.

- [ ] **Step 6: Replace active mode associate planning**

In `EmergencyFireControllerSyncPlanner`, replace `makeActiveModeAssociateItems()` with:

```swift
func makeAssociatedGroupItems() throws -> [EmergencyFireControllerSyncItem] {
    guard let publishGroup = data.publishGroup else { return [] }
    let allAddresses = data.configuration.activeLightLCGroupAddresses.sorted()
    return allAddresses.compactMap { address in
        guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
            return nil
        }
        let brightness = associatedBrightness(for: address)
        var tasks = group.nodes.flatMap {
            makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, brightness: brightness)
        }
        if data.configuration.restoreSettings.actionType == .restoreAuto {
            tasks.append(makeAutoRestoreTask(group: group))
        }
        return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
    }
}
```

Add:

```swift
private func associatedBrightness(for groupAddress: Address) -> Int {
    if data.configuration.fireAlarmSettings.associateGroupAddresses.contains(groupAddress) {
        return data.configuration.fireAlarmSettings.triggerBrightness
    }
    return data.configuration.powerLossSettings.triggerBrightness
}
```

Expected: each group appears once. If both events share the same group, Fire Alarm brightness is used for the retained trigger scene store task because Fire has higher priority.

- [ ] **Step 7: Remove trigger scene mode argument**

Change `makeAssociateTasks` signature to:

```swift
func makeAssociateTasks(node: Node, group: Group, publishGroup: Group, brightness: Int) -> [EmergencyFireControllerSyncTask]
```

Inside it, remove `triggerScene` parameter and call:

```swift
if let triggerTask = makeTriggerSceneStoreTask(node: node, triggerScene: DeviceEmerFireData.fireAlarmTriggerSceneNumber, brightness: brightness) {
    tasks.append(triggerTask)
}
```

Expected: scene store no longer branches by work mode. The actual v2 action config is the source of event-specific behavior.

- [ ] **Step 8: Update cleanup functions**

Replace pending mode helpers:

```swift
func pendingCleanupFunctions(for groupAddress: Address) -> [EmergencyFireControllerFunction] {
    EmergencyFireControllerFunction.allCases.filter { function in
        data.settings(for: function).pendingUnassociateGroupAddresses.contains(groupAddress)
    }
}
```

Update local group collection:

```swift
private func pendingCleanupGroups() -> [(address: Address, functions: [EmergencyFireControllerFunction])] {
    var groups: [Address: [EmergencyFireControllerFunction]] = [:]
    EmergencyFireControllerFunction.allCases.forEach { function in
        data.settings(for: function).pendingUnassociateGroupAddresses.forEach { address in
            groups[address, default: []].append(function)
        }
    }
    return groups.map { (address: $0.key, functions: $0.value) }.sorted { $0.address < $1.address }
}
```

Expected: cleanup no longer references work modes.

- [ ] **Step 9: Update `makeItems()`**

Replace:

```swift
items.append(contentsOf: try makeActiveModeAssociateItems())
items.append(contentsOf: try makeActiveModeCleanupItems())
```

with:

```swift
items.append(contentsOf: try makeAssociatedGroupItems())
items.append(contentsOf: try makeCleanupItems())
```

Rename `makeActiveModeCleanupItems` to `makeCleanupItems`.

Expected: sync planner executes dual-event association.

- [ ] **Step 10: Update group mutation sync**

In `makeGroupMutationItems`, replace active mode logic with:

```swift
let activeDesiredGroups = controller.configuration.activeLightLCGroupAddresses
let groupAddress = group.address.address
let groupIsActiveDesired = activeDesiredGroups.contains(groupAddress)
let pendingFunctions = planner.pendingCleanupFunctions(for: groupAddress)

var tasks: [EmergencyFireControllerSyncTask] = []
if groupIsActiveDesired {
    let brightness = planner.associatedBrightness(for: groupAddress)
    tasks.append(contentsOf: addNodes.flatMap {
        planner.makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, brightness: brightness)
    })
}

if groupIsActiveDesired || !pendingFunctions.isEmpty {
    tasks.append(contentsOf: exitNodes.flatMap {
        planner.makeLightLCCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingFunctions: pendingFunctions)
    })
}
```

Expected: group member changes update EFC associations without active mode.

- [ ] **Step 11: Run targeted search**

Run:

```bash
rg -n "EmergencyFireControllerWorkMode|activeMode|activeModeSettings|makeActiveMode|pendingModes|triggerSceneNumber\\(" SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected: no remaining references that drive EFC configuration. Display-only old text should be updated or removed.

- [ ] **Step 12: Commit sync changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "Update emergency fire dual event sync"
```

Expected: commit succeeds. If `SyncDevicesViewController.swift` or `SyncDevicesCellModel.swift` did not change, omit them from `git add`.

---

### Task 5: Update Monitor and Display References

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`

- [ ] **Step 1: Search monitor workMode usage**

Run:

```bash
rg -n "workMode|powerLossEmergency|fireAlarmEmergency|allDisabled|currentWorkMode" SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitor*
```

Expected: output lists all monitor branches that still assume one active mode.

- [ ] **Step 2: Replace monitor summaries**

For monitor text that previously chose one mode, show both configured trigger values. Use these display facts:

```swift
let powerLossBrightness = data.configuration.powerLossSettings.triggerBrightness
let fireAlarmBrightness = data.configuration.fireAlarmSettings.triggerBrightness
let groupCount = data.configuration.activeLightLCGroupAddresses.count
```

Expected: monitor no longer hides one event because of `workMode`.

- [ ] **Step 3: Keep comprehensive status mapping**

Do not change SDK GET if it already uses:

```swift
SunricherVendorGet(function: .emergencyComprehensiveStatus)
```

Expected: monitor still reads v2 status.

- [ ] **Step 4: Remove disabled mode display**

Delete any UI branch that treats `allDisabled` as a configured display state. Empty associated groups should be represented by normal empty/unsynced configuration behavior, not old disabled mode.

Expected: no user-facing disabled workMode state remains.

- [ ] **Step 5: Commit monitor display changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
git commit -m "Update emergency fire monitor display"
```

Expected: commit succeeds. If a searched file did not change, omit it from `git add`.

---

### Task 6: Compile Fixes and Verification

**Files:**
- Modify only files required by compiler errors under `SunSmart/Main/Device/Device1.5/FireAlarm/`
- Modify `SunSmart.xcodeproj/project.pbxproj` only if a new Swift file was added

- [ ] **Step 1: Run source searches**

Run:

```bash
rg -n "EmergencyFireControllerWorkMode|workMode|enablePowerLossEmergency|enableFireAlarmEmergency|powerLossResuming|fireAlarmResuming|fireAlarmStopInstructions|powerRestoreInstructions|CTL_SET|ctl\\(" SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Space
```

Expected:
- No EFC configuration code uses `workMode`.
- No edit UI code uses old enable toggles or old per-mode restore rows.
- No restore default still emits CTL.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Fix compile errors narrowly**

If the build reports missing properties or enum cases from the migration, edit only the named FireAlarm file and replace the old usage with the new dual-event equivalent. Examples:

```swift
configuration.workMode != .allDisabled
```

becomes:

```swift
configuration.hasSyncIntent
```

and:

```swift
configuration.activeSettings
```

becomes explicit function settings:

```swift
configuration.powerLossSettings
configuration.fireAlarmSettings
```

Expected: fixes stay inside Emergency Fire scope unless compiler points to display code in SyncDevices.

- [ ] **Step 4: Re-run build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Verify changed files**

Run:

```bash
git diff --name-only
git status --short
```

Expected:
- Changed files are limited to Emergency Fire implementation files, project file only if new Swift files were added, and no unrelated untracked file is staged.
- `docs/260616_1156_proximity_photocell_group_add_commands.md` remains untracked and unstaged.

- [ ] **Step 7: Commit final fixes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart.xcodeproj/project.pbxproj
git diff --cached --name-only
git diff --cached --check
git commit -m "Implement emergency fire dual event editor"
```

Expected: commit includes only relevant implementation files. If `SunSmart.xcodeproj/project.pbxproj`, `SyncDevicesViewController.swift`, or `SyncDevicesCellModel.swift` did not change, omit them from `git add`.

---

## Self-Review

- Spec coverage:
  - Dual event display and no two-choice logic: Tasks 1, 2, 3.
  - Global Associate With Group(s): Tasks 2 and 3.
  - Same-space same-function group exclusion: Task 2.
  - Brightness only, no color temperature: Tasks 1 and 4.
  - Event occurs defaults/ranges: Tasks 1, 2, 3.
  - Event ends defaults/ranges/action types: Tasks 1, 2, 3.
  - Add virtual/Edit virtual/Edit real reuse: Task 3 and existing `LinkedEmerFireEditVC` flow, verified in Task 6.
  - SDK v2 resend/action sync: Task 4.
  - No old workMode migration: Task 1 and Task 6.
  - Resource rule: Task 3 Step 8.
- Placeholder scan: no placeholder or fill-later instructions are present.
- Type consistency:
  - `EmergencyFireControllerFunction` is introduced before sync tasks use it.
  - `EmergencyFireRestoreActionType` and `EmergencyFireControllerRestoreSettings` are introduced before edit state and action cell use them.
  - `pendingFunctions` replaces `pendingModes` consistently in sync task planning.
