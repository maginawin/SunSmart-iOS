# AC power switch Space Offline 控制拦截分析与方案

## 结论

问题真实存在。

AC power switch 监控页在 Space Offline 时会展示 `Space Offline`，但只要 switch 处于 Enabled，面板虚拟按钮仍保持可点击。点击后当前代码会继续尝试通过 `MeshAPI.sendMessage` 向 `switchData.linkGroupAddress` 发送组控制命令，没有先拦截蓝牙 mesh 未连接状态，也不会提示用户。

正常在线时，点击 AC power switch 页面里的虚拟按钮确实应该向该 power switch 的 linked group 发送控制命令。Space Offline 时命令无法发出，应在 App 侧提前拦截，并复用现有 toast key `device_notconnect_message`：

`This operation requires the phone's bluetooth connection to the device.`

## 代码事实

- AC power switch 的 Space Offline 状态来自 `PJEightKeySwitchMonitorViewModel.acHeaderState()`：
  - `isSpaceMeshConnected` 直接读取 `MeshLibManager.manager.isMeshNetworkConnected`
  - mesh 未连接时 `statusText = "space_offline".localizedString`
- AC power switch 页面刷新连接状态的观察者只触发 `updateUI()`，不会改变按钮命令发送逻辑。
- 面板按钮是否可点由 `viewModel.settingsState.isEnabled && !isTxEnablePending` 决定；这里没有 mesh 连接判断。
- 面板短按入口 `handlePanelKeyTap(index:)` 只排除了未 LINK 的虚拟 power switch 和短时间重复点击，随后直接调用 `virtualGroupControlSender.sendKeyTap(...)`。
- 长按 dimming / Auto 的最终确认也直接调用同一个 sender：
  - `sendBrightness(...)`
  - `sendAuto(...)`
- `PJEightKeySwitchVirtualGroupControlSender` 三个发送方法都从 `switchData.linkGroupAddress` 取目标地址，并通过 `MeshAPI.sendMessage(...)` 发送到 group。
- `device_notconnect_message` 已存在于英文和简体中文本地化文件。

## 影响范围

本次建议只修 AC power switch 监控页的虚拟面板控制入口：

- 短按 8 个虚拟按键
- dimming 弹窗确认发送 brightness
- Auto 弹窗确认发送 auto command

不默认扩大到以下入口，除非后续确认一起处理：

- 底部 Enabled 开关，属于配置 AC power switch TX enable，目标是真实 power switch node，不是 linked group
- Identify
- Refresh
- Battery power switch 的激活/同步流程
- Edit / Delete / Add Device 流程

## 开发方案

1. 在 `PJEightKeySwitchMonitorViewModel` 增加一个语义化判断，例如“是否允许发送面板组控制命令”。
   - 对 AC power switch：必须 `MeshLibManager.manager.isMeshNetworkConnected == true`
   - 对其他 power switch：保持现有行为，避免扩大 Battery 行为面

2. 在 `PJEightKeySwitchMonitorVC` 增加统一拦截方法。
   - mesh 未连接时显示 `"device_notconnect_message".localizedString`
   - 返回 false，阻止继续调用 sender
   - 这样短按、dimming 确认、Auto 确认可以复用同一判断

3. 在三个面板控制入口前加 guard。
   - `handlePanelKeyTap(index:)`
   - `brightnessEndedAction`
   - `autoAction`

4. 保持 UI 展示不变。
   - Space Offline 时仍显示 `Space Offline`
   - Enabled 状态仍按当前 switch 配置展示
   - 点击时给 toast，而不是把整个面板直接禁用；这样符合“Enabled 但当前手机未连接设备”的语义

## 验证计划

1. 静态核查：
   - 确认三个 sender 入口都被同一个 offline guard 覆盖。
   - 确认 `device_notconnect_message` 没有新增 key，不触碰本地化资源。

2. 编译验证：
   - 按项目规则运行 iPhoneOS 构建：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

3. 手工验证：
   - AC power switch `0x0A78 / 0x2A11` 或 `0x0A78 / 0x2A12` 已 LINK group。
   - 断开当前 space 的蓝牙 mesh 连接，页面显示 `Space Offline`。
   - Switch 处于 Enabled。
   - 点击虚拟按钮、dimming 确认、Auto 确认，均显示 `This operation requires the phone's bluetooth connection to the device`，且不发送 group command。
   - 恢复蓝牙 mesh 连接后，相同操作仍能向 linked group 发送控制命令。

## 待确认

请确认是否按以上范围实现：只拦截 AC power switch 监控页的虚拟面板 group control，不扩大到底部 Enabled 开关、Identify、Refresh。
