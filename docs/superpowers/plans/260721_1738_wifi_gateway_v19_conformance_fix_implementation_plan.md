# WiFi Gateway V1.9 Conformance Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly requests subagent-driven execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本地 NordicSigMeshSDK 与 SunSmart App 严格符合用户确认的 WiFi Gateway V1.9 P0/P1 行为，并用 focused tests、静态契约及五个 generic iPhoneOS build 收口。

**Architecture:** 先收紧 SDK wire truth，再建立 App 纯状态 reducer，最后让现有 ViewController/Coordinator 只负责编排 Mesh 请求与 UI。`0x0F` 严格只接受 5-byte RET；凭据 mutation recovery、连接轮询和 Cancel transport gate 分别拥有独立、可 standalone 编译的状态模型。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、XCTest、standalone `swiftc` contracts、CocoaPods workspace、`xcodebuild`。

## Global Constraints

- 权威协议：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/WiFi Gateway V1.9.md`。
- 权威设计：`docs/superpowers/specs/260721_1734_wifi_gateway_v19_conformance_fix_design.md`。
- App worktree：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway`。
- SDK worktree：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- `0x0F` 只接受 V1.9 5-byte RET，不保留旧 4-byte compatibility。
- RSSI polling 保持 completion 后 5 秒；单次 `0x0F` request deadline 改为 4 秒。
- `0x0D`、`0x13` 不确定结果最多查询一次 `0x12`，不得自动重发 SET。
- `0x10` 与 `0x11` 单次 request deadline 均为 3 秒；其余 Subcode 使用 Task 3 的完整 V1.9 timing table。
- 所有新增用户可见文案同步 English 与 `zh-Hans`，不得硬编码。
- 新 App Swift 文件加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不修改 HTTP OTA、密码存储策略、capability 协商、普通 transaction ID 或其它 Gateway 行为。
- 不新增 Auth 信息，不顺手重构，不格式化无关文件。
- iOS 构建直接运行 `xcodebuild`，使用 `iphoneos` generic destination，不使用 Simulator、shell wrapper 或日志重定向。
- 每个任务只 stage 本任务列出的文件，不得 stage `docs/260721_1658_wifi_gateway_v19_protocol_conformance_analysis.md`。

---

## Task 1: 收紧 SDK Wi-Fi 凭据与结果语义

**Files:**

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

**Interfaces:**

- Produces: `WiFiGatewayV19TextValidator.firstForbiddenCredentialScalar(in:) -> UInt32?`。
- Produces: `WiFiGatewayV19TextValidator.firstInvalidIdentifierByte(in:) -> UInt8?`。
- Produces: `WiFiGatewayV19TextValidator.isValidIdentifierBytes(_:) -> Bool`，Task 2 复用。
- Produces: `WiFiGatewayCredentials.ssidData`、`passwordData` 与 raw-byte `Equatable`。
- Produces: `.unconfirmed` typed cases和 `WiFiGatewayConnectionStatus.requestFormatError`。

- [ ] **Step 1: 在 SDK XCTest 中写凭据 V1.9 RED tests**

在 `WiFiGatewayVendorMessageTests` 增加以下测试方法；协议 12.1 示例必须直接断言完整 payload：

```swift
func testCredentialsV19MultilingualExampleRoundTrip() throws {
    let credentials = try WiFiGatewayCredentials(
        ssid: "中文WiFi",
        password: "密码,PA\"ss"
    )
    let expectedSet = Data([
        0x43, 0x0D, 0x0A,
        0xE4, 0xB8, 0xAD, 0xE6, 0x96, 0x87, 0x57, 0x69, 0x46, 0x69,
        0x0C,
        0xE5, 0xAF, 0x86, 0xE7, 0xA0, 0x81, 0x2C, 0x50, 0x41, 0x22, 0x73, 0x73
    ])
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)).parameters,
        expectedSet
    )

    let readPayload = Data([0x43, 0x12, 0x00]) + expectedSet.dropFirst(2)
    guard case .wifiGatewayCredentialsRead(.success(let decoded)) =
            SunricherVendorStatus(parameters: readPayload)?.status.parameters else {
        return XCTFail("Expected V1.9 multilingual credentials")
    }
    XCTAssertEqual(decoded, credentials)
    XCTAssertEqual(decoded.ssidData, credentials.ssidData)
    XCTAssertEqual(decoded.passwordData, credentials.passwordData)
}

func testCredentialV19ByteLengthsAndCharacters() throws {
    XCTAssertNoThrow(
        try WiFiGatewayCredentials(ssid: String(repeating: "A", count: 32), password: nil)
    )
    XCTAssertThrowsError(
        try WiFiGatewayCredentials(ssid: String(repeating: "A", count: 33), password: nil)
    )
    XCTAssertNoThrow(
        try WiFiGatewayCredentials(ssid: "A,\"\\B", password: "密码,\"\\abcd")
    )
    XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "Bad\nName", password: nil))
    XCTAssertThrowsError(try WiFiGatewayCredentials(ssid: "Bad\u{0085}Name", password: nil))
}

func testCredentialEqualityUsesOriginalUTF8Bytes() throws {
    let composed = try WiFiGatewayCredentials(ssid: "é", password: nil)
    let decomposed = try WiFiGatewayCredentials(ssid: "e\u{301}", password: nil)
    XCTAssertNotEqual(composed.ssidData, decomposed.ssidData)
    XCTAssertNotEqual(composed, decomposed)
}

func testV19TypedUnconfirmedAndRequestFormatErrorNames() {
    assertCredentialsSet(
        Data([0x43, 0x0D, 0x02]),
        expected: .unconfirmed,
        isSuccessful: false,
        errorCode: 0x02
    )
    assertCredentialsRead(
        Data([0x43, 0x12, 0x02]),
        expected: .unconfirmed,
        isSuccessful: false,
        errorCode: 0x02
    )
    assertCredentialsClear(
        Data([0x43, 0x13, 0x02]),
        expected: .unconfirmed,
        isSuccessful: false,
        errorCode: 0x02
    )
    assertConnectionStatus(
        Data([0x43, 0x0E, 0x06]),
        expected: .requestFormatError,
        isSuccessful: false,
        errorCode: 0x06
    )
}
```

同时删除或反转当前“32-byte SSID、双引号、反斜杠必须失败”的旧断言。

- [ ] **Step 2: 运行 RED tests，确认失败原因来自旧规则/旧 case 名**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: 新测试因 32-byte/Unicode 凭据被拒绝、缺少 `.unconfirmed`、`.requestFormatError` 或 byte data API 而 FAIL。若 SwiftPM 在编译测试前被仓库既有 UIKit import 阻塞，保留原始错误，并在 Step 4 使用 App iPhoneOS build 与后续 standalone contracts验证。

- [ ] **Step 3: 新增共享文本 validator**

创建 `WiFiGatewayV19TextValidator.swift`：

```swift
import Foundation

enum WiFiGatewayV19TextValidator {
    static func firstForbiddenCredentialScalar(in value: String) -> UInt32? {
        value.unicodeScalars.lazy
            .map(\.value)
            .first { scalar in
                scalar <= 0x1F || (0x7F...0x9F).contains(scalar)
            }
    }

    static func isValidIdentifierBytes(_ bytes: [UInt8]) -> Bool {
        firstInvalidIdentifierByte(in: bytes) == nil
    }

    static func firstInvalidIdentifierByte(in bytes: [UInt8]) -> UInt8? {
        bytes.first {
            !(0x20...0x7E).contains($0) ||
                $0 == 0x22 ||
                $0 == 0x2C ||
                $0 == 0x5C
        }
    }
}
```

- [ ] **Step 4: 修改 `WiFiGatewayCredentials` 与 typed enums**

在 `SunricherVendorStatus.swift` 中：

1. 把 credential validation error 改为：

```swift
public enum WiFiGatewayCredentialValidationError: Error, Equatable {
    case invalidSSIDLength(Int)
    case invalidPasswordLength(Int)
    case invalidControlCharacter(field: WiFiGatewayCredentialField, scalarValue: UInt32)
}
```

2. 让两个 initializer 都先取得/解码 String，再调用以下 validator：

```swift
private static func validate(
    ssid: String,
    password: String?,
    ssidBytes: [UInt8],
    passwordBytes: [UInt8]
) throws {
    guard (1...32).contains(ssidBytes.count) else {
        throw WiFiGatewayCredentialValidationError.invalidSSIDLength(ssidBytes.count)
    }
    guard passwordBytes.isEmpty || (8...63).contains(passwordBytes.count) else {
        throw WiFiGatewayCredentialValidationError.invalidPasswordLength(passwordBytes.count)
    }
    if let scalar = WiFiGatewayV19TextValidator.firstForbiddenCredentialScalar(in: ssid) {
        throw WiFiGatewayCredentialValidationError.invalidControlCharacter(
            field: .ssid,
            scalarValue: scalar
        )
    }
    if let password,
       let scalar = WiFiGatewayV19TextValidator.firstForbiddenCredentialScalar(in: password) {
        throw WiFiGatewayCredentialValidationError.invalidControlCharacter(
            field: .password,
            scalarValue: scalar
        )
    }
}
```

3. 暴露 immutable wire bytes 并显式定义 equality：

```swift
public var ssidData: Data { Data(ssidBytes) }
public var passwordData: Data { Data(passwordBytes) }

public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.ssidBytes == rhs.ssidBytes && lhs.passwordBytes == rhs.passwordBytes
}
```

4. 把三个 `0x02` case 改名为 `.unconfirmed`；给 `WiFiGatewayConnectionStatus` 增加：

```swift
case requestFormatError
```

并在 raw-value initializer 中让 `0x06` 映射到该 case。

- [ ] **Step 5: 运行 SDK focused test**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: `WiFiGatewayVendorMessageTests` PASS；若只存在既有 UIKit 环境阻塞，输出必须与 Step 2 记录一致，不能出现本任务新增 Swift 编译错误。

- [ ] **Step 6: 检查 SDK diff 并提交**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
git diff --check
git diff -- Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "fix: align wifi gateway credential semantics with v1.9"
```

Expected: 只提交上述 SDK files。

## Task 2: 严格实现 SDK `0x0F` 与共享 identifier validator

**Files:**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStart.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**

- Consumes: `WiFiGatewayV19TextValidator.isValidIdentifierBytes(_:)` from Task 1。
- Produces: `WiFiGatewayRSSIResult` 与组合型 `WiFiGatewayRSSIStatus`。
- Removes: `WiFiGatewayNetworkStatus.notReported` 和 4-byte `0x0F` parsing。

- [ ] **Step 1: 把 `0x0F` 与 identifier 边界改成 RED tests**

用以下断言替换当前 4-byte compatibility 和 `rssi=0` 成功断言：

```swift
func testRSSIStatusV19KeepsIndependentInternetState() {
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x01, 0x00, 0x00]),
        expected: .init(rssiResult: .unavailable, networkStatus: .normal),
        isSuccessful: false,
        errorCode: 0x01
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x02, 0x00, 0x01]),
        expected: .init(rssiResult: .readFailed, networkStatus: .unavailable),
        isSuccessful: false,
        errorCode: 0x02
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x7F, 0x00, 0x7F]),
        expected: .init(
            rssiResult: .reserved(rawValue: 0x7F),
            networkStatus: .reserved(rawValue: 0x7F)
        ),
        isSuccessful: false,
        errorCode: 0x7F
    )
}

func testRSSIStatusV19RejectsLegacyAndInvalidFieldCombinations() {
    let invalid = [
        Data([0x43, 0x0F, 0x00, 0xBF]),
        Data([0x43, 0x0F, 0x00, 0x00, 0x00]),
        Data([0x43, 0x0F, 0x01, 0xFF, 0x00]),
        Data([0x43, 0x0F, 0x02, 0x00, 0x02, 0x00])
    ]
    for payload in invalid {
        XCTAssertNil(SunricherVendorStatus(parameters: payload)?.status.parameters)
    }
}

func testV19IdentifiersRejectQuoteCommaAndBackslash() {
    for value in ["bad\"id", "bad,id", "bad\\id"] {
        let versionPayload = Data([0x43, 0x14, 0x00, UInt8(value.utf8.count)]) + Data(value.utf8)
        XCTAssertNil(SunricherVendorStatus(parameters: versionPayload)?.status.parameters)
        XCTAssertNil(
            SunricherVendorStatus(
                parameters: makeDFUStatusPayload(
                    stage: 0x01,
                    percent: 10,
                    code: 0,
                    firmwareID: value
                )
            )?.status.parameters
        )
    }
}
```

- [ ] **Step 2: 运行 RED test**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
```

Expected: legacy 4-byte、RSSI zero、缺失 Internet status 或逗号/反斜杠 identifier 至少一项 FAIL；既有 UIKit blocker 按 Task 1 同一规则记录。

- [ ] **Step 3: 实现组合型 RSSI model 和严格 5-byte parser**

把 SDK model 改为：

```swift
public enum WiFiGatewayRSSIResult: Equatable {
    case valid(dbm: Int8)
    case unavailable
    case readFailed
    case reserved(rawValue: UInt8)
}

public struct WiFiGatewayRSSIStatus: Equatable {
    public let rssiResult: WiFiGatewayRSSIResult
    public let networkStatus: WiFiGatewayNetworkStatus

    public init(
        rssiResult: WiFiGatewayRSSIResult,
        networkStatus: WiFiGatewayNetworkStatus
    ) {
        self.rssiResult = rssiResult
        self.networkStatus = networkStatus
    }
}
```

`wifiGatewayRSSIStatusGet` parser 使用以下完整逻辑：

```swift
guard data.count == 5 else { return nil }
let networkStatus = WiFiGatewayNetworkStatus(rawValue: data[4])
let rssiResult: WiFiGatewayRSSIResult
switch status {
case 0x00:
    let rssi = Int8(bitPattern: data[3])
    guard (-127 ... -1).contains(rssi) else { return nil }
    rssiResult = .valid(dbm: rssi)
case 0x01:
    guard data[3] == 0 else { return nil }
    rssiResult = .unavailable
case 0x02:
    guard data[3] == 0 else { return nil }
    rssiResult = .readFailed
default:
    guard data[3] == 0 else { return nil }
    rssiResult = .reserved(rawValue: status)
}
return .wifiGatewayRSSIStatus(
    .init(rssiResult: rssiResult, networkStatus: networkStatus)
)
```

从 `WiFiGatewayNetworkStatus` 删除 `.notReported`。

- [ ] **Step 4: 让 `0x10/0x11/0x14` 复用 identifier validator**

- `WiFiGatewayDFUStart.validateFirmwareID` 调用 `WiFiGatewayV19TextValidator.firstInvalidIdentifierByte(in:)`，用返回 byte 构造当前 field-specific error。
- `WiFiGatewayDFUStatusParser` 删除 private `validIdentifier`，两个 byte array 都调用共享 validator。
- `wifiGatewayFirmwareVersionParameters` 在 `1...32` 长度检查后调用共享 validator；失败返回 nil。

关键 replacement：

```swift
guard WiFiGatewayV19TextValidator.isValidIdentifierBytes(firmwareBytes),
      WiFiGatewayV19TextValidator.isValidIdentifierBytes(versionBytes) else {
    return nil
}
```

- [ ] **Step 5: 更新 App 侧 standalone SDK contract 编译依赖**

在 `scripts/check_wifi_gateway_firmware_update.sh` 增加 validator path，并让 Start/Status contract 的 `swiftc` 命令同时编译它：

```bash
sdk_text_validator="$sdk_source/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift"

swiftc -parse-as-library "$sdk_text_validator" "$sdk_status" "$sdk_contract" -o /tmp/WiFiGatewayDFUStatusV19Contract
swiftc -parse-as-library "$sdk_text_validator" "$sdk_start" "$sdk_start_contract" -o /tmp/WiFiGatewayDFUStartV19Contract
```

- [ ] **Step 6: 运行 GREEN tests/contracts**

Run:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: SDK focused tests PASS，或只有已记录 UIKit blocker；firmware standalone contracts PASS。

- [ ] **Step 7: 分仓提交**

SDK:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
git diff --check
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStart.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "fix: enforce wifi gateway v1.9 status parsing"
```

App:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/wifi-gateway
git add scripts/check_wifi_gateway_firmware_update.sh
git commit -m "test: compile shared wifi gateway v1.9 validator"
```

## Task 3: 建立 App 唯一 V1.9 timing truth

**Files:**

- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift`
- Create: `Tests/Device/WiFiGatewayV19TimingTests.swift`
- Modify: `scripts/check_wifi_gateway_network_connectivity.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `WiFiGatewayV19Subcode`。
- Produces: `WiFiGatewayV19Timing.responseTimeout(for:)`、`connectionPollInterval`、`connectionPollWindow`、`rssiPollDelay`。

- [ ] **Step 1: 创建 timing RED test**

```swift
import Foundation

@main
struct WiFiGatewayV19TimingTests {
    static func main() {
        let expected: [(WiFiGatewayV19Subcode, TimeInterval)] = [
            (.credentialsSet, 7),
            (.connectionStatus, 3),
            (.rssiStatus, 4),
            (.dfuStart, 3),
            (.dfuStatus, 3),
            (.credentialsRead, 7),
            (.credentialsClear, 7),
            (.firmwareVersion, 7),
            (.dfuCancel, 7)
        ]
        for (subcode, timeout) in expected {
            precondition(WiFiGatewayV19Timing.responseTimeout(for: subcode) == timeout)
        }
        precondition(WiFiGatewayV19Timing.connectionPollInterval == 5)
        precondition(WiFiGatewayV19Timing.connectionPollWindow == 65)
        precondition(WiFiGatewayV19Timing.rssiPollDelay == 5)
        print("WiFiGatewayV19TimingTests passed")
    }
}
```

- [ ] **Step 2: 在 network contract 中加入 RED compile/run**

在脚本顶部定义：

```bash
timing="SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift"
timing_test="Tests/Device/WiFiGatewayV19TimingTests.swift"
```

在成功输出前加入：

```bash
swiftc -parse-as-library "$timing" "$timing_test" -o /tmp/WiFiGatewayV19TimingTests
/tmp/WiFiGatewayV19TimingTests
```

Run:

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
```

Expected: FAIL because timing source file does not exist。

- [ ] **Step 3: 创建完整 timing source**

```swift
import Foundation

enum WiFiGatewayV19Subcode: UInt8, CaseIterable {
    case credentialsSet = 0x0D
    case connectionStatus = 0x0E
    case rssiStatus = 0x0F
    case dfuStart = 0x10
    case dfuStatus = 0x11
    case credentialsRead = 0x12
    case credentialsClear = 0x13
    case firmwareVersion = 0x14
    case dfuCancel = 0x15
}

enum WiFiGatewayV19Timing {
    static let connectionPollInterval: TimeInterval = 5
    static let connectionPollWindow: TimeInterval = 65
    static let rssiPollDelay: TimeInterval = 5

    static func responseTimeout(for subcode: WiFiGatewayV19Subcode) -> TimeInterval {
        switch subcode {
        case .connectionStatus, .dfuStart, .dfuStatus:
            return 3
        case .rssiStatus:
            return 4
        case .credentialsSet, .credentialsRead, .credentialsClear,
             .firmwareVersion, .dfuCancel:
            return 7
        }
    }
}
```

- [ ] **Step 4: 把 timing source 加入四个 App target**

在 `SunSmart.xcodeproj/project.pbxproj` 中参照 `WiFiGatewayTimeSyncCoordinator.swift`：新增一个 file reference、四个 build-file references，将文件加入 Gateway `Model` group，并分别加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` Sources phase。完成后 `rg -c 'WiFiGatewayV19Timing.swift' SunSmart.xcodeproj/project.pbxproj` 必须输出 `10`。

- [ ] **Step 5: 运行 GREEN contract 并提交**

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
git diff --check
git add SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift Tests/Device/WiFiGatewayV19TimingTests.swift scripts/check_wifi_gateway_network_connectivity.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "test: define wifi gateway v1.9 timing"
```

Expected: timing test 与原 network contract PASS。

## Task 4: 建立凭据 mutation recovery reducer

**Files:**

- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayCredentialMutationReducer.swift`
- Create: `Tests/Device/WiFiGatewayCredentialMutationReducerTests.swift`
- Modify: `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `WiFiGatewayCredentialSnapshot`，使用 `Data` 保证 byte equality。
- Produces: `WiFiGatewayCredentialMutationReducer.reduce(_:) -> WiFiGatewayCredentialMutationAction`。
- Consumed by: Task 6 `WiFiGatewayViewController`。

- [ ] **Step 1: 创建完整 RED reducer test**

```swift
import Foundation

@main
struct WiFiGatewayCredentialMutationReducerTests {
    static let old = WiFiGatewayCredentialSnapshot(
        ssid: Data("old".utf8),
        password: Data("password".utf8)
    )
    static let target = WiFiGatewayCredentialSnapshot(
        ssid: Data("中文WiFi".utf8),
        password: Data("密码,PA\"ss".utf8)
    )

    static func main() {
        testSetConfirmed()
        testSetRecoveryReached()
        testSetRecoveryNotReachedAndUnknown()
        testClearConfirmedAndRecovery()
        testDuplicateInputsNeverResend()
        print("WiFiGatewayCredentialMutationReducerTests passed")
    }

    static func testSetConfirmed() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        precondition(reducer.reduce(.start(.set(target: target))) == .sendSet(target))
        precondition(reducer.reduce(.mutationResponse(.confirmed)) == .setTargetReached)
    }

    static func testSetRecoveryReached() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        _ = reducer.reduce(.start(.set(target: target)))
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(
            reducer.reduce(.recoveryResponse(.credentials(target))) == .setTargetReached
        )
    }

    static func testSetRecoveryNotReachedAndUnknown() {
        var notReached = WiFiGatewayCredentialMutationReducer()
        _ = notReached.reduce(.start(.set(target: target)))
        _ = notReached.reduce(.mutationResponse(.unconfirmed))
        precondition(
            notReached.reduce(.recoveryResponse(.credentials(old))) == .setTargetNotReached
        )

        var unknown = WiFiGatewayCredentialMutationReducer()
        _ = unknown.reduce(.start(.set(target: target)))
        _ = unknown.reduce(.mutationResponse(.unconfirmed))
        precondition(unknown.reduce(.recoveryResponse(.unconfirmed)) == .setTargetUnknown)
    }

    static func testClearConfirmedAndRecovery() {
        var confirmed = WiFiGatewayCredentialMutationReducer()
        precondition(confirmed.reduce(.start(.clear(previous: old))) == .sendClear)
        precondition(confirmed.reduce(.mutationResponse(.confirmed)) == .clearTargetReached)

        var reached = WiFiGatewayCredentialMutationReducer()
        _ = reached.reduce(.start(.clear(previous: old)))
        precondition(reached.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(reached.reduce(.recoveryResponse(.notConfigured)) == .clearTargetReached)

        var notReached = WiFiGatewayCredentialMutationReducer()
        _ = notReached.reduce(.start(.clear(previous: old)))
        _ = notReached.reduce(.mutationResponse(.unconfirmed))
        precondition(
            notReached.reduce(.recoveryResponse(.credentials(old))) ==
                .clearTargetNotReached(old)
        )
    }

    static func testDuplicateInputsNeverResend() {
        var reducer = WiFiGatewayCredentialMutationReducer()
        precondition(reducer.reduce(.start(.set(target: target))) == .sendSet(target))
        precondition(reducer.reduce(.start(.set(target: target))) == .none)
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .requestCredentials)
        precondition(reducer.reduce(.mutationResponse(.unconfirmed)) == .none)
        precondition(reducer.reduce(.recoveryResponse(.unconfirmed)) == .setTargetUnknown)
        precondition(reducer.reduce(.recoveryResponse(.unconfirmed)) == .none)
    }
}
```

- [ ] **Step 2: 把 test 接入 clear contract 并确认 RED**

在脚本中加入：

```bash
mutation_reducer="SunSmart/Main/Device/Gateway/Model/WiFiGatewayCredentialMutationReducer.swift"
mutation_test="Tests/Device/WiFiGatewayCredentialMutationReducerTests.swift"
swiftc -parse-as-library "$mutation_reducer" "$mutation_test" -o /tmp/WiFiGatewayCredentialMutationReducerTests
/tmp/WiFiGatewayCredentialMutationReducerTests
```

Run: `bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh`

Expected: FAIL because reducer source does not exist。

- [ ] **Step 3: 创建完整 reducer source**

```swift
import Foundation

struct WiFiGatewayCredentialSnapshot: Equatable {
    let ssid: Data
    let password: Data
}

enum WiFiGatewayCredentialMutationOperation: Equatable {
    case set(target: WiFiGatewayCredentialSnapshot)
    case clear(previous: WiFiGatewayCredentialSnapshot)
}

enum WiFiGatewayCredentialMutationResponse: Equatable {
    case confirmed
    case invalidParameters
    case unconfirmed
}

enum WiFiGatewayCredentialReadObservation: Equatable {
    case credentials(WiFiGatewayCredentialSnapshot)
    case notConfigured
    case unconfirmed
}

enum WiFiGatewayCredentialMutationInput: Equatable {
    case start(WiFiGatewayCredentialMutationOperation)
    case mutationResponse(WiFiGatewayCredentialMutationResponse)
    case recoveryResponse(WiFiGatewayCredentialReadObservation)
}

enum WiFiGatewayCredentialMutationAction: Equatable {
    case none
    case sendSet(WiFiGatewayCredentialSnapshot)
    case sendClear
    case requestCredentials
    case setTargetReached
    case setTargetNotReached
    case setTargetUnknown
    case clearTargetReached
    case clearTargetNotReached(WiFiGatewayCredentialSnapshot)
    case clearTargetUnknown
}

struct WiFiGatewayCredentialMutationReducer {
    private enum Phase: Equatable {
        case idle
        case waitingMutation(WiFiGatewayCredentialMutationOperation)
        case waitingRecovery(WiFiGatewayCredentialMutationOperation)
        case finished
    }

    private var phase: Phase = .idle

    mutating func reduce(
        _ input: WiFiGatewayCredentialMutationInput
    ) -> WiFiGatewayCredentialMutationAction {
        switch (phase, input) {
        case (.idle, .start(let operation)):
            phase = .waitingMutation(operation)
            switch operation {
            case .set(let target): return .sendSet(target)
            case .clear: return .sendClear
            }

        case (.waitingMutation(let operation), .mutationResponse(.confirmed)):
            phase = .finished
            switch operation {
            case .set: return .setTargetReached
            case .clear: return .clearTargetReached
            }

        case (.waitingMutation(let operation), .mutationResponse(.invalidParameters)):
            phase = .finished
            switch operation {
            case .set: return .setTargetNotReached
            case .clear(let previous): return .clearTargetNotReached(previous)
            }

        case (.waitingMutation(let operation), .mutationResponse(.unconfirmed)):
            phase = .waitingRecovery(operation)
            return .requestCredentials

        case (.waitingRecovery(.set(let target)), .recoveryResponse(.credentials(let value))):
            phase = .finished
            return value == target ? .setTargetReached : .setTargetNotReached

        case (.waitingRecovery(.set), .recoveryResponse(.notConfigured)):
            phase = .finished
            return .setTargetNotReached

        case (.waitingRecovery(.set), .recoveryResponse(.unconfirmed)):
            phase = .finished
            return .setTargetUnknown

        case (.waitingRecovery(.clear), .recoveryResponse(.notConfigured)):
            phase = .finished
            return .clearTargetReached

        case (.waitingRecovery(.clear), .recoveryResponse(.credentials(let value))):
            phase = .finished
            return .clearTargetNotReached(value)

        case (.waitingRecovery(.clear), .recoveryResponse(.unconfirmed)):
            phase = .finished
            return .clearTargetUnknown

        default:
            return .none
        }
    }
}
```

- [ ] **Step 4: 把 mutation reducer 加入四个 App target**

参照 Task 3 的 target wiring，将 `WiFiGatewayCredentialMutationReducer.swift` 加入 Gateway `Model` group 与四个 Sources phase。`rg -c 'WiFiGatewayCredentialMutationReducer.swift' SunSmart.xcodeproj/project.pbxproj` 必须输出 `10`。

- [ ] **Step 5: 运行 GREEN test 并提交**

```bash
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
git diff --check
git add SunSmart/Main/Device/Gateway/Model/WiFiGatewayCredentialMutationReducer.swift Tests/Device/WiFiGatewayCredentialMutationReducerTests.swift scripts/check_wifi_gateway_disconnect_clear_credentials.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "test: model wifi credential mutation recovery"
```

## Task 5: 建立 `0x0E` completion-driven polling reducer

**Files:**

- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayConnectionPollingReducer.swift`
- Create: `Tests/Device/WiFiGatewayConnectionPollingReducerTests.swift`
- Modify: `scripts/check_wifi_gateway_network_connectivity.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `WiFiGatewayV19Timing.connectionPollInterval/window`。
- Produces: `start(now:)`、`receive(_:now:)`、`timerFired(now:)`。
- Consumed by: Task 6 controller integration。

- [ ] **Step 1: 创建完整 polling RED test**

```swift
import Foundation

@main
struct WiFiGatewayConnectionPollingReducerTests {
    static func main() {
        testImmediateThenFiveSecondPolling()
        testSixtyFiveSecondBoundary()
        testFormatErrorAndTimeoutPreserveFlow()
        testTerminalResultsStopPolling()
        print("WiFiGatewayConnectionPollingReducerTests passed")
    }

    static func testImmediateThenFiveSecondPolling() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        precondition(reducer.start(now: 100) == .sendQuery)
        precondition(reducer.receive(.connecting, now: 102) == .schedule(after: 5))
        precondition(reducer.timerFired(now: 107) == .sendQuery)
    }

    static func testSixtyFiveSecondBoundary() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        _ = reducer.start(now: 0)
        precondition(reducer.receive(.connecting, now: 64) == .schedule(after: 1))
        precondition(reducer.timerFired(now: 65) == .timedOut)
        precondition(reducer.timerFired(now: 66) == .none)
    }

    static func testFormatErrorAndTimeoutPreserveFlow() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        _ = reducer.start(now: 0)
        precondition(reducer.receive(.requestFormatError, now: 1) == .schedule(after: 5))
        precondition(reducer.timerFired(now: 6) == .sendQuery)
        precondition(reducer.receive(.noValidResult, now: 9) == .schedule(after: 5))
    }

    static func testTerminalResultsStopPolling() {
        let values: [(WiFiGatewayConnectionPollingObservation, WiFiGatewayConnectionPollingAction)] = [
            (.connected, .connected),
            (.passwordError, .failed),
            (.failed, .failed),
            (.notConfigured, .notConfigured),
            (.reserved, .failed)
        ]
        for (observation, expected) in values {
            var reducer = WiFiGatewayConnectionPollingReducer()
            _ = reducer.start(now: 0)
            precondition(reducer.receive(observation, now: 1) == expected)
            precondition(reducer.timerFired(now: 2) == .none)
        }
    }
}
```

- [ ] **Step 2: 接入 contract 并确认 RED**

向 network script 增加 source/test paths 和 `swiftc -parse-as-library` 命令，同时编译 Task 3 timing source。

Run: `bash scripts/check_wifi_gateway_network_connectivity.sh`

Expected: FAIL because polling reducer source does not exist。

- [ ] **Step 3: 创建完整 polling reducer**

```swift
import Foundation

enum WiFiGatewayConnectionPollingObservation: Equatable {
    case connecting
    case connected
    case passwordError
    case failed
    case notConfigured
    case requestFormatError
    case reserved
    case noValidResult
}

enum WiFiGatewayConnectionPollingAction: Equatable {
    case none
    case sendQuery
    case schedule(after: TimeInterval)
    case connected
    case failed
    case notConfigured
    case timedOut
}

struct WiFiGatewayConnectionPollingReducer {
    private enum Phase: Equatable {
        case idle
        case active(deadline: TimeInterval)
        case finished
    }

    private var phase: Phase = .idle

    mutating func start(now: TimeInterval) -> WiFiGatewayConnectionPollingAction {
        guard phase == .idle else { return .none }
        phase = .active(deadline: now + WiFiGatewayV19Timing.connectionPollWindow)
        return .sendQuery
    }

    mutating func receive(
        _ observation: WiFiGatewayConnectionPollingObservation,
        now: TimeInterval
    ) -> WiFiGatewayConnectionPollingAction {
        guard case .active(let deadline) = phase else { return .none }
        switch observation {
        case .connected:
            phase = .finished
            return .connected
        case .passwordError, .failed, .reserved:
            phase = .finished
            return .failed
        case .notConfigured:
            phase = .finished
            return .notConfigured
        case .connecting, .requestFormatError, .noValidResult:
            guard now < deadline else {
                phase = .finished
                return .timedOut
            }
            return .schedule(
                after: min(WiFiGatewayV19Timing.connectionPollInterval, deadline - now)
            )
        }
    }

    mutating func timerFired(now: TimeInterval) -> WiFiGatewayConnectionPollingAction {
        guard case .active(let deadline) = phase else { return .none }
        guard now < deadline else {
            phase = .finished
            return .timedOut
        }
        return .sendQuery
    }
}
```

- [ ] **Step 4: 把 polling reducer 加入四个 App target**

将 `WiFiGatewayConnectionPollingReducer.swift` 加入 Gateway `Model` group 与四个 Sources phase。`rg -c 'WiFiGatewayConnectionPollingReducer.swift' SunSmart.xcodeproj/project.pbxproj` 必须输出 `10`。

- [ ] **Step 5: 运行 GREEN contract 并提交**

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
git diff --check
git add SunSmart/Main/Device/Gateway/Model/WiFiGatewayConnectionPollingReducer.swift Tests/Device/WiFiGatewayConnectionPollingReducerTests.swift scripts/check_wifi_gateway_network_connectivity.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "test: model wifi gateway connection polling"
```

## Task 6: 把 SDK typed model、deadline 和 Wi-Fi reducers 接入页面

**Files:**

- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `scripts/check_wifi_gateway_network_connectivity.sh`
- Modify: `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- Modify: `scripts/check_wifi_gateway_wifi_status_header.sh`

**Interfaces:**

- Consumes: Task 1/2 SDK typed APIs。
- Consumes: Tasks 3/4/5 App pure models。
- Produces: controller action drivers，且所有 Mesh request 使用 exact Subcode deadline。

- [ ] **Step 1: 先收紧三个静态 contract 形成 RED**

更新检查目标：

- network script 不再要求 `UserDefaults` 以外的新安全变更；增加 exact Subcode timeout symbols、one-shot 5 秒/65 秒 polling、`.requestFormatError` 保持状态检查。
- clear script 要求 mutation reducer driver、单个 recovery `0x12` call site，以及 clear 确认前不调用 `clearLocalNetworkFields()`。
- RSSI script 把 10 秒改为 5 秒，把单次 timeout 2 秒改为 4 秒，并要求 `status.rssiResult` 与 `status.networkStatus` 分开 switch/mapping。

Run:

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 三个脚本因 controller/cell 仍使用旧 timeout、ASCII gate、旧 reducer flow 或旧 RSSI enum而 FAIL。

- [ ] **Step 2: 删除输入层 ASCII 限制并统一按钮校验**

`GatewayNetworkConnectivityCell.passwordChanged()` 改为无字符回退：

```swift
@objc private func passwordChanged() {
    let password = passwordTextField.text ?? ""
    currentPassword = password
    let nextState = passwordChangedCallback?(password) ?? .disabled
    apply(
        connectState: nextState,
        canSelectWiFi: selectWiFiButton.isEnabled,
        canRefresh: refreshButton.isEnabled,
        isRefreshing: !refreshLoadingImageView.isHidden,
        canEditSSID: canEditSSID,
        canEditPassword: canEditPassword,
        canTogglePasswordVisibility: passwordVisibilityButton.isEnabled
    )
}
```

Controller 的 editable state 直接尝试构造 SDK credentials：

```swift
private func computeEditableConnectState(password: String) -> GatewayNetworkConnectivityCell.ConnectState {
    guard (try? WiFiGatewayCredentials(ssid: networkSSID, password: password)) != nil else {
        return .disabled
    }
    return .available
}
```

`makeCredentialsForConnect()` 分别映射 SSID length、password length 和 control character errors；不再把所有 SSID 错误显示为空。

- [ ] **Step 3: 让请求 helper 强制指定 Subcode deadline**

`sendWiFiGatewayGet` 的 signature 改为：

```swift
private func sendWiFiGatewayGet(
    _ function: VendorFunctionGet,
    subcode: WiFiGatewayV19Subcode,
    origin: WiFiRequestOrigin,
    completion: @escaping (SunricherVendorStatus?) -> Void
) -> Bool
```

内部统一使用：

```swift
timeout: WiFiGatewayV19Timing.responseTimeout(for: subcode)
```

所有 call site 使用明确映射：

- `.wifiGatewayCredentials` → `.credentialsRead`
- `.wifiGatewayConnectionStatus` → `.connectionStatus`
- `.wifiGatewayRSSIStatus` → `.rssiStatus`

credentials SET/CLEAR helper 分别固定 `.credentialsSet`、`.credentialsClear`，删除 10 秒默认值。

- [ ] **Step 4: 接入 credential mutation reducer**

增加：

```swift
private var credentialMutationReducer = WiFiGatewayCredentialMutationReducer()
```

每次用户操作创建新的 reducer，`WiFiGatewayCredentialSnapshot` 从 SDK `ssidData/passwordData` 构造。typed response 映射规则固定为：

```swift
private func mutationResponse(
    from result: WiFiGatewayCredentialsSetResult?
) -> WiFiGatewayCredentialMutationResponse {
    switch result {
    case .accepted: return .confirmed
    case .invalidParameters: return .invalidParameters
    case .unconfirmed, .reserved, nil: return .unconfirmed
    }
}
```

Clear 使用相同三态映射。`requestCredentials` action 只能调用一次 `.wifiGatewayCredentials/.credentialsRead`；read result 转成 credentials/notConfigured/unconfirmed 后再次驱动 reducer。

Action side effects 固定如下：

- `.setTargetReached`：设置 source 为 gateway 并启动 Task 5 polling。
- `.setTargetNotReached`：恢复 editable，显示现有失败。
- `.setTargetUnknown`：恢复 editable，显示新的 unconfirmed 文案。
- `.clearTargetReached`：此时才清空字段并显示 Not Configured。
- `.clearTargetNotReached(snapshot)`：应用回读凭据，然后查询一次 `0x0E`。
- `.clearTargetUnknown`：保留清除前字段/连接状态并显示新的 unconfirmed 文案。

- [ ] **Step 5: 接入 polling reducer 与 `0x0E 06`**

删除 repeating timer 逻辑，保留 one-shot `networkConnectTimer`。每个 flow 创建新 reducer，使用 `ProcessInfo.processInfo.systemUptime` 作为 monotonic `now`。

Action driver：

```swift
private func applyConnectionPollingAction(
    _ action: WiFiGatewayConnectionPollingAction,
    operationID: Int
) {
    switch action {
    case .sendQuery:
        requestConnectionPollingStatus(operationID: operationID)
    case .schedule(let delay):
        scheduleConnectionPolling(after: delay, operationID: operationID)
    case .connected:
        finishConnectedState()
    case .failed, .timedOut:
        finishConnectionFailure()
    case .notConfigured:
        finishNotConfiguredState()
    case .none:
        break
    }
}
```

`WiFiGatewayConnectionStatus.requestFormatError` 和 nil/malformed callback 映射为 `.requestFormatError` / `.noValidResult`，不调用 `applyConnectionStatus`，因此保留当前 UI。

`loadConfiguredGatewayConnectionStatus`、`refreshConfiguredGatewayConnectionStatus` 和其它非轮询 switch 也必须显式处理 `.requestFormatError`：保持已有 credentials、header 和 connect state，只结束当前 refresh/loading，不映射为 password/connection failure。

- [ ] **Step 6: 接入组合型 RSSI model**

`applyWiFiRSSIStatus` 改为先算图标，再独立覆盖 Internet 文案：

```swift
private func applyWiFiRSSIStatus(_ status: WiFiGatewayRSSIStatus) {
    let signalStatus: WiFiHeaderStatus
    switch status.rssiResult {
    case .valid(let dbm):
        signalStatus = wifiHeaderStatus(forRSSIDBm: dbm)
    case .unavailable, .readFailed, .reserved:
        signalStatus = .noSignal
    }

    switch status.networkStatus {
    case .normal:
        updateWiFiHeaderStatus(signalStatus)
    case .unavailable:
        updateWiFiHeaderStatus(.init(
            iconName: signalStatus.iconName,
            localizedStatusKey: "wifi_status_no_internet"
        ))
    case .unknown, .reserved:
        updateWiFiHeaderStatus(.init(
            iconName: signalStatus.iconName,
            localizedStatusKey: "wifi_status_unknown"
        ))
    }
}
```

RSSI request 使用 `.rssiStatus` 的 4 秒 deadline，下一轮仍使用 `WiFiGatewayV19Timing.rssiPollDelay == 5`。

- [ ] **Step 7: 添加双语文案**

English：

```text
"wifi_gateway_ssid_length_error" = "Wi-Fi name must be 1–32 UTF-8 bytes.";
"wifi_gateway_configuration_unconfirmed" = "Unable to confirm Wi-Fi configuration.";
"wifi_gateway_clear_unconfirmed" = "Unable to confirm Wi-Fi credential removal.";
```

简体中文：

```text
"wifi_gateway_ssid_length_error" = "Wi-Fi 名称必须为 1–32 个 UTF-8 字节。";
"wifi_gateway_configuration_unconfirmed" = "无法确认 Wi-Fi 配置结果。";
"wifi_gateway_clear_unconfirmed" = "无法确认 Wi-Fi 凭据清除结果。";
```

- [ ] **Step 8: 运行 focused contracts**

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
git diff --check
```

Expected: 三个 scripts PASS，原先 10 秒 RSSI 静态契约不再存在。

- [ ] **Step 9: 提交 App Wi-Fi integration**

```bash
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings scripts/check_wifi_gateway_network_connectivity.sh scripts/check_wifi_gateway_disconnect_clear_credentials.sh scripts/check_wifi_gateway_wifi_status_header.sh
git commit -m "fix: align wifi gateway network flow with v1.9"
```

## Task 7: 建立持久化 `0x15` transaction gate 并修正 busy

**Files:**

- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUTransactionGate.swift`
- Create: `Tests/Firmware/WiFiFirmwareDFUTransactionGateTests.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift`
- Modify: `Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `WiFiFirmwareDFUTransactionGate.beginCancel(at:timeout:)`、`finishCancel()`、`expireIfNeeded(at:)`、`blocksStart(at:)`。
- Produces: `WiFiFirmwareDFUSession.transactionGate`，optional decode fallback compatible。
- Changes: `.busy` → recovery query，而不是 resolved failure。

- [ ] **Step 1: 创建 transaction gate RED test**

```swift
import Foundation

@main
struct WiFiFirmwareDFUTransactionGateTests {
    static func main() throws {
        testBlocksUntilCallback()
        testBlocksUntilDeadlineWithoutCallback()
        testRoundTripPersistence()
        print("WiFiFirmwareDFUTransactionGateTests passed")
    }

    static func testBlocksUntilCallback() {
        var gate = WiFiFirmwareDFUTransactionGate()
        precondition(gate.beginCancel(at: 100, timeout: 7))
        precondition(!gate.beginCancel(at: 101, timeout: 7))
        precondition(gate.blocksStart(at: 106.9))
        gate.finishCancel()
        precondition(!gate.blocksStart(at: 106.9))
    }

    static func testBlocksUntilDeadlineWithoutCallback() {
        var gate = WiFiFirmwareDFUTransactionGate()
        precondition(gate.beginCancel(at: 100, timeout: 7))
        precondition(gate.blocksStart(at: 106.9))
        precondition(!gate.blocksStart(at: 107))
        precondition(gate.expireIfNeeded(at: 107))
        precondition(gate.cancelDeadline == nil)
    }

    static func testRoundTripPersistence() throws {
        var gate = WiFiFirmwareDFUTransactionGate()
        _ = gate.beginCancel(at: 100, timeout: 7)
        let data = try JSONEncoder().encode(gate)
        let decoded = try JSONDecoder().decode(
            WiFiFirmwareDFUTransactionGate.self,
            from: data
        )
        precondition(decoded.blocksStart(at: 106))
    }
}
```

- [ ] **Step 2: 修改 Cancel RED test 的 busy 期望**

把 `testBusyEndsThisAttempt` 改名并改成：

```swift
private static func testBusyStartsAuthoritativeRecovery() {
    var pending = WiFiFirmwareDFUCancelReducer(state: .init(phase: .pending))
    precondition(pending.reduce(.response(.busy)) == .requestRecoveryQuery)
    precondition(pending.state.phase == .recovering)

    var unknown = WiFiFirmwareDFUCancelReducer(state: .init(phase: .unknown))
    precondition(unknown.reduce(.response(.busy)) == .requestUnknownQuery)
    precondition(unknown.state.phase == .unknown)
}
```

- [ ] **Step 3: 把两个 tests 接入 firmware script 并确认 RED**

新增 gate source/test 的 `swiftc` command；现有 Cancel reducer test 也会因旧 busy 语义失败。

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: transaction gate file missing或 busy expectation FAIL。

- [ ] **Step 4: 创建完整 transaction gate**

```swift
import Foundation

struct WiFiFirmwareDFUTransactionGate: Codable, Equatable {
    private(set) var cancelDeadline: TimeInterval?

    mutating func beginCancel(at now: TimeInterval, timeout: TimeInterval) -> Bool {
        guard !blocksStart(at: now) else { return false }
        cancelDeadline = now + timeout
        return true
    }

    mutating func finishCancel() {
        cancelDeadline = nil
    }

    @discardableResult
    mutating func expireIfNeeded(at now: TimeInterval) -> Bool {
        guard let cancelDeadline, now >= cancelDeadline else { return false }
        self.cancelDeadline = nil
        return true
    }

    func blocksStart(at now: TimeInterval) -> Bool {
        guard let cancelDeadline else { return false }
        return now < cancelDeadline
    }
}
```

使用 `Date().timeIntervalSince1970` 作为需要持久化的 wall-clock `now`；不要使用不可跨进程恢复的 uptime。

- [ ] **Step 5: 把 gate 持久化到 session**

在 `WiFiFirmwareDFUSession` 增加：

```swift
var transactionGate: WiFiFirmwareDFUTransactionGate
```

initializer 默认 `.init()`，`CodingKeys` 增加 `transactionGate`，decoder 使用：

```swift
transactionGate = try container.decodeIfPresent(
    WiFiFirmwareDFUTransactionGate.self,
    forKey: .transactionGate
) ?? .init()
```

这保证旧 JSON session 可以恢复。

- [ ] **Step 6: 修改 busy reducer 分支**

`.invalidParameters` 保持 resolved；`.busy` 从该分支移出并加入：

```swift
case (.pending, .response(.busy)),
     (.recovering, .response(.busy)):
    state.phase = .recovering
    return .requestRecoveryQuery

case (.unknown, .response(.busy)):
    return .requestUnknownQuery
```

- [ ] **Step 7: 更新 firmware standalone compile inputs**

脚本定义 gate source/test，并让所有包含 `WiFiFirmwareDFUState.swift` 的 `swiftc` 命令同时传入 gate source：

```bash
transaction_gate="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUTransactionGate.swift"
transaction_gate_test="Tests/Firmware/WiFiFirmwareDFUTransactionGateTests.swift"

swiftc -parse-as-library "$transaction_gate" "$transaction_gate_test" -o /tmp/WiFiFirmwareDFUTransactionGateTests
/tmp/WiFiFirmwareDFUTransactionGateTests

swiftc -parse-as-library "$transaction_gate" "$cancel_reducer" "$reducer" "$state" "$focused_test" -o /tmp/WiFiFirmwareDFUStatusReducerTests
swiftc -parse-as-library "$transaction_gate" "$cancel_reducer" "$reducer" "$state" "$cancel_focused_test" -o /tmp/WiFiFirmwareDFUCancelReducerTests
```

- [ ] **Step 8: 把 transaction gate 加入四个 App target**

将 `WiFiFirmwareDFUTransactionGate.swift` 加入 Firmware `Model` group 与四个 Sources phase。`rg -c 'WiFiFirmwareDFUTransactionGate.swift' SunSmart.xcodeproj/project.pbxproj` 必须输出 `10`。

- [ ] **Step 9: 运行 GREEN tests 并提交**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUTransactionGate.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift Tests/Firmware/WiFiFirmwareDFUTransactionGateTests.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift scripts/check_wifi_gateway_firmware_update.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: preserve wifi ota cancel transaction gate"
```

## Task 8: 重排 OTA 恢复并接入统一 Start gate

**Files:**

- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**

- Consumes: Task 3 V1.9 timing 与 Task 7 session gate。
- Produces: `WiFiFirmwareDFUCoordinator.Event.startAvailability(Bool)`。
- Preserves: existing status/cancel reducer、一次性 start recovery、10/30 秒业务查询节奏。

- [ ] **Step 1: 先写静态和纯 policy RED checks**

在 firmware script 增加检查：

- `beginInitialLoad()` 在 `queryCurrentVersion()` 之前出现 `registerObserversIfNeeded()` 和权威 `queryDFUStatus`。
- `timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStart)`。
- `timeout: WiFiGatewayV19Timing.responseTimeout(for: .firmwareVersion)`。
- `start()` 读取 `transactionGate.blocksStart`。
- terminal handler 不调用 `finishCancel()`。
- cancel callback 先 `finishCancel()` 再处理业务 response。
- controller 处理 `.startAvailability` 并将它同时用于 Upgrade 与 Retry enablement。
- cloud completion 不调用 `refreshOTAStatus()`。

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: 旧 initial-load order、10/5 秒 timeout 和缺少 start event 导致 FAIL。

- [ ] **Step 2: 重写 coordinator 初始入口顺序**

`beginInitialLoad()` 在清理 generation 状态后执行：

```swift
registerObserversIfNeeded()
emitStartAvailability()
enterCommunicationUnknown()
queryDFUStatus(purpose: .normal(authoritative: true))
```

删除 `cancelRequestInFlight` 作为 Start/Cancel 真值的职责；重复 Cancel 由 session 内 `transactionGate.beginCancel` 拒绝，业务是否继续 block 由 `cancelState.blocksNewStart` 决定。

删除该方法末尾直接 `queryCurrentVersion()`。`refreshOTAStatus()` 保留给用户显式 refresh 或现有调用兼容，但页面初始加载不再依赖它。

权威 query callback 增加 version scheduling：

- 完整 `IDLE`：清理 stale session并查询 `0x14`。
- `PREPARING` 或合法终态：处理状态后查询 `0x14`；SUCCESS 已带 module version 时允许直接 emit confirmed version，再按现有 UI 需要决定是否补 `0x14`。
- busy 中间态：不查询 `0x14`，等首个合法终态。
- 无完整合法权威 RET：保持 communication unknown，不查询 `0x14`，并 emit `.currentVersionFailed` 结束 Current version loading；该 UI 失败不改变 OTA session 的 unknown 判断。

- [ ] **Step 3: 对齐 `0x10/0x14` deadline**

替换为：

```swift
timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStart)
```

和：

```swift
timeout: WiFiGatewayV19Timing.responseTimeout(for: .firmwareVersion)
```

`0x11/0x15` 也改为读取 Task 3 同一表；其 reducer 中的 10/30 秒业务 timing 常量保留。

- [ ] **Step 4: 接入 cancel transport gate**

发送 `0x15` 前：

```swift
let now = Date().timeIntervalSince1970
guard session.transactionGate.beginCancel(
    at: now,
    timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuCancel)
) else { return }
self.session = session
saveSession()
emitStartAvailability()
```

Cancel callback 无论 RET、nil 或 malformed 都先执行：

```swift
if var session = self.session {
    session.transactionGate.finishCancel()
    self.session = session
    self.saveSession()
}
self.emitStartAvailability()
```

然后把 response 交给原 Cancel reducer。terminal EVENT/status handler 不得调用 `finishCancel()`。

恢复 session 时调用 `blocksStart(at: Date().timeIntervalSince1970)`；已过期 gate 不再阻止，并在下一次保存时清除过期 deadline。

新增独立 `cancelGateWorkItem`。每次 begin/restore active gate 时按剩余 deadline 调度；触发后调用 `expireIfNeeded`、保存 session、重新 emit Start availability。`deactivate()` 取消本 coordinator 的 work item；下次 `beginInitialLoad()` 按持久化 deadline 重新调度。这样旧 coordinator 已释放 callback 时，新页面也最多保守等待到 7 秒 deadline。

接受 Cancel 或原 OTA terminal 时，如果 transaction gate 仍 active，不得删除整个 session；保留 terminal snapshot 与 gate，等 callback/deadline 后再允许 Retry。terminal handler 不调用 `finishCancel()`。

- [ ] **Step 5: 统一 coordinator 与按钮的 Start truth**

Event 增加：

```swift
case startAvailability(Bool)
```

集中计算：

```swift
private func canStartNewOTA(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
    guard isActive,
          !startRequestInFlight,
          pendingStart == nil,
          session?.transactionGate.blocksStart(at: now) != true else {
        return false
    }
    guard let session, !session.terminalConsumed else { return true }
    return !session.cancelState.blocksNewStart &&
        session.lastStatus?.stage.isTerminal == true
}
```

`start()` 首个 guard 使用该方法；任何 session/cancel/gate 改变后 emit availability。

ViewController 增加 `canStartOTA`，处理 `.startAvailability`，并把 `.upgrade`、`.retry`、`.cancelled` 的 `isEnabled` 与 `canStartOTA` 合并。用户点击时 coordinator 内部 guard 仍是最终防线。

- [ ] **Step 6: 让云请求完全不阻塞恢复**

`loadFirmwareData()` 先调用 `dfuCoordinator.beginInitialLoad()`，再并行调用 `loadCloudFirmwareRequest`。删除 completion 触发 `dfuCoordinator.refreshOTAStatus()` 的路径；cloud completion 只刷新 server firmware UI。

`WiFiFirmwareInitialLoadGate` 若只剩该旧用途，删除 WiFi page 对它的持有和相关测试；如果基类仍使用它，则只移除 WiFi subclass 的 OTA recovery dependency，不改基类。

- [ ] **Step 7: 运行 GREEN firmware contract**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: status/cancel/transaction gate focused tests与 ordering contracts 全部 PASS。

- [ ] **Step 8: 提交 OTA integration**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift scripts/check_wifi_gateway_firmware_update.sh
git commit -m "fix: prioritize wifi ota recovery and gate new starts"
```

## Task 9: 审核四 target wiring 并执行全量验证

**Files:**

- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify only: all SDK/App files changed in Tasks 1–8。

**Interfaces:**

- Consumes: 四个 App 新 source files。
- Produces: 四 target 一致 source membership 审核和最终验证证据。

- [ ] **Step 1: 审核四个新 source files 的 target membership**

Tasks 3、4、5、7 已为以下文件各新增一个 `PBXFileReference`、四个 `PBXBuildFile`，并加入对应 Model group与四个 target 的 `PBXSourcesBuildPhase`：

- `WiFiGatewayV19Timing.swift`
- `WiFiGatewayCredentialMutationReducer.swift`
- `WiFiGatewayConnectionPollingReducer.swift`
- `WiFiFirmwareDFUTransactionGate.swift`

使用新的、唯一的 24 位 hex object IDs；执行以下检查确保每个文件有 1 个 file reference、4 个 build-file references 和 4 个 Sources entries：

```bash
for file in WiFiGatewayV19Timing.swift WiFiGatewayCredentialMutationReducer.swift WiFiGatewayConnectionPollingReducer.swift WiFiFirmwareDFUTransactionGate.swift; do
  rg -c "$file" SunSmart.xcodeproj/project.pbxproj
done
```

Expected: 每个文件输出 `10`；人工核对四个 Sources phase，不能只依赖总计数。若不一致，回到创建该文件的任务修正并 amend 对应 commit，不能把 broken membership 留到单独 build commit。

- [ ] **Step 2: 运行全部 focused checks**

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: 全部 PASS，`git diff --check` 无输出。

- [ ] **Step 3: 运行 SDK focused tests**

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter WiFiGatewayVendorMessageTests
git diff --check
git status --short
```

Expected: tests PASS 且 SDK clean。若唯一失败仍是既有 UIKit/macOS build blocker，记录原始错误；不得把它写成 PASS。

- [ ] **Step 4: 构建 NordicSigMeshDemo generic iPhoneOS**

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建四个 App targets**

Run from App worktree，逐条直接执行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 每条命令均出现 `** BUILD SUCCEEDED **`。任一 target 失败时停在该 target，按原始错误修复 scoped wiring/compile issue 后重跑该 target，再重跑后续 target。

- [ ] **Step 6: 审核范围与最终 diff**

App:

```bash
git status --short
git diff --stat 689e150e..HEAD
git diff --check
```

SDK:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
git status --short
git log -3 --oneline
git diff --check
```

Expected: 没有无关源码、资源、Auth 或依赖变更；App 的既有未跟踪分析文档仍未被加入任何 commit。

- [ ] **Step 7: 写实施总结**

创建 `docs/260721_1738_wifi_gateway_v19_conformance_fix_implementation_summary.md`，逐项记录：

- 6 个 P0、5 个 P1 对应 commit/test。
- SDK focused test 是 PASS 还是被 UIKit blocker 阻塞。
- NordicSigMeshDemo 和四个 App target 的实际 build 结果。
- focused shell checks 与 `git diff --check` 结果。
- 未执行的真机场景：丢 RET、迟到 RET、EVENT/RET 乱序、Proxy 重连、离页重进、App 重启、32-byte/中文凭据和 RSSI/Internet 组合。

只提交该总结文件：

```bash
git add docs/260721_1738_wifi_gateway_v19_conformance_fix_implementation_summary.md
git commit -m "docs: summarize wifi gateway v1.9 conformance fixes"
```

## Final Review Checklist

- [ ] SDK credential tests覆盖协议 12.1 exact bytes、32-byte SSID、Unicode controls 和 raw-byte equality。
- [ ] `0x0D/0x12/0x13` raw `0x02` 全部命名为 `.unconfirmed`。
- [ ] `0x0E 06` typed 为 `.requestFormatError`，App 不改变旧连接状态。
- [ ] `0x0F` 只接受 5 bytes，RSSI result 和 Internet status 永远独立存在。
- [ ] `0x11/0x14` 共用与 `0x10` 相同的 identifier 字符规则。
- [ ] 所有 Subcode deadline 与 V1.9 表一致。
- [ ] `0x0E` 首次立即、completion 后 5 秒、65 秒总窗口。
- [ ] `0x0D/0x13` 不确定结果最多一个 `0x12`，不存在 SET retry。
- [ ] RSSI poll delay 为 5 秒，静态 contract 不再要求 10 秒。
- [ ] observer/权威 `0x11` 不受 cloud request 阻塞。
- [ ] `0x15` terminal EVENT 不释放 transport gate。
- [ ] `0x15 04` 进入权威恢复。
- [ ] Upgrade/Retry UI 与 coordinator `start()` 使用同一 Start truth。
- [ ] 四个 App target 和 NordicSigMeshDemo build 都有最新证据。
- [ ] 未把协议安全 P2、UserDefaults password policy 或无关 refactor 混入本轮。
