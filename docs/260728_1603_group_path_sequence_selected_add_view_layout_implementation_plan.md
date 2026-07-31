# GroupPathSequenceDeviceAddView Selected 状态布局优化实施计划

> **执行要求：** REQUIRED SUB-SKILL: 使用 `superpowers:executing-plans` 在当前会话 Inline Execution，按任务顺序执行并在每个 GREEN 检查点复核。不要使用 subagents。

**Goal:** 在选中 Path 或 Zone 后，修正 `GroupPathSequenceDeviceAddView` 的 selected 内容布局，使弹窗运行路径不使用纵向缩放、空态相对整个内容卡片居中、Trigger Add 列表固定为 68 高度，并使 Quick Add 操作组垂直居中。

**Architecture:** 保持现有公共父 View、高度策略、控制器和代理接口不变。仅调整共用步骤 View 的 `.equalColumns` 固定纵向指标，以及 Quick Add、Trigger Add、Manually Add 三个子 View 的局部 Auto Layout 约束；每项改动先增加源代码合同断言，再实施最小修改。

**Tech Stack:** Swift 5、UIKit、SnapKit、现有 Swift 源代码合同测试、Xcode generic iPhoneOS 构建。

## 全局约束

- 所有实现和文档使用简体中文说明；UI 文案保持现有国际化 Key，不新增硬编码文案。
- `GroupPathSequenceDeviceAddView` 的白色 `adding content view` 基础高度保持 160。
- Trigger Add 的 `UICollectionView` 高度在 iPhone、iPad 上统一固定为 68。
- Trigger Add 与 Manually Add 的 `No devices` 相对各自根 View 水平、垂直居中。
- Quick Add 的 Start/Pause、Stop 和状态文字相对根 View 垂直居中并保持同一中心线。
- 弹窗直属文件不得重新引入 `SCRYFrom`；公共步骤 View 的 `.equalColumns` 路径不得执行 `SCRYFrom`。
- 公共步骤 View 的 legacy 路径保持现状，避免影响 Profile、Reset 和 Device Add Instructions。
- 不修改 closed/open、高度策略、safe area 数据流、控制器、代理协议、业务状态机、过滤逻辑、资源、本地化、依赖或 target 配置。
- Space Trigger Zone 继续保持隐藏。
- 保留 worktree 中已有修改，尤其是 Trigger Add、Manually Add 的 `updateNoDevicesLabelVisibility()` 修复及已有合同测试。
- 未经用户授权不执行 `git add`、`git commit`、`git push`、merge 或 PR 操作；各任务不包含提交步骤。
- 构建直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

**修改：**

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
  - 增加 `.equalColumns` 固定纵向指标、Trigger Add 固定高度、空态父级居中和 Quick Add 垂直居中的合同断言。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
  - 为 `.equalColumns` 路径传入固定 8-point 标题间距，同时保留 legacy 缩放。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
  - 统一列表高度常量，并将 `No devices` 改为相对根 View 居中。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
  - 将 `No devices` 改为相对根 View 居中。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
  - 将 Start/Pause 按钮改为相对根 View 垂直居中。

**创建：**

- `docs/260728_1603_group_path_sequence_selected_add_view_layout_implementation_summary.md`
  - 实施完成后记录根因、改动、RED→GREEN、构建结果和真机待验项。

**保持不变：**

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
- Group Sequence、Group Trigger Zone 和 Space Trigger Zone 控制器。

---

### Task 1：固定 `.equalColumns` 步骤提示的纵向间距

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`

**Interfaces:**

- Consumes: `GroupPathSequenceDeviceAddStepView.LayoutStyle.equalColumns`
- Produces: `LayoutMetrics.equalColumnTitleSpacing`
- Produces: `StepFunctionView.init(imageName:title:titleColor:constrainsWidth:titleSpacing:)`
- Preserves: `.legacy` 的 `SCRYFrom(8)` 标题间距与 legacy 圆角行为

- [ ] **Step 1：增加 `.equalColumns` 固定纵向指标的失败合同**

在现有 `stepView` 断言后增加：

```swift
require(
    stepView.contains("static let equalColumnTitleSpacing: CGFloat = 8"),
    "Equal-column guide title spacing must be a fixed 8 points"
)
require(
    stepView.contains(
        "layoutStyle == .equalColumns ? LayoutMetrics.equalColumnTitleSpacing : SCRYFrom(8)"
    ),
    "Equal-column guide must select fixed title spacing without changing legacy scaling"
)
require(
    stepView.contains("titleSpacing: titleSpacing"),
    "Guide must pass the layout-specific title spacing into each step"
)
require(
    stepView.contains(
        "make.top.equalTo(imageView.snp.bottom).offset(titleSpacing)"
    ),
    "Step title constraint must consume the injected fixed spacing"
)
require(
    !stepView.contains(
        "make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(8))"
    ),
    "Step title constraint must not call SCRYFrom directly"
)
```

- [ ] **Step 2：编译并运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，首个新断言报告缺少固定 8-point `equalColumnTitleSpacing`。

- [ ] **Step 3：为 `.equalColumns` 注入固定标题间距**

在 `GroupPathSequenceDeviceAddStepView.LayoutMetrics` 增加：

```swift
static let equalColumnTitleSpacing: CGFloat = 8
```

在 `buildSteps()` 创建步骤项之前计算布局专用间距：

```swift
let titleSpacing = layoutStyle == .equalColumns ? LayoutMetrics.equalColumnTitleSpacing : SCRYFrom(8)
```

创建 `StepFunctionView` 时传入：

```swift
titleSpacing: titleSpacing
```

将 `StepFunctionView` 初始化接口扩展为：

```swift
init(
    imageName: String,
    title: String,
    titleColor: UIColor,
    constrainsWidth: Bool = true,
    titleSpacing: CGFloat
)
```

将标题顶部约束改为：

```swift
make.top.equalTo(imageView.snp.bottom).offset(titleSpacing)
```

不要修改 legacy 分支的圆角、stack spacing、宽度限制或其他调用页面。

- [ ] **Step 4：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS，输出 `GroupPathSequenceDeviceAddViewContractTests layout passed`。

---

### Task 2：固定 Trigger Add 列表高度并居中空态

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`

**Interfaces:**

- Produces: `private let collectionViewHeight: CGFloat = 68`
- Preserves: `updateNoDevicesLabelVisibility()` 的引导状态与空设备联合判断
- Preserves: `HorizontalDirectionFlowLayout`、每页数量、item 尺寸、刷新与识别回调

- [ ] **Step 1：将旧列表高度合同替换为固定 68 合同**

删除旧断言：

```swift
require(
    triggerAddView.contains("let collectionHeight: CGFloat = isIPad ? 64 : 44"),
    "Trigger Add collection height must retain CGFloat typing"
)
```

增加：

```swift
require(
    triggerAddView.contains("private let collectionViewHeight: CGFloat = 68"),
    "Trigger Add collection height must be a fixed 68 points"
)
require(
    triggerAddView.contains(
        "return topContentInset + 66 + extraHintHeight + collectionViewHeight"
    ),
    "Trigger Add preferred height must use the same 68-point collection height"
)

let triggerCollectionConstraints = section(
    in: triggerAddView,
    from: "collectionView.snp.makeConstraints",
    to: "noDevicesLabel ="
)
require(
    triggerCollectionConstraints.contains(
        "make.height.equalTo(collectionViewHeight)"
    ),
    "Trigger Add collection constraint must use the shared 68-point height"
)

let triggerNoDevicesConstraints = section(
    in: triggerAddView,
    from: "noDevicesLabel.snp.makeConstraints",
    to: "pageControl ="
)
require(
    triggerNoDevicesConstraints.contains("make.center.equalToSuperview()"),
    "Trigger Add No devices must center in the whole adding content view"
)
require(
    !triggerNoDevicesConstraints.contains("collectionView"),
    "Trigger Add No devices must not center in the collection view"
)
```

将现有高度算术断言中的 `collectionHeight` 更新为 `collectionViewHeight`，避免合同同时要求新旧实现。

- [ ] **Step 2：运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，报告 Trigger Add 尚未使用固定 68 高度或空态仍相对列表居中。

- [ ] **Step 3：实施 Trigger Add 最小布局修改**

在 `topContentInset` 附近增加：

```swift
private let collectionViewHeight: CGFloat = 68
```

将 `preferredContentHeight` 的 selected 分支改为使用同一常量：

```swift
let extraHintHeight: CGFloat = usesGroupFilterLayout ? 26 : 0
return topContentInset + 66 + extraHintHeight + collectionViewHeight
```

将列表高度约束改为：

```swift
make.height.equalTo(collectionViewHeight)
```

将 `No devices` 约束改为：

```swift
noDevicesLabel.snp.makeConstraints { make in
    make.center.equalToSuperview()
}
```

不要修改 `updateNoDevicesLabelVisibility()`、设备数组、分页或 flow layout 配置。

- [ ] **Step 4：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS。

---

### Task 3：将 Manually Add 空态居中到整个内容卡片

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`

**Interfaces:**

- Preserves: `currentCollectionHeight()`、`preferredMinimumCollectionHeight`、`rowNum`
- Preserves: `updateNoDevicesLabelVisibility()` 的显隐规则

- [ ] **Step 1：增加 Manually Add 空态父级居中的失败合同**

在 Trigger/Manually 空态显隐规则断言之后增加：

```swift
let manuallyNoDevicesConstraints = section(
    in: manuallyAddView,
    from: "noDevicesLabel.snp.makeConstraints",
    to: "pageControl ="
)
require(
    manuallyNoDevicesConstraints.contains("make.center.equalToSuperview()"),
    "Manually Add No devices must center in the whole adding content view"
)
require(
    !manuallyNoDevicesConstraints.contains("collectionView"),
    "Manually Add No devices must not center in the collection view"
)
```

- [ ] **Step 2：运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，报告 Manually Add 的 `No devices` 仍相对 `UICollectionView` 居中。

- [ ] **Step 3：修改 Manually Add 空态中心约束**

将约束改为：

```swift
noDevicesLabel.snp.makeConstraints { make in
    make.center.equalToSuperview()
}
```

不要修改列表高度更新、1～3 行展开、分页或既有显隐辅助方法。

- [ ] **Step 4：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS。

---

### Task 4：垂直居中 Quick Add 操作组

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`

**Interfaces:**

- Preserves: `updateQuickAddState(_:)`
- Preserves: `startBtnAction(sender:)`、`stopBtnAction()`
- Preserves: Start/Pause 的现有水平偏移、Stop 显隐和状态文案

- [ ] **Step 1：增加 Quick Add 操作组垂直居中的失败合同**

增加：

```swift
let quickStartConstraints = section(
    in: quickAddView,
    from: "startBtn.snp.makeConstraints",
    to: "//        pauseBtn"
)
require(
    quickStartConstraints.contains("make.centerY.equalToSuperview()"),
    "Quick Add Start and Pause must center vertically in the adding content view"
)
require(
    !quickStartConstraints.contains("make.top"),
    "Quick Add Start and Pause must not retain top-chain positioning"
)

let quickStopConstraints = section(
    in: quickAddView,
    from: "stopBtn.snp.makeConstraints",
    to: "addStateLabel ="
)
require(
    quickStopConstraints.contains("make.centerY.equalTo(startBtn)"),
    "Quick Add Stop must share the Start and Pause center line"
)

let quickStateLabelConstraints = section(
    in: quickAddView,
    from: "addStateLabel.snp.makeConstraints",
    to: "messageLabel ="
)
require(
    quickStateLabelConstraints.contains("make.centerY.equalTo(startBtn)"),
    "Quick Add state text must share the Start and Pause center line"
)
```

- [ ] **Step 2：运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，报告 Start/Pause 仍使用顶部链式定位。

- [ ] **Step 3：修改 Start/Pause 初始垂直约束**

将初始约束改为：

```swift
startBtn.snp.makeConstraints { make in
    make.centerX.equalToSuperview()
    make.centerY.equalToSuperview()
}
```

保留 Stop 与状态文字的既有 `centerY.equalTo(startBtn)`。

检查以下状态更新方法仅继续更新 `centerX`，不添加或更新 `top`、`centerY`：

- `showStepGuideUI()`
- `updateQuickAddState(_:)`
- `startBtnAction(sender:)`
- `stopBtnAction()`

- [ ] **Step 4：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS。

---

### Task 5：完整静态验证和四品牌 iPhoneOS 构建

**Files:**

- Verify: `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
- Verify: `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- Verify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- Verify: `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- Verify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

- [ ] **Step 1：从干净的临时二进制重新运行完整合同测试**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS，输出 `GroupPathSequenceDeviceAddViewContractTests layout passed`。

- [ ] **Step 2：检查 diff 格式**

Run:

```bash
git diff --check
```

Expected: exit 0，无输出。

- [ ] **Step 3：检查弹窗直属文件未重新引入 `SCRYFrom`**

Run:

```bash
rg -n "SCRYFrom" SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift
```

Expected: exit 1，无匹配。

单独检查公共步骤 View，确认匹配只属于 legacy 路径，`.equalColumns` 使用固定 `equalColumnTitleSpacing`：

```bash
rg -n "SCRYFrom|equalColumnTitleSpacing|titleSpacing" SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift
```

Expected:

- legacy 圆角和 legacy 标题间距仍可包含 `SCRYFrom`；
- `.equalColumns` 选择固定 8-point `equalColumnTitleSpacing`；
- 标题约束只消费注入的 `titleSpacing`。

- [ ] **Step 4：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0，`** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0，`** BUILD SUCCEEDED **`。

- [ ] **Step 6：构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0，`** BUILD SUCCEEDED **`。

- [ ] **Step 7：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0，`** BUILD SUCCEEDED **`。

---

### Task 6：记录结果并交付真机回归清单

**Files:**

- Create: `docs/260728_1603_group_path_sequence_selected_add_view_layout_implementation_summary.md`

- [ ] **Step 1：记录实际实现结果**

总结文档必须记录：

- 实际修改文件。
- `.equalColumns` 与 legacy 的缩放隔离方式。
- Trigger Add 的固定 68 高度与首选高度一致性。
- 两个 `No devices` 的新居中参照。
- Quick Add 操作组的垂直中心线。
- 每个合同测试的 RED 失败信息和最终 GREEN 输出。
- `git diff --check` 结果。
- 四个品牌 target 的真实构建结果及非本次引入的既有警告。
- 未执行的 Git 操作。

- [ ] **Step 2：明确真机待验项**

总结文档和最终交付必须明确：自动化与构建不能替代真机视觉验收，仍需用户检查：

1. Sequence 选中 Path 后的 Trigger Add 与 Manually Add 空态中心。
2. Trigger Zone 选中 Zone 后的相同状态。
3. Trigger Add 有设备时 68 高度列表的点击、分页、刷新和识别。
4. Manually Add 一行及多行展开。
5. Quick Add 的 Stop、Adding、Pause 三种状态。
6. English 与简体中文状态文字是否遮挡。
7. closed/open 与三模式循环切换后布局是否漂移。
8. Space Trigger Zone 入口继续隐藏。

- [ ] **Step 3：复核 worktree 状态**

Run:

```bash
git status --short
```

Expected: 只出现本任务文件及进入任务前已存在的相关修改；不得出现资源、本地化、依赖、target 配置或无关模块变更。

---

## 计划自检

- 设计文档四项需求分别由 Task 1～4 覆盖。
- Trigger Add 的约束高度与首选高度使用同一常量，避免双值漂移。
- `.equalColumns` 固定纵向布局与 legacy 复用页面明确隔离。
- 空态居中不改变前序 `No devices` 显隐修复。
- Quick Add 只改变垂直锚点，不改变状态机和水平关系。
- 没有占位步骤、未定义接口或跨任务名称不一致。
- Task 5 覆盖合同测试、静态检查与四品牌 generic iPhoneOS 构建。
- Task 6 将自动化证据与真机视觉验收明确分开。
- 未包含未经授权的 Git 提交、推送或集成操作。

