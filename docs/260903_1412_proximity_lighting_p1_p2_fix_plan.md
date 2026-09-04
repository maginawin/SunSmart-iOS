# 邻近照明 P1 / P2 完整修复计划

## 1. 目标与范围

本计划覆盖上一轮分析识别的全部 P1、P2 问题，目标是让以下四层状态在所有邻近照明操作中保持可解释、可恢复和最终一致：

1. App 逻辑拓扑：Group Sequence、Group Trigger Zone、Space Trigger Zone。
2. 本地持久化：GroupInfo、SpaceData、Node 已观测邻近状态。
3. 云端快照：导出、上传、下载、导入、旧新版本兼容和并发覆盖。
4. 真实设备：Enabled、Relay Number、Neighbors 的 Mesh 同步与失败重试。

本轮文档只规划，不修改运行代码。实现时保持改动聚焦，不改 Auth，不顺手重构其他业务。

## 2. 已冻结的修复语义

### 2.1 Profile 降级采用删除语义

推荐并在本计划中默认采用：Group Profile 从 `proximityLighting` 或 `proximityLightingWithPhotocell` 变为非邻近类型时：

- 删除该 Group 的 `proximityLightingPath`，包括 Sequence 和 Group Trigger Zone。
- 删除所有 Space Trigger Zone 中属于该 Group 的成员项。
- 保留 Sequence/Zone 容器的规则仅适用于成员或 Node 被移除；Profile 降级直接删除整个 Group 邻近拓扑。
- 再次改回邻近 Profile 时从空拓扑开始，不静默恢复历史关系。

原因是当前模型没有“暂停/归档”状态。保留旧数据会让重新启用 Profile 时无提示恢复关系。如果产品要求保留，应另行设计显式归档状态、云 Schema 和恢复确认，不应作为本次修复的隐式行为。

### 2.2 逻辑状态先于设备状态

除 Group 删除外，用户确认修改后先持久化新的期望拓扑并写入 Cloud Dirty，再执行 Mesh 同步：

- 同步成功：Node 已观测状态更新并再次上传。
- 同步部分失败：期望拓扑不回滚，失败设备继续显示为待同步。
- App 中断：Cloud Dirty 和 Node/目标差异可在下次进入时恢复。

Group 删除属于不可逆操作，只有原 Group 设备退出以及跨 Group 邻居更新全部成功后，才真正移除 Group 和其扩展数据。

### 2.3 不静默裁剪有业务含义的超限数据

- 无效 Group、无效 Node、错误成员归属等悬空引用可以自动清理。
- 同一 Zone 内完全重复的成员可以保留首次出现并删除后续重复项。
- Sequence 中重复出现的 Node、跨 Sequence/Zone 重复使用的 Node 继续允许，因为现有 UI 支持 Show Added Devices。
- 超过 32 条 Sequence、单 Sequence 超过 200 个 Point、超过 32 个 Group/Space Zone、单设备最终邻居超过 184 个属于硬错误，不静默截断。
- 云导入遇到硬错误时，在应用服务器快照前失败并保留本地最后正确数据。

### 2.4 云导入不在后台静默控制灯具

- 服务器快照导入完成后必须计算明确的待同步设备集合。
- 用户主动刷新/导入且当前 Space 可编辑、Mesh 已连接时，可进入自动启动的 Sync Device(s) 页面。
- 后台更新、首次加载、只读用户或 Mesh 未连接时，不自动发送 Mesh 命令；保留并展示 Devices not synced，等待用户进入可控同步流程。

## 3. 修复后的统一数据流

每次可能改变邻近关系的操作都走同一条流程：

1. 从当前 Space、全部 Group、Group 成员和 Node 缓存生成旧拓扑快照。
2. 在副本上应用 Profile、成员、Group、Node、地址或页面编辑变化。
3. 规范化引用并执行容量、成员归属和 Profile 资格校验。
4. 生成新拓扑 Plan。
5. 比较旧、新 Plan，并结合 Node 当前已观测状态生成完整待同步集合。
6. 按操作类型持久化期望状态，先写 Cloud Dirty，再保存 GroupInfo/SpaceData。
7. 清除所有受影响 Node 的同步状态缓存。
8. 立即排队上传新的逻辑拓扑；Mesh 同步结束后再上传最新 Node 已观测状态。
9. 同步失败保持在待同步状态，不通过 HTTP 200 或局部 ACK 宣告整体完成。

待同步集合不能只包含“本次编辑地址”，应覆盖新拓扑下整个 Space 的未同步邻近设备：

- 候选地址至少为旧 Plan targets、新 Plan targets、规范化清理涉及的 Group 成员三者并集。
- 已永久删除的 Node 不发送消息。
- 仍存在的旧成员可得到 Disable。
- Space Trigger Zone 的其他 Group 对端必须进入 Neighbor Set 更新。
- 对每台候选设备继续复用现有 `ProximityLightingTopologyPolicy.mutation` 生成最小必要任务。

## 4. 核心领域层设计

### 4.1 新增纯值拓扑协调策略

新增 `SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift`，只依赖 Foundation，不直接访问 UIKit、数据库、Cloud Manager 或 NordicSigMeshSDK 运行对象。

职责：

- 表达包含所有 Group 的原始拓扑快照，不能像当前 Plan 一样提前丢弃非邻近 Group，否则无法发现和清理历史数据。
- 接收变更原因：Profile 变化、成员变化、Group 删除、Node 删除、地址迁移、Group Path 编辑、Space Zone 编辑、云导入、启动迁移。
- 规范化 Group Sequence、Group Trigger Zone 和 Space Trigger Zone。
- 生成规范化结果、硬错误、自动修复记录、旧/新目标差异和候选设备地址。
- 保证输出顺序稳定，便于持久化、云 JSON 和测试比较。

建议的纯值结果包含：

- 规范化后的每个 Group Path。
- 规范化后的 Space Zones。
- 旧 Plan 和新 Plan。
- 目标发生变化的地址。
- 完整候选地址。
- 自动删除的引用及原因统计。
- 容量、Profile 数值和归属冲突等硬错误。

### 4.2 新增 App 模型适配协调器

新增 `SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift`，负责将真实 `SpaceData`、`Group`、`Node` 转换为纯值快照，并把 Reconciler 结果应用回 App 模型。

职责边界：

- 捕获快照、构建 Draft、调用纯值策略。
- 将 Node 统一映射到 Sunricher Vendor Model 所在 Element 地址；永久删除时同时记录 Node 的全部 Element 地址，确保异常导入的非标准地址也能被清理。
- 在主线程或同一串行上下文中读取和写入 MeshNetworkManager 共享模型；纯值计算可离开主线程。
- 先调用 `space.markLocalChangePendingCloudSync()`，再保存受影响 GroupInfo 和 SpaceData。
- 清除旧/新候选 Node 的 `cacheGroupNeedSync` 与 `cacheNeedSync`。
- 为仍存在且支持 Sunricher Vendor Model 的 Node 生成预计算 `NodeSyncData`。
- 返回生命周期结果，不直接 present UI。

生命周期结果至少包含：

- 是否发生逻辑变化。
- 受影响 Group 与设备地址。
- 完整的邻近照明同步任务。
- 是否需要 `.device` 或 `.network(.address)` 云提交。
- 规范化警告和硬错误。

### 4.3 扩展现有 Planner 而不是复制拓扑算法

保留 `ProximityLightingTopologyPolicy.makePlan` 为唯一目标拓扑计算器，并补齐：

- 完整成员覆盖，而不仅是 `additionalGroupMembers`。
- Profile/Relay Number 覆盖。
- 排除待删除 Group。
- Group Path 和 Space Zone 覆盖。
- 旧、新 Plan target 差异计算。

所有 UI 页面、生命周期操作、导入后检查都使用相同 Planner/Reconciler，不再各自编译邻居集合。

### 4.4 共用同步任务呈现

在 `SyncDevicesViewController` 中提取 Group Path 与 Space Trigger Zone 两段重复的邻近任务构建逻辑，支持一个通用的预计算邻近任务来源。

Group Profile/成员编辑需要在现有 `.group` 同步之外附加跨 Group 邻近任务：

- 同 Group Node 已由 Group 同步生成的邻近任务不重复添加。
- 其他 Group 对端作为补充设备加入同一个 Sync Device(s) 页面。
- Disable、Relay Number、Neighbor Set 继续使用现有任务和 ACK 更新逻辑。
- SAVE 创建的页面默认自动开始；红色 Re-sync 入口维持等待用户操作。

Node 删除或云导入只有邻近任务时，使用统一的全 Space 邻近同步类型，不再用页面名称决定业务算法。

## 5. P1 实施任务

### P1-1：先建立 RED 测试和统一策略

修改/新增：

- `SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift`
- 新增 `SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift`
- `Tests/Group/ProximityLightingTopologyPolicyTests.swift`
- 新增 `Tests/Group/ProximityLightingLifecyclePolicyTests.swift`
- `scripts/check_path_topology_persistence.sh`

先增加会在当前实现失败的用例：

- Profile 邻近 → 非邻近。
- 成员移除同时影响 Group Path、Group Zone、Space Zone。
- Group 删除影响 Space Zone 对端。
- Node 删除清理所有匹配地址，而不是首次匹配。
- 两个 Group 的 Space Zone 关系变化产生双方任务。
- 邻近 Profile Relay Number 变化。
- 非邻近 → 邻近不会恢复已删除的旧拓扑。
- 已有历史悬空数据的启动规范化。

通过条件：先证明旧实现 RED，再完成纯策略 GREEN；纯策略测试不依赖 UIKit 或真实 Mesh。

### P1-2：接入 Group Path / Space Zone 直接 SAVE

修改：

- `GroupPathSequencePageController.swift`
- `SpacePathTriggerZoneController.swift`
- `Node+SyncData.swift`
- `SyncDevicesViewController.swift`

目标：

- 将当前两个已经基本正确的 SAVE 入口迁移到 Coordinator，作为统一流程的首批调用方。
- 保留现有容量提示、Cloud Dirty、无任务退出、同步失败停留和自动 `startSync()` 行为。
- 页面顶部 Devices not synced 与 SAVE 使用同一完整待同步集合。
- 避免后续生命周期入口与直接 SAVE 使用两套算法。

通过条件：现有三组 Path/Trigger Zone 聚焦测试不回归；新协调器输出与当前正确场景一致。

### P1-3：修复 Profile 更新与降级

修改：

- `ProfileSettingsViewController.swift`
- `GroupViewController.swift`
- `GroupProximityLightingData.swift`
- `SyncDevicesViewController.swift`

流程：

1. 保存前以旧 Profile 构建旧快照，以待保存 Profile 构建 Draft。
2. 两个邻近类型之间切换时保留拓扑；Relay Number 变化生成最小任务。
3. 邻近类型降级时将 Group Path 设为 `nil`，从所有 Space Zones 删除该 Group 项。
4. 先标记 Cloud Dirty，再保存 Profile、GroupInfo 和 SpaceData。
5. 当前 Group 继续执行完整 Profile 同步；跨 Group 对端追加到同一同步页。
6. 即使当前 Group 为空，只要跨 Group 有待同步设备也必须进入同步页。

需要调整 Profile 保存回调，让领域保存结果能够返回给 Profile 页面，而不是只有无返回值的 UI callback。

通过条件：降级后本地与导出 JSON 都不包含该 Group 的邻近拓扑，当前 Group 设备 Disable，跨组对端邻居移除；重新启用从空拓扑开始。

### P1-4：修复 Group 成员新增/移除

修改：

- `GroupMembersViewController.swift`
- `GroupProximityLightingData.swift`
- `SyncDevicesViewController.swift`

流程：

1. 在修改 `groupState` 前构建旧快照。
2. 使用完整成员覆盖生成 Draft，不再依赖只支持新增的 `additionalGroupMembers`。
3. 对退出 Node：Sequence 所有匹配 Point 置空；Group Zone 删除所有匹配地址；Space Zone 删除全部匹配 `(groupAddress, deviceAddress)`。
4. 保留空 Sequence Point 和空 Zone 容器，避免破坏现有页面布局语义。
5. 在任何本地修改前完成 Mesh 连接检查，修复当前“先改本地、后发现断连”的窗口。
6. 持久化后进入包含退出、加入、同组剩余成员及跨组对端的统一同步页。

通过条件：无论 Group 当前是否已降级，都不会留下退出 Node 引用；跨组对端能更新；中途失败后重进页面仍显示完整待同步集合。

### P1-5：修复 Group 删除和两个入口差异

修改：

- `GroupServer.swift`
- `GroupsViewController.swift`
- `GroupViewController.swift`
- `MeshNetwork+SunSmart.swift`

特殊两阶段流程：

1. 删除前构建“排除目标 Group、并清理 Space Zone”的新 Plan，但暂不删除 Group。
2. 原 Group Node 依次执行邻近 Disable、其他 Group 清理任务、Unsubscribe。
3. Space Zone 其他 Group 对端执行新 Neighbor Set。
4. 所有必要设备成功后，才移除 Mesh Group、删除 GroupInfo/Profile 扩展、保存清理后的 Space Zones并提交 Cloud Dirty。
5. 任一设备失败则保留 Group 与旧逻辑拓扑，进入统一重试流程；已成功设备的缓存会让重试准确生成差异。
6. 本地 Provisioner 对 Group 的取消订阅延后到最终提交，避免删除失败时本地订阅已经丢失。
7. Group 列表和 Group 详情统一调用同一个领域删除入口，UI 只负责刷新/关闭，不再分别决定云提交。

通过条件：两个入口产生相同本地、Mesh 和云结果；空 Group 但存在 Space Zone 对端时也会先处理对端；删除失败不会留下半删除的 Group 数据。

### P1-6：修复单个、批量和强制 Node 删除

修改：

- `DevicePermanentDeletionCleanup.swift`
- `DeviceLightViewController.swift`
- `DeviceLightsViewController.swift`
- `DeviceProtocol.swift`
- `DeviceDongleViewController.swift`
- 通过 `DeviceProtocol` 复用删除的 Emergency Fire 入口

流程：

1. `DevicePermanentDeletionContext` 初始化时捕获旧拓扑、Vendor Element 地址和全部 Element 地址。
2. Reset 成功或用户确认 Force Delete 后，删除 Group Sequence、Group Zone、Space Zone 中所有属于该 Node 的引用。
3. 先标记 Cloud Dirty，再保存所有 GroupInfo/SpaceData，然后删除 Node 扩展。
4. 删除的 Node 不再发送邻近任务；所有关系另一端设备生成新 Neighbor Set。
5. 批量删除合并多个 Context 的结果，只显示一次同步页并去重设备任务。
6. Mesh 未连接的 Force Delete 仍完成逻辑清理和云提交，其他设备保留为 Devices not synced，连接恢复后可重试。
7. Node 地址回收后不会因为旧引用把邻近关系绑定到新设备。

`DevicePermanentDeletionContext.commit()` 需要返回生命周期结果；现有无邻近能力的 Dongle 路径得到空结果并保持原行为。

通过条件：删除完成后本地数据库、导出 JSON、其他 Group 页面均找不到旧 Node 引用；跨组对端任务完整。

### P1-7：统一 Node 地址恢复/迁移

修改：

- `GroupProximityLightingData.swift`
- `DeviceRestoreViewController.swift`

流程：

- 用 Coordinator 替代当前单独遍历 Group/Space 引用的方法。
- 替换所有匹配地址并再次校验新 Node 的 Group 归属。
- 用旧、新 Plan 并集同步恢复 Node 及关系另一端设备。
- 将补充任务并入现有 Device Restore 同步页面，不再留给未定义的“外部同步流程”。
- Cloud Dirty 仍在 GroupInfo/SpaceData 保存前写入。

通过条件：地址迁移后无旧地址，恢复 Node 与所有邻近对端在同一恢复流程中达到一致；失败可重试。

### P1-8：修复历史遗留数据

修改：

- `SpaceViewController.swift`
- `GroupProximityLightingData.swift`
- 新 Coordinator/Reconciler

每次进入 Space 时执行幂等、低成本规范化：

- 非邻近 Group 的历史 Path 设为 `nil`。
- Group Path 中不存在或不属于该 Group 的 Node 引用被清理。
- Space Zone 中无效 Group、非邻近 Group、错误成员归属或不存在 Node 被清理。
- 只删除同一 Zone 内完全重复的成员，不删除合法跨 Zone/Sequence 复用。
- 若有变化，先标记 Cloud Dirty，再保存并生成待同步集合。

限制：若历史悬空地址已经被新 Node 复用且新 Node 同时满足当前 Group 归属，单凭地址无法恢复原始身份。这类既有数据只能通过服务器历史、设备 UUID 或人工核对处理；本修复可保证后续删除不再产生该问题。

## 6. P2 实施任务

### P2-1：将 Space 导入改为解析、校验、应用三阶段

修改：

- `ImportData.swift`
- 新增 `SunSmart/Common/Data/ProximityLightingImportPolicy.swift`，或将纯规则放入 Reconciler
- `SpaceTriggerZone.swift`
- `GroupProximityLightingData.swift`

当前 `SpaceData.update` 会直接清除并重建 Mesh 数据。修复后必须在破坏本地状态之前完成：

1. Parse：将服务器 JSON 解码到隔离的导入快照，不写真实 MeshNetwork。
2. Validate/Normalize：检查字段、Profile、成员归属、地址、容量、Relay Number 和最终 184 邻居限制。
3. Apply：只有没有硬错误时才替换真实网络并保存规范化结果。

验证规则：

- Group/Node 必须属于当前 Space/subnetwork。
- Sequence 地址必须为 0 或有效单播地址；有效地址必须解析到当前 Group 成员。
- Group Zone 地址必须属于当前 Group。
- Space Zone 项必须同时匹配存在的邻近 Group 和其成员。
- Group/Space Zone 内重复项按首次出现去重。
- Sequence 重复和跨容器复用不误删。
- Path/Zone 数量、Point 数量及 184 Neighbor 限制严格校验。
- `proximityLightingNumber` 只接受 0...20 或 255；非法值作为硬错误，不使用静默默认值覆盖。

`SpaceData.update` 应返回可忽略的 `SpaceImportOutcome`，包含是否应用、自动修复报告、硬错误和导入后的待同步集合。现有后台调用可忽略 UI 呈现，但当前 Space 控制器必须消费结果。

### P2-2：修复缺失字段、空数组和版本语义

App 的新 Space JSON 增加独立的 `proximityLightingSchemaVersion`，初始版本为 1：

- version 1 必须显式包含 `triggerZones`，空数组表示明确清空。
- version 1 Group 为非邻近 Profile 时不得携带 `proximityLightingPath`。
- version 1 缺少必需字段时拒绝邻近拓扑快照，不把它解释为空。
- 未携带 version 的旧快照：更新已存在 Space 时保留本地 `triggerZones`；首次导入的新 Space 才使用空数组。

该兼容规则必须在服务端能力上线后启用。否则旧客户端仍可能先在服务器上丢失字段，新客户端只能保护已有本地副本，不能恢复服务器已丢失的数据。

### P2-3：导出和上传前增加防御性规范化

修改：

- `ExportData.swift`
- `CloudSynchronizationManager.swift`
- `NetowrkReqeustApi.swift`

目标：

- 自动云上传和文件导出使用同一个规范化快照。
- 非邻近 Group 不导出 `proximityLightingPath`。
- `triggerZones` 永远显式导出，包括空数组。
- 不存在、错误归属和无资格 Group 的引用不能进入请求体。
- 导出时发现硬错误要让上传失败并保留 Cloud Dirty，不返回看似成功的不完整 payload。
- 自动清理的历史悬空数据需要写回本地，并由 owner/editor 上传修复后的快照。
- Node 的 Enabled、Relay Number、Neighbors 保持“已观测状态”语义，不能在导出时用目标值伪造成功。

上传逻辑状态和设备状态分两次或由 Cloud Manager 合并排队均可，但必须保证：逻辑拓扑保存后即使 Mesh 失败也能上传；每次 Mesh ACK 改变 Node 已观测状态后再次排队上传。

### P2-4：导入后生成并呈现设备收敛状态

修改：

- `ImportData.swift`
- `SiteViewController.swift`
- `SpaceViewController.swift`
- `SyncDevicesViewController.swift`

导入成功后：

- 用规范化新 Plan 和导入的 Node 已观测状态计算完整待同步集合。
- 清除候选 Node 的同步判断缓存。
- 主动前台更新按 2.4 的规则进入或提示 Sync Device(s)。
- 后台/只读/离线状态不自动发 Mesh，但下次进入 Space 时可重建同一待同步集合。
- 导入逻辑成功、设备全部同步成功分别记录和展示，禁止用云下载成功代替设备成功。

不新增一套独立的“假成功缓存”；待同步状态始终由持久化目标拓扑与 Node 已观测状态比较得到，App 重启后仍能重建。

### P2-5：服务端兼容和并发契约

此任务不在当前 iOS 仓库内，但属于 P2 完成条件。接口范围：

- `/sitespace/sync/spaceprops`
- `/sitespace/get/spaceprops`

先使用隔离测试 Space 做黑盒验证：

- 字段缺失与空数组是合并还是整体替换。
- 未知字段是否原样保留。
- 相同/更旧 `updateTimestamp` 上传是否被拒绝。
- 两台客户端并发上传时是最后写入覆盖还是存在版本冲突。

若现网没有足够保护，服务端按以下契约修改：

- 无 `proximityLightingSchemaVersion` 的旧客户端上传不得删除服务器已有 `triggerZones`。
- version 1 请求的 `triggerZones` 为权威字段，空数组可清空，缺失字段拒绝。
- GET 原样返回 version、Group Path 和 Space Zones。
- 使用服务器 revision 或等效条件写入；客户端上传携带 base revision，过期写入返回冲突，不静默覆盖。
- 冲突后客户端先下载最新快照，再按整个邻近拓扑进行显式选择/重试；不按数组下标盲目合并 Sequence/Zone。

发布顺序必须是服务端向前兼容规则先上线，再发布携带 version 1 的 App。

### P2-6：云端纠错与可观测性

为不含隐私和 Auth 的诊断增加结构化计数：

- 自动删除的无效 Group、Node、成员引用数量。
- 导入硬错误类型、路径数量、Zone 数量、最大邻居数。
- 导入后待同步设备数、成功数、失败数。
- 上传的 schema version 和 topology 摘要，不打印 Key、设备密钥或完整用户数据。

日志只用于诊断，不能代替 UI 失败状态或自动化断言。

## 7. 文件与 Target 影响

### 新增共享文件

- `SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift`
- `SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift`
- 可能新增 `SunSmart/Common/Data/ProximityLightingImportPolicy.swift`
- `Tests/Group/ProximityLightingLifecyclePolicyTests.swift`
- `Tests/Group/ProximityLightingLifecycleContractTests.swift`
- `Tests/Group/ProximityLightingCloudImportPolicyTests.swift`

新增 App 源文件必须在 `SunSmart.xcodeproj/project.pbxproj` 中同步加入：

- SunSmart
- Archipelago
- Lumineux
- SylSmart
- SLG Sync Plus

### 现有主要修改文件

- `ProximityLightingTopologyPolicy.swift`
- `GroupProximityLightingData.swift`
- `Node+SyncData.swift`
- `ProfileSettingsViewController.swift`
- `GroupMembersViewController.swift`
- `GroupServer.swift`
- `GroupsViewController.swift`
- `GroupViewController.swift`
- `DevicePermanentDeletionCleanup.swift`
- 各 Node 删除调用方
- `DeviceRestoreViewController.swift`
- `GroupPathSequencePageController.swift`
- `SpacePathTriggerZoneController.swift`
- `SyncDevicesViewController.swift`
- `ImportData.swift`
- `ExportData.swift`
- `CloudSynchronizationManager.swift`
- `SpaceViewController.swift`
- `SiteViewController.swift`
- `NetowrkReqeustApi.swift`

如新增用户可见的导入失败或待同步提示，必须同时修改 English 和简体中文 Localizable.strings，并检查五个共享 target。

NordicSigMeshSDK 无需修改；现有邻近照明消息类型和 ACK 更新能力足够。若实现中发现 SDK 无法表达必要操作，应停止 SDK 修改并重新确认范围。

## 8. 测试与验证计划

### 8.1 纯策略测试

至少覆盖：

1. Group Sequence 双向相邻关系。
2. Group Zone 和 Space Zone 合并去重。
3. Profile 降级清空 Group/Space 逻辑引用并生成 Disable/对端更新。
4. 成员移除清理所有出现位置。
5. Group 删除处理空 Group 和跨组对端。
6. Node 删除覆盖 Vendor Element 与异常 Element 地址。
7. 批量 Node 删除结果合并。
8. 地址迁移替换所有 Group/Space 引用。
9. Relay Number 0...20、255 和非法值。
10. 32 Path、200 Point、32 Zone、184 Neighbor 的边界值和越界值。
11. 合法 Sequence 重复/跨 Zone 复用不被误删。
12. 同 Zone 重复项稳定去重。
13. 旧、新 Plan 的完整 pending 集合，不只包含本次变化地址。
14. 空拓扑下邻近 Group 保持 Enabled、非邻近旧成员得到 Disable。

### 8.2 源码契约测试

锁定以下顺序和入口：

- Cloud Dirty 早于 GroupInfo/SpaceData 持久化。
- 成员连接检查早于 `groupState` 修改。
- Profile、成员、Group 删除、Node 删除、Restore 均调用 Coordinator。
- Group 两个删除入口调用同一领域方法。
- 永久删除所有 Context 调用方消费或合并生命周期结果。
- Group/Space SAVE 使用统一 Reconciler。
- 导入在清空旧 Mesh 前完成解析和硬校验。
- 非邻近 Group 不导出 Path，空 Space Zone 显式导出。
- 新文件进入五个 target。

### 8.3 App 构建

按项目要求直接运行无签名 generic iPhoneOS Debug 构建，不使用 Simulator：

- SunSmart
- Archipelago
- Lumineux
- SylSmart
- SLG Sync Plus

构建前后运行聚焦脚本、`git diff --check`，并检查本地 NordicSigMeshSDK 与 Package.resolved 没有被意外改动。

### 8.4 本地 App 流程验收

对 Profile 降级、成员移除、Group 删除、Node 单删/批删/强删、地址恢复逐项验证：

- 操作前后 Group Sequence、Group Zone、Space Zone 数据。
- Sync Device(s) 展示设备集合与任务类型。
- 无任务、全部成功、部分失败、全部失败、主动返回、App 重启。
- 离线操作不会先修改再无提示退出。
- 同一操作从不同页面入口结果一致。

### 8.5 真实服务器验收

使用隔离 Site/Space 和可查看的请求/响应证据：

1. 非空拓扑上传与另一台客户端下载。
2. 空数组清除。
3. Group 降级、成员/Group/Node 删除后服务器无悬空引用。
4. 缺失字段、version 1 缺字段、非法成员、超容量 payload。
5. 旧 App 上传后新字段仍在。
6. 新 App 清空后旧 App 上传不会恢复旧关系。
7. 两台客户端并发编辑触发 revision 冲突而非静默覆盖。

### 8.6 真实 BLE/Mesh 验收

每个生命周期场景均读取或通过重连核对：

- 当前 Group Node 的 Enabled。
- 每个 Group 的 Relay Number。
- Group 内和跨 Group 的完整 Neighbors。
- 删除/移除关系两端都已更新。
- 单个设备失败后其状态保持待同步，成功设备不重复写入无关任务。
- App 重启、断开重连、Proxy 切换后仍能重建并完成任务。

## 9. 分阶段提交与发布门禁

### 阶段 A：纯策略和 RED/GREEN 测试

- 不接业务入口。
- 完成 Reconciler、diff、规范化与容量测试。
- 门禁：纯策略全部通过。

### 阶段 B：统一直接 SAVE 与同步呈现

- 将 Group/Space 现有正确 SAVE 迁入统一协调器。
- 门禁：当前功能、自动同步和五 target 构建不回归。

### 阶段 C：P1 生命周期入口

- 依次接 Profile、成员、Group 删除、Node 删除、Restore、历史规范化。
- 每接一个入口先完成对应 RED/GREEN 和故障恢复测试。
- 门禁：所有 P1 本地/App 自动化通过，再做真机测试。

### 阶段 D：服务端兼容先行

- 完成黑盒验证、schema/revision 契约和服务端上线。
- 门禁：旧版与新版交叉测试通过。

### 阶段 E：P2 App 导入导出

- 上线三阶段导入、导出防御、导入后 pending 集合与前台同步呈现。
- 门禁：无破坏性半导入，所有云 fixture 和五 target 构建通过。

### 阶段 F：端到端验收

- 服务器、两台 App、真实 Mesh 设备联测。
- 所有自动化、构建、云往返和设备状态证据分别记录。

未获得明确授权前不 commit、不 push。建议每个阶段独立审查，避免 P1 生命周期和 P2 全量导入重构混成一个难以回退的提交。

## 10. 完成定义

只有同时满足以下条件，才能认定 P1、P2 全部修复：

- 所有 Profile、成员、Group、Node、Restore、直接 SAVE 入口使用统一旧/新拓扑流程。
- 本地数据库和导出 JSON 不存在无效 Profile、Group、成员或 Node 引用。
- 任何拓扑变化都包含跨 Group 对端，并显示完整待同步集合。
- 同步失败可重建、可见、可重试，不误报整体成功。
- 云导入在破坏本地数据前完成校验，硬错误保留最后正确快照。
- 缺失字段与空数组具有版本化的不同语义。
- 服务端保护旧客户端和并发写入，旧版本不会删除新字段。
- 五个 App target 构建通过。
- 真实服务器往返通过。
- 真实 BLE/Mesh 读取或重连验证通过。

自动化全绿、HTTP 200 或 iOS 编译成功中的任意一项，都不能单独作为最终完成证据。
