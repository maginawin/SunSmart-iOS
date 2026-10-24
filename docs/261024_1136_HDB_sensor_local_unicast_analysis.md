# HDB Sensor Publication 本机单播实施记录

日期：2026-10-24。状态：已按确认范围完成 App 实施及自动化验证，未操作真机；未修改 SDK、固件或服务器。

结论：对于唯一 Light LC Server 的 HDB 灯具，可将 Presence Sensor Server 的 publication destination 改为本机 Light LC Server 所在 Element 的单播地址。目标按接收模型确定，不按发送 Sensor 的 Element 或节点主地址确定。协议支持同节点 Element 间通信；现有设备固件是否正确处理此路径仍需运行验证。

本轮用户已确认：新增 `spaceData.hdb.devices[].sensorPublication`；其中 `elementAddress` 记录本机 LC 目的地址，改为本机单播。`sensorGroupId` 为空，或设备没有 SIG Light LC Server `0x130F` 时，该地址显式为 null。不要求新增旧项目兼容迁移。用户已确认实施，以下记录最终契约、实现边界及验证结果。

最终范围：保留 Sensor Group 地址分配、`sensorGroupId` 和 `sensorGroupModels`，供后续其他功能使用；`sensorGroupModels` 继续按现有 Composition 规则生成并保存完整清单，不因本次取消订阅而清空；没有 LC 时按该规则自然为空。本次仅将 Presence publication 改为本机 LC 单播，并取消 preparation、Zone 重建和普通 Sync 中为这条感应链建立或补回的 Sensor Group 订阅。`sensorGroupId=null` 或没有 LC 时，`sensorPublication.elementAddress=null`。

## 1. 变更前行为

标准配网和 Key Bind 完成后，`HDBDeviceAddCompletion.run` 调用 `prepareIntent`，随后使用公共 Sync 任务执行 HDB preparation。经典添加、专业添加和恢复入口均复用这条完成链。

- 适用对象：当前 HDB preparation 解析默认限定为灯具，不能扩大为所有独立传感器设备。
- Composition 中任一 Element 存在 SIG Sensor Server `0x1100`：分配或复用本设备唯一的 `sensorGroupId`，范围 `0xC001...0xFEFC`。
- 所有 Sensor Server 的属性类型都已识别且非零，并且只有一个 Presence Detected `0x004D` 实例：配置该实例的 publication。属性未知或没有 Presence 时跳过 publication；存在多个 Presence 实例时报不支持。
- 变更前直接订阅该组的 preparation 目标是所有 Light LC Server `0x130F` 和所有 Sensor Server `0x1100`。
- Presence publication 使用当前 Space AppKey，目标为 `sensorGroupId`，Credentials Flag 为 0，TTL 为 `0xFF`，Period 为 0，Retransmit Count 为 2、Interval 为 100 ms。
- 后续 Zone 全量同步会重建订阅，并保留 LC 所在 Element 上 `0x130F`、`0x1310`、`0x1000` 的 Sensor Group 订阅；该链路不负责 Sensor Server 的订阅。

因此，“有 Sensor 就分配组”基本正确；publication 一直只针对可唯一识别的 Presence Sensor，而非所有 Sensor Model。本次保留该选择规则，将目的地址改为本机 LC，并取消上述 Sensor Group 订阅。

## 2. 地址应如何选择

三个地址含义必须分开：

| 地址 | 用途 | 选取规则 |
| --- | --- | --- |
| 配置命令外层目的地址 | 将 Config Model Publication Set 交给节点 Configuration Server | 节点 Primary Element 地址 |
| 配置参数 ElementAddress | 指定要修改哪个 Model 实例的 publication | Presence Sensor Server `0x1100` 所在 Element |
| 配置参数 PublishAddress | 指定此后 Sensor Status 发给谁 | 负责本机灯控的 Light LC Server `0x130F` 所在 Element |

仓库此前保存的 2026-10-21 样本中，Primary/Presence Sensor 地址为 `0x0008`，Ambient Sensor 地址为 `0x0009`，LC Server 地址为 `0x000A`。按该 Composition，配置命令应发往 `0x0008`，参数 ElementAddress 为 `0x0008`、ModelIdentifier 为 `0x1100`、PublishAddress 为 `0x000A`；运行时 Sensor Status 为 `SRC=0x0008, DST=0x000A`。该样本是历史导出记录，不是本次设备实时回读。

不能把 `PublishAddress` 直接设为 `0x0008` 并期待消息自动交给 `0x000A` 的 LC。单播按目标 Element 和消息 opcode 分发；只有接收模型也在 Sensor 所在 Element 时，两个地址才可以相同。也不要把目标选为任意存在 Sensor Server 的 Element：本需求的消费者是 LC Server。

依据：Mesh Protocol 1.1 §2.3.4、§2.3.9 规定 Element 寻址及 publication 可使用单播；Mesh Model 1.1 §6.5.1.7.1 定义 LC 接收 Sensor Status 后更新 Occupancy 的行为。目的 Element 不需要为自己的单播地址配置 Subscription Add，但发送 Sensor 与接收 LC 仍须绑定同一个有效 AppKey。

## 3. 可行条件与边界

- **一个目标 LC：** 可以使用本机 LC Element 单播。Bluetooth SIG 的网络说明明确支持通过 local interface 在同一节点的 Elements 间通信，不需要手机或网关持续转发。
- **多个目标 LC：** 一个 Model 只有一个 publication address，改成一个 LC 单播会遗漏其他 LC。本次有组且存在多个 LC 时明确报不支持，不默认选第一个；多 LC 场景的控制规则留待另行确认。
- **没有 LC：** `sensorPublication.elementAddress` 显式保存为 null，publication 配置跳过，不因这一空值报 publication 错误或一直等待发布同步；不能回退到 Sensor Element 或 Primary 地址。此数据规则不等于所有依赖 LC 的 HDB 灯控功能均已具备执行条件。
- **LC 运行条件：** 正确地址之外，还需要 LC Mode、Occupancy Mode、Auto/手动覆盖状态及灯控参数符合预期。Presence 状态交给 LC 状态机消费，后续调光/熄灭由其计时和状态转换决定，不是直接把 Sensor 原始值当作 Generic OnOff 命令。
- **现有固件：** Publication Set 成功只证明配置接受，不能证明本机 Sensor Status 实际进入 LC；需要验证 local delivery 和断电持久化。当前 iOS SDK 有本机 loopback 实现，但它运行在 App 端，不能作为设备固件实测证据。
- **其他消费者：** 若以后要求网关或其他节点通过订阅获得这一路主动上报，单一本机单播不能同时承担该组发布用途。这里仅限定自主发布路径，不代表有权限的远端 Sensor Get 查询被禁用。

本次减少这条感应链的订阅配置任务，并有减少相关组播传播的潜力；组地址仍分配并保留。减少空口流量的实际幅度需固件日志或抓包确认，不以 App 配置 ACK 推断。

## 4. 已实施的 JSON 契约

有组地址且本机 LC 地址为 `000A`：

```json
"sensorGroupId": "C07F",
"sensorPublication": [
  { "modelId": "1100", "elementAddress": "000A" }
]
```

没有组地址时，或设备没有 LC 时，地址为 null。以下示例为没有组地址；若有组但没有 LC，应保留实际 `sensorGroupId`，仅将 publication 地址设为 null：

```json
"sensorGroupId": null,
"sensorPublication": [
  { "modelId": "1100", "elementAddress": null }
]
```

这是设备级“发布配置”数组，不是现有 `zoneModels` 等清单使用的 Element/Model 引用：

| 字段 | 含义 | 校验 |
| --- | --- | --- |
| modelId | 要配置 publication 的模型类型 | 本次固定为字符串 `1100`，不改成接收方的 `130F` |
| elementAddress | 运行时 Sensor Status 的发布目的地址 | 4 位十六进制字符串，属于当前设备且该 Element 包含 SIG LC Server `130F`；输出大写 |

`1100 + 000A` 不要求 `000A` 上存在 Sensor Server，也不能据此选中 `000A` 上可能存在的 Energy Sensor。发布方仍按全部 Sensor 属性识别结果选取唯一 Presence Sensor；其 Element 地址只用于配置命令的 ElementAddress。

本次数组固定一个条目，保留用户给出的数组结构，不借此新增多发布者或一对多能力。新格式必填 `sensorPublication`、`modelId`、`elementAddress`；没有组或没有 LC 时，保留单条 `modelId=1100, elementAddress=null`，而非省略字段或输出空数组。非空地址解析时允许小写并规范化，拒绝整数地址、空字符串、`0000`、组地址、其他节点地址或不包含 LC 的 Element。校验必须允许“有组但设备没有 LC，地址为 null”的合法状态。

状态规则：

- `sensorGroupId=null`：必须输出 `elementAddress=null`，不生成本次 Sensor publication 写入。null 不等于发送禁用 publication 命令，也不放宽原有标准入网/readiness 条件。
- 无论是否已有 `sensorGroupId`，设备没有 SIG LC Server `0x130F`：必须输出 `elementAddress=null`，跳过 publication 写入及其差异/待同步检查。已分配的组地址继续保留，不能因为 publication 为空而清除或回收。
- `sensorGroupId` 非空且只有一个 LC：自动填入该 LC Element 地址，发送时以该字段作为目的地址，不再使用组地址作为 publication destination。
- 有组且存在多个 LC 无法唯一确定：不能默认选择 Primary/第一个 LC，也不能将歧义混同于“没有 LC”而静默写 null。本次报不支持；多 LC 目标规则另行确定。
- 属性未齐或没有 Presence：沿用当前不创建 publication 任务的规则。即使元数据有 LC 目的地址，也不能据此给任意 Sensor Server 配置 publication。
- 多个 Presence：保留当前不支持的规则。

本机单播不需要 Sensor Group 订阅，更新方案如下：

- preparation 不再向所有 Sensor Server `1100` 和 LC Server `130F` 添加本设备 Sensor Group 地址。
- Zone 重建不再向 LC 所在 Element 的 `130F`、`1310`、`1000` 补回 Sensor Group；Lighting Zones 和 `FEFD` 的订阅仍按其原有用途配置。
- 普通 Sync 不因缺少 Sensor Group 订阅而报未同步，也不生成补订阅任务；诊断不再将该组列入期望订阅。
- `sensorGroupModels` 继续按现有规则收录所有 LC 所在 Element 上实际存在的 `130F`、`1310`、`1000`，保留生成、存储、比较、导入导出及归属校验。它是保留给其他功能使用的模型清单，不代表本次必须下发订阅，也不代表设备已完成订阅；不得强制清空，也不得仅凭它非空就在本次 preparation/Zone/Sync 中生成 Sensor Group Add。
- 本次以新项目为主，不新增旧订阅迁移流程。复用已配置过的测试设备时，如需清除旧组，只针对原 `sensorGroupId` 执行 Subscription Delete 并核对共享订阅表；不能通过额外 Delete All 清理而破坏 Zone/FEFD。设备已有其他用途的组发布不自动纳入此次清理。

组地址仍按原有 Sensor 能力条件分配或复用，继续参与 Site 地址池占用、唯一性校验、持久化、导入导出、恢复及删除回收。地址与模型清单保留供后续功能使用；本次不扩展实现这些后续功能，也不取消字段或释放在用设备的组地址。

保留 `sensorGroupId=null → sensorPublication.elementAddress=null`，同时增加“没有 LC 则地址为 null”。生成设备元数据时先处理组状态，再按实际 LC 能力生成单播地址或合法 null；组分配失败仍按原机制保持可重试，不能绕过地址分配提前宣称 preparation 完成。

保持当前开发中的 schemaVersion=2，将新字段作为新契约必填项，不增加旧数据缺字段自动回填、旧格式迁移或旧初始化签名兼容分支。缺少字段的旧数据不能按新格式直接导入/加载；已有的显式默认恢复功能需要继续正确生成新结构，但不另建兼容流程。

## 5. App 实施结果

- 数据层新增独立 `HDBSensorPublication`，必填单条数组，显式编码 null；校验地址格式、当前 Composition 的 LC 接收目标及 group/null 一致性。公共模型引用类型保持非空地址语义。
- 组分配成功后，在同一次 HDB 更新中保存 `sensorGroupId` 与 publication 目的地址；重试复用原有组。模型清单比较与 publication 校验分开，避免工厂初始 null 导致重复初始化。
- preparation 计划读取已保存目的地址，并将其纳入计划/签名。发送方继续使用唯一 Presence Sensor；发送前核对发布方和 LC 接收方的当前 Space AppKey 绑定。配置参数、ACK 匹配、失败保存和过期任务拦截复用原机制。
- preparation、普通 Sync、Zone 重建与诊断均不再要求 Sensor Group 订阅。Zone 重建执行 Delete All、Broadcast、Add Zones；保留原有 Zone/FEFD 行为以及 Sensor Group 地址和模型元数据。
- 重新配网或显式默认恢复按当前 Composition 更新目的地址。组被移除或 LC 消失时写 null；仅 LC 消失不释放组地址。普通 Sync 的有效配置不会反复重算初始化状态。
- 无 LC 时可保存合法 metadata/null 并跳过 publication；完整灯控初始化与 Zone 执行仍要求原有 LC 等能力，不能把合法 null 当成整条 preparation 成功。
- 已更新现有 JSON 示例、模型数组契约和配置命令文档。SDK 的既有 `ConfigModelPublicationSet` 支持单播，无需新增 API 或修改依赖。

如果网关/Web 也执行 preparation 或 Zone 配置，对应团队需同步采用新契约：定位唯一 Presence `1100` 为发布方，目的地址取 `sensorPublication.elementAddress`，不得回写为 `sensorGroupId`，也不得仅凭保留的 `sensorGroupModels` 清单重新添加本次已取消的 Sensor Group 订阅。两个旧字段须继续保存和传递，以供其他功能使用。目前只核对 App，未验证外部实现；App 不修改固件、服务器或部署配置。设备是否需要固件配套由本机单播运行验收决定。

## 6. 验证结果与待验收

以下检查均通过，覆盖本次修改后的生产逻辑；隔离夹具不替代设备运行验收：

| 验证入口 | 本次覆盖 |
| --- | --- |
| `check_hdb_configuration.py`、preparation policy 回归 | JSON 字符串/null 往返、缺字段及非法地址拒绝、无组/无 LC、多 LC 拒绝、发布方与接收方地址区分 |
| `check_hdb_persistence.py` | 实际 SQLite 保存/重载、事务失败回滚及字段保留 |
| `check_hdb_integration.py` 及 device-sync/device-tasks/add-completion/add-execution/subelement 模式 | 添加和普通 Sync、组分配/复用、取消/失败/重试/迟到 ACK、拒绝旧组目的地址 ACK、接收方 AppKey 校验、Zone/FEFD 恢复且不补回 Sensor Group、签名稳定、无 LC 元数据合法但完整初始化仍拒绝 |
| `check_hdb_diagnostics.py` | 本机 LC publication 期望、合法 null、不再要求 Sensor Group 订阅、保留 Zone/FEFD 诊断 |
| `check_hdb_import_recovery.py` | 导入保护、默认恢复、当前 Composition 地址变化、组移除或 LC 消失后的 null、LC 消失时组地址保留 |
| `SunSmart` generic iOS Debug 构建 | `SunSmartLocal.xcworkspace`，`iphoneos`，关闭签名，构建退出码 0 |

构建使用既有本地 SDK 映射 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f`，SDK 无未提交改动。本次共享代码没有新增品牌条件或资源/依赖变更，以 SunSmart 为代表构建；未执行真机、网关/Web 或服务器联调。

人工设备验收顺序：

1. 读取 Composition、Presence 属性映射、目标模型 AppKey 绑定，记录固件版本与原 publication。
2. 配置 Presence Sensor Server 发布到本机 LC Element，Publication Get 回读目的地址和 AppKey。
3. 在 Auto 且 LC 配置正确时，断开 App 连接，触发人体感应，检查本灯响应及 Hold/Fade 后行为；相邻灯不应被该发布触发。
4. 断电重启后重复，检查 publication 持久化和自主控制。
5. 执行 Sync、空/非空 Zones 切换和退出重进，确认 publication 不被改回组地址，Sensor Group 订阅不再被补回，Zone/FEFD 订阅保留；需要验证流量收益时另用设备日志或抓包观察。

待用户完成以上真实设备验收。配置 ACK、隔离回归和 App 编译通过均不代表固件的本机投递及断电持久化已经验证。

## 证据入口

- [当前目标解析](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)
- [Preparation 策略](../SunSmart/Common/Data/HDBDevicePreparationPolicy.swift)
- [发送、差异比较及初始化身份](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift)
- [地址分配与回收](../SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift)
- [Zone 重建与地址校验](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)
- [2026-10-21 历史样本](261021_1610_HDB_self_sensor_two_stage_analysis.md)
- [Mesh Protocol 1.1，§2.3.4 / §2.3.9](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html)
- [Mesh Model 1.1，§6.5.1.7.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)
- [Bluetooth SIG Mesh Networking Primer，§5.5](https://www.bluetooth.com/bluetooth-mesh-networking-primer/)
