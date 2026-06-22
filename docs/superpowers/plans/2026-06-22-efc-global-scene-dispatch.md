# EFC Global Scene Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EFC recall scene handling run from a Space-level global mesh message entry instead of page-level `messageDelegate` forwarding.

**Architecture:** `MeshLibManager` gets a small independent `globalMessageObservers` multicast hook that does not replace `messageDelegate` or `messageReceiveCallback`. `SpaceViewController` registers one observer while the Space is active and forwards all ordinary mesh messages to `EmergencyFireControllerSceneEventManager.dispatch(...)`. Existing page-level EFC dispatch calls are removed so each recall scene is handled once.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK local Swift Package, Bash contract script, Xcode iPhoneOS build.

---

### File Structure

- Modify SDK: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
  - Add global mesh message observer registration/removal.
  - Invoke observers from the existing ordinary message receive path before page `messageDelegate`.
- Modify App: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - Register the Space-level EFC mesh message observer after `EmergencyFireControllerSceneEventManager.activate()`.
  - Remove the observer in `deinit` with the same lifecycle as the EFC manager.
- Modify App pages by removing direct EFC dispatch calls:
  - `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - `SunSmart/Main/Device/Controller/DeviceBaseViewController.swift`
  - `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorDelegates.swift`
  - `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
  - `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
  - `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- Modify contract: `scripts/check_efc_controller_flows.sh`
  - Assert global observer API exists.
  - Assert `SpaceViewController` registers/removes observer and is the only App caller of EFC dispatch.
  - Assert page-level direct dispatch calls are gone.

### Task 1: Add SDK Global Message Observer

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`

- [ ] **Step 1: Add observer storage and API**

Add near `messageReceiveCallback`:

```swift
public typealias GlobalMessageObserver = (_ manager: MeshNetworkManager, _ message: MeshMessage, _ source: Address, _ destination: Address) -> Void

private var globalMessageObservers: [UUID: GlobalMessageObserver] = [:]

@discardableResult
public func addGlobalMessageObserver(_ observer: @escaping GlobalMessageObserver) -> UUID {
    let id = UUID()
    globalMessageObservers[id] = observer
    return id
}

public func removeGlobalMessageObserver(_ id: UUID?) {
    guard let id else { return }
    globalMessageObservers.removeValue(forKey: id)
}
```

- [ ] **Step 2: Notify observers in the existing receive path**

In `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)`, inside the ordinary non-heartbeat/non-external-vendor branch, add before the `messageDelegate?.meshNetworkManager(...didReceiveMessage...)` callback:

```swift
let observers = globalMessageObservers.values
if !observers.isEmpty {
    delegateQueue.async {
        observers.forEach { observer in
            observer(manager, message, source, destination.address)
        }
    }
}
```

Keep `messageReceiveCallback?(message, source)` untouched because OTA distribution uses it.

### Task 2: Register EFC Dispatch From Space

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1: Add observer token storage**

Add near `emergencyFireControllerSceneEventManager`:

```swift
private var emergencyFireSceneMessageObserverId: UUID?
```

- [ ] **Step 2: Register after EFC manager activation**

After:

```swift
self.emergencyFireControllerSceneEventManager?.activate()
```

add:

```swift
self.registerEmergencyFireSceneMessageObserverIfNeeded()
```

- [ ] **Step 3: Add register/remove helpers**

Add private helpers in `SpaceViewController`:

```swift
private func registerEmergencyFireSceneMessageObserverIfNeeded() {
    guard emergencyFireSceneMessageObserverId == nil else { return }
    emergencyFireSceneMessageObserverId = MeshLibManager.manager.addGlobalMessageObserver { [weak self] _, message, source, destination in
        guard self?.emergencyFireControllerSceneEventManager != nil else { return }
        EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)
    }
}

private func removeEmergencyFireSceneMessageObserver() {
    MeshLibManager.manager.removeGlobalMessageObserver(emergencyFireSceneMessageObserverId)
    emergencyFireSceneMessageObserverId = nil
}
```

- [ ] **Step 4: Remove observer before deactivating manager**

In `deinit`, before `emergencyFireControllerSceneEventManager?.deactivate()`:

```swift
removeEmergencyFireSceneMessageObserver()
```

### Task 3: Remove Page-Level EFC Dispatch

**Files:**
- Modify all listed page files containing direct `EmergencyFireControllerSceneEventManager.dispatch(...)`.

- [ ] **Step 1: Remove direct dispatch line from each page**

Remove only this line wherever it appears outside `SpaceViewController`:

```swift
EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)
```

Do not remove page-specific `didReceiveMessage` logic such as `node.updateData(message:)`, UI reloads, calibration handling, or group control behavior.

### Task 4: Add Contract Guards

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add positive assertions**

Add assertions:

```bash
assert_contains "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift" \
  "addGlobalMessageObserver" \
  "SDK must expose a global message observer for Space-level EFC scene dispatch."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "registerEmergencyFireSceneMessageObserverIfNeeded()" \
  "Space must register the global EFC scene message observer after activating the scene manager."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "removeEmergencyFireSceneMessageObserver()" \
  "Space must remove the global EFC scene message observer when leaving the Space lifecycle."
```

- [ ] **Step 2: Add count assertion**

Add:

```bash
assert_count "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)" \
  "1" \
  "Only SpaceViewController should dispatch EFC scene messages from the global observer."

if grep -R "EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)" \
  SunSmart/Main/Device SunSmart/Main/Group SunSmart/Main/Space/TriggerZone; then
  echo "FAIL: Page-level EFC scene dispatch must be removed; Space global observer owns dispatch." >&2
  exit 1
fi
```

### Task 5: Verify

**Files:**
- Validate App and local SDK.

- [ ] **Step 1: Run EFC contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 2: Run diff whitespace check**

Run:

```bash
git diff --check
```

Expected: no output, exit code 0.

- [ ] **Step 3: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

### Self-Review

- Spec coverage: Covers global mesh observer, Space-level EFC dispatch, page-level dispatch removal, contract checks, and iPhoneOS verification.
- Placeholder scan: No TBD/TODO placeholders.
- Type consistency: Observer token uses `UUID?`; SDK API names match App calls.

