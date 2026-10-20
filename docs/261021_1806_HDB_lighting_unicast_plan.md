# HDB Lighting Configuration 固定 Unicast 更新方案

日期：2026-10-21。状态：已按确认方案完成 App 实施，相关离线回归与 SunSmart generic iOS Debug 构建通过；真机及网关联调待人工验收。

## 1. 结论与范围

移除 `HDB configuration → Lighting configuration` 的整个 Transmission 选择行，固定配置单个灯设备。删除 HDB 根级 `broadcast` 和 `lightingZones[].lightingConfiguration`，只在 `devices[].lightingConfiguration` 保存灯光参数及字段状态。

用户原文同时提到“移除 Multicast 和 Unicast”及“固定 Unicast”，本方案按最终行为理解：不再提供发送模式选择，App 使用 Unicast，广播/组播参数配置由网关负责。

- 保留 Target 单灯选择、Override、Intensity、Soft Dimming、Time Delay、Install Date 及现有字段范围、默认值和状态语义。
- 保留 Lighting Zones 目录、设备与 Zone 的关系、Sensor Group、设备准备和订阅能力。网关仍需要这些数据，不能因字段名含 broadcast 就删除子 element 的 `0xFEFD` 订阅。
- 范围限定为 Lighting configuration 的参数配置。独立的 Lighting Zones 控制入口及普通 Group、Scene、Profile 等功能不随本次移除。
- 不实现 HDB 旧格式迁移，也不保留旧广播/Zone 配置的兼容读写；普通非 HDB 数据兼容必须保留。
- 仅实施 App。预计不需要新增 SDK API、修改依赖、数据库列或服务器接口；网关/服务器是否存在依赖旧字段的实现尚无运行证据，交由对应团队核对。

## 2. 修改前已核实的完整链路

| 环节 | 当前实现 | 本次含义 |
| --- | --- | --- |
| 页面 | `HDBLightingConfigurationViewController` 默认 `.broadcast`，三个模式决定目标列表和 Get 行为 | 不能仅隐藏两个选项；必须调整初始选择、空列表及按钮可用性 |
| 下发 | `HDBLightingConfigurationService.set` 按 scope 选设备；Unicast 等待 ACK，其他模式在发送完成后记成功 | 收敛为单设备 acknowledged 消息，删除广播覆盖判断和组播分支 |
| 参数合并 | `HDBLightingConfigurationPolicy.record` 同时可写设备、Zone、broadcast | 删除聚合范围读写，单设备操作不能影响其他设备或 Zone |
| 模型 | `HDBConfiguration.broadcast`、`HDBLightingZone.lightingConfiguration` 参与 Codable / Equatable | 必须删除模型属性和对应编码、解码、校验，导出中连 null 占位也不保留 |
| 本地与云端 | `Database` 编解码同一模型；Store 保存并排队同步；`ExportData` 调用 `json`，`ImportData` 调用 `decode/validateReferences` | 修改共享模型可贯通保存、重启、导入、上传；不另建平行 JSON 转换逻辑 |
| 一致性与清理 | `SpaceConfigurationIntegrityPolicy` 使用 HDB canonical；`SpaceSyncCleanupPolicy` 用 HDB 地址识别专用分组 | 保留地址及引用，确保普通分组清理、快照比较和恢复不受影响 |
| 后续恢复 | `HDBDeviceSyncService` 已从设备配置构造 acknowledged 参数任务 | 复用当前失败恢复，不再依赖 Zone / broadcast 保存值 |

生产 scope 使用方集中在该 Controller、Service、Policy；`HDBLightingMessages` 的消息构造还供设备初始化/同步使用。清理发送分支时必须同步核对这些使用方，保持现有协议参数与 Force Off 的 primary OnOff 选择规则。

主要源码依据：

- [页面](../SunSmart/Main/Space/HDB/Controller/HDBLightingConfigurationViewController.swift)、[配置服务](../SunSmart/Main/Space/HDB/Model/HDBLightingConfigurationService.swift)、[配置策略](../SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift)。
- [HDB 模型](../SunSmart/Common/Data/HDBConfiguration.swift)、[校验与 JSON 策略](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)、[配置存储](../SunSmart/Common/Data/HDBConfigurationStore.swift)。
- [数据库](../SunSmart/Common/Data/Database.swift)、[导入](../SunSmart/Common/Data/ImportData.swift)、[导出](../SunSmart/Common/Data/ExportData.swift)、[一致性比较](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift)、[快照清理](../SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift)。
- [设备同步](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift)、[消息构造](../SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift)。

## 3. 实施方案

### 3.1 页面与交互

1. 首区只保留 Target 单灯选择；删除 Transmission 控件、切换回调、全 Space / Zone 目标选项。
2. 页面持有可选的目标设备 UUID。初次进入按当前主地址排序选第一盏灯；刷新时优先保留仍有效的选择。目标消失后清空草稿与已保存状态并回到未选择状态，用户重新选择后才能操作，避免把上一台设备的草稿发给另一台。
3. 没有灯或没有有效选择时，展示可国际化的空状态并禁用 Set / Get / Save Failsafe 和字段修改；不能以空目标成功保存。
4. 切换设备时从该设备重新加载保存值，再按现有默认值规则补齐草稿。执行中禁止切换；离页沿用现有取消流程。
5. Get 保持当前 Unicast 的真实设备读取行为；Install Date 仍读保存值。Failsafe Delay 与 Install Date 仍按现有元数据方式保存，不新增 Mesh 消息。
6. 更新 `hdb_lighting_scope_help` 中英文说明；删除无引用的旧模式专用 Key 前检查全项目使用方。保留共用字段及状态文案。

### 3.2 服务与发送

1. 将 Service 的 `saved/set/get` 和 Policy 的保存入口收敛为明确的单设备 UUID，移除只用于此页面的广播/组播 scope；不留下可绕过 UI 的聚合入口。
2. 复用 `writes` 和 `targets` 生成所选设备各匹配 element 的命令，始终使用带应答消息。Unicast 指发送到正确 element 的单播地址，不是把所有命令都发到 `nodeAddress`。
3. 保留写入前权限、设备准备、连接、AppKey、设备身份和应急状态校验。单播不应因设备 Zone 订阅 pending 或没有加入 Zone 而新增阻断。
4. 保留先保存 pending 意图，再逐项发送和核对 ACK 的顺序；同字段所有目标 element 成功后才能置 synced。其他设备和未选择字段不变。
5. 保留共享会话、取消结算、配置 revision 和身份校验。超时、取消、失败或失效回调不能把未完成字段标记 synced；旧回调不能覆盖较新值。
6. 继续使用现有恢复入口：Intensity / Soft Dimming / Time Delay 的 pending 由设备同步恢复；Override 沿用用户明确 Set 的路径，不新增重启后自动重放 Force On / Force Off。
7. `HDBLightingMessages` 若同步移除已无生产使用方的 unacknowledged 分支，仅调整该 helper 与现有调用点；不改变共享 SDK 或 Zone 控制机制。

### 3.3 数据结构与普通数据兼容

| 路径 | 更新后 |
| --- | --- |
| `spaceData.hdb.schemaVersion` | 建议本次继续为 `1`，按无旧 HDB 迁移要求更新当前契约；不把版本值解释为兼容历史所有 schema-1 数据 |
| `spaceData.hdb.broadcast` | 完全移除 |
| `spaceData.hdb.lightingZones[]` | 仅 `zoneId`、`name`、`groupAddress` |
| `spaceData.hdb.devices[].lightingConfiguration` | 保留现有字段级 `{status, value}` 结构 |
| `spaceData.hdb.devices[]` 其余字段 | 保留身份、MAC、成员完整列表、`lightingZonesStatus`、`sensorGroupId` |

不增加 `transmission` 字段；固定单播是 App 执行策略，不需要存入 JSON。

- 删除 `HDBBroadcastConfiguration`、HDB 根级旧 `lightingConfiguration` 的特殊兼容分支和 Zone 配置的 Codable / 校验逻辑。新编码器不得输出上述已删除 Key。
- 不编写旧 HDB 迁移、补值、合并或旧字段保真逻辑，也不新增清库流程。历史 HDB 测试项目由使用方重建；若通用 Decoder 自然忽略未知旧 Key，不等于承诺旧数据无损兼容。
- 普通旧项目缺少整个 `hdb` 时继续解码为 nil，保存与再导出不得自动补 HDB、创建 Zone 或改变正常节点/分组配置。
- 保留合法空 HDB 集合和空设备成员列表；新建 HDB Space 仍按现有逻辑预建 63 个 Zone，不能把这一创建规则新增为所有读入数据必须有 63 项的限制。
- `mac` 按第 7 节改为必填有效字符串；保留 `sensorGroupId` 的必填 Key / 可 null 语义、设备字段状态、值范围、设备与 Zone 唯一性和引用校验。损坏的新格式不能回退为空或绕过完整性校验。
- 继续保留导入恢复事务、当前权限/网络身份检查与并发保存基线；普通的 Scene、Profile、Trigger Zone、Proximity、Timed 等数据不改格式。
- 共享模型负责编码收敛，Database / ExportData 无需修改。ImportData 仅在对应 Node 的 MAC 缺失或格式无效时，使用同份已校验 HDB 记录的 MAC 补齐；必须匹配 UUID 和主地址，普通无 HDB 数据保留原行为。

### 3.4 网关与服务器契约

网关按 `lightingZones[].groupAddress`、`devices[].lightingZones` 和设备级参数实现其广播/组播策略。不同设备可能保存不同参数；本次不规定网关如何合并不同值，也不在 App 添加新的 Zone 统一值或广播配置。

服务器/网关团队需要核对是否校验或读取已删除字段，接受新 payload 缺少这些字段且不补回，并保持关联的 `groups`、`nodes` 与 `spaceData.hdb` 属于同一快照。网关如何执行、如何回传执行结果属于外部契约，尚未由本次 App 分析证实；App 的字段 synced 不能当作网关已执行或云上传成功。

这些配套由对应团队实施。本次 App 工作可独立推进；端到端交付需使用支持新契约的网关/服务器验证，旧新版 HDB 客户端混用不属于兼容承诺。

## 4. JSON 参考

[完整 HDB 对象示例](261021_1806_HDB_unicast_example.json) 包含 63 个 Zone 和两台合成设备，可作为 `spaceData.hdb` 的值。它不是完整 Space 导入包；完整 payload 仍需匹配的 `nodes`、`groups` 等正常数据。

- 示例地址采用十进制整数：49153 = `0xC001`；完整目录示例用连续地址，仅为便于阅读，实际分配由地址池决定，不可通过 zoneId 推导地址。
- 两台设备 MAC 为合成示意值 `AA:BB:CC:DD:EE:01` / `AA:BB:CC:DD:EE:02`，均非空，不代表现场设备。
- 第一台设备展示已保存/完成的配置；第二台展示 Intensity 部分完成及 Zone pending。它们是契约示意，不是真机测量值。
- `sensorGroupId` 示例 49216 = `0xC040`，需对应同一 Space 中 App 标记 `isVirtual=true` 的 Group；这里不代表新增 SIG 虚拟地址约定。
- `lightingControl` 可取 `Auto`、`Force_On`、`Force_Off`。亮度值为百分比；Ramp / Hold Time 为秒，Install Date 为 `dd-MM-yyyy`。
- `failsafeDelay`、`installDate` 的 synced 沿用当前“元数据已保存”的含义；不表示这些字段已经通过 Mesh 下发。
- 新增设备初始值仍为 Auto、Failsafe Delay 5、Dim 20、Bright 80、Ramp Up 1、Ramp Down 2、Hold 30；需下发字段初始 pending，Failsafe Delay 初始 synced，Install Date 未设置时不输出字段。

## 5. 实施后的必要验证

| 范围 | 关键行为 / 现有入口 |
| --- | --- |
| JSON 与空值 | `check_hdb_configuration.py`：新模型往返没有删除的 Key；63 Zone 示例、空 devices、空成员、有效 mac 必填，sensor null 合法，缺少保留必填字段及非法引用仍拒绝。替换旧 broadcast 保真用例与脚本引用的旧示例，旧示例可保留为历史材料 |
| 单设备路由 | `check_hdb_lighting_configuration.py`、`check_hdb_lighting_messages.py`：仅所选设备各目标 element；Force Off 仅 primary OnOff；无广播或组播目的地址 |
| 服务状态 | `check_hdb_lighting_configuration_service.py`：逐字段、多 element ACK、超时/取消/迟到回调、其他设备不变、无目标拒绝、未准备限制及离线元数据保存；将原广播/组播场景改为单播等价行为，保留失败/取消覆盖 |
| 持久化与普通兼容 | `check_hdb_persistence.py`、`check_hdb_import_recovery.py`、`check_space_sync_cleanup.py`：保存重载、配置比较、导入重试、旧普通数据无 hdb、新 HDB 与正常 Group/Scene 等共存；补缺少的行为夹具，不能只检查源码文本 |
| 初始化与恢复联动 | `check_hdb_space_creation.py`、`check_hdb_integration.py`：新建默认目录、设备初始化、pending 参数恢复和成员数据保留；若改变共享消息 helper，补相关设备准备回归 |
| 文案与构建 | 更新英文/简体中文文案，核对五品牌资源及 Sources 归属。实现稳定后核对 workspace/SDK realpath，构建一次代表 SunSmart generic iOS Debug；出现品牌编译差异或资源归属风险再扩大 |
| 人工验收 | 无灯进入、选择 A 修改/读取、切到 B、A 发送失败重试、发送时离页再进入、查看新导出 JSON；另由对应团队验收网关消费新结构 |

影响品牌为 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。当前相关源码均列入五品牌 Sources；计划不新增文件归属、编译条件或 SDK API，不机械重复五品牌乘 Debug/Release。

## 6. 交付与实施基线

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-HDB-261020`；分支 `feat/HDB-261020`；HEAD `355632ee`。未提交 Git。
- 开始实施前已有 16 个修改文件；其中 8 个保持逐字节不变，另 8 个仅在本任务相关位置集成。保留设备准备、Sensor / subelement、Auto 过渡时间等已有工作；其他任务文档未修改。
- 同一任务继续更新本文与 JSON 示例。最终实现和验证记录见第 8 节。

## 7. 已确认补充：HDB 的 MAC 必填

用户追问“有没有可能必须有 mac 值，不能为 null”。结论：可以作为新的 HDB 业务契约，但必须补齐写入来源与失败处理，不能只改属性类型。用户已确认采用本节约束，第 3/4/5 节及 JSON 示例已同步更新。

### 修改前核实事实

- 当前 HDB 初始化 `prepareIntent` 和 Lighting Configuration 补建设备记录时直接传入 `mac: nil`；Lighting Zones 保存时才读取并规范化 `node.macAddress`。这是 HDB 记录为空的明确来源，不证明设备没有 MAC。
- 本机 SDK 映射已核对为 `one-dev`。`MeshAddDeviceManager.startScan` 与 `startScanRestoreDevices` 的标准扫描回调均要求 `device.macAddress` 非空才返回设备；来源为厂商广播中的 6 字节，或已有厂商格式设备名称。FastAdd 完成配网时会把这个值写到 Node。因此正常扫描添加/恢复链路具备填入 MAC 的来源。
- App Classic / Professional 添加完成回调仍有“没有 MAC 则随机生成”的兜底分支。它的存在不等于当前标准扫描路径会触发，但说明仅检查 `node.macAddress` 非空或格式正确不能证明是硬件值。
- 普通云端导入允许 `nodes[].macAddress` 缺失，普通导出将 nil 写为空串；SDK 本地 Node MAC 也可空。这些普通数据兼容不能随 HDB 契约一起收紧。

### 已采用的 HDB 专属约束

1. 新 HDB `devices[].mac` 必填，保存为大写冒号分隔的 6 字节字符串；缺字段、null、空串和非法格式均不接受。`sensorGroupId` 仍可 null，空 devices 数组仍合法。
2. 复用并提取当前 HDB MAC 规范化逻辑，让设备添加/初始化、Lighting Zones、Lighting Configuration 和恢复使用同一来源与校验；HDB 初始化不能先落 null 再等待另一个页面补齐。
3. HDB 新增/恢复在可确认的最早入口检查扫描 MAC，避免走普通添加的随机 MAC 兜底。缺失时明确报错、保留重试入口，不生成假的 MAC 或把 UUID/主地址当 MAC。
4. 如果流程已完成配网才发现缺失，保留现有节点并报告 HDB 配置未完成，不能宣称添加完整成功，也不能自动删除已入网设备。补得可靠 MAC 后应能重新进入同一初始化流程，不能被先前写入的半成品 HDB 自己阻断。
5. 导入只对存在的 HDB 设备记录施加新约束，继续验证 UUID/地址引用；同一节点两处均有有效 MAC 时核对规范化后的值一致。快照中的字符串不能离线证明硬件真实性，可信来源与字段格式校验需分别表述。
6. 不修改普通 Node 的可空模型、通用导入规则或普通项目的随机值兼容行为。旧 HDB 无 MAC 的数据按用户既定范围不做迁移。

本轮同步更新示例与相关测试，覆盖真实扫描 MAC 写入、规范化、缺失失败后重试、恢复身份更新、新 HDB 非法 MAC 拒绝、普通无 MAC 数据继续可导入。上述来源判断为源码证据，未做设备扫描或外部网关联调。

## 8. 实施与验证记录

### 已实施

- 删除 Transmission 行和 HDBLightingScope，Target 只选一盏灯；首次选首台，目标消失后清空选择/草稿，无目标禁用操作，执行时禁止切换。补齐中英文提示。
- Service / Policy 仅接收设备 UUID，所有配置写入均使用带应答的消息，保留多 element、逐字段确认、取消结算、版本与身份校验；既有 Auto 省略过渡时间的行为保留。
- 模型删除 broadcast 与 Zone lightingConfiguration；设备 mac 为非可选 String，新 HDB 拒绝缺失/null/空串/错误格式，规范化 scanner / Node 常用格式。原普通数据兼容、Zone / Sensor 地址与订阅保留。
- 添加与恢复前在 HDB 专属校验中锁定扫描 MAC，HDB 不进入随机 MAC 兜底；普通 Site 保留原路径。配网后若缺 MAC，不写半成品 HDB，现有完成协调器报告未完成并允许重试。
- 初始化、Zone 保存和 Lighting Configuration 补记录复用同一设备元数据入口；恢复把地址和 MAC 同次保存，避免中间上传的两者身份不一致。
- 导入保持 UUID/地址引用校验；两处都有有效 MAC 时必须一致。节点扩展缺失 MAC 时，使用同一已校验 HDB 记录补齐，普通项目仍可没有 MAC。

### 自动化验证

- 已通过：configuration（含 schema）、lighting_configuration、lighting_configuration_service、lighting_messages、persistence、import_recovery、space_sync_cleanup。
- 已通过：device_preparation（包括 device-sync、device-tasks、add-completion、add-execution、subelement 五种集成模式）、integration、space_creation、group_lifecycle、zone_control、presentation。
- 消息夹具补充了 acknowledged 协议声明。Space 创建夹具合并共享 Schedule / DeviceSwitchData 定义并补 subelement 属性，使其匹配当前已有共享边界；生产创建/删除逻辑没有因此调整。
- 本地 SDK 已核对为 `.local-sdk/nordic-sig-mesh-sdk` → `one-dev`，revision `8c5af55`，SDK 工作树干净，本任务未修改 SDK。
- SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建通过（exit 0）。最终兼容性调整后增量构建亦通过。使用工作树稳定目录 `SunSmart-feat-HDB-261020-unicast`，与其他任务构建目录隔离。
- 最终补测普通 Site 使用原回调 MAC、HDB 添加前拦截，以及单设备 Get 部分读取失败：回显 incomplete，不改变保存值/状态；对应添加完成与配置服务回归通过。
- 五品牌共享源码与 Localizable.strings 归属核对通过；英文/简体中文 strings 语法与新增 Key 检查通过；JSON 示例、文档链接和 `git diff --check` 通过。
- 未自动运行真机、服务器或网关，未进行其他四品牌构建；本次未新增品牌编译差异或资源归属。App 离线结果不代表外部实现已适配。

### 最短人工验收

1. 新 HDB Space 添加灯，导出确认 mac 非空且无 broadcast、Zone lightingConfiguration；原普通项目仍正常打开和导入。
2. Lighting Configuration 无 Transmission；选择 A Set/Get，再选择 B，确认值与状态不串设备。
3. 中断 A 的参数设置后重新进入，未确认字段保持 pending，重试可完成；无灯/目标移除时不可继续写入。
4. 缺失 MAC 的 HDB 添加应报明确错误，补齐后可重试；对接团队验证网关按新结构消费目录、成员和设备参数。
