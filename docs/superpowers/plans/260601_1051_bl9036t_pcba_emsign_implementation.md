# BL9036T-PCBA EMSign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `0x0A78 / 0x24C1` 的 `SR-BL9036T-PCBA` 增加 EMSign 产品 Profile，使其保留 Lighting 通路，但单设备页只支持 vendor Identify，并从 Device Parameter Settings 完全排除。

**Architecture:** 保持 `deviceCategory = Lighting`，不新增 `Node.DeviceType`。在 `Node` 扩展中增加轻量产品 Profile 判断，集中驱动默认命名、参数设置过滤和单设备页 UI 分支。`DeviceLightViewController` 内部增加 Identify-only 分支，普通灯控路径保持原状。

**Tech Stack:** iOS UIKit、Swift、SnapKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 增加 `0x24C1` 产品 Profile 判断。
  - 为该 Profile 返回默认名前缀 `EM`。
  - 让该 Profile 的 `supportSetParameter` 返回 `false`。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 增加 EMSign Identify-only UI 分支。
  - Identify 使用 `SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500)))`。
  - 防止该分支触发 on/off、lightness、CCT 命令。
- Verify only: `SunSmart/devices_config.json`
  - 确认 `0x24C1` 为 `iconCategory = EMSign`、`deviceCategory = Lighting`。
- Verify and commit existing resource rename: `SunSmart/Assets.xcassets/Device/device_offline_EMSign.imageset`
  - 当前工作区已将 typo 目录 `deivce_offline_EMSign.imageset` 修正为 `device_offline_EMSign.imageset`。
  - 执行实现时将该资源修正作为独立资源提交纳入。
- No test target exists in this worktree. Verification uses focused static checks plus required `xcodebuild` build.

---

### Task 1: Add EMSign Product Profile

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Verify the Profile does not exist yet**

Run:

```bash
rg -n "isEmergencySignController|emergencySignControllerProductIdentifiers" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: command exits with no matches.

- [ ] **Step 2: Add static Profile helpers**

In `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`, near the existing power switch helpers around `static func isPowerSwitch(...)`, insert:

```swift
    private static let emergencySignControllerCompanyIdentifier: UInt16 = 0x0A78
    private static let emergencySignControllerProductIdentifiers: Set<UInt16> = [0x24C1]

    static func isEmergencySignController(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        guard companyIdentifier == emergencySignControllerCompanyIdentifier,
              let productIdentifier else {
            return false
        }
        return emergencySignControllerProductIdentifiers.contains(productIdentifier)
    }
```

- [ ] **Step 3: Add the instance helper**

In the same file, near `var isPowerSwitch: Bool`, insert:

```swift
    var isEmergencySignController: Bool {
        return Node.isEmergencySignController(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }
```

- [ ] **Step 4: Update default name prefix**

Replace the beginning of `var defaultNameCategory: String?` with:

```swift
    var defaultNameCategory: String? {
        if isEmergencySignController {
            return "EM"
        }
        switch self.deviceType {
        case .light:
            return "L"
        case .sensor:
            return "S"
        case .switches:
            return "SW"
        case .gateway:
            return "gateway".localizedString
        case .dongle:
            return "dongle".localizedString
        case .emergencyController:
            return "EFC"
        case .unknown:
            return nil
        }
    }
```

- [ ] **Step 5: Exclude the Profile from Device Parameter Settings**

In `var supportSetParameter: Bool`, after the existing guard, add the Profile check:

```swift
    var supportSetParameter: Bool {
        guard self.sunricherVendorModel != nil, self.productIdentifier != nil else {
            return false
        }
        if isEmergencySignController {
            return false
        }
        if self.deviceType == .switches ||
            self.deviceType == .dongle ||
            self.deviceType == .gateway ||
            self.deviceType == .emergencyController {
            return false
        }
        return true
    }
```

- [ ] **Step 6: Run focused static verification**

Run:

```bash
rg -n "isEmergencySignController|emergencySignControllerProductIdentifiers|return \"EM\"|supportSetParameter" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: output includes the static helper, instance helper, `return "EM"`, and `supportSetParameter`.

- [ ] **Step 7: Commit the Profile change only**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "feat: add EMSign controller profile" -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: commit succeeds and does not include staged asset renames.

---

### Task 2: Add Identify-Only Device Page

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Verify the Identify-only branch does not exist yet**

Run:

```bash
rg -n "emergencySignIdentifyButton|setupEmergencySignUI|updateEmergencySignData|emergencySignIdentifyAction" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: command exits with no matches.

- [ ] **Step 2: Add the Identify button property**

In `DeviceLightViewController`, near the existing UI properties, add:

```swift
    private var emergencySignIdentifyButton: UIButton?
```

- [ ] **Step 3: Gate normal light setup in `viewDidLoad`**

In `viewDidLoad`, replace the block:

```swift
        // 初始化UI
        setupUI()
        // 根据设备类型显示UI
        updateUI()
        // 绑定事件
        bindSliderAction()
        // 获取设备数据
        getNodeState()
```

with:

```swift
        // 初始化UI
        setupUI()
        if node.isEmergencySignController {
            setupEmergencySignUI()
        } else {
            // 根据设备类型显示UI
            updateUI()
            // 绑定事件
            bindSliderAction()
        }
        // 获取设备数据
        getNodeState()
```

- [ ] **Step 4: Keep relay and lux controls out of the EMSign branch**

In `viewDidLoad`, replace:

```swift
        relaySwitch.isHidden = false
        relayLabel.isHidden = false
```

with:

```swift
        relaySwitch.isHidden = node.isEmergencySignController
        relayLabel.isHidden = node.isEmergencySignController
```

In the same method, replace:

```swift
        if node.ambientLightSensorModel != nil {
```

with:

```swift
        if !node.isEmergencySignController, node.ambientLightSensorModel != nil {
```

- [ ] **Step 5: Avoid normal slider refresh for EMSign**

In `viewWillAppear`, replace:

```swift
        updateData()
        updateSliderValue()
        
        if node.ambientLightSensorModel != nil {
            getNodeAmbientSensorLux()
        }
```

with:

```swift
        updateData()
        if !node.isEmergencySignController {
            updateSliderValue()
        }
        
        if !node.isEmergencySignController, node.ambientLightSensorModel != nil {
            getNodeAmbientSensorLux()
        }
```

- [ ] **Step 6: Route data updates to EMSign rendering**

At the top of `private func updateData()`, add:

```swift
        if node.isEmergencySignController {
            updateEmergencySignData()
            return
        }
```

- [ ] **Step 7: Guard the normal on/off action**

At the top of `@objc private func onoffAction(sender: UIButton)`, add:

```swift
        guard !node.isEmergencySignController else {
            return
        }
```

- [ ] **Step 8: Add Identify-only UI and update methods**

Add these methods inside `DeviceLightViewController`, before `private func bindSliderAction()`:

```swift
    private func setupEmergencySignUI() {
        lightImageBtn.setImage(UIImage(named: "device_center_EMSign"), for: .normal)
        lightImageBtn.setImage(UIImage(named: "device_center_EMSign"), for: .selected)
        lightImageBtn.removeTarget(self, action: #selector(onoffAction), for: .touchUpInside)
        lightImageBtn.isUserInteractionEnabled = false
        lightImageBtn.isSelected = true
        lightImageBtn.snp.remakeConstraints { make in
            make.center.equalTo(lightBgView)
            make.width.height.equalTo(SCRYFit(48))
        }

        lightBgView.image = UIImage(named: "device_light_bg")
        lightBgView.alpha = 1
        lightGrayBgView.alpha = 0

        brightnessView.isHidden = true
        cctView.isHidden = true
        lightnessSlider.isHidden = true
        cctSlider.isHidden = true
        onoffBtn.isHidden = true
        relaySwitch.isHidden = true
        relayLabel.isHidden = true

        let identifyButton = UIButton(normalImageName: "device_identify", target: self, action: #selector(emergencySignIdentifyAction))
        view.addSubview(identifyButton)
        identifyButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(160))
            make.width.height.equalTo(SCRYFit(40))
        }
        emergencySignIdentifyButton = identifyButton
    }

    private func updateEmergencySignData() {
        brightnessView.isHidden = true
        cctView.isHidden = true
        lightnessSlider.isHidden = true
        cctSlider.isHidden = true
        onoffBtn.isHidden = true
        relaySwitch.isHidden = true
        relayLabel.isHidden = true

        if node.isKeybindComplete {
            view.hideEmptyDataView()

            guard node.state else {
                emergencySignIdentifyButton?.isHidden = true
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                return
            }

            view.hideEmptyDataView()
            emergencySignIdentifyButton?.isHidden = false
            emergencySignIdentifyButton?.isEnabled = node.sunricherVendorModel != nil
            emergencySignIdentifyButton?.alpha = node.sunricherVendorModel != nil ? 1 : 0.45
            lightImageBtn.isSelected = true
            lightBgView.image = UIImage(named: "device_light_bg")
            lightBgView.alpha = 1
            lightGrayBgView.alpha = 0
        } else {
            emergencySignIdentifyButton?.isHidden = true
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) { [weak self] in
                    self?.repairBtnClick()
                }
                if let emptyView = view.emptyView {
                    if space.deviceOperates.contains(.edit) {
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                        }
                    } else {
                        emptyView.button.isHidden = true
                    }
                }
            }
        }
    }

    @objc private func emergencySignIdentifyAction() {
        guard node.isKeybindComplete, node.state else {
            XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: false)
            return
        }
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: vendorModel)
    }
```

- [ ] **Step 9: Avoid slider refresh in mesh message callbacks**

In `meshNetworkManager(_:deviceDataUpdate:)`, replace:

```swift
            updateData()
            updateSliderValue()
```

with:

```swift
            updateData()
            if !self.node.isEmergencySignController {
                updateSliderValue()
            }
```

In `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)`, replace the same two-line block inside the address match with the same guarded version.

- [ ] **Step 10: Run focused static verification**

Run:

```bash
rg -n "setupEmergencySignUI|updateEmergencySignData|emergencySignIdentifyAction|device_center_EMSign|SunricherVendorSet\\(function: \\.identify\\(mode: \\.breathe\\(count: 1, period: 1500\\)\\)\\)" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: output includes the setup method, update method, Identify action, `device_center_EMSign`, and the vendor identify command.

- [ ] **Step 11: Verify normal light command calls remain outside the EMSign action**

Run:

```bash
rg -n "setNodeOnOffState|setNodeLightnessState|setNodeColorTemperatureState|emergencySignIdentifyAction" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: normal light command calls still exist for regular light controls, and `emergencySignIdentifyAction` contains only vendor identify.

- [ ] **Step 12: Commit the UI change only**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: add EMSign identify-only control page" -- SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: commit succeeds and does not include staged asset renames.

---

### Task 3: Verify Config and Commit Resource Rename

**Files:**
- Verify: `SunSmart/devices_config.json`
- Verify: `SunSmart/Assets.xcassets/Device/device_EMSign.imageset`
- Verify and commit: `SunSmart/Assets.xcassets/Device/device_offline_EMSign.imageset`
- Verify: `SunSmart/Assets.xcassets/Device/device_unsync_EMSign.imageset`
- Verify: `SunSmart/Assets.xcassets/Device/device_center_EMSign.imageset`

- [ ] **Step 1: Verify 0x24C1 config**

Run:

```bash
rg -n -A6 '"productId": "24C1"' SunSmart/devices_config.json
```

Expected output includes:

```text
"productId": "24C1"
"categoryName": "EL Controller"
"elementCount": 3
"iconCategory": "EMSign"
"deviceCategory": "Lighting"
"modelName": "SR-BL9036T-PCBA"
```

- [ ] **Step 2: Verify EMSign image sets exist**

Run:

```bash
test -d SunSmart/Assets.xcassets/Device/device_EMSign.imageset
test -d SunSmart/Assets.xcassets/Device/device_offline_EMSign.imageset
test -d SunSmart/Assets.xcassets/Device/device_unsync_EMSign.imageset
test -d SunSmart/Assets.xcassets/Device/device_center_EMSign.imageset
```

Expected: all commands exit with status 0.

- [ ] **Step 3: Verify old typo asset directory is gone**

Run:

```bash
test ! -d SunSmart/Assets.xcassets/Device/deivce_offline_EMSign.imageset
```

Expected: command exits with status 0.

- [ ] **Step 4: Stage the resource rename explicitly**

Run:

```bash
git add SunSmart/Assets.xcassets/Device/device_offline_EMSign.imageset
git add -u SunSmart/Assets.xcassets/Device/deivce_offline_EMSign.imageset
```

Expected: staged diff contains only the typo-to-correct EMSign offline asset rename.

- [ ] **Step 5: Commit the resource rename only**

Run:

```bash
git commit -m "fix: align EMSign offline asset name" -- SunSmart/Assets.xcassets/Device/deivce_offline_EMSign.imageset SunSmart/Assets.xcassets/Device/device_offline_EMSign.imageset
```

Expected: commit succeeds and includes only the four offline EMSign asset file renames.

---

### Task 4: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Verify Device Parameter Settings exclusion path**

Run:

```bash
rg -n "node.supportSetParameter|allDevices.append|DeviceCategoryData\\(name: node.categoryName" SunSmart/Main/Device/Parameter/Controller/DeviceCategorysViewController.swift
```

Expected: output confirms `DeviceCategorysViewController` still builds data from `node.supportSetParameter`, so the Profile change excludes `0x24C1` from All devices and PID categories.

- [ ] **Step 2: Verify no unexpected protocol edits**

Run:

```bash
git diff --name-only HEAD~3..HEAD
```

Expected: output includes implementation files and asset rename only. It does not include `protocols/0x24C1.json`.

- [ ] **Step 3: Run required iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Record final status**

Run:

```bash
git status --short
```

Expected: no uncommitted implementation changes remain. Any unrelated user changes that predate execution must be listed separately in the final response and not reverted.

