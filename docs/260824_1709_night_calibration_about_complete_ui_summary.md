# Night Calibration About 与完成态 UI 实施总结

## 1. 实施结果

已按确认方案完成 Calibration 页面 Night Cal. 优化：

1. About 只在进入页面时根据当前 Active 初始化一次：Active 为 None 时展开，存在有效 Night / Sensor / Plane Active 时收起。
2. 页面内切换校准模式、选择 sensor、点击 Re-calibrate 或完成校准不会自动改变 About 展开状态，后续完全由用户手动控制。
3. Night Calibration Complete 已按 Figma `Card / Calibration Complete` 重建 Target level、Profile Update Notice 和 Re-calibrate 三个组件。
4. Notice 按 Profile 真实保存字段区分：occupancy/vacancy daylight 显示 Occupancy/Vacant 提示，纯 daylight 显示 Task level 更新提示。
5. pending-device 异常提示保留；无 pending 时正常完成态只呈现 Figma 三个组件。

## 2. UI 调整

### 2.1 Target level

- 改为 `#F6F8FF` 背景、14 圆角的 Value Card；
- 第一行合并显示 Target level 与 lux 值；
- 第二行显示带括号的取样亮度；
- 字号、颜色、行高、内边距和组件间距按 Figma 节点实现。

### 2.2 Profile Update Notice

- 改为 `#FFF9EF` 背景、14 圆角；
- 复用项目中与 Figma 路径完全一致的 `site_entry_sync_warning`；
- 正文使用橙色 11 pt 多行富文本；
- occupancy/vacancy daylight 中的 Vacant / 空置亮度使用 Semibold；
- 英文和简体中文文案同步更新。

### 2.3 Re-calibrate

- 改为 1 pt 灰色边框、14 圆角的整行按钮；
- 文字恢复一级正文色，并按 Figma 使用 14 pt、20 pt 行高；
- 导入 Figma 原始 16×16 disclosure SVG；
- 整行继续触发既有 Re-calibrate 草稿逻辑。
- 内部文字与箭头不单独成为 VoiceOver 焦点，辅助功能只聚焦整行按钮。

## 3. 修改范围

业务与 UI：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- `SunSmart/Main/Group/View/LightSensorCalibrationAboutView.swift`
- `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift`

本地化与资源：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart/Assets.xcassets/Common/night_calibration_disclosure.imageset/`

契约：

- `Tests/Group/NightCalibrationWorkflowContractTests.swift`
- `scripts/check_night_calibration_workflow.sh`

未修改 SDK、Profile 存储、数据库、导入导出、Night 校准计算、publication、Configuring、STOP/RETRY/CANCEL 或 Auto 恢复流程。

## 4. 回归保护

Workflow 契约新增检查：

- About 的入口初始化调用只允许出现一次；
- Night 完成态保留 Target、Notice、Re-calibrate 与 pending 状态；
- 纯 daylight 与 occupancy/vacancy daylight 使用不同 Notice；
- 英文和简体中文新增 Key 必须同步存在；
- warning 与 disclosure 资源名称正确；
- disclosure SVG 的尺寸、路径和颜色必须与 Figma 一致。
- Re-calibrate 文字使用设计行高，内部装饰子视图不产生重复 VoiceOver 焦点。

新增契约先因资源和入口状态缺失而失败，实施后通过。

## 5. 验证结果

以下均通过：

- `scripts/check_night_calibration_workflow.sh`
- `scripts/check_night_calibration_persistence.sh`
- `git diff --check`
- SunSmart：Debug、iphoneos、generic iOS、关闭签名构建
- Archipelago：Debug、iphoneos、generic iOS、关闭签名构建
- SLG Sync Plus：Debug、iphoneos、generic iOS、关闭签名构建
- SylSmart：Debug、iphoneos、generic iOS、关闭签名构建
- 四个已构建 App 的 `Assets.car` 均包含 `night_calibration_disclosure`

四个构建只有既有 AppIntents metadata extraction skipped 警告，没有编译或 Asset Catalog 错误。

## 6. 待真机验收

本轮未进行真实 UI/设备验收，仍需确认：

- Active None 与已有 Active 两类入口的 About 初始展开状态；
- 用户手动切换 About 后，Segment、sensor、Re-calibrate 和校准完成不会覆盖该状态；
- English 与简体中文在窄屏下的 Notice 换行和高度；
- Re-calibrate 整行点击、按压反馈和 disclosure 对齐；
- VoiceOver 读取 About Expanded/Collapsed 与 Re-calibrate；
- pending 大于 0 时的额外提示布局；
- 真实 Night 校准后 Target、Occupancy/Task Notice 与保存数据一致。

编译与静态契约不能证明像素级视觉、手势、BLE Mesh ACK 或固件行为。
