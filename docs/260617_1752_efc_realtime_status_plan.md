# EFC Realtime Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EFC 绑定节点在线/离线状态变化后，Others 列表和 EFC 设备详情页实时刷新 UI。

**Architecture:** 保持 `DeviceEmerFireData.displayStatus` 作为状态真值，不新增缓存字段。页面层补齐 `deviceStateUpdateNotificationName` 监听，按绑定节点地址局部刷新对应 EFC item 或详情页状态。

**Tech Stack:** Swift、UIKit、NotificationCenter、NordicSigMeshSDK `Node`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - 增加 `deviceStateUpdateNotificationName` 监听。
  - 增加按 `Node.primaryUnicastAddress` 匹配 EFC item 的局部刷新方法。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - 增加 `deviceStateUpdateNotificationName` 监听。
  - 收到当前绑定节点后调用现有 `renderNodeAvailabilityChange(_:)`。

---

### Task 1: Others 列表监听 EFC 绑定节点状态变化

**Files:**
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`

- [ ] **Step 1: 增加通知监听**

在 `addNotificationObserver()` 的现有三个 observer 后追加：

```swift
NotificationCenter.default.addObserver(forName: .init(deviceStateUpdateNotificationName), object: nil, queue: .main) { [weak self] notification in
    guard let self,
          self.view.window != nil,
          let node = notification.object as? Node else {
        return
    }
    self.reloadEmergencyFireItem(for: node)
}
```

- [ ] **Step 2: 增加局部刷新方法**

在 `reloadShowItems()` 后增加：

```swift
private func reloadEmergencyFireItem(for node: Node) {
    guard let index = showItems.firstIndex(where: { item in
        guard case .emergencyFireController(let device) = item else {
            return false
        }
        return device.bindNodeAddress == node.primaryUnicastAddress
    }) else {
        return
    }

    let indexPath = IndexPath(item: index, section: 0)
    if let cell = collectionView.cellForItem(at: indexPath) as? EmerFireAlarmDeviceCell,
       case .emergencyFireController(let device) = showItems[index] {
        cell.configCell(device: device, editing: isEdit)
    } else {
        collectionView.reloadItems(at: [indexPath])
    }
}
```

- [ ] **Step 3: 局部检查**

Run:

```bash
rg -n "reloadEmergencyFireItem|deviceStateUpdateNotificationName" SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
```

Expected:

- `DeviceOthersViewController.swift` 中出现 `deviceStateUpdateNotificationName` 监听。
- `reloadEmergencyFireItem(for:)` 使用 `bindNodeAddress == node.primaryUnicastAddress` 匹配。

---

### Task 2: EFC 详情页监听通用设备状态通知

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`

- [ ] **Step 1: 增加通知监听**

在 `viewDidLoad()` 中现有 `.linkedEmerFireConfigDidChange` observer 后追加：

```swift
NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceStateDidUpdate(_:)), name: .init(deviceStateUpdateNotificationName), object: nil)
```

- [ ] **Step 2: 增加通知处理方法**

在 `handleConfigDidChange(_:)` 同一类 extension 可访问范围内，或 `EmerFireAlarmMonitorVC` 主类中增加：

```swift
@objc private func handleDeviceStateDidUpdate(_ notification: Notification) {
    guard let node = notification.object as? Node else {
        return
    }
    renderNodeAvailabilityChange(node)
}
```

如果方法放在 `EmerFireAlarmMonitorRendering.swift` extension 中，因为 selector 需要 Objective-C 可见且 extension 当前不是 `private`，方法应声明为：

```swift
@objc func handleDeviceStateDidUpdate(_ notification: Notification) {
    guard let node = notification.object as? Node else {
        return
    }
    renderNodeAvailabilityChange(node)
}
```

- [ ] **Step 3: 局部检查**

Run:

```bash
rg -n "handleDeviceStateDidUpdate|deviceStateUpdateNotificationName|renderNodeAvailabilityChange" SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift
```

Expected:

- `EmerFireAlarmMonitorVC.swift` 中出现 `deviceStateUpdateNotificationName` observer。
- handler 最终调用 `renderNodeAvailabilityChange(node)`。

---

### Task 3: Verification

**Files:**
- Verify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`

- [ ] **Step 1: 检查本次 diff 范围**

Run:

```bash
git diff -- SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift docs/260617_1752_efc_realtime_status_plan.md
```

Expected:

- 只包含 EFC 状态刷新监听和本计划文档。
- 不包含资源、本地化、target 配置或无关格式化。

- [ ] **Step 2: whitespace 检查**

Run:

```bash
git diff --check -- SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift docs/260617_1752_efc_realtime_status_plan.md
```

Expected:

- No output.

- [ ] **Step 3: iPhoneOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- `** BUILD SUCCEEDED **`
