# Path Sequence 空状态水平居中修复设计

## 1. 问题

在 iPad 的 Path Sequence 页面中，以下两个分类没有数据时，空状态图片、文案和操作按钮整体偏右：

- Sequence：`No sequences`
- Trigger Zone：`No trigger zones`

预期空状态内容相对当前 View Controller 的可见内容区域水平居中。

## 2. 根因

`EmptyDataView` 的内部布局已经使用水平居中约束：

- 图片相对内部 `contentView` 水平居中。
- 按钮相对内部 `contentView` 水平居中。
- 文案通过左右约束覆盖内部 `contentView`。

问题发生在最外层 `EmptyDataView`：

1. Sequence 和 Trigger Zone 控制器把 `tableView.frame` 作为一次性 frame 传给根视图上的空状态。
2. 最外层 `EmptyDataView` 没有约束到 `tableView` 或 View Controller。
3. 页面只在首次布局时重新创建一次空状态。
4. iPad 的 Page Controller 后续调整子控制器尺寸时，空状态仍保留旧 frame。
5. 内部图片和按钮虽然继续在空状态自身内部居中，但空状态容器已经不再与当前 View Controller 对齐，因此视觉上整体偏右。

## 3. 修复方案

保留空状态添加到 View Controller 根视图的现有层级和点击行为，但不再依赖外层 frame 快照。

在 Sequence 和 Trigger Zone 两个控制器创建空状态后：

- 使用 Auto Layout 将最外层 `EmptyDataView` 的四条边约束到各自的 `tableView`。
- 由现有 `tableView` 左右等距约束保证空状态中心与 View Controller 水平中心一致。
- 当 iPad Page Controller、旋转或分屏导致可见区域尺寸变化时，空状态随 `tableView` 自动更新。
- 保留现有图片、文案、按钮的内部居中约束。

## 4. 修改范围

修改：

- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

不修改：

- 公共 `EmptyDataView` API 和其他页面。
- `SpacePathTriggerZoneController`。
- 空状态图片、文案、按钮尺寸和纵向位置。
- 本地化、资源、依赖或 target 配置。
- Path Sequence 的数据、设备添加和 Mesh 业务逻辑。

## 5. 测试与验证

遵循 RED → GREEN：

1. 扩展现有 Path Sequence 合同测试，要求两个控制器都把根视图上的空状态约束到对应 `tableView`。
2. 先运行合同测试，确认现有实现因缺少外层约束而失败。
3. 添加最小生产代码，使两个控制器使用相同的约束方式。
4. 再运行合同测试，确认通过。
5. 运行 `git diff --check`。
6. 使用 generic iPhoneOS、Debug、关闭代码签名构建 `SunSmart`。

构建成功只能验证编译链；最终视觉结果仍需在 iPad 上验证：

- Sequence 空状态相对 View Controller 水平居中。
- Trigger Zone 空状态相对 View Controller 水平居中。
- 旋转或分屏尺寸变化后仍保持居中。
- 添加数据后空状态正常移除，按钮回调行为不变。

## 6. 完成条件

- 两个分类的最外层空状态均由 Auto Layout 跟随 `tableView`。
- 不再依赖一次性 `tableView.frame` 决定外层空状态的最终布局。
- 合同测试、差异检查和 `SunSmart` generic iPhoneOS 构建通过。
- 不覆盖当前工作区已有的无关修改。
