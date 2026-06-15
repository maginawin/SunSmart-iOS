# Light control page 顶部与 OnOff 间距优化

## 需求

- iPad 与 iPhone：
  - 顶部 `lightGrayBgView` 组合控件或 `UpDownLightView` 顶部，与右上角 Relay Switch 组件底部的间隔改为 `0`。
- iPhone：
  - `OnOffBtn` 顶部与上方控件底部间隔改为 `30`。
  - `OnOffBtn` 底部与下方控件顶部间隔改为 `8`。

## 实现

- `lightGrayBgView.top` 从 `relaySwitch.bottom + 20` 改为直接等于 `relaySwitch.bottom`。
- `UpDownLightView.top` 继续跟随 `lightGrayBgView.top`，因此自动使用相同顶部间距。
- iPhone 上：
  - up/down light：`onoffBtn.top = upDownRatioView.bottom + 30`。
  - 普通 light：`onoffBtn.top = brightnessView.bottom + 30`。
  - `controlPanelView.top = onoffBtn.bottom + 8`。
- iPad 上保留原有 `OnOffBtn` 与下方控制区间距，只应用顶部 Relay Switch 间距调整。

## 验证

- 检查 `DeviceLightViewController` 中 SnapKit 约束是否只改变目标间距。
- 使用 iPhoneOS `xcodebuild` 验证编译。
