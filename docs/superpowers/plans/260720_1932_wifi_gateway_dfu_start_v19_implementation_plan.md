# WiFi Gateway DFU Start `0x43/0x10` V1.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session, with review checkpoints after each task. Do not use subagents for this plan.

**Goal:** 将 WiFi Gateway start OTA 请求切换到带非零 `ota_id` 的 V1.9 wire contract，并让 App 严格执行 RET 关联、EVENT 优先确认、一次性 `0x43/0x11` 恢复和 no-auto-resend。

**Architecture:** 本地 NordicSigMeshSDK 使用独立 typed start request/response 负责字段校验、LE 编解码和 ota ID 响应关联；App 使用纯 Swift pending-start recovery 模型管理本轮身份与无有效 RET 的确认决策，coordinator 只负责 Mesh I/O、会话建立和 UI event。现有 URL builder、`0x43/0x11` V1.9 parser/reducer、页面布局和状态 UI 保持不变，只增加精确 contracts。

**Tech Stack:** Swift 5、Foundation、UIKit、NordicSigMeshSDK、SIG Mesh Vendor Messages、XCTest、独立 `swiftc` focused tests、shell contracts、Xcode generic iPhoneOS builds。

> **执行记录（2026-07-20）：** 已按 Inline Execution 实施。由于 SDK 当前 `swift test` 在 macOS host 构建阶段会被既有 UIKit 依赖阻断，V1.9 start 类型被放入独立的 Foundation-only 文件，并增加可由 `swiftc` 直接执行的协议 contract；集成层改由 SDK Demo 与四个 App scheme 的 generic iPhoneOS 构建验证。该调整不改变已确认的协议或 App 行为。

## Global Constraints

- `firmware_id` 取 HTTPS body 的 `version`，最多移除一个前导 `v` 或 `V`。
- 每次用户点击 `UPGRADE` 或 `UPGRADE AGAIN` 都生成新的非零随机 `UInt64 ota_id`。
- EVENT 和一次 `0x43/0x11` 都无法确认时，显示通信超时并提供 `UPGRADE AGAIN`；不继续查询，不自动重发 `0x43/0x10`。
- 只发送 V1.9 新格式，不兼容旧版无 `ota_id` 的 start 请求。
- URL 必须使用当前 App 区域 HTTPS base URL，仅把 scheme 改成 `http`，追加 `/sitespace/ota/download?key={filename}`；不得使用 response body 的预签名 `url`。
- 保留 `URLQueryItem` 的必要 percent encoding；需求示例必须逐字生成指定 URL。
- `0x43/0x10` 不发送 `size` 或 `sha256`。
- 有效 RET 必须来自正确 source/network、精确 11 字节、ret 位于 `0x00...0x04` 且回显 ota ID 等于请求 ID。
- `ret=0x01...0x04` 是明确失败结果，不进入无有效 RET 的恢复查询；reserved ret 视为无有效 RET。
- 不新增或实现 `0x43/0x15` cancel，不修改现有 `0x43/0x11` V1.9 stage/code 布局。
- 不修改 generic BLE/Mesh firmware update 流程，不新增 Auth 信息，不顺手重构共享模块。
- App 源码继续由 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 共用。
- iOS 验证只使用 generic iPhoneOS `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。
- App worktree 与本地 SDK repository 分开提交；不得暂存或提交无关文件。

## File Structure

### Local NordicSigMeshSDK repository

- Create: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStart.swift` — Foundation-only start request/response、字段校验、11-byte RET parser 与 ota ID matcher。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift` — typed response routing，并移除旧 metadata 类型。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift` — V1.9 payload encoding。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift` — ota ID response correlation。
- Modify: `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift` — request validation、encoding、RET parsing 与旧格式拒绝。
- Modify: `Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift` — same-opcode/different-ota response isolation。
- Create: `scripts/check_wifi_gateway_dfu_start_v19.swift` — 不依赖 UIKit 的 start wire contract。

### App worktree

- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift` — 增加纯 Swift pending-start recovery decision model。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift` — ota ID 生成、typed request、RET/EVENT/one-query start flow。
- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift` — pending start 身份和恢复决策 focused tests。
- Create: `Tests/Firmware/WiFiFirmwareDFUMetadataBuilderTests.swift` — 精确 URL 与 version normalization contract。
- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — URL 示例、V1.9 API、无旧 payload、no-auto-resend contracts。
- Modify: `docs/260720_1921_wifi_gateway_dfu_start_v19_requirement_analysis.md` — 保持 confirmed baseline，不再改变已确认语义。
- Create: `docs/260720_1932_wifi_gateway_dfu_start_v19_implementation_summary.md` — 最终改动和验证证据。

---

### Task 1: Replace the SDK start request with the V1.9 typed wire contract

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:1148-1225`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift:232-238`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift:282-344`

**Interfaces:**
- Produces: `WiFiGatewayDFUStartRequest.init(otaID:url:firmwareID:) throws`.
- Produces: `VendorFunctionSet.wifiGatewayDFUStart(WiFiGatewayDFUStartRequest)`.
- Consumes: current App URL and normalized version strings.
- Preserves: `WiFiGatewayDFUStartResult` ret mapping.

- [ ] **Step 1: Replace the old encoding tests with failing V1.9 tests**

Replace `testWiFiGatewayDFUStartEncoding`, payload-boundary assertions, and invalid-field assertions with tests containing these exact cases:

```swift
func testWiFiGatewayDFUStartV19Encoding() throws {
    let request = try WiFiGatewayDFUStartRequest(
        otaID: 0x8877665544332211,
        url: "http://fw.example.com/wifi.bin",
        firmwareID: "0.4.0"
    )
    let expected = Data([0x43, 0x10])
        + Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        + Data([0x1E, 0x00])
        + Data("http://fw.example.com/wifi.bin".utf8)
        + Data([0x05])
        + Data("0.4.0".utf8)
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUStart(request)).parameters,
        expected
    )
    XCTAssertEqual(expected.count, 48)
}

func testWiFiGatewayDFUStartV19LengthBoundaries() throws {
    let firmwareID = "0.4.0"
    let maximumURL = "http://" + String(repeating: "a", count: 231)
    let request = try WiFiGatewayDFUStartRequest(
        otaID: 1,
        url: maximumURL,
        firmwareID: firmwareID
    )
    XCTAssertEqual(maximumURL.utf8.count, 238)
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUStart(request)).parameters?.count,
        256
    )

    let oversizedURL = "http://" + String(repeating: "a", count: 232)
    XCTAssertThrowsError(
        try WiFiGatewayDFUStartRequest(
            otaID: 1,
            url: oversizedURL,
            firmwareID: firmwareID
        )
    ) {
        XCTAssertEqual(
            $0 as? WiFiGatewayDFUStartValidationError,
            .urlTooLongForFirmwareID(urlLength: 239, firmwareIDLength: 5)
        )
    }
}

func testWiFiGatewayDFUStartV19RejectsInvalidFields() {
    XCTAssertThrowsError(
        try WiFiGatewayDFUStartRequest(otaID: 0, url: "http://fw/a", firmwareID: "1")
    ) {
        XCTAssertEqual($0 as? WiFiGatewayDFUStartValidationError, .invalidOTAID)
    }
    XCTAssertThrowsError(
        try WiFiGatewayDFUStartRequest(otaID: 1, url: "https://fw/a", firmwareID: "1")
    ) {
        XCTAssertEqual($0 as? WiFiGatewayDFUStartValidationError, .invalidURLScheme)
    }
    XCTAssertThrowsError(
        try WiFiGatewayDFUStartRequest(otaID: 1, url: "http://fw/a", firmwareID: "1,2")
    ) {
        XCTAssertEqual(
            $0 as? WiFiGatewayDFUStartValidationError,
            .invalidCharacter(field: .firmwareID, byte: 0x2C)
        )
    }
    XCTAssertThrowsError(
        try WiFiGatewayDFUStartRequest(otaID: 1, url: "http://fw/a", firmwareID: "1\\2")
    ) {
        XCTAssertEqual(
            $0 as? WiFiGatewayDFUStartValidationError,
            .invalidCharacter(field: .firmwareID, byte: 0x5C)
        )
    }
    XCTAssertNoThrow(
        try WiFiGatewayDFUStartRequest(otaID: UInt64.max, url: "http://", firmwareID: "1")
    )
}
```

- [ ] **Step 2: Run the focused SDK tests and verify red state**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
swift test --filter WiFiGatewayVendorMessageTests.testWiFiGatewayDFUStartV19Encoding
```

Expected: FAIL because `WiFiGatewayDFUStartRequest` and `WiFiGatewayDFUStartValidationError` do not exist.

- [ ] **Step 3: Replace metadata types with the exact V1.9 request types**

Replace `WiFiGatewayDFUMetadataField`, `WiFiGatewayDFUMetadataValidationError`, and `WiFiGatewayDFUMetadata` with:

```swift
public enum WiFiGatewayDFUStartField: Equatable {
    case url
    case firmwareID
}

public enum WiFiGatewayDFUStartValidationError: Error, Equatable {
    case invalidOTAID
    case invalidURLScheme
    case invalidCharacter(field: WiFiGatewayDFUStartField, byte: UInt8)
    case invalidURLLength(Int)
    case invalidFirmwareIDLength(Int)
    case urlTooLongForFirmwareID(urlLength: Int, firmwareIDLength: Int)
}

public struct WiFiGatewayDFUStartRequest: Equatable {
    public let otaID: UInt64
    public let url: String
    public let firmwareID: String
    let urlBytes: [UInt8]
    let firmwareIDBytes: [UInt8]

    public init(otaID: UInt64, url: String, firmwareID: String) throws {
        guard otaID != 0 else {
            throw WiFiGatewayDFUStartValidationError.invalidOTAID
        }
        guard url.hasPrefix("http://") else {
            throw WiFiGatewayDFUStartValidationError.invalidURLScheme
        }

        let urlBytes = Array(url.utf8)
        guard (7...242).contains(urlBytes.count) else {
            throw WiFiGatewayDFUStartValidationError.invalidURLLength(urlBytes.count)
        }
        try Self.validateURL(urlBytes)

        let firmwareIDBytes = Array(firmwareID.utf8)
        guard (1...32).contains(firmwareIDBytes.count) else {
            throw WiFiGatewayDFUStartValidationError.invalidFirmwareIDLength(
                firmwareIDBytes.count
            )
        }
        try Self.validateFirmwareID(firmwareIDBytes)

        guard urlBytes.count <= 243 - firmwareIDBytes.count else {
            throw WiFiGatewayDFUStartValidationError.urlTooLongForFirmwareID(
                urlLength: urlBytes.count,
                firmwareIDLength: firmwareIDBytes.count
            )
        }

        self.otaID = otaID
        self.url = url
        self.firmwareID = firmwareID
        self.urlBytes = urlBytes
        self.firmwareIDBytes = firmwareIDBytes
    }

    private static func validateURL(_ bytes: [UInt8]) throws {
        for byte in bytes {
            guard (0x20...0x7E).contains(byte), byte != 0x22 else {
                throw WiFiGatewayDFUStartValidationError.invalidCharacter(
                    field: .url,
                    byte: byte
                )
            }
        }
    }

    private static func validateFirmwareID(_ bytes: [UInt8]) throws {
        for byte in bytes {
            guard (0x20...0x7E).contains(byte),
                  byte != 0x22,
                  byte != 0x2C,
                  byte != 0x5C else {
                throw WiFiGatewayDFUStartValidationError.invalidCharacter(
                    field: .firmwareID,
                    byte: byte
                )
            }
        }
    }
}
```

Change `VendorFunctionSet` to consume `WiFiGatewayDFUStartRequest`:

```swift
case wifiGatewayDFUStart(WiFiGatewayDFUStartRequest)
```

Replace every remaining `WiFiGatewayDFUMetadata` construction in `WiFiGatewayVendorMessageTests`, including the cross-command response-isolation test, with a `WiFiGatewayDFUStartRequest` carrying `otaID: 7`. Keep that test's old 3-byte status only until Task 2 replaces the RET fixture; this removes all references to the deleted request type so the test target compiles.

- [ ] **Step 4: Encode the exact V1.9 payload**

Replace the current `.wifiGatewayDFUStart` encoding branch with:

```swift
case .wifiGatewayDFUStart(let request):
    return data
        + request.otaID.littleEndian
        + UInt16(request.urlBytes.count).littleEndian
        + Data(request.urlBytes)
        + UInt8(request.firmwareIDBytes.count)
        + Data(request.firmwareIDBytes)
```

Do not add `size`, `sha256`, legacy fallback, feature flags, or a second start enum case.

- [ ] **Step 5: Run all request encoding and validation tests**

```bash
swift test --filter WiFiGatewayVendorMessageTests.testWiFiGatewayDFUStartV19Encoding
swift test --filter WiFiGatewayVendorMessageTests.testWiFiGatewayDFUStartV19LengthBoundaries
swift test --filter WiFiGatewayVendorMessageTests.testWiFiGatewayDFUStartV19RejectsInvalidFields
```

Expected: all three request encoding/validation tests PASS. The old RET fixture is not asserted in these filtered tests and is replaced in Task 2.

- [ ] **Step 6: Commit the SDK request contract**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "feat: update wifi dfu start request to v1.9"
```

---

### Task 2: Parse and correlate the V1.9 start RET in NordicSigMeshSDK

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:82-85,1199-1222,2388`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift:606-616`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift:346-364,580-615,660-678`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift:35-55`

**Interfaces:**
- Produces: `WiFiGatewayDFUStartResponse(result:otaID:)`.
- Produces: `FunctionParameters.wifiGatewayDFUStart(WiFiGatewayDFUStartResponse)`.
- Consumes: request ota ID from Task 1 for `MeshMessageHandle` correlation.

- [ ] **Step 1: Write failing 11-byte RET tests**

Replace the old 3-byte `testWiFiGatewayDFUStartResponseParsing` assertions with:

```swift
func testWiFiGatewayDFUStartV19ResponseParsing() {
    let otaID: UInt64 = 0x8877665544332211
    let otaBytes = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])

    assertDFUStart(
        Data([0x43, 0x10, 0x00]) + otaBytes,
        expectedResult: .accepted,
        expectedOTAID: otaID,
        isSuccessful: true,
        errorCode: nil
    )
    assertDFUStart(
        Data([0x43, 0x10, 0x03]) + otaBytes,
        expectedResult: .internalError,
        expectedOTAID: otaID,
        isSuccessful: false,
        errorCode: 0x03
    )
    assertDFUStart(
        Data([0x43, 0x10, 0x01]) + Data(repeating: 0, count: 8),
        expectedResult: .invalidParameters,
        expectedOTAID: 0,
        isSuccessful: false,
        errorCode: 0x01
    )
    assertDFUStart(
        Data([0x43, 0x10, 0x7F]) + otaBytes,
        expectedResult: .reserved(rawValue: 0x7F),
        expectedOTAID: otaID,
        isSuccessful: false,
        errorCode: 0x7F
    )

    XCTAssertNil(SunricherVendorStatus(parameters: Data([0x43, 0x10, 0x00]))?.status.parameters)
    XCTAssertNil(
        SunricherVendorStatus(
            parameters: Data([0x43, 0x10, 0x00]) + otaBytes + Data([0x00])
        )?.status.parameters
    )
}
```

Update the helper to inspect the response wrapper:

```swift
private func assertDFUStart(
    _ data: Data,
    expectedResult: WiFiGatewayDFUStartResult,
    expectedOTAID: UInt64,
    isSuccessful: Bool,
    errorCode: UInt8?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let status = SunricherVendorStatus(parameters: data)
    XCTAssertEqual(status?.status.code, .wifiGatewayDFUStart, file: file, line: line)
    XCTAssertEqual(status?.status.isSuccessful, isSuccessful, file: file, line: line)
    XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
    if case .wifiGatewayDFUStart(let response) = status?.status.parameters {
        XCTAssertEqual(response.result, expectedResult, file: file, line: line)
        XCTAssertEqual(response.otaID, expectedOTAID, file: file, line: line)
    } else {
        XCTFail("Expected WiFi Gateway DFU start response", file: file, line: line)
    }
}
```

- [ ] **Step 2: Write failing response-correlation tests**

Add to `MeshMessageHandleResponseMatchingTests`:

```swift
func testWiFiGatewayDFUStartStatusMustMatchRequestedOTAID() throws {
    let request = try WiFiGatewayDFUStartRequest(
        otaID: 0x1122334455667788,
        url: "http://fw/a.bin",
        firmwareID: "0.4.0"
    )
    let handle = MeshMessageHandle(
        message: SunricherVendorSet(function: .wifiGatewayDFUStart(request)),
        address: 0x0003
    )
    let matching = SunricherVendorStatus(
        parameters: Data([0x43, 0x10, 0x00, 0x88, 0x77, 0x66, 0x55,
                          0x44, 0x33, 0x22, 0x11])
    )!
    let stale = SunricherVendorStatus(
        parameters: Data([0x43, 0x10, 0x00, 0x89, 0x77, 0x66, 0x55,
                          0x44, 0x33, 0x22, 0x11])
    )!
    let zero = SunricherVendorStatus(
        parameters: Data([0x43, 0x10, 0x01]) + Data(repeating: 0, count: 8)
    )!

    XCTAssertFalse(handle.matchesResponse(stale, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(zero, from: 0x0003))
    XCTAssertTrue(handle.matchesResponse(matching, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(matching, from: 0x0004))
}
```

- [ ] **Step 3: Run the new tests and verify red state**

```bash
swift test --filter WiFiGatewayVendorMessageTests.testWiFiGatewayDFUStartV19ResponseParsing
swift test --filter MeshMessageHandleResponseMatchingTests.testWiFiGatewayDFUStartStatusMustMatchRequestedOTAID
```

Expected: FAIL because the parser still accepts only 3 bytes and response matching only checks the vendor command code.

- [ ] **Step 4: Add the typed response and exact parser**

Keep the existing result enum, then add:

```swift
public struct WiFiGatewayDFUStartResponse: Equatable {
    public let result: WiFiGatewayDFUStartResult
    public let otaID: UInt64

    init(result: WiFiGatewayDFUStartResult, otaID: UInt64) {
        self.result = result
        self.otaID = otaID
    }
}
```

Change `FunctionParameters` to:

```swift
case wifiGatewayDFUStart(WiFiGatewayDFUStartResponse)
```

Replace the current `guard data.count == 3` route with:

```swift
case .wifiGatewayDFUStart:
    guard data.count == 11 else { return nil }
    let otaID = data[3..<11].enumerated().reduce(UInt64(0)) { value, item in
        value | (UInt64(item.element) << UInt64(item.offset * 8))
    }
    return .wifiGatewayDFUStart(
        .init(result: .init(rawValue: status), otaID: otaID)
    )
```

- [ ] **Step 5: Correlate start responses by ota ID**

Put this special case before the generic vendor-set command comparison in `matchesVendorStatus`:

```swift
if let vendorSet = message as? SunricherVendorSet,
   case .wifiGatewayDFUStart(let request) = vendorSet.function {
    guard status.status.code == .wifiGatewayDFUStart,
          case .wifiGatewayDFUStart(let response) = status.status.parameters else {
        return false
    }
    return response.otaID == request.otaID
}
```

Leave all other vendor request matching unchanged.

- [ ] **Step 6: Update the existing cross-command WiFi test**

Where `WiFiGatewayVendorMessageTests` constructs `dfuStartMetadata` and a 3-byte status, replace them with:

```swift
let dfuStartRequest = try WiFiGatewayDFUStartRequest(
    otaID: 7,
    url: "http://fw/a.bin",
    firmwareID: "0.4.0"
)
let dfuStartHandle = MeshMessageHandle(
    message: SunricherVendorSet(function: .wifiGatewayDFUStart(dfuStartRequest)),
    address: 0x0003
)
let dfuStartStatus = SunricherVendorStatus(
    parameters: Data([0x43, 0x10, 0x00, 0x07, 0x00, 0x00, 0x00,
                      0x00, 0x00, 0x00, 0x00])
)!
```

- [ ] **Step 7: Run SDK verification and commit**

```bash
swift test --filter WiFiGatewayVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests
git diff --check
```

Expected: both test classes PASS and `git diff --check` produces no output.

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift
git commit -m "feat: correlate wifi dfu start responses"
```

---

### Task 3: Add a pure App pending-start recovery model

**Files:**
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift:76-155`
- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift:1-205`

**Interfaces:**
- Consumes: existing `WiFiFirmwareDFUStatusReducer` and `WiFiFirmwareDFUStatusSnapshot`.
- Produces: `WiFiFirmwareDFUStartRecovery.record(_:source:)`.
- Produces: `WiFiFirmwareDFUStartRecovery.nextAfterMissingRET()` with `.established`, `.queryOnce`, or `.unknown`.

- [ ] **Step 1: Add failing recovery-decision tests**

Add these calls to `main()`:

```swift
testStartRecoveryRejectsOtherRounds()
testStartRecoveryUsesEventBeforeQuery()
testStartRecoveryQueriesExactlyOnce()
testStartRecoveryCanBeConfirmedWhileQueryIsInFlight()
```

Add the exact test functions:

```swift
private static func testStartRecoveryRejectsOtherRounds() {
    var recovery = WiFiFirmwareDFUStartRecovery(
        otaID: 7,
        firmwareID: "0.4.0"
    )
    precondition(!recovery.record(snapshot(
        otaID: 8,
        stage: .preparing,
        percent: 0
    ), source: .event))
    precondition(!recovery.record(snapshot(
        otaID: 7,
        stage: .preparing,
        percent: 0,
        firmwareID: "0.5.0"
    ), source: .event))
    precondition(!recovery.record(snapshot(
        otaID: 0,
        stage: .idle,
        percent: 0,
        firmwareID: nil
    ), source: .event))
}

private static func testStartRecoveryUsesEventBeforeQuery() {
    var recovery = WiFiFirmwareDFUStartRecovery(
        otaID: 7,
        firmwareID: "0.4.0"
    )
    let preparing = snapshot(otaID: 7, stage: .preparing, percent: 0)
    precondition(recovery.record(preparing, source: .event))
    precondition(recovery.nextAfterMissingRET() == .established(preparing))
}

private static func testStartRecoveryQueriesExactlyOnce() {
    var recovery = WiFiFirmwareDFUStartRecovery(
        otaID: 7,
        firmwareID: "0.4.0"
    )
    precondition(recovery.nextAfterMissingRET() == .queryOnce)
    precondition(recovery.nextAfterMissingRET() == .unknown)
    precondition(recovery.nextAfterMissingRET() == .unknown)
}

private static func testStartRecoveryCanBeConfirmedWhileQueryIsInFlight() {
    var recovery = WiFiFirmwareDFUStartRecovery(
        otaID: 7,
        firmwareID: "0.4.0"
    )
    precondition(recovery.nextAfterMissingRET() == .queryOnce)
    let downloading = snapshot(otaID: 7, stage: .downloading, percent: 4)
    precondition(recovery.record(downloading, source: .query))
    precondition(recovery.nextAfterMissingRET() == .established(downloading))
}
```

- [ ] **Step 2: Run the standalone test and verify red state**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: FAIL because `WiFiFirmwareDFUStartRecovery` does not exist.

- [ ] **Step 3: Implement the pure recovery model**

Append to `WiFiFirmwareDFUStatusReducer.swift`:

```swift
enum WiFiFirmwareDFUStartRecoveryDecision: Equatable {
    case established(WiFiFirmwareDFUStatusSnapshot)
    case queryOnce
    case unknown
}

struct WiFiFirmwareDFUStartRecovery {
    let otaID: UInt64
    let firmwareID: String
    private(set) var reducer: WiFiFirmwareDFUStatusReducer
    private(set) var didIssueStatusQuery = false

    init(otaID: UInt64, firmwareID: String) {
        self.otaID = otaID
        self.firmwareID = firmwareID
        self.reducer = WiFiFirmwareDFUStatusReducer(
            targetFirmwareID: firmwareID,
            boundOTAID: otaID
        )
    }

    mutating func record(
        _ status: WiFiFirmwareDFUStatusSnapshot,
        source: WiFiFirmwareDFUStatusSource
    ) -> Bool {
        switch reducer.reduce(status, source: source) {
        case .accepted, .ignored(.duplicate):
            return true
        case .ignored:
            return false
        }
    }

    mutating func nextAfterMissingRET() -> WiFiFirmwareDFUStartRecoveryDecision {
        if let status = reducer.lastAcceptedStatus {
            return .established(status)
        }
        guard !didIssueStatusQuery else {
            return .unknown
        }
        didIssueStatusQuery = true
        return .queryOnce
    }
}
```

The reducer is initialized with the request ota ID, so the first status cannot bind an unrelated round.

- [ ] **Step 4: Run focused tests and commit**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
git diff --check
```

Expected: `WiFiFirmwareDFUStatusReducerTests passed`; diff check has no output.

```bash
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift
git commit -m "feat: model wifi dfu start recovery"
```

---

### Task 4: Integrate V1.9 start identity and one-query recovery in the App coordinator

**Files:**
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift:28-41,131-232,270-302,306-370,603-610`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh:1-205`

**Interfaces:**
- Consumes: SDK `WiFiGatewayDFUStartRequest` and `WiFiGatewayDFUStartResponse` from Tasks 1-2.
- Consumes: `WiFiFirmwareDFUStartRecovery` from Task 3.
- Produces: existing `.loadingStart`, `.updateState`, and session events; no ViewController API change.

- [ ] **Step 1: Strengthen the shell contract before implementation**

Replace the old metadata constructor assertion and add these exact checks:

```bash
rg -n 'let otaID = UInt64\.random\(in: 1\.\.\.UInt64\.max\)' "$coordinator" >/dev/null || fail "each user start must create a nonzero random ota ID"
rg -n 'WiFiGatewayDFUStartRequest\(' "$coordinator" >/dev/null || fail "coordinator must use the V1.9 typed start request"
rg -n 'otaID: otaID' "$coordinator" >/dev/null || fail "typed start request must carry the generated ota ID"
rg -n 'WiFiFirmwareDFUStartRecovery\(otaID: otaID, firmwareID: firmwareID\)' "$coordinator" >/dev/null || fail "pending recovery must bind ota ID and firmware ID before SET"
rg -n 'queryPendingStartStatusOnce' "$coordinator" >/dev/null || fail "missing one-shot status query after invalid RET"
rg -n 'case \.reserved:' "$coordinator" >/dev/null || fail "reserved start ret must use invalid-RET recovery"
if rg -n 'WiFiGatewayDFUMetadata\(' "$coordinator" >/dev/null; then
  fail "legacy start metadata API must not remain"
fi
start_send_count=$(grep -Fc 'SunricherVendorSet(function: .wifiGatewayDFUStart(request))' "$coordinator")
[ "$start_send_count" -eq 1 ] || fail "coordinator must contain exactly one 0x43/0x10 send site"
```

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL on the new ota ID/V1.9 request assertions.

- [ ] **Step 2: Replace pending start fields**

Replace:

```swift
private var pendingStartFirmwareID: String?
private var pendingStartReducer: WiFiFirmwareDFUStatusReducer?
```

with:

```swift
private var pendingStart: WiFiFirmwareDFUStartRecovery?
private var pendingStartQueryInFlight = false
```

Update `clearPendingStart()` to:

```swift
private func clearPendingStart() {
    pendingStart = nil
    pendingStartQueryInFlight = false
}
```

- [ ] **Step 3: Build and send the V1.9 request**

Replace the metadata creation section in `start(filename:version:)` with:

```swift
let request: WiFiGatewayDFUStartRequest
let firmwareID: String
let otaID = UInt64.random(in: 1...UInt64.max)
do {
    let url = try WiFiFirmwareDFUMetadataBuilder.makeURL(filename: filename)
    firmwareID = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: version)
    request = try WiFiGatewayDFUStartRequest(
        otaID: otaID,
        url: url,
        firmwareID: firmwareID
    )
} catch {
    emit(.loadingStart(false))
    emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
    return
}
```

Before sending, set:

```swift
pendingStart = WiFiFirmwareDFUStartRecovery(
    otaID: otaID,
    firmwareID: firmwareID
)
```

Send exactly once:

```swift
MeshAPI.sendMessage(
    message: SunricherVendorSet(function: .wifiGatewayDFUStart(request)),
    model: vendorModel,
    timeout: 10
) { [weak self] response in
    DispatchQueue.main.async {
        guard let self, self.isCurrent(requestGeneration) else { return }
        self.startRequestInFlight = false
        self.emit(.loadingStart(false))
        guard let status = response as? SunricherVendorStatus,
              case .wifiGatewayDFUStart(let startResponse) = status.status.parameters,
              startResponse.otaID == otaID else {
            self.resolveMissingStartRET()
            return
        }
        self.handleStartResponse(startResponse)
    }
}
```

- [ ] **Step 4: Handle defined and reserved RET separately**

Replace `handleStartResult` with:

```swift
private func handleStartResponse(_ response: WiFiGatewayDFUStartResponse) {
    switch response.result {
    case .accepted:
        establishPendingStart()
    case .internetUnavailable:
        clearPendingStart()
        emit(.updateState(.init(kind: .connFailedServerUnable, percent: 0)))
    case .invalidParameters, .busy, .internalError:
        clearPendingStart()
        emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
    case .reserved:
        resolveMissingStartRET()
    }
}
```

This guarantees `ret=0x03` ends the current request without query or resend, while reserved ret follows the invalid-RET recovery rule.

- [ ] **Step 5: Record only matching EVENT during pending start**

Replace the current `startRequestInFlight`/firmware-only EVENT branch with:

```swift
if var pending = pendingStart {
    let matched = pending.record(snapshot, source: .event)
    pendingStart = pending
    if matched, !startRequestInFlight, pendingStartQueryInFlight {
        establishPendingStart()
    }
    return
}
```

This branch deliberately ignores other ota IDs, other firmware IDs, and IDLE without passing them into an older session.

- [ ] **Step 6: Establish the session with the request ota ID immediately**

Add:

```swift
private func establishPendingStart() {
    guard let pending = pendingStart else { return }
    let pendingStatus = pending.reducer.lastAcceptedStatus
    reducer = pending.reducer
    let initialState = pendingStatus.flatMap(WiFiFirmwareDFUStateMapper.map)
        ?? .init(kind: .downloading, percent: 0)
    session = WiFiFirmwareDFUSession(
        targetFirmwareID: pending.firmwareID,
        otaID: pending.otaID,
        lastStatus: pendingStatus,
        lastState: initialState,
        terminalConsumed: false,
        requiresAuthoritativeQuery: false
    )
    clearPendingStart()
    lastValidStatusAt = Date().timeIntervalSince1970
    saveSession()
    emit(.updateState(initialState))

    if let pendingStatus {
        finishOrSchedule(after: pendingStatus)
    } else {
        queryDFUStatus(authoritative: false)
    }
}
```

New V1.9 sessions must never be created with `otaID=nil`. Keep the persisted property optional only so existing stored sessions remain decodable.

- [ ] **Step 7: Implement EVENT-first, one-query-only missing-RET recovery**

Add:

```swift
private func resolveMissingStartRET() {
    guard var pending = pendingStart else {
        finishUnknownStart()
        return
    }
    let decision = pending.nextAfterMissingRET()
    pendingStart = pending
    switch decision {
    case .established:
        establishPendingStart()
    case .queryOnce:
        queryPendingStartStatusOnce()
    case .unknown:
        finishUnknownStart()
    }
}

private func queryPendingStartStatusOnce() {
    guard isActive,
          !pendingStartQueryInFlight,
          let vendorModel = validVendorModel() else {
        finishUnknownStart()
        return
    }
    let requestGeneration = generation
    pendingStartQueryInFlight = true
    MeshAPI.sendMessage(
        message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
        model: vendorModel,
        timeout: WiFiFirmwareDFUQueryTiming.statusTimeout
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.pendingStartQueryInFlight = false
            guard self.pendingStart != nil else { return }
            if let response = response as? SunricherVendorStatus,
               case .wifiGatewayDFUStatus(.success(let value)) =
                response.status.parameters,
               var pending = self.pendingStart {
                _ = pending.record(
                    self.makeSnapshot(from: value),
                    source: .query
                )
                self.pendingStart = pending
            }
            self.resolveMissingStartRET()
        }
    }
}

private func finishUnknownStart() {
    clearPendingStart()
    emit(.updateState(.init(kind: .connFailedTimeout, percent: 0)))
}
```

Do not call `start` from any failure or recovery method. Do not schedule the normal 10/30-second status loop until `establishPendingStart()` creates a session.

- [ ] **Step 8: Lock the exact URL example and region behavior**

Keep `WiFiFirmwareDFUMetadataBuilder` unchanged. Add to the shell contract after its current source assertions:

```bash
expected_url='http://www.mericher.com/srv2/sitespace/ota/download?key=dev/20260514100245/OTA_Gateway_SS_0A78_0x2721_wifi_9036T-GW-54TA-PA-WIFI_v0.4.0_20260514.zip'
actual_url=$(swift -e 'import Foundation
let baseURL = URL(string: "https://www.mericher.com/srv2")!
let filename = "dev/20260514100245/OTA_Gateway_SS_0A78_0x2721_wifi_9036T-GW-54TA-PA-WIFI_v0.4.0_20260514.zip"
var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
components.scheme = "http"
components.path += "/sitespace/ota/download"
components.queryItems = [URLQueryItem(name: "key", value: filename)]
print(components.url!.absoluteString)')
[ "$actual_url" = "$expected_url" ] || fail "URL example does not match the confirmed contract"
```

Also retain the existing static checks for `UserData.currentServerRegion.baseURL`, `components.scheme = "http"`, fixed download path, and `URLQueryItem(name: "key", value: filename)`.

- [ ] **Step 9: Run App focused checks**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: `PASS: WiFi Gateway firmware update static checks`; diff check has no output.

- [ ] **Step 10: Commit the coordinator integration**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: start wifi dfu with v1.9 identity"
```

---

### Task 5: Run cross-repository verification and write the implementation summary

**Files:**
- Create: `docs/260720_1932_wifi_gateway_dfu_start_v19_implementation_summary.md`
- Verify unchanged: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUMetadataBuilder.swift`
- Verify unchanged: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Verify unchanged: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift`

**Interfaces:**
- Consumes: all SDK/App changes from Tasks 1-4.
- Produces: reproducible verification evidence and final scope summary.

- [ ] **Step 1: Re-run complete SDK focused tests**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
swift test --filter WiFiGatewayVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests
swift test --filter DebugUARTTests
git diff --check
git status --short
```

Expected: all selected tests PASS; diff check has no output; status contains only the intended SDK files or is clean after Task 2 commits.

- [ ] **Step 2: Re-run App focused and regression checks**

Run from the App worktree:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_menu_icons.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
```

Expected: every script prints PASS; plist reports OK; diff check has no output.

- [ ] **Step 3: Build all four iPhoneOS targets directly**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: each command ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Perform exact scope scans**

```bash
rg -n 'WiFiGatewayDFUMetadata|payloadLength = 5' /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift
rg -n 'sha256|firmwareSize' /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift
rg -n 'wifiGatewayDFUCancel|wifiDFUCancel' SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift
rg -n -A3 'case \.wifiGatewayDFUStart:' /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift
rg -n 'wifiGatewayDFUStart' SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift
```

Expected:

- No legacy metadata type, old start length formula, or 3-byte start RET guard.
- No start payload `sha256`/size or cancel implementation.
- Exactly one App send site for `wifiGatewayDFUStart`; other matches are typed response handling only.

- [ ] **Step 5: Write the implementation summary**

Create `docs/260720_1932_wifi_gateway_dfu_start_v19_implementation_summary.md` with this exact structure after all preceding commands produce the expected successful results:

```markdown
# WiFi Gateway DFU Start V1.9 实施总结

## 完成内容

- URL 继续按当前区域 HTTP host、固定 download path 和 body.filename 构造。
- SDK start request 已加入非零 UInt64 LE ota ID，并按 V1.9 校验长度和字符。
- SDK start RET 已切换为精确 11 字节，并按请求 ota ID 关联。
- App 每次明确用户操作生成新 ota ID；无有效 RET 时先认匹配 EVENT，否则只查询一次状态。
- 无法确认时展示通信超时和 UPGRADE AGAIN，不继续查询，不自动重发。

## 范围保持

- 未实现 0x43/0x15 cancel。
- 未修改 0x43/0x11 V1.9 状态布局。
- 未修改 BLE/Mesh firmware update 流程或 WiFi firmware 页面布局。

## 验证证据

- SDK focused tests：`WiFiGatewayVendorMessageTests`、`MeshMessageHandleResponseMatchingTests`、`DebugUARTTests` 全部通过。
- App focused/regression scripts：WiFi firmware、menu、network connectivity、WiFi header、SIG Mesh header contracts 全部通过。
- 四个 generic iPhoneOS builds：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 均为 `BUILD SUCCEEDED`。
- `git diff --check`：App 与 SDK repositories 均无 whitespace error。
```

- [ ] **Step 6: Commit the summary and perform final status review**

```bash
git add docs/260720_1921_wifi_gateway_dfu_start_v19_requirement_analysis.md docs/260720_1932_wifi_gateway_dfu_start_v19_implementation_summary.md docs/superpowers/plans/260720_1932_wifi_gateway_dfu_start_v19_implementation_plan.md
git commit -m "docs: summarize wifi dfu start v1.9"
git status --short
git log -6 --oneline
```

Expected: App worktree is clean after the documentation commit; recent history shows the recovery model, coordinator integration, and summary commits. If unrelated user changes exist, leave them unstaged and report them instead of forcing a clean status.

## Execution Handoff

The confirmed execution mode is **Inline Execution**. Use `superpowers:executing-plans` in the current session, execute Tasks 1-5 in order, and pause for a checkpoint after each SDK/App repository commit boundary. Do not dispatch subagents.
