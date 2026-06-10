# Device Light Content Display Control 设计

## 背景

`Site - Space - More - Content Display` 已经提供两个 Space 级设置：

- `showCCTQuickButtons`
- `controlType`

数据层、设置页、本地保存、云同步已经存在。本轮需求是让支持亮度和色温的单设备主控制页消费这两个设置，并按 Figma 展示以下组合：

- `Show CCT quick buttons = disabled` + `Control style = Simple`
- `Show CCT quick buttons = enabled` + `Control style = Simple`
- `Show CCT quick buttons = disabled` + `Control style = Detailed`
- `Show CCT quick buttons = enabled` + `Control style = Detailed`

本轮只更新设备主控制页，不更新 Group 页、批量控制页、基础信息页或 Device Parameter Settings 设置页。但因为后续 Group 需要实现类似功能，本设计会抽出新的控制面板视图，避免把布局和交互继续散落在 `DeviceLightViewController` 中。

## 目标

- 新增 `DeviceLightControlPanelView`，承接亮度 slider、色温 slider、CCT quick buttons、Detailed 数值入口和输入弹窗触发。
- `DeviceLightViewController` 使用该面板替代当前直接持有的 `lightnessSlider`、`cctSlider` 底部控制布局。
- 控制页根据当前 `space.showCCTQuickButtons` 和 `space.controlType` 展示 Simple 或 Detailed 样式。
- CCT quick buttons 只在 Space 启用、设备按单设备展示语义支持 CCT、且当前控制页显示 CCT slider 时展示。
- 单亮度设备在 Detailed 样式下只展示 Detailed 亮度 slider。
- 支持亮度和色温设备在 Detailed 样式下同时展示 Detailed 亮度和 Detailed 色温 slider。
- 页面在小屏高度不足时可滚动，避免 quick buttons 或 Detailed 控件被底部安全区截断。
- 所有新增文字使用国际化。

## 非目标

- 不更新 Group 控制页实际 UI。
- 不更新 `DeviceLightBasicController` 及其表格控制 cell。
- 不更新多设备批量控制页。
- 不修改 Content Display 设置页。
- 不修改 `SpaceData`、数据库、导入导出和云同步字段。
- 不改变现有 Mesh 控制命令语义。
- 不新增 Auth 信息。

## 当前代码事实

- `DeviceLightViewController` 当前直接在 `setupUI()` 中创建灯图、状态行、开关按钮、`BuoySliderView` 亮度 slider 和 `BuoySliderView` 色温 slider。
- 当前主控制页使用固定底部约束布局，小屏高度不足时没有滚动容器。
- 亮度变更通过 `MeshAPI.setNodeLightnessState(address:lightness:ack:)` 下发。
- 色温变更通过 `MeshAPI.setNodeColorTemperatureState(address:temperature:ack:)` 下发。
- `node.singleDeviceDisplaySupportCct` 是单设备 UI 是否展示 CCT 的能力判断，受 `Change Control Page` 影响。
- `node.effectiveCctRange` 是当前设备的有效色温范围，受 `Absolute CCT Range` 影响。
- `node.supportDimming` 判断当前设备是否展示亮度控制。
- `SpaceControlType` 已有 `.simple` 和 `.detailed`。
- Figma 更新后，5 和 6 个 CCT quick buttons 均不包含 `4500K`，使用 `4000K`。

## 方案选择

采用“抽出 `DeviceLightControlPanelView`，设备页先接入，后续 Group 可复用”的方案。

备选方案：

- 在 `DeviceLightViewController` 内直接补 UI：改动最少，但会继续扩大控制器职责，不利于后续 Group 复用。
- 复用 `DeviceLightBasicController` 的 `DeviceLightControlViewCell`：该控件是表格样式，并带加减按钮和百分比式 CCT 映射，不符合本轮主控制页 Figma。

选择抽面板的原因：

- 亮度、色温、quick buttons、Detailed 输入属于同一个控制面板职责，应集中在一个 View 内维护布局状态。
- `DeviceLightViewController` 继续负责设备状态、Mesh 命令和导航，不直接拼底部控制控件。
- 后续 Group 页可以复用同一面板，只替换 value/range/capability 和发送回调。

## 组件设计

### DeviceLightControlPanelView

新增 UIKit 视图，职责包括：

- 根据配置展示亮度 slider。
- 根据配置展示色温 slider。
- 根据配置展示或隐藏 CCT quick buttons。
- 在 Detailed 模式展示标题和可点击值按钮。
- 向外暴露用户改动回调，不直接依赖 `Node` 或 `MeshAPI`。

输入数据建议封装为配置模型：

- `controlType: SpaceControlType`
- `showCCTQuickButtons: Bool`
- `showsBrightness: Bool`
- `showsCCT: Bool`
- `brightnessValue: Int`
- `brightnessRange: ClosedRange<Int>`
- `cctValue: Int`
- `cctRange: ClosedRange<Int>`

输出回调：

- 亮度即时值变化，用于更新页面状态和灯图。
- 亮度限流值变化，用于发送 Mesh 命令。
- 色温即时值变化，用于更新页面状态和灯图。
- 色温限流值变化，用于发送 Mesh 命令。
- 请求编辑亮度值。
- 请求编辑色温值。

面板不直接弹 `SRAlertView`。弹窗由 `DeviceLightViewController` 发起，这样 Group 页后续可按自己的控制器上下文复用同一面板。

### DetailedControlSliderView

在面板内部新增一个小型子视图，包装：

- 标题 label。
- 右侧可点击值 button。
- `BuoySliderView`。

Simple 模式可以继续直接使用 `BuoySliderView`，Detailed 模式使用该包装视图。两者都复用同一套 slider 回调。

### CCTQuickButtonsView

在面板内部新增 quick buttons 行，职责包括：

- 根据当前 quick button 数组生成按钮。
- 当前 CCT 值等于某个预设值时高亮该按钮。
- 点击按钮后回调目标 CCT 值。
- iPhone 宽度下按 Figma 横向展示，优先压缩间距，不换行。
- iPad 宽度下从左到右铺满可用宽度，间隔平分。

按钮样式：

- 高亮：背景 `#6667AB`，文字白色。
- 未选中：白色背景，`#ECECEC` 边框，文字 `#6667AB`。
- 尺寸按 Figma 约 48x32，圆角 16。

## 展示规则

### CCT 能力

设备主控制页使用 `node.singleDeviceDisplaySupportCct` 判断是否展示 CCT。若 Device Parameter 中 `Change Control Page = Single White`，即使设备真实支持 CCT，也不展示 CCT slider 和 quick buttons。

### CCT quick buttons

仅当以下条件同时满足才展示：

- `space.showCCTQuickButtons == true`
- `node.singleDeviceDisplaySupportCct == true`
- 当前页面展示 CCT slider

Quick button 值：

- `node.effectiveCctRange.upperBound >= 6500` 时展示 6 个：`2700K, 3000K, 3500K, 4000K, 5000K, 6500K`
- `node.effectiveCctRange.upperBound < 6500` 时展示 5 个：`2700K, 3000K, 3500K, 4000K, 5000K`

点击 quick button 后：

1. 将目标值按 `node.effectiveCctRange` clamp。
2. 更新色温 slider。
3. 更新 `node.temperature`。
4. 刷新灯图和状态文字。
5. 发送一次色温控制命令。

如果预设值低于有效范围下限或高于有效范围上限，仍显示固定预设文本，但实际下发值按设备范围 clamp。

### Control style Simple

Simple 模式保持现有主控制页体验：

- 不展示 Detailed 标题。
- 不展示右侧可点击数值按钮。
- 不使用 `DeviceSliderFunctionView` 的加减按钮控件组。
- 亮度和色温继续使用 `BuoySliderView`。
- 若 quick buttons 启用，在色温 slider 下方展示 quick buttons。

### Control style Detailed

Detailed 模式在 `BuoySliderView` 上方增加：

- 亮度标题：`Brightness`
- 亮度值按钮：例如 `100%`
- 色温标题：`Color Temp`
- 色温值按钮：例如 `6500K`

值按钮使用下划线样式和重要文字色 `#2E315D`。点击后由控制器弹输入框。

## 输入弹窗

弹窗复用现有 `SRAlertView` 输入能力，按 Figma 风格使用：

- 标题：`Brightness` 或 `Color Temp`
- 输入框：数字键盘
- 操作：`CANCEL`、`CONFIRM`

确认逻辑：

- 亮度输入按当前有效亮度范围 clamp。
- 色温输入按 `node.effectiveCctRange` clamp。
- 输入为空或无法解析时，不发送命令，并保持当前值。
- 输入大于最大值时，更新到最大值并发送命令。
- 输入小于最小值时，更新到最小值并发送命令。
- 输入在范围内时，使用输入值更新 slider 并发送命令。

亮度最小值采用当前 slider 有效范围，即 `Node.getLightness100(lightness: node.lightnessRange.lowerBound)`。最大值采用 `Node.getLightness100(lightness: node.lightnessRange.upperBound)`。

## 滚动布局

`DeviceLightViewController` 需要将主内容放入 `UIScrollView`：

- 顶层背景仍为 `Background_Color`。
- 灯图、状态行、开关按钮、控制面板都放入 scroll content view。
- content view 宽度等于页面宽度。
- 以最小内容高度撑开，若设备高度不足则允许滚动。
- 安全区底部预留空间，避免 quick buttons 与 home indicator 重叠。

小屏处理优先级：

1. 保持 Figma 视觉顺序。
2. 保持 slider 和 quick buttons 可触达。
3. 允许页面滚动。
4. 不缩小文字到难以阅读。

## 数据流

进入页面或 `viewWillAppear`：

1. 控制器从 `space` 读取 `showCCTQuickButtons` 和 `controlType`。
2. 控制器从 `node` 读取能力、亮度、色温和范围。
3. 控制器组装配置传给 `DeviceLightControlPanelView`。

用户滑动亮度：

1. 面板回调即时亮度值。
2. 控制器更新 `node.lightness`、`node.isOn`、关灯前亮度缓存和页面显示。
3. 面板回调限流亮度值。
4. 控制器调用现有 MeshAPI 发送亮度命令。

用户滑动色温：

1. 面板回调即时色温值。
2. 控制器按 `node.clampEffectiveCct` 更新 `node.temperature` 和页面显示。
3. 面板回调限流色温值。
4. 控制器调用现有 MeshAPI 发送色温命令。

用户点击 quick button：

1. 面板回调目标 CCT。
2. 控制器按有效范围 clamp。
3. 控制器更新面板、节点和页面显示。
4. 控制器发送色温命令。

用户在 Detailed 输入框确认：

1. 控制器解析并 clamp 输入值。
2. 控制器更新面板和节点。
3. 控制器发送对应 Mesh 命令。

设备状态回刷：

- `meshNetworkManager(_:deviceDataUpdate:)` 继续调用 `updateData()` 和面板值更新。
- 更新面板值时避免触发用户交互回调或重复发送命令。

## 国际化

新增或复用以下 key，英文和简体中文都需要同步：

- `brightness`
- `color_temp`
- `cancel`
- `confirm`

如果已有 key 能覆盖对应文案，优先复用，不新增重复 key。Figma 上的 UI 文案默认英文，但 App 内实际显示按当前语言国际化。

## 权限与错误处理

- 本轮控制页行为不新增权限判断，沿用现有设备控制页入口和可操作逻辑。
- 设备离线、未 keybind、修复入口等状态继续沿用现有 `DeviceLightViewController` 逻辑。
- 输入为空或非数字时不下发命令，保持当前值。
- Mesh 下发失败不在本轮新增错误 UI，沿用现有控制页即时控制行为。
- 若 Space 设置在页面展示期间变化，下一次进入或 `viewWillAppear` 重新读取配置。

## 验收标准

- `showCCTQuickButtons = false` + `controlType = simple` 时，设备主控制页保持当前 Simple 样式，不显示 quick buttons。
- `showCCTQuickButtons = true` + `controlType = simple` 时，色温 slider 下显示 CCT quick buttons，不显示 Detailed 标题和值按钮。
- `showCCTQuickButtons = false` + `controlType = detailed` 时，亮度和色温 slider 使用 Detailed 样式，不显示 quick buttons。
- `showCCTQuickButtons = true` + `controlType = detailed` 时，Detailed 控件下方显示 CCT quick buttons。
- CCT 上限大于等于 6500K 时显示 6 个 quick buttons：`2700K, 3000K, 3500K, 4000K, 5000K, 6500K`。
- CCT 上限小于 6500K 时显示 5 个 quick buttons：`2700K, 3000K, 3500K, 4000K, 5000K`。
- quick buttons 中不出现 `4500K`。
- `Change Control Page = Single White` 的设备不显示 CCT slider 和 quick buttons。
- 单亮度设备在 Detailed 模式下只显示亮度 Detailed slider。
- 亮度输入超范围时 clamp 到有效范围后更新 slider 并发送命令。
- 色温输入超范围时 clamp 到 `node.effectiveCctRange` 后更新 slider 并发送命令。
- 小屏设备可滚动查看完整控制面板。
- iPad quick buttons 从左到右平分间隔。
- 所有新增文字使用国际化。
- `SunSmart` iPhoneOS Debug 构建通过。

## 验证计划

- 静态检查：
  - 确认 `DeviceLightControlPanelView` 不直接依赖 `Node` 或 `MeshAPI`。
  - 确认 `DeviceLightViewController` 仍负责 Mesh 命令发送。
  - 确认 `DeviceLightBasicController`、Group 页和批量控制页未被修改。
  - 确认 quick button 固定值无 `4500K`。
  - 确认新增文字在英文和简体中文本地化文件中存在。
- 行为验证：
  - 覆盖四种 Content Display 组合。
  - 覆盖 Single White、Tunable White、单亮度、亮度+CCT。
  - 覆盖 CCT range 上限小于 6500K 和大于等于 6500K。
  - 覆盖 Detailed 输入框的低于最小值、范围内、高于最大值。
- 构建验证：
  - 运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
