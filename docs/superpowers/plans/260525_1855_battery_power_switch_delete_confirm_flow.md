# Battery Power Switch Delete Confirm Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复真实 Battery Power Switch 删除时 `Confirm` 后再次弹窗的问题，并让需要同步和不需要同步的删除路径都符合已确认设计。

**Architecture:** 将“删除入口确认”和“已确认删除执行”分离。BPS 详情页/编辑页把当前页面作为 source 传回 switches 列表控制器；需要同步时从 source 的 navigation stack push `SyncDevicesViewController`，成功后先返回 BPS 页面，再本地删除、提示 Done、关闭 BPS 页面。

**Tech Stack:** Swift、UIKit、UICollectionView、NotificationCenter、NordicSigMeshSDK、现有 `SRAlertView`、`XWHUDManager`、`SyncDevicesViewController`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
  - 拆分已确认删除执行流。
  - 支持从 BPS source 页面 push 同步页。
  - 同步失败、返回或 STOP 时停留在同步页，不删除本地数据。
  - 同步成功或无需同步时统一本地删除。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 调整 `deleteSwitchAction` 签名。
  - 真实 BPS 确认后不 dismiss，直接把当前详情页作为 source 传给执行流。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 调整 `deleteSwitchAction` 签名。
  - 真实 BPS 确认后不 dismiss，直接把当前编辑页作为 source 传给执行流。
- Verify only: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 确认真正本地删除仍复用 `MeshNetworkManager.instance.deleteSwitch(switchData:)`。

---

### Task 1: 调整 BPS 删除回调签名，保留当前页面

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

- [ ] **Step 1: 确认当前回调签名和调用点**

Run:

```bash
rg -n "deleteSwitchAction" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- `PJEightKeySwitchMonitorVC` 中存在 `var deleteSwitchAction: ((DeviceSwitchData) -> Void)?`。
- `PJPreAddEightKeySwitchesVC` 中存在 `var deleteSwitchAction: ((DeviceSwitchData) -> Void)?`。
- 详情页、编辑页和 switches 列表中都有对应调用点。

- [ ] **Step 2: 修改 `PJEightKeySwitchMonitorVC` 的回调类型**

Replace:

```swift
var deleteSwitchAction: ((DeviceSwitchData) -> Void)?
```

With:

```swift
var deleteSwitchAction: ((DeviceSwitchData, UIViewController) -> Void)?
```

- [ ] **Step 3: 修改 `PJEightKeySwitchMonitorVC.deleteCurrentSwitch()` 的 Confirm 行为**

Replace the `SRAlertAction` handler in `deleteCurrentSwitch()` with:

```swift
SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
    guard let self else { return }
    self.deleteSwitchAction?(self.viewModel.switchData, self)
})
```

Expected behavior:

- 真实 BPS 详情页仍弹一次确认。
- 点击 `Confirm` 后不 dismiss 当前 BPS 页面。
- 删除执行流可以在当前 BPS navigation stack 中 push 同步页。

- [ ] **Step 4: 修改 `PJPreAddEightKeySwitchesVC` 的回调类型**

Replace:

```swift
var deleteSwitchAction: ((DeviceSwitchData) -> Void)?
```

With:

```swift
var deleteSwitchAction: ((DeviceSwitchData, UIViewController) -> Void)?
```

- [ ] **Step 5: 修改 `PJPreAddEightKeySwitchesVC.deleteAction()` 的虚拟 BPS 直删分支**

Replace:

```swift
dismiss(animated: true) { [weak self] in
    self?.deleteSwitchAction?(switchData)
}
```

With:

```swift
self.deleteSwitchAction?(switchData, self)
```

Expected behavior:

- 未关联虚拟 BPS 仍不弹确认。
- 直接进入已确认删除执行流，由执行流负责 Done 提示和关闭 BPS 页面。

- [ ] **Step 6: 修改 `PJPreAddEightKeySwitchesVC.deleteAction()` 的真实 BPS Confirm 行为**

Replace the `SRAlertAction` handler in the real BPS delete alert with:

```swift
SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
    guard let self else { return }
    self.deleteSwitchAction?(switchData, self)
})
```

Expected behavior:

- 真实 BPS 编辑页仍弹一次确认。
- 点击 `Confirm` 后不 dismiss 当前编辑页。
- 删除执行流可以从当前编辑页 push 同步页。

- [ ] **Step 7: 更新 `PJEightKeySwitchMonitorVC.pushEditor()` 赋值**

No code change is needed if both properties now share this exact type:

```swift
var deleteSwitchAction: ((DeviceSwitchData, UIViewController) -> Void)?
```

Run:

```bash
sed -n '432,442p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `vc.deleteSwitchAction = deleteSwitchAction` 仍可编译。

- [ ] **Step 8: 更新 switches 列表传入 BPS 编辑页的删除回调**

In `DeviceSwitchesViewController.collectionLongPressAction`, replace:

```swift
vc.deleteSwitchAction = { [weak self] switchData in
    guard let self else { return }
    self.deleteConfirmedSwitch(switchData)
}
```

With:

```swift
vc.deleteSwitchAction = { [weak self] switchData, source in
    guard let self else { return }
    self.deleteConfirmedSwitch(switchData, source: source)
}
```

- [ ] **Step 9: 更新 switches 列表传入 BPS 详情页的删除回调**

In `DeviceSwitchesViewController.collectionView(_:didSelectItemAt:)`, replace:

```swift
vc.deleteSwitchAction = { [weak self] switchData in
    guard let self else { return }
    self.deleteConfirmedSwitch(switchData)
}
```

With:

```swift
vc.deleteSwitchAction = { [weak self] switchData, source in
    guard let self else { return }
    self.deleteConfirmedSwitch(switchData, source: source)
}
```

- [ ] **Step 10: 验证签名替换完整**

Run:

```bash
rg -n "deleteSwitchAction\\?\\(|deleteSwitchAction =" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- 详情页调用形态为 `deleteSwitchAction?(..., self)`。
- 编辑页调用形态为 `deleteSwitchAction?(..., self)`。
- switches 列表闭包参数为 `switchData, source`。

- [ ] **Step 11: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
git commit -m "fix: pass battery switch delete source"
```

Expected:

- Commit succeeds.
- Do not stage unrelated existing battery refresh files or untracked docs.

---

### Task 2: 拆分已确认删除执行流

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

- [ ] **Step 1: Replace `deleteSwitchData(_:)` with source-aware sync flow**

Replace the current `deleteSwitchData(_ switchData: DeviceSwitchData)` function with:

```swift
private func deleteSwitchData(_ switchData: DeviceSwitchData, source: UIViewController?) {

    guard MeshLibManager.manager.isMeshNetworkConnected else {
        XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
        return
    }

    let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData, deleteSwitch: true))
    vc.syncSuccessCallback = { [weak self, weak source] _ in
        guard let self else { return }
        if let navigationController = source?.navigationController {
            navigationController.popViewController(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak source] in
                self?.completeConfirmedSwitchDelete(switchData, source: source)
            }
        } else {
            self.dismiss(animated: true) { [weak self] in
                self?.completeConfirmedSwitchDelete(switchData, source: nil)
            }
        }
    }
    vc.backActionCallback = { _ in }

    if let source, let navigationController = source.navigationController {
        navigationController.pushViewController(vc, animated: true)
    } else {
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
}
```

Expected behavior:

- BPS page source exists: sync page is pushed on the BPS navigation stack.
- Sync success from BPS page: pop back to BPS page, then delete and close.
- Sync failure, STOP, or back: `backActionCallback` intentionally does nothing, so the sync page stays in its current failed/stopped state.
- List source is nil: keep the existing modal sync presentation pattern.

- [ ] **Step 2: Add `completeConfirmedSwitchDelete` after `deleteCache`**

Insert this function immediately after `deleteCache(switchData:)`:

```swift
private func completeConfirmedSwitchDelete(_ switchData: DeviceSwitchData, source: UIViewController?) {
    deleteCache(switchData: switchData)

    guard let source else {
        return
    }

    XWHUDManager.showSuccessTipHUD("done!".localizedString)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak source] in
        self?.closeDeletedSwitchSource(source)
    }
}
```

- [ ] **Step 3: Add `closeDeletedSwitchSource` after `completeConfirmedSwitchDelete`**

Insert this function immediately after `completeConfirmedSwitchDelete`:

```swift
private func closeDeletedSwitchSource(_ source: UIViewController?) {
    guard let source else {
        return
    }

    if let navigationController = source.navigationController,
       navigationController.presentingViewController != nil {
        navigationController.dismiss(animated: true)
    } else {
        source.dismiss(animated: true)
    }
}
```

Expected behavior:

- BPS modal navigation closes after Done.
- switches page remains visible and refreshed.

- [ ] **Step 4: Replace `deleteConfirmedSwitch(_:)` with source-aware execution**

Replace the current `deleteConfirmedSwitch(_ switchData: DeviceSwitchData)` function with:

```swift
private func deleteConfirmedSwitch(_ switchData: DeviceSwitchData, source: UIViewController? = nil) {
    guard !switchData.getNeedSyncDatas(deleteSwitch: true).isEmpty() else {
        completeConfirmedSwitchDelete(switchData, source: source)
        return
    }
    deleteSwitchData(switchData, source: source)
}
```

Expected behavior:

- `getNeedSyncDatas(deleteSwitch: true).isEmpty()` remains the only sync decision.
- No-sync path deletes immediately.
- Sync path enters `SyncDevicesViewController`.
- No alert is shown in this function.

- [ ] **Step 5: Keep list delete confirmation as the only list-level alert**

Confirm `requestDeleteSwitch(_:)` still contains:

```swift
SRAlertView(title: "notification".localizedString, message: "switchs_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
    self?.deleteConfirmedSwitch(switchData)
})]).show()
```

Expected behavior:

- List delete still asks for confirmation.
- Confirm enters the source-less execution path.

- [ ] **Step 6: Verify no deleted BPS source path dismisses before execution**

Run:

```bash
sed -n '456,476p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
sed -n '315,334p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- Real BPS confirm handlers call `deleteSwitchAction?(..., self)`.
- Real BPS confirm handlers do not call `dismiss(animated:)`.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: avoid duplicate battery switch delete flow"
```

Expected:

- Commit succeeds.
- Commit does not include unrelated files.

---

### Task 3: Verify deletion invariants and build

**Files:**
- Verify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Verify reset and address-level cloud sync still live in local delete**

Run:

```bash
rg -n "ConfigNodeReset\\(\\)|forceRemove\\(node:|SpaceChangeDataType\\.network\\(type: \\.address\\)|deleteSwitch\\(switchData:" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- `ConfigNodeReset()` is still sent in `silentlyResetBatteryPowerSwitchIfNeeded`.
- `forceRemove(node:)` is still used for real BPS node removal.
- `SpaceChangeDataType.network(type: .address)` is still posted for real BPS deletion.

- [ ] **Step 2: Verify switches list does not use local delete animation**

Run:

```bash
rg -n "deleteItems\\(at:" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- No output.

- [ ] **Step 3: Verify sync failure/back path does not delete local data**

Run:

```bash
sed -n '220,285p' SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected:

- `vc.backActionCallback = { _ in }` exists in `deleteSwitchData(_:source:)`.
- `deleteCache(switchData:)` is only called by `completeConfirmedSwitchDelete`.
- `completeConfirmedSwitchDelete` is only called by no-sync path and sync success path.

- [ ] **Step 4: Verify diff has no whitespace errors**

Run:

```bash
git diff --check
```

Expected:

- No output.

- [ ] **Step 5: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Output contains `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification on device or simulator**

Run these flows in the app:

1. Open `site - space - main - switches`.
2. Open a real Battery Power Switch detail page.
3. Tap top-right menu, tap `Delete`, then tap `Confirm`.
4. If the switch has no sync work, confirm the app shows `Done`, closes the BPS page, and the switches list refreshes.
5. If the switch has sync work, confirm the app pushes `Sync device(s)`.
6. On sync success, confirm the app returns to the BPS page, shows `Done`, closes the BPS page, and the switches list refreshes.
7. On sync failure or STOP, confirm the app stays on the sync page and the BPS still exists locally.
8. Repeat from BPS edit page bottom `Delete`.
9. Repeat from switches list edit-mode delete.

Expected:

- Real BPS delete shows only one confirmation alert.
- No second alert appears after `Confirm`.
- Local deletion only happens after no-sync direct path or sync success.
- Unlinked virtual BPS still deletes directly with `Done`.

- [ ] **Step 7: Commit verification fixes if any were needed**

Run:

```bash
git status --short
```

Expected:

- Only intentional implementation files are modified.
- Existing unrelated battery refresh files and untracked battery docs are not staged unless the current task explicitly changes them.

If verification caused small implementation corrections, commit only those corrections:

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: complete battery switch delete verification"
```
