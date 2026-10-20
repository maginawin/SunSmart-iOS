# HDB Configuration：Lighting Zones 设计与实施记录

- 更新：2026-10-21 15:57；已按用户要求补充第 4 节并实施 FEFD → Sensor → Lighting Zones 的共享计划修复，避免覆盖 FEFD 后被 SDK `isKeybindComplete` 阻断。当前契约见第 4/21 节，根因见第 20 节，本轮验证见第 21.6 节。相关自动回归及 SunSmart generic iOS Debug 构建通过；真机与云端运行验收待用户执行。
- 本轮基线：`feat/HDB-261020`，HEAD `215fe00662d52d7c41d2693e20c999d82914d16b`。除已更新的第 4 节外，第 1–20 节保留历史设计、实施、验证与故障记录；第 19 节 Sensor 优先方案由第 4/21 节 FEFD 优先规则补充修正。未提交或推送。
- 本地 SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，调查时无未提交修改；`.local-sdk/nordic-sig-mesh-sdk` 正确指向该目录。
- 前轮工作流记录保留在下文。本轮按项目轻量执行规则完成 App 修复、回归及构建；未修改 SDK、固件、服务器或运行配置。

## 1. 结论与范围

推荐把 HDB 业务配置保存在云端/导出 JSON 的 `site.space.spaceData.hdb` 对象下；在 App 中对应 `SpaceData.hdb`。使用现有普通 SDK Group 记录消耗 Group 地址池，不设置 isVirtual、不增加隐藏 Group 功能。HDB 的设备多 Zone 关系仍以 hdb JSON 为准，不走普通 Group 的单组配置流程。

用户已确认首期为：通过 Site → Space 添加设备后，在 HDB Configuration 中经现有 Mesh 通道配置设备，并同步至 SunSmart 服务器。MQTT 收发、HDB 平台接入、网关侧 Zone 映射由相应团队后续配套。

本期实现 Lighting Zones；Trigger Zones、Lighting Configuration、Sensor Configuration 仅用于判断订阅需求，不实现这些功能或预建其数据结构。首期配置对象为 Space 中的灯节点；具体 HDB 产品/PID 与固件能力表仍需补充。

用户进一步确认：当前用于协议测试，不使用普通 Group 功能；Get 直接返回保存的 JSON，不读取设备；设备 JSON 包含 nodeAddress 和 mac；App 统一更新，不实现旧版本丢弃 hdb 的兼容机制。

验收目标：每个 Space 独立管理 Zone ID 1–63；一个设备最多期望加入 8 个 Zone；Zone ID 映射并消耗独立分配的 Mesh group address；按“设备 × Zone”保存期望和结果，失败后整 Zone 重试；Get 无设备等待、返回 JSON 配置及已保存的结果；退出重进、同步、删除后关系不丢失。本期不验收普通 Group 与 HDB 的业务混用。

## 2. 协议事实、推导和缺口

依据：[Sample_payload.md](../protocols/HDB/Sample_payload.md) 的 Lighting Zones 示例；[SLP Interface Control Document.md](../protocols/HDB/SLP%20Interface%20Control%20Document.md) §4.1.2.2、§4.1.2.3.1–4（原 PDF p.17–32）。

| 事项 | 已证实内容 | 方案解释 / 未决边界 |
| --- | --- | --- |
| Set | `setLightingZone` 明确只支持单播，`ConfigurationZone=0` | 请求的目的地址是 Node 的主单播地址；组地址放在 Config Subscription 消息参数内 |
| Get | ICD 总则明确所有 Get 按 SensorId 单播；样例也写 Unicast | 协议仍按单设备寻址；App Get 在 JSON 中定位该设备，不产生 Mesh Get 消息 |
| 数量 | 一台 sensor 可分配最多 8 个 lighting zones；字典写 1–8 | 未定义 0、清空、删除的线上契约；App 建议允许 0–8，0 表示清空，由 App 执行退订，不能声称 HDB 平台已经支持 0 |
| ID 范围 | ZoneId 为 1–63；原文为每 gateway 共 63 个 | 按用户需求以 Space 为命名空间。未来必须确认 gateway/Space 对应关系；同一 gateway 若覆盖多个 Space，不能直接用重复 ZoneId 路由 |
| Set 列表语义 | 文档说 assign，未明确增量追加还是整表替换 | 推荐 App Set 接收完整目标列表，计算新增与移除；未来外部接口须确认同样语义 |
| 应答 | Set_Ack/Get_Ack；公共枚举还包含 Set_Error/Get_Error | 协议没有每 Zone / 每 Model 失败数组；App 自己的状态不能直接塞入标准 LightingZones 数组 |
| Trigger Zones | 指触发节点要激活的 lighting zones，且写明命令到 gateway | 后续应引用同一 ZoneId 映射；不等同于现有 SunSmart Space Trigger Zone 的业务含义 |
| 底层实现 | ICD 是 Smart Lighting System 与 SLP 的 MQTT 接口 | 没有规定 SIG Model、Vendor Opcode、订阅表容量或设备持久化行为；这些不能从 JSON 推定 |

样例中的 SenderId、Resourcepath、EventId、尾部空格等只作为文档样例，不作为 App 默认值；Node UUID 也不能直接当作 HDB SensorId。外部身份映射后续单独确认。

## 3. Group 地址占用与最小接入

按用户调整，不采用隐藏 Group。Zone 创建时复用 SDK 分配和普通 Group 持久登记，地址立即从可用池扣除；对应 groupAddress 保存到 hdb。记录创建后不执行普通 Group 的 Profile、单组成员配置流程，也不新增隐藏开关或普通 Group 功能。

- `MeshAPI.createGroup` → `MeshNetwork.add(group:)` → `group.save()` 已可登记地址；分配器与 `getAvailableGroupAddresses` 都依赖 `Group.loadAddresses`。只在 hdb 记地址、却不影响分配器，不算完成地址消耗。
- `MissingGroupSubscriptionCleanup` 需要地址在 `network.groups` 中，才能将其识别为合法订阅；普通 Group 登记也能满足这一点。
- 地址不足复用已有申请/离线不足提示，不预占全部 63 个；创建一个 Zone 消耗一个地址。创建失败不下发，持久登记与 hdb 映射需一致。
- HDB 所有权以 hdb 中的 groupAddress 集合识别，不使用名称或 isVirtual 标志。普通 Group 页面不在本期使用范围，允许这些记录按现有方式显示。

**仍需处理一个实际云同步依赖：** `SpaceSyncCleanupPolicy` 会在普通组订阅交集中发现多个组时抛出 `ambiguousGroupMembership`，ImportData 的 preflight 也会推导普通单组归属。这些是上传/导入自动执行的逻辑，不以用户是否打开 Group 页面为条件。需要按 hdb 地址集合将 HDB 的多 Zone 订阅从普通单组归属推导中排除，同时保留其地址占用和有效订阅；这不增加隐藏 Group 功能，也不扩展普通 Group 业务需求。相关导出的 groupAddress/groupState 应保持一致，不能把任意第一个 HDB Zone 当成普通归属后又在导入时拒绝。

实施前 HDB 菜单只是占位页面；本次已接入实际 site/space。保存/下发/重试复用现有权限、Space 生命周期和恢复保护。所有改动限定为支持本次 HDB Set、JSON Get 与云同步所必需的入口。

## 4. Model 订阅表（已确认）

“加入 Lighting Zone”是让以下五类 Model 订阅映射的组地址。配置 subscription 的 Set 消息发到节点单播地址；本期 App Get 只读 JSON。该集合由用户明确确认，不是 ICD 原文指定的 Model 清单；后续参数命令的具体语义仍需单独确认。

| Model | 标识 | 对应功能与已有证据 | 本期订阅要求 |
| --- | --- | --- | --- |
| Light LC Server | SIG `0x130F` | LC Mode、LC Light OnOff；现有 App 使用 LightLCModeSet、LightLCLightOnOffSet | 必需，已确认 |
| Light LC Setup Server | SIG `0x1310` | LC Property；现有 App 已用它配置亮度档、Fade On/Fade/Run On 等 | 必需，已确认 |
| Sunricher Vendor Server | Company `0x0A78`，Model `0x0001` | 现有 motionSensitivity、manualOverrideTimeout 等走 Vendor | 必需，已确认 |
| Generic OnOff Server | SIG `0x1000` | 接收 Generic OnOff 开关命令 | 必需，已确认 |
| Light Lightness Server | SIG `0x1300` | 接收直接亮度控制命令；HDB dim/bright 档位配置不等于即时亮度 Set | 必需，已确认 |

**补充：FEFD、Sensor 与 Zone 的订阅顺序（2026-10-21，当前修复契约）**

`0xFEFD` 是 SDK 的 `Subelement Broadcast`，用于 App 全体调色温（`LightCTLTemperatureSetUnacknowledged`）和全体 Auto（`LightLCLightOnOffSetUnacknowledged`）。当前 App 在 `SiteViewController` 配置固定订阅要求：非主 element 上的 Light CTL Temperature Server（`0x1306`）与 Light LC Server（`0x130F`）。SDK `isKeybindComplete` 检查参与配置的这些实例；这是本项目策略，不是 SIG 对所有产品的通用强制要求。

为支持设备使用自身传感器，添加初始化为检测到占用或照度传感能力的设备分配 `sensorGroupId`，并将相应 Sensor Server publication 设置为该地址。两种 Sensor 使用同一地址；Sensor Server 负责发布，不因发布而要求订阅该地址。

| Model / 实例 | `0xFEFD` | `sensorGroupId`（已识别传感器并分配地址时） | Lighting Zones |
| --- | --- | --- | --- |
| Light CTL Temperature Server `1306`，非主 element | 直接要求；现有普通初始化配置 | 不因本规则增加 | 不属于本期 Zone targets，保持原有订阅 |
| Light LC Server `130F`，非主 element | 直接要求 | 需要 | 需要 |
| Light LC Server `130F`，主 element | 不因本规则要求 | 需要 | 需要 |
| Light LC Setup Server `1310`、Generic OnOff Server `1000`，与 LC 同 element 且共享订阅表 | 随该表的非主 LC 要求保留 | 随 LC 保留 | 需要 |
| Generic OnOff Server `1000` 的其他实例、Light Lightness Server `1300`、Vendor `0A78/0001` | 仅当实际同表关系连接到要求 FEFD 的实例时保留 | 仅当实际同表关系连接到 LC 时保留 | 需要 |

保护范围由完整 Composition 中的接收者、SDK `relatedModels` 和同 element 条件共同确定，再与五类 Zone targets 取交集。不能仅按 Model ID 字面交集，也不能把跨 element 的扩展关系当成共享列表。两个 Generic OnOff 实例按 element 地址区分。

| 目标订阅表要求 | 首次替换 | 后续追加 |
| --- | --- | --- |
| FEFD + Sensor | Overwrite FEFD | Add Sensor，再 Add 全部目标 Zones |
| 仅 FEFD | Overwrite FEFD | Add 全部目标 Zones |
| 仅 Sensor | Overwrite Sensor | Add 全部目标 Zones |
| 无保留地址，Zones 非空 | Overwrite 第一个 Zone | Add 剩余 Zones |
| 无保留地址，Zones 为空 | DeleteAll | 无 |

执行按阶段推进：先完成全部 FEFD Overwrite，再处理 Sensor（受 FEFD 保护时 Add，否则 Overwrite），然后重置其他表，最后 Add Zones。同一共享表的所有 Overwrite 必须先于其 Add，防止后一个 Model 的 Overwrite 清除前一个 Model 刚追加的地址。所有必要 Model 操作仍需对应成功 ACK，不能以 SDK 关联缓存更新代替设备确认。空 Zones 仍保留必要的 FEFD/Sensor；FEFD Overwrite 到 Sensor Add 之间 Sensor 会暂时移除，失败保持 pending 并按完整计划重试。

添加设备中的 Sensor subscription 仍使用 Add，publication 使用 Publication Set，preparation/initialization 使用 Vendor/LC 参数、Mode 与 Auto Set；只有后续 Lighting Zones 任务与 Set/Apply 复用本全量替换计划。HDB context 仅在 HDB Site 成立，不改变标准 Site 的添加、绑定或普通 Group 同步。也不修改全局 FEFD 策略或放宽 SDK 完成检查。故障前已丢失 FEFD 的设备，通过完整普通 Sync 补回 FEFD 后，再进入修复后的 HDB 计划。

FEFD 不计入最多 8 个 Zone，不作为新的业务配置持久化；同表可能需要容纳 `FEFD + Sensor + 8 Zones = 10` 个地址。容量不足按实际失败处理，保留重试状态，容量和真实控制效果由设备验收。相关 HDB 表仍按已确认全量替换规则清理旧普通 Group/开关订阅，不承诺保留 HDB 与普通业务混用的旧地址。

对于具备占用传感能力的设备，配合二段式调光参数及 LC／Auto 初始化，形成自身感应控制链路；真实感应与调光效果仍需设备验收。只有照度传感能力的设备也会分配 `sensorGroupId`，但不能据此认定其具备占用感应能力。

网关可通过 App 分享的 `hdb.devices[].sensorGroupId` 获取设备已分配的传感器组地址。非空表示 App 已识别传感能力并分配地址；`null` 不一定表示不支持，也可能是分配尚未完成或失败。该字段不能区分占用传感器与照度传感器，也不表示设备初始化已完成。

五类 Model 全部纳入每个“设备 × Zone”的成功判据，不再将 Vendor、Generic OnOff、Light Lightness 作为可选项。设备缺少任一类时显示 Unsupported，不可静默跳过后算成功。Sensor Server、Sensor Setup Server、Config Server、各 Client 及 Scene/Time/Scheduler/CTL/HSL 等不加入本期 HDB Zone 订阅集合；Lighting Zones 更新本身不修改传感器 publication，publication 由上述设备初始化流程配置。

所选 Model 集合是固定配置策略，不是失败任务记录。固件/Composition 变化后，由用户再次 Apply；Apply 将旧 synced 置 pending 并重放当前全部 Model 实例。Get 仍返回历史记录，不检测 Composition 或自动改写状态。完整 Auto/Force/Failsafe、安装日期、光感/雨感参数的 Mesh 对应仍缺少设备侧契约，订阅表本身不解决这些语义缺口。

实施计划按“Node 整台设备加入 Zone”收敛：遍历全部 element，选择五类 Model 的全部实例，按 element address + company ID + model ID 去重。不能固定 element 0，不能只取首个 Generic OnOff / Light Lightness，也不能只按 UInt16 ID 选择 Vendor。不提供单输出选择；如果后续需要分别控制多输出，应作为新的配置粒度讨论。

Model 扩展可能在同一 element 共享 Subscription List；表中“需要覆盖的功能 Model”不等于每次一定要独立写一份物理列表。SDK 也会通过 `relatedModels` 更新关联缓存。应验证实际 element/Model 结果；首次实现允许显式 Add 所有选定 Model，但不得据缓存自动补全就认定设备均已确认。标准依据：[Bluetooth Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)，§1.4、§6.5。

8 个 HDB Zone 不代表固件必然有余量；本轮全量替换后需验证“必要 FEFD/Sensor + 8 个 HDB Zone”的容量。容量不足保留设备 pending 和可重试状态。[Bluetooth Mesh Protocol 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html) 允许实现限制订阅容量。

## 5. 已实施的 hdb JSON

以下为经实施计划确认并落地的数据结构，整体放在 `spaceData.hdb` 下；地址值仅为示例，并非已经分配。

```json
{
  "schemaVersion": 1,
  "lightingZones": [
    { "zoneId": 1, "name": "Zone 1", "groupAddress": 49152 },
    { "zoneId": 2, "name": "Zone 2", "groupAddress": 49153 },
    { "zoneId": 3, "name": "Zone 3", "groupAddress": 49154 }
  ],
  "devices": [
    {
      "nodeUuid": "11111111-1111-4111-8111-111111111111",
      "nodeAddress": 1,
      "mac": "AA:BB:CC:DD:EE:FF",
      "lightingZones": [
        { "zoneId": 1, "desired": true, "status": "synced" },
        { "zoneId": 2, "desired": true, "status": "failed" },
        { "zoneId": 3, "desired": false, "status": "failed" }
      ]
    }
  ]
}
```

| 字段 | 规则 |
| --- | --- |
| schemaVersion | HDB 对象自身版本；首版为 1，不借用已有 timed/proximity schema |
| lightingZones | Space 级 Zone 目录；ZoneId 唯一、1–63；地址唯一且必须为本 Space 可使用的已登记地址，不与其他用途抢占 |
| name | 用户自定义名称；默认显示名通过国际化生成，首期支持重命名 |
| groupAddress | JSON 整数 UInt16；UI 可显示十六进制；SDK export 的地址字符串在边界转换，不混用类型 |
| devices[].nodeUuid | 当前 Space 中的 Mesh Node UUID，作为稳定关联标识；nodeAddress/mac 提供协议测试所需地址信息，不代替 UUID 身份校验 |
| devices[].nodeAddress | 节点主单播地址，建议 JSON 整数（1–32767），与 groupAddress 类型一致；由当前 Node 更新 |
| devices[].mac | 设备 MAC，建议大写冒号分隔字符串；由 Node.macAddress 规范化获得。源数据缺失时保存 null，不伪造地址，不为 Get 额外读设备 |
| desired | true=期望加入，false=期望移除。移除失败必须保留 false 记录，不能删掉重试依据 |
| status | pending=未完成/中断待重试；synced=期望已获确认；failed=本次执行失败。只按设备 × Zone 保存，不保存 Model 任务结果 |

`desired=false` 且退订确认成功后删除该成员记录，无须长期保留成功的退订历史。运行中的进度、Model 回复、错误细节、操作 token 放内存，必要诊断仅 DEBUG 输出。Zone 级 Failed/Synced 由成员聚合，不再额外持久化一个容易失配的总状态；无成员显示 Empty，不能显示为下发成功。

同一设备最多 8 条 `desired=true`，false 的清理记录不计入期望数量，但执行前必须考虑实际仍占用的槽位。Zone 删除时目录项保存可选 `deleting: true`：不再供新选择，保留映射与待退订成员；全部退订确认并保存后删除目录及成员记录，Zone ID 可再次创建。按用户“分配后消耗地址池”的要求，已分配 Group 地址持续占用，首期不回收；再次创建同一 Zone ID 会获得新的 Group 地址。

不预建空的 triggerZones、lightingConfiguration、sensorConfiguration；后续确认结构再增添。保留 schemaVersion 便于明确格式；本期统一升级，不做旧客户端字段保留、降级导出或多版本混用恢复。仍需检查 JSON 类型、引用和地址范围，避免将损坏数据当成空配置。

不存 `NumberOfZone`，从结果数组计算；不存完整 MQTT envelope、Node 副本或 `failedModels`；不把所有成功项再复制到一个 applied 数组。`status` 只表示 App 最近一次执行记录；Get 直接返回 JSON，接受缓存与设备偶有差异，不读取设备进行校验或自动纠偏。

## 6. Set、失败与重试流程

1. 校验当前 Space/节点身份、权限、恢复状态、模型能力、ZoneId、重复项、完整目标列表数量。nodeAddress/mac 从当前节点元数据写入；不能凭旧地址对另一个 UUID 的节点下发。
2. 创建 Zone 时先在合法地址范围分配、登记普通 Group，再保存 hdb 映射；保存失败不发送。已登记地址持续占用，HDB 保存失败或中断也不回收；后续创建跳过该地址，不扫描所有 Group 随意删除。
3. 保存完整目标列表以及移除意图；本次涉及的全部项置 pending，Apply 完整重放当前 Model 实例。更新 Space 修改标记，通过既有云同步机制上传意图；已经有可信基线时，后续临时云失败不应抹掉设备任务或强制重做已成功订阅。
4. 按设备串行执行，先处理移除、再处理新增；特别是 8→8 替换，旧 Zone 退订失败时暂停会增加占用的新 Zone，不能瞬时配置 9 个。
5. 每个 Zone 将相应 ConfigModelSubscriptionAdd/Delete 发送到节点主单播地址，消息参数包含实际 element、Model 和映射组地址。只操作这个 HDB 地址；禁止用 Overwrite/DeleteAll 破坏普通组与其他功能订阅。
6. 使用既有 `SyncSessionCoordinator` / `SyncExecutionEnvironment` / `MeshProxyMessageCommand` 的顺序执行、结果和取消机制；用一个 Zone 聚合其全部 Model 子任务。不要调用普通 nodeAddToGroup 流程，也不要将一批同 opcode 配置直接塞入会去重的普通控制消息队列。
7. 成功须全部必要操作取得有效成功回执；匹配节点、element、Model（含 Company）、group address、操作批次。传输完成本身不是配置成功。部分失败保留该 Zone 的期望并标 failed，其他 Zone 的成功不回滚。
8. 用户 Retry 时对该 Zone 重新执行完整必要 Model 流程，不依赖上次 failedModels。Add 可重放；Delete 即便本地缓存显示未订阅，也应发送明确 Delete 并根据回执确认，避免回执丢失后误判已清理。无需清空再重建全部设备配置。
9. 离开页面/Space、取消、权限变化时停止属于当前任务的发送；保留未完成意图。旧回调不能修改新配置或已删除节点。重启后从 pending/failed 恢复待重试展示，不自动把它们改成功。

HDB 与现有普通同步共用 Mesh 执行资源时必须串行持有执行权，不能同时提交再调用全局 stop。回调校验和数据写入应在同一状态所有者上完成；再次 Apply 会将整个目标集合置 pending 并重放当前所有 Model 实例，因此 Composition 或固件变化后需重新 Apply；Get 不承担设备检测或自动恢复职责。永久删除仍按 UUID 清除成员记录，新 UUID 不继承旧设备配置。

配置下发与云同步两个结果分开：设备成功、云上传失败时显示独立云状态并只重试上传；云成功、设备失败时保留 failed 继续设备重试。不能新增一个“存在 HDB pending 就禁止所有 HDB 操作”的保护，让 Retry 被自己的记录拦住。

## 7. Get：直接返回 JSON

按用户明确要求，Get 从当前 Space 的 hdb JSON 找到设备记录并立即返回，不发 ConfigSIGModelSubscriptionGet / ConfigVendorModelSubscriptionGet，不要求蓝牙连接或设备在线，也不等待服务器请求。页面进入时沿用既有 Space 加载/同步，Get 按当前已加载并持久化的配置快照响应。

- 返回设备的 nodeUuid、nodeAddress、mac 及 lightingZones 记录；pending/failed 记录同样保留，不能只取 synced 后称为“JSON 内容”。
- desired=false 的失败退订记录也返回，并保留其标志；UI 显示为 Removing / Failed，不计入当前目标 Zone 数量。
- Get 是读取操作，不更新 status、不补发 Set、不修正设备实况，也不自动把失败改成功。蓝牙关闭、设备离线、上次 Set 失败都不阻塞 Get。
- 设备已在 Space 内但尚无 HDB 配置时，按该节点已有元数据返回空 lightingZones；只读不自动创建 Zone。设备不属于当前 Space、JSON 损坏则返回对应本地错误，不冒充合法空数据。
- 接受极少数缓存与设备实际状态不一致的情况；界面使用 `Get` / `Saved Configuration`，不称为 Read from Device 或设备实时读回。

App Get 的完整 JSON 与未来 HDB 标准 Get_Ack 是两个输出层次。若将本地 JSON 投影为标准 `NumberOfZone + LightingZones`，建议取 desired=true 的 ZoneId（包括 pending/failed），NumberOfZone 为该列表长度；status 与待退订记录仍在 App 完整数据中展示，不擅自扩展 ICD 字段。该投影表示保存的目标配置，不宣称设备实时结果。外部 MQTT 实现和清空为 0 的格式仍属后续配套。

因此删除原方案中的设备订阅读取、实时差异展示和 SDK“只读订阅观察”扩展。本期没有因 Get 而修改 SDK 的需求；Set 优先复用现有 SDK 消息与回执能力，只有实施时证实缺少必要接口才另行说明。

## 8. 持久化、云同步与关联生命周期

| 链路 | 必须接入的内容 |
| --- | --- |
| SpaceData / 本地数据库 | hdb 对象及 blob 列、幂等迁移、两条 Space load 路径；编码/解码失败不可变成空配置 |
| copy / applyConfigurationState | 复制完整 HDB 配置，避免旧 Space 对象写回覆盖新数据 |
| ExportData / ImportData | 在现有 spaceData 下增 hdb；登记的普通 Group 同步导出/导入；在破坏性替换前校验引用、地址归属、UUID 和 schema |
| 配置快照 / safety / readback | HDB 的 Zone 映射、成员期望、删除意图纳入配置一致性检查；上传快照还需验证 hdb 状态字段确实被服务器保存。执行结果状态变化不应误当作用户修改了期望 |
| 云上传过程中再次修改 | 回执只确认该次提交快照；后来的目标/状态继续保持 dirty，不能被旧回执抹掉 |
| 普通同步 / 清理 | 已登记 HDB Group 是合法已知组；HDB 地址排除于普通单组 membership 推导，不按普通 Profile 生成任务；HDB 的失败重试由 HDB 配置入口负责 |
| 单设备永久删除 | 接入 DevicePermanentDeletionCleanup 的 durable journal、引用清理、readback/replay；UUID 删除后不得把旧意图移交给复用单播地址的新节点 |
| 删除 Zone | 所有残留退订确认后才移除目录，离线设备保留待删除状态；Group 地址始终占用，不提供强制删除 |
| Space 删除/退出/重新导入 | 同时处理 blob、占用组记录、任务所有权及恢复记录；不提前回收仍使用的地址 |
| Space clone | 新 Mesh 身份不能照抄旧 nodeUuid/地址；首期克隆不复制 HDB Zone、设备关系及其占用组，不增加 Zone 模板复制功能 |
| 空 Space | 无设备但有 Zone 目录属于合法配置；检查 SpaceData.isEmpty 使用方，避免被空配置流程误清 |

统一更新所有参与测试的 App，本期删除“旧客户端丢 hdb”的兼容设计、旧版缺字段恢复、降级导出和旧/新客户端往返测试。历史数据库尚无 HDB 列、尚未配置 HDB 的 Space 仍是正常初始化场景，必须支持；这不等同于继续支持旧客户端写入。显式清空仍需先完成未清理的退订意图，损坏 JSON 不能解释为用户清空。

当前版本上传、下载和文件导入导出必须完整保留 hdb、nodeAddress、mac、status 及地址占用；仍需服务器回读验证。服务器若丢字段不能记为成功，失败后复用既有重试。继续使用现有 Space 冲突处理，不额外设计跨版本合并机制。

## 9. 页面方案

- 入口沿用 `Site → Space → More → HDB Configuration`，传入实际 site/space。添加设备完成后用户进入该页面；首期不擅自增加强制自动跳转。
- HDB Configuration 首期只提供可用的 `Lighting Zones`，其他功能后续再加入。
- Lighting Zones 显示 Zone 目录、成员数、聚合状态；支持 `Add Zone`、查看成员、改名及安全删除。
- 设备配置界面选择已创建的 Zone，显示 `0/8` 至 `8/8`；`Apply` 按该设备完整选择集合执行。
- 提供 JSON `Get`、单 Zone `Retry`、`Retry Failed`；失败退订仍可见。批量操作使用相同设备级执行入口。
- 将 `Synced`、`Pending`、`Failed`、`Removing` 与云同步状态分别呈现；Removing 由删除意图推导，不扩充 Model 持久任务列表。
- 使用既有表单/设备选择/同步进度组件；所有新 UI 文案补 English 与简体中文。UI 目前仅 SunSmart 可见；共享存储/导入保护影响其他品牌，不能只改 SunSmart 条件编译内的序列化。

## 10. 后续实施边界与验证

已按用户授权依次完成：数据及地址占用 → HDB Set 任务与 JSON Get → 页面与重试 → 云回执/导入恢复/删除接入。自动化证据及真实运行验收边界见末节。

必要行为验证：

1. 同 Space 1/63 边界、0/64/重复 ID 拒绝；不同 Space 同 ZoneId 但 Mesh 地址不冲突；地址不足与占位保存失败恢复。
2. 同设备选择 1/8/9 个、App 空集合清理、8→8 替换、退订失败后不增加第 9 个；不调用普通 Group 配置流程。
3. 每个 Model 成功/拒绝/超时/ACK 丢失；整 Zone 重试；JSON Get 返回保存的成功/失败/待退订记录且不发任何 Mesh 查询，不自动修正 failed。
4. 多 element、必要 Model 缺失、Vendor ID 匹配、共享订阅列表及真实设备容量；关闭蓝牙/设备离线时 JSON Get 仍可立即完成。
5. 取消、页面退出、切 Space、权限撤销、节点删除、目标再次编辑后的晚回调；重进页面保留 pending/failed；真实 App 重启与 SQLite 回读留人工验收。
6. SQLite 双读取、copy、云/文件/分享 round trip；nodeAddress/mac 正确类型、MAC 缺失及节点重配更新；新建缺失、显式空和损坏 JSON；服务器丢 hdb 或状态字段不能误认上传成功。不做旧版 App 混用回归。
7. 一个设备加入多个普通地址登记的 HDB Zone 后，上传/导入不触发普通单组歧义或误删；分配后地址不可重复使用；设备/Zone/Space 删除与重启重放；跨 Space 隔离。不扩展普通 Group 功能验收。

相关现有验证底座：`check_feature_visibility.sh`、`check_space_sync_cleanup.py`、`check_missing_group_hardware_cleanup.py`、`check_space_protection_snapshot.py`、`check_space_recovery_receipts.py`、`check_space_membership_lifecycle.py`、`check_device_permanent_deletion_cleanup.sh`、`check_space_delete_cloud_restore.sh`。实施时按实际差异选择，不机械全跑；HDB 新行为需补直接行为夹具，不以源码文本匹配替代。

Swift 实施完成后按项目规则运行相关回归及 SunSmart generic iOS Debug 构建一次。若 SDK 公共 API/跨品牌依赖发生变化，稳定后合入前覆盖受影响品牌。本轮执行 generic iOS 编译，不自动真机测试；订阅容量、设备重启保持、真实组命令效果、云端保真与多客户端联调均待运行验收。

## 11. 外部配套与发布依赖

| 责任方 | 契约 / 原因 | 验收方式 / 发布依赖 |
| --- | --- | --- |
| 固件团队 | 确认目标 PID 的 Composition、所需接收 Model、组订阅支持/容量、掉电保持；确认后续 HDB 参数对应 Vendor/LC 语义 | 当前固件上“原有订阅 + 8 HDB Zones”、逐 Model Set 回执与实际组命令效果、掉电保持实测（由设备团队或独立验收完成，不加入 App Get）；不因 App 编译成功就判支持 |
| SunSmart 服务器团队 | 确认当前统一版本的 hdb 对象透传、状态及设备地址信息保留、地址不足申请能力 | 上传→服务器回读→同版本客户端加载；核对 hdb 全部字段及地址占用 |
| 网关 / HDB 对接团队 | Space/gateway 命名空间、ZoneId→groupAddress、SensorId→Node UUID、全量 Set/0 清空、部分失败错误契约 | 后续 MQTT 到 Mesh 端到端联调；本期不实现，不将该配套作为 App 配置完成的既成事实 |

## 12. 当前确认项

已确认：

- 首期 App 配置 + SunSmart 云同步；其他 HDB 配套后续处理。
- 每台设备 JSON 带 nodeAddress 和 mac，同时保留 nodeUuid 关联。
- Get 直接返回 JSON，不读取设备，优先保证体验。
- 本期用于协议测试，不使用普通 Group 功能；不做隐藏 Group，只消耗地址池。
- App 统一更新，不考虑旧版本丢 hdb 的兼容问题。
- Lighting Zones 固定订阅 Light LC Server、Light LC Setup Server、Sunricher Vendor Server、Generic OnOff Server、Light Lightness Server；五类全部纳入成功判据，失败仍只持久化到设备 × Zone 粒度，重试完整集合。

用户要求继续后，实施计划沿用并明确以下默认值：Set 替换完整目标列表，0 表示 App 内清空；nodeAddress 为整数，mac 为大写冒号分隔字符串，未知时为 null；按整 Node 选择五类 Model 的全部实例。目标设备须属于当前 Space 的灯节点且具备全部五类 Model，不预建 PID 白名单。Model 类型集合已确认，不重复询问。上述边界已随下方实施计划审阅，并在用户“在当前会话顺序实施”后落地。

## 证据索引

App 主要文件（路径相对仓库；定位以符号为准）：

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`：HDB 入口与占位 VC。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift`、`DeviceAddViewController.swift`：Space 添加设备真实路径。
- `SunSmart/Common/Data/SpaceData.swift`、`SpaceMembershipCoordinator.swift`、`SunSmart/Common/Data/Database.swift`：模型/配置复制/数据库。
- `SunSmart/Common/Data/ExportData.swift`、`ImportData.swift`：spaceData 与 Group 导入导出。
- `SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift`、`SpaceConfigurationSafety.swift`：配置快照、当前版本上传回读。
- `SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift`、`SpaceSyncCleanupPolicy.swift`：缺组订阅清理与普通 membership。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`、`DevicePermanentDeletionCleanup.swift`：地址回收、状态应用及删除。
- `SunSmart/Main/Group/Controller/GroupAddViewController.swift`：地址申请；`SunSmart/Main/Space/Model/SyncExecutionSession.swift`、`SyncExecutionEnvironment.swift`：执行/重试/取消。
- `SunSmart/Common/Data/Node+MessageHandles.swift`：LC/Vendor 参数消息的当前映射。

SDK 主要符号：`MeshAPI.createGroup/getAvailableGroupAddresses`、`MeshNetwork.customNextAvailableGroupAddress/add(group:)`、`Node.group`、`NodeSubscriptionManager`、`Models.swift` 的 Model IDs/relatedModels、`MeshUtils.swift` 的 CompanyId。

---

# HDB Lighting Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user chooses delegation. Execute task-by-task; checkboxes track completion. 不自动提交 Git。

**Goal:** 在 Site → Space → HDB Configuration 完成 Lighting Zones 的设备配置、JSON Get、失败重试和 SunSmart 云同步。

**Architecture:** hdb 保存 Zone 目录及设备级 desired/status；普通 SDK Group 仅登记地址占用。五类 Model 全部实例组成设备 × Zone 的串行任务，执行层复用现有发送通道与取消机制；Get 读取本地对象，不发 Mesh 或网络请求。

**Tech Stack:** Swift、UIKit、Codable、现有 SQLite 封装、NordicSigMeshSDK、CocoaPods / Swift Package；测试沿用仓库 swiftc 脚本，不创建临时 Xcode 工程。

**Spec:** 本文件第 1–12 节；本节是同一任务的实施计划，不另建重复设计文档。

## Global Constraints

- 当前工作树 `feat/HDB-261020` 单一写入负责人；执行前核对可能变化的 HEAD、未提交差异与本地 SDK 映射。保留其他任务的修改，不自动 commit/push。
- 只做 App 端。优先不改 SDK；不修改固件、服务器、运行配置或部署。Get 不需要 SDK 新接口。
- ZoneId 为 1–63，每 Node 的 desired=true 最多 8 个；地址分配遵守现有 Provisioner 范围与特殊地址保留。
- 五类 Model 为 `0x130F`、`0x1310`、Vendor `0x0A78/0x0001`、`0x1000`、`0x1300`；任一类型缺失均不进入下发。
- Get 返回 JSON，包含 pending/failed/待退订项；不发查询、不改状态、不因设备离线而失败。
- 不隐藏 Group，不增加普通 Group 业务功能；HDB 地址必须占用池，且不参与普通单组归属推导。
- 不做旧 App 混用兼容；保留首次数据库迁移、合法空配置、当前版本坏数据保护与上传字段完整性。
- 新 UI 文案 English / 简体中文齐全；日志仅 DEBUG，不输出凭据。只实现 Lighting Zones，不预建其他 HDB 子系统。
- 不自动真机测试、不使用 Simulator；实施验证按第 10 节，构建与真实设备/云端验收分开报告。

## Review Focus

1. 八个 Zone 替换八个：退订失败不能继续新增超容量，失败清理记录不能丢失；由任务 1、4 的行为测试覆盖。
2. 新 Node 复用旧单播地址：旧回调与旧 JSON 不得应用到新 UUID；由任务 3、4 覆盖。
3. HDB 注册普通 Group 后自动云清理触发：多 Zone 不得引发普通 membership 歧义、Profile 配置或孤儿退订；由任务 2、3 覆盖。
4. 地址登记成功而 hdb 保存失败/进程中断：地址不能再次分配、不能发设备命令或删除无关 Group；由任务 3 覆盖。
5. 云提交后新一轮设备结果到达：旧回执不能覆盖较新的 status/desired，且 pending 不得阻断自己的 Retry；由任务 2、4 覆盖。

## 文件与接口约定

新增文件按职责分开，但同属本功能，不抽象成通用配置框架：

| 文件 | 职责 |
| --- | --- |
| `SunSmart/Common/Data/HDBConfiguration.swift` | Foundation-only Codable 值类型与校验错误 |
| `SunSmart/Common/Data/HDBLightingZonePolicy.swift` | Foundation-only 目标集合、Model 实例选择规则、任务描述、结果聚合与 JSON 投影 |
| `SunSmart/Common/Data/HDBConfigurationStore.swift` | Space 最新对象读取、保存、地址占用、生命周期及云 dirty 标记 |
| `SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift` | 使用现有 SyncSessionCoordinator 的轮次、逐 Zone 执行、取消及结果提交；可注入传输以测试 |
| `SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift` | 当前 Node/Model 与纯任务描述之间的转换，桥接 SyncExecutionEnvironment |
| `SunSmart/Main/Space/HDB/Controller/HDBConfigurationViewController.swift` | HDB 入口、Zone 目录、创建/改名/删除及状态 |
| `SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDeviceViewController.swift` | 设备选择、0/8 目标编辑、Apply/Get/Retry 与 JSON 展示 |

数据类型由任务 1 定义：`HDBConfiguration(schemaVersion:lightingZones:devices:)`、`HDBLightingZone(zoneId:name:groupAddress:deleting:)`、`HDBDeviceConfiguration(nodeUuid:nodeAddress:mac:lightingZones:)`、`HDBZoneMembership(zoneId:desired:status:)`、`HDBSyncStatus`。

值类型使用 UUID、UInt16、Int、String?、Bool 和数组，不引用 SDK Node/Model。UUID JSON 为规范字符串；MAC 缺失编码为显式 null；deleting 默认 false，可省略 false；status 只有 pending/synced/failed。`SpaceData.hdb` 可选：nil 表示尚无配置，实际 Get 可按现有 Node 元数据返回空设备结果。

任务 1 同时定义纯描述：

- `HDBModelTarget(elementAddress: UInt16, modelIdentifier: UInt16, companyIdentifier: UInt16?)`，Hashable。
- `HDBZoneOperation(nodeUuid: UUID, nodeAddress: UInt16, zoneId: Int, groupAddress: UInt16, desired: Bool, targets: [HDBModelTarget])`，Equatable。
- `HDBZoneReceipt(operation: HDBZoneOperation, successful: Bool)`，失败原因只供当次显示，不写 Model 子状态到 hdb。

## Task 1：数据模型与确定性行为

**Files:** 新增上述 HDBConfiguration / HDBLightingZonePolicy；新增 `Tests/HDB/HDBConfigurationTests.swift`、`scripts/check_hdb_configuration.py`。

**Interfaces:**

- `HDBLightingZonePolicy.validate(_ configuration: HDBConfiguration) throws`
- `HDBLightingZonePolicy.replacingZones(_ zoneIds: [Int], for device: HDBDeviceConfiguration, in configuration: HDBConfiguration) throws -> HDBConfiguration`
- `HDBLightingZonePolicy.requiredTargets(from models: [HDBModelTarget]) throws -> [HDBModelTarget]`
- `HDBLightingZonePolicy.operations(for device: HDBDeviceConfiguration, in configuration: HDBConfiguration, targets: [HDBModelTarget]) throws -> [HDBZoneOperation]`
- `HDBLightingZonePolicy.get(_ nodeUuid: UUID, in configuration: HDBConfiguration) -> HDBDeviceConfiguration?`

- [x] 编写失败行为夹具：`testJSONRoundTrip` 检查 nodeAddress=1、mac 与显式 null、failed/desired=false 原样往返；`testReplacementKeepsFailedRemoval` 检查从 1…8 改成 2…9，1 的 desired=false、9 的 pending、期望总数仍 8；`testRejectNinthTarget` 拒绝 9 个、重复与未知 ID。
- [x] 夹具覆盖 `testAllModelInstances`：跨两个 element 的两个 Generic OnOff 均入选，Vendor 公司不符不算第五类，缺一类抛 Unsupported；排序与重复输入结果确定。
- [x] 建立 swiftc runner，运行 `python3 scripts/check_hdb_configuration.py` 确认失败，再实现上述纯函数；策略先删除后加入，不生成任何 Get 消息。
- [x] 运行同命令，所有行为断言通过；Get 的结果含 failed 和待退订项且输入未改变。0 清空只创建退订意图，不直接删除失败记录。

## Task 2：Space 存储、导入导出与云一致性

**Files:** 修改 `SpaceData.swift`、`Database.swift`、`SpaceMembershipCoordinator.swift`、`ExportData.swift`、`ImportData.swift`、`SpaceConfigurationIntegrityPolicy.swift`、`SpaceConfigurationSafety.swift`（均在 `SunSmart/Common/Data/`）；新增 HDBConfigurationStore。测试新增 `Tests/HDB/HDBPersistenceTests.swift`、`scripts/check_hdb_persistence.py`，扩展现有配置快照/回执夹具。

**Interfaces:**

- `HDBConfigurationStore.load(space: SpaceData) throws -> HDBConfiguration`
- `HDBConfigurationStore.update(space: SpaceData, _ mutate: (inout HDBConfiguration) throws -> Void) throws`：主线程读取最新持久 Space、检查归属/权限、校验、保存并更新调用方；失败不得向调用方发布成功状态。
- `HDBLightingZonePolicy.groupAddresses(in payload: [String: Any]) throws -> Set<UInt16>`：供清理、preflight 与配置快照共同使用，nil HDB 返回空集合，坏 HDB 抛错。

- [x] 新增行为夹具验证坏 JSON 拒绝、Store 从最新 Space 修改、保存失败、旧对象保存合并（含最新 nil 清空）及冲突拒绝。首次迁移、两条 load、copy 已接入并静态核对；真实 SQLite 升级与重启回读保留人工验收。
- [x] 扩展 round-trip 夹具：JSON 包含完整 hdb、MAC null、删除意图；当前版本服务器返回丢 hdb/丢 status 时不能确认对应提交。
- [x] 给 Space 表增加可空 hdb blob 和幂等迁移；补两条 load、save 与 applyConfigurationState。实现 Store 的统一持久更新和既有 lastUpdate/云 dirty 机制，不创建新网络上传接口。
- [x] Export 添加 spaceData.hdb；Import 在破坏性替换前验证完整 HDB 与节点/组引用、身份及地址归属。配置快照覆盖 Zone 映射/desired；该次上传回执另检查完整 hdb 字段，包括 status。后到状态不因旧提交回执被标 clean。
- [x] 运行 `python3 scripts/check_hdb_persistence.py`、`python3 scripts/check_space_protection_snapshot.py`、`python3 scripts/check_space_recovery_receipts.py`，断言全部通过。新增依赖需同步补入这些脚本的 swiftc 文件列表。

## Task 3：地址池、普通归属边界与删除恢复

**Files:** 修改 HDBConfigurationStore / HDBLightingZonePolicy；修改 `SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift`、`SpaceSyncCleanupCoordinator.swift`、`ImportData.swift`、`ExportData.swift`、`DevicePermanentDeletionCleanup.swift`、`MeshNetwork+SunSmart.swift`；定向适配 `SunSmart/Main/Group/Model/GroupProximityLightingData.swift` 中的 ProximityLightingTopologyContext，以及 `SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift` 的 HDB 组过滤。新增 `Tests/HDB/HDBGroupLifecycleTests.swift`、`scripts/check_hdb_group_lifecycle.py`。

**Interfaces:**

- `HDBConfigurationStore.createZone(space: SpaceData, zoneId: Int, name: String) throws -> HDBLightingZone`
- `HDBConfigurationStore.markZoneForDeletion(space: SpaceData, zoneId: Int) throws`
- `HDBConfigurationStore.removeDevice(space: SpaceData, nodeUuid: UUID) throws`
- `HDBConfigurationStore.finishZoneDeletion(space: SpaceData, zoneId: Int) throws`：没有未完成成员后移除目录；已分配 Group 地址持续占用，不回收。

- [x] 组合夹具验证连续创建地址不同、保存失败保留已占用地址且不发送；后续分配不复用该地址。跨 Space 地址池共用与地址不足申请路径复用现有 SDK/服务器接口，真实环境留联调验收。
- [x] 复用 MeshAPI 分配并保存普通 Group，`isVirtual=false`；GroupInfo 使用合法默认值以满足现有存储格式，不生成 Profile 下发。失败或中断时已持久占用的地址继续保留，禁止不确定回滚导致重用；仅对已知本次创建、确认未引用且从未下发的记录做安全清理，不扫描删除全网“多余组”。
- [x] `testMultipleHDBSubscriptionsExportImport` 用真实清理/preflight 逻辑验证：HDB 地址属于已知地址，不是 orphan；从普通 membership 候选中排除 HDB；不写成任意第一个 HDB 组，也不将它们作为 Proximity/Profile 业务组。非 HDB 的两个普通组仍须拒绝，不能整体关闭原校验。
- [x] Zone 删除先保存 deleting 与成员退订意图；退订失败保留目录/占用。永久设备删除接入现有 journal 的引用清理及 readback 完成判据。Space 删除清理 blob；Space clone 首期不复制 HDB Zone/设备关系，也不复制无主的 HDB 占用组；空 Space 的 HDB 目录不能丢。
- [x] 运行 `python3 scripts/check_hdb_group_lifecycle.py`、`python3 scripts/check_space_sync_cleanup.py`、`python3 scripts/check_missing_group_hardware_cleanup.py`、`bash scripts/check_device_permanent_deletion_cleanup.sh`。设备删除重放、新 UUID 复用旧地址、合法空 Zone 与非 HDB 校验行为均通过。

## Task 4：Set 执行、重试与 JSON Get

**Files:** 新增 HDBLightingZoneExecutor / HDBLightingZoneService；复用 `SunSmart/Main/Space/Model/SyncSessionCoordinator.swift`、`SyncExecutionEnvironment.swift`、`SyncRunLifecycle.swift`，不复制一套全局发送队列。新增 `Tests/HDB/HDBLightingZoneExecutorTests.swift`、`scripts/check_hdb_lighting_zone_execution.py`。

**Interfaces:**

- 执行器初始化注入 `send: (HDBZoneOperation, @escaping (HDBZoneReceipt) -> Void) -> Void`、`stop: (@escaping () -> Void) -> Void`、`isCurrent: () -> Bool`、`persist: (HDBZoneReceipt) throws -> Void` 和现有 lane；核心不依赖 UIKit/SDK，生产适配在 Service。
- `HDBLightingZoneExecutor.start(_ operations: [HDBZoneOperation], completion: @escaping () -> Void)`、`cancel()`；沿用 coordinator 的轮次与 lane 所有权。
- `HDBLightingZoneService.init(site: SiteData, space: SpaceData)`；`setLightingZones(nodeUuid: UUID, zoneIds: [Int]) throws`、`getLightingZones(nodeUuid: UUID) throws -> HDBDeviceConfiguration`、`retry(nodeUuid: UUID, zoneId: Int) throws`、`cancel()`。

- [x] 用可控传输/持久化夹具先复现：一个 Model 拒绝使整个 Zone failed；重复/晚到完成不重复保存；退出等待中的任务不停止其他 owner；保存结果失败不显示 synced。
- [x] App 的 Mesh 适配遍历 Node 全部 element，解析全部目标实例；为每个 Zone 生成 ConfigModelSubscriptionAdd/Delete，目的为主单播地址。校验每个状态的地址、Model 与 element；空消息数组不得算成功。不调用普通 nodeAddToGroup，不批量塞入控制类去重队列。
- [x] 执行器持有共享 lane，逐 Zone 提交整批 Model，全部 ACK 成功后才 persist synced。失败保存 Zone 级 failed；移除失败保留 false，并暂停本设备的新增操作以避免超过 8 个；其他设备可继续。
- [x] Retry 重建该 Zone 的完整 Model 操作；Delete 不因缓存缺失而跳过。取消后留 pending/failed，校验账号/Space/网络/Node 实例及本轮目标快照；正常 status 保存不使自己的目标快照失效。
- [x] Get 仅加载保存对象及必要的已有节点元数据，含失败项与 nodeAddress/mac，不调用 send/stop/云同步，不改变 hdb。新增 `testGetOfflineMakesZeroTransportCalls`；8→8 失败、全部成功、UUID 地址复用、pending 仍可 Retry、云失败与设备失败分离分别验证。
- [x] 运行 `python3 scripts/check_hdb_lighting_zone_execution.py`、`python3 scripts/check_sync_run_lifecycle.py`、`python3 scripts/check_sync_execution_session.py`，通过后不扩大到无关 Mesh 回归。

## Task 5：页面、交互与项目接入

**Files:** 新增两个 HDB Controller；修改 `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`、`SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings`、`SunSmart.xcodeproj/project.pbxproj`；扩展 `Tests/Config/SpaceMoreMenuTests.swift`，新增 `Tests/HDB/HDBPresentationTests.swift`、`scripts/check_hdb_presentation.py`。

**Interfaces:** `HDBConfigurationViewController.init(site: SiteData, space: SpaceData)`；设备页 `init(site: SiteData, space: SpaceData, nodeUuid: UUID)`。页面只调用任务 3、4 的 Store/Service，不直接构造 Mesh 消息或写数据库。

- [x] 添加显示状态的行为测试：failed 保留可重试、false 记录显示 Removing、0/8 与 8/8、空设备、取消后再进入恢复正确；不为布局新增测试工程。
- [x] 替换占位 VC，沿用现有导航、表单与 cell；目录支持创建、改名、删除，设备页按完整集合 Apply。Get 在本页展示格式化 JSON，可复制，不另建导出文件；不显示 Read from Device。
- [x] 提供单 Zone Retry、Retry Failed，执行期间禁止同设备重复编辑/提交；退出取消当前 owner。进入与每次变更重新检查权限，Get 按已有入口可见性和读取条件执行，不以设备在线性为前提。
- [x] 复用现有国际化 Key，不足时 English / 简体中文同时增加；project 文件由主执行者统一登记源文件和资源归属。功能 UI 仍由现有 SunSmart feature visibility 控制。
- [x] 运行 `python3 scripts/check_hdb_presentation.py`、`bash scripts/check_feature_visibility.sh`，检查五品牌资源/源文件配置。长名称、错误提示、iPad 弹窗和真实点击路径留最短人工验收步骤。

## Task 6：集成验证与交付

**Files:** 更新本文件的实际实施/验证记录，不新增多份总结；按前面任务实际变更维护现有测试脚本。

- [x] 核对前五项行为测试与相关回归均有真实通过记录，组合覆盖“创建两 Zone → Set 部分失败 → JSON Get → Retry → 云回读 → 再进入 → 删除”，测试使用实际生产策略/执行器，替身仅限传输、数据库或服务器边界。
- [x] 实施后再次确认 `SunSmartLocal.xcworkspace`、SunSmart scheme、SDK realpath 未变化。运行一次代表构建：`xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020 CODE_SIGNING_ALLOWED=NO build`。直接查看命令输出，不重定向，不 clean。
- [x] 本计划包含 project 源文件和本地化资源归属变化：稳定后合入前，在同一 DerivedData 串行补构建 Archipelago、SLG Sync Plus、SylSmart、Lumineux（替换同一命令的 scheme）。若没有 Release 条件变化，不追加 Release。
- [x] `git diff --check`，确认仅授权 App/测试/文档改动、正式远端依赖未改绑。不自动安装真机、提交或推送。
- [x] 交付改动结果、实际已跑检查及失败/阻塞；将真实订阅效果、固件容量/掉电保持、服务器往返保真标记待人工/联调验收，不能用隔离测试或构建替代。

## 计划自审与执行交接

已逐项对照第 1–12 节：四项用户调整由任务 1–3 覆盖；固定五类 Model 与整 Zone 重试由任务 1、4 覆盖；页面、云同步及删除闭环由任务 2–6 覆盖。上述五项 Review Focus 均有对应行为夹具。首次无 HDB 与旧 App 混用分开处理；Get 无设备查询；没有固件/后端变更。

用户选择当前会话顺序实施后，由主代理完成业务代码与集成；独立审查代理只读核对。新增检查命令及实际结果见下方记录。


## 13. 实际实施与验证（2026-10-20）

已实现：Zone 创建/重命名/成员查看/删除、设备完整集合 Apply、JSON Get/复制、单项及待处理项重试、退出取消、状态持久化和既有云同步。入口仍为 `Site → Space → More → HDB Configuration`，UI 仅 SunSmart 可见。目录页独立显示当前云上传状态，可下拉刷新；设备状态仍按设备 × Zone 展示。

实现选择：

- 每次 Apply 重放完整目标集合及全部当前 Model 实例；Get 保持纯本地读取。Composition 变化后由用户再次 Apply。
- Group 地址一经分配持续消耗；删除目录不回收地址。登记成功但 HDB 保存失败也保留占用，避免地址再用。
- 复用现有配置快照的完整 HDB 字段比较，状态丢失也拒绝云确认；执行期 freshness 则忽略 status，并在自己的持久结果后刷新基线。
- 数据库 save 使用独立纯函数处理旧对象合并，最新值为 nil 也保留清空语义。Store 只回写 HDB、版本及必要计数，不覆盖当前页面的临时权限/OTA 状态；云任务使用现有 Site/Space 分流。
- 除原计划文件外，补齐 `NodeSyncReadContext`、`NodeSyncTopologySnapshot`、`NodeSyncTopologyStorage` 的 HDB 归属排除，覆盖普通同步的共享读取路径；新增 `HDBConfigurationStore+Mesh` 与 `HDBPresentation` 分离 SDK 边界和纯展示逻辑。

自动化验证：

| 检查 | 结果 / 范围 |
| --- | --- |
| `check_hdb_configuration.py` | 通过：JSON/null、完整替换/清空、数量与引用校验、跨 element Model、再次 Apply 全量重放、Get 保留失败 |
| `check_hdb_persistence.py` | 通过：Store 最新值与失败保存、真实 save 所用纯合并策略、权威 nil 清空、JSON 完整字段比较、云删除投影 |
| `check_hdb_group_lifecycle.py` | 通过：真实清理策略排除 HDB 多组、保留已知地址、普通多组仍拒绝、删除意图 |
| `check_hdb_lighting_zone_execution.py` | 通过：ACK 聚合、退订失败阻止新增、其他设备继续、通道所有权、取消/重复/迟到回执、保存失败 |
| `check_hdb_presentation.py` | 通过：失败退订显示、空选择与 JSON 原样展示；不代表真实布局验收 |
| `check_hdb_integration.py` | 通过：生产 Store/Service/Executor 组合流程；数据库、SDK/传输和云调用为替身；离线 Get 零发送/停止/上传 |
| 既有相关回归 | `check_space_sync_cleanup.py`、`check_missing_group_hardware_cleanup.py`、`check_space_protection_snapshot.py`、`check_space_recovery_receipts.py`、`check_sync_run_lifecycle.py`、`check_sync_execution_session.py`、`check_proximity_scoped_import.py`、`check_node_sync_status_refresh.py`、`zsh scripts/check_device_permanent_deletion_cleanup.sh` 均通过 |
| 可见性与资源 | `check_feature_visibility.sh` 五品牌 Debug/Release 可见性及真实菜单检查通过；project 语法校验与 `git diff --check` 通过 |

独立审查确认并修复三项 P2：直接 topology planner 未排除 HDB、旧对象保存复活已清空的 HDB、相同集合 Apply 跳过旧 synced。分别先复现后通过回归，修复后定向只读复核未发现新的重要问题。

构建使用 `SunSmartLocal.xcworkspace`，本地 SDK revision 未变且未修改。所有构建为 Debug、generic iOS、`CODE_SIGNING_ALLOWED=NO`，共用本工作树固定 DerivedData；不运行 Simulator/真机。沙箱内 Xcode 无法打开有效 workspace，提升构建进程环境权限后正常执行；没有改绑正式远端依赖或清理共享缓存。现有重复 asset / deprecated API / Info.plist 资源等警告未作为本任务扩展修改。

- SunSmart：通过。
- Archipelago：通过。
- SLG Sync Plus：通过。
- SylSmart：通过。
- Lumineux：通过。首次 quiet 构建退出码为 0，但输出含“command failed with exit code 0”诊断；同一代码与依赖进行增量复核，明确输出 `BUILD SUCCEEDED`，退出码为 0。

人工验收最短路径：

1. 更新 App 后进入有灯具的 Space，打开 HDB Configuration，创建两个 Zone，核对 ID、Group 地址和成员页；退出、重启再进入确认 SQLite 迁移及保存读取。
2. 对一台具备五类 Model 的灯 Apply；制造离线失败，检查 Failed、JSON 中 nodeAddress/mac/status；关闭蓝牙点 Get，应立即返回保存内容。恢复连接 Retry，检查完整 Model 订阅及真实组控效果。
3. 配满 8 个后替换一个；退订失败时新加入项不得发送。全清空及删除 Zone 后确认待退订保留到成功、地址不复用；固件断电重启后确认订阅保持。
4. 检查云上传成功后的服务器回读/另一客户端加载是否完整保留 hdb，失败时云状态与设备状态独立；核对长名称、iPad 弹窗和真实点击体验。

未自动验收：真实 SQLite 升级/重启、BLE/网关 ACK、固件订阅容量及掉电保持、服务器实际往返、多客户端冲突和 UI 视觉体验。自动化替身与编译不替代这些证据。MQTT/HDB 平台/网关 Zone 映射仍由对应团队后续实现。

工作树和分支保持原位；本轮不提交、不推送、不合并。

## 14. Lighting Zones 测试控制补充方案（2026-10-20，已确认）

本节记录已确认的补充方案，不改变第 13 节首期实现的验证结论。规划调查时 App HEAD 为 `56cd4dc3`（`feat: HDB lighting zones`），工作树干净。用户确认方案后，基于后续修复提交 `dc38e3cb` 顺序实施；实际结果见第 16 节。

### 14.1 已确认的现有行为

| 操作 | 当前入口 / 实际语义 |
| --- | --- |
| 创建 Zone 目录及组地址映射 | `HDBConfigurationStore.createZone`，分配并登记普通 Mesh Group，再保存 hdb |
| 将设备加入或移出 Zone | `HDBLightingZoneService.setLightingZones(nodeUuid:zoneIds:)`；传入设备的完整目标 Zone 集合，空数组清空其全部成员关系 |
| 删除 Zone 本身 | `HDBLightingZoneService.deleteZone`；标记 deleting，完成全部成员退订后删除目录；已分配地址仍占用 |
| 查看成员 | 当前已支持：点击 Zone → Members；按 hdb 关系列出设备，包括失败与待移除记录 |
| 移除最后一个成员 | 只删除对应成员关系，普通 Zone 目录、名称、Zone ID、groupAddress 保留；仅明确标记 deleting 的目录会在完成退订后删除 |
| 从 Space 永久删除全部设备 | 永久删除及云删除投影按设备身份移除 hdb.devices，保留 lightingZones；空 Zone 可重新加入设备并复用原地址 |

因此，`setLightingZones` 用于增删“设备与 Zone 的关系”，不负责创建或删除 Space 级 Zone 目录。ICD 的命令名为单数 `setLightingZone`，也是给单台设备分配 Zone 列表；App 的复数方法名表达完整列表接口，当前不直接发送同名 MQTT 消息。

用户要求“删光设备后保留 Zone”与当前普通成员移除行为一致。本次增加明确回归保障，不增加自动删除空 Zone 的逻辑。目录中的 `Delete Zone` 与移除成员应使用不同文案；明确删除目录需二次确认，说明空 Zone 本来可以保留并复用映射。

### 14.2 详情页与控制语义

推荐点击 Zone 直接进入详情页：顶部显示名称、Zone ID、Mesh Group Address；中部提供 `Auto`、`On`、`Off`、`Brightness`；下方直接显示 `Members` 与独立的 `Pending Removal`。重命名、删除 Zone 放导航菜单。复用现有成员筛选和设备配置页，点击成员仍进入设备的 Zone 选择页。

成员列表来自 hdb，不以普通 `Group.nodes` 推导业务成员；展示名称、nodeAddress、MAC（缺失显示占位）、订阅状态。desired=true 的 pending/failed 仍显示为成员并标注状态；desired=false 单独列出，不计入成员数。空 Zone 显示 `No devices` 并保留入口；没有任何成员或待移除记录时禁用测试按钮。存在失败或待移除记录时允许测试，显示数量提示：组播实际到达范围取决于设备订阅，部分成功及退订失败的设备仍可能响应。

| UI | 发送消息 | 目标与含义 |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` | Zone 映射组地址；沿用 Group 页 Auto |
| On | `GenericOnOffSetUnacknowledged(true)` | Zone 映射组地址；普通开灯，不承诺固定 100% |
| Off | `GenericOnOffSetUnacknowledged(false)` | Zone 映射组地址；普通关灯 |
| Brightness | `LightLightnessSetUnacknowledged(lightness:)` | Zone 映射组地址；0–100%，复用 `Node.getLightness(lightness100:)` 转换；0 表示零亮度 |

采用真正的组地址发送，不能遍历成员改成逐灯单播，否则无法验证 Zone 组播订阅。保留现有 SDK 普通控制队列行为，不增加逐灯 Get 或回执收集。按钮操作与亮度输入只表示请求；无确认组播不能把设备或成员状态标记为“控制成功”。页面可显示 `Requested` 与本次请求值，不展示为设备实际模式/亮度；这些测试输入不写 hdb、不触发 HDB 云保存，重进页面不冒充实时状态。

Auto 沿用现有动作，不额外写 LC Mode、Profile、传感器参数或手动覆盖超时。LC Light OnOff 与 LC Mode 是不同状态，因此自动照明表现依赖设备已有 LC 配置，订阅成功本身不代表自动策略已配置。标准依据：[Bluetooth Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html) §6.2.3.1、§6.3.5.1、§6.3.5.3。本期不实现 ICD `setLightOverride` 的 Force_On / Force_Off / FailsafeDelay，也不把即时亮度设置当作 `setLightIntensity` 的 DimIntensity / BrightIntensity 配置。

这四项测试直接覆盖 LC、Generic OnOff、Light Lightness 的控制接收。LC Setup 与 Vendor 的完整功能验证需要后续参数命令；四项控制生效不能证明五类 Model 的所有功能均已验收。

### 14.3 复用、边界与修改范围

- 直接复用 `LightGroupControlCommandSender.setGroupOnOff/setGroupLightness`；Auto 按现有 Group 页构造同一消息。在 HDB Service 增加 Zone 控制入口，统一检查最新目录、组地址映射、账户/Space/网络身份及权限，不复用带普通 Profile/单组归属副作用的整个 Group Controller。
- 亮度复用 `DeviceLightControlPanelView` 的亮度部分、节流和数值输入入口，隐藏 CCT；显示的是测试请求值，初始 100% 不触发发送。仅配置现有组件，不改变它在 GroupViewController、DeviceLightViewController 的行为。共享 sender 其他使用方还包括 GroupsViewController、DeviceLightsViewController；本期保持其已有行为。
- 延续 HDB 入口的编辑角色范围，并在每次操作检查实时权限。正在删除的 Zone 禁止测试；当前 Mesh 配置批次忙、连接不可用或身份变化时拒绝新发送并提示。沿用现有消防应急手动控制限制，按已知 Zone 设备核对，不用普通单组归属替代。
- 测试控制不排队到设备恢复在线后补发，不为离开页面调用全局 stop；退出后取消本页面尚未提交的节流动作。已经交给 SDK 的即时消息无法撤回。读取成员/Get 仍可离线进行。
- 最小改动涉及 HDB 目录/详情 Controller、HDB Service/展示逻辑、English/简体中文文案及新增源文件的项目归属；hdb JSON schema、数据库字段、SDK 和服务器接口无需新增。

### 14.4 实施与验收边界

1. 先补控制行为测试：四种动作的消息、参数与目标必须为正确的 Zone 组地址；0/1/50/100% 边界；不向成员单播；测试控制不修改 hdb 或订阅状态、不调用 HDB 云保存；连接/身份/权限/删除/忙状态下不发消息。
2. 补成员及生命周期回归：多 Zone 设备仅移除指定关系；最后一台退订成功后保留目录与原地址；退订失败仍显示待移除；永久删除最后一台设备后保留目录；重新加入使用相同组地址且不新分配；明确删除 Zone 仍遵循原删除流程。
3. 扩展现有 `Tests/HDB` 与 `check_hdb_*` 脚本，必要时新增独立控制行为夹具；使用生产策略/服务与可记录消息的传输边界替身，不通过匹配源码字符串认定功能通过。成员展示覆盖失败、空值、空 Zone、离线和返回刷新。
4. 实施后运行受影响 HDB 回归及普通 Group 控制相关检查；SunSmart generic iOS Debug 构建。若新增文件/资源归属变化，稳定后合入前串行覆盖其余受影响品牌。
5. 人工验证用 A 仅在 Zone 1、B 同时在 Zone 1/2、C 仅在 Zone 2：各 Zone 控制只影响实际订阅成员；亮度边界、普通 On/Off、已有 LC 参数下 Auto 分别验收。再移除最后一个成员、重启/云回读并重新加入，确认 Zone ID 与 Group 地址不变。部分失败/离线时 UI 不得宣称全部设备成功。

## 15. 审查问题修复（2026-10-20 11:48）

该轮仅实施用户确认的五项审查问题。其结束时，第 14 节成员操作与测试控制仍是独立规划；后续实施记录见第 16 节。

### 15.1 行为与边界

| 问题 | 修复与保护 |
| --- | --- |
| 恢复旧云端版本后仍被提升为本地版本 | `SpaceData.save(importingConfiguration:)` 区分校验后的配置导入与普通保存。导入在同一事务内先落所选版本，再允许拓扑协调器普通保存；最终回读同时核对 HDB 和两个时间戳。普通保存继续保护旧对象合并。 |
| 暂存快照与请求 HDB 混存 | 在选择 pending/reviewed 快照并完成规范化后解析、校验 HDB；节点、Group、时间戳及 HDB 使用同一载荷。合法旧格式缺少 HDB 时保持 nil；损坏或 UUID/地址不匹配的所选快照仍拒绝。 |
| 重配地址后重试发往旧地址 | 配网完成入口按同 UUID 迁移 HDB 地址，并将所有订阅/退订状态置为 pending；同地址重新配网也重新确认订阅。历史遗留地址在单项 Retry、全部 Retry 和删除 Zone 执行前补迁移。保存失败不发送，保留原意图供重试。 |
| 损坏 HDB 无法云端恢复 | 普通对象仍不能覆盖损坏行；完整导入校验后的配置可替换该行，包含合法旧格式 nil。导入事务与最终回读仍是提交条件，不放宽权限、网络身份或 HDB 结构/引用校验。 |
| 批量删除重复全网加载 | 每次身份检查只读取一份持久网络快照，用 UUID 索引校验捕获节点。捕获地址和 Device Key 值，发送时再核对操作地址及 Model targets；地址、密钥、节点实例或数据库身份变化后的回执不写入成功。 |

配网迁移失败只记录 DEBUG 错误，保留 HDB 原记录；后续 HDB Retry 可补迁移，不新增永久阻断。恢复不会自动宣称订阅成功，仍需 HDB 重试获得全套 Model ACK。Get 保持只读。

### 15.2 自动化结果

- 7 项 HDB 脚本通过：configuration、persistence、group_lifecycle、lighting_zone_execution、presentation、integration，以及新增 `check_hdb_import_recovery.py`。
- 新增导入夹具执行生产导入准备段与生产 `save` 的版本/损坏数据保护段，覆盖 110→90→95、无 HDB Space、损坏行合法恢复、普通旧对象冲突、pending/reviewed 选择、仅名称/状态变化、非法引用、合法缺字段及不可读暂存。存储、journal 和其他导入策略是边界替身，不代表完整 App 云恢复验收。
- 扩展生产 Store/Service/Executor 集成夹具，覆盖恢复地址后的三类执行入口、同地址重新配网、迁移保存失败、地址/密钥/节点实例变化、数据库已替换而内存未刷新时的迟到 ACK，以及其他 UUID 复用旧地址。
- 相同 30 设备 Zone 删除夹具：HEAD `56cd4dc3` 的 Service 为 **2,730** 次 `MeshNetwork.load`，修复后为 **91** 次，调用量减少约 **96.7%**。基线用 `check_hdb_integration.py --baseline-service` 读取本轮修复前 HEAD 的 Service；该数字只证明隔离夹具内调用量，不代表整 App 主线程耗时。
- 4 项关联脚本通过：`check_space_recovery_receipts.py`、`check_proximity_scoped_import.py`、`check_space_sync_cleanup.py`、`check_configuration_database_safety.sh`。最后一项使用实际 SQLite，覆盖失败事务回滚。
- 关联脚本首次遇到默认 clang ModuleCache 不可写；将 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH` 指向已有可写的 `~/Library/Developer/Xcode/ModuleCache.noindex/HDBTests` 后通过，没有删除共享缓存或改业务代码绕过。
- SunSmart 代表构建通过：`SunSmartLocal.xcworkspace`、Debug、iphoneos、generic iOS、`CODE_SIGNING_ALLOWED=NO`；DerivedData 为 `SunSmart-feat-HDB-261020`。本轮为共享逻辑修复，无新增品牌资源/编译分支，因此没有重复五品牌构建。
- 本地 SDK 仍指向 `one-dev`，revision `8c5af55`，工作树干净，未新增 SDK API 或修改正式依赖。已有 project 与本设计文档的其他未提交改动均保留。本轮未提交、推送或操作真机。

### 15.3 待人工验收

1. 本地版本较新时明确恢复旧云端快照，退出重进，确认不会立即产生错误的待上传；随后导入介于两者之间的新云版本，应正常应用。暂存恢复被中断后，以另一请求版本重试，确认 HDB 名称、状态和节点/Group 仍来自原选定快照。
2. 在测试数据中损坏 HDB 本地 blob，用完整合法云端配置恢复；确认恢复后可重新进入 HDB，普通旧页面保存不能直接覆盖损坏数据。
3. 同 UUID 灯具恢复配网取得新地址后，分别执行单项 Retry、全部 Retry、删除 Zone；核对实际消息地址、五类 Model 订阅和云回读。发送过程中切换/替换节点，确认迟到回执不标记成功。
4. 用真实 30 设备 Zone 删除观察主线程响应及设备退订结果。未进行真机、实际云端、服务器联调或整 App 性能测量，自动化与构建结果不能替代这些验收。

## 16. Zone 详情与测试控制实施（2026-10-20）

基于 `dc38e3cb`（`fix: lighting zones`）顺序实施第 14 节确认方案。开始时工作树干净；所有实现由主执行者写入，只读代理核对结果。仍使用既有 `one-dev` SDK，无 SDK、固件、服务器或 JSON schema 修改。

### 16.1 已实现行为

- 点击 Zone 直接进入 `HDBLightingZoneDetailViewController`：显示 Zone ID、组地址、测试控制，以及分别列出的成员和待移除设备。设备行含名称、节点地址、MAC、订阅状态；点击进入原设备 Zone 配置页。空 Zone 保留目录、映射和名称。
- Auto/On/Off/0–100% Brightness 按第 14 节发送无确认组播，复用现有 sender、亮度控件及换算。亮度行另有数值输入按钮，simple/detailed 均可用。初始 100% 只是输入值，进入页面不发送。
- 每次发送检查最新 Zone 与进入页时的组地址一致，核对账户、区域、Space/网络、权限、恢复保护、Group 登记、删除/配置忙、应急及连接状态。失败/待移除成员可测试；空 Zone 禁止无目标测试。
- 仅显示 `Requested` 与最后请求值，不标记设备控制成功、不改 hdb、不调用 HDB 云保存或成员 Get。页面离开后忽略未提交的亮度回调；已提交 SDK 的即时控制不能撤回，测试控制退出不会停止其他配置任务。
- 重命名及明确删除 Zone 移到详情菜单；删除前二次确认并说明空 Zone 可保留复用。原 `setLightingZones` 完整替换与 `deleteZone` 的目录删除语义保持一致。
- 应急与连接状态变化刷新可见详情页；隐藏页不刷新。应急解除后不再需要退出重进才能恢复控制。

### 16.2 自动化与审查

- 9 项 `check_hdb_*.py` 通过。原 7 项保留，其中 integration 扩展最后成员移除失败/重试、清空后保留两 Zone、重新加入使用原地址、设备清理后目录保留。
- 新增 `check_hdb_zone_control.py`：执行生产 HDB Service 和共享 `LightGroupControlCommandSender`，SDK/连接/数据库/云为边界替身；断言实际交给边界的消息类型、组地址、参数、0/1/50/100%、错误上下文零发送，以及 hdb/云保存/配置队列不变。此证据不等于无线设备接收确认。
- 新增 `check_hdb_control_observation.py`：提取并执行生产页面的观察者注册代码，以真实 Foundation 通知验证应急变化、连接恢复、隐藏页忽略。先复现应急事件未刷新失败，再修复通过；不模拟完整 UIKit 布局。
- `check_hdb_presentation.py` 扩展成员与待移除分组、失败成员保留、按节点地址排序及空 Zone。
- `check_feature_visibility.sh` 五品牌 Debug/Release 可见性与真实菜单回归通过；`check_lights_all_control_cooldown.sh` 通过。新增页面在五品牌 Sources 登记，中英文各 53 个 HDB Key，无重复；project/strings 语法及 diff 空白检查通过。
- 只读审查发现“应急解除后按钮仍禁用”P2，修复并定向复查通过；其他本次确认范围内未发现确定性新增问题。审查不替代真机或服务器验收。

### 16.3 构建与交付状态

使用 `SunSmartLocal.xcworkspace`，Debug、generic iOS、`CODE_SIGNING_ALLOWED=NO`，固定 DerivedData `SunSmart-feat-HDB-261020`，同目录串行编译。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均通过，最终代码均取得明确的 `BUILD SUCCEEDED`。

Archipelago 初次 quiet 构建退出码为 0，但输出含“command failed with exit code 0”诊断；完成页面修复后使用非 quiet 增量构建核对成功。未修改业务代码绕过该诊断，未 clean 或删除缓存。现有 asset 名称、API 废弃、Info.plist 资源警告未扩展处理。

改动保留在当前 `feat/HDB-261020` 工作树，未提交、推送或合并；未运行 Simulator/真机。

### 16.4 人工验收最短路径

1. Zone 1 放入 A/B，Zone 2 放入 B/C；点击 Zone 进入详情，检查失败成员、待移除记录、MAC 缺失及长名称。测试 Auto、On、Off、0/1/50/100%，确认实际响应范围；Auto 使用已有 LC 参数。
2. simple/detailed 两种样式拖动亮度及打开数值输入；拖动后立即返回，确认不再因页面回调补发。断开/恢复连接和触发/解除应急，确认可用性及时变化；页面只显示请求结果。
3. 移除最后一个成员，制造一次退订失败后 Retry；成功后重启并同步回读，确认目录与原地址仍存在，重新加入设备不消耗新地址。明确 `Delete Zone` 则按提示删除目录。
4. 检查 iPhone/iPad 布局、菜单定位与返回刷新。尚未执行真机、真实云往返及 UI 视觉验收；组控效果也不能代替 Vendor/LC Setup 后续参数功能验收。

## 17. 收敛方案：新 Space 预建与 HDB 分段展示（2026-10-20 16:00，已确认）

用户要求先回退扩大后的实施，仅保留本节需求。本轮实施的 44 个已跟踪代码、工程、资源和测试文件已恢复至 `8c2ff5b2`，新增的 5 个文件已移除。此前提交的 HDB 功能保留；回退完成时仅设计文档存在未提交差异。本节替代原第 17 节方案；先前实施期间的测试结果不作为新方案已完成的证据。

### 17.1 明确范围

1. 当前启用 HDB 的 SunSmart 新建 Space 时，一次分配 Zone ID 1–63。
2. 新分配地址从当前 Provisioner 的可用地址中选取，候选为 `0xC001–0xFEFC`，按整个 Site / meshUUID 排除已占用地址后升序取值；不同 Space 不能重复使用同一组号。
3. 旧 Space 不自动补齐、不修改已有映射；保留现有手动新增 Zone 入口。旧 Space 后续手动新增也采用相同的新地址分配规则。
4. 新旧 Space 的 Zone 均不能删除目录；保留重命名、设备成员增删、重试和现有 Auto / On / Off / Brightness 控制。清空成员后仍保留 Zone。
5. HDB Configuration 使用 `Lighting Zones` / `Devices` 两个 segment 切换，默认展示 Lighting Zones。
6. Space 正常删除后，其 Group 地址重新进入同一 Site 当前 Provisioner 的可用地址池。

本期不包含普通 Group 列表隐藏、跨页面 Group 选择器/同步/拓扑改造，也不新增 owner 云删除状态机、初始化日志框架、服务器地址归还接口或 SDK 修改。

### 17.2 最小实施方式

**新 Space 初始化：**

- 在共享的 `SiteData.addSpace` 创建流程接入一个 HDB 批量初始化方法，显式传入新 Space / 子网；复用现有 Group、GroupInfo 和 HDB 数据模型。
- 创建前先计算并检查 63 个可用地址；不足时提示失败，暂不创建 Space。本期不新增自动申请地址的网络流程；旧 Space 手动新增时已有的申请入口继续保留。
- 一次创建完整的 63 个 Group 和 HDB 映射，一次保存 Space，然后沿用现有云同步。不能循环调用会逐项排云同步的 `createZone`。
- 检查保存结果；函数返回失败时清理本次新建的 Space/子网，复用现有删除及其恢复机制，不向用户报告创建成功、不上传半成品。
- 不增加初始化状态字段或 JSON 版本。跨两个数据库的任意进程终止恢复不作为本期新增能力，不能把这次批量写入描述成跨库原子事务。
- 预建只登记目录和地址，不向灯具下发订阅；每台设备最多 8 个 Zone 的现有规则继续有效。

**旧 Space 与目录保留：**

- 保留手动 `createZone`；将它的地址查询改为全 Site 查询，并应用 `0xC001` 下限。已有 `0xC000` 等合法映射照常读取和使用。
- 当前目录少于 63 项时保留新增入口；满 63 项时隐藏或禁用。无需新增“新/旧 Space”标记。
- 删除详情页的 Delete Zone 操作，并阻止服务层新增目录删除任务；`setLightingZones([])` 仍能移除某台灯的全部成员关系。
- 如有旧版本遗留的 `deleting` 状态，只完成已有退订，结束后清除标记并保留目录。这是已有数据兼容，不扩展为新的删除流程。

**分段展示：**

- 复用 `CustomSegmentedControl`，显示 `Lighting Zones (N)` 与 `Devices (N)`，各段只展示对应列表。
- Zone 按 ID 排序，空 Zone 也展示；旧 Space 显示实际数量，设备列表沿用现有规则。
- 返回页面保留当前分段；切换仅更新展示，不发 Mesh Get、不修改 JSON、不触发云同步。
- 保留当前关闭按钮和禁止下滑关闭的行为，使用现有英文/中文本地化 Key，仅按需调整帮助文案。

### 17.3 回收复杂度与必要程度

**建议保留回收，正常流程复杂度低。** 现有 `SpaceData.delete()` 调用 SDK 删除子网，SDK 会删除该子网的 Group；分配器按“当前 Provisioner 获配地址减已登记 Group”计算可用地址，所以正常完成 Space 删除后即可复用，不需要单独的 HDB 地址池或回收服务。

每次新建占用 63 个组号，反复删除重建时复用有实际价值。本期验证的是已有正常删除链的释放与后续复用；不会将它扩大为所有网络超时、进程终止和跨客户端并发情况下的全新自动恢复保证。上云 Space 仍沿用已有“云删除成功后再本地删除”的次序。

与 63 个组直接相关的一个必要小修正：现有 editor 解绑额度计算使用 `32 - usedGroupAddresses.count`，应限制结果不小于 0，避免传入负的 `suffix` 长度。只修正这个边界，不重构解绑/回收流程。

### 17.4 改动与验证边界

预计业务改动集中在 Space 创建接入、HDB Store/Service、HDB 首页和 Zone 详情页；如需更明确的地址不足提示，再小幅调整创建入口。复用已有文件和机制，不修改普通 Group 页面、Scene/Schedule/Trigger Zone 消费者、共享云同步管理器或 SDK。

必要验证：

- 新 Space 正好 63 项，映射来自合法获配范围；同 Site 两个 Space 不重号；地址不足时无成功 Space、无半成品上传。
- 已有 Space 不自动变化；手动新增仍可用，分配不占用其他 Space 已有组号；Get 保持只读。
- 保存失败走本次创建的清理；正常删除 Space 后，新建 Space 能复用释放的地址。
- Zone 目录不能删除，最后一个成员移除后仍保留；旧待退订状态完成后保留目录。
- segment 切换、返回保持、63 项滚动和空设备列表；现有控制/成员功能继续可用。
- 只针对上述行为扩展现有 HDB 回归，运行受影响的相关检查及 SunSmart generic iOS Debug 编译。真实分段体验、设备响应和完整云回读由人工验收。

用户已确认实施。本轮按上述范围顺序实现，验证结果记录于本节下方。

### 17.5 本轮实施与验证（2026-10-20 16:14）

已按收敛范围完成 8 个业务/本地化文件的修改，复用既有工程文件与 SDK API：

- `SiteData.addSpace` 先检查当前 Provisioner 在整个 Site 的可用地址，再创建新子网并一次初始化 63 个 Group / GroupInfo / HDB 映射。显式绑定新子网，不切换当前打开的 Space；Space 保存成功后才返回并由原 UI 入口排云同步。地址不足和保存失败返回本地化错误，失败清理调用原有 `SpaceData.delete()`。
- `createZone` 保留旧 Space 手动新增，采用相同全 Site 查询与 `0xC001` 下限。HDB schema 与旧合法映射不变。
- HDB 详情不再提供目录删除，服务拒绝新增删除任务；历史 `deleting` 完成退订后保留目录。成员清空、设备移除均不删除 Zone。
- HDB Configuration 默认显示 `Lighting Zones (N)`，可切换 `Devices (N)`，进入详情返回后保持选择。切换不调用 Mesh Get，不保存 HDB；63 项时禁用新增。
- 正常 Space 删除复用既有 SDK 子网删除，地址回到同 Site 当前 Provisioner 的可用池；editor 解绑未用组额度计算加下限 0。

验证记录：

- 新增 `check_hdb_space_creation.py`：编译实际 Space 创建/删除方法与 HDB Store，SDK、数据库和云边界使用夹具。已覆盖 63 项/顺序/范围/去重、两个 Space 不重号、旧 Space 手动新增、地址不足不创建子网、Group/GroupInfo/Space 保存失败清理及重试、正常删除后复用、非 HDB 品牌保持空 Space。实施前用例确认失败于“新 Space 没有 63 项”。
- 既有 9 项 HDB 检查通过：configuration、persistence、group_lifecycle、import_recovery、lighting_zone_execution、integration、presentation、zone_control、control_observation。integration 与 zone_control 按新目录保留语义补充用例，仍覆盖 5 个 Model、失败重试、只读 Get 和原控制命令。
- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 编译返回 0。Xcode 构建记录为 0 errors、74 warnings；未修改工程或新增品牌编译分支，本轮使用 SunSmart 代表共享代码编译。
- English / 简体中文 strings 的 `plutil -lint`、`git diff --check` 通过。SDK `one-dev` 仍为 `8c5af55`，无差异。

隔离测试不证明实际 SQLite 跨库原子性、云端回读或真实灯具响应。人工验收最短路径：

1. 同一 Site 连建两个 Space，分别进入 HDB Configuration，确认各 63 项、默认 Zones、两段计数正确、地址不重号；进入 Devices / 详情再返回，确认分段保留及列表滚动正常。
2. 旧 Space 手动新增 Zone，确认原映射未改变；测试成员添加/移除、Auto/On/Off/Brightness，清空成员后目录仍在且没有 Delete Zone。
3. 删除一个测试 Space 后新建，确认可复用释放的地址；同步后重新加载，核对服务器回读的 `spaceData.hdb`、Zone 名称与组映射。

未执行真机安装运行或服务器联调。独立只读审查未发现可确认的 Critical / Important / Minor 新问题；已交叉核对真实 SDK 分配、Group 保存与正常子网删除链。63 组初始化的真实主线程耗时尚无 trace，不作性能验收结论。

## 18. 当前实现的容量与地址分配补充分析（2026-10-20 15:31）

本节保留当前实现的容量与影响核对，尚未实施默认预建。核对基线为 App `feat/HDB-261020` / `8c2ff5b2`、本地 SDK `one-dev` / `8c5af55`，两者调查开始时工作树干净，`SunSmartLocal.xcworkspace` 映射正确。以下 `0xC000` 起点、手动增删与普通 Group 展示描述的是基线实现；后续只实施第 17 节的收敛范围。本节中的其他联动分析保留为调查记录，不代表本期实施清单。

### 18.1 结论与容量

63 个空 Zone 的地址开销通常可接受，但不能据此认定对整个 App 的 Group 无影响。当前代码仍按需逐个创建；改为默认预建之前，必须处理已发现的跨 Space 地址分配问题，并明确普通 Group 展示和空 Space 引导的变化。

| 范围 | 当前代码依据与含义 |
| --- | --- |
| App 业务可分配地址 | HDB 使用 `0xC000...0xFEFC`，共 16,125 个；`FEFD/FEFE/FEFF` 为既有特殊用途。63 个约占 0.39%。 |
| 本地 SDK 新 Site 默认获配范围 | `MeshNetworkManager.createMeshNetwork` 默认 `0xC000...0xCC9A`，共 3,227 个；首个 Space 预占 63 个后剩 3,164 个。只计 HDB 可容纳 51 个完整的 63-Zone Space，余 14 个，但普通组、开关通讯组等还会占用。 |
| 实际账号额度 | 导入会按服务器 `ownerGroupsAddress` / provisioner 覆盖范围，因此 3,227 不是线上承诺；没有本次真实服务器额度样本。现有不足申请入口每次请求 16 个，批量预建需要按实际缺口处理。 |
| 地址隔离范围 | 同一 Site 的 Space 共用 `meshUUID` 和 Provisioner 地址池；不同 Site 的池独立。不是整个账号/App 共用一个全局池。 |
| 设备容量 | 预建空目录不发送订阅消息，也不让每台灯订阅 63 个组；现有 App 每设备最多期望加入 8 个 Zone。真实固件订阅余量仍需设备验收。 |

### 18.2 必须先处理：HDB 分配范围与数据库唯一性不一致

当前调用链：

1. `HDBConfigurationStore+Mesh.swift` 的 `createZone` 使用带 `subnetworkId` 的 `getAvailableGroupAddresses`，自行取首个地址并传给 `MeshAPI.createGroup`。
2. SDK `MeshAPI.getAvailableGroupAddresses` 从整个 Mesh 的 Provisioner 获得范围，但 `Group.loadAddresses` 按传入 `subnetworkId` 只排除当前 Space 的已用地址。
3. 普通 Group 的默认分配器 `customNextAvailableGroupAddress` 则调用不带子网参数的 `Group.loadAddresses(meshUUID:)`，会排除整个 Site 已使用地址。HDB 显式传入地址绕过了这层全 Site 排除。
4. Space 进入流程按子网加载 `MeshNetwork`；`MeshNetwork.add(group:)` 的重复检查只看该内存网络中的 groups。
5. SDK `groups` 表唯一键是 `(meshUUID, groupAddress)`，保存使用 `INSERT OR REPLACE`，唯一性不包含 `subnetworkId`。

因此，在同一 Site 中 A 已持有 `C000`、B 尚无组且使用同一获配范围时，B 的 HDB 创建仍会选中 `C000`。在正常的按 Space 加载上下文中，A 不在内存重复检查范围，保存 B 可替换 A 的数据库 Group 行；若内存恰好包含 A，则会报组已存在。这个问题不是容量不足，即使只创建一个 Zone 也可能触发，默认预建 63 个会扩大影响。

建议在 App 的 HDB 共享创建入口按整个 `meshUUID` 排除已占地址，保留当前 Provisioner 范围、特殊地址过滤及目标 Space 归属检查；默认预建与手动创建应复用同一规则。无需为此修改固件或服务器，也不应先扩大 SDK 通用接口的行为范围。已经形成冲突的数据需另行核对有效快照，不能仅改分配器后声称历史数据已恢复。

### 18.3 其他已确认联动及实施边界

- **普通 Groups 列表与计数会增加 63。** HDB 当前登记为 `isVirtual=false` 的普通 SDK Group；`MeshNetworkManager.groups` 没有排除 HDB，`GroupsViewController.updateUI` 使用该数组显示并保存计数。按现有“不隐藏 Group”的设计，这些 Zone 会显示出来；尚未验收普通 Group 业务与 HDB 混用。
- **新 Space 不再满足空配置条件。** `SpaceData.isEmpty` 同时检查 HDB 目录及 groupCount；`SpaceViewController.configurationFlowGuidance` 依赖该条件，预建后原先的空 Space 配置引导不会自动出现。
- **删除和重建会继续消耗地址。** 当前明确删除 Zone 只移除 HDB 目录，Group 地址不回收。后续初始化必须幂等，不能每次进入/重启重建，也不能把用户主动删除的 Zone 自动补回。
- **创建入口不能直接循环现有 `createZone` 63 次。** `SiteData.addSpace` 只创建子网和 Space，并不保证当前全局 Mesh 上下文已切到新 Space；现有 `createZone` 要求当前上下文完全匹配。每次 `update` 还会落库、更新时间和排入云同步。需要明确新 Space 上下文，批量完成地址登记和 HDB 保存，避免形成 63 次独立业务提交；中途失败必须保留已占用地址并支持按现有目录继续补齐。
- **持久化、导入导出仍须保持成对记录。** 既有清理和导出已按 HDB 地址排除普通单组归属推导，不能只写 63 条 JSON 而不登记 Group。初始化完成后 Group 列表、hdb 映射和摘要计数必须一致，再进入既有 Space 云同步；不得将部分初始化伪装成完整成功。

实施时最小验证应覆盖：同 Site 两个 Space 的地址互斥及 A 的记录不变、已有普通/虚拟 Group 保留、额度不足/申请失败、中途持久化失败后的恢复、重复进入不重复占号、空 Zone 云往返，以及普通 Groups 展示和引导的预期变化。仅预建目录不应有设备订阅下发。

本轮完成源码核对及独立内存 SQLite 演示：使用相同唯一键、按子网查询和 `INSERT OR REPLACE` 时，B 的 `C000` 行会替换 A。该演示只验证数据库语义，不是完整 App/SDK 集成复现；未修改生产代码、未执行 App 构建或真机/服务器验收。

## 19. Lighting Zones 全量配置（2026-10-21，已实施）

本节为前轮 Sensor 优先实现记录。涉及 FEFD 的起点、阶段顺序、临时 Sensor 缺失与容量要求，以第 4/21 节为准；设备级 pending/synced、完整重试和其余范围继续适用。

### 19.1 调整结论与用户已明确的边界

**已实施调整后的方案：Sensor 地址作为需要保留它的订阅表的 Overwrite 起点；其他订阅表以首个 Zone 或空列表为起点；最后 Add 目标 Zones。只持久化设备级 `lightingZonesStatus`，成员对象仅保留 `zoneId`。** 这样可删除成员增删差集、成员状态、逐 Zone 重试及清空后的 Sensor 补回阶段，空目标也有明确的待同步状态。

用户本轮明确：

- 需要 sensorGroupId 的 Model，永远先 Overwrite sensorGroupId，再 Add 全部目标 Lighting Zones；目标为空时只保留 Sensor。
- 不需要 sensorGroupId 的 Model，非空目标以第一个 Zone 的 group address Overwrite，再 Add 其余 Zone；空目标直接 DeleteAll。
- 删除成员 `desired` 和 `status`；`lightingZonesStatus` 只有 `pending/synced`，待同步时完整重发，不保留单 Zone 重试。
- 接受无法准确识别仍可能响应旧 Zone 的设备，由人工测试发现后重新配置；不采用上一版建议的 Space 级 pending → Multicast 拦截。
- 旧测试项目会删除重建，不做旧 HDB 格式迁移、旧移除意图恢复或新旧格式往返兼容。本次已按确认方案实施 App，不新增旧格式恢复分支。

必须补充一项实现约束：**“需要 Sensor”要包含与 Sensor 接收 Model 共享同一订阅表的相关目标 Model。** 只按 Model ID 把 LC 归为 Sensor、LC Setup 归为非 Sensor，会在后续 Overwrite/DeleteAll 时再次清掉 Sensor，违背本轮目的。该处理是沿现有模型关系生成临时计划，不新增持久化共享表结构。

### 19.2 实施前链路与对应改动

| 核对项 | 当前事实与调整方向 |
| --- | --- |
| 持久状态 | `HDBSyncStatus` 已只有 `pending/synced`。本次新增设备级 Zone 状态，删除 `HDBZoneMembership.desired/status`，不是新增第三种状态。运行任务的失败/取消错误提示保留。 |
| 目标生成 | `HDBLightingZonePolicy.replacingZones` 当前保存旧/新 ID 并集；`operations` 依赖成员状态，先 Delete 后 Add。改为只保存完整目标，生成不依赖旧成员的计划。 |
| 两条执行链 | Apply 使用 `HDBLightingZoneService/Executor`；普通 Sync、添加与恢复收尾使用 `HDBDeviceSyncService/Task`。二者必须复用目标分类、命令编码、ACK 和整轮结果语义。 |
| Sensor 接收者 | `HDBDevicePreparationPolicy.plan.subscriptionTargets` 当前为全部实际 LC `0x130F`；Sensor publication 使用设备自己的 sensorGroupId。保留此接收策略，再计算本轮其他目标 Model 是否共享它的订阅表。 |
| 共享订阅表 | SDK `Model.relatedModels` 提供模型扩展关系；`ConfigurationClientHandler` 将订阅修改同时应用于同 element 的相关 Model。LC Setup `0x1310` 扩展 LC，LC 扩展同 element 的 Generic OnOff，不能独立设置互相冲突的起始地址。 |
| 同步及重试 | `needsSync` 当前只看成员 status；`SyncRetryPolicy` 默认保留成功任务。前者改看设备级状态，后者在 HDB Zone 重试时重置本设备全部 Zone 阶段，保留成功且无关的初始化/参数任务。 |
| 消费者 | Presentation、首页成员计数、详情页、Lighting Configuration 成员查询和组播检查均依赖 `desired/status`。全部改为目标成员 + 所属设备的整体状态。 |
| 目录与旧兼容 | 目录当前禁止删除；`deleting/deleteZone/retryLegacyRemoval` 仅用于旧移除意图。无旧数据兼容要求后移除这些直接关联的分支，清空设备成员仍保留目录及地址。 |
| 持久化链 | Codable → Store → Space blob → 导出/云快照 canonical → ImportData/readback 必须完整保留新设备状态和目标列表。无须新增 SQLite 列、服务器 API 或持久任务表。 |

### 19.3 数据契约：一个状态来源

非空目标完成后的设备字段：

```json
{
  "lightingZonesStatus": "synced",
  "lightingZones": [
    { "zoneId": 1 },
    { "zoneId": 2 }
  ]
}
```

空目标尚未完成：

```json
{
  "lightingZonesStatus": "pending",
  "lightingZones": []
}
```

规则：

1. 数组仅表示目标，0–8 个不重复且存在于目录的 Zone ID；保留对象数组结构，不擅自改成整数数组。按 ID 升序保存和执行，Mesh 命令使用目录映射的 group address。
2. `lightingZonesStatus` 是这一设备整轮订阅配置的唯一持久状态，覆盖 Sensor 起始配置及全部 Zone 配置。成员不再保存 `desired/status`，也不另存旧列表或每 Model 任务结果。
3. 每次显式 Set/Apply 都先保存完整目标及 pending，即使目标与上次相同、上次已 synced，也完整重发。这保留了人工发现设备实际状态不符后再次 Apply 的恢复入口。
4. 普通 Sync 根据设备级 pending 判断是否需要生成整轮 Zone 任务；新设备首次建立意图、恢复配网及初始化身份变化时置 pending。判断 HDB 设备整体是否需要 Sync 时，仍保留既有初始化、Sensor publication、Lighting Configuration 等独立待办检查，不能被这一个字段替代。
5. 所有必要 Model 的全部阶段 ACK 校验和保存成功后，才将设备级状态置 synced。任何失败、取消、中断或成功状态保存失败都保持 pending；不保留部分 Zone synced 的中间结果。
6. 空目标成功后仍保存空数组及 synced。有 Sensor 的设备保留 Sensor 订阅；无 Sensor 的设备清空相关订阅。两者都能在重启后区分成功和待重试，不使用虚构 Zone 占位。
7. Get 只返回保存值，不读取设备、不改状态、不自动纠偏。`synced` 是本次配置确认结果，不能代表之后设备状态永不变化。

### 19.4 Sensor 优先的目标分类和消息顺序

本轮再次核对：本地 SDK `one-dev` 为 `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，工作区干净，`.local-sdk` 映射正确；现有 SDK 已有 Overwrite/DeleteAll/Add 及公开的 `relatedModels`，本轮只修改 App，SDK 保持该 revision 且无差异。

**计划生成：** 以五类必要 Model 的全部实际实例为 Zone targets，复用 preparation plan 的 Sensor subscriptionTargets 作为接收者。对每个接收者使用 SDK 关系，限定同一 element，找出本轮会修改同一订阅表的目标 Model，统一列入 Sensor 保留集合；剩余目标为独立的非 Sensor 集合。必须基于完整 Composition 计算关系，再筛选本轮 targets，避免漏掉经其他模型连接的扩展关系。不能仅凭“设备有 Sensor”让不同 element 的所有 Model 都订阅 Sensor。

只有设备确实不支持 Sensor 时才使用无 Sensor 分支。支持 Sensor 但 sensorGroupId 尚未分配、地址无效或计划缺失时，沿既有初始化/分配流程恢复，暂不发送本轮覆盖；不能将缺失数据当作无 Sensor 而 DeleteAll。

| 目标 Model 所在订阅表 | Lighting Zones | 起始命令 | 后续命令 |
| --- | --- | --- | --- |
| 需要保留 Sensor（直接接收或与接收者共享） | 空或非空 | Overwrite sensorGroupId | 对全部目标 Zone 执行 Add；空目标无 Add |
| 不需要 Sensor | 非空 | Overwrite 第一个 Zone 的 group address | Add 其余 Zone |
| 不需要 Sensor | 空 | DeleteAll | 无 |

以同 element 的 LC / LC Setup 为例：如果 LC Overwrite Sensor 后再对 LC Setup Overwrite Zone 1，Sensor 会消失；LC Setup DeleteAll 也会清空 LC 的 Sensor。因此两者均以 Sensor 为起点，再 Add Zone。与 LC 不同 element、没有同表关系的 Lightness / Vendor 等仍按非 Sensor 规则处理。SDK 无法表达未知 Vendor 扩展关系；这部分不能凭 App 源码推定固件一定独立，需要目标设备验收。标准共享规则见 [Mesh Protocol 1.1 §4.2.4](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html)。

整台设备按三个阶段串行：

1. **Sensor 起始阶段：** 对 Sensor 保留集合全部目标 Overwrite sensorGroupId，取得匹配的成功 ACK。
2. **其他订阅表起始阶段：** 对剩余目标执行首 Zone Overwrite 或 DeleteAll。由于已排除与 Sensor 共享的目标，这一阶段不会按已知共享关系删除阶段 1 的 Sensor 地址。
3. **Zone Add 阶段：** Sensor 保留集合 Add 全部目标 Zones；非 Sensor 集合 Add 第二个及后续 Zones。所有 Overwrite/DeleteAll 必须早于本阶段，避免后一个覆盖清除前一个 Add。

仍对每个必要目标 Model 下发并校验，不利用共享列表跳过必要 Model 的 ACK。对共享 Sensor 表重复 Overwrite 同一 Sensor 地址是相同目标；它不会用 Zone 地址替换 Sensor。分阶段是内存执行计划，不形成新的持久状态机。

**失败语义：** 每个阶段完整成功才继续下一阶段；失败后整台设备保持 pending，不回滚或清空已经写入的 Sensor。Sensor 起始阶段成功后，阶段 2/3 的失败不会由后续计划删除其地址。若 Sensor Overwrite 自身失败、publication/初始化未完成，或设备固件行为不符合已知共享关系，不能声称本地占用功能已正常；真实感应效果需设备验证。

保持现有初始化中的 Sensor subscription/publication、基础参数、LC Mode 和 Auto 顺序。Zone Set 不重新写 publication、Mode 或 Auto，也不为省一条订阅消息重排完整初始化；准备完成后进入本轮 Zone 计划时，以 Sensor Overwrite 再建立明确起点是允许的。必要初始化已完成而 Sensor subscription 缺失时，应允许本轮计划修复，不让完整 `isPrepared` 检查阻断自身恢复。

### 19.5 整设备重试、ACK 与持久化

- 删除单 Zone `retry(nodeUuid:zoneId:)` 及其差集/移除优先逻辑；页面不提供单个 Zone 的重试。`Sync Device(s)`、设备重试和显式 Apply 使用完整目标。旧服务接口确无调用方后删除，不保留兼容转发。
- 同步页即使从某个失败阶段/任务发起重试，也必须重置同一设备全部 Zone 阶段，从 Sensor Overwrite 或非 Sensor 的首 Zone Overwrite/DeleteAll 重新开始。自动重试遵循同样规则，不能只补最后失败的 Add；无关成功任务继续复用。
- 整轮开始前持久化 pending，保存失败不发送；最终状态保存失败也保留 pending，并清理对应同步判定缓存。云上传失败沿用既有上传重试，不抹掉已确认的设备结果。
- 新计划显式区分 Overwrite/DeleteAll/Add，复用 transport lane、生命周期 token、节点身份、目标快照及 revision 保护；外部修改、同目标再次编辑、节点重建、切 Space/账号后拒绝旧回调写成功。
- DeleteAll 请求不带地址，ACK 要求 Status 的 Address=0；不能复用当前“response = status byte + request”的字节比较。Overwrite/Add 匹配预期地址，并检查成功状态、源节点、element、SIG/Vendor Model/Company 及本次请求。标准测试见 [MESH.TS.p15](https://files.bluetooth.com/wp-content/uploads/dlm_uploads/2025/02/MESH.TS_.p15.pdf)。
- SDK 的 transport 成功不等于业务 ACK 匹配；App 必须控制阶段边界，严格校验后再放行下一阶段。错 ACK、缺失/重复回调、发送失败、保存失败都不能将整轮记为 synced。继续复用现有取消处理，不在已失效会话中补发。

### 19.6 UI、组播与其他功能边界

**显示：** 首页和详情只按目标列表显示成员，待同步数量按目标成员设备的 `lightingZonesStatus` 计算。设备页显示一个整体状态，即使目标为空也能展示 pending/synced 和进入 Sync；删除成员状态行、Removing/Pending Removal 与单 Zone Retry 入口。若 Zone 详情仍展示某设备同步情况，明确它是设备整体状态，不暗示单 Zone 单独成功。保留目录改名、63 项展示、Get 和现有国际化机制。

**Multicast：** 按用户选择，不保留旧成员、不新增 Space 级 pending 拦截，不增加设备订阅读取或实际接收者推导。既有“当前目标成员尚未同步时不执行正式 Multicast”的检查改读这些设备的 `lightingZonesStatus`，范围仍限当前 Zone；其他设备 pending 不阻断该 Zone。已离开目标列表但可能残留的订阅不再参与校验，由人工测试后对该设备完整 Apply/Sync。Unicast/Broadcast、权限、连接、prepared 和既有应急检查维持原范围，不增加因未知旧成员而扩大到整个 Space 的规则。

**测试控制：** 详情 Auto/On/Off/Brightness 继续表示请求，不能冒充实际完成。删除已无法计算的待移除设备数量；帮助文案简要说明显示目标成员、实际响应可能不同、可重新 Apply。空目标 Zone 的测试禁用保持现有规则，不因删除成员状态引入其他交互改造。

**订阅归属：** 全量覆盖会清除相关订阅表中的普通 Group、开关组、子元素广播组等其他地址。本轮只保留 Sensor 和目标 Lighting Zones，不自动恢复旧缓存订阅；HDB 与普通组/开关业务混用的保持能力不在此次承诺内。Sensor 集合的扩展仅为了遵循已有共享订阅表关系，不额外建立新传感器功能。

**容量：** 有 Sensor 的相关订阅表可能需要 8 个 Zone 加 1 个 Sensor 地址；Add 容量不足时整轮 pending，但已确认的 Sensor 地址仍保留。不得删除 Sensor、跳过必要 Model 或减少目标来伪造成功。真实容量、Vendor 共享行为和掉电保存属于设备验收范围。

### 19.7 最小完整实施与验证

本轮已完成以下 App 范围：

1. **模型、策略、Store：** 成员只留 zoneId；新增设备级两态并接入 Set、恢复和 `needsSync`；基于 SDK 现有共享关系计算 Sensor 保留集合、生成三个阶段。移除直接关联的旧退订/目录删除兼容分支，不扩大为其他旧格式清理。
2. **执行和重试：** 更新 Apply 与普通 Sync 两条链，共用计划、编码和 ACK；将单 Zone 执行结果改为整设备结算，调整 HDB Zone 的重试关联，覆盖添加/恢复收尾。Sensor publication 和其他参数初始化继续使用现有机制。
3. **消费者和保存：** 更新 Presentation、相关页面、Lighting Configuration 当前目标成员判断；核对本地 blob、canonical、导入导出、云回读及永久删除，不新增后端接口或 SDK API。
4. **文档和夹具：** 更新本节及 Lighting Configuration、初始化/统一同步文档；同步最新 JSON 示例和测试夹具。历史 current_demo 与旧验证记录保持其快照身份，不作为新方案运行证据。

必要行为验证：

- 新 JSON 成员只有 zoneId，设备状态仅 pending/synced；目标 0/1/8、9 个拒绝、重复/不存在 ID、相同目标显式重放、8→8 替换；空目标失败后保存重载仍可 Sync。
- 有/无 Sensor、同/不同 element、LC/LC Setup/同 element OnOff 共享列表；Sensor 保留集合先 Overwrite Sensor，其他集合按目标分支初始化，所有 Add 最后执行；五类必要 Model 及多个实例均覆盖。
- 使用会实际联动清空/添加的共享列表替身证明：Sensor 阶段成功后，在其他 Overwrite/DeleteAll、Zone Add 失败或容量不足时，Sensor 地址仍存在；整轮仍 pending。Sensor 自身失败不误报占用可用。
- DeleteAll Address=0、错误 node/element/model/company/address、超时、缺失/重复/迟到 ACK、保存失败、取消、身份变化与同目标再次编辑；无成功误记或旧回调污染。
- 同步页单任务/步骤/设备和自动重试均重做本设备完整 Zone 阶段，无单 Zone 重试；无关成功初始化/参数保持。已 synced 但人工发现实况不符时，可再次 Apply 全量修复。
- 不新增 Space 级 Multicast 拦截；当前目标成员的设备状态检查正确，旧成员残留按已接受边界不自动推断；Get、Unicast/Broadcast、原应急/权限、测试控制提示保持既定语义。
- 新结构持久化、导入导出及规范比较；清空仍保留目录，永久删除设备移除完整记录；首次添加和恢复不因成员数组为空误报已同步。不增加旧 HDB 格式迁移测试。

优先扩展现有 Tests/HDB 与 `check_hdb_configuration.py`、`check_hdb_lighting_zone_execution.py`、`check_hdb_integration.py`（device-sync/device-tasks/add-execution）、persistence/import_recovery/presentation/zone_control、lighting_configuration_service，以及 `check_sync_task_builders.py` / `check_sync_execution_session.py` 的相关行为检查。类型变化影响的其他现有夹具随本轮同步调整，不以源码字符串断言替代消息/状态行为验证。

生产 Swift 修改完成后，按固定工作树 DerivedData 运行一次 SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建。共享代码和本地化涉及五品牌；没有新增工程归属、依赖或不同编译分支时使用 SunSmart 代表，否则按实际跨品牌风险补齐。English/简体中文资源另做有效性检查。

人工验收：有 Sensor 灯完成初始化后依次配置 `[1,2] → [3,4] → []`；分别在 Sensor 起始、其他起始、Zone Add 阶段制造失败。Sensor 起始确认成功后，后两阶段失败仍应能本地感应；重启后完整 Sync 收敛，新旧 Zone 控制范围、8 Zone + Sensor 容量、多 element 行为及云回读另行确认。App ACK/隔离测试/编译不替代真实占用效果验收。

### 19.8 本轮实施与验证记录

用户已确认本节方案。代码已落在当前工作树，未 commit/push；无 SDK、固件或服务端变更，也不需要新 SDK API。复用本地 `one-dev` 现有消息及共享列表接口；正式依赖记录的 revision 同为 `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`。

实施结果：

- `HDBZonePlan` 保存内存目标快照，按 Sensor/reset/add 生成阶段；Apply 和普通 Sync 共用计划、消息编码与严格 ACK 匹配。每个阶段全部成功才推进，最后一个阶段保存设备 synced。
- Context 根据完整 SDK `relatedModels` 且仅同 element 划分 Sensor 保留集合。失败不回滚 Sensor；非空 Apply 允许修复缺少的 Sensor subscription，但仍要求 initialization receipt 和 publication 完整。
- Store 先持久化纯目标列表及 pending；新设备和 Restore 的空目标也进入同步。Codable、完整快照、导入导出和云回执比较包含设备级状态；旧 schema 不迁移。
- `SyncRetryPolicy` 的任务/步骤/设备重试联动整台设备所有 Zone 阶段；自动重试沿用同一入口。无关成功初始化和参数保持。删除单 Zone retry 和旧 deleting/removal 分支。
- 页面只展示目标成员及设备整体状态，设备空目标也显示状态；正式 Multicast 仅检查当前目标成员，不新增 Space 级阻断。详情测试帮助与中英文文案同步更新。
- 最新合成示例为 [完整配置](261021_1154_HDB_proposed_demo.json) 和 [初始化及部分完成](261021_1154_HDB_proposed_initial_demo.json)。`current_demo` 保留为改动前快照，不属于当前 schema 测试输入。

| 验证 | 本轮结果与覆盖边界 |
| --- | --- |
| `check_hdb_configuration.py`、`check_hdb_lighting_zone_execution.py` | 通过；目标替换、0/1/8/超限、Schema、阶段顺序、整轮完成、取消/重复/迟到结果、传输所有权 |
| `check_hdb_integration.py` | 通过；生产 Store/Service/Executor，SDK/数据库边界替身：Overwrite/Add/DeleteAll、跨 element、共享表联动、后续失败保留 Sensor、空目标重载、同目标重发、节点与版本变化、意图/节点/最终保存失败 |
| `check_hdb_device_preparation.py` | 通过；含 device-sync/device-tasks/add-completion/add-execution，真实 planner/task/store 与新增设备完成链。全部 Model 实例 ACK、DeleteAll Address=0、错误 element/address/model/company、初始化后空目标同步、阶段依赖 |
| `check_sync_task_builders.py`、`check_sync_execution_session.py` | 通过；生产重试策略从任务/步骤/设备入口重置全部 Zone 阶段，保留无关成功任务；共享 Session 的调度、停止、迟到回调与资源交接 |
| `check_hdb_persistence.py`、`check_hdb_import_recovery.py`、`check_hdb_group_lifecycle.py` | 通过；新结构本地/导入/快照往返、设备状态字段丢失拒绝、旧上传不覆盖新意图、目录保留、永久删除投影 |
| `check_hdb_presentation.py`、`check_hdb_zone_control.py`、`check_hdb_lighting_configuration.py`、`check_hdb_lighting_configuration_service.py` | 通过；设备两态及目标成员、Get、测试控制/权限/应急、正式配置既有发送及状态语义 |
| SunSmart 构建 | `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，`BUILD SUCCEEDED`。稳定 DerivedData：`SunSmart-feat-HDB-261020`。无新增 target 归属、依赖或品牌条件分支，使用代表品牌验证；其他四品牌未构建 |

已先通过旧行为回归建立基线，新增断言分别复现了空目标缺少设备状态、旧成员被保留和重试只重置失败 Add 的问题，修改后对应行为回归通过。隔离测试使用 SDK/数据库/云边界替身，不等于 BLE、真实存储故障或服务器集成验收。构建保留既有非阻断警告。

独立只读代码审查已完成，未发现可确认的本轮新增正确性缺陷。English/简体中文 strings 的 `plutil -lint`、`git diff --check` 均通过；两份最新合成 JSON 经生产 Codable 解码、策略校验和重新编码通过。正式 Multicast 回归确认：当前目标成员 pending 被拒绝，其他设备 pending 不阻断当前 Zone。真机、8 Zone + Sensor 容量、Vendor 共享关系、掉电保存和完整云往返仍待人工验收；最短步骤见 19.7。不会自动操作设备。

## 20. 添加设备 Lighting Zones 失败分析（2026-10-21 15:39，未实施修复）

### 20.1 结论

已定位为 App 全量订阅策略与 SDK 配置完成判定的冲突：Sensor 阶段将 element `0004` 的 LC 共享订阅表 Overwrite 为 `C07F`，移除了原有子元素广播地址 `FEFD`；SDK `node.isKeybindComplete` 因此变成 false。下一阶段调用 `HDBDeviceSyncTask.makeHandles()` 时被这个条件拒绝，产生 `plan-failed / expectedRevision=none / handles=0 / unavailable`。该阶段尚未发出 DeleteAll。

这不是已发送三条 Sensor Overwrite 的超时或错误 ACK：三条均收到对应 Model 的 Success，且任务记录 `persisted handles=3 ack=3`。本轮仅分析，保留现有未提交实现，未改业务代码。

### 20.2 日志与源码闭环

当前故障发生在新建 HDB Site 的 Space 2（Space ID 前缀 `E6CDB3D8`），节点 `0002`，PID `2502`、VID 3、三个 element。以下仅摘录必要信息，不保存日志中的密钥或完整网络数据。

| 阶段 | 日志证据 | 解释 |
| --- | --- | --- |
| HDB 前置任务 | subscription 1/1、两次 publication 各 1/1、initialization 12/12 均 persisted | 传感器链路配置和初始化任务已经取得应用层应答 |
| Sensor 覆盖 | element `0004` 的 `1000`、`130F`、`1310` 均执行 `801E` Overwrite `C07F`，对应 `801F` 均 Success | 本阶段三条消息全部确认；共享订阅缓存被替换 |
| 下一阶段 | `persisted kind=zone handles=3 ack=3` 后紧接 `plan-failed kind=zone expectedRevision=none handles=0 reason=unavailable` | 在生成消息前失败，尚未进入下一阶段发送 |
| 首次普通 Sync | 先 Add `FEFD` 到 element `0004` / `130F`；随后再次执行三条 Overwrite，全部 Success 后再次 plan-failed | 普通初始化补回其要求的广播订阅，HDB 覆盖又移除它，形成稳定循环 |
| 后续步骤 Retry | 只出现多条 plan-failed，未发送 Zone 消息 | Retry 不补普通初始化；节点仍缺少 FEFD，连 Sensor 阶段都被阻断 |

源码链：

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 统一设置 `subElementGroupSubscriptionModelIDs = [Light CTL Temperature Server, Light LC Server]`，HDB Site 也使用该配置。
2. 本地 SDK `MeshLib/Node/Node+Config.swift` 的 `isKeybindComplete` 不仅检查 AppKey/Model 绑定，还要求上述 Model 位于非主 element 时订阅 `.subElementBroadcastGroup`（`FEFD`）。本样本 LC `130F` 位于 `0004`，满足该检查条件。
3. SDK `ConfigurationClientHandler.swift` 收到成功的 Subscription Overwrite 后，对请求 Model 和同 element 的 `relatedModels` 先 `unsubscribeFromAll()`，再订阅新地址。这里 `C07F` 已有合法 Group 记录，FEFD 会从 LC 缓存移除。至少 LC 自身的 Overwrite 就足以触发，不依赖对固件未知共享关系的猜测。
4. [HDBDeviceSyncService.swift](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift) 的 `makeHandles()` 每个阶段都检查 `isCurrent() && node.isKeybindComplete && key != nil`，通过后才赋值 `expectedRevision`。`persist()` 不重新检查 `isKeybindComplete`，所以 Sensor 阶段仍会保存成功，下一阶段才失败。
5. [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 在该属性为 false 时产生 `deviceInitialize`。SDK `Node+Messages.swift` 的 `getNodeNeedKeyBindModelMessages()` 会补回缺少的 FEFD，解释普通 Sync 中再次出现的 Add。
6. [SyncRetryPolicy.swift](../SunSmart/Main/Space/Model/SyncRetryPolicy.swift) 重置整台设备的 Zone 阶段时会读取 `operationType.messageHandles`；这些读取也调用 `makeHandles()`。因此同一次 Retry 的多条 plan-failed 不代表多次无线发送。

首次失败前后 revision 都是 `1792568091`，且未出现 `invalid / revision-changed`；后续第一次 Sync 同样在 `1792568093` 内重现。现有证据不支持把本次失败归因于云端并发修改 revision。

### 20.3 关联影响与排除范围

- 只修改下一阶段的 guard 不足以完整修复。`prepareIntents`、添加完成入口、普通 Sync 的初始化任务/成功判定、Lights 列表修复提示和设备页等都消费 `isKeybindComplete`。即使暂时允许 Zone 继续，也会留下“已完成 HDB 配置却仍需修复/同步”的状态冲突。
- `HDBLightingZoneService` 的直接 Apply 路径没有同样的逐阶段 `isKeybindComplete` guard，因此与添加后的统一 Sync 存在入口差异。它仍会清除相关 FEFD，不能由 Apply 结果推定普通 Sync 和修复提示已正确。
- 启动时 `invalidStoredHDB` 对应旧 Space `B497D767…`、`082ADA11…`；本次新增设备位于新 Space `E6CDB3D8…`。旧数据导入/恢复故障需单独分析，不是本次阶段转换失败的直接原因。
- 本次多次云上传及回读确实记录成功；它们与设备 Zone 任务是不同完成条件，不能清除设备 pending。失败后仍有 LightCTLGet/Status 正常往返，也不符合“连接已经整体不可用”的解释。
- `Local … model … not bound to key` 没有阻止本轮初始化 12/12 ACK 入账；当前失败点是 App 计划前置检查。不能据此日志单独断言所有本地 Model 配置正确，也不需要用它解释此次 Zone 失败。
- Sensor 阶段成功后不会把整设备标记 synced，因为仍有 reset 阶段未完成。Add 最终 incomplete=1 符合任务失败状态；`settled-incomplete incomplete=0` 是合并结果前打印，不是先成功后被云端改坏。

### 20.4 隔离复现与此前测试缺口

在临时目录生成诊断夹具，复用当前生产 Store、Context、Zone planner 和 `HDBDeviceSyncTask`，并直接提取本地 SDK **原始 `isKeybindComplete` getter**；数据库、无线应答、初始化元数据和共享订阅缓存仍为边界替身。构造与日志相同的三 element 分布、LC 非主 element、FEFD 初始订阅、C07F Sensor 地址和空 Zone 目标。

两轮均复现：

```text
sensor ACK=3/3; LC subscriptions=[C07F]
SDK isKeybindComplete=false; reset handles=0
context/key valid; zone pending
```

两轮之间仅补回 LC FEFD；再次 Overwrite 后仍失败。随后单独重试 Sensor 阶段得到 handles=0。诊断过程未改生产文件或已有测试，临时文件已删除；这验证 App/SDK 判定冲突，不是新增真机或云端验收。

[HDBMeshTestBoundaries.swift](../Tests/HDB/HDBMeshTestBoundaries.swift) 把 `isKeybindComplete` 写为固定初值 true 的可写布尔值；即使共享订阅缓存正确模拟了 Overwrite 清空，它也不会随 FEFD 消失重新计算。此前隔离测试遗漏了这个 SDK 状态依赖，导致阶段测试通过却未覆盖真实添加路径。这是此次实现和验证的缺口，第 19.8 节通过记录不能作为该路径已验收的依据。

### 20.5 建议修复边界与验收

以下为首次根因分析时的建议；用户随后选择保留 FEFD，具体按第 21 节收敛，不再采用取消 HDB 广播要求的方向。

建议在 App 端统一 HDB 的订阅要求与配置就绪判定：优先评估现有 Site 级 `subElementGroupSubscriptionModelIDs` 配置机制，使 HDB 全量替换所管理的订阅表不再同时要求旧 FEFD；若 Site 级粒度不能准确覆盖相关设备，则采用明确的 HDB 就绪策略并统一相关消费者。保留真实网络/AppKey、Model 绑定、初始化元数据、权限、身份和版本检查；普通 Site 的广播订阅要求保持原行为。

实施前需核对相关产品的 Model/element 共享关系，以及 HDB/普通 Site 切换后的配置恢复。不能仅删除当前 guard、仅改失败标志或强制写 synced。按第 19.6 节已确认契约，本轮全量替换只保留 Sensor 和目标 Zones；直接在末尾补 FEFD 会改变这项订阅契约，不能作为不说明影响的补丁。

必要验证：

1. 三 element、LC 在非主 element：Sensor Overwrite 后继续 reset；空 Zone 完成后设备 synced，普通 Sync 不再补回 FEFD 引发循环，Lights 不再误报需修复。
2. 非空 Zone：Sensor → reset → add 完整完成；阶段失败/退出重进后可以整设备重试，仍保留 Sensor。
3. 直接 Apply、添加完成、普通 Sync、步骤 Retry 使用一致的就绪语义；缺少真实 AppKey/Model 绑定时仍拒绝并允许既有修复流程。
4. 普通 Site、HDB/普通 Site 切换及未被 HDB 覆盖的子元素广播需求保持正确；仅按实际影响补充代表构建。
5. 回归夹具须让就绪判定随订阅变化，避免继续固定 true。修复后由用户验证设备添加、Sync/Repair UI 和实际控制；自动化通过不替代真实感应、掉电保存及云往返。

本节调查结束时状态：根因分析和隔离复现完成，当时未实施修复或构建。本轮实施和验证结果已更新至第 21.6 节；独立的云请求分析文档不在本次修改范围。

## 21. FEFD 用途、标准项目边界与保留顺序（2026-10-21 15:44）

用户提出修复方向：固定要求 FEFD 的 Model 若与 Lighting Zone 修改范围重合，以 FEFD 为 Overwrite 首地址，再按需 Add sensorGroupId，最后 Add Lighting Zone 地址；要求不影响标准项目。第 21.1–21.4 节记录调用范围和修复契约，第 21.5–21.6 节记录本轮已授权实施与验证。

### 21.1 哪些 Model 要求 FEFD

当前 App 在 `SiteViewController` 将 SDK `subElementGroupSubscriptionModelIDs` 设置为以下两类。SDK 默认该数组为空，因此这是本项目配置的要求，不能把它理解为所有产品的 LC Model 天生固定订阅 FEFD。

| Model | SIG ID | 当前要求的实例范围 |
| --- | --- | --- |
| Light CTL Temperature Server | `1306` | 非主 element 上、参与 SDK 配置完成检查的实例 |
| Light LC Server | `130F` | 非主 element 上、参与 SDK 配置完成检查的实例 |

`isKeybindComplete` 对节点的 `supportModels` 检查上述条件。LC Setup `1310`、Generic OnOff `1000` 不在直接要求列表中，但本样本 element `0004` 上它们与 LC `130F` 同属 SDK 表达的共享订阅集合；HDB 覆盖它们时也必须保留 FEFD。

FEFD 在 SDK 中命名为 `Subelement Broadcast`，是既有子元素广播用途地址。已核对 [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift) 的实际发送方：

- Lights 页面全体调色温：`LightCTLTemperatureSetUnacknowledged` 发往 FEFD，由相应 Temperature Model 接收。
- Lights 页面全体 Auto：`LightLCLightOnOffSetUnacknowledged(true)` 发往 FEFD，由相应 LC Model 接收。

它不是一个用户 Lighting Zone，也不是每设备的 Sensor Group；不分配新地址，不占用 0–8 个 Zone 名额，但占设备订阅表容量。普通归属推导和云清理已有 FEFD 排除规则，不把它当成普通业务 Group。

### 21.2 添加流程中哪些任务使用全量替换

需要区分整个添加收尾与具体任务名：

| 添加后的任务 | 当前实际命令 | 是否复用 Set Lighting Zones 的覆盖计划 |
| --- | --- | --- |
| Sensor subscription | `ConfigModelSubscriptionAdd(sensorGroupId)` | 否，仍是 Add |
| Sensor publication | `ConfigModelPublicationSet` | 否 |
| HDB preparation / 日志 initialization | Vendor 参数、LC 属性、Occupancy Mode、LC Mode、Auto 等 Set | 否，不在这里执行 Subscription Overwrite/DeleteAll |
| Lighting Zones / 日志 zone | 按表要求先 FEFD Overwrite，再 Sensor Add/Overwrite、其他表 Overwrite/DeleteAll，最后 Zone Add | 是 |

添加/Restore/普通 Sync 使用 `HDBDeviceSyncService.makeSteps → context.zoneOperations → HDBLightingZonePolicy.operations`，Set/Apply 使用 `HDBLightingZoneService.setLightingZones → context.zoneOperations`；两条执行链的 Zone 消息编码均使用 `HDBLightingZoneService.handles`。因此修复应落在这份 HDB 共享计划和其上下文，不复制到 preparation 参数逻辑。

### 21.3 标准项目边界

- `HDBDeviceSyncContext.resolve` 先检查 `site.loadIsHdbSite()`；标准 Site 返回 nil。标准项目不会因为调用了共同添加收尾入口就建立 HDB 意图或执行 HDB Overwrite/DeleteAll。
- 经典添加、专业添加和 Restore 共用 HDB 收尾协调器，但标准 Site 会直接跳过，保留普通添加结果。普通 Sync 也只在解析到 HDB context 时追加 HDB 步骤。
- 当前改动中共享 `SyncRetryPolicy` 确有新增分支，但只匹配 `.hdb` 且 `isLightingZoneOperation` 的任务；普通任务仍执行原有单任务重试逻辑。
- 此方向保留 SDK FEFD 判定和既有全体色温/Auto 通道，无须修改全局 Model 配置、SDK 就绪判断、普通项目的配网/Group/场景/开关流程。
- “标准项目不受 HDB 覆盖”不等于“同一 HDB 设备上的所有旧业务订阅均保留”。HDB 全量替换仍按当前契约清除相关表中旧普通 Group/开关等地址；本次只新增 FEFD 保留。SDK 同 element 共享表中的其他 Model 会随表联动，这是本次必须纳入的范围。

本轮运行 `check_hdb_integration.py --device-sync` 与 `--add-completion` 均通过。其中标准 Site 用例检查不建立 HDB 会话、不改变 HDB 数据、不产生 HDB 待同步状态、保留标准添加失败集合。这些是此前生产入口的隔离行为证据，不是标准项目全功能真机验收；本轮修复后已重新验证，见第 21.6 节。

### 21.4 按用户方向细化的规则

必须按“实际 element + 同表关系”判断保留需求，不能仅对两个 Model ID 与 Zone targets 做字面交集。以完整节点关系找到非主 element 的 FEFD 接收者，再把同 element、与其共享订阅表且属于本轮 Zone targets 的 Model 一并纳入保留集合；Sensor 保留集合沿用相同的完整关系处理。

| 本轮目标所在订阅表 | 第一条命令 | 后续追加 |
| --- | --- | --- |
| 需要 FEFD，也需要 Sensor | Overwrite FEFD | Add sensorGroupId，再 Add 全部目标 Zones |
| 需要 FEFD，不需要 Sensor | Overwrite FEFD | Add 全部目标 Zones |
| 不需要 FEFD，需要 Sensor | Overwrite sensorGroupId | Add 全部目标 Zones |
| 两者均不需要，Zones 非空 | Overwrite 第一个 Zone 地址 | Add 其余 Zones |
| 两者均不需要，Zones 为空 | DeleteAll | 无 |

同一共享订阅表的各目标必须采用一致起点；先完成会作用于这张表的所有 Overwrite，再追加 Sensor/Zone，不能逐 Model 做完一整套后再覆盖下一个 Model，否则后者会删除前者的 Add 结果。全部必要目标仍应取得对应 ACK，不依赖 SDK 缓存联动冒充设备逐项确认。

本次日志的具体结果应为：element `0004` 的 `1000/130F/1310` 都以 FEFD 为起点，再添加 C07F；空 Zone 最终保留 `{FEFD, C07F}`。element `0003` 的 `1306` 不在当前五类 Zone targets 中，保持其原有 FEFD，不额外对它下发 Zone 覆盖。其他独立且不需要两种保留地址的表，在空 Zone 时继续 DeleteAll。

状态与恢复边界：

- 修复保持 `isKeybindComplete` 的真实检查。已有故障样本缺 FEFD 时，可由完整普通 Sync 先执行既有初始化补回，再进入新 HDB 计划；不能把它标成已成功，也不能让没有真实绑定的设备绕过检查。
- FEFD Overwrite 会暂时清掉同表 Sensor，直到 Sensor Add 成功；若该 Add 失败，必须保持 pending 并可重试，不能沿用旧方案“Sensor 起始阶段成功后一直保留 Sensor”的表述。
- 同表最多可能容纳 `FEFD + Sensor + 8 Zones = 10` 个地址；容量不足仍应失败并保留重试状态，真实容量待设备验收。
- FEFD 是执行计划的保留地址，不写成新的 Zone/Sensor 配置，不更改业务 JSON schema。

后续实施验证需覆盖：真实 getter 随订阅变化、非主/主 element 区别、同表多个目标的覆盖顺序、FEFD/Sensor 有无组合、空/非空 Zone、旧失败设备完整 Sync 恢复、Sensor Add/后续 Zone Add 失败与重试，以及上述标准 Site 隔离用例。无需改 SDK、固件或服务器。

### 21.5 实施计划（2026-10-21，已授权）

1. 更新第 4 节为统一契约；仅在 HDB 内存计划增加 FEFD 保护目标和起始阶段，复用同 element 关系推导。JSON schema、SDK 和普通项目行为不变。
2. 修改共享 Zone planner，使添加、Restore、普通 Sync、步骤 Retry 与直接 Set/Apply 使用 FEFD → Sensor → Zones 的同一顺序；两条执行链都校验 FEFD 保护集合没有变化。
3. 增加与现场一致的三 element 夹具，使用本地 SDK 实际 `isKeybindComplete` getter 验证每条订阅 ACK 后仍满足就绪条件；覆盖空/非空 Zone、同表联动、旧缺失 FEFD 恢复、失败重试、主 element 和标准 Site 隔离。保留真实未绑定拦截。
4. 运行相关 HDB/同步回归；用映射正确的 `SunSmartLocal.xcworkspace` 对 SunSmart 做一次 generic iOS Debug 无签名构建。真实设备验证由用户执行，不修改或部署外部系统。

### 21.6 修复结果与验证（2026-10-21 15:57）

实施完成：

- `HDBDeviceSyncContext` 从当前 SDK 配置的子元素广播 Model 找到接收者，沿完整节点 `relatedModels` 取同 element 关联，再与 Zone targets 取交集；Sensor 保留复用同一关联筛选。非主 LC 关联的 `1000/130F/1310` 全部保护，跨 element 的 Lightness 不误保护，Temperature `1306` 本身不增加 Zone 命令。
- `HDBLightingZonePolicy` 新增 FEFD 起始阶段，随后按是否受 FEFD 保护选择 Sensor Add 或 Overwrite，再重置无保留地址的表，最后 Add Zones。内存 `HDBZonePlan` 保存本轮广播保护目标，两条执行链在发送/回执时重新校验，避免配置或 Composition 改变后继续旧计划。
- 添加、Restore、普通 Sync 与直接 Apply 继续复用计划；步骤重试仍重置全部 Zone 阶段。没有修改 preparation 参数操作、全局 FEFD Model 列表、SDK readiness、标准 Site 分支、JSON schema、资源或品牌编译配置。
- 本轮生产改动限于 `HDBConfiguration.swift`、`HDBLightingZonePolicy.swift`、`HDBDeviceSyncContext.swift`、`HDBDeviceSyncService.swift`、`HDBLightingZoneService.swift`。已有其他未提交改动保留，未提交、推送或修改 SDK。

验证证据：

1. 新增三 element 夹具，集成脚本从当前映射的 SDK `Node+Config.swift` 提取实际 `isKeybindComplete` getter 执行。修复前明确失败于 `Zone ACK removed required FEFD from SDK readiness`；修复后每条 Zone ACK 后 readiness 均保持 true，并完成最后状态保存。数据库、无线传输、Composition 关系和其他 SDK 元数据仍是测试边界，不是完整 SDK/硬件运行。
2. 覆盖有/无 Sensor、0/8 Zones；非主 LC 共享表最终分别为 FEFD + 必要 Sensor + 全部 Zones，Temperature FEFD 保持不变。主 LC 无额外 FEFD 要求；即使广播接收者不在五类 Zone targets 中，也能保护同表的 Zone target。缺少绑定/绑定到错误 AppKey 仍拒绝。
3. 分别注入 FEFD、Sensor、Reset、Zone Add 阶段失败；确认后续不执行、设备保留 pending，页面重新创建后完整 Retry 成功。首个 Sensor Add 失败时 Sensor 暂时缺失，仍允许再执行修复。广播要求改变后，两条执行链拒绝旧 ACK，不误写 synced。
4. 旧缺 FEFD 状态在普通 HDB Task 入口仍被阻止；模拟既有普通初始化的 FEFD Add 成功回执后，实际 HDB planner/task 完整收敛；直接 Apply 也能修复。此夹具没有执行完整普通 SDK 初始化消息生成器，真实旧设备完整 Sync 仍须按下述步骤验收。
5. 添加收尾夹具已改为与现场一致的三 element 拓扑，实际 Add coordinator/任务规划/ACK 持久化共七阶段成功（Sensor subscription、两个 publication、initialization、FEFD/Sensor/reset），无 incomplete。完整同步页 Retry 策略夹具覆盖四个 Zone 阶段，并保持无关成功任务不重做。

| 本轮自动检查 | 结果 / 范围 |
| --- | --- |
| `check_hdb_configuration.py` | 通过，配置与 schema 回归 |
| `check_hdb_integration.py` | 通过，直接 Apply、共享 Sensor 表、空目标、失败与迟到回执 |
| `check_hdb_device_preparation.py` | 通过；包含 device-sync、device-tasks、add-completion、add-execution 和新增 subelement 模式；含标准 Site 隔离 |
| `check_hdb_lighting_zone_execution.py` | 通过，阶段阻断、取消、持久化与共享通道 |
| `check_sync_execution_session.py` | 通过，实际 Session 调度与生命周期 |
| `check_sync_task_builders.py` | 通过，普通任务与四阶段 HDB Retry |
| `git diff --check` | 通过 |
| SunSmart 构建 | `SunSmartLocal.xcworkspace` / SunSmart / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，15:56 输出 `BUILD SUCCEEDED` |

五品牌共用此次逻辑，无新资源、编译条件或 SDK API；本轮以 SunSmart 代表构建，未机械重复其他品牌。SDK revision `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，本轮无修改；无新增 SDK 发布依赖。构建使用工作树专属 DerivedData `SunSmart-feat-HDB-261020`，未 clean 或运行 Simulator/真机。

最短人工验收：

1. 对本日志的旧失败设备执行一次完整 Sync：确认普通初始化补 FEFD 后，HDB Zone 阶段不再出现 `plan-failed ... reason=unavailable`，最终完成；步骤 Retry 不应再触发 FEFD 补回/擦除循环。
2. 在 HDB Space 新增同型号三 element 设备；空 Zones 下确认 LC 同表 `1000/130F/1310` 先 Overwrite FEFD，再 Add sensorGroupId，最后保留两者；添加完成不显示 incomplete。
3. Set 8 个 Zones，再清空，分别验证灯控、全体 Auto/色温与本地感应；离开重进/设备重启后检查配置保持。包含 FEFD + Sensor 时需真实订阅容量至少 10。
4. 切回标准 Site，抽测添加、普通 Group、全体 Auto/色温；标准 Site 不应产生 HDB Overwrite/DeleteAll。真实设备、云端往返和 UI 体验尚未在本轮验收。
