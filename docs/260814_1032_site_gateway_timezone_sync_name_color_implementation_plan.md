# Site 网关时区同步名称颜色实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with checkpoints. Per project instructions, use Inline Execution and do not dispatch subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Site 页面 `Overview` 右侧和 `SiteGatewaysMenuView` 中需要同步时区的 Gateway 名称使用 `#BB4D00`，不需要同步的 Gateway 完全保留现有颜色与交互。

**Architecture:** 复用 `SyncGatewaysContextSelectionPolicy` 的既有权限、offset、dirty override 与 ID 标准化逻辑，由 `SyncGatewaysContextBuilder.makeTargets` 统一生成待同步 Gateway targets。`SiteViewController` 只把标准化待同步 ID 投影到 `GatewayListItem` 和 `GatewayMenuData`，两个 View 只消费显式展示状态，不自行判断业务状态。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、standalone `swiftc` source contract、Xcode generic iPhoneOS build。

## Global Constraints

- 需要同步时区的 Gateway 名称固定使用 `#BB4D00`，即 `RGB(187, 77, 0)`。
- `GatewayListView` 中待同步颜色优先于选中颜色；原有选中下划线继续显示。
- 不需要同步的 Gateway 保持现状：选中使用 `Bar_Color`，未选中使用 `ImportantText_Color`。
- `Overview`、Add Gateway、连接状态点、Gateway 图标、同步失败图标、背景、字体、布局、分隔线和交互保持现状。
- 不修改 `SyncGatewayCell`，不改变 Gateway Time Set、BLE/Mesh、Site timezone 仲裁、Review Sync 或云同步流程。
- 不新增用户可见文案，不修改 English、简体中文本地化、资源、依赖或 target 配置。
- 保留 worktree 中已有未提交 UI、资源、测试与文档改动；不得 reset、覆盖或混入无关格式化。
- 构建只使用 generic iPhoneOS；禁止 Simulator 验证和 shell 包装/日志重定向。
- 未获得用户明确授权时不执行 `git commit`、push 或 merge；每个任务仅提供建议提交边界与信息。

---

## 文件职责与变更边界

- `SunSmart/Main/Site/Model/SyncGatewaysContext.swift`
  - 新增 `SyncGatewaysContextBuilder.makeTargets(...) -> [SyncGatewayRuntimeTarget]`，成为完整 Sync Context 与 Site 名称状态的共享 target 构建入口。
- `SunSmart/Main/Site/View/GatewayListView.swift`
  - 定义共享待同步名称颜色；扩展 `GatewayListItem.needsTimeZoneSync`；实现确认后的颜色优先级。
- `SunSmart/Main/Site/View/SiteGatewaysMenuView.swift`
  - 扩展 `GatewayMenuData.needsTimeZoneSync`；仅调整 Gateway 名称颜色并显式恢复复用 cell 颜色。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 查询待同步 ID；统一构造 Gateway list items；向菜单数据传递同一状态。
- `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
  - 新增无 UIKit 运行依赖的 source contract，覆盖共享入口、颜色优先级、Overview、Add Gateway、复用恢复与三个 list item 构造入口。
- `scripts/check_site_sync_gateways.sh`
  - 编译并运行新增 contract，继续作为本功能聚合检查入口。

---

### Task 1: 提取共享 Gateway 同步目标构建入口

**Files:**

- Create: `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
- Modify: `scripts/check_site_sync_gateways.sh:18`
- Modify: `SunSmart/Main/Site/Model/SyncGatewaysContext.swift:100-174`
- Test: `Tests/Site/SyncGatewaysContextTests.swift`

**Interfaces:**

- Consumes: `SyncGatewaysContextSelectionPolicy.select(scope:targetOffsetMinutes:remote:local:)`、`GatewayModel.resolveNode(in:)`、`SiteGatewayAccessScope.resolve(remote:)`。
- Produces: `SyncGatewaysContextBuilder.makeTargets(targetTimeZone:remote:meshNetwork:gatewayModels:) -> [SyncGatewayRuntimeTarget]`。
- Produces: `SyncGatewaysContextBuilder.make(...)` 继续返回相同 `SyncGatewaysContext`，但内部 targets 必须来自 `makeTargets(...)`。

- [ ] **Step 1: 创建只覆盖共享 Context 入口的失败契约**

创建 `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`：

```swift
import Foundation

@main
struct SiteGatewayTimeZoneNameColorContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            fatalError("Expected context, gateway list, gateway menu, and site controller paths")
        }

        let context = try source(arguments[1])
        _ = try source(arguments[2])
        _ = try source(arguments[3])
        _ = try source(arguments[4])

        require(
            context.contains("static func makeTargets("),
            "Context builder must expose one reusable target construction entry"
        )
        require(
            context.contains("let targets = makeTargets("),
            "Full SyncGatewaysContext construction must reuse makeTargets"
        )
        require(
            occurrences(of: "SyncGatewaysContextSelectionPolicy.select(", in: context) == 1,
            "Gateway selection policy must not be duplicated"
        )

        print("SiteGatewayTimeZoneNameColorContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
```

- [ ] **Step 2: 将新契约接入现有聚合脚本**

在 `scripts/check_site_sync_gateways.sh` 的 `SyncGatewaysContextTests` 之后加入：

```bash
swiftc -parse-as-library \
  Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift \
  -o /tmp/SiteGatewayTimeZoneNameColorContractTests
/tmp/SiteGatewayTimeZoneNameColorContractTests \
  SunSmart/Main/Site/Model/SyncGatewaysContext.swift \
  SunSmart/Main/Site/View/GatewayListView.swift \
  SunSmart/Main/Site/View/SiteGatewaysMenuView.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift
```

- [ ] **Step 3: 运行新契约并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift -o /tmp/SiteGatewayTimeZoneNameColorContractTests
/tmp/SiteGatewayTimeZoneNameColorContractTests SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: FAIL，错误为 `Context builder must expose one reusable target construction entry`，而不是参数数量或文件路径错误。

- [ ] **Step 4: 提取最小共享实现**

在 `SyncGatewaysContextBuilder` 中新增：

```swift
static func makeTargets(
    targetTimeZone: SiteTimeZoneValue,
    remote: SiteEntryTimeZoneRemoteSnapshot,
    meshNetwork: MeshNetwork,
    gatewayModels: [GatewayModel]
) -> [SyncGatewayRuntimeTarget] {
    var modelsByID: [String: GatewayModel] = [:]
    gatewayModels.forEach { model in
        guard let id = SiteGatewayAccessScope.normalize(model.mac),
              modelsByID[id] == nil else {
            return
        }
        modelsByID[id] = model
    }

    let local = modelsByID.reduce(into: [String: SyncGatewayLocalCandidate]()) {
        result, pair in
        let node = pair.value.resolveNode(in: meshNetwork)
        result[pair.key] = SyncGatewayLocalCandidate(
            displayName: pair.value.name,
            offsetMinutes: (node?.timezone?.secondsFromGMT()).map { $0 / 60 },
            isCloudDirty: pair.value.needUploadCloud,
            hasGatewayModel: true,
            hasNode: node != nil
        )
    }
    let descriptors = SyncGatewaysContextSelectionPolicy.select(
        scope: SiteGatewayAccessScope.resolve(remote: remote),
        targetOffsetMinutes: targetTimeZone.offsetMinutes,
        remote: remote.gateways.enumerated().map { index, gateway in
            SyncGatewayRemoteCandidate(
                id: gateway.id,
                offsetMinutes: gateway.offsetMinutes,
                order: index
            )
        },
        local: local
    )
    return descriptors.map { descriptor in
        let gateway = modelsByID[descriptor.id]
        return SyncGatewayRuntimeTarget(
            descriptor: descriptor,
            gateway: gateway,
            node: gateway?.resolveNode(in: meshNetwork)
        )
    }
}
```

将 `make(...)` 中原有 `modelsByID`、`local`、`descriptors` 和 `targets` 构造替换为：

```swift
let targets = makeTargets(
    targetTimeZone: targetTimeZone,
    remote: remote,
    meshNetwork: meshNetwork,
    gatewayModels: gatewayModels
)
```

保留后续 Network Key resolution 与 `SyncGatewaysContext` 返回逻辑不变。

- [ ] **Step 5: 运行聚焦测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Common/Data/SiteTimeZoneValue.swift SunSmart/Main/Site/Model/SitePropsEditPolicy.swift SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift SunSmart/Main/Site/Model/SyncGatewaysContext.swift Tests/Site/SyncGatewaysContextTests.swift -o /tmp/SyncGatewaysContextTests
/tmp/SyncGatewaysContextTests
swiftc -parse-as-library Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift -o /tmp/SiteGatewayTimeZoneNameColorContractTests
/tmp/SiteGatewayTimeZoneNameColorContractTests SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: 分别输出 `SyncGatewaysContextTests passed` 与 `SiteGatewayTimeZoneNameColorContractTests passed`。

- [ ] **Step 6: 检查任务边界并记录建议提交**

Run:

```bash
git diff --check -- SunSmart/Main/Site/Model/SyncGatewaysContext.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift scripts/check_site_sync_gateways.sh
git diff -- SunSmart/Main/Site/Model/SyncGatewaysContext.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift scripts/check_site_sync_gateways.sh
```

Expected: 无空白错误，diff 只包含共享 target 构建、初始 contract 与脚本入口。

Suggested commit, only after explicit user authorization: `refactor: share gateway timezone sync targets`

---

### Task 2: 接入 Site 横向 Gateway 名称颜色

**Files:**

- Modify: `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
- Modify: `SunSmart/Main/Site/View/GatewayListView.swift:13-27,323-365`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2295-2340,2828-2860,2968-2992`

**Interfaces:**

- Consumes: Task 1 的 `SyncGatewaysContextBuilder.makeTargets(...)`。
- Produces: `SiteGatewayTimeZoneSyncAppearance.pendingNameColor: UIColor`。
- Produces: `GatewayListItem.needsTimeZoneSync: Bool`，initializer 默认值为 false。
- Produces: `SiteViewController.pendingTimeZoneSyncGatewayIDs() -> Set<String>`。
- Produces: `SiteViewController.makeGatewayListItems(_ gateways: [Gateway]) -> [GatewayListItem]`。

- [ ] **Step 1: 扩展契约，先锁定横向列表规则**

在 contract 中读取 `gatewayList` 与 `siteController`，并在 Context 断言后加入：

```swift
let gatewayList = try source(arguments[2])
let siteController = try source(arguments[4])

require(gatewayList.contains("enum SiteGatewayTimeZoneSyncAppearance"))
require(gatewayList.contains("static let pendingNameColor = RGB(187, 77, 0)"))
require(gatewayList.contains("var needsTimeZoneSync: Bool"))
require(gatewayList.contains("needsTimeZoneSync: Bool = false"))
require(gatewayList.contains("item.needsTimeZoneSync"))
require(gatewayList.contains("SiteGatewayTimeZoneSyncAppearance.pendingNameColor"))
require(gatewayList.contains("item.isSelected ? Bar_Color : ImportantText_Color"))
require(gatewayList.contains("underlineView.isHidden = !item.isSelected"))

require(
    siteController.contains("private func pendingTimeZoneSyncGatewayIDs() -> Set<String>"),
    "Site controller must expose one read-only pending ID query"
)
require(siteController.contains("SyncGatewaysContextBuilder.makeTargets("))
require(
    siteController.contains("private func makeGatewayListItems("),
    "All horizontal Gateway items must use one builder"
)
require(
    occurrences(of: "makeGatewayListItems(showGatewayModels)", in: siteController) == 2,
    "Header and all-space refresh must share the same item builder"
)
require(
    occurrences(of: "makeGatewayListItems(gatewayModels)", in: siteController) == 1,
    "Favourite refresh must preserve its existing Gateway source"
)
```

删除 Task 1 中用于忽略 `arguments[2]` 和 `arguments[4]` 的两行 `_ = try source(...)`，菜单文件仍可暂时读取后忽略。

- [ ] **Step 2: 运行契约并确认 RED**

重复 Task 1 Step 3 命令。

Expected: FAIL 于缺少 `SiteGatewayTimeZoneSyncAppearance` 或 `needsTimeZoneSync`，不得在 Context 共享入口断言处失败。

- [ ] **Step 3: 扩展 GatewayListItem 并实现颜色优先级**

在 `GatewayListView.swift` 增加模块内共享样式：

```swift
enum SiteGatewayTimeZoneSyncAppearance {
    static let pendingNameColor = RGB(187, 77, 0)
}
```

在 `GatewayListItem` 增加字段与默认参数：

```swift
var needsTimeZoneSync: Bool

init(
    id: String,
    title: String,
    status: GatewayConnectStatus? = nil,
    isSelected: Bool = false,
    gatewayModel: GatewayModel? = nil,
    needsTimeZoneSync: Bool = false
) {
    self.id = id
    self.title = title
    self.status = status
    self.isSelected = isSelected
    self.gatewayModel = gatewayModel
    self.needsTimeZoneSync = needsTimeZoneSync
}
```

将 `GatewayItemView.update(with:)` 的名称颜色改为：

```swift
titleLabel.textColor = item.needsTimeZoneSync
    ? SiteGatewayTimeZoneSyncAppearance.pendingNameColor
    : (item.isSelected ? Bar_Color : ImportantText_Color)
```

不得修改 `underlineView.isHidden = !item.isSelected` 以及状态点、失败图标、字体和 arrangedSubviews 逻辑。

- [ ] **Step 4: 在 SiteViewController 增加待同步 ID 查询**

在 `showSyncGatewaysPage()` 附近增加：

```swift
private func pendingTimeZoneSyncGatewayIDs() -> Set<String> {
    guard let remote = latestTimeZoneRemoteSnapshot,
          let storageValue = site.timezone,
          let targetTimeZone = SiteTimeZoneValue(storageValue: storageValue),
          targetTimeZone == remote.timezone,
          let meshNetwork = sitePrimaryMeshNetwork() else {
        return []
    }
    let targets = SyncGatewaysContextBuilder.makeTargets(
        targetTimeZone: targetTimeZone,
        remote: remote,
        meshNetwork: meshNetwork,
        gatewayModels: gatewayModels.map(\.model)
    )
    return Set(targets.map(\.descriptor.id))
}
```

该 guard 必须与 `showSyncGatewaysPage()` 的证据条件一致；未知状态返回空集合，不把未知状态标为待同步。

- [ ] **Step 5: 统一三个 Gateway list items 构造入口**

增加 helper：

```swift
private func makeGatewayListItems(_ gateways: [Gateway]) -> [GatewayListItem] {
    let pendingIDs = pendingTimeZoneSyncGatewayIDs()
    var items = gateways.map { gateway in
        let id = SiteGatewayAccessScope.normalize(gateway.mac)
        return GatewayListItem(
            id: gateway.mac,
            title: gateway.name,
            status: gateway.connectStatus,
            gatewayModel: gateway.model,
            needsTimeZoneSync: id.map(pendingIDs.contains) ?? false
        )
    }
    if !items.isEmpty {
        items.insert(
            GatewayListItem(id: "", title: "overview".localizedString),
            at: 0
        )
    }
    return items
}
```

精确替换三个现有构造块：

- all-space 云同步成功刷新：`let items = makeGatewayListItems(showGatewayModels)`。
- favourite Gateway error 刷新：`let items = makeGatewayListItems(gatewayModels)`，保留当前数据源，不顺手改成 `showGatewayModels`。
- collection supplementary Header：`let items = makeGatewayListItems(showGatewayModels)`。

调用 `gatewayListView.updateItems(items)`、`selectedIndex` 与延迟清理同步状态的代码保持不变。

- [ ] **Step 6: 运行 contract 与既有 Sync Gateway 回归**

Run:

```bash
/tmp/SiteGatewayTimeZoneNameColorContractTests SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift
scripts/check_site_sync_gateways.sh
```

Expected: 新 contract 与现有聚合检查均 passed；`SyncGatewaysUIContractTests` 仍不要求修改 `SyncGatewayCell`。

- [ ] **Step 7: 检查任务边界并记录建议提交**

Run:

```bash
git diff --check -- SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift
git diff -- SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift
```

Expected: 只包含共享颜色、展示字段、待同步 ID 查询与三个 items 构造入口；不包含 `SyncGatewayCell`、本地化或资源变更。

Suggested commit, only after explicit user authorization: `feat: highlight gateways needing timezone sync`

---

### Task 3: 接入 SiteGatewaysMenuView 名称颜色

**Files:**

- Modify: `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
- Modify: `SunSmart/Main/Site/View/SiteGatewaysMenuView.swift:12-17,157-191`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2834-2859`

**Interfaces:**

- Consumes: Task 2 的 `pendingTimeZoneSyncGatewayIDs()` 与 `SiteGatewayTimeZoneSyncAppearance.pendingNameColor`。
- Produces: `SiteGatewaysMenuView.GatewayMenuData.needsTimeZoneSync: Bool`。
- Preserves: `SiteGatewaysMenuView.show(...)` 签名、选择回调、Add Gateway 回调和默认 `titleColor`。

- [ ] **Step 1: 扩展契约，锁定菜单颜色与复用恢复**

在 contract 中读取 `gatewayMenu`，并加入：

```swift
let gatewayMenu = try source(arguments[3])

require(gatewayMenu.contains("let needsTimeZoneSync: Bool"))
require(gatewayMenu.contains("data.needsTimeZoneSync"))
require(gatewayMenu.contains("SiteGatewayTimeZoneSyncAppearance.pendingNameColor"))
require(
    occurrences(of: "cell.titleLabel.textColor = titleColor", in: gatewayMenu) >= 1,
    "Normal Gateway and Add Gateway rows must restore the original title color"
)
require(gatewayMenu.contains("cell.backgroundColor = selectIndex == indexPath.row"))
require(gatewayMenu.contains("cell.iconImageView.image = UIImage(named: \"gateway_status_online\")"))

require(
    siteController.contains("SiteGatewaysMenuView.GatewayMenuData("),
    "Site controller must still build menu presentation data"
)
require(
    occurrences(
        of: "needsTimeZoneSync: id.map(pendingIDs.contains) ?? false",
        in: siteController
    ) == 2,
    "Horizontal list and menu data must use the same normalized pending ID set"
)
```

删除用于忽略 `arguments[3]` 的 `_ = try source(...)`。

- [ ] **Step 2: 运行契约并确认 RED**

重复 Task 1 Step 3 命令。

Expected: FAIL 于 `GatewayMenuData` 缺少 `needsTimeZoneSync`；Task 1 和 Task 2 的断言必须保持 GREEN。

- [ ] **Step 3: 扩展菜单展示模型并实现显式颜色恢复**

扩展 `GatewayMenuData`：

```swift
struct GatewayMenuData {
    let name: String
    let status: GatewayConnectStatus
    let needsTimeZoneSync: Bool
}
```

在 `cellForRowAt` 中把名称颜色放入各自分支：

```swift
if indexPath.row == datas.count {
    cell.cellStyle = .none
    cell.titleX = SCRXFrom(8)
    cell.titleLabel.text = "＋" + "add_gateway".localizedString
    cell.titleLabel.textColor = titleColor
} else {
    let data = datas[indexPath.row]
    cell.cellStyle = .icon
    // 保留现有 status -> icon 映射
    cell.iconX = SCRXFrom(8)
    cell.titleX = SCRXFrom(22)
    cell.titleLabel.text = data.name
    cell.titleLabel.textColor = data.needsTimeZoneSync
        ? SiteGatewayTimeZoneSyncAppearance.pendingNameColor
        : titleColor
}
```

删除分支后的无条件 `cell.titleLabel.textColor = titleColor`。字体、背景、separator、arrow、corner radius 和 selection style 保持原代码。

- [ ] **Step 4: 在菜单打开时传递同一待同步 ID 集合**

将 `gatewayListViewDidClickMenu(_:)` 的数据构造改为：

```swift
let pendingIDs = pendingTimeZoneSyncGatewayIDs()
let datas = showGatewayModels.map { gateway in
    let id = SiteGatewayAccessScope.normalize(gateway.mac)
    return SiteGatewaysMenuView.GatewayMenuData(
        name: gateway.name,
        status: gateway.connectStatus,
        needsTimeZoneSync: id.map(pendingIDs.contains) ?? false
    )
}
```

菜单锚点、`selectIndex`、选择回调、`setupData()` 与 Add Gateway 回调保持不变。

- [ ] **Step 5: 运行聚焦契约与聚合检查**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift -o /tmp/SiteGatewayTimeZoneNameColorContractTests
/tmp/SiteGatewayTimeZoneNameColorContractTests SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift
scripts/check_site_sync_gateways.sh
```

Expected: 输出 `SiteGatewayTimeZoneNameColorContractTests passed` 与 `SiteSyncGateways checks passed`。

- [ ] **Step 6: 检查任务边界并记录建议提交**

Run:

```bash
git diff --check -- SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift
git diff -- SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift
```

Expected: 菜单只新增状态输入和名称颜色分支；其他控件与回调无变化。

Suggested commit, only after explicit user authorization: `feat: highlight timezone sync gateways in site menu`

---

### Task 4: 完整回归与四品牌构建验证

**Files:**

- Verify: `SunSmart/Main/Site/Model/SyncGatewaysContext.swift`
- Verify: `SunSmart/Main/Site/View/GatewayListView.swift`
- Verify: `SunSmart/Main/Site/View/SiteGatewaysMenuView.swift`
- Verify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Verify: `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
- Verify: `scripts/check_site_sync_gateways.sh`

**Interfaces:**

- Consumes: Tasks 1–3 的最终生产与测试代码。
- Produces: 聚焦测试、静态检查与四个 generic iPhoneOS target 的验证证据。

- [ ] **Step 1: 记录现有 dirty worktree 并核对任务文件**

Run:

```bash
git status --short
git diff --name-only
```

Expected: 保留任务开始前已有的 Gateway icon、SyncGatewayCell、SupportingViews、测试和文档改动；不得清理、覆盖或声称这些都是本任务产生。

- [ ] **Step 2: 运行聚合测试与 diff check**

Run:

```bash
scripts/check_site_sync_gateways.sh
git diff --check
```

Expected: 输出 `SiteSyncGateways checks passed`，`git diff --check` 无输出。

- [ ] **Step 3: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 执行最终范围审查**

Run:

```bash
git diff -- SunSmart/Main/Site/Model/SyncGatewaysContext.swift SunSmart/Main/Site/View/GatewayListView.swift SunSmart/Main/Site/View/SiteGatewaysMenuView.swift SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift scripts/check_site_sync_gateways.sh
git status --short
```

Expected:

- 待同步 Gateway 在横向列表中无论选中与否都使用 `#BB4D00`。
- 不需要同步的横向 Gateway 仍按 `Bar_Color` / `ImportantText_Color` 展示。
- `Overview`、选中下划线和所有非名称控件保持原逻辑。
- 菜单待同步 Gateway 使用 `#BB4D00`；普通 Gateway 和 Add Gateway 恢复现有 `titleColor`。
- `SyncGatewayCell`、本地化、资源、target 配置和依赖没有由本任务修改。
- 现有 dirty worktree 改动仍被保留并与本任务边界清楚区分。

- [ ] **Step 8: 记录验收边界**

交付总结必须明确：standalone contracts 与 generic iPhoneOS builds 不能证明真实服务器快照、Owner/Editor/Visitor 生产权限、BLE/Mesh、cloud dirty 生命周期或真机视觉结果。仍需在真机验证混合 Gateway、选中切换、超过四个 Gateway、菜单 cell 复用，以及同步成功后的颜色恢复。

Suggested final commit, only after explicit user authorization: `feat: show gateway timezone sync name state`

---

## Inline Execution Checkpoints

- Checkpoint A：Task 1 完成后，审查 `makeTargets` 是否仅提取现有逻辑，确保 Sync Context 行为不变。
- Checkpoint B：Task 2 完成后，审查三个 `GatewayListItem` 构造入口、Overview 默认值与选中颜色优先级。
- Checkpoint C：Task 3 完成后，审查菜单 Add Gateway 和 cell reuse 颜色恢复，确认其他控件无变化。
- Checkpoint D：Task 4 完成后，只基于实际命令输出声明测试和构建结果，并保留真机/服务器验收边界。
