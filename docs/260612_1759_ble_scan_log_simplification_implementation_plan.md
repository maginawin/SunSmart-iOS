# BLE Scan Log Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 BLE 扫描相关 DEBUG 日志从完整 advertisement 输出收敛为场景化单行短日志。

**Architecture:** 在 `MeshLibManager` 内提供私有短日志 helper，统一设备名解析和输出格式；Add Device 与 RSSI refresh 复用该 helper；OTA 实际连接目标在自己的扫描委托中输出同格式短日志。业务扫描、过滤、回调、连接逻辑保持不变。

**Tech Stack:** Swift, CoreBluetooth, NordicSigMeshSDK, Xcode iPhoneOS build.

---

## File Structure

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
  - 删除公共 `didDiscover` 的完整 `advertisementData` 打印。
  - 增加私有 `bleScanName(...)` 与 `logFoundDevice(...)` helper。
  - 在 `refreshNodesRSSI(...)` 成功匹配当前 Mesh 节点后输出 `Found: <name>, rssi: <rssi>, refresh node mac: <mac>`。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift`
  - 在 `startScan(...)` 成功生成 `ProvisioningDevice` 且存在 `macAddress` 后输出 `Found: <name>, rssi: <rssi>, mac: <mac>`。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareUpdateManager.swift`
  - 在 `MeshFirmwareUpdateOperation.didDiscover(...)` 匹配 OTA 目标 MAC 后输出 `Found OTA target: <name>, rssi: <rssi>, mac: <mac>`。

## Task 1: Add Shared Short Log Helper

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`

- [ ] **Step 1: Add name formatting helper**

Add private helper methods inside `MeshLibManager`, near the scan methods:

```swift
private func bleScanName(peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
    if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
        return localName
    }
    if let name = peripheral.name, !name.isEmpty {
        return name
    }
    return "Unknown"
}

func logFoundDevice(prefix: String = "Found", peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber, macLabel: String, macAddress: String) {
    #if DEBUG
    let name = bleScanName(peripheral: peripheral, advertisementData: advertisementData)
    print("\(prefix): \(name), rssi: \(rssi), \(macLabel): \(macAddress)")
    #endif
}
```

- [ ] **Step 2: Remove full advertisement print**

In `centralManager(_:didDiscover:advertisementData:rssi:)`, remove the DEBUG print:

```swift
#if DEBUG
print("name: \(peripheral.name ?? "") advertisement: \(advertisementData) rssi: \(RSSI)")
#endif
```

Keep the scan callback behavior unchanged:

```swift
if RSSI.intValue <= 0, self.scanResultBack != nil {
    self.scanResultBack!(peripheral, advertisementData, RSSI)
}
```

## Task 2: Add Short Logs for Add Device and RSSI Refresh

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift`

- [ ] **Step 1: Replace RSSI refresh MAC print**

In `refreshNodesRSSI(...)`, replace:

```swift
print("refresh node mac: \(macAddress)")
```

with:

```swift
self.logFoundDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi, macLabel: "refresh node mac", macAddress: macAddress)
```

- [ ] **Step 2: Add Add Device short log**

In `MeshAddDeviceManager.startScan(...)`, after this guard succeeds:

```swift
if let device = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi), device.macAddress != nil {
```

bind the MAC and log it:

```swift
if let device = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi), let macAddress = device.macAddress {
    MeshLibManager.manager.logFoundDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi, macLabel: "mac", macAddress: macAddress)
```

Keep the existing list replacement and callback body unchanged.

## Task 3: Add Short Log for OTA Target Discovery

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareUpdateManager.swift`

- [ ] **Step 1: Log only matched OTA target**

In `MeshFirmwareUpdateOperation.centralManager(_:didDiscover:advertisementData:rssi:)`, inside:

```swift
if advertisementData.macAddress == updateNode.macAddress {
```

add:

```swift
if let macAddress = updateNode.macAddress {
    MeshLibManager.manager.logFoundDevice(prefix: "Found OTA target", peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI, macLabel: "mac", macAddress: macAddress)
}
```

Keep existing `peripheral` assignment, `gattBearerOpen(...)`, and `stopDiscoverDevice()` behavior unchanged.

## Task 4: Verify

**Files:**
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFirmwareUpdateManager.swift`

- [ ] **Step 1: Static log search**

Run:

```bash
rg -n "advertisement:|refresh node mac:|Found OTA target|logFoundDevice" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager
```

Expected:

- No old full advertisement print remains.
- No standalone `print("refresh node mac: ...")` remains.
- `Found OTA target` and `logFoundDevice` call sites are present.

- [ ] **Step 2: Whitespace check**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
git diff --check
```

Expected: no output.

- [ ] **Step 3: iPhoneOS build**

Run from `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light`:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.
