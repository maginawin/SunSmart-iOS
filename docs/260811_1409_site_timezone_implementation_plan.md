# Site Time Zone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution and review checkpoints.

**目标：** 在四个品牌 target 中启用 Site 专用编辑页，增加固定 UTC offset 的 Site Time Zone、Local time、时区选择、retrieve/update 分量同步及可持久化失败重试，同时保持现有整包 Site 同步流程不变。

**架构：** 将 timezone 解析、catalog/search、timestamp/pending/merge 规则拆成 Foundation-only 策略，使用独立 `swiftc` 测试覆盖；`SiteData` 继续作为本地真值，数据库保存完整 timezone 和 pending 元数据；Edit Site 通过专用 API client/coordinator 进入、保存和重试；UIKit 控制器只负责草稿、路由和 Figma 状态展示。

**技术栈：** Swift、Foundation、UIKit、SnapKit、SQLite.swift、Moya、SwiftyJSON、独立 `swiftc` focused tests、源码 contract tests、Xcode generic iPhoneOS build。

---

## 0. 执行约束与真值来源

- 需求与行为真值：`docs/260811_1351_site_timezone_design.md`。
- 计划执行方式：当前会话 Inline Execution；不使用 subagents。
- 严格执行 RED → GREEN → REFACTOR；每个任务先看到预期失败，再写最小实现。
- 未经用户明确授权，不执行 `git commit`、`git push` 或 `git merge`。每个任务只记录建议提交信息。
- 保留现有 `SunSmart.xcodeproj/project.pbxproj` 和 `SunSmart/all_utc_timezones.json` 改动，不清理 Xcode 已产生的无关 diff。
- 不新增 Auth 信息，不修改 Timed、Gateway Time Set，不让 Site timezone 参与 Mesh/Gateway 同步。
- 不增加 `needsFullSiteSync` 或第二套版本时间；始终只维护 `site.lastUpdate`。
- 不修改 `CloudSynchronizationManager` 的整包同步成功回调去清除 `pendingSitePropsMask`。
- 新增 Swift 源文件必须同时加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target；新增文案同时维护 English 和简体中文。
- 构建只使用 generic iPhoneOS；不使用 Simulator。

## 1. 预计文件范围

### 新增

- `SunSmart/Common/Data/SiteTimeZoneValue.swift`
- `SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift`
- `SunSmart/Main/Site/Model/SitePropsEditPolicy.swift`
- `SunSmart/Main/Site/Model/SitePropsAPIClient.swift`
- `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`
- `SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift`
- `SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift`
- `SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift`
- `Tests/Site/SiteTimeZoneValueTests.swift`
- `Tests/Site/SiteTimeZoneCatalogTests.swift`
- `Tests/Site/SitePropsEditPolicyTests.swift`
- `Tests/Site/SiteTimeZonePersistenceContractTests.swift`
- `Tests/Site/SitePropsAPIContractTests.swift`
- `Tests/Site/SiteTimeZoneUIContractTests.swift`

### 修改

- `SunSmart/Common/Data/SiteData.swift`
- `SunSmart/Common/Data/Database.swift`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/ExportData.swift`
- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Common/Network/NetowrkReqeustApi.swift`
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- `SunSmart/Main/Site/Controller/SitesViewController.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

### 明确不修改

- `SunSmart/Main/Site/Controller/InfoEditViewController.swift`
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` 的同步路由和 pending 清理行为
- Timed、WiFi Gateway Proxy Ready / Time Set 相关文件

---

## Task 1：建立 timezone 完整值、固定 offset 与 Local time 规则

**Files:**

- Create: `SunSmart/Common/Data/SiteTimeZoneValue.swift`
- Create: `Tests/Site/SiteTimeZoneValueTests.swift`

### Step 1：先写失败测试

在测试中表驱动覆盖：

- `Asia/Singapore (UTC+08:00)`、`Indian/Comoro (UTC+03:00)`、`Etc/UTC (UTC+00:00)`；
- `UTC-03:30`、`UTC+05:45`；
- 空字符串、缺少括号、缺少 `UTC`、无符号、分钟超过 59、绝对值超过 14 小时；
- 相同 offset 但不同 `ianaId` 不相等；
- 固定 offset 的跨日、跨年、正负 offset；
- `yyyy-M-d h:mm:ss a` 和 English AM/PM；
- Local time 只依赖传入 `Date` 和 offset，不调用 IANA 夏令时规则。

计划接口：

```swift
struct SiteTimeZoneValue: Hashable {
    let ianaId: String
    let offsetMinutes: Int

    init?(storageValue: String)
    init?(ianaId: String, rawUTCOffset: String)

    var displayOffset: String { get }       // UTC+08:00
    var storageValue: String { get }        // Asia/Singapore (UTC+08:00)
    func formattedLocalDate(at date: Date) -> String
}
```

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneValueTests.swift -o /tmp/SiteTimeZoneValueTests
```

Expected：因 `SiteTimeZoneValue` 尚不存在而编译失败。

### Step 2：实现最小值对象

- trim 完整输入和 `ianaId`；`ianaId` 不限制为 JSON 中已有值，但不得为空。
- 只接受 `UTC±HH:mm`；分钟为 `00...59`，总 offset 为 `-840...840` 分钟。
- 组装时始终输出两位小时和两位分钟。
- `formattedLocalDate` 使用 `TimeZone(secondsFromGMT:)` 和 `en_US_POSIX`，不使用 `TimeZone(identifier: ianaId)`。
- DateFormatter 不放共享可变全局；由值对象或内部工厂按需创建，避免并发修改。

### Step 3：运行 GREEN 测试

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift Tests/Site/SiteTimeZoneValueTests.swift -o /tmp/SiteTimeZoneValueTests
/tmp/SiteTimeZoneValueTests
```

Expected：`SiteTimeZoneValueTests passed`。

### Step 4：局部复核

- 确认没有 IANA/DST 计算分支。
- 确认不同 `ianaId` 即使 offset 相同仍不相等。
- 建议提交信息：`feat: add site timezone value model`；未经授权不提交。

---

## Task 2：解析 bundled catalog、注入 UTC、搜索与手机默认时区

**Files:**

- Create: `SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift`
- Create: `Tests/Site/SiteTimeZoneCatalogTests.swift`
- Read: `SunSmart/all_utc_timezones.json`

### Step 1：先写 catalog/search 失败测试

计划接口：

```swift
struct SiteTimeZoneCatalogEntry: Equatable, Decodable {
    let region: String
    let ianaId: String
    let utcOffset: String
    var value: SiteTimeZoneValue { get }
}

struct SiteTimeZoneCatalogSection: Equatable {
    let region: String
    let entries: [SiteTimeZoneCatalogEntry]
}

struct SiteTimeZoneCatalog {
    init(data: Data) throws
    var allSections: [SiteTimeZoneCatalogSection] { get }
    func sections(matching query: String) -> [SiteTimeZoneCatalogSection]
    func defaultValue(for phoneTimeZone: TimeZone, at date: Date) -> SiteTimeZoneValue
    static func bundled() throws -> SiteTimeZoneCatalog
}
```

测试读取真实 JSON，断言：

- 原文件 397 条、8 个 Region；
- 注入 `UTC` 首组和唯一 `Etc/UTC / UTC+00:00` 后为 9 组、398 行；
- JSON Region 和组内顺序不变；
- query trim、忽略大小写；
- Region 命中返回整组；ianaId、原始 `+08:00`、展示 `UTC+08:00` 只返回匹配行；
- 空 query 恢复全量；无结果为空；
- JSON 精确 identifier 使用静态 JSON offset；
- UTC 统一得到 `Etc/UTC (UTC+00:00)`；
- JSON 未命中时保留手机 identifier，并以 `secondsFromGMT - daylightSavingTimeOffset` 得到标准 offset。

Run：

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift Tests/Site/SiteTimeZoneCatalogTests.swift -o /tmp/SiteTimeZoneCatalogTests
```

Expected：因 catalog 类型尚不存在而编译失败。

### Step 2：实现 catalog

- Decodable 只读取 `region`、`ianaId`、`utcOffset`，不引入当前不使用的城市/国家国际化字段。
- 解析任一行失败时整体抛错，避免静默丢行。
- UTC 组在内存注入，不修改 JSON 内容。
- 搜索使用 `localizedCaseInsensitiveContains` 或等价不区分大小写包含匹配；Region 命中优先返回整组。
- `bundled()` 从 `Bundle.main.url(forResource: "all_utc_timezones", withExtension: "json")` 读取。
- 手机 fallback 将标准 offset 四舍五入前先确认秒数能被 60 整除；异常时降级到当前 `secondsFromGMT` 的分钟值并限制到合法范围。

### Step 3：运行 GREEN 测试

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift Tests/Site/SiteTimeZoneCatalogTests.swift -o /tmp/SiteTimeZoneCatalogTests
/tmp/SiteTimeZoneCatalogTests SunSmart/all_utc_timezones.json
```

Expected：`SiteTimeZoneCatalogTests passed`，报告 9 groups / 398 entries。

### Step 4：局部复核

- 对 bundled JSON 额外执行 JSON 语法校验。

```bash
jq empty SunSmart/all_utc_timezones.json
```

- 建议提交信息：`feat: add site timezone catalog and search`；未经授权不提交。

---

## Task 3：建立字段 mask、timestamp、retrieve merge 与 update snapshot 纯策略

**Files:**

- Create: `SunSmart/Main/Site/Model/SitePropsEditPolicy.swift`
- Create: `Tests/Site/SitePropsEditPolicyTests.swift`

### Step 1：先写失败测试

计划纯类型：

```swift
struct SitePropsFieldMask: OptionSet {
    let rawValue: Int
    static let siteName: Self
    static let imageId: Self
    static let timezone: Self
}

struct SitePropsValues: Equatable {
    var siteName: String
    var imageId: Int
    var timezone: SiteTimeZoneValue?
}

struct SitePropsPendingState: Equatable {
    var fields: SitePropsFieldMask
    var timestamp: Int64?
}

struct SitePropsRemoteSnapshot: Equatable {
    let values: SitePropsValues
    let timestamp: Int64
    let timezoneWasProvided: Bool
}

struct SitePropsUpdateSnapshot: Equatable {
    let siteId: String
    let fields: SitePropsFieldMask
    let values: SitePropsValues
    let timestamp: Int64
}

struct SitePropsLocalState: Equatable {
    var values: SitePropsValues
    var lastUpdate: Int64
    var lastUploadCloudTimestamp: Int64?
    var pending: SitePropsPendingState
}

struct SitePropsEditDraft: Equatable {
    let original: SitePropsValues
    var values: SitePropsValues
}

struct SitePropsRetrieveMergeResult: Equatable {
    let state: SitePropsLocalState
    let shouldPersist: Bool
}

struct SitePropsCommitPlan: Equatable {
    let targetState: SitePropsLocalState
    let updateSnapshot: SitePropsUpdateSnapshot?
    let hasNewChanges: Bool
    let includesTimezone: Bool
}

enum SitePropsLocalSaveError: Error {
    case databaseWriteFailed
}
```

策略至少暴露：

```swift
enum SitePropsEditPolicy {
    static func changedFields(from original: SitePropsValues, to draft: SitePropsValues) -> SitePropsFieldMask
    static func nextTimestamp(now: Int64, current: Int64) -> Int64
    static func makeUpdateSnapshot(siteId: String, local: SitePropsLocalState, original: SitePropsValues, draft: SitePropsValues, now: Int64) -> SitePropsUpdateSnapshot?
    static func mergeRetrieve(local: SitePropsLocalState, remote: SitePropsRemoteSnapshot) -> SitePropsRetrieveMergeResult
    static func updateResponseMatches(request: SitePropsUpdateSnapshot, response: SitePropsRemoteSnapshot) -> Bool
}
```

测试覆盖：

- name/image/timezone 单项与组合变化；相同 offset 但不同 IANA 计为 timezone 变化；
- `max(now, lastUpdate + 1)` 单调秒级 timestamp；
- 无新变化的纯重试复用 pending timestamp；pending 上产生新修改时字段取并集并升级 timestamp；
- 防御性处理 mask 非空但 pending timestamp 缺失的异常本地状态：按新提交生成单调 timestamp，不发送 0 或缺失 timestamp；
- 无变化且无 pending 不生成请求；
- retrieve：remote 新、本地新、相等 remote 优先；
- pending 全字段在 remote timestamp 不小于 pending timestamp 且值都匹配时清除；
- 任一 pending 字段不匹配时完整本地 props 初始化草稿，不混入 remote 非 pending 字段；
- remote timezone 缺失/空时保留本地 timezone，不创建 pending；
- update 回复必须 timestamp 和所有已发送字段原样匹配；未发送字段忽略；
- update 成功清理仅限 snapshot 仍与当前 pending timestamp/值相同的字段，否则保留新版本。

### Step 2：运行 RED

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
```

Expected：因 policy 类型尚不存在而编译失败。

### Step 3：实现纯策略

- merge 函数不得读写数据库或全局网络状态。
- `timezoneWasProvided == false` 时，remote values 中的 nil 只表示“不覆盖”，不是“清空”。
- 只有所有 pending 字段同时满足 timestamp 与值对账条件才把旧 pending 视为已由云端完成。
- update 响应匹配只比较 request.fields；timezone 使用完整值比较。

### Step 4：运行 GREEN

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
```

Expected：`SitePropsEditPolicyTests passed`。

### Step 5：局部复核

- 将最终设计第 10 节 merge 矩阵逐项映射到测试名，缺一项先补测试。
- 建议提交信息：`feat: add site props merge and pending policy`；未经授权不提交。

---

## Task 4：扩展 SiteData 与数据库，持久化 timezone 和 pending

**Files:**

- Modify: `SunSmart/Common/Data/SiteData.swift`
- Modify: `SunSmart/Common/Data/Database.swift`
- Create: `Tests/Site/SiteTimeZonePersistenceContractTests.swift`

### Step 1：先写 persistence contract

Contract 读取上述两个源码文件并断言：

- `SiteData` 有 `timezone: String?`、`pendingSitePropsMask`、`pendingSitePropsTimestamp`；
- timezone setter 或初始化路径把空字符串规范化为 nil；
- `copy()` 复制 timezone 和 pending；
- SQLite expression、create、旧表 addColumn、loadAll、load、save 六个路径都覆盖三个新增列；
- `pendingSitePropsMask` 旧数据默认 0，timestamp 默认 nil；
- 不新增第二个云端版本 timestamp。

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift
```

Expected：缺少新增字段/迁移路径而失败。

### Step 2：修改 SiteData

- 保存层使用完整字符串，UI/策略层通过 `SiteTimeZoneValue(storageValue:)` 获取结构化值。
- 建议属性：

```swift
var timezone: String?
var pendingSitePropsMask: SitePropsFieldMask = []
var pendingSitePropsTimestamp: Int64?
```

- `copy()` 保留 timezone、pending、pending timestamp；clone 的重置在 Task 5 处理。
- 不把 pending 映射到 `syncCloudError`，两者语义保持独立。

### Step 3：执行兼容迁移

在 `sites` 表增加：

- `timezone TEXT NULL`；
- `pendingSitePropsMask INTEGER NOT NULL DEFAULT 0`；
- `pendingSitePropsTimestamp INTEGER NULL`。

沿用当前 schema.columnDefinitions + addColumn 模式，分别检查列存在性；任何旧数据库都不得因某一列已存在而跳过其他列。

### Step 4：运行 GREEN contract

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift
```

Expected：`SiteTimeZonePersistenceContractTests passed`。

### Step 5：迁移验收边界

- 自动 contract 证明 create/migrate/load/save 路径齐全。
- 在最终真机验收中保留一份升级前数据库：升级启动后验证原 Site/Space/Scene 数量与内容、timezone nil、pending 为空。
- 建议提交信息：`feat: persist site timezone and pending props`；未经授权不提交。

---

## Task 5：新建、克隆、整包 export/import 接入 timezone

**Files:**

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Common/Data/SiteData.swift`
- Modify: `SunSmart/Common/Data/ExportData.swift`
- Modify: `SunSmart/Common/Data/ImportData.swift`
- Modify: `Tests/Site/SiteTimeZonePersistenceContractTests.swift`

### Step 1：扩展失败 contract

增加断言：

- `SiteData.add(name:)` 从 bundled catalog 生成手机默认 timezone；
- catalog 加载失败仍使用手机 identifier + 标准 offset fallback，不让新建 Site 失败；
- clone：源 timezone 有值则继承，无值则生成手机默认；pending mask/timestamp 重置；
- `SiteData.export()` 在 timezone 有效时写入完整 `timezone`；nil 时不写；
- `/get/siteprops` 或整包 import 的缺失/null/空 timezone 不清除本地值；有效完整格式在服务器版本胜出时写入；
- pending 字段永不 export，也不由 cloud import 创建。

### Step 2：运行 RED contract

```bash
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected：新增集成断言失败。

### Step 3：实现新建与克隆

- `SiteData.add(name:)` 在首次 `save()` 前设置 timezone。
- `cloneData()` 在新的 id/timestamp 设置后：继承源 timezone；若源为空，使用手机默认；把 pending mask/timestamp 清空。
- clone 不复制 `lastUploadCloudTimestamp`，继续被视为未首次上传。

### Step 4：实现 export/import

- export 只在 `SiteTimeZoneValue(storageValue:)` 成功时写 `timezone = value.storageValue`。
- import 仅在云端 timezone 为非空且合法时覆盖；缺失/null/空/非法不得清除本地 timezone。
- 不改变现有 timestamp 比较、Mesh key、Space 导入和整包同步调度。

### Step 5：运行 focused 与 contract

```bash
/tmp/SiteTimeZoneValueTests
/tmp/SiteTimeZoneCatalogTests SunSmart/all_utc_timezones.json
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected：全部通过。

### Step 6：局部复核

- 核对 `site.export()` 原有字段和值没有变化，只新增合法 timezone。
- 建议提交信息：`feat: include timezone in site lifecycle and sync export`；未经授权不提交。

---

## Task 6：增加 retrieve/update API 契约与解析

**Files:**

- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift`
- Create: `SunSmart/Main/Site/Model/SitePropsAPIClient.swift`
- Create: `Tests/Site/SitePropsAPIContractTests.swift`

### Step 1：先写 API contract

枚举计划增加：

```swift
case sitePropsRetrieve(siteId: String)
case sitePropsUpdate(siteId: String, props: [String: Any])
```

Contract 断言：

- path 精确为 `/sitespace/retrieve/siteprops` 和 `/sitespace/update/siteprops`；
- retrieve 根字段是 userId/siteId/props，props 的 timezone/imageId/siteName/updateTimestamp 全为 `NSNull()`；
- update 根字段是 userId/siteId/props；
- update props 的 updateTimestamp 必传，其他三项只按 mask 出现；
- 新接口使用普通 JSONEncoding；不误加到现有 gzip header 分支；
- `diagnosticName` 覆盖两个新 case。

### Step 2：运行 RED

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift
```

Expected：新 API case/client 不存在而失败。

### Step 3：实现 API client

计划接口：

```swift
protocol SitePropsAPIClientProtocol {
    func retrieve(siteId: String) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>
    func update(snapshot: SitePropsUpdateSnapshot) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>
}

final class SitePropsAPIClient: SitePropsAPIClientProtocol {
    init(networkRequest: NetworkRequest = .shared)
}
```

- retrieve 只解析 `data.props`；缺字段、错误类型、缺 updateTimestamp 或非空非法 timezone 都返回失败。
- retrieve 的 timezone 缺失/null/空是合法的“未提供有效 timezone”，用 `timezoneWasProvided = false` 表达。
- update 解析 `data`；reply 的已发送字段最终由 `SitePropsEditPolicy.updateResponseMatches` 校验。
- API client 不写 SiteData，不决定 merge，不显示 UI。

### Step 4：运行 GREEN contract 与 policy

```bash
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift
/tmp/SitePropsEditPolicyTests
```

Expected：两个测试均通过。

### Step 5：局部复核

- 用 `NetowrkReqeustApi.parameters` 生成请求样本，确认 `NSNull` 被 JSONEncoding 编码为 JSON null。
- 确认未增加 token/Auth/header。
- 建议提交信息：`feat: add retrieve and update site props APIs`；未经授权不提交。

---

## Task 7：实现 Site props 编辑协调器与可恢复 pending

**Files:**

- Create: `SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift`
- Modify: `Tests/Site/SitePropsEditPolicyTests.swift`
- Modify: `Tests/Site/SitePropsAPIContractTests.swift`

### Step 1：补协调器行为测试/contract

计划接口：

```swift
@MainActor
final class SitePropsEditCoordinator {
    init(site: SiteData, apiClient: SitePropsAPIClientProtocol = SitePropsAPIClient())

    func prepareDraft(online: Bool) async -> SitePropsEditDraft
    func makeCommitPlan(draft: SitePropsEditDraft, online: Bool, now: Int64) -> SitePropsCommitPlan
    func persist(_ plan: SitePropsCommitPlan) -> Result<SitePropsUpdateSnapshot?, SitePropsLocalSaveError>
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}
```

补测试覆盖：

- online prepare 等 retrieve 后才返回 draft；失败静默返回 local；offline 不调用 API；
- retrieve merge 改变本地/清理 pending 时才调用 save；保存失败时使用原本地值初始化 draft；
- Done 的“新变化 + 历史 pending”并集；无变化/无 pending 直接关闭；
- local save 失败不提交 API；
- save 前同时写 target values、`lastUpdate`、mask、pending timestamp；单条 Site row 写入失败时恢复内存旧值；
- update success 只在 snapshot timestamp/值仍匹配时清 pending；
- success 将 `lastUploadCloudTimestamp` 推进到 snapshot timestamp；failure 保留旧值；
- server success 后本地 pending 清理 save 失败按失败返回，依靠下次 retrieve 对账；
- coordinator 不调用 `CloudSynchronizationManager`。

没有 XCTest target，因此：纯分支继续在 `SitePropsEditPolicyTests` 中使用 fake state 验证；runtime wiring 使用源码 contract 验证调用边界。

### Step 2：实现 prepare

- offline：从当前 Site 创建 draft。
- online：await retrieve → validate → policy merge → 必要时保存 → 返回最终 draft。
- malformed nonempty timezone 由 client 作为整次 retrieve 失败；不部分合并 name/icon。
- 本地仍有 pending 时完整使用本地 name/image/timezone。

### Step 3：实现 commit/persist

- `makeCommitPlan` 不修改 Site。
- 纯重试复用 pending timestamp；有新变化用 `max(now, site.lastUpdate + 1)`。
- `persist` 先备份内存字段，写 Site 值/lastUpdate/pending 后调用现有单行 `site.save()`；失败恢复备份并不发请求。

### Step 4：实现 submit

- 请求前 snapshot 不可变。
- `.success` 仍须通过回复 exact-match 校验，否则当失败处理。
- 清理 pending 前再次比较当前 timestamp 和字段值，防止覆盖请求期间的新版本。
- 不在这里触发整包同步，也不修改整包同步完成回调。

### Step 5：运行 focused tests/contracts

```bash
/tmp/SitePropsEditPolicyTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
```

Expected：policy 与 API/coordinator contract 全部通过，并确认 `CloudSynchronizationManager` 未增加 pending 清理。

### Step 6：局部复核

- 对照最终设计第 10–13 节完成状态矩阵审查。
- 建议提交信息：`feat: coordinate editable site props sync`；未经授权不提交。

---

## Task 8：实现 Time Zone 选择页、分组、搜索与回传

**Files:**

- Create: `SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift`
- Create: `SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift`
- Create: `Tests/Site/SiteTimeZoneUIContractTests.swift`

### Step 1：先写 UI source contract

Contract 断言：

- 页面使用 catalog sections，不在控制器重复解析 JSON；
- 搜索框 placeholder 使用本地化 key；输入交给 catalog `sections(matching:)`；
- table/collection section header 展示 Region；cell 展示 ianaId 和 `UTC±HH:mm`；
- 无结果显示本地化 `No time zones found.`；
- 选择 cell 通过 callback 返回 `SiteTimeZoneValue` 并 pop；
- 无 checkmark、高亮状态或清空 timezone 行。

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift
```

Expected：文件不存在而失败。

### Step 2：按 Figma 实现最小页面

- 页面 title、搜索框、Region header、行高、分隔线、字体和颜色优先复用现有主题常量。
- 第一组由 catalog 固定为 UTC。
- `onSelect: (SiteTimeZoneValue) -> Void` 只回写上级 draft，不访问 `SiteData.save()`。
- 搜索 trim 和匹配全部复用 catalog；控制器只负责重载与 empty state。
- 选中后先执行 callback，再 `popViewController(animated: true)`。

### Step 3：运行 model 与 UI contract

```bash
/tmp/SiteTimeZoneCatalogTests SunSmart/all_utc_timezones.json
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift
```

Expected：均通过。

### Step 4：局部人工检查

- UTC 首组、8 个 JSON Region、398 行；
- Region 命中整组，iana/offset 命中单行；
- keyboard 下列表可滚动，清空搜索恢复全量；
- 暂不显示当前选择标记。
- 建议提交信息：`feat: add site timezone selection screen`；未经授权不提交。

---

## Task 9：重写专用 SiteEditViewController 布局、草稿与 Local time 生命周期

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`

### Step 1：扩展 RED contract

断言：

- 初始化接收 Site、draft、coordinator；页面 title 使用 `site.name`；
- 内容顺序为 Name、Time Zone、Site Icon；
- `Site Icon` 标题位于 icon collection 上方；
- timezone 未配置显示 Not configured 并隐藏 Local time；
- 已配置显示 ianaId、offset 和完整文本，例如 `Local time · 2026-8-1 6:06:20 AM`；
- Time Zone 行 push 选择页，回传只更新 draft；
- close 丢弃本次 draft，不改 Site；
- timer 0.5 秒，但每次从新的 `Date()` 计算；
- view visible/foreground 立即刷新，view disappear/background/deinit 停止；
- `Not synced to server` 由任一 pending 字段控制，触控高度至少 44pt，并与 Done 调用同一 selector/方法。

### Step 2：重建 UI，复用现有组件

- 复用 `ImageCollectionViewCell`、项目字体/颜色/SnapKit、现有 close 资源和 modal navigation 风格。
- 保留 Name 32 字符、空值、重名校验能力；逻辑从 `InfoEditViewController` 局部迁入专用控制器，不修改通用控制器。
- Site Icon 使用现有 `site_1` 至 `site_28` 资源和四列布局。
- `Not synced to server` 放 Time Zone 标题右侧；视觉尺寸按 Figma，外围透明 button/hit container 保证至少 44pt。

### Step 3：实现 Local time 生命周期

- 使用 `DispatchSourceTimer`、`Timer` 或现有弱定时器均可，但 UI 更新在 main queue。
- `viewDidAppear` 和 app foreground notification 立即刷新后启动 0.5 秒 tick。
- `viewWillDisappear`、background notification、deinit 统一停止并移除 observer。
- tick 每次取新的 clock `Date()`，调用 `SiteTimeZoneValue.formattedLocalDate`，不对旧显示值加秒。
- 前缀通过 format localization key 组装，AM/PM 来自值对象的 `en_US_POSIX` 日期文本。

### Step 4：运行 focused tests/contracts

```bash
/tmp/SiteTimeZoneValueTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift
```

Expected：全部通过。

### Step 5：局部人工检查

- 页面标题随进入时 Site name，不能固定为 Edit Site；
- Figma 中的 `Size Icon` 不得进入实现；
- Local time 不出现明显 +2 秒跳变，离开页面后无残留 timer。
- 建议提交信息：`feat: build dedicated edit site timezone UI`；未经授权不提交。

---

## Task 10：实现 Done、离线、Toast、同步状态卡片与两个入口路由

**Files:**

- Create: `SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SitesViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Modify: `Tests/Site/SitePropsAPIContractTests.swift`

### Step 1：先扩展行为 contract

对两个 entry source 和编辑页断言：

- `editSite` 不再创建 `InfoEditViewController`，不再从 Edit Site 路径调用 `CloudSynchronizationManager.syncSite`；
- online 进入编辑前显示原页面 loading，等待 retrieve 后才 present；retrieve 失败静默使用 local；offline 直接使用 local；
- 无变化/无 pending：关闭，无请求/Toast；
- 有 pending 无新变化：Done/Not synced 执行重试；
- fields 含 timezone：在线先确认；Cancel 留在编辑页且不落库；离线先提示，Got it 后落库并返回 Sites；
- 仅 name/icon：本地落库后返回 Sites；online update 成功/失败显示对应 Toast，offline 显示失败 Toast；
- 含 timezone online：落库、返回 Sites、显示不可关闭等待卡片、执行 update，再切 success/failure，最后才出现可点 Done；
- Site 内页入口成功提交后退出 Site 内页回到 Sites；Sites 列表入口只关闭 modal；两者都刷新同一个 Site 对象；
- 成功状态固定 `No gateways`，无任何 gateway/Mesh API 调用。

### Step 2：实现同步状态 View

计划状态：

```swift
enum SiteTimeZoneSyncStatus {
    case saving
    case successNoGateways
    case failure
}

final class SiteTimeZoneSyncStatusView: UIView {
    func show()
    func update(state: SiteTimeZoneSyncStatus)
}
```

- `.saving`：`Time zone sync status`，加载态，不显示可关闭控件；背景 tap 不关闭。
- `.successNoGateways`：`Saved successfully`、`No gateways`、`No gateways configured — no sync needed.`、DONE。
- `.failure`：标题 `Saved failed`，结束加载，显示 DONE；其他布局遵循对应 Figma 失败态。
- DONE 只关闭卡片，不发起第二次请求。

### Step 3：实现 Done 状态机

- Done 与 Not synced 调同一 `attemptCommit()`。
- 本地保存失败：停留编辑页，`Failed to update site.`，无请求。
- timezone online 的确认使用 `SRAlertView` 或最小专用 alert，按钮复用现有 `cancel`，新增 Update Time Zone key；Cancel 只 dismiss alert。
- timezone offline 的 Got it 先调用 coordinator.persist；失败仍停留编辑页并显示失败，成功才返回 Sites。
- name/icon offline 按已确认行为：落库、返回 Sites、失败 Toast、保留 pending。

### Step 4：接入两个入口

- `SitesViewController.editSite(site:)`：online show HUD → await coordinator.prepareDraft → hide HUD → present；提交后 dismiss modal、`reloadSiteData(site)`，在 Sites view/window 展示 Toast 或状态卡片。
- `SiteViewController.editSite()`：同样 prepare/present；提交后 dismiss modal，更新 title/site reference，再 pop 当前 Site 页面到 Sites；状态卡片必须在 Sites 已可见后 show。
- 页面被释放或用户在 retrieve 中离开时取消/忽略迟到结果，不 present 到不可见控制器。
- 两个入口共用 `SitePropsEditCoordinator` 和 `SiteEditViewController`，只保留返回 Sites 的路由差异。

### Step 5：执行 focused contracts

```bash
/tmp/SitePropsEditPolicyTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift
```

Expected：全部通过。

### Step 6：分支人工检查

- 在线 timezone：Cancel、success、HTTP failure、code 200 但响应字段不匹配；
- 离线 timezone：Got it 后本地可见、pending 可见；
- name/icon：online success/failure、offline；
- 重启后 pending 恢复，Not synced 可重试；
- pending 后被旧整包同步上传，下次 retrieve 对账清除；
- 建议提交信息：`feat: complete edit site props sync flow`；未经授权不提交。

---

## Task 11：补齐国际化与四 target 文件/资源归属

**Files:**

- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: `SunSmart/all_utc_timezones.json`
- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`

### Step 1：先写资源 contract

断言每个新 key 在 EN/zh-Hans 各出现一次，新 Swift 文件在四个 Sources build phase 中各出现一次，JSON 在四个 Resources build phase 中各出现一次。

新增 key 建议如下；`cancel`、`done` 复用现有 key：

| Key | English | 简体中文 |
|---|---|---|
| `site_time_zone` | Time Zone | 时区 |
| `site_local_time_format` | Local time · %@ | 本地时间 · %@ |
| `site_icon` | Site Icon | 场所图标 |
| `site_time_zone_not_configured` | Not configured | 未配置 |
| `site_time_zone_search_placeholder` | Search time zones | 搜索时区 |
| `site_time_zone_search_empty` | No time zones found. | 未找到时区。 |
| `site_props_not_synced` | Not synced to server | 未同步至服务器 |
| `site_time_zone_update_prompt` | Update Site time zone? | 更新场所时区？ |
| `site_time_zone_update_action` | UPDATE TIME ZONE | 更新时区 |
| `site_time_zone_offline_title` | You are offline | 当前处于离线状态 |
| `got_it` | Got it | 知道了 |
| `site_time_zone_sync_status` | Time zone sync status | 时区同步状态 |
| `site_props_saved_successfully` | Saved successfully | 保存成功 |
| `site_props_saved_failed` | Saved failed | 保存失败 |
| `site_time_zone_no_gateways` | No gateways | 无网关 |
| `site_time_zone_no_gateway_sync_needed` | No gateways configured — no sync needed. | 未配置网关，无需同步。 |
| `site_updated` | Site updated. | 场所已更新。 |
| `site_update_failed` | Failed to update site. | 场所更新失败。 |

### Step 2：运行 RED contract

```bash
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：缺 key 和/或新 source membership 而失败。

### Step 3：补资源与 target membership

- 新文件加入现有 Site Model/Controller/View 或 Common Data group。
- 每个新 Swift 文件有四个 PBXBuildFile entry，分别进入四个 Sources phase。
- 保留 JSON 现有四个 Resources entry，不重复添加。
- 不扩大 project.pbxproj 清理范围，不接受 Xcode 自动移除已有文件或 package 设置。

### Step 4：校验 strings、JSON 和 membership

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
jq empty SunSmart/all_utc_timezones.json
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：语法与 contract 均通过。

### Step 5：局部复核

- 所有用户可见文案只从 localization key 获取；timezone Region/ianaId/offset 按需求保持原始英文数据。
- 四个品牌 target 无遗漏或重复资源 warning。
- 建议提交信息：`feat: localize site timezone UI for all targets`；未经授权不提交。

---

## Task 12：完整回归、四 target 构建与验收交接

**Files:**

- Verify all files above
- Verify unchanged scope: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
- Verify unchanged scope: Timed/Gateway Time Set files

### Step 1：重跑全部 focused tests

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift Tests/Site/SiteTimeZoneValueTests.swift -o /tmp/SiteTimeZoneValueTests
/tmp/SiteTimeZoneValueTests
```

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift Tests/Site/SiteTimeZoneCatalogTests.swift -o /tmp/SiteTimeZoneCatalogTests
/tmp/SiteTimeZoneCatalogTests SunSmart/all_utc_timezones.json
```

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
```

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

```bash
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
```

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：每个测试输出各自唯一的 `passed` 成功标识，退出码为 0。

### Step 2：静态与 diff 检查

```bash
git diff --check
git status --short
git diff --stat
```

人工确认：

- diff 中没有 `needsFullSiteSync`、第二个 Site 版本 timestamp；
- `CloudSynchronizationManager` 未新增 pending 清理或 edit 分量路由；
- `InfoEditViewController` 未被改动；
- Timed/Gateway Time Set 文件未被改动；
- project.pbxproj 保留用户原有 JSON 资源改动。

### Step 3：四个 generic iPhoneOS 构建

依次直接运行，任何一个失败先按失败阶段定位并修复，不并行运行 Xcode 构建：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：四个 target 均 `BUILD SUCCEEDED`。构建成功只证明编译/链接/资源归属，不替代服务器和真机验收。

### Step 4：服务器联调矩阵

- retrieve：新/旧/equal timestamp、timezone missing/null/empty/valid/malformed、请求失败；
- update：name、icon、timezone、三者组合、HTTP failure、code failure、reply timestamp mismatch、sent field mismatch；
- pending：失败后重启重试、失败后整包同步、下次 retrieve 对账；
- 确认所有请求 timezone 为完整格式，例如 `Indian/Comoro (UTC+03:00)`。

### Step 5：真机 UI 验收矩阵

- English/简体中文、iPhone/iPad、四品牌 target；
- 两个 Edit Site 入口、未配置/已配置/pending；
- timezone 搜索/选择/返回、关闭丢草稿、Cancel、Got it、DONE；
- Local time 0.5 秒刷新、跨分钟、前后台、离开页面停止；
- status saving 不可关闭，success/failure 只能由 DONE 关闭；
- old DB 升级、App 重启 pending 恢复；
- Timed/Gateway Time Set 仍使用手机时区。

### Step 6：完成报告

报告必须区分：

- 已通过的纯策略/contract；
- 四个 iPhoneOS build 结果；
- 已完成的真机 UI；
- 已完成或仍待服务器确认的 retrieve/update 真实网络分支；
- 明确说明本期未做 gateway/Mesh timezone sync。

建议最终提交信息：`feat: add site timezone editing and props sync`；未经授权不提交。

---

## 需求覆盖复核表

| 需求 | 计划任务 |
|---|---|
| 完整 timezone 格式、固定 offset、Local time | Task 1、9 |
| JSON 397 条、UTC 注入、分组与搜索 | Task 2、8 |
| 新建/克隆默认 timezone | Task 2、5 |
| Site 本地 DB 与 pending 重启恢复 | Task 3、4、7 |
| 单一 lastUpdate/updateTimestamp | Task 3、7 |
| retrieve merge 与失败静默回退 | Task 3、6、7、10 |
| update 可选字段与响应严格校验 | Task 3、6、7 |
| 原整包同步增加 timezone但流程不变 | Task 5、12 |
| Site 专用编辑页、Site Icon 标题 | Task 9 |
| Not synced 点击等同 Done | Task 9、10 |
| timezone confirm/offline/status | Task 10 |
| name/icon Toast 流程 | Task 10 |
| 两个入口统一、回到 Sites | Task 10 |
| 四 target 与双语国际化 | Task 11、12 |
| 不改 Timed/Gateway/InfoEdit/全局同步架构 | Task 0、12 |
