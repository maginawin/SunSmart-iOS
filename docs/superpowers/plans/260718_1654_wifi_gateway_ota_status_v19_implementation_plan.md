# WiFi Gateway OTA 状态 `0x43/0x11` V1.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session, with review checkpoints after each task.

**Goal:** 将 WiFi Gateway `0x43/0x11` 升级为 V1.9 完整 RET/EVENT 协议，并让 App 严格执行身份匹配、状态归并、查询节奏、断连恢复和 `Upgrade cancelled` UI。

**Architecture:** 本地 NordicSigMeshSDK 只负责严格编解码、EVENT 分流和可并存的连接观察接口；App 使用纯 Swift reducer 管理 OTA 身份与状态顺序，coordinator 管理 Mesh 请求、EVENT、时间和持久化，UIKit 层只渲染状态。SDK 与 App 分仓提交，先完成 SDK typed contract，再完成 App 消费层。

**Tech Stack:** Swift 5、Foundation、UIKit、NordicSigMeshSDK、SIG Mesh Vendor Messages、独立 `swiftc` focused tests、shell contracts、Xcode generic iPhoneOS builds。

## Global Constraints

- 仅实现 `0x43/0x11`；不得编码、发送、模拟或预留可执行的 `0x43/0x15`。
- `CANCEL` 按钮继续禁用；仅实现 `Upgrade cancelled + UPGRADE AGAIN`，不实现 `Failed to cancel + CANCEL AGAIN`。
- EVENT 使用协议 Opcode `0xF50A78`，在当前 SDK UInt32 表示中复用 `SunricherReportMessage.opCode = 0xF5780A`，不得注册第二个相同 Opcode 类型。
- GET 等待上限为 3 秒；非终态 10 秒无新状态才补查；30 秒无合法匹配状态进入通信未知，之后每 30 秒补查。
- 重连后必须先取得本次 GET 的完整合法 RET，才能继续使用 EVENT；不得用断连前缓存判定结果。
- 所有新增用户可见文案同步 English 和简体中文，不硬编码，不新增 Auth 信息。
- 新 App 源文件加入四个共享 target：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。
- iOS 验证只使用 generic iPhoneOS `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。
- 保持改动聚焦，不重构共享 firmware 页面、Mesh manager 或 vendor 基础层的无关代码。
- `SunSmart.xcodeproj/xcshareddata/xcschemes/SunSmart.xcscheme` 不属于本任务；若执行期间出现用户本地改动，不得修改、暂存或提交该文件。

## File Structure

### Local NordicSigMeshSDK repository

- Create: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift` — V1.9 status types and the shared strict parser.
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift` — RET result routing; remove the obsolete inline status parser/types.
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherReportMessage.swift` — parse `43 11 00...` EVENT through the shared parser.
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift` — additive global connection observers.
- Modify: `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift` — SDK integration and response-isolation tests.
- Create: `scripts/check_wifi_gateway_dfu_status_v19.swift` — Foundation-only executable parser contract.

### App worktree

- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift` — pure status identity/order reducer and communication constants.
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift` — UI mapping and V1.9 session persistence.
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift` — EVENT/GET/start lanes, timers, and authoritative reconnect.
- Modify: `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift` — cancelled and communication-unknown rendering.
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — primary button mapping.
- Modify: `SunSmart/en.lproj/Localizable.strings` — English cancelled copy.
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings` — Simplified Chinese cancelled copy.
- Modify: `SunSmart.xcodeproj/project.pbxproj` — reducer membership in four targets.
- Create: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift` — standalone reducer/session tests.
- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — V1.9 static contracts and focused-test invocation.
- Create: `docs/260718_1900_wifi_gateway_ota_status_v19_implementation_summary.md` — final evidence summary.

---

### Task 1: Implement the strict V1.9 RET parser in NordicSigMeshSDK

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/scripts/check_wifi_gateway_dfu_status_v19.swift`

**Interfaces:**
- Produces: `WiFiGatewayDFUStatusParser.parse(_:) -> WiFiGatewayDFUStatus?` for both RET and EVENT.
- Produces: `WiFiGatewayDFUStatus.otaID: UInt64` and V1.9 stage/code enums.
- Produces: `WiFiGatewayDFUStatusResult.busy`.
- Consumes: the existing `FunctionParameters.wifiGatewayDFUStatus` route.

- [ ] **Step 1: Write the failing standalone parser contract**

Create `scripts/check_wifi_gateway_dfu_status_v19.swift` with an `@main` runner. It must build full payloads from the fixed V1.9 offsets and assert the following exact cases:

```swift
import Foundation

@main
struct WiFiGatewayDFUStatusV19Contract {
    static func payload(
        otaID: UInt64,
        stage: UInt8,
        percent: UInt8,
        code: UInt8,
        firmwareID: String = "0.4.0",
        moduleVersion: String? = nil
    ) -> Data {
        var data = Data([0x43, 0x11, 0x00])
        for offset in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: otaID >> UInt64(offset * 8)))
        }
        data.append(contentsOf: [stage, percent, code, UInt8(firmwareID.utf8.count)])
        data.append(contentsOf: firmwareID.utf8)
        let version = moduleVersion ?? ""
        data.append(UInt8(version.utf8.count))
        data.append(contentsOf: version.utf8)
        return data
    }

    static func main() {
        let preparing = WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 0x8877665544332211, stage: 0x0C, percent: 0, code: 0)
        )
        precondition(preparing?.otaID == 0x8877665544332211)
        precondition(preparing?.stage == .preparing)

        let success = WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x08, percent: 100, code: 0,
                    firmwareID: "v0.4.0", moduleVersion: "0.4.0")
        )
        precondition(success?.stage == .success)

        let cancelled = WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x0B, percent: 50, code: 0)
        )
        precondition(cancelled?.stage == .cancelled)

        let metadataFailure = WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x0A, percent: 0, code: 0x18)
        )
        precondition(metadataFailure?.code == .metadata)

        precondition(WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x01, percent: 100, code: 0)
        ) == nil)
        precondition(WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x08, percent: 100, code: 0,
                    firmwareID: "0.4.0", moduleVersion: "0.3.0")
        ) == nil)
        precondition(WiFiGatewayDFUStatusParser.parse(
            payload(otaID: 7, stage: 0x0B, percent: 50, code: 0x04)
        ) == nil)

        print("WiFiGatewayDFUStatusV19Contract passed")
    }
}
```

- [ ] **Step 2: Run the contract and verify it fails before implementation**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift scripts/check_wifi_gateway_dfu_status_v19.swift -o /tmp/WiFiGatewayDFUStatusV19Contract
```

Expected: FAIL because `WiFiGatewayDFUStatus.swift` does not exist yet.

- [ ] **Step 3: Add the V1.9 status types and shared parser**

Create `WiFiGatewayDFUStatus.swift` as a Foundation-only file. Use these exact public cases and parser rules:

```swift
import Foundation

public enum WiFiGatewayDFUStage: UInt8, Equatable, Codable {
    case idle = 0x00
    case downloading = 0x01
    case verifying = 0x02
    case verifyOK = 0x03
    case verifyFail = 0x04
    case rebooting = 0x05
    case recovering = 0x06
    case versionCheck = 0x07
    case success = 0x08
    case timeout = 0x09
    case failed = 0x0A
    case cancelled = 0x0B
    case preparing = 0x0C
}

public enum WiFiGatewayDFUCode: Equatable {
    case none, noNetwork, http, size, verify, version
    case noPartition, noMemory, otaBegin, otaWrite, otaEnd, setBoot
    case internalError, triggerError, triggerTimeout, otaTimeout, protocolError
    case versionProtocol, versionMissing, versionQueryError
    case versionQueryTimeout, versionMismatch, recoveryTimeout, metadata
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .none
        case 0x01: self = .noNetwork
        case 0x02: self = .http
        case 0x03: self = .size
        case 0x04: self = .verify
        case 0x05: self = .version
        case 0x06: self = .noPartition
        case 0x07: self = .noMemory
        case 0x08: self = .otaBegin
        case 0x09: self = .otaWrite
        case 0x0A: self = .otaEnd
        case 0x0B: self = .setBoot
        case 0x0C: self = .internalError
        case 0x0D: self = .triggerError
        case 0x0E: self = .triggerTimeout
        case 0x10: self = .otaTimeout
        case 0x11: self = .protocolError
        case 0x12: self = .versionProtocol
        case 0x13: self = .versionMissing
        case 0x14: self = .versionQueryError
        case 0x15: self = .versionQueryTimeout
        case 0x16: self = .versionMismatch
        case 0x17: self = .recoveryTimeout
        case 0x18: self = .metadata
        default: self = .reserved(rawValue: rawValue)
        }
    }

    var isTimeout: Bool {
        switch self {
        case .triggerTimeout, .otaTimeout, .versionQueryTimeout, .recoveryTimeout:
            return true
        default:
            return false
        }
    }
}

public struct WiFiGatewayDFUStatus: Equatable {
    public let otaID: UInt64
    public let stage: WiFiGatewayDFUStage
    public let percent: UInt8
    public let code: WiFiGatewayDFUCode
    public let firmwareID: String?
    public let moduleVersion: String?
}

public enum WiFiGatewayDFUStatusResult: Equatable {
    case success(WiFiGatewayDFUStatus)
    case invalidParameters
    case busy
    case reserved(rawValue: UInt8)
}

enum WiFiGatewayDFUStatusParser {
    static func parse(_ data: Data) -> WiFiGatewayDFUStatus? {
        guard data.count >= 16,
              data[0] == 0x43, data[1] == 0x11, data[2] == 0x00,
              let stage = WiFiGatewayDFUStage(rawValue: data[11]) else { return nil }

        let otaID = data[3..<11].enumerated().reduce(UInt64(0)) {
            $0 | (UInt64($1.element) << UInt64($1.offset * 8))
        }
        let percent = data[12]
        let code = WiFiGatewayDFUCode(rawValue: data[13])
        let firmwareLength = Int(data[14])
        guard firmwareLength <= 32 else { return nil }
        let firmwareStart = 15
        let firmwareEnd = firmwareStart + firmwareLength
        guard data.count >= firmwareEnd + 1 else { return nil }
        let versionLength = Int(data[firmwareEnd])
        guard versionLength <= 32 else { return nil }
        let versionStart = firmwareEnd + 1
        let expectedLength = versionStart + versionLength
        guard data.count == expectedLength else { return nil }

        let firmwareBytes = Array(data[firmwareStart..<firmwareEnd])
        let versionBytes = Array(data[versionStart..<expectedLength])
        guard validIdentifier(firmwareBytes), validIdentifier(versionBytes) else { return nil }
        let firmwareID = firmwareBytes.isEmpty ? nil : String(bytes: firmwareBytes, encoding: .ascii)
        let moduleVersion = versionBytes.isEmpty ? nil : String(bytes: versionBytes, encoding: .ascii)
        guard firmwareBytes.isEmpty || firmwareID != nil,
              versionBytes.isEmpty || moduleVersion != nil else { return nil }

        let value = WiFiGatewayDFUStatus(
            otaID: otaID, stage: stage, percent: percent, code: code,
            firmwareID: firmwareID, moduleVersion: moduleVersion
        )
        return validFields(value) ? value : nil
    }

    private static func validIdentifier(_ bytes: [UInt8]) -> Bool {
        bytes.allSatisfy { (0x20...0x7E).contains($0) && $0 != 0x22 }
    }

    private static func validFields(_ value: WiFiGatewayDFUStatus) -> Bool {
        let hasFirmware = value.firmwareID?.isEmpty == false
        let hasVersion = value.moduleVersion?.isEmpty == false
        switch value.stage {
        case .idle:
            return value.otaID == 0 && value.percent == 0 && value.code == .none && !hasFirmware && !hasVersion
        case .preparing:
            return active(value, percent: 0) && !hasVersion
        case .downloading:
            return value.percent <= 99 && active(value) && !hasVersion
        case .verifying, .verifyOK, .rebooting, .recovering, .versionCheck:
            return active(value, percent: 100) && !hasVersion
        case .success:
            guard active(value, percent: 100), hasVersion,
                  let firmware = value.firmwareID, let version = value.moduleVersion else { return false }
            return normalized(firmware) == normalized(version)
        case .verifyFail:
            return value.otaID != 0 && value.percent == 100 && value.code == .verify && hasFirmware && !hasVersion
        case .timeout:
            return value.otaID != 0 && value.percent <= 100 && value.code.isTimeout && hasFirmware && !hasVersion
        case .failed:
            guard value.otaID != 0, value.percent <= 100, value.code != .none,
                  !value.code.isTimeout, hasFirmware else { return false }
            if value.code == .versionMismatch {
                guard let firmware = value.firmwareID, let version = value.moduleVersion else { return false }
                return normalized(firmware) != normalized(version)
            }
            return !hasVersion
        case .cancelled:
            return value.otaID != 0 && value.percent <= 100 && value.code == .none && hasFirmware && !hasVersion
        }
    }

    private static func active(_ value: WiFiGatewayDFUStatus, percent: UInt8? = nil) -> Bool {
        value.otaID != 0 && value.code == .none && value.firmwareID?.isEmpty == false &&
            (percent == nil || value.percent == percent)
    }

    private static func normalized(_ value: String) -> String {
        (value.first == "v" || value.first == "V") ? String(value.dropFirst()) : value
    }
}
```

Move the old public stage/code/status/result declarations out of `SunricherVendorStatus.swift`; there must be exactly one definition of each type.

- [ ] **Step 4: Route V1.9 RET results through the parser**

Replace the old inline `wifiGatewayDFUStatusParameters` body with:

```swift
private static func wifiGatewayDFUStatusParameters(data: Data, status: UInt8) -> FunctionParameters? {
    switch status {
    case 0x00:
        guard let value = WiFiGatewayDFUStatusParser.parse(data) else { return nil }
        return .wifiGatewayDFUStatus(.success(value))
    case 0x01:
        guard data.count == 3 else { return nil }
        return .wifiGatewayDFUStatus(.invalidParameters)
    case 0x02:
        guard data.count == 3 else { return nil }
        return .wifiGatewayDFUStatus(.busy)
    default:
        guard data.count == 3 else { return nil }
        return .wifiGatewayDFUStatus(.reserved(rawValue: status))
    }
}
```

Update the `FunctionParameters.wifiGatewayDFUStatus` comment to say “查询 RET 结果”; EVENT will have a separate report-data route in Task 2.

- [ ] **Step 5: Replace the obsolete SDK XCTest payloads with V1.9 tables**

In `WiFiGatewayVendorMessageTests.swift`, add a test payload helper with the same byte construction as the standalone contract, then cover:

```swift
let validStages: [(UInt8, UInt8, UInt8, String?, WiFiGatewayDFUStage)] = [
    (0x0C, 0, 0, nil, .preparing),
    (0x01, 99, 0, nil, .downloading),
    (0x02, 100, 0, nil, .verifying),
    (0x03, 100, 0, nil, .verifyOK),
    (0x05, 100, 0, nil, .rebooting),
    (0x06, 100, 0, nil, .recovering),
    (0x07, 100, 0, nil, .versionCheck),
    (0x08, 100, 0, "0.4.0", .success),
    (0x04, 100, 0x04, nil, .verifyFail),
    (0x09, 42, 0x10, nil, .timeout),
    (0x0A, 42, 0x18, nil, .failed),
    (0x0B, 42, 0, nil, .cancelled)
]
```

Also assert `43 11 02 -> .busy`, unknown stage rejection, `0x0F -> .reserved(rawValue: 0x0F)` only under `FAILED`, illegal tail bytes, 33-byte identifiers, quote/CR/non-ASCII rejection, illegal percent, invalid `SUCCESS` version equality, and invalid module-version presence.

- [ ] **Step 6: Run the standalone parser contract**

```bash
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift scripts/check_wifi_gateway_dfu_status_v19.swift -o /tmp/WiFiGatewayDFUStatusV19Contract
/tmp/WiFiGatewayDFUStatusV19Contract
```

Expected: `WiFiGatewayDFUStatusV19Contract passed`.

Run the package test for evidence:

```bash
swift test --filter WiFiGatewayVendorMessageTests
```

Expected in the current repository: it may stop before test execution at the known macOS `no such module 'UIKit'` limitation. Record this exact infrastructure blocker; the standalone contract must pass.

- [ ] **Step 7: Commit SDK RET support**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift scripts/check_wifi_gateway_dfu_status_v19.swift
git commit -m "feat: update wifi gateway ota status protocol"
```

---

### Task 2: Parse V1.9 OTA EVENT without colliding with existing reports

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherReportMessage.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

**Interfaces:**
- Consumes: `WiFiGatewayDFUStatusParser.parse(_:)` from Task 1.
- Produces: `SunricherReportMessage.ReportData.wifiGatewayDFUStatus(WiFiGatewayDFUStatus)`.
- Preserves: `.on_offline(online:)` and Opcode `0xF5780A`.

- [ ] **Step 1: Add failing EVENT integration tests**

Add tests that construct the same valid full payload for both `SunricherVendorStatus` and `SunricherReportMessage`, assert equal status values, and verify the EVENT cannot match a GET handle:

```swift
let event = SunricherReportMessage(parameters: payload)
guard case .wifiGatewayDFUStatus(let eventStatus) = event?.reportData else {
    return XCTFail("Expected WiFi Gateway OTA EVENT")
}
XCTAssertEqual(eventStatus, retStatus)

let handle = MeshMessageHandle(
    message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
    address: 0x0003
)
XCTAssertFalse(handle.matchesResponse(event!, from: 0x0003))
```

Keep an explicit regression assertion for `SunricherReportMessage(parameters: Data([0x01, 0x01]))`.

- [ ] **Step 2: Run the focused package test and confirm the EVENT case is missing**

```bash
swift test --filter WiFiGatewayVendorMessageTests/testWiFiGatewayDFUStatusEventParsing
```

Expected: either the known UIKit infrastructure blocker or compile failure because `.wifiGatewayDFUStatus` does not yet exist. Do not treat the UIKit blocker as a feature pass.

- [ ] **Step 3: Extend the existing report type**

Update `SunricherReportMessage` without introducing a second Opcode type:

```swift
public enum ReportType: UInt8 {
    case on_offline = 0x01
    case wifiGatewayDFUStatus = 0x43
}

public enum ReportData {
    case on_offline(online: Bool)
    case wifiGatewayDFUStatus(WiFiGatewayDFUStatus)
}
```

Its initializer must switch on the first byte. For `0x43`, require the full `43 11 00...` parser result; for `0x01`, preserve the old two-byte online parsing:

```swift
switch reportType {
case .on_offline:
    guard parameters.count >= 2 else {
        reportData = nil
        break
    }
    reportData = .on_offline(online: parameters[1] != 0)
case .wifiGatewayDFUStatus:
    guard let status = WiFiGatewayDFUStatusParser.parse(parameters) else { return nil }
    reportData = .wifiGatewayDFUStatus(status)
}
```

- [ ] **Step 4: Compile the SDK through the iPhoneOS demo**

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit SDK EVENT support**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherReportMessage.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "feat: add wifi gateway ota status events"
```

---

### Task 3: Add additive Mesh connection observers to NordicSigMeshSDK

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`

**Interfaces:**
- Produces: `addGlobalConnectionObserver(_:) -> UUID`.
- Produces: `removeGlobalConnectionObserver(_:)`.
- Callback: `(MeshNetworkManager, Bool) -> Void`, where Bool is the effective Mesh-connected truth.

- [ ] **Step 1: Add a failing source contract**

Before implementation, run:

```bash
rg -n 'addGlobalConnectionObserver|removeGlobalConnectionObserver|currentGlobalConnectionObservers' Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift
```

Expected: no matches.

- [ ] **Step 2: Add thread-safe observer storage and public APIs**

Place these members next to `GlobalMessageObserver`:

```swift
public typealias GlobalConnectionObserver = (_ manager: MeshNetworkManager, _ isConnected: Bool) -> Void
private var globalConnectionObservers: [UUID: GlobalConnectionObserver] = [:]
private let globalConnectionObserversLock = NSLock()
```

Add APIs mirroring message observers:

```swift
@discardableResult
public func addGlobalConnectionObserver(_ observer: @escaping GlobalConnectionObserver) -> UUID {
    let id = UUID()
    globalConnectionObserversLock.lock()
    globalConnectionObservers[id] = observer
    globalConnectionObserversLock.unlock()
    return id
}

public func removeGlobalConnectionObserver(_ id: UUID?) {
    guard let id else { return }
    globalConnectionObserversLock.lock()
    globalConnectionObservers.removeValue(forKey: id)
    globalConnectionObserversLock.unlock()
}

private func currentGlobalConnectionObservers() -> [GlobalConnectionObserver] {
    globalConnectionObserversLock.lock()
    let observers = Array(globalConnectionObservers.values)
    globalConnectionObserversLock.unlock()
    return observers
}

private func notifyGlobalConnectionObservers(isConnected: Bool) {
    guard let manager = meshNetworkManager else { return }
    let observers = currentGlobalConnectionObservers()
    guard !observers.isEmpty else { return }
    delegateQueue.async {
        observers.forEach { $0(manager, isConnected) }
    }
}
```

- [ ] **Step 3: Notify only at effective connection transitions**

Add one private setter that compares the old and new truth before notifying:

```swift
private func setMeshNetworkConnected(_ isConnected: Bool) {
    let didChange = self.isMeshNetworkConnected != isConnected
    self.isMeshNetworkConnected = isConnected
    if didChange {
        notifyGlobalConnectionObservers(isConnected: isConnected)
    }
}
```

Use it at every existing effective-truth assignment: successful proxy-filter setup, the whitelist retry fallback first-open branch, the zero-proxy close branch, Bluetooth-off handling, and mesh-network replacement/reset. Preserve the existing main-queue dispatch where it already exists.

Do not notify from a raw bearer-open callback before whitelist setup, and do not emit another `true` merely because a proxy was replaced while the effective state was already connected.

- [ ] **Step 4: Run source contract and demo build**

```bash
rg -n 'addGlobalConnectionObserver|removeGlobalConnectionObserver|notifyGlobalConnectionObservers' Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift
```

Expected: all three API names appear.

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit connection observation**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift
git commit -m "feat: observe mesh connection changes"
```

---

### Task 4: Implement the pure App reducer and V1.9 session store

**Files:**
- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- Create: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `WiFiFirmwareDFUStatusReducer.reduce(_:source:) -> WiFiFirmwareDFUReduction`.
- Produces: `WiFiFirmwareDFUStatusSnapshot`, persisted in `WiFiFirmwareDFUSession`.
- Produces: `WiFiFirmwareDFUQueryTiming.statusTimeout = 3`, `quietQueryInterval = 10`, `unknownThreshold = 30`, `unknownQueryInterval = 30`.
- Consumes later: coordinator converts SDK status to the pure snapshot.

- [ ] **Step 1: Write failing reducer tests**

Create an `@main` table-driven test that covers identity bind/mismatch, skipped forward stages, backwards stages, download regression, duplicate state, first terminal lock, query-restored cancellation and rejected live `VERIFYING -> CANCELLED`:

```swift
import Foundation

@main
struct WiFiFirmwareDFUStatusReducerTests {
    static func snapshot(
        otaID: UInt64 = 7,
        stage: WiFiFirmwareDFUStatusStage,
        percent: Int,
        firmwareID: String? = "0.4.0",
        failure: WiFiFirmwareDFUFailureCategory = .none
    ) -> WiFiFirmwareDFUStatusSnapshot {
        .init(otaID: otaID, stage: stage, percent: percent,
              failureCategory: failure, codeIdentifier: "none",
              firmwareID: firmwareID, moduleVersion: nil)
    }

    static func main() {
        var reducer = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(reducer.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .accepted)
        precondition(reducer.boundOTAID == 7)
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 40), source: .event) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 40), source: .event) == .ignored(.duplicate))
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 35), source: .event) == .ignored(.downloadProgressRegressed))
        precondition(reducer.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .ignored(.stageRegressed))
        precondition(reducer.reduce(snapshot(otaID: 8, stage: .downloading, percent: 50), source: .event) == .ignored(.identityMismatch))
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 50, firmwareID: "0.5.0"), source: .event) == .ignored(.identityMismatch))
        precondition(reducer.reduce(snapshot(stage: .verifying, percent: 100), source: .event) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .cancelled, percent: 100), source: .event) == .ignored(.cancelledRequiresQuery))
        precondition(reducer.reduce(snapshot(stage: .cancelled, percent: 100), source: .query) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .success, percent: 100), source: .query) == .ignored(.terminalLocked))

        var skipped = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(skipped.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .accepted)
        precondition(skipped.reduce(snapshot(stage: .versionCheck, percent: 100), source: .event) == .accepted)

        precondition(WiFiFirmwareDFUQueryTiming.statusTimeout == 3)
        precondition(WiFiFirmwareDFUQueryTiming.quietQueryInterval == 10)
        precondition(WiFiFirmwareDFUQueryTiming.unknownThreshold == 30)
        precondition(WiFiFirmwareDFUQueryTiming.unknownQueryInterval == 30)
        print("WiFiFirmwareDFUStatusReducerTests passed")
    }
}
```

- [ ] **Step 2: Run the reducer test and verify it fails before the source exists**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: FAIL because `WiFiFirmwareDFUStatusReducer.swift` does not exist.

- [ ] **Step 3: Implement the pure reducer**

Create Foundation-only domain types. The reducer must expose these exact cases:

```swift
enum WiFiFirmwareDFUStatusStage: String, Codable, Equatable {
    case idle, preparing, downloading, verifying, verifyOK, verifyFail
    case rebooting, recovering, versionCheck, success, timeout, failed, cancelled

    var forwardRank: Int? {
        switch self {
        case .preparing: return 0
        case .downloading: return 1
        case .verifying: return 2
        case .verifyOK: return 3
        case .rebooting: return 4
        case .recovering: return 5
        case .versionCheck: return 6
        default: return nil
        }
    }

    var isTerminal: Bool {
        switch self {
        case .verifyFail, .success, .timeout, .failed, .cancelled: return true
        default: return false
        }
    }
}

enum WiFiFirmwareDFUFailureCategory: String, Codable, Equatable {
    case none, download, timeout, other
}

struct WiFiFirmwareDFUStatusSnapshot: Codable, Equatable {
    let otaID: UInt64
    let stage: WiFiFirmwareDFUStatusStage
    let percent: Int
    let failureCategory: WiFiFirmwareDFUFailureCategory
    let codeIdentifier: String
    let firmwareID: String?
    let moduleVersion: String?
}

enum WiFiFirmwareDFUStatusSource { case event, query }
enum WiFiFirmwareDFUIgnoreReason: Equatable {
    case invalidIdle, identityMismatch, stageRegressed
    case downloadProgressRegressed, duplicate, terminalLocked, cancelledRequiresQuery
}
enum WiFiFirmwareDFUReduction: Equatable {
    case accepted
    case ignored(WiFiFirmwareDFUIgnoreReason)
}

enum WiFiFirmwareDFUQueryTiming {
    static let statusTimeout: TimeInterval = 3
    static let quietQueryInterval: TimeInterval = 10
    static let unknownThreshold: TimeInterval = 30
    static let unknownQueryInterval: TimeInterval = 30
}
```

`reduce` must apply this exact order: reject IDLE, missing/mismatched firmware ID, or zero OTA ID; reject terminal-locked; bind the first nonzero OTA ID; enforce bound identity; reject live EVENT `VERIFYING -> CANCELLED`; accept any other first terminal; then enforce nonterminal rank and download progress. Only `.accepted` mutates `lastAcceptedStatus`.

Provide an initializer that can restore `boundOTAID` and `lastAcceptedStatus` from a V1.9 session after ordinary view recreation. Authoritative reconnect must deliberately use a fresh reducer and then require the returned identity to equal the stored `otaID/targetFirmwareID`, as specified in Task 5.

- [ ] **Step 4: Replace the old SDK-coupled mapper and session**

Remove `import NordicSigMeshSDK` from `WiFiFirmwareDFUState.swift`. Change `WiFiFirmwareDFUStateMapper.map` to accept `WiFiFirmwareDFUStatusSnapshot` and map:

```swift
case .preparing, .downloading: .downloading
case .verifying, .verifyOK, .rebooting, .recovering, .versionCheck: .updating
case .verifyFail: .downloadFailed
case .failed where failureCategory == .download: .downloadFailed
case .failed, .timeout: .upgradeFailed
case .success: .upgradeComplete
case .cancelled: .cancelled
case .idle: nil
```

Add `.cancelled` and `.communicationUnknown` to `WiFiFirmwareUpdatingKind`.

Replace the session with:

```swift
struct WiFiFirmwareDFUSession: Codable, Equatable {
    let targetFirmwareID: String
    var otaID: UInt64?
    var lastStatus: WiFiFirmwareDFUStatusSnapshot?
    var lastState: WiFiFirmwareUpdatingState?
    var terminalConsumed: Bool
    var requiresAuthoritativeQuery: Bool
}
```

Change the storage key to `wifi_firmware_dfu_session.v19.<networkUUID>.<nodeAddress>`. On load, delete the legacy `wifi_firmware_dfu_session.<networkUUID>.<nodeAddress>` key before reading V1.9 data; never attempt to infer an OTA ID from old cached state.

- [ ] **Step 5: Add the reducer source to all four targets**

Use the prevalidated IDs:

```text
C8F6A1302FA3000000000001  PBXFileReference
C8F6A1312FA3000000000001  SunSmart PBXBuildFile
C8F6A1322FA3000000000001  Archipelago PBXBuildFile
C8F6A1332FA3000000000001  SLG Sync Plus PBXBuildFile
C8F6A1342FA3000000000001  SylSmart PBXBuildFile
```

Insert the file reference in the Firmware `Model` group and one build file in each of the four existing source phases adjacent to `WiFiFirmwareDFUState.swift`.

- [ ] **Step 6: Run the reducer tests**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: `WiFiFirmwareDFUStatusReducerTests passed`.

```bash
plutil -lint SunSmart.xcodeproj/project.pbxproj
```

Expected: `SunSmart.xcodeproj/project.pbxproj: OK`.

- [ ] **Step 7: Commit the pure App state layer**

Do not stage `SunSmart.xcodeproj/xcshareddata/xcschemes/SunSmart.xcscheme`.

```bash
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add wifi ota status reducer"
```

---

### Task 5: Rebuild the coordinator around EVENT, authoritative GET, and V1.9 timing

**Files:**
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`

**Interfaces:**
- Consumes: SDK `SunricherReportMessage.ReportData.wifiGatewayDFUStatus` and RET result.
- Consumes: `addGlobalConnectionObserver` from Task 3.
- Consumes: App reducer/session from Task 4.
- Produces: existing coordinator `Event`, including `.updateState(.communicationUnknown)` and `.updateState(.cancelled)`.

- [ ] **Step 1: Extend focused tests for mapper and persisted-session behavior**

Add assertions that `.preparing` maps to `.downloading(0)`, `.cancelled(50)` maps to cancelled, download-category `FAILED` maps to download failed, other failure maps to upgrade failed, and V1.9 store removes the legacy key.

Run the test and confirm failure until the mapping/session changes are complete:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected before completing the mapper assertions: a precondition failure naming the mismatched state.

- [ ] **Step 2: Split request lanes and observer IDs**

Replace the single `requestInFlight` and `observerID` fields with:

```swift
private var messageObserverID: UUID?
private var connectionObserverID: UUID?
private var statusQueryInFlight = false
private var startRequestInFlight = false
private var currentVersionQueryInFlight = false
private var pendingStartFirmwareID: String?
private var pendingStartReducer: WiFiFirmwareDFUStatusReducer?
private var queryWorkItem: DispatchWorkItem?
private var lastValidStatusAt: TimeInterval?
private var communicationUnknown = false
private var reducer: WiFiFirmwareDFUStatusReducer?
```

EVENT handling must never check any request-in-flight flag.

- [ ] **Step 3: Convert SDK status to the pure snapshot**

Add one exhaustive conversion method. Map SDK stages one-to-one; categorize `.noNetwork`, `.http`, `.size`, `.verify`, and `.metadata` as `.download`; timeout stage as `.timeout`; all other failure codes, including `.reserved`, as `.other`. Preserve the SDK code name/raw value in `codeIdentifier`.

The conversion must return `nil` only for SDK `IDLE` when no target identity exists; the SDK parser has already rejected malformed field combinations.

- [ ] **Step 4: Accept EVENT during the start request and suppress redundant GET**

At `start`, set `pendingStartFirmwareID` and create `pendingStartReducer` before sending `0x43/0x10`. The message observer must:

```swift
guard source == nodeAddress,
      MeshNetworkManager.instance.meshNetwork?.uuid == networkUUID,
      let report = message as? SunricherReportMessage,
      case .wifiGatewayDFUStatus(let status) = report.reportData else { return }
```

If the start ACK is still pending and firmware ID matches, convert each EVENT and feed it to `pendingStartReducer` in arrival order, so regressions and terminal locking are enforced even before the ACK. After `.accepted`, promote that reducer into the V1.9 session, render its last accepted status, and skip immediate GET. If no matching EVENT was accepted, issue one immediate status GET. On any non-accepted start result, discard the pending reducer and its identity.

- [ ] **Step 5: Implement the 3-second GET result lane**

`queryDFUStatus(authoritative:)` must use:

```swift
timeout: WiFiFirmwareDFUQueryTiming.statusTimeout
```

Only `.wifiGatewayDFUStatus(.success(value))` is a valid result. `.busy`, `.invalidParameters`, reserved result, transport timeout, malformed response and identity mismatch all call the no-valid-status path without ending the session.

An authoritative GET clears `requiresAuthoritativeQuery` only after a complete legal identity match. For this one response, create a fresh reducer baseline with the stored target identity and require the returned `otaID/firmwareID` to match the persisted session; then replace the pre-disconnect reducer and cached phase with the query result. This allows the authoritative query—not the old phase cache—to decide whether the OTA is nonterminal or terminal. A matching duplicate normal GET is valid communication and may clear communication-unknown UI even though reducer returns `.duplicate`.

- [ ] **Step 6: Implement normal and unknown query scheduling**

Use one cancellable work item. After an accepted nonterminal EVENT or a matching legal GET, schedule the next query no earlier than 10 seconds. When a scheduled query begins, compare `Date().timeIntervalSince1970` with `lastValidStatusAt`:

- elapsed under 30 seconds: remain in progress;
- elapsed at least 30 seconds: emit `.communicationUnknown` with the last accepted percent before querying;
- after a failed normal query, schedule the next check for `min(10 seconds, time remaining to the 30-second threshold)`, so a 3-second GET timeout cannot postpone communication-unknown beyond the threshold;
- while unknown: schedule the next query 30 seconds after completion;
- a matching legal status clears unknown, re-emits the mapped last state, and returns to 10-second timing;
- a terminal cancels the work item permanently.

Before the 30-second threshold, failed 10-second GET attempts may repeat at 10-second spacing; they must never overlap.

- [ ] **Step 7: Implement disconnect and authoritative reconnect**

Register `addGlobalConnectionObserver` and verify the callback manager belongs to the coordinator's `networkUUID`. On `false` for an active nonterminal session:

```swift
session.requiresAuthoritativeQuery = true
communicationUnknown = true
cancelScheduledQuery()
emit(.updateState(.init(kind: .communicationUnknown,
                        percent: session.lastStatus?.percent ?? 0)))
saveSession()
```

On `true`, if authoritative recovery is required and no status GET is in flight, query immediately with `authoritative: true`. Ignore EVENT while the flag is true. A persisted active session restored after process relaunch also starts behind this authoritative-query gate and must not render its cached phase as a result. Remove both observers in `deactivate` and `deinit`.

- [ ] **Step 8: Preserve first terminal and cancellation rules**

Persist reducer state after every accepted status. For `.success`, stop queries and emit `confirmedVersion`. For `.verifyFail`, `.failed`, `.timeout`, and `.cancelled`, stop queries without clearing the session. A query-sourced `CANCELLED` maps to cancelled UI; a live `VERIFYING -> CANCELLED` stays rejected by the reducer.

Do not clear an accepted session on IDLE, foreign firmware ID, foreign OTA ID, busy or invalid response.

- [ ] **Step 9: Run focused tests and one App compile checkpoint**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: `WiFiFirmwareDFUStatusReducerTests passed`.

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit coordinator behavior**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift
git commit -m "feat: coordinate wifi ota status v1.9"
```

---

### Task 6: Add cancelled UI, localization, and V1.9 static contracts

**Files:**
- Modify: `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: `.cancelled` and `.communicationUnknown` UI kinds.
- Produces: `wifi_firmware_upgrade_cancelled` localization.
- Preserves: disabled `.cancelDisabled`; no cancel-again action.

- [ ] **Step 1: Make the shell contract fail on the old polling and missing cancelled UI**

Replace the obsolete guards for `requestInFlight`, `timeout: 5`, `after: 2`, and degraded `after: 10`. Add exact guards for:

```bash
reducer="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift"
sdk_source="/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK"

[ -f "$reducer" ] || fail "missing WiFi OTA V1.9 reducer"
rg -n 'statusTimeout: TimeInterval = 3' "$reducer" >/dev/null || fail "status GET timeout must be 3 seconds"
rg -n 'quietQueryInterval: TimeInterval = 10' "$reducer" >/dev/null || fail "quiet query interval must be 10 seconds"
rg -n 'unknownThreshold: TimeInterval = 30' "$reducer" >/dev/null || fail "unknown threshold must be 30 seconds"
rg -n 'unknownQueryInterval: TimeInterval = 30' "$reducer" >/dev/null || fail "unknown query interval must be 30 seconds"
rg -n 'addGlobalConnectionObserver' "$coordinator" >/dev/null || fail "coordinator missing connection observer"
rg -n 'case \.wifiGatewayDFUStatus' "$coordinator" >/dev/null || fail "coordinator missing OTA EVENT route"
rg -n 'requiresAuthoritativeQuery' "$coordinator" >/dev/null || fail "coordinator missing authoritative reconnect gate"
rg -n 'case \.cancelled' "$state" >/dev/null || fail "state missing cancelled terminal"
rg -n 'case \.communicationUnknown' "$state" >/dev/null || fail "state missing communication unknown"
```

Also reject future cancel implementation by names/copy, not raw `0x15` because `0x15` is a valid version-query error code:

```bash
if rg -n 'wifiGatewayDFUCancel|wifiDFUCancel|CANCEL AGAIN|cancel_again' SunSmart "$sdk_source" >/dev/null; then
  fail "0x43/0x15 cancel implementation is out of scope"
fi
```

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected before UI updates: FAIL on the missing cancelled localization/rendering checks.

- [ ] **Step 2: Render cancelled and communication-unknown states**

In `WiFiFirmwareUpdatingView.applyContent`, add:

```swift
case .cancelled:
    titleKey = "wifi_firmware_upgrade_cancelled"
    detailKey = nil
    imageName = "alert_failed"
case .communicationUnknown:
    titleKey = "wifi_firmware_connection_failed"
    detailKey = "wifi_firmware_communication_timeout"
    imageName = "alert_failed"
```

Reuse the existing progress bar, percent, `ImportantText_Color`, and `alert_failed`; do not add assets or use `SCRX/SCRY`.

- [ ] **Step 3: Map primary actions**

In `primaryActionPresentation(for:)`:

```swift
case .downloading, .updating, .communicationUnknown:
    return .init(titleKey: "cancel", isEnabled: false, action: .cancelDisabled)
case .cancelled:
    return .init(titleKey: "wifi_firmware_upgrade_again", isEnabled: true, action: .retry)
```

Keep existing start failure and OTA failure states on `UPGRADE AGAIN`, success on `DONE`, and `.cancelDisabled` as a no-op. Do not add a primary-action enum case for cancel-again.

- [ ] **Step 4: Add both localizations**

```text
SunSmart/en.lproj/Localizable.strings:
"wifi_firmware_upgrade_cancelled" = "Upgrade cancelled";

SunSmart/zh-Hans.lproj/Localizable.strings:
"wifi_firmware_upgrade_cancelled" = "升级已取消";
```

- [ ] **Step 5: Complete and run static contracts**

Add localization presence checks, reducer PBX membership count of four, standalone reducer compile/run, and SDK parser script invocation to `check_wifi_gateway_firmware_update.sh`.

```bash
bash -n scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: `PASS: WiFi Gateway firmware update static checks`.

- [ ] **Step 6: Validate localization and project syntax**

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
plutil -lint SunSmart.xcodeproj/project.pbxproj
```

Expected: all three paths report `OK`.

- [ ] **Step 7: Commit UI and contracts**

```bash
git add SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: show wifi ota cancelled status"
```

---

### Task 7: Run full verification and document evidence

**Files:**
- Create: `docs/260718_1900_wifi_gateway_ota_status_v19_implementation_summary.md`

**Interfaces:**
- Consumes: all SDK/App deliverables.
- Produces: source-backed build/test evidence and known limitations.

- [ ] **Step 1: Verify both repositories contain only intended changes**

Run `git status --short` in both repositories. The SDK should be clean after its three commits. The App may still show the pre-existing `SunSmart.xcscheme` change; verify no task commit contains it.

- [ ] **Step 2: Run focused logic and static contracts**

From the SDK:

```bash
swiftc -parse-as-library Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift scripts/check_wifi_gateway_dfu_status_v19.swift -o /tmp/WiFiGatewayDFUStatusV19Contract
/tmp/WiFiGatewayDFUStatusV19Contract
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: standalone PASS; record whether `swift test` reaches tests or stops at the known UIKit blocker.

From the App:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: reducer PASS, contract PASS, diff check no output.

- [ ] **Step 3: Build the SDK demo for generic iPhoneOS**

From `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Build all four App targets for generic iPhoneOS**

Run separately from the App worktree:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected for each: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Write the implementation summary**

The summary must record:

- SDK and App commit hashes.
- Exact RET/EVENT/status identity behavior delivered.
- `Upgrade cancelled` UI and explicit absence of `0x43/0x15`.
- Focused test outputs.
- `swift test` result and UIKit blocker if still present.
- SDK Demo and four App build results.
- Any real-device cases not exercised; do not claim runtime evidence from static tests.
- Confirmation that the unrelated `SunSmart.xcscheme` change was preserved and excluded.

- [ ] **Step 6: Commit the summary only**

```bash
git add docs/260718_1900_wifi_gateway_ota_status_v19_implementation_summary.md
git commit -m "docs: summarize wifi ota status v1.9"
```

- [ ] **Step 7: Final audit**

Run:

```bash
git log --oneline -6
git status --short
```

Expected: task commits are visible; no unexpected task files remain. The unrelated scheme modification may remain unstaged and must be reported separately.
