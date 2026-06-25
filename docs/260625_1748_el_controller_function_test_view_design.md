# EL Controller Function Test View 设计方案

## 背景

`CID 0x0A78 / PID 0x24C1` 的 EL Controller 在 `devices_config.json` 中归类为 `Lighting`，设备详情页进入 `DeviceLightViewController`。当前该设备同时命中 `node.isEmergencySignController`，因此详情页使用 EM Sign 专用 UI：顶部灯图、Identify 按钮、Relay 控件以及离线/repair 空态。

本次需求是在 EL Controller 设备页中新增两个本地 UI 状态循环卡片：

- `Function Test`
- `RX/TX Cable`

两个卡片只做本地 UI 状态循环，不发送 mesh/vendor 命令，不解析真实设备回包。

## 目标

- 将 `identifyButton.top` 从 `lightBgView.bottom + 160` 调整为 `lightBgView.bottom + 30`。
- 在 `identifyButton` 下方新增 `Function Test` 类型的 `ELControllerFunctionTestView`，间隔 30。
- 在 `Function Test` 卡片下方新增 `RX/TX Cable` 类型的 `ELControllerFunctionTestView`，间隔 16。
- 两个 `ELControllerFunctionTestView` 与屏幕左右间隔均为 16。
- 两个卡片均只在 EL Controller 设备页正常可用状态展示；离线或 repair 空态时隐藏。
- 使用已添加的 `function_test_icon` 和 `rx_tx_cable_icon` 图片资源。
- 所有新增用户可见文案支持英文和简体中文本地化。

## 非目标

- 不实现真实 Function Test 或 RX/TX Cable 检测协议。
- 不发送新增 mesh/vendor 命令。
- 不修改设备发现、设备分类、列表页或组页路由。
- 不改变 `node.isEmergencySignController`、`node.isSupportVendorIdentify`、Relay 读写逻辑。
- 不调整普通 Light 设备页布局。

## 入口与展示条件

入口仍在 `DeviceLightViewController` 的 EM Sign / EL Controller 专用 UI 分支内处理。

展示条件：

- `node.isEmergencySignController == true`
- `node.isKeybindComplete == true`
- `node.state == true`

当设备离线或需要 repair 时：

- 隐藏 `identifyButton`
- 隐藏 `Function Test` 卡片
- 隐藏 `RX/TX Cable` 卡片
- 保留现有离线/repair 空态逻辑

## 组件设计

新增自定义 View：`ELControllerFunctionTestView`。

组件使用一个大类型区分内容：

- `.functionTest`
- `.rxTxCable`

组件内部包含：

- 白色卡片容器
- Header
  - 左侧 icon
  - 标题
  - 可选 tag
  - 右侧按钮
- State 区域
  - 单状态 view
  - 多 fault 状态列表
  - loading spinner

推荐保留 `Function Test` 的 `FT` tag；`RX/TX Cable` 不展示 `FT` tag。

## 布局设计

页面布局：

- `identifyButton.top = lightBgView.bottom + 30`
- `Function Test` 卡片：
  - top = `identifyButton.bottom + 30`
  - left/right = 16
- `RX/TX Cable` 卡片：
  - top = `Function Test.bottom + 16`
  - left/right = 16
  - bottom 作为 `contentView` 的 EM Sign 分支底部约束

卡片内部布局按 Figma：

- 卡片圆角 16
- 白色背景
- 轻阴影
- Header：顶部 16、底部 12、左右 16
- State 区：左右 16、底部 16
- 单状态高度 52，圆角 14
- 多 fault 每项高度 40，间距 6，圆角 14
- loading 使用 `PJEightKeySwitchWaitingSpinnerView`，固定 24x24，不做缩放

## Function Test 状态机

点击右上角按钮按以下顺序循环：

1. normal
2. awaiting
3. test passed
4. lamp fault
5. battery fault
6. circuit fault
7. lamp fault + battery fault
8. lamp fault + circuit fault
9. battery fault + circuit fault
10. lamp fault + battery fault + circuit fault
11. normal

显示规则：

- normal：
  - 按钮文案：`Start`
  - 状态文案：`Tap "Start" to send command to device`
  - 灰色 state view
- awaiting：
  - 按钮文案：`Testing…`
  - 按钮半透明
  - 状态文案：`Awaiting device response…`
  - 显示 24x24 loading spinner
- test passed：
  - 绿色成功样式
  - 文案：`Test Passed`
- lamp fault：
  - 橙色 warning 样式
  - 文案：`Lamp Fault`
- battery fault：
  - 红色 fault 样式
  - 文案：`Battery Fault`
- circuit fault：
  - 红色 fault 样式
  - 文案：`Circuit Fault`
- 多 fault：
  - 每个 fault 单独一行
  - 每行高度 40
  - 行间距 6

## RX/TX Cable 状态机

点击右上角按钮按以下顺序循环：

1. normal
2. checkingConnection
3. connection normal
4. connection fault
5. normal

显示规则：

- normal：
  - icon：`rx_tx_cable_icon`
  - 标题：`RX/TX Cable`
  - 按钮文案：`Check`
  - 状态文案：`Tap "Check" to test sign panel connection`
  - 灰色 state view
- checkingConnection：
  - 按钮文案：`Checking...`
  - 按钮半透明
  - 状态文案：`Checking sign panel connection...`
  - 复用 Function Test awaiting 的 loading 布局
  - 显示 24x24 loading spinner
- connection normal：
  - 复用 Function Test 的绿色成功样式
  - 文案：`Connection Normal`
- connection fault：
  - 复用 Function Test 的红色 fault 样式
  - 文案：`Connection Fault`

RX/TX Cable 不提供组合 fault 状态。

## 按钮宽度

右上角按钮宽度根据文字内容自适应：

- 使用内容宽度加左右 padding
- 设置最小宽度，保证 `Start` / `Check` 不过窄
- `Testing…` / `Checking...` 不截断
- 高度固定 28
- 圆角使用胶囊样式

## 本地化

优先复用已有 Key：

- `Start`
- `check`
- `testing…`

新增 Key 覆盖以下文案，并同步英文、简体中文：

- `Function Test`
- `FT`
- `Tap "Start" to send command to device`
- `Awaiting device response…`
- `Test Passed`
- `Lamp Fault`
- `Battery Fault`
- `Circuit Fault`
- `RX/TX Cable`
- `Checking...`
- `Tap "Check" to test sign panel connection`
- `Checking sign panel connection...`
- `Connection Normal`
- `Connection Fault`

## 风险与处理

- 普通 Light 页面布局风险：新增 View 只接入 EM Sign / EL Controller 分支，不影响普通 Light。
- 滚动内容高度风险：将 `RX/TX Cable` 卡片作为 EM Sign 分支底部约束，避免隐藏的 `controlPanelView` 影响 content height。
- 资源 target 风险：新增图片资源已在 asset catalog 中，需要确认相关 target 能访问。
- 本地化风险：新增所有用户可见文案必须同步 `en` 和 `zh-Hans`。
- Loading 风险：复用 `PJEightKeySwitchWaitingSpinnerView`，固定约束为 24x24，不使用 transform 缩放。

## 验证计划

- 检查 `0x0A78 / 0x24C1` EL Controller 设备页：
  - Identify 按钮距 `lightBgView.bottom` 为 30
  - Function Test 卡片距 Identify 按钮 30
  - RX/TX Cable 卡片距 Function Test 卡片 16
  - 两张卡片左右距屏幕 16
- 点击 Function Test 按钮，确认完整状态循环。
- 点击 RX/TX Cable 按钮，确认完整状态循环。
- 检查离线和 repair 空态下两张卡片隐藏。
- 检查普通 Light 设备页不出现这两个卡片。
- 检查 Relay 控件仍按既有逻辑显示和刷新。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
