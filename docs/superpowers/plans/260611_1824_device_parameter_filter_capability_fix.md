# Device Parameter Filter Capability Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Device Parameter Settings 设备列表页的 `Filter` 弹窗只展示当前设备实际支持的参数类型，并让 `--` 只代表支持参数但当前无值。

**Architecture:** 在 `DeviceParameterDevicesViewController` 内新增页面局部能力判断 helper，避免引入跨模块抽象。`setupFilterData()`、弹窗内容生成和筛选应用统一使用同一能力判断，保持设备列表 cell 与 Filter 弹窗一致。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `Node` capability properties, existing `DeviceParameterFilterView`.

---

### Task 1: Add Local Filter Capability Helper

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`

- [x] **Step 1: Add helper methods inside `DeviceParameterDevicesViewController`**

Add these private methods near `setupFilterData()` so the filter data source has one local capability rule:

```swift
    private func devicesSupportingFilter(_ type: ParameterFilterData.ParameterType) -> [Node] {
        devices.filter { nodeSupportsFilter($0, type: type) }
    }

    private func nodeSupportsFilter(_ node: Node, type: ParameterFilterData.ParameterType) -> Bool {
        switch type {
        case .pwm:
            return node.supportPwmFrequency
        case .ratedPower:
            return true
        case .absoluteSensitivity:
            return node.supportMotionSensitivity
        case .transitionTime:
            return node.supportDefaultTransitionTime
        case .changeControlPage, .absoluteCctRange:
            return node.rawSupportCct
        }
    }
```

- [x] **Step 2: Run syntax-level build check if available through Xcode build later**

Do not run a separate command here. This task is verified by the final iPhoneOS build in Task 4.

### Task 2: Filter Candidate Value Collection By Capability

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`

- [x] **Step 1: Update `setupFilterData()` value collection**

Change the loop in `setupFilterData()` so each value is collected only from nodes supporting that parameter:

```swift
        devices.forEach({ node in

            if nodeSupportsFilter(node, type: .pwm), let pwm = node.tempPwm, !pwmValues.contains(pwm) {
                pwmValues.append(pwm)
            }
            if nodeSupportsFilter(node, type: .ratedPower), node.tempRatedPowerPhases.count > 0 {
                if !ratedPowers.contains(node.tempRatedPowerPhases) {
                    ratedPowers.append(node.tempRatedPowerPhases)
                }
            }
            if nodeSupportsFilter(node, type: .absoluteSensitivity), let range = node.tempSensitivityRange, !absoluteSensitivitys.contains(range) {
                absoluteSensitivitys.append(range)
            }
            if nodeSupportsFilter(node, type: .transitionTime), let transitionTime = node.tempTransitionTime, !transitionTimes.contains(where: { $0.interval == transitionTime.interval }) {
                transitionTimes.append(transitionTime)
            }
            if nodeSupportsFilter(node, type: .changeControlPage) {
                if !changeControlPages.contains(node.tempChangeControlPage) {
                    changeControlPages.append(node.tempChangeControlPage)
                }
            }
            if nodeSupportsFilter(node, type: .absoluteCctRange) {
                if !absoluteCctRanges.contains(node.tempAbsoluteCctRange) {
                    absoluteCctRanges.append(node.tempAbsoluteCctRange)
                }
            }

        })
```

- [x] **Step 2: Confirm existing CCT behavior remains equivalent**

Check that `.changeControlPage` and `.absoluteCctRange` still map to `rawSupportCct`, matching the existing code path.

### Task 3: Filter Popup Content And Result Application By Capability

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`

- [x] **Step 1: Add supported device groups at the start of `promptViewFilterAction(_:)`**

Add these constants before building `pwmContents`:

```swift
        let pwmDevices = devicesSupportingFilter(.pwm)
        let ratedPowerDevices = devicesSupportingFilter(.ratedPower)
        let sensitivityDevices = devicesSupportingFilter(.absoluteSensitivity)
        let transitionTimeDevices = devicesSupportingFilter(.transitionTime)
        let changeControlPageDevices = devicesSupportingFilter(.changeControlPage)
        let absoluteCctRangeDevices = devicesSupportingFilter(.absoluteCctRange)
```

- [x] **Step 2: Restrict `--` generation to supported devices**

Update the empty-value checks:

```swift
        if pwmDevices.contains(where: { $0.tempPwm == nil }) {
            pwmContents.insert(("--", nil), at: 0)
        }
```

```swift
        if ratedPowerDevices.contains(where: { $0.tempRatedPowerPhases.isEmpty }) {
            powerDatas.insert(("--", []), at: 0)
        }
```

```swift
        if sensitivityDevices.contains(where: { $0.tempSensitivityRange == nil }) {
            sensitivityContents.insert(("--", nil), at: 0)
        }
```

```swift
        if transitionTimeDevices.contains(where: { $0.tempTransitionTime == nil }) {
            transitionTimeDatas.insert(("--", nil), at: 0)
        }
```

- [x] **Step 3: Only create sections when at least one device supports the parameter**

Update each section guard so empty content from unsupported devices cannot create a section:

```swift
        if !pwmDevices.isEmpty && pwmContents.count > 0 {
            filterDatas.append(.init(type: .pwm, isShow: pwmSelectIndex != nil, contents: pwmContents.map({ $0.name }), selectIndex: pwmSelectIndex))
        }
```

Apply the same pattern to `ratedPowerDevices`, `sensitivityDevices`, `transitionTimeDevices`, `changeControlPageDevices`, and `absoluteCctRangeDevices`.

- [x] **Step 4: Restrict applied filter results to supported devices**

Update each filter branch to include `nodeSupportsFilter`:

```swift
                        showDevices = showDevices.filter({ self.nodeSupportsFilter($0, type: .pwm) && $0.tempPwm == data.value })
```

For empty selections:

```swift
                        showDevices = showDevices.filter({ self.nodeSupportsFilter($0, type: .pwm) && $0.tempPwm == nil })
```

Apply the same pattern to rated power, absolute sensitivity, transition time, change control page, and absolute CCT range. CCT branches should keep value checks and replace the existing direct `rawSupportCct` check with the helper.

### Task 4: Verify And Commit

**Files:**
- Verify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`

- [x] **Step 1: Run focused code search**

Run:

```bash
rg -n "devices\\.contains\\(where: \\{ \\$0\\.temp(Pwm|SensitivityRange|TransitionTime)|rawSupportCct && \\$0\\.temp(ChangeControlPage|AbsoluteCctRange)|filterDatas.append" SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift
```

Expected: no remaining `devices.contains` empty-value checks for parameter filters; CCT filter branches should use `nodeSupportsFilter`.

- [x] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [x] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [x] **Step 4: Review changed files**

Run:

```bash
git status --short
git diff -- SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift
```

Expected: implementation changes are limited to `DeviceParameterDevicesViewController.swift` plus this plan file if it has not already been committed.

- [x] **Step 5: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift docs/superpowers/plans/260611_1824_device_parameter_filter_capability_fix.md
git commit -m "fix: filter device parameters by capability"
```

Expected: commit succeeds.

## Self-Review

- Spec coverage: The plan covers capability-based section visibility, supported-device-only candidate values, `--` semantics, applied filter consistency, and iPhoneOS build verification.
- Placeholder scan: No placeholder tasks remain.
- Type consistency: The helper uses existing `ParameterFilterData.ParameterType` cases and existing `Node` capability properties.
