# Site Gateway 孤儿关联客户端防御设计

## 背景

`siteInfo` 可能返回内部不一致的完整 Site 快照：

- 顶层 `gateways` 不包含任何 Gateway。
- Space 仍携带非空 `gatewayId`、`gatewayOnline` 和
  `gatewayLastupdate`。

当前 `SpaceData` 独立导入这些字段，Site 概览和 Space 卡片又直接消费
`SpaceData.gatewayStatus`，所以孤儿 `gatewayId` 会被展示为真实 Internet
online/offline 状态。

此前已确定服务器 `gatewayOnline` 是 Site Internet 状态真值，本地
`GatewayModel`、Mesh 当前网络和 `Node.state` 不能反向覆盖它。本设计需要在
不破坏该约束的前提下，拒绝完整服务器快照中的孤儿关联。

## 目标

1. owner 收到完整且格式有效的 `siteInfo.gateways` 快照时，只有存在于该
   Gateway 集合中的 `Space.gatewayId` 才视为有效关联。
2. 顶层 `gateways = []` 且 Space 残留 `gatewayId` 时，将该 Space 归一为
   `.notBound`。
3. Gateway 存在于顶层列表、但本地 Node 暂时无法解析时，继续保留服务器
   `gatewayOnline`，避免重新引入 false offline/notBound。
4. 快照不完整、格式异常或权限可能导致 Gateway 列表裁剪时，采取保守策略，
   不清理 Space 状态。
5. All Spaces、Favourites、Space 卡片、Add Gateway 权限和 Associated Spaces
   候选共享同一个归一化后的 `SpaceData` 状态。

## 非目标

- 不修复服务器数据库、缓存或 Gateway 删除事务。
- 不修改 Gateway bind、unbind、delete API 或请求顺序。
- 不使用本地 `GatewayModel`、Mesh Node 或 `Node.state` 推断服务器关联。
- 不新增 unknown/stale UI、用户提示或本地化文案。
- 不修改 Wi-Fi/4G Gateway 协议。
- 不为 editor/visitor 猜测顶层 `gateways` 是否完整。

## 方案比较

### 方案 A：在 `SiteData.update` 中归一化完整服务器快照

从同一次 `siteInfo` 的顶层 `gateways` 提取服务器 Gateway ID 集合，完成 Space
导入后，对本次响应中的 Space 进行关联一致性判定。

优点：

- 在数据源入口消除矛盾，所有下游页面和权限判断自然一致。
- 直接比较同一个服务器响应中的两部分数据，不依赖本地 Mesh 状态。
- 可以通过纯 Swift policy 覆盖边界条件。
- 不需要在多个 UI 消费点重复过滤。

缺点：

- 需要明确什么情况下顶层 Gateway 列表可视为完整快照。
- 归一化发生在 Space 导入后，需要保存被清理的本地 Space 状态。

### 方案 B：只在 Site UI 统计和 Space 卡片中过滤

Site 页面展示前，用可见 Gateway 列表过滤 Space 状态。

优点：

- 表面改动较小。

缺点：

- `Add Gateway`、Associated Spaces 和其他消费者仍会读取脏
  `relevanceGatewayId`。
- 如果使用本地 `showGatewayModels`，会重新受到主网快照或 Node 解析失败影响。
- 同一 Space 在不同页面可能显示不同状态。

该方案不采用。

### 方案 C：Gateway 删除前逐个解绑 Space

客户端在 `gatewayDelete` 前依次调用 `gatewayUnbindSpace`。

优点：

- 可以减少由当前 App 删除 Gateway 产生的残留关联。

缺点：

- 不能处理历史脏数据、其他客户端、后台操作或服务端缓存异常。
- 新增部分解绑成功、部分失败的事务状态。
- 不构成对矛盾 `siteInfo` 的通用防御。

该方案可作为服务端删除流程修复的补充评估，但不属于本次客户端防御。

## 采用方案

采用方案 A。

### 权威快照定义

只有同时满足以下条件，顶层 Gateway 列表才可用于强校验：

1. Site 顶层 `role == owner`。
2. `gateways` 字段存在且可以解析为数组。
3. 数组中的每个元素都包含非空 `macAddress`。

空数组是有效的权威快照，表示服务器确认当前 Site 没有 Gateway。

以下情况均视为非权威快照：

- editor 或 visitor。
- `gateways` 缺失、不是数组或解析失败。
- 任一 Gateway 项缺少有效 `macAddress`。

非权威快照只保留 Space 原始服务器状态，不执行清理。

### ID 归一化

Gateway ID 比较规则：

1. 去除首尾空白。
2. 转为小写。
3. 不主动删除冒号、连字符或其他字符，避免引入未经协议确认的等价规则。

顶层 `macAddress` 与 Space `gatewayId` 使用相同规则。

### Space 决策

对于本次 `siteInfo.spaces` 返回的每个 Space：

| 条件 | 决策 |
| --- | --- |
| Space `gatewayId` 缺失或为空 | 保持现有 `.notBound` 导入结果 |
| Gateway 快照非权威 | 保留 Space 的服务器关联和 online/offline |
| Gateway 快照权威且包含 Space `gatewayId` | 保留服务器 `gatewayOnline` |
| Gateway 快照权威但不包含 Space `gatewayId` | 清理为 `.notBound` |

清理孤儿关联时同时设置：

- `relevanceGatewayId = nil`
- `gatewayStatus = .notBound`
- `gatewayLastOnline = nil`

随后保存该 Space 的本地数据库状态，但不触发 Space 云同步，不把本地防御结果
回写服务器。

### 诊断

DEBUG 构建记录一条结构化日志，包含：

- siteId
- spaceId
- orphanGatewayId
- snapshot scope

日志不得包含 AppKey、NetKey、Auth 或其他密钥。

## 组件边界

### `SiteGatewayAssociationConsistencyPolicy`

新增纯 Swift policy，不依赖 UIKit、数据库或 NordicSigMeshSDK。

职责：

- 构造权威或非权威 Gateway 快照。
- 统一规范化 Gateway ID。
- 对 Space Gateway ID 返回 `.preserve` 或 `.clearOrphan`。

### `SiteData.update`

继续负责完整 Site 快照导入，并新增以下编排：

1. 在导入 Space 前读取本次响应的 Gateway 字典数组。
2. 根据 Site 权限和 Gateway 数组完整性创建 consistency snapshot。
3. 并发导入本次服务器返回的 Space。
4. 只对本次响应中的 Space 应用 policy。
5. 清理孤儿关联、保存 Space 并输出 DEBUG 诊断。
6. 继续执行现有 Space 合并和 Gateway 导入。

### Site UI

`SiteViewController` 和 `SpacesViewCell` 不增加第二套过滤逻辑。

它们继续消费归一化后的 `SpaceData.gatewayStatus`。`setupData()` 继续禁止根据
本地 Gateway 或 Node 状态修改 Space Internet 状态。

## 数据流

正常 Gateway：

`siteInfo.gateways + siteInfo.spaces`
→ 权威 ID 快照命中
→ 保留 `gatewayOnline`
→ Site Internet 概览与 Space 图标

孤儿 Gateway：

`siteInfo.gateways = [] + Space.gatewayId != nil`
→ 权威 ID 快照未命中
→ 清理为 `.notBound`
→ `Internet Online: 0 / No Gateway: 2`

本地 Node 暂时不可解析：

`siteInfo.gateways` 包含 Gateway
→ 权威 ID 快照命中
→ 保留服务器 online/offline
→ 本地 Node 解析失败只限制 Gateway 操作，不改变 Site Internet 展示

## 错误与保守策略

- Gateway 数组格式异常：不清理任何 Space，记录为非权威快照。
- editor/visitor：不清理，等待服务器接口完整性契约确认。
- Space 保存失败：保留内存归一化结果供当前页面使用，并输出 DEBUG 诊断；
  下一次权威 `siteInfo` 会再次执行归一化。
- `spaceInfo` 单独响应不包含顶层 Gateway 列表：不执行本规则，避免凭旧快照清理。

## 测试设计

### Policy 单元测试

1. owner 完整空 Gateway 数组 + Space 孤儿 ID → `.clearOrphan`。
2. owner 完整数组包含匹配 ID → `.preserve`。
3. Gateway ID 大小写和首尾空白不同 → `.preserve`。
4. editor/visitor 等非完整 scope + 空数组 → `.preserve`。
5. Gateway 数组缺失 → `.preserve`。
6. Gateway 数组含无效 `macAddress` → 整个快照非权威并 `.preserve`。
7. Space 没有 Gateway ID → `.preserve`。

### 导入契约测试

1. `SiteData.update` 使用同一次响应的 `gateways` 构造 policy snapshot。
2. 只对 owner 完整快照启用强校验。
3. `.clearOrphan` 同时清理三个 Space 字段并保存。
4. `SiteViewController.setupData()` 仍不得写 `space.gatewayStatus`。
5. 防御链不得引用 `Node.state`、当前 Mesh 或 `showGatewayModels`。

### 构建验证

新增 policy 文件加入以下四个 target：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

四个 target 均使用 generic iPhoneOS Debug 构建验证。

## 验收标准

1. 对问题日志等价的 owner 响应，两个 Space 都显示 No Gateway，不显示 online
   图标，概览为 `Internet Online: 0`、`No Gateway: 2`。
2. 顶层 Gateway 存在但本地 Node 解析失败时，Space 仍按服务器
   `gatewayOnline` 展示。
3. editor/visitor 行为保持现状。
4. Gateway bind、unbind、delete 和在线状态刷新流程保持现状。
5. 不新增用户可见文案、资源、依赖或 Auth 信息。

## 实施边界

本设计只提供客户端数据防御，不能替代服务端清理 Gateway 孤儿关联。服务端仍应
修复删除事务和 `siteInfo` 引用完整性。
