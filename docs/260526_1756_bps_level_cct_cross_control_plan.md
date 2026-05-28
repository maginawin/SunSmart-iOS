# BPS Level Up/Down 同时控制 Light 色温问题分析

## 背景

场景：Site - Space - 添加设备 - 恢复设备数据中，同时恢复 battery power switch 与 light。上一轮修复后，light 不再因为 BPS 后完成而被误标记为恢复失败。

新问题：battery power switch 的 level up/down 能同时控制 light 的色温变化。怀疑方向是 light 的色温相关 model 订阅了 BPS 虚拟组，或 BPS target subscription 没有按 BPS 设备 profile/按键功能精确生成。

## 当前证据

### BPS 按键动作

`PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 会把所有按键动作发到 `linkGroupAddress`，也就是 BPS 的虚拟组。

位置：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:189`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:262`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:275`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:286`

level up/down 对应：

- click：`levelDelta`
- press：`levelMove`
- pressRelease：`levelMove` level = 0

这些动作本质上是 Generic Level 语义。它们不是 Light CTL 专用消息，也不会天然区分“亮度 level”与“色温 level”；区别完全取决于 BPS 虚拟组被订阅到了 light 的哪个 model/element。

### Light target subscription

修复前 BPS target subscription 的入口是：

- `SunSmart/Common/Data/Node+MessageHandles.swift:119`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1770`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1790`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1808`

修复前代码的目标是只订阅：

- Generic OnOff Server
- 亮度 element 上的 Generic Level Server
- Scene Server
- Light Lightness Server
- Light LC Server

并且把其它 Generic Level Server 当作 obsolete cleanup：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1763`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1780`

这说明代码已经有“不要让 CTL Temperature 的 Generic Level 订阅 BPS 虚拟组”的设计意图。

### 日志中的异常订阅

上一段恢复日志里，BPS 虚拟组 `0xC00B` / `49163` 出现了 light 第二 element 的 Generic Level Server 订阅成功：

- `ConfigModelSubscriptionStatus(status: Success, address: 49163, elementAddress: 435, modelIdentifier: 4098, ...)`

`4098` 是 `0x1002`，即 Generic Level Server。对于 CTL light，第二 element 上的 Generic Level Server 通常对应 CTL Temperature 的 level 通道。因此 BPS level up/down 发到 `0xC00B` 后，会同时命中亮度 level 与色温 level，表现为亮度和色温一起变化。

## 根因判断

直接原因：light 的色温相关 Generic Level 通道订阅了 BPS 的虚拟组，BPS level up/down 的 Generic Level 动作被该通道消费。

更深层原因有两个：

1. BPS target subscription 的期望模型集合目前是静态 capability 逻辑，没有从实际 `batteryPowerSwitchKeyConfigurations` 的动作类型反推需要订阅哪些模型。
2. 旧版本或恢复流程中可能已经把 CTL Temperature 相关 model / Generic Level model 订阅到了 BPS 虚拟组；修复前 cleanup 只覆盖“其它 Generic Level Server”，且依赖本地 `model.isSubscribed(to:)` 状态。如果本地缓存与设备实际订阅不一致，或者恢复成功过滤按 node/group 粗粒度吞掉了未完成 cleanup，就可能留下真实设备端的错误订阅。

这不是 profile 参数本身导致的色温变化；profile 只是决定 light 的 LC/场景/默认值等设备配置。BPS level up/down 是否影响色温，主要由 BPS 虚拟组订阅到了哪些 model 决定。修复应让订阅集合由 BPS 按键动作能力决定，而不是泛化订阅 light 的所有相关控制能力。

## 修复目标

- BPS level up/down 只控制 light 亮度，不改变色温。
- BPS scene recall / on-off / auto 等已有功能保持不变。
- 如果未来确实配置了 CCT 相关 BPS action，例如 `ctlTemperatureSet`，才订阅 CCT 所需 model。
- 本次不处理历史错误订阅 cleanup；现场通过重置设备清除旧订阅状态。

## 修复方案

### 1. 增加 BPS target model 规划器

在 `MeshNetwork+SunSmart.swift` 中把 BPS target model 计算从静态 capability list 改为 action-aware 规划。

输入：

- `PJEightKeySwitchData`
- target `Node`
- 当前 appKeyIndex

输出：

- desired models：本轮 BPS 配置真正需要订阅到 link group 的 models

建议映射：

- `onOffToggle` / `onOffSet`：Generic OnOff Server
- `lightCtrlOnOff`：Light LC Server
- `levelDelta` / `levelMove`：亮度 element 上的 Generic Level Server，只能使用 `node.levelModel` 或现有 `batteryPowerSwitchBrightnessLevelModel`
- `lightnessSet`：Light Lightness Server
- `sceneRecall`：Scene Server
- `ctlSet` / `ctlTemperatureSet`：只有出现这些 action 时，才加入 CTL Server / CTL Temperature Server

生成订阅消息时：

- desired 且未订阅：发送 add
- desired 已订阅：不发送

### 2. 同步入口统一使用新规划器

以下入口都应走同一个 BPS target model 规划器，避免 restore、普通同步、添加设备逻辑不一致：

- `Node.getBatteryPowerSwitchSubscriptionMessageHandles`
- `Node.getBatteryPowerSwitchTargetSubscriptionMessageHandles`
- `SyncDevicesCellModel` 中 BPS target subscription 的完成判断
- `SyncDevicesViewController` 中 BPS target subscription 的任务生成
- `DeviceRestoreViewController` 中恢复后是否忽略 sync failed 的判定

### 3. 增加诊断日志

在生成 BPS target subscription handles 时输出摘要：

- BPS name / link group
- target node address / name
- desired model list
- key action types

现场如果再出现 level up/down 影响色温，可以直接确认 CTL Temperature 相关 model 是否仍在 BPS 虚拟组里。

### 4. 验证计划

自动化优先级：

- 当前工程没有 XCTest target，需要先确认是否新增轻量测试目标或把规划器抽成纯 Swift 可测试方法。
- 如果暂不新增测试 target，至少通过小范围函数 + 手动日志验证。

手动验证：

1. 恢复包含 BPS 与 CTL light 的旧数据。
2. 检查恢复日志中 BPS 虚拟组 `0xC00B` 或对应 link group 不再出现 CTL Temperature element 的 Generic Level Server 订阅 add。
3. 重置设备后重新恢复，操作 BPS level up/down：只改变亮度，色温不变。
4. 操作 BPS on/off、scene recall、auto：既有功能保持正常。
5. 构建验证：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 实施结果

已按用户确认后的目标完成实现：

- `MeshNetwork+SunSmart.swift` 中 BPS target subscription 从静态能力列表改为按 `batteryPowerSwitchKeyConfigurations` 的 action type 生成 desired models。
- `levelDelta` / `levelMove` 只订阅亮度 element 上的 Generic Level Server，不再泛化订阅其它 Generic Level Server。
- `ctlSet` / `ctlTemperatureSet` 只有在真实 action 出现时才订阅 CTL / CTL Temperature Server。
- 删除历史错误订阅 cleanup 不纳入本次修复；现场通过重置设备清除旧订阅状态。
- `SyncDevicesViewController` 中 BPS target group 同步任务统一走 `getBatteryPowerSwitchTargetSubscriptionMessageHandles`，避免和 restore / sync 判断路径不一致。

验证结果：

- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。
- 针对本次改动文件执行 `git diff --check` 通过。
- 全仓库 `git diff --check` 仍会被既有无关 Network 文件空白问题影响，本次未处理。

## 风险点

- 不能简单不订阅 Generic Level Server，否则 BPS level up/down 会失效。
- 不能简单删除所有 CTL 订阅，因为未来如果支持 BPS CCT action，需要按 action 明确订阅。
- 不能只修 restore；普通 Sync Devices 和新添加 BPS/light 的路径也会生成同类订阅。
- 本次不做历史 cleanup，因此未重置过的旧设备仍可能保留设备端旧订阅；现场需要按约定重置设备后验证。
