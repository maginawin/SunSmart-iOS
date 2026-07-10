# WiFi Gateway Repair 完整恢复设计

## 1. 文档状态

- 日期：2026-07-10
- 状态：设计已确认，等待书面审阅
- 设备范围：CID `0x0A78`、PID `0x2721` 的 WiFi Gateway
- 关联分析：`docs/260710_1543_wifi_gateway_repair_state_analysis.md`
- 前置恢复设计：`docs/260710_1206_wifi_gateway_interrupted_add_recovery_design.md`
- 已确认方案：方案 A，Repair 与 `Devices not synced` 共用完整恢复状态机

## 2. 背景

WiFi Gateway 在 Site 添加页刚显示 `Adding` 时断电，可能已经完成 Provisioning 并保存 Node 与 `GatewayModel`，但尚未完成 Composition、AppKey、Model Bind、Publish 或 Gateway 附加配置。此时 Gateway 可以保留在 Site 中，并在重新上电后进入详情页。

现有页面在 `node.isKeybindComplete == false` 时展示 `The device needs to be repaired.`。当前 Repair 只执行通用 Key Bind，成功后不继续执行 Gateway 的 Associated Spaces、Project、Sync Spaces 和 Server Information，因此返回正常详情后仍可能展示 `Devices not synced`。

现有 Repair 还使用 Window 级、无自动截止时间的 `Repairing…` HUD，并且没有接入 WiFi acknowledged 请求串行协调器，存在重复触发、回调生命周期混乱和 HUD 无法退出的风险。

## 3. 目标

本次修复需要达到以下目标：

1. Repair 状态隐藏 WiFi Gateway 底部 SAVE。
2. Repair 与 `Devices not synced` 复用同一套 Gateway Recovery 任务构建与执行能力。
3. Repair 能覆盖 Composition 尚未完成的最早中断窗口。
4. Repair 完整执行基础 Mesh 配置和 Gateway 业务配置。
5. Repair 只有在基础 Key Bind 完整且 Gateway 差异为空时才成功。
6. Repair 不与 WiFi 自动读取、RSSI 或用户网络操作并发发送 acknowledged 消息。
7. Repair 不再使用不可退出的 Window 级无限时 HUD。
8. Repair 成功返回后不展示 `Devices not synced`。

## 4. 非目标

本次不包含以下改动：

- 不修改 Fast Add 的整体成功判定、回滚或删除策略；
- 不改变其他设备类型的通用 Repair；
- 不改变其他 4G Gateway 的 Repair 底部操作和恢复方式；
- 不修改普通 Save 的差异同步策略；
- 不读取、保存或重新下发 WiFi SSID、Password；
- 不新增 Auth 信息；
- 不对通用 Sync 页面做无关重构；
- App 公开能力足够时不修改 NordicSigMeshSDK。

## 5. 页面状态真值

Gateway 详情页保持以下固定优先级：

| 条件 | 主页面状态 | 附加提示 |
| --- | --- | --- |
| `node.isKeybindComplete == false` | Repair 空状态 | 不展示正常网关信息，不展示 SAVE |
| `node.isKeybindComplete == true` 且 Gateway 差异非空 | 正常网关详情 | 展示 `Devices not synced` |
| `node.isKeybindComplete == true` 且 Gateway 差异为空 | 正常网关详情 | 不展示未同步提示 |

Gateway Online、BLE Proxy、WiFi Connected 和 RSSI 只影响正常详情内的连接展示，不改变以上主状态优先级。

该判断仍使用 App 本地已确认的 Node 状态，不在页面进入时增加一轮设备全状态读取。

## 6. 组件设计

### 6.1 Gateway 页面状态渲染

职责：根据 `isKeybindComplete` 切换 Repair 空状态与正常详情，并根据 Gateway 差异决定是否展示 `Devices not synced`。

Repair 状态下：

- 隐藏整个 WiFi Gateway 底部操作区；
- 保留 Repair 按钮；
- 不启动 WiFi Credentials、Connection Status 或 RSSI 自动请求。

正常状态下恢复 WiFi Gateway 的 Save-only 底部操作和 Network Connectivity 加载。

### 6.2 Gateway Recovery 触发来源

Gateway Recovery 增加明确的触发来源：

- `devicesNotSynced`：使用已经实现的强制 Gateway 初始化模式；
- `repair`：使用本设计新增的 Repair 初始化模式。

触发来源只决定第一个 Initialize 任务和完成后的页面刷新语义。Associated Spaces、Association Project、Sync Spaces、Server Information、离线终止和 Skipped 规则继续复用现有实现。

### 6.3 Repair 初始化构建器

Repair 初始化负责把 Node 从本地不完整状态恢复到 `isKeybindComplete == true`，分为两个阶段。

第一阶段处理 Composition：

- 当 Elements、Models 或 Company Identifier 不完整时，先发送 Composition Data Get；
- 必须收到匹配且成功的 Composition Data Status；
- 收到并更新 Node 后，才能构造依赖具体 Models 的 Bind、Publish 和读取任务；
- 如果本地 Composition 已完整，则不增加无必要的 Composition 读取。

第二阶段处理基础配置：

- 强制下发当前网络 AppKey；
- 设备要求主网络且当前网络不是主网络时，强制下发主 NetKey 与主 AppKey；
- 对 Gateway 全部支持 Models 强制重做要求的 AppKey Bind；
- 追加当前 Node 为满足 `isKeybindComplete` 仍需要的 Publish、子 Element 广播订阅、Sensor Descriptor、Firmware ID、Composition Hash 等配置或读取；
- 关键 Key/Bind 不依据本地 `knows`、`bind` 缓存裁剪；
- 不生成 WiFi Credentials 相关消息。

如果第一阶段取得了新的 Composition，第二阶段消息必须在 Composition Status 更新 Node 后动态生成，不能在 Models 尚不存在时提前构造。

### 6.4 Gateway 业务恢复任务

Repair 初始化完成后，继续执行现有 Gateway Recovery：

1. `Initialize`
2. `Associated Spaces`（存在目标 Space 时）
3. `Association Project`
4. `Sync Spaces`
5. `Server Information`（存在服务器目标时）

任务语义保持不变：

- Associated Spaces 对目标列表执行完整 NetKey、AppKey 和 Model Bind；
- Association Project 强制下发 Site/Project；
- Sync Spaces 强制下发完整目标 AppKey Index 列表；
- Server Information 存在有效目标时强制下发；
- 不读取或覆盖 WiFi SSID、Password。

## 7. 数据流

用户在 Repair 空状态点击 Repair 后：

1. 使用现有统一 Gateway 权限真值进行防御性校验；
2. 检查 Gateway Online 与 Proxy 可用状态；
3. 进入 WiFi 请求前置协调器；
4. 若已有自动请求，停止新增 Timer 请求并等待当前自动请求完成；
5. 若存在用户主动网络操作，不排队并提示等待；Repair 空状态正常情况下不会暴露这些操作；
6. 只创建一次 `.gatewayRecovery(..., trigger: .repair)`；
7. 导航到现有 Sync 任务进度页；
8. 执行 Repair Initialize；
9. Initialize 成功后执行所有适用的 Gateway 业务恢复任务；
10. 所有任务结束后执行最终收敛检查；
11. 成功时展示 Sync 完成状态；用户返回 Gateway 页面后重新渲染正常详情并加载 Network Connectivity；
12. 失败时保留任务失败状态；用户返回后根据最新 `isKeybindComplete` 决定继续展示 Repair，还是正常详情加 `Devices not synced`。

## 8. 成功语义

### 8.1 Initialize 成功

Repair Initialize 必须同时满足：

- 实际生成的消息列表非空；
- 每条 Config 或读取消息收到匹配的成功业务 Status；
- 动态追加的第二阶段消息全部结束；
- 最终 `node.isKeybindComplete == true`。

只有 Transport ACK、空消息列表、超时、取消、失败 Status 或最终 Key Bind 仍不完整，都视为 Initialize 失败。

### 8.2 Repair 总体成功

Repair 总体成功必须同时满足：

- 所有必要任务无 Failed 或 Skipped；
- `node.isKeybindComplete == true`；
- `node.getNodeSyncGatewayData(gateway:)` 重新计算为空。

任务行全部成功但最终差异仍非空时，Recovery 总体必须转为失败或未完成，不能调用成功回调，也不能显示 Repair 成功提示。

这条规则是“Repair 成功后不再展示 `Devices not synced`”的最终保证。它不通过强行隐藏提示实现，而是收紧 Repair 成功定义。

## 9. 依赖与错误处理

- Initialize 是所有后续任务的关键前置；失败后其余任务标记为 `Skipped`。
- Associated Spaces 失败后，Association Project、Sync Spaces 和 Server Information 仍继续执行。
- 其他独立 Gateway 任务失败后记录失败，并继续执行剩余独立任务。
- Gateway 中途 Offline 时停止当前恢复链，未开始任务标记为 `Skipped`。
- 失败、超时、取消和 Skipped 不写入虚假的成功状态。
- Retry 清除当前失败任务的运行结果和 Skipped 标记，并使用新的运行标识。
- 每次 Recovery 使用独立 operation identifier；旧回调不能更新新运行、弹窗或导航。

## 10. WiFi 请求串行与生命周期

### 10.1 Repair 状态自动请求

当 `node.isKeybindComplete == false` 时，WiFi Gateway 页面不自动发送：

- Credentials Get；
- Connection Status Get；
- RSSI Get。

这样可以避免尚未完成 AppKey/Model Bind 时发送必然失败或可能干扰 Repair 的 Vendor acknowledged 请求。

### 10.2 已存在自动请求

如果页面状态切换前已经发出自动请求：

- 不取消已经发送的 acknowledged 请求；
- 停止安排新的 RSSI Timer；
- 只记录一个 pending Repair；
- 当前请求成功、失败或超时后，Gateway 仍 Online 才继续 Repair；
- 等待期间不堆叠中间成功或失败提示。

### 10.3 页面退出

Repair 不再使用 Window 级无限时 HUD。导航离开 Gateway 或 Sync 页面时：

- 清理 pending Repair；
- 停止页面 Timer；
- 使旧 operation identifier 失效；
- 不让旧回调重新导航或覆盖新页面状态；
- 已发送消息沿用底层结束机制，但结束回调不得更新失效页面。

## 11. UI 规则

- Repair 空状态继续使用现有英文文案 `The device needs to be repaired.` 和 `REPAIR`；
- Repair 状态不展示 SAVE；
- 点击 REPAIR 后进入现有 Sync 任务进度页；
- 不再展示当前 Window 级 `Repairing…` 无限时 HUD；
- Sync 页沿用现有任务成功、失败、Skipped 和 Retry 展示；
- 本设计不新增新的用户可见文案；如果实施时确需新增文案，必须同时补充 English 和简体中文；
- 完整成功后返回 Gateway 页面，正常显示 Name、Network Connectivity、Associated Spaces 和 Server Information，不展示 `Devices not synced`。

## 12. 预计改动边界

### App 代码

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 统一 Repair 与 Gateway Recovery 导航入口；恢复结束后刷新主页面状态。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Repair 状态隐藏 SAVE；阻止 Repair 状态自动 WiFi 请求；成功后重新加载 Network Connectivity。
- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 提供 Repair Composition 阶段和 Composition 后强制基础配置构建能力。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 增加 Repair Initialize 操作类型，并把 `isKeybindComplete` 纳入成功判断。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 增加 Recovery trigger、动态追加 Repair 配置、最终收敛检查和运行标识隔离。

### Contract checks

优先在 `scripts/` 中补充聚焦检查，覆盖：

- Repair 与正常页面底部操作分流；
- Repair 状态不启动 WiFi 自动读取；
- Repair trigger 使用完整 Recovery；
- Composition 后才生成依赖 Models 的强制配置；
- Repair Initialize 要求 `isKeybindComplete`；
- Repair 总成功要求 Gateway 差异为空；
- Recovery 不包含 WiFi Credentials 写入。

### SDK 边界

实现优先复用 App 与 SDK 已公开的 Config 消息和 `MeshProxyMessageCommand` 动态追加能力。只有公开接口无法安全完成 Composition 后动态构建时，才切换工程依赖到本地 NordicSigMeshSDK 并做最小修改；发生该情况时需重新验证所有引用 SDK 的品牌 target。

## 13. 验证设计

### 13.1 状态契约

- Key Bind 不完整：Repair 空状态、REPAIR 可见、SAVE 隐藏、无 WiFi 自动请求；
- Key Bind 完整且差异非空：正常详情、`Devices not synced` 可见；
- Key Bind 完整且差异为空：正常详情、未同步提示隐藏。

### 13.2 Recovery 契约

- 缺少 Composition 时先取得 Composition，再生成强制 Bind；
- Composition 已完整时直接进入强制基础配置；
- Initialize 消息成功但 `isKeybindComplete` 仍为 false 时任务失败；
- Initialize 失败后其余任务 Skipped；
- Associated Spaces 失败不阻止其他独立任务；
- 所有任务成功但最终差异非空时不调用成功回调；
- 重复点击和旧回调不能启动或完成第二条 Recovery；
- Repair 期间不读写 WiFi Credentials。

### 13.3 iPhoneOS 构建

按项目规则直接运行 Debug generic iPhoneOS、关闭签名的构建：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

### 13.4 真机断电矩阵

至少覆盖：

1. `Adding` 刚出现、Provisioning 未完成；
2. Provisioning 完成、Composition 未完成；
3. Composition 完成、AppKey/Model Bind 进行中；
4. Key Bind 完成、Gateway append 进行中；
5. Gateway append 部分完成。

对于 Site 中已经留下 Gateway 的场景，验证：

- 页面进入 Repair 或 `Devices not synced` 的状态符合真实优先级；
- Repair 页面无 SAVE；
- 点击 Repair 只进入一次 Sync 进度页；
- Recovery 可失败、Retry 和退出，不遗留 Window HUD；
- Repair 成功后 `isKeybindComplete == true`；
- Repair 成功返回后 Gateway 差异为空且不展示 `Devices not synced`；
- WiFi Credentials 未被读取后覆盖或重新下发；
- 任一必要任务失败时不提示 Repair 成功。

## 14. 完成标准

本设计完成的判定标准为：

1. Repair 状态不展示 SAVE；
2. Repair 使用现有 Sync 任务进度页和 Gateway Recovery 执行器；
3. 最早可保留 Node 的 Adding 断电窗口能够通过 Repair 初始化恢复 Composition 与 Key Bind；
4. Repair 成功定义同时覆盖基础 Key Bind 与 Gateway 业务差异；
5. Repair 成功返回后不展示 `Devices not synced`；
6. 不出现重复 Repair、不可退出 Window HUD 或旧回调再次导航；
7. 不改变其他设备和其他 Gateway 的 Repair 行为；
8. 四个品牌 target 均通过 iPhoneOS build；
9. 真机断电矩阵有明确验收记录，未执行前不得宣称现场问题已完全修复。
