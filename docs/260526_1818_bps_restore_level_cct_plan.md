# BPS 恢复后 Level Up/Down 仍控制色温问题分析与修复方案

## 背景

用户在恢复 light + BPS 设备后，配网和配置均显示成功，但 BPS 的 level up/down 仍然会控制色温。

本次日志来自已经应用过 action-aware BPS target subscription 方案后的恢复流程。

## 日志关键证据

1. 新增的 BPS target planner 调试日志已经生效：

   ```text
   [BPS Target] subscribe node=01D3, group=C00B, actions=8,8,8,8,3,4,4,3,4,4,2,6,2, desired=01D3/1000,01D3/1002,01D3/1300,01D5/130F
   ```

   这说明当前根据按键动作计算出的目标模型是正确的：

   - `01D3/1000`: Generic OnOff Server
   - `01D3/1002`: 主元素上的 Generic Level Server，用于亮度 level up/down
   - `01D3/1300`: Light Lightness Server
   - `01D5/130F`: Light LC Server

   这里没有 `01D4/1002`。

2. 日志后续仍然出现错误订阅：

   ```text
   Sending Access PDU (opcode: 0x801B, parameters: 0xD4010BC00210)
   ConfigModelSubscriptionStatus(status: Success, address: 49163, elementAddress: 468, modelIdentifier: 4098, ...)
   ```

   解码结果：

   - `0x801B`: ConfigModelSubscriptionAdd
   - `D401`: element `0x01D4`
   - `0BC0`: group `0xC00B`
   - `0210`: model `0x1002`, Generic Level Server

   `01D4/1002` 是 CTL Temperature element 上的 Generic Level Server。它被订阅到 BPS link group `C00B` 后，BPS 发出的 level move/delta 就会同时命中色温 element，导致色温变化。

## 根因判断

上一次修改的 BPS 专用 planner 本身没有问题，它计算出的 desired set 不包含 `01D4/1002`。

问题来自另一条通用订阅路径：恢复流程会执行 `newNode.getSyncData(type: .all)`，再通过 `NodeSyncData.getMessageHandles(node:)` 生成 `.subscribeGroup` 消息。通用组订阅逻辑会根据节点支持模型批量补组订阅，不理解 BPS link group 是控制链路组，不应按普通房间组处理。

因此，恢复数据里只要 BPS link group `C00B` 被当作普通 group 参与同步，就可能绕过 BPS 专用 planner，重新给 `01D4/1002` 下发订阅。

## 修复目标

1. BPS link group 的 target subscription 只能由 BPS action-aware planner 生成。
2. 通用 group subscription 不能对 BPS link group 自动补全所有可订阅模型。
3. 本方案不处理历史错误订阅；验证时通过重置设备后重新配置确认不会再次写入错误订阅。
4. 普通房间组、场景、LC、sensor、schedule 等现有同步逻辑不受影响。

## 修复方案

### 1. 抽出 BPS 目标模型身份判断

在 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 中，把当前私有的 BPS desired model 计算能力扩展为可复用判断：

- 根据 `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 计算允许订阅的目标模型。
- 用 `elementAddress + modelIdentifier` 做身份比较，避免依赖 Model 对象实例。
- `levelDelta` / `levelMove` 只允许主亮度元素上的 `Generic Level Server`，不允许 CTL Temperature element 的 `Generic Level Server`。

### 2. BPS link group 禁止走普通组订阅补全

在通用 `.subscribeGroup(group)` 消息生成路径加保护：

- 如果 group address 命中任一 BPS `linkGroupAddress`，不要调用普通 `node.getSubscribeToGroupMessages(group)`。
- 对该 group 找到对应 BPS switchData 后，改用 `node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(...)`。
- 如果找不到 switchData，则跳过并记录 DEBUG 日志，避免误把控制链路组当房间组。

重点检查路径：

- `SunSmart/Common/Data/Node+MessageHandles.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- `SunSmart/Main/Group/Model/GroupServer.swift`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

### 3. 恢复流程增加兜底过滤日志

在 `DeviceRestoreViewController` 的 append messages 阶段增加 DEBUG 兜底：

- 对发往 BPS link group 的 `ConfigModelSubscriptionAdd` 做一次 allowed set 校验。
- 如果发现 `01D4/1002 -> C00B` 这类非 desired 消息，阻止下发并打印：

  ```text
  [BPS Target] skip stale restore subscription node=01D3 group=C00B model=01D4/1002
  ```

这层不是主逻辑，只用于防止恢复链路还有遗漏入口。

不生成 `ConfigModelSubscriptionDelete`，因为本轮验证基于设备重置后重新配置，不需要清理历史错误订阅。

## 验证计划

1. 构建验证：

   ```text
   xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
   ```

2. 重新恢复同一组 light + BPS。

3. 日志中应保留：

   ```text
   [BPS Target] subscribe node=01D3, group=C00B, desired=01D3/1000,01D3/1002,01D3/1300,01D5/130F
   ```

4. 日志中不应再出现：

   ```text
   Sending Access PDU (opcode: 0x801B, parameters: 0xD4010BC00210)
   ConfigModelSubscriptionStatus(status: Success, address: 49163, elementAddress: 468, modelIdentifier: 4098, ...)
   ```

5. 操作验证：

   - BPS level up/down 只改变亮度。
   - 色温保持不变。
   - On/Off、Lightness Set、LC 开关等原 BPS 按键功能仍正常。
   - 普通房间组同步仍能补齐 lightness、CTL、LC 等正常订阅。

## 风险与边界

- 不能全局禁止 Generic Level 订阅，只能针对 BPS link group 做 action-aware 限制。
- 如果未来 BPS 动作新增色温控制，allowed set 需要根据 `.ctlTemperatureSet` 明确允许 `temperatureModel`。
- 已经被错误恢复过且不重置的现场，本方案不会主动删除 `01D4/1002`。

## 实现结果

已完成本方案中的代码修改：

- 增加 `MeshNetworkManager.batteryPowerSwitchData(linkGroupAddress:)`，用于识别 BPS link group。
- 增加 `Node.getSunSmartSubscribeToGroupMessageHandles(...)`，BPS link group 统一改走 action-aware BPS target planner。
- `NodeSyncData`、空间同步、组成员订阅入口均改用上述安全订阅入口。
- 恢复 append message 阶段增加兜底过滤，阻止非 desired 的 `ConfigModelSubscriptionAdd` 写入 BPS link group。
- 未增加历史错误订阅清理逻辑，符合本轮“重置设备后重新配置”的验证前提。

## 验证结果

- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`：通过。
- 核心路径源码守卫：未再发现直接调用 `node.getSubscribeToGroupMessages(group/self)` 或用该结果做 count 判断。
- `git diff --check`：通过。
