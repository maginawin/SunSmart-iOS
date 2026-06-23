# ZLL Controller Sensor Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `0x0A78 / 0x2132` 的 ZLL Controller Sensor 图标和重命名后的 AC Power Switch 离线图标都走统一的 `device_offline_\(iconCategory)` 命名规则。

**Architecture:** 保持 `devices_config.json` 的 `iconCategory` 配置驱动不变，只清理历史离线图标特例和一处 AC Power Switch 硬编码。`ZLLControllerSensor` 不新增分支，直接复用 `MeshDeviceConfigInfo` 现有默认规则。

**Tech Stack:** Swift、UIKit asset catalog、Xcode asset lookup、`jq`、`xcodebuild`

---

## File Structure

- Modify: `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift`
  - 负责设备配置解析后的通用图标名派生。
  - 本次移除 `ACPowerSwitch` 离线图标旧特例，让所有 icon category 使用统一离线命名规则。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 负责八键开关列表项展示图标。
  - 本次把 AC Power Switch 离线状态硬编码从旧资源名改为新资源名。
- Verify only: `SunSmart/devices_config.json`
  - 确认 `0x0A78 / 0x2132` 仍为 `iconCategory = ZLLControllerSensor`、`deviceCategory = Lighting`。
- Verify only: `SunSmart/Assets.xcassets/Device/`
  - 确认新资源目录存在。

## Task 1: Clean Generic Offline Icon Rule

**Files:**
- Modify: `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift`

- [ ] **Step 1: Capture the current failing reference**

Run:

```sh
rg -n "device_ACPowerSwitch_offline|offlineIconName" SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift
```

Expected before implementation:

```text
SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift:34:    var offlineIconName: String {
SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift:36:            return "device_ACPowerSwitch_offline"
```

- [ ] **Step 2: Remove the old AC Power Switch exception**

In `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift`, replace:

```swift
    var offlineIconName: String {
        if iconCategory == "ACPowerSwitch" {
            return "device_ACPowerSwitch_offline"
        }
        return "device_offline_\(iconCategory)"
    }
```

with:

```swift
    var offlineIconName: String {
        return "device_offline_\(iconCategory)"
    }
```

- [ ] **Step 3: Verify the generic rule no longer references the old asset**

Run:

```sh
rg -n "device_ACPowerSwitch_offline" SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift
```

Expected:

```text
```

The command should produce no output and exit with status `1`.

## Task 2: Update Eight-Key AC Power Switch Offline Icon

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: Capture the remaining old hardcoded reference**

Run:

```sh
rg -n "device_ACPowerSwitch_offline" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected before implementation:

```text
SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:297:            return "device_ACPowerSwitch_offline"
```

- [ ] **Step 2: Update the hardcoded offline asset name**

In `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`, replace:

```swift
    var displayIconAssetName: String {
        if powerSwitchKind == .ac, proxyNode?.state == false {
            return "device_ACPowerSwitch_offline"
        }
        return powerSwitchKind.deviceIconAssetName
    }
```

with:

```swift
    var displayIconAssetName: String {
        if powerSwitchKind == .ac, proxyNode?.state == false {
            return "device_offline_ACPowerSwitch"
        }
        return powerSwitchKind.deviceIconAssetName
    }
```

- [ ] **Step 3: Verify the hardcoded reference uses the new resource**

Run:

```sh
rg -n "device_offline_ACPowerSwitch|device_ACPowerSwitch_offline" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected after implementation:

```text
SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:297:            return "device_offline_ACPowerSwitch"
```

## Task 3: Static Config and Asset Verification

**Files:**
- Verify only: `SunSmart/devices_config.json`
- Verify only: `SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset`
- Verify only: `SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset`
- Verify only: `SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset`

- [ ] **Step 1: Validate JSON files**

Run:

```sh
jq empty SunSmart/devices_config.json SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset/Contents.json SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset/Contents.json SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset/Contents.json
```

Expected:

```text
```

The command should produce no output and exit with status `0`.

- [ ] **Step 2: Confirm the 0x2132 device config**

Run:

```sh
sed -n '1168,1179p' SunSmart/devices_config.json
```

Expected output contains:

```text
        "productId": "2132",
        "categoryName": "ZLLC Controller",
        "elementCount": 2,
        "iconCategory": "ZLLControllerSensor",
        "deviceCategory": "Lighting",
```

- [ ] **Step 3: Confirm required asset directories**

Run:

```sh
find SunSmart/Assets.xcassets/Device -maxdepth 1 -type d \( -name 'device_ZLLControllerSensor.imageset' -o -name 'device_offline_ZLLControllerSensor.imageset' -o -name 'device_offline_ACPowerSwitch.imageset' \) -print | sort
```

Expected:

```text
SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset
SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset
SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset
```

## Task 4: Whole-Repo Reference Verification

**Files:**
- Verify only: `SunSmart/`

- [ ] **Step 1: Ensure old resource names are no longer referenced by source code**

Run:

```sh
rg -n "device_ACPowerSwitch_offline|ZLLControllerSensor_offline" SunSmart
```

Expected:

```text
```

The command should produce no output and exit with status `1`.

- [ ] **Step 2: Check whitespace and patch hygiene**

Run:

```sh
git diff --check
```

Expected:

```text
```

The command should produce no output and exit with status `0`.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

## Task 5: Commit Implementation

**Files:**
- Stage and commit only files needed for this change.

- [ ] **Step 1: Review changed files before staging**

Run:

```sh
git status --short
```

Expected changed implementation files include:

```text
 M SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift
 M SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Existing resource and `devices_config.json` changes may also appear because they were already present in the working tree and are required for the feature. Do not stage unrelated files.

- [ ] **Step 2: Stage focused implementation files**

Run:

```sh
git add SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/devices_config.json SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset
```

- [ ] **Step 3: Include old AC offline asset deletion if still shown**

Run:

```sh
git add -u SunSmart/Assets.xcassets/Device/device_ACPowerSwitch_offline.imageset
```

Expected: no terminal output.

- [ ] **Step 4: Confirm staged files are scoped**

Run:

```sh
git diff --cached --name-status
```

Expected staged files are limited to:

```text
M	SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift
M	SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
M	SunSmart/devices_config.json
A	SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset/Contents.json
A	SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset/device_ZLLCController.png
A	SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset/device_ZLLCController@2x.png
A	SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset/device_ZLLCController@3x.png
R100	SunSmart/Assets.xcassets/Device/device_ACPowerSwitch_offline.imageset/Contents.json	SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset/Contents.json
R100	SunSmart/Assets.xcassets/Device/device_ACPowerSwitch_offline.imageset/Property 1=8keys-AC-offline.png	SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset/Property 1=8keys-AC-offline.png
R100	SunSmart/Assets.xcassets/Device/device_ACPowerSwitch_offline.imageset/Property 1=8keys-AC-offline@2x.png	SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset/Property 1=8keys-AC-offline@2x.png
R100	SunSmart/Assets.xcassets/Device/device_ACPowerSwitch_offline.imageset/Property 1=8keys-AC-offline@3x.png	SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset/Property 1=8keys-AC-offline@3x.png
A	SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset/Contents.json
A	SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset/device_ZLLCController_offline.png
A	SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset/device_ZLLCController_offline@2x.png
A	SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset/device_ZLLCController_offline@3x.png
```

- [ ] **Step 5: Commit**

Run:

```sh
git commit -m "fix: align controller sensor offline icons"
```

Expected: commit succeeds.
