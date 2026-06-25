# EL Controller RX/TX Unknown State 设计

## 背景

EL Controller 设备范围限定为 CID `0x0A78`、PID `0x24C1`。当前 App 已支持在 Space 首次连接后读取 RX/TX Cable Connection 状态，并在设备详情页手动 Check 后同步更新同一个 runtime 状态。

当前 runtime 状态只有 Normal 和 Fault，默认未读取时会按 Normal 展示。新需求要求区分“未获取过状态”和“已确认正常”，因此需要新增 Unknown 状态。

## 目标

- 为 EL Controller RX/TX Connection State 增加 Unknown 状态。
- Unknown 表示 App 尚未获取 RX/TX Cable Connection 状态，或尚未根据结果更新。
- Space - Main - Lights 列表中，Unknown 与 Normal 使用同一在线图标。
- EL Controller 设备详情页中，Unknown 展示默认提示：`Tap "Check" to test sign panel connection`。
- 已有 Normal、Fault、timeout 判 Fault 的行为保持不变。

## 状态定义

RX/TX Connection State 变为三态：

- Unknown：默认值，表示未获取或尚未更新。
- Normal：GET RX/TX Cable Connection 收到成功结果。
- Fault：GET RX/TX Cable Connection 收到失败结果、timeout、无有效 response，或 response 无法解析为对应状态。

Unknown 不等同于 Normal。二者只是在 Space 列表图标上使用相同图片。

## Space 列表展示

仅影响 EL Controller 设备，不影响其他 Lighting 设备。

- Offline：显示 `device_offline_EMSign`。
- Online + Unknown：显示 `device_EMSign`。
- Online + Normal：显示 `device_EMSign`。
- Online + Fault：显示 `device_unsync_EMSign`。

现有离线图标优先级保持不变：只要设备 Offline，就不看 RX/TX Connection State。

## 设备详情页展示

EL Controller 设备页面进入时继续读取当前 Space 中保存的 RX/TX Connection State，并映射到 RX/TX Cable 卡片。

- Unknown：展示默认提示 `Tap "Check" to test sign panel connection`。
- Normal：展示 `Connection Normal`。
- Fault：展示 `Connection Fault`。
- Checking：用户点击 Check 后的临时状态，保持现有展示。

手动 Check 成功返回后更新 shared state 并刷新当前页面。手动 Check timeout、无有效 response 或 ret 非 0 时更新为 Fault，并同步刷新 Space 列表图标。

## 自动读取流程

Space 首次连接后的自动读取流程保持现状：

- 只在当前 Space 页面生命周期内触发一次。
- 只针对在线、已 keybind、支持 EL Controller RX/TX 状态且有 Sunricher Vendor Model 的设备。
- 读取成功后更新 Normal 或 Fault。
- timeout、无有效 response 或无对应状态时更新 Fault。
- 未触发读取、或读取前进入详情页时，状态保持 Unknown。

## 非目标

- 不持久化 RX/TX Connection State 到数据库或云端。
- 不改变 Function Test 流程。
- 不改变协议 opcode、payload、timeout 配置。
- 不扩大 CID/PID 适配范围。
- 不调整其他设备的在线/离线状态逻辑。

## 验证

- 检查 Unknown 默认值是否生效。
- 检查 Space 列表中 Unknown 和 Normal 都显示 `device_EMSign`，Fault 显示 `device_unsync_EMSign`，Offline 显示 `device_offline_EMSign`。
- 检查详情页 Unknown 显示默认提示。
- 检查手动 Check 和自动读取仍能将成功结果更新为 Normal，将失败或 timeout 更新为 Fault。
- 运行 `git diff --check`。
- 运行 iPhoneOS `xcodebuild` 编译验证。
