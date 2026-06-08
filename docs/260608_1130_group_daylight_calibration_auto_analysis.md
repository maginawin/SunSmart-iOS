# Group Daylight Profile Calibration AUTO Analysis

## 范围

分析 group profile：

- `occupancy_daylight`: Occupancy sensing with daylight harvesting
- `vacancy_daylight`: Vacancy sensing with daylight harvesting
- `daylight`: Daylight harvesting (Closed loop)

场景是 group 中有两个以上支持光照度的设备，在 Calibration 页校准第 1 个、第 2 个或更多光照设备后，是否会自动进入 AUTO 状态。

## 结论

问题真实存在，但不是只在“第 2 个设备”时才有。

当前 Calibration 成功后会做两类事情：

1. 通过 SDK 完成当前光照传感器校准。
2. 将当前传感器的 Sensor Server publication 指向 group，并对 group 内灯具补发 profile 配置。

它不会在校准结束后发送 group 页 AUTO 按钮相同的运行态触发命令：

`LightLCLightOnOffSetUnacknowledged(true)`。

因此，如果灯具当前 Light LC Light OnOff 运行态没有处于 on / auto，校准完成后即使 `LightLCModeSet(true)` 和 `lightAutoAdjustEnabled(true)` 已配置成功，也可能不会立即表现为 AUTO 生效。用户手动在 group 页面点击一次 AUTO 后会发送 `LightLCLightOnOffSetUnacknowledged(true)`，所以现场反馈“点一次 AUTO 才生效”与代码行为一致。

这个风险对第 1 个、第 2 个、第 N 个校准设备都存在。第 2 个设备更容易复现，是因为切换到未校准的第 2 个传感器时，页面会先关闭上一个已启用光感传感器的 publication，并在校准过程中直接下发 group 亮度控制做测量，最终没有恢复 LC Light OnOff 运行态。

## 当前 group 未校准时的命令序列

入口：`LightSensorCalibrationViewController.calibrationBtnAction()` 调用：

`MeshSensorCalibrateManager.manager.calibrate(node:ambientLightOffLux:ambientLightOnLux:)`

SDK 校准阶段主要命令：

1. `SunricherVendorSet(.daylightCalibrate(0xFFFF))`
2. `SunricherVendorSet(.daylightCalibrateRate(sensorRate: 100, ambientLightRate: 100))`
3. `SunricherVendorSet(.daylightPublishDelta(1))`
4. `ConfigModelPublicationSet`：把被校准传感器的 Sensor Server publication 临时设到 local node。
5. 多次 `LightLightnessSetUnacknowledged` 到 group 地址，用于采集 0%、25%、50%、75%、95%、100% 等亮度点。
6. `SunricherVendorSet(.daylightCalibrateIlluminanceInflectionPoint(...))`
7. `SunricherVendorSet(.daylightCalibrateRate(sensorRate: calculated, ambientLightRate: calculated))`
8. `SunricherVendorSet(.daylightPublishDelta(defaultPublishDelta))`

App 成功回调后：

1. `ConfigModelPublicationSet`：把当前传感器 Sensor Server publication 设到 group 地址。
2. `configuring(lightNodes: group.nodes)` 遍历 `group.nodes`，对 `getNodeSyncProfiles()` 返回非空的节点下发 profile 配置。
3. 典型 daylight profile 配置可能包含：
   - `LightLCModeSet(true)`
   - `LightLCOccupancyModeSet(true/false)`，取决于 profile 是 occupancy / vacancy / daylight
   - `SunricherVendorSet(.manualOverrideTimeout(...))`
   - `SunricherVendorSet(.manualControlEnabled(false))`
   - `SunricherVendorSet(.lightAutoAdjustEnabled(true))`
   - `LightLCPropertySet` 的 lux / lightness / timing / regulator 参数
   - 如支持 LC scene，还可能包含 `SceneRecall` / `SunricherVendorSet(.daylightConditionRecall(...))` 和 `SceneStore`

不会发送：

`LightLCLightOnOffSetUnacknowledged(true)`

## 当前 group 已校准 1 个设备，继续校准第 2 个设备

如果第 2 个设备还未校准，用户在 Calibration 页选择第 2 个传感器时：

1. 若第 1 个传感器 Sensor Server publication 指向当前 group，会先对第 1 个传感器发送 `ConfigModelPublicationSet(disablePublicationFor:)`。
2. 将 `group.info.ambientLightSensorNodeAddress` 置空并保存。
3. 因第 2 个传感器未校准，只会选中它等待校准，不会马上启用 publication。
4. 之后校准第 2 个设备，命令序列与“未校准 group”基本相同。
5. 校准成功后，把第 2 个传感器 Sensor Server publication 设置到 group，并重新 `configuring(lightNodes: group.nodes)`。

同样不会发送：

`LightLCLightOnOffSetUnacknowledged(true)`

如果第 2 个设备已经校准过，选择它时会直接走 `sensorEnabled(...)` 并同步 profile，但也不会发送 `LightLCLightOnOffSetUnacknowledged(true)`。

## 为什么手动点 AUTO 后生效

group 页面 AUTO 按钮逻辑是：

`MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true, ...), address: group.address.address)`

这条是 Light LC 的运行态触发命令。它和同步阶段的 `LightLCModeSet(true)` 不同：

- `LightLCModeSet(true)`：开启 Light LC Controller 配置开关。
- `SunricherVendorSet(.lightAutoAdjustEnabled(true))`：开启 daylight auto adjust 配置。
- `LightLCLightOnOffSetUnacknowledged(true)`：触发 LC Light OnOff 运行态进入 on / auto。

当前校准完成路径只有前两类配置，没有最后这条运行态触发。

## 数量影响

不依赖“已校准设备数量”本身，依赖的是被控灯具当前运行态。

- 第 1 个设备：如果校准前或校准过程中灯具已经被手动亮度控制打断 LC Light OnOff，校准完成后也可能不自动进入 AUTO。
- 第 2 个设备：更容易出现，因为切换传感器会 disable 上一个 publication，校准算法又会直接控制 group 亮度，结束后没有 AUTO restore。
- 第 N 个设备：同第 2 个，只要切换当前 group 使用的光感传感器并重新校准，都有同类风险。
- 如果灯具原本已经处于 LC Light OnOff on / auto，或者设备固件在配置变更后自行保持/恢复运行态，则可能表现正常，因此现场现象可能不是 100% 必现。

## 关键代码位置

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - `calibrationBtnAction()`：校准入口。
  - `sensorEnabled(sensor:...)`：校准成功后设置 Sensor Server publication 到 group，并调用 `configuring(lightNodes:)`。
  - `configuring(lightNodes:)`：只发送 `getNodeSyncProfiles()` 生成的 profile 配置。
  - `enableDaylightSensor(...)`：切换第 2 个传感器时先 disable 上一个已启用传感器。
- `SunSmart/Common/Data/Node+SyncData.swift`
  - `getNodeSyncProfiles(...)`：生成 sensor publication、LC mode、daylight auto adjust、profile 属性等配置项。
  - `getNodeLightDataSyncProfiles(...)`：在 daylight 已启用时生成 `lightAutoAdujustEnabled(true)`。
- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - `ProfileType.getMessageHandles(node:)`：把配置项映射为 `LightLCModeSet`、`LightLCPropertySet`、`SunricherVendorSet(.lightAutoAdjustEnabled(...))` 等。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `autoBtnAction(sender:)`：group 页面手动 AUTO，发送 `LightLCLightOnOffSetUnacknowledged(true)`。
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
  - `calibrate(...)` / `initialize()` / `setLightingAndSensorInflectionPoint()` / `setCalibrateRate()`：SDK 校准命令序列。
  - `lightsControl(lightness:)`：校准中直接发送 group lightness 控制。

## 后续建议

若产品预期是“Calibration 完成后立即自动恢复 AUTO”，需要在校准成功且 profile 配置完成后补发一次 group 级 `LightLCLightOnOffSetUnacknowledged(true)`，或在配置流程中增加等价的 auto restore 步骤。实现前需要确认是否所有 daylight profile 在校准完成后都应该立即触发 AUTO，以及失败/部分失败时是否仍触发。
