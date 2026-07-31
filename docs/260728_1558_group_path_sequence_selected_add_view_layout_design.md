# GroupPathSequenceDeviceAddView Selected 状态布局优化设计

## 1. 背景

Path sequence 页面在选中 Path 或 Zone 后，展开公共 `GroupPathSequenceDeviceAddView` 会展示 Quick Add、Trigger Add、Manually Add 三种 selected 内容。

当前 selected 状态存在以下布局问题：

- Trigger Add 的 `UICollectionView` 在 iPhone 上高度为 44、iPad 上高度为 64，与期望的固定 68 不一致。
- Trigger Add 与 Manually Add 的 `No devices` 当前相对各自的 `UICollectionView` 居中，不是相对整个白色 `adding content view` 居中。
- Quick Add 的 Start/Pause 按钮使用顶部链式约束定位；Stop 按钮和状态文字虽然跟随 Start/Pause 对齐，但整组控件没有相对内容卡片垂直居中。
- 弹窗直属 Parent、Quick Add、Trigger Add、Manually Add、Add Device Cell 已不包含 `SCRYFrom`，但三种模式共用的步骤提示 View 仍有纵向缩放调用。

## 2. 目标

在不改变设备添加业务流程的前提下，统一 selected 状态下的固定布局：

- 弹窗实际使用的布局路径不再依赖 `SCRYFrom`。
- Trigger Add 与 Manually Add 的 `No devices` 在整个白色 `adding content view` 中水平、垂直居中。
- Trigger Add 的 `UICollectionView` 高度固定为 68。
- Quick Add 的 Start/Pause、Stop 和右侧状态文字位于同一水平中心线，并在白色 `adding content view` 中垂直居中。

## 3. 非目标

本次不修改：

- Quick Add、Trigger Add、Manually Add 的业务状态机、代理回调或设备过滤逻辑。
- Trigger Add 的 item 数量、item 尺寸、分页、刷新或识别逻辑。
- Manually Add 的动态列表高度、1～3 行展开或分页逻辑。
- 三种模式的水平布局关系。
- `GroupPathSequenceDeviceAddView` 的 closed/open 状态、高度策略或 safe area 数据流。
- Path Header、Path Cell、Path Test 等不属于弹窗的 View。
- Space Trigger Zone 的入口和可见性；该功能继续保持隐藏。
- 本地化文案、图片资源、依赖和 target 配置。

## 4. 方案选择

采用“局部固定约束与统一 Layout Metrics”方案。

各子 View 继续负责自己的 selected 内容布局，通过固定 point 常量和 Auto Layout 完成调整。公共父 View、控制器、高度策略、业务接口均保持不变。

不新增统一布局容器，也不在 `layoutSubviews` 中手工计算控件位置，以避免扩大历史 View 的重构范围或引入 Auto Layout 状态冲突。

## 5. 详细设计

### 5.1 `SCRYFrom` 清理边界

以下弹窗直属文件保持不使用 `SCRYFrom`：

- `GroupPathSequenceDeviceAddView.swift`
- `GroupPathSequenceQuickAddView.swift`
- `GroupPathSequenceTriggerAddView.swift`
- `GroupPathSequenceManuallyAddView.swift`
- `GroupPathSequenceAddDeviceCell.swift`

`GroupPathSequenceDeviceAddStepView` 被 Profile、Reset 和 Device Add Instructions 等页面复用，因此不对 legacy 布局做全局改版。

弹窗使用的 `.equalColumns` 路径改为显式固定纵向指标：

- 提示标题与步骤图片间距固定为 8。
- 等宽列顶部、列间距及其他纵向指标继续使用固定 point。
- `.equalColumns` 路径不执行 `SCRYFrom`。
- legacy 路径保持原有缩放行为，避免影响无关页面。

“去掉此弹窗中所有 `SCRYFrom`”的验收范围，是弹窗直属文件与公共步骤 View 的 `.equalColumns` 运行路径，不包含公共步骤 View 的 legacy 路径及 Path sequence 页面其他非弹窗 View。

### 5.2 Trigger Add

为 Trigger Add 使用单一固定列表高度常量 68，并同时用于：

- `UICollectionView` 的高度约束。
- selected 内容首选高度计算。

这样可以避免实际约束高度与父 View 上报高度不一致。

列表仍采用现有 `HorizontalDirectionFlowLayout`。列表高度调整不修改 flow layout 的 item 宽高计算、每页数量、横向分页和 section inset。

`No devices` 的中心约束从 `UICollectionView` 改为 Trigger Add 根 View：

- 水平中心等于父 View 水平中心。
- 垂直中心等于父 View 垂直中心。

其显隐规则保持不变：只有引导内容隐藏且设备列表为空时才显示。

### 5.3 Manually Add

`No devices` 的中心约束从 `UICollectionView` 改为 Manually Add 根 View：

- 水平中心等于父 View 水平中心。
- 垂直中心等于父 View 垂直中心。

当 Manually Add 从一行展开到多行、父内容高度增加时，`No devices` 随父 View 新高度保持居中。

不修改 `currentCollectionHeight()`、`rowNum`、最低列表高度、分页或展开按钮逻辑。

### 5.4 Quick Add

Start 与 Pause 共用现有状态按钮。该按钮改为：

- 保留现有水平中心约束及状态切换时的水平偏移。
- 移除相对筛选提示区域的顶部链式定位。
- 垂直中心等于 Quick Add 根 View 垂直中心。

Stop 按钮继续与 Start/Pause 按钮垂直中心对齐。

右侧状态文字继续与 Start/Pause 按钮垂直中心对齐，覆盖以下文案状态：

- `Click to add`
- `Pause add`
- `Adding…`

状态切换只更新按钮显隐、选中状态、文字、文字颜色和现有水平位置，不再改变垂直位置。

筛选控件和底部说明文字的现有约束不变。

### 5.5 父 View 与高度策略

Group Sequence 和 Group Trigger Zone 继续使用 `.fixedBase`：

- 白色 `adding content view` 基础高度仍为 160。
- Trigger Add 列表高度调整为 68 后，其内容仍可容纳在 160 基础高度中。
- Quick Add 的垂直居中参照该 160 高度内容卡片。
- Manually Add 需要多行时继续沿用现有扩展高度规则。

隐藏的 Space Trigger Zone 继续使用 `.dynamicSelected`。本次不修改其控制器或入口；共享子 View 的约束调整会自然复用，但不改变功能可见性。

## 6. 状态与数据流

本次不新增状态。

现有数据流保持：

1. 控制器选择 Path 或 Zone。
2. `canAddDevice` 变为 `true`。
3. 三个子 View 隐藏步骤引导并展示 selected 内容。
4. 切换 Quick Add、Trigger Add、Manually Add 时，父 View 切换可见子 View。
5. 子 View 按现有代理协议处理添加状态、设备刷新、设备选择和识别。

布局变化不参与业务状态判断。

## 7. 测试设计

扩展现有 `GroupPathSequenceDeviceAddViewContractTests`，先写失败断言，再实施最小修改。

合同测试覆盖：

- 弹窗直属 Parent、Quick Add、Trigger Add、Manually Add、Add Device Cell 不包含 `SCRYFrom`。
- 公共步骤 View 的 `.equalColumns` 路径使用固定 8-point 标题间距，不执行纵向缩放。
- Trigger Add 的列表约束和首选高度计算使用同一个固定 68 常量。
- Trigger Add 与 Manually Add 的 `No devices` 相对各自根 View 居中，不再相对列表居中。
- Quick Add 的 Start/Pause 按钮相对根 View 垂直居中。
- Stop 按钮和状态文字继续相对 Start/Pause 垂直居中。
- Quick Add 状态更新只修改水平位置，不引入新的顶部或垂直位置更新。

静态与构建验证：

- 运行合同测试并确认 RED 到 GREEN。
- 运行 `git diff --check`。
- 检查约定弹窗范围内的 `SCRYFrom`。
- 使用 generic iPhoneOS、Debug、关闭代码签名构建：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`

## 8. 真机验收

构建成功不能证明视觉布局正确。真机至少验证：

1. Sequence 选中 Path 后展开底部 View。
2. Trigger Zone 选中 Zone 后展开底部 View。
3. Trigger Add 有设备时，列表显示区域高度符合 68，设备点击、分页、刷新和识别仍可用。
4. Trigger Add 无设备时，`No devices` 位于整个白色内容卡片中心。
5. Manually Add 无设备时，`No devices` 位于整个白色内容卡片中心。
6. Manually Add 一行及多行高度下，空态和设备列表均无约束异常。
7. Quick Add 的 Stop、Adding、Pause 三种状态下，按钮组和右侧文字始终垂直居中。
8. English 与简体中文下状态文字不遮挡按钮。
9. closed/open 往返和三种添加方式循环切换后，布局不漂移。
10. Space Trigger Zone 入口继续保持隐藏。

## 9. 预计影响文件

修改：

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

不修改：

- `GroupPathSequenceDeviceAddView.swift`
- Group Sequence、Group Trigger Zone 和 Space Trigger Zone 控制器。
- 本地化文件、资源目录、依赖和 target 配置。

## 10. 完成条件

以下条件全部满足才视为完成：

- 四项布局需求按本设计落地。
- 弹窗 `.equalColumns` 路径不再执行 `SCRYFrom`。
- selected 状态业务行为保持不变。
- 合同测试通过。
- `git diff --check` 通过。
- 四个品牌 target 的 generic iPhoneOS 构建成功。
- 真机视觉结果由用户按第 8 节完成验收。
