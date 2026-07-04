# Proxy 后灯控命令 TTL 分析

## 结论

- 当前 App 连接 Proxy 后，普通灯控的 on/off、brightness/level、CCT 命令没有在 App 调用点单独指定 TTL。
- 这些命令统一进入 `MeshAPI.sendMessage(..., defaultTTL: nil)`，再进入 `MeshMessageManager` 队列，最终发送时 `withTtl` 仍为 `nil`。
- SDK 最终使用的 TTL fallback 顺序是：
  1. 调用方显式传入的 `defaultTTL`
  2. 本地 Provisioner Node 的 `defaultTTL`
  3. `networkParameters.defaultTtl`
- 当前 SDK 初始化时把 `networkParameters.defaultTtl` 设置为 `5`。因此在没有本地 Provisioner Node 覆盖值的常规情况下，灯控命令 TTL 是 `5`。
- Proxy 连接本身只作为发送条件存在：`MeshMessageManager` 要求 `MeshLibManager.manager.currentProxy != nil` 才发送队列消息；Proxy 连接不单独改变 TTL。

## 命令入口

`DeviceLightsViewController` 的 Lights 列表 item on/off：

- 在线设备 tap 后进入 `sendLightItemOnOffCommand(node:)`
- 默认路径调用 `MeshAPI.setNodeOnOffState(address:isOn:ack: true)`
- Lab ACK 详情开关打开时，直接构造 `GenericOnOffSet` 再交给 `LightAckProgressTracker`，仍不传 TTL

`DeviceLightViewController` 的灯详情页：

- on/off：`MeshAPI.setNodeOnOffState(..., ack: true)` -> `GenericOnOffSet`
- brightness / level：`MeshAPI.setNodeLightnessState(..., ack: true)` -> `LightLightnessSet`
- 拖动 brightness 未结束时：`MeshAPI.setNodeLightnessState(..., ack: false)` -> `LightLightnessSetUnacknowledged`
- CCT：`MeshAPI.setNodeColorTemperatureState(..., ack: true)` -> `LightCTLTemperatureSet`
- 拖动 CCT 未结束时：`MeshAPI.setNodeColorTemperatureState(..., ack: false)` -> `LightCTLTemperatureSetUnacknowledged`

这里用户口中的 `level`，在普通 Light 页面实际对应 Light Lightness 模型，不是 Generic Level Set。仓库里有 Generic Level delegate/model 支持，但当前普通灯控入口没有发送 `GenericLevelSet`。

## 统一接口管理情况

灯控命令是统一经过 SDK 的 `MeshAPI` 和 `MeshMessageManager` 管理的：

1. 页面调用 `MeshAPI.setNodeOnOffState` / `setNodeLightnessState` / `setNodeColorTemperatureState`
2. `MeshAPI` 选择 ACK 或 unack message，并调用 `sendMessage`
3. `sendMessage` 创建 `MeshMessageHandle(message:model/address:defaultTTL:)`
4. `MeshMessageManager` 队列按 200 ms 间隔发送，并把 `messageHandle.defaultTTL` 传给 `MeshNetworkManager.send(..., withTtl:)`
5. Lower Transport 层最终解析 TTL

这套接口支持按消息覆盖 TTL，因为 `MeshAPI.sendMessage` 有 `defaultTTL` 参数，`MeshMessageHandle` 也保存 `defaultTTL`。但当前普通灯控调用没有使用这个覆盖能力。

## TTL 计算链路

发送队列传下去的是：

- `MeshMessageHandle.defaultTTL`
- 普通灯控调用点没有传值，所以是 `nil`

Lower Transport 层最终使用：

`initialTtl ?? provisionerNode.defaultTTL ?? networkManager.networkParameters.defaultTtl`

当前 SDK 初始化配置：

- `MeshLibManager.initConfig()` 中执行 `parameters.setDefaultTtl(5)`
- `NetworkParameters.defaultTtl` 默认值本身也是 `5`

所以普通情况下，on/off、brightness/lightness、CCT 的网络层 TTL 都是 `5`。

## 例外和边界

- 如果本地 mesh 数据里 Provisioner Node 的 `defaultTTL` 有持久化覆盖值，则会优先于 `networkParameters.defaultTtl`。
- 如果未来某个调用显式传 `defaultTTL`，会优先于 Provisioner Node 和全局默认值。
- 这次只分析普通灯控命令。部分其他功能已经显式传 TTL，例如 SDK heartbeat/report 相关路径里存在 `defaultTTL: 0` 的用法，这不代表普通灯控也使用 TTL 0。
