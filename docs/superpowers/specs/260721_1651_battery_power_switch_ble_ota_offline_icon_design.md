# Battery Power Switch BLE OTA 离线图标优化设计

## 背景

入口为 Site → Space → More → Firmware update via BLE，页面由 `SpaceMoreViewController` 进入 `BleFirmwareUpdateViewController`，设备行由 `BleFirmwareUpdateDeviceCell` 展示。

当前设备行以 `Node.rssi` 是否为空判断本轮 BLE 扫描是否找到设备：

- `rssi` 非空时，Battery Power Switch 展示 `device_BatteryPowerSwitch`。
- `rssi` 为空时，仍加载 `device_BatteryPowerSwitch`，仅使用次级文字颜色染色。

因此当前离线状态没有使用项目已有的 `device_offline_BatteryPowerSwitch` 资源。

## 目标

- Battery Power Switch 在线时继续展示 `device_BatteryPowerSwitch`。
- Battery Power Switch 未被 BLE 扫描找到时展示 `device_offline_BatteryPowerSwitch`。
- AC Power Switch 和其他设备维持现有展示行为。
- 不改变 BLE 扫描、RSSI、设备选择及固件升级流程。

## 非目标

- 不统一其他设备的离线图标策略。
- 不修改 AC Power Switch 的离线图标。
- 不新增或修改图片资源。
- 不修改本地化、target 配置、依赖或 NordicSigMeshSDK。

## 方案选择

采用方案 A：在 `BleFirmwareUpdateDeviceCell` 的现有离线分支中增加 Battery Power Switch 窄特判。

未采用以下方案：

- 全部设备离线时统一使用 `offlineIconName`：会扩大行为影响面。
- 新增独立图标状态策略层：对本次单一特判属于过度设计。

## 详细设计

### 图标选择

保持现有在线判定标准不变：

- 在线分支：继续通过现有 `bleFirmwareIconName` 加载图标。
- 离线分支：
  - Battery Power Switch 通过 `Node.offlineIconName` 加载离线图标；其设备配置的 `iconCategory` 为 `BatteryPowerSwitch`，最终解析为 `device_offline_BatteryPowerSwitch`。
  - 其他设备继续使用现有在线图标染灰逻辑。

### 资源失败回退

若 `device_offline_BatteryPowerSwitch` 因资源异常加载失败，则回退到当前的灰色 `device_BatteryPowerSwitch`，避免设备图标为空。

### 数据流

1. 刷新开始时，Controller 将节点的 RSSI 清空。
2. BLE 扫描找到设备后，节点获得 RSSI。
3. Cell 根据 RSSI 是否为空进入在线或离线展示分支。
4. 仅在离线且节点为 Battery Power Switch 时切换到离线资源。

该设计不会改变扫描结束条件、升级可用性、选择状态或设备排序。

## 影响范围

预计只修改：

- `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`

已有资源直接复用：

- `SunSmart/Assets.xcassets/Device/device_BatteryPowerSwitch.imageset`
- `SunSmart/Assets.xcassets/Device/device_offline_BatteryPowerSwitch.imageset`

## 验证方案

### 静态验证

- 确认 Battery Power Switch 在线分支仍使用在线图标。
- 确认 Battery Power Switch 离线分支使用 `offlineIconName`。
- 确认非 Battery Power Switch 的离线逻辑保持不变。
- 确认在线、离线 Battery Power Switch 资源均存在且 `Contents.json` 合法。
- 运行 `git diff --check`。

### 构建验证

- 使用 SunSmart Debug、iPhoneOS、关闭签名的方式运行 `xcodebuild`。

### 运行时验收

- 进入 Site → Space → More → Firmware update via BLE。
- Battery Power Switch 被扫描到时显示 `device_BatteryPowerSwitch`。
- Battery Power Switch 未被扫描到时显示 `device_offline_BatteryPowerSwitch`。
- AC Power Switch 和其他设备离线图标与当前版本一致。

## 成功标准

- Battery Power Switch 在线/离线状态使用指定的两套资源。
- 本次改动不影响其他设备类型和 BLE OTA 业务流程。
- 静态检查与 SunSmart iPhoneOS 构建通过。
