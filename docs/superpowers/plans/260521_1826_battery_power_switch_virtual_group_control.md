# Battery Power Switch Virtual Group Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Battery Power Switch 设备页中间 8 个按钮和现有长按弹窗向 BPS 虚拟地址发送对应控制命令。

**Architecture:** 保持现有 UIKit 页面结构，新增一个 `PJEightKeySwitchMonitorVC.swift` 内部私有 sender，集中处理 BPS 虚拟地址、按钮索引到 Mesh message 的映射和发送。View 层只补齐 tap 回调，VC 负责同按钮 200ms 限流和把弹窗结果转给 sender，不改配置同步、target group 订阅或 SDK。

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, MeshAPI, xcodebuild

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 引入 `NordicSigMeshSDK`。
  - 增加私有 `PJEightKeySwitchVirtualGroupControlSender`。
  - 增加同按钮 200ms tap 限流。
  - 连接 panel tap、brightness popup ended、AUTO popup click 到 sender。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift`
  - 增加 `keyTapAction`。
  - 在 `configure(items:enabled:)` 中为每个 key 绑定 tap 回调。
  - 保留现有 dimming 长按、ON 长按和 disabled tap 行为。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift`
  - 让所有 enabled key 都能触发短按 tap。
  - 保留长按优先逻辑：长按已触发时，抬手不再触发 tap。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift`
  - 增加亮度结束回调。
  - 只在 slider `ended == true` 时回调外层。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift`
  - 增加 AUTO 点击回调。
  - 点击 AUTO 后先通知外层发送命令，再沿用当前 loading UI。

---

### Task 1: 增加 BPS 虚拟组控制 sender 和 VC 限流

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 写 RED 静态检查，确认 sender 与 200ms 限流尚不存在**

Run:

```bash
rg -n "PJEightKeySwitchVirtualGroupControlSender|keyTapThrottleInterval|handlePanelKeyTap|sendKeyTap\\(" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 没有输出。

- [ ] **Step 2: 引入 SDK 并增加 sender、限流状态**

In `PJEightKeySwitchMonitorVC.swift`, replace:

```swift
import UIKit
```

With:

```swift
import UIKit
import NordicSigMeshSDK
```

Inside `PJEightKeySwitchMonitorVC`, after:

```swift
private var batteryRefreshFlow: PJEightKeySwitchBatteryRefreshFlow?
```

Add:

```swift
private let virtualGroupControlSender = PJEightKeySwitchVirtualGroupControlSender()
private var lastKeyTapTimes: [Int: Date] = [:]
private let keyTapThrottleInterval: TimeInterval = 0.2
```

- [ ] **Step 3: 增加 panel tap 处理与同按钮限流 helper**

In `PJEightKeySwitchMonitorVC`, after `finishBatteryRefresh()`, add:

```swift
private func handlePanelKeyTap(index: Int) {
    guard shouldAcceptKeyTap(index: index) else {
        return
    }
    virtualGroupControlSender.sendKeyTap(index: index, switchData: viewModel.switchData)
}

private func shouldAcceptKeyTap(index: Int, now: Date = Date()) -> Bool {
    if let lastTapTime = lastKeyTapTimes[index],
       now.timeIntervalSince(lastTapTime) < keyTapThrottleInterval {
        return false
    }
    lastKeyTapTimes[index] = now
    return true
}
```

- [ ] **Step 4: 增加私有 sender 类型**

At the end of `PJEightKeySwitchMonitorVC.swift`, after the closing brace of `PJEightKeySwitchMonitorVC`, add:

```swift
private final class PJEightKeySwitchVirtualGroupControlSender {

    private static let dimmingStepLevel: Int32 = 13107

    func sendKeyTap(index: Int, switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress,
              let message = keyTapMessage(index: index, switchData: switchData) else {
            return
        }
        MeshAPI.sendMessage(message: message, address: address)
    }

    func sendBrightness(_ value: Int, switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress else {
            return
        }
        let lightness = Node.getLightness(lightness100: value)
        MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: address)
    }

    func sendAuto(switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress else {
            return
        }
        let message = LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)
        MeshAPI.sendMessage(message: message, address: address)
    }

    private func keyTapMessage(index: Int, switchData: PJEightKeySwitchData) -> MeshMessage? {
        switch index {
        case 0...3:
            return topKeyMessage(index: index, switchData: switchData)
        case 4:
            return GenericDeltaSetUnacknowledged(delta: Self.dimmingStepLevel)
        case 5:
            return GenericDeltaSetUnacknowledged(delta: -Self.dimmingStepLevel)
        case 6:
            return GenericOnOffSetUnacknowledged(true)
        case 7:
            return GenericOnOffSetUnacknowledged(false)
        default:
            return nil
        }
    }

    private func topKeyMessage(index: Int, switchData: PJEightKeySwitchData) -> MeshMessage? {
        switch switchData.eightKeyPanelType {
        case .scene8Key:
            let sceneNumbers = [
                switchData.sceneANumber,
                switchData.sceneBNumber,
                switchData.sceneCNumber,
                switchData.sceneDNumber
            ]
            guard sceneNumbers.indices.contains(index),
                  let sceneNumber = sceneNumbers[index] else {
                return nil
            }
            return SceneRecallUnacknowledged(sceneNumber)
        case .brightness8Key:
            let brightnessValues = [100, 75, 50, 25]
            guard brightnessValues.indices.contains(index) else {
                return nil
            }
            let lightness = Node.getLightness(lightness100: brightnessValues[index])
            return LightLightnessSetUnacknowledged(lightness: lightness)
        }
    }
}
```

- [ ] **Step 5: 静态验证 sender 覆盖命令映射**

Run:

```bash
rg -n "SceneRecallUnacknowledged|LightLightnessSetUnacknowledged|GenericDeltaSetUnacknowledged|GenericOnOffSetUnacknowledged|LightLCLightOnOffSetUnacknowledged|keyTapThrottleInterval: TimeInterval = 0.2" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 输出包含上述 6 类 message。
- 输出包含 `keyTapThrottleInterval: TimeInterval = 0.2`。

---

### Task 2: 补齐 8 个中间按钮的 tap 回调

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 写 RED 静态检查，确认 panel 还没有 key tap 回调**

Run:

```bash
rg -n "keyTapAction|handlePanelKeyTap|enumerated\\(\\)\\.forEach" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 如果 Task 1 已完成，只能在 VC 中看到 `handlePanelKeyTap`。
- `PJEightKeySwitchMonitorPanelView.swift` 中没有 `keyTapAction`。

- [ ] **Step 2: 在 panel view 增加 key tap callback**

In `PJEightKeySwitchMonitorPanelView`, replace:

```swift
var dimmingLongPressAction: ((PJEightKeySwitchMonitorViewModel.KeyItem.Direction) -> Void)?
var autoLongPressAction: (() -> Void)?
var disabledTapAction: (() -> Void)?
```

With:

```swift
var keyTapAction: ((Int) -> Void)?
var dimmingLongPressAction: ((PJEightKeySwitchMonitorViewModel.KeyItem.Direction) -> Void)?
var autoLongPressAction: (() -> Void)?
var disabledTapAction: (() -> Void)?
```

- [ ] **Step 3: 在 panel configure 中按 index 绑定 tap**

In `PJEightKeySwitchMonitorPanelView.configure(items:enabled:)`, replace:

```swift
zip(keyViews, items).forEach { keyView, item in
    keyView.configure(item: item, enabled: enabled)
    keyView.longPressAction = nil
    keyView.disabledTapAction = nil
```

With:

```swift
zip(keyViews, items).enumerated().forEach { index, pair in
    let (keyView, item) = pair
    keyView.configure(item: item, enabled: enabled)
    keyView.tapAction = nil
    keyView.longPressAction = nil
    keyView.disabledTapAction = nil
    if enabled {
        keyView.tapAction = { [weak self] in
            self?.keyTapAction?(index)
        }
    }
```

Expected:

- 每个 enabled key 都有 tap callback。
- 后续 dimming / ON long press 绑定逻辑保持原样。
- disabled 状态仍只绑定 `disabledTapAction`。

- [ ] **Step 4: 允许 key view 的所有 enabled key 短按**

In `PJEightKeySwitchMonitorKeyView.configure(item:enabled:)`, replace:

```swift
isPressable = enabled && isScenePressKey && item.detailText != nil
isLongPressable = enabled && (isDimmingKey || isAutoKey)
```

With:

```swift
isPressable = enabled
isLongPressable = enabled && (isDimmingKey || isAutoKey)
```

Expected:

- Scene 未配置时也能触发 tap，实际发送层静默忽略。
- Brightness、Dim Up、Dim Down、ON、OFF 都能触发 tap。
- 已触发长按的 dimming / ON 仍不会在抬手时触发 tap，因为现有 `didTriggerLongPress` 分支会 return。

- [ ] **Step 5: VC 绑定 panel key tap**

In `PJEightKeySwitchMonitorVC.bindActions()`, after:

```swift
headerView.refreshAction = { [weak self] in
    self?.refreshMonitor()
}
```

Add:

```swift
panelView.keyTapAction = { [weak self] index in
    self?.handlePanelKeyTap(index: index)
}
```

- [ ] **Step 6: 静态验证 8 key tap 路径**

Run:

```bash
rg -n "keyTapAction|isPressable = enabled|handlePanelKeyTap\\(index:" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `PJEightKeySwitchMonitorPanelView.swift` 包含 `var keyTapAction` 和 `self?.keyTapAction?(index)`。
- `PJEightKeySwitchMonitorKeyView.swift` 包含 `isPressable = enabled`。
- `PJEightKeySwitchMonitorVC.swift` 包含 `handlePanelKeyTap(index:)` 调用。

---

### Task 3: 接入亮度弹窗结束发送和 AUTO 弹窗发送

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 写 RED 静态检查，确认弹窗还没有发送回调**

Run:

```bash
rg -n "brightnessEndedAction|autoAction|sendBrightness|sendAuto" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 如果 Task 1 已完成，VC 中只看到 sender 的 `sendBrightness` / `sendAuto` 方法定义。
- 两个 popup controller 文件中没有 `brightnessEndedAction` 或 `autoAction`。

- [ ] **Step 2: 亮度弹窗增加 ended callback**

In `PJEightKeySwitchDimmingPopupController`, after:

```swift
final class PJEightKeySwitchDimmingPopupController: UIViewController {
```

Add:

```swift
var brightnessEndedAction: ((Int) -> Void)?
```

In `setupUI()`, after the slider constraints block:

```swift
sliderView.snp.makeConstraints { make in
    make.top.equalTo(titleLabel.snp.bottom).offset(Layout.sliderTop)
    make.left.equalToSuperview().offset(Layout.sliderHorizontalInset)
    make.right.equalToSuperview().offset(-Layout.sliderHorizontalInset)
    make.height.equalTo(Layout.sliderHeight)
    make.bottom.lessThanOrEqualToSuperview().offset(-Layout.sliderBottomInset)
}
```

Add:

```swift
sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
    guard ended else {
        return
    }
    self?.brightnessEndedAction?(value)
}
```

Expected:

- 拖动过程中 `ended == false` 时不发送。
- 松手或结束时只回调一次最终 value。

- [ ] **Step 3: AUTO 弹窗增加 click callback**

In `PJEightKeySwitchForcedAutoPopupController`, after:

```swift
final class PJEightKeySwitchForcedAutoPopupController: UIViewController {
```

Add:

```swift
var autoAction: (() -> Void)?
```

In `autoButtonAction()`, replace:

```swift
guard autoButtonState == .normal else { return }
autoButtonState = .loading
updateAutoButtonUI()
```

With:

```swift
guard autoButtonState == .normal else { return }
autoAction?()
autoButtonState = .loading
updateAutoButtonUI()
```

Expected:

- AUTO 点击立即通知外层发送一次命令。
- loading UI 仍按现有逻辑约 2.2 秒后恢复。
- 重复点击 loading 状态仍被 guard 过滤。

- [ ] **Step 4: VC 连接亮度弹窗 ended 发送**

In `PJEightKeySwitchMonitorVC.presentDimmingPopup()`, replace:

```swift
private func presentDimmingPopup() {
    let vc = PJEightKeySwitchDimmingPopupController()
    present(vc, animated: true)
}
```

With:

```swift
private func presentDimmingPopup() {
    let vc = PJEightKeySwitchDimmingPopupController()
    vc.brightnessEndedAction = { [weak self] value in
        guard let self else { return }
        self.virtualGroupControlSender.sendBrightness(value, switchData: self.viewModel.switchData)
    }
    present(vc, animated: true)
}
```

- [ ] **Step 5: VC 连接 AUTO 弹窗发送**

In `PJEightKeySwitchMonitorVC.presentForcedAutoPopup()`, replace:

```swift
private func presentForcedAutoPopup() {
    let vc = PJEightKeySwitchForcedAutoPopupController()
    present(vc, animated: true)
}
```

With:

```swift
private func presentForcedAutoPopup() {
    let vc = PJEightKeySwitchForcedAutoPopupController()
    vc.autoAction = { [weak self] in
        guard let self else { return }
        self.virtualGroupControlSender.sendAuto(switchData: self.viewModel.switchData)
    }
    present(vc, animated: true)
}
```

- [ ] **Step 6: 静态验证弹窗发送只在确认动作后发生**

Run:

```bash
rg -n "brightnessEndedAction|guard ended else|autoAction\\?\\(\\)|sendBrightness\\(value|sendAuto\\(switchData" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 亮度弹窗包含 `guard ended else { return }`。
- AUTO 弹窗包含 `autoAction?()`。
- VC 包含 `sendBrightness(value, switchData:)` 和 `sendAuto(switchData:)`。

---

### Task 4: 全量静态检查、构建验证和提交

**Files:**
- Verify: all modified files from Tasks 1-3

- [ ] **Step 1: 检查没有 App 层重发逻辑**

Run:

```bash
rg -n "asyncAfter\\(deadline: \\.now\\(\\) \\+ 0\\.2|sendKeyTap\\(index:.*sendKeyTap|sendBrightness\\(.*sendBrightness|sendAuto\\(.*sendAuto" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 没有输出。
- 注意：项目其他文件可能有 `asyncAfter`，本检查只针对 BPS monitor VC。

- [ ] **Step 2: 检查同按钮 200ms 限流存在**

Run:

```bash
rg -n "keyTapThrottleInterval: TimeInterval = 0\\.2|lastKeyTapTimes\\[index\\]|now\\.timeIntervalSince\\(lastTapTime\\) < keyTapThrottleInterval" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 输出 3 行，分别对应限流常量、读取上次点击时间和更新时间。

- [ ] **Step 3: 检查所有命令都走 BPS 虚拟地址**

Run:

```bash
rg -n "guard let address = switchData.linkGroupAddress|MeshAPI\\.sendMessage\\(message: .*address: address\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- sender 的 `sendKeyTap`、`sendBrightness`、`sendAuto` 都先读取 `switchData.linkGroupAddress`。
- sender 的发送都使用 `address: address`。

- [ ] **Step 4: 空白检查**

Run:

```bash
git diff --check
```

Expected:

- 没有输出。

- [ ] **Step 5: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 检查待提交改动范围**

Run:

```bash
git status --short
```

Expected:

- 本任务相关改动只包含：
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift`
- 工作区可能已有其它用户改动；不要 stage 或 revert 不属于本任务的文件。

- [ ] **Step 7: 提交实现**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchForcedAutoPopupController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift
git commit -m "feat: control battery switch virtual group"
```

Expected:

- Commit 只包含本任务相关的 5 个代码文件，不包含无关文件。
- Commit message 不包含 codex 相关行。

## Plan Self-Review

- Spec coverage：8 个按钮单击、scene 未配置静默、无 target group 也发送、亮度 ended 发送、AUTO 弹窗发送、不重发、同按钮 200ms 限流均有对应任务。
- Placeholder scan：无未决内容，步骤完整。
- Type consistency：计划中使用的 `PJEightKeySwitchData`、`PJEightKeySwitchMonitorViewModel.KeyItem`、`MeshMessage`、`MeshAPI.sendMessage(message:address:)`、`GenericDeltaSetUnacknowledged(delta:)`、`LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 与现有代码或 SDK API 一致。
- Scope check：计划只触碰 BPS monitor 页面、两个 popup 和 key view，不改配置同步、SDK 或普通 switch 页面。
