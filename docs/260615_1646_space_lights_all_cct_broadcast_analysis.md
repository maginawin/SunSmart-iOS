# Space Main Lights All 控制弹窗广播行为分析

## 问题结论

- 亮度当前发送的是广播命令。
- 色温当前不是广播命令，而是对每个支持 CCT 的灯逐台发送单播命令。
- 因此“亮度变化效果一致、色温变化效果不一致”的问题真实存在，根因在发送路径不一致。

## 当前入口

页面入口是 `Site > Space > Main > Lights`，对应 `DeviceLightsViewController`。

长按 collection view 的第 0 个 cell，也就是 All 控制按钮时，会进入 `deviceAllSetting()`，展示 `DeviceLightControlView` 弹窗。弹窗里亮度和色温 slider 都通过 throttle 回调交给 `DeviceLightsViewController`。

## 亮度发送链路

`DeviceLightControlView` 的亮度 slider 触发：

- `DeviceLightControlView.valueThrottleChangedCallback`
- `DeviceLightsViewController.lightControl(_:levelValueChanged:ended:)`
- `MeshAPI.setAllLightnessState(lightness:)`
- SDK 内部发送 `LightLightnessSetUnacknowledged` 到 `.allNodes`

`.allNodes` 是 `0xFFFF`，属于所有节点广播地址。因此亮度是单条广播控制命令。

## 色温发送链路

`DeviceLightControlView` 的色温 slider 触发：

- `DeviceLightControlView.valueThrottleChangedCallback`
- `DeviceLightsViewController.lightControl(_:cctValueChanged:ended:)`
- `devices.filter({ $0.effectiveSupportCct })`
- 对每个 CCT 节点执行 `MeshAPI.setNodeColorTemperatureState(address: $0.primaryUnicastAddress, temperature: nodeTemperature)`
- SDK 内部通过节点的 `temperatureModel` 发送到该节点 model

这里的目标地址是每台设备的 `primaryUnicastAddress`，不是 `.allNodes`。所以色温是多条单播控制命令。

## 为什么表现不一致

亮度使用一条广播包，所有灯在同一次 mesh 控制消息下响应，视觉效果天然更同步。

色温对每台设备循环单播，命令会按节点顺序逐条入队和发送。设备收到命令的时间不同，mesh 转发、ack 配置、队列调度和重传都会放大这种时间差，所以视觉上会出现不一致。

## 修复方向

若预期是“亮度和色温都发送广播命令，使设备变化效果一致”，最直接的收口点是 `DeviceLightsViewController.lightControl(_:cctValueChanged:ended:)`：

- 发送层从逐台 `setNodeColorTemperatureState(address: primaryUnicastAddress, ...)` 改为 `MeshAPI.setAllColorTemperatureState(temperature:)`。
- 保留本地 UI 状态更新，对支持 CCT 的节点更新 `temperature` 后刷新列表。

需要注意一个取舍：当前 All 弹窗的 CCT 范围是所有支持 CCT 设备 `effectiveCctRange` 的并集，旧逻辑会对每台设备单独 `clampEffectiveCct`。改成一条广播后，App 侧不能为不同设备发送不同 clamp 值；如果同一 Space 内设备 CCT 范围不一致，需要确认是接受设备端自行处理越界，还是把 All 弹窗范围改成所有设备范围的交集。

