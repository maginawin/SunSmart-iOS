# EL Controller RX/TX Connection State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `0x0A78 / 0x24C1` EL Controller 增加 Space 生命周期内共享的 RX/TX Connection State，并让 Space Lights 列表与设备详情页保持一致。

**Architecture:** 在 App 层为 SDK `Node` 增加运行态 RX/TX 状态扩展，作为自动检查、Lights 列表和详情页的共享状态源。`DevicesViewController` 负责 Space 首次连接后的单次自动读取，`ELControllerFunctionTestHelper` 负责详情页读取和手动 Check 回写。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, NotificationCenter, XCTest-free iPhoneOS build verification.

---

## File Structure

- Create: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`
  - 定义 EL Controller RX/TX 运行态枚举。
  - 为 `Node` 提供默认 Normal 的 associated-object 状态属性。
  - 提供状态更新 helper，状态变更时发 `deviceStateUpdateNotificationName`。
  - 提供 EL Controller 判定和列表图标选择 helper。

- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
  - 在线 EL Controller 使用 `node.elControllerLightsIconName`，根据 RX/TX 状态展示 normal/fault 图标。
  - Offline 仍保持现有 `offlineIconName` 优先。

- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - 在首次 Mesh 连接成功门禁中触发 EL Controller RX/TX 自动检查。
  - 只在本次 Space 进入生命周期内执行一次；断线重连不重复执行。
  - 逐台发送 `SunricherVendorGet(.elControllerRxTxCableConnection)`，明确返回后更新 `Node` 共享状态。

- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
  - `startPageSession()` 初始化 RX/TX UI 时读取 `node.elControllerRxTxConnectionState`。
  - 手动 Check 返回明确成功/失败时回写 `node` 状态。
  - 超时、无响应、解析失败时恢复当前 `node` 状态，不写 Fault。

- Verify only: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
  - 现有 `RxTxState.normal/fault/checking/idle` 可复用，无需新增 UI 状态。

---

### Task 1: Add Shared Runtime RX/TX State On Node

**Files:**
- Create: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`

- [ ] **Step 1: Create the Node extension file**

Add:

```swift
//
//  Node+ELControllerRxTx.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/26.
//

import Foundation
import NordicSigMeshSDK

enum ELControllerRxTxConnectionState {
    case normal
    case fault
}

private enum ELControllerRxTxAssociatedKeys {
    static var connectionState: UInt8 = 0
}

extension Node {

    var supportsELControllerRxTxConnectionState: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x24C1
    }

    var elControllerRxTxConnectionState: ELControllerRxTxConnectionState {
        get {
            objc_getAssociatedObject(self, &ELControllerRxTxAssociatedKeys.connectionState) as? ELControllerRxTxConnectionState ?? .normal
        }
        set {
            objc_setAssociatedObject(self, &ELControllerRxTxAssociatedKeys.connectionState, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    @discardableResult
    func updateELControllerRxTxConnectionState(_ state: ELControllerRxTxConnectionState) -> Bool {
        guard supportsELControllerRxTxConnectionState else {
            return false
        }
        guard elControllerRxTxConnectionState != state else {
            return false
        }
        elControllerRxTxConnectionState = state
        NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: self)
        return true
    }

    var elControllerLightsIconName: String {
        guard supportsELControllerRxTxConnectionState else {
            return iconName
        }
        switch elControllerRxTxConnectionState {
        case .normal:
            return iconName
        case .fault:
            return unsyncIconName
        }
    }
}
```

- [ ] **Step 2: Review compile boundaries**

Confirm the extension is in the app target path under `SunSmart/Common/Data/`, not the SDK. This keeps the state App-only and avoids changing SDK data contracts.

- [ ] **Step 3: Commit Task 1**

Run:

```bash
git add SunSmart/Common/Data/Node+ELControllerRxTx.swift
git commit -m "Add EL Controller RXTX runtime state"
```

Expected: commit succeeds and only the new extension file is included.

---

### Task 2: Use RX/TX State For Lights Item Icon

**Files:**
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`

- [ ] **Step 1: Update online icon assignment**

In `device.didSet`, replace the online branch icon assignment:

```swift
iconImageView.image = UIImage(named: device.iconName)
```

with:

```swift
iconImageView.image = UIImage(named: device.supportsELControllerRxTxConnectionState ? device.elControllerLightsIconName : device.iconName)
```

Keep the existing offline branch unchanged:

```swift
iconImageView.image = UIImage(named: device.offlineIconName)
```

This preserves Offline priority.

- [ ] **Step 2: Validate visual rules by code inspection**

Check these paths:

```swift
if device.isKeybindComplete {
    iconImageView.image = UIImage(named: device.supportsELControllerRxTxConnectionState ? device.elControllerLightsIconName : device.iconName)

    if device.state {
        ...
    } else {
        iconImageView.image = UIImage(named: device.offlineIconName)
    }
}
```

Expected:

- Online + Normal uses `device_EMSign`.
- Online + Fault uses `device_unsync_EMSign`.
- Offline uses `device_offline_EMSign`, regardless of stored RX/TX state.

- [ ] **Step 3: Run a focused compile check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/View/DevicesViewCell.swift
git commit -m "Show EL Controller RXTX fault icon"
```

Expected: commit succeeds and only `DevicesViewCell.swift` is included.

---

### Task 3: Trigger One-Time RX/TX Auto Check After First Space Connection

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`

- [ ] **Step 1: Add state flag**

Near existing properties:

```swift
/// 是否首次连接
private var firstConnectionNetwork: Bool = true
```

Add:

```swift
private var hasRequestedELControllerRxTxConnectionState = false
```

- [ ] **Step 2: Trigger after first connection**

Inside `addObservation()`, in the existing block:

```swift
if MeshLibManager.manager.isMeshNetworkConnected, self.firstConnectionNetwork {
    // 首次连接上mesh网络
    self.firstConnectionNetwork = false
    ...
}
```

After `self.getMeshDistribution()` add:

```swift
self.scheduleInitialELControllerRxTxConnectionCheck()
```

This keeps the trigger inside the existing first-connection gate.

- [ ] **Step 3: Add scheduler method**

Add this method in `DevicesViewController` extension or private methods area:

```swift
private func scheduleInitialELControllerRxTxConnectionCheck() {
    guard !hasRequestedELControllerRxTxConnectionState else {
        return
    }
    hasRequestedELControllerRxTxConnectionState = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.requestInitialELControllerRxTxConnectionState()
    }
}
```

- [ ] **Step 4: Add request method**

Add:

```swift
private func requestInitialELControllerRxTxConnectionState() {
    guard MeshLibManager.manager.isMeshNetworkConnected else {
        return
    }

    let nodes = MeshNetworkManager.instance.realNodes.filter {
        $0.supportsELControllerRxTxConnectionState &&
        $0.isKeybindComplete &&
        $0.state &&
        $0.sunricherVendorModel != nil
    }

    nodes.enumerated().forEach { index, node in
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) { [weak self, weak node] in
            guard let self,
                  let node,
                  MeshLibManager.manager.isMeshNetworkConnected,
                  node.state,
                  let vendorModel = node.sunricherVendorModel else {
                return
            }
            self.requestELControllerRxTxConnectionState(node: node, vendorModel: vendorModel)
        }
    }
}
```

- [ ] **Step 5: Add send method**

Add:

```swift
private func requestELControllerRxTxConnectionState(node: Node, vendorModel: Model) {
    MeshAPI.sendMessage(
        message: SunricherVendorGet(function: .elControllerRxTxCableConnection),
        model: vendorModel,
        timeout: 5
    ) { response in
        DispatchQueue.main.async {
            guard let status = response as? SunricherVendorStatus,
                  status.status.code == .elControllerRxTxCableConnection else {
                return
            }

            let state: ELControllerRxTxConnectionState = status.status.isSuccessful ? .normal : .fault
            node.updateELControllerRxTxConnectionState(state)
        }
    }
}
```

This implements the confirmed B behavior: timeout, nil response, wrong response type, or parse failure do not change state.

- [ ] **Step 6: Run compile check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift
git commit -m "Check EL Controller RXTX state on first connection"
```

Expected: commit succeeds and only `DevicesViewController.swift` is included.

---

### Task 4: Sync Detail Page RX/TX UI With Shared Node State

**Files:**
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`

- [ ] **Step 1: Add helper to apply stored state**

Add:

```swift
private func applyStoredRxTxState() {
    switch node.elControllerRxTxConnectionState {
    case .normal:
        updateRxTxState?(.normal)
    case .fault:
        updateRxTxState?(.fault)
    }
}
```

- [ ] **Step 2: Update page session reset behavior**

In `startPageSession()`, replace:

```swift
resetUI()
```

with:

```swift
resetFunctionTestUI()
applyStoredRxTxState()
```

Then replace the existing `resetUI()` method:

```swift
private func resetUI() {
    updateFunctionTestState?(.idle)
    updateRxTxState?(.idle)
}
```

with:

```swift
private func resetFunctionTestUI() {
    updateFunctionTestState?(.idle)
}
```

- [ ] **Step 3: Keep page exit function-test reset scoped**

In `stopPageSession()`, replace:

```swift
resetUI()
```

with:

```swift
resetFunctionTestUI()
```

Do not reset RX/TX state on page exit. It should remain in `node.elControllerRxTxConnectionState` for the current Space session.

- [ ] **Step 4: Update manual Check success/failure handling**

In `checkRxTxCable()` response block, replace:

```swift
guard let status = response as? SunricherVendorStatus,
      status.status.code == .elControllerRxTxCableConnection,
      status.status.isSuccessful else {
    self.updateRxTxState?(.fault)
    return
}
self.updateRxTxState?(.normal)
```

with:

```swift
guard let status = response as? SunricherVendorStatus,
      status.status.code == .elControllerRxTxCableConnection else {
    self.applyStoredRxTxState()
    return
}

let state: ELControllerRxTxConnectionState = status.status.isSuccessful ? .normal : .fault
self.node.updateELControllerRxTxConnectionState(state)
self.applyStoredRxTxState()
```

This ensures timeout or parse failure does not write Fault.

- [ ] **Step 5: Update passive vendor status handling**

In `handleStatus(_:, sentFrom:)`, replace:

```swift
case .elControllerRxTxCableConnection:
    updateRxTxState?(status.status.isSuccessful ? .normal : .fault)
    return true
```

with:

```swift
case .elControllerRxTxCableConnection:
    let state: ELControllerRxTxConnectionState = status.status.isSuccessful ? .normal : .fault
    node.updateELControllerRxTxConnectionState(state)
    applyStoredRxTxState()
    return true
```

- [ ] **Step 6: Run compile check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit Task 4**

Run:

```bash
git add SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
git commit -m "Sync EL Controller detail RXTX state"
```

Expected: commit succeeds and only `ELControllerFunctionTestHelper.swift` is included.

---

### Task 5: Final Verification

**Files:**
- Verify: all files changed in Tasks 1-4.

- [ ] **Step 1: Check status**

Run:

```bash
git status --short
```

Expected: clean working tree, or only intentional uncommitted verification notes if the user asked for them.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check HEAD~4..HEAD
```

Expected: no output.

- [ ] **Step 3: Run final iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual log verification with device**

When testing with a real EL Controller, verify logs:

```text
Sending Access PDU (opcode: 0xF1780A, parameters: 0x4500)
Response Access PDU (opcode: 0xF3780A, parameters: 0x450000)
```

Expected for success:

- `ret == 0`
- `node.elControllerRxTxConnectionState == .normal`
- Lights item shows `device_EMSign`
- Detail RX/TX card shows `Connection Normal`

For explicit failure:

```text
Response Access PDU (opcode: 0xF3780A, parameters: 0x4500XX)
```

Expected when `XX != 00`:

- `node.elControllerRxTxConnectionState == .fault`
- Lights item shows `device_unsync_EMSign`
- Detail RX/TX card shows `Connection Fault`

- [ ] **Step 5: Confirm lifecycle behavior**

Manual scenario checklist:

- Enter Space, first connection succeeds: one RX/TX GET is sent for each online/keybound EL Controller.
- Disconnect and reconnect inside the same Space VC: no additional automatic RX/TX GET is sent.
- Pop back out of Space, enter again, reconnect: automatic RX/TX GET is sent again.
- EL Controller Offline: Lights item shows `device_offline_EMSign`.
- Detail manual Check success/failure updates both detail card and Lights list.
- Detail manual Check timeout leaves the prior RX/TX state unchanged.

- [ ] **Step 6: Commit any final fixes**

If final verification required fixes, commit them with focused messages. If no fixes were needed, do not create an empty commit.
