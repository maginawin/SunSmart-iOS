# WiFi Gateway Network Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference selects Inline Execution by default; do not dispatch subagents unless the user explicitly asks.

**Goal:** Add a WiFi Gateway-only `Network Connectivity` section that displays the phone SSID, accepts an ASCII password, and simulates connect/disconnect states without sending SSID/password to the gateway.

**Architecture:** Keep Gateway shared behavior in `GatewayViewController`, but open small table-section hooks so `WiFiGatewayViewController` can insert a WiFi-only section. Put SSID lookup behind a focused helper and keep all connection state in `WiFiGatewayViewController` memory. Build the Figma UI as a dedicated table cell so existing generic gateway cells stay stable.

**Tech Stack:** UIKit, SnapKit, CoreLocation, NetworkExtension, Xcode project resources, `.strings` localization, shell static checks, iPhoneOS `xcodebuild`.

---

## Source Spec

- Design doc: `docs/260703_1033_wifi_gateway_network_connectivity_design.md`
- Confirmed scope:方案 A；仅模拟连接；不下发 SSID/password；仅 `CID 0x0A78 / PID 0x2721` WiFi Gateway 页面展示。

## Files

- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - Open table-section extension points.
  - Add `.networkConnectivity` case.
  - Register/dequeue the new WiFi cell without affecting default Gateway sections.
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Insert the new section after `.activate`.
  - Own SSID/password/connect state and callbacks.
  - Present Change Wi-Fi alert and handle app foreground refresh.
- Create: `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`
  - Dedicated Figma-aligned section cell.
- Create: `SunSmart/Main/Device/Gateway/View/GatewayChangeWiFiAlertView.swift`
  - Dedicated Figma-aligned overlay for the Change Wi-Fi alert.
- Create: `SunSmart/Main/Device/Gateway/Model/WiFiSSIDProvider.swift`
  - Small SSID lookup wrapper using `NEHotspotNetwork.fetchCurrent`.
  - Requests location permission only when needed for SSID access.
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add visible UI strings and ASCII warning.
- Create: `SunSmart/en.lproj/InfoPlist.strings`
- Create: `SunSmart/zh-Hans.lproj/InfoPlist.strings`
  - Localize location permission text.
- Create: `SunSmart/SunSmart.entitlements`
- Create: `Archipelago/Archipelago.entitlements`
- Create: `SLGSync/SLGSync.entitlements`
- Create: `SylSmart/SylSmart.entitlements`
  - Add Wi-Fi Info entitlement for all brand targets.
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - Add new Swift files to all brand target Sources.
  - Add `InfoPlist.strings` resource references.
  - Set `CODE_SIGN_ENTITLEMENTS` for all brand target build configurations.
- Create: `scripts/check_wifi_gateway_network_connectivity.sh`
  - Static regression check for route scope, no SSID/password downlink, localization, resources, and section insertion.

---

### Task 1: Add Gateway Section Hooks

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`

- [ ] **Step 1: Replace private `sections` with an overridable property**

Change the existing computed property near the top of `GatewayViewController` from private to internal:

```swift
var sections: [SectionType] {
    let baseSections: [SectionType] = [.name, .activate, .info, .associatedSpaces, .apn, .serverInformation]
    return supportsAPNConfiguration ? baseSections : baseSections.filter { $0 != .apn }
}
```

Expected: all existing references in the same file still compile, and `WiFiGatewayViewController` can override `sections`.

- [ ] **Step 2: Add the new section enum case**

Add the case between `.activate` and `.info` in `SectionType`:

```swift
/// WiFi network connectivity
case networkConnectivity
```

- [ ] **Step 3: Add default hook methods before the table view extension**

Add these methods near `configureActivateCell(_:)`:

```swift
func registerAdditionalGatewayCells(in tableView: UITableView) {}

func configureNetworkConnectivityCell(_ cell: GatewayNetworkConnectivityCell) {}

func networkConnectivityCellHeight() -> CGFloat {
    return UITableView.automaticDimension
}
```

- [ ] **Step 4: Call the registration hook**

In `setupUI()`, immediately after existing `tableView.register(...)` calls, add:

```swift
registerAdditionalGatewayCells(in: tableView)
```

- [ ] **Step 5: Handle `.networkConnectivity` in data source and delegate**

Add switch branches:

```swift
case .networkConnectivity:
    return 1
```

```swift
case .networkConnectivity:
    let cell = tableView.dequeueReusableCell(withIdentifier: GatewayNetworkConnectivityCell.reuseIdentifier, for: indexPath) as! GatewayNetworkConnectivityCell
    configureNetworkConnectivityCell(cell)
    tableviewCell = cell
```

```swift
case .networkConnectivity:
    return networkConnectivityCellHeight()
```

```swift
case .networkConnectivity:
    headerView.titleLabel.text = "network_connectivity".localizedString
```

Expected: base `GatewayViewController` never shows `.networkConnectivity`, so this is inert for 4G Gateway.

- [ ] **Step 6: Make section reload usable by subclass**

Change:

```swift
private func reloadSection(_ section: SectionType)
```

to:

```swift
func reloadSection(_ section: SectionType)
```

- [ ] **Step 7: Commit task**

```bash
git add SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "refactor: add gateway section hooks"
```

---

### Task 2: Add SSID Provider And Entitlements

**Files:**
- Create: `SunSmart/Main/Device/Gateway/Model/WiFiSSIDProvider.swift`
- Create: `SunSmart/SunSmart.entitlements`
- Create: `Archipelago/Archipelago.entitlements`
- Create: `SLGSync/SLGSync.entitlements`
- Create: `SylSmart/SylSmart.entitlements`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Create: `SunSmart/en.lproj/InfoPlist.strings`
- Create: `SunSmart/zh-Hans.lproj/InfoPlist.strings`

- [ ] **Step 1: Create `WiFiSSIDProvider.swift`**

```swift
//
//  WiFiSSIDProvider.swift
//  SunSmart
//

import CoreLocation
import Foundation
import NetworkExtension

final class WiFiSSIDProvider: NSObject {
    static let shared = WiFiSSIDProvider()

    private let locationManager = CLLocationManager()
    private var pendingCompletions: [(String) -> Void] = []

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func fetchCurrentSSID(completion: @escaping (String) -> Void) {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            fetchSSIDWithoutPermissionRequest(completion: completion)
        case .notDetermined:
            pendingCompletions.append(completion)
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            completion("")
        @unknown default:
            completion("")
        }
    }

    private func fetchSSIDWithoutPermissionRequest(completion: @escaping (String) -> Void) {
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { network in
                DispatchQueue.main.async {
                    completion(network?.ssid ?? "")
                }
            }
        } else {
            completion("")
        }
    }
}

extension WiFiSSIDProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        guard !completions.isEmpty else { return }

        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            completions.forEach { $0("") }
            return
        }

        fetchSSIDWithoutPermissionRequest { ssid in
            completions.forEach { $0(ssid) }
        }
    }
}
```

- [ ] **Step 2: Create entitlement files**

Each entitlement file has this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.networking.wifi-info</key>
	<true/>
</dict>
</plist>
```

Use these exact paths:

```text
SunSmart/SunSmart.entitlements
Archipelago/Archipelago.entitlements
SLGSync/SLGSync.entitlements
SylSmart/SylSmart.entitlements
```

- [ ] **Step 3: Create localized InfoPlist permission strings**

`SunSmart/en.lproj/InfoPlist.strings`:

```text
"NSLocationWhenInUseUsageDescription" = "SunSmart uses location permission to display the currently connected Wi-Fi network name.";
```

`SunSmart/zh-Hans.lproj/InfoPlist.strings`:

```text
"NSLocationWhenInUseUsageDescription" = "SunSmart 需要定位权限以显示当前连接的 Wi-Fi 网络名称。";
```

- [ ] **Step 4: Add plist key to all brand Info.plist files**

Add this key to:

```text
SunSmart/Info.plist
Archipelago/Archipelago-Info.plist
SLGSync/SLGSync-Info.plist
SylSmart/SylSmart-Info.plist
```

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>SunSmart uses location permission to display the currently connected Wi-Fi network name.</string>
```

The localized `InfoPlist.strings` files provide the zh-Hans runtime text.

- [ ] **Step 5: Update `project.pbxproj`**

Add `WiFiSSIDProvider.swift` to the same Gateway group as other Gateway model/controller files and to all four brand target Sources.

Add the entitlement files to their brand groups and set `CODE_SIGN_ENTITLEMENTS` in every Debug/Release build configuration:

```text
SunSmart -> SunSmart/SunSmart.entitlements
Archipelago -> Archipelago/Archipelago.entitlements
SLG Sync Plus -> SLGSync/SLGSync.entitlements
SylSmart -> SylSmart/SylSmart.entitlements
```

Add `InfoPlist.strings` as a localized resource variant group with `en` and `zh-Hans` children, and include it in all four Resources build phases.

- [ ] **Step 6: Verify provider references**

Run:

```bash
rg -n "WiFiSSIDProvider|NEHotspotNetwork|com.apple.developer.networking.wifi-info|NSLocationWhenInUseUsageDescription|CODE_SIGN_ENTITLEMENTS" SunSmart Archipelago SLGSync SylSmart SunSmart.xcodeproj/project.pbxproj
```

Expected:

- `WiFiSSIDProvider.swift` imports `NetworkExtension`.
- All four entitlement files contain `com.apple.developer.networking.wifi-info`.
- All four brand Info.plist files contain `NSLocationWhenInUseUsageDescription`.
- Project file contains `CODE_SIGN_ENTITLEMENTS` entries for all four brand targets.

- [ ] **Step 7: Commit task**

```bash
git add SunSmart/Main/Device/Gateway/Model/WiFiSSIDProvider.swift SunSmart/SunSmart.entitlements Archipelago/Archipelago.entitlements SLGSync/SLGSync.entitlements SylSmart/SylSmart.entitlements SunSmart/en.lproj/InfoPlist.strings SunSmart/zh-Hans.lproj/InfoPlist.strings SunSmart/Info.plist Archipelago/Archipelago-Info.plist SLGSync/SLGSync-Info.plist SylSmart/SylSmart-Info.plist SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add wifi ssid provider"
```

---

### Task 3: Add Network Connectivity Cell

**Files:**
- Create: `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the cell class**

Create a UIKit cell with explicit callbacks:

```swift
//
//  GatewayNetworkConnectivityCell.swift
//  SunSmart
//

import UIKit

final class GatewayNetworkConnectivityCell: UITableViewCell {
    static let reuseIdentifier = "GatewayNetworkConnectivityCell"

    enum ConnectState {
        case disabled
        case available
        case connecting
        case connected
    }

    var selectWiFiCallback: (() -> Void)?
    var refreshCallback: (() -> Void)?
    var passwordChangedCallback: ((String) -> Void)?
    var togglePasswordVisibilityCallback: (() -> Void)?
    var connectActionCallback: (() -> Void)?

    private let containerView = UIView()
    private let ssidTitleLabel = UILabel()
    private let ssidValueLabel = UILabel()
    private let ssidInputView = UIView()
    private let selectWiFiButton = UIButton(type: .custom)
    private let noteLabel = UILabel()
    private let refreshButton = UIButton(type: .custom)
    private let passwordTitleLabel = UILabel()
    private let passwordInputView = UIView()
    private let passwordTextField = UITextField()
    private let passwordVisibilityButton = UIButton(type: .custom)
    private let connectButton = UIButton(type: .custom)
    private let loadingImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectWiFiCallback = nil
        refreshCallback = nil
        passwordChangedCallback = nil
        togglePasswordVisibilityCallback = nil
        connectActionCallback = nil
    }

    func update(ssid: String, password: String, passwordVisible: Bool, connectState: ConnectState) {
        ssidValueLabel.text = ssid
        passwordTextField.text = password
        passwordTextField.isSecureTextEntry = !passwordVisible
        passwordVisibilityButton.setImage(UIImage(named: passwordVisible ? "show_password" : "hide_password"), for: .normal)
        apply(connectState: connectState)
    }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        containerView.layer.masksToBounds = true
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.right.equalToSuperview()
        }

        [ssidTitleLabel, passwordTitleLabel].forEach {
            $0.font = UIFont.systemFont(ofSize: 14, weight: .light)
            $0.textColor = ImportantText_Color
        }
        ssidTitleLabel.text = "ssid".localizedString
        passwordTitleLabel.text = "Password".localizedString

        [ssidInputView, passwordInputView].forEach {
            $0.backgroundColor = RGB(248, 250, 252)
            $0.layer.cornerRadius = SCRYFrom(5)
            $0.layer.borderWidth = 0.5
            $0.layer.borderColor = RGB(236, 236, 236).cgColor
        }

        ssidValueLabel.font = UIFont.systemFont(ofSize: 13, weight: .light)
        ssidValueLabel.textColor = TextBlack_Color
        ssidValueLabel.lineBreakMode = .byTruncatingTail

        selectWiFiButton.setImage(UIImage(named: "select_wifi"), for: .normal)
        selectWiFiButton.addTarget(self, action: #selector(selectWiFiAction), for: .touchUpInside)

        noteLabel.font = UIFont.systemFont(ofSize: 12, weight: .light)
        noteLabel.textColor = SubText_Color
        noteLabel.text = "only_supports_24ghz_networks".localizedString

        refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        refreshButton.setTitle("refresh".localizedString, for: .normal)
        refreshButton.setTitleColor(Bar_Color, for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshAction), for: .touchUpInside)

        passwordTextField.font = UIFont.systemFont(ofSize: 13, weight: .light)
        passwordTextField.textColor = TextBlack_Color
        passwordTextField.isSecureTextEntry = true
        passwordTextField.autocorrectionType = .no
        passwordTextField.autocapitalizationType = .none
        passwordTextField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)

        passwordVisibilityButton.addTarget(self, action: #selector(togglePasswordVisibilityAction), for: .touchUpInside)

        connectButton.layer.cornerRadius = SCRYFrom(15)
        connectButton.layer.borderWidth = 1
        connectButton.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
        connectButton.backgroundColor = .white
        connectButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        connectButton.addTarget(self, action: #selector(connectAction), for: .touchUpInside)

        loadingImageView.image = UIImage(named: "space_add_3")
        loadingImageView.isHidden = true

        layoutViews()
    }

    private func layoutViews() {
        containerView.addSubview(ssidTitleLabel)
        containerView.addSubview(ssidInputView)
        ssidInputView.addSubview(ssidValueLabel)
        ssidInputView.addSubview(selectWiFiButton)
        containerView.addSubview(noteLabel)
        containerView.addSubview(refreshButton)
        containerView.addSubview(passwordTitleLabel)
        containerView.addSubview(passwordInputView)
        passwordInputView.addSubview(passwordTextField)
        passwordInputView.addSubview(passwordVisibilityButton)
        containerView.addSubview(connectButton)
        connectButton.addSubview(loadingImageView)

        ssidTitleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(62))
            make.height.equalTo(SCRYFrom(32))
        }
        ssidInputView.snp.makeConstraints { make in
            make.left.equalTo(ssidTitleLabel.snp.right).offset(SCRXFrom(8))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalTo(ssidTitleLabel)
            make.height.equalTo(SCRYFrom(32))
        }
        selectWiFiButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        ssidValueLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(8))
            make.right.equalTo(selectWiFiButton.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(ssidInputView)
            make.top.equalTo(ssidInputView.snp.bottom).offset(SCRYFrom(4))
            make.height.equalTo(SCRYFrom(24))
        }
        refreshButton.snp.makeConstraints { make in
            make.right.equalTo(ssidInputView)
            make.centerY.equalTo(noteLabel)
        }
        passwordTitleLabel.snp.makeConstraints { make in
            make.left.width.height.equalTo(ssidTitleLabel)
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(4))
        }
        passwordInputView.snp.makeConstraints { make in
            make.left.right.height.equalTo(ssidInputView)
            make.centerY.equalTo(passwordTitleLabel)
        }
        passwordVisibilityButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        passwordTextField.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(8))
            make.right.equalTo(passwordVisibilityButton.snp.left).offset(SCRXFrom(-4))
            make.top.bottom.equalToSuperview()
        }
        connectButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.equalTo(passwordInputView.snp.bottom).offset(SCRYFrom(10))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalToSuperview().offset(SCRYFrom(-16))
        }
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(24))
        }
    }

    private func apply(connectState: ConnectState) {
        let isConnecting = connectState == .connecting
        let isConnected = connectState == .connected

        selectWiFiButton.isEnabled = !isConnecting && !isConnected
        refreshButton.isEnabled = !isConnecting && !isConnected
        passwordTextField.isEnabled = !isConnecting && !isConnected
        passwordVisibilityButton.isEnabled = !isConnecting && !isConnected

        loadingImageView.isHidden = !isConnecting
        connectButton.setTitle(isConnecting ? nil : (isConnected ? "disconnect".localizedString : "connect_to_wifi".localizedString), for: .normal)
        connectButton.setTitleColor(connectState == .disabled ? RGB(147, 148, 196) : Bar_Color, for: .normal)
        connectButton.isEnabled = connectState != .disabled && !isConnecting
    }

    @objc private func selectWiFiAction() {
        selectWiFiCallback?()
    }

    @objc private func refreshAction() {
        refreshCallback?()
    }

    @objc private func passwordChanged() {
        passwordChangedCallback?(passwordTextField.text ?? "")
    }

    @objc private func togglePasswordVisibilityAction() {
        togglePasswordVisibilityCallback?()
    }

    @objc private func connectAction() {
        connectActionCallback?()
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Add `GatewayNetworkConnectivityCell.swift` to the Gateway View group and to all four brand target Sources.

- [ ] **Step 3: Commit task**

```bash
git add SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add gateway network connectivity cell"
```

---

### Task 4: Wire WiFiGatewayViewController State Machine

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

- [ ] **Step 1: Add state properties**

Add inside `WiFiGatewayViewController`:

```swift
private var networkSSID: String = ""
private var networkPassword: String = ""
private var isNetworkPasswordVisible: Bool = false
private var networkConnectState: GatewayNetworkConnectivityCell.ConnectState = .disabled
private var networkConnectTimer: Timer?
private var shouldRefreshSSIDWhenActive: Bool = false
```

- [ ] **Step 2: Override sections and cell hooks**

```swift
override var sections: [SectionType] {
    var sections = super.sections
    if let activateIndex = sections.firstIndex(of: .activate) {
        sections.insert(.networkConnectivity, at: sections.index(after: activateIndex))
    }
    return sections
}

override func registerAdditionalGatewayCells(in tableView: UITableView) {
    tableView.register(GatewayNetworkConnectivityCell.classForCoder(), forCellReuseIdentifier: GatewayNetworkConnectivityCell.reuseIdentifier)
}

override func networkConnectivityCellHeight() -> CGFloat {
    return SCRYFrom(172)
}

override func configureNetworkConnectivityCell(_ cell: GatewayNetworkConnectivityCell) {
    cell.update(ssid: networkSSID, password: networkPassword, passwordVisible: isNetworkPasswordVisible, connectState: networkConnectState)
    cell.selectWiFiCallback = { [weak self] in self?.showChangeWiFiAlert() }
    cell.refreshCallback = { [weak self] in self?.refreshCurrentSSID() }
    cell.passwordChangedCallback = { [weak self] password in self?.updateNetworkPassword(password) }
    cell.togglePasswordVisibilityCallback = { [weak self] in self?.toggleNetworkPasswordVisibility() }
    cell.connectActionCallback = { [weak self] in self?.networkConnectButtonAction() }
}
```

- [ ] **Step 3: Add lifecycle hooks**

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    refreshCurrentSSID()
}

deinit {
    networkConnectTimer?.invalidate()
    NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
}
```

If `deinit` conflicts with superclass behavior, keep it in the final subclass; Swift allows subclass `deinit` without calling `super`.

- [ ] **Step 4: Add SSID refresh**

```swift
private func refreshCurrentSSID() {
    guard networkConnectState != .connecting, networkConnectState != .connected else { return }
    WiFiSSIDProvider.shared.fetchCurrentSSID { [weak self] ssid in
        guard let self else { return }
        self.networkSSID = ssid
        self.reloadSection(.networkConnectivity)
    }
}

@objc private func appDidBecomeActive() {
    guard shouldRefreshSSIDWhenActive else { return }
    shouldRefreshSSIDWhenActive = false
    refreshCurrentSSID()
}
```

- [ ] **Step 5: Add password validation**

```swift
private func updateNetworkPassword(_ password: String) {
    guard password.canBeConverted(to: .ascii) else {
        XWHUDManager.showTipHUD("wifi_password_ascii_only".localizedString, isLineFeed: true)
        reloadSection(.networkConnectivity)
        return
    }
    networkPassword = password
    syncNetworkConnectStateForPassword()
    reloadSection(.networkConnectivity)
}

private func syncNetworkConnectStateForPassword() {
    guard networkConnectState != .connecting, networkConnectState != .connected else { return }
    networkConnectState = networkPassword.count >= 8 ? .available : .disabled
}

private func toggleNetworkPasswordVisibility() {
    guard networkConnectState != .connecting, networkConnectState != .connected else { return }
    isNetworkPasswordVisible.toggle()
    reloadSection(.networkConnectivity)
}
```

- [ ] **Step 6: Add connect/disconnect simulation**

```swift
private func networkConnectButtonAction() {
    switch networkConnectState {
    case .available:
        startNetworkConnectionSimulation()
    case .connected:
        disconnectNetworkSimulation()
    case .disabled, .connecting:
        break
    }
}

private func startNetworkConnectionSimulation() {
    networkConnectTimer?.invalidate()
    networkConnectState = .connecting
    reloadSection(.networkConnectivity)
    networkConnectTimer = LCWeakTimer.scheduledTimer(timeInterval: 2, aTarget: self, selector: #selector(finishNetworkConnectionSimulation), userInfo: nil, repeats: false)
    if let networkConnectTimer {
        RunLoop.main.add(networkConnectTimer, forMode: .common)
    }
}

@objc private func finishNetworkConnectionSimulation() {
    networkConnectTimer?.invalidate()
    networkConnectTimer = nil
    networkConnectState = .connected
    reloadSection(.networkConnectivity)
}

private func disconnectNetworkSimulation() {
    networkConnectTimer?.invalidate()
    networkConnectTimer = nil
    networkSSID = ""
    networkPassword = ""
    isNetworkPasswordVisible = false
    networkConnectState = .disabled
    reloadSection(.networkConnectivity)
}
```

- [ ] **Step 7: Commit task**

```bash
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "feat: simulate wifi gateway network connectivity"
```

---

### Task 5: Add Change Wi-Fi Alert

**Files:**
- Create: `SunSmart/Main/Device/Gateway/View/GatewayChangeWiFiAlertView.swift`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `GatewayChangeWiFiAlertView.swift`**

```swift
//
//  GatewayChangeWiFiAlertView.swift
//  SunSmart
//

import UIKit

final class GatewayChangeWiFiAlertView: UIView {

    private let shadeView = UIView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let introImageView = UIImageView()
    private let settingsButton = UIButton(type: .custom)
    private var settingsCallback: (() -> Void)?

    static func show(settingsCallback: @escaping () -> Void) {
        let alertView = GatewayChangeWiFiAlertView(frame: UIScreen.main.bounds)
        alertView.settingsCallback = settingsCallback
        UIApplication.shared.keyWindow().addSubview(alertView)
        alertView.showAnimation()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        shadeView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        shadeView.alpha = 0
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.layer.masksToBounds = true
        contentView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(359))
            make.height.equalTo(SCRYFrom(380))
        }

        titleLabel.text = "connect_to_24ghz_wifi_network".localizedString
        titleLabel.textColor = TextBlack_Color
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.textAlignment = .center

        introImageView.image = UIImage(named: "connect_wifi_intro")
        introImageView.contentMode = .scaleAspectFit

        settingsButton.backgroundColor = Bar_Color
        settingsButton.layer.cornerRadius = SCRYFrom(20)
        settingsButton.setTitle("go_to_system_settings".localizedString, for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        settingsButton.addTarget(self, action: #selector(settingsButtonAction), for: .touchUpInside)

        contentView.addSubview(titleLabel)
        contentView.addSubview(introImageView)
        contentView.addSubview(settingsButton)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(30))
            make.left.right.equalToSuperview().inset(SCRXFrom(32))
        }
        introImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(102))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(290))
            make.height.equalTo(SCRYFrom(152))
        }
        settingsButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(SCRYFrom(-40))
            make.width.equalTo(SCRXFrom(248))
            make.height.equalTo(SCRYFrom(40))
        }
    }

    private func showAnimation() {
        UIView.animate(withDuration: 0.2) {
            self.shadeView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    private func dismissThenRunCallback() {
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        } completion: { _ in
            let callback = self.settingsCallback
            self.removeFromSuperview()
            callback?()
        }
    }

    @objc private func settingsButtonAction() {
        dismissThenRunCallback()
    }
}
```

- [ ] **Step 2: Add the alert file to the Xcode project**

Add `GatewayChangeWiFiAlertView.swift` to the Gateway View group and to all four brand target Sources.

- [ ] **Step 3: Add alert presenter**

Add to `WiFiGatewayViewController`:

```swift
private func showChangeWiFiAlert() {
    GatewayChangeWiFiAlertView.show { [weak self] in
        self?.openSystemSettingsForWiFiChange()
    }
}
```

- [ ] **Step 4: Add settings opener**

```swift
private func openSystemSettingsForWiFiChange() {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(settingsURL) else {
        XWHUDManager.showTipHUD("network_error".localizedString, isLineFeed: true)
        return
    }
    shouldRefreshSSIDWhenActive = true
    UIApplication.shared.open(settingsURL)
}
```

- [ ] **Step 5: Verify alert visually in code**

Check:

```bash
rg -n "connect_wifi_intro|go_to_system_settings|GatewayChangeWiFiAlertView|UIApplication.openSettingsURLString|shouldRefreshSSIDWhenActive" SunSmart/Main/Device/Gateway
```

Expected: all five patterns appear under `SunSmart/Main/Device/Gateway`.

- [ ] **Step 6: Commit task**

```bash
git add SunSmart/Main/Device/Gateway/View/GatewayChangeWiFiAlertView.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add wifi change settings alert"
```

---

### Task 6: Add Localized Strings

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English strings**

Append near existing Gateway strings:

```text
"network_connectivity" = "Network Connectivity";
"ssid" = "SSID";
"select_wifi" = "Select Wi-Fi";
"only_supports_24ghz_networks" = "Only supports 2.4GHz networks.";
"connect_to_wifi" = "Connect to Wi-Fi";
"disconnect" = "Disconnect";
"connect_to_24ghz_wifi_network" = "Connect to 2.4 GHz Wi-Fi Network";
"go_to_system_settings" = "Go to System Settings";
"wifi_password_ascii_only" = "Password only supports ASCII characters.";
```

Reuse existing `"refresh"` and `"Password"` keys.

- [ ] **Step 2: Add Simplified Chinese strings**

Append matching keys:

```text
"network_connectivity" = "网络连接";
"ssid" = "SSID";
"select_wifi" = "选择 Wi-Fi";
"only_supports_24ghz_networks" = "仅支持 2.4GHz 网络。";
"connect_to_wifi" = "连接 Wi-Fi";
"disconnect" = "断开连接";
"connect_to_24ghz_wifi_network" = "连接到 2.4 GHz Wi-Fi 网络";
"go_to_system_settings" = "前往系统设置";
"wifi_password_ascii_only" = "密码仅支持 ASCII 字符。";
```

- [ ] **Step 3: Validate strings syntax**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/en.lproj/InfoPlist.strings SunSmart/zh-Hans.lproj/InfoPlist.strings
```

Expected: all files report `OK`.

- [ ] **Step 4: Commit task**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/en.lproj/InfoPlist.strings SunSmart/zh-Hans.lproj/InfoPlist.strings
git commit -m "feat: localize wifi connectivity section"
```

---

### Task 7: Add Static Regression Script

**Files:**
- Create: `scripts/check_wifi_gateway_network_connectivity.sh`

- [ ] **Step 1: Create script**

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

rg -n "case networkConnectivity|network_connectivity|GatewayNetworkConnectivityCell" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift >/dev/null || fail "GatewayViewController missing network connectivity hook"
rg -n "override var sections|\\.networkConnectivity|refreshCurrentSSID|startNetworkConnectionSimulation|disconnectNetworkSimulation" SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift >/dev/null || fail "WiFiGatewayViewController missing network connectivity state machine"
rg -n "SunricherVendorSet|gatewayMQTTConnectInfoSet|gatewaySubnetsRelevanceSet|NetworkRequest.shared.request" SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift && fail "WiFi connectivity simulation must not send gateway/network commands"
rg -n "GatewayChangeWiFiAlertView|connect_wifi_intro|go_to_system_settings" SunSmart/Main/Device/Gateway/View/GatewayChangeWiFiAlertView.swift >/dev/null || fail "Change WiFi alert missing"
rg -n "connect_wifi_intro|select_wifi|show_password|hide_password" SunSmart/Assets.xcassets >/dev/null || fail "Required WiFi connectivity assets missing"
rg -n '"network_connectivity"|"connect_to_wifi"|"go_to_system_settings"|"wifi_password_ascii_only"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings >/dev/null || fail "Required localization keys missing"
rg -n "com.apple.developer.networking.wifi-info" SunSmart/SunSmart.entitlements Archipelago/Archipelago.entitlements SLGSync/SLGSync.entitlements SylSmart/SylSmart.entitlements >/dev/null || fail "WiFi Info entitlement missing"

echo "PASS: WiFi Gateway network connectivity static checks"
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_network_connectivity.sh
```

Expected:

```text
PASS: WiFi Gateway network connectivity static checks
```

- [ ] **Step 3: Commit task**

```bash
git add scripts/check_wifi_gateway_network_connectivity.sh
git commit -m "test: add wifi gateway connectivity check"
```

---

### Task 8: Final Verification

**Files:**
- All changed files from Tasks 1-7.

- [ ] **Step 1: Confirm working tree scope**

Run:

```bash
git status --short
```

Expected: only intentional files are modified/staged. Existing image assets may remain staged from before this plan; do not remove or revert them.

- [ ] **Step 2: Run static checks**

```bash
git diff --check
scripts/check_wifi_gateway_network_connectivity.sh
plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/en.lproj/InfoPlist.strings SunSmart/zh-Hans.lproj/InfoPlist.strings SunSmart/Info.plist Archipelago/Archipelago-Info.plist SLGSync/SLGSync-Info.plist SylSmart/SylSmart-Info.plist
```

Expected:

- `git diff --check` exits 0.
- Script prints `PASS`.
- `plutil` reports each file `OK`.

- [ ] **Step 3: Build SunSmart for iPhoneOS**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Build other affected brand targets**

Run serially:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme "SLG Sync Plus" -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: each target prints `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual acceptance checklist**

On a real or development build:

```text
1. Open WiFi Gateway CID 0x0A78 / PID 0x2721.
2. Confirm Network Connectivity appears below Activate and above Associated Spaces.
3. Confirm Password is empty on every page open.
4. Enter fewer than 8 ASCII chars: Connect is disabled.
5. Enter 8 ASCII chars: Connect is enabled.
6. Enter non-ASCII char: input is rejected or warning appears.
7. Tap Connect: button shows loading for about 2 seconds.
8. After 2 seconds: button shows Disconnect.
9. Tap Disconnect: SSID and Password clear, Connect becomes disabled.
10. Tap select_wifi: alert appears with connect_wifi_intro and Go to System Settings.
11. Return from Settings: SSID refresh attempts when not connected/connecting.
12. Open a non-WiFi Gateway: Network Connectivity is absent.
```

- [ ] **Step 6: Final status report**

Run:

```bash
git status --short
```

Expected: no unexpected modified files. If verification revealed a concrete failure, fix the exact failing file in the relevant earlier task and rerun Task 8 from Step 1.
