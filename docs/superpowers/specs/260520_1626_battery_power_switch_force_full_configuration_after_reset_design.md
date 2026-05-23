# Battery Power Switch Reset 后强制完整配置设计

## 背景

Battery Power Switch 在 SAVE 或 Sync device(s) 的 configuration 流程中，执行 reset 后需要重新下发完整自身配置。近期对 `.batteryPowerSwitchModelPublication` 的调整把发送逻辑改成依赖本地 `model.publish` 状态：当本地认为 publication 已配置时，会生成空的 publication 命令列表，并被判定为成功。

这个判断在 reset 后不可靠。reset 是设备端 vendor 命令，会清掉真实设备配置，但本地 mesh model 缓存不一定同步清除。因此 reset 后若仍按本地 publication 状态跳过发送，设备端可能缺少 Profile Client Model Publication，导致按键无法 publish 到虚拟 switch group，表现为基本不能控制设备。

## 目标

- 保留 activation 与 re-sync 的需求：configuration 失败后，RE-Sync 前仍需要等待 Battery Power Switch 激活，并从 reset 开始重发。
- 每次 reset 成功发送后，必须重新下发完整 Battery Power Switch 自身配置。
- reset 后的 Key Config 和 Model Publication 不能因本地缓存看起来已配置而被跳过。
- 不恢复“默认成功”逻辑。关键配置步骤必须以本轮命令发送结果为准。

## 非目标

- 不修改 target group subscription / unsubscription 的业务规则。
- 不改 Battery Power Switch capability 检测协议。
- 不处理无关设备类型、普通 EnOcean switch、profile、scene、schedule 的同步逻辑。

## 方案

采用方案 A：Reset 后强制完整 BPS 自身配置。

同步顺序保持为：

1. Reset
2. Key Config
3. Model Publication
4. Target group subscription / unsubscription

当本轮 Battery Power Switch configuration 执行过 reset 后：

- Key Config：按当前 `PJEightKeySwitchData` 生成完整按键配置并发送。
- Model Publication：对 Battery Power Switch 的全部 Profile Client Models 强制生成 publication set 命令，等价于使用 `includeExisting: true`。
- 成功判定：不能因为本地 `getBatteryPowerSwitchPublicationMessageHandles(... includeExisting: false).isEmpty` 就判定成功；本轮有命令时必须依赖命令结果。

如果没有执行 reset，则普通 group-only sync 仍不需要触发 BPS 自身 configuration，也不需要 activation。

## 设计细节

### SyncDevicesViewController

增加本轮上下文标记，用于表示当前 BPS configuration 已执行 reset，例如：

- `batteryPowerSwitchConfigurationResetCompleted`

当 `.batteryPowerSwitchReset` 对应任务成功后设置为 true。后续 `.batteryPowerSwitchKeyConfig` 和 `.batteryPowerSwitchModelPublication` 构造 message handles 时读取该状态：

- reset completed 为 true：强制完整发送。
- reset completed 为 false：保持普通差异发送或当前既有逻辑。

fail-fast 行为保留：BPS 自身 configuration 任一步失败后，当前 BPS 后续自身 configuration 任务标记失败，RE-Sync 需重新 activation 并从 reset 开始。

### DeviceOperationType / message handles

避免在全局 `DeviceOperationType.messageHandles` 中隐式依赖本地 publication 状态完成 reset 后配置。实现上可以新增专门的 helper，由 `SyncDevicesViewController` 在发送 BPS own configuration 时构造 handles，并传入是否强制完整发送。

Model Publication 强制模式下：

- 使用 `node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: includeExisting: true)`。
- 对返回的 handles 设置当前已有的发送策略，例如 `continuous = false`。

### 成功判定

`.batteryPowerSwitchModelPublication` 不再仅依赖本地状态空列表判定成功。

建议规则：

- 如果本轮发送了 publication handles，全部 handle 成功才算成功。
- 如果本轮因为没有 reset、且确实无需发送 publication，则可按现有本地状态校验。
- reset 后 publication handles 为空应视为异常失败，而不是成功，因为 reset 后必须重新设置全部 publication。

## 风险与验证

主要风险是同步框架目前的成功判定同时看发送结果和 `operationType.isSuccessful`。修复时需要确保 reset 后强制发送 publication 的上下文能够传递到成功判定，避免本轮发送成功却被旧本地缓存误判失败，或本轮未发送却被误判成功。

验证方式：

- 静态检查 reset 后 `.batteryPowerSwitchModelPublication` 使用强制完整 publication handles。
- 静态检查 group-only sync 不触发 BPS own reset/key/publication。
- 构建验证：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 手动验证建议：
  - 修改 Scene Profile 的 scene target 后 SAVE，激活后确认 reset、key config、model publication 均发送。
  - 人为让 publication 失败后 RE-Sync，确认先 activation，再从 reset 开始完整重发。
  - 仅添加/删除 group，确认不弹 activation，不发送 reset/key/publication，只发送目标设备 subscription/unsubscription。
