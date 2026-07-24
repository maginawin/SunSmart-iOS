# Site Gateway Online 状态真值分离设计

## 背景

Site 的 All Spaces 和 Favourites 页面通过 `SpaceData.gatewayStatus` 统计 `Internet Online`、`Internet Offline`、`No Gateway`，并控制每个 Space 卡片右上角的 Internet 状态图标。

服务器 `siteInfo` 会为每个 Space 返回 `gatewayId`、`gatewayOnline` 和 `gatewayLastupdate`。当前 App 会先把这些字段导入 `SpaceData`，随后又在 `SiteViewController.setupData()` 中根据本地 `Gateway` 解析结果反向覆盖相同状态。

进入 Space 后，App 会连接 Space 子网。返回 Site 时，`viewWillAppear` 早于 `viewDidAppear` 执行，第一次 `setupData()` 仍处于 Space 子网；Site 主网网关无法从当前 Mesh 网络解析，服务器导入的 `.online` 因而被覆盖为 `.notBound`。这会使 `Internet Online` 变为 0，并移除 Space 卡片的 online 图标。

该故障位于 Site/Gateway 共享状态层，Wi‑Fi 和 4G 网关都会受到影响。

## 目标

- 服务器 `gatewayOnline` 是 Site 页面 Internet online/offline 的唯一权威来源。
- 当前 Mesh 主网、子网、BLE 代理或节点解析状态不得反向修改 Internet 状态。
- 从 Space 返回 Site 后，All Spaces 和 Favourites 保持服务器最后一次有效状态。
- Wi‑Fi 与 4G 网关共用同一修复，不增加设备类型分支。
- 网关绑定、解绑、删除和新增关联后，Site 能从服务器刷新新的权威关联状态。
- Site 主网网关节点暂时无法解析时，只限制需要真实节点的操作，不隐藏或篡改 Internet 概览与 Space 图标。
- 保持现有用户可见文案、图标、布局、权限和网关协议不变。

## 非目标

本次不实现：

- 新的 unknown、stale 或最后刷新时间 UI。
- Wi‑Fi Gateway V1.9 协议调整。
- 4G CSQ/RSSI 规则调整。
- NordicSigMeshSDK 的节点 online/offline 机制调整。
- 网关 MQTT 在线判定或服务器在线算法调整。
- Site/Space 页面视觉改版。
- 与网关状态无关的 Site、Space 或设备模块重构。

## 状态语义与所有权

| 状态 | 权威来源 | 消费位置 | 本次约束 |
| --- | --- | --- | --- |
| Space 是否绑定网关 | 服务器 `gatewayId` 或已确认的服务器绑定结果 | Site 列表、添加网关权限、网关关联列表 | 不根据当前 Mesh 是否存在网关节点推断 |
| Gateway Internet online/offline | 服务器 `gatewayOnline` | Site 概览、Space 卡片、Gateway 列表状态 | 不由 BLE、子网或 `Node.state` 覆盖 |
| Gateway 最后在线时间 | 服务器 `gatewayLastupdate` | Gateway offline 状态展示 | 仅随服务器状态更新 |
| 本地 Mesh 节点可达性 | SDK `Node.state` | 网关详情、设备控制、需要真实节点的操作 | 不参与 Site Internet 统计 |
| Wi‑Fi 信号与 Internet 状态 | Wi‑Fi Gateway V1.9 RSSI 状态响应 | Wi‑Fi 网关详情页 | 保持现状 |
| 4G 信号等级 | `csqRssi` | 4G 网关详情页 | 保持现状 |
| 手机网络可用性 | `NetworkRequest.shared.networkable` | 请求能力、无网络提示 | 不直接改变 Gateway Internet 状态 |

## 采用的架构

### 1. `SpaceData` 保持服务器状态快照

`SpaceData.relevanceGatewayId`、`gatewayStatus` 和 `gatewayLastOnline` 继续由 `siteInfo`/`spaceInfo` 导入，但不再由 `setupData()` 根据本地网关列表反向覆盖。

`setupData()` 的职责收窄为：

- 从 `site.spaces` 生成 All Spaces 和 Favourites 数据。
- 应用当前 Gateway 筛选条件。
- 构建可操作的 Gateway 列表。
- 刷新 Collection View、Header 和 Empty View。

它不再写入 Space 的绑定状态或 Internet 状态。

### 2. Gateway 展示状态单向派生

`Gateway.connectStatus` 仍作为 Gateway 下拉列表和 Gateway Header 的运行期展示状态，但只从服务器导入的 Space 状态派生。

数据方向固定为：

服务器 Space 状态 → `SpaceData.gatewayStatus` → `Gateway.connectStatus` → Gateway UI。

禁止反向执行：

`Gateway.connectStatus` → `SpaceData.gatewayStatus`。

`activate` 继续用于区分已激活 Gateway 的 offline 与未激活 Gateway 的 inactive，但不能把 Space 的服务器 online 状态改写为 offline、inactive 或 notBound。

### 3. 显式解析 Site 主网节点

Site 构建 `Gateway` 运行期对象时，不再无条件使用 `MeshNetworkManager.instance.meshNetwork`。

节点解析顺序为：

1. 当前 Mesh 属于目标 Site 且当前 Network Key 是主网时，复用当前 Mesh 网络。
2. 否则，从本地数据库只读加载该 Site 的主网快照。
3. 使用明确的主网对象解析 `GatewayModel.address` 对应节点。
4. 不打开 BLE 连接，不切换当前 Mesh 会话。

如果主网快照或节点解析失败：

- 不修改任何 `SpaceData` 状态。
- Internet 概览和 Space 卡片继续展示服务器最后一次有效状态。
- 该 Gateway 暂时不进入需要真实 `Node` 的操作列表。
- `viewDidAppear` 切回 Site 主网后，既有二次 `setupData()` 可重新解析操作对象。

### 4. 概览与操作能力解耦

Internet 概览和 Space 卡片是否展示状态，只取决于 `SpaceData.gatewayStatus`。

Gateway 下拉列表、网关详情、恢复、同步和 OTA 等需要真实节点的入口，继续依赖成功解析的 `Gateway` 对象。

因此，“节点暂时无法解析”只表示本地操作条件暂不可用，不等同于：

- Internet offline。
- Space 未绑定网关。
- Gateway 未激活。

现有 Add Gateway UI 和权限判断保持不变，只修正其输入状态不再被错误覆盖。

### 5. 绑定拓扑变更后的权威刷新

网关关联 Space 的保存流程已经逐项调用服务器 bind/unbind 接口。设计要求保存流程区分：

- 关联集合未变化。
- 至少发生一次已确认成功的绑定或解绑。

只有关联集合发生变化时，Gateway 页面发出专用的“Site Gateway 关联拓扑已变化”通知。Site 页面收到后记录需要权威刷新，不使用 `setupData()` 本地猜测绑定结果。

当用户返回 Site：

1. 页面可以先按最后一次有效服务器状态展示。
2. 触发一次 `siteInfo` 请求。
3. 请求成功后导入新的 `gatewayId`、`gatewayOnline` 和 `gatewayLastupdate`。
4. 再执行只读的 `setupData()`。

新增网关继续复用现有添加完成后的 `loadSiteRequest()`；删除网关继续复用现有 `SiteStateChangeNotificationName` 所触发的 Site 权威刷新。

普通 Gateway 名称、APN、服务器信息、修复或设备同步通知不触发额外的关联刷新，避免把所有 Gateway 数据变化都扩大为 `siteInfo` 请求。

## 页面生命周期数据流

### 下拉刷新

1. Site 请求 `siteInfo`。
2. `SiteData.update` 导入服务器 Space 状态。
3. `setupData()` 只读生成列表和概览。
4. All Spaces 与 Favourites 使用同一批 `SpaceData` 状态。

### 进入 Space

1. Site 先按现有流程刷新目标 Space 数据。
2. `SpaceViewController` 切换到 Space 子网并连接设备。
3. Site 已缓存的 Internet 状态不随 Mesh 会话切换而变化。

### 从 Space 返回 Site

1. `viewWillAppear` 可以执行只读 `setupData()`。
2. 即使当前仍是 Space 子网，解析失败也不会修改 Space 状态。
3. `viewDidAppear` 切回 Site 主网。
4. 主网切换完成后再次构建 Gateway 操作对象。
5. 概览与 Space 图标在整个过程中保持服务器最后一次有效状态。

### 网关绑定或解绑 Space

1. Gateway 页面完成服务器 bind/unbind 请求。
2. 本地 Gateway 关联集合保存成功。
3. 仅在关联集合确实变化时标记 Site 需要权威刷新。
4. 返回 Site 后请求一次 `siteInfo`。
5. 成功响应成为新的绑定和 Internet 状态真值。

## 异常与降级处理

### Site 主网本地快照无法加载

- 保留服务器 Space 状态。
- 不显示依赖真实节点的 Gateway 操作入口。
- 不把状态改成 offline、inactive 或 notBound。
- 主网重新加载成功后恢复操作入口。

### `siteInfo` 请求失败

- 保留最后一次成功导入的服务器状态。
- 结束 Refresh Control 和 HUD，沿用现有错误处理。
- 不使用 BLE Mesh 状态填补 Internet 状态。
- 用户可通过下拉刷新重新请求。

### 手机无网络

- 保留缓存的服务器状态。
- 显示现有手机无网络提示。
- 不把 Gateway Internet 状态改成 offline。

### Gateway 本地 Mesh 断开

- `Node.state` 可以变为 false，并继续限制网关详情或设备控制。
- Site `Internet Online` 和 Space 卡片图标不变。
- 下一次服务器刷新决定 Internet 状态是否变化。

### 服务器数据不一致

同一 Gateway 关联多个 Space 时，Site 继续使用服务器针对每个 Space 返回的状态。App 不再用任意一个 Space 的本地派生结果覆盖其他 Space。

Gateway 下拉项仍按现有 Gateway 级映射展示；本次不引入冲突状态 UI。

## 行为矩阵

| 场景 | Internet 概览 | Space 图标 | Gateway 操作入口 |
| --- | --- | --- | --- |
| 服务器 online，当前 Site 主网 | Online +1 | 绿色 online | 主网节点可解析时可用 |
| 服务器 online，当前 Space 子网 | Online +1 | 绿色 online | 节点暂不可解析时可暂缓 |
| 服务器 offline，当前 Space 子网 | Offline +1 | offline | 节点暂不可解析时可暂缓 |
| 服务器显示未绑定 | No Gateway +1 | 不显示 | 按现有添加权限显示 |
| 手机无网络，缓存 online | 保持 Online +1 | 保持绿色 online | 网络请求类操作受限 |
| BLE 代理断开，缓存 online | 保持 Online +1 | 保持绿色 online | 本地 Mesh 操作受限 |
| 绑定成功但 Site 尚未刷新 | 保持最后一次有效状态 | 保持最后一次有效状态 | 返回 Site 后自动请求权威状态 |
| 解绑成功但 Site 尚未刷新 | 保持最后一次有效状态 | 保持最后一次有效状态 | 返回 Site 后自动请求权威状态 |

## 影响文件

### 生产代码

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 移除 `setupData()` 对 `SpaceData.gatewayStatus` 的反向覆盖。
  - 显式从 Site 主网解析 Gateway 节点。
  - 将 Internet 概览可见性与 Gateway 节点解析结果解耦。
  - 监听关联拓扑变化并在返回 Site 时触发权威刷新。

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 区分关联集合是否实际变化。
  - 在服务器绑定/解绑成功且本地配置保存后发出专用关联拓扑变化通知。

### 自动化验证

- `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
  - 验证 `setupData()` 不再写入 Space Gateway 状态。
  - 验证 Gateway 节点解析显式使用 Site 主网。
  - 验证概览状态不依赖 Gateway 节点是否解析成功。
  - 验证关联拓扑变化触发权威 Site 刷新。

- `scripts/check_site_gateway_online_state.sh`
  - 编译并运行状态契约测试。
  - 检查 Wi‑Fi 与 4G 共用 Site 状态路径，不增加设备类型特判。

### 不需要修改

- `SunSmart/Common/Data/ImportData.swift` 的服务器字段导入规则。
- `SunSmart/Common/Data/SpaceData.swift` 的 `GatewayStatus` 枚举。
- `SunSmart/Main/Space/View/SpacesViewCell.swift` 的图标映射。
- Wi‑Fi/4G Gateway 协议、资源和本地化。
- NordicSigMeshSDK。
- CocoaPods、Swift Package 和 target 配置。

## 测试策略

### 自动化契约测试

先让新契约测试在当前代码上失败，证明它能捕获以下问题：

- `setupData()` 写入 `space.gatewayStatus`。
- `loadGatewaysData()` 依赖默认当前 Mesh 网络。
- 概览可见性错误依赖 `showGatewayModels`。
- 绑定/解绑后没有权威 Site 刷新标记。

完成修复后重新运行，要求全部通过。

### 源码与静态验证

- 运行 `scripts/check_site_gateway_online_state.sh`。
- 运行 `git diff --check`。
- 确认没有新增用户可见文案、资源、依赖或 Auth 信息。
- 确认没有修改 Wi‑Fi/4G 协议解析。

### 多 Target 构建

Site、Space 和 Gateway 代码由多个品牌 target 共享，需直接使用 generic iPhoneOS 依次构建：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建成功只证明静态集成成立，不代表 Wi‑Fi、4G、BLE 或服务器行为已完成真机验收。

### 真机验收

1. Wi‑Fi Gateway online，关联一个 Space；下拉 Site 后应显示 `Internet Online: 1` 和绿色图标。
2. 进入关联 Space，连接设备成功，再返回 Site；online 数量和图标保持不变。
3. 在 All Spaces 和 Favourites 分别重复步骤 2。
4. 4G Gateway 重复步骤 1–3。
5. 仅断开 BLE 或切换子网，服务器仍 online 时，Site 状态保持 online。
6. Gateway Internet 真正断开并完成服务器状态更新后，下拉刷新显示 offline 和最后在线时间。
7. 手机无网络时保留最后一次服务器状态；恢复网络并下拉后更新。
8. 新增 Gateway 并关联 Space，返回 Site 后显示服务器最新状态。
9. 已有 Gateway 新增或解除 Space 关联，返回 Site 后绑定状态和统计正确。
10. 删除 Gateway 后，关联 Space 更新为 No Gateway。
11. Owner、Editor、Visitor 的 Gateway 可见性和操作权限保持现状。
12. Gateway 筛选后的 All Spaces 与 Favourites 列表保持正确。

## 改动边界与回归保护

- 不新增 Auth、服务器凭据或敏感日志。
- 不格式化或重构无关文件。
- 不把 `Node.state`、Wi‑Fi RSSI、Wi‑Fi `networkStatus` 或 4G `csqRssi` 合并进 Site Internet 状态。
- 不改变 Space 卡片既有 online/offline/notBound 图标映射。
- 不改变 Gateway 详情、恢复、同步和 OTA 对真实节点的既有要求。
- 不因本次缺陷引入 unknown/stale UI；如后续需要，单独设计。

## 设计自检

- 方案 B 的状态真值、主网解析、绑定刷新和降级行为均有明确责任边界。
- Internet 状态与本地 Mesh 可达性保持单向、无循环依赖。
- Wi‑Fi 与 4G 使用同一状态路径，没有设备类型特判。
- 绑定、解绑、新增和删除均有权威刷新路径。
- 主网节点解析失败不会再改变或隐藏服务器 Internet 状态。
- All Spaces、Favourites、权限、筛选和多 target 回归范围已覆盖。
- 设计不需要修改协议、SDK、本地化、资源、依赖或 target 配置。
- 范围可由一个聚焦的实现计划完成，无需拆分为独立子项目。
