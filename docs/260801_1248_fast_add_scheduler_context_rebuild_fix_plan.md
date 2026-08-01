# Fast Add Scheduler Group 上下文重建修复实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话中逐任务 Inline Execution；每一步使用 checkbox 跟踪。未经用户明确要求，不使用 subagents，不执行 Git commit、push 或 merge。

**目标：** 修复 Fast Add 和 Group Deferred Sync 重建 Schedule handles 时丢失目标 Group 上下文的问题，使 automatic Group 的 `turnOn` Schedule 首次就写入 Light LC Scheduler，并让 Fast Add 使用与普通 Group Sync 相同的 per-Model 同步真值。

**架构：** 为 `DeviceOperationType` 增加兼容现有调用的 context-aware 消息生成方法，`DeviceGroupDeferredSyncTask` 在 Fast Add batch 和每次 retry 中显式传入目标 Group。一个 Fast Add batch 内发送列表与 checkpoint 复用同一批 handles；不同 retry 重新生成 handles。Schedule task 的成功判定改用 Group-aware、per-Model 差异，其他操作继续使用现有判定。

**技术栈：** Swift、UIKit、NordicSigMeshSDK、SIG Mesh Scheduler、Swift standalone contract tests、Bash/Zsh、Xcode generic iPhoneOS build。

## 全局约束

- 当前年份按 2026 年处理，所有说明和文档使用简体中文。
- 只修改 iOS App 内 Fast Add/Deferred Sync 及其测试脚本，不修改 NordicSigMeshSDK。
- 不修改 Scheduler Owner 规则、opcode、payload、消息顺序、15 秒 ACK timeout 或 `maxRetryCount = 2`。
- 不修改数据库、云端、UI、本地化、资源、依赖或 target 配置。
- 不隐藏 Need Sync，不清空业务 dirty state，不放宽 per-Model Scheduler 比较。
- 保留 Classic 与 Professional Controller 共享 `DeviceGroupFastAddSyncPlanner` 的现状。
- 保留 Scene Recall 过滤、空任务成功和非 Schedule task 的现有行为。
- 使用 `apply_patch` 修改文件，不格式化无关代码。
- 构建直接运行 `xcodebuild`，使用 generic iPhoneOS destination，不使用 shell 包装、日志重定向或 Simulator。
- 不执行 Git commit、push 或 merge；每个任务以 diff 和测试结果作为检查点。
- 设计依据：`docs/260801_1230_fast_add_scheduler_context_rebuild_fix_design.md`。

---

## 文件结构

- 修改 `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
  - 为 context-aware operation factory、Fast Add batch、retry 和 model-aware verification 增加 RED/GREEN 源码契约。
- 修改 `scripts/check_timed_scheduler_single_owner.sh`
  - 将 `SyncDevicesCellModel.swift` 作为新增契约输入传给 standalone Swift 测试。
- 修改 `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 提供 `DeviceOperationType.makeMessageHandles(contextGroup:)`，并让现有 `messageHandles` 属性保持兼容。
- 修改 `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 删除预建 handle 状态；Fast Add batch 和 retry 使用同一 Group 重新生成；Schedule verification 使用 per-Model 真值。
- 修改 `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
  - 补强一次 batch 内身份一致和不同生成批次相互独立的契约。
- 修改 `scripts/check_fast_add_dual_scene_verification.sh`
  - 修正 Controller 多行调用检查，并串联 Scheduler context contract。
- 更新 `docs/260801_1128_proximity_photocell_direct_add_scheduler_owner_regression_analysis.md`
  - 实施完成后记录静态、构建和真机验证边界，不提前宣称真机修复完成。

---

### Task 1：先建立 contextGroup 全链路 RED 契约

**Files:**

- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift:5-48,297-360,544-571`
- Modify: `scripts/check_timed_scheduler_single_owner.sh:17-32`
- Test: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**

- Consumes: 当前 `DeviceOperationType.messageHandles`、`DeviceGroupDeferredSyncTask.makeMessageHandles()` 和 Planner 源码。
- Produces: `testDeferredTaskGroupContext(...)` 源码契约，以及第 12 个源码输入 `SyncDevicesCellModel.swift`。

- [ ] **Step 1：扩展 standalone contract 的输入参数**

把参数数量从 12 调整为 13，并读取新增的 operation model 源码：

```swift
guard CommandLine.arguments.count == 13 else {
    fatalError("Expected 12 source file paths")
}

let operationModel = try source(at: 12)
```

在主测试序列中加入：

```swift
testDeferredTaskGroupContext(
    operationModel: operationModel,
    groupSyncPlanner: groupSyncPlanner
)
```

- [ ] **Step 2：写入当前实现必然失败的 context 传播契约**

新增测试，使用现有 `section(in:from:to:)` 限定检查范围，并使用空白归一化避免多行格式造成假失败：

```swift
private static func testDeferredTaskGroupContext(
    operationModel: String,
    groupSyncPlanner: String
) {
    let operationMessages = normalized(section(
        in: operationModel,
        from: "/// 对应操作需要发送的消息处理",
        to: "/// 设备删除操作"
    ))
    let task = normalized(section(
        in: groupSyncPlanner,
        from: "struct DeviceGroupDeferredSyncTask",
        to: "struct DeviceGroupDeferredSyncPlan"
    ))
    let attempts = normalized(section(
        in: groupSyncPlanner,
        from: "static func runTasks(",
        to: "static func logTaskAttempt("
    ))
    let batch = normalized(section(
        in: groupSyncPlanner,
        from: "static func makeTaskCheckpointBatch(",
        to: "static func usesTaskScopedVerification("
    ))

    require(
        operationMessages.contains("func makeMessageHandles( contextGroup: Group? = nil ) -> [MeshMessageHandle]"),
        "DeviceOperationType must expose context-aware message generation"
    )
    require(
        operationMessages.contains("schedule.getMessageHandles( node: node, contextGroup: contextGroup )"),
        "Schedule configuration must forward contextGroup"
    )
    require(
        task.contains("operationType.makeMessageHandles(contextGroup: contextGroup)"),
        "Deferred task regeneration must retain Group context"
    )
    require(
        !task.contains("let messageHandles: [MeshMessageHandle]"),
        "Deferred task must not retain executed handles for retry"
    )
    require(
        attempts.contains("task.makeMessageHandles(contextGroup: group)"),
        "Every deferred attempt must regenerate with the target Group"
    )
    require(
        batch.contains("task.makeMessageHandles(contextGroup: group)"),
        "Fast Add batch must generate handles with the target Group"
    )
}

private static func normalized(_ source: String) -> String {
    source.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
}
```

实施时根据 Swift 源码归一化后的实际空格微调断言字符串，但不得退回依赖完整单行格式的检查。

- [ ] **Step 3：把 operation model 路径传入测试程序**

在 `scripts/check_timed_scheduler_single_owner.sh` 的测试参数末尾追加：

```zsh
"${repo_root}/SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
```

- [ ] **Step 4：运行测试并确认 RED 原因准确**

Run:

```bash
zsh scripts/check_timed_scheduler_single_owner.sh
```

Expected: FAIL，首个相关错误必须是缺少 `makeMessageHandles(contextGroup:)` 或 task 仍通过无上下文入口重建；不能接受编译错误、参数数量错误或 source marker 错误作为 RED 证据。

- [ ] **Step 5：检查本任务 diff**

Run:

```bash
git diff -- Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift scripts/check_timed_scheduler_single_owner.sh
```

Expected: 只有新增输入和 context RED 契约，无业务代码改动、无无关格式化。

---

### Task 2：实现 context-aware handle 生成和 retry 生命周期

**Files:**

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:443-690`
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:9-17,75,178-232,314-428,463-478`
- Test: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**

- Consumes: `Schedule.getMessageHandles(node:contextGroup:delete:)`、Task 1 的 RED 契约、目标 `Group`。
- Produces: `DeviceOperationType.makeMessageHandles(contextGroup:)`、`DeviceGroupDeferredSyncTask.makeMessageHandles(contextGroup:)`、Group-aware Fast Add batch 和 retry。

- [ ] **Step 1：把 DeviceOperationType 现有生成逻辑迁入兼容方法**

保留现有属性作为默认入口：

```swift
var messageHandles: [MeshMessageHandle] {
    makeMessageHandles()
}

func makeMessageHandles(
    contextGroup: Group? = nil
) -> [MeshMessageHandle] {
    var messageHandles: [MeshMessageHandle] = []
    // 原 switch self 的完整逻辑原样迁入
    return messageHandles
}
```

除 Schedule configuration 外，原 switch 的每个分支内容保持不变。

- [ ] **Step 2：只给 Schedule configuration 继续传递 contextGroup**

把配置分支限定为：

```swift
case .schedule(let schedule):
    messageHandles.append(
        contentsOf: schedule.getMessageHandles(
            node: node,
            contextGroup: contextGroup
        )
    )
```

Schedule delete 保持 `delete: true` 的全 Model 清理语义，不改变 payload 或顺序。

- [ ] **Step 3：让 deferred task 只保存语义操作**

将 task 收敛为：

```swift
struct DeviceGroupDeferredSyncTask {
    let operationType: DeviceOperationType

    func makeMessageHandles(
        contextGroup: Group
    ) -> [MeshMessageHandle] {
        operationType
            .makeMessageHandles(contextGroup: contextGroup)
            .filter { !($0.message is SceneRecall) }
    }
}
```

删除 task 的 `messageHandles`、`filteredSceneRecallCount`，并删除 `appendTask` 的 `explicitMessageHandles` 参数和预生成逻辑。`.syncSchedules` 与其他分支一样只创建 semantic `DeviceOperationType`。

- [ ] **Step 4：Fast Add batch 每个 task 只生成一次**

把 batch 工厂签名改为：

```swift
static func makeTaskCheckpointBatch(
    tasks: [DeviceGroupDeferredSyncTask],
    group: Group
) -> FastAddTaskCheckpointBatch<MeshMessageHandle>
```

调用端和 batch 内部统一传 Group：

```swift
let deferredBatch = makeTaskCheckpointBatch(
    tasks: plan.deferredTasks,
    group: group
)

let messageHandles = task.makeMessageHandles(contextGroup: group)
```

`FastAddTaskCheckpointSource` 必须继续直接接收这次生成的 `messageHandles`，不得再次生成 checkpoint handles。

- [ ] **Step 5：每次 deferred attempt 使用同一 Group 生成全新 handles**

删除 `runTasks` 中生成后立即丢弃的 `let messageHandles = task.makeMessageHandles()` 和对应 guard；由 `runTaskAttempt` 唯一生成当前 attempt：

```swift
let messageHandles = task.makeMessageHandles(contextGroup: group)
guard !messageHandles.isEmpty else {
    completion(true)
    return
}
```

递归 retry 不传递旧 handles，确保下一 attempt 再次调用该方法。

- [ ] **Step 6：运行 context 契约并确认 GREEN**

Run:

```bash
zsh scripts/check_timed_scheduler_single_owner.sh
```

Expected: `TimedSchedulerOwnerPolicyTests passed` 和 `TimedSchedulerSingleOwnerContractTests passed`。

- [ ] **Step 7：检查焦点 diff**

Run:

```bash
git diff -- SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift scripts/check_timed_scheduler_single_owner.sh
```

Expected: 非 Schedule operation 分支无语义变化；不存在无关格式化、SDK 改动或 Controller 改动。

---

### Task 3：增加 Group-aware、per-Model Schedule 成功判定

**Files:**

- Modify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift:新增 deferred verification 契约`
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:DeviceGroupDeferredSyncTask, runTaskAttempt, makeTaskCheckpointBatch`
- Test: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

**Interfaces:**

- Consumes: `Schedule.needsSync(on:contextGroup:)`、`Schedule.needsDelete(from:contextGroup:)`、Task 2 的 context-aware task。
- Produces: `DeviceGroupDeferredSyncTask.isSuccessful(contextGroup:)`，供 Fast Add checkpoint 和 deferred retry 共用。

- [ ] **Step 1：先补充严格验证 RED 契约**

在 `testDeferredTaskGroupContext` 中加入：

```swift
require(
    task.contains("!schedule.needsSync(on: node, contextGroup: contextGroup)"),
    "Schedule configuration must verify the owner and cleanup Models"
)
require(
    task.contains("!schedule.needsDelete(from: node, contextGroup: contextGroup)"),
    "Schedule deletion must verify every Scheduler Model is clear"
)
require(
    attempts.contains("task.isSuccessful(contextGroup: group)"),
    "Deferred retry must use Group-aware task verification"
)
require(
    batch.contains("task.isSuccessful(contextGroup: group)"),
    "Fast Add checkpoints must use Group-aware task verification"
)
```

- [ ] **Step 2：运行测试并确认 RED 指向旧的合并状态判定**

Run:

```bash
zsh scripts/check_timed_scheduler_single_owner.sh
```

Expected: FAIL，错误必须指向缺少 `task.isSuccessful(contextGroup:)` 或缺少 model-aware Schedule 判断。

- [ ] **Step 3：实现 task 级严格验证**

在 `DeviceGroupDeferredSyncTask` 中增加：

```swift
func isSuccessful(contextGroup: Group) -> Bool {
    switch operationType {
    case .configuration(let node, let type):
        if case .schedule(let schedule) = type {
            return !schedule.needsSync(
                on: node,
                contextGroup: contextGroup
            )
        }
    case .delete(let node, let type):
        if case .schedule(let schedule) = type {
            return !schedule.needsDelete(
                from: node,
                contextGroup: contextGroup
            )
        }
    default:
        break
    }
    return operationType.isSuccessful
}
```

`default: break` 必须保留，使 `.read` 和其他未特化 operation 明确回退到原有验证语义。

- [ ] **Step 4：Fast Add checkpoint 和 retry 复用同一严格判定**

替换两处旧判定：

```swift
let operationSuccessful = task.isSuccessful(contextGroup: group)
```

以及 checkpoint closure：

```swift
return FastAddTaskCheckpointSource(
    messageHandles: messageHandles
) {
    task.isSuccessful(contextGroup: group)
}
```

- [ ] **Step 5：运行 Scheduler 契约并确认 GREEN**

Run:

```bash
zsh scripts/check_timed_scheduler_single_owner.sh
```

Expected: 两个 Timed Scheduler 测试程序均通过；Owner policy、cleanup、历史入口和新增 Fast Add context 契约全部为 GREEN。

- [ ] **Step 6：确认没有通过 UI 状态绕过真实差异**

Run:

```bash
rg -n "getNeedSyncGroup|legacyCompatible|clear.*needSync|needSync.*false" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected: 不出现新增的 Group 页面兼容结果、强制清除 Need Sync 或放宽验证代码。

---

### Task 4：补强 checkpoint 生命周期并修复失效的集成脚本

**Files:**

- Modify: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift:main 和 identity tests`
- Modify: `scripts/check_fast_add_dual_scene_verification.sh:13-78`
- Test: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Test: `scripts/check_fast_add_dual_scene_verification.sh`

**Interfaces:**

- Consumes: `FastAddTaskCheckpointBatch`、Task 2/3 的 task APIs、Classic/Professional success callback。
- Produces: 不受源码换行影响的 Fast Add 集成契约，证明同 batch identity、跨 batch independence、Group context 和回调顺序。

- [ ] **Step 1：增加两个独立 batch 不共享 handle 状态的测试**

在 tracker tests 中加入并从 `main()` 调用：

```swift
private static func testSeparateBatchesKeepIndependentHandleIdentity() {
    let firstTail = TestMessageHandle()
    let retryTail = TestMessageHandle()
    let firstBatch = FastAddTaskCheckpointBatch(
        sources: [
            FastAddTaskCheckpointSource(
                messageHandles: [firstTail],
                verify: { true }
            )
        ]
    )
    let retryBatch = FastAddTaskCheckpointBatch(
        sources: [
            FastAddTaskCheckpointSource(
                messageHandles: [retryTail],
                verify: { true }
            )
        ]
    )

    precondition(firstBatch.messageHandles[0] !== retryBatch.messageHandles[0])
    firstBatch.tracker.recordSuccess(for: retryTail)
    precondition(firstBatch.tracker.hasFailure)
    firstBatch.tracker.recordSuccess(for: firstTail)
    precondition(!firstBatch.tracker.hasFailure)
}
```

该测试只证明 batch/tracker 身份隔离；“生产 retry 每次调用生成方法”由 Task 1 的 Planner 源码契约负责，不能把测试替身结果冒充真实 Mesh handle 验证。

- [ ] **Step 2：运行 tracker tests**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
```

Expected: `FastAddTaskCheckpointTrackerTests passed` 和 `PASS: Fast Add task checkpoint tracker`。

- [ ] **Step 3：让 dual-scene 脚本串联 Scheduler context contract**

在脚本开头的 tracker test 之后增加：

```bash
zsh scripts/check_timed_scheduler_single_owner.sh
```

更新旧检查，使其匹配新的 Group-aware API：

```bash
rg -n -F 'task.makeMessageHandles(contextGroup: group)' "$planner" >/dev/null \
  || fail "Fast Add and retries must regenerate deferred handles with the target Group"
rg -n -F 'task.isSuccessful(contextGroup: group)' "$planner" >/dev/null \
  || fail "Fast Add and retries must verify Schedule state with the target Group"
```

删除要求旧调用 `task.makeMessageHandles()` 和 `task.operationType.isSuccessful` 的断言。

- [ ] **Step 4：修复 Classic/Professional 多行 updateData 顺序检查**

使用 `rg -U` 的局部 multiline pattern，允许 `updateData` 参数换行，但仍要求 `plan.recordSuccessfulMessageHandle` 出现在更新 Node 之后：

```bash
rg -n -U '(?s:node\.updateData\(.{0,500}?message:[[:space:]]*messageHandle\.message.{0,500}?\)[[:space:]]+plan\.recordSuccessfulMessageHandle\(messageHandle\))' "$controller" >/dev/null \
  || fail "$controller must update Node before evaluating the task checkpoint"
```

保留 Classic 与 Professional 循环、真实消息失败处理、空 Path/Zone、sensor publication 严格比较和禁止 compatibility bypass 的检查。

- [ ] **Step 5：运行修正后的完整脚本**

Run:

```bash
bash scripts/check_fast_add_dual_scene_verification.sh
```

Expected: tracker、Timed Scheduler policy/contract 和 Fast Add dual-scene/task-scoped verification 全部 PASS。

- [ ] **Step 6：确认脚本失败路径仍有效**

临时在工作副本中把一条 context 断言指向不存在的标记，运行脚本确认返回非零后，立即使用 `apply_patch` 恢复该测试行；不得使用 `git checkout` 或 `git reset`。

Expected: 人为破坏时明确 FAIL，恢复后重新运行为 PASS，证明脚本不是无条件成功。

---

### Task 5：静态检查与三个共享 scheme 的 iPhoneOS 构建

**Files:**

- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Verify: `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
- Verify: `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- Verify: `scripts/check_timed_scheduler_single_owner.sh`
- Verify: `scripts/check_fast_add_dual_scene_verification.sh`

**Interfaces:**

- Consumes: Tasks 1-4 的完成代码和测试。
- Produces: 可复现的静态测试、diff hygiene 和 generic iPhoneOS 构建证据。

- [ ] **Step 1：串行运行所有 focused tests**

Run:

```bash
bash scripts/check_fast_add_task_checkpoint_tracker.sh
zsh scripts/check_timed_scheduler_single_owner.sh
bash scripts/check_fast_add_dual_scene_verification.sh
```

Expected: 三条命令全部退出码 0；不能把脚本内部重复运行某个测试当作跳过独立命令的理由。

- [ ] **Step 2：检查 diff 和工作区归属**

Run:

```bash
git status --short
git diff --check
git diff --stat
git diff -- SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift Tests/Device/FastAddTaskCheckpointTrackerTests.swift scripts/check_timed_scheduler_single_owner.sh scripts/check_fast_add_dual_scene_verification.sh
```

Expected: 只有计划内文件和用户已有文档；无空白错误、无 SDK/资源/依赖/target 配置改动。

- [ ] **Step 3：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。若失败，先区分编译错误、依赖解析、签名或环境阶段，只修复本任务导致的编译问题。

- [ ] **Step 4：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6：记录静态与构建边界**

把每条测试和每个 scheme 的实际结果记录到最终总结。即使全部通过，也必须明确“尚未进行真实 Mesh 硬件验收”，不能宣称完整修复已在真机确认。

---

### Task 6：真机 Mesh 闭环验收与文档收尾

**Files:**

- Modify: `docs/260801_1128_proximity_photocell_direct_add_scheduler_owner_regression_analysis.md:验证状态`
- Review: 用户提供的修复后 Fast Add 和再次进入 Sync 的日志

**Interfaces:**

- Consumes: Tasks 1-5 的实现、可安装 App、支持 ordinary 与 Light LC Scheduler 的真实设备。
- Produces: 首次写入正确且无需二次迁移的日志证据，以及区分静态、构建和真机状态的最终报告。

- [ ] **Step 1：Classic 主路径验收**

在 Classic Fast Add 中直接把新设备加入 `Proximity/Predictive Lighting with Photocell` Group，保存完整日志。

Expected:

- index 0、5 的 cleanup `noAction` 发往 ordinary Scheduler；
- index 0、5 的有效 `turnOn` entry 发往 Light LC Scheduler；
- 所有对应 ACK 成功；
- 添加完成后不显示 Need Sync。

- [ ] **Step 2：Professional 主路径验收**

在 Professional Fast Add 重复同一设备类型和 Group Profile，保存完整日志。

Expected: 与 Classic 的 Owner、cleanup 和最终状态一致。

- [ ] **Step 3：再次进入 Sync 验证无二次迁移**

添加完成后进入 Group Sync 页面并触发状态读取；如页面没有差异，不强制发送 SAVE。

Expected: 不再出现“清理 ordinary、写入 Light LC”的纠正 batch，因为首次 Fast Add 已完成正确路由。

- [ ] **Step 4：补测低风险路径**

至少覆盖：

- Timed Scene Recall：继续使用 ordinary Scheduler；
- 普通 Scene Store：Scene 数据无需二次同步；
- 无 Schedule Group：不新增 Scheduler 消息；
- 人为制造一次 Mesh 失败：真实失败仍显示失败并保留 Sync 入口。

- [ ] **Step 5：更新分析文档的验证状态**

只记录实际完成的结果：

- focused contracts；
- 三个 generic iPhoneOS builds；
- Classic 真机；
- Professional 真机；
- 再次进入 Sync；
- Scene/无 Schedule/真实失败回归。

未执行或证据不足的项目必须标注“未验证”，不得写成通过。

- [ ] **Step 6：最终工作区检查**

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: 仅包含本计划授权的代码、测试、脚本和文档改动；不创建 commit。

---

## 最终验收清单

- [ ] 当前未修复代码能够被新增 RED 契约准确捕获。
- [ ] `DeviceOperationType` 的普通调用保持无上下文兼容。
- [ ] Fast Add batch 首次生成显式使用目标 Group。
- [ ] deferred retry 每次生成新 handles 并保留目标 Group。
- [ ] 同一 batch 的发送 handles 与 checkpoint 使用相同实例。
- [ ] Schedule ACK 成功后按正确 Owner 和 cleanup Models 验证。
- [ ] 非 Schedule task、Scene Recall、Profile、Scene、Proximity 和空 Path 行为不变。
- [ ] Classic 与 Professional 共用 Planner 的契约继续成立。
- [ ] 三条 focused test 命令通过。
- [ ] `git diff --check` 通过。
- [ ] SunSmart、Archipelago、SylSmart generic iPhoneOS build 通过。
- [ ] 真机首次写入目标 Model 正确，添加完成后无 Need Sync。
- [ ] 再次进入 Sync 不产生 Owner 反向迁移。
- [ ] 最终报告明确区分静态、构建和真机验收。
