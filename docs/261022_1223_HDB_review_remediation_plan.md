# HDB Review 五项问题修复方案

日期：2026-10-22。状态：用户已确认，五项修复及约定自动检查已完成。改动仅涉及测试、脚本和文档；未修改 App 生产代码、工程配置或 SDK。

## 结论与范围

五项均需修复。前三项使既有回归无法执行，后两项会向外部团队交付错误的数据和执行条件。它们与此前 Xcode 本地编译列表未包含 Diagnostics 文件的现象不同，App 构建恢复不能关闭这些问题。

工作树为 `feat-HDB-261020`，分支 `feat/HDB-261020`，HEAD `aae4a3e1`；分析开始时无未提交改动，实施开始时仅有本方案文件。采用测试边界修复和文档收敛，保留现行严格新格式，不增加旧 HDB 数据迁移。未提交或推送。

## 实施前证据

| Review 项 | 本轮复核 | 影响 |
| --- | --- | --- |
| 拓扑截取标记 | `check_path_topology_persistence.sh` 在 `private func refreshSummaryCountsFromSpaceMesh` 截取终点处崩溃，退出 133；实际方法已无 `private` | 聚合入口在第一项退出，后续检查未运行 |
| scoped-import 缺 Store 边界 | 直接运行脚本编译失败；缺少 `finishSensorGroupCleanup`、`sensorGroupName`、`pendingSensorGroupAddresses` 所属的 `HDBConfigurationStore` | 导入、删除恢复和归属协调断言不能执行；同时影响上述聚合入口 |
| Site 批量清理缺 SDK 边界 | 用现有 `.local-sdk/nordic-sig-mesh-sdk` 运行，`SiteExtensionStore.swift` 报 `no such module NordicSigMeshSDK` | 协调、清理及真实 SQLite 断言未执行 |
| 摘要与示例过期 | 用当前生产 Codable 与 Policy 验证：摘要 JSON 和三份旧 demo 均在 `devices[0].mac=null` 处拒绝；源码核对还确认缺三个 Model 数组和 `broadcastId`，保留已删除作用域 | 外部生成的数据不可按当前契约读取；摘要旧 Model 范围和阶段顺序也不能继续作为实施依据 |
| Sensor 阶段条件冲突 | 命令清单 §2.3 仍按是否有 Sensor Server 要求地址；生产 `operations` 按 `sensorGroupId` 是否非空生成阶段 | 合法的空地址记录会被按文档实现的网关错误拒绝 |

分析阶段 `check_hdb_configuration.py` 通过，最新 `261021_1806_HDB_unicast_example.json` 通过生产解码、校验和往返。当时 Model 数组测试已覆盖非空 Sensor Model 清单与空地址共存，但未显式放入 Sensor Server；本轮已补该触发条件及选定 Zone 的正常执行路径。

## 1. 修正拓扑测试截取边界

- 修改 `Tests/Group/PathTopologyPersistenceContractTests.swift` 的终点为 `func refreshSummaryCountsFromSpaceMesh`，避免依赖访问修饰符。
- 保留被截取方法的原断言与聚合脚本的失败退出行为；生产方法仍供 HDB Store 调用。
- 先连同第 2 项修好，再运行整个 `check_path_topology_persistence.sh`，确认后续 topology、lifecycle、integrity、scoped-import、recovery receipts 检查都实际执行。

## 2. 补齐 scoped-import 的隔离依赖

修改范围：`scripts/check_proximity_scoped_import.py`、`Tests/Group/ProximityLightingScopedImportTests.swift`，必要时在既有 `DeviceDeletionRecoveryExecutionTests.swift` 补调用边界断言。

- 为三个被生产删除流程调用的 Store 方法提供最小、可控的测试边界。`sensorGroupName` 复用生产方法；待清理集合、完成结果及错误可由夹具设置，每个场景重置。
- 不把完整 Store、持久化和 Mesh 服务依赖全部引入 scoped-import，也不把回收方法无条件写成成功。该套测试仍以生产导入预检、删除恢复、普通拓扑和归属协调为被测对象。
- 同步修正夹具 `SpaceData.hdbGroupAddresses`：复用 `hdb?.allGroupAddresses ?? []`，同时包含 Zone 与 Sensor 地址。当前夹具只包含 Zone，与生产语义不同，属于补齐同一隔离边界的必要一致性工作。
- 保留既有导入/HDB 地址排除与删除恢复断言；补充 Sensor 地址排除及 Store 待清理结果传递的最小行为场景。
- 真实 Sensor Group 回收、引用未清理时保留、删除/保存失败、重试及地址复用，继续由 `check_hdb_integration.py --device-sync` 编译生产 Store 验证。scoped-import 的替身不用于证明这些生产行为通过。

## 3. 恢复 Site 批量清理的独立编译

修改范围：`scripts/check_site_zone_cleanup_batch.py`、`Tests/Site/SiteZoneCleanupBatchTests.swift`。

- 沿用 `check_site_hdb_persistence.py`：生成临时 `SiteExtensionStore.swift`，只移除该测试环境的 `import NordicSigMeshSDK`；保留完整 Store 方法及真实 SQLite 保存点、JSON 编解码和持久化操作。
- 为 `NodeSyncStatusGeneration.invalidate()`、`MeshNetworkManager.instance.meshNetwork`、网络 UUID 和节点 `clearSyncStateCache()` 补齐最小测试对象，复用当前夹具中的 Node/MeshNetwork，避免重名类型。
- 用可观测计数确认普通 Zone 清理不触发 HDB 类型切换失效；类型发生变化时按 Store 分支失效，保存失败不提前更新内存/失效。保留既有批量清理和 SQLite 断言。
- 不删除生产 SDK import，不以空实现替换生产 Store，也不改 SDK。

## 4. 收敛摘要、最终契约和示例

以现有 [Model 数组方案](261022_1116_HDB_device_model_arrays_plan.md) 作为当前数据契约入口，以 [网关命令清单](261022_0945_HDB_site_configuration_commands.md) 作为执行规范，互相链接。继续使用已通过解码的 [完整 HDB 对象示例](261021_1806_HDB_unicast_example.json)。它是 `spaceData.hdb` 的值，不是完整 Space 导入包。

- 将旧 [App/Server 技术摘要](261021_1601_HDB_app_server_technical_summary.md) 明确标记为归档历史快照，顶部指向当前契约；全文不再作为当前对接依据。将其中仍有效的 HTTP 路径、Space payload 包装、同快照 Group/Node 引用、pending/synced 和上传回读要求核对生产代码后合入当前契约。
- 当前契约补齐完整字段表：严格非空规范 MAC；三个 Model 数组必填，空目标用 `[]`；`broadcastId` 固定 65277；`sensorGroupId` 必须存在且可为 null；Lighting Configuration 仅保留设备作用域。撤销旧摘要中的 broadcast 缺省兼容及旧执行顺序描述。
- 三份 `261021_1154_HDB_*demo.json` 移至 `docs/archive/hdb/`，附简短归档说明，明确不可作为当前导入/生成样本；不修改历史 JSON 来冒充新格式。
- 更新引用这些示例的 `261020_1945_HDB_local_occupancy_analysis.md`、`261020_1019_HDB_lighting_zones_design.md`，删除“当前结构一致/最新示例”等过期指引，分别链接历史样本或当前有效样本。对旧设计正文标明历史阶段，不重写全部历史分析。
- 在现有 `check_hdb_configuration.py` 中明确当前完整 JSON 示例清单；如当前契约保留完整 JSON 代码块，将该块也交给生产解码/校验/往返检查。字段片段须标注不完整，不作为完整对象输入。归档样本不计入当前契约的通过数。
- 完整 Space 的 `nodes`、`groups`、UUID、地址和 Model 引用仍须接受生产导入检查；HDB 对象解码通过不表述为完整 Space 或服务端联调通过。

## 5. 同步网关 Sensor 阶段条件

修改命令清单 §2 及其必要前置条件：

- 先验证持久化的三个 Model 清单和地址，再执行 Delete All；任务使用 App 已生成的清单，Model 筛选说明用于解释和校验这些清单。
- `sensorGroupId=null`：跳过 Sensor 阶段，包括设备存在 Sensor Server、`sensorGroupModels` 非空的情况。Zone Set 不分配新地址。
- 地址非空：验证有效地址、无冲突、Sensor 接收清单非空且与模型一致；全部验证在 Delete All 前完成，再遍历 `sensorGroupModels` 逐项 Add。
- Preparation 的 Sensor Group 分配、Sensor Server 订阅和 Presence publication 继续保留在 §1，不与 Zone Set 的空地址放行条件混用。
- 保持四阶段顺序、成功 ACK、失败立即停止和重试从 Delete All 开始的规则。空 Zone 目标仍执行 Delete All 及实际需要的 Broadcast/Sensor 恢复。
- 在既有 `HDBConfigurationTests.swift` 中补显式包含 Sensor Server 的合法空地址场景，验证仍能生成 Reset/Broadcast/所选 Zones，且不生成 Sensor 阶段；同时保留非空地址路径和非法地址拒绝检查。

## 实施顺序与验收

1. 修复拓扑和 scoped-import 边界，完整运行 `bash scripts/check_path_topology_persistence.sh`。独立 scoped-import 可在调试时运行，最终聚合入口结果覆盖其相同代码/依赖版本，无需机械重复。
2. 修复批量清理夹具，运行 `python3 scripts/check_site_zone_cleanup_batch.py .local-sdk/nordic-sig-mesh-sdk`；对照运行 `check_site_hdb_persistence.py`，确认生产 Store 的隔离方式仍一致。
3. 收敛文档和示例、补充精确空地址场景，运行 `python3 scripts/check_hdb_configuration.py`，检查当前文档链接、归档声明和 JSON 引用。
4. 运行 `python3 scripts/check_hdb_integration.py --device-sync`，确认 scoped-import 所隔离的真实 Store 回收链仍有执行证据。
5. `git diff --check`，确认生产代码和正式依赖未变。上述必要检查通过即结束本范围验证。

本范围不修改 Swift 生产代码，按项目规则不为测试/文档修复重复 App 构建。若实施中发现必须修改生产代码，先说明新增原因与范围，再按实际风险补相关回归及一次 SunSmartLocal / SunSmart / Debug / generic iOS 构建。真机和外部联调不属于本次自动验证。

## 独立未完成事项

上一轮已验证本地 workspace 构建成功；正式 `SunSmart.xcworkspace` 仍缺 SDK 已在本地提供的 `updatesLocalState` 与带参数 `isKeybindComplete` API，产生四处编译错误。五项 review 修复不能解决这一发布依赖。SDK 提交/发布与正式依赖更新应单独处理，不在本方案中擅自提交、推送或改绑路径。

外部团队需按收敛后的契约实施并验证合法空地址、四阶段顺序及保存/回读完整性；本任务只维护 App 仓库中的接口文档，不修改固件、服务器或网关代码。

## 实施结果与验证

五项按上述范围完成。拓扑聚合通过首项后还暴露出 `ProximityLightingReviewRegressionContractTests.swift` 的同类旧标记：删除同步入口已通过 `HDBDeviceSyncService.deletionSyncType` 选择任务，测试仍硬编码 `.spaceTriggerZones(datas:)`。已将两处截取起点收敛到控制器构造调用，保留“退出同步页面后再回调、只完成一次”的既有断言；未回退生产任务选择。

| 检查 | 本轮结果及范围 |
| --- | --- |
| `check_path_topology_persistence.sh` | 退出 0，完整执行 topology、lifecycle、review contracts、integrity、scoped-import、删除恢复/批量删除及 recovery receipts；包含 Store 委派、待清理结果和 Zone/Sensor 排除断言 |
| `check_site_zone_cleanup_batch.py .local-sdk/nordic-sig-mesh-sdk` | 退出 0；原批量清理、三个入口、真实 SQLite 重开/失败/恢复及新增类型切换缓存范围和回滚断言通过 |
| `check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk` | 退出 0；真实 Site SQLite 保存/回滚/重载、区域隔离及初始化 receipt 持久化通过 |
| `check_hdb_integration.py --device-sync` | 退出 0；生产 Store/context/planner 的分配失败重试、恢复、Sensor 引用清理及地址复用通过 |
| `check_hdb_configuration.py` | 退出 0；显式 Sensor Server + null 地址、空/非空 Zone、非空及非法 Sensor 地址、新格式严格校验通过；当前示例文件与契约内完整 JSON 均经过生产解码、校验、往返 |
| 归档与文档 | 三份 JSON 与 HEAD 原文件逐字节一致；修改/新增 Markdown 的本地链接有效，旧样本引用已指向归档路径；摘要及历史设计已明确失效范围 |
| 差异边界 | `git diff --check` 通过；生产 Swift、工程和依赖声明无变更 |

本轮未重复 App 构建，未进行真机、UI 或外部联调。SQLite/策略/隔离入口的通过不代表设备、网关或服务器验收通过；正式 SDK 发布依赖仍按上一节单独跟进。
