# EL Controller Function Test Awaiting 闪烁问题分析与方案

## 结论

问题真实存在于当前实现路径中。点击 EL Controller 页面 `Function Test - Start` 后，App 先把 Function Test 状态设置为 `Awaiting device response...`，再发送 `GET 0x01 Device Status`。当返回 `status == 0x03` 时，callback 会继续发送 Start Function Test。

但同一条 Device Status 也可能通过页面统一 vendor status 入口进入 `ELControllerFunctionTestHelper.handleStatus(...)`。当前 `handleStatus` 对 `.elControllerDeviceStatus` 会直接调用 `applyDeviceStatus(deviceStatus)`；而 `applyDeviceStatus(0x03)` 会走 `else` 分支，把 Function Test 状态改成 `.idle`，因此 UI 会短暂显示 `Tap "Start" to send command to device`。随后 Start ACK 返回后又切回 `Awaiting device response...`，形成用户看到的闪烁。

## 当前代码链路

点击 Start：

1. `ELControllerFunctionTestHelper.startFunctionTest()`：
   - `stopFunctionTestResultPolling()`
   - `updateFunctionTestState?(.awaiting)`
   - `requestDeviceStatusBeforeStart(using:)`
2. `requestDeviceStatusBeforeStart(using:)`：
   - 发送 `SunricherVendorGet(function: .elControllerDeviceStatus)`
   - `0x03` 时调用 `sendStartFunctionTest(using:)`
   - `0x0E` 时调用 `applyDeviceStatus(deviceStatus)`
   - 其他值或 timeout 时显示 `.normalModeRequired`
3. `DeviceLightViewController` 的 vendor status 通知入口：
   - 收到 `SunricherVendorStatus` 后调用 `handleELControllerVendorStatus(...)`
   - 再转给 `ELControllerFunctionTestHelper.handleStatus(...)`
4. `handleStatus(...)` 当前对 `.elControllerDeviceStatus` 统一执行 `applyDeviceStatus(deviceStatus)`。
5. `applyDeviceStatus(0x03)` 当前会 `stopFunctionTestResultPolling()` 并显示 `.idle`，造成 `Tap "Start"...` 闪烁。

## 目标行为

点击 Function Test 的 Start 后：

- 立即展示并保持 `Awaiting device response...`。
- Start 前置读取 Device Status 得到 `0x03` 时，不再短暂显示 `Tap "Start"...`。
- 因为后续肯定会发送 Start Function Test，所以 `0x03` 到 Start ACK 之间仍保持 Awaiting。
- `0x0E` 保持之前的 testing 处理：保持 Awaiting 并轮询 Function Test Result。
- other values、timeout、解析失败、非成功 ret 仍展示 `FT testing can only be performed in normal mode.`。
- 页面进入时自动读取 Device Status 的既有行为不变：非 testing 仍恢复 idle。
- RX/TX Cable、Function Test Result 轮询、Exit Function Test 不变。

## 方案对比

### 方案 A：在 helper 内增加 Start 前置校验阶段标记（推荐）

在 `ELControllerFunctionTestHelper` 中新增一个私有布尔状态，例如 `shouldIgnoreNormalDeviceStatusForFunctionTest`。

行为：

1. 点击 Start 后设置 `shouldIgnoreNormalDeviceStatusForFunctionTest = true`，UI 进入 `.awaiting`。
2. `requestDeviceStatusBeforeStart` callback 收到 `0x03` 后不清掉该标记，直接进入 `sendStartFunctionTest(using:)`，期间 UI 保持 `.awaiting`。
3. Start ACK 成功后继续保留该标记，避免更晚到的 normal Device Status 或测试后 normal status 把结果态冲回 idle；Start ACK 失败时清掉该标记。
4. 如果 `status == 0x0E`，复用既有 `applyDeviceStatus` 处理。
5. 如果失败或 other values，展示 `.normalModeRequired`。
6. `handleStatus(.elControllerDeviceStatus)` 发现 `shouldIgnoreNormalDeviceStatusForFunctionTest == true` 且 status 不是 `0x0E` 时，不调用 `applyDeviceStatus`，只消费这条 status，避免把 UI 改回 idle。
7. `stopPageSession()`、Start ACK 失败、Start 前置异常终态时清理该标记，避免页面退出或失败后残留。

优点：

- 改动只在 `ELControllerFunctionTestHelper`，不需要改 UI view、本地化或 SDK。
- 保留页面进入时 Device Status 自动读取的当前行为。
- 保留 `0x0E` testing 处理。
- 精确解决 Start 前置 `GET 0x01` 与页面统一 status 入口之间的 UI 状态竞争。

缺点：

- helper 增加一个很小的阶段状态，需要保证所有结束路径都清理。

### 方案 B：改 `applyDeviceStatus` 让 `0x03` 不再恢复 idle

让 `applyDeviceStatus` 对非 testing 状态不更新 UI 或维持当前状态。

优点：

- 代码表面更少。

缺点：

- 会影响页面进入时自动 Device Status 的既有行为。页面进入读到 normal 后原本应恢复 idle，如果不恢复，可能保留旧的 Awaiting 或结果状态。
- 影响范围比本次需求更大，不推荐。

### 方案 C：在 `sendStartFunctionTest` 前再次强制设置 Awaiting

`0x03` 后调用 `sendStartFunctionTest` 时再次 `updateFunctionTestState?(.awaiting)`。

优点：

- 实现简单。

缺点：

- 不能保证消除闪烁。若统一 status 入口在 callback 之后到达，仍可能把 UI 改回 idle。
- 只是覆盖症状，不处理状态竞争源头。

## 推荐开发方案

采用方案 A。

具体改动：

1. 在 `ELControllerFunctionTestHelper` 中新增私有状态：
   - `private var shouldIgnoreNormalDeviceStatusForFunctionTest = false`
2. `startFunctionTest()` 在进入 Awaiting 后、发送 Start 前置 Device Status 前设置该状态为 true。
3. `requestDeviceStatusBeforeStart` 的 callback 在进入主线程且确认 helper 仍 active 后，按现有 `0x03 / 0x0E / other` 分支处理。
4. `0x03` 分支保持该状态贯穿 Start ACK 成功后的等待/结果展示阶段，防止统一 status 入口晚到或测试后 normal status 把 UI 改回 idle。
5. callback guard 失败、timeout、Start ACK 失败或 other values 进入对应终态时，清理该状态；`0x0E` 保持该状态并进入既有 testing/轮询流程。
6. `handleStatus(.elControllerDeviceStatus)` 中：
   - 如果 `shouldIgnoreNormalDeviceStatusForFunctionTest == true` 且 status 是 `0x03` 或其他非 testing 值，不调用 `applyDeviceStatus`，直接返回 true。
   - 如果 status 是 `0x0E`，仍允许 `applyDeviceStatus`，保持 testing 行为。
7. `stopPageSession()` 中清理 `shouldIgnoreNormalDeviceStatusForFunctionTest`，避免页面退出后残留。

## 验证计划

源码检查：

- `rg` 确认新增阶段状态只存在于 `ELControllerFunctionTestHelper`。
- `rg` 确认 Start 前置异常、normal-mode 提示、Start ACK 失败和页面退出会清理阶段状态；`0x03` 成功路径保留该状态。
- `rg` 确认 `handleStatus(.elControllerDeviceStatus)` 对 Start 前置阶段有保护。

构建验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工 BLE 验收：

- EL Controller 真实设备，点击 Function Test - Start。
- Device Status 返回 `0x03` 时，从点击到 Start ACK/轮询期间始终显示 `Awaiting device response...`，不再闪 `Tap "Start"...`。
- Device Status 返回 `0x0E` 时仍保持 testing/轮询。
- Device Status 返回 other 或 timeout 时仍展示 normal-mode 提示。

## 待确认

请确认采用方案 A：在 `ELControllerFunctionTestHelper` 内增加 Start 前置校验阶段标记，屏蔽这条 Start 前置 Device Status 对通用 `applyDeviceStatus(0x03)` 的 idle 更新。
