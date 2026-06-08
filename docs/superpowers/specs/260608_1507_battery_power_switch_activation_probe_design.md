# Battery Power Switch Activation Probe 设计

## 背景

Battery Power Switch 是低功耗设备。App 在下发部分自身配置或执行特定设备动作前，会先展示等待激活弹窗，让用户按键唤醒设备。当前等待激活探测统一由 `MeshBatteryPowerSwitchActivationDetector` 执行。

现有探测命令是 `SunricherVendorGet(function: .batteryPowerSwitchCapability)`，对应 Vendor GET `0x4C 0x01`。本次要求统一改为 Vendor GET `0x4C 0x03`，用该命令判断设备是否处于已激活、可响应状态。

SDK 中已经存在 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)`，其参数为 `0x4C 0x03`，响应 code 为 `.batteryPowerSwitchTxEnabled`。因此本次不新增协议定义，优先复用现有 SDK 能力。

## 当前等待激活流程

所有等待激活探测都会复用 `PJEightKeySwitchActivationDetecting` 和默认实现 `MeshBatteryPowerSwitchActivationDetector`。

涉及流程如下：

- `PJEightKeySwitchActivationFlow`
  - Battery Power Switch 保存后，如果需要同步自身配置，先等待激活。
  - 入口包括详情页保存、编辑/预添加保存、Group Power Switch 保存。
  - `SyncDevicesViewController` 同步失败后，选择包含 Battery Power Switch 自身配置的失败项并 Re-Sync，也会再次等待激活。
- `PJEightKeySwitchIdentifyFlow`
  - Identify 前先等待激活，检测成功后持续发送标准 SIG Mesh identify。
- `PJEightKeySwitchTxEnableFlow`
  - Battery Power Switch enable/disable 前先等待激活，检测成功后发送 TX Enable 设置命令。

## 目标

1. 所有等待激活探测统一发送 Vendor GET `0x4C 0x03`。
2. 不再使用 Vendor GET `0x4C 0x01` 作为等待激活探测命令。
3. 保持现有弹窗、倒计时、轮询间隔、超时、重试、同步页和后续动作不变。
4. 保持改动聚焦，不重构同步队列、Mesh 消息系统或 Power Switch 数据模型。

## 非目标

- 不修改 Battery Power Switch 自身配置命令。
- 不修改 TX Enable 设置命令。
- 不修改 Identify 的 SIG Mesh identify 命令。
- 不新增 SDK 协议 case。
- 不改变 AC Power Switch 行为。
- 不改变等待激活弹窗 UI 和本地化文案。

## 推荐方案

采用集中替换 detector 的方案。

修改 `MeshBatteryPowerSwitchActivationDetector.sendActivationProbe(to:completion:)`：

- 发送命令从 `SunricherVendorGet(function: .batteryPowerSwitchCapability)` 改为 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)`。
- 成功判断从 `.batteryPowerSwitchCapability` 改为 `.batteryPowerSwitchTxEnabled`。
- 仍然要求响应是 `SunricherVendorStatus`，且 `status.status.isSuccessful == true`。
- 不读取或使用返回的 enabled Bool，收到成功响应即认为设备已激活。

选择原因：

- 所有等待激活流程已经通过同一个 detector 抽象，集中替换可以一次覆盖 SAVE、Re-Sync、Identify、TX Enable。
- 复用 SDK 已有 `0x4C 0x03` GET 定义，避免引入重复协议枚举。
- 改动范围最小，风险集中在一个类。

## 备选方案

### 各 flow 单独注入新 detector

可以分别控制 SAVE、Identify、TX Enable 的探测命令，但本次需求是全部统一，拆分会增加不必要复杂度。

### 新增专门 activation status 协议 case

如果后续协议文档明确 `0x4C 0x03` 不应归类为 TX Enable GET，而是独立 Activation Status，可以在 SDK 中新增语义更准确的 case。当前 SDK 已经把 `0x4C 0x03` 映射为 `batteryPowerSwitchTxEnabled`，本次先复用现有实现。

## 数据流

1. 用户触发需要等待激活的操作。
2. 对应 flow 展示 waiting 弹窗。
3. flow 立即调用 detector 发送一次 activation probe。
4. 后续每 3 秒继续调用 detector。
5. detector 发送 Vendor GET `0x4C 0x03` 到 `node.sunricherVendorModel`。
6. 如果收到成功的 `.batteryPowerSwitchTxEnabled` 响应，flow 切换为 detected。
7. detected 后继续执行原有后续动作：
   - SAVE / Re-Sync：进入或重启 `SyncDevicesViewController` 同步。
   - Identify：进入 identifying 状态并持续发送 identify。
   - TX Enable：发送 TX Enable 设置命令。
8. 60 秒内没有成功响应时，仍按现有逻辑显示 no response，允许取消或重试。

## 错误处理

- `node.sunricherVendorModel` 不存在：立即回调未检测到，flow 继续等待下一轮或最终超时。
- 响应不是 `SunricherVendorStatus`：视为未检测到。
- 响应 code 不是 `.batteryPowerSwitchTxEnabled`：视为未检测到。
- 响应 unsuccessful：视为未检测到。
- 返回 enabled 为 true 或 false 都不影响激活判断，只要响应成功即可。

## 文件影响

预计修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 更新 `MeshBatteryPowerSwitchActivationDetector` 的发送命令和成功判断。

预计不修改：

- SDK 源码和 SDK 测试。
- `SyncDevicesViewController` 同步队列逻辑。
- Power Switch view model 和数据模型。
- 本地化、资源、target 配置和依赖。

## 验证

静态验证：

- `MeshBatteryPowerSwitchActivationDetector` 不再使用 `.batteryPowerSwitchCapability`。
- 等待激活探测改用 `.batteryPowerSwitchTxEnabled`。
- 其它 Battery Power Switch capability GET 使用点不受影响。
- `PJEightKeySwitchActivationFlow`、`PJEightKeySwitchIdentifyFlow`、`PJEightKeySwitchTxEnableFlow` 仍共用默认 detector。

构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

手动验证建议：

- Battery Power Switch SAVE 需要自身配置同步时，等待激活阶段发送 `0x4C 0x03`。
- 同步失败后 Re-Sync 同类配置时，等待激活阶段发送 `0x4C 0x03`。
- Identify 等待激活阶段发送 `0x4C 0x03`，检测成功后仍发送 SIG Mesh identify。
- Battery Power Switch enable/disable 等待激活阶段发送 `0x4C 0x03`，检测成功后仍发送 TX Enable 设置命令。

## 风险

- 当前 SDK 将 `0x4C 0x03` 解析为 TX Enable 状态。用于激活判断时，语义上依赖“设备能成功回复该 GET 即代表已激活”，而不是依赖 TX Enable 的开关值。
- 如果部分固件版本对 `0x4C 0x03` GET 支持不一致，等待激活可能无法检测成功；但这是本次协议要求指定的探测命令，应以新命令为准。

## 自检

- 无待确认占位内容。
- 方案范围只覆盖等待激活探测，不改变后续业务命令。
- 设计与当前代码结构一致：所有等待激活 flow 共用默认 detector。
- 文件影响不涉及本地化、资源、target 配置或依赖。
