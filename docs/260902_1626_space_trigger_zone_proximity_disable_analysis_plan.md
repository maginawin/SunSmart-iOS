# Space Trigger Zone 空 Zone 导致 Proximity Lighting 被禁用：原因分析与修复计划

## 1. 结论

这是 App 侧设备同步拓扑计算错误，不是 Cloud Sync、Mesh 丢包或设备误回包。

当前 `SpacePathTriggerZoneController` 把 `space.triggerZones` 单独计算出的邻居列表当成设备完整的 Proximity Lighting 邻居真值。Save 时会遍历 Space 内所有 Proximity Lighting Group 的设备；某台设备只要没有出现在非空 Space Trigger Zone 中，`desiredNeighbors` 就为空，代码便在设备当前为 Enabled 时生成 `proximityLightingEnabled(false)`。

因此：

- 新增 32 个空 Zone 不是特殊阈值问题；新增 1 个空 Zone 后 Save 也能触发同类问题。
- 32 个空 Zone 没有成员，所以所有 eligible node 的 Space 邻居都为空。
- 代码没有读取或合并 `group.info.proximityLightingPath.paths` 与 `group.info.proximityLightingPath.zones`。
- Group 已配置的 Path 和 Group Trigger Zone 仍保存在本地与云端逻辑模型中，但对应设备的同一套 Proximity Lighting 功能被 Space Save 下发的 Disable 关闭。

正确处理原则应为：Group Path、Group Trigger Zone、Space Trigger Zone 是同一张设备邻居表的三个逻辑输入，必须先合并为统一的设备目标拓扑，再生成 Mesh 任务。空 Space Zone 只表示“没有新增 Space 关系”，不能表示“关闭该 Space 内所有设备的 Proximity Lighting”。

## 2. 日志证据

### 2.1 确实下发了 Disable

日志中的消息为：

- Vendor Function：`proximityLightingEnabled(false)`。
- Access Parameters：`41 01 00`。
- `0x41`：Proximity Lighting 功能。
- `0x01`：Enabled 子命令。
- `0x00`：禁用。

样例中至少以下设备收到了该命令并返回成功：

| 十进制地址 | Mesh 地址 | 结果 |
| --- | --- | --- |
| 140 | `0x008C` | Vendor Status success |
| 143 | `0x008F` | Vendor Status success |
| 153 | `0x0099` | Vendor Status success |
| 156 | `0x009C` | Vendor Status success |
| 159 | `0x009F` | Vendor Status success |

`buildSyncDatas()` 只有在 Node 缓存中的 `proximityLightingEnabled == true` 时才为“空目标邻居”生成 Disable，因此日志任务数不一定等于 Space 的 7 个 Node；已经处于 Disabled 或不满足任务条件的 Node 不会重复生成同一任务。

### 2.2 回包证明设备接受了命令

每台设备返回的 `SunricherVendorStatus` 均包含：

- `isSuccessful: true`；
- `ResponseCode.proximityLightingEnabled`；
- 对应源地址。

当前 SDK 在成功回包后会把 Node 缓存中的 `proximityLightingEnabled` 更新为下发值。因此从日志和当前 SDK 行为可以确认：这些设备不是只创建了 UI Task，而是已经成功执行了 Disable 命令。

`Local Vendor Model ... not bound to key` 出现在 Status 接收之后；本日志仍完成了解密、Status 解析和 App message delegate 分发。它不是本次错误任务的生成原因，也不能抵消前面的成功回包。

### 2.3 Cloud Sync 与设备同步是两条链

Cloud 请求中 Group 的 `proximityLightingPath` 仍保存了 Path 和 Group Trigger Zone 数据，HTTP 也返回 `200 success`。这只能证明逻辑 JSON 上传成功，不能证明设备仍启用或邻居表正确。

本次实际状态是：

1. Group Path / Group Trigger Zone 逻辑数据仍存在。
2. Space Trigger Zone 的 32 个空逻辑 Zone 被保存。
3. App 随后独立向现场设备发送 Disable。
4. 云端仍可能同时保有正确的 Group 逻辑结构和导致本次操作的 Space 逻辑结构。

日志中的 `Content-Encoding: gzip` 与 `actualBodyGzip=false` 是另一项 HTTP 契约问题，与本次 Proximity Lighting Task 生成无直接因果关系。

## 3. 源码调用链

入口已在 `SpaceMoreViewController.makeOptions()` 中对有 Group 编辑权限的用户开放。

Save 调用链：

1. `SpacePathTriggerZoneController.saveAction()` 保存 `space.triggerZones`。
2. 无论本次编辑是否产生任何实际 Zone 成员关系，都会调用 `buildSyncDatas()`。
3. `buildSyncDatas()` 遍历 `eligibleNodes`，范围是 Space 内所有 Proximity Lighting / Proximity Lighting With Photocell Group 的去重设备集合。
4. `desiredNeighborAddresses()` 只从当前 `setZones` 计算邻居。
5. 32 个空 Zone 对任何 Node 都得到空数组。
6. 对当前 Enabled 的 Node 生成 `.proximityLightingEnabled(false)`。
7. `SyncDevicesViewController(.spaceTriggerZones)` 将任务转换为 `SunricherVendorSet(.proximityLightingEnabled(false))` 并逐台发送。

这一行为从 2026-03-30 引入 Space Trigger Zone 时已经存在，并非本轮 Space Add View UI 修改引入。

## 4. 根因分层

### P0：存在两个逻辑真值，却写同一份设备物理状态

Group Save 的目标邻居只来自 Group Path 与 Group Trigger Zone；Space Save 的目标邻居只来自 Space Trigger Zone。两边都会写设备的同一份：

- Enabled；
- Relay Number；
- Neighbor Addresses。

两边都没有合并另一方配置，所以最后保存的一方覆盖前一方。即使只修复“空 Space Zone 不 Disable”，之后保存非空 Space Zone仍会覆盖 Group 邻居；再保存 Group Path 又会覆盖 Space 邻居。

### P0：空列表语义错误

Space 侧把“当前 Node 没有 Space 邻居”解释为“禁用 Proximity Lighting”。但 Group 侧当前语义是：只要 Node 仍属于 Proximity Lighting Profile，即使目标邻居为空，也应保持或恢复 Enabled。

本次场景中，空 Space Zone 应当是零拓扑贡献，而不是全局关闭指令。

### P1：同步范围过大

新增空 Zone 只改变逻辑占位结构，没有改变任何设备之间的边关系，但当前代码仍扫描所有 eligible node，并可能给所有 Enabled Node 生成 Disable。

Space 编辑应只重新计算受旧、新 Space Zone 成员关系影响的设备。首次新增纯空 Zone 的受影响设备集合应为空，因此只需本地保存和 Cloud Sync，不应进入设备同步页。

### P1：`node.group` 不是可靠的 Group 身份

当前 Space 同步使用 `node.group?.info.profile.proximityLightingNumber` 获取 Relay Number，添加 Space Zone Item 时也使用 `node.group?.address` 保存 Group 地址。

SDK 的 `node.group` 实现只是遍历元素订阅并返回第一个普通 Group。设备属于多个 Group 时，这个 Group 可能不是用户筛选或选择的 Group，也无法表达一个 Node 的所有有效 Group 成员关系。

此外，Group Path 同步页传入了明确的 `group`，但 `SyncDevicesViewController` 内又调用无参数的 `node.getNodeSyncProximityLighting()`，仍可能退回第一个订阅 Group。

### P1：现有契约测试固化了错误行为

`PathTopologyPersistenceContractTests` 当前明确断言：eligible node 没有 Space desired neighbors 时必须保留 `.proximityLightingEnabled(false)` 分支。该契约测试本轮通过，但它验证的是旧设计，不是用户期望的 Group / Space 共存语义。

此前 2026-07-28 的协议审计已经记录“Group 与 Space 两套功能写同一张设备邻居表并互相覆盖”的风险；2026-07-29 的修复范围明确不处理该架构冲突，并明确保留空邻居时 Disable 的行为。入口于 2026-07-30 正式开放后，该风险变成用户可直接触发的问题。

## 5. 推荐的产品与设备真值

建议确认并采用“可共存、统一合并”的产品语义：

1. Group Path 提供相邻 Point 之间的邻居关系。
2. Group Trigger Zone 提供同一 Group Zone 内的邻居关系。
3. Space Trigger Zone 提供跨 Group Zone 内的邻居关系。
4. 每台设备最终 Neighbor Addresses 是以上三类关系的去重并集。
5. 空 Path Point、空 Group Zone、空 Space Zone 都只贡献零条关系。
6. Node 仍属于任一有效 Proximity Lighting Group 时，Space 页面不得仅因 Space 邻居为空而 Disable。
7. 只有 Node 已不属于任何有效 Proximity Lighting Group，或产品明确执行关闭功能的操作时，才生成 Disable。

如果产品实际希望 Space Trigger Zone 替代 Group Path / Group Trigger Zone，则必须在 UI 上将两套功能设为互斥，并在切换前明确告知会清空或覆盖旧配置；不能继续让两套入口可同时编辑、云端同时保存、设备端最后写入者获胜。结合当前页面设计与用户场景，推荐采用合并语义。

## 6. 场景处理规则

| 操作 | 设备侧期望 |
| --- | --- |
| 首次新增 1～32 个空 Space Zone | 0 个 Mesh Task；只保存逻辑结构并 Cloud Sync |
| 在空 Space Zone 中加入设备 | 只重算新 Zone 成员；目标为 Group 关系与 Space 关系的并集 |
| 从 Space Zone 移除设备 | 重算旧、新成员并集；只移除 Space 贡献，保留 Group 贡献 |
| 删除非空 Space Zone | 同上，不能清除仍由 Group 提供的邻居关系 |
| 删除全部 Space Zone | 恢复为纯 Group 拓扑；仍在 Proximity Lighting Group 的设备不得被 Disable |
| 再次保存 Group Path / Group Trigger Zone | 同样通过统一编译器合并 Space 关系，不能反向覆盖 Space 配置 |
| Group Profile 改为非 Proximity Lighting，且 Node 不再属于其他有效 Proximity Lighting Group | 才允许生成 Disable |

## 7. 多 Group Relay 冲突规则

设备只有一个 `proximityLightingRelayCount`，不能同时表达多个不同 Group 的 Relay Number。

建议规则：

- Node 只属于一个有效 Proximity Lighting Group：使用该 Group 的配置。
- Node 属于多个有效 Proximity Lighting Group，且 Relay Number 相同：允许合并邻居关系并使用共同值。
- Node 属于多个有效 Proximity Lighting Group，但 Relay Number 不同：阻止产生 Mesh 写任务并提示用户先统一 Group 配置；禁止静默选择第一个、最小值或最大值。
- Space Zone Item 必须保存用户实际选择来源的 `groupAddress`，不能从 `node.group` 反推。

如果需要新增冲突提示，必须同时补充 English 与简体中文本地化。

## 8. 修复方案

### 阶段 1：先建立失败回归用例

1. 修改 `Tests/Group/PathTopologyPersistenceContractTests.swift`，删除“空 Space 目标邻居必须 Disable”的旧契约。
2. 新增统一拓扑编译的聚焦测试，先证明当前实现失败。
3. 覆盖首次新增 32 个空 Zone 时设备任务数为 0。
4. 覆盖 Group Path、Group Trigger Zone 与 Space Trigger Zone 的邻居并集合并。
5. 覆盖删除 Space 关系后 Group 关系仍存在、设备仍 Enabled。
6. 覆盖 Group 与 Space 交替保存不改变最终有效拓扑。

### 阶段 2：引入单一拓扑编译器

建议新增纯业务层 `ProximityLightingTopologyPlanner`，输入为：

- 当前 Space；
- Space 内当前有效 Group 与成员关系；
- Group Path / Group Trigger Zone；
- Space Trigger Zone；
- 保存页面尚未提交的 proposed override。

输出每台 Node 唯一的目标状态：

- Enabled；
- Relay Number；
- 去重后的 Neighbor Addresses；
- 规划错误，例如多 Group Relay 冲突。

编译器不发送消息、不保存数据库、不读取 UI 状态。所有页面和后台同步入口都复用同一结果。

### 阶段 3：拆分“拓扑计算”和“设备缓存差异比较”

将当前 `Node.getNodeSyncProximityLighting()` 中混在一起的职责拆开：

1. 统一编译器负责算出目标状态。
2. Node 比较器只比较目标状态与 SDK 缓存状态，生成至多一个 `NodeSyncData`。

建议的任务优先级保持现状：

1. Neighbor 不一致：发送完整 Neighbor Set，该命令同时携带 Enabled 与 Relay。
2. Neighbor 一致、只有 Relay 不一致：发送 Relay Set。
3. Neighbor 与 Relay 一致、只有 Enabled 不一致：发送 Enabled。
4. 全部一致：不生成任务。

### 阶段 4：修正 Space Save 的变更范围

`SpacePathTriggerZoneController.saveAction()` 应在覆盖持久化数据前保留清理后的 old/new Zone 快照，并计算受影响 Node：

- old Space Zone 成员地址；
- new Space Zone 成员地址；
- 两者去重并集。

首次新增纯空 Zone时集合为空，直接走本地保存与 Cloud Sync 分支。

删除或修改非空 Zone 时，对受影响 Node 使用完整统一拓扑重新计算；不能直接把 Space 单独算出的空数组映射成 Disable。

### 阶段 5：修正 Group Save 与重新同步入口

以下入口必须使用同一个 Planner，避免 Space 修好后又被 Group 反向覆盖：

- `GroupPathSequencePageController.saveAction()`；
- `GroupPathSequencePageController.syncFailedBtnAction()`；
- `SyncDevicesViewController` 的 Group Path 分支；
- Group 成员添加、移除与 Profile 改变产生的 Proximity Lighting 同步；
- `GroupServer` 的添加/移除设备消息规划；
- `DeviceGroupDeferredSyncPlanner`；
- Device Restore / 全量 Need Sync 对 Proximity Lighting 的判断。

Group Path 的同步类型不应再在 `SyncDevicesViewController` 内根据 `node.group` 二次计算。页面或共享规划层应传入已经基于明确 Space/Group 上下文计算的任务。

### 阶段 6：修正 Space Item 的 Group 身份

Space 添加候选不能只传 `Node`；需要保留明确的 Group + Node 成员上下文。用户从某个 Group 筛选项选择设备时，Item 使用该 Group 地址。选择 All Eligible Groups 时：

- 单一有效 Group 直接使用；
- 多个有效 Group且语义无冲突时采用明确、可追踪的成员集合；
- Relay 配置冲突时阻止 Save/同步并给出本地化提示。

## 9. 预计修改文件

主要文件：

- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Group/Model/GroupServer.swift`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `Tests/Group/PathTopologyPersistenceContractTests.swift`
- `scripts/check_path_topology_persistence.sh`

建议新增：

- `SunSmart/Main/Group/Model/ProximityLightingTopologyPlanner.swift`
- 对应的聚焦拓扑测试或独立契约测试。

如果新增 Swift 文件，需要同步加入所有引用该共享业务代码的品牌 target，并逐一检查 target membership。若采用现有文件承载 Planner，可以减少 project 配置改动，但不应牺牲单一职责和可测试性。

如新增 Relay 冲突提示，还需同步修改：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- 其他品牌 target 实际引用的对应本地化资源。

## 10. 回归测试矩阵

### 10.1 纯逻辑测试

1. Group Path `A-B-C`，无 Space Zone：A 邻居 B；B 邻居 A/C；C 邻居 B。
2. 在上述状态新增 32 个空 Space Zone：目标拓扑完全不变，设备任务数为 0。
3. Space Zone 加入 A/C：A 在 B 基础上增加 C；C 在 B 基础上增加 A；不产生重复地址。
4. 删除该 Space Zone：恢复纯 Group 拓扑，不 Disable A/B/C。
5. Group Trigger Zone 与 Space Zone 有重复边：最终仅保留一个地址。
6. 跨 Group Space Zone：双方都保留各自 Group 关系，并增加跨 Group 关系。
7. Node 多 Group、Relay 相同：允许。
8. Node 多 Group、Relay 不同：产生明确规划错误，0 个 Mesh 写任务。
9. Node 不再属于任何有效 Proximity Lighting Group：允许 Disable。
10. SDK 缓存已与目标一致：0 个任务。

### 10.2 App 流程测试

1. Space More → Trigger Zone → Add 32 → 不添加设备 → Save。
2. 不应进入包含 Proximity Lighting Disable 的 Sync Devices 流程。
3. Group 页面已有 Path 与 Trigger Zone 的编辑数据保持不变。
4. 返回 Group 页面不应出现由本次空 Zone 保存引起的 Devices Not Synced。
5. Group Save → Space Save → Group Save 交替执行，任务目标保持统一。
6. 删除已有非空 Space Zone，确认只移除 Space 边。
7. Owner / Editor / Visitor 权限路径分别验证。

### 10.3 日志验收

本问题的直接回归标准：

- 新增纯空 Space Zone 后 Save，不得出现由该操作生成的 `proximityLightingEnabled(false)`。
- 不得出现对应的 Access Parameters `41 01 00`。
- 若 Group 与 Space 合并后的目标和设备缓存相同，应为 0 个 Mesh Task。
- 若确有拓扑变化，Neighbor Set Payload 必须等于 Group + Space 去重并集。

### 10.4 构建与真机验收

实现后按共享 target 范围执行聚焦契约测试，并对 SunSmart、Archipelago、SLG Sync Plus、SylSmart 等引用该共享代码的 target 做 generic iPhoneOS 无签名构建检查。

真机至少验证：

1. 空 Zone Save 后原 Group Path / Trigger Zone 触发行为不变。
2. 非空跨 Group Space Zone 的实际触发范围正确。
3. 删除 Space 关系后 Group 关系仍生效。
4. Group 与 Space 交替保存后设备行为不随最后保存入口变化。
5. 设备重启后配置仍保持。

编译通过、HTTP 200 或 Vendor ACK 都不能单独替代上述真实 Mesh 行为验收。

## 11. 临时止损建议

在完整合并方案实施并验证前，不建议继续用当前版本保存 Space Trigger Zone。

若必须先做最小止损，可暂时满足以下两条：

1. old/new Space Zone 都没有任何成员时，禁止生成设备任务。
2. 对仍属于有效 Proximity Lighting Group 的 Node，Space Save 不得因 Space 邻居为空而发送 Disable。

这能阻止本次事故，但不能解决 Group 与 Space 非空配置互相覆盖，所以只能作为短期补丁，不能作为最终完成标准。

## 12. 当前验证边界

已完成：

- 用户日志的 Access PDU、Vendor Status 与设备地址核对。
- Space Save → Task → Mesh Message 源码调用链追踪。
- Group 与 Space 两套邻居算法、共享设备字段与缓存更新核对。
- 所有 `getNodeSyncProximityLighting()` 主要调用点扫描。
- 当前 App 固定的 NordicSigMeshSDK `release` revision 与本地 SDK checkout 一致性核对。
- 当前 `PathTopologyPersistenceContractTests` 运行通过，并确认其保留了旧 Disable 契约。

未完成：

- 未修改运行代码。
- 未执行 iOS Build；本轮为分析与方案确认阶段。
- 未做真实设备邻居表读取、交替保存或重启验证。
- 多 Group Relay 冲突的产品交互仍需确认。

