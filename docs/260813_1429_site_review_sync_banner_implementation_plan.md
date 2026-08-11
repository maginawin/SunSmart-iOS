# Site Review Sync Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with inline checkpoints. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Site 首次时区检查结束及后续服务器刷新后，按服务器实际 Site time zone 与权限范围内 Gateway Offset 的比较结果，动态展示或隐藏 Figma `Review sync` 提示组件，并提供空的 `Sync gateways` 页面入口。

**Architecture:** 继续保留 `SiteEntryTimeZoneSyncCoordinator` 的“每个 `SiteViewController` 实例只消费首次响应”边界；在现有纯 Policy 中增加独立的页面 Review 状态计算，供首次结果和每次后续成功响应共同使用。`SiteViewController` 只保存当前实例的瞬时页面状态，`SiteGatewayHeaderView` 负责在 All Spaces 与 Favourites 两个列表中按同一状态布局提示组件；服务器请求失败或响应非法时不覆盖上一次可信状态。

**Tech Stack:** Swift、UIKit、SnapKit、Foundation `TimeZone`、现有 `/sitespace/get/siteprops` 导入链路、独立 `swiftc` 策略/源码契约测试、Xcode generic iPhoneOS build。

## Global Constraints

- 以最近一次成功获取或成功写入的服务器实际 Site time zone 为页面真值；本地上传失败时继续使用原 cloud timezone。
- 页面组件只在权限范围内 `pendingGatewayCount > 0` 时展示。
- Owner 比较响应中的全部 Gateway；Editor 只比较 Editor Spaces 绑定的 Gateway；Visitor 不展示组件。
- Gateway Offset 继续使用 `(timezoneOffset - 64) × 15` 分钟，并沿用当前非法值、缺失 Gateway 和 ID 去重规则。
- `Sync status` 只允许当前 `SiteViewController` 实例首次成功响应触发；后续刷新不得再次展示。
- 弹窗 `LATER` 与弹窗 `REVIEW SYNC` 都只关闭弹窗；只有页面组件 `Review sync` 才 push `Sync gateways`。
- 下拉刷新失败、响应缺失关键字段或 cloud timezone 非法时，保留上一次可信页面状态。
- 服务器响应 `updateTimestamp > site.lastUpdate` 时继续由现有 `site.update(siteJsonData:)` 更新 App timezone；不增加第二套 Site props 持久化规则。
- All Spaces 与 Favourites 使用同一份 Site 级 Review 状态，组件与上下可见块间距均为 8。
- 所有新增用户可见文案必须同时提供 English 和简体中文；英文正确区分 1 gateway 与 N gateways。
- 本期 `Sync gateways` 只创建空页面，不传 Gateway 列表，不实现 BLE/Mesh、扫描、连接、写入、进度或结果。
- 复用现有 `site_entry_sync_warning` SVG，不新增重复图片资源。
- 新 Swift 文件必须加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 保留当前 worktree 已有未提交改动；不重置、不格式化无关文件、不自动 commit、push 或 merge。
- 构建只使用 generic iPhoneOS；不得使用 Simulator、shell 包装或日志重定向。

## File Responsibility Map

- `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`：唯一的权限范围与 Gateway Offset 比较规则；新增可重复调用的页面 Review 状态计算。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：保存当前页面状态，接入首次结果/后续刷新，并负责页面导航。
- `SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift`：Figma 56pt Review sync 提示组件，只负责显示和按钮事件。
- `SunSmart/Main/Site/View/SiteGatewayHeaderView.swift`：组合 Gateway list、Gateway status 与 Review sync 三个块并维护垂直布局。
- `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift`：本期空白目标页面。
- `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift`：页面 Review 状态纯策略测试。
- `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`：首次弹窗与后续刷新生命周期契约。
- `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`：Figma UI、双 header、导航、本地化和四 target 文件引用契约。

---

### Task 1: 增加可重复调用的页面 Review 状态纯策略

**Files:**

- Modify: `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift:18-261`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift:4-460`

**Interfaces:**

- Consumes: `SiteEntryTimeZoneRemoteSnapshot`、远端或成功写入后的 `SiteTimeZoneValue`。
- Produces: `SiteTimeZoneReviewState`、`SiteEntryTimeZoneSyncPolicy.reviewState(remote:)`、`SiteEntryTimeZoneSyncPolicy.reviewState(remote:serverTimezone:)`。

- [ ] **Step 1: 在 Policy 测试入口增加页面状态测试调用**

在 `main()` 的既有测试调用后加入：

```swift
testReviewStateUsesServerTruth()
testReviewStateRespectsAccessScope()
testReviewStateRejectsInvalidServerTimezone()
```

- [ ] **Step 2: 写 server truth 与成功上传切换的失败测试**

在 `SiteEntryTimeZoneSyncPolicyTests` 中加入：

```swift
private static func testReviewStateUsesServerTruth() {
    let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!
    let tokyo = SiteTimeZoneValue(
        ianaId: "Asia/Tokyo",
        rawUTCOffset: "+09:00"
    )!
    let remote = remoteSnapshot(
        role: .owner,
        timezone: tokyo,
        timestamp: 100,
        gateways: [gateway("AA:BB", 480)]
    )

    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: remote) ==
            .review(serverTimezone: tokyo, gatewayCount: 1),
        "Remote server timezone must drive the refresh review state"
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(
            remote: remote,
            serverTimezone: singapore
        ) == .hidden,
        "A successful local upload must recompute against the new server timezone"
    )
}
```

- [ ] **Step 3: 写 Owner、Editor、Visitor 与 invalid 的失败测试**

加入以下完整断言：

```swift
private static func testReviewStateRespectsAccessScope() {
    let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!
    let editorSpaces = [
        space(.editor, gatewayId: "editor-gateway"),
        space(.visitor, gatewayId: "visitor-gateway")
    ]
    let gateways = [
        gateway("editor-gateway", 0),
        gateway("visitor-gateway", 0)
    ]
    let editorRemote = remoteSnapshot(
        role: .visitor,
        timezone: singapore,
        timestamp: 100,
        spaces: editorSpaces,
        gateways: gateways
    )
    let visitorRemote = remoteSnapshot(
        role: .visitor,
        timezone: singapore,
        timestamp: 100,
        spaces: [space(.visitor, gatewayId: "visitor-gateway")],
        gateways: gateways
    )

    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: editorRemote) ==
            .review(serverTimezone: singapore, gatewayCount: 1),
        "Editor must count only Editor Space gateways"
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: visitorRemote) == .hidden,
        "Visitor must not expose a gateway sync action"
    )

    let ownerRemote = remoteSnapshot(
        role: .owner,
        timezone: singapore,
        timestamp: 100,
        gateways: [
            gateway("AA:BB", 480),
            gateway("aa:bb", 0),
            gateway(nil, nil)
        ]
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: ownerRemote) ==
            .review(serverTimezone: singapore, gatewayCount: 2),
        "Owner must deduplicate identified gateways and count anonymous invalid gateways"
    )

    let missingEditorGateway = remoteSnapshot(
        role: .visitor,
        timezone: singapore,
        timestamp: 100,
        spaces: [space(.editor, gatewayId: "missing")],
        gateways: []
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: missingEditorGateway) ==
            .review(serverTimezone: singapore, gatewayCount: 1),
        "Missing Editor-bound gateway data must remain pending"
    )

    let allInSync = remoteSnapshot(
        role: .owner,
        timezone: singapore,
        timestamp: 100,
        gateways: [gateway("AA:BB", 480)]
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: allInSync) == .hidden,
        "A valid all-in-sync snapshot must hide the page component"
    )
}

private static func testReviewStateRejectsInvalidServerTimezone() {
    let invalidRemote = remoteSnapshot(
        role: .owner,
        timezone: nil,
        timestamp: 100,
        gateways: [gateway("AA:BB", nil)]
    )
    require(
        SiteEntryTimeZoneSyncPolicy.reviewState(remote: invalidRemote) == nil,
        "Invalid cloud timezone must not replace the last trusted page state"
    )
}
```

- [ ] **Step 4: 运行 Policy 测试并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
```

Expected: 编译因缺少 `SiteTimeZoneReviewState` 或 `reviewState` 接口失败。

- [ ] **Step 5: 增加最小页面状态类型**

在 `SiteEntryGatewaySummary` 后加入：

```swift
enum SiteTimeZoneReviewState: Equatable {
    case hidden
    case review(
        serverTimezone: SiteTimeZoneValue,
        gatewayCount: Int
    )
}
```

- [ ] **Step 6: 在现有 Policy 内复用同一 gatewaySummary 实现两个入口**

在 `SiteEntryTimeZoneSyncPolicy` 中加入：

```swift
static func reviewState(
    remote: SiteEntryTimeZoneRemoteSnapshot
) -> SiteTimeZoneReviewState? {
    guard let serverTimezone = validated(remote.timezone) else {
        return nil
    }
    return reviewState(
        remote: remote,
        serverTimezone: serverTimezone
    )
}

static func reviewState(
    remote: SiteEntryTimeZoneRemoteSnapshot,
    serverTimezone: SiteTimeZoneValue
) -> SiteTimeZoneReviewState {
    let gateway = gatewaySummary(
        scope: accessScope(remote),
        gateways: remote.gateways,
        targetOffsetMinutes: serverTimezone.offsetMinutes
    )
    guard case let .pending(count) = gateway else {
        return .hidden
    }
    return .review(
        serverTimezone: serverTimezone,
        gatewayCount: count
    )
}
```

不要复制 Owner/Editor/Visitor 或 Offset 比较逻辑；两个入口必须继续调用现有 `accessScope` 与 `gatewaySummary`。

- [ ] **Step 7: 运行 Policy 测试并确认 GREEN**

重复 Step 4 命令。Expected: 输出 `SiteEntryTimeZoneSyncPolicyTests passed`。

- [ ] **Step 8: 检查 Task 1 差异范围**

Run:

```bash
git diff --check -- SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift
git diff -- SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift
```

Expected: 只增加纯状态与测试，不引入 UIKit、网络、持久化或导航。

---

### Task 2: 将首次结果与后续刷新接入同一页面状态

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:68-88, 435-529, 609-653, 2649-2770`
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift:149-229`

**Interfaces:**

- Consumes: Task 1 的 `SiteTimeZoneReviewState` 与两个 `reviewState` 接口。
- Produces: Controller 属性 `timeZoneReviewState`、可信状态更新方法，以及携带 remote snapshot 的 entry overlay 调用链。

- [ ] **Step 1: 增加后续刷新与上传成功顺序的失败契约**

在 `SiteEntryTimeZoneSyncContractTests` 中加入：

```swift
require(
    siteController.contains(
        "private var timeZoneReviewState: SiteTimeZoneReviewState = .hidden"
    ) &&
        siteController.contains("private func applyTimeZoneReviewState(") &&
        siteController.contains("private func setTimeZoneReviewState("),
    "Site must own one non-persistent review state"
)
require(
    appearsInOrder(
        [
            "await self.site.update(siteJsonData: siteData)",
            "if let remoteSnapshot {",
            "self.applyTimeZoneReviewState(from: remoteSnapshot)",
            "handleEntrySyncDecision("
        ],
        in: siteController
    ),
    "Every valid response must update the page state before entry handling"
)
require(
    siteController.contains("remoteSnapshot: remoteSnapshot") &&
        appearsInOrder(
            [
                "let result = await entrySyncCoordinator.run(decision)",
                "if result.site == .updatedToServer",
                "serverTimezone: result.timezone",
                "entrySyncOverlay.showResult(result)"
            ],
            in: siteController
        ),
    "Successful app-to-cloud sync must update server truth before result actions"
)
require(
    occurrences(of: "entrySyncCoordinator.prepare(", in: siteController) == 1 &&
        siteController.contains("hasConsumedEntryResponse") == false,
    "Page refresh must preserve the coordinator's existing one-entry gate"
)
```

契约不要求 failure 分支把状态设为 hidden；状态不变必须通过“只有合法 snapshot 或成功上传才调用 setter”体现。

- [ ] **Step 2: 运行 Entry Contract 并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 因 Controller 尚未持有页面状态、remote snapshot 未传入 overlay 而失败。

- [ ] **Step 3: 增加 Controller 瞬时状态与可信更新方法**

在 entry sync 属性附近加入：

```swift
private var timeZoneReviewState: SiteTimeZoneReviewState = .hidden
```

并加入：

```swift
private func applyTimeZoneReviewState(
    from remote: SiteEntryTimeZoneRemoteSnapshot
) {
    guard let state = SiteEntryTimeZoneSyncPolicy.reviewState(remote: remote) else {
        return
    }
    setTimeZoneReviewState(state)
}

private func applyTimeZoneReviewState(
    from remote: SiteEntryTimeZoneRemoteSnapshot,
    serverTimezone: SiteTimeZoneValue
) {
    setTimeZoneReviewState(
        SiteEntryTimeZoneSyncPolicy.reviewState(
            remote: remote,
            serverTimezone: serverTimezone
        )
    )
}

private func setTimeZoneReviewState(_ state: SiteTimeZoneReviewState) {
    guard state != timeZoneReviewState else { return }
    timeZoneReviewState = state
    guard isViewLoaded else { return }
    allSpacesCollectionView.collectionViewLayout.invalidateLayout()
    favouritesCollectionView.collectionViewLayout.invalidateLayout()
    allSpacesCollectionView.reloadData()
    favouritesCollectionView.reloadData()
}
```

这里不持久化状态；invalid response 通过第一个方法的 `nil` 直接保留旧值。

- [ ] **Step 4: 每次合法响应导入后都应用 remote server truth**

在 `site.update` 和 `setupData()` 完成后、`handleEntrySyncDecision` 前加入：

```swift
if let remoteSnapshot {
    self.applyTimeZoneReviewState(from: remoteSnapshot)
}
```

不要放进 `entrySyncCoordinator.prepare` 的首次分支；后续刷新虽然 decision 为 `.noAction`，仍必须执行此更新。

- [ ] **Step 5: 把 remote snapshot 传入首次可见流程**

调整接口为：

```swift
private func handleEntrySyncDecision(
    _ decision: SiteEntryTimeZoneDecision,
    remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot?
) -> Bool

private func showEntrySyncOverlay(
    for decision: SiteEntryTimeZoneDecision,
    remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot
) -> Bool
```

`.noAction` 与 `.useVisitorRemote` 保持原行为；三个可见 decision 必须先取得非空 remote snapshot 才展示 Overlay。

- [ ] **Step 6: 只在 app-to-cloud 成功时覆盖 server truth**

在 `entrySyncCoordinator.run` 返回并完成既有 cancellation/window guards 后、`showResult` 前加入：

```swift
if result.site == .updatedToServer {
    applyTimeZoneReviewState(
        from: remoteSnapshot,
        serverTimezone: result.timezone
    )
}
entrySyncOverlay.showResult(result)
```

`.failedToUpdateServer` 不执行覆盖，因此保留 Step 4 已按原 remote timezone 计算的页面状态。

- [ ] **Step 7: 运行 Policy、Entry Contract 与 Coordinator 回归**

Run:

```bash
/tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
/tmp/SiteEntryTimeZoneSyncCoordinatorTests
```

Expected: 三项均输出 passed；Coordinator 的 `hasConsumedEntryResponse` 行为保持不变。

- [ ] **Step 8: 检查刷新失败没有清空状态的副作用**

Run:

```bash
rg -n "timeZoneReviewState = \.hidden|setTimeZoneReviewState\(\.hidden\)" SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: 只有属性初值或合法 Policy 结果可产生 hidden；request failure、parser failure 和 timeout 分支没有无条件清空。

---

### Task 3: 实现 Figma Review sync 组件并接入双 header

**Files:**

- Create: `SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift`
- Modify: `SunSmart/Main/Site/View/SiteGatewayHeaderView.swift:10-113`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2649-2770`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Create: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

**Interfaces:**

- Consumes: `SiteTimeZoneReviewState.review(serverTimezone:gatewayCount:)`。
- Produces: `SiteTimeZoneReviewSyncView.update(serverTimezone:gatewayCount:)`、`SiteGatewayHeaderView.timeZoneReviewState`、`SiteGatewayHeaderView.onReviewSync`。

- [ ] **Step 1: 写 Figma、本地化、header 和 target 失败契约**

新建 `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`，测试入口读取 7 个路径：Review view、header、Site controller、English、简体中文、project、warning imageset。入口先固定参数契约：

```swift
let arguments = CommandLine.arguments
guard arguments.count == 8 else {
    fatalError("Expected review view, header, Site controller, English, Chinese, project, and warning asset paths")
}

let reviewView = try String(contentsOfFile: arguments[1], encoding: .utf8)
let header = try String(contentsOfFile: arguments[2], encoding: .utf8)
let siteController = try String(contentsOfFile: arguments[3], encoding: .utf8)
let english = try String(contentsOfFile: arguments[4], encoding: .utf8)
let simplifiedChinese = try String(contentsOfFile: arguments[5], encoding: .utf8)
let project = try String(contentsOfFile: arguments[6], encoding: .utf8)
let warningAsset = try String(contentsOfFile: arguments[7], encoding: .utf8)
```

核心断言写为：

```swift
require(reviewView.contains("final class SiteTimeZoneReviewSyncView: UIView"))
require(reviewView.contains("RGB(255, 249, 239)"))
require(reviewView.contains("layer.cornerRadius = SCRYFrom(14)"))
require(reviewView.contains("UIImage(named: \"site_entry_sync_warning\")"))
require(reviewView.contains("make.size.equalTo(SCRYFrom(16))"))
require(reviewView.contains("RGB(100, 116, 139)"))
require(reviewView.contains("RGB(151, 60, 0)"))
require(reviewView.contains("make.height.equalTo(SCRYFrom(28))"))
require(reviewView.contains("numberOfLines = 2"))
require(reviewView.contains("var onReviewSync: (() -> Void)?"))

for key in [
    "site_time_zone_review_sync_single",
    "site_time_zone_review_sync_multiple",
    "site_time_zone_review_sync_action"
] {
    require(occurrences(of: "\"\(key)\" =", in: english) == 1)
    require(occurrences(of: "\"\(key)\" =", in: simplifiedChinese) == 1)
    require(reviewView.contains("\"\(key)\".localizedString"))
}

require(header.contains("let timeZoneReviewSyncView = SiteTimeZoneReviewSyncView()"))
require(header.contains("var timeZoneReviewState: SiteTimeZoneReviewState"))
require(header.contains("var onReviewSync: (() -> Void)?"))
require(header.contains("timeZoneReviewSyncView.isHidden = true"))
require(siteController.contains("headerView.timeZoneReviewState = timeZoneReviewState"))
require(siteController.contains("headerH += SCRYFrom(64)"))

require(occurrences(of: "SiteTimeZoneReviewSyncView.swift in Sources", in: project) == 4)
require(warningAsset.contains("site_entry_sync_warning.svg"))
```

文件尾实现已有 contract 风格的 `occurrences` 与 `require` helper。

- [ ] **Step 2: 运行 Review Contract 并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 因 Review view 文件不存在而失败。

- [ ] **Step 3: 新建最小 Review view**

实现以下稳定结构：

```swift
import UIKit
import SnapKit

final class SiteTimeZoneReviewSyncView: UIView {
    var onReviewSync: (() -> Void)?

    private let iconView = UIImageView(
        image: UIImage(named: "site_entry_sync_warning")
    )
    private let messageLabel = UILabel()
    private let reviewButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        serverTimezone: SiteTimeZoneValue,
        gatewayCount: Int
    ) {
        let key = gatewayCount == 1
            ? "site_time_zone_review_sync_single"
            : "site_time_zone_review_sync_multiple"
        let text = gatewayCount == 1
            ? String(format: key.localizedString, serverTimezone.displayOffset)
            : String(
                format: key.localizedString,
                serverTimezone.displayOffset,
                gatewayCount
            )
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = SCRYFrom(16)
        paragraph.maximumLineHeight = SCRYFrom(16)
        messageLabel.attributedText = NSAttributedString(
            string: text,
            attributes: [.paragraphStyle: paragraph]
        )
    }

    private func setupUI() {
        backgroundColor = RGB(255, 249, 239)
        layer.cornerRadius = SCRYFrom(14)

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }

        reviewButton.backgroundColor = .white
        reviewButton.layer.cornerRadius = SCRYFrom(10)
        reviewButton.setTitle(
            "site_time_zone_review_sync_action".localizedString,
            for: .normal
        )
        reviewButton.setTitleColor(RGB(151, 60, 0), for: .normal)
        reviewButton.titleLabel?.font = UIFont.systemFont(
            ofSize: SCRYFrom(12),
            weight: .semibold
        )
        reviewButton.addTarget(
            self,
            action: #selector(reviewButtonDidTap),
            for: .touchUpInside
        )
        addSubview(reviewButton)
        reviewButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(28))
            make.width.greaterThanOrEqualTo(SCRXFrom(87))
        }

        messageLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        messageLabel.textColor = RGB(100, 116, 139)
        messageLabel.numberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(12))
            make.right.equalTo(reviewButton.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
    }

    @objc private func reviewButtonDidTap() {
        onReviewSync?()
    }
}
```

- [ ] **Step 4: 增加页面组件独立本地化**

English：

```text
"site_time_zone_review_sync_single" = "Server time zone %@ · 1 gateway needs time zone sync";
"site_time_zone_review_sync_multiple" = "Server time zone %@ · %d gateways need time zone sync";
"site_time_zone_review_sync_action" = "Review sync";
```

简体中文：

```text
"site_time_zone_review_sync_single" = "服务器时区 %@ · 1 个网关需要同步时区";
"site_time_zone_review_sync_multiple" = "服务器时区 %@ · %d 个网关需要同步时区";
"site_time_zone_review_sync_action" = "检查同步";
```

不要复用或修改弹窗全大写 `site_entry_sync_review_sync`。

- [ ] **Step 5: 扩展 SiteGatewayHeaderView 的显式可见状态**

增加：

```swift
let timeZoneReviewSyncView = SiteTimeZoneReviewSyncView()
var onReviewSync: (() -> Void)?

var showGatewayStatusView = true {
    didSet {
        gatewayStatusView.isHidden = !showGatewayStatusView
        updateLayout()
    }
}

var timeZoneReviewState: SiteTimeZoneReviewState = .hidden {
    didSet {
        switch timeZoneReviewState {
        case .hidden:
            timeZoneReviewSyncView.isHidden = true
        case let .review(serverTimezone, gatewayCount):
            timeZoneReviewSyncView.isHidden = false
            timeZoneReviewSyncView.update(
                serverTimezone: serverTimezone,
                gatewayCount: gatewayCount
            )
        }
        updateLayout()
    }
}
```

在 `setupUI()` 中添加 Review view，并把事件单向转发：

```swift
timeZoneReviewSyncView.onReviewSync = { [weak self] in
    self?.onReviewSync?()
}
timeZoneReviewSyncView.isHidden = true
addSubview(timeZoneReviewSyncView)
updateLayout()
```

把现有 `showGatewayListView` 的约束分支收拢到一个 `updateLayout()`。布局必须满足：

- Gateway list 可见时固定 top 0、高 40；
- Gateway status 可见时位于上一个可见块下方 8、高 40；
- Review view 可见时位于上一个可见块下方 8、高 56；
- Review view 左右与 Gateway list 一致；
- hidden view 不占高度。

- [ ] **Step 6: Controller 同时驱动两个 header 和 header 高度**

在 `viewForSupplementaryElementOfKind` 中用显式属性替换直接隐藏：

```swift
headerView.showGatewayStatusView = showGatewayStatus
headerView.timeZoneReviewState = timeZoneReviewState
```

在 `referenceSizeForHeaderInSection` 的现有 48/48 计算后加入：

```swift
if case .review = timeZoneReviewState {
    headerH += SCRYFrom(64)
}
```

56 是组件高度，额外 8 是组件与第一张 Space Cell 的下间距；All Spaces 与 Favourites 使用同一计算。

- [ ] **Step 7: 将 Review view 加入四个 app target**

在 `project.pbxproj` 中新增一个 file reference、四个 build file，并分别加入四个 Sources phase。命名必须统一为 `SiteTimeZoneReviewSyncView.swift in Sources`，不得修改其他 target 配置。

- [ ] **Step 8: 运行 Review Contract、本地化和既有 UI 契约**

Run:

```bash
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 两个 contract 均 passed，两份 strings 均 `OK`。

---

### Task 4: 增加空的 Sync gateways 页面并只从页面组件导航

**Files:**

- Create: `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:681-705, 2670-2750`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

**Interfaces:**

- Consumes: `SiteGatewayHeaderView.onReviewSync`。
- Produces: `SyncGatewaysViewController` 与 `SiteViewController.showSyncGatewaysPage()`。

- [ ] **Step 1: 扩展导航与空页面失败契约**

让 Review Contract 额外读取 `SyncGatewaysViewController.swift`：参数数量改为 9，`arguments[4]` 读取 Sync page，后续 English、简体中文、project、warning asset 索引依次后移。加入：

```swift
require(syncPage.contains("final class SyncGatewaysViewController: UIViewController"))
require(syncPage.contains("title = \"site_sync_gateways_title\".localizedString"))
require(syncPage.contains("view.backgroundColor = Background_Color"))
require(siteController.contains("headerView.onReviewSync = { [weak self] in"))
require(siteController.contains("self?.showSyncGatewaysPage()"))
require(siteController.contains("private func showSyncGatewaysPage()"))
require(siteController.contains("SyncGatewaysViewController()"))
require(siteController.contains("navigationController?.pushViewController"))
require(
    appearsInOrder(
        [
            "private func handleEntrySyncReview()",
            "finishEntrySyncOverlay()"
        ],
        in: siteController
    )
)
require(!section(
    from: "private func handleEntrySyncReview()",
    to: "private func cancelEntrySyncOverlay()",
    in: siteController
).contains("pushViewController"))
require(occurrences(of: "SyncGatewaysViewController.swift in Sources", in: project) == 4)
```

同时把 `site_sync_gateways_title` 加入两种语言唯一性检查，并在测试文件尾增加本任务使用的 helper：

```swift
private static func appearsInOrder(
    _ needles: [String],
    in text: String
) -> Bool {
    var lowerBound = text.startIndex
    for needle in needles {
        guard let range = text.range(
            of: needle,
            range: lowerBound..<text.endIndex
        ) else {
            return false
        }
        lowerBound = range.upperBound
    }
    return true
}

private static func section(
    from start: String,
    to end: String,
    in text: String
) -> String {
    guard
        let startRange = text.range(of: start),
        let endRange = text.range(
            of: end,
            range: startRange.upperBound..<text.endIndex
        )
    else {
        return ""
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}
```

- [ ] **Step 2: 运行 Review Contract 并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 因目标页面和路由不存在而失败。

- [ ] **Step 3: 新建空目标页面**

实现：

```swift
import UIKit

final class SyncGatewaysViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "site_sync_gateways_title".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(
            color: Background_Color
        )
    }
}
```

不增加列表、按钮、Gateway 参数或业务依赖。

- [ ] **Step 4: 增加页面标题国际化**

English：

```text
"site_sync_gateways_title" = "Sync gateways";
```

简体中文：

```text
"site_sync_gateways_title" = "同步网关";
```

- [ ] **Step 5: 只在页面 header 绑定导航事件**

在 `viewForSupplementaryElementOfKind` 中加入：

```swift
headerView.onReviewSync = { [weak self] in
    self?.showSyncGatewaysPage()
}
```

并新增：

```swift
private func showSyncGatewaysPage() {
    let controller = SyncGatewaysViewController()
    navigationController?.pushViewController(controller, animated: true)
}
```

`handleEntrySyncReview()` 必须继续只调用 `finishEntrySyncOverlay()`。

- [ ] **Step 6: 将 Sync page 加入四个 app target**

在 `project.pbxproj` 中新增一个 file reference、四个 build file，并分别加入四个 Sources phase；不改依赖、Build Settings 或其他资源。

- [ ] **Step 7: 运行 Review、Entry 与 strings 契约**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 两个 contract 均 passed，两份 strings 均 `OK`；弹窗 Review 仍为 dismiss-only。

---

### Task 5: 聚焦回归、范围检查和四品牌 iPhoneOS 构建

**Files:**

- Create after implementation: `docs/260813_1429_site_review_sync_banner_implementation_summary.md`
- Verify all files modified in Tasks 1-4.

**Interfaces:**

- Consumes: Tasks 1-4 的最终实现。
- Produces: source/test/build 证据和真实服务器、真机、Gateway 端到端待验收边界。

- [ ] **Step 1: 重新编译并运行三项核心测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift -o /tmp/SiteEntryTimeZoneSyncPolicyTests
/tmp/SiteEntryTimeZoneSyncPolicyTests
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift -o /tmp/SiteEntryTimeZoneSyncCoordinatorTests
/tmp/SiteEntryTimeZoneSyncCoordinatorTests
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: Policy、Coordinator、Entry Contract、Review Contract 全部 passed。

- [ ] **Step 2: 回归既有 Site 时区与提示契约**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift Tests/Site/SitePropsEditPolicyTests.swift -o /tmp/SitePropsEditPolicyTests
/tmp/SitePropsEditPolicyTests
swiftc -parse-as-library Tests/Site/SiteTimeZonePersistenceContractTests.swift -o /tmp/SiteTimeZonePersistenceContractTests
/tmp/SiteTimeZonePersistenceContractTests SunSmart/Common/Data/SiteData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
swiftc -parse-as-library Tests/Site/SitePropsAPIContractTests.swift -o /tmp/SitePropsAPIContractTests
/tmp/SitePropsAPIContractTests SunSmart/Common/Network/NetowrkReqeustApi.swift SunSmart/Main/Site/Model/SitePropsAPIClient.swift SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
swiftc -parse-as-library Tests/Site/SiteEditAlertTransitionContractTests.swift -o /tmp/SiteEditAlertTransitionContractTests
/tmp/SiteEditAlertTransitionContractTests component SunSmart/Common/View/SRAlertView.swift
/tmp/SiteEditAlertTransitionContractTests edit-site SunSmart/Main/Site/Controller/SiteEditViewController.swift
swiftc -parse-as-library Tests/Site/SiteGatewayOnlineStateContractTests.swift -o /tmp/SiteGatewayOnlineStateContractTests
/tmp/SiteGatewayOnlineStateContractTests SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Common/Data/ImportData.swift
```

Expected: 全部输出各自的 passed；Site gateway association refresh 仍调用同一个 `loadSiteRequest()`，但不会再次展示 `Sync status`。

- [ ] **Step 3: 检查本地化、格式和范围**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
git status --short
rg -n "MeshAPI|TimeSet|TimeZoneSet|gatewayBind|gatewayUnbind|scan|connect" SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift
git diff -U12 -- SunSmart/Main/Site/Controller/SiteViewController.swift | rg -n "pushViewController|handleEntrySyncReview|showSyncGatewaysPage"
```

Expected:

- 两份 strings 输出 `OK`；
- 无 whitespace error；
- 新组件和空页面没有 Gateway/BLE/Mesh 行为；
- 新增 push 只来自页面组件入口，弹窗 `handleEntrySyncReview` 没有 push；
- `git status` 中原有未提交改动得到保留，没有无关格式化。

- [ ] **Step 4: 直接构建四个 generic iPhoneOS scheme**

依次运行，不并行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四项均 `BUILD SUCCEEDED`。

- [ ] **Step 5: 写实施总结并记录验收边界**

总结至少记录：

- 已验证：纯策略矩阵、首次一次性 Overlay、后续刷新页面状态、Figma 源码契约、双 header、空页面路由、本地化语法、四品牌编译。
- 未验证：真实 `/get/siteprops` 字段完整性、Editor Space 用户更新 Site props 的服务器授权、真机动态高度与按钮触感、真实 Gateway/BLE/Mesh 同步。
- 明确说明：本期 `Sync gateways` 为空页面，未修改任何 Gateway Offset。

## Implementation Completion Criteria

- 首次 Overlay 的 `LATER` 与 `REVIEW SYNC` 关闭后，Site 页面已经呈现最终 Review 状态。
- Site 与 Gateway 都正常时保持现状；有 pending Gateway 时显示服务器实际 Offset 和准确数量。
- app-to-cloud 成功后按新服务器时区重算；失败后按原 cloud timezone 保留或隐藏组件。
- 后续下拉刷新或 gateway association refresh 更新组件但不重复弹窗。
- 请求失败或非法响应不清空旧组件；合法快照确认全部一致后组件消失。
- All Spaces 与 Favourites 状态一致，Figma 尺寸/颜色/间距契约通过。
- 页面 `Review sync` 进入空的 `Sync gateways`，弹窗 `REVIEW SYNC` 不导航。
- English、简体中文和四个 app target 均通过验证。
