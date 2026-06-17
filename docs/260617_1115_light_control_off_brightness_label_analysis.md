# Light Control Off Brightness Value Label Analysis

## 结论

问题真实存在。

Group control page 已能在 Off 状态把详细亮度滑条右上角 value label 展示为 `0%`，因为它在配置和 on/off 点击刷新时都会显式按 `group.isOn ? brightness : 0` 传入亮度值。

Light control page 仍可能展示 low-end trim，因为它的顶部亮度状态和 control panel 配置使用了不同的数据公式：

- 顶部 brightness label 使用 `node.isOn ? Node.getLightness100(lightness: node.lightness) : 0`
- control panel 配置直接使用 `Node.getLightness100(lightness: node.lightness)`

当灯 Off 且 Profile 有 low-end trim 时，SDK 的 `Node.lightness` setter 会把 `0` clamp 到 `node.lightnessRange.lowerBound`。因此 light control page 即使 `node.isOn == false`，control panel 仍会从 `node.lightness` 得到 low-end trim 对应百分比，最终右上角 value label 展示 low-end trim。

## 证据链

### Group control page

`GroupViewController.updateControlPanel()` 已经显式判断 group on/off：

- Off: `brightnessValue = 0`
- On: `brightnessValue = Node.getLightness100(lightness: group.lightness)`

`GroupViewController.onoffBtnClick()` 也用同样规则刷新 `controlPanelView.setBrightnessValue(...)`。

这解释了为什么 group 页已经符合预期。

### Light control page

`DeviceLightViewController.updateData()` 顶部亮度状态使用 `node.isOn` 判断，所以 Off 时顶部显示 `0%`。

但 `DeviceLightViewController.updateControlPanel()` 没有使用 `node.isOn` 判断，直接把 `Node.getLightness100(lightness: node.lightness)` 传给 `DeviceLightControlPanelView.Configuration.brightnessValue`。

`DeviceLightViewController.onoffAction()` 关灯时虽然执行了 `node.lightness = 0`，但 SDK 的 `Node.lightness` setter 会按 `lightnessRange` clamp：

- low-end trim > 0 时，写入 `0` 后实际存储为 `lightnessRange.lowerBound`
- 随后 `updateControlPanel()` 从 `node.lightness` 读到的就是 low-end trim

因此 shared `DeviceLightControlPanelView` 已经允许 `0%` 展示，但 light control page 上游没有传入 `0`，导致本次症状仍存在。

## 建议修复方向

继续沿用已确认的方案 A，不改 SDK 的 `Node.lightness` clamp，不改 slider 交互范围。

最小修复点放在 `DeviceLightViewController.updateControlPanel()`：

- 新增局部 `brightnessValue`
- Off 时传 `0`
- On 时传 `Node.getLightness100(lightness: node.lightness)`

这样 device light control page 与 group control page 的展示语义保持一致；`DeviceLightControlPanelView` 仍负责允许 `0%` 作为 Off 展示特例，slider thumb 仍受 `limitRange` 限制在 low-end trim 起点。

## 不建议的方向

- 不建议修改 SDK 的 `Node.lightness` setter，因为它是全局模型语义，影响面大。
- 不建议让 slider range 在 Off 时变成 `0...100`，这会削弱 low-end/high-end trim 的禁用区语义。
- 不建议只改 `DeviceLightControlPanelView`，因为当前问题的根因是 light control page 上游传入了 low-end trim，而不是 shared panel 不支持 `0%`。
