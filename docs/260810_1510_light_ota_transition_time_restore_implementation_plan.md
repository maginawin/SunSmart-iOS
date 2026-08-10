# Light OTA Transition Time Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. This project requires Inline Execution and does not authorize subagents or Git commits.

**Goal:** BLE OTA 触发设备重置并重新添加后，把升级前缓存的 Default Transition Time 写回新设备，并让失败状态和后续 Sync 使用同一真值。

**Architecture:** 在 App 通用恢复层增加一个纯值策略，统一判断“恢复目标是否仍待同步”；旧 Node 的值写入 `NodeRestoreData`，`.all` 同步规划和 `getNeedSync()` 都复用该策略。现有 `DeviceParameterType` 继续负责 acknowledged SET、Status 更新和严格成功判断。

**Tech Stack:** Swift、UIKit App、NordicSigMeshSDK、Xcode workspace、standalone Swift focused test、shell contract。

## Global Constraints

- 所有回复和文档使用简体中文；不新增用户可见文案。
- 不修改 NordicSigMeshSDK、协议 payload、UI、本地化、资源或依赖版本。
- 公共 App 源码必须覆盖 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 保持改动聚焦，不重构其他 Device Parameter。
- 不执行 Git commit、push 或 merge。
- 构建必须直接使用 generic iPhoneOS `xcodebuild`，不用 shell 包装、日志重定向或 Simulator。

---

## File Structure

- Create: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`
  - 只负责基于恢复目标、设备当前值和有效能力计算待写回 raw value。
- Create: `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
  - 使用字面量覆盖 mismatch、equal、nil target 和 unsupported 四类行为。
- Create: `scripts/check_device_restore_transition_time.sh`
  - 编译并运行真实策略文件，同时验证恢复链路接线契约。
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 把旧 Node 的 Transition Time 写入 `NodeRestoreData`。
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - `.all` 生成 Transition Time 恢复项；`getNeedSync()` 使用相同策略。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - 把纯策略文件加入 Common/Data 分组和四个 App target。
- Modify: `docs/260810_1448_light_ota_transition_time_restore_analysis_plan.md`
  - 在实施后补充实现状态与验证边界。

## Task 1: 建立 RED focused test

**Files:**

- Create: `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
- Create: `scripts/check_device_restore_transition_time.sh`

**Interfaces:**

- Consumes: 尚不存在的 `DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(restoreTargetRawValue:currentRawValue:isSupported:)`。
- Produces: 可重复运行的 focused test/contract 命令。

- [ ] **Step 1: 写行为测试**

测试使用以下字面量：

- 旧值 3 秒：`0x1E`；
- 新设备默认 1 秒：`0x0A`；
- mismatch 且支持：返回 `0x1E`；
- current 为空且支持：返回 `0x1E`；
- current 已为 `0x1E`：返回 `nil`；
- restore target 为空：返回 `nil`；
- 不支持：返回 `nil`。

测试入口采用 `@main`，任何断言失败必须以非零退出；全部通过时输出用例数量。

- [ ] **Step 2: 写 focused runner**

Runner 直接编译生产策略文件和测试文件：

```bash
xcrun swiftc \
  SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift \
  scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift \
  -o /tmp/device_restore_transition_time_policy_tests
/tmp/device_restore_transition_time_policy_tests
```

随后使用固定字符串检查以下接线：

- `oldNode.defaultTransitionTime` 进入 `NodeRestoreData`；
- `.all` 调用策略并生成 `.defaultTransitionTime`；
- `getNeedSync()` 调用同一策略；
- 既有消息仍为 `GenericDefaultTransitionTimeSet`；
- 既有成功判断仍比较 `rawValue`。

- [ ] **Step 3: 验证 RED**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: FAIL，原因是生产策略文件/符号尚不存在，而不是脚本语法错误。

## Task 2: 实现最小纯策略并纳入四 target

**Files:**

- Create: `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `UInt8?` 的恢复目标和当前值、Bool 有效能力。
- Produces: `pendingTargetRawValue(...) -> UInt8?`；非空表示必须写回的目标 raw value。

- [ ] **Step 1: 实现最小策略**

```swift
enum DeviceRestoreDefaultTransitionTimePolicy {
    static func pendingTargetRawValue(
        restoreTargetRawValue: UInt8?,
        currentRawValue: UInt8?,
        isSupported: Bool
    ) -> UInt8? {
        guard isSupported,
              let restoreTargetRawValue,
              restoreTargetRawValue != currentRawValue else {
            return nil
        }
        return restoreTargetRawValue
    }
}
```

- [ ] **Step 2: 加入四个 App target**

在 Xcode project 中新增一个 PBXFileReference、四个 PBXBuildFile，并分别加入以下 Sources phase：

- `C88553B12DE6B44C00C8B688`
- `C886E0012E30DE4900D0C3A6`
- `C896B9A02A930BA800217512`
- `C8BB65AF2ED3F056000C63EE`

同时把文件引用加入 Common/Data 分组。

- [ ] **Step 3: 运行 focused test**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: 纯策略行为用例通过，但接线检查仍因生产恢复链路未修改而 FAIL。

## Task 3: 接入恢复快照、同步规划和状态真值

**Files:**

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

**Interfaces:**

- Consumes: `oldNode.defaultTransitionTime?.rawValue`、新 Node 当前 raw value、`supportDefaultTransitionTime`。
- Produces: `NodeRestoreData.defaultTransitionTime`、一个聚合后的 `.deviceParameterTypes`、一致的 `needSync` 结果。

- [ ] **Step 1: 保存旧值到恢复快照**

创建 `NodeRestoreData` 时传入旧 Node 的 `defaultTransitionTime`，保留原 `TransitionTime/rawValue`，不使用 UI 默认 1 秒。

- [ ] **Step 2: 调整 `.all` 参数聚合**

把 `deviceParameterTypes` 提到 Vendor 条件之外：

- PWM、Rated Power、Motion Sensitivity Range、Photosensor Exception 仍受原 Vendor 条件约束；
- Transition Time 使用策略，能力值传 `supportDefaultTransitionTime`；
- 策略返回 raw value 时构造 `TransitionTime(rawValue:)` 并追加 `.defaultTransitionTime`；
- 全部参数完成后只追加一个非空 `.deviceParameterTypes`。

- [ ] **Step 3: 补齐 `getNeedSync()`**

用相同策略和同样的三个输入判断 Transition Time；策略返回非空时返回 `true`。

- [ ] **Step 4: 验证 GREEN**

Run: `scripts/check_device_restore_transition_time.sh`

Expected: PASS，7 个策略行为用例与全部接线检查通过。

- [ ] **Step 5: 检查 patch 健康度**

Run: `git diff --check`

Expected: exit 0。

## Task 4: 构建与范围验证

**Files:**

- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: 所有修改的 Swift 文件和脚本。

**Interfaces:**

- Consumes: Task 1-3 的完整 diff。
- Produces: 四 target generic iPhoneOS 编译证据与最终验收边界。

- [ ] **Step 1: 验证 project membership**

确认策略文件恰好有一个 FileReference、四个 Sources membership，且未进入 Pods 或 SDK target。

- [ ] **Step 2: 构建 SunSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 构建 Archipelago**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 SLG Sync Plus**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 SylSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 最终 fresh verification**

重新执行：

- `scripts/check_device_restore_transition_time.sh`
- `git diff --check`
- `git status --short`

检查未出现 SDK、Pods、资源、本地化或无关文件改动。

## Task 5: 更新文档并交付

**Files:**

- Modify: `docs/260810_1448_light_ota_transition_time_restore_analysis_plan.md`

- [ ] **Step 1: 记录实施结果**

写明已修改的链路、focused test 数量、四 target 构建结果和未完成的真机验收。

- [ ] **Step 2: 最终自检**

逐项核对已批准方案 A：

- 旧值进入恢复快照；
- mismatch 生成 acknowledged SET；
- equal/nil/unsupported 不发送；
- Status raw value 决定成功；
- 失败保持 Needs Sync；
- SDK、UI、云端和其他参数行为未改。

- [ ] **Step 3: 不提交 Git**

保留工作区改动，向用户交付文件清单、验证证据和真机验收边界。

## 评审问题修复附录（2026-08-10）

### 实施结果

- `DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(...)` 已过滤低 6 位为 `0x3F` 的 Unknown raw value，覆盖 `0x3F`、`0x7F`、`0xBF`、`0xFF`；
- `.all` 与 `getNeedSync()` 继续共享同一策略，因此 Unknown 不生成 SET，也不持续触发 Needs Sync；
- 新增成功 SET 与恢复目标的严格 raw value 匹配策略；
- `Node.updateData(...)` 在成功且目标匹配时只清空 `restoreData.defaultTransitionTime` 并调用 `save()`；
- 失败、空目标或目标不匹配时保留恢复目标；
- 未修改 SDK、Import/Export、UI、本地化、资源、依赖或其他 Device Parameter 行为。

### TDD 证据

- Unknown RED：`0x3F` 用例先失败，实际错误为 expected `nil`、got `Optional(63)`；
- Unknown GREEN：11 个 pending-target 用例通过；
- Cleanup RED：测试先因缺少 `shouldClearRestoreTarget` 成员编译失败；
- Cleanup GREEN：3 个 cleanup 用例通过；
- Wiring RED：14 个行为用例通过后，接线检查因缺少 `GenericDefaultTransitionTimeSet` 分支失败；
- Wiring GREEN：成功清理与 `save()` 接线检查通过。

### 自动验证结果

- `scripts/check_device_restore_transition_time.sh`：11 个 pending-target 用例、3 个 cleanup 用例和 wiring contract 全部通过；
- `git diff --check`：通过；
- `SunSmart` generic iPhoneOS build：exit 0，`BUILD SUCCEEDED`；
- `Archipelago` generic iPhoneOS build：exit 0，`BUILD SUCCEEDED`；
- `SLG Sync Plus` generic iPhoneOS build：exit 0，`BUILD SUCCEEDED`；
- `SylSmart` generic iPhoneOS build：exit 0，`BUILD SUCCEEDED`。

### 未验收边界

尚未完成真机、真实 BLE/Mesh 和固件验收。以下结论不能由 focused test 或编译替代：

1. 3 秒恢复真实发送 `0x820E + 0x1E`；
2. 收到 `0x8210 + 0x1E` 后重启 App 不再显示 Needs Sync；
3. 其他控制器后续修改 Transition Time 时 App 不再回写旧 `0x1E`；
4. 注入 Unknown 旧恢复数据时不发送 `0x820E`，也不持续显示 Needs Sync。
