# HDB 初始化、配置结构与统一同步

更新时间：2026-10-21。用户已确认本方案，App 实施、相关回归与 SunSmart 编译已完成。真机、服务器往返和其他品牌构建不在本轮已通过范围内。

工作树：`feat-HDB-261020`，分支 `feat/HDB-261020`，基线 `d04d226e`。保留未提交改动，不提交、推送或操作真机。仅修改 App；SDK、固件、服务器未修改。

2026-10-21 Lighting Zones 更新已实施：成员仅保留 zoneId，设备级 lightingZonesStatus 记录整轮 pending/synced，统一整设备重试。需要 Sensor 的 Model 及同 element 共享其订阅表的目标 Model 优先 Overwrite sensorGroupId，其他独立表再 Overwrite 首 Zone 或 DeleteAll，最后 Add Zones。初始化参数和 Sensor publication 保持现有流程；不新增 Space 级 Multicast 拦截。当前协议与本轮独立验证记录见 [Lighting Zones 设计文档第 19 节](261020_1019_HDB_lighting_zones_design.md)；本文后续旧验证记录只证明对应历史阶段。

## 已落地的业务规则

只有持久化 `site.isHdbSite == true` 才执行 HDB 初始化和 HDB 同步判定。Standard Site、传统独立 Space 继续原流程；菜单是否可见、`spaceData.hdb` 是否存在都不替代 Site 类型判断。

HDB 添加和恢复流程为：标准任务结束并释放传输资源 → HDB 初始化与必要同步 → 按持久结果结算。已入网设备若任务失败、取消、超时或保存失败，保留设备并提示同步，不再次 provisioning。Classic、Professional、Restore 共用 HDB 完成判定。

HDB Configuration 不再展示独立 Preparation 任务。需要恢复时进入与 Site → Space → Lights 相同的 Sync Device。初始化任务仍由统一同步生成，不能因 UI 不展示 Preparation 而取消必要的设备配置。

目标是设备在没有 Trigger Zones、甚至尚未加入 Lighting Zone 时，完成自身 Sensor publication 与 LC subscription，并在 Auto 下使用两段调光。App 配置链已实现，固件对自身传感事件及 Auto 的实际反应仍需设备验收。

## `spaceData.hdb` 结构

根对象包含 `schemaVersion`、`lightingZones`、`devices`、`broadcast`。

| 位置 | 数据 |
| --- | --- |
| `devices[].sensorGroupId` | 普通功能组地址；不支持 Sensor 时显式 `null` |
| `devices[].lightingZones[]` | 目标列表，成员仅 `{zoneId}` |
| `devices[].lightingZonesStatus` | 整设备订阅配置结果 `pending / synced`，包含空目标 |
| `devices[].lightingConfiguration.<field>` | `{status, value}` |
| `lightingZones[].lightingConfiguration` | 初始 `null`；对该作用域执行 Set 后写入本次字段 |
| `broadcast.lightingConfiguration` | 初始 `null`；对当前 Space 执行 Broadcast Set 后写入本次字段 |

删除 HDB 中的 `sensorGroups`、`devices[].preparation`、根级 `lightingConfiguration`；删除配置的 `values/results` 两层和 `basis/revision/source`。不增加旧 HDB 格式兼容或迁移。

最新示例由生产 Codable 和 HDB 校验器验证；旧快照保留用于历史对照：

- [改动前配置快照](261021_1154_HDB_current_demo.json)：保留旧成员结构，不再适用于当前 schema。
- [已确认的配置示例](261021_1154_HDB_proposed_demo.json)：保留先前文件名，内容与当前结构一致。
- [初始化完成及部分完成示例](261021_1154_HDB_proposed_initial_demo.json)：Zone 和 broadcast 均为 `null`，设备保留默认值和逐字段完成状态。

文件根对象就是 `spaceData.hdb`，不包含外层 Mesh `groups/nodes/keys`，不能当作完整 Site 备份导入。全部为合成数据，不包含真实设备或密钥。示例 Zone 地址为 0xC001～0xC03F，Sensor 地址为 49216（0xC040）；无 Sensor 的设备为 `null`。

## 两种持久状态

只保留 `pending / synced`。

| 操作 | synced 的条件 |
| --- | --- |
| 组播、广播 Lighting Set | 该字段的全部必要消息发送成功并保存结果；无需回读或逐设备 ACK |
| 显式单播 Lighting Set、默认初始化、普通参数同步 | 该字段所有必要 Model 收到匹配的成功 ACK，并保存结果 |
| Zone 全量配置（含空目标） | Sensor/reset/add 全部阶段必要 Model ACK 匹配且最终保存成功 |
| Failsafe Delay、Install Date | App 元数据保存成功 |

发送失败、响应不匹配、超时、取消、未执行均保持 pending。App 通用任务的失败、取消、错误提示仍保留，未将它们改成成功。

Zone Set 先保存完整目标与设备 pending，不保留旧成员。全部阶段成功后置设备 synced；中断、失败和保存失败保持 pending，Sync 整体重发。空目标有 Sensor 时保留 Sensor，无 Sensor 时 DeleteAll，成功后仍保存空数组及 synced。

每个字段独立结算。同一字段有多个 Model 时必须全部完成；某字段失败不会回退其他已完成字段。组播/广播中离线目标的相应记录也按用户确认的“发送成功即 synced”规则更新。

`synced` 表示遵循该次操作的完成规则，不表示实时回读一致。Get 的观测值不会自动覆盖保存的配置意图。

## 默认参数与恢复

创建 HDB 设备意图时即保存默认值，不把 `lightingConfiguration` 强制设为 `null`。

| 字段 | 初始值 | 初始状态 |
| --- | --- | --- |
| lightingControl | Auto | pending |
| dimIntensity | 20% | pending |
| brightIntensity | 80% | pending |
| rampUpTime | 1 秒 | pending |
| rampDownTime | 2 秒 | pending |
| holdTime | 30 秒 | pending |
| failsafeDelay | 5 | 本地保存后 synced |
| installDate | 无 | 用户设置前不生成字段 |

初始化使用现有 LC、Vendor 和配置 ACK 消息，顺序为：

1. Sensor 的自身 LC subscription、Sensor publication。
2. Occupancy Mode=true、T4=0xFFFFFE、manualControl=false、lightAutoAdjustEnabled=false、无限 Manual override timeout 等基础设置。
3. 当前设备保存的亮度、渐变和保持时间。
4. 所有 LC Mode=true ACK，随后 Auto ACK。
5. 保存初始化完成身份；继续必要的 Zone 同步。

LC Mode Set 与 Auto 的 Light LC Light OnOff Set 是不同命令，不能互相替代。初始化的 `lightingControl` 完成判定同时包含 Mode 与 Auto ACK；Mode 失败但后续 Auto 回复成功，仍为 pending。初始化重试以 Auto 收尾，已经 ACK 的数值参数不重复发送。

初始化完整判定还包括基础配置、publication、subscription，不能仅看亮度字段都 synced。运行中的 Force/Auto 或当前亮度不代表初始化成功。

### 最小初始化身份记录

不在 HDB JSON 中保存任务清单。复用现有 `Node.PreConfiguration` 的一个 `hdbInitializationSignature` 字符串：

- 身份基于期望初始化计划、DeviceKey 和 createdTimestamp 的 SHA-256；不保存明文密钥或任务列表。
- `pending:<signature>` 表示该设备实例的初始化意图已持久建立，允许保留部分字段进度。
- 完整 signature 仅在全部初始化 ACK 及持久化成功后保存。
- 保存后读取 SQLite 确认，不能把无数据库或写入失败当作完成。

该字段沿用既有 Node PreConfiguration 导入/导出和存储机制。非 HDB 不生成该值，不改变标准设备的同步判据。

重新配网、地址变化或初始化身份变化时，统一 `prepareIntent` 会保留用户的数值配置，重置硬件字段与 Zone 状态为 pending，并按 Auto 初始化。若 Restore 页面前一次保存失败，普通 Sync 会重新建立该意图并修复地址。

只有当前身份的 pending 意图已经保存，才允许生成/执行初始化任务。准备阶段吞掉的错误仍会在计划入口显式失败，不允许拿旧 synced 参数跳过恢复。初始化部分成功后重试同一个 pending 身份，不重置已经完成的数值字段。

普通参数同步只读取设备最终保存的亮度、渐变、保持时间；不重放历史 Force On/Off，也不无条件切回 Auto。新加入 Zone 不自动继承历史 Zone/Broadcast 设置。

## Sensor 功能组与删除

`sensorGroupId` 使用现有 Site 共用普通 Group 地址池。当前 App 分配范围为 `0xC001..<0xFEFD`；Group 实体保存 `isVirtual=true`。这是 App 的内部功能组标记，不是 Bluetooth Mesh 的 0x8000 虚拟地址或 Label UUID。

删除 `hdbSensorGroupAddresses`、`visibleLightingGroups` 以及为它们增加的专用页面过滤，普通页面继续依靠既有 `isVirtual` 过滤。HDB Lighting Zone 与传统单 Group Profile 的隔离仍保留。

占用和 lux 使用同一个 sensorGroupId：同一个 Sensor Server 实例只配置一次 publication；不同实例分别配置到同一目的地址。仅 lux 能力的 Sensor 也纳入分配和 publication。Sensor Server 不因负责发布而加入 Lighting Zone 的订阅列表，接收感应事件的是 LC。不开启本期以外的 daylight 校准、lux 来源管理或 Lighting Trigger Zones。

分配先保存 Group，再写设备 sensorGroupId。内部 Group 名称包含设备 UUID，使“Group 已保存、HDB 引用尚未保存”的中断可幂等恢复；不新增地址分配注册表。地址不足时保留 sensorGroupId=null 和需要同步，恢复后可再次分配。

删除按现有永久删除语义执行：

1. 在现有 `SpaceDeletionJournal.Entry` 暂存待清理的 sensorGroupId，然后移除 HDB 设备记录。
2. 节点/拓扑删除完成后 journal 的 stage 可进入 cleaned，让剩余设备能正常 Sync。
3. journal 中仍带 sensorGroupId 的项不会因云上传 ACK 被丢弃。Group 继续占用地址。
4. 剩余设备通过普通 Sync 清理已知 publication/subscription，ACK 后再删除 Group、标记 Space 待上传并清除 journal 地址。
5. 没有剩余节点时也执行本地回收。删除、保存失败可再次恢复；清理中的同 UUID Group 不会被新分配直接认领。
6. Group 删除后如持久写入失败，旧 journal 不会清理已复用该地址的新 Group 或新设备引用。

删除地址信息只存在既有临时 journal，不回到 HDB 业务 JSON。Space 删除继续使用整子网删除。离线强制删除沿用现有语义，物理设备的最终复位由实际删除流程/用户完成。

## 作用域更新与一致性

| Set 作用域 | 更新范围 |
| --- | --- |
| Device | 该设备的本次字段 |
| Lighting Zone | 该 Zone 及本次全部有效成员设备 |
| Broadcast | 当前 Space 的 broadcast、全部 Lighting Zones（含空 Zone）、全部适用灯具 |

同一次 Store 更新保存作用域及设备字段，按字段合并。单播不反向修改父 Zone；多个 Zone 重叠时，设备以最后接受的字段意图为准。后续 Sync 只读设备最终值。

硬件写入取得共享传输执行权后，先保存 pending 意图，再发送；保存失败不发送。每字段完成后单独保存 synced。响应校验同时检查设备身份、作用域快照和 Space 更新版本，80→90→80 也不会让第一次的旧回执结束新意图。

空 Zone/无适用灯具的硬件 Set 提前拒绝；本地日期等元数据可保存。权限、AppKey、全部必要 Model、Zone 订阅和广播跨 Space 覆盖继续使用现有前置保护。

批量状态读取复用 `NodeSyncReadContext` 的配置、Site 类型和清理地址缓存，避免逐节点反复读取同一 journal。没有宣称已完成 2000 节点整 App 性能验收。

## 实施与验证记录

本地入口为 `SunSmartLocal.xcworkspace`；SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55`，本轮检查工作树干净，未修改 SDK 或正式依赖映射。

自动化验证使用生产策略、Store、Service、Task、Session 代码；SDK 无线、UI、云端由夹具边界替代。真实 SQLite 检查使用临时数据库，不访问账号数据库。

已验证范围：

- 新 schema、显式 null、默认值、两状态、字段合并、广播/Zone/设备范围传播及 Codable 往返。
- 共用地址池、isVirtual 导入引用、同模型去重、占用/lux 独立实例、无 Sensor、地址不足、分配失败重试。
- 生产 Sync Task 的多 Model 部分 ACK、错响应、旧回执、字段重试、Mode/Auto 顺序、持久保存失败、恢复地址和自定义参数。
- 准备意图保存失败后禁止生成或直接执行初始化；再次同步可恢复。初始化全成功前不会签发完整完成身份。
- 生产添加完成协调器的 Standard 旁路、标准依赖失败、HDB 部分成功、取消、迟到回调、持久就绪判定。
- Zone 加入/退出、失败重试、空 Zone 保留、传输共享、原有控制权限与观察刷新。
- 删除 journal 的上传留存、清理中地址占用、零节点回收、地址重用保护。
- 实际 SQLite 中 Site 类型与 Node 初始化身份保存、重开、读取、删除，及 Node Codable 导入/导出。
- 生产 Sync Session/Coordinator 的写回顺序、停止、重试、补偿、关闭和跨页面执行权。

主要命令入口：`check_hdb_configuration.py`、`check_hdb_device_preparation.py`、`check_hdb_integration.py`、`check_hdb_lighting_configuration*.py`、`check_hdb_lighting_messages.py`、`check_hdb_persistence.py`、`check_hdb_import_recovery.py`、`check_hdb_space_creation.py`、`check_hdb_zone_control.py`、`check_hdb_lighting_zone_execution.py`、`check_hdb_group_lifecycle.py`、`check_hdb_presentation.py`、`check_hdb_control_observation.py`、`check_site_hdb_persistence.py`、`check_sync_execution_session.py`、`check_sync_run_lifecycle.py`、`check_device_permanent_deletion_cleanup.sh`。

最终只读审查发现并修复两项：遗漏 LC Mode 与 Auto 的区别；Restore 保存失败后复用旧 synced 的恢复旁路。均已加入直接行为回归，不依赖源码字符串匹配。

构建：SunSmart、Debug、generic iOS、禁用签名，2026-10-21 最终构建退出码 0，输出 `BUILD SUCCEEDED`。存在既有 weak capture 和 AppIntents 元数据提示，未作为本轮修复范围。五品牌新文件 Sources 归属已核对；其他品牌尚未构建，合入前按项目规则补齐。未操作真机或 Simulator，未执行服务器往返联调。

## 最短人工验收

1. 新建 HDB Site，在不配置 Trigger Zones/Lighting Zone 成员的情况下添加传感灯具。确认标准与 HDB 任务完成后才成功，Auto 下感应进入 Bright，Hold 到期后经 RampDown 进入 Dim，再次感应经 RampUp 回到 Bright。
2. 设置自定义 Bright/Dim/Hold；模拟中断后 Sync，再恢复/重新配网。应保留自定义数值，不回退默认值；未 ACK 字段保持 pending，初始化未完成不得显示添加成功。
3. 在 Zone 与 Broadcast 分别 Set，再单播修改其中一台。检查相应作用域和设备字段更新，单播不改父 Zone；组播发送成功即 synced，无逐设备回读。
4. 删除带 sensorGroupId 的设备。若有其他 Model 引用先提示同步；全部清理后地址可复用，普通组列表不显示 Sensor 功能组。
5. Standard Site 和传统 Space 分别执行添加、Sync、恢复；确认没有 HDB Preparation 或其缺失导致的同步提示，并检查原 Kinetic 功能组行为。

上述真机及最终 UI/云端体验由用户验收，自动化和编译不能替代。
