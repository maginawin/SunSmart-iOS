# Gateway Activate 移除需求分析与方案

## 结论

需求范围已确认：只移除 WiFi Gateway / 4G Gateway 详情页内的 Activate UI。

本次不移除 Activate 相关协议、同步数据计算、SAVE 任务生成、数据库字段、导入导出字段或 Site 列表状态逻辑。

## 当前代码事实

- 4G Gateway 使用 `GatewayViewController`；WiFi Gateway 继承 `GatewayViewController`。
- `GatewayViewController.sections` 当前包含 `.activate`，所以两个页面都会展示 Activate section。
- `WiFiGatewayViewController.sections` 目前基于父类 section 过滤 `.info`，并把 `networkConnectivity` 插在 `.activate` 后面。
- `GatewayViewController.configureActivateCell` 只更新本地 `setGatewayModel.activate`，没有在点击开关时直接发 Mesh 命令。
- `GatewayViewController.saveBtnAction` 会先保存 `setGatewayModel`，再调用 `node.getNodeSyncGatewayData(gateway:)` 判断是否进入 `SyncDevicesViewController`。
- `Node.getNodeSyncGatewayData(gateway:)` 当前会：
  - 将 `gateway.activate` 传给 `.gatewayAssociatedSpaces` / `.gatewayUnbindAssociatedSpaces`。
  - 根据 `gateway.activate` 计算 `currentAppkeyIndexs`，并可能追加 `.syncGatewaySubnetAppkeyIndexs`。
- `Node+MessageHandles` 中 Activate 相关的实际 Vendor Set 是：
  - `.gatewaySubnetsRelevanceSet`
  - `.gatewaySubnetAppkeyAdd`
  - `.gatewaySubnetAppkeyDelete`
- `SunricherVendorGet(function: .gatewaySimActivateState)` 当前在 `GatewayViewController.viewDidLoad` 中是注释代码，没有主动执行。

## 需求完整性判断

已明确：

- 删除 WiFi Gateway 和 4G Gateway 页面中的 Activate section。
- WiFi Gateway 的 Network Connectivity 不再依赖 `.activate` section 作为插入锚点，改为显示在 Name section 后。
- Activate 相关协议和任务保持现状。

不在本次范围：

- 修改 `Node.getNodeSyncGatewayData(gateway:)`。
- 修改 `Node+MessageHandles` 中 gateway subnet relevance 相关消息。
- 修改 `SyncDevicesViewController` 的 Gateway 同步任务展示。
- 修改 Site 首页、Gateway 下拉列表、Gateway status card 中的 inactive / noActivated 表现。
- 修改已存在本地数据库中的 `GatewayModel.activate`。
- 修改导入导出 JSON 中的 `activate` 字段。

## 推荐方案

### 方案 A：详情页窄范围移除（已确认）

只在 Gateway 详情页收口 Activate：

1. `GatewayViewController.sections` 不再包含 `.activate`。
2. `WiFiGatewayViewController.sections` 中 `networkConnectivity` 不再依赖 `.activate` 的位置，改为插在 `.name` 之后。
3. 保留 `saveBtnAction`、`Node.getNodeSyncGatewayData(gateway:)`、`Node+MessageHandles`、`SyncDevicesViewController` 中现有 Activate 相关协议和任务逻辑。
4. 保留 `GatewayModel.activate`、数据库、导入导出、Site 列表状态逻辑不动。

优点：改动小，直接满足页面与 SAVE 行为，风险最低。

风险：Site 列表仍可能显示 `No Activated`。如果产品要求完全去掉 Activate 概念，需要另开范围处理。

### 方案 B：全局废弃 Activate

除方案 A 外，同时移除或重定义 Site 列表、Gateway 状态、导入导出、数据库默认值中的 Activate 语义。

优点：产品概念统一。

风险：影响面大，可能破坏历史数据、云同步、导入导出兼容和其他 target 表现；不建议在当前需求下直接做。

## 推荐实施计划

1. 更新静态检查脚本，覆盖：
   - `GatewayViewController.sections` 不包含 `.activate`。
   - `WiFiGatewayViewController.sections` 不依赖 `.activate` 插入 `networkConnectivity`。
2. 修改 `GatewayViewController.sections`，删除 Activate section。
3. 修改 `WiFiGatewayViewController.sections`，将 Network Connectivity 插入到 `.name` 后。
4. 不修改 SAVE 同步路径、协议消息、SyncDevices 任务构造、Copy Information、数据库和导入导出。
5. 运行静态检查脚本。
6. 运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 待确认

已确认按方案 A 执行，且本次只移除 WiFi Gateway / 4G Gateway 详情页内的 Activate UI。
