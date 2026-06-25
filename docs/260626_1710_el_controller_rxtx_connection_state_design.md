# EL Controller RX/TX Connection State 设计

## 背景

当前 Space 内设备的在线状态统一来自 SDK 的 `Node.state`：

- `true` 表示 Online。
- `false` 表示 Offline。
- 进入 Lights 页面后，`DeviceLightsViewController` 通过 `MeshNodeHeartbeatManager.shared.refresh()` 触发设备在线状态刷新。
- Mesh 连接断开时，SDK 会将当前 Space 的 real nodes 置为 Offline。
- Lights 列表的设备图标由 `DevicesViewCell` 根据 `node.state` 和设备配置图标决定。

`0x0A78 / 0x24C1` EL Controller 当前配置为 `Lighting + EMSign`，已有普通、离线、异常三种资源：

- `device_EMSign`
- `device_unsync_EMSign`
- `device_offline_EMSign`

EL Controller 详情页已经有手动 `Check RX/TX Cable` 能力，但状态只保存在详情页 helper/view 内，没有和 Space 的 Lights 列表共享。因此当前列表与详情页的 RX/TX Cable Connection State 不具备一致状态源。

## 目标

为 EL Controller 增加 Space 级运行态的 RX/TX Connection State：

- 默认：`RX/TX Connection Normal`
- 明确收到设备返回成功：`RX/TX Connection Normal`
- 明确收到设备返回失败：`RX/TX Connection Fault`

这个状态用于：

- `Site - Space - Main - Lights` 中 EL Controller item 图标展示。
- EL Controller 详情页 RX/TX Cable 卡片展示。
- EL Controller 详情页手动 Check 后反向更新 Lights 列表。

## 非目标

- 不将 RX/TX Connection State 写入数据库。
- 不进入 `SpaceData.export()` / cloud sync / share / import。
- 不改变普通设备 Online / Offline 的现有判定。
- 不扩展到非 `0x0A78 / 0x24C1` 设备。
- 不在 Space 内每次断线重连后重复自动读取 RX/TX Cable 状态。

## 状态规则

新增运行态枚举：

- `normal`
- `fault`

默认值为 `normal`。

状态更新规则：

- 收到 `SunricherVendorStatus`，code 为 `elControllerRxTxCableConnection`，且 `ret == 0`：更新为 `normal`。
- 收到 `SunricherVendorStatus`，code 为 `elControllerRxTxCableConnection`，且 `ret != 0`：更新为 `fault`。
- GET 超时、无响应、解析失败、无 vendor model：不改变当前状态。

该规则采用“明确失败才展示 Fault”的策略，避免因为无线临时丢包或超时把设备误标为 RX/TX Connection Fault。

## 架构方案

采用方案 A：在 App 层给 `Node` 增加 EL Controller RX/TX 运行态属性，作为列表和详情页的共享状态源。

原因：

- 现有 `Node.state`、`isOn`、`rssi` 等展示状态均是运行时属性，RX/TX Connection State 也是当前连接会话内的现场状态。
- 退出 Space 后 Mesh/Node 生命周期会重建，状态自然恢复默认 Normal，符合需求。
- 不污染 Space 数据合同，不会把临时故障同步给其他用户或下次进入 Space。
- 从详情页、列表页、自动检查流程都可以读写同一个 `Node` 对象，边界清楚。

## 自动读取流程

在 `DevicesViewController` 首次 Mesh 连接成功流程中增加一次 EL Controller RX/TX 自动检查。

触发条件：

- `MeshLibManager.manager.isMeshNetworkConnected == true`
- 当前 `DevicesViewController.firstConnectionNetwork == true`
- 当前 Space 内存在 EL Controller 节点

执行时机：

- 复用 `DevicesViewController` 现有首次连接门禁。
- 在首次连接成功后，延迟到在线状态有机会刷新后执行。
- 对每个符合条件的 EL Controller，在准备发送 GET 前额外延迟 100ms。

节点过滤：

- `node.companyIdentifier == 0x0A78`
- `node.productIdentifier == 0x24C1`
- `node.state == true`
- `node.isKeybindComplete == true`
- `node.sunricherVendorModel != nil`

发送命令：

- `SunricherVendorGet(function: .elControllerRxTxCableConnection)`
- Wire payload 对应 `F1 78 0A 45 00`

多设备处理：

- 如果 Space 内存在多台 EL Controller，按队列逐台发送。
- 每台之间保持小间隔，避免和 heartbeat、Time sync 等现有消息同时拥塞。

生命周期限制：

- Space 内断线重连不再自动读取，因为 `firstConnectionNetwork` 已经变为 `false`。
- 退出 Space 后再进入，新 `DevicesViewController` 会重新拥有 `firstConnectionNetwork == true`，首次连接后再次读取。

## Lights 列表展示

`DevicesViewCell` 对 EL Controller 图标使用以下优先级：

1. `node.state == false`：显示 `device_offline_EMSign`。
2. `node.state == true` 且 RX/TX Connection State 为 `normal`：显示 `device_EMSign`。
3. `node.state == true` 且 RX/TX Connection State 为 `fault`：显示 `device_unsync_EMSign`。

Offline 优先级最高。即使上一次 RX/TX 状态为 Fault，只要设备 Offline，仍显示 Offline 图标。

## EL Controller 详情页

详情页 RX/TX Cable 卡片启动时不再直接展示默认 idle 状态，而是读取当前 `node` 上保存的 RX/TX Connection State：

- `normal`：展示 Connection Normal。
- `fault`：展示 Connection Fault。

手动 Check 流程：

- 点击 Check 后进入 checking UI。
- 收到明确成功返回：更新 `node` 状态为 `normal`，详情页展示 Normal，并通知列表刷新该设备 item。
- 收到明确失败返回：更新 `node` 状态为 `fault`，详情页展示 Fault，并通知列表刷新该设备 item。
- 超时、无响应、解析失败：退出 checking 后恢复为当前 `node` 状态，不改写为 Fault。

## 通知与刷新

当 RX/TX Connection State 发生变化时：

- 更新 `node` 运行态属性。
- 发送现有 `deviceStateUpdateNotificationName`，object 使用该 `node`。
- Lights 列表已监听该通知，可复用现有 `reloadCollectionItem(node:)` 刷新单个 item。

如果状态值未变化，不需要重复刷新。

## 错误处理

- 无 vendor model：跳过自动读取，不改变状态。
- 设备 Offline：跳过自动读取，列表显示 Offline。
- GET 超时：不改变状态。
- 收到非 EL Controller RX/TX 响应：忽略。
- 响应来源不是目标 node 主元素或 vendor model 元素：忽略。

## 测试与验证

建议验证：

- 进入 Space，首次连接后 EL Controller 在线，自动发送一次 `F1 78 0A 45 00`。
- 同一次 Space 会话内断开再重连，不再自动发送 RX/TX GET。
- 退出 Space 再进入，首次连接后再次自动发送 RX/TX GET。
- 自动读取返回 `ret == 0`，列表显示 `device_EMSign`，详情页显示 Connection Normal。
- 自动读取返回 `ret != 0`，列表显示 `device_unsync_EMSign`，详情页显示 Connection Fault。
- 自动读取超时，保持当前状态不变。
- EL Controller Offline 时，列表始终显示 `device_offline_EMSign`。
- 详情页手动 Check 返回后，Lights 列表图标同步更新。

构建验证：

- 使用 iPhoneOS `xcodebuild` 验证 `SunSmart` scheme。

