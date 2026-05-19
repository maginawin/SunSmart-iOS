# Battery Power Switch Model Publication 耗时分析

## 结论

Battery Power Switch 在更新 Profile 样式后 SAVE，或新增设备后进入 BPS 同步流程时，`Model Publication` 步骤耗时久的主要原因是：

- 当前实现对 BPS 的 Profile Client Models 使用 `includeExisting: true`，即使设备上已有相同 publication，也会重复下发。
- SDK 的 `batteryPowerSwitchProfileClientModels` 会从设备 Composition 的所有 element 中收集 BPS Profile 需要的 Client Models。
- `0x2A01.json` 与 `0x2A02.json` 中 8 个 element 都包含以下 5 个 Client Models：
  - `0x1001` Generic OnOff Client
  - `0x1003` Generic Level Client
  - `0x1205` Scene Client
  - `0x1302` Light Lightness Client
  - `0x1311` Light LC Client
- 因此 `Model Publication` 一次会生成 `8 * 5 = 40` 条 `ConfigModelPublicationSet`。
- 这些都是 acknowledged config messages，`SyncDevicesViewController` 当前给普通同步任务的 ACK timeout 是 `15s`；`MeshProxyMessageCommand` 逐条发送并等待 `ConfigModelPublicationStatus`。
- 每条命令实际等待时间按 `ackTimeout + allAddresss.count * 1s` 计算。BPS publication 是单播到 BPS 节点，因此单条超时约 `16s`。如果 BPS 是 LPN，且只能通过其他 Proxy/Friend 路径配置，status 延迟或丢失时会明显拉长整体耗时。

## 触发路径

### Edit / SAVE

`PJPreAddEightKeySwitchesVC.submitBatteryPowerSwitch(_:)`

1. Profile 样式改变后，`batteryPowerSwitchDesiredConfigHash` 中的 `panel=...` 改变。
2. `prepareBatteryPowerSwitchDesiredConfig` 将 `syncState` 置为 `.pending`。
3. 进入 `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`。
4. `appendBatteryPowerSwitchSyncModels` 固定生成 3 个 BPS 自身步骤：
   - `Reset`
   - `Key Config`
   - `Model Publication`
5. `batteryPowerSwitchModelPublication` 的 `messageHandles` 调用：
   - `node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: true)`

### Direct Add

Direct Add 成功后：

1. `DeviceAddClassicModeController` / `DeviceAddProfessionalModeController` 检测到 `node.isBatteryPowerSwitch`。
2. 调用 `MeshNetworkManager.instance.createDefaultSwitch(forBatteryPowerSwitch: node)`。
3. 默认 BPS switch data 被保存为 pending desired config。
4. 后续进入 BPS 同步或 SAVE 时，走同一套 `Reset -> Key Config -> Model Publication -> Target Group Subscription` 流程。

## Model Publication 具体发送的命令

`Model Publication` 步骤只发 BPS 自身的 publication 配置命令，不配置 target groups。

每条命令为：

```text
ConfigModelPublicationSet(
  publishAddress: switchData.linkGroupAddress,
  appKeyIndex: currentApplicationKey.index,
  ttl: networkParameters.defaultTtl,
  period: disabled,
  retransmit: count 1, interval 200ms
)
```

发送目标节点是 BPS 的 primary unicast address；命令中的 element address 与 model id 分别对应每个按键 element 的 client model。

按当前协议 JSON，发送顺序为按 element 遍历，每个 element 依次发送：

```text
Element 0: ConfigModelPublicationSet -> Generic OnOff Client    (0x1001)
Element 0: ConfigModelPublicationSet -> Generic Level Client    (0x1003)
Element 0: ConfigModelPublicationSet -> Scene Client            (0x1205)
Element 0: ConfigModelPublicationSet -> Light Lightness Client  (0x1302)
Element 0: ConfigModelPublicationSet -> Light LC Client         (0x1311)

Element 1: same 5 commands
Element 2: same 5 commands
Element 3: same 5 commands
Element 4: same 5 commands
Element 5: same 5 commands
Element 6: same 5 commands
Element 7: same 5 commands
```

合计 40 条 `ConfigModelPublicationSet`，均等待 `ConfigModelPublicationStatus`。

## SAVE 全流程还会发送哪些命令

BPS SAVE 同步顺序为：

1. `Reset`
   - 1 条 `SunricherVendorSet(.batteryPowerSwitchResetDefaults)`
2. `Key Config`
   - 多条 `SunricherVendorSet(.batteryPowerSwitchKeyConfig(...))`
   - Scene Profile：最多 13 条；未选择场景时会减少 scene recall 配置。
   - Brightness Profile：固定 13 条。
3. `Model Publication`
   - 当前实现 40 条 `ConfigModelPublicationSet`。
4. `Target Group Subscription`
   - 对每个 target group 中的设备，给 capability models 订阅 BPS 的内部虚拟组。
   - 发送 `ConfigModelSubscriptionAdd`，必要时先发送 obsolete CCT/非亮度 Generic Level 的 `ConfigModelSubscriptionDelete`。

## 为什么 Profile 样式变化会重复发 publication

Profile 样式改变后，真正需要变化的是 BPS vendor key config；publication 的目标地址通常仍然是同一个 `linkGroupAddress`，并没有随 Scene/Brightness profile 改变。

但是当前同步步骤不区分 publication 是否已经正确：

- `appendBatteryPowerSwitchSyncModels` 每次都会生成 `Model Publication` step。
- `SyncDevicesCellModel.messageHandles` 对 `.batteryPowerSwitchModelPublication` 使用 `includeExisting: true`。
- 因此即使所有 client model 的 publication 已经是目标虚拟组 + retransmit 1/200ms，也仍然重发 40 条。

## 可选优化方向

优先级较高的优化：

1. `Model Publication` 生成 message handles 时不要使用 `includeExisting: true`，改为只发送 `model.publish != expectedPublish` 的项。
2. 保持 `isSuccessful` 仍然检查所有需要的 publication 是否已经正确，避免漏配置。
3. Profile 切换时，如果 publication 地址、AppKey、TTL、period、retransmit 未变化，则 `Model Publication` step 应为空并快速完成。

进一步优化：

1. 只给当前 desired key config 实际会使用的按键 element + client model 设置 publication。
2. Scene Profile 通常只需要 scene / level / onoff / light lc 相关按键模型；Brightness Profile 通常只需要 lightness / level / onoff / light lc 相关按键模型。
3. 这样首次同步也可从 40 条降低到约 9 条左右，但需要严格按 button index 映射到对应 element，避免漏掉 Key1 位于主 element 的特殊情况。

