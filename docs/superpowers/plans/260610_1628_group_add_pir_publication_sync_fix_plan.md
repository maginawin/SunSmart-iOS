# Group Add PIR Publication Sync Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复批量 Add Device 到 group members 后，带 PIR light 残留 Sensor Server publication 待同步的问题。

**Architecture:** 在 `DeviceGroupDeferredSyncPlanner` 中接收可选 `GroupProfileSyncContext`，让 Add Device 自动入组路径使用 `.memberAdded` 语义生成 deferred profile tasks。Classic 和 Professional 添加页在收尾执行 deferred sync 前，根据 `addFinish` 的 `successList` 与已有 `addSuccessNodes` 补齐缺失 plan，并按 node address 去重，避免多设备回调顺序导致某个设备的 publication task 未执行。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Add Device / group deferred sync 流程。

---

## Scope

实现设计文档：

- `docs/superpowers/specs/260610_1623_group_add_pir_publication_sync_design.md`

本计划只修改：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

不新增文件，不修改资源、本地化、target 配置或 SDK。

## Task 1: 扩展 deferred sync planner

**Files:**

- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [ ] **Step 1: 更新 makePlan 签名**

把：

```swift
static func makePlan(node: Node, group: Group) -> DeviceGroupDeferredSyncPlan {
    let syncDatas = node.getSyncData(type: .group(group))
```

改为：

```swift
static func makePlan(
    node: Node,
    group: Group,
    profileSyncContext: GroupProfileSyncContext? = nil
) -> DeviceGroupDeferredSyncPlan {
    let syncDatas = node.getSyncData(type: .group(group), profileSyncContext: profileSyncContext)
```

- [ ] **Step 2: 运行符号检查**

Run:

```sh
rg -n "static func makePlan|profileSyncContext|node.getSyncData\\(type: \\.group\\(group\\)" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- `makePlan` 签名包含 `profileSyncContext: GroupProfileSyncContext? = nil`
- `node.getSyncData` 调用传入 `profileSyncContext`

## Task 2: 修复 Classic Add Device deferred plan 收尾

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: 新增 member-added context helper**

在 `pendingGroupDeferredSyncSuccessDevices` 属性之后加入：

```swift
private var groupMemberAddedProfileSyncContext: GroupProfileSyncContext {
    GroupProfileSyncContext(reason: .memberAdded)
}
```

- [ ] **Step 2: 新增 pending plan 补齐 helper**

在 `finishGroupDeferredSyncPlans(completion:)` 前加入：

```swift
private func appendMissingGroupDeferredSyncPlans(successDevices: [ProvisioningDevice]) {
    guard let group = addToGroup else {
        return
    }

    var plannedNodeAddresses = Set(pendingGroupDeferredSyncPlans.map { $0.node.primaryUnicastAddress })
    var pendingSuccessDeviceAddresses = Set(pendingGroupDeferredSyncSuccessDevices.map { $0.address })
    let successfulNodes = addSuccessNodes + successDevices.compactMap { device in
        MeshNetworkManager.instance.meshNetwork?.node(withAddress: device.address)
    }
    var handledNodeAddresses: Set<Address> = []

    successfulNodes.forEach { node in
        guard node.deviceType == .light,
              node.group == group,
              !plannedNodeAddresses.contains(node.primaryUnicastAddress),
              !handledNodeAddresses.contains(node.primaryUnicastAddress) else {
            return
        }

        let plan = DeviceGroupDeferredSyncPlanner.makePlan(
            node: node,
            group: group,
            profileSyncContext: groupMemberAddedProfileSyncContext
        )
        guard plan.hasDeferredTasks else {
            return
        }

        pendingGroupDeferredSyncPlans.append((node: node, group: group, plan: plan))
        plannedNodeAddresses.insert(node.primaryUnicastAddress)
        handledNodeAddresses.insert(node.primaryUnicastAddress)

        if let device = successDevices.first(where: { $0.address == node.primaryUnicastAddress }),
           !pendingSuccessDeviceAddresses.contains(device.address) {
            pendingGroupDeferredSyncSuccessDevices.append(device)
            pendingSuccessDeviceAddresses.insert(device.address)
        }
    }
}
```

- [ ] **Step 3: 让收尾方法接收 successList 并补齐缺失 plans**

把：

```swift
private func finishGroupDeferredSyncPlans(completion: @escaping () -> Void) {
    let plans = pendingGroupDeferredSyncPlans
```

改为：

```swift
private func finishGroupDeferredSyncPlans(successDevices: [ProvisioningDevice], completion: @escaping () -> Void) {
    appendMissingGroupDeferredSyncPlans(successDevices: successDevices)
    let plans = pendingGroupDeferredSyncPlans
```

- [ ] **Step 4: append 阶段传入 member-added context**

把 light + group append 阶段：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
```

改为：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(
    node: node,
    group: group,
    profileSyncContext: groupMemberAddedProfileSyncContext
)
```

- [ ] **Step 5: addSuccess 阶段传入 member-added context**

把 add success 阶段：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
```

改为：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(
    node: node,
    group: group,
    profileSyncContext: groupMemberAddedProfileSyncContext
)
```

- [ ] **Step 6: 更新 addFinish 调用**

把：

```swift
self.finishGroupDeferredSyncPlans { [weak self] in
```

改为：

```swift
self.finishGroupDeferredSyncPlans(successDevices: successList) { [weak self] in
```

- [ ] **Step 7: 运行 Classic 静态检查**

Run:

```sh
rg -n "groupMemberAddedProfileSyncContext|appendMissingGroupDeferredSyncPlans|finishGroupDeferredSyncPlans|DeviceGroupDeferredSyncPlanner.makePlan" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected:

- 存在 `groupMemberAddedProfileSyncContext`
- `finishGroupDeferredSyncPlans` 接收 `successDevices`
- `finishGroupDeferredSyncPlans` 调用 `appendMissingGroupDeferredSyncPlans(successDevices:)`
- Classic 中 light + group 的 `makePlan` 调用传入 `profileSyncContext`

## Task 3: 修复 Professional Add Device deferred plan 收尾

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 新增 member-added context helper**

在 `pendingGroupDeferredSyncSuccessDevices` 属性之后加入：

```swift
private var groupMemberAddedProfileSyncContext: GroupProfileSyncContext {
    GroupProfileSyncContext(reason: .memberAdded)
}
```

- [ ] **Step 2: 新增当前 group helper**

在 `addTargetNameOverride` 之后加入：

```swift
private var currentAddGroup: Group? {
    if case .group(let group) = addTarget {
        return group
    }
    return nil
}
```

- [ ] **Step 3: 新增 pending plan 补齐 helper**

在 `finishGroupDeferredSyncPlans(completion:)` 前加入：

```swift
private func appendMissingGroupDeferredSyncPlans(successDevices: [ProvisioningDevice]) {
    guard let group = currentAddGroup else {
        return
    }

    var plannedNodeAddresses = Set(pendingGroupDeferredSyncPlans.map { $0.node.primaryUnicastAddress })
    var pendingSuccessDeviceAddresses = Set(pendingGroupDeferredSyncSuccessDevices.map { $0.address })
    let successfulNodes = addSuccessNodes + successDevices.compactMap { device in
        MeshNetworkManager.instance.meshNetwork?.node(withAddress: device.address)
    }
    var handledNodeAddresses: Set<Address> = []

    successfulNodes.forEach { node in
        guard node.deviceType == .light,
              node.group == group,
              !plannedNodeAddresses.contains(node.primaryUnicastAddress),
              !handledNodeAddresses.contains(node.primaryUnicastAddress) else {
            return
        }

        let plan = DeviceGroupDeferredSyncPlanner.makePlan(
            node: node,
            group: group,
            profileSyncContext: groupMemberAddedProfileSyncContext
        )
        guard plan.hasDeferredTasks else {
            return
        }

        pendingGroupDeferredSyncPlans.append((node: node, group: group, plan: plan))
        plannedNodeAddresses.insert(node.primaryUnicastAddress)
        handledNodeAddresses.insert(node.primaryUnicastAddress)

        if let device = successDevices.first(where: { $0.address == node.primaryUnicastAddress }),
           !pendingSuccessDeviceAddresses.contains(device.address) {
            pendingGroupDeferredSyncSuccessDevices.append(device)
            pendingSuccessDeviceAddresses.insert(device.address)
        }
    }
}
```

- [ ] **Step 4: 让收尾方法接收 successList 并补齐缺失 plans**

把：

```swift
private func finishGroupDeferredSyncPlans(completion: @escaping () -> Void) {
    let plans = pendingGroupDeferredSyncPlans
```

改为：

```swift
private func finishGroupDeferredSyncPlans(successDevices: [ProvisioningDevice], completion: @escaping () -> Void) {
    appendMissingGroupDeferredSyncPlans(successDevices: successDevices)
    let plans = pendingGroupDeferredSyncPlans
```

- [ ] **Step 5: append 阶段传入 member-added context**

把 light + group append 阶段：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
```

改为：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(
    node: node,
    group: group,
    profileSyncContext: groupMemberAddedProfileSyncContext
)
```

- [ ] **Step 6: addSuccess 阶段传入 member-added context**

把 add success 阶段：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
```

改为：

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(
    node: node,
    group: group,
    profileSyncContext: groupMemberAddedProfileSyncContext
)
```

- [ ] **Step 7: 更新 addFinish 调用**

把：

```swift
self.finishGroupDeferredSyncPlans { [weak self] in
```

改为：

```swift
self.finishGroupDeferredSyncPlans(successDevices: successList) { [weak self] in
```

- [ ] **Step 8: 运行 Professional 静态检查**

Run:

```sh
rg -n "groupMemberAddedProfileSyncContext|currentAddGroup|appendMissingGroupDeferredSyncPlans|finishGroupDeferredSyncPlans|DeviceGroupDeferredSyncPlanner.makePlan" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- 存在 `groupMemberAddedProfileSyncContext`
- 存在 `currentAddGroup`
- `finishGroupDeferredSyncPlans` 接收 `successDevices`
- `finishGroupDeferredSyncPlans` 调用 `appendMissingGroupDeferredSyncPlans(successDevices:)`
- Professional 中 light + group 的 `makePlan` 调用传入 `profileSyncContext`

## Task 4: Verification

**Files:**

- Verify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 检查 makePlan 调用点**

Run:

```sh
rg -n "DeviceGroupDeferredSyncPlanner.makePlan" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- Classic 两个 light + group 调用都传 `profileSyncContext`
- Professional 两个 light + group 调用都传 `profileSyncContext`
- planner 定义保留默认 `profileSyncContext: nil`

- [ ] **Step 2: 检查 diff**

Run:

```sh
git diff -- SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- 只包含本计划范围内改动。
- 没有本地化、资源、target 配置改动。

- [ ] **Step 3: 检查空白错误**

Run:

```sh
git diff --check
```

Expected:

- 无输出。

- [ ] **Step 4: iPhoneOS 构建验证**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- `** BUILD SUCCEEDED **`

## Manual QA

实现后手工验证：

1. 创建非 Manual Control profile 的新 group。
2. 从 Members 空页点击 Add device。
3. 同时 Add Selected 2 个带 PIR 的 light，返回 Members / Main - Lights 后不应残留单个设备需要同步。
4. 同时 Add Selected 3 个带 PIR 的 light，返回后不应残留单个设备需要同步。
5. 若故意制造 Mesh deferred sync 失败，设备仍应展示需要同步，点击 Main - Lights 同步按钮后应补齐。
