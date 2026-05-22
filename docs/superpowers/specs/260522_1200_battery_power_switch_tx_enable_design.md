# Battery Power Switch TX Enable 设计

## 背景

Battery Power Switch 设备页底部已有 `Enable` 开关，当前实现主要改变 App 本地 `enabled` 状态，并把 `enabled` 混入 Battery Power Switch key configuration 的同步判断。禁用时，当前代码会让 `batteryPowerSwitchKeyConfigurations(...)` 返回空数组，间接表达“无按键功能”。

新协议提供了更准确的全局 TX 开关：

```text
Vendor SET 0x4C 0x03 <enable>
```

其中 `<enable>` 为 `0` 禁用、`1` 启用。该命令只屏蔽按键触发的 SIG client 消息发送，不影响 LED、按键边沿事件、Health 上报、本地组合键或 App 访问设备。

## 目标

- 加入 Space 后，App 本地默认启用 Battery Power Switch。
- 加入 Space 阶段不下发 `SET 0x4C 0x03 0x01`，因为固件默认启用。
- 禁用成功后，手机上不能模拟发送控制命令，中间控制面板禁用；真实 Battery Power Switch 按键不再发送 SIG client 控制消息。
- 启用成功后，手机模拟发送和真实按键 TX 恢复正常。
- 只有 `SET 0x4C 0x03` 成功后，才更新本地数据库并触发云同步。
- Monitor 页直接切换 Enable 需要等待用户激活设备，并在弹窗内重试发送 enable/disable 命令。
- Edit 页 Enable 只修改编辑态，点击 SAVE 后再统一进入激活和 Sync 流程。

## 非目标

- 不实现 `GET 0x4C 0x03` 主动读取或设备真实状态纠偏。
- 不改变 refresh battery 流程。
- 不改变 LED 开关 `0x4C 0x02` 的业务语义。
- 不支持 v1.0.22 之前固件的兼容分支。本功能只面向最新协议固件。

## 方案选择

采用独立 TX Enable 同步项。

`0x4C 0x00` key configuration 只负责按钮功能，`0x4C 0x03` 只负责 Battery Power Switch 全局按键 TX 开关。`enabled` 不再用于让 key configuration 变为空，也不再写入 key configuration hash。

未采用的方案：

- 保留当前 key configuration hash 逻辑并补发 TX Enable：改动较小，但仍会混淆“按键功能配置”和“整机 TX 开关”。
- 增加 GET 状态校准：更完整，但本次需求已明确只实现下发成功后持久化。

## 数据模型

`PJEightKeySwitchData.enabled` 继续作为 App 的目标启用状态，用于 UI、本地数据库、导入导出和云同步。

新增一组独立的 Battery Power Switch TX Enable 应用状态，用于判断本地目标状态是否已经成功写到设备。实现可以采用以下方式之一，但语义必须一致：

- `appliedTxEnabled: Bool?`
- 或独立 hash/version 字段，例如 `desiredTxEnableHash` / `appliedTxEnableHash`

推荐使用 `appliedTxEnabled: Bool?`，因为当前命令只有一个布尔值，hash 没有必要。

同步判断：

- `needsBatteryPowerSwitchConfigurationSync` 不再因为 `enabled` 变化而变为 true。
- 新增 `needsBatteryPowerSwitchTxEnableSync`，当 `appliedTxEnabled != enabled` 时为 true。
- `needsBatteryPowerSwitchSync` 应包含 key configuration、TX Enable、target group subscription 三类需求。
- Add 阶段创建默认 Battery Power Switch 时，`enabled = true` 且 `appliedTxEnabled = true`，表示设备默认值已满足，不需要下发 `enable=1`。

Key Config 生成规则：

- `batteryPowerSwitchDesiredConfigHash(appKeyIndex:)` 不包含 `enabled`。
- `batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 不因 `enabled == false` 返回空数组。
- 若缺少 `linkGroupAddress`，仍按现有逻辑无法生成 key configuration。

## SDK 协议支持

本地 `NordicSigMeshSDK` 需要新增 `0x4C 0x03` 支持：

- `VendorBatteryPowerSwitchCode.txEnable = 0x03`
- `VendorFunctionSet.batteryPowerSwitchTxEnabled(Bool)`
- `VendorFunctionGet.batteryPowerSwitchTxEnabled` 可不对 App 暴露使用，但底层 status code 应能识别该 response。
- `VendorFunctionCode.batteryPowerSwitchTxEnabled` 或等价 response code 映射。
- `SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(false))` 参数为 `0x4C 0x03 0x00`。
- `SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(true))` 参数为 `0x4C 0x03 0x01`。
- 成功判定为收到 `SunricherVendorStatus`，且 `status.isSuccessful == true`，response code 为 `batteryPowerSwitchTxEnabled`。

## Monitor 页即时切换

Battery Power Switch 设备页底部 `Enable` UISwitch 切换时，不立刻更新数据库或云：

1. 用户切换 UISwitch。
2. UI 进入 pending 状态。Enable 控件临时不可重复点击，中间控制面板不提前切到新状态，避免用户误以为已成功。
3. 弹出复用现有激活弹窗样式与语义的 `Save After Activation` / `激活后保存`。
4. 等待用户按设备按键激活。
5. 设备激活后，每 3 秒发送一次 `SET 0x4C 0x03 <enable>`。
6. 收到成功响应后：
   - 更新 `switchData.enabled`
   - 更新 TX Enable 已应用状态
   - 保存 `DeviceSwitchData` 与 `PJEightKeySwitchRepository`
   - 发送现有刷新通知，触发列表、页面和云同步链路
   - 弹窗展示成功后关闭，刷新 UI
7. 60 秒仍未成功时，弹窗提示 timeout，提供 `CANCEL` 与 `TRY AGAIN`：
   - `CANCEL`：恢复切换前状态，不保存本地，不同步云。
   - `TRY AGAIN`：重新进入 60 秒等待和 3 秒发送循环。

禁用成功后，现有中间控制面板 disabled 样式和 `disabledTapAction` 继续生效，手机模拟发送不执行。启用成功后恢复正常。

## Edit SAVE 流程

Edit 页 `Enable` 行只修改编辑态，不立即发送协议命令。

点击 SAVE 后统一判断：

- 如果 `enabled` 未变化，不创建 TX Enable 同步任务。
- 如果 `enabled` 变化，创建 `batteryPowerSwitchTxEnable(switchData:)` 同步任务。
- 如果同时需要 Key Config 和 TX Enable：
  - 需要 `Save After Activation` / `激活后保存` 弹窗。
  - 激活后进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。
  - 顺序为 `Key Config` -> `TX Enable` -> target group subscription/unsubscription。
- 如果不需要 Key Config，但需要 TX Enable：
  - 需要激活弹窗。
  - 激活后进入 Sync device(s)。
  - 顺序为 `TX Enable` -> target group subscription/unsubscription。
- 如果不需要 Key Config，也不需要 TX Enable，仅需要更新 target group subscription/unsubscription：
  - 不需要激活弹窗。
  - 直接进入 Sync device(s)。

这个编排合理，因为 Key Config 和 TX Enable 都写 Battery Power Switch 本机 NVS，需要通信窗口；target group subscription 写目标灯具或组内设备，不依赖 Battery Power Switch 被激活。

## Sync 队列

新增 Battery Power Switch own configuration 类型：

```text
batteryPowerSwitchTxEnable(switchData:)
```

Sync device(s) 中 Battery Power Switch 自身配置包含：

- `batteryPowerSwitchKeyConfig`
- `batteryPowerSwitchTxEnable`

own configuration 相关判断需要同步包含 TX Enable：

- 是否需要激活
- 是否属于 Battery Power Switch configuration
- 是否属于 Battery Power Switch own configuration
- 是否属于 Battery Power Switch sync operation
- 失败后是否触发重新激活 resync
- backActionCallback 中成功/失败状态记录

成功规则：

- `batteryPowerSwitchTxEnable` 必须生成至少 1 条 message handle，空 handles 不能算成功。
- 收到成功响应才算成功。
- 成功后记录 `appliedTxEnabled = enabled` 或等价应用状态。
- 若本轮 Key Config 和 TX Enable 都存在，二者都成功后，Battery Power Switch own configuration 才算完整成功。

失败规则：

- Monitor 页即时切换失败或 timeout：不保存 `enabled`，UI 恢复旧值，不同步云。
- Edit SAVE 中 TX Enable 失败：不把新的 `enabled` 作为最终成功状态同步云。实现时应保留 SAVE 前旧 `enabled` 快照；own configuration 失败时回滚 `enabled` 到旧值，标记 sync failed，并让用户重试。
- 如果只同步 target group，沿用现有成功/失败逻辑。

## 持久化与云同步边界

只有本地数据库保存成功后，才通过现有通知触发云同步。

Monitor 页即时切换：

- TX Enable 成功前不保存、不通知。
- 成功后保存并通知。

Edit SAVE：

- 如果 SAVE 涉及 Key Config 或 TX Enable，进入 Sync 前不保存最终状态到本地和云。
- Sync 成功后保存最终状态并通知。
- Sync 失败时不保存失败的 `enabled` 目标值。
- 如果 SAVE 只涉及 target group subscription/unsubscription，不涉及 Battery Power Switch own configuration，则沿用现有直接进入 Sync 的行为，但仍应避免在最终失败时把未完成的目标状态当作成功状态同步。

## UI 状态

Monitor 页：

- `enabled == false` 时，中间控制面板禁用，点击提示现有 `neightkeyswitches_disabled_tip`。
- 切换 pending 时，Enable 控件不可重复点击。
- pending 不应让中间控制面板提前进入新状态。

Edit 页：

- Name 行下方的 Enable 行保持现有位置。
- 切换 Enable 只影响 SAVE 按钮状态。
- 不在 Edit 页切换时弹窗或发送命令。

## 验证计划

- SDK 单元测试覆盖 `SET 0x4C 0x03 0x00` 与 `SET 0x4C 0x03 0x01` 参数编码。
- SDK status 解析覆盖 `RET 0x4C 0x03 0x00` 成功响应。
- 静态检查 `batteryPowerSwitchDesiredConfigHash` 不再包含 `enabled`。
- 静态检查 `batteryPowerSwitchKeyConfigurations` 不再因 `enabled == false` 返回空。
- Monitor 页 disable 成功后，面板禁用且本地状态保存。
- Monitor 页 disable timeout/cancel 后，UI 和本地状态恢复旧值。
- Edit 页只改 Enable 时，SAVE 后展示激活弹窗，成功后保存，失败后不保存新 enabled。
- Edit 页只改 target group 时，不展示激活弹窗，直接进入 Sync。
- Key Config + TX Enable 同时存在时，Sync 顺序为 `Key Config` -> `TX Enable` -> target group。
- iPhoneOS Debug build 通过：

```text
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
