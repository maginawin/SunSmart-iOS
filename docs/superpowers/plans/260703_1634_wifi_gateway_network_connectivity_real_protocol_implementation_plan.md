# WiFi Gateway Network Connectivity Real Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference selects Inline Execution by default; do not dispatch subagents unless the user explicitly asks.

**Goal:** Replace the WiFi Gateway Network Connectivity simulation with real `43 0D / 43 0E / 43 12` vendor protocol reads, writes, polling, local password caching, and explicit SSID clearing.

**Architecture:** Keep the behavior scoped to `WiFiGatewayViewController`, with only small parent hooks in `GatewayViewController` for table reload and gateway online-state notifications. `GatewayNetworkConnectivityCell` remains a passive UIKit view that exposes callbacks and accepts controller-owned state. SDK typed enums drive all Wi-Fi status decisions; App never uses `SunricherVendorStatus.status.isSuccessful` for `.connected`.

**Tech Stack:** UIKit, SnapKit, NordicSigMeshSDK vendor messages, `LCWeakTimer`, `UserDefaults`, `.strings` localization, shell static checks, iPhoneOS `xcodebuild`.

---

## Source Spec

- Design doc: `docs/superpowers/specs/260703_1533_wifi_gateway_network_connectivity_real_protocol_design.md`
- Existing simulation plan for historical context only: `docs/superpowers/plans/260703_1040_wifi_gateway_network_connectivity.md`
- Confirmed behavior:
  - Gateway offline/unknown hides Network Connectivity.
  - Gateway configured SSID/password is the display truth and is not overwritten by phone Wi-Fi.
  - Connected state uses `Disconnect` for local clearing.
  - Configured but non-connected state uses SSID clear icon for local clearing.
  - `Refresh` shows phone SSID only after unconfigured/local-clear state.
  - Empty password is valid for open Wi-Fi; non-empty password must be 8-63 supported characters.

## Files

- Modify: `scripts/check_wifi_gateway_network_connectivity.sh`
  - Replace simulation-only assertions with real protocol, status enum, clear button, UserDefaults, and localization checks.
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - Add a table reload hook for dynamic section visibility.
  - Add gateway online-state hook calls used by WiFi Gateway only.
- Modify: `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`
  - Add SSID clear icon button.
  - Allow Change Wi-Fi in connected state.
  - Let controller compute connect state while typing, preserving keyboard focus.
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Remove simulation state.
  - Add gateway credentials/status reads, credentials set, polling, timeout, local clear, and password cache.
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add specific SSID/password validation strings.

---

### Task 1: Update Static Regression Script

**Files:**
- Modify: `scripts/check_wifi_gateway_network_connectivity.sh`

- [ ] **Step 1: Replace simulation assertions with real-protocol assertions**

Edit `scripts/check_wifi_gateway_network_connectivity.sh` so the body after `fail()` contains these checks:

```bash
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
wifi_cell="SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "case networkConnectivity|network_connectivity|GatewayNetworkConnectivityCell" "$gateway_controller" >/dev/null || fail "GatewayViewController missing network connectivity hook"
rg -n "func reloadGatewayTable\\(\\)" "$gateway_controller" >/dev/null || fail "GatewayViewController missing full table reload hook"
rg -n "func gatewayOnlineStateDidUpdate\\(_ isOnline: Bool\\)" "$gateway_controller" >/dev/null || fail "GatewayViewController missing online-state hook"

rg -n "wifiGatewayCredentials|wifiGatewayConnectionStatus|wifiGatewayCredentialsSet" "$wifi_controller" >/dev/null || fail "WiFiGatewayViewController must use real WiFi Gateway vendor protocol"
rg -n "startNetworkConnectionSimulation|finishNetworkConnectionSimulation|disconnectNetworkSimulation" "$wifi_controller" && fail "WiFiGatewayViewController must not keep simulation methods"
rg -n "WiFiGatewayCredentialsReadResult|WiFiGatewayConnectionStatus|WiFiGatewayCredentialsSetResult" "$wifi_controller" >/dev/null || fail "WiFiGatewayViewController must parse typed WiFi Gateway results"
rg -n "status\\.isSuccessful.*connected|connected.*status\\.isSuccessful" "$wifi_controller" && fail "WiFi connection success must not use status.isSuccessful"
rg -n "UserDefaults\\.standard" "$wifi_controller" >/dev/null || fail "WiFi passwords must be cached in UserDefaults"
rg -n "ssidClearCallback|clearNetworkSSIDLocally|showsSSIDClearButton" "$wifi_controller" "$wifi_cell" >/dev/null || fail "SSID clear behavior missing"
rg -n "networkConnectivityVisible|setNetworkConnectivityVisible" "$wifi_controller" >/dev/null || fail "Network Connectivity section visibility must be state-driven"
rg -n "connectionPollTimeout|networkConnectionStartedAt|pollNetworkConnectionStatus" "$wifi_controller" >/dev/null || fail "Connection polling timeout missing"
rg -n "pendingNetworkResultHUD|isNetworkPageVisible" "$wifi_controller" >/dev/null || fail "Subpage HUD suppression behavior missing"

rg -n "ssidClearButton" "$wifi_cell" >/dev/null || fail "SSID clear button missing from cell"
rg -n "selectWiFiButton\\.isEnabled = canSelectWiFi && !isConnecting" "$wifi_cell" >/dev/null || fail "Change Wi-Fi should only be disabled while connecting"
rg -n "passwordChangedCallback: \\(\\(String\\) -> ConnectState\\)\\?" "$wifi_cell" >/dev/null || fail "Controller should compute connect state while typing"
rg -n "nameField_clear|close" "$wifi_cell" >/dev/null || fail "SSID clear button should reuse an existing clear icon"

rg -n '"wifi_gateway_ssid_empty"|"wifi_gateway_password_length_error"|"wifi_gateway_password_character_error"' "$localizable_en" "$localizable_zh" >/dev/null || fail "WiFi Gateway validation localization missing"

echo "PASS: WiFi Gateway network connectivity real protocol static checks"
```

- [ ] **Step 2: Run the script and verify it fails before implementation**

Run:

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
```

Expected: `FAIL` mentioning one of the new real-protocol checks, because simulation methods still exist and real protocol calls are not wired.

- [ ] **Step 3: Commit the failing regression script**

```bash
git add scripts/check_wifi_gateway_network_connectivity.sh
git commit -m "test: cover wifi gateway real connectivity"
```

---

### Task 2: Add Gateway Parent Hooks

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`

- [ ] **Step 1: Add a full table reload hook**

Near `reloadSection(_:)`, add:

```swift
func reloadGatewayTable() {
    tableView.reloadData()
}
```

Keep existing `reloadSection(_:)` unchanged.

- [ ] **Step 2: Add an online-state hook**

Near the other overridable Gateway hooks, add:

```swift
func gatewayOnlineStateDidUpdate(_ isOnline: Bool) {}
```

- [ ] **Step 3: Call the hook after proxy connection completes**

In `setNetworkConnected()` completion, after `self.onlineState = self.node.state`, call:

```swift
self.gatewayOnlineStateDidUpdate(self.node.state)
```

Expected local context:

```swift
self.isConnecting = false
self.headerView.hideConnectingUI()
self.onlineState = self.node.state
self.gatewayOnlineStateDidUpdate(self.node.state)
self.syncSignalRefreshState(forceRefresh: self.node.state)
self.updateData()
self.updateSaveBtnState()
```

- [ ] **Step 4: Call the hook when mesh state changes**

In `meshNetworkManager(_:deviceDataUpdate:)`, keep the hook scoped to state transitions and repeated offline updates. Replace the body of the matching-node branch with:

```swift
if node.state != onlineState {
    onlineState = node.state
    gatewayOnlineStateDidUpdate(node.state)
    syncSignalRefreshState(forceRefresh: node.state)
} else if !node.state {
    gatewayOnlineStateDidUpdate(false)
    syncSignalRefreshState()
}
updateData()
```

Expected: online updates that do not change `node.state` do not reload gateway credentials and do not overwrite a user-cleared SSID.

- [ ] **Step 5: Commit parent hooks**

```bash
git add SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "refactor: add gateway connectivity hooks"
```

---

### Task 3: Update Network Connectivity Cell

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`

- [ ] **Step 1: Add callback and button properties**

Add the callback next to existing callbacks:

```swift
var ssidClearCallback: (() -> Void)?
```

Change password callback to return the controller-computed state:

```swift
var passwordChangedCallback: ((String) -> ConnectState)?
```

Add the clear button next to `selectWiFiButton`:

```swift
private let ssidClearButton = UIButton(type: .custom)
```

- [ ] **Step 2: Clear callback in reuse**

In `prepareForReuse()`, add:

```swift
ssidClearCallback = nil
```

- [ ] **Step 3: Expand the update method**

Replace the current `update(...)` signature with:

```swift
func update(
    ssid: String,
    password: String,
    passwordVisible: Bool,
    connectState: ConnectState,
    showsSSIDClearButton: Bool,
    canSelectWiFi: Bool,
    canRefresh: Bool,
    canEditPassword: Bool
) {
    ssidValueLabel.text = ssid
    currentPassword = password
    passwordTextField.text = password
    passwordTextField.isSecureTextEntry = !passwordVisible
    passwordVisibilityButton.setImage(UIImage(named: passwordVisible ? "show_password" : "hide_password"), for: .normal)
    ssidClearButton.isHidden = !showsSSIDClearButton
    apply(
        connectState: connectState,
        canSelectWiFi: canSelectWiFi,
        canRefresh: canRefresh,
        canEditPassword: canEditPassword
    )
}
```

- [ ] **Step 4: Configure clear button**

In `setupUI()`, after `selectWiFiButton` setup, add:

```swift
ssidClearButton.setImage(UIImage(named: "nameField_clear") ?? UIImage(named: "close"), for: .normal)
ssidClearButton.addTarget(self, action: #selector(clearSSIDAction), for: .touchUpInside)
ssidClearButton.isHidden = true
```

- [ ] **Step 5: Layout clear button between SSID label and Change Wi-Fi**

In `layoutViews()`, add the button to `ssidInputView` and update constraints:

```swift
ssidInputView.addSubview(ssidClearButton)
```

```swift
ssidClearButton.snp.makeConstraints { make in
    make.right.equalTo(selectWiFiButton.snp.left)
    make.centerY.equalToSuperview()
    make.width.height.equalTo(SCRYFrom(30))
}
ssidValueLabel.snp.remakeConstraints { make in
    make.left.equalToSuperview().offset(SCRXFrom(8))
    make.right.equalTo(ssidClearButton.snp.left).offset(SCRXFrom(-4))
    make.centerY.equalToSuperview()
}
```

- [ ] **Step 6: Replace `apply(connectState:)`**

Replace the method with:

```swift
private func apply(
    connectState: ConnectState,
    canSelectWiFi: Bool,
    canRefresh: Bool,
    canEditPassword: Bool
) {
    let isConnecting = connectState == .connecting
    let isConnected = connectState == .connected

    selectWiFiButton.isEnabled = canSelectWiFi && !isConnecting
    refreshButton.isEnabled = canRefresh && !isConnecting
    passwordTextField.isEnabled = canEditPassword && !isConnecting && !isConnected
    passwordVisibilityButton.isEnabled = canEditPassword && !isConnecting && !isConnected
    ssidClearButton.isEnabled = !isConnecting

    loadingImageView.isHidden = !isConnecting
    if isConnecting {
        loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: .max, animationKey: "loading")
    } else {
        loadingImageView.layer.removeAnimation(forKey: "loading")
    }

    let title: String?
    if isConnecting {
        title = nil
    } else if isConnected {
        title = "disconnect".localizedString
    } else {
        title = "connect_to_wifi".localizedString
    }
    connectButton.setTitle(title, for: .normal)
    connectButton.setTitleColor(connectState == .disabled ? RGB(147, 148, 196) : Bar_Color, for: .normal)
    connectButton.isEnabled = connectState != .disabled && !isConnecting
}
```

- [ ] **Step 7: Let controller compute typing state**

Replace the state update in `passwordChanged()` with:

```swift
currentPassword = password
let nextState = passwordChangedCallback?(password) ?? .disabled
apply(
    connectState: nextState,
    canSelectWiFi: selectWiFiButton.isEnabled,
    canRefresh: refreshButton.isEnabled,
    canEditPassword: passwordTextField.isEnabled
)
```

- [ ] **Step 8: Add clear action**

Add:

```swift
@objc private func clearSSIDAction() {
    ssidClearCallback?()
}
```

- [ ] **Step 9: Commit cell changes**

```bash
git add SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift
git commit -m "feat: add wifi gateway ssid clear control"
```

---

### Task 4: Add Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English keys near existing WiFi Gateway keys**

Add to `SunSmart/en.lproj/Localizable.strings`:

```text
"wifi_gateway_ssid_empty" = "Select a Wi-Fi network first.";
"wifi_gateway_password_length_error" = "Leave the password empty for an open Wi-Fi network, or enter 8-63 characters.";
"wifi_gateway_password_character_error" = "Password can only contain letters, numbers, symbols, and spaces. Double quotes and backslashes are not supported.";
```

- [ ] **Step 2: Add Simplified Chinese keys near existing WiFi Gateway keys**

Add to `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"wifi_gateway_ssid_empty" = "请先选择 Wi-Fi 网络。";
"wifi_gateway_password_length_error" = "无密码 Wi-Fi 可留空；如填写密码，请输入 8-63 个字符。";
"wifi_gateway_password_character_error" = "密码只能包含英文字母、数字、符号和空格，不支持双引号或反斜杠。";
```

- [ ] **Step 3: Commit localization**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add wifi gateway validation strings"
```

---

### Task 5: Replace WiFi Gateway Simulation With Real Protocol State

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

- [ ] **Step 1: Replace stored properties**

Replace the current network fields with:

```swift
private enum NetworkCredentialSource {
    case gateway
    case phone
    case localClear
}

private enum PendingNetworkResultHUD {
    case success
    case failure
}

private var networkSSID: String = ""
private var networkPassword: String = ""
private var networkCredentialSource: NetworkCredentialSource = .localClear
private var isNetworkConnectivityVisible: Bool = false
private var isNetworkPasswordVisible: Bool = false
private var networkConnectState: GatewayNetworkConnectivityCell.ConnectState = .disabled
private var networkConnectTimer: Timer?
private var networkConnectionStartedAt: Date?
private var shouldRefreshSSIDWhenActive: Bool = false
private var isNetworkPageVisible: Bool = false
private var pendingNetworkResultHUD: PendingNetworkResultHUD?
private var networkOperationID: Int = 0
private let connectionPollInterval: TimeInterval = 2
private let connectionPollTimeout: TimeInterval = 60
private let wifiPasswordCacheKey = "wifi_gateway_saved_passwords_by_ssid"
```

- [ ] **Step 2: Gate section insertion**

Change `sections` override:

```swift
override var sections: [SectionType] {
    var sections = super.sections
    guard isNetworkConnectivityVisible, let activateIndex = sections.firstIndex(of: .activate) else {
        return sections
    }
    sections.insert(.networkConnectivity, at: sections.index(after: activateIndex))
    return sections
}
```

- [ ] **Step 3: Replace `viewDidLoad` side effect**

Remove the initial `refreshCurrentSSID()` call. Keep the app-active observer.

Expected:

```swift
override func viewDidLoad() {
    super.viewDidLoad()

    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
}
```

- [ ] **Step 4: Track page visibility without stopping child-page polling**

Add:

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    isNetworkPageVisible = true
    showPendingNetworkResultHUDIfNeeded()
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    isNetworkPageVisible = false
    if isMovingFromParent || navigationController?.isBeingDismissed == true || isBeingDismissed {
        stopNetworkConnectionPolling()
    }
}
```

- [ ] **Step 5: Stop polling in deinit**

Replace `networkConnectTimer?.invalidate()` with:

```swift
stopNetworkConnectionPolling()
```

- [ ] **Step 6: Configure the expanded cell API**

Replace `configureNetworkConnectivityCell(_:)` body with:

```swift
let isConnecting = networkConnectState == .connecting
let isConnected = networkConnectState == .connected
let showsClear = shouldShowSSIDClearButton()
cell.update(
    ssid: networkSSID,
    password: networkPassword,
    passwordVisible: isNetworkPasswordVisible,
    connectState: networkConnectState,
    showsSSIDClearButton: showsClear,
    canSelectWiFi: !isConnecting,
    canRefresh: canRefreshPhoneSSID(),
    canEditPassword: !isConnected && !isConnecting
)
cell.selectWiFiCallback = { [weak self] in
    self?.showChangeWiFiAlert()
}
cell.refreshCallback = { [weak self] in
    self?.refreshCurrentSSID(showsResultHUD: true)
}
cell.ssidClearCallback = { [weak self] in
    self?.clearNetworkSSIDLocally()
}
cell.passwordChangedCallback = { [weak self] password in
    self?.updateNetworkPassword(password) ?? .disabled
}
cell.togglePasswordVisibilityCallback = { [weak self] in
    self?.toggleNetworkPasswordVisibility()
}
cell.connectActionCallback = { [weak self] in
    self?.networkConnectButtonAction()
}
```

- [ ] **Step 7: Add gateway online hook**

Add:

```swift
override func gatewayOnlineStateDidUpdate(_ isOnline: Bool) {
    if !isOnline {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    guard networkConnectState != .connecting else { return }
    loadNetworkConnectivityFromGateway()
}
```

- [ ] **Step 8: Add visibility helpers**

Add:

```swift
private func setNetworkConnectivityVisible(_ visible: Bool) {
    guard isNetworkConnectivityVisible != visible else { return }
    isNetworkConnectivityVisible = visible
    reloadGatewayTable()
}

private func hideNetworkConnectivityForOfflineGateway() {
    stopNetworkConnectionPolling()
    networkSSID = ""
    networkPassword = ""
    networkCredentialSource = .localClear
    networkConnectState = .disabled
    isNetworkPasswordVisible = false
    setNetworkConnectivityVisible(false)
}
```

- [ ] **Step 9: Add operation token helper**

Add:

```swift
@discardableResult
private func beginNetworkOperation() -> Int {
    networkOperationID += 1
    return networkOperationID
}

private func isCurrentNetworkOperation(_ operationID: Int) -> Bool {
    operationID == networkOperationID
}
```

- [ ] **Step 10: Add SDK send helpers**

Add:

```swift
private func sendWiFiGatewayGet(
    _ function: VendorFunctionGet,
    timeout: TimeInterval = 10,
    completion: @escaping (SunricherVendorStatus?) -> Void
) {
    guard let vendorModel = node.sunricherVendorModel else {
        completion(nil)
        return
    }
    MeshAPI.sendMessage(message: SunricherVendorGet(function: function), model: vendorModel, timeout: timeout) { response in
        DispatchQueue.main.async {
            completion(response as? SunricherVendorStatus)
        }
    }
}

private func sendWiFiGatewayCredentialsSet(
    _ credentials: WiFiGatewayCredentials,
    timeout: TimeInterval = 10,
    completion: @escaping (WiFiGatewayCredentialsSetResult?) -> Void
) {
    guard let vendorModel = node.sunricherVendorModel else {
        completion(nil)
        return
    }
    MeshAPI.sendMessage(message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)), model: vendorModel, timeout: timeout) { response in
        DispatchQueue.main.async {
            guard let status = response as? SunricherVendorStatus,
                  case .wifiGatewayCredentialsSet(let result) = status.status.parameters else {
                completion(nil)
                return
            }
            completion(result)
        }
    }
}
```

- [ ] **Step 11: Read gateway credentials**

Add:

```swift
private func loadNetworkConnectivityFromGateway() {
    guard node.state else {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    stopNetworkConnectionPolling()
    setNetworkConnectivityVisible(false)
    let operationID = beginNetworkOperation()
    sendWiFiGatewayGet(.wifiGatewayCredentials) { [weak self] status in
        guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
        guard let status,
              case .wifiGatewayCredentialsRead(let result) = status.status.parameters else {
            self.showCredentialsFetchFailedIfVisible()
            return
        }
        switch result {
        case .success(let credentials):
            self.networkSSID = credentials.ssid
            self.networkPassword = credentials.password ?? ""
            self.networkCredentialSource = .gateway
            self.loadConfiguredGatewayConnectionStatus(operationID: operationID)
        case .notConfigured:
            self.networkCredentialSource = .phone
            self.networkConnectState = .disabled
            self.setNetworkConnectivityVisible(true)
            self.refreshCurrentSSID(showsResultHUD: false)
        case .internalError, .reserved:
            self.showCredentialsFetchFailedIfVisible()
        }
    }
}
```

- [ ] **Step 12: Read initial configured gateway status**

Add:

```swift
private func loadConfiguredGatewayConnectionStatus(operationID: Int) {
    sendWiFiGatewayGet(.wifiGatewayConnectionStatus) { [weak self] status in
        guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
        guard let status,
              case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
            self.setNetworkConnectivityVisible(false)
            self.showCredentialsFetchFailedIfVisible()
            return
        }
        self.applyConnectionStatus(connectionStatus, showsHUD: false)
        self.setNetworkConnectivityVisible(true)
        self.reloadSection(.networkConnectivity)
    }
}
```

- [ ] **Step 13: Add status mapping**

Add:

```swift
private func applyConnectionStatus(_ status: WiFiGatewayConnectionStatus, showsHUD: Bool) {
    switch status {
    case .connected:
        networkConnectState = .connected
        if showsHUD {
            handleNetworkConnectionFinished(.success)
        }
    case .notStartedOrConnecting:
        networkConnectState = networkSSID.isEmpty ? .disabled : .available
    case .passwordError, .failed, .reserved:
        networkConnectState = networkSSID.isEmpty ? .disabled : .available
        if showsHUD {
            handleNetworkConnectionFinished(.failure)
        }
    }
}
```

- [ ] **Step 14: Replace phone SSID refresh**

Replace `refreshCurrentSSID(showsResultHUD:)` with:

```swift
private func refreshCurrentSSID(showsResultHUD: Bool = false) {
    guard canRefreshPhoneSSID() else { return }
    WiFiSSIDProvider.shared.fetchCurrentSSID { [weak self] ssid in
        guard let self else { return }
        self.networkSSID = ssid
        self.networkCredentialSource = ssid.isEmpty ? .localClear : .phone
        self.networkPassword = self.cachedPassword(for: ssid)
        self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
        self.reloadSection(.networkConnectivity)
        if showsResultHUD {
            self.showRefreshSSIDResultHUD(success: !ssid.isEmpty)
        }
    }
}
```

Add:

```swift
private func canRefreshPhoneSSID() -> Bool {
    guard networkConnectState != .connecting else { return false }
    return networkCredentialSource != .gateway
}
```

- [ ] **Step 15: Add password cache helpers**

Add:

```swift
private func cachedPassword(for ssid: String) -> String {
    guard !ssid.isEmpty,
          let values = UserDefaults.standard.dictionary(forKey: wifiPasswordCacheKey) as? [String: String] else {
        return ""
    }
    return values[ssid] ?? ""
}

private func saveCachedPassword(_ password: String, for ssid: String) {
    guard !ssid.isEmpty else { return }
    var values = UserDefaults.standard.dictionary(forKey: wifiPasswordCacheKey) as? [String: String] ?? [:]
    values[ssid] = password
    UserDefaults.standard.set(values, forKey: wifiPasswordCacheKey)
}
```

- [ ] **Step 16: Replace password update**

Change `updateNetworkPassword(_:)` to return state:

```swift
private func updateNetworkPassword(_ password: String) -> GatewayNetworkConnectivityCell.ConnectState {
    guard password.canBeConverted(to: .ascii) else {
        XWHUDManager.showTipHUD("wifi_gateway_password_character_error".localizedString, isLineFeed: true)
        return networkConnectState
    }
    networkPassword = password
    networkConnectState = computeEditableConnectState(password: password)
    return networkConnectState
}

private func computeEditableConnectState(password: String) -> GatewayNetworkConnectivityCell.ConnectState {
    guard !networkSSID.isEmpty else { return .disabled }
    guard password.isEmpty || (8...63).contains(password.count) else { return .disabled }
    return .available
}
```

- [ ] **Step 17: Add validation helpers for Connect**

Add:

```swift
private func makeCredentialsForConnect() -> WiFiGatewayCredentials? {
    guard !networkSSID.isEmpty else {
        XWHUDManager.showTipHUD("wifi_gateway_ssid_empty".localizedString, isLineFeed: true)
        return nil
    }
    do {
        return try WiFiGatewayCredentials(ssid: networkSSID, password: networkPassword)
    } catch WiFiGatewayCredentialValidationError.invalidPasswordLength(_) {
        XWHUDManager.showTipHUD("wifi_gateway_password_length_error".localizedString, isLineFeed: true)
        return nil
    } catch WiFiGatewayCredentialValidationError.invalidCharacter(field: .password, byte: _) {
        XWHUDManager.showTipHUD("wifi_gateway_password_character_error".localizedString, isLineFeed: true)
        return nil
    } catch {
        XWHUDManager.showTipHUD("wifi_gateway_ssid_empty".localizedString, isLineFeed: true)
        return nil
    }
}
```

- [ ] **Step 18: Replace button action**

Replace `networkConnectButtonAction()` with:

```swift
private func networkConnectButtonAction() {
    switch networkConnectState {
    case .available:
        connectNetworkWithGateway()
    case .connected:
        clearNetworkByDisconnect()
    case .disabled, .connecting:
        break
    }
}
```

- [ ] **Step 19: Add real connect flow**

Add:

```swift
private func connectNetworkWithGateway() {
    guard let credentials = makeCredentialsForConnect() else { return }
    stopNetworkConnectionPolling()
    networkConnectState = .connecting
    setNetworkConnectivityVisible(true)
    reloadSection(.networkConnectivity)
    let operationID = beginNetworkOperation()
    sendWiFiGatewayCredentialsSet(credentials) { [weak self] result in
        guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
        guard result == .accepted else {
            self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
            self.reloadSection(.networkConnectivity)
            self.handleNetworkConnectionFinished(.failure)
            return
        }
        self.networkConnectionStartedAt = Date()
        self.startNetworkConnectionPolling()
    }
}
```

- [ ] **Step 20: Add polling**

Add:

```swift
private func startNetworkConnectionPolling() {
    networkConnectTimer?.invalidate()
    pollNetworkConnectionStatus()
    networkConnectTimer = LCWeakTimer.scheduledTimer(timeInterval: connectionPollInterval, aTarget: self, selector: #selector(pollNetworkConnectionStatus), userInfo: nil, repeats: true)
    if let networkConnectTimer {
        RunLoop.main.add(networkConnectTimer, forMode: .common)
    }
}

private func stopNetworkConnectionPolling() {
    networkConnectTimer?.invalidate()
    networkConnectTimer = nil
    networkConnectionStartedAt = nil
}

@objc private func pollNetworkConnectionStatus() {
    guard node.state else {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    if let startedAt = networkConnectionStartedAt, Date().timeIntervalSince(startedAt) >= connectionPollTimeout {
        stopNetworkConnectionPolling()
        networkConnectState = computeEditableConnectState(password: networkPassword)
        reloadSection(.networkConnectivity)
        handleNetworkConnectionFinished(.failure)
        return
    }
    sendWiFiGatewayGet(.wifiGatewayConnectionStatus, timeout: connectionPollInterval) { [weak self] status in
        guard let self, self.networkConnectState == .connecting, self.node.state else { return }
        guard let status,
              case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
            return
        }
        switch connectionStatus {
        case .connected:
            self.stopNetworkConnectionPolling()
            self.networkConnectState = .connected
            self.saveCachedPassword(self.networkPassword, for: self.networkSSID)
            self.reloadSection(.networkConnectivity)
            self.handleNetworkConnectionFinished(.success)
        case .passwordError, .failed, .reserved:
            self.stopNetworkConnectionPolling()
            self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
            self.reloadSection(.networkConnectivity)
            self.handleNetworkConnectionFinished(.failure)
        case .notStartedOrConnecting:
            break
        }
    }
}
```

- [ ] **Step 21: Add local clear flows**

Add:

```swift
private func clearNetworkByDisconnect() {
    stopNetworkConnectionPolling()
    clearLocalNetworkFields()
    reloadSection(.networkConnectivity)
}

private func clearNetworkSSIDLocally() {
    guard networkConnectState != .connecting else { return }
    clearLocalNetworkFields()
    reloadSection(.networkConnectivity)
}

private func clearLocalNetworkFields() {
    networkSSID = ""
    networkPassword = ""
    networkCredentialSource = .localClear
    isNetworkPasswordVisible = false
    networkConnectState = .disabled
}
```

- [ ] **Step 22: Add clear and control-state helpers**

Add:

```swift
private func shouldShowSSIDClearButton() -> Bool {
    guard !networkSSID.isEmpty, networkConnectState != .connecting else { return false }
    if networkCredentialSource == .gateway && networkConnectState == .connected {
        return false
    }
    return true
}
```

- [ ] **Step 23: Add HUD handling**

Add:

```swift
private func showCredentialsFetchFailedIfVisible() {
    setNetworkConnectivityVisible(false)
    if isNetworkPageVisible {
        XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
    }
}

private func handleNetworkConnectionFinished(_ result: PendingNetworkResultHUD) {
    if isNetworkPageVisible {
        showNetworkResultHUD(result)
    } else {
        pendingNetworkResultHUD = result
    }
}

private func showPendingNetworkResultHUDIfNeeded() {
    guard let pendingNetworkResultHUD else { return }
    self.pendingNetworkResultHUD = nil
    showNetworkResultHUD(pendingNetworkResultHUD)
}

private func showNetworkResultHUD(_ result: PendingNetworkResultHUD) {
    switch result {
    case .success:
        XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
    case .failure:
        XWHUDManager.showErrorTipHUD("failed".localizedString)
    }
}
```

- [ ] **Step 24: Update password visibility and app-active behavior**

Change `toggleNetworkPasswordVisibility()` guard to block only connecting:

```swift
guard networkConnectState != .connecting else { return }
```

Change `appDidBecomeActive()`:

```swift
@objc private func appDidBecomeActive() {
    guard shouldRefreshSSIDWhenActive else { return }
    shouldRefreshSSIDWhenActive = false
    guard canRefreshPhoneSSID() else { return }
    refreshCurrentSSID()
}
```

- [ ] **Step 25: Keep Change Wi-Fi available while connected**

Leave `showChangeWiFiAlert()` as-is. In `openSystemSettingsForWiFiChange()`, keep:

```swift
shouldRefreshSSIDWhenActive = true
UIApplication.shared.open(settingsURL)
```

Expected: if `networkCredentialSource == .gateway`, `appDidBecomeActive()` does not overwrite gateway SSID/password.

- [ ] **Step 26: Commit controller implementation**

```bash
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "feat: use real wifi gateway connectivity protocol"
```

---

### Task 6: Run Static Checks And Build

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run static regression script**

Run:

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
```

Expected:

```text
PASS: WiFi Gateway network connectivity real protocol static checks
```

- [ ] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect changed files**

Run:

```bash
git status --short
git diff --stat
```

Expected: only the planned files changed.

- [ ] **Step 5: Commit verification fixes if needed**

If build or script requires small fixes, commit only those fixes:

```bash
git add scripts/check_wifi_gateway_network_connectivity.sh SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: stabilize wifi gateway connectivity"
```

Expected: no commit is created if Step 1-3 pass without fixes.

---

## Self-Review Checklist

- Spec coverage:
  - Offline/unknown hides section: Task 5 Step 7-8.
  - Initial credential read: Task 5 Step 11.
  - Configured credential status read: Task 5 Step 12-13.
  - Unconfigured phone SSID and UserDefaults cache: Task 5 Step 14-15.
  - Empty password and password validation: Task 4, Task 5 Step 16-17.
  - Real credentials set and status polling: Task 5 Step 19-20.
  - 60 second timeout: Task 5 Step 20.
  - Subpage polling without immediate HUD: Task 5 Step 4 and Step 23.
  - Disconnect local clear: Task 5 Step 21.
  - SSID clear for configured non-connected state: Task 3 and Task 5 Step 21-22.
  - Connected Change Wi-Fi does not overwrite gateway SSID: Task 5 Step 24-25.
  - No 4G Gateway behavior change: Task 2 parent hooks are inert by default; WiFi behavior remains in `WiFiGatewayViewController`.
- Incomplete-instruction scan: every task names exact files, commands, snippets, and expected results.
- Type consistency:
  - Cell callback returns `GatewayNetworkConnectivityCell.ConnectState`.
  - Controller calls `reloadGatewayTable()` from the parent hook.
  - Controller uses SDK `WiFiGatewayCredentialsReadResult`, `WiFiGatewayCredentialsSetResult`, and `WiFiGatewayConnectionStatus` typed results.
