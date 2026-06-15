# Emergency Fire SDK v2 协议层设计

## 背景

- 设备：Emergency Fire / Emergency Controller
- Company ID：`0x0A78`
- Product ID：`0x2131`
- 最新协议：`Emergency fire protocol.md` v2.0.0，固件 v1.5.0 未改 `0x4D` 协议
- 现有分析文档：`docs/260615_1633_emergency_fire_protocol_conflict_analysis.md`
- 本设计范围：只规划 SDK v2 协议层，不实现 App UI、App 同步模型、数据库迁移或设备配置页面

## 决策结论

直接废弃旧 v1.3.6 Emergency Controller SDK API，只保留 v2 协议语义。

原因：

- 设备仍处于研发阶段，旧固件未正式发布，不需要兼容旧 wire format。
- 最新协议对同一个 `0x4D` 的 `0x03/0x04/0x05` 做了 breaking 变更，保留旧 API 容易让调用方误用。
- 让旧 App 调用点编译失败是有价值的，可以暴露所有需要迁移到 v2 的地方。

推荐路线：原地迁移现有 `SunricherVendorGet` / `SunricherVendorSet` / `SunricherVendorStatus` 的 Emergency Fire 分支，但替换为 v2 类型和命名。

## 目标

1. SDK 只暴露最新 Emergency Fire v2 协议语义。
2. 完整覆盖 `0x4D/0x01..0x07`。
3. 用强类型表达三状态、enable、综合状态、per-state resend 和 action config。
4. 单元测试锁定 GET、SET、STATUS 和异常 payload 的 wire format。
5. 保持现有 vendor message 入口结构，不新增另一套 message 类型。

## 非目标

- 不做 App UI 展示。
- 不做 App EFC 配置模型。
- 不做 App 同步任务规划。
- 不做旧固件兼容。
- 不做数据库迁移。
- 不做设备端行为推断，只按协议文档实现 payload 编解码。

## API 命名原则

旧名字中带有旧语义的类型和 case 不继续沿用：

| 旧概念 | 处理 |
|---|---|
| `EmergencyControllerMode` | 删除或替换，不再表达 disabled/emergency/fire |
| `EmergencyControllerSceneIndex` | 替换为 v2 三状态 index |
| `EmergencyControllerResendParameters` | 替换为 per-state N/M |
| `EmergencyControllerCurrentModeStatus` | 替换为 comprehensive status |
| `emergencyMode` | 改为 enabled 语义 |
| `emergencyCurrentModeStatus` | 改为 comprehensive status 语义 |

新的 public 类型建议统一使用 `EmergencyFire` 前缀，避免继续混淆旧 `EmergencyController` 概念。

## 数据模型设计

### EmergencyFireStateIndex

表示最新协议的三种状态：

| raw value | case | 场景号 |
|---:|---|---:|
| `0` | `emergencyTrigger` | `0xFF20` |
| `1` | `fireTrigger` | `0xFF21` |
| `2` | `restore` | `0xFF22` |

`0x03` 及以上值为非法。

### EmergencyFireSceneConfig

用于 `0x4D/0x01` STATUS：

- `stateIndex`
- `stage2Target`
- `sceneNumber`

协议中 `stage2Target` 对应当前 `_action[idx].stage2_target`。

### EmergencyFireDetailStatus

用于 `0x4D/0x02` STATUS。字段沿用现有 detail status 能力：

- `fireMillivolts`
- `emergencyMillivolts`
- `fireActive`
- `emergencyActive`
- `powerLossLevel`
- `powerLossInputActive`
- `emergencyAdcActive`

该结构可复用旧字段名，但类型名前缀改为 v2 命名。

### EmergencyFireResendParameters

用于 `0x4D/0x03` SET/GET STATUS：

- `stateIndex`
- `intervalSeconds`
- `count`

其中 `count == 0xFFFF` 表示无限重发。

### EmergencyFireComprehensiveStatus

用于 `0x4D/0x04` STATUS：

- `enabled`
- `fireActive`
- `emergencyActive`
- `everTriggered`

不再解析旧 `mode + active`。

### EmergencyFireRestoreDelay

`0x4D/0x06` 仍为单字节秒数。

SDK 可以用 `UInt8` 表达，调用方需要遵守协议范围 `0...120`。如果后续实现时决定在初始化器中校验，超出范围应返回 nil 或 clamp 策略需要明确，默认建议不自动 clamp。

### EmergencyFireAction

用于 `0x4D/0x07` 的 action_type 和 params：

| action_type | case | 参数 | 字节数 |
|---:|---|---|---:|
| `0x01` | `onOff` | `onoff: UInt8` | 1 |
| `0x02` | `levelDelta` | `delta: Int32` | 4 |
| `0x03` | `levelMove` | `delta: Int16` | 2 |
| `0x04` | `sceneRecall` | `sceneNumber: SceneNumber` | 2 |
| `0x05` | `lightControlOnOff` | `onoff: UInt8` | 1 |
| `0x06` | `lightness` | `lightness: UInt16` | 2 |
| `0x07` | `ctl` | `lightness: UInt16, temperature: UInt16, deltaUV: Int16` | 6 |
| `0x08` | `ctlTemperature` | `temperature: UInt16, deltaUV: Int16` | 4 |
| `0x09` | `hsl` | `lightness: UInt16, hue: UInt16, saturation: UInt16` | 6 |
| `0x0A` | `hslHue` | `hue: UInt16` | 2 |
| `0x0B` | `hslSaturation` | `saturation: UInt16` | 2 |
| `0x0C` | `powerLevel` | `power: UInt16` | 2 |
| `0xFF` | `invalid` | 无 | 0 |

整数按小端编码。`Int16` / `Int32` 需要按二进制补码写入 payload。

### EmergencyFireActionConfig

用于 `0x4D/0x07` SET/GET STATUS：

- `stateIndex`
- `action`
- `stage1Target`
- `stage2Target`
- `appKeyIndex`
- `ttl`
- `transitionTime`
- `delay`

编码规则：

- SET payload = `state_idx + action_type + stage1_target + stage2_target + app_idx + ttl + transition_time + delay + params`
- `appKeyIndex` 低 12 bit 有效，SDK 保留 `UInt16` 类型，不主动丢失原值；编码时按协议小端写入。
- `ttl` 支持 `0...127` 和 `0xFF`。
- `action == .invalid` 时 params 为空。

### EmergencyFireActionConfigAck

用于 `0x4D/0x07` SET STATUS：

- `stateIndex`
- `actionType`

SET STATUS 只回显 state 和 action type，不返回完整 action config。

## Vendor Function 调整

继续使用现有 message 类型：

- `SunricherVendorGet`
- `SunricherVendorSet`
- `SunricherVendorStatus`

调整 `VendorFireEmergencySceneCode`：

| subcode | case | v2 语义 |
|---:|---|---|
| `0x01` | `sceneConfig` | 场景查看 |
| `0x02` | `detailStatus` | 详细状态 |
| `0x03` | `resendParameters` | per-state 重发参数 |
| `0x04` | `comprehensiveStatus` | 综合状态 |
| `0x05` | `enabled` | enable SET/GET |
| `0x06` | `restoreDelay` | RESTORE 首次延迟 |
| `0x07` | `actionConfig` | 动作配置 |

### VendorFunctionGet

建议 case：

- `emergencySceneConfig(stateIndex: EmergencyFireStateIndex)`
- `emergencyDetailStatus`
- `emergencyResendParameters(stateIndex: EmergencyFireStateIndex)`
- `emergencyComprehensiveStatus`
- `emergencyEnabled`
- `emergencyRestoreDelay`
- `emergencyActionConfig(stateIndex: EmergencyFireStateIndex)`

GET 编码：

| case | payload |
|---|---|
| scene config | `[0x4D, 0x01, state_idx]` |
| detail status | `[0x4D, 0x02]` |
| resend parameters | `[0x4D, 0x03, state_idx]` |
| comprehensive status | `[0x4D, 0x04]` |
| enabled | `[0x4D, 0x05]` |
| restore delay | `[0x4D, 0x06]` |
| action config | `[0x4D, 0x07, state_idx]` |

### VendorFunctionSet

建议 case：

- `emergencyResendParameters(EmergencyFireResendParameters)`
- `emergencyEnabled(Bool)`
- `emergencyRestoreDelay(seconds: UInt8)`
- `emergencyActionConfig(EmergencyFireActionConfig)`

SET 编码：

| case | payload |
|---|---|
| resend parameters | `[0x4D, 0x03, state_idx, N le16, M le16]` |
| enabled true | `[0x4D, 0x05, 0x01]` |
| enabled false | `[0x4D, 0x05, 0x00]` |
| restore delay | `[0x4D, 0x06, seconds]` |
| action config | `[0x4D, 0x07, fixed header, params]` |

## Status 解码设计

### 通用规则

- `ret != 0`：`isSuccessful = false`，`errorCode = ret`，`parameters = nil`。
- `ret == 0` 但长度不足：`isSuccessful = false`，`parameters = nil`。
- `ret == 0` 但 enum 值非法：`isSuccessful = false`，`parameters = nil`。
- 不抛异常，沿用现有 `SunricherVendorStatus` 风格。

### `0x01` scene config

解码：

- `ret`
- `state_idx`
- `stage2_target`
- `scene_number`

最小长度：8 字节，包括 `0x4D, 0x01, ret`。

### `0x02` detail status

解码：

- `ret`
- `fire_mv`
- `em_mv`
- `fire_active`
- `em_active`
- `power_loss_level`
- `power_loss_input_active`
- `em_adc_active`

字段与当前旧实现基本一致。

### `0x03` resend parameters

解码：

- `ret`
- `state_idx`
- `N`
- `M`

不再解析旧的 trigger/stop 四字段格式。

### `0x04` comprehensive status

解码：

- `ret`
- `enable`
- `fire_active`
- `em_active`
- `ever_triggered`

不再解析旧 `mode + active`。

### `0x05` enabled

解码：

- `ret`
- `enable`

`enable > 1` 视为非法 payload。

### `0x06` restore delay

解码：

- `ret`
- `restore_delay_s`

如果设备返回 `restore_delay_s > 120`，建议视为非法 payload，避免把设备异常值当作正常配置。

### `0x07` action config

SET STATUS 解码：

- `ret`
- `state_idx`
- `action_type`

GET STATUS 解码：

- `ret`
- `state_idx`
- `action_type`
- 如果 `action_type == 0xFF`，允许短返回，不要求后续固定头字段。
- 如果 `action_type != 0xFF`，必须解析固定字段和对应长度 params。

action params 长度必须按 action type 精确匹配。

## 测试设计

重写 `EmergencyControllerVendorMessageTests` 为 v2 语义测试，不保留旧断言。

### GET 编码测试

- scene config `.emergencyTrigger` -> `[0x4D, 0x01, 0x00]`
- detail status -> `[0x4D, 0x02]`
- resend parameters `.restore` -> `[0x4D, 0x03, 0x02]`
- comprehensive status -> `[0x4D, 0x04]`
- enabled -> `[0x4D, 0x05]`
- restore delay -> `[0x4D, 0x06]`
- action config `.fireTrigger` -> `[0x4D, 0x07, 0x01]`

### SET 编码测试

- resend `.restore, N=5, M=10` -> `[0x4D, 0x03, 0x02, 0x05, 0x00, 0x0A, 0x00]`
- enabled true -> `[0x4D, 0x05, 0x01]`
- enabled false -> `[0x4D, 0x05, 0x00]`
- restore delay 2 -> `[0x4D, 0x06, 0x02]`
- action config 至少覆盖：
  - invalid
  - lightness
  - ctl
  - hsl
  - levelDelta
  - powerLevel

### STATUS 解码测试

- `0x01` scene config 返回 state/stage2Target/sceneNumber。
- `0x02` detail status 返回所有 detail 字段。
- `0x03` resend 返回 state/N/M。
- `0x04` comprehensive 返回 enabled/fire/em/ever。
- `0x05` enabled 返回 Bool。
- `0x06` restore delay 返回 seconds。
- `0x07` SET ack 返回 state/action summary。
- `0x07` GET full 返回完整 action config。
- `0x07` GET invalid 短返回解析为 invalid。

### 异常测试

- `ret != 0` 时 `isSuccessful = false`。
- `state_idx = 3` 解析失败。
- `action_type = 0x0D` 解析失败。
- action params 长度不足解析失败。
- 旧 `0x04` mode+active 格式不再按旧逻辑解析。

## 验证命令

SDK 仓库验证：

`swift test --filter EmergencyControllerVendorMessageTests`

App 仓库后续验证：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

预期：SDK v2 实现完成后，App 旧调用点会出现编译错误。这些错误是后续 App 层迁移的入口，不应在 SDK 层用旧 API 兼容掩盖。

## 影响面

### SDK 文件

主要涉及：

- `SunricherVendorStatus.swift`
- `SunricherVendorGet.swift`
- `SunricherVendorSet.swift`
- `EmergencyControllerVendorMessageTests.swift`

可能涉及：

- `Node+SupportModels.swift`：后续检查 Element 3 的 8 个 Client model 绑定能力时需要扩展，但这属于 App/设备配置后续阶段，不纳入本轮 v2 wire format 的最小范围。

### App 后续影响

SDK v2 改完后，App 中这些旧调用会失效，需要后续单独规划：

- `emergencyMode`
- `emergencyCurrentModeStatus`
- `emergencyResendParameters` 旧结构
- `EmergencyControllerMode`
- `EmergencyControllerSceneIndex`
- `EmergencyControllerCurrentModeStatus`
- 旧四场景常量 `0xFF20...0xFF23`

## 分阶段建议

本轮只做 SDK v2 协议层：

1. 先重写 SDK 类型和测试。
2. 再实现 v2 编码。
3. 再实现 v2 解码。
4. 最后跑 SDK 单元测试。

App UI、App 同步、数据库和迁移另起计划处理。

## 开放问题

本设计已按“直接废弃旧 API，只保留 v2”收口，没有旧固件兼容分支。

后续 App 层规划时还需要决定：

- 是否第一版 UI 支持全部 12 种 action type。
- 是否继续创建内部 virtual group，还是完全改用 `0x07` 的 stage target。
- 旧本地配置如何迁移到三状态配置。
- OTA 后是否强制完整重配。
