# App CCT Support Analysis

## 结论

当前 App 判断设备是否支持 CCT 功能的核心条件是：节点的 Mesh Composition Data 中是否包含 SIG Model `Light CTL Temperature Server`，也就是代码里的 `node.temperatureModel != nil`。

这不是基于设备名称、PID、设备类型或云端产品能力表判断，而是基于节点元素里的 SIG Model 列表解析结果判断。

## 判断来源

`temperatureModel` 定义在本地 `NordicSigMeshSDK` 的 `Node+SupportModels.swift` 中。它通过 `getFunctionModel(modelId: .lightCTLTemperatureServerModelId)` 在节点所有 `elements` 中查找对应 SIG Model。

相关 Model ID：

- `Light Lightness Server`: `0x1300`
- `Light CTL Server`: `0x1303`
- `Light CTL Setup Server`: `0x1304`
- `Light CTL Temperature Server`: `0x1306`

因此，只要设备 Composition Data 的任意 Element 包含 `0x1306`，App 就认为该节点支持色温/CCT。

## Composition Data 解析链路

设备配网或读取 Composition Data 后，SDK 在 `Element.init(compositionData:offset:)` 中解析 Element：

- 读取 SIG Model 数量。
- 按 2 字节读取每个 SIG Model ID。
- 创建 `Model(sigModelId:)` 并加入 Element。

后续 `Node.temperatureModel` 就是在这些 Element Model 中查找 `0x1306`。

## App 内主要使用点

设备详情/控制页：

- `DeviceLightViewController.updateUI()` 使用 `node.temperatureModel != nil` 决定是否显示 CCT 滑块和色温视图。
- `DeviceLightBasicController` 使用同一条件决定控制区是 1 行亮度，还是 2 行亮度 + CCT。
- `DeviceLightHeaderView` 和 `DevicesViewCell` 使用同一条件决定是否显示色温百分比和 CCT 颜色。

组控制：

- `Group.supportCct` 判断组内是否存在任一 `temperatureModel != nil` 的节点。
- `GroupViewController` 根据组内是否有支持 CCT 的节点显示或隐藏组色温滑块。
- `DeviceLightsViewController.deviceAllSetting()` 根据当前设备列表是否存在支持 CCT 的设备，决定批量控制面板是否包含 CCT。

场景/同步：

- 场景下发时，如果节点同时有 `ctlModel` 且 `temperatureModel != nil`，使用 `LightCTLSet` 同时设置亮度和色温。
- 如果没有 CCT，则退化为只下发亮度 `LightLightnessSet`，再不支持亮度则退化为开关 `GenericOnOffSet`。

状态读取和控制：

- `MeshAPI.getNodeState()` 只有在 `node.temperatureModel != nil` 时才读取 `LightCTLTemperatureGet`；如果有 `ctlModel` 且未缓存色温范围，还会先读取 `LightCTLTemperatureRangeGet`。
- `MeshAPI.setNodeColorTemperatureState()` 也先判断 `node.temperatureModel`，存在才发送 `LightCTLTemperatureSet` 或 `LightCTLTemperatureSetUnacknowledged`。

## 色温范围不是能力判断

`lightCTLTemperatureRange` 只是 CCT 数值范围，用于滑块上下限和 0~100 百分比转换。它不是“是否支持 CCT”的判断依据。

添加设备、恢复设备时，如果 `ctlModel != nil && temperatureModel != nil`，App 会追加 `LightCTLTemperatureRangeGet()` 去获取范围；如果没拿到范围，则使用默认 `2700...6500`。

## 关键注意点

当前逻辑隐含要求：仅有 `Light CTL Server` 还不够，必须有 `Light CTL Temperature Server` 才被 App 视为支持 CCT。部分下发场景还同时要求 `ctlModel != nil`，例如场景同步使用 `LightCTLSet` 时需要 `ctlModel` 和 `temperatureModel` 都存在。

