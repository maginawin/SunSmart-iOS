# Site 进入时区同步检查实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Site 页面首次成功获取 `/sitespace/get/siteprops` 后，按已确认的权限、timezone 和 timestamp 规则完成 Site 级收敛，并展示 Figma checking/结果 Overlay。

**Architecture:** 采用方案 A。`SiteViewController` 仅捕获请求前快照并接线；Foundation 纯策略负责仲裁；独立协调器负责一次性触发、持久化/上传、1/30 秒计时和迟到响应；专用 UIKit Overlay 负责展示，不复用 `SRAlertView` 或 Edit Site 的 `SiteTimeZoneSyncStatusView`。

**Tech Stack:** Swift、UIKit、Swift Concurrency、SwiftyJSON、SnapKit、现有 `SitePropsAPIClientProtocol`、独立 `swiftc` 契约测试、`xcodebuild` generic iPhoneOS。

## 全局约束

- 当前阶段只实现 Site timezone；不得发送 Gateway Time Zone SET，不进入 BLE/Mesh、扫描或 `Review sync`。
- 权限只以本次 `/get/siteprops` 当前 Site 的 `role` 为准。
- 服务器 timestamp 严格更新才采用服务器 timezone；否则采用本地 timezone 并显式上传。
- checking 实际显示后至少 1 秒、最多 30 秒；期间禁止遮罩关闭、导航返回和侧滑返回。
- Gateway 只读同步标识的正式 JSON 字段名不在 Figma、当前源码或已确认需求中；响应解析器必须隔离该映射。拿不到正式字段契约时不得猜测字段名，统一按“无待同步 Gateway”展示 `All gateways are in sync`。
- 用户可见文案全部国际化，同时提供 English 和简体中文。
- 新源码必须加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不改 Edit Site 现有 `SiteTimeZoneSyncStatusView` 行为，不做无关重构，不新增 Auth 信息。
- 验证只使用 generic iPhoneOS，不使用 Simulator；静态测试和构建不能宣称真实服务器、真机或 Gateway 端到端通过。
- 未得到单独授权前不创建 Git commit；每项任务以 `git diff --check` 和相应测试作为检查点。

---

## 文件结构

- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`
  - 责任：请求前/远端快照、权限、timezone/timestamp 仲裁、Gateway 结果映射和更新快照构造。
- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
  - 责任：从 `/get/siteprops` 的原始 Site 字典提取 `role`、timezone、timestamp、Gateway 总数与可用同步标识；不修改模型。
- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift`
  - 责任：每页面实例一次、持久化/上传、最短/最长计时、取消和迟到结果隔离。
- Create: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
  - 责任：Figma 居中卡片的 checking/result UI、`GOT IT` 回调及动态 Site/Gateway 文案。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 责任：在导入前捕获本地快照、把首次成功响应交给协调器、协调 HUD、Overlay 和导航锁定。
- Modify: `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`
  - 责任：仅增加可复用的 Site state 读取/应用边界，保持 Edit Site 行为不变。
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Create: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`
- Create: `Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift`
- Create: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`

## 统一接口

后续任务统一使用以下名称，禁止各任务自行改名：

```swift
enum SiteEntryRole: Equatable { case owner, editor, visitor }

struct SiteEntryTimeZoneLocalSnapshot: Equatable {
    let siteId: String
    let values: SitePropsValues
    let lastUpdate: Int64
    let lastUploadCloudTimestamp: Int64?
    let pending: SitePropsPendingState

    var timezone: SiteTimeZoneValue? { values.timezone }
}

struct SiteEntryGatewaySyncSnapshot: Equatable {
    let totalCount: Int
    let pendingCount: Int?
}

struct SiteEntryTimeZoneRemoteSnapshot: Equatable {
    let role: SiteEntryRole
    let timezone: SiteTimeZoneValue?
    let timestamp: Int64
    let gateways: SiteEntryGatewaySyncSnapshot
}

enum SiteEntryGatewaySummary: Equatable {
    case noGateways
    case pending(Int)
    case inSync
}

enum SiteEntryTimeZoneDecision: Equatable {
    case noAction
    case useRemote(
        timezone: SiteTimeZoneValue,
        remoteTimestamp: Int64,
        gateway: SiteEntryGatewaySummary
    )
    case useLocal(snapshot: SitePropsUpdateSnapshot, gateway: SiteEntryGatewaySummary)
}

enum SiteEntryTimeZoneSiteResult: Equatable {
    case updatedFromServer
    case updatedToServer
    case failedToUpdateServer
}

struct SiteEntryTimeZoneResult: Equatable {
    let timezone: SiteTimeZoneValue
    let site: SiteEntryTimeZoneSiteResult
    let gateway: SiteEntryGatewaySummary
}
```

---

### Task 1：建立进入响应只读解析边界

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
- Create: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`

**Interfaces:**

- Produces: `SiteEntryTimeZoneRemoteSnapshot`
- Produces: `SiteEntryTimeZoneSyncResponseParser.parse(siteData:gatewaySyncFlag:)`
- Consumes: `SiteTimeZoneValue(storageValue:)`

- [ ] **Step 1：写解析失败测试**

在 `SiteEntryTimeZoneSyncPolicyTests.swift` 建立独立 `@main` 测试入口，先覆盖：

```swift
let owner = parser.parse(siteData: [
    "role": "owner",
    "timezone": "Asia/Singapore (UTC+08:00)",
    "updateTimestamp": 101,
    "gateways": [["sync": true], ["sync": false]]
]) { $0["sync"] as? Bool }
require(owner?.role == .owner, "Expected response role")
require(owner?.gateways == .init(totalCount: 2, pendingCount: 1), "Expected one pending gateway")

let missingFlags = parser.parse(siteData: [
    "role": "editor",
    "timezone": "Etc/UTC (UTC+00:00)",
    "updateTimestamp": 102,
    "gateways": [["macAddress": "a"], ["macAddress": "b"]]
]) { _ in nil }
require(missingFlags?.gateways.pendingCount == nil, "Missing flags must remain unknown")

let invalidTimezone = parser.parse(siteData: [
    "role": "owner",
    "timezone": "invalid",
    "updateTimestamp": 103,
    "gateways": []
]) { _ in nil }
require(invalidTimezone?.timezone == nil, "Invalid remote timezone must be represented as nil")
```

测试中的 `sync` 只是注入解析器的 fixture key，不得成为生产字段约定。

- [ ] **Step 2：运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 编译失败，提示 `SiteEntryTimeZoneSyncResponseParser` 或快照类型不存在。

- [ ] **Step 3：实现最小只读解析器**

实现签名：

```swift
enum SiteEntryTimeZoneSyncResponseParser {
    typealias GatewaySyncFlag = ([String: Any]) -> Bool?

    static func parse(
        siteData: [String: Any],
        gatewaySyncFlag: GatewaySyncFlag
    ) -> SiteEntryTimeZoneRemoteSnapshot?
}
```

解析规则：

- `role` 仅接受 `owner`、`editor`，其他值统一 `.visitor`。
- `updateTimestamp` 必须能安全转换为 `Int64`，否则整个只读快照失败并维持现状。
- timezone 缺失、空或非法时保留为 `nil`，不能使整个响应解析失败。
- `gateways` 缺失视为 0 个 Gateway；存在时 `totalCount` 取数组数量。
- 仅当每个 Gateway 的注入标识都能解析时生成 `pendingCount`；任一个缺失或非法则为 `nil`。
- 生产接线只使用后端已书面确认的字段适配器；当前契约缺失时传入 `{ _ in nil }`，由策略降级为 `.inSync`。

- [ ] **Step 4：运行解析测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 输出 `SiteEntryTimeZoneSyncPolicyTests passed`。

- [ ] **Step 5：检查点**

Run: `git diff --check`

Expected: 无输出，退出码 0。

---

### Task 2：实现纯 timezone 仲裁策略

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`

**Interfaces:**

- Consumes: Task 1 的远端快照
- Produces: `SiteEntryTimeZoneSyncPolicy.decide(local:remote:now:) -> SiteEntryTimeZoneDecision`
- Produces: `SiteEntryTimeZoneSyncPolicy.gatewaySummary(_:) -> SiteEntryGatewaySummary`

- [ ] **Step 1：补全决策矩阵失败测试**

加入这些明确断言：

```swift
require(decide(role: .visitor, local: singapore, localTime: 100, remote: utc, remoteTime: 101) == .noAction,
        "Visitor must keep current behavior")
require(decide(role: .owner, local: singapore, localTime: 100, remote: singapore, remoteTime: 101) == .noAction,
        "Equal normalized timezone must not show the overlay")
require(remoteDecision(role: .editor, localTime: 100, remoteTime: 101).usesRemote,
        "Strictly newer remote timestamp must win")
require(localDecision(role: .owner, localTime: 101, remoteTime: 100).usesLocal,
        "Newer local timestamp must upload")
require(localDecision(role: .owner, localTime: 100, remoteTime: 100).usesLocal,
        "Equal timestamp with different values must upload local")
require(decide(local: nil, remote: utc).usesRemote,
        "Only valid remote timezone must win")
require(decide(local: singapore, remote: nil).usesLocal,
        "Only valid local timezone must upload")
require(decide(local: nil, remote: nil) == .noAction,
        "Two invalid timezones must keep current behavior")
require(gateway(total: 0, pending: nil) == .noGateways, "No gateways")
require(gateway(total: 3, pending: 2) == .pending(2), "Pending count")
require(gateway(total: 3, pending: nil) == .inSync, "Unknown flags use approved fallback")
require(gateway(total: 3, pending: 0) == .inSync, "All gateways are in sync")
```

同时断言本地胜出生成的 `SitePropsUpdateSnapshot`：

- `fields == [.timezone]`；
- `timestamp > local.lastUpdate`；
- `timestamp > remote.timestamp`；
- values 中 name/image 保持请求前本地值。

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 缺少 `SiteEntryTimeZoneSyncPolicy`。

- [ ] **Step 3：实现纯策略**

实现公开入口：

```swift
enum SiteEntryTimeZoneSyncPolicy {
    static func decide(
        local: SiteEntryTimeZoneLocalSnapshot,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        now: Int64
    ) -> SiteEntryTimeZoneDecision

    static func gatewaySummary(
        _ snapshot: SiteEntryGatewaySyncSnapshot
    ) -> SiteEntryGatewaySummary
}
```

关键实现约束：

- 先判断 Owner/Editor，再判断 timezone 有效性与相等性。
- 本地胜出使用 `SitePropsEditPolicy.nextTimestamp(now:current:)`，其中 `current = max(local.lastUpdate, remote.timestamp)`。
- 本地胜出构建只包含 `.timezone` 的 pending/update snapshot，不把 name/image 误标为 pending。
- 本地 pending state 必须保留既有待上传字段并加入 `.timezone`，统一使用新 timestamp；timezone 上传成功只清除 `.timezone`，其他 pending 字段继续保留。
- Gateway 未知标识按 `.inSync`，但 0 个 Gateway 的优先级最高。

- [ ] **Step 4：运行策略与既有 policy 回归**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
```

Expected: 两项测试分别输出 passed。

- [ ] **Step 5：检查点**

Run: `git diff --check`

---

### Task 3：提供可复用的本地状态应用边界

**Files:**

- Modify: `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`
- Modify: `Tests/Site/SitePropsAPIContractTests.swift`
- Verify: `Tests/Site/SiteTimeZonePersistenceContractTests.swift`

**Interfaces:**

- Produces: `SitePropsEditCoordinator.currentState() -> SitePropsLocalState`
- Produces: `SitePropsEditCoordinator.persistState(_:) -> Bool`
- Existing: `submit(_:) async -> Bool`

- [ ] **Step 1：写复用边界契约失败测试**

在 `SitePropsAPIContractTests` 的 coordinator 检查中增加：

```swift
require(
    coordinator.contains("func currentState() -> SitePropsLocalState") &&
    coordinator.contains("func persistState(_ state: SitePropsLocalState) -> Bool"),
    "Site entry and Edit Site must share one state persistence boundary"
)
```

并继续要求 `apply(_:)` 不公开，避免调用方绕过回滚。

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
```

Expected: 缺少可复用读取/持久化接口。

- [ ] **Step 3：最小化开放状态接口**

在 `@MainActor SitePropsEditCoordinator` 中：

```swift
func currentState() -> SitePropsLocalState

@discardableResult
func persistState(_ state: SitePropsLocalState) -> Bool
```

`persistState` 必须：保存旧 state、应用新 state、调用 `site.save()`；失败时恢复旧 state 并返回 false。现有 `prepareDraft`、`persist(_:)` 改为调用该边界，行为保持不变。

- [ ] **Step 4：运行 API、policy 和持久化回归**

Run:

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected: 两项测试输出 passed。

- [ ] **Step 5：检查点**

Run: `git diff --check`

---

### Task 4：实现一次性协调、计时、持久化与上传

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift`
- Create: `Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift`
- Modify: `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`

**Interfaces:**

- Consumes: Task 2 policy、Task 3 state/API boundary
- Produces: `prepare(local:remote:now:) -> SiteEntryTimeZoneDecision`
- Produces: `run(_:) async -> SiteEntryTimeZoneResult`
- Produces: `consumeWithoutAction()`
- Produces: `cancel()`
- Produces: `hasConsumedEntryResponse`

- [ ] **Step 1：写协调器失败测试**

使用 fake API、fake store 和可控 sleeper，覆盖：

```swift
await requireSingleConsumption()
await requireFastSuccessWaitsOneSecond()
await requireSlowSuccessPublishesImmediatelyAfterCompletion()
await requireThirtySecondTimeoutWinsRace()
await requireLateSuccessCannotReplaceFailure()
await requireCancelProducesNoResult()
await requireRemotePersistenceDoesNotUpload()
await requireLocalUploadSuccessClearsPending()
await requireLocalUploadFailureKeepsPending()
```

fake 依赖统一协议：

```swift
protocol SiteEntryTimeZoneSyncStore: AnyObject {
    func currentState() -> SitePropsLocalState
    func persistState(_ state: SitePropsLocalState) -> Bool
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}

protocol SiteEntryTimeZoneSyncSleeping {
    func sleep(nanoseconds: UInt64) async throws
}
```

在 `SitePropsEditCoordinator.swift` 增加显式 conformance，转发到 Task 3 已开放的方法；不得复制 `apply(_:)` 或另写数据库逻辑：

```swift
extension SitePropsEditCoordinator: SiteEntryTimeZoneSyncStore {}
```

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
```

Expected: 缺少 coordinator 和依赖协议。

- [ ] **Step 3：实现协调器状态机**

实现：

```swift
@MainActor
final class SiteEntryTimeZoneSyncCoordinator {
    static let minimumDisplayNanoseconds: UInt64 = 1_000_000_000
    static let timeoutNanoseconds: UInt64 = 30_000_000_000

    private(set) var hasConsumedEntryResponse = false

    func prepare(
        local: SiteEntryTimeZoneLocalSnapshot,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        now: Int64
    ) -> SiteEntryTimeZoneDecision

    func run(
        _ decision: SiteEntryTimeZoneDecision
    ) async -> SiteEntryTimeZoneResult

    func consumeWithoutAction()
    func cancel()
}
```

执行规则：

- `prepare` 第一次调用即设置 `hasConsumedEntryResponse` 并委托纯策略；后续调用返回 `.noAction`。
- 原始响应无法解析时由入口调用 `consumeWithoutAction()`，确保首次成功请求仍被消费，刷新不重试。
- `.noAction` 不展示 Overlay、不启动计时、不修改数据。
- checking 已由 UI 实际展示后才调用 `run`，因此 1/30 秒均以 `run` 为起点。
- 使用结构化并发竞争业务任务与 30 秒 timeout；终态以一次性 token/状态门收口。
- 业务任务完成早于 1 秒时补足剩余时间；完成晚于 1 秒时立即发布。
- `.useRemote` 只替换 timezone；`lastUpdate` 使用 `max(current.lastUpdate, remoteTimestamp)`，不得因“本地 timezone 非法、远端有效但版本较旧”而倒退；持久化成功后返回 `.updatedFromServer`，绝不调用 submit。
- `.useLocal` 先持久化 timezone pending，再调用 submit；成功清除对应 pending，失败保持 pending。
- timeout 返回 `.failedToUpdateServer`；任何后续业务回调不得改变 UI 或清掉 pending。

- [ ] **Step 4：运行协调器测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
/tmp/SiteEntryTimeZoneSyncCoordinatorTests
```

Expected: 输出 `SiteEntryTimeZoneSyncCoordinatorTests passed`。

- [ ] **Step 5：检查点**

Run: `git diff --check`

---

### Task 5：实现 Figma 专用 Overlay 与本地化

**Files:**

- Create: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**

- Consumes: `SiteEntryTimeZoneResult`
- Produces: `showChecking(in:)`、`showResult(_:)`、`dismiss()`、`onGotIt`

- [ ] **Step 1：写 UI/文案契约失败测试**

契约测试读取 Overlay 和两个 strings 文件，要求：

- Overlay 有 `.checking`、`.result(SiteEntryTimeZoneResult)` 两态。
- checking 无按钮；result 只有 `GOT IT`。
- 不出现 `SRAlertView`、`SiteTimeZoneSyncStatusView`、`Review sync`、Mesh 或 Gateway 写操作。
- 使用 40% 黑色全屏遮罩、20pt 圆角居中卡片和 Figma 文案 Key。
- 以下 Key 在两种语言中各出现一次：

```text
site_entry_sync_checking_title
site_entry_sync_checking_message
site_entry_sync_status_title
site_entry_sync_site_time_zone
site_entry_sync_updated_from_server
site_entry_sync_updated_to_server
site_entry_sync_failed_to_update_server
site_entry_sync_gateway_time_zone
site_entry_sync_no_gateways
site_entry_sync_gateways_need_sync
site_entry_sync_gateways_in_sync
site_entry_sync_got_it
```

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj
```

Expected: 文件或本地化 Key 缺失。

- [ ] **Step 3：实现 Overlay**

公开 API：

```swift
final class SiteEntryTimeZoneSyncOverlay: UIView {
    enum State: Equatable {
        case checking
        case result(SiteEntryTimeZoneResult)
    }

    var onGotIt: (() -> Void)?
    func showChecking(in container: UIView)
    func showResult(_ result: SiteEntryTimeZoneResult)
    func dismiss()
}
```

布局按 Figma `399:11417` 和结果变体实现：

- `backgroundColor = UIColor.black.withAlphaComponent(0.4)`。
- 卡片居中，左右至少 16pt 安全间距，圆角 20pt；复用项目 `RGB`、`SCRXFrom`、`SCRYFrom` 和 SnapKit。
- checking 使用项目已存在且视觉匹配的 loading 方案；若无匹配资产，则从 Figma 导出原始 asset 并加入 Assets，不手绘 SVG。
- Site 行显示最终 timezone 的 `displayOffset` 与 site result 文案。
- Gateway 行按 `.noGateways`、`.pending(count)`、`.inSync` 映射；数量使用本地化格式参数。
- label 支持多行和 Dynamic Type/字体缩放；长 IANA/文案不得突破卡片。
- 遮罩不绑定 dismiss tap；checking 隐藏按钮；result 仅显示 `GOT IT`。

- [ ] **Step 4：增加 English 与简体中文**

English 使用已确认原文：

```text
Checking sync status…
Comparing server time zone and gateway configuration.
Sync status
Updated from server
Updated to server
Failed to update server
No gateways to sync
%d gateways need time zone sync
All gateways are in sync
GOT IT
```

简体中文提供等义翻译，不改变 English 默认文案；所有文案通过 `.localizedString` 或项目格式化本地化入口获取。

- [ ] **Step 5：运行 UI 契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj
```

Expected: 输出 `SiteEntryTimeZoneSyncContractTests passed`。

- [ ] **Step 6：检查点**

Run: `git diff --check`

---

### Task 6：接入 Site 首次成功请求与导航锁定

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`

**Interfaces:**

- Consumes: Task 1–5 全部接口
- Produces: `handleEntryTimeZoneSyncIfNeeded(siteData:local:)`
- Produces: `setEntrySyncNavigationLocked(_:)`
- Produces: `finishEntrySyncOverlay()`

- [ ] **Step 1：写入口和导航契约失败测试**

要求 `SiteViewController`：

- 拥有单个 `SiteEntryTimeZoneSyncCoordinator` 与 Overlay。
- 在 `site.update(siteJsonData:)` 前创建包含 `SitePropsValues` 的 `SiteEntryTimeZoneLocalSnapshot`。
- 仅在 `.success` 且原始 Site 字典可解析时调用进入检查；failure 保持原有分支。
- 使用响应 `role`，不读取请求前 `site.permission` 作为准入判断。
- 先执行 `XWHUDManager.hideInView(with:)`，再展示 checking。
- `backAction` 在 entry sync 锁定时直接返回。
- 保存并恢复 `interactivePopGestureRecognizer?.isEnabled` 的进入前值。
- `GOT IT` 后清理 Overlay/Task 并恢复导航。
- `deinit` 或取消入口会调用 coordinator cancel。
- 同一实例的刷新/网络恢复不会重置 coordinator 的 consumed 状态。

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj
```

Expected: Site 入口和导航锁定契约缺失。

- [ ] **Step 3：接入请求前快照**

在 `loadSiteRequest()` 成功分支、调用整包导入之前：

```swift
let localState = sitePropsCoordinator.currentState()
let localSnapshot = SiteEntryTimeZoneLocalSnapshot(
    siteId: site.id,
    values: localState.values,
    lastUpdate: localState.lastUpdate,
    lastUploadCloudTimestamp: localState.lastUploadCloudTimestamp,
    pending: localState.pending
)
```

然后用 Task 1 parser 解析原始 `siteData`。生产 `gatewaySyncFlag` 必须来自正式后端字段适配；字段契约仍不可用时明确传 `{ _ in nil }`，使有 Gateway 的只读行按已确认规则显示 in-sync，不尝试根据本地 Mesh 猜测。解析失败时调用 `consumeWithoutAction()`，本页面实例不因刷新再次尝试。

- [ ] **Step 4：保持既有导入与页面刷新**

整包 `site.update(siteJsonData:)`、地址回收、`setupData()`、自动进入 Space 和既有 Cloud sync 路由保持原顺序。新流程只在成功响应中插入：

1. 导入前快照；
2. 由协调器 `prepare` 生成决策；
3. 导入完成并隐藏 HUD；
4. 若决策需要处理，展示 checking 后调用 `run`。

请求失败、无法解析 timestamp、Visitor、相同 timezone 和两端 timezone 无效均不得展示 Overlay。

- [ ] **Step 5：实现导航锁定与 Overlay 生命周期**

实现：

```swift
private func setEntrySyncNavigationLocked(_ locked: Bool)
private func finishEntrySyncOverlay()
```

- 锁定时禁用左侧返回 action 的实际 pop，并将侧滑值保存后设为 false。
- 解除时恢复保存值，不能无条件设为 true。
- Overlay 的 `onGotIt` 调用 finish。
- coordinator 超时返回 failure result，仍保持锁定直到 `GOT IT`。
- 控制器释放时取消任务；外部 Site 切换时清理但不显示迟到结果。

- [ ] **Step 6：运行新旧 UI 契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: 两项测试输出 passed；Edit Site 既有弹窗契约不变。

- [ ] **Step 7：检查点**

Run: `git diff --check`

---

### Task 7：加入四 target 并完成全量验证

**Files:**

- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Verify: 本计划所有源码、本地化和测试文件

**Interfaces:**

- Produces: 四品牌 target 的一致 source/resource membership

- [ ] **Step 1：先扩展 membership 契约**

在 `SiteTimeZoneUIContractTests.testLocalizationAndTargetMembership` 的 `newSourceFiles` 加入：

```swift
"SiteEntryTimeZoneSyncPolicy.swift",
"SiteEntryTimeZoneSyncResponseParser.swift",
"SiteEntryTimeZoneSyncCoordinator.swift",
"SiteEntryTimeZoneSyncOverlay.swift"
```

每个文件必须在 PBXSourcesBuildPhase 中恰好出现 4 次。

- [ ] **Step 2：运行并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected: 新源码尚未加入四个 Sources phase。

- [ ] **Step 3：更新 Xcode 工程 membership**

为四个新源码创建 file reference，并把它们加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 Sources phase。若 Task 5 引入 Figma loading asset，同时确认 Asset Catalog 已由四个 target 共用；不要新增重复品牌资源。

- [ ] **Step 4：运行全部聚焦测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
/tmp/SiteEntryTimeZoneSyncCoordinatorTests
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected: 每项输出对应的 `passed`，退出码均为 0。

- [ ] **Step 5：运行格式与范围检查**

Run:

```bash
git diff --check
git status --short
git diff --stat
rg -n "Review sync|Time Set|Gateway Time|MeshAPI|SRAlertView" SunSmart/Main/Site/Model/SiteEntryTimeZoneSync* SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift
```

Expected:

- `git diff --check` 无输出。
- 变更只包含本计划文件和已确认文档。
- 新功能源码中不存在 Gateway 写操作、Mesh API、`Review sync` 或 `SRAlertView` 依赖。

- [ ] **Step 6：四品牌 generic iPhoneOS Debug 构建**

依次运行，不使用 shell 包装、不重定向日志：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四项均出现 `BUILD SUCCEEDED`。

- [ ] **Step 7：记录人工验收清单**

在实施总结中明确仍需真机/真实环境验证：

- Figma checking/result 视觉、loading、横竖屏、iPad、Dynamic Type。
- 30 秒期间返回按钮和侧滑均不可离开；`GOT IT` 后恢复原导航状态。
- 真实 Owner/Editor/Visitor 响应与 timezone timestamp 仲裁。
- 真实服务器 timezone 上传成功、失败、超时和迟到响应。
- 真实 Gateway 同步标识字段确认后，0、部分和全部待同步的只读结果。

不得把构建成功写成上述端到端验收通过。

---

## 实施顺序与检查点

按 Task 1 → 7 顺序执行。Task 1–4 先建立纯数据和时序真值；Task 5 完成独立 UI；Task 6 才接入现有控制器；Task 7 最后修改 target membership 并进行四品牌构建。每个 Task 完成后先展示测试证据和 diff 范围，再进入下一 Task。

按项目约定，执行阶段默认使用 `superpowers:executing-plans` 的 Inline Execution，不使用 subagents，也不再询问执行方式。
