# EL Controller Relay 控件显示设计

## 背景

`CID 0x0A78 / PID 0x24C1` 在 `SunSmart/devices_config.json` 中配置为 `EL Controller`，`deviceCategory` 为 `Lighting`，因此设备详情入口会进入 `DeviceLightViewController`。

当前代码同时将该设备命中 `node.isEmergencySignController`。这会让详情页走 EM Sign 专用 UI，并隐藏普通 Light 页面右上角的 `Relay` 控件。用户确认该设备支持 Relay 切换，需要在详情页右上角展示 Relay 控件组。

## 目标

- 在 `CID 0x0A78 / PID 0x24C1` 的 EL Controller 详情页右上角展示现有普通 Light 的 `Relay` 标签和开关。
- 复用现有 Relay 读写链路：
  - 进入详情页读取 `MeshAPI.getReplyState(address:)`。
  - 开关变化调用 `MeshAPI.setReplyState(address:enabled:)`。
  - UI 状态从 `node.features?.relay == .enabled` 更新。
- 保持其他 EM Sign / EL Controller 既有行为不变。

## 非目标

- 不把 `0x24C1` 改回完整普通 Light UI。
- 不恢复亮度、CCT、On/Off 等普通 Light 控制。
- 不改变列表页、组页中 `isEmergencySignController` 的点击屏蔽逻辑。
- 不改变 `isSupportVendorIdentify == false` 的现有特例。
- 不新增本地化文案；继续使用当前已有 `Relay` 显示。

## 方案

采用已确认的方案 C：只把 Relay 显示能力从 `isEmergencySignController` 的 UI 隐藏规则中拆出。

新增一个聚焦的能力判断，例如 `node.supportsLightDetailRelayControl`。该判断用于详情页 UI，不替代 `isEmergencySignController`：

- 普通 Light：保持现有 Relay 显示行为。
- `CID 0x0A78 / PID 0x24C1`：即使命中 `isEmergencySignController`，仍允许显示 Relay 控件。
- 其他 EM Sign / Emergency 特例：继续隐藏 Relay。

`DeviceLightViewController` 中将目前直接使用 `node.isEmergencySignController` 隐藏 `relaySwitch` / `relayLabel` 的逻辑，替换为上述能力判断。`setupEmergencySignUI()` 和 `updateEmergencySignData()` 仍负责隐藏亮度、CCT、控制面板、On/Off 与 Identify UI 状态，但不再无条件隐藏 Relay；Relay 的最终可见性由能力判断统一控制。

## 数据流

1. 页面创建 `relaySwitch` 和 `relayLabel`，位置仍在内容区右上角。
2. `viewDidLoad` 执行后，根据 `supportsLightDetailRelayControl` 决定是否显示 Relay 控件。
3. 页面继续调用 `MeshAPI.getReplyState(address: node.primaryUnicastAddress)` 读取 Relay 状态。
4. `updateData` / `updateEmergencySignData` 根据 `node.features?.relay == .enabled` 更新开关状态。
5. 用户切换开关时继续调用 `MeshAPI.setReplyState(address:enabled:)`；发送失败时恢复开关状态。

## 错误处理

- 发送失败时沿用现有逻辑：重新启用开关，并把开关状态回滚。
- 设备未绑定或离线时保留现有空态/修复逻辑；Relay 控件是否显示不改变这些流程。
- 若后续读取不到 `node.features?.relay`，开关默认按现有逻辑显示为关闭状态，等待后续状态刷新。

## 验证

- 静态检查 `0x0A78 / 0x24C1` 命中新的 Relay 显示能力。
- 检查普通 Light 的 Relay 显示与读写逻辑不变。
- 检查其他 `isEmergencySignController` 依赖点不被重命名或改语义。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
