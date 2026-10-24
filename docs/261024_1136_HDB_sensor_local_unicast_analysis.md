# HDB Sensor Publication 本机单播实施记录

日期：2026-10-24。状态：已按确认的新三字段契约完成 App 调整、针对性回归及 SunSmart 编译；未操作真机，未修改 SDK、固件或服务器。

结论：对于唯一 Light LC Server 的 HDB 灯具，可将 Presence Sensor Server 的 publication destination 改为本机 Light LC Server 所在 Element 的单播地址。目标按接收模型确定，不按发送 Sensor 的 Element 或节点主地址确定。协议支持同节点 Element 间通信；现有设备固件是否正确处理此路径仍需运行验证。

本轮用户已确认三字段契约：`modelId + elementAddress` 定位需要配置 publication 的发布方，`publishAddress` 表示发布目标。旧结构项目由用户删除，不新增缺字段兼容、地址含义猜测或迁移代码，继续使用开发中的 schemaVersion=2。

最终范围：保留 Sensor Group 地址分配、`sensorGroupId` 和 `sensorGroupModels`，供其他功能使用；当前 Presence publication 仍发布到本机 LC 单播地址，preparation、Zone 重建和普通 Sync 不为这条感应链添加 Sensor Group 订阅。源和目的分别存储，配置命令与 ACK 处理沿用现有机制。

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
- **没有 LC：** 发布方已识别时，`sensorPublication.publishAddress` 显式保存为 null，publication 配置跳过，不因这一空值报 publication 错误或一直等待发布同步；不能回退到 Sensor Element 或 Primary 地址。此数据规则不等于所有依赖 LC 的 HDB 灯控功能均已具备执行条件。
- **LC 运行条件：** 正确地址之外，还需要 LC Mode、Occupancy Mode、Auto/手动覆盖状态及灯控参数符合预期。Presence 状态交给 LC 状态机消费，后续调光/熄灭由其计时和状态转换决定，不是直接把 Sensor 原始值当作 Generic OnOff 命令。
- **现有固件：** Publication Set 成功只证明配置接受，不能证明本机 Sensor Status 实际进入 LC；需要验证 local delivery 和断电持久化。当前 iOS SDK 有本机 loopback 实现，但它运行在 App 端，不能作为设备固件实测证据。
- **其他消费者：** 若以后要求网关或其他节点通过订阅获得这一路主动上报，单一本机单播不能同时承担该组发布用途。这里仅限定自主发布路径，不代表有权限的远端 Sensor Get 查询被禁用。

本次减少这条感应链的订阅配置任务，并有减少相关组播传播的潜力；组地址仍分配并保留。减少空口流量的实际幅度需固件日志或抓包确认，不以 App 配置 ACK 推断。

## 4. 当前 JSON 契约

Presence Sensor 位于 `0008`、本机 LC 位于 `000A`，且已有组地址：

```json
"sensorGroupId": "C07F",
"sensorPublication": [
  { "modelId": "1100", "elementAddress": "0008", "publishAddress": "000A" }
]
```

| 字段 | 含义 | 校验 |
| --- | --- | --- |
| modelId | 需要配置 publication 的模型 | 当前固定字符串 `1100` |
| elementAddress | 发布方 Model 所在 Element 的单播地址 | 必填非空 4 位十六进制字符串；属于当前设备，指向唯一 Presence Sensor Server |
| publishAddress | 发布目的地址 | 必填 4 位十六进制字符串或显式 null；非空时为本机唯一 LC Server 所在 Element |

条目三个字段均必填，输出大写十六进制；地址不接受整数、组地址、`0000`、越界值或 `0x` 前缀。整个数组必填、当前最多一条。不能把旧结构中的目标 `elementAddress` 当作发布方地址；缺少 `publishAddress` 的旧条目直接拒绝。

状态规则：

- 全部 Sensor 类型已知且非 0、仅有一个 Presence Detected `004D`：保存该发布方的 `modelId` 与 `elementAddress`。
- 类型未齐或没有 Presence：保存 `sensorPublication=[]`，不创建 publication 任务；多个 Presence 报不支持。不得选用 Ambient/Energy Sensor 或过期的 Presence 快捷缓存。
- 发布方已知但 `sensorGroupId=null`，或设备没有 LC：保留发布方信息，`publishAddress=null`，跳过写入与待同步检查。null 不等于发送禁用 publication 命令，也不代表完整 HDB 初始化已经就绪。
- 有发布方、有组且唯一 LC：`publishAddress` 使用该 LC 的 Element 单播地址；有多个 LC 时不默认选择 Primary 或第一个，报不支持。
- 导入/导出与发送前，结合当前 Composition 和 `sensorTypes` 校验源地址及 Presence 属性；LC 目标、组地址合法性和原有身份检查仍然有效。
- 配置命令外层发往设备 Primary Address；参数 Element Address=`elementAddress`、Model ID=`modelId`、Publish Address=`publishAddress`。发布方与 LC 都须绑定当前 Space AppKey。
- Sensor Group 分配、回收、唯一性检查和 `sensorGroupModels` 保持现有用途；不新增 Sensor Group 订阅、不修改 Zone/FEFD 行为。

## 5. App 实施结果

- 数据结构分离非空发布方地址和可空目的地址；生成、SQLite 保存、导入导出与默认恢复均使用新三字段契约。
- Presence 筛选由共享规则处理，设备元数据、preparation 和诊断使用同一选择结果；任务由保存的发布方引用生成，目的地址取 `publishAddress`，并核对实时属性证据。
- 重新配网、Composition 或属性映射变化时重建发布方及目的地址。复制模型元数据后按保留的组状态刷新目的地址；普通 Sync 的匹配配置不反复重置初始化。
- 默认恢复使用云端 Node 的 Composition 与 `sensorTypes`，不能仅解码普通 Mesh Node 后丢弃属性类型，导致已知 Presence 被当作未知。
- 保存的源地址与新属性证据不一致时阻止旧任务执行，后续 prepareIntent 更新元数据再规划；失败、取消、过期及不匹配 ACK 沿用原有保护。
- 已同步当前数据契约、JSON 示例和网关配置任务文档。SDK 既有 API 足够，本次未新增 SDK API 或修改依赖。

网关/Web 如果执行 preparation，需按新 `elementAddress + modelId` 定位发布方，并使用 `publishAddress` 为目的地址；空数组或 null 目的地址跳过配置。对应团队负责实现并联调，发布前应核对新结构传递及命令参数。App 本次不修改固件、服务器或运行配置；旧项目按用户约定删除，不增加自动迁移。

## 6. 本次三字段调整的验证

以下检查均通过；隔离夹具不替代真实设备与外部系统验收。

| 验证入口 | 本次覆盖 |
| --- | --- |
| `check_hdb_configuration.py` | 新字段往返、旧条目缺字段拒绝、源/目标分离、空数组与 null、错误发布方/目标及多个 Presence 拒绝、当前 JSON 示例 |
| `check_hdb_persistence.py` | 实际 SQLite 重载、三字段及 null 保留、保存失败回滚 |
| `check_hdb_import_recovery.py` | 导入/默认恢复、云端 Sensor 属性、源与 LC 地址变化、无组/无 LC；保留既有恢复能力，不新增旧结构兼容分支 |
| preparation 策略夹具与 `check_hdb_integration.py` 的 device-sync/device-tasks/add-completion/add-execution/subelement 五种模式 | 添加时外层地址、源 Model 与 Publish Address；类型识别变化后更新保存源地址；失败/重试/取消、错误及迟到 ACK；Zone/FEFD 订阅 |
| `check_hdb_integration.py` 默认模式 | Store/Service/Executor、共享模型复制后刷新、完整目标重建、恢复与持久状态 |
| `check_hdb_diagnostics.py` | 按保存的发布方与目的地址生成期望值、属性未知与歧义、读回比较和取消 |
| `check_hdb_lighting_configuration_service.py`、`check_hdb_zone_control.py` | 共享数据模型对单设备配置、Lighting Zone 控制与 SDK Presence 编码的关联影响 |
| `git diff --check` | 差异格式检查 |
| `SunSmart` generic iOS Debug | 直接 xcodebuild，iphoneos，关闭签名，退出码 0；存在既有编译警告，无编译错误 |

构建 DerivedData 使用稳定目录 `SunSmart-feat-HDB-261020-Codex`。保留本轮开始时已有的 Zone 页面、Hold Time、控制相关未提交改动；未提交 Git。

使用 `SunSmartLocal.xcworkspace`，SDK 映射到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f`，SDK 无未提交改动。本次共享代码没有新增品牌条件或资源/依赖变更，以 SunSmart 为代表进行 generic iOS Debug 编译。未执行真机、网关/Web 或服务器联调。

人工设备验收顺序：

1. 读取 Composition、Presence 属性映射、目标模型 AppKey 绑定，记录固件版本与原 publication。
2. 配置 Presence Sensor Server 发布到本机 LC Element，Publication Get 回读源 Element/Model、目的地址和 AppKey，同时核对导出 JSON 的三个字段。
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
