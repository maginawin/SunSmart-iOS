# 可外接光照传感器灯设备设计

## 背景

在需要 `CALIBRATE` 的 Group Profile 中，用户进入 Calibration 页面后，会在 `Select daylight sensor` 下选择用于校准的日光传感器。部分灯设备具备外接光照传感器能力，但 App 无法判断物理传感器当前是否真的已连接。

Company ID 为 `0x0A78` 时，以下 Product ID 需要统一视为这种特殊灯设备：

- `0x2121`
- `0x2122`
- `0x2132`
- `0x2133`
- `0x2491`
- `0x2492`
- `0x2493`
- `0x2494`

这些设备仍然归类为 Lighting 设备，不改成独立传感器类型。它们始终暴露 `ambientLightSensorModel`，因此已经会进入 `group.ambientLightSensorNodes`，并自然出现在现有 daylight sensor 选择列表中。

## 设计决策

使用集中的 `Node` 能力 getter 识别此产品族，例如 `isExternalLightSensorCapableLuminaire`。

该能力的含义是：

- 设备是一个可外接光照传感器的灯。
- 如果外接传感器已连接，它可以作为 daylight sensor 使用。
- 如果外接传感器未连接，它仍然暴露 sensor model，但需要用户自行识别实际安装状态。

这个能力标记不应改变设备类型归类、添加流程、分组逻辑、OTA 行为、设备页路由或通用 Lighting 行为。

## Getter 优劣

推荐在 `Node` 上使用 getter，因为该规则属于产品能力，不是某个页面的一次性 UI 条件。这样可以把 Company ID 和 Product ID 列表集中在一个位置，后续如果其它流程也需要识别这种设备，可以复用同一语义。

缺点是通用 `Node` 扩展会增加一个产品特定业务规则。这个代价可以接受，因为项目中已经存在类似的 `Node` 产品能力 helper，用于处理硬件差异；集中判断也能避免 Product ID 条件散落在多个 UI 控制器中。

不采用的方案：

- 只在 Calibration 控制器里写 Product ID 判断。初始改动最小，但会把产品识别和单个页面强绑定，后续相关流程容易遗漏。
- 在 `devices_config.json` 增加字段。这个方式更数据驱动，但目标 Product ID 目前只有一部分存在于该文件中，App 仍然需要运行时兜底规则，反而形成双来源。

## Calibration 行为

`LightSensorCalibrationSelectView` 继续只负责列表展示，并通过 delegate 上报开关意图。业务判断仍放在 `LightSensorCalibrationViewController`。

当用户尝试把此类特殊设备从 disabled 切到 enabled 时：

1. 控制器先检查新的 `Node` 能力 getter。
2. 如果设备命中该能力，在改变选择状态或发送 mesh 配置消息前先弹出确认提示。
3. `CANCEL` 保持或恢复 disabled 状态，不发送 sensor enable 消息。
4. `CONFIRM` 继续现有 enabled 流程。

弹窗文案：

- Title: `Notification`
- Message: `This device has the ability to connect to an external light sensor. Before calibration, please ensure that the sensor is connected.`
- Buttons:
  - `CANCEL`
  - `CONFIRM`

同一设备从 enabled 切回 disabled 时不弹窗，继续走当前取消选择流程。

普通 daylight sensor 保持现有行为，不显示新增提示。

## 数据流

现有 UI 流程适合承载这次改动：

- `LightSensorCalibrationSelectViewCell` 不直接通过 `UISwitch` value changed 提交状态。
- cell 使用覆盖按钮上报用户期望的 enabled 状态。
- `LightSensorCalibrationSelectView` 将该意图转发给 `LightSensorCalibrationViewController`。
- 控制器决定是否启用、禁用、进入 loading、发送 mesh 消息或回滚状态。

由于 switch 在 delegate 回调前不会真正提交状态，`CANCEL` 路径可以保持简单：让 `selectState` 保持 `.switchOff`，必要时刷新目标 cell。

`CONFIRM` 路径应在用户确认后复用现有选择逻辑，使以下处理保持不变：

- loading 防重入
- 上一个已选 sensor 的禁用
- publish 配置
- calibration 状态更新
- manual correction 按钮更新
- 失败回滚
- space data changed 通知

## 错误处理

新增弹窗不能绕过现有错误处理。用户点击 `CONFIRM` 后，所有当前失败路径仍然生效。

如果另一个 sensor 正处于 loading，现有 loading guard 应继续阻止操作。这种无法处理的点击不应弹出新增提示。

如果禁用上一个已选 sensor 失败，现有回滚行为仍然是最终状态来源。

## 本地化

新增用户可见文案按需求使用英文。实现时应新增或复用本地化 key，但英文资源必须保持以下文本：

- `Notification`
- `This device has the ability to connect to an external light sensor. Before calibration, please ensure that the sensor is connected.`
- `CANCEL`
- `CONFIRM`

因为这次改动涉及本地化资源，实现时需要同步检查共享 `SunSmart/en.lproj` 和 `SunSmart/zh-Hans.lproj` 字符串文件是否被相关 target 正确包含。中文资源如果没有明确翻译需求，可以先保持同样的英文文案，避免与需求原文不一致。

## 验证

人工验证和代码审查需要覆盖：

- `0x0A78 / 0x2121`、`0x2122`、`0x2132`、`0x2133`、`0x2491`、`0x2492`、`0x2493`、`0x2494` 都能通过新的能力 getter 返回 true。
- 其它 Product ID 返回 false。
- 特殊设备从 disabled 切到 enabled 时，在 sensor enable 配置前弹窗。
- 特殊设备点击 `CANCEL` 后保持 disabled，且不发送 enable 消息。
- 特殊设备点击 `CONFIRM` 后继续现有 enable 行为。
- 特殊设备从 enabled 切到 disabled 时不弹窗。
- 普通 daylight sensor 从 disabled 切到 enabled 时不弹窗。
- 现有校准前固件最低版本检查仍然生效。
- 现有 loading 防重入和上一个 sensor 失败回滚行为不变。

构建验证使用项目推荐命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
