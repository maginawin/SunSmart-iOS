# Default Transition Time 恢复评审问题修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本项目默认 Inline Execution，不授权 subagents 或 Git commit。

**Goal:** 过滤所有不能用于 SET 的 Unknown Default Transition Time，并在 OTA 恢复 SET 成功且目标匹配后持久化清除恢复目标。

**Architecture:** 延续现有纯值策略边界：`DeviceRestoreDefaultTransitionTimePolicy` 同时提供“是否需要恢复”和“成功 SET 是否可消费恢复目标”两个判断，`.all` 与 `getNeedSync()` 不增加重复分支。`Node.updateData(...)` 只负责在成功消息到达后执行匹配、清空和持久化副作用。

**Tech Stack:** Swift、UIKit App、NordicSigMeshSDK、standalone Swift focused test、shell wiring contract、Xcode workspace。

## Global Constraints

- 所有回复和文档使用简体中文；不新增或修改用户可见文案。
- 保持修改聚焦，不重构其他 Device Parameter，不格式化无关文件。
- 不修改 NordicSigMeshSDK、协议 payload、Import/Export、UI、本地化、资源或依赖版本。
- Unknown 的判定以 Transition Time raw value 低 6 位是否等于 `0x3F` 为准，必须覆盖 `0x3F`、`0x7F`、`0xBF`、`0xFF`。
- 只有成功且 SET 目标与恢复目标相同时才能清除 `restoreData.defaultTransitionTime`；失败或目标不匹配必须保留。
- 保留当前工作树全部既有改动；不吸收、不覆盖、不回滚无关文件。
- 不执行 Git commit、push 或 merge。
- iOS 构建必须直接运行 generic iPhoneOS `xcodebuild`，不用 shell 包装、日志重定向或 Simulator。
- 四个共享 App target 均需验证：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

---

## File Structure

- Modify: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`
  - 集中判断恢复目标是否 Known；提供成功 SET 与恢复目标的匹配策略。
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 在 `Node.updateData(...)` 中消费成功且匹配的 Default Transition Time 恢复目标并保存。
- Modify: `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
  - 使用字面量覆盖四种 Unknown 编码、合法边界及成功消费条件。
- Modify: `scripts/check_device_restore_transition_time.sh`
  - 保留现有行为测试和恢复链路检查，增加成功清理副作用的接线契约。
- Verify only: `SunSmart/Common/Data/Node+SyncData.swift`
  - `.all` 与 `getNeedSync()` 继续复用 `pendingTargetRawValue(...)`，不重复判断 Known。
- Verify only: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 继续把 `handle.isSuccessful` 传给 `Node.updateData(...)`。
- Verify only: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 继续以设备 Status 更新后的 raw value 严格判断 SET 是否成功。
- Modify after verification: `docs/260810_1510_light_ota_transition_time_restore_implementation_plan.md`
  - 增加本轮评审修复与验证结果附录。
- Modify after verification: `docs/260810_1546_transition_time_review_fix_design.md`
  - 标记实现结果、自动验证结果和真机验收边界。

## Task 1: 用 RED/GREEN 锁定 Unknown 过滤

**Files:**

- Modify: `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
- Modify: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`

**Interfaces:**

- Consumes: `pendingTargetRawValue(restoreTargetRawValue: UInt8?, currentRawValue: UInt8?, isSupported: Bool) -> UInt8?`。
- Produces: 只有 capability 有效、目标存在、目标为 Known 且与当前值不同时才返回目标 raw value。

- [ ] **Step 1: 增加四个 Unknown RED 用例**

在既有 `cases` 数组中追加以下字面量用例；每个用例的 `currentRawValue` 使用合法且不同的 `0x0A`，确保失败原因只能是缺少 Known 校验：

```swift
TestCase(
    name: "unknown hundred-millisecond target does not sync",
    restoreTargetRawValue: 0x3F,
    currentRawValue: 0x0A,
    isSupported: true,
    expectedRawValue: nil
),
TestCase(
    name: "unknown second target does not sync",
    restoreTargetRawValue: 0x7F,
    currentRawValue: 0x0A,
    isSupported: true,
    expectedRawValue: nil
),
TestCase(
    name: "unknown ten-second target does not sync",
    restoreTargetRawValue: 0xBF,
    currentRawValue: 0x0A,
    isSupported: true,
    expectedRawValue: nil
),
TestCase(
    name: "unknown ten-minute target does not sync",
    restoreTargetRawValue: 0xFF,
    currentRawValue: 0x0A,
    isSupported: true,
    expectedRawValue: nil
),
```

- [ ] **Step 2: 运行 focused test，确认 RED**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 测试以非零状态退出，首个 Unknown 用例报告 expected `nil`、actual `Optional(63)`；不能是脚本语法或编译环境错误。

- [ ] **Step 3: 在共享策略中增加最小 Known 判断**

把现有 guard 调整为：

```swift
guard isSupported,
      let restoreTargetRawValue,
      restoreTargetRawValue & 0x3F != 0x3F,
      restoreTargetRawValue != currentRawValue else {
    return nil
}
return restoreTargetRawValue
```

不在 `Node+SyncData.swift` 的两个调用点重复构造 `TransitionTime` 或判断 `isKnown`。

- [ ] **Step 4: 运行 focused test，确认 GREEN**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 输出 `PASS: 11 default transition time restore policy cases` 和既有 wiring contract PASS。

- [ ] **Step 5: 完成 Task 1 检查点**

Run: `git diff --check -- SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`

Expected: exit 0；不提交 Git。

## Task 2: 用 RED/GREEN 锁定成功 SET 的目标匹配

**Files:**

- Modify: `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
- Modify: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`

**Interfaces:**

- Consumes: `restoreTargetRawValue: UInt8?` 和已经由调用方确认成功的 `successfulSetRawValue: UInt8`。
- Produces: `shouldClearRestoreTarget(restoreTargetRawValue:successfulSetRawValue:) -> Bool`；只有非空目标与 SET raw value 完全相同才返回 true。

- [ ] **Step 1: 增加成功消费判断的 RED 用例**

在测试入口增加以下三个字面量断言，不能复用生产策略计算 expected：

```swift
let cleanupCases: [(String, UInt8?, UInt8, Bool)] = [
    ("matching successful SET clears restore target", 0x1E, 0x1E, true),
    ("different successful SET preserves restore target", 0x1E, 0x0A, false),
    ("missing restore target is not cleared", nil, 0x1E, false),
]

for (name, restoreTargetRawValue, successfulSetRawValue, expected) in cleanupCases {
    let actual = DeviceRestoreDefaultTransitionTimePolicy.shouldClearRestoreTarget(
        restoreTargetRawValue: restoreTargetRawValue,
        successfulSetRawValue: successfulSetRawValue
    )
    guard actual == expected else {
        fatalError("\(name): expected \(expected), got \(actual)")
    }
}

print("PASS: \(cases.count) default transition time pending-target cases")
print("PASS: \(cleanupCases.count) default transition time cleanup cases")
```

删除原来的单行总计输出，改为上述两行，分别报告 11 个 pending-target 用例和 3 个 cleanup 用例。

- [ ] **Step 2: 运行 focused test，确认 RED**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: Swift 编译失败，明确报告 `DeviceRestoreDefaultTransitionTimePolicy` 没有 `shouldClearRestoreTarget` 成员。

- [ ] **Step 3: 增加最小成功消费策略**

在同一策略类型中新增：

```swift
static func shouldClearRestoreTarget(
    restoreTargetRawValue: UInt8?,
    successfulSetRawValue: UInt8
) -> Bool {
    guard let restoreTargetRawValue else {
        return false
    }
    return restoreTargetRawValue == successfulSetRawValue
}
```

该函数不接收 `isSuccess`；失败消息已由 `Node.updateData(...)` 的入口 guard 拦截，避免在两个位置维护成功定义。

- [ ] **Step 4: 运行 focused test，确认 GREEN**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 输出 11 个 pending-target 用例 PASS、3 个 cleanup 用例 PASS，以及既有 wiring contract PASS。

- [ ] **Step 5: 完成 Task 2 检查点**

Run: `git diff --check -- SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`

Expected: exit 0；不提交 Git。

## Task 3: 接入成功后的清空与持久化

**Files:**

- Modify: `scripts/check_device_restore_transition_time.sh`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

**Interfaces:**

- Consumes: `Node.updateData(message:isSuccess:model:)` 已过滤失败消息；`GenericDefaultTransitionTimeSet.transitionTime.rawValue`；Task 2 的 `shouldClearRestoreTarget(...)`。
- Produces: 成功且目标匹配时将 `restoreData.defaultTransitionTime` 置空并通过 `Node.save()` 持久化；其他恢复字段保持不变。

- [ ] **Step 1: 先增加失败的 wiring contract**

在现有 runner 中增加限定到 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 的固定接线检查：

```sh
require_fixed \
    "case is GenericDefaultTransitionTimeSet:" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "DeviceRestoreDefaultTransitionTimePolicy.shouldClearRestoreTarget(" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "successfulSetRawValue: transitionTimeMessage.transitionTime.rawValue" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "self.restoreData?.defaultTransitionTime = nil" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "            self.restoreData?.defaultTransitionTime = nil
            save()" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

最后一个多行检查用于确认清理与 `save()` 在同一相邻分支中，不能仅依赖全文件中其他参数已有的 `save()`。

- [ ] **Step 2: 运行 focused test，确认接线 RED**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 14 个纯策略行为用例先通过，随后 wiring contract 因缺少 `case is GenericDefaultTransitionTimeSet:` 失败。

- [ ] **Step 3: 在 `Node.updateData(...)` 增加最小成功分支**

在 `LightCTLTemperatureRangeSet` 与 `SunricherVendorSet` 等状态更新分支附近加入：

```swift
case is GenericDefaultTransitionTimeSet:
    let transitionTimeMessage = message as! GenericDefaultTransitionTimeSet
    if DeviceRestoreDefaultTransitionTimePolicy.shouldClearRestoreTarget(
        restoreTargetRawValue: self.restoreData?.defaultTransitionTime?.rawValue,
        successfulSetRawValue: transitionTimeMessage.transitionTime.rawValue
    ) {
        self.restoreData?.defaultTransitionTime = nil
        save()
    }
```

不要在该分支修改 `node.defaultTransitionTime`；设备 Status 已由 SDK 更新该属性。不要清空整个 `restoreData`，因为其中可能还有其他未完成恢复项。

- [ ] **Step 4: 运行 focused test，确认接线 GREEN**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 11 个 pending-target 用例、3 个 cleanup 用例和全部 wiring contract 均 PASS。

- [ ] **Step 5: 复核失败与不匹配路径**

静态追踪以下条件：

- `isSuccess == false` 时，`Node.updateData(...)` 在 switch 前返回，字段不会清除；
- SET raw value 与恢复目标不同时，纯策略返回 false，字段不会清除也不会保存；
- 恢复目标为空时，不执行无变化保存；
- 成功匹配时只清除 `defaultTransitionTime`，其他 `NodeRestoreData` 字段不变。

- [ ] **Step 6: 完成 Task 3 检查点**

Run: `git diff --check -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift scripts/check_device_restore_transition_time.sh scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`

Expected: exit 0；不提交 Git。

## Task 4: 聚焦回归与四 target 构建

**Files:**

- Verify: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Task 1-3 的完整增量 diff。
- Produces: focused test、patch 健康度、共享策略接线和四个 generic iPhoneOS target 的静态验证证据。

- [ ] **Step 1: fresh 运行 focused test**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 11 个 pending-target 用例、3 个 cleanup 用例及全部 wiring contract PASS。

- [ ] **Step 2: 检查共享真值和范围**

确认：

- `pendingTargetRawValue(...)` 在 `Node+SyncData.swift` 中恰好出现两次，分别服务 `.all` 和 `getNeedSync()`；
- `shouldClearRestoreTarget(...)` 只在 `Node.updateData(...)` 的成功 SET 分支消费；
- 本轮未修改 SDK、Import/Export、UI、本地化、资源或依赖；
- 既有 `DeviceRestoreDefaultTransitionTimePolicy.swift` 仍属于四个共享 App target。

- [ ] **Step 3: 运行完整 patch 健康检查**

Run: `git diff --check`

Expected: exit 0。

- [ ] **Step 4: 构建 SunSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 Archipelago**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SLG Sync Plus**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: 构建 SylSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 8: 构建后 fresh verification**

依次重新执行：

- `scripts/check_device_restore_transition_time.sh`；
- `git diff --check`；
- `git status --short`。

Expected: focused test 与 diff 检查继续通过；状态列表只包含用户原有改动、本轮四个实现/测试文件以及计划和结果文档。

## Task 5: 更新文档并准备真机验收

**Files:**

- Modify: `docs/260810_1510_light_ota_transition_time_restore_implementation_plan.md`
- Modify: `docs/260810_1546_transition_time_review_fix_design.md`

**Interfaces:**

- Consumes: Task 1-4 的 fresh 验证输出。
- Produces: 可审计的实现范围、自动验证结果、未完成硬件验收和协议验收清单。

- [ ] **Step 1: 更新既有实施计划结果**

在 `docs/260810_1510_light_ota_transition_time_restore_implementation_plan.md` 末尾增加“评审问题修复”附录，写明：

- Unknown 四种 raw value 已过滤；
- 成功且匹配的 SET 会清空并保存恢复目标；
- focused test 的实际用例数和结果；
- 四 target 的实际构建结果；
- 未做真机时明确写“未验收”，不能用构建结果替代。

- [ ] **Step 2: 更新设计文档状态**

在 `docs/260810_1546_transition_time_review_fix_design.md` 增加实施状态，逐条映射两个 P2、修改文件和验证证据；如果任何构建未通过，记录准确 failure stage，不把它写成修复完成。

- [ ] **Step 3: 记录真机验收清单**

保留以下待验收项：

1. 合法 3 秒恢复发送 `0x820E + 0x1E`；
2. 收到 `0x8210 + 0x1E` 后 App 重启不再 Needs Sync；
3. 其他控制器后续修改值时 App 不再回写旧 `0x1E`；
4. Unknown 旧数据不发送 `0x820E`，也不持续 Needs Sync。

- [ ] **Step 4: 最终自检**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: PASS。

Run: `git diff --check`

Expected: exit 0。

Run: `git status --short`

Expected: 无 SDK、Pods、资源、本地化、依赖或无关模块新增改动；不提交 Git。
