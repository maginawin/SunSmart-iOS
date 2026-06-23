# EFC LINK Associated Group Sync Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 EFC LINK 后没有进入 Sync 页面的问题，并确保 LINK 后 Sync 只下发 associated Group 内真实设备的 subscription 配置。

**Architecture:** `DeviceAddViewController` 已经负责关闭 Add Device 后再回调外层，因此 `LinkedEmerFireEditVC` 不再二次 dismiss。LINK 后 Sync 通过 `EmergencyFireControllerSyncPlanner.makeAssociatedGroupItems()` 提供限定 items，避免 `items: nil` 触发完整 EFC controller sync。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, `EmergencyFireControllerSyncPlanner`, `SyncDevicesViewController`, shell contract script, Xcode iPhoneOS build.

---

## File Structure

- Modify: `scripts/check_efc_controller_flows.sh`
  - 增加 contract，要求 LINK 后直接调用 sync gate。
  - 禁止二次 dismiss completion 包裹 sync gate。
  - 要求 LINK 后 Sync 使用 `makeAssociatedGroupItems()`。
  - 禁止 `openSyncAfterLinkedDeviceIfNeeded()` 使用 `items: nil`。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - 移除 LINK callback 内二次 dismiss。
  - `openSyncAfterLinkedDeviceIfNeeded()` 只构建 associated group sync items。

---

### Task 1: 更新 LINK 后 Sync Contract

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: 写失败 contract**

在现有 EFC LINK 断言附近增加：

```bash
assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "self.dismiss(animated: true) { [weak self] in" \
  "EFC LINK callback must not dismiss again because DeviceAddViewController already closes the Add Device flow before invoking the callback."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "let items = try planner.makeAssociatedGroupItems()" \
  "EFC LINK sync must build associated group subscription items explicitly."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "items: items" \
  "EFC LINK sync must pass limited associated group items to SyncDevicesViewController."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "SyncDevicesViewController(type: .emergencyFire(data: device, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))" \
  "EFC LINK sync must not use nil items because that re-runs full controller sync."
```

- [ ] **Step 2: 运行 contract，确认当前实现失败**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL，失败应指向二次 dismiss 仍存在，或 `makeAssociatedGroupItems()` / `items: items` 缺失。

- [ ] **Step 3: 提交 contract**

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: tighten EFC link sync routing contract"
```

---

### Task 2: 修正 LINK Callback 和 Limited Sync Items

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`

- [ ] **Step 1: 移除 callback 内二次 dismiss**

把 LINK 成功 callback 尾部改成直接调用 sync gate：

```swift
controller.deviceAddCallback = { [weak self] _ in
    DispatchQueue.main.async {
        guard let self else { return }
        _ = self.viewModel.refreshLinkedDeviceFromStore()
        self.linkView.configure(isLinked: true)
        self.tableView.reloadData()
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
        self.openSyncAfterLinkedDeviceIfNeeded()
    }
}
```

Reason: `DeviceAddViewController.finishBindingFlowIfNeeded()` 已经在关闭 Add Device 后才调用外层 callback。

- [ ] **Step 2: 让 sync gate 只构建 associated group items**

将 `openSyncAfterLinkedDeviceIfNeeded()` 改为：

```swift
@discardableResult
private func openSyncAfterLinkedDeviceIfNeeded() -> Bool {
    guard let device = viewModel.currentDevice(),
          device.bindNode != nil,
          device.configuration.hasSyncIntent else {
        return false
    }
    let planner = EmergencyFireControllerSyncPlanner(
        data: device,
        meshUUID: device.meshUUID,
        subnetworkId: device.meshNetworkId
    )
    let items: [EmergencyFireControllerSyncItem]
    do {
        items = try planner.makeAssociatedGroupItems()
    } catch {
        XWHUDManager.showErrorTipHUD(error.localizedDescription)
        return false
    }
    guard !items.isEmpty else {
        return false
    }
    let controller = SyncDevicesViewController(type: .emergencyFire(data: device, items: items, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))
    controller.syncSuccessCallback = { [weak self] _ in
        guard let self else { return }
        _ = self.viewModel.refreshLinkedDeviceFromStore()
        self.tableView.reloadData()
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
    }
    navigationController?.pushViewController(controller, animated: true)
    return true
}
```

Notes:

- `makeAssociatedGroupItems()` 内部依赖 `data.publishGroup`；`DeviceEmerFireStore.bind(_:to:in:)` 已在 LINK 时确保 publish group。
- `guard !items.isEmpty` 覆盖空组和没有可下发 Model subscription 的场景。
- 使用 `refreshLinkedDeviceFromStore()`，同步成功后一起刷新 `isSynced`、绑定状态和 publish group。

- [ ] **Step 3: 运行 contract，确认通过**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: PASS，输出 `EFC controller flow contracts passed.`

- [ ] **Step 4: 提交 LINK 修正**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
git commit -m "fix: open limited EFC group sync after link"
```

---

### Task 3: 验证

**Files:**
- No code changes expected.

- [ ] **Step 1: 空白和状态检查**

Run:

```bash
git status --short
git diff --check
```

Expected:

- `git status --short` 没有未预期文件。
- `git diff --check` 无输出并返回成功。

- [ ] **Step 2: EFC contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: `EFC controller flow contracts passed.`

- [ ] **Step 3: iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手工验证**

```text
1. 虚拟 EFC + 空组 + LINK 真实 EFC
   Expected:
   - Add Device 完成并关闭。
   - 不进入 Sync 页面。
   - 不显示 need-sync。

2. 虚拟 EFC + 有真实设备 Group + LINK 真实 EFC
   Expected:
   - Add Device 完成并关闭。
   - Edit 页面随后进入 EFC Sync。
   - Sync 页面只包含 Group 内真实设备的 EFC subscription 同步项。
   - Sync 成功后功能生效，不再显示 need-sync。
```

---

## Self-Review

- Spec coverage:
  - 二次 dismiss 根因：Task 2 Step 1。
  - LINK 后只同步 associated group subscription：Task 2 Step 2。
  - 空组不进 Sync：Task 2 Step 2 的 `guard !items.isEmpty`。
  - 不改 SDK / 不恢复 fast-add group append：全计划无 SDK 和 Add Device controller 修改。
- Placeholder scan:
  - 未使用占位描述或未落地步骤。
- Type consistency:
  - `EmergencyFireControllerSyncPlanner`、`makeAssociatedGroupItems()`、`EmergencyFireControllerSyncItem`、`SyncDevicesViewController` 均为当前代码中已有符号。

