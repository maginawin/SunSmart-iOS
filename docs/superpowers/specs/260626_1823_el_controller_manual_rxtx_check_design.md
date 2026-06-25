# EL Controller Manual RX/TX Check 设计

## 背景

当前 EL Controller 设备范围限定为 CID `0x0A78`、PID `0x24C1`。App 已为该设备维护 runtime RX/TX Connection State，状态包括 Unknown、Normal、Fault。

当前代码已经实现旧需求：进入 Space 并首次连接 Mesh 后，会自动读取一次 EL Controller 的 RX/TX Cable Connection 状态，并把结果更新到 Space 列表和 EL Controller 详情页共享的 runtime 状态中。

新需求变更为：进入 Space 并连接 Space 时不再自动读取 RX/TX Cable Connection。每次进入 Space 时 EL Controller 的 RX/TX Connection State 都应默认为 Unknown，只有用户进入 EL Controller 设备页面并手动点击 Check 后，才读取并更新 RX/TX 状态。

## 当前代码事实

`DevicesViewController` 中存在旧的自动读取链路：

- 首次 Mesh 连接成功后调用 `scheduleInitialELControllerRxTxConnectionCheckIfNeeded()`。
- 该方法延迟 100ms 后调用 `requestInitialELControllerRxTxConnectionState()`。
- 自动筛选在线、已 keybind、有 Sunricher Vendor Model 的 EL Controller。
- 自动发送 `SunricherVendorGet(function: .elControllerRxTxCableConnection)`。
- 有效 response 根据 ret 更新 Normal 或 Fault。
- timeout、无有效 response 或 response code 不匹配时更新 Fault。
- `deviceStateUpdateObserver` 还会在设备状态更新后补触发一次自动读取。

设备详情页手动 Check 链路已经存在于 `ELControllerFunctionTestHelper.checkRxTxCable()`，并且可以继续作为唯一读取 RX/TX Cable Connection 的入口。

## 目标

- 移除 Space 首次连接后的 EL Controller RX/TX Cable Connection 自动读取。
- 移除设备状态更新后补触发的 RX/TX 自动读取。
- 每次进入 Space 时，把 EL Controller RX/TX Connection State 重置为 Unknown。
- 保留 EL Controller 设备页面手动 Check 功能。
- 手动 Check 后继续更新 Space 列表和设备详情页共享状态。

## 状态语义

- Unknown：进入 Space 后的默认状态，表示当前 Space 生命周期内尚未手动读取 RX/TX Cable Connection。
- Normal：手动 Check 收到成功结果。
- Fault：手动 Check 收到失败结果、timeout、无有效 response，或 response 无法解析为 RX/TX Cable Connection 状态。

如果用户离开 Space 后再次进入 Space，即使上一次手动 Check 得到 Normal 或 Fault，也应重新变为 Unknown。

## 数据流

### 进入 Space

`DevicesViewController.viewDidLoad()` 早期重置 EL Controller RX/TX 状态：

- 遍历当前 mesh 的 real nodes。
- 只处理 `supportsELControllerRxTxConnectionState == true` 的节点。
- 将 `elControllerRxTxConnectionState` 更新为 Unknown。
- 通过现有 state update 通知刷新列表项。

### Mesh 首次连接

首次 Mesh 连接成功后继续执行现有流程：

- 隐藏连接 loading。
- 处理 address 申请。
- 获取 mesh distribution。
- 同步时间。

不再执行 RX/TX Cable Connection 自动读取。

### 手动 Check

EL Controller 设备详情页中，用户点击 RX/TX Cable 的 Check 按钮后：

- 继续由 `ELControllerFunctionTestHelper.checkRxTxCable()` 发送 GET RX/TX Cable Connection。
- 成功 response 且 ret 为 0：更新为 Normal。
- ret 非 0、timeout、无有效 response、code 不匹配：更新为 Fault。
- 更新 shared state 后继续通过现有通知刷新 Space - Main - Lights 列表 item。

## UI 映射

Space - Main - Lights：

- Online + Unknown：`device_EMSign`
- Online + Normal：`device_EMSign`
- Online + Fault：`device_unsync_EMSign`
- Offline：`device_offline_EMSign`

EL Controller 设备详情页：

- Unknown：`Tap "Check" to test sign panel connection`
- Normal：`Connection Normal`
- Fault：`Connection Fault`
- Checking：保持现有 checking UI

## 非目标

- 不改变 Function Test 流程。
- 不改变 RX/TX Cable Connection 协议、opcode、payload 或 timeout。
- 不持久化 RX/TX Connection State。
- 不扩大 EL Controller CID/PID 适配范围。
- 不调整其他设备的 Online/Offline 状态逻辑。
- 不新增用户可见文案。

## 验证

- 搜索确认 `DevicesViewController` 中不再存在 RX/TX 自动读取方法和调用。
- 搜索确认唯一发送 `.elControllerRxTxCableConnection` GET 的 App 入口是 `ELControllerFunctionTestHelper.checkRxTxCable()`。
- 进入 Space 后 EL Controller 默认状态为 Unknown。
- 手动 Check 成功后更新为 Normal。
- 手动 Check 失败、timeout 或无有效 response 后更新为 Fault。
- 运行 `git diff --check`。
- 运行 iPhoneOS `xcodebuild` 编译验证。
