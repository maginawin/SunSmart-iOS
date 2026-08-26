# ACK 重试计时使用 Effective TTL 修复方案

## 结论

Review 评论成立。

当前 Lab 全局 TTL override 已在 Lower Transport 的分段与非分段 Access Message 出口生效，但 Access Layer 创建 acknowledged 单播的可靠消息上下文时，仍只读取本地 Provisioner Node 的默认 TTL 或 Network Parameters 默认 TTL。

因此，实际发送 TTL 与 ACK 首次重试间隔的 TTL 输入可能不一致。例如：

- Lab override 为 `127`；
- Provisioner / Network 默认 TTL 为 `5`；
- 实际 Network PDU 使用 TTL `127`；
- ACK 计时仍按 TTL `5` 计算；
- 两者的 TTL 补偿分别为 `6.35` 秒和 `0.25` 秒，相差 `6.1` 秒；
- 配置、Get、Set 等 acknowledged 单播可能在响应仍在多跳路径中时提前重发。

推荐在 SDK Access Layer 创建可靠消息上下文时复用现有 `OutgoingAccessMessageTtlPolicy`，用与 Lower Transport 相同的优先级解析 effective TTL，再交给现有 ACK 间隔公式。

## 根因与调用链

当前发送链路为：

1. App / SDK manager 发起 Mesh Access 或 Configuration message；
2. `AccessLayer.send` 构造 `AccessPdu`；
3. acknowledged 单播在 `AccessLayer.createReliableContext` 创建重试与超时计时器；
4. PDU 进入 Upper Transport；
5. Lower Transport 在分段或非分段出口解析实际发送 TTL；
6. Network Layer 使用该 TTL 构造 Network PDU。

第 3 步当前 TTL fallback 为：

1. Provisioner Node `defaultTTL`；
2. Network Parameters `defaultTtl`。

第 5 步实际发送 TTL 优先级已经是：

1. Lab 全局 `outgoingAccessMessageTtlOverride`；
2. 调用方显式 `initialTtl`；
3. Provisioner Node `defaultTTL`；
4. Network Parameters `defaultTtl`。

两处优先级不一致是本问题的直接原因。

ACK 首次重试间隔现有公式为：

> 基础间隔 + 50 ms × TTL + 50 ms × Access PDU 分段数

默认基础间隔为 2 秒。后续重试继续按现有实现逐次翻倍，总 timeout 继续使用当前 `acknowledgmentMessageTimeout`。

## 推荐修改范围

### 1. SDK Access Layer

修改本地 SDK 仓库中的：

`Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`

在 `createReliableContext` 中，不再直接使用 Provisioner / Network 默认 TTL，而是调用现有 `OutgoingAccessMessageTtlPolicy.resolve`，输入以下四级来源：

1. `MeshNetworkManager.outgoingAccessMessageTtlOverride`；
2. 当前 acknowledged message 的 `initialTtl`；
3. 发送 Element 所属 Provisioner Node 的 `defaultTTL`；
4. `networkParameters.defaultTtl`。

解析出的 effective TTL 只替换 ACK 首次重试间隔的 TTL 输入。可靠上下文的创建条件、消息重发闭包、指数退避、取消逻辑和总 timeout 保持不变。

### 2. SDK 回归测试

扩展：

`Tests/NordicSigMeshSDKTests/OutgoingAccessMessageTtlPolicyTests.swift`

新增针对 ACK 间隔的回归场景，至少覆盖：

- override 为 `127`、默认 TTL 为 `5` 时，ACK 间隔使用 `127` 的 TTL 补偿；
- override 关闭时，显式 `initialTtl` 仍优先于 Provisioner / Network 默认值；
- override 和显式 TTL 都缺失时，保持原 Provisioner / Network fallback；
- 分段数补偿继续保留，不被 TTL 修复覆盖或重复计算。

由于当前 Swift Package 在 macOS `swift test` 环境会被既有 UIKit 依赖阻断，XCTest 作为 iOS package 测试源保留；同时继续使用可独立编译的 TTL policy 测试和 App contract 脚本提供当前环境可执行证据。

### 3. App→SDK 静态契约

更新：

`scripts/check_lab_light_group_ttl.sh`

将 SDK `AccessLayer.swift` 纳入必需文件与契约检查，断言：

- reliable context 使用生产的 `OutgoingAccessMessageTtlPolicy`；
- ACK 间隔使用解析后的 effective TTL；
- Lower Transport 仍只有分段与非分段两个 Access Message 出口应用发送 TTL override；
- App 的 Lab 设置、持久化 Key、SDK 同步、UI 文案及原有 scope 检查保持不变。

## 明确不修改

本修复不包含以下改动：

- 不修改 App Lab UI、国际化文案或 UserDefaults Key；
- 不改变 TTL override 的 `0...127` 校验和优先级；
- 不改变 acknowledged message 的总 timeout；
- 不改变首次重试后的指数退避逻辑；
- 不改变 unacknowledged、Group / Virtual / Broadcast 不创建可靠响应上下文的既有行为；
- 不改变 Lower Transport Segment ACK、Heartbeat、Proxy Configuration、Provisioning 或 payload 内嵌 TTL；
- 不重构 Access / Upper / Lower Transport 的整体接口；
- 不处理运行中的 Lab override 被并发切换这一未提出的边界语义。

## 验证方案

### 自动化与静态检查

1. 运行全局 TTL contract 脚本，确认 App 配置、Access ACK 计时与 Lower Transport 发送出口契约一致；
2. 运行独立 TTL policy 测试，确认 `override > initialTtl > Provisioner TTL > Network TTL` 优先级不回退；
3. 对 App 与 SDK 两个仓库运行 `git diff --check`；
4. 检查改动文件集合，确保仅涉及 SDK Access Layer、相关测试、App contract 脚本和实施总结文档。

### 四品牌构建

App 当前已经通过本地 Swift Package 路径引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，四个品牌 target 都引用 `NordicSigMeshSDK`。

按项目规则直接、串行运行 generic iPhoneOS Debug 构建：

- `SunSmart`；
- `Archipelago`；
- `SLG Sync Plus`；
- `SylSmart`。

不使用 Simulator，不使用 shell 包装或日志重定向。

### 真机 / Mesh 验收建议

自动化与构建只能证明源码和集成契约，不能证明真实多跳时序。建议在真实 Proxy / Relay Mesh 中补充：

1. override 关闭、默认 TTL `5`：确认 ACK 首次重试行为与当前版本一致；
2. override 开启、TTL `127`：发送 acknowledged 单播 Get / Set / Config，确认不会仍按 TTL `5` 的时间提前重发；
3. 同时覆盖短消息和会分段的 Configuration / Vendor 消息，确认 TTL 与分段数补偿只各计算一次；
4. 在响应到达时确认可靠上下文按原逻辑取消，未产生额外重发；
5. 通过可信 SDK 时间日志或抓包对照首包、响应和首次重发时间。

## 风险与控制

### 高 TTL 会推迟首次重试

这是本修复的预期结果。TTL `127` 相比 TTL `5` 增加 `6.1` 秒 TTL 补偿，可减少长路径响应仍在途时的过早重发。

### 总 timeout 可能早于较后轮重试

本次不调整 30 秒默认总 timeout。修改后首次及后续重试次数可能因更长间隔而减少，但这属于现有 timeout 配置与指数退避的既定约束，不应在修复 review 评论时扩大语义。如真实网络表明 TTL `127` 需要同步增加总 timeout，应另立需求并基于 Mesh 时序数据评估。

### override 运行中切换

本方案按创建可靠上下文时的 effective TTL 设置该上下文的重试计时；常规 Lab 使用是先设置 override 再发送消息。若产品要求已在途的可靠消息随开关变化动态改写计时器或发送 TTL，需要另行定义一致性语义，本次不自行扩展。

## 完成标准

- ACK 可靠上下文与实际 Access PDU 使用同一 TTL 解析优先级；
- review 示例中 override `127`、默认 TTL `5` 时，ACK 计时不再使用 TTL `5`；
- override 关闭后的历史 fallback 行为不变；
- 全局 TTL contract、独立 policy 测试、`git diff --check` 通过；
- 四品牌 generic iPhoneOS Debug 构建通过；
- 真机多跳验证仍作为设备侧最终验收边界单独报告。

## 待确认

建议按上述最小范围实施。本轮不修改 App UI 或 TTL 总 timeout；若你确认，我再开始修改 SDK、测试与 contract 脚本，并完成四品牌构建验证。
