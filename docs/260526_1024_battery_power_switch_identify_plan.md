# Battery Power Switch Identify 标准 SIG Mesh 静默发送规划

## 背景

- 页面：Battery Power Switch 监控页，控制器为 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`。
- 当前右上角菜单已有 `Identify` 项，但点击回调只有注释，没有发送 Mesh 命令。
- 调整后的目标命令为标准 SIG Mesh Health Model Identify/Attention 无回复命令：`AttentionSetUnacknowledged(attentionTimer: 6)`。
- Battery Power Switch 是 lower power energy 设备，Identify 不要求回复，也不做成功/失败 HUD 提示。
- Battery Power Switch 不使用 Sunricher 私有 identify 协议；私有协议主要用于灯光控制器。

## 当前代码依据

- `PJEightKeySwitchMonitorVC.moreAction()` 在非 unlinked virtual battery power switch 时展示 `Identify`。
- `PJEightKeySwitchMonitorViewModel.informationNode` 只在 `switchData.proxyNode?.isBatteryPowerSwitch == true` 时返回真实节点。
- SDK 的 `MeshAPI.identify(address:attentionTimer:ack:)` 默认 `ack == false`，会发送标准 SIG Mesh Health Model 的 `AttentionSetUnacknowledged(attentionTimer:)`。
- SDK 只有在 `ack == true` 时才会发送 `AttentionSet(attentionTimer:)`，这不符合本次“无回复、静默发送”的要求。
- 灯具页使用的 `SunricherVendorSet(function: .identify(...))` 是私有 identify 协议，不用于 Battery Power Switch。

## 确认方案

在 `PJEightKeySwitchMonitorVC` 内新增一个私有 `identifyAction()`，并让右上角菜单的 `Identify` 点击回调调用它。该方法只做标准 SIG Mesh Identify 静默发送，不等待回复。

发送路径：

- 通过 `viewModel.informationNode` 获取真实 battery power switch 节点。
- 调用 `MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)`。
- 保持 `ack` 使用默认值 `false`，实际发送 `AttentionSetUnacknowledged(attentionTimer: 6)`。
- 不设置 timeout，不注册 callback，不根据响应显示 HUD。
- 如果运行时拿不到 `informationNode`，直接返回，不做提示。

选择原因：

- 能严格满足“标准 SIG Mesh identify、无回复、静默发送”的要求。
- 直接复用 SDK 已有 `MeshAPI.identify` 封装，避免手写底层 message 选择逻辑。
- 不使用灯光控制器相关的 Sunricher 私有 identify 协议。
- 改动面只落在 Battery Power Switch 监控页，风险最小。

## 实施任务

- 修改 `PJEightKeySwitchMonitorVC.moreAction()` 中 `Identify` 菜单项的点击闭包，使用 `[weak self]` 并调用 `identifyAction()`。
- 在同一控制器内新增 `private func identifyAction()`。
- `identifyAction()` 先校验 `viewModel.informationNode`，失败时直接返回。
- 校验通过后调用 `MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)`，不传 `ack` 参数。
- 不增加成功提示、失败提示、timeout 或 response callback。
- 不改菜单展示条件：仍只在非 unlinked virtual battery power switch 时展示 Identify。

## 验证计划

- 静态检查：确认 `PJEightKeySwitchMonitorVC.swift` 已引入 `NordicSigMeshSDK`，无需新增 import。
- 构建验证：运行 SunSmart Debug iPhoneOS 构建。
- 手工验证：进入真实 battery power switch 监控页，点击右上角 `Identify`，预期 App 侧 Mesh 发送队列出现 Health Model `AttentionSetUnacknowledged(attentionTimer: 6)`。
- 静默行为验证：点击后不应出现成功/失败 HUD，也不应等待设备回复。
- 日志预期：Space Debug UART Log 不一定显示该发送命令，因为它记录的是设备 UART 输出，不是 App 侧所有 Mesh TX；如需确认发送，应看 App 侧 Mesh 发送日志或 SDK send message 日志。

## 风险与边界

- 如果目标节点没有 `healthModel` 或 Health Model 未正确绑定 app key，SDK 可能无法完成有效发送；由于本次要求静默发送，App 不做用户可见错误提示。
- 如果当前连接的 proxy 不可用，SDK 发送队列也可能失败；本次规划不改变 proxy 选择逻辑，也不新增失败提示。
- 本次只规划 battery power switch 监控页右上角菜单 Identify，不改变灯具、网关、Fire Alarm 或添加设备流程。
