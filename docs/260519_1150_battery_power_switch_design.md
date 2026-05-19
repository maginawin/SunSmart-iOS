# Battery Power Switch 设备接入设计

## 背景

`devices_config.json` 新增两个 Battery Power Switch 设备：

- `0x2A01`: `SR-BL2422K8N-4SC(US)`
- `0x2A02`: `SR-BL2422K8N-4DIM(US)`

这两个设备需要在 App 中解析为开关类设备，在添加页、Site / Space 页面、主页开关分类中按 Switch 展示，并使用 `device_BatteryPowerSwitch` 图标资源。设备是 Low Power 节点，但在 Add 和 BLE Direct OTA 时允许临时 BLE 连接；其他场景不允许连接，且成功后必须主动断开。

## 目标

1. 两个 PID 在扫描、添加、展示、默认命名中走现有 Switch 规则。
2. 添加页中展示在开关分类下。
3. 添加成功后自动创建对应 `DeviceSwitchData`，展示在主页开关页，并计入 16 个开关上限。
4. 当当前 Space 的开关数量已达 16 时，在添加前禁止选择或添加这两个设备。
5. 添加配置过程中为该设备所有需要 AppKey 的 Models 绑定当前 Space 的 AppKey。
6. 仅 Add 与 BLE Direct OTA 允许连接这两个设备；Add 成功和 OTA 成功后主动断开 BLE 连接。
7. 保持改动聚焦，不影响其他 Lighting、Gateway、Dongle、EmergencyController、普通 Switch 流程。

## 设备识别与配置

采用配置驱动方案，在 `devices_config.json` 中为 `0x2A01` 和 `0x2A02` 增加记录：

- `deviceCategory` 使用 `Switches`，复用现有 `Node.DeviceType.switches` 映射。
- `iconCategory` 使用 `BatteryPowerSwitch`，使现有 `device_\(iconCategory)` 规则解析到 `device_BatteryPowerSwitch`。
- `categoryName` 使用 `Battery Power Switch`。
- `elementCount` 使用 `8`。
- `modelName` 按 PID 分别保存真实型号。

默认名称延续已有 Switch 规则：节点默认名称使用 `SW` 前缀，虚拟开关数据使用现有 `DeviceSwitchData.default()` / `getNextSwitchName()` 规则。

## 添加页与上限限制

Classic Add 和 Professional Add 都需要识别 Battery Power Switch：

- 扫描到设备后按 `.switches` 类型进入开关分类。
- 设备可展示，但当 `MeshNetworkManager.instance.switchs.count >= 16` 时禁止选择或开始添加。
- 添加前拦截优先于真实入网，避免设备入网成功后无法创建开关数据。
- 上限提示复用现有开关上限提示文案。

如果未达到 16 个上限，添加流程继续执行。

## 添加成功后的数据创建

添加成功后，如果成功节点 PID 是 `0x2A01` 或 `0x2A02`：

1. 创建一条 `DeviceSwitchData`。
2. 保存到本地数据库。
3. 加入 `MeshNetworkManager.instance.switchs`。
4. 发送 `switchsRefreshNotificationName`，刷新主页开关页。
5. 更新 Space 中的开关数量统计。

该真实 Node 自身仍保存为 `.switches` 类型，用于设备列表、信息页、OTA 等基础能力；主页开关页展示的是自动创建的开关数据。

## AppKey 绑定策略

Battery Power Switch 的添加配置必须完成当前 Space AppKey 绑定：

- 配网后先读取 Composition Data。
- 添加当前 Space 的 `ApplicationKey`。
- 对该节点所有需要 AppKey 的 Models 执行 Model App Bind，而不是只使用现有灯具模型白名单。
- 任一必需 Model App Bind 失败，都视为此设备添加配置失败。

该规则仅作用于 PID `0x2A01` / `0x2A02`，不扩大到普通灯具、网关、传感器或其他开关设备。

## BLE 连接策略

Battery Power Switch 是特殊连接白名单设备。

允许连接的场景：

- Add：添加扫描、Identify、Provisioning、Key Bind、添加阶段必要初始化。
- BLE Direct OTA：`BleFirmwareUpdateViewController` 通过 `MeshFirmwareUpdateManager` 进行点对点升级。

禁止连接的场景：

- 自动 Proxy 连接。
- 手动选择已入网 Proxy。
- 设备控制、同步、校准、调试、普通 Mesh 消息发送中的直连。
- 非 Add / 非 BLE Direct OTA 的所有已入网 BLE Proxy 连接入口。

实现上应提供统一判断，避免 PID 判断散落，例如集中表达“是否 Battery Power Switch”和“当前连接原因是否允许”。SDK 中自动 Proxy 扫描和指定 `connectProxy(node:)` 都需要遵守该限制。

## 主动断开策略

成功路径必须主动断开：

- Add 成功后，如果节点 PID 是 `0x2A01` 或 `0x2A02`，完成 AppKey 绑定、开关数据创建和必要保存后，主动断开该节点 BLE 连接。
- BLE Direct OTA 成功后，如果成功节点 PID 是 `0x2A01` 或 `0x2A02`，主动断开该节点 BLE 连接。

失败、取消、页面退出时也建议释放连接，但本次验收的强制条件是 Add 成功和 OTA 成功后的主动断开。

## 影响范围

App 侧重点文件：

- `SunSmart/devices_config.json`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`

SDK 侧重点文件：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/NetworkConnection.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareUpdateManager.swift`

SDK 侧更新前必须先做现状核查：

- 检查 SDK 是否已经支持 `0x2A01` / `0x2A02` 的设备能力、Models、Key Bind 或 OTA 连接流程。
- 检查是否已有可复用的 Low Power / Proxy 过滤逻辑和断开连接接口。
- 如果 SDK 已经具备对应能力，App 侧应复用现有接口，不新增重复接口或重复设备类型。
- 仅当现有 SDK 能力无法满足 Add / BLE Direct OTA 白名单、自动 Proxy 禁连、成功后主动断开、全 Models AppKey 绑定时，才在 SDK 中补齐最小必要能力。

如果需要修改 SDK，应先将工程中的 `NordicSigMeshSDK` Swift Package 切换到本地路径，再验证所有引用该 SDK 的 target。

## 验证范围

1. `SunSmart` Debug iphoneos 编译通过。
2. `NordicSigMeshSDK` 相关测试或至少 Swift 编译通过。
3. 扫描 `0x2A01` / `0x2A02` 时显示在 Add 页开关分类。
4. 开关数量小于 16 时可添加，添加成功后主页开关页出现新开关。
5. 开关数量等于 16 时添加前禁止选择或添加 Battery Power Switch。
6. 添加配置中所有必需 Models 绑定当前 Space AppKey；绑定失败时添加失败。
7. Add 成功后断开该设备 BLE 连接。
8. 自动 Proxy 和手动 Proxy 不连接这两个 PID。
9. BLE Direct OTA 可连接并升级这两个 PID，OTA 成功后断开 BLE 连接。
10. 普通灯具、普通开关、Gateway、Dongle、EmergencyController 添加和 OTA 行为不回归。
11. SDK 变更前已完成现有能力核查；若 SDK 已支持对应能力，实现中不新增重复接口。

## 非目标

- 不新增独立 `Node.DeviceType.batteryPowerSwitch`。
- 不在 SDK 中新增已经存在且可复用的设备接口或重复能力。
- 不重构现有添加流程和 OTA 流程。
- 不修改无关品牌资源和本地化文案，除非实现时发现现有文案无法复用。
- 不改变普通 Low Power 设备的通用行为，除非它与这两个 PID 的连接限制共用同一 SDK 入口且必须修正。
