# EL Controller Energy Data Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> For this repository, `AGENTS.md` selects Inline Execution by default, so use `superpowers:executing-plans` unless the user explicitly asks for subagents.

**Goal:** Remove `isEmergencySignController` devices, including `CID 0x0A78 / PID 0x24C1` EL Controller, from Energy Data display, harvest, history, and export selection.

**Architecture:** Keep the filter local to the Energy Data module. Static Data and Time Series Data will still require `.light`, but will additionally exclude `node.isEmergencySignController`; historical Static Data fallback will use `MeshDeviceConfigInfo.companyId/productId` with `Node.isEmergencySignController(companyIdentifier:productIdentifier:)`.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `Node` capability helpers, Xcode `xcodebuild`.

---

## File Structure

- Modify `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
  - Owns Static Data display, latest/previous history loading, and `HARVEST NEW ENERGY DATA` live device collection.
  - Add a local `isEnergyDataNode(_:)` predicate and use it for live nodes and current-node history filtering.
  - Rename the local historical helper from light-only wording to Energy Data wording so its behavior matches the new rule.
- Modify `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`
  - Owns Time Series import/export UI and export device candidate list.
  - Apply the same `.light && !isEmergencySignController` rule to export candidates.

No new files are needed. Do not modify `devices_config.json`, `Node.DeviceType`, or `Node.isEmergencySignController`.

---

### Task 1: Static Data live and history filter

**Files:**
- Modify: `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`

- [ ] **Step 1: Inspect the existing Static Data filter**

Run:

```bash
sed -n '145,185p' SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift
```

Expected: output shows `energyDataNodes` filtering only `node.deviceType == .light`, `lightOnlyStaticData(_:)`, and `isLightEnergyData(_:)`.

- [ ] **Step 2: Replace the Static Data filter helpers**

In `EnergyStaticDataViewController`, replace the current `energyDataNodes`, `lightOnlyStaticData(_:)`, and `isLightEnergyData(_:)` block with:

```swift
    private var energyDataNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter { isEnergyDataNode($0) }
    }

    private func isEnergyDataNode(_ node: Node) -> Bool {
        node.deviceType == .light && !node.isEmergencySignController
    }

    private func energyDataStaticData(_ staticData: EnergyStatisticsStaticData?) -> EnergyStatisticsStaticData? {
        guard let staticData = staticData else { return nil }
        let deviceEnergyDatas = staticData.deviceEnergyDatas.filter { isEnergyData($0) }
        return EnergyStatisticsStaticData(
            timestamp: staticData.timestamp,
            incomplete: staticData.incomplete,
            deviceEnergyDatas: deviceEnergyDatas,
            groups: staticData.groups
        )
    }

    private func isEnergyData(_ data: DeviceTotalEnergyData) -> Bool {
        if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: data.address) {
            return isEnergyDataNode(node)
        }

        guard let productId = data.productId,
              let deviceInfo = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.productId == productId }) else {
            return false
        }
        return Node.DeviceType(deviceCategory: deviceInfo.deviceCategory) == .light
            && !Node.isEmergencySignController(companyIdentifier: deviceInfo.companyId, productIdentifier: deviceInfo.productId)
    }
```

Expected behavior:
- Live harvest nodes exclude EL Controller before `ReadDevicesDataViewController(type: .harvestData(nodes: nodes))` is created.
- Historical records exclude EL Controller both when the current mesh node still exists and when only `productId` fallback data is available.

- [ ] **Step 3: Update Static Data call sites**

In `setupData()`, replace:

```swift
        latestHarvestData = lightOnlyStaticData(staticDatas.first)
        previousHarvestData = staticDatas.count > 1 ? lightOnlyStaticData(staticDatas[1]) : nil
```

with:

```swift
        latestHarvestData = energyDataStaticData(staticDatas.first)
        previousHarvestData = staticDatas.count > 1 ? energyDataStaticData(staticDatas[1]) : nil
```

Expected: there are no remaining references to `lightOnlyStaticData` or `isLightEnergyData`.

- [ ] **Step 4: Verify Static Data references**

Run:

```bash
rg -n "lightOnlyStaticData|isLightEnergyData|isEnergyDataNode|isEnergyData\\(" SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift
```

Expected:
- No `lightOnlyStaticData` result.
- No `isLightEnergyData` result.
- Results include `isEnergyDataNode` and `isEnergyData(`.

---

### Task 2: Time Series export device filter

**Files:**
- Modify: `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`

- [ ] **Step 1: Inspect the existing Time Series filter**

Run:

```bash
sed -n '50,70p' SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
```

Expected: output shows `energyDataNodes` filtering only `node.deviceType == .light`.

- [ ] **Step 2: Exclude emergency sign controllers from Time Series candidates**

Replace:

```swift
    private var energyDataNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }
    }
```

with:

```swift
    private var energyDataNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter {
            $0.deviceType == .light && !$0.isEmergencySignController
        }
    }
```

Expected behavior: `devices = energyDataNodes` in `viewDidLoad()` no longer includes EL Controller, so `EnergySelectExportDevicesController` cannot show it for Device export selection.

- [ ] **Step 3: Verify Time Series references**

Run:

```bash
rg -n "energyDataNodes|isEmergencySignController|deviceType == \\.light" SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
```

Expected:
- `energyDataNodes` result includes `!$0.isEmergencySignController`.
- There is no remaining Time Series `energyDataNodes` implementation that filters only by `.light`.

---

### Task 3: Regression scan, build, and commit

**Files:**
- Verify: `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
- Verify: `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`

- [ ] **Step 1: Scan Energy Data for remaining light-only candidate filters**

Run:

```bash
rg -n "filter \\{ \\$0\\.deviceType == \\.light \\}|filter\\(\\{ \\$0\\.deviceType == \\.light \\}\\)" SunSmart/Main/Energy/Controller
```

Expected: no results from `EnergyStaticDataViewController.swift` or `EnergyTimeSeriesDataViewController.swift` showing a bare light-only Energy Data candidate filter.

- [ ] **Step 2: Inspect the final diff**

Run:

```bash
git diff -- SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
```

Expected:
- Static Data live source uses `isEnergyDataNode`.
- Static Data historical fallback excludes `Node.isEmergencySignController(companyIdentifier:productIdentifier:)`.
- Time Series source excludes `isEmergencySignController`.
- No unrelated formatting or resource changes.

- [ ] **Step 3: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift
git commit -m "fix: filter EL Controller from energy data"
```

Expected: commit contains only the two Energy Data controller changes.

---

## Self-Review

- Spec coverage: Static Data Device display, Harvest data live list, old Static Data history, Time Series Device export selection, Device Parameter Settings non-impact, and iPhoneOS verification are each covered by tasks above.
- Placeholder scan: no placeholder markers are present.
- Type consistency: plan uses existing `Node.isEmergencySignController`, static `Node.isEmergencySignController(companyIdentifier:productIdentifier:)`, `MeshDeviceConfigInfo.companyId`, `MeshDeviceConfigInfo.productId`, and existing controller method names.
