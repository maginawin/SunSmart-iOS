# Emergency Fire App v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Project preference is Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 App 中 Emergency Fire Controller 从旧 v1.3.6 工作模式/场景模型迁移到 v2 `enable + 3 state action config`，形成可保存、可同步、可显示的最小闭环，并为后续完整 action editor 留出清晰边界。

**Architecture:** SDK 已只保留 v2 `EmergencyFire*` API，因此 App 层不再兼容旧 vendor API。App 本地配置继续复用 `DeviceEmerFireData.configurationData` JSON 字段，通过 `Codable` 默认值和派生 action config 完成旧配置迁移；同步层统一生成 `0x4D/0x05`、`0x03`、`0x06`、`0x07` vendor 消息。UI 第一阶段不重做全量 12 种动作编辑器，而是复用现有“关联组 + 亮度/恢复延迟/发送次数”界面生成默认 action。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK v2 vendor messages, SQLite JSON configuration.

---

## Scope

本轮做：

1. App v2 配置/同步模型。
2. 最小 UI 闭环：现有编辑页可保存 v2 配置，监控页可读取 v2 综合状态。
3. action_type 扩展：先在模型层支持 12 种 action，UI 先暴露默认动作生成，不做完整高级编辑器。
4. 迁移与清理：旧 JSON 字段可解码到 v2，旧 SDK API 调用清零。

本轮不做：

1. 新增完整 action_type 高级编辑 UI。
2. 重新设计页面视觉。
3. 兼容旧固件 vendor wire format。

## v2 Desired Model

保留用户已有概念：

- `powerLossSettings` 对应 v2 `state_idx=0` Emergency Trigger。
- `fireAlarmSettings` 对应 v2 `state_idx=1` Fire Trigger。
- 新增 `restoreSettings` 或派生 restore action，对应 v2 `state_idx=2` Restore。
- `enabled` 取代旧 `workMode` 下发语义；旧 `workMode != allDisabled` 迁移为 `enabled=true`，旧 `allDisabled` 迁移为 `enabled=false`。

最小 UI 生成动作：

| state | 默认 action | stage1_target | stage2_target | params |
|---|---|---|---|---|
| Emergency Trigger | `LIGHTNESS_SET` | 内部 publish group | 内部 publish group | `triggerBrightness` 转 lightness |
| Fire Trigger | `HSL_SET` | 内部 publish group | 内部 publish group | 红色 `hue=0,saturation=0xFFFF`，lightness 使用 UI 亮度 |
| Restore | `CTL_SET` | 内部 publish group | 内部 publish group | `lightness=0x8000,temperature=6500,deltaUV=0` |

如果某个 state 没有关联组，生成 `INVALID` action，避免设备默认静默状态不透明。

## Task 1: App v2 配置模型

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`

- [x] **Step 1: Replace old vendor-mode mapping**

Remove `EmergencyFireControllerWorkMode.vendorMode`; add `EmergencyFireControllerConfiguration.enabled`.

Expected:
- Old App code no longer references `EmergencyControllerMode`.
- `allDisabled` remains as local UI compatibility state, but it only maps to `enabled=false`.

- [x] **Step 2: Add v2 state/action model helpers**

Add app-side helpers to derive:
- `EmergencyFireStateIndex` for power loss, fire alarm, restore.
- `EmergencyFireResendParameters` per state.
- `EmergencyFireActionConfig` per state.

Expected:
- No UI caller needs to know v2 byte layout.
- Derived configs use SDK `EmergencyFireActionConfig`.

- [x] **Step 3: Make Codable migration explicit**

Keep decoding old JSON fields:
- `workMode`
- `powerLossSettings`
- `fireAlarmSettings`

Add defaults for new v2 fields so existing saved configs load without crash.

Expected:
- Existing database rows with old `configurationData` decode.
- Imported config JSON without new fields decodes.

## Task 2: v2 同步下发

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`

- [x] **Step 1: Replace old `.emergencyMode`**

Use:
- `SunricherVendorSet(function: .emergencyEnabled(configuration.enabled))`

Expected:
- No App source references `.emergencyMode`.

- [x] **Step 2: Replace old aggregate resend**

Generate one `EmergencyFireResendParameters` per v2 state:
- Emergency Trigger
- Fire Trigger
- Restore

Expected:
- No App source references `EmergencyControllerResendParameters`.
- Sync page can show separate resend tasks if needed.

- [x] **Step 3: Add `0x07` action config sync tasks**

Generate `SunricherVendorSet(function: .emergencyActionConfig(...))` for each state whose derived config changed or during full sync.

Expected:
- A newly configured device receives at least one non-INVALID action config.
- Disabled states receive INVALID action config.

- [x] **Step 4: Keep publication/subscription cleanup focused**

Do not remove existing internal publish group, Scene Client publication, LC Client publication, or cleanup logic in this task unless it directly blocks v2 compile.

Expected:
- Existing group cleanup behavior remains intact.

## Task 3: 最小 UI 闭环

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`

- [x] **Step 1: Monitor status GET uses v2 comprehensive status**

Replace:
- `SunricherVendorGet(function: .emergencyCurrentModeStatus)`

With:
- `SunricherVendorGet(function: .emergencyComprehensiveStatus)`

Expected:
- Monitor display can map `enabled/fireActive/emergencyActive/everTriggered`.

- [x] **Step 2: Keep existing edit UI but save v2 intent**

Existing toggles and steppers continue to render, but saving writes v2-derived configuration and marks the device unsynced.

Expected:
- User can create/edit an EFC without seeing an incomplete action editor.
- Saved config produces v2 sync tasks.

- [x] **Step 3: Add readable action summary text**

Where the UI currently shows brightness/group/restore values, keep those rows and do not expose raw `action_type` unless advanced editing is implemented later.

Expected:
- UI remains usable and does not show protocol jargon.

## Task 4: action_type 扩展边界

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- Create only if needed: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireActionPreset.swift`

- [x] **Step 1: Add App-level action preset enum**

Represent all 12 SDK action types plus invalid, but default UI only uses lightness/hsl/ctl/invalid.

Expected:
- Future UI can switch from preset-derived defaults to explicit user-selected action without changing sync plumbing.

- [x] **Step 2: Convert presets to SDK actions**

Provide one conversion function from App preset to `EmergencyFireAction`.

Expected:
- No duplicated action mapping in UI or sync planner.

## Task 5: 迁移与清理

**Files:**
- All FireAlarm Swift files under `SunSmart/Main/Device/Device1.5/FireAlarm/`

- [x] **Step 1: Remove old SDK API references**

Search and clear:
- `EmergencyControllerMode`
- `EmergencyControllerSceneIndex`
- `EmergencyControllerResendParameters`
- `EmergencyControllerCurrentModeStatus`
- `.emergencyCurrentModeStatus`
- `.emergencyMode`

Expected:
- Search returns no App source references to removed SDK symbols.

- [x] **Step 2: Validate SDK and App compile surface**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- SDK build succeeds.

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- If Pods config is still missing, record the Pods blocker.
- If Pods config is present, App should compile past Emergency Fire old API removal.

## Implementation Result

- App v2 配置模型已接入 `enabled + Emergency/Fire/Restore state`。
- 同步任务已改为下发 `emergencyEnabled`、逐 state `emergencyResendParameters`、逐 state `emergencyActionConfig`、`emergencyRestoreDelay`。
- Monitor 页已改为读取 v2 `emergencyComprehensiveStatus`。
- action_type 模型层已覆盖 SDK v2 的 12 种 action 和 `invalid`；当前 UI 仍使用默认派生动作，不暴露高级 action editor。
- 旧 SDK FireAlarm 调用精确搜索已无命中。
- App iPhoneOS 构建已通过。

## Known Verification Limit

The App project currently has no unit test target. `swift test --filter EmergencyControllerVendorMessageTests` in the SDK is blocked by SwiftPM/macOS compiling SDK sources that import `UIKit`. Therefore this implementation relies on:

1. SDK iPhoneOS build for SDK compile verification.
2. SDK wire-format test source as behavior documentation.
3. App iPhoneOS build when Pods configuration is available.
4. Source search for removed old API references.
