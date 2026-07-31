# Site 无 Gateway 却显示 Internet Online 日志分析

## 结论

本次现象不是 App 探测到了真实 Gateway，也不是 Mesh `Node.state` 判断错误。

直接原因是 `siteInfo` 返回了相互矛盾的服务器数据：

- Site 顶层 `gateways` 是空数组，表示当前响应中没有任何 Gateway。
- Space 对象仍携带非空 `gatewayId`、`gatewayOnline: true` 和
  `gatewayLastupdate`。

客户端导入 Space 时只要看到非空 `gatewayId`，就直接采用 `gatewayOnline`；
它不会验证该 `gatewayId` 是否仍存在于同一响应的顶层 `gateways`。Site 概览
随后统计的是 online Space 数量，而不是实际 Gateway 数量，所以两个 Space
均被导入为 online 后，页面显示 `Internet Online: 2`，两个 Space 卡片也都显示
online 图标。

## 日志证据

### 1. 请求成功，不是缓存请求失败后的旧 UI

`siteInfo` 返回：

- HTTP status：200
- businessCode：200
- businessMessage：success

响应被正常导入，日志随后出现“导入数据完成”和进入 `SiteViewController`。

### 2. 顶层没有 Gateway

响应 `data.gateways` 明确为 `[]`。

这与“项目实际没有 Gateway”的观察一致。导入代码会把服务器 Gateway 列表
构造成 `serverByMac`；当数组为空时，已上传的本地 Gateway 缓存也会被删除。

对应源码：

- `SunSmart/Common/Data/ImportData.swift:481-525`

### 3. Space 中仍残留 Gateway 关联及 online 状态

日志中可完整看到的 `Space 1` 包含：

- `gatewayId: EF725643A2B9`
- `gatewayOnline: true`
- `gatewayLastupdate: 2026-07-30T07:24:02.770Z`

完整响应被截断，无法仅凭所贴文本读取第二个 Space 的原始三个字段；但页面最终
统计为 online 2，结合确定性的导入和统计代码，可以确认运行时两个 Space 的
`gatewayStatus` 都是 `.online`。

### 4. Space 导入没有做跨字段一致性校验

`SpaceData` 的导入规则是：

1. `gatewayId` 非空，则保存为 `relevanceGatewayId`。
2. `gatewayOnline == true`，则设置 `gatewayStatus = .online`。
3. 只有 `gatewayId` 缺失或为空，才设置为 `.notBound`。

这里没有检查 `gatewayId` 是否存在于顶层 `gateways`。

对应源码：

- `SunSmart/Common/Data/ImportData.swift:992-1005`

### 5. Internet Online 统计的是 Space，不是 Gateway

Site 概览直接对当前 Space 数组分类：

- `.online` Space 数量 → `Internet Online`
- `.offline` Space 数量 → `Internet Offline`
- `.notBound` Space 数量 → `No Gateway`

因此 `Internet Online: 2` 的准确语义是“两个 Space 的缓存状态为 online”，
不是“项目存在两个 online Gateway”。

对应源码：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:2384-2391`

Space 卡片同样只读取 `space.gatewayStatus`，所以两个卡片也会展示 online 图标。

对应源码：

- `SunSmart/Main/Space/View/SpacesViewCell.swift:116-124`

## 根因分层

### P0：服务器响应存在引用完整性错误

同一个 `siteInfo` 快照同时表达：

- Gateway 集合为空。
- Space 仍绑定 Gateway `EF725643A2B9`，且该 Gateway online。

这两个事实不能同时成立。最高可能性是 Gateway 删除后，服务器删除了 Gateway
记录，却没有同步清理 Space 上的冗余关联和在线字段；也可能是不同数据表或缓存
的传播时序不一致。

App 的删除流程在服务端只调用一次 `gatewayDelete`，没有先逐个调用
`gatewayUnbindSpace`。客户端因此依赖服务端删除接口原子地清理 Gateway 与全部
Space 关联。

对应源码：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:687-696`

仅凭客户端日志能够确认“服务端响应已经不一致”，但还不能区分后台数据库级联
清理遗漏、缓存未失效或删除事务部分成功。需要服务端按 Gateway
`EF725643A2B9` 查询删除记录及两个 Space 的关联表。

### P1：客户端缺少针对矛盾快照的防御

客户端分别导入 `spaces` 和 `gateways`，但没有在完整 Site 响应中校验：

`Space.gatewayId` 必须能在 `data.gateways` 找到对应 Gateway。

因此服务端的孤儿 `gatewayId` 会一路传播到 Site 概览和 Space 卡片。

### P2：2026-07-24 的状态真值修复扩大了该脏数据的可见性

之前 Site 页面会用本地 Gateway/Mesh 解析结果反向覆盖 Space 状态，这会产生
“真实 Gateway online 却显示 offline/notBound”的问题。现有实现已正确禁止这种
反向覆盖，并允许在本地 Gateway 节点暂时无法解析时继续展示服务器状态。

但当前实现只判断“Space 是否存在服务器 Gateway 状态”，没有区分：

1. Gateway 在顶层服务器列表中存在，只是本地 Node 暂时无法解析。
2. Gateway 在顶层服务器列表中根本不存在，Space 持有孤儿 `gatewayId`。

所以前一个问题被修复后，后一个数据一致性缺口显现出来。不能恢复为按本地
`GatewayModel` 或 `Node.state` 覆盖状态，否则会重新引入此前的跨 Mesh 误判。

对应源码：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:786-794`

## 与其他日志的关系

- `DeviceParameterNodeProbe nodeCount=0` 说明本次参数探测没有节点，但它不是
  Gateway Internet 状态来源。
- `PJSpaceCountProbe` 中的 `nodes=0`、switches、scenes、groups 和 schedules
  用于 Space 内容/数量诊断，不参与 `gatewayStatus` 判定。
- `serverDeviceCount` 与 Internet online 状态无关。

## 修复方向建议

### 服务端优先

Gateway 删除应在同一事务中完成：

1. 删除 Gateway。
2. 清理所有关联 Space 的 `gatewayId`。
3. 清理或重置 `gatewayOnline`、`gatewayLastupdate`。
4. 使 `siteInfo` 保证每个非空 Space `gatewayId` 都能在顶层 `gateways` 中找到。

### 客户端防御

对 owner 的完整 `siteInfo` 响应，以顶层 `gateways` 的 MAC 集合作为“Gateway
是否存在”的服务器身份真值：

- Space 的 `gatewayId` 存在于该集合：保留服务器 `gatewayOnline`。
- Space 的 `gatewayId` 不存在于该集合：按 `.notBound` 展示，并记录孤儿关联
  诊断。

校验不能依赖本地 `showGatewayModels`、Mesh 当前网络或 `Node.state`，否则会
重新引入本地节点解析导致的 false offline/notBound。

访客或服务端可能返回裁剪 Gateway 列表的场景，需要先确认接口契约，再决定是否
应用同一强校验。

## 建议验证用例

1. 顶层 Gateway 存在、Space 指向该 Gateway、`gatewayOnline = true`，但本地
   Node 暂时解析失败：仍显示 online。
2. 顶层 `gateways = []`，Space 残留 `gatewayId` 和
   `gatewayOnline = true`：显示 `No Gateway`，不显示 online 图标。
3. 删除一个关联两个 Space 的 Gateway 后立即请求 `siteInfo`：顶层 Gateway
   与两个 Space 的关联字段必须同时清理。
4. owner、editor、visitor 分别验证 Gateway 列表是否为完整或权限裁剪响应。

本次仅完成日志与源码分析，没有修改生产代码。
