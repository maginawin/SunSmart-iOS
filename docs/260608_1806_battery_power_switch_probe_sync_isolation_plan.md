# Battery Power Switch Activation Probe 与 Sync 队列隔离优化计划

## 背景

上一轮日志分析显示，Battery Power Switch 保存失败的高概率原因不是设备拒绝 `batteryPowerSwitchKeyConfig`，而是 activation probe 的 `GET 0x4C03` 与 Sync 队列中的 `SET 0x4C00` key config 在同一目标节点上发生重叠。

当前 probe 使用 `MeshAPI.sendMessage(message:model:timeout:result:)`。该 API 会按 `SunricherVendorStatus` 的 opcode 注册等待回调，并且会主动调用 `cancelNotifyCallback` 清理同 source/opcode 的旧等待。底层 `NetworkManager.cancel(messageWithHandler:)` 又会按 destination address 移除 `responseCallbacks`。由于 `GET 0x4C03` 和 `SET 0x4C00` 的响应 opcode 都是 `0xF3780A`，只在 vendor parameters 中区分业务 code，当前 callback/cancel 粒度不足以安全并发。

## 目标

- activation probe 和 Sync 队列串行隔离：进入 `SyncDevicesViewController` 前，上一轮 probe 必须已经成功、失败或被明确废弃，不允许有可超时取消的残留 probe。
- activation probe 不再使用会取消同节点其它 response callback 的发送方式。
- 不改变 Battery Power Switch 的业务协议：probe 仍使用 Vendor GET `0x4C03`，成功判断仍是收到 `.batteryPowerSwitchTxEnabled` 成功 status。
- 不扩大到 AC Power Switch、普通设备、Emergency Fire Controller 或通用 Sync 队列重构。

## 非目标

- 不把失败简单改成忽略 `cancelled`。
- 不只通过延长 timeout 降低复现概率。
- 不整体重写 `NetworkManager.responseCallbacks` 存储模型。
- 不改变 key config、TX Enable、LED Indicator、target subscription 的业务顺序。

## 首选方案

采用双层隔离：

1. SDK 层新增一个给 app-key acknowledged message 使用的 no-response-callback 发送路径。
   - 发送 `SunricherVendorGet(.batteryPowerSwitchTxEnabled)` 时，不注册 `responseCallbacks`。
   - 不调用 `cancelNotifyCallback`。
   - probe timeout 只结束 probe 自己的等待，不调用普通 `MessageHandle.cancel()`，不取消同节点其它 acknowledged message。

2. App 层让 activation flow 等待当前 probe 完整收尾后再执行 `onDetectedCompleted`。
   - 检测成功后先停止 timer，标记不再发新 probe。
   - 最后一条 probe 的 completion 返回后，再 dismiss alert 并进入 Sync。
   - 即使 callback 晚到，也只能影响当前 activation generation，不能再触发旧 flow 的状态推进。

这个方案比整体改 `responseCallbacks` 更聚焦，也比把 probe 接入 `MeshProxyMessageCommand` 更清晰：probe 仍是独立检测动作，但不会污染 Sync 队列和底层 response callback。

## 文件影响

### SDK 仓库

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`
  - 给 app-key mesh message 发送增加可选的 `awaitResponse` 控制，默认保持现有行为。

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
  - 新增 app-key `AcknowledgedMeshMessage` 的 no-response-callback 内部发送方法。

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager+Callbacks.swift`
  - 公开到 SDK 内部 API：对目标 model 发送 acknowledged mesh message，但不等待 response callback。

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift`
  - 新增专用于 filtered vendor probe 的发送 helper，避免复用现有会 `cancelNotifyCallback` 的 `sendMessage`。

- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NetworkManagerCancellationTests.swift`
  - 增加 no-response-callback 路径不会注册或清理同节点 `responseCallbacks` 的回归测试。

### App 仓库

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 调整 `PJEightKeySwitchActivationDetecting` 抽象，使 flow 能知道 probe 是否已经完成。
  - `MeshBatteryPowerSwitchActivationDetector` 改用 SDK 新 helper。
  - `PJEightKeySwitchActivationFlow`、`PJEightKeySwitchIdentifyFlow`、`PJEightKeySwitchTxEnableFlow` 统一处理 in-flight probe 状态。

- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 确认 SAVE 入口仍只在 activation flow detected 后 push Sync。

- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 确认编辑/预添加保存入口没有绕过 activation flow。

- Inspect: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
  - 确认 Group Power Switch 保存入口仍复用同一 activation flow。

## Task 1：用测试固定 SDK 取消边界

- [ ] 在 `NetworkManagerCancellationTests.swift` 新增测试：同一 destination 已存在 `responseCallbacks[destination]` 时，no-response-callback 发送不应覆盖该 callback。
- [ ] 新增测试：no-response-callback 发送本身不写入 `responseCallbacks`，也不主动清理既有 `responseCallbacks[destination]`。
- [ ] 运行 SDK 相关测试：
  - `swift test --filter NetworkManagerCancellationTests`
- [ ] 期望结果：新增测试先失败，证明当前缺少安全发送路径。

## Task 2：新增 SDK no-response-callback app-key 发送路径

- [ ] 在 `AccessLayer.swift` 中为 app-key mesh message 发送增加 `awaitResponse` 参数，默认值为 true。
- [ ] 当 `awaitResponse == false` 时，不创建 reliable acknowledgment context，但仍通过 upper transport 发送 PDU。
- [ ] 在 `NetworkManager.swift` 中新增 app-key acknowledged message 的 `sendWithoutWaitingForResponse` 内部方法。
- [ ] 该方法不写入 `outgoingMessages`，不写入 `responseCallbacks`，也不通过 timeout cancel 当前 destination。
- [ ] 不改变普通 `MessageHandle.cancel()` 的既有语义；activation probe helper 不应向 App 层暴露这个 handle，也不应在 timeout 时调用它。
- [ ] 在 `MeshNetworkManager+Callbacks.swift` 中新增面向 `Model` 的 wrapper，复用现有 `send(_:from:to:model:)` 的关键校验：
  - mesh network 必须存在。
  - target model 必须属于 element。
  - target model 必须绑定 app key。
  - local provisioner 必须有 source element。
  - TTL 必须合法。
- [ ] 跑测试：
  - `swift test --filter NetworkManagerCancellationTests`
- [ ] 期望结果：Task 1 新增测试通过，既有 cancellation 测试不回退。

## Task 3：新增 filtered vendor probe helper

- [ ] 在 `MeshAPI.swift` 新增 Battery Power Switch activation probe helper。
- [ ] helper 发送 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)` 时使用 Task 2 的 no-response-callback path。
- [ ] helper 单独等待 `SunricherVendorStatus`，并在 completion 中过滤：
  - message 类型必须是 `SunricherVendorStatus`。
  - status 必须 successful。
  - status code 必须是 `.batteryPowerSwitchTxEnabled`。
- [ ] helper 的 timeout 只返回 probe 失败，不调用 `cancelNotifyCallback`，也不调用 `cancel(messageWithHandler:)` 取消同节点其它发送。
- [ ] helper 只向调用方暴露 detected/failed 结果，不向 App 层暴露底层 `MessageHandle`。
- [ ] 补充 SDK 测试：
  - `BatteryPowerSwitchVendorMessageTests` 继续覆盖 `GET 0x4C03` 编码和 status 解析。
  - 如果测试架构允许，增加 helper timeout 不清理 `responseCallbacks` 的测试；如果 helper 依赖真实 mesh network 太重，则在 `NetworkManagerCancellationTests` 中覆盖底层行为即可。
- [ ] 跑 SDK 测试：
  - `swift test --filter BatteryPowerSwitchVendorMessageTests`
  - `swift test --filter NetworkManagerCancellationTests`

## Task 4：App activation flow 串行隔离

- [ ] 调整 `PJEightKeySwitchActivationDetecting`，让调用方能标记 probe generation 与 in-flight 状态。
- [ ] `MeshBatteryPowerSwitchActivationDetector` 改为调用 Task 3 的 SDK helper。
- [ ] 在 `PJEightKeySwitchActivationFlow` 中维护当前 probe 是否 pending。
- [ ] 检测成功时停止 timer，不再发新 probe；如果当前 completion 已经返回成功，则按现有 1 秒成功展示后进入 Sync；如果还有异步尾部，则等尾部 completion 归档后再进入 Sync。
- [ ] 在 cancel/no response/deinit 时递增 generation，废弃旧 completion；旧 completion 不允许 dismiss、不允许 push Sync、不允许重启 timer。
- [ ] 同步把相同机制应用到 `PJEightKeySwitchIdentifyFlow` 和 `PJEightKeySwitchTxEnableFlow`，避免三套 flow 出现不同的 probe 生命周期语义。
- [ ] 静态检查：
  - activation detector 不再调用 `MeshAPI.sendMessage(... timeout: 1.5)`。
  - activation detector 使用新的 filtered probe helper。
  - 三个 flow 的旧 completion 都受 generation 与 state 双重保护。

## Task 5：Sync 入口保护与日志验证

- [ ] 在 `PJEightKeySwitchActivationFlow.completeDetected` 前增加调试日志，记录 `probeCompletedBeforeSync=true`。
- [ ] 在 `MeshBatteryPowerSwitchActivationDetector` 或 SDK helper 增加临时调试日志，记录 probe start、success、timeout、ignored stale completion。
- [ ] 手动复测 Battery Power Switch SAVE：
  - 进入 Sync 前最后一条 `GET 0x4C03` 已经完成。
  - Sync 期间不再出现旧 probe 的 `Response to Access PDU (opcode: 0xF1780A, parameters: 0x4C03) not received (timeout)`。
  - key config button 0 到最后一条全部收到 `0x4C0000` success。
  - `SyncDevicesViewController` 的 `完成` 不早于最后一条 key config 的 success callback。
- [ ] 验证无 UI 文案变化，无本地化变更，无资源变更。

## Task 6：构建与回归验证

- [ ] SDK 测试：
  - `swift test --filter NetworkManagerCancellationTests`
  - `swift test --filter BatteryPowerSwitchVendorMessageTests`
- [ ] App 构建：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] 如果本次修改 SDK 源码但 App 仍引用远程 package，需要先按项目规则确认 `NordicSigMeshSDK` 是否已经切到本地路径；没有切换时不要误判 App build 结果。
- [ ] 最终检查：
  - `git diff --check`
  - `git status --short`
  - 只提交 SDK 发送路径、App activation flow、相关测试与本计划。

## 风险与取舍

- `AccessLayer.send` 增加 `awaitResponse` 参数必须保持默认 true，避免影响现有 acknowledged message 行为。
- no-response-callback 发送不应被泛化到普通业务命令；本次只用于 activation probe 这种“收到即代表唤醒”的探测。
- filtered wait 仍按 `SunricherVendorStatus` opcode 接收消息，所以必须依赖 App 层串行隔离来避免误消费 Sync 的 key config status。
- 如果后续还要支持多个并发 vendor status 等待，应另起设计，按 vendor main code/subcode 建立更细粒度 callback key；本次不建议扩大到这个层面。

## 验收标准

- Battery Power Switch SAVE 前 activation probe 与 Sync key config 不再重叠。
- probe timeout 不再取消同节点其它 `responseCallbacks`。
- SAVE 失败日志中不再出现 `GET 0x4C03 timeout` 后紧跟 key config `cancelled`。
- SDK cancellation 相关测试通过。
- SunSmart iPhoneOS Debug build 通过。
