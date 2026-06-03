# Battery Power Switch Empty Scene Panel Bug Design

## 背景

用户复现路径：

1. 添加 battery power switch。
2. 配置 Panel 为 brightness panel。
3. 绑定一个 group。
4. battery power switch 可正常控制该 group。
5. 将 Panel 切换为 scene panel。
6. 不配置任何 scene。

现象：设备面板显示为 scene panel，但物理 scene 按钮仍能控制 group 亮度，表现为 brightness panel 的旧行为。

期望：scene panel 下未配置 scene 的按键应完全无动作。

## 当前命令链路

Battery power switch 当前没有独立的 panel-type vendor 命令。App 通过一组 `batteryPowerSwitchKeyConfig` vendor set 命令把各按键动作写入设备，间接表达 panel 行为。

关键路径：

- `PJPreAddEightKeySwitchesViewModel.buildSwitchData()` 将 UI 选择写入 `switchData.eightKeyPanelType`，并将旧的 `panelType` 映射为 `.scenes_4key` 或 `.default_4key`。
- `PJPreAddEightKeySwitchesVC.submitBatteryPowerSwitch(_:)` 比较 desired hash，判断是否需要同步自有配置。
- `SyncDevicesViewController.appendBatteryPowerSwitchItems(...)` 创建 `.batteryPowerSwitchKeyConfig` 同步任务。
- `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 生成实际 `BatteryPowerSwitchKeyConfiguration` 列表。
- `SyncDevicesCellModel` 和 `SyncDevicesViewController.batteryPowerSwitchMessageHandles(...)` 将每个配置包装成 `SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration))`。

## 根因

`scene8Key` 当前只在 sceneA/B/C/D 有值时生成前 4 个 `.sceneRecall` 配置；没有 scene 的 key 会被跳过。

当用户从 brightness panel 切换到 scene panel 且 4 个 scene 都为空时：

- desired hash 会变化，触发 key config 同步。
- 前 4 个 scene 按键没有生成任何新配置。
- dimming、ON、AUTO、OFF 仍会生成配置。
- 设备端之前写入的前 4 个 `.lightnessSet` 配置没有被覆盖。

因此旧 brightness 配置残留在设备中，导致 scene 按钮仍控制 group 亮度。

SDK 协议层已有 `BatteryPowerSwitchActionType.disabled = 0`，可用于显式禁用某个 button/trigger 的动作。

## 推荐方案

在 `PJEightKeySwitchData` 的按键配置生成层修复。

`scene8Key` 下，前 4 个按键总是生成 click 配置：

- 对应 scene 已配置：发送 `.sceneRecall`，保留当前 scene recall 行为。
- 对应 scene 未配置：发送 `.disabled`，明确覆盖设备端旧动作。

这样从 brightness panel 切到空 scene panel 时，App 会发送 button 0...3 的 disabled key config，设备端旧的 `.lightnessSet` 行为会被清除，未配置 scene 的物理按键无动作。

## 方案取舍

选择推荐方案的原因：

- 符合产品期望：未配置 scene 的按键完全无动作。
- 改动集中在配置生成层，所有 add、link、restore、sync 路径都会复用同一逻辑。
- 不需要阻止用户保存空 scene panel。
- 不需要 reset defaults，避免重置 TX、LED 或其它设备设置带来的额外风险。

不采用的方案：

- 保存时强制至少配置一个 scene：不符合本次确认的产品期望。
- 切换 panel 时先 reset defaults 再写配置：影响面大，中间态风险高，不适合这个窄问题。

## 数据流影响

`batteryPowerSwitchDesiredConfigHash(appKeyIndex:)` 已经把 scene nil 状态纳入 hash，保持不变即可。

`batteryPowerSwitchTargetCapabilityModels(for:)` 基于生成出来的 action types 计算目标 group 需要订阅的 model。改为 disabled 后：

- 空 scene 不再引入 `.sceneRecall`。
- 空 scene 不再保留 brightness 的 `.lightnessSet`。
- dimming、ON、AUTO、OFF 仍会继续引入所需 model。

这与 scene panel 其余按键仍可控制 group 的现有 UI 定义一致。

## 错误处理

如果设备不接受 disabled key config，同步任务会按现有 vendor set 结果进入失败路径，不应把 `appliedConfigHash` 标记为成功。

无需新增 Auth 信息、target 配置、资源或依赖。

## 测试要求

建议补充 focused 单元测试或等价可验证测试：

1. `scene8Key` 且 sceneA/B/C/D 全为空时，`batteryPowerSwitchKeyConfigurations(...)` 生成 button 0...3、trigger `.click`、type `.disabled` 的配置。
2. `scene8Key` 混合配置时，有 scene 的键生成 `.sceneRecall`，无 scene 的键生成 `.disabled`。
3. `brightness8Key` 仍生成 button 0...3 的 `.lightnessSet`，避免回归。

实现后建议运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如 SDK 侧测试被修改，还需在 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 运行相关 Swift 测试。

## 验收标准

1. 从 brightness panel 切换到 scene panel 且不配置任何 scene 后，前 4 个物理 scene 按键无动作。
2. 配置了 scene 的 scene 按键仍能 recall 对应 scene。
3. brightness panel 前 4 个亮度键行为不变。
4. battery power switch 的 dimming、ON、AUTO、OFF 现有行为不受影响。
5. 同步失败时不会错误标记为已同步。
