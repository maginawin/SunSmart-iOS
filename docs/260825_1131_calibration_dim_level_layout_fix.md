# Calibration Dim level 布局修复

## 问题现象

Calibration 页面中，Dim level 下方的减号按钮、滑条和加号按钮全部挤压并重叠在左侧。

## 根因

`LightSensorCalibrationDimLevelView` 为加号按钮设置 SnapKit 约束时，将 `right` 与 `centerY` 通过同一条链式表达式都绑定到了减号按钮。

这会产生两个直接后果：

- 加号按钮的右边缘与减号按钮的右边缘重合，两个按钮发生重叠。
- 滑条左边缘位于减号按钮右侧，右边缘却被约束到已重叠的加号按钮左侧，导致滑条可用宽度为负，Auto Layout 必须打破约束并将控件挤在左侧。

## 修复

- 将加号按钮的右边缘约束改为父视图右边缘。
- 保留加号按钮与减号按钮的垂直居中对齐。
- 未调整控件尺寸、间距、颜色、资源、交互逻辑、本地化或 Calibration 业务流程。

修复后的水平布局关系为：减号按钮固定在左侧，滑条占据中间可用宽度，加号按钮固定在右侧。

## 回归保护

扩展 `SensorCalibrationWorkflowContractTests`，限定 Dim level 控件必须满足以下结构约束：

- 加号按钮右对齐父容器。
- 加号按钮垂直对齐减号按钮。
- 禁止再次将加号按钮的右边缘绑定到减号按钮。

测试在业务修复前按预期失败，修复后通过。

## 验证结果

- `scripts/check_sensor_calibration_workflow.sh`：通过。
- `git diff --check`：通过。
- SunSmart，Debug，iphoneos，关闭签名：构建通过。
- Archipelago，Debug，iphoneos，关闭签名：构建通过。
- SLG Sync Plus，Debug，iphoneos，关闭签名：构建通过。
- SylSmart，Debug，iphoneos，关闭签名：构建通过。

构建期间 workspace 当前解析到本地 `NordicSigMeshSDK`；本次修复未修改 SDK 或依赖配置。

## 待人工验收

自动化约束检查和编译无法替代真机视觉与触摸验收。建议在至少一个实际品牌 App 的 Calibration 页面确认：

- 减号、滑条、加号从左到右正常展开，无重叠。
- 滑条拖动区域和加减按钮点击区域正常。
- Dim level 数值变化及调光行为保持原有逻辑。
