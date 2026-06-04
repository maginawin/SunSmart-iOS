# Daylight Uncalibrated Auto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复纯 `.daylight` profile 未校准时重新 SAVE / Sync 后 Auto 行为不稳定的问题，让设备响应 Auto 时进入 profile high-end trim 亮度。

**Architecture:** 只修改 profile 同步数据生成层，不修改组页、传感器、遥控器的 Auto 命令。未校准纯 `.daylight` 在 `.taskLevel` 分支中写入 `LightControlLightnessOn = highEndTrim`；已校准 `.daylight` 继续由现有 target lux 和 auto-min 逻辑维护 closed-loop 行为。

**Tech Stack:** Swift, iOS, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - Responsibility: 生成节点加入 group 或保存 group profile 时需要同步的 `ProfileType` 列表。
  - Scope: 只改 `getNodeLightDataSyncProfiles(group:groupLightData:lightLCProperty:forceFullProfileSync:)` 内 `.taskLevel` 的未校准纯 `.daylight` 分支。
- Read-only reference: `SunSmart/Common/Data/Node+MessageHandles.swift`
  - Responsibility: 将 `.occupancyLevel(value:)` 转成 `LightLCPropertySet(.lightControlLightnessOn, .perceivedLightness(...))`。
- Read-only reference: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - Responsibility: 组页 Auto 命令入口。本计划不修改该文件。

## Task 1: 修改未校准纯 Daylight 的 Task Level 同步规则

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift:1275-1284`

- [ ] **Step 1: 记录当前待替换分支**

确认当前 `.taskLevel` 分支仍是以下结构：

```swift
case .taskLevel(let level):
    if daylightType {
        if forceFullProfileSync || lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level { // 设置占用阶段无限长，维持该照度
            syncProfile.append(.occupancyLux(lux: level))
        }
    }else {
        if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) { // 设置占用阶段无限长，维持该亮度
            syncProfile.append(.occupancyLevel(value: level))
        }
    }
    if forceFullProfileSync || lightLCProperty.timeRunOn != 0xFFFFFE {
        syncProfile.append(.t2(second: 0xFFFFFE))
    }
```

Run: `nl -ba SunSmart/Common/Data/Node+SyncData.swift | sed -n '1270,1290p'`

Expected: 能看到上述 `.taskLevel` 分支。

- [ ] **Step 2: 实现未校准纯 `.daylight` fallback**

将 `.taskLevel` 分支替换为：

```swift
case .taskLevel(let level):
    if groupProfile.type == .daylight && !daylightEnabled {
        let fallbackLevel = groupLightData.highEndTrim
        if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: fallbackLevel) {
            syncProfile.append(.occupancyLevel(value: fallbackLevel))
        }
    }else if daylightType {
        if forceFullProfileSync || lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level { // 设置占用阶段无限长，维持该照度
            syncProfile.append(.occupancyLux(lux: level))
        }
    }else {
        if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) { // 设置占用阶段无限长，维持该亮度
            syncProfile.append(.occupancyLevel(value: level))
        }
    }
    if forceFullProfileSync || lightLCProperty.timeRunOn != 0xFFFFFE {
        syncProfile.append(.t2(second: 0xFFFFFE))
    }
```

Rationale:

- `groupProfile.type == .daylight && !daylightEnabled` 精确限制为未校准纯 daylight。
- `fallbackLevel = groupLightData.highEndTrim` 使用当前同步场景的 high-end trim。纯 `.daylight` 当前只有 General Scene，该值等同于 profile high-end trim。
- 复用 `.occupancyLevel(value:)`，让现有 message handle 写入 `LightControlLightnessOn`。
- 已校准 `.daylight` 仍走 `occupancyLux(lux:)`，随后现有 `autoMinValue` 分支会把 `LightControlLightnessOn` 改回 auto-min 或 0。

- [ ] **Step 3: 源码检查未修改 Auto 命令**

Run: `rg -n "LightLCLightOnOffSetUnacknowledged\\(true" SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Device1.5/FireAlarm`

Expected:

- `GroupViewController.autoBtnAction` 仍发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)`。
- 本任务没有改动上述文件。

- [ ] **Step 4: 源码检查 fallback 只作用于纯 `.daylight`**

Run: `rg -n "fallbackLevel|groupProfile.type == \\.daylight && !daylightEnabled|occupancyLevel\\(value: fallbackLevel\\)" SunSmart/Common/Data/Node+SyncData.swift`

Expected:

- 出现 `groupProfile.type == .daylight && !daylightEnabled`。
- 出现 `let fallbackLevel = groupLightData.highEndTrim`。
- 出现 `syncProfile.append(.occupancyLevel(value: fallbackLevel))`。
- `.occupancy_daylight` / `.vacancy_daylight` 没有新增专门分支。

## Task 2: 验证构建和行为边界

**Files:**
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: 检查 `.occupancyLevel(value:)` 的消息落点**

Run: `nl -ba SunSmart/Common/Data/Node+MessageHandles.swift | sed -n '355,365p'`

Expected: `.occupancyLevel(let value)` 转成 `LightLCPropertySet(of: .lightControlLightnessOn, value: .perceivedLightness(lightness))`。

- [ ] **Step 2: 检查已校准分支仍能改回 auto-min 或 0**

Run: `nl -ba SunSmart/Common/Data/Node+SyncData.swift | sed -n '1240,1260p'`

Expected:

```swift
if daylightEnabled {
    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
        syncProfile.append(.occupancyLevel(value: level))
    }
```

其中 `level` 来自 `let level = enabled ? value : 0`。

- [ ] **Step 3: 检查 diff 聚焦**

Run: `git diff -- SunSmart/Common/Data/Node+SyncData.swift`

Expected:

- 只修改 `.taskLevel` 分支。
- 没有修改 `GroupViewController.swift`。
- 没有新增 Auth、资源、target 配置或依赖。

- [ ] **Step 4: 编译 SunSmart iOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: build succeeds with exit code 0。

- [ ] **Step 5: 提交实现**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "fix: set daylight auto fallback level"
```

Expected: 生成一个只包含 `Node+SyncData.swift` 行为修复的提交。

## Self-Review

- Spec coverage: Task 1 覆盖方案 A 的同步规则改动；Task 2 覆盖 Auto 命令不变、已校准改回 auto-min/0、源码 diff 和 iOS build。
- Placeholder scan: 计划不包含待填内容。
- Type consistency: 使用现有 `ProfileType.occupancyLevel(value:)`、`groupLightData.highEndTrim`、`daylightEnabled`、`lightLCProperty.lightnessOn` 和 `Node.getLightness(lightness100:)`，均来自当前代码。
