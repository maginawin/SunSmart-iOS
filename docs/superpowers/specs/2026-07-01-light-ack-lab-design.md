# Light ACK Details Lab 设计

## 背景

基于 `docs/260701_1716_space_lights_commands_report.md` 的分析，`Site > Space > Main > Lights` 中只有部分灯控命令是 ACK command。需要在 App 的 Lab 设置中增加一个试验功能，用于在指定 ACK 控制命令发送后展示命令进度弹窗。

本设计只规划功能，不改动业务代码。

## 目标

- 在 App 主页 Sites 列表左上角菜单进入 `User settings` 后，增加 `Lab` 行。
- 点击 `Lab` 进入 Lab 页面。
- Lab 页面展示一项开关：`Display light ACK details`。
- 开关使用 `UserDefaults` 持久化，默认值为 `false`。
- 开关关闭时，App 行为保持现状。
- 开关开启时，仅在 `Site > Space > Main > Lights` 列表页和单灯详情页发送指定 ACK 控制命令后展示进度弹窗。

## 非目标

- 不覆盖其他入口，例如 Group、Energy、Schedule、Device Parameter 等页面中的 ACK 命令。
- 不覆盖全部设备 tile。
- 不覆盖滑动过程中的 unack 亮度和色温命令。
- 不覆盖列表页离线点击发送的 `GenericOnOffGet`。它是 ACK 查询，但不是控灯动作，按确认结果不展示弹窗。
- 不改 SDK 公共 ACK 机制，不扩大 `MeshAPI` 现有 API 语义。
- 不自动关闭 ACK 进度弹窗，关闭动作由用户手动完成。

## 入口和页面

### User settings

当前 `SitesViewController.menuClick()` 中点击菜单的 `.user` 会 push `UserSettingsViewController`。`UserSettingsViewController` 当前只有 `Name` 一行。

新增 `Lab` 行：

- 样式复用 `Name` 行的 `CustomTableViewCell` arrow 样式。
- 标题为 `Lab`。
- 右侧 detail text 为空。
- 点击后 push 新的 `LabViewController`。

### Lab 页面

新增 `LabViewController`：

- 标题为 `Lab`。
- 使用 `UITableView` 和现有 `CustomTableViewCell`。
- 当前仅一行：
  - 标题：`Display light ACK details`
  - 样式：`.switch`
  - 右侧 `UISwitch`
- `UISwitch` 读取和写入 `UserDefaults`。
- `UserDefaults` key 为 `lab_display_light_ack_details`。
- 默认值为 `false`，没有写入值时显示 Disabled。

## ACK 弹窗范围

当 `Display light ACK details == false`：

- 所有现有发送路径不变。
- 不展示 ACK 进度弹窗。

当 `Display light ACK details == true`：

仅以下路径展示弹窗。

### Lights 列表页

文件：`SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

覆盖：

- 单个在线 light item 点击后发送 `GenericOnOffSet`
  - On：标题示例 `L1 On`
  - Off：标题示例 `L1 Off`
  - opcode：`0x8202`

不覆盖：

- 第 0 个全部设备 tile。
- 离线设备点击发送的 `GenericOnOffGet`。
- repair/key bind 入口。

### Light 详情页

文件：`SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

覆盖：

- 开关：
  - `GenericOnOffSet`
  - opcode：`0x8202`
  - 标题示例：`L1 On` / `L1 Off`
- 亮度：
  - 仅滑动结束和手动输入的 ACK 发送
  - `LightLightnessSet`
  - opcode：`0x824C`
  - 标题示例：`L1 brightness 10%`
- 色温：
  - 仅滑动结束、快捷按钮和手动输入的 ACK 发送
  - `LightCTLTemperatureSet`
  - opcode：`0x8264`
  - 标题示例：`L1 5000K`
- Identify：
  - 仅 vendor identify
  - `SunricherVendorSet(.identify)`
  - opcode：`0xF0780A`
  - 标题示例：`L1 Identify`

不覆盖：

- 非 vendor identify 当前发送 `AttentionSetUnacknowledged`，不是 ACK command。
- emergency sign controller 被 guard 阻止的开关动作。
- 滑动过程中的 `LightLightnessSetUnacknowledged` 和 `LightCTLTemperatureSetUnacknowledged`。

## 进度弹窗行为

新增一个轻量 App 侧 ACK 进度服务，命名为 `LightAckProgressTracker`。它只服务上述两个页面，不作为 SDK 通用 ACK 框架。

发送前：

- 如果 Lab 开关关闭，调用现有发送 API。
- 如果 Lab 开关开启，构造等价 ACK message，调用现有 `MeshAPI.sendMessage(... result:)` 回调发送路径，并立即展示弹窗。

弹窗内容：

- Title：设备名称 + 命令类型，例如 `L1 On`、`L1 Off`、`L1 brightness 10%`、`L1 5000K`、`L1 Identify`。
- Message 初始内容：
  - `Sent L1 On`
  - `Command 0x8202`
- Message 收到结果后追加：
  - 成功：`Result L1 On OK`
  - 失败：`Result L1 On Failed`
  - 超时：`Result L1 On Timeout`
  - 可追加 response 类型和 source，例如 `Response GenericOnOffStatus from 0x0003`
- Button：
  - `Close`
  - 用户手动关闭。

如果旧弹窗仍未关闭时又发送新的 ACK 控制命令：

- 推荐复用同一个弹窗内容，切换为最新命令并继续更新进度。
- 这样避免多个 alert 堆叠，也符合试验功能的观察用途。

## 结果判断

使用 `MeshAPI.sendMessage(message:model:timeout:result:)` 或 `MeshAPI.sendMessage(message:address:timeout:result:)` 的回调结果：

- `result` 返回目标 response 类型时，显示 OK。
- `result == nil` 时，显示 Timeout。
- 首版不区分 ACK 等待超时和其它发送/等待失败；现有 `MeshAPI.sendMessage(... result:)` 在失败时只回传 nil，因此统一按 `Timeout` 展示。

## 本地化

新增用户可见文案需要加入英文和简体中文：

- `lab`
- `display_light_ack_details`
- `light_ack_sent_format`
- `light_ack_command_format`
- `light_ack_result_ok_format`
- `light_ack_result_failed_format`
- `light_ack_result_timeout_format`
- `light_ack_response_format`
- `close`

如果已有 `close` key，可复用现有 key，不重复新增。

## 数据流

1. 用户进入 `User settings`。
2. 点击 `Lab` 进入 Lab 页面。
3. 用户开启 `Display light ACK details`。
4. `UserDefaults` 写入 `lab_display_light_ack_details = true`。
5. 用户回到 Main Lights 或 Light 详情页发送目标 ACK 控制命令。
6. 页面发送前查询 Lab 开关状态。
7. 开关启用时，ACK 追踪器展示初始弹窗并通过带回调的 ACK 发送路径发送命令。
8. 收到 ACK response 或回调超时后，追踪器更新弹窗 message。
9. 用户点击 `Close` 手动关闭。

## 错误和边界

- 如果设备没有对应 model，保持现有行为：不发送、不弹窗。
- 如果页面已释放或不在窗口上，不再强制展示新弹窗。
- 如果发送前设备状态检查拦截，例如 emergency sign 或 key bind repair，不弹窗。
- Lab 开关关闭时不能改变现有命令发送路径和 UI 更新时序。
- 对于亮度和色温滑动，只在 `ended == true` 时弹窗。

## 测试计划

- 手动检查 `User settings`：
  - `Name` 行仍可编辑名称。
  - `Lab` 行样式与 `Name` 行一致，右侧无 detail text。
  - 点击 `Lab` 可进入 Lab 页面。
- 手动检查 Lab：
  - 默认开关关闭。
  - 切换开关后退出再进入仍保持上次状态。
  - 重启 App 后仍保持上次状态。
- 手动检查 ACK 弹窗：
  - Lab 关闭时 Main Lights 和 Light 详情页行为不变。
  - Lab 开启时，在线单灯点击 On/Off 弹窗。
  - Lab 开启时，离线单灯点击 `GenericOnOffGet` 不弹窗。
  - Lab 开启时，详情页开关、亮度滑动结束、亮度手动输入、色温滑动结束、色温快捷按钮、色温手动输入、vendor Identify 弹窗。
  - 滑动过程中的 unack 命令不弹窗。
  - 全部设备 tile 不弹窗。
- 静态验证：
  - `git diff --check`
  - iPhoneOS `xcodebuild`。

## 实施边界

本功能应拆成一次实现计划完成，改动集中在：

- `UserSettingsViewController`
- 新增 `LabViewController`
- 新增 Lab 设置持久化小工具或命名空间
- 新增 Light ACK 进度追踪器
- `DeviceLightsViewController` 的单灯在线点击 ACK 发送点
- `DeviceLightViewController` 的 ACK 发送点
- `Localizable.strings` 英文和简体中文

不修改无关设备控制页面，不做 SDK 层大范围重构。
