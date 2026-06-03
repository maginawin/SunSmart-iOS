# Group Schedule Orphan 分析与修复计划

## 背景

问题描述：设备在 group 内时，添加了以 group 为目标的日程；随后将设备从 group 中移除，但该日程仍然在设备上生效。

本次只做问题真实性分析和修复开发计划，不修改业务代码。

## 结论

问题真实存在，或至少存在明确的代码缺口。

现有设计里，group 日程不是只保存为“group 目标”，而是会下发为每个目标节点上的 `SchedulerActionSet`。因此，设备从 group 移出后，如果节点上已有的 SchedulerAction 没有被删除，日程仍会由设备本地 Scheduler model 执行。

代码中已经存在“移出 group 时删除日程”的设计意图，但删除判断依赖 `groupState == .exitFailure`、`schedule.needDeleteGroups` 或 `schedule.needDeleteNodes`。如果节点已经不再属于 group，且没有处于这些显式待删除状态，就可能留下孤儿日程。

## 证据

- `Schedule.getMessageHandles(node:delete:)` 在设置日程时会向节点写入 `SchedulerActionSet`，删除时用空 `SchedulerRegistryEntry` 清除对应 index。位置：`SunSmart/Common/Data/Node+MessageHandles.swift`。
- group 成员编辑页在移除节点时会把节点设置为 `.exitFailure`，并进入 `SyncDevicesViewController(type: .group(..., outNodes: exitNodes))` 同步。位置：`SunSmart/Main/Group/Controller/GroupMembersViewController.swift`。
- `SyncDevicesViewController` 对退出 group 的流程会把删除日程、删除场景、退订 group 放到 remove section，并通过依赖保证退订 group 在其他删除任务之后执行。位置：`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`。
- `Node.getNodeNeedDeleteSchedules(group:schedule:)` 当前只在以下条件下返回待删除日程：
  - 设备不再被该日程直接或间接绑定；
  - 且设备在 `needDeleteNodes` 中，或传入 group 且满足 `.exitFailure` / `needDeleteGroups` / `needDeleteScenes`。
- 上述判断没有覆盖“节点缓存仍有 `schedulerActions[schedule.id]`，但当前不再属于该 group 日程目标”的孤儿状态。

## 影响范围

主要影响普通 schedule 目标为 group 的场景：

- group 日程已成功下发到组内设备；
- 后续设备被移出 group；
- 由于同步失败、状态恢复、数据导入、重试、或某些入口没有保留 `.exitFailure` 上下文，节点仍保留旧 schedule action；
- 到点后设备仍执行旧日程。

间接影响：

- 以 scene 为目标的日程也可能通过 scene 的 group 产生类似孤儿 schedule；
- profile 日程和 dongle collection schedule 是不同路径，不建议放在同一轮修复中混改。

## 修复方案对比

### 方案 A：只在移出 group 的 UI 流程强制追加删除任务

在 `GroupMembersViewController` 或 `SyncDevicesViewController` 中，根据 outNodes 和 group 的当前绑定日程直接补充删除任务。

优点：改动小，容易对准用户描述路径。

缺点：只修一个入口；后续 restore、导入、重新同步、自动检测等路径仍可能留下孤儿日程。

### 方案 B：增强 `getNodeNeedDeleteSchedules` 的孤儿日程识别

在节点同步数据的统一判断中增加规则：如果节点存在某个 schedule action，但该节点已经不属于该 schedule 的直接目标、group 目标或 scene 目标，则该 schedule 应返回为待删除项。

优点：修复点位于统一同步判断，覆盖设备页同步、group 同步、schedule 同步、restore 后重试等路径；符合现有架构。

缺点：需要谨慎避免误删直接绑定到设备的日程，尤其是同一 schedule 同时存在 node/group/scene 间接关系变化时。

### 方案 C：新增 schedule membership 快照

记录每个 schedule 曾经下发到哪些节点，移组时按快照删除。

优点：最精确，能明确知道哪些节点曾经被下发过。

缺点：需要新增持久化字段和迁移逻辑，复杂度高，不适合当前缺口的首轮修复。

## 推荐方案

推荐采用方案 B，并只增加普通 schedule 的 orphan 检测，不引入新持久化结构。

核心规则：

1. 节点必须支持 Scheduler model。
2. 节点本地必须存在 `schedulerActions[schedule.id]`，且该 entry 有效或至少存在。
3. 当前 schedule 不再直接绑定该节点，也不再通过当前有效 group 或 scene group 绑定该节点。
4. 满足以上条件时，将该 schedule 作为待删除项返回。
5. 保留现有 `.exitFailure`、`needDeleteNodes`、`needDeleteGroups`、`needDeleteScenes` 逻辑，避免破坏原有待删除状态清理。

## 开发计划

1. 在 `Node+SyncData.swift` 为 `getNodeNeedDeleteSchedules(group:schedule:)` 增加清晰的 membership 判断辅助逻辑。
2. 将现有 `isBindNode` 判断拆成“当前是否应保留该日程”和“是否处于显式待删除状态”两个概念。
3. 增加 orphan 条件：节点有本地 schedule action，但当前 schedule 目标集合已不包含该节点。
4. 确保直接设备目标的 schedule 不会被 group 移除误删。
5. 确保 scene 目标 schedule 在节点仍属于 scene 关联 group 时不会误删。
6. 检查 `Schedule.getNeedSyncDatas()` 是否也需要同样孤儿识别；如果 schedule 编辑页依赖它，应同步更新，避免只在 group 同步页修复。
7. 增加或更新最小单元测试。如果项目现有测试难以覆盖 NordicSigMeshSDK 对象，可优先补充一个小的纯判断函数测试，或记录手测用例。
8. 用推荐 iOS 构建命令验证 `SunSmart` target 编译。

## 当前 App 中如何发现这个问题

### 直接发现路径

当前 App 最直接的发现方式是在“设备移出 group 后的同步流程”中观察同步任务列表。

操作路径：

1. 在 Timed/Schedule 中创建一个以 group G 为目标的 enabled schedule。
2. 确认设备 A 属于 group G，并完成 schedule 同步。
3. 进入 group G 的成员编辑页，把设备 A 从 group G 中移除。
4. 保存后进入 `SyncDevicesViewController(type: .group(..., outNodes: ...))`。
5. 正常情况下，设备 A 的 remove section 应包含 `remove_schedule`，并且该步骤应在 `remove_from_group` 前完成。
6. 如果同步页只出现 `remove_from_group`，没有 `remove_schedule`，则说明当前 App 没有识别到该设备上的 group schedule 残留，这就是问题的直接信号。

### 事后发现路径

如果用户已经完成移组并离开同步页，可以通过以下方式发现：

1. 等到原 group schedule 的触发时间。
2. 观察已经移出 group G 的设备 A 是否仍执行该 schedule 的动作。
3. 如果 A 仍执行，而该 schedule 没有直接选择设备 A，则问题成立。

也可以进入 schedule 编辑页检查同步提示：

- `ScheduleAddView` 顶部有 `devices_not_synced` 提示按钮，点击后进入对应 schedule 的同步页。
- 目标选择弹窗中，group cell 或 device cell 也会显示 sync failed 图标。
- 这些提示依赖 `schedule.getNeedSyncDatas()`、`group.getNeedSyncScheduleDataNodes(_:)` 等同步差异计算。

### 当前 App 的盲区

当前 App 可能发现不了这个问题，原因是 UI 提示也依赖同一套同步差异判断。

如果孤儿 schedule 没有被 `getNodeNeedDeleteSchedules(group:schedule:)` 或 `Schedule.getNeedSyncDatas()` 识别，那么：

- Schedule 编辑页的 `devices_not_synced` 可能不会显示；
- group/device target 选择页的 sync failed 图标可能不会显示；
- 设备列表或 group 页面上的 sync failed 入口也可能不会出现；
- 用户最终只能通过“移出 group 的设备到点仍执行日程”发现问题。

因此修复时不能只让同步页补一个删除步骤，还需要让 `needSync` / schedule diff 数据源能识别 orphan schedule，这样当前 App 的同步提示才能把问题暴露出来并允许用户重试修复。

## 新增 group member 是否会同步关联日程

当前代码已有“新增 group 成员后同步关联日程给新成员”的逻辑，暂未发现与移出成员同级别的缺口。

主要链路：

1. `GroupMembersViewController.saveAction()` 会计算 `addNodes`，并把新增节点标记为 `.inGroup`，随后进入 `SyncDevicesViewController(type: .group(self.group, inNodes: addNodes, outNodes: exitNodes))`。
2. `SyncDevicesViewController.setupDataSource()` 会遍历 `inNodes`，对每个新增节点调用 `getSyncDeviceModel(group:node:effectiveMemberCount:profileSyncContext:)`。
3. `getSyncDeviceModel` 内部调用 `node.getSyncData(type: .group(group, ...))`。
4. `Node.getNodeSyncSchedules(group:schedule:)` 会判断：
   - schedule 直接选择该 node；或
   - schedule 选择了该 group；或
   - schedule 选择的 scene 关联了该 group。
5. 如果新成员没有对应 `schedulerActions[schedule.id]`，或本地 entry 与 schedule 不一致，就返回 `.syncSchedules`。
6. `SyncDevicesViewController` 会把 `.syncSchedules` 转成 configuration section 的 `schedule` 步骤，并且该步骤依赖 `add_to_group` 完成后再执行。

因此，新增 group member 时，当前 App 理论上会把以下日程同步给新成员：

- 直接以该 group 为目标的 schedule；
- 以 scene 为目标，且该 scene 关联了该 group 的 schedule；
- 直接以该设备为目标的 schedule。

新增成员路径仍需要纳入回归验证，但不是本次主要修复点。若实测发现新增成员没有 schedule 步骤，优先检查：

- 新成员是否支持 `schedulerSetupModel`；
- 该 group 是否确实存在于 `schedule.groupAddresses` 或 `schedule.scene?.info.groups`；
- `node.schedulerActions[schedule.id]` 是否已经存在且与目标 entry 一致；
- `add_to_group` 是否失败，导致后续 schedule 步骤因依赖未执行。

## 实现结果

已按推荐方案实现。

改动点：

- 在 `Schedule` 上新增统一判断：
  - `targets(node:contextGroup:)`：判断当前日程是否应该作用到节点；
  - `needsSync(on:contextGroup:)`：判断节点是否需要下发/更新日程；
  - `needsDelete(from:contextGroup:)`：判断节点是否存在应删除的日程。
- `Node.getNodeSyncSchedules(group:schedule:)` 和 `Node.getNodeNeedDeleteSchedules(group:schedule:)` 改为使用统一判断。
- `Schedule.getNeedSyncDatas()` 增加 orphan schedule 删除识别：节点本地存在 schedule action，但当前 schedule 不再通过设备、group 或 scene group 目标覆盖该节点时，会进入删除数据。
- `Group.getNeedSyncScheduleDataNodes(_:)` 改为使用统一判断，同时避免原有 force unwrap 风险。
- `ScheduleScenesView` 的 sync failed 图标判断改为同时识别需要同步和需要删除的 schedule。

实现语义：

- 设备从 group 移出后，仅因该 group 或该 group 所属 scene 下发的 schedule 会被识别为待删除。
- 直接选择该设备的 schedule 会被保留。
- 新增 group member 时，仍会通过 `contextGroup` 识别 group / scene schedule，并在 `add_to_group` 后同步给新成员。

## 验证用例

### 手动验证

1. 创建设备 A 和 group G。
2. 将设备 A 加入 group G。
3. 创建以 group G 为目标的 enabled schedule。
4. 确认设备 A 的 `schedulerActions` 中有该 schedule id。
5. 将设备 A 从 group G 移除并执行同步。
6. 确认同步列表包含 remove schedule，且在 remove from group 前完成。
7. 确认设备 A 的 `schedulerActions` 中不再有该 schedule id。
8. 到日程时间点确认设备 A 不再执行。

### 回归验证

- 设备仍留在 group 内时，group schedule 不应被删除。
- schedule 直接选择设备 A 时，即使 A 被移出 group，也不应删除该 schedule。
- scene schedule 中，如果 A 仍属于 scene 关联 group，不应删除。
- 同步失败后重试，应仍能识别并删除孤儿 schedule。
- 向已有 group schedule 的 group 新增设备 B，SyncDevices 页面应出现 B 的 `schedule` 配置步骤，且 B 同步完成后应按该 group schedule 执行。
- 向已有 scene schedule 的 group 新增设备 B，如果该 group 属于 scene 目标，B 也应获得对应 schedule。

### 构建验证

已运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

结果：构建通过。构建日志仍有既有资源警告，包括 duplicate build file、asset symbol 重名和 Bad.imageset 重名；本次未修改这些资源或 target 配置。

## 风险与注意事项

- `schedulerActions` 可能包含无效 entry；删除判断应明确处理“存在但无效”的情况，避免重复生成无意义任务。
- `Schedule.getMessageHandles(delete:)` 对 action 为 `.turnOn` 且 `node.group != nil` 时使用 Light LC Scheduler model；如果节点已经离组，删除路径可能改用普通 Scheduler model。需要确认硬件协议上旧 entry 实际写入的是哪个 model，必要时删除时同时考虑旧 group 上下文。
- 不要扩大到 collection schedule、profile、dongle 路径，避免无关行为变化。

## 待确认问题

修复默认语义建议为：设备从 group 移出后，所有仅因该 group 或该 group 所属 scene 下发到设备的日程都必须删除；直接选择该设备的日程保留。

如果产品期望“移出 group 后仍保留设备已收到的历史日程”，则当前行为是设计选择，但这与现有删除逻辑和用户问题描述不一致。
