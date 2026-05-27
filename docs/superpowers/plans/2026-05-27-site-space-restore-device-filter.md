# Site Space Restore Device Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Site 右上角恢复页只展示 gateway，让 Space 添加设备弹窗恢复页只展示当前 space 的非 gateway 设备。

**Architecture:** 在 `DeviceRestoreViewController` 增加入口级过滤策略，默认不过滤。恢复页在 `.specified(nodes:)` 数据源和扫描回调两处调用同一个过滤函数，入口只负责传入策略，恢复执行和同步流程保持不变。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 增加 `RestoreFilter`。
  - 扩展初始化参数并保存策略。
  - 增加 `shouldIncludeRestoreNode(_:)`、`isNodeRestored(_:)`、`pendingRestoreNodes(from:)`。
  - 用统一过滤函数处理 `.specified(nodes:)` 和扫描发现的节点。
  - 调整 `.specified(nodes:)` 的 footer 分母和自动停止条件，避免过滤后目标数量不一致。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - Site 右上角恢复入口传入 `.gatewaysOnly`。
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Space 添加设备弹窗恢复入口传入 `.currentSpaceNonGateways`。

## Task 1: Add Restore Filter To DeviceRestoreViewController

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:90-100`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:263-268`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:376-401`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:428-451`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:500-508`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2234-2240`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2635-2641`

- [ ] **Step 1: Add filter storage and constructor parameter**

Update the property area and initializer to this shape:

```swift
    let site: SiteData
    let space: SpaceData?

    /// 恢复数据模式
    let restoreMode: RestoreMode
    /// 恢复设备入口过滤
    private let restoreFilter: RestoreFilter
```

```swift
    init(site: SiteData, space: SpaceData?, restoreMode: RestoreMode, restoreFilter: RestoreFilter = .all) {
        self.site = site
        self.space = space
        self.restoreMode = restoreMode
        self.restoreFilter = restoreFilter
        super.init(nibName: nil, bundle: nil)
    }
```

- [ ] **Step 2: Add RestoreFilter enum**

Add the enum next to `RestoreMode`:

```swift
    /// 恢复设备入口过滤
    enum RestoreFilter {
        /// 不限制设备类型或归属
        case all
        /// 仅恢复 gateway 设备
        case gatewaysOnly
        /// 仅恢复当前 space 内的非 gateway 设备
        case currentSpaceNonGateways
    }
```

- [ ] **Step 3: Add shared filter helpers**

Add these helpers before `setupDataSource()`:

```swift
    private func shouldIncludeRestoreNode(_ node: Node) -> Bool {
        switch restoreFilter {
        case .all:
            return true
        case .gatewaysOnly:
            return node.deviceType == .gateway
        case .currentSpaceNonGateways:
            guard let space else {
                return false
            }
            return node.deviceType != .gateway && node.subNetworkId == space.meshNetworkId
        }
    }

    private func isNodeRestored(_ node: Node) -> Bool {
        restoreNodes.contains {
            $0.macAddress == node.macAddress || $0.macAddress?.toOldMacAddress() == node.macAddress
        }
    }

    private func pendingRestoreNodes(from nodes: [Node]) -> [Node] {
        nodes.filter { node in
            shouldIncludeRestoreNode(node) && !isNodeRestored(node)
        }
    }
```

- [ ] **Step 4: Filter specified restore data source**

Replace the `.specified(let nodes)` branch in `setupDataSource()` with:

```swift
        case .specified(let nodes):
            sections.removeAll()
            /// 需要继续恢复的设备，如已恢复的设备将不展示
            let nextRestoreNodes = pendingRestoreNodes(from: nodes)
            nextRestoreNodes.forEach { node in
                let data = DeviceRestoreData(node: node)
                if let section = sections.first(where: { $0.group == node.group }) {
                    section.restoreDatas.append(data)
                } else {
                    let section = DeviceRestoreSection(group: node.group, restoreDatas: [data])
                    if node.group == nil {
                        sections.insert(section, at: 0)
                    } else {
                        sections.append(section)
                    }
                }
            }
            showSections = sections
```

- [ ] **Step 5: Filter scanned restore nodes**

In `startScan()`, remove the existing `space != nil, node.deviceType == .gateway` check and use the shared filter before mutating `unprovisionedDevice`:

```swift
            guard shouldIncludeRestoreNode(node) else {
                return
            }
```

Then replace the `.specified(let nodes)` membership check with:

```swift
            if case .specified(let nodes) = self.restoreMode {
                let nextRestoreNodes = self.pendingRestoreNodes(from: nodes)
                if !nextRestoreNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    return
                }
            }
```

- [ ] **Step 6: Adjust specified footer and stop target count**

In the scan callback, replace the `.specified(let nodes)` footer and stop condition with:

```swift
            case .specified(let nodes):
                let restoreTargetCount = self.pendingRestoreNodes(from: nodes).count
                self.footerView.selectCountLabel.text = "\(self.showDevices.count)/\(restoreTargetCount)"
                // 已找到全部设备
                if self.allDevices.count >= restoreTargetCount {
                    stopScan()
                    if self.automationRestore { // 自动恢复设备流程
                        addSelectedBtnClick()
                    }
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
                    }
                    return
                }
```

In `updateUIState()`, replace the `.specified(let nodes)` footer count with:

```swift
            case .specified(let nodes):
                footerView.selectCountLabel.text = "\(showDevices.count)/\(pendingRestoreNodes(from: nodes).count)"
```

- [ ] **Step 7: Run focused static checks**

Run:

```bash
rg -n "RestoreFilter|shouldIncludeRestoreNode|pendingRestoreNodes|space != nil, node.deviceType == \\.gateway" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- `RestoreFilter`, `shouldIncludeRestoreNode`, and `pendingRestoreNodes` are present.
- The old `space != nil, node.deviceType == .gateway` scan guard is absent.

## Task 2: Wire Entry-Specific Filters

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:1153-1161`
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift:505-514`

- [ ] **Step 1: Update Site restore entry**

Change the Site entry constructor to:

```swift
        let vc = DeviceRestoreViewController(
            site: site,
            space: nil,
            restoreMode: .default,
            restoreFilter: .gatewaysOnly
        )
```

Keep `deviceRestoreCallback` unchanged.

- [ ] **Step 2: Update Space restore entry**

Change the Space entry constructor to:

```swift
        let vc = DeviceRestoreViewController(
            site: self.site,
            space: space,
            restoreMode: .default,
            restoreFilter: .currentSpaceNonGateways
        )
```

Keep `deviceRestoreCallback` unchanged.

- [ ] **Step 3: Confirm other entries use default behavior**

Run:

```bash
rg -n "DeviceRestoreViewController\\(site:" SunSmart -g '*.swift'
```

Expected:

- `SiteViewController.swift` passes `.gatewaysOnly`.
- `DevicesViewController.swift` passes `.currentSpaceNonGateways`.
- Firmware and 1.5 container entries compile through the default `.all` parameter.

## Task 3: Build Verification

**Files:**
- Verify only; no additional source edits.

- [ ] **Step 1: Check git diff scope**

Run:

```bash
git diff -- SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Controller/DevicesViewController.swift
```

Expected:

- Only filter strategy, constructor call sites, and related specified-count updates changed.
- No localization, assets, target settings, dependency, or unrelated formatting changes.

- [ ] **Step 2: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Controller/DevicesViewController.swift
git commit -m "fix: filter restore devices by entry"
```

Expected:

- Commit includes only the three source files above.

## Plan Self-Review

- Spec coverage: Site gateway-only、Space current-space non-gateway、其他入口默认不变、扫描和指定数据源统一过滤均有任务覆盖。
- Placeholder scan: plan contains no incomplete markers.
- Type consistency: plan consistently uses `RestoreFilter`, `restoreFilter`, `shouldIncludeRestoreNode(_:)`, `pendingRestoreNodes(from:)`, `node.subNetworkId`, and `space.meshNetworkId`.
