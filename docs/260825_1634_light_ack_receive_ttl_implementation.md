# Light ACK Rx / App Tx TTL 实现与验证记录

## 实现结果

已按确认范围完成现有 Light ACK details 的 TTL 诊断扩展。Lab 同时开启 `Display light ACK details` 与 `Override Light/Group control TTL`，并将 `Light/Group Control TTL` 设置为 `25` 后，Lights 列表或 Light Detail 的 acknowledged 灯控命令在收到 ACK 时按以下顺序展示：

1. `Result ... OK / Failed`
2. `ACK Rx TTL 25 (App Tx TTL 25)`
3. `Response ...`

其中：

- `ACK Rx TTL` 是 ACK 到达 App 时承载它的 Network PDU 剩余 TTL。
- `App Tx TTL` 是本次命令进入 SDK 发送链路时采用的显式 TTL，值在发送时固化，不会在 ACK 返回时重新读取 Lab 设置。
- `ACK Rx TTL` 不等同于设备 Default TTL；ACK 经过 Mesh Relay 时，接收 TTL 可能已被递减。

## 展示规则

| 场景 | TTL 行 |
| --- | --- |
| 正常 ACK，业务状态成功 | 展示 |
| 正常 ACK，vendor 业务状态失败 | 展示 |
| replay protection 拒收 packet | 展示 |
| timeout | 不展示 |
| cancelled / 普通发送失败 | 不展示 |
| override 关闭，App 没有显式 Tx TTL | 不推算、不展示 |
| 分段消息无法归一为单一接收 TTL | 不展示 |

本轮只保留原有 Light ACK details 入口：Lights 列表与 Light Detail；没有给 Group 页面新增 ACK 弹窗。

## SDK 实现

本地 `NordicSigMeshSDK` 新增了兼容的接收元数据结果，不改变现有只返回 `MeshMessage` 或 `StaticMeshResponse` 的 API。

正常 ACK 的 TTL 沿真实解码链路传递：

1. `NetworkPdu.ttl`
2. `AccessMessage.receivedTTL`
3. `UpperTransportPdu.receivedTTL`
4. `AccessPdu.receivedTTL`
5. `AccessLayer`
6. `NetworkManager`
7. `MeshNetworkManager` metadata-aware wait/callback
8. `MeshAPI.sendMessageWithReceiveMetadata`
9. `LightAckProgressTracker`

分段 Access Message 只有在所有 segment 都有 TTL 且数值一致时才返回单一 `receivedTTL`，否则返回 `nil`，避免将任意一个 segment 的 TTL 冒充整条消息 TTL。

Replay protection 在 Lower Transport 丢弃 packet 前直接把该 Network PDU 的 TTL 写入 `MeshReplayProtectionDiscardEvent`，因此 rejected packet 不依赖 Access Message 解码也能展示真实接收 TTL。

## App 实现

`LightAckProgressTracker` 在创建 command id 时同步保存本次显式 `defaultTTL`，随后使用 metadata-aware ACK API：

- 正常 ACK 从接收结果读取 `receivedTTL`。
- replay rejected 从诊断事件读取 `receivedTTL`。
- 只有 ACK Rx TTL 与 App Tx TTL 都存在时才组成 TTL 行。
- command 完成后清理 Tx TTL，旧 command 回调仍由 command id 隔离。

新增 English 与简体中文本地化：

- English：`ACK Rx TTL %d (App Tx TTL %d)`
- 简体中文：`ACK 接收 TTL %d（App 发送 TTL %d）`

## 自动验证

已通过：

- Light ACK Rx / App Tx TTL 专项契约脚本。
- 既有 Light ACK replay diagnostics 契约脚本。
- 既有 Lab Light/Group TTL 契约脚本。
- English 与简体中文 `Localizable.strings` 语法检查。
- App 工作区 `git diff --check`。
- SDK 本轮 TTL 相关已跟踪文件的聚焦 `git diff --check`。

SDK 新增单元测试覆盖：

- 匹配 source、destination、opcode 的 callback 返回 `receivedTTL == 25`。
- TTL `0`、`1`、`25`、`127` 原值保留。
- source 或 destination 不匹配时不消费 callback。
- replay discard event 保留 `receivedTTL == 25`。

`swift test` 无法在当前 macOS SwiftPM 环境执行，因为 SDK 源码依赖 UIKit，失败为 `no such module 'UIKit'`，测试尚未实际运行。

## 四品牌构建状态

已直接使用 iPhoneOS、generic device、关闭签名的方式分别构建：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

四个 target 均在同一个与本需求无关的既有问题处停止：

- `LightSensorCalibrationViewController.swift:311`
- 本地 SDK 的校准错误枚举已增加多个 case，但 App 的 `switch error` 尚未覆盖，编译器报 `switch must be exhaustive`。

TTL SDK 源码和 `LightAckProgressTracker` 已通过这些构建中的对应编译阶段，未发现本轮 API、类型或调用点错误。由于上述共同阻断，四品牌完整构建不能标记为通过。

本地 SDK 根目录的独立 `xcodebuild` 还会先被一个空的 `NordicSigMeshSDK.xcworkspace` 阻断，未用破坏性方式移动或删除该工作区。

## 保留的无关改动

本地 SDK 当前还有用户所有的校准开发改动，本轮未覆盖、未格式化、未修复：

- `MeshSensorCalibrateManager.swift`
- `MeshSensorCalibrateServer.swift`
- `SensorCalibrateMathTests.swift`

SDK 全仓 `git diff --check` 仍会被 `MeshSensorCalibrateManager.swift` 的既有行尾空格阻断；TTL 相关文件的聚焦检查通过。

## 真机验收建议

自动检查不能替代真实 Mesh packet 和 UI 验收。建议使用设备完成：

1. 开启两个 Lab 开关并设置 TTL 25。
2. 分别验证 Lights 列表 on/off，以及 Light Detail on/off、brightness、CCT、identify。
3. 无 Relay 场景确认常规 ACK 显示 `ACK Rx TTL 25 (App Tx TTL 25)`。
4. 有 Relay 场景确认 ACK Rx TTL 允许小于 25，App Tx TTL 仍为 25。
5. 制造 replay rejected packet，确认 Result 下展示 TTL 行。
6. 制造纯 timeout，确认不展示 TTL 行。
7. 关闭 override，确认不推算或展示 App fallback TTL。
8. 检查较小屏幕上弹窗新增一行后的高度和换行效果。

Bluetooth Mesh Network PDU 与 TTL 语义参考：

- https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html
