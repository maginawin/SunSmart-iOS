# BLE Scan Log Simplification Plan

## 背景

当前查找设备时控制台会打印完整 `advertisementData`，内容很长，并且 `refresh node mac` 被拆成另一行。实际排查时常用信息通常是设备名、RSSI，以及在已入网节点场景下匹配到的节点 MAC。

期望输出压缩为单行，例如：

`Found: SR Dongle, rssi: -45, refresh node mac: E46176326A7B`

## 代码事实

- 完整广播日志来自本地 `NordicSigMeshSDK` 的 `MeshLibManager.centralManager(_:didDiscover:advertisementData:rssi:)`。
- `refresh node mac` 日志来自同一个文件的 `refreshNodesRSSI(...)` 扫描结果闭包中，且只有在广播通过当前 Mesh 网络匹配，并成功解析到 `ProvisioningDevice.macAddress` 后才会打印。
- Add Device 入口通过 `MeshAPI.startScanDevice(...)` -> `MeshAddDeviceManager.startScan(...)` -> `MeshLibManager.scanDevice(...)` 扫描未入网设备。这个场景不需要、也不应该匹配当前 Mesh 节点。
- OTA 有两类扫描：
  - 固件页刷新设备 RSSI 时会走 `MeshLibManager.refreshNodesRSSI(...)`。
  - 实际 OTA 连接目标时，`MeshFirmwareUpdateOperation` 使用独立 `CBCentralManager` 扫描 `MeshProxyService`，按 `advertisementData.macAddress == updateNode.macAddress` 匹配目标。
- 当前 App 工程已经通过本地 Swift Package 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，因此 SDK 侧修改可直接被 App 构建验证。
- `MeshLibManager.showLogs` 目前用于 nRF Mesh logger 分类，没有扫描专用分类；为这次日志优化扩展分类会扩大改动面。

## 方案选项

### 方案 A：按扫描场景统一输出短日志

做法：

- 移除或禁用 `MeshLibManager.didDiscover` 中完整 `advertisementData` 的 DEBUG 打印。
- 在 SDK 内增加一个私有短日志格式 helper，统一解析设备名：
  - 优先 `advertisementData[CBAdvertisementDataLocalNameKey]`。
  - 其次 `peripheral.name`。
  - 都为空时使用 `Unknown`。
- Add Device / 普通未入网扫描：在 `MeshAddDeviceManager.startScan(...)` 成功生成 `ProvisioningDevice` 且有 `macAddress` 后输出：
  - `Found: <name>, rssi: <rssi>, mac: <mac>`
- 已入网节点 RSSI refresh：在 `refreshNodesRSSI(...)` 成功匹配当前 Mesh 节点后输出：
  - `Found: <name>, rssi: <rssi>, refresh node mac: <mac>`
- OTA 实际连接目标：在 `MeshFirmwareUpdateOperation.didDiscover(...)` 匹配 `updateNode.macAddress` 后输出：
  - `Found OTA target: <name>, rssi: <rssi>, mac: <mac>`

优点：

- Add Device 不依赖当前 Mesh 节点匹配，符合未入网扫描语义。
- RSSI refresh 仍只在确认当前 Mesh 节点后输出 `refresh node mac`，避免误导。
- OTA 目标扫描也能简化，并且能看出是 OTA target。
- 所有场景都不打印完整 `advertisementData`，控制台噪音最低。

风险：

- 需要改动 SDK 中 2-3 个扫描位置，而不是只改一个 `print`。
- 如果某个页面依赖公共 `didDiscover` 的完整原始广播排查问题，需要临时恢复详细日志或另加开关。

### 方案 B：只替换公共 `didDiscover` 为短日志

做法：

- 将公共 `didDiscover` 的完整 advertisement 打印替换成短日志。
- `refreshNodesRSSI`、Add Device、OTA 业务闭包保持现状。

优点：

- 改动最小。
- Add Device 等走 `MeshLibManager.scanDevice(...)` 的入口会变短。

风险：

- 公共扫描阶段还不知道是否匹配到当前 Mesh 节点，也拿不到最终 `refresh node mac`。
- OTA 实际连接目标不走 `MeshLibManager.didDiscover`，覆盖不到。
- 仍可能出现两行日志，达不到你期望的“一行包含全部信息”。

### 方案 C：新增扫描日志开关或分类

做法：

- 在 SDK 中新增 BLE scan log 开关或扩展 logger 分类。
- 需要时打开短日志，不需要时关闭，也可以选择是否打印完整 advertisement。

优点：

- 后续排查可以灵活打开/关闭。

风险：

- 需要新增公开配置或扩展 `LogCategory`，影响 SDK API 面。
- 对这次“一行日志”目标偏重。

## 推荐方案

推荐使用方案 A。

理由：

- Add Device 是未入网扫描，不应该要求匹配当前 Mesh 节点；方案 A 会在生成 `ProvisioningDevice` 后直接输出短日志。
- `refresh node mac` 只在已入网节点 RSSI refresh 中可靠；方案 A 保留这个语义。
- OTA 实际目标扫描不走公共 `MeshLibManager.didDiscover`；方案 A 会补到 OTA 自己的匹配点。
- 相比新增公开日志开关，方案 A 不扩大 SDK API 面。

## 实施边界

- 修改范围：
  - `NordicSigMeshSDK/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
  - `NordicSigMeshSDK/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift`
  - `NordicSigMeshSDK/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareUpdateManager.swift`
- 不修改 App UI、扫描时长、过滤规则、回调数据结构、入网逻辑或连接逻辑。
- 不新增 Auth 信息。
- 不调整资源、target 配置或依赖。

## 验证计划

- 静态检查确认旧的完整 `advertisementData` 打印不再存在。
- 静态检查确认 Add Device、RSSI refresh、OTA target 三类路径都有短日志输出点。
- 运行本地 SDK 构建或 App iPhoneOS 构建，优先使用项目约定的 `xcodebuild` iPhoneOS 命令。
- 如有设备可现场扫描，确认日志变为一行，并且格式为：

`Found: SR Dongle, rssi: -45, refresh node mac: E46176326A7B`

Add Device 场景格式为：

`Found: SR Dongle, rssi: -45, mac: E46176326A7B`

OTA 目标连接场景格式为：

`Found OTA target: SR Dongle, rssi: -45, mac: E46176326A7B`

## 待确认

请确认是否按方案 A 实施。

如果你希望所有场景使用完全相同的前缀 `Found:`，OTA 也可以不加 `OTA target`，但我建议保留这个标识，便于区分 OTA 目标连接扫描和普通设备查找。
