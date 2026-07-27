# Kinetic Switch 色温控制误改单色灯亮度：原因分析与修复方案

## 1. 问题结论

该问题不是 Scene Recall、按键动作编码或 L3 固件误判导致，而是 App 在创建 Kinetic Switch 时，通过 `NordicSigMeshSDK` 错误地把 L3 的“亮度 Generic Level Server”订阅到了开关专用的“色温虚拟组”。

Cooler / Warmer 长按最终由代理节点的 Generic Level Client 向色温虚拟组发送 Level Move。由于 L3 的亮度 Level Model 被错误订阅到该组，L3 会把 Level Move 当作亮度调节执行，因此亮度随 Cooler / Warmer 变化。

`Scene Panel (4 key)` 存在同样问题。它和 `Default (4 key) Panel` 的右侧长按动作使用同一套 CCT 目标地址与订阅生成逻辑，仅短按 Scene Recall 的场景数量不同。

## 2. 日志证据

日志文件：

`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/fix/create switch log 260727.txt`

### 2.1 开关动作地址正确分流

- 主控制虚拟组：`0xC003`（49155）
- 色温虚拟组：`0xC004`（49156）
- Key 2：`cctUp(address: 49156)`，对应 Cooler
- Key 1：`cctDown(address: 49156)`，对应 Warmer

这说明按键数据构建层已经把亮度和色温分配到两个不同虚拟组，问题不在 `DeviceSwitchData.switchKeys` 的目标地址选择。

### 2.2 L1、L2 的正确色温订阅

日志为两盏色温灯的次级元素添加：

- `ConfigModelSubscriptionAdd(address: 49156, elementAddress: 12, modelIdentifier: 4098)`
- `ConfigModelSubscriptionAdd(address: 49156, elementAddress: 20, modelIdentifier: 4098)`

其中 `modelIdentifier: 4098` 即 SIG Model `0x1002`（Generic Level Server）。在色温灯的 Light CTL Temperature 元素上，该 Level Model 用于相对色温调节。

### 2.3 L3 的错误色温订阅

日志还为 L3 添加：

- `ConfigModelSubscriptionAdd(address: 49156, elementAddress: 22, modelIdentifier: 4098)`

L3 的设备信息为 CID `0x0A78`、PID `0x2011`，仅有调光能力。其 element `0x0016` 上的 `0x1002` 是亮度 Generic Level Server，不是色温 Level Model。该错误订阅返回 `Success`，说明设备接受了配置，但不代表配置语义正确。

## 3. 代码数据流

### 3.1 Panel 动作生成

文件：`SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`

- `default_4key`：
  - Key 2 长按为 `cctUp(subLinkGroupAddress)`
  - Key 1 长按为 `cctDown(subLinkGroupAddress)`
- `scenes_4key`：
  - Key 2 长按仍为 `cctUp(subLinkGroupAddress)`
  - Key 1 长按仍为 `cctDown(subLinkGroupAddress)`

因此两个 4-key Panel 都会进入相同的 CCT 订阅路径。

### 3.2 App 同步入口

文件：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

App 对每个绑定 Group 中的 Node 调用 SDK 的 `getEnOceanSubscriptionMessageHandles(switchKeys:)`。设备是否应订阅色温组，实际由 SDK 返回的目标 Model 决定。

### 3.3 SDK 错误回退

文件：`NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`

`ctlTemperatureLevelModel` 的当前逻辑为：

1. 如果存在 Light CTL Temperature Server，则返回同元素的 Generic Level Server；
2. 如果不存在 Temperature Model，则回退到 `levelModels.last`。

对 L3 来说，`levelModels` 只有一个亮度 Level Model，因此 `first` 和 `last` 是同一个 Model。SDK 把它误认为色温 Level Model。

文件：`NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift`

`getEnOceanSubscriptionMessageHandles` 对 `cctUp / cctDown` 直接使用上述 `ctlTemperatureLevelModel`，最终生成 L3 的错误 `0xC004 -> 0x1002` 订阅。

该回退由 SDK 提交 `7369797`（`enOcean开关cct level client model读取优化`）引入。提交前只有 `levelModels.count >= 2` 时才选择第二个 Level Model，单色灯不会进入 CCT 订阅。

## 4. Scene Panel (4 key) 判断

结论：同样存在。

两种 Panel 的差异只在短按动作：

- Default：ON/AUTO、OFF、Scene A、Scene B
- Scene Panel：Scene A、Scene B、Scene C、Scene D

两者的长按动作完全一致：

- 左侧：Dim Up / Dim Down，发送到主控制虚拟组
- 右侧：Cooler / Warmer，发送到色温虚拟组

因此只要 Group 中包含仅调光设备，Scene Panel 创建或重新同步时也会把该设备的亮度 Level Model 错误订阅到色温虚拟组。

## 5. 修复方案比较

### 方案 A：仅收紧 `ctlTemperatureLevelModel`

不存在 Light CTL Temperature Server 时直接返回 `nil`，不再回退到任意 Level Model。

优点：

- 改动最小；
- 从能力模型源头修正错误语义；
- 新创建或尚未错误订阅的单色灯不会再订阅色温组。

不足：

- 已经错误订阅 `0xC004` 的 L3 不会自动解除订阅；
- 升级后既有 Switch 仍会继续误控，除非删除设备数据、重新配网或另加清理逻辑。

不建议单独采用。

### 方案 B：严格识别 CCT Model，并对历史错误订阅做能力感知的对账修复

这是推荐方案。

1. `ctlTemperatureLevelModel` 只允许从 Light CTL Temperature Server 所在元素解析 Generic Level Server；没有 Temperature Model 时返回 `nil`。
2. 生成 EnOcean CCT 订阅时：
   - 色温灯：订阅真正的 Temperature Level Model；
   - 单色灯：不生成 CCT 订阅；
   - 如果单色灯的亮度 Level Model 已经订阅该 CCT 虚拟组，生成 Subscription Delete，清理历史错误状态。
3. 生成解绑消息时，同时覆盖正确 CCT Model 和历史错误的亮度 Level Model，确保删除 Switch、移出 Group、重新同步都能收敛到正确状态。
4. 不修改 Panel 按键定义、虚拟组分配、场景选择或代理节点发布逻辑。

优点：

- 同时修复新配置和既有错误配置；
- 修复位于 SDK 的能力识别与订阅边界，所有调用入口一致生效；
- Default / Scene Panel 无需分别打补丁；
- 既有 Switch 可通过当前 Resync 流程清理错误订阅。

代价：

- 比方案 A 多一小段历史状态清理逻辑；
- 需要验证删除或移出 Group 时不会残留旧订阅。

### 方案 C：仅在 App 层按 `effectiveSupportCct` 过滤 Node

在 App 的 Switch 同步规划层跳过单色灯的 CCT 配置。

优点：

- 不改变 SDK 的通用 Model 解析属性。

不足：

- SDK 仍会把亮度 Model 暴露为 CCT Model，根因保留；
- App 的创建、重同步、移组、删 Switch 等入口都要重复防守；
- 历史错误订阅清理更分散；
- 其他 SDK 调用方仍可能复现。

不建议。

## 6. 用户确认后的实施范围

2026-07-27 用户确认采用方案 B 的严格能力识别主路径，但明确不处理已经错误配置的设备；既有设备通过删除 Switch 后重新添加恢复。因此本次不实现历史错误订阅的 Subscription Delete 或迁移逻辑。

改动限制在本地 `NordicSigMeshSDK`，App 继续使用当前本地 Swift Package 引用。

预计修改：

- `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
  - 收紧 `ctlTemperatureLevelModel` 的能力语义。
- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift`
  - 不需要业务修改；现有 CCT 订阅逻辑会在 `ctlTemperatureLevelModel == nil` 时自然跳过单色灯。
- `Sources/NordicSigMeshSDK/MeshLib/Node/CctLevelModelResolver.swift`
  - 把 Temperature 元素到对应 Level Model 的选择提取为可独立运行的纯 Swift 决策。
- `Tests/Standalone/CctLevelModelResolverTests.swift`
  - 单色灯没有 Temperature 元素时不能得到 CCT Level Model；
  - 色温灯继续从 Temperature 元素解析 Generic Level Server；
  - Temperature 元素缺少 Level Model 时返回空。

不纳入本次范围：

- 已经错误配置的设备及其历史 CCT 虚拟组订阅清理；
- 日志中相同订阅消息重复生成的优化；
- Panel UI、文案、场景数量或按键布局调整；
- 与 Kinetic Switch 无关的 Group / Scene 重构。

## 7. 验证计划

### 7.1 自动化与静态验证

1. 先增加失败测试，复现“单色灯被识别为拥有 CCT Level Model”。
2. 实施最小修复后验证上述测试转绿。
3. 检查现有 Default / Scene Panel 映射均继续把 Cooler / Warmer 指向 `subLinkGroupAddress`。
4. 对 App 与 SDK 分别运行 `git diff --check`。
5. macOS `swift test` 可能仍被 SDK 既有 `UIKit` 依赖阻断；若发生，只能记录为未进入测试执行，不能宣称 XCTest 已通过。

### 7.2 iPhoneOS 编译验证

使用 generic iPhoneOS、关闭签名，分别验证：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

不使用 Simulator。

### 7.3 真机 Mesh 验收

对 Default (4 key) 和 Scene Panel (4 key) 各验证一次，均使用 L1 / L2 色温灯和 L3 单色调光灯：

1. 新建 Switch：
   - L1、L2 订阅 CCT 虚拟组；
   - L3 不出现针对 CCT 虚拟组的 Subscription Add。
2. 长按 Cooler / Warmer：
   - L1、L2 色温变化；
   - L3 亮度保持不变。
3. 长按 Dim Up / Dim Down：
   - L1、L2、L3 亮度均正常变化。
4. 短按 Scene：
   - Default Panel 的 Scene A / B 正常；
   - Scene Panel 的 Scene A / B / C / D 正常。
5. 删除并重新添加 Switch 后再次验证上述行为；不要求升级后对旧 Switch 执行迁移或 Resync 修复。

## 8. 风险与边界

- 自动化、静态检查与 iPhoneOS 编译只能证明代码路径和编译集成正确，不能替代真实 Mesh 设备验收。
- 日志中的 Config Status `Success` 只代表设备接受消息，不代表订阅到了正确语义的 Model。
- 既有错误订阅不会由本次代码自动清理；必须按用户确认的方式删除 Switch 后重新添加。
