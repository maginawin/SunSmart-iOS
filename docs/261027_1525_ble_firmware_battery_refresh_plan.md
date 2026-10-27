# BLE 固件升级页 Battery Power Switch 刷新方案

状态：已实施，相关自动化回归与六品牌 Debug generic iOS 编译通过；真实 BLE 与 UI 体验待人工验收。
日期：2026-10-27。

## 结论与已确认选择

需求合理，可在 App 端完成。推荐复用 BLE 固件页现有扫描流程，增加手动激活等待模式；保留进入页面与下拉刷新的原有规则。

用户已确认：手动等待以 30 秒为上限，本页目标设备在本轮全部重新发现后可以提前结束。不是发现任意一个设备就结束，也不能用上一轮缓存判断本轮已经找齐。

用户已确认其余交互与实施范围。30 秒只控制 App 等待发现设备的时间，不会延长设备自身的唤醒时间；原有提示中的 60 秒是现有产品文案，本轮没有设备实测来验证该窗口。

## 当前行为与影响范围

- 实际入口为 `SpaceMoreViewController` 的 BLE 操作，具有现有编辑权限检查，进入 `BleFirmwareUpdateViewController(site:space:)`。
- 页面初始化及下拉刷新都进入 `refreshRSSI()`。初始安排 10 秒结束；首次发现一个尚未绑定 peripheral 的目标设备后重新安排 10 秒；所有目标都有 RSSI 与 peripheral 时提前结束。因此“10 秒内找不到任何设备就结束”成立，但并非每次进入都固定扫描 10 秒。
- 页面传给 SDK 的等待时间是 99999，实际由页面的结束任务控制。新增手动模式时，必须同时处理页面的 10 秒任务和扫描回调中的续期，不能只增加倒计时 UI 或单独修改 SDK 参数。
- 现有刷新会清空全页 RSSI/peripheral，并重建分类、重置选择及请求云端固件信息。手动等待不能直接照搬这段初始化，否则会影响普通设备已经取得的结果和选择。
- 扫描期间，全选、设备选择与单设备升级会被现有逻辑拦截，底部升级按钮显示 STOP。手动模式继续沿用这套规则。
- 同一控制器还被 Site 网关升级入口复用，具有单独的目标列表与 Network Key 范围。新控件仅对 Space 入口、已有 Battery Power Switch 分类展示，不改变 Site 网关入口。
- 当前 Battery Power Switch 判定复用 `Node.isBatteryPowerSwitch`，对应 CID 0x0A78、PID 0x2A01/0x2A02；不按名称、图标或分支名称推断设备类型。AC Power Switch、Kinetic switch 等不增加此控件。

## 方案比较

| 方案 | 影响 | 结论 |
| --- | --- | --- |
| 现有页面扫描增加手动等待模式 | 共用目标过滤、身份验证、RSSI 更新、排序、停止与升级互斥，只区分触发方式和结束规则 | 推荐 |
| 全部扫描统一改为 30 秒 | 会改变普通设备、下拉刷新及 Site 网关入口的等待行为 | 不采用 |
| 新建独立 Battery 扫描器 | SDK 扫描资源共享，容易相互替换回调，需额外协调与升级流程的关系 | 本需求无需采用 |

## 控件与交互

参考设计：

- [REFRESH](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=689-4105)
- [Waiting / CANCEL](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=689-4217)

沿用现有分类展开规则；在 Battery 提示下方增加控件，提示文本自身的折叠/展开与扫描状态独立。两个 Figma 节点分别展示了不同的提示展开状态，不把 REFRESH/Waiting 与该展开状态绑定。

设计基准为提示下方间距 8、控件高度 32、圆角 15、白底与主题色半透明描边。适配沿用项目缩放、字体与主题机制，不把 311 的参考宽度固定到所有设备。

| 场景 | 控件及行为 |
| --- | --- |
| 首次进入页面 | 默认 REFRESH；原有自动扫描仍可发现已激活设备，无需强制点击 |
| 点击 REFRESH | 整条可点击；接管本页当前扫描，取消旧的结束任务，从新的 30 秒窗口开始 |
| Waiting | Loading、`Waiting for switch activation (30s)...`、CANCEL；每秒更新剩余秒数，仅 CANCEL 可点击控件内的操作区域 |
| 全部找到、到时或点 CANCEL | 停止本次发现会话，恢复 REFRESH；保留已取得结果，恢复原有选择/升级能力 |
| 正在升级 | 禁止开启新扫描，沿用现有操作限制与提示；不取消升级任务 |
| 多个 Battery 分类 | 整页同时只有一个扫描窗口，各 Battery 控件同步展示 Waiting 与剩余秒数；任一 CANCEL 结束同一次会话 |

Loading 直接使用现有 `PJEightKeySwitchWaitingSpinnerView`。刷新复用 `refresh` 并按设计显示英文大写，取消复用 `cancel`，倒计时复用 `neightkeyswitches_activation_waiting_format`；现有 English、简体中文均已提供这些 Key，预计无需新增资源或修改文案。

等待文案保持单行，关闭自动缩小字体，使用 UIKit `UILabel.lineBreakMode = .byTruncatingMiddle` 在空间不足时省略中间文字，保留开头提示和尾部秒数。每秒仍更新完整国际化字符串，由 UILabel 根据当前宽度截断；CANCEL 保持原有高优先级约束与点击区域。

Waiting 只限制该控件内部的点击区域；页面其他操作继续受原有扫描/升级规则管理。底部 STOP 继续可用，效果与 CANCEL 一致，不增加“已点 STOP 但仍显示 Waiting”的状态。

## 扫描与状态处理

1. 区分普通扫描与手动激活等待，状态由页面持有，Cell 只渲染与转发操作，避免滚动复用或收起分类造成倒计时重启。
2. 普通扫描保持现有 10 秒续期和全部发现提前结束的规则。手动模式不执行旧的 10 秒续期，SDK 等待参数使用 30 秒，并处理完成回调，防止 SDK 已结束但 UI 仍等待。
3. 点击手动刷新时先使旧会话及其延迟任务失效，再停止旧扫描、开启新窗口；即使初始自动扫描仍在进行，也能响应点击，不能被现有 `refreshing` 判断直接忽略。
4. 手动刷新不重建整页分类、不额外请求云端固件信息，也不清空普通设备的发现结果、选择或升级结果。Battery 目标的 RSSI/peripheral 与可选择状态按本轮重新发现刷新，避免把旧的激活结果当成仍然有效。保留分类及提示的展开状态。
5. 记录本轮已经有效发现的目标地址。目标范围沿用页面经过现有过滤后的 `nodes`；只有本轮所有目标均收到有效样本才提前结束。发现仍执行原有 Mesh 身份验证、页面目标匹配、固件版本判断和 RSSI >= -80 的升级条件，不因“发现”直接视为“可升级”。
6. UI 倒计时每秒刷新，滚动时继续更新；30 秒截止与显示使用同一会话时间依据。无需亚秒精度，不因重复广播续期。超时直接恢复 REFRESH，不新增弹窗。
7. CANCEL、STOP、全部发现、超时、蓝牙不可用、页面退出和手动等待期间进入后台，共用幂等结束入口：先使本轮失效，再取消计时/延迟任务与排序任务，停止 SDK 的本轮发现，刷新最终列表和按钮。
8. 结束与重试使用会话标识检查回调。SDK 完成回调可能由 stop 同步触发，须先失效再调用 stop；迟到回调或上一轮计时不能更新新一轮状态或重新延长等待。
9. 点 CANCEL 结束的是本次 RSSI/设备发现，不是断开 Mesh 连接，也不是调用固件升级取消。当前页面进入固件版本/帮助等其他页面时，结束新的手动等待；返回显示 REFRESH，用户可再次启动。
10. 启动前检查现有蓝牙状态；等待中可复用项目已有的 `bluetoothState` KVO 方式处理关闭/不可用，不替换全局 SDK delegate。失败后恢复 REFRESH，允许环境恢复后再次点击。

## 预计实施范围

- `BleFirmwareUpdateViewController.swift`：扫描模式、时间与回调管理、统一结束入口、页面生命周期和 Cell 状态同步。
- `BleFirmwareTypeUpdateViewCell.swift`：提示下方的两种展示、点击范围、复用清理与布局。
- 围绕上述扫描模式补必要的行为测试；若需要隔离时钟和回调测试，使用仅服务于本页面的小型状态模型，不扩展为通用扫描框架。

不需要改固件、服务器、持久化格式、正式 SDK 依赖或新增 SDK API。继续使用已存在的 `refreshNodesRSSI` / `stopRefreshNodesRSSI`。

已核对本机 `SunSmartLocal.xcworkspace` 映射到 `one-dev` SDK，当前 revision 为 `9998967`，SDK 工作树无未提交差异。这里只是当前分析基线，不表示正式 release 已同步该 revision；实施前按实际依赖状态复核，不修改共享 SDK 来完成本需求。

当前 App 分支为 `fix/SR-BL2421-MINI-261027`，HEAD 为 `cdced6a6`；分析开始时工作树干净。本任务修改上列控制器与 Cell，新增扫描状态模型、行为测试与检查脚本，并将模型加入六个 target；未提交。

执行期间另出现电池刷新弹窗控制器、Monitor 调用及提示布局的未提交改动，以及 English、简体中文 `neightkeyswitches_refresh_message` 的改动，均非本任务写入，已保留；本次复用的 Spinner 接口与倒计时 Key 未受影响。

## 验证与验收

实施清单（主代理在当前独立工作树内执行，不自动提交）：

- [x] Task 1：新增仅服务于本页的 `BleFirmwareScanSession`（`Mode.automatic/batteryActivation`、`begin(mode:targetAddresses:at:)`、`receive(address:sessionID:at:)`、`end(sessionID:)`、`remainingSeconds(at:)`），用真实生产状态模型测试 10 秒续期、30 秒截止、本轮全部发现及取消/重试隔离。
- [x] Task 2：控制器使用该状态模型接入现有 SDK，增加统一结束与生命周期清理；Cell 增加 REFRESH/Waiting、委托事件和复用清理，复用现有 Spinner 与文案。
- [x] Task 3：将状态模型加入六个共享 target，运行 `scripts/check_ble_firmware_scan.sh`、检查差异并完成受影响品牌 Debug generic iOS 编译；回填实际结果及待人工验收项。

接口衔接：Task 1 的 `sessionID` 同时保护 Task 2 的 SDK 回调、截止任务与倒计时；Task 2 根据 `remainingSeconds(at:)` 渲染所有 Battery Cell。旧会话先 `end` 再停止 SDK，防止同步完成回调重入。既有中英文提示词差异不纳入本任务。

自动化验证重点：

- 普通模式的 10 秒续期与手动模式的 30 秒上限互不覆盖。
- 初始扫描期间点击 REFRESH 能开启新窗口；旧的 10 秒任务不会截断它。
- 单个设备发现不提前结束，全部本轮目标发现可以结束；旧缓存不触发结束。
- CANCEL/STOP 后不再处理本次发现；取消后立即重试，旧回调与旧超时不影响新会话。
- 已发现结果与普通设备选择保留；无设备激活、蓝牙不可用、退出/后台后都能结束并恢复。
- 多分类、提示折叠、Cell 复用的状态与倒计时一致；升级中不能启动扫描。

优先运行相关既有固件版本策略与网关扫描过滤测试，再补本次状态行为夹具。现有 WiFi DFU 测试不能作为 BLE 等待流程验收证据。

生产代码实施后使用正确映射的本地 workspace，完成一次 SunSmart Debug generic iOS 编译，不运行 Simulator。该页、Spinner 与本地化目前在 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 target 中共享；若新增文件导致 Sources 配置变化，合入前检查全部受影响 target 的归属并按项目要求覆盖编译。

人工最短验收：

1. 进入页面后直接激活设备，确认原自动发现路径仍可使用。
2. 等初始扫描结束，再点 REFRESH；检查从 30 秒开始倒计时，10 秒后仍可发现晚激活的设备。
3. 检查找齐后提前结束、未找齐到时结束；过程中点 CANCEL/底部 STOP，随后再激活设备，不应继续更新已结束会话的列表。
4. 再次 REFRESH 可发现设备；普通灯的已有结果、选择、固件入口及升级流程正常，升级中的扫描拦截正常。
5. 检查两个 Battery 分类、提示收起/展开、滚动复用、离开重进、后台返回及蓝牙关闭恢复；中英文和窄屏下 CANCEL 均可见可点。
6. 对 Battery Switch 完成一次发现、选择、升级以及既有升级后断连/恢复流程验收。

## 实施与验证结果

- `scripts/check_ble_firmware_scan.sh` 通过：3 套既有固件版本/网关扫描策略回归与 9 项新增扫描状态行为测试。测试直接编译生产状态模型；它们不代表 UIKit 点击或真实广播已验收。
- 独立只读审查发现一处选择保护问题：手动等待保留普通设备选择后，Cell 仍先修改选择再调用旧拦截，会清掉原先选择。已将设备行与分类全选统一改为通过 `performSelectionChange` 在变更前拦截，补充“等待期间选择不变、取消后恢复选择能力”行为回归并通过；审查未发现其他可确认的 P1/P2。
- 扫描功能实施后的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 scheme 均完成 Debug generic iOS 编译，`xcodebuild` 退出码均为 0。使用 `SunSmartLocal.xcworkspace`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=NO`；未使用 Simulator、未安装或运行真机。
- 后续按用户要求，将等待长文案改为 UILabel 原生中间截断，保留尾部倒计时并关闭自动缩字。调整后 3 套既有策略回归、9 项状态行为测试和 SunSmart Debug generic iOS 编译再次通过；资源、target 配置与品牌编译路径均未变化，未重复其余品牌构建。中间省略与窄屏视觉效果仍待人工确认。
- 构建缓存隔离在 `~/Library/Developer/Xcode/DerivedData/SunSmart-fix-SR-BL2421-MINI-261027-battery-refresh`，同目录串行。构建仍有现有依赖和旧代码警告，本任务未扩大处理。
- 本地 SDK 未修改，未新增依赖、资源或本地化 Key。现有其他任务的未提交修改已保留，没有 commit、push 或合并。

待人工验收：上方最短步骤中的真实 30 秒发现、全部找到提前结束、CANCEL/STOP 后停止发现、普通设备原选择保留、多分类/窄屏/滚动复用，以及 Battery Switch 完整升级与既有恢复路径。
