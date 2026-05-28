# Battery Power Switch Identify 菜单排查

## 结论

Battery Power Switch 监控页右上角菜单会显示 `Identify`，但当前点击后没有发送任何 Mesh 命令。

入口位于：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `moreAction()` 中追加了 `Identify` 菜单项
- `tapItemBack` 闭包内部只有 `// Identify` 注释，没有调用 `MeshAPI.identify` 或 `MeshAPI.sendMessage`

因此在 Log 上看不到对应消息，主要原因是当前没有消息进入发送队列。

## 代码链路

### Battery Power Switch 当前实现

`PJEightKeySwitchMonitorVC.moreAction()`：

- 非未绑定虚拟开关时显示 `Identify`
- 真实 Battery Power Switch 同时显示 `Information`
- `Identify` 点击回调为空

### 其他页面的 Identify 参考

项目内已有两类 Identify 写法：

1. 灯具详情页使用 Sunricher Vendor Identify：
   - `SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500)))`
   - 发送到 `node.sunricherVendorModel`

2. Fire Alarm 监控页使用 Health Model Attention：
   - `AttentionSet(attentionTimer: 6)`
   - 发送到 `healthModel`
   - 带 ack 回调，失败时提示 failed

SDK 里的通用 `MeshAPI.identify(address:attentionTimer:ack:)` 默认发送：

- `AttentionSetUnacknowledged(attentionTimer:)`
- 如果 `ack == true` 则发送 `AttentionSet(attentionTimer:)`
- 单播且找到 `healthModel` 时走 model 发送，否则按 address 发送

## 如果实现，可能的命令选择

当前代码没有明确为 Battery Power Switch 选定命令。按现有项目风格有两个候选：

1. 复用灯具详情页的 Sunricher Vendor Identify：
   - `SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500)))`
   - Vendor 功能码映射为 `deviceIdentify`
   - 前缀为 `VendorOpCode.nodeConfig` / `NodeConfigCode.identify`，即 `0x48 / 0x03`

2. 复用 Health Model Attention：
   - `MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)`
   - 默认是 unack 的 `AttentionSetUnacknowledged`
   - `ack: true` 时才是 ack 的 `AttentionSet`

具体选哪种需要看 Battery Power Switch 固件支持哪一路 Identify。

## Log 看不到的原因

`MeshAPI.sendMessage` 会把消息加入 `MeshMessageManager` 队列；实际发送时 `MeshMessageManager.sendMessageEvent()` 会打印 `send message: ...`。

Battery Power Switch 菜单当前没有调用 `MeshAPI.sendMessage`，也没有调用 `MeshAPI.identify`，所以不会触发这条打印。

如果你看的是 Space Debug 的 UART Log，它只订阅当前 proxy 的 Debug UART GATT TX characteristic，记录的是设备 UART 输出，不是 App 侧所有 Mesh TX 发送记录。即使后续补了 Mesh Identify 命令，也不一定会出现在 UART Log，除非设备固件主动通过 Debug UART 打印对应内容。

## 判断

当前现象符合代码实现：菜单项存在，但 Identify 动作还没有接线。

