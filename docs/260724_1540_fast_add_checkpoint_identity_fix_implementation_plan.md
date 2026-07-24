# Fast Add 检查点对象身份修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Fast Add 实际发送列表与任务检查点复用同一批 `MeshMessageHandle` 对象，消除 Proximity/Predictive Lighting with Photocell 成功添加后出现红色同步图标的误报。

**Architecture:** 在现有泛型 Tracker 文件中增加 Fast Add 专用 batch；batch 从每个任务的一组句柄和严格验证闭包构建有序发送列表及尾句柄检查点。Light Fast Add Planner 对每个 deferred task 只调用一次 `makeMessageHandles()`，然后同时使用 batch 的 `messageHandles` 和 `tracker`；共享 Deferred Runner、Sensor 分支、Controller、Repair/Restore 与直接添加流程保持不变。

**Tech Stack:** Swift、NordicSigMeshSDK、现有 `swiftc` 测试脚本、Bash 源码边界检查、Xcode generic iPhoneOS build。

## 全局约束

- 仅修改 `FastAddTaskCheckpointTracker.swift`、`DeviceGroupDeferredSyncPlanner.swift` 的 Fast Add 专用部分、对应纯 Swift 测试及现有 Fast Add 检查脚本。
- 不修改 `DeviceGroupDeferredSyncTask.makeMessageHandles()` 的共享重试语义。
- 不修改 `DeviceGroupDeferredSyncPlanner.run`、`runTaskAttempt`、Classic/Professional Controller、`DeviceRestoreViewController`、无 Group 直接添加分支或 Group 页面同步入口。
- 不修改 `Node+SyncData.swift`、`SyncDevicesCellModel.swift`、NordicSigMeshSDK、本地化、资源、target 或依赖配置。
- 不改变任何 Mesh opcode、payload、消息顺序、Profile 参数、Path/Zone/Neighbor 规则或严格成功判定。
- Sensor Fast Add 继续使用现有消息列表、最终验证和空 Tracker。
- 真实消息失败、checkpoint 未完成或严格业务验证失败时仍必须得到 `.syncFailed`。
- 使用 TDD：先观察针对旧实现的失败，再写最小实现。
- 构建只使用 generic iPhoneOS，不使用 Simulator。
- 保留工作区中已有的未跟踪文档，不纳入本次代码提交。

---

## 文件结构与职责

- `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
  - 保留现有 checkpoint 状态机。
  - 新增纯 Swift 泛型 source/batch，唯一职责是保持发送句柄顺序和 checkpoint 对象身份。
- `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
  - 覆盖 batch 身份、顺序、空任务、非尾句柄、等价对象隔离以及现有 Night/Day 状态快照语义。
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 仅调整 Light Fast Add 组装：每个 deferred task 生成一次句柄，再复用 batch 输出。
  - 共享 Deferred Runner 的任务生成与重试逻辑不变。
- `scripts/check_fast_add_task_checkpoint_tracker.sh`
  - 继续编译并执行纯 Swift测试，继续确认 Tracker 属于四个 App target。
- `scripts/check_fast_add_dual_scene_verification.sh`
  - 更新 Fast Add 接线断言，增加旧双重生成方式的否定断言，保留现有严格成功判定和跨流程边界断言。

---

### Task 1：用纯 Swift Batch 锁定对象身份契约

**Files:**

- Modify: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Modify: `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- Verify: `scripts/check_fast_add_task_checkpoint_tracker.sh`

**Interfaces:**

- Consumes: 现有 `FastAddTaskCheckpoint<MessageHandle>` 与 `FastAddTaskCheckpointTracker<MessageHandle>`。
- Produces: `FastAddTaskCheckpointSource<MessageHandle>`，包含 `messageHandles: [MessageHandle]` 与 `verify: () -> Bool`。
- Produces: `FastAddTaskCheckpointBatch<MessageHandle>`，包含 `messageHandles: [MessageHandle]` 与 `tracker: FastAddTaskCheckpointTracker<MessageHandle>`。
- Guarantee: batch 中每个 checkpoint 的 `lastMessageHandle` 必须直接引用对应 source 的最后一个对象，不复制或重新创建对象。

- [ ] **Step 1：扩充测试入口，先覆盖 Batch 对象身份和边界**

将 `Tests/Device/FastAddTaskCheckpointTrackerTests.swift` 替换为以下完整内容：

```swift
final class TestMessageHandle {}

@main
struct FastAddTaskCheckpointTrackerTests {
    static func main() {
        testBatchPreservesMessageOrderAndTailIdentity()
        testActualTailHandleCompletesCheckpoint()
        testEquivalentHandleInstancesRemainIndependent()
        testNonTailHandleDoesNotCompleteCheckpoint()
        testUnknownHandleDoesNotCompletePendingCheckpoint()
        testEmptySourceIsIgnored()
        testEmptyBatchSucceeds()
        testNightResultSurvivesDayOverwrite()
        testFailedCheckpointCannotBecomeSuccessfulLater()
        testDuplicateSuccessDoesNotReevaluateCheckpoint()
        testUnknownHandleDoesNotAffectCompletedCheckpoint()
        testPendingCheckpointIsFailure()
        print("FastAddTaskCheckpointTrackerTests passed")
    }

    private static func testBatchPreservesMessageOrderAndTailIdentity() {
        let first = TestMessageHandle()
        let firstTail = TestMessageHandle()
        let secondTail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, firstTail],
                    verify: { true }
                ),
                FastAddTaskCheckpointSource(
                    messageHandles: [secondTail],
                    verify: { true }
                )
            ]
        )

        precondition(batch.messageHandles.count == 3)
        precondition(batch.messageHandles[0] === first)
        precondition(batch.messageHandles[1] === firstTail)
        precondition(batch.messageHandles[2] === secondTail)

        batch.tracker.recordSuccess(for: firstTail)
        precondition(batch.tracker.hasFailure)
        batch.tracker.recordSuccess(for: secondTail)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testActualTailHandleCompletesCheckpoint() {
        let first = TestMessageHandle()
        let tail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, tail],
                    verify: { true }
                )
            ]
        )

        let actualTail = batch.messageHandles[1]
        precondition(actualTail === tail)
        batch.tracker.recordSuccess(for: actualTail)

        precondition(!batch.tracker.hasFailure)
    }

    private static func testEquivalentHandleInstancesRemainIndependent() {
        let firstTail = TestMessageHandle()
        let secondTail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [firstTail],
                    verify: { true }
                ),
                FastAddTaskCheckpointSource(
                    messageHandles: [secondTail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: firstTail)
        precondition(batch.tracker.hasFailure)
        batch.tracker.recordSuccess(for: secondTail)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testNonTailHandleDoesNotCompleteCheckpoint() {
        let first = TestMessageHandle()
        let tail = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [first, tail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: first)

        precondition(batch.tracker.hasFailure)
    }

    private static func testUnknownHandleDoesNotCompletePendingCheckpoint() {
        let tail = TestMessageHandle()
        let unknown = TestMessageHandle()
        let batch = FastAddTaskCheckpointBatch(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [tail],
                    verify: { true }
                )
            ]
        )

        batch.tracker.recordSuccess(for: unknown)

        precondition(batch.tracker.hasFailure)
    }

    private static func testEmptySourceIsIgnored() {
        let batch = FastAddTaskCheckpointBatch<TestMessageHandle>(
            sources: [
                FastAddTaskCheckpointSource(
                    messageHandles: [],
                    verify: { false }
                )
            ]
        )

        precondition(batch.messageHandles.isEmpty)
        precondition(!batch.tracker.hasFailure)
    }

    private static func testEmptyBatchSucceeds() {
        let batch = FastAddTaskCheckpointBatch<TestMessageHandle>(sources: [])

        precondition(batch.messageHandles.isEmpty)
        precondition(!batch.tracker.hasFailure)
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
}
```

- [ ] **Step 2：运行测试，确认旧实现无法编译**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
```

Expected: FAIL，Swift 编译器报告找不到 `FastAddTaskCheckpointBatch` 或 `FastAddTaskCheckpointSource`。这是预期的 RED 阶段。

- [ ] **Step 3：实现最小泛型 Source 与 Batch**

在 `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift` 的现有 `FastAddTaskCheckpoint` 之后、Tracker 之前加入：

```swift
struct FastAddTaskCheckpointSource<MessageHandle: AnyObject> {
    let messageHandles: [MessageHandle]
    let verify: () -> Bool
}

struct FastAddTaskCheckpointBatch<MessageHandle: AnyObject> {
    let messageHandles: [MessageHandle]
    let tracker: FastAddTaskCheckpointTracker<MessageHandle>

    init(sources: [FastAddTaskCheckpointSource<MessageHandle>]) {
        var messageHandles: [MessageHandle] = []
        var checkpoints: [FastAddTaskCheckpoint<MessageHandle>] = []

        sources.forEach { source in
            guard let lastMessageHandle = source.messageHandles.last else {
                return
            }
            messageHandles.append(contentsOf: source.messageHandles)
            checkpoints.append(
                FastAddTaskCheckpoint(
                    lastMessageHandle: lastMessageHandle,
                    verify: source.verify
                )
            )
        }

        self.messageHandles = messageHandles
        tracker = FastAddTaskCheckpointTracker(checkpoints: checkpoints)
    }
}
```

不要修改 `FastAddTaskCheckpointTracker.recordSuccess` 的 `===` 身份匹配，不要把 pending 改成成功。

- [ ] **Step 4：运行纯 Swift 测试，确认通过**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
```

Expected:

```text
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
```

- [ ] **Step 5：检查本任务差异**

Run:

```bash
git diff --check
git diff -- SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift Tests/Device/FastAddTaskCheckpointTrackerTests.swift
```

Expected: `git diff --check` 无输出；差异只包含泛型 source/batch 和上述测试。

- [ ] **Step 6：提交 Batch 与测试**

```bash
git add SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift Tests/Device/FastAddTaskCheckpointTrackerTests.swift
git commit -m "test: cover fast add checkpoint handle identity"
```

Expected: commit 成功，且不包含现有未跟踪文档。

---

### Task 2：把 Light Fast Add 接到同一批句柄

**Files:**

- Modify: `scripts/check_fast_add_dual_scene_verification.sh`
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:55-93`
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:435-448`
- Verify unchanged: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:161-168`
- Verify unchanged: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:253-409`
- Verify unchanged: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify unchanged: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

**Interfaces:**

- Consumes: Task 1 的 `FastAddTaskCheckpointSource<MeshMessageHandle>`。
- Consumes: Task 1 的 `FastAddTaskCheckpointBatch<MeshMessageHandle>`。
- Produces: `DeviceGroupFastAddSyncPlanner.makeTaskCheckpointBatch(tasks:) -> FastAddTaskCheckpointBatch<MeshMessageHandle>`。
- Guarantee: helper 对每个 deferred task 只调用一次 `task.makeMessageHandles()`。
- Guarantee: `appendMessageHandles` 使用 `deferredBatch.messageHandles`，`taskCheckpointTracker` 使用同一 `deferredBatch.tracker`。

- [ ] **Step 1：先更新源码边界脚本，使旧接线失败**

在 `scripts/check_fast_add_dual_scene_verification.sh` 中，用以下检查替换原来的 `makeTaskCheckpoints(tasks: plan.deferredTasks)` 检查：

```bash
rg -n -F 'let deferredBatch = makeTaskCheckpointBatch(tasks: plan.deferredTasks)' "$planner" >/dev/null \
  || fail "Light Fast Add must prepare deferred handles and checkpoints in one batch"
rg -n -F '+ deferredBatch.messageHandles' "$planner" >/dev/null \
  || fail "Light Fast Add must append the prepared deferred handles"
rg -n -F 'taskCheckpointTracker: deferredBatch.tracker' "$planner" >/dev/null \
  || fail "Light Fast Add must reuse the tracker from the same prepared batch"
rg -n -F 'let messageHandles = task.makeMessageHandles()' "$planner" >/dev/null \
  || fail "Fast Add batch must generate each deferred task handle list once"

if rg -n -F 'plan.deferredTasks.flatMap { $0.makeMessageHandles() }' "$planner" >/dev/null; then
  fail "Light Fast Add must not regenerate deferred handles for the append list"
fi
if rg -n -F 'makeTaskCheckpoints(tasks: plan.deferredTasks)' "$planner" >/dev/null; then
  fail "Light Fast Add must not regenerate deferred handles for checkpoints"
fi
```

在 `taskCheckpointTracker.hasFailure` 检查之后加入 Sensor 分支保护：

```bash
rg -n -F 'taskCheckpointTracker: FastAddTaskCheckpointTracker(checkpoints: [])' "$planner" >/dev/null \
  || fail "Sensor Fast Add must continue to use an empty task checkpoint tracker"
```

保留脚本中关于以下行为的全部现有检查：

- `task.operationType.isSuccessful`
- `syncDatas.filter { !usesTaskScopedVerification($0) }`
- `effectiveMemberCount`
- strict sensor publication
- 禁止 Group page compatibility
- 空 Path/Zone
- Classic/Professional 先更新 Node 再记录 checkpoint
- 真实消息失败处理

- [ ] **Step 2：运行边界脚本，确认旧 Planner 接线失败**

Run:

```bash
bash scripts/check_fast_add_dual_scene_verification.sh
```

Expected: 纯 Swift Tracker 测试先通过，随后 FAIL：

```text
FAIL: Light Fast Add must prepare deferred handles and checkpoints in one batch
```

- [ ] **Step 3：在 Light Fast Add 分支创建并复用 Batch**

在 `DeviceGroupFastAddSyncPlanner.makePlan` 的 `.light` 分支中，把：

```swift
let appendMessageHandles = plan.immediateMessageHandles
    + plan.deferredTasks.flatMap { $0.makeMessageHandles() }
guard !appendMessageHandles.isEmpty else {
    return nil
}
let immediateSyncDatas = syncDatas.filter { !usesTaskScopedVerification($0) }
let taskCheckpoints = makeTaskCheckpoints(tasks: plan.deferredTasks)
```

替换为：

```swift
let deferredBatch = makeTaskCheckpointBatch(tasks: plan.deferredTasks)
let appendMessageHandles = plan.immediateMessageHandles
    + deferredBatch.messageHandles
guard !appendMessageHandles.isEmpty else {
    return nil
}
let immediateSyncDatas = syncDatas.filter { !usesTaskScopedVerification($0) }
```

并把返回 Plan 时的 Tracker：

```swift
taskCheckpointTracker: FastAddTaskCheckpointTracker(
    checkpoints: taskCheckpoints
)
```

替换为：

```swift
taskCheckpointTracker: deferredBatch.tracker
```

`.sensor`、`default` 和 `verificationOperations` 不做任何修改。

- [ ] **Step 4：用单次生成 helper 替换旧 Checkpoint helper**

在 `private extension DeviceGroupFastAddSyncPlanner` 中，把完整的旧方法：

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
```

替换为：

```swift
static func makeTaskCheckpointBatch(
    tasks: [DeviceGroupDeferredSyncTask]
) -> FastAddTaskCheckpointBatch<MeshMessageHandle> {
    let sources = tasks.compactMap { task -> FastAddTaskCheckpointSource<MeshMessageHandle>? in
        let messageHandles = task.makeMessageHandles()
        guard !messageHandles.isEmpty else {
            return nil
        }
        return FastAddTaskCheckpointSource(
            messageHandles: messageHandles
        ) {
            task.operationType.isSuccessful
        }
    }
    return FastAddTaskCheckpointBatch(sources: sources)
}
```

不要改动文件顶部的共享 `DeviceGroupDeferredSyncTask.makeMessageHandles()`，也不要改动 `runTasks` 和 `runTaskAttempt` 中用于重试的调用。

- [ ] **Step 5：运行 Fast Add 两组自动检查**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
bash scripts/check_fast_add_dual_scene_verification.sh
```

Expected:

```text
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
FastAddTaskCheckpointTrackerTests passed
PASS: Fast Add task checkpoint tracker
PASS: Fast Add dual-scene task-scoped verification
```

- [ ] **Step 6：验证改动边界**

Run:

```bash
git diff --check
git diff --name-only
git diff -- SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift scripts/check_fast_add_dual_scene_verification.sh
```

Expected:

- `git diff --check` 无输出；
- 本任务只修改 Planner 的 Fast Add 组装/helper 和边界脚本；
- `DeviceGroupDeferredSyncPlanner.run`、`runTasks`、`runTaskAttempt` 无差异；
- Classic/Professional Controller、`Node+SyncData.swift`、`SyncDevicesCellModel.swift`、Repair/Restore 和 SDK 无差异。

- [ ] **Step 7：提交 Planner 接线修复**

```bash
git add SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift scripts/check_fast_add_dual_scene_verification.sh
git commit -m "fix: reuse fast add handles for task checkpoints"
```

Expected: commit 成功，且只包含上述两个文件。

---

### Task 3：执行完整静态、构建与真机回归验收

**Files:**

- Verify: `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- Verify: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Verify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Verify: `scripts/check_fast_add_task_checkpoint_tracker.sh`
- Verify: `scripts/check_fast_add_dual_scene_verification.sh`
- Do not modify: 其他业务文件

**Interfaces:**

- Consumes: Task 1 的身份一致 batch。
- Consumes: Task 2 的 Light Fast Add 接线。
- Produces: 静态测试、四品牌 generic iPhoneOS 构建结果和真机回归记录。

- [ ] **Step 1：运行纯 Swift 测试与源码边界检查**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
bash scripts/check_fast_add_dual_scene_verification.sh
```

Expected: 两个脚本均输出 `PASS`，且无编译错误或边界断言失败。

- [ ] **Step 2：运行差异完整性检查**

Run:

```bash
git diff --check
git status --short
git diff --stat 8d45f7bf..HEAD
git diff --name-only 8d45f7bf..HEAD
```

Expected:

- `git diff --check` 无输出；
- 从已确认设计 commit `8d45f7bf` 开始，业务/测试改动只涉及：
  - `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
  - `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
  - `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - `scripts/check_fast_add_dual_scene_verification.sh`
- 计划文档可单独出现；
- 原有三个未跟踪文档继续保持未跟踪，不删除、不覆盖、不加入代码提交。

- [ ] **Step 3：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7：目标场景真机验收**

在 Add Device 页面，以 Light 设备加入未配置 Path 的 `Proximity/Predictive lighting with photocell` Group，记录以下结果：

1. 添加过程完成且全部 Mesh status 为 Success；
2. `motionSensitivity` 返回值仍精确等于请求值；
3. `proximityLightingNeighborSet` 成功，允许空 `neighborAddresses`；
4. Night Scene `FF01` 与 Day Scene `FF02` 都写入成功；
5. Add Device 页面设备右侧显示成功状态，不出现红色同步图标；
6. 返回 Group 页面后设备正常展示且无待同步提示。

Expected: 六项全部满足。若出现真实 Mesh 失败或严格状态不匹配，红色失败图标仍应出现。

- [ ] **Step 8：八种 Group Profile 回归**

分别执行 Light Fast Add，并记录 Add Device 页面最终状态及 Group 页面状态：

1. Occupancy sensing with daylight harvesting
2. Vacancy sensing with daylight harvesting
3. Occupancy sensing
4. Vacancy sensing
5. Daylight harvesting
6. Manual control
7. Proximity/Predictive lighting
8. Proximity/Predictive lighting with photocell

Expected: 成功场景不误报红色图标；每种 Profile 的消息顺序、参数和最终业务状态与修复前一致。

- [ ] **Step 9：其他添加与修复流程回归**

依次验证：

1. Classic 模式直接添加设备，不选择 Group；
2. Professional 模式直接添加设备，不选择 Group；
3. Light 添加到普通 Group；
4. Sensor 添加到 Group；
5. Repair 已有设备；
6. Restore 已有设备；
7. Proximity Group 有既有成员；
8. 人为制造一条真实消息失败。

Expected:

- 前七项沿用现有流程并保持原行为；
- 无 Group 直接添加、Repair、Restore 不进入 Fast Add batch；
- Sensor 继续使用空 checkpoint tracker；
- 第八项仍显示红色同步失败图标，不被本修复掩盖。

- [ ] **Step 10：最终提交检查**

Run:

```bash
git log -4 --oneline
git status --short
```

Expected:

- 存在独立的 Batch/测试提交和 Planner 接线修复提交；
- 没有意外修改 SDK、Controller、Repair/Restore、本地化、资源、target 或依赖；
- 未跟踪文档仍由用户决定是否纳入版本控制。

---

## 完成判定

只有同时满足以下条件，才能宣称修复完成：

- batch 自动测试证明发送尾句柄能以对象身份命中 checkpoint；
- Fast Add 源码边界脚本证明旧的双重句柄生成接线已移除；
- strict operation verification、pending/failed 判定和真实失败路径保留；
- `git diff --check` 通过；
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS build 全部成功；
- 目标 Photocell 真机场景不再误报红色图标；
- 其他七种 Profile、直接添加、Sensor 添加、Repair、Restore 和真实失败场景回归通过。

自动测试和构建成功只能证明代码与静态边界正确，不能替代真实 Mesh 硬件验收。
