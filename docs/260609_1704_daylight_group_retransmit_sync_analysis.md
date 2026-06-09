# Daylight Group 升级后显示需要同步问题分析

## 背景

- 旧 App commit：`027656b31e50a2afb59bf38644a6964e4ec9f914`
- 新 App HEAD：`08db6481d211732d82f20204fa6e71d1fe33a91c`
- 复现路径：旧 App 创建 `daylight harvesting (closed loop)` group，添加 members，完成 calibration，设备工作正常；升级到 HEAD 后，该 group 显示需要同步。
- 本文只分析根因和修复方案，不修改代码。

## 结论

根因是两个 commit 之间引入了 Sensor Server publication retransmit 的新同步语义。旧 App 只要求传感器 publication address 指向 group；新 App 要求 publication address 指向 group，并且 publication retransmit 必须等于 `group.sensorServerPublicationRetransmit(...)` 的目标值。

旧 App 的 daylight calibration 入口会把 ambient light sensor 的 publication 配到当前 group，但 retransmit 是 `.disabled`。这个配置在旧 App 判定为已同步，在 HEAD 会因为 retransmit 不匹配被 `getNodeSyncProfiles(...)` 加入 `.sensorEnabled(...)`，于是 `Node.needSyncGroupData` 变为 `true`，最终 group 显示需要同步。

这不是 daylight calibration 的 `AUTO` 恢复提交直接导致的，也不是设备现场功能突然失效。更准确地说，是新 App 的同步判定标准升级后，把旧 App 已能工作的配置判定为未达到新标准。

## 证据链

1. `Group.needSync` 依赖组内任一 node 的 `needSyncGroupData`。
   - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
   - `Group.needSync` 使用 `nodes.contains { $0.needSyncGroupData }`。
   - `Node.needSyncGroupData` 会调用 `getNeedSyncGroup()`，该流程最终进入 group profile 同步判断。

2. `Node.getSyncData(type: .group(...))` 会调用 `getNodeSyncProfiles(...)`。
   - `SunSmart/Common/Data/Node+SyncData.swift`
   - 如果 `getNodeSyncProfiles(...)` 返回非空，就追加 `.profile(types:)`，从而认为该 node 有 group data 需要同步。

3. HEAD 的 `getNodeSyncProfiles(...)` 对 sensor publication 使用完整配置比较。
   - `Group.sensorServerPublicationRetransmit(effectiveMemberCount:)`：
     - member count `<= 3` 时目标 retransmit 为 `2 / 100ms`。
     - member count `> 3` 时目标 retransmit 为 `1 / 100ms`。
   - `Model.isSensorServerPublicationConfigured(...)` 同时比较 publication address 和 retransmit。
   - daylight 类型 group 中，ambient light sensor 如果不满足该完整配置，就会加入 `.sensorEnabled(...)`。

4. 旧 commit 的同一判断只比较 publication address。
   - 旧逻辑中 ambient light sensor 只要 `publicationAddress == group.address` 就不再需要 `.sensorEnabled(...)`。
   - 旧逻辑的 `.sensorEnabled(...)` message 也固定使用 `.disabled` retransmit。

5. 当前 calibration 入口仍有直接写 `.disabled` retransmit 的代码。
   - `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
   - `sensorEnabled(sensor:)` 直接构造 `ConfigModelPublicationSet(Publish(... retransmit: .disabled), ...)`。
   - HEAD 后续的 `configuring(lightNodes:)` 可能会再通过 profile sync 补成目标 retransmit，但旧 App 没有这一步的新语义；升级后旧缓存自然会被新语义判定为待同步。

## 影响范围

### 会出现同类升级后需要同步的 Profile group

只要旧 App 已把 Sensor Server publication 配到 group，但 retransmit 是旧的 `.disabled`，HEAD 就可能显示需要同步。

按当前 `getNodeSyncProfiles(...)` 的 Profile 类型判断，受影响范围包括：

| Profile group | 受影响 sensor | 原因 |
| --- | --- | --- |
| `occupancy_daylight` | Ambient light sensor + occupancy sensor | 同时属于 daylight type 和 occupancy type |
| `vacancy_daylight` | Ambient light sensor + occupancy sensor | 同时属于 daylight type 和 occupancy type |
| `daylight` | Ambient light sensor | 属于 daylight type |
| `occupancy` | Occupancy sensor | 属于 occupancy type |
| `vacancy` | Occupancy sensor | 属于 occupancy type |

### 不属于本次 retransmit 兼容问题的 Profile group

| Profile group | 判断 |
| --- | --- |
| `manualControl` | 当前逻辑不会启用 ambient/PIR sensor publication；如果有旧的 sensor publication，仍可能走禁用清理，但不是本次 retransmit 新规则导致。 |
| `proximityLighting` | 当前 `getNodeSyncProfiles(...)` 的 sensor publication 启用判断没有把它纳入 occupancy type。 |
| `proximityLightingWithPhotocell` | 当前 daylight/occupancy sensor publication 启用判断也没有纳入它；它的 light sensor condition 配置属于另一条同步逻辑。 |

### 额外注意

新规则还会让 group member count 的变化影响目标 retransmit。`<= 3` 与 `> 3` 的目标 retransmit 不同，所以成员数量跨过 3/4 边界后出现同步需求是新规则的设计结果，不属于旧 App 升级兼容问题。

## 修复方案候选

### 方案 A：保持严格判定，允许旧 group 升级后提示同步

做法：不修改兼容逻辑。旧 group 升级后显示需要同步，用户执行一次同步后设备 publication retransmit 达到新标准。

优点：
- 最符合 `13f28bb9 Add sensor server publication retransmit design` 引入的新技术目标。
- 实现成本最低。

缺点：
- 用户会看到“升级 App 后原本正常的 group 变成需要同步”，体验上像回归。
- 大量历史现场可能集中出现同步提示。

### 方案 B：回退 retransmit 比较，只比较 publication address

做法：把 `isSensorServerPublicationConfigured(...)` 或调用方恢复成旧 App 语义，只要 address 正确就认为已同步。

优点：
- 可以完全消除旧 group 升级后的同步提示。
- 改动小。

缺点：
- 直接废掉新 retransmit 设计，后续新建/保存 Profile 也可能不再补齐目标 retransmit。
- 不能区分“旧配置兼容”和“新配置应该严格达标”。

### 方案 C：推荐，兼容旧配置，但新建/显式 SAVE 仍使用目标 retransmit

做法：
- 保留 `group.sensorServerPublicationRetransmit(...)` 作为新目标配置。
- 新增“兼容检查”和“严格同步”两种语义：
  - 普通 `needSyncGroupData` / group 列表展示时，如果 Sensor Server publication address 已经指向 group，且 retransmit 是旧 App 的 `.disabled`，允许认为 legacy-compatible，不显示需要同步。
  - 用户执行 Profile SAVE、member add 后的同步、calibration 后的配置同步、明确的 resync 时，仍使用严格目标 retransmit，生成并下发 `.sensorEnabled(... retransmit: target)`。
- 把 `LightSensorCalibrationViewController.sensorEnabled(sensor:)` 的直接 publication message 也改为使用 `group.sensorServerPublicationRetransmit(...)`，避免 HEAD 自己继续先写入旧 `.disabled` 语义。

优点：
- 不让旧 App 升级后的正常 group 仅因 retransmit 变严格而显示同步提示。
- 保留新规则：后续用户显式保存或重新配置时，设备仍会被升级到目标 retransmit。
- 兼容范围可以精确限制在 Sensor Server publication address 已正确指向当前 group 的 legacy `.disabled` 情况，不会掩盖 address 错误、缺 publication、传感器缺失等真实同步问题。

缺点：
- 需要给 `getNodeSyncProfiles(...)` 或其调用链增加上下文，避免同一函数在“展示 need sync”和“生成 SAVE 任务”时混用同一种判断语义。
- 需要补测试覆盖，否则容易再次出现保存路径被兼容逻辑吞掉的问题。

## 推荐修复设计

采用方案 C。

### 1. 抽出 Sensor Server publication 判断策略

在 Sensor Server publication helper 层增加两类判断：

- 严格判断：address 和 retransmit 都必须匹配目标值。
- legacy-compatible 判断：address 必须匹配；如果 retransmit 已是目标值，返回已同步；如果 retransmit 是旧 App 的 `.disabled`，也允许返回已同步，但只用于普通展示/自动 need-sync 计算。

不建议把兼容逻辑写成“任意 retransmit 都通过”。只能接受 `.disabled` 这个明确的旧 App 状态，否则会掩盖错误配置。

### 2. 区分 need-sync 展示与同步任务生成

`getNodeSyncProfiles(...)` 现在同时服务于：

- group 列表是否显示需要同步；
- Sync Devices 页面生成任务；
- Profile SAVE、member add、calibration 等显式配置流程。

需要给调用链增加明确上下文，例如 `sensorPublicationCheckMode`：

- `.legacyCompatible`：用于普通 `needSyncGroupData` 展示。
- `.strictTarget`：用于显式 SAVE / calibration / member add / resync 任务生成。

已有 `GroupProfileSyncContext` 可以作为扩展点，但要避免只覆盖 Profile SAVE，遗漏 group 列表和 calibration。

### 3. 修正 calibration 直接写 publication 的目标值

`LightSensorCalibrationViewController.sensorEnabled(sensor:)` 不应继续直接写 `.disabled` retransmit。即使后续 `configuring(...)` 会尝试补齐，也会产生一次不必要的旧配置写入。

目标：calibration 入口第一次写 Sensor Server publication 时就使用 `group.sensorServerPublicationRetransmit(...)`。

### 4. 覆盖所有相关 Profile 类型

修复不能只针对 `.daylight`，否则 `.occupancy_daylight`、`.vacancy_daylight` 以及纯 occupancy/vacancy group 仍可能在旧 App 升级后出现相同问题。

兼容判断应作用于 Sensor Server publication 这一底层规则，而不是散落在某个 Profile case。

## 验证计划

1. 静态回归验证：
   - 对比旧 commit 的 `getNodeSyncProfiles(...)` 与 HEAD，确认旧 address-only 配置会在 legacy-compatible 模式下不触发 need-sync。
   - 确认 address 错误、publication 缺失、非 `.disabled` 且非目标 retransmit 的错误配置仍触发 need-sync。

2. 单元或轻量模型测试：
   - 构造 daylight group，ambient light sensor publication address 指向 group，retransmit 为 `.disabled`，普通 need-sync 返回 false。
   - 同样数据在 strict 模式下返回 `.sensorEnabled(...)`。
   - 构造 occupancy group，PIR sensor publication address 指向 group，retransmit 为 `.disabled`，普通 need-sync 返回 false，strict 模式返回同步项。
   - 构造 member count `3` 与 `4` 的 group，严格模式目标 retransmit 分别为 `2 / 100ms` 与 `1 / 100ms`。

3. 手工路径验证：
   - 用旧 App 数据升级到 HEAD，已经校准且工作正常的 daylight closed loop group 不再仅因 legacy retransmit 显示需要同步。
   - 对同一个 group 执行一次 Profile SAVE 或 calibration，确认下发的 Sensor Server publication 使用目标 retransmit。
   - 对 `occupancy_daylight`、`vacancy_daylight`、`occupancy`、`vacancy` 各抽样验证旧数据升级后的显示状态。

4. 构建验证：
   - 按项目规则优先使用 iPhoneOS 构建：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险和边界

- 如果产品要求所有历史设备都必须立即升级到新 retransmit 规则，那么方案 A 才是正确行为；但这意味着升级后显示需要同步是预期，不应修复。
- 如果采用方案 C，旧配置会被视为 legacy-compatible，设备可能保持旧 `.disabled` retransmit，直到用户执行显式 SAVE/calibration/resync。这是为了避免升级噪音而接受的兼容折中。
- 不应修改 Battery/AC Power Switch 的 retransmit 逻辑；本问题只涉及普通 Profile Sensor Server publication。
- 不应把兼容范围扩大到任意 retransmit 值，否则会隐藏真实配置错误。

