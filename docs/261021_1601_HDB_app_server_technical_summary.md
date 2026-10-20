# HDB Lighting Zones：App 与服务器技术契约及实施核对

更新：2026-10-21 16:12（Asia/Singapore）；补充 §4.2 Model/element 订阅表与多实例 Generic OnOff 的区别。

## 1. 结论与证据边界

**App 已实现 HDB Lighting Zones 的配置模型、63 Zone 预建、设备全量订阅、FEFD/Sensor 保留、本地保存、导入导出和现有云同步接入。当前代码采用设备级 `pending/synced`，不能再以原设计前半部分的成员级 `desired/status`、增量 Add/Delete 或逐 Zone 重试作为接口依据。**

**服务器方面已确认的是 App 的 HTTP 接口、上传数据结构和回读校验逻辑；未核对后端源码、部署版本或本轮真实请求，不能确认服务器已经完整保存这些字段。HDB 平台的 MQTT 接入、网关映射及端到端执行仍是外部配套。**

本轮执行 7 项定向检查，6 项通过；`check_hdb_space_creation.py` 因测试替身编译错误未能执行。未修改生产代码或测试，未构建、未操作真机、未访问实际服务器。隔离回归不等于 SQLite、BLE、云端或 UI 运行验收。

### 核对基线

| 项目 | 本次基线 |
| --- | --- |
| 工作树 / 分支 | `feat-HDB-261020` / `feat/HDB-261020` |
| 交付时 HEAD | `355632ee4c252119f2ad920f4fff7b06c5d3e51e`，`feat: fix adding HDB light issues` |
| 基线变化 | 开始时为 `215fe006` 加已有未提交修改；核对期间其他操作提交了上述 HEAD。本任务未执行提交。所记录的生产 Swift、HDB 测试和检查脚本内容哈希在回归前后未变。 |
| 本地 SDK | `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；revision `8c5af55f5887e588e71f053ab44e2f6aa53a86a0` |
| 设计来源 | [Lighting Zones 设计与实施记录](261020_1019_HDB_lighting_zones_design.md)，以当前第 4、19、21 节结合生产实现为准 |
| 协议来源 | [HDB 示例](../protocols/HDB/Sample_payload.md)、[SLP ICD](../protocols/HDB/SLP%20Interface%20Control%20Document.md) §4.1.2.3.1 |

原文是累积实施记录：早期方案及当时的“当前实现”不都适用于最新代码。原文在本轮期间补充了 §21.6 的 FEFD 修复与构建记录，但首页仍保留修复前 HEAD 和“未提交”描述；版本以本表为准。

## 2. 系统分工与实际入口

| 层次 | 已确认实现 / 契约 | 未完成或不能据此推定的内容 |
| --- | --- | --- |
| App | 在 HDB Site 中管理 Space 的 Zone 目录与设备目标；通过现有 Mesh 配置通道下发，保存 ACK 结果；通过 Site/Space 同步上云 | `synced` 不是实时读取，也不是云端确认或永久不变的设备状态 |
| SunSmart 服务器 | App 使用现有 Site/Space HTTP 接口发送 HDB JSON、Group 占用和节点信息，并回读比较 | 后端实现和字段保真未在本轮实测；没有新增 HDB 专用接口的 App 代码 |
| 网关 / HDB 平台 | ICD 定义 `SmartLighting/setLightingZone`、`getLightingZone`、Set/Get ACK | 当前 HDB 配置链未接入这些 MQTT 事件的接收、转换、执行与应答；App 中同名 Swift 方法是本地业务服务，不是 MQTT handler |
| 设备 / SDK | App 复用 SDK 的 Composition、Model 关系、Config Subscription 消息和结果缓存 | 固件实际共享订阅表、容量、掉电保存和控制效果仍需设备验收 |

业务入口是 `Site → Space → More → HDB Configuration`。页面有 Lighting Zones / Devices 分段，Zone 详情支持成员查看、重命名和测试控制；设备页支持完整选择、Apply、同步及 JSON Get。当前主菜单不提供 Zone 新增/删除；文件中仍有旧 `addZone` 等私有辅助方法，不能把未接到 UI 的方法当作现有产品入口。

Site 类型保存在 `site.extensionData.isHdbSite`；执行上下文再次读取类型、账户、区域、Space、节点归属和权限，标准 Site 不建立 HDB 上下文。配置修改还受 `canEditing`、Group 编辑权限和配置恢复保护约束。

品牌范围需要纠正早期描述：当前 [debug_features.json](../SunSmart/debug_features.json) 仅把 **Site 类型选择**限定为 SunSmart；`space.hdbConfiguration` 规则未限定品牌，允许 Debug/Release 的 owner/editor。结合 `SpaceMoreViewController.canShowHDBConfiguration`，其他品牌加载 HDB Site 且权限满足时也可能显示入口。共享模型、存储和同步逻辑属于五品牌共用范围；本轮未做跨品牌 UI 运行验证。

主要依据：[SpaceMoreViewController](../SunSmart/Main/Space/Controller/SpaceMoreViewController.swift)、[HDBConfigurationViewController](../SunSmart/Main/Space/HDB/Controller/HDBConfigurationViewController.swift)、[HDBDeviceSyncContext](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)、[SiteExtensionData](../SunSmart/Common/Data/SiteExtensionData.swift)。

## 3. App 与服务器共享的数据契约

### 3.1 存放位置与字段

HDB 对象位于每个导出 Space 的 `spaceData.hdb`。Site 上传的具体路径是 `site.spaces[].spaceData.hdb`；单 Space 上传是 `spaces[0].spaceData.hdb`。原文的 `site.space.spaceData.hdb` 应理解为业务层级，不应照抄成 HTTP 字段路径。

| 字段 | 当前类型及含义 | 校验 / 对接要求 |
| --- | --- | --- |
| `schemaVersion` | 整数，当前为 `1` | 是 HDB 格式版本，不是 Space 更新版本；仅凭 `1` 不能区分历史上已经变化的 HDB 结构 |
| `lightingZones` | Space 级目录数组 | `zoneId` 唯一，1–63；`groupAddress` 唯一；非空名称 |
| `lightingZones[].groupAddress` | UInt16 JSON 整数 | 读取校验允许 `0xC000...0xFEFC`；当前新分配从 `0xC001` 起过滤，不能把固定的 `C000 + zoneId` 当映射规则 |
| `lightingZones[].lightingConfiguration` | 字段配置对象或 `null` | Zone 范围的 Lighting Configuration 保存值 |
| `devices[].nodeUuid` | UUID 字符串 | 稳定关联标识；导入必须与同一 payload 的节点 UUID 和主单播地址同时吻合 |
| `devices[].nodeAddress` | 1–32767 的 JSON 整数 | 主单播地址，不是某个子 element 地址；设备恢复后需更新身份 |
| `devices[].mac` | 大写冒号分隔 MAC 或 `null` | Key 必须存在；未知时不伪造。初始化入口可能先写 `null`，不能要求每条记录都有实际 MAC |
| `devices[].lightingZones` | `[{"zoneId": 1}, ...]` | 完整目标列表，0–8 项，不重复，必须引用现有目录；不是增量列表，也不是当前设备实况 |
| `devices[].lightingZonesStatus` | `pending` / `synced` | 必填；整设备全部 Zone 阶段的持久结果，空目标也有状态 |
| `devices[].sensorGroupId` | UInt16 JSON 整数或 `null` | Key 必须存在；非空为 `0xC001...0xFEFC`，设备间不重复且不与 Zone 地址重叠 |
| `devices[].lightingConfiguration` | 字段配置对象或 `null` | 单设备 Lighting Configuration 目标与字段状态 |
| `broadcast.lightingConfiguration` | 字段配置对象或 `null` | Space 广播范围的配置；与设备、Zone 范围分别存放 |

SDK Mesh payload 中 `groups[].address`、`nodes[].unicastAddress` 为十六进制字符串，而 HDB 内对应地址是整数。服务器及后续网关转换必须保留类型边界。`sensorGroupId` 引用 SDK 中 `isVirtual=true` 的 Group 记录，但其数值仍在普通组地址范围；这里的 App/SDK 标记不能直接解释成 SIG Virtual Address 或 Label UUID。

服务器必须把关联的 `groups`、`nodes` 与 `spaceData.hdb` 作为同一 Space 快照保存。导入验证要求 Zone 地址存在于非 virtual Group、Sensor 地址存在于 virtual Group，且设备身份有效；只透传孤立的 `hdb` 不足以构成可导入的项目。

### 3.2 当前格式示例

以下仅演示 `hdb` 对象，目录缩为一个 Zone；新建 Space 实际预建 63 个。UUID、MAC 和地址为合成值，不含 Mesh 密钥。完整 Space 仍须带匹配的 `groups` 与 `nodes`。

```json
{
  "schemaVersion": 1,
  "lightingZones": [
    { "zoneId": 1, "name": "Zone 1", "groupAddress": 49153, "lightingConfiguration": null }
  ],
  "devices": [
    {
      "nodeUuid": "11111111-1111-4111-8111-111111111111",
      "nodeAddress": 2,
      "mac": null,
      "lightingZones": [{ "zoneId": 1 }],
      "lightingZonesStatus": "pending",
      "sensorGroupId": 49216,
      "lightingConfiguration": null
    }
  ],
  "broadcast": { "lightingConfiguration": null }
}
```

上例可表达未配置 Lighting Configuration 的合法存储记录，不代表新设备初始化完成；实际初始化会建立默认字段并执行必要任务。

### 3.3 状态与兼容性

- `lightingZonesStatus=pending` 包括尚未执行、失败、取消、中断或最终保存失败；不再持久化 `failed`。失败细节属于当前执行结果和 DEBUG 诊断。
- `synced` 表示该设备整轮订阅操作取得必要成功 ACK 并完成保存；不表示设备此后没有变化，也不表示云上传成功。
- 当前不输出成员 `desired/status`、Zone `deleting`、`failedModels` 或旧成员清理清单。服务器不应自行补回这些字段或仅保留 synced 成员。
- 缺少整个 `hdb` 可表示未配置 HDB；已有 `hdb` 却损坏或缺少设备必填状态等字段会拒绝读取/导入，不能回退为空配置。
- 当前有一处窄兼容：缺少 `broadcast` 且没有非空旧根级 `lightingConfiguration` 时可补空 broadcast；这不等于支持全部旧 schema-1 数据。旧成员结构缺少新设备状态时仍不兼容。原方案已明确旧测试项目重建，不做通用旧格式迁移。
- 当前模型并不保证未来未知 HDB 字段经过旧 App 解码/编码后仍保留；新增字段或新格式需同步更新参与测试的客户端并明确兼容方案。

主要依据：[HDBConfiguration](../SunSmart/Common/Data/HDBConfiguration.swift)、[HDBLightingZonePolicy](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)、[ExportData](../SunSmart/Common/Data/ExportData.swift)、[ImportData](../SunSmart/Common/Data/ImportData.swift)。

## 4. App 的实际配置执行

### 4.1 Zone、地址池与设备容量

HDB Site 新建 Space 且功能可见时，`SiteData.addSpace` 先确认有 63 个地址，再创建子网和 Zone 1–63。每个 Zone 都保存非 virtual 的 SDK Group，实际消耗地址池；预建目录本身不发送 63 份设备订阅。旧 Space 打开时不会自动补齐目录。

可用地址按整个 Site 的 Mesh UUID 查询，排除全 Site 已用地址；同一 Site 的不同 Space 共用地址池，但分别拥有 1–63 的业务 Zone ID。当前新分配范围 `0xC001...0xFEFC` 有 16,124 个候选地址，实际可分配数量仍受 Provisioner/服务器额度及其他用途占用限制。每台带可识别 Sensor 的设备还会单独消耗一个 Sensor Group。

地址不足会在新建子网前拒绝创建。当前 `SiteViewController.addSpace` 只显示错误，**没有在该入口自动申请补齐 63 个地址**；已有单 Zone 辅助代码的 16 地址申请不代表新 Space 的自动补额能力。设备清空 Zone 目标不会删除目录或释放其 63 个地址。

依据：[MeshNetwork+SunSmart](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)、[HDBConfigurationStore+Mesh](../SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift)、[SiteViewController](../SunSmart/Main/Site/Controller/SiteViewController.swift)。本轮 Space 创建隔离回归编译失败，因此本节落地判断来自源码，未增加创建行为测试通过的结论。

### 4.2 全 Node 目标与 FEFD/Sensor 顺序

必需 Model 为 SIG `130F`（LC）、`1310`（LC Setup）、`1000`（Generic OnOff）、`1300`（Lightness），以及 Company `0A78` / Model `0001`（Vendor）。遍历全部 element，按 element 地址、Company、Model 区分实例；五类缺任一类即 Unsupported。当前依据 Composition 选择能力，没有 HDB PID 白名单。

**Model 与 element 的订阅要求：** 下表中“随共享表”均指完整 Composition 中、同一 element 内由 SDK `relatedModels` 表达的关系；不能把跨 element 的模型关联当成同一订阅表。Sensor 一列以 App 已识别传感能力并分配 `sensorGroupId` 为前提。

| Model | 标识 / 实例位置 | FEFD 要求 | Sensor 要求 | Lighting Zones / 本期作用 |
| --- | --- | --- | --- | --- |
| Light LC Server | SIG `130F`，非主 element | 直接要求保留 | 直接接收 Sensor，需要保留 | 全部实例加入目标 Zones；LC Auto 接收者 |
| Light LC Server | SIG `130F`，主 element | 不因 LC 身份直接要求 | 直接接收 Sensor，需要保留 | 全部实例加入目标 Zones；不能因另一个 element 有 FEFD 就给本实例增加要求 |
| Light LC Setup Server | SIG `1310`，与 LC 同 element 且共享表 | 随该表的非主 LC 要求保留 | 随 LC 保留 | 全部实例加入目标 Zones；LC 参数配置接收者 |
| Generic OnOff Server | SIG `1000`，与非主 LC 同 element 且共享表 | 随非主 LC 保留 | 随 LC 保留 | 加入全部目标 Zones；不能作为普通独立 OnOff 表执行清空 |
| Generic OnOff Server | SIG `1000`，与主 LC 同 element 且共享表 | 不因主 LC 或 OnOff 身份直接要求 | 随主 LC 保留 | 加入全部目标 Zones；与上一行的 FEFD 起点不同 |
| Generic OnOff Server | SIG `1000`，其他实例，包括没有 LC 同表关系的主 element 实例 | 仅与本 element 的 FEFD 接收者同表时保留 | 仅与本 element 的 LC 同表时保留 | 每个实例都加入目标 Zones；无保留要求时按首 Zone Overwrite / 空目标 DeleteAll |
| Light Lightness Server | SIG `1300`，所有实际实例 | 按本 element 的实际同表关系 | 按本 element 的实际同表关系 | 全部实例加入目标 Zones；直接亮度控制接收者 |
| Sunricher Vendor Server | Company `0A78` / Model `0001`，所有实际实例 | 按本 element 的实际同表关系 | 按本 element 的实际同表关系 | 全部实例加入目标 Zones；Vendor 参数接收者。未知固件共享关系不能由 App 猜测 |
| Light CTL Temperature Server | SIG `1306`，非主 element | 普通初始化直接要求 | 本规则不额外增加 | 不属于五类 Zone targets，不直接执行 Zone 覆盖；若与 Zone target 同表，后者仍须保护其 FEFD |
| Sensor Server | SIG `1100`，识别到的占用/照度 Sensor 实例 | 本规则不额外增加 | publication 指向 Sensor Group，不能因此推定需要订阅该地址 | 不属于 Zone targets；由前置初始化配置 publication |

LC Setup 等其他实例如不满足表中明确的同表条件，也按实际关系分类，不仅凭 Model 名称套用 LC 的保留要求。Sensor Setup、Config Server、各 Client 和其他未列入的模型不直接加入本期 Zone targets；它们所在表是否被联动影响仍取决于实际共享关系。

**Generic OnOff 在多个 element 中不是同一个配置目标。** 当前现场拓扑对应的三 element 回归夹具可说明区别：假设节点主地址为 `0002`、Sensor Group 为 `C07F`，所选 Zone 地址集合记为 Z（示例地址，不是固定分配规则）。

| 实例 / 同表关系 | Zone 非空时的配置 | Zone 为空时的结果 | 区别 |
| --- | --- | --- | --- |
| `0002 / 1000`，主 element，无 LC/FEFD 接收者同表关系 | Overwrite 首个 Zone，再 Add 其余 Z | DeleteAll，表为空 | 不因 `0004` 的 LC 需要 Sensor/FEFD 就保留它们 |
| `0004 / 1000`，非主 element，与 `0004 / 130F、1310` 同表 | 先完成该表各目标的 FEFD Overwrite，再 Add C07F 和全部 Z | 保留 `{FEFD, C07F}` | 即使 Model ID 同为 `1000`，也必须采用 LC 共享表的保护顺序 |
| `0003 / 1306`，另一个非主 element | 本轮不直接修改 | 原有 FEFD 保持 | 与上述两个 OnOff 不因同属一个 Node 就共享订阅表 |

上述差异由模型关系决定，不能泛化成“所有主 element OnOff 都不需要 Sensor”或“所有非主 OnOff 都需要 FEFD”。例如 Generic OnOff 与主 element LC 同表时，需要 Sensor，但没有非主 LC 的 FEFD 要求；与非主 Temperature Model 同表但不与 LC 同表时，则可能只需保留 FEFD。无 Sensor 的设备，表中 C07F 对应的步骤和结果省略。

**订阅全部 OnOff 实例，不代表控制命令总是向全部实例分别发送：**

- 正式 Lighting Configuration 的单播 `Force_Off` 只选主 element 的 `1000`；主 element 缺少该 Model 时拒绝，不退回非主 element。广播也不额外补发 secondary OnOff，不能据此删除它的 Zone 订阅。
- Multicast `Force_Off` 只用主 OnOff 做模型/绑定预检，但实际向 Zone 组地址发一条无应答 Generic OnOff。主、非主 OnOff 若都已绑定并订阅同一组，都可能接收；Zone 详情的 On/Off 测试控制同样使用组地址，不能承诺只有主 element 生效。
- LC 同 element 的 OnOff 与主 element 的 OnOff 是不同实例，不能把对前者的操作直接认定为后者的直接灯输出控制，也不能仅凭同一个 `1000` ID 推定二者的状态绑定和实际灯光表现相同。App 当前 Force Off 的选址已明确；固件收到组命令后两个实例的实际作用及最终输出仍需设备验收。Auto 则使用 LC `130F` 的 Light LC Light OnOff 消息，不是向各 `1000` 逐一发送 Generic OnOff。

Set 消息发往节点主单播地址，参数携带实际 element、Model 和映射组地址。当前是 **Overwrite/DeleteAll/Add 全量计划**，不再计算旧、新 Zone 差集。

| 目标所在的共享订阅表 | 起始操作 | 后续操作 |
| --- | --- | --- |
| 需要 FEFD 与 Sensor | Overwrite `FEFD` | Add Sensor，再 Add 所有目标 Zones |
| 仅需要 FEFD | Overwrite `FEFD` | Add 所有目标 Zones |
| 仅需要 Sensor | Overwrite Sensor | Add 所有目标 Zones |
| 两者均不需要，目标非空 | Overwrite 首个 Zone | Add 剩余 Zones |
| 两者均不需要，目标为空 | DeleteAll | 无 |

执行阶段为 broadcast → sensor → reset → add，跳过空阶段；同一共享表所有 Overwrite 先完成，再 Add 保留地址和 Zone。保留集合根据完整 Composition、同 element 的 `relatedModels` 和实际接收者计算，不能只按 Model ID 字面判断。

FEFD 是 SDK 的 Subelement Broadcast，App 全体色温/Auto 已使用它。当前 Site 设置要求非主 element 的 `1306`、`130F` 保留 FEFD；SDK `isKeybindComplete` 检查这一条件。HDB 保护会与五类 Zone targets 取交集并包括同表目标，未被 HDB 修改的 Temperature Model 保持原订阅。修复不放宽 SDK 就绪检查，也不修改标准 Site 的全局广播策略。

Sensor Group 用于设备自身传感器发布以及 LC 接收。占用或照度 Sensor 被识别时分配，同一设备两类 Sensor 共用地址；只有照度 Sensor 不能据此认定支持占用感应。`sensorGroupId=null` 也不能单独解释成设备不支持 Sensor，可能尚未完成分配。

空目标仍保留所需 FEFD/Sensor。FEFD Overwrite 到 Sensor Add 之间可能短暂没有 Sensor；失败时保留 pending，按完整计划重试。最多 8 个 Zone 不包括 FEFD/Sensor，同表可能需要 **10 个地址**。容量不足、未知 Vendor 共享关系及真实感应效果需设备验收。

HDB 全量替换会清除相关表中的旧普通 Group/开关订阅；本期没有承诺 HDB 与普通业务混用时保留所有旧地址。HDB Zone 更新不重写 Sensor publication，它属于前置初始化。

依据：[HDBDeviceSyncContext](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)、[HDBLightingZonePolicy](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)、[HDBLightingZoneService](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift)、[HDBLightingConfigurationPolicy](../SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift)。三 element 及同表边界依据：[HDBSDKKeybindTestBoundaries](../Tests/HDB/HDBSDKKeybindTestBoundaries.swift)、[HDBSubelementSubscriptionTests](../Tests/HDB/HDBSubelementSubscriptionTests.swift)；Force Off 的已确认范围见 [Lighting Configuration 设计 §10](261020_1649_HDB_lighting_configuration_design.md)。本次补充仅核对已有代码和夹具，未重跑回归或增加设备验收结论。

### 4.3 入口、成功条件与恢复

直接 Apply 使用 `HDBLightingZoneService/Executor`；添加、Restore、普通 Sync 使用 `HDBDeviceSyncService/Task`。两条链共用 Zone 计划及消息编码。添加前置任务依次处理 Sensor subscription Add、publication、Vendor/LC 初始化；随后进入上述 Zone 全量计划，不能把全部添加任务都解释为 Overwrite。

每次 Apply 都先持久化完整目标和 pending，即使目标未变化也重放。普通 Sync 在设备 pending 时生成任务；从失败步骤重试也重置该设备所有 Zone 阶段，保留无关的已成功初始化/参数任务。

成功要求全部阶段的必要操作取得正确 ACK，再保存节点及最终状态。ACK 核对成功码、目标 element、Model/Company、预期地址并依附当前节点和请求；DeleteAll 的返回地址要求为 0。SDK 更新关联缓存不能替代逐请求 ACK。上下文、节点身份、版本或保留集合变化后拒绝旧回调；取消、中断和持久化失败不伪装 synced。

旧失败设备若已丢 FEFD，普通 HDB Task 仍受真实 `isKeybindComplete` 阻断；需要完整普通 Sync 先补 FEFD，再进入新 HDB 计划。当前直接 Apply 计划也具备重建保留订阅的能力，但不等同于放宽普通同步的前置条件。

**Lighting Zones Get** 直接返回本地保存的设备 JSON；无记录时读取本地节点元数据生成空目标。不发 Mesh Get、不等待云端，也不改状态。不要将这一语义推广到所有 HDB Get：已有 Lighting Configuration 的部分单播 Get 会读取设备。

依据：[HDBDeviceSyncService](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift)、[HDBLightingZoneExecutor](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift)、[SyncRetryPolicy](../SunSmart/Main/Space/Model/SyncRetryPolicy.swift)、[HDBDeviceAddCompletion](../SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift)。

## 5. Lighting Configuration 已有的关联实现

原文早期写“Lighting Configuration 不实现”，当前代码已经有页面、服务、消息及存储。服务器对 `hdb` 的保存不能只支持 Zone 和设备列表而丢弃这些配置。

| 字段 | 当前 App 值 / 范围 | 实际处理 |
| --- | --- | --- |
| `lightingControl` | Auto / Force_On / Force_Off；默认 Auto | LC OnOff true / Lightness 65535 / 主 element Generic OnOff false |
| `dimIntensity` / `brightIntensity` | 0–50 / 50–100；默认 20 / 80，百分比 | LC Property `002F` / `002E`，转换为 0–65535 |
| `rampUpTime` / `rampDownTime` | 1–3 秒；默认 1 / 2 | LC Property `0037` / `0036`，转换为毫秒 |
| `holdTime` | 10–3600 秒；默认 30 | LC Property `003C`，转换为毫秒 |
| `failsafeDelay` | 0–250；默认 5 | 当前仅保存业务值，不生成设备 failsafe 计时消息；不能宣称自动回退已实现 |
| `installDate` | 严格 `dd-MM-yyyy`，默认未设置 | 当前仅保存业务值，不向设备写安装日期 |

各字段格式是 `{ "status": "pending或synced", "value": ... }`。`failsafeDelay`、`installDate` 保存即记 synced；其他字段单播需匹配设备 ACK，而 multicast/broadcast 使用无应答发送，完成后也会记 synced。因此 **Lighting Configuration 的 synced 不都意味着逐设备确认**，与 `lightingZonesStatus` 的整轮配置 ACK 语义必须区分。

正式 Lighting Configuration multicast 要求当前目标成员 Zone 状态全部 synced；别的设备 pending 不整体封锁该 Zone。Zone 详情的测试控制允许当前目标成员 pending，发送也不改保存状态。当前目标列表不保留已经移除但尚未被成功重写的旧成员，无法仅靠 JSON 排除它们仍响应旧组命令的可能性。

依据：[HDBConfiguration](../SunSmart/Common/Data/HDBConfiguration.swift)、[HDBLightingConfigurationPolicy](../SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift)、[HDBLightingConfigurationService](../SunSmart/Main/Space/HDB/Model/HDBLightingConfigurationService.swift)、[HDBLightingMessages](../SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift)。本节为关联技术核对，不替代完整 Lighting Configuration 专项验收。

## 6. 持久化、云端和生命周期的一致性

| 链路 | 当前落地内容 | 验证限制 |
| --- | --- | --- |
| 本地数据库 | Space 的可空 `hdb` blob、缺列迁移、两条 load 路径；解码失败标记 `hdbLoadFailed` 并阻断配置 | 本轮未运行真实 SQLite 迁移/重启测试 |
| 保存与旧对象 | Store 从最新持久 Space 修改；保存比较 baseline，旧页面不能静默覆盖新 HDB；版本单调递增 | 回归使用数据库边界替身 |
| 导出/导入 | `spaceData.hdb` 完整编码；导入前验证 schema、成员/地址及 Group/Node 引用；选定恢复快照一致应用 | 未执行真实文件分享、服务器往返 |
| 普通 Group 归属 | HDB Zone/Sensor 地址排除于普通单组推导；Group 仍登记占池；避免多 Zone 被误判成普通多组冲突 | 不表示普通 Group 与 HDB 混用已验收 |
| 配置快照/回读 | `configurationData` 含 canonical HDB，包括设备和字段状态；丢 HDB、丢必填字段、状态变化可造成不一致 | 不是任意未知字段的逐字节保真校验；合法缺省可规范化 |
| 云上传期间再修改 | 提交保存对应版本快照，确认只推进该提交时间；本地后续版本继续 dirty | 本轮验证了相关 HDB快照差异，未运行真实多客户端并发 |
| 永久删除设备 | 清除 UUID 对应 HDB 设备，Sensor 地址进入删除日志；存在发布/订阅引用时延后回收 | Zone 目录及地址保留，不转移旧配置给复用单播地址的新 UUID |
| Space 删除/克隆 | 删除走现有取消及子网清理；clone 清空 HDB 配置，不能照抄旧身份 | 本轮创建/删除脚本未编译通过，不能引用为本轮行为验证 |
| 合法空 Space | 无设备但有 Zone 目录不是无配置；`isEmpty` 已考虑 HDB 目录 | 空目标与缺失/损坏配置严格区分 |

关键实现：[Database](../SunSmart/Common/Data/Database.swift)、[HDBConfigurationStore](../SunSmart/Common/Data/HDBConfigurationStore.swift)、[SpaceSyncCleanupPolicy](../SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift)、[SpaceConfigurationIntegrityPolicy](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift)、[SpaceConfigurationSafety](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)、[DevicePermanentDeletionCleanup](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)。

## 7. SunSmart HTTP 接口与服务器要求

### 7.1 当前 App 已接的接口

以下为区域 baseURL 后的路径；样本环境 baseURL 包含 `/srv2`。**这些接口全部使用 POST，包括路径名带 get 的读取。**

| 用途 | 路径 | 主要请求结构 |
| --- | --- | --- |
| 上传 Site 与指定 Spaces | `/sitespace/sync/siteprops` | `site`（含 `spaces[]`、Site 扩展和地址资源）、`user`；新 Site 路径还携带已用设备地址数量 |
| 上传单 Space | `/sitespace/sync/spaceprops` | `siteId`、`spaceId`、`spaces: [SpacePayload]`、`userId` |
| 读取基线 / 上传后回读 | `/sitespace/get/spaceprops` | `siteId`、`spaceId`、`passwd`、`userId`；返回 `data` 为 Space payload |
| 申请地址 | `/sitespace/address/claim` | `siteId`、`addrType`、`number`、`userId`；已有 Group 申请代码消费返回 `provisioner` |

代码依据：[NetowrkReqeustApi](../SunSmart/Common/Network/NetowrkReqeustApi.swift)、[CloudSynchronizationManager](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift)。本文只列字段名，不记录密码、鉴权信息或密钥。

实际链路为：本地意图/结果保存 → 更新 Space 版本 → 排队既有云同步 → 远端基线与权限/配置检查 → 导出和提交快照 → 上传 → 回读比较 → 仅确认该提交版本。HTTP 200 本身不足以完成确认，Mesh ACK 也不能替代云确认。

当前 `HDBConfigurationStore.update` 每次成功保存仍会 `enqueueSpaceSync(..., .promptly)`；添加期间多个阶段可能触发多次同步。另文提出的“整批添加只做一次最终同步、正常条件下三次 HTTP”尚未落地，不能写成现有请求次数或后端 SLA。参见 [添加设备云请求分析](261021_1510_HDB_device_add_cloud_requests_analysis.md)；本轮仅确认现有即时排队代码，没有重测该文日志数量。

### 7.2 需要服务器团队确认的契约

1. 保存、回读和分享导出的同版本 Space 必须保留完整 `hdb`，尤其 `lightingZonesStatus`、`sensorGroupId`、显式 `null`、三个范围的 Lighting Configuration 及其字段状态。
2. 同一快照的 `groups`、`nodes`、`hdb` 和 Site 地址资源保持一致；Zone 与 Sensor Group 的标记、地址类型及节点 UUID/地址关联不得被服务器改写成另一种含义。
3. 回读不能只返回设备执行成功的子集；pending 是重试所需目标，不能过滤或由服务器自动改成 synced。
4. 地址申请额度、耗尽行为和跨客户端分配一致性需要真实服务验证。App 已做 Site 范围排重，但不是对服务器原子分配实现的证明。
5. App 有版本/快照保护，不等于后端已提供原子条件写入或跨客户端合并。此次未看到独立基线版本条件字段，后端并发保证需另外确认，不能仅凭 `updateTimestamp` 推定。

以上是待确认的服务契约；本任务没有修改、部署或要求已完成任何服务器实现。

## 8. HDB 平台 / 网关对接仍需明确的事项

| 事项 | 已有事实 | 对接前必须确定 |
| --- | --- | --- |
| Zone 命名空间 | ICD 为每 gateway 最多 63；App 为每 Space 1–63 | gateway 与 Space 对应关系；一个 gateway 跨多个 Space 时如何避免 ZoneId 冲突 |
| 设备身份 | App 保存 UUID、主单播地址、可空 MAC | 外部 SensorId 与 Site/Space/Node 的映射；不能直接假定 SensorId 等于 UUID/MAC |
| Set | ICD 单播、ConfigurationZone=0；App 完整替换 0–8 目标 | 外部 Set 是否全量替换；ICD 数量为 1–8，0 清空需明确扩展契约 |
| Get | App Lighting Zones Get 为保存快照；ICD 有 Get_Ack | 返回“目标”还是“设备实况”；若投影为 NumberOfZone/LightingZones，按当前目标数组计算，不能把 pending 省略 |
| ACK / 错误 | App 有逐请求 ACK 和整设备 pending；ICD 有 Set_Ack/Set_Error 等 | 多 Model 部分失败、超时、重试与操作关联如何映射；不要擅自把 App 状态塞进标准 LightingZones 数组 |
| Mesh 地址 | App 已保存 ZoneId→groupAddress、设备 sensorGroupId | 网关如何获取同版本映射、何时刷新、如何确认节点初始化已就绪 |
| Sensor 能力 | 非空 sensorGroupId 表示已分配地址 | 不能凭该字段区分占用/照度，也不能确认设备配置完成；能力与就绪状态需额外契约 |
| Lighting Configuration | App 已保存参数并实现部分 Mesh 映射 | failsafe 真实行为、安装日期外部消费及控制效果，不能由 JSON 保存成功推定 |

发布依赖分开判断：App 配置与 SunSmart 云存储链可以独立验证；HDB 平台联动必须等待网关/HDB 团队完成映射和协议对接。固件团队负责确认 Composition、共享表、容量与掉电保持。外部代码与部署不在本项目 App 实施范围。

## 9. 本轮验证记录与最短验收

### 9.1 本轮实际执行

| 检查 | 结果 | 证明范围 |
| --- | --- | --- |
| `check_hdb_configuration.py` | 通过 | 生产 Codable/策略、完整目标及空目标、边界、schema；已有两份合成 JSON 的解码/校验 |
| `check_hdb_persistence.py` | 通过 | payload 往返、必填字段/身份拒绝、canonical 状态差异、旧对象保存保护 |
| `check_hdb_import_recovery.py` | 通过 | 提取生产 save/import 准备代码，验证选定恢复快照和损坏数据保护；存储为替身 |
| `check_hdb_integration.py --subelement` | 通过 | 使用实际映射 SDK 的 `isKeybindComplete` getter；FEFD/Sensor、0/8 Zones、同表关系、旧状态恢复和失败重试 |
| `check_hdb_integration.py --device-sync` | 通过 | HDB context/planner/store、标准 Site 隔离、地址分配失败/重试、恢复与清理 |
| `check_hdb_integration.py` | 通过 | 生产 Store/Service/Executor，完整重放、空目标、ACK、保存失败及迟到结果 |
| `check_hdb_space_creation.py` | **未通过：测试夹具编译失败** | `HDBMeshTestBoundaries` 与 `HDBSpaceCreationTests` 重复声明 Schedule/DeviceSwitchData；该脚本组合的 MeshLibManager 替身缺少 `subElementGroupSubscriptionModelIDs`。未执行创建断言，不能解释为业务创建代码已失败或已通过。 |

本轮只记录并定位测试夹具问题，没有擅自修复。建议后续在对应测试维护任务中修复组合边界并重跑创建回归。

SDK getter 被真实提取执行，但 Composition 关系、SDK 其余元数据、传输、数据库和云端仍有替身。原文 §21.6 记录了另一轮 SunSmart generic iOS Debug 构建通过；本次没有重新构建，也没有把历史构建或未运行的其他回归记入上述通过数。

### 9.2 待人工 / 联调验收

1. 新建 HDB Space：确认 63 个目录及地址登记；同 Site 再建 Space 不重复使用地址；额度不足时提示且不留下半成品。
2. 添加现场三 element 设备：空目标下保留 FEFD/Sensor；设 8 个 Zone 后清空，验证订阅容量、Auto/色温、本地感应与掉电恢复。旧缺 FEFD 设备执行完整 Sync，应结束补回/覆盖循环。
3. 失败/取消后退出重进，设备仍为 pending；完整重试后 synced，标准 Site 不产生 HDB 全量覆盖任务。
4. 上传含 pending、空目标、Sensor 和 Lighting Configuration 的项目，服务器回读、同版本另一客户端加载/分享导入均保留数据和 Group/Node 引用。受控环境验证丢 HDB/必填状态时不能误报云同步成功。
5. 网关/HDB 团队按第 8 节确认映射、0 清空和失败应答后，再验收 MQTT→Mesh→ACK 的端到端链路。

这些步骤未在本轮执行；不能以本文中的源码落地或隔离回归结果代替。
