# Battery/AC Power Switch Edit Panel Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagents for this plan.

**Goal:** 让独立 Edit Switch 页面只允许虚拟 Battery/AC power switch 修改 Panel 类型，真实设备保留 Panel 值但隐藏箭头且不能进入 Select Panel。

**Architecture:** 复用 `PJPreAddEightKeySwitchesVC` 现有的真实设备 LINK 判断作为唯一真值。在共享信息行中增加运行时箭头显隐和 value 右侧布局更新能力，再由 Edit Controller 同时控制 Panel 行交互与跳转 guard；现有 `bindViewModel()` 会在首次进入和 LINK 完成后统一刷新状态。

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

## Global Constraints

- 只调整独立 Edit Switch 页面；Group Power Switch 展开卡片保持现状。
- Virtual Battery/AC 显示 Panel 箭头，并在具备 edit 权限时允许进入 Select Panel。
- Real Battery/AC 显示当前 Panel 值，隐藏箭头，点击不跳转。
- Create Battery/AC power switch 页面继续允许选择 Panel。
- 复用现有 `isRealDeviceLinked` 判断，不新增 virtual/real 缓存或类型推测。
- UI 禁用和跳转 guard 必须同时存在。
- 不新增用户可见文案、Auth 信息、本地化、资源、target、依赖、协议、存储或 SDK 改动。
- 不顺手重构 Group、Scene、More Settings 或其他编辑逻辑。
- 构建校验必须直接使用 iPhoneOS `xcodebuild`，不得使用 Simulator 或 shell 包装。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`
  - 给既有 arrow/value-with-arrow 行增加运行时箭头显隐能力。
  - 当 value-with-arrow 隐藏箭头时，把 value 右侧约束从 36pt 语义调整为普通只读行的 16pt 语义；重新显示时恢复。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 定义 Panel 选择可用性，复用现有 `canEdit` 和 `isRealDeviceLinked`。
  - 在页面绑定/刷新时更新 Panel 行箭头与交互。
  - 在 Select Panel 跳转入口保留第二层保护。
- Inspect only: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
  - 确认 Group Power Switch 页面没有差异。
- No changes: ViewModel、Model、Repository、数据库、本地化资源、target 配置、依赖和 `NordicSigMeshSDK`。

---

### Task 1: 锁定真实 Battery/AC Power Switch 的 Panel 行

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift:65`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:228`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:415`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:493`
- Inspect: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

**Interfaces:**
- Consumes: `PJPreAddEightKeySwitchesVC.canEdit: Bool`、`PJPreAddEightKeySwitchesVC.isRealDeviceLinked: Bool`、`PJPreAddEightKeySwitchesVC.bindViewModel()` 的既有刷新链路。
- Produces: `PJEightKeySwitchInfoRowView.setShowsArrow(_ showsArrow: Bool)`；`PJPreAddEightKeySwitchesVC.allowsPanelSelection: Bool`。

- [ ] **Step 1: 运行改动前的回归基线检查**

Run:

```bash
rg -n "func setShowsArrow|allowsPanelSelection|guard ensureEditable\(\), allowsPanelSelection|panelRowView\.setShowsArrow" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 命令退出码为 1 且没有匹配，证明当前版本尚未提供动态箭头和真实设备 Panel 跳转保护。

再运行：

```bash
rg -n "panelRowView\.isUserInteractionEnabled = canEdit|private var isRealDeviceLinked|private func selectPanelAction" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 三处均有匹配，确认问题基线为“Panel 行只受 `canEdit` 控制，已有真实设备判断但未用于 Panel 行”。

- [ ] **Step 2: 为共享信息行增加动态箭头能力**

在 `PJEightKeySwitchInfoRowView.setValue(_:)` 后增加：

```swift
func setShowsArrow(_ showsArrow: Bool) {
    switch accessoryStyle {
    case .arrow:
        arrowImageView.isHidden = !showsArrow
    case .valueWithArrow:
        arrowImageView.isHidden = !showsArrow
        valueLabel.snp.updateConstraints { make in
            make.right.equalTo(SCRXFrom(showsArrow ? -36 : -16))
        }
    case .none, .toggle:
        break
    }
}
```

Expected:

- `.valueWithArrow` 隐藏箭头时，value 右边距与 `.none` 行一致。
- 重新显示箭头时恢复原有 36pt 右边距。
- `.none` 和 `.toggle` 不受影响。
- `.arrow` 仅切换箭头本身，不改变既有手势。

- [ ] **Step 3: 定义 Panel 选择可用性**

在 `canEdit` 后、`canDelete` 前增加：

```swift
private var allowsPanelSelection: Bool {
    canEdit && !isRealDeviceLinked
}
```

Expected:

- Virtual + 可编辑：`true`。
- Virtual + 无 edit 权限：`false`。
- Real Battery/AC：始终为 `false`。
- Create 模式没有真实设备 LINK，在现有可编辑条件下为 `true`。

- [ ] **Step 4: 给 Select Panel 跳转增加第二层保护**

将 `selectPanelAction()` 开头：

```swift
guard ensureEditable() else { return }
```

替换为：

```swift
guard ensureEditable(), allowsPanelSelection else { return }
```

Expected: 即使未来 Panel 行手势被错误触发，真实 Battery/AC power switch 也不会创建或 push `PJEightKeySwitchSelectPanelController`；无 edit 权限时仍先由 `ensureEditable()` 保留现有权限提示语义。

- [ ] **Step 5: 在统一页面绑定链路中更新 Panel 行状态**

将 `applyEditableState()` 中：

```swift
editorView.panelRowView.isUserInteractionEnabled = canEdit
```

替换为：

```swift
editorView.panelRowView.setShowsArrow(!isRealDeviceLinked)
editorView.panelRowView.isUserInteractionEnabled = allowsPanelSelection
```

保留其他行的现有赋值不变：

```swift
editorView.groupRowView.isUserInteractionEnabled = canEdit
editorView.sceneRowView.isUserInteractionEnabled = canEdit
editorView.moreSettingsRowView.isUserInteractionEnabled = canEdit
```

Expected:

- `bindViewModel()` 首次调用 `applyEditableState()` 时呈现正确状态。
- `refreshEditingStateFromCurrentSwitchData()` 在 LINK 完成后重新调用 `bindViewModel()`，Panel 行随最新真实设备状态切换。
- Group、Scene、More Settings 不改变。

- [ ] **Step 6: 运行定向源码回归检查**

Run:

```bash
rg -n "func setShowsArrow|allowsPanelSelection|guard ensureEditable\(\), allowsPanelSelection|panelRowView\.setShowsArrow\(!isRealDeviceLinked\)|panelRowView\.isUserInteractionEnabled = allowsPanelSelection" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 五类新逻辑均有匹配。

Run:

```bash
rg -n "panelRowView\.isUserInteractionEnabled = canEdit" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 命令退出码为 1 且没有匹配。

Run:

```bash
git diff -- SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj Podfile
```

Expected: 没有输出，确认 Group 页面、ViewModel、Model、本地化、target 与依赖均未修改。

- [ ] **Step 7: 检查最终 diff 和格式**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 只包含动态箭头、Panel 选择谓词、跳转 guard 和 Panel 行状态绑定；没有其他重构。

Run:

```bash
git diff --check
```

Expected: 没有输出。

- [ ] **Step 8: 执行 iPhoneOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 9: 完成行为验收记录**

在可用测试数据或真机环境中核对：

1. Virtual Battery Edit：Panel 显示箭头，可进入 Select Panel 并更新值和预览。
2. Virtual AC Edit：Panel 显示箭头，可进入 Select Panel 并更新值和预览。
3. Real Battery Edit：Panel 显示值、无箭头、点击无跳转。
4. Real AC Edit：Panel 显示值、无箭头、点击无跳转。
5. Virtual Battery/AC 完成 LINK 返回 Edit：Panel 立即切换为无箭头且不可点击。
6. Create Battery/AC：Panel 选择保持可用。
7. Group Power Switch 展开卡片行为保持现状。

Expected: 有对应环境的用例全部符合；若当前缺少真实设备或测试数据，应在实施总结中明确标记未进行的运行时用例，不能用编译成功替代行为验证。

- [ ] **Step 10: 提交聚焦改动**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: lock real power switch panel selection"
```

Expected: 提交只包含两个目标 Swift 文件；设计文档和计划文档已在各自文档提交中管理，现有无关未跟踪文件不进入提交。

---

## Plan Self-Review

- Spec coverage: Task 1 Steps 3–5 覆盖 virtual/real、权限、双层保护和 LINK 后刷新；Step 6 锁定 Group 页面和其他模块非目标；Step 9 覆盖全部验收矩阵。
- Completeness: 每个修改步骤都给出精确文件、现有上下文、目标实现和预期结果。
- Type consistency: `setShowsArrow(_:)` 的调用名称与定义一致；`allowsPanelSelection` 同时用于跳转保护和 UI 交互；箭头视觉继续直接使用 `isRealDeviceLinked`，符合“真实设备隐藏箭头”的设计。
- Scope: 业务改动仅涉及两个 Swift 文件，不新增 ViewModel、Model、Repository、数据库、本地化、target、依赖或 SDK 改动。
- Verification: 包含改动前基线、改动后源码断言、非目标 diff 检查、`git diff --check`、iPhoneOS build 和运行时验收记录。
