# Battery Power Switch Activation Alert 设计

## 背景

Battery Power Switch 在保存配置时可能需要先让用户按键激活设备。设备未激活时，App 发出的能力读取命令会过期；设备激活并回复后，App 才能继续下发 Battery Power Switch configuration 全命令和配置设备命令。

当前代码中已经有接近 Figma 设计的 `PJEightKeySwitchActivationAlertView` 和 `PJEightKeySwitchActivationAlertController`，但现状仍偏向专用 demo：状态结果由本地延迟模拟，Mesh 检测逻辑尚未接入。新设计应在复用现有 UI 的基础上，把弹窗抽象为可配置控件，并把 Battery Power Switch 的激活检测放在独立业务协调层中。

Figma 读取到的三个状态页面为：

- `waiting for switch activation`
- `switch detected`
- `switch no response`

三者布局一致，只改变状态图标、状态文字和底部按钮数量。

## 目标

1. 将现有激活弹窗改造成可复用状态弹窗控件，支持标题、副标题、状态文字、状态类型、底部按钮数量和按钮文字配置。
2. 弹窗不允许通过点击空白遮罩关闭，只能由弹窗按钮或业务自动关闭逻辑关闭。
3. Battery Power Switch SAVE 时，如果需要发送 configuration 命令，则先展示激活弹窗。
4. waiting 状态从 60s 开始倒计时，每秒更新 UI，每 2s 重发一次 Battery Power Switch capability GET。
5. 收到符合 `Vendor RET 0x4C 0x01 0x00` 的成功响应后进入 detected 状态。
6. detected 短暂展示后自动关闭弹窗，并进入现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 流程。
7. 60s 内没有收到成功响应则进入 no response 状态，允许用户取消或重试。
8. 保持改动聚焦，不重构无关 Switch 编辑、同步和 Mesh 消息系统。

## 非目标

- 不替换现有 `SyncDevicesViewController`。
- 不在弹窗内直接执行 configuration 全命令。
- 不新增新的 Battery Power Switch 协议定义；使用 SDK 现有 `SunricherVendorGet(function: .batteryPowerSwitchCapability)`。
- 不解析 `button_count`、`trigger_count`、`config_version` 的具体值作为激活成功条件。
- 不改变非 Battery Power Switch 的 SAVE 行为。

## Figma 设计要点

弹窗是底部 sheet：

- 画布基准：375 x 812。
- 遮罩：黑色，30% opacity。
- 弹窗高度：356。
- 弹窗位置：底部贴边。
- 顶部圆角：15。
- 内容背景：`#F8FAFC`。
- 按钮区背景：白色。
- 顶部分割线：0.5pt 视觉线。
- 双按钮状态中间有竖向分割线。

文字样式：

- 标题：`Save After Activation`，17pt，Regular，颜色 `#2E315D`，居中。
- 副标题：14pt，Regular，颜色 `#94A3B8`，宽度约 300，居中，支持换行。
- 状态文字：14pt，Regular，颜色 `#64748B`。
- 普通按钮：16pt，Light，颜色 `#404F66`。
- 主按钮：16pt，Light，颜色 `#6667AB`。

状态展示：

- waiting：loading icon + `Waiting for switch activation (%ds)...`，一个 `CANCEL` 按钮。
- detected：success icon + `Device Activation Detected`，一个 `CANCEL` 按钮。
- no response：failure icon + `No response detected`，`CANCEL` 和 `TRY AGAIN` 两个按钮。

## 组件设计

保留现有 `PJEightKeySwitchActivationAlertView` 的布局基础，将其职责收敛为纯展示控件。控件不直接知道 Battery Power Switch、profile、倒计时或 Mesh 协议。

建议抽象出以下配置概念：

- 弹窗文本配置：标题、副标题、状态文字。
- 状态展示类型：loading、success、failure。
- 按钮配置：标题、样式、点击回调。
- 展示更新接口：一次性应用完整内容，避免调用方分散更新多个 label 和 icon。

现有 controller 可继续承载 modal presentation，但应去掉 demo result 逻辑。业务状态由外部 flow 或 coordinator 驱动。

遮罩 view 只做视觉遮罩，不添加 tap dismiss。`modalPresentationStyle` 继续使用 `.overFullScreen`，保证遮罩覆盖当前页面并保留当前导航栈。

## Battery Power Switch 激活 Flow

新增一个轻量业务协调层，负责 Battery Power Switch SAVE 前的激活检测。它可以是独立 coordinator，也可以是专用 controller 的内部 flow object，但不要把 Mesh 检测逻辑放进 view。

职责：

- 创建并展示弹窗。
- 进入 waiting 状态时启动 60s 倒计时。
- 每秒刷新倒计时状态文字。
- 每 2s 发送一次 capability GET。
- 收到成功响应后切到 detected。
- 超时后切到 no response。
- 处理 cancel、try again、自动关闭和页面释放。

SAVE 入口流程：

1. 用户点击 SAVE。
2. 执行现有保存前检查和 desired configuration 准备。
3. 如果不是 Battery Power Switch，或 Battery Power Switch 不需要同步，则沿用现有保存流程。
4. 如果是 Battery Power Switch 且需要同步，则展示激活弹窗。
5. waiting 成功检测到设备激活后，短暂展示 detected。
6. detected 自动关闭弹窗，进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。
7. 同步成功或失败后的状态标记、持久化、通知刷新和返回逻辑沿用现有实现。

## 状态机

### waiting

进入条件：

- SAVE 触发后需要 Battery Power Switch 同步。
- no response 状态点击 `TRY AGAIN`。

行为：

- 倒计时设置为 60s。
- UI 每秒更新 `Waiting for switch activation (%ds)...`。
- 每 2s 发送一次 capability GET。
- 底部只有 `CANCEL`。

退出：

- 收到成功响应：进入 detected。
- 倒计时到 0：进入 no response。
- 用户点击 `CANCEL`：停止倒计时和轮询，关闭弹窗，不进入同步。

### detected

进入条件：

- 当前 flow 仍在 waiting，并收到符合协议的成功响应。

行为：

- 停止倒计时。
- 停止后续轮询。
- 展示 success icon 和 `Device Activation Detected`。
- 短暂延迟后自动关闭弹窗，并启动现有同步页面。

退出：

- 自动关闭：进入同步页面。
- 用户点击 `CANCEL`：只关闭弹窗，不进入同步页面。

### no response

进入条件：

- 60s 内没有收到成功响应。

行为：

- 停止倒计时。
- 停止后续轮询。
- 展示 failure icon 和 `No response detected`。
- 底部按钮为 `CANCEL` 和 `TRY AGAIN`。

退出：

- `CANCEL`：关闭弹窗，不进入同步。
- `TRY AGAIN`：重置为 waiting，重新开始 60s 倒计时和 2s 轮询。

## Mesh 协议和成功判定

激活检测命令使用 SDK 已有接口：

- `SunricherVendorGet(function: .batteryPowerSwitchCapability)`

它对应协议：

- 请求：`Vendor GET 0x4C 0x01`
- 成功返回：`Vendor RET 0x4C 0x01 0x00 <button_count> <trigger_count> <config_version>`

成功判定：

- 收到符合 `Vendor RET 0x4C 0x01 0x00` 的成功响应即可认为设备已激活。
- 不需要解析或校验 `button_count`、`trigger_count`、`config_version` 的实际值。
- 如果没有响应、响应失败、响应无法解析为成功的 Battery Power Switch capability status，则保持 waiting，直到下一轮轮询或 60s 超时。

并发和晚到回调处理：

- 每轮 GET 使用 flow 的当前 generation 或 session id 标记。
- 只处理当前 generation 且状态仍为 waiting 的响应。
- flow 已 cancel、timeout、detected 或 deinit 后，晚到回调必须被忽略。
- `TRY AGAIN` 会创建新的 generation，旧 generation 的回调不影响新一轮等待。

## Profile 文案

标题：

- `Save After Activation`

brightness profile 副标题：

- `Press 'Button 75%' and 'Button ON' to activate the device.`

scene profile 副标题：

- `Press 'Button 2' and 'Button ON' to activate the device.`

状态文字：

- waiting：`Waiting for switch activation (%ds)...`
- detected：`Device Activation Detected`
- no response：`No response detected`

按钮：

- `CANCEL`
- `TRY AGAIN`

现有本地化 key 已覆盖主要文案，可继续复用；如需严格匹配 Figma 的 `TRY AGAIN`，可以新增或复用适合的本地化 key，但不要影响其他 `retry` 使用场景。

## 错误和取消处理

- waiting 点击 `CANCEL`：停止倒计时和轮询，关闭弹窗，不保存同步成功状态，不进入同步页面。
- detected 点击 `CANCEL`：关闭弹窗，并取消自动进入同步页面。
- no response 点击 `CANCEL`：关闭弹窗，不进入同步页面。
- no response 点击 `TRY AGAIN`：重新开始 waiting；不重新执行 SAVE 前数据准备。
- 页面退出或弹窗释放：停止 timer，并让所有晚到 Mesh callback 失效。
- Mesh 消息发送失败不立即切 no response；继续等待下一轮发送，直到 60s 到点。

## 影响范围

重点文件：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

SDK 侧使用现有能力，不计划修改：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

## 验证范围

1. waiting 状态显示 Figma 对应布局，每秒倒计时，从 60s 开始。
2. waiting 状态每 2s 发送一次 `Vendor GET 0x4C 0x01`。
3. 收到 `Vendor RET 0x4C 0x01 0x00` 后进入 detected。
4. detected 短暂展示后自动关闭，并进入现有 Battery Power Switch 同步页面。
5. detected 点击 `CANCEL` 时只关闭弹窗，不进入同步页面。
6. 60s 无成功响应后进入 no response。
7. no response 点击 `TRY AGAIN` 重新开始倒计时和轮询。
8. waiting 和 no response 点击 `CANCEL` 都不会进入同步页面。
9. brightness 和 scene profile 的激活提示文案正确。
10. 非 Battery Power Switch SAVE 不弹激活弹窗。
11. Battery Power Switch 不需要同步时不弹激活弹窗。
12. 晚到 Mesh callback 不会改变已取消、已超时或新一轮等待的状态。
13. `SunSmart` Debug iphoneos 编译通过：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 待实施时注意

- 不要保留 `scheduleActivationDemoResult` 这类 demo 结果切换逻辑。
- 不要让弹窗 view 直接调用 Mesh API。
- 不要因为抽象通用组件而重命名或迁移大量无关文件。
- 若新增本地化 key，需要同步 `en` 和 `zh-Hans`。
- 设计中的 detected 自动关闭延迟建议在实现计划中固定为 0.8 到 1.2 秒之间的具体值。
