# AC Power Switch Identify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AC Power Switch 点击设备页右上角 `Identify` 后立即发送一次 Identify 命令，不再展示 Battery Power Switch 使用的激活等待弹窗。

**Architecture:** 在现有设备页入口 `PJEightKeySwitchMonitorVC.identifyAction()` 做 Battery/AC 分流。Battery 继续使用 `PJEightKeySwitchIdentifyFlow`；AC 直接复用 `MeshBatteryPowerSwitchIdentifySender.sendIdentify(to:)` 单次发送能力，不新增 CID/PID 映射、不新增文案、不改弹窗 Flow。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 新增一个 Identify sender 属性，供 AC 分支发送单次 Identify。
  - 修改 `identifyAction()`，将 `informationNode` guard 改为绑定节点变量，并在 `.ac` 时直接发送后返回。
- Read-only reference: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - `MeshBatteryPowerSwitchIdentifySender` 当前封装了 `MeshAPI.identify(address:attentionTimer: 6)`，不需要修改。

## Task 1: 分流 AC Power Switch Identify

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Inspect the current Identify entry**

Run:

```sh
sed -n '1,125p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: `identifyAction()` currently guards `viewModel.informationNode != nil` and always starts `PJEightKeySwitchIdentifyFlow`.

- [ ] **Step 2: Add a sender property to the view controller**

In `PJEightKeySwitchMonitorVC`, add this stored property near the existing flow properties:

```swift
private let identifySender = MeshBatteryPowerSwitchIdentifySender()
```

Expected surrounding shape:

```swift
private var activationFlow: PJEightKeySwitchActivationFlow?
private var batteryRefreshFlow: PJEightKeySwitchBatteryRefreshFlow?
private var txEnableFlow: PJEightKeySwitchTxEnableFlow?
private var identifyFlow: PJEightKeySwitchIdentifyFlow?
private let identifySender = MeshBatteryPowerSwitchIdentifySender()
```

- [ ] **Step 3: Implement AC direct Identify branch**

Replace `identifyAction()` with:

```swift
private func identifyAction() {
    guard viewModel.canEditPowerSwitch else {
        showNoPermissionTip()
        return
    }
    guard let node = viewModel.informationNode else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }

    if viewModel.switchData.powerSwitchKind == .ac {
        identifySender.sendIdentify(to: node)
        return
    }

    let flow = PJEightKeySwitchIdentifyFlow(
        presenter: self,
        switchData: viewModel.switchData,
        onFinished: { [weak self] in
            self?.identifyFlow = nil
        }
    )
    identifyFlow = flow
    flow.start()
}
```

Expected behavior:

- AC Power Switch sends one Identify command and returns immediately.
- Battery Power Switch still starts `PJEightKeySwitchIdentifyFlow`.
- The existing permission and missing-node guards stay unchanged in behavior.

- [ ] **Step 4: Confirm no popup flow is reachable for AC**

Run:

```sh
sed -n '96,125p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: the `.ac` branch appears before `PJEightKeySwitchIdentifyFlow` is created.

- [ ] **Step 5: Run diff hygiene check**

Run:

```sh
git diff --check
```

Expected: no output.

- [ ] **Step 6: Build SunSmart for iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit implementation**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "fix: identify ac power switch directly"
```

Expected: one commit containing only the Identify behavior change.

## Self-Review

- Spec coverage: The plan preserves Battery Identify, changes AC Identify to one immediate send, keeps existing menu/permission/missing-node guards, and avoids CID/PID mapping or localization changes.
- Placeholder scan: No placeholders remain.
- Type consistency: `MeshBatteryPowerSwitchIdentifySender`, `PJEightKeySwitchIdentifyFlow`, `viewModel.switchData.powerSwitchKind`, `.ac`, and `viewModel.informationNode` match the existing code inspected for this plan.
