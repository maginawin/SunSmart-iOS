# HDB 数据契约与设备 Model 数组配置

日期：2026-10-22。状态：已按确认方案完成 App 实现、相关离线回归与 SunSmart Debug generic iOS 构建；真实设备及外部联调待验收。

2026-10-22 格式已按 [v2 方案](261022_1626_HDB_json_format_plan.md) 更新；本次验证结果记录在该方案中。

本文是当前 HDB 数据对接入口；完整 JSON 见 [有效示例](261021_1806_HDB_unicast_example.json)，配置命令和参数见 [网关执行清单](261022_0945_HDB_site_configuration_commands.md)。早期摘要和旧 demo 已归档，不适用于当前格式。

## 1. 结论与范围

最新方案采用：**Delete All → Broadcast → Sensor Group（有地址才执行）→ Add Zones**。新增 devices[].broadcastModels 与固定 devices[].broadcastId="FEFD"（数值 65277），保留 App 既有 Broadcast 恢复任务。

本方案适用于重新创建的 HDB 项目。按用户最新要求，不处理旧设备、不提供旧数据迁移或旧字段缺失兼容；项目删除/重建由用户安排，本任务不自动删除项目。普通 Site 的既有行为保持。

必要边界：

- 普通初始化、SDK 配置完成判断以及全部 Auto/色温的现有 Broadcast 机制保留；撤销上一版取消 FEFD、增加 SDK 按 Node 策略和改为单播控制的计划。
- 三个数组分别表达 Zone、Broadcast 恢复、Sensor Group 接收的显式命令目标，不能互相代替。
- Preparation 的其他固定参数、Sensor Server 订阅与 publication 不属于本次 Set Lighting Zones 四阶段，继续各自执行。

## 2. JSON 契约

### 完整对象与必填字段

HDB 对象位于单份 Space payload 的 `spaceData.hdb`。Site 上传时该 Space 位于 `site.spaces[]`，单 Space 上传时位于请求的 `spaces[]`；不要把业务层级 `site.space.spaceData.hdb` 当成固定 HTTP 字段路径。

除 `devices[].lightingConfiguration` 可省略或为 null 外，下表字段均须存在；数组没有条目时写 `[]`。整个 `hdb` 缺失表示未提供 HDB 配置；已有 `hdb` 却为 null、损坏或缺必填字段时拒绝读取，不能当空配置保存。

| 字段 | 类型与约束 |
| --- | --- |
| `schemaVersion` | 整数 `2`；版本 1 拒绝读取、不迁移；不是 Space 更新时间 |
| `lightingZones` | Space 目录数组；新建 HDB Space 预建 63 个，目录与设备选择分别存储 |
| `lightingZones[].zoneId` | 整数 1–63，Space 内唯一 |
| `lightingZones[].name` | 非空字符串 |
| `lightingZones[].groupId` | 唯一的 4 位十六进制字符串地址；读取允许 `C000`–`FEFC`，新分配使用 `C001`–`FEFC`；不按 zoneId 推算地址 |
| `devices` | 设备数组；UUID 和主单播地址分别唯一 |
| `devices[].nodeUuid` | UUID 字符串，与同快照 Node 身份一致 |
| `devices[].nodeAddress` | 4 位十六进制字符串 `0001`–`7FFF`，设备 Primary Address |
| `devices[].mac` | 12 位无分隔符 MAC，例如 `AABBCCDDEEFF`；输入接受大小写、输出大写；null、缺字段、带分隔符均拒绝 |
| `devices[].lightingZones` | 0–8 个整数 zoneId，例如 `[1,2,3]`，不重复且引用本 Space 目录；是完整目标列表 |
| `devices[].lightingZonesStatus` | `pending` 或 `synced`；包括空目标在内的整设备 Zone 任务状态 |
| `devices[].sensorGroupId` | 4 位十六进制字符串 `C001`–`FEFC` 或显式 null；非空时设备间不重复、不与 Zone 地址冲突；分配还须使用全 Site 地址池 |
| `devices[].zoneModels` | 必填数组；条目为十六进制字符串 `elementAddress` 和 `modelId`，筛选规则见下文 |
| `devices[].sensorGroupModels` | 必填数组；由 Composition 生成，与地址是否已分配无关 |
| `devices[].broadcastModels` | 必填数组；本次 Reset 后必须恢复 Broadcast 的目标 |
| `devices[].broadcastId` | 必填字符串 `FEFD`（数值 65277），即使恢复清单为空也保留 |
| `devices[].lightingConfiguration` | 单设备字段配置对象或 null；当前导出保留该键；各参数为 `{ "status": "pending或synced", "value": 值 }` |

Lighting Configuration 只存于设备：不再输出根级 `broadcast`、根级 `lightingConfiguration` 或 `lightingZones[].lightingConfiguration`，不保留这些旧作用域的读写或迁移。解码器忽略未知键不表示会保存这些旧字段；服务端不得依赖旧字段往返保真。

| Lighting Configuration 字段 | value 类型、范围和新设备默认值 |
| --- | --- |
| `lightingControl` | 字符串 `Auto` / `Force_On` / `Force_Off`；默认 `Auto` |
| `failsafeDelay` | 整数 0–250；默认 5；当前仅保存业务值，不生成设备计时消息 |
| `dimIntensity` / `brightIntensity` | 整数百分比 0–50 / 50–100；默认 20 / 80 |
| `rampUpTime` / `rampDownTime` | 整数秒 1–3；默认 1 / 2 |
| `holdTime` | 整数秒 10–3600；默认 30 |
| `installDate` | 严格 `dd-MM-yyyy` 字符串；默认未设置；仅保存业务值，不发送设备命令 |

`lightingZonesStatus=synced` 要求本轮全部必要 ACK 和最终保存成功。失败、取消、中断或最终保存失败保持 pending，供整轮重试。Lighting Configuration 中设备下发字段由相应 ACK 确认，`failsafeDelay`、`installDate` 保存即完成；这些状态均不代表云上传成功、设备实时状态或真实运行验收。

### Model 清单通用规则

新增 `spaceData.hdb.devices[].zoneModels`、`spaceData.hdb.devices[].sensorGroupModels`、`spaceData.hdb.devices[].broadcastModels`，以及同级的 `broadcastId`。三个数组每项只包含十六进制字符串 `elementAddress`、`modelId`，表示命令目标，不表示设备当前订阅结果。

| 字段/Model | 数值或规则 |
| --- | --- |
| elementAddress | 4 位字符串，实际 Element 单播地址 `0001`–`7FFF`；不是 Element index |
| Generic OnOff Server | `1000`（数值 4096） |
| Light Lightness Server | `1300`（数值 4864） |
| Light CTL Temperature Server | `1306`（数值 4870，仅可能用于 Broadcast 恢复） |
| Light LC Server | `130F`（数值 4879） |
| Light LC Setup Server | `1310`（数值 4880） |
| Vendor 0x0A78 / 0x0001 | `0A780001`（数值 175636481） |

SIG modelId 使用 4 位、Vendor 使用 8 位；无 0x 前缀，统一大写输出。Vendor 字符串解析后的数值沿用 SDK 内存表示：`(Company ID << 16) | Vendor Model ID`。发送命令时仍分别编码 Company ID 与 Model ID，不能把解析后的 UInt32 直接当成四个小端字节写入消息。

共同约束：

- 三个数组均为新格式必填字段；没有目标时写 `[]`。缺字段、null、错误类型、负数、越界或错误模型引用均报错。此规则取代上一版“缺字段视为空数组”的旧数据兼容要求。
- `broadcastId` 必填且只能是字符串 `FEFD`，不允许 null 或其他地址；即使 broadcastModels=[] 也保留 broadcastId。它是固定共用地址，不参与 Lighting Zone/Sensor Group 地址分配，也不受 Sensor Group 地址唯一性约束。
- `sensorGroupId` 使用 4 位十六进制字符串或显式 null；null 表示本次 Zone 操作跳过 Sensor Group。0、空字符串不表示合法空值。
- sensorGroupModels 按 Composition 生成，不受 sensorGroupId 是否已分配影响。因此允许非空清单与 sensorGroupId=null 同时存在。
- 按 `(elementAddress, modelId)` 去重、排序；配置比较对数组顺序规范化，不忽略字段或同步结果。
- 条目必须属于当前设备，符合筛选规则；开始破坏性命令前，存储清单必须与本次 Composition 计算结果一致。
- schemaVersion=2，拒绝版本 1；不提供旧数据补齐或升级。Web/网关需同步采用新契约。
- `lightingZones=[]` 表示清空 Zone 选择，不意味着 zoneModels 为空。

### zoneModels

| Model | 收录范围 |
| --- | --- |
| Generic OnOff Server 0x1000 | 仅 Primary Element |
| Light Lightness Server 0x1300 | 所有 Elements，包括 Primary |
| Light LC Server 0x130F | 所有 Elements，包括 Primary |
| Light LC Setup Server 0x1310 | 所有 Elements，包括 Primary |
| Vendor 0x0A78 / 0x0001 | 仅 Primary Element |

实际执行 Zone 配置时设备须具备这五类：Primary 中必须有 OnOff 和指定 Vendor；另外三类在设备范围各至少一个。所有符合范围的实例都收录，不要求五类在同一 Element。

存储/序列化允许显式空数组，但不满足能力门槛、Composition 不完整或执行清单为空时，拒绝开始 Zone Set；不能把“未找到目标”记为成功。

### sensorGroupModels

遍历所有包含 SIG Light LC Server 0x130F 的 Elements，包括 Primary：

- 收录该 Element 的 0x130F。
- 同一 Element 有 SIG 0x1000、0x1310 时分别收录。
- 不收录其他 Element 的 OnOff/LC Setup，不加入 Lightness、Vendor 或 Sensor Server 0x1100。

sensorGroupModels 不一定是 zoneModels 的子集：非 Primary OnOff 可以进入前者，但不能进入后者。

### broadcastModels 与 broadcastId

broadcastId 固定为 65277（0xFEFD）。broadcastModels 表示 **本次 Zone Delete All 后需显式恢复 Broadcast 的目标**，不等于设备所有广播接收模型，也不是把 zoneModels 复制一份。

沿用现有 App Broadcast 恢复规则，但以本次新的 zoneModels 作为 Reset 影响范围的起点：

1. 遍历包含 SIG Light LC Server 0x130F 的所有非 Primary Elements：收录该 Element 的 0x130F，以及同 Element 实际存在的 0x1000、0x1310。
2. 遍历包含 SIG Light CTL Temperature Server 0x1306 的所有非 Primary Elements：仅当本轮 Reset 会影响其订阅时恢复。
   - 同 Element 存在与它共享订阅表的 0x1000、0x1300、0x130F、0x1310 时，收录其中实际共享的各个 Model。
   - 没有上述共享 Model，但按当前 App 的扩展链 Reset 处理它仍受影响时，直接收录该 0x1306。
   - 本轮 Reset 不影响它时，不加入本次恢复清单；原有初始化仍负责建立其 Broadcast 订阅。
3. 仅判断实际模型扩展/共享关系，不能因为在同一 Element 就把所有模型加入。仅匹配 SIG Model，排除相同低 16 位 ID 的 Vendor Model。去重并按 Element/Model 排序。
4. zoneModels 的“OnOff 仅 Primary”限制不套用到 Broadcast 恢复，因此 broadcastModels 可以包含非 Primary OnOff；也可以包含 zoneModels 中没有的 0x1306。
5. 只在不存在应恢复目标时输出 []。有应恢复目标却清单为空/不完整必须在 Reset 前报错；合法空数组跳过 Broadcast 阶段。

当前 HDB Reset 的本地缓存处理包含跨 Element 扩展链。目标生成复用现有机制并覆盖相关回归，不把缓存联动等同于固件已验证行为。Web/网关直接执行 App 提供的清单，不需要重新推导 SDK 的 relatedModels。

### 完整 HDB 对象示例

以下合成设备 Primary=256，包含 OnOff、Lightness、Vendor；Element=257 包含 OnOff、LC、LC Setup，Element=258 可包含 Sensor Server。地址尚未分配，`sensorGroupId=null`，Zone Set 跳过 Sensor 阶段。目录为便于阅读仅列一个 Zone。

<!-- hdb-complete-example -->
```json
{
  "schemaVersion": 2,
  "lightingZones": [
    {
      "zoneId": 1,
      "name": "Zone 1",
      "groupId": "C001"
    }
  ],
  "devices": [
    {
      "nodeUuid": "11111111-1111-4111-8111-111111111111",
      "nodeAddress": "0100",
      "mac": "AABBCCDDEEFF",
      "lightingZones": [
        1
      ],
      "lightingZonesStatus": "pending",
      "sensorGroupId": null,
      "zoneModels": [
        {
          "elementAddress": "0100",
          "modelId": "1000"
        },
        {
          "elementAddress": "0100",
          "modelId": "1300"
        },
        {
          "elementAddress": "0100",
          "modelId": "0A780001"
        },
        {
          "elementAddress": "0101",
          "modelId": "130F"
        },
        {
          "elementAddress": "0101",
          "modelId": "1310"
        }
      ],
      "sensorGroupModels": [
        {
          "elementAddress": "0101",
          "modelId": "1000"
        },
        {
          "elementAddress": "0101",
          "modelId": "130F"
        },
        {
          "elementAddress": "0101",
          "modelId": "1310"
        }
      ],
      "broadcastModels": [
        {
          "elementAddress": "0101",
          "modelId": "1000"
        },
        {
          "elementAddress": "0101",
          "modelId": "130F"
        },
        {
          "elementAddress": "0101",
          "modelId": "1310"
        }
      ],
      "broadcastId": "FEFD",
      "lightingConfiguration": null
    }
  ]
}
```

该对象可作为 `spaceData.hdb` 的值，不是完整 Space 导入包。带 63 个 Zone 和逐字段配置的样本见 [完整示例文件](261021_1806_HDB_unicast_example.json)；两个示例均纳入 `check_hdb_configuration.py` 的生产解码、校验及往返验证。

### Lighting Configuration 命令描述

设备级 `lightingConfiguration` 采用 [单目标命令描述契约](261022_1358_HDB_lighting_configuration_metadata_plan.md)：普通参数增加 `elementAddress/modelId/property`，lightingControl 直接增加 Auto、Force_On、Force_Off 三个地址字段；不增加 models 数组。目标为首个 LC 的同 Element Setup、首个 LC、首个 Lightness 或 Primary OnOff，具体随命令确定；三类订阅清单仍保留原本所有目标。

新描述存在于数据库和上传快照，导入及云端比较严格验证完整性与目标一致性，不接受旧格式缺字段。elementAddress 显式 null 仅表示设备无对应目标，不能执行 Set；字段缺失不能当成 null。failsafeDelay/installDate 不增加命令描述。下文完整 Space 与 HTTP 保存/回读约定也包括这些字段。

### Space 快照与 HTTP 对接

完整 Space 必须带同版本的 `spaceData.hdb`、`groups`、`nodes` 和正常 Mesh 数据。Zone 地址引用非 virtual Group；非空 Sensor 地址引用 `isVirtual=true` 的 Group。此标记是 App/SDK 的用途分类，Sensor 地址本身仍是普通组地址，不是 Label UUID。Node UUID、Primary Address、Model 清单必须相符；读取到有效 Node MAC 时还须与 HDB MAC 一致。HDB 的 nodeAddress、elementAddress、sensorGroupId、broadcastId、modelId、property、groupId 均使用十六进制字符串；HDB 中不再输出 groupAddress。SDK `groups[].address`、`nodes[].unicastAddress`、Model 标识保持原十六进制字符串格式。

以下为区域 baseURL 后的现有 App 接口，方法均为 **POST**：

| 用途 | 路径 | 请求结构 |
| --- | --- | --- |
| 上传 Site 与 Spaces | `/sitespace/sync/siteprops` | `site`（其中 `spaces[]` 为 Space payload）、`user`；新 Site 另带 `devicesInSetle` |
| 上传单 Space | `/sitespace/sync/spaceprops` | `siteId`、`spaceId`、`spaces: [SpacePayload]`、`userId` |
| 读取基线及上传后回读 | `/sitespace/get/spaceprops` | `siteId`、`spaceId`、`passwd`、`userId`；响应 `data` 为 Space payload |
| 申请地址 | `/sitespace/address/claim` | `siteId`、`addrType`、`number`、`userId`；App 消费返回的 `provisioner` 地址资源 |

保存和回读须保留全部目标、显式 null、空数组、三个 Model 清单、固定 broadcastId 和设备/字段状态，不能过滤 pending 或由服务器改写为 synced。App 保存后按既有机制排队同步，导出提交快照，回读比较后只确认该提交版本；期间新增本地修改仍待上传。HTTP 200 或 Mesh ACK 均不能单独替代该回读确认。

当前未承诺未知字段经旧 App 解码/编码后仍保留，也不提供旧 HDB 结构迁移。服务端地址分配并发保证、跨客户端写入一致性及完整字段往返须由服务端团队联调确认；本契约不表示外部实现已完成。

## 3. Set Lighting Zones：完整执行约定

### 3.1 开始前验证与保存

- 核对 HDB Site/Space、设备身份、编辑权限、AppKey/Model 绑定及任务占用。
- 从该设备 Composition 一次性生成三个数组；核对 Primary、五类能力和所有模型引用。
- 目标 zoneId 去重且最多 8 个，全部能在 `hdb.lightingZones` 找到；实际地址字段名是 `groupId`，按十六进制解析得到 Mesh 组地址。
- sensorGroupId 非空时验证其为该设备的有效 Sensor Group 地址，不与 Lighting Zone 冲突；sensorGroupModels 必须非空。无效地址/有地址无目标必须在 Delete All 前报错，避免先清空再发现计划不可执行。
- 验证 broadcastId="FEFD"，并核对 broadcastModels 完整覆盖本次 Reset 所需恢复目标。
- 保存三个清单及 broadcastId、目标 Zone 选择和 `lightingZonesStatus=pending` 后才开始发送；保存失败不发送。捕获不可变执行计划，后续以同一计划校验身份、配置变化和 ACK。

### 3.2 Delete All

遍历全部 zoneModels，逐项发送 `ConfigModelSubscriptionDeleteAll`。

所有项均收到成功 `ConfigModelSubscriptionStatus` 后才进入下一阶段。失败、超时或取消立即停止后续阶段。

### 3.3 Broadcast

broadcastModels=[]：跳过本节。

否则遍历全部 broadcastModels，逐项发送 `ConfigModelSubscriptionAdd(broadcastId)`，即 Add(65277)。所有项均成功后才进入 Sensor Group 阶段。

不能在 Delete All 尚未全部成功时开始恢复；后续 Reset 可能再次清除已添加的 Broadcast 地址。

### 3.4 Sensor Group

sensorGroupId=null：跳过本节，不因设备存在 Sensor Server 在本次 Zone 任务中自动插入分配或其他命令。

sensorGroupId 非空：遍历全部 sensorGroupModels，逐项发送 `ConfigModelSubscriptionAdd(sensorGroupId)`，全部成功后继续。

设备添加 Preparation 仍负责原有 Sensor Group 分配与 publication；其是否准备完成是独立生命周期条件，不改写本节的空地址语义，也不重新引入 sensorGroupModels 为空必须等价于 sensorGroupId=null 的旧约束。

### 3.5 Add Zones

遍历选中的 zoneId，读取其 `hdb.lightingZones[].groupId` 并按十六进制解析；对每个地址遍历全部 zoneModels，逐项发送 `ConfigModelSubscriptionAdd(groupAddress)`。

目标 Zone 为空时跳过本节；前面已执行的 Delete All、Broadcast 和必要的 Sensor Group 订阅仍有效。

### 3.6 目的地址、结果与重试

- 上述配置命令统一发送到设备 Primary Address（nodeAddress），参数填入每项的 elementAddress 和 Model 标识。Vendor 使用带 Company ID 的格式。
- 只在所有实际需要执行的命令均成功后写 `lightingZonesStatus=synced`。
- 目标 Zone 为空且 sensorGroupId=null：仍须完成 Delete All 和必要的 Broadcast；仅当 broadcastModels 也为空时，Delete All 全部成功即完成。
- 部分成功、失败、取消、断连或持久化失败保留 pending；重试完整执行 Delete All → 可选 Broadcast → 可选 Sensor → 可选 Zones。
- 不因个别 Add 成功提前标记整台设备完成；迟到 ACK 不得确认新一轮任务。已接受的设备回执缓存沿现有机制保存。
- 保留现有绑定、权限、身份与任务生命周期保护。Reset 后到 Broadcast 恢复完成期间，仅对本轮承诺恢复的接收目标使用现有临时就绪豁免；其他缺绑定、缺 publication 等错误仍阻断任务。

## 4. 数据与任务实现

1. 在现有 HDBConfiguration.swift 内新增三个数组、broadcastId 和十六进制字符串编码条目。内部可继续复用 HDBModelTarget，保留其原字符串编码以避免波及 Preparation 的内部签名。数据库继续使用 hdb JSON 列。
2. 在现有 Policy 中增加明确接收 Primary Address 的 Zone/Sensor 筛选函数，Broadcast 复用现有恢复目标计算并接入新的 Zone Reset 集合。Preparation、Lighting Configuration 和诊断使用到的原通用模型集合不能整体收窄，尤其不能漏掉非 Primary Vendor 初始化。
3. 新设备创建、已授权配置保存、设备重入网/Composition 更新时保存相应清单；变化在操作前完成，不能在 Delete All 过程中改写本次计划。删除设备时随设备条目删除，不做旧项目补齐或批量迁移。
4. 导入严格验证新字段、Composition 引用及事务读回；导出输出已经生成并核验的三个数组及 broadcastId。只读导出不修改数据库、不自动分配组、不发送 BLE。新格式不完整时报告问题，不临时合成兼容数据掩盖写入缺陷。
5. canonical 比较包含排序后的三个数组、broadcastId 和现有状态，保证本地保存、导出、云端回执使用同一快照；不增加旧字段兼容归一化。
6. Zone 页 Set/Retry 与普通设备同步统一使用相同四阶段生成器；保留 broadcastTargets/broadcast stage，并将持久化 broadcastModels 映射到同一执行目标。生成、保存、导出、任务捕获和 ACK 校验共用同一结果；broadcastId 固定校验后作为恢复地址，不能出现 JSON 与发送参数分离。sensorTargets 由 sensorGroupModels 得出，是否发送仅由 sensorGroupId 决定。
7. 更新仓库 JSON 示例与本任务文档中的接口约定。桌面示例不在本轮修改。Web/网关/服务端由对应团队同步解析和保存新字段，不由本任务修改其代码或部署。

## 5. 保留 Broadcast 后的改动边界

- 保留 SiteViewController 的现有子 Element Broadcast 配置、SDK 普通初始化发送与配置完成检查，不增加上一版提出的按 Node SDK 扩展点。
- 保留 Devices 页全部 Auto/色温的 0xFEFD 控制，Lighting Zone 组地址控制也保持原规则。
- 保留现有 Reset 后 Broadcast 恢复、部分成功缓存保存、重试和临时就绪豁免机制。新的 zoneModels 收窄后，必须重新计算真正受影响的恢复范围，不能把旧全 Element Zone 集合继续用于 Reset 影响分析。
- 更新诊断：显式目标按三个数组及其地址确定，并考虑同 Element 共享订阅表。被排除的非 Primary Vendor 不再要求 Zone 订阅；非 Primary OnOff 不能简单按“必须为空”判断。未受 Reset 影响的非 Primary CTL Temperature 仍可能需要初始化建立的 FEFD，不能因它不在本次 broadcastModels 就误报该订阅多余。
- 本需求未新增 SDK API，未修改 SDK。现有 one-dev SDK 的既有差异继续保留；本地映射已核对，正式 SDK 发布状态不属于本轮验证结论。

## 6. 验证与验收

- 编解码：新格式往返、显式空数组、缺字段拒绝、8 位 Vendor、重复/乱序、越界、错误设备/Model 引用；持久化重载、导入回滚及上传回执一致。
- 精确目标：Primary 与多个子 Element；Zone 排除子 Element OnOff/Vendor；Sensor 仅收录 LC 所在 Element 的指定 Models；三数组不要求包含关系；Broadcast 覆盖非 Primary LC、受影响/不受影响 CTL Temperature、同 Element 共享模型及直接 0x1306 fallback。
- 四阶段：有/无 Broadcast 目标、有/无 sensorGroupId、有/无目标 Zone，多个 Zone 与多实例；顺序及参数与三个数组完全一致；broadcastId 非 65277 在 Reset 前拒绝。
- 生命周期：前置失败不得先 Delete All；每阶段部分 ACK、超时、取消、断连、存储失败及重试；Reset 暂时清掉 FEFD 后 Broadcast 恢复仍可执行；恢复完成后后续 Sensor/Add 正常，失败可重试，不能永久卡在未就绪。
- 回归 Preparation：全部 Vendor 固定初始化、Sensor Server 订阅、Presence publication 和灯光参数行为保持。
- HDB/普通 Site 切换、离线读取及设备添加回调；现有 SDK 初始化要求保持，临时恢复豁免不降低其他配置要求。
- HDB 全部 Auto/色温保留原控制路径，设备验收确认 Broadcast 恢复后可响应；诊断正确区分 Zone、Broadcast 和 Sensor 预期。
- 优先扩展现有 HDB configuration、persistence、import recovery、device preparation、subelement、diagnostics 和相关控制回归；复用现有 SDK 就绪检查夹具验证临时恢复路径。
- 完成后用 SunSmartLocal.xcworkspace 构建 SunSmart Debug generic iOS，无签名、无 Simulator。共享逻辑无品牌分支且无资源/依赖配置变化时以代表 target 验证；如实施引入跨品牌配置/API 风险再扩大构建范围，不默认增加 Release。
- 真实验收由用户操作：新建 HDB 项目，添加多 Element 设备，核对导出的三个数组与 broadcastId；Set/清空/Retry 后读回订阅并检查 FEFD 恢复；确认后续同步、诊断及全部控制。Web/网关按相同 JSON 和四阶段联调。离线测试与构建不能替代设备/外部联调。

## 7. 实施交付与验证结果

已实现并接通以下行为：

- 新设备、Composition 更新、设备恢复及 Zone Set/Retry 保存三个 Model 清单（JSON 使用十六进制字符串）；空数组显式输出，缺字段或错误 broadcastId 拒绝导入。
- 导入及导出核对 Composition 与清单一致性；导出不修复数据。保存失败不开始发送；执行计划包含三个清单及 broadcastId，过期回执不能确认已变化的配置。
- Zone Reset/Add 使用新的 Primary 限制；Broadcast 与 Sensor 使用各自清单，按四阶段屏障执行。Preparation 保留全部 Vendor 初始化，普通 Broadcast 初始化与控制入口保持。
- 诊断考虑共享订阅表，区分本轮需恢复的 FEFD 与普通初始化已有的 FEFD。仓库示例已更新：`docs/261021_1806_HDB_unicast_example.json`；未改桌面原文件。

本轮验证：

- configuration、persistence、import recovery、integration、subelement、diagnostics、lighting configuration/service/messages、lighting zone execution、group lifecycle、space creation 相关脚本通过。
- device preparation 脚本中的 preparation、device sync、device tasks、add completion、add execution 组件通过；随后更新旧子 Element OnOff 断言，单独重跑 subelement 通过。
- 回归覆盖JSON/缺字段/空数组、精确模型筛选、多阶段顺序、空 Sensor Group/空 Zone、Broadcast 共享与直接 0x1306 恢复、取消/失败/重试/迟到回执、模型变更持久化与旧计划失效、非 Primary Vendor 初始化保留。
- SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建通过。此次为共享逻辑变更，没有品牌资源、工程或依赖配置变更，未扩大至其他品牌或 Release。
- `git diff --check` 通过。上述回归使用隔离的数据库/SDK/通信边界，不代表完整 App 导入、真实 SQLite、BLE、云端或网关联调已经验收。

最短人工验收：

1. 新建 HDB 项目，添加多 Element 设备；导出后核对三数组、Primary 限制和 broadcastId="FEFD"，再用新格式导入并确认数据保留。
2. 设置多个 Zone，再清空 Zone；读回订阅，确认 Zone 变化、Sensor Group 与 FEFD 恢复，并验证全部 Auto/色温控制。
3. 配置中断后重试，确认完整执行四阶段、完成状态正确且诊断无错误预期。Web/网关团队用同一 JSON 核对目标与命令次序。

交付基线：分支 feat/HDB-261020，HEAD=9964b7cd；本轮改动未提交。保留既有 AGENTS.md 与 `docs/261022_0945_HDB_site_configuration_commands.md` 改动。构建使用 `.local-sdk/nordic-sig-mesh-sdk` 映射到 one-dev（HEAD=8c5af55，含原有未提交差异）；本轮未修改该 SDK，未更改正式远端依赖。真实设备由用户验收，Web/网关/服务端配套由对应团队实施。
