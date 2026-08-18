# Editor 网关旧名称与 Devices not synced 分析

## 结论

完整响应与 2026-08-18 的在线脱敏复核已经把两个客户端根因确认下来：

1. **旧名称是 Gateway 缺失 `updateTimestamp` 与客户端严格版本门槛共同造成的缓存收敛失败。** 服务端已返回 `Gateway1`，但已有 iPad GatewayModel 不会被替换。
2. **`Devices not synced` 是 Editor 局部 Key 范围与 Gateway 全量 Subnet Index 比较造成的权限范围误判。** 当前 iPad 只拥有 `wifi/index 1`，Gateway 全量配置为 `[1,2]`，当前源码会把局部 `[1]` 与全量 `[1,2]` 比较并生成 Subnet Index 差异。
3. **Reset/重新添加不是上述两个问题成立的必要条件。** 但同 MAC 下若 Node UUID、地址或 Key/Bind 生命周期发生变化，缺失 Gateway 版本会使旧缓存更难被替换，因此会放大问题。
4. **`configComplete=false` 是另一条配置完整性线索，但不是 Name 区域红色提示的直接判断条件。**

服务端日志已经证明当前云端名称为 `Gateway1`。因此不应先把问题归因于 Owner 改名没有上传成功，也不应把 `Devices not synced` 理解为名称不同步提示。

## 日志能直接证明的事实

同一次 iPad Editor 的 `siteInfo` 响应以及在线复核结果为：

| 字段 | 响应值 |
| --- | --- |
| Site role | `editor` |
| 当前返回的 Editor Space | `wifi` |
| Editor Space NetKey/AppKey index | `1` |
| `macAddress` | `D499FFB45841` |
| `name` | `Gateway1` |
| `uuid` | `7C74B610-78FB-4489-838B-49EF87046B76` |
| `unicastAddress` | `0013` |
| `gatewayInfo.projectId` | `BBEE852F-DFC0-41C1-AFB3-C28BF17633EE` |
| `gatewayInfo.subnetAppkeyIndexs` | `[1, 2]` |
| `gatewayPreconfigured.associatedSpaces` | Space 1/index 2、wifi/index 1 |
| Gateway `updateTimestamp` | 缺失 |
| `netKeys` / `appKeys` | `[0, 1, 2]` |
| `gatewayOnline` | `true` |
| `configComplete` | `false` |

响应中的 Gateway 对象已经闭合，在线请求也确认 `hasUpdateTimestamp=false`；对象中只有 Mesh Node 时间字段 `timestamp`。这两个字段语义不同，`timestamp` 不能替代 GatewayModel 的云端更新版本。

还需要修正最初场景描述中的一个事实：按服务器当前权限数据，iPad 用户作为 Editor 获得的是 `wifi`，不是 `Space 1`。`Space 1/index 2` 仍在 Gateway 的全量关联列表中，但没有出现在该 Editor 的 `spaces` 数组里，也没有向该 Editor 返回 index 2 的 NetKey/AppKey 密钥材料。

Space 日志只说明 `wifi` 的 `serverUpdateTimestamp == localLastUpdate`，因此 Space 数据被跳过。它不能证明 Gateway 数据已导入，因为 Gateway 有独立的版本判断链路。

## 旧名称为什么仍显示为 Gateway111

### 页面不直接显示本次 HTTP JSON

Gateway 详情页初始化时接收运行期聚合对象 `Gateway`，其中包含本地持久化的 `GatewayModel` 和本地 Mesh `Node`。页面标题和名称输入值都直接取 `gatewayModel.name`。

因此，即使网络日志里已经出现 `name=Gateway1`，只要本地 GatewayModel 没有被替换，页面仍会稳定显示旧的 `Gateway111`。

关键源码位置：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:142-173`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:1415-1453`

### Gateway 导入被独立版本门槛拦住

Site 导入 Gateway 时按 MAC 找本地缓存，再读取每个 Gateway 对象的 `updateTimestamp`。只有以下任一条件成立才导入服务器 Node 和 GatewayModel：

- 本地没有该 MAC 的 GatewayModel；
- 服务端 Gateway `updateTimestamp` 大于本地 `GatewayModel.lastUpdate`。

如果字段缺失，当前实现把服务端版本当作 `0`。首次导入时因为本地没有记录，仍可保存 `Gateway111`；之后即使服务器名称变成 `Gateway1`，服务端版本仍为 `0`，本地版本也是 `0` 或更大，`serverUpdate > cacheUpdate` 不成立，新的名称、Node、地址和 GatewayInfo 会整体跳过。

关键源码位置：

- `SunSmart/Common/Data/ImportData.swift:516-567`
- `SunSmart/Common/Data/ImportData.swift:591-596`

这与现场现象完全吻合：HTTP 响应是新名称，导入完成后 UI 仍是旧名称。

### Owner 改名链路本身已经有云端结果

Owner 保存名称后，本地会同步更新 GatewayModel 与 Node name，并通过 Site 的 Gateway 数据变更通知推进 `GatewayModel.lastUpdate`，随后排队 Gateway Register 云端同步。

本次 Editor 的响应已经读到 `Gateway1`，说明至少服务器当前快照已经是新名称。问题发生在 Editor 把服务器快照落入本地缓存的阶段。

关键源码位置：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:846-902`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:401-415`

## Devices not synced 为什么出现

### 它不比较名称

Name 区域是否显示 `Devices not synced`，只取决于 `node.getNodeSyncGatewayData(gateway:)` 是否非空。该差异函数不比较 `GatewayModel.name` 与 `Node.name`。

它比较的是：

- Gateway Project ID；
- Associated Space 的 NetKey、AppKey 与 Model App Bind；
- Gateway 当前多出来、需要解绑的 secondary Key；
- Vendor Subnet AppKey Index 列表；
- 4G APN；
- MQTT Server 信息。

因此 `Gateway111` 对 `Gateway1` 本身不会触发该红色提示。

关键源码位置：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:2246-2259`
- `SunSmart/Common/Data/Node+SyncData.swift:1705-1781`

### 已确认的权限裁剪误判

当前远端 Gateway 关联两个子网，`subnetAppkeyIndexs=[1,2]`。iPad 响应中只有 `wifi/index 1`，没有 `Space 1/index 2` 的 Space 数据及 Key 材料。

Site 初始化会把顶层 Primary Key/index 0 和 Editor Space Key/index 1 加入 iPad MeshNetwork。Gateway Node JSON 虽然声明它认识 indexes `[0,1,2]`，但 `Node.applicationKeys` 不是直接返回 JSON 中的 index 数组，而是从当前 MeshNetwork 的完整 ApplicationKey 对象中解析“该 Node 认识的 Key”。由于 iPad 没有 index 2 的完整 ApplicationKey，最终可解析集合只能是 `[0,1]`。

差异计算过滤掉 Primary Key 后得到 `currentAppkeyIndexs=[1]`，再与 GatewayInfo 的全量 `[1,2]` 比较，确定会生成 `syncGatewaySubnetAppkeyIndexs([1])`，从而显示 `Devices not synced`。

这不是 Gateway 真实配置缺少 index 2。恰恰相反，同一响应已经显示 Gateway 的 NetKey/AppKey、Time、Time Setup、Vendor Model Bind 与 `gatewayInfo.subnetAppkeyIndexs` 都包含 index 2。红色提示来自客户端把 Editor 的局部可见集合误当成 Gateway 的全量期望集合。

这条路径还有权限风险：如果后续恢复流程使用 `[1]` 覆盖 Gateway 全量 `[1,2]`，可能误移除 Editor 无权管理的 `Space 1/index 2`。当前专用 Gateway Recovery 构建器还要求所有 `associatedSpaces` 都能解析到完整 Key；Editor 缺少 index 2 时可能直接无法构建恢复对象。后续修复必须先定义权限范围，不能简单让 Editor 的局部 Key 集合覆盖 Gateway 的全量 Subnet Index。

相关源码位置：

- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift:268-288`
- `SunSmart/Common/Data/Node+SyncData.swift:1722-1765`

### 旧 Node / GatewayModel 配对也会产生真实差异

如果 Gateway 在 Owner 手机上经历过 Reset 和重新添加，同一物理 MAC 可能对应新的 Node UUID、Unicast Address 或重新生成的 Key/Bind 状态。当前 GatewayModel 数据库以 `siteId + MAC` 唯一标识 Gateway，而远端替换仍受 `updateTimestamp` 门槛控制。

如果门槛没有通过，iPad 可能继续使用旧地址指向的 Node，或使用旧 GatewayModel 配上后来被其他导入路径更新过的 Node。此时以下任一差异都会触发提示：

- 旧 `gatewayInfo.projectId` 与当前 Site ID 不一致；
- Node 中的 secondary NetKey/AppKey/Model Bind 与旧 associatedSpaces 不一致；
- Node 的 `subnetAppkeyIndexs` 与本地可见 AppKey indexes 不一致；
- 旧 MQTT 信息与 GatewayModel 中的服务器目标不一致。

所以 Reset/重新添加不是旧名称问题成立的必要条件，但它会显著提高“同 MAC、不同 Node 生命周期未正确替换”的概率。

### `configComplete=false` 的边界

响应中 `configComplete=false` 说明服务器快照认为该 Node 的通用配置未完成，和重置/重新添加背景相符。但当前 `Devices not synced` 的显示条件没有直接读取 `configComplete` 或 `isKeybindComplete`，因此不能仅凭这个字段断言红色提示的具体差异类型。

即使不新增日志，按该完整响应建立的新鲜 Editor 本地网络，也能确定产生 `syncGatewaySubnetAppkeyIndexs([1])`。旧 iPad 缓存还可能叠加 Project ID、Associated Space 或 MQTT 等其他差异；如需确认是否存在叠加项，再输出具体枚举类型即可。

## 推荐的最小确认数据

下一轮复现只需在 iPad Site 导入和 Gateway 页面各记录一次以下数据，不需要先改业务行为：

### Site Gateway 导入前后

- 远端：MAC、name、UUID、unicastAddress、`updateTimestamp` 是否存在及原始类型、`timestamp`。
- 本地导入前：GatewayModel name、address、lastUpdate、lastUploadCloudTimestamp。
- 导入决策：serverUpdate、cacheUpdate、shouldReplace、跳过原因。
- 导入后：最终 GatewayModel name/address，以及 resolve 到的 Node UUID/name/address。

### Editor 权限与 Key 范围

- iPad 实际收到的 Spaces、每个 Space role、gatewayId、NetKey index、AppKey index。
- 当前 MeshNetwork 的全部可见 NetKey/AppKey indexes。
- 目标 Node 的 known NetKey/AppKey indexes。
- GatewayModel associatedSpaces 的 spaceId/appKeyIndex/permission。
- GatewayInfo subnetAppkeyIndexs。

### 未同步差异类型

输出 `getNodeSyncGatewayData` 的类型，不输出 Key、密码或 Auth 内容。重点确认是否为：

- `syncGatewayProjectId`
- `gatewayAssociatedSpaces`
- `gatewayUnbindAssociatedSpaces`
- `syncGatewaySubnetAppkeyIndexs`
- `syncGatewayMQTTInformation`

## 快速判别实验

1. 在 iPad 清除该 Site 的本地缓存后重新接受分享，或用全新安装的受控测试机进入同一 Site。
2. 如果名称立即变为 `Gateway1`，可直接证明旧名称来自本地缓存替换门槛，而不是服务器改名失败。
3. 新安装仍应显示 `Devices not synced`；若差异类型只有 `syncGatewaySubnetAppkeyIndexs([1])`，即与本次源码推导完全一致。
4. 如果新安装不再显示提示，旧 iPad 输出的 Node UUID/address 又与响应不同，则 Reset/重新添加遗留旧生命周期是主要放大因素。

清缓存只能作为诊断实验，不是产品修复方案；执行前需确认测试账号和数据可重新恢复。

## 后续修复方向

### 方向 A：修正 Gateway 云端版本契约

优先让 `/sitespace/get/siteprops` 中每个 Gateway 始终返回可比较、单调推进的 `updateTimestamp`，并确保 Rename、Reset、Delete/Re-add、Associated Spaces 和 Gateway Register 都推进该版本。

客户端同时应对缺失/相等版本增加安全收敛规则：只有本地 Gateway 不处于 dirty/uploading 状态时，才允许根据服务器稳定身份与内容差异更新；若 MAC 相同但 UUID/address 已变化，应按新 Node 生命周期处理，不能继续沿用旧地址。

不能直接用 Node `timestamp` 代替，因为它是 Mesh 时间字段，不是 Gateway 云端修改版本。

### 方向 B：修正 Editor 的 Gateway 配置比较范围

将“Gateway 全量真实配置”与“Editor 被授权看到和修改的 Space 切片”分开：

- Owner 可比较和恢复全部关联 Space；
- Editor 只能比较被分享的关联 Space；
- 未授权 Space 的 Subnet Index 必须作为不可见但需保留的 opaque state，不能因本地缺 Key 被判为待删除；
- Editor 的 Subnet Index 目标不能直接取 `node.applicationKeys`；至少需要保留 GatewayInfo 中不属于当前 Editor 授权范围的既有 indexes；
- Authorized index 1 可做完整 Key/Bind 检查，opaque index 2 只能保持，不得由 Editor 增删；
- 如果恢复流程必须掌握全量 Key 才能保证安全，应限制为 Owner 执行，而不是让 Editor 用局部状态覆盖全量配置。

### 方向 C：增加 Reset/Re-add 生命周期防御

同 Site、同 MAC 的远端 Gateway 若 UUID 或地址改变，应显式清理旧 Node 引用并绑定新 Node；同时验证旧 GatewayModel 的 name、associatedSpaces、GatewayInfo 与上传 generation 不会跨生命周期误复用。

## 当前证据边界

本分析已经从日志和当前源码证明：

- 服务器响应名称是 `Gateway1`；
- UI 名称来自本地 GatewayModel，而非直接来自响应；
- Gateway 导入依赖网关级 `updateTimestamp` 严格递增；
- `Devices not synced` 不比较名称；
- 当前服务器 Gateway 对象确实缺少 `updateTimestamp`；
- 当前 Editor 只获得 `wifi/index 1`，Gateway 全量 Subnet Index 为 `[1,2]`；
- 当前差异算法会由此生成 `syncGatewaySubnetAppkeyIndexs([1])`；
- Reset/Re-add 在同 MAC 下可能放大旧 Node 生命周期残留。

尚未由现有日志证明：

- iPad 本地 GatewayModel 的实际 lastUpdate/address/UUID；
- 旧 iPad 上是否除 `syncGatewaySubnetAppkeyIndexs([1])` 外还叠加其他差异；
- Gateway 固件当前持久化的真实 Key/Bind/MQTT 状态。

因此两个主要现象均已定案。额外差异日志只用于判断 Reset/旧缓存是否叠加了更多问题，不再影响本次两个主根因的成立。

## 接口安全附带发现

当前执行环境不携带 Authorization、Cookie 或请求签名，只提交 Site ID 与 User ID，也能从该接口获得完整 Site 数据。原始响应包含 Mesh Key、Device Key 和 MQTT 凭据等敏感信息。

如果服务器上游没有可信 IP 白名单、mTLS 或等价的访问控制，这属于高风险越权读取边界：知道或猜到 Site ID 与 User ID 的调用方可能读取设备控制密钥。应立即由服务器团队确认入口层鉴权；如当前确实对公网开放且无其他保护，应撤销暴露凭据、轮换相关 Mesh/MQTT 密钥，并避免继续在日志和文档中保存明文。
