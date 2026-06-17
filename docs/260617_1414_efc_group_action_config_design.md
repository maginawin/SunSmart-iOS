# EFC Group 与动作配置重构设计

## 目标

将 Emergency Fire Controller 的编辑页同步逻辑调整为新的协议模型：

- 每个 EFC 添加到 Space 后立即拥有独立虚拟组，记作 EFC Group。
- App 保留现有接收 EFC Scene Recall 的方式，用 Scene ID 更新 EFC 状态。
- Associate with group(s) 只负责让受控灯订阅 EFC Group 的业务控制模型。
- 移除“设置灯状态后 Store Scene”的旧设计。
- `0x4D/0x07` 动作配置成为 Fire / Power Loss / Event Ends 的唯一动作来源。

## 当前 App 接收 EFC Scene Recall 的方式

当前代码不是通过给手机本地某个 Scene Client model 下发订阅来接收 EFC Scene Recall，而是通过以下链路生效：

1. 进入 Space 后，`SpaceViewController` 创建 `EmergencyFireControllerSceneEventManager`。
2. `EmergencyFireControllerSceneEventManager.activate()` 会调用 `refreshProxyFilterAddresses()`。
3. `refreshProxyFilterAddresses()` 从所有 EFC 配置中取 `publishGroupAddress`，把这些 EFC Group 地址加入当前 proxy filter。
4. 各页面的 `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)` 收到 Mesh message 后调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`。
5. Manager 只处理 `SceneRecall` / `SceneRecallUnacknowledged`。
6. Manager 用 `destination == controller.publishGroupAddress` 和 `source` 属于 EFC 节点或其元素地址来匹配控制器。
7. Manager 根据 Scene ID 映射状态：
   - `0xFF20` -> Power Loss triggered
   - `0xFF21` -> Fire Alarm triggered
   - `0xFF22` -> Restored
8. 匹配成功后发 `emergencyFireControllerSceneEventNotification`，监控页据此更新显示状态。

这个机制已经能工作，本轮保留。当前缺口是：如果 EFC 添加到 Space 后还没有 Associate Group 或没有进入同步，`publishGroupAddress` 可能为空，proxy filter 没有 EFC Group 可加入，App 就可能收不到 EFC 的 Scene Recall 事件。

## 设计方案

采用方案 A：完整切换到 EFC Group + action config 模型。

### 1. EFC Group 生命周期

每个 EFC 在添加到 Space 或绑定真实 EFC 节点后立即创建并保存一个独立 virtual group。

涉及入口：

- Classic add flow：EFC provision complete 后 `DeviceEmerFireStore.shared.ensureDevice(...)` 或 `bind(...)`。
- Professional add flow：同 Classic。
- 从已有 Mesh 节点恢复/导入本地记录：`ensureDevice(...)`、`restoreDevice(...)`。
- 编辑页 link real device 后的绑定流程。

规则：

- 如果 `publishGroupAddress` 已存在，复用，不重复创建。
- 如果不存在，调用现有 `ensurePublishGroup(meshUUID:subnetworkId:)` 创建并保存。
- 创建或复用后刷新 `EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()`。
- 删除 EFC 时仍清理本地 cached virtual group；灯端订阅清理由同步任务处理。

这样即使没有 Associate Group，App 也能把 EFC Group 加到 proxy filter，并接收 EFC Scene Recall 状态事件。

### 2. Associate with group(s)

添加 Group 时：

- Group 内所有在线、keybind 完成、具备 Light Lightness Server model 的灯，订阅 EFC Group。
- 如果 Event Ends 选择 Restore AUTO，则这些灯额外让 Light LC Server model 订阅 EFC Group。
- 不再订阅 Scene Server。
- 不再执行 `LightLightnessSet + SceneStore`。

删除 Group 时：

- 对曾经受该 EFC 影响的 Group 内灯，解除 Light Lightness Server 对 EFC Group 的订阅。
- 如果灯的 Light LC Server 曾因 Restore AUTO 订阅过 EFC Group，也解除该订阅。
- 不再解除 Scene Server 订阅，除非为了兼容清理历史旧订阅。历史清理建议作为一次迁移兼容：如果发现 Scene Server 仍订阅 EFC Group，可顺带 delete，避免旧配置残留。

### 3. Fire / Power Loss 动作配置

`When The Emergency Event Occurs` 下发 `0x4D/0x07`。

Fire Alarm Emergency：

- `state_idx = 0x01`
- `action_type = 0x06`
- `stage1_target = EFC Group`
- `stage2_target = EFC Group`
- `app_idx = Space App Key Index`
- `ttl = 0xFF`
- `transition_time = 0x00`
- `delay = 0x00`
- `params = U16 brightness value`

Power Loss Emergency：

- `state_idx = 0x00`
- `action_type = 0x06`
- `stage1_target = EFC Group`
- `stage2_target = EFC Group`
- `app_idx = Space App Key Index`
- `ttl = 0xFF`
- `transition_time = 0x00`
- `delay = 0x00`
- `params = U16 brightness value`

当前代码已能编码 `0x4D/0x07` 的字段形态，但 App 层需要把 TTL 从 `networkParameters.defaultTtl` 改为 `0xFF`。

### 4. Repeatedly Send Emergency Control Every

使用 `0x4D/0x03` 重发参数：

- `state_idx = 0x03`
- `N = UI seconds value`
- `M = 0xFFFF`

当前 SDK 编码符合 `state_idx + N + M`。App 侧当前使用 `triggerIntervalSeconds` 和 `triggerCount`，需要确保 `triggerCount` 固定为 `0xFFFF`，不被旧配置或导入数据改成其他值。

### 5. Event Ends 动作配置

Action 使用 `0x4D/0x07`。

Restore AUTO：

- `state_idx = 0x02`
- `action_type = 0x05`
- `stage1_target = EFC Group`
- `stage2_target = EFC Group`
- `app_idx = Space App Key Index`
- `ttl = 0xFF`
- `transition_time = 0x00`
- `delay = 0x00`
- `params = U8 0x01`
- 关联灯需要 Light LC Server 订阅 EFC Group。

Set Brightness to：

- `state_idx = 0x02`
- `action_type = 0x06`
- `stage1_target = EFC Group`
- `stage2_target = EFC Group`
- `app_idx = Space App Key Index`
- `ttl = 0xFF`
- `transition_time = 0x00`
- `delay = 0x00`
- `params = U16 brightness value`
- 关联灯只需要 Light Lightness Server 订阅 EFC Group。

None：

- `state_idx = 0x02`
- `action_type = 0xFF`
- `stage1_target = EFC Group`
- `stage2_target = EFC Group`
- `app_idx = Space App Key Index`
- `ttl = 0xFF`
- `transition_time = 0x00`
- `delay = 0x00`
- `params = empty`

当前 SDK `.invalid` action 会编码为空 params，符合 None 的 params 要求。App 层需要保证即使 action 是 `.invalid`，仍使用 EFC Group、当前 AppKey、TTL `0xFF`。

### 6. Resuming in

使用 `0x4D/0x06` restore delay set：

- `restore_delay_s = UI seconds value`
- 范围 `0...120`
- 默认 `2`

当前 UI 范围和默认值符合要求。

### 7. Send Count

使用 `0x4D/0x03` 重发参数：

- `state_idx = 0x02`
- `N = 0x0005`
- `M = UI send count`
- 范围 `1...5`
- 默认 `2`

当前 UI 范围、默认值和 SDK 编码方向符合要求。

## 当前不符合项

1. EFC Group 不在添加到 Space 后立即创建。
2. 没有 Associate Group 时，App 可能没有 EFC Group 地址可加入 proxy filter。
3. 关联 Group 时订阅的是 Scene Server 和 Light LC Server，不是 Light Lightness Server。
4. Light LC Server 当前无条件订阅，应改为只有 Restore AUTO 时订阅。
5. 仍存在 `LightLightnessSet + SceneStore(0xFF20/0xFF21)` 旧任务。
6. cleanup 当前解除 Scene Server / Light LC Server，未覆盖 Light Lightness Server。
7. action config TTL 当前使用默认 TTL，协议建议为 `0xFF`。
8. 保留场景常量当前仍被注释/导出过滤/状态事件复用，需要区分“状态事件 Scene ID”与“灯端 Store Scene”两个概念。

## 实现边界

本轮做：

- EFC Group 创建时机前移到 EFC 添加/绑定/恢复后。
- 保留现有 proxy filter + dispatch + Scene ID 状态解析机制。
- 重写 Associate Group 的订阅模型。
- 移除灯端 Store Scene 同步任务。
- 修正 action config TTL 和 None action target。
- 增加必要的历史订阅清理，避免旧 Scene Server 订阅残留。

本轮不做：

- 不改 UI 视觉和文案结构。
- 不新增完整 action editor。
- 不改变 SDK `0x4D/0x07` / `0x4D/0x03` 基础编码，除非实现中发现 SDK 与协议字节级不一致。
- 不改变 EFC Scene Recall 的现有接收机制。

## 验收标准

1. 添加 EFC 到 Space 后，即使没有 Associate Group，本地也有 `publishGroupAddress`。
2. 进入 Space 后 proxy filter 包含该 EFC Group。
3. EFC 发 `SceneRecall(0xFF20/0xFF21/0xFF22)` 到 EFC Group 时，App 能匹配控制器并更新状态。
4. Associate 添加 Group 时，日志出现 Light Lightness Server subscription 到 EFC Group。
5. Restore AUTO 时额外出现 Light LC Server subscription；Set Brightness/None 不出现新的 Light LC subscription。
6. SAVE 不再出现 `SceneStore(0xFF20/0xFF21/0xFF22)`。
7. `0x4D/0x07` 三条动作配置的 TTL 为 `0xFF`，target 都是 EFC Group。
8. 删除 Group 时解除对应模型订阅，旧 Scene Server 订阅如存在也被清掉。
