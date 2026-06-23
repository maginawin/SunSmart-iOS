# AC Power Switch Identify 设计

## 背景

Battery Power Switch 与 AC Power Switch 共用 CID `0x0A78`，通过 PID 区分设备类型：

- Battery Power Switch: `0x2A01`, `0x2A02`
- AC Power Switch: `0x2A11`, `0x2A12`

当前设备页面右上角菜单的 `Identify` 入口位于 `PJEightKeySwitchMonitorVC.identifyAction()`。现状是 Battery 与 AC 都进入 `PJEightKeySwitchIdentifyFlow`，该流程会展示 `Identify Device` 弹窗，等待设备激活后再发送 Identify 命令。

需求是 AC Power Switch 点击 `Identify` 后立即发送一次 Identify 命令给设备，不展示 `Identify Device` 弹窗，也不等待激活。Battery Power Switch 保持现有等待激活流程。

## 方案

采用最小分流方案，在 `PJEightKeySwitchMonitorVC.identifyAction()` 中按 `viewModel.switchData.powerSwitchKind` 判断：

- `battery`：继续创建并启动 `PJEightKeySwitchIdentifyFlow`，保持现有弹窗、激活探测、重发与自动结束行为。
- `ac`：直接向 `viewModel.informationNode.primaryUnicastAddress` 发送一次 Identify 命令，`attentionTimer` 沿用现有 `MeshBatteryPowerSwitchIdentifySender` 的 6 秒设置。

设备类型判断继续复用现有 `PJEightKeyPowerSwitchKind`，不新增 CID/PID 映射，不新增本地化文案。

## 行为边界

- 菜单展示条件不变：未绑定真实 Power Switch 的 virtual switch 不展示 `Identify`。
- 权限校验不变：没有 edit 权限时仍提示无权限。
- 真实节点缺失时仍提示失败。
- AC Power Switch 点击 `Identify` 只发送一次命令，不展示弹窗，不启动 3 秒重发 timer，不启动 60 秒自动停止流程。
- Battery Power Switch 的 Identify 行为不变。

## 涉及文件

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

预计只需要修改 `PJEightKeySwitchMonitorVC.swift`。`PJEightKeySwitchActivationAlertController.swift` 中的 `MeshBatteryPowerSwitchIdentifySender` 已封装单次发送行为，可直接复用或作为参考，不需要改变弹窗流程本身。

## 验证

完成实现后执行：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

人工验证重点：

- AC Power Switch 页面点击右上角 `Identify` 后，不出现 `Identify Device` 弹窗。
- AC Power Switch 点击后只触发一次 Identify 发送。
- Battery Power Switch 页面点击 `Identify` 后，仍出现原有 `Identify Device` 弹窗并等待激活。
