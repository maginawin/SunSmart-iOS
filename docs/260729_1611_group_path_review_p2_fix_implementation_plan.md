# Group Path Review P2 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Do not use subagents unless the user explicitly requests them.

**Goal:** 修复新增空 Sequence 未标记云同步的问题，并消除 Space Trigger Zone 构建设备任务时对成员资格集合的逐节点重复扫描。

**Architecture:** Group Path 编辑期间只维护子页面工作副本，父页面在保存时统一合并，从而让保存前快照可靠识别新增空 Sequence。Space Trigger Zone 在一次设备任务构建开始时生成操作级资格集合，并向每个节点的邻居计算函数显式传递；不增加长期缓存，避免 Profile 或成员关系变化后使用过期结果。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Swift 可执行契约测试、Xcode generic iPhoneOS build。

## Global Constraints

- 所有改动保持在当前 linked worktree。
- 不修改 Mesh Opcode、Access Payload、设备命令或服务器 API。
- 不改变 Group Path 写前云脏标记、通知所有权和设备同步分支。
- 不改变 Space Trigger Zone 的永久清理、空 Zone 保留和目标邻居为空时禁用 Proximity Lighting 的语义。
- 不新增长期资格缓存，不新增 Auth、本地化、资源、依赖或 target 配置。
- 不格式化或重构无关代码。
- 不执行 Git commit、push、merge 或其他未经授权的 Git 写操作。
- 验证使用 generic iPhoneOS，不使用 Simulator。

---

## 文件范围

- Modify: `Tests/Group/PathTopologyPersistenceContractTests.swift`
  - 增加空 Sequence 工作副本契约。
  - 增加一次设备任务构建只计算一次资格集合的契约。
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
  - 移除新增 Sequence 时对父级 `groupPath.paths` 的提前写入。
- Modify: `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
  - 在 `buildSyncDatas()` 中生成一次资格集合并传给每个节点复用。

不修改：

- `GroupPathSequencePageController.saveAction()` 的写前云脏标记顺序。
- `SpaceData.markLocalChangePendingCloudSync()`。
- `SyncDevicesViewController` 的通知行为。
- SDK 与协议实现。

---

### Task 1：修复新增空 Sequence 的变更漏判

**Files:**

- Test: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Modify: `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`

**Interfaces:**

- Consumes: `GroupPathSequenceViewController.setPaths`
- Consumes: `GroupPathSequencePageController.saveAction()`
- Preserves: 保存时由 `groupPath.paths = vc.setPaths` 合并工作副本
- Produces: 新增 Sequence 在保存前不会修改父级 `groupPath`

- [ ] **Step 1：增加失败契约**

在测试中读取 `GroupPathSequenceViewController.swift`：

```swift
let groupPathSequenceController = try source(
    root,
    "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift"
)
```

提取 `addPath()`：

```swift
let addPath = section(
    in: groupPathSequenceController,
    from: "func addPath()",
    to: "/// 停止设置路径"
)
```

增加契约：

```swift
require(
    !addPath.contains("groupPath.paths.append"),
    "Adding a Sequence must not mutate the parent Group Path before save"
)
require(
    addPath.contains("setPaths.append"),
    "Adding a Sequence must update the editable path copy"
)
require(
    appearsBefore(
        "let equalPath = groupPath.copy()",
        "groupPath.paths = vc.setPaths",
        in: groupSave
    ),
    "Group Path must snapshot persisted data before merging child edits"
)
```

该契约捕获的具体回归是：重新引入对父级 `groupPath.paths` 的提前追加，导致保存时快照已经包含新增空 Sequence。

- [ ] **Step 2：执行测试并确认 RED**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- Exit code 非 0。
- 首个新增失败信息为：
  `Adding a Sequence must not mutate the parent Group Path before save`

- [ ] **Step 3：实施最小修复**

在 `GroupPathSequenceViewController.addPath()` 的确认回调中删除：

```swift
self.groupPath.paths.append(contentsOf: list)
```

保留：

```swift
self.setPaths.append(contentsOf: list.map({ $0.copy() }))
```

不得调整删除、重置、设备添加或页面切换逻辑。

- [ ] **Step 4：执行测试并确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- Exit code 0。
- 输出：
  `PASS: Path topology persistence contracts hold.`

---

### Task 2：复用一次设备任务构建的 Trigger Zone 资格集合

**Files:**

- Test: `Tests/Group/PathTopologyPersistenceContractTests.swift`
- Modify: `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`

**Interfaces:**

- Consumes: `eligibleZoneMemberKeys() -> Set<SpaceTriggerZoneMemberKey>`
- Changes: `desiredNeighborAddresses(for:)`
- Produces: `desiredNeighborAddresses(for:eligibleKeys:)`
- Preserves: `buildSyncDatas() -> [(node: Node, syncData: NodeSyncData)]`

- [ ] **Step 1：替换旧契约并增加失败契约**

删除“`desiredNeighborAddresses` 自行调用 `eligibleZoneMemberKeys()`”的旧断言，改为：

```swift
require(
    occurrenceCount("eligibleZoneMemberKeys()", in: syncBuilder) == 1,
    "One device-task build must calculate eligibility exactly once"
)
require(
    syncBuilder.contains(
        "desiredNeighborAddresses(for: node, eligibleKeys: eligibleKeys)"
    ),
    "Device-task construction must reuse the operation eligibility set"
)
require(
    !desiredNeighbors.contains("eligibleZoneMemberKeys()"),
    "Per-node neighbor calculation must not rebuild global eligibility"
)
require(
    desiredNeighbors.contains(
        "eligibleKeys: Set<SpaceTriggerZoneMemberKey>"
    ),
    "Per-node neighbor calculation must receive the operation eligibility set"
)
```

该契约捕获的具体回归是：将 `eligibleZoneMemberKeys()` 放回逐节点邻居计算，恢复对全部 Group 和 `realNodes` 的重复扫描。

- [ ] **Step 2：执行测试并确认 RED**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- Exit code 非 0。
- 首个新增失败信息为：
  `One device-task build must calculate eligibility exactly once`
  或后续资格复用断言。

- [ ] **Step 3：实施最小修复**

将 `buildSyncDatas()` 调整为在遍历节点前生成一次集合：

```swift
private func buildSyncDatas() -> [(node: Node, syncData: NodeSyncData)] {
    let eligibleKeys = eligibleZoneMemberKeys()
    return eligibleNodes.compactMap { node in
        let desiredNeighbors = desiredNeighborAddresses(
            for: node,
            eligibleKeys: eligibleKeys
        )
        // 保留其余既有同步分支
    }
}
```

调整邻居计算签名并删除函数内部的资格重算：

```swift
private func desiredNeighborAddresses(
    for node: Node,
    eligibleKeys: Set<SpaceTriggerZoneMemberKey>
) -> [Address] {
    let currentAddress = normalizedAddress(for: node)
    var neighbors: [Address] = []
    // 保留既有成员过滤和去重逻辑
}
```

不把资格集合保存为控制器属性；初始化和保存清理继续按调用时状态计算。

- [ ] **Step 4：执行测试并确认 GREEN**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- Exit code 0。
- 输出：
  `PASS: Path topology persistence contracts hold.`

---

### Task 3：静态检查与 iPhoneOS 构建

**Files:**

- Verify only: 本计划涉及的所有修改文件。

**Interfaces:**

- Preserves: SunSmart target 的现有编译接口。

- [ ] **Step 1：执行完整聚焦契约**

Run:

```bash
./scripts/check_path_topology_persistence.sh
```

Expected:

- Exit code 0。
- 无失败契约。

- [ ] **Step 2：执行 diff whitespace 检查**

Run:

```bash
git diff --check
```

Expected:

- Exit code 0。
- 无输出。

- [ ] **Step 3：执行 generic iPhoneOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Exit code 0。
- 输出包含 `BUILD SUCCEEDED`。

- [ ] **Step 4：审查最终 diff**

Run:

```bash
git diff -- Tests/Group/PathTopologyPersistenceContractTests.swift SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift
```

Expected:

- Sequence 改动只移除父级提前写入。
- Trigger Zone 改动只把操作级资格集合传给逐节点邻居计算。
- 测试覆盖两个回归。
- 不包含协议、服务器、通知、本地化、资源或 target 修改。

---

## 自审结果

- Spec coverage：两个评审意见均有独立 RED、最小 GREEN 和最终构建验证。
- Scope：没有 SDK、协议、服务器或通知行为变化。
- Type consistency：资格集合类型始终为 `Set<SpaceTriggerZoneMemberKey>`。
- Cache correctness：集合仅在一次同步任务构建中复用，不跨操作缓存。
- Placeholder scan：没有 TBD、TODO 或未定义步骤。
- Execution mode：按项目约定使用 Inline Execution，不使用 subagents。
