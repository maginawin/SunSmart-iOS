# WiFi Gateway DFU App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This project explicitly defaults to Inline Execution; do not use subagents unless the user separately requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 更新 NordicSigMeshSDK 的新版 `43 10`，并在 WiFi Firmware Update 页面实现可恢复、可轮询、支持主动上报的真实 WiFi 固件升级流程。

**Architecture:** SDK 只保留 URL + firmware ID metadata 和协议编解码；App 使用独立 URL builder、状态映射、session store 和 coordinator 管理 OTA。`WiFiFirmwareUpdateViewController` 绑定 coordinator 到共享固件页面，`WiFiFirmwareUpdatingView` 只渲染状态，BLE/Mesh 页面通过父类默认 hook 保持原行为。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、XCTest、UserDefaults、Bash focused contracts、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复、计划、总结使用简体中文；UI 文案使用英文并提供 English/zh-CN 本地化。
- 新版 `43 10` 只包含 URL 和 firmware ID；完整业务 payload 长度为 `5 + url_len + firmware_id_len`，最大 256 字节。
- OTA URL 必须基于 `UserData.currentServerRegion.baseURL`，scheme 改为 HTTP，路径固定 `/sitespace/ota/download`，query 为 `key=filename`。
- firmware ID 只移除最多一个前导 `v/V`。
- `downloading`、`updating` 均显示 disabled `CANCEL`；本期不实现取消或伪取消。
- `43 10 ret=0x04` 使用 `Unable to connect to the server`。
- Mesh 请求串行；页面恢复先查 `43 11`，没有匹配活动 session 才查 `43 14`。
- 不新增 Auth 信息，不修改服务端，不修改 BLE/Mesh OTA 行为，不新增 App unit-test target。
- UI 指定间距不使用 `SCRX/SCRY`；新增或修改用户文案必须同步 English 和简体中文。
- App 验证直接使用 generic iPhoneOS `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。

---

### Task 1: 将 NordicSigMeshSDK `43 10` 同步为 URL + firmware ID

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`

**Interfaces:**
- Produces: `public init(url: String, firmwareID: String) throws`
- Produces: `WiFiGatewayDFUMetadata.url`, `firmwareID`, internal `urlBytes`, `firmwareIDBytes`
- Preserves: `SunricherVendorSet(function: .wifiGatewayDFUStart(metadata))`
- Preserves: `WiFiGatewayDFUStartResult`、`WiFiGatewayDFUStatusResult`、`WiFiGatewayFirmwareVersionResult`

- [ ] **Step 1: 先把 SDK 测试改成新版 initializer 和精确 payload**

将 encoding 测试的核心改为：

```swift
func testWiFiGatewayDFUStartEncoding() throws {
    let metadata = try WiFiGatewayDFUMetadata(
        url: "http://fw.example.com/wifi.bin",
        firmwareID: "0.4.0"
    )
    let expected = Data([0x43, 0x10, 0x1E, 0x00])
        + Data("http://fw.example.com/wifi.bin".utf8)
        + Data([0x05])
        + Data("0.4.0".utf8)
    XCTAssertEqual(
        SunricherVendorSet(function: .wifiGatewayDFUStart(metadata)).parameters,
        expected
    )
}
```

长度边界改为 firmware ID 长 5 时 URL 最大 246 字节：

```swift
let maximumURL = "http://" + String(repeating: "a", count: 239)
let metadata = try WiFiGatewayDFUMetadata(url: maximumURL, firmwareID: "0.4.0")
XCTAssertEqual(SunricherVendorSet(function: .wifiGatewayDFUStart(metadata)).parameters?.count, 256)

let oversizedURL = "http://" + String(repeating: "a", count: 240)
XCTAssertThrowsError(try WiFiGatewayDFUMetadata(url: oversizedURL, firmwareID: "0.4.0")) {
    XCTAssertEqual($0 as? WiFiGatewayDFUMetadataValidationError, .payloadTooLarge(257))
}
```

删除 SHA256/size 测试，保留 HTTPS、双引号、CR/LF、非 ASCII、firmware ID 0/33 字节测试。

- [ ] **Step 2: 运行 focused SDK 测试，确认 RED**

Run:

```bash
swift test --filter WiFiGatewayVendorMessageTests
```

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: 编译失败，提示 `WiFiGatewayDFUMetadata` 仍要求 `sha256` 和 `size`。

- [ ] **Step 3: 最小化更新 SDK metadata 和编码**

将 validation error 收口为：

```swift
public enum WiFiGatewayDFUMetadataValidationError: Error, Equatable {
    case invalidURLScheme
    case invalidCharacter(field: WiFiGatewayDFUMetadataField, byte: UInt8)
    case invalidFirmwareIDLength(Int)
    case payloadTooLarge(Int)
}
```

将 metadata 实现收口为：

```swift
public struct WiFiGatewayDFUMetadata: Equatable {
    public let url: String
    public let firmwareID: String
    let urlBytes: [UInt8]
    let firmwareIDBytes: [UInt8]

    public init(url: String, firmwareID: String) throws {
        guard url.hasPrefix("http://") else {
            throw WiFiGatewayDFUMetadataValidationError.invalidURLScheme
        }
        let urlBytes = Array(url.utf8)
        try Self.validateASCII(urlBytes, field: .url)

        let firmwareIDBytes = Array(firmwareID.utf8)
        guard (1...32).contains(firmwareIDBytes.count) else {
            throw WiFiGatewayDFUMetadataValidationError.invalidFirmwareIDLength(firmwareIDBytes.count)
        }
        try Self.validateASCII(firmwareIDBytes, field: .firmwareID)

        let payloadLength = 5 + urlBytes.count + firmwareIDBytes.count
        guard payloadLength <= 256 else {
            throw WiFiGatewayDFUMetadataValidationError.payloadTooLarge(payloadLength)
        }

        self.url = url
        self.firmwareID = firmwareID
        self.urlBytes = urlBytes
        self.firmwareIDBytes = firmwareIDBytes
    }
}
```

将 Set 编码改为：

```swift
case .wifiGatewayDFUStart(let metadata):
    return data
        + UInt16(metadata.urlBytes.count)
        + Data(metadata.urlBytes)
        + UInt8(metadata.firmwareIDBytes.count)
        + Data(metadata.firmwareIDBytes)
```

- [ ] **Step 4: 运行 SDK tests 和 diff 检查，确认 GREEN**

Run:

```bash
swift test --filter WiFiGatewayVendorMessageTests
git diff --check
```

Expected: `WiFiGatewayVendorMessageTests` 全部通过，diff check 无输出。

- [ ] **Step 5: 构建 SDK Demo generic iPhoneOS**

Run:

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 提交 SDK**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git commit -m "feat: update wifi gateway dfu metadata"
```

---

### Task 2: 为 URL builder 和 state model 建立 focused contract RED

**Files:**
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Task 1 新版 `WiFiGatewayDFUMetadata(url:firmwareID:)`
- Produces: Task 3 数据层的静态验收契约

- [ ] **Step 1: 在 contract 中声明新增文件和关键行为**

增加本任务文件变量：

```bash
builder="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUMetadataBuilder.swift"
state="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift"
```

增加断言，至少覆盖：

```bash
[ -f "$builder" ] || fail "missing WiFi firmware DFU metadata builder"
[ -f "$state" ] || fail "missing WiFi firmware DFU state model"
rg -n 'UserData\.currentServerRegion\.baseURL' "$builder" >/dev/null || fail "URL builder must use current app region"
rg -n 'components\.scheme = "http"' "$builder" >/dev/null || fail "URL builder must force HTTP"
rg -n '/sitespace/ota/download' "$builder" >/dev/null || fail "URL builder missing OTA download path"
rg -n 'URLQueryItem\(name: "key", value: filename\)' "$builder" >/dev/null || fail "URL builder must encode filename as key query"
rg -n 'enum WiFiFirmwareUpdatingKind' "$state" >/dev/null || fail "missing WiFi firmware UI state"
rg -n 'struct WiFiFirmwareDFUSession' "$state" >/dev/null || fail "missing WiFi firmware persisted session"
```

本任务保留旧 placeholder 断言，直到 Task 7 先将其替换为真实 action 的 RED contract。

- [ ] **Step 2: 运行 contract，确认 RED**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: 首个失败为 `missing WiFi firmware DFU metadata builder`。

---

### Task 3: 实现 OTA URL、firmware ID、UI state 和 session store

**Files:**
- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUMetadataBuilder.swift`
- Create: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Produces: `WiFiFirmwareDFUMetadataBuilder.makeURL(filename:) throws -> String`
- Produces: `WiFiFirmwareDFUMetadataBuilder.firmwareID(version:) throws -> String`
- Produces: `WiFiFirmwareUpdatingState`、`WiFiFirmwarePrimaryActionPresentation`
- Produces: `WiFiFirmwareDFUSessionStore.load/save/remove`
- Produces: `WiFiFirmwareDFUStateMapper.map(status:targetFirmwareID:)`

- [ ] **Step 1: 创建 URL builder 和版本规范化**

实现固定接口：

```swift
enum WiFiFirmwareDFUMetadataBuilderError: Error, Equatable {
    case invalidRegionURL
    case invalidDownloadURL
    case invalidFirmwareID
}

struct WiFiFirmwareDFUMetadataBuilder {
    static let downloadPath = "/sitespace/ota/download"

    static func makeURL(filename: String, baseURL: URL = UserData.currentServerRegion.baseURL) throws -> String {
        guard !filename.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WiFiFirmwareDFUMetadataBuilderError.invalidRegionURL
        }
        components.scheme = "http"
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + downloadPath
        components.queryItems = [URLQueryItem(name: "key", value: filename)]
        guard let value = components.url?.absoluteString else {
            throw WiFiFirmwareDFUMetadataBuilderError.invalidDownloadURL
        }
        return value
    }

    static func firmwareID(version: String) throws -> String {
        let value = (version.first == "v" || version.first == "V") ? String(version.dropFirst()) : version
        guard !value.isEmpty else { throw WiFiFirmwareDFUMetadataBuilderError.invalidFirmwareID }
        return value
    }
}
```

SDK metadata 负责最终 HTTP、ASCII、1...32 和 256 字节校验，App builder 不复制协议校验。

- [ ] **Step 2: 创建 App UI state、协议映射和 Codable session**

状态接口固定为：

```swift
enum WiFiFirmwareUpdatingKind: String, Codable {
    case connFailedTimeout
    case connFailedServerUnable
    case downloading
    case downloadFailed
    case updating
    case upgradeFailed
    case upgradeComplete
}

struct WiFiFirmwareUpdatingState: Equatable, Codable {
    let kind: WiFiFirmwareUpdatingKind
    let percent: Int
}

enum WiFiFirmwarePrimaryAction: Equatable {
    case upgrade
    case retry
    case cancelDisabled
    case done
}

struct WiFiFirmwarePrimaryActionPresentation: Equatable {
    let titleKey: String
    let isEnabled: Bool
    let action: WiFiFirmwarePrimaryAction
}
```

Mapper 必须实现以下 switch：

```swift
static func map(status: WiFiGatewayDFUStatus, targetFirmwareID: String) -> WiFiFirmwareUpdatingState? {
    guard status.firmwareID == targetFirmwareID else { return nil }
    let percent = min(100, max(0, Int(status.percent)))
    switch status.stage {
    case .downloading:
        return .init(kind: .downloading, percent: percent)
    case .verifying, .verifyOK, .rebooting, .recovering, .versionCheck:
        return .init(kind: .updating, percent: percent)
    case .verifyFail:
        return .init(kind: .downloadFailed, percent: percent)
    case .success:
        return .init(kind: .upgradeComplete, percent: 100)
    case .failed:
        switch status.code {
        case .noNetwork, .http, .sizeMismatch:
            return .init(kind: .downloadFailed, percent: percent)
        default:
            return .init(kind: .upgradeFailed, percent: percent)
        }
    case .timeout, .reserved(_):
        return .init(kind: .upgradeFailed, percent: percent)
    case .idle:
        return nil
    }
}
```

Session 使用 Codable 保存 target、accepted、最后 UI state、module version、terminal consumed。stage/code identifier 使用 App 自有 String 字段，分别通过 exhaustive switch 映射为 `idle/downloading/verifying/verifyOK/verifyFail/rebooting/recovering/versionCheck/success/timeout/failed/reserved:<raw>` 和 `none/noNetwork/http/sizeMismatch/verify/versionRejected/noPartition/noMemory/otaBegin/otaWrite/otaEnd/setBoot/internalError/triggerError/triggerTimeout/triggerBusyTimeout/otaTimeout/protocolError/versionProtocol/versionMissing/versionQueryError/versionQueryTimeout/versionMismatch/recoveryTimeout/reserved:<raw>`；不得依赖不可 Codable 的 SDK enum。store key 为：

```swift
"wifi_firmware_dfu_session.\(networkUUID.uuidString).\(nodeAddress)"
```

Session 和 Store 接口固定为：

```swift
struct WiFiFirmwareDFUSession: Codable, Equatable {
    let targetFirmwareID: String
    var accepted: Bool
    var lastState: WiFiFirmwareUpdatingState?
    var stageIdentifier: String?
    var codeIdentifier: String?
    var moduleVersion: String?
    var terminalConsumed: Bool
}

struct WiFiFirmwareDFUSessionStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(networkUUID: UUID, nodeAddress: UInt16) -> WiFiFirmwareDFUSession?
    func save(_ session: WiFiFirmwareDFUSession, networkUUID: UUID, nodeAddress: UInt16)
    func remove(networkUUID: UUID, nodeAddress: UInt16)
}
```

编码或解码失败时返回 nil/移除损坏值，不让持久化错误阻断页面。

- [ ] **Step 3: 给共享云端版本解析增加窄 hook**

父类新增：

```swift
func normalizedServerFirmwareVersion(_ rawVersion: String) -> String {
    rawVersion.replacingOccurrences(of: "v", with: "")
}
```

构造 `FirmwareServerData` 时使用该 hook。WiFi 子类 override：

```swift
override func normalizedServerFirmwareVersion(_ rawVersion: String) -> String {
    (try? WiFiFirmwareDFUMetadataBuilder.firmwareID(version: rawVersion)) ?? rawVersion
}
```

这样 BLE/Mesh 保持现有逻辑，WiFi 只去掉一个前导 v/V。

- [ ] **Step 4: 将两个新 Model 文件加入四个 target**

在 Firmware/Model group 增加两个 PBXFileReference，并为 SunSmart、Archipelago、SLG Sync Plus、SylSmart 各增加 PBXBuildFile 和 Sources entry。不得修改其它 target 设置。

- [ ] **Step 5: 运行 focused contract，确认数据层 GREEN**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: `PASS: WiFi Gateway firmware update static checks`。此时 coordinator/view/integration 的断言尚未加入。

- [ ] **Step 6: 提交独立数据层**

```bash
git add SunSmart/Main/Firmware/Model/WiFiFirmwareDFUMetadataBuilder.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart.xcodeproj/project.pbxproj scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: add wifi firmware dfu state model"
```

---

### Task 4: 实现串行 WiFi DFU coordinator

**Files:**
- Create: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Task 1 `WiFiGatewayDFUMetadata(url:firmwareID:)`
- Consumes: Task 3 builder、mapper、session store
- Produces: `WiFiFirmwareDFUCoordinator.Event`
- Produces: `activate()`、`deactivate()`、`start(filename:version:)`、`consumeSuccess()`、`refresh()`

- [ ] **Step 1: 先增加 coordinator contract 并验证 RED**

在 script 新增 coordinator 文件变量及新版 SDK metadata、observer add/remove、2/5/10 秒调度、generation、session store 的断言。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL at `missing WiFi firmware DFU coordinator`。

- [ ] **Step 2: 定义 coordinator 事件和生命周期接口**

```swift
final class WiFiFirmwareDFUCoordinator {
    enum Event {
        case loadingStart(Bool)
        case currentVersionLoading
        case currentVersion(String)
        case currentVersionFailed
        case updateState(WiFiFirmwareUpdatingState)
        case idle
        case confirmedVersion(String)
    }

    var onEvent: ((Event) -> Void)?

    func activate()
    func deactivate()
    func refresh()
    func start(filename: String, version: String)
    func consumeSuccess()
}
```

Initializer 必须接收 `Node` 和可注入的 `WiFiFirmwareDFUSessionStore`；内部从 node 获取 vendor model、unicast address 和当前 mesh UUID。

- [ ] **Step 3: 实现 observer、generation 和单请求串行门**

Coordinator 保存：

```swift
private var observerID: UUID?
private var pollWorkItem: DispatchWorkItem?
private var generation = 0
private var requestInFlight = false
private var consecutiveQueryFailures = 0
private var isActive = false
private var session: WiFiFirmwareDFUSession?
```

`activate()` 只注册一次 global observer，observer 必须校验：

```swift
guard source == node.primaryUnicastAddress,
      MeshNetworkManager.instance.meshNetwork?.uuid == networkUUID,
      let status = message as? SunricherVendorStatus,
      case .wifiGatewayDFUStatus(.success(let value)) = status.status.parameters else { return }
```

`deactivate()` 取消 work item、移除 observer、generation 加一，但不删除活动 session。

- [ ] **Step 4: 实现页面恢复顺序**

`activate/refresh` 的顺序固定为：

```swift
queryDFUStatus { [weak self] result in
    guard let self else { return }
    if self.restoreMatchingSession(from: result) {
        self.scheduleNextPoll(after: 2)
    } else {
        self.queryCurrentVersion()
    }
}
```

没有本地 accepted session 时，设备的旧终态不进入 UI。查询失败也继续 `43 14`。

- [ ] **Step 5: 实现 start ACK 映射**

`start(filename:version:)` 必须：

1. generation 加一并暂停旧轮询。
2. 发出 `.loadingStart(true)`。
3. builder 构造 URL/firmware ID。
4. SDK metadata 校验。
5. 用 `MeshAPI.sendMessage(... timeout: 10)` 发送 `43 10`。

ACK 映射固定为：

```swift
case .accepted:
    saveNewAcceptedSession()
    emit(.loadingStart(false))
    queryAndPollImmediately()
case .internetUnavailable:
    emit(.loadingStart(false))
    emit(.updateState(.init(kind: .connFailedServerUnable, percent: 0)))
case .invalidParameters, .busy, .internalError, .reserved(_):
    emit(.loadingStart(false))
    emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
```

nil、错误 message type 或不匹配 status 映射为 `connFailedTimeout`。metadata 本地失败映射为 `upgradeFailed`，不得发送 Mesh 命令。

- [ ] **Step 6: 实现轮询、失败降频和终态**

- 正常 interval 2 秒、query timeout 5 秒。
- 只有 `requestInFlight == false` 才能查询。
- 连续 3 次查询失败后使用 10 秒 interval。
- 合法匹配状态将失败计数归零。
- 主动上报和轮询调用同一个 `handle(status:)`。
- `idle`、mismatch、终态、DONE 停止 poll。
- success 使用 moduleVersion，否则使用 target firmware ID，发出 `confirmedVersion`。
- active session 的 ret!=0/解析失败保留最后状态，不发出设备失败终态。

- [ ] **Step 7: 将 coordinator 加入四个 target 并运行 contract**

在 Firmware/Controller group 增加 file reference、四个 build file 和四个 Sources entry。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: coordinator 相关断言通过，下一失败指向 updating view 或页面 integration。

- [ ] **Step 8: 提交 coordinator**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift SunSmart.xcodeproj/project.pbxproj scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: add wifi firmware dfu coordinator"
```

---

### Task 5: 实现 `WiFiFirmwareUpdatingView` 和本地化

**Files:**
- Create: `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: `WiFiFirmwareUpdatingState`
- Produces: `func configure(state: WiFiFirmwareUpdatingState)`

- [ ] **Step 1: 先增加 view/localization contract 并验证 RED**

在 script 新增 updating view 文件变量，断言全部 UI kind、两张既有图片名、不使用 `SCRX/SCRY`、新增 key 在两种语言存在。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL at `missing WiFi firmware updating view`。

- [ ] **Step 2: 新增/复用本地化 key**

复用 `cancel`、`done`、`Loading...`，新增：

```text
wifi_firmware_upgrade_again
wifi_firmware_connection_failed
wifi_firmware_communication_timeout
wifi_firmware_server_unable
wifi_firmware_downloading
wifi_firmware_updating
wifi_firmware_download_failed
wifi_firmware_upgrade_failed
wifi_firmware_upgrade_complete
```

English 值严格使用 Figma 文案；简体中文分别使用“再次升级、连接失败、通信超时、无法连接服务器、正在下载...、正在升级...、下载失败、升级失败、升级完成！”。

- [ ] **Step 3: 创建纯渲染 View**

View 内部包含 background progress、foreground progress、percent label、result horizontal stack、icon 和 detail label。核心接口：

```swift
final class WiFiFirmwareUpdatingView: UIView {
    func configure(state: WiFiFirmwareUpdatingState) {
        let percent = min(100, max(0, state.percent))
        percentLabel.text = "\(percent)%"
        progressWidthConstraint?.update(offset: progressContainer.bounds.width * CGFloat(percent) / 100)
        applyContent(for: state.kind)
    }
}
```

布局要求：

- progress 高 2 pt。
- percent label 在右侧。
- 失败 icon `alert_failed`，成功 icon `sync_success_small`。
- downloading/updating 无 icon。
- `connFailedTimeout` 显示两行 `Connection failed` + `Communication timeout`。
- `connFailedServerUnable` 显示 `Connection failed` + `Unable to connect to the server`。
- 不使用 `SCRX/SCRY`。
- 所有文案只取 localization key。

- [ ] **Step 4: 加入四个 target 并校验资源复用**

在 Firmware/View group 增加 file reference、四个 build file 和 Sources entry。不得新增图片资源；使用已存在的 `alert_failed` 和 `sync_success_small`。

- [ ] **Step 5: 运行 contract 和 plist lint**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: view/localization checks 通过，plist 均 `OK`。

- [ ] **Step 6: 提交 View**

```bash
git add SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: add wifi firmware updating view"
```

---

### Task 6: 给共享固件页面增加滚动容器和动态 action hook

**Files:**
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Produces: `var usesScrollableFirmwareContent: Bool { false }`
- Produces: `func makeAdditionalFirmwareContentView() -> UIView? { nil }`
- Produces: `var additionalFirmwareContentTopSpacing: CGFloat { 0 }`
- Produces: `var additionalFirmwareContentHorizontalInset: CGFloat { 0 }`
- Produces: `func setAdditionalFirmwareContentHidden(_ hidden: Bool)`
- Produces: `func updateFirmwarePrimaryAction(titleKey:isEnabled:)`
- Produces: `func applyAdditionalFirmwareUIState()`

- [ ] **Step 1: 先增加 parent hook contract 并验证 RED**

Contract 增加对上述七个 hook 的断言，并断言父类默认 `usesScrollableFirmwareContent == false`、horizontal inset 为 0。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL at `missing scrollable firmware content hook`。

- [ ] **Step 2: 重排 setupUI，但保持默认页面行为**

父类新增可选 `contentScrollView` 和 `pageContentView`：

- 默认 hook 为 false 时，现有 header/version/current constraints 保持原 root view 关系。
- WiFi hook 为 true 时，scroll view 约束为 safe area top 到 bottomView top，content view width 等于 scroll view。
- header、new version、current version 都放入 content view。
- additional view 接在 current version 下方。
- content bottom 接 additional view bottom；无 additional view 时接 current version bottom。
- horizontal inset 使用 hook；WiFi 后续 override 为 36 pt。
- 保存 additional view 的 top constraint 和 `height == 0` collapse constraint。隐藏时 top offset 更新为 0 并激活 collapse constraint；显示时 top offset 恢复 hook 值并停用 collapse constraint，让 View 内部约束计算真实高度。

不要改变现有数值缩放逻辑；只有新增 WiFi additional view spacing 使用固定 32 pt。

- [ ] **Step 3: 增加运行时按钮和子类最终覆盖 hook**

```swift
func updateFirmwarePrimaryAction(titleKey: String, isEnabled: Bool) {
    downloadBtn.setTitle(titleKey.localizedString, for: .normal)
    downloadBtn.isEnabled = isEnabled
}

func setAdditionalFirmwareContentHidden(_ hidden: Bool) {
    additionalFirmwareContentView?.isHidden = hidden
    additionalFirmwareContentTopConstraint?.update(offset: hidden ? 0 : additionalFirmwareContentTopSpacing)
    if hidden {
        additionalFirmwareContentCollapsedHeightConstraint?.activate()
    } else {
        additionalFirmwareContentCollapsedHeightConstraint?.deactivate()
    }
}

func applyAdditionalFirmwareUIState() {}
```

在父类 `updateUI()` 最后调用 `applyAdditionalFirmwareUIState()`，确保 cloud/current refresh 后 WiFi workflow 状态最终生效。父类默认为空。

- [ ] **Step 4: 运行原有 focused contract**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: parent 默认 hook 和现有 BLE/Mesh 断言继续通过。

- [ ] **Step 5: 提交共享页面 hook**

```bash
git add SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift scripts/check_wifi_gateway_firmware_update.sh
git commit -m "refactor: add wifi firmware page hooks"
```

---

### Task 7: 将 WiFi 页面接入 coordinator、状态 View 和按钮状态机

**Files:**
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Tasks 3–6 的 builder、state、coordinator、view、parent hooks
- Produces: 完整 UPGRADE / UPGRADE AGAIN / DONE 页面流程

- [ ] **Step 1: 将 placeholder contract 改成真实 integration contract，确认 RED**

删除旧 `under_development` 预期，新增 coordinator start、UPGRADE AGAIN、disabled CANCEL、DONE、scroll hook、32/36 pt 的断言。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL，指出 WiFi primary action 仍为 placeholder。

- [ ] **Step 2: 将 WiFi 页面布局 hook 接到 updating view**

```swift
private lazy var updatingView = WiFiFirmwareUpdatingView()

override var usesScrollableFirmwareContent: Bool { true }
override var additionalFirmwareContentTopSpacing: CGFloat { 32 }
override var additionalFirmwareContentHorizontalInset: CGFloat { 36 }
override func makeAdditionalFirmwareContentView() -> UIView? { updatingView }
```

父类通过 horizontal inset hook 给 updating view 左右固定 36 pt；默认调用 `setAdditionalFirmwareContentHidden(true)`，确保默认页面不留下 32/94 pt 空白。

- [ ] **Step 3: 用 coordinator 替换直接 `43 14` 和 placeholder**

删除 `currentVersionRequestID` 和 Controller 内直接 `MeshAPI.sendMessage`。新增：

```swift
private lazy var dfuCoordinator = WiFiFirmwareDFUCoordinator(node: node)
private var updatingState: WiFiFirmwareUpdatingState?
private var primaryAction: WiFiFirmwarePrimaryAction = .upgrade
```

`loadAdditionalFirmwareData()` 调用 coordinator activate/refresh。`viewWillAppear` activate，`viewWillDisappear` deactivate，deinit 再执行安全清理。

- [ ] **Step 4: 绑定 coordinator Event**

事件处理固定为：

- `.loadingStart(true)` → `XWHUDManager.showCustomHUD(withMessage: "Loading...".localizedString, view: view)`。
- `.loadingStart(false)` → `XWHUDManager.hideInView(with: view)`。
- `.currentVersionLoading` → Current version = Loading。
- `.currentVersion(value)` / `.confirmedVersion(value)` → Current version loaded，刷新版本比较。
- `.currentVersionFailed` → Current version Failed，New version 仍显示，UPGRADE disabled。
- `.updateState(value)` → 显示/configure updating view并应用按钮 presentation。
- `.idle` → 隐藏 updating view并回到版本比较。

所有 UI 更新 dispatch 到 main queue。

- [ ] **Step 5: 实现一个 selector 驱动四种 action**

```swift
@objc override func firmwarePrimaryAction() {
    switch primaryAction {
    case .upgrade, .retry:
        guard let serverData = type.serverData else { return }
        dfuCoordinator.start(filename: serverData.filename, version: serverData.version)
    case .done:
        dfuCoordinator.consumeSuccess()
    case .cancelDisabled:
        break
    }
}
```

`applyAdditionalFirmwareUIState()` 必须确保：

- default：沿用 Current/New version 比较结果和 `UPGRADE`。
- running：`CANCEL` disabled。
- failure：`UPGRADE AGAIN` enabled。
- complete：`DONE` enabled。

- [ ] **Step 6: DONE 后刷新 Current version 和默认 UI**

收到 confirmed version 时先更新 Current version；DONE 后清 session、隐藏状态 View、重新执行父类 updateUI。若 target 等于 New version，UPGRADE disabled。

- [ ] **Step 7: 更新 focused contract 到 GREEN**

Contract 必须删除 placeholder 预期，并断言：

- coordinator start 使用 `serverData.filename/version`。
- running 两态使用 disabled CANCEL。
- retry 使用 UPGRADE AGAIN。
- done 调用 `consumeSuccess()`。
- WiFi 使用 scroll hook 和 32/36 固定间距。
- current failed 仍显示 New version但 action disabled。

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: `PASS: WiFi Gateway firmware update static checks`。

- [ ] **Step 8: 提交页面接入**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: enable wifi gateway firmware upgrade"
```

---

### Task 8: 全量验证、实机交付矩阵和总结

**Files:**
- Create: `docs/260715_1443_wifi_gateway_dfu_app_implementation_summary.md`
- Verify: App、SDK、project、localization、scripts

**Interfaces:**
- Consumes: Tasks 1–7 完整实现
- Produces: 可审计的验证证据和交付总结

- [ ] **Step 1: 运行 SDK 最终测试**

```bash
swift test --filter WiFiGatewayVendorMessageTests
```

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: 全部通过。

- [ ] **Step 2: 运行全部 WiFi Gateway regression scripts**

依次运行：

```bash
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

Expected: 10/10 PASS。

- [ ] **Step 3: 校验工程、本地化和 diff**

```bash
plutil -lint SunSmart.xcodeproj/project.pbxproj
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: plutil 全部 OK；diff check 无输出。

- [ ] **Step 4: 直接构建四个 App scheme**

分别运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四次均 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 按 design spec 执行实机矩阵**

至少记录：版本比较、全部 `43 10` ret、start transport timeout、downloading/updating、download/upgrade failure、success、DONE、页面返回、App 重启、firmware ID mismatch。若当前没有可控网关状态，明确列出未覆盖项，不用模拟结果冒充实机证据。

- [ ] **Step 6: 写实现总结**

总结必须包含：

- SDK commit 与 App commits。
- 新 URL 规则和示例验证。
- 状态/按钮映射。
- 自动验证结果。
- 实机已覆盖和未覆盖矩阵。
- CANCEL disabled 的已知边界。

- [ ] **Step 7: 提交总结并确认工作区**

```bash
git add docs/260715_1443_wifi_gateway_dfu_app_implementation_summary.md
git commit -m "docs: summarize wifi gateway dfu app implementation"
git status --short
```

Expected: App worktree clean；SDK repo clean。不得自动 merge、push 或删除 worktree。
