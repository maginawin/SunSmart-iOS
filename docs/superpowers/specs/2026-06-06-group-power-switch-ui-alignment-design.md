# Group Power Switch UI Alignment Design

## 背景

在 group 页面通过右上角选项菜单进入 switch 页面时，`Kinetic switch` 页面表现正常，但 `Battery Power Switch` 和 `AC Power Switch` 页面存在多处 UI 与交互不一致。

当前代码中，Kinetic switch 使用 `GroupSwitchsViewController` 的 section header + rows 结构：

- 每个 switch 是一个 table section。
- 折叠态只展示 `GroupSwitchsHeaderView`，高度为 `SCRYFrom(64)`。
- 展开态追加普通设置 rows 和 `GroupSwitchPanelViewCell`。

Battery/AC Power Switch 当前使用 `GroupPowerSwitchesViewController` + `GroupPowerSwitchCell`：

- 每个 switch 是一个 table row。
- header、设置 rows、panel preview、delete/save actions 都包在同一个 `UITableViewCell` 内。
- 展开/折叠依赖 cell 内部 stack view 显隐和 table 自动高度。

这种结构差异会直接导致折叠高度、展开点击区域、panel 背景、箭头位置和 row accessory 与 Kinetic 页面不一致。

## 目标

采用方案 1：将 Battery/AC group 页面改为与 Kinetic switch 一致的 `section header + rows + panel row` 结构，同时保留现有 Battery/AC 的业务逻辑。

修复后需要满足：

- Battery/AC switch 默认折叠时，行高与 Kinetic switch 折叠态一致。
- Battery/AC switch 展开后，panel type 图片外层背景、圆角、边框、边距和布局风格与 Kinetic switch 展开后的 panel 区一致，仅保留 Battery/AC 自身的 8-key panel 图片差异。
- 只有点击 switch name/header 那一行才切换展开/收起。
- 点击展开后的底部 panel 或 action 区不触发展开/收起。
- Battery/AC switch 右侧展开/收起按钮的图片、大小、位置与 Kinetic switch 一致。
- 展开后的 `More Settings` 右侧不显示摘要内容，只保留右箭头。
- 展开后各设置 row 的右箭头与 Kinetic switch 中 `CustomTableViewCell.cellStyle = .arrow` 的箭头一致。
- Battery/AC edit switch 页面中的各设置 row 右箭头也与 Kinetic switch 的 row 箭头一致。

## 非目标

- 不调整 Kinetic switch 已有业务逻辑。
- 不重构 Mesh 同步、开关保存、删除、启用/禁用流程。
- 不新增 Auth 信息。
- 不修改本地化文案语义；如无需新增文案，不改 localization 文件。
- 不做跨 target 的无关格式化或大范围重构。

## 设计

### 页面结构

`GroupPowerSwitchesViewController` 从单 section 多 row 调整为多 section：

- `numberOfSections` 返回 `viewModel.switchDatas.count`。
- 每个 section 对应一个 `PJEightKeySwitchData`。
- `viewForHeaderInSection` 展示 switch header。
- 未展开时，`numberOfRowsInSection` 返回 0。
- 展开时，根据当前 switch 状态返回设置 rows、panel preview row 和 action row。

折叠高度以 Kinetic 为基准：

- `heightForHeaderInSection` 返回 `SCRYFrom(64)`。
- `heightForFooterInSection` 返回 `0.01`。

### Header

Battery/AC 的 header 应对齐 `GroupSwitchsHeaderView`：

- 左侧显示 switch name。
- 第二行显示 MAC 或未绑定状态。
- 右侧显示 enable switch。
- enable switch 右侧显示 `arrow_up` / `arrow_down`。
- 箭头右边距、enable switch 与箭头间距使用 Kinetic 的约束基准。

为了降低对 Kinetic 页面的回归风险，优先新增 Battery/AC 专用 header view，复制 Kinetic 视觉布局并保留 Battery/AC 需要的 pending enable 状态；不直接改动 `GroupSwitchsHeaderView`。

### 展开 Rows

展开后的普通 row 使用与 Kinetic 一致的 `CustomTableViewCell` arrow 样式：

- `Panel`
- `Group`
- `Scene`，仅 scene panel 展示
- `More Settings`

`More Settings` row 不设置右侧内容文本，只显示标题和右箭头。Battery/AC edit switch 页面中的 `moreSettingsRowView` 已是 `.arrow`，需要同步检查其他 row 的 arrow 位置、尺寸与 Kinetic 一致。

### Panel Preview

Battery/AC 仍使用 `PJEightKeySwitchPanelView` 展示 8-key panel 图片和内容，但外层 table row 应对齐 Kinetic `GroupSwitchPanelViewCell` 的面板样式：

- row 背景为 `Background_Color`。
- 面板容器白底。
- 面板容器圆角、边框、左右边距、顶部边距参照 Kinetic。
- panel 图片/预览位于容器中间区域。
- delete/save action 不放在 header，也不参与展开/收起点击。

如果现有 `GroupPowerSwitchCell` 内的 `PJEightKeySwitchPanelView` 约束与 Kinetic 面板图片区差异较大，优先新建 Battery/AC 专用 panel/action cell，以减少对 edit switch 页面中 `PJEightKeySwitchPanelView` 的影响。

### 交互

展开状态仍由 `expandedSwitchIDs` 管理，但 key 从 row index 改为 switch id：

- 点击 header 时切换 `expandedSwitchIDs`。
- 普通 row 点击进入对应设置页面。
- panel preview row 不响应 table selection。
- action row 只响应 delete/save 按钮。
- 删除 switch 后从 `expandedSwitchIDs` 和 pending enable 集合中清理对应 id。

删除现有 `tableView(_:didSelectRowAt:)` 中点击整个 row 切换展开的行为，避免点击底部 panel 或 action 区收起 cell。

### 数据流

保留现有 `GroupPowerSwitchesViewModel` 职责：

- switch 数据加载与 copy。
- panel/group/scene/more settings 标题生成。
- 保存变更判断。
- virtual/real switch 的持久化和同步决策。

Controller 仅调整 table structure 与 row 类型，不改变保存、启用、删除、同步流程。

### 错误处理

错误处理沿用现有逻辑：

- 无权限展示 `no_permission`。
- 保存失败展示 `failed`。
- real switch 保存需要同步时继续走 `SyncDevicesViewController`。
- Battery switch 需要激活时继续走 `PJEightKeySwitchActivationFlow`。
- AC enable 继续直接发送 Tx Enable。

结构调整不改变错误文案和流程。

## 验证计划

静态验证：

- 检查 Battery/AC group 页面折叠态每个 section header 高度为 `SCRYFrom(64)`。
- 检查展开后普通 rows 高度为 `SCRYFrom(44)`。
- 检查 `More Settings` 在 group 页面和 edit switch 页面均只显示右箭头，不显示摘要内容。
- 检查 `didSelectRowAt` 不再承担展开/收起行为。

构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

人工验证建议：

- Group 页面进入 Kinetic switch，记录折叠态 header、展开箭头、row 箭头、panel 区风格。
- Group 页面进入 Battery Power Switch，对比折叠态、展开态和 More Settings row。
- Group 页面进入 AC Power Switch，执行同样对比。
- 在 Battery/AC 展开态点击 panel preview 和 delete/save 区，确认不会收起。
- 在 Battery/AC edit switch 页面检查 row arrow 与 Kinetic row arrow 一致。

