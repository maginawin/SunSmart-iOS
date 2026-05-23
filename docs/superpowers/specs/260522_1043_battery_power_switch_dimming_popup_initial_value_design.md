# Battery Power Switch Dimming Popup 初始值优化设计

## 背景

Battery Power Switch 页面中间开关面板支持模拟设备向虚拟组发送控制命令。长按 Dim Up 或 Dim Down 后会展示亮度 slider 弹窗，用户松手结束滑动后，App 发送 `LightLightnessSetUnacknowledged` 到 Battery Power Switch 的虚拟组。

当前 slider 的最终值是 50%，但弹窗出现后能看到 slider 从 0% 跳到 50% 的生硬变化。代码上，`PJEightKeySwitchDimmingPopupController` 在 `viewDidAppear(_:)` 中设置 `sliderView.value = 50`，此时弹窗已完成首帧展示，因此用户能看到初始 0% 到目标 50% 的变化。

## 目标

- 长按 Dim Up 后展示的 slider bar 默认显示 50%。
- 长按 Dim Down 后展示的 slider bar 默认显示 50%。
- 弹窗展示过程中不要出现 slider 从 0% 跳到 50% 的动画或跳变。
- 初始化 50% 只用于 UI 初始状态，不发送任何虚拟组亮度命令。

## 非目标

- 不修改 dim up / dim down 单击发送 `GenericDeltaSetUnacknowledged` 的逻辑。
- 不修改用户拖动 slider 结束后发送亮度命令的逻辑。
- 不修改 `BuoySliderView` 的全局 API 或其它页面的 slider 行为。
- 不调整弹窗样式、尺寸、文案、遮罩或展示动画。

## 方案

采用小范围修复：只调整 `PJEightKeySwitchDimmingPopupController` 的 slider 初始值设置时机。

`PJEightKeySwitchDimmingPopupController` 在 `setupUI()` 中完成 `sliderView` 加入视图、约束和基础配置后，立即把 `sliderView.value` 设置为 50。该设置发生在弹窗首帧展示之前，并且放在 `valueThrottleChangedCallback` 绑定之前，避免初始化默认值被误认为用户操作。

移除 `viewDidAppear(_:)` 中的 `sliderView.value = 50`。弹窗出现时，slider 已经处于 50% 状态，不再有可见的 0% 到 50% 变化。

## 数据流

1. 用户在中间开关面板长按 Dim Up 或 Dim Down。
2. `PJEightKeySwitchMonitorVC.presentDimmingPopup()` 创建 `PJEightKeySwitchDimmingPopupController`。
3. 弹窗在 `setupUI()` 中把 slider 初始值设置为 50%。
4. 弹窗展示首帧时 slider 已经显示 50%。
5. 用户拖动 slider 并结束后，`valueThrottleChangedCallback` 在 `ended == true` 时触发 `brightnessEndedAction`。
6. `PJEightKeySwitchVirtualGroupControlSender.sendBrightness(_:switchData:)` 将亮度转换为 Lightness 并发送到虚拟组。

## 错误处理

本次不新增错误处理。若 `switchData.linkGroupAddress` 为空，现有 `sendBrightness` 会直接返回，不发送 Mesh 命令。初始化 slider 默认值不依赖虚拟组地址。

## 验证

- 静态检查 `PJEightKeySwitchDimmingPopupController` 不再在 `viewDidAppear(_:)` 中设置 slider 值。
- 静态检查 50% 初始值设置发生在 `valueThrottleChangedCallback` 绑定之前。
- 编译验证：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

