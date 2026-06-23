# Power Switch Monitor Enable UISwitch 只读设计

## 背景

AC Power Switch 和 Battery Power Switch 的监控页底部 Settings 行展示一个 Switch Enable `UISwitch`。当前用户点击该开关后，会触发 `PJEightKeySwitchMonitorStatusSetView.enableChanged`，再由 `PJEightKeySwitchMonitorVC.startTxEnableUpdate(_:)` 进入 Enabled / Disabled 更新流程：

- Battery Power Switch：走激活与 Tx Enable 更新流程。
- AC Power Switch：直接发送 Tx Enable 更新。
- 未链接虚拟 Power Switch：直接更新本地状态并触发刷新与同步通知。

需求变更为：监控页底部 Settings 行的 Switch Enable `UISwitch` 只展示状态，不允许用户点击切换。底部弹窗收起与展开时都不允许点击生效。

## 目标

- 只禁止监控页底部 Settings 行的 Switch Enable `UISwitch` 点击。
- 保留 `UISwitch` 当前 Enabled / Disabled 的视觉样式，不显示系统 disabled 浅色样式。
- 点击该 `UISwitch` 区域不触发设备 Enabled / Disabled 更新。
- 点击该 `UISwitch` 区域不透传给底部 Settings 行，不导致弹窗展开或收起。
- 保留后续重新启用该功能所需的业务代码和发送流程。

## 非目标

- 不修改 Edit Switch 页面中的 Enabled / Disabled 编辑能力。
- 不删除 `startTxEnableUpdate(_:)`、Battery / AC Tx Enable 更新流程、未链接虚拟开关本地更新逻辑。
- 不改变底部 Settings 行其他交互，例如展开/收起和 Group Link 展示。
- 不调整 Power Switch 的设备协议、同步流程、本地化或资源。

## 方案

在 `PJEightKeySwitchMonitorStatusSetView` 内为 `enableSwitch` 添加一个透明触摸拦截层。

具体设计：

1. `enableSwitch` 继续使用 `setOn(state.isEnabled, animated: false)` 渲染真实状态。
2. `enableSwitch` 保持 `isEnabled = true`，避免系统 disabled 样式导致颜色变浅。
3. 新增透明 `UIControl` 覆盖在 `enableSwitch` 上方，用于消费触摸事件。
4. 拦截层不绑定业务 action，点击后不产生任何效果。
5. 保留 `enableSwitch.addTarget(...)`、`enableValueChanged(_:)` 和控制器中的 `enableChanged` 绑定，方便后续重新启用底部切换功能。
6. 展开区域中的 enable / disable 小开关仍作为不可交互图例，不需要额外修改。

## 数据流

修改前：

用户点击底部 `UISwitch` -> `enableValueChanged(_:)` -> `enableChanged` -> `startTxEnableUpdate(_:)` -> 发送或保存 Enabled / Disabled 状态。

修改后：

用户点击底部 `UISwitch` 区域 -> 透明拦截层消费触摸 -> 不触发 `UISwitch.valueChanged` -> 不进入 `startTxEnableUpdate(_:)`。

程序刷新 UI 时仍按原数据流展示状态：

`PJEightKeySwitchMonitorVC.updateUI()` -> `bottomView.configure(state:)` -> `enableSwitch.setOn(state.isEnabled, animated: false)`。

## 错误处理

本次改动不新增网络、协议或持久化操作，因此不新增错误处理。既有 Tx Enable 更新失败处理保留，后续如果重新启用底部开关仍可复用。

## 验证

- 静态检查 `PJEightKeySwitchMonitorStatusSetView` 中触摸拦截层覆盖 `enableSwitch`，且 `enableSwitch.isEnabled` 未被置为 `false`。
- 静态检查 `PJEightKeySwitchMonitorVC.startTxEnableUpdate(_:)` 和相关 Tx Enable 代码仍保留。
- 运行 `git diff --check`。
- 运行 iPhoneOS 编译：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
