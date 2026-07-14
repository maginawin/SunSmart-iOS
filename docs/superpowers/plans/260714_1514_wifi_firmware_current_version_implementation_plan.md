# WiFi Firmware Current Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 NordicSigMeshSDK 实现 WiFi Gateway `43 14` firmware version 查询，并让现有 WiFi Firmware Update 页面实时展示 Current version，仅在云端 New version 严格更高时启用 `UPGRADE`。

**Architecture:** SDK 沿现有 `SunricherVendorGet` / `SunricherVendorStatus` Gateway pipeline 增加独立 response code 和 typed result。App 保留 `FirmwareVersionViewController` 的共享 UI 与云端查询，只增加默认兼容的附加数据加载和 Current version 展示 hook；`WiFiFirmwareUpdateViewController` 持有目标 node、实时查询状态和版本比较逻辑。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SIG Mesh Vendor Messages、SwiftyJSON、SnapKit、XCTest、Bash 静态契约、Xcode Debug iPhoneOS build。

## Global Constraints

- 设备范围固定为 CID `0x0A78`、PID `0x2721`；不得改变其它 Gateway。
- SDK GET payload 必须精确为 `43 14`，不得允许调用方追加参数。
- success version 长度为 `1...32`，只接受可展示 ASCII `0x20...0x7E`，并严格拒绝长度不符和 trailing bytes。
- SDK 必须保留 `invalidParameters`、`busy`、`queryFailed`、`deadlineExceeded` 和未知 ret 的 typed result。
- App 首次进入和 Refresh 时并行查询 New version 与 Current version。
- Current version 初始显示 `Loading...`；失败显示 `Failed`；失败或 loading 时 `UPGRADE` 禁用。
- 比较前只移除开头一个 `v` 或 `V`，之后使用项目现有 `.numeric` 比较；仅 New version 为 `.orderedDescending` 时启用。
- App 使用 10 秒 Mesh timeout，不把网关内部 5 秒 deadline 机械映射为 App timeout。
- `UPGRADE` 点击继续显示现有 `under_development`，不实现真实 WiFi DFU。
- 查询结果不得写入 Node、数据库或云端缓存。
- 其它 Gateway、BLE/Mesh Firmware Update 与四个品牌 target 的既有行为必须保持不变。
- 所有用户可见文案必须国际化，并同步 English 与简体中文。
- 不新增 Auth 信息，不顺手重构无关模块，不批量格式化文件。
- 使用 Debug iPhoneOS generic destination、`CODE_SIGNING_ALLOWED=NO` 验证，不使用 Simulator。

---

## File Structure

### NordicSigMeshSDK repository

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift` — 编码 `43 14` GET。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift` — Gateway subcode、response routing、typed result 与严格解析。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift` — 新结果的显式 no-op 分支。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift` — 编码、解析、非法 payload 与 response matching 测试。

### App repository

- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift` — 增加默认兼容的 Current version 与附加数据请求 hook。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — Current version 状态机、实时查询和联合版本比较。
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` — 将当前 node 传给固件页面。
- Modify: `SunSmart/en.lproj/Localizable.strings` — 新增 `current_version`。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings` — 新增 `current_version`。
- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — 守住 SDK 接入、页面状态、入口、比较和回归契约。
- Create: `docs/260714_1514_wifi_firmware_current_version_implementation_summary.md` — 记录实施结果与验证证据。

## Interfaces

### SDK produces

- `VendorFunctionGet.wifiGatewayFirmwareVersion`
- `ResponseCode.wifiGatewayFirmwareVersionGet`
- `WiFiGatewayFirmwareVersionResult`
- `FunctionParameters.wifiGatewayFirmwareVersion(WiFiGatewayFirmwareVersionResult)`

### App shared controller produces

- `currentVersionTitleText: String`
- `currentVersionDisplayText: String`
- `createsUIBeforeCloudRequest: Bool`
- `requiresAdditionalFirmwareReload: Bool`
- `loadAdditionalFirmwareData()`
- `refreshFirmwareUI()`

### WiFi page consumes

- 当前 `Node`
- `node.sunricherVendorModel`
- `MeshAPI.sendMessage(message:model:timeout:result:)`
- `WiFiGatewayFirmwareVersionResult`
- `type.serverData?.version`

---

### Task 1: 以 XCTest 驱动 SDK `43 14` 编码与解析

**Files:**
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`

**Interfaces:**
- Consumes: 现有 `VendorGatewayCode`、`VendorFunctionGet`、`ResponseCode`、`SunricherVendorStatus.Status.wifiGatewayParameters`。
- Produces: 本计划全局 Interfaces 中列出的四个 SDK public interfaces。

- [ ] **Step 1: 写 GET 编码与合法 response 测试**

在 `testWifiGatewayGetEncoding()` 末尾加入：

```swift
XCTAssertEqual(
    SunricherVendorGet(function: .wifiGatewayFirmwareVersion).parameters,
    Data([0x43, 0x14])
)
```

新增：

```swift
func testFirmwareVersionResponseParsing() {
    let payload = Data([0x43, 0x14, 0x00, 0x06]) + Data("V1.7.0".utf8)
    let status = SunricherVendorStatus(parameters: payload)

    XCTAssertEqual(status?.status.isSuccessful, true)
    XCTAssertEqual(status?.status.errorCode, nil)
    XCTAssertEqual(status?.status.code, .wifiGatewayFirmwareVersionGet)
    if case .wifiGatewayFirmwareVersion(.success(let version)) = status?.status.parameters {
        XCTAssertEqual(version, "V1.7.0")
    } else {
        XCTFail("Expected WiFi Gateway firmware version")
    }

    let oneByte = SunricherVendorStatus(parameters: Data([0x43, 0x14, 0x00, 0x01, 0x31]))
    if case .wifiGatewayFirmwareVersion(.success(let version)) = oneByte?.status.parameters {
        XCTAssertEqual(version, "1")
    } else {
        XCTFail("Expected one-byte firmware version")
    }

    let maxVersion = String(repeating: "1", count: 32)
    let maxPayload = Data([0x43, 0x14, 0x00, 0x20]) + Data(maxVersion.utf8)
    if case .wifiGatewayFirmwareVersion(.success(let version)) = SunricherVendorStatus(parameters: maxPayload)?.status.parameters {
        XCTAssertEqual(version, maxVersion)
    } else {
        XCTFail("Expected 32-byte firmware version")
    }
}
```

- [ ] **Step 2: 写 ret 与非法 payload 测试**

新增：

```swift
func testFirmwareVersionFailureAndMalformedResponseParsing() {
    assertFirmwareVersion(Data([0x43, 0x14, 0x01]), expected: .invalidParameters, errorCode: 0x01)
    assertFirmwareVersion(Data([0x43, 0x14, 0x02]), expected: .busy, errorCode: 0x02)
    assertFirmwareVersion(Data([0x43, 0x14, 0x03]), expected: .queryFailed, errorCode: 0x03)
    assertFirmwareVersion(Data([0x43, 0x14, 0x04]), expected: .deadlineExceeded, errorCode: 0x04)
    assertFirmwareVersion(Data([0x43, 0x14, 0x7F]), expected: .reserved(rawValue: 0x7F), errorCode: 0x7F)

    let malformed: [Data] = [
        Data([0x43, 0x14, 0x00]),
        Data([0x43, 0x14, 0x00, 0x00]),
        Data([0x43, 0x14, 0x00, 0x21]) + Data(repeating: 0x31, count: 33),
        Data([0x43, 0x14, 0x00, 0x03, 0x31, 0x2E]),
        Data([0x43, 0x14, 0x00, 0x01, 0x1F]),
        Data([0x43, 0x14, 0x00, 0x01, 0x80]),
        Data([0x43, 0x14, 0x00, 0x01, 0x31, 0x00]),
        Data([0x43, 0x14, 0x02, 0x00])
    ]

    for payload in malformed {
        let status = SunricherVendorStatus(parameters: payload)
        XCTAssertEqual(status?.status.code, .wifiGatewayFirmwareVersionGet)
        XCTAssertEqual(status?.status.isSuccessful, false)
        XCTAssertNil(status?.status.parameters)
    }
}

private func assertFirmwareVersion(
    _ data: Data,
    expected: WiFiGatewayFirmwareVersionResult,
    errorCode: UInt8,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let status = SunricherVendorStatus(parameters: data)
    XCTAssertEqual(status?.status.isSuccessful, false, file: file, line: line)
    XCTAssertEqual(status?.status.errorCode, errorCode, file: file, line: line)
    XCTAssertEqual(status?.status.code, .wifiGatewayFirmwareVersionGet, file: file, line: line)
    if case .wifiGatewayFirmwareVersion(let result) = status?.status.parameters {
        XCTAssertEqual(result, expected, file: file, line: line)
    } else {
        XCTFail("Expected WiFi Gateway firmware version result", file: file, line: line)
    }
}
```

- [ ] **Step 3: 扩展 response matching 测试**

在 `testWiFiGatewayVendorStatusMustMatchCurrentCommandCode()` 加入：

```swift
let firmwareVersionHandle = MeshMessageHandle(
    message: SunricherVendorGet(function: .wifiGatewayFirmwareVersion),
    address: 0x0003
)
let firmwareVersionStatus = SunricherVendorStatus(
    parameters: Data([0x43, 0x14, 0x00, 0x05]) + Data("1.7.0".utf8)
)!

XCTAssertTrue(firmwareVersionHandle.matchesResponse(firmwareVersionStatus, from: 0x0003))
XCTAssertFalse(firmwareVersionHandle.matchesResponse(connectionStatus, from: 0x0003))
XCTAssertFalse(connectionHandle.matchesResponse(firmwareVersionStatus, from: 0x0003))
XCTAssertFalse(firmwareVersionHandle.matchesResponse(firmwareVersionStatus, from: 0x0004))
```

- [ ] **Step 4: 运行测试并记录红灯或既有 UIKit blocker**

Run：

```bash
swift test --filter WiFiGatewayVendorMessageTests
```

Working directory：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected：若测试目标能编译，则 FAIL 于缺少 `wifiGatewayFirmwareVersion` interfaces；若仍在编译测试目标前报 `no such module 'UIKit'`，记录为既有 SwiftPM/macOS blocker，并继续以新增 XCTest 源码和 iPhoneOS build 验证，不把它误判为新功能失败。

- [ ] **Step 5: 实现 GET function 与 Gateway routing**

在 `VendorGatewayCode` 加入：

```swift
/// 获取 Wi-Fi firmware version
case wifiFirmwareVersionGet = 0x14
```

在 `VendorFunctionGet` 加入 case，并在 `command` switch 中映射：

```swift
case wifiGatewayFirmwareVersion
```

```swift
case .wifiGatewayFirmwareVersion: return .wifiGatewayFirmwareVersionGet
```

在 `ResponseCode` enum、Gateway initializer switch 和 `code` switch 分别加入：

```swift
case wifiGatewayFirmwareVersionGet
```

```swift
case VendorGatewayCode.wifiFirmwareVersionGet.rawValue:
    self = .wifiGatewayFirmwareVersionGet
```

```swift
case .wifiGatewayFirmwareVersionGet:
    return [VendorOpCode.gateway.rawValue, VendorGatewayCode.wifiFirmwareVersionGet.rawValue]
```

- [ ] **Step 6: 实现 typed result 与严格 parser**

在 WiFi result enums 区域加入：

```swift
public enum WiFiGatewayFirmwareVersionResult: Equatable {
    case success(String)
    case invalidParameters
    case busy
    case queryFailed
    case deadlineExceeded
    case reserved(rawValue: UInt8)
}
```

在 `FunctionParameters` 加入：

```swift
/// Wi-Fi firmware version 查询结果
case wifiGatewayFirmwareVersion(WiFiGatewayFirmwareVersionResult)
```

在 `wifiGatewayParameters` switch 加入：

```swift
case .wifiGatewayFirmwareVersionGet:
    return wifiGatewayFirmwareVersionParameters(data: data, status: status)
```

新增严格 parser：

```swift
private static func wifiGatewayFirmwareVersionParameters(data: Data, status: UInt8) -> FunctionParameters? {
    switch status {
    case 0x00:
        guard data.count >= 5 else { return nil }
        let versionLength = Int(data[3])
        guard (1...32).contains(versionLength), data.count == 4 + versionLength else { return nil }
        let versionBytes = Array(data[4...])
        guard versionBytes.allSatisfy({ (0x20...0x7E).contains($0) }),
              let version = String(bytes: versionBytes, encoding: .ascii) else {
            return nil
        }
        return .wifiGatewayFirmwareVersion(.success(version))
    case 0x01:
        guard data.count == 3 else { return nil }
        return .wifiGatewayFirmwareVersion(.invalidParameters)
    case 0x02:
        guard data.count == 3 else { return nil }
        return .wifiGatewayFirmwareVersion(.busy)
    case 0x03:
        guard data.count == 3 else { return nil }
        return .wifiGatewayFirmwareVersion(.queryFailed)
    case 0x04:
        guard data.count == 3 else { return nil }
        return .wifiGatewayFirmwareVersion(.deadlineExceeded)
    default:
        guard data.count == 3 else { return nil }
        return .wifiGatewayFirmwareVersion(.reserved(rawValue: status))
    }
}
```

把 `.wifiGatewayFirmwareVersionGet` 加入 `ResponseCode.isWiFiGatewayResponse`。

- [ ] **Step 7: 补齐 delegate exhaustive switch**

在 `VendorServerDelegate` 对 `FunctionParameters` 的 switch 中，将新 case 加入 no-op 分支：

```swift
case .wifiGatewayCredentialsSet,
        .wifiGatewayCredentialsClear,
        .wifiGatewayFirmwareVersion:
    return
```

- [ ] **Step 8: 尝试 focused tests 并执行 SDK iPhoneOS build**

Run：

```bash
swift test --filter WiFiGatewayVendorMessageTests
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Working directory：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected：focused tests PASS，或仅保留已确认的 `no such module 'UIKit'` blocker；iPhoneOS build 必须以 `** BUILD SUCCEEDED **` 结束。

- [ ] **Step 9: 检查并提交 SDK 改动**

Run：

```bash
git diff --check
git diff -- Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "feat: add wifi firmware version query"
```

Expected：`git diff --check` 无输出；SDK 仓库生成一个仅含四个目标文件的提交。

---

### Task 2: 以静态契约驱动共享 Firmware 页面扩展点

**Files:**
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`

**Interfaces:**
- Consumes: 现有 `displayedCurrentTargetVersion`、`loadCloudFirmwareRequest()`、`reloadBtnAction()`、`updateUI()`、`setupUI()`。
- Produces: 本计划全局 Interfaces 中列出的六个 App shared controller hooks。

- [ ] **Step 1: 在脚本加入共享 hook 红灯契约**

在 `scripts/check_wifi_gateway_firmware_update.sh` 的 parent 检查区域加入：

```bash
rg -n 'var currentVersionTitleText: String' "$parent" >/dev/null || fail "missing current version title hook"
rg -n 'var currentVersionDisplayText: String' "$parent" >/dev/null || fail "missing current version display hook"
rg -n 'var createsUIBeforeCloudRequest: Bool' "$parent" >/dev/null || fail "missing early UI hook"
rg -n 'var requiresAdditionalFirmwareReload: Bool' "$parent" >/dev/null || fail "missing additional reload state hook"
rg -n 'func loadAdditionalFirmwareData\(\)' "$parent" >/dev/null || fail "missing additional firmware load hook"
rg -n 'func refreshFirmwareUI\(\)' "$parent" >/dev/null || fail "missing firmware UI refresh hook"
rg -n 'currentVersionTitleText' "$parent" >/dev/null || fail "current version title label ignores hook"
rg -n 'currentVersionDisplayText' "$parent" >/dev/null || fail "current version label ignores hook"
rg -n 'if createsUIBeforeCloudRequest' "$parent" >/dev/null || fail "viewDidLoad ignores early UI hook"
additional_load_count=$(grep -Fc 'loadAdditionalFirmwareData()' "$parent")
[ "$additional_load_count" -eq 3 ] || fail "additional firmware load must appear in declaration, initial load, and refresh"
rg -n 'if requiresAdditionalFirmwareReload' "$parent" >/dev/null || fail "firmware UI ignores additional failure"
```

- [ ] **Step 2: 运行契约并确认红灯**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected：FAIL，首个新错误为 `missing current version title hook`。

- [ ] **Step 3: 增加默认兼容 hook**

在现有可覆盖属性区域加入：

```swift
var currentVersionTitleText: String { "current_target_version".localizedString }
var currentVersionDisplayText: String { displayedCurrentTargetVersion ?? "none".localizedString }
var createsUIBeforeCloudRequest: Bool { false }
var requiresAdditionalFirmwareReload: Bool { false }

func loadAdditionalFirmwareData() {}

func refreshFirmwareUI() {
    guard headerView != nil else { return }
    updateUI()
}
```

这些默认值不得改变历史固件页面：没有附加请求、标题与 None 逻辑保持现状、UI 仍可在云端请求完成后创建。

- [ ] **Step 4: 让 WiFi 页面可立即创建 UI 并触发附加加载**

将 `viewDidLoad()` 的请求部分调整为：

```swift
if createsUIBeforeCloudRequest {
    setupUI()
    updateUI()
}
loadCloudFirmwareRequest()
loadAdditionalFirmwareData()
```

保留云端 completion 中现有的 `if headerView == nil { setupUI() }`，供默认页面延迟创建 UI。

- [ ] **Step 5: 让 Refresh 同时触发附加请求**

将 `reloadBtnAction()` 调整为：

```swift
@objc private func reloadBtnAction() {
    loadCloudFirmwareRequest()
    loadAdditionalFirmwareData()
}
```

WiFi 的 `loadCloudFirmwareRequest()` 会同步清空旧 `serverData`，随后附加请求进入 loading 并触发 UI 刷新，因此旧按钮状态不会残留。

- [ ] **Step 6: 把 Current version 文案和附加失败接入 updateUI**

在 `updateUI()` 开头统一设置：

```swift
currentVersionLabel.text = currentVersionDisplayText
```

保留 `displayedCurrentTargetVersion` 是否为 nil 对 delete button 和 trailing constraint 的现有判断，但删除其中对 label 重复赋值的两处代码。

在 `updateUI()` 完成现有 server/no-server 分支后加入：

```swift
if requiresAdditionalFirmwareReload {
    stateLabel.isHidden = true
    reloadBtn.isHidden = false
    downloadBtn.isEnabled = false
}
```

将 `setupUI()` 中标题初始化改为：

```swift
currentVersionTitleLabel = UILabel(text: currentVersionTitleText, textColor: TextBlack_Color, fontSize: 14)
```

- [ ] **Step 7: 运行契约与主 target 编译**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：脚本继续失败于尚未实现的 WiFi 子类契约，但共享 hook 断言通过；SunSmart build 必须成功。

---

### Task 3: 实现 WiFi Current version 状态机与联合版本比较

**Files:**
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Task 1 SDK interfaces、Task 2 shared hooks、`Node.sunricherVendorModel`。
- Produces: node-scoped `43 14` 查询、loading/loaded/failed 状态与严格升级资格。

- [ ] **Step 1: 在脚本加入 WiFi 状态机红灯契约**

加入：

```bash
rg -n 'import NordicSigMeshSDK' "$wifi" >/dev/null || fail "WiFi firmware page must import SDK"
rg -n 'private enum CurrentVersionState' "$wifi" >/dev/null || fail "missing current version state"
rg -n 'private let node: Node' "$wifi" >/dev/null || fail "WiFi firmware page missing target node"
rg -n 'private var currentVersionRequestID: Int = 0' "$wifi" >/dev/null || fail "missing stale callback guard"
rg -n 'init\(node: Node\)' "$wifi" >/dev/null || fail "WiFi firmware page initializer must require node"
rg -n 'override var currentVersionTitleText: String' "$wifi" >/dev/null || fail "WiFi page missing Current version title"
rg -n 'override var currentVersionDisplayText: String' "$wifi" >/dev/null || fail "WiFi page missing current version display state"
rg -n 'override var createsUIBeforeCloudRequest: Bool' "$wifi" >/dev/null || fail "WiFi page must create UI before requests complete"
rg -n 'override var requiresAdditionalFirmwareReload: Bool' "$wifi" >/dev/null || fail "WiFi page missing device failure refresh state"
rg -n 'override func loadAdditionalFirmwareData\(\)' "$wifi" >/dev/null || fail "WiFi page missing firmware version query"
rg -n 'SunricherVendorGet\(function: \.wifiGatewayFirmwareVersion\)' "$wifi" >/dev/null || fail "WiFi page does not send 43 14"
rg -n 'timeout: 10' "$wifi" >/dev/null || fail "WiFi firmware query must use 10-second Mesh timeout"
rg -n 'currentVersionRequestID == requestID' "$wifi" >/dev/null || fail "WiFi page does not reject stale callbacks"
rg -n 'case \.wifiGatewayFirmwareVersion\(\.success\(let version\)\)' "$wifi" >/dev/null || fail "WiFi page does not consume typed version result"
rg -n 'compare\(currentVersion, options: \.numeric\) == \.orderedDescending' "$wifi" >/dev/null || fail "WiFi page missing numeric version comparison"
```

删除旧断言：

```bash
rg -n 'return type\.serverData\?\.version' "$wifi" >/dev/null || fail "WiFi target version must come from current server result"
wifi_true_override_count=$(grep -Fc 'return true' "$wifi")
[ "$wifi_true_override_count" -eq 2 ] || fail "WiFi reset and availability overrides must both return true"
```

- [ ] **Step 2: 运行契约并确认红灯**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected：FAIL 于 `WiFi firmware page must import SDK` 或 `missing current version state`。

- [ ] **Step 3: 引入 node 与 CurrentVersionState**

在 WiFi controller 中加入 SDK import、状态和 initializer：

```swift
import NordicSigMeshSDK

private enum CurrentVersionState {
    case loading
    case loaded(String)
    case failed
}

private let node: Node
private var currentVersionState: CurrentVersionState = .loading
private var currentVersionRequestID: Int = 0

init(node: Node) {
    self.node = node
    super.init(
        type: FirmwareUpdateTypeData(
            productId: 0x2721,
            targetVersion: nil,
            nodes: [node]
        )
    )
}

required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
}
```

删除原来的无参数 `convenience init()`。

- [ ] **Step 4: 覆盖 Current version UI hooks**

加入：

```swift
override var currentVersionTitleText: String {
    return "current_version".localizedString
}

override var currentVersionDisplayText: String {
    switch currentVersionState {
    case .loading:
        return "Loading...".localizedString
    case .loaded(let version):
        return version
    case .failed:
        return "failed".localizedString
    }
}

override var displayedCurrentTargetVersion: String? {
    guard case .loaded(let version) = currentVersionState else { return nil }
    return version
}

override var createsUIBeforeCloudRequest: Bool {
    return true
}

override var requiresAdditionalFirmwareReload: Bool {
    guard case .failed = currentVersionState else { return false }
    return true
}
```

保留 `resetsServerFirmwareBeforeCloudRequest = true`，删除原来无条件 `return true` 的 `isNewServerFirmwareAvailable`。

- [ ] **Step 5: 实现实时查询和 stale callback 防护**

加入：

```swift
override func loadAdditionalFirmwareData() {
    currentVersionRequestID += 1
    let requestID = currentVersionRequestID
    currentVersionState = .loading
    refreshFirmwareUI()

    guard node.state,
          node.isKeybindComplete,
          let vendorModel = node.sunricherVendorModel else {
        currentVersionState = .failed
        refreshFirmwareUI()
        return
    }

    MeshAPI.sendMessage(
        message: SunricherVendorGet(function: .wifiGatewayFirmwareVersion),
        model: vendorModel,
        timeout: 10
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self, self.currentVersionRequestID == requestID else { return }
            guard let status = response as? SunricherVendorStatus,
                  case .wifiGatewayFirmwareVersion(.success(let version)) = status.status.parameters else {
                self.currentVersionState = .failed
                self.refreshFirmwareUI()
                return
            }
            self.currentVersionState = .loaded(version)
            self.refreshFirmwareUI()
        }
    }
}
```

`currentVersionRequestID` 确保 Refresh 后的旧 callback 不能覆盖新请求状态。

- [ ] **Step 6: 实现版本规范化与联合比较**

加入：

```swift
override func isNewServerFirmwareAvailable(_ serverData: FirmwareServerData) -> Bool {
    guard let currentVersion = displayedCurrentTargetVersion.flatMap(normalizedVersion),
          let newVersion = normalizedVersion(serverData.version) else {
        return false
    }
    return newVersion.compare(currentVersion, options: .numeric) == .orderedDescending
}

private func normalizedVersion(_ version: String) -> String? {
    let normalized: String
    if version.first == "v" || version.first == "V" {
        normalized = String(version.dropFirst())
    } else {
        normalized = version
    }
    return normalized.isEmpty ? nil : normalized
}
```

不得 trim、补齐版本段或定义 prerelease 权重；只执行已确认的单个 `v/V` 前缀移除。

- [ ] **Step 7: 运行聚焦契约**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected：失败推进到尚未修改的菜单 initializer 或本地化契约；SDK、shared hooks 和 WiFi state assertions 均通过。

---

### Task 4: 接通菜单入口、国际化与最终页面契约

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Task 3 的 `WiFiFirmwareUpdateViewController.init(node:)`。
- Produces: 当前 node 的唯一入口与双语 `current_version` 文案。

- [ ] **Step 1: 更新入口与国际化红灯契约**

将脚本旧入口断言：

```bash
rg -n 'let controller = WiFiFirmwareUpdateViewController\(\)' "$gateway" >/dev/null || fail "WiFi DFU menu must create the WiFi firmware controller"
```

替换为：

```bash
rg -n 'let controller = WiFiFirmwareUpdateViewController\(node: self\.node\)' "$gateway" >/dev/null || fail "WiFi DFU menu must pass current node"
grep -Fq '"current_version" = "Current version";' "$localizable_en" || fail "missing English Current version localization"
grep -Fq '"current_version" = "当前版本";' "$localizable_zh" || fail "missing Chinese Current version localization"
```

- [ ] **Step 2: 运行契约并确认红灯**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected：FAIL 于 `WiFi DFU menu must pass current node`。

- [ ] **Step 3: 把当前 node 传入页面**

在 `WiFiGatewayViewController.moreClick()` 中改为：

```swift
let controller = WiFiFirmwareUpdateViewController(node: self.node)
self.navigationController?.pushViewController(controller, animated: true)
```

只修改 WiFi DFU 回调，不改变 Delete、Information、Identify 或隐藏的 Diagnosis。

- [ ] **Step 4: 新增双语 Current version**

在两个本地化文件相同语义区域加入：

```text
"current_version" = "Current version";
```

```text
"current_version" = "当前版本";
```

继续复用现有 `Loading...` 和 `failed` key，不新增重复文案。

- [ ] **Step 5: 运行聚焦脚本与 diff 检查**

Run：

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected：脚本输出 `PASS: WiFi Gateway firmware update static checks`；`git diff --check` 无输出。

- [ ] **Step 6: 构建 SunSmart 主 target**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：退出码 `0`，结尾包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 检查并提交 App 核心实现**

Run：

```bash
git diff -- SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings scripts/check_wifi_gateway_firmware_update.sh
git add SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: show wifi firmware current version"
```

Expected：生成一个只包含上述六个文件的 App 提交。

---

### Task 5: 完成回归、四 target 构建与实施总结

**Files:**
- Test: `scripts/check_gateway_activate_header_layout.sh`
- Test: `scripts/check_gateway_associated_spaces_deferred_save.sh`
- Test: `scripts/check_wifi_gateway_apn_removed.sh`
- Test: `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`
- Test: `scripts/check_wifi_gateway_info_rows_hidden.sh`
- Test: `scripts/check_wifi_gateway_menu_icons.sh`
- Test: `scripts/check_wifi_gateway_network_connectivity.sh`
- Test: `scripts/check_wifi_gateway_repair_recovery.sh`
- Test: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Test: `scripts/check_wifi_gateway_sig_mesh_status_header.sh`
- Test: `scripts/check_wifi_gateway_wifi_status_header.sh`
- Create: `docs/260714_1514_wifi_firmware_current_version_implementation_summary.md`

**Interfaces:**
- Consumes: Tasks 1-4 的 SDK 和 App commits。
- Produces: 聚焦契约、SDK Demo、四品牌 iPhoneOS build 证据和最终总结。

- [ ] **Step 1: 逐个运行 Gateway/WiFi Gateway 静态回归**

Run：

```bash
bash scripts/check_gateway_activate_header_layout.sh
bash scripts/check_gateway_associated_spaces_deferred_save.sh
bash scripts/check_wifi_gateway_apn_removed.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_info_rows_hidden.sh
bash scripts/check_wifi_gateway_menu_icons.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected：每个脚本输出各自的 `PASS`，无 FAIL。

- [ ] **Step 2: 再次验证 SDK Demo iPhoneOS build**

Run：

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Working directory：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected：`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 串行验证四个 App target**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：四条命令分别以 `** BUILD SUCCEEDED **` 结束。必须串行运行，避免共享 DerivedData 的 build database lock。

- [ ] **Step 4: 检查两个仓库状态与最终差异**

Run：

```bash
git status --short
git diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected：除待创建的 implementation summary 外，App 仓库无未提交业务改动；SDK 仓库干净。

- [ ] **Step 5: 写实施总结**

创建 `docs/260714_1514_wifi_firmware_current_version_implementation_summary.md`，至少记录：

- SDK typed result 与严格 parser 的最终接口。
- App loading/loaded/failed 状态机与 10 秒 Mesh timeout。
- Refresh 双请求和 stale callback 防护。
- `v/V` + `.numeric` 比较结果。
- focused tests 的真实结果；若 `swift test` 被 UIKit 阻断，记录完整 blocker，但不得写成测试通过。
- SDK Demo 与四个 App target 的实际 build 结果。
- SDK commit 与 App commit hash。
- 真实 DFU 仍不在范围内。

- [ ] **Step 6: 提交总结文档**

Run：

```bash
git add docs/260714_1514_wifi_firmware_current_version_implementation_summary.md
git commit -m "docs: summarize wifi firmware current version"
git status --short
```

Expected：总结提交成功；App 工作区最终干净。

## Final Acceptance Checklist

- [ ] SDK 请求 payload 精确为 `43 14`。
- [ ] success、四个已知失败 ret、未知 ret 和全部 malformed payload 有测试覆盖。
- [ ] response matching 不会误接其它 Gateway subcode 或 source。
- [ ] 页面进入后立即显示 `Current version: Loading...`。
- [ ] 查询成功展示实时版本；失败展示 `Failed`，旧值不会残留。
- [ ] Refresh 同时重新请求 New version 与 Current version。
- [ ] 旧 callback 不能覆盖新一轮 Refresh 状态。
- [ ] 仅 New version 严格高于 Current version 时 `UPGRADE` 可用。
- [ ] `UPGRADE` 仍为 `under_development`。
- [ ] 所有新文案均有 English 与简体中文。
- [ ] SDK Demo 与四个 App target 的 Debug iPhoneOS 构建通过。
- [ ] 两个仓库无非预期改动。
