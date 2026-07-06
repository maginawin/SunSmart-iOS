# Light ACK Timeout SeqAuth Analysis And Repair Plan

## 背景

当前 Site > Space > Lights 约 300 个设备，启用 Lab 中的 ACK 详情能力后，控制部分设备时出现：

- 设备本身能响应控制。
- App 仍提示 timeout / cancelled。
- 日志中目标设备地址为 `0x015A`，发送的是 `GenericOnOffSet`，opcode `0x8202`，TID `0xDD`。

## 已确认事实

1. 这次不是单纯的 RF 丢包。
   日志里 App 已收到来自 `0x015A`、发往本机 `0x0001` 的 3 个 Network PDU，网络 seq 分别是 `1748`、`1749`、`1750`。

2. ACK 响应没有进入 Access 层。
   三个包都在 Lower Transport 层被 replay protection 丢弃：
   `Discarding packet (seqAuth: 1748, expected > 2024)`，后续 `1749`、`1750` 同理。

3. App 的 timeout 是结果，不是第一根因。
   因为响应包在 lower transport 阶段被丢掉，ACK wait 回调等不到 `GenericOnOffStatus`，最终触发 timeout。

4. 日志里的 `cancelled` 是 timeout 后的清理副作用。
   SDK reliable context 超时后会 cancel 对应 message handle / notify callback，因此不能把 `cancelled` 理解成用户主动取消或按钮层取消。

5. Lab ACK 详情开关更像是暴露问题，不是 replay 丢包根因。
   当前 Lights 列表和 Light Detail 的单灯 on/off 默认本来就走 acknowledged `GenericOnOffSet`。Lab 开启后只是走 `LightAckProgressTracker` 展示等待结果，没有关闭或绕过 SDK replay protection。

6. TTL / Proxy 不是本次日志的优先根因。
   响应已经从 `0x015A` 到达本机。如果是 TTL 不足、Proxy filter 没放行、或纯链路不可达，通常不会出现来自目标源地址的 Network PDU 并被 replay protection 拒收。

## 代码证据

- `DeviceLightsViewController.sendLightItemOnOffCommand(node:)`：Lights item on/off 在 Lab 关闭时通过 `LightGroupControlCommandSender.setNodeOnOff(..., ack: true)` 发送；Lab 开启时通过 `LightAckProgressTracker` 发送同类 `GenericOnOffSet`。
- `DeviceLightViewController.sendLightDetailOnOffCommand()`：Light Detail on/off 同样走 acknowledged `GenericOnOffSet`。
- `LightAckProgressTracker.send(...)`：只负责展示发送中、成功、timeout 等状态，核心仍是 `MeshAPI.sendMessage(message:model:defaultTTL:result:)`。
- `LowerTransportLayer.checkAgainstReplayAttack(_:)`：按 source address 读取上次收到的 SeqAuth；当前包的 `receivedSeqAuth` 必须大于 `lastSeqAuth`，否则打印 `Discarding packet` 并返回 false。
- `LowerTransportLayer` 的 SeqAuth store 使用 `UserDefaults(suiteName: meshNetwork.uuid.uuidString)`，因此是按 mesh UUID 分隔，不是全 App 全局共用。
- `MeshNetwork.remove(nodeWithUuid:)` 删除 node 时会把地址加入 `networkExclusions`，并且注释明确说明不能直接清除该 node 的 SeqAuth，否则可能接受旧 replay 包。
- `ImportData` 中存在 server import 时把 node 从 exclusion 中移除再加入 network 的路径，这能解释“同一 mesh 内地址/设备状态被恢复或复用后，本地 RPL 仍高于设备当前 sequence”的场景。

## 最可能原因

### 原因 1：设备端 sequence number 回退

本机记录 `0x015A` 上一次有效 SeqAuth 是 `2024`，但当前设备从 `1748` 开始回复。说明设备当前发送 sequence 低于 App 本地 RPL 记录。

常见触发条件：

- 设备掉电/重启后没有持久化最新 sequence。
- 固件只周期性保存 sequence，异常断电后回滚到旧值。
- 设备恢复了旧备份或被重置后仍保留同一 mesh 身份/地址。

这个原因与日志最匹配。

### 原因 2：同一 mesh 内地址复用或恢复导入

如果 `0x015A` 曾经属于旧设备，App 已记录旧设备 seq 到 `2024`，后来通过 force delete、server import、同步恢复等路径重新引入同地址设备，而新设备 seq 只有 `1748`，App 会继续按同一 source address 执行 replay 校验并拒收。

300 个设备的 Site 会提高这种问题出现概率：地址多、同步路径多、删除/恢复/多用户编辑交错时更容易出现旧地址重新进入网络。

### 原因 3：当前 mesh 中存在重复地址或云端状态不一致

如果两个物理设备或两份 node 数据同时指向 `0x015A`，其中一个先把 App 的 RPL 推到 `2024`，另一个再以 `1748` 回应，就会稳定复现当前表现。

### 原因 4：App 本地 RPL 状态和设备真实状态不同步

同一 mesh UUID 下，App 保留了历史 RPL；设备端或云端数据回到更早状态。因为 RPL 按 mesh UUID 存储，这不是跨不同 mesh 的污染，而是当前 mesh 内的状态不一致。

## 低概率原因

- 增大 ACK timeout：无效。响应已经很快到达，只是被丢弃。
- 增大 TTL：无效或收益很低。响应已到达本机。
- 增加重试次数：只能让设备 seq 继续增加；如果差值较大，会造成大量重复控制，而且仍然不能从根上解释问题。
- 关闭 ACK：会隐藏问题。命令可能继续生效，但 App 无法确认设备真实状态。
- 全局关闭 replay protection：不建议，安全风险和协议风险都过大。

## 验证计划

1. 采样 affected device 和 normal device。
   对同一命令分别记录 source、destination、ivIndex、network seq、expected SeqAuth、node name、node UUID、MAC、product id。

2. 读取当前 mesh UUID 下 `0x015A` 的 RPL。
   检查 `lastSeqAuth` 是否为 `2024`，`previousSeqAuth` 是否也在附近。

3. 查当前 mesh 数据是否存在地址异常。
   检查 `MeshNetwork.nodes`、本地数据库、server import JSON、exclusions 中是否出现 `0x015A` 的重复、删除后恢复、或不同 UUID/MAC 覆盖。

4. 对受影响设备做连续 ACK 控制采样。
   如果设备 seq 从 `1748` 单调增加，但在超过 `2024` 前一直 timeout，超过后 ACK 恢复，则可直接确认是设备/本地 RPL sequence gap。

5. 在开发构建中只对 `0x015A` 临时清理 RPL 后重试。
   如果清理后 ACK 立即成功，基本确认本地 RPL 与设备 seq 不一致是主因。该验证只用于开发/受控环境，不应直接作为默认产品行为。

## 推荐修复方案

### 阶段 1：补 Replay / ACK 诊断，不改变默认控制行为

在 SDK LowerTransportLayer 里增加受控诊断事件或日志字段：

- mesh UUID
- source / destination
- node name / UUID / MAC
- received ivIndex / seq / SeqAuth
- stored last / previous SeqAuth
- 是否存在 pending acknowledged command
- pending opcode / expected response opcode

在 Lab ACK 详情中将这类失败显示为：

- `Response rejected by replay protection`
- 附带 source、received seq、expected seq

这样用户看到的不是泛化 timeout，而是明确知道设备有回应但被 replay protection 拒收。

### 阶段 2：增加 Lab-only 的单设备 RPL 修复入口

提供一个只在 Lab / Diagnostics 下可见的动作：清理当前 mesh 中某个 node 的 replay record。

约束：

- 只能作用于当前 mesh UUID。
- 只能作用于当前 mesh 中真实存在的单个 node。
- 只清理该 node 所有 element address 的 last / previous SeqAuth。
- 执行前要求用户确认，并说明这是安全例外操作。
- 清理后自动或提示用户重试 ACK 控制。
- 记录操作日志，包含 mesh UUID、node address、node UUID/MAC、清理前 last/previous 值。

这个方案可以恢复已确认 stale sequence 的设备，又不改变默认网络安全策略。

### 阶段 3：收紧导入/地址复用链路

检查并收口以下路径：

- `forceRemove(node:)` 后重新 import 同地址 node。
- server import 时发现 node 在 current / previous IV Index 的 exclusion 中，又把 exclusion 删除并加入网络。
- 同一 address 对应不同 UUID/MAC 的 node 覆盖。

建议策略：

- import 时如果发现同地址 node 正在 exclusion 内，先记录 conflict diagnostic。
- 如果 UUID/MAC 与旧记录不一致，不要静默当作普通更新；标记为 address reuse conflict。
- 如果确认为同一物理设备但 sequence 回退，引导用户使用 Lab RPL repair。
- 不在普通 import 流程里无提示清理 RPL。

### 阶段 4：设备端 / 运维侧确认

如果多个设备在断电重启后都出现 sequence 回退，应同步排查设备固件：

- sequence 是否按 SIG Mesh 要求持久化。
- 持久化周期是否可能导致大幅回退。
- 恢复出厂、重新入网、云端恢复时是否复用了旧 mesh address。

App 侧 repair 可以止血，但设备端 sequence 回退才是长期根因。

## 验收计划

1. affected device 未 repair 前：
   Lab ACK 详情显示 replay rejected，而不是普通 timeout。

2. normal device：
   ACK 成功路径不变。

3. affected device 执行 Lab RPL repair 后：
   下一次 ACK 控制能收到 status，App 不再提示 timeout。

4. 安全边界：
   默认控制流程不关闭 replay protection。
   默认 import / sync 不自动清 RPL。
   只允许 Lab / Diagnostics 单设备显式修复。

5. 构建验证：
   使用 iPhoneOS `xcodebuild` 校验 `SunSmart`。如果改到 SDK 公共 API 或资源/localization，再同步检查受影响 target。

## 建议确认的实现范围

推荐先做：

1. Replay discard 诊断事件。
2. Lab ACK 详情识别并展示 replay rejected。
3. Lab-only 单设备 RPL repair。
4. import / forceRemove / exclusion 路径只补诊断与冲突提示，不先做自动清理。

暂不做：

1. 全局关闭 replay protection。
2. 普通用户默认自动清理 RPL。
3. 通过增加 timeout / TTL / retry 来掩盖问题。
4. 大范围重构 MeshAPI ACK 发送链路。

## 待确认问题

1. 这些 timeout 设备是否近期经历过断电、重置、删除后重新同步、或从其他手机导入？
2. 同一设备连续控制约 300 次后，ACK 是否会在 seq 超过 `2024` 后恢复？
3. 是否接受把“清理单设备 RPL”放在 Lab / Diagnostics 下作为显式 repair 操作？

## 本次实施记录（2026-07-06 16:55）

已先实现确认范围中的前两项：

1. Replay discard 诊断事件。
   SDK 在 Lower Transport replay protection 拒收包时，发布 `MeshReplayProtectionDiscardEvent`，包含 mesh UUID、source、destination、ivIndex、sequence、received SeqAuth、expected SeqAuth、previous SeqAuth，以及当前等待中的 response / message opcode。

2. Lab ACK 详情识别并展示 replay rejected。
   `LightAckProgressTracker` 在等待 ACK 期间监听 replay discard 事件；如果事件来源地址和当前 ACK 命令匹配，则将 Lab ACK 详情从普通 timeout 改为 replay protection rejected，并展示 source、received SeqAuth、expected SeqAuth。

未实现的范围：

- 未增加 Lab-only RPL repair 入口。
- 未修改 import / forceRemove / exclusion 行为。
- 未关闭 replay protection。
- 未改变默认 acknowledged command 发送和 retry 行为。

验证结果：

- `bash scripts/check_light_ack_replay_diagnostics.sh` 通过。
- `git diff --check` 通过。
- `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check` 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。
