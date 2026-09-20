# Information 页面 TTL 功能分析与开发方案

日期：2026-09-20。状态：用户已确认，代码实现及自动化验证完成；真实 Mesh、页面体验与服务器重新拉取待人工验收。

## 结论

需求合理，现有共享 Information 页面、Mesh 标准配置消息及本地/云端数据结构能够承接。需要明确 TTL 的定义、合法输入、实时读取失败的展示、权限范围，以及设备成功但本地/云端保存失败的处理。

建议配置节点的 Default TTL；在 Signal strength 后、Date time / Time zone 前显示 TTL。设备读取确认、本地保存及本次云端同步均成功后才提示完整成功。设备已修改而云端失败时保留真实新值，显示部分成功并支持只重试云端同步。

## 调查基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-gateway`；分支 `fix-gateway`；HEAD `089b3550`；调查开始时工作树干净。
- 本地入口：`SunSmartLocal.xcworkspace`；`.local-sdk/nordic-sig-mesh-sdk` 正确指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`a971027`；调查时无未提交改动。以下 SDK 结论来自当前本地源码，不代表已验证正式远端 release 的版本一致性。
- 初次调查只读取代码并编写方案；用户确认后的实施及验证结果见下文。全过程未操作真机或服务器。

## 已确认的代码事实

| 范围 | 事实与方案影响 |
| --- | --- |
| Information 页面 | `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift` 已通过 row ID 组织数据和点击事件；Signal strength 后追加日期/时区。可增加 `.ttl`，无需依赖固定行号。 |
| 网关入口 | `GatewayViewController` 将 `GatewayInformationContext(site:gateway:)` 传入共享页面；`WiFiGatewayViewController` 继承此控制器。`GatewayInformationViewController.swift` 是空壳，不是本次实际入口。 |
| 普通设备入口 | `DeviceBaseViewController`、`DeviceLightViewController`、`EmerFireAlarmMonitorRouting`、`PJEightKeySwitchMonitorVC` 均调用共享页面；目前没有统一传入用于 TTL 权限及上传的 Space 上下文。 |
| 真实节点与逻辑设备 | 八键开关 `informationNode` 取自 `switchData.proxyNode`，但有 `node.isPowerSwitch` 限制；此入口可对应真实电池开关，不能仅因字段名含 proxy 就排除。实施时按页面代表的真实设备核对身份，不能把逻辑开关 TTL 操作落在灯具代理上。 |
| 设备权限 | `SpaceData.canEditing` 处理角色、退出/删除、密码验证和配置安全状态；`deviceOperates.contains(.edit)` 还处理 Editor 禁用及 Mesh OTA 等限制。 |
| 网关权限 | `SiteData.canConfigureGateway(_:)` 已实现 Site Owner 与可编辑关联 Space 的判断；无关联 Space 的网关也有现行授权规则。不能用“Site 中任意 Space 是 Editor”替代现有作用域。 |
| Mesh 消息 | SDK 已提供 `ConfigDefaultTtlGet`、`ConfigDefaultTtlSet`、`ConfigDefaultTtlStatus`。Status 只有 TTL 值，没有独立的成功/失败状态码。 |
| SDK 缓存 | `Node.defaultTTL` 是可空缓存；已入网远端 Node 的 public setter 拒绝直接赋值。`ConfigurationClientHandler` 收到 Status 后更新内部 TTL，并调用 `node.save()`。 |
| 本地存储 | SDK `MeshDatabase.swift` 的 Node 主表有 `defaultTTL`，`node.save()` 写入该列。`savePropertys()` 写的是另一张属性表，不能独立保存 TTL。SDK 自动保存没有向页面返回保存结果，业务流程需检查可用的显式保存结果。 |
| 云端数据 | Node Codable 已包含可选 `defaultTTL`。App `ExportData.swift` 的 Space 节点导出与独立 Node 导出均基于该编码；`ImportData.swift` 使用 Node 解码恢复。无需另造 TTL 字段，旧数据缺字段可保持 nil。 |
| 普通设备同步 | `SpaceData.commitLocalChangeForCloudSync` 已封装时间戳递增、持久化和 Space/Site 上传选择，但当前不暴露完成回调。若需页面等待服务器结果，应最小扩展此入口或订阅对应任务结果，不能仅发全局通知。 |
| 网关同步 | `syncGateway` 实际走 `GatewayServerAuthorizationService.authorizeWithReceipt`，提交节点 JSON 并按 submitted generation 确认上传。应复用现有关联数据保护、版本确认和错误状态。 |
| 同步并发 | `addSynchronizationHandle` 会取消、替换同一对象的旧任务。页面不能把旧任务取消当作设备写入失败，也不能用此前任务的成功结束本次等待。 |
| Mesh 并发 | SDK 心跳在部分设备上也使用 Default TTL Get；页面自动读取、Set 与核实读取需串行，并过滤目标身份、请求轮次和返回值。不要通过全局清空消息或停止他人任务解决竞争。 |

SDK 相对源码位置：`Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/Node.swift`、`Mesh Messages/Foundation/Configuration/ConfigDefaultTtl*.swift`、`Layers/Foundation Layer/ConfigurationClientHandler.swift`，以及 `Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`。

## 建议补全的需求

### TTL 的定义和输入

- 本功能表示目标 Mesh 节点的 **Default TTL**，不是 App/Lab 发包 TTL、收到报文的剩余 TTL、Model Publication TTL，或 Trigger Zone / Neighbor 的载荷 TTL。
- 用户追加防呆要求后，Information 的可编辑值限定为 **2～127 的十进制整数**，禁止设置 0、1、128～255、负数、小数和空输入；不能自动截断或把非法值钳制成另一个值。协议响应仍接受 0 或 2～127，以兼容既有设备。SDK 当前消息注释写为 `1...127` 且构造器不校验，App 在输入、操作协调器和 Mesh 下发入口分别校验可编辑范围。
- `0` 表示该设备使用默认 TTL 发出的相关报文不经其他节点中继，可能影响多跳回传。Information 禁止设置为 0；既有 0 仍能读取、显示、保存实际值，并可修改为 2～127。不自动迁移已有配置。关闭设备 Relay 是停止转发其他设备的报文，与 Default TTL=0 不等价。依据：[Bluetooth SIG Mesh Primer](https://www.bluetooth.com/bluetooth-mesh-networking-primer/)。
- `0xFF` 在部分发布/业务配置中可能表示使用默认 TTL，不能写入节点的 Default TTL。
- 设置 Default TTL 不保证所有消息都采用此值；显式配置的 Publication/业务 TTL 保持各自语义。此次不联动修改这些字段。

协议交叉核对：[Bluetooth SIG Mesh Protocol](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html) 的 Default TTL 与 Config Default TTL 消息章节；合法值由 [Silicon Labs 官方 Config Client 文档](https://docs.silabs.com/btmesh/latest/bluetooth-mesh-api/sl-btmesh-config-client#sl-btmesh-config-client-set-default-ttl) 明确列出为 0、2～127。未进行任何型号的固件实测。

### 展示和权限

- 行顺序：`Signal strength → TTL → Date time → Time zone`，后两项按现有入口规则出现。
- 仅对应作用域内的 Owner/Editor 展示 TTL；Visitor 隐藏且不触发该页面的 TTL 读写。
- 角色决定可见性，实际配置状态决定可编辑性。普通设备复用 `canEditing && deviceOperates.contains(.edit)`；网关复用现有 `canConfigureGateway`。Owner/Editor 临时不可配置时保留行但禁用修改并解释原因。
- 普通设备必须显式带入所属 Space。网关使用 Site/Gateway 上下文。展示、点击和最终发送前重新核对权限与当前网络/节点身份，不能只在构建列表时判断一次。
- 对真实 Mesh 节点启用；真实电池开关仍可支持，但可能需要唤醒。纯逻辑/虚拟对象或实际指向另一台代理设备的页面不应提供可写 TTL，建议隐藏该行。DALI 下游地址不单独视为 Mesh 节点。

### 当前值如何获取

- 进入页面时，对有权限的真实目标发送一次 `ConfigDefaultTtlGet`，读取中显示 `Reading…`。
- 收到合法 Status 后显示返回整数；以本次响应作为“当前配置”证据，不拿 App 默认值或 `node.defaultTTL ?? 5` 冒充设备实际值。
- 读取失败/连接不可用时显示 `--`；点击 TTL 尝试重新读取，读成功后再进入编辑弹窗。缓存可保留，但首版不把未经本页确认的缓存展示为当前值。
- 同一页面读取与写入串行；重复点击不产生并行任务。不持续轮询。重新进入页面重新读取。
- 网关首版复用现有 Information 的目标网关直连 Proxy Ready 前提；普通节点通过当前合法 Mesh Proxy 路由访问，无需逐台 BLE 直连。
- 网关服务器在线、RSSI 非空、Node.state 在线均不能替代当前可用的 Mesh 配置通道。无 Device Key/当前网络不匹配时不发送配置请求，也不因此判定设备永久不支持 TTL。
- 读取到与缓存不同的合法值时，保存真实缓存，并通过对应对象的既有云同步入口同步差异；数值未变化时不重复标脏上传。单纯阅读时不弹“修改成功”。

### 编辑与等待

- 弹窗复用 `SRAlertView`：标题 `TTL`，预填本次读取值，数字键盘，`Cancel` / `Confirm`，文案说明可编辑范围及禁止设置 0 的原因。
- 校验失败保持编辑、给出原因；不能沿用现有亮度输入中的自动范围钳制行为。
- 未修改数值则直接关闭，不发 Set；若已有云端待同步错误，提供独立的重试同步操作。
- 点击 Confirm 后关闭输入弹窗，复用等待 HUD/进度组件，按阶段显示 `Updating TTL…`、`Verifying TTL…`、`Syncing…`，期间禁用重复提交。
- 标准 Set 的 Status 本身是设备确认；必须验证来自目标节点、返回值合法且等于目标值。返回旧值或收到无关消息不能视为成功。
- Set 超时/回值不符时，在通道仍可用的情况下追加一次 Get 核实；读回目标值则继续保存和同步，读回其他合法值则展示实际值并提示未按预期修改。再次无响应显示“无法确认修改结果，请重连后重试”，不能声称硬件一定未修改。
- 实现使用 SDK acknowledged 机制，Get/Set 的独立终止期限为当前 `acknowledgmentMessageTimeout + 3` 秒；目的地址暂忙时仅在前 2 秒内重试发送，核实最多一次。未采用最初建议的读取 10 秒强制取消：SDK 的 `MessageHandle.cancel()` 会清理该目的地址的其他回调，可能干扰 TimeGet。云端前台等待最长 30 秒；已离线则保留入队任务并立即给出待同步结果。
- 页面退出时停止页面读取和 HUD 回调；已发送写入不能被宣称撤销。已取得真实设备确认的本地保存和云端同步由操作上下文完成，不能仅因 VC 释放丢失。切换网络后不把旧回调应用到新网络对象。

### 成功、失败与离线

| 实际结果 | 页面及数据行为 |
| --- | --- |
| 发送前权限/通道检查失败 | 不发 Set；解释权限或连接问题，保留真实已知状态。 |
| 收到合法值，但与目标值不同 | 显示设备实际返回值，提示未能修改为目标值；不上传用户未被确认的输入。 |
| Set 无响应且核实也失败 | 显示结果未确认，允许重连后重读；不把旧缓存当作当前实际值，不提交期望 TTL。 |
| 设备确认成功、本地保存失败 | 显示设备实际新值，提示“设备已更新，本地保存失败”；重试保存，不回滚设备，不提示整体成功。 |
| 设备和本地成功、云端失败/超时/离线 | 显示新 TTL，保留现有待上传标记；提示“TTL 已更新，但服务器同步失败”，提供 Retry；重试只执行云端步骤。 |
| 设备、本地、本次云端上传均成功 | 刷新 TTL，结束等待，提示 `TTL updated successfully.`。 |

建议允许“有 Mesh 通道但手机无互联网”时修改，按待云端同步处理，不为了网络离线禁止合法的本地配置。对于尚未上传的 Site，复用现有先上传 Site 的选择逻辑。若产品要求必须有互联网才能开始修改，可以调整前置条件，但仍无法消除写设备之后服务器失败的部分成功场景。

## 开发拆分

1. **补齐目标与权限上下文**：为共享 Information 增加明确的普通设备 Space / 网关上下文；接入上述五处实际入口，核对真实节点身份。TTL 不依赖 Lights 专属时间上下文。
2. **实现局部 TTL 操作逻辑**：集中输入校验、读取、Set/核实、阶段状态及请求身份；只服务 Information TTL，不扩展成通用设备配置框架。优先使用已有 SDK Config API，不预设 SDK 改动。
3. **衔接保存与同步结果**：使用 SDK 已更新的真实 Node 值，检查 Node 主表保存；普通设备最小扩展现有提交入口以取得对应云同步结果，网关复用 generation/receipt。对于任务替换追踪当前待上传版本，不因旧回调误报成功。
4. **接入 UI 和国际化**：增加行、数字输入、等待及结果提示；复用通用 Key，新增 TTL 专用 Key 同时补齐 `en.lproj`、`zh-Hans.lproj`，核对五品牌资源归属。当前 Lab TTL 范围文案不可直接复用。
5. **执行针对性验证**：先完成行为测试，再构建受影响代表 scheme；若新增文件归属或资源/项目配置产生跨品牌风险，稳定后覆盖全部受影响品牌。

预计改动集中在共享 Information 控制器、一个局部 TTL 操作对象、现有入口的上下文传递、Space 提交入口的最小结果透传及中英文文案。原则上不增加数据库列、不新增 TTL 专用服务器接口、不调整 Lab TTL、不迁移旧设备配置。服务器是否完整保留并返回该字段仍需实际上传/重新拉取验收，不能仅依据客户端导出判断服务端已通过。

如实施暴露 SDK 缺失，先明确最小差异，再按项目规则只在 `one-dev` 修改，并记录 revision、发布待办与 App 正式依赖兼容性；当前方案不依赖新增 SDK API。

## 验证范围和完成标准

- 输入行为：2、127 允许；0（含 00/000）、1、128、255、负数、小数、空输入拒绝；相同值不重复写设备。既有 TTL=0 能读取并改回允许范围，核实返回 0 时按实际值显示且提示目标值未生效。
- 可见与编辑权限：Owner、所属 Space Editor、Visitor、Editor 禁用、待删除/权限失效；网关关联和无关联场景符合现行授权；最终发送前权限变化可拦截。
- 目标身份：网关、灯、传感器、真实电池开关/EFC、代理/逻辑对象；匹配网络和节点，错误来源/过期回调不驱动成功。
- 状态链：Get 成功/失败、Set 匹配/不匹配、Set 超时后 Get 成功确认、重复点击、连接断开、页面退出、云同步替换、服务器失败后仅重试云端。
- 数据行为：nil TTL/旧数据兼容；收到真实值后本地保存并重新加载；网关和 Space 导出/导入保留 `defaultTTL`；新值不被旧上传完成回调覆盖。
- 本地 SDK 自动保存的失败返回未透传到页面，需使用可用的显式保存结果和重新加载测试补足，不能仅断言内存值。
- 构建：实现后使用 `SunSmartLocal.xcworkspace`、Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`、本工作树稳定 DerivedData；不使用 Simulator。分析阶段不构建。
- 人工运行：4G 与 Wi-Fi 网关各一次；普通节点经 Proxy 修改一次；修改后重新进入并重启 App 核对；从服务器重新拉取确认；断网验证部分成功与恢复重试；禁止设置 TTL 0 与既有 TTL 0 的读回/纠正路径；Visitor 行隐藏。由用户完成，不自动操作真机。

## 已确认决策

用户已确认以下方案并授权实施：

1. 配置对象为节点 Default TTL。按追加要求，仅允许设置 2～127，禁止设置 0；保留既有 0 的读取和纠正能力，不联动其他 TTL 或 Relay。
2. 进入页面真实 Get，失败显示 `--`，点击重读；网关要求目标 Proxy Ready，普通设备走当前 Mesh Proxy。
3. 按实际设备/网关作用域展示和编辑；没有自身 Mesh 节点的逻辑对象不展示可写 TTL。
4. 支持设备已修改但云端待同步的部分成功结果，允许离线配置并只重试云端；全部完成后才提示完整成功。


## 实施结果与交接

- App 分支仍为 `fix-gateway`，基线 HEAD `089b3550`，改动未提交；SDK `one-dev` 未修改，未新增 SDK API 或调整正式依赖声明。
- 新增 `InformationTTLCoordinator.swift`：实际 TTL 值、输入校验、读/写/核实/保存/同步状态及失败重试。单独的 CloudConfirmation 决策确保旧上传版本不能确认本次修改。
- 新增 `InformationTTLMeshService.swift`：显式 Space/Gateway 作用域、权限与网络身份复核、标准 Config API、Node 主表保存及本地读回、现有云同步及上传版本确认。
- 更新共享 Information 与普通设备、灯、真实八键开关、EFC 入口；网关使用已有 GatewayInformationContext 自动接入。TTL 行位于 Signal strength 后；日期、时区的显示与点击入口保留。
- 首次 TTL 读取等待页面已有时间及固件读取结束，避免目的地址忙导致彼此干扰；SDK 暂忙重试有界，不取消其他请求。
- 云端失败不会阻止继续编辑 TTL；页面提供独立 Retry sync 入口。本地保存失败提供 Retry。结果提示明确保留设备已经确认的真实值。
- `SpaceData.enqueueSpaceSync` 从 private 调整为模块可用，复用已经持久化的待上传版本，不重复递增版本；未引入额外服务器接口或数据库列。
- 两个生产文件已加入五个品牌的 Sources；TTL 文案已补齐共享 English/简体中文资源。

### 已执行验证

| 验证 | 结果及证据范围 |
| --- | --- |
| `bash scripts/check_information_ttl.sh` | 通过。直接运行生产 TTL 状态逻辑的隔离行为测试：合法/非法输入、重复点击、旧值不冒充实时值、nil 缓存、超时核实、不同回值、本地保存失败、云端失败、只重试保存/上传、离线后继续编辑、页面退出、权限/网络变化、旧回调及上传版本。 |
| `bash scripts/check_gateway_information_time.sh` | 通过。包含原有时间格式/恢复相关隔离测试及页面、初始化入口等源码契约检查；源码检查不能证明真实 UI 行为。首次因枚举声明文本变化触发旧断言，恢复原日期/时区声明方式后通过，未放宽测试。 |
| `InformationClockRecoveryTests` | 使用现有 SDK MeshTimeConversion 与共享恢复逻辑编译后执行，通过。 |
| `LightTimeInformationRuntimeContractTests` | 对当前 Lights/Information/SDK 源码与项目配置检查，通过；属于源码契约而非真机运行。 |
| `bash scripts/check_device_information_menu_transition.sh` | 通过，确认现有菜单关闭后跳转的源码契约。 |
| 首版五品牌 generic iPhoneOS Debug 构建 | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 全部退出码 0；均使用 `SunSmartLocal.xcworkspace`、`CODE_SIGNING_ALLOWED=NO` 和 `DerivedData/SunSmart-fix-gateway` 串行构建。包含既有弃用、资源/重复源文件等警告，本任务未清理无关警告。 |
| 文件检查 | 项目配置与中英本地化 `plutil -lint` 通过，`git diff --check` 通过。 |

自动化未连接真实节点，也未执行服务器上传/拉取。隔离测试验证状态决策，构建验证 iOS 类型/API 与品牌文件归属；这些结果不代替实际 BLE、固件、本地数据库运行和服务器验收。

### 最短人工验收

1. 分别进入 4G / Wi-Fi 网关和一台普通设备的 Information，Owner/Editor 在 Signal strength 后看到实时 TTL；Visitor 不显示。
2. 修改为合法值，确认等待结束后提示成功，重新进入和重启 App 后读到相同值；从服务器重新拉取该设备配置，核对 `defaultTTL`。
3. 断开互联网但保持 Mesh 通道，修改 TTL，确认保留新值并提示同步未完成；仍能继续编辑。恢复互联网后点 Retry sync，确认仅补同步。
4. 设备不可达或在下发后断连时，确认有限等待后失败/结果未确认，重连重读可恢复；验证输入 0 无法提交；若设备已是 TTL 0，仍显示真实值并可改为 2～127。
5. 检查原有时间行、MAC 复制与返回交互；电池设备按其唤醒条件验证。无需自动安装或运行真机。


### 追加：禁止设置 TTL=0

用户要求仅增加设置防呆。已区分协议合法值 `isValid`（0 或 2～127）与可编辑值 `isEditable`（2～127），同时用于输入解析、协调器和 Mesh Set 入口；读取、核实及本地实际值保存继续兼容 0。没有修改 Relay 行为。

`bash scripts/check_information_ttl.sh` 已通过，新增直接调用 update(0) 不下发、前导零输入拒绝、既有 0 可读且可纠正、核实返回 0 保持设备真实值等回归。English/简体中文文案检查通过。本轮仅收紧共享校验和既有文案，无品牌条件或资源归属变化，构建选择代表 scheme SunSmart；先前四个其他品牌的构建属于首版验证，不视为本次重跑结果。

本轮 SunSmart generic iPhoneOS Debug 构建已通过（退出码 0），SDK 来源仍为 `one-dev/a971027`，`git diff --check` 通过。未操作真机。
