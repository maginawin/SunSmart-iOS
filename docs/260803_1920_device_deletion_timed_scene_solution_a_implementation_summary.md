# 设备删除后 Timed / Scene 方案 A 实施总结

## 1. 实施结果

已按确认范围完成“方案 A + Scene capability guard 小修正”：

1. 新配网 Node 在 App 生成附加 Scene / Schedule 消息之前，将全部 Scheduler Setup Model 初始化为权威空状态；
2. 正常删除成功和用户确认 Force Delete 后，清理 Schedule 中对被删设备地址的 active / pending 直接引用；
3. Reset 失败且用户取消 Force Delete 时不修改 Schedule；
4. Group / Scene Target 的全局 Timed 和 Scene 定义保持不变；
5. Scene Delete 能力门槛改为 Scene Setup Model，不再错误依赖 Scheduler Setup Model；
6. 新增 Common 文件已同步加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

本轮未修改本地化、资源、Auth、依赖或服务器接口，未执行 Git commit、push、merge。

## 2. SDK 修改

本地 SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

### 2.1 Fresh Scheduler 状态

新增 `FreshProvisioningSchedulerState`：

- 为 Composition 中的每个 Scheduler Setup Model 建立空 Entry map；
- 使用“所有 Model 已有状态”作为重复生命周期边界保护，避免后续 Schedule 写入成功后再次被清空；
- 支持多 Scheduler Model，并对重复 Model identifier 安全去重。

`Node.initializeFreshProvisioningSchedulerStateIfNeeded()` 负责：

- 写入 per-Model known-empty 状态；
- 清空兼容扁平 `schedulerActions` 和 `scheduleIds`；
- 清除只属于历史坏缓存的 preserved data / decode error；
- 保存 Node 属性；
- 输出 Node、Scheduler Model Element 和保存结果诊断日志。

`MeshFastAddDeviceOperation` 在基础配置完全收敛、外部 append messages 回调执行之前调用初始化，因此：

- 只添加到 Space 时，新 Node 不再是 Scheduler unknown；
- 直接添加到 Group 或 Restore 时，后续附加任务仍可在 known-empty 基础上建立实际 Scene / Schedule 状态；
- existing / imported / reload Node 不经过该 fresh provisioning 边界，原有 unknown 可重试语义保持不变。

### 2.2 并存 SDK 改动保护

开始实施时，SDK 已存在另一组未提交的动态 TimeSet 消息刷新改动，涉及：

- `MeshFastAddDeviceManager.swift`；
- `MeshMessageManager.swift`；
- `MeshScheduleServer.swift`；
- `Node+Messages.swift`；
- `RefreshableValue.swift` 及其测试。

本次只在独立位置增加 fresh Scheduler 生命周期逻辑，没有回退、覆盖或归因这些并存改动。四品牌构建同时编译了两组改动。

## 3. App 修改

### 3.1 永久删除上下文

新增 `DevicePermanentDeletionContext`：

- 发 Reset 前捕获 Node、地址、Mesh UUID、Subnetwork ID 和当前 Schedule 引用；
- context 初始化不修改数据；
- `commit()` 具备重复调用保护；
- 仅在永久删除已经成立时执行 Schedule 与既有 Node 扩展数据清理。

接入的删除入口：

- `DeviceProtocol.deleteNodes` 通用批量删除；
- `DeviceLightsViewController` 多灯删除；
- `DeviceLightViewController` 单灯详情删除；
- `DeviceDongleViewController` Dongle 绑定 Node 删除。

各入口提交规则一致：

| 分支 | 是否提交 Schedule 清理 |
| --- | --- |
| Node Reset 成功 | 是 |
| Node Reset 失败，用户取消 | 否 |
| Node Reset 失败，用户确认 Force Delete | 是 |

### 3.2 Direct Device Timed 地址清理

新增纯状态策略 `DeviceScheduleAddressCleanup`：

- 从 `nodeAddresses` 删除目标地址；
- 从 `needDeleteNodeAddresses` 删除目标地址；
- 删除全部重复引用；
- 保留其他 Direct Device 地址；
- 未引用目标地址时不保存 Schedule；
- 每个发生变化的 Schedule 只保存一次；
- 不删除 Schedule 对象，不修改 Group、Scene、Profile Target。

### 3.3 Scene capability guard

`Node.getNodeNeedDeleteSceneDatas` 现在以 `sceneSetupModel` 判断 Scene Delete 能力，覆盖“支持 Scene、不支持 Scheduler”的设备，同时没有增加 fresh ungrouped Node 的 Scene orphan 扫描。

## 4. TDD 证据

### 4.1 Fresh provisioning Scheduler 状态

RED：Standalone 测试因 `FreshProvisioningSchedulerState` 不存在而编译失败。

GREEN：`scripts/check_fresh_provisioning_scheduler_state.sh` 输出：

- `FreshProvisioningSchedulerStateTests passed`

覆盖每个 Model known-empty、重复边界不重置、重复 identifier 安全。

### 4.2 Device Schedule 地址清理

RED：Standalone 测试因 `DeviceScheduleAddressCleanup` 不存在而编译失败。

GREEN：`scripts/check_device_permanent_deletion_cleanup.sh` 输出：

- `DeviceScheduleAddressCleanupTests passed`

覆盖 active / pending 同时清理、重复地址、保留其他目标和未关联 no-op。

### 4.3 Scene capability

RED：Standalone 测试因 `SceneDeleteCapability` 不存在而编译失败。

GREEN：`scripts/check_scene_delete_capability.sh` 输出：

- `SceneDeleteCapabilityTests passed`

覆盖有 Scene Setup 时允许判断、缺少 Scene Setup 时不生成删除任务。

说明：SDK 完整 `swift test` 在 macOS 主机上会被工程既有的 `UIKit` import 阻断，因此本轮使用既有 Standalone 测试模式验证纯状态逻辑，再由 generic iPhoneOS 构建验证完整 SDK / App 集成。

## 5. 回归与工程验证

以下聚焦测试通过：

- FreshProvisioningSchedulerStateTests；
- DeviceScheduleAddressCleanupTests；
- SceneDeleteCapabilityTests；
- TimedSchedulerOwnerPolicyTests；
- TimedSchedulerSingleOwnerContractTests；
- SchedulerModelCachePersistenceTests；
- SchedulerModelReadCompletionTests；
- FastAddTaskCheckpointTrackerTests；
- Fast Add dual-scene task-scoped verification。

工程与差异检查通过：

- `plutil -lint SunSmart.xcodeproj/project.pbxproj`；
- 三个新增 Common 文件在四个 Sources Phase 中各出现一次；
- App `git diff --check`；
- SDK `git diff --check`。

以下 generic iPhoneOS Debug 构建均输出 `BUILD SUCCEEDED`：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

构建日志仍包含既有 warning：AppIntents metadata 未启用、部分品牌 Info.plist 位于 Copy Bundle Resources、部分 target 存在 FSCalendar 重复 Compile Sources；本次没有修改这些范围。

## 6. 尚未完成的真实环境验收

静态、测试和构建结果不能代替设备真实状态验证。仍需真机覆盖：

1. 正常 Reset 删除与 Reset 失败后的 Force Delete；
2. Force Delete 后确认设备真正回到 unprovisioned，再重新添加；
3. Classic / Professional；
4. 只添加到 Space、Manual Group、Automatic Profile Group；
5. 0 / 1 / 16 个 Timed；
6. Device / Group / Scene Target 混合；
7. ordinary / Light LC / 多 Scheduler Model；
8. 返回 Lights、进入 Timed、退出重进 Space、杀进程重启；
9. Scene waitDelete 与 Scene-only capability 设备。

关键验收结果应为：

- 永久删除后，App Schedule 不再包含旧 Node active / pending 直接地址；
- 删除失败并取消 Force Delete 时，Schedule 保持原样；
- 新 Node 只添加到 Space 后，每个 Scheduler Setup Model 为 known empty；
- Lights 页不再生成 0～15 的虚假 Scheduler Delete；
- 加入目标 Group 时只出现真实需要的 Scene / Timed 正向同步；
- existing unknown、权威读取失败和真实 cleanup 残留仍保持可见、可重试。
