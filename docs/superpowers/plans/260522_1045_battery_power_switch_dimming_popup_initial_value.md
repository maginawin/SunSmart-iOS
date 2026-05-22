# Battery Power Switch Dimming Popup Initial Value Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch 页面中间开关面板长按 Dim Up / Dim Down 后，亮度 slider 弹窗从 0% 跳到 50% 的生硬显示问题。

**Architecture:** 只调整 `PJEightKeySwitchDimmingPopupController` 的初始值设置时机。让 slider 在弹窗首帧展示前完成 50% 初始化，并保持用户滑动结束后才发送虚拟组亮度命令。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、现有 `BuoySliderView` / `CustomDeviceSlider`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift`
  - 负责 Battery Power Switch dimming 底部弹窗 UI 和 slider 结束滑动后的亮度回调。
  - 本次只移动默认值设置，不改弹窗展示方式和 Mesh 发送逻辑。

## Task 1: 调整 Dimming Popup Slider 初始值时机

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift:49-104`

- [ ] **Step 1: 记录当前问题位置**

Run:

```bash
nl -ba SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift | sed -n '49,104p'
```

Expected: 看到 `viewDidAppear(_:)` 中存在：

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    sliderView.value = 50
}
```

- [ ] **Step 2: 移除 `viewDidAppear(_:)` 中的 50% 赋值**

在 `PJEightKeySwitchDimmingPopupController.swift` 中删除以下方法：

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    sliderView.value = 50
}
```

删除后 `viewDidLoad()` 后面应直接进入 `setupUI()`：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
}

private func setupUI() {
    view.backgroundColor = .clear
```

- [ ] **Step 3: 在回调绑定前设置初始值**

在 `setupUI()` 中，`sliderView.snp.makeConstraints` 闭包结束后、`sliderView.valueThrottleChangedCallback` 绑定前，加入：

```swift
sliderView.value = 50
```

目标代码结构应为：

```swift
sheetView.addSubview(sliderView)
sliderView.snp.makeConstraints { make in
    make.top.equalTo(titleLabel.snp.bottom).offset(Layout.sliderTop)
    make.left.equalToSuperview().offset(Layout.sliderHorizontalInset)
    make.right.equalToSuperview().offset(-Layout.sliderHorizontalInset)
    make.height.equalTo(Layout.sliderHeight)
    make.bottom.lessThanOrEqualToSuperview().offset(-Layout.sliderBottomInset)
}
sliderView.value = 50
sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
    guard ended else {
        return
    }
    self?.brightnessEndedAction?(value)
}
```

- [ ] **Step 4: 静态检查赋值位置**

Run:

```bash
rg -n "viewDidAppear|sliderView.value = 50|valueThrottleChangedCallback" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift
```

Expected:

```text
98:        sliderView.value = 50
99:        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
```

行号可因编辑略有变化，但必须满足：
- 不再出现 `viewDidAppear`。
- `sliderView.value = 50` 出现在 `valueThrottleChangedCallback` 前面。

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出包含：

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 6: 检查工作区只包含本任务相关改动**

Run:

```bash
git status --short
```

Expected: 至少包含本任务修改：

```text
 M SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift
```

当前工作区可能已有与本任务无关的用户改动，必须保留并不要加入本任务提交：

```text
 M SunSmart/Main/Space/Controller/SpaceViewController.swift
?? docs/260522_1004_space_permission_popup_analysis.md
?? docs/260522_1008_space_permission_popup_root_cause_and_fix_plan.md
```

- [ ] **Step 7: 提交实现**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchDimmingPopupController.swift
git commit -m "fix: initialize battery switch dimming slider"
```

Expected: 生成一个只包含 `PJEightKeySwitchDimmingPopupController.swift` 的提交。

