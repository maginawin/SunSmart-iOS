# Wi‑Fi / 4G Gateway Online 状态异常分析与待确认修复方案

## 1. 结论

这是 Site 页面共享状态层的问题，不是 Wi‑Fi 网关或 4G 网关各自的协议问题。

从 Space 返回 Site 时，Site 会在 Mesh 仍处于 Space 子网的阶段先执行一次 `setupData()`。此时 Site 主网中的网关节点无法从“当前 Mesh 网络”解析出来，网关列表会暂时为空；随后 `setupData()` 又把服务器导入的 `SpaceData.gatewayStatus` 从 `.online` 覆盖成 `.notBound`。

Site 在 `viewDidAppear` 切回主网后会再次刷新数据，但第一次刷新已经破坏了内存中的服务器状态。第二次刷新只能把该 Space 继续判成非 online，直到用户下拉刷新，再次通过 `siteInfo` 从服务器取回 `gatewayOnline = true`。

这条链路同时适用于 Wi‑Fi 和 4G 网关，因此两者会出现相同现象。

## 2. 用户现象与源码链路对应

### 2.1 下拉刷新后显示正确

`siteInfo` 返回的 Space JSON 在 `ImportData.swift` 中按以下规则导入：

- `gatewayId` 非空且 `gatewayOnline = true`：`gatewayStatus = .online`
- `gatewayId` 非空且 `gatewayOnline = false`：`gatewayStatus = .offline`，并记录 `gatewayLastupdate`
- `gatewayId` 为空：`gatewayStatus = .notBound`

证据位置：

- `SunSmart/Common/Data/ImportData.swift` 第 992–1005 行

Site 页的概览直接统计 `SpaceData.gatewayStatus`：

- `.online` 数量显示为 `Internet Online`
- `.offline` 数量显示为 `Internet Offline`
- `.notBound` 数量显示为 `No Gateway`

证据位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift` 第 2341–2348 行

Space 卡片右上角图标也直接读取同一个字段：

- `.online` 显示绿色 Internet online 图标
- `.offline` 显示灰色 Internet offline 图标
- `.notBound` 不显示网关图标

证据位置：

- `SunSmart/Main/Space/View/SpacesViewCell.swift` 第 116–124 行

因此，下拉刷新后的 `Internet Online: 1` 和绿色图标都来自服务器 `gatewayOnline`。

### 2.2 进入 Space 后发生网络上下文切换

进入 Space 时，`SpaceViewController` 使用该 Space 的 `meshNetworkId` 加载并连接子网。

证据位置：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift` 第 328–332 行
- `SunSmart/Main/Space/Controller/SpaceViewController.swift` 第 657–665 行

SDK 加载子网时会按 `subnetworkId` 过滤节点，因此当前 Space 子网不会包含 Site 主网中的网关节点。

证据位置：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift` 第 744–751 行

### 2.3 返回 Site 时先刷新 UI，后切回主网

Site 返回流程的顺序是：

1. `viewWillAppear` 立即调用 `setupData()`
2. `viewDidAppear` 才检查当前网络是否为 Site 主网
3. 如果仍在 Space 子网，则异步切回 Site 主网，完成后再次调用 `setupData()`

证据位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift` 第 138–149 行
- `SunSmart/Main/Site/Controller/SiteViewController.swift` 第 167–184 行

第一次 `setupData()` 执行时仍处于 Space 子网。

### 2.4 第一次刷新破坏服务器状态

`loadGatewaysData()` 通过 `Gateway.resolve(model:)` 从当前 `MeshNetworkManager` 的 Mesh 网络解析网关节点。当前网络是 Space 子网时，主网网关解析失败，`compactMap` 会将其过滤掉。

证据位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift` 第 709–718 行
- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift` 中 `resolveNode(in:)`、`Gateway.resolve(model:)`

随后 `setupData()` 会反向改写每个 Space 的服务器状态：

- 当前网关列表中存在关联该 Space 的网关：按 `Gateway.connectStatus` 写成 `.online` 或 `.offline`
- 找不到网关：写成 `.notBound`

证据位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift` 第 257–286 行

此时网关列表为空，所以原本由服务器写入的 `.online` 被改成 `.notBound`。概览 online 数量变为 0，Space 卡片不再显示 online 图标。

第二次 `setupData()` 虽然已经切回主网，但第一次调用已经覆盖 `site.spaces` 中同一批 `SpaceData` 对象。没有新的服务器响应时，原始 `gatewayOnline = true` 无法自行恢复。

## 3. 当前 App 如何判断 online / offline

当前实际存在三类不同的“在线”概念。

### 3.1 Site 页的 Internet online / offline

正常来源是服务器 `siteInfo` 中每个 Space 的：

- `gatewayId`
- `gatewayOnline`
- `gatewayLastupdate`

它表达的是网关与互联网/服务器的在线状态，不是手机是否有网络，也不是 App 是否通过 BLE Mesh 连接到该网关。

### 3.2 本地 Mesh 节点 online / offline

`Node.state` 表达 App 当前 Mesh 会话中是否观察到节点在线。它受当前主网/子网、代理连接、心跳和超时影响。

它适合设备控制可用性判断，但不应直接作为 Site 页 `Internet Online` 的真值。

### 3.3 Wi‑Fi / 4G 信号与 Internet 状态

- Wi‑Fi 网关详情页通过 V1.9 的 RSSI 状态响应分别处理 Wi‑Fi 信号和 `networkStatus`。`No Signal` 与 `No Internet` 是分开的。
- 4G 网关详情页通过 `csqRssi` 计算蜂窝信号等级。

这些是详情页的即时本地状态，不是 Site 概览当前采用的状态来源。

## 4. 合理性评估

### 4.1 合理部分

- `Internet Online` 使用服务器状态作为真值是合理的。网关可能通过 Wi‑Fi 或 4G 连云，但不一定处于手机当前 BLE Mesh 的可达范围。
- 手机自身的 `NetworkRequest.shared.networkable` 只控制 App 请求和无网络提示，不直接决定网关是否在线，这也是合理的。
- Wi‑Fi 信号、4G 信号、本地 Mesh 可达性、云端 Internet 在线状态应保持独立，当前详情页已有部分这种区分。

### 4.2 不合理部分

- `SpaceData.gatewayStatus` 同时承担“服务器状态快照”和“本地 UI 派生状态”，存在双向覆盖。
- “当前子网解析不到主网网关节点”被错误解释为“Space 未绑定网关”。
- 页面生命周期和当前全局 Mesh 网络上下文会改变 Internet 状态，状态真值层不稳定。
- `loadGatewaysData()` 从首个匹配 Space 反推整个网关的 `connectStatus`，随后又把该状态写回所有 Space，形成循环依赖。
- 状态只有 online、offline、notBound，没有 unknown/stale。服务器状态尚未刷新时，App 无法明确表达“当前未知”，只能展示缓存值或错误降级。

综合判断：服务器作为 Internet 状态来源的方向合理，但当前本地状态传播和覆盖机制不合理。

## 5. 修复方案比较

### 方案 A：仅调整返回页面的执行时序

从 Space 返回时，如果当前仍是子网，则跳过 `viewWillAppear` 中的 `setupData()`；等待 `viewDidAppear` 切回 Site 主网后再刷新。

优点：

- 改动最小。
- 可以修复当前明确的复现步骤。

缺点：

- `setupData()` 仍会覆盖服务器状态。
- 通知、异步回调或其他入口只要在错误 Mesh 上下文调用 `setupData()`，问题仍会复发。
- 状态真值层的循环依赖没有解决。

结论：可作为临时止血，不建议作为最终修复。

### 方案 B：拆分真值与派生状态，并显式使用 Site 主网解析网关

核心规则：

1. `SpaceData.relevanceGatewayId`、`gatewayStatus`、`gatewayLastOnline` 只由服务器导入或明确的绑定/解绑结果更新。
2. `setupData()` 只读取这些字段用于展示，不再因为当前 Mesh 网络解析结果覆盖它们。
3. Site 需要构造可操作的 `Gateway` 对象时，显式从 Site 主网加载网关节点，不依赖当前全局 Mesh 网络恰好处于主网。
4. 网关绑定/解绑成功后，通过服务器刷新或明确的关联结果更新 Space 状态，不再依赖 `setupData()` 猜测。
5. 无法加载主网节点时，只影响网关详情入口或本地操作能力，不改变 Internet online/offline 与绑定状态。

优点：

- 在状态源头消除本问题。
- Wi‑Fi 与 4G 共用一套修复。
- 不再依赖页面生命周期、当前子网或 BLE 连接状态。
- 保留服务器 Internet 状态与本地 Mesh 可达性的语义边界。

缺点：

- 需要同时审计网关绑定、解绑、删除和通知刷新路径。
- 改动量高于方案 A，但仍可限制在 Site/Gateway 状态层，不需要修改协议或 SDK。

结论：推荐。

### 方案 C：建立完整 Gateway Presence 状态模型

分别建模：

- 云端 Internet 状态
- 本地 Mesh 可达性
- Wi‑Fi/4G 信号状态
- Space 绑定状态
- 数据新鲜度和 unknown/stale

优点：

- 语义最完整，未来可明确展示“云端在线但本地不可达”等组合状态。

缺点：

- 涉及模型、UI、文案、本地化和更多业务入口。
- 对当前问题而言范围偏大。

结论：适合作为后续架构演进，不建议与本次缺陷捆绑。

## 6. 推荐方案 B 的实施规划

### 阶段 1：建立回归测试

- 覆盖“服务器 online + 当前处于 Space 子网 + 返回 Site”的场景。
- 断言 `Internet Online` 仍为 1。
- 断言关联 Space 保持 online 图标。
- 断言当前子网无法解析 Site 主网网关时，不会将 Space 改成 `.notBound` 或 `.offline`。
- 同一组测试分别覆盖 Wi‑Fi 和 4G 网关数据，证明修复位于共享状态层。

### 阶段 2：修正状态所有权

- 移除 `setupData()` 对服务器导入状态的无条件反向覆盖。
- 将 Site 概览与 Space 卡片统一保持为 `SpaceData.gatewayStatus` 的只读消费者。
- 明确本地绑定/解绑完成后的状态更新入口，避免依赖 UI 刷新函数产生业务状态。

### 阶段 3：消除当前 Mesh 上下文依赖

- Site 加载网关时显式解析 Site 主网节点。
- 当前处于 Space 子网、其他 Site 网络或尚未加载 Mesh 时，不把“解析失败”解释为 offline/notBound。
- 网关详情和 OTA 等需要真实节点的入口继续要求主网节点可用。

### 阶段 4：审计绑定与权限路径

检查以下路径在移除反向覆盖后仍能正确刷新：

- 添加网关并关联 Space
- 已有网关新增关联 Space
- 解除 Space 关联
- 删除网关
- Owner、Editor、Visitor 的网关可见性
- All Spaces 和 Favourites
- 网关筛选后的 Space 列表

### 阶段 5：验证

静态与自动化验证：

- 新增状态解析回归测试。
- 运行相关测试。
- 运行 `git diff --check`。
- 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS target，因为 Site/Gateway 代码由多个品牌 target 共享。

真机验收：

- Wi‑Fi 网关：下拉在线、进入关联 Space 并连接设备、返回 Site，online 数量与图标保持正确。
- 4G 网关：执行同一流程。
- Internet 真正断开后，下拉刷新能显示 offline 和最后在线时间。
- App 仅断开 BLE 或切换 Space 子网时，不应改变服务器 Internet 状态。
- 手机无网络时，保留最后一次服务器状态，不凭本地 Mesh 状态伪造 Internet offline；恢复手机网络并下拉后更新。

## 7. 改动边界

本次建议不修改：

- Wi‑Fi Gateway V1.9 协议。
- 4G CSQ/RSSI 解析。
- SDK 的节点 online/offline 机制。
- 用户可见文案和图标资源。
- 与网关状态无关的 Site/Space 功能。

## 8. 当前验证状态

本结论已完成源码级数据流与生命周期交叉验证，且能完整解释用户提供的稳定复现现象。

尚未进行：

- 业务代码修改。
- 自动化测试。
- iPhoneOS 构建。
- Wi‑Fi/4G 真机回归。

以上工作需在方案确认后执行。
