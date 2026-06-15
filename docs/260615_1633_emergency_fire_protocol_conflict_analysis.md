# Emergency Fire 最新协议与当前 App/SDK 实现冲突分析

## 背景

- 设备：Emergency Fire / Emergency Controller
- Company ID：`0x0A78`
- Product ID：`0x2131`
- 最新协议来源：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/emergency-fire/Emergency fire protocol.md`
- 最新协议版本：v2.0.0；文档说明 v1.5.0 未改 0x4D 协议
- 当前分析范围：App 仓库 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire` 与本地 SDK `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`
- 本文只分析冲突和差异，不改代码，不给开发实施计划

## 结论摘要

当前 App/SDK 已经有一套 Emergency Fire Controller 实现，且已经使用相同的 vendor 协议入口 `0x4D`。但这套实现整体更接近协议文档所称的 v1.3.6 语义：应急/火警二选一工作模式、4 个保留场景、通过 Scene Client 和 Light LC Client publication 驱动受控灯具。

最新协议 v1.4.0/v2.0.0 对同一个 `0x4D` 命令族做了 breaking 变更：工作模式从 `mode=0/1/2` 改为 `enable=0/1`，状态从 4 个场景变为 3 个状态，`0x03/0x04/0x05` payload 语义改变，并新增 `0x07` 动作配置。也就是说冲突不是“新增一组命令”这么简单，而是同 opcode、同 subcode 的 wire format 和业务语义重叠冲突。

## 最新协议命令摘要

最新协议的 vendor 入口：

| 项 | 最新协议 |
|---|---|
| Vendor opcode | `0x4D`，FIRE_EM_SCENE |
| Element | Element 1 的 Sunricher Vendor Setup Server |
| 字节序 | 多字节字段小端 |
| 状态数 | 3 个：EM_TRIGGER / FIRE_TRIGGER / RESTORE |
| 触发模型 | fire/em 并发检测，火警优先，应急其次，恢复最低 |
| 目标地址 | 由 `0x4D/0x07` payload 携带，不再依赖模型 publication |
| AppKey | Element 3 上 8 个 Client 模型都要绑定 AppKey，不需要配 Publish Address |

最新协议 subcode：

| subcode | 最新用途 | 与旧语义关系 |
|---|---|---|
| `0x01` | 场景查看，idx 0..2 | idx 范围从 0..3 改为 0..2 |
| `0x02` | 详细状态 | 基本沿用 |
| `0x03` | per-state 重发参数，payload 为 `state_idx + N + M` | 格式从 8B 改为 5B |
| `0x04` | 综合状态：enable/fire/em/ever_triggered | 语义从 mode+active 改为 enable+两个输入状态+ever |
| `0x05` | enable SET/GET | 语义从 mode 0/1/2 改为 enable 0/1 |
| `0x06` | restore_delay SET/GET | 基本沿用，但只作用于 RESTORE |
| `0x07` | 动作配置 SET/GET | 新增 |

最新协议保留场景号：

| state_idx | 最新状态 | 最新场景号 |
|---|---|---|
| `0` | EM_TRIGGER | `0xFF20` |
| `1` | FIRE_TRIGGER | `0xFF21` |
| `2` | RESTORE | `0xFF22` |

最新协议明确废弃旧场景语义：

| 旧语义 | 最新协议状态 |
|---|---|
| `0xFF20 = EM_TRIG` | 保留为 EM_TRIGGER |
| `0xFF21 = EM_STOP` | 改为 FIRE_TRIGGER |
| `0xFF22 = FIRE_TRIG` | 改为 RESTORE |
| `0xFF23 = FIRE_STOP` | 废弃 |

## 当前 App 实现摘要

### 设备识别

当前 `SunSmart/devices_config.json` 已包含 `0x0A78/0x2131`：

| 字段 | 当前值 |
|---|---|
| `companyId` | `0A78` |
| `productId` | `2131` |
| `categoryName` | `Emergency Controller` |
| `elementCount` | `3` |
| `iconCategory` | `EmergencyController` |
| `deviceCategory` | `EmergencyController` |
| `modelName` | `SR-BL2421-DryCon924` |

`Node.DeviceType` 会把 `deviceCategory == "EmergencyController"` 映射成 `.emergencyController`。因此当前 App 对 `0x2131` 的基础分类是存在的。

需要注意：`Node.isEmergencySignController` 当前只特判 `0x0A78/0x24C1`，不包含 `0x2131`。`0x2131` 主要通过 `deviceType == .emergencyController` 走 Emergency Fire Controller 流程，不要把这两个判断混用。

### App 业务配置模型

当前 App 的 EFC 配置核心是：

| 当前模型 | 当前语义 |
|---|---|
| `EmergencyFireControllerWorkMode.powerLossEmergency` | 应急/掉电模式 |
| `EmergencyFireControllerWorkMode.fireAlarmEmergency` | 火警模式 |
| `EmergencyFireControllerWorkMode.allDisabled` | 禁用 |
| `EmergencyFireControllerModeSettings` | 单个模式下的关联组、触发亮度、trigger/stop 重发、restore delay |

当前模型是“当前只激活一个 workMode”的结构。最新协议改为 fire 与 em 并发检测，App 应能同时配置 EM_TRIGGER、FIRE_TRIGGER、RESTORE 三个状态动作；这与当前 workMode 二选一结构冲突。

### App 同步链路

当前同步任务在 `DeviceEmerFireData+Sync.swift` 和 `EmergencyFireControllerSyncPlanner.swift` 中生成，主要行为是：

| 当前同步动作 | 当前实现 |
|---|---|
| 控制器侧 publication | 给 Scene Client 和 Light LC Client 设置同一个内部 virtual group publication |
| 工作模式 | 下发 `SunricherVendorSet(function: .emergencyMode(...))` |
| 重发参数 | 下发 `SunricherVendorSet(function: .emergencyResendParameters(...))` |
| 恢复延迟 | 下发 `SunricherVendorSet(function: .emergencyRestoreDelay(...))` |
| 灯组侧订阅 | 让受控灯订阅内部 publish group |
| 场景预置 | 用 `LightLightnessSet` 调亮度后 `SceneStore` 保留场景 |
| 自动恢复 | 给组发 `LightLCLightOnOffSetUnacknowledged(true)` |

这条链路依赖“控制器模型 publication + 受控灯订阅 publish group”。最新协议要求目标地址、AppKey、TTL、transition、delay、动作参数由 `0x4D/0x07` payload 提供，明确不需要给 Element 3 的 Client 模型配 Publish Address。当前同步方式与最新协议的目标地址机制冲突。

### 当前 App 保留场景号

当前 App 定义：

| 当前常量 | 当前值 | 当前语义 |
|---|---:|---|
| `powerLossTriggerSceneNumber` | `0xFF20` | 应急触发 |
| `powerLossStopSceneNumber` | `0xFF21` | 应急停止 |
| `fireAlarmTriggerSceneNumber` | `0xFF22` | 火警触发 |
| `fireAlarmStopSceneNumber` | `0xFF23` | 火警停止 |

这与最新协议只有 `0xFF20/0xFF21/0xFF22` 三个场景、且 `0xFF21/0xFF22` 语义重排直接冲突。

### 当前监控状态

当前监控页读取 `0x4D/0x04`：

| 当前读取 | 当前解析 |
|---|---|
| `SunricherVendorGet(function: .emergencyCurrentModeStatus)` | 期望 SDK 返回 `EmergencyControllerCurrentModeStatus(mode, active)` |
| UI 映射 | `mode=.emergency` + `active` 显示应急状态；`mode=.fire` + `active` 显示火警状态 |

最新协议 `0x4D/0x04` 返回的是 `enable + fire_active + em_active + ever_triggered`。当前解析会把 `enable` 当作旧 `mode`，把 `fire_active` 当作旧 `active`，并忽略后面的 em/ever 字段，状态展示会错误。

## 当前 SDK 实现摘要

SDK 已有 `fireEmergencyScene = 0x4D`，并支持 `0x01..0x06`：

| SDK 枚举/结构 | 当前语义 |
|---|---|
| `VendorFireEmergencySceneCode.sceneConfig = 0x01` | 场景配置查看 |
| `detailStatus = 0x02` | 详细状态 |
| `resendParameters = 0x03` | 旧版场景重发参数 |
| `currentModeStatus = 0x04` | 旧版当前模式状态 |
| `mode = 0x05` | 旧版工作模式 |
| `restoreDelay = 0x06` | STOP 场景恢复延迟 |
| `EmergencyControllerMode` | disabled/emergency/fire |
| `EmergencyControllerSceneIndex` | emergencyTrigger/emergencyStop/fireTrigger/fireStop |
| `EmergencyControllerResendParameters` | trigger N/M + stop N/M，共 8B |

SDK 当前没有 `0x07` 动作配置的数据结构、编码、解码和测试。

SDK 测试 `EmergencyControllerVendorMessageTests` 也固定了旧协议期望：

| 测试项 | 当前期望 |
|---|---|
| `0x01 GET` | 可请求 `.fireStop`，即 idx `0x03` |
| `0x03 SET` | `0x4D 0x03 + triggerInterval + triggerCount + stopInterval + stopCount` |
| `0x04 STATUS` | 解析为 `mode + active` |
| `0x05 SET` | `mode=0/1/2` |

这些测试与最新协议的 breaking change 一致冲突。

## 相同点

| 项 | 相同情况 |
|---|---|
| 设备 PID | App 配置已包含 `0x0A78/0x2131` |
| Element 数 | App 配置为 3，最新协议也是 3 |
| Vendor opcode | SDK/App 已使用 `0x4D` 作为 Fire/Emergency vendor 入口 |
| `0x02` 详细状态 | 当前 SDK 解析字段与最新协议基本一致：fire/em ADC、active、power loss、em adc active |
| `0x06` restore delay | 当前 SDK/App 已有 restore delay SET/GET 能力，字段长度与范围方向基本可复用 |
| 基础 UI 模块 | App 已有 EFC 设备列表、编辑页、监控页、同步页、删除清理流程 |
| 受控灯场景预置能力 | App 已有对受控灯写场景、订阅组、清理订阅的同步框架 |

## 不同点与冲突

### 1. `0x4D/0x01` 场景查看 index 和场景语义冲突

| 维度 | 当前实现 | 最新协议 |
|---|---|---|
| index 范围 | 0..3 |
| index 含义 | 0 EM trigger / 1 EM stop / 2 Fire trigger / 3 Fire stop |
| 最新范围 | 0..2 |
| 最新含义 | 0 EM_TRIGGER / 1 FIRE_TRIGGER / 2 RESTORE |

影响：

- 当前 SDK 的 `EmergencyControllerSceneIndex.fireStop = 3` 对新固件非法。
- 当前 App 仍保留 `0xFF23`，新协议已废弃。
- 当前 `0xFF21`、`0xFF22` 的 UI/业务语义会与新固件实际语义错位。

### 2. `0x4D/0x03` 重发参数 payload 冲突

| 维度 | 当前实现 | 最新协议 |
|---|---|---|
| SET payload | `triggerInterval + triggerCount + stopInterval + stopCount`，8B |
| GET payload | 无参 |
| STATUS payload | 同 8B |
| 最新 SET payload | `state_idx + N + M`，5B |
| 最新 GET payload | `state_idx` |
| 最新 STATUS payload | `ret + state_idx + N + M` |

影响：

- 当前 App 下发的 resend 命令长度和字段语义对新固件不匹配。
- 当前 SDK 解析新固件返回会把 `state_idx/N/M` 错读成旧的 trigger/stop 参数，或因长度检查失败。
- 最新协议要求三状态各自配置，当前 App 只有当前激活 mode 的 trigger/stop 两组参数。

### 3. `0x4D/0x04` 综合状态语义冲突

| 维度 | 当前实现 | 最新协议 |
|---|---|---|
| 当前解析 | `ret + mode + active` |
| 最新返回 | `ret + enable + fire_active + em_active + ever_triggered` |

影响：

- 新固件返回 `enable=1, fire=0, em=1, ever=1` 时，当前 SDK 会解析成 `mode=.emergency, active=false`，UI 可能显示应急正常而不是应急触发。
- 当前 UI 模型无法表达 fire/em 同时存在或 fire 抢占 em 的状态。
- `ever_triggered` 完全没有当前 App 表达入口。

### 4. `0x4D/0x05` 工作模式变 enable，写命令冲突

| 维度 | 当前实现 | 最新协议 |
|---|---|---|
| 当前 SET | `mode=0/1/2`，disabled/emergency/fire |
| 最新 SET | `enable=0/1` |
| 当前业务 | Power Loss 和 Fire Alarm 二选一 |
| 最新业务 | Fire 与 EM 并发检测，仅 enable 控制是否发 mesh |

影响：

- 当前 App 切到 fire mode 会下发 `0x02`，新固件会按非法 enable 返回错误。
- 当前 App 切到 emergency mode 会下发 `0x01`，新固件只会理解为 enable=1，不会表示“只启用应急”。
- 最新协议不再支持 App 通过 mode 让应急/火警互斥。

### 5. `0x4D/0x07` 动作配置缺失

最新协议新增 `0x07`，用于配置每个 state 的 stage1 action、stage1 target、stage2 target、app_idx、ttl、transition、delay 和 action params。

当前 SDK/App 没有：

- `0x07` subcode 枚举；
- action type 0x01..0x0C / 0xFF 的数据模型；
- SET/GET 编码；
- STATUS 解码；
- App 侧 UI/配置模型；
- 同步任务；
- 对 INVALID 默认静默的处理；
- 对三状态 EM/FIRE/RESTORE 的独立动作配置。

这是最新协议落地的最大缺口。

### 6. 目标地址机制冲突

| 维度 | 当前实现 | 最新协议 |
|---|---|---|
| 当前目标地址来源 | Scene Client / Light LC Client publication 指向内部 virtual group；受控灯订阅这个 group |
| 最新目标地址来源 | `0x07` payload 内的 `stage1_target` / `stage2_target` |
| 当前是否配 Publish Address | 会配置 Scene Client 和 Light LC Client publication |
| 最新是否配 Publish Address | 明确不需要配 Publish Address |

影响：

- 当前同步建立的内部 publish group 对新协议阶段发送不是必需机制。
- 当前 App 不会把目标地址下发到 `0x07`，新固件默认 action_type=INVALID 时将完全静默。
- 删除/清理逻辑现在主要围绕内部 publish group 订阅，最新协议下是否仍需要保留这套清理策略要重新评估。

### 7. Client Model 覆盖不完整

最新协议要求 Element 3 绑定 8 个 Client 模型：

- Scene Client
- Generic OnOff Client
- Generic Level Client
- Generic Power Level Client
- Light Lightness Client
- Light CTL Client
- Light HSL Client
- Light LC Client

SDK 当前 `Node+SupportModels` 能看到 OnOff Client、Level Client、Light LC Client、Light CTL Client、Scene Client 等 accessor，并且 `supportModels` 会追加部分 client model。但没有看到 HSL Client 和 Generic Power Level Client 被纳入 EFC 所需模型检查；Power Switch profile 也只列了 5 个 client model。

影响：

- 新固件 Element 3 的 8 个 Client 模型可能无法全部绑定 AppKey。
- 如果 `0x07` 配置 HSL 或 Power Level action，即使 payload 正确，也可能因为对应 Client 模型未绑定 AppKey 而设备端发送失败。

### 8. App UI 和数据模型与最新协议不匹配

当前 UI 是：

- 选择一种 workMode；
- 针对该模式配置组、触发亮度、停止/恢复、重发次数；
- 监控页展示当前 mode 下 normal/triggered/resuming。

最新协议需要表达：

- 全局 enable；
- EM_TRIGGER、FIRE_TRIGGER、RESTORE 三个状态；
- 每个状态独立 action_type 和 action params；
- stage1 target 与 stage2 target；
- fire/em active 并发状态；
- ever_triggered；
- action_type=INVALID 的静默状态；
- RESTORE 是统一恢复，不再有 EM_STOP/FIRE_STOP 两套。

因此只改 SDK wire format 不能完整适配最新协议，App 层业务模型也需要重做设计。

### 9. Motion sensitivity 黑名单已包含 `0x2131`

当前 `MeshNetwork+SunSmart.swift` 中 `unsupportedMotionSensitivityProductIdentifiers` 已包含 `0x2131`。这与本次协议本身不是冲突点，但说明 App 已经把 `0x2131` 视为不支持普通灯具类 motion sensitivity 的特殊 PID。后续规划时需要保留这一能力判断，不要因为重做 Emergency Controller 流程误删。

## 命令级对照表

| 命令 | 当前 App/SDK 是否有 | 最新协议是否可复用 | 主要问题 |
|---|---|---|---|
| `0x4D/0x01` scene config GET | 有 | 部分可复用 | idx 从 0..3 改为 0..2，`0xFF21/0xFF22` 语义变，`0xFF23` 废弃 |
| `0x4D/0x02` detail status GET | 有 | 基本可复用 | 字段基本一致，需确认 ret/长度处理 |
| `0x4D/0x03` resend SET/GET | 有 | 不能直接复用 | payload 从旧 8B 改为 per-state 5B，GET 也需要 state_idx |
| `0x4D/0x04` current status GET | 有 | 不能直接复用 | 返回语义从 mode+active 改为 enable/fire/em/ever |
| `0x4D/0x05` mode/enable SET/GET | 有 | 不能直接复用 | mode 0/1/2 改为 enable 0/1 |
| `0x4D/0x06` restore delay SET/GET | 有 | 大体可复用 | 作用范围从 stop/restore 语义转为统一 RESTORE |
| `0x4D/0x07` action config SET/GET | 无 | 必须新增 | 最新协议核心能力；当前缺失 SDK 和 App 配置链路 |

## 影响面

### SDK

- `VendorFireEmergencySceneCode` 需要支持 `0x07`。
- `EmergencyControllerMode` 旧模型不能表达最新 enable/status。
- `EmergencyControllerSceneIndex` 旧 4 值模型与新 3 状态冲突。
- `EmergencyControllerResendParameters` 旧结构与新 per-state N/M 冲突。
- `SunricherVendorGet` / `SunricherVendorSet` / `SunricherVendorStatus` 需要区分新旧协议或迁移模型。
- SDK 测试目前锁定旧协议，后续必须补最新协议测试，同时决定旧协议兼容策略。
- Client model accessor / support model 列表需要核实 Generic Power Level Client 和 Light HSL Client。

### App

- `LinkedEmerFireConfig` / `EmergencyFireControllerConfiguration` 当前 workMode 二选一模型不适配新协议。
- `DeviceEmerFireData+Sync` 当前 controller sync tasks 下发旧 mode/resend/restoreDelay，不会下发 `0x07`。
- `EmergencyFireControllerSyncPlanner` 当前基于内部 publish group 和受控灯订阅，不符合新协议目标地址随 `0x07` 下发的模型。
- 监控页当前读取 `0x04` 并映射 mode+active，新协议会显示错误。
- 保留场景号常量与导入/导出过滤会受 `0xFF21/0xFF22/0xFF23` 变化影响。
- 删除/清理流程是否仍需要清受控灯订阅，需要基于最终兼容策略重新判断。
- 添加设备基础识别目前是通的，但首次配置流程需要补齐 Element 3 的 8 个 Client AppKey 绑定要求。

## 需要后续规划明确的问题

1. 是否需要兼容旧固件 v1.3.6 和新固件 v1.4.0/v1.5.0。
2. 如果需要兼容，App/SDK 如何根据 composition hash、固件版本或能力探测选择旧/新协议。
3. 现有数据库里的 EFC 配置如何迁移到三状态模型。
4. 旧的四场景配置如何转换成 EM_TRIGGER / FIRE_TRIGGER / RESTORE。
5. 是否保留内部 virtual publish group 作为旧协议兼容路径，还是对新协议完全改为 `0x07` payload target。
6. 新 UI 是否支持 12 种 action_type，还是先落地一个受限动作集合。
7. Element 3 的 8 个 Client 模型绑定由 SDK 自动 keybind 完成，还是 App 在 EFC 添加/修复流程中显式补齐。
8. OTA v1.3.6 → v1.4.0 后 composition hash 变化 + NVS 全擦，App 是否需要强制完整重配流程。

## 当前最关键风险

如果直接拿当前 App/SDK 去配置最新协议固件：

- `0x4D/0x05` 可能写入非法 enable 值；
- `0x4D/0x03` payload 长度和字段错误；
- `0x4D/0x04` 状态会被错误解析；
- `0x4D/0x07` 没有下发，设备默认 action_type=INVALID，实际 mesh 发送可能完全静默；
- 场景号 `0xFF21/0xFF22` 会按旧语义预置，和新固件触发语义错位；
- `0xFF23` 仍被 App 当作保留 fire stop，但新协议已废弃；
- HSL / Power Level 等新 action 对应 Client 模型可能未绑定 AppKey。

因此最新协议适配应按 breaking change 处理，而不是在旧 EFC 流程上局部补一两个字段。
