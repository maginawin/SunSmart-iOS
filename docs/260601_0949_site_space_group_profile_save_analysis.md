# Site - Space - Group Profile SAVE 下发分析

## 结论摘要

当前 App 中，真正可用于 Group Profile 的类型来自 `Profile.ProfileType.defaultGroupProfileTypes`，共 8 种：

| rawValue | Profile | 中文说明 | 主要设备要求 |
| --- | --- | --- | --- |
| 1 | `occupancy_daylight` | 占用感应 + 日光采集 / Occupancy sensing with daylight harvesting | luminaire、light sensor、occupancy sensor |
| 2 | `vacancy_daylight` | 空置感应 + 日光采集 / Vacancy sensing with daylight harvesting | luminaire、light sensor、manual control、occupancy sensor |
| 3 | `occupancy` | 占用感应 / Occupancy sensing | luminaire、occupancy sensor |
| 4 | `vacancy` | 空置感应 / Vacancy sensing | luminaire、occupancy sensor、manual control |
| 5 | `daylight` | 日光采集 / Daylight harvesting | luminaire、light sensor |
| 6 | `manualControl` | 手动控制 / Manual control | luminaire、manual control |
| 7 | `proximityLighting` | 邻近/预测照明 / Proximity / predictive lighting | luminaire、occupancy sensor、path sequence setting |
| 8 | `proximityLightingWithPhotocell` | 带光感条件的邻近/预测照明 / Proximity / predictive lighting with photocell | luminaire、light sensor、occupancy sensor、path sequence setting |

代码里存在一个旧的 `GroupProfilesViewController.profiles` 字符串数组，包含 `Photocell`、`Occupancy sensing with photocell`、`Vacancy sensing with photocell`，但该页面点击只提示 coming soon，且不对应当前 `Profile.ProfileType`。因此本分析不把它们列为当前有效 Group Profile。

Profile SAVE 不是全量下发，而是“先落库，再按每个节点的当前状态生成差量同步项”。同一个 Profile 在不同节点上实际下发的命令可能不同：只有目标值与节点当前缓存/回包状态不一致、并且节点具备相应 Model / capability 时才会生成命令。

## Site - Space - Group - Profile 关联

1. `SiteData` 保存 site 级数据，`id` 与 `meshUUID` 关联同一个 Mesh 网络；`meshNetworkId` 是主网网络 id。
2. `SpaceData` 属于一个 `siteId`，同时保存 `meshUUID` 和 `meshNetworkId`。这里的 `meshNetworkId` 是 space 对应的子网 network id。
3. `GroupInfo` 以 `meshUUID + subNetworkKey + groupAddress` 保存 group 扩展信息，其中 `profileId` 指向 `Profile.profilesTable` 中同一 `meshUUID + subNetworkKey` 下的 Profile。
4. Group 页面进入 Profile 设置后，`ProfileSettingsViewController` 保存回调会：
   - 更新 `group.info.profile`；
   - 保存 `group.info`，即保存 group 到 profileId 的关系；
   - 保存 Profile 本体数据；
   - 清除 group / node 同步缓存；
   - 如果 `group.nodes.contains { $0.needSync }`，进入 `SyncDevicesViewController(type: .group(...))` 执行设备同步。

关键代码位置：

- `SunSmart/Common/Data/SiteData.swift`
- `SunSmart/Common/Data/SpaceData.swift`
- `SunSmart/Common/Data/Database.swift`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

## SAVE 通用下发链路

### 1. UI 校验和本地保存

普通 Profile SAVE 主要直接落库；`proximityLightingWithPhotocell` 会额外校验：

- night lux 必填；
- day lux 必填；
- night / day lux 都必须在 `0...5000`；
- night lux 必须小于 day lux；
- day lux - night lux 必须大于等于 5；
- 保存 profile 关联的 light sensor template；
- 对组内不支持 `.lightLCScene` required function 的 node 补齐 requiredFunctionTypes 并保存 preConfiguration。

切换 Profile 类型时：

- 如果新类型不是 `proximityLightingWithPhotocell`，清空 node preConfiguration 中 day/night profile lux 和 light data；
- 如果新类型不是 daylight 类型，给已校准节点标记 `resetDaylightCalibration = true`，后续同步时会把校准倍率恢复为 `100 / 100`。

### 2. Node 差量生成入口

Group SAVE 后通过 `Node.getSyncData(type: .group(group, effectiveMemberCount: ...))` 生成同步数据，profile 相关部分是：

1. 设备未初始化：先生成 `.deviceInitialize`。
2. 组订阅不完整：生成 `.subscribeGroup(group)`。
3. 调用 `getNodeSyncProfiles(group:)` 生成 `.profile(types: [...])`。
4. 再生成场景、日程、开关、邻近照明路径等其它同步项。

如果需要加入组，`SyncDevicesViewController` 会把其它配置步骤依赖到 `add_to_group` 之后。也就是说新增设备时大顺序是：

`deviceInitialize -> subscribeGroup -> profile -> scenes -> schedules -> switches -> proximityLighting`

删除组时则相反，退组会依赖其它删除配置先完成。

### 3. Profile 同步任务内部顺序

`getNodeSyncProfiles(group:)` 返回的是有序数组；`SyncDevicesViewController` 再用 task dependency 保证场景型 Profile 的关键顺序：

1. `profileToggleTriggerConditionLuxLock` 如果存在，先执行。
2. `profileDayToggleTriggerConditionLux` / `profileNightToggleTriggerConditionLux` 在切换场景前执行。
3. `lightControlSwitch` 或 `daylightSensorConditionRecall` 在对应场景参数设置前执行。
4. 场景内参数按生成顺序逐个设置。
5. `lightControlStore` 依赖当前场景内参数全部成功后执行。
6. 下一个场景的 switch / recall 会依赖上一个 store 完成。
7. `profileToggleTriggerConditionLuxUnLock` 如果存在，最后执行。
8. `powerOnState`、`sensitivity`、`lightControlDelete`、`profileToggleTriggerConditionLuxDelete` 不额外依赖场景参数。

实际发送由 `MeshProxyMessageCommand.shared.addMessage` 串行执行；每个任务完成后会用回包结果和 `operationType.isSuccessful` 共同判定任务成功。

### 4. SAVE 期间 PIR 保护

如果是 Profile SAVE 且没有新增/移出组成员，`ProfileSensorProtectionContext` 会在同步队列中插入：

1. 最前：`profileSensorProtectionDisable`，对支持 `.pirEnabled` 的 occupancy sensor 发送 `SunricherVendorSet(.pirEnabled(false))`；
2. 最后：如果保存后的 Profile 是占用类，插入 `profileSensorTargetEnable`，恢复目标 PIR 状态。

目标恢复规则：

- 如果旧 Profile 也是占用类，只恢复 SAVE 前已经启用的 PIR sensor；
- 如果旧 Profile 不是占用类，但新 Profile 是占用类，则启用所有支持 PIR protection 的 sensor；
- 如果同步中断，`applyProfileSensorTargetStateIfNeeded()` 会尝试后台补发剩余的启用命令。

注意：这里的“占用类”使用 `Profile.ProfileType.occupancyType`，包含 `proximityLighting` 和 `proximityLightingWithPhotocell`。但 `Node.getNodeSyncProfiles` 内用于标准 Sensor Publication 的本地 `occupancyType` 只包含前四种 occupancy/vacancy profile，不包含 proximity 两种。

## ProfileType 到 Mesh / Vendor 命令映射

| ProfileType 同步项 | 实际下发命令 | 成功规则 |
| --- | --- | --- |
| `sensorEnabled` | `ConfigModelPublicationSet(Publish(to: groupAddress, using: currentApplicationKey, ttl, period, retransmit), to: Sensor Server Model)` | 每个目标 Sensor Server Model 的 publication address 和 retransmit 等于目标值 |
| `sensorDisable` | `ConfigModelPublicationSet(disablePublicationFor: Sensor Server Model)` | 每个目标 Sensor Server Model 的 publication address 为空 |
| `mode(true/false)` | `LightLCModeSet` | `node.lightLCProperty.mode == enabled` |
| `occupancyMode(true/false)` | `LightLCOccupancyModeSet` | `node.lightLCProperty.occupancyMode == enabled` |
| `highLowEndTrim` | `LightLightnessRangeSet(min...max)` | 节点 lightness range 换算成百分比后等于目标 range |
| `occupancyLevel` | `LightLCPropertySet(.lightControlLightnessOn, .perceivedLightness(...))` | `node.lightLCProperty.lightnessOn` 等于目标 lightness |
| `occupancyLux` | `LightLCPropertySet(.lightControlAmbientLuxLevelOn, .illuminance(...))` | `node.lightLCProperty.luxLevelOn` 等于目标 lux |
| `vacantLevel` | `LightLCPropertySet(.lightControlLightnessProlong, .perceivedLightness(...))` | `node.lightLCProperty.lightnessProlong` 等于目标 lightness |
| `vacantLux` | `LightLCPropertySet(.lightControlAmbientLuxLevelProlong, .illuminance(...))` | `node.lightLCProperty.luxLevelProlong` 等于目标 lux |
| `standbyLevel` | `LightLCPropertySet(.lightControlLightnessStandby, .perceivedLightness(...))` | `node.lightLCProperty.lightnessStandby` 等于目标 lightness |
| `standbyLux` | `LightLCPropertySet(.lightControlAmbientLuxLevelStandby, .illuminance(...))` | `node.lightLCProperty.luxLevelStandby` 等于目标 lux |
| `adjustSpeed` | 依次发送 `LightLCPropertySet`：`RegulatorKid`、`RegulatorKiu`、`RegulatorKpd`、`RegulatorKpu`、`RegulatorAccuracy` | Kid / Kiu / Kpd / Kpu 等于 `Node.getLightRegulator(speed:)` 结果。当前成功规则未校验 Accuracy |
| `t1` | `LightLCPropertySet(.lightControlTimeFadeOn, .timeMillisecond24(second * 1000))` | `timeFadeOn == min(second * 1000, 0xFFFFFE)` |
| `t2` | `LightLCPropertySet(.lightControlTimeRunOn, .timeMillisecond24(min(second * 1000, 0xFFFFFE)))` | `timeRunOn == min(second * 1000, 0xFFFFFE)` |
| `t3` | `LightLCPropertySet(.lightControlTimeFade, .timeMillisecond24(second * 1000))` | `timeFade == min(second * 1000, 0xFFFFFE)` |
| `t4` | `LightLCPropertySet(.lightControlTimeProlong, .timeMillisecond24(min(second * 1000, 0xFFFFFE)))` | `timeProlong == min(second * 1000, 0xFFFFFE)` |
| `t5` | `LightLCPropertySet(.lightControlTimeFadeStandbyAuto, .timeMillisecond24(second * 1000))` | `timeFadeStandbyAuto == min(second * 1000, 0xFFFFFE)` |
| `manualOverrideTimeout` | `SunricherVendorSet(.manualOverrideTimeout(enabled, state, interval))`，非 max 秒数会换算成毫秒 | enabled、timeout、manualControlState 全部等于目标 |
| `manualControl` | `SunricherVendorSet(.manualControlEnabled(enabled))` | `node.lightLCProperty.manualControlMode == enabled` |
| `lightAutoAdujustEnabled` | `SunricherVendorSet(.lightAutoAdjustEnabled(enabled))` | `node.lightLCProperty.lightAutoAdjustEnabled == enabled` |
| `powerOnState(.off/.restore)` | `GenericOnPowerUpSet(.off/.restore)` | `node.powerUpState` 等于目标 |
| `powerOnState(.definedLightLevel)` | 支持 CCT 时先 `LightCTLDefaultSet(lightness, temperature, deltaUV: 0)`，否则 `LightLightnessDefaultSet(lightness)`；最后 `GenericOnPowerUpSet(.default)` | `node.powerUpState == .default`、默认亮度等于目标；如果目标 CCT 存在，还要求 `node.defaultCct` 等于目标 CCT |
| `daylightCalibration` | `SunricherVendorSet(.daylightCalibrate(value))` | `node.daylightCalibrationValue == value` |
| `daylightCalibrateRate` | `SunricherVendorSet(.daylightCalibrateRate(sensorRate, ambientLightRate))` | 当前直接返回 true，不读回比对 |
| `daylightCalibrateInflectionPoint` | `SunricherVendorSet(.daylightCalibrateIlluminanceInflectionPoint(...))` | 当前直接返回 true，不读回比对 |
| `sensitivity` | `SunricherVendorSet(.motionSensitivity(value, maxValue, minValue))` | `node.motionSensitivity == value` |
| `lightControlSwitch` | `SceneRecall(sceneNumber)` on Light LC Scene Model | 当前直接返回 true |
| `daylightSensorConditionRecall` | `SunricherVendorSet(.daylightConditionRecall(index))` | 当前直接返回 true |
| `lightControlStore` | 默认只发 `SceneStore(sceneNumber)` on Light LC Scene Setup Model；只有 `turnOffBeforeStore == true` 时才先发 `LightLCLightOnOffSet(false)` | `node.lightControlSceneExecuteDatas` 中存在该 sceneNumber |
| `lightControlDelete` | `SceneDelete(sceneNumber)` on Light LC Scene Model | 该 sceneNumber 不再存在于 `node.lightControlSceneExecuteDatas` |
| `profileDayToggleTriggerConditionLux` / `profileNightToggleTriggerConditionLux` | 支持分段 capability 时按差异发送 `daylightConditionLuxThresholdSet`、`daylightExecuteSceneActionSet`、`daylightConditionLuxUseCalibrationValuesSet`；否则发送整包 `daylightExecuteSceneSet` | 只校验存在同 index 的 lux trigger condition，不校验 min/max/destination/scene/useCalibrationValues 是否完全等于目标 |
| `profileToggleTriggerConditionLuxDelete` | `SunricherVendorSet(.daylightExecuteSceneSet(index, minLux: 0, maxLux: 0, useCalibrationValues: false, destination: 0, sceneNumber: 0))` | 同 index 的 lux trigger condition 不存在 |
| `profileToggleTriggerConditionLuxLock` | `SunricherVendorSet(.daylightLuxTriggerLock(delay: 600))` | 当前直接返回 true |
| `profileToggleTriggerConditionLuxUnLock` | `SunricherVendorSet(.daylightLuxTriggerLock(delay: 0))` | 当前直接返回 true |
| `proximityLightingEnabled` | `SunricherVendorSet(.proximityLightingEnabled(enabled))` | `node.proximityLightingEnabled == enabled` |
| `proximityLightingRelayNumber` | `SunricherVendorSet(.proximityLightingRelaySet(relay))` | `node.proximityLightingRelayCount == relayNumber` |
| `proximityLightingNeighbor` | `SunricherVendorSet(.proximityLightingNeighborSet(enabled: true, relay, ttl: 0, relayAppKeyIndex, neighborAddresses))` | relay count 相等且 neighbor address 排序后相等 |

## 各 Profile SAVE 时的目标下发顺序

以下顺序描述的是“当节点状态与目标不一致时”的下发顺序。节点不支持对应 Model / capability 时不会生成该命令。

### 1. `occupancy_daylight`

目标行为：有人时按 daylight harvesting 调光，无人后进入 vacant / standby 阶段。

目标设备：

- Ambient light sensor：需要把 Sensor Server publication 设置到 group address。
- Occupancy sensor：需要把 Presence Sensor Server publication 设置到 group address。
- Luminaire：需要设置 Light LC、Light LC Setup、Lightness Setup、Power OnOff Setup 等。

SAVE 下发顺序：

1. PIR protection：如适用，先对支持 PIR enable 的 sensor 下发 `SunricherVendorSet(.pirEnabled(false))`。
2. 如果节点未初始化或未订阅组：先执行初始化和 group subscription。
3. Sensor publication：
   - ambient light sensor 下发 `ConfigModelPublicationSet(Publish(to: groupAddress...))`；
   - presence sensor 下发 `ConfigModelPublicationSet(Publish(to: groupAddress...))`。
4. 如果 daylight 已启用且有 restore calibration 数据：下发 `daylightCalibration`、`daylightCalibrateRate`、`daylightCalibrateInflectionPoint`。
5. Luminaire 全局范围：必要时下发 `LightLightnessRangeSet(lowEndTrim...highEndTrim)`。
6. 如果存在不属于当前 profile scenes 的 Light LC scene：逐个 `SceneDelete`。
7. 如果节点存在旧的 day/night lux trigger condition，因为该 Profile 不是 `proximityLightingWithPhotocell`，逐个发送 `profileToggleTriggerConditionLuxDelete`。
8. 对 General Scene：
   - 支持 Light LC scene 时先 `SceneRecall(generalLightControlScene)`；
   - `LightLCModeSet(true)`；
   - `LightLCOccupancyModeSet(true)`；
   - `manualOverrideTimeout(enabled: true, state: .standby, second: profile.manualOverrideTimeout)`；
   - `manualControlEnabled(false)`；
   - daylight 已启用时 `lightAutoAdjustEnabled(true)`，否则 `false`；
   - `occupancyLux` 设置 `.lightControlAmbientLuxLevelOn`；
   - `vacantLux` 设置 `.lightControlAmbientLuxLevelProlong`；
   - `standbyLux` 设置 `.lightControlAmbientLuxLevelStandby`；
   - auto min level：daylight 已启用时把 `.lightControlLightnessOn / Prolong / Standby` 设为 autoMinLevel 或 0；未校准但为 occupancy daylight 时使用默认 `100 / 50 / 0`；
   - `t1 -> t2 -> t3 -> t4 -> t5`；
   - `adjustSpeed` 依次设置 5 个 regulator 属性；
   - 支持 Light LC scene 时最后 `SceneStore(generalLightControlScene)`。
9. Power-up：按目标发送 `LightCTLDefaultSet` 或 `LightLightnessDefaultSet`，再 `GenericOnPowerUpSet`；off / restore 只发 `GenericOnPowerUpSet`。
10. Sensitivity：presence sensor 节点下发 `motionSensitivity`。
11. PIR protection：如适用，最后恢复目标 PIR enable 状态。

成功规则：

- 每个 ProfileType 按上文映射表校验；
- 整个设备所有相关 task 成功后，设备成功；
- 所有设备成功后，SyncDevicesViewController 判定 group profile SAVE 同步成功。

### 2. `vacancy_daylight`

目标行为：手动打开后进入 daylight harvesting；vacancy 语义通过关闭 occupancy mode 实现。

相对 `occupancy_daylight` 的主要差异：

1. Sensor publication 与 daylight calibration 规则相同。
2. General Scene 中 `LightLCModeSet(true)` 相同。
3. `LightLCOccupancyModeSet(false)`，因为 vacancy 类型不在 `occupancyMode` 开启列表。
4. `manualOverrideTimeout` 的 state 仍为 `.standby`。
5. `manualControlEnabled(false)`，当前代码只有 `manualControl` Profile 会启用 manual control mode。
6. 阶段值仍按 daylight 类型使用 lux：`occupancyLux`、`vacantLux`、`standbyLux`。
7. auto min、T1-T5、adjustSpeed、Power-up、Sensitivity 规则同 `occupancy_daylight`。

成功规则同 `occupancy_daylight`，其中 occupancy mode 需要读回为 false。

### 3. `occupancy`

目标行为：有人触发后按百分比亮度运行，无 daylight harvesting。

SAVE 下发顺序：

1. PIR protection：如适用先禁用 PIR。
2. 初始化 / group subscription。
3. Sensor publication：
   - ambient light sensor 如果已有 publication，发送 `sensorDisable`；
   - presence sensor 设置 publication 到 group address。
4. 如果有旧 daylight trigger condition，逐个 `profileToggleTriggerConditionLuxDelete`。
5. General Scene：
   - `SceneRecall(generalLightControlScene)`；
   - `LightLCModeSet(true)`；
   - `LightLCOccupancyModeSet(true)`；
   - `manualOverrideTimeout(enabled: true, state: .standby, second: profile.manualOverrideTimeout)`；
   - `manualControlEnabled(false)`；
   - `lightAutoAdjustEnabled(false)`；
   - `occupancyLevel` 设置 `.lightControlLightnessOn`；
   - `vacantLevel` 设置 `.lightControlLightnessProlong`；
   - `standbyLevel` 设置 `.lightControlLightnessStandby`；
   - `t1 -> t2 -> t3 -> t4 -> t5`；
   - `SceneStore(generalLightControlScene)`。
6. Power-up。
7. Sensitivity。
8. PIR protection：如适用恢复目标 PIR enable。

成功规则：

- 百分比亮度会转换成 Lightness 值后和 `node.lightLCProperty.lightnessOn / Prolong / Standby` 比对；
- `lightAutoAdjustEnabled` 必须为 false；
- 其它规则同映射表。

### 4. `vacancy`

目标行为：手动介入后运行 occupancy/vacancy 阶段，但 occupancy mode 关闭。

相对 `occupancy` 的主要差异：

1. presence sensor publication 仍会设置到 group address。
2. General Scene 中 `LightLCOccupancyModeSet(false)`。
3. `manualControlEnabled(false)`。
4. 阶段值使用百分比：`occupancyLevel`、`vacantLevel`、`standbyLevel`。
5. 其它顺序同 `occupancy`。

成功规则同 `occupancy`，其中 occupancy mode 需要为 false。

### 5. `daylight`

目标行为：按环境光维持 task lux，不使用 occupancy sensor。

SAVE 下发顺序：

1. PIR protection：如果旧/新 Profile 触发 protection 逻辑，可能先禁用 PIR；新 Profile 不是占用类，不会插入最后的目标启用。
2. 初始化 / group subscription。
3. Sensor publication：
   - ambient light sensor 设置 publication 到 group address；
   - presence sensor 如果 publication 指向该 group，则发送 `sensorDisable`。
4. daylight calibration restore：同 daylight 类规则。
5. 删除旧 Light LC scene / 删除旧 day-night lux trigger condition。
6. General Scene：
   - `SceneRecall(generalLightControlScene)`；
   - `LightLCModeSet(true)`；
   - `LightLCOccupancyModeSet(false)`；
   - `manualOverrideTimeout(enabled: true, state: .on, second: profile.manualOverrideTimeout)`；默认新建 daylight Profile 时 timeout 是 `.max`；
   - `manualControlEnabled(false)`；
   - daylight 已启用时 `lightAutoAdjustEnabled(true)`，否则 `false`；
   - `taskLevel` 作为 `occupancyLux` 设置 `.lightControlAmbientLuxLevelOn`；
   - 强制 `t2` 为 `0xFFFFFE`，表示 run on 近似无限长；
   - `t1`；
   - `adjustSpeed`；
   - `SceneStore(generalLightControlScene)`。
7. Power-up。

成功规则：

- `manualControlState` 必须为 `.on`；
- `timeRunOn` 必须为 `0xFFFFFE`；
- `luxLevelOn` 等于 task lux；
- 不下发 sensitivity，因为当前 `getNodeSyncProfiles` 只对 occupancy 前四类或 proximity 两类做 sensitivity。

### 6. `manualControl`

目标行为：手动控制固定亮度，不使用 daylight / occupancy 自动化。

SAVE 下发顺序：

1. PIR protection：如果旧/新 Profile 触发 protection，可能先禁用 PIR；新 Profile 不是占用类，不会插入最后的目标启用。
2. 初始化 / group subscription。
3. Sensor publication：
   - ambient light sensor 如果已有 publication，发送 `sensorDisable`；
   - presence sensor 如果 publication 指向该 group，发送 `sensorDisable`。
4. 删除旧 Light LC scene / 删除旧 day-night lux trigger condition。
5. General Scene：
   - `SceneRecall(generalLightControlScene)`；
   - `LightLCModeSet(true)`；
   - `LightLCOccupancyModeSet(false)`；
   - `manualOverrideTimeout(enabled: true, state: .standby, second: profile.manualOverrideTimeout)`；默认新建 manual Profile 时 timeout 是 `.max`；
   - `manualControlEnabled(true)`；
   - `lightAutoAdjustEnabled(false)`；
   - `taskLevel` 作为 `occupancyLevel` 设置 `.lightControlLightnessOn`；
   - 强制 `t2` 为 `0xFFFFFE`；
   - `t1`；
   - `SceneStore(generalLightControlScene)`。
6. Power-up。

成功规则：

- `manualControlMode == true`；
- `occupancyMode == false`；
- `timeRunOn == 0xFFFFFE`；
- `.lightControlLightnessOn` 等于 task level 换算后的 Lightness。

### 7. `proximityLighting`

目标行为：使用邻近照明路径/区域配置驱动预测照明，不使用 daylight harvesting。

SAVE 下发顺序：

1. PIR protection：如适用先禁用 PIR，最后恢复目标 PIR enable。
2. 初始化 / group subscription。
3. Sensor publication：
   - 当前 `getNodeSyncProfiles` 的本地 occupancyType 不包含 proximity，因此不会为 proximity 自动启用 presence sensor publication 到 group；
   - ambient light sensor 如有 publication 会被 `sensorDisable`；
   - 如果 presence sensor publication 正好指向 group address，也会被 `sensorDisable`，因为 proximity 不在该本地 occupancyType 中。
4. 删除旧 Light LC scene / 删除旧 day-night lux trigger condition。
5. General Scene：
   - `SceneRecall(generalLightControlScene)`；
   - `LightLCModeSet(true)`；
   - `LightLCOccupancyModeSet(true)`；
   - `manualOverrideTimeout(enabled: true, state: .standby, second: profile.manualOverrideTimeout)`；
   - `manualControlEnabled(false)`；
   - `lightAutoAdjustEnabled(false)`；
   - `occupancyLevel`、`vacantLevel`、`standbyLevel`；
   - `t1 -> t2 -> t3 -> t4 -> t5`；
   - `SceneStore(generalLightControlScene)`。
6. Power-up。
7. Sensitivity：presence sensor 节点下发 `motionSensitivity`。
8. 邻近照明路径同步在 profile 同步之后生成：
   - 如果 group 不再是 proximity 类型且节点当前 `proximityLightingEnabled == true`，发送 `proximityLightingEnabled(false)`；
   - 如果邻居列表相同但 relay count 不同且功能已启用，发送 `proximityLightingRelaySet`；
   - 否则发送 `proximityLightingNeighborSet(enabled: true, relay, ttl: 0, relayAppKeyIndex, neighborAddresses)`；
   - 如果邻居和 relay 都已一致但功能未启用，发送 `proximityLightingEnabled(true)`。
9. PIR protection：如适用恢复目标 PIR enable。

成功规则：

- Light LC 部分同 `occupancy` 的百分比亮度规则；
- proximity path 额外要求 `proximityLightingRelayCount` 和 `proximityLightingNeighborAddresses` 与目标一致，或 `proximityLightingEnabled` 等于目标。

### 8. `proximityLightingWithPhotocell`

目标行为：以 day/night lux 条件切换两套 proximity lighting scene。

默认新建 Profile 时有三个 scene：

- General Scene：保留在 Profile 里，但同步时被过滤掉，不作为 Light LC scene 下发；
- Night Scene：`generalLightControlScene + 1`，condition id = 0，默认 night lux = 30，默认 standbyLevel = 30；
- Day Scene：`generalLightControlScene + 2`，condition id = 1，默认 day lux = 70，默认三阶段亮度为 0。

SAVE 下发顺序：

1. UI 先校验 night / day lux。
2. PIR protection：如适用先禁用 PIR。
3. 初始化 / group subscription。
4. Sensor publication：
   - 当前本地 daylightType 不包含 `proximityLightingWithPhotocell`，因此不会使用 `sensorEnabled` 把 ambient light sensor publication 到 group address；
   - presence sensor publication 也不会按普通 occupancyType 启用。
5. 如果有 daylight calibration restore 数据，只有当 group 的 ambient light sensor 已校准或 restoreData 有校准数据时才会恢复。
6. Luminaire / light sensor node 上，Profile scenes 过滤掉 General Scene，只处理 Night Scene 和 Day Scene。
7. 对 Night Scene：
   - 如果 lux condition 不一致，先生成 `profileNightToggleTriggerConditionLux(id: 0, minLux: 0, maxLux: nightLux, useCalibrationValues, destination, sceneNumber)`；
   - 如果该 scene 的 Light LC 数据需要变更：
     - 如果节点支持 `.lightSensorConditionRecall` 且已有同 id condition，先 `daylightConditionRecall(id: 0)`；
     - 否则 `SceneRecall(nightSceneNumber)`；
     - 再设置 `LightLCModeSet(true)`；
     - `LightLCOccupancyModeSet(true)`；
     - `manualOverrideTimeout(... state: .standby ...)`；
     - `manualControlEnabled(false)`；
     - `lightAutoAdjustEnabled(false)`；
     - 因不是 daylightType，阶段值按百分比下发 `occupancyLevel`、`vacantLevel`、`standbyLevel`；
     - `t1 -> t2 -> t3 -> t4 -> t5`；
     - `SceneStore(nightSceneNumber)`。
8. 对 Day Scene：
   - 如果 lux condition 不一致，先生成 `profileDayToggleTriggerConditionLux(id: 1, minLux: dayLux, maxLux: UInt16.max, useCalibrationValues, destination, sceneNumber)`；
   - 如果 scene 数据需要变更，按 Night Scene 同样顺序 recall / set / store。
9. 如果本次包含 condition 设置或节点已有 lux trigger condition，同时又需要切换 scene，则整个过程外层包一组：
   - 最前 `profileToggleTriggerConditionLuxLock(delay: 600)`；
   - 最后 `profileToggleTriggerConditionLuxUnLock`。
   - Lock 时还会先插入 `daylightConditionRecallGet` 记录当前 condition；Unlock 时如果记录到了 index，会先恢复 `daylightConditionRecall(index)` 再解锁。
10. Power-up。
11. Sensitivity。
12. 邻近照明路径同步，同 `proximityLighting`。
13. PIR protection：如适用恢复目标 PIR enable。

成功规则：

- Night / Day condition 当前只校验 node 中存在对应 id，不校验 minLux / maxLux / destination / sceneNumber / useCalibrationValues 是否完全等于目标；
- scene store 只校验 `lightControlSceneExecuteDatas` 中存在 sceneNumber；
- switch / recall / lock / unlock 当前直接判定成功，只依赖消息发送结果和后续状态更新；
- 其它 Light LC、Power-up、Sensitivity、Proximity Path 规则同上。

## 重要差量条件

以下条件决定“是否下发”，不是每次 SAVE 都必发：

- `LightLCModeSet(true)`：只有 `lightLCProperty.mode` 为空或 false 时生成。
- `LightLCOccupancyModeSet`：目标值与当前 `lightLCProperty.occupancyMode` 不一致时生成。
- `manualOverrideTimeout`：enabled、timeout 毫秒值、manualControlState 任一不一致时生成。
- `manualControlEnabled`：manual Profile 目标 true，其它 Profile 目标 false，仅当前值不一致时生成。
- `lightAutoAdjustEnabled`：daylight 类且已校准目标 true，其它目标 false，仅当前值不一致时生成。
- 阶段亮度/lux、时间、adjustSpeed：逐项对比 Light LC property，只有不一致才生成。
- `SceneStore`：只有当前 scene 的 Light LC 数据发生变化并且节点支持 Light LC Scene 时生成。
- `PowerOnState`：只有 onPowerUp、默认亮度或默认 CCT 不一致时生成。
- `Sensitivity`：只在 occupancy 前四类或 proximity 两类，并且节点有 presence sensor 时检查。
- `ProximityLighting`：只在 profile 是 proximity 两类时配置；切走 proximity 且设备仍启用时会发送禁用。

## 不明确或需产品/协议确认的问题

1. 旧 `GroupProfilesViewController.profiles` 中的 `Photocell`、`Occupancy sensing with photocell`、`Vacancy sensing with photocell` 是否仍是未来需求？当前代码没有对应 `Profile.ProfileType`，也没有实际 SAVE 路径。
2. `proximityLighting` / `proximityLightingWithPhotocell` 在 `Profile.ProfileType.occupancyType` 中属于占用类，但在 `Node.getNodeSyncProfiles` 的本地 `occupancyType` 中不属于普通 presence sensor publication 类型。这会导致 proximity Profile SAVE 不通过 `sensorEnabled` 配置 presence sensor publication。需要确认这是协议设计，还是遗漏。
3. `profileDayToggleTriggerConditionLux` / `profileNightToggleTriggerConditionLux` 的成功规则当前只检查 condition id 是否存在，不检查 min/max lux、destination、sceneNumber、useCalibrationValues 是否一致。需要确认是否足够。
4. `daylightCalibrateRate`、`daylightCalibrateInflectionPoint`、`lightControlSwitch`、`daylightSensorConditionRecall`、`profileToggleTriggerConditionLuxLock/UnLock` 当前成功规则直接返回 true。需要确认是否接受“只要消息发送流程成功就视为成功”。
5. `lightControlStore` 已有 `turnOffBeforeStore` 参数，但当前 Group Profile SAVE 默认不再发送 `LightLCLightOnOffSet(false)`，只发送 `SceneStore`。需要确认所有 Profile SAVE 均应保持当前默认不关灯行为。

## 参考代码

- `SunSmart/Main/Profile/Model/Profile.swift`
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
- `SunSmart/Common/Data/Database.swift`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`
- `SunSmart/Common/Data/Node+MessageHandles.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
