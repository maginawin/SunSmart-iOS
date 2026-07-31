# Group Members 退组时 Timed Scheduler Owner 迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. 按项目约束使用 Inline Execution；除非用户明确要求，不使用 subagents。

**Goal:** 修复自动 Profile Group 退组时 Device Target 的 `Turn On` 定时未从 Light LC Scheduler 迁回 ordinary Scheduler的问题，同时保持“Scheduler 迁移失败仍继续退组、Timed 保留真实待同步”的失败语义。

**Architecture:** 保留现有 Owner 解析、`Schedule.needsSync`、`Node.getSyncData` 和 Scheduler 消息构建器；在现有 Timed Policy 文件新增一个不依赖 UIKit/Mesh 的退组步骤路由策略，并由 `SyncDevicesViewController` 使用。退出节点的 `.syncSchedules` 仍使用 configuration operation，但进入该节点的 Remove Section；普通同步和添加成员仍进入 Configuration Section。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Swift 行为测试与合同测试脚本、Xcode generic iPhoneOS build。

## Global Constraints

- 所有计划执行和交付说明使用简体中文。
- 当前年份按 2026 年处理。
- 仅修改计划列出的生产代码、测试和文档。
- 不修改 Scheduler Owner 解析、Timed 同步判定、SDK、Localizable strings、Assets、target 配置或依赖。
- 不新增 Auth 信息。
- 不格式化或重构无关代码。
- 保留工作区既有未提交文档和用户改动。
- 未经用户明确授权，不执行 Git commit、push、merge。
- 执行 iOS 构建时直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。
- Scheduler 迁移失败不阻止最终 `unsubscribeGroup`；失败状态必须继续由 Sync Devices 和 Timed 如实展示。
- 自动化和 generic iPhoneOS build 不能代替真机 Mesh 验收。

---

## 文件结构

### 生产代码

- Modify: `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
  - 新增纯 Group Member Exit Step 路由策略。
  - 只把退组布尔上下文映射为 Remove 或 Configuration。
  - 声明退组 Schedule Owner 迁移不阻止最终 Group removal。

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 计算 `.syncSchedules` 是否处于退组上下文并使用纯路由策略。
  - 将退组 Schedule Owner 迁移从 `removeGroupStep` 的阻断依赖中排除。
  - 不改变 Schedule operation 类型、Owner 解析、消息内容或失败聚合。

### 自动化测试

- Modify: `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`
  - 增加 Group Member Removal Schedule Routing 真实行为测试。
  - 验证退组返回 Remove，非退组返回 Configuration。
  - 验证退组 Schedule Owner 迁移不阻止 Group removal。

- Verify: `scripts/check_timed_scheduler_single_owner.sh`
  - 现有脚本已共同编译 Policy 与行为测试，无需修改。

### 文档

- Existing: `docs/260731_1409_timed_group_member_removal_resync_root_cause_analysis.md`
- Existing: `docs/260731_1438_timed_group_member_removal_scheduler_migration_design.md`
- This plan: `docs/260731_1445_timed_group_member_removal_scheduler_migration_implementation_plan.md`
- Execution output: 执行完成时按 `yyMMdd_HHmm_[description].md` 创建实施总结。

---

### Task 1: 建立退组 Scheduler 路由 RED 行为测试

**Files:**

- Modify: `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

**Interfaces:**

- Consumes:
  - 现有 `require(_:_:)` 行为测试工具。
- Produces:
  - `testGroupMemberExitRoutesScheduleMigrationToRemoval()`。
  - `testOrdinaryScheduleSyncRoutesToConfiguration()`。
  - 当前生产代码上稳定失败的 RED 结果。

- [ ] **Step 1: 从 main 调用两个新测试**

```swift
testGroupMemberExitRoutesScheduleMigrationToRemoval()
testOrdinaryScheduleSyncRoutesToConfiguration()
```

- [ ] **Step 2: 添加路由行为测试**

```swift
private static func testGroupMemberExitRoutesScheduleMigrationToRemoval() {
    require(
        TimedSchedulerGroupMemberExitStepPolicy.destination(
            isExitingGroup: true
        ) == .removal,
        "Exiting Group Schedule migration must route to Remove Section"
    )
}

private static func testOrdinaryScheduleSyncRoutesToConfiguration() {
    require(
        TimedSchedulerGroupMemberExitStepPolicy.destination(
            isExitingGroup: false
        ) == .configuration,
        "Ordinary Schedule synchronization must remain in Configuration Section"
    )
}
```

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```bash
scripts/check_timed_scheduler_single_owner.sh
```

Expected:

- Swift 编译失败；
- 失败原因明确为尚不存在的生产 API：

```text
cannot find 'TimedSchedulerGroupMemberExitStepPolicy' in scope
```

若失败原因是测试拼写或其他接线错误，先修正测试；只有缺少生产 API 才是有效 RED。

- [ ] **Step 4: RED 检查点**

Run:

```bash
git status --short
git diff -- Tests/Timed/TimedSchedulerOwnerPolicyTests.swift
```

Expected:

- 只有行为测试发生计划内修改；
- 根因分析、设计和计划文档继续保留；
- 不执行 Git commit。

---

### Task 2: 最小实现退出节点 Schedule Step 归类

**Files:**

- Modify: `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1481-1490`
- Test: `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

**Interfaces:**

- Consumes:
  - `node.groupState`
  - 当前函数内的 `removeGroupStep`
  - `deleteSteps`
  - `configturationSteps`
- Produces:
  - 可独立测试的退组步骤目标策略。
  - 退出节点的 `.syncSchedules` 进入 `removeDevice.steps`。
  - 普通或添加节点的 `.syncSchedules` 保持原 Configuration Section。
  - Schedule operation 仍由现有 `.configuration(...schedule...)` 构建。

- [ ] **Step 1: 添加最小纯路由策略**

在 `TimedSchedulerOwnerPolicy.swift` 新增：

```swift
enum TimedSchedulerGroupMemberExitStepDestination {
    case removal
    case configuration
}

enum TimedSchedulerGroupMemberExitStepPolicy {
    static func destination(
        isExitingGroup: Bool
    ) -> TimedSchedulerGroupMemberExitStepDestination {
        return isExitingGroup ? .removal : .configuration
    }
}
```

- [ ] **Step 2: 确认路由策略测试 GREEN**

Run:

```bash
scripts/check_timed_scheduler_single_owner.sh
```

Expected:

```text
TimedSchedulerOwnerPolicyTests passed
TimedSchedulerSingleOwnerContractTests passed
```

- [ ] **Step 3: 确认退组优先语义 RED**

添加 `testGroupMemberExitScheduleMigrationDoesNotBlockRemoval()` 后先运行聚焦脚本。

Expected:

```text
type 'TimedSchedulerGroupMemberExitStepPolicy' has no member 'shouldBlockGroupExit'
```

- [ ] **Step 4: 添加 non-blocking 策略**

添加 `shouldBlockGroupExit(isExitingGroup:)`，退组返回 `false`。

```swift
static func shouldBlockGroupExit(
    isExitingGroup: Bool
) -> Bool {
    return !isExitingGroup
}
```

- [ ] **Step 5: 接入 `.syncSchedules` 分支**

保持 Schedule task 为 configuration；创建 Step 后计算退组上下文并调用策略：

```swift
let isExitingGroup = node.groupState == .exitFailure
    || removeGroupStep != nil
switch TimedSchedulerGroupMemberExitStepPolicy.destination(
    isExitingGroup: isExitingGroup
) {
case .removal:
    deleteSteps.append(step)
    if !TimedSchedulerGroupMemberExitStepPolicy.shouldBlockGroupExit(
        isExitingGroup: isExitingGroup
    ) {
        nonBlockingGroupExitSteps.append(step)
    }
case .configuration:
    configturationSteps.append(step)
}
```

函数开头新增局部 `nonBlockingGroupExitSteps` 集合。组装 `removeGroupStep` 前置依赖时，从 `deleteSteps` 中排除该集合；不要移除其他既有依赖。

不要：

- 将 operation 改成 `.delete`；
- 修改 `.deleteSchedules` 分支；
- 取消所有 `removeGroupStep.relevanceStepModels`；
- 修改 `NodeSyncData.level`；
- 修改 outNodes 循环；
- 修改 Owner 解析或 Timed 判定。

- [ ] **Step 6: 运行聚焦测试并确认 GREEN**

Run:

```bash
scripts/check_timed_scheduler_single_owner.sh
```

Expected:

```text
TimedSchedulerOwnerPolicyTests passed
TimedSchedulerSingleOwnerContractTests passed
```

- [ ] **Step 7: 检查最小生产差异**

Run:

```bash
git diff -- SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- 生产代码只增加纯路由策略及 exiting/normal 的 Step 归类接线；
- 没有 outNodes、Owner、Schedule 消息或其他业务修改。

- [ ] **Step 8: GREEN 检查点**

Run:

```bash
git diff --check
git status --short
```

Expected:

- `git diff --check` 无输出并以 0 结束；
- 不执行 Git commit。

---

### Task 3: 运行 Timed 完整聚焦回归与范围检查

**Files:**

- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
- Verify: `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`
- Verify: `scripts/check_timed_scheduler_single_owner.sh`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

**Interfaces:**

- Consumes:
  - Task 1 的路由行为测试。
  - Task 2 的最小实现。
- Produces:
  - single-owner 与 persistence 两套聚焦验证结果。
  - App 与 SDK 工作区范围证据。

- [ ] **Step 1: 重跑 single-owner 聚焦合同**

Run:

```bash
scripts/check_timed_scheduler_single_owner.sh
```

Expected:

```text
TimedSchedulerOwnerPolicyTests passed
TimedSchedulerSingleOwnerContractTests passed
```

- [ ] **Step 2: 运行 Scheduler persistence 聚焦合同**

Run:

```bash
scripts/check_timed_scheduler_persistence.sh
```

Expected:

```text
SchedulerModelCachePersistenceTests passed
SchedulerModelReadCompletionTests passed
```

- [ ] **Step 3: 检查 App 工作区范围**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Expected tracked code changes:

- `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

Expected untracked/文档范围：

- 根因分析；
- 设计文档；
- 实施计划。

- [ ] **Step 4: 检查 SDK 未被本次修改**

Run:

```bash
git -C ../../nordic-sig-mesh-sdk status --short
```

Expected:

- 无本次任务引入的 SDK 修改；
- 如已有用户改动，记录并保留，不得覆盖或清理。

- [ ] **Step 5: 回归检查点**

记录：

- 每个测试命令的退出码；
- 完整 passed 文案；
- App/SDK 工作区状态；
- 不执行 Git commit。

---

### Task 4: 验证四个品牌 generic iPhoneOS 构建

**Files:**

- Verify: `SunSmart.xcworkspace`
- Verify: shared Common source target membership

**Interfaces:**

- Consumes:
  - Task 2 的共享 `SyncDevicesViewController` 改动。
- Produces:
  - SunSmart、Archipelago、SLG Sync Plus、SylSmart 的编译证据。

- [ ] **Step 1: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 2: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 4: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: 记录构建边界**

记录：

- 四个命令的退出码；
- 是否出现工程既有 warning；
- 是否出现可明确归因于本次改动的新 warning；
- generic iPhoneOS build 不代表真机 Mesh 验收。

---

### Task 5: 执行真机成功路径验收

**Files:**

- Verify logs: 用户指定的日志目录或新的 `July 31 logs` 验收目录
- Verify UI: Group Members、Sync Devices、Timed

**Interfaces:**

- Consumes:
  - 自动 Profile Group。
  - 双 Scheduler 灯具。
  - Group Target 和 Device Target 混合定时。
- Produces:
  - 成功退组后的消息、Model 缓存和 Timed 状态证据。

- [ ] **Step 1: 建立验收基线**

准备 6 条定时：

- id 0、5：Group Target + Turn On；
- id 1、3：Device Target + Turn On；
- id 2、4：Device Target + Turn Off。

确认 L2、L6 加入自动 Profile Group 后：

- id 0、1、3、5 位于 Light LC Scheduler；
- id 2、4 位于 ordinary Scheduler；
- Timed 全部为 `reason=synchronized`。

- [ ] **Step 2: 移除 L2、L6**

在 Group Members 中移除 L2、L6，并保留完整 Sync Devices 日志。

Expected Scheduler 操作：

- L2、L6：delete id 0、5；
- L2、L6：set id 1、3；
- id 1、3：先向 Light LC Scheduler 写 `noAction`；
- id 1、3：再向 ordinary Scheduler 写目标 entry；
- id 2、4：没有无关 `SchedulerActionSet`。

- [ ] **Step 3: 确认退组成功**

Expected:

- 所有相关 `SchedulerActionStatus` 成功；
- `ConfigModelSubscriptionDelete` 成功；
- `unsubscribeGroup` 完成；
- Sync Devices 对 L2、L6 显示成功。

- [ ] **Step 4: 检查 Timed**

Expected:

- id 0、5 不再把 L2、L6 当作 target；
- id 1、3 在 L2、L6 的 ordinary Owner 中匹配；
- Light LC Owner 不存在 id 1、3 残留；
- id 2、4 保持 synchronized；
- 没有因本次退组新增的待同步。

- [ ] **Step 5: 验证持久化生命周期**

依次执行：

1. 退出 Timed 再进入；
2. 退出 Space 再进入；
3. 强制结束 App；
4. 重启并进入同一 Space/Timed。

Expected:

- 六条定时状态保持；
- 不出现 `owner-model-unknown`；
- 不出现 `owner-entry-missing`；
- 不出现 `cleanup-entry-residual`。

---

### Task 6: 执行失败路径与 Manual Control 对照验收

**Files:**

- Verify logs: 真机失败注入日志
- Verify UI: Sync Devices、Timed

**Interfaces:**

- Consumes:
  - Task 5 的成功场景。
  - 可控离线或 Mesh Scheduler 失败条件。
- Produces:
  - “失败仍退组、Timed 保持真实”的产品验收证据。
  - Manual Control 不迁移的对照证据。

- [ ] **Step 1: 制造 Scheduler 迁移失败**

使用可恢复、可说明的方式让退出节点的 id 1 或 id 3 Scheduler 操作失败，例如在对应设备不可达时执行退组。

不得通过修改生产代码伪造成功。

- [ ] **Step 2: 确认退组优先语义**

Expected:

- Schedule Step 标记失败；
- 后续步骤继续；
- `unsubscribeGroup` 仍执行；
- 节点最终退出 Group；
- Sync Devices 最终显示失败，而不是成功。

- [ ] **Step 3: 确认 Timed 保持真实**

Expected:

- Timed 显示实际差异；
- `reason` 为 `owner-entry-missing`、`owner-entry-mismatch` 或 `cleanup-entry-residual` 之一；
- 不显示伪 synchronized；
- 节点恢复在线后，既有重新同步入口可以修复。

- [ ] **Step 4: 验证 Manual Control Group**

Expected:

- Device Target Turn On 在入组前、组内、退组后都使用 ordinary Scheduler；
- 退组不产生不必要的 ordinary ↔ Light LC 迁移；
- Group Target 定时仍按既有规则删除。

---

### Task 7: 完成总结与交付检查

**Files:**

- Create: `docs/` 下按执行时刻命名的 `yyMMdd_HHmm_timed_group_member_removal_scheduler_migration_implementation_summary.md`
- Verify: all planned source, test, script and document files

**Interfaces:**

- Consumes:
  - RED→GREEN 结果。
  - 两套聚焦测试结果。
  - 四品牌构建结果。
  - 真机成功/失败/Manual Control 结果。
- Produces:
  - 可审计的最终实施总结。
  - 未完成真机项的明确边界说明。

- [ ] **Step 1: 创建实施总结**

总结必须包含：

- 根因；
- 实际生产改动；
- RED 失败证据；
- GREEN 通过证据；
- persistence 回归结果；
- 四品牌构建结果；
- 真机成功路径；
- 真机失败路径；
- Manual Control 对照；
- 未验证边界；
- Git 状态；
- 未执行 commit、push 或 merge。

- [ ] **Step 2: 最终静态复核**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected:

- 无空白错误；
- 差异仅覆盖计划范围；
- 用户既有改动未被覆盖。

- [ ] **Step 3: 最终测试复核**

Run:

```bash
scripts/check_timed_scheduler_single_owner.sh
scripts/check_timed_scheduler_persistence.sh
```

Expected:

```text
TimedSchedulerOwnerPolicyTests passed
TimedSchedulerSingleOwnerContractTests passed
SchedulerModelCachePersistenceTests passed
SchedulerModelReadCompletionTests passed
```

- [ ] **Step 4: 交付状态分层**

最终报告必须分别说明：

- 静态合同：通过或失败；
- generic iPhoneOS build：各 scheme 通过或失败；
- 真机 Mesh 成功路径：通过、失败或未执行；
- 真机失败语义：通过、失败或未执行；
- App 重载生命周期：通过、失败或未执行；
- 不得用测试或 build 成功替代真机结论。

- [ ] **Step 5: Git 检查点**

不执行 Git commit。若用户后续明确授权提交，再单独提供聚焦 commit message，且不包含 Codex 相关说明。

---

## Inline Execution 顺序

按项目约束，实施时默认使用 `superpowers:executing-plans` 在当前会话 Inline Execution：

1. Task 1：建立 RED；
2. Task 2：最小 GREEN；
3. Task 3：聚焦回归；
4. Task 4：四品牌构建；
5. Task 5：真机成功路径；
6. Task 6：真机失败与 Manual Control；
7. Task 7：总结交付。

如果当前会话无法进行真机操作，Task 1–4 可完成静态与构建验证，Task 5–6 必须明确标记为“等待用户真机验收”，不得宣称整条业务链完成。
