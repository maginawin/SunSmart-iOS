# Debug 设备列表稳定排序 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Debug 页面设备列表按进入页面时 `MeshNetworkManager.instance.realNodes` 的原始顺序稳定展示，不再因为扫描到广播或 RSSI 更新而移动设备位置。

**Architecture:** 在 Debug 列表 item 中保存原始顺序索引，ViewModel 后续只更新设备 found/RSSI 状态，不改变顺序索引。列表仍按现有分类展示，每个分类内部使用原始顺序排序。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`

---

## 文件结构

- 修改 `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
  - 为 `SpaceDebugNodeItem` 增加 `displayOrder` 字段，表示 Debug 页面内部稳定排序索引。
- 修改 `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
  - `makeItems(nodes:)` 使用 `enumerated()` 生成 item，并写入 `displayOrder`。
  - `sections()` 去掉 `isFound` 和 `displayTitle` 排序，改为按 `displayOrder` 排序。
  - `updateFoundNode(_:)` 继续只更新 peripheral、RSSI、lastSeen，不改变 `displayOrder`。

## Task 1: 保存 Debug 设备原始顺序

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`

- [ ] **Step 1: 检查当前排序代码**

Run:

```bash
sed -n '90,130p' SunSmart/Main/Space/Debug/SpaceDebugModels.swift
sed -n '86,125p' SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
```

Expected:

```text
SpaceDebugNodeItem 当前没有 displayOrder 字段。
SpaceDebugViewModel.sections() 当前会先按 isFound 排序，再按 displayTitle 排序。
makeItems(nodes:) 当前直接用 nodes.map 生成字典。
```

- [ ] **Step 2: 修改 `SpaceDebugNodeItem`**

在 `SunSmart/Main/Space/Debug/SpaceDebugModels.swift` 中，将 `SpaceDebugNodeItem` 的属性区域改为以下结构：

```swift
struct SpaceDebugNodeItem {
    let node: Node
    let displayOrder: Int
    var peripheral: CBPeripheral?
    var rssi: Int?
    var lastSeen: Date?
    var isConnecting: Bool = false

    var address: Address {
        node.primaryUnicastAddress
    }
```

关键点：

- `displayOrder` 使用 `let`，扫描更新时不应改变。
- 字段位置放在 `node` 后面，表示它是 item 的基础身份信息。

- [ ] **Step 3: 修改 `makeItems(nodes:)`**

在 `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift` 中，将 `makeItems(nodes:)` 改为：

```swift
private static func makeItems(nodes: [Node]) -> [Address: SpaceDebugNodeItem] {
    Dictionary(
        uniqueKeysWithValues: nodes.enumerated().map { index, node in
            (node.primaryUnicastAddress, SpaceDebugNodeItem(node: node, displayOrder: index))
        }
    )
}
```

Expected:

```text
每个 node 都保存它在 realNodes 中的原始下标。
后续更新 peripheral/RSSI 时，displayOrder 会跟随 item 保留。
```

- [ ] **Step 4: 修改 `sections()` 排序规则**

在 `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift` 中，将 `sections()` 改为：

```swift
func sections() -> [SpaceDebugSection] {
    SpaceDebugDeviceCategory.allCases.map { category in
        let items = itemsByAddress.values
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                lhs.displayOrder < rhs.displayOrder
            }
        return SpaceDebugSection(category: category, items: items)
    }.filter { !$0.items.isEmpty }
}
```

Expected:

```text
分类顺序仍是 SpaceDebugDeviceCategory.allCases。
同一分类内只按 displayOrder 排序。
扫描 found 状态不再影响位置。
设备名称不再影响位置。
```

- [ ] **Step 5: 静态检查排序逻辑**

Run:

```bash
rg -n "isFound !=|displayTitle\\.localizedCaseInsensitiveCompare|displayOrder|SpaceDebugNodeItem\\(node:" SunSmart/Main/Space/Debug/SpaceDebugModels.swift SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
```

Expected:

```text
不应再出现 isFound != rhs.isFound。
不应再出现 displayTitle.localizedCaseInsensitiveCompare。
应出现 displayOrder 字段。
应出现 SpaceDebugNodeItem(node: node, displayOrder: index)。
```

- [ ] **Step 6: 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

说明：

- 当前工程没有 XCTest target，本任务使用静态检查和 iOS Debug 构建验证。
- 构建中的既有 warning 不属于本任务范围；只要没有本次改动导致的 error 即可。

- [ ] **Step 7: 提交代码**

Run:

```bash
git status --short
git add SunSmart/Main/Space/Debug/SpaceDebugModels.swift SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
git commit -m "fix: keep debug device list order stable"
```

Expected:

```text
提交只包含 SpaceDebugModels.swift 和 SpaceDebugViewModel.swift。
```

## Task 2: 最终复核

**Files:**
- Read: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
- Read: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`

- [ ] **Step 1: 查看最终 diff**

Run:

```bash
git show --stat --oneline HEAD
git show -- SunSmart/Main/Space/Debug/SpaceDebugModels.swift SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
```

Expected:

```text
最新提交是 fix: keep debug device list order stable。
diff 只包含 displayOrder 字段、makeItems(nodes:) 和 sections() 排序调整。
没有修改扫描、连接、UART 或其他页面逻辑。
```

- [ ] **Step 2: 确认工作区干净**

Run:

```bash
git status --short
```

Expected:

```text
无输出。
```

- [ ] **Step 3: 给用户回报结果**

回报内容需要包含：

```text
已实现 Debug 设备列表稳定排序。
扫描到设备广播后只更新 RSSI/信号状态，不再把设备移动到前面。
已通过 SunSmart Debug iOS 构建验证。
提交号：使用 git commit 输出中的最新提交哈希。
```
