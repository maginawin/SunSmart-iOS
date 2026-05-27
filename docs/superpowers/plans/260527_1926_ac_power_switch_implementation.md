# AC Power Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AC Power Switch support by reusing the existing 8-key Battery Power Switch behavior while separating battery-powered and AC-powered device-family behavior.

**Architecture:** Keep `PJEightKeySwitchData` as the shared 8-key power switch model and add a persisted device-family field. Split PID recognition into Battery, AC, and shared Power Switch predicates, then branch only where power behavior differs: battery reads, Proxy disconnect, activation waiting, binding filters, and monitor header UI.

**Tech Stack:** Swift, UIKit, SnapKit, SQLite.swift, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - Add Battery/AC/common Power Switch PID helpers.
  - Map `0x2A11` / `0x2A12` to the same panel types as `0x2A01` / `0x2A02`.
  - Preserve existing `isBatteryPowerSwitch` as Battery-only.

- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`
  - Add scan-time AC/common Power Switch recognition helpers.

- Modify: `SunSmart/devices_config.json`
  - Ensure `0x2A11` and `0x2A12` are registered as Switches with `ACPowerSwitch` icon category.
  - Preserve any already-present local edits in this file.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - Add `PJEightKeyPowerSwitchKind`.
  - Persist the selected kind on `PJEightKeySwitchData`.
  - Make existing sync-state checks work for Battery and AC real nodes.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  - Add SQLite column `powerSwitchKind`.
  - Default legacy rows to Battery.
  - Infer AC from a bound real AC node when metadata is legacy.

- Modify: `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`
  - Broaden `batteryPowerSwitchData` to return metadata for linked Battery or linked AC power switches while preserving unlinked semantics.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - Accept both Battery and AC nodes.
  - Enforce source virtual switch kind when binding/restoring.
  - Skip initial battery read request and Proxy disconnect for AC.

- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
  - Filter bind target candidates by the virtual switch kind.

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Use common Power Switch count/selection checks.
  - Let AC pass through default configuration.
  - Avoid battery read/disconnect because helper returns no request for AC.

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Same changes as classic add flow.

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - Restore Battery and AC using the same 8-key restore path.
  - Match restore source kind to replacement node kind.
  - Avoid AC battery read/disconnect.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift`
  - Add AC option metadata.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJSwitchesTypesVC.swift`
  - Add the AC option in the Switches popup, to the right of Battery Power Switch.

- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Wire AC popup action to virtual AC creation.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
  - Add `.acPowerSwitch` creation kind.
  - Save AC virtual switches with `powerSwitchKind = .ac`.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - Treat Battery and AC as linked power switches.
  - Skip activation prompt for AC before sync.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - Produce Battery header state or centered AC status state.
  - Use `node.state` for AC `Online` / `Offline`.
  - Use `Unlinked` for unbound virtual AC.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
  - Support Battery layout and centered status-only layout.

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - Skip battery refresh for AC.
  - Send AC TX Enable without activation waiting.
  - Keep Battery activation flow unchanged.

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Skip Battery-specific key-config waits and activation resync for AC.

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - Reuse existing action cases; no new cases are required unless compile errors reveal a naming boundary that must be made explicit.

- Modify: `SunSmart/en.lproj/Localizable.strings`
  - Add `neightkeyswitches_ac_power_switch`.

- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add `neightkeyswitches_ac_power_switch`.

- Verify only: `docs/superpowers/specs/260527_1917_ac_power_switch_design.md`
  - Source of truth for behavior.

---

### Task 1: Add Power Switch Device-Family Recognition

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`

- [ ] **Step 1: Verify current Battery-only recognition**

Run:

```bash
rg -n "batteryPowerSwitchProductIdentifiers|isACPowerSwitch|isPowerSwitch|powerSwitchKind|batteryPowerSwitchPanelType|var isBatteryPowerSwitch" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

- `batteryPowerSwitchProductIdentifiers` exists with `[0x2A01, 0x2A02]`.
- `isACPowerSwitch`, common `isPowerSwitch`, and `powerSwitchKind` do not exist yet.

- [ ] **Step 2: Add shared kind enum**

In `PJEightKeySwitchData.swift`, add this enum after imports and before `final class PJEightKeySwitchData`:

```swift
enum PJEightKeyPowerSwitchKind: Int {
    case battery = 0
    case ac = 1

    static let companyIdentifier: UInt16 = 0x0A78
    static let batteryProductIdentifiers: Set<UInt16> = [0x2A01, 0x2A02]
    static let acProductIdentifiers: Set<UInt16> = [0x2A11, 0x2A12]

    static func make(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> PJEightKeyPowerSwitchKind? {
        guard companyIdentifier == Self.companyIdentifier,
              let productIdentifier else {
            return nil
        }
        if batteryProductIdentifiers.contains(productIdentifier) {
            return .battery
        }
        if acProductIdentifiers.contains(productIdentifier) {
            return .ac
        }
        return nil
    }

    static func panelType(productIdentifier: UInt16?) -> PJEightKeySwitchPanelDefinition.PanelType? {
        switch productIdentifier {
        case 0x2A01, 0x2A11:
            return .scene8Key
        case 0x2A02, 0x2A12:
            return .brightness8Key
        default:
            return nil
        }
    }
}
```

- [ ] **Step 3: Add node recognition helpers**

In `MeshNetwork+SunSmart.swift`, replace the current Battery-only constants and `isBatteryPowerSwitch(companyIdentifier:productIdentifier:)` block with this compatible block:

```swift
    static let batteryPowerSwitchCompanyIdentifier: UInt16 = PJEightKeyPowerSwitchKind.companyIdentifier
    static let batteryPowerSwitchProductIdentifiers: Set<UInt16> = PJEightKeyPowerSwitchKind.batteryProductIdentifiers
    static let acPowerSwitchProductIdentifiers: Set<UInt16> = PJEightKeyPowerSwitchKind.acProductIdentifiers

    static func powerSwitchKind(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> PJEightKeyPowerSwitchKind? {
        PJEightKeyPowerSwitchKind.make(
            companyIdentifier: companyIdentifier,
            productIdentifier: productIdentifier
        )
    }

    static func isBatteryPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) == .battery
    }

    static func isACPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) == .ac
    }

    static func isPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) != nil
    }
```

In the `Node` extension near `var isBatteryPowerSwitch`, add:

```swift
    var powerSwitchKind: PJEightKeyPowerSwitchKind? {
        return Node.powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isACPowerSwitch: Bool {
        return Node.isACPowerSwitch(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isPowerSwitch: Bool {
        return Node.isPowerSwitch(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }
```

Update `batteryPowerSwitchPanelType` so it accepts AC:

```swift
    var batteryPowerSwitchPanelType: PJEightKeySwitchPanelDefinition.PanelType? {
        guard isPowerSwitch else {
            return nil
        }
        return PJEightKeyPowerSwitchKind.panelType(productIdentifier: productIdentifier)
    }
```

- [ ] **Step 4: Add provisioning-device helpers**

In `ProvisioningDevice+Add.swift`, keep `isBatteryPowerSwitch` and add:

```swift
    var powerSwitchKind: PJEightKeyPowerSwitchKind? {
        return PJEightKeyPowerSwitchKind.make(companyIdentifier: cid, productIdentifier: pid)
    }

    var isACPowerSwitch: Bool {
        return powerSwitchKind == .ac
    }

    var isPowerSwitch: Bool {
        return powerSwitchKind != nil
    }
```

- [ ] **Step 5: Run static check**

Run:

```bash
rg -n "isACPowerSwitch|isPowerSwitch|powerSwitchKind|acPowerSwitchProductIdentifiers|0x2A11|0x2A12" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

- AC PID constants appear in `PJEightKeySwitchData.swift`.
- `isBatteryPowerSwitch` still exists and remains Battery-only.
- `isACPowerSwitch` and `isPowerSwitch` exist for both `Node` and `ProvisioningDevice`.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "feat: recognize ac power switch devices"
```

---

### Task 2: Persist Power Switch Kind

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- Modify: `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`

- [ ] **Step 1: Add model property**

In `PJEightKeySwitchData.swift`, add this property near the other stored properties:

```swift
    var powerSwitchKind: PJEightKeyPowerSwitchKind = .battery
```

In `convenience init(baseSwitchData:metadata:)`, after `maxKeyCount = 8`, assign:

```swift
        powerSwitchKind = metadata.powerSwitchKind
```

In `copy()`, copy the value:

```swift
        copy.powerSwitchKind = powerSwitchKind
```

Add this helper near `needsBatteryPowerSwitchConfigurationSync`:

```swift
    var isACPowerSwitch: Bool {
        powerSwitchKind == .ac
    }

    var isBatteryPowerSwitchKind: Bool {
        powerSwitchKind == .battery
    }

    var requiresActivationBeforeOwnConfiguration: Bool {
        powerSwitchKind == .battery
    }
```

Update guards in `needsBatteryPowerSwitchConfigurationSync`, `needsBatteryPowerSwitchSync`, `needsBatteryPowerSwitchTxEnableSync`, `needsBatteryPowerSwitchLEDIndicatorSync`, and `displayStatus` from `proxyNode?.isBatteryPowerSwitch == true` to `proxyNode?.isPowerSwitch == true`.

- [ ] **Step 2: Extend repository metadata**

In `PJEightKeySwitchRepository.Metadata`, add:

```swift
        let powerSwitchKind: PJEightKeyPowerSwitchKind
```

Add a defaulted initializer parameter after `panelType`:

```swift
            powerSwitchKind: PJEightKeyPowerSwitchKind = .battery,
```

Assign it in the initializer:

```swift
            self.powerSwitchKind = powerSwitchKind
```

In `ExpressionKey`, add:

```swift
        static let powerSwitchKind = Expression<Int>("powerSwitchKind")
```

In table creation, add:

```swift
                builder.column(ExpressionKey.powerSwitchKind)
```

In `initDatabase()`, add this migration after the existing column checks begin:

```swift
            if !columns.contains(where: { $0.name == "powerSwitchKind" }) {
                _ = try? SunSmartDataManager.shared.db?.run(
                    table.addColumn(
                        ExpressionKey.powerSwitchKind,
                        defaultValue: PJEightKeyPowerSwitchKind.battery.rawValue
                    )
                )
            }
```

In `save(_:)`, add:

```swift
            ExpressionKey.powerSwitchKind <- switchData.powerSwitchKind.rawValue,
```

In `metadata(for:)`, compute kind before returning:

```swift
        let storedPowerSwitchKind = PJEightKeyPowerSwitchKind(rawValue: row[ExpressionKey.powerSwitchKind]) ?? .battery
        let inferredPowerSwitchKind = switchData.proxyNode?.powerSwitchKind
        let powerSwitchKind = inferredPowerSwitchKind ?? storedPowerSwitchKind
```

Then pass `powerSwitchKind: powerSwitchKind` to `Metadata(...)`.

- [ ] **Step 3: Preserve linked-only conversion semantics**

In `DeviceSwitchData.swift`, update `batteryPowerSwitchData` to support linked AC while still returning nil for unlinked base switch data:

```swift
    var batteryPowerSwitchData: PJEightKeySwitchData? {
        guard proxyNode?.isPowerSwitch == true else {
            return nil
        }
        if let switchData = self as? PJEightKeySwitchData {
            return switchData
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: self)
    }
```

- [ ] **Step 4: Run static check**

Run:

```bash
rg -n "powerSwitchKind|requiresActivationBeforeOwnConfiguration|isPowerSwitch == true" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift
```

Expected:

- Repository table, migration, save, metadata, and model copy paths all mention `powerSwitchKind`.
- Existing BPS sync guards now use `isPowerSwitch`.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift
git commit -m "feat: persist power switch kind"
```

---

### Task 3: Register AC Products and Add Popup Entry

**Files:**
- Modify: `SunSmart/devices_config.json`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJSwitchesTypesVC.swift`
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`

- [ ] **Step 1: Inspect local product-config edit before modifying**

Run:

```bash
git diff -- SunSmart/devices_config.json
```

Expected:

- Review the current local diff and preserve existing AC product edits if they are already present.

- [ ] **Step 2: Ensure devices config contains AC products**

In `SunSmart/devices_config.json`, ensure these two objects are present near the existing `2A01` / `2A02` Battery entries:

```json
    {
        "companyId": "0A78",
        "productId": "2A11",
        "categoryName": "AC Power Switch",
        "elementCount": 8,
        "iconCategory": "ACPowerSwitch",
        "deviceCategory": "Switches",
        "modelName": "SR-BL2422K8N-4SC-AC(US)"
    },
    {
        "companyId": "0A78",
        "productId": "2A12",
        "categoryName": "AC Power Switch",
        "elementCount": 8,
        "iconCategory": "ACPowerSwitch",
        "deviceCategory": "Switches",
        "modelName": "SR-BL2422K8N-4DIM-AC(US)"
    },
```

- [ ] **Step 3: Add localized title**

In `SunSmart/en.lproj/Localizable.strings`, add near `neightkeyswitches_battery_power_switch`:

```text
"neightkeyswitches_ac_power_switch" = "AC Power\nSwitch";
```

In `SunSmart/zh-Hans.lproj/Localizable.strings`, add near `neightkeyswitches_battery_power_switch`:

```text
"neightkeyswitches_ac_power_switch" = "AC 供电\n开关";
```

- [ ] **Step 4: Add AC option metadata**

In `PJSwitchesTypesViewModel.swift`, update `items` to include AC:

```swift
    let items: [Item] = [
        Item(imageName: "Kinetics_device", title: "kinetic_switch".localizedString),
        Item(imageName: "BatteryPowersw_device", title: "neightkeyswitches_battery_power_switch".localizedString),
        Item(imageName: "device_ACPowerSwitch", title: "neightkeyswitches_ac_power_switch".localizedString)
    ]
```

- [ ] **Step 5: Add AC callback and view**

In `PJSwitchesTypesVC.swift`:

Add property:

```swift
    private let onACSwitch: (() -> Void)?
```

Add lazy view after `batterySwitchView`:

```swift
    private lazy var acSwitchView: PJTopbtBoLabView = {
        PJTopbtBoLabView(
            imageName: viewModel.items[2].imageName,
            title: viewModel.items[2].title,
            target: self,
            action: #selector(acSwitchAction)
        )
    }()
```

Add initializer parameter and assignment:

```swift
        onACSwitch: (() -> Void)? = nil
```

```swift
        self.onACSwitch = onACSwitch
```

Update `makePopupViewController` to accept and pass `onACSwitch`.

Add action:

```swift
    @objc private func acSwitchAction() {
        dismissSheet { [onACSwitch] in
            onACSwitch?()
        }
    }
```

In `setupUI()`, add constraints:

```swift
        contentView.addSubview(acSwitchView)
        acSwitchView.snp.makeConstraints { make in
            make.left.equalTo(batterySwitchView.snp.right).offset(SCRXFrom(28))
            make.top.width.equalTo(kineticSwitchView)
        }
```

- [ ] **Step 6: Add AC creation kind**

In `PJPreAddEightKeySwitchesViewModel.CreationKind`, add:

```swift
        case acPowerSwitch
```

Add:

```swift
    var powerSwitchKind: PJEightKeyPowerSwitchKind? {
        switch creationKind {
        case .batteryPowerSwitch:
            return .battery
        case .acPowerSwitch:
            return .ac
        case .kineticSwitch:
            return nil
        }
    }
```

Update `init(space:switchData:)` to preserve existing kind:

```swift
        self.creationKind = switchData.powerSwitchKind == .ac ? .acPowerSwitch : .batteryPowerSwitch
```

Replace `isBatteryPowerSwitchPreCreate` with:

```swift
    var isPowerSwitchPreCreate: Bool {
        sourceSwitchData == nil && powerSwitchKind != nil
    }
```

In `buildSwitchData()`, after `moreSettingsState` assignment:

```swift
        if let powerSwitchKind {
            switchData.powerSwitchKind = powerSwitchKind
        }
```

Update the pre-create sync reset condition from `isBatteryPowerSwitchPreCreate` to `isPowerSwitchPreCreate`.

- [ ] **Step 7: Wire AC popup action**

In `DevicesViewController.swift`, update `PJSwitchesTypesVC.makePopupViewController` call to pass:

```swift
                    onACSwitch: { [weak self] in
                        guard let self = self else { return }
                        let vc = PJPreAddEightKeySwitchesVC(space: self.space, creationKind: .acPowerSwitch)
                        if isIPad {
                            vc.preferredContentSize = iPadPreferredContentSize
                        }
                        self.present(NavigationViewController(rootViewController: vc), animated: true)
                    }
```

- [ ] **Step 8: Run static check**

Run:

```bash
rg -n "neightkeyswitches_ac_power_switch|acPowerSwitch|onACSwitch|device_ACPowerSwitch|2A11|2A12" SunSmart/devices_config.json SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJSwitchesTypesVC.swift SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
```

Expected:

- AC title is localized in both string files.
- Popup view model contains the AC image and title.
- Popup controller exposes `onACSwitch`.
- Devices view controller creates `.acPowerSwitch`.
- Product config contains both AC PIDs.

- [ ] **Step 9: Commit Task 3**

Run:

```bash
git add SunSmart/devices_config.json SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJSwitchesTypesVC.swift SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
git commit -m "feat: add ac power switch creation entry"
```

---

### Task 4: Enforce AC/Battery Binding and Configure Add Flow

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Filter bind target by kind**

In `DeviceAddViewController.swift`, update `AddDeviceBindTarget.allows(_ device:)` for `.batteryPowerSwitch`:

```swift
        case .batteryPowerSwitch(let switchData):
            return device.powerSwitchKind == switchData.powerSwitchKind
```

Update `allows(_ node:)`:

```swift
        case .batteryPowerSwitch(let switchData):
            return node.powerSwitchKind == switchData.powerSwitchKind
```

- [ ] **Step 2: Set kind when creating default switch from real node**

In `MeshNetwork+SunSmart.swift`, update `createDefaultSwitch(forBatteryPowerSwitch:)`:

```swift
        guard node.isPowerSwitch,
              let powerSwitchKind = node.powerSwitchKind else {
            return nil
        }
```

When creating metadata:

```swift
        let metadata = PJEightKeySwitchRepository.Metadata(
            panelType: panelType,
            powerSwitchKind: powerSwitchKind,
            moreSettingsState: .default
        )
```

- [ ] **Step 3: Expand add configuration support**

In `BatteryPowerSwitchAddConfiguration.isSupportedAddNode(_:)`, replace Battery-only checks with:

```swift
        return node.isPowerSwitch
```

In `prepareSwitchData(for:)`, after the switch is made:

```swift
        if let kind = node.powerSwitchKind {
            switchData.powerSwitchKind = kind
        }
```

In `prepareLinkedSwitchData(sourceSwitchData:node:)`, after `isSupportedAddNode(node)` guard, add:

```swift
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind else {
            return .failure(.unsupportedNode)
        }
```

In `prepareRestoreSwitchData(sourceSwitchData:node:)`, after `isSupportedAddNode(node)` guard, add the same kind check:

```swift
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind else {
            return .failure(.unsupportedNode)
        }
```

When linked or restore data is copied, preserve kind:

```swift
        switchData.powerSwitchKind = sourceSwitchData.powerSwitchKind
```

- [ ] **Step 4: Skip AC initial battery read**

In `BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(for:node:)`, add:

```swift
        guard node.isBatteryPowerSwitch else {
            return nil
        }
```

In `readInitialBatteryLevelsAndDisconnect`, update fallback filtering to Battery only:

```swift
            .filter { $0.isBatteryPowerSwitch && !requestAddresses.contains($0.primaryUnicastAddress) }
```

Keep `disconnectBatteryPowerSwitchNode(address:)` Battery-only by leaving its `isSupportedAddNode` guard and adding:

```swift
              node.isBatteryPowerSwitch else {
```

- [ ] **Step 5: Use common Power Switch checks in add controllers**

In both `DeviceAddClassicModeController.swift` and `DeviceAddProfessionalModeController.swift`, replace scan and limit checks:

```swift
device.isBatteryPowerSwitch
```

with:

```swift
device.isPowerSwitch
```

for selection limit and `isBatteryPowerSwitchLimitExceeded`.

Keep final notification checks broader:

```swift
if self.addSuccessNodes.contains(where: { $0.isPowerSwitch }) {
    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
}
```

Update add-success request creation:

```swift
                if node.isPowerSwitch,
                   let request = finalizeBatteryPowerSwitchAddConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
```

- [ ] **Step 6: Run static check**

Run:

```bash
rg -n "isPowerSwitch|powerSwitchKind == sourceSwitchData.powerSwitchKind|makeInitialBatteryReadRequest|readInitialBatteryLevelsAndDisconnect|addSuccessNodes.contains\\(where: \\{ \\$0.isPowerSwitch" SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- Bind target filters compare kind.
- Add controllers use `isPowerSwitch` for Battery and AC discovery.
- Battery read helper remains Battery-only.

- [ ] **Step 7: Commit Task 4**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "feat: bind ac power switches by kind"
```

---

### Task 5: Extend Restore Flow for AC

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Replace restore recognition with common Power Switch**

In `DeviceRestoreViewController.swift`, update helper `isBatteryPowerSwitchRestore(oldNode:newNode:)` to allow either kind and require matching kind:

```swift
    private func isBatteryPowerSwitchRestore(oldNode: Node, newNode: Node) -> Bool {
        guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(newNode),
              let switchData = batteryPowerSwitchData(boundTo: oldNode) else {
            return false
        }
        return switchData.powerSwitchKind == newNode.powerSwitchKind
    }
```

- [ ] **Step 2: Preserve kind during restore preparation**

In `prepareBatteryPowerSwitchRestoreConfiguration`, rely on `BatteryPowerSwitchAddConfiguration.prepareRestoreSwitchData` kind matching from Task 4. Confirm failure path stores the unsupported-node message when kind mismatches.

Run:

```bash
rg -n "prepareRestoreSwitchData|failedBatteryPowerSwitchRestoreReasons|unsupportedNode" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- Restore controller calls `prepareRestoreSwitchData`.
- Add configuration helper contains kind mismatch guard.

- [ ] **Step 3: Skip AC battery read and disconnect through helper behavior**

In `DeviceRestoreViewController.swift`, update Battery-only success-node collection near restore completion:

```swift
        let addedBatteryPowerSwitchNodes = restoreNodes.filter { $0.isBatteryPowerSwitch }
```

Keep this Battery-only. AC nodes must not be included in fallback disconnect nodes.

- [ ] **Step 4: Run static check**

Run:

```bash
rg -n "isBatteryPowerSwitchRestore|addedBatteryPowerSwitchNodes|isBatteryPowerSwitch|isPowerSwitch" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- Restore detection allows common Power Switch through helper and matching kind.
- Fallback disconnect list remains Battery-only.

- [ ] **Step 5: Commit Task 5**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "feat: support ac power switch restore"
```

---

### Task 6: Skip Battery Activation Waits for AC Sync and Save

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Treat AC as linked power switch in editor**

In `PJPreAddEightKeySwitchesVC.swift`, update:

```swift
    private func isBatteryPowerSwitchLinked(_ switchData: DeviceSwitchData) -> Bool {
        switchData.proxyNode?.isPowerSwitch == true
    }
```

Any guard using `switchData.proxyNode?.isBatteryPowerSwitch == true` for linked Power Switch editor behavior should use `isPowerSwitch`.

- [ ] **Step 2: Skip activation before editor sync for AC**

In `submitBatteryPowerSwitch(_:)`, replace:

```swift
            presentBatteryPowerSwitchActivation(for: switchData)
```

with:

```swift
            if switchData.requiresActivationBeforeOwnConfiguration {
                presentBatteryPowerSwitchActivation(for: switchData)
            } else {
                pushBatteryPowerSwitchSync(switchData)
            }
```

- [ ] **Step 3: Skip activation before monitor sync for AC**

In `PJEightKeySwitchMonitorVC.pushBatteryPowerSwitchSync()`, replace:

```swift
        if needsConfigurationSync {
            presentBatteryPowerSwitchActivation()
        } else {
            pushBatteryPowerSwitchSyncController()
        }
```

with:

```swift
        if needsConfigurationSync && viewModel.switchData.requiresActivationBeforeOwnConfiguration {
            presentBatteryPowerSwitchActivation()
        } else {
            pushBatteryPowerSwitchSyncController()
        }
```

- [ ] **Step 4: Skip SyncDevices key-config delays for AC**

In `SyncDevicesViewController.beginSyncRun()`, update the delay setup:

```swift
        if batteryPowerSwitchDataForSync?.requiresActivationBeforeOwnConfiguration == true {
            batteryPowerSwitchKeyConfigEarliestDate = Date().addingTimeInterval(Self.batteryPowerSwitchKeyConfigInitialDelay)
        } else {
            batteryPowerSwitchKeyConfigEarliestDate = nil
        }
```

In `waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded(for:)`, add this guard:

```swift
        guard batteryPowerSwitchDataForSync?.requiresActivationBeforeOwnConfiguration == true else {
            return
        }
```

In any caller that starts `startBatteryPowerSwitchConfigurationResyncAfterActivation()`, guard it with:

```swift
if batteryPowerSwitchDataForSync?.requiresActivationBeforeOwnConfiguration == true {
    startBatteryPowerSwitchConfigurationResyncAfterActivation()
}
```

- [ ] **Step 5: Run static check**

Run:

```bash
rg -n "requiresActivationBeforeOwnConfiguration|startBatteryPowerSwitchConfigurationResyncAfterActivation|batteryPowerSwitchKeyConfigEarliestDate|isPowerSwitch == true" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- Editor and monitor sync only present activation flow for Battery kind.
- Sync controller delay is only configured for Battery kind.

- [ ] **Step 6: Commit Task 6**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: skip activation waits for ac power switch"
```

---

### Task 7: Add AC Monitor Header and Direct TX Enable

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Extend header state**

In `PJEightKeySwitchMonitorViewModel.HeaderState`, add:

```swift
        enum Layout {
            case battery
            case centeredStatus
        }
```

Add property:

```swift
        let layout: Layout
```

In `headerState`, branch by kind:

```swift
        if switchData.powerSwitchKind == .ac {
            return acHeaderState()
        }
```

Add this helper in the private extension:

```swift
    func acHeaderState() -> HeaderState {
        if isUnlinkedVirtualBatteryPowerSwitch {
            return HeaderState(
                batteryText: "",
                batteryIconSystemName: "",
                statusPrefixText: "",
                statusText: "neightkeyswitches_unlinked".localizedString,
                statusColor: RGB(148, 163, 184),
                updatedText: "",
                style: .unlinked,
                showsRefreshButton: false,
                layout: .centeredStatus
            )
        }

        let online = informationNode?.state == true
        return HeaderState(
            batteryText: "",
            batteryIconSystemName: "",
            statusPrefixText: "",
            statusText: online ? "online".localizedString : "Offline".localizedString,
            statusColor: online ? RGB(69, 197, 122) : RGB(148, 163, 184),
            updatedText: "",
            style: online ? .normal : .unknown,
            showsRefreshButton: false,
            layout: .centeredStatus
        )
    }
```

In the existing Battery return, pass `layout: .battery`.

- [ ] **Step 2: Extend header view state and layout**

In `PJEightKeySwitchMonitorHeaderView.State`, add:

```swift
        enum Layout {
            case battery
            case centeredStatus
        }

        let layout: Layout
```

In `configure(state:)`, add:

```swift
        statusPrefixLabel.isHidden = state.statusPrefixText.isEmpty
        apply(layout: state.layout)
```

Add layout helper:

```swift
    private func apply(layout: State.Layout) {
        switch layout {
        case .battery:
            batteryIconView.isHidden = false
            batteryLabel.isHidden = false
            updatedLabel.isHidden = false
            statusStackView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(batteryLabel.snp.right).offset(SCRXFrom(24))
            }
            updatedLabel.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(statusStackView.snp.right).offset(SCRXFrom(24))
                make.right.equalTo(refreshButton.snp.left).offset(-SCRXFrom(4))
            }
        case .centeredStatus:
            batteryIconView.isHidden = true
            batteryLabel.isHidden = true
            updatedLabel.isHidden = true
            refreshButton.isHidden = true
            statusStackView.snp.remakeConstraints { make in
                make.center.equalToSuperview()
            }
            updatedLabel.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.centerY.equalToSuperview()
            }
        }
    }
```

- [ ] **Step 3: Pass layout from monitor controller**

In `PJEightKeySwitchMonitorVC.updateUI()`, pass:

```swift
            layout: header.layout == .battery ? .battery : .centeredStatus
```

- [ ] **Step 4: Disable AC battery refresh path**

In `PJEightKeySwitchMonitorViewModel.canRefreshBattery`, update:

```swift
        switchData.powerSwitchKind == .battery && switchData.proxyNode?.isBatteryPowerSwitch == true && space.permission != .visitor
```

In `PJEightKeySwitchMonitorVC.refreshMonitor()`, add before node lookup:

```swift
        guard viewModel.switchData.powerSwitchKind == .battery else {
            return
        }
```

- [ ] **Step 5: Send AC TX Enable without activation flow**

In `PJEightKeySwitchMonitorVC.startTxEnableUpdate(_:)`, after setting `pendingEnabledValue` and `updateUI()`, branch:

```swift
        if viewModel.switchData.powerSwitchKind == .ac {
            sendACTxEnable(isEnabled)
            return
        }
```

Add helper:

```swift
    private func sendACTxEnable(_ isEnabled: Bool) {
        guard let node = viewModel.informationNode else {
            pendingEnabledValue = nil
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            updateUI()
            return
        }

        MeshBatteryPowerSwitchTxEnableSender().sendTxEnable(isEnabled, to: node) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                if succeeded {
                    self.viewModel.applyTxEnableSucceeded(isEnabled)
                    self.viewModel.persist()
                    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                } else {
                    XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                }
                self.pendingEnabledValue = nil
                self.updateUI()
            }
        }
    }
```

- [ ] **Step 6: Run static check**

Run:

```bash
rg -n "centeredStatus|acHeaderState|sendACTxEnable|canRefreshBattery|powerSwitchKind == \\.battery|powerSwitchKind == \\.ac" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- Header supports centered AC status.
- AC refresh path is disabled.
- AC TX Enable path does not instantiate `PJEightKeySwitchTxEnableFlow`.

- [ ] **Step 7: Commit Task 7**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: show ac power switch online status"
```

---

### Task 8: Build and Regression Verification

**Files:**
- Verify: all modified Swift, JSON, strings, and asset files.

- [ ] **Step 1: Confirm no forbidden broad formatting or unrelated files**

Run:

```bash
git status --short
```

Expected:

- Only files intentionally modified by the AC Power Switch implementation are staged or modified.
- Protocol files under `protocols/` may remain untracked and must not be committed by implementation commits unless explicitly requested.

- [ ] **Step 2: Run Swift compile build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run targeted static checks**

Run:

```bash
rg -n "GenericBatteryGet|disconnectProxy|PJEightKeySwitchActivationFlow|PJEightKeySwitchTxEnableFlow|batteryPowerSwitchKeyConfigInitialDelay" SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Controller SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `GenericBatteryGet` is still only in the Battery refresh/read flow.
- `disconnectProxy` for power switches is still Battery-only.
- AC save/sync branches do not call activation flow.
- AC TX Enable branch does not call `PJEightKeySwitchTxEnableFlow`.

- [ ] **Step 4: Verify device config parsing risk**

Run:

```bash
plutil -lint SunSmart/devices_config.json
```

Expected:

- `SunSmart/devices_config.json: OK`

- [ ] **Step 5: Verify localization syntax**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- Both files report `OK`.

- [ ] **Step 6: Commit verification fixes only when actual files changed**

Run:

```bash
git status --short
```

Expected:

- If verification produced no additional source changes, do not create an empty commit.
- If verification produced source fixes, stage only the exact files shown by `git status --short` that belong to AC Power Switch implementation, then commit with:

```bash
git commit -m "fix: stabilize ac power switch build"
```

---

## Self-Review

- Spec coverage: This plan covers AC PID recognition, persisted virtual AC kind, kind-restricted binding, add/restore behavior, no AC battery read, no AC Proxy disconnect, no AC activation wait, AC monitor `Online`/`Offline`/`Unlinked`, shared 16-switch limit, localizations, product config, and build verification.
- Red-flag scan: No incomplete-token markers or unspecified implementation steps are present.
- Type consistency: The plan uses `PJEightKeyPowerSwitchKind`, `powerSwitchKind`, `isACPowerSwitch`, `isPowerSwitch`, and `requiresActivationBeforeOwnConfiguration` consistently across model, node, provisioning, add, restore, sync, and UI tasks.
