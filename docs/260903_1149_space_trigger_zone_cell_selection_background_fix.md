# Space Trigger Zone Cell 选中背景修复

## 问题

在 `Space > More > Trigger Zone` 页面点击 Zone 行左右留白时，Cell 会出现 UIKit 默认的行选中背景。

## 原因

页面的 `UITableView` 保留了默认行选择能力。Zone 的业务选中并不依赖 Table View 行选择，而是由 Cell 内部 `UICollectionView` 的点击手势触发，并通过黄色边框展示。因此，左右留白触发的是多余的 `UITableViewCell` 选中态。

## 修改方案与范围

- 在 `SpacePathTriggerZoneController` 创建 Table View 时关闭行选择。
- 保留 Cell 内部 Zone 点击手势、黄色边框、设备菜单及拖放逻辑。
- 不修改共享的 `GroupPathSequenceTriggerZoneViewCell`，因此不会改变 Group Trigger Zone 页面现有行为。
- 不涉及约束、本地化、资源、Target 配置、依赖或 SDK 修改。

## 回归覆盖

- 在 `SpaceTriggerZoneFollowupContractTests` 中新增契约，要求 Space Trigger Zone 表格禁用行选择。
- 修复前契约按预期失败，修复后通过。
- `GroupPathSequenceDeviceAddViewContractTests` 通过，确认共享 Add View 与相关布局契约未受影响。
- `git diff --check` 通过。
- Generic iPhoneOS Debug 无签名编译通过：
  - SunSmart
  - Archipelago
  - Lumineux
  - SylSmart
  - SLG Sync Plus

## 验收边界

当前环境没有可用真机，无法执行实际点击与视觉验收。需要在真机进入 `Space > More > Trigger Zone`，分别点击 Zone 行左、右留白，确认 Cell 不出现选中背景；再点击白色内容区域，确认 Zone 仍显示黄色选中边框且设备操作正常。
