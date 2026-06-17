# Brightness Off Value Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 灯或组处于 Off 时，详细亮度滑条右上角 value label 显示 `0%`，On 时保持现有 trim clamp 展示逻辑。

**Architecture:** 只修改共享视图 `DeviceLightControlPanelView` 的亮度展示归一化。`brightnessValue == 0` 作为 Off 展示特例保留，非 0 值继续 clamp 到 `brightnessRange`；滑条 track 仍是 `0...100`，`limitRange` 仍负责灰色禁用区和交互限制。

**Tech Stack:** Swift、UIKit、现有 `BuoySliderView` / `CustomDeviceSlider`。

---

### Task 1: 亮度展示归一化

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift`
- Verify: source check、`git diff --check`、iPhoneOS workspace build

- [ ] **Step 1: RED/source check 确认当前缺少 Off 展示特例**

Run:

```bash
rg -n "normalizedBrightnessDisplayValue|guard value != 0 else" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: exit 1，说明当前没有允许 `0` 展示值穿透 low-end trim 的统一 helper。

- [ ] **Step 2: 添加亮度展示 helper**

在 `normalizedCCTInputValue` 附近添加：

```swift
private static func normalizedBrightnessDisplayValue(_ value: Int, range: ClosedRange<Int>) -> Int {
    guard value != 0 else { return 0 }
    return max(range.lowerBound, min(range.upperBound, value))
}
```

- [ ] **Step 3: 更新外部状态刷新入口**

把 `setBrightnessValue(_:)` 里的 brightness clamp 改为调用 helper：

```swift
let normalizedValue = Self.normalizedBrightnessDisplayValue(value, range: configuration.brightnessRange)
configuration.brightnessValue = normalizedValue
```

效果：设备页和组控页传入 Off 的 `0` 时，`configuration.brightnessValue` 保留为 `0`，`configureSliderValues` 的 `valueText` 输出 `0%`。

- [ ] **Step 4: 更新滑条交互后的本地展示缓存**

把 `updateStoredBrightness(_:)` 里的 brightness clamp 改为同一个 helper：

```swift
configuration.brightnessValue = Self.normalizedBrightnessDisplayValue(value, range: configuration.brightnessRange)
```

效果：交互值仍来自 `CustomDeviceSlider.limitRange`，正常情况下是 trim 范围内的值；如后续有 Off 入口直接刷新该方法，也能保持 `0%` 展示一致。

- [ ] **Step 5: GREEN/source check 确认 helper 和调用点存在**

Run:

```bash
rg -n "normalizedBrightnessDisplayValue" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: helper 定义 1 处，调用 2 处。

- [ ] **Step 6: 检查空白与 patch 质量**

Run:

```bash
git diff --check
```

Expected: no output，exit 0。

- [ ] **Step 7: iPhoneOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0，末尾包含 `BUILD SUCCEEDED`。

- [ ] **Step 8: 检查构建副作用**

Run:

```bash
git status --short
```

Expected: 只包含本任务相关 Swift 文件和 docs 文件；若 Xcode 生成或删除无关文件，恢复到构建前状态。
