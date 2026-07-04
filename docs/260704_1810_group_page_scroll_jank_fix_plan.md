# Group 页面设备列表滚动卡顿修复计划

## 目标

修复 Site > Space > Group 页面在 83 个设备 group 中滑动 collection view 卡顿的问题。修复范围限定在 Group 页面滚动性能、Group 页面刷新策略、`DeviceUpDownRatioControlView` 约束冲突，不改 SDK、不改 Mesh 收包链路、不改全局 `Group` 模型语义。

## 已确认根因

参考分析文档：`docs/260704_1803_group_page_collection_scroll_jank_analysis.md`。

核心结论：

- `DeviceUpDownRatioControlView` 的 quick buttons 存在确定 Auto Layout 冲突。
- Group 页对高频 `SensorStatus` 上报的 UI 刷新粒度过粗。
- 83 个成员让 `group.nodes` 扫描、layout attributes 重建、cell 配置成本被放大。
- cell 配置中的约束更新和自适应文本计算会进一步放大滚动期间主线程压力。

## 可选方案

### 方案 A：局部收口修复（推荐）

只修改当前问题链路上的最小集合：

- 修 `DeviceUpDownRatioControlView` 约束冲突。
- 收紧 `GroupViewController` 对 sensor-only message 的刷新路径。
- 对 Group 页面常用派生数据做轻量缓存。
- 只在必要时刷新可见 cell 和 group control panel。

优点：

- 风险最低，改动集中。
- 不影响 SDK、普通 Lights 页面、Scene/Profile/batch control 语义。
- 可以直接对当前日志中的两个主要信号做验证：约束冲突消失、sensor publish 不再触发不必要 collection item/control panel 更新。

缺点：

- 不是全局性能框架化治理。
- 如果后续其他页面也暴露相似问题，需要再按页面处理。

### 方案 B：Group 页面统一刷新调度器

在 `GroupViewController` 内引入统一 UI update scheduler，把所有 mesh message 转成 coalesced update，再批量刷新 sensor view、visible cell、control panel。

优点：

- 对高频上报更稳，后续扩展性更好。
- 可以天然合并同一 run loop 或短窗口内的多条消息。

缺点：

- 改动量更大。
- 需要更细地证明各种 group control、switch action、sensor publish、manual refresh 不被延迟或漏刷。
- 对当前问题来说偏重。

### 方案 C：全局 cell/layout 性能重构

改 `AlignCenterFlowLayout`、`DevicesViewCell`、`AdaptiveTextView` 等共享组件，让所有横向分页设备列表受益。

优点：

- 长期收益最大。

缺点：

- 影响面最大，容易波及 Lights、Groups、Scenes、Sensors、Switches 等多个页面。
- 与当前卡顿根因中的 sensor message 刷新粒度不完全同层。
- 不适合作为本次第一轮修复。

推荐采用方案 A。先解决确定冲突和错误刷新粒度，再根据复测结果决定是否补充方案 B 的轻量节流。

## 推荐实施范围

### 阶段 1：修复 `DeviceUpDownRatioControlView` 约束冲突

修改文件：

- `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`

计划：

- quick buttons 不再依赖 5 个固定宽度按钮加固定 spacing 的布局方式。
- 去掉 hidden/临时 0 宽高布局阶段会强制触发布局求解的调用。
- `upValue` 未变化时直接短路，避免重复刷新 slider、label 和 quick buttons。
- quick buttons selected state 未变化时不重复设置颜色和触发布局。

边界：

- 保留现有 5 个 quick button value：`100/0`、`70/30`、`50/50`、`30/70`、`0/100`。
- 保留 slider 取值语义和 callback 行为。
- 同步检查单灯 `DeviceLightViewController`，因为它也复用这个 view。

### 阶段 2：收紧 Group 页 sensor-only message 刷新路径

修改文件：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`

计划：

- 明确区分 sensor-only message 和 light/control message。
- `SensorStatus` 只更新 `GroupSensorView` 需要展示的 sensor 状态，不触发设备 collection item 刷新，也不触发 group control panel / up-down ratio UI 更新。
- switch action 仍保持现有 group-wide 刷新语义，因为它可能影响多个灯的本地状态。
- 只在 lightness、on/off、CCT、scene、switch action 等会影响设备格子或 group 控制面板的消息里刷新相关 UI。

边界：

- 不改变 `node.updateData(message:)` 的缓存更新。
- 不改变 sensor publish 接收和解析。
- 不改变 `GroupSensorView` 展示逻辑。

### 阶段 3：减少 Group 页面重复 O(n) 查找和派生计算

修改文件：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`

计划：

- 在 Group 页面内维护局部派生缓存，例如 node address 到 index 的映射、支持 CCT 的节点集合、支持 up/down ratio 的节点集合。
- group 切换、成员变更、`updateUI()` 时重建缓存。
- `reloadCollectionItem(node:)` 优先通过 address-index cache 定位 cell。
- group control panel 更新只在相关数据发生变化时执行。

边界：

- 不修改 `Group.lightness`、`Group.isOn`、`Group.effectiveSupportCct` 等共享模型属性。
- 缓存只属于 `GroupViewController`，避免影响 Scene/Profile/batch control 的现有语义。

### 阶段 4：必要时补轻量 UI 合并

修改文件：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`

触发条件：

- 阶段 1-3 后，复测仍能看到滚动期间大量 UI 刷新或掉帧。

计划：

- 在当前 run loop 或短时间窗口内合并同类 UI 刷新。
- collection view 正在 dragging/decelerating 时，非关键的不可见 cell 刷新延后到滚动结束。
- 关键交互反馈，例如用户手动点 group on/off、brightness、CCT，仍立即更新。

边界：

- 不延迟用户主动操作的视觉反馈。
- 不延迟 sensor header 的当前状态展示。

### 阶段 5：必要时降低 cell 配置成本

修改文件：

- `SunSmart/Main/Group/View/GroupDeviceViewCell.swift`
- `SunSmart/Main/Device/View/DevicesViewCell.swift`
- `SunSmart/Common/View/AdaptiveTextView.swift`

触发条件：

- 阶段 1-4 后，复测仍显示 cell 配置是主要瓶颈。

计划：

- 避免每次设置同一 node 状态都重复更新 SnapKit 约束。
- `AdaptiveTextView` 在 text、bounds、font 参数未变化时短路。

边界：

- 这一步触及共享 cell / text view，默认不纳入第一轮实现，除非复测证据证明仍需要。

## 验证计划

### 静态检查

- `git diff --check`
- 检查 `DeviceUpDownRatioControlView` 中不再有会在设置 value 时强制触发 hidden/0-size 布局求解的路径。
- 检查 `GroupViewController` 中 `SensorStatus` 不再落入 collection item/control panel 刷新路径。

### 构建验证

按项目规则运行 iPhoneOS build：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如修改共享控件后影响多 target，再同步验证相关 target。

### 手工验证

使用同一类 83 设备 group 复测：

- 进入 Group 页面后，不再出现 `DeviceUpDownRatioControlView` 的 Auto Layout 冲突日志。
- 滑动 collection view 时，sensor publish 仍能更新底部/传感器区域状态。
- 滑动 collection view 时，不应因 sensor-only message 持续刷新设备格子或 group control panel。
- group on/off、brightness、CCT、up/down ratio、switch action 仍能即时更新可见 UI。
- 长按设备进入单灯详情仍正常，单灯 up/down ratio 控件显示与操作不受影响。

## 风险与控制

- `DeviceUpDownRatioControlView` 是共享控件，必须同时检查 Group 页和单灯详情页。
- `GroupViewController` 中 switch action 和 sensor message 不能混淆；switch action 仍可能代表多个设备状态变化，不应按 sensor-only 处理。
- 局部缓存只放在页面层，不改 `Group` 共享模型，避免影响 Scene/Profile/batch control。
- 先完成阶段 1-3 并复测，再决定是否进入阶段 4-5。

## 确认点

建议确认使用方案 A，并按阶段 1-3 作为第一轮实现范围。阶段 4-5 作为复测后再决定的后备优化，不在第一轮默认实现。

