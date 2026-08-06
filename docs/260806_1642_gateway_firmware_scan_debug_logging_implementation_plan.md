# Gateway Firmware Scan DEBUG Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` with Inline Execution. Do not use subagents for this plan.

**Goal:** 在 Site Firmware Update 的 Gateway BLE OTA 页面中，为每个实际候选与广播过滤点输出去重、脱敏、仅 DEBUG 可见的原因日志。

**Architecture:** App 侧使用独立 `GatewayFirmwareScanDebugLogger` 贯穿 Site 候选、页面白名单和升级资格；本地 NordicSigMeshSDK 使用独立 `NodeRSSIScanDebugLogger` 记录广播身份与 MAC 反查。首次 Session ID 由 Site 入口生成并传入页面与 SDK，后续刷新由页面生成新 Session；两个 Logger 只记录诊断，不决定业务过滤结果。

**Tech Stack:** Swift、UIKit、CoreBluetooth、NordicSigMeshSDK、standalone Swift contract tests、Xcode generic iPhoneOS build。

## Global Constraints

- 所有新日志使用 `[GatewayFirmwareScan]` 前缀，只在 `DEBUG` 构建输出。
- 不扫描全部 BLE 广播；继续仅扫描 Mesh Proxy Service。
- MAC 和 Peripheral UUID 仅输出末四位。
- 禁止输出 Network Key、Device Key、AppKey、完整 MAC、完整 Peripheral UUID 或 Auth 信息。
- 不改变候选、权限、Mesh 身份、MAC 匹配、固件版本与 RSSI 业务规则。
- 保留 App 与本地 SDK 的既有未提交改动，不提交 Git。
- 新 App 源文件必须加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 Target。
- iOS 构建直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。

---

## File Map

- Create: `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDebugLogger.swift` — App 侧 Session、脱敏、事件去重、计数和汇总。
- Create: `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDiagnosticPolicy.swift` — App 候选、版本与 RSSI 的纯原因决策。
- Create: `Tests/Firmware/GatewayFirmwareScanDebugLoggerTests.swift` — App Logger 的独立行为测试。
- Create: `Tests/Firmware/GatewayFirmwareScanDiagnosticPolicyTests.swift` — App 原因决策行为测试。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 将 App Logger 加入 Firmware/Model 与四个 Target。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift` — 首次 Session 与 Site 候选诊断。
- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift` — 页面候选、地址白名单、升级资格与刷新汇总。
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDebugLogger.swift` — SDK 广播诊断去重与汇总。
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDiagnosticPolicy.swift` — SDK 广播过滤的纯原因决策。
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/NodeRSSIScanDebugLoggerTests.swift` — SDK Logger 独立测试。
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/NodeRSSIScanDiagnosticPolicyTests.swift` — SDK 原因决策行为测试。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift` — 广播过滤原因和可选 Session 上下文。

---

### Task 1: App DEBUG Logger

**Files:**

- Create: `Tests/Firmware/GatewayFirmwareScanDebugLoggerTests.swift`
- Create: `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDebugLogger.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `GatewayFirmwareScanDebugLogger.makeSessionID() -> String`
- Produces: `GatewayFirmwareScanDebugLogger.init(sessionID: String, sink: @escaping (String) -> Void = { print($0) })`
- Produces: `record(stage: String, result: String, reason: String, deviceKey: String, cid: UInt16? = nil, pid: UInt16? = nil, address: UInt16? = nil, rssi: Int? = nil, macAddress: String? = nil, peripheralIdentifier: UUID? = nil)`
- Produces: `finish()`，幂等输出一次 `stage=summary result=finished`。

- [ ] **Step 1: Write the failing standalone test**

测试使用固定 Session 和注入 Sink，连续记录两次相同事件、一次不同原因，然后结束。断言：相同事件只输出一次；不同原因分别输出；完整 MAC 与 UUID 不出现；末四位出现；Summary 中两个原因各计数一次；重复 `finish()` 不重复输出。

```swift
import Foundation

@main
struct GatewayFirmwareScanDebugLoggerTests {
    static func main() {
        var lines: [String] = []
        let logger = GatewayFirmwareScanDebugLogger(
            sessionID: "A1B2C3D4",
            sink: { lines.append($0) }
        )
        let peripheralID = UUID(uuidString: "11111111-2222-3333-4444-555566667777")!

        logger.record(
            stage: "page_candidate",
            result: "rejected",
            reason: "missing_product_id",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF",
            peripheralIdentifier: peripheralID
        )
        logger.record(
            stage: "page_candidate",
            result: "rejected",
            reason: "missing_product_id",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF",
            peripheralIdentifier: peripheralID
        )
        logger.record(
            stage: "eligibility",
            result: "disabled",
            reason: "rssi_unavailable",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF"
        )
        logger.finish()
        logger.finish()

        precondition(lines.count == 3)
        precondition(lines.allSatisfy { $0.contains("[GatewayFirmwareScan]") })
        precondition(lines.allSatisfy { !$0.contains("AABBCCDDEEFF") })
        precondition(lines.allSatisfy { !$0.contains(peripheralID.uuidString) })
        precondition(lines.contains { $0.contains("mac_suffix=EEFF") })
        precondition(lines.contains { $0.contains("peripheral_suffix=7777") })
        precondition(lines.last?.contains("missing_product_id:1") == true)
        precondition(lines.last?.contains("rssi_unavailable:1") == true)
        print("GatewayFirmwareScanDebugLoggerTests passed")
    }
}
```

- [ ] **Step 2: Run RED verification**

Run:

```bash
swiftc -D DEBUG Tests/Firmware/GatewayFirmwareScanDebugLoggerTests.swift SunSmart/Main/Firmware/Model/GatewayFirmwareScanDebugLogger.swift -o /tmp/gateway_firmware_scan_logger_tests
```

Expected: FAIL because `GatewayFirmwareScanDebugLogger.swift` or the type does not exist.

- [ ] **Step 3: Implement the minimal Logger**

实现一个 Foundation-only final class：保存 `sessionID`、注入 Sink、`Set<EventKey>`、`[String: Int]` 和 `finished`；`record` 与 `finish` 的输出代码全部放在 `#if DEBUG` 内。Suffix 辅助函数仅返回规范化字符串的最后四个字符，不在日志中拼接原始值。

- [ ] **Step 4: Add the source to all App targets**

在 `project.pbxproj` 中增加一个 File Reference、四个 PBXBuildFile，并分别插入已有四个 Sources Build Phase；File Reference 放在 Firmware/Model group，位置紧邻 `FirmwareVersionUpdatePolicy.swift`。

- [ ] **Step 5: Run GREEN verification**

Run the compile command from Step 2, then:

```bash
/tmp/gateway_firmware_scan_logger_tests
```

Expected: `GatewayFirmwareScanDebugLoggerTests passed`。

---

### Task 2: SDK DEBUG Logger

**Files:**

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/NodeRSSIScanDebugLoggerTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDebugLogger.swift`

**Interfaces:**

- Produces: `NodeRSSIScanDebugLogger.init(sessionID: String, sink: @escaping (String) -> Void = { print($0) })`
- Produces: `record(result: String, reason: String, deviceKey: String, cid: UInt16? = nil, pid: UInt16? = nil, address: UInt16? = nil, rssi: Int? = nil, macAddress: String? = nil, peripheralIdentifier: UUID? = nil)`
- Produces: `finish()`，幂等输出 SDK 原因汇总。

- [ ] **Step 1: Write the failing standalone SDK test**

测试固定 Session、MAC 和 Peripheral UUID：连续两次记录 `node_mac_not_found`，再记录一次 `advertisement_matched`，调用两次 `finish()`。断言总行数为三、完整 MAC 与 UUID 不出现、末四位出现、两个原因在 Summary 中各计数一次。

```swift
import Foundation

@main
struct NodeRSSIScanDebugLoggerTests {
    static func main() {
        var lines: [String] = []
        let logger = NodeRSSIScanDebugLogger(
            sessionID: "A1B2C3D4",
            sink: { lines.append($0) }
        )
        let peripheralID = UUID(uuidString: "11111111-2222-3333-4444-555566667777")!

        for _ in 0..<2 {
            logger.record(
                result: "rejected",
                reason: "node_mac_not_found",
                deviceKey: "peripheral-7777",
                cid: 0x0A78,
                pid: 0x2701,
                rssi: -67,
                macAddress: "AABBCCDDEEFF",
                peripheralIdentifier: peripheralID
            )
        }
        logger.record(
            result: "accepted",
            reason: "advertisement_matched",
            deviceKey: "node-0003",
            cid: 0x0A78,
            pid: 0x2701,
            address: 0x0003,
            rssi: -66,
            macAddress: "AABBCCDDEEFF",
            peripheralIdentifier: peripheralID
        )
        logger.finish()
        logger.finish()

        precondition(lines.count == 3)
        precondition(lines.allSatisfy { $0.contains("[GatewayFirmwareScan]") })
        precondition(lines.allSatisfy { !$0.contains("AABBCCDDEEFF") })
        precondition(lines.allSatisfy { !$0.contains(peripheralID.uuidString) })
        precondition(lines.contains { $0.contains("mac_suffix=EEFF") })
        precondition(lines.contains { $0.contains("peripheral_suffix=7777") })
        precondition(lines.last?.contains("node_mac_not_found:1") == true)
        precondition(lines.last?.contains("advertisement_matched:1") == true)
        print("NodeRSSIScanDebugLoggerTests passed")
    }
}
```

- [ ] **Step 2: Run RED verification**

Run from the SDK root:

```bash
swiftc -D DEBUG Tests/Standalone/NodeRSSIScanDebugLoggerTests.swift Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDebugLogger.swift -o /tmp/node_rssi_scan_logger_tests
```

Expected: FAIL because the SDK Logger does not exist.

- [ ] **Step 3: Implement the minimal SDK Logger**

实现 Foundation-only final class。类内保存 `sessionID`、注入 Sink、由 `result/reason/deviceKey` 组成的 `Set<EventKey>`、`[String: Int]` 原因计数和 `finished`。`record` 固定输出 `stage=sdk_advertisement`；`record` 与 `finish` 的输出代码全部放在 `#if DEBUG`；Suffix 只返回规范化标识的最后四个字符。

- [ ] **Step 4: Run GREEN verification**

Run the compile command from Step 2, then:

```bash
/tmp/node_rssi_scan_logger_tests
```

Expected: `NodeRSSIScanDebugLoggerTests passed`。

---

### Task 3: SDK Broadcast Rejection Reasons

**Files:**

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/NodeRSSIScanDiagnosticPolicyTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDiagnosticPolicy.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`

**Interfaces:**

- Modifies: `refreshNodesRSSI(withWaitFor:debugLogSessionID:nodeScan:finished:)`
- Consumes: `NodeRSSIScanDebugLogger`
- Produces: `NodeRSSIScanDiagnosticPolicy.networkIdentityReason(matchesMesh:matchesCurrentKey:)`
- Produces: `NodeRSSIScanDiagnosticPolicy.nodeIdentityReason(identityAvailable:matchesCurrentKey:)`
- Produces: `NodeRSSIScanDiagnosticPolicy.nodeLookupReason(deviceParsed:macAvailable:nodeFound:)`
- Keeps: all existing callers source-compatible through `debugLogSessionID: String? = nil`.

- [ ] **Step 1: Write the failing SDK decision-policy test**

使用逐字面量输入验证每个错误分支，确保错误原因不由测试复用生产逻辑计算。删除任一 Policy 分支、交换 Mesh/Key 判断顺序或把缺少 MAC 当作 Node lookup 失败，都必须使测试失败。

```swift
import Foundation

@main
struct NodeRSSIScanDiagnosticPolicyTests {
    static func main() {
        precondition(NodeRSSIScanDiagnosticPolicy.networkIdentityReason(matchesMesh: false, matchesCurrentKey: false) == "mesh_network_mismatch")
        precondition(NodeRSSIScanDiagnosticPolicy.networkIdentityReason(matchesMesh: true, matchesCurrentKey: false) == "current_network_key_mismatch")
        precondition(NodeRSSIScanDiagnosticPolicy.networkIdentityReason(matchesMesh: true, matchesCurrentKey: true) == nil)
        precondition(NodeRSSIScanDiagnosticPolicy.nodeIdentityReason(identityAvailable: false, matchesCurrentKey: false) == "missing_supported_identity")
        precondition(NodeRSSIScanDiagnosticPolicy.nodeIdentityReason(identityAvailable: true, matchesCurrentKey: false) == "node_identity_mismatch")
        precondition(NodeRSSIScanDiagnosticPolicy.nodeIdentityReason(identityAvailable: true, matchesCurrentKey: true) == nil)
        precondition(NodeRSSIScanDiagnosticPolicy.nodeLookupReason(deviceParsed: false, macAvailable: false, nodeFound: false) == "provisioning_device_parse_failed")
        precondition(NodeRSSIScanDiagnosticPolicy.nodeLookupReason(deviceParsed: true, macAvailable: false, nodeFound: false) == "missing_mac")
        precondition(NodeRSSIScanDiagnosticPolicy.nodeLookupReason(deviceParsed: true, macAvailable: true, nodeFound: false) == "node_mac_not_found")
        precondition(NodeRSSIScanDiagnosticPolicy.nodeLookupReason(deviceParsed: true, macAvailable: true, nodeFound: true) == nil)
        print("NodeRSSIScanDiagnosticPolicyTests passed")
    }
}
```

- [ ] **Step 2: Run RED verification**

Run from the SDK root:

```bash
swiftc Tests/Standalone/NodeRSSIScanDiagnosticPolicyTests.swift Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIScanDiagnosticPolicy.swift -o /tmp/node_rssi_scan_diagnostic_policy_tests
```

Expected: FAIL because `NodeRSSIScanDiagnosticPolicy` does not exist.

- [ ] **Step 3: Add the optional SDK diagnostic context**

先实现纯 Policy 使 Step 1 的字面量分支测试通过。再为 `refreshNodesRSSI` 增加 `debugLogSessionID: String? = nil`。开始新扫描时仅在 `#if DEBUG` 且 Session 非空时创建 `NodeRSSIScanDebugLogger`；`stopRefreshNodesRSSI` 调用 `finish()` 并清空 Logger。

- [ ] **Step 4: Split compound guards without changing acceptance**

将 Network Identity 的 Mesh Network 与 current Network Key 判断拆开记录；将 Node Identity 缺失与验证失败拆开；将 ProvisioningDevice、MAC 和 Node lookup 拆成顺序 guard。每个拒绝分支先记录原因再 `return`，成功广播和 connected Proxy 分别记录成功原因。

- [ ] **Step 5: Run GREEN verification and existing SDK session test**

Run the Policy compile command from Step 2 and execute `/tmp/node_rssi_scan_diagnostic_policy_tests`，then from the SDK root:

```bash
swiftc Tests/Standalone/NodeRSSIRefreshSessionPolicyTests.swift Sources/NordicSigMeshSDK/MeshLib/Manager/NodeRSSIRefreshSessionPolicy.swift -o /tmp/node_rssi_refresh_session_tests
/tmp/node_rssi_refresh_session_tests
```

Expected: Policy and existing Session tests both pass。

---

### Task 4: Site and Firmware Page Diagnostics

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- Create: `Tests/Firmware/GatewayFirmwareScanDiagnosticPolicyTests.swift`
- Create: `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDiagnosticPolicy.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `GatewayFirmwareScanDebugLogger`
- Consumes: SDK `debugLogSessionID`
- Produces: `GatewayFirmwareScanDiagnosticPolicy.siteCandidateReason(nodeResolved:canConfigure:isOwner:hasAssociatedSpace:)`
- Produces: `GatewayFirmwareScanDiagnosticPolicy.pageCandidateReason(productID:)`
- Produces: `GatewayFirmwareScanDiagnosticPolicy.eligibilityReason(currentVersion:targetVersion:versionEligibility:rssi:scanFinished:)`
- Modifies: `BleFirmwareUpdateViewController.init(site:space:nodes:debugLogSessionID:)` with a default `nil` value to keep all existing callers compatible.

- [ ] **Step 1: Write the failing App decision-policy test**

用字面量输入覆盖未解析 Node、权限拒绝、无 Associated Space、缺少 PID、缺少本地固件、缺少当前版本、非法版本、不允许升级、扫描结束仍无 RSSI、低于 -80 和可升级。生产 Site 与页面日志分支必须调用该 Policy 返回的原因。

- [ ] **Step 2: Run RED verification**

Run:

```bash
swiftc Tests/Firmware/GatewayFirmwareScanDiagnosticPolicyTests.swift SunSmart/Main/Firmware/Model/GatewayFirmwareScanDiagnosticPolicy.swift SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift -o /tmp/gateway_firmware_scan_diagnostic_policy_tests
```

Expected: FAIL because `GatewayFirmwareScanDiagnosticPolicy` does not exist.

- [ ] **Step 3: Add Site entry diagnostics**

先实现纯 Policy 并运行 `/tmp/gateway_firmware_scan_diagnostic_policy_tests` 确认 GREEN。再在 `firmwareUpdate()` 中生成 Session 和 Logger；对当前 `GatewayModel.load(siteId:)` 做只读诊断，记录无法解析、权限、Associated Space 与 accepted。实际 `gateways` 变量仍直接来自 `firmwareUpdateGatewayModels`，诊断结果不得替代业务结果。将 Session 传给页面 initializer。

- [ ] **Step 4: Add page Session lifecycle and candidate logs**

页面保存首次 Logger；只有 Logger 已结束时，下拉刷新才生成新 Session。`setupData` 对缺少 PID 和已加入 PID 类别记录原因。`refreshNodesRSSI` 传入当前 Session。

- [ ] **Step 5: Add whitelist and eligibility logs**

拆开 SDK 回调中的地址 guard；不在白名单时记录并返回，成功时记录。固件和版本原因在 `setupData` 记录；RSSI 低门槛和 eligible 在扫描回调记录；扫描结束时只对仍无 RSSI/Peripheral 的候选记录 `rssi_unavailable`。页面 `stopRefreshRSSI` 和正常 `refreshNodesRSSIFinish` 使用同一个幂等 finalizer 输出 Summary。

- [ ] **Step 6: Run GREEN verification and App Logger test**

Run the App Policy command from Step 2、Task 1 Logger commands、Task 3 SDK Policy commands。

Expected: all pass。

---

### Task 5: Focused and Multi-target Verification

**Files:**

- Verify only; do not modify unrelated files.

- [ ] **Step 1: Run all new standalone behavior tests**

Run the App Logger、App Policy、SDK Logger、SDK Policy and existing Node RSSI Session tests from Tasks 1-4.

- [ ] **Step 2: Run existing firmware version policy test**

Compile and run `Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift` with `SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift` using its existing standalone command pattern.

- [ ] **Step 3: Validate project membership and formatting**

Run:

```bash
rg -n "GatewayFirmwareScanDebugLogger.swift in Sources" SunSmart.xcodeproj/project.pbxproj
git diff --check
git status --short
```

Expected: four Sources memberships; no whitespace errors; only scoped App docs/tests/source/project changes plus preserved SDK pre-existing and scoped diagnostic changes.

- [ ] **Step 4: Build SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Build the other SDK-consuming brand targets**

Run the same generic iPhoneOS command for schemes `Archipelago`, `SLG Sync Plus`, and `SylSmart`.

Expected: all three report `BUILD SUCCEEDED`。

- [ ] **Step 6: Review final diff and evidence boundary**

Confirm no user-visible copy, localization, resource, dependency, Auth, permission, filtering rule or RSSI threshold changed. Report standalone tests and builds separately from real 4G Gateway validation; hardware acceptance remains open until a device produces the new reason logs.
