# WiFi Gateway Repair 与未同步状态分析

## 1. 文档状态

- 日期：2026-07-10
- 状态：源码分析完成，方案 A 已于 2026-07-10 确认
- 设备范围：CID `0x0A78`、PID `0x2721` 的 WiFi Gateway
- 前置设计：`docs/260710_1206_wifi_gateway_interrupted_add_recovery_design.md`
- 前置实现总结：`docs/260710_1343_wifi_gateway_recovery_implementation_summary.md`
- 正式设计：`docs/260710_1555_wifi_gateway_repair_recovery_design.md`

## 2. 结论

当前 WiFi Gateway 页面存在三个有明确优先级的展示层级：

1. `node.isKeybindComplete == false` 时，直接展示 `The device needs to be repaired.`，正常网关内容被空状态覆盖。
2. `node.isKeybindComplete == true` 时，展示正常网关详情；此时如果 `getNodeSyncGatewayData(gateway:)` 非空，再在 Name 区域展示 `Devices not synced`。
3. `node.isKeybindComplete == true` 且 Gateway 同步差异为空时，展示正常网关详情，不展示 `Devices not synced`。

`The device needs to be repaired.` 的优先级高于 `Devices not synced`。两者不是同一状态的不同文案：前者表示 App 本地 Node 的 Mesh 初始化或 Key Bind 完整性不满足；后者表示基础 Key Bind 已被本地判定为完成，但 Gateway 业务目标与本地已确认的设备状态仍有差异。

设备 Online、BLE Proxy 已连接或 WiFi 已连接都不能替代 `isKeybindComplete`。因此 Gateway 可以在 Online 时仍展示 Repair；相反，基础 Key Bind 已完成的 Gateway 即使当前 Offline，也不会仅因 Offline 进入 Repair 页面。

## 3. 三类页面状态的真实判断条件

### 3.1 Repair 页面

`GatewayViewController.updateData()` 在 `node.isKeybindComplete == false` 时创建 Repair 空状态。判断只依赖本地 Node 数据，不会在进入页面时读取设备真实 Key、Bind、Publish 或 Model 状态。

`isKeybindComplete` 的主要要求来自 SDK `Node+Config.swift`：

- Node 已完成基础 Initialize；
- 已有 AppKey、Elements、Models 和 Company Identifier；
- 要求主网络的设备已具备主 NetKey 与主 AppKey；
- 所有支持的 Models 已绑定要求的 AppKey；
- 需要 Publish 的 Models 已具备 Publish；
- 子 Element 所需广播组订阅已完成；
- Sensor Descriptor、Firmware ID、Composition Hash 等必需数据已取得。

任何一项在 App 本地缓存中不满足，都会直接进入 Repair 页面。

### 3.2 Devices not synced

只有 `isKeybindComplete == true`、正常详情已经展示时，Name 区域才检查 `getNodeSyncGatewayData(gateway:)`。对 WiFi Gateway，可能产生差异的主要条件包括：

- Gateway 的 Site/Project ID 与 `node.gatewayInfo.projectId` 不一致；
- Associated Spaces 对应的 NetKey、AppKey 或 Model Bind 不完整；
- Node 仍保留目标 Associated Spaces 之外的 Secondary Key，需要解绑；
- Gateway 当前目标的 Subnet AppKey Index 列表与已确认状态不一致；
- 本地已有 Server/MQTT 目标，但设备已确认的 Server Information 不一致。

WiFi Gateway 不参与 4G APN 差异判断。

### 3.3 正常网关信息

当 `isKeybindComplete == true` 时，页面显示 Name、Network Connectivity、Associated Spaces、Server Information 等 WiFi Gateway 正常内容。是否同时显示 `Devices not synced`，只取决于 Gateway 业务差异是否为空。

页面中的 Mesh Online、WiFi 配置、WiFi Connected、RSSI 等属于正常详情内的子状态，不决定 Repair 与正常详情之间的主分支。

## 4. 为什么“刚显示 Adding 就断电”更容易进入 Repair

Site 添加页在设备 GATT 连接成功后就把 UI 状态改为 `Adding`。这个文案会覆盖后续多个实际阶段：

1. Provisioning；
2. Provisioning 完成后保存 Node；
3. 创建并保存 `GatewayModel`；
4. Mesh Initialize / Key Bind；
5. Gateway Register；
6. Project、Spaces、Server 等 Gateway 附加配置。

因此 `Adding` 不是“已经完成基础配置”的标志。

如果断电发生在 Provisioning 已完成、Node 与 `GatewayModel` 已保存，但 Composition、AppKey、Model Bind、Publish 或必需状态尚未完成的窗口，Site 页面已经能找到这个 Gateway，而 `node.isKeybindComplete` 为 false，详情页就展示 Repair。

如果断电稍晚，App 本地已经满足 `isKeybindComplete`，但 Gateway 附加配置尚未全部完成，则页面展示正常详情加 `Devices not synced`。

还有第三种缓存分裂窗口：App 已根据 Status 更新为 Key Bind 完成，但设备断电前未可靠持久化相同配置。此时 App 仍可能展示正常详情或 `Devices not synced`，但后续 Vendor 命令无法获得业务响应。前一轮强制恢复设计就是为了处理这一类本地完成、设备实际不完整的情况。

## 5. SAVE 按钮显示问题

问题已确认存在。

父类在 Repair 状态调用 `showRepairBottomActions()`；普通 Gateway 默认显示 Delete。WiFi Gateway 覆盖了这个方法，但当前覆盖实现与正常状态相同，都会调用 `showSaveOnlyUI()`，所以 Repair 空状态下仍显示 SAVE。

修复边界应只作用于 WiFi Gateway：

- Repair 状态隐藏整个底部操作区，至少保证 SAVE 不可见、不可点击；
- 回到正常详情后恢复 WiFi Gateway 的 Save-only 底部操作；
- 不改变其他 Gateway 当前 Repair 底部操作规则。

## 6. 当前 Repair 为什么会成功后仍出现 Devices not synced

当前 Repair 只调用通用 `repairDevices`，底层执行 `MeshAPI.startKeyBind`。这条链只负责 Node Initialize / Key Bind 相关配置。

Repair 成功后，`GatewayViewController` 只在 `node.isKeybindComplete == true` 时移除 Repair 空状态并刷新页面；它不会继续执行：

- Associated Spaces 完整配置；
- Association Project；
- Sync Spaces；
- Server Information；
- Gateway 最终差异收敛检查。

因此基础 Key Bind 修复成功后进入正常详情，而 Gateway 业务差异仍存在，Name 区域继续显示 `Devices not synced`，是当前两段独立流程的必然结果。

当前 Repair 的成功提示也只代表通用 Key Bind 消息链返回成功，没有把以下条件作为统一成功门槛：

- `node.isKeybindComplete == true`；
- Gateway 完整恢复任务全部完成；
- `getNodeSyncGatewayData(gateway:)` 重新计算为空。

## 7. Repairing 成功后再次转圈并无法退出的风险

源码中没有“Repair 成功后自动再次调用 Repair”的显式递归，因此不能仅凭现有代码认定界面一定会自动启动第二轮 Repair。

但“再次出现 Repairing 并长期不结束”的风险真实存在，主要原因如下：

1. Repair 没有页面级 `isRepairing` 或操作标识，不能防止快速重复触发或旧回调影响新操作。
2. Repair 使用 Window 级、无自动截止时间的 `Repairing…` HUD；只有 Key Bind success/fail 回调会隐藏。
3. 页面退出、对象释放和 Gateway 切换没有专门终止或清理 Repair HUD 与 Repair 操作。
4. Repair 没有经过当前 WiFi Gateway 的 acknowledged 请求协调器。Gateway Online 后可能仍在自动读取 WiFi 信息，用户同时点击 Repair 会让 Device Key Config 与 AppKey Vendor 请求重叠。
5. 底层 Key Bind 与消息执行器是共享对象；重复 Key Bind 或其他消息链插入时会共享运行状态、消息队列和回调，存在回调归属被后续操作改变的风险。

单独、无并发的 Key Bind 有底层连接和 ACK 超时，理论上应结束。因此“无限 Repairing”更可能来自重复触发、请求重叠或回调生命周期丢失，而不是某一条 ACK 自身没有超时。

这项判断是源码级风险确认；由于本轮没有新的 Repair runtime Log，尚不能把用户现场的具体一次卡住百分之百归因到其中某一个分支。

## 8. 修复方案比较

### 方案 A：Repair 与 Devices not synced 共用完整恢复状态机（推荐）

Repair 按钮进入与 `Devices not synced` 相同的 Gateway Recovery 引擎，但使用更强的 Repair 初始化模式：

1. 必要时先取得或刷新 Composition，确保 Models 可用；
2. 强制下发 Gateway 基础 NetKey/AppKey 和 Model Bind；
3. 补齐 Publish、订阅、Sensor/Firmware/Composition Hash 等使 `isKeybindComplete` 成立所需的配置；
4. 执行 Associated Spaces、Association Project、Sync Spaces、Server Information；
5. 最终同时校验 Key Bind 完整与 Gateway 差异收敛；
6. 只有最终校验通过才提示 Repair 成功。

Repair 使用现有可退出、可展示任务结果的 Sync 进度页，不再使用不可取消的 Window HUD。

优点：只有一套任务与成功语义；可直接解决假成功、后续 `Devices not synced` 和无限 HUD；错误位置可见。

代价：点击 Repair 后会进入任务进度页，交互变化比当前单一转圈更明显。

### 方案 B：保留 Repairing HUD，在后台串联完整恢复

保留当前页面和 `Repairing…` 样式，在 Key Bind 后继续后台运行完整 Gateway Recovery，全部成功后才关闭 HUD。

优点：表面交互变化最小。

代价：完整恢复时间较长但过程不可见；需要额外实现取消、退出清理、进度、错误归属和后台 runner，容易形成第二套 Sync 执行器；再次出现不可退出 HUD 的风险最高。

### 方案 C：Repair 只修 Key Bind，成功后自动打开 Devices not synced

先完成当前 Repair，再自动进入现有 Gateway Recovery。

优点：实现改动较小。

代价：用户会经历两段流程；如果在两段之间提示成功，会继续产生假成功；如果第二段失败，Repair 成功语义仍然模糊。不能完整满足“Repair 成功后不再出现 Devices not synced”。

## 9. 推荐设计

推荐采用方案 A，并保持以下边界。

### 9.1 单一恢复入口

Gateway Recovery 增加明确触发来源：

- `Devices not synced`：沿用已实现的强制 Gateway 恢复；
- `Repair`：先完成可让 `isKeybindComplete` 成立的 Repair 初始化，再执行同一套 Gateway 业务恢复。

两种来源复用相同的 Associated Spaces、Project、Sync Spaces、Server Information 任务构建和串行执行，不再让 Repair 单独调用通用 `repairDevices` 后提前提示成功。

### 9.2 Repair 初始化

Repair 初始化不能直接复用当前 `gatewayRecoveryInitialization` 的现状，因为当前实现假设 Node 已有 Elements/Models，主要用于“本地 Key Bind 已完成但设备实际可能不一致”的 Devices not synced 场景。

Repair 模式需要：

1. 在 Elements/Models 不完整时先完成 Composition；
2. Composition 可用后再生成强制 Gateway Key/Bind 消息；
3. 同时补齐正常 Key Bind 仍缺少的 Publish、订阅和必要读取；
4. 初始化任务只有在消息全部成功且 `node.isKeybindComplete == true` 时才成功；
5. 初始化失败时，后续 Gateway 业务任务全部标记为 Skipped。

### 9.3 最终成功语义

完整 Repair 只有同时满足以下条件才提示成功：

- Recovery 中所有必要任务成功；
- `node.isKeybindComplete == true`；
- `node.getNodeSyncGatewayData(gateway:)` 重新计算为空。

如果任务表面成功但最终差异仍非空，流程必须显示失败或未完成，不能先提示 Repair 成功再回到页面展示 `Devices not synced`。

### 9.4 UI 与生命周期

- Repair 状态隐藏 WiFi Gateway 底部 SAVE；
- Repair 按钮只允许启动一个 Recovery；
- Repair 开始后进入现有 Sync 进度页，允许用户查看失败任务并按现有规则退出；
- 页面不再创建 Window 级无限时 Repair HUD；
- 返回 Gateway 页面时重新执行主状态渲染；
- 完整成功后显示正常详情，并在确认差异为空后不显示 `Devices not synced`；
- 失败后继续展示 Repair 或未同步状态，取决于最新的 `isKeybindComplete`；
- 旧操作回调不能更新新页面或再次发起 Recovery。

### 9.5 WiFi 请求串行

- `node.isKeybindComplete == false` 时不自动发 WiFi Credentials、Connection Status 或 RSSI 请求；
- Repair 使用现有 Gateway Recovery 前置协调逻辑，确保不会与已发出的自动 acknowledged 请求重叠；
- 自动请求结束后才能进入 Repair Recovery；
- Repair 完整成功并返回正常详情后，再重新加载 Network Connectivity；
- 用户网络操作在 Repair 空状态下不可见，不新增新的操作分支。

## 10. 预计影响文件

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 统一 Repair 与 Recovery 入口、页面刷新和最终状态回调。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Repair 状态隐藏 SAVE；Repair 时禁止自动 WiFi 请求；恢复完成后重新加载 Network Connectivity。
- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 增加 Repair 初始化所需的 Composition 后强制配置构建能力，保持不写 WiFi Credentials。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 区分 Repair 初始化与现有 Gateway Recovery 初始化，并收紧成功判断。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Gateway Recovery 触发来源、Repair 初始化时序、最终收敛检查和页面返回语义。
- `scripts/` 下的 WiFi Gateway contract checks
  - 增加页面状态、SAVE 隐藏、Repair 初始化、最终成功条件和 WiFi 请求门禁检查。

暂不计划修改通用 `DeviceProtocol.repairDevices` 或其他设备的 Repair 行为；WiFi Gateway 走专用完整恢复入口，避免扩大影响面。若 App 公开能力无法在 Composition 返回后追加强制配置，再评估对本地 NordicSigMeshSDK 的最小改动。

## 11. 验证矩阵

### 11.1 静态与状态契约

- `isKeybindComplete == false`：展示 Repair、隐藏 SAVE、不启动 WiFi 自动读取；
- `isKeybindComplete == true` 且 Gateway 差异非空：展示正常详情与 `Devices not synced`；
- `isKeybindComplete == true` 且差异为空：展示正常详情，不展示未同步提示；
- Repair 初始化缺少 Composition 时必须先取得 Models，再构建强制 Bind；
- Repair 成功必须同时满足 Key Bind 完整和 Gateway 差异为空；
- Recovery 期间重复点击不能启动第二条链；
- 退出或失败不会遗留 Window HUD 或旧回调导航。

### 11.2 iPhoneOS 构建

按项目规则直接验证以下 Debug generic iPhoneOS build，关闭签名：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

### 11.3 真机断电验收

至少覆盖以下断电窗口：

1. UI 刚显示 `Adding`、Provisioning 尚未完成；
2. Provisioning 完成、Composition 尚未完成；
3. Composition 完成、AppKey/Model Bind 进行中；
4. Key Bind 完成、Gateway append 配置进行中；
5. Gateway append 部分完成。

对能够在 Site 中留下 Gateway 的场景，验证：

- Repair 与 Devices not synced 的展示符合状态优先级；
- Repair 页面无 SAVE；
- Repair 只启动一次且可以退出进度页；
- 完整 Repair 成功后 `isKeybindComplete` 成立；
- 返回页面不再展示 `Devices not synced`；
- WiFi Credentials 未被恢复流程读取后覆盖或重新下发；
- 任一必要任务失败时不提示 Repair 成功。

## 12. 已确认决策

采用方案 A：点击 Repair 后进入现有 Sync 任务进度页，由该页面展示完整恢复过程；不再保留当前不可退出的 Window 级 `Repairing…` 转圈。
