# Lab 全局下行 Mesh TTL 实现总结

## 实现结果

已将 Lab 中原本只覆盖部分灯具与分组控制命令的 TTL 设置，调整为 App 全局下行 Mesh Access / Configuration 消息的 Network PDU TTL 覆盖。

开启 `Override Outgoing Mesh TTL` 后，SDK 在统一发送出口使用 `Outgoing Mesh TTL`；关闭后恢复原有 TTL fallback 行为。

新的优先级为：

1. Lab 全局 TTL override；
2. 调用方显式 `initialTtl`；
3. 本地 Provisioner Node `defaultTTL`；
4. SDK Network Parameters `defaultTtl`。

## 作用范围

### 已覆盖

- SIG 与 Vendor Access Message；
- Configuration Message；
- acknowledged 与 unacknowledged 消息；
- 单播、组播、虚拟地址与广播目标；
- 分段与非分段 Access Message；
- 原本显式指定 `initialTtl`（包括 `0`）的 Access Message。

### 明确不覆盖

- Provisioning PDU；
- Proxy Configuration PDU；
- Heartbeat 等 Control Message；
- Lower Transport Segment Acknowledgment；
- 消息 payload 内具有独立业务含义的 TTL 字段。

## App 改动

- Lab 文案改为 `Override Outgoing Mesh TTL` 与 `Outgoing Mesh TTL`，并同步 English、简体中文本地化。
- 保留原有 UserDefaults 存储 Key，避免升级后丢失已保存的开关和值。
- App 冷启动时恢复并同步全局 TTL override。
- 开关变化或 TTL 数值保存后立即同步 SDK。
- `LightGroupControlCommandSender` 仅保留消息构造与发送职责，移除页面级 TTL 注入。
- `Display light ACK details` 继续只负责现有单灯 ACK 诊断展示，不作为 TTL override 开关；诊断上下文改为读取新的全局 TTL 配置。

## SDK 改动

- `MeshNetworkManager` 新增线程安全、仅运行时保存的全局 outgoing Access Message TTL override。
- override 仅接受 `0...127`，传入 `nil` 表示关闭。
- 在 Lower Transport 的分段与非分段 Access Message 统一出口应用 override。
- override 使用静态运行时状态，不写入 Mesh 数据，因此切换 Site / Space 或重建 manager 后不会静默丢失，也不会改变 Provisioner / Network 的默认 TTL 配置。

## 验证结果

### 已通过

- 全局 TTL 静态契约脚本：通过。
- 独立 TTL 优先级策略测试：通过。
- App 与 SDK 两个仓库 `git diff --check`：通过。
- `SunSmart` generic iPhoneOS Debug 构建：通过。
- `Archipelago` generic iPhoneOS Debug 构建：通过。
- `SLG Sync Plus` generic iPhoneOS Debug 构建：通过。
- `SylSmart` generic iPhoneOS Debug 构建：通过。

四品牌构建均使用本地 `NordicSigMeshSDK` 路径依赖，未使用 Simulator。

### 环境限制

SDK 的 Swift Package XCTest 无法在当前 macOS `swift test` 环境启动，因为既有 SDK 源码依赖 UIKit，而 Package 的 macOS 测试构建报 `no such module 'UIKit'`。本次使用不依赖 UIKit 的独立策略测试覆盖 TTL 优先级，并由四品牌 iPhoneOS 构建验证 SDK 生产代码集成。

### 仍需真机验收

- 使用抓包或可信 Network PDU 发送日志确认实际 TTL；
- 验证 TTL `0`、常用值及 `127`；
- 覆盖单播、Group、Broadcast、短消息和分段消息；
- 验证 Fast Add、配置、同步、Firmware / BLOB / OTA 等原本可能显式指定 TTL 的流程；
- 确认 Provisioning、Proxy Configuration、Heartbeat、Segment ACK 与 payload 内嵌 TTL 未被改写；
- 检查四品牌 Lab 页面 English / 简体中文真实布局、即时生效与重启恢复。

## 完成边界

源码契约、策略测试与四品牌构建已经通过，能够证明实现和 target 集成成立；在真实 Proxy / Relay Mesh 中完成抓包或等价日志验证前，不能宣称设备侧全局 TTL 行为已经验收完成。
