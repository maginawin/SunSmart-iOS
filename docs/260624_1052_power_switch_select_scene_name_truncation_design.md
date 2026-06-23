# AC/Battery Power Switch Select Scene 名称截断设计

## 背景

AC Power Switch 与 Battery Power Switch 的 Edit 页面中，Scene Panel 会通过 `SwitchSelectScenePageController` 进入 Select Scene 页面。当前 Scene Cell 中，如果 Scene 名称过长，名称会超过最右侧选中/未选中按钮区域。

预期行为：

- Scene name 单行展示。
- 名称过长时尾部以 `...` 截断。
- name label 右边与右侧选中/未选中按钮左边至少间隔 8pt。
- 不改变现有选择、取消选择、回调和保存逻辑。

## 代码事实

Select Scene 页面由 `SwitchSelectSceneViewController` 承载：

- `PJPreAddEightKeySwitchesVC.selectScenesAction()` 从 AC/Battery Power Switch Edit 页面进入。
- `GroupPowerSwitchesViewController.selectScenes(id:)` 也复用同一个 Select Scene 页面。
- `SwitchSelectSceneViewController.tableView(_:cellForRowAt:)` 使用 `CustomTableViewCell`，设置 `cell.cellStyle = .icon`，再把 `iconImageView` 移到右侧作为选择按钮。

当前根因在布局约束：

- `CustomTableViewCell` 的 `.icon` 样式只给 `titleLabel` 设置 left 和 centerY。
- `SwitchSelectSceneViewController` 通过 `cell.iconX = tableView.width - 30 - SCRXFrom(8)` 把 `iconImageView` 放到右侧。
- `iconX` 的 didSet 会重新设置 `titleLabel` 为 left + centerY，仍没有 trailing 限制。
- 因此长 Scene name 没有可截断宽度，会直接绘制到右侧按钮区域。

## 方案比较

### 方案 A：局部修复 Select Scene cell 约束

在 `SwitchSelectSceneViewController` 的 cell 配置处，针对 Select Scene 页面补齐标题约束：

- `titleLabel.numberOfLines = 1`
- `titleLabel.lineBreakMode = .byTruncatingTail`
- `titleLabel.trailing <= iconImageView.leading - 8`
- 保持右侧 `iconImageView` 位置不变

优点：

- 改动最小，直接修复目标页面。
- 不影响 `CustomTableViewCell` 在其他菜单、列表、设置页里的通用表现。
- 因为 AC/Battery Edit 和 Group Power Switch 复用同一 Select Scene 页面，可同时覆盖这些入口。

缺点：

- 仍然继续复用通用 cell，没有为 Select Scene 创建专用 cell。

### 方案 B：新增专用 Switch Select Scene Cell

为 Select Scene 页面新增专用 UITableViewCell，明确包含 name label、select icon、separator。

优点：

- 组件边界更清晰。
- 长期维护性更好。

缺点：

- 对当前单点布局问题来说改动偏大。
- 需要额外迁移现有 cell 配置，风险和验证面更宽。

### 方案 C：修改 `CustomTableViewCell` 通用 `.icon` 样式

在通用 cell 的 `.icon` 样式内统一给 `titleLabel` 增加 trailing 或 max width。

优点：

- 会把同类 `.icon` 样式调整扩展到所有通用 cell 使用方。

缺点：

- `CustomTableViewCell` 使用范围很广，包含菜单、筛选、信息页、设备页等多个业务入口。
- 容易引入非目标页面的视觉变化，不符合本次聚焦修复范围。

## 推荐设计

采用方案 A：只在 `SwitchSelectSceneViewController` 中修复 Select Scene 页 cell 的 title label 约束。

实现要点：

1. 在 `cellForRowAt` 保持现有 scene、selected image、editable tint、selection callback 逻辑不变。
2. 设置 `titleLabel` 单行尾部截断。
3. 在设置右侧 icon 位置后，为 `titleLabel` 增加 trailing 到 `iconImageView.leading` 的约束，间隔 8pt。
4. 不修改 `CustomTableViewCell` 的通用实现，避免影响其他页面。
5. 不新增本地化 key，因为没有新增或修改用户可见文案。

## 影响范围

直接覆盖：

- AC Power Switch Edit -> Select Scene
- Battery Power Switch Edit -> Select Scene

因为同页复用，间接覆盖：

- Group Power Switch -> Scene Panel -> Select Scene

不覆盖：

- Scene 列表主页
- Schedule 选择 Scene 页面
- Device Information 中的 scene 展示
- 其他使用 `CustomTableViewCell.cellStyle = .icon` 的通用页面

## 验收标准

1. 超长 Scene name 在 Select Scene cell 中单行显示。
2. 超长 Scene name 结尾显示 `...`。
3. name label 右边与右侧选中/未选中按钮左边至少 8pt。
4. 已选中和未选中状态图标显示不变。
5. 点击 Scene 后选择/取消选择行为不变。
6. AC/Battery Power Switch Edit 入口可正常进入并回写选择结果。
7. Group Power Switch 复用入口没有出现布局或选择回归。

## 验证计划

- 静态检查：
  - 确认 `SwitchSelectSceneViewController` 中 title label 有 trailing 限制和尾部截断配置。
  - 确认没有修改 `CustomTableViewCell` 通用布局。
- 构建验证：
  - 运行 SunSmart iPhoneOS Debug 构建。
- 可选手动验证：
  - 准备一个超长名称 Scene。
  - 从 AC Power Switch Edit 页进入 Select Scene，检查名称截断和按钮间距。
  - 从 Battery Power Switch Edit 页进入 Select Scene，检查同样行为。
  - 从 Group Power Switch 的 Scene Panel 入口进入 Select Scene，确认没有回归。

## 自查结论

- 本设计范围足够小，适合单次实施计划。
- 没有新增文案、资源、target 配置或依赖。
- 方案不改变数据流和保存逻辑，仅补齐 Select Scene cell 的视觉约束。
- 8pt 间距和尾部省略已作为明确验收条件写入。
