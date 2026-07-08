# EL Controller Function Test Start 前状态校验分析与方案

## 结论

需求主体是完整的，当前代码也已经具备所需协议基础：`GET 0x00/0x01/0x03`、`RET 0x00/0x01/0x03` 在本地 `NordicSigMeshSDK` 中已有编码、解析和测试覆盖。当前缺口集中在 App 层：EL Controller 页面点击 Function Test 的 `Start` 后，现在直接发送 Start Function Test，没有先发送 Get Device Status。

推荐采用 App helper 层窄改：只调整 `ELControllerFunctionTestHelper.startFunctionTest()` 的点击流程，先读 Device Status；`status == 0x03` 时继续发送 Start Function Test；`status == 0x0E` 时保持既有 Function testing 处理，让 Function Test 处于 testing 状态并轮询结果；其他值、GET timeout 或解析失败在 Function Test 结果栏展示 `FT testing can only be performed in normal mode.`，并复用 Battery Fault 的浅红背景样式。

## 当前协议核对

- `SunricherVendorGet.opCode = 0xF1780A`，EL Controller GET 使用 parameters `45 + subcode`。
- `.elControllerRxTxCableConnection` 编码为 `45 00`。
- `.elControllerDeviceStatus` 编码为 `45 01`。
- `.elControllerFunctionTestResult` 编码为 `45 03`。
- `SunricherVendorStatus` 解析 `RET 0xF3780A` 的 parameters：`45 + subcode + ret + payload`。
- `RET 45 00 ret` 已解析为 RX/TX Cable Connection，应答无额外数据。
- `RET 45 01 ret status` 已解析为 Device Status。
- `RET 45 03 ret validity faultBits` 已解析为 Function Test Result。

当前 SDK 的 `ELControllerDeviceStatus.isFunctionTesting` 只把 `0x0E` 识别为 Function testing，`0x03` 与其他值都不是 Function testing。这个语义适合页面进入时判断是否继续轮询，但不完全等同于本次 Start 前置校验规则。

## 当前 App 行为

- `ELControllerFunctionTestHelper.startPageSession()` 页面进入时会发送 `GET 0x01 Device Status`。
- 如果页面进入读到 `0x0E`，当前会显示 Awaiting 并开始轮询 Function Test Result。
- 如果页面进入读到非 `0x0E`，当前会停止轮询并恢复 idle。
- `startFunctionTest()` 点击 Start 后当前直接发送 `SET 0x07 Start Function Test`，成功后才轮询 `GET 0x03 Function Test Result`。
- `ELControllerFunctionTestView` 现有 `.fault` 样式就是 Battery Fault 的浅红背景：`RGB(255, 59, 48, 0.10)`，可以直接复用。

## 需求不完善或需确认点

1. 协议表中写明 `GET 0x01` 的 `Other values = Normal status`，但优化要求中写明 `other values, timeout` 都要阻止 Function Test。两者存在语义冲突。

   推荐解释：页面进入时可继续沿用 SDK 的 “非 testing 即普通展示” 逻辑；点击 Start 的前置校验使用更严格规则，只允许 `0x03` 继续 Start，`0x0E` 进入既有 testing/轮询流程，其他值展示 normal mode 提示。

2. 点击 Start 后等待 `GET 0x01` 结果期间，需求没有指定中间 UI。

   推荐解释：短暂复用现有 Awaiting 状态禁用按钮，收到 `0x03` 后继续 Start，收到异常/timeout 后替换为本次新增提示。这样不新增额外中间文案，改动最小。

3. 需求只指定 Function Test 行右侧 Start 后的行为，没有要求改变页面进入时的自动 Device Status 读取。

   推荐解释：页面进入逻辑保持不变，避免影响已有“设备已经处于 Function testing 时继续轮询结果”的行为。

## 方案对比

### 方案 A：App helper 层 Start 前置校验（推荐）

修改范围：

- `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
- `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

行为：

1. `startFunctionTest()` 先停止旧轮询并进入短暂 Awaiting。
2. 发送 `SunricherVendorGet(function: .elControllerDeviceStatus)`。
3. 收到 `RET 45 01 00 03`：继续发送 `SunricherVendorSet(function: .elControllerStartFunctionTest)`，后续流程保持原样。
4. 收到 `RET 45 01 00 0E`：不发送 Start，保持既有 Function testing 处理，展示 Awaiting 并轮询 Function Test Result。
5. 收到其他 status、非成功 ret、解析失败或 timeout：不发送 Start，展示 `FT testing can only be performed in normal mode.`。
6. 结果栏使用现有 `.fault` 样式，背景与 Battery Fault 一致。

优点：

- 改动收口在 EL Controller UI helper，不影响 SDK 通用 parser。
- 不改变 RX/TX Cable、页面进入自动读取、Function Test Result 轮询、Exit Function Test。
- 与当前本地 SDK 引用状态匹配，风险最低。

缺点：

- `ELControllerDeviceStatus` 本身仍只提供 `isFunctionTesting`，Start gate 的 “只允许 0x03” 规则会在 App helper 中表达。

### 方案 B：SDK 增加明确的 Device Status 语义

在 SDK 中给 `ELControllerDeviceStatus` 增加类似 `isNormalMode`，App 使用 SDK 语义判断。

优点：

- 协议语义更集中，后续其他 App 或 SDK demo 可复用。

缺点：

- 需要修改本地 SDK、补 SDK 测试，并确认远程 SDK 同步策略。
- 本次需求只影响当前页面 Start 点击，改动面偏大。

### 方案 C：复用现有 failed 状态，不新增 UI state

Start 前置校验失败时直接展示现有 `Test Failed`。

优点：

- 最小代码改动。

缺点：

- 不满足指定文案 `FT testing can only be performed in normal mode.`。
- 用户无法区分“设备不在 normal mode”和“Start 命令失败”。

## 推荐开发计划

采用方案 A。

1. 在 `ELControllerFunctionTestView.FunctionTestState` 增加一个专用状态，例如 `normalModeRequired`。
2. 在 `functionTestDisplayState` 中把该状态映射到新增本地化 key，样式使用 `.fault`，按钮恢复 `Start` 且可再次点击。
3. 在英文和简体中文本地化中新增 key：
   - English: `FT testing can only be performed in normal mode.`
   - 简体中文：建议 `仅可在正常模式下执行功能测试。`
4. 在 `ELControllerFunctionTestHelper.startFunctionTest()` 中拆出两段流程：
   - Start 前读取 Device Status。
   - raw status 为 `0x03` 时调用原 Start SET 流程。
   - raw status 为 `0x0E` 时复用 `applyDeviceStatus` 的既有 testing 处理，进入 Awaiting 并启动 Function Test Result 轮询。
5. 对 Device Status 的其他 raw 值、非成功 ret、解析失败、timeout 统一展示 `normalModeRequired`。
6. 保持 `startPageSession()` 的现有逻辑不变：页面进入读到 `0x0E` 仍按已有行为进入 Awaiting/轮询，避免改变其他功能。
7. 保持 RX/TX Cable Check、Function Test Result 轮询和 Exit Function Test 不变。

## 验证建议

代码级验证：

- `rg` 确认 Start 点击路径中先出现 `elControllerDeviceStatus`，再出现 `elControllerStartFunctionTest`。
- `rg` 确认新增本地化 key 在 English 与简体中文均存在。
- `git diff --check`。
- iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工 BLE 验收：

- 真实 `CID 0x0A78 / PID 0x24C1` 设备，Device Status 返回 `0x03` 时，点击 Start 后继续发送 Start Function Test，并维持原轮询结果流程。
- Device Status 返回 `0x0E` 时，点击 Start 后不发送 Start Function Test，Function Test 保持 testing 状态，显示 Awaiting 并轮询结果。
- Device Status 返回其他值时，点击 Start 后不发送 Start Function Test，展示同一提示。
- Device Status timeout 时，点击 Start 后不发送 Start Function Test，展示同一提示。
- RX/TX Cable Check 行行为不变。
- 页面进入时已有的 Device Status 自动读取行为不变。

## 待用户确认

请确认采用方案 A，并确认两个解释：

1. Start 前置校验中，`status == 0x03` 继续 Start，`status == 0x0E` 保持既有 testing/轮询处理，其他值和 timeout 展示 normal mode 提示。
2. 页面进入时已有的 Device Status 自动读取保持当前逻辑，不扩展本次错误提示。
