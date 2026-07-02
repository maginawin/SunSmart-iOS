# Gateway Activate SIG Mesh 命令分析

## 结论

当前 4G Gateway 与 WiFi Gateway 的 Activate 启用/禁用共用同一套父类页面逻辑和同一套同步逻辑。WiFi Gateway 只重写了菜单和 APN 支持，不单独实现 Activate。

Activate 本身不是一个独立的 “enable / disable” vendor opcode。保存后，App 根据 `GatewayModel.activate` 重新计算网关应关联的子网 AppKey index 列表，并同步到设备：

- 启用 Activate：发送 `SunricherVendorSet(function: .gatewaySubnetsRelevanceSet(subnetAppkeyIndexs: [...]))`，payload 中带当前已绑定的 secondary AppKey index 列表。
- 禁用 Activate：发送同一个 `gatewaySubnetsRelevanceSet`，但列表为空。
- 如果本次保存同时新增或移除 associated spaces，还可能先发送 Config NetKey/AppKey/Model App Bind 或 Unbind/Delete。只有 `activate == true` 且本次确实产生配置消息时，才会补发 `gatewaySubnetAppkeyAdd` 或 `gatewaySubnetAppkeyDelete`。

## 页面入口

- Site 网关入口在 `SunSmart/Main/Site/Controller/SiteViewController.swift`。
- `node.isWiFiGateway == true` 时进入 `WiFiGatewayViewController`。
- 其他 Gateway 进入 legacy `GatewayViewController`。
- WiFi Gateway 判断条件在 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`：`companyIdentifier == 0x0A78` 且 `productIdentifier == 0x2721`。

## Activate UI 行为

`GatewayViewController.configureActivateCell` 里只做本地编辑态变更：

- 校验当前不在连接中。
- 校验 site 有 edit 权限。
- 校验 gateway 已有 MQTT 授权信息。
- 切换 `setGatewayModel.activate`。
- Save 按钮变为可用。

真正发 Mesh 命令发生在 Save 后：

- `saveBtnAction` 保存 `GatewayModel`。
- `node.getNodeSyncGatewayData(gateway: setGatewayModel)` 计算需要同步的数据。
- 若需要同步，进入 `SyncDevicesViewController(type: .devices([node]))`。

## 同步数据计算

`Node.getNodeSyncGatewayData(gateway:)` 中与 Activate 直接相关的是：

- `gateway.activate == true` 时，`currentAppkeyIndexs` 为当前网关节点已绑定的 secondary application key indexes。
- `gateway.activate == false` 时，`currentAppkeyIndexs` 为空数组。
- 如果 `currentAppkeyIndexs` 与 `gatewayInfo?.subnetAppkeyIndexs` 不一致，追加 `.syncGatewaySubnetAppkeyIndexs(appkeyIndexs: currentAppkeyIndexs)`。

WiFi Gateway 与 4G Gateway 都走这段逻辑。差异是 WiFi Gateway 会跳过 APN 同步：`if !isWiFiGateway, let apn = gateway.apn ...`。

## SIG Mesh / Vendor 命令

主消息：

- Mesh message：`SunricherVendorSet`
- Vendor Set opcode：`0xF0780A`
- Response：`SunricherVendorStatus`
- Vendor main code：`VendorOpCode.gateway = 0x43`
- Gateway subcode：`VendorGatewayCode.subnetsRelevanceSet = 0x05`
- SDK function：`gatewaySubnetsRelevanceSet(subnetAppkeyIndexs:)`
- Payload：`43 05 <count> <appkeyIndex UInt16>...`

`UInt16` 在 SDK 里通过 `DataConvertible` 直接按本机内存写入；在当前 iOS 小端环境下表现为 little-endian。因此 AppKey index `0x0001` 会写成 `01 00`。

示例：

- 启用且关联 AppKey index `0x0001`：`43 05 01 01 00`
- 禁用：`43 05 00`

关联/解绑 Space 伴随命令：

- 新增关联时，可能先发送标准 Config 消息：
  - `ConfigNetKeyAdd`
  - `ConfigAppKeyAdd`
  - `ConfigModelAppBind`
- 如果 `activate == true` 且确实产生了配置消息，还会发送：
  - `SunricherVendorSet(function: .gatewaySubnetAppkeyAdd(subnetAppkeyIndex: ...))`
  - Vendor main code：`0x43`
  - Gateway subcode：`0x0B`
  - Payload：`43 0B <appkeyIndex UInt16>`
- 解除关联时，可能先发送标准 Config 消息：
  - `ConfigModelAppUnbind`
  - `ConfigAppKeyDelete`
  - `ConfigNetKeyDelete`
- 如果 `activate == true` 且确实产生了配置消息，还会发送：
  - `SunricherVendorSet(function: .gatewaySubnetAppkeyDelete(subnetAppkeyIndex: ...))`
  - Vendor main code：`0x43`
  - Gateway subcode：`0x0C`
  - Payload：`43 0C <appkeyIndex UInt16>`

注意：当用户只是把 Activate 从启用切到禁用，且 associated spaces 没有新增/移除时，核心同步不会发 `gatewaySubnetAppkeyDelete`，而是发 `gatewaySubnetsRelevanceSet` 的空列表：`43 05 00`。

## 非 Activate 命令

代码中存在 `SunricherVendorGet(function: .gatewaySimActivateState)`，对应：

- Vendor Get opcode：`0xF1780A`
- Payload：`43 06`

但它在 `GatewayViewController.viewDidLoad` 中是注释代码，并且含义是获取 SIM 激活状态，不是当前页面 Activate 开关的启用/禁用命令。
