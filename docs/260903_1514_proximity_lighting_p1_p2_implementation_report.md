# 邻近照明 P1 / P2 修复实施报告

## 1. 实施结论

本轮已经完成当前 iOS App 仓库内可落地的 P1 生命周期修复，以及 P2 的导入、导出、上传保护、同步收敛和诊断能力。五个共享 App target 均已通过无签名 generic iPhoneOS Debug 构建，聚焦策略与源码契约测试全部通过。

当前结论需要分层表达：

- P1 App 侧代码与自动化门禁已完成。
- P2 App 侧代码与自动化门禁已完成。
- P2-5 属于服务端兼容和并发控制，当前仓库没有服务端实现，尚未完成真实接口黑盒验证或服务器修改。
- 尚未执行真实 BLE/Mesh 设备回读、真实服务器双客户端往返和完整 UI 手工验收。因此不能把本报告等同于端到端发布验收完成。

## 2. 已冻结并实现的业务语义

### 2.1 Profile 降级

Group Profile 从两个邻近类型之一变为非邻近类型时采用删除语义：

- 删除该 Group 的 Sequence 与 Group Trigger Zone 数据。
- 从全部 Space Trigger Zone 中删除属于该 Group 的成员。
- 当前 Group 设备生成 Disable，跨 Group 对端重新计算 Neighbor Set。
- 后续重新启用邻近 Profile 时从空拓扑开始，不恢复已删除的历史关系。

两个邻近 Profile 之间切换仍保留拓扑；`proximityLightingNumber` 更新只生成所需的 Relay Number 差异任务。

### 2.2 逻辑目标与设备已观测状态分离

- 普通编辑先标记 Cloud Dirty，再保存规范化后的逻辑拓扑，然后进入 Mesh 同步。
- Mesh 部分失败不回滚逻辑目标，失败设备继续保持为 Devices not synced，可在下次进入时重建。
- Node 导出字段仍表示 App 已观测状态，不会用逻辑目标伪造设备已经执行成功。
- Group 删除采用两阶段流程：先完成原 Group 退出与跨 Group 对端同步，再提交本地 Group 删除；同步失败时保留 Group，避免半删除。

### 2.3 规范化与硬错误

可以自动修复的内容包括无资格 Group 拓扑、无效 Group/Node/成员引用和同一 Zone 内重复成员。以下情况作为硬错误，不静默裁剪：

- Group 地址冲突。
- Relay Number 不在 `0...20` 或 `255`。
- 超过 32 条 Path、单 Path 超过 200 个 Point。
- 超过 32 个 Group 或 Space Trigger Zone。
- 同一 Node 异常属于多个 Group。
- 单设备最终邻居超过 184 个。

## 3. P1 生命周期修复结果

| 场景 | 修复后的处理 | 设备同步范围 |
| --- | --- | --- |
| Group Profile 邻近变非邻近 | 删除 Group Path，并清理全部 Space Zone 中该 Group 引用 | 当前 Group Disable，加上所有跨 Group 对端更新 |
| 两个邻近 Profile 互换或属性更新 | 保留拓扑并重新计算差异 | 当前 Group 与受影响对端；Relay 变化使用最小任务 |
| Group 新增或移除成员 | 清理 Sequence、Group Zone、Space Zone 中全部失效引用；连接检查早于模型修改 | 退出、加入、同组剩余成员及跨 Group 对端 |
| 删除邻近 Group | 先计算排除目标 Group 后的新拓扑；设备同步成功后才删除 Group、扩展和本地订阅 | 原 Group 退出/Disable，加上跨 Group 对端 |
| 单个、批量、强制删除 Node | 按 Node 全部 Element 地址清理所有 Group/Space 引用；删除 Node 本身不再发送任务 | 合并并去重所有仍存在的关系对端 |
| Node 地址恢复或迁移 | 统一替换所有 Sequence、Group Zone、Space Zone 地址并重新校验 | 恢复 Node 与全部关系对端进入同一流程 |
| Group Path 与 Space Zone 直接 SAVE | 统一使用完整 Space 拓扑协调器；保留自动开始同步 | 完整待同步集合，不再仅依赖本页编辑地址 |
| 历史遗留数据 | 进入 Space 时执行幂等规范化并持久化修复 | 保留待同步状态；不会在后台或只读场景静默控制灯具 |

Group Profile 的另一处编辑入口 `GroupAddViewController` 也已接入同一协调器，避免绕过 Profile 页面直接保存造成数据与设备状态分叉。Group 列表和详情删除入口统一使用 `GroupServer` 的领域删除流程。

## 4. 统一拓扑与同步实现

新增的纯值 Reconciler 负责：

- 捕获包含非邻近历史数据在内的完整原始拓扑。
- 规范化 Group Sequence、Group Trigger Zone、Space Trigger Zone。
- 校验容量、成员归属、Relay Number 和最终邻居数量。
- 生成旧、新目标 Plan、受影响候选地址、自动修复和硬错误。
- 保持稳定顺序与稳定去重，便于持久化、云 JSON 和测试比较。

App Lifecycle Coordinator 负责：

- 在真实 `SpaceData`、`Group`、`Node` 与纯值拓扑之间转换。
- 在同一提交边界内完成 Cloud Dirty、GroupInfo/SpaceData 保存和同步缓存失效。
- 根据旧、新 Plan 与 Node 已观测状态生成完整 `NodeSyncData`。
- 把附加的跨 Group 邻近任务并入现有 Sync Device(s) 页面。

`SyncDevicesViewController` 已提取共用邻近任务渲染流程，Profile、成员、删除、Restore、Group Path 和 Space Trigger Zone 不再各自维护不同的邻居计算规则。

## 5. P2 导入、导出、上传与同步修复结果

### 5.1 导入

Space 导入已经改为“预解析与校验后再应用”：

- 在清空或重建真实 MeshNetwork 之前完成 JSON、Profile、成员、引用、容量与最终邻居校验。
- 硬错误直接拒绝本次快照，保留本地最后正确数据。
- 导入返回明确的 applied、skipped 或 rejected 结果；前台 Site/Space 与文件导入入口不会把拒绝误报为成功。
- version 1 要求显式且可解码的 `triggerZones`，空数组表示明确清空；非邻近 Group 不允许携带 Path。
- 无 version 的旧快照在更新已有 Space 时保留本地 `triggerZones`，首次导入才初始化为空数组。
- 导入成功后重新计算完整待同步集合。只有当前 Space 可见、用户可编辑且 Mesh 已连接时，主动前台导入才可进入自动同步；后台、只读和离线状态只保留待同步提示。

### 5.2 导出与文件导出

- Space JSON 显式导出 `proximityLightingSchemaVersion = 1`。
- `triggerZones` 始终显式导出，包括空数组。
- 非邻近 Group 不导出 `proximityLightingPath`。
- 导出前使用与运行时相同的规范化和硬校验。
- 可安全修复的历史引用会先写回本地；发现硬错误时返回失败，不生成看似成功但不完整的 payload。
- Site 导出中任一目标 Space 失败时整体失败，避免文件或上传结果混入空字典。

### 5.3 自动上传与 Cloud Dirty

- 云上传获取 payload 失败时不发送请求，记录同步失败并保留 Cloud Dirty，以便修复后重试。
- 直接上传、文件导出、解绑前导出等调用方均显式处理失败结果并使用已国际化的提示。
- 逻辑拓扑提交和 Mesh ACK 后的 Node 已观测状态更新都可重新排队上传；HTTP 成功不再被解释为灯具已经执行成功。

### 5.4 诊断能力

新增的诊断只输出计数和错误类型，不输出 Auth、设备密钥或完整用户数据：

- 导入 schema、Group/Path/Zone 数量、最大邻居数、自动修复数和待同步设备数。
- 导入硬错误总数及分类。
- 导出 schema 与拓扑摘要。
- 邻近同步任务总数、成功数和失败数。

## 6. 国际化与共享 target

新增三组 English 与简体中文文案：

- 邻近照明拓扑无效。
- 邻近照明导出失败。
- 邻近照明导入失败。

两个新增共享 Swift 文件已加入以下五个 target 的 Sources：SunSmart、Archipelago、Lumineux、SylSmart、SLG Sync Plus。未修改 NordicSigMeshSDK 源码或 Swift Package 锁定版本；当前仍解析到远程 `release` revision `86f5ec9`。

## 7. 自动化与构建证据

2026-09-03 执行结果：

| 门禁 | 结果 |
| --- | --- |
| Path topology persistence contracts | PASS |
| Proximity Lighting topology policy tests | PASS |
| Proximity Lighting lifecycle policy tests | PASS |
| Space Trigger Zone follow-up contracts | PASS |
| Proximity Lighting lifecycle integration contracts | PASS |
| `git diff --check` | PASS |
| SunSmart generic iPhoneOS Debug | BUILD SUCCEEDED |
| Archipelago generic iPhoneOS Debug | BUILD SUCCEEDED |
| Lumineux generic iPhoneOS Debug | BUILD SUCCEEDED |
| SylSmart generic iPhoneOS Debug | BUILD SUCCEEDED |
| SLG Sync Plus generic iPhoneOS Debug | BUILD SUCCEEDED |

构建使用真实 iPhoneOS SDK、generic iOS destination 和关闭签名方式，未使用 Simulator。构建日志仍含工程既有的资源/弃用类警告，本轮未做无关清理。

## 8. 尚未完成的外部与人工门禁

### 8.1 P2-5 服务端契约

当前 iOS 仓库无法实现服务器的字段保留和 revision 冲突控制。发布前必须通过隔离 Site/Space 验证并按需要修改服务端：

- 缺失 `triggerZones` 与显式空数组的合并/替换差异。
- 未知字段是否被原样保留。
- 旧客户端上传是否会删除服务器已有的新字段。
- 相同或更旧时间戳上传是否被拒绝。
- 两台客户端并发上传是否有 revision 冲突，而不是静默最后写入覆盖。

在服务器兼容规则和双客户端黑盒证据完成前，不能宣称 P2 端到端完成。

### 8.2 真实 BLE/Mesh

需要用真实设备逐项读取或重连确认 Enabled、Relay Number 和完整 Neighbors，并覆盖关系两端、单设备失败、重试、App 重启和 Proxy 切换。当前证据只证明 App 生成和持久化了预期任务，不证明灯具已经执行。

### 8.3 UI 手工验收

需要逐项走 Profile、成员、Group 删除、单删/批删/强删、Restore、直接 SAVE、文件导入和服务器同步页面，核对 Devices not synced 集合、自动开始、部分失败与返回重进表现。当前没有真实 UI 布局或交互验收证据。

## 9. 交付状态

- 所有代码和文档改动均保留在当前工作树，未 commit、未 push。
- 未修改 Auth 信息。
- 未格式化或重构无关模块。
- 建议下一阶段先完成服务端 P2-5 黑盒/兼容修复，再执行双客户端、真实 Mesh 与完整 UI 发布验收。
