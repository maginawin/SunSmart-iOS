# Professional Candidate 虚拟目标导致 Select all 隐藏问题分析

## 问题

在 Add Device 页面 Professional Mode 中，展开 Candidate Device List 后，在 `Add Device(s) to` 中选择虚拟 power switch，再收起 Candidate Device List，外层 Professional Mode 页面中的 Select all 相关控件也会隐藏。

预期是在点击外层 Scan 之后，外层 Professional Mode 页面应恢复展示 Select all 相关控件。

## 根因

Candidate Device List 中选择目标时，会回调到 `DeviceAddProfessionalModeController.applyTargetSelection(_:)`。

选择虚拟 Battery/AC Power Switch 后，外层 controller 会设置：

- `addTarget = .space(space)`
- `bindTarget = .batteryPowerSwitch(switchData)`

外层 Professional Mode 的 Select all cell 和设备行左侧选择按钮都使用 `hidesBatchSelectionControls` 控制隐藏，而该属性依赖：

- `bindTarget != nil`
- 或 `addTarget` 是 `.dongle`

因此 Candidate Device List 收起后，外层 controller 仍保留了 Candidate 中临时选择的 `bindTarget`，导致外层 Select all 相关控件继续隐藏。

## 修复

在 Professional Mode 开始扫描前增加重置逻辑：

- 仅当当前入口允许切换 `Add Device(s) to` 时执行；
- 如果存在临时 `bindTarget`，恢复为 `Space`；
- 同步 Candidate Device List 和外层设备选择状态。

这样普通 Site - Space - Main 入口在点击 Scan 后会恢复 Select all 控件；通过 Battery/AC Power Switch、EFC 等 LINK 功能进入时，由于 `allowsTargetSelection == false`，不会重置目标，也不会改变 LINK 页面保持现状的要求。
