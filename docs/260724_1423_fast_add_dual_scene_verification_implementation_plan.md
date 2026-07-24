# Fast Add 双场景同步结果校验修复实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话逐任务执行；不使用 subagents。每个步骤使用复选框跟踪。

**目标：** 修复 Photocell 组内 Fast Add 在 Night、Day 均成功后仍显示 `sync_failed` 的误判，同时保留真实消息失败、任务未收敛和严格传感器发布重传校验。

**架构：** 新增一个不依赖 UIKit 或 NordicSigMeshSDK 的通用检查点追踪器，以消息句柄对象身份识别 deferred task 的完成边界，并在该边界立即固化校验结果。Light Fast Add 的 deferred operations 改用检查点结果，immediate operations、Sensor Fast Add 和 EFC 继续沿用原有最终校验路径；Classic 与 Professional 只负责在同步更新 Node 后转发成功回调。

**技术栈：** Swift、NordicSigMeshSDK、Xcode project、standalone `swiftc` contract tests、Shell source contracts、`xcodebuild` generic iPhoneOS。

## 全局约束

- 只修复 Add Device 双场景批处理的最终校验误判。
- 同时覆盖 Classic 与 Professional Add Device。
- 空 Path 仍下发空邻居列表，Group 页面仍显示独立的 `SET Path` 提示。
- 不修改 Proximity/Predictive Lighting 协议、Path 产品语义或 NordicSigMeshSDK。
- Fast Add 继续按加入后的 `effectiveMemberCount` 使用严格传感器发布重传目标。
- 不把 Fast Add 最终校验替换为 `getNeedSyncGroup` 或 `legacyCompatible`。
- 不改变追加消息顺序、SDK 失败后继续策略或 EFC 独立结果处理。
- 新文件必须同时加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不新增用户可见文案，不修改本地化资源。
- 保留现有未跟踪文件 `docs/260724_1225_proximity_photocell_fast_add_sync_icon_analysis.md`，不得放入实现提交。
- iOS 构建只使用 generic iPhoneOS，不使用 Simulator，不使用 shell 包装或日志重定向。

---

## 文件结构

### 新增

- `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
  - 只负责检查点状态机和对象身份匹配；
  - 不导入 UIKit、NordicSigMeshSDK，不认识 Node、Group 或 Mesh 协议。
- `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
  - 纯 Swift 行为测试；
  - 覆盖 Night/Day 状态覆盖、失败固化、重复回调、未知句柄和等待状态。
- `scripts/check_fast_add_task_checkpoint_tracker.sh`
  - 编译并运行纯 Swift 测试；
  - 检查新文件是否进入四个 target。
- `scripts/check_fast_add_dual_scene_verification.sh`
  - 检查 Planner、两个 Add Device 入口、严格重传和空 Path 边界。

### 修改

- `SunSmart.xcodeproj/project.pbxproj`
  - 将检查点追踪器加入 Model group 和四个 app target 的 Sources。
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 从既有 `deferredTasks` 生成检查点；
  - Light 的批次末校验只保留 immediate operations；
  - Sensor Fast Add 保持原有批次末校验。
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 在同步 `node.updateData` 后通知计划完成检查点。
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 与 Classic 使用完全相同的成功回调顺序。

---

### Task 1：建立可独立测试的检查点追踪器

**文件：**

- Create: `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- Create: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Create: `scripts/check_fast_add_task_checkpoint_tracker.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**接口：**

- Produces: `FastAddTaskCheckpoint<MessageHandle>`
- Produces: `FastAddTaskCheckpointTracker<MessageHandle>`
- Produces: `recordSuccess(for:)`
- Produces: `hasFailure`
- Consumes: 仅要求 `MessageHandle: AnyObject`

- [ ] **Step 1：先写失败的纯 Swift 行为测试**

创建 `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`：

```swift
final class TestMessageHandle {}

@main
struct FastAddTaskCheckpointTrackerTests {
    static func main() {
        testNightResultSurvivesDayOverwrite()
        testFailedCheckpointCannotBecomeSuccessfulLater()
        testDuplicateSuccessDoesNotReevaluateCheckpoint()
        testUnknownHandleDoesNotAffectCompletedCheckpoint()
        testPendingCheckpointIsFailure()
        testEmptyTrackerSucceeds()
        print("FastAddTaskCheckpointTrackerTests passed")
    }

    private static func testNightResultSurvivesDayOverwrite() {
        let nightHandle = TestMessageHandle()
        let dayHandle = TestMessageHandle()
        var currentLevel = 100
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: nightHandle) {
                    currentLevel == 100
                },
                FastAddTaskCheckpoint(lastMessageHandle: dayHandle) {
                    currentLevel == 0
                }
            ]
        )

        tracker.recordSuccess(for: nightHandle)
        currentLevel = 0
        tracker.recordSuccess(for: dayHandle)

        precondition(!tracker.hasFailure)
    }

    private static func testFailedCheckpointCannotBecomeSuccessfulLater() {
        let handle = TestMessageHandle()
        var currentLevel = 0
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: handle) {
                    currentLevel == 100
                }
            ]
        )

        tracker.recordSuccess(for: handle)
        currentLevel = 100
        tracker.recordSuccess(for: handle)

        precondition(tracker.hasFailure)
    }

    private static func testDuplicateSuccessDoesNotReevaluateCheckpoint() {
        let handle = TestMessageHandle()
        var currentLevel = 100
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: handle) {
                    currentLevel == 100
                }
            ]
        )

        tracker.recordSuccess(for: handle)
        currentLevel = 0
        tracker.recordSuccess(for: handle)

        precondition(!tracker.hasFailure)
    }

    private static func testUnknownHandleDoesNotAffectCompletedCheckpoint() {
        let expectedHandle = TestMessageHandle()
        let unknownHandle = TestMessageHandle()
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: expectedHandle) {
                    true
                }
            ]
        )

        tracker.recordSuccess(for: expectedHandle)
        tracker.recordSuccess(for: unknownHandle)

        precondition(!tracker.hasFailure)
    }

    private static func testPendingCheckpointIsFailure() {
        let tracker = FastAddTaskCheckpointTracker(
            checkpoints: [
                FastAddTaskCheckpoint(lastMessageHandle: TestMessageHandle()) {
                    true
                }
            ]
        )

        precondition(tracker.hasFailure)
    }

    private static func testEmptyTrackerSucceeds() {
        let tracker = FastAddTaskCheckpointTracker<TestMessageHandle>(checkpoints: [])

        precondition(!tracker.hasFailure)
    }
}
```

- [ ] **Step 2：创建检查脚本并确认测试先失败**

创建 `scripts/check_fast_add_task_checkpoint_tracker.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tracker="SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift"
test_file="Tests/Device/FastAddTaskCheckpointTrackerTests.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
binary="/tmp/FastAddTaskCheckpointTrackerTests"

[ -f "$tracker" ] || fail "missing FastAddTaskCheckpointTracker source"
[ -f "$test_file" ] || fail "missing FastAddTaskCheckpointTracker tests"

swiftc -parse-as-library "$tracker" "$test_file" -o "$binary"
"$binary"

source_count="$(rg -c 'C8FA20[1-4]12F12000100000001 /\* FastAddTaskCheckpointTracker.swift in Sources \*/,' "$project_file")"
[ "$source_count" -eq 4 ] || fail "tracker must belong to all four app target source phases"

rg -n 'FastAddTaskCheckpointTracker.swift' "$project_file" >/dev/null \
  || fail "tracker file reference missing from project"

echo "PASS: Fast Add task checkpoint tracker"
```

运行：

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
```

预期：FAIL，输出 `missing FastAddTaskCheckpointTracker source`。

- [ ] **Step 3：实现最小检查点状态机**

创建 `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`：

```swift
struct FastAddTaskCheckpoint<MessageHandle: AnyObject> {
    let lastMessageHandle: MessageHandle
    let verify: () -> Bool
}

final class FastAddTaskCheckpointTracker<MessageHandle: AnyObject> {
    private enum State {
        case pending
        case succeeded
        case failed
    }

    private struct Entry {
        let checkpoint: FastAddTaskCheckpoint<MessageHandle>
        var state: State
    }

    private var entries: [Entry]

    init(checkpoints: [FastAddTaskCheckpoint<MessageHandle>]) {
        entries = checkpoints.map {
            Entry(checkpoint: $0, state: .pending)
        }
    }

    func recordSuccess(for messageHandle: MessageHandle) {
        guard let index = entries.firstIndex(where: {
            $0.checkpoint.lastMessageHandle === messageHandle
        }) else {
            return
        }
        guard case .pending = entries[index].state else {
            return
        }

        let succeeded = entries[index].checkpoint.verify()
        entries[index].state = succeeded ? .succeeded : .failed
    }

    var hasFailure: Bool {
        entries.contains {
            switch $0.state {
            case .pending, .failed:
                return true
            case .succeeded:
                return false
            }
        }
    }
}
```

- [ ] **Step 4：把新文件加入四个 app target**

在 `SunSmart.xcodeproj/project.pbxproj` 中使用以下未占用 ID：

```text
C8FA20012F12000100000001  FileReference
C8FA20112F12000100000001  Archipelago BuildFile
C8FA20212F12000100000001  SylSmart BuildFile
C8FA20312F12000100000001  SunSmart BuildFile
C8FA20412F12000100000001  SLG Sync Plus BuildFile
```

在 `PBXBuildFile` section 添加：

```text
C8FA20112F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */; };
C8FA20212F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */; };
C8FA20312F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */; };
C8FA20412F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */; };
```

在 `PBXFileReference` section 添加：

```text
C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FastAddTaskCheckpointTracker.swift; sourceTree = "<group>"; };
```

在 `C89941962AD4FB05008DCD76 /* Model */` group 的 `children` 中，紧邻 `DeviceGroupDeferredSyncPlanner.swift` 添加：

```text
C8FA20012F12000100000001 /* FastAddTaskCheckpointTracker.swift */,
```

分别加入四个 Sources phase：

```text
C88553B12DE6B44C00C8B688 /* Archipelago Sources */
  C8FA20112F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */,

C886E0012E30DE4900D0C3A6 /* SylSmart Sources */
  C8FA20212F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */,

C896B9A02A930BA800217512 /* SunSmart Sources */
  C8FA20312F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */,

C8BB65AF2ED3F056000C63EE /* SLG Sync Plus Sources */
  C8FA20412F12000100000001 /* FastAddTaskCheckpointTracker.swift in Sources */,
```

- [ ] **Step 5：运行测试并确认通过**

运行：

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
```

预期：

```text
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
```

再运行：

```bash
git diff --check
```

预期：无输出，退出码为 0。

- [ ] **Step 6：提交检查点追踪器**

```bash
git add \
  SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift \
  Tests/Device/FastAddTaskCheckpointTrackerTests.swift \
  scripts/check_fast_add_task_checkpoint_tracker.sh \
  SunSmart.xcodeproj/project.pbxproj
git commit -m "test: add fast add task checkpoint tracker"
```

---

### Task 2：让 Light Fast Add 在 deferred task 边界固化校验结果

**文件：**

- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Create: `scripts/check_fast_add_dual_scene_verification.sh`

**接口：**

- Consumes: `FastAddTaskCheckpoint<MeshMessageHandle>`
- Consumes: `FastAddTaskCheckpointTracker<MeshMessageHandle>`
- Produces: `DeviceGroupFastAddSyncPlan.recordSuccessfulMessageHandle(_:)`
- Produces: `DeviceGroupFastAddSyncPlan.hasVerificationFailure`
- 保留: `DeviceGroupFastAddSyncPlan.contains(_:)`

- [ ] **Step 1：先写 Planner 集成契约**

创建 `scripts/check_fast_add_dual_scene_verification.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

planner="SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift"
node_sync="SunSmart/Common/Data/Node+SyncData.swift"
operation_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"

bash scripts/check_fast_add_task_checkpoint_tracker.sh

rg -n -F 'FastAddTaskCheckpointTracker<MeshMessageHandle>' "$planner" >/dev/null \
  || fail "Fast Add plan must own a task checkpoint tracker"
rg -n -F 'func recordSuccessfulMessageHandle(_ messageHandle: MeshMessageHandle)' "$planner" >/dev/null \
  || fail "Fast Add plan must expose task checkpoint recording"
rg -n -F 'taskCheckpointTracker.recordSuccess(for: messageHandle)' "$planner" >/dev/null \
  || fail "Fast Add plan must forward successful handles to the tracker"
rg -n -F 'makeTaskCheckpoints(tasks: plan.deferredTasks)' "$planner" >/dev/null \
  || fail "Light Fast Add must reuse existing deferred task boundaries"
rg -n -F 'task.operationType.isSuccessful' "$planner" >/dev/null \
  || fail "Task checkpoint must use the existing strict operation success predicate"
rg -n -F 'syncDatas.filter { !usesTaskScopedVerification($0) }' "$planner" >/dev/null \
  || fail "Light batch verification must exclude task-scoped operations"
rg -n -F 'taskCheckpointTracker.hasFailure' "$planner" >/dev/null \
  || fail "Final Fast Add result must include pending or failed checkpoints"

rg -n -F 'effectiveMemberCount: effectiveMemberCount' "$planner" >/dev/null \
  || fail "Fast Add must preserve effective member count"
rg -n -F 'sensorPublicationSyncMode: SensorPublicationSyncMode = .strictTarget' "$node_sync" >/dev/null \
  || fail "Profile generation must remain strict by default"
rg -n -F 'return publication.retransmit == retransmit' "$node_sync" >/dev/null \
  || fail "Strict sensor publication comparison missing"
rg -n -F '!$0.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: retransmit)' "$operation_model" >/dev/null \
  || fail "sensorEnabled verification must compare the exact retransmit target"

if rg -n 'getNeedSyncGroup|legacyCompatible' "$planner" >/dev/null; then
  fail "Fast Add planner must not use the Group page compatibility result"
fi

rg -n -F 'for path in proximityLightingPath?.paths ?? []' "$node_sync" >/dev/null \
  || fail "empty Path must continue to produce an empty path iteration"
rg -n -F 'for zone in proximityLightingPath?.zones ?? []' "$node_sync" >/dev/null \
  || fail "empty Path must continue to produce an empty zone iteration"

echo "PASS: Fast Add dual-scene task-scoped verification"
```

- [ ] **Step 2：运行契约并确认先失败**

运行：

```bash
bash scripts/check_fast_add_dual_scene_verification.sh
```

预期：Tracker 单元测试通过，随后 FAIL，输出 `Fast Add plan must own a task checkpoint tracker`。

- [ ] **Step 3：扩展 Fast Add 计划结果**

在 `DeviceGroupFastAddSyncPlan` 中加入检查点追踪器：

```swift
struct DeviceGroupFastAddSyncPlan {
    let nodeAddress: Address
    let group: Group
    let appendMessageHandles: [MeshMessageHandle]
    let verificationOperations: [DeviceOperationType]
    let taskCheckpointTracker: FastAddTaskCheckpointTracker<MeshMessageHandle>

    func contains(_ messageHandle: MeshMessageHandle) -> Bool {
        appendMessageHandles.contains { $0 === messageHandle }
    }

    func recordSuccessfulMessageHandle(_ messageHandle: MeshMessageHandle) {
        taskCheckpointTracker.recordSuccess(for: messageHandle)
    }

    var hasVerificationFailure: Bool {
        taskCheckpointTracker.hasFailure
            || verificationOperations.contains { !$0.isSuccessful }
    }
}
```

这里保留 `verificationOperations`，但 Light 分支只向其中放入 immediate operations；Sensor 分支仍放入全部 operations。

- [ ] **Step 4：从既有 deferred tasks 生成检查点**

在 `private extension DeviceGroupFastAddSyncPlanner` 中新增：

```swift
static func makeTaskCheckpoints(
    tasks: [DeviceGroupDeferredSyncTask]
) -> [FastAddTaskCheckpoint<MeshMessageHandle>] {
    tasks.compactMap { task in
        guard let lastMessageHandle = task.makeMessageHandles().last else {
            return nil
        }
        return FastAddTaskCheckpoint(lastMessageHandle: lastMessageHandle) {
            task.operationType.isSuccessful
        }
    }
}

static func usesTaskScopedVerification(_ syncData: NodeSyncData) -> Bool {
    switch syncData {
    case .profile,
         .syncScenes,
         .deleteScenes,
         .syncSchedules,
         .deleteSchedules,
         .syncCollectionSchedules,
         .deleteCollectionSchedules,
         .syncSwitchProxy,
         .deleteSwitchProxy,
         .syncSwitchs,
         .deleteSwitchs,
         .proximityLightingEnabled,
         .proximityLightingRelayNumber,
         .proximityLightingNeighbor:
        return true
    default:
        return false
    }
}
```

该 case 集合必须与 `DeviceGroupDeferredSyncPlanner.makePlan` 中进入 `deferredTasks` 的集合一致。

- [ ] **Step 5：修改 Light 和 Sensor 的计划创建**

将 Light 分支的返回部分改为：

```swift
let immediateSyncDatas = syncDatas.filter { !usesTaskScopedVerification($0) }
let taskCheckpoints = makeTaskCheckpoints(tasks: plan.deferredTasks)

return DeviceGroupFastAddSyncPlan(
    nodeAddress: node.primaryUnicastAddress,
    group: group,
    appendMessageHandles: appendMessageHandles,
    verificationOperations: makeVerificationOperations(
        syncDatas: immediateSyncDatas,
        node: node
    ),
    taskCheckpointTracker: FastAddTaskCheckpointTracker(
        checkpoints: taskCheckpoints
    )
)
```

将 Sensor 分支的返回部分改为：

```swift
return DeviceGroupFastAddSyncPlan(
    nodeAddress: node.primaryUnicastAddress,
    group: group,
    appendMessageHandles: appendMessageHandles,
    verificationOperations: makeVerificationOperations(
        syncDatas: syncDatas,
        node: node
    ),
    taskCheckpointTracker: FastAddTaskCheckpointTracker(checkpoints: [])
)
```

不要改变以下生成顺序：

```swift
let appendMessageHandles = plan.immediateMessageHandles
    + plan.deferredTasks.flatMap { $0.makeMessageHandles() }
```

- [ ] **Step 6：运行 Planner 契约并确认通过**

运行：

```bash
bash scripts/check_fast_add_dual_scene_verification.sh
```

预期：

```text
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
PASS: Fast Add dual-scene task-scoped verification
```

再运行：

```bash
git diff --check
```

预期：无输出，退出码为 0。

- [ ] **Step 7：提交 Planner 接入**

```bash
git add \
  SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift \
  scripts/check_fast_add_dual_scene_verification.sh
git commit -m "fix: verify fast add tasks at completion boundaries"
```

---

### Task 3：让 Classic 与 Professional 记录成功检查点

**文件：**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Modify: `scripts/check_fast_add_dual_scene_verification.sh`

**接口：**

- Consumes: `DeviceGroupFastAddSyncPlan.recordSuccessfulMessageHandle(_:)`
- 保留: `recordFastAddGroupSyncFailure(_:)`
- 保留: `resolveEmergencyFireGroupMutationFailed(for:)`

- [ ] **Step 1：先扩展双入口失败契约**

在 `scripts/check_fast_add_dual_scene_verification.sh` 的成功输出之前加入：

```bash
classic="SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift"
professional="SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift"

for controller in "$classic" "$professional"; do
  rg -n -F 'if let plan = self?.fastAddGroupSyncPlan(containing: messageHandle)' "$controller" >/dev/null \
    || fail "$controller must resolve the shared Fast Add plan in the success callback"
  rg -n -F 'plan.recordSuccessfulMessageHandle(messageHandle)' "$controller" >/dev/null \
    || fail "$controller must record the checkpoint after updating Node"
  rg -n -U 'node\.updateData\(message: messageHandle\.message\)\n[[:space:]]+plan\.recordSuccessfulMessageHandle\(messageHandle\)' "$controller" >/dev/null \
    || fail "$controller must update Node before evaluating the task checkpoint"
  rg -n -F 'self.recordFastAddGroupSyncFailure(plan)' "$controller" >/dev/null \
    || fail "$controller must preserve real message failure handling"
done
```

- [ ] **Step 2：运行契约并确认先失败**

运行：

```bash
bash scripts/check_fast_add_dual_scene_verification.sh
```

预期：FAIL，首先指出 Classic 缺少 `plan.recordSuccessfulMessageHandle(messageHandle)`。

- [ ] **Step 3：修改 Classic 成功回调**

在 `DeviceAddClassicModeController.swift` 的 `appendMessageSuccessBack` 中，将组同步分支改为：

```swift
if let plan = self?.fastAddGroupSyncPlan(containing: messageHandle) {
    node.updateData(message: messageHandle.message)
    plan.recordSuccessfulMessageHandle(messageHandle)
} else {
    DispatchQueue.global().async {
        node.updateData(message: messageHandle.message)
    }
}
```

顺序不可交换：SDK 已经先用 ACK 更新 Node，控制器再同步执行 `updateData`，最后才允许检查点读取 Node。

- [ ] **Step 4：修改 Professional 成功回调**

在 `DeviceAddProfessionalModeController.swift` 的 `appendMessageSuccessBack` 中使用同一实现：

```swift
if let plan = self?.fastAddGroupSyncPlan(containing: messageHandle) {
    node.updateData(message: messageHandle.message)
    plan.recordSuccessfulMessageHandle(messageHandle)
} else {
    DispatchQueue.global().async {
        node.updateData(message: messageHandle.message)
    }
}
```

不要修改两个控制器的失败回调、EFC 路由、Battery Power Switch 路由和 UI 状态赋值。

- [ ] **Step 5：运行全部聚焦契约**

运行：

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
bash scripts/check_fast_add_dual_scene_verification.sh
git diff --check
```

预期：

```text
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
PASS: Fast Add dual-scene task-scoped verification
```

`git diff --check` 无输出，退出码为 0。

- [ ] **Step 6：审查本任务范围**

运行：

```bash
git diff --name-only HEAD
```

预期只包含：

```text
SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
scripts/check_fast_add_dual_scene_verification.sh
```

若出现 `Node+SyncData.swift`、本地 SDK、Localizable、资源或其他控制器，停止并移除范围外改动。

- [ ] **Step 7：提交双入口接入**

```bash
git add \
  SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift \
  SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift \
  scripts/check_fast_add_dual_scene_verification.sh
git commit -m "fix: record fast add task verification checkpoints"
```

---

### Task 4：完成四品牌构建与行为验收

**文件：**

- Verify: `SunSmart.xcworkspace`
- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- Verify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Verify: 两个 Add Device controller

**接口：**

- Consumes: 前三项任务的完整实现。
- Produces: 静态测试、四品牌编译和真机验收证据。

- [ ] **Step 1：运行完整静态验证**

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
bash scripts/check_fast_add_dual_scene_verification.sh
git diff --check
```

预期：两个脚本均 PASS，`git diff --check` 无输出。

- [ ] **Step 2：确认工程与本地 SDK 边界**

运行：

```bash
git diff --name-only 8808bc23..HEAD
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

App 仓库预期只有本计划列出的 source、test、script 和 project 文件；本地 SDK 不得因本修复产生新改动。

确认 `SunSmart.xcodeproj/project.pbxproj` 中仍使用：

```text
XCLocalSwiftPackageReference "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk"
```

- [ ] **Step 3：构建 SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 4：构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 6：构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

如果当前环境首次构建因 sandbox package resolution 失败，应使用相同的直接 `xcodebuild` 命令申请必要权限后重试；不要切换 Simulator，不要用 shell 包装或重定向日志。

- [ ] **Step 7：人工检查最终差异**

运行：

```bash
git status --short
git diff 8808bc23..HEAD -- \
  SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift \
  SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift \
  SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift \
  SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift \
  Tests/Device/FastAddTaskCheckpointTrackerTests.swift \
  scripts/check_fast_add_task_checkpoint_tracker.sh \
  scripts/check_fast_add_dual_scene_verification.sh \
  SunSmart.xcodeproj/project.pbxproj
```

必须确认：

- Night 检查点在 Day 消息发送前固化；
- deferred operations 不再参加批次末当前态回查；
- immediate operations 和 Sensor Fast Add 仍有最终校验；
- `.sensorEnabled` 仍通过精确 retransmit 比较；
- Classic 与 Professional 的 Node 更新和检查点顺序一致；
- 空 Path 代码、Group `SET Path`、SDK 和本地化均未修改。

- [ ] **Step 8：真机验收**

按以下顺序记录结果：

1. 创建无 Path 的 `Proximity/Predictive lighting with photocell` 组；
2. Classic Add Device 直接加入设备；
3. 确认 Night `0xFF01`、Day `0xFF02`、Motion Sensitivity、空邻居 Proximity 均返回成功；
4. 确认 Add Device 显示成功，不出现 `sync_failed`；
5. 返回 Group 页面，确认设备正常展示，同时保留 `SET Path`；
6. Professional Add Device 重复步骤 2～5；
7. 制造真实配置失败，确认 Add Device 仍显示 `sync_failed`；
8. 使用第 4 个成员触发 retransmit 目标变化，确认旧值未收敛时仍显示失败，新值收敛后显示成功。

如果没有可用真机或 Mesh 设备，交付报告必须明确写为“编译与静态验证通过，真机 Mesh 验收待执行”，不得把构建成功表述为设备行为已验证。

---

## 最终完成标准

- 聚焦 Swift 测试和两个 source contract 脚本全部通过；
- 四个共享品牌 scheme 的 generic iPhoneOS 构建全部成功；
- Classic 与 Professional 使用同一个任务检查点机制；
- Night 的成功结果不会被 Day 当前状态覆盖；
- 真实消息失败、检查点失败或检查点未完成仍产生 `.syncFailed`；
- 成员数超过 3 时严格 retransmit 校验仍有效；
- 空 Path 和 Group `SET Path` 行为未改变；
- NordicSigMeshSDK、协议、本地化和无关模块没有改动；
- 真机验收结果与编译结果分开报告。
