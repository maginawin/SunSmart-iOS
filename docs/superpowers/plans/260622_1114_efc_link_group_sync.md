# EFC LINK Group Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复虚拟 EFC LINK 真实 EFC 后，真实 Group 订阅配置在 Add Device append 阶段发送目标错位、页面等待很久且配置不生效的问题。

**Architecture:** Add Device append 阶段只负责刚入网 EFC controller 自身默认配置。跨节点的 associated Group 订阅任务不再进入 fast-add append，而是在 LINK 成功并关闭 Add Device 页面后，通过现有 EFC Sync 流程按真实目标地址发送。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, `SyncDevicesViewController`, `EmergencyFireControllerSyncPlanner`, shell contract script, Xcode iPhoneOS build.

---

## File Structure

- Modify: `scripts/check_efc_controller_flows.sh`
  - 更新 contract：禁止 EFC LINK 把 associated Group 订阅任务追加到 Add Device append；要求 LINK callback 调用 `openSyncAfterLinkedDeviceIfNeeded()`。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Classic add flow 只保留 EFC controller 默认配置 append，移除 linked group subscription append 状态和失败跟踪。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Professional add flow 做同样收口，避免两个 add mode 行为漂移。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - LINK 成功后先 dismiss Add Device，再按当前 EFC 配置意图打开 EFC Sync；Sync 成功后刷新 Edit 页同步状态。

---

### Task 1: 更新 EFC LINK Contract

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: 改 contract，先让它在当前代码上失败**

把当前要求 append Group 订阅任务的断言替换为负向断言，并要求 LINK callback 实际调用 sync gate。

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "self.openSyncAfterLinkedDeviceIfNeeded()" \
  "Bind to a new EFC must enter the EFC sync flow after Add Device is dismissed when there is syncable group configuration."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Classic EFC LINK must not append associated group subscription messages during Add Device."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Professional EFC LINK must not append associated group subscription messages during Add Device."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "linkedEmergencyFireGroupSubscriptionMessageHandles" \
  "Classic Add Device must not track linked EFC group subscription handles in fast-add append state."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "linkedEmergencyFireGroupSubscriptionMessageHandles" \
  "Professional Add Device must not track linked EFC group subscription handles in fast-add append state."
```

保留对 `finishLinkedEmergencyFireControllerConfiguration(for: node)` 的断言先不动，直到 Task 2 决定是否重命名。

- [ ] **Step 2: 运行 contract，确认失败点是预期的旧行为**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL，失败内容应指向 `self.openSyncAfterLinkedDeviceIfNeeded()` 缺失，或 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(...)` / `linkedEmergencyFireGroupSubscriptionMessageHandles` 仍存在。

- [ ] **Step 3: 提交 contract**

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: update EFC link group sync contract"
```

---

### Task 2: 收口 Classic Add Device 的 EFC append 状态

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: 移除 linked group subscription fast-add 状态**

删除属性：

```swift
private var linkedEmergencyFireGroupSubscriptionMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedLinkedEmergencyFireGroupSubscriptionNodeAddresses: Set<Address> = []
```

在 `resetFastAddGroupSyncBatch()` 中删除：

```swift
linkedEmergencyFireGroupSubscriptionMessageHandles.removeAll()
failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.removeAll()
```

- [ ] **Step 2: 删除 append helper 和 lookup helper**

删除整个 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller:appendMessages:)`。

删除：

```swift
private func linkedEmergencyFireGroupSubscriptionNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
    linkedEmergencyFireGroupSubscriptionMessageHandles.first { _, handles in
        handles.contains { $0 === messageHandle }
    }?.key
}
```

- [ ] **Step 3: 让 finish 只处理 controller 默认配置**

将 `finishLinkedEmergencyFireControllerConfiguration(for:)` 改为只看 `emergencyFireDefaultConfigurationMessageHandles`。可保留现有函数名以减少调用点改动。

```swift
private func finishLinkedEmergencyFireControllerConfiguration(for node: Node) {
    let hadDefaultConfiguration = emergencyFireDefaultConfigurationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    guard hadDefaultConfiguration,
          let controller = DeviceEmerFireStore.shared.devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) else {
        return
    }
    let defaultConfigurationFailed = failedEmergencyFireDefaultConfigurationNodeAddresses.contains(node.primaryUnicastAddress)
    failedEmergencyFireDefaultConfigurationNodeAddresses.remove(node.primaryUnicastAddress)

    controller.isSynced = !defaultConfigurationFailed
    DeviceEmerFireStore.shared.save(controller)
}
```

注意：这里允许有 associated Group 的 EFC 暂时被 default config 标记为 synced，因为 LINK 成功后会立即按 `configuration.hasSyncIntent` 打开 EFC Sync；`hasSyncIntent` 不依赖 `isSynced`。

- [ ] **Step 4: 删除 append 阶段的 Group 订阅调用**

在 EFC add append 分支中只保留默认配置：

```swift
appendEmergencyFireControllerDefaultConfigurationMessages(controller: controller, appendMessages: &appendMessages)
```

删除紧随其后的：

```swift
appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)
```

- [ ] **Step 5: 删除 append failure callback 中的 linked subscription 失败记录**

删除：

```swift
if let nodeAddress = self.linkedEmergencyFireGroupSubscriptionNodeAddress(containing: messageHandle) {
    self.failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.insert(nodeAddress)
}
```

- [ ] **Step 6: 运行 contract，确认 Classic 相关旧断言已解除但 Professional 仍失败**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL，剩余失败应来自 Professional controller 或 LINK callback 尚未调用 sync gate。

- [ ] **Step 7: 提交 Classic 收口**

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
git commit -m "fix: stop classic EFC link group append"
```

---

### Task 3: 收口 Professional Add Device 的 EFC append 状态

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 对 Professional 执行与 Classic 相同的状态移除**

删除属性：

```swift
private var linkedEmergencyFireGroupSubscriptionMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedLinkedEmergencyFireGroupSubscriptionNodeAddresses: Set<Address> = []
```

在 `resetFastAddGroupSyncBatch()` 中删除：

```swift
linkedEmergencyFireGroupSubscriptionMessageHandles.removeAll()
failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.removeAll()
```

- [ ] **Step 2: 删除 Professional 的 append helper 和 lookup helper**

删除整个 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller:appendMessages:)`。

删除：

```swift
private func linkedEmergencyFireGroupSubscriptionNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
    linkedEmergencyFireGroupSubscriptionMessageHandles.first { _, handles in
        handles.contains { $0 === messageHandle }
    }?.key
}
```

- [ ] **Step 3: 让 Professional finish 只处理 controller 默认配置**

使用与 Classic 相同的实现：

```swift
private func finishLinkedEmergencyFireControllerConfiguration(for node: Node) {
    let hadDefaultConfiguration = emergencyFireDefaultConfigurationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    guard hadDefaultConfiguration,
          let controller = DeviceEmerFireStore.shared.devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) else {
        return
    }
    let defaultConfigurationFailed = failedEmergencyFireDefaultConfigurationNodeAddresses.contains(node.primaryUnicastAddress)
    failedEmergencyFireDefaultConfigurationNodeAddresses.remove(node.primaryUnicastAddress)

    controller.isSynced = !defaultConfigurationFailed
    DeviceEmerFireStore.shared.save(controller)
}
```

- [ ] **Step 4: 删除 Professional append 阶段的 Group 订阅调用**

保留：

```swift
appendEmergencyFireControllerDefaultConfigurationMessages(controller: controller, appendMessages: &appendMessages)
```

删除：

```swift
appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)
```

- [ ] **Step 5: 删除 Professional append failure callback 中的 linked subscription 失败记录**

删除：

```swift
if let nodeAddress = self.linkedEmergencyFireGroupSubscriptionNodeAddress(containing: messageHandle) {
    self.failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.insert(nodeAddress)
}
```

- [ ] **Step 6: 运行 contract，确认只剩 LINK callback 相关失败**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL，失败应只剩 `LinkedEmerFireEditVC.swift` 中缺少 `self.openSyncAfterLinkedDeviceIfNeeded()`。

- [ ] **Step 7: 提交 Professional 收口**

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: stop professional EFC link group append"
```

---

### Task 4: LINK 成功后进入正确 EFC Sync 流程

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`

- [ ] **Step 1: 在 LINK 成功 callback 中 dismiss 后打开 sync gate**

把 `deviceAddCallback` 的尾部从直接 dismiss 改为带 completion 的 dismiss。关键形状：

```swift
controller.deviceAddCallback = { [weak self] _ in
    DispatchQueue.main.async {
        guard let self else { return }
        _ = self.viewModel.refreshLinkedDeviceFromStore()
        self.linkView.configure(isLinked: true)
        self.tableView.reloadData()
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
        self.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.openSyncAfterLinkedDeviceIfNeeded()
        }
    }
}
```

这样 Add Device 页面先关闭，再由 Edit 页面自己的 navigation controller push Sync 页面。

- [ ] **Step 2: 给 LINK 后 Sync 成功补最小 UI 刷新**

更新 `openSyncAfterLinkedDeviceIfNeeded()`，仍以 `device.configuration.hasSyncIntent` 作为 gate，不看 `isSynced`。

```swift
@discardableResult
private func openSyncAfterLinkedDeviceIfNeeded() -> Bool {
    guard let device = viewModel.currentDevice(),
          device.bindNode != nil,
          device.configuration.hasSyncIntent else {
        return false
    }
    let controller = SyncDevicesViewController(type: .emergencyFire(data: device, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))
    controller.syncSuccessCallback = { [weak self] _ in
        guard let self else { return }
        _ = self.viewModel.refreshSyncStatusFromStore()
        self.tableView.reloadData()
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
    }
    navigationController?.pushViewController(controller, animated: true)
    return true
}
```

不要设置 `backActionCallback`。`SyncDevicesViewController.backAction()` 在没有 callback 时会自动 `closeAfterSync()`，这符合 LINK 后同步页现有关闭行为。

- [ ] **Step 3: 运行 contract，确认通过**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: PASS，输出应表示 EFC controller flow checks passed。

- [ ] **Step 4: 提交 LINK 后 sync 路由**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
git commit -m "fix: sync EFC link groups after add"
```

---

### Task 5: 编译与最终验证

**Files:**
- No code changes expected.

- [ ] **Step 1: 检查工作区和空白错误**

Run:

```bash
git status --short
git diff --check
```

Expected:

- `git status --short` 没有未预期文件。
- `git diff --check` 无输出并返回成功。

- [ ] **Step 2: 跑 EFC contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: PASS。

- [ ] **Step 3: 跑 iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手工验证矩阵**

验证以下流程：

```text
1. 虚拟 EFC + 空组 + LINK 真实 EFC
   Expected:
   - Add Device 不再因 Group 订阅 append 等待 45 秒。
   - EFC controller 自身配置成功后不显示 need-sync。
   - 不打开 Sync 页面，因为 configuration.hasSyncIntent 为 false。

2. 虚拟 EFC + 有真实设备 Group + LINK 真实 EFC
   Expected:
   - Add Device 完成后关闭。
   - Edit 页面随后进入 EFC Sync。
   - Sync 通过真实目标地址下发 Group 设备订阅配置。
   - Sync 成功后不再显示 need-sync。

3. 虚拟 EFC + 有真实设备 Group + Group 内设备离线
   Expected:
   - Add Device 不再长时间卡在 append。
   - 后续 EFC Sync 失败并保留 need-sync。
   - 用户后续 Retry / SAVE 可继续下发。
```

- [ ] **Step 5: 最终提交或确认无额外变更**

如果 Task 5 只产生验证结果，不需要提交。若为了 contract 或修复又有补充改动，提交：

```bash
git add <changed-files>
git commit -m "fix: finalize EFC link group sync"
```

---

## Self-Review

- Spec coverage:
  - Add Device append 只处理 EFC 自身配置：Task 2、Task 3。
  - Group 订阅走 LINK 后 Sync：Task 4。
  - 空组不打开 Sync：Task 4 使用 `configuration.hasSyncIntent` gate。
  - 有真实设备 Group 配置立即下发：Task 4 复用 EFC Sync。
  - 不改 SDK fast-add 语义：全计划无 SDK 文件修改。
- Placeholder scan:
  - 未使用占位描述或未落地步骤。
- Type consistency:
  - `openSyncAfterLinkedDeviceIfNeeded()`、`SyncDevicesViewController`、`configuration.hasSyncIntent`、`finishLinkedEmergencyFireControllerConfiguration(for:)` 均为当前代码中已存在的符号。
