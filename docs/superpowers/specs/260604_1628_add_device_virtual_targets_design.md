# Add Device Virtual Targets Design

## 背景

Add Device 页面当前已经支持添加到 Space、Group，以及部分从外部入口传入的固定绑定目标，例如虚拟 Battery Power Switch LINK、Emergency Controller LINK、Dongle 绑定。新需求要求在 Add Device 页面自身的 `Add Device(s) to` 下拉列表中展示未绑定虚拟设备，并在 Classic Mode 与 Professional Mode 中统一限制可添加的真实设备。

本设计聚焦 Add Device 页面，不改变虚拟设备创建页、详情页、设备配置同步协议，也不改变 Battery/AC Power Switch 的 LINK 页面入口行为。

## 目标

- 在 Classic Mode 的 `Add Device(s) to` 下拉列表中展示 Space、Group，以及未绑定虚拟 Battery Power Switch、AC Power Switch、Emergency Controller、Dongle。
- 在 Professional Mode 的 Candidate Device List 中复用同样的 `Add Device(s) to` 选择逻辑。
- 选择虚拟设备后，仅允许匹配 company id、product id、设备类型的真实设备直接添加。
- Battery/AC Power Switch 还必须校验真实设备 product id 对应的默认 panel 类型与虚拟 switch 的 panel 类型一致。
- 不匹配设备继续展示，但禁用选择和 Add。
- 只要当前 `Add Device(s) to` 目标是虚拟设备，就隐藏底部 `Select all / Add selected` 相关批量控件，并隐藏设备行左侧选择按钮；Classic Mode 与 Professional Mode 都遵循该规则。
- 当前 `Add Device(s) to` 目标是 Group 时，即使 Switches/Others 因 group 规则不可选，也保留底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮；在对应列表内禁用不可添加设备，select all 不应选中这些 disabled 设备。
- 普通入口与 LINK 入口的差异仅在目标选择：Site - Space - Main 右上角按钮进入的 Add Device 页面允许切换 `Add Device(s) to`，LINK 入口不允许切换。
- 从 Space 或 Group 切换到虚拟设备时，清空已有选中设备。
- Battery/AC Power Switch LINK 页面保持现状，不允许切换 `Add Device(s) to`。

## 非目标

- 不新增 Auth 信息。
- 不新增资源图片。
- 不改设备协议或 Mesh SDK。
- 不重构 Add Device 页面整体结构。
- 不改变 Space 与 Group 的既有添加语义，只在现有 Group 禁用 Switches/Others 规则基础上接入统一策略。

## 推荐方案

采用统一 Add Target Policy。

新增一个轻量目标策略层，将当前目标归一为：

- Space。
- Group。
- 虚拟 Power Switch，承载 `PJEightKeySwitchData`，并区分 Battery 与 AC。
- 虚拟 Emergency Controller。
- 虚拟 Dongle。
- 外部固定绑定目标，例如现有 LINK 入口。

Classic、Professional 主列表、Professional Candidate 弹层都调用同一套策略判断：

- 当前目标名称。
- 下拉列表展示内容。
- 选中目标后应自动切换到的分类。
- 当前分类是否允许切换。
- 某个扫描设备是否可添加。
- 底部批量控件和设备行左侧选择按钮是否展示。

LINK 入口继续由 `addBehavior.allowsTargetSelection == false` 兜底，不展示或不允许切换 Add Device(s) to。由于 LINK 入口目标固定为虚拟设备，也进入虚拟目标 UI 规则：隐藏底部 `Select all / Add selected` 相关批量控件和行左侧选择按钮。

## 下拉列表行为

`DeviceAddTargetSelectView` 扩展为分组列表：

- `Space` 始终显示。
- `Group` 仅在存在 group 时显示分类，展开后列出所有 group。
- `Battery Power Switch` 仅在存在未绑定虚拟 battery power switch 时显示。
- `AC Power Switch` 仅在存在未绑定虚拟 ac power switch 时显示。
- `Emergency Controller` 仅在存在未绑定虚拟 emergency controller 时显示。
- `Dongle` 仅在存在未绑定虚拟 dongle 时显示。

各分类默认展开，并保留现有折叠/展开交互。

未绑定定义：

- Power Switch：`MeshNetworkManager.instance.switchs` 中 `PJEightKeySwitchData` 且 `proxyNodeAddress == nil`。
- Emergency Controller：`DeviceEmerFireStore.shared.devices(in:)` 中 `bindNodeAddress == nil`。
- Dongle：`MeshNetworkManager.instance.dongles` 中 `bindNodeAddress == nil`。

## 目标选择行为

选择 `Space`：

- 恢复默认添加到 space。
- 允许切换任意分类。
- 从虚拟目标切回 Space 后，不恢复旧选中态。

选择 `Group`：

- 恢复 group 添加规则。
- 允许切换任意分类。
- Switches、Dongle、Gateway、Emergency Controller、Unknown 继续展示但禁用。
- 保留底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮。
- Select all 仅作用于当前列表内可添加设备；当当前分类内设备都因 group 规则 disabled 时，select all 保持未选中或 disabled，不产生批量选择。

选择虚拟 Battery 或 AC Power Switch：

- 自动切换到 `Switches` 分类。
- 禁止切换到 `Lights`、`Sensors`、`Others`。
- 用户尝试切换其他分类时提示 `You can't choose other devices.`

选择虚拟 Emergency Controller 或 Dongle：

- 自动切换到 `Others` 分类。
- 禁止切换到 `Lights`、`Switches`、`Sensors`。
- 用户尝试切换其他分类时提示 `You can't choose other devices.`

从 Space 或 Group 切换到任意虚拟设备：

- 清空 Classic 中 `scanDevices` 与 `showDevices` 的选中态。
- 清空 Professional 中 `scanDevices`、`inRSSIDevices`、`remainingRSSIDevices`、`candidateDevices` 的选中态。
- Candidate 弹层打开时同步刷新目标名称、分类、disabled 状态和底部控件。

## 设备匹配规则

虚拟 Battery Power Switch：

- 真实设备必须是 Switches 分类。
- company id 必须匹配 `PJEightKeyPowerSwitchKind.companyIdentifier`。
- product id 必须属于 battery power switch product ids。
- 真实设备 product id 推导出的 panel 类型必须等于虚拟 switch 的 `eightKeyPanelType`。

虚拟 AC Power Switch：

- 真实设备必须是 Switches 分类。
- company id 必须匹配 `PJEightKeyPowerSwitchKind.companyIdentifier`。
- product id 必须属于 AC power switch product ids。
- 真实设备 product id 推导出的 panel 类型必须等于虚拟 switch 的 `eightKeyPanelType`。

虚拟 Emergency Controller：

- 真实设备必须是 Emergency Controller。
- company id 与 product id 必须满足现有 emergency controller 识别逻辑。

虚拟 Dongle：

- 真实设备必须是 Dongle。
- company id 与 product id 必须满足现有 dongle 识别逻辑或设备配置中 Dongle 分类识别逻辑。

不匹配设备：

- 继续展示在当前分类中。
- `selectedState` 设置为 disabled。
- 左侧选择按钮隐藏。
- 单行 Add 按钮禁用。
- Add 入口再做最终过滤，避免 stale state 绕过 UI。

## 添加成功后的绑定

Power Switch：

- 复用 `BatteryPowerSwitchAddConfiguration.prepareLinkedSwitchData` 完成真实 node 与虚拟 switch 绑定。
- 在该 helper 或邻近策略中补齐 panel/product id 校验。
- 成功后继续执行现有 power switch 配置消息、初始电量读取、刷新通知。

Emergency Controller：

- 复用 `DeviceEmerFireStore.shared.bind(_, to:, in:)`。
- 成功后发送现有 emergency controller 数据刷新通知。

Dongle：

- 复用现有 `bindToDongle` 逻辑。
- 选择未绑定虚拟 dongle 时，将真实 dongle node 绑定到该 `DeviceDongleData`。
- 成功后发送 Others 列表刷新通知。

Space：

- 保持现有默认行为。

Group：

- 保持现有 group 添加行为与 group deferred sync 逻辑。

## UI 控件规则

入口分两类：

- 普通 Add Device 入口：从 Site - Space - Main 右上角按钮进入。用户可在 `Add Device(s) to` 中切换 Space、Group、未绑定虚拟设备。
- LINK 入口：从 Battery Power Switch、AC Power Switch、Emergency Controller 等设备的 LINK 功能进入。目标固定，不允许切换 `Add Device(s) to`。

当前目标分两类：

- Space 或 Group：保持现有批量控件和行选择按钮规则。
- Group 目标下 Switches/Others 被禁用是设备级禁用，不触发虚拟目标 UI；因此保留批量控件，只让 disabled 设备和 select all 行为不可用。
- 虚拟设备：隐藏底部 `Select all / Add selected` 相关批量控件，并隐藏设备行左侧选择按钮。普通入口选中虚拟设备后也按此规则处理；与 LINK 入口唯一差异是普通入口仍可切换 `Add Device(s) to`。

Classic Mode：

- 虚拟目标下隐藏底部 `Select all / Add selected` 相关批量控件，并隐藏设备行左侧选择按钮。
- 虚拟目标下以单行 Add 作为唯一添加入口。
- Group 目标下不隐藏批量控件；Switches/Others 分类内设备 disabled，select all 不选中 disabled 设备。
- 分类切换拦截接入现有 `WMMenuViewDelegate`。

Professional Mode 主列表：

- 虚拟目标下分类锁定。
- 虚拟目标下隐藏 Select all cell 或其中的选择按钮，并隐藏设备行左侧选择按钮；若存在底部 `Add selected`，也按批量相关控件隐藏。
- Group 目标下不隐藏 Select all cell 或行左侧选择按钮；Switches/Others 内 disabled 设备不可选，select all 不选中 disabled 设备。
- Candidate 加入入口过滤不可添加设备。

Professional Candidate Device List：

- `Add Device(s) to` 下拉与 Classic 使用同一列表。
- 虚拟目标下隐藏底部 `Select all / Add selected` 相关批量控件，并隐藏设备行左侧选择按钮。
- Group 目标下不隐藏底部批量控件或行左侧选择按钮；只禁用不可添加设备，并让 select all 对 disabled 设备无效。
- 分类切换拦截补齐 `shouldSelesctedIndex`。
- 单行 Add 前检查 disabled 与策略匹配。
- `startAdd` delegate 回调前过滤不可添加设备。

LINK 页面：

- Battery/AC Power Switch LINK 入口保持 `Add Device(s) to` 不可切换。
- Emergency Controller 等 LINK 入口同样保持目标不可切换。
- LINK 入口因目标固定为虚拟设备，隐藏底部 `Select all / Add selected` 相关批量控件，并隐藏设备行左侧选择按钮；Professional Mode 也按此规则处理。
- 仍然只允许当前虚拟 switch 作为固定目标。
- 补齐 panel/product id 校验，避免 LINK 入口绕过新规则。

## 涉及文件

- `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
  - 扩展或替换当前 target enum，承载统一目标状态。

- `SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift`
  - 扩展下拉分组和 selection case。

- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 接入统一 target policy。
  - 处理自动切换分类、分类锁定、disabled 状态、虚拟目标批量控件隐藏、虚拟目标行选择按钮隐藏、单行添加过滤。

- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 主列表和 Candidate 弹层都接入统一策略。
  - 保证 scan list、RSSI list、candidate list 状态一致。
  - 区分普通入口与 LINK 入口的目标切换规则；虚拟目标 UI 展示规则保持一致。

- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 支持分类锁定、虚拟目标批量控件隐藏、虚拟目标行选择按钮隐藏、目标名称 override、disabled 添加防线。

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 补齐 kind 与 panel/product id 匹配校验。

- 可能涉及 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 如果现有 dongle company/product id 识别缺少统一 helper，则在这里补一个小 helper。

## 测试计划

静态检查：

- Classic、Professional、Candidate 三处 Add Target 选择入口都接入统一下拉。
- Classic、Professional、Candidate 三处分类切换都接入虚拟目标锁定。
- Add Selected、candidate startAdd、单行 Add 都有最终过滤。
- LINK 入口仍然不可切换 Add Device(s) to。
- 普通入口选择虚拟设备和 LINK 入口都隐藏底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮，Classic 与 Professional 均覆盖。
- Group 目标下 Switches/Others 不可添加时仍保留批量控件和行左侧选择按钮，select all 不选中 disabled 设备。

手动用例：

- 无未绑定虚拟设备时，下拉只显示 Space 和已有 Group。
- 有未绑定 Battery/AC/Emergency/Dongle 时，显示对应分类。
- 选虚拟 Battery Power Switch 后自动进入 Switches，其他分类不可切换并提示 `You can't choose other devices.`
- 选虚拟 AC Power Switch 后自动进入 Switches，panel 不匹配的真实 switch disabled。
- 选虚拟 Emergency Controller 后自动进入 Others，仅匹配 EFC 可 Add。
- 选虚拟 Dongle 后自动进入 Others，仅匹配 Dongle 可 Add。
- 普通 Add Device 入口选择虚拟目标时，隐藏底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮。
- Battery/AC Power Switch、Emergency Controller 等 LINK 入口同样隐藏底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮。
- 选择 Group 后切到 Switches 或 Others，批量控件仍展示；设备为 disabled，select all 不选择这些设备，Add selected 不提交这些设备。
- 从 Space 切到虚拟设备时，之前选中的设备清空。
- 从虚拟设备切回 Space 或 Group 后允许切换分类。
- Professional Candidate Device List 与 Classic 表现一致。
- Battery/AC Power Switch LINK 页面仍保持固定目标。

构建验证：

- 按项目规则运行 iPhoneOS 构建：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与处理

- Classic、Professional、Candidate 三套 UI 状态容易出现不一致。
  - 处理：下沉统一 policy，并在三个入口都保留最终过滤。

- Power Switch 现有 LINK 逻辑只校验 kind，可能接受 panel 不匹配设备。
  - 处理：在绑定 helper 层补 panel/product id 校验，使新入口和 LINK 入口一致。

- Dongle 若没有现成 company/product id helper，单靠 `deviceType == .dongle` 可能不够严格。
  - 处理：优先复用设备配置解析出的 Dongle 分类；如需严格 helper，只新增小范围判断，不改设备配置结构。

- 普通入口和 LINK 入口的目标切换规则不同，但虚拟目标 UI 规则相同，容易把差异放错层级。
  - 处理：目标策略同时暴露入口类型和当前目标类型；入口类型只控制是否允许切换 `Add Device(s) to`，目标类型控制批量控件和行选择按钮展示。

## 验收标准

- 用户可在 Add Device 页面下拉选择所有未绑定虚拟设备。
- 选中虚拟设备后自动进入对应分类，并锁定分类。
- 不匹配设备继续展示但不可添加。
- 普通 Add Device 入口选择虚拟目标时，隐藏底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮。
- LINK 入口同样隐藏底部 `Select all / Add selected` 相关批量控件和设备行左侧选择按钮，Classic 与 Professional 表现一致。
- Group 目标下禁用 Switches/Others 设备时不隐藏批量控件和行左侧选择按钮，select all 不会选中 disabled 设备。
- 普通入口与 LINK 入口的唯一行为差异是：普通入口允许切换 `Add Device(s) to`，LINK 入口不允许切换。
- 匹配真实设备直接添加后，与所选虚拟设备建立绑定。
- LINK 页面目标不可切换的现状不变。
- iPhoneOS 构建通过。
