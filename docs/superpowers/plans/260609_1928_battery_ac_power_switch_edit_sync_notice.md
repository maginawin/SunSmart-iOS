# Battery/AC Power Switch Edit Sync Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在 battery/ac power switch edit 页面 Name 右侧显示与 Kinetic switch 一致的 `Device not synced` 控件组，并点击进入同步页面。

**Architecture:** 只改 power switch edit 页自身边界：`PJEightKeySwitchEditorView` 负责展示按钮，`PJPreAddEightKeySwitchesVC` 负责根据 `PJEightKeySwitchData.needsBatteryPowerSwitchSync` 控制显隐和复用既有同步跳转。不同步未保存表单内容，避免点击提示时把编辑中变更混入重试同步。

**Tech Stack:** UIKit、SnapKit、现有本地化 key、现有 `SyncDevicesViewController(type: .batteryPowerSwitch)` 同步流程。

---

## 文件结构

- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift`
  - 增加 `syncFailedButton`。
  - 样式与 Kinetic `DeviceSwitchHeaderView.syncFailedBtn` 对齐。
  - 放在 Name 标题行右侧。
- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 给按钮绑定点击事件。
  - 根据 `currentEightKeySwitchData?.needsBatteryPowerSwitchSync == true` 控制显隐。
  - 点击时复用现有 `pushBatteryPowerSwitchSync(_:)`。
- 不修改 Kinetic switch、列表页、同步页、本地化、资源、target 配置或依赖。

## Task 1: 增加 edit 页同步失败控件

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift`

- [x] **Step 1: 在 editor view 增加按钮属性**

在 `clearNameButton` 后、`settingsContainerView` 前新增：

```swift
    let syncFailedButton: UIButton = {
        let button = UIButton(
            title: "devices_not_synced".localizedString,
            titleSize: 14,
            titleWeight: .light,
            titleColor: Red_Color,
            fit: false,
            normalImageName: "schedule_sync_failed"
        )
        button.isHidden = true
        button.setImagePosition(position: .left, spacing: SCRXFrom(4))
        return button
    }()
```

- [x] **Step 2: 把按钮加入 Name 标题行**

在 `contentView.addSubview(nameSectionLabel)` 之后加入：

```swift
        contentView.addSubview(syncFailedButton)
        syncFailedButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(nameSectionLabel)
        }
```

- [x] **Step 3: 本地静态检查**

Run: `git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift`

Expected:
- 仅新增 `syncFailedButton` 属性和约束。
- 没有调整 Name 输入框、settings、panel preview、link button 的原有布局。

## Task 2: 接入显隐状态与点击跳转

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: 绑定按钮点击事件**

在 `setupUI()` 中 `editorView.clearNameButton.addTarget(...)` 后加入：

```swift
        editorView.syncFailedButton.addTarget(self, action: #selector(syncFailedButtonAction), for: .touchUpInside)
```

- [x] **Step 2: 增加点击处理方法**

在 `saveBarButtonAction()` 后加入：

```swift
    @objc private func syncFailedButtonAction() {
        view.endEditing(true)
        guard let switchData = currentEightKeySwitchData,
              switchData.needsBatteryPowerSwitchSync else {
            updateSyncFailedButtonVisibility()
            return
        }
        pushBatteryPowerSwitchSync(switchData)
    }
```

说明：这里读取当前持久化/实时 switch 数据，不调用 `viewModel.buildSwitchData()`，避免未保存表单内容被同步流程持久化。

- [x] **Step 3: 增加显隐刷新方法**

在 `updateSaveBarButtonState()` 后加入：

```swift
    private func updateSyncFailedButtonVisibility() {
        guard isEditMode,
              let switchData = currentEightKeySwitchData else {
            editorView.syncFailedButton.isHidden = true
            return
        }
        editorView.syncFailedButton.isHidden = !switchData.needsBatteryPowerSwitchSync
    }
```

- [x] **Step 4: 在现有 UI 刷新路径调用显隐刷新**

在 `bindViewModel()` 中 `updateSaveBarButtonState()` 后加入：

```swift
        updateSyncFailedButtonVisibility()
```

在 `refreshEditingStateFromCurrentSwitchData()` 中保持调用 `bindViewModel()`，不额外重复调用。

- [x] **Step 5: 同步回调后刷新本页状态**

在 `pushBatteryPowerSwitchSync(_:)` 的 `syncSuccessCallback` 中，`postSwitchDataChangedNotifications()` 后加入：

```swift
            self.refreshEditingStateFromCurrentSwitchData()
```

在 `backActionCallback` 中，`postSwitchDataChangedNotifications()` 后加入：

```swift
            self.refreshEditingStateFromCurrentSwitchData()
```

说明：现有逻辑随后会 `popBackAfterBatteryPowerSwitchSync(animated: true)`，刷新用于保证 iPad 或未立即销毁场景下按钮状态不滞留。

- [x] **Step 6: 本地静态检查**

Run: `git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

Expected:
- 新增按钮 target、`syncFailedButtonAction()`、`updateSyncFailedButtonVisibility()`。
- 显示条件为 `needsBatteryPowerSwitchSync`。
- 点击路径复用 `pushBatteryPowerSwitchSync(_:)`。
- 没有改变 `submitBatteryPowerSwitch(_:)` 的保存和同步判断。

## Task 3: 构建与人工验证

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: 运行 whitespace 检查**

Run: `git diff --check`

Expected: no output, exit code 0.

- [x] **Step 2: 运行 iPhoneOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [x] **Step 3: 人工路径验证**

验证路径：

- switches 页面中，选择一个需要同步的 battery power switch，长按进入 edit 页。
- 确认 Name 右侧显示 `Device not synced`，包含左侧图标。
- 点击 `Device not synced`，确认进入同步页面。
- switches 页面中，选择一个需要同步的 ac power switch，长按进入 edit 页，重复上述检查。
- 选择无需同步的 battery/ac power switch，进入 edit 页，确认不显示 `Device not synced`。
- 新建 battery/ac power switch 页面不显示该控件。
- 未绑定真实 power switch 的虚拟 switch edit 页不显示该控件。

Expected:
- 需要同步时显示并可跳转。
- 无需同步、新建、未绑定真实 power switch 时隐藏。
- Kinetic switch edit 页视觉和行为不变。

- [x] **Step 4: 检查目标文件范围**

Run: `git status --short`

Expected:

```text
 M SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
 M SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift
?? docs/superpowers/plans/260609_1928_battery_ac_power_switch_edit_sync_notice.md
```

如果计划文档已单独提交，则 Expected 中不包含计划文档。

## 自查

- Spec 覆盖：Name 右侧提示、Kinetic 视觉一致、点击跳同步页、完整需要同步口径、非目标范围均有对应任务。
- 未完成标记检查：未发现空泛步骤或未完成标记。
- 类型一致性：计划使用现有 `PJEightKeySwitchData.needsBatteryPowerSwitchSync`、`currentEightKeySwitchData`、`pushBatteryPowerSwitchSync(_:)`、`SyncDevicesViewController(type: .batteryPowerSwitch)`，均已在当前代码中存在。
