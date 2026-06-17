# EFC Event Ends Set Brightness 分析与修复计划

## 背景

- 场景：EFC 设备 `Associate with group(s)` 添加 Group 后点击 SAVE。
- 现象：`Fire alarm emergency` 和 `Power loss emergency` 都能在 Group 中生效，但 `Event Ends` 的 `Set brightness to 1%` 没有生效。
- 本次只做事实分析与修复计划，不修改业务代码。

## SAVE 下发命令顺序

日志中的 EFC 是 `EFC2`，绑定节点地址 `0x1D70`，内部 publish group 是 `0xCD24`。被关联灯节点是 `0x005A`，用户可见 Group 地址是 `0xC009`。

### 1. 读取 EFC 综合状态

1. App 发 `SunricherVendorGet(.emergencyComprehensiveStatus)` 到 `0x1D70`。
2. Access PDU：opcode `0xF1780A`，parameters `0x4D04`。
3. EFC 返回 opcode `0xF3780A`，parameters `0x4D040001000001`。
4. SDK 解析为 `enabled=true, fireActive=false, emergencyActive=false, everTriggered=true`。

这一步只是进入同步前读状态，不直接配置 Event Ends。

### 2. 确认或复用 EFC 内部 publish group

日志多次出现：

- `reuse publish group device=EFC2, address=0xCD24`
- `publication already set device=EFC2, node=7536, address=0xCD24`

说明当前 SAVE 没有重新下发 Scene Client / Light LC Client publication；App 认为 EFC 控制器侧已经发布到内部 group `0xCD24`。

### 3. 下发 Power Loss action config

1. App 发 `SunricherVendorSet(.emergencyActionConfig(... stateIndex=.emergencyTrigger ... action=.lightness(33422) ... target=0xCD24 ...))` 到 `0x1D70`。
2. Access PDU：opcode `0xF0780A`，parameters `0x4D07000624CD24CD01000500008E82`。
3. 字段含义：
   - `0x4D07`：Emergency action config。
   - `00`：state index = Emergency Trigger / Power Loss。
   - `06`：action type = Lightness。
   - `24CD24CD`：stage1/stage2 target 都是 `0xCD24`。
   - `0100`：AppKey index = 1。
   - `05`：TTL = 5。
   - `0000`：transition / delay = 0。
   - `8E82`：lightness = `0x828E` = 33422，约 51%。
4. EFC ACK：parameters `0x4D07000006`，成功。

### 4. 下发 Fire Alarm action config

1. App 发 `SunricherVendorSet(.emergencyActionConfig(... stateIndex=.fireTrigger ... action=.lightness(65535) ... target=0xCD24 ...))` 到 `0x1D70`。
2. Access PDU：opcode `0xF0780A`，parameters `0x4D07010624CD24CD0100050000FFFF`。
3. 字段含义：
   - state index = Fire Trigger。
   - action type = Lightness。
   - target = `0xCD24`。
   - lightness = `0xFFFF` = 100%。
4. EFC ACK：parameters `0x4D07000106`，成功。

### 5. 下发 Restore / Event Ends action config

1. App 发 `SunricherVendorSet(.emergencyActionConfig(... stateIndex=.restore ... action=.lightness(655) ... target=0xCD24 ...))` 到 `0x1D70`。
2. Access PDU：opcode `0xF0780A`，parameters `0x4D07020624CD24CD01000500008F02`。
3. 字段含义：
   - state index = Restore / Event Ends。
   - action type = Lightness。
   - target = `0xCD24`。
   - lightness = `0x028F` = 655，约 1%。
4. EFC ACK：parameters `0x4D07000206`，成功。

结论：从 App 到 EFC 的 `Event Ends -> Set brightness to 1%` vendor action config 已经发出，并且 EFC 返回成功 ACK。

### 6. 给灯节点添加 Scene Server 订阅

1. App 发 `ConfigModelSubscriptionAdd` 到灯节点 `0x005A`。
2. 参数：`0x5A0024CD0312`。
3. 含义：灯节点 element `0x005A` 的 Scene Server model `0x1203` 订阅内部 publish group `0xCD24`。
4. 灯节点返回 `ConfigModelSubscriptionStatus Success`。

这一步让灯可以接收 EFC 发到 `0xCD24` 的 Scene Recall。

### 7. 写 Power Loss 触发场景到灯节点

1. App 发 `LightLightnessSet(33422)` 到灯节点 `0x005A`。
2. 灯返回 `LightLightnessStatus(lightness: 33422)`。
3. App 发 `SceneStore(scene: 0xFF20)` 到灯节点 `0x005A`。
4. 灯返回 `SceneRegisterStatus Success, currentScene=0xFF20, scenes=[0xFF20, 0xFF21]`。

这一步把 Power Loss 对应亮度写入保留场景 `0xFF20`。

### 8. 同步过程中收到 EFC 发出的 Restore 场景回放

在写 `SceneStore(0xFF20)` 期间，日志插入收到：

- source `0x1D72`
- destination `0xCD24`
- message `SceneRecallUnacknowledged(scene: 0xFF22)`

这说明 EFC 在某个时刻仍向内部 publish group `0xCD24` 发出了 Restore 场景 `0xFF22`。这条消息不是 App 主动发的，是 EFC 广播出来的。

### 9. 写 Fire Alarm 触发场景到灯节点

1. App 发 `LightLightnessSet(65535)` 到灯节点 `0x005A`。
2. 灯返回 `LightLightnessStatus(lightness: 65535)`。
3. App 发 `SceneStore(scene: 0xFF21)` 到灯节点 `0x005A`。
4. 灯返回 `SceneRegisterStatus Success, currentScene=0xFF21, scenes=[0xFF20, 0xFF21]`。

这一步把 Fire Alarm 对应亮度写入保留场景 `0xFF21`。

### 10. 给灯节点添加 Light LC Server 订阅

1. App 发 `ConfigModelSubscriptionAdd` 到灯节点 `0x005A`。
2. 参数：`0x5C0024CD0F13`。
3. 含义：灯节点 element `0x005C` 的 Light LC Server model `0x130F` 订阅内部 publish group `0xCD24`。
4. 灯节点返回 `ConfigModelSubscriptionStatus Success`。

这一步用于 `Restore AUTO` 类动作，不直接写 `Set brightness to 1%`。

## 代码事实

### 当前 App 会生成三条 EFC action config

`DeviceEmerFireData.makeControllerSyncTasks(...)` 会遍历 `.emergencyTrigger`、`.fireTrigger`、`.restore` 三个 state，并按 `configuration.actionConfig(...)` 生成 `SunricherVendorSet(.emergencyActionConfig(...))`。

当前 `restoreSettings.actionType == .setBrightness` 时，`LinkedEmerFireConfig.action(for: .restore)` 会生成 `.lightness(Node.getLightness(lightness100: restoreSettings.brightness))`。因此日志里的 restore `0x028F` 符合 App 当前配置。

### 当前 App 只给灯节点存触发场景，不存 Restore 场景

`EmergencyFireControllerSyncPlanner.makeAssociateTasks(...)` 的灯节点任务是：

1. Scene Server 订阅内部 publish group。
2. 对关联到该 Group 的 Power Loss / Fire Alarm，分别执行 `LightLightnessSet + SceneStore(0xFF20/0xFF21)`。
3. Light LC Server 订阅内部 publish group。

它不会为 `.setBrightness` 的 Event Ends 生成 `LightLightnessSet(1%) + SceneStore(0xFF22)`。

这和日志一致：灯节点最终的 `SceneRegisterStatus` 只有 `[0xFF20, 0xFF21]`，没有 `0xFF22`。

## 问题判断

### 已基本排除

1. 不是 EFC action config 没发：日志中 `0x4D070206...8F02` 已发送。
2. 不是 EFC action config ACK 解析失败：`0x4D07000206` 被 SDK 解析为 success。
3. 不是编辑页没有保存 1%：云同步 payload 已显示 `restoreSettings.actionType=setBrightness, brightness=1, sendCount=5`。
4. 不是灯节点完全没有订阅 EFC 内部 group：Scene Server 和 Light LC Server subscription 都返回 success。

### 最高优先级疑点

1. **Restore 实际执行路径仍是 Scene Recall `0xFF22`，但 App 没有给灯存 `0xFF22`。**
   - 日志中 EFC 发出了 `SceneRecallUnacknowledged(scene: 0xFF22)`。
   - App 只存了 `0xFF20` 和 `0xFF21`。
   - 如果固件对 Restore 仍走 scene recall，灯端没有 `0xFF22` 场景，`Set brightness to 1%` 自然不会生效。

2. **EFC ACK 了 `action_type=lightness`，但实际执行仍可能沿用 restore scene 机制。**
   - ACK 只能证明设备接受了配置，不等于实际事件一定按该 action type 执行。
   - 当前日志里的真实广播消息是 Scene Recall，不是 Light Lightness Set。

3. **同步过程中事件触发打断灯端场景写入。**
   - `SceneRecall(0xFF22)` 插入在 `SceneStore(0xFF20)` 期间。
   - 如果 EFC 在 SAVE 后立即处于 restore/event-ends 过程，可能改变灯当前状态，影响随后的 SceneStore 内容。
   - 不过这不是唯一根因，因为即使没有打断，当前 planner 也没有主动写 `0xFF22`。

4. **当前实现与早前 v2 设计计划不一致。**
   - 早前计划曾把 Restore 设计为独立保留状态 `0xFF22`。
   - 当前代码虽然定义了 `restoreSceneNumber = 0xFF22`，但 associate planner 没使用它。

5. **`SWIFT TASK CONTINUATION MISUSE` 是独立风险，但不是这次 1% 不生效的直接证据。**
   - 它发生在同步完成后的状态轮询阶段。
   - 需要另行修，但当前日志中核心配置与灯端订阅已经完成，且 restore 不生效的主要证据来自 EFC 实际广播 `0xFF22` 与灯端未存 `0xFF22`。

## 建议修复方案

### 方案 A：补齐 Restore Set Brightness 的灯端保留场景写入（推荐）

目标：当 `restoreSettings.actionType == .setBrightness` 时，关联 Group 内每个灯节点同步时额外写入 `0xFF22`：

1. `LightLightnessSet(restore brightness)`。
2. `SceneStore(DeviceEmerFireData.restoreSceneNumber)`。

这样即使 EFC 实际仍广播 `SceneRecall(0xFF22)`，灯端也有正确的 1% 场景可执行。

需要调整：

- `EmergencyFireControllerSyncTaskKind`：新增或复用一种清晰的 restore scene task kind，例如 `restoreScene`。
- `EmergencyFireControllerSyncPlanner.makeAssociateTasks(...)`：在 trigger scenes 后，根据 `restoreSettings.actionType == .setBrightness` 增加 restore scene store task。
- `SyncDevicesViewController.emergencyFireControllerTaskDisplayName(...)`：让同步页显示类似 `Event Ends 1%`，避免被误认成 trigger scene。
- 如果后续 `restoreBrightness` 改变但关联组不变，`changedFromConfiguration` 场景下也必须让关联灯重新写 `0xFF22`；否则只改 brightness 时 EFC action config 更新了，但灯端旧场景不更新。

优点：

- 与日志中的真实执行行为匹配。
- 改动集中在 planner 和同步展示，不碰 SDK wire format。
- 对现有 Fire / Power Loss 已生效路径影响最小。

风险：

- 写 restore scene 会临时把灯亮度调到 1%，同步体验上可能可见。
- 如果固件后续真正改为直接发 Lightness Set，这个场景仍是兼容兜底，不会破坏 direct action。

### 方案 B：把 Restore Set Brightness 的 EFC action 改为 Scene Recall `0xFF22`

目标：App 不再对 Restore 下发 `action_type=lightness`，而是下发 `action_type=sceneRecall(0xFF22)`；灯端同步同样写 `0xFF22`。

优点：

- 和当前观察到的 EFC 实际广播完全一致。
- 语义更接近“Event Ends 是一个保留场景”。

风险：

- UI 文案是 `Set brightness to 1%`，但 EFC action config 会变成 Scene Recall，需要代码注释和文档说明这是为了兼容当前固件执行路径。
- 如果协议确认 `0x4D/0x07 restore lightness` 应该直接生效，则这会绕开 direct action 能力。

### 方案 C：只保留 direct Lightness action，要求固件修复

目标：App 继续下发 `action_type=lightness(1%)`，不存 `0xFF22`，由固件保证 Restore 时发 Lightness Set 到 target group。

优点：

- 最符合 `0x4D/0x07 action_type=lightness` 的字面含义。

风险：

- 当前日志已经显示 EFC 发的是 `SceneRecall(0xFF22)`，短期内 App 侧无法让 1% 生效。
- 需要固件侧确认并修改，App 没有立即可验证的闭环。

## 推荐执行计划

我建议采用 **方案 A**，并把方案 B 作为协议/固件确认后的可选收敛。

### Task 1：补 planner 中的 Restore scene 写入

修改文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

实施点：

1. 为 Restore Set Brightness 增加独立 task kind，避免和 Power Loss / Fire Alarm trigger scene 混在一起。
2. 在每个关联灯节点的 sync task 中，当 restore action 是 set brightness 时追加 `restore brightness + SceneStore(0xFF22)`。
3. 同步页展示使用 `Event Ends 1%` 或现有 UI 英文风格可接受的短标题。
4. 只在 Group 内真实节点上生成任务；缺少 lightness model 或 scene setup model 时按现有 trigger scene 逻辑跳过或失败。

验收：

- SAVE 后日志中应出现 `LightLightnessSet(lightness: 655)` 到灯节点。
- 随后应出现 `SceneStore(scene: 65314)`，即 `0xFF22`。
- 灯节点 `SceneRegisterStatus.scenes` 应包含 `65314`。

### Task 2：保证只修改 Event Ends 亮度时也会重写灯端 Restore scene

修改文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- 如需要，调整 `DeviceEmerFireData+Sync.swift` 的 changed config 判定辅助。

实施点：

1. 当 `oldConfiguration.restoreSettings.brightness/actionType` 与新配置不同，即使关联组没变，也要为当前关联 Group 的灯生成 restore scene 写入任务。
2. 避免每次只改 `sendCount/resumingSeconds` 都重写灯端 scene；这些只需要 EFC vendor resend/delay。
3. 首次完整同步仍应写 restore scene。

验收：

- 只把 Event Ends 从 1% 改到 10% 后 SAVE，日志应重写 `0xFF22`，不需要重写 `0xFF20/0xFF21`。
- 只改 `Send Count` 时不应无意义重写灯端 `0xFF22`。

### Task 3：增加 planner 单元级保护或最小可验证断言

修改文件候选：

- 现有 FireAlarm planner 测试文件如果已有则复用。
- 如果当前 App target 没有可用单元测试，至少新增 planner debug/assert helper 或局部可运行验证入口。

断言内容：

- setBrightness restore 配置下，planner 为关联灯生成 `SceneStore(0xFF22)`。
- restoreAuto 配置下，不生成 restore scene store，仍保留 Auto Restore task。
- Power Loss / Fire Alarm 的 `0xFF20/0xFF21` 行为不变。

### Task 4：构建验证

按项目规则使用 iPhoneOS 构建：

- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如果改动触及 SDK，则额外构建本地 SDK demo target；方案 A 预计不需要改 SDK。

## 需要你确认的问题

1. 是否按 **方案 A** 实现：App 补写灯端 `0xFF22` restore scene，保持 EFC vendor action config 仍发 `action_type=lightness(1%)`。
2. 同步时短暂把灯切到 Event Ends 亮度是否可以接受。如果不能接受，需要讨论是否使用无感方式或先记录旧状态再恢复。
3. 是否需要同时把 EFC restore action config 改成 `sceneRecall(0xFF22)`。我建议先不改，除非固件/协议明确要求 Restore 必须走 Scene Recall。
