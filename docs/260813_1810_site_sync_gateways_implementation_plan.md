# Site Sync gateways 实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 按任务和检查点实施本计划。仓库默认采用 Inline Execution；除非用户明确改变要求，否则不得分派 subagents。各步骤使用 checkbox（`- [ ]`）追踪。

**目标：** 实现 Site 的 Sync gateways 页面，使用户可以发现附近需要更新时区的 Gateway，逐台通过 BLE 写入完整日期时间和 Site timezone offset，并将已确认的 Node 变更安全地同步到云端。

**架构：** 页面使用不可变 `SyncGatewaysContext` 和纯状态模型作为唯一 UI 真值；独立扫描会话负责 RSSI、15 秒有效扫描时间及暂停/恢复，独立时间同步协调器负责串行 BLE 连接、显式 Time Set、typed Time Status 校验和退出后的迟到收敛。Device Synced 后立即更新 UI，并通过 generation-safe 的现有 `.syncGateway` 链路异步回写云端；一个页面批次最多静默刷新一次 Site 权威快照。

**技术栈：** Swift 5、UIKit、SnapKit、CoreBluetooth、NordicSigMeshSDK、SIG Mesh Time Model、现有 standalone `swiftc` tests、source contract tests、Xcode generic iPhoneOS builds。

## 全局约束

- 所有回复、计划、实现注释和新增文档默认使用简体中文；用户可见 UI 文案使用 English 与简体中文国际化。
- Target timezone 使用进入页面时已协调完成的 `app.site.timezone` 快照；不得在事务中改用 `TimeZone.current`。
- 每台 Gateway 必须通过一个完整 Time Set 同时更新当前 Date-Time 和 target timezone offset；不得只发送 Time Zone Set。
- Device Synced 真值是有效且 offset 匹配的 typed Time Status 加本地 Node 持久化成功；不等待云端响应。
- 云端固定复用 `.syncGateway(gateway:node:)` 和 `/sitespace/sapce/gateway/regist`；不改用 `/sitespace/sync/siteprops`。
- `gateway/regist` body 中的 `updateTimestamp` 在服务器无业务作用，只能作为客户端 dirty generation marker，不能用于推导 `SiteData.lastUpdate`。
- BLE 云上传失败不回退 Cell、不减少进度、不显示本页 BLE 失败 Toast。
- 同一时刻最多一台 Gateway 处于 Syncing；同步期间暂停实际 RSSI 扫描并冻结 15 秒计时。
- Back、完成的侧滑返回和 Done 必须 finish 页面任务；取消的侧滑返回不得误停任务。
- Toast 只复用与 Figma `399:10968` 一致的 `ToastStatusView` `.siteUpdate` 外观：`%@ sync failed. Try again.` 与 `%@ time zone updated.`。
- 不新增 Auth 信息，不记录 Node export、NetKey、AppKey、MQTT 凭据或其他敏感 payload。
- App 当前已通过 `XCLocalSwiftPackageReference` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`；实施时保留该本地依赖。
- App 与 SDK 是两个 Git 仓库；SDK 任务只提交 SDK 仓库，App 任务只提交 App 仓库。
- 新增 App Swift 文件必须加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 保留当前 worktree 中与本功能无关的改动，不顺手重构 Gateway OTA、全局 BLE/Proxy 或其他 Site 模块。
- iOS 构建只使用 generic iPhoneOS，不使用 Simulator，不用 shell 包装或重定向 `xcodebuild` 日志。

---

## 文件结构

### NordicSigMeshSDK 仓库

- Create: `Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift` — 将显式 Date 和固定 TimeZone 转换为 Mesh TAI seconds/subsecond。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift` — 增加显式 Date/TimeZone 的 Time Set factory，同时保留现有无参数 API。
- Create: `Tests/Standalone/ExplicitTimeSetInputTests.swift` — 不依赖 UIKit 的时间转换聚焦测试。

### SunSmart App 仓库

- Create: `SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift` — Owner/Editor/Visitor 的共享 Gateway 可见范围策略。
- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift` — 改为复用共享可见范围策略。
- Create: `SunSmart/Main/Site/Model/SyncGatewaysContext.swift` — Context、目标描述与本地 Gateway/Node runtime binding。
- Create: `SunSmart/Main/Site/Model/SyncGatewaysState.swift` — 纯 Device/Cloud/Proximity 状态和 Section 投影。
- Create: `SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift` — 扫描生命周期、active-scan elapsed 计算、Peripheral cache。
- Create: `SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift` — attempt 生命周期、Time Status 校验、持久化与迟到收敛。
- Create: `SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift` — 单调 dirty generation 与上传确认规则。
- Modify: `SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift` — 返回请求实际提交 generation 的 receipt。
- Modify: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` — generation-safe `.syncGateway` 循环及 per-handle completion。
- Create: `SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift` — 页面批次云状态与最多一次 Site refresh。
- Create: `SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift` — Site import 前后仅保护仍 dirty 的 Node timestamp/timezone。
- Create: `SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift` — Site time-zone 卡片和进度条。
- Create: `SunSmart/Main/Site/View/SyncGatewayCell.swift` — Gateway 图标、RSSI、No signal 和 action 状态。
- Create: `SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift` — On-site Alert、Section header、空态、attention、Bottom action bar。
- Modify: `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift` — 页面组装、状态渲染、交互、Toast 和 finish。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift` — 保存最新远端快照、统一两个入口、Context builder、静默 Site refresh 和 dirty retry。
- Modify: `SunSmart/en.lproj/Localizable.strings` — 新增 Sync gateways English 参数化文案。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings` — 新增对应简体中文文案。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 新文件加入四个 App target。
- Create: `Tests/Site/SyncGatewaysContextTests.swift` — Context 范围、顺序和 dirty override 测试。
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift` — Review policy 的 dirty local override 回归测试。
- Create: `Tests/Site/SyncGatewaysStateTests.swift` — Section、排序、进度、按钮互斥和状态转换测试。
- Create: `Tests/Site/SyncGatewaysScanSessionTests.swift` — active scan 计时与 session 隔离测试。
- Create: `Tests/Site/GatewayTimeSyncCoordinatorTests.swift` — attempt、Time Status 和退出语义测试。
- Create: `Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift` — generation 竞态测试。
- Create: `Tests/Site/SyncGatewaysCloudBridgeTests.swift` — 批次云收敛和单次 refresh 测试。
- Create: `Tests/Site/SyncGatewaysUIContractTests.swift` — Figma 结构、入口、生命周期、Toast、本地化和 target membership 契约。
- Create: `scripts/check_site_sync_gateways.sh` — 聚合全部 standalone/source contract 检查。

---

### Task 1: 共享 Gateway 权限范围与不可变 Context

**Files:**
- Create: `SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift`
- Create: `SunSmart/Main/Site/Model/SyncGatewaysContext.swift`
- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`
- Create: `Tests/Site/SyncGatewaysContextTests.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`

**Interfaces:**
- Consumes: `SiteEntryTimeZoneRemoteSnapshot`、`SiteEntrySpaceAccessSnapshot`、`SiteEntryGatewayTimeZoneSnapshot`、`SiteTimeZoneValue`、本地 GatewayModel/Node binding。
- Produces: `SiteGatewayAccessScope.resolve(remote:)`、`SyncGatewaysContextSelectionPolicy.select(...)`、`SyncGatewaysContext`、`SyncGatewayRuntimeTarget`。

- [ ] **Step 1: 写 Context 选择失败测试**

在 `SyncGatewaysContextTests.swift` 建立 `@main` 测试，覆盖：Owner 保持远端顺序；Editor 只选择 Editor Space 的 gatewayId；Visitor 返回空；远端已一致项排除；dirty local offset 等于 target 时排除；dirty local offset 不等时保留；无本地 binding 的远端项仍保留但 `isSyncable == false`；重复 MAC 只保留第一次出现顺序。同步扩充 `SiteEntryTimeZoneSyncPolicyTests.swift`，证明同一 dirty override 同时影响 entry decision 和 review pending count，避免两个入口口径分裂。

核心断言写成：

```swift
let targets = SyncGatewaysContextSelectionPolicy.select(
    scope: .owner,
    targetOffsetMinutes: 480,
    remote: [
        .init(id: "aa:bb", offsetMinutes: 0, order: 0),
        .init(id: "cc:dd", offsetMinutes: 480, order: 1),
        .init(id: "ee:ff", offsetMinutes: nil, order: 2)
    ],
    local: [
        "aa:bb": .init(displayName: "Gateway A", offsetMinutes: 480,
                        isCloudDirty: true, hasGatewayModel: true, hasNode: true)
    ]
)

precondition(targets.map(\.id) == ["ee:ff"])
precondition(targets[0].remoteOrder == 2)
precondition(targets[0].isSyncable == false)
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift Tests/Site/SyncGatewaysContextTests.swift -o /tmp/SyncGatewaysContextTests
```

Expected: FAIL，错误包含 `cannot find 'SyncGatewaysContextSelectionPolicy' in scope`。

- [ ] **Step 3: 实现共享权限策略和纯选择输入**

在 `SiteGatewayAccessScope.swift` 定义：

```swift
enum SiteGatewayAccessScope: Equatable {
    case owner
    case editor(Set<String>)
    case visitor

    static func resolve(remote: SiteEntryTimeZoneRemoteSnapshot) -> Self
    func contains(normalizedGatewayID: String) -> Bool
}
```

`resolve` 必须沿用当前 Review policy：Owner 全部；Editor 取 `spaces.filter { $0.role == .editor }` 的非空标准化 gatewayId；没有 Editor Space 时为 Visitor。将 `SiteEntryTimeZoneSyncPolicy` 的私有 `AccessScope` 删除并改用该类型，确保 Review count 与目标页使用同一权限真值。

同时给 `reviewState`、`decide` 和内部 `gatewaySummary` 增加默认值为空字典的 `localDirtyOffsetMinutesByGatewayID: [String: Int]` 输入。远端 Gateway 对应本地 dirty override 时，以该 offset 判断 pending；这样 App 重启或 Site 再次进入时，本地已经由有效 Time Status 确认且等待云上传的 Gateway 不会再次触发现场 BLE。现有调用点不传参数时保持原行为。

在 `SyncGatewaysContext.swift` 先放 Foundation-only 选择类型：

```swift
struct SyncGatewayRemoteCandidate: Equatable {
    let id: String?
    let offsetMinutes: Int?
    let order: Int
}

struct SyncGatewayLocalCandidate: Equatable {
    let displayName: String
    let offsetMinutes: Int?
    let isCloudDirty: Bool
    let hasGatewayModel: Bool
    let hasNode: Bool
}

struct SyncGatewayTargetDescriptor: Equatable {
    let id: String
    let displayName: String?
    let remoteOrder: Int
    let initialOffsetMinutes: Int?
    let isSyncable: Bool
}
```

选择规则使用标准化 MAC 去重；dirty local 使用 Node offset 覆盖远端 offset，clean local 仍以远端 snapshot 为任务真值；只返回 effective offset 不等于 target 的记录。

- [ ] **Step 4: 增加 runtime Context builder**

在同一文件的 `#if canImport(NordicSigMeshSDK)` 区域定义：

```swift
struct SyncGatewayRuntimeTarget {
    let descriptor: SyncGatewayTargetDescriptor
    let gateway: GatewayModel?
    let node: Node?
}

struct SyncGatewaysContext {
    let sessionID: UUID
    let siteID: String
    let siteName: String
    let targetTimeZone: SiteTimeZoneValue
    let targets: [SyncGatewayRuntimeTarget]
    let allowedNetworkKeyIndexesByNodeAddress: [UInt16: Set<UInt16>]
}
```

Builder 使用 `GatewayModel.load(siteId:)`、Site primary MeshNetwork 和标准化 MAC 建立 binding；Node offset 取 `node.timezone?.secondsFromGMT() / 60`。Key scope 复用现有 `GatewayFirmwareScanNetworkKeyScopePolicy`，每台可同步 Gateway 只允许 Primary 与自身 Associated Space keys，禁止把所有 Gateway keys 合并成全局集合。

- [ ] **Step 5: 运行 Context 与现有 Review policy 测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift SunSmart/Main/Site/Model/SyncGatewaysContext.swift Tests/Site/SyncGatewaysContextTests.swift -o /tmp/SyncGatewaysContextTests
/tmp/SyncGatewaysContextTests
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 两项分别输出 `SyncGatewaysContextTests passed` 和 `SiteEntryTimeZoneSyncPolicyTests passed`。

- [ ] **Step 6: 提交 App 变更**

```bash
git add SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SyncGatewaysContextTests.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift
git commit -m "feat: add sync gateways context"
```

---

### Task 2: Gateway 页面纯状态模型

**Files:**
- Create: `SunSmart/Main/Site/Model/SyncGatewaysState.swift`
- Create: `Tests/Site/SyncGatewaysStateTests.swift`

**Interfaces:**
- Consumes: `[SyncGatewayTargetDescriptor]` 和归一化 Gateway ID。
- Produces: `SyncGatewaysState`、`SyncGatewayItemState`、`nearbyItems`、`otherItems`、`progress`、`attentionCount` 以及事件方法。

- [ ] **Step 1: 写状态投影失败测试**

测试至少包含以下事件序列：

```swift
var state = SyncGatewaysState(targets: makeFourTargets())
precondition(state.nearbyItems.isEmpty)
precondition(state.otherItems.map(\.id) == ["a", "b", "c", "d"])

state.receiveAdvertisement(id: "b", rssi: -45)
state.receiveAdvertisement(id: "a", rssi: -60)
precondition(state.nearbyItems.map(\.id) == ["a", "b"])

let attempt = state.beginSync(id: "a")!
precondition(state.action(for: "b") == .disabledSync)
state.finishSync(id: "a", attemptID: attempt, result: .success)
precondition(state.progress == .init(updated: 1, total: 4))
precondition(state.otherItems.map(\.id) == ["c", "d", "a"])
```

另测 failed 保持 Retry、failed 丢信号进入 Other、重新发现回到 Nearby、syncing 在扫描暂停时仍固定 Nearby、旧 attempt 结果被忽略、cloud failed 不改变 Device 状态、attention 为 0 时消失。已 synced item 后续收到广播仍更新 RSSI；15 秒没有新广播时只把其信号行改为 No signal，Device 状态与 Synced 标签保持不变。

- [ ] **Step 2: 运行并确认类型不存在**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysState.swift Tests/Site/SyncGatewaysStateTests.swift -o /tmp/SyncGatewaysStateTests
```

Expected: FAIL，文件或 `SyncGatewaysState` 尚不存在。

- [ ] **Step 3: 实现最小状态类型**

```swift
enum SyncGatewayDeviceState: Equatable { case pending, syncing(UUID), failed, synced }
enum SyncGatewayCloudState: Equatable { case clean, pending, uploading, failed }
enum SyncGatewayAction: Equatable { case sync, syncing, retry, disabledSync, disabledRetry, synced, unavailable }

struct SyncGatewayItemState: Equatable {
    let id: String
    let displayName: String?
    let remoteOrder: Int
    let isSyncable: Bool
    var device: SyncGatewayDeviceState
    var cloud: SyncGatewayCloudState
    var rssi: Int?
    var activeMissingDuration: TimeInterval
    var isNoSignal: Bool
}
```

`SyncGatewaysState.advanceActiveScan(by:)` 只更新非 syncing items；达到 `15.0` 秒置 No signal。广告事件对 pending、failed 和 synced item 都更新 RSSI/重置 missing duration，但 synced 永远留在 Other。`otherItems` 先未 synced/no signal，再 synced，每组 `remoteOrder` 升序；`nearbyItems` 为未 synced 且有信号，外加当前 syncing item。信号状态与 Device 状态正交：synced item 失联只显示 No signal，不回退为 pending/failed，也不减少进度。

- [ ] **Step 4: 运行聚焦测试**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysState.swift Tests/Site/SyncGatewaysStateTests.swift -o /tmp/SyncGatewaysStateTests
/tmp/SyncGatewaysStateTests
```

Expected: `SyncGatewaysStateTests passed`。

- [ ] **Step 5: 提交状态模型**

```bash
git add SunSmart/Main/Site/Model/SyncGatewaysState.swift Tests/Site/SyncGatewaysStateTests.swift
git commit -m "feat: add sync gateways state model"
```

---

### Task 3: 页面拥有的 RSSI 扫描会话

**Files:**
- Create: `SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift`
- Create: `Tests/Site/SyncGatewaysScanSessionTests.swift`

**Interfaces:**
- Consumes: `SyncGatewaysContext.allowedNetworkKeyIndexesByNodeAddress`、`MeshLibManager.refreshNodesRSSI`、目标 Node address 映射。
- Produces: `start()`、`pause()`、`resume()`、`finish()`、`peripheral(for:)`、`onAdvertisement`、`onActiveElapsed`、`onAvailabilityFailure`。

- [ ] **Step 1: 写扫描生命周期 core 失败测试**

使用显式 monotonic 时间测试：

```swift
var core = SyncGatewaysScanSessionCore(sessionID: UUID())
core.resume(at: 10)
precondition(core.consumeElapsed(at: 14) == 4)
core.pause(at: 15)
precondition(core.consumeElapsed(at: 30) == 0)
core.resume(at: 40)
precondition(core.consumeElapsed(at: 43) == 3)
core.finish()
precondition(core.consumeElapsed(at: 50) == 0)
```

另测重复 pause/resume 幂等、旧 session callback 不被接受、finish 后不能恢复。

- [ ] **Step 2: 运行并确认失败**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift Tests/Site/SyncGatewaysScanSessionTests.swift -o /tmp/SyncGatewaysScanSessionTests
```

Expected: FAIL，文件或 core 类型不存在。

- [ ] **Step 3: 实现 Foundation-only core**

```swift
struct SyncGatewaysScanSessionCore {
    enum Phase { case idle, running(lastTick: TimeInterval), paused, finished }
    let sessionID: UUID
    private(set) var phase: Phase = .idle

    mutating func resume(at now: TimeInterval)
    mutating func pause(at now: TimeInterval)
    mutating func consumeElapsed(at now: TimeInterval) -> TimeInterval
    mutating func accepts(callbackSessionID: UUID) -> Bool
    mutating func finish()
}
```

计算只使用 `ProcessInfo.processInfo.systemUptime`，禁止使用墙钟 Date 计算 15 秒。

- [ ] **Step 4: 实现 SDK runtime adapter**

在 `#if canImport(CoreBluetooth) && canImport(NordicSigMeshSDK)` 中实现 `SyncGatewaysScanSession`：

- `start/resume` 调用 `refreshNodesRSSI(withWaitFor: 60, allowedNetworkKeyIndexesByNodeAddress: ...)`。
- 60 秒 finished 时，只有 phase 仍为 running 且 session ID 匹配才开始下一轮，实现持续扫描。
- `pause` 先把 core 置 paused，再调用 `stopRefreshNodesRSSI()`，防止 stop 触发的 finished 回调立即重启。
- `finish` 先置 finished、停止 timer、清空 Peripheral cache，再停止 SDK scan。
- 1 秒 main-queue timer 调用 `consumeElapsed` 并把 delta 交给状态模型。
- 扫描结果按 `node.primaryUnicastAddress` 映射 target ID，缓存 `CBPeripheral` 并回传整数 RSSI。
- Bluetooth 非 `.poweredOn` 时暂停实际扫描、停止 active elapsed，并通过 `onAvailabilityFailure` 通知 Controller。Controller 复用现有 `SRAlertView`、`bluetooth_required_title`、`bluetooth_required_message`、`settings` 和 `close` 文案组合，不新增另一套蓝牙提示语；Bluetooth 恢复为 `.poweredOn` 且页面 session 仍有效时关闭提示并 `resume()`。

- [ ] **Step 5: 运行扫描 core 测试**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift Tests/Site/SyncGatewaysScanSessionTests.swift -o /tmp/SyncGatewaysScanSessionTests
/tmp/SyncGatewaysScanSessionTests
```

Expected: `SyncGatewaysScanSessionTests passed`。

- [ ] **Step 6: 提交扫描会话**

```bash
git add SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift Tests/Site/SyncGatewaysScanSessionTests.swift
git commit -m "feat: add sync gateways scan session"
```

---

### Task 4: SDK 显式 Date 与 target offset 的 Time Set

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/ExplicitTimeSetInputTests.swift`

**Interfaces:**
- Consumes: Foundation `Date`、fixed-offset `TimeZone`、现有 `TaiTime` 与 `TimeSet`。
- Produces: `ExplicitTimeSetInput.make(date:timeZone:)` 和 `Node.setLocalTimeMessage(date:timeZone:) -> TimeSet`；现有 `Node.setLocalTimeMessage()` 保持兼容。

- [ ] **Step 1: 写时间转换失败测试**

```swift
let date = Date(timeIntervalSince1970: 946_684_800 + 123.5)
let zone = TimeZone(secondsFromGMT: 8 * 3_600)!
let input = ExplicitTimeSetInput.make(date: date, timeZone: zone)

precondition(input.seconds == 123)
precondition(input.subSecond == 128)
precondition(input.timeZone.secondsFromGMT() == 28_800)
```

另测 UTC-03:30、整秒 subsecond 为 0，以及 2000-01-01 前 Date 触发明确 precondition failure 的边界不进入生产调用。

- [ ] **Step 2: 运行并确认失败**

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift Tests/Standalone/ExplicitTimeSetInputTests.swift -o /tmp/ExplicitTimeSetInputTests
```

Expected: FAIL，源文件或类型不存在。

- [ ] **Step 3: 实现纯时间输入**

```swift
public struct ExplicitTimeSetInput: Equatable {
    public let seconds: UInt64
    public let subSecond: UInt8
    public let timeZone: TimeZone

    public static func make(date: Date, timeZone: TimeZone) -> Self {
        let taiInterval = date.timeIntervalSince1970 - 946_684_800
        precondition(taiInterval >= 0, "Mesh TAI time must not precede 2000-01-01")
        let wholeSeconds = floor(taiInterval)
        let subSecond = UInt8((taiInterval - wholeSeconds) * 256)
        return .init(seconds: UInt64(wholeSeconds), subSecond: subSecond, timeZone: timeZone)
    }
}
```

- [ ] **Step 4: 增加 Node overload 并保留旧行为**

```swift
static func setLocalTimeMessage(date: Date, timeZone: TimeZone) -> TimeSet {
    let input = ExplicitTimeSetInput.make(date: date, timeZone: timeZone)
    return TimeSet(time: TaiTime(
        seconds: input.seconds,
        subSecond: input.subSecond,
        uncertainty: 0,
        authority: false,
        taiDelta: 0,
        tzOffset: input.timeZone
    ))
}

static func setLocalTimeMessage() -> TimeSet {
    setLocalTimeMessage(date: Date(), timeZone: .current)
}
```

现有 `MeshAPI.syncNodeTime` 与 WiFi Gateway 流程继续调用无参数 API，不改变其语义。

- [ ] **Step 5: 运行 SDK 聚焦测试与 iPhoneOS build**

```bash
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift Tests/Standalone/ExplicitTimeSetInputTests.swift -o /tmp/ExplicitTimeSetInputTests
/tmp/ExplicitTimeSetInputTests
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 聚焦测试输出 `ExplicitTimeSetInputTests passed`，Demo 显示 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 在 SDK 仓库提交**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift Tests/Standalone/ExplicitTimeSetInputTests.swift
git commit -m "feat: add explicit time set input"
```

---

### Task 5: 单 Gateway Time Sync attempt 协调器

**Files:**
- Create: `SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift`
- Create: `Tests/Site/GatewayTimeSyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `SyncGatewayRuntimeTarget`、`CBPeripheral`、Context target offset、SDK explicit Time Set、`MeshAPI.sendMessage`。
- Produces: `GatewayTimeSyncAttemptCore`、`GatewayTimeStatusSnapshot`、`GatewayTimeSyncOutcome`、`GatewayTimeSyncCoordinator.synchronize(...)` 和 `finishPage()`。

- [ ] **Step 1: 写 attempt 与 Status 校验失败测试**

测试纯 core：一次只允许一个 attempt；连接成功前退出为 cancelled-before-send；sent 后页面退出转 detached；有效非零 seconds 且 offset 匹配为 success；offset mismatch、zero time、timeout 为 failed；终态后迟到 Status 忽略；旧 attempt ID 不能结束新 Retry。

```swift
var core = GatewayTimeSyncAttemptCore(pageSessionID: pageID)
let attemptID = core.begin(gatewayID: "a")!
precondition(core.markSent(attemptID: attemptID))
core.detachPage()
let decision = core.receive(
    attemptID: attemptID,
    status: .init(seconds: 100, offsetMinutes: 480),
    targetOffsetMinutes: 480
)
precondition(decision == .success(renderUI: false))
```

- [ ] **Step 2: 运行并确认失败**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift Tests/Site/GatewayTimeSyncCoordinatorTests.swift -o /tmp/GatewayTimeSyncCoordinatorTests
```

Expected: FAIL，协调器类型不存在。

- [ ] **Step 3: 实现纯 attempt core**

定义明确 phase：

```swift
enum GatewayTimeSyncAttemptPhase: Equatable {
    case connecting, sent, detachedAfterSend, finished
}

struct GatewayTimeStatusSnapshot: Equatable {
    let seconds: UInt64
    let offsetMinutes: Int
}

enum GatewayTimeSyncDecision: Equatable {
    case success(renderUI: Bool)
    case failure(renderUI: Bool)
    case cancelledBeforeSend
    case ignored
}
```

`receive` 必须要求 `seconds > 0` 且 `offsetMinutes == targetOffsetMinutes`。`detachPage` 在 connecting 阶段取消，在 sent 阶段保留 attempt 但令 `renderUI == false`。

- [ ] **Step 4: 实现 runtime transport 和 coordinator**

Runtime 流程固定为：

```swift
scanSession.pause()
MeshLibManager.manager.connectProxy(node: target.node, peripheral: peripheral) { connected in
    // connected 且 attempt 仍为 connecting 时，使用 Date() + fixed target TimeZone 构造 Time Set
    // markSent 后调用 MeshAPI.sendMessage(..., timeout: 10)
    // 只接受 TimeStatus，并转换 seconds / tzOffset.secondsFromGMT()/60
}
```

成功后显式写入 `node.timestamp`、`node.timezone` 并要求 `node.savePropertys() == true`；持久化失败按 Device failure 处理。协调器提供两个闭包：

```swift
var onPersistedSuccess: ((SyncGatewayRuntimeTarget) -> Void)?
var onUISettlement: ((String, UUID, Result<Void, GatewayTimeSyncError>) -> Void)?
```

sent 后 callback 必须强持有协调器直到 SDK 10 秒 timeout 收敛，保证页面释放后仍能执行 `onPersistedSuccess`；UI closure 只能在 core 返回 `renderUI == true` 时调用。事务终态断开本页主动连接，并通过 closure 通知 Controller 恢复扫描；页面已 finish 时不恢复。

- [ ] **Step 5: 运行协调器 core 测试**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift Tests/Site/GatewayTimeSyncCoordinatorTests.swift -o /tmp/GatewayTimeSyncCoordinatorTests
/tmp/GatewayTimeSyncCoordinatorTests
```

Expected: `GatewayTimeSyncCoordinatorTests passed`。

- [ ] **Step 6: 提交协调器**

```bash
git add SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift Tests/Site/GatewayTimeSyncCoordinatorTests.swift
git commit -m "feat: add gateway time sync coordinator"
```

---

### Task 6: Generation-safe 的现有 `.syncGateway` 链路

**Files:**
- Create: `SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift`
- Modify: `SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift`
- Modify: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
- Create: `Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift`

**Interfaces:**
- Consumes: `GatewayModel.lastUpdate`、`lastUploadCloudTimestamp`、现有 `.syncGateway` operation。
- Produces: `GatewayCloudSyncGenerationPolicy`、`GatewayServerAuthorizationReceipt`、generation-safe gateway handle completion。

- [ ] **Step 1: 写 generation 失败测试**

```swift
precondition(GatewayCloudSyncGenerationPolicy.next(now: 100, current: 100, uploaded: 100) == 101)
precondition(GatewayCloudSyncGenerationPolicy.confirmed(previous: 80, submitted: 90) == 90)
precondition(GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 101, confirmed: 100))
precondition(!GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 100, confirmed: 100))
```

另测旧 submitted 不能降低 uploaded、服务器无视 updateTimestamp 不影响客户端 generation 判断。

- [ ] **Step 2: 运行并确认失败**

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift -o /tmp/GatewayCloudSyncGenerationPolicyTests
```

Expected: FAIL，策略类型不存在。

- [ ] **Step 3: 实现纯 generation 策略**

```swift
enum GatewayCloudSyncGenerationPolicy {
    static func next(now: Int64, current: Int64, uploaded: Int64?) -> Int64 {
        max(now, current + 1, (uploaded ?? 0) + 1)
    }

    static func confirmed(previous: Int64?, submitted: Int64) -> Int64 {
        max(previous ?? 0, submitted)
    }

    static func needsAnotherUpload(current: Int64, confirmed: Int64?) -> Bool {
        current > (confirmed ?? 0)
    }
}
```

- [ ] **Step 4: 给 Authorization 增加 receipt，但保留旧 API**

```swift
struct GatewayServerAuthorizationReceipt {
    let information: GatewayInformation.MQTTConnectInformation
    let submittedGeneration: Int64
}
```

新增 `authorizeWithReceipt(gateway:node:policy:requestedGeneration:)`；新建 in-flight task 时捕获 `requestedGeneration` 和本次 Node export，响应成功返回相同 generation。现有 `authorize(...)` 调用新方法并只映射 `information`，因此 Device Add 和 SyncDevices 调用点不需要改变。

同 Gateway 新调用若 join 旧 in-flight task，必须收到旧 task 的真实 `submittedGeneration`，不能伪装成新 generation。

- [ ] **Step 5: 让 `.syncGateway` handle 循环到当前 generation clean**

在 `CloudSynchronizationHandle.syncOperation()` 的 Gateway 分支中：

1. 捕获 `requestedGeneration = gateway.lastUpdate`。
2. 调用 `authorizeWithReceipt(...requestedGeneration:)`。
3. 成功后只把 `lastUploadCloudTimestamp` 推进到 receipt 的 `submittedGeneration`。
4. 保存后若 `gateway.lastUpdate > lastUploadCloudTimestamp`，继续下一轮 authorize。
5. 只有当前 generation 已 clean 才发布 `.successful`；任一网络/服务错误发布 `.failure` 并保留 dirty。
6. 每轮检查 Task cancellation，旧 handle 不能在取消后更新状态。

给 `CloudSynchronizationManager.addSynchronizationHandle` 增加可选 per-handle callback 并返回 handle：

```swift
@discardableResult
func addSynchronizationHandle(
    operation: SyncOperation,
    level: SyncLevel,
    result: ((CloudSynchronizationState) -> Void)? = nil
) -> CloudSynchronizationHandle
```

Manager 继续通知现有单 delegate，同时调用本次 result；不允许页面抢占全局 delegate。

- [ ] **Step 6: 运行 generation 测试与 source contract**

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift -o /tmp/GatewayCloudSyncGenerationPolicyTests
/tmp/GatewayCloudSyncGenerationPolicyTests
git diff --check -- SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift
```

Expected: `GatewayCloudSyncGenerationPolicyTests passed`，diff check 无输出。

- [ ] **Step 7: 提交云同步基础修正**

```bash
git add SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift
git commit -m "fix: preserve gateway cloud generations"
```

---

### Task 7: 页面 Cloud Bridge、dirty retry 与单次 Site snapshot

**Files:**
- Create: `SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift`
- Create: `SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift`
- Create: `Tests/Site/SyncGatewaysCloudBridgeTests.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`

**Interfaces:**
- Consumes: generation-safe `CloudSynchronizationManager.addSynchronizationHandle`、Gateway runtime target、异步 silent Site refresh closure。
- Produces: `recordDeviceSuccessAndEnqueue(_:)`、`retryDirty(_:)`、`finishBatchIfNeeded()`、每 Gateway cloud state callback、最多一次 refresh，以及 Site import 前后 dirty Node 时间值保护。

- [ ] **Step 1: 写 batch reducer 失败测试**

```swift
var batch = SyncGatewaysCloudBatchState()
batch.register(gatewayID: "a")
batch.register(gatewayID: "b")
precondition(!batch.settle(gatewayID: "a"))
precondition(batch.settle(gatewayID: "b"))
precondition(!batch.settle(gatewayID: "b"))
```

测试同 Gateway/同 generation 重复 enqueue 不增加 pending count、success/failure 都算 batch terminal、refresh 只发一次、新批次可再次 refresh；另以注入的 generation closure 证明 `recordDeviceSuccessAndEnqueue` 推进一次，而任意次数 `retryDirty` 都不推进。

同时为 `SyncGatewaysDirtyTimeOverridePolicy` 增加纯值测试：只有 GatewayModel 仍 dirty、本地 Node offset 已等于 target、远端 offset 仍不等于 target 时才捕获；clean Gateway、无有效 timestamp/timezone、目标已变化或远端已经收敛时均不保护。

- [ ] **Step 2: 运行并确认失败**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift Tests/Site/SyncGatewaysCloudBridgeTests.swift -o /tmp/SyncGatewaysCloudBridgeTests
```

Expected: FAIL，bridge/core 类型不存在。

- [ ] **Step 3: 实现 batch core 与 runtime bridge**

`recordDeviceSuccessAndEnqueue(target:)` 表示新的 BLE 确认属性变更：先使用 `GatewayCloudSyncGenerationPolicy.next` 推进并保存 GatewayModel，再发送 `.syncGateway(gateway:node:)`。`retryDirty(target:)` 仅在 `gateway.needUploadCloud == true` 时发送当前 generation，不推进 `lastUpdate`。两者共用按标准化 Gateway ID/generation 去重的内部 enqueue；同一 generation 重复调用不得新增 handle，更新 generation 则由 Task 6 的 handle 循环带上最新 payload。per-handle callback 映射为 `.uploading/.clean/.failed`，不得触碰 Device state。

所有本批 handle 进入 success/failure terminal 后执行：

```swift
if batchState.shouldRefreshAfterSettlement {
    await refreshSiteSnapshot()
}
```

页面退出不取消已入队云请求；bridge 不持有 ViewController，只持有 silent refresh closure 和弱 UI state callback。

- [ ] **Step 4: 在 Site 页面增加 silent refresh 与 dirty retry**

将现有 `@objc loadSiteRequest()` 保留为无参数入口，并把实际请求提取为：

```swift
private enum SiteLoadPresentation { case interactive, silentGatewayReconcile }
private func loadSiteRequest(presentation: SiteLoadPresentation)
```

`.interactive` 保持 HUD、Entry overlay 和现有导航行为；`.silentGatewayReconcile` 不显示 HUD、不重放 Entry overlay，但仍 parse remote snapshot、`await site.update`、`setupData` 和 `applyTimeZoneReviewState`。

每次成功 parse Site 响应后、调用 `await site.update(siteJsonData:)` 前，使用当前 primary MeshNetwork 捕获需要保护的本地值：GatewayModel `needUploadCloud == true`、Node 有有效 `timestamp/timezone`、本地 offset 等于本次 Site target，且远端同 Gateway offset 尚未收敛。快照至少包含标准化 MAC、`timestamp` 和 fixed-offset `TimeZone`；不得捕获其他 Node 属性。

`site.update` 返回后重新按标准化 MAC 在当前 primary MeshNetwork 找 Node。若对应 GatewayModel 仍 dirty 且 Site target 未变化，则恢复捕获的 `node.timestamp`、`node.timezone` 并调用 `node.savePropertys()`；否则接受远端导入值。这样 `ImportData.swift` 现有无条件赋值无需修改，也不会让旧云端快照把已由有效 Time Status 确认的本地值覆盖。

同一批 dirty offset 字典传给 `SiteEntryTimeZoneSyncPolicy.reviewState/decide`；页面 Context builder 也使用它。因此 BLE 已成功但云未收敛的 Gateway 不重新计入 pending，云端收敛并令 GatewayModel clean 后则恢复以远端 snapshot 为权威。

在 `viewWillAppear` 完成 `setupData()` 后，以及 `networkableObservation` 从 false 变 true 时，对 `gatewayModels.filter(\.model.needUploadCloud)` 调用 `retryDirty`。依旧只同步每个 Gateway 自己的 Node，不触发整 Site upload，也不推进新的 generation。

- [ ] **Step 5: 运行 bridge 测试**

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift Tests/Site/SyncGatewaysCloudBridgeTests.swift -o /tmp/SyncGatewaysCloudBridgeTests
/tmp/SyncGatewaysCloudBridgeTests
```

Expected: `SyncGatewaysCloudBridgeTests passed`。

- [ ] **Step 6: 提交 Cloud Bridge**

```bash
git add SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift Tests/Site/SyncGatewaysCloudBridgeTests.swift SunSmart/Main/Site/Controller/SiteViewController.swift
git commit -m "feat: reconcile sync gateway cloud state"
```

---

### Task 8: Figma 页面组件与国际化

**Files:**
- Create: `SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift`
- Create: `SunSmart/Main/Site/View/SyncGatewayCell.swift`
- Create: `SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/Site/SyncGatewaysUIContractTests.swift`

**Interfaces:**
- Consumes: `SyncGatewaysState` 的只读 projection。
- Produces: `SyncGatewaysTimeZoneCardView.update(...)`、`SyncGatewayCell.update(...)`、supporting views 和完整参数化文案。

- [ ] **Step 1: 写 UI/localization source contract 失败测试**

创建读取三个 View 文件、Controller、本地化和 project 的 `@main` contract，先约束以下 Key 在两种语言中各出现一次且被消费：

```swift
let keys = [
    "site_sync_gateways_timezone_title_format",
    "site_sync_gateways_progress_format",
    "site_sync_gateways_gateway_fallback",
    "site_sync_gateways_onsite_title",
    "site_sync_gateways_onsite_message",
    "site_sync_gateways_nearby_title",
    "site_sync_gateways_nearby_empty",
    "site_sync_gateways_other_title",
    "site_sync_gateways_attention_single",
    "site_sync_gateways_attention_multiple",
    "site_sync_gateways_sync",
    "site_sync_gateways_syncing",
    "site_sync_gateways_retry",
    "site_sync_gateways_synced",
    "site_sync_gateways_no_signal",
    "site_sync_gateways_done",
    "site_sync_gateways_failure_toast",
    "site_sync_gateways_success_toast"
]
```

Contract 同时检查 View 使用 `time-zone-sync-status-gateway`、`gateway_sync_fail`、`site_entry_sync_loading`、`site_entry_sync_warning` 和 `ToastStatusView.Appearance.siteUpdate`。

- [ ] **Step 2: 运行并确认失败**

```bash
swiftc -parse-as-library Tests/Site/SyncGatewaysUIContractTests.swift -o /tmp/SyncGatewaysUIContractTests
/tmp/SyncGatewaysUIContractTests SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift SunSmart/Main/Site/View/SyncGatewayCell.swift SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected: FAIL，提示 View 文件或 localization keys 缺失。

- [ ] **Step 3: 添加精确文案**

English：

```text
%@ time zone
%d of %d updated
Gateway %d
On-site sync required
Move near each gateway with your phone. Only gateways with a nearby connection can be updated.
Nearby gateways
No more gateways are currently nearby. Move closer and rescan.
Other gateways
1 gateway still needs attention. You can finish now and continue when you are near another gateway.
%d gateways still need attention. You can finish now and continue when you are near another gateway.
Sync / Syncing / Retry / Synced / No signal / Done
%@ sync failed. Try again.
%@ time zone updated.
```

简体中文使用完整参数化句子：`%@ 时区`、`已更新 %d/%d`、`网关 %d`、`需要现场同步`、`请携带手机靠近每个网关。只有能在附近建立连接的网关才能更新。`、`附近的网关`、`附近暂未发现更多网关，请靠近网关后继续等待扫描。`、`其他网关`、单复数 attention 的自然中文、`同步/同步中/重试/已同步/无信号/完成`、`%@ 同步失败，请重试。`、`%@ 时区已更新。`。

- [ ] **Step 4: 实现 Time-zone card 和 Alert**

按 Figma `399:10732`：页面内容背景 `#F6F7FB`，水平 inset 16；卡片白色、corner radius 16、content inset 16；Site title 14pt `#657898`；offset 20pt `#1B1425`；progress 14pt `#64748B`；track 高 4、`#E5E8F0`，fill `#6864B3`。

Alert top spacing 16、背景 `#FFF9EF`、corner radius 16、horizontal 16 / vertical 12；warning icon 20；title 14pt `#75521F`；body 12pt `#64748B`、line height 20。

- [ ] **Step 5: 实现 Gateway Cell 和 Sections**

Cell 高 60、白色、corner radius 10、horizontal 16 / vertical 8；gateway icon 30；name 15pt `#1E2329`；RSSI 12pt `#9AABC2`；Sync/Syncing/Retry action 为 64×30、radius 15、0.5 border `#6667AB`。failed 使用 `gateway_sync_fail`，正常/同步完成使用 `time-zone-sync-status-gateway`；未同步的 No signal 不显示可点击 action。

Synced 按 Figma `399:11270` 使用 64×24 的只读状态标签：背景 `rgba(100,116,139,0.1)`、radius 15、文字 12pt `#94A3B8`；其 RSSI 行继续响应广告更新，15 秒无广告时仅改为 No signal，Synced 标签和进度不变。

Nearby/Other header 14pt `#1E2329`，Nearby 右侧 24pt `site_entry_sync_loading` 持续旋转。Nearby cell 间距 16；空态和 attention 使用居中 12pt `#94A3B8`、line height 20。Bottom action bar 高 90、白色、顶部 0.5 分隔线；Done 16pt `#1E2329`。

- [ ] **Step 6: 运行 UI contract**

重复 Step 2 命令。Expected: `SyncGatewaysUIContractTests passed`。

- [ ] **Step 7: 提交 UI 组件**

```bash
git add SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift SunSmart/Main/Site/View/SyncGatewayCell.swift SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings Tests/Site/SyncGatewaysUIContractTests.swift
git commit -m "feat: add sync gateways views"
```

---

### Task 9: Controller、统一入口与页面生命周期

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`
- Modify: `Tests/Site/SyncGatewaysUIContractTests.swift`

**Interfaces:**
- Consumes: Context、State、ScanSession、TimeSyncCoordinator、CloudBridge 和 Task 8 Views。
- Produces: 两个入口的统一 router、完整页面渲染、Sync/Retry、Toast、Done/Back/interactive-pop/background finish。

- [ ] **Step 1: 扩充入口与生命周期失败 contract**

约束：

- `handleEntrySyncReview()` 必须先 `finishEntrySyncOverlay()` 再 `showSyncGatewaysPage()`。
- Banner 与 overlay 都调用唯一 `showSyncGatewaysPage()`。
- Site controller 保存 `latestTimeZoneRemoteSnapshot`，router 使用同一 Context builder。
- Controller 只能由 `init(context:cloudBridge:canStartSync:)` 创建，禁止无参数 init。
- Done、custom Back 调用同一 `finish(reason:)`。
- interactive pop 使用 transition coordinator 的 interaction change，只在 `isCancelled == false` 时 finish。
- 使用 `UIApplication.didEnterBackgroundNotification` 暂停 scan；未发送 attempt 进入 failed；使用 `UIApplication.willEnterForegroundNotification` 在 session 有效且 Bluetooth 可用时 resume。
- Toast 明确使用 `.siteUpdate`、`.bottom` 和动态 Gateway name。

- [ ] **Step 2: 运行三个 contract 并确认失败**

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
/tmp/SyncGatewaysUIContractTests SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift SunSmart/Main/Site/View/SyncGatewayCell.swift SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected: 至少入口和 Controller lifecycle 新断言失败。

- [ ] **Step 3: Site controller 保存快照并统一路由**

在每次成功 parse 后保存 `latestTimeZoneRemoteSnapshot`。`showSyncGatewaysPage()`：

1. guard Site 当前 timezone 与 remote/current server timezone 一致。
2. 使用当前 primary mesh network、本地 GatewayModel 和 remote snapshot 创建 Context。
3. Context 无目标时更新 Review state 为 hidden，不 push。
4. 创建 Cloud Bridge，silent refresh closure 调用 `.silentGatewayReconcile`。
5. 注入 `canStartSync(target:)` closure：先比较 `SiteTimeZoneValue(storageValue: site.timezone)` 与 Context target，再用当前本地 Site/Space/Gateway 重新解析 `SiteGatewayAccessScope`，确认该 Gateway 仍在可见范围且仍有 GatewayModel/Node binding。
6. `pushViewController(SyncGatewaysViewController(context:..., cloudBridge:..., canStartSync:...), animated: true)`。

`handleEntrySyncReview()` 必须完成 overlay 清理后调用该 router；Banner 保持调用同一 router。

- [ ] **Step 4: 组装 Controller 与单向渲染**

Controller 使用 `UIScrollView + vertical UIStackView` 展示卡片、Alert、Nearby 和 Other，Bottom bar 固定于 safe area；状态变化统一走：

```swift
private func mutateState(_ mutation: (inout SyncGatewaysState) -> Void) {
    guard !isFinished else { return }
    mutation(&state)
    render(state)
}
```

`render` 重建小规模 Gateway rows 或复用按 ID 缓存的 Cell，但不得分别维护 Nearby/Other 数组。Sync/Retry 从 `scanSession.peripheral(for:)` 取 Peripheral，调用 `state.beginSync` 后 pause scan，并发起 coordinator。

协调器的 `onPersistedSuccess` 是 `CloudBridge.recordDeviceSuccessAndEnqueue` 的唯一入口，保证页面退出后的迟到成功仍会上传且每次 BLE 成功只推进一次 generation；可见页面收到 success settlement 时只把状态改为 synced 并显示成功 Toast，不得再次 enqueue。失败 settlement 把状态改为 failed 并显示失败 Toast。Cloud callback 只更新 cloud axis。

每次 Sync/Retry 在 `state.beginSync` 之前调用 `canStartSync(target)`；返回 false 时 finish 当前任务、pop 回 Site 并触发 silent reconcile，不允许对旧 target offset、已移出 Gateway 或已失效权限发起连接。服务器在页面快照之后发生但 App 尚未获知的权限变化，仍由接口拒绝和下一次权威 refresh 收敛。

- [ ] **Step 5: 实现 finish 与后台语义**

```swift
private func finish(reason: SyncGatewaysFinishReason) {
    guard !isFinished else { return }
    isFinished = true
    scanSession.finish()
    timeSyncCoordinator.finishPage()
    stopSearchingAnimation()
    removeLifecycleObservers()
}
```

Custom Back 和 Done 先 finish 再 pop。Interactive pop 在 `viewWillDisappear` 获取 transition coordinator；非交互式且 `isMovingFromParent` 立即 finish，交互式只在 interaction change 的 context 未取消时 finish。进入后台调用 scan pause 和 coordinator background handling，不把扫描暂停时间计入 15 秒。

- [ ] **Step 6: 实现 Toast 与动作状态**

```swift
let key = success
    ? "site_sync_gateways_success_toast"
    : "site_sync_gateways_failure_toast"
ToastStatusView.show(
    in: view,
    message: String(format: key.localizedString, gatewayName),
    type: success ? .success : .failure,
    appearance: .siteUpdate,
    position: .bottom
)
```

同步期间其他 action 使用 disabled 外观；Done 始终 enabled。Cloud failure 不走上述 Toast。

- [ ] **Step 7: 运行入口/UI contract**

重复 Step 2 三组命令。Expected: 三项分别输出 `passed`。

- [ ] **Step 8: 提交 Controller 集成**

```bash
git add SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteEntryTimeZoneSyncContractTests.swift Tests/Site/SiteTimeZoneReviewSyncContractTests.swift Tests/Site/SyncGatewaysUIContractTests.swift
git commit -m "feat: integrate sync gateways flow"
```

---

### Task 10: 四 target 接线与聚合验证脚本

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `Tests/Site/SyncGatewaysUIContractTests.swift`
- Create: `scripts/check_site_sync_gateways.sh`

**Interfaces:**
- Consumes: Tasks 1–9 的全部 App source/tests。
- Produces: 四 target membership 契约和一个可重复的 focused verification 命令。

- [ ] **Step 1: 让 target membership contract 先失败**

在 UI contract 中列出所有新增 App Swift 文件，并检查每个 `PBXFileReference` 存在、每个文件分别出现在四个 target 的 Sources phase。不能只检查全局出现次数。

- [ ] **Step 2: 运行 UI contract 并确认 project membership 失败**

重复 Task 8 Step 2 命令。Expected: FAIL，指出新增 Swift 文件尚未属于四个 target。

- [ ] **Step 3: 将新增文件加入四个 target**

编辑 `project.pbxproj`，给 Tasks 1–9 的每个新增 App source 创建单一 FileReference，并为四个 target 各创建 BuildFile/Sources entry。Tests 与 scripts 不加入 App target。保持现有本地 Nordic package reference 不变。

- [ ] **Step 4: 创建聚合脚本**

`scripts/check_site_sync_gateways.sh` 必须使用 `set -euo pipefail`，从 repo root 依次编译/运行：

1. `SyncGatewaysContextTests`
2. `SiteEntryTimeZoneSyncPolicyTests`
3. `SyncGatewaysStateTests`
4. `SyncGatewaysScanSessionTests`
5. `GatewayTimeSyncCoordinatorTests`
6. `GatewayCloudSyncGenerationPolicyTests`
7. `SyncGatewaysCloudBridgeTests`
8. `SiteEntryTimeZoneSyncContractTests`
9. `SiteTimeZoneReviewSyncContractTests`
10. `SyncGatewaysUIContractTests`
11. 现有 `SiteTimeZoneUIContractTests` 的 routing 与 localization 两种 invocation。

脚本只写 `/tmp/SyncGateways*` binaries，不修改 repo 内容；任一失败立即非零退出，全部通过输出 `SiteSyncGateways checks passed`。

- [ ] **Step 5: 运行聚合脚本与 diff check**

```bash
chmod +x scripts/check_site_sync_gateways.sh
scripts/check_site_sync_gateways.sh
git diff --check
```

Expected: `SiteSyncGateways checks passed`，diff check 无输出。

- [ ] **Step 6: 提交工程接线与脚本**

```bash
git add SunSmart.xcodeproj/project.pbxproj Tests/Site/SyncGatewaysUIContractTests.swift scripts/check_site_sync_gateways.sh
git commit -m "test: add sync gateways verification"
```

---

### Task 11: App/SDK 静态回归与四品牌 iPhoneOS 构建

**Files:**
- Verify: Tasks 1–10 的所有文件
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

**Interfaces:**
- Consumes: 完整实现与两个仓库的提交。
- Produces: 可审查的静态、构建与待真机/服务器验收结果；不把构建成功描述为端到端成功。

- [ ] **Step 1: 运行 SDK focused test 和 Demo build**

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/ExplicitTimeSetInput.swift Tests/Standalone/ExplicitTimeSetInputTests.swift -o /tmp/ExplicitTimeSetInputTests
/tmp/ExplicitTimeSetInputTests
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: focused test passed，Demo `** BUILD SUCCEEDED **`。

- [ ] **Step 2: 运行 App focused tests**

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/time-zone
scripts/check_site_sync_gateways.sh
git diff --check
```

Expected: 聚合脚本 passed，diff check 无输出。

- [ ] **Step 3: 构建 SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 检查两个仓库状态和提交边界**

```bash
git status --short
git log --oneline -8
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk log --oneline -5
```

Expected: App 未包含 SDK 源码，SDK 未包含 App 源码；用户原有未跟踪分析文档仍保持未跟踪，未被意外提交。

- [ ] **Step 8: 记录仍需外部验收的项目**

交付总结必须明确列为未由静态/构建证明：

- 真机持续 BLE 广播、Gateway 身份识别和多个 Network Key 范围。
- 同步暂停扫描期间 15 秒不累计，事务结束后续算。
- 每次只有一台 Gateway 连接与 Syncing。
- 真实 Gateway 接收完整 Date-Time 与 target offset，并返回匹配 Time Status。
- Done、Back、完成/取消侧滑、后台/前台和退出后的迟到 ACK。
- `/sitespace/sapce/gateway/regist` 实际持久化 timestamp/timezoneOffset。
- 网络失败后的 dirty retry、旧 generation 竞态和 `/sitespace/get/siteprops` 权威回读。
- 四品牌真机 UI、资源和 English/简体中文显示。

---

## 执行检查点

- Checkpoint A：Tasks 1–3 完成后审查 Context、Section 投影和扫描 active-time 语义，暂不接硬件。
- Checkpoint B：Tasks 4–5 完成后审查 SDK explicit Time Set、typed Time Status 和迟到 attempt 所有权。
- Checkpoint C：Tasks 6–7 完成后审查 `.syncGateway` generation、dirty retry 与单次 Site refresh。
- Checkpoint D：Tasks 8–10 完成后对照 Figma 节点与两个入口，运行全部 focused contracts。
- Checkpoint E：Task 11 完成后只声明静态/构建结果，并把真机与服务器项交给实际环境验收。
