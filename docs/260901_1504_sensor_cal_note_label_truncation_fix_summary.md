# Sensor Cal. noteLabel 截断修复总结

## 修复结果

已完成 `LightSensorTargetSensorValueView` 英文说明文字在旧版 iOS 上可能只获得两行高度并显示 `tar...` 的聚焦修复。

本次没有固定三行或卡片高度，而是让 Label 始终按最终可用宽度计算完整多行高度：

- 将 `noteLabel` 保留为 View 的私有属性；
- 保持 `numberOfLines = 0`，明确使用 `.byWordWrapping`；
- 将垂直 Content Hugging 和 Compression Resistance 设置为 `.required`；
- 在 `layoutSubviews` 中根据 Label 实际宽度维护 `preferredMaxLayoutWidth`，宽度变化时使固有尺寸失效；
- 保留原有英文/中文文案、12pt Regular 字体、颜色、边距、Target value / LX / Use sensor reading 自适应布局以及 Dim level 交互。

## 回归保护

`Tests/Group/SensorCalibrationWorkflowContractTests.swift` 已新增多行说明文字契约，覆盖：

- 无限行和 word wrapping；
- required 垂直 Hugging/Compression Resistance；
- 使用实际 Label 宽度更新 `preferredMaxLayoutWidth`；
- 原 inputRow 自适应规则继续保留。

契约测试在实现前按预期失败，实现后通过。

## 自动验证

- `zsh scripts/check_sensor_calibration_workflow.sh`：通过；
- `zsh scripts/check_night_calibration_workflow.sh`：通过；
- `git diff --check`：通过；
- SunSmart generic iPhoneOS Debug 无签名构建：通过；
- Archipelago generic iPhoneOS Debug 无签名构建：通过；
- SLG Sync Plus generic iPhoneOS Debug 无签名构建：通过；
- SylSmart generic iPhoneOS Debug 无签名构建：通过。

四个 target 均使用 iPhoneOS 26.5 SDK 构建，最低部署版本仍为 iOS 15.0。本次没有修改本地化、资源、target 配置、依赖或 NordicSigMeshSDK。

## 尚待真机验收

当前 `xcrun xctrace list devices` 返回 `No devices available for the recording`，因此无法在本轮直接完成截图级布局验收。

仍需在 iPhone 11 / iOS 18.3.2 上确认：

1. English 下说明文字实际换为三行；
2. 末尾完整显示 `target.`，没有省略号；
3. Dim level 不下移到异常位置，卡片底部间距正确；
4. 切换 Night Cal.、Sensor Cal.、Plane Cal. 后内容高度正确重算；
5. 简体中文以及 iPhone 12/15 / iOS 26+ 没有布局回归。

自动化与构建结果证明源码契约和四品牌集成通过，不等同于上述真机 UI 验收。
