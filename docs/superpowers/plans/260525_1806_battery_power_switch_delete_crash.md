# Battery Power Switch Delete Crash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复删除真实 Battery Power Switch 时的 collection view 崩溃，并明确真实/虚拟 BPS 的删除确认边界。

**Architecture:** 保持现有全局 `MeshNetworkManager.instance.switchs` 数据源不重构。列表删除成功后统一完整刷新，不再对全局数组做局部 `deleteItems` 动画；真实 BPS 仍走确认弹窗，未关联虚拟 BPS 直接删除。

**Tech Stack:** Swift、UIKit、UICollectionView、NotificationCenter、NordicSigMeshSDK、现有 `SRAlertView` / `XWHUDManager`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
  - 负责 Switch 列表删除入口。
  - 修复 `deleteCache` 的 collection view 刷新方式。
  - 列表入口对未关联虚拟 BPS 直接删除。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 负责 BPS 编辑页删除入口。
  - 未关联虚拟 BPS 从编辑页删除时不弹确认，真实 BPS 保留确认。
- Verify only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 已经有未关联虚拟 BPS 直接删除、真实 BPS 确认删除的行为，实施时只做确认，不做无关改动。

---

### Task 1: 修复列表删除刷新和虚拟 BPS 列表直删

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

- [ ] **Step 1: 记录当前崩溃触发点**

Run:

```bash
rg -n "deleteCache|deleteItems|switchsRefreshNotificationName|eightKeySwitchData" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- `deleteCache` 中存在 `collectionView.deleteItems(at:)`。
- 当前控制器监听 `switchsRefreshNotificationName` 并在通知中调用 `updateUI()`。

- [ ] **Step 2: 添加未关联虚拟 BPS 判断 helper**

在 `eightKeySwitchData(for:)` 后添加：

```swift
    private func isUnlinkedVirtualBatteryPowerSwitch(_ switchData: DeviceSwitchData) -> Bool {
        guard let eightKeySwitch = eightKeySwitchData(for: switchData) else {
            return false
        }
        return eightKeySwitch.proxyNode?.isBatteryPowerSwitch != true
    }
```

用途：

- 列表 cell 删除入口可以识别未关联虚拟 BPS。
- 真实 BPS 的 `proxyNode?.isBatteryPowerSwitch == true`，仍走确认和同步删除。

- [ ] **Step 3: 将 `deleteCache` 改成完整刷新**

替换整个 `deleteCache(switchData:)`：

```swift
    private func deleteCache(switchData: DeviceSwitchData) {
        MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)

        if MeshNetworkManager.instance.switchs.isEmpty {
            isEdit = false
        }
        updateUI()
    }
```

关键点：

- 删除后不再读取旧 `index`。
- 不再调用 `collectionView.deleteItems(at:)`。
- 即使 `MeshNetworkManager.deleteSwitch` 内部同步发出刷新通知，也只会导致多次完整刷新，不会触发 UIKit 局部删除断言。

- [ ] **Step 4: 列表入口对未关联虚拟 BPS 直接删除**

在 `cellForItemAt` 的 `deleteAction` closure 中，`SRAlertView` 前添加：

```swift
            if self.isUnlinkedVirtualBatteryPowerSwitch(switche) {
                self.deleteCache(switchData: switche)
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                return
            }
```

保留后面的现有确认弹窗，用于真实 BPS 和其他需要确认的 switch 删除。

- [ ] **Step 5: 验证列表删除代码不再局部删除**

Run:

```bash
rg -n "deleteCache|deleteItems|isUnlinkedVirtualBatteryPowerSwitch|showSuccessTipHUD" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- `deleteCache` 存在。
- `isUnlinkedVirtualBatteryPowerSwitch` 存在。
- `collectionView.deleteItems(at:)` 在该文件中不再出现。

- [ ] **Step 6: Commit Task 1**

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
git commit -m "fix: refresh switch list after delete"
```

---

### Task 2: 修复编辑页未关联虚拟 BPS 删除确认边界

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 确认详情页现有删除边界**

Run:

```bash
sed -n '448,476p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `deleteCurrentSwitch()` 对 `viewModel.isUnlinkedVirtualBatteryPowerSwitch` 直接调用 `deleteUnlinkedVirtualSwitch()`。
- 真实 BPS 走 `SRAlertView` 确认弹窗。

- [ ] **Step 2: 编辑页未关联虚拟 BPS 直接删除**

在 `PJPreAddEightKeySwitchesVC.deleteAction()` 中，`guard let switchData = viewModel.sourceSwitchData else { return }` 后添加：

```swift
        guard switchData.proxyNode?.isBatteryPowerSwitch == true else {
            dismiss(animated: true) { [weak self] in
                self?.deleteSwitchAction?(switchData)
            }
            return
        }
```

保留后面的 `SRAlertView`，用于真实 BPS 删除确认。

- [ ] **Step 3: 验证编辑页真实/虚拟分支**

Run:

```bash
sed -n '312,332p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- `guard switchData.proxyNode?.isBatteryPowerSwitch == true else` 存在。
- 该 guard 的 else 分支直接 `dismiss` 并触发 `deleteSwitchAction`。
- `SRAlertView` 仍在 guard 后面。

- [ ] **Step 4: Commit Task 2**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: skip alert for unlinked virtual switch"
```

---

### Task 3: 验证删除链路和构建

**Files:**
- Verify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 验证真实 BPS reset / node 删除 / 地址级云同步仍存在**

Run:

```bash
rg -n "ConfigNodeReset\\(\\)|forceRemove\\(node:|SpaceChangeDataType\\.network\\(type: \\.address\\)|deleteSwitch\\(switchData:" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- `ConfigNodeReset()` 仍在 `deleteSwitch(switchData:)` 的真实 BPS 删除链路中。
- `forceRemove(node:)` 仍存在。
- `SpaceChangeDataType.network(type: .address)` 仍存在。

- [ ] **Step 2: 验证列表不再使用局部删除动画**

Run:

```bash
rg -n "deleteItems\\(at:" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- 无输出。

- [ ] **Step 3: 验证 diff 无空白错误**

Run:

```bash
git diff --check
```

Expected:

- 无输出。

- [ ] **Step 4: 运行 iOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 输出包含 `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit verification note if files changed**

如果验证过程中没有改文件，不需要 commit。若只修改了实现文件，前两项 task 已经分别提交。

Run:

```bash
git status --short
```

Expected:

- 无未提交实现文件。
