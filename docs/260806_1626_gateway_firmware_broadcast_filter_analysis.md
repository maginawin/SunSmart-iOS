# Site Firmware Update 中 Gateway 广播过滤规则分析

## 结论

当前 `Site -> Firmware Update` 的 Gateway BLE OTA 页面，并不是把广播扫描到的所有设备动态加入列表。

页面展示对象先由 Site 本地保存的 Gateway 与 Mesh Node 生成；广播扫描只负责在这些既有候选节点中反查设备、更新 `peripheral` 和 RSSI，并决定设备能否勾选升级。

因此：

- 如果 4G Gateway 在页面中完全没有类别或设备条目，主要原因不在广播过滤，而在进入页面前的候选 Gateway、Gateway 对应 Node，或 Node 的 Product ID 数据。
- 如果 4G Gateway 已有条目，但没有信号、呈禁用状态或不能勾选，才需要重点检查广播过滤、MAC 反查、固件版本和 RSSI 门槛。
- 当前代码没有按“4G Gateway”名称或按某个 4G PID 主动排除设备。

## 一、进入页面前的候选 Gateway 规则

### 1. Site 必须能加载 GatewayModel 并解析到主 Mesh 网络中的 Node

`SiteViewController.loadGatewaysData()` 的数据来源是当前 Site 下保存的 `GatewayModel`。每个 GatewayModel 都必须按其地址在 Site 主网络中解析到 Node，否则直接丢弃。

源码位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:720-750`

这里隐含的必要条件是：

1. `GatewayModel` 已按当前 Site ID 保存；
2. 当前 Site 主 Mesh 网络可以加载；
3. `GatewayModel.address` 能在该网络中解析到 Node。

### 2. Owner 与非 Owner 的候选规则不同

`firmwareUpdateGatewayModels` 的规则是：

- Site Owner：使用 `gatewayModels`，即 Site 内所有已成功解析到 Node 的 Gateway；
- 非 Owner：先经过 `site.canConfigureGateway` 权限过滤，再要求 Gateway 的 `associatedSpaces` 非空。

源码位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:72-82`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:259-268`
- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift:263-283`

所以，如果当前账号不是 Site Owner，4G Gateway 没有关联任何 Space，它会在进入 Firmware Update 页面前被明确排除。这是当前源码中最直接的“整台 Gateway 不展示”规则。

### 3. 页面只接收上述 Gateway 对应的 Node

点击 Firmware Update 后，代码只把 `firmwareUpdateGatewayModels` 中的 Node 传给 `BleFirmwareUpdateViewController`。

源码位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:1213-1228`

Site 入口传入 `space: nil`，所以 `BLEFirmwareSpaceDeviceResolver` 不会再按 Space、Switch、Dongle 或 EFC 类型排除这些 Node。

源码位置：

- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:180-201`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:298-304`

### 4. Node 必须具有 Product ID 才会生成页面类别

页面构建 `firmwareTypeDatas` 时，只处理 `node.productIdentifier` 非空的 Node。Product ID 为空时，即使 Node 已经传入页面，也不会生成任何设备类别或设备条目。

源码位置：

- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:563-608`

这也是“Gateway 已在 Site 中，但 Firmware Update 页面完全没有它”的高优先级原因。

## 二、广播扫描过滤规则

页面调用本地 `NordicSigMeshSDK` 的 `refreshNodesRSSI`。当前工程使用的是本地 SDK 路径：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

### 1. CoreBluetooth Service 过滤

扫描只指定 Bluetooth Mesh Proxy Service，不扫描任意 BLE 广播，也不扫描未配网的 Mesh Provisioning Service。

SDK 源码位置：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:485-492`
- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:534`

因此设备必须广播 Mesh Proxy Service，才能走普通广播反查路径。

### 2. Mesh 网络身份过滤

扫描到 Proxy 广播后，必须满足以下二选一规则：

1. 广播含 Network Identity：既要匹配当前 Mesh Network，也要匹配当前选中的 Network Key；
2. 没有 Network Identity 时：必须含 Node Identity 或 Private Node Identity，并能使用当前 Network Key 在当前 Mesh Network 中验证通过。

否则广播会被当成其他 Mesh 网络的设备丢弃。

SDK 源码位置：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:538-553`
- `Sources/NordicSigMeshSDK/nRFMeshProvision/Utils/Beacon.swift:92-123`
- `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/NetworkIdentity.swift:48-131`

需要特别注意：这里只匹配当前 `currentNetworkKey`。即使广播属于同一个 Mesh Network，只要 4G Gateway 当前广播身份来自另一个子网 Key，也不能进入后续 MAC 匹配。

### 3. 广播必须能解析出 MAC

网络身份通过后，SDK 使用 `ProvisioningDevice` 解析 MAC，规则为：

- 优先读取 Manufacturer Data；长度至少 10 字节；第 4 到第 9 字节反序后作为 MAC；
- Manufacturer Data 不满足时，才回退到设备名；设备名必须刚好 20 个字符，并以当前 `CompanyId.hex` 开头，后 12 个字符用于解析 MAC。

SDK 源码位置：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift:1074-1147`

普通 Manufacturer Data 路径没有按 Gateway PID 过滤，也没有要求 CID 必须等于 Sunricher Company ID；这里真正影响反查的是数据长度和 MAC 字节布局。

### 4. 广播 MAC 必须匹配已入网 Node

解析出 MAC 后，只在当前 `realNodes` 中查找：

- `node.macAddress == 广播解析 MAC`；或
- `node.macAddress == device.oldMacAddress`。

匹配不到已保存 Node 时，即使 Mesh 网络身份验证成功，也不会回调页面。

SDK 源码位置：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:555-569`

需要注意：`device.oldMacAddress` 只在 20 字符设备名回退路径中赋值；当广播走 Manufacturer Data 路径时，它通常为空。如果 4G Gateway 的数据库 MAC 与 Manufacturer Data 的字节序约定不一致，当前普通广播路径没有再做一次旧 MAC 转换，会直接匹配失败。

### 5. App 页面还有一次地址白名单匹配

SDK 回调 Node 后，页面还要求回调 Node 的 `primaryUnicastAddress` 存在于进入页面时传入的 `nodes` 中。否则忽略该广播结果。

源码位置：

- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:442-445`

所以附近同一 Mesh 网络中的其他节点即使广播完全合规，也不会被动态加入这个 Gateway 页面。

### 6. 已连接 Proxy 是另一条 RSSI 来源

当前本地 SDK 工作区还包含未提交的 Proxy RSSI 刷新改动：对于已打开的 Proxy 连接，SDK 会主动 `readRSSI`，再优先按 Proxy 的 Node Address、其次按 Proxy MAC 反查 Node。

SDK 源码位置：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:573-619`

这条路径不依赖新的广播包通过上述 Network Identity 与 Manufacturer Data 过滤，但最终仍受页面传入 Node 地址白名单限制。

## 三、展示与“可升级”的区别

广播成功不会创建新的页面条目，只会为已有 Node 写入 `peripheral` 和 RSSI。

设备要变为可勾选，还必须同时满足：

1. 本地已有该 Product ID 的固件包；
2. 当前版本与目标版本通过 BLE batch-aware 版本策略判定为可升级；
3. 已从广播或已连接 Proxy 获得 RSSI；
4. RSSI 大于等于 -80 dBm。

任一条件不满足，设备仍可展示，但会处于禁用状态。

源码位置：

- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:423-466`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:563-604`

## 四、4G Gateway 是否被型号规则排除

没有。当前设备配置中明确存在多组 4G Gateway：

- CID `0A78`、PID `1701`
- CID `0A78`、PID `1702`
- CID `0A78`、PID `2701`
- CID `0A78`、PID `2702`
- CID `0A78`、PID `2711`

它们的 `deviceCategory` 都是 `Gateway`，型号为 `SR-BL9036T-GW-WP4G`。

配置位置：

- `SunSmart/devices_config.json:653-661`
- `SunSmart/devices_config.json:1054-1071`
- `SunSmart/devices_config.json:1152-1160`
- `SunSmart/devices_config.json:1233-1241`

因此，现有源码没有“Wi-Fi Gateway 可展示、4G Gateway 不展示”的显式产品类型过滤。

## 五、针对当前 4G Gateway 的排查优先级

### A. 如果页面中完全没有该 Gateway

按以下顺序核对：

1. 当前账号是否为 Site Owner；若不是，检查该 Gateway 的 `associatedSpaces` 是否为空；
2. `GatewayModel.load(siteId:)` 是否能加载到这台 Gateway；
3. GatewayModel 的地址能否在 Site 主 Mesh 网络解析到 Node；
4. 解析到的 Node 是否有 `productIdentifier`；
5. Product ID 是否为设备真实 PID，而不是导入或 Composition 数据缺失后的空值。

这五项都发生在广播扫描之前。

### B. 如果页面有 Gateway 条目，但没有信号或不能勾选

按以下顺序核对：

1. 广播是否包含 Mesh Proxy Service；
2. Proxy Service Data 是 Network Identity、Private Network Identity、Node Identity，还是不支持的其他格式；
3. 广播身份是否匹配 App 当前 `currentNetworkKey`；
4. Manufacturer Data 是否至少 10 字节；
5. Manufacturer Data 第 4 到第 9 字节反序后的 MAC 是否等于 Node 保存的 `macAddress`；
6. 是否存在 MAC 新旧字节序不一致；
7. 本地是否已有该 PID 的固件包，版本是否被判定为可升级；
8. RSSI 是否达到 -80 dBm。

## 六、证据边界

本次结论来自当前 App 与本地 SDK 源码静态追踪，没有使用该 4G Gateway 的真实广播包、App DEBUG 日志或真机抓包。因此可以确认现行过滤规则及不存在显式 4G/PID 排除，但不能仅凭源码确认这台具体设备最终命中了哪一条过滤条件。

当前 DEBUG 日志 `Found: ... refresh node mac ...` 位于网络身份、MAC 解析和 Node MAC 匹配全部通过之后。看不到该日志只能说明广播没有走到最终成功点，不能单靠这条日志区分是 Service、网络身份、MAC 解析还是 MAC 匹配失败。
