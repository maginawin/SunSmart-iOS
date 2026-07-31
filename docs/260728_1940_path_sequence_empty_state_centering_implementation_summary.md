# Path Sequence 空状态水平居中实施总结

## 1. 结论

已将 Path Sequence 页面中 Sequence 和 Trigger Zone 的最外层空状态改为使用 Auto Layout 跟随各自的 `tableView`。

空状态内部原有的图片、文案和按钮居中约束保持不变；外层容器不再依赖一次性的 `tableView.frame`，因此可以随 iPad Page Controller、旋转和分屏造成的尺寸变化自动更新。

## 2. 根因

原实现的图片和按钮确实使用了水平居中约束，但这些约束只相对于 `EmptyDataView` 内部容器生效。

两个 Group 控制器把 `tableView.frame` 作为一次性 frame 传给根视图上的 `EmptyDataView`，最外层空状态没有约束到 `tableView`。iPad 容器后续调整子控制器尺寸时，内部内容仍在旧空状态 frame 中居中，导致整个空状态视觉上偏右。

## 3. 实际修改

修改：

- `GroupPathSequenceViewController`
  - 移除空状态创建时的 `frame: tableView.frame`。
  - 创建后将最外层 `EmptyDataView` 四边约束到 Sequence `tableView`。
- `GroupPathSequenceTriggerZoneController`
  - 移除空状态创建时的 `frame: tableView.frame`。
  - 创建后将最外层 `EmptyDataView` 四边约束到 Trigger Zone `tableView`。
- `GroupPathSequenceDeviceAddViewContractTests`
  - 增加两个控制器不得依赖一次性 frame 快照的合同。
  - 增加两个控制器必须为最外层空状态建立约束的合同。
  - 增加最外层空状态必须跟随 `tableView` 四边的合同。

未修改：

- 公共 `EmptyDataView`。
- `SpacePathTriggerZoneController`。
- 空状态图片、文案、按钮尺寸、纵向偏移和点击回调。
- 本地化、资源、依赖及 target 配置。
- 当前工作区已有的 `GroupPathSequenceManuallyAddView` 拖拽预览改动和对应合同。

## 4. RED → GREEN

### RED

生产代码修改前编译并运行合同测试：

- 编译成功。
- 测试退出码：133。
- 失败信息：`Sequence empty state must not depend on a one-time table frame snapshot`。

该失败直接证明现有实现仍依赖一次性的 `tableView.frame`。

### GREEN

完成两个控制器的最小修改后重新运行同一合同测试：

- 退出码：0。
- 输出：`GroupPathSequenceDeviceAddViewContractTests layout passed`。

## 5. 静态与构建验证

### 差异检查

`git diff --check`：

- 退出码：0。
- 无输出。

### SunSmart generic iPhoneOS 构建

构建配置：

- Workspace：`SunSmart.xcworkspace`
- Scheme：`SunSmart`
- Configuration：`Debug`
- SDK：`iphoneos`
- Destination：`generic/platform=iOS`
- Code Signing：关闭

结果：

- 退出码：0。
- 输出：`** BUILD SUCCEEDED **`。

## 6. 验收边界

合同测试和 generic iPhoneOS 构建证明布局合同及编译链通过，但不等同于 iPad 真实视觉验收。

仍需在 iPad 上确认：

1. Sequence 无数据时，图片、`No sequences` 和按钮相对 View Controller 水平居中。
2. Trigger Zone 无数据时，图片、`No trigger zones` 和按钮相对 View Controller 水平居中。
3. 旋转和分屏尺寸变化后仍保持水平居中。
4. 点击添加按钮后回调正常，产生数据后空状态正常移除。

## 7. Git 状态

本次未执行 commit、push、merge 或 PR 操作。

工作区在本次任务开始前已有未提交修改；这些修改均被保留，没有回退或覆盖。
