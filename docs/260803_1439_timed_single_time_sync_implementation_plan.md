# Timed 单设备单次校时 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Do not use subagents unless the user explicitly changes the project instruction.

**Goal:** 将常规 Timed 日程同步改为同一设备每轮最多一次 Time Set，并确保该消息在真实发送或重试边界刷新时间，失败时阻断本设备后续启用日程。

**Architecture:** App 层用纯策略计算每设备是否需要校时及哪些日程依赖校时，再用独立 `DeviceOperationType` task 编排依赖；SDK 层给 `MeshMessageHandle` 增加保持对象身份的动态消息 provider，并在普通代理队列与 Fast Add 队列的真实发送边界刷新。Schedule 的消息生成只保留 cleanup 与 Owner Set，所有批量入口显式组装一次校时。

**Tech Stack:** Swift 5、UIKit、NordicSigMeshSDK、Swift Package Manager、XCTest、现有 standalone Swift contract scripts、Xcode generic iPhoneOS build。

## Global Constraints

- 所有新增或修改的用户可见文案同时维护 English 与简体中文。
- 不新增 Auth、AppKey、NetKey 或其他认证信息；诊断日志不得输出认证数据。
- 保持 Scheduler 单 Owner、非 Owner cleanup、Group 退出非阻断迁移和 Fast Add checkpoint `===` 身份语义。
- 当前 App worktree 已有 EFC 文档、测试和脚本改动；不得覆盖、回退或批量格式化这些改动。
- SDK 当前位于 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 的 `dev` 分支且基线干净。
- 未经用户明确要求不执行 Git commit、push 或 merge。
- 实现必须严格执行 RED → GREEN → REFACTOR；每个生产行为修改前先运行对应失败测试。
- 构建只使用 generic iPhoneOS，不使用 Simulator，也不使用 shell 包装或日志重定向。

---

### Task 1: SDK 动态 MeshMessageHandle

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshMessageManager.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleDynamicMessageTests.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/RefreshableValueTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/scripts/check_refreshable_value.sh`

**Interfaces:**
- Produces: `MeshMessageHandle.init(messageProvider:model:defaultTTL:)`
- Produces: `MeshMessageHandle.init(messageProvider:address:defaultTTL:)`
- Produces: `MeshMessageHandle.prepareMessageForSend()`
- Produces: `Node.makeLocalTimeSetMessageHandle(model:)`
- Invariant: `MeshMessageHandle` 实例、address、model 和 callback identity 不变，只在发送边界替换内部 `message`。

- [ ] **Step 1: 新增动态 provider 的失败测试**

  测试使用一个带字节值的真实 `StaticMeshMessage` fixture，provider 每次返回不同参数。断言初始化调用一次 provider；每次 `prepareMessageForSend()` 再调用一次，并且 `handle.message.parameters` 变为最新字节。另加固定 handle 测试，断言 prepare 不改变参数。

- [ ] **Step 2: 运行 SDK 聚焦测试确认 RED**

  Run: `swiftc -parse-as-library Tests/Standalone/RefreshableValueTests.swift -o /tmp/RefreshableValueTests`

  Expected: 编译失败，明确缺少 `RefreshableValue`。本 SDK import UIKit，macOS `swift test` 会先因平台错误失败，因此不能作为有效 RED，也不使用 Simulator 绕过项目规则。

- [ ] **Step 3: 最小实现动态 handle**

  将 `message` 从不可变属性调整为 `public private(set)`，保存可选 provider；旧 initializer provider 为 `nil`，新 initializer 在构造时生成初始消息。`prepareMessageForSend()` 仅在 provider 存在时更新消息。

- [ ] **Step 4: 接入两个真实发送边界**

  - `MeshMessageManager.sendMessageEvent()`：handle 出队且确认 proxy 存在后、日志及读取 `meshMessage` 前调用 prepare；busy 重新入队后再次出队会再次刷新。
  - `MeshFastAddDeviceOperation.sendAppendMessages()`：读取当前 `messageHandle.message` 前调用 prepare；busy 重试重新进入此方法时再次刷新。

- [ ] **Step 5: 增加 Time Set 动态工厂**

  `Node.makeLocalTimeSetMessageHandle(model:)` 使用 provider 调用 `Node.setLocalTimeMessage()`，不改变现有 `Node.setLocalTimeMessage()` 的协议、时区或 payload 编码。

- [ ] **Step 6: 运行 SDK 测试确认 GREEN**

  Run: `zsh scripts/check_refreshable_value.sh`

  Expected: 动态与固定 value 测试全部通过，0 failure。

- [ ] **Step 7: 运行相关 SDK 回归**

  Run: `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: 动态 wrapper、普通代理队列与 Fast Add 发送边界在 iPhoneOS SDK 下编译通过；运行期回归由 standalone test、App contract 和最终真机承担。

### Task 2: 纯校时策略与 App 集成类型

**Files:**
- Create: `SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Test: `Tests/Timed/TimedScheduleTimeSyncPolicyTests.swift`
- Create: `scripts/check_timed_schedule_time_sync.sh`

**Interfaces:**
- Produces: `TimedScheduleTimeSyncPlan.requiresTimeSync: Bool`
- Produces: `TimedScheduleTimeSyncPlan.scheduleRequiresTimeSync: [Bool]`
- Produces: `TimedScheduleTimeSyncPolicy.makePlan(hasTimeModel:scheduleEnabledStates:)`

- [ ] **Step 1: 编写纯策略失败测试和 runner**

  用手工字面量覆盖：16 个启用、16 个禁用、启用/禁用混合、无 Time Model、空数组。断言只有“存在 Time Model 且至少一个启用写入”时 `requiresTimeSync == true`，并且只有启用日程的 dependency 位为 true。

- [ ] **Step 2: 运行策略脚本确认 RED**

  Run: `zsh scripts/check_timed_schedule_time_sync.sh`

  Expected: 编译失败，明确缺少 `TimedScheduleTimeSyncPolicy`。

- [ ] **Step 3: 实现最小纯策略**

  策略只接收 Bool 数组，不引用 `Node`、`Schedule`、SDK 单例或 UI，便于所有入口共享并保持测试真实。

- [ ] **Step 4: 将策略文件加入四个 target**

  同一个文件加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` Sources；不修改其他资源、依赖或 build setting。

- [ ] **Step 5: 运行策略脚本确认 GREEN**

  Run: `zsh scripts/check_timed_schedule_time_sync.sh`

  Expected: 所有策略矩阵通过。

### Task 3: 将 Time Set 从单个 Schedule 消息中分离

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**
- Produces: `ActionType.timeSynchronization`
- Produces: `DeviceOperationType.configuration(node:type: .timeSynchronization)` 的单一动态 Time Set handle
- Produces: `DeviceOperationType.isTimedScheduleTimeSyncOperation`
- Consumes: `Node.makeLocalTimeSetMessageHandle(model:)`

- [ ] **Step 1: 扩充单 Owner contract 并确认 RED**

  新契约要求：`Schedule.getMessageHandles` 不再包含 `Node.setLocalTimeMessage()`；Time Set 只能由 `.timeSynchronization` operation 构造；该 handle 使用 SDK 动态工厂且 `continuous == false`。

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Expected: 旧实现因 Schedule 内仍嵌入 Time Set 而失败。

- [ ] **Step 2: 增加独立 time synchronization operation**

  在 `ActionType` 增加 `.timeSynchronization`：

  - `isSuccessful` 返回 true，最终成功仍由 acknowledged Time Status 对应的 handle 结果决定；
  - 有 Time Model 时生成一个动态 Time Set handle；
  - 无 Time Model 时返回空数组；
  - handle 失败时中止当前命令队列。

- [ ] **Step 3: 移除 Schedule 内隐式 Time Set**

  `Schedule.getMessageHandles` 对启用日程只保留非 Owner cleanup 和 Owner Set；禁用、删除及 Owner 规则保持原样。

- [ ] **Step 4: 运行单 Owner contract 确认 GREEN**

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Expected: 既有 Owner/cleanup 契约与新校时职责分离契约均通过。

### Task 4: Sync Devices 独立任务、依赖和重试

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**
- Consumes: `TimedScheduleTimeSyncPolicy.makePlan(...)`
- Consumes: `.timeSynchronization`
- Behavior: Schedule step 的 tasks 为可选 `Sync Time` + 原日程 tasks；启用日程依赖 Sync Time，禁用日程不依赖。

- [ ] **Step 1: 编写 Sync Devices 依赖失败契约**

  契约覆盖：16 个启用只建立一个 time task；time task 位于首个日程前；启用日程的 `relevanceTaskModels` 指向同一 time task；retry relevance 会带回 time task；Group 退出的非阻断 step 策略不变。

- [ ] **Step 2: 运行契约确认 RED**

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Expected: 缺少独立 task 或 retry dependency，测试失败。

- [ ] **Step 3: 实现 Sync Devices task 编排**

  在 `.syncSchedules` 分支计算一次 plan；仅当 policy 要求时创建 `Sync Time` task，并把对应启用日程 task 关联到它。无 Time Model 时不创建前置 task，保持现有兼容写入。

- [ ] **Step 4: 实现 retry dependency**

  `SyncDeviceStepTaskModel.resyncRelevanceCheck()` 将 time synchronization 作为必须重新执行的前置任务；单 task retry 不复用上轮已发送的时间。

- [ ] **Step 5: 增加本地化**

  English：`Sync Time`；简体中文：`同步时间`。复用统一 key，不硬编码用户可见字符串。

- [ ] **Step 6: 运行策略与契约确认 GREEN**

  Run: `zsh scripts/check_timed_schedule_time_sync.sh`

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

### Task 5: Deferred Sync 与 Fast Add

**Files:**
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Modify: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
- Modify: `scripts/check_fast_add_task_checkpoint_tracker.sh`

**Interfaces:**
- `DeviceGroupDeferredSyncTask.requiresSuccessfulTimeSync`
- `DeviceGroupDeferredSyncTask.isTimeSynchronization`
- Fast Add batch 仍复用同一批 `MeshMessageHandle` 实例。

- [ ] **Step 1: 编写 Deferred/Fast Add 失败测试**

  覆盖：一个设备 16 个启用日程只产生一个 time task；time task handle 位于所有 Schedule handles 之前；time handle 与 tracker checkpoint 使用同一对象；time failure 状态会跳过依赖日程；非日程任务排在校时段之前，避免因 time failure 被无关阻断。

- [ ] **Step 2: 运行测试确认 RED**

  Run: `zsh scripts/check_fast_add_task_checkpoint_tracker.sh`

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

- [ ] **Step 3: 调整 deferred task 计划**

  对 `.syncSchedules` 使用纯策略：插入一次 time task，并标记启用日程依赖。将 Timed time + schedule 段放到其他独立 deferred tasks 之后，同时保持 Profile、Scene 在 Schedule 前的既有要求。

- [ ] **Step 4: 调整 deferred runner 失败状态**

  runner 记录本轮 time task 成功状态；失败后不发送 `requiresSuccessfulTimeSync` 的日程 task，但继续处理不依赖校时的任务，最终 plan 返回失败。

- [ ] **Step 5: 保持 Fast Add checkpoint identity**

  `makeTaskCheckpointBatch` 对动态 time handle 和 schedule handles 仍只调用一次 `makeMessageHandles`；发送列表、contains、success callback 和 tracker 共用相同实例。

- [ ] **Step 6: 运行测试确认 GREEN**

  Run: `zsh scripts/check_fast_add_task_checkpoint_tracker.sh`

  Run: `zsh scripts/check_fast_add_dual_scene_verification.sh`

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

### Task 6: Device Restore 执行时生成与失败依赖

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**
- `DeferredRestoreTask` 保存 operation 和 dependency metadata，不保存创建阶段生成的 handles。
- 每次执行/重试调用 task 的 handle factory；time task 使用 SDK 发送边界刷新。

- [ ] **Step 1: 编写 restore 失败契约**

  契约要求 `DeferredRestoreTask` 不保存 `[MeshMessageHandle]`，每个设备只插入一次 time task，执行和重试时生成 handles，time failure 跳过依赖的启用日程。

- [ ] **Step 2: 运行契约确认 RED**

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

- [ ] **Step 3: 将 restore task 改为语义任务**

  Scene Recall 过滤在每次生成 handles 后执行；`filteredSceneRecallCount` 随本次生成结果计算，不在计划阶段冻结。

- [ ] **Step 4: 传播 time dependency 状态**

  递归 runner 维护可选 time success 状态：time task 最终失败后跳过依赖日程并保留 `hadFailedTask == true`；其他 profile、scene、switch、删除任务继续按原逻辑运行。

- [ ] **Step 5: 保持 retry 与响应恢复语义**

  Time Set 的 busy/显式 retry 在发送边界刷新；其他失败 handles、可靠 operation state、Scene Recall 排除和缓存更新逻辑不改变。

- [ ] **Step 6: 运行契约确认 GREEN**

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Run: `zsh scripts/check_device_restore_efc_support.sh`

  Expected: Timed 新契约通过，已有 EFC restore 支持不回归。

### Task 7: 收口批量和直接入口

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Modify: `SunSmart/Main/Group/Model/GroupServer.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Timed/Model/ScheduleServer.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift`
- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**
- `NodeSyncData.syncSchedules`：每设备 batch 至多一个 time handle。
- `Group.getNodeSyncDataMessageHandles`：多 Schedule 共用一个 time handle。
- `ScheduleServer`：按设备顺序执行独立 batch 并聚合失败。

- [ ] **Step 1: 编写入口覆盖失败契约**

  枚举全部生产调用点，要求不得直接依赖 Schedule 内嵌 Time Set；`NodeSyncData`、Group add、restore、ScheduleServer、SDK MeshScheduleServer 均显式使用统一 time operation 或动态工厂。

- [ ] **Step 2: 运行契约确认 RED**

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

- [ ] **Step 3: 收口单设备批量构造**

  `NodeSyncData.syncSchedules`、Group add 和节点 restore 按纯策略在首个启用 Schedule 前插入一次动态 time handle；删除路径不插入。

- [ ] **Step 4: 重构 ScheduleServer 为按设备小批次**

  先构造明确的设备操作列表，再逐设备调用 `MeshProxyMessageCommand`：本设备 time handle 失败会中止本设备 Schedule 写入；完成回调继续下一设备；最终任一设备失败则走原 failed callback，否则 success。每个成功 handle 继续调用 `node.updateData`。

- [ ] **Step 5: 更新 SDK MeshScheduleServer**

  仅把已有“一设备一次”的固定 Time Set 替换为动态工厂，不改变其 ordinary Scheduler owner 或 `timestamp == 0` 条件。

- [ ] **Step 6: 运行全部聚焦测试确认 GREEN**

  Run: `zsh scripts/check_timed_schedule_time_sync.sh`

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Run: `zsh scripts/check_timed_scheduler_persistence.sh`

  Run: `zsh scripts/check_fast_add_task_checkpoint_tracker.sh`

### Task 8: 诊断、静态检查与四品牌构建

**Files:**
- Modify only if needed: Timed DEBUG logging sites touched above
- Create: `docs/260803_1439_timed_single_time_sync_implementation_summary.md`

**Interfaces:**
- DEBUG 日志记录 node、入口、刷新/发送/响应阶段，不记录认证数据。

- [ ] **Step 1: 全量搜索 Time Set 生产入口**

  Run: `rg -n 'setLocalTimeMessage\(\)|makeLocalTimeSetMessageHandle|timeSynchronization' SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK`

  逐条确认：Timed 批量入口使用动态工厂且每设备一次；DevicesViewController 广播与 Gateway time coordinator 属于独立业务，不误改。

- [ ] **Step 2: 运行 SDK 聚焦测试与 iPhoneOS 构建**

  Run: `zsh scripts/check_refreshable_value.sh`

  Run: `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: standalone 行为测试通过，SDK generic iPhoneOS build 通过。macOS `swift test` 因 UIKit 平台限制不列为成功门禁。

- [ ] **Step 3: 运行 App 聚焦脚本**

  Run: `zsh scripts/check_timed_schedule_time_sync.sh`

  Run: `zsh scripts/check_timed_scheduler_single_owner.sh`

  Run: `zsh scripts/check_timed_scheduler_persistence.sh`

  Run: `zsh scripts/check_fast_add_dual_scene_verification.sh`

  Run: `zsh scripts/check_device_restore_efc_support.sh`

- [ ] **Step 4: 检查差异边界**

  Run: `git diff --check`

  分别检查 App 与 SDK 的 `git diff --stat`、`git diff --name-only`，确认没有覆盖基线中的 EFC 文件、未新增 Auth、未修改无关资源或依赖。

- [ ] **Step 5: 四品牌 generic iPhoneOS 构建**

  依次直接运行：

  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

- [ ] **Step 6: 自审设计与实现一致性**

  逐项核对方案 A：单设备单次、发送边界刷新、Time Status ACK、失败阻断启用日程、不阻断纯删除与 Group 退出、Fast Add identity、所有入口覆盖。由于项目禁止默认 subagents，不调用 code-review subagent，由主代理对 App 与 SDK diff 分别完成一次独立复核。

- [ ] **Step 7: 生成实施总结**

  明确区分：自动化/构建结果、未执行的真机 Mesh 验收、原 Group 1 → Group 2 场景的真机检查清单。未经真机读取 Time Status 与 Scheduler Register/Action，不宣称硬件业务链已最终验证。

## Plan Self-Review

- Spec coverage：方案 A 的六项核心约束分别落在 Task 1、3、4、5、6、7；Group 删除回归与真机边界在 Task 8。
- Placeholder scan：所有步骤均给出明确文件、行为、命令和期望结果，没有待补内容或模糊复用指令。
- Type consistency：动态 SDK API、纯 policy plan、独立 `.timeSynchronization` operation、Sync/Deferred/Restore dependency metadata 在各任务中名称一致。
- Scope control：不引入强制 Time Get，不改变 Scheduler Owner，不重构非 Timed 队列，不提交 Git。
