# WiFi Gateway Vendor Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本地 `NordicSigMeshSDK` 中实现 WiFi Gateway `43 0D / 43 0E / 43 0F / 43 12` vendor 协议的请求编码、typed response 解析和回包匹配测试。

**Architecture:** 复用现有 `SunricherVendorSet / SunricherVendorGet / SunricherVendorStatus`，只扩展 Gateway 主码 `0x43` 的子码、请求枚举、结果类型和解析分支。App 不新增调用、不改 UI，后续 App 层通过 `status.parameters` 的 typed enum 区分业务结果。

**Tech Stack:** Swift 5.8、Swift Package Manager、XCTest、Sunricher vendor mesh message abstraction。

---

## 文件结构

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
  - 覆盖请求编码、输入校验、response typed parsing、RSSI signed int8、凭据读取和回包匹配。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 增加 WiFi Gateway 凭据 value type、validation error、结果 enum、Gateway 子码、ResponseCode、FunctionParameters 和 response parser。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  - 增加 `wifiGatewayCredentialsSet` 请求 case 和 `43 0D` payload 编码。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - 增加 `43 0E / 43 0F / 43 12` get 请求 case。

不修改 App 源码，不新增本地化文案，不新增明文 Wi-Fi 密码日志。

## Task 1: 写 WiFi Gateway vendor 协议失败测试

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

- [ ] **Step 1: 创建测试文件**

```swift
import XCTest
@testable import NordicSigMeshSDK

final class WiFiGatewayVendorMessageTests: XCTestCase {

    func testCredentialsSetEncoding() throws {
        let secured = try WiFiGatewayCredentials(ssid: "OfficeWiFi", password: "password1")
        XCTAssertEqual(
            SunricherVendorSet(function: .wifiGatewayCredentialsSet(secured)).parameters,
            Data([0x43, 0x0D, 0x0A]) + Data("OfficeWiFi".utf8) + Data([0x09]) + Data("password1".utf8)
        )

        let open = try WiFiGatewayCredentials(ssid: "OpenNet", password: nil)
        XCTAssertEqual(
            SunricherVendorSet(function: .wifiGatewayCredentialsSet(open)).parameters,
            Data([0x43, 0x0D, 0x07]) + Data("OpenNet".utf8) + Data([0x00])
        )

        let blankPassword = try WiFiGatewayCredentials(ssid: "OpenNet", password: "")
        XCTAssertNil(blankPassword.password)
        XCTAssertEqual(
            SunricherVendorSet(function: .wifiGatewayCredentialsSet(blankPassword)).parameters,
            Data([0x43, 0x0D, 0x07]) + Data("OpenNet".utf8) + Data([0x00])
        )
    }

    func testCredentialValidationRejectsInvalidInput() {
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "", password: nil)) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidSSIDLength(0))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: String(repeating: "A", count: 32), password: nil)) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidSSIDLength(32))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "OfficeWiFi", password: "1234567")) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidPasswordLength(7))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "OfficeWiFi", password: String(repeating: "A", count: 64))) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidPasswordLength(64))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "Bad\"Name", password: nil)) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidCharacter(field: .ssid, byte: 0x22))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "Bad\\Name", password: nil)) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidCharacter(field: .ssid, byte: 0x5C))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "Bad\nName", password: nil)) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidCharacter(field: .ssid, byte: 0x0A))
        }
        XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "OfficeWiFi", password: "bad\\pass1")) { error in
            XCTAssertEqual(error as? WiFiGatewayCredentialValidationError, .invalidCharacter(field: .password, byte: 0x5C))
        }
    }

    func testWifiGatewayGetEncoding() {
        XCTAssertEqual(
            SunricherVendorGet(function: .wifiGatewayConnectionStatus).parameters,
            Data([0x43, 0x0E])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .wifiGatewayRSSIStatus).parameters,
            Data([0x43, 0x0F])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .wifiGatewayCredentials).parameters,
            Data([0x43, 0x12])
        )
    }

    func testCredentialsSetResponseParsing() {
        assertCredentialsSet(Data([0x43, 0x0D, 0x00]), expected: .accepted, isSuccessful: true, errorCode: nil)
        assertCredentialsSet(Data([0x43, 0x0D, 0x01]), expected: .invalidParameters, isSuccessful: false, errorCode: 0x01)
        assertCredentialsSet(Data([0x43, 0x0D, 0x02]), expected: .internalError, isSuccessful: false, errorCode: 0x02)
        assertCredentialsSet(Data([0x43, 0x0D, 0x7F]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

        let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x0D, 0x00, 0x00]))
        XCTAssertEqual(trailing?.status.isSuccessful, false)
        XCTAssertNil(trailing?.status.parameters)
    }

    func testConnectionStatusResponseParsing() {
        assertConnectionStatus(Data([0x43, 0x0E, 0x00]), expected: .notStartedOrConnecting, isSuccessful: true, errorCode: nil)
        assertConnectionStatus(Data([0x43, 0x0E, 0x01]), expected: .connected, isSuccessful: false, errorCode: 0x01)
        assertConnectionStatus(Data([0x43, 0x0E, 0x02]), expected: .passwordError, isSuccessful: false, errorCode: 0x02)
        assertConnectionStatus(Data([0x43, 0x0E, 0x03]), expected: .failed, isSuccessful: false, errorCode: 0x03)
        assertConnectionStatus(Data([0x43, 0x0E, 0x7F]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

        let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x0E, 0x01, 0x00]))
        XCTAssertEqual(trailing?.status.isSuccessful, false)
        XCTAssertNil(trailing?.status.parameters)
    }

    func testRSSIStatusResponseParsing() {
        assertRSSIStatus(Data([0x43, 0x0F, 0x00, 0xBF]), expected: .valid(dbm: -65), isSuccessful: true, errorCode: nil)
        assertRSSIStatus(Data([0x43, 0x0F, 0x00, 0x81]), expected: .valid(dbm: -127), isSuccessful: true, errorCode: nil)
        assertRSSIStatus(Data([0x43, 0x0F, 0x00, 0x00]), expected: .valid(dbm: 0), isSuccessful: true, errorCode: nil)
        assertRSSIStatus(Data([0x43, 0x0F, 0x01, 0x00]), expected: .unavailable, isSuccessful: false, errorCode: 0x01)
        assertRSSIStatus(Data([0x43, 0x0F, 0x02, 0x00]), expected: .readFailed, isSuccessful: false, errorCode: 0x02)
        assertRSSIStatus(Data([0x43, 0x0F, 0x7F, 0x00]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

        let tooLow = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x00, 0x80]))
        XCTAssertEqual(tooLow?.status.isSuccessful, false)
        XCTAssertNil(tooLow?.status.parameters)

        let positive = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x00, 0x01]))
        XCTAssertEqual(positive?.status.isSuccessful, false)
        XCTAssertNil(positive?.status.parameters)

        let short = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x01]))
        XCTAssertEqual(short?.status.isSuccessful, false)
        XCTAssertNil(short?.status.parameters)

        let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x01, 0x00, 0x00]))
        XCTAssertEqual(trailing?.status.isSuccessful, false)
        XCTAssertNil(trailing?.status.parameters)
    }

    func testCredentialsReadResponseParsing() {
        let securedPayload = Data([0x43, 0x12, 0x00, 0x0A]) + Data("OfficeWiFi".utf8) + Data([0x09]) + Data("password1".utf8)
        let secured = SunricherVendorStatus(parameters: securedPayload)
        XCTAssertEqual(secured?.status.isSuccessful, true)
        XCTAssertEqual(secured?.status.code, .wifiGatewayCredentialsGet)
        if case .wifiGatewayCredentialsRead(.success(let credentials)) = secured?.status.parameters {
            XCTAssertEqual(credentials.ssid, "OfficeWiFi")
            XCTAssertEqual(credentials.password, "password1")
        } else {
            XCTFail("Expected WiFi Gateway credentials")
        }

        let openPayload = Data([0x43, 0x12, 0x00, 0x07]) + Data("OpenNet".utf8) + Data([0x00])
        let open = SunricherVendorStatus(parameters: openPayload)
        if case .wifiGatewayCredentialsRead(.success(let credentials)) = open?.status.parameters {
            XCTAssertEqual(credentials.ssid, "OpenNet")
            XCTAssertNil(credentials.password)
        } else {
            XCTFail("Expected open WiFi Gateway credentials")
        }

        assertCredentialsRead(Data([0x43, 0x12, 0x01]), expected: .notConfigured, isSuccessful: false, errorCode: 0x01)
        assertCredentialsRead(Data([0x43, 0x12, 0x02]), expected: .internalError, isSuccessful: false, errorCode: 0x02)
        assertCredentialsRead(Data([0x43, 0x12, 0x7F]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

        let trailingNotConfigured = SunricherVendorStatus(parameters: Data([0x43, 0x12, 0x01, 0x00]))
        XCTAssertEqual(trailingNotConfigured?.status.isSuccessful, false)
        XCTAssertNil(trailingNotConfigured?.status.parameters)

        let shortSuccess = SunricherVendorStatus(parameters: Data([0x43, 0x12, 0x00, 0x07]))
        XCTAssertEqual(shortSuccess?.status.isSuccessful, false)
        XCTAssertNil(shortSuccess?.status.parameters)

        let lengthMismatch = SunricherVendorStatus(parameters: Data([0x43, 0x12, 0x00, 0x07]) + Data("OpenNet".utf8) + Data([0x08]))
        XCTAssertEqual(lengthMismatch?.status.isSuccessful, false)
        XCTAssertNil(lengthMismatch?.status.parameters)

        let invalidPasswordLength = SunricherVendorStatus(parameters: Data([0x43, 0x12, 0x00, 0x07]) + Data("OpenNet".utf8) + Data([0x07]) + Data("1234567".utf8))
        XCTAssertEqual(invalidPasswordLength?.status.isSuccessful, false)
        XCTAssertNil(invalidPasswordLength?.status.parameters)
    }

    func testWiFiGatewayVendorStatusMustMatchCurrentCommandCode() throws {
        let connectionHandle = MeshMessageHandle(
            message: SunricherVendorGet(function: .wifiGatewayConnectionStatus),
            address: 0x0003
        )
        let connectionStatus = SunricherVendorStatus(parameters: Data([0x43, 0x0E, 0x01]))!
        let rssiStatus = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x01, 0x00]))!
        let credentialsStatus = SunricherVendorStatus(parameters: Data([0x43, 0x12, 0x01]))!

        XCTAssertTrue(connectionHandle.matchesResponse(connectionStatus, from: 0x0003))
        XCTAssertFalse(connectionHandle.matchesResponse(rssiStatus, from: 0x0003))
        XCTAssertFalse(connectionHandle.matchesResponse(credentialsStatus, from: 0x0003))

        let setCredentials = try WiFiGatewayCredentials(ssid: "OfficeWiFi", password: "password1")
        let setHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(setCredentials)),
            address: 0x0003
        )
        let setStatus = SunricherVendorStatus(parameters: Data([0x43, 0x0D, 0x00]))!
        let oldGatewayStatus = SunricherVendorStatus(parameters: Data([0x43, 0x05, 0x00]))!

        XCTAssertTrue(setHandle.matchesResponse(setStatus, from: 0x0003))
        XCTAssertFalse(setHandle.matchesResponse(oldGatewayStatus, from: 0x0003))
    }

    private func assertCredentialsSet(
        _ data: Data,
        expected: WiFiGatewayCredentialsSetResult,
        isSuccessful: Bool,
        errorCode: UInt8?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let status = SunricherVendorStatus(parameters: data)
        XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
        XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
        XCTAssertEqual(status?.status.code, .wifiGatewayCredentialsSet, file: file, line: line)
        if case .wifiGatewayCredentialsSet(let result) = status?.status.parameters {
            XCTAssertEqual(result, expected, file: file, line: line)
        } else {
            XCTFail("Expected WiFi Gateway credentials set result", file: file, line: line)
        }
    }

    private func assertConnectionStatus(
        _ data: Data,
        expected: WiFiGatewayConnectionStatus,
        isSuccessful: Bool,
        errorCode: UInt8?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let status = SunricherVendorStatus(parameters: data)
        XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
        XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
        XCTAssertEqual(status?.status.code, .wifiGatewayConnectionStatusGet, file: file, line: line)
        if case .wifiGatewayConnectionStatus(let result) = status?.status.parameters {
            XCTAssertEqual(result, expected, file: file, line: line)
        } else {
            XCTFail("Expected WiFi Gateway connection status", file: file, line: line)
        }
    }

    private func assertRSSIStatus(
        _ data: Data,
        expected: WiFiGatewayRSSIStatus,
        isSuccessful: Bool,
        errorCode: UInt8?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let status = SunricherVendorStatus(parameters: data)
        XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
        XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
        XCTAssertEqual(status?.status.code, .wifiGatewayRSSIStatusGet, file: file, line: line)
        if case .wifiGatewayRSSIStatus(let result) = status?.status.parameters {
            XCTAssertEqual(result, expected, file: file, line: line)
        } else {
            XCTFail("Expected WiFi Gateway RSSI status", file: file, line: line)
        }
    }

    private func assertCredentialsRead(
        _ data: Data,
        expected: WiFiGatewayCredentialsReadResult,
        isSuccessful: Bool,
        errorCode: UInt8?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let status = SunricherVendorStatus(parameters: data)
        XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
        XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
        XCTAssertEqual(status?.status.code, .wifiGatewayCredentialsGet, file: file, line: line)
        if case .wifiGatewayCredentialsRead(let result) = status?.status.parameters {
            XCTAssertEqual(result, expected, file: file, line: line)
        } else {
            XCTFail("Expected WiFi Gateway credentials read result", file: file, line: line)
        }
    }
}
```

- [ ] **Step 2: 运行新增测试并确认失败**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: FAIL，错误包含 `cannot find 'WiFiGatewayCredentials' in scope`、`type 'VendorFunctionGet' has no member 'wifiGatewayConnectionStatus'` 或等价未定义符号。

## Task 2: 增加 WiFi Gateway value types 和结果类型

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: 在 `VendorGatewayCode` 后增加 WiFi Gateway 类型**

在 `VendorGatewayCode` 结束后、`VendorProximityLightingCode` 前插入：

```swift
public enum WiFiGatewayCredentialField: Equatable {
    case ssid
    case password
}

public enum WiFiGatewayCredentialValidationError: Error, Equatable {
    case invalidSSIDLength(Int)
    case invalidPasswordLength(Int)
    case invalidCharacter(field: WiFiGatewayCredentialField, byte: UInt8)
}

public struct WiFiGatewayCredentials: Equatable {
    public let ssid: String
    public let password: String?
    let ssidBytes: [UInt8]
    let passwordBytes: [UInt8]

    public init(ssid: String, password: String? = nil) throws {
        let ssidBytes = Array(ssid.utf8)
        let passwordText = password ?? ""
        let passwordBytes = Array(passwordText.utf8)
        try Self.validate(ssidBytes: ssidBytes, passwordBytes: passwordBytes)

        self.ssid = ssid
        self.password = passwordText.isEmpty ? nil : passwordText
        self.ssidBytes = ssidBytes
        self.passwordBytes = passwordBytes
    }

    init?(ssidBytes: [UInt8], passwordBytes: [UInt8]) {
        do {
            try Self.validate(ssidBytes: ssidBytes, passwordBytes: passwordBytes)
        } catch {
            return nil
        }
        guard let ssid = String(bytes: ssidBytes, encoding: .utf8) else {
            return nil
        }
        let password: String?
        if passwordBytes.isEmpty {
            password = nil
        } else {
            guard let decodedPassword = String(bytes: passwordBytes, encoding: .utf8) else {
                return nil
            }
            password = decodedPassword
        }

        self.ssid = ssid
        self.password = password
        self.ssidBytes = ssidBytes
        self.passwordBytes = passwordBytes
    }

    private static func validate(ssidBytes: [UInt8], passwordBytes: [UInt8]) throws {
        guard (1...31).contains(ssidBytes.count) else {
            throw WiFiGatewayCredentialValidationError.invalidSSIDLength(ssidBytes.count)
        }
        guard passwordBytes.isEmpty || (8...63).contains(passwordBytes.count) else {
            throw WiFiGatewayCredentialValidationError.invalidPasswordLength(passwordBytes.count)
        }
        try validatePrintableASCII(ssidBytes, field: .ssid)
        try validatePrintableASCII(passwordBytes, field: .password)
    }

    private static func validatePrintableASCII(_ bytes: [UInt8], field: WiFiGatewayCredentialField) throws {
        for byte in bytes {
            guard (0x20...0x7E).contains(byte), byte != 0x22, byte != 0x5C else {
                throw WiFiGatewayCredentialValidationError.invalidCharacter(field: field, byte: byte)
            }
        }
    }
}

public enum WiFiGatewayCredentialsSetResult: Equatable {
    case accepted
    case invalidParameters
    case internalError
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00:
            self = .accepted
        case 0x01:
            self = .invalidParameters
        case 0x02:
            self = .internalError
        default:
            self = .reserved(rawValue: rawValue)
        }
    }
}

public enum WiFiGatewayConnectionStatus: Equatable {
    case notStartedOrConnecting
    case connected
    case passwordError
    case failed
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00:
            self = .notStartedOrConnecting
        case 0x01:
            self = .connected
        case 0x02:
            self = .passwordError
        case 0x03:
            self = .failed
        default:
            self = .reserved(rawValue: rawValue)
        }
    }
}

public enum WiFiGatewayRSSIStatus: Equatable {
    case valid(dbm: Int8)
    case unavailable
    case readFailed
    case reserved(rawValue: UInt8)
}

public enum WiFiGatewayCredentialsReadResult: Equatable {
    case success(WiFiGatewayCredentials)
    case notConfigured
    case internalError
    case reserved(rawValue: UInt8)
}
```

- [ ] **Step 2: 运行测试并确认仍失败在协议枚举缺失**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: FAIL，错误收敛到 `VendorFunctionSet`、`VendorFunctionGet`、`ResponseCode` 或 `FunctionParameters` 的 WiFi case 未定义。

## Task 3: 增加 Gateway 子码、ResponseCode 和 FunctionParameters

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: 扩展 `VendorGatewayCode`**

把 `VendorGatewayCode` 的尾部替换为：

```swift
    /// 添加子网appkey
    case subnetAppkeyAdd = 0x0B
    /// 删除子网appkey
    case subnetAppkeyDelete = 0x0C
    /// 设置 Wi-Fi SSID/password
    case wifiCredentialsSet = 0x0D
    /// 获取 Wi-Fi 连接状态
    case wifiConnectionStatusGet = 0x0E
    /// 获取 Wi-Fi RSSI
    case wifiRSSIStatusGet = 0x0F
    /// 获取 Wi-Fi SSID/password
    case wifiCredentialsGet = 0x12
```

- [ ] **Step 2: 扩展 `ResponseCode.init(opcode:subcode:)` 的 `.gateway` 分支**

在 `.gateway` switch 中的 `VendorGatewayCode.simCpsiGet` 分支后、`default` 前加入：

```swift
            case VendorGatewayCode.wifiCredentialsSet.rawValue:
                self = .wifiGatewayCredentialsSet
            case VendorGatewayCode.wifiConnectionStatusGet.rawValue:
                self = .wifiGatewayConnectionStatusGet
            case VendorGatewayCode.wifiRSSIStatusGet.rawValue:
                self = .wifiGatewayRSSIStatusGet
            case VendorGatewayCode.wifiCredentialsGet.rawValue:
                self = .wifiGatewayCredentialsGet
```

- [ ] **Step 3: 扩展 `ResponseCode` enum cases**

在 `case gatewaySimCpsiGet` 后加入：

```swift
    /// 设置 Wi-Fi SSID/password
    case wifiGatewayCredentialsSet
    /// 获取 Wi-Fi 连接状态
    case wifiGatewayConnectionStatusGet
    /// 获取 Wi-Fi RSSI
    case wifiGatewayRSSIStatusGet
    /// 获取 Wi-Fi SSID/password
    case wifiGatewayCredentialsGet
```

- [ ] **Step 4: 扩展 `ResponseCode.code`**

在 `case .gatewaySimCpsiGet` 后加入：

```swift
        case .wifiGatewayCredentialsSet:
            return [VendorOpCode.gateway.rawValue, VendorGatewayCode.wifiCredentialsSet.rawValue]
        case .wifiGatewayConnectionStatusGet:
            return [VendorOpCode.gateway.rawValue, VendorGatewayCode.wifiConnectionStatusGet.rawValue]
        case .wifiGatewayRSSIStatusGet:
            return [VendorOpCode.gateway.rawValue, VendorGatewayCode.wifiRSSIStatusGet.rawValue]
        case .wifiGatewayCredentialsGet:
            return [VendorOpCode.gateway.rawValue, VendorGatewayCode.wifiCredentialsGet.rawValue]
```

- [ ] **Step 5: 扩展 `FunctionParameters`**

在 `case gatewaySimCpsiState(system: UInt8, operation: UInt8, cid: UInt8, state: UInt8)` 后加入：

```swift
    /// Wi-Fi 凭据设置结果
    case wifiGatewayCredentialsSet(WiFiGatewayCredentialsSetResult)
    /// Wi-Fi 连接状态
    case wifiGatewayConnectionStatus(WiFiGatewayConnectionStatus)
    /// Wi-Fi RSSI 状态
    case wifiGatewayRSSIStatus(WiFiGatewayRSSIStatus)
    /// Wi-Fi 凭据读取结果
    case wifiGatewayCredentialsRead(WiFiGatewayCredentialsReadResult)
```

- [ ] **Step 6: 运行测试并确认失败收敛到请求构造或解析缺失**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: FAIL，错误集中在 `VendorFunctionSet` / `VendorFunctionGet` case 未定义，或 response `parameters` 仍未解析出 WiFi typed enum。

## Task 4: 实现 Set/Get 请求编码

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`

- [ ] **Step 1: 在 `VendorFunctionSet.data` 增加 `43 0D` 编码**

在 `.gatewaySubnetAppkeyDelete` 分支后加入：

```swift
        case .wifiGatewayCredentialsSet(let credentials):
            return data + UInt8(credentials.ssidBytes.count) + Data(credentials.ssidBytes) + UInt8(credentials.passwordBytes.count) + Data(credentials.passwordBytes)
```

- [ ] **Step 2: 在 `VendorFunctionSet.command` 增加 response command**

在 `.gatewaySubnetAppkeyDelete` 分支后加入：

```swift
        case .wifiGatewayCredentialsSet: return .wifiGatewayCredentialsSet
```

- [ ] **Step 3: 在 `VendorFunctionSet` cases 中加入 set case**

在 `case gatewaySubnetAppkeyDelete(subnetAppkeyIndex: UInt16)` 后加入：

```swift
    /// 设置 Wi-Fi Gateway SSID/password
    case wifiGatewayCredentialsSet(WiFiGatewayCredentials)
```

- [ ] **Step 4: 在 `VendorFunctionGet.command` 增加 get mapping**

在 `.gatewaySimCpsi` 分支后加入：

```swift
        case .wifiGatewayConnectionStatus: return .wifiGatewayConnectionStatusGet
        case .wifiGatewayRSSIStatus: return .wifiGatewayRSSIStatusGet
        case .wifiGatewayCredentials: return .wifiGatewayCredentialsGet
```

- [ ] **Step 5: 在 `VendorFunctionGet` cases 中加入 get case**

在 `case gatewaySimCpsi` 后加入：

```swift
    /// 获取 Wi-Fi Gateway 连接状态
    case wifiGatewayConnectionStatus
    /// 获取 Wi-Fi Gateway RSSI
    case wifiGatewayRSSIStatus
    /// 获取 Wi-Fi Gateway SSID/password
    case wifiGatewayCredentials
```

- [ ] **Step 6: 运行编码测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests/testCredentialsSetEncoding
swift test --filter WiFiGatewayVendorMessageTests/testCredentialValidationRejectsInvalidInput
swift test --filter WiFiGatewayVendorMessageTests/testWifiGatewayGetEncoding
```

Expected: PASS for three encoding and validation tests.

## Task 5: 实现 WiFi Gateway response typed parsing

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: 在 `Status` 中增加 WiFi parser helper**

在 `init(isSuccessful:code:parameters:)` 后、`init?(data:)` 前加入：

```swift
        private static func wifiGatewayParameters(responseCode: ResponseCode, data: Data, status: UInt8) -> FunctionParameters? {
            switch responseCode {
            case .wifiGatewayCredentialsSet:
                guard data.count == 3 else { return nil }
                return .wifiGatewayCredentialsSet(.init(rawValue: status))
            case .wifiGatewayConnectionStatusGet:
                guard data.count == 3 else { return nil }
                return .wifiGatewayConnectionStatus(.init(rawValue: status))
            case .wifiGatewayRSSIStatusGet:
                guard data.count == 4 else { return nil }
                switch status {
                case 0x00:
                    let rssi = Int8(bitPattern: data[3])
                    guard (-127...0).contains(rssi) else { return nil }
                    return .wifiGatewayRSSIStatus(.valid(dbm: rssi))
                case 0x01:
                    return .wifiGatewayRSSIStatus(.unavailable)
                case 0x02:
                    return .wifiGatewayRSSIStatus(.readFailed)
                default:
                    return .wifiGatewayRSSIStatus(.reserved(rawValue: status))
                }
            case .wifiGatewayCredentialsGet:
                return wifiGatewayCredentialsReadParameters(data: data, status: status)
            default:
                return nil
            }
        }

        private static func wifiGatewayCredentialsReadParameters(data: Data, status: UInt8) -> FunctionParameters? {
            switch status {
            case 0x00:
                guard data.count >= 5 else { return nil }
                let ssidLength = Int(data[3])
                guard (1...31).contains(ssidLength) else { return nil }

                let ssidStart = 4
                let ssidEnd = ssidStart + ssidLength
                guard data.count >= ssidEnd + 1 else { return nil }

                let passwordLength = Int(data[ssidEnd])
                guard passwordLength == 0 || (8...63).contains(passwordLength) else { return nil }

                let passwordStart = ssidEnd + 1
                let expectedLength = passwordStart + passwordLength
                guard data.count == expectedLength else { return nil }

                let ssidBytes = Array(data[ssidStart..<ssidEnd])
                let passwordBytes = Array(data[passwordStart..<expectedLength])
                guard let credentials = WiFiGatewayCredentials(ssidBytes: ssidBytes, passwordBytes: passwordBytes) else {
                    return nil
                }
                return .wifiGatewayCredentialsRead(.success(credentials))
            case 0x01:
                guard data.count == 3 else { return nil }
                return .wifiGatewayCredentialsRead(.notConfigured)
            case 0x02:
                guard data.count == 3 else { return nil }
                return .wifiGatewayCredentialsRead(.internalError)
            default:
                guard data.count == 3 else { return nil }
                return .wifiGatewayCredentialsRead(.reserved(rawValue: status))
            }
        }
```

- [ ] **Step 2: 在 `Status.init(data:)` 中优先处理 WiFi typed response**

在现有代码：

```swift
            if responseCode == .emergencyWorkingMode && data.count == 3 {
                self.parameters = .emergencyWorkingModeAck(.init(responseCode: status))
                return
            }
```

后面紧接加入：

```swift
            if responseCode.isWiFiGatewayResponse {
                self.parameters = Self.wifiGatewayParameters(responseCode: responseCode, data: data, status: status)
                if self.parameters == nil {
                    self.isSuccessful = false
                }
                return
            }
```

- [ ] **Step 3: 增加 `ResponseCode` 私有 helper**

在 `public extension ResponseCode` 结束后加入：

```swift
private extension ResponseCode {
    var isWiFiGatewayResponse: Bool {
        switch self {
        case .wifiGatewayCredentialsSet,
                .wifiGatewayConnectionStatusGet,
                .wifiGatewayRSSIStatusGet,
                .wifiGatewayCredentialsGet:
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: 运行解析测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests/testCredentialsSetResponseParsing
swift test --filter WiFiGatewayVendorMessageTests/testConnectionStatusResponseParsing
swift test --filter WiFiGatewayVendorMessageTests/testRSSIStatusResponseParsing
swift test --filter WiFiGatewayVendorMessageTests/testCredentialsReadResponseParsing
```

Expected: PASS for four parsing tests.

## Task 6: 验证回包匹配和旧 Gateway 子码不受影响

**Files:**
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Existing behavior covered by: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`

- [ ] **Step 1: 运行 WiFi 回包匹配测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests/testWiFiGatewayVendorStatusMustMatchCurrentCommandCode
```

Expected: PASS。`43 0E` 不匹配 `43 0F / 43 12`，`43 0D` 不匹配旧 `43 05`。

- [ ] **Step 2: 运行既有 vendor matching 测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter MeshMessageHandleResponseMatchingTests
```

Expected: PASS。现有 battery power switch、up/down light、publication matching 不回退。

## Task 7: 运行 SDK 和 App 验证

**Files:**
- No source changes in this task.

- [ ] **Step 1: 运行新增测试类**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: PASS。

- [ ] **Step 2: 运行相关既有测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter MeshMessageHandleResponseMatchingTests
swift test --filter UpDownLightVendorMessageTests
swift test --filter ELControllerVendorMessageTests
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: PASS。

- [ ] **Step 3: 运行 SDK 全量测试**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test
```

Expected: PASS。若既有 UIKit 或环境问题导致全量失败，保留失败摘要，并以 Step 1 和 Step 2 的过滤测试作为本次 SDK 协议变更的直接证据。

- [ ] **Step 4: 运行 App iPhoneOS 构建**

Run from `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway`:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 5: 检查 whitespace**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway
git diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected: both commands produce no output.

## Task 8: 提交实现

**Files:**
- Modified SDK files and new SDK test file.
- Plan file remains in App worktree docs.

- [ ] **Step 1: 查看 App worktree 状态**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway
git status --short
```

Expected: only the plan file is modified or clean if already committed.

- [ ] **Step 2: 查看 SDK worktree 状态**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: only these SDK files changed:

```text
M Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift
M Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift
M Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift
?? Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
```

- [ ] **Step 3: 提交 SDK 实现**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add wifi gateway vendor protocol"
```

Expected: commit succeeds.

- [ ] **Step 4: 如果 App plan 文档未提交，提交计划文档**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway
git add docs/superpowers/plans/260703_1454_wifi_gateway_vendor_protocol_implementation_plan.md
git commit -m "docs: plan wifi gateway vendor protocol implementation"
```

Expected: commit succeeds if the plan file was not already committed. If there is nothing to commit, keep the existing clean state.

## Self-Review

- Spec coverage:
  - `43 0D` set encoding and response result: Task 1, Task 4, Task 5.
  - `43 0E` get encoding and typed connection status: Task 1, Task 4, Task 5.
  - `43 0F` get encoding, signed int8 RSSI, unavailable/read failed: Task 1, Task 4, Task 5.
  - `43 12` get encoding, credentials read success/not configured/internal error: Task 1, Task 4, Task 5.
  - response matching by subcode: Task 6.
  - no App UI implementation: file structure and Task 7 only build App.
  - sensitive password logging: no logging code is introduced in any task.
- Placeholder scan:
  - No placeholder steps; every code-changing step includes concrete Swift code.
- Type consistency:
  - Test names match planned types: `WiFiGatewayCredentials`, `WiFiGatewayCredentialValidationError`, `WiFiGatewayCredentialsSetResult`, `WiFiGatewayConnectionStatus`, `WiFiGatewayRSSIStatus`, `WiFiGatewayCredentialsReadResult`.
  - Function cases match planned `ResponseCode` names: `wifiGatewayCredentialsSet`, `wifiGatewayConnectionStatusGet`, `wifiGatewayRSSIStatusGet`, `wifiGatewayCredentialsGet`.
