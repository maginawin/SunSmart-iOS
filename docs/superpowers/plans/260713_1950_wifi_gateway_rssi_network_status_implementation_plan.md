# WiFi Gateway RSSI Network Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with checkpoints. Project instructions require Inline Execution; do not use subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 兼容解析 V1.7 `43 0F` RSSI/Internet 状态响应，在页面顶部展示正确状态，并把轮询调整为每轮 completion 后等待 5 秒。

**Architecture:** 本地 `NordicSigMeshSDK` 负责严格解析新旧 payload，并通过 typed result 区分 `normal`、`unavailable`、`unknown`、保留值和旧固件未报告状态。App 只消费 typed result：保留现有 RSSI 分级图标与文字，在新版 Internet 异常时覆盖状态文字；轮询由固定重复 timer 改为 completion 驱动的单次 timer。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SIG Mesh vendor messages、XCTest、Bash/rg focused contracts、Xcode iPhoneOS builds。

**Design Reference:** `docs/superpowers/specs/260713_1941_wifi_gateway_rssi_network_status_design.md`

## Global Constraints

- 仅适用于 `companyId == 0x0A78 && productId == 0x2721` 的 WiFi Gateway 现有页面链路。
- GET payload 必须继续精确为 `43 0F`，不增加 trailing bytes。
- `rssi_status == 0x00` 时才允许解析 `network_status`；其他状态忽略该字节并保持 `No Signal` 行为。
- 新 5 字节成功响应按 `network_status` 映射；旧 4 字节成功响应继续展示原有 RSSI 分级。
- RSSI 有效时保持 `Excellent / Good / Poor / Bad` 分级，不展示原始 dBm 数值。
- `NORMAL` 展示 RSSI 分级；`UNAVAILABLE` 展示 `No Internet`；`UNKNOWN` 和保留值展示 `Unknown`。
- Internet 异常但 RSSI 有效时继续使用 RSSI 分级图标，不使用 `wifi_no_signal`。
- 下一轮查询必须从上一轮 completion 开始等待 5 秒；单轮 request timeout 固定为 2 秒。
- 页面退出、Gateway 离线、key bind 未完成、Wi-Fi 非 connected、Connect/Disconnect/Repair 时停止轮询。
- 新增用户可见文案必须同时支持 English 和简体中文，不硬编码到 controller。
- 修改保持聚焦，不调整 `GatewayInformationHeaderView`、图片资源、4G Gateway、其他 WiFi 协议或 target 配置。
- App 工程继续使用本地 SDK 路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，不切回远程依赖。
- 验证只使用 generic iPhoneOS，不使用 Simulator，不使用 shell 包装或日志重定向执行 `xcodebuild`。

## File Map

### 本地 SDK 仓库

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 定义 Internet typed status。
  - 解析 V1.7 5 字节响应和旧固件 4 字节成功响应。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
  - 覆盖新旧 payload、边界值、failure payload 和非法长度。

### App worktree

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - 将 SDK typed result 映射到现有 header。
  - 管理 completion 后 5 秒的单次 RSSI timer。
- `SunSmart/en.lproj/Localizable.strings`
  - 增加 `No Internet`、`Unknown`。
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 `无互联网连接`、`未知`。
- `scripts/check_wifi_gateway_wifi_status_header.sh`
  - 守住网络状态映射、原有 RSSI 阈值和新轮询时序。
- `docs/260713_1950_wifi_gateway_rssi_network_status_implementation_summary.md`
  - 记录最终实现范围与验证证据。

---

### Task 1: 扩展 NordicSigMeshSDK 的 RSSI/Internet typed parsing

**Files:**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift:111`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:47`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:1038`

**Interfaces:**

- Consumes: `SunricherVendorStatus(parameters:)`、`ResponseCode.wifiGatewayRSSIStatusGet`、现有 `FunctionParameters.wifiGatewayRSSIStatus(WiFiGatewayRSSIStatus)`。
- Produces: `public enum WiFiGatewayNetworkStatus: Equatable` 和 `WiFiGatewayRSSIStatus.valid(dbm:networkStatus:)`，供 Task 2 的 App 映射使用。

- [ ] **Step 1: 先把 RSSI parsing tests 改成新旧协议完整矩阵**

将 `testRSSIStatusResponseParsing()` 整体替换为：

```swift
func testRSSIStatusResponseParsing() {
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0xBF, 0x00]),
        expected: .valid(dbm: -65, networkStatus: .normal),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0xBF, 0x01]),
        expected: .valid(dbm: -65, networkStatus: .unavailable),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0xBF, 0x02]),
        expected: .valid(dbm: -65, networkStatus: .unknown),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0xBF, 0x7F]),
        expected: .valid(dbm: -65, networkStatus: .reserved(rawValue: 0x7F)),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0xBF]),
        expected: .valid(dbm: -65, networkStatus: .notReported),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0x81, 0x00]),
        expected: .valid(dbm: -127, networkStatus: .normal),
        isSuccessful: true,
        errorCode: nil
    )
    assertRSSIStatus(
        Data([0x43, 0x0F, 0x00, 0x00, 0x00]),
        expected: .valid(dbm: 0, networkStatus: .normal),
        isSuccessful: true,
        errorCode: nil
    )

    assertRSSIStatus(Data([0x43, 0x0F, 0x01, 0x00]), expected: .unavailable, isSuccessful: false, errorCode: 0x01)
    assertRSSIStatus(Data([0x43, 0x0F, 0x01, 0x00, 0x00]), expected: .unavailable, isSuccessful: false, errorCode: 0x01)
    assertRSSIStatus(Data([0x43, 0x0F, 0x02, 0x00]), expected: .readFailed, isSuccessful: false, errorCode: 0x02)
    assertRSSIStatus(Data([0x43, 0x0F, 0x02, 0x00, 0x02]), expected: .readFailed, isSuccessful: false, errorCode: 0x02)
    assertRSSIStatus(Data([0x43, 0x0F, 0x7F, 0x00]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)
    assertRSSIStatus(Data([0x43, 0x0F, 0x7F, 0x00, 0x00]), expected: .reserved(rawValue: 0x7F), isSuccessful: false, errorCode: 0x7F)

    let tooLow = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x00, 0x80, 0x00]))
    XCTAssertEqual(tooLow?.status.isSuccessful, false)
    XCTAssertNil(tooLow?.status.parameters)

    let positive = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x00, 0x01, 0x00]))
    XCTAssertEqual(positive?.status.isSuccessful, false)
    XCTAssertNil(positive?.status.parameters)

    let short = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x01]))
    XCTAssertEqual(short?.status.isSuccessful, false)
    XCTAssertNil(short?.status.parameters)

    let trailing = SunricherVendorStatus(parameters: Data([0x43, 0x0F, 0x01, 0x00, 0x00, 0x00]))
    XCTAssertEqual(trailing?.status.isSuccessful, false)
    XCTAssertNil(trailing?.status.parameters)
}
```

保留 `testWifiGatewayGetEncoding()` 中对 `Data([0x43, 0x0F])` 的既有断言，确保 GET 编码没有变化。

- [ ] **Step 2: 运行定向测试，记录当前 API 不满足新断言**

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Run:

```bash
swift test --filter WiFiGatewayVendorMessageTests.testRSSIStatusResponseParsing
```

Expected: 如果测试 target 能进入编译，应因为 `WiFiGatewayNetworkStatus` 或 `.valid(dbm:networkStatus:)` 尚不存在而失败；如果先被仓库既有 UIKit/macOS 限制阻断，预期错误为 `no such module 'UIKit'`，保留该输出作为环境限制证据并继续使用 iPhoneOS build 验证。

- [ ] **Step 3: 增加 Internet typed status 并扩展 RSSI result**

在 `WiFiGatewayRSSIStatus` 前增加以下类型，并替换原有 RSSI enum：

```swift
public enum WiFiGatewayNetworkStatus: Equatable {
    case normal
    case unavailable
    case unknown
    case reserved(rawValue: UInt8)
    case notReported

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00:
            self = .normal
        case 0x01:
            self = .unavailable
        case 0x02:
            self = .unknown
        default:
            self = .reserved(rawValue: rawValue)
        }
    }
}

public enum WiFiGatewayRSSIStatus: Equatable {
    case valid(dbm: Int8, networkStatus: WiFiGatewayNetworkStatus)
    case unavailable
    case readFailed
    case reserved(rawValue: UInt8)
}
```

`notReported` 不参与 raw-value 初始化，只由旧 4 字节成功 response 产生。

- [ ] **Step 4: 按 4/5 字节兼容矩阵修改 RSSI response parser**

将 `case .wifiGatewayRSSIStatusGet` 分支替换为：

```swift
case .wifiGatewayRSSIStatusGet:
    guard data.count == 4 || data.count == 5 else { return nil }
    switch status {
    case 0x00:
        let rssi = Int8(bitPattern: data[3])
        guard (-127...0).contains(rssi) else { return nil }
        let networkStatus: WiFiGatewayNetworkStatus
        if data.count == 5 {
            networkStatus = .init(rawValue: data[4])
        } else {
            networkStatus = .notReported
        }
        return .wifiGatewayRSSIStatus(.valid(dbm: rssi, networkStatus: networkStatus))
    case 0x01:
        return .wifiGatewayRSSIStatus(.unavailable)
    case 0x02:
        return .wifiGatewayRSSIStatus(.readFailed)
    default:
        return .wifiGatewayRSSIStatus(.reserved(rawValue: status))
    }
```

这个分支必须先校验总长度，再仅在 `status == 0x00` 时读取第五字节。

- [ ] **Step 5: 复查新 enum 的所有使用点**

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Run:

```bash
rg -n "WiFiGatewayRSSIStatus|case \.valid|\.valid\(dbm:" Sources Tests
```

Expected: SDK 内所有 `.valid` 断言都已使用 `networkStatus:`；除 App worktree 尚待 Task 2 更新外，不存在旧 case arity。

- [ ] **Step 6: 再运行定向测试并执行 SDK Demo iPhoneOS build**

Working directory for the first command: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Run:

```bash
swift test --filter WiFiGatewayVendorMessageTests.testRSSIStatusResponseParsing
```

Expected: PASS；若仍在测试 target 编译前命中既有 `no such module 'UIKit'`，确认错误没有变化且不是新增 RSSI 类型导致的编译错误。

Then run directly:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 检查 SDK diff 并提交**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add wifi gateway network status"
```

Expected: `diff --check` 无输出；commit 仅包含上述两个 SDK 文件。

---

### Task 2: 在 App 顶部映射 RSSI 与 Internet 状态

**Files:**

- Modify: `scripts/check_wifi_gateway_wifi_status_header.sh:57`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:947`
- Modify: `SunSmart/en.lproj/Localizable.strings:1959`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:1975`

**Interfaces:**

- Consumes: Task 1 的 `WiFiGatewayRSSIStatus.valid(dbm:networkStatus:)` 和 `WiFiGatewayNetworkStatus`。
- Produces: `wifiHeaderStatus(forRSSIDBm:networkStatus:) -> WiFiHeaderStatus`，供当前 RSSI completion 路径调用。

- [ ] **Step 1: 先扩展 focused contract 约束 Internet 状态映射和文案**

在 `scripts/check_wifi_gateway_wifi_status_header.sh` 的 typed RSSI 检查后加入：

```bash
rg -n "case \.valid\(let dbm, let networkStatus\)" "$wifi_controller" >/dev/null \
  || fail "Valid Wi-Fi RSSI must carry the typed network status."

rg -n "wifiHeaderStatus\(forRSSIDBm: dbm, networkStatus: networkStatus\)" "$wifi_controller" >/dev/null \
  || fail "Valid Wi-Fi RSSI must map RSSI and network status together."

rg -n "case \.normal, \.notReported:" "$wifi_controller" >/dev/null \
  || fail "NORMAL and legacy not-reported responses must keep the RSSI grade."

rg -n 'localizedStatusKey: "wifi_status_no_internet"' "$wifi_controller" >/dev/null \
  || fail "UNAVAILABLE must display the localized No Internet status."

rg -n 'localizedStatusKey: "wifi_status_unknown"' "$wifi_controller" >/dev/null \
  || fail "UNKNOWN and reserved network states must display the localized Unknown status."
```

在本地化检查区域加入：

```bash
rg -n '"wifi_status_no_internet" = "No Internet";' "$en_strings" >/dev/null \
  || fail "English localization must define No Internet."

rg -n '"wifi_status_no_internet" = "无互联网连接";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 无互联网连接."

rg -n '"wifi_status_unknown" = "Unknown";' "$en_strings" >/dev/null \
  || fail "English localization must define Unknown."

rg -n '"wifi_status_unknown" = "未知";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 未知."
```

- [ ] **Step 2: 运行 focused contract 验证其先失败**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: FAIL，首先指出 valid RSSI 尚未携带并映射 `networkStatus`，或缺少新的本地化 key。

- [ ] **Step 3: 增加 English 与简体中文本地化**

在既有 `wifi_status_not_connected` 附近分别加入：

```text
"wifi_status_no_internet" = "No Internet";
"wifi_status_unknown" = "Unknown";
```

```text
"wifi_status_no_internet" = "无互联网连接";
"wifi_status_unknown" = "未知";
```

- [ ] **Step 4: 更新 App 的有效 RSSI case 并增加组合映射 helper**

将 `applyWiFiRSSIStatus(_:)` 替换为：

```swift
private func applyWiFiRSSIStatus(_ status: WiFiGatewayRSSIStatus) {
    switch status {
    case .valid(let dbm, let networkStatus):
        updateWiFiHeaderStatus(wifiHeaderStatus(forRSSIDBm: dbm, networkStatus: networkStatus))
    case .unavailable, .readFailed, .reserved(rawValue: _):
        updateWiFiHeaderStatus(.noSignal)
    }
}
```

保留当前 `wifiHeaderStatus(forRSSIDBm:)` 的所有阈值，然后在它后面增加：

```swift
private func wifiHeaderStatus(
    forRSSIDBm dbm: Int8,
    networkStatus: WiFiGatewayNetworkStatus
) -> WiFiHeaderStatus {
    let rssiStatus = wifiHeaderStatus(forRSSIDBm: dbm)
    switch networkStatus {
    case .normal, .notReported:
        return rssiStatus
    case .unavailable:
        return WiFiHeaderStatus(
            iconName: rssiStatus.iconName,
            localizedStatusKey: "wifi_status_no_internet"
        )
    case .unknown, .reserved(rawValue: _):
        return WiFiHeaderStatus(
            iconName: rssiStatus.iconName,
            localizedStatusKey: "wifi_status_unknown"
        )
    }
}
```

不得改变 `wifiHeaderStatus(forRSSIDBm:)` 的四个阈值，也不得给 Internet 状态增加新图片。

- [ ] **Step 5: 运行 focused contract 和 SunSmart iPhoneOS build**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: `PASS: WiFi Gateway header Wi-Fi status view and RSSI refresh checks passed.`

Then run directly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，证明 App 已适配 Task 1 的 SDK public enum arity。

- [ ] **Step 6: 检查 App diff 并提交状态映射**

Run:

```bash
git diff --check
git status --short
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings scripts/check_wifi_gateway_wifi_status_header.sh
git commit -m "feat: show wifi gateway network status"
```

Expected: commit 只包含 controller、两个本地化文件和 focused contract；不包含 SDK 文件或无关资源。

---

### Task 3: 将 RSSI 轮询改为 completion 后 5 秒单次调度

**Files:**

- Modify: `scripts/check_wifi_gateway_wifi_status_header.sh:45`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:63`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:895`

**Interfaces:**

- Consumes: 现有 `sendWiFiGatewayGet(_:origin:timeout:completion:) -> Bool` 和 `wifiRSSIStatusTimer` 生命周期。
- Produces: `scheduleNextWiFiRSSIStatusRefresh()`，以及 `wifiRSSIStatusPollDelay == 5`、`wifiRSSIStatusRequestTimeout == 2` 的明确时序契约。

- [ ] **Step 1: 先把 focused contract 从旧 2 秒重复 timer 改成新时序断言**

删除旧检查：

```bash
rg -n "private let wifiRSSIStatusPollInterval: TimeInterval = 2" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI status polling interval must be 2 seconds."
```

在同一位置加入：

```bash
rg -n "private let wifiRSSIStatusPollDelay: TimeInterval = 5" "$wifi_controller" >/dev/null \
  || fail "The next Wi-Fi RSSI query must wait 5 seconds after completion."

rg -n "private let wifiRSSIStatusRequestTimeout: TimeInterval = 2" "$wifi_controller" >/dev/null \
  || fail "Each Wi-Fi RSSI request must keep the 2-second hard timeout."

rg -n "scheduleNextWiFiRSSIStatusRefresh\(\)" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI polling must use completion-driven scheduling."

rg -U -n "wifiRSSIStatusTimer = LCWeakTimer\.scheduledTimer\([[:space:][:print:]]*timeInterval: wifiRSSIStatusPollDelay,[[:space:][:print:]]*repeats: false" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI polling must use a one-shot 5-second timer."

rg -n "timeout: wifiRSSIStatusRequestTimeout" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI GET must use the independent 2-second request timeout."

if rg -n "wifiRSSIStatusPollInterval" "$wifi_controller" >/dev/null; then
  fail "The old fixed RSSI polling interval must be removed."
fi
```

- [ ] **Step 2: 运行 focused contract 验证旧轮询实现不满足新时序**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: FAIL，指出缺少 5 秒 poll delay、2 秒独立 timeout 或 one-shot scheduling。

- [ ] **Step 3: 拆分 RSSI poll delay 与 request timeout 常量**

将：

```swift
private let wifiRSSIStatusPollInterval: TimeInterval = 2
```

替换为：

```swift
private let wifiRSSIStatusPollDelay: TimeInterval = 5
private let wifiRSSIStatusRequestTimeout: TimeInterval = 2
```

- [ ] **Step 4: 用单次 timer 替换 start/refresh 调度链**

将 `startWiFiRSSIStatusRefresh()`、`stopWiFiRSSIStatusRefresh()` 和 `refreshWiFiRSSIStatus()` 替换为以下实现，并在 stop 与 refresh 之间增加 scheduling helper：

```swift
private func startWiFiRSSIStatusRefresh() {
    guard isNetworkPageVisible, node.isKeybindComplete else {
        stopWiFiRSSIStatusRefresh()
        return
    }
    guard node.state, networkConnectState == .connected else {
        stopWiFiRSSIStatusRefresh()
        updateWiFiHeaderStatus(.notConnected)
        return
    }
    wifiRSSIStatusTimer?.invalidate()
    wifiRSSIStatusTimer = nil
    refreshWiFiRSSIStatus()
}

private func stopWiFiRSSIStatusRefresh() {
    wifiRSSIStatusTimer?.invalidate()
    wifiRSSIStatusTimer = nil
}

private func scheduleNextWiFiRSSIStatusRefresh() {
    guard isNetworkPageVisible,
          node.isKeybindComplete,
          node.state,
          networkConnectState == .connected else {
        stopWiFiRSSIStatusRefresh()
        return
    }
    wifiRSSIStatusTimer?.invalidate()
    wifiRSSIStatusTimer = LCWeakTimer.scheduledTimer(
        timeInterval: wifiRSSIStatusPollDelay,
        aTarget: self,
        selector: #selector(refreshWiFiRSSIStatus),
        userInfo: nil,
        repeats: false
    )
    if let wifiRSSIStatusTimer {
        RunLoop.main.add(wifiRSSIStatusTimer, forMode: .common)
    }
}

@objc private func refreshWiFiRSSIStatus() {
    guard isNetworkPageVisible, node.isKeybindComplete else {
        stopWiFiRSSIStatusRefresh()
        return
    }
    guard node.state else {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    guard networkConnectState == .connected else {
        stopWiFiRSSIStatusRefresh()
        updateWiFiHeaderStatus(.notConnected)
        return
    }
    let didStart = sendWiFiGatewayGet(
        .wifiGatewayRSSIStatus,
        origin: .automatic,
        timeout: wifiRSSIStatusRequestTimeout
    ) { [weak self] status in
        guard let self else { return }
        guard self.isNetworkPageVisible,
              self.node.isKeybindComplete,
              self.node.state,
              self.networkConnectState == .connected else {
            self.stopWiFiRSSIStatusRefresh()
            return
        }
        if let status,
           case .wifiGatewayRSSIStatus(let rssiStatus) = status.status.parameters {
            self.applyWiFiRSSIStatus(rssiStatus)
        } else {
            self.updateWiFiHeaderStatus(.noSignal)
        }
        self.scheduleNextWiFiRSSIStatusRefresh()
    }
    if !didStart {
        scheduleNextWiFiRSSIStatusRefresh()
    }
}
```

该实现保证：正常响应、failure response、非法 response 和 timeout 都从 completion 时刻重新计时；请求 gate 被占用时不会并发发送，也不会永久停止轮询；页面离开后 in-flight completion 不会重新启动 timer。

- [ ] **Step 5: 运行 focused contracts**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
```

Expected: 四个脚本均输出各自的 `PASS`，证明新 timer 没有破坏 Network Connectivity、Disconnect 或 SIG Mesh header 状态边界。

- [ ] **Step 6: 执行 SunSmart iPhoneOS build**

Run directly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 检查 diff 并提交轮询改造**

Run:

```bash
git diff --check
git status --short
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift scripts/check_wifi_gateway_wifi_status_header.sh
git commit -m "fix: align wifi rssi polling timing"
```

Expected: commit 只包含 RSSI scheduling 和对应 focused contract。

---

### Task 4: 跨 target 验证并记录实施总结

**Files:**

- Create: `docs/260713_1950_wifi_gateway_rssi_network_status_implementation_summary.md`
- Verify: all files modified in Tasks 1-3

**Interfaces:**

- Consumes: Tasks 1-3 的 SDK typed parsing、App mapping、one-shot scheduling 和 focused contracts。
- Produces: 五个 iPhoneOS target 的构建证据、clean diff/status 和可审阅的实施总结。

- [ ] **Step 1: 运行 SDK 定向测试并确认已知环境边界**

Working directory: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Run:

```bash
swift test --filter WiFiGatewayVendorMessageTests.testRSSIStatusResponseParsing
```

Expected: 测试可运行时 PASS；若既有 UIKit/macOS 限制仍存在，只接受 `no such module 'UIKit'` 这一已知阻断，任何 RSSI enum、parser 或测试代码编译错误都必须修复后再继续。

- [ ] **Step 2: 构建本地 SDK Demo**

Run directly:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 运行 WiFi Gateway focused contracts**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
```

Expected: 六个脚本均输出 `PASS`，且没有恢复链、Disconnect 或 header contract 回归。

- [ ] **Step 4: 构建四个 App target**

依次直接运行：

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

Expected: 四条命令均输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 检查两个仓库的 diff 与状态**

Run:

```bash
git diff --check
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: 两个 `diff --check` 均无输出；App worktree 只允许出现尚未提交的 implementation summary，SDK 仓库必须 clean。

- [ ] **Step 6: 写实施总结**

创建 `docs/260713_1950_wifi_gateway_rssi_network_status_implementation_summary.md`，内容使用以下结构；SDK 定向测试一节根据 Step 1 的实际结果选择且只保留一条结果描述：

```markdown
# WiFi Gateway RSSI 网络状态实施总结

## 完成范围

- 本地 NordicSigMeshSDK 已兼容 V1.7 五字节 RSSI response 和旧四字节成功 response。
- App 在 `NORMAL` / 旧固件响应时保持 RSSI 分级，在 `UNAVAILABLE` 时展示 `No Internet`，在 `UNKNOWN` / 保留值时展示 `Unknown`。
- 非成功 `rssi_status` 继续展示 `No Signal`。
- RSSI 查询已调整为单轮 completion 后等待 5 秒，request timeout 保持 2 秒。
- English 和简体中文文案已同步。

## 兼容边界

- 旧 `43 0F 00 <rssi>` 继续展示 `Excellent / Good / Poor / Bad`。
- 非成功 RSSI response 可以是四或五字节，第五字节不会参与 Internet 状态解析。
- 页面离开、Gateway 离线、Wi-Fi 未连接和相关网络操作期间不会继续 RSSI 轮询。

## 验证结果

- WiFi Gateway focused contracts：全部通过。
- `git diff --check`：App 与 SDK 均通过。
- NordicSigMeshDemo generic iPhoneOS Debug build：通过。
- SunSmart generic iPhoneOS Debug build：通过。
- Archipelago generic iPhoneOS Debug build：通过。
- SLG Sync Plus generic iPhoneOS Debug build：通过。
- SylSmart generic iPhoneOS Debug build：通过。

## SDK 定向测试

- `WiFiGatewayVendorMessageTests.testRSSIStatusResponseParsing`：通过。
```

如果 Step 1 命中既有 UIKit/macOS 阻断，则将最后一条替换为：

```markdown
- `swift test` 在执行目标测试前被仓库既有 `no such module 'UIKit'` 阻断；协议实现已通过 SDK Demo 和四个 App generic iPhoneOS build 验证。
```

- [ ] **Step 7: 提交实施总结并确认 App worktree clean**

Run:

```bash
git add docs/260713_1950_wifi_gateway_rssi_network_status_implementation_summary.md
git commit -m "docs: summarize wifi network status update"
git status --short
```

Expected: commit 只包含实施总结；最终 `git status --short` 无输出。

## Final Review Checklist

- [ ] 对照设计文档逐条确认 11 项验收标准均由 Task 1-4 覆盖。
- [ ] 确认 SDK 只解析协议，不依赖 App 本地化或 UIKit 页面状态。
- [ ] 确认 App 不读取原始 payload，也不使用 `43 0E`、RSSI 或 MQTT 推断 Internet。
- [ ] 确认 `notReported` 与显式 `UNKNOWN` 保持独立，旧固件仍展示 RSSI 分级。
- [ ] 确认 `UNAVAILABLE` / `UNKNOWN` 使用 RSSI 分级图标而非 `wifi_no_signal`。
- [ ] 确认所有新文案均来自 English 和简体中文本地化文件。
- [ ] 确认下一轮查询由 completion 后的 one-shot 5 秒 timer 触发。
- [ ] 确认两个仓库没有无关改动或未提交文件。
