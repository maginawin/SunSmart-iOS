# Scene Settings Group CCT Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `Scene Settings` 页面长按 Group 时，按 `group.effectiveSupportCct` 展示“亮度 + 色温”或“仅亮度”弹窗。

**Architecture:** 复用现有 `SceneExecuteDataPickerView`，增加一个默认开启的 `showCct` 配置，避免影响 Scene 创建页等已有调用。`SceneSettingsViewController` 在打开弹窗时传入 `group.effectiveSupportCct`，不改动 `ExecuteSceneData` 数据结构和现有同步/预览消息逻辑。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode workspace 构建。

---

## 文件结构

- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`
  - 负责场景参数弹窗 UI。
  - 新增 `showCct` 配置。
  - 仅亮度模式下不创建 CCT label/slider，并缩小内容高度。
  - 回调仍返回 `(lightness, cct)`。
- Modify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
  - 负责 Scene Settings 页面 Group 长按后的弹窗调用。
  - 打开弹窗时传入 `showCct: group.effectiveSupportCct`。
- No change: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`
  - 继续使用默认 `showCct == true`，保持现有 Scene 创建页行为。

## Task 1: 扩展 SceneExecuteDataPickerView 支持仅亮度模式

**Files:**
- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`

- [ ] **Step 1: 记录当前缺口**

Run:

```bash
rg -n "showCct|selectedCct|make.height.equalTo\\(SCRYFrom\\(220\\)\\)" SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected:

- 找不到 `showCct`。
- 找不到 `selectedCct`。
- 可以看到内容高度固定为 `SCRYFrom(220)`。

- [ ] **Step 2: 增加 showCct 状态与 show(...) 参数**

在 `SceneExecuteDataPickerView` 的属性区增加：

```swift
private var showCct: Bool = true
```

把 `show(...)` 方法签名改为：

```swift
static func show(
    lightness: Int = 100,
    cct: Int = 4500,
    lightnessLimitRange: ClosedRange<Int>? = nil,
    cctRange: ClosedRange<UInt16> = NodeAbsoluteCctRange.defaultRange,
    showCct: Bool = true,
    showDelete: Bool = true,
    picker: DataPickerCallback?,
    delete: DeleteCallback? = nil
) {
```

在创建 `pickerView` 后设置：

```swift
pickerView.showCct = showCct
```

保持已有调用兼容：`showCct` 必须有默认值 `true`，并且 `picker` 和 `delete` 的回调签名不变。

- [ ] **Step 3: 新增 CCT 回调值 helper**

在 `deleteBtnAction()` 之前增加 helper：

```swift
private var selectedCct: Int {
    if showCct {
        return cctSliderView.value
    }
    return min(Int(cctRange.upperBound), max(Int(cctRange.lowerBound), cct))
}
```

把 `confirmBtnAction()` 中的 CCT 读取改为：

```swift
let cct = selectedCct
```

把 `shadeViewAction()` 中的 CCT 读取也改为：

```swift
let cct = selectedCct
```

这样仅亮度模式不会访问未创建的 `cctSliderView`。

- [ ] **Step 4: 根据 showCct 调整弹窗高度**

在 `contentView.snp.makeConstraints` 之前增加：

```swift
let contentHeight = showCct ? SCRYFrom(220) : SCRYFrom(120)
```

把原来的固定高度：

```swift
make.height.equalTo(SCRYFrom(220))
```

改为：

```swift
make.height.equalTo(contentHeight)
```

`SCRYFrom(120)` 保留顶部 24、亮度 label、14 间距和 40 高度 slider，并给底部留出余量。

- [ ] **Step 5: 仅在 showCct 为 true 时创建 CCT 控件**

在亮度 slider 约束完成后、创建 `cctValue` 之前增加：

```swift
guard showCct else {
    return
}
```

保留现有 CCT label 与 CCT slider 创建代码不变，让支持 CCT 的弹窗保持当前样式。

- [ ] **Step 6: 静态检查弹窗代码**

Run:

```bash
rg -n "showCct|selectedCct|contentHeight|guard showCct" SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected:

- `showCct` 属性存在。
- `show(...)` 方法参数包含 `showCct: Bool = true`。
- `selectedCct` 存在。
- `contentHeight` 存在。
- `guard showCct else` 存在。

- [ ] **Step 7: 编译检查当前任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 8: Commit**

Run:

```bash
git add SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
git commit -m "feat: support brightness-only scene picker"
```

Expected:

- 生成一个只包含 `SceneExecuteDataPickerView.swift` 的提交。

## Task 2: Scene Settings 按 Group CCT 能力打开对应弹窗

**Files:**
- Modify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`

- [ ] **Step 1: 记录当前调用缺口**

Run:

```bash
rg -n "SceneExecuteDataPickerView\\.show|showCct" SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift
```

Expected:

- 可以看到 `SceneExecuteDataPickerView.show(...)` 调用。
- 当前调用中没有 `showCct:`。

- [ ] **Step 2: 修改 Scene Settings 弹窗调用**

在 `updateGroupSceneExecuteData(group:)` 中，把 `SceneExecuteDataPickerView.show(...)` 调用改为包含：

```swift
showCct: group.effectiveSupportCct,
showDelete: false
```

目标调用结构为：

```swift
SceneExecuteDataPickerView.show(
    lightness: data?.lightness ?? 100,
    cct: data?.cct ?? 4500,
    lightnessLimitRange: groupLightData.lowEndTrim...groupLightData.highEndTrim,
    cctRange: group.effectiveCctRange,
    showCct: group.effectiveSupportCct,
    showDelete: false
) { [weak self] lightness, cct in
```

回调内部保持现有逻辑不变：

```swift
let cct = Int(group.clampEffectiveCct(UInt16(cct)))
if let sceneData = data {
    sceneData.lightness = lightness
    sceneData.cct = cct
} else {
    group.executeSceneData = ExecuteSceneData(lightness: lightness, cct: cct)
}
```

- [ ] **Step 3: 静态检查 Scene Settings 调用点**

Run:

```bash
rg -n "showCct: group\\.effectiveSupportCct|showDelete: false" SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift
```

Expected:

- `showCct: group.effectiveSupportCct` 存在。
- `showDelete: false` 仍存在。

- [ ] **Step 4: 确认 Scene 创建页保持默认 CCT 行为**

Run:

```bash
rg -n "SceneExecuteDataPickerView\\.show" SunSmart/Main/Scene/Controller/SceneAddViewController.swift
```

Expected:

- Scene 创建页调用点不需要新增 `showCct:`。
- 由于 `showCct` 默认值为 `true`，创建页仍展示亮度和色温。

- [ ] **Step 5: 编译检查当前任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: Commit**

Run:

```bash
git add SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift
git commit -m "fix: adapt scene settings picker to group cct support"
```

Expected:

- 生成一个只包含 `SceneSettingsViewController.swift` 的提交。

## Task 3: 最终验证

**Files:**
- Verify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`
- Verify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- Verify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`

- [ ] **Step 1: 检查所有弹窗调用点**

Run:

```bash
rg -n "SceneExecuteDataPickerView\\.show|showCct:" SunSmart/Main/Scene
```

Expected:

- `SceneSettingsViewController.swift` 的调用包含 `showCct: group.effectiveSupportCct`。
- `SceneAddViewController.swift` 的调用不包含 `showCct:`，走默认 `true`。
- `SceneExecuteDataPickerView.swift` 的方法签名包含 `showCct: Bool = true`。

- [ ] **Step 2: 检查仅亮度模式不会访问 CCT slider**

Run:

```bash
rg -n "cctSliderView\\.value|selectedCct|guard showCct" SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected:

- `confirmBtnAction()` 和 `shadeViewAction()` 使用 `selectedCct`。
- `cctSliderView.value` 只出现在 `selectedCct` 中。
- CCT 控件创建前存在 `guard showCct else { return }`。

- [ ] **Step 3: 最终 iOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 检查工作区状态**

Run:

```bash
git status --short
```

Expected:

- 只剩用户已有的无关改动，或工作区干净。
- 如果出现本计划产生的未提交改动，先确认是否属于 Task 1 或 Task 2，再提交或说明原因。

## 手动验证建议

- 在 `Site - Space - Scene` 中长按 Scene，进入 Scene 页面。
- 点击右上角 Settings，进入 `Scene Settings`。
- 长按支持 CCT 的 Group：弹窗显示亮度和色温。
- 长按不支持 CCT 的 Group：弹窗只显示亮度。
- 对不支持 CCT 的 Group 修改亮度后确认，Group 被选中且亮度展示更新。
- 点击 Preview 时，支持 CCT 的 Group 仍发送 CTL 控制；不支持 CCT 的 Group 只走亮度控制。

## Self-Review

- Spec coverage: 已覆盖 `Scene Settings` 长按 Group、按 `group.effectiveSupportCct` 展示、仅亮度弹窗、保持 Scene 创建页不变、保留数据结构与同步/预览逻辑。
- Placeholder scan: 计划中没有空泛内容或未定义的步骤。
- Type consistency: 使用的类型和属性来自现有代码：`SceneExecuteDataPickerView`、`SceneSettingsViewController`、`Group.effectiveSupportCct`、`ExecuteSceneData`、`DeviceSliderFunctionView`。
