# Path Sequence Empty State Centering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Do not use subagents unless the user explicitly changes the execution preference.

**Goal:** 让 iPad Path Sequence 页面中 Sequence 和 Trigger Zone 的空状态始终相对当前 View Controller 水平居中。

**Architecture:** 保留空状态作为两个子控制器根视图的子视图，避免改变 `UITableView` 的滚动语义。创建空状态后，使用 SnapKit 将最外层 `EmptyDataView` 四边约束到对应 `tableView`，由 Auto Layout 跟随 iPad Page Controller、旋转和分屏产生的尺寸变化。

**Tech Stack:** Swift、UIKit、SnapKit、Foundation 合同测试、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复和项目文档使用简体中文；用户可见 UI 文案保持现有本地化。
- 改动只覆盖 Group Path Sequence 的 Sequence 和 Trigger Zone 两个子控制器。
- 不修改公共 `EmptyDataView`、Space Trigger Zone、本地化、资源、依赖或 target 配置。
- 保留当前工作区中已有的未提交改动，不覆盖或回退无关内容。
- 遵循 RED → GREEN，生产代码修改前必须先看到新增测试因缺少外层约束而失败。
- iOS 构建直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 Simulator、shell 包装或日志重定向。
- 未经用户明确授权，不执行 Git commit、push、merge 或 PR 操作。

---

## File Structure

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
  - 扩展现有 Path Sequence 合同测试，约束两个控制器的空状态宿主和 Auto Layout 关系。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
  - Sequence 空状态创建后，将最外层空状态约束到 `tableView`。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
  - Trigger Zone 空状态创建后，将最外层空状态约束到 `tableView`。
- `docs/260728_1940_path_sequence_empty_state_centering_implementation_summary.md`
  - 记录根因、实际改动、RED/GREEN、差异检查、构建结果和真机验收边界。

### Task 1: 空状态外层约束回归测试与最小修复

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- Create: `docs/260728_1940_path_sequence_empty_state_centering_implementation_summary.md`

**Interfaces:**

- Consumes: `UIView.showEmptyDataView(...)` 创建并通过 `view.emptyView` 暴露最外层 `EmptyDataView`。
- Produces: Sequence 和 Trigger Zone 的 `updateEmptyUI()` 在空状态存在时建立 `EmptyDataView.edges == tableView.edges` 约束。
- Preserves: 现有空状态图片、文案、按钮、点击回调、背景颜色、纵向偏移和显隐逻辑。

- [x] **Step 1: 在现有合同测试中加入失败断言**

在已读取 `sequenceController` 和 `zoneController` 后，提取两个 `updateEmptyUI()` 方法：

```swift
let sequenceEmptyState = section(
    in: sequenceController,
    from: "private func updateEmptyUI()",
    to: "private func updateDeviceAddViewUI()"
)
let zoneEmptyState = section(
    in: zoneController,
    from: "private func updateEmptyUI()",
    to: "private func updateDeviceAddViewUI()"
)
```

加入以下合同：

```swift
for (name, emptyState) in [
    ("Sequence", sequenceEmptyState),
    ("Trigger Zone", zoneEmptyState),
] {
    require(
        !emptyState.contains("frame: tableView.frame"),
        "\(name) empty state must not depend on a one-time table frame snapshot"
    )
    require(
        emptyState.contains("view.emptyView?.snp.makeConstraints"),
        "\(name) empty state must receive outer Auto Layout constraints"
    )
    require(
        emptyState.contains("make.edges.equalTo(tableView)"),
        "\(name) empty state must track all table view edges"
    )
}
```

该测试防止以下回归：

- 再次使用一次性 `tableView.frame` 决定最终布局。
- 只保留内部图片或按钮的 `centerX`，遗漏最外层空状态约束。
- 只约束水平中心而遗漏宽高或纵向覆盖区域。

- [x] **Step 2: 编译并运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected:

- 编译成功。
- 测试退出码非零。
- 首个新增失败信息为 `Sequence empty state must not depend on a one-time table frame snapshot`。
- 失败来自当前生产代码仍包含 `frame: tableView.frame`，而不是测试语法或文件路径错误。

- [x] **Step 3: 修复 Sequence 空状态外层约束**

在 `GroupPathSequenceViewController.updateEmptyUI()` 中：

1. 从 `view.showEmptyDataView(...)` 调用移除 `frame: tableView.frame`。
2. 保留现有 title、background、button、button width、position、bottom margin 和回调。
3. 创建完成后添加：

```swift
view.emptyView?.snp.makeConstraints { make in
    make.edges.equalTo(tableView)
}
```

最终外层空状态由 `tableView` 的四边约束决定，内部图片和按钮继续使用 `EmptyDataView` 现有的水平居中约束。

- [x] **Step 4: 修复 Trigger Zone 空状态外层约束**

在 `GroupPathSequenceTriggerZoneController.updateEmptyUI()` 中执行与 Sequence 相同的最小修改：

1. 移除 `frame: tableView.frame`。
2. 保留现有空状态配置和 `addZone()` 回调。
3. 创建完成后添加：

```swift
view.emptyView?.snp.makeConstraints { make in
    make.edges.equalTo(tableView)
}
```

不要抽取公共 helper；两个调用点规模很小，抽取会扩大本次修复范围。

- [x] **Step 5: 重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected:

- 退出码为零。
- 输出 `GroupPathSequenceDeviceAddViewContractTests layout passed`。
- 既有合同和新增空状态合同全部通过。

- [x] **Step 6: 审查聚焦差异**

Run:

```bash
git diff -- SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift
```

确认：

- 两个控制器只改变空状态外层布局方式。
- 不修改空状态文案、图片、按钮、纵向位置或点击行为。
- 测试文件保留用户当前已有的其他未提交改动。
- `SpacePathTriggerZoneController` 和公共 `EmptyDataView` 没有变化。

- [x] **Step 7: 运行差异格式检查**

Run:

```bash
git diff --check
```

Expected: 退出码为零且无输出。

- [x] **Step 8: 运行 SunSmart generic iPhoneOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 退出码为零。
- 输出包含 `** BUILD SUCCEEDED **`。

构建仅验证 Swift、UIKit、SnapKit 和工程集成，不宣称 iPad 视觉效果已由真实设备验收。

- [x] **Step 9: 保存实施总结**

创建 `docs/260728_1940_path_sequence_empty_state_centering_implementation_summary.md`，记录：

- 根因：外层空状态使用一次性 frame，内部居中不等于相对 View Controller 居中。
- 修复：两个 Group 控制器将外层空状态四边约束到 `tableView`。
- RED：新增合同测试的实际失败信息和退出状态。
- GREEN：合同测试的通过输出。
- `git diff --check` 结果。
- `SunSmart` generic iPhoneOS 构建结果。
- 当前未修改、未回退的既有工作区变更。
- 尚需用户在 iPad 上验证 Sequence、Trigger Zone、旋转和分屏场景。

## Plan Self-Review

- Spec coverage: 根因、两个控制器、约束方式、TDD、构建和真机边界均有对应步骤。
- Placeholder scan: 所有步骤均包含明确文件、实际修改内容、命令和预期结果。
- Type consistency: 使用现有 `UIView.emptyView`、SnapKit `snp.makeConstraints` 和两个控制器既有 `tableView` 属性，不新增接口。
- Scope: 单一布局缺陷、单一实施任务，不需要拆分子项目或使用 subagents。
