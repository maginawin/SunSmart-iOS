# Battery Power Switch Identify Activation 设计

## 背景

Battery Power Switch 监控页右上角菜单已有 `Identify` 选项。当前实现点击后直接调用标准 SIG Mesh identify：

- 页面：`PJEightKeySwitchMonitorVC`
- 入口：`moreAction()` 中的 `Identify` 菜单项
- 当前动作：`MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)`

Battery Power Switch 是低功耗设备，直接发送 identify 时，如果设备未被用户按键激活，设备可能无法接收命令。现有 enable/disable 流程已经有一套等待用户激活设备的弹窗和探测机制。本次要把 Identify 改成同样先等待激活，再持续发送 identify。

## 目标

- 点击右上角 `Identify` 后，弹出等待设备激活的底部弹窗。
- 弹窗标题为 `Identify Device`。
- 提示文案复用 enable/disable 的激活提示，即当前面板类型对应的 `switchData.eightKeyPanelType.activationInstruction`。
- 中间 loading、success、failure 状态样式复用 enable/disable 激活弹窗。
- 等待激活时，后台每 3 秒发送一次与 enable/disable 相同的激活探测命令，持续 60 秒。
- 收到成功响应后，显示 `Device Activation Detected` 1 秒。
- 之后切换为 `Identifying...`，每 3 秒发送一次标准 SIG Mesh identify 命令。
- `Identifying...` 阶段持续到用户点击 `CANCEL`，不自动超时。
- 60 秒未检测到设备激活时显示 `No response detected`，提供 `CANCEL` 和 `TRY AGAIN`。
- `TRY AGAIN` 重新回到 `Waiting for switch activation (60s)...`。

## 非目标

- 不修改 enable/disable 的现有行为。
- 不修改 Refresh Device 的电量刷新流程。
- 不修改 SDK 协议实现。
- 不把 Battery Power Switch identify 改成 Sunricher 私有 identify 协议。
- 不改变菜单展示条件；未绑定虚拟 Battery Power Switch 仍不展示 `Identify`。

## 方案选择

采用独立 `PJEightKeySwitchIdentifyFlow`，复用现有 `PJEightKeySwitchActivationAlertController` 和 `PJEightKeySwitchActivationAlertView`。

选择原因：

- Identify 与 enable/disable 都需要等待低功耗设备被用户激活，但激活后的动作不同。
- enable/disable 成功后需要保存状态并关闭弹窗；identify 成功激活后需要进入持续发送状态，直到用户取消。
- 独立 flow 可以复用 UI，又避免把 `PJEightKeySwitchTxEnableFlow` 的状态机扩展得过于复杂。

不采用的方案：

- 扩展 `PJEightKeySwitchTxEnableFlow` 为通用激活后发送 flow：复用代码更多，但会混入 enable/disable 的持久化和自动关闭语义。
- 直接在 `PJEightKeySwitchMonitorVC.identifyAction()` 内写 timer：改动更少，但控制器会承担过多状态机细节，取消和重试清理更容易出错。

## 命令设计

### 等待激活阶段

等待激活阶段必须复用 enable/disable 的探测命令，不使用电量读取命令。

具体发送：

- 使用现有 `MeshBatteryPowerSwitchActivationDetector`
- 内部发送 `SunricherVendorGet(function: .batteryPowerSwitchCapability)`
- 发送到 `node.sunricherVendorModel`
- 成功条件沿用现有逻辑：
  - response 是 `SunricherVendorStatus`
  - `status.status.isSuccessful == true`
  - `status.status.code == .batteryPowerSwitchCapability`

发送节奏：

- 进入 waiting 后立即发送一次。
- 之后每 3 秒发送一次。
- 60 秒内收到成功即进入 detected。
- 60 秒仍未成功则进入 timeout。

### 识别阶段

识别阶段发送标准 SIG Mesh identify。

具体发送：

- `MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)`
- 不传 `ack`，保持默认无回复发送。
- 不等待响应，不因单次发送失败显示错误。

发送节奏：

- 进入 `Identifying...` 后立即发送一次。
- 之后每 3 秒发送一次。
- 一直持续到用户点击 `CANCEL`。

## 状态机

`PJEightKeySwitchIdentifyFlow` 状态：

- `idle`：尚未开始。
- `waiting`：展示 `Waiting for switch activation (%ds)...`，运行 60 秒倒计时和 3 秒 activation probe timer。
- `detected`：展示 `Device Activation Detected`，停止 waiting timer，1 秒后进入 identifying。
- `identifying`：展示 `Identifying...`，每 3 秒发送 SIG Mesh identify，无倒计时。
- `noResponse`：展示 `No response detected`，提供 `CANCEL` 和 `TRY AGAIN`。
- `cancelled`：停止所有 timer 和延迟任务，关闭弹窗。

每次进入 waiting 或 retry 时生成新的 `generation`，所有异步回调必须检查 generation 与 state，避免旧响应影响新流程。

## UI 文案

新增本地化 key：

- `neightkeyswitches_identify_title`
  - English: `Identify Device`
  - 简中：`识别设备`
- `neightkeyswitches_identifying`
  - English: `Identifying...`
  - 简中：`正在识别...`

复用现有 key：

- `neightkeyswitches_activation_waiting_format`
- `neightkeyswitches_activation_detected`
- `neightkeyswitches_activation_timeout`
- `cancel`
- `try_again`

## 文件影响

预计修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 增加 `identifyFlow` 引用。
  - `identifyAction()` 改为启动 `PJEightKeySwitchIdentifyFlow`。
  - `deinit` 中取消 identify flow。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 新增 `PJEightKeySwitchIdentifyFlow`。
  - 新增 `PJEightKeySwitchIdentifySending` 协议和默认 SIG Mesh sender。
  - 复用现有 `PJEightKeySwitchActivationDetecting` 等待激活。

- `SunSmart/en.lproj/Localizable.strings`
  - 新增英文文案。

- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增简中文案。

不需要修改其它品牌资源、target 配置或 SDK 依赖。

## 错误处理

- `informationNode` 不存在：点击 identify 后显示现有 `failed` 提示，不启动流程。
- waiting 阶段 probe 失败：不提示，继续等待下一次 probe。
- timeout：停止所有发送，显示 `No response detected`。
- `CANCEL`：停止所有 timer、延迟任务和旧 generation，关闭弹窗。
- `TRY AGAIN`：生成新 generation，重新进入 60 秒 waiting。
- `Identifying...` 阶段不处理单次 identify 发送失败，不显示成功或失败提示。

## 测试与验证

开发完成后验证：

- `Identify` 菜单点击后会展示 `Identify Device` 弹窗，不再直接只发送一次 identify。
- waiting 阶段复用 enable/disable 的 `SunricherVendorGet(function: .batteryPowerSwitchCapability)`，间隔 3 秒。
- waiting 阶段 60 秒未检测到激活时显示 `No response detected`，按钮为 `CANCEL` 和 `TRY AGAIN`。
- `TRY AGAIN` 会重新进入 60 秒 waiting。
- 检测到激活后显示 `Device Activation Detected` 1 秒。
- 进入 `Identifying...` 后每 3 秒发送一次 `MeshAPI.identify(address:attentionTimer:)`。
- `Identifying...` 阶段不自动超时，点击 `CANCEL` 后停止发送并关闭弹窗。
- enable/disable 原有激活流程行为不变。
- Refresh Device 电量刷新流程行为不变。

构建验证使用项目推荐命令：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 风险

- Identify 阶段不等待 ack，因此无法从 App 侧确认每次 identify 是否被设备实际执行。这符合当前标准 SIG Mesh identify 静默发送策略。
- 用户长时间停留在 `Identifying...` 会持续每 3 秒发送 identify；由于必须用户主动进入并可随时取消，范围可控。
- 如果设备激活窗口很短，3 秒 probe 间隔可能错过部分窗口；该间隔与 enable/disable 保持一致，避免不同流程表现不一致。
