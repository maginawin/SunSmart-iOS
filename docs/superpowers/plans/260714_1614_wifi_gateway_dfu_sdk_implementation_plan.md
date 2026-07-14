# WiFi Gateway DFU SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `NordicSigMeshSDK` 中实现 WiFi Gateway `43 10` Start DFU 和 `43 11` Get DFU Status 的严格编码、强类型解析及 response matching。

**Architecture:** 继续使用现有 `SunricherVendorSet/Get/Status` Gateway vendor routing；由 throwing metadata value object 在发送前封锁非法 `43 10` 参数，由 `SunricherVendorStatus` 统一解析 `43 10` ACK、`43 11` 查询应答及主动上报。SDK 不维护 OTA session、不自动轮询，也不修改 App 业务代码。

**Tech Stack:** Swift、XCTest、NordicSigMeshSDK、SIG Mesh Vendor Message、Xcode iPhoneOS build。

## Global Constraints

- 本轮只修改本地 SDK `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`；App 仓库除计划和实施总结文档外不修改业务代码。
- `43 10` 完整业务 payload 从 `43` 起最多 256 字节，SDK 构造阶段必须严格拒绝超限参数。
- URL 仅支持区分大小写的 `http://`，不支持 `https://`。
- URL、SHA256、firmware ID 按 ASCII 字节编码；出站 URL 和 firmware ID 拒绝双引号、CR、LF 与不可打印字符。
- SHA256 必须为 64 字节十六进制 ASCII；size 必须大于 0；firmware ID 长度必须为 `1...32`。
- `43 11` 的 `ret=0x00` 只代表状态消息有效，不代表 OTA 成功；SDK 不以 percent 或其它 stage 推断成功。
- 未知 stage、code、ret 必须保留 raw value，不能映射为成功。
- 不新增 Auth 信息，不顺手重构或格式化无关文件。
- 验证使用直接 `xcodebuild`、iPhoneOS generic destination，不使用 Simulator、shell 包装或日志重定向。

---

## 文件结构

- 修改 `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`：增加 `43 10` SET case 和 wire encoding。
- 修改 `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`：增加固定 `43 11` GET case。
- 修改 `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`：增加 metadata、validation error、start/status result、stage/code/status 模型，以及 routing 和严格 parser。
- 修改 `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`：为新增 SET case 增加 no-op，禁止缓存敏感 metadata 或 OTA 状态。
- 修改 `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`：覆盖编码、边界、解析、malformed payload 和 response matching。
- 新增 App 仓库实施总结 `docs/260714_1614_wifi_gateway_dfu_sdk_implementation_summary.md`：记录实际提交和验证证据，不包含 App 功能实现。

---

### Task 1: `43 10` Metadata、SET 编码与 ACK 解析

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`

**Interfaces:**
- Produces: `WiFiGatewayDFUMetadata.init(url:sha256:size:firmwareID:) throws`
- Produces: `VendorFunctionSet.wifiGatewayDFUStart(WiFiGatewayDFUMetadata)`
- Produces: `FunctionParameters.wifiGatewayDFUStart(WiFiGatewayDFUStartResult)`
- Produces: `ResponseCode.wifiGatewayDFUStart`

- [ ] **Step 1: 写入失败的 metadata 与 SET 编码测试**

在 `WiFiGatewayVendorMessageTests` 中加入以下测试。测试既检查 wire bytes，也固定 256 字节边界和每类 validation error：

```swift
func testWiFiGatewayDFUStartEncoding() throws {
    let metadata = try WiFiGatewayDFUMetadata(
        url: "http://fw.example.com/wifi.bin",
        sha256: String(repeating: "a1", count: 32),
        size: 0x12345678,
        firmwareID: "0.4.0"
    )
    let expected = Data([0x43, 0x10, 0x1E, 0x00])
        + Data("http://fw.example.com/wifi.bin".utf8)
        + Data(String(repeating: "a1", count: 32).utf8)
        + Data([0x78, 0x56, 0x34, 0x12, 0x05])
        + Data("0.4.0".utf8)
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUStart(metadata)).parameters,
        expected
    )
}

func testWiFiGatewayDFUMetadataPayloadLengthBoundary() throws {
    let sha256 = String(repeating: "0", count: 64)
    let maximumURL = "http://" + String(repeating: "a", count: 171)
    let metadata = try WiFiGatewayDFUMetadata(
        url: maximumURL,
        sha256: sha256,
        size: 1,
        firmwareID: "0.4.0"
    )
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUStart(metadata)).parameters?.count,
        256
    )

    let oversizedURL = "http://" + String(repeating: "a", count: 172)
    XCTAssertThrowsError(
        try WiFiGatewayDFUMetadata(
            url: oversizedURL,
            sha256: sha256,
            size: 1,
            firmwareID: "0.4.0"
        )
    ) { error in
        XCTAssertEqual(
            error as? WiFiGatewayDFUMetadataValidationError,
            .payloadTooLarge(257)
        )
    }
}

func testWiFiGatewayDFUMetadataRejectsInvalidFields() {
    let sha256 = String(repeating: "A", count: 64)
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "https://fw/a", sha256: sha256, size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidURLScheme)
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/\"a", sha256: sha256, size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidCharacter(field: .url, byte: 0x22))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/\na", sha256: sha256, size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidCharacter(field: .url, byte: 0x0A))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/é", sha256: sha256, size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidCharacter(field: .url, byte: 0xC3))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: String(repeating: "0", count: 63), size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidSHA256Length(63))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: String(repeating: "g", count: 64), size: 1, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidSHA256Character(byte: 0x67))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 0, firmwareID: "1")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidSize)
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 1, firmwareID: "")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidFirmwareIDLength(0))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 1, firmwareID: String(repeating: "1", count: 33))) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidFirmwareIDLength(33))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 1, firmwareID: "1\r2")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidCharacter(field: .firmwareID, byte: 0x0D))
    }
    XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 1, firmwareID: "1\"2")) {
        XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .invalidCharacter(field: .firmwareID, byte: 0x22))
    }

    XCTAssertNoThrow(try WiFiGatewayDFUMetadata(url: "http://fw\\a", sha256: String(repeating: "aF", count: 32), size: 1, firmwareID: "1"))
    XCTAssertNoThrow(try WiFiGatewayDFUMetadata(url: "http://fw/a", sha256: sha256, size: 1, firmwareID: String(repeating: "1", count: 32)))
}
```

- [ ] **Step 2: 写入失败的 `43 10` ACK 测试**

```swift
func testWiFiGatewayDFUStartResponseParsing() {
    assertDFUStart(Data([0x43, 0x10, 0x00]), expected: .accepted, isSuccessful: true, errorCode: nil)
    assertDFUStart(Data([0x43, 0x10, 0x01]), expected: .invalidParameters, isSuccessful: false, errorCode: 0x01)
    assertDFUStart(Data([0x43, 0x10, 0x02]), expected: .busy, isSuccessful: false, errorCode: 0x02)
    assertDFUStart(Data([0x43, 0x10, 0x03]), expected: .internalError, isSuccessful: false, errorCode: 0x03)
    assertDFUStart(Data([0x43, 0x10, 0x04]), expected: .internetUnavailable, isSuccessful: false, errorCode: 0x04)
    assertDFUStart(Data([0x43, 0x10, 0x7F]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

    let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x10, 0x00, 0x00]))
    XCTAssertEqual(trailing?.status.code, .wifiGatewayDFUStart)
    XCTAssertFalse(trailing?.status.isSuccessful ?? true)
    XCTAssertNil(trailing?.status.parameters)
}

private func assertDFUStart(
    _ data: Data,
    expected: WiFiGatewayDFUStartResult,
    isSuccessful: Bool,
    errorCode: UInt8?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let status = SunricherVendorStatus(parameters: data)
    XCTAssertEqual(status?.status.code, .wifiGatewayDFUStart, file: file, line: line)
    XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
    XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
    if case .wifiGatewayDFUStart(let result) = status?.status.parameters {
        XCTAssertEqual(result, expected, file: file, line: line)
    } else {
        XCTFail("Expected WiFi Gateway DFU start result", file: file, line: line)
    }
}
```

- [ ] **Step 3: 运行定向测试并确认因接口不存在而失败**

Run: `swift test --filter WiFiGatewayVendorMessageTests`

Expected: 若 SwiftPM 能进入测试编译，因 `WiFiGatewayDFUMetadata`、`.wifiGatewayDFUStart` 等符号不存在而 FAIL；若先出现既有 `no such module 'UIKit'`，记录该原始阻塞并继续 Step 4，不能把它描述为测试断言失败。

- [ ] **Step 4: 实现 metadata 和 start result 类型**

在 `SunricherVendorStatus.swift` 的现有 WiFi Gateway 模型区域加入：

```swift
public enum WiFiGatewayDFUMetadataField: Equatable {
    case url
    case firmwareID
}

public enum WiFiGatewayDFUMetadataValidationError: Error, Equatable {
    case invalidURLScheme
    case invalidCharacter(field: WiFiGatewayDFUMetadataField, byte: UInt8)
    case invalidSHA256Length(Int)
    case invalidSHA256Character(byte: UInt8)
    case invalidSize
    case invalidFirmwareIDLength(Int)
    case payloadTooLarge(Int)
}

public struct WiFiGatewayDFUMetadata: Equatable {
    public let url: String
    public let sha256: String
    public let size: UInt32
    public let firmwareID: String
    let urlBytes: [UInt8]
    let sha256Bytes: [UInt8]
    let firmwareIDBytes: [UInt8]

    public init(url: String, sha256: String, size: UInt32, firmwareID: String) throws {
        guard url.hasPrefix("http://") else {
            throw WiFiGatewayDFUMetadataValidationError.invalidURLScheme
        }
        let urlBytes = Array(url.utf8)
        try Self.validateASCII(urlBytes, field: .url)

        let sha256Bytes = Array(sha256.utf8)
        guard sha256Bytes.count == 64 else {
            throw WiFiGatewayDFUMetadataValidationError.invalidSHA256Length(sha256Bytes.count)
        }
        for byte in sha256Bytes where !((0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)) {
            throw WiFiGatewayDFUMetadataValidationError.invalidSHA256Character(byte: byte)
        }
        guard size > 0 else {
            throw WiFiGatewayDFUMetadataValidationError.invalidSize
        }

        let firmwareIDBytes = Array(firmwareID.utf8)
        guard (1...32).contains(firmwareIDBytes.count) else {
            throw WiFiGatewayDFUMetadataValidationError.invalidFirmwareIDLength(firmwareIDBytes.count)
        }
        try Self.validateASCII(firmwareIDBytes, field: .firmwareID)

        let payloadLength = 73 + urlBytes.count + firmwareIDBytes.count
        guard payloadLength <= 256 else {
            throw WiFiGatewayDFUMetadataValidationError.payloadTooLarge(payloadLength)
        }

        self.url = url
        self.sha256 = sha256
        self.size = size
        self.firmwareID = firmwareID
        self.urlBytes = urlBytes
        self.sha256Bytes = sha256Bytes
        self.firmwareIDBytes = firmwareIDBytes
    }

    private static func validateASCII(_ bytes: [UInt8], field: WiFiGatewayDFUMetadataField) throws {
        for byte in bytes {
            guard (0x20...0x7E).contains(byte), byte != 0x22, byte != 0x0D, byte != 0x0A else {
                throw WiFiGatewayDFUMetadataValidationError.invalidCharacter(field: field, byte: byte)
            }
        }
    }
}

public enum WiFiGatewayDFUStartResult: Equatable {
    case accepted
    case invalidParameters
    case busy
    case internalError
    case internetUnavailable
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .accepted
        case 0x01: self = .invalidParameters
        case 0x02: self = .busy
        case 0x03: self = .internalError
        case 0x04: self = .internetUnavailable
        default: self = .reserved(rawValue: rawValue)
        }
    }
}
```

- [ ] **Step 5: 接入 `43 10` routing、SET 编码和严格 ACK parser**

进行以下精确扩展：

```swift
// VendorGatewayCode
case wifiDFUStart = 0x10

// VendorFunctionSet.data
case .wifiGatewayDFUStart(let metadata):
    return data
        + UInt16(metadata.urlBytes.count)
        + Data(metadata.urlBytes)
        + Data(metadata.sha256Bytes)
        + metadata.size
        + UInt8(metadata.firmwareIDBytes.count)
        + Data(metadata.firmwareIDBytes)

// VendorFunctionSet.command
case .wifiGatewayDFUStart: return .wifiGatewayDFUStart

// VendorFunctionSet
case wifiGatewayDFUStart(WiFiGatewayDFUMetadata)

// FunctionParameters
case wifiGatewayDFUStart(WiFiGatewayDFUStartResult)
```

在 `ResponseCode.init(opcode:subcode:)`、case 列表、`code` 和 `isWiFiGatewayResponse` 中加入 `.wifiGatewayDFUStart`，其 code 固定为 `[0x43, 0x10]`。在 `wifiGatewayParameters` 中加入：

```swift
case .wifiGatewayDFUStart:
    guard data.count == 3 else { return nil }
    return .wifiGatewayDFUStart(.init(rawValue: status))
```

在 `VendorServerDelegate` 的 WiFi no-op 分支加入 `.wifiGatewayDFUStart`：

```swift
case .wifiGatewayCredentialsSet,
        .wifiGatewayCredentialsClear,
        .wifiGatewayDFUStart:
    return
```

- [ ] **Step 6: 运行 Task 1 定向验证**

Run: `swift test --filter WiFiGatewayVendorMessageTests`

Expected: 在支持 UIKit 的测试环境中新增测试 PASS；若仍被既有 `no such module 'UIKit'` 阻塞，保存错误证据并运行 SDK iPhoneOS build，确保新增 exhaustive switch 和生产代码可编译。

Run: `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: 提交 Task 1**

```bash
git add Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift
git commit -m "feat: add wifi gateway dfu start protocol"
```

---

### Task 2: `43 11` GET、状态解析与 response matching

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

**Interfaces:**
- Consumes: `ResponseCode` Gateway routing from Task 1
- Produces: `VendorFunctionGet.wifiGatewayDFUStatus`
- Produces: `WiFiGatewayDFUStatusResult.success(WiFiGatewayDFUStatus)`
- Produces: `FunctionParameters.wifiGatewayDFUStatus(WiFiGatewayDFUStatusResult)`
- Produces: `ResponseCode.wifiGatewayDFUStatusGet`

- [ ] **Step 1: 写入失败的 GET、正常状态和主动上报解析测试**

```swift
func testWiFiGatewayDFUStatusGetEncodingAndParsing() {
    XCTAssertEqual(
        SunricherVendorGet(function: .wifiGatewayDFUStatus).parameters,
        Data([0x43, 0x11])
    )

    let payload = Data([0x43, 0x11, 0x00, 0x01, 0x2A, 0x00, 0x05])
        + Data("0.4.0".utf8)
        + Data([0x05])
        + Data("0.3.0".utf8)
    let response = SunricherVendorStatus(parameters: payload)
    XCTAssertTrue(response?.status.isSuccessful ?? false)
    XCTAssertEqual(response?.status.errorCode, nil)
    XCTAssertEqual(response?.status.code, .wifiGatewayDFUStatusGet)
    if case .wifiGatewayDFUStatus(.success(let value)) = response?.status.parameters {
        XCTAssertEqual(value.stage, .downloading)
        XCTAssertEqual(value.percent, 42)
        XCTAssertEqual(value.code, .none)
        XCTAssertEqual(value.firmwareID, "0.4.0")
        XCTAssertEqual(value.moduleVersion, "0.3.0")
    } else {
        XCTFail("Expected WiFi Gateway DFU status")
    }

    let unsolicited = SunricherVendorStatus(parameters: payload)
    XCTAssertNotNil(unsolicited)
}

func testWiFiGatewayDFUStatusAllowsIdleWithEmptyVersions() {
    let payload = Data([0x43, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    if case .wifiGatewayDFUStatus(.success(let value)) = SunricherVendorStatus(parameters: payload)?.status.parameters {
        XCTAssertEqual(value.stage, .idle)
        XCTAssertEqual(value.percent, 0)
        XCTAssertEqual(value.code, .none)
        XCTAssertNil(value.firmwareID)
        XCTAssertNil(value.moduleVersion)
    } else {
        XCTFail("Expected idle WiFi Gateway DFU status")
    }
}

func testWiFiGatewayDFUStatusAllowsMaximumVersionLengths() {
    let firmwareID = String(repeating: "f", count: 32)
    let moduleVersion = String(repeating: "m", count: 32)
    let payload = Data([0x43, 0x11, 0x00, 0x07, 0x64, 0x00, 0x20])
        + Data(firmwareID.utf8)
        + Data([0x20])
        + Data(moduleVersion.utf8)
    if case .wifiGatewayDFUStatus(.success(let value)) = SunricherVendorStatus(parameters: payload)?.status.parameters {
        XCTAssertEqual(value.firmwareID, firmwareID)
        XCTAssertEqual(value.moduleVersion, moduleVersion)
    } else {
        XCTFail("Expected maximum-length WiFi Gateway DFU status strings")
    }
}
```

- [ ] **Step 2: 写入失败的 stage/code、错误 ret 和 malformed payload 测试**

使用以下表驱动测试覆盖 stage `0x00...0x0A` 和 code `0x00...0x17`；每一行都构造完整合法 `43 11 00` payload 并通过 `SunricherVendorStatus` 解析：

```swift
func testWiFiGatewayDFUStatusStageAndCodeMappings() {
    let stages: [(UInt8, WiFiGatewayDFUStage)] = [
        (0x00, .idle), (0x01, .downloading), (0x02, .verifying),
        (0x03, .verifyOK), (0x04, .verifyFail), (0x05, .rebooting),
        (0x06, .recovering), (0x07, .versionCheck), (0x08, .success),
        (0x09, .timeout), (0x0A, .failed)
    ]
    for (rawValue, expected) in stages {
        let payload = Data([0x43, 0x11, 0x00, rawValue, 0x00, 0x00, 0x00, 0x00])
        if case .wifiGatewayDFUStatus(.success(let value)) = SunricherVendorStatus(parameters: payload)?.status.parameters {
            XCTAssertEqual(value.stage, expected)
        } else {
            XCTFail("Expected stage mapping for \(rawValue)")
        }
    }

    let codes: [(UInt8, WiFiGatewayDFUCode)] = [
        (0x00, .none), (0x01, .noNetwork), (0x02, .http),
        (0x03, .sizeMismatch), (0x04, .verify), (0x05, .versionRejected),
        (0x06, .noPartition), (0x07, .noMemory), (0x08, .otaBegin),
        (0x09, .otaWrite), (0x0A, .otaEnd), (0x0B, .setBoot),
        (0x0C, .internalError), (0x0D, .triggerError), (0x0E, .triggerTimeout),
        (0x0F, .triggerBusyTimeout), (0x10, .otaTimeout), (0x11, .protocolError),
        (0x12, .versionProtocol), (0x13, .versionMissing), (0x14, .versionQueryError),
        (0x15, .versionQueryTimeout), (0x16, .versionMismatch), (0x17, .recoveryTimeout)
    ]
    for (rawValue, expected) in codes {
        let payload = Data([0x43, 0x11, 0x00, 0x0A, 0x00, rawValue, 0x00, 0x00])
        if case .wifiGatewayDFUStatus(.success(let value)) = SunricherVendorStatus(parameters: payload)?.status.parameters {
            XCTAssertEqual(value.code, expected)
        } else {
            XCTFail("Expected code mapping for \(rawValue)")
        }
    }
}
```

另加入以下边界测试：

```swift
func testWiFiGatewayDFUStatusReservedValuesAndMalformedPayloads() {
    let reserved = SunricherVendorStatus(parameters: Data([0x43, 0x11, 0x00, 0x7F, 0x64, 0x80, 0x00, 0x00]))
    if case .wifiGatewayDFUStatus(.success(let value)) = reserved?.status.parameters {
        XCTAssertEqual(value.stage, .reserved(rawValue: 0x7F))
        XCTAssertEqual(value.code, .reserved(rawValue: 0x80))
    } else {
        XCTFail("Expected reserved WiFi Gateway DFU values")
    }

    assertDFUStatusResult(Data([0x43, 0x11, 0x01]), expected: .invalidParameters, errorCode: 0x01)
    assertDFUStatusResult(Data([0x43, 0x11, 0x7F]), expected: .reserved(rawValue: 0x7F), errorCode: 0x7F)

    let malformed: [Data] = [
        Data([0x43, 0x11, 0x00, 0x01, 0x65, 0x00, 0x00, 0x00]),
        Data([0x43, 0x11, 0x00, 0x01, 0x32, 0x00, 0x21, 0x00]),
        Data([0x43, 0x11, 0x00, 0x01, 0x32, 0x00, 0x01, 0xC3, 0x00]),
        Data([0x43, 0x11, 0x00, 0x01, 0x32, 0x00, 0x05]) + Data("0.4".utf8),
        Data([0x43, 0x11, 0x00, 0x01, 0x32, 0x00, 0x00, 0x21]),
        Data([0x43, 0x11, 0x00, 0x01, 0x32, 0x00, 0x00, 0x00, 0xFF]),
        Data([0x43, 0x11, 0x01, 0x00])
    ]
    for payload in malformed {
        let status = SunricherVendorStatus(parameters: payload)
        XCTAssertFalse(status?.status.isSuccessful ?? true)
        XCTAssertNil(status?.status.parameters)
    }

    let inconsistent = SunricherVendorStatus(parameters: Data([0x43, 0x11, 0x00, 0x08, 0x64, 0x16, 0x00, 0x00]))
    if case .wifiGatewayDFUStatus(.success(let value)) = inconsistent?.status.parameters {
        XCTAssertEqual(value.stage, .success)
        XCTAssertEqual(value.code, .versionMismatch)
    } else {
        XCTFail("Expected SDK to preserve inconsistent stage and code")
    }
}
```

实现测试 helper：

```swift
private func assertDFUStatusResult(
    _ data: Data,
    expected: WiFiGatewayDFUStatusResult,
    errorCode: UInt8,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let status = SunricherVendorStatus(parameters: data)
    XCTAssertEqual(status?.status.code, .wifiGatewayDFUStatusGet, file: file, line: line)
    XCTAssertFalse(status?.status.isSuccessful ?? true, file: file, line: line)
    XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
    if case .wifiGatewayDFUStatus(let result) = status?.status.parameters {
        XCTAssertEqual(result, expected, file: file, line: line)
    } else {
        XCTFail("Expected WiFi Gateway DFU status result", file: file, line: line)
    }
}
```

- [ ] **Step 3: 扩展现有 response matching 测试**

在 `testWiFiGatewayVendorStatusMustMatchCurrentCommandCode` 中加入 `43 10`、`43 11` 与既有 `43 14` 的交叉隔离断言：

```swift
let dfuStartMetadata = try WiFiGatewayDFUMetadata(
    url: "http://fw/a.bin",
    sha256: String(repeating: "0", count: 64),
    size: 1,
    firmwareID: "0.4.0"
)
let dfuStartHandle = MeshMessageHandle(
    message: SunricherVendorSet(function: .wifiGatewayDFUStart(dfuStartMetadata)),
    address: 0x0003
)
let dfuStartStatus = SunricherVendorStatus(parameters: Data([0x43, 0x10, 0x00]))!
let dfuStatusHandle = MeshMessageHandle(
    message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
    address: 0x0003
)
let dfuStatus = SunricherVendorStatus(parameters: Data([0x43, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))!

XCTAssertTrue(dfuStartHandle.matchesResponse(dfuStartStatus, from: 0x0003))
XCTAssertFalse(dfuStartHandle.matchesResponse(dfuStatus, from: 0x0003))
XCTAssertTrue(dfuStatusHandle.matchesResponse(dfuStatus, from: 0x0003))
XCTAssertFalse(dfuStatusHandle.matchesResponse(dfuStartStatus, from: 0x0003))
XCTAssertFalse(dfuStatusHandle.matchesResponse(firmwareVersionStatus, from: 0x0003))
XCTAssertFalse(firmwareVersionHandle.matchesResponse(dfuStatus, from: 0x0003))
XCTAssertFalse(dfuStatusHandle.matchesResponse(dfuStatus, from: 0x0004))
```

- [ ] **Step 4: 运行测试并确认因 `43 11` 接口不存在而失败**

Run: `swift test --filter WiFiGatewayVendorMessageTests`

Expected: 若进入测试编译，因 `.wifiGatewayDFUStatus`、`WiFiGatewayDFUStage` 等符号不存在而 FAIL；若被既有 UIKit 问题先行阻塞，记录原始错误并继续实现。

- [ ] **Step 5: 实现 stage、code、status 和 status result 类型**

在 `SunricherVendorStatus.swift` 加入以下完整枚举。每个枚举提供非失败的内部 `init(rawValue:)`，未知值构造 `.reserved(rawValue:)`：

```swift
public enum WiFiGatewayDFUStage: Equatable {
    case idle
    case downloading
    case verifying
    case verifyOK
    case verifyFail
    case rebooting
    case recovering
    case versionCheck
    case success
    case timeout
    case failed
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .idle
        case 0x01: self = .downloading
        case 0x02: self = .verifying
        case 0x03: self = .verifyOK
        case 0x04: self = .verifyFail
        case 0x05: self = .rebooting
        case 0x06: self = .recovering
        case 0x07: self = .versionCheck
        case 0x08: self = .success
        case 0x09: self = .timeout
        case 0x0A: self = .failed
        default: self = .reserved(rawValue: rawValue)
        }
    }
}

public enum WiFiGatewayDFUCode: Equatable {
    case none
    case noNetwork
    case http
    case sizeMismatch
    case verify
    case versionRejected
    case noPartition
    case noMemory
    case otaBegin
    case otaWrite
    case otaEnd
    case setBoot
    case internalError
    case triggerError
    case triggerTimeout
    case triggerBusyTimeout
    case otaTimeout
    case protocolError
    case versionProtocol
    case versionMissing
    case versionQueryError
    case versionQueryTimeout
    case versionMismatch
    case recoveryTimeout
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .none
        case 0x01: self = .noNetwork
        case 0x02: self = .http
        case 0x03: self = .sizeMismatch
        case 0x04: self = .verify
        case 0x05: self = .versionRejected
        case 0x06: self = .noPartition
        case 0x07: self = .noMemory
        case 0x08: self = .otaBegin
        case 0x09: self = .otaWrite
        case 0x0A: self = .otaEnd
        case 0x0B: self = .setBoot
        case 0x0C: self = .internalError
        case 0x0D: self = .triggerError
        case 0x0E: self = .triggerTimeout
        case 0x0F: self = .triggerBusyTimeout
        case 0x10: self = .otaTimeout
        case 0x11: self = .protocolError
        case 0x12: self = .versionProtocol
        case 0x13: self = .versionMissing
        case 0x14: self = .versionQueryError
        case 0x15: self = .versionQueryTimeout
        case 0x16: self = .versionMismatch
        case 0x17: self = .recoveryTimeout
        default: self = .reserved(rawValue: rawValue)
        }
    }
}
```

状态模型为：

```swift
public struct WiFiGatewayDFUStatus: Equatable {
    public let stage: WiFiGatewayDFUStage
    public let percent: UInt8
    public let code: WiFiGatewayDFUCode
    public let firmwareID: String?
    public let moduleVersion: String?
}

public enum WiFiGatewayDFUStatusResult: Equatable {
    case success(WiFiGatewayDFUStatus)
    case invalidParameters
    case reserved(rawValue: UInt8)
}
```

- [ ] **Step 6: 接入 GET routing 和严格 `43 11` parser**

扩展：

```swift
// VendorGatewayCode
case wifiDFUStatusGet = 0x11

// VendorFunctionGet.command
case .wifiGatewayDFUStatus: return .wifiGatewayDFUStatusGet

// VendorFunctionGet
case wifiGatewayDFUStatus

// FunctionParameters
case wifiGatewayDFUStatus(WiFiGatewayDFUStatusResult)
```

在 `ResponseCode` 的 initializer、case、code 和 `isWiFiGatewayResponse` 中加入 `[0x43, 0x11]`。在 WiFi parser 中使用以下完整长度算法：

```swift
private static func wifiGatewayDFUStatusParameters(data: Data, status: UInt8) -> FunctionParameters? {
    guard status == 0x00 else {
        guard data.count == 3 else { return nil }
        if status == 0x01 {
            return .wifiGatewayDFUStatus(.invalidParameters)
        }
        return .wifiGatewayDFUStatus(.reserved(rawValue: status))
    }

    guard data.count >= 8 else { return nil }
    let percent = data[4]
    guard percent <= 100 else { return nil }

    let firmwareIDLength = Int(data[6])
    guard firmwareIDLength <= 32 else { return nil }
    let firmwareIDStart = 7
    let firmwareIDEnd = firmwareIDStart + firmwareIDLength
    guard data.count >= firmwareIDEnd + 1 else { return nil }

    let moduleVersionLength = Int(data[firmwareIDEnd])
    guard moduleVersionLength <= 32 else { return nil }
    let moduleVersionStart = firmwareIDEnd + 1
    let expectedLength = moduleVersionStart + moduleVersionLength
    guard data.count == expectedLength else { return nil }

    let firmwareIDBytes = Array(data[firmwareIDStart..<firmwareIDEnd])
    let moduleVersionBytes = Array(data[moduleVersionStart..<expectedLength])
    guard firmwareIDBytes.allSatisfy({ (0x20...0x7E).contains($0) }),
          moduleVersionBytes.allSatisfy({ (0x20...0x7E).contains($0) }) else {
        return nil
    }

    let firmwareID = firmwareIDBytes.isEmpty ? nil : String(bytes: firmwareIDBytes, encoding: .ascii)
    let moduleVersion = moduleVersionBytes.isEmpty ? nil : String(bytes: moduleVersionBytes, encoding: .ascii)
    guard firmwareIDBytes.isEmpty || firmwareID != nil,
          moduleVersionBytes.isEmpty || moduleVersion != nil else {
        return nil
    }

    return .wifiGatewayDFUStatus(.success(.init(
        stage: .init(rawValue: data[3]),
        percent: percent,
        code: .init(rawValue: data[5]),
        firmwareID: firmwareID,
        moduleVersion: moduleVersion
    )))
}
```

从 `wifiGatewayParameters` 的 `.wifiGatewayDFUStatusGet` 分支调用该 helper。

- [ ] **Step 7: 运行 Task 2 定向验证**

Run: `swift test --filter WiFiGatewayVendorMessageTests`

Expected: 支持 UIKit 时全部 WiFi Gateway vendor tests PASS；若仍为既有 `no such module 'UIKit'`，原样记录阻塞。

Run: `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 8: 提交 Task 2**

```bash
git add Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift
git commit -m "feat: add wifi gateway dfu status protocol"
```

---

### Task 3: 全量目标验证与实施总结

**Files:**
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`
- Verify: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway/SunSmart.xcworkspace`
- Create: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway/docs/260714_1614_wifi_gateway_dfu_sdk_implementation_summary.md`

**Interfaces:**
- Consumes: Task 1 和 Task 2 的最终 SDK public API
- Produces: 四品牌 target 的编译兼容性证据和本轮实际交付记录

- [ ] **Step 1: 检查 SDK 改动范围和 diff 质量**

Run: `git status --short`

Expected: SDK 仓库只包含预期文件；Task 1、Task 2 已提交后应为空。

Run: `git diff --check HEAD~2 HEAD`

Expected: 无 whitespace error。

Run: `rg -n "wifiGatewayDFU|WiFiGatewayDFU|wifiDFU" Sources Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

Expected: 命中 Set/Get/Status、delegate no-op 和测试，不命中无关 manager 或 App 状态存储。

- [ ] **Step 2: 运行最终 SDK 验证**

Run: `swift test --filter WiFiGatewayVendorMessageTests`

Expected: 测试 PASS；若现有 UIKit/macOS SwiftPM 限制仍存在，保留完整 `no such module 'UIKit'` 证据并将该项标记为 blocked，而不是 passed。

Run: `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 依次构建四个 App iPhoneOS scheme**

在 App worktree 中直接运行：

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: 四次均输出 `BUILD SUCCEEDED`。

- [ ] **Step 4: 编写实际实施总结**

创建 `docs/260714_1614_wifi_gateway_dfu_sdk_implementation_summary.md`，内容必须明确记录：

- 实现的两个协议和 public API。
- SDK 实际修改文件。
- metadata 校验边界和 `43 11` parser 边界。
- SDK 两个实际 commit hash。
- 定向测试的实际结果；若被 UIKit 阻塞，原样记录阻塞而非宣称通过。
- SDK iPhoneOS build 和四个 App scheme 的实际结果。
- 明确说明没有实现 App OTA 流程、自动轮询和 UI。

- [ ] **Step 5: 提交实施总结并检查两个仓库状态**

在 App worktree 提交总结：

```bash
git add docs/260714_1614_wifi_gateway_dfu_sdk_implementation_summary.md
git commit -m "docs: summarize wifi gateway dfu sdk"
```

Run: `git status --short`

Expected: App worktree clean。

Run: `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short`

Expected: SDK repository clean。
