# Site Entry Time Zone 与 Gateway 权限状态 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在进入 Site 的首次成功 `/sitespace/get/siteprops` 响应中，按 Owner、Editor Spaces、Visitor Spaces 权限仲裁 Site timezone，并只比较权限范围内 Gateway 的 `timezoneOffset`，生成准确的 `result` 或 `gatewaysNeedSync` 状态。

**Architecture:** 在整包导入前由 Response Parser 生成远端 Site/Space/Gateway 只读快照，纯 Policy 负责权限范围、目标 Site timezone 和 Gateway Offset 计数。Coordinator 区分可见 Owner/Editor 流程与静默 Visitor cloud 权威收敛；Overlay 只增加 `Already in sync with server` Site 结果，不承载权限或解析逻辑。

**Tech Stack:** Swift、UIKit、Foundation `TimeZone`、现有 Site props API/SQLite 持久化、独立 `swiftc` 契约测试、Xcode generic iPhoneOS build。

## Global Constraints

- 所有新增或修改的用户可见文案必须同时提供 English 和简体中文。
- Gateway `timezoneOffset` 使用 `(value - 64) × 15` 转为 UTC Offset 分钟。
- Owner 检查全部 Gateway；Editor 只检查 Editor Spaces 绑定 Gateway；Visitor 不检查 Gateway。
- Visitor 使用完整 cloud Site props 与 cloud `updateTimestamp` 权威覆盖本地，清除全部 Site props pending，不上传 cloud，不显示 Sync status。
- Site timezone 发生更新而没有符合权限的 Gateway 时，仍展示普通 `result`；仅 Gateway 分支结束。
- `timezoneOffset` 缺失、非法或 Editor Space 绑定的 Gateway 对象缺失时，按待同步计数。
- 本期不实现 `REVIEW SYNC` 后续导航、扫描、BLE/Mesh 或 Gateway 写入。
- 保持每个 `SiteViewController` 实例只消费首次成功响应。
- 不修改依赖或 target 配置，不格式化无关文件。
- 不自动 commit、push 或 merge；每个任务使用测试结果与 `git diff` 作为检查点。

---

### Task 1: 解析 Site、Space 权限与 Gateway Offset 远端快照

**Files:**

- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`

**Interfaces:**

- Consumes: `/get/siteprops` 的 `role`、`siteName`、`imageId`、`timezone`、`updateTimestamp`、`spaces[].role`、`spaces[].gatewayId`、`gateways[].macAddress`、`gateways[].timezoneOffset`。
- Produces: `SiteEntrySpaceAccessSnapshot`、`SiteEntryGatewayTimeZoneSnapshot` 和扩展后的 `SiteEntryTimeZoneRemoteSnapshot`。

- [ ] **Step 1: 扩充 Parser 失败测试**

在 `testResponseParser()` 中固定以下输入与断言：

```swift
let snapshot = SiteEntryTimeZoneSyncResponseParser.parse(siteData: [
    "role": "visitor",
    "siteName": "Remote Site",
    "imageId": 7,
    "timezone": "Asia/Singapore (UTC+08:00)",
    "updateTimestamp": 101,
    "spaces": [
        ["uuid": "editor-space", "role": "editor", "gatewayId": " AA:BB "],
        ["uuid": "visitor-space", "role": "visitor", "gatewayId": "CC:DD"]
    ],
    "gateways": [
        ["macAddress": "aa:bb", "timezoneOffset": 96],
        ["macAddress": "cc:dd", "timezoneOffset": 64],
        ["macAddress": "ee:ff", "timezoneOffset": true]
    ]
])
require(snapshot?.values.siteName == "Remote Site", "Expected complete remote Site props")
require(snapshot?.spaces.first?.gatewayId == "aa:bb", "Gateway IDs must be normalized")
require(snapshot?.gateways[0].offsetMinutes == 480, "96 must decode to UTC+08:00")
require(snapshot?.gateways[1].offsetMinutes == 0, "64 must decode to UTC+00:00")
require(snapshot?.gateways[2].offsetMinutes == nil, "Bool must be invalid")
```

继续覆盖 `NSNumber`、数字字符串、负偏移编码、缺失字段、非整数、`-1`、`256`、重复大小写 Gateway ID 和空白 ID。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 因现有 Parser 仍要求 `gatewaySyncFlag`、且远端快照没有 spaces/完整 Site props/Gateway Offset 字段而失败。

- [ ] **Step 3: 实现最小 Parser 模型与转换**

使用以下稳定接口：

```swift
struct SiteEntrySpaceAccessSnapshot: Equatable {
    let role: SiteEntryRole
    let gatewayId: String?
}

struct SiteEntryGatewayTimeZoneSnapshot: Equatable {
    let id: String?
    let offsetMinutes: Int?
}

struct SiteEntryTimeZoneRemoteSnapshot: Equatable {
    let role: SiteEntryRole
    let values: SitePropsValues
    let timestamp: Int64
    let spaces: [SiteEntrySpaceAccessSnapshot]
    let gateways: [SiteEntryGatewayTimeZoneSnapshot]
}
```

Parser 删除 `gatewaySyncFlag` 参数，直接解析响应。Gateway ID 使用去除首尾空白后的小写形式；`timezoneOffset` 只接受可无损转为 `UInt8` 的整数或数字字符串，Bool 明确拒绝，再转换为分钟。

- [ ] **Step 4: 运行测试并确认 Parser GREEN**

重复 Step 2 命令。Expected: Parser 相关断言通过；旧 Policy 断言若因类型迁移失败，则只修复测试构造器到新快照接口，不提前实现 Task 2 行为。

- [ ] **Step 5: 检查任务差异**

Run: `git diff --check`

Expected: 无 whitespace error；差异只包含 Parser、Policy 测试和两份已批准文档。

---

### Task 2: 实现权限范围、Site 仲裁与 Gateway 统计纯策略

**Files:**

- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`

**Interfaces:**

- Consumes: Task 1 的远端快照、`SiteEntryTimeZoneLocalSnapshot`。
- Produces: Owner/Editor/Visitor 决策、`.showGatewayStatus`、`.useVisitorRemote`、`.alreadyInSync` 和权限过滤后的 `SiteEntryGatewaySummary`。

- [ ] **Step 1: 写完整权限与状态矩阵失败测试**

至少加入以下独立断言：

```swift
require(
    equalOwnerDecision(gatewayOffsets: [480]) == .noAction,
    "Equal Site and matching Gateway must enter normally"
)
require(
    isGatewayOnly(equalOwnerDecision(gatewayOffsets: [480, 0]), pending: 1),
    "Equal Site with one mismatched Gateway must show Already in sync"
)
require(
    editorPendingCount(editorGatewayIds: ["a"], gateways: [("a", 0), ("b", 0)]) == 1,
    "Editor must ignore Visitor-only Gateway b"
)
require(
    isVisitorRemote(visitorDecision(localTime: 200, remoteTime: 100)),
    "Visitor must use cloud even when App timestamp is newer"
)
```

补充：Owner 全量、Editor/Visitor 混合 Spaces、Gateway 重复绑定去重、Editor 绑定对象缺失、非法 Offset、无 Gateway、cloud 较新、App 较新、timestamp 相等冲突、仅一端 timezone 有效、Visitor cloud timezone 无效。

- [ ] **Step 2: 运行测试并确认 Policy RED**

重复 Task 1 Step 2 命令。Expected: 因缺少权限范围、新决策和按目标 Offset 统计而失败。

- [ ] **Step 3: 实现最小纯策略**

固定决策与结果接口：

```swift
enum SiteEntryTimeZoneDecision: Equatable {
    case noAction
    case showGatewayStatus(timezone: SiteTimeZoneValue, gateway: SiteEntryGatewaySummary)
    case useRemote(timezone: SiteTimeZoneValue, remoteTimestamp: Int64, gateway: SiteEntryGatewaySummary)
    case useLocal(snapshot: SitePropsUpdateSnapshot, gateway: SiteEntryGatewaySummary)
    case useVisitorRemote(state: SitePropsLocalState)
}

enum SiteEntryTimeZoneSiteResult: Equatable {
    case alreadyInSync
    case updatedFromServer
    case updatedToServer
    case failedToUpdateServer
}
```

权限推导顺序必须为：顶层 Owner → 至少一个 Editor Space → Visitor。Editor Gateway 集合只取 Editor Spaces 的有效 `gatewayId`。Owner 对全部 Gateway 去重比较；Editor 对授权 ID 逐一查找，缺失对象即 pending；Visitor 不生成 Gateway summary。

Visitor 的目标状态使用完整 remote values、remote timestamp、`lastUploadCloudTimestamp = remote.timestamp`、空 pending。Owner/Editor 本地胜出继续生成严格大于两端的 timestamp。

- [ ] **Step 4: 运行测试并确认 Policy GREEN**

重复 Task 1 Step 2 命令。Expected: 输出 `SiteEntryTimeZoneSyncPolicyTests passed`。

- [ ] **Step 5: 检查策略无副作用**

Run:

```bash
rg -n "NetworkRequest|save\(|submit\(|SiteViewController|UIView" SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift
```

Expected: 无匹配，Policy 保持纯函数。

---

### Task 3: Coordinator 与 Site 页面接入可见/静默决策

**Files:**

- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**

- Consumes: Task 2 的五类决策。
- Produces: 可见流程 `run(_:)` 与 Visitor 静默落库 `applySilent(_:)`；Controller 在导入后按决策类型分流。

- [ ] **Step 1: 写 Coordinator 失败测试**

增加以下测试：

```swift
let result = await coordinator.run(.showGatewayStatus(
    timezone: singapore,
    gateway: .pending(1)
))
require(result.site == .alreadyInSync, "Gateway-only flow must report Site already in sync")
require(store.persistCallCount == 0, "Gateway-only flow must not persist")
require(store.submitCallCount == 0, "Gateway-only flow must not upload")

let applied = coordinator.applySilent(.useVisitorRemote(state: remoteState))
require(applied, "Visitor cloud state must persist silently")
require(store.submitCallCount == 0, "Visitor must never upload")
require(store.state.pending.fields.isEmpty, "Visitor must clear Site props pending")
```

同时覆盖 Visitor persist 失败、`run(.useVisitorRemote)` 被拒绝、`applySilent` 不接受其他决策、Gateway-only 仍遵守最短 1 秒展示。

- [ ] **Step 2: 运行 Coordinator 测试并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
/tmp/SiteEntryTimeZoneSyncCoordinatorTests
```

Expected: 因缺少 Gateway-only 与 Visitor silent 接口而失败。

- [ ] **Step 3: 实现 Coordinator 分流**

新增：

```swift
@discardableResult
func applySilent(_ decision: SiteEntryTimeZoneDecision) -> Bool
```

它只接受 `.useVisitorRemote` 并调用 `store.persistState`，不启动 minimum/timeout/business task，不调用 submit。`run(.showGatewayStatus)` 立即生成 `.alreadyInSync` 业务结果，但仍由既有 minimum display gate 发布。

- [ ] **Step 4: 更新 Controller 失败契约**

契约要求：

- Parser 调用不再含 `gatewaySyncFlag: { _ in nil }`。
- 完整导入完成后，Visitor silent decision 先 `applySilent` 再继续既有导航。
- `.showGatewayStatus`、`.useRemote`、`.useLocal` 才调用 `showEntrySyncOverlay`。
- `.noAction` 直接继续导航。
- 每实例一次消费、HUD 顺序、导航锁定、取消逻辑保持不变。

- [ ] **Step 5: 实现 Controller 最小接入并跑 GREEN**

先运行 Coordinator 命令，Expected: `SiteEntryTimeZoneSyncCoordinatorTests passed`。然后运行：

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: Controller/生命周期断言通过；Task 4 新 UI 断言尚未加入。

---

### Task 4: 增加 Already in sync UI 与国际化契约

**Files:**

- Modify: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**

- Consumes: `SiteEntryTimeZoneSiteResult.alreadyInSync`。
- Produces: English `Already in sync with server`、简体中文 `已与服务器同步`，仍由 `.pending` 自动选择 `gatewaysNeedSync`。

- [ ] **Step 1: 增加 UI/本地化失败契约**

要求两份本地化各且仅各一份：

```text
site_entry_sync_already_in_sync_with_server
```

契约同时要求 Overlay 在 `.alreadyInSync` 分支读取该 Key，使用现有成功图标/绿色状态，不改变 `.updatedFromServer`、`.updatedToServer`、`.failedToUpdateServer`。

- [ ] **Step 2: 运行 Contract 并确认 RED**

运行 Task 3 Step 5 的 Contract 命令。Expected: 因缺少 enum 消费或本地化 Key 失败。

- [ ] **Step 3: 实现最小 UI 与本地化**

English 值为 `Already in sync with server`，简体中文值为 `已与服务器同步`。只扩展 Site 结果 switch；Gateway `.pending`、警告图标、`LATER`、`REVIEW SYNC`、关闭回调均保持原实现。

- [ ] **Step 4: 运行 Contract 与本地化语法检查**

Run:

```bash
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: Contract 输出 passed，两份 strings 均输出 `OK`。

---

### Task 5: 全量聚焦回归、静态检查与四品牌构建

**Files:**

- Modify: `docs/260813_1048_site_entry_gateway_timezone_status_analysis.md`
- Modify: `docs/260813_1119_site_entry_timezone_gateway_permission_implementation_plan.md`
- Create: `docs/260813_1119_site_entry_timezone_gateway_permission_implementation_summary.md`

**Interfaces:**

- Consumes: Tasks 1–4 的最终实现与测试。
- Produces: source/test/build 证据和明确的真实服务器/真机验收边界。

- [ ] **Step 1: 运行三项核心测试**

依次执行 Tasks 1、3、4 的 Policy、Coordinator、Contract 命令。Expected: 三项均输出 passed。

- [ ] **Step 2: 回归相关 Site 聚焦测试**

按各测试现有参数运行：

- `SiteTimeZoneUIContractTests`
- `SiteTimeZonePersistenceContractTests`
- `SitePropsEditPolicyTests`
- `SitePropsAPIContractTests`
- `SiteUpdateToastUIContractTests`
- `SiteEditAlertTransitionContractTests`

Expected: 全部通过，且参数顺序使用各测试入口的实际要求。

- [ ] **Step 3: 静态与范围检查**

Run:

```bash
git diff --check
git status --short
rg -n "MeshAPI|TimeSet|gatewayBind|gatewayUnbind|pushViewController" SunSmart/Main/Site/Model/SiteEntryTimeZoneSync* SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift
```

Expected: 无 whitespace error；新流程不包含 Gateway/BLE/Mesh 写入或 Review 路由；改动文件与计划一致。

- [ ] **Step 4: 直接构建四个 generic iPhoneOS target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四项均 `BUILD SUCCEEDED`。不得使用 Simulator、shell 包装或日志重定向。

- [ ] **Step 5: 写实施总结**

总结必须区分：

- 已验证：纯策略、Coordinator、UI 契约、本地化语法、四品牌编译。
- 未验证：Editor Space 用户的服务端 Site props 更新授权、真实 `/get/siteprops` 字段完整性、真机弹窗视觉与交互、真实 Gateway/BLE/Mesh。
- `REVIEW SYNC` 当前只关闭 Overlay，不执行后续业务。
