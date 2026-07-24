# Site Gateway Online 状态真值分离实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复从 Space 返回 Site 后 Wi‑Fi/4G Gateway 的 `Internet Online` 计数和 Space online 图标被本地 Mesh 子网状态错误覆盖的问题。

**Architecture:** `SpaceData.gatewayStatus` 保持服务器权威状态，`SiteViewController.setupData()` 只读渲染；Gateway 运行期对象显式从 Site 主网解析，不依赖当前全局 Mesh 上下文。Gateway 绑定拓扑发生服务器确认的变化后，通过专用通知让 Site 在返回时执行一次权威 `siteInfo` 刷新。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Foundation 命令行契约测试、Bash、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复、计划和总结使用简体中文；现有 UI 文案保持英文及既有国际化，不新增用户可见文案。
- 采用已确认的方案 B，不实现 unknown/stale UI，不修改 Wi‑Fi Gateway V1.9、4G CSQ/RSSI 或 NordicSigMeshSDK。
- 不新增 Auth 信息、服务器凭据或敏感日志。
- 保持改动聚焦，不重构无关模块，不格式化大量无关文件。
- `SpaceData.relevanceGatewayId`、`gatewayStatus`、`gatewayLastOnline` 只由服务器导入或服务器确认的绑定结果更新。
- `Node.state`、Wi‑Fi RSSI、Wi‑Fi `networkStatus`、4G `csqRssi` 不参与 Site Internet online/offline 判定。
- All Spaces 与 Favourites 必须共享同一修复行为。
- 不修改本地化、资源、依赖和 target 配置。
- 执行方式使用 Inline Execution；除非用户明确要求，不使用 subagents。
- iOS 验证直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

- Create: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
  - 从源码提取目标函数，保护状态单向性、Site 主网解析和概览可见性。
- Create: `scripts/check_site_gateway_online_state.sh`
  - 编译并运行独立 Swift 契约测试。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 移除 Space Gateway 状态反向覆盖，显式解析 Site 主网，解耦概览可见性，并监听绑定拓扑变化。
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 记录 bind/unbind 是否实际改变服务器拓扑，并发出专用权威刷新通知。

---

### Task 1: 建立会失败的 Site Gateway 状态契约测试

**Files:**

- Create: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Create: `scripts/check_site_gateway_online_state.sh`
- Test: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`

**Interfaces:**

- Consumes: `SiteViewController.swift` 中的 `setupData()`、`loadGatewaysData()` 和 Gateway Header 渲染代码。
- Produces: `scripts/check_site_gateway_online_state.sh`，后续任务统一用它验证源码契约。

- [ ] **Step 1: 创建失败的状态所有权契约测试**

创建 `Tests/Site/SiteGatewayOnlineStateContractTests.swift`：

```swift
import Foundation

@main
struct SiteGatewayOnlineStateContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected SiteViewController.swift path")
        }

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )

        let setupData = section(
            in: source,
            from: "private func setupData()",
            to: "/// 添加通知监听"
        )
        require(
            !setupData.contains("space.gatewayStatus ="),
            "setupData must not mutate server-owned Space gateway status"
        )

        require(
            source.contains("private func sitePrimaryMeshNetwork() -> MeshNetwork?"),
            "SiteViewController must expose an explicit Site primary-network resolver"
        )

        let loadGatewaysData = section(
            in: source,
            from: "private func loadGatewaysData()",
            to: "// MARK: - Action"
        )
        require(
            loadGatewaysData.contains("sitePrimaryMeshNetwork()"),
            "loadGatewaysData must resolve gateways from the Site primary network"
        )
        require(
            loadGatewaysData.contains("model.resolveNode(in: meshNetwork)"),
            "Gateway node resolution must receive the explicit Site primary network"
        )
        require(
            !loadGatewaysData.contains("Gateway.resolve(model:"),
            "loadGatewaysData must not use the current global Mesh network implicitly"
        )
        require(
            !loadGatewaysData.contains("isWiFiGateway"),
            "Site Internet state loading must not branch by Wi-Fi versus 4G gateway type"
        )

        require(
            source.contains("private func shouldShowGatewayStatus(for spaces: [SpaceData]) -> Bool"),
            "Gateway overview visibility must have a shared server-state policy"
        )
        let visibilityUseCount = source.components(
            separatedBy: "shouldShowGatewayStatus(for: spaces)"
        ).count - 1
        require(
            visibilityUseCount >= 2,
            "Gateway status visibility policy must be reused by header rendering and layout"
        )

        print("SiteGatewayOnlineStateContractTests passed")
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let startRange = source.range(of: startMarker) else {
            fatalError("Missing source marker: \(startMarker)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: endMarker) else {
            fatalError("Missing source marker: \(endMarker)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
```

- [ ] **Step 2: 创建契约测试运行脚本**

创建 `scripts/check_site_gateway_online_state.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_source="$repo_root/Tests/Site/SiteGatewayOnlineStateContractTests.swift"
site_source="$repo_root/SunSmart/Main/Site/Controller/SiteViewController.swift"
temp_dir="$(mktemp -d)"
test_binary="$temp_dir/site_gateway_online_state_contract_tests"

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

swiftc "$test_source" -o "$test_binary"
"$test_binary" "$site_source"

echo "PASS: Site Gateway online-state source ownership checks passed."
```

- [ ] **Step 3: 赋予脚本执行权限**

Run:

```bash
chmod +x scripts/check_site_gateway_online_state.sh
```

Expected: 命令无输出并返回 0。

- [ ] **Step 4: 运行测试并确认当前实现失败**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected: FAIL，首个失败原因是 `setupData must not mutate server-owned Space gateway status`。

- [ ] **Step 5: 提交失败测试**

```bash
git add Tests/Site/SiteGatewayOnlineStateContractTests.swift scripts/check_site_gateway_online_state.sh
git commit -m "test: guard site gateway online state ownership"
```

---

### Task 2: 让 Site 状态渲染与当前 Mesh 子网解耦

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:257-290`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:708-751`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2303-2392`
- Test: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`

**Interfaces:**

- Consumes: `SiteData.meshUUID`、`SiteData.meshNetworkId`、`GatewayModel.resolveNode(in:)`、服务器导入的 `SpaceData.gatewayStatus`。
- Produces: `sitePrimaryMeshNetwork() -> MeshNetwork?`、`shouldShowGatewayStatus(for:) -> Bool` 和只读的 `setupData()`。

- [ ] **Step 1: 移除 `setupData()` 对服务器状态的反向覆盖**

在 `setupData()` 中删除以下完整区块：

```swift
allSpaces.forEach({ space in
    if let gateway = self.gatewayModels.first(where: { gateway in gateway.associatedSpaces.contains(where: { $0.spaceId == space.id }) }) {
        space.gatewayStatus = gateway.connectStatus == .online ? .online : .offline
    }else {
        space.gatewayStatus = .notBound
    }
})
```

删除后，`setupData()` 在 Gateway 筛选完成后直接执行：

```swift
self.allSpacesCollectionView.reloadData()
self.favouritesCollectionView.reloadData()
self.updateEmptyView()
```

- [ ] **Step 2: 添加显式 Site 主网解析**

在 `loadGatewaysData()` 前加入：

```swift
private func sitePrimaryMeshNetwork() -> MeshNetwork? {
    let manager = MeshNetworkManager.instance
    if let meshNetwork = manager.meshNetwork,
       meshNetwork.uuid.uuidString == site.meshUUID,
       manager.currentNetworkKey.isPrimary {
        return meshNetwork
    }
    return MeshNetwork.load(
        meshUUID: site.meshUUID,
        subnetworkId: site.meshNetworkId
    )
}
```

把 `loadGatewaysData()` 开头替换为：

```swift
private func loadGatewaysData() -> [Gateway] {
    guard let meshNetwork = sitePrimaryMeshNetwork() else {
        return []
    }

    let gatewayModels = GatewayModel.load(siteId: site.id).compactMap { model in
        guard let node = model.resolveNode(in: meshNetwork) else {
            return nil
        }
        return Gateway(model: model, node: node)
    }
```

保留现有 `gatewayModels.forEach` 的服务器状态到 `Gateway.connectStatus` 映射以及最终 `return gatewayModels`。

- [ ] **Step 3: 添加统一的 Gateway 状态区域可见性规则**

在 `loadGatewaysData()` 后加入：

```swift
private func shouldShowGatewayStatus(for spaces: [SpaceData]) -> Bool {
    let hasServerGatewayStatus = spaces.contains {
        $0.gatewayStatus != .notBound
    }
    return !site.spaces.isEmpty &&
        (!showGatewayModels.isEmpty ||
         hasServerGatewayStatus ||
         site.permission != .owner)
}
```

该方法只决定 Internet 状态区域是否显示，不改变 Add Gateway UI、Gateway 下拉列表或权限。

- [ ] **Step 4: 在 Header 渲染中复用可见性规则**

在 `collectionView(_:viewForSupplementaryElementOfKind:at:)` 完成 `spaces` 选择后加入：

```swift
let showGatewayStatus = shouldShowGatewayStatus(for: spaces)
```

删除两个分支内现有的：

```swift
headerView.gatewayStatusView.isHidden = site.spaces.isEmpty || showGatewayModels.isEmpty
```

和：

```swift
headerView.gatewayStatusView.isHidden = self.site.permission == .owner
```

在 `if showGatewayModels.count > 0 { ... } else { ... }` 结束后统一加入：

```swift
headerView.gatewayStatusView.isHidden = !showGatewayStatus
```

- [ ] **Step 5: 在 Header 高度计算中复用同一规则**

把 `referenceSizeForHeaderInSection` 中现有增加高度的条件替换为：

```swift
let spaces = collectionView == allSpacesCollectionView
    ? allSpaces
    : favouriteSpaces
if shouldShowGatewayStatus(for: spaces) {
    headerH += SCRYFrom(48)
}
```

保留 `headerW`、基础 `headerH` 和返回值。

- [ ] **Step 6: 运行契约测试并确认通过**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected:

```text
SiteGatewayOnlineStateContractTests passed
PASS: Site Gateway online-state source ownership checks passed.
```

- [ ] **Step 7: 检查补丁格式**

Run:

```bash
git diff --check
```

Expected: 无输出并返回 0。

- [ ] **Step 8: 提交 Site 状态修复**

```bash
git add SunSmart/Main/Site/Controller/SiteViewController.swift
git commit -m "fix: preserve site gateway internet status"
```

---

### Task 3: 绑定拓扑变化后触发服务器权威刷新

**Files:**

- Modify: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:12-16`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:341-354`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:514-621`
- Test: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`

**Interfaces:**

- Consumes: Task 2 的只读 `setupData()` 和现有 `reloadData`/`loadSiteRequest()` 返回刷新机制。
- Produces: `siteGatewayAssociationTopologyChangedNotificationName`、`AssociatedSpacesSaveResult`、`notifySiteGatewayAssociationTopologyChanged()`。

- [ ] **Step 1: 扩展契约测试，先要求关联拓扑刷新契约**

在 `print("SiteGatewayOnlineStateContractTests passed")` 前加入：

```swift
require(
    source.contains("let siteGatewayAssociationTopologyChangedNotificationName"),
    "Site must define a dedicated gateway-association topology notification"
)
require(
    source.contains("forName: .init(siteGatewayAssociationTopologyChangedNotificationName)"),
    "Site must observe gateway-association topology changes"
)

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected SiteViewController.swift and GatewayViewController.swift paths")
}
let gatewaySource = try String(
    contentsOfFile: CommandLine.arguments[2],
    encoding: .utf8
)
require(
    gatewaySource.contains("private struct AssociatedSpacesSaveResult"),
    "Gateway save flow must retain both success and topology-change outcomes"
)
require(
    gatewaySource.contains("let topologyChanged: Bool"),
    "Gateway association result must expose topologyChanged"
)
require(
    gatewaySource.contains("notifySiteGatewayAssociationTopologyChanged()"),
    "Gateway save flow must notify Site after confirmed topology changes"
)
```

同时把文件开头参数检查改为：

```swift
guard CommandLine.arguments.count == 3 else {
    fatalError("Expected SiteViewController.swift and GatewayViewController.swift paths")
}
```

并删除后面重复的 `guard CommandLine.arguments.count == 3`。

修改脚本变量：

```bash
gateway_source="$repo_root/SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
```

把运行测试二进制的命令改为：

```bash
"$test_binary" "$site_source" "$gateway_source"
```

- [ ] **Step 2: 运行测试并确认新契约失败**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected: FAIL，首个新失败原因是 `Site must define a dedicated gateway-association topology notification`。

- [ ] **Step 3: 在 Site 中定义并监听专用通知**

在现有通知名称旁加入：

```swift
let siteGatewayAssociationTopologyChangedNotificationName =
    "siteGatewayAssociationTopologyChangedNotification"
```

在 `addNotificationObserver()` 的 `siteGatewayDataChangedNotificaitonName` 监听之后加入：

```swift
NotificationCenter.default.addObserver(
    forName: .init(siteGatewayAssociationTopologyChangedNotificationName),
    object: nil,
    queue: nil
) { [weak self] _ in
    self?.reloadData = true
}
```

该监听只标记权威刷新；现有 `viewWillAppear` 会在返回 Site 时清除 `reloadData` 并调用一次 `loadSiteRequest()`。

- [ ] **Step 4: 让关联保存同时返回成功与拓扑变化**

在 `saveAssociatedSpacesIfNeeded()` 前加入：

```swift
private struct AssociatedSpacesSaveResult {
    let succeeded: Bool
    let topologyChanged: Bool
}
```

把 `saveAssociatedSpacesIfNeeded()` 完整替换为：

```swift
private func saveAssociatedSpacesIfNeeded() async -> AssociatedSpacesSaveResult {
    let oldSpaces = gatewayModel.associatedSpaces
    let newSpaces = setGatewayModel.associatedSpaces
    let addSpaces = newSpaces.filter { newSpace in
        !oldSpaces.contains(where: { $0.spaceId == newSpace.spaceId })
    }
    let unbindSpaces = oldSpaces.filter { oldSpace in
        !newSpaces.contains(where: { $0.spaceId == oldSpace.spaceId })
    }

    guard !addSpaces.isEmpty || !unbindSpaces.isEmpty else {
        return .init(succeeded: true, topologyChanged: false)
    }
    guard NetworkRequest.shared.networkable else {
        XWHUDManager.showTipHUD(
            "gateway_associated_no_network_message".localizedString,
            isLineFeed: true,
            afterDelay: 1.5
        )
        return .init(succeeded: false, topologyChanged: false)
    }

    var topologyChanged = false
    XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
    for space in addSpaces {
        let result = await NetworkRequest.shared.request(
            .gatewayBindSpace(spaceId: space.spaceId, gatewayId: gateway.mac)
        )
        switch result {
        case .success:
            topologyChanged = true
        case .failure(let error):
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD(error.localizedDescription)
            return .init(
                succeeded: false,
                topologyChanged: topologyChanged
            )
        }
    }
    for space in unbindSpaces {
        let result = await NetworkRequest.shared.request(
            .gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac)
        )
        switch result {
        case .success:
            topologyChanged = true
        case .failure(let error):
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD(error.localizedDescription)
            return .init(
                succeeded: false,
                topologyChanged: topologyChanged
            )
        }
    }
    XWHUDManager.hide()
    return .init(succeeded: true, topologyChanged: topologyChanged)
}
```

- [ ] **Step 5: 在保存入口处理完整成功与部分成功**

把 `saveBtnAction()` 的异步保存区块替换为：

```swift
Task { [weak self] in
    guard let self = self else { return }
    let associationResult = await self.saveAssociatedSpacesIfNeeded()
    guard associationResult.succeeded else {
        if associationResult.topologyChanged {
            self.notifySiteGatewayAssociationTopologyChanged()
        }
        self.updateSaveBtnState()
        return
    }
    self.persistGatewayConfiguration(
        name: name,
        associationTopologyChanged: associationResult.topologyChanged
    )
}
```

部分请求成功、后续请求失败时也必须通知 Site 权威刷新，避免服务器拓扑已经变化而本地继续显示旧状态。

- [ ] **Step 6: 在本地保存成功后发出专用通知**

把方法签名改为：

```swift
private func persistGatewayConfiguration(
    name: String,
    associationTopologyChanged: Bool
) {
```

在 `gateway.model.save()` 后加入：

```swift
if associationTopologyChanged {
    notifySiteGatewayAssociationTopologyChanged()
}
```

在 `persistGatewayConfiguration` 后加入：

```swift
private func notifySiteGatewayAssociationTopologyChanged() {
    NotificationCenter.default.post(
        name: .init(siteGatewayAssociationTopologyChangedNotificationName),
        object: gateway
    )
}
```

- [ ] **Step 7: 运行完整契约测试**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected:

```text
SiteGatewayOnlineStateContractTests passed
PASS: Site Gateway online-state source ownership checks passed.
```

- [ ] **Step 8: 检查补丁格式**

Run:

```bash
git diff --check
```

Expected: 无输出并返回 0。

- [ ] **Step 9: 提交绑定拓扑刷新**

```bash
git add Tests/Site/SiteGatewayOnlineStateContractTests.swift scripts/check_site_gateway_online_state.sh SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "fix: refresh site after gateway association changes"
```

---

### Task 4: 完成静态、多 Target 构建与交付验证

**Files:**

- Verify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Verify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Verify: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Verify: `scripts/check_site_gateway_online_state.sh`

**Interfaces:**

- Consumes: Tasks 1–3 的最终实现。
- Produces: 自动化契约、四品牌 iPhoneOS 构建结果和明确的真机待验收清单。

- [ ] **Step 1: 重新运行契约测试**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected:

```text
SiteGatewayOnlineStateContractTests passed
PASS: Site Gateway online-state source ownership checks passed.
```

- [ ] **Step 2: 检查最终差异范围**

Run:

```bash
git diff HEAD~2 -- SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift Tests/Site/SiteGatewayOnlineStateContractTests.swift scripts/check_site_gateway_online_state.sh
```

Expected: 只包含 Site 状态只读化、主网解析、概览可见性、绑定拓扑刷新和对应测试。

- [ ] **Step 3: 运行最终格式检查**

Run:

```bash
git diff --check HEAD~2 HEAD
```

Expected: 无输出并返回 0。

- [ ] **Step 4: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 8: 核对工作区与提交历史**

Run:

```bash
git status --short
```

Expected: 无输出。

Run:

```bash
git log -n 4 --oneline
```

Expected: 最新提交依次包含实现计划、状态契约测试、Site 状态修复和绑定拓扑刷新，且提交信息不包含 Codex 说明。

- [ ] **Step 9: 交付时明确真机待验收项**

最终总结必须区分：

- 已完成：契约测试、`git diff --check`、SunSmart/Archipelago/SLG Sync Plus/SylSmart generic iPhoneOS 构建。
- 待真机：Wi‑Fi 与 4G Gateway 在 All Spaces/Favourites 的进入 Space 后返回流程。
- 待真实服务器：Internet 真正 offline、绑定、解绑、删除后的 `siteInfo` 往返。
- 构建成功不代表 BLE、Wi‑Fi、4G 或服务器行为已经验收。

---

## 实施完成判定

只有同时满足以下条件才可声称代码修复完成：

- 新契约测试先在旧代码失败、在新代码通过。
- `setupData()` 不再写入 `SpaceData.gatewayStatus`。
- Gateway 节点解析显式使用 Site 主网。
- 主网节点解析失败不会隐藏服务器 Internet 状态。
- 绑定/解绑发生完整或部分服务器成功时，Site 都会安排权威刷新。
- Wi‑Fi 与 4G 没有新增状态分支。
- `git diff --check` 通过。
- 四个品牌 generic iPhoneOS 构建全部成功。

真机和真实服务器验收仍必须单独报告，不能由自动化或构建结果代替。
