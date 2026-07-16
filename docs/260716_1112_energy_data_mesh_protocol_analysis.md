# Site - Space - More - Energy Data 协议分析

## 结论

Energy Data 页面向设备采集能耗时，使用的是 Bluetooth SIG Mesh 的标准 Sensor Model 协议，不是 Sunricher Vendor Model 私有协议。

具体消息为：

- 目标 Model：Sensor Server，SIG Model ID `0x1100`
- 请求消息：Sensor Get，Opcode `0x8231`
- 当前请求参数：空，即不指定 Property ID，要求目标 Element 返回其全部 Sensor 值
- 响应消息：Sensor Status，Opcode `0x52`
- 页面关注的标准 Device Property：
  - Total Device Energy Use：`0x006A`
  - Precise Total Device Energy Use：`0x0072`
  - SDK 解析时也兼容 Active Energy Loadside：`0x0080`

因此，“消息、Model、Opcode、Property 编码”都属于 SIG Mesh 标准体系；但设备是否实现和正确返回这些能耗 Property，仍取决于设备固件的 Sensor Server、Composition Data、Model 所在 Element 和 AppKey 绑定是否正确。

## App 调用链

1. `SpaceMoreViewController` 从 `Energy Data` 入口打开 `EnergyDataViewController`；SylSmart target 直接打开 `EnergyStaticDataViewController`。
2. `EnergyStaticDataViewController.readMeshDevicesEnergy()` 从当前 Mesh 网络筛选灯具节点，清空节点上一次的能耗缓存，然后进入 `ReadDevicesDataViewController(type: .harvestData)`。
3. `ReadDevicesDataViewController` 将每个设备的读取任务设置为 `DeviceReadParameterType.totalDeviceEnergyUse`。
4. `DeviceReadParameterType.getMessageHandles(node:)` 通过 `node.energyModel` 找到承载能耗 Property 的 Sensor Server Model，并创建 `SensorGet()`。
5. `SensorGet()` 未传 Property，因此 Access Payload 不包含 Property ID；目标 Element 应在 `Sensor Status` 中返回全部可用 Sensor 值。
6. SDK 解析 `Sensor Status` 后，将：
   - `0x006A` 保存为 `totalDeviceEnergyUse`；
   - `0x0072` 保存为 `preciseTotalDeviceEnergyUse`；
   - `0x0080` 兼容保存为 `totalDeviceEnergyUse`。
7. 页面将读取值转换并保存为本地静态能耗快照，再用于 Space、Group、Device 和 Time Series 展示。

补充说明：快照中的 `Maximum Rated Power` 来自节点已有的 `phaseEnergyConsumptions` 参数；本次 Energy Data 采集不会重新读取该参数。该参数若由 App 主动读取，走的是 `SunricherVendorGet(.phaseEnergyConsumption)` 厂商协议。也就是说，页面点击采集时新获取的累计能耗是 SIG Sensor 协议，页面同时引用的额定功率配置并非由这条 Sensor Get 实时取得。

## 标准协议与设备实现的边界

这是标准 SIG Mesh Sensor 协议，但不代表任意 SIG Mesh 灯具都天然支持 Energy Data。当前 App 只有在已识别到设备 Sensor Server 承载 `0x006A` 或 `0x0072` 时，才能得到 `node.energyModel` 并发送请求。

常见失败边界包括：

- 设备 Composition Data 中没有 Sensor Server Model；
- 能耗 Property 所在 Element 或 Model 布局与固件实际响应不一致；
- Sensor Server 没有绑定当前 Space AppKey；
- 固件没有实现 `0x006A` / `0x0072`，或以长度为 0 的 Sensor Status 表示 `Value is not known`；
- 设备只实现了其他能耗 Property，但 App 的 `energyModel` 识别规则没有将其作为入口 Property。

## 代码证据

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`：Energy Data 页面入口。
- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`：设备筛选、发起采集、清空缓存及保存结果。
- `SunSmart/Main/Space/Controller/ReadDevicesDataViewController.swift`：把采集任务映射为 `totalDeviceEnergyUse`。
- `SunSmart/Common/Data/Node+SyncData.swift`：创建 `SensorGet()`，没有调用 `SunricherVendorGet`。
- 本地 `NordicSigMeshSDK` 的 `Node+SupportModels.swift`：通过 `0x006A` 或 `0x0072` 定位能耗 Sensor Server Model。
- 本地 `NordicSigMeshSDK` 的 `SensorGet.swift`：Opcode `0x8231`，空参数表示读取目标 Element 的全部 Sensor 值。
- 本地 `NordicSigMeshSDK` 的 `SensorStatus.swift`：响应 Opcode `0x52`。
- 本地 `NordicSigMeshSDK` 的 `DeviceProperty.swift`：能耗 Property ID 定义。
- 本地 `NordicSigMeshSDK` 的 `Node+Messages.swift`：能耗值解析与节点缓存更新。
