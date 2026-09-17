# 网关详情页重复进入连接超时：分析与 App 修复记录

日期：2026-09-17。状态：用户已确认仅 App 端方案，代码与自动化验证完成；真机快速重进验收待用户完成。SDK 未修改。

## 结论

本次失败发生在第二次进入 Wi-Fi 网关详情页后的 BLE 建连阶段：SDK 等待 10 秒仍未收到连接成功回调，主动取消连接并标记 `GattBearerError.connectionTimeout`。首次 GATT、Proxy 白名单和后续 Mesh 消息均成功，不能把这次失败归因于 Wi-Fi 密码、MQTT 授权或白名单配置。

最值得优先修复的是连接退出与重进的生命周期缺口：SDK 在异步取消连接后立即移除旧 bearer，App 又把全局连接关闭放在页面 `deinit` 中。代码缺口已确认，但现有日志不足以证明旧物理连接残留就是这一次超时的唯一根因。

本次已仅修改 App：显式结束页面连接会话、短暂保留可取得的旧 bearer、对刚关闭的目标设置短冷却、隔离旧页面及旧尝试回调，并补最多两次自动重试。SDK 源码、版本及正式依赖不变；布局问题保留为独立发现，不纳入这次连接修复。

App 现有接口不能可靠观察底层断开完成，也拿不到连接失败的详细错误。短冷却属于减少重连竞争的补偿措施，不能宣称等价于等待物理断开；本轮重点是消除 App 可控的生命周期风险，并让失败能够有界恢复。

## 分析基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-gateway`。
- 分支：`fix-gateway`；HEAD：`c926f113f2d4a5e9f0d308d5b5aea1c56b7bf358`。分析开始时工作树干净。
- 入口：Site 页网关操作按钮 → `SiteViewController.gatewayOperationClickAction` → 模态导航栈 → `WiFiGatewayViewController`，连接逻辑继承自 `GatewayViewController`。
- 本机 workspace：`SunSmartLocal.xcworkspace`，`.local-sdk/nordic-sig-mesh-sdk` 正确指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK：`one-dev`，HEAD `eba71f13dffb50ecad7bc4a854a4086982d50dd1`，分析时无未提交改动；正式 workspace 的 Package.resolved 也固定在同一 revision，正式 project 仍使用远端 `release` 分支。
- 尚无用户运行包的版本/提交标识，不能断言该运行包与当前工作树完全一致。
- 本文不保存原始日志中的凭据、完整密钥或可还原凭据的报文。

## 日志定位

| 阶段 | 证据 | 能支持的结论 |
| --- | --- | --- |
| 首次 BLE/GATT | Connected、服务及特征发现、通知开启、GATT Bearer ready | 首次 BLE 与 GATT 初始化成功 |
| Mesh Proxy | 白名单数量先为 0，再为 3，应用报告配置成功 | 首次 Proxy 已可通信 |
| 业务通信 | TimeStatus、TTL、凭据读取完整分段响应 | 首次 Mesh 收发及解密有效；分段 ACK 本身不是失败证据 |
| Wi-Fi | `43 0E 01` 被解析为 connected；RSSI 为 -30 dBm，networkStatus 为 normal | 网关报告 Wi-Fi 已连接；这个 RSSI 是 Wi-Fi 信号，不是手机到网关的 BLE RSSI |
| 云端 | gatewayRegister 业务码 200；siteInfo 记录 gatewayOnline=true | 云端注册成功，并报告网关在线；不代表手机 BLE 可连接 |
| 退出 | `Cancelling connection...`，其后没有旧连接的 `Disconnected...` | 发出了取消请求，缺少实际关闭完成证据 |
| 第二次进入 | poweredOn → Connecting → 10 秒超时 → SDK connectionTimeout | 失败尚未进入服务发现、通知订阅和白名单阶段 |

`Connection timed out after 10.0s` 来自 `BaseGattProxyBearer.startConnectionTimeoutTimer()`：仅在 peripheral 仍为 `.connecting` 时触发，先设置 SDK 的 pendingDisconnectionError，再调用取消连接。后面的 Disconnected/error 是取消的结果及 SDK 错误标记，不能解释成“第二次已经连上又被网关主动断开”。

当前有三个不同期限：底层 BLE 建连 10 秒；SDK 指定节点连接 15 秒；App 在 GATT 成功之后才启动的 Proxy Ready 等待 20 秒。本次触发的是第一层。

补充日志（用户明确复现：连接成功 → 退出 → 立刻重进）：Site 导入总计约 151.66 ms，两个 Space 因远端时间戳不更新而跳过覆盖。导入完成后才出现第二次页面进入和 BLE Connecting。该日志再次印证建连阶段失败；没有证据表明导入工作持续阻塞了随后的 10 秒。

## 代码风险与证据强度

### 1. 异步断开后立即移除 bearer：优先嫌疑

调用链：

`GatewayViewController.deinit` → `MeshLibManager.close()` → `NetworkConnection.close()` → `BaseGattProxyBearer.close()`。

`NetworkConnection.close()` 当前依次执行停止扫描、逐个 bearer.close、proxies.removeAll、isStarted=false、向上层同步报告 didClose。底层 close 只向 CoreBluetooth 发出 cancel 请求，没有关闭完成屏障。

每个 `BaseGattProxyBearer` 自己持有一个 CBCentralManager。移除 proxies 会撤掉 NetworkConnection 对旧 bearer 的持有；代码没有专门保留待关闭 bearer/owner 的机制。重进又可新建 bearer 和 central，并启动新连接。由此存在旧回调丢失、关闭未确认就重连的窗口。

Apple 明确说明 cancelPeripheralConnection 是非阻塞方法，取消本地连接也不保证物理链路立即断开，完成通过 delegate 通知。因此“已请求取消”与“已收到本地关闭终态”应分别处理。[Apple 文档](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection%28_%3A%29)

缺少旧 Disconnected 日志与上述代码一致，但也可能来自对象释放或日志缺失；不能仅凭它断言网关一直占着连接。设备重新开放可连接广播的时机、固件 BLE/Wi-Fi 并发和外部连接占用仍是待验证项。

### 2. 页面释放时无条件关闭全局连接：已确认的交叉会话风险

页面正常退出时没有显式完成连接会话，清理依赖 deinit。控制器存在跨异步响应持有的路径，例如 `sendWiFiGatewayGet` 的响应闭包使用 self；页面从界面消失并不保证立即释放。

旧页面若在新页面开始连接后才释放，会无条件调用全局 close，也会无条件恢复全局 messageDelegate，可能关闭或覆盖新页面的状态。已有 attemptID 能过滤部分 App 回调，但不能阻止这种全局副作用。

这是可由代码确认的风险，本条日志中旧取消出现在第二次进入之前，尚没有证据说明这一次发生了“旧 deinit 关闭新连接”。

另外，当前异步排队的 ensureTargetGatewayProxyConnection 在执行时只检查删除状态，没有重新核对页面是否仍有效，退出期间也有迟到重连的窗口。

### 3. 连接失败和主动取消收尾不完整：已确认

- `NetworkConnection.close()` 没有结束 connectNode、connectNodeCallback、connectNodeTimer，也没有同步复位 isOpen。连接中退出与已就绪退出没有统一完成语义。
- 底层 didClose 只从 proxies 删除 bearer 并调用 proxieCloseHandle，没有立即向当前指定节点连接回调返回失败及底层原因。
- 指定连接扫描到目标后停止扫描；重进路径不调用自动模式 open，isStarted 可能为 false。失败后的自动重扫不能依赖 proxieCloseHandle 的自动模式分支。
- 外层通常只能等 15 秒 timer 返回 false。App 对 connectCompleted(false) 没有重试；connecting 状态下 meshDisconnected 被 reducer 忽略。
- GATT 成功后，App 的 20 秒 Ready timeout 目前只改变展示状态，没有完成底层尝试的清理。

这些问题不能单独解释第一次底层建连为什么超时，但会放大一次偶发失败，使页面长时间停留在等待或离线，缺少明确恢复路径。

### 4. 其他日志的判断

- `isSuccessful=false / errorCode=1 / connected`：SDK 通用字段按第三字节非零视为失败，Wi-Fi 专用解析则把 0x01 解释为 connected。现有 `WiFiGatewayVendorMessageTests.testConnectionStatusResponseParsing` 明确保留这个兼容行为；App 使用 typed connectionStatus，不按通用 isSuccessful 判 Wi-Fi 状态。本次不改全局解析语义。
- 布局冲突确定存在：cell 的强制垂直链合计 `16+32+4+24+12+32+10+32+16=178`，控制器固定行高为 `SCRYFrom(180)`。日志对应约 186.768 pt 与 188.867 pt，相差约 2.099 pt；全部相等约束无法同时满足，UIKit 打破按钮高度约束。这是高度不一致，不是空间不足。报警后仍成功收到了 RSSI，未发现它导致 BLE 超时的证据。
- `XPC connection invalid` 没有 subsystem、连接实例或系统错误详情，暂不能确定来自哪个系统服务，不作为独立根因。
- siteInfo 导入日志显示约 11 ms 完成，且在第二次进入之前完成；当前更新代码可复用同一主网对象，没有该段导入造成 10 秒连接阻塞的证据。
- 本段只见注册成功及状态读取，没有能证明网关被下发重启、清除 Wi-Fi 或修改 MQTT 配置的证据。

## 已确认开发方案：仅 App

### A. 页面显式退出与旧回调隔离

主要文件为 `GatewayViewController.swift`、`GatewayDetailProxyConnectionState.swift`，必要时增加一个仅服务网关详情页的小型连接会话辅助类，并衔接 Site 的模态关闭回调。

1. 在返回按钮关闭、实际 pop 或模态关闭完成时，幂等结束页面会话；进入子页面或交互式关闭被取消不结束会话。退出时立即取消该页面的重试和 Ready 等待，后续业务回调不再触发连接/刷新。
2. 移除 deinit 中无条件操作全局连接和 messageDelegate 的行为。使用 App 页面 owner token、网络上下文及目标匹配保护清理；只有当前拥有者可以操作其连接，旧页面晚释放不能影响新页面。
3. 使用 SDK 现有公开接口：当前拥有者先调用 `disconnectProxy(node:)` 取消指定节点连接的 timer/callback，再调用 `close()` 停止扫描和清理连接列表。不能只调用 disconnectProxy，因为尚未 Ready 的 bearer 可能没有 nodeAddress，无法按地址移除。
4. 清理前先将本页面标为 finishing，屏蔽 SDK 同步离线回调触发的自动重连；恢复消息代理前检查代理仍是当前页面。

### B. 快速重进的短冷却

1. 退出时记录目标的关闭请求时间（单调时钟）及网络身份。再次进入同一目标时，若距离关闭不足 1 秒，等待剩余时间再调用 connectProxy；已超过则直接连接。首次正常进入不额外延迟。
2. 对退出时能从 `currentProxy` 取得的已就绪 bearer，App 短暂持有 2 秒后释放，以减少 SDK 清空数组后旧 bearer/central 立即失去持有的风险。这个延迟只释放对象引用，不在延迟回调中再次关闭连接，不持有旧页面，也不抢占 SDK delegate。
3. 上述 1 秒和 2 秒为初始补偿参数，不是固件协议值或断开完成保证；运行日志若显示无效，应依据证据调整策略，不能持续加长等待掩盖问题。
4. 冷却任务属于新页面会话；退出、换目标、网络上下文改变或蓝牙不可用时取消。不会让离开页面后排队的任务重新启动 BLE 连接。

### C. 有界自动重试

1. 每轮连接最多 3 次尝试：首次 + 2 次重试，失败收尾后间隔 1 秒再次调用 `connectProxy(node:)`，复用 SDK 的目标扫描匹配。
2. 触发来源是现有 Bool 回调失败、App 侧连接回调兜底超时、Proxy Ready 超时。不能声称只对 connectionTimeout 重试，因为公开 Bool 回调不暴露错误类型；必须先检查蓝牙开启、页面有效、节点支持连接且网络/目标仍匹配。
3. 单次连接回调设置 18 秒 App 兜底，覆盖 SDK 15 秒 timer 未回调等情况；Ready 阶段沿用 20 秒等待。单轮恢复总预算为 50 秒，达到次数或时间上限即停止，避免多层 timeout 叠加造成过长等待；预算使用单调时钟，不改变 SDK timeout。
4. 重试前按 A 清理当前尝试，使 SDK 不因 proxies 中残留同一设备而跳过真正重连。先使旧 attemptID 失效，再调用清理接口，避免取消事件消耗重试或造成并发重试。
5. 等待重试期间保持明确的连接中状态；达到上限后显示既有连接失败提示并恢复离线 UI。若当前已有手动重连入口则复用，不为本次额外增加页面结构。
6. 成功必须以匹配当前目标的 Proxy Ready 为准；GATT 成功仅进入 Ready 等待。过滤旧 attempt、旧页面和失效网络的事件，不修改现有 Wi-Fi 状态/凭据业务。

### D. App 侧诊断与范围

仅增加 DEBUG 日志：页面/attempt/session、匿名化目标、单调时钟、冷却剩余时间、第几次尝试、Bool 结果、Ready 超时、清理请求、旧回调忽略原因、恢复预算耗尽。

通过 App 日志与已有 SDK 日志对照，不解析 SDK 日志来驱动业务，不声称能从 Bool 取得系统错误或从全局离线事件确认物理断开。新增日志不输出 Wi-Fi/MQTT 凭据或 Mesh 密钥。

本次不修改 SDK、依赖锁文件、协议解析、网络导入逻辑或布局。行高冲突作为已知独立问题保留。

## 验证与发布边界

实施后优先补 App 行为测试，使用可控时间及连接接口替身覆盖：正常首次连接无延迟；Ready 后退出立即重进只等待剩余冷却；连接中退出；旧页面迟到释放；旧失败回调不污染新尝试；首次失败后重试成功；连续失败达到 3 次或 50 秒停止；连接回调缺失；Ready 超时；冷却/重试期间退出、蓝牙关闭、切换网络；子页面返回及取消 dismiss。验证实际 App 会话代码对公开接口的调用次数和次序，不以源码匹配替代行为测试。

复用 `Tests/Device/GatewayDetailProxyConnectionStateTests.swift`、`scripts/check_gateway_detail_proxy_ready_state.sh`，保留已有 Wi-Fi 状态及自动加载相关回归。

使用 `SunSmartLocal.xcworkspace`，对 SunSmart 做一次 Debug generic iOS、关闭签名构建，使用该工作树稳定的 DerivedData；不使用 Simulator。本次不新增 SDK API、修改依赖或增加 SDK 发布待办。若新增 App 源文件，核对五品牌 Sources 归属；是否扩展品牌构建取决于实际 project 配置变动风险。

运行验收默认由用户完成：同一网关连续进入、退出、立即重进至少 10 次，再覆盖连接中退出、等待重试时退出及子页面返回。预期仅有一个有效尝试；首次失败后可看到重试日志并恢复；持续失败在次数/时间预算内结束；离开页面不再尝试连接。记录 App 关闭请求与后续 SDK 日志，不把 App 离线通知记成物理断开完成。

若 App 修复后仍出现 BLE 超时，依据新增日志区分首次偶发失败后恢复、持续失败及退出后错误重试，再决定是否需要固件侧补充连接/广播证据。本次不因此修改 SDK。没有运行证据前不宣布已解决设备侧重连问题。

## 实施与验证结果

用户已回复“按此范围实施”。以下改动位于 `fix-gateway`，基于前述 HEAD，尚未提交：

- 在现有 `GatewayDetailProxyConnectionState.swift` 中增加网关详情专用的连接会话与页面所有权管理，沿用原有 Proxy Ready reducer；注入连接接口、时钟和调度器，使行为测试直接执行生产会话逻辑。
- `GatewayViewController` 接入会话，明确处理退出、交互式关闭取消、子页面返回、蓝牙变化、删除流程及迟到回调；SDK 仍通过既有公开接口调用。
- Site 模态关闭回调负责结束整个网关导航栈的根页面会话，覆盖子页面仍在显示时关闭导航栈。
- 同目标关闭后至少间隔 1 秒才再次建连；首次进入不等待。退出时可取得的旧 bearer 保留 2 秒后仅释放引用，延迟任务不会再调用关闭接口。
- 每轮首次加两次重试，共最多三次；回调兜底 18 秒、Ready 等待 20 秒、总预算 50 秒。后台/子页面不启动新重试；退出终止整个会话。
- 复用现有 `wifi_firmware_connection_failed` 国际化文案，未添加资源、工程配置或依赖变更。公共代码归属保持五品牌一致，本次选择 SunSmart 代表构建。

自动化结果：

| 项目 | 结果与范围 |
| --- | --- |
| `check_gateway_detail_proxy_ready_state.sh` | 通过原有 12 个 reducer 用例，以及新增 15 组生命周期场景；覆盖时序、重试、退出、上下文更换、删除期间保留连接和旧 bearer 的有限持有 |
| `check_wifi_gateway_network_connectivity.sh` | 通过 Wi-Fi 协议静态检查、V1.9 timing 与 connection polling reducer 测试 |
| `check_wifi_gateway_proxy_ready_no_time_set.sh` | 通过，保持 Proxy Ready 不自动下发 TimeSet |
| `check_wifi_gateway_repair_recovery.sh` | 通过 Repair 初始化约束检查 |
| `check_gateway_deletion.sh` | 通过删除协调器、上下文、Force Clear 及集成检查 |
| SunSmart Debug generic iOS | 2026-09-17 10:11 构建成功；`SunSmartLocal.xcworkspace`、`CODE_SIGNING_ALLOWED=NO`，DerivedData 为 `SunSmart-fix-gateway` |
| 工作区 | `git diff --check` 通过；SDK 工作树及依赖未改动 |

回归检查中的两项源码断言作了同步维护：Wi-Fi 脚本原本不接受 HEAD 已有的 `!isDeletingGateway, supportsGatewaySignalRefresh` 组合 guard；Force Clear 的断言改为检查迁移后的连接会话状态。Ready timeout 与旧尝试隔离不再依赖源码字符串，改由行为测试验证。

未执行真机安装或运行。编译与隔离测试不能证明固件侧重连成功率；1 秒冷却和 2 秒对象持有仍是 App 补偿策略。

## 最短人工验收

1. 用本工作树构建，在同一网关连接成功后退出并立刻重进，连续至少 10 次。预期重进在关闭请求满 1 秒后开始连接，成功后正常进入 Proxy Ready。
2. 若出现原有 10 秒 BLE timeout，继续停留：SDK Bool 失败通常在该次约 15 秒时返回，随后应出现下一次 `[GatewayConnection] ... connect`（count 增加）。三次尝试或 50 秒到限后才结束并提示失败。
3. 在重试等待或连接中退出，确认随后没有该 page 标识的新 connect；旧回调可出现 `ignored_callback`，不能关闭新页面的连接。
4. 进入网关子页面再返回，或取消交互式关闭，已就绪连接应继续复用。

诊断前缀为 `[GatewayConnection]`，主要事件为 `scheduled`、`connect`、`completed`、`failed`、`close_requested`、`ready`、`finish`、`ignored_callback`、`budget_exhausted`。`close_requested` 只代表 App 发出关闭请求，不代表物理断开已完成。后续粘贴 SDK 原始报文前需去除凭据。

## 补充分析：进入网关页面的耗时链路与提速方案

时间：2026-09-17 10:23（Asia/Singapore）。本节仅分析方案，未修改 App 或 SDK 业务代码，也未重新构建或运行设备。上文构建和测试结果属于此前重进修复，不代表本节提速方案已实现或验收。

当前基线：App `fix-gateway`，HEAD `18cf1834`，分析开始时工作树干净；本地 workspace 映射正常，SDK `one-dev`，HEAD `eba71f13dffb50ecad7bc4a854a4086982d50dd1`，工作树干净，与正式依赖锁定 revision 一致。

### 结论与证据边界

存在三类值得处理的等待：SDK 特定代理切换路径可能等待约 5 秒才首发白名单；云端关联 Space 请求使用覆盖页面的加载框；Wi-Fi 状态展示被凭据读取串行挡住。前一项可缩短实际 Proxy Ready 时间，后两项主要缩短页面可用与状态可见时间。

代码能够确认这些路径和条件；当前没有此次“感觉慢”的阶段耗时日志，不能断言某一项就是本次现场主因，也不能给出已实现的提速百分比。此前日志证明过 BLE 建连超时，应与本节发现的 GATT 成功后白名单等待分开判断。

### 当前实际业务流程

入口是 Site 网关操作按钮 → `SiteViewController.gatewayOperationClickAction` → 模态导航栈。Wi-Fi 网关使用 `WiFiGatewayViewController`，4G 网关使用 `GatewayViewController`，连接会话共用后者；Space 下的 `GatewaysViewController` 不是此次实际详情页入口。

1. `viewDidLoad` 建立页面、读取本地模型、注册连接观察者，同时异步请求 `gatewayAssociationSpaceList`。该请求显示覆盖当前页面的 HUD，返回后更新关联 Space 并隐藏 HUD；HTTP 请求超时配置为 10 秒。它不在 BLE 的前置依赖中，但可能挡住页面交互，不能将其耗时直接加到 BLE 耗时上。
2. `viewWillAppear` 调用 `ensureTargetGatewayProxyConnection`。同网络、同目标网关已有有效 Ready 会话时直接复用；否则创建本页连接尝试。仅同目标刚关闭后不足 1 秒时等待剩余冷却，首次正常进入不额外等待。退出后的 bearer 持有 2 秒只为延续对象生命，并不等价于强制等待 2 秒。
3. App 调用 `connectProxy(node:)`。SDK 再检查已打开目标代理；没有可复用连接时扫描 Mesh Proxy 广播，校验网络/子网并按网关 MAC 匹配。App 当前未传入 SDK 已支持的 peripheral 参数，因此走重新扫描路径。
4. 找到目标后进行 BLE 连接 → 服务发现 → 特征发现 → 开启通知。GATT Open 时 SDK 的 Bool 成功回调已返回，但页面仍等待严格的 Proxy Ready。
5. 用有效网络 beacon 确认 Proxy key，配置 accept list 和所需地址，收到 FilterStatus 后发布带目标节点及会话身份的 Proxy Ready。此时页头结束 Connecting，显示 SIG Mesh 在线；不能提前用 GATT Open 或云端在线替代。
6. Ready 后，基类发起 `TimeGet` 读取网关时间。Wi-Fi 子类另外串行执行：读取凭据 `0x12` → 已配置时查询连接状态 `0x0E` → 已连接时立即查询 RSSI/互联网状态 `0x0F`。未配置分支显示未配置并读取手机 SSID。凭据或连接状态读取失败会使 Network Connectivity 区域继续隐藏；页头初始为未连接，已连接分支要等 RSSI/互联网查询才更新为相应状态。
7. 4G 分支在 Ready 后查询 SIM/信号，并进行 10 秒周期刷新，不走 Wi-Fi 的三步读取链。Wi-Fi 首次 RSSI 是立即查询，后续是上次完成后延迟 5 秒再查，因此不能把 5 秒轮询间隔当成首次必等时间。

正常进入页面不会自动重新配置 Wi-Fi，也不会自动执行 MQTT 授权；这两类写操作由对应用户动作触发。时间读取也不等同于自动下发 TimeSet。

### 已定位的等待与优先级

| 优先级 | 发现与代码依据 | 建议及预期收益 | 边界 |
| --- | --- | --- | --- |
| P1：实际连接耗时 | `MeshLibManager.bearerDidOpen` 只开启 5 秒白名单重试 timer；`NetworkLayer.updateProxyFilter` 仅在 `proxyNetworkKey == nil` 时立即初始化。已连接其他代理再切换网关、key 未清空时，首轮可能落到 +5 秒 timer | 用新 bearer/session 单独标记“需要初始化白名单”，在新连接的有效 beacon/key 与发送目标确认后立即首发，5 秒 timer 只做失败重试；命中条件时可消除该约 5 秒空等 | 需修改 SDK，实际收益待阶段日志验证；不能在旧 key/旧代理上盲目首发，不能取消 Ready 门槛 |
| P1：页面可用 | `GatewayViewController.viewDidLoad` 为关联 Space 云请求显示页面 HUD | 复用本地关联数据显示，改为该区域内加载/失败重试；不阻塞其他与该请求无关的操作 | 不加速 BLE 或 HTTP；关联编辑/删除等仍必须保持现有权限和最新数据校验 |
| P2：Wi-Fi 状态可见 | `loadNetworkConnectivityFromGateway` 必须先读完整凭据，成功后才查询连接状态，最后查 RSSI；请求期还会锁住相关控件 | 先查连接状态并明确显示“读取中/已连接/未连接/未配置”，联网与信号随后补齐；凭据读取继续单独保护编辑区 | 先调整读取优先级与展示，不直接并发所有 Vendor 请求。固件异常码、旧固件和未配置路径保留；已连接 Wi-Fi 不代表互联网可用 |
| P2：扫描耗时 | `connectProxy(node:peripheral:result:)` 已支持直接使用已知 peripheral，当前页面只用无 peripheral 重载 | 如果日志表明扫描占比高，再按网络及目标复用近期已验证 peripheral，失效时回落扫描 | 不缓存“在线”为连接成功，不只凭 MAC 绕过网络身份检查；必须保留目标与 Ready 会话确认 |
| P2：失败长尾 | BLE 10 秒超时后，SDK 指定节点失败通常仍由 15 秒 timer 返回 | SDK 在明确失败/取消终态时及时结束该尝试并回传原因，再由 App 有界重试，可减少等待外层 timer 的空档 | 只能缩短失败恢复，不能改善本来成功的 BLE 建连；需要防旧尝试回调污染新连接 |

5 秒候选的条件链：已有代理使 NetworkLayer 保存了 `proxyNetworkKey` → 新网关 GATT 打开并关闭旧代理 → 有新代理可发送，通常没有 `bearerClosed` 发送失败 → key 未清空 → 新 beacon 更新 key 时 `justConnected` 为 false → 没有立即调用 `newProxyDidConnect` → GATT Open 后约 5 秒 timer 才触发初始化。

全 SDK 的该 key 清空赋值位于发送遇到 `BearerError.bearerClosed` 的路径；代理关闭回调本身没有重置它。冷首连 key 为空时，收到有效 beacon 即可初始化；已有目标 Ready 的复用路径也没有这个等待。因此这不是所有进入场景固定增加 5 秒。

### 正确理解各个时间参数

| 参数 | 当前值 | 含义 |
| --- | --- | --- |
| 同目标快速重进冷却 | 距关闭满 1 秒 | 只等待剩余部分；不能解释通常首次连接的多秒等待 |
| BLE connect | 10 秒 | 未建连的失败期限，不是正常延迟 |
| GATT 服务发现 | 3 秒超时，失败间隔 0.5 秒，最多重试两次 | 正常服务发现不固定等满期限 |
| SDK 指定目标连接 | 15 秒 | 扫描/建立 GATT 的外层失败期限 |
| App Bool 回调兜底 | 18 秒 | 处理 SDK 回调缺失，成功即结束该等待 |
| App Proxy Ready 等待 | GATT 成功后 20 秒 | 等严格白名单就绪，成功即取消 |
| App 一轮恢复 | 最多 3 次，总预算 50 秒 | 包含首次及两次重试、间隔和各阶段；不能把所有 timeout 再机械相加 |
| Wi-Fi 三类读取 | 凭据 7 秒、连接状态 3 秒、RSSI 4 秒 | 每个请求的响应超时配置，实际成功响应会提前完成；不是正常进入必等 14 秒，也不是整页严格总时限 |
| TimeGet | 10 秒 | 独立响应等待，不会要求 Wi-Fi 等它返回 |

`MeshAPI.sendMessage` 进入全局发送队列，约每 0.2 秒发一条，但不等待上一条业务回复。TimeGet 虽先入队，不会因自身 10 秒 timeout 让后续 Wi-Fi 固定等待 10 秒；真正的 Wi-Fi 串行依赖在 App 回调与 `activeWiFiRequest` 单请求保护中。首轮心跳也可能进入同一发送队列，但不能据此断言它造成当前长耗时。

不建议优先缩短所有 timeout、删除重进冷却、全局提高发包频率或改为每次退出保留连接。这些分别改变失败恢复、断开竞争、所有 Mesh 请求及页面资源归属，未解决已找到的首发空等。CoreBluetooth 的取消是异步操作，取消请求不保证底层物理连接立即结束；若后续替代 1 秒补偿，应以 SDK 可观察的关闭终态和可靠回退为依据。[Apple 取消连接说明](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:))

已知 peripheral 的复用可建立在系统按 identifier 获取 peripheral 的能力上，但“能取回对象”不是“仍可连接”或“网络身份已确认”的保证。[Apple retrievePeripherals 说明](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveperipherals(withidentifiers:))

### 建议实施与验证范围

优先记录现有链路的少量阶段时间，并处理已确认的页面 HUD 依赖。若 GATT Open 到白名单首发贴近 5 秒，优先修 SDK 初始化生命周期；如果限定只改 App，则先完成局部加载和 Wi-Fi 展示顺序，明确这不能消除 SDK 的白名单等待。

阶段记录应包含：点击进入、发起连接、扫描匹配、GATT Open、首个有效 beacon、白名单首发、Proxy Ready、关联 Space 请求完成、Wi-Fi 状态可见、凭据可编辑。统一使用单调时钟及页面/尝试/Ready 会话标识；DEBUG 日志不记录 SSID、密码、密钥或报文载荷。App 已有 `[GatewayConnection]` 可复用，不另建通用诊断框架。

同一网关和位置对比：首次连接、已有其他代理时切换、快速退出重进、同一 Ready 子页面返回；各记录多次的阶段中位数及长尾，并同时记录失败率。Wi-Fi 覆盖已配置、未配置、读取失败；HUD 覆盖云端慢/失败。不能只统计成功样本而掩盖失败率上升。

若实施 SDK 方案，行为测试应覆盖：旧 key 已有时新连接仍及时初始化、同一连接重复 beacon 不重复首发、旧 bearer 迟到回调、错误网络 beacon、首发失败后原重试仍有效。SDK 使用当前 `one-dev`，实施前重新核对是否有其他任务写入，并记录 revision/差异及正式发布待办；不能只在本地路径修好而漏发远端依赖。

主要源码索引：

- App 入口与并行 HUD：`SunSmart/Main/Site/Controller/SiteViewController.swift` 的 `gatewayOperationClickAction`；`SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift` 的 `viewDidLoad`、`viewWillAppear`、`ensureTargetGatewayProxyConnection`。
- App 连接恢复：`SunSmart/Main/Device/Gateway/Model/GatewayDetailProxyConnectionState.swift`。
- Wi-Fi 读取和展示：`SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` 的 `loadNetworkConnectivityFromGateway`、`loadConfiguredGatewayConnectionStatus`、`startWiFiRSSIStatusRefresh`；超时在 `Model/WiFiGatewayV19Timing.swift`。
- SDK 相对 `Sources/NordicSigMeshSDK/`：`MeshLib/Manager/MeshLibManager.swift` 的 `bearerDidOpen`、`proxyFilterUpdated`；`MeshLib/MeshNetwork/NetworkConnection.swift` 的 `connect`、`bearerDidOpen`；`nRFMeshProvision/Layers/Network Layer/NetworkLayer.swift` 的 `updateProxyFilter`；`nRFMeshProvision/ProxyFilter.swift` 的 `newProxyDidConnect`；`MeshLib/Manager/MeshMessageManager.swift` 的发送 timer。

## 补充分析：30 秒建连需求与第三次连接被总预算中断

时间：2026-09-17 10:33（Asia/Singapore）。用户明确本轮先完成统一分析与方案，不实施。范围调整为白名单及时初始化、网关建连超时和失败恢复；上节的页面 HUD、Wi-Fi 读取顺序和 peripheral 缓存优化不纳入当前建议实施范围。

### 日志能够确认的结论

此次不能归结为“网关一直连不上”：前两次未完成 GATT，第三次已完成 BLE 连接、服务/特征发现和通知订阅，并收到能通过密钥认证的主网 beacon，随后由 App 的总预算主动取消。前两次建连迟缓的底层原因尚未确定；第三次主动中止的责任明确在当前 App 策略。

| 日志事件 | 单调时间 uptime | 分析 |
| --- | --- | --- |
| 首次 SDK 输出 connectionTimeout | 无时间戳 | SDK 自己的 10 秒 BLE 建连 timer 触发取消，并把该错误带到 Disconnected；不是网关返回“连接超时”报文 |
| 第二次发起连接 | 105669.501821 | App 开始该次指定目标连接，尚不能等同于底层 `central.connect` 开始 |
| 第二次 Bool 失败 | 105684.594750 | 间隔 15.093 秒，符合 SDK 外层指定节点 15 秒 timer；随后 App 清理并取消当前 BLE 连接 |
| 第三次发起连接 | 105685.632615 | 间隔约 1.038 秒后重试 |
| 第三次 Bool 成功、此前 GATT ready | 105699.507586 | 自尝试开始 13.875 秒，包含扫描、连接和 GATT 初始化；不能据此说 BLE 自身超过 10 秒或其 timer 失效 |
| 收到主网与子网 beacon | 无时间戳 | 主网密钥认证成功，未见白名单首发/确认；子网 beacon 被丢弃属于当前 SDK 的正常选择分支 |
| App budget_exhausted | 105703.138334 | 成功回调后仅 3.631 秒，触发主动取消；没有给这次完整的 20 秒 Proxy Ready 等待 |

`Connection timed out after 10.0s` 的来源是 SDK `BaseGattProxyBearer.connectionTimeout = 10` 和 `startConnectionTimeoutTimer()`：在外设仍为 `.connecting` 时记录日志，设置 `GattBearerError.connectionTimeout`，调用 `cancelPeripheralConnection`。该属性为 SDK 内部可见，当前 App 未配置它。默认值作用于共用 bearer，另有 DFU 路径覆盖为 14 秒；直接把默认值全局替换为 30 秒会影响此次网关页面之外的连接。

第二次没有 10 秒日志并不矛盾：SDK 15 秒从指定节点连接开始计时，底层 10 秒从实际 BLE connect 开始计时，两者起点不同。扫描或初始化耗时后，外层可能先到期。当前日志没有各条 SDK 日志的单调时间，不能进一步分解扫描与 BLE 各占多少。

### 白名单与预算为何会叠加失败

按成功回调近似 GATT Open 时间，5 秒白名单兜底首发预计约在 `105704.508`，比 App 关闭晚约 1.369 秒。SDK 行没有时间戳，回调也经过主线程调度，这只是近似对齐；不能把它当作精确记录到的 timer 触发时刻。

提供的日志在有效主网 beacon 后没有 `New Proxy connected`、`Sending SetFilterType` 或白名单确认，且没有显示主网 IV 校验拒绝。结合已查明的旧 `proxyNetworkKey` 抑制首发路径，白名单延迟是强候选；尚不能仅凭日志缺失证明状态变量当时一定非空。此次确定的是 App 在 GATT 成功后很快主动关闭，白名单的 5 秒兜底很可能来不及发挥作用。

`Discarding beacon for secondary network` 不表示主网认证失败，不能通过放宽密钥/网络检查解决。`XPC connection invalid` 缺少来源、实例及错误上下文，不能单凭这一行判断网关、蓝牙系统或 App 谁出错。

网关可连接广播恢复较慢、固件繁忙或连接占用、无线环境、iOS 蓝牙状态及旧连接释放时序都仍可能影响前两次建连；日志不足以在这些假设之间作出选择。第三次成功证明当时能建立 BLE/GATT 并接收认证 beacon，不证明网关始终正常，也不证明 Mesh 双向业务消息已全部可用。

### 统一修改方案（待确认实施）

建议将网关指定连接的时间拆成有明确起点的阶段，保留其他调用方原有配置与签名兼容。不能只改一个 `10` 为 `30`：现有 SDK 15 秒和 App 18 秒会先中止。

| 阶段 | 当前策略 | 建议初始策略 |
| --- | --- | --- |
| 扫描匹配目标 | 与建连/GATT 共享 SDK 15 秒外层期限 | 网关连接单独允许扫描最多 15 秒；匹配后停止该阶段 timer |
| BLE 建连 | 共用 bearer 默认 10 秒 | 网关指定连接传入 30 秒，从实际 `central.connect` 开始；didConnect/明确失败/取消即结束计时 |
| GATT 初始化 | 服务发现每次 3 秒、最多两次重试，特征/通知缺少完整独立总期限 | 保留服务发现重试，网关路径增加约 12 秒阶段期限，覆盖约 10 秒的服务发现失败路径及特征/通知余量 |
| SDK 目标回调与 App 兜底 | SDK 全阶段 15 秒、App 18 秒 | SDK 按阶段及时完成成功/失败回调，不再让原 15 秒 timer 跨阶段抢跑；App 约 60 秒兜底，来源为扫描 15 + BLE 30 + GATT 12 + 调度余量 3 |
| Proxy Ready | 成功回调后 20 秒，但会被整轮 50 秒覆盖 | 保留成功回调后的独立 20 秒，等待真实白名单确认 |
| 整轮恢复 | 最多三次；50 秒一到直接关闭当前尝试 | 保留最多三次及重试间隔；把 50 秒改为“允许发起新尝试的窗口”，不截断已经发出的有效尝试；当前尝试仍由上述阶段期限和回调兜底约束 |

除用户指定的 BLE 30 秒外，表中 12/60 秒是建议初始配置，不是协议常量，实施时应由一处网关连接配置推导并验证。首次、重试和直接外设连接路径应使用同一规则；退出、蓝牙关闭、切换网络和用户取消仍立即结束会话，不因新超时而延迟。

上述窗口规则需要明确代价：不再承诺整轮 50 秒内结束；接近窗口末尾开始的尝试可以完成自己的阶段，保守上界约为 50 + 60 + 20 = 130 秒（不含调度异常），最多三次不意味着每次都必须用满三次。连续长超时通常会更早耗尽“新尝试窗口”，不会无限延长。正常连接不会主动等满任一期限，白名单及时首发才是改善成功路径速度的措施。

SDK 必须同时把目标 bearer 的明确失败及时向该次指定连接回调传递，取消扫描/阶段 timer，并以尝试身份保证只完成一次。当前 `didClose` 主要负责移除 bearer，没有及时完成指定连接回调，失败因此可能等到外层 timer。关闭期间保留必要对象到关闭终态或有限兜底，旧尝试迟到回调不得结束新尝试；无需改其他设备的自动代理策略。

### 白名单实现边界补充

还确认一个会话起点接线问题：`NetworkConnection.bearerDidOpen` 收到实际 GattBearer 后向上层传的是 `self`（NetworkConnection）。`MeshLibManager.bearerDidOpen` 内 `as? GattBearer` 的 `beginSession` 分支因此在正常路径不执行；白名单完成时仍可通过 `markReadyIfNeeded` 懒创建会话，所以这不是“所有 Ready 必然失败”的证据，但不能依赖当前回调完成新会话初始化。

实施应在确认新实际 bearer 成为发送代理时，建立明确的新会话边界，使本会话首个合法认证 beacon 即可触发白名单首发。保留白名单确认才 Ready，以及原失败重试。可以保留对外通用连接回调语义，用内部会话通知承接，避免为了修复局部流程改变全部 SDK delegate 的既有含义。

不能在每次 beacon、旧连接关闭或异步 Bool 成功回调中无条件清 key，也不能直接使用旧代理 key 提前发白名单。当前接收链路会丢失实际 bearer 来源，后续又有 `Task.detached` 处理；因此 Proxy beacon/FilterStatus 的会话身份或局部顺序保护必须与初始化一起处理，防止旧消息影响新会话。这是本次连接生命周期的必要一致性保障，不需要重构普通 Mesh 业务消息调度。

### 最小验证与归因下一步

实施时优先复现本次明确失败：前两次失败，第三次在整轮约 46 秒完成 GATT，白名单在约 51 秒确认；预期不会在 50 秒被主动关闭。还应覆盖：BLE 在 29 秒成功和 30 秒未成功；扫描 15 秒失败；GATT/Ready 各自超时；恢复窗口到期不再启动下一次，但当前阶段完成；失败立即回调；退出与旧回调隔离；同网络已有旧 key 时新连接及时首发。

沿用 `Tests/Device/GatewayDetailConnectionSessionTests.swift` 的可控时钟覆盖 App，SDK 复用 `Tests/Standalone/ProxyReadyRegistryTests.swift` 并补真实初始化策略的行为测试。现有 registry 测试不覆盖 NetworkConnection 的回调接线，也不覆盖 NetworkLayer 首发，所以不能独立当成本次完整验收。稳定后按 SDK 公共接口影响完成相关品牌 generic iOS 构建；真机由用户验收。

仅补本次所需 DEBUG 阶段记录：扫描开始/匹配、实际 BLE connect/didConnect、GATT Ready、有效 beacon 接受/拒绝原因、白名单首发/确认、失败/取消来源及剩余期限；带页面/尝试/实际 bearer 会话标识和单调时间，不打印密钥、SSID、密码或原始载荷。这样下一次若仍在 30 秒内没有 didConnect，才能把“扫描慢”“App 提前取消”“BLE 实际未建连”分开，再决定是否需要网关侧广播/连接日志。

本轮验证仅包括源码复核、用户日志时间差计算及文档 diff 检查；未修改业务代码，未运行新测试、构建或设备。SDK 保持 `eba71f13dffb50ecad7bc4a854a4086982d50dd1` 且干净。实施 SDK 后需记录实际 revision/未提交差异及远端 release 发布待办，本地编译不代表正式依赖已包含修复。

## 补充分析：普通节点与网关的超时策略对照

日期：2026-09-17。本轮用户要求比较其他节点和网关，并分析统一连接超时策略；仍只分析、不实施。App 与 SDK HEAD 未变。**本节将此前“仅网关指定连接改为 30 秒”的范围建议更新为“普通节点与网关的常规 Mesh Proxy 连接共用 SDK 阶段策略”**；页面展示仍维持现状，配网/DFU 的业务期限单独核对。

### 当前是否相同

结论：底层大部分相同，完整业务策略不同。普通节点和网关并没有按产品类型分别设置 10 秒与其他值；差异主要来自调用入口、用途，以及调用方额外的 timer。甚至同一个网关，在详情页和 Sync Gateways 页面使用的完整策略也不同。

普通灯具进入详情页主要通过当前 Mesh 代理发送状态读取与控制消息，不会自动要求手机重新直连这盏灯。只有“Set Proxy”等明确动作才指定连接该节点。网关详情页则要求目标网关成为实际 Ready 代理。因此两类页面的体感速度不能仅用 BLE timeout 数值比较。

| 当前有效入口/路径 | BLE 建连期限 | 外层连接期限与重试 | 当前成功判定 |
| --- | --- | --- | --- |
| 网关详情（Wi-Fi/4G） | 10 秒 | SDK 指定连接 15 秒；App 回调兜底 18 秒、Ready 20 秒、最多三次、整轮 50 秒 | 目标 Proxy Ready；GATT Bool 成功只进入继续等待 |
| 普通灯具 Set Proxy | 10 秒 | 同一 `connectProxy` 的 SDK 15 秒；该 App 调用点没有详情页的重试和总预算 | Bool true 即提示成功，此时是 GATT Open，未额外等待严格 Ready |
| Space 调试指定节点 | 10 秒 | 同一 SDK 15 秒；首次可传 peripheral 跳过扫描，重连用无 peripheral 重载 | Bool true 后继续 UART 支持检查/调试流程 |
| Sync Gateways 时间同步 | 10 秒 | 同一 SDK 15 秒；传已扫描到的 peripheral，无网关详情的 18/20/50 秒策略 | Bool true 后直接发 TimeSet，随后业务响应等待 10 秒；没有显式的严格 Ready 等待 |
| Space 自动连接 Mesh 代理 | 每个新 GattBearer 默认 10 秒 | 自动扫描、挑选代理；失败/断开后在自动模式继续扫描，没有指定连接的 15 秒单次回调期限，也没有网关页面最多三次/50 秒规则 | 全局 `isMeshNetworkConnected`；通常白名单成功更新，但 SDK 另有白名单多次失败后的旧连接状态兜底，不等同于严格 Ready |
| 批量 Mesh 命令等待网络 | 继承自动代理的 10 秒 | `MeshProxyMessageCommand` 网络未连接时开启自动连接，另设 15 秒；到期将尚未发送的命令判失败 | 接收 MeshLibManager 的连接通知再开始发消息；与命令 ACK 超时分开 |
| Site Trigger Zone 切换网络 | 继承自动代理的 10 秒 | App 单独等待网络 30 秒，到期主动断开；用户可重试 | 匹配网络的 `isMeshNetworkConnected`，不是某个指定节点的严格 Ready |

普通自动代理还存在两种容易混淆的时间：弱信号候选选择有约 1 秒防抖；自动替换弱信号代理有 15 秒选择状态 timer。它们都不是底层 BLE 建连超时。Space 页的 10 秒 HUD 自动隐藏也不是取消连接，不能把 UI 隐藏时间当成连接失败期限。

### 专用路径的区别与实际入口

`GattBearer` 和配网使用的 `PBGattBearer` 均继承 `BaseGattProxyBearer`，共用默认 BLE 10 秒和服务发现重试（每次 3 秒、最多两次重试、间隔 0.5 秒）。所以全局修改 base 默认值会波及配网，并不只影响普通代理和网关。

| 路径 | 当前限制 | 与统一策略的关系 |
| --- | --- | --- |
| 未配网 Identify | PBGatt BLE 10 秒；外层等待 GATT Open 也为 10 秒，打开后再计 Attention 时间 | 若 BLE 改 30 秒，该外层 10 秒也必须调整；Attention 时长不能跟着改 |
| 当前 App 添加/恢复（FastAdd） | 初次 PB BLE 10 秒；15 秒未 Open 触发一次关闭并间隔 1 秒重连；整个添加初始期限 30 秒 | 只改底层会被 15 秒重连和 30 秒整个流程期限截断；连接与配网/绑定必须分开预算 |
| FastAdd 配网后配置 | 非 Telink 重新创建 GattBearer，默认 10 秒；Telink 路径直接切换 service | 前者涉及第二次 BLE 建连，后者不是重新连接；均不能机械累加同一个 30 秒到所有阶段 |
| 当前 BLE/Mesh DFU | 新建 GattBearer 显式设置 14 秒，外层连接 15 秒，失败后间隔 0.5 秒，最多三次重连；复用旧代理则继承该 bearer | 只改默认 10 秒不会改变显式 14 秒；统一单次连接策略需联动 14/15 秒及重连总耗时 |
| BLOB 初连/重连 | 使用传入 bearer，不自行创建；BLE 继承 10/14 秒，外层 15 秒；依据 RSSI 允许不同重连次数 | 不存在一个独立“BLOB BLE 默认值”；应统一传入 bearer 与外层连接阶段，保留数据传输期限 |
| Mesh Distribution 上传前连接 | 默认 BLE 10 秒，指定连接外层 15 秒，Bool true 后读取分发信息 | 同一 NetworkConnection 连接策略的有效调用方，不能漏掉 |
| 当前传感器校准 Manager | 扫描 15 秒；找到后新建 GattBearer，BLE 10 秒，外层 GATT 15 秒；打开后转业务准备 20 秒 | 扫描、建连和校准命令是不同阶段，只改建连相关期限 |

App 的添加入口（Classic、Professional、Site 添加和 Restore）均找到 `MeshAPI.startFastAddDevices` 实际调用；传感器校准当前使用 `MeshSensorCalibrateManager`。SDK 还保留旧添加总预算 120 秒、独立 provisioning 总预算 10 秒、旧/β校准指定连接 15 秒等实现，但此次没有找到 App 对独立 provisioning 的调用，旧校准 App 调用已注释。它们属于 SDK 全局默认变更的兼容性审计项，不能描述成当前页面都会经过。

EnOcean SDK 操作和 Vendor OTA 对应路径未自行建立 BLE，使用已有 Mesh 通道；其中 10/15 秒是业务响应等待。控制灯具、配置绑定、TimeSet、固件传输等响应超时同理，不应因为 BLE 统一 30 秒就统一改为 30 秒。

### 更新后的统一建议

1. **常规 Mesh Proxy 连接按用途统一，不区分网关还是灯具。** 在 SDK 维护同一组扫描、BLE 建连 30 秒、GATT 初始化、Proxy Ready 阶段定义。指定节点连接的公开入口和 SDK 内部直接调用 NetworkConnection 的路径都使用它；App 不再各自猜测底层需要多久。扫描和 GATT/Ready 数值仍是待实施验证的配置，前一节的 15/12/20 秒可作为初值。
2. **保留不同任务的结束方式。** 自动代理应能继续选择其他节点；用户指定连接应给出有界结果；网关页面可保留有限重试和进入页面的生命周期。无需把所有页面都套上“最多三次、50 秒窗口”，也不能让页面的短预算抢先中止已进入下一阶段的有效连接。
3. **统一“可以开始 Mesh 业务”的判断。** 常规指定连接若随后要发送 Mesh 消息，应复用现有 Proxy Ready 上下文及观察机制，等实际目标白名单完成。既有 Bool 回调当前表示 GATT 打开，不能未经迁移就暗改它的语义；Set Proxy、Sync Gateways、Distribution 和校准等调用方需按用途逐一衔接。UART 调试、配网和专用 DFU 不因这一调整被强制增加无关的 Mesh Ready 门槛。
4. **白名单及时初始化在 SDK 共用层修复。** 普通代理切换和网关重连都受益，按实际 bearer/session 隔离旧 beacon、关闭和确认消息，不在 App 为网关单独绕过初始化。
5. **外层期限同批联动。** 必须覆盖指定连接的 15 秒、批量命令等待网络的 15 秒、自动代理替换的 15 秒、Trigger Zone 的 30 秒，以及网关详情 18/20/50 秒的关系。需要区别“只结束业务等待”和“实际关闭蓝牙”；不是搜索所有 15/30 秒后批量替换。
6. **配网与 DFU 使用明确的专用配置。** 可以复用相同的 BLE 阶段实现；若产品目标是连这些场景也统一为 30 秒，则必须把上表的 Identify/FastAdd/DFU/BLOB/校准外层计时一起调整并验证。当前分析不把“普通节点与网关统一”自动扩大为所有业务超时统一，也不把专用 14 秒当成已有固件协议要求。

实际代价是：未响应节点的单次 BLE 等待可能从 10 秒延长到 30 秒；自动代理可能因此更晚转向另一个候选，DFU 重试最坏耗时也会增加。明确拒绝/失败应立即结束当前尝试，而非强行等满 30 秒；用户退出、取消、蓝牙关闭仍立即响应。统一的价值是阶段边界和失败行为一致，不保证所有场景的失败提示更快。

建议按一组常规 Mesh Proxy 连接改动实施，验证普通灯具 Set Proxy、Space 自动连接/代理替换、网关详情、Sync Gateways、批量配置等待网络及 Trigger Zone，覆盖 10～30 秒内成功、30 秒无响应、GATT 成功后白名单稍晚、明确失败、退出及旧回调。如果改到 BaseGattProxyBearer 共用默认值或 DFU 显式配置，则额外覆盖当前 FastAdd、未配网 Identify、DFU/BLOB 和校准，不能仅凭网关通过就认定其他节点已兼容。

### 源码定位与本轮验证

- 普通灯具入口：`SunSmart/Main/Device/Controller/DeviceLightViewController.swift`，`viewDidLoad`/`getNodeState` 与 `moreClick` 内 Set Proxy 分支。
- 同一网关的另一个入口：`SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift`，`synchronize`；扫描与业务区分见 `SyncGatewaysScanSession.swift` 和 `SyncGatewaysViewController.swift`。
- 普通自动代理：`SunSmart/Main/Space/Controller/SpaceViewController.swift` 的 `setNetworkConnected`；SDK `NetworkConnection.open`、`centralManager(_:didDiscover:advertisementData:rssi:)`、`proxieCloseHandle`。
- 额外业务外层：SDK `MeshProxyMessageCommand.addMessage`/`meshNetworkConnectTimeout`；App `SiteTriggerZoneViewController.swift` 的连接协调器 `scheduleTimeout`/`fail`。
- 专用路径：SDK `MeshAddDeviceManager`、`MeshFastAddDeviceManager`、`MeshDeviceProvisioningManager`、`MeshFirmwareUpdateManager`、`MeshFirmwareBLOBServer`、`MeshFirmwareDistributionManager`、`MeshSensorCalibrateManager`。

本轮完成有效调用点与 SDK 实现的只读对照，区分了注释/未发现 App 调用的旧路径；仅更新本文，未修改生产代码，未构建或运行设备。

## 2026-09-17 实施记录：统一常规 Mesh Proxy 连接策略

用户授权“按更新后的统一建议继续”后，本轮已实施 App 与本地 SDK 的共用连接链路。以下记录替代前述章节中“尚未实施”的当前状态，前面的分析保留作为决策依据。

### 已落地行为

| 阶段 / 调用方 | 本次实现 |
| --- | --- |
| 指定节点扫描 | 15 秒；发现目标后取消扫描阶段期限 |
| 常规 Mesh Proxy BLE 建连 | 普通节点、网关共用 30 秒；进入 GATT 后取消建连阶段期限 |
| GATT 初始化 | 12 秒，覆盖服务/特征发现与通知开启；关闭时取消发现重试 |
| Proxy Ready | GATT 打开后 20 秒，实际目标的完整白名单确认后才成功 |
| App 指定连接外层 | SDK 导出 GATT 回调兜底 60 秒、含 Ready 的兜底 80 秒 |
| 网关详情 | 最多三次、1 秒冷却保留；50 秒仅禁止新尝试，已开始的尝试继续受阶段期限约束 |
| 自动代理 | 保留自动扫描/候选选择；每个候选受 BLE/GATT/Ready 阶段期限约束；候选失败可继续重选；指定目标不因低 RSSI 被自动替换 |
| 配网、专用 DFU/BLOB | 保留 Base 默认 10 秒、专用 DFU 显式 14 秒及各自业务期限，没有统一改成 30 秒 |

50 秒不再是页面等待的绝对上限。若最后一次在窗口末尾启动，App 兜底理论上可接近 130 秒（发起时刻 + 60 + 20）；SDK 正常回调会按实际阶段更早完成或失败。这是允许有效在途连接完成的取舍，界面加载和 Wi-Fi 展示逻辑未改。

- 保持 `connectProxy` 的 Bool 表示 GATT 已打开；新增 `connectProxyReady(node:peripheral:result:)`，成功表示目标 Proxy Ready，回调在主线程。
- Set Proxy、Sync Gateways、SDK Distribution 与旧/β校准等需要 Mesh 通信的入口已迁移到 Ready API；复用已有连接时也检查目标 Ready。UART 调试入口保留 GATT 语义。
- 网关详情继续使用 GATT 回调 + 已有目标 Ready 观察器；计时常量由 SDK 注入 Foundation-only Session。TimeSet 的 10 秒消息响应期限保持不变。
- 批量 Mesh 命令等待网络、Trigger Zone 外层等待改用 SDK 80 秒兜底；业务消息响应时间没有混入连接阶段时间。

### 白名单与会话隔离

常规 `NetworkConnection` 的 Proxy 控制事件在主队列与 CoreBluetooth 生命周期串行执行；普通 Mesh access 消息仍走原调度。每个实际 bearer 打开时创建独立 session，立即清除上个连接的 Proxy key/filter 状态。因此新连接收到有效、通过既有网络和 IV 验证的 beacon 后直接首发白名单，不再等待旧 key 偶然失效或 5 秒重试。

Proxy 配置发送固定到该 session 的实际 bearer；旧 bearer 的 beacon、FilterStatus、关闭回调，以及已排队的发送、delegate 回调和定时回调不能作用于新 session。初始化保留第 5/10 秒整体重试，第 20 秒未确认则失败；常规路径不再使用“重试结束即视为在线”的兜底。每批 FilterStatus 的类型与数量均需匹配，完整确认后才公布 Ready。

关闭正在等待 Ready 的目标（含 `disconnectCurrent`）立即结束等待并只交付一次失败；旧 bearer 断开时短暂保留 2 秒，给异步取消留出释放窗口，此时间不是系统完成断开的保证。

Ready 后的动态白名单仍有请求超时恢复；保留普通代理切换的 `proxyDidReplace` 通知，供组页面重新添加临时订阅地址。未管理的直接 bearer 保留原有 updated/limit 回调顺序。补充的 DEBUG 日志记录阶段、attempt、peripheral、session 和单调时间；有效 beacon 触发首发时记录 `beacon_accepted_filter_start`，新增日志不含密钥、Wi-Fi 凭据或报文载荷。

### 验证记录

- App 网关状态机 12 个用例、连接 Session 19 个场景通过；含第 47 秒 GATT / 第 53 秒 Ready、第 57 秒 GATT / 第 70 秒 Ready、接近第 50 秒启动后的独立阶段超时、冷却跨窗口不再重试、退出及旧回调隔离。
- `GatewayTimeSyncCoordinatorTests` 行为测试、`check_site_timeset_call_sites.sh` 调用点检查通过。
- SDK `check_mesh_proxy_connection_timing.sh` 通过 10 个生产 helper 行为场景，含 29 秒继续等待、30 秒超时、阶段切换、强制触发已取消定时回调、取消幂等与 session gate。
- SDK `check_proxy_filter_session.sh` 编译实际 `ProxyFilter` 并使用传输/模型替身，6 个场景通过：分批确认、错误/不完整确认不能 Ready、重复地址、旧 session delegate 丢弃、动态请求超时恢复与旧 timer 隔离、直接 bearer 回调兼容。
- 最终代码使用 `SunSmartLocal.xcworkspace` 完成 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌 Debug / generic iOS 编译，全部退出码 0；保留既有资源/弃用 API 等警告。SDK `check_network_connection_session.sh` 编译实际 `NetworkConnection` 和阶段 helper，11 个接线行为场景通过，覆盖自动/指定竞争、同目标 pending 采用、GATT/Ready 区分、旧事件隔离、四种取消入口、回调重入、代理替换标识、排队成功失效与 RSSI 选择策略。上述隔离测试与编译不覆盖无线链路、真实 beacon 认证或网关固件。
- Sync Gateways 现有 UI 静态契约有已过时断言：硬编码四个 target / 8 次 Sources，当前工程为五个 target / 10 次。相关测试和工程配置本轮未改；该项不能记为通过。

App 和 SDK 的 `git diff --check` 通过。以上为代码、隔离行为测试和编译验证；真实连接稳定性与速度仍待人工验收。

### 交接与最短人工验收

- App：`fix-gateway`，基线 `18cf1834`，本轮代码、测试和本文为未提交改动。
- SDK：`one-dev`，基线 `eba71f13dffb50ecad7bc4a854a4086982d50dd1`，本轮阶段策略、控制会话、Ready API、调用点及测试为未提交改动。
- 当前入口 `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 正确指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。正式 project 的 gitee `release` 和依赖锁文件未改。
- **正式依赖待办**：需要先将 SDK 本轮差异发布/合入远端 `release`，再更新 App 的正式依赖 revision；新 App 已引用 `MeshProxyConnectionTiming` 与 `connectProxyReady`，不能只提交 App 后期待旧远端 SDK 可编译。
- 未自动安装或运行真机。人工先用同一网关退出再进入，检查 `gatt_open` → `beacon_accepted_filter_start` → `ready` 的间隔和 session；已开始的连接跨 50 秒不能被页面预算主动关闭。再验证普通灯具 Set Proxy、Sync Gateways、组页面代理替换，以及连接中退出/重进不受旧回调影响。
- 若仍出现 30 秒内无 `didConnect`，保留新阶段日志并同步采集网关广播/连接日志；本次已修复可证实的 App/SDK 提前截断及初始化问题，但未凭静态分析判定现场无线迟缓一定属于网关或 App。
