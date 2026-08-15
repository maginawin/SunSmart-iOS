# Site Gateway 云端时区同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 在现有 `Time zone sync status` 弹窗中展示全部有权限的 Gateway，先完成 Site 时区同步，再批量下发 Gateway 时区并按 3 秒轮询、3 分钟超时实时更新 `Pushing…`、`Synced`、`Failed`，全部终态后才允许点击 `DONE`。

**Architecture:** 保留 `SiteEntryTimeZoneSyncCoordinator` 只负责 Site 阶段；新增纯数据 Target Builder、批次状态归并器、响应解析器、API Client 和独立 Gateway Coordinator。`SiteViewController` 只负责串联 Site 结果、Gateway 批次、弹窗显示、Review sync 和静默刷新，HTTP 成功不写 Mesh Node 状态。

**Tech Stack:** Swift、UIKit、SnapKit、Moya、Swift Concurrency、当前 `swiftc -parse-as-library` 可执行测试、Xcode workspace 多 target 构建。

**Global Constraints:** UI 文案使用英文并提供 English/简体中文本地化；不得新增 Auth/userId 参数；不得持久化 `requestId`；不得修改 Mesh Node 的 timestamp/timezone 或调用 `savePropertys()`；只复用现有资源和组件；新增 Swift 文件必须加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target；执行阶段仅在用户明确授权时执行本计划列出的建议 commit。

---

## 0. 已确认行为与不可变约束

- 只有现有 Site 入口策略决定展示弹窗时，才渲染 Gateway 明细并启动 Gateway 阶段。
- Site 与 Cloud 时区相同且所有 Gateway 已同步时，现有 `.noAction` 保持静默，不为了展示“全成功”而新增弹窗。
- Site 更新失败时不得请求 `/sitespace/gateway/datetime/update`；本批次原本为 `Pushing…` 的行全部转为 `Failed`，原本已匹配的行保持 `Synced`。
- Owner 可处理 Site 返回的全部有效 Gateway；Editor 只处理其 Editor Space 关联的 Gateway；Visitor 不展示、不下发。
- 弹窗展示全部有权限 Gateway，标题计数是有权限总数；请求体只包含需要同步的 Gateway MAC。
- Gateway 名称为空或缺失时显示请求使用的 MAC。
- 首次状态查询在获得有效 `requestId` 3 秒后发出；之后每 3 秒查询一次。
- 从获得有效 `requestId` 开始计 180 秒；进入后台的时间计入超时，恢复前台时先判断是否已超时。
- 单次状态查询失败、响应结构不可解析或返回未知值时不改变行状态，继续轮询直至全部终态或超时。
- 状态终态不可逆；同一响应中同一 MAC 同时出现成功与失败终态时，本轮不更新该 MAC，继续等待后续结果。
- `Succeed` 显示 `Synced`；`Failed`、`Expired` 显示 `Failed`；`Requested` 保持 `Pushing…`；`NIL`、null、缺失和其他值保持原状态。
- 提交接口失败或 `requestId` 无效时，本批次全部未完成 Gateway 立即失败。
- 有 Gateway 处于 `Pushing…` 时不得展示 `DONE`，且返回、侧滑、遮罩点击和其他关闭路径全部被阻断。
- 无有权限 Gateway 或全部 Gateway 已终态时展示 `DONE`；不再提供 `LATER`、`REVIEW SYNC` 弹窗按钮。
- 失败 Gateway 仍通过 Site 页现有 `Review sync` 入口进入 BLE 补偿页，计数仅包含失败数量。
- Gateway 批次终态后触发一次不阻塞 `DONE` 的静默 Site 刷新；本次成功 MAC 在当前 `SiteViewController` 生命周期内保留目标 offset 覆盖，直到云端快照匹配或控制器销毁。

## 1. 文件结构与责任边界

### 新增生产文件

- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift`
  - 有权限 Gateway Target、显示名和有效 offset 的构建规则。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift`
  - 行状态、远端状态归并、失败计数和 `canDismiss`。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift`
  - `requestId` 与状态列表的无副作用解析。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneAPIClient.swift`
  - `NetworkRequest` 到 Gateway 同步协议的适配。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift`
  - 提交、轮询、总超时、取消和晚到响应隔离。
- `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
  - `GATEWAYS` 标题、可滚动行列表、无 Gateway 文案和失败统计卡片。

### 修改生产文件

- `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
  - 同时保留规范化 ID 与原始请求 MAC。
- `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`
  - 统一使用 Target Builder 计算 Gateway 摘要，避免入口策略和弹窗列表出现两套权限/偏移判断。
- `SunSmart/Common/Network/NetowrkReqeustApi.swift`
  - 新增两个 POST endpoint、诊断名、路径与精确 body。
- `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
  - 将单一 Gateway 汇总卡改为明细组件，改标题和关闭规则。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 串联两个阶段、维护当前生命周期成功覆盖并触发静默刷新。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 更新标题并新增 Gateway 行、空状态、失败统计和 `DONE` 文案。
- `SunSmart.xcodeproj/project.pbxproj`
  - 六个新增 Swift 文件加入四个 target。
- `scripts/check_site_sync_gateways.sh`
  - 纳入全部新增纯逻辑测试和 contract 测试。

### 新增测试文件

- `Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneSyncStateTests.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneResponseParserTests.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneSyncCoordinatorTests.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneAPIContractTests.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`

### 修改测试文件

- `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`
- `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

---

## Task 1: 保留 Gateway 请求身份并建立唯一 Target Builder

**Files:**

- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`
- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`

**Consumes:** `SiteEntryTimeZoneRemoteSnapshot`、`SiteGatewayAccessScope`、导入前捕获的本地 Gateway 名称/dirty offset、当前控制器生命周期内的已确认成功 offset。

**Produces:** 有序且按规范化 ID 去重的 `[SiteGatewayCloudTimeZoneTarget]`；入口策略与弹窗使用同一个构建结果。

- [ ] 1.1 先补失败测试，覆盖以下矩阵：Owner 全量、Editor 仅 Editor Space、Visitor 空数组、重复 MAC 大小写去重、Editor Space 中存在但 `gateways` 缺失、无名称回退 MAC、已匹配为无需同步、offset 缺失为需同步、重复快照 offset 冲突为需同步、确认成功 offset 优先级最高、本地 dirty offset 次之、远端 offset 最后。

测试入口保持仓库现有 `@main` 风格，核心断言调用如下接口：

```swift
let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
    targetOffsetMinutes: 480,
    remote: remote,
    localByGatewayID: local,
    confirmedOffsetMinutesByGatewayID: confirmed
)
require(targets.map(\.id) == ["ef725643a2b9"], "Editor must only receive its authorized Gateway")
require(targets.first?.requestMAC == "EF725643A2B9", "Request must preserve the trimmed wire MAC")
```

- [ ] 1.2 用最小 `swiftc` 命令运行测试并确认因为新类型不存在而失败：

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift -o /tmp/SiteGatewayCloudTimeZoneTargetTests
/tmp/SiteGatewayCloudTimeZoneTargetTests
```

- [ ] 1.3 扩展远端快照，保留规范化比较 ID 和原始请求值；旧调用通过默认参数继续编译：

```swift
private func trimmedGatewayIdentifier(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

struct SiteEntrySpaceAccessSnapshot: Equatable {
    let role: SiteEntryRole
    let gatewayId: String?
    let requestGatewayId: String?

    init(role: SiteEntryRole, gatewayId: String?, requestGatewayId: String? = nil) {
        self.role = role
        self.gatewayId = SiteGatewayAccessScope.normalize(gatewayId)
        self.requestGatewayId = trimmedGatewayIdentifier(requestGatewayId ?? gatewayId)
    }
}

struct SiteEntryGatewayTimeZoneSnapshot: Equatable {
    let id: String?
    let requestMAC: String?
    let offsetMinutes: Int?

    init(id: String?, requestMAC: String? = nil, offsetMinutes: Int?) {
        self.id = SiteGatewayAccessScope.normalize(id)
        self.requestMAC = trimmedGatewayIdentifier(requestMAC ?? id)
        self.offsetMinutes = offsetMinutes
    }
}
```

解析 `spaces[].gatewayId` 和 `gateways[].macAddress` 时分别把原始字符串传给 `requestGatewayId`、`requestMAC`；规范化仍只用于比较，不把 lowercased 字符串强制发回服务器。

- [ ] 1.4 新增 Target 模型与构建入口，固定字段和优先级：

```swift
struct SiteGatewayCloudTimeZoneLocalSnapshot: Equatable {
    let displayName: String
    let dirtyOffsetMinutes: Int?
}

struct SiteGatewayCloudTimeZoneTarget: Equatable, Identifiable {
    let id: String
    let requestMAC: String
    let displayName: String
    let remoteOrder: Int
    let effectiveOffsetMinutes: Int?
    let requiresSync: Bool
}

enum SiteGatewayCloudTimeZoneTargetBuilder {
    static func build(
        targetOffsetMinutes: Int,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        localByGatewayID: [String: SiteGatewayCloudTimeZoneLocalSnapshot],
        confirmedOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> [SiteGatewayCloudTimeZoneTarget]
}
```

构建规则按以下顺序实现：

1. Owner 按 `remote.gateways` 首次出现顺序取有效 ID。
2. Editor 先按 `remote.gateways` 顺序取权限集合内 ID，再按 Editor Space 首次出现顺序补齐服务器 Gateway 列表缺失的 ID。
3. Visitor 返回空数组。
4. `requestMAC` 优先用远端 Gateway 原始 MAC，再用 Space 原始 Gateway ID，最后用规范化 ID。
5. `displayName` 使用 trim 后的本地名称；为空时使用 `requestMAC`。
6. 有效 offset 优先级为 `confirmed > local dirty > remote`；同 ID 多个远端非空 offset 不一致时，远端 offset 视为未知。
7. `effectiveOffsetMinutes == targetOffsetMinutes` 时 `requiresSync == false`，否则为 `true`。

- [ ] 1.5 将 `SiteEntryTimeZoneSyncPolicy.gatewaySummary` 改为调用 Target Builder，并只从 targets 计算 `.noGateways`、`.pending(count)`、`.inSync`。为保持纯策略测试不依赖 UIKit，给策略传入的本地字典转换成 `SiteGatewayCloudTimeZoneLocalSnapshot(displayName: "", dirtyOffsetMinutes: value)`。

- [ ] 1.6 运行 Target 与入口策略测试，确认权限、计数和弹窗触发行为同时通过。

- [ ] 1.7 建议 commit（仅获授权后执行）：`feat: add gateway timezone sync target builder`

---

## Task 2: 实现 Gateway 批次状态归并器

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneSyncStateTests.swift`

**Consumes:** Task 1 的 Target，以及解析后的远端 MAC 状态集合。

**Produces:** UI 可直接消费的行状态、请求 MAC、失败数、终态判断和不可逆状态转换。

- [ ] 2.1 先写失败测试，覆盖初始化、混合已同步/待同步、大小写匹配、额外 MAC 忽略、Requested 不变、成功/失败/过期映射、未知值不进入 reducer、终态不可逆、同轮冲突不更新、全部终态提前完成、`failPushing()` 只失败未完成行。

```swift
var state = SiteGatewayCloudTimeZoneBatchState(targets: targets)
state.apply([
    .init(id: "ef725643a2b9", statuses: [.succeed]),
    .init(id: "ef725643a2b0", statuses: [.failed])
])
require(state.items.map(\.status) == [.synced, .failed], "Terminal statuses must update independently")
require(state.canDismiss, "DONE is available only after every row is terminal")
```

- [ ] 2.2 运行最小测试并确认新状态类型缺失导致失败。

- [ ] 2.3 实现以下固定模型：

```swift
enum SiteGatewayCloudTimeZoneItemStatus: Equatable {
    case pushing
    case synced
    case failed
}

enum SiteGatewayCloudTimeZoneRemoteStatus: Hashable {
    case requested
    case succeed
    case failed
    case expired
}

struct SiteGatewayCloudTimeZoneRemoteStatusSnapshot: Equatable {
    let id: String
    let statuses: Set<SiteGatewayCloudTimeZoneRemoteStatus>
}

struct SiteGatewayCloudTimeZoneItem: Equatable, Identifiable {
    let id: String
    let requestMAC: String
    let displayName: String
    var status: SiteGatewayCloudTimeZoneItemStatus
}

struct SiteGatewayCloudTimeZoneBatchState: Equatable {
    private(set) var items: [SiteGatewayCloudTimeZoneItem]

    init(targets: [SiteGatewayCloudTimeZoneTarget])
    var authorizedCount: Int { get }
    var requestMACs: [String] { get }
    var hasPushing: Bool { get }
    var failedCount: Int { get }
    var canDismiss: Bool { get }
    mutating func apply(_ snapshots: [SiteGatewayCloudTimeZoneRemoteStatusSnapshot])
    mutating func failPushing()
}
```

- [ ] 2.4 在 `apply` 中先按规范化 ID 聚合状态；`.succeed` 与 `.failed`/`.expired` 同时存在时视为冲突并跳过；只有当前 `.pushing` 行允许转换；`.requested` 单独存在时不变。

- [ ] 2.5 运行状态测试并确认通过；再用 `git diff --check` 检查空白错误。

- [ ] 2.6 建议 commit（仅获授权后执行）：`feat: model gateway timezone batch state`

---

## Task 3: 实现响应解析与精确 API 契约

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift`
- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneAPIClient.swift`
- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneResponseParserTests.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneAPIContractTests.swift`

**Consumes:** `/sitespace/gateway/datetime/update` 和 `/sitespace/request/status` 的字典响应。

**Produces:** 正 `Int64 requestId`、已知 Gateway 状态集合，以及 Coordinator 可替换的 API 协议。

- [ ] 3.1 先写 requestId 解析失败测试：接受正 Int、Int64、整数 NSNumber 和数字字符串；拒绝 Bool、0、负数、小数、空字符串、越界数、缺少 `data.requestId`。

- [ ] 3.2 先写状态解析失败测试：接受 data 数组中的单键或多键字典；MAC trim/lowercase 后归并；状态值 trim 后按大小写不敏感识别四个已知值；`NIL`、null、非字符串和未知值忽略；data 不是数组时返回 `nil`；合法空数组返回 `[]`。

```swift
enum SiteGatewayCloudTimeZoneResponseParser {
    static func parseRequestID(from response: [String: Any]) -> Int64?
    static func parseStatuses(
        from response: [String: Any]
    ) -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]?
}
```

- [ ] 3.3 运行解析测试并确认因实现缺失而失败，然后实现无副作用解析器并跑绿。

- [ ] 3.4 在 `NetowrkReqeustApi` 新增两个 case，并同步所有 exhaustive switch：

```swift
case gatewayDateTimeUpdate(siteId: String, gateways: [String])
case gatewayDateTimeRequestStatus(requestId: Int64)
```

固定映射如下：

| Case | diagnosticName | path | method | parameters |
|---|---|---|---|---|
| `gatewayDateTimeUpdate` | `gatewayDateTimeUpdate` | `/sitespace/gateway/datetime/update` | POST | `siteId`, `gateways` |
| `gatewayDateTimeRequestStatus` | `gatewayDateTimeRequestStatus` | `/sitespace/request/status` | POST | `requestId` |

参数字典不得加入 `userId`、token、timezone 或任何新 Auth 字段。

- [ ] 3.5 定义 API 协议和适配器；协议放在 Coordinator 文件中以便纯 Swift 测试只编译协议与协调器，生产适配器单独依赖 `NetworkRequest`：

```swift
protocol SiteGatewayCloudTimeZoneAPI {
    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64
    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]
}

enum SiteGatewayCloudTimeZoneAPIClientError: Error {
    case invalidRequestID
    case invalidStatusResponse
}

struct SiteGatewayCloudTimeZoneAPIClient: SiteGatewayCloudTimeZoneAPI {
    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64
    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]
}
```

`NetworkRequest` 已将业务 `code != 200` 归入 failure；适配器只需转抛 `NetworkApiError`，并在成功字典无法解析时抛出上面的解析错误。

- [ ] 3.6 新增字符串 contract 测试，逐一断言 case、diagnosticName、两条 path、精确参数键，以及 API Client 使用两个 parser；断言 Gateway 参数分支不含 `UserData.currentUserId`。

- [ ] 3.7 运行 parser 与 API contract 测试，再运行一次工程编译到 Swift 类型检查阶段，确认 exhaustive switch 没有遗漏。

- [ ] 3.8 建议 commit（仅获授权后执行）：`feat: add gateway timezone cloud api`

---

## Task 4: 实现 3 秒轮询、180 秒总超时与会话隔离

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneSyncCoordinatorTests.swift`

**Consumes:** API 协议、Task 2 批次状态。

**Produces:** 每次行状态变化回调和一个终态批次；取消时返回 `nil`，避免旧控制器或旧会话更新 UI；以连续单调时钟保证后台时间计入 180 秒截止时间。

- [ ] 4.1 先写 Fake API 和可控 Timing，覆盖以下失败测试：无请求 MAC 不调用 API；提交成功后首次 poll 前先 sleep 3 秒；Requested 后继续；状态请求失败继续；部分终态继续；全部终态立即停止；提交失败全部失败；无效响应由 API 抛错后全部失败；180 秒任务先完成时剩余行失败；模拟后台跨过 deadline 后不再发 status 请求；取消立即返回 nil；晚到提交/状态响应不影响已结束会话；新 run 使旧 token 失效。

- [ ] 4.2 运行最小测试并确认协调器不存在而失败。

- [ ] 4.3 建立以下接口与固定时间常量：

```swift
protocol SiteGatewayCloudTimeZoneTiming {
    var nowNanoseconds: UInt64 { get }
    func sleep(nanoseconds: UInt64) async throws
}

@MainActor
final class SiteGatewayCloudTimeZoneSyncCoordinator {
    nonisolated static let pollIntervalNanoseconds: UInt64 = 3_000_000_000
    nonisolated static let timeoutNanoseconds: UInt64 = 180_000_000_000

    init(
        api: SiteGatewayCloudTimeZoneAPI,
        timing: SiteGatewayCloudTimeZoneTiming,
        pollIntervalNanoseconds: UInt64 = pollIntervalNanoseconds,
        timeoutNanoseconds: UInt64 = timeoutNanoseconds
    )

    func run(
        siteID: String,
        initialState: SiteGatewayCloudTimeZoneBatchState,
        onUpdate: @escaping @MainActor (SiteGatewayCloudTimeZoneBatchState) -> Void
    ) async -> SiteGatewayCloudTimeZoneBatchState?

    func cancel()
}
```

生产 timing 使用 `ContinuousClock` 计算单调连续时间并使用 `Task.sleep(nanoseconds:)`；测试显式传可推进时间的 Fake Timing。获得有效 requestId 时记录 `deadlineNanoseconds = timing.nowNanoseconds + timeoutNanoseconds`，使用溢出安全加法。

- [ ] 4.4 以 `ActiveRun(token, continuation, state)` 管理生命周期。`run` 先取消旧会话并创建 token；提交由独立 Task 执行。获得有效 requestId 后同时启动：

1. timeout task：sleep 180 秒，若 token 仍活动则 `failPushing()`、回调最终状态并结束。
2. poll task：循环先 sleep 3 秒；sleep 返回后、发请求前和响应返回后都比较连续时钟与 deadline；到期时走统一 timeout 完成路径。未到期才请求 status；请求异常直接进入下一轮；成功则 apply、仅在状态变化时回调；全部终态时立即结束。

所有回调、结束和响应处理都必须先验证 token；`finish` 先清空 active run、取消兄弟任务，再 resume continuation，保证只完成一次。

- [ ] 4.5 `cancel()` 清空 active run、取消 submit/poll/timeout tasks，并让 continuation 返回 nil。调用方 Task cancellation 通过 `withTaskCancellationHandler` 转发到 `cancel()`。

- [ ] 4.6 运行协调器测试至少连续 3 次，确认可控 timing 下无竞态和偶发失败。

- [ ] 4.7 建议 commit（仅获授权后执行）：`feat: coordinate gateway timezone polling`

---

## Task 5: 构建 Gateway 明细、空状态与失败统计 UI

**Files:**

- Create: `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Consumes:** `SiteGatewayCloudTimeZoneBatchState`。

**Produces:** 可嵌入弹窗的固定头部 + 仅行列表滚动的 Gateway 组件。

- [ ] 5.1 先写 UI contract 失败测试，断言组件含 `GATEWAYS` 标题和 authorized count、table/scroll 列表、三种状态文案、loading 动画、成功/失败资源、No gateways 两行文案、失败数单复数格式、失败提示，以及所有本地化 key 在两种语言中各出现一次。

- [ ] 5.2 固定组件公开接口，避免 View 直接理解网络状态：

```swift
final class SiteEntryGatewayTimeZoneStatusView: UIView {
    func update(_ state: SiteGatewayCloudTimeZoneBatchState)
}
```

内部使用 `UITableView` 或现有等价可复用列表；行高固定，列表自身滚动，外部标题与失败卡不滚动。每次 update 按 `items` 原顺序 reload，数量通常较小，无需差异化数据源。

- [ ] 5.3 按 Figma 和现有资源实现状态视觉：

| 状态 | Gateway 资源 | 状态资源/动画 | 文案颜色 |
|---|---|---|---|
| `pushing` | `time-zone-sync-status-gateway` | `site_entry_sync_loading` 持续旋转 | 主题紫色 |
| `synced` | `time-zone-sync-status-gateway` | `site_entry_sync_success` | 绿色 |
| `failed` | `gateway_sync_tz_fail` | 失败视觉由 Gateway 资源表达 | `#FF4831` |

复用 `siteEntrySyncLoading` animation key，离开 `pushing` 或 cell reuse 时必须移除动画，防止复用后错误旋转。

- [ ] 5.4 更新原 key 并新增以下 key；English 值作为产品 UI 基准，简体中文提供自然翻译：

| Key | English |
|---|---|
| `site_entry_sync_status_title` | `Time zone sync status` |
| `site_entry_sync_gateways_header` | `GATEWAYS` |
| `site_entry_sync_gateway_pushing` | `Pushing…` |
| `site_entry_sync_gateway_synced` | `Synced` |
| `site_entry_sync_gateway_failed` | `Failed` |
| `site_entry_sync_no_gateways_title` | `No gateways` |
| `site_entry_sync_no_gateways_message` | `No gateways configured - no sync needed.` |
| `site_entry_sync_one_gateway_failed` | `1 gateway failed` |
| `site_entry_sync_gateways_failed_format` | `%d gateways failed` |
| `site_entry_sync_failed_guidance` | `Sync on-site via Bluetooth to complete.` |
| `site_entry_sync_done` | `DONE` |

- [ ] 5.5 对 authorized count 使用 `NumberFormatter` 或 `String(count)`，不使用带复数语义的旧 Gateway summary key。失败数明确走 1 与大于 1 两个 key。

- [ ] 5.6 运行 UI contract；检查 Dynamic Type 下名称单行截断、MAC 回退可读、0/1/N 行以及滚动复用后动画状态。

- [ ] 5.7 建议 commit（仅获授权后执行）：`feat: add gateway timezone status list ui`

---

## Task 6: 重构弹窗为不可提前关闭的结果 Bottom Sheet

**Files:**

- Modify: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Consumes:** Site 阶段结果和 Gateway 批次状态。

**Produces:** 检查态 + 结果 Bottom Sheet，只有 `gateways.canDismiss` 时显示 `DONE`。

- [ ] 6.1 先修改 contract 测试，使旧 `gatewaysNeedSync`、`onLater`、`onReviewSync`、`LATER`、`REVIEW SYNC` 断言失败，并新增标题、明细组件、safe area、滚动、DONE 门禁和遮罩不可关闭断言。

- [ ] 6.2 将状态和回调收敛为：

```swift
enum State: Equatable {
    case checking
    case result(
        site: SiteEntryTimeZoneResult,
        gateways: SiteGatewayCloudTimeZoneBatchState
    )
}

var onDone: (() -> Void)?

func showResult(
    _ site: SiteEntryTimeZoneResult,
    gateways: SiteGatewayCloudTimeZoneBatchState
)
```

- [ ] 6.3 保留现有 checking card 和 Site status card；移除旧 Gateway summary card、`gotItButton`、`laterButton`、`reviewSyncButton`，嵌入 `SiteEntryGatewayTimeZoneStatusView` 并增加单一 `doneButton`。

- [ ] 6.4 将结果卡改为底部 Sheet：左右遵循现有 343pt 设计宽度上限；底部贴 safe area；顶部约束为 `greaterThanOrEqualTo(safeArea.top + 16pt)`；根据内容向上增长。Title、Site 卡、GATEWAYS header、失败卡和 footer 固定，只有 Gateway 行列表设置可压缩高度和滚动。

- [ ] 6.5 `doneButton.isHidden = !gateways.canDismiss`；按钮 handler 再次 guard `canDismiss`。Overlay 不添加背景 tap gesture，不暴露关闭 API 给处理中路径；父控制器继续禁用 interactive pop。

- [ ] 6.6 `update` 时只更新已有 view，不重复建立约束；从 pushing 进入终态时展示 footer，并触发布局动画，确保 Sheet 顶部始终不越过 `safeArea.top + 16pt`。

- [ ] 6.7 运行 overlay contract 和 UI contract，确认旧按钮/key 不再被生产 UI 消费。

- [ ] 6.8 建议 commit（仅获授权后执行）：`feat: update timezone sync result sheet`

---

## Task 7: 在 SiteViewController 串联 Site 与 Gateway 两阶段

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

**Consumes:** Site 决策/结果、远端快照、导入前本地 Gateway 快照、Target Builder、Gateway Coordinator。

**Produces:** 严格的先 Site 后 Gateway 流程、实时弹窗状态、Review sync 失败计数和一次静默 reconcile。

- [ ] 7.1 先扩展 contract 测试，断言：导入前捕获 dirty offset 和 display name；Site 失败分支不启动 Gateway Coordinator；Site 成功才 run；onUpdate 更新 overlay；终态更新 Review sync；成功覆盖参与后续 review；静默刷新只触发一次；不得出现 MeshAPI、`node.timezone =`、`node.timestamp =` 或 `savePropertys()` 的新增 HTTP 成功写入路径。

- [ ] 7.2 将待展示上下文扩展为：

```swift
private struct PendingEntrySyncPresentation {
    let decision: SiteEntryTimeZoneDecision
    let remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot
    let localGatewaySnapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot]
}

private var confirmedGatewayOffsetMinutesByID: [String: Int] = [:]
private var gatewayEntrySyncTask: Task<Void, Never>?
```

在现有 `dirtyTimeOverrides` 捕获发生的同一导入前窗口，从 `gatewayModels` 构建名称与 dirty offset 字典；禁止在 `site.update` 完成后才尝试恢复已经被服务器导入覆盖的 dirty 值。

- [ ] 7.3 增加 Gateway Coordinator lazy property，生产使用 `SiteGatewayCloudTimeZoneAPIClient()`；overlay 只绑定 `onDone` 到 `finishEntrySyncOverlay()`。

- [ ] 7.4 将 `presentPendingEntrySyncOverlayIfPossible()` 的 Task 拆为顺序流程：

1. 展示 checking。
2. await 现有 `entrySyncCoordinator.run(decision)`。
3. 使用 `result.timezone.offsetMinutes`、远端快照、本地快照、确认成功覆盖构建 targets 和初始 batch。
4. Site 结果为 `.failedToUpdateServer`：`batch.failPushing()`，直接展示终态，不调用 Gateway Coordinator。
5. Site 成功且 `batch.requestMACs.isEmpty`：展示无 Gateway 或全 Synced 终态，不调用接口。
6. Site 成功且存在待同步 MAC：先展示含 `Pushing…` 的结果 Sheet，再 await Gateway Coordinator，并通过 `onUpdate` 原位刷新。
7. Gateway 终态后调用统一 reconcile 方法。

建议把步骤 3 至 7 封装为以下私有方法，避免主展示方法继续膨胀：

```swift
private func makeGatewayEntrySyncState(
    presentation: PendingEntrySyncPresentation,
    targetTimeZone: SiteTimeZoneValue
) -> SiteGatewayCloudTimeZoneBatchState

private func runGatewayEntrySyncIfNeeded(
    siteResult: SiteEntryTimeZoneResult,
    presentation: PendingEntrySyncPresentation,
    initialState: SiteGatewayCloudTimeZoneBatchState
) async

private func reconcileGatewayEntrySyncResult(
    _ state: SiteGatewayCloudTimeZoneBatchState,
    targetOffsetMinutes: Int,
    remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot
)
```

- [ ] 7.5 在 reconcile 中只把本批次 `.synced` 且初始为 `requiresSync` 的 ID 写入 `confirmedGatewayOffsetMinutesByID[id] = targetOffsetMinutes`；已初始匹配的行无需新增覆盖。失败数为 0 时设置 Review sync hidden；失败数大于 0 时设置 `.review(serverTimezone: result.timezone, gatewayCount: failedCount)`。

- [ ] 7.6 终态后启动一次 fire-and-forget `performSiteLoad(presentation: .silentGatewayReconcile)`；不得 await 此刷新后才显示 DONE。刷新解析新快照时：

1. 若远端同 ID offset 已等于确认 offset，清除该确认项。
2. 若未匹配，保留确认项，使当前控制器不会被服务器延迟快照重新标记为待同步。
3. Review state 和 Target Builder 都合并传入剩余确认覆盖。

- [ ] 7.7 修正结束与生命周期：`finishEntrySyncOverlay()` 同时取消 Site/Gateway tasks 和两个 coordinator；`viewDidDisappear`/deinit 路径失效 token；只有 `DONE` 走 finish。维持现有返回手势开关恢复和 `continuePostImportNavigationIfNeeded()`。

- [ ] 7.8 运行两个 contract 测试和 `scripts/check_site_sync_gateways.sh`；确认 Site 更新失败、无 Gateway、全已同步、部分失败、全部失败、全部成功五条路径都有静态或纯逻辑证据。

- [ ] 7.9 建议 commit（仅获授权后执行）：`feat: sync gateway timezone after site entry`

---

## Task 8: 工程归属、本地化与完整验证

**Files:**

- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_site_sync_gateways.sh`
- Verify: 本计划列出的全部生产、测试、本地化和资源文件

**Consumes:** Tasks 1–7 的完整改动。

**Produces:** 四 target 可编译、focused tests 全绿、无范围外修改的可交付结果。

- [ ] 8.1 将六个新增 Swift 文件各创建一个 `PBXFileReference`，放入现有 Site Model/View group；每个文件创建四个 `PBXBuildFile` 并分别加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` Sources phase。

- [ ] 8.2 在 `scripts/check_site_sync_gateways.sh` 中加入四组纯 Swift 测试和两组 contract 测试；每组使用唯一 `/tmp` 可执行名，不改变现有检查顺序和 `set -euo pipefail`。

- [ ] 8.3 运行 focused checks：

```bash
./scripts/check_site_sync_gateways.sh
```

- [ ] 8.4 运行本地化和 project contract，确认新增 key 在 English/简体中文各一次，六个 Swift 文件各出现在四个 Sources phase，两个已存在 Gateway SVG 与三个通用 sync SVG 均保留 vector representation。

- [ ] 8.5 串行运行四个 generic iPhoneOS unsigned build，不使用 shell 包装、不重定向日志、不用 Simulator：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

- [ ] 8.6 运行差异检查：

```bash
git diff --check
git status --short
git diff --stat
```

逐文件确认没有新增 Auth/userId、没有修改 SDK、没有修改 Mesh Node 状态、没有格式化无关文件、没有丢失用户原有改动。

- [ ] 8.7 在真机与测试服务器上执行人工验收；此项是交付前的外部验收边界，不能由编译替代：

1. Owner：0、1、长列表、部分已同步、全部需同步。
2. Editor：只出现 Editor Space Gateway；Visitor 无弹窗 Gateway 阶段。
3. Site 上行失败：零次 Gateway update 请求，pending 行全失败。
4. update 接口失败、无效 requestId、status 间歇失败、unknown/NIL、Expired、部分成功、冲突终态、完整超时。
5. Pushing 期间返回、侧滑、点遮罩均不能关闭；终态才出现 DONE。
6. 长列表顶部距离不小于 `safeArea.top + 16pt`，只有 Gateway 行滚动。
7. English/简体中文文案、单复数、MAC 回退和 Dynamic Type 视觉。
8. 终态静默刷新不阻塞 DONE，服务器延迟快照不使本次成功 Gateway 重新进入待同步。

- [ ] 8.8 建议 commit（仅获授权后执行）：`test: verify gateway timezone cloud sync`

---

## 自检清单

### 需求覆盖

- [ ] 弹窗触发范围未扩大，Visitor 保持静默。
- [ ] Site 成功是 Gateway 下发的硬前置条件。
- [ ] 权限、去重、名称回退、请求 MAC 与展示总数规则一致。
- [ ] 请求只发送需同步 MAC，且 body 不含 timezone/Auth/userId。
- [ ] 3 秒轮询、180 秒总超时、状态映射、未知值、单次失败重试和终态冲突均有测试。
- [ ] Pushing 时无 DONE 且无法关闭；终态/无 Gateway 时有 DONE。
- [ ] No gateways、Synced、Failed、失败统计和标题文案完全国际化。
- [ ] 失败数正确进入 Review sync，HTTP 成功不伪造 BLE/Mesh 本地状态。
- [ ] requestId 不持久化，控制器销毁后不恢复旧任务。
- [ ] 静默刷新与当前生命周期成功覆盖不会形成重复弹窗或重复下发。

### 类型与依赖一致性

- [ ] Target Builder、入口策略、Review state 和 UI 使用同一规范化 ID 规则。
- [ ] API Client 只依赖 parser 和 `NetworkRequest`；Coordinator 只依赖协议，不依赖 Moya/UIKit。
- [ ] 状态 reducer 为纯值类型；Coordinator 的 token 检查位于所有异步响应和结束路径。
- [ ] 新 Swift 文件全部进入四 target；测试的 `swiftc` 输入顺序包含全部类型依赖。

### 占位与质量扫描

- [ ] 执行 `rg -n 'TODO|TBD|FIXME|fatalError\("implement|preconditionFailure\("implement'` 检查本次新增生产文件，没有未实现占位。
- [ ] 执行 `rg -n 'Syned|Sync status|LATER|REVIEW SYNC'`，确认旧产品文案不再由该弹窗消费；其他历史页面如仍使用相同词语，按文件范围判断，不做范围外修改。
- [ ] `git diff --check`、focused tests、四 target generic iPhoneOS build 全部通过后，才可以声明代码实现完成。
- [ ] 最终报告明确区分：纯逻辑测试、静态 contract、编译证据、真机视觉、服务器状态轮询和 BLE 补偿页验收。

## 执行交接

计划已拆成可单独验证的任务，可选择以下执行方式：

1. **Subagent-Driven（当前会话）**：用户明确选择后，使用 `superpowers:subagent-driven-development` 逐任务实施并在每个 Task 后复核；共享 `project.pbxproj`、本地化文件与 `SiteViewController.swift` 的步骤仍串行处理。
2. **Separate Session（新会话）**：在独立会话使用 `superpowers:executing-plans`，按 Task 1 到 Task 8 顺序执行并保留检查点。

在用户选择执行方式前，本计划不触发业务代码修改、commit、push 或 merge。
