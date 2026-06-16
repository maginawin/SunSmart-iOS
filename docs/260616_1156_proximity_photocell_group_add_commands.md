# Proximity Lighting With Photocell 入组命令分析

## 结论

在当前源码里，用户把一个新灯设备添加到 `proximityLightingWithPhotocell` 组时，App 会按 `GroupProfileSyncContext(reason: .memberAdded)` 生成强制完整 profile sync。假定该设备是灯、支持 PIR、Lux sensor、亮度和色温，则实际下发命令分为四类：

1. 组订阅：把设备相关 server model 订阅到目标 group。
2. Light LC profile：启用 Light LC / Occupancy Mode，写入亮度阶段、时间参数、manual override、power up、PIR 灵敏度。
3. Photocell day/night condition：写入 night/day lux condition，并在需要时通过 daylight condition recall 切换到对应 Light LC scene。
4. Proximity lighting vendor 配置：写入邻近节点列表、relay count，并启用 proximity lighting。

注意：`proximityLightingWithPhotocell` 不走 daylight harvesting closed-loop 的 `Light Control Ambient LuxLevel On` 作为主目标 lux。这里的 photocell 是通过 vendor daylight condition 触发 day/night scene，而 Light LC 阶段仍使用百分比亮度。

## 入口链路

- Classic Add Device 和 Professional Add Device 都会对 light 设备使用 `GroupProfileSyncContext(reason: .memberAdded)`。
- `memberAdded` 会让 `shouldForceFullProfileSync == true`，因此新成员不是只补 group subscription，而是强制完整下发该 group profile。
- Add Device 使用 `DeviceGroupFastAddSyncPlanner.makePlan(...)`：
  - light 设备：`node.getSyncData(type: .group(...), profileSyncContext: memberAdded)`。
  - immediate handles + deferred task handles 被展开进 provisioning 后的 append messages。
  - `SceneRecall` 会在 fast-add deferred task 里被过滤掉，避免添加阶段直接切换现场灯光 scene。

## 命令顺序

以下是组相关命令的逻辑顺序。实际是否发送某条命令取决于设备本地缓存、设备 capabilities、当前 group profile、已有订阅和已有 condition 是否已经一致；但 `memberAdded` 会让 profile 项尽量完整下发。

### 0. Add Device 通用前置

如果设备支持 CTL 且当前尚未读取色温范围，Add Device append message 前面可能先插入：

- `LightCTLTemperatureRangeGet`，opcode `0x8262`

这不是 proximity photocell profile 的核心命令，只是新设备入网后的能力/范围读取。

### 1. 初始化与组订阅

如果 key bind/config 尚未完成：

- device initialize / config messages，来自 `node.getInitializeMessageHandles()` 或 `node.getConfigMessageHandles()`

如果设备没有完整订阅目标 group：

- `ConfigModelSubscriptionAdd`，opcode `0x801B`

当前 App 启动时把以下 model 列入 group subscription：

- `Generic OnOff Server`
- `Light Lightness Server`
- `Light CTL Temperature Server`
- `Light CTL Server`
- `Sensor Server`
- `Light LC Server`

因此在“支持亮度和色温”的假设下，Lightness、CTL、CTL Temperature 相关 model 会被订阅。Sensor Server / Light LC Server 也会随配置列表订阅；这只是接收 group 控制/状态所需的订阅，不等同于 PIR publication 被配置到 group。

### 2. Profile 前置配置

`proximityLightingWithPhotocell` 设备会进入 Light LC profile 配置。典型顺序：

1. `LightLightnessRangeSet`，opcode `0x825B`
   - 设置 High / Low End Trim。
2. 删除设备上多余的 Light LC scene 或旧 lux trigger condition。
   - `SceneDelete`
   - `SunricherVendorSet(.daylightExecuteSceneSet(... zero ...))`
3. 针对每个有效 profile scene，按 scene 逐个生成配置。

### 3. 每个 night/day scene 的配置顺序

对 `proximityLightingWithPhotocell`，general scene 会被过滤，重点是 Night Scene 和 Day Scene。

对每个 night/day scene，如果设备有 ambient light sensor model 和 Sunricher vendor model，会先准备对应 lux condition：

- Night condition：`profileNightToggleTriggerConditionLux`
  - id 默认 `0`
  - minLux `0`
  - maxLux = night starts below lux，默认 `30`
  - destination = 设备 Light LC Scene model 所在 element 地址，缺省回退 Light LC model element / primary unicast
  - sceneNumber = Night Scene
- Day condition：`profileDayToggleTriggerConditionLux`
  - id 默认 `1`
  - minLux = day starts above lux，默认 `70`
  - maxLux `0xFFFF`
  - destination 同上
  - sceneNumber = Day Scene

如果设备支持分段 condition set，会拆成：

1. `SunricherVendorSet(.daylightConditionLuxThresholdSet)`，vendor opcode `0xF0780A`，参数 code `0x31 0x3C`
2. `SunricherVendorSet(.daylightExecuteSceneActionSet)`，vendor opcode `0xF0780A`，参数 code `0x31 0x3D`
3. `SunricherVendorSet(.daylightConditionLuxUseCalibrationValuesSet)`，vendor opcode `0xF0780A`，参数 code `0x31 0x3E`

如果不支持分段 condition set，则合并为：

- `SunricherVendorSet(.daylightExecuteSceneSet)`，vendor opcode `0xF0780A`，参数 code `0x31 0x3A`

随后才进入该 scene 的 Light LC 参数写入：

1. `LightLCModeSet(true)`，opcode `0x8292`
2. `LightLCOccupancyModeSet(true)`，opcode `0x8296`
3. `SunricherVendorSet(.manualOverrideTimeout(...))`，vendor opcode `0xF0780A`，参数 code `0x32`
4. `SunricherVendorSet(.manualControlEnabled(false))`，vendor opcode `0xF0780A`，参数 code `0x33`
5. `SunricherVendorSet(.lightAutoAdjustEnabled(false))`，vendor opcode `0xF0780A`，参数 code `0x34`
6. `LightLCPropertySet(.lightControlLightnessOn)`，opcode `0x62`，property id `0x002E`
7. `LightLCPropertySet(.lightControlLightnessProlong)`，opcode `0x62`，property id `0x002F`
8. `LightLCPropertySet(.lightControlLightnessStandby)`，opcode `0x62`，property id `0x0030`
9. `LightLCPropertySet(.lightControlTimeFadeOn)`，opcode `0x62`，property id `0x0037`
10. `LightLCPropertySet(.lightControlTimeRunOn)`，opcode `0x62`，property id `0x003C`
11. `LightLCPropertySet(.lightControlTimeFade)`，opcode `0x62`，property id `0x0036`
12. `LightLCPropertySet(.lightControlTimeProlong)`，opcode `0x62`，property id `0x003B`
13. `LightLCPropertySet(.lightControlTimeFadeStandbyAuto)`，opcode `0x62`，property id `0x0038`
14. `SceneStore(sceneNumber)`，opcode `0x8246`

如果设备支持 `lightSensorConditionRecall` 且本地已有目标 condition index，切换 scene 用：

- `SunricherVendorSet(.daylightConditionRecall(index))`，vendor opcode `0xF0780A`，参数 code `0x31 0x3F`

否则切换 scene 用：

- `SceneRecall(sceneNumber)`，opcode `0x8242`

但在 Add Device fast-add deferred task 里，`SceneRecall` 会被过滤；`daylightConditionRecall` 不属于 `SceneRecall` 类型，不会被这个过滤器移除。当前修复逻辑会保证 condition 写入排在 recall 前。

### 4. Photocell lock / unlock

如果 profile 同步中包含 day/night condition 配置，或设备上已有 lux trigger conditions，并且本轮需要 profile switch / recall，则 App 会把整段 profile 配置包在 lock/unlock 中：

1. 队首插入 `SunricherVendorSet(.daylightLuxTriggerLock(delay: 600))`
   - vendor opcode `0xF0780A`
   - 参数 code `0x31 0x3B`
   - delay `600` 秒，即 payload `31 3B 58 02`
2. 所有 condition、Light LC 参数、SceneStore 等配置
3. 队尾追加 `SunricherVendorSet(.daylightLuxTriggerLock(delay: 0))`
   - 用作 unlock

同步页执行 lock task 时还会先插入：

- `SunricherVendorGet(.daylightConditionRecallGet)`，vendor get opcode `0xF1780A`，参数 code `0x31 0x3F`

用于记录当前运行的 day/night condition index，unlock 时如有旧 index，会先恢复：

- `SunricherVendorSet(.daylightConditionRecall(index: oldIndex))`

### 5. Power Up 与 PIR 灵敏度

profile scene 配置之后，继续同步 group profile 的全局项：

- `GenericOnPowerUpSet`，opcode `0x8213`
- 如果 Power Up 是 defined light level 且设备支持 CCT：
  - `LightCTLDefaultSet`，opcode `0x8269`
  - 同时写默认 lightness 和默认 color temperature
- `SunricherVendorSet(.motionSensitivity(...))`，vendor opcode `0xF0780A`，参数 code `0x40`

这里的 PIR 支持主要体现在：

- Light LC Occupancy Mode 开启
- motion sensitivity 下发
- proximity lighting vendor 邻居触发配置

当前 `getNodeSyncProfiles` 不会因为 `proximityLightingWithPhotocell` 把 PIR Sensor Server publication 配到 group；普通 Sensor publication enable 只覆盖 occupancy / vacancy 相关类型，不含 proximity 类型。

### 6. Proximity lighting vendor 配置

最后 `getNodeSyncProximityLighting(group:)` 会按 group 的 path / zone 计算邻居节点：

- 如果邻居列表和 relay count 已一致，但设备未启用 proximity lighting：
  - `SunricherVendorSet(.proximityLightingEnabled(true))`
  - vendor opcode `0xF0780A`
  - 参数 code `0x41 0x01`
- 如果已启用、邻居一致但 relay count 不一致：
  - `SunricherVendorSet(.proximityLightingRelaySet(relay))`
  - vendor opcode `0xF0780A`
  - 参数 code `0x41 0x03`
- 否则：
  - `SunricherVendorSet(.proximityLightingNeighborSet(enabled: true, relay, ttl: 0, relayAppKeyIndex, neighborAddresses))`
  - vendor opcode `0xF0780A`
  - 参数 code `0x41 0x02`

`proximityLightingNeighborSet` payload 顺序为：

1. relay app key index
2. enabled
3. relay count
4. ttl
5. neighbor count
6. neighbor addresses

## 重试策略

### Add Device fast-add path

Add Device 的 fast-add path 没有弹同步页那种逐 task 自动 retry。它把 group sync append messages 直接交给 provisioning 后续消息发送：

- append message 成功：立即 `node.updateData(message:)` 更新本地缓存。
- append message 失败：如果该 message 属于 fast-add group sync plan，则记录该 plan 失败、清同步缓存、更新 group sync state。
- 添加成功回调里再执行 `resolveFastAddGroupSyncFailed(for:)`：
  - 只要有 fast-add append message 失败，判定 group sync failed。
  - 或者所有发送看似成功，但 verification operation 仍不成功，也判定 group sync failed。
  - 设备添加本体仍可成功，但 UI 状态变为 `.syncFailed`。

### SyncDevicesViewController path

同步页路径有两层重试：

1. 普通同步页失败后，用户可以点击 Retry；`automationRestore` 场景会自动重试 2 次。
2. `DeviceGroupDeferredSyncPlanner.run(...)` 默认 `maxRetryCount = 2`，即同一个 deferred task 最多执行 3 次。

`DeviceGroupDeferredSyncPlanner` 每次 task 完成后会：

- 对每个 handle 调用 `node.updateData(message:isSuccess:)`
- 清 node sync cache
- 用两个条件判断 task 成功：
  - 所有 result handles 都 `isSuccessful == true`
  - `task.operationType.isSuccessful == true`

如果失败且 retry 次数未耗尽，就重建新的 `MeshMessageHandle` 再发一次；如果耗尽，会清 cache、更新 group sync state，并把该 task 记为失败。

## daylightConditionRecall 异常处理

对 `daylightConditionRecall(index:)`，当前源码有专项恢复：

- 只处理 vendor status 失败
- code 必须是 `daylightConditionRecall`
- `errorCode == 2`
- 同一轮同步里同一设备同一 index 只恢复一次

恢复动作：

1. 优先从当前同步 step 的 day/night condition task 中找同 index 的 condition。
2. 找不到时，从当前 group profile 的 night/day data 推导 condition。
3. 将该 condition 强制 `forceFullSet: true`，先补写 condition。
4. 再重发 `SunricherVendorSet(.daylightConditionRecall(index))`。

这层恢复不会吞掉失败；如果补写 condition 或 recall 重试仍失败，最终同步仍显示失败。

## 成功判断

Add Device fast-add path 的成功条件：

- provisioning / add device 本体成功；
- fast-add group sync append message 没有失败；
- verification operations 全部成功。

具体到本问题，关键 verification 包括：

- group subscription 已存在；
- Light LC mode、occupancy mode、Light LC lightness/time properties 与目标值一致；
- power up 状态一致；若 defined light level 且支持 CCT，则默认 CCT 也一致；
- motion sensitivity 等于 group profile sensitivity；
- day/night lux trigger condition index 已存在；
- SceneStore 后本地 Light LC scene execute data 已包含目标 scene；
- proximity lighting 邻居列表和 relay count 与计算结果一致。

部分操作的 `isSuccessful` 当前只做弱判定：

- `daylightSensorConditionRecall` 返回 true，主要依赖 handle ACK / vendor status；
- lock / unlock 返回 true，主要依赖 handle ACK / vendor status；
- proximity lighting enabled / relay 单独操作返回 true，neighbor set 才校验 relay count 和 neighbor list；
- daylight calibration rate / inflection point 返回 true。

因此最终“设备添加成功但显示 sync failed”的常见含义是：设备入网成功，但上述 group profile / condition / proximity vendor 配置中至少一项没有 ACK 成功，或 ACK 后本地状态未达到 verification 条件。

## 主要代码位置

- `SunSmart/Common/Data/Node+SyncData.swift`
  - `GroupProfileSyncContext`
  - `getSyncData(type:profileSyncContext:)`
  - `getNodeSyncProfiles(...)`
  - `getNodeLightDataSyncProfiles(...)`
  - `getNodeSyncProximityLighting(group:)`
- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - `NodeSyncData.getMessageHandles(node:)`
  - `ProfileType.getMessageHandles(node:)`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - fast-add plan 展开
  - deferred task retry / success 判定
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Classic Add Device fast-add group sync plan 注册和失败回写
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Professional Add Device fast-add group sync plan 注册和失败回写
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 同步页 task 依赖、retry、daylightConditionRecall recovery
- `NordicSigMeshSDK`
  - `SunricherVendorSet`
  - `SunricherVendorStatus`
  - `LightLCPropertySet`
  - `ConfigModelSubscriptionAdd`
