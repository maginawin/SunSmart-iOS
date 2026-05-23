# Battery Power Switch 默认重发参数优化设计

## 背景

`protocols/2422K8N_US_4DIM.md` 中 Battery Power Switch 的 `0x4C 0x00` key configuration 已扩展为 v1.0.22 的 16B wire，在原有 `ttl` 后追加：

- `retransmit_count`
- `retransmit_interval`
- `transition`

上一轮实现中，App 已停止为每个 SIG Client Model 配置 publication retransmit，改为通过 key configuration 固定写入 `retransmit_count=1`、`retransmit_interval=3`、`transition=0xFF`。实际验证发现，dim up/down 使用 `LEVEL_DELTA` / `LEVEL_MOVE` 时，应用层 retransmit 会导致一次用户操作被固件重复发送多次，表现为调光步进异常或持续调光行为异常。

协议文档当前推荐 APP 默认值为 `retransmit_count=0`、`retransmit_interval=0`、`transition=0xFF`，行为等价于旧 13B wire 的单次发送加 builtin transition default。

## 目标

- Battery Power Switch 按键功能配置默认使用单次发送。
- 继续保持 v1.0.22+ 新协议 16B wire。
- 避免 dim up/down 因应用层 retransmit 被重复执行。
- 让已经同步过 `1/200` 的设备进入 pending，并在下一次同步时重发 `0/0/FF` 配置。

## 非目标

- 不修改 refresh battery 的 `GenericBatteryGet` 轮询流程。
- 不恢复每个 Model 的 publication retransmit 配置。
- 不做 v1.0.18 / v1.0.21 旧协议 fallback。
- 不增加 UI 设置项让用户配置 retransmit 或 transition。
- 不按 action type 做差异化 retransmit 策略。

## 设计

### SDK 默认值

在本地 `NordicSigMeshSDK` 中，将 `BatteryPowerSwitchKeyConfiguration` initializer 的默认值调整为：

- `retransmitCount = 0`
- `retransmitInterval = 0`
- `transition = 0xFF`

`data` 仍然固定输出 16B key configuration，不改变字段顺序。默认编码会从：

```text
... <ttl> 01 03 FF
```

变为：

```text
... <ttl> 00 00 FF
```

GET status 解析仍然读取设备返回的实际值，不覆盖为默认值。这样现场若存在非默认配置，App 仍可正确显示或调试解析结果。

### App 配置 hash

在 `PJEightKeySwitchData.batteryPowerSwitchDesiredConfigHash(appKeyIndex:)` 中，将 key config 参数标识从：

```text
keyConfigWire=16,retransmit=1/200,transition=FF
```

调整为：

```text
keyConfigWire=16,retransmit=0/0,transition=FF
```

这个 hash 变更用于触发已配置设备重新同步。保存 Edit 页面或 Sync 页面发现 desired hash 与 applied hash 不一致时，会重新下发 key configuration，把旧的 `1/200` 覆盖为 `0/0`。

### Refresh Battery

Refresh battery 当前由 `PJEightKeySwitchBatteryRefreshFlow` 周期性发送 `GenericBatteryGet`，读取 `GenericBatteryStatus` 后保存电量。该流程不使用 `0x4C 0x00` key configuration 的 retransmit 字段，也不受本次默认值调整影响。

本次只修正 refresh 之前可能触发的 BPS 配置同步内容：如果设备因为 hash 变化需要先同步 key configuration，同步后的按键配置会使用 `0/0/FF`，避免后续 dim up/down 异常。

## 数据流

1. 用户添加 Battery Power Switch，或在 Edit 页面保存。
2. App 生成 BPS desired config hash，包含 `retransmit=0/0`。
3. 如需同步，App 生成 `BatteryPowerSwitchKeyConfiguration` 列表。
4. SDK 默认把每条配置编码为 16B，末尾为 `00 00 FF`。
5. 设备持久化每个 button / trigger 的配置。
6. 用户单击或长按 dim up/down 时，固件只发送一次对应 SIG Client 消息。

## 错误处理

- 设备返回 0x4C SET 失败时，沿用现有同步失败处理。
- App 不新增旧固件兼容分支；客户需先升级到 v1.0.22+。
- 若 refresh battery 时设备当前配置未同步，仍沿用现有逻辑先进入 BPS sync，再执行 refresh。

## 测试方案

- 更新 `BatteryPowerSwitchVendorMessageTests`：
  - SET expected bytes 从 `... FF 01 03 FF` 改为 `... FF 00 00 FF`。
  - GET status fixture 改为 `00 00 FF`。
  - 断言 `retransmitCount == 0`、`retransmitInterval == 0`、`transition == 0xFF`。
- 静态检查 App 中不再存在 `retransmit=1/200`。
- 静态检查 SDK 默认值不再是 `retransmitCount: UInt8 = 1`。
- 执行 `SunSmart` iphoneos Debug build。
- 如 SwiftPM 单测仍因 SDK 在 macOS test 环境 `import UIKit` 失败，记录失败原因；以 iOS build 和静态断言作为本轮可执行验证。

## 风险与取舍

Mesh 组播/广播不是强保证送达。取消应用层 retransmit 后，偶发丢包时用户可能需要再次按键。但对 Battery Power Switch 的普通控灯和调光交互来说，单次发送更接近用户预期，也避免 `LEVEL_DELTA` / `LEVEL_MOVE` 被重复执行造成明显异常。

如果未来有“紧急关闭”这类确实需要高可靠的动作，可以再单独设计按 action type 或业务场景配置 retransmit 的能力。本次不引入该复杂度。
