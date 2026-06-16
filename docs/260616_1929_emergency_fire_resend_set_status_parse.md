# Emergency Fire Controller Resend SET STATUS 解析核查

## 结论

当前设备回复本身符合你给出的最新协议：

- `0x4D030000` = `0x4D/0x03`，`ret=0`，`state_idx=0`
- `0x4D030001` = `0x4D/0x03`，`ret=0`，`state_idx=1`
- `0x4D030002` = `0x4D/0x03`，`ret=0`，`state_idx=2`

问题在当前 SDK 解析：`SunricherVendorStatus` 把 `0x4D/0x03` 成功回复统一当成 GET STATUS 解析，要求至少 8 字节，也就是 `ret + state_idx + N + M`。因此 4 字节的 SET STATUS ACK 会被误判为失败。

## 当前协议对照

`0x4D/0x03 SET` payload 是 5 字节：

| 字段 | 长度 | 示例 |
|---|---:|---|
| `state_idx` | 1 | `00` / `01` / `02` |
| `N` | 2 | `0300` / `0500` |
| `M` | 2 | `FFFF` / `0400` |

`0x4D/0x03 SET STATUS` payload 是 2 字节：

| 字段 | 长度 | 示例 |
|---|---:|---|
| `ret` | 1 | `00` |
| `state_idx` | 1 | `00` / `01` / `02` |

所以完整 vendor status parameters 是 4 字节：`4D 03 ret state_idx`。

## 当前代码行为

SDK 的 vendor status 通用头解析如下：

- offset 0：main opcode，`0x4D`
- offset 1：subcode，`0x03`
- offset 2：status/ret

当 `ret == 0` 时，`isSuccessful` 先被设为 `true`。

但是进入 `.emergencyResendParameters` 分支后，当前代码要求：

- `data.count >= 8`
- offset 3 能解析为 `EmergencyFireStateIndex`
- offset 4..5 解析 `intervalSeconds`
- offset 6..7 解析 `count`

这只适合 GET STATUS：`4D 03 ret state_idx N M`。

对你给出的 SET STATUS：

| 回复 | 初始 ret 判断 | `.emergencyResendParameters` 长度判断 | 当前结果 |
|---|---|---|---|
| `4D030000` | 成功 | `count = 4 < 8` | 被改成失败 |
| `4D030001` | 成功 | `count = 4 < 8` | 被改成失败 |
| `4D030002` | 成功 | `count = 4 < 8` | 被改成失败 |

## App 层影响

Emergency Fire 同步任务会下发三条 `SunricherVendorSet(function: .emergencyResendParameters(...))`。

同步页最后看每个 `MeshMessageHandle.isSuccessful`，而 `MeshProxyMessageCommand` 对 `SunricherVendorStatus` 会继续检查 `vendorMessage.status.isSuccessful`。因此这三条正确 ACK 会被记入 `notRespondAddresss`，最终表现为对应 Resend 任务失败。

## 与旧日志的区别

仓库里已有一份未跟踪文档 `docs/260616_1854_emergency_fire_resend_failure_analysis.md`，其中分析的是旧回复 `0x4D0302`。

`0x4D0302` 只有 3 字节，只能表示 `ret=2`，确实是设备返回长度错误。

你现在提供的回复是 `0x4D030000 / 0x4D030001 / 0x4D030002`，这是 4 字节 SET STATUS 成功 ACK，不能再按旧文档里的“固件长度错误”结论处理。

## 建议修复方向

SDK 应区分 `0x4D/0x03` 的两种成功回复：

1. `data.count == 4`：SET STATUS ACK，只解析 `state_idx`，保留 `isSuccessful = true`。
2. `data.count >= 8`：GET STATUS，解析 `state_idx + N + M` 为 `EmergencyFireResendParameters`。

为了避免丢失 ACK 的回显信息，可以新增一个独立参数类型，例如 `EmergencyFireResendParametersAck(stateIndex:)`；如果不想扩 API，也至少不能把 4 字节成功 ACK 改成失败。

同时需要补 SDK 单元测试：

- `SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x00]))` 应成功。
- `SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x01]))` 应成功。
- `SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x02]))` 应成功。
- 原 GET STATUS `Data([0x4D, 0x03, 0x00, 0x02, 0x05, 0x00, 0x0A, 0x00])` 仍应解析出 `stateIndex=.restore, intervalSeconds=5, count=10`。

## 实施记录

已按建议修复方向实施：

- SDK 新增 `EmergencyFireResendParametersAck`，用于表达 `0x4D/0x03` SET STATUS 的 `state_idx` 回显。
- `.emergencyResendParameters` 解析分支现在区分：
  - 4 字节成功回复：解析为 `.emergencyResendParametersAck`。
  - 8 字节及以上成功回复：继续解析为 `.emergencyResendParameters`。
  - 其他长度或非法 `state_idx`：保持失败。
- SDK 测试补充三条 4 字节 ACK：`0x4D030000`、`0x4D030001`、`0x4D030002`。

验证：

- `xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` 通过。
- `swift test --filter EmergencyFireVendorMessageTests` 当前不可作为有效验证：SwiftPM CLI 在编译 SDK 时先遇到 iOS-only `UIKit` module 不可用，未进入测试执行。
