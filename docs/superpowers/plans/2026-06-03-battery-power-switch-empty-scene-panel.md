# Battery Power Switch Empty Scene Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 battery power switch 从 brightness panel 切换到未配置 scene 的 scene panel 后，前 4 个物理按键仍按旧 brightness 配置控制 group 的问题。

**Architecture:** 在 `PJEightKeySwitchData` 的按键配置生成层修复，保证 scene panel 前 4 个 click key 始终下发配置：有 scene 时下发 `.sceneRecall`，无 scene 时下发 `.disabled`。同步、添加、绑定、恢复流程都复用同一个配置生成入口，因此不改同步页面、不改资源、不改 target 配置。

**Tech Stack:** Swift, UIKit app code, NordicSigMeshSDK vendor message types, Xcode workspace build verification.

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 责任：生成 battery power switch 的目标 key configuration 列表。
  - 本次只修改 `sceneRecallConfigurations(address:appKeyIndex:)`，不调整 UI、数据库、资源、target 配置或同步控制器。

无新增文件。当前主工程没有测试 target，本计划不新增 XCTest target，避免修改 `SunSmart.xcodeproj/project.pbxproj` 带来无关风险。

## Task 1: 显式禁用未配置 Scene 的前 4 个按键

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 读取当前方法，确认旧行为**

Run:

```bash
sed -n '300,322p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected: 看到 `sceneRecallConfigurations(address:appKeyIndex:)` 使用 `compactMap`，`sceneNumber == nil` 时 `return nil`，因此未配置 scene 的按键不会生成任何 key config。

- [ ] **Step 2: 修改 scene key config 生成逻辑**

Replace `sceneRecallConfigurations(address:appKeyIndex:)` with:

```swift
func sceneRecallConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
    let sceneNumbers = [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber]
    return sceneNumbers.enumerated().map { index, sceneNumber in
        guard let sceneNumber else {
            return BatteryPowerSwitchKeyConfiguration(
                button: UInt8(index),
                trigger: .click,
                type: .disabled,
                address: address,
                appKeyIndex: appKeyIndex
            )
        }
        return BatteryPowerSwitchKeyConfiguration(
            button: UInt8(index),
            trigger: .click,
            type: .sceneRecall,
            sceneId: sceneNumber,
            address: address,
            appKeyIndex: appKeyIndex
        )
    }
}
```

Why: `map` guarantees button 0...3 each has a new click configuration. `.disabled` overwrites stale `.lightnessSet` actions on the device when the corresponding scene is empty.

- [ ] **Step 3: 静态核对生成数量和 action type**

Run:

```bash
sed -n '300,330p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

- 方法使用 `map`，不是 `compactMap`。
- `guard let sceneNumber else` 分支返回 `type: .disabled`。
- 非空 scene 分支仍返回 `type: .sceneRecall`。
- button index 仍来自 `enumerated()`，保持 0...3。

- [ ] **Step 4: 确认 brightness panel 逻辑没有被改动**

Run:

```bash
sed -n '322,338p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected: `brightnessConfigurations(address:appKeyIndex:)` 仍对 `[100, 75, 50, 25]` 生成 `.lightnessSet`，button index 仍是 0...3。

- [ ] **Step 5: 提交业务修复**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "fix: disable empty battery switch scene keys"
```

Expected: diff 只包含 `PJEightKeySwitchData.swift` 中 `sceneRecallConfigurations` 的最小修改。

## Task 2: 构建验证和行为核对

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Verify: `docs/superpowers/specs/2026-06-03-battery-power-switch-empty-scene-panel-design.md`

- [ ] **Step 1: 运行 iPhoneOS Debug 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds。不要使用 shell 包装、不要重定向日志、不要用 Simulator 做校验。

- [ ] **Step 2: 核对修复覆盖 spec 验收标准**

Inspect `PJEightKeySwitchData.swift` and confirm:

```swift
// scene8Key + nil scene -> disabled key config
BatteryPowerSwitchKeyConfiguration(
    button: UInt8(index),
    trigger: .click,
    type: .disabled,
    address: address,
    appKeyIndex: appKeyIndex
)
```

Expected:

- 从 brightness panel 切到 empty scene panel 时，button 0...3 会收到 disabled 配置，旧 `.lightnessSet` 会被覆盖。
- 配置了 scene 的 key 仍收到 `.sceneRecall`。
- brightness panel 的 `.lightnessSet` 生成逻辑不变。
- dimming、ON、AUTO、OFF 逻辑不变。
- 同步成功/失败标记仍走现有 `SyncDevicesViewController` 流程。

- [ ] **Step 3: 查看最终工作区状态**

Run:

```bash
git status --short
git log --oneline -3
```

Expected:

- `git status --short` 没有未提交业务代码。
- 最近提交包含 spec 文档提交和业务修复提交。

