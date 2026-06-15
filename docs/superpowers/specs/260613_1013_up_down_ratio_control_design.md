# Up/Down Ratio 控件设计

## 背景

本次需求是在单设备控制页中，为指定设备增加一个与 `DeviceLightControlPanelView` 色温滑条控件组相近的自定义 View，用于控制 up/down ratio。

目标设备为 Company ID `0x0A78`、Product ID `0x2491`。当前工程中该 PID 已存在于 `SunSmart/devices_config.json`，型号为 `SR-BL2421_SSV_2CH`，设备分类仍为 Lighting。该 PID 也已经包含在现有 `isExternalLightSensorCapableLuminaire` 判断集合中，本次不改变这类设备既有能力判断。

## 已确认需求

- 新控件标题为 `Up/Down Ratio`。
- Slider 值范围为 `0...100`，值代表 `upValue`。
- `downValue` 不独立存储，始终通过 `100 - upValue` 计算。
- 默认值为 `upValue = 50`，展示为 `50/50`。
- title label 与 value label 永远展示，不受 simple/detailed control type 影响。
- value label 不允许点击，不提供弹窗输入。
- Slider 滑动时，在 thumb 上方浮窗展示当前 `upValue/downValue`；停止滑动后隐藏。
- 下方快捷按钮为 `100/0`、`75/25`、`50/50`、`25/75`、`0/100`。
- Slider 当前值等于快捷按钮 up 值时，选中对应按钮；其它值不选中任何按钮。
- 点击快捷按钮后，Slider、value label、快捷按钮选中态同步更新。
- 控件需要暴露 `upValue` get/set、`downValue` get、`valueChanging` event、`valueChanged` event。
- 页面层需要预留事件接线，后续用于补设备命令。
- 当前实现只在页面层更新并保存本地 `upRatio`，不发送 Mesh/vendor 命令。
- `upRatio` 需要永久本地存储，但暂时不上传服务器，不进入 share/import 或 space cloud sync。

## 非目标

- 不改 `0x2492`、`0x2493`、`0x2494` 等其它 external light sensor capable luminaire PID 的设备页。
- 不修改 `DeviceLightControlPanelView` 的 simple/detailed 展示规则。
- 不新增 value label 输入弹窗。
- 不新增设备命令下发逻辑。
- 不把 `upRatio` 写入 `Node.export()` 或服务器同步 payload。
- 不调整 group 控制页。

## 方案对比

### 推荐方案：独立控件 + 复用现有 Slider 基础

新增 `DeviceUpDownRatioControlView`，复用现有 `BuoySliderView` / `CustomDeviceSlider` 的滑动、thumb、浮窗和限流事件基础。为 `BuoySliderView` 增加轻量 value formatter，使 ratio 控件的浮窗可以展示 `up/down`，同时不影响亮度和色温现有显示。

优点：

- 新控件边界清楚，只负责 ratio UI 与事件。
- 页面层可明确处理 `valueChanging` / `valueChanged`，后续补设备命令时不需要重构控件。
- 保持现有 slider 交互、浮窗和视觉资产一致。
- PID 特例不污染 `DeviceLightControlPanelView` 的通用配置模型。

缺点：

- 需要对 `BuoySliderView` 做一个小扩展，必须确认默认 formatter 不改变现有亮度/色温显示。

### 备选方案：放入 `DeviceLightControlPanelView`

将 ratio 控件作为 `DeviceLightControlPanelView` 的一部分，通过配置控制显示。

优点：

- 控制区都在同一个 View 中。

缺点：

- ratio 控件不受 simple/detailed 影响，与现有 `DeviceLightControlPanelView.Configuration` 的语义不一致。
- `DeviceLightControlPanelView` 已被 Group 页复用，PID 特例容易影响其它入口。
- 后续维护时容易把 ratio 当成通用 light control 能力。

### 备选方案：完全新写 Slider

不复用 `BuoySliderView`，直接为 ratio 新写 slider、浮窗和拖动事件。

优点：

- 不需要改现有 slider 类。

缺点：

- 重复实现 thumb 浮窗、事件和限流逻辑。
- 视觉和行为更容易与现有控件不一致。
- 后续修复 slider 通用问题时需要维护两套实现。

## 最终设计

采用推荐方案。

### 控件结构

新增 `DeviceUpDownRatioControlView`，作为独立 `UIView`：

- 顶部左侧 title label：`Up/Down Ratio`。
- 顶部右侧 value label：`upValue/downValue`。
- 中间 slider：范围 `0...100`，步进为 `1`。
- 底部 quick buttons：固定 5 个 pill button。

视觉对齐 Figma 节点：

- title 使用辅助文字色 `#64748B`。
- value 使用重要文字色 `#2E315D`。
- quick button 选中态使用主题色 `#6667AB` 和白色文字。
- quick button 未选中态使用白色背景、`#ECECEC` 边框、主题色文字。
- 控件宽度由页面约束决定，和 `DeviceLightControlPanelView` 保持一致。

### 控件行为

`upValue` setter 对输入做 `0...100` clamp，并同步：

- slider value；
- 顶部 value label；
- slider 浮窗文案；
- quick button 选中态。

`downValue` 只读，始终返回 `100 - upValue`。

滑动过程中：

- 更新顶部 value label。
- 更新 quick button 选中态。
- 浮窗展示当前 `upValue/downValue`。
- 触发 `valueChanging(upValue)`。

滑动结束时：

- 隐藏浮窗。
- 触发 `valueChanged(upValue)`。

点击 quick button 时：

- 更新 `upValue`。
- 触发 `valueChanging(upValue)`，让页面可即时刷新本地 UI 状态。
- 触发 `valueChanged(upValue)`，让页面保存本地持久化数据。

### 页面集成

在 `DeviceLightViewController` 中新增 `upDownRatioView`。

新增设备能力判断，例如 `node.supportsUpDownRatioControl`，只在以下条件成立时返回 true：

- `companyIdentifier == 0x0A78`
- `productIdentifier == 0x2491`

页面布局分两套：

目标设备：

- `upDownRatioView` 顶部约束到亮度/色温状态控件底部，间距 `20`。
- `upDownRatioView` 宽度与 `DeviceLightControlPanelView` 一致。
- `upDownRatioView` 底部到 `onoffBtn` 顶部，间距 `40`。
- `onoffBtn` 底部到 `DeviceLightControlPanelView` 顶部，间距 `16`。

非目标设备：

- `upDownRatioView` 隐藏。
- 保持现有 `onoffBtn` 到 `DeviceLightControlPanelView` 的布局，不改变其它设备页面。

页面事件处理：

- `valueChanging`：更新 `node.upRatio`，刷新本地 UI 状态，不发送设备命令。
- `valueChanged`：更新 `node.upRatio`，保存 `node.preConfiguration` 到本地数据库，不发送设备命令。

### 本地存储

在 `Node.PreConfiguration` 中增加 `upRatio`：

- 类型使用 optional Int 存储，getter 层默认回落为 `50`。
- setter 统一 clamp 到 `0...100`。
- 数据库表 `node_preConfiguration` 增加 `upRatio` 字段。
- 数据库迁移时若字段不存在则添加，默认值为 `50`。
- 读取旧数据时，如果字段不存在或为空，App 表现为 `50/50`。

不修改以下链路：

- `Node.export()`。
- `SpaceData.export()` 中的 node payload。
- share/import 中的 node JSON。
- `/sitespace/sync/spaceprops` 上传内容。

这样可以保证 `upRatio` 跨 App 重启永久保存，但不会同步到服务器。

## 风险与约束

- `BuoySliderView` 的 formatter 扩展必须保持默认行为不变，亮度仍显示百分比，色温仍显示 K。
- 目标 PID 已经是 external light sensor capable luminaire，页面新增 ratio 控件不能影响它现有的 ambient lux、calibration、profile 逻辑。
- `DeviceLightViewController` 当前布局较紧，目标设备插入新控件后需要确认小屏幕可滚动且控件不重叠。
- 如果后续补设备命令，应只在页面事件处理里增加发送逻辑，不把 Mesh 逻辑放进 ratio View。

## 验证

代码审查：

- 确认 PID gate 只匹配 `0x0A78 / 0x2491`。
- 确认其它 PID 不创建或不展示 ratio 控件。
- 确认 `DeviceLightControlPanelView` 原有配置逻辑未被 ratio 特例污染。
- 确认 `Node.export()` 和 share/import payload 未包含 `upRatio`。
- 确认 `Node.PreConfiguration` 旧数据默认回落为 `50`。

交互验证：

- 首次进入目标设备页，控件显示 `50/50`，`50/50` 快捷按钮选中。
- 滑动到 `60` 时，显示 `60/40`，无快捷按钮选中。
- 滑动中浮窗显示 `60/40`，停止滑动后隐藏。
- 点击 `75/25` 后，slider 移动到 `75`，value label 显示 `75/25`，`75/25` 按钮选中。
- App 重启后，目标设备页恢复上次保存的 `upRatio`。
- 非目标设备页面布局和行为保持不变。

构建验证：

- 使用 iPhoneOS build 验证：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
