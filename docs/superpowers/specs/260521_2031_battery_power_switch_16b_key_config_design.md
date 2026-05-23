# Battery Power Switch 16B Key Config 设计

## 背景

`protocols/2422K8N_US_4DIM.md` 已更新 `0x4C 0x00` 按键配置协议。v1.0.22 起，`Vendor SET 0x4C 0x00` wire 长度从旧 13B 升级为 16B，在原 `ttl` 后追加：

- `retransmit_count`
- `retransmit_interval`
- `transition`

本次 App 只面向 v1.0.22+ 固件。客户会先升级到最新固件再配置 battery power switch，因此不做旧 13B/15B wire fallback。

## 当前调查结论

当前 App 在添加 battery power switch 时会下发配置命令。Classic / Professional 添加流程会调用 `BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(...)`，生成 `SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(...))`。

当前添加流程也会下发 publication retransmit 配置。`defaultConfigurationMessageHandles(...)` 会追加 `node.getBatteryPowerSwitchPublicationMessageHandles(...)`，对 BPS profile client models 逐个下发 `ConfigModelPublicationSet`，并使用 `Publish.Retransmit(publishRetransmitCount: 1, intervalSteps: 3)`。

当前 Edit 页面 SAVE 后，如果需要 Switch configuration，也会下发 publication retransmit。`SyncDevicesViewController.appendBatteryPowerSwitchItems(...)` 会生成 `Key Config` 和 `Model Publication` 两个 step；`Model Publication` 依赖 `Key Config` 成功后执行，同样调用 `getBatteryPowerSwitchPublicationMessageHandles(...)`。

其他 battery power switch 相关 publication retransmit 配置集中在 `Node.getBatteryPowerSwitchPublicationMessageHandles(...)`。普通 sensor publication 也有 retransmit 参数，但不是 BPS 按键控制路径。

当前本地 `NordicSigMeshSDK` 还不支持新 16B wire。`BatteryPowerSwitchKeyConfiguration` 只定义到 `ttl`，`data` 仍编码 13B；`BatteryPowerSwitchActionType` 只支持到 `0x08`，尚未同步新协议的 `0x09...0x10`。

## 决策

采用 16B-only 方案：

1. SDK 升级 `BatteryPowerSwitchKeyConfiguration` 为 v1.0.22 协议模型，直接编码 16B。
2. App 删除 BPS profile client model publication 同步，不再为每个 Model 配置 publication retransmit。
3. App 所有 BPS `0x4C 0x00 SET` 固定写入：
   - `retransmit_count = 1`
   - `retransmit_interval = 3`，表示 200ms
   - `transition = 0xFF`
4. 不支持旧固件 fallback。旧固件若返回 `err=1`，按普通同步失败处理。

## SDK 设计

在本地 `NordicSigMeshSDK` 中调整 `BatteryPowerSwitchKeyConfiguration`：

- 新增 `retransmitCount: UInt8`
- 新增 `retransmitInterval: UInt8`
- 新增 `transition: UInt8`
- 默认值设为 `1 / 3 / 0xFF`
- `data` 固定输出 16B，末尾为 `retransmitCount, retransmitInterval, transition`

`BatteryPowerSwitchActionType` 同步扩展到协议完整范围：

- `0x09 CTL_SET`
- `0x0A CTL_TEMP_SET`
- `0x0B HSL_SET`
- `0x0C HSL_HUE_SET`
- `0x0D HSL_SAT_SET`
- `0x0E PLVL_SET`
- `0x0F PONOFF_SET`
- `0x10 DTT_SET`

`SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(...))` 保持现有入口，避免 App 层手工拼包。

`0x4C 0x00` status 解析按 16B 配置体处理。由于本次只面向 v1.0.22+，GET 单项配置返回不足 16B 时可解析失败，不做旧协议兼容。

## App 同步流程设计

添加 battery power switch 时，默认配置链只保留 Key Config：

- 保留 `BatteryPowerSwitchAddConfiguration.prepareSwitchData(...)`
- 保留 `batteryPowerSwitchKeyConfigurations(appKeyIndex:)`
- `defaultConfigurationMessageHandles(...)` 不再追加 BPS model publication handles

Edit 页面 SAVE 后，如果需要 Switch configuration，只生成 `Key Config` step：

- 删除 `batteryPowerSwitchModelPublication` step 的生成
- 删除 `Key Config -> Model Publication` 依赖
- 同步成功判断不再依赖 BPS model publication

target group subscription 继续保留。BPS 按键配置里的 `addr` 仍指向 link group，目标设备仍需要订阅该 group 才能响应按键消息。

## 配置 Hash 设计

当前 hash 中的：

`publication=profileClients@link,retransmit=1/200`

需要改为表达新协议配置：

`keyConfigWire=16,retransmit=1/200,transition=FF`

这样历史上按旧 publication 方案同步过的设备，会重新显示需要同步，并通过 SAVE 写入 16B `0x4C` 配置。

## 错误处理

如果 `0x4C 0x00 SET` 返回失败，沿用现有 BPS sync failed 流程：

- 标记 `syncState = failed`
- 记录失败原因
- UI 显示 sync issue
- 用户可重新 SAVE 重试

如果旧固件返回 `err=1`，也按普通失败处理，不降级为 13B。

删除 BPS model publication 后，如果相关 helper 暂时保留但不再被 BPS 添加和 SAVE 流程调用，也不得再影响 BPS 同步成功条件。

## 验证范围

SDK 验证：

- 更新 `BatteryPowerSwitchVendorMessageTests`
- 确认 `SunricherVendorSet(.batteryPowerSwitchKeyConfig)` 输出 16B 配置体，总参数长度对应 `0x4C 0x00 + 16B`
- 确认 payload 末尾为 `01 03 FF`
- 确认 16B GET status 能解析出 `retransmitCount = 1`、`retransmitInterval = 3`、`transition = 0xFF`

App 验证：

- 检查添加流程不再生成 BPS `Model Publication`
- 检查 Edit SAVE 流程不再生成 BPS `Model Publication`
- 检查 BPS target subscription 仍按现有流程生成
- 检查 desired config hash 变化会触发旧本地记录重新同步

构建验证：

- 在本地 SDK 执行 `swift test`
- 在 App 工程执行 SunSmart iOS build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 非目标

- 不做旧固件 13B/15B fallback。
- 不新增 UI 控件让用户配置 retransmit 或 transition。
- 不调整普通 sensor publication retransmit。
- 不扩大到非 battery power switch 的配置路径。
