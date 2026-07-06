# Lab TTL 下放到所有 SIG Mesh 命令可行性分析

## 结论

当前 App 不支持把 Lab 中的 TTL 设置覆盖到所有 SIG Mesh 命令。

现有 Lab TTL 功能是一个窄范围实现：`LabSettings` 保存开关和值，`LightGroupControlCommandSender` 在灯具/分组控制命令发送时读取 `LabSettings.lightGroupControlTTLOverride`，再把 TTL 作为 `MeshAPI.sendMessage(..., defaultTTL:)` 传入。这个实现只覆盖被改走 helper 的 Light / Group 灯控入口，不覆盖 Energy、Schedule、Device Parameter、Switch、Fire Alarm、Gateway、Sync、Firmware、SDK 内部 manager 等其他 SIG Mesh 命令。

从技术上看，可以扩展到更大范围，因为 SDK 的主发送链已经支持 per-message TTL：`MeshAPI.sendMessage` 接收 `defaultTTL`，`MeshMessageHandle` 保存 `defaultTTL`，`MeshMessageManager` 发送时传给 `MeshNetworkManager.send(..., withTtl:)`，Lower Transport 最终按 `initialTtl ?? provisionerNode.defaultTTL ?? networkParameters.defaultTtl` 计算网络层 TTL。

但“所有 SIG Mesh 命令”需要先定义清楚范围。如果指 App 业务层主动发出的 Access Message，可以做，复杂度中高。如果指包含 SDK 内部 heartbeat、provision/key bind、DFU、configuration、segmentation ACK、response message、proxy configuration、以及 payload 内自带 TTL 字段的命令，则复杂度高，不建议直接用一个 Lab 开关无差别覆盖。

## 当前 Lab TTL 功能范围

现有入口：

- `SunSmart/Common/Data/LabSettings.swift`
  - `overrideLightGroupControlTTL`
  - `lightGroupControlTTL`
  - `lightGroupControlTTLOverride`
- `SunSmart/Main/Site/Controller/LabViewController.swift`
  - Lab 页面展示 `Override Light/Group Control TTL`
  - 只有开关打开时才展示 TTL 数值行
- `SunSmart/Common/Data/LightGroupControlCommandSender.swift`
  - 单灯 on/off、brightness/lightness、CCT
  - 分组 on/off、brightness/lightness、CCT
  - All lights on/off、brightness
  - Light 页面 identify / vendor identify

现有设计是显式收窄 scope。`light_group_control_ttl_scope` 的文案也是“仅影响灯具和分组的灯控命令，其他功能不受影响”。

## 发送链路现状

App 和 SDK 中有三类相关发送入口：

1. `MeshAPI.sendMessage(...)`
   - SDK 已有 `defaultTTL` 参数。
   - 当前 App 中粗略匹配到约 95 处 `MeshAPI.sendMessage` 使用点，其中只有 `LightGroupControlCommandSender` 和 `LightAckProgressTracker` 相关路径接入了 Lab TTL。

2. `MeshMessageHandle(...)`
   - `MeshMessageHandle` 已有 `defaultTTL` 属性。
   - 当前 App 中粗略匹配到约 187 处 `MeshMessageHandle` 构造点，大量用于 sync、scene、schedule、gateway、EFC、add/restore、group profile 等流程。

3. `MeshAPI.setNodeOnOffState` / `setGroupOnOffState` / `setNodeLightnessState` 等高层 helper
   - 这些 SDK helper 当前没有暴露 `defaultTTL` 参数。
   - App 中粗略匹配到约 36 处这类调用，分布在 Timed、Scene、DALI、Energy、Parameter、Profile、Fire Alarm、Group 等页面。

主链路里，`MeshMessageManager` 会把 `messageHandle.defaultTTL` 传给 `MeshNetworkManager.send(..., withTtl:)`。Lower Transport 对普通 outgoing Access PDU 使用：

`initialTtl ?? provisionerNode.defaultTTL ?? networkManager.networkParameters.defaultTtl`

当前 SDK 初始化把 `networkParameters.defaultTtl` 设为 5；`NetworkParameters.defaultTtl` 本身会 clamp 到 `2...127`。

## 不能简单全局覆盖的原因

1. “网络层 TTL”和“payload 内的 TTL 字段”不是同一件事。

例如 `ConfigModelPublicationSet(Publish(... ttl: ...))`、`ConfigHeartbeatPublicationSet(usingTtl:)`、Firmware Distribution 的 `distributionTTL` / `uploadTTL` / `updateTTL`，以及部分 vendor payload 中的 `ttl`，这些 TTL 是命令内容的一部分。改变 Access PDU 的发送 TTL 不会自动改变这些 payload 字段。

2. 有些命令已有特殊 TTL 语义。

当前代码里已有 `withTtl: 0`、`withTtl: 1`、`defaultTTL = 0` 之类的专用路径，典型场景包括 fast add、direct/probe、firmware BLOB、proxy command 等。无差别覆盖可能破坏原有单跳、直连或固件升级语义。

3. ACK 超时策略不完全跟随 per-message override。

SDK 的可靠消息上下文在计算 ACK 初始等待时间时读取的是本地 node default TTL / network default TTL，而不是传入的 `initialTtl`。也就是说即使发送 PDU 使用了 Lab TTL，ACK retry/timeout 的部分时间参数仍可能按默认 TTL 估算。现有 Light/Group 场景影响较小；扩到所有 acknowledged 命令后需要专项验证。

4. Response / Segment ACK / Proxy Configuration 不应被业务 Lab 开关覆盖。

这些不是用户主动下发的业务命令，属于协议栈自身行为。把 Lab TTL 直接压到 Lower Transport 层，会有误伤风险。

## 可选方案与复杂度

### 方案 A：扩展 App 业务发送入口，所有调用点显式传 Lab TTL

做法：

- 给 App 侧所有 `MeshAPI.sendMessage`、`MeshMessageHandle`、`MeshAPI.set...State` 调用点补 TTL 参数。
- SDK 高层 helper 需要增加可选 `defaultTTL` 参数，避免 App 重写大量 message 构造逻辑。
- 对 payload TTL 字段保持原状，不把它们混入网络层 TTL override。

复杂度：中高。

优点是 scope 清楚，只覆盖 App 主动业务命令。缺点是调用点很多，漏点风险高，且后续新增命令容易忘记接入。适合“所有 App 页面主动下发的普通 Access Message”，不适合覆盖 SDK 内部流程。

### 方案 B：在 `MeshMessageManager` / `MeshMessageHandle` 层做默认注入

做法：

- 在 SDK 或 App wrapper 层集中读取 Lab TTL。
- 当 `MeshMessageHandle.defaultTTL == nil` 且命令满足可覆盖条件时，发送前填入 Lab TTL。
- 明确排除 provisioning、key bind、DFU、heartbeat、proxy configuration、SDK 内部 manager、response/ack、以及 payload TTL 类命令。

复杂度：中。

优点是改动点少，能覆盖大部分经队列发送的 App 业务命令。缺点是 `MeshMessageManager` 在 SDK 内部，读取 App 的 `LabSettings` 会产生依赖方向问题；更合理的做法是 SDK 暴露一个可选 policy / provider，由 App 注入。这个方案仍然不能覆盖所有绕过 `MeshMessageManager` 的直接 `MeshNetworkManager.send` 路径。

### 方案 C：修改 SDK 的全局 default TTL

做法：

- Lab 设置直接修改 `MeshNetworkManager.instance.networkParameters.defaultTtl` 或本地 provisioner node default TTL。

复杂度：低到中。

优点是最省调用点改造，凡是 `initialTtl == nil` 的消息都会走新默认值。缺点很大：`networkParameters.defaultTtl` clamp 在 `2...127`，不能支持现有 Lab 允许的 TTL 0/1；它会影响配置、sync、publication 构造、firmware 等广泛流程；显式传 TTL 的路径不受影响。这个方案不适合作为 Lab 诊断功能的主实现。

### 方案 D：Lower Transport 全局覆盖

做法：

- 在 Lower Transport 计算最终 TTL 前注入 Lab override。

复杂度：高。

优点是覆盖面最大。缺点是协议层风险也最大：response、segmented retransmission、ack、SDK 内部专用 TTL、proxy/config 语义都可能被影响；同时 payload TTL 字段仍不会变。除非目标是做底层协议实验，并且只在 debug/internal build 中启用，否则不建议。

## 推荐判断

如果需求是“让 Lab TTL 覆盖所有 App 页面主动发出的普通 SIG Mesh Access Message”，推荐走方案 B 的 policy 化实现，并配一个明确的 exclude list。这样能减少调用点改造，又避免 SDK 直接依赖 App 的 `LabSettings`。

如果需求是“所有 Light / Group / Energy / Parameter / Fire Alarm / Gateway 页面里的业务命令都可用 Lab TTL”，可以在方案 B 基础上逐步放开，并用脚本检查新增命令是否绕过 policy。

如果需求是真正“所有 SIG Mesh 命令，包括 SDK 内部、配置、DFU、heartbeat、response、payload TTL”，不建议做成一个普通 Lab 开关。这个范围需要拆成多个 TTL 类型：

- Outgoing Access PDU network TTL
- Model Publication payload TTL
- Heartbeat Publication payload TTL
- Firmware Distribution / Update payload TTL
- Vendor command payload TTL
- Transport response / segment ACK TTL

这些类型语义不同，不应该统一由一个数值强行覆盖。

## 验证建议

分析阶段未改业务代码，因此不需要跑 iPhoneOS build。

若后续进入实现，建议至少验证：

- `git diff --check`
- `scripts/check_lab_light_group_ttl.sh`
- iPhoneOS `xcodebuild`，至少 `SunSmart` scheme
- Lab TTL 关闭时，现有业务发送路径保持 `defaultTTL == nil`
- Lab TTL 开启时，普通 App 业务命令使用 override TTL
- 明确排除的 SDK 内部流程仍保持原 TTL 语义
- TTL 0、TTL 1、TTL 2、TTL 5 分别在直连 Proxy、relay、多播/组播场景下手动验证
