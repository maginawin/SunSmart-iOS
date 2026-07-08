# EL Controller Function Test Status Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击 EL Controller Function Test 的 Start 时，先读取 Device Status，并按 `0x03 / 0x0E / other-timeout` 分支处理。

**Architecture:** 改动收口在 `ELControllerFunctionTestHelper` 和 `ELControllerFunctionTestView`。View 新增一个可复用现有 fault 样式的 Function Test 状态；helper 将 Start 流程拆成“读取 Device Status”和“发送 Start SET”两段，不改变页面进入、RX/TX、结果轮询和 Exit Function Test 的既有行为。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode iPhoneOS build。

---

## Test Strategy

当前 `SunSmart.xcodeproj` 只有 `SunSmart`、`Archipelago`、`SylSmart`、`SLG Sync Plus` 四个 App target，没有 XCTest target。`ELControllerFunctionTestHelper` 依赖 SDK `Node`、`MeshAPI` 静态发送入口和 UIKit 页面生命周期，不能在现有工程内低风险补一个真正可运行的 Red-Green 单测。

本次采用以下验证替代：

- `rg` 检查 Start 点击路径先发送 `.elControllerDeviceStatus`，`0x03` 分支再发送 `.elControllerStartFunctionTest`。
- `rg` 检查新增本地化 key 覆盖 English 与简体中文。
- `git diff --check`。
- iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Files

- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

## Task 1: Add Function Test Normal-Mode Warning State

- [ ] **Step 1: Update the Function Test state enum**

In `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`, add `case normalModeRequired` to `FunctionTestState`.

- [ ] **Step 2: Map the state to the existing fault style**

In `functionTestDisplayState(_:)`, add a branch for `normalModeRequired`:

```swift
case .normalModeRequired:
    return .init(
        buttonTitleKey: "el_controller_function_test_start_button",
        buttonAlpha: 1,
        rows: [.init(titleKey: "el_controller_function_test_normal_mode_required", style: .fault)],
        showsSpinner: false
    )
```

Expected behavior: button title returns to Start, the row uses the same `.fault` background and text colors as Battery Fault.

- [ ] **Step 3: Add localized strings**

Add to `SunSmart/en.lproj/Localizable.strings` near existing EL Controller Function Test keys:

```text
"el_controller_function_test_normal_mode_required" = "FT testing can only be performed in normal mode.";
```

Add to `SunSmart/zh-Hans.lproj/Localizable.strings` near the same keys:

```text
"el_controller_function_test_normal_mode_required" = "仅可在正常模式下执行功能测试。";
```

## Task 2: Gate Start Function Test by Device Status

- [ ] **Step 1: Split Start SET into a private helper**

In `ELControllerFunctionTestHelper`, move the current `SunricherVendorSet(function: .elControllerStartFunctionTest)` send logic from `startFunctionTest()` into a new private method:

```swift
private func sendStartFunctionTest(using vendorModel: Model) {
    MeshAPI.sendMessage(
        message: SunricherVendorSet(function: .elControllerStartFunctionTest),
        model: vendorModel,
        timeout: 5
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self = self, self.isActive else { return }
            guard let status = response as? SunricherVendorStatus,
                  status.status.code == .elControllerStartFunctionTest,
                  status.status.isSuccessful else {
                self.updateFunctionTestState?(.failed)
                return
            }
            self.updateFunctionTestState?(.awaiting)
            self.startFunctionTestResultPolling()
        }
    }
}
```

- [ ] **Step 2: Add a private Device Status request helper**

Add a new method in `ELControllerFunctionTestHelper`:

```swift
private func requestDeviceStatusBeforeStart(using vendorModel: Model) {
    MeshAPI.sendMessage(
        message: SunricherVendorGet(function: .elControllerDeviceStatus),
        model: vendorModel,
        timeout: 3
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self = self, self.isActive else { return }
            guard let status = response as? SunricherVendorStatus,
                  status.status.code == .elControllerDeviceStatus,
                  status.status.isSuccessful,
                  case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                self.updateFunctionTestState?(.normalModeRequired)
                return
            }

            if deviceStatus.rawValue == 0x03 {
                self.sendStartFunctionTest(using: vendorModel)
            } else if deviceStatus.isFunctionTesting {
                self.applyDeviceStatus(deviceStatus)
            } else {
                self.updateFunctionTestState?(.normalModeRequired)
            }
        }
    }
}
```

Expected behavior:

- `0x03`: continue to Start SET.
- `0x0E`: keep prior testing behavior through `applyDeviceStatus`.
- other raw values, timeout, parse failure, non-success ret: show normal-mode warning.

- [ ] **Step 3: Replace `startFunctionTest()` body after guards**

Keep existing offline and missing vendor-model guards. After guards:

```swift
isActive = true
stopFunctionTestResultPolling()
updateFunctionTestState?(.awaiting)
requestDeviceStatusBeforeStart(using: vendorModel)
```

Expected behavior: clicking Start no longer directly sends Start SET.

## Task 3: Verify

- [ ] **Step 1: Source checks**

Run:

```bash
rg -n "normalModeRequired|el_controller_function_test_normal_mode_required|requestDeviceStatusBeforeStart|sendStartFunctionTest|elControllerDeviceStatus|elControllerStartFunctionTest" SunSmart/Main/Device/View/ELControllerFunctionTestView.swift SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- `normalModeRequired` exists in the enum and display-state switch.
- `el_controller_function_test_normal_mode_required` exists in English and Simplified Chinese.
- `startFunctionTest()` calls `requestDeviceStatusBeforeStart`.
- `sendStartFunctionTest` is the only helper that sends `.elControllerStartFunctionTest`.

- [ ] **Step 2: Diff whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.
