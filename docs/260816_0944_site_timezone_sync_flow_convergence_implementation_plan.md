# Site Time Zone Sync Flow Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将进入 Site、从 Sites 编辑 Site、从 Site 编辑 Site 三条时区同步路径收敛到唯一的 `SiteTimeZoneSyncStatusView` 和共享 Gateway 同步阶段，同时保留各入口正确的 Site 决策、权限和导航生命周期。

**Architecture:** `SiteTimeZoneSyncStatusView` 只渲染统一展示状态；进入 Site 继续由现有 Entry Policy/Coordinator 完成 App/Cloud Site 仲裁，Edit Site 继续显式提交用户选择。两条路径得到可信 Site timezone 后，都调用共享 `SiteGatewayCloudTimeZoneSessionCoordinator`；Edit 路径额外通过完整 `/sitespace/get/siteprops` 快照确认权限和 Gateway offset。

**Tech Stack:** Swift、UIKit、SnapKit、Swift Concurrency、现有 `NetworkRequest`、现有独立 `swiftc` contract/unit tests、Xcode workspace 多品牌 target。

## Global Constraints

- 所有用户可见文案必须支持 English 和简体中文，禁止硬编码。
- Owner 使用远端全部有效 Gateways；Editor 只使用 Editor Spaces 绑定的 Gateways；Visitor 不自动下发 Gateway。
- Gateway offset 分钟继续使用 `(timezoneOffset - 64) * 15`，不把 IANA/DST 规则当作设备固定 offset。
- Site Cloud 更新失败时不得调用 Gateway datetime update。
- 完整 Site/Gateway 快照不可用或 timezone 与本次目标不一致时必须 fail closed：不得显示 `No gateways`，不得调用 Gateway API。
- 离线 Edit Site 只保留本地 pending，不展示 Gateway 推送进度。
- `Pushing…` 存在时禁止 `DONE`；所有 Gateway 终态或非 Gateway 终态失败后才允许关闭。
- 保留现有全宽结果 Sheet、底部 safe area 白色背景、`DONE` 位置、左侧状态图标与加载动画。
- 两个 Edit Site 入口分别留在 Sites 和 Site，不改变既有返回路由。
- 保留当前 worktree 的未提交修改，不 reset、clean、commit、push 或 merge；除非用户另行授权，不创建 Git commit。
- 验证构建直接运行 generic iPhoneOS `xcodebuild`，关闭签名，不使用 shell 包装、日志重定向或 Simulator。

---

## File Structure

### 新增文件

- `SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift`：唯一 UI 展示状态，不依赖 UIKit。
- `SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshot.swift`：定义不依赖网络实现的完整快照读取结果与 protocol。
- `SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshotProvider.swift`：读取并解析完整 Site/Spaces/Gateways 快照。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneLocalContext.swift`：在导入覆盖前或 Edit 完成后构造 Gateway 名称与可信 dirty offset 上下文。
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift`：共享 Target Builder、下发、轮询、取消与终态汇总。
- `SunSmart/Main/Site/Model/SiteTimeZoneEditSyncCoordinator.swift`：编排 Edit Site 上传、完整快照确认和共享 Gateway 阶段。
- 对应 `Tests/Site/*Tests.swift` 单元测试与 contract tests。

### 主要修改文件

- `SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift`：吸收 Overlay 的完整 checking/result UI。
- `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`：支持 batch、快照不可用和未开始三种 Gateway 展示输入。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：改用统一 View 和共享 Gateway session。
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`：改用 Edit sync coordinator，不再只把 Site submit 映射成布尔状态。
- `SunSmart/Main/Site/Controller/SitesViewController.swift`：注入来源页终态刷新回调。
- `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`、`SiteTimeZoneUIContractTests.swift`、`SiteGatewayCloudTimeZoneUIContractTests.swift`、`SiteUpdateToastUIContractTests.swift`。
- `scripts/check_site_sync_gateways.sh`、`SunSmart.xcodeproj/project.pbxproj`、两份 `Localizable.strings`。

### 删除文件

- `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`：所有调用点迁移且契约 GREEN 后删除。

---

### Task 1: 定义入口无关的展示状态

**Files:**
- Create: `SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift`
- Create: `Tests/Site/SiteTimeZoneSyncPresentationStateTests.swift`
- Modify: `scripts/check_site_sync_gateways.sh`

**Interfaces:**
- Consumes: `SiteTimeZoneValue`、`SiteEntryTimeZoneSiteResult`、`SiteEntryTimeZoneResult`、`SiteGatewayCloudTimeZoneBatchState`。
- Produces: `SiteTimeZoneSyncSitePresentation`、`SiteTimeZoneGatewayPresentation`、`SiteTimeZoneSyncPresentationState`、统一 `canDismiss` 规则。

- [ ] **Step 1: 写展示状态失败测试**

在 `SiteTimeZoneSyncPresentationStateTests.swift` 中覆盖以下断言：

```swift
let timezone = SiteTimeZoneValue(
    ianaId: "Asia/Singapore",
    rawUTCOffset: "+08:00"
)!
let site = SiteTimeZoneSyncSitePresentation(
    timezone: timezone,
    result: .updatedToServer
)

require(!SiteTimeZoneSyncPresentationState.working(.savingSite).canDismiss)
require(!SiteTimeZoneSyncPresentationState.result(
    site: site,
    gateways: .batch(pushingBatch)
).canDismiss)
require(SiteTimeZoneSyncPresentationState.result(
    site: site,
    gateways: .batch(terminalBatch)
).canDismiss)
require(SiteTimeZoneSyncPresentationState.result(
    site: site,
    gateways: .notStarted
).canDismiss)
require(SiteTimeZoneSyncPresentationState.result(
    site: site,
    gateways: .unavailable
).canDismiss)
```

同时验证 `SiteTimeZoneSyncSitePresentation(entryResult:)` 只复制 timezone 与 Site result，不继续把旧 `SiteEntryGatewaySummary` 暴露给 UI。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift \
  Tests/Site/SiteTimeZoneSyncPresentationStateTests.swift \
  -o /tmp/SiteTimeZoneSyncPresentationStateTests
```

Expected: FAIL，因为生产状态文件尚不存在。

- [ ] **Step 3: 实现最小展示模型**

使用以下公开接口：

```swift
struct SiteTimeZoneSyncSitePresentation: Equatable {
    let timezone: SiteTimeZoneValue
    let result: SiteEntryTimeZoneSiteResult

    init(timezone: SiteTimeZoneValue, result: SiteEntryTimeZoneSiteResult)
    init(entryResult: SiteEntryTimeZoneResult)
}

enum SiteTimeZoneSyncWorkingStage: Equatable {
    case checkingSite
    case savingSite
}

enum SiteTimeZoneGatewayPresentation: Equatable {
    case notStarted
    case unavailable
    case batch(SiteGatewayCloudTimeZoneBatchState)
}

enum SiteTimeZoneSyncPresentationState: Equatable {
    case working(SiteTimeZoneSyncWorkingStage)
    case result(
        site: SiteTimeZoneSyncSitePresentation,
        gateways: SiteTimeZoneGatewayPresentation
    )

    var canDismiss: Bool { get }
}
```

`working` 一律不可关闭；`.batch` 委托 `batch.canDismiss`；`.notStarted` 与 `.unavailable` 是终态。

- [ ] **Step 4: 运行测试并确认 GREEN**

执行 Step 2 的编译命令，再运行：

```bash
/tmp/SiteTimeZoneSyncPresentationStateTests
```

Expected: `SiteTimeZoneSyncPresentationStateTests passed`。

- [ ] **Step 5: 将新测试加入聚焦脚本**

在 `scripts/check_site_sync_gateways.sh` 中使用与 Step 2 相同的源文件集合编译并运行该测试；运行脚本，确认既有检查仍通过。

---

### Task 2: 抽取共享 Gateway Cloud 同步会话

**Files:**
- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift`
- Create: `Tests/Site/SiteGatewayCloudTimeZoneSessionCoordinatorTests.swift`
- Modify: `scripts/check_site_sync_gateways.sh`

**Interfaces:**
- Consumes: `SiteGatewayCloudTimeZoneTargetBuilder`、`SiteGatewayCloudTimeZoneSyncCoordinator`、远端快照、本地快照和本会话 confirmed offsets。
- Produces: `SiteGatewayCloudTimeZoneSessionInput`、`SiteGatewayCloudTimeZoneSessionResult`、`run(input:onUpdate:)`、`cancel()`。

- [ ] **Step 1: 写共享会话失败测试**

测试至少覆盖：

```swift
let input = SiteGatewayCloudTimeZoneSessionInput(
    siteID: "site-1",
    targetTimeZone: singapore,
    remoteSnapshot: ownerRemote,
    localSnapshotsByID: localSnapshots,
    confirmedOffsetMinutesByGatewayID: [:]
)

let result = await coordinator.run(input: input) { updates.append($0) }
require(updates.first?.items.map(\.status) == [.synced, .pushing])
require(api.submittedMACs == ["pending-mac"])
require(result?.terminalState.items.map(\.status) == [.synced, .synced])
require(result?.confirmedOffsetMinutesByGatewayID["pending-mac"] == 480)
```

还要覆盖：无待同步项不调用 API、失败项生成 `SiteGatewayTimeZoneReviewContext`、取消返回 nil、第二次运行隔离第一次迟到更新、Visitor 目标为空。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift \
  Tests/Site/SiteGatewayCloudTimeZoneSessionCoordinatorTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneSessionCoordinatorTests
```

Expected: FAIL，因为共享会话类型不存在。

- [ ] **Step 3: 定义输入与结果**

```swift
struct SiteGatewayCloudTimeZoneSessionInput: Equatable {
    let siteID: String
    let targetTimeZone: SiteTimeZoneValue
    let remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot
    let localSnapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot]
    let confirmedOffsetMinutesByGatewayID: [String: Int]
}

struct SiteGatewayCloudTimeZoneSessionResult: Equatable {
    let initialState: SiteGatewayCloudTimeZoneBatchState
    let terminalState: SiteGatewayCloudTimeZoneBatchState
    let confirmedOffsetMinutesByGatewayID: [String: Int]
    let reviewContext: SiteGatewayTimeZoneReviewContext?
}
```

`confirmedOffsetMinutesByGatewayID` 必须包含 input 中仍有效的 confirmed offsets，并合并本次由 initial `pushing` 收敛为 terminal `synced` 的目标；调用方用该完整字典替换当前会话缓存，不做重复增量推导。

- [ ] **Step 4: 实现 session-token 隔离与共享编排**

```swift
@MainActor
final class SiteGatewayCloudTimeZoneSessionCoordinator {
    init(syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator)

    func run(
        input: SiteGatewayCloudTimeZoneSessionInput,
        onUpdate: @escaping @MainActor (SiteGatewayCloudTimeZoneBatchState) -> Void
    ) async -> SiteGatewayCloudTimeZoneSessionResult?

    func cancel()
}
```

实现顺序必须是：生成 token、取消旧 run、构建 targets、立即回调 initial state、无 request MAC 时直接完成、有 request MAC 时调用现有 coordinator、只接受当前 token 的更新、根据 initial pushing IDs 与 terminal synced IDs 生成 confirmed offsets、通过现有 `SiteGatewayTimeZoneReviewContext.make` 生成失败上下文。

- [ ] **Step 5: 运行测试并确认 GREEN**

执行 Step 2 的编译命令和：

```bash
/tmp/SiteGatewayCloudTimeZoneSessionCoordinatorTests
```

Expected: 所有共享会话用例通过。

- [ ] **Step 6: 接入聚焦脚本**

把新测试加入 `scripts/check_site_sync_gateways.sh`，紧跟现有 Gateway sync coordinator tests，确保依赖顺序可读。

---

### Task 3: 提供完整远端快照与共享本地 Gateway 上下文

**Files:**
- Create: `SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshot.swift`
- Create: `SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshotProvider.swift`
- Create: `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneLocalContext.swift`
- Create: `Tests/Site/SiteTimeZoneSnapshotProviderContractTests.swift`
- Modify: `Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift`
- Modify: `scripts/check_site_sync_gateways.sh`

**Interfaces:**
- Consumes: `.siteInfo(siteId:)`、`SiteEntryTimeZoneSyncResponseParser`、`GatewayModel.load(siteId:)`、`MeshNetwork.load`、`SyncGatewaysDirtyTimeOverridePolicy`。
- Produces: `SiteTimeZoneRemoteSnapshotFetchResult`、`SiteTimeZoneRemoteSnapshotProviding`、`SiteGatewayCloudTimeZoneLocalContext`、`SiteGatewayCloudTimeZoneLocalContextBuilder.make(...)`。

- [ ] **Step 1: 写 Provider contract 的失败断言**

先在不依赖 `NetworkRequest` 的 `SiteTimeZoneRemoteSnapshot.swift` 定义：

```swift
protocol SiteTimeZoneRemoteSnapshotProviding {
    func retrieve(siteID: String) async -> SiteTimeZoneRemoteSnapshotFetchResult
}

enum SiteTimeZoneRemoteSnapshotFetchResult: Equatable {
    case success(SiteEntryTimeZoneRemoteSnapshot)
    case unavailable
}
```

Contract 同时断言 concrete provider 调用 `.siteInfo(siteId: siteID)`，只从 response `data` 读取字典并调用 `SiteEntryTimeZoneSyncResponseParser.parse`；请求失败、缺失 data 或 parser 失败全部返回 `.unavailable`，不得构造空 Gateway snapshot。

- [ ] **Step 2: 运行 Provider contract 并确认 RED**

Run:

```bash
swiftc -parse-as-library \
  Tests/Site/SiteTimeZoneSnapshotProviderContractTests.swift \
  -o /tmp/SiteTimeZoneSnapshotProviderContractTests
/tmp/SiteTimeZoneSnapshotProviderContractTests \
  SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshot.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshotProvider.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneLocalContext.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: FAIL，因为三个生产文件尚不存在。

- [ ] **Step 3: 实现远端 Provider**

```swift
struct SiteTimeZoneRemoteSnapshotProvider: SiteTimeZoneRemoteSnapshotProviding {
    let networkRequest: NetworkRequest

    init(networkRequest: NetworkRequest = .shared)

    func retrieve(siteID: String) async -> SiteTimeZoneRemoteSnapshotFetchResult
}
```

不在 Provider 内调用 `site.update(siteJsonData:)`，避免读取职责隐式变成整站覆盖写入。

- [ ] **Step 4: 写本地上下文测试/contract**

定义并验证：

```swift
struct SiteGatewayCloudTimeZoneLocalContext: Equatable {
    let snapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot]
    let dirtyOverridesByID: [String: SyncGatewayDirtyTimeOverride]
}

@MainActor
enum SiteGatewayCloudTimeZoneLocalContextBuilder {
    static func make(
        site: SiteData,
        remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot,
        targetTimeZone: SiteTimeZoneValue
    ) -> SiteGatewayCloudTimeZoneLocalContext
}
```

要求权限范围来自 remote snapshot；本地 Gateway 只提供名称和 dirty offset。无法解析 Mesh/Node 时仍保留 Gateway 名称，但 `dirtyOffsetMinutes` 为 nil。

- [ ] **Step 5: 将 SiteViewController 私有逻辑迁到 Builder**

用 Builder 替换 `captureDirtyGatewayTimeOverrides` 与 `makeLocalGatewayTimeZoneSnapshots` 中重复的候选构造；保留 `restoreDirtyGatewayTimeOverrides`，并改为消费 `context.dirtyOverridesByID`。Entry 仍必须在 `await site.update(...)` 前创建 context。

- [ ] **Step 6: 运行 Provider contract 和 Gateway target tests**

运行 Step 2 命令、现有 `/tmp/SiteGatewayCloudTimeZoneTargetTests` 以及完整 `scripts/check_site_sync_gateways.sh`。

Expected: 快照不可用不会降级为空列表；Owner/Editor/Visitor 和 dirty offset 优先级全部保持 GREEN。

---

### Task 4: 实现 Edit Site 专用 Site 阶段编排

**Files:**
- Create: `SunSmart/Main/Site/Model/SiteTimeZoneEditSyncCoordinator.swift`
- Create: `Tests/Site/SiteTimeZoneEditSyncCoordinatorTests.swift`
- Modify: `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`
- Modify: `scripts/check_site_sync_gateways.sh`

**Interfaces:**
- Consumes: `SitePropsUpdateSnapshot`、可注入 Site submit、remote snapshot provider、本地 snapshots provider、共享 Gateway session。
- Produces: `SiteTimeZoneEditSyncOutcome`、`run(snapshot:onUpdate:)`、`cancel()`。

- [ ] **Step 1: 写 Edit flow 失败测试**

使用 fake submitter/provider/session 覆盖：

```swift
let outcome = await coordinator.run(snapshot: timezoneSnapshot) {
    updates.append($0)
}

require(updates.first == .working(.savingSite))
require(updates.contains(.result(
    site: updatedToServerSite,
    gateways: .batch(initialPushingState)
)))
require(outcome == .completed(sessionResult))
```

还必须验证：

- Site submit false -> `.siteFailed`，remote provider 与 Gateway session 调用次数均为 0。
- remote `.unavailable` -> `.gatewayUnavailable`，Gateway session 调用次数为 0。
- remote timezone 不等于 snapshot target -> `.gatewayUnavailable`。
- remote Visitor -> 空 batch、Gateway API 不提交。
- run 被取消后不再发 UI 更新。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneRemoteSnapshot.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneEditSyncCoordinator.swift \
  Tests/Site/SiteTimeZoneEditSyncCoordinatorTests.swift \
  -o /tmp/SiteTimeZoneEditSyncCoordinatorTests
```

Expected: FAIL，因为 Edit flow coordinator 尚不存在。测试只编译 `SiteTimeZoneRemoteSnapshot.swift` 中的抽象接口和 fake；concrete provider 继续由 Task 3 contract 与 App 构建验证。

- [ ] **Step 3: 定义可测试依赖接口**

```swift
@MainActor
protocol SiteTimeZoneEditSubmitting: AnyObject {
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}

enum SiteTimeZoneEditSyncOutcome: Equatable {
    case siteFailed
    case gatewayUnavailable
    case completed(SiteGatewayCloudTimeZoneSessionResult)
}
```

将 `extension SitePropsEditCoordinator: SiteTimeZoneEditSubmitting {}` 放在 `SitePropsEditCoordinator.swift`，避免纯 Coordinator 单元测试必须编译数据库依赖。本地 snapshots 通过构造器闭包注入；production 闭包调用 Task 3 Builder，测试闭包返回固定字典。

- [ ] **Step 4: 实现 Edit flow coordinator**

```swift
@MainActor
final class SiteTimeZoneEditSyncCoordinator {
    init(
        siteID: String,
        submitter: SiteTimeZoneEditSubmitting,
        remoteProvider: SiteTimeZoneRemoteSnapshotProviding,
        gatewaySession: SiteGatewayCloudTimeZoneSessionCoordinator,
        makeLocalSnapshots: @escaping @MainActor (
            SiteEntryTimeZoneRemoteSnapshot,
            SiteTimeZoneValue
        ) -> [String: SiteGatewayCloudTimeZoneLocalSnapshot]
    )

    func run(
        snapshot: SitePropsUpdateSnapshot,
        onUpdate: @escaping @MainActor (SiteTimeZoneSyncPresentationState) -> Void
    ) async -> SiteTimeZoneEditSyncOutcome?

    func cancel()
}
```

处理顺序固定为：校验 snapshot 含 timezone、发出 saving、submit、构造 Site result、retrieve 完整 snapshot、校验 snapshot timezone 等于目标、通过注入闭包创建 local snapshots、运行 Gateway session、把每次 batch 映射到统一 UI state、返回终态 outcome。Production 闭包捕获当前 `SiteData` 并调用 Task 3 Builder；Coordinator 本身不依赖数据库类型。

- [ ] **Step 5: 运行测试并确认 GREEN**

运行 Step 2 命令与二进制，随后把测试加入 `scripts/check_site_sync_gateways.sh`。

---

### Task 5: 将 Overlay UI 合并进 SiteTimeZoneSyncStatusView

**Files:**
- Modify: `SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift`
- Modify: `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- Modify: `Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `SiteTimeZoneSyncPresentationState`。
- Produces: `show(in:)`、`update(state:)`、`onDone`，以及 Gateway `update(_ presentation:)`。

- [ ] **Step 1: 先改 UI contracts 并确认 RED**

把原 Overlay 布局断言迁到 `SiteTimeZoneSyncStatusView`：全宽 Sheet、safe-area 白底、checking card、Site result、动态 Gateway viewport、61pt terminal Footer、`DONE` guard、无背景点击关闭。

把旧状态断言从：

```swift
case saving
case success
case failure
```

改为：

```swift
func update(state: SiteTimeZoneSyncPresentationState)
var onDone: (() -> Void)?
```

运行三个 contract 二进制，Expected: RED，因为状态视图尚未承载 Overlay UI。

- [ ] **Step 2: 扩展 Gateway presentation UI**

为 `SiteEntryGatewayTimeZoneStatusView` 增加：

```swift
func update(_ presentation: SiteTimeZoneGatewayPresentation)
```

规则：

- `.batch` 继续调用当前列表/空状态/失败统计实现。
- `.unavailable` 显示独立失败说明，不显示 `No gateways`，不构造伪 Gateway 行。
- `.notStarted` 由父 View 隐藏 Gateway 区域，Gateway View 不自行猜测 Site 失败原因。

同步加入以下本地化，供本 Task 的 UI contract 直接验证：

```text
site_time_zone_gateway_check_unavailable_title
English: Unable to check gateways
简体中文：无法检查网关

site_time_zone_gateway_check_unavailable_message
English: Gateway time zones could not be verified. Try again from the Site.
简体中文：无法验证网关时区，请稍后在场所页面重试。
```

- [ ] **Step 3: 迁移 Overlay UI 到唯一状态视图**

迁移而不是重新设计以下能力：

- checking card 与 `site_entry_sync_loading` 动画。
- 结果 Sheet 的全宽、安全区白底、阴影和动态高度。
- Site 状态映射 `alreadyInSync/updatedFromServer/updatedToServer/failedToUpdateServer`。
- Gateway component 与 preferred-height callback。
- `Pushing…` 时 Footer 高度 0，终态时 61。
- `show(in parentView: UIView? = nil)` 的 activeWindow fallback。

`doneButtonDidTap` 必须先检查 `state.canDismiss`；有 `onDone` 时交给宿主处理，没有 callback 时自行从 superview 移除，供 Edit flow 使用。

- [ ] **Step 4: 删除旧 Site-only 固定 Gateway 卡**

删除 `SiteTimeZoneSyncStatusView` 当前固定 `gatewayCard`、`site_no_gateways` 和布尔 `success/failure` 映射；所有 No gateways 都必须来自 `.batch` 且授权 targets 为空。

- [ ] **Step 5: 运行 UI contracts 并确认 GREEN**

运行：

```bash
./scripts/check_site_sync_gateways.sh
```

Expected: Gateway 行图标、Dynamic Type、全宽、安全区、Footer 和 Edit full-screen contracts 全部通过。此时暂不删除 Overlay 文件，因为 Site 入口尚未迁移。

---

### Task 6: Site 入口迁移到统一 View 和共享 Gateway session

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`
- Modify: `scripts/check_site_sync_gateways.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Delete: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`

**Interfaces:**
- Consumes: Entry Policy/Coordinator、Task 3 local context、Task 2 Gateway session、Task 5 unified status View。
- Produces: 行为不变的 Site-entry presentation、导航锁、取消、Review sync 与静默刷新。

- [ ] **Step 1: 修改 Entry contract 并确认 RED**

Contract 要求：

- `SiteViewController` 的 lazy view 类型为 `SiteTimeZoneSyncStatusView`。
- checking 使用 `.working(.checkingSite)`。
- Entry result 转成 `SiteTimeZoneSyncSitePresentation(entryResult:)`。
- Gateway 阶段调用 `SiteGatewayCloudTimeZoneSessionCoordinator.run`。
- 不再直接创建 `SiteGatewayCloudTimeZoneSyncCoordinator` 或维护 `gatewayEntrySyncTask`。
- 项目和脚本不再引用 `SiteEntryTimeZoneSyncOverlay.swift`。

运行旧 contract，Expected: RED。

- [ ] **Step 2: 替换 Site 页面展示对象**

将 `entrySyncOverlay` 改为统一 status view，并保留：

```swift
statusView.onDone = { [weak self] in
    self?.finishEntryTimeZoneSyncStatus()
}
```

展示时仍传入 `navigationController?.view ?? view`，避免改变当前覆盖范围和 Site 页面生命周期。

- [ ] **Step 3: 使用共享 local context 和 Gateway session**

Entry 在完整 import 前构造 local context；Site stage 完成后生成 session input。`onUpdate` 只在当前 entry session token 有效时更新 View。终态使用 `SiteGatewayCloudTimeZoneSessionResult` 更新：

- `confirmedGatewayOffsetMinutesByID`。
- `gatewayTimeZoneReviewContext`。
- `refreshCurrentGatewayTimeZoneReviewProjection()`。
- 必要的 `.silentGatewayReconcile`。

- [ ] **Step 4: 删除 Controller 内重复编排**

删除或收缩以下旧职责：

- `gatewayEntrySyncCoordinator`。
- `gatewayEntrySyncTask`。
- `makeGatewayEntrySyncState`。
- `startGatewayEntrySyncIfNeeded`。
- 只为旧会话存在的重复终态汇总代码。

保留 Entry 专属的 Site 仲裁、导航锁、页面消失取消和 post-import navigation。

- [ ] **Step 5: 删除 Overlay 和工程引用**

使用 `apply_patch` 删除 Overlay 文件，并从 `project.pbxproj` 的 PBXFileReference、PBXBuildFile、PBXGroup 与四个 PBXSourcesBuildPhase 移除对应条目。不得删除 `SiteTimeZoneSyncStatusView` 或 Gateway status view 的四 target membership。

- [ ] **Step 6: 更新脚本参数并运行聚焦回归**

`SiteEntryTimeZoneSyncContractTests` 的第一个参数改为 `SiteTimeZoneSyncStatusView.swift`；更新 `SiteTimeZoneUIContractTests` 的 target membership 文件名断言。

Run:

```bash
./scripts/check_site_sync_gateways.sh
```

Expected: Entry、Review sync、统一 UI 和 Gateway coordinator 检查全部通过。

---

### Task 7: Edit Site 接入完整 Gateway 流程

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SitesViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Modify: `Tests/Site/SiteUpdateToastUIContractTests.swift`

**Interfaces:**
- Consumes: `SiteTimeZoneEditSyncCoordinator` 和统一 status view。
- Produces: 两个 Edit 入口相同的同步业务链，以及来源页专属终态刷新 callback。

- [ ] **Step 1: 修改 Edit routing contracts 并确认 RED**

Contract 必须要求 `finishTimeZoneCommit`：

- 创建 `.working(.savingSite)` 的统一 status view。
- 调用 `SiteTimeZoneEditSyncCoordinator.run`，而不是直接 `await coordinator.submit` 后映射 Bool。
- 每次 coordinator update 都调用 `statusView.update(state:)`。
- terminal callback 不改变原 Sites/Site 返回路由。
- 离线路径不创建 status view 或 Gateway session。

Expected: 旧实现 RED。

- [ ] **Step 2: 增加来源页终态回调**

在 `SiteEditViewController` 增加：

```swift
var timeZoneSyncDidFinish: ((SiteTimeZoneEditSyncOutcome) -> Void)?
```

在 Edit modal 完全 dismiss 后捕获 callback、status view 和 coordinator 到 Task 生命周期中；Task 结束时通知 callback。不要让已 dismiss 的 Edit controller 成为会话唯一 owner。

- [ ] **Step 3: 替换 finishTimeZoneCommit**

在线且 snapshot 存在时：

1. 创建 status view，设置 `.working(.savingSite)` 并 `show()`。
2. 创建 production remote provider、Gateway session 和 Edit coordinator。
3. 运行 coordinator 并把所有更新发送到 status view。
4. status view 无外部 `onDone` 时终态自行关闭。

在线但 snapshot 缺失继续视为 Site failure，不启动 Gateway。离线保持当前 pending 规则且不展示推送 UI。

- [ ] **Step 4: 注入两个来源页刷新策略**

- `SitesViewController`：终态调用现有 `reloadSiteData(site)`，不新增 Review sync 入口。
- `SiteViewController`：终态触发 `.silentGatewayReconcile`，刷新 `latestTimeZoneRemoteSnapshot`、名称颜色和 Review sync；必须避免再次展示 Entry overlay。

两者都保留 `finishEditingHandler` 的现有 modal dismissal 和 `completion(self.view)` 路由契约。

- [ ] **Step 5: 验证失败文案复用边界**

确认 Edit flow 使用 Task 5 已加入的 `site_time_zone_gateway_check_unavailable_title/message`；Site submit failure 沿用现有 Site failed 文案；`.notStarted` 隐藏 Gateway 区域，不新增重复文案。

- [ ] **Step 6: 运行 Edit 和本地化回归**

运行：

```bash
./scripts/check_site_sync_gateways.sh
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

并运行现有 Site props/edit contracts。Expected: ordinary Site update Toast 完全不变，timezone 路径统一进入 Gateway flow。

---

### Task 8: 工程集成、差异审计与四品牌验证

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_site_sync_gateways.sh`
- Verify: 本计划涉及的所有生产、测试、本地化和文档文件

**Interfaces:**
- Consumes: Tasks 1-7 的最终实现。
- Produces: 四品牌共享 Sources/Resources 一致、聚焦测试通过、generic iPhoneOS 构建证据。

- [ ] **Step 1: 检查工程 membership**

确认每个新增 Swift 生产文件均有四个 `PBXBuildFile` 并进入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Sources；确认 Overlay 为零引用；确认两份 Localizable 仍由四个 target 使用。

- [ ] **Step 2: 运行完整聚焦测试**

Run:

```bash
./scripts/check_site_sync_gateways.sh
```

Expected: `SiteSyncGateways checks passed`。

- [ ] **Step 3: 运行关联 Site contracts**

运行脚本未覆盖的 `SitePropsEditPolicyTests`、`SitePropsAPIContractTests`、`SitePropsAPIResponseParserTests`、`SiteTimeZonePersistenceContractTests`、`SiteUpdateToastUIContractTests` 和 `SiteEditAlertTransitionContractTests`，沿用仓库现有 `swiftc` 参数与二进制命令。

Expected: 所有检查通过，普通 name/image update、离线 pending、dismiss 顺序均无回归。

- [ ] **Step 4: 运行静态差异检查**

Run:

```bash
git diff --check
git status --short
```

确认只包含批准范围和既有未提交文件；不得覆盖用户已有文档或其他改动。

- [ ] **Step 5: 串行构建四个 iPhoneOS scheme**

Run each command directly and serially:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四个命令分别输出 `BUILD SUCCEEDED`。如果遇到 `build.db ... database is locked`，先确认没有并行 Xcode/CLI build，再串行重试；不得把锁错误当作源码失败。

- [ ] **Step 6: 人工验收矩阵**

在真实服务器和真机覆盖：

- 进入 Site：Site 已一致但部分 Gateway pending。
- Sites -> Edit Site：无 Gateway、全部一致、部分 pending、部分失败。
- Site -> Edit Site：相同四种 Gateway 情形，并检查 Review sync 即时刷新。
- Site upload 失败、完整 snapshot 失败、snapshot timezone 不一致。
- Owner、Editor Spaces、Visitor/无操作范围。
- 三分钟超时、App 前后台切换、重复会话取消。
- `Pushing…` 左侧加载动画、`Synced`/`Failed` 左侧图标、右侧纯文字。
- 全宽 Sheet、底部白色 safe area、`DONE` 位置、英文/简体中文、小屏 iPhone、常规 iPhone、iPad 和 Dynamic Type。

记录边界：构建、contract、HTTP requestId 或服务器 Gateway success 都不能单独证明真实 Mesh Node timezone/timestamp 已更新。

---

## Plan Self-Review Result

- 规格覆盖：唯一 View、三入口、权限、完整快照、Site 失败、快照失败、离线、Gateway 状态、Review sync、导航、取消、四品牌均有对应 Task。
- 类型一致性：统一 UI 只消费 `SiteTimeZoneSyncPresentationState`；共享 Gateway session 的输入/结果被 Entry 与 Edit 两条路径共同使用。
- 范围控制：不重写 Entry App/Cloud 仲裁，不修改 Gateway API/轮询协议，不新增 Sites Review sync，不改普通 Site Update Toast。
- 无未决占位：失败语义、本地化文案、测试命令、构建命令和人工验收矩阵均已明确。
