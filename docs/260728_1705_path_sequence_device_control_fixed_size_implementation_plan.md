# Path Sequence 设备控件固定尺寸实施计划

> **执行要求：** REQUIRED SUB-SKILL: 使用 `superpowers:executing-plans` 在当前会话 Inline Execution，按任务顺序执行并在每个 GREEN 检查点复核。不要使用 subagents。

**Goal:** 将 Sequence、Trigger Zone 和 `GroupPathSequenceDeviceAddView` 中的可见设备控件在 iPhone、iPad 上统一固定为 44×44，设备图片固定为 20×20，并将 Sequence 顶部编号标签固定为 16 高。

**Architecture:** 保留 iPhone 5 列、iPad 8 列及现有自适应布局槽位，只固定槽位内部的可见设备控件。Sequence 与 Trigger Zone 继续复用 `GroupPathSequencePathItem`；Add View 的设备 Cell 增加内部固定容器，公共 `HorizontalDirectionFlowLayout` 不做全局修改。

**Tech Stack:** Swift 5、UIKit、SnapKit、现有 Swift 源码合同测试、Xcode generic iPhoneOS 构建。

## 全局约束

- 采用已确认方案 A：可见设备控件固定 44×44，自适应 Collection View 槽位可以宽于 44。
- 在线、离线设备图片固定 20×20；Add 图标和方向箭头保持现状。
- Sequence 顶部编号标签固定高 16，Sequence 槽位高度固定为 60。
- iPhone 保持 5 列，iPad 保持 8 列。
- 只清理设备列表尺寸链中的 `SCRYFrom`，不重构页面外壳、Header、空状态或业务流程。
- 保留 `GroupPathSequenceDeviceAddView` 的 160pt 基础内容高度、closed/open、高度策略和 safe area 数据流。
- 保留 Trigger Add 的 68pt Collection View 高度。
- 保留 Manually Add 的 1～3 行展开、分页和拖拽。
- 不修改用户可见文案、本地化、资源、依赖或 Target 配置。
- 相关文件由四个品牌 Target 共用，最终构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart。
- 未经用户授权不执行 `git add`、`git commit`、`git push`、merge 或 PR。
- 构建直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

**修改：**

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
  - 增加 Sequence、Trigger Zone 和 Add View 固定设备尺寸合同。
- `SunSmart/Main/Group/Path/View/GroupPathSequencePathLayout.swift`
  - 集中定义设备控件尺寸，并让 Sequence 连接线使用 44pt 控件边界。
- `SunSmart/Main/Group/Path/View/GroupPathSequencePathViewCell.swift`
  - 固定 Sequence 设备、Add Item、图片和标签尺寸。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerZoneViewCell.swift`
  - 固定 Trigger Zone 设备高度和 Table View Cell 高度计算。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
  - 固定设备行估算高度。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
  - 增加固定 44×44 内部设备容器。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
  - 固定设备 Item 高度、列表垂直居中和选中边框目标。
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
  - 固定设备 Item 高度、多行高度计算和选中边框目标。

**保持不变：**

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Common/View/HorizontalDirectionFlowLayout.swift`
- 数据模型、代理协议、Mesh 消息、分页数量和拖拽数据。

**完成后创建：**

- `docs/260728_1705_path_sequence_device_control_fixed_size_implementation_summary.md`

---

### Task 1：Sequence 与 Trigger Zone 固定设备尺寸

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequencePathLayout.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequencePathViewCell.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerZoneViewCell.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`

**Interfaces:**

- Produces: `GroupPathSequenceDeviceItemMetrics`
- Produces: `controlSize = 44`
- Produces: `imageSize = 20`
- Produces: `sequenceLabelHeight = 16`
- Produces: `sequenceItemHeight = 60`
- Preserves: Sequence 5/8 列蛇形排序、连接线、Add Item、选择和拖放。
- Preserves: Trigger Zone 5/8 列、空数据、选择和拖放。

- [ ] **Step 1：增加失败合同**

在合同测试中加载 Path Cell、Trigger Zone Cell 和 Path Layout，并增加以下合同：

```swift
let pathCell = try source(
    root,
    "SunSmart/Main/Group/Path/View/GroupPathSequencePathViewCell.swift"
)
let zoneCell = try source(
    root,
    "SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerZoneViewCell.swift"
)
let pathLayout = try source(
    root,
    "SunSmart/Main/Group/Path/View/GroupPathSequencePathLayout.swift"
)
```

要求合同覆盖：

```swift
require(pathLayout.contains("static let controlSize: CGFloat = 44"), "Device control must be 44 points")
require(pathLayout.contains("static let imageSize: CGFloat = 20"), "Device image must be 20 points")
require(pathLayout.contains("static let sequenceLabelHeight: CGFloat = 16"), "Sequence label must be 16 points")
require(pathLayout.contains("static let sequenceItemHeight: CGFloat = 60"), "Sequence item height must be 60 points")
require(pathCell.contains("make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.controlSize)"), "Sequence control must use fixed 44")
require(pathCell.contains("make.height.equalTo(GroupPathSequenceDeviceItemMetrics.sequenceLabelHeight)"), "Sequence label must use fixed 16")
require(pathCell.contains("make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.imageSize)"), "Sequence image must use fixed 20")
require(!pathCell.contains("SCRYFrom"), "Sequence device cell must not retain SCRYFrom")
require(!zoneCell.contains("SCRYFrom"), "Trigger Zone device cell must not retain SCRYFrom")
require(!pathLayout.contains("SCRYFrom"), "Sequence path layout must not retain SCRYFrom")
```

Trigger Zone 合同还需验证：

```swift
require(zoneCell.contains("height: GroupPathSequenceDeviceItemMetrics.controlSize"), "Trigger Zone slot height must be 44")
require(zoneCell.contains("max(rowCount - 1, 0)"), "Trigger Zone zero rows must not produce negative spacing")
require(zoneController.contains("tableView.estimatedRowHeight = 76"), "Trigger Zone estimated row height must be fixed")
```

- [ ] **Step 2：运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，首个新增断言报告缺少固定 44pt 设备控件指标。

- [ ] **Step 3：实现共享固定指标和 Sequence Layout**

在 `GroupPathSequencePathLayout.swift` 增加：

```swift
enum GroupPathSequenceDeviceItemMetrics {
    static let controlSize: CGFloat = 44
    static let controlCornerRadius: CGFloat = 22
    static let imageSize: CGFloat = 20
    static let sequenceLabelHeight: CGFloat = 16
    static let sequenceItemHeight: CGFloat = 60
    static let lineSpacing: CGFloat = 8
    static let sequenceVerticalInset: CGFloat = 10
    static let triggerZoneSectionInset: CGFloat = 16
    static let triggerZoneMinimumHeight: CGFloat = 60
    static let imageTopSpacing: CGFloat = 3
    static let imageNameSpacing: CGFloat = 2
}
```

将 Path Layout 的默认 Item 高度设为 `sequenceItemHeight`。每次 `prepare()` 都用当前 Collection View 宽度重新生成槽位宽度与固定高度，不保留旧 `itemSize.width`。

跨行连接线的左右端点使用：

```swift
GroupPathSequenceDeviceItemMetrics.controlSize * 0.5
```

不要再使用自适应槽位宽度的一半作为 44pt 圆形控件边界。

- [ ] **Step 4：固定 Sequence Item 内部布局**

在 `GroupPathSequencePathViewCell.swift`：

- `itemHeight` 使用 `sequenceItemHeight`。
- 行间距使用固定 `lineSpacing`。
- Collection View 上下 Inset 使用固定 `sequenceVerticalInset`。
- 初始高度使用 `sequenceItemHeight + 上下 Inset`。
- `sequenceLabel` 固定高 16。
- 设备 `boxView` 和 Add Item `boxView` 固定 44×44，水平居中并贴槽位底部。
- 设备图片固定 20×20。
- 图片顶部固定 3，图片到名称固定 2，不再区分 iPhone/iPad。
- 圆角固定为 22，确保 44×44 的 `boxView` 始终保持原有圆形，不依赖布局时读取 Frame。
- 文件内剩余交互菜单纵向指标改为等值固定 point，确保不再保留 `SCRYFrom`。

- [ ] **Step 5：固定 Trigger Zone Item 和行高**

在 `GroupPathSequenceTriggerZoneViewCell.swift`：

- `sizeForItemAt` 保留当前自适应槽位宽度，高度固定为 44。
- 行间距固定为 8。
- Section 上下 Inset 固定为 16。
- Cell 高度按 `rowCount × 44 + max(rowCount - 1, 0) × 8 + 32` 计算。
- 零设备继续使用固定最小高度 60。
- 文件内剩余交互菜单纵向指标改为等值固定 point，确保不再保留 `SCRYFrom`。

在 `GroupPathSequenceTriggerZoneController.swift` 将设备行估算高度设为固定 76。不要改页面外壳、Header 和空状态。

- [ ] **Step 6：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS，输出 `GroupPathSequenceDeviceAddViewContractTests layout passed`。

---

### Task 2：Add View 固定设备控件和多行高度

**Files:**

- Modify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- Modify: `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`

**Interfaces:**

- Produces: `GroupPathSequenceAddDeviceCell.boxView`
- Consumes: `GroupPathSequenceDeviceItemMetrics.controlSize`
- Consumes: `GroupPathSequenceDeviceItemMetrics.imageSize`
- Preserves: `HorizontalDirectionFlowLayout` 的自适应槽位宽度与分页。
- Preserves: Trigger/Manually Add 的代理、选择、识别、拖拽与空状态。

- [ ] **Step 1：增加失败合同**

增加以下合同：

```swift
require(addDeviceCell.contains("var boxView: UIView!"), "Add device cell must expose its fixed visual control")
require(addDeviceCell.contains("make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.controlSize)"), "Add device control must be fixed 44")
require(addDeviceCell.contains("make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.imageSize)"), "Add device image must be fixed 20")
require(triggerAddView.contains("flowLayout.itemHeight = GroupPathSequenceDeviceItemMetrics.controlSize"), "Trigger Add item height must be 44")
require(triggerAddView.contains("UIEdgeInsets(top: 12, left: 26, bottom: 12, right: 25)"), "Trigger Add 44-point item must center in 68 points")
require(!triggerAddView.contains("make.height.equalTo(isIPad ? 64 : 44)"), "Trigger Add must retain fixed 68-point collection height")
require(manuallyAddView.contains("flowLayout.itemHeight = GroupPathSequenceDeviceItemMetrics.controlSize"), "Manually Add item height must be 44")
require(manuallyAddView.contains("return GroupPathSequenceDeviceItemMetrics.controlSize * CGFloat(rowNum)"), "Manual height must use fixed 44")
```

还需验证 Trigger Add 和 Manually Add 的选中、未选中边框都更新 `cell.boxView.layer.borderColor`，不再更新整个 Cell Layer。

- [ ] **Step 2：运行合同测试，确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: FAIL，首个新增断言报告 Add Device Cell 尚无固定内部设备容器。

- [ ] **Step 3：实现 Add Device Cell 内部固定控件**

在 `GroupPathSequenceAddDeviceCell.swift`：

- Cell 本身保持透明，不再直接绘制边框和圆角。
- 新增公开只读用途的 `boxView`。
- `boxView` 在自适应槽位内水平居中，固定 44×44。
- 边框移至 `boxView`，圆角固定为 22，保持原有圆形。
- 设备图片移入 `boxView` 并固定 20×20。
- 名称移入 `boxView`。
- 图片顶部固定 3，图片到名称固定 2，不再区分 iPhone/iPad。

- [ ] **Step 4：固定 Trigger Add 设备高度**

在 `GroupPathSequenceTriggerAddView.swift`：

- `flowLayout.itemHeight` 固定为 44。
- Section 上下 Inset 都设为 12，使 44pt 控件在 68pt Collection View 内垂直居中。
- 初始约束、默认筛选布局和 Group Filter 布局三处都使用同一个 `collectionViewHeight = 68`。
- 选中和未选中边框更新 `cell.boxView.layer.borderColor`。
- 不改变每页数量、刷新、识别和空状态逻辑。

- [ ] **Step 5：固定 Manually Add 单行和多行高度**

在 `GroupPathSequenceManuallyAddView.swift`：

- `flowLayout.itemHeight` 固定为 44。
- `preferredMinimumCollectionHeight` 固定为 44，不再区分 iPhone/iPad。
- `currentCollectionHeight()` 使用 `44 × rowNum + 行间距 × (rowNum - 1)`。
- 选中和未选中边框更新 `cell.boxView.layer.borderColor`。
- 保留现有 `rowNum`、分页和拖拽逻辑。

- [ ] **Step 6：重新运行合同测试，确认 GREEN**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS。

---

### Task 3：完整验证和实施总结

**Files:**

- Create: `docs/260728_1705_path_sequence_device_control_fixed_size_implementation_summary.md`

**Interfaces:**

- Verifies: 已确认方案 A 的全部布局合同。
- Preserves: 四品牌 Target 编译兼容性。

- [ ] **Step 1：运行完整合同测试**

Run:

```bash
swiftc -parse-as-library Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/trigger-zone-july
```

Expected: PASS。

- [ ] **Step 2：运行静态检查**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` 无输出；状态只包含本任务预期文件。

- [ ] **Step 3：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7：复核需求覆盖**

逐项复核：

- Sequence 可见设备与 Add Item 44×44。
- Sequence 图片 20×20、标签高 16、槽位高 60。
- Trigger Zone 可见设备 44×44，零行高度安全。
- Trigger Add、Manually Add 可见设备 44×44。
- iPhone 5 列、iPad 8 列不变。
- Sequence 连接线转角使用 44pt 控件边界。
- `GroupPathSequenceDeviceAddView` 高度策略不回退。
- 业务逻辑、本地化、资源和 Target 配置无额外变化。

- [ ] **Step 8：编写实施总结**

总结记录：

- 根因与最终布局契约。
- 两轮 RED→GREEN 的实际失败和通过结果。
- 四 Target 构建结果。
- 自动化和构建不能覆盖的 iPhone/iPad 真机 UI 验收项。
- 未执行任何 Git 提交、推送、合并或 PR。
