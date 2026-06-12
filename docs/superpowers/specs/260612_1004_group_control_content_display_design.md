# Group Control Content Display 设计

## 背景

`Site - Space - More - Content Display` 已经提供两个 Space 级控制页设置：

- `showCCTQuickButtons`
- `controlType`

单设备 light control 页面已经通过 `DeviceLightControlPanelView` 消费这两个设置。本轮需求是在 Group 控制页面复用同一个控制面板组件，让 Group 页支持 CCT quick buttons 和 Simple/Detailed control type，同时保持 Group 页现有上半部分布局、成员分页、On/Off、Auto 和底部 sensor 抽屉行为。

## 目标

- Group 控制页复用 `DeviceLightControlPanelView` 展示亮度、色温、CCT quick buttons 和 Detailed 输入入口。
- Group 页根据 `space.showCCTQuickButtons` 和 `space.controlType` 展示与 light device control 页面一致的控制面板样式。
- Group 页只有底部控制面板区域在高度不足时可滚动；上方 collection、On/Off、Auto 不参与滚动。
- `DeviceLightControlPanelView` 顶部与 On/Off、Auto button 底部间隔为 `30`。
- 控制面板底部避让默认收起的 `GroupSensorView`，避免被 `40 + safeAreaBottom` 的底部抽屉遮挡。
- CCT quick buttons 数量使用 group 中所有 CCT 设备 effective CCT range 的最高值判断，复用现有 `group.effectiveCctRange`。
- Group CCT 目标色温超出任一组内 CCT 设备 effective range 时，提示用户：`Some devices have reached their color temperature limit.`

## 非目标

- 不修改 Content Display 设置页。
- 不新增 Group 专属 Content Display 配置。
- 不改变 `SpaceData`、数据库、导入导出或云同步字段。
- 不改变 Mesh 命令的 group address 控制语义。
- 不修改 light device control 页面的既有行为。
- 不重构 Group 成员 collection、Auto 命令、sensor 抽屉或 emergency manual control block 逻辑。
- 不新增 Auth 信息。

## 当前代码事实

- `DeviceLightControlPanelView` 已封装 Simple/Detailed 样式、亮度 slider、CCT slider、CCT quick buttons、Detailed 数值入口回调。
- `DeviceLightControlPanelView.Configuration.cctQuickButtonValues` 当前规则为：
  - `cctRange.upperBound >= 6500` 时展示 `2700K, 3000K, 3500K, 4000K, 5000K, 6500K`
  - 否则展示 `2700K, 3000K, 3500K, 4000K, 5000K`
- `DeviceLightViewController` 已直接读取 `space.controlType` 和 `space.showCCTQuickButtons` 配置控制面板。
- `GroupViewController` 当前直接持有 `lightnessSlider` 和 `cctSlider`。
- `GroupViewController.updateUI()` 当前将亮度范围设置为 `profile.lightControlData.lowEndTrim...highEndTrim`。
- Group CCT slider 当前使用 `group.effectiveCctRange`，并通过 `group.clampEffectiveCct` 设置当前值。
- `group.effectiveCctRange` 当前是组内所有 `effectiveSupportCct` 设备 `effectiveCctRange` 的并集，已经符合 quick buttons 数量判断所需的最高值逻辑。
- `GroupSensorView` 默认收起高度为 `SCRYFrom(40) + kSafeAreaBottomHeight`，展开时会占据页面底部更大区域。
- Group 页当前 CCT 拖动通过 `MeshAPI.setGroupColorTemperatureState(address:temperature:)` 发送到 group address，不在手指结束时额外改为 ack 语义。

## 方案选择

采用“在 Group 页复用 `DeviceLightControlPanelView`，并只让底部控制区滚动”的方案。

备选方案：

- 将整个 Group 页面包进 `UIScrollView`：统一但风险高，会影响 collection 横向分页、左右切换 group 手势和底部 sensor 抽屉。
- 保留现有 `lightnessSlider` / `cctSlider`，在 Group 页重新手写 quick buttons 和 Detailed 样式：改动表面局部，但会复制设备页逻辑，后续两页样式容易分叉。

推荐方案的原因：

- 复用已经为设备页抽出的控制面板，保持 UI 展示规则一致。
- Group 控制器继续负责 group 数据、权限、Mesh 命令和本地状态更新，面板不直接依赖 `Group` 或 `MeshAPI`。
- 只让底部控制区滚动，能降低对现有 Group 页面手势和抽屉的影响。

## 布局设计

`GroupViewController` 新增：

- `controlScrollView`
- `controlContentView`
- `controlPanelView: DeviceLightControlPanelView`

布局规则：

- `controlScrollView.top = onoffBtn.bottom + 30`。
- `controlScrollView.left/right` 与当前 Group slider 一致：
  - iPhone 对齐 `collectionView`。
  - iPad 使用现有 `SCRXFrom(107)` 左右边距。
- `controlScrollView.bottom` 避让默认收起的 `GroupSensorView`，至少预留 `SCRYFrom(40) + kSafeAreaBottomHeight`。
- `controlContentView.width == controlScrollView.width`。
- `controlPanelView` 贴合 `controlContentView` 顶部、左右和底部。
- 当内容高度小于可见高度时，控制区不需要滚动。
- 当内容高度大于可见高度，或底部抽屉会挡住控制面板时，只有 `controlScrollView` 垂直滚动。

现有 `lightnessSlider` 和 `cctSlider` 会被控制面板替代，不再同时显示两套控制。Group 无亮度且无 CCT 能力时隐藏控制面板，保持现有空组和成员展示行为。

## 数据流

`GroupViewController.updateUI()` 继续作为主要刷新入口，组装 `DeviceLightControlPanelView.Configuration`：

- `controlType`: `space.controlType`
- `showCCTQuickButtons`: `space.showCCTQuickButtons`
- `showsBrightness`: `group.supportLightness`
- `showsCCT`: `group.effectiveSupportCct`
- `brightnessValue`: `Node.getLightness100(lightness: group.lightness)`
- `brightnessRange`: `group.info.profile.lightControlData.lowEndTrim...group.info.profile.lightControlData.highEndTrim`
- `cctValue`: `Int(group.clampEffectiveCct(UInt16(group.cct)))`
- `cctRange`: `Int(group.effectiveCctRange.lowerBound)...Int(group.effectiveCctRange.upperBound)`

`group.effectiveCctRange` 直接作为面板 CCT range，因此 quick buttons 5/6 个数量与现有 group CCT slider 范围保持一致。

## 交互设计

### 亮度

亮度即时变化：

- 更新 `group.lightness`。
- 更新 `group.isOn` 和 `onoffBtn.isSelected`。
- 更新组内节点的 `isOn` 和 `lightness`。

亮度限流发送：

- 沿用当前 Group 页逻辑，通过 `MeshAPI.setGroupLightnessState(address:lightness:)` 发到 group address。
- `ended == true` 时刷新可见 cell，保持当前行为。

Detailed 亮度输入：

- 复用设备页数字输入弹窗模式。
- 输入值按当前 group brightness range clamp。
- 更新面板、group 和组内节点后，发送 group lightness 命令。

### 色温

CCT slider 变化：

- 目标值先按 `group.effectiveCctRange` clamp。
- 更新 `group.cct`。
- 通过 `MeshAPI.setGroupColorTemperatureState(address:temperature:)` 发到 group address。
- 组内支持 CCT 的节点使用各自 `node.clampEffectiveCct(temperature)` 更新本地 temperature。
- `ended == true` 时刷新可见 cell，并执行 CCT 限制提示判断。

CCT quick button：

- 使用按钮原始值作为 group target。
- target 按 `group.effectiveCctRange` clamp 后更新面板和 group 状态。
- 组内支持 CCT 的节点继续按各自 range clamp。
- 发送一次 group color temperature 命令。
- 点击后执行 CCT 限制提示判断。

Detailed CCT 输入：

- 使用用户输入值作为 group target。
- target 按 `group.effectiveCctRange` clamp。
- 更新面板、group、组内 CCT 节点，并发送 group color temperature 命令。
- 确认后执行 CCT 限制提示判断。

所有入口前继续调用 `showEmergencyControlBlockedIfNeeded()`。若 emergency manual control blocked，保持现有提示，不更新 UI，不发送 Mesh 命令。

## CCT 限制提示

新增本地化 key：

- `group_cct_limit_reached_message`

英文文案：

- `Some devices have reached their color temperature limit.`

中文文案：

- `部分设备已达到色温限制。`

触发条件：

对 `group.nodes.filter { $0.effectiveSupportCct }` 检查本次操作的目标色温：

- `target < node.effectiveCctRange.lowerBound`
- 或 `target > node.effectiveCctRange.upperBound`

满足任一设备即提示一次。

触发入口：

- Quick button 点击后，使用按钮原始值判断。
- CCT slider `ended == true` 时，使用该次回调的 value 判断。
- Detailed CCT 输入确认后，使用用户输入值判断。

不在 slider 拖动过程中连续提示，避免 toast 频繁出现。真实发送值仍按 `group.effectiveCctRange` clamp，组内节点本地状态仍按各自 range clamp。

## 国际化

需要同步更新：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

新增 key 仅用于 Group 页的多设备限制提示，不替换设备页已有单设备 `cct_limit_reached_message`。

## 验收标准

- Group 页根据 `space.controlType` 展示 Simple 或 Detailed 控制面板。
- Group 页根据 `space.showCCTQuickButtons` 决定是否展示 CCT quick buttons。
- Group 无 CCT 能力时不展示 CCT slider 和 quick buttons。
- `group.effectiveCctRange.upperBound >= 6500` 时展示 6 个 quick buttons，否则展示 5 个。
- Quick button、CCT slider 松手、Detailed CCT 输入确认后，若目标色温超出任一组内 CCT 设备 range，提示 `Some devices have reached their color temperature limit.`。
- CCT slider 拖动过程中不连续提示。
- 小屏高度不足时，仅底部控制面板区域可滚动，并能避让默认收起的 `GroupSensorView`。
- On/Off、Auto、Group sensor 抽屉、左右切换 group、collection 横向分页行为不被控制面板滚动影响。
- iPhoneOS 构建通过：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 实现风险

- `DeviceLightControlPanelView` 当前在设备页使用，若为 Group 页调整内部布局，需要确认不会改变设备页既有表现。
- Group 页底部 sensor 抽屉使用约束和手动 frame 动画混合，控制区底部避让应优先依赖收起高度，避免参与抽屉展开动画。
- Group 页 collection 横向分页和页面左右切换手势应避免被新增 scroll view 覆盖到上半部分。
- `updateUI()`、`reloadCollectionItem(node:)`、收到 Mesh status 后的刷新路径都需要更新面板状态，避免旧 slider 替换后状态不同步。

## 后续计划入口

用户确认本规格后，下一步使用 `superpowers:writing-plans` 编写实现计划，默认按 Inline Execution 执行。
