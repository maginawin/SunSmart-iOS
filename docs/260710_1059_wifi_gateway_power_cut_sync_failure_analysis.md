# WiFi Gateway 添加中断电后的权限与同步失败分析

## 1. 问题范围

- 设备：WiFi Gateway，CID `0x0A78`，PID `0x2721`。
- 操作：在 Site 页面添加设备；Adding 阶段等待数秒后断电；设备再次上电并以 BLE Mesh Proxy 连接。
- 现象：
  - Gateway 页面显示 `Devices not synced`。
  - 未关联 Space 时点击该入口提示 `No permission!`。
  - 关联一个 Editor Space 后可以进入 `Sync device(s)`，但 `Association Project`、`Associated Spaces`、`Sync Spaces`、`Server Information` 失败。
- 分析依据：当前 App / 本地 NordicSigMeshSDK 源码，以及 `gateway sync log.md`。
- 本文只分析问题，不修改业务代码。

## 2. 结论摘要

本次现象不是一个单点问题，而是三个问题叠加：

1. `No permission!` 是确定存在的页面权限判断错误，与 Gateway 的 BLE Online 状态、断电或设备配置完整度无直接关系。
2. 添加中断电确实可能留下“App 已保存并视为添加成功，但设备配置未完成或未持久化”的半完成 Gateway。当前 Fast Add 的成功语义允许这种状态存在。
3. 当前 Log 证明 BLE/GATT、Proxy、Network Key 和 Device Key 通路正常，但所有依赖 `MainApplicationKey` 的 Vendor 消息没有收到 Access 层业务响应。最高概率原因是 App 本地缓存的 AppKey / Vendor Model bind 状态与设备实际状态不一致。
4. 进入 WiFi Gateway 页面后自动读取 Wi-Fi credentials，与随后启动的 Sync 同时向同一节点发送 acknowledged Vendor 消息。Log 已出现 Swift continuation leak，说明这里还有独立的并发/回调覆盖风险，会污染任务的 timeout / cancelled 归属并放大失败。

因此，用户关于“添加过程中断电，后续没有继续完成配置”的怀疑基本成立，但更准确的表述是：

> Provisioning 已完成并已落本地模型；Key Bind、Vendor Model 配置或 Gateway 附加配置没有形成可靠的设备侧持久化确认，而 Fast Add 仍把该节点保留为添加成功。之后重同步依据本地缓存判断设备已完成 Key Bind，没有先修复真实设备侧 AppKey / Model bind，导致所有 Gateway Vendor 任务继续超时。

## 3. `No permission!` 的直接原因

### 3.1 当前点击条件

Gateway 页面只有在 `getNodeSyncGatewayData` 非空时展示 `Devices not synced`。点击该入口时，代码同时要求：

- Site 的 effective capability 包含 edit；
- Gateway 至少有一个 permission 为 Editor 的 Associated Space。

当 Associated Spaces 为空时，第二个条件恒为 false，因此即使当前用户是 Site Owner、Site 具备 edit 能力，也会提示 `No permission!`。

代码位置：

- 展示 `Devices not synced`：`GatewayViewController.swift:1143-1156`
- 点击权限判断：`GatewayViewController.swift:1211-1222`

### 3.2 为什么添加 Associated Space 后不再提示

添加的 Space permission 为 Editor 后，`contains(Editor)` 变为 true，点击条件通过。这与 Gateway 是否完成设备配置无关，只是刚好满足了页面写死的第二个条件。

### 3.3 同文件中的反例

Gateway SAVE 已采用更合理的判断：Associated Spaces 为空可以保存；非空时才要求至少有一个 Editor Space。位置为 `GatewayViewController.swift:483-490`。

因此，`Devices not synced` 的点击判断与同页面 SAVE 的权限语义不一致。这里可以确认是 App 侧逻辑问题，而不是设备返回 `No permission`。

## 4. 添加过程中为什么可能留下半完成设备

### 4.1 Provisioning 完成时已提前持久化

Fast Add 的 Provisioning complete 后，SDK 已将 Node 写入本地；App 的 `provisionCompleteCallback` 随即保存 Node，并创建、保存 `GatewayModel`。

位置：

- SDK 保存已 provision 的 Node：`MeshFastAddDeviceManager.swift:1209-1225`
- App 保存 Node / GatewayModel：`SiteDeviceAddViewController.swift:476-500`

这一步发生在 Key Bind 和 Gateway 附加配置完成之前，所以此后断电并不会自动撤销本地 Gateway。

### 4.2 Fast Add 默认不强制 Key Bind 完成

Site 添加入口调用 `startFastAddDevices` 时没有传 `mustKeybindFinish`；SDK 默认值为 false。

SDK 在节点已入网的情况下，即使后续发生 disconnect / config failure，只要不是被特殊标记的强制配置设备，也会回调 `deviceAddSuccessBack`，而不是删除节点或回调添加失败。

位置：

- App 调用入口：`SiteDeviceAddViewController.swift:468`
- SDK 默认值：`MeshFastAddDeviceManager.swift:82-92`
- 已入网但配置失败仍回调成功：`MeshFastAddDeviceManager.swift:833-874`

### 4.3 Gateway 附加任务失败也不会阻止最终成功

Key Bind 完成后，App 组装 Gateway 的 Project、Subnet、MQTT 等附加消息。SDK 对默认 continuous 的附加消息采用“当前失败后继续”；队列耗尽后仍进入添加成功。

位置：

- 组装 Gateway 附加消息：`SiteDeviceAddViewController.swift:503-547`
- 附加消息失败后继续：`MeshFastAddDeviceManager.swift:895-909`

所以即使断电发生在 Gateway 专有配置阶段，仍可能看到设备最终留在 Site 中，随后由 `Devices not synced` 补偿提示暴露未完成状态。

### 4.4 断电窗口存在缓存与设备持久化分裂风险

SDK 已在 Key Bind 的 bearer 异常断开分支中明确注释：配置过程断开可能造成最近数据未写入设备，并主动清除本地 current AppKey / model bind 缓存。

位置：`MeshFastAddDeviceManager.swift:1136-1155`。

但该保护仅在 `addStep == keybind` 时执行。如果断电发生在：

- App 已收到配置 Status 并更新本地缓存之后；或
- SDK 已从 keybind 切换到 `sendAppendMessages` 之后；或
- 设备已应答但尚未把配置可靠写入非易失存储；

则本地仍可能认为 Key Bind 已完成，而设备重启后实际缺少对应 AppKey 或 Model bind。

这与本次后续 Log 的表现高度一致。

## 5. Log 证明了什么

### 5.1 云端 Associated Space 查询正常

Log 1-20 行显示 Associated Space 列表接口 HTTP 200、业务码 200，并返回一个带 AppKey index 的 Space。因此当前同步失败不是由该查询接口失败直接造成。

### 5.2 BLE/GATT 和 Proxy 在线正常

Log 23-54 行显示：

- BLE connected；
- services / characteristics discovery 成功；
- notifications enabled；
- GATT bearer ready；
- Secure Network Beacon 可认证；
- Proxy filter 配置成功。

所以 UI 中 BLE Online 是真实的，但它只证明 Proxy 和 Network 层可用。

### 5.3 Device Key 配置消息可正常往返

Log 56-67 行的 `ConfigDefaultTtlGet` 使用 Gateway Device Key，收到 `ConfigDefaultTtlStatus(ttl: 7)`。

这证明：

- 节点地址 `0x0072` 可达；
- Primary Network Key 路径可用；
- Device Key 正确；
- 设备能够处理标准 Config Server 消息。

因此不能把本次失败归因于“设备完全离线”“Proxy 不通”或“Node 地址错误”。

### 5.4 所有 MainApplicationKey Vendor 消息无业务响应

进入页面后，App 先发送 Wi-Fi credentials Get；随后同步任务发送 Project、Subnet relevance 和 MQTT 信息。Log 中这些消息均使用 `MainApplicationKey (index: 0)`。

Project 与 MQTT 这两条长分段消息都收到了完整 Transport ACK。这只证明设备收到了并重组了 Upper Transport PDU，不代表设备已成功解密 AppKey、找到绑定的 Vendor Model 并执行命令。`43 05` Sync Spaces 是短消息，不需要分段 Transport ACK；Log 仅看到发送/重发，同样没有业务响应。

整个 Log 没有看到对应的 `SunricherVendorStatus` Access PDU，最终均为 timeout / cancelled。因此失败层级位于 Transport ACK 之后、Vendor Access response 之前。

最高概率边界是：

- 设备侧没有持久化 MainApplicationKey；或
- MainApplicationKey 存在，但没有绑定到 Sunricher Vendor Model；或
- App 本地 model.bind 记录与设备实际 bind 不一致。

### 5.5 当前重同步没有先做 Initialize

`getSyncData(.all)` 只有在本地 `node.isKeybindComplete == false` 时才生成 `Initialize`。本次用户看到的是四个 Gateway 任务，Log 也没有 `ConfigAppKeyAdd` / 主 Vendor Model 的 `ConfigModelAppBind`，而是直接用 MainApplicationKey 发送 Vendor 命令。

这说明当前 App 本地缓存很可能认为 Key Bind 已完成。结合设备端不回任何 MainApplicationKey Vendor Status，支持“本地缓存与设备真实状态分裂”的判断。

## 6. 四项任务为何出现、为何失败

Gateway 同步任务由 `getNodeSyncGatewayData` 比较期望模型与 `node.gatewayInfo` / key bind 缓存生成：`Node+SyncData.swift:1665-1740`。

| UI 任务 | 生成原因 | 主要消息 | 本次表现 |
| --- | --- | --- | --- |
| Association Project | 本地 Gateway siteId 与 `gatewayInfo.projectId` 不同或后者为空 | Gateway Vendor `43 04` | 分段 Transport ACK 完整，但无 Vendor Status |
| Associated Spaces | 对应子网 NetKey/AppKey 或 Gateway 相关 Model bind 不完整 | Config NetKey/AppKey/Model bind，必要时附加 `43 0B` | UI 失败；当前截取 Log 中未看到该任务独立的 Config 消息，可能为空 handle 后状态校验失败，或受前后任务/缓存状态影响 |
| Sync Spaces | 当前 secondary AppKey index 列表与 `gatewayInfo.subnetAppkeyIndexs` 不同 | Gateway Vendor `43 05` | 无 Vendor Status |
| Server Information | 服务器 MQTT 信息与 `gatewayInfo.mqttConnectInfo` 不同或后者为空 | Gateway Vendor `43 02` | 长分段 Transport ACK 完整，但无 Vendor Status |

这些任务持续出现，是因为只有成功响应后 App 才会更新对应 `gatewayInfo` / key 缓存；当前无业务响应，所以差异始终存在，`Devices not synced` 不会消失。

## 7. 独立存在的同步并发问题

### 7.1 Log 中的重叠

- Log 68-78 行：页面自动发送 Wi-Fi credentials Get `43 12`，并已进入重发。
- Log 79-88 行：用户在该请求仍未完成时进入 Sync 并启动 Project Set。
- Log 89 行立即出现 `SWIFT TASK CONTINUATION MISUSE`。
- 后续可见 credentials Get、Project Set、Subnet Set、MQTT Set 的发送、重发、timeout 交错；打印的“失败 message”与紧邻 timeout 的 payload 也出现错位。

### 7.2 代码原因

WiFi 页面在 Proxy Online 后自动调用 `loadNetworkConnectivityFromGateway`，异步发送 credentials Get；但 `Devices not synced` 的点击门槛只检查 parent controller 的 Proxy `isConnecting`，没有检查 Wi-Fi credentials 请求是否仍在进行。

另外，SDK callback 发送接口会按 response opcode + source 取消旧的 notify callback，再登记新 callback；NetworkManager 的 acknowledged response continuation 又以 destination 为 key。对同一节点并发发送多条 Vendor acknowledged 消息时存在 callback 覆盖/取消风险。

位置：

- 自动 credentials Get：`WiFiGatewayViewController.swift:262-327`
- 点击只检查 Proxy `isConnecting`：`GatewayViewController.swift:1211-1215`
- SDK callback 注册/取消：`MeshAPI.swift:1255-1272`
- NetworkManager destination callback：`NetworkManager.swift:242-266`

### 7.3 对本次结论的影响

并发问题会让某个请求的 timeout 取消或完成另一个请求，导致 UI 任务失败归属不可靠，也解释 continuation leak。

但它不是唯一根因：credentials Get 在 Sync 开始前已经重发，并且整段 Log 从未出现任何 Vendor Access Status。即使去掉并发，本次设备的 MainApplicationKey / Vendor Model 通路仍然高度可疑。

## 8. 根因分级

### 已确认

1. 空 Associated Spaces 被点击逻辑错误地当成无权限。
2. Provisioning 完成后 Node / GatewayModel 已持久化，早于 Key Bind 和 Gateway 附加配置完成。
3. Fast Add 默认不强制 Key Bind 完成，已入网节点的后续失败可以被回调为添加成功。
4. BLE Proxy 和 Device Key 通路正常；MainApplicationKey Vendor 通路无业务响应。
5. 页面自动 Wi-Fi credentials Get 与 Sync 存在并发，且本次已触发 continuation leak。

### 高概率根因

1. 断电导致设备实际 MainApplicationKey 或 Sunricher Vendor Model bind 未持久化/丢失，而 App 本地缓存仍认为已完成。
2. 详情页的补偿同步只依据本地 `isKeybindComplete` 决定是否生成 Initialize，无法发现“缓存为 complete、设备实际 incomplete”的分裂状态。

### 中概率放大因素

1. 断电发生在 Key Bind 刚应答或刚进入 Gateway append 阶段，越过了 SDK 仅针对 `addStep == keybind` 的缓存清理保护。
2. 自动 Wi-Fi GET 与 Sync 的 callback / destination 冲突，使多个 Vendor 任务相互取消或错误归因。

### 当前证据不支持

1. Gateway BLE Offline。
2. Proxy filter 未配置成功。
3. Device Key 错误。
4. Associated Space 查询接口失败。
5. 单纯某一个 Project / MQTT payload 格式错误。因为多个不同 subcode 的 Vendor 请求全部无 Access response，更符合共同的 AppKey / Model bind 层问题。

## 9. 建议的下一轮验证

下一步应先验证根因，不建议直接改四个业务 task：

1. 使用 Device Key 单独读取设备真实 AppKey 列表及 Sunricher Vendor Model 的 AppKey bind，和 App 本地 `node.applicationKeys`、`vendorModel.bind` 对比。
2. 在不触发 Wi-Fi credentials 自动 Get 的条件下，串行发送一个旧 Gateway Vendor 命令并等待 Status，确认 MainApplicationKey Vendor 通路是否恢复。
3. 若设备侧缺少 AppKey / bind，先完整执行一次 Node Initialize / Key Bind，再串行执行四个 Gateway 任务；若随后成功，即可确认根因。
4. 分别在 Provisioning、Key Bind、Gateway append 三个阶段断电，记录 `addStep`、每条 Config Status、设备断开时机和最终 `isKeybindComplete`，找出产生“本地 complete、设备 incomplete”的精确窗口。
5. 单独复现页面并发：等待 credentials Get 完成后再 Sync，与立即 Sync 对比，确认 continuation leak 和任务错位是否消失。

## 10. 最终判断

本次问题真实存在，并且用户的方向基本正确。最核心的设备侧问题不是 Gateway 的某一个业务 model 值没有设置，而是添加成功边界过早，使 App 能保存并展示一个尚未可靠完成 Key Bind / Vendor 配置的 Gateway；断电后又缺少基于设备真实配置的恢复校验。

同时必须把两个 App 侧问题分开处理：

- `No permission!` 是空 Associated Spaces 的权限条件错误；
- 四项 Sync 失败的直接表现是 MainApplicationKey Vendor Access 无响应，并被 Wi-Fi 自动读取与 Sync 的并发进一步放大。

在读取设备真实 AppKey / Model bind 前，不能把根因百分之百定为“设备未持久化 MainApplicationKey”，但当前日志与代码证据对这一假设的支持度最高。
