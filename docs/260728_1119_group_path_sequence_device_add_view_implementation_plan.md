# GroupPathSequenceDeviceAddView 固定布局实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 `superpowers:executing-plans` 进行 Inline Execution，按任务逐项执行并在阶段间检查。步骤使用 checkbox 跟踪。

**Goal:** 将 `GroupPathSequenceDeviceAddView` 改为默认 closed、精确固定布局、可配置内容高度策略，并全面移除约定范围内 selected 内容的 `SCRXFrom`、`SCRYFrom`。

**Architecture:** 公共 View 统一管理 closed/open、外壳约束、safe area 和高度回调，通过显式 `ContentHeightPolicy` 区分 Group 固定基础高度与 Space 动态 selected 高度。默认提示通过公共步骤 View 的可配置等宽布局实现，不影响其他调用页面；业务数据继续由各 Controller 持有。

**Tech Stack:** Swift、UIKit、SnapKit、WMMenuView、独立 `swiftc` 源码契约测试、Xcode generic iPhoneOS 构建。

## Global Constraints

- 设计依据：`docs/260728_1115_group_path_sequence_device_add_view_design.md`。
- 所有回复、计划和总结使用简体中文；本任务不新增用户可见文案。
- closed：标题行 44，向上箭头，整体高度 `44 + safeAreaInsets.bottom`。
- open：标题行 44、菜单 44、卡片顶部 8、基础卡片 160、卡片底部 8。
- Group open 基础高度为 `264 + safeAreaInsets.bottom`。
- Manually Add 多行使用 160 与实际内容高度中的较大值。
- 初始 closed；选中 Path/Zone 后自动 open。
- Space Trigger Zone 继续隐藏，不修改 `SpaceMoreViewController`。
- Space 继续直接组合公共 View，不新增 View 子类或 Controller 继承。
- 五个目标文件最终不得包含 `SCRXFrom`、`SCRYFrom`，包括注释：
  - `GroupPathSequenceDeviceAddView.swift`
  - `GroupPathSequenceQuickAddView.swift`
  - `GroupPathSequenceTriggerAddView.swift`
  - `GroupPathSequenceManuallyAddView.swift`
  - `GroupPathSequenceAddDeviceCell.swift`
- `GroupPathSequenceDeviceAddStepView` 的旧默认布局必须保持；只有本添加组件启用固定三列等宽布局。
- selected 状态只做固定 point 改造，不主动重新设计过滤器、按钮、设备 Cell、分页或操作流程。
- 不修改本地化、资源、依赖或 target membership。
- 不新增 Auth 信息。
- 保留用户现有改动，不格式化或重构无关文件。
- 未经用户明确授权，不执行 `git add`、`git commit`、merge、push 或 PR 操作。
- iOS 验证直接运行 `xcodebuild`，使用 generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO`；不使用 Simulator、shell 包装或日志重定向。
- 四个品牌 scheme 均需构建：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

---

## 文件职责

### 新增

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
  - 以源码契约覆盖状态、精确尺寸、高度策略、等宽提示、缩放清理和 Space 入口保持隐藏。

### 修改

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
  - 统一 closed/open、固定外壳约束、内容高度策略和高度计算。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
  - 提供默认 legacy 与本组件使用的 equalColumns 两种布局。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
  - 启用等宽提示布局并移除 selected 内容横纵向缩放。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
  - 启用等宽提示布局并移除 selected 内容横纵向缩放。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
  - 启用等宽提示布局并移除 selected 内容横纵向缩放，保留多行首选高度。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
  - 移除专用设备 Cell 的横纵向缩放。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
  - 显式选择 fixedBase 策略，并把添加 View 最小高度钳制值改为固定 44。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
  - 显式选择 fixedBase 策略，并把添加 View 最小高度钳制值改为固定 44。
- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
  - 显式选择 dynamicSelected 策略，并把添加 View 最小高度钳制值改为固定 44。

### 明确不修改

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`
- `Podfile`
- Swift Package 配置

---

### Task 1：为公共 View 建立状态、固定布局和高度策略

**Files:**

- Create: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- Modify: `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
- Inspect only: `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`

**Interfaces:**

- Produces: `GroupPathSequenceDeviceAddView.ContentHeightPolicy`
  - `.fixedBase`
  - `.dynamicSelected`
- Produces: `var contentHeightPolicy: ContentHeightPolicy`
- Preserves: `func setCollapsed(_ collapsed: Bool, animated: Bool = false)`
- Preserves: `var heightChanged: ((CGFloat) -> Void)?`
- Preserves: 所有现有 delegate 方法。

- [ ] **Step 1：写入第一阶段失败契约测试**

创建 `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`，先覆盖公共 View 与调用方策略：

```swift
import Foundation

@main
struct GroupPathSequenceDeviceAddViewContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let addView = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift")
        let sequenceController = try source(root, "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift")
        let zoneController = try source(root, "SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift")
        let spaceController = try source(root, "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift")
        let spaceMore = try source(root, "SunSmart/Main/Space/Controller/SpaceMoreViewController.swift")

        require(addView.contains("enum ContentHeightPolicy"), "Missing content height policy")
        require(addView.contains("case fixedBase"), "Missing Group fixed-base policy")
        require(addView.contains("case dynamicSelected"), "Missing Space dynamic-selected policy")
        require(addView.contains("private var collapsed: Bool = true"), "View must initialize closed")
        require(addView.contains("static let headerHeight: CGFloat = 44"), "Header height must be 44")
        require(addView.contains("static let addTypeBarHeight: CGFloat = 44"), "Menu height must be 44")
        require(addView.contains("static let contentCardTopSpacing: CGFloat = 8"), "Card top spacing must be 8")
        require(addView.contains("static let contentCardBottomSpacing: CGFloat = 8"), "Card bottom spacing must be 8")
        require(addView.contains("static let contentCardHorizontalInset: CGFloat = 16"), "Card horizontal inset must be 16")
        require(addView.contains("static let baseContentHeight: CGFloat = 160"), "Base content height must be 160")
        require(addView.contains("self.collapsed ? \"arrow_up_black\" : \"arrow_down_black\""),
                "Arrow mapping must be closed-up/open-down")
        require(addView.contains("max(LayoutMetrics.baseContentHeight, manuallyAddView.preferredContentHeight)"),
                "Manual multi-row content must grow above 160")
        require(addView.contains("LayoutMetrics.headerHeight + bodyHeight + safeAreaInsets.bottom"),
                "Expanded height must include header, body and safe area")
        require(!addView.contains("SCRXFrom"), "Parent add view must not retain SCRXFrom")
        require(!addView.contains("SCRYFrom"), "Parent add view must not retain SCRYFrom")

        require(sequenceController.contains("deviceAddView.contentHeightPolicy = .fixedBase"),
                "Sequence controller must select fixedBase")
        require(zoneController.contains("deviceAddView.contentHeightPolicy = .fixedBase"),
                "Group zone controller must select fixedBase")
        require(spaceController.contains("deviceAddView.contentHeightPolicy = .dynamicSelected"),
                "Space controller must select dynamicSelected")

        require(sequenceController.contains("max(height, 44)"),
                "Sequence controller must clamp to fixed 44")
        require(zoneController.contains("max(height, 44)"),
                "Group zone controller must clamp to fixed 44")
        require(spaceController.contains("max(height, 44)"),
                "Space controller must clamp to fixed 44")

        let makeOptions = section(in: spaceMore,
                                  from: "private func makeOptions()",
                                  to: "private func reloadOptions()")
        require(!makeOptions.contains(".triggerZone"),
                "Space Trigger Zone must remain hidden")

        print("GroupPathSequenceDeviceAddViewContractTests layout passed")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(root)/\(relativePath)", encoding: .utf8)
    }

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start) else {
            fatalError("Missing source marker: \(start)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: end) else {
            fatalError("Missing source marker: \(end)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
```

- [ ] **Step 2：运行契约测试并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected:

- 编译成功。
- 运行失败，首个错误为缺少 `ContentHeightPolicy`、默认 closed、固定布局常量或固定策略配置之一。
- 失败发生在契约断言，不是文件路径错误。

- [ ] **Step 3：在公共 View 中定义固定布局指标和高度策略**

在 `GroupPathSequenceDeviceAddView` 内定义：

```swift
enum ContentHeightPolicy {
    case fixedBase
    case dynamicSelected
}

private enum LayoutMetrics {
    static let headerHeight: CGFloat = 44
    static let addTypeBarHeight: CGFloat = 44
    static let contentCardTopSpacing: CGFloat = 8
    static let contentCardBottomSpacing: CGFloat = 8
    static let contentCardHorizontalInset: CGFloat = 16
    static let baseContentHeight: CGFloat = 160
    static let cornerRadius: CGFloat = 15
    static let contentCornerRadius: CGFloat = 10
}

var contentHeightPolicy: ContentHeightPolicy = .fixedBase {
    didSet {
        refreshPreferredHeight()
    }
}
```

同时：

- 把 `collapsed` 初始值改为 `true`。
- 用以下两个约束属性替换 `contentCardMinHeightConstraint`：

```swift
private var bodyHeightConstraint: NSLayoutConstraint?
private var contentCardHeightConstraint: NSLayoutConstraint?
```

- 删除 `containerTopInset`、`containerBottomInset`、`headerBodySpacing` 等旧缩放常量。
- 删除 `containerStackView` 和 `updateContainerBottomInset()`。
- 删除 `minimumContentHeight`、`updateContentMinimumHeight()` 和旧的 `greaterThanOrEqualTo` 内容高度约束。
- 删除父 View 中全部 `SCRXFrom`、`SCRYFrom`，包括注释。

- [ ] **Step 4：改为标题、body、菜单和卡片的直接约束**

父 View 使用以下固定约束关系：

```swift
headerView.snp.makeConstraints { make in
    make.top.left.right.equalToSuperview()
    make.height.equalTo(LayoutMetrics.headerHeight)
}

bodyContainerView.snp.makeConstraints { make in
    make.top.equalTo(headerView.snp.bottom)
    make.left.right.equalToSuperview()
}

let initialBodyHeight = LayoutMetrics.addTypeBarHeight
    + LayoutMetrics.contentCardTopSpacing
    + LayoutMetrics.baseContentHeight
    + LayoutMetrics.contentCardBottomSpacing
bodyHeightConstraint = bodyContainerView.heightAnchor.constraint(
    equalToConstant: initialBodyHeight
)
bodyHeightConstraint?.isActive = true

addTypeBar.snp.makeConstraints { make in
    make.top.left.right.equalToSuperview()
    make.height.equalTo(LayoutMetrics.addTypeBarHeight)
}

contentCardView.snp.makeConstraints { make in
    make.top.equalTo(addTypeBar.snp.bottom).offset(LayoutMetrics.contentCardTopSpacing)
    make.left.right.equalToSuperview().inset(LayoutMetrics.contentCardHorizontalInset)
    make.bottom.equalToSuperview().inset(LayoutMetrics.contentCardBottomSpacing)
}

contentCardHeightConstraint = contentCardView.heightAnchor.constraint(
    equalToConstant: LayoutMetrics.baseContentHeight
)
contentCardHeightConstraint?.isActive = true
```

`bodyHeightConstraint` 和 `contentCardHeightConstraint` 均为 `NSLayoutConstraint?`，不要把 `NSLayoutConstraint` 传给 SnapKit 的 `equalTo`。

约束结果必须满足：

- body 高度 = `44 + 8 + contentHeight + 8`。
- closed 时 body 只隐藏，不需要靠父 Stack 折叠。
- 父 View 的外部高度约束负责把 closed 总高度设为 `44 + safe area`。

- [ ] **Step 5：统一内容高度和整体高度计算**

新增并统一使用以下逻辑：

```swift
private func resolvedContentHeight() -> CGFloat {
    switch contentHeightPolicy {
    case .fixedBase:
        if currentMode == .manuallyAdd, manuallyAddView.guideContentView.isHidden {
            return max(LayoutMetrics.baseContentHeight, manuallyAddView.preferredContentHeight)
        }
        return LayoutMetrics.baseContentHeight
    case .dynamicSelected:
        return max(LayoutMetrics.baseContentHeight, visibleContentHeight())
    }
}

private func updateContentHeightConstraints() -> CGFloat {
    let contentHeight = resolvedContentHeight()
    let bodyHeight = LayoutMetrics.addTypeBarHeight
        + LayoutMetrics.contentCardTopSpacing
        + contentHeight
        + LayoutMetrics.contentCardBottomSpacing
    contentCardHeightConstraint?.constant = contentHeight
    bodyHeightConstraint?.constant = bodyHeight
    return bodyHeight
}
```

`emitPreferredHeightIfNeeded()` 使用：

```swift
let height: CGFloat
if isHidden {
    height = 0
} else if collapsed {
    height = LayoutMetrics.headerHeight + safeAreaInsets.bottom
} else {
    let bodyHeight = updateContentHeightConstraints()
    height = LayoutMetrics.headerHeight + bodyHeight + safeAreaInsets.bottom
}
```

保留现有 0.5 point 去重容差。

`safeAreaInsetsDidChange()` 只在 bottom inset 实际变化时调用 `refreshPreferredHeight()`；不再更新旧 Stack bottom inset。

- [ ] **Step 6：反转箭头映射并保持附件按钮行为**

`updateCollapseUI(animated:)` 使用：

```swift
let imageName = self.collapsed ? "arrow_up_black" : "arrow_down_black"
```

继续：

- closed 时隐藏 body、refresh 和 unfold。
- open 时恢复 body。
- refresh/unfold 的显示仍由 `updateAccessoryButtons()` 根据模式和数据决定。
- 不在 closed/open 切换中重置添加模式或业务状态。

- [ ] **Step 7：三个 Controller 显式选择高度策略**

在创建 `deviceAddView` 后、注册 `heightChanged` 前设置：

```swift
deviceAddView.contentHeightPolicy = .fixedBase
```

应用于：

- `GroupPathSequenceViewController`
- `GroupPathSequenceTriggerZoneController`

Space 使用：

```swift
deviceAddView.contentHeightPolicy = .dynamicSelected
```

同时把三个 Controller 中：

```swift
max(height, SCRYFrom(44))
```

改为：

```swift
max(height, 44)
```

不要修改 `SpaceMoreViewController`。

- [ ] **Step 8：运行第一阶段契约测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected:

```text
GroupPathSequenceDeviceAddViewContractTests layout passed
```

- [ ] **Step 9：阶段检查**

检查：

- 父 View 中无 `SCRXFrom`、`SCRYFrom`。
- `SpaceMoreViewController` 无修改。
- Controller 仍只在选中 Path/Zone 后调用 `setCollapsed(false, ...)`。
- 无 Path/Zone 的隐藏逻辑未改变。

本阶段不执行 Git 提交。

---

### Task 2：为默认提示增加三列等宽布局

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`

**Interfaces:**

- Produces: `GroupPathSequenceDeviceAddStepView.LayoutStyle`
  - `.legacy`
  - `.equalColumns`
- Produces initializer parameter: `layoutStyle: LayoutStyle = .legacy`
- Preserves initializer compatibility for all existing callers.

- [ ] **Step 1：扩展契约测试并确认等宽布局 RED**

在测试中读取四个文件：

```swift
let stepView = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift")
let quickAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift")
let triggerAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift")
let manuallyAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift")
```

增加断言：

```swift
require(stepView.contains("enum LayoutStyle"), "Missing step layout style")
require(stepView.contains("case legacy"), "Missing legacy step layout")
require(stepView.contains("case equalColumns"), "Missing equal-column step layout")
require(stepView.contains("layoutStyle: LayoutStyle = .legacy"),
        "Existing callers must default to legacy")
require(stepView.contains("stackView.distribution = .fillEqually"),
        "Equal columns must use fillEqually")
require(stepView.contains("stackView.spacing = 16"),
        "Equal columns must use 16 spacing")
require(stepView.contains("make.left.right.equalToSuperview().inset(16)"),
        "Equal columns must use 16 outer insets")
require(stepView.contains("constrainsWidth: layoutStyle == .legacy"),
        "Equal columns must disable legacy item width caps")

for contentView in [quickAdd, triggerAdd, manuallyAdd] {
    require(contentView.contains("layoutStyle: .equalColumns"),
            "Each add mode guide must enable equal columns")
    require(contentView.contains("make.left.right.equalToSuperview()"),
            "Guide view must fill card width before applying 16-point column insets")
}
```

把成功输出改为：

```text
GroupPathSequenceDeviceAddViewContractTests layout and guide passed
```

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected: FAIL，首个错误为缺少 `LayoutStyle` 或 `.equalColumns`。

- [ ] **Step 2：给公共步骤 View 增加兼容的布局样式**

定义：

```swift
enum LayoutStyle {
    case legacy
    case equalColumns
}

private let layoutStyle: LayoutStyle

init(
    frame: CGRect = .zero,
    steps: [StepItem],
    layoutStyle: LayoutStyle = .legacy
) {
    self.layoutStyle = layoutStyle
    super.init(frame: frame)
    self.steps = steps
    setupUI()
}
```

配置 Stack：

```swift
stackView.axis = .horizontal
stackView.alignment = .top

switch layoutStyle {
case .legacy:
    stackView.distribution = .fill
    stackView.spacing = isIPad ? SCRXFrom(30) : SCRXFrom(20)
case .equalColumns:
    stackView.distribution = .fillEqually
    stackView.spacing = 16
}
```

约束分支：

```swift
switch layoutStyle {
case .legacy:
    stackView.snp.makeConstraints { make in
        make.centerX.centerY.equalToSuperview()
        make.left.greaterThanOrEqualTo(SCRXFrom(10))
        make.right.lessThanOrEqualTo(SCRXFrom(-10))
        make.width.lessThanOrEqualTo(isIPad ? SCRXFrom(600) : SCRXFrom(320))
        make.top.greaterThanOrEqualToSuperview()
        make.bottom.lessThanOrEqualToSuperview()
    }
case .equalColumns:
    stackView.snp.makeConstraints { make in
        make.left.right.equalToSuperview().inset(16)
        make.centerY.equalToSuperview()
        make.top.greaterThanOrEqualToSuperview()
        make.bottom.lessThanOrEqualToSuperview()
    }
}
```

- [ ] **Step 3：解除 equalColumns 下的旧单项宽度限制**

`StepFunctionView` 初始化器增加：

```swift
init(
    imageName: String,
    title: String,
    titleColor: UIColor,
    constrainsWidth: Bool
)
```

仅 legacy 添加旧最小/最大宽度约束：

```swift
if constrainsWidth {
    snp.makeConstraints { make in
        make.width.greaterThanOrEqualTo(minWidth)
        make.width.lessThanOrEqualTo(maxWidth).priority(.required)
    }
}
```

创建步骤项时传入：

```swift
constrainsWidth: layoutStyle == .legacy
```

equalColumns 使用固定值：

- 图标 20 × 20。
- 图标到文字 8。
- 三列间距 16。
- 左右外边距 16。

legacy 的 `SCRXFrom`、`SCRYFrom` 保留，因为其他页面仍依赖旧默认布局。

- [ ] **Step 4：三个添加模式启用 equalColumns**

Quick、Trigger、Manually 创建 `guideView` 时增加：

```swift
layoutStyle: .equalColumns
```

三个文件中 `guideView` 本身改为填满 `guideContentView` 的水平宽度：

```swift
guideView.snp.makeConstraints { make in
    make.left.right.equalToSuperview()
    make.top.equalTo(12)
    make.bottom.equalTo(-12)
}
```

这样等宽 Stack 的左右 16 直接相对于内容卡片生效，最终每列宽度严格为：

```text
(addingContentView.width - 16 - 16 - 16 - 16) / 3
```

保持各自 `steps` 文案和 Controller 后续覆盖 `steps` 的行为不变。

- [ ] **Step 5：运行第二阶段契约测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected:

```text
GroupPathSequenceDeviceAddViewContractTests layout and guide passed
```

- [ ] **Step 6：阶段检查**

确认：

- 第二列由 `.fillEqually` 和左右/列间 16 自然居中。
- equalColumns 不受 `StepFunctionView` 旧 maxWidth 限制。
- Profile、说明页、重置页未传 `layoutStyle`，继续使用 `.legacy`。
- 没有修改步骤文案和本地化。

本阶段不执行 Git 提交。

---

### Task 3：全面清理 selected 内容横纵向缩放

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
- Verify: `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`

**Interfaces:**

- Preserves: 三个 Add View 的公开属性、delegate、配置方法和 `preferredContentHeight`。
- Preserves: `GroupPathSequenceAddDeviceCell.iconImageView`、`nameLabel`。
- Produces: 五个目标文件中零 `SCRXFrom`、零 `SCRYFrom`。

- [ ] **Step 1：扩展缩放清理契约并确认 RED**

测试读取 Cell：

```swift
let addDeviceCell = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift")
```

增加：

```swift
let fixedPointSources: [(String, String)] = [
    ("GroupPathSequenceDeviceAddView", addView),
    ("GroupPathSequenceQuickAddView", quickAdd),
    ("GroupPathSequenceTriggerAddView", triggerAdd),
    ("GroupPathSequenceManuallyAddView", manuallyAdd),
    ("GroupPathSequenceAddDeviceCell", addDeviceCell)
]

for (name, source) in fixedPointSources {
    require(!source.contains("SCRXFrom"), "\(name) must not contain SCRXFrom")
    require(!source.contains("SCRYFrom"), "\(name) must not contain SCRYFrom")
}
```

把成功输出改为：

```text
GroupPathSequenceDeviceAddViewContractTests passed
```

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected: FAIL，首个错误指向 Quick、Trigger、Manually 或 Cell 中仍存在的缩放调用。

- [ ] **Step 2：机械替换固定 point，不改变 selected 结构**

在四个尚未清理的目标文件中执行等值替换，规则为：

```swift
SCRXFrom(value)  -> value
SCRYFrom(value)  -> value
SCRXFrom(-value) -> -value
SCRYFrom(-value) -> -value
```

组合表达式保留可读形式：

```swift
SCRYFrom(30 + 16 + 38) -> 30 + 16 + 38
SCREEN_WIDTH - SCRXFrom(48) -> SCREEN_WIDTH - 48
UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(4), bottom: SCRYFrom(4), right: SCRXFrom(4))
-> UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
```

具体范围包括：

- `topContentInset`。
- guide 首选高度的 fallback/inset。
- Quick Add start/stop 水平偏移。
- TitleSelectView 的菜单宽度、行高、圆角和 row inset。
- group filter、add type filter 的宽高和边距。
- hint、message、button 的边距和间距。
- Trigger/Manual Collection View 的 item spacing、section inset、行高和页码间距。
- Manual 多行首选高度计算。
- Add Device Cell 的图标顶部、文字左右边距和图文间距。
- 已注释的旧 TitleSelectView 和布局代码。

不要改动：

- `isIPad` 分支本身。
- `FontFit`。
- Collection View 行列数。
- 过滤器、菜单和按钮业务逻辑。
- 设备选择、识别、分页和 delegate 回调。

- [ ] **Step 3：使用格式化工具只格式化目标文件**

Run:

```bash
swiftformat SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift
```

如果仓库没有 `swiftformat` 命令，则跳过本步，不安装新工具，也不格式化其他文件。

- [ ] **Step 4：运行缩放搜索**

Run:

```bash
rg -n "SCRXFrom|SCRYFrom" \
  SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift
```

Expected: 无输出，exit code 1。

- [ ] **Step 5：运行完整聚焦契约并确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected:

```text
GroupPathSequenceDeviceAddViewContractTests passed
```

- [ ] **Step 6：阶段检查**

检查：

- `preferredContentHeight` 仍与现有 selected 控件关系一致。
- Manual `rowNum` 变化仍更新 Collection View 高度。
- Space 双过滤器相关配置方法仍存在且签名未变。
- selected 内容没有新增 hard-coded 用户可见文案。

本阶段不执行 Git 提交。

---

### Task 4：完成自动化、静态差异与约束审计

**Files:**

- Verify: Task 1～3 的全部修改文件
- Verify: `docs/260728_1115_group_path_sequence_device_add_view_design.md`

**Interfaces:**

- Consumes: 完成后的契约测试和业务源码。
- Produces: 聚焦测试、缩放扫描、差异检查结果。

- [ ] **Step 1：重新运行聚焦契约**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
```

Expected:

```text
GroupPathSequenceDeviceAddViewContractTests passed
```

- [ ] **Step 2：审计五个目标文件无缩放**

Run:

```bash
rg -n "SCRXFrom|SCRYFrom" \
  SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift
```

Expected: 无输出。

- [ ] **Step 3：审计 Space 入口继续隐藏**

Run:

```bash
sed -n '78,90p' SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

Expected:

- `makeOptions()` 不包含 `.triggerZone`。
- 文件本身没有本任务产生的差异。

- [ ] **Step 4：检查格式与空白错误**

Run:

```bash
git diff --check
```

Expected: exit code 0，无输出。

- [ ] **Step 5：人工审阅聚焦差异**

只审阅以下文件，不处理无关工作树改动：

```bash
git diff -- \
  SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift \
  SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift
```

确认：

- 没有业务逻辑重构。
- 没有本地化、资源、依赖、target 或 Auth 改动。
- 没有启用 Space Trigger Zone。
- 没有误改其他页面的步骤 View 默认布局。

本阶段不执行 Git 提交。

---

### Task 5：验证四个品牌 generic iPhoneOS 构建

**Files:**

- Verify: `SunSmart.xcworkspace`
- Verify: Task 1～3 的全部 Swift 修改

**Interfaces:**

- Consumes: 已通过聚焦契约和静态检查的源码。
- Produces: 四个品牌 target 的编译证据。

- [ ] **Step 1：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit code 0。

- [ ] **Step 2：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit code 0。

- [ ] **Step 3：构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit code 0。

- [ ] **Step 4：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit code 0。

- [ ] **Step 5：若构建失败，先判断失败阶段**

处理规则：

- Swift 编译失败：优先读取首个相关源码错误并修复本任务改动。
- Package resolution 或 sandbox 权限失败：使用同一条直接 `xcodebuild` 命令申请必要权限后重试。
- 与本任务无关且四个 target 共同存在的既有错误：记录完整证据，不把它描述为本任务代码失败。
- 不切换到 Simulator。
- 不使用 shell 包装或日志重定向。

本阶段不执行 Git 提交。

---

### Task 6：完成实施总结与真机验收交接

**Files:**

- Create: `docs/260728_1119_group_path_sequence_device_add_view_implementation_summary.md`
- Reference: `docs/260728_1115_group_path_sequence_device_add_view_design.md`
- Reference: `docs/260728_1119_group_path_sequence_device_add_view_implementation_plan.md`

**Interfaces:**

- Consumes: 最终差异、契约测试、四 target 构建结果。
- Produces: 可追溯的实施总结和真机验收清单。

- [ ] **Step 1：重新运行最终快速检查**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
git diff --check
```

Expected:

- `GroupPathSequenceDeviceAddViewContractTests passed`
- `git diff --check` 无输出。

- [ ] **Step 2：编写实施总结**

总结必须包含：

- 实际修改文件。
- closed/open 最终高度公式。
- Group 与 Space 高度策略。
- 默认提示三列等宽实现。
- 五个目标文件的缩放扫描结果。
- 契约测试实际命令和结果。
- 四个 scheme 的实际构建结果。
- 未修改 Space More 入口。
- 未执行的 Git 操作。
- 尚未完成的真机 UI 验收。

- [ ] **Step 3：交付真机验收清单**

用户后续校验：

- 首次进入 Sequence、Trigger Zone 均为 closed。
- closed 为向上箭头，open 为向下箭头。
- closed 高度为 44 + safe area。
- open 基础高度为 264 + safe area。
- 选中 Path/Zone 自动 open。
- English、简体中文下第二步提示严格居中。
- 三个提示标题列宽一致。
- Quick、Trigger、Manually selected 状态可操作。
- Manually Add 1～3 行不裁剪。
- closed/open 往返不丢失模式、过滤条件和设备数据。
- selected 状态的后续视觉问题单独记录为下一任务。

- [ ] **Step 4：最终报告边界**

最终报告必须区分：

- 已通过的源码契约。
- 已通过的 generic iPhoneOS 编译。
- 尚未由 Codex 完成的真机视觉与交互验收。

不得把 build 成功描述为 selected UI 已经验证正确。

本阶段不执行 Git 提交。

---

## 执行方式

根据项目 `AGENTS.md`，本计划确认后默认使用：

`2. Inline Execution`

执行时使用 `superpowers:executing-plans`，在当前会话按 Task 1～6 顺序完成，并在每个 GREEN 阶段进行检查。除非用户另行明确要求，不使用 subagents，也不再次询问执行方式。
