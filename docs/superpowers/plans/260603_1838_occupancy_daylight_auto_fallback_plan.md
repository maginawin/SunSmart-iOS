# Occupancy Daylight Auto Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `.occupancy_daylight` / `.vacancy_daylight` 未校准时，重新 SAVE / Sync profile 后响应 Auto 命令进入 profile high-end trim 亮度。

**Architecture:** 只修改 profile 同步数据生成层，不修改任何 Auto 命令入口。由于 `.occupancy_daylight` / `.vacancy_daylight` 的 `LightData.levels` 不包含 `.taskLevel`，实际修复点是 `autoMinValue` 未校准 fallback 分支：把 LC On 从固定 100 改为 `groupLightData.highEndTrim`，并保持已校准分支由 auto-min 或 0 回写。

**Tech Stack:** Swift, iOS, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - Responsibility: 生成节点加入 group 或保存 group profile 时需要同步的 `ProfileType` 列表。
  - Scope: 只改 `getNodeLightDataSyncProfiles(group:groupLightData:lightLCProperty:forceFullProfileSync:)` 中 `.autoMinValue` 的未校准 occupancy fallback 分支。
- Read-only reference: `SunSmart/Main/Profile/Model/Profile.swift`
  - Responsibility: 定义各 profile 的 `LightData.levels`。`.occupancy_daylight` / `.vacancy_daylight` 通过 `.autoMinValue` 分支处理未校准 fallback，纯 `.daylight` 通过 `.taskLevel` 分支处理。
- Read-only reference: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - Responsibility: 组页 Auto 命令入口。本计划不修改该文件。

## Task 1: 修改 Occupancy Daylight 未校准 Auto fallback

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift:1259-1271`

- [ ] **Step 1: 记录当前未校准 fallback 分支**

确认当前 `.autoMinValue` 未校准 occupancy 分支仍是固定 `100 / 50 / 0`：

```swift
}else if occupancyType { // 日光感应并且存在占用感应profile，未校准时阶段启用默认百分比调光
    let occupancyLevel = 100
    let vacantLevel = 50
    let standbyLevel = 0
    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: occupancyLevel) {
        syncProfile.append(.occupancyLevel(value: occupancyLevel))
    }
    if forceFullProfileSync || lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: vacantLevel) {
        syncProfile.append(.vacantLevel(value: vacantLevel))
    }
    if forceFullProfileSync || lightLCProperty.lightnessStandby == nil || lightLCProperty.lightnessStandby! != Node.getLightness(lightness100: standbyLevel) {
        syncProfile.append(.standbyLevel(value: standbyLevel))
    }
}
```

Run: `nl -ba SunSmart/Common/Data/Node+SyncData.swift | sed -n '1248,1274p'`

Expected: 能看到上述固定 fallback 分支。

- [ ] **Step 2: 实现 high-end trim fallback**

将未校准 occupancy fallback 分支替换为：

```swift
}else if occupancyType { // 日光感应并且存在占用感应profile，未校准时阶段启用默认百分比调光
    let occupancyLevel = daylightType ? groupLightData.highEndTrim : 100
    let vacantLevel = 50
    let standbyLevel = 0
    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: occupancyLevel) {
        syncProfile.append(.occupancyLevel(value: occupancyLevel))
    }
    if forceFullProfileSync || lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: vacantLevel) {
        syncProfile.append(.vacantLevel(value: vacantLevel))
    }
    if forceFullProfileSync || lightLCProperty.lightnessStandby == nil || lightLCProperty.lightnessStandby! != Node.getLightness(lightness100: standbyLevel) {
        syncProfile.append(.standbyLevel(value: standbyLevel))
    }
}
```

Rationale:

- `.occupancy_daylight` / `.vacancy_daylight` 满足 `daylightType && occupancyType`，未校准时 LC On 写入 high-end trim。
- 普通 `.occupancy` / `.vacancy` 不满足 `daylightType`，仍保持固定 100 / 50 / 0 行为。
- `.daylight` 不满足 `occupancyType`，仍使用已完成的 `.taskLevel` high-end trim fallback。
- 已校准 daylight profiles 不进入该分支，继续由上面的 `daylightEnabled` 分支把 On/Prolong/Standby 写回 auto-min 或 0。

- [ ] **Step 3: 源码检查修改范围**

Run: `git diff -- SunSmart/Common/Data/Node+SyncData.swift`

Expected:

- 只有 `let occupancyLevel = 100` 变为 `let occupancyLevel = daylightType ? groupLightData.highEndTrim : 100`。
- 没有修改 `GroupViewController.swift`。
- 没有新增 Auth、资源、target 配置或依赖。

## Task 2: 验证边界和构建

**Files:**
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: 检查 `.occupancyLevel(value:)` 的消息落点**

Run: `nl -ba SunSmart/Common/Data/Node+MessageHandles.swift | sed -n '361,364p'`

Expected:

```swift
case .occupancyLevel(let value):
    let lightness = Node.getLightness(lightness100: value)
    messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlLightnessOn, value: .perceivedLightness(lightness)), model: lightLCSetupModel))
```

- [ ] **Step 2: 检查纯 `.daylight` fallback 仍保留**

Run: `nl -ba SunSmart/Common/Data/Node+SyncData.swift | sed -n '1274,1284p'`

Expected:

```swift
case .taskLevel(let level):
    if groupProfile.type == .daylight && !daylightEnabled {
        let fallbackLevel = groupLightData.highEndTrim
```

- [ ] **Step 3: 检查 Auto 命令入口没有变化**

Run: `rg -n "LightLCLightOnOffSetUnacknowledged\\(true" SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Device1.5/FireAlarm`

Expected:

- `GroupViewController.autoBtnAction` 仍发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)`。
- 遥控器和 EFC Auto 相关命令入口仍存在，且本任务没有改动这些文件。

- [ ] **Step 4: 编译 SunSmart iOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: build succeeds with exit code 0。

- [ ] **Step 5: 提交实现**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "fix: use high-end trim for daylight occupancy auto"
```

Expected: 生成一个只包含 `Node+SyncData.swift` 行为修复的提交。

## Self-Review

- Spec coverage: Task 1 覆盖 `.occupancy_daylight` / `.vacancy_daylight` 未校准 Auto 进入 high-end trim；Task 2 覆盖 `.daylight` 既有修复、Auto 命令不变和 iOS build。
- Placeholder scan: 计划不包含待填内容。
- Type consistency: 使用现有 `daylightType`、`occupancyType`、`groupLightData.highEndTrim`、`ProfileType.occupancyLevel(value:)` 和 `Node.getLightness(lightness100:)`。
