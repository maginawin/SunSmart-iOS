# Simulate Fault HTTP API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Simulate Fault 弹窗中的 9 个按钮接入 `/srv2/temporary/device/alert/add`，请求期间阻止重复点击，并复用现有 HUD 展示 Sending、成功和失败状态。

**Architecture:** 新增独立、可纯 Swift 测试的 `SimulateFaultRequestPayload` 与 `SimulateFaultAlertPayload`，由 `SimulateFaultAction` 负责 alert 映射，现有 Moya target 负责 path 和 JSON parameters。`SimulateFaultViewController` 持有 `SpaceData` 与 `Node`，在内部发送请求和管理 window HUD，不向设备页回传事件，也不发送 Mesh 命令。

**Tech Stack:** Swift、UIKit、Foundation、Moya、SnapKit、XWHUDManager、shell contract、Xcode/iPhoneOS。

## Global Constraints

- 最终 URL 必须包含 `/srv2/temporary/device/alert/add`，host 继续使用 `UserData.currentServerRegion.baseURL`。
- body 只包含 OpenAPI 要求的 9 个字段，不新增 `userId`、Auth 或 token。
- `nodeId` 使用 `node.uuid.uuidString`；`nodeAddress` 使用 `node.primaryUnicastAddress.hex`。
- `source` 固定 `ios`，`desc` 与 `location` 固定为空字符串。
- `datetime` 使用点击时的 `Date()`，按 UTC、Gregorian、`en_US_POSIX` 输出 `yyyy-MM-dd HH:mm:ss`。
- 9 个按钮严格使用已确认的 `type/status/level` 映射。
- 请求期间使用 window HUD 和 `isSending` 双重防重复；请求结束后保持 Simulate Fault 打开。
- 成功复用 `successful`，失败复用 `failed`；新增 `simulate_fault_sending` 中英文文案。
- 不发送 Mesh 命令，不修改其他设备页面，不增加自动重试。
- 不使用 subagents，按 Inline Execution 执行。
- iOS 验证必须直接运行 `xcodebuild`，使用 iPhoneOS generic destination，不使用 Simulator 或 shell 包装/日志重定向。

---

### Task 1: 类型化 payload 与 9 个 action 映射

**Files:**
- Create: `SunSmart/Common/Network/SimulateFaultRequest.swift`
- Modify: `SunSmart/Main/Device/Model/SimulateFaultAction.swift`
- Modify: `Tests/Device/SimulateFaultModelTests.swift`

**Interfaces:**
- Produces: `SimulateFaultAlertPayload(type:status:level:)`、`SimulateFaultRequestPayload.init(siteId:spaceId:nodeId:alert:nodeAddress:date:)`、`SimulateFaultRequestPayload.parameters`、`SimulateFaultAction.alertPayload`。
- Consumes: Foundation `Date`、现有 `SimulateFaultAction`。

- [ ] **Step 1: 先写失败的 action 与 request body 测试**

在 `SimulateFaultModelTests.main()` 增加 9 个 action 的期望表，并逐项验证：

```swift
let expectedAlerts: [SimulateFaultAction: SimulateFaultAlertPayload] = [
    .motionSensor(.normal): .init(type: "motion_sensor", status: "normal", level: "3"),
    .motionSensor(.fault): .init(type: "motion_sensor", status: "fault", level: "3"),
    .photocellSensor(.normal): .init(type: "photocell_sensor", status: "normal", level: "2"),
    .photocellSensor(.fault): .init(type: "photocell_sensor", status: "fault", level: "2"),
    .lightStatus(.normal): .init(type: "light_status", status: "normal", level: "1"),
    .lightStatus(.dim): .init(type: "light_status", status: "dim", level: "1"),
    .lightStatus(.flicker): .init(type: "light_status", status: "flicker", level: "1"),
    .lightStatus(.dimFlicker): .init(type: "light_status", status: "dim_flicker", level: "1"),
    .lightStatus(.off): .init(type: "light_status", status: "off", level: "1")
]
precondition(expectedAlerts.count == 9)
expectedAlerts.forEach { action, expected in
    precondition(action.alertPayload == expected)
}

let payload = SimulateFaultRequestPayload(
    siteId: "ST02",
    spaceId: "SP02",
    nodeId: "01AA8F81-16D3-4482-87A3-5799F3F05D98",
    alert: .init(type: "motion_sensor", status: "fault", level: "3"),
    nodeAddress: "00A1",
    date: Date(timeIntervalSince1970: 0)
)
let parameters = payload.parameters
precondition(parameters.count == 9)
precondition(parameters["siteId"] as? String == "ST02")
precondition(parameters["spaceId"] as? String == "SP02")
precondition(parameters["nodeId"] as? String == "01AA8F81-16D3-4482-87A3-5799F3F05D98")
precondition(parameters["nodeAddress"] as? String == "00A1")
precondition(parameters["source"] as? String == "ios")
precondition(parameters["desc"] as? String == "")
precondition(parameters["location"] as? String == "")
precondition(parameters["datetime"] as? String == "1970-01-01 00:00:00")
let alert = parameters["alert"] as? [String: String]
precondition(alert == ["type": "motion_sensor", "status": "fault", "level": "3"])
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```sh
swiftc SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
```

Expected: FAIL，提示找不到 `SimulateFaultAlertPayload`、`SimulateFaultRequestPayload` 或 `alertPayload`。

- [ ] **Step 3: 新增纯 Foundation request 模型**

创建 `SunSmart/Common/Network/SimulateFaultRequest.swift`：

```swift
import Foundation

struct SimulateFaultAlertPayload: Equatable {
    let type: String
    let status: String
    let level: String

    var parameters: [String: String] {
        ["type": type, "status": status, "level": level]
    }
}

struct SimulateFaultRequestPayload {
    let siteId: String
    let spaceId: String
    let nodeId: String
    let alert: SimulateFaultAlertPayload
    let nodeAddress: String
    let source = "ios"
    let desc = ""
    let location = ""
    let datetime: String

    init(
        siteId: String,
        spaceId: String,
        nodeId: String,
        alert: SimulateFaultAlertPayload,
        nodeAddress: String,
        date: Date
    ) {
        self.siteId = siteId
        self.spaceId = spaceId
        self.nodeId = nodeId
        self.alert = alert
        self.nodeAddress = nodeAddress
        self.datetime = Self.utcDateTimeString(from: date)
    }

    var parameters: [String: Any] {
        [
            "siteId": siteId,
            "spaceId": spaceId,
            "nodeId": nodeId,
            "alert": alert.parameters,
            "nodeAddress": nodeAddress,
            "source": source,
            "desc": desc,
            "location": location,
            "datetime": datetime
        ]
    }

    private static func utcDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: 实现 action 到 alert 的完整映射**

在 `SimulateFaultAction.swift` 增加：

```swift
extension SimulateFaultAction {
    var alertPayload: SimulateFaultAlertPayload {
        switch self {
        case .motionSensor(.normal):
            return .init(type: "motion_sensor", status: "normal", level: "3")
        case .motionSensor(.fault):
            return .init(type: "motion_sensor", status: "fault", level: "3")
        case .photocellSensor(.normal):
            return .init(type: "photocell_sensor", status: "normal", level: "2")
        case .photocellSensor(.fault):
            return .init(type: "photocell_sensor", status: "fault", level: "2")
        case .lightStatus(.normal):
            return .init(type: "light_status", status: "normal", level: "1")
        case .lightStatus(.dim):
            return .init(type: "light_status", status: "dim", level: "1")
        case .lightStatus(.flicker):
            return .init(type: "light_status", status: "flicker", level: "1")
        case .lightStatus(.dimFlicker):
            return .init(type: "light_status", status: "dim_flicker", level: "1")
        case .lightStatus(.off):
            return .init(type: "light_status", status: "off", level: "1")
        }
    }
}
```

- [ ] **Step 5: 运行测试并确认 GREEN**

Run:

```sh
swiftc SunSmart/Common/Network/SimulateFaultRequest.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
```

Expected: `SimulateFaultModelTests passed`。

### Task 2: Moya endpoint 与四 target 工程接线

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SimulateFaultRequestPayload.parameters`。
- Produces: `NetowrkReqeustApi.simulateFault(payload:)`，path `/temporary/device/alert/add`，四 target source membership。

- [ ] **Step 1: 先增加失败的 endpoint 与工程接线契约**

在 `check_simulate_fault.sh` 增加：

```sh
request_file="SunSmart/Common/Network/SimulateFaultRequest.swift"
api_file="SunSmart/Common/Network/NetowrkReqeustApi.swift"

test -f "$request_file" || fail "SimulateFaultRequest.swift is missing"
grep -Fq 'case simulateFault(payload: SimulateFaultRequestPayload)' "$api_file" \
  || fail "network API must expose simulateFault"
grep -Fq 'return "/temporary/device/alert/add"' "$api_file" \
  || fail "simulateFault must use the temporary device alert endpoint"
grep -Fq 'case .simulateFault(let payload):' "$api_file" \
  || fail "simulateFault must encode its typed payload"
grep -Fq 'return payload.parameters' "$api_file" \
  || fail "simulateFault must send the complete JSON body"
test "$(grep -c 'SimulateFaultRequest.swift in Sources' SunSmart.xcodeproj/project.pbxproj)" -eq 8 \
  || fail "all four app targets must compile SimulateFaultRequest.swift"
```

- [ ] **Step 2: 运行契约并确认 RED**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL，提示网络 API 尚未暴露 `simulateFault`。

- [ ] **Step 3: 将 endpoint 加入现有 Moya target**

在 `NetowrkReqeustApi` 增加 case：

```swift
case simulateFault(payload: SimulateFaultRequestPayload)
```

同步三个 switch：

```swift
case .simulateFault: return "simulateFault"
```

```swift
case .simulateFault:
    return "/temporary/device/alert/add"
```

```swift
case .simulateFault(let payload):
    return payload.parameters
```

保留现有统一 `.post`、`JSONEncoding.default`、`UserData.currentServerRegion.baseURL` 和 headers 逻辑。

- [ ] **Step 4: 将新模型加入四个 app target**

在 `project.pbxproj` 增加一个 `PBXFileReference`、四个 `PBXBuildFile`，将文件放入 Common/Network 对应 group，并分别加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Sources phase。

- [ ] **Step 5: 校验工程文件和 endpoint 契约**

Run: `plutil -lint SunSmart.xcodeproj/project.pbxproj`

Expected: `SunSmart.xcodeproj/project.pbxproj: OK`。

Run: `bash scripts/check_simulate_fault.sh`

Expected: 仍因 UI/HUD 尚未接线而通过旧契约；Task 3 新契约加入前 endpoint 相关检查必须通过。

### Task 3: View Controller 请求、HUD、防重复与本地化

**Files:**
- Modify: `scripts/check_simulate_fault.sh`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Device/View/SimulateFaultViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `SimulateFaultAction.alertPayload`、`SimulateFaultRequestPayload`、`NetowrkReqeustApi.simulateFault(payload:)`、`SpaceData`、NordicSigMeshSDK `Node`、`XWHUDManager`。
- Produces: 点击按钮后单次发送 HTTP 请求并显示 Sending/成功/失败 HUD；结果后保留 Simulate Fault。

- [ ] **Step 1: 先增加失败的 UI/HUD/本地化契约**

在 `check_simulate_fault.sh` 增加检查：

```sh
grep -Fq 'private let node: Node' "$controller_file" \
  || fail "Simulate Fault controller must retain the selected node"
grep -Fq 'private var isSending = false' "$controller_file" \
  || fail "Simulate Fault must prevent duplicate HTTP requests"
grep -Fq 'NetworkRequest.shared.request(.simulateFault(payload: payload))' "$controller_file" \
  || fail "Simulate Fault actions must call the HTTP endpoint"
grep -Fq 'XWHUDManager.showCustomHUD(withMessage: "simulate_fault_sending".localizedString, isWindow: true)' "$controller_file" \
  || fail "Simulate Fault must show a window Sending HUD"
grep -Fq 'XWHUDManager.showSuccessTipHUD("successful".localizedString)' "$controller_file" \
  || fail "Simulate Fault must reuse the success HUD"
grep -Fq 'XWHUDManager.showErrorTipHUD("failed".localizedString)' "$controller_file" \
  || fail "Simulate Fault must reuse the failure HUD"
grep -Fq 'let controller = SimulateFaultViewController(space: space, node: node)' "$light_file" \
  || fail "Light controller must pass the selected node"
check_string "$en_strings" '"simulate_fault_sending" = "Sending...";'
check_string "$zh_strings" '"simulate_fault_sending" = "发送中...";'
```

将原有禁止项从 `MeshAPI|sendMessage|NordicSigMeshSDK` 收紧为 `MeshAPI|sendMessage`，允许 View Controller 为 `Node` 类型导入 NordicSigMeshSDK，但仍禁止发送 Mesh 命令。

- [ ] **Step 2: 运行契约并确认 RED**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL，提示控制器尚未持有 selected node。

- [ ] **Step 3: 将 Node 传入 Simulate Fault 控制器**

在 `SimulateFaultViewController` 导入 NordicSigMeshSDK，增加：

```swift
private let node: Node
private var isSending = false
```

将 initializer 调整为：

```swift
init(space: SpaceData, node: Node) {
    self.space = space
    self.node = node
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
}
```

设备页调用调整为：

```swift
let controller = SimulateFaultViewController(space: space, node: node)
```

- [ ] **Step 4: 在 action handler 中发送请求并管理 HUD**

将空实现替换为：

```swift
private func handleAction(_ action: SimulateFaultAction) {
    guard space.deviceOperates.contains(.edit) else {
        dismiss(animated: true)
        return
    }
    guard !isSending else { return }

    isSending = true
    let payload = SimulateFaultRequestPayload(
        siteId: space.siteId,
        spaceId: space.id,
        nodeId: node.uuid.uuidString,
        alert: action.alertPayload,
        nodeAddress: node.primaryUnicastAddress.hex,
        date: Date()
    )
    XWHUDManager.showCustomHUD(withMessage: "simulate_fault_sending".localizedString, isWindow: true)
    NetworkRequest.shared.request(.simulateFault(payload: payload)) { [weak self] result in
        XWHUDManager.hide()
        self?.isSending = false
        switch result {
        case .success:
            XWHUDManager.showSuccessTipHUD("successful".localizedString)
        case .failure:
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
    }
}
```

该 handler 不调用 `dismiss` 处理成功或失败，因此结果后 Simulate Fault 保持打开。

- [ ] **Step 5: 增加 Sending 本地化**

English：

```text
"simulate_fault_sending" = "Sending...";
```

简体中文：

```text
"simulate_fault_sending" = "发送中...";
```

- [ ] **Step 6: 运行定向测试并确认 GREEN**

Run:

```sh
swiftc SunSmart/Common/Network/SimulateFaultRequest.swift SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests
/tmp/SimulateFaultModelTests
```

Expected: `SimulateFaultModelTests passed`。

Run: `bash scripts/check_simulate_fault.sh`

Expected: `PASS: Simulate Fault contract is present.`

Run: `bash scripts/check_device_menu_icons.sh`

Expected: PASS，Light proxy 图标仍为 `menu_set_proxy`。

### Task 4: 完整验证与实施总结

**Files:**
- Create: `docs/260716_1722_simulate_fault_http_api_summary.md`

**Interfaces:**
- Consumes: Task 1-3 的最终代码和验证结果。
- Produces: 四 target 构建证据、范围说明和真机验证清单。

- [ ] **Step 1: 检查格式与工程文件**

Run: `git diff --check`

Expected: 无输出，exit code 0。

Run: `plutil -lint SunSmart.xcodeproj/project.pbxproj`

Expected: `SunSmart.xcodeproj/project.pbxproj: OK`。

- [ ] **Step 2: 直接构建四个品牌 target**

依次运行：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四次均输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 写实施总结**

总结记录：接口最终 URL、9 个映射、字段来源、UTC 日期、HUD 与防重复行为、RED/GREEN 证据、四 target 构建结果、未修改范围，以及逐按钮服务端核对的人工验证清单。

- [ ] **Step 4: 提交聚焦改动**

只暂存本计划涉及的 Simulate Fault、网络、工程、本地化、测试、脚本和总结文件；不要暂存既有 `AGENTS.md`、Site/Space key 分析文档或 Energy Data 协议分析文档。

建议提交信息：

```text
feat: send simulated faults to server
```
