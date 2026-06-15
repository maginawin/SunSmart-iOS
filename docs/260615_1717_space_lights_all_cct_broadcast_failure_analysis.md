# Space Lights All 色温广播失效原因分析

## 结论

刚刚把 All 色温从逐台单播改成 `MeshAPI.setAllColorTemperatureState(temperature:)` 后，App 无法控制色温，根因是广播地址选错了。

亮度使用 `.allNodes` 广播可行，是因为 Light Lightness Server 通常在 Primary Element。色温使用 `.allNodes` 不可行，是因为 Light CTL Temperature Server 可能在非 Primary Element，而 SDK 明确只让 Primary Element 上的 model 处理 `.allNodes` 消息。

## 旧色温方式为什么有效

旧代码在 `DeviceLightsViewController.lightControl(_:cctValueChanged:ended:)` 中：

1. 筛选 `cctNodes = devices.filter({ $0.effectiveSupportCct })`。
2. 对每台设备计算 `nodeTemperature = node.clampEffectiveCct(temperature)`。
3. 调用 `MeshAPI.setNodeColorTemperatureState(address: node.primaryUnicastAddress, temperature: nodeTemperature)`。

虽然调用参数传的是 `primaryUnicastAddress`，但 SDK 内部并不是直接把 `LightCTLTemperatureSet` 发到 primary address。`setNodeColorTemperatureState` 会通过节点查到 `node.temperatureModel`，然后调用 `sendMessage(message:model:)`。

SDK 的 model 发送路径会使用 `model.parentElement.unicastAddress` 作为目的地址。因此旧方式实际能打到 Light CTL Temperature Server 所在的 element，即使它不在 Primary Element 也能控制成功。

## 新色温方式为什么失效

新代码调用：

```swift
MeshAPI.setAllColorTemperatureState(temperature: temperature)
```

SDK 内部会发送 `LightCTLTemperatureSetUnacknowledged` 到 `.allNodes`。

问题在接收规则：SDK `AccessLayer` 注释和判断写明，发到 `.allNodes` 的消息只由 Primary Element 上的 model 处理。若设备的 Light CTL Temperature Server 在子 element，子 element 不会处理 `.allNodes` 上的 `LightCTLTemperatureSetUnacknowledged`，所以设备不会改变色温。

## 项目已有的正确广播机制

项目已经为这类子 element 控制准备了专门的广播组：

- `SiteViewController` 配置 `MeshLibManager.manager.subElementGroupSubscriptionModelIDs = [.lightCTLTemperatureServerModelId, .lightLCServerModelId]`。
- SDK 同步配置时，会让非 Primary Element 上的这些 model 订阅 `.subElementBroadcastGroup`。
- 地址常量是 `.subElementBroadcastGroupAddress`，值为 `0xFEFD`。
- 同一个 All 弹窗的 Auto 控制已经用 `LightLCLightOnOffSetUnacknowledged(true)` 发到 `.subElementBroadcastGroupAddress`。

因此这里的“广播”不能简单等同于 `.allNodes`。对 CCT Temperature Server，应使用子 element 广播组，或同时兼容 primary/secondary 两种 element 布局。

## 修复方向

推荐把 All 色温发送改为：

```swift
MeshAPI.sendMessage(
    message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0),
    address: .subElementBroadcastGroupAddress
)
```

本地 UI 状态更新仍保留当前逻辑：只更新 `effectiveSupportCct` 的节点，并按各自 `effectiveCctRange` clamp 展示值。

如果担心有少数设备把 Light CTL Temperature Server 放在 Primary Element 且没有订阅 `0xFEFD`，可以考虑同时发送 `.allNodes` 和 `.subElementBroadcastGroupAddress`，但这会带来重复控制和 TID/时序副作用，需要谨慎验证。就当前项目配置看，优先应改为子 element 广播组。

## 已采用的修复

`DeviceLightsViewController.lightControl(_:cctValueChanged:ended:)` 已改为发送：

```swift
MeshAPI.sendMessage(
    message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0),
    address: .subElementBroadcastGroupAddress
)
```

本地 UI 状态更新仍只作用于 `effectiveSupportCct` 节点，并继续按各自 `effectiveCctRange` clamp 展示值。
