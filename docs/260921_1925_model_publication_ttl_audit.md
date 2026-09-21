# 全 App Model Publication TTL 调查

日期：2026-09-21。本文保留最初只读调查、确认方案与后续实施记录。

**最新状态：用户确认 A 后已完成 6 个 SDK 文件、7 处 Publication TTL 修正；相关行为回归与 SunSmart generic iOS 构建通过。代码尚未提交或发布，正式 SDK 依赖更新及真机验收待后续处理。**

## 修复前调查结论

1. 当前实际使用的标准 Model Publication **尚未全部统一为 `0xFF`**。明确遗漏位于 SDK `MeshSensorCalibrateManager.initialize()`：Plane / Night / Sensor 三种光照校准共用此入口，临时将 Ambient Light Sensor Server 发布到手机本地节点，TTL 写入 `networkParameters.defaultTtl`，当前为 **5 / `0x05`**。
2. Group Profile 的 Presence / Ambient Light 发布、校准成功后的传感器选择、Group 页补建发布、Kinetic 代理 Client 发布、EFC Scene Client 发布，新建配置均使用 **`0xFF`**。
3. SDK 另有 6 个显式写 `networkParameters.defaultTtl` 的启用构造位置，但分别受空 Model 列表抑制，或未发现当前 App 调用；不能与正在使用的校准入口混为一谈。
4. 取消发布配置使用 **地址 `0x0000`、TTL `0`**；校准失败回滚**原样恢复快照 TTL**。这两类操作应单独决策，不适合机械替换所有 TTL。
5. 新下发使用 `0xFF` 不代表设备旧配置已经更新。Profile 同步已检查 TTL；EFC 和 Kinetic 的现有判定不会仅因 TTL 不同而强制重新配置。

建议先考虑校准公共入口的最小修正；潜在 SDK 入口的一致性整理和存量设备迁移分别决定。本轮没有实施上述建议。

## 调查基线与覆盖

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix`，分支 `fix`。
- App HEAD：`59f7dbbafc0ce40c64a8051150ce7e15c7db946e`；调查开始时工作区干净。
- 已确认 `2d0bf4539d3e13869e69699e97ed8b9cb3446fc6` 是当前 HEAD 的祖先，并核对该提交及当前源码，而非只引用历史分析。
- 本机入口：`SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`a971027e08f9775d7a3f071a06f89be1c38ecc96`，正式 workspace 的 `Package.resolved` 同样锁定此 revision，项目仍引用远端 `release`。
- SDK 已有未提交改动：`MeshFastAddDeviceManager.swift`、`MeshProxyMessageCommand.swift`，以及未跟踪的 `Tests/Standalone/RestoreQueueLifecycleTests.swift`、`scripts/check_restore_queue_lifecycle.sh`。本轮只读，没有覆盖这些工作。
- 检索范围：App 生产源码、SDK `Sources`、Pods 源码；追踪 `ConfigModelPublicationSet`、`ConfigModelPublicationVirtualAddressSet`、`Publish`/`Publish.init`、封装 API、禁用与快照恢复，以及调用点和前置判定。Pods 未找到其他标准 Publication 写入实现。
- 本次审计针对共享 App/SDK 源码，未发现这些写入点有品牌独立 TTL 分支。未验证设备固件状态、云端独立下发或仓库外客户端。

## TTL 的准确含义

Bluetooth SIG Mesh Protocol 1.1 §4.2.3.5：Publish TTL 为 `0xFF` 时，模型使用源设备的 Default TTL。它不是 255 跳，也不是复制 App 的 network default TTL。依据：[Bluetooth SIG Mesh Protocol](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html)。

本地 SDK 的 `Publish.ttl` 文档同样定义 255 为默认 TTL；标准 Set 和 Virtual Address Set 编码器均直接将 `publish.ttl` 写入负载，没有自动将 5 转换为 `0xFF`。

`MeshLibManager.initConfig()` 明确调用 `parameters.setDefaultTtl(5)`；本轮源码检索没有发现 App 将这一网络参数改成其他值。所以下文使用该参数的构造点，在当前默认初始化路径下实际写入 `0x05`。

必须分开看三个状态：

| 状态 | 当前实现 | 是否自动修正 Model Publish TTL |
| --- | --- | --- |
| App SDK network default TTL | 初始化为 5 | 否；旧构造点把数值 5 直接复制进 publication |
| Lab 的 App 发包 TTL 覆盖 | `LabSettings.applyOutgoingMeshTTLOverride()` 设置独立 outgoing override | 否；不改 publication 负载，也不改 `networkParameters.defaultTtl` |
| 设备 Default TTL | Information 页发送 `ConfigDefaultTtlSet` | 否；只有 Publish TTL=`0xFF` 才随设备 Default TTL 生效 |

证据：[Publish.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh%20Model/Publish.swift)、[MeshLibManager.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift)、[LabSettings.swift](../SunSmart/Common/Data/LabSettings.swift)、[InformationTTLMeshService.swift](../SunSmart/Main/Device/InformationTTLMeshService.swift)。

## 当前 App 实际使用的启用发布功能

| 功能 | 配置的 Model / 发布目标 | 下发 TTL | 入口与判定 |
| --- | --- | --- | --- |
| Occupancy / Vacancy；含 Daylight 的两种对应 Profile | Presence Sensor Server → 灯组 | `0xFF` | `getNodeSyncProfiles` → `.sensorEnabled` → `ProfileType.getMessageHandles`；比较地址、TTL 和 retransmit |
| Daylight；Occupancy with Daylight / Vacancy with Daylight | 被选中的 Ambient Light Sensor Server → 灯组 | `0xFF` | 同一 Profile 构造入口；比较地址、TTL 和 retransmit |
| 添加组成员、Fast Add 附加组配置、延后同步、Space Sync、恢复后的组 Profile 配置，以及 EFC 同步中复用的灯组配置 | 相应 Presence / Ambient Light Sensor Server → 灯组 | `0xFF` | 复用上述 Profile 消息及同步判定，不是另一套 TTL 策略；无对应任务时不下发 |
| 光照校准准备阶段：Plane / Night / Sensor Cal. | Ambient Light Sensor Server → 手机 Provisioner 单播地址 | **`0x05`** | SDK `MeshSensorCalibrateManager.initialize()` 每次构造临时发布；三种模式共用 |
| Plane Cal. 成功后启用传感器、选择已有校准的传感器 | Ambient Light Sensor Server → 灯组 | `0xFF` | App `sensorEnabled`；地址相同但 TTL 错误也会重配 |
| Night / Sensor Cal. 成功后提交传感器选择 | Ambient Light Sensor Server → 灯组 | `0xFF` | App `commitCalibrationSensorSelection`；地址与 TTL 校验，配置失败进入回滚 |
| 进入 Group 页面，补建所选光照传感器发布 | Ambient Light Sensor Server → 灯组 | `0xFF` | `GroupViewController.viewDidAppear`；**仅地址不匹配时发送**，地址相同的旧 TTL 不在此处纠正 |
| Kinetic / EnOcean 动能开关代理的绑定、启用及按键变化同步 | 代理设备 Light LC Client / Generic OnOff Client / Scene Client / Generic Level Client → 按键动作目标地址 | `0xFF` | SDK `getEnOceanSwitchEnabledMessageHandles`；Set / Virtual Address Set 共用同一个 `Publish` |
| EFC 应急/消防控制器状态事件发布 | Scene Client → EFC 内部发布组 | `0xFF` | `DeviceEmerFireData.getPublicationMessageHandles`；以发布地址判断是否需要配置 |

Presence 与 Ambient Light 都是 Sensor Server（SIG Model ID `0x1100`），通过属性和 element 区分用途。Kinetic 的调光与调色温都可使用 Generic Level Client，但由对应 element / 按键路由区分。EFC 的 Scene Client 发布是控制器状态事件链路，不能和它的 Vendor Action Config 混为一谈。

Manual Control 和两类 Proximity Lighting 不在 `getNodeSyncProfiles` 的 Presence-to-group 启用条件内；它们可能触发旧传感器发布清理。Proximity 的私有邻居转发另有 TTL 字段，不属于本表的标准 Model Publication。

主要证据：[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)、[Node+MessageHandles.swift](../SunSmart/Common/Data/Node+MessageHandles.swift)、[LightSensorCalibrationViewController.swift](../SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift)、[GroupViewController.swift](../SunSmart/Main/Group/Controller/GroupViewController.swift)、[DeviceEmerFireData+Sync.swift](../SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift)、[MeshSensorCalibrateManager.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift)、[MeshEnOceanProxyServer.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift)。

## 校准遗漏的行为链与实际影响

1. App 的 Plane / Night / Sensor 按钮分别调用 SDK `calibrate` / `calibrateNight` / `calibrateSensor`，都汇入 `initialize()`。
2. SDK 保存旧 Publication 快照，然后临时把 Ambient Light Sensor Server 的发布目标改成手机，TTL=5、period disabled、retransmit disabled。
3. 正常成功后，App 的 `sensorEnabled` 或 `commitCalibrationSensorSelection` 再将目标设为灯组、TTL=`0xFF`。
4. SDK 校准失败时恢复旧快照；Night / Sensor 的 App 提交失败也有快照恢复。恢复的 TTL 是快照原值。

因此，`2d0bf4539` 修好了**校准完成后的组发布**，没有修改 SDK **校准期间向手机的临时发布**。该提交只涉及 App 代码及测试/文档，并未改变 SDK。

这是明确的配置策略不一致，但不能由此直接断言校准失败或多跳覆盖异常：当前 SDK 优先使用传感器自身 Proxy，必要时建立该传感器的 GATT 连接，且校准采样还调用 `SensorGet`。临时 Publish TTL=5 与运行期间整组 Publish TTL=5 的影响不同。成功流程会将 TTL 改回 `0xFF`；实际中断、离线、固件对配置的处理仍需运行证据。

## SDK 中仍写 5 的潜在/旧入口

以下加上正在使用的 `MeshSensorCalibrateManager.initialize()`，共 7 个显式使用 `networkParameters.defaultTtl` 的启用构造位置。

| 构造位置 | TTL / Model / 目标 | 当前 App 是否会使用 |
| --- | --- | --- |
| `Node+Messages.getConfigMessageHandles` | 5；`publishModelIDs` 指定的 Model → `.localClientGroupAddress` | 通用函数被 Fast Add、重绑、设备恢复、读取/同步、网关补配置调用；但正常 Site 流程将 `publishModelIDs=[]`，publication 循环不生成消息 |
| `MeshAPI.publishNode` | 5；调用者指定 Model 与目标，可设置 period | 全 App 与 SDK 未发现调用，仅有 API 定义 |
| `MeshSensorCalibrateServer.publishSensorAmbientLight` | 5；Ambient Light Sensor Server → 手机 | 旧校准实现；App 中调用已注释，仅 SDK busy 判断还引用实例 |
| `MeshSensorBetaCalibrateServer.publishSensorAmbientLight` | 5；Ambient Light Sensor Server → 手机 | 未发现 App 调用 |
| `MeshAddDeviceManager.didReceiveMessage` 的普通状态发布 | 5；OnOff / Lightness / CTL Temperature / HSL Server → `0xFFFF` | 旧 `startAddDevice(s)` 链；当前 App 添加与恢复使用 `startFastAddDevices`，未发现旧添加 API 调用 |
| 同一旧 Manager 的周期发布后备分支 | 5；Generic OnOff Server → `0xFFFF` | 同属未调用旧链；还位于 Heartbeat 配置构造失败的后备分支，不能视为当前周期上报功能 |

`SiteViewController.viewDidLoad` 同时清空 `publishModelIDs` 和 `publishTimeModelIDs`；本轮未发现其他生产赋值恢复这些列表。SDK 原始默认列表仍非空，若未来绕过 Site 初始化或启用通用发布功能，这些路径会重新暴露 TTL=5 的策略差异。该结论仅用于说明潜在入口，不表示当前已复现这种绕过。

注意旧 `MeshAddDeviceManager` 自己持有私有 Model 列表，不受上述全局空列表控制；它目前不触发的依据是**当前 App 无旧添加 API 调用**。

另有 App `GroupViewController.sensorPublishCheck()` 两处启用构造已经是 `0xFF`，但唯一调用已注释；`LightSensorCalibrationViewController` 和 SDK `Node+Messages` 还保留了 TTL=5 的注释代码。以上不计为实际运行写入。

证据：[SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift)、[Node+Messages.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift)、[MeshAPI.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift)、[MeshAddDeviceManager.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift)。

## 禁用、回滚与存量设备

| 操作 | 实际 TTL | 判断 |
| --- | --- | --- |
| Profile 清理不再需要的传感器发布；校准切换旧传感器、关闭传感器；Kinetic 禁用/解绑 | `0`；Publish Address=`0x0000` | SDK `disablePublicationFor` / `Publish.disabled` 生成的关闭状态，不是启用后固定 TTL=0 的发布；建议保持 |
| SDK 校准失败的 `restorePreviousPublicationIfNeeded` | 旧 `Publish.ttl`；可能 5、`0xFF` 或其他已缓存值；无旧值时禁用 | 完整恢复进入校准前状态，不应在恢复编码器中隐式迁移 |
| App 校准提交失败的 `publicationRestoreHandle` | 选中/原组选中传感器快照中的 TTL；无快照时禁用 | 同上；如要统一旧值，应作为独立迁移策略 |
| Group Profile Need Sync / SAVE / Sync | 校验 TTL 必须为 `0xFF`，否则生成修正任务 | `2d0bf4539` 已补齐；仍依赖缓存与成功下发，不能宣称离线设备已更新 |
| Group 页面进入补建 | 新下发为 `0xFF`，仅比较地址 | 单纯重新进页面不保证相同地址的 TTL=5 被纠正；后续 Profile 同步可处理 |
| EFC 发布同步 | 新下发为 `0xFF`，仅比较地址 | 旧地址正确、TTL=5 时不会仅因 TTL 自动重写；触发普通同步也不必然发 Publication |
| Kinetic 按键同步 | 新下发为 `0xFF`，先比较按键配置差异 | 按键未变时可无发布任务，旧 TTL 不能保证自动更新 |

导入/导出、数据库加载中的 `Publish` 编解码，以及 Publication Status 回写缓存，本身不是向设备配置 Publication。不能通过修改这些基础编解码器实现 TTL 全局覆盖，否则会改变快照恢复与设备真实状态记录。

## 其他 TTL 字段的范围边界

- Battery/AC Switch Key Config、EFC Action Config、Proximity Neighbor Config 属于私有协议配置；Heartbeat Publication、DFU Distribution 也有独立 TTL 状态。不能把 Model Publish TTL=`0xFF` 的规范直接应用到所有这些字段。
- 本轮附带核对发现，当前 `GroupServer.getNodeAddMessageHandles` 的私有 Neighbor Config 仍取 `networkParameters.defaultTtl`（5）；Node / Space / EFC 同步相关 Neighbor 写 0。这是独立问题，不计入标准 Model Publication 遗漏，也未在本轮修改。较早修复记录不能代替当前分支源码。
- Lab 覆盖的是 App 发送配置命令的网络层 TTL；对“配置负载中的 Publish TTL”没有补救作用。

## 建议的后续决策

1. **最小范围**：将当前 SDK `MeshSensorCalibrateManager.initialize()` 的临时发布 TTL 改为 `0xFF`；一处覆盖三种校准模式。保留地址、AppKey、period、retransmit、成功后切换和失败回滚语义。
2. **可选一致性整理**：是否把 SDK 其余 6 个潜在/旧启用构造位置也统一为 `0xFF`，避免今后重新启用时复发。此项不需开启当前关闭的功能，也无需改网络层默认 TTL。
3. **独立决定存量策略**：是否让 EFC/Kinetic 主动识别旧 TTL、是否让进入 Group 页面就修正 TTL，以及是否安排存量读回/迁移。上述内容会扩大行为范围，不应默认为一次常量修正的附带工作。
4. 若批准实施，优先用现有 Publication/校准行为测试验证 `0xFF` 的实际 payload、成功转回组发布、失败原样恢复、禁用状态不变；SDK 发布与 App 正式依赖 revision 同步记录。完成后按项目要求构建代表 scheme。共享 SDK 已有其他未提交工作，实施前须再次确认写入范围。

本轮完成的是源码调用链、参数来源、编码器和入口条件审计。未运行构建或测试，也没有设备读回、空口抓包或真实覆盖范围结论。现场验收应区分校准准备阶段的临时发布、成功后的组发布和失败恢复后的旧配置。

## 开发方案及用户确认（2026-09-21 19:35）

本节记录用户指定的两项：当前校准临时发布修正，以及另外 6 处潜在/旧启用构造的一致性整理。前文其余建议不进入本次实施范围。**用户已回复 A，批准同时实施两项；完成情况见末尾实施记录。**

### 基线刷新

- App HEAD 仍为 `59f7dbbafc0ce40c64a8051150ce7e15c7db946e`，当前只有本分析文档未跟踪。
- SDK 已更新至 `9624f9cf3b5a06f738bed91a943e54f7435ed8cc`，工作区干净。上一轮记录的 Fast Add / Proxy Queue 改动及相应测试已包含在该提交中。
- 已检查 SDK 两个 revision 的差异：仅涉及上述队列修复及测试，不涉及本方案的 6 个生产文件；7 处 Publication TTL 仍取 `networkParameters.defaultTtl`。
- 本地映射仍指向 `one-dev`；正式 `Package.resolved` 仍为 `a971027e08f9775d7a3f071a06f89be1c38ecc96`。本地 SDK 与正式锁定版本已有差异，最终交付分别记录，不能用本地构建代替正式依赖已发布的结论。

### 推荐范围与具体改法

**推荐同时批准第 1、2 项：6 个 SDK 生产文件，共 7 处参数替换。** 另外 6 处与现行校准入口具有相同的 Publish TTL 语义，替换不要求打开旧功能。若仅批准第 1 项，则只改下表第一行并执行相应验证。

| 决策 | SDK 文件 / 函数 | 数量 | 实施方式 |
| --- | --- | --- | --- |
| 1：最小修正 | `MeshSensorCalibrateManager.swift` / `initialize()` | 1 | 临时向手机发布的 TTL 从网络默认值改为 `0xFF`，覆盖 Plane / Night / Sensor 三种校准 |
| 2：一致性整理 | `Node+Messages.swift` / `getConfigMessageHandles()` | 1 | 通用节点状态发布改为 `0xFF` |
| 2：一致性整理 | `MeshAPI.swift` / `publishNode()` | 1 | 显式发布 API 改为 `0xFF`，调用签名与 period 规则不变 |
| 2：一致性整理 | `MeshSensorCalibrateServer.swift` / `publishSensorAmbientLight()` | 1 | 旧校准临时发布改为 `0xFF` |
| 2：一致性整理 | `MeshSensorBetaCalibrateServer.swift` / `publishSensorAmbientLight()` | 1 | 旧 Beta 校准临时发布改为 `0xFF` |
| 2：一致性整理 | `MeshAddDeviceManager.swift` / `didReceiveMessage` | 2 | 普通状态发布及周期发布后备分支均改为 `0xFF` |

所有替换都只作用于**启用标准 Model Publication 时的 TTL 实参**，直接使用 `0xFF`，与 SDK 已有 Kinetic 实现一致。必要时加简短注释解释“使用源设备 Default TTL”。不为 7 处常量替换引入公共策略 API、跨模块依赖或通用工厂。

约束：

- 保留 Model / element、发布地址、AppKey、Friendship flag、period、retransmit、发送目标、调用前置条件和执行顺序。
- 保留成功后切换到组发布、失败快照恢复、无快照时禁用的现有行为。旧快照 TTL=5 时仍恢复 5。
- 保留 `Publish.disabled` 的地址 `0x0000` 和 TTL=0。
- 不修改 `networkParameters.defaultTtl`、Lab 发包 TTL、Heartbeat 或其他私有协议 TTL；尤其不误改旧添加函数中紧邻的 Heartbeat Publication TTL。
- 不启用空 Model 列表或旧 API，不修改注释中的旧代码，不新增 TTL 差异判定或存量迁移，不修改 App 业务代码。

### 验证方案

1. **复用现有行为测试入口**：扩展 App `Tests/Group/SensorPublicationBehaviorTests.py`，按批准范围提取 SDK 生产 Publication 构造表达式，配合现有值/Model 替身与 SDK 实际 payload 编码代码执行验证。保留测试对 `.local-sdk` 实际映射的读取，不建立临时 Xcode 工程或新测试框架。
2. **验证真实输出参数**：覆盖全部获批构造位置；令 App network TTL 取 5、15、127 等不同值，断言生成的 Publish TTL 和 payload TTL 字节始终为 `0xFF`。同时核对地址、AppKey、Model、period 和 retransmit 保持原行为；周期发布/API 需包含非零 period 用例，防止误变成禁用周期。
3. **保护恢复与禁用语义**：复用 `Tests/Group/CalibrationModeControlBehaviorTests.py` 的成功提交、失败及重试、旧快照完整恢复用例；补充 SDK `restorePreviousPublicationIfNeeded` 的必要隔离行为覆盖，验证旧快照含 TTL=5 / `0xFF` 均原样发送，无快照则禁用，失败状态仍正确返回。三种校准模式共用 `initialize()` 的关系以调用链检查配合运行验收确认，不能把构造表达式测试称为完整三模式运行测试。
4. **一次代表构建**：整轮改动及回归完成后，使用 `SunSmartLocal.xcworkspace`、`SunSmart`、Debug、`iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，稳定 DerivedData 目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-cli`。无公共 API、资源或品牌编译路径变化，按本次风险不机械重复所有品牌/Release 构建。
5. **静态收口**：确认除批准的 TTL 参数及相关测试外没有新增业务差异；检查启用入口没有遗漏，禁用、回滚和网络默认 TTL 未变，执行 `git diff --check`。已有综合 TTL 脚本同时约束本次范围外的 Neighbor 配置，不为使它通过而扩大本次修复；本次验收以针对性行为/payload 回归为主。

自动化验收标准是获批构造点写出 `0xFF`、其他字段及恢复/禁用行为保持、相关回归和代表构建通过。真实设备默认 TTL 的使用及通信表现仍由运行验收确认。

### SDK 交付与人工验收

- 实施落在当前实际使用的 `one-dev`；开始写入前再核对 HEAD、工作区及 SDK 写入占用，避免与其他任务并发修改。
- 本方案只批准源码与测试修改的范围。SDK commit / push / release、App 正式依赖锁定更新按后续明确授权执行；不改正式工程为个人绝对路径。
- 交付记录 SDK 基线、最终 revision 或未提交 diff、App 本地映射与测试/构建结果，并列出“SDK 发布后更新正式锁定 revision”的待办。
- 默认不自动操作真机。最短人工验收是分别进入 Plane / Night / Sensor 校准，检查准备阶段发往手机的 Publication TTL=`0xFF`；正常完成后仍发往灯组且 TTL=`0xFF`；一次受控失败后核对旧快照恢复。潜在/旧入口通过隔离 payload 测试覆盖，不为验收而打开隐藏功能。

**用户确认：A. 同时实施第 1+2 项（7 处）。其他决策本轮均不实施。**

## 实施与验证记录（2026-09-21）

### 实际修改

- SDK `one-dev` 基于 `9624f9cf3b5a06f738bed91a943e54f7435ed8cc`，上述 6 个生产文件合计 7 处 TTL 实参替换为 `0xFF`。最终生产 diff 为 7 行替换，没有其他行为修改。
- App 生产代码、工程配置、依赖声明及锁文件均未修改。仅扩展 [SensorPublicationBehaviorTests.py](../Tests/Group/SensorPublicationBehaviorTests.py)，沿用既有隔离 Swift 行为验证方式。
- 测试直接使用 7 个 SDK 入口的生产构造表达式、SDK `Publish` 初始化方法、周期/重发初始化方法、`ConfigModelPublicationSet` 初始化及实际 payload 编码器，并执行 SDK 的原始 `restorePreviousPublicationIfNeeded` 方法体。外围 Node/Model 和发送响应使用替身，不能作为真实 BLE 或三种校准完整流程验收。
- 已复核最终 diff：发布地址、AppKey、Friendship flag、period、retransmit、前置条件、成功切换与失败回滚未变；禁用仍为地址 0 / TTL 0。网络默认 TTL、Heartbeat、私有 Neighbor 参数、旧功能开关及迁移判定未改。
- 全量复查标准 Publication 构造后，剩余取 `networkParameters.defaultTtl` 的匹配均在既有注释中，本次未修改注释代码。

### 验证证据

| 检查 | 结果与边界 |
| --- | --- |
| 修改生产代码前运行新增 Publication 回归 | 按预期失败：`FAIL: calibration must inherit device Default TTL, network TTL=5`，确认能捕获原问题 |
| `python3 Tests/Group/SensorPublicationBehaviorTests.py` | **通过，1769 条 App/SDK 行为与 payload 断言**；覆盖 7 个入口、network TTL=5/15/127、两个 AppKey、不同目标地址、周期 0/16/63、旧快照 TTL=0/5/15/255、成功/失败/无响应及禁用 |
| `python3 Tests/Group/CalibrationModeControlBehaviorTests.py` | **通过，575 条生产方法提取后的命令序列断言**；含既有成功提交、失败/重试与旧 Publication 完整恢复 |
| App 与 SDK `git diff --check` | 通过 |
| SunSmart generic iOS 构建 | **`BUILD SUCCEEDED`，退出码 0**；Debug / iphoneos / generic iOS / 无签名；已确认解析到当前 `.local-sdk/nordic-sig-mesh-sdk` |

构建使用 `SunSmartLocal.xcworkspace`、`SunSmart` scheme，DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-cli`。没有 Simulator 或真机安装/运行；构建后生产代码未再修改。新增隔离测试仍会输出原有提取片段中 `daylightEnabled` 未使用警告，不影响测试结果。

### 交付状态与剩余事项

- App HEAD 保持 `59f7dbbafc0ce40c64a8051150ce7e15c7db946e`；本次 App 差异为测试文件与本分析文档。
- SDK HEAD 保持 `9624f9cf3b5a06f738bed91a943e54f7435ed8cc`，**本次修复在其上的 6 个未提交文件中**。仅检出该 revision 尚不包含 TTL 修复，需要同时携带本次 diff。
- 未执行 commit、push 或发布。正式 `SunSmart.xcworkspace` 仍锁定 `a971027e08f9775d7a3f071a06f89be1c38ecc96`；待 SDK 修复发布后再更新 App 正式锁定 revision。本地构建通过不表示正式依赖已取得修复。
- 真机验收未执行：检查三种校准准备阶段的 Publication TTL=`0xFF`，成功后转回灯组发布，一次受控失败后恢复原配置。设备实际采用 Default TTL 与通信表现仍需该运行证据。
