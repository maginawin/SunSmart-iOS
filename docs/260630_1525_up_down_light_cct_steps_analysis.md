# Up/Down Light Max Color Temperature / CCT Steps 读取链路分析

## 结论

当前 `nRF54L15-M3` 分支会在 `CID 0x0A78 / PID 0x2491` Up/Down Light 添加入网后读取该设备的 CCT steps 信息。

代码层对应的是 `SunricherVendorGet(function: .upDownLightDefaultCctSteps)`：

- Vendor get message opcode：`0xF1780A`
- Sunricher vendor model：`.vensorServerModelId = (0x0A78 << 16) | 0x01`
- Vendor payload：`[0x53, 0x01]`
- 读取结果被保存到 SDK 的 `Node.upDownLightDefaultCctSteps`

这个值当前不是作为独立 UI 设置展示，而是用于推导 Device Parameter Settings 里的 `Absolute CCT Range` 默认范围。

## 触发时机

读取发生在添加或恢复设备成功之后、最终 completion / notification 之前：

- Classic add：`DeviceAddClassicModeController` 的 `addFinish`
- Professional add：`DeviceAddProfessionalModeController` 的 `addFinish`
- Restore add：`DeviceRestoreViewController` 的 restore deferred flow 之后

三处最终都调用 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(...)`。

Reader 会先筛选 `supportsUpDownRatioControl` 的节点；App 侧这个判断是：

- `companyIdentifier == 0x0A78`
- `productIdentifier == 0x2491`

如果节点没有 Sunricher vendor model，则不会发送 GET，并直接保存 fallback steps `5`。

## 返回值处理

SDK 解析 `[0x53, 0x01, status, steps]` 这类返回时，只接受成功状态下的 steps `5` 或 `6`：

- steps `6`：保存为 `6`
- steps `5`：保存为 `5`
- 无返回、失败、不是 `.upDownLightDefaultCctSteps`、或其他 steps 值：归一为 `5`

保存路径有两层：

- Reader 回调中把 normalized steps 写入 `node.upDownLightDefaultCctSteps` 并 `savePropertys()`
- 通用消息接收路径 `Node.updateNodeStatus(message:source:)` 也会处理 `.upDownLightDefaultCctSteps(let steps)` 并落库

第二层能覆盖一种竞态场景：Reader callback 如果先匹配到其他 vendor status，后续真正的 steps status 仍可通过通用接收路径保存。

## 对 Absolute CCT Range 的影响

SDK 的默认范围规则在 `Node.defaultAbsoluteCctRange`：

- 对 `CID 0x0A78 / PID 0x2491`：
  - `upDownLightDefaultCctSteps == 6` 时，默认范围为 `2700K...6500K`
  - 其他情况，包括默认值、失败、未读到、steps `5`，默认范围为 `2700K...5000K`
- `defaultChangeControlPage` 仍是 `.tunableWhite`，不会因为该设备而变成 single white

Device Parameter Settings 页面初始化 `Absolute CCT Range` 行时，读取的是 `devices.first?.defaultAbsoluteCctRange`，所以：

- 如果添加入网后成功读到并保存 steps `6`，该页面默认 absolute CCT range 会变成 `2700K~6500K`
- 如果未读到或返回 steps `5`，会显示 `2700K~5000K`

另外，SDK 的 `effectiveCctRange` 对 Up/Down Light 有一个特殊保护：如果 steps 已经是 `6`，但之前的 `LightCTLTemperatureRangeGet` 把 legacy `2700K...5000K` 写进了 `absoluteCctRange`，`effectiveCctRange` 会让位给 `defaultAbsoluteCctRange`，也就是 `2700K...6500K`。这避免旧五步范围覆盖六步设备默认值。

但如果用户或同步流程设置了其他实际 absolute range，例如 `3000K...4500K`，仍然优先使用该显式范围，不会被 steps 默认值覆盖。

## 关键代码位置

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - `UpDownLightDefaultCctStepsReader`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Classic add 成功后读取
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Professional add 成功后读取
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - Restore 成功后读取
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - `upDownLightDefaultCctSteps` GET payload
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - `[0x53, 0x01]` 返回值解析
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
  - `upDownLightDefaultCctSteps`、`defaultAbsoluteCctRange`、`effectiveCctRange`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`
  - `upDownLightDefaultCctSteps` 落库与加载
