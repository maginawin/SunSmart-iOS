# BPS 与 Light 同时恢复后 Light 误判同步失败分析

## 背景

场景：在 Site - Space - 添加设备 - 恢复设备数据中同时恢复两个设备：

- battery power switch
- light

旧数据中 light 位于 battery power switch 的 target groups 中，因此恢复后 light 需要订阅 battery power switch 的虚拟组。现象是 light 先显示恢复成功；battery power switch 后显示恢复成功；随后 light 又被改成恢复失败，需要同步。但实际 battery power switch 已经可以控制 light。

## 日志结论

这次日志不支持 “Mesh 配置失败” 这个结论，反而说明 BPS 控制链路已经恢复成功。

关键地址：

- light 新地址：`0x01B2`，十进制 `434`，日志中使用 `L1's Device Key`
- battery power switch 新地址：`0x01B5`，十进制 `437`，日志中使用 `SW1's Device Key`
- BPS 目标虚拟组：`0xC00B`，十进制 `49163`

关键证据：

- light 的模型绑定、profile、场景、LC 参数、默认值等大量配置返回 `Success`。
- BPS 的 `batteryPowerSwitchKeyConfig`、`batteryPowerSwitchTxEnabled`、`batteryPowerSwitchLEDEnabled` 均返回成功。
- BPS 配置中多次使用 `address: 49163`，即旧 target group 虚拟组地址。
- light 对 `0xC00B` 的订阅也返回成功，例如 `ConfigModelSubscriptionStatus(status: Success, address: 49163, elementAddress: 434/435/436, ...)`。
- 恢复末尾 BPS 的 `GenericBatteryGet` 成功，说明 BPS 节点可通信且 restore 成功后的读电量流程正常。

日志中出现过一次 `SWIFT TASK CONTINUATION MISUSE: send(_:from:to:withTtl:) leaked its continuation without resuming it`。这说明并发发送路径存在 SDK 层异步 continuation 风险，但本次 light 后续仍持续收到成功回包，且 BPS 控制链路可用，所以它不是 light 被最终标记同步失败的直接证据。它应作为并发恢复的次级风险单独跟踪。

## 代码原因

主因在 `DeviceRestoreViewController` 的完成态复判。

在 `addSuccess` 中，设备先被标记为 success。非 BPS 设备只有在 `node.needSync` 且不是邻近照明同步项时，才会被标记为 `syncFailed`。

位置：

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:768`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:785`

但在 `addFinish` 中，所有设备完成后会重新扫描 `restoreNodes`，只要非 BPS 节点 `node.needSync == true`，就把成功列表里的设备状态改成 `syncFailed`。

位置：

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:821`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:825`

这导致一个竞争窗口：

1. light 先完成 append messages，状态显示 success。
2. BPS 继续恢复 key config / tx / led 等配置。
3. BPS 完成后触发 `addFinish`。
4. `addFinish` 用更宽泛的 `node.needSync` 复判所有已恢复节点。
5. light 因残留同步项被改成 `syncFailed`。

`node.needSync` 本身是一个宽泛布尔值，会覆盖组订阅、profile、场景、日程、动能开关、邻近照明、设备参数、Dongle、Gateway 等多个同步来源。

位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1898`
- `SunSmart/Common/Data/Node+SyncData.swift:369`
- `SunSmart/Common/Data/Node+SyncData.swift:623`

其中 BPS target group 同步来源在 `getNodeSyncSwitchs`，只要 `getBatteryPowerSwitchTargetSubscriptionMessageHandles(...)` 还返回待发送消息，就会认为该 light 仍需同步。

位置：

- `SunSmart/Common/Data/Node+SyncData.swift:1403`
- `SunSmart/Common/Data/Node+SyncData.swift:1418`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1808`

另一个关键点是，`Node.updateData(message:)` 目前只在普通所属组订阅成功时清理 `restoreData.addGroupAddress` / `groupState`。对于 BPS 虚拟组订阅，相关逻辑仍是注释占位，没有把“虚拟组订阅已恢复成功”写回到可让 `needSync` 消失的状态。

位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2411`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2414`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2428`

因此，本次问题本质是恢复流程的完成态判断误用了全局 `needSync`：它把已经由本轮恢复成功发送过的 BPS target 虚拟组订阅，继续当成需要用户同步的失败项。

## 修复目标

恢复完成后的 UI 状态应满足：

- 如果 BPS 恢复成功，且 light 对 BPS link group 的 target subscription 在本轮恢复中已经成功发送，则 light 保持 success。
- 如果 light 确实还有其它未完成同步项，仍应显示 sync failed。
- 如果 BPS 自身 key config / tx / led 恢复失败，BPS 仍应显示失败，不应被目标 light 的状态掩盖。
- 不改变非 BPS 恢复、普通组恢复、邻近照明外部同步的既有行为。

## 修复计划

1. 把 `DeviceRestoreViewController` 中 “恢复后是否应该显示同步失败” 收敛成一个专用判断方法，避免 `addSuccess` 和 `addFinish` 使用两套条件。

2. 在 BPS restore session 中记录本轮成功恢复的 BPS link group 地址。可在 `finalizeBatteryPowerSwitchRestoreConfiguration(for:)` 成功调用 `BatteryPowerSwitchAddConfiguration.markSucceeded(...)` 后记录 `switchData.linkGroupAddress`。

3. 在 `addFinish` 的复判里，不再直接使用 `!node.isBatteryPowerSwitch && node.needSync`。改为调用专用判断方法：

   - 继续排除 BPS 节点。
   - 继续保留邻近照明的特殊规则，和 `addSuccess` 保持一致。
   - 计算节点的实际 sync data，而不是只看 `needSync`。
   - 如果剩余 sync data 只来自本轮成功恢复 BPS 的 target subscription，则不把 light 标记为 `syncFailed`。
   - 如果还存在 profile、scene、schedule、普通 group、设备参数、非本轮 BPS 订阅等其它同步项，则继续标记 `syncFailed`。

4. 补充诊断日志。每次准备把已成功设备改成 `syncFailed` 时，打印：

   - node address / name
   - sync data 类型摘要
   - 是否命中 BPS restored link group 过滤
   - BPS link group 地址

   这样后续现场日志能直接解释 UI 状态变化，不需要只靠底层 Mesh 回包推断。

5. 优先补单元级覆盖。如果当前工程已有可复用测试入口，抽出纯判断函数后覆盖以下用例：

   - BPS restore 成功，light 只剩该 BPS link group target subscription：不标记同步失败。
   - light 还有其它 profile / scene / schedule / parameter sync data：仍标记同步失败。
   - BPS restore 失败或 link group 不在本轮成功集合内：不吞掉目标订阅同步失败。
   - 邻近照明 sync data：保持现有外部同步行为。

6. 手动验证场景：

   - 同时恢复 battery power switch + light，light 原本在 BPS target groups 中。
   - 验证 light 完成后保持 success，不在 BPS 成功后被改成 sync failed。
   - 验证 BPS 能控制 light。
   - 验证 BPS 初始电量读取成功。
   - 验证单独恢复存在真实未同步项的 light，仍能显示 sync failed。

7. 构建验证按项目规则执行：

   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 实施结果

已在 `DeviceRestoreViewController` 内完成聚焦修复：

- 新增恢复 session 级别的 BPS link group 跟踪：
  - 待恢复 BPS link group
  - 已成功恢复 BPS link group
  - 本轮已收到成功回包的 BPS target subscription
- `addSelectedBtnClick` 在开始恢复前记录本轮被选中 BPS 的 link group，避免 light 先完成时被误判。
- `finalizeBatteryPowerSwitchRestoreConfiguration(for:)` 在 BPS 厂商配置成功后记录成功恢复的 link group，并在 BPS 完成后移除 pending 状态。
- `appendMessageSuccessBack` 在收到 `ConfigModelSubscriptionStatus` 成功回包时，记录当前 light 已成功订阅的 BPS target group。
- `addSuccess` 与 `addFinish` 统一调用同一个恢复同步判断方法，不再分别使用不同条件。
- 判断逻辑只过滤“本轮 BPS 恢复已经覆盖的 target subscription”：
  - `deviceSuccess` 阶段：如果 link group 属于本轮 pending 或 successful BPS，先不把 light 判为失败，避免 BPS 尚未完成时出现假失败。
  - `batchFinish` 阶段：只有同时满足 BPS link group 成功恢复、且对应 target subscription 收到成功回包，才忽略该项。
  - 如果还存在 profile、scene、schedule、普通 group、设备参数等其它同步项，仍会标记 `syncFailed`。
- 保留邻近照明同步的既有例外行为。
- 增加恢复同步判定诊断日志，后续现场日志可直接看到被标记或被过滤的 sync data 摘要。

## 验证结果

- `git diff --check` 通过，无空白错误。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过，输出 `** BUILD SUCCEEDED **`。
- 工程当前没有 XCTest/unit-test target，因此没有可运行的单元测试目标。此次通过小范围内部方法边界、静态差异检查和 iOS Debug 构建验证。

## 风险点

- 不能简单移除 `addFinish` 的同步失败复判，因为它可能仍承担“所有恢复设备完成后再判断跨设备同步项”的职责。
- 不能简单把 light 的 `needSync` 清掉，因为它可能同时包含其它真实未同步数据。
- 修复应只过滤本轮 BPS restore 已成功覆盖的 link group target subscription，不能泛化为忽略所有 BPS target subscription。
- `SWIFT TASK CONTINUATION MISUSE` 说明并发 restore 仍有 SDK 发送层风险；本次可不作为主修复，但完成状态判定加日志后，如果仍出现真实超时，可再单独排查发送队列/continuation 生命周期。
