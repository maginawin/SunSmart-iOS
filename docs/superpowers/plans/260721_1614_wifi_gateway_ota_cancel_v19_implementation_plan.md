# WiFi Gateway OTA Cancel V1.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 WiFi Gateway firmware update 页面实现完整的 V1.9 `0x43/0x15` 单次取消事务、恢复查询、持久化和 UI。

**Architecture:** 本地 NordicSigMeshSDK 负责强类型 request/response、严格 parser 和 `ota_id` response matching；App 使用 Foundation-only `WiFiFirmwareDFUCancelReducer` 管理取消事务，由现有 `WiFiFirmwareDFUCoordinator` 统一执行 Mesh 请求、计时、session 持久化和 UI event。原 `0x43/0x11` status reducer、页面重进权威恢复及 `0x14 + cloud latest -> 0x11` initial-load gate 保持为 OTA 状态真值层。

**Tech Stack:** Swift、UIKit、Foundation、NordicSigMeshSDK、XCTest、standalone Swift focused tests、shell contract、Xcode generic iPhoneOS builds。

## Global Constraints

- 设计真值为 `docs/superpowers/specs/260721_1606_wifi_gateway_ota_cancel_v19_design.md`。
- 按项目指令使用 `superpowers:executing-plans` Inline Execution；不使用 subagents。
- `CANCEL` 只在权威确认的 `PREPARING` / `DOWNLOADING` 开放。
- 点击后立即发送且只发送一次；不弹确认框、不自动重发、不提供 `CANCEL AGAIN`。
- 发送后按钮标题保持 `CANCEL` 并立即禁用。
- 7 秒无结论后最多连续查询 3 次 `0x43/0x11`，每次等待 3 秒；仍未知时页面可见期间每 30 秒查询。
- 取消未知只由完整 `IDLE` 或匹配本轮终态解除，并阻止新的 `0x43/0x10`。
- 离开页面停止取消 timer/query；重进或重连只查询 `0x43/0x11`，不得重发 `0x43/0x15`。
- 不建立全局后台 OTA 查询服务，不修改 BLE OTA、Mesh OTA 或其它 Gateway。
- 新增用户文案同步 English 与简体中文；不新增图片资源、依赖或 Auth 信息。
- 保留当前未提交的 re-entry recovery、request-order、Auto Layout 和“相同版本允许升级”改动，不回退、不格式化、不把无关文件混入提交。
- App 新文件加入 Common 共享 target；验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。
- Task 3 Coordinator 与 Task 4 UI/localization 属于同一个 App 编译批次：Task 3 只做 focused/static checkpoint，不提交不可编译的中间态；Task 4 完成 exhaustive UI switch、target membership 和本地化后先通过 `SunSmart` iPhoneOS build，再统一提交该批次。
- iOS 验证只使用直接 `xcodebuild`、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`；不使用 Simulator、shell 包装或日志重定向。
- SDK 仓库当前为干净 `dev`；App 仓库为 dirty worktree。SDK 可正常提交；App 每次提交前必须用 `git add -p` 仅暂存本任务 hunks，并逐行检查 `git diff --cached`。若无法与既有 hunks 安全分离，则保留未提交并在总结中说明，禁止整文件暂存。

---

## File Structure

### NordicSigMeshSDK

- Create: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift` — Cancel request、result、response、parser、matcher。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift` — SET payload 与 response command。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift` — subcode、response code、RET route、typed parameters。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift` — request/response `ota_id` matching。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift` — exhaustive SET switch 的无副作用 case。
- Modify: `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift` — codec/parser tests。
- Modify: `Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift` — transaction matching tests。

### App worktree

- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift` — 纯取消事务状态机。
- Create: `Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift` — reducer executable focused tests。
- Create: `Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift` — SDK 新协议 standalone contract。
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift` — session Codable、UI kind/action、authoritative recovery policy。
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift` — cancellation-authorized status source。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift` — cancel send、RET/EVENT、query purpose、lifecycle、Start guard。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — Cancel action、availability、toast。
- Modify: `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift` — unknown cancellation renderer。
- Modify: `SunSmart/en.lproj/Localizable.strings` — 3 个 English keys。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings` — 3 个简体中文 keys。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — cancel reducer 四 target membership。
- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift` — session migration / status-source regression。
- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — 新协议、文件、target、文案和行为 contract。
- Create: `docs/260721_1614_wifi_gateway_ota_cancel_v19_implementation_summary.md` — 最终证据总结。

---

### Task 1: NordicSigMeshSDK `0x43/0x15` Strongly Typed Protocol

**Files:**

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`
- Create: `Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift`

**Interfaces:**

- Produces: `WiFiGatewayDFUCancelRequest.init(otaID: UInt64) throws`。
- Produces: `WiFiGatewayDFUCancelResult.success / invalidParameters / notCancelled / unconfirmed / busy / reserved(rawValue:)`。
- Produces: `WiFiGatewayDFUCancelResponse.result`、`.otaID`。
- Produces: `VendorFunctionSet.wifiGatewayDFUCancel(WiFiGatewayDFUCancelRequest)`。
- Produces: `FunctionParameters.wifiGatewayDFUCancel(WiFiGatewayDFUCancelResponse)`。
- Consumed later by: `WiFiFirmwareDFUCoordinator.cancel()`。

- [ ] **Step 1: Write RED protocol tests**

在 SDK XCTest 增加以下测试，并在 App contract 文件写同样的纯协议断言：

```swift
func testWiFiGatewayDFUCancelV19EncodingAndValidation() throws {
    let request = try WiFiGatewayDFUCancelRequest(otaID: 0x8877665544332211)
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUCancel(request)).parameters,
        Data([0x43, 0x15, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
    )
    XCTAssertThrowsError(try WiFiGatewayDFUCancelRequest(otaID: 0)) {
        XCTAssertEqual($0 as? WiFiGatewayDFUCancelValidationError, .invalidOTAID)
    }
}

func testWiFiGatewayDFUCancelV19ResponseParsing() {
    let ota = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
    assertDFUCancel(Data([0x43, 0x15, 0x00]) + ota, expected: .success, otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x01]) + ota, expected: .invalidParameters, otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x02]) + ota, expected: .notCancelled, otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x03]) + ota, expected: .unconfirmed, otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x04]) + ota, expected: .busy, otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x7F]) + ota, expected: .reserved(rawValue: 0x7F), otaID: 0x8877665544332211)
    assertDFUCancel(Data([0x43, 0x15, 0x01]) + Data(repeating: 0, count: 8), expected: .invalidParameters, otaID: 0)

    let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x15, 0x00]) + ota + Data([0]))
    XCTAssertEqual(trailing?.status.code, .wifiGatewayDFUCancel)
    XCTAssertFalse(trailing?.status.isSuccessful ?? true)
    XCTAssertNil(trailing?.status.parameters)
}
```

Response matching test must use the existing `MeshMessageHandle(message:address:)` pattern and assert matching ID/source true, stale ID、zero ID、wrong source、Start RET、Status RET false。

```swift
func testWiFiGatewayDFUCancelStatusMustMatchRequestedOTAID() throws {
    let request = try WiFiGatewayDFUCancelRequest(otaID: 0x1122334455667788)
    let handle = MeshMessageHandle(
        message: SunricherVendorSet(function: .wifiGatewayDFUCancel(request)),
        address: 0x0003
    )
    let matching = SunricherVendorStatus(
        parameters: Data([0x43, 0x15, 0x00, 0x88, 0x77, 0x66, 0x55,
                          0x44, 0x33, 0x22, 0x11])
    )!
    let stale = SunricherVendorStatus(
        parameters: Data([0x43, 0x15, 0x00, 0x89, 0x77, 0x66, 0x55,
                          0x44, 0x33, 0x22, 0x11])
    )!
    let zero = SunricherVendorStatus(
        parameters: Data([0x43, 0x15, 0x01]) + Data(repeating: 0, count: 8)
    )!
    let start = SunricherVendorStatus(
        parameters: Data([0x43, 0x10, 0x00, 0x88, 0x77, 0x66, 0x55,
                          0x44, 0x33, 0x22, 0x11])
    )!

    XCTAssertTrue(handle.matchesResponse(matching, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(stale, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(zero, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(start, from: 0x0003))
    XCTAssertFalse(handle.matchesResponse(matching, from: 0x0004))
}

private func assertDFUCancel(
    _ data: Data,
    expected: WiFiGatewayDFUCancelResult,
    otaID: UInt64,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let status = SunricherVendorStatus(parameters: data)
    XCTAssertEqual(status?.status.code, .wifiGatewayDFUCancel, file: file, line: line)
    if case .wifiGatewayDFUCancel(let response) = status?.status.parameters {
        XCTAssertEqual(response.result, expected, file: file, line: line)
        XCTAssertEqual(response.otaID, otaID, file: file, line: line)
    } else {
        XCTFail("Expected WiFi Gateway DFU cancel result", file: file, line: line)
    }
}
```

`Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift` 使用以下完整内容：

```swift
import Foundation

@main
struct WiFiGatewayDFUCancelV19Contract {
    static func main() throws {
        let request = try WiFiGatewayDFUCancelRequest(otaID: 0x8877665544332211)
        precondition(
            request.parameters == Data([
                0x43, 0x15, 0x11, 0x22, 0x33,
                0x44, 0x55, 0x66, 0x77, 0x88
            ])
        )
        do {
            _ = try WiFiGatewayDFUCancelRequest(otaID: 0)
            preconditionFailure("zero ota_id must be rejected")
        } catch {
            precondition(error as? WiFiGatewayDFUCancelValidationError == .invalidOTAID)
        }

        let ota = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        let expected: [(UInt8, WiFiGatewayDFUCancelResult)] = [
            (0x00, .success),
            (0x01, .invalidParameters),
            (0x02, .notCancelled),
            (0x03, .unconfirmed),
            (0x04, .busy),
            (0x7F, .reserved(rawValue: 0x7F))
        ]
        for (raw, result) in expected {
            let response = WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, raw]) + ota
            )
            precondition(response?.result == result)
            precondition(response?.otaID == 0x8877665544332211)
        }
        precondition(
            WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, 0x01]) + Data(repeating: 0, count: 8)
            )?.otaID == 0
        )
        precondition(
            WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, 0x00]) + ota + Data([0])
            ) == nil
        )
        precondition(
            WiFiGatewayDFUCancelResponseMatcher.matches(
                requestOTAID: request.otaID,
                response: WiFiGatewayDFUCancelResponseParser.parse(
                    Data([0x43, 0x15, 0x00]) + ota
                )
            )
        )
        print("WiFiGatewayDFUCancelV19Contract passed")
    }
}
```

- [ ] **Step 2: Run the focused contract to verify RED**

Run from App worktree:

```bash
swiftc -parse-as-library /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift -o /tmp/WiFiGatewayDFUCancelV19Contract
```

Expected: FAIL because `WiFiGatewayDFUCancel.swift` and its public types do not exist yet.

- [ ] **Step 3: Implement the standalone protocol model**

Create the SDK file with this complete model:

```swift
import Foundation

public enum WiFiGatewayDFUCancelValidationError: Error, Equatable {
    case invalidOTAID
}

public struct WiFiGatewayDFUCancelRequest: Equatable {
    public let otaID: UInt64

    public init(otaID: UInt64) throws {
        guard otaID != 0 else {
            throw WiFiGatewayDFUCancelValidationError.invalidOTAID
        }
        self.otaID = otaID
    }

    var parameters: Data {
        var data = Data([0x43, 0x15])
        for offset in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: otaID >> UInt64(offset * 8)))
        }
        return data
    }
}

public enum WiFiGatewayDFUCancelResult: Equatable {
    case success
    case invalidParameters
    case notCancelled
    case unconfirmed
    case busy
    case reserved(rawValue: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .success
        case 0x01: self = .invalidParameters
        case 0x02: self = .notCancelled
        case 0x03: self = .unconfirmed
        case 0x04: self = .busy
        default: self = .reserved(rawValue: rawValue)
        }
    }
}

public struct WiFiGatewayDFUCancelResponse: Equatable {
    public let result: WiFiGatewayDFUCancelResult
    public let otaID: UInt64

    init(result: WiFiGatewayDFUCancelResult, otaID: UInt64) {
        self.result = result
        self.otaID = otaID
    }
}

enum WiFiGatewayDFUCancelResponseParser {
    static func parse(_ data: Data) -> WiFiGatewayDFUCancelResponse? {
        guard data.count == 11, data[0] == 0x43, data[1] == 0x15 else { return nil }
        let otaID = data[3..<11].enumerated().reduce(UInt64(0)) { value, item in
            value | (UInt64(item.element) << UInt64(item.offset * 8))
        }
        return .init(result: .init(rawValue: data[2]), otaID: otaID)
    }
}

enum WiFiGatewayDFUCancelResponseMatcher {
    static func matches(requestOTAID: UInt64, response: WiFiGatewayDFUCancelResponse?) -> Bool {
        response?.otaID == requestOTAID
    }
}
```

- [ ] **Step 4: Wire the SDK exhaustive switches**

Apply these exact semantic additions:

```swift
// VendorGatewayCode
case wifiDFUCancel = 0x15

// VendorFunctionSet
case wifiGatewayDFUCancel(WiFiGatewayDFUCancelRequest)

// VendorFunctionSet.data
case .wifiGatewayDFUCancel(let request):
    return request.parameters

// VendorFunctionSet.responseCommand
case .wifiGatewayDFUCancel: return .wifiGatewayDFUCancel

// ResponseCode and FunctionParameters
case wifiGatewayDFUCancel
case wifiGatewayDFUCancel(WiFiGatewayDFUCancelResponse)

// wifiGatewayParameters
case .wifiGatewayDFUCancel:
    guard let response = WiFiGatewayDFUCancelResponseParser.parse(data) else { return nil }
    return .wifiGatewayDFUCancel(response)
```

Add `.wifiGatewayDFUCancel` to gateway response-code initialization, `ResponseCode.code`, `isWiFiGatewayResponse`, and the `VendorServerDelegate` no-op group. In `MeshMessageHandle.matchesVendorStatus`, add a Cancel branch before the generic Vendor SET branch, mirroring Start but using `WiFiGatewayDFUCancelResponseMatcher`.

- [ ] **Step 5: Run GREEN checks**

Run:

```bash
swiftc -parse-as-library /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift -o /tmp/WiFiGatewayDFUCancelV19Contract
/tmp/WiFiGatewayDFUCancelV19Contract
```

Expected: `WiFiGatewayDFUCancelV19Contract passed`。

Run from SDK repo:

```bash
swift test --filter WiFiGatewayVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests
```

Expected: tests pass. If the existing UIKit-on-macOS package limitation blocks execution, record the exact `no such module 'UIKit'` output; the standalone contract and Task 5 iPhoneOS Demo build remain mandatory and must pass.

- [ ] **Step 6: Commit SDK protocol support**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift
git diff --cached --check
git commit -m "feat: support wifi gateway ota cancel protocol"
```

- [ ] **Step 7: Commit the standalone App-side protocol contract**

Run from App worktree; this is a new file and can be staged without touching existing dirty files:

```bash
git add Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift
git diff --cached --check
git diff --cached
git commit -m "test: guard wifi gateway ota cancel protocol"
```

Expected cached diff contains exactly one new contract file。

---

### Task 2: Foundation-only Cancel Reducer and Session Migration

**Files:**

- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift`
- Create: `Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift`
- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`

**Interfaces:**

- Produces: `WiFiFirmwareDFUCancelState.phase / sawVerifyingWhilePending / recoveryQueryCount / hasAttempted / blocksNewStart`。
- Produces: `WiFiFirmwareDFUCancelReducer.reduce(_:) -> WiFiFirmwareDFUCancelAction`。
- Produces: `WiFiFirmwareDFUSession.cancelState` with backward-compatible Codable。
- Produces: `WiFiFirmwareDFUStatusSource.cancellation`。
- Consumed later by: Coordinator only。

- [ ] **Step 1: Write RED reducer tests**

Create an `@main` focused executable whose `main()` calls named tests for: send-once、success/event order、`VERIFYING -> 0x02`、ordinary `0x02`、`0x03`、unknown ret、`0x04`、7-second timeout action、three invalid recovery results、matched intermediate、unknown polling、IDLE clear、terminal resolution、resume behavior。

Core assertions:

```swift
var reducer = WiFiFirmwareDFUCancelReducer()
precondition(reducer.reduce(.sent) == .none)
precondition(reducer.state.phase == .pending)
precondition(reducer.state.hasAttempted)
precondition(reducer.state.blocksNewStart)
precondition(reducer.reduce(.sent) == .none)

precondition(reducer.reduce(.matchedStatus(.verifying)) == .updateOriginalOTA)
precondition(reducer.reduce(.response(.notCancelled)) == .continueOriginalOTA(showFailureTip: true))
precondition(reducer.state.phase == .resolved)

var recovery = WiFiFirmwareDFUCancelReducer(state: .init(phase: .pending))
precondition(recovery.reduce(.pendingTimeout) == .requestRecoveryQuery)
precondition(recovery.reduce(.recoveryQuery(.invalid)) == .requestRecoveryQuery)
precondition(recovery.reduce(.recoveryQuery(.idle)) == .requestRecoveryQuery)
precondition(recovery.reduce(.recoveryQuery(.invalid)) == .enterUnknown)
precondition(recovery.state.phase == .unknown)
```

Status regression must prove ordinary `.event` still rejects `VERIFYING -> CANCELLED`, while `.cancellation` accepts it.

- [ ] **Step 2: Run focused tests to verify RED**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift -o /tmp/WiFiFirmwareDFUCancelReducerTests
```

Expected: FAIL because the cancel reducer types and session field do not exist.

- [ ] **Step 3: Implement cancel reducer types and transition table**

Use these exact public-to-App internal interfaces:

```swift
enum WiFiFirmwareDFUCancelPhase: String, Codable, Equatable {
    case notRequested, pending, recovering, unknown, resolved
}

struct WiFiFirmwareDFUCancelState: Codable, Equatable {
    var phase: WiFiFirmwareDFUCancelPhase = .notRequested
    var sawVerifyingWhilePending = false
    var recoveryQueryCount = 0

    var hasAttempted: Bool { phase != .notRequested }
    var blocksNewStart: Bool { phase == .pending || phase == .recovering || phase == .unknown }
}

enum WiFiFirmwareDFUCancelRET: Equatable {
    case success, invalidParameters, notCancelled, unconfirmed, busy, reserved
}

enum WiFiFirmwareDFUCancelStatusObservation: Equatable {
    case idle
    case matchedIntermediate(WiFiFirmwareDFUStatusStage)
    case matchedCancelled
    case matchedOtherTerminal
    case invalid
}

enum WiFiFirmwareDFUCancelInput: Equatable {
    case sent
    case response(WiFiFirmwareDFUCancelRET)
    case matchedStatus(WiFiFirmwareDFUStatusStage)
    case pendingTimeout
    case recoveryQuery(WiFiFirmwareDFUCancelStatusObservation)
    case unknownQuery(WiFiFirmwareDFUCancelStatusObservation)
    case resume
}

enum WiFiFirmwareDFUCancelAction: Equatable {
    case none
    case updateOriginalOTA
    case cancellationSucceeded
    case originalOTAFinished
    case continueOriginalOTA(showFailureTip: Bool)
    case requestRecoveryQuery
    case requestUnknownQuery
    case enterUnknown
    case scheduleUnknownQuery(updateOriginalOTA: Bool)
    case clearSession
}

enum WiFiFirmwareDFUCancelTiming {
    static let responseTimeout: TimeInterval = 7
    static let statusTimeout: TimeInterval = 3
    static let maximumRecoveryQueries = 3
    static let unknownQueryInterval: TimeInterval = 30
}
```

Reducer transition implementation must be a single exhaustive `switch (state.phase, input)` with these decisions:

- `.notRequested + .sent` -> `.pending`。
- `.pending + matched verifying` records flag, action `.updateOriginalOTA`。
- any attempted phase + matched cancelled -> `.resolved / .cancellationSucceeded`。
- any attempted phase + other terminal -> `.resolved / .originalOTAFinished`。
- any unresolved phase + success -> success；invalid/busy -> resolved continue + tip。
- pending/recovering + notCancelled with verifying -> resolved continue + tip；ordinary notCancelled/unconfirmed/reserved keeps or enters recovery and requests the appropriate query。
- unknown + notCancelled/unconfirmed/reserved remains unknown and requests/schedules an unknown query；迟到 RET 不得被丢弃。
- `.recovering + invalid/idle` increments count；before 3 requests next query，at 3 enter unknown。
- `.recovering + matched intermediate` -> resolved continue + tip。
- `.unknown + idle` -> resolved clear session；cancelled/terminal -> terminal actions；intermediate/invalid -> remain unknown and schedule 30-second query。
- `.pending/.recovering + resume` -> recovering count 0 + request recovery query；`.unknown + resume` -> request unknown query。
- duplicate/late inputs in `.resolved` -> `.none`。

- [ ] **Step 4: Add backward-compatible session Codable and recovery policy**

Add `cancelState` and explicit initializer. Implement custom `init(from:)` using `decodeIfPresent(... ) ?? .init()` for cancelState while decoding every existing field with its current type. Keep encoding automatic or implement matching `encode(to:)`.

Update query eligibility:

```swift
var isStatusQueryEligible: Bool {
    !terminalConsumed && (
        cancelState.blocksNewStart ||
        requiresAuthoritativeQuery ||
        lastStatus?.stage.isTerminal != true
    )
}
```

In authoritative recovery, when `cancelState.blocksNewStart` is true: accept only matching identity; allow complete IDLE to clear only for `.unknown`; all other mismatch returns `.retainSession`。Add `.cancellation` to `WiFiFirmwareDFUStatusSource`; keep the existing cancelled guard scoped to `.event` only.

- [ ] **Step 5: Run GREEN focused tests**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift -o /tmp/WiFiFirmwareDFUCancelReducerTests
/tmp/WiFiFirmwareDFUCancelReducerTests
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: both executables print `passed`。

- [ ] **Step 6: Stage only Task 2 hunks and commit if safely separable**

```bash
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift
git add -p SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift
git diff --cached --check
git diff --cached
git commit -m "feat: model wifi gateway ota cancellation"
```

Expected cached diff: only cancel reducer/session/status-source tests; no pre-existing re-entry/request-order hunks。

---

### Task 3: Coordinator Cancel Transaction, Recovery Queries, and Start Guard

**Files:**

- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**

- Consumes: Task 1 `WiFiGatewayDFUCancelRequest/Response/Result`。
- Consumes: Task 2 cancel reducer and session state。
- Produces: `WiFiFirmwareDFUCoordinator.cancel()`。
- Produces events: `.cancelAvailability(Bool)` and `.cancelNotEffective`。
- Preserves: `beginInitialLoad()` / `refreshOTAStatus()` gate and current generation semantics。

- [ ] **Step 1: Add RED static contract**

Replace the current “cancel is out of scope” rejection with positive assertions for: SDK cancel file、`func cancel()`、7/3/30 constants、session persisted before `MeshAPI.sendMessage`、`.wifiGatewayDFUCancel(request)`、global Cancel RET observer、`WiFiFirmwareDFUStatusSource.cancellation`、single cancel action、Start guard、three-query cap、unknown scheduling、deactivate no resend。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL at the first missing positive cancel assertion.

- [ ] **Step 2: Add Coordinator event and query-purpose state**

Add:

```swift
case cancelAvailability(Bool)
case cancelNotEffective

private enum StatusQueryPurpose: Equatable {
    case normal(authoritative: Bool)
    case cancelRecovery
    case cancelUnknown
}

private var cancelRequestInFlight = false
private var cancelReducer = WiFiFirmwareDFUCancelReducer()
```

Restore `cancelReducer` from `session.cancelState` in init。Whenever reducer mutates, assign state back to session and call `saveSession()` before performing the returned action。

- [ ] **Step 3: Implement guarded single-send `cancel()`**

The method must follow this exact order:

```swift
func cancel() {
    guard isActive,
          !cancelRequestInFlight,
          var session,
          !session.terminalConsumed,
          session.requiresAuthoritativeQuery == false,
          let otaID = session.otaID,
          otaID != 0,
          session.lastStatus?.otaID == otaID,
          session.lastStatus?.firmwareID == session.targetFirmwareID,
          session.lastStatus?.stage == .preparing || session.lastStatus?.stage == .downloading,
          !session.cancelState.hasAttempted,
          let vendorModel = validVendorModel(),
          let request = try? WiFiGatewayDFUCancelRequest(otaID: otaID) else { return }

    _ = cancelReducer.reduce(.sent)
    session.cancelState = cancelReducer.state
    self.session = session
    saveSession()
    emit(.cancelAvailability(false))
    cancelScheduledQuery()
    cancelRequestInFlight = true
    let requestGeneration = generation

    MeshAPI.sendMessage(
        message: SunricherVendorSet(function: .wifiGatewayDFUCancel(request)),
        model: vendorModel,
        timeout: WiFiFirmwareDFUCancelTiming.responseTimeout
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.cancelRequestInFlight = false
            self.handleCancelCallback(response, expectedOTAID: otaID)
        }
    }
}
```

The parenthesized stage guard must be implemented safely as a local `stage` plus `[.preparing, .downloading].contains(stage)` to avoid Swift precedence ambiguity。

- [ ] **Step 4: Route RET and EVENT through one reducer-action handler**

Extend the global observer switch to accept both `SunricherReportMessage.wifiGatewayDFUStatus` and `SunricherVendorStatus.wifiGatewayDFUCancel`。Map SDK result exactly:

```swift
case .success: .success
case .invalidParameters: .invalidParameters
case .notCancelled: .notCancelled
case .unconfirmed: .unconfirmed
case .busy: .busy
case .reserved: .reserved
```

Reject any response whose `otaID` is zero or differs from `session.otaID`。Both callback and observer may deliver the same RET; `.resolved`/phase guards make the second delivery `.none`。

For matching Status:

- Feed its stage to cancel reducer when `hasAttempted`。
- Use status source `.cancellation` only for a matching `CANCELLED` after a real cancel attempt；otherwise keep `.event` / `.query`。
- Accept the original OTA snapshot through the existing status reducer before scheduling the cancel action。
- On Cancel RET success, synthesize a matching `.cancelled` snapshot from the last status identity/progress and accept it with `.cancellation`。

- [ ] **Step 5: Implement recovery and unknown query purposes**

Change the private query entry to `queryDFUStatus(purpose: StatusQueryPurpose)` and keep one `statusQueryInFlight`。For `.cancelRecovery`, convert each completion to `matchedCancelled / matchedOtherTerminal / matchedIntermediate / idle / invalid` and feed `.recoveryQuery`。For `.cancelUnknown`, feed `.unknownQuery`。

Central action execution:

```swift
case .requestRecoveryQuery:
    queryDFUStatus(purpose: .cancelRecovery)
case .enterUnknown:
    emit(.updateState(.init(kind: .cancellationUnknown, percent: currentPercent)))
    scheduleQuery(after: WiFiFirmwareDFUCancelTiming.unknownQueryInterval, purpose: .cancelUnknown)
case .requestUnknownQuery:
    queryDFUStatus(purpose: .cancelUnknown)
case .scheduleUnknownQuery(let updateOriginalOTA):
    if updateOriginalOTA { emitCancellationUnknownState() }
    scheduleQuery(after: WiFiFirmwareDFUCancelTiming.unknownQueryInterval, purpose: .cancelUnknown)
case .continueOriginalOTA(let showFailureTip):
    if showFailureTip { emit(.cancelNotEffective) }
    scheduleNormalQuery()
case .clearSession:
    clearSession(); emit(.idle)
```

Recovery invalid/IDLE must issue at most three immediate GETs, each using 3-second timeout。Unknown uses only 30-second schedule。Never use the normal 10-second query while cancel phase is `.unknown`。

- [ ] **Step 6: Integrate lifecycle and Start safety**

- `deactivate()` invalidates generation, clears in-flight flags/timers, persists page recovery, never calls Cancel。
- `refreshOTAStatus()` inspects persisted phase: pending/recovering resumes `.cancelRecovery`; unknown resumes `.cancelUnknown`; resolved/notRequested uses current authoritative flow。
- reconnect does the same phase-based authoritative query immediately。
- `start()` checks old session before `clearSession()`。Allow no session or a known terminal; reject any nonterminal session or `cancelState.blocksNewStart == true`。
- Every accepted status re-emits Cancel availability: true only for matching preparing/downloading, authoritative gate false, no prior attempt。

- [ ] **Step 7: Run Coordinator contracts and focused tests**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: static checks pass and no whitespace errors。

- [ ] **Step 8: Review the Task 3 checkpoint without committing a partial App state**

```bash
git diff --check
git diff -- SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift scripts/check_wifi_gateway_firmware_update.sh
```

Expected: no whitespace errors；review confirms pre-existing initial-load/re-entry hunks are preserved。Do not commit until Task 4 supplies the exhaustive UI cases and the App compiles。

---

### Task 4: WiFi Firmware Cancel UI, Localization, and Target Membership

**Files:**

- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**

- Consumes: Coordinator `.cancelAvailability` / `.cancelNotEffective` / `.updateState`。
- Produces: `WiFiFirmwareUpdatingKind.cancellationUnknown`。
- Produces: `WiFiFirmwarePrimaryAction.cancel`。
- Produces localization keys: `wifi_firmware_cancel_not_effective`、`wifi_firmware_cancel_result_unknown`、`wifi_firmware_waiting_status_confirmation`。

- [ ] **Step 1: Add RED UI/static assertions**

Contract must assert: `.cancel` action exists、controller calls `dfuCoordinator.cancel()`、availability controls enabled state、pending title remains `cancel`、unknown renderer uses both keys、English/Chinese exact values、new reducer has four PBXBuildFile and four Sources entries。

Run `bash scripts/check_wifi_gateway_firmware_update.sh` and expect FAIL at missing UI cancel action。

- [ ] **Step 2: Add UI state and action**

```swift
enum WiFiFirmwareUpdatingKind: String, Codable {
    // existing cases...
    case cancellationUnknown
}

enum WiFiFirmwarePrimaryAction: Equatable {
    case upgrade, retry, cancel, cancelDisabled, done
}
```

Controller adds `private var canCancel = false`。Handle `.cancelAvailability(let enabled)` by updating `canCancel` and refreshing UI；handle `.cancelNotEffective` with:

```swift
XWHUDManager.showTipHUD(
    "wifi_firmware_cancel_not_effective".localizedString,
    isLineFeed: true
)
```

For `.downloading`, return enabled `.cancel` only when `canCancel`; otherwise disabled `.cancelDisabled`。`.updating`、`.communicationUnknown`、`.cancellationUnknown` always return disabled Cancel。`firmwarePrimaryAction()` routes `.cancel` to `dfuCoordinator.cancel()`。

- [ ] **Step 3: Render cancellation unknown and add exact localizations**

View mapping:

```swift
case .cancellationUnknown:
    titleKey = "wifi_firmware_cancel_result_unknown"
    detailKey = "wifi_firmware_waiting_status_confirmation"
    imageName = "alert_failed"
```

English:

```text
"wifi_firmware_cancel_not_effective" = "Unable to cancel. The update will continue.";
"wifi_firmware_cancel_result_unknown" = "Cancellation result unknown";
"wifi_firmware_waiting_status_confirmation" = "Waiting for status confirmation";
```

Simplified Chinese:

```text
"wifi_firmware_cancel_not_effective" = "无法取消，固件升级将继续。";
"wifi_firmware_cancel_result_unknown" = "取消结果未知";
"wifi_firmware_waiting_status_confirmation" = "正在等待状态确认";
```

- [ ] **Step 4: Add cancel reducer to all four targets**

Use unused IDs `C8F6A1402FA3000000000001` for PBXFileReference and `C8F6A141...C8F6A144` for four PBXBuildFile entries。Place the file next to `WiFiFirmwareDFUStatusReducer.swift` in the Firmware Model group and add one Sources entry to each of the four existing target phases。Do not change target settings or package references。

- [ ] **Step 5: Run UI, localization, and project checks**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: contract passes；all three plist checks report `OK`；diff check is silent；build ends with `** BUILD SUCCEEDED **`。

- [ ] **Step 6: Stage Task 4 hunks safely and commit if separable**

```bash
git add -p SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj scripts/check_wifi_gateway_firmware_update.sh
git diff --cached --check
git diff --cached
git commit -m "feat: support wifi gateway ota cancellation"
```

Expected cached diff preserves the same-version experiment and request-order changes as pre-existing context, without attributing unrelated hunks to this task。

---

### Task 5: Full Verification, Scope Audit, and Implementation Summary

**Files:**

- Verify: all Task 1–4 files in both repositories。
- Create: `docs/260721_1614_wifi_gateway_ota_cancel_v19_implementation_summary.md`。

**Interfaces:**

- Consumes: complete SDK/App implementation。
- Produces: reproducible verification evidence and explicit remaining real-device checks。

- [ ] **Step 1: Run all focused contracts**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift -o /tmp/WiFiFirmwareDFUCancelReducerTests
/tmp/WiFiFirmwareDFUCancelReducerTests
swiftc -parse-as-library /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift -o /tmp/WiFiGatewayDFUCancelV19Contract
/tmp/WiFiGatewayDFUCancelV19Contract
```

Expected: contract script PASS and both executables print `passed`。

- [ ] **Step 2: Audit both repository diffs**

Run in App repo and SDK repo separately:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: no whitespace errors。Classify every App path as pre-existing user work、this feature、or generated summary；do not delete or stage unrelated files。SDK diff contains only Task 1 if it has not already been committed。

- [ ] **Step 3: Build the SDK Demo for iPhoneOS**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Build all four App targets for iPhoneOS**

Run directly from App worktree:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all four commands end with `** BUILD SUCCEEDED **`。

- [ ] **Step 5: Perform protocol/source acceptance audit**

Confirm in source and tests:

- exactly one `0x15` send site；no retry path and no `CANCEL AGAIN`。
- Cancel enabled only after matching authoritative preparing/downloading。
- persistence occurs before send。
- RET/event order converges and late callbacks are ignored。
- `VERIFYING -> 0x02` branch differs from ordinary `0x02`。
- recovery count is exactly 3 and each GET timeout is 3 seconds。
- unknown interval is 30 seconds and blocks Start。
- complete IDLE/matching terminal are the only unknown unblockers。
- page exit stops queries；re-entry/reconnect query only and never resend Cancel。
- initial-load gate and current/cloud request order remain intact。
- new reducer belongs to all four targets and all copy is localized。

- [ ] **Step 6: Write implementation summary**

Summary must record: SDK commit、App commit status、RED/GREEN evidence、focused contract outputs、lint、five iPhoneOS build results、preserved dirty paths、and these real-device checks still required:

1. only one raw `43 15 <ota_id>` after tapping Cancel；
2. button disables immediately；
3. RET-first and EVENT-first both converge；
4. 7-second/3-query/30-second cadence in logs；
5. leaving/re-entering never emits a second `43 15`；
6. unknown state never emits a new `43 10`。

- [ ] **Step 7: Commit summary and any safely separable remaining App hunks**

Stage only verified task hunks. Inspect cached diff before committing:

```bash
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift
git add -p SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift scripts/check_wifi_gateway_firmware_update.sh
git add docs/260721_1614_wifi_gateway_ota_cancel_v19_implementation_summary.md
git diff --cached --check
git diff --cached
git commit -m "feat: support wifi gateway ota cancellation"
```

If pre-existing hunks cannot be separated safely, commit only new files/cleanly separable hunks and document the remaining uncommitted paths; never broaden staging to force a clean commit。
