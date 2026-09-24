# Professional Mode 光感添加后 CPU 100% 与页面卡顿分析

日期：2026-09-24。状态：用户已确认方案，App + SDK 修复及自动化验证已完成，真机性能/体验待人工验收。

## 结论

这份 trace 已足以定位本次长时间无响应的直接根因，并给出有针对性的修复方案。

**添加完成通知触发背后的 Lights 页面刷新 RSSI，SDK 在主线程对重复收到的 Node Identity 广播执行全网络节点遍历和 AES 身份校验。持续计算使界面事件和停止扫描的定时回调长时间得不到处理，形成约 48 秒的 Severe Hang。**

不是由“六台设备的数据量”直接解释：用户确认添加前 Space 约有 120 台设备，这六台直接添加到 Space。当前身份匹配遍历整个 MeshNetwork.nodes，并不限于新加的六台。光感模式是现场触发入口，共享 RSSI 路径才是修复重点。

记录中可以同时找到扫描启动、昂贵计算、扫描停止三段调用栈，用户也确认等待很久后自行恢复。证据支持持续计算造成的暂时无响应，不支持将本次现象定性为永久死锁或无限循环。

## 证据范围与复核信息

| 项目 | 本次核实结果 |
| --- | --- |
| 原始 trace | `/Users/maginawin/Desktop/tmp/260924 1542 add pro mode.trace` |
| 录制设备 | iPhone XR，iOS 18.7.10 |
| App / PID | SunSmart / 5564 |
| 时间 | 2026-09-24 15:39:45.596 ～ 15:41:40.420，UTC+8 |
| 时长 / 模板 | 114.824283 秒 / Time Profiler，Attached、Deferred |
| 样本 | 120,668 个，1 ms 权重；累计 CPU 采样权重 120.668 秒 |
| 主线程权重 | 63.951 秒 |
| App 工作树 | `fix-BL9105N-XXCCTXXE-260924` |
| App 分支 / HEAD | `fix/BL9105N-XXCCTXXE-260924` / `fa436c67d00d233ea2fcad5728c53004eb244c54` |
| 实际本地入口 | `SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` |
| SDK realpath | `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` |
| SDK 当前 HEAD | `ebbe1c969381363487bfe6e371bae08e954f6f00` |
| 初始工作树状态 | App、SDK 均无未提交修改 |

原始导出中的 App 符号只有地址。已找到 UUID 完全匹配的本机二进制，通过 `atos` 还原 7,472 个 App 地址：

- UUID：`06E08598-E5F3-319A-B397-DAFAD0072009`。
- 二进制：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmartLocal-egzyzujmrtmffngmxmchpjqzgenz/Build/Products/Debug-iphoneos/SunSmart.app/SunSmart.debug.dylib`。

UUID 匹配保证本次地址解析使用正确构建；App/SDK HEAD 是本轮源码分析基线，不能仅由 UUID 反推出录制时的 Git revision。热点函数及其关键源码行与当前实现相符。

XML 统计解析了 id/ref，包括 thread、weight、backtrace 和 frame；每条栈的同一统计项仅计一次。22 个样本无调用栈。以下权重是统计采样，不是调用次数；包含子调用的各层权重相互重叠，不可相加。

## 完整触发、卡顿、恢复链

### 1. 添加完成后，隐藏的 Lights 页面启动扫描

相对时间 **45.748166 秒**的实际栈包含：

`DeviceAddProfessionalModeController.addDevice 的 addFinish 完成闭包`

→ `NotificationCenter.post(devicesAddNotificationName)`

→ `DeviceLightsViewController.addNotificationObserver 的通知闭包`

→ `getNodesState()`

→ `MeshLibManager.refreshNodesRSSI(withWaitFor: 10)`

→ `scanDevice(withServices: [MeshProxyService.uuid])`。

对应 App 源码：

- [DeviceAddProfessionalModeController.swift](../SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift)：添加完成后的通知位于约第 1638 行。
- [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift)：约第 132～142 行的通知处理无页面可见性限制，直接调用 `getNodesState()`；约第 283 行请求扫描 10 秒。
- `viewWillAppear` 当前加载设备列表，`viewDidAppear` 注册代理，但没有消费“隐藏时延后的状态刷新”的现成状态。因此不能仅删除通知中的调用而丢掉返回页面后的必要刷新。

这段调用栈直接证明此次 RSSI 扫描来自添加完成通知，不只是静态代码推断。

### 2. 主线程身份校验占满一个核心

Hangs 表记录最长卡顿：

- 相对时间 **45.918771 ～ 93.933808 秒**，持续 **48.015038 秒**。
- 对应墙钟约 **15:40:31.515 ～ 15:41:19.530**。
- 该窗口主线程累计运行采样权重 **47.881 秒**。

| 该卡顿窗口内的主线程路径 | 包含权重 | 占窗口内主线程权重 |
| --- | ---: | ---: |
| `refreshNodesRSSI` 广播回调 | 47.777 秒 | 99.78% |
| `MeshNetwork.matches(nodeIdentity:networkKey:)` | 46.857 秒 | 97.86% |
| `Crypto.calculateHash` | 46.285 秒 | 包含在上述链中 |

中间完整 **48～93 秒**区间，主线程权重 44.938 秒 / 45 秒，约 **99.86% 单核 CPU**；进程约 100.24%，与用户观察到的持续 100% 一致。

主要实际调用链：

`CoreBluetooth.didDiscover`

→ `MeshLibManager.refreshNodesRSSI` 广播回调

→ `MeshNetwork.matches(nodeIdentity:networkKey:)`

→ `MeshNetwork.node(matchingNodeIdentity:)`

→ `nodes.first { nodeIdentity.matches(node: $0) }`

→ `PublicNodeIdentity.matches(node:)`

→ `Crypto.calculateHash / calculateECB`

→ `CryptoSwift.AES.encrypt / expandedKey / expandKey`。

### 3. 停止扫描的定时器也被拖延

相对时间 **93.934166 秒**捕获到：

`__NSFireDelayedPerform`

→ `MeshLibManager.refreshNodesRSSIFinish()`

→ `stopRefreshNodesRSSI()`

→ `CBCentralManager.stopScan()`。

它紧接最长 Hang 的结束。启动和停止的采样时间相隔约 **48.186 秒**，而调用参数为 10 秒。当前结束机制是主线程 `perform(...afterDelay:)`，且昂贵匹配前没有独立的会话到期检查。证据支持主线程负载使定时停止延后，从而延长扫描处理的卡顿窗口。

采样没有逐包入口/出口及定时器注册 signpost，不能精确分解“排队等待时间”“每包时长”或算出包数，也不能将 48 秒误读为单次 AES 的执行时间。

## SDK 内部的具体放大机制

源码目录均相对于上述 SDK realpath：

1. `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`：初始化 `CBCentralManager(delegate: self, queue: nil, ...)`，本次回调栈也确认在主线程。`scanDevice` 开启 `AllowDuplicates = true`。
2. `refreshNodesRSSI` 约第 640 行先根据厂商 MAC/旧 MAC 查找实际 Node，但普通扫描分支随后没有复用该 Node 做定向认证；约第 789 行仍调用全网 `matches(nodeIdentity:networkKey:)`。
3. `Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/NetworkConnection.swift` 的上述 helper 先搜索 `meshNetwork.nodes`，匹配后才判断返回 Node 是否包含当前 Key index。
4. `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh API/MeshNetwork+Nodes.swift` 的搜索逐 Node 计算；`Mesh Model/NodeIdentity.swift` 中每个 Node 又尝试它的 Network Key，Key Refresh 时还可能尝试旧 Key。
5. 普通 RSSI 分支在身份计算之后才处理 `lookupReason`。即使厂商数据不能对应本地 Node，仍可能先执行全网认证，随后才丢弃该包。
6. `NodeRSSIRefreshSessionPolicy.accept` 仅在认证完成、发出结果时去重更新样本，不缓存认证结果，也不阻止同一身份包重复消耗 AES 计算。
7. `Crypto.calculateECB` 每次新建 AES 对象；对象的 `expandedKey`、S-box 是实例级惰性数据，新实例仍需重新计算。当前 Debug 构建进一步放大这条重复计算链的成本。

SDK 已有 `NodeIdentity+NetworkKeyMatch.swift`，支持对“指定 Node + 指定 NetworkKey”认证 Public/Private Node Identity，并尝试当前和旧 Identity Key；Gateway 受限扫描已使用它。修复优先复用这一能力。

**MAC/Peripheral 仅用于选择候选 Node，不能代替密码学身份认证。** 复用 helper 时仍需保留该 Node 的合法 Key 归属与当前扫描范围限制。不能用“广播属于网络中的某一 Node”就把 RSSI 更新给另一个按 MAC 找到的 Node。

## 已确认主因之外的发现与限制

- 记录中还有六段约 0.85～0.94 秒的卡顿，主要落在 `SiteDeviceOwnershipReconciler.provisioned → MeshNetwork.load`；另有清理/云同步卡顿。这些是独立的短卡顿，不是最长 48 秒的主要来源，建议另项处理，保持身份及恢复保护不变。
- 全程 `libRPAC.dylib` 路径有约 41.916 秒跨线程包含权重，其中最长 Hang 内只有 0.790 秒。它明显影响整段 CPU 总量，但不能替代主线程 RSSI 热点作为此次卡死解释。不凭库名推断具体 Xcode 诊断开关。
- 当前样本是带 `SunSmart.debug.dylib` 的构建。可以确认 Debug 现场根因，不能断言 Release 也会卡相同秒数。
- 热状态在相对 61.354 秒由 Nominal 变为 Fair，96.375 秒变为 Serious。长卡顿在 Nominal 时已开始，因此升温不是该次卡顿的起始解释，但后续性能比较需控制温度。
- 没有逐包日志，尚不清楚现场 Node Identity 包有多少来自新增六台、旧设备或附近其他网络，也无法从采样得出每次遍历的实际节点数。以上不影响确定共享扫描算法及其停止机制需要修复。

## 修复方案（2026-09-24 已获用户确认）

### A. SDK：修复 RSSI 共享入口

1. **候选 Node 提前筛选并定向认证。** 复用现有 MAC/旧 MAC 匹配，无法对应本地 Node 的包提前返回；对找到的 Node 校验当前扫描允许的 NetworkKey，复用 `NodeIdentity.matches(node:networkKey:)`，移除普通 RSSI 分支中的全网身份遍历。保留 Public/Private、Key Refresh 旧 Key、当前子网和 Gateway 授权 Key 范围语义。
2. **在同一扫描会话复用相同身份包的认证结果。** 缓存按实际身份数据、候选 Node 和有效 Key 上下文区分，不能仅按 Peripheral 或 MAC 放行。相同身份仍可更新最新 RSSI；身份随机数/Hash、节点、网络或 Key 状态变化必须重新验证。缓存有界，会话结束清空，拒绝结果同样不能跨失效边界复用。
3. **昂贵计算前检查会话和到期时间。** 复用现有 sessionID，增加单调时钟 deadline，在回调入口先拒绝过期/取消会话，并保障完成回调最多一次。保留定时结束，同时避免必须等主线程定时回调被调度才停止处理过期数据。
4. 增加少量 `#if DEBUG` 会话汇总：收到包数、候选数、实际身份验证次数、缓存命中、最慢一次处理时长、计划/实际结束时间。日志不输出密钥或完整身份数据，不逐包高频打印。

本轮不修改底层 AES 算法，不把可变 Mesh 对象直接丢到并发全局队列。先消除工作量的规模放大和重复；若后续相同条件 trace 仍显示单次定向认证超预算，再评估不可变快照下的后台处理。

### B. App：避免隐藏页面主动启动 RSSI 扫描

5. Lights 页面收到添加完成通知时仍保持必要的数据刷新；页面不可交互/被 Add Device 覆盖时，合并记录一次待刷新状态，不立即启动 RSSI 扫描。
6. 返回 Lights 页面且 Mesh 连接满足条件时消费待刷新状态；断开后重连也应能补刷，避免单纯加可见性 guard 造成永久丢失刷新。延后刷新不应抢占 Add Device 正在使用的扫描。

只改 App 入口会把 SDK 的同类问题留在其他 RSSI 页面；只改 SDK 则仍保留隐藏页面的不必要扫描。建议 A、B 一起作为本轮最小完整修复链。

### C. 验证与交付

- 优先扩展已有 `NodeIdentityNetworkKeyMatchTests`、`NodeRSSIRefreshSessionPolicyTests`、Gateway Key Scope 相关测试。验证合法 Public/Private/旧 Key、错 Key、错 Node、旧 MAC、未知节点、重复广告、身份改变、取消/超时/重启和结束一次的行为。
- 使用合成 120/126 Node 场景验证每个包不再全网尝试；统计真实验证调用数，不用源码字符串断言或 Time Profiler 样本数冒充调用次数。
- 验证隐藏页收到通知后延后扫描，返回/重连补刷一次，重复添加批次不积压；记录共享扫描的实际生命周期。
- 一轮生产代码修改完成后运行相关回归，并使用映射已核实的 `SunSmartLocal.xcworkspace` 做一次 SunSmart generic iOS Debug 无签名构建。分析共享 SDK 对五品牌的影响；若实施改变公共 API/依赖或引入跨品牌编译风险，再覆盖相应品牌构建。
- 用户在同一 iPhone XR、约 120 台背景规模、相同六台设备和相同模式复测：添加完成后按钮可响应，返回 Lights 后 RSSI/设备状态正常，重复扫描仍正常；再录制覆盖添加完成前及其后至少 20 秒的 Time Profiler。比较主线程身份验证权重、扫描实际结束时间及 Hangs。
- 若需要判断发布版体验，再用相同数据、温度及一致诊断配置补 Release/Profile 对照。自动化和构建结果不替代真机体验验收。
- SDK 修复应落在用户正在使用的 `one-dev`，实施前重新核对其改动及独占写入条件。记录修复 revision/差异与正式 `release` 依赖发布待办，不改绑正式工程的远端依赖。

## 是否还需要补充材料

**现在不需要再录一份 trace 才能制定或开始上述修复。** 用户已补齐原有设备规模、添加目标和最终恢复情况，现有证据链已完整到共享入口及算法层。

修复后若仍出现卡顿，再补同场景 trace 和新增会话汇总日志，说明构建版本、设备规模及卡住时刻。只有届时仍存在“认证次数为什么异常多”的疑问，才需要进一步记录脱敏的广告类型/重复次数；无需提供网络密钥。

## 分析阶段产物和验证边界

- 分析阶段仅新增本文，没有修改业务代码或 SDK；后续经用户确认的实施和验证见下节。全任务没有安装或操作真机。
- 离线导出与统计：`/tmp/add_pro_260924_toc.xml`、`/tmp/add_pro_260924_samples.xml`、`/tmp/add_pro_260924_hangs.xml`、`/tmp/add_pro_260924_thermal_single.xml`、`/tmp/add_pro_260924_symbolicated.json`、`/tmp/add_pro_260924_summary.json`。
- XML 解析脚本：`/tmp/analyze_add_pro_260924.py`。临时产物不代替原始 trace，后续可从原始记录重新导出。
- xctrace 多表导出曾失败；本次实际证据使用分别成功导出的 Time Profiler、Hangs、Thermal 表。工具导出错误不是 App 崩溃证据。


## 已实施修复与验证（2026-09-24）

### 实际改动

App：`SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`。

- `viewDidAppear` / `viewWillDisappear` 维护页面是否可交互，隐藏状态只保留一次待刷新请求；保留原有列表数据更新。
- 返回页面、蓝牙恢复/代理连接成功时按页面可见性与 Mesh 连接条件补刷；自动心跳开启不妨碍消费添加完成留下的待刷新请求。
- 设备添加入口已核对为导航 push，生命周期事件与本次延后刷新入口对应。

SDK 修改位于 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，基线仍为 `ebbe1c969381363487bfe6e371bae08e954f6f00`，修复保持未提交状态：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`：在普通 RSSI 路径按 MAC/旧 MAC 定位候选后，只认证该 Node 与当前 Key；未知 Node 提前拒绝。Gateway 授权范围继续沿用原策略。
- `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIIdentityCache.swift`：新增仅供 RSSI 使用的有界会话缓存（最多 256 项），保存成功和失败结果。缓存键包含 Node UUID/地址、Key index、当前/旧 Identity Key、Public/Private 类型、Hash 和 Random；身份或 Key 变化自然不能命中旧结果。MAC 仍不是认证凭据。
- `Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIRefreshSessionPolicy.swift`：在处理前和发布样本前校验 sessionID 与单调时钟 deadline。
- 主线程延时结束改为捕获会话身份的 `DispatchWorkItem`；取消/替换时旧回调不能结束新会话。共享扫描新增 generation 识别，RSSI 已被其他扫描接替时不会停止对方的扫描。
- 结束处理在调用客户端完成回调前清除旧状态，避免回调重入覆盖新会话。网络缺失失败路径同样先清除回调再通知。
- 移除逐样本 RSSI 打印，改为每会话一次 `#if DEBUG` 汇总：`[NodeRSSIRefresh]`，包括包数、候选数、认证次数、缓存命中、最慢处理、计划时长及实际时长；不输出密钥和完整身份数据。Gateway 原有按事件去重诊断保留。

没有修改底层 AES、公开 SDK API、依赖配置、国际化或资源。其他设备归属检查/数据加载造成的短卡顿保持原范围，未在本次扩大处理。

### 已执行验证

1. `bash .local-sdk/nordic-sig-mesh-sdk/scripts/check_node_rssi_refresh.sh`：通过。
   - 运行生产 `MeshLibManager` 的实际扫描/刷新方法及字段、生产 Node Identity 类型/校验方法和缓存；替换蓝牙、网络模型边界及时间，使用 CommonCrypto AES 作为夹具独立计算来源，不调用真实蓝牙。
   - 126 个合成 Node 中，同一合法身份连续接收 60 次只执行一次 Hash 认证，60 次 RSSI 更新均保留，最终值为最新值。
   - 验证未知 MAC/缺失身份在认证前拒绝，旧 MAC 定位、同网错 Node 拒绝及失败缓存、Public/Private Identity、Random 变化、Key 成员移除、Key Refresh 旧 Key 允许与旧 Key 撤销后拒绝。
   - 验证扫描到期前置拒绝、不再消耗认证、完成仅一次、旧回调/定时任务不能停止新会话、其他添加扫描接管后仍继续、切换网络、Gateway 允许/禁止 Key 范围、Network Identity 分支、有界淘汰/重置，以及完成回调重入。
   - 同时通过已有 `NodeRSSIRefreshSessionPolicyTests`（补充到期边界、错误会话结束、重复结束及零时长）、`NodeRSSIGatewayKeyScopePolicyTests`、`NodeRSSIScanDiagnosticPolicyTests` 和 `NodeRSSIScanDebugLoggerTests`。
2. `bash scripts/check_device_lights_state_refresh.sh`：通过。
   - 运行控制器实际的页面生命周期和状态刷新方法，UI/Mesh 使用边界替身；验证六次隐藏刷新合并、返回消费一次、隐藏蓝牙/代理回调不启动扫描、断开后返回保留请求、重连后补刷、窗口未挂载及正常可见手动刷新。
   - 这是方法级行为测试，不验证 UIKit 的真实外观/事件分发，也不是整页运行验收。
3. SunSmart generic iOS Debug 无签名构建：**BUILD SUCCEEDED**，2026-09-24 16:14。
   - workspace：`SunSmartLocal.xcworkspace`；scheme：`SunSmart`。
   - `-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。
   - DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-BL9105N-XXCCTXXE-260924`。
   - 构建输出确认 NordicSigMeshSDK 从当前工作树 `.local-sdk/nordic-sig-mesh-sdk` 解析，实际指向 `one-dev`。
   - 五品牌共享此次控制器和 SDK 实现，无新增品牌条件、公开 API 或依赖/资源变化；本轮使用代表 SunSmart 构建，没有宣称其余四品牌或 Release 已构建。
4. App / SDK `git diff --check`：通过。未提交、推送或发布。

### 未完成项与最短人工验收

- 用同等约 120 台规模的 Space，按 Professional Mode → Add based on light sensing 添加六台；确认完成后页面按钮和返回动作可用，没有再次持续 CPU 100%。
- 返回 Lights 页面，确认设备数量、状态及 RSSI 刷新正常；重复刷新/再次进入添加页面，确认旧扫描不会中断新的添加扫描。
- 如需性能验收，录制同设备同条件 trace，覆盖添加完成前及完成后、返回 Lights 后的扫描窗口；对照 `[NodeRSSIRefresh]` 汇总的实际时长、认证次数和缓存命中。自动化中的一次认证结果不能当作手机上的耗时改善实测。
- 正式依赖发布仍待处理：本地修复目前只存在于上述 `one-dev` 未提交差异，App 正式远端 `release` 配置未变。正式打包/集成前须将 SDK 修复按正常流程提交并发布到被引用的 release，再核对 App 解析 revision。不能只提交 App 控制器改动就认为共享 RSSI 根因已修复。
