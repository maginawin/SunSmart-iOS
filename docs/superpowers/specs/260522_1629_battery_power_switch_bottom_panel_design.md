# Battery Power Switch 底部面板 UI 优化设计

## 背景

Battery Power Switch 设备页底部有一个可收起/展开的 Settings 面板。用户提供了 Figma 设计，要求收起态修正 Enable 开关颜色和 Group link 图标，展开态按 Figma 重新对齐 UI。

本次设计只覆盖设备详情页底部面板的 UI 与交互表现，不修改 Switch Enable 的协议下发、数据库持久化、云同步和 activation flow。

## Figma 参考

- Unlinked icon：`https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=61-3890`
- 展开态，已绑定目标组：`https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=61-3830`
- 展开态，未绑定目标组：`https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=61-3874`

解析结果显示，展开态 sheet 的视觉结构为：

- 白色底部 sheet，顶部左右圆角 20pt，有上浮阴影。
- Header 行高度约 40pt，左侧为折叠箭头和 `Settings`，右侧为 `Group link` 和 `Enable`。
- 展开内容顶部为 `all status tag`，宽 335pt，高 32pt，背景 `#FAFAFA`，圆角 10pt。
- `all status tag` 固定展示 `Linked`、`Unlinked`、`Enable`、`Disabled` 四个图例项。
- 组信息区域标题为 `The groups it controls:`。
- 绑定目标组时展示组名列表，组名过长单行截断。
- 未绑定目标组时展示空状态文案 `Not connected to any group, switch-related functions cannot be performed.`

## 当前差异

收起态存在两个差异。

Enable 右侧的真实 `UISwitch` 当前使用系统默认样式，没有统一设置应用内开关主题色。它需要改成和其他 UISwitch 一致的颜色，避免在 Battery Power Switch 页面表现为默认色。

Group link 图标当前固定显示 linked 图标。未关联任何目标组时，需要显示 Figma 的 unlinked 图标，颜色使用辅助色 `#94A3B8`，图标尺寸为 16pt，放在 20pt 点击区域中。

展开态差异更大。

当前展开内容更像“当前状态详情”，会根据 linked/unlinked 状态改变图例颜色，并且内部 Enable Switch 可交互。Figma 设计要求 `all status tag` 是固定图例，linked 与 unlinked 状态下 UI 完全一致，且其中的 Switch 不可操作。

当前展开态使用真实 `UISwitch` 作为内部 Enable 展示，尺寸和 Figma 的 30x20 小开关不一致，也存在误触发 Enable 下发的风险。展开态应改为绘制型 mini switch 图例。

当前组列表直接放在面板中，没有独立滚动区域。目标组过多时，预期只滚动组列表区域，底部 sheet 自身高度固定。

当前展开态的字号、颜色、间距和阴影与 Figma 不完全一致，需要统一调整。

## 目标行为

收起态保持现有高度和交互，只调整视觉。

- 收起态高度保持 `40pt + safeAreaBottomHeight`。
- Enable 的真实 `UISwitch` 保持可操作，继续触发现有启用/禁用流程。
- Enable 的真实 `UISwitch` 在 pending 状态下保持不可操作。
- Group link 图标根据是否已绑定目标组切换 linked/unlinked 图标。

展开态改为固定高度和固定图例。

- 展开态高度使用 `330pt + safeAreaBottomHeight`。
- 展开态 header 的真实 Enable 开关仍可操作，行为与收起态一致。
- `all status tag` 内的 Enable/Disabled 小开关只是图例，不可操作，不触发任何下发逻辑。
- `all status tag` 在 linked 与 unlinked 状态下 UI 完全一致。
- 绑定目标组时，展示组名列表。
- 目标组过多时，只允许组列表区域滚动。
- 未绑定目标组时，展示空状态文案，不显示滚动组列表。

## 设计方案

采用局部改造 `PJEightKeySwitchMonitorStatusSetView` 的方案。

现有 `PJEightKeySwitchMonitorVC` 已经通过 `bottomView.configure(state:)` 传入 `groupNames`、`isGroupLinked`、`isEnabled` 和 `isPending`，并通过 `enableChanged` 处理真实 Enable 下发。这个数据流满足新 UI，不需要改变控制器和业务流程。

`PJEightKeySwitchMonitorStatusSetView` 继续负责底部面板的布局、展开收起、Group link 点击和 Enable 开关交互。修改集中在该 View 内部：

- 统一真实 `enableSwitch` 的主题色。
- 在 `configure(state:)` 中按 `isGroupLinked` 设置 header Group link 图标。
- 调整展开高度为固定 330pt 加 safe area。
- 重建 `all status tag` 的布局，使其固定显示四个图例项。
- 用自定义绘制型 mini switch 替代展开态内部真实 `UISwitch`。
- 将组名列表放入独立 `UIScrollView`。
- 按 Figma 调整颜色、字号、间距、圆角和阴影。

## 组件边界

`PJEightKeySwitchMonitorStatusSetView` 是本次主要修改点。

它继续公开：

- `configure(state:)`
- `isExpanded`
- `expandAction`
- `enableChanged`
- `groupLinkAction`

它不新增业务状态，不持久化数据，不直接发送 Mesh 命令。

内部可新增轻量私有视图，例如 mini switch 图例视图，用于画出 30x20 的开关图例。该视图不对外暴露，也不处理点击。

`PJEightKeySwitchMonitorVC` 原则上不改业务逻辑。如实现时发现需要刷新布局，只允许做最小范围的调用调整。

## 本地化

继续使用已有本地化 key：

- `settings`
- `neightkeyswitches_group_link`
- `enable`
- `disabled`
- `neightkeyswitches_linked`
- `neightkeyswitches_unlinked`
- `neightkeyswitches_groups_it_controls`
- `neightkeyswitches_group_empty_tip`

若现有英文或中文文案与 Figma 空状态不一致，应只更新对应本地化文案，不新增硬编码字符串。

## 验证计划

实现后需要验证以下状态：

- 收起态，已绑定目标组，Enable 开启。
- 收起态，未绑定目标组，Enable 开启。
- 收起态，Enable pending 时开关不可操作。
- 展开态，已绑定目标组且组数量较少。
- 展开态，已绑定目标组且组数量超过可见区域，只有组列表滚动。
- 展开态，未绑定目标组。
- 展开态 `all status tag` 中的小开关不可操作，不触发 `enableChanged`。
- App iPhoneOS Debug 编译通过。

## 非目标

本次不修改 Battery Power Switch 的协议命令。

本次不修改 Enable 下发、成功后持久化、失败回滚、云同步或 activation alert 流程。

本次不修改中间控制面板和电池刷新逻辑。

本次不处理 Figma 以外的其他页面视觉调整。
