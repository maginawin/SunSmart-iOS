# Emergency Fire SDK V1 Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove remaining Emergency Fire V1 naming and Scene-number semantics from the local Nordic SDK while keeping the v2 vendor protocol behavior unchanged.

**Architecture:** The SDK protocol API already uses v2 types, so the implementation is a narrow cleanup. Update the SDK Scene-number constants to expose only v2 three-state Emergency Fire names, rename the Emergency Fire vendor-message tests away from `EmergencyController`, and rewrite the historical Scene-number doc so it no longer documents the V1 start/end mapping.

**Tech Stack:** Swift, XCTest source files, Markdown docs, Xcode iPhoneOS build verification.

---

## 文件结构

- App worktree plan only:
  - Create: `docs/260616_1735_emergency_fire_sdk_v1_cleanup_implementation_plan.md`
- SDK code and docs:
  - Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Group/Group+LightLCScenes.swift`
  - Move: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift` -> `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
  - Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs/260407_1540_scene_number_usage_analysis.md`

## Task 1: Baseline Guardrails

**Files:**
- Read: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Group/Group+LightLCScenes.swift`
- Read: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift`
- Read: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs/260407_1540_scene_number_usage_analysis.md`

- [ ] **Step 1: Confirm SDK worktree state**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: no unrelated dirty files. If dirty files exist, inspect them and avoid overwriting unrelated user work.

- [ ] **Step 2: Confirm old protocol API is already gone**

Run:

```bash
rg -n "EmergencyControllerMode|EmergencyControllerSceneIndex|EmergencyControllerResendParameters|EmergencyControllerCurrentModeStatus|emergencyMode|emergencyCurrentModeStatus" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected: no output. This preserves the current conclusion that V1 protocol API is not present.

- [ ] **Step 3: Confirm old Scene constants are currently present**

Run:

```bash
rg -n "fireAlarmStartScene|fireAlarmEndScene|emergencyStartScene|emergencyEndScene" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs
```

Expected: matches in `Group+LightLCScenes.swift` and `docs/260407_1540_scene_number_usage_analysis.md`.

## Task 2: Rename Tests and Add V2 Scene Constant Coverage

**Files:**
- Move: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift` -> `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Move the test file**

Run:

```bash
mv /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift
```

Expected: the old path no longer exists and the new path exists.

- [ ] **Step 2: Rename the test class**

Replace:

```swift
final class EmergencyControllerVendorMessageTests: XCTestCase {
```

with:

```swift
final class EmergencyFireVendorMessageTests: XCTestCase {
```

- [ ] **Step 3: Add v2 Scene constant assertions**

Insert this test after the class opening brace:

```swift
    func testEmergencyFireV2ReservedSceneNumbers() {
        XCTAssertEqual(SceneNumber.emergencyFireEmergencyTriggerScene, 0xFF20)
        XCTAssertEqual(SceneNumber.emergencyFireFireTriggerScene, 0xFF21)
        XCTAssertEqual(SceneNumber.emergencyFireRestoreScene, 0xFF22)
        XCTAssertTrue(SceneNumber.emergencyFireEmergencyTriggerScene.isEventTriggerScene)
        XCTAssertTrue(SceneNumber.emergencyFireFireTriggerScene.isEventTriggerScene)
        XCTAssertTrue(SceneNumber.emergencyFireRestoreScene.isEventTriggerScene)
    }
```

Expected before Task 3: these identifiers do not compile until the new Scene constants are added. This is the intended failing test state.

## Task 3: Replace V1 Scene Constants with V2 Names

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Group/Group+LightLCScenes.swift`

- [ ] **Step 1: Replace the old start/end constants**

Replace this block:

```swift
    /// 火警开始
    static let fireAlarmStartScene: SceneNumber = 0xFF20
    /// 火警结束
    static let fireAlarmEndScene: SceneNumber = 0xFF21
    /// 应急开始
    static let emergencyStartScene: SceneNumber = 0xFF22
    /// 应急结束
    static let emergencyEndScene: SceneNumber = 0xFF23
```

with:

```swift
    /// Emergency Fire v2 EM_TRIGGER scene.
    static let emergencyFireEmergencyTriggerScene: SceneNumber = 0xFF20
    /// Emergency Fire v2 FIRE_TRIGGER scene.
    static let emergencyFireFireTriggerScene: SceneNumber = 0xFF21
    /// Emergency Fire v2 RESTORE scene.
    static let emergencyFireRestoreScene: SceneNumber = 0xFF22
```

Expected: `0xFF23` is no longer assigned to an Emergency Fire Scene constant.

- [ ] **Step 2: Search for old constant usage in SDK**

Run:

```bash
rg -n "fireAlarmStartScene|fireAlarmEndScene|emergencyStartScene|emergencyEndScene" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected: no output.

## Task 4: Rewrite Historical Scene-Number Documentation

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs/260407_1540_scene_number_usage_analysis.md`

- [ ] **Step 1: Update the document header**

Replace the current recent-update and summary lines with:

```markdown
> 最近更新：2026-06-16（Emergency Fire v2 三状态语义清理）
> 调查范围：`Sources/NordicSigMeshSDK/`（含 `MeshLib/` 高层封装与 `nRFMeshProvision/` 二次开发协议栈）
> 结论摘要：项目**确实**使用固件场景号承载多个非"通用场景"的业务功能，并且**预留了固定的场景号段**给灯光控制（LightLC）、快照（Snapshot）以及事件触发功能。Emergency Fire 已切换为 v2 三状态语义，不再使用 V1 start/end 四段语义。
```

- [ ] **Step 2: Update the allocated event-trigger table**

Replace the event-trigger allocation table with:

```markdown
事件触发段（`0xFF20 ~ 0xFF3F`）当前已分配的场景号：

| 场景号 | 常量名 | 用途 |
|---|---|---|
| `0xFF20` | `emergencyFireEmergencyTriggerScene` | Emergency Fire v2 EM_TRIGGER |
| `0xFF21` | `emergencyFireFireTriggerScene` | Emergency Fire v2 FIRE_TRIGGER |
| `0xFF22` | `emergencyFireRestoreScene` | Emergency Fire v2 RESTORE |
| `0xFF23 ~ 0xFF3F` | （保留） | 后续新增的事件触发类场景 |
```

- [ ] **Step 3: Update the code sample**

Replace the event-trigger code sample with:

```swift
public extension SceneNumber {
    /// 事件触发场景段起始（含），共 32 槽
    static let minEventTriggerScene: SceneNumber = 0xFF20
    /// 事件触发场景段结束（含）
    static let maxEventTriggerScene: SceneNumber = 0xFF3F

    /// Emergency Fire v2 EM_TRIGGER scene.
    static let emergencyFireEmergencyTriggerScene: SceneNumber = 0xFF20
    /// Emergency Fire v2 FIRE_TRIGGER scene.
    static let emergencyFireFireTriggerScene: SceneNumber = 0xFF21
    /// Emergency Fire v2 RESTORE scene.
    static let emergencyFireRestoreScene: SceneNumber = 0xFF22
}

public extension SceneNumber {
    /// 是否事件触发场景（Emergency Fire / 后续扩展）
    var isEventTriggerScene: Bool {
        return (SceneNumber.minEventTriggerScene...SceneNumber.maxEventTriggerScene).contains(self)
    }
}
```

- [ ] **Step 4: Update the Emergency Fire section**

Replace section 4 with:

```markdown
### 4. 事件触发场景（保留段 `0xFF20 ~ 0xFF3F`）

- **场景号**：`SceneNumber.minEventTriggerScene ~ maxEventTriggerScene`，共 32 个槽位。
- **当前已分配**：
  - `0xFF20` `emergencyFireEmergencyTriggerScene` —— Emergency Fire v2 EM_TRIGGER
  - `0xFF21` `emergencyFireFireTriggerScene` —— Emergency Fire v2 FIRE_TRIGGER
  - `0xFF22` `emergencyFireRestoreScene` —— Emergency Fire v2 RESTORE
- **保留余量**：`0xFF23 ~ 0xFF3F`，供后续新增事件触发类场景使用。
- **Emergency Fire v2 约束**：真实动作配置以 vendor `0x4D/0x07` action config 为准。这里的 Scene 常量只表达 v2 状态与特殊场景隔离，不代表旧版 publication + stop scene 流程。
- **段间隔**：与 LightLC 段（结束于 `0xFF10`）之间留有 `0xFF11 ~ 0xFF1F` 共 16 槽的空隙，预留给 LightLC 未来扩展。
- **路由判定**：因为 `isSpecialScene` 已经覆盖整个 `≥ 0xFF00` 段，事件触发场景在收到 `SceneStatus / SceneRegisterStatus` 时同样会被自动过滤，不会注册成 `meshNetwork.scenes` 中的用户场景。
```

- [ ] **Step 5: Remove stale planning wording**

Delete the old planning list under the event-trigger section. The v2 constants are now implemented, so the document must not say the event-trigger segment is only "规划中".

- [ ] **Step 6: Update conclusion bullets**

Replace old conclusion mentions of "火警开始 / 火警结束 / 应急开始 / 应急结束" and "`0xFF20 ~ 0xFF23` 给火警 / 应急的 start/end" with v2 wording:

```markdown
   - 事件触发场景（Emergency Fire v2 的 EM_TRIGGER / FIRE_TRIGGER / RESTORE）
```

and:

```markdown
   - `0xFF20 ~ 0xFF3F` —— 事件触发场景段（32 槽，当前分配 `0xFF20 ~ 0xFF22` 给 Emergency Fire v2 三状态，`0xFF23 ~ 0xFF3F` 保留）
```

## Task 5: Verification

**Files:**
- Verify: SDK source, SDK tests, SDK docs, App build integration.

- [ ] **Step 1: Verify old protocol API names are absent**

Run:

```bash
rg -n "EmergencyControllerMode|EmergencyControllerSceneIndex|EmergencyControllerResendParameters|EmergencyControllerCurrentModeStatus|emergencyMode|emergencyCurrentModeStatus" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected: no output.

- [ ] **Step 2: Verify old Scene constants are absent**

Run:

```bash
rg -n "fireAlarmStartScene|fireAlarmEndScene|emergencyStartScene|emergencyEndScene" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs
```

Expected: no output.

- [ ] **Step 3: Verify `0xFF23` is not assigned to Emergency Fire**

Run:

```bash
rg -n "0xFF23|FF23" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/docs
```

Expected: only documentation statements that `0xFF23...0xFF3F` are reserved; no SDK constant assigning `0xFF23` to Emergency Fire.

- [ ] **Step 4: Build SDK for iPhoneOS**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Build App for iPhoneOS**

Run from `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire`:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`, unless blocked by an unrelated existing App issue. If blocked, capture the first unrelated error and do not broaden this cleanup.

- [ ] **Step 6: Check whitespace**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
git diff --check
```

Expected: no output.

## Task 6: Commit

**Files:**
- Commit SDK changes in `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`.
- Commit this plan document in `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire`.

- [ ] **Step 1: Commit App plan doc**

Run:

```bash
git add docs/260616_1735_emergency_fire_sdk_v1_cleanup_implementation_plan.md
git commit -m "docs: plan emergency fire sdk v1 cleanup"
```

Expected: one App-repo docs commit.

- [ ] **Step 2: Commit SDK cleanup**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Group/Group+LightLCScenes.swift Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift docs/260407_1540_scene_number_usage_analysis.md
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add -u Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "refactor: remove emergency fire v1 scene semantics"
```

Expected: one SDK commit containing only the Scene constant, test rename, and doc updates.
