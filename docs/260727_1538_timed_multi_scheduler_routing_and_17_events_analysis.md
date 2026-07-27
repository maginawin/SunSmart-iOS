# Timed 多 Scheduler 路由与“16 条日程执行 17 次”分析

## 1. 结论

### 1.1 三种 Target 当前并不是各自固定使用不同 Scheduler Model

当前 Scheduler Model 的选择主要由 **Action、节点是否已识别为组成员、Light LC Scheduler 是否存在**决定，而不是只由 TargetType 决定。

当前行为：

| Target | UI Action | Schedule Action | 当前发送 Model |
|---|---|---|---|
| Devices | Auto/On | `turnOn = 0x01` | 节点已加入任意普通组且存在 Light LC Scheduler 时发送到 Light LC Scheduler；否则发送到 `schedulerSetupModel` |
| Devices | Off | `turnOff = 0x00` | `schedulerSetupModel` |
| Groups | Auto/On | `turnOn = 0x01` | 组成员存在 Light LC Scheduler 时发送到 Light LC Scheduler；否则发送到 `schedulerSetupModel` |
| Groups | Off | `turnOff = 0x00` | `schedulerSetupModel` |
| Scenes | Recall | `sceneRecall = 0x02` | `schedulerSetupModel` |

所以：

- Devices 和 Groups 的 Auto/On 走相同代码；
- Devices Target 中，如果设备本身已经在某个组，也可能被路由到 Light LC Scheduler；
- Scenes 并不是 Auto/On 或 Off，Scene Target 会强制使用 Scene Recall；
- TargetType 本身没有被传入最终 Model 路由判断。

### 1.2 “16 条日程执行 17 次”高度可能与双 Scheduler 实例和残留 slot 有关

标准 Mesh 的 16 条限制是：

> 每个 Scheduler Server 实例拥有一个独立的 16-entry Schedule Register。

如果一个节点有：

- 普通 Scheduler Server；
- Light LC Element 上的 Scheduler Server；

那么设备物理上存在两个独立 Register，理论上可以同时保存最多 32 个 entry。App 的产品层虽然只允许创建 16 个全局 schedule id，但无法阻止同一个 id 同时残留在两个 Scheduler 实例中。

双 Scheduler 本身不会自动把 16 变成 17。出现 17 次需要至少一个重复或孤儿 entry，例如：

| Scheduler 实例 | 有效 entry |
|---|---:|
| Light LC Scheduler | 16 |
| 普通 Scheduler | 1 个旧 entry |
| 设备实际可执行事件总数 | 17 |

当前代码中存在多条可以产生这种残留的确定性路径，因此该测试反馈具有较高可信度。

### 1.3 不建议未经条件确认就“有 Light LC 时所有 Action 都只使用 Light LC Scheduler”

“每个节点只设一个权威 Scheduler”这个方向正确，但直接规定“双模型设备全部使用 Light LC Scheduler”存在行为风险：

- Turn Off 是否能通过 Light LC Element 正确关闭主灯，需要固件 Composition 和状态绑定契约确认；
- Scene Recall 从 Light LC Scheduler 所在 Element 开始执行，不能向地址更小的 Element 回溯；如果业务 Scene 存在普通 Scene Server 上，可能无法正确 Recall；
- Devices Target 的 Auto/On 是否应在设备已入组时一律进入 AUTO，目前产品语义并不完全明确；
- 旧 App、恢复数据和现存设备中普通 Scheduler 上的 entry 仍需迁移和清理。

当前更安全的建议是：

> 保留按业务语义选择 Scheduler 的能力，但建立明确的 per-node、per-schedule Model ownership；写入前清理非 Owner Model 的同 index entry，删除时清理所有 Scheduler Model，并按 Model 读取和比对状态。

## 2. Target 到节点集合的差异

### 2.1 Devices

新增日程时：

- `nodeAddresses` 保存用户直接选择的节点地址；
- `selectTargetType = .devices`；
- 同步目标是这些节点。

相关位置：

- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift:196-200`
- `SunSmart/Main/Timed/Model/Scheduler.swift:83-87`

### 2.2 Groups

新增日程时：

- `groupAddresses` 保存选择的组地址；
- `selectTargetType = .groups`；
- 实际下发时展开为各组的 `group.nodes`。

相关位置：

- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift:201-204`
- `SunSmart/Main/Timed/Model/Scheduler.swift:88-92`

### 2.3 Scenes

新增日程时：

- `sceneNumber` 保存选择的 Scene；
- `selectTargetType = .scene`；
- 实际下发节点来自 Scene 关联的 Groups；
- Action 由 UI 强制设为 `.sceneRecall`。

相关位置：

- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift:205-210`
- `SunSmart/Main/Timed/View/ScheduleAddView.swift:84-102`
- `SunSmart/Main/Timed/View/ScheduleAddView.swift:123-138`

## 3. Model 路由的真实决定因素

### 3.1 `schedulerSetupModel`

SDK 的 `node.schedulerSetupModel` 调用 `getFunctionModel(modelId:)`。

`getFunctionModel` 按 `node.elements` 顺序返回第一个包含目标 Model ID 的 Element。因此它不是一个显式命名的“手动 Scheduler”，只是节点中找到的第一个 Scheduler Setup Server。

在普通 Scheduler 位于前面、Light LC Scheduler 位于后面的 Composition 中，它表现为普通 Scheduler。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift:149-153`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift:718-727`

### 3.2 `lightLCSchedulerSetupModel`

`node.lightLCSchedulerSetupModel`：

1. 先找到 Light LC Server 所在 Element；
2. 再只在该 Element 中查找 Scheduler Setup Server。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift:493-510`

### 3.3 最终路由没有检查 TargetType

`Schedule.getMessageHandles(node:delete:)` 的 Set 路由条件是：

- `schedule.action == .turnOn`；
- `node.group != nil`；
- `node.lightLCSchedulerSetupModel != nil`。

条件成立就发 Light LC Scheduler，否则发 `node.schedulerSetupModel`。

相关位置：

- `SunSmart/Common/Data/Node+MessageHandles.swift:421-459`

该函数没有检查：

- `selectTargetType == .devices`；
- `selectTargetType == .groups`；
- 具体选择的是哪个 Group。

所以 Devices Target 选择一个已经属于任意组的设备时，也会使用 Light LC Scheduler。

## 4. App 实际 Action 不止 Auto/On 和 Off

当前 UI：

- Devices / Groups：Auto/On、Off；
- Scenes：Recall。

对应标准 Action：

| UI | SchedulerAction |
|---|---|
| Auto/On | `.turnOn` |
| Off | `.turnOff` |
| Recall | `.sceneRecall` |

标准 Scheduler 不存在独立 AUTO Action。AUTO 是 App 和固件利用 Scheduler 所在 Element 及 Light LC 状态绑定形成的业务语义。

## 5. 为什么两个 Scheduler 可以出现超过 16 个实际事件

Bluetooth Mesh Model 1.1 定义 Schedule Register 为一个 16-entry、从 0 开始索引的数组。这个 State 属于对应 Element 上的 Scheduler Server / Scheduler Setup Server 实例。

因此两个 Scheduler Server 实例分别拥有：

- 普通 Scheduler：index 0...15；
- Light LC Scheduler：index 0...15。

两个实例中的 `index = 3` 是两个独立存储位置，不会互相覆盖。

官方规范：

https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html

规范中的关键点：

- Schedule Register 是 16-entry array；
- Scheduler Get / Action Get 操作的是某个 Element 的 Schedule Register；
- Scheduler Action Set 设置的是接收该消息的 Scheduler Setup Server 所对应的 Register。

## 6. 当前代码产生重复或孤儿日程的路径

### 6.1 删除 Auto/On 日程时可能只清理普通 Scheduler

这是目前最明确的风险。

`ScheduleServer.deleteSchedule` 在构造删除任务前先执行：

`schedule.action = .noAction`

之后删除消息进入 `Schedule.getMessageHandles(node:delete: true)`。

删除路由仍使用当前 `schedule.action == .turnOn` 来判断是否选择 Light LC Scheduler。此时 Action 已经被改成 `.noAction`，所以会落入 `schedulerSetupModel` 分支。

如果原 Auto/On entry 实际保存在 Light LC Scheduler：

1. App 删除普通 Scheduler 的同 index；
2. Light LC Scheduler 上的原 entry 未被删除；
3. App 本地 Schedule 对象被删除；
4. 该 Light LC entry 后续仍会由设备执行；
5. App 重新复用相同 id 时，设备可能在两个 Scheduler 上同时存在该 index。

相关位置：

- `SunSmart/Main/Timed/Model/ScheduleServer.swift:82-99`
- `SunSmart/Common/Data/Node+MessageHandles.swift:426-440`

另外，Direct Devices 删除路径中还有一个独立疑点：

- 先向 `needDeleteNodeAddresses` append；
- 随后立即 `removeAll()`。

这可能使直接设备目标的删除任务根本没有保留目标节点。

相关位置：

- `SunSmart/Main/Timed/Model/ScheduleServer.swift:89-90`

### 6.2 从 Auto/On 改为 Off 时不会清理原 Light LC entry

编辑保存先把 `schedule.action` 改成新 Action，再计算同步并生成消息。

例如：

1. 原 Action 为 Auto/On，index 5 写在 Light LC Scheduler；
2. 用户编辑为 Off；
3. 当前 Action 变成 `.turnOff`；
4. 新 entry 被写到 `schedulerSetupModel` 的 index 5；
5. Light LC Scheduler 的旧 Auto/On index 5 没有清理。

于是同一个 App Schedule 对象对应两个设备 entry。

反向从 Off 改为 Auto/On也存在相同问题：

- 普通 Scheduler 的旧 Off entry 可能残留；
- Light LC Scheduler 新增 Auto/On entry。

相关位置：

- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift:367-425`
- `SunSmart/Common/Data/Node+MessageHandles.swift:447-459`

### 6.3 Target 或组状态变化可能改变 Model 路由，但没有迁移旧 entry

以下变化都可能导致同一个 index 的目标 Model 改变：

- Devices Target 的节点从未入组变为已入组；
- Groups Target 的节点刚加入组；
- 设备 Composition 或恢复数据补全了 Light LC Scheduler；
- Target 从 Devices 切换到 Groups；
- Action 从 Turn On 切换为 Off 或 Scene Recall；
- 节点退出组。

当前同步流程只向新路由写入，没有记录旧 Owner Model，也没有先删除旧 Owner 上的 entry。

### 6.4 删除后 id 会被 App 重新复用

App 的 id 只根据本地 `MeshNetworkManager.instance.schedules` 查找 0...15 中的空位。

它不会先确认该 id 是否仍残留在设备的其他 Scheduler Register 中。

相关位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:731-738`

因此：

1. App 删除 id 3；
2. Light LC Scheduler 的 id 3 删除失败或未被路由到；
3. App 本地释放 id 3；
4. 新日程再次使用 id 3；
5. 新日程被写到普通 Scheduler；
6. 两个 id 3 在设备上同时有效；
7. App 仍只显示一个 id 3。

## 7. 为什么 App 很难发现第 17 条

### 7.1 `scheduleIds` 不是两个 Model 的并集

收到任意 Scheduler Status 后，SDK会把该响应的 16-bit schedules 字段转换成 id 数组，然后直接赋值给：

`node.scheduleIds`

如果分别收到两个 Scheduler Server 的状态，后一个响应会覆盖前一个结果，而不是求并集，也没有保留来源 Model。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:99-113`

### 7.2 `schedulerActions` 会按 index 覆盖

收到 Scheduler Action Status 后，SDK执行：

`schedulerActions[index] = entry`

如果普通 Scheduler 和 Light LC Scheduler 都存在 index 3：

- App 最终只保留最后收到的一条；
- 无法知道设备实际存在两条；
- 无法统计物理 entry 总数；
- 无法识别同 index 的 Model 冲突。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:114-128`

### 7.3 常用读取 API 只查询第一个 Scheduler Model

`MeshScheduleServer.getSchedule` 只使用：

`node.schedulerSetupModel`

它不会遍历 `getFunctionModels(.schedulerSetupServerModelId)`，也不会主动查询 `lightLCSchedulerSetupModel`。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift:94-122`

### 7.4 同步判断仍使用扁平缓存

App 判断某条 Schedule 是否需要同步时，只比较：

`node.schedulerActions[id]` 与本地 `schedulerEntry`

没有比较：

- entry 位于哪个 Model；
- 非 Owner Model 是否存在同 index；
- 两个 Model 是否存在冲突 entry。

相关位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1564-1578`

## 8. 对“16 条执行 17 次”的判断

### 8.1 与双 Scheduler 有关的条件

该反馈与双 Scheduler 高度相关，但需要准确表述：

> 不是“双 Scheduler 自动把 16 变成 17”，而是当前 App 缺少 Model ownership、跨 Model 清理和全量读取，导致同一个 App schedule id 可以在两个 Scheduler Register 中各占一个 entry。

### 8.2 最符合当前代码的形成方式

优先级从高到低：

1. 删除 Auto/On 日程时只删除普通 Scheduler，Light LC entry 残留；
2. Auto/On 与 Off 之间编辑，旧 Model entry 未清理；
3. Target、组成员状态或设备恢复导致 Model 路由变化；
4. 旧版本或其他同步入口曾把 entry 写到不同 Model；
5. id 被 App 本地释放后再次复用。

### 8.3 可以达到的最坏情况

如果 0...15 在普通 Scheduler 和 Light LC Scheduler 中都有效，设备理论上可以保存 32 个物理事件，而 App 仍只管理 16 个逻辑 id。

## 9. 是否采用“有 Light LC 就只使用 Light LC Scheduler”

### 方案 A：Model-aware ownership 与迁移，推荐

核心规则：

1. 每个 node + schedule id 只允许有一个 Owner Scheduler Model；
2. 根据业务语义选择 Owner；
3. Set 前检查并清理所有非 Owner Scheduler 的同 index；
4. Action、Target、组状态导致 Owner 改变时，先删除旧 Owner，再写新 Owner；
5. Delete 时不根据当前 Action 推断历史 Owner，直接清理该节点所有 Scheduler Setup Model 的同 index；
6. Read 时遍历所有 Scheduler Setup Model，状态按 Model 保存；
7. 同步判断同时检查 Owner entry 正确和非 Owner entry 不存在。

优点：

- 保留当前 Auto、Off、Scene 的既有语义；
- 可以修复第 17 条和幽灵日程；
- 可识别旧 App/恢复数据；
- 不依赖某个产品所有 Action 都能在 Light LC Element 正确执行。

代价：

- 需要调整 App 与 SDK 的数据结构、读取和同步判断；
- 需要明确 Model migration 的顺序和部分失败处理。

### 方案 B：双模型设备全部只使用 Light LC Scheduler

优点：

- 每台设备只有一个 Register；
- 逻辑和计数最简单；
- 不容易产生跨 Model 重复；
- Auto/On 的 AUTO 语义更稳定。

风险：

- Scene Recall 可能无法覆盖普通 Scene Server 所在的较早 Element；
- Turn Off、普通 On 和 Direct Device 行为可能改变；
- 需要迁移并清空普通 Scheduler 的 0...15；
- 需要固件 Composition 和状态绑定契约明确保证所有当前 Action 都能在 Light LC Scheduler 上正确工作；
- 非 Light LC 设备、仅普通 Scheduler 设备和旧固件仍需 fallback。

判断：

> 该方案只有在固件明确承诺 Light LC Scheduler 对 Turn On、Turn Off、Scene Recall 都满足 App 当前业务语义时才建议采用。

### 方案 C：保持现有路由，只修删除

内容：

- 删除时同时清理两个 Scheduler；
- Action 切换时清理旧 Model。

优点：

- 改动最小。

缺点：

- 读取仍看不到双 Model 冲突；
- 同步判断仍可能把错误 Model 判为成功；
- 旧残留无法可靠发现；
- Target/组状态变化仍可能再次制造重复。

判断：

> 只能作为临时止血，不建议作为完整修复。

## 10. 推荐设计

推荐采用方案 A，同时把“单一物理 Owner”作为强约束。

建议路由语义：

| 业务场景 | Owner 候选 |
|---|---|
| Group + Auto/On，节点支持 Light LC Scheduler | Light LC Scheduler |
| Device + Auto/On | 需要产品确认：按节点能力进入 AUTO，或明确改为普通 On |
| Off | 使用该 schedule 已记录的 Owner；若新建则按业务 Target 选择，不应仅因 Action 改变就静默换 Model |
| Scene Recall | 默认普通 Scheduler，除非 Scene 数据明确存储在 Light LC Element |
| 仅一个 Scheduler Setup Model | 使用唯一 Model |

其中 Off 应跟随 Schedule Owner，而不是固定使用普通 Scheduler。否则 Auto/On 与 Off 切换仍会迁移 Model。

## 11. 不依赖现场复测的验证方式

即使当前无法重新进行硬件复测，也可以先通过源码契约和模拟状态验证根因。

建议后续测试覆盖：

1. 双 Model：Light LC index 0...15 共 16 条，普通 Model 另有一个 stale entry，识别总物理 entry 为 17；
2. 删除 Auto/On：生成两个 Model 的 index 清理任务；
3. Auto/On 改 Off：先清 Light LC 旧 entry，再按 Owner 规则写新 entry；
4. Off 改 Auto/On：先清普通旧 entry，再写 Light LC；
5. Delete 不依赖当前 `schedule.action`；
6. Read 遍历两个 Scheduler Model；
7. 同 index 出现在两个 Model 时标记 conflict，而不是覆盖；
8. 修复/同步后 16 个逻辑 Schedule 对应恰好 16 个物理 Owner entry；
9. Scene Recall 不被误写到无法覆盖目标 Scene Server 的 Element；
10. 单 Scheduler 设备保持现有行为。

这些测试可以先证明 App 的路由和清理契约，不需要真实等待 16 条日程逐条执行。

## 12. 最终建议

1. 将“16 条执行 17 次”与当前 AUTO 异常合并视为同一类 **多 Scheduler ownership 缺失**问题处理。
2. 不要只修改 Auto/On 的 Set Model；必须一起处理 Set、Edit、Delete、Read、Sync、Restore 和 id reuse。
3. 当前优先方案不是无条件“全部使用 Light LC Scheduler”，而是：
   - 每条逻辑 Schedule 只能有一个物理 Owner；
   - 删除清理所有可能的历史 Owner；
   - 状态读取保留 Model 维度；
   - 检测并修复同 index 的跨 Model 冲突。
4. 如果固件后续确认双模型设备的所有 Scheduler Action 都能由 Light LC Scheduler 完整承载，再考虑把方案 A 的 Owner 规则简化为“Light LC 优先的单模型策略”。
