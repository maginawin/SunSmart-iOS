# Battery Power Switch Identify Auto Stop 开发计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 当前项目偏好 Inline Execution，不默认使用 subagents。

**目标：** Battery Power Switch 进入 `Identifying...` 后，每 3 秒持续发送标准 SIG Mesh Identify 命令，但最长只持续 60 秒；达到 60 秒后 App 主动停止发送并关闭 `Identify Device` 弹窗。

**架构：** 保持现有 `PJEightKeySwitchIdentifyFlow` 作为 Identify 状态机的唯一 owner，只在识别阶段增加独立 60 秒生命周期控制。等待激活阶段、探测命令、`CANCEL`、`TRY AGAIN`、菜单入口和本地化文案不变。

**技术栈：** Swift, UIKit, Timer, NordicSigMeshSDK, existing `PJEightKeySwitchActivationAlertController`, existing `PJEightKeySwitchIdentifyFlow`。

---

## 真实性判断

当前问题真实存在。

已确认现有实现路径：

- `PJEightKeySwitchMonitorVC.moreAction()` 的 `Identify` 菜单会调用 `identifyAction()`。
- `identifyAction()` 会创建并持有 `PJEightKeySwitchIdentifyFlow`。
- `PJEightKeySwitchIdentifyFlow` 等待激活阶段已有 60 秒倒计时和 3 秒 activation probe。
- 激活成功后会展示 `Device Activation Detected`，1 秒后进入 `Identifying...`。
- `startIdentifying()` 进入识别阶段后立即发送一次 Identify，并通过 `identifyTimer` 每 3 秒重复发送。
- `stopTimers()` 会停止 `identifyTimer`，`cancel()` 会关闭弹窗并触发 `onFinished`。

缺口是：识别阶段没有 60 秒自动终止计时器，也没有到期后主动关闭弹窗的完成路径。因此只要用户不点击 `CANCEL`，`identifyTimer` 会一直运行。

## 需求边界

本次只补齐识别阶段的自动终止，不改变以下行为：

- 点击右上角菜单 `Identify` 后仍弹出 `Identify Device`。
- 设备激活前仍等待用户激活设备。
- 激活探测仍复用 `MeshBatteryPowerSwitchActivationDetector`。
- 等待激活阶段仍是 60 秒未响应后显示 `No response detected`，并提供 `CANCEL` / `TRY AGAIN`。
- 激活成功后仍显示 `Device Activation Detected` 1 秒，再进入 `Identifying...`。
- `Identifying...` 阶段仍每 3 秒发送一次 `MeshAPI.identify(address:attentionTimer:)`。
- 用户点击 `CANCEL` 仍立即停止发送并关闭弹窗。
- 不新增本地化文案，不修改资源，不修改 target 配置，不修改 SDK。

## 推荐方案

在 `PJEightKeySwitchIdentifyFlow` 中新增识别阶段专用的 60 秒结束机制。

推荐做法：

- 新增一个只服务于 identifying 阶段的 timer 或延迟 work item，命名上表达 `identifyAutoStop` / `identifyTimeout` 语义。
- 在 `startIdentifying()` 中启动自动终止计时，与现有 3 秒 `identifyTimer` 同步进入生命周期。
- 自动终止触发时只在当前状态仍为 `.identifying` 时生效，避免旧异步任务影响 retry、cancel 或新一轮流程。
- 自动终止触发后复用现有清理能力：停止所有 timer、取消延迟任务、dismiss 弹窗、调用 `onFinished`，让 `PJEightKeySwitchMonitorVC.identifyFlow` 被置空。
- `cancel()`、`deinit`、`startWaiting()`、`showNoResponse()`、`showDetected()` 等会离开 identifying 或重置流程的路径，都必须取消这个自动终止机制。

推荐不复用 waiting 阶段的 `remainingSeconds` 作为 identifying 阶段倒计时。原因是当前 UI 在 identifying 阶段只显示 `Identifying...`，需求没有要求展示剩余秒数；复用 countdown 会让等待激活和识别发送两个阶段的语义混在一起，后续更容易误改。

## 文件影响

预计只修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

不需要修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`
- `NordicSigMeshSDK`

## 开发计划

### Task 1: 增加识别阶段自动终止状态

**文件：**

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [x] 在 `PJEightKeySwitchIdentifyFlow` 的私有属性区新增 identifying 阶段自动终止句柄。
- [x] 确认该句柄只属于 Identify flow，不影响 `PJEightKeySwitchActivationFlow` 和 `PJEightKeySwitchTxEnableFlow`。
- [x] 在 `deinit` 中取消该句柄，避免页面释放后还有延迟回调。
- [x] 在 `cancel()` 中取消该句柄，保证用户点击 `CANCEL` 后不会再触发自动关闭回调。
- [x] 在 `startWaiting()` 中取消该句柄，保证 `TRY AGAIN` 或流程重启时旧 identifying 回调失效。
- [x] 在 `showNoResponse()` 中取消该句柄，保证等待激活超时状态不会被旧 identifying 回调关闭。

### Task 2: 在 `Identifying...` 阶段启动 60 秒自动终止

**文件：**

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [x] 在 `startIdentifying()` 中，进入 `.identifying`、更新 `generation`、启动 3 秒 `identifyTimer` 的同时，启动 60 秒自动终止。
- [x] 自动终止回调必须回到主线程执行 UI dismiss。
- [x] 自动终止回调必须检查当前仍是 `.identifying`，且 generation 未变化。
- [x] 到期后停止 `identifyTimer`，避免第 60 秒后继续发送 Identify。
- [x] 到期后关闭弹窗，并调用 `onFinished`。
- [x] 不显示额外失败或成功文案；需求是主动终止发送并关闭弹窗。

### Task 3: 收紧清理逻辑

**文件：**

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [x] 检查 `stopTimers()` 是否应该统一停止 identifying 自动终止句柄。
- [x] 如果自动终止使用 `DispatchWorkItem`，则增加独立取消方法，避免 `stopTimers()` 名称与 work item 语义不一致。
- [x] 确认所有退出路径只调用一次 `onFinished`。
- [x] 确认 `PJEightKeySwitchMonitorVC.deinit` 调用 `identifyFlow?.cancel()` 时不会造成循环回调或重复 dismiss 问题。

### Task 4: 静态检查与构建验证

**文件：**

- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [x] 使用 `rg` 确认新增自动终止逻辑只出现在 `PJEightKeySwitchIdentifyFlow` 内。
- [x] 使用 `git diff --check` 检查空白错误。
- [x] 运行 iPhoneOS 构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

### Task 5: 手工验证路径

**验证场景：**

- [ ] 进入真实 Battery Power Switch 监控页。
- [ ] 点击右上角菜单 `Identify`。
- [ ] 确认弹窗标题为 `Identify Device`。
- [ ] 不激活设备，确认 60 秒后仍显示 `No response detected`，且 `TRY AGAIN` 可重新等待激活。
- [ ] 再次点击 `Identify`，激活设备。
- [ ] 确认检测到激活后进入 `Identifying...`。
- [ ] 确认进入 `Identifying...` 后会持续发送 Identify。
- [ ] 在 60 秒内点击 `CANCEL`，确认弹窗关闭且不再继续发送 Identify。
- [ ] 再次进入 `Identifying...` 后不点击 `CANCEL`，确认 60 秒后 App 主动停止发送 Identify 并关闭弹窗。
- [ ] 重复打开 Identify，确认旧 timer 不会影响新流程。

## 风险与注意点

- 如果使用 `Timer`，需要确保它加入主 run loop 并在所有退出路径 invalidate。
- 如果使用 `DispatchWorkItem`，需要确保 generation 和 state 双重校验，避免旧 work item 关闭新弹窗。
- 自动关闭弹窗时不应显示 `No response detected`，因为设备已经激活且正在识别，本次只是达到持续发送上限。
- 本次不改变 Identify 命令本身，仍使用标准 SIG Mesh Identify，`attentionTimer` 仍保持当前实现的 6 秒。
- 当前工作区已有与本任务无关的未提交改动，实施时只 stage 本任务文件，避免混入 `project.pbxproj`、`GroupViewController.swift` 或既有 docs 改动。

## 完成标准

- `Identifying...` 阶段最多持续 60 秒。
- 60 秒到期后弹窗自动关闭。
- 60 秒到期后不再发送 Identify。
- 点击 `CANCEL` 仍可随时立即关闭并停止发送。
- 等待激活阶段原有 60 秒 timeout、`TRY AGAIN` 和激活探测行为不回归。
- iPhoneOS `SunSmart` scheme 构建通过。
