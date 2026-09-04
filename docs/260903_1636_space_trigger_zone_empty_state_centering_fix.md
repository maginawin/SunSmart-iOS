# Space Trigger Zone 空状态水平居中修复

## 问题

在 iPad 的 `Space - More - Trigger Zone` 页面中，没有 Trigger Zone 时，`No Trigger zones!` 空状态组件没有相对页面可见内容区域水平居中。

## 根因

`EmptyDataView` 内部图片、文案和按钮已经相对自身容器居中。偏移来自最外层空状态容器：

1. `SpacePathTriggerZoneController` 在创建空状态时传入一次性的 `tableView.frame`。
2. 空状态被添加到控制器根视图，但没有约束到 `tableView`。
3. iPad 导航容器完成后续布局、旋转或分屏尺寸变化时，`tableView` 会更新，空状态仍保留创建时的旧 frame。
4. 空状态内容最终相对旧容器居中，导致视觉位置偏移。

## 修复方案

- 空状态创建时不再传入 `tableView.frame`。
- 创建后将最外层 `EmptyDataView` 四边约束到 `tableView`。
- 保留空状态内部布局、纵向偏移、按钮回调和 Table View 滚动状态。
- 不修改公共 `EmptyDataView`，避免影响其他页面。

## 修改范围

- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

不修改本地化、资源、依赖、target 配置、Trigger Zone 数据、添加流程、保存流程或 Mesh 同步。

## 验证计划

1. 先扩展现有空状态布局合同，要求 Space Trigger Zone 不依赖 frame 快照，并跟随 `tableView` 四边；确认修改前失败。
2. 实施最小布局修复后重新运行合同测试。
3. 运行相关 Trigger Zone 回归合同和差异检查。
4. 使用 generic iPhoneOS、Debug、关闭代码签名构建主 `SunSmart` scheme。
5. 检查是否有可用的真实 iPad 布局验证环境；如当前环境没有连接设备，明确保留真机视觉验收边界。

## 验收点

- iPad 无 Trigger Zone 时，空状态图片、文案和按钮整体相对 Table View 水平居中。
- 旋转或分屏尺寸变化后仍保持水平居中。
- Add trigger zone 按钮行为不变。
- 创建或删除 Trigger Zone 后，空状态显示与隐藏行为不变。

## 实施结果

- 已移除 Space Trigger Zone 空状态创建时的一次性 `tableView.frame`。
- 已将最外层空状态四边约束到 `tableView`，使其随 iPad 页面最终布局、旋转和分屏尺寸变化自动更新。
- 已扩展既有布局合同，将 Space Trigger Zone 纳入 Sequence、Group Trigger Zone 相同的空状态约束检查。
- 未修改公共 `EmptyDataView`、本地化、资源、依赖、target 配置或 Trigger Zone 业务流程。

## 验证结果

### RED → GREEN

- 修改生产代码前，新增合同按预期失败：Space Trigger Zone 空状态仍依赖一次性 Table View frame。
- 完成修复后，`GroupPathSequenceDeviceAddViewContractTests` 通过。

### 相关回归

- `SpaceTriggerZoneFollowupContractTests`：通过。
- `PathTopologyPersistenceContractTests`：通过。
- `git diff --check`：通过。
- 额外运行的 `PathSaveSelectionClearingContractTests` 失败。失败来自该合同仍查找旧的容量校验调用，而当前 Group SAVE 已改为生命周期协调器入口；本次空状态修改未涉及 Group SAVE、选择清理或该合同文件，因此未扩大范围处理。

### 多 target 构建

以下 scheme 均使用 Debug、generic iPhoneOS、关闭代码签名构建通过：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

构建存在工程原有的资源命名、废弃 API、并发隔离和重复 Sources 等警告；本次修改没有新增对应代码。

## 真机布局验收边界

当前环境能发现已配对的真实 iPad，但用户未指定允许安装和启动测试的具体设备，工程也没有现成 UI Test scheme。本次未擅自向任何 iPad 安装 App，因此以下实际视觉验证仍待完成：

1. 进入 `Space - More - Trigger Zone`，确认无数据空状态水平居中。
2. 横竖屏切换后确认仍水平居中。
3. 分屏宽度变化后确认仍水平居中。
4. 点击 Add trigger zone，确认交互路径不变。
