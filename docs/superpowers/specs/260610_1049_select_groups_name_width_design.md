# Select Group(s) Group Name 宽度修复设计

## 背景

在 kinetic switch、battery power switch、ac power switch 的 Edit 页面进入 `Select Group(s)` 后，iPad 上较长的 group name 只能展示到 cell 约一半宽度。用户预期该页面与 `Select Scene` 类似，在设备宽度允许时尽量展示更宽的名称，并且 group name 与右侧 group on/off 按钮之间保留 8pt 间距。

## 现状与根因

相关入口最终复用同一个 `SwitchSelectGroupsViewCell`：

- Kinetic switch edit 页通过 `DeviceSwitchViewController` 进入 `SwitchSelectGroupsViewController`。
- Battery/AC power switch edit 页通过 `PJPreAddEightKeySwitchesVC` 进入 `PJDeviceGroupSelectionViewController`。
- Group 维度 power switch 页面中的只读 group 展示也复用 `SwitchSelectGroupsViewController`。

`SwitchSelectGroupsViewCell` 当前将 `nameLabel` 约束为 `width <= SCRXFrom(200)`。在 iPad 上，table/cell 宽度会增长，但 group name 最大宽度仍被固定在约 200pt，因此出现名称区域只占 cell 一半的问题。

`Select Scene` 页面使用 `CustomTableViewCell`，右侧选择图标靠近 cell 右边缘，标题没有同样的 200pt 固定最大宽度限制，因此在宽屏设备上能展示更长文本。

## 目标

- `Select Group(s)` 中 group name 在 iPad 上使用更多可用宽度。
- group name 与右侧 group on/off 按钮的最小间距为 8pt。
- iPhone 仍保持单行展示和尾部截断，不改变 cell 高度。
- 同时覆盖 kinetic switch、battery power switch、ac power switch 的 Edit 页面。
- 不改变 group 选择、select all、on/off 控制、禁用态、排序和保存逻辑。

## 推荐方案

在共享的 `SwitchSelectGroupsViewCell` 中调整 `nameLabel` 约束：

- 保持左侧约束：`selectImageView.right + 8`。
- 移除 `width <= SCRXFrom(200)` 固定宽度上限。
- 增加右侧约束：`nameLabel.right <= onoffBtn.left - 8`。
- 保持 `nameLabel` 单行尾部截断。
- 给右侧 `onoffBtn` 保持较高水平压缩优先级，避免长名称挤压按钮。

该方案只调整共享 cell 布局，不需要分别修改 Kinetic、Battery/AC 两套 controller。因为三个 Edit 入口都复用同一个 cell，所以单点修改能覆盖所有目标页面。

## 备选方案

### 方案 B：只在 Battery/AC group selection 页面新建或定制 cell

优点是影响范围更窄；缺点是 Kinetic switch edit 页仍会保留同类宽度问题，不满足本次需求中三类 Edit 页面统一修复的范围。

### 方案 C：按 iPad 判断设置更大的固定最大宽度

优点是改动直观；缺点是仍然依赖硬编码宽度，横竖屏、分屏、未来容器宽度变化时仍可能不准确。

## 影响范围

直接影响：

- `SwitchSelectGroupsViewCell`
- `SwitchSelectGroupsViewController`
- `PJDeviceGroupSelectionViewController`

预期行为变化仅限于 `Select Group(s)` cell 中 group name 可用宽度变大。业务数据、选择回调、on/off 控制和同步逻辑不变。

## 非目标

- 不调整 `Select Scene` 页面。
- 不调整 `CustomTableViewCell` 通用布局。
- 不改变导航、底部 Done 按钮、Select All 行为。
- 不新增本地化、资源、target 配置或依赖。
- 不做无关 UI 重构。

## 验证计划

1. 静态检查 `SwitchSelectGroupsViewCell` 约束，确认 group name 右边界受 `onoffBtn.left - 8` 限制，不再受固定 200pt 宽度限制。
2. 检查三个入口仍复用该 cell：
   - Kinetic switch edit -> `SwitchSelectGroupsViewController`
   - Battery power switch edit -> `PJDeviceGroupSelectionViewController`
   - AC power switch edit -> `PJDeviceGroupSelectionViewController`
3. 运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
4. 如需视觉确认，再在 iPad 尺寸下检查长 group name 与右侧 on/off 按钮之间保留 8pt 间距，并且文本单行截断。

## 自检结论

- 没有未决占位项。
- 方案与根因一致：修复固定最大宽度约束。
- 范围足够小，可以作为单个实施计划执行。
- 关键行为边界明确：只改变展示宽度，不改变选择或控制逻辑。
