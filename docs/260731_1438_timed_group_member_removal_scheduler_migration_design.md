# Group Members 退组时 Timed Scheduler Owner 迁移设计

## 1. 状态

- 日期：2026-07-31
- 设计状态：已确认
- 选定方案：退出节点的 `.syncSchedules` 进入 Remove Section
- 失败语义：Scheduler Owner 迁移失败仍继续完成退组，Timed 保留真实待同步状态
- 本文只定义修复设计，不包含业务代码修改

## 2. 背景

当前自动 Profile Group 使用 membership-dependent Scheduler Owner：

- 自动 Profile Group 内的 `Turn On` 定时使用 Light LC Scheduler；
- 不在 Group 中的 `Turn On` 定时使用 ordinary Scheduler；
- `Turn Off` 等普通动作始终使用 ordinary Scheduler。

节点加入自动 Profile Group 时，Group Members 同步流程能够将直接 Device Target 的 `Turn On` 定时从 ordinary Scheduler 迁移到 Light LC Scheduler。

节点移出 Group 时：

1. `GroupMembersViewController` 将节点标记为 `.exitFailure`；
2. Owner Policy 将退出节点视为无有效 Group；
3. 直接 Device Target 的 `Turn On` 定时需要从 Light LC Scheduler 迁回 ordinary Scheduler；
4. `Node.getSyncData(type: .group(...))` 能够产生对应 `.syncSchedules`；
5. `SyncDevicesViewController.getSyncDeviceModel` 将 `.syncSchedules` 固定放入 `configturationSteps`；
6. outNodes 数据源只消费 `removeDevice`，这批迁移步骤被丢弃；
7. Group Target 定时虽然被正确删除，但直接 Device Target 的 `Turn On` 定时仍停留在 Light LC Scheduler；
8. Timed 页面随后正确显示 `owner-entry-missing`。

完整根因证据见：

`docs/260731_1409_timed_group_member_removal_resync_root_cause_analysis.md`

## 3. 目标

### 3.1 功能目标

成功移出自动 Profile Group 时：

- Group Target 定时从退出节点的全部 Scheduler Model 中删除；
- 直接 Device Target 的 `Turn On` 定时从 Light LC Scheduler 迁回 ordinary Scheduler；
- 直接 Device Target 的 `Turn Off` 定时不产生无关重写；
- Timed 页面不出现由本次成功退组引入的待同步；
- 不恢复 ordinary/Light LC 双 Owner 残留。

### 3.2 失败目标

Scheduler Owner 迁移失败时：

- 不阻止后续退组操作；
- 最终仍允许执行 `unsubscribeGroup`；
- Sync Devices 页面如实显示该节点同步失败；
- Timed 页面保留真实待同步；
- 不清除或伪造失败状态；
- 用户可以从 Timed 或既有重新同步入口再次修复。

### 3.3 工程目标

- 改动限制在同步步骤编排层；
- 复用现有 `Schedule.needsSync`、Owner Policy 和消息构建逻辑；
- 不复制 Scheduler 差异判定；
- 不改变 Mesh 协议；
- 不增加用户可见文案；
- 不引入新依赖；
- 不修改 SDK。

## 4. 非目标

本次不处理：

- 重新设计 Scheduler Owner Policy；
- 修改 `Schedule.needsSync` 或严格 per-Model 判定；
- 修改 Timed 页面的同步图标规则；
- 将 `owner-entry-missing` 隐藏为已同步；
- 修改 SDK Scheduler codec 或权威读取；
- 让 Scheduler 迁移失败阻断退组；
- 为整个 Sync Devices 框架增加事务或回滚机制；
- 重构全部 `deleteSteps` / `configturationSteps` 分类；
- 修改 Group Profile、Scene、Switch、Proximity Lighting 或 Emergency Fire 的业务规则。

## 5. 方案比较

### 5.1 方案 A：退出节点的 `.syncSchedules` 进入 Remove Section

做法：

- 普通节点或加入节点继续把 `.syncSchedules` 放入 `configturationSteps`；
- 正在退出 Group 的节点把 `.syncSchedules` 放入 `deleteSteps`；
- 任务的 `DeviceOperationType` 仍然是 `.configuration(...schedule...)`。

优点：

- 直接修复步骤丢失位置；
- 退出节点仍只有一个 `removeDevice` 模型；
- 复用现有退出节点对 Profile、PIR、Proximity Lighting 的分类模式；
- Schedule 步骤与退组步骤出现在同一 Remove Section；
- 现有退出排序会在 `unsubscribeGroup` 前尝试 Schedule 操作；
- 失败状态自然聚合到退出节点。

代价：

- `deleteSteps` 中会包含一个配置型 Schedule 操作，命名是历史结构，不完全等价于协议 Delete；
- 需要合同测试锁定“退出时归 Remove、普通时归 Configuration”的双分支。

结论：采用。

### 5.2 方案 B：outNodes 同时加入 Configuration Section

做法：

- outNodes 同时消费 `removeDevice` 和 `configturationDevice`。

问题：

- 同一退出节点会同时出现在 Remove 和 Configuration Section；
- Section 顺序可能使最终退组先于 Scheduler 迁移；
- 失败状态、重试入口和 UI 聚合被拆成两个节点模型；
- 会把退出节点的其他配置型步骤一并带入，扩大行为范围。

结论：不采用。

### 5.3 方案 C：退组结束后后台修复 Scheduler

做法：

- 完成退组后再单独扫描 Timed 差异并发送修复消息。

问题：

- 用户看不到完整进度和失败位置；
- 需要额外后台编排与重试状态；
- Timed 或 Group Members 需要承担新的跨页面职责；
- 可能和用户立即进入 Timed 的操作竞争；
- 不能复用当前 Sync Devices 的结果聚合。

结论：不采用。

## 6. 生产代码设计

### 6.1 生产改动点

文件一：

`SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`

新增纯路由策略，将“是否为退组上下文”映射为：

- 退组：Remove Section；
- 非退组：Configuration Section。

同一策略同时声明：退组中的 Schedule Owner 迁移是 best-effort，不应阻止最终 Group removal。该策略不依赖 UIKit、Mesh 或源码文本，可由现有 Swift 聚焦测试直接验证真实返回值。

文件二：

`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

位置：

`getSyncDeviceModel(group:node:effectiveMemberCount:profileSyncContext:)` 的 `.syncSchedules` 分支。

行为：

1. 继续为每个 Schedule 创建 `.configuration(node:type:.schedule(...))` 任务；
2. 继续使用现有 Schedule 消息构建器完成：
   - 可用时发送 `TimeSet`；
   - 清理全部非 Owner Scheduler Model；
   - 向当前 ordinary Owner 写入目标 entry；
3. 创建 Schedule Step 后计算节点是否处于退组流程：
   - `node.groupState == .exitFailure`；
   - 或已经存在 `removeGroupStep`；
4. 将上述布尔值交给纯路由策略；
5. 策略返回 Remove 时加入 `deleteSteps`；
6. 退组 Schedule Owner 迁移同时记录为 non-blocking Group-exit Step；
7. 策略返回 Configuration 时加入 `configturationSteps`；
8. 为 `removeGroupStep` 组装前置依赖时，排除上述 non-blocking Step；其他既有删除步骤仍保持原依赖语义。

### 6.2 为什么操作仍是 Configuration

退出自动 Group 后，直接 Device Target 的定时仍然存在，只是 Owner 从 Light LC 改为 ordinary。

因此该任务必须：

- 删除旧 Light LC Owner 的同 index；
- 写入 ordinary Owner 的原定时 entry。

不能把它变成 Schedule Delete，否则会把仍然有效的直接 Device Target 定时从设备上彻底删除。

### 6.3 执行顺序

现有退出流程会按 `NodeSyncData.level` 降序组织步骤：

- `.syncSchedules` / `.deleteSchedules`：level 4；
- `.unsubscribeGroup`：level 1。

因此：

- Scheduler Owner 迁移和 Group Target Scheduler 删除都会在最终退订前被尝试；
- 两种 Schedule 操作同为 level 4，相对顺序不作为业务前提；
- 两者操作不同的 Schedule index，当前复现场景不存在先后依赖；
- `.syncSchedules` Owner 迁移不会成为 `unsubscribeGroup` 的阻断依赖；
- 既有其他删除步骤的阻断依赖保持不变。

### 6.4 成功数据流

以 L2、L6 为例：

1. 节点进入 `.exitFailure`；
2. id 0、5 被判定为 `deleteSchedules`；
3. id 1、3 被判定为 `syncSchedules`；
4. 两类步骤都进入退出节点的 Remove Section；
5. id 0、5 从 ordinary 和 Light LC Scheduler 清除；
6. id 1、3 从 Light LC Scheduler 清除并写入 ordinary Scheduler；
7. `unsubscribeGroup` 执行；
8. 每条成功的 `SchedulerActionStatus` 按具体 Model 更新 `allSchedulerModelEntrys`；
9. 再进入 Timed：
   - id 0、5 不再以 L2、L6 为目标；
   - id 1、3 在 ordinary Owner 中匹配；
   - Light LC 中没有残留；
   - id 2、4 保持原状态；
   - 六条定时均不因本次退组显示待同步。

### 6.5 失败数据流

如果 id 1 或 id 3 的 Scheduler 迁移失败：

1. 对应 Schedule Step 标记失败；
2. Sync Devices 继续处理后续步骤；
3. `removeGroupStep.relevanceStepModels` 不包含该迁移 Step；
4. `unsubscribeGroup` 仍可执行；
5. 退出节点最终聚合为同步失败；
6. 退组仍完成；
7. per-Model 缓存只反映实际收到成功响应的操作；
8. Timed 继续显示：
   - `owner-entry-missing`；
   - `owner-entry-mismatch`；
   - 或 `cleanup-entry-residual`；
9. 用户后续重新同步时继续使用现有严格差异判定修复。

本次不把失败改成成功，也不清除同步图标。

## 7. 测试设计

### 7.1 RED 行为测试

扩展：

`Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

新增 Group Member Removal Schedule Routing 行为测试，验证：

1. 退组上下文返回 Remove Section；
2. 退组 Schedule Owner 迁移不阻止 Group removal；
3. 非退组上下文返回 Configuration Section。

RED 预期：

- 测试引用尚不存在的路由策略，Swift 编译明确失败；
- 失败原因只能是缺少该生产 API，不能是测试拼写或接线错误。

GREEN 预期：

- 新增纯策略并接入 `.syncSchedules` 后，行为测试通过；
- 既有 Timed Owner、清理和持久化合同保持通过。

控制器接线由编译和聚焦差异复核验证；不使用读取生产源码字符串的测试，避免测试实现细节而非真实行为。

### 7.2 测试脚本

`scripts/check_timed_scheduler_single_owner.sh`

现有脚本已经共同编译 `TimedSchedulerOwnerPolicy.swift` 和
`TimedSchedulerOwnerPolicyTests.swift`，因此无需修改脚本，也不新增测试依赖或 Xcode target。

### 7.3 静态验证

必须执行：

- `scripts/check_timed_scheduler_single_owner.sh`
- `scripts/check_timed_scheduler_persistence.sh`
- `git diff --check`

静态检查必须确认：

- 只修改计划内文件；
- 无本地化、资源、target 或依赖变化；
- SDK 工作区无本次改动；
- 没有无关格式化。

### 7.4 iPhoneOS 构建

`SyncDevicesViewController` 位于共享业务代码，必须分别验证：

1. SunSmart；
2. Archipelago；
3. SLG Sync Plus；
4. SylSmart。

全部使用：

- Debug；
- generic iPhoneOS；
- `CODE_SIGNING_ALLOWED=NO`；
- 直接运行 `xcodebuild`；
- 不使用 Simulator；
- 不使用 shell 包装或日志重定向。

### 7.5 真机验收

#### 成功路径

准备：

- 自动 Profile Group；
- 双 Scheduler 灯具；
- Group Target Turn On：id 0、5；
- Device Target Turn On：id 1、3；
- Device Target Turn Off：id 2、4。

步骤：

1. L2、L6 加入 Group；
2. 确认 Timed 六条均 synchronized；
3. L2、L6 移出 Group；
4. 确认退组日志包含：
   - delete id 0、5；
   - set id 1、3；
   - id 1、3 先清理 Light LC、再写 ordinary；
5. 确认所有相关 Status 成功；
6. 再进入 Timed；
7. 确认六条定时没有由退组引入的待同步；
8. 退出 Space、重进 Space 和 Timed；
9. 杀进程、重启并再次检查；
10. 确认结果保持。

#### 失败路径

通过真实离线节点或可控故障注入使 Scheduler 迁移失败：

1. 确认 Schedule Step 失败；
2. 确认后续 `unsubscribeGroup` 仍执行；
3. 确认节点最终已退出 Group；
4. 确认 Sync Devices 显示失败；
5. 确认 Timed 保留真实待同步；
6. 节点恢复在线后从既有入口重新同步；
7. 确认同步成功后标记消失。

## 8. 验收标准

修复完成必须同时满足：

1. 自动 Profile Group 成功退组后，直接 Device Target 的 `Turn On` 定时迁回 ordinary Scheduler；
2. Group Target 定时从退出节点全部 Scheduler Model 清除；
3. `Turn Off` 定时没有无关消息；
4. 成功退组后 Timed 无新增待同步；
5. 迁移失败不阻止退组；
6. 迁移失败时 Sync Devices 和 Timed 均保持真实失败状态；
7. Manual Control Group 不发生不必要 Owner 迁移；
8. 既有 single-owner、cache persistence 合同通过；
9. 四个品牌 generic iPhoneOS 构建通过；
10. 真机成功、失败和重载生命周期完成验证。

## 9. 文件范围

预计修改：

- `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

预计新增：

- 实施计划 Markdown 文档

明确不修改：

- `SunSmart/Main/Timed/Model/Scheduler.swift`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`
- `SunSmart/Common/Data/Node+MessageHandles.swift`
- `SunSmart/Main/Timed/Controller/TimedViewController.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`
- Localizable strings
- Assets
- Xcode target 配置
- 依赖配置

## 10. 风险与控制

### 风险 1：错误地删除直接 Device Target 定时

控制：

- `.syncSchedules` 保持 configuration operation；
- 既有 single-owner 合同继续锁定 Schedule configuration operation；
- 真机检查 id 1、3 最终存在于 ordinary Scheduler。

### 风险 2：普通同步被错误放入 Remove Section

控制：

- 仅在 `.exitFailure` 或存在 `removeGroupStep` 时进入 `deleteSteps`；
- 纯策略行为测试要求非退组上下文返回 Configuration。

### 风险 3：Scheduler 失败意外阻断退组

控制：

- 退组 Owner 迁移 Step 被显式记录为 non-blocking；
- 组装 `removeGroupStep.relevanceStepModels` 时排除该 Step；
- 其他既有删除依赖不受影响；
- 失败路径真机验证必须确认 `unsubscribeGroup` 继续执行。

### 风险 4：隐藏真实同步失败

控制：

- 不修改 `Schedule.needsSync`；
- 不修改 Timed 图标判定；
- 不回退到扁平 `schedulerActions`；
- 失败时保留 per-Model 真值。

### 风险 5：共享代码影响其他品牌

控制：

- 四个品牌 target 分别执行 generic iPhoneOS 构建；
- 不改本地化、资源、target 和依赖。

## 11. 实施边界

本设计以最小改动修复已确认的编排缺口：

> 退出节点仍可能需要执行配置型 Scheduler Owner 迁移，这类任务必须参与 Remove Section，但失败不阻止用户完成退组。

如果实施过程中发现必须修改 Owner 解析、SDK、Timed 判定或整个 Sync Devices 事务语义，应停止实施并重新确认范围，不得顺手扩大修复。
