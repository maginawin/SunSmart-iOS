# Battery Power Switch Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从 `PJEightKeySwitchMonitorVC` 右上角菜单进入真实 Battery Power Switch 的 Information 页面，并按 BPS 自身 mesh node、target groups、Scene Profile 配置展示内容。

**Architecture:** 复用 `DeviceInformationViewController` 的 light information 样式和表格交互，只增加轻量配置能力。`PJEightKeySwitchMonitorViewModel` 负责把 BPS 信息页所需的节点、Group 摘要、Scene 摘要暴露给 VC；`PJEightKeySwitchMonitorVC` 只负责菜单显隐和 push。

**Tech Stack:** UIKit, Swift, SnapKit, NordicSigMeshSDK, 现有 `DeviceInformationViewController` / `PJEightKeySwitchMonitorVC` / `PJEightKeySwitchMonitorViewModel`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
  - 增加 `DeviceInfoDisplayMode`。
  - 增加 `sceneTextOverride`。
  - 让 BPS 可强制展示 9 个 Device 字段，并让 Scene section 支持摘要模式。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - 增加 Information 相关只读 helper。
  - helper 只读，不触发 sync、save 或通知。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - Information 菜单仅真实 BPS 显示。
  - 点击后 push 复用的 `DeviceInformationViewController`。

- No new test files:
  - 当前工程没有针对这些 UIKit controller 的现成单元测试入口。
  - 本计划使用代码级检查、编译和手动 UI 验证覆盖风险点。

---

### Task 1: Extend DeviceInformationViewController Configuration

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift:15-139`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift:167-207`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift:240-286`

- [ ] **Step 1: Add explicit display configuration**

In `DeviceInformationViewController`, add a display mode enum and scene override storage near the existing properties.

```swift
private enum DeviceInfoDisplayMode {
    case standard
    case full
}

private var tableView: UITableView!

private var sections: [SectionType] = [.deviceInfo, .group, .scene]
private var sectionShowMap: [SectionType: Bool] = [:]
private var deviceInfoModels: [CustomCellModel] = []

let node: Node
private let emptyGroupText: String
private let groupTextOverride: String?
private let sceneTextOverride: String?
private let deviceInfoDisplayMode: DeviceInfoDisplayMode
```

- [ ] **Step 2: Update initializer without changing existing call sites**

Replace the initializer with this version. Existing callers keep the same behavior because the new parameters have defaults.

```swift
init(
    node: Node,
    emptyGroupText: String? = nil,
    showsSceneSection: Bool = true,
    groupTextOverride: String? = nil,
    sceneTextOverride: String? = nil,
    showsFullDeviceInfo: Bool = false
) {
    self.node = node
    self.emptyGroupText = emptyGroupText ?? "device_not_added_group".localizedString
    self.groupTextOverride = groupTextOverride
    self.sceneTextOverride = sceneTextOverride
    self.deviceInfoDisplayMode = showsFullDeviceInfo ? .full : .standard
    self.sections = showsSceneSection ? [.deviceInfo, .group, .scene] : [.deviceInfo, .group]
    super.init(nibName: nil, bundle: nil)
}
```

- [ ] **Step 3: Make full Device rows reusable**

Replace `setupDeviceInfoDataSource()` with this implementation. This keeps standard light behavior unchanged and enables BPS to show PID / Address / Version Identifier outside DEBUG.

```swift
/// 设备数据
private func setupDeviceInfoDataSource() {
    var name = node.name ?? ""
    if let group = node.group, SpaceViewController.currentSpace()?.displayDeviceNamePrefix ?? false {
        name = "\(group.name)-\(name)"
    }
    let nameModel = CustomCellModel(title: "name".localizedString, content: name, style: .none)

    let macModel = CustomCellModel(icon: UIImage(named: "copy"), title: "MAC", content: node.macAddressResult, style: .icon)

    let pidContent = node.productIdentifier.map { "0x\($0.hex)" } ?? "--"
    let pidModel = CustomCellModel(title: "PID".localizedString, content: pidContent, style: .none)

    let addressModel = CustomCellModel(title: "address".localizedString, content: "\(node.primaryUnicastAddress)", style: .none)

    let vidModel = CustomCellModel(title: "Version Identifier", content: node.versionIdentifier != nil ? "\(node.versionIdentifier!)" : "--", style: .none)

    let devModel = CustomCellModel(title: "model".localizedString, content: node.modelName ?? "--", style: .none)

    let typeName = node.categoryName
    let deviceTypeModel = CustomCellModel(title: "device_type".localizedString, content: typeName ?? "--", style: .none)

    let firmwareModel = CustomCellModel(title: "firmware".localizedString, content: node.firmwareVersion ?? "--", style: .none)

    let singleStrengthModel = CustomCellModel(title: "signal_strength".localizedString, content: node.rssi != nil ? "\(node.rssi!)dB" : "--", style: .none)

    switch deviceInfoDisplayMode {
    case .full:
        deviceInfoModels = [nameModel, macModel, pidModel, addressModel, vidModel, devModel, deviceTypeModel, firmwareModel, singleStrengthModel]
    case .standard:
        #if DEBUG
        deviceInfoModels = [nameModel, macModel, pidModel, addressModel, vidModel, devModel, deviceTypeModel, firmwareModel, singleStrengthModel]
        #else
        deviceInfoModels = [nameModel, macModel, devModel, deviceTypeModel, firmwareModel, singleStrengthModel]
        #endif
    }
}
```

- [ ] **Step 4: Make Scene section support summary override**

In `tableView(_:numberOfRowsInSection:)`, replace the `.scene` case with:

```swift
case .scene:
    guard sceneTextOverride == nil else {
        return 0
    }
    let sceneCount = node.scenes.count
    let isShow = sectionShowMap[sectionType] ?? false
    return (isShow && sceneCount > 0) ? sceneCount : 0
```

In `tableView(_:viewForHeaderInSection:)`, replace the `.scene` case with:

```swift
case .scene:
    headerView.titleLabel.text = "scene".localizedString
    if let sceneTextOverride {
        headerView.contentLabel.isHidden = false
        headerView.contentLabel.text = sceneTextOverride
    } else if node.scenes.count > 0 {
        headerView.showImageView.isHidden = false
        let isShow = sectionShowMap[sectionType] ?? false
        headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
    } else {
        headerView.contentLabel.isHidden = false
        headerView.contentLabel.text = "device_not_added_scene".localizedString
    }
```

- [ ] **Step 5: Prevent row access for summary Scene sections**

At the start of the `else` branch in `cellForRowAt`, before `let scene = node.scenes[indexPath.row]`, add a defensive guard:

```swift
guard sceneTextOverride == nil else {
    return cell
}
```

The resulting non-device branch should begin:

```swift
} else {
    guard sceneTextOverride == nil else {
        return cell
    }
    let scene = node.scenes[indexPath.row]
    cell.cellStyle = .none
```

- [ ] **Step 6: Run targeted source checks**

Run:

```bash
rg -n "DeviceInfoDisplayMode|sceneTextOverride|showsFullDeviceInfo" SunSmart/Main/Device/Controller/DeviceInformationViewController.swift
```

Expected:

- `DeviceInfoDisplayMode` appears in the enum declaration and mode switch.
- `sceneTextOverride` appears in the property list, initializer, scene row count, scene header, and defensive cell guard.
- `showsFullDeviceInfo` appears in the initializer signature and mode assignment.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceInformationViewController.swift
git commit -m "feat: configure device information display"
```

---

### Task 2: Add Battery Power Switch Information Helpers

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift:69-81`

- [ ] **Step 1: Add read-only helper properties**

In `PJEightKeySwitchMonitorViewModel`, add these properties after `title` and before `needsBatteryPowerSwitchSync`.

```swift
var isRealBatteryPowerSwitch: Bool {
    informationNode != nil
}

var informationNode: Node? {
    guard let node = switchData.proxyNode, node.isBatteryPowerSwitch else {
        return nil
    }
    return node
}

var informationGroupText: String? {
    let names = switchData.bindGroups.map(\.name)
    return names.isEmpty ? nil : names.joined(separator: ", ")
}

var showsInformationSceneSection: Bool {
    switchData.eightKeyPanelType == .scene8Key
}

var informationSceneText: String? {
    guard showsInformationSceneSection else {
        return nil
    }
    let names = [switchData.sceneA, switchData.sceneB, switchData.sceneC, switchData.sceneD]
        .compactMap { $0?.name }
    return names.isEmpty ? nil : names.joined(separator: ", ")
}
```

- [ ] **Step 2: Verify helper names and imports**

Run:

```bash
rg -n "isRealBatteryPowerSwitch|informationNode|informationGroupText|showsInformationSceneSection|informationSceneText" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
```

Expected:

- Each helper appears exactly once in the view model.
- The file already imports `NordicSigMeshSDK`, so `Node` resolves without new imports.

- [ ] **Step 3: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
git commit -m "feat: expose switch information state"
```

---

### Task 3: Wire Information Menu Entry and Navigation

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:46-70`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:238-280`

- [ ] **Step 1: Gate the Information menu item**

In `moreAction()`, replace the unconditional Information item:

```swift
items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { _ in
   //information
}))
```

with:

```swift
if viewModel.isRealBatteryPowerSwitch {
    items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
        self?.pushInformation()
    }))
}
```

- [ ] **Step 2: Add pushInformation()**

Add this method near `presentForcedAutoPopup()` and before `pushBatteryPowerSwitchSync()`:

```swift
private func pushInformation() {
    guard let node = viewModel.informationNode else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }

    let groupText = viewModel.informationGroupText ?? "Not yet linked to a group".localizedString
    let sceneText = viewModel.informationSceneText ?? "Not yet linked to a scene".localizedString
    let vc = DeviceInformationViewController(
        node: node,
        emptyGroupText: "Not yet linked to a group".localizedString,
        showsSceneSection: viewModel.showsInformationSceneSection,
        groupTextOverride: groupText,
        sceneTextOverride: sceneText,
        showsFullDeviceInfo: true
    )
    navigationController?.pushViewController(vc, animated: true)
}
```

- [ ] **Step 3: Run targeted source checks**

Run:

```bash
rg -n "pushInformation|menu_information|showsFullDeviceInfo|Not yet linked to a scene" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `pushInformation` appears in the menu callback and method declaration.
- `menu_information` is inside an `if viewModel.isRealBatteryPowerSwitch` block.
- `showsFullDeviceInfo: true` is passed to `DeviceInformationViewController`.
- `Not yet linked to a scene` appears in `pushInformation()`.

- [ ] **Step 4: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: open switch information page"
```

---

### Task 4: Build and Regression Verification

**Files:**
- Verify only.

- [ ] **Step 1: Confirm final diff scope**

Run:

```bash
git status --short
```

Expected:

- No modified source files remain unstaged after Task 1-3 commits.
- Existing unrelated untracked docs may still appear:
  - `docs/260519_1400_pj_eight_key_switch_monitor_issues.md`
  - `docs/260519_1405_pj_eight_key_switch_monitor_fix_plan.md`

- [ ] **Step 2: Confirm DeviceInformation default call sites still compile at source level**

Run:

```bash
rg -n "DeviceInformationViewController\\(" SunSmart/Main
```

Expected call sites:

- `DeviceBaseViewController`
- `DeviceLightViewController`
- `PJNGatewayViewController`
- `EmerFireAlarmMonitorRouting`
- `PJEightKeySwitchMonitorVC`

Existing call sites do not need new parameters because the initializer defaults preserve compatibility.

- [ ] **Step 3: Build SunSmart**

Run the project-approved build command directly, without shell wrapping and without output redirection:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- No compile error for `DeviceInfoDisplayMode`, `sceneTextOverride`, `Node`, `DeviceInformationViewController` initializer, or `pushInformation()`.

- [ ] **Step 4: Manual UI verification on a real BPS-backed switch**

Use an existing real Battery Power Switch whose `switchData.proxyNode?.isBatteryPowerSwitch == true`.

Expected:

- Right-top menu shows `Information`.
- Tapping `Information` pushes the information page.
- Device section shows:
  - `Name`
  - `MAC`
  - `PID`
  - `Address`
  - `Version Identifier`
  - `Model`
  - `Device Type`
  - `Firmware`
  - `Signal strength`
- `MAC` equals `node.macAddressResult`.
- MAC row still copies value and shows `copy_success`.

- [ ] **Step 5: Manual UI verification on a virtual BPS switch**

Use a virtual switch whose `switchData.proxyNode?.isBatteryPowerSwitch != true`.

Expected:

- Right-top menu does not show `Information`.
- Existing Edit, Delete, Identify menu behavior remains unchanged.

- [ ] **Step 6: Manual Group / Scene verification**

Use one Scene Profile BPS and one Brightness Profile BPS.

Expected:

- Scene Profile with scenes: Scene section appears and shows configured scene names joined by `, `.
- Scene Profile without scenes: Scene section appears and shows `Not yet linked to a scene`.
- Brightness Profile: Scene section is absent.
- With target groups: Group section shows target group names joined by `, `.
- Without target groups: Group section shows `Not yet linked to a group`.

- [ ] **Step 7: Manual regression verification**

Open existing non-BPS information pages.

Expected:

- Light information still uses the original Device row behavior: PID / Address / Version Identifier are DEBUG-only.
- Light Scene section still expands to scene rows when scenes exist.
- FireAlarm information still uses its group override and still hides Scene section.

---

## Self-Review

- Spec coverage:
  - Real BPS menu entry: Task 3.
  - Virtual BPS no menu entry: Task 3 and Task 4 Step 5.
  - Device rows and MAC source: Task 1 and Task 4 Step 4.
  - Group summary: Task 2, Task 3, Task 4 Step 6.
  - Scene Profile only: Task 2, Task 3, Task 4 Step 6.
  - Light / FireAlarm regression: Task 1 defaults and Task 4 Step 7.

- Placeholder scan:
  - No placeholder markers or unspecified implementation steps.
  - Each code change step includes the exact Swift code to add or replace.

- Type consistency:
  - `DeviceInfoDisplayMode`, `sceneTextOverride`, `showsFullDeviceInfo`, `isRealBatteryPowerSwitch`, `informationNode`, `informationGroupText`, `showsInformationSceneSection`, and `informationSceneText` are defined before later tasks reference them.
  - `DeviceInformationViewController` initializer defaults preserve existing call sites.
