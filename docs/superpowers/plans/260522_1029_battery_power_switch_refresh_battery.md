# Battery Power Switch Refresh Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Battery Power Switch 的 Refresh Device 电量读取重试间隔从 3 秒改为 1 秒，并更新中英文弹窗提示，且不影响 SAVE profile configuration 的等待激活间隔。

**Architecture:** Refresh Device 电量刷新由 `PJEightKeySwitchBatteryRefreshFlow` 独立管理，SAVE profile configuration 的等待激活由 `PJEightKeySwitchActivationFlow` 独立管理。本次只修改 refresh flow 的 probe timer 与 `neightkeyswitches_refresh_message` 本地化文案，通过静态检查确认 activation flow 仍保持 3 秒。

**Tech Stack:** Swift、UIKit、Timer、NordicSigMeshSDK `GenericBatteryGet`、iOS `.strings` 本地化、Xcode `xcodebuild`。

---

## 文件结构

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
  - 负责 Refresh Device 弹窗和电量读取 flow。
  - 将 battery refresh probe interval 显式命名为 1 秒，并在 `probeTimer` 中使用。
- Do not modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 负责 SAVE profile configuration 后的等待激活 flow。
  - 只用于验证其 activation probe timer 仍为 3 秒。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 更新英文 refresh 提示。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 更新简中 refresh 提示。

当前工作区已有 unrelated 改动，不要添加或修改：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`
- `docs/260522_1004_space_permission_popup_analysis.md`
- `docs/260522_1008_space_permission_popup_root_cause_and_fix_plan.md`

---

### Task 1: 调整 Refresh Battery Probe 间隔

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift:162-230`

- [ ] **Step 1: 记录当前 refresh timer 行为**

Run:

```bash
nl -ba SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift | sed -n '219,230p'
```

Expected: 看到 `Timer.scheduledTimer(withTimeInterval: 3, repeats: true)`。

- [ ] **Step 2: 修改 refresh flow，增加 1 秒命名常量并使用它**

在 `PJEightKeySwitchBatteryRefreshFlow` 的 stored properties 中增加：

```swift
private let batteryRefreshProbeInterval: TimeInterval = 1
```

将 `startWaiting()` 中的 timer 从：

```swift
probeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
    guard let self else { return }
    self.sendProbe(for: self.generation)
}
```

改为：

```swift
probeTimer = Timer.scheduledTimer(withTimeInterval: batteryRefreshProbeInterval, repeats: true) { [weak self] _ in
    guard let self else { return }
    self.sendProbe(for: self.generation)
}
```

不要修改 `sendProbe(for: generation)` 的首次立即发送逻辑。

- [ ] **Step 3: 检查 refresh flow 已使用 1 秒间隔**

Run:

```bash
rg -n "batteryRefreshProbeInterval|withTimeInterval: batteryRefreshProbeInterval|withTimeInterval: 3" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
```

Expected:

```text
匹配 batteryRefreshProbeInterval 的定义
匹配 withTimeInterval: batteryRefreshProbeInterval
不再匹配 withTimeInterval: 3
```

- [ ] **Step 4: 检查 SAVE activation flow 仍保持 3 秒**

Run:

```bash
rg -n "probeTimer = Timer\\.scheduledTimer\\(withTimeInterval: 3" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected: 至少 1 个匹配，位置在 `PJEightKeySwitchActivationFlow.startWaiting()`。

- [ ] **Step 5: 提交 Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
git commit -m "fix: speed up battery refresh probe interval"
```

Expected: commit 成功，且不包含 Space 相关文件。

---

### Task 2: 更新 Refresh Device 中英文提示文案

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings:828`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:828`

- [ ] **Step 1: 修改英文文案**

将 `SunSmart/en.lproj/Localizable.strings` 中：

```text
"neightkeyswitches_refresh_message" = "Press any button on the device";
```

改为：

```text
"neightkeyswitches_refresh_message" = "Press any button on the device multiple times";
```

- [ ] **Step 2: 修改简中文案**

将 `SunSmart/zh-Hans.lproj/Localizable.strings` 中：

```text
"neightkeyswitches_refresh_message" = "请按一下设备上的任意按键";
```

改为：

```text
"neightkeyswitches_refresh_message" = "请多次按下设备上的任意按键";
```

- [ ] **Step 3: 检查中英文文案**

Run:

```bash
rg -n "\"neightkeyswitches_refresh_message\"" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

```text
SunSmart/en.lproj/Localizable.strings:..."neightkeyswitches_refresh_message" = "Press any button on the device multiple times";
SunSmart/zh-Hans.lproj/Localizable.strings:..."neightkeyswitches_refresh_message" = "请多次按下设备上的任意按键";
```

- [ ] **Step 4: 提交 Task 2**

Run:

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: update battery refresh prompt copy"
```

Expected: commit 成功，且只包含两个本地化文件。

---

### Task 3: 验证 Build 与改动范围

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 静态验证 refresh timer 与 activation timer**

Run:

```bash
rg -n "batteryRefreshProbeInterval|withTimeInterval: batteryRefreshProbeInterval" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
rg -n "probeTimer = Timer\\.scheduledTimer\\(withTimeInterval: 3" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

```text
Refresh file shows the 1-second batteryRefreshProbeInterval constant and its timer usage.
Activation file still shows the 3-second activation probe timer.
```

- [ ] **Step 2: 静态验证文案**

Run:

```bash
rg -n "Press any button on the device multiple times|请多次按下设备上的任意按键" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 英文和简中各 1 个匹配。

- [ ] **Step 3: 检查 git 范围**

Run:

```bash
git status --short
```

Expected:

```text
仍可看到任务开始前已有的 unrelated Space 改动和 docs/260522_100x... 文件。
不要看到本任务文件处于未提交状态。
```

- [ ] **Step 4: 运行 iPhoneOS Debug build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

如果 build 失败，先确认失败是否来自本任务修改的 3 个文件。若失败来自已有 unrelated Space 改动，不要修改 Space 文件，记录失败原因并向用户说明。

- [ ] **Step 5: 汇总结果**

记录：

```text
Refresh Device: GenericBatteryGet immediate probe retained; repeat interval changed to 1s.
SAVE profile activation: activation probe interval remains 3s.
Copy: English and Simplified Chinese refresh prompt updated.
Build: report xcodebuild result.
```

