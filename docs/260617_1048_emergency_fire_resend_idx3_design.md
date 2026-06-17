# Emergency Fire 重发参数 idx=3 设计

## 背景

固件 v2.1.0 更新了 `0x4D/0x03` 重发参数协议，新增 `state_idx=3`：

- `SET idx=3`：用一条命令把同一组 `N/M` 同时写入应急触发 `idx=0` 和火警触发 `idx=1`，各自掉电保存，不影响恢复 `idx=2`。
- `GET idx=3`：读取应急与火警同步值，并做一致性校验。
- `GET STATUS ret=5`：仅在 `idx=3` 时表示应急与火警 `N/M` 不一致。

当前 App 的编辑页只有一个 `Repeatedly Send Emergency Control Every` 字段，并会把同一个触发间隔写入 `powerLossSettings` 和 `fireAlarmSettings`。同步层再按 `idx=0`、`idx=1` 分别下发两条 resend SET。新协议下这两条命令可以合并为一条 `idx=3` SET。

当前 `When The Emergency Event Ends:` 下的 `Send Count (5-second interval):` 已对应 restore resend：`state_idx=2, N=5, M=sendCount`。这个行为符合新需求，保持不变。

## 目标

1. SDK 支持 `state_idx=3` 的 SET、GET、SET STATUS、GET STATUS。
2. SDK 测试覆盖 `GET idx=3` 和 `GET STATUS ret=5` 的“不一致”状态。
3. App 设置 `Repeatedly Send Emergency Control Every` 时只下发一条 `state_idx=3` resend SET。
4. App 继续使用 `state_idx=2` 设置 `Send Count (5-second interval):`，不改变 restore 行为。
5. SDK 保留 `state_idx=0` 和 `state_idx=1`，作为未来单独设置应急/火警触发重发参数的功能预留。

## 非目标

1. 不重做 Emergency Fire 编辑 UI。
2. 不新增应急触发与火警触发分别设置 resend 的 App UI。
3. 不改变 action config、enable、restore delay、publication、subscription 同步逻辑。
4. 不兼容旧固件的旧 wire format；本设计只围绕当前 v2.1.0 协议。

## 推荐方案

采用 SDK + App 双层收口：

1. SDK 扩展协议表达能力，新增 `state_idx=3` case，并补齐解析和测试。
2. App 同步层把 trigger resend 从 `idx=0 + idx=1` 两条任务合并为 `idx=3` 一条任务。
3. Restore resend 仍作为独立 `idx=2` 任务存在。

这个方案让协议语义集中在 SDK，App 只表达业务意图：触发事件的重发参数是同一组值，恢复事件的发送次数仍是独立值。

## SDK 设计

### State Index

`EmergencyFireStateIndex` 增加一个 `rawValue = 3` 的 case。命名建议：

- `emergencyAndFireSync`

含义是“应急触发与火警触发同步 resend 值”。保留现有：

- `emergencyTrigger = 0`
- `fireTrigger = 1`
- `restore = 2`

### SET 编码

现有 `SunricherVendorSet(function: .emergencyResendParameters(...))` 编码逻辑是：

- `0x4D`
- `0x03`
- `state_idx`
- `N`
- `M`

只要 `EmergencyFireStateIndex` 支持 `3`，SET 编码无需新增专门分支。

### GET 编码

现有 `SunricherVendorGet(function: .emergencyResendParameters(stateIndex: ...))` 编码逻辑会附加 `state_idx`。扩展 enum 后，`GET idx=3` 可复用现有路径。

### STATUS 解析

`0x4D/0x03` status parser 保持区分两种 payload：

- 4 字节：`ret + state_idx`，对应 SET STATUS。
- 8 字节：`ret + state_idx + N + M`，对应 GET STATUS。

解析要求：

1. `ret=0, idx=0/1/2/3, 4 bytes`：解析为 `EmergencyFireResendParametersAck`。
2. `ret=0, idx=0/1/2/3, 8 bytes`：解析为 `EmergencyFireResendParameters`。
3. `ret=5, idx=3, 4 bytes 或 8 bytes`：`isSuccessful=false`，但不能把它误判为长度错误或 idx 越界；需要保留可识别的 `idx=3` ack/status 信息，便于调用方和测试区分“应急与火警 N/M 不一致”。
4. `idx` 非 `0...3`：仍按 idx 越界处理。
5. 长度既不是 4 字节也不足以组成 GET STATUS 时：仍按长度错误处理。

如果当前 `SunricherVendorStatus` 的公共模型只能通过 `isSuccessful` 和 `parameters` 表达状态，实施时应优先保持现有 API 形态：失败 ret 不改变成功判断，但 parser 要能返回包含 `stateIndex` 的 resend ACK/status 参数。若现有类型无法表达 ret 值，可在 SDK 内新增一个最小的 ack/status 结构字段来保存 `ret`，但不扩大 App 使用面。

## App 设计

### 配置模型

保留现有本地配置：

- `powerLossSettings.triggerIntervalSeconds`
- `powerLossSettings.triggerCount`
- `fireAlarmSettings.triggerIntervalSeconds`
- `fireAlarmSettings.triggerCount`
- `restoreSettings.sendCount`

当前 UI 的 trigger interval 是单一字段，保存时已经同步写入 power loss 和 fire alarm 两份 settings。实施时不需要迁移数据库结构。

### Sync Task 生成

当前 sync 层遍历 `EmergencyFireControllerState.allCases`，会生成：

- `Emergency Resend` -> `idx=0`
- `Fire Resend` -> `idx=1`
- `Restore Resend` -> `idx=2`

调整后生成：

- `Trigger Resend` -> `idx=3`
- `Restore Resend` -> `idx=2`

`Trigger Resend` 的 `N/M` 使用现有触发 resend 值。由于保存时两个触发 settings 已经保持一致，优先读取 `powerLossSettings` 即可；为了防止旧数据或导入数据不一致，生成任务前应先沿用现有保存归一化逻辑，或在 sync helper 中显式选择 App 当前 UI 的单一业务值。

### Changed-only 判断

触发 resend 的 changed-only 比较从分别比较 `idx=0`、`idx=1` 改为比较合并后的 `idx=3` 参数：

- interval 或 count 变化时，生成一条 `Trigger Resend`。
- 仅 restore send count 变化时，只生成 `Restore Resend`。

### Restore 保持现状

`Send Count (5-second interval):` 继续生成：

- `state_idx=2`
- `N=5`
- `M=restoreSettings.sendCount`

不改变 UI 文案、取值范围和同步语义。

## 测试计划

### SDK 测试

在 `EmergencyFireVendorMessageTests` 补充：

1. `SunricherVendorSet` 编码 `idx=3`：
   - 期望 payload 为 `0x4D 0x03 0x03 N M`。
2. `SunricherVendorGet` 编码 `idx=3`：
   - 期望 payload 为 `0x4D 0x03 0x03`。
3. SET STATUS `ret=0, idx=3`：
   - `isSuccessful=true`
   - 参数能识别 `stateIndex = .emergencyAndFireSync`
4. GET STATUS `ret=0, idx=3, N/M`：
   - `isSuccessful=true`
   - 返回 `EmergencyFireResendParameters(stateIndex: .emergencyAndFireSync, intervalSeconds: N, count: M)`
5. GET STATUS `ret=5, idx=3`：
   - `isSuccessful=false`
   - 不被误判为长度错误或 idx 越界
   - 参数或状态中可识别 `stateIndex = .emergencyAndFireSync`

### App 验证

1. 保存 `Repeatedly Send Emergency Control Every` 后，trigger resend 只生成一条 `idx=3` SET。
2. 保存 `Send Count (5-second interval):` 后，restore resend 仍生成 `idx=2, N=5, M=sendCount` SET。
3. 首次完整同步时包含一条 `Trigger Resend` 和一条 `Restore Resend`，不再包含单独的 `Emergency Resend` 与 `Fire Resend`。

### 构建验证

优先执行：

1. SDK iPhoneOS build：
   `xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
2. App iPhoneOS build：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与处理

1. **ret=5 表达能力不足**
   - 如果现有 `EmergencyFireResendParametersAck` 不携带 ret，测试很难证明 ret=5 被正确识别。实施时可最小扩展 ack/status 模型，保存 `responseCode` 或 `ret`。

2. **旧配置中 powerLoss/fireAlarm trigger resend 不一致**
   - 当前 UI 已是单一字段，保存会归一化。同步前若发现不一致，按当前 UI 业务值下发 `idx=3`，让设备重新合并。

3. **sync task 标题变化影响展示**
   - 任务标题从 `Emergency Resend`、`Fire Resend` 收口为 `Trigger Resend`。同步页只应展示更少任务，不应影响执行顺序。

4. **SDK 保留 idx=0/1 后 App 误用**
   - App 层新增 helper 表达“trigger sync resend”，不要让业务代码直接遍历 `EmergencyFireControllerState.allCases` 生成 resend。

## 验收标准

1. App 对 `Repeatedly Send Emergency Control Every` 只发送一条 `0x4D/0x03 SET idx=3`。
2. App 对 `Send Count (5-second interval):` 继续发送 `0x4D/0x03 SET idx=2, N=5`。
3. SDK 可编码 `GET idx=3`。
4. SDK 可解析 `SET STATUS ret=0 idx=3`。
5. SDK 可解析 `GET STATUS ret=0 idx=3 N/M`。
6. SDK 对 `GET STATUS ret=5 idx=3` 判断为失败但保留“不一致发生在 idx=3”的可识别信息。
7. SDK build 和 App build 通过，或记录与本次改动无关的明确环境阻塞。
