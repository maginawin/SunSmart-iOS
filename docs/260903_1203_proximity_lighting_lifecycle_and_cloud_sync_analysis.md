# 邻近照明 Node 生命周期与云同步完整性分析

## 1. 分析范围与基线

- 分析工作树：`trigger-zone-july`
- 源码基线：`7aa173ed`
- Swift Package 锁定的 NordicSigMeshSDK：`release` 分支，revision `86f5ec9e40148b9cd93e0512702337fcec41dd40`
- 本次仅做源码、数据流和现有测试分析，不修改运行代码。
- “正确”分成四层判断：App 逻辑拓扑、本地持久化、云端往返、真实设备 Mesh 状态。某一层通过不能替代其他层。

## 2. 总体结论

当前实现只能评定为“部分正确”，不能认为 Sequence / Trigger Zone 在所有邻近照明生命周期操作及云同步场景下都被完整处理。

直接从 Group Sequence / Group Trigger Zone 或 Space Trigger Zone 页面执行编辑、删除、重置和 SAVE 时，当前拓扑规划、Cloud Dirty、本地保存、同步任务生成与自动进入 Sync Devices 的主链路基本完整。邻近 Profile 内部属性更新，尤其 `proximityLightingNumber` 变化，也能生成 Relay Number 更新任务。

主要缺口集中在这些页面之外的生命周期操作：

1. Group Profile 从邻近类型切换为非邻近类型时，当前 Group 的设备会生成 Disable，但逻辑 Sequence / Trigger Zone 引用仍被保留，Space Trigger Zone 中涉及该 Group 的跨组关系也没有统一清理或归档；其他 Group 的关联设备不会在这次 Group 同步中更新邻居表。
2. 从邻近 Group 移除成员时，只清理该 Group 自身 Sequence / Group Trigger Zone 中的引用；不会清理 Space Trigger Zone，也不会同步受跨组关系影响的其他 Group 设备。
3. 删除邻近 Group 时，原 Group 设备有退出/Disable 路径，但 Space Trigger Zone 中的 Group/Node 引用不会同步删除，其他 Group 的设备不会重编译邻居表；不同删除入口的 Cloud Dirty/上传触发还不一致。
4. 永久删除 Node 时，没有清理 Group Sequence、Group Trigger Zone、Space Trigger Zone 中的引用，也没有同步邻近关系中的其他设备。随后上传服务器会携带悬空拓扑引用。
5. 云导出/导入已覆盖相关字段，但导入只做结构解码和地址基础校验，没有做 Profile 资格、Group 成员归属、跨字段引用、重复项和容量的完整语义校验，也不会在导入后自动让真实设备状态收敛。

因此，当前最大的系统性问题不是某一个 SAVE 页面，而是缺少一个覆盖“旧拓扑 → 新拓扑”的统一生命周期协调器。各入口分别更新自己的局部数据和局部设备集合，无法可靠处理跨 Group 的 Space Trigger Zone 影响。

## 3. 邻近照明数据所有权

| 数据 | 当前所有者 | 作用 | 主要风险 |
| --- | --- | --- | --- |
| Sequence 与 Group Trigger Zone | `GroupInfo.proximityLightingPath` | 保存 Group 内部的有向邻近关系 | 生命周期入口未统一清理；导入不校验成员归属 |
| Space Trigger Zone | `SpaceData.triggerZones` | 保存跨 Group 的 Trigger Zone 关系 | Group/成员/Node 删除后易留下悬空引用 |
| 邻近 Profile 与 Relay Number | `Group.profile` | 决定 Group 是否参与邻近拓扑及设备 Relay Number | Profile 降级后旧拓扑仍保留，重新启用时会静默恢复 |
| 设备已观测邻近状态 | Node 扩展字段 | 缓存 Enabled、Relay Number、Neighbors，用于判断是否需要同步 | 云端保存的是已观测/缓存状态，不等于真实设备已执行成功 |

核心拓扑规划器会只让两个邻近 Profile 的 Group 参与计算，并按当前有效成员过滤 Group Sequence、Group Trigger Zone 和 Space Trigger Zone。它能避免把明显无效引用直接编译进新的目标拓扑，但不会反向修复保存的数据，也不会自动发现所有需要重新同步的旧拓扑设备。

## 4. 用户列举场景逐项结论

| 场景 | App 逻辑数据 | 设备同步 | 云端数据 | 结论 |
| --- | --- | --- | --- | --- |
| 邻近 Group Profile 改为非邻近 Profile | 原 Sequence / Group Trigger Zone 和 Space Trigger Zone 引用保留 | 当前 Group 成员可生成 Disable；跨组关联设备不在 `.group` 同步集合中 | Profile 可上传，但旧拓扑也可能继续上传 | 部分正确，高风险 |
| 从邻近 Group 移除 Node | 当前 Group 内 Sequence / Group Trigger Zone 会清理；Space Trigger Zone 不清理 | 退出 Node 与当前 Group 剩余成员可同步；其他 Group 关联设备不更新 | 完成同步后通常可触发上传，但悬空 Space 引用仍会被导出 | 部分正确，高风险 |
| 删除邻近 Group | GroupInfo 随 Group 删除；Space Trigger Zone 引用不清理 | 原 Group Node 可走退出/Disable；跨组关联设备不更新 | 删除入口的变更通知不一致，且可能上传悬空 Space 引用 | 不完整，高风险 |
| 更新邻近 Group Profile 属性 | Profile 配置正常保存；邻近类型之间切换保留拓扑 | 类型变化强制完整 Profile 同步；Relay Number 变化能生成专用更新 | Profile 与 Relay Number 可导出/导入 | 基本正确，需真机确认 |
| 删除邻近 Group 中的 Node | Group/Space 拓扑引用都不主动清理 | 被删 Node 本身被移除，但其邻近关系中的其他设备不更新 | 云上传可能包含已删除 Node 地址 | 不正确，高风险 |

### 4.1 Profile 从邻近类型切换为非邻近类型

`ProfileSettingsViewController` 在 Profile 类型变化时构造强制同步上下文；`Node+SyncData` 的全局拓扑规划会把已经不具备邻近资格的 Group 排除，并为原先 Enabled 的当前 Group Node 生成 Disable。因此，“关闭当前 Group 设备的邻近功能”这一步具备实现依据。

但 Group 自身 `proximityLightingPath` 和 Space 的 `triggerZones` 并未随 Profile 降级清理，也没有明确的“暂停/归档”状态。`.group` 同步数据源只包含当前 Group 的成员和进出成员，不包含因 Space Trigger Zone 关系而受影响的其他 Group Node。结果是：

- App 新规划中不再使用这些引用，但持久化和云数据仍保留它们。
- 其他 Group 的真实设备可能仍保留已失效的邻居地址。
- 将 Profile 再改回邻近类型时，旧关系会无提示地重新生效。

“降级时删除拓扑”还是“保留为暂停配置”属于产品规则，但无论选择哪一种，都必须显式表达，并同步旧、新拓扑的并集设备。当前实现两者都没有完整做到。

### 4.2 从邻近 Group 移除 Node

`GroupMembersViewController` 会在当前 Group 仍是邻近 Profile 时调用 `GroupProximityLightingPathData.removeNode`，从本 Group 的 Sequence 和 Group Trigger Zone 中删除地址，并让退出 Node、加入 Node和本 Group 剩余成员进入 Group 同步。

存在三项缺口：

- 不处理 `SpaceData.triggerZones` 中相同的 `(groupAddress, deviceAddress)` 引用。
- 不包含其他 Group 中因 Space Trigger Zone 邻接变化而需要更新的设备。
- 如果先把 Group 降级为非邻近 Profile，再移除成员，本 Group 路径清理也会被条件判断跳过。

另外，`removeNode` 对每条 Sequence / Zone 只删除首次命中的地址。正常 UI 通常不会制造重复项，但异常导入数据中若有重复地址，仍可能残留。

### 4.3 删除邻近 Group

Group 删除前会为 Group 内 Node 构建退出同步数据，因此原 Group Node 有机会收到 Disable/退出配置。随后 `Group.deleteExtension` 会删除 GroupInfo、Profile 等扩展数据。

但 `Group.deleteExtension` 不会清理 `SpaceData.triggerZones`，也不会为其他 Group 设备生成新的邻居表。这里还存在入口差异：Group 列表删除成功后会发送 `spaceDataChanged`，而 Group 详情页删除成功后只发送 `groupsRefresh`。后者只更新 Space 统计数据，不等价于明确标记和上传完整云变更。因此同一种删除操作可能因入口不同而产生不同的云同步结果。

### 4.4 更新 proximity group profile 属性

这一场景是当前较完整的部分：

- Profile 类型变化会强制完整 Profile 数据同步。
- 在两个邻近 Profile 之间切换时，Group 仍具备拓扑资格，已有关系继续参与规划。
- `proximityLightingNumber` 变化时，拓扑策略支持仅生成 Relay Number 变更，而不必重写未变化的邻居集合。
- 其他 Profile 属性继续走现有 Group Profile 同步。

需要保留两个验收边界：自动化测试能证明任务生成，不能证明 BLE/Mesh ACK 后设备已经应用；如果类型变化同时改变跨 Group Space 关系的有效性，仍会受到前述“同步集合只覆盖当前 Group”的限制。

### 4.5 永久删除 proximity group 中的 Node

永久删除流程的清理上下文目前只处理 Schedule 等通用引用并调用 Node 扩展删除，没有调用邻近拓扑清理：

- Group Sequence 中地址保留，解析不到 Node 时可能表现为空项；若地址将来复用，还可能错误指向新设备。
- Group Trigger Zone 和 Space Trigger Zone 中地址保留。
- 邻近关系另一端的设备不会收到新的 Neighbor Set。
- 批量删除流程随后可以正常提交云变更，但导出的是包含悬空引用的逻辑拓扑。

这是本轮分析中最明确的功能缺口。

## 5. 其他邻近照明相关操作

| 操作 | 当前行为 | 结论/注意事项 |
| --- | --- | --- |
| Group Sequence / Group Trigger Zone 直接新增、删除、重置并 SAVE | 合并工作副本、生成完整 Group 目标、先标记 Cloud Dirty、保存并自动同步 | 基本正确；这些关系只在 Group 内，当前同步范围匹配 |
| Space Trigger Zone 直接新增、删除、重置并 SAVE | 保存前清理当前工作副本的无效成员，按完整 Space 拓扑生成所有待同步任务 | 基本正确；也是修复历史悬空 Space 引用的人工恢复入口之一 |
| 向邻近 Group 新增成员 | 新成员触发完整 Profile 同步；未被加入拓扑前不会凭空产生邻居关系 | 基本正确 |
| 非邻近 Profile 改为邻近 Profile | 所有成员可进入 Enabled 状态，即使邻居集合为空 | 策略上明确；但此前保留的旧拓扑会静默恢复，需要产品确认 |
| Node 地址恢复/迁移 | 会迁移所有 Group Path/Zone 和 Space Zone 中的旧地址，并标记云变更 | 逻辑引用迁移较完整；受影响的其他真实设备不会自动完成全量收敛 |
| 打开 Space Trigger Zone 页面 | 工作副本会过滤无效 Group/Node 组合 | 只有点击 SAVE 才写回；仅打开页面不修复持久化数据 |
| 打开 Group Trigger Zone 页面 | 工作副本会过滤已不在全局 Node 集合中的地址 | 不会过滤“Node 仍存在但已不属于当前 Group”的引用，且仍需 SAVE 才写回 |
| 异常导入导致一个 Node 同时落入多个 Group | 规划结果依赖稳定排序和后写覆盖 Relay Number | 正常 UI 假设单 Group 归属，异常数据缺少显式冲突拒绝或修复 |
| 同步失败/离线 | 任务可保留失败状态，部分 SAVE 流程停留同步页 | 生命周期入口并不统一；个别流程在本地已变更后遇到连接检查失败，可能未及时提交云变更 |

## 6. 导出、导入、上传和服务器同步

### 6.1 已覆盖的字段

当前 JSON/数据库链路已经覆盖：

- Space 的 `triggerZones`。
- GroupInfo 的 `proximityLightingPath`，其中包含 Sequence 与 Group Trigger Zone。
- Group Profile 及邻近 Profile 的 `proximityLightingNumber`。
- Node 已观测的邻近 Enabled、Relay Number 和 Neighbors 状态。

Space 导出会写出 `triggerZones`，包括空数组；Group Path 只要非空对象存在就会导出，不因当前 Group 已变成非邻近 Profile 而自动删除。云上传使用完整 `SpaceData.export()` 结果，HTTP 上传成功后更新本地云时间戳，但没有额外的邻近拓扑协调逻辑。

### 6.2 语义完整性缺口

导入侧主要做 JSON 解码和单播地址合法性处理，未统一验证：

- 引用的 Group 是否存在且仍使用允许的邻近 Profile。
- 引用的 Node 是否存在并属于所声明的 Group。
- Sequence、Group Trigger Zone、Space Trigger Zone 是否有重复项。
- 数量是否符合 Path/Zone/Neighbor 的容量限制。
- 同一 Node 的异常多 Group 归属或 Relay Number 冲突。
- 导入后的逻辑目标与 Node 已观测状态之间是否需要生成 Mesh 同步任务。

因此，云链路对字段的“序列化完整”不等于对数据的“语义正确”。悬空引用可以从本地导出到服务器，再被另一台设备原样导入。

### 6.3 全量快照与版本兼容风险

当前 Space 导入按时间戳和摘要条件采用整体快照，`triggerZones` 缺失或解码失败时会归一为空数组。当前版本导出总会携带该字段，但旧版本 App 是否省略字段、服务器是全量替换还是字段合并，需要用真实服务端往返验证。在没有服务端契约证据前，存在“旧客户端上传后清空新客户端 Space Trigger Zone”的兼容风险，不能仅凭本地 JSON 代码断言安全。

### 6.4 云状态与真实设备状态必须分开

- 云上传成功只证明服务器接受了逻辑数据/缓存状态。
- Node 中导出的 Enabled、Relay Number、Neighbors 是 App 已观测或缓存的状态。
- 两者都不能证明目标灯具已经通过 Mesh 成功执行、持久化并在重新连接后保持一致。

服务器同步完成后，当前导入流程不会自动将导入拓扑编译为设备任务。因此多手机场景下可能出现“App/云拓扑一致，但现场设备仍维持旧邻居表”。

## 7. 根因归纳

1. 邻近逻辑拓扑分散在 GroupInfo 和 SpaceData，生命周期操作只清理各自熟悉的局部模型。
2. 同步任务通常从“新拓扑中的当前 Group 成员”生成，而不是从“旧拓扑与新拓扑的受影响设备并集”生成。
3. Space Trigger Zone 可跨 Group，任何 Group/Profile/成员/Node 生命周期变化都可能影响其他 Group；`.group` 同步范围无法覆盖这种关系。
4. Cloud Dirty、持久化和同步触发分散在多个页面控制器，导致同一业务操作的不同入口行为不一致。
5. 导入层把 JSON 结构合法当作业务拓扑合法，缺少统一校验、修复报告和设备收敛阶段。

## 8. 建议修复方案

### P1：建立统一的拓扑生命周期协调器

每次 Profile、Group 成员、Group、Node 或地址发生变化时，统一获取变更前与变更后的完整 Space 拓扑，计算受影响设备地址并集，再完成：

- 清理或显式归档 Group/Space 逻辑引用。
- 同步保存 GroupInfo 与 SpaceData。
- 在持久化前标记 Cloud Dirty，避免中途断连造成云变更丢失。
- 清除所有受影响 Node 的邻近同步缓存，而不是只清当前 Group。
- 为仍存在的所有受影响设备生成 Enable/Disable、Relay Number、Neighbor Set 任务。
- 对已删除设备跳过发送，但必须更新关系另一端的设备。

### P1：补齐五个生命周期入口

优先接入：Profile 降级、成员移除、Group 删除、Node 永久删除、Node 地址迁移。所有入口调用同一服务，不再在 ViewController 内分别维护部分逻辑。

Profile 降级需要先确认产品语义：

- 若是“删除配置”，立即清除 Group Path/Zone 和涉及该 Group 的 Space Zone。
- 若是“暂停配置”，应增加显式状态/版本语义，UI 和云端都能识别，重新启用前给出明确恢复行为；即使暂停，也要同步旧拓扑受影响设备的关闭和邻居移除。

### P1：修复跨 Group 同步范围

Group 操作不能只使用 `.group` 数据源。应基于旧、新 Space 拓扑的并集生成专用邻近同步任务，包含 Space Trigger Zone 关系另一端的所有有效设备。失败任务必须保留为可见的待同步状态。

### P1：统一云变更提交时机

Group 列表、Group 详情、单个设备删除、批量删除、成员编辑等入口应由领域层统一标记并提交相同的变更范围，避免依赖页面通知是否恰好发送。特别需要修复 Group 详情页删除未明确发送 `spaceDataChanged` 的差异。

### P2：导入后做拓扑规范化和设备收敛

导入完成前统一执行：Profile 资格、Group/Node 存在性、成员归属、地址规范化、去重、容量、冲突检查。建议区分：

- 可安全自动删除的悬空引用。
- 必须保留并提示用户的容量/归属冲突。
- 导入导致的旧、新设备目标差异。

随后将逻辑导入成功与真实设备同步拆成两个状态，生成明确的待同步集合。

### P2：确认服务端兼容契约

用真实接口验证 `triggerZones` 在字段缺失、空数组、旧客户端上传、并发多端上传时的替换/合并规则。若服务端无法提供字段级版本兼容，应增加 Schema Version 或能力版本，避免旧客户端覆盖新字段。

## 9. 建议回归与验收矩阵

### 自动化测试

1. 邻近 Profile → 非邻近 Profile：当前 Group 关闭，Space 跨组对端 Neighbor Set 更新，逻辑引用按产品规则清理或暂停。
2. 邻近 Group 移除成员：Group 与 Space 引用均清理；退出 Node、同组 Node、跨组对端均进入正确任务集合。
3. 删除邻近 Group：无悬空 Space Zone；不同 UI 入口产生相同本地与云结果。
4. 永久删除 Node：Group/Space 引用全部清理；关系另一端设备更新；地址复用不恢复旧关系。
5. Relay Number 更新：只生成必要任务，失败后仍显示待同步。
6. 邻近类型互换、非邻近 → 邻近、邻近 → 非邻近 → 邻近的往返语义。
7. 含重复、越界、错误 Group、错误成员、已删除 Node 的服务器 JSON 导入。
8. Space Trigger Zone 跨两个及以上 Group 的旧/新拓扑差异集合。
9. 离线、中途失败、App 重启后的 Cloud Dirty、待同步任务和本地数据恢复。

### 真实服务器验收

- 设备 A 创建非空拓扑并上传，设备 B 下载核对。
- 设备 A 清空拓扑并上传，设备 B 确认空数组能覆盖旧数据。
- 旧版本与新版本交替上传，确认 `triggerZones` 不被意外丢失。
- Group/Node 删除后检查服务器 JSON 不含悬空地址。

### 真实设备验收

- 对每类生命周期操作读取或重新连接确认 Enabled、Relay Number、Neighbors 最终状态。
- 验证跨 Group Space Trigger Zone 的关系两端都更新。
- 制造单设备失败，确认失败保持可见、重试后收敛且不误报成功。
- App 重启、断开重连、Mesh Proxy 切换后再次核对设备状态。

## 10. 本次验证结果与边界

执行现有聚焦脚本后，以下检查通过：

- `PASS: Path topology persistence contracts hold.`
- `PASS: Proximity Lighting topology policy tests.`
- `PASS: Space Trigger Zone follow-up contracts hold.`

脚本声明 Bash；直接用 Zsh 运行会因 `BASH_SOURCE` 报错，改按其 shebang 使用 Bash 后通过。这三个测试能证明当前主拓扑策略、直接 SAVE 和部分持久化契约，没有覆盖本报告识别的完整生命周期清理、跨 Group 设备同步、真实服务器往返和真实 BLE/Mesh 收敛。

本轮没有修改业务代码，因此未运行多 target iOS 构建；编译结果也不会改变上述数据完整性结论。

## 11. 最终判定

- 直接 Sequence / Trigger Zone 编辑与 SAVE：基本正确。
- 邻近 Profile 属性更新：基本正确，但需真实设备验证。
- Profile 降级、成员移除、Group 删除：局部正确，跨 Group 与数据清理不完整。
- 永久删除 Node：邻近照明生命周期处理不正确。
- 本地/云字段覆盖：已实现。
- 导入语义完整性、跨版本兼容与导入后设备收敛：未完整实现。

建议在继续扩展 UI 功能前，优先完成 P1 生命周期协调器和跨 Group 同步集合，否则后续入口越多，悬空引用与 App/云/设备三方不一致会继续累积。
