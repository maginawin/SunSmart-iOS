# Scene OFF Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an OFF button to the Scene control popup and make Preview, SAVE, add-to-group scene sync, restore scene sync, and success checks treat OFF as `SceneExecuteData.isOn == false`.

**Architecture:** Keep storage unchanged by using the existing `SceneExecuteData.isOn` field and `lightness = 0`. Put UI state in `ExecuteSceneData` and `SceneExecuteDataPickerView`, and put device sync behavior in `Scene.getSyncMessageHandles(node:data:)` so all scene sync entry points share the same command generation. Update Sync device(s) response handling and operation success checks to match the actual OnOff command used for OFF scenes.

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, existing MeshAPI and Sync device(s) models.

---

### Task 1: Add OFF State To Scene Picker And UI Data

**Files:**
- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`

- [ ] **Step 1: Update picker callback signature and state**

In `SceneExecuteDataPickerView`, change the callback and add OFF state fields:

```swift
typealias DataPickerCallback = ((Bool, Int, Int)->Void)
```

Add these properties near the existing `showCct`, `lightness`, and `cct` properties:

```swift
private var offBtn: UIButton!
private var isOn: Bool = true
private var maximumLightness: Int {
    lightnessLimitRange?.upperBound ?? 100
}
```

Change `show(...)` to accept and store `isOn`:

```swift
static func show(lightness: Int = 100, isOn: Bool? = nil, cct: Int = 4500, lightnessLimitRange: ClosedRange<Int>? = nil, cctRange: ClosedRange<UInt16> = NodeAbsoluteCctRange.defaultRange, showCct: Bool = true, showDelete: Bool = true, picker: DataPickerCallback?, delete: DeleteCallback? = nil) {
    
    let pickerView = SceneExecuteDataPickerView(frame: UIScreen.main.bounds)
    pickerView.showDelete = showDelete
    pickerView.showCct = showCct
    pickerView.lightness = lightness
    pickerView.isOn = isOn ?? lightness > 0
    pickerView.cctRange = cctRange
    pickerView.lightnessLimitRange = lightnessLimitRange
    pickerView.pickerCallback = picker
    pickerView.deleteCallback = delete
    pickerView.cct = cct
    pickerView.setupUI()
    pickerView.tag = 100
    UIApplication.shared.keyWindow().addSubview(pickerView)
    pickerView.showAnimation()
}
```

- [ ] **Step 2: Add OFF button UI and state helpers**

Add these methods in `SceneExecuteDataPickerView` before `setupUI()`:

```swift
private var selectedIsOn: Bool {
    lightnessSliderView.value > 0
}

private func updateOffButtonState() {
    let isOff = !isOn
    offBtn.backgroundColor = isOff ? RGB(102, 103, 171) : .white
    offBtn.setTitleColor(isOff ? .white : RGB(102, 103, 171), for: .normal)
    offBtn.layer.borderWidth = isOff ? 0 : 1
    offBtn.layer.borderColor = RGB(147, 148, 196).cgColor
}

private func setLightnessValue(_ value: Int) {
    lightnessSliderView.value = value
    lightnessLabel.text = "\(lightnessSliderView.value)%"
    isOn = lightnessSliderView.value > 0
    updateOffButtonState()
}

@objc private func offBtnAction() {
    if isOn {
        setLightnessValue(0)
    } else {
        setLightnessValue(maximumLightness)
    }
}
```

Update `confirmBtnAction()` and `shadeViewAction()` so they pass `selectedIsOn`:

```swift
let lightness = lightnessSliderView.value
let cct = selectedCct
pickerCallback?(selectedIsOn, lightness, cct)
```

- [ ] **Step 3: Place OFF button and allow brightness lower bound 0**

In `setupUI()`, change content height:

```swift
let contentHeight = showCct ? SCRYFrom(244) : SCRYFrom(146)
```

After creating `contentView`, add the OFF button:

```swift
offBtn = UIButton(title: "OFF", titleSize: 12, titleWeight: .medium, titleColor: RGB(102, 103, 171), target: self, action: #selector(offBtnAction))
offBtn.layer.cornerRadius = SCRYFrom(10)
offBtn.layer.borderWidth = 1
offBtn.layer.borderColor = RGB(147, 148, 196).cgColor
contentView.addSubview(offBtn)
offBtn.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(20))
    make.top.equalTo(SCRYFrom(16))
    make.width.equalTo(SCRXFrom(52))
    make.height.equalTo(SCRYFrom(32))
}
```

When clamping initial brightness, keep using the passed range, but callers will pass `0...highEndTrim` for scene settings:

```swift
var lightnessValue = isOn ? lightness : 0
if let range = lightnessLimitRange {
    lightnessValue = max(range.lowerBound, min(range.upperBound, lightnessValue))
}
if lightnessValue == 0 {
    isOn = false
}
```

Change the lightness label top constraint:

```swift
make.top.equalTo(SCRYFrom(48))
```

Change the lightness value callback:

```swift
lightnessSliderView.valueChangedCallback = {[weak self] value in
    self?.lightnessLabel.text = "\(value)%"
    self?.isOn = value > 0
    self?.updateOffButtonState()
}
```

After laying out the slider, call:

```swift
updateOffButtonState()
```

- [ ] **Step 4: Add `isOn` to `ExecuteSceneData`**

In `SceneAddViewController.swift`, update `ExecuteSceneData`:

```swift
class ExecuteSceneData {
    /// 是否开启
    var isOn: Bool
    /// 亮度 0~100
    var lightness: Int
    /// 色温
    var cct: Int
    
    init(isOn: Bool = true, lightness: Int, cct: Int) {
        self.isOn = isOn
        self.lightness = isOn ? lightness : 0
        self.cct = cct
    }
    
    init(data: SceneExecuteData) {
        self.isOn = data.isOn
        self.lightness = data.isOn ? Node.getLightness100(lightness: data.lightness) : 0
        self.cct = Int(data.cct)
    }
}
```

- [ ] **Step 5: Update scene picker call sites in create-scene data list**

In `SceneAddDataListViewCellDelegate.didLongPressData`, update `show(...)` and the callback:

```swift
SceneExecuteDataPickerView.show(lightness: data.lightness, isOn: data.isOn, cct: data.cct, cctRange: sceneDataCctRange) {[weak self] isOn, lightness, cct in
    guard let self = self else { return }
    data.isOn = isOn
    data.lightness = isOn ? lightness : 0
    data.cct = cct
    self.collectionView.reloadData()
} delete: {[weak self] in
    guard let self = self else { return }
    self.sceneDatas.remove(at: index)
    if index == self.sceneDataSelectIndex {
        self.sceneDataSelectIndex = nil
    }
    self.collectionView.reloadData()
}
```

In `cellDidAddAction`, update the callback:

```swift
SceneExecuteDataPickerView.show(cctRange: sceneDataCctRange, showDelete: false) {[weak self] isOn, lightness, cct in
    let data = ExecuteSceneData(isOn: isOn, lightness: lightness, cct: cct)
    self?.sceneDatas.append(data)
    self?.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
}
```

- [ ] **Step 6: Keep template and group assignment OFF state**

When assigning selected template data to a group in `collectionView(_:didSelectItemAt:)`, preserve `isOn`:

```swift
group.executeSceneData = .init(isOn: data.isOn, lightness: data.lightness, cct: Int(group.clampEffectiveCct(UInt16(data.cct))))
```

In reset comparison, include `isOn`:

```swift
if defalutSceneDatas[index].isOn != data.isOn || defalutSceneDatas[index].lightness != data.lightness || defalutSceneDatas[index].cct != data.cct {
    valueEdit = true
    break
}
```

- [ ] **Step 7: Continue to Task 2 before building**

Do not build or commit here. Task 1 changes the shared picker callback signature, and Task 2 updates the remaining controller call sites. The first buildable checkpoint is Task 2 Step 6.

### Task 2: Save And Preview OFF State In Scene Controllers

**Files:**
- Modify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`

- [ ] **Step 1: Add a shared preview helper to Scene Settings**

In `SceneSettingsViewController`, add this private helper near `previewBtnAction(sender:)`:

```swift
private func previewSceneData(_ data: ExecuteSceneData, for group: Group) {
    guard group.nodes.count > 0 else { return }
    guard data.isOn else {
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: false)
        return
    }
    let effectiveCctCount = group.nodes.filter({ $0.effectiveSupportCct }).count
    if effectiveCctCount > 0 {
        MeshAPI.setGroupCTLState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: group.clampEffectiveCct(UInt16(data.cct)))
    }
    if effectiveCctCount < group.lightnessNodes.count {
        MeshAPI.setGroupLightnessState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness))
    }
}
```

Replace the body inside `controlGroups.forEach` in `previewBtnAction(sender:)` with:

```swift
if let data = $0.executeSceneData {
    previewSceneData(data, for: $0)
}
```

- [ ] **Step 2: Update Scene Settings picker call**

In `updateGroupSceneExecuteData(group:)`, pass `isOn`, allow brightness lower bound 0, and store callback state:

```swift
let isOn = data?.isOn ?? true
let initialLightness = isOn ? data?.lightness ?? 100 : 0
SceneExecuteDataPickerView.show(lightness: initialLightness, isOn: isOn, cct: data?.cct ?? 4500, lightnessLimitRange: 0...groupLightData.highEndTrim, cctRange: group.effectiveCctRange, showCct: group.effectiveSupportCct, showDelete: false) {[weak self] isOn, lightness, cct in
    guard let self = self else { return }
    let cct = Int(group.clampEffectiveCct(UInt16(cct)))
    if let sceneData = data {
        sceneData.isOn = isOn
        sceneData.lightness = isOn ? lightness : 0
        sceneData.cct = cct
    } else {
        group.executeSceneData = ExecuteSceneData(isOn: isOn, lightness: lightness, cct: cct)
    }
    group.isSelected = true
    if let index = MeshNetworkManager.instance.groups.firstIndex(of: group) {
        CATransaction.setDisableActions(true)
        self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        CATransaction.commit()
    } else {
        self.collectionView.reloadData()
    }
}
```

- [ ] **Step 3: Save `isOn` in Scene Settings member and settings modes**

In `doneAction()`, when updating or appending `SceneExecuteData`, use:

```swift
let isOn = executeSceneData.isOn
let lightness = isOn ? Node.getLightness(lightness100: executeSceneData.lightness) : 0
let cct = $0.clampEffectiveCct(UInt16(executeSceneData.cct))
if let data = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
    data.isOn = isOn
    data.lightness = lightness
    data.cct = cct
} else {
    $0.info.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: scene.number, isOn: isOn, lightness: lightness, cct: cct))
}
```

In `saveAction()`, update the `updateGroups` comparison:

```swift
return newData.isOn != oldData.isOn || newData.lightness != Node.getLightness100(lightness: oldData.lightness) || newData.cct != oldData.cct
```

In the `addGroups.forEach` block, save:

```swift
let isOn = $0.executeSceneData!.isOn
let lightness = isOn ? Node.getLightness(lightness100: $0.executeSceneData!.lightness) : 0
let cct = $0.clampEffectiveCct(UInt16($0.executeSceneData!.cct))
$0.info.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: scene.number, isOn: isOn, lightness: lightness, cct: cct))
```

In the `updateGroups.forEach` block, update:

```swift
data.isOn = $0.executeSceneData!.isOn
data.lightness = data.isOn ? Node.getLightness(lightness100: $0.executeSceneData!.lightness) : 0
data.cct = $0.clampEffectiveCct(UInt16($0.executeSceneData!.cct))
```

- [ ] **Step 4: Add a shared preview helper to Scene Add**

In `SceneAddViewController`, add this private helper near `previewBtnAction()`:

```swift
private func previewSceneData(_ data: ExecuteSceneData, for group: Group) {
    guard group.nodes.count > 0 else { return }
    guard data.isOn else {
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: false)
        return
    }
    let effectiveCctCount = group.nodes.filter({ $0.effectiveSupportCct }).count
    if effectiveCctCount > 0 {
        MeshAPI.setGroupCTLState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: group.clampEffectiveCct(UInt16(data.cct)))
    }
    if effectiveCctCount < group.lightnessNodes.count {
        MeshAPI.setGroupLightnessState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness))
    }
}
```

Replace the body inside `groups.forEach` in `previewBtnAction()` with:

```swift
if let data = $0.executeSceneData {
    previewSceneData(data, for: $0)
}
```

- [ ] **Step 5: Save `isOn` in Scene Add**

In `addSceneHandle()`, replace the `executeData` creation with:

```swift
let lightness = data.isOn ? Node.getLightness(lightness100: data.lightness) : 0
let executeData = SceneExecuteData(sceneNumber: scene.number, isOn: data.isOn, lightness: lightness, cct: $0.clampEffectiveCct(UInt16(data.cct)))
```

- [ ] **Step 6: Build-check this task**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. This checkpoint covers the picker callback signature and all Scene Add / Scene Settings save and preview call sites.

- [ ] **Step 7: Commit Task 2**

```bash
git add SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift SunSmart/Main/Scene/Controller/SceneAddViewController.swift
git commit -m "feat: save scene off state"
```

### Task 3: Generate OFF Scene Sync Commands

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Send only OnOff and SceneStore for OFF scene sync**

In `Scene.getSyncMessageHandles(node:data:)`, after `let targetData = data.deviceTarget(for: node)`, add an OFF branch before the CTL / Lightness branch:

```swift
let targetData = data.deviceTarget(for: node)
let lightness = targetData.lightness
if !targetData.isOn {
    if let onoffModel = node.onoffModel {
        messageHandles.append(MeshMessageHandle(message: GenericOnOffSet(false), model: onoffModel))
    }
} else if let ctlModel = node.ctlModel, node.effectiveSupportCct {
    messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: targetData.cct, deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctlModel))
} else if let lightnessModel = node.lightnessModel {
    messageHandles.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel))
} else if let onoffModel = node.onoffModel {
    messageHandles.append(MeshMessageHandle(message: GenericOnOffSet(lightness > 0), model: onoffModel))
}
```

Keep the existing `SceneStore` append condition:

```swift
if messageHandles.count > 0 {
    messageHandles.append(MeshMessageHandle(message: SceneStore(self.number), model: sceneSetupModel))
}
```

- [ ] **Step 2: Preserve target `isOn` when applying device target**

In `SceneExecuteData.deviceTarget(for:)`, keep `isOn` unchanged:

```swift
isOn: isOn,
lightness: isOn ? lightness : 0,
```

Full initializer block should be:

```swift
let data = SceneExecuteData(
    sceneNumber: sceneNumber,
    isOn: isOn,
    lightness: isOn ? lightness : 0,
    cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : cct,
    lightControlData: lightControlData
)
```

- [ ] **Step 3: Cache OFF scene state correctly on SceneStore**

In `Node.updateData(message:isSuccess:)` inside the `case is SceneStore:` branch, change the cached scene data creation so OFF uses group scene data:

```swift
let targetIsOn = groupSceneData?.isOn ?? lightness > 0
let targetLightness = targetIsOn ? lightness : 0
let sceneData = SceneExecuteData(sceneNumber: sceneId, isOn: targetIsOn, lightness: targetLightness, cct: clampEffectiveCct(cct))
```

This replaces:

```swift
let sceneData = SceneExecuteData(sceneNumber: sceneId, isOn: lightness > 0, lightness: lightness, cct: clampEffectiveCct(cct))
```

- [ ] **Step 4: Continue to Task 4 before building**

Do not build or commit here. Task 3 changes OFF scene command generation, and Task 4 updates success handling to match the new command type. The next buildable checkpoint is Task 4 Step 4.

### Task 4: Match Success Checks To OFF Commands

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Update Sync device(s) scene status handling**

In `SyncDevicesViewController` successful callback, change the scene status branch from:

```swift
}else if (statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus), messageHandles.contains(where: { $0.message is SceneStore }) {
```

to:

```swift
}else if (statusMessage is GenericOnOffStatus || statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus), messageHandles.contains(where: { $0.message is SceneStore }) {
```

Inside the branch, after `node.updateNodeStatus(...)`, add:

```swift
if let onOffStatus = statusMessage as? GenericOnOffStatus, !(onOffStatus.targetState ?? onOffStatus.isOn) {
    node.lightness = 0
}
```

- [ ] **Step 2: Update deferred restore scene status handling**

In `DeviceRestoreViewController.handleDeferredRestoreSuccessfulResponse(...)`, change the status type guard from:

```swift
if statusMessage is LightLightnessStatus
    || statusMessage is LightCTLTemperatureStatus
    || statusMessage is LightCTLStatus
    || statusMessage is LightHSLStatus,
   messageHandles.contains(where: { $0.message is SceneStore }) {
```

to:

```swift
if statusMessage is GenericOnOffStatus
    || statusMessage is LightLightnessStatus
    || statusMessage is LightCTLTemperatureStatus
    || statusMessage is LightCTLStatus
    || statusMessage is LightHSLStatus,
   messageHandles.contains(where: { $0.message is SceneStore }) {
```

After `targetNode.updateNodeStatus(...)`, add:

```swift
if let onOffStatus = statusMessage as? GenericOnOffStatus, !(onOffStatus.targetState ?? onOffStatus.isOn) {
    targetNode.lightness = 0
}
```

- [ ] **Step 3: Add OFF-specific scene operation success**

In `DeviceOperationType.isSuccessful`, inside `.configuration(_, let type)` and `case .scene(let sceneId, let sceneData)`, replace the existing guard block with:

```swift
guard let sceneData = sceneData, let nodeScene = node.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }) else {
    return false
}
if !sceneData.isOn {
    return nodeScene.isOn == false
}
guard nodeScene.isSynced(with: sceneData, for: node) else {
    let target = sceneData.deviceTarget(for: node)
    print("scene\(sceneData.sceneNumber) target: isOn \(target.isOn) lightness \(target.lightness) cct \(target.cct)")
    print("scene\(nodeScene.sceneNumber) real: isOn \(nodeScene.isOn) lightness \(nodeScene.lightness) cct \(nodeScene.cct)")
    return false
}
return true
```

- [ ] **Step 4: Build-check this task**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. If it fails on `GenericOnOffStatus` not found, confirm `NordicSigMeshSDK` is imported in the touched files; these files already import project dependencies in the current codebase.

- [ ] **Step 5: Commit Task 4**

```bash
git add SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: validate scene off sync"
```

### Task 5: Final Verification

**Files:**
- Verify only: no planned source edits.

- [ ] **Step 1: Search for outdated picker callback call sites**

Run:

```sh
rg -n "SceneExecuteDataPickerView.show" SunSmart/Main/Scene SunSmart/Common -g '*.swift'
```

Expected: every callback accepts `isOn, lightness, cct`, and Scene Settings passes `0...groupLightData.highEndTrim`.

- [ ] **Step 2: Search for scene save paths that ignore `isOn`**

Run:

```sh
rg -n "SceneExecuteData\\(sceneNumber: scene.number|data.lightness =|\\.isOn =" SunSmart/Main/Scene SunSmart/Common/Data -g '*.swift'
```

Expected: Scene add/settings save paths set `SceneExecuteData.isOn`; sync cache paths preserve OFF state.

- [ ] **Step 3: Run final build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Inspect git diff**

Run:

```sh
git status --short
git diff --stat
```

Expected: only focused Scene, Sync device(s), and docs plan files are changed since the task commits.

## Self-Review

- Spec coverage: UI style, OFF/brightness coupling, low-end trim removal for scene popup, high-end trim retention, Preview behavior, SAVE sync behavior, add-to-group sync, restore sync, and success checks are covered by Tasks 1 through 5.
- Placeholder scan: the plan contains no unresolved markers.
- Type consistency: `DataPickerCallback` consistently uses `(Bool, Int, Int)`, `ExecuteSceneData` consistently carries `isOn`, and sync code consistently treats OFF as `SceneExecuteData.isOn == false`.
