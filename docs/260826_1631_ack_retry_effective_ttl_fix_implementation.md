# ACK 重试计时使用 Effective TTL 实施总结

## 实施结果

已按确认方案完成修复。

acknowledged 单播创建可靠消息上下文时，现在使用与实际 Access PDU 发送路径相同的 effective TTL 优先级：

1. Lab 全局 outgoing Access message TTL override；
2. 调用方显式 `initialTtl`；
3. 本地 Provisioner Node `defaultTTL`；
4. Network Parameters `defaultTtl`。

因此，当 Lab override 为 `127`、默认 TTL 为 `5` 时，ACK 首次重试间隔不再按 TTL `5` 的 `0.25` 秒补偿计算，而是按 TTL `127` 的 `6.35` 秒补偿计算；两者相差 `6.1` 秒。基础间隔与分段数补偿继续由现有 Network Parameters 公式计算。

## 代码改动

### SDK Access Layer

修改：

`Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`

`createReliableContext` 不再直接读取 Provisioner / Network 默认 TTL，而是复用生产的 `OutgoingAccessMessageTtlPolicy.resolve`，解析结果继续传给现有 `acknowledgmentMessageInterval`。

以下行为未修改：

- acknowledged 单播可靠上下文的创建条件；
- 响应接收后的取消逻辑；
- 首次重试后的指数退避；
- 默认 30 秒总 timeout；
- 重发时使用原 PDU 和 Key Set 的行为；
- unacknowledged、Group、Virtual、Broadcast 目标的既有语义；
- Lower Transport Segment ACK、Heartbeat、Proxy Configuration、Provisioning 和 payload 内嵌 TTL。

### SDK 回归测试

扩展：

`Tests/NordicSigMeshSDKTests/OutgoingAccessMessageTtlPolicyTests.swift`

新增覆盖：

- override `127` 相比 fallback TTL `5` 增加 `6.1` 秒 ACK TTL 补偿；
- override 关闭时，显式 `initialTtl` 继续生效；
- 不同 Access PDU 分段数仍保留每段 50 ms 的补偿。

### App→SDK contract

更新：

`scripts/check_lab_light_group_ttl.sh`

新增对 SDK Access Layer 的静态契约：

- reliable context 必须调用生产的 effective TTL resolver；
- ACK interval 必须使用 resolver 输出的 TTL；
- 对应回归测试必须保留。

原有 App Lab 设置、持久化 Key、SDK 同步、国际化文案，以及 Lower Transport 分段 / 非分段两个发送出口契约保持不变。

## 验证结果

### 已通过

- Lab 全局 outgoing Mesh TTL contract：通过；
- 独立生产 TTL policy 测试：通过；
- App 仓库 `git diff --check`：通过；
- SDK 仓库 `git diff --check`：通过；
- `SunSmart` generic iPhoneOS Debug 构建：通过；
- `Archipelago` generic iPhoneOS Debug 构建：通过；
- `SLG Sync Plus` generic iPhoneOS Debug 构建：通过；
- `SylSmart` generic iPhoneOS Debug 构建：通过。

四品牌构建均关闭代码签名，不使用 Simulator，并确认解析的 `NordicSigMeshSDK` 为本地路径：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

### XCTest 环境限制

已尝试运行指定 Swift Package XCTest，但 macOS SwiftPM 在编译 SDK 生产源码时被既有 UIKit 依赖阻断：

`MeshDeviceProvisioningManager.swift: no such module 'UIKit'`

失败发生在 `NordicSigMeshSDK` 模块的 macOS 编译阶段，尚未进入本次新增 XCTest。该限制与本次修改无关。新增 SDK 生产代码已由四品牌 iPhoneOS 构建实际编译通过；TTL resolver 的独立可执行测试也已通过。

## 完成边界

当前证据可以确认：

- Access Layer ACK 计时与 Lower Transport 实际发送 TTL 采用相同优先级；
- override `127`、默认 TTL `5` 的 review 场景已在源码与测试契约中修复；
- SDK 生产代码可被四个品牌 target 编译和链接；
- App UI、TTL 总 timeout 和排除路径未被扩大修改。

当前证据不能代替真实 Mesh 多跳验收。仍建议使用真实 Proxy / Relay Mesh，通过抓包或可信时间日志验证 acknowledged Get / Set / Config 的首包、响应与首次重发时序，尤其覆盖 TTL `127` 和分段消息。
