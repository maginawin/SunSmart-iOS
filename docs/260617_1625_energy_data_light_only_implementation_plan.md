# Energy Data Light-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Site - Space - More - Energy Data` only collect and display lights.

**Architecture:** Keep the filter local to the Energy Data module and avoid changing global node semantics. Static Data will filter both live collection nodes and historical display records; Time Series export selection will use the same live light-only source.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `Node.DeviceType` and `MeshDeviceConfigInfo` device metadata.

---

## File Structure

- Modify `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
  - Add private light-only helpers.
  - Filter loaded `EnergyStatisticsStaticData` before it drives Space, Group, and Device UI.
  - Filter collection nodes before launching `ReadDevicesDataViewController`.
- Modify `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`
  - Filter export candidate devices to lights.
- Verify with iPhoneOS `xcodebuild`.

## Task 1: Static Data 读取与采集只使用 Lights

**Files:**
- Modify: `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift:150-268`

- [ ] **Step 1: Add private filtering helpers**

Add these helpers inside `EnergyStaticDataViewController`, near `back()` and before `setupData()`:

```swift
    private var energyDataNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }
    }

    private func lightOnlyStaticData(_ staticData: EnergyStatisticsStaticData?) -> EnergyStatisticsStaticData? {
        guard let staticData = staticData else { return nil }
        let deviceEnergyDatas = staticData.deviceEnergyDatas.filter { isLightEnergyData($0) }
        return EnergyStatisticsStaticData(
            timestamp: staticData.timestamp,
            incomplete: staticData.incomplete,
            deviceEnergyDatas: deviceEnergyDatas,
            groups: staticData.groups
        )
    }

    private func isLightEnergyData(_ data: DeviceTotalEnergyData) -> Bool {
        guard let productId = data.productId,
              let deviceInfo = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.productId == productId }) else {
            return false
        }
        return Node.DeviceType(deviceCategory: deviceInfo.deviceCategory) == .light
    }
```

- [ ] **Step 2: Filter loaded historical static data**

Replace the start of `setupData()` with:

```swift
        let staticDatas = EnergyStatisticsStaticData.load(spaceId: space.id)

        latestHarvestData = lightOnlyStaticData(staticDatas.first)
        previousHarvestData = staticDatas.count > 1 ? lightOnlyStaticData(staticDatas[1]) : nil
```

Expected behavior: all downstream Space, Group, and Device UI uses filtered `latestHarvestData` / `previousHarvestData`; old Battery/AC records no longer affect totals or list rows.

- [ ] **Step 3: Defensively filter converted collection nodes**

At the beginning of `convertDeviceTotalEnergyDatas(nodes:failedNodes:)`, before creating `timestamp`, add:

```swift
        let nodes = nodes.filter { $0.deviceType == .light }
        let failedNodes = failedNodes.filter { $0.deviceType == .light }
```

Expected behavior: even if a future caller passes all `realNodes`, only lights are persisted in new Energy Static Data records.

- [ ] **Step 4: Collect only light nodes**

In `readMeshDevicesEnergy()`, replace:

```swift
        let nodes = MeshNetworkManager.instance.realNodes
```

with:

```swift
        let nodes = energyDataNodes
```

Expected behavior: `ReadDevicesDataViewController(type: .harvestData(nodes: nodes))` receives only lights, so Battery/AC Power Switch is not queried for total energy use.

- [ ] **Step 5: Review the Static Data diff**

Run:

```bash
git diff -- SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift
```

Expected: the diff only adds local light filtering and does not change unrelated UI layout, strings, resources, or target configuration.

## Task 2: Time Series 导出设备选择只使用 Lights

**Files:**
- Modify: `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift:55-65`

- [ ] **Step 1: Add a private live-device helper**

Add this helper inside `EnergyTimeSeriesDataViewController`, near the initializer section before `viewDidLoad()`:

```swift
    private var energyDataNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }
    }
```

- [ ] **Step 2: Use the helper in `viewDidLoad()`**

Replace:

```swift
        devices = MeshNetworkManager.instance.realNodes
```

with:

```swift
        devices = energyDataNodes
```

Expected behavior: `EnergySelectExportDevicesController` receives only lights, so Battery/AC Power Switch is not available in Time Series export device selection.

- [ ] **Step 3: Review the Time Series diff**

Run:

```bash
git diff -- SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
```

Expected: the diff only changes device source filtering.

## Task 3: Verification

**Files:**
- Verify: `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
- Verify: `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`

- [ ] **Step 1: Scan for remaining unfiltered Energy Data `realNodes` usage**

Run:

```bash
rg -n "MeshNetworkManager\\.instance\\.realNodes" SunSmart/Main/Energy/Controller
```

Expected: Energy Data controllers do not use `realNodes` directly for Static Data collection or Time Series export candidate selection.

- [ ] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Build iPhoneOS SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Review final changed files**

Run:

```bash
git status --short
git diff --stat
```

Expected: only the two Energy controller files are modified, plus this implementation plan if it has not already been committed.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
git commit -m "fix: filter energy data devices to lights"
```

Expected: commit succeeds without staging unrelated files.

## Self-Review

- Spec coverage: Static Data collection, Static Data display, old non-light records, and Time Series export selection are all covered.
- Placeholder scan: no deferred or incomplete implementation language remains.
- Type consistency: live filters use `Node.deviceType == .light`; historical filters use `DeviceTotalEnergyData.productId` plus `MeshLibManager.manager.supportDeviceInfos` to derive `Node.DeviceType.light`.
