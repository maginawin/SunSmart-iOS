# Sequence / Trigger Zone 风险 2、3、4、6 修复实施计划

> **执行要求：** 必须使用 `superpowers:executing-plans` 在当前会话 Inline Execution；除非用户明确要求，不使用 subagents。每个任务按复选框逐步执行并设置阶段性检查点。

**目标：** 关闭 Group 保存的云同步中断窗口，显式导出空 Space Trigger Zone 并兼容空数组或字段缺失的导入，保证一次保存只触发一次云同步通知，并永久清理不再符合 Profile 的成员。

**架构：** 在现有 `SpaceData` 云同步扩展中抽取一个只负责持久化待上传状态的写前标记，Group 与 Space Trigger Zone 在保存业务数据前调用。保留现有 NotificationCenter 和 `SyncDevicesViewController` 架构；Space Trigger Zone 使用唯一的 `groupAddress + normalized deviceAddress` 有效集合完成清理和设备邻居编译。

**技术栈：** Swift、UIKit、NordicSigMeshSDK、SQLite 数据模型、NotificationCenter、现有 CloudSynchronizationManager、独立 Swift 源码契约测试、Xcode generic iPhoneOS 构建。

## 全局约束

- 所有回复、文档和计划使用简体中文。
- 当前年份按 2026 年处理。
- 保持改动聚焦，不重构无关模块。
- 不修改 Mesh Opcode、私有协议 Payload、NordicSigMeshSDK 或服务器 API。
- 不新增 Auth、依赖、本地化文案、资源或 target 配置。
- Risk 6 永久清理失效成员，但保留成员清空后的 Zone。
- Risk 3 导出空数组时必须保留 `triggerZones` 键；导入空数组或字段缺失时都归一化为本地空数组。
- 目标邻居为空时继续使用现有 Proximity Lighting Disable，不扩展为空 Neighbor Set 双命令。
- 未获得用户 Git 授权前，不执行 `git add`、`git commit`、merge、push 或 PR 操作。
- iOS 构建必须直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。
- 设计基准：`docs/260729_1457_sequence_trigger_zone_risk_2_3_4_6_design.md`。

---

## 文件结构

### 新增

- `Tests/Group/PathTopologyPersistenceContractTests.swift`
  - 聚焦验证写前标记顺序、空数组导出与兼容导入、通知所有权和成员资格清理契约。
- `scripts/check_path_topology_persistence.sh`
  - 编译并运行上述独立 Swift 契约测试。

### 修改

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - 提供共享写前云脏标记并让现有 commit 方法复用。
- `SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift`
  - 注入 Space，并在 Group 数据保存前写入待上传标记。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 创建 Group Path 页面时传入当前 Space。
- `SunSmart/Common/Data/ExportData.swift`
  - 移除 `triggerZones` 非空门禁，空数组也显式导出。
- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
  - 调整写前标记、通知所有权、永久成员清理和防御性邻居过滤。

### 验证但不修改

- `SunSmart/Common/Data/ImportData.swift`
  - 保留并验证空数组和字段缺失都归一化为空数组的现有逻辑。

---

### Task 1：建立写前云脏标记并接入 Group 保存

**文件：**

- Create: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Create: `scripts/check_path_topology_persistence.sh`
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

**接口：**

- Produces: `SpaceData.markLocalChangePendingCloudSync() -> Void`
- Produces: `GroupPathSequencePageController.init(space: SpaceData, group: Group)`
- Preserves: `SpaceData.commitLocalChangeForCloudSync(site:changeType:)`

- [ ] **Step 1：创建失败的源码契约测试**

新增 `Tests/Group/PathTopologyPersistenceContractTests.swift`：

```swift
import Foundation

@main
struct PathTopologyPersistenceContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let spaceController = try source(
            root,
            "SunSmart/Main/Space/Controller/SpaceViewController.swift"
        )
        let groupPathController = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift"
        )
        let groupController = try source(
            root,
            "SunSmart/Main/Group/Controller/GroupViewController.swift"
        )

        require(
            spaceController.contains("func markLocalChangePendingCloudSync()"),
            "SpaceData must expose a write-ahead cloud dirty marker"
        )

        let cloudCommit = section(
            in: spaceController,
            from: "func commitLocalChangeForCloudSync",
            to: "private func refreshSummaryCountsFromCurrentMesh"
        )
        require(
            cloudCommit.contains("markLocalChangePendingCloudSync()"),
            "The existing cloud commit helper must reuse the write-ahead marker"
        )

        let groupSave = section(
            in: groupPathController,
            from: "@objc private func saveAction()",
            to: "@objc private func addItemAction()"
        )
        require(
            groupPathController.contains("let space: SpaceData"),
            "Group Path page must retain the owning Space"
        )
        require(
            groupPathController.contains("init(space: SpaceData, group: Group)"),
            "Group Path page must receive Space explicitly"
        )
        require(
            groupSave.contains("if edit"),
            "Unchanged Group Path data must not be marked dirty"
        )
        require(
            appearsBefore(
                "space.markLocalChangePendingCloudSync()",
                "group.info.save()",
                in: groupSave
            ),
            "Group Path must persist the cloud dirty marker before GroupInfo"
        )
        require(
            groupController.contains(
                "GroupPathSequencePageController(space: space, group: group)"
            ),
            "GroupViewController must pass the owning Space to Group Path"
        )

        print("PASS: Path topology persistence contracts hold.")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            fatalError("Unable to locate section: \(startMarker) ... \(endMarker)")
        }
        return String(source[start..<end])
    }

    private static func appearsBefore(
        _ first: String,
        _ second: String,
        in source: String
    ) -> Bool {
        guard let firstIndex = source.range(of: first)?.lowerBound,
              let secondIndex = source.range(of: second)?.lowerBound else {
            return false
        }
        return firstIndex < secondIndex
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
```

新增 `scripts/check_path_topology_persistence.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_source="$repo_root/Tests/Group/PathTopologyPersistenceContractTests.swift"
test_binary="${TMPDIR:-/tmp}/PathTopologyPersistenceContractTests"

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" "$repo_root"
```

- [ ] **Step 2：执行测试，确认 RED**

Run:

```bash
chmod +x scripts/check_path_topology_persistence.sh
./scripts/check_path_topology_persistence.sh
```

Expected:

- 测试失败。
- 首个失败应指向缺少 `markLocalChangePendingCloudSync()`、缺少新初始化方法或保存顺序不符合契约。

- [ ] **Step 3：实现最小写前标记**

在 `SpaceViewController.swift` 的 `extension SpaceData` 中增加：

```swift
func markLocalChangePendingCloudSync() {
    refreshSummaryCountsFromCurrentMesh()

    guard permission == .owner || permission == .editor else {
        save()
        return
    }

    markSpaceUploadNeeded()
}
```

将 `commitLocalChangeForCloudSync` 开头调整为：

```swift
func commitLocalChangeForCloudSync(
    site currentSite: SiteData? = nil,
    changeType: SpaceChangeDataType
) {
    markLocalChangePendingCloudSync()

    guard permission == .owner || permission == .editor else {
        return
    }

    guard let site = currentSite ?? SiteData.load(siteId: siteId) else {
        save()
        return
    }

    // 后续现有 Site 恢复、API 分支和入队逻辑保持不变。
}
```

不得复制单调时间逻辑；继续由现有 `markSpaceUploadNeeded()` 唯一负责：

```swift
lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)
```

- [ ] **Step 4：把 Space 注入 Group Path 页面**

将 Group Path 页面依赖调整为：

```swift
let space: SpaceData
let group: Group

init(space: SpaceData, group: Group) {
    self.space = space
    self.group = group
    self.groupPath = group.info.proximityLightingPath ?? .init(paths: [], zones: [])
    super.init(nibName: nil, bundle: nil)
    self.scrollEnable = false
}
```

将 `GroupViewController.setPath()` 创建页面的位置调整为：

```swift
let vc = GroupPathSequencePageController(space: space, group: group)
```

- [ ] **Step 5：调整 Group 保存顺序**

在 `saveAction()` 完成 `edit` 判定后、写入并保存 GroupInfo 前增加：

```swift
if edit {
    space.markLocalChangePendingCloudSync()
}

group.info.proximityLightingPath = groupPath
group.info.save()
group.updateGroupSyncState()
```

保留现有通知分支：

- 无设备任务且 `edit == true`：一次 `.common`。
- 有设备任务：等待通用同步页的一次 `.device`。

- [ ] **Step 6：执行聚焦测试，确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
./scripts/check_space_delete_cloud_restore.sh
```

Expected:

- 两个脚本均输出 `PASS`。
- 现有 Space 删除流程仍通过共享 commit 方法标记并入队。

- [ ] **Step 7：阶段检查**

检查：

```bash
git diff --check
git diff -- \
  SunSmart/Main/Space/Controller/SpaceViewController.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift \
  SunSmart/Main/Group/Controller/GroupViewController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift \
  scripts/check_path_topology_persistence.sh
```

Expected:

- 无空白错误。
- Group 页面只有实际编辑时才写前标记。
- 本阶段不改变设备命令和云同步通知数量。

若用户已明确授权 Git 提交，可执行：

```bash
git add \
  SunSmart/Main/Space/Controller/SpaceViewController.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift \
  SunSmart/Main/Group/Controller/GroupViewController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift \
  scripts/check_path_topology_persistence.sh
git commit -m "fix: mark path topology changes before local save"
```

---

### Task 2：显式导出空 triggerZones 并锁定兼容导入

**文件：**

- Modify: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Modify: `SunSmart/Common/Data/ExportData.swift`
- Verify only: `SunSmart/Common/Data/ImportData.swift`

**接口：**

- Consumes: Task 1 的聚焦契约测试入口。
- Produces: `SpaceData.export()` 在编码成功时始终输出 `triggerZones`。
- Preserves: `SpaceData` 导入空数组或缺少字段时都赋值 `[]`。

- [ ] **Step 1：增加失败的导出契约和导入兼容契约**

在测试中读取：

```swift
let exportData = try source(
    root,
    "SunSmart/Common/Data/ExportData.swift"
)
let importData = try source(
    root,
    "SunSmart/Common/Data/ImportData.swift"
)
let spaceExport = section(
    in: exportData,
    from: "extension SpaceData",
    to: "extension Node"
)
```

增加断言：

```swift
require(
    !spaceExport.contains("if !self.triggerZones.isEmpty"),
    "Empty Space Trigger Zones must not be omitted from export"
)
require(
    spaceExport.contains(
        "spaceJsonData.updateValue(triggerZonesArray, forKey: \"triggerZones\")"
    ),
    "Space export must write the triggerZones key after successful encoding"
)
require(
    importData.contains(
        "if let triggerZonesArray = json[\"triggerZones\"].arrayObject as? [[String: Any]]"
    ),
    "Space import must accept a present triggerZones array, including an empty array"
)
require(
    importData.contains("self.triggerZones = triggerZones"),
    "Space import must retain successfully decoded triggerZones"
)
require(
    importData.contains("self.triggerZones = []"),
    "Space import must normalize a missing or invalid triggerZones field to an empty array"
)
```

- [ ] **Step 2：执行测试，确认 RED**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 失败信息为 `Empty Space Trigger Zones must not be omitted from export`。
- 导入兼容断言应保持通过，证明当前 ImportData 已覆盖空数组和字段缺失。

- [ ] **Step 3：移除导出非空门禁**

将 `SpaceData.export()` 中的导出逻辑改为：

```swift
if let data = try? jsonEncoder.encode(self.triggerZones),
   let triggerZonesArray = try? JSONSerialization.jsonObject(with: data)
       as? [[String: Any]] {
    spaceJsonData.updateValue(triggerZonesArray, forKey: "triggerZones")
}
```

保持编码失败时不写键；不得用空数组伪装编码失败。不得修改 `ImportData.swift` 的现有兼容分支。

- [ ] **Step 4：执行测试，确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 输出 `PASS: Path topology persistence contracts hold.`。
- 导出契约、空数组导入和字段缺失导入契约全部通过。

- [ ] **Step 5：阶段检查**

Run:

```bash
git diff --check
git diff -- \
  SunSmart/Common/Data/ExportData.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
git diff --exit-code -- SunSmart/Common/Data/ImportData.swift
```

确认：

- 非空数组编码保持不变。
- 空数组编码为 `[]` 并写入 `triggerZones`。
- 空数组导入后为 `[]`。
- 缺少 `triggerZones` 属性时进入 `else` 并赋值 `[]`。
- `ImportData.swift` 没有生产改动。

若用户已明确授权 Git 提交，可执行：

```bash
git add \
  SunSmart/Common/Data/ExportData.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
git commit -m "fix: export empty space trigger zones"
```

---

### Task 3：收敛 Space Trigger Zone 云同步通知

**文件：**

- Modify: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Modify: `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`

**接口：**

- Preserves: 无设备任务时页面发送 `.common`。
- Preserves: `SyncDevicesViewController` 结束时发送 `.device`。
- Removes: Space Trigger Zone 成功回调中的 `.common`。

- [ ] **Step 1：增加失败契约**

在测试中读取 Space Trigger Zone 与通用同步页：

```swift
let triggerZoneController = try source(
    root,
    "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift"
)
let syncDevicesController = try source(
    root,
    "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
)
let triggerZoneSave = section(
    in: triggerZoneController,
    from: "@objc private func saveAction()",
    to: "private func zonesEqual"
)
```

增加计数工具：

```swift
private static func occurrenceCount(_ needle: String, in source: String) -> Int {
    return source.components(separatedBy: needle).count - 1
}
```

增加断言：

```swift
let notificationCall =
    "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName)"

require(
    occurrenceCount(notificationCall, in: triggerZoneSave) == 1,
    "Space Trigger Zone save must own only the no-device common notification"
)
require(
    triggerZoneSave.contains("object: SpaceChangeDataType.common"),
    "The no-device branch must retain its common cloud notification"
)
require(
    syncDevicesController.contains(
        "object: SpaceChangeDataType.device"
    ),
    "The shared device sync controller must remain the device notification owner"
)
```

- [ ] **Step 2：执行测试，确认 RED**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 失败原因是 Space Trigger Zone `saveAction()` 内仍有两处通知。

- [ ] **Step 3：移除成功回调中的重复通知**

将成功回调收敛为：

```swift
vc.syncSuccessCallback = { [weak self] _ in
    XWHUDManager.showSuccessTipHUD("done!".localizedString)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        self?.navigationController?.popViewController(animated: true)
    }
}
```

不得移除无设备任务分支的 `.common`，也不得修改 `SyncDevicesViewController` 的通用 `.device`。

- [ ] **Step 4：执行测试，确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 聚焦契约通过。
- `saveAction()` 中只剩无设备任务分支的一处 `.common`。

- [ ] **Step 5：阶段检查**

Run:

```bash
git diff --check
git diff -- \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
```

确认：

- 无设备任务：一次 `.common`。
- 有设备任务成功：通用同步页一次 `.device`。
- 有设备任务失败：通用同步页一次 `.device`。
- 成功 HUD 和返回行为不变。

若用户已明确授权 Git 提交，可执行：

```bash
git add \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
git commit -m "fix: avoid duplicate trigger zone cloud notifications"
```

---

### Task 4：永久清理失效成员并统一设备邻居过滤

**文件：**

- Modify: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Modify: `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`

**接口：**

- Produces: 私有 `SpaceTriggerZoneMemberKey: Hashable`
- Produces: 私有 `eligibleZoneMemberKeys() -> Set<SpaceTriggerZoneMemberKey>`
- Produces: 私有 `sanitizeSetZones() -> Void`
- Preserves: Zone 数量和顺序。
- Preserves: 目标邻居为空时 `.proximityLightingEnabled(false)`。

- [ ] **Step 1：增加失败契约**

对 `triggerZoneController` 增加：

```swift
require(
    triggerZoneController.contains(
        "private struct SpaceTriggerZoneMemberKey: Hashable"
    ),
    "Trigger Zone eligibility must use a group and device address key"
)
require(
    triggerZoneController.contains(
        "private func eligibleZoneMemberKeys() -> Set<SpaceTriggerZoneMemberKey>"
    ),
    "Trigger Zone must build one current eligibility set"
)
require(
    triggerZoneController.contains("private func sanitizeSetZones()"),
    "Trigger Zone must expose one sanitizer for its working copy"
)

let initializer = section(
    in: triggerZoneController,
    from: "init(site: SiteData, space: SpaceData)",
    to: "required init?(coder:"
)
require(
    initializer.contains("sanitizeSetZones()"),
    "Trigger Zone must sanitize the working copy during initialization"
)

let triggerZoneSave = section(
    in: triggerZoneController,
    from: "@objc private func saveAction()",
    to: "private func zonesEqual"
)
require(
    appearsBefore("sanitizeSetZones()", "let oldZones", in: triggerZoneSave),
    "Trigger Zone must sanitize again before save comparison"
)
require(
    appearsBefore(
        "space.markLocalChangePendingCloudSync()",
        "space.triggerZones = newZones",
        in: triggerZoneSave
    ),
    "Space Trigger Zone must write the cloud marker before logical persistence"
)

let desiredNeighbors = section(
    in: triggerZoneController,
    from: "private func desiredNeighborAddresses",
    to: "private func appendNode"
)
require(
    desiredNeighbors.contains("eligibleZoneMemberKeys()"),
    "Desired neighbors must defensively reuse current eligibility"
)

let sanitizer = section(
    in: triggerZoneController,
    from: "private func sanitizeSetZones()",
    to: "private var quickAddGroupFilterOptions"
)
require(
    sanitizer.contains("zone.items.removeAll"),
    "Sanitizer must remove invalid members"
)
require(
    !sanitizer.contains("setZones.removeAll"),
    "Sanitizer must retain empty zones"
)

let syncBuilder = section(
    in: triggerZoneController,
    from: "private func buildSyncDatas()",
    to: "private func desiredNeighborAddresses"
)
require(
    syncBuilder.contains(".proximityLightingEnabled(false)"),
    "An eligible node with no desired neighbors must retain disable behavior"
)
```

- [ ] **Step 2：执行测试，确认 RED**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 首个失败应指向缺少成员键、资格集合或 sanitizer。

- [ ] **Step 3：增加唯一成员资格集合**

在 `SpacePathTriggerZoneController` 内增加：

```swift
private struct SpaceTriggerZoneMemberKey: Hashable {
    let groupAddress: Address
    let deviceAddress: Address
}
```

在 `eligibleNodes` 附近增加：

```swift
private func eligibleZoneMemberKeys() -> Set<SpaceTriggerZoneMemberKey> {
    var keys = Set<SpaceTriggerZoneMemberKey>()
    eligibleGroups.forEach { group in
        group.nodes.forEach { node in
            keys.insert(
                .init(
                    groupAddress: group.address.address,
                    deviceAddress: normalizedAddress(for: node)
                )
            )
        }
    }
    return keys
}

private func sanitizeSetZones() {
    let eligibleKeys = eligibleZoneMemberKeys()
    setZones.forEach { zone in
        zone.items.removeAll { item in
            !eligibleKeys.contains(
                .init(
                    groupAddress: item.groupAddress,
                    deviceAddress: item.deviceAddress
                )
            )
        }
    }
}
```

该集合同时证明：

- Group 存在。
- Group 属于当前 `space.meshNetworkId`，因为来源是 `eligibleGroups`。
- Profile 当前符合要求。
- Node 当前仍属于该 Group。
- Item 的 Group/Node 地址组合仍精确匹配。

- [ ] **Step 4：在初始化和保存前执行永久清理**

初始化中删除原有只检查 `item.node == nil || item.group == nil` 的局部清理，改为：

```swift
self.setZones = space.triggerZones.map { $0.copy() }
self.sanitizeSetZones()
```

`saveAction()` 开头调整为：

```swift
stopSetZone()
sanitizeSetZones()

let oldZones = space.triggerZones.map { $0.copy() }
let newZones = setZones.map { $0.copy() }
let didEdit = !zonesEqual(oldZones, newZones)

if didEdit {
    space.markLocalChangePendingCloudSync()
    space.triggerZones = newZones
    space.save()
}
```

不得删除空 Zone；`setZones` 的数组数量和顺序保持不变。

- [ ] **Step 5：防御性过滤 desired neighbors**

将 `desiredNeighborAddresses(for:)` 调整为：

```swift
private func desiredNeighborAddresses(for node: Node) -> [Address] {
    let currentAddress = normalizedAddress(for: node)
    let eligibleKeys = eligibleZoneMemberKeys()
    var neighbors: [Address] = []

    setZones.forEach { zone in
        guard zone.items.contains(where: { item in
            item.deviceAddress == currentAddress &&
            eligibleKeys.contains(
                .init(
                    groupAddress: item.groupAddress,
                    deviceAddress: item.deviceAddress
                )
            )
        }) else {
            return
        }

        zone.items.forEach { item in
            let key = SpaceTriggerZoneMemberKey(
                groupAddress: item.groupAddress,
                deviceAddress: item.deviceAddress
            )
            guard eligibleKeys.contains(key),
                  item.deviceAddress != currentAddress,
                  !neighbors.contains(item.deviceAddress) else {
                return
            }
            neighbors.append(item.deviceAddress)
        }
    }
    return neighbors
}
```

保留现有 `buildSyncDatas()` 分支：

```swift
if desiredNeighbors.isEmpty {
    return node.proximityLightingEnabled
        ? (node, .proximityLightingEnabled(false))
        : nil
}
```

不得在本任务中增加空 Neighbor Set、协议新命令或 SDK 修改。

- [ ] **Step 6：执行测试，确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- 聚焦契约通过。
- 清理方法只删除 Zone Item，不删除 Zone。
- 初始化、保存前比较和设备目标编译使用同一资格规则。

- [ ] **Step 7：阶段检查**

Run:

```bash
git diff --check
git diff -- \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
```

人工核对以下数据场景：

| 场景 | 预期 |
| --- | --- |
| Group 已删除 | Item 删除 |
| Node 已删除 | Item 删除 |
| Group 移出当前 Mesh Network | Item 删除 |
| Profile 改为非 Proximity Lighting | Item 删除 |
| Node 从原 Group 移到另一 Group | 旧地址组合删除 |
| Zone 所有 Item 失效 | Zone 保留，items 为空 |
| 有效 Item | 地址与顺序不变 |

若用户已明确授权 Git 提交，可执行：

```bash
git add \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift
git commit -m "fix: prune ineligible space trigger zone members"
```

---

### Task 5：完整回归、共享 target 构建与交付检查

**文件：**

- Verify: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Verify: `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`
- Verify: `scripts/check_path_topology_persistence.sh`
- Verify: `scripts/check_space_delete_cloud_restore.sh`
- Verify: 本计划列出的全部生产文件。

**接口：**

- Consumes: Tasks 1–4 的全部行为。
- Produces: 自动化与编译证据；不替代真机 Mesh 和真实服务器验收。

- [ ] **Step 1：运行新增聚焦契约**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

```text
PASS: Path topology persistence contracts hold.
```

- [ ] **Step 2：运行现有相关契约**

Run:

```bash
swiftc -parse-as-library \
  Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift \
  -o /tmp/GroupPathSequenceDeviceAddViewContractTests
/tmp/GroupPathSequenceDeviceAddViewContractTests "$PWD"
./scripts/check_space_delete_cloud_restore.sh
```

Expected:

- Group Path Sequence UI/调用方契约通过。
- Space 删除云同步恢复契约输出 `PASS`。

- [ ] **Step 3：执行静态检查**

Run:

```bash
git diff --check
git status --short
git diff --stat
git diff -- \
  SunSmart/Main/Space/Controller/SpaceViewController.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift \
  SunSmart/Main/Group/Controller/GroupViewController.swift \
  SunSmart/Common/Data/ExportData.swift \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift \
  scripts/check_path_topology_persistence.sh
```

Expected:

- 无空白错误。
- 不覆盖已有的未跟踪分析文档。
- 无协议、SDK、本地化、资源、依赖或无关文件变化。

- [ ] **Step 4：构建主 target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- `** BUILD SUCCEEDED **`。
- 若失败，记录首个 Swift 编译错误，不把依赖恢复日志当作业务代码错误。

- [ ] **Step 5：构建共享品牌 target**

本次修改包含 Common 数据导出和共享 Space/Group 页面。依次运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 两个共享 scheme 均 `** BUILD SUCCEEDED **`。
- `SLG Sync Plus` 当前没有共享 workspace scheme；记录为未执行，而不是误报构建通过。

- [ ] **Step 6：最终源码审计**

逐项确认：

1. Risk 2：Group 写前标记在 GroupInfo 保存之前。
2. Risk 3：导出不再使用非空门禁；空数组写入 `triggerZones`，导入空数组或字段缺失都得到 `[]`。
3. Risk 4：Space Trigger Zone `saveAction()` 只有一处业务通知。
4. Risk 6：资格集合来自当前 Space 的 eligible Groups 和其当前 Nodes。
5. 空 Zone 被保留。
6. 目标邻居为空时仍为 Disable，没有新增私有协议命令。
7. `SyncDevicesViewController` 的通用 `.device` 行为未被修改。

- [ ] **Step 7：列出真机与服务器验收项**

交付报告必须将以下项目标为“待真机/真实服务器验证”，除非本次确实完成：

- Group 保存后立即杀 App，重新打开仍能恢复云同步。
- 删除全部 Space Trigger Zones，服务器请求包含 `"triggerZones": []`。
- 分别导入空数组和缺少 `triggerZones` 属性的数据，本地都得到空数组。
- 有设备任务的 Space Trigger Zone 保存只产生一次云同步入队。
- Profile 失效成员从 UI、本地和服务器消失。
- 其他有效节点收到的 `0xF0780A / 0x41 / 0x02` Payload 不包含失效地址。
- 清理最后一个邻居时，节点收到既有 `0x41 / 0x01` Disable。

- [ ] **Step 8：可选最终提交**

只有用户明确授权 Git 提交时才运行：

```bash
git add \
  SunSmart/Main/Space/Controller/SpaceViewController.swift \
  SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift \
  SunSmart/Main/Group/Controller/GroupViewController.swift \
  SunSmart/Common/Data/ExportData.swift \
  SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift \
  Tests/Group/PathTopologyPersistenceContractTests.swift \
  scripts/check_path_topology_persistence.sh \
  docs/260729_1457_sequence_trigger_zone_risk_2_3_4_6_design.md \
  docs/260729_1457_sequence_trigger_zone_risk_2_3_4_6_implementation_plan.md
git commit -m "fix: harden path topology persistence and cleanup"
```

提交前再次确认未暂存用户已有的：

```text
docs/260728_2000_path_sequence_and_trigger_zone_protocol_analysis.md
```

除非用户明确要求把该分析文档一并提交。
