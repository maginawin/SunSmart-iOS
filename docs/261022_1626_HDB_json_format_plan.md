# HDB JSON 格式调整方案与实施结果

结论：以共享 HDB 编解码为主要改动边界，同时调整对应校验和测试；不只处理导出字符串。App 的 Mesh 命令、地址选择、Zone 成员及同步状态语义可以保持现状。只修改导出会使新文件导入、云端回读校验失败。

用户已确认：SIG Model ID 为 4 位、Vendor Model ID 保留 8 位；只支持新格式，不迁移旧 HDB 数据。用户随后确认完整 demo 及范围，App 实施已完成，验证结果见末节。

## 1. Demo 与格式约定

[完整 demo](261022_1626_HDB_json_v2_demo.json) 带 `spaceData.hdb` 包装，使用合成设备和 4 个 Zone；不是完整可导入 Space 包，未包含 `nodes/groups` 及 Mesh 密钥。正式新建 HDB Space 仍按现有逻辑创建 63 个 Zone。

| 路径或字段 | 拟定格式与规则 |
| --- | --- |
| `hdb.schemaVersion` | 已采用 `2`，明确拒绝旧格式 |
| `hdb.lightingZones[].groupId` | 4 位大写十六进制字符串，如 `C001`；替代旧 groupAddress 字段 |
| `devices[].nodeAddress` | 大写 4 位十六进制字符串，如 `000B` |
| 三个 Model 数组中的 `elementAddress` | 大写 4 位十六进制字符串，如 `000D` |
| 三个 Model 数组中的 `modelId` | SIG 为 `1000/130F/1310` 等 4 位；Vendor 为 `0A780001` 等 8 位，保留 Company ID |
| 参数描述中的 `elementAddress/modelId/property` | 大写 4 位十六进制字符串，如 `000D/1310/002F` |
| `broadcastId` | 固定值用字符串 `FEFD` 输出 |
| `sensorGroupId` | 已分配时为 4 位字符串，如 `C040`；未分配时保留显式 `null` |
| `devices[].mac` | 12 位大写十六进制字符，无分隔符，如 `C73EC82E3DB7` |
| `devices[].lightingZones` | 仅数字 zoneId 数组，如 `[1,2,3,4]`；合法空目标为 `[]` |
| `lightingConfiguration.lightingControl` | `status`、`Auto`、`Force_On`、`Force_Off`、`value` 五个字段；删除 `mapValues`，三个选项直接填目标地址 |

全部十六进制字符串不带 `0x`。字符串按十六进制解释，不能把 `1000` 当十进制 1000。新输入严格校验长度、字符和范围，接受字母大小写、统一大写输出；不再接受原整数地址、对象成员数组、带分隔符 HDB MAC 或 mapValues。

按当前代码校正两处路径：

- MAC 实际位于 `devices[].mac`，不存在 `devices.zoneModel.mac`；`zoneModels` 是模型引用数组。
- 本次数字数组指设备的 `devices[].lightingZones`。顶层 `hdb.lightingZones` 使用 `{zoneId,name,groupId}` 目录，它供页面显示、成员校验及订阅任务查找地址使用。按用户追加要求，groupAddress 改名为 groupId 并输出 4 位十六进制字符串；内部 UInt16 地址及已有引用/范围校验保持。

`status` 和顶层选项 `value` 是业务状态，不固定写成 `synced/Auto`。示例只展示已同步 Auto 的情况；未完成、失败或重试时仍按现有规则保留 pending。

无对应模型目标时，地址保留显式 `null`，不能用 `0000` 充当真实目标；字段缺失应拒绝。`lightingConfiguration=null`、已有可空参数和未设置 installDate 的语义保留。Model 清单为空仅在现有业务规则允许的状态下合法，不能借格式更新放宽可执行性校验。

## 2. lightingControl 的执行含义

三个地址继续从同一设备模型清单按现有 `HDBLightingWrite.target` 规则生成，并在导入时核验；不能信任任意远程地址，也不能在回读比较时重新补齐丢失字段。

| JSON 选项 | 目标选择 | 当前 App 固定生成的命令及值 |
| --- | --- | --- |
| Auto | 地址最小的 SIG LC Server，modelId=130F | `LightLCLightOnOffSet(true)` |
| Force_On | 地址最小的 SIG Lightness Server，modelId=1300 | `LightLightnessSet(65535)` |
| Force_Off | Primary Element 上的 SIG OnOff Server，modelId=1000 | `GenericOnOffSet(false)` |

这些是当前 App 实现规则，不是新增设备能力声明。三个选项地址可以相同，也可以不同；demo 中 Primary=000B，首个 LC=000D。参数的目标继续为首个 LC 同 Element 上的 LC Setup；不因另一个 Element 有 Setup 而切换目标。

五个 Property 保持：dimIntensity=002F、brightIntensity=002E、rampUpTime=0037、rampDownTime=0036、holdTime=003C。参数 value 仍使用原数字与单位；百分比、秒到 Mesh 原始值的换算保持。failsafeDelay、installDate 仍仅保存 status/value。

## 3. 对 App 的影响与必要调整

| 链路 | 已核实事实 | 必须保证 |
| --- | --- | --- |
| 本地保存、重启读取 | Database 直接 JSONEncoder/JSONDecoder 读写 HDB 列，加载失败会设置 hdbLoadFailed 并阻断配置 | 新格式必须可保存、重载；不更改数据库表结构。旧格式拒绝读取，保留原数据，不回退空配置 |
| 导出、分享、上传 | ExportData 调用 HDBLightingZonePolicy.json，先核对设备模型 | 从同一编码器输出新结构；导出只读，不分配组地址、不发 BLE |
| 导入、云端恢复 | ImportData 先 decode/validateReferences，后核对 SDK Node 模型及事务读回 | 同步支持新格式的严格校验；保留 UUID、Primary、MAC、Group、模型一致性保护及失败回滚 |
| 云同步比较 | configurationData 先解码 HDB 再 canonical；本地还保存历史比较快照 | 新上传、新回读使用同一表示；缺字段、错误地址、状态改变不得被归一化成相等。按用户决定，不迁移历史旧快照 |
| Zone 页及任务 | 内部成员为 HDBZoneMembership，任务由 zoneId 查顶层目录得到组地址 | 只改变成员的 JSON 表示，内部类型可保留；选择、清空、最多 8 个、重试及四阶段订阅行为保持 |
| Lighting Configuration Set/Get、初始化、恢复 | 内部 HDBLightingControl/HDBLightingWrite 已生成固定命令，JSON 里的描述是派生值 | 扁平地址与真实 Set/Get 选择保持一致；不固定成功状态、不新增发送或重复初始化 |
| MAC 身份和显示 | normalizedMAC 当前返回冒号格式；准备完成校验、引用校验和恢复共用它 | 保留内部规范格式，仅在 HDB 编解码边界转无分隔符；解码先验证新格式再规范化，避免影响 SDK Node、扫描及原显示 |

因此，此次属于数据契约调整，影响 App 的数据读写与校验，但不要求改变灯光或 Zone 的业务行为。新增行为仅为新格式的接受与旧格式的拒绝；若漏改共享读写入口，则会直接表现为 App 无法读取、导入或完成同步。

不迁移的实际影响：已有旧 HDB 本地项目升级后可能被阻断，旧导出文件/云端 HDB 不能用于新版本恢复；需要用户使用新格式项目或新建项目。不会自动删除数据库、重建组地址或清除恢复记录。普通非 HDB Site 不应受影响。

版本号已升为 2，避免同一个 schemaVersion 下混用两个不兼容契约，也使无设备的旧空 HDB 能被明确识别。旧 App 不具备新格式读取能力，不承诺跨版本混用。

## 4. 最小实施方案

1. 在现有 HDBConfiguration.swift 内实现新格式编解码：schemaVersion、UInt16 十六进制字段、SIG/Vendor Model ID、设备成员数字数组、MAC 输出与读取、扁平 lightingControl、Property 描述。保留内部数值类型与 HDBZoneMembership，不为格式改动重写业务模型。
2. 调整 HDBLightingZonePolicy 的版本及格式配套校验；复用既有范围、引用、模型集合及 canonical 规则。只有实际需要时才改 Database/ImportData/ExportData，不在这些入口各做一次字符串转换。
3. 检查历史比较快照遇到旧 HDB 时仍不能确认新格式上传；不新增兼容归一化、不伪造新基线、不降低现有冲突恢复保护。以回归证明新格式保存、导入、比较与恢复路径一致。
4. 保持 HDBModelTarget 和 HDBDevicePreparationPlan 的内部编码及 signature 不变。它们不是 spaceData.hdb 的外部表示；统一改它们会无谓改变初始化摘要并触发重新准备。Model 数组使用 HDBModelReference 的外部编解码即可。
5. 更新现有 HDB 行为测试、当前 JSON 示例及网关契约文档。确认后将本 demo 纳入生产解码往返测试，并更新旧当前样本，避免两个“当前契约”并存；历史 archive 文件保留。

预计不需要修改 SDK、UI 布局、国际化、品牌资源和工程配置。五品牌共用本次数据模型，以 SunSmart 为代表构建；如实施出现品牌差异或资源/API 风险，再扩大到对应品牌。

## 5. 验证范围

- 新格式完整往返：七类字段、Vendor 保留 Company ID、补零、大小写、显式 null、空 Zone、空设备、schemaVersion；旧整数、旧数组对象、旧 MAC、旧 mapValues、旧版本拒绝。
- 非法输入：非十六进制、0x 前缀、错误宽度、越界、Boolean 冒充数字、错误广播地址、重复/不存在/超过 8 个 Zone；错误 UUID、MAC、模型与 Element 引用。
- 命令一致性：Auto/On/Off 三目标与实际 Set/Get 一致；多 Element、乱序、缺模型、首 LC 无 Setup、Vendor 低位碰撞；四阶段 Delete All → Broadcast → Sensor → Zones 的命令字节及次序保持。
- 状态连续性：pending/synced、保存失败、部分 ACK、取消/迟到回执、重试、恢复地址变化及初始化摘要保持；JSON 格式改变不能自动变更业务状态。
- 保存和云端：新格式重载、导入回滚、MAC 身份比较、canonical 排序、字段丢失拒绝、旧基线不误确认、新上传后又发生本地编辑不得被旧回读确认。
- 优先运行/扩展既有 configuration（含 schema simplification）、persistence、import recovery、lighting configuration/service/messages、device preparation、lighting zone execution、presentation 回归；涉及共享云端比较改动时加跑对应 recovery/readback 回归。
- 现有 persistence/import recovery 夹具使用存储替身，不能声称真实 SQLite 事务已通过；需要补充直接覆盖 Space HDB 列的新格式保存/读取证据，或明确列为人工验收，不借 Site 类型存储测试替代。
- Swift 修改结束后运行一次 SunSmartLocal / SunSmart / Debug / generic iOS / 无签名构建，先核对实际 SDK 映射与稳定 DerivedData。分析阶段不构建，不自动操作真机。

最短人工验收：新建 HDB 项目并添加多 Element 设备 → 核对导出新格式 → 重启与导入后检查成员和参数 → Set/Clear/Retry Zones 及三个灯光选项 → 云端上传回读。BLE、真实 UI、云端和网关表现须分别验收。

## 6. 外部配套与本轮证据

网关/Web 需读取新字符串、成员数组与扁平控制地址，并按上表生成固定命令；服务器需完整保存和回传 schemaVersion、字段类型、null、数组及动态状态。由对应团队确认读取、保存、回读及命令目标一致；若服务端仅透传 JSON，是否需要改代码仍由其实现验证。本任务仅修改 App，不修改外部代码、配置或部署。

分析基线：feat/HDB-261020，HEAD=f93859f7，开始时工作区干净。已读取当前 HDBConfiguration、HDBLightingZonePolicy、HDBConfigurationStore、Database、ImportData、ExportData、SpaceConfigurationIntegrityPolicy、LightingConfigurationPolicy/Service、LightingMessages、PreparationPolicy 及相关测试。旧审查记录仅用于定位，未复用为本次通过证据。

初次分析只生成方案与 demo；用户确认后按本文件实施。schemaVersion=2、仅设备 lightingZones 改数字数组已确认；随后用户追加确认顶层 groupAddress 改为 groupId 十六进制字符串。

## 7. 实施与验证结果

生产代码仅修改 HDBConfiguration.swift 与 HDBLightingZonePolicy.swift：

- 新根对象与读取版本为 2；所有指定十六进制字段严格读取、统一大写输出，SIG/Vendor 分别为 4/8 位。
- 设备 MAC 在 JSON 中无分隔符，内部仍为规范冒号格式；设备 Zone 选择输出数字数组，顶层目录使用 groupId 十六进制字符串。
- lightingControl 输出五字段扁平结构，地址按既有目标策略派生并严格核验；Property 描述使用十六进制字符串。合法 null、实际状态与业务值保持。
- Database、ImportData、ExportData、云端比较通过已有共享入口接入新格式，无需新增各自转换分支；没有修改 SDK 或初始化签名编码。
- 新 demo、当前完整 HDB 样本及内嵌契约示例纳入生产编解码往返验证；网关执行清单及当前契约已同步更新。

已通过的自动化证据：

- configuration（含 schema simplification）：严格字段格式、大小写归一化、Vendor 身份、版本 1/旧字段拒绝、空值/缺字段区别、当前示例往返、初始化目标内部编码保持。
- persistence、import recovery：真实 SQLite 精简 spaces 表的 hdb BLOB 写入、连接重开、状态/空成员保存、失败事务回滚及旧数据原文保留；生产保存保护、导入准备与引用校验、旧基线不误确认、缺字段回读拒绝。
- integration、lighting configuration/service/messages、lighting zone execution、presentation、device preparation（含 device sync/tasks、add completion/execution、subelement）、space creation：真实生产策略与隔离存储/通信边界下的命令、目标、状态、失败/重试/取消/迟到回执以及普通 Site 隔离。
- 共享 space recovery receipts 与 proximity scoped import：HDB v2 恢复可记录有效基线，上传回读/新旧编辑保护及普通 Group/设备清理隔离回归通过；保留原 63 Zone、4 Node 导入快照覆盖。
- SunSmartLocal.xcworkspace / SunSmart / Debug / iphoneos / generic iOS / CODE_SIGNING_ALLOWED=NO 构建成功（退出码 0）。输出包含未使用变量、捕获方式和已有非可选 MAC 使用 ?? 等警告；本轮未修改这些位置。

SQLite 测试直接验证生产 HDB 编解码与该数据列的真实持久化，但未运行完整 App Database 的全部表和完整导入事务。其余隔离测试也不代表真机、BLE、云端或网关已经验收。

构建来源：one-dev SDK HEAD=8c5af55，沿用原有 Node 配置及配置读回相关未提交差异；本轮未修改 SDK、正式依赖、品牌工程或资源。DerivedData 使用该工作树稳定目录 SunSmart-feat-HDB-261020。

`git diff --check` 与当前文档 JSON 语法检查通过。最终人工验收仍按第 5 节执行。所有改动保持未提交，未自动安装或运行真机，未执行外部部署。


## 8. groupId 追加调整（2026-10-22）

用户要求 spaceData.hdb 内所有 groupAddress 改名 groupId，并使用 4 位十六进制字符串。实际外部字段全部由 HDBLightingZone 编解码；现已在这一共享边界完成，复用既有 HDBHexUInt16。内部 groupAddress: UInt16 保留，UI、地址分配、订阅命令、模型恢复及 SDK 普通节点数据无需更名。schemaVersion 仍为本轮未发布的 2。

新输入要求 groupId 存在，拒绝整数、null、错误位数、前缀、非法字符、无效组地址及旧 groupAddress；同时携带新旧字段也拒绝。字母大小写均可读取，统一大写输出，组地址仍须唯一并引用正确的 Mesh Group。沿用不迁移策略，不自动重写旧存储。

当前完整示例、demo、数据契约和网关执行清单同步更新。新增行为回归覆盖 C000/C001/FEFC 边界、大小写归一化、无效范围、缺字段/旧字段/混合字段、Group 引用、云端回读字段缺失及地址变化；真实 SQLite 重开核对 groupId 字符串存储。

本次 configuration（含 schema simplification）、persistence、import recovery、integration、space creation 回归均通过。SunSmartLocal / SunSmart / Debug / generic iOS / 无签名构建通过（退出码 0），git diff --check 通过；本次未运行真机或外部联调。
