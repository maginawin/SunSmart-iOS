# Daylight 未校准时默认 Calibration Mode 分析与修复

## 结论

问题已修复。当前 App 在 daylight profile group 的 Calibration 页面中，如果当前 Group 没有有效的已校准光照传感器，会默认选中 **`Night Cal.`**。

修复前默认选中的是 **`Plane Cal.`**，与产品预期不一致。

## 修复前源码调用链

1. `LightSensorCalibrationViewController.viewDidLoad()` 先读取 `effectiveActiveCalibrationMode`。
2. `Profile.effectiveCalibrationMode(sensorCalibrated:)` 在没有有效已校准传感器时返回 `.none`。
3. `lightSensorMode(for: .none)` 返回 `nil`。
4. 页面通过 `lightSensorMode(for: effectiveActiveCalibrationMode) ?? .plane` 计算初始选中模式，因此最终选择 `.plane`，对应 `Plane Cal.`。
5. `LightSensorCalibrationModeView` 自身也把 segmented control 和无法解析的 selected mode 兜底为 `.plane`，但页面进入时的直接决定因素是第 4 步。

## 影响范围

- 影响未校准 Group 首次进入 Calibration 页时的模式默认选择。
- 已校准且保存了有效模式的 Group，仍会按已保存的 `Night Cal.`、`Sensor Cal.` 或 `Plane Cal.` 显示，不应因为修正未校准默认值而改变。
- `Active` 状态在未校准时仍应显示 `None`；“当前生效模式”与“准备执行的默认选中模式”是两个不同概念。

## 测试覆盖观察

现有 `NightCalibrationWorkflowContractTests` 覆盖 Night 校准结果提交、Auto 恢复门控、草稿状态和 About 初始展开，但没有约束“未校准时默认选中 `Night Cal.`”这一行为，因此当前 `.plane` 兜底未被测试发现。

## 修复边界

仅调整 Calibration 页面在 `effectiveActiveCalibrationMode == .none` 时的初始选择为 `.night`，并新增对应契约测试。没有修改 Profile 持久化默认值、旧数据 `nil` 的 `.planeCal` 兼容逻辑、校准算法或协议流程。

## 实施结果

- 未校准时，Calibration 页面默认选中 `Night Cal.`。
- 未校准时，`Active` 仍显示 `None`。
- 已校准时，仍按保存的有效模式初始化页面。
- 契约测试新增了未校准默认选择的约束。

## 验证结果

- `zsh scripts/check_night_calibration_workflow.sh`：通过。
- `git diff --check`：通过。
- `SunSmart` unsigned generic iPhoneOS Debug build：通过。
- `Archipelago` unsigned generic iPhoneOS Debug build：通过。
- `SLG Sync Plus` unsigned generic iPhoneOS Debug build：通过。
- `SylSmart` unsigned generic iPhoneOS Debug build：通过。

以上结果证明源码契约和四个品牌 target 的编译集成通过；尚未进行真机页面行为验收。
