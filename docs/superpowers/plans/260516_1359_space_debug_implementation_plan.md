# Space Debug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Space-level Debug flow that scans real Mesh nodes, shows RSSI and availability, connects directly to a selected node, and restores the normal Space Mesh auto-connection when the flow exits.

**Architecture:** `SpaceViewController` only owns the menu entry and restoration callback. The Debug feature lives under `SunSmart/Main/Space/Debug/`, with a view model for sections and throttled RSSI state, a Bluetooth session wrapper for Mesh SDK lifecycle, a scan list page, and a dedicated diagnostic detail page. Version 1 uses the existing NordicSigMeshSDK public scan and `connectProxy(node:)` APIs, stores scanned `CBPeripheral` references inside the Debug session, and keeps the UI isolated so a future UART / serial-log bridge can be added without coupling the pages to CoreBluetooth delegates.

**Tech Stack:** UIKit, SnapKit, NordicSigMeshSDK, CoreBluetooth, UITableView, Xcode project PBX source membership, localized `.strings`.

---

## File Map

- Create: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
  - Shared enums and value objects for categories, scan state, connection state, and display rows.
- Create: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
  - Owns real-node snapshots, category grouping, found state, connecting state, and 1 second UI refresh throttling.
- Create: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
  - Owns Debug lifecycle: disconnect normal Space Mesh, reload current Mesh without opening auto connection, scan RSSI, stop scan, connect selected node, disconnect Debug link, and report unexpected disconnects.
- Create: `SunSmart/Main/Space/Debug/SpaceDebugSummaryView.swift`
  - Header view with state and `Found / Total`.
- Create: `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`
  - List cell showing icon, group/device name, RSSI, signal bars, and found/not-found/connecting state.
- Create: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
  - Debug scan home page with grouped table, Scan/Stop action, connect-failure alert, and flow cleanup.
- Create: `SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`
  - Dedicated diagnostic detail page with connection status, node metadata, and reserved BLE Services section.
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - Add the `Debug` menu item after `Share`; push the Debug flow; restore normal Space connection after the Debug flow exits.
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - Add Debug feature strings.
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add Debug feature strings.
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - Add the new Swift files to the project group and the source phases for `SunSmart`, `Archipelago`, `SLG Sync Plus`, and `SylSmart`.

## Existing Anchors

- Space menu: `SunSmart/Main/Space/Controller/SpaceViewController.swift`, `moreClick()`.
- Normal Space Mesh connection: `SpaceViewController.setNetworkConnected()`.
- Debug entry permission source: `SpaceData.canEditing` in `SunSmart/Common/Data/SpaceData.swift`.
- Device categories: `Node.DeviceType` in `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`.
- RSSI scan: `MeshLibManager.manager.refreshNodesRSSI(withWaitFor:nodeScan:finished:)`.
- Stop RSSI scan: `MeshLibManager.manager.stopRefreshNodesRSSI()`.
- Direct node proxy connection: `MeshLibManager.manager.connectProxy(node:result:)`.
- Disconnect selected proxy: call `MeshLibManager.manager.close()` and then `meshNetworkDisconnect()` because the package version currently resolved by the app does not expose `disconnectProxy(node:)`.
- Load Mesh without auto-open: `MeshLibManager.manager.setMeshNetworkConnected(meshUUID:subNetworkId:connected: false)`.
- Reload normal Space connection after Debug: call existing `SpaceViewController.setNetworkConnected()` from a closure created inside `SpaceViewController`.

## Verification Commands

- Primary build:
  - Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-build.log 2>&1"`
  - Expected: exit code `0`.
- Cross-target checks after source membership changes:
  - Run the same command with `-scheme Archipelago`.
  - Run the same command with `-scheme 'SLG Sync Plus'`.
  - Run the same command with `-scheme SylSmart`.
  - Expected: exit code `0` for each scheme.
- Manual BLE validation requires physical devices in a provisioned Space; simulator cannot verify scan/connect behavior.

## Task 1: Add Debug Localized Strings

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English strings near the existing common action keys**

```text
"debug" = "Debug";
"debug_preparing" = "Preparing";
"debug_scanning" = "Scanning";
"debug_stopped" = "Stopped";
"debug_found_format" = "%d / %d Found";
"debug_found" = "Found";
"debug_not_found" = "Not Found";
"debug_node_address" = "Node Address";
"debug_pid" = "PID";
"debug_cid" = "CID";
"debug_proxy" = "Proxy";
"debug_supported" = "Supported";
"debug_not_supported" = "Not Supported";
"debug_connected" = "Connected";
"debug_disconnected" = "Disconnected";
"debug_reconnecting" = "Reconnecting";
"debug_connection_failed_message" = "Connection failed.";
"debug_connection_disconnected_message" = "The device connection was disconnected.";
"debug_reconnect" = "Re-connect";
"debug_ble_services" = "BLE Services";
"debug_ble_services_empty" = "No BLE services are shown in this version.";
```

- [ ] **Step 2: Add Simplified Chinese strings at the matching position**

```text
"debug" = "调试";
"debug_preparing" = "准备中";
"debug_scanning" = "扫描中";
"debug_stopped" = "已停止";
"debug_found_format" = "已找到 %d / %d";
"debug_found" = "已找到";
"debug_not_found" = "未找到";
"debug_node_address" = "节点地址";
"debug_pid" = "PID";
"debug_cid" = "CID";
"debug_proxy" = "代理";
"debug_supported" = "支持";
"debug_not_supported" = "不支持";
"debug_connected" = "已连接";
"debug_disconnected" = "已断开";
"debug_reconnecting" = "重连中";
"debug_connection_failed_message" = "连接失败。";
"debug_connection_disconnected_message" = "设备连接已断开。";
"debug_reconnect" = "重新连接";
"debug_ble_services" = "BLE Services";
"debug_ble_services_empty" = "当前版本不展示 BLE Services。";
```

- [ ] **Step 3: Verify the strings exist exactly once**

Run: `rg -n '"debug"|"debug_found_format"|"debug_connection_failed_message"|"debug_ble_services_empty"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings`

Expected: each key appears once in each localization file.

- [ ] **Step 4: Commit**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add space debug strings"
```

## Task 2: Add Debug Models

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`

- [ ] **Step 1: Create the Debug folder**

Run: `mkdir -p SunSmart/Main/Space/Debug`

Expected: `SunSmart/Main/Space/Debug` exists.

- [ ] **Step 2: Add model definitions**

```swift
import CoreBluetooth
import Foundation
import NordicSigMeshSDK

enum SpaceDebugDeviceCategory: Int, CaseIterable {
    case lights
    case switches
    case sensors
    case others

    init(node: Node) {
        switch node.deviceType {
        case .light:
            self = .lights
        case .switches:
            self = .switches
        case .sensor:
            self = .sensors
        case .dongle, .gateway, .emergencyController, .unknown:
            self = .others
        }
    }

    var title: String {
        switch self {
        case .lights:
            return "lights".localizedString
        case .switches:
            return "switches".localizedString
        case .sensors:
            return "sensors".localizedString
        case .others:
            return "others".localizedString
        }
    }
}

enum SpaceDebugScanState {
    case idle
    case preparing
    case scanning
    case stopped
    case connecting(Address)

    var title: String {
        switch self {
        case .idle, .stopped:
            return "debug_stopped".localizedString
        case .preparing:
            return "debug_preparing".localizedString
        case .scanning:
            return "debug_scanning".localizedString
        case .connecting:
            return "connecting".localizedString
        }
    }
}

enum SpaceDebugConnectionState {
    case connecting
    case connected
    case reconnecting
    case disconnected

    var title: String {
        switch self {
        case .connecting:
            return "connecting".localizedString
        case .connected:
            return "debug_connected".localizedString
        case .reconnecting:
            return "debug_reconnecting".localizedString
        case .disconnected:
            return "debug_disconnected".localizedString
        }
    }
}

struct SpaceDebugNodeItem {
    let node: Node
    var peripheral: CBPeripheral?
    var rssi: Int?
    var lastSeen: Date?
    var isConnecting: Bool = false

    var address: Address {
        node.primaryUnicastAddress
    }

    var category: SpaceDebugDeviceCategory {
        SpaceDebugDeviceCategory(node: node)
    }

    var isFound: Bool {
        peripheral != nil && rssi != nil
    }

    var groupName: String? {
        node.group?.name
    }

    var nodeName: String {
        node.name ?? "\(node.primaryUnicastAddress)"
    }

    var displayTitle: String {
        if let groupName = groupName, !groupName.isEmpty {
            return "\(groupName) - \(nodeName)"
        }
        return nodeName
    }
}

struct SpaceDebugSection {
    let category: SpaceDebugDeviceCategory
    var items: [SpaceDebugNodeItem]
}
```

- [ ] **Step 3: Confirm the file is present**

Run: `rg -n "SpaceDebugDeviceCategory|SpaceDebugNodeItem|SpaceDebugSection" SunSmart/Main/Space/Debug/SpaceDebugModels.swift`

Expected: all three symbols are printed.

## Task 3: Add the Debug View Model

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`

- [ ] **Step 1: Add the view model**

```swift
import Foundation
import NordicSigMeshSDK

final class SpaceDebugViewModel {
    var onSnapshotChanged: (() -> Void)?

    private var itemsByAddress: [Address: SpaceDebugNodeItem]
    private var scanState: SpaceDebugScanState = .idle
    private var pendingRefresh: DispatchWorkItem?

    init(nodes: [Node]) {
        self.itemsByAddress = Dictionary(
            uniqueKeysWithValues: nodes.map { node in
                (node.primaryUnicastAddress, SpaceDebugNodeItem(node: node))
            }
        )
    }

    var totalCount: Int {
        itemsByAddress.count
    }

    var foundCount: Int {
        itemsByAddress.values.filter(\.isFound).count
    }

    var currentScanState: SpaceDebugScanState {
        scanState
    }

    func replaceNodes(_ nodes: [Node]) {
        itemsByAddress = Dictionary(
            uniqueKeysWithValues: nodes.map { node in
                (node.primaryUnicastAddress, SpaceDebugNodeItem(node: node))
            }
        )
        onSnapshotChanged?()
    }

    func setScanState(_ state: SpaceDebugScanState) {
        scanState = state
        onSnapshotChanged?()
    }

    func resetFoundState() {
        itemsByAddress = Dictionary(
            uniqueKeysWithValues: itemsByAddress.values.map { item in
                var next = item
                next.peripheral = nil
                next.rssi = nil
                next.lastSeen = nil
                next.isConnecting = false
                return (next.address, next)
            }
        )
        onSnapshotChanged?()
    }

    func updateFoundNode(_ data: MeshNodePeripheralData) {
        let address = data.node.primaryUnicastAddress
        guard var item = itemsByAddress[address] else {
            return
        }
        item.peripheral = data.peripheral
        item.rssi = data.rssi.intValue
        item.lastSeen = Date()
        itemsByAddress[address] = item
        scheduleSnapshotRefresh()
    }

    func setConnecting(address: Address?) {
        itemsByAddress = Dictionary(
            uniqueKeysWithValues: itemsByAddress.values.map { item in
                var next = item
                next.isConnecting = address == item.address
                return (next.address, next)
            }
        )
        if let address = address {
            scanState = .connecting(address)
        }
        onSnapshotChanged?()
    }

    func item(at indexPath: IndexPath) -> SpaceDebugNodeItem {
        sections()[indexPath.section].items[indexPath.row]
    }

    func sections() -> [SpaceDebugSection] {
        SpaceDebugDeviceCategory.allCases.map { category in
            let items = itemsByAddress.values
                .filter { $0.category == category }
                .sorted { lhs, rhs in
                    if lhs.isFound != rhs.isFound {
                        return lhs.isFound && !rhs.isFound
                    }
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
            return SpaceDebugSection(category: category, items: items)
        }.filter { !$0.items.isEmpty }
    }

    private func scheduleSnapshotRefresh() {
        guard pendingRefresh == nil else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingRefresh = nil
            self?.onSnapshotChanged?()
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}
```

- [ ] **Step 2: Confirm the throttling code is present**

Run: `rg -n "scheduleSnapshotRefresh|asyncAfter\\(deadline: \\.now\\(\\) \\+ 1\\.0|foundCount" SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`

Expected: the throttled refresh method, 1 second delay, and `foundCount` are printed.

## Task 4: Add the Debug Bluetooth Session

**Files:**
- Create: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`

- [ ] **Step 1: Add the session wrapper**

```swift
import CoreBluetooth
import Foundation
import NordicSigMeshSDK

final class DebugBluetoothSession {
    var onUnexpectedDisconnect: ((Node) -> Void)?

    private let space: SpaceData
    private var connectedNode: Node?
    private var isEnding = false
    private var isConnecting = false
    private var meshConnectionObservation: NSKeyValueObservation?

    init(space: SpaceData) {
        self.space = space
        observeMeshConnection()
    }

    deinit {
        finish()
    }

    func prepare(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            MeshLibManager.manager.stopRefreshNodesRSSI()
            MeshLibManager.manager.meshNetworkDisconnect()
            MeshLibManager.manager.setMeshNetworkConnected(
                meshUUID: self.space.meshUUID,
                subNetworkId: self.space.meshNetworkId,
                connected: false
            )

            guard let manager = MeshLibManager.manager.meshNetworkManager else {
                completion(false)
                return
            }

            manager.loadExtensionData { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    func startScan(onNodeFound: @escaping (MeshNodePeripheralData) -> Void) {
        MeshLibManager.manager.stopRefreshNodesRSSI()
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 99999, nodeScan: { data in
            DispatchQueue.main.async {
                onNodeFound(data)
            }
        }, finished: nil)
    }

    func stopScan() {
        MeshLibManager.manager.stopRefreshNodesRSSI()
    }

    func connect(_ item: SpaceDebugNodeItem, completion: @escaping (Bool) -> Void) {
        stopScan()
        connectedNode = item.node
        isConnecting = true
        MeshLibManager.manager.connectProxy(node: item.node) { [weak self] success in
            DispatchQueue.main.async {
                self?.isConnecting = false
                if !success {
                    self?.connectedNode = nil
                }
                completion(success)
            }
        }
    }

    func reconnect(completion: @escaping (Bool) -> Void) {
        guard let node = connectedNode else {
            completion(false)
            return
        }
        isConnecting = true
        MeshLibManager.manager.connectProxy(node: node) { [weak self] success in
            DispatchQueue.main.async {
                self?.isConnecting = false
                completion(success)
            }
        }
    }

    func finish() {
        guard !isEnding else {
            return
        }
        isEnding = true
        stopScan()
        if connectedNode != nil {
            MeshLibManager.manager.close()
        }
        MeshLibManager.manager.meshNetworkDisconnect()
        connectedNode = nil
        meshConnectionObservation = nil
    }

    private func observeMeshConnection() {
        meshConnectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async {
                guard !self.isEnding, !self.isConnecting, !MeshLibManager.manager.isMeshNetworkConnected, let node = self.connectedNode else {
                    return
                }
                self.onUnexpectedDisconnect?(node)
            }
        }
    }
}
```

- [ ] **Step 2: Confirm the session uses the correct Debug lifecycle**

Run: `rg -n "connected: false|refreshNodesRSSI\\(withWaitFor: 99999|connectProxy\\(node|meshNetworkDisconnect" SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`

Expected: all lifecycle calls are printed.

## Task 5: Add the Summary Header View

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugSummaryView.swift`

- [ ] **Step 1: Add the header view**

```swift
import UIKit

final class SpaceDebugSummaryView: UIView {
    private let stateLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: SpaceDebugScanState, found: Int, total: Int) {
        stateLabel.text = state.title
        countLabel.text = String(format: "debug_found_format".localizedString, found, total)
    }

    private func setupUI() {
        backgroundColor = Background_Color

        let container = UIView()
        container.backgroundColor = .white
        container.layer.cornerRadius = SCRXFrom(8)
        addSubview(container)
        container.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(8))
        }

        stateLabel.font = Font_Medium_Size(15)
        stateLabel.textColor = Title_Color
        container.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }

        countLabel.font = FONTS(SCRXFrom(13))
        countLabel.textColor = SubText_Color
        container.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.left.greaterThanOrEqualTo(stateLabel.snp.right).offset(SCRXFrom(12))
        }
    }
}
```

- [ ] **Step 2: Confirm the header exposes the update API**

Run: `rg -n "func update\\(state: SpaceDebugScanState, found: Int, total: Int\\)" SunSmart/Main/Space/Debug/SpaceDebugSummaryView.swift`

Expected: the update method is printed.

## Task 6: Add the Debug Device Cell

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`

- [ ] **Step 1: Add the table cell**

```swift
import UIKit

final class SpaceDebugDeviceCell: UITableViewCell {
    static let reuseIdentifier = "SpaceDebugDeviceCell"

    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let signalStrengthView = DeviceSignalStrengthView()
    private let rssiLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(item: SpaceDebugNodeItem) {
        iconImageView.image = UIImage(named: item.isFound ? item.node.iconName : item.node.offlineIconName)
        nameLabel.text = item.displayTitle

        if item.isConnecting {
            statusLabel.text = "connecting".localizedString
        } else {
            statusLabel.text = item.isFound ? "debug_found".localizedString : "debug_not_found".localizedString
        }

        if let rssi = item.rssi {
            signalStrengthView.setSignalStrength(rssi: rssi)
            rssiLabel.text = "\(rssi)dBm"
        } else {
            signalStrengthView.setSignalStrength(rssi: -120)
            rssiLabel.text = "--"
        }

        let enabled = item.isFound && !item.isConnecting
        contentView.alpha = enabled ? 1.0 : 0.45
        selectionStyle = enabled ? .gray : .none
        isUserInteractionEnabled = enabled || item.isConnecting
    }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .white

        iconImageView.contentMode = .scaleAspectFit
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: SCRXFrom(36), height: SCRXFrom(36)))
        }

        nameLabel.font = FONTS(SCRXFrom(15))
        nameLabel.textColor = Title_Color
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(12))
            make.right.lessThanOrEqualTo(signalStrengthView.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(12))
        }

        statusLabel.font = FONTS(SCRXFrom(12))
        statusLabel.textColor = SubText_Color
        contentView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.lessThanOrEqualTo(SCRYFrom(-12))
        }

        signalStrengthView.setSignalStrength(rssi: -120)
        contentView.addSubview(signalStrengthView)
        signalStrengthView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview().offset(SCRYFrom(-8))
            make.size.equalTo(CGSize(width: SCRXFrom(56), height: SCRYFrom(14)))
        }

        rssiLabel.font = FONTS(SCRXFrom(12))
        rssiLabel.textColor = SubText_Color
        rssiLabel.textAlignment = .right
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.right.equalTo(signalStrengthView)
            make.top.equalTo(signalStrengthView.snp.bottom).offset(SCRYFrom(4))
        }
    }
}
```

- [ ] **Step 2: Confirm the cell uses existing signal bars**

Run: `rg -n "DeviceSignalStrengthView|debug_not_found|offlineIconName" SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`

Expected: all three references are printed.

## Task 7: Add the Debug Detail Page

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`

- [ ] **Step 1: Add the detail controller**

```swift
import UIKit
import NordicSigMeshSDK

final class SpaceDebugDeviceViewController: UIViewController {
    private let session: DebugBluetoothSession
    private let item: SpaceDebugNodeItem
    private let statusLabel = UILabel()
    private let stackView = UIStackView()
    private var connectionState: SpaceDebugConnectionState = .connected

    init(session: DebugBluetoothSession, item: SpaceDebugNodeItem) {
        self.session = session
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.displayTitle
        view.backgroundColor = Background_Color
        setupUI()
        render()

        session.onUnexpectedDisconnect = { [weak self] node in
            guard let self = self, node.primaryUnicastAddress == self.item.node.primaryUnicastAddress else {
                return
            }
            self.connectionState = .disconnected
            self.render()
            self.showDisconnectedAlert()
        }
    }

    private func setupUI() {
        statusLabel.font = Font_Medium_Size(15)
        statusLabel.textColor = Title_Color
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
        }

        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(10)
        view.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(statusLabel.snp.bottom).offset(SCRYFrom(16))
        }
    }

    private func render() {
        statusLabel.text = connectionState.title
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        addInfoRow(title: "debug_node_address".localizedString, value: "\(item.node.primaryUnicastAddress)")
        addInfoRow(title: "mac".localizedString, value: item.node.macAddressResult ?? item.node.macAddress ?? "--")
        addInfoRow(title: "RSSI", value: item.rssi.map { "\($0)dBm" } ?? "--")
        addInfoRow(title: "debug_pid".localizedString, value: item.node.productIdentifier.map { String(format: "0x%04X", $0) } ?? "--")
        addInfoRow(title: "debug_cid".localizedString, value: item.node.companyIdentifier.map { String(format: "0x%04X", $0) } ?? "--")
        addInfoRow(title: "device_type".localizedString, value: item.category.title)
        addInfoRow(title: "debug_proxy".localizedString, value: item.node.features?.proxy == .enabled ? "debug_supported".localizedString : "debug_not_supported".localizedString)
        addInfoRow(title: "debug_ble_services".localizedString, value: "debug_ble_services_empty".localizedString)
    }

    private func addInfoRow(title: String, value: String) {
        let row = UIView()
        row.backgroundColor = .white
        row.layer.cornerRadius = SCRXFrom(8)

        let titleLabel = UILabel()
        titleLabel.font = FONTS(SCRXFrom(13))
        titleLabel.textColor = SubText_Color
        titleLabel.text = title
        row.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(12))
        }

        let valueLabel = UILabel()
        valueLabel.font = FONTS(SCRXFrom(13))
        valueLabel.textColor = Title_Color
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.text = value
        row.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }

        stackView.addArrangedSubview(row)
    }

    private func showDisconnectedAlert() {
        SRAlertView(title: "notification".localizedString, message: "debug_connection_disconnected_message".localizedString, actions: [
            SRAlertAction(title: "close".localizedString, actionHandler: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }),
            SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
                self?.reconnect()
            })
        ]).show()
    }

    private func reconnect() {
        connectionState = .reconnecting
        render()
        session.reconnect { [weak self] success in
            guard let self = self else {
                return
            }
            self.connectionState = success ? .connected : .disconnected
            self.render()
            if !success {
                self.showDisconnectedAlert()
            }
        }
    }
}
```

- [ ] **Step 2: Confirm the alert actions match the requirement**

Run: `rg -n "debug_connection_disconnected_message|debug_reconnect|popViewController|reconnect\\(\\)" SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`

Expected: the disconnected alert, Close behavior, and Re-connect behavior are printed.

## Task 8: Add the Debug Scan Home Page

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

- [ ] **Step 1: Add the scan controller**

```swift
import UIKit
import NordicSigMeshSDK

final class SpaceDebugViewController: UIViewController {
    private let space: SpaceData
    private let session: DebugBluetoothSession
    private let viewModel: SpaceDebugViewModel
    private let onFlowFinished: () -> Void
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let summaryView = SpaceDebugSummaryView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFrom(68)))
    private var didPrepare = false
    private var didFinishFlow = false

    init(space: SpaceData, onFlowFinished: @escaping () -> Void) {
        self.space = space
        self.session = DebugBluetoothSession(space: space)
        self.viewModel = SpaceDebugViewModel(nodes: [])
        self.onFlowFinished = onFlowFinished
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "debug".localizedString
        view.backgroundColor = Background_Color
        setupUI()
        bindViewModel()
        prepareAndStartScan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        finishFlow()
    }

    deinit {
        finishFlow()
    }

    private func setupUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "stop".localizedString, style: .plain, target: self, action: #selector(scanButtonTapped))

        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.tableHeaderView = summaryView
        tableView.rowHeight = SCRYFrom(72)
        tableView.register(SpaceDebugDeviceCell.self, forCellReuseIdentifier: SpaceDebugDeviceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func bindViewModel() {
        viewModel.onSnapshotChanged = { [weak self] in
            self?.reloadSnapshot()
        }
        reloadSnapshot()
    }

    private func prepareAndStartScan() {
        guard !didPrepare else {
            startScan(reset: false)
            return
        }
        didPrepare = true
        viewModel.setScanState(.preparing)
        session.prepare { [weak self] success in
            guard let self = self else {
                return
            }
            self.viewModel.replaceNodes(MeshNetworkManager.instance.realNodes)
            guard self.viewModel.currentScanState == .preparing else {
                return
            }
            if success, self.viewModel.totalCount > 0 {
                self.startScan(reset: false)
            } else {
                self.viewModel.setScanState(.stopped)
                self.navigationItem.rightBarButtonItem?.title = "scan".localizedString
            }
        }
    }

    private func startScan(reset: Bool) {
        if reset {
            viewModel.resetFoundState()
        }
        viewModel.setScanState(.scanning)
        navigationItem.rightBarButtonItem?.title = "stop".localizedString
        navigationItem.rightBarButtonItem?.isEnabled = true
        session.startScan { [weak self] data in
            self?.viewModel.updateFoundNode(data)
        }
    }

    private func stopScan() {
        session.stopScan()
        viewModel.setScanState(.stopped)
        navigationItem.rightBarButtonItem?.title = "scan".localizedString
        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    @objc private func scanButtonTapped() {
        switch viewModel.currentScanState {
        case .scanning, .preparing:
            stopScan()
        case .idle, .stopped:
            startScan(reset: true)
        case .connecting:
            break
        }
    }

    private func reloadSnapshot() {
        summaryView.update(state: viewModel.currentScanState, found: viewModel.foundCount, total: viewModel.totalCount)
        tableView.reloadData()
    }

    private func connect(_ item: SpaceDebugNodeItem) {
        guard item.isFound else {
            return
        }
        stopScan()
        viewModel.setConnecting(address: item.address)
        navigationItem.rightBarButtonItem?.isEnabled = false
        session.connect(item) { [weak self] success in
            guard let self = self else {
                return
            }
            self.viewModel.setConnecting(address: nil)
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            if success {
                let detail = SpaceDebugDeviceViewController(session: self.session, item: item)
                self.navigationController?.pushViewController(detail, animated: true)
            } else {
                self.showConnectionFailedAlert()
            }
        }
    }

    private func showConnectionFailedAlert() {
        SRAlertView(title: "failed".localizedString, message: "debug_connection_failed_message".localizedString, actions: [
            SRAlertAction(title: "ok".localizedString, actionHandler: nil),
            SRAlertAction(title: "scan".localizedString, actionHandler: { [weak self] _ in
                self?.startScan(reset: true)
            })
        ]).show()
    }

    private func finishFlow() {
        guard !didFinishFlow else {
            return
        }
        didFinishFlow = true
        session.finish()
        onFlowFinished()
    }
}

extension SpaceDebugViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections().count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections()[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections()[section].category.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SpaceDebugDeviceCell.reuseIdentifier, for: indexPath) as! SpaceDebugDeviceCell
        cell.update(item: viewModel.item(at: indexPath))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        connect(viewModel.item(at: indexPath))
    }
}
```

- [ ] **Step 2: Confirm the scan flow has the required actions**

Run: `rg -n "prepareAndStartScan|startScan\\(reset:|stopScan\\(\\)|showConnectionFailedAlert|finishFlow" SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

Expected: prepare, scan, stop, connect-failure alert, and finish methods are printed.

## Task 9: Add Debug Files to the Xcode Project

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add PBX file references and a `Debug` group under the existing `Space` group**

Use stable new IDs and add file references for:

```text
SpaceDebugModels.swift
SpaceDebugViewModel.swift
DebugBluetoothSession.swift
SpaceDebugSummaryView.swift
SpaceDebugDeviceCell.swift
SpaceDebugViewController.swift
SpaceDebugDeviceViewController.swift
```

Insert the new `Debug` group under `C898E3032ABBF3BF00C71315 /* Space */`, next to `TriggerZone`, `Controller`, `Model`, and `View`.

- [ ] **Step 2: Add build files for all four app targets**

Add one PBXBuildFile per new Swift file per target source phase:

```text
C88553B12DE6B44C00C8B688 /* Sources */ for Archipelago
C886E0012E30DE4900D0C3A6 /* Sources */ for SylSmart
C896B9A02A930BA800217512 /* Sources */ for SunSmart
C8BB65AF2ED3F056000C63EE /* Sources */ for SLG Sync Plus
```

- [ ] **Step 3: Verify every new file appears five times**

Each file should appear once as a `PBXFileReference` and four times as `PBXBuildFile` entries.

Run: `rg -n "SpaceDebugModels.swift|SpaceDebugViewModel.swift|DebugBluetoothSession.swift|SpaceDebugSummaryView.swift|SpaceDebugDeviceCell.swift|SpaceDebugViewController.swift|SpaceDebugDeviceViewController.swift" SunSmart.xcodeproj/project.pbxproj`

Expected: each filename appears in the file reference section, the `Debug` group, and all four source build phases.

- [ ] **Step 4: Run the primary build to catch model/UI compile errors**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-build.log 2>&1"`

Expected: exit code `0`. If it fails, inspect `/tmp/sun-smart-space-debug-build.log` and fix only errors caused by the new Debug files.

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Space/Debug SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add space debug flow skeleton"
```

## Task 10: Hook Debug Into the Space Menu

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1: Add the `Debug` item after `Share`**

In `moreClick()`, append this block after the existing share item block and before the existing unbind item block:

```swift
if space.canEditing {
    items.append(.init(icon: UIImage(named: "menu_information"), title: "debug".localizedString, tapItemBack: { [weak self] _ in
        self?.openSpaceDebug()
    }))
}
```

- [ ] **Step 2: Add the Debug route inside `SpaceViewController`**

Add this private method near the other Space route helpers:

```swift
private func openSpaceDebug() {
    let vc = SpaceDebugViewController(space: space) { [weak self] in
        self?.setNetworkConnected()
    }
    navigationController?.pushViewController(vc, animated: true)
}
```

- [ ] **Step 3: Verify menu order in code**

Run: `sed -n '960,1008p' SunSmart/Main/Space/Controller/SpaceViewController.swift`

Expected: the order is edit, delete, share, debug, then unbind.

- [ ] **Step 4: Run the primary build**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-build.log 2>&1"`

Expected: exit code `0`.

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Space/Controller/SpaceViewController.swift
git commit -m "feat: add space debug menu entry"
```

## Task 11: Validate Debug Flow Behavior With Hardware

**Files:**
- No source changes expected in this task. Fix source only if a validation step exposes a defect.

- [ ] **Step 1: Owner/editor menu visibility**

Open a Space as owner or editor.

Expected:
- The menu shows `Edit`, `Delete`, `Share`, `Debug` when those existing operations are permitted.
- The menu shows `Debug` for editor when `space.canEditing` is true.
- Visitor accounts do not show `Debug`.

- [ ] **Step 2: Enter Debug scan page**

Tap `Debug`.

Expected:
- The normal Space Mesh connection is disconnected.
- The Debug page title is `Debug`.
- The right button is `Stop`.
- The header shows scanning state and `Found / Total`.
- The table contains only `MeshNetworkManager.instance.realNodes`.

- [ ] **Step 3: Verify categories**

Check nodes across categories.

Expected:
- `Node.DeviceType.light` appears under `Lights`.
- `Node.DeviceType.switches` appears under `Switches`.
- `Node.DeviceType.sensor` appears under `Sensors`.
- Gateway, dongle, emergency controller, and unknown real nodes appear under `Others`.

- [ ] **Step 4: Verify scan controls**

Let scan run for at least 5 seconds, tap `Stop`, then tap `Scan`.

Expected:
- RSSI values update around once per second while scanning.
- `Stop` stops updates.
- `Scan` clears found state and starts updates again.
- Not-found devices are gray and cannot be selected.

- [ ] **Step 5: Verify successful direct connect**

Tap a found node.

Expected:
- Scanning stops before connection starts.
- The selected row shows connecting state.
- On success, the app pushes the dedicated Debug detail page.
- The detail title is `Group Name - Device Name` when the node has a group, otherwise the node name.
- Detail rows show node address, MAC, RSSI, PID, CID, device type, proxy support, and the reserved BLE Services row.

- [ ] **Step 6: Verify first connection failure**

Use an unreachable node or disable the device during connect.

Expected:
- Alert title is `Failed`.
- Alert message is `Connection failed.`
- Buttons are `OK` and `Scan`.
- `OK` dismisses the alert and leaves the Debug list stopped.
- `Scan` dismisses the alert, resets found state, and resumes scanning.

- [ ] **Step 7: Verify unexpected disconnect on detail**

Disconnect power from the connected device or move out of range after detail page opens.

Expected:
- Detail status changes to `Disconnected`.
- Alert message says the device connection was disconnected.
- `Close` pops back to the Debug list.
- `Re-connect` changes status to `Reconnecting`; success returns to `Connected`; failure shows the same Close/Re-connect options.

- [ ] **Step 8: Verify exit restoration**

From the Debug list, tap Back to return to Space.

Expected:
- Debug scanning stops.
- Any Debug direct connection is disconnected.
- `SpaceViewController.setNetworkConnected()` runs and the Space resumes the normal automatic Mesh connection path.
- Returning from Debug detail to the Debug list does not restore the normal Space connection until the whole Debug flow exits.

## Task 12: Cross-Target Build Verification

**Files:**
- No source changes expected in this task. Fix source membership or compile errors if any target fails.

- [ ] **Step 1: Build `Archipelago`**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-archipelago.log 2>&1"`

Expected: exit code `0`.

- [ ] **Step 2: Build `SLG Sync Plus`**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-slg.log 2>&1"`

Expected: exit code `0`.

- [ ] **Step 3: Build `SylSmart`**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-space-debug-sylsmart.log 2>&1"`

Expected: exit code `0`.

- [ ] **Step 4: Commit verification fixes if needed**

If any target required source-membership or compile fixes:

```bash
git add SunSmart.xcodeproj/project.pbxproj SunSmart/Main/Space/Debug SunSmart/Main/Space/Controller/SpaceViewController.swift
git commit -m "fix: compile space debug across app targets"
```

If all targets pass without fixes, do not create an empty commit.

## Self-Review Checklist

- Spec coverage:
  - Menu entry and owner/editor visibility are covered in Tasks 10 and 11.
  - Real-node-only data source is covered in Tasks 3, 8, and 11.
  - Category grouping is covered in Tasks 2, 3, and 11.
  - Continuous scan, Stop, and Scan are covered in Tasks 4, 8, and 11.
  - RSSI refresh throttling is covered in Task 3.
  - Disabled not-found rows are covered in Task 6.
  - Connect success and dedicated detail page are covered in Tasks 7, 8, and 11.
  - Connect failure alert with `OK` / `Scan` is covered in Task 8.
  - Unexpected detail disconnect alert with `Close` / `Re-connect` is covered in Task 7.
  - Exiting the whole Debug flow and restoring Space auto Mesh is covered in Tasks 4, 8, 10, and 11.
  - A+ future UART boundary is covered by `DebugBluetoothSession`, stored peripheral references in `SpaceDebugNodeItem`, and the reserved BLE Services row.
- Placeholder scan:
  - The plan intentionally avoids forbidden placeholder phrases and vague implementation steps.
- Type consistency:
  - `SpaceDebugNodeItem`, `SpaceDebugSection`, `SpaceDebugScanState`, and `DebugBluetoothSession` names match across tasks.
  - `SpaceDebugViewController(space:onFlowFinished:)` matches the route in `SpaceViewController.openSpaceDebug()`.
  - The session uses current public SDK methods and does not require SDK package switching in version 1.
