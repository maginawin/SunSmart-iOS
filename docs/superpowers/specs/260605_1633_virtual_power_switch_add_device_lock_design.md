# Virtual Power Switch Add Device Lock Design

## 背景

Battery Power Switch 与 AC Power Switch 的虚拟设备来源有两类：

- 从未 link 过真实设备的预创建虚拟 switch。
- 曾经 link 过真实设备，但真实设备手动重置后被重新添加为其他 switch，旧 switch 因失去有效真实节点而回到虚拟状态。

业务原则是这两类虚拟设备在任何入口、任何列表中都应被视为同一种虚拟设备，具备相同的 Add Device、LINK、panel type 过滤和操作限制。

## 真实性分析

当前代码中，Add Device 已经具备一部分目标策略：

- `AddDeviceBindTarget.batteryPowerSwitch` 会按 `powerSwitchKind` 与 `eightKeyPanelType` 过滤真实 power switch。
- Add Device 的普通入口可以在 `Add Device(s) to` 中选择虚拟 Battery/AC Power Switch。
- Switch edit 页面点击 `LINK` 前会先保存当前编辑页数据，再把保存后的 `PJEightKeySwitchData` 作为固定 `bindTarget` 进入 Add Device。
- Classic、Professional 与 Candidate Device List 都已经会在虚拟目标下隐藏批量选择控件。

但问题真实存在：

- Classic Mode 在 Stop 后，单行 `+` 只检查当前设备状态和容量限制；第一个设备进入添加流程后，用户仍可点击第二个匹配设备的 `+`。
- Professional Mode 的 Candidate Device List 单次回调会截取一个设备，但用户可以连续点击多个设备，造成同一个虚拟目标被多次 LINK。
- Candidate Device List 作为 Professional Mode 的弹层，与外层 Professional 列表共享 controller 目标状态；修复必须覆盖弹层入口和外层入口，不能只改某一个列表。
- 旧虚拟 power switch 的归一化当前存在风险：无效 proxy link 的 normalize 逻辑只覆盖 battery，AC 旧真实节点失效后可能仍保留 `proxyNodeAddress`，从而没有回到 `displayStatus.isVirtualSwitch`。

## 目标

- Battery 与 AC 的旧无效真实节点绑定都能归一化为虚拟 power switch。
- `Add Device(s) to` 选择虚拟 Battery/AC Power Switch 后，候选真实 switch 继续按 `powerSwitchKind` 与 panel type 过滤。
- Switch edit 页面进入 `LINK` 时，Add Device 使用点击 LINK 前编辑页展示并保存后的 panel type。
- 同一个虚拟目标进入真实设备 LINK 流程后，只允许第一个真实设备继续添加；其它匹配设备不能再被点击进入 LINK。
- Classic Mode、Professional Mode 主列表、Professional Candidate Device List 都遵循同一业务流程。
- Others 中的虚拟设备也遵循同样的单目标添加锁，避免连续 LINK 多个真实设备到同一个虚拟设备。

## 非目标

- 不改变 Space 与 Group 的普通批量添加流程。
- 不重构 Add Device 页面整体架构。
- 不新增 Auth 信息。
- 不新增资源、target、依赖或协议字段。
- 不改变真实 power switch 添加到 Space 时自动创建 switch 数据的既有流程。

## 推荐方案

采用轻量 Add Device 虚拟目标锁，并补齐 Battery/AC Power Switch 归一化。

该方案保持现有 Add Device controller 结构，只在现有入口前增加统一的“虚拟目标是否已经开始添加”判断，在现有 power switch normalize 逻辑中把 AC 纳入同一规则。这样可以覆盖当前问题，同时避免重构刚改动过的 Add Device 目标策略。

备选方案一是只在按钮点击处做局部防抖。它改动最小，但 Classic、Professional、Candidate 会继续分散判断，也不能处理 AC 旧虚拟归一化。

备选方案二是重构完整 Add Target Policy。它长期更清晰，但当前需求只需要修复单目标 LINK 锁和 AC 归一化，重构范围偏大。

## 虚拟设备归一化

Power Switch 虚拟状态以 `PJEightKeySwitchData.displayStatus.isVirtualSwitch` 为准。归一化逻辑需要同时覆盖 Battery 与 AC：

- 如果 switch 有 `proxyNodeAddress`，但对应 node 不存在，清空 `proxyNodeAddress` 并保存。
- 如果 switch 是 Battery，但 proxy node 不再是 Battery Power Switch，清空 `proxyNodeAddress` 并保存。
- 如果 switch 是 AC，但 proxy node 不再是 AC Power Switch，清空 `proxyNodeAddress` 并保存。
- 如果 runtime 中仍是普通 `DeviceSwitchData`，但 repository 中有 8-key metadata，先转换为 `PJEightKeySwitchData` 再判断。
- 归一化后，旧虚拟设备与从未 link 过的虚拟设备都通过同一个 `displayStatus.isVirtualSwitch` 进入 Add Device 目标列表。

这保证 Battery/AC 两类旧数据在 Site - Space - Switches、Site - Space - Main 进入 Add Device、Switch edit LINK 入口中表现一致。

## Panel Type 来源

普通 Add Device 入口：

- 用户从 Site - Space - Main 进入 Add Device。
- 用户在 `Add Device(s) to` 中选择虚拟 Battery/AC Power Switch。
- Add Device 直接使用所选虚拟 switch 当前持久化的 `eightKeyPanelType` 过滤真实设备。

Switch edit LINK 入口：

- 用户从 Site - Space - Switches 进入虚拟 power switch 页面，再进入 switch edit 页面。
- 用户在 edit 页面选择 panel type 时，只更新编辑页 view model 和 UI，不立即写本地数据库。
- 用户点击 `LINK` 时，先用当前编辑页状态构建 `PJEightKeySwitchData` 并保存到本地数据库。
- Add Device 使用这份已保存的 `switchData` 作为 `bindTarget`，因此真实设备过滤以点击 LINK 前页面展示的 panel type 为准。

## 添加锁行为

当当前 Add Device 目标是虚拟设备时，进入单目标添加模式：

- 当前目标包括 Battery Power Switch、AC Power Switch、Emergency Controller、Dongle，以及外部 LINK 入口传入的固定 `bindTarget`。
- 第一个可添加设备进入地址检查或 fast add 流程后，目标被视为正在 LINK。
- 正在 LINK 时，其它设备行的 `+` 应禁用或点击无效。
- 即使 UI 状态未及时刷新，controller 的 start-add 前置判断也必须拒绝第二个设备。
- 如果第一个设备成功，LINK 流程继续关闭或回调，不允许用户再追加第二个设备到同一个虚拟目标。
- 如果第一个设备失败、地址申请失败、用户取消等待队列，锁释放，允许用户重试同一个或另一个匹配设备。

非虚拟目标不使用该锁：

- Space 保持既有批量添加。
- Group 保持既有批量添加和不可添加设备禁用逻辑。
- 真实设备添加到 Space 后自动创建 power switch 数据的流程不受影响。

## Classic Mode

Classic Mode 的 Stop 后设备列表是本次问题的主要触发点。

修复后：

- 选择虚拟 Battery/AC Power Switch 后继续锁定 Switches 分类。
- 列表中只允许 panel type 与 kind 匹配的真实 switch 可点击。
- 点击第一个匹配设备的 `+` 后，虚拟目标进入正在 LINK 状态。
- 其它匹配设备的 `+` 不再能触发 `checkDeviceAddressesAreSufficient`。
- 失败或取消后恢复可点击状态。
- Group 目标不进入该锁，仍使用原有批量控件规则。

## Professional Mode

Professional Mode 有两个相关入口：

- 主列表中把扫描设备加入 Candidate Device List。
- Candidate Device List 中点击单行 `+` 触发真实添加。

修复后：

- 选中虚拟目标后，主列表和 Candidate Device List 同步目标名称、分类锁定、设备禁用状态。
- Candidate Device List 中点击第一个设备 `+` 后，虚拟目标进入正在 LINK 状态。
- Candidate Device List 不能再连续点击多个设备进入 LINK。
- 外层 Professional 主列表也不能绕过锁继续加入或触发第二个设备。
- 点击外层 Scan 触发的目标重置逻辑仍保持现有语义：普通入口可重置临时虚拟目标，固定 LINK 入口不重置。

## Others 虚拟设备

Emergency Controller 与 Dongle 属于 Others 分类，但同样是虚拟设备绑定真实设备的流程。

修复后：

- 选择虚拟 Emergency Controller 后，只允许 Emergency Controller 类型真实设备。
- 选择虚拟 Dongle 后，只允许 Dongle 类型真实设备。
- 点击第一个真实设备进入添加流程后，同样禁止继续点击其它匹配设备的 `+`。
- 成功、失败、取消时的锁释放规则与 Battery/AC Power Switch 一致。

## 错误处理

锁释放场景：

- 地址不足且网络不可用，设备状态恢复为 `.none`。
- 地址申请接口失败，设备状态恢复为 `.none`。
- 用户取消等待队列，等待设备状态恢复。
- Fast add 失败，设备状态为 `.failed`，允许用户重试。

锁保持场景：

- 设备处于 `.wait`、`.addConnecting`、`.adding`。
- 已添加成功并等待 LINK 流程关闭或回调。
- 正在执行 power switch 追加配置消息。

## 测试策略

静态检查：

- 确认 Battery 与 AC 的 invalid proxy normalize 都覆盖。
- 确认 Add Device target 列表仍通过 `displayStatus.isVirtualSwitch` 收集虚拟 Battery/AC。
- 确认 Classic 单行 `+`、Professional Candidate 单行 `+`、Professional start-add delegate 都有最终锁校验。
- 确认 panel type 过滤仍使用 `powerSwitchKind` 与 `eightKeyPanelType`。

构建验证：

- 按项目规则使用 iPhoneOS `xcodebuild` 校验 `SunSmart` scheme。
- 不使用 Simulator 作为构建校验。

手动回归建议：

- 普通 Add Device 入口选择未 link 过的 Battery Power Switch，Stop 后点击第一个匹配设备，再点第二个匹配设备，第二次应无效。
- 普通 Add Device 入口选择旧绑定失效后的 Battery Power Switch，同样验证只能 LINK 一个设备。
- 普通 Add Device 入口选择旧绑定失效后的 AC Power Switch，确认它会出现在目标列表并只能 LINK 一个设备。
- Switch edit 中切换 panel type 后点 LINK，候选真实 switch 按新 panel type 过滤。
- Professional Candidate Device List 选择虚拟 power switch 后，连续点击多个候选设备时只有第一个进入添加。
- Others 中虚拟 Emergency Controller 或 Dongle 也只能启动一个真实设备添加流程。

## 自检

- 无未决占位符。
- Battery 与 AC 在归一化、目标列表、过滤、添加锁中按同一虚拟设备原则处理。
- 普通入口与 LINK 入口的 panel type 来源已区分清楚。
- 范围聚焦在 Add Device 虚拟目标与 power switch 虚拟状态归一化，不包含无关 UI 或协议重构。
