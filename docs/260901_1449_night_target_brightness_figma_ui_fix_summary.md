# Night Target Brightness Figma UI 修复总结

## 1. 完成内容

已按 Figma 节点 `519:14714` 修复 `Night Cal.` 未完成态的 `Target Night Brightness` 卡片：

- 卡片纵向顺序调整为 `Target Night Brightness` → `Dim level` → Calibration Learning 说明；
- Dim level 位于标题下方 16 pt；
- 说明位于 Dim level 下方 20 pt，卡片底部内边距 24 pt；
- 卡片不使用固定高度，由标题、Dim level 和多行说明的完整约束链自动撑高；
- 标题使用 14 pt Regular、20 pt 行高；
- 说明使用 12 pt Regular、19.5 pt 行高和 `AssistText_Color`；
- 英文说明已替换为需求指定的 Figma 文案，简体中文已同步国际化。

## 2. 变更边界

业务实现只涉及：

- `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift` 中的 `LightSensorTargetNightBrightnessView`；
- `SunSmart/en.lproj/Localizable.strings` 中的 `calibration_target_night_brightness_note`；
- `SunSmart/zh-Hans.lproj/Localizable.strings` 中的 `calibration_target_night_brightness_note`；
- `Tests/Group/NightCalibrationWorkflowContractTests.swift` 中的 Night 卡片回归合同。

未修改：

- `LightSensorCalibrationDimLevelView` 共享组件；
- `LightSensorTargetSensorValueView`；
- Plane Cal. 的 ON/OFF 输入 View；
- `LightSensorCalibrationViewController` 的模式显隐和校准业务逻辑；
- SDK、Assets、target 配置和依赖。

实施期间工作区原有的 Calibration 确认弹窗中英文文案改动已保留。

## 3. 回归保护

Night 合同测试新增以下约束：

- Dim level 必须直接连接标题底部；
- 说明必须连接 Dim level 底部，并负责闭合卡片底部约束；
- Night 卡片不得增加固定高度；
- 说明必须保留多行、12 pt 和 19.5 pt 行高；
- 英文和简体中文说明必须与已确认文案一致。

## 4. 验证结果

已通过：

- `zsh scripts/check_night_calibration_workflow.sh`；
- English / 简体中文 `Localizable.strings` 的 `plutil -lint`；
- `git diff --check`；
- `SunSmart` Debug generic iPhoneOS unsigned 构建；
- `Archipelago` Debug generic iPhoneOS unsigned 构建；
- `SLG Sync Plus` Debug generic iPhoneOS unsigned 构建；
- `SylSmart` Debug generic iPhoneOS unsigned 构建。

`SLG Sync Plus` 第一次构建因 Xcode 服务日志权限异常而中止，并误报 workspace 无效；在允许 Xcode 正常访问其服务后使用相同 generic iPhoneOS 命令重试成功，未发现源码编译问题。

## 5. 尚未完成的真实 UI 验收

当前 `xcrun xctrace list devices` 返回 `No devices available for the recording`，无法按项目要求在真实设备上完成实际布局测试。因此当前结果证明：

- Night 专属源码结构和自适应约束合同正确；
- 中英文资源有效；
- 四个品牌 target 编译集成成功。

当前结果尚不能替代以下真实设备验收：

- 375 pt 及其他实际屏幕宽度下的最终卡片高度与换行效果；
- English / 简体中文的实际视觉间距、截断和滚动表现；
- Dim level 减号、滑条、加号的触摸与显示；
- 切换到 `Sensor Cal.`、`Plane Cal.` 后的截图级 UI 无变化确认。
