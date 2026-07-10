# WiFi Gateway Server Information 恢复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本项目明确采用 Inline Execution，不使用 subagents。

**Goal:** 让 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 在 Repair 中完成 Server Authorization 与 Server Information 恢复，离线时继续独立 Mesh 任务，并且服务器配置未收敛前绝不显示 Repair success。

**Architecture:** 新增一个共享 Gateway Server Authorization 服务，统一 Gateway Register、响应校验、MQTT 信息持久化和同 Gateway 请求合并；在现有 Gateway Recovery 任务图中加入 HTTP `Server Authorization` 任务和动态 `Server Information` Mesh 任务。Fast Add、Cloud Sync、Repair 与 WiFi Authorize 都通过该服务发起注册，Cloud 不再先走通用 request 分支再丢弃响应；WiFi Authorize 复用服务器恢复子链和现有 WiFi acknowledged 请求协调器，其他 Gateway 的 Repair/Authorize 保持现状。

**Tech Stack:** Swift、UIKit、Swift Concurrency、NordicSigMeshSDK、Moya、SQLite.swift、SnapKit、Bash/`rg` 源码契约检查、Xcode `xcodebuild` generic iPhoneOS。

**实现收敛说明:** 已批准设计中的 Cloud 路径描述为“通用请求完成后复用解析器消费响应”。本计划进一步收敛为：`.syncGateway` 直接通过共享 Authorization 服务发起同一个 Gateway Register，并保留 Cloud waiter 的 cancel/state callback。对外 API、Cloud 成功语义和 Cloud 原有 `gatewayPreconfigured` payload 结构不变；共享服务让 Add、Cloud、Repair、Authorize 真正按 Site/MAC 合并同一时刻的注册请求，避免只共享解析器却仍发生重复 HTTP 请求。

## Global Constraints

- 核心行为变更仅处理 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway；其他 Gateway 的 Repair 和 Authorize 页面路径保持现状。
- 离线时 Initialize、Associated Spaces、Association Project、Sync Spaces 等可执行 Mesh 任务继续；Server Authorization 失败，Server Information 与 Final Verification 标记为 Skipped，整体 Recovery 失败。
- 网络恢复后 Retry 保留 Success 任务，只重置 Failed/Skipped 服务器链及其后继验证。
- `mqttServerInfo == nil` 对 WiFi Gateway 必须解释为服务器恢复未完成，不能解释为无差异。
- Recovery、Authorize 和 Cloud Sync 不读取、修改或下发 WiFi SSID、Password。
- 不新增、生成、硬编码或记录 MQTT Auth 信息；Debug 日志不得输出 username、password、client ID 或完整 Gateway Register 响应。
- 不修改 Fast Add 的总体成功判定、回滚或删除策略。
- 不修改普通 Save 的差异同步策略。
- 不对通用 Sync、Cloud 或 NetworkRequest 做无关重构。
- App 现有公开能力足够，本轮不修改 NordicSigMeshSDK。
- 所有新增用户可见文案同时支持 English 和简体中文；禁止硬编码用户可见文案。
- 新增共享 Swift 文件必须加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 重要计划与实施总结保存在 `docs/`，文件名遵循 `yyMMdd_HHmm_[description].md`。
- iOS 验证直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 Simulator、shell wrapper 或日志重定向。
- 当前工程没有可用的 App XCTest target；使用聚焦源码契约脚本先行，并以四品牌 iPhoneOS build 和真机矩阵作为最终验证。
- Gateway Register 重复注册能否返回或重新签发完整 MQTT 凭据必须通过真实 API/真机验证；未确认前不得宣称现场问题完全闭环。

---

## 文件结构与职责

- `SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift`
  - 唯一负责 Gateway Register、响应字段校验、MQTT 信息构造、持久化和同 Gateway 请求合并；不发送 Mesh 消息、不控制页面。
- `SunSmart.xcodeproj/project.pbxproj`
  - 将共享 Authorization 服务加入四个品牌 target。
- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift`
  - Fast Add 调用共享 Authorization 服务，保持原有总体成功/回滚语义。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
  - `syncGateway` 特判调用共享 Authorization 服务并保留取消/状态回调，不再由通用 request 分支单独发起 Gateway Register。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 定义 Server Authorization、动态 Server Information、服务器验证和收紧后的 Recovery 成功条件。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 组装服务器恢复子任务，在 Sync worker 中执行异步 HTTP 任务，并复用现有 Success 保留与 Failed/Skipped Retry。
- `SunSmart/Main/Space/View/SyncDevicesProgressView.swift`
  - 在任务详情中显示 Authorization 的具体本地化错误，而不是一律显示 `Failure`。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 提供可覆盖的 Server Authorization 行为、服务器恢复导航和持久化模型刷新；保留其他 Gateway 的旧 Authorize。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - WiFi Gateway Authorize 复用 acknowledged 请求前置协调器并进入服务器恢复子链。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 `Server Authorization` 任务标题。
- `scripts/check_wifi_gateway_server_information_recovery.sh`
  - 守住共享解析、Cloud 保存、任务依赖、动态读取、最终验证、页面分流、本地化和 Auth 日志边界。
- `docs/260710_1715_wifi_gateway_server_information_recovery_implementation_summary.md`
  - 记录最终静态检查、构建和真机/API 未执行项。

---

### Task 1: 建立共享 Gateway Server Authorization 服务

**Files:**
- Create: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Create: `SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `GatewayServerAuthorizationRequestPolicy.ifMissing`、`.always`。
- Produces: `GatewayServerAuthorizationError: LocalizedError`，包含 `noNetwork`、`nodeExportFailed`、`requestFailed(NetworkApiError)`、`invalidResponse(missingFields:)`、`persistenceFailed`。
- Produces: `GatewayServerAuthorizationService.shared.authorize(gateway:node:policy:) async -> Result<GatewayInformation.MQTTConnectInformation, GatewayServerAuthorizationError>`。
- Produces: `GatewayServerAuthorizationService.isValid(_:)`，作为页面、任务和最终验证的统一目标完整性判断。
- Guarantee: 不输出或记录响应字段值；Add、Cloud、Repair、Authorize 对同 Site/MAC 的 Authorization 请求复用同一 in-flight Task。

- [ ] **Step 1: 创建共享服务的失败契约**

创建 `scripts/check_wifi_gateway_server_information_recovery.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

service="SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift"
project="SunSmart.xcodeproj/project.pbxproj"

test -f "$service" || fail "Gateway Server Authorization service is missing"
rg -n "actor GatewayServerAuthorizationService" "$service" >/dev/null \
  || fail "Authorization requests must be coordinated by an actor"
rg -n "case noNetwork|case nodeExportFailed|case requestFailed|case invalidResponse|case persistenceFailed" "$service" >/dev/null \
  || fail "Authorization must expose explicit failure categories"
for field in mqttUsername mqttPassword mqttClientId host port; do
  rg -n "data\[\"$field\"\]" "$service" >/dev/null \
    || fail "Gateway Register parser must require $field"
done
rg -n "func authorize\(" "$service" >/dev/null \
  || fail "Authorization service must expose authorize"
rg -n "gateway\.save\(\)" "$service" >/dev/null \
  || fail "Valid MQTT information must be persisted"
rg -n "GatewayServerAuthorizationService.swift" "$project" | awk 'END { exit(NR >= 6 ? 0 : 1) }' \
  || fail "Authorization service must have one file reference, four build files, and a group reference"
if rg -n 'print\(.*(mqttUsername|mqttPassword|mqttClientId|response)' "$service" >/dev/null; then
  fail "Authorization service must not log credentials or the full response"
fi

echo "PASS: WiFi Gateway Server Authorization service contracts"
```

- [ ] **Step 2: 赋予脚本权限并验证 RED**

Run:

```bash
chmod +x scripts/check_wifi_gateway_server_information_recovery.sh
scripts/check_wifi_gateway_server_information_recovery.sh
```

Expected: FAIL，首个失败为 `Gateway Server Authorization service is missing`。

- [ ] **Step 3: 新增共享 Authorization 类型和响应解析**

创建 `GatewayServerAuthorizationService.swift`，先写入以下完整类型骨架与解析/持久化实现：

```swift
import Foundation
import NordicSigMeshSDK

enum GatewayServerAuthorizationRequestPolicy: Equatable {
    case ifMissing
    case always
}

enum GatewayServerAuthorizationError: Error, Equatable {
    case noNetwork
    case nodeExportFailed
    case requestFailed(NetworkApiError)
    case invalidResponse(missingFields: [String])
    case persistenceFailed

    var networkApiError: NetworkApiError {
        switch self {
        case .noNetwork:
            return .noNetwork
        case .requestFailed(let error):
            return error
        case .nodeExportFailed, .invalidResponse, .persistenceFailed:
            return .init(
                code: 9998,
                message: diagnosticDescription,
                httpStatusCode: nil,
                responseBody: nil
            )
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .noNetwork:
            return "phone has no network"
        case .nodeExportFailed:
            return "node export failed"
        case .requestFailed(let error):
            return "request failed: \(error.code)"
        case .invalidResponse(let missingFields):
            return "invalid response fields: \(missingFields.sorted().joined(separator: ","))"
        case .persistenceFailed:
            return "gateway persistence failed"
        }
    }
}

extension GatewayServerAuthorizationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "phone_no_network".localizedString
        case .requestFailed(let error):
            return error.localizedDescription
        case .nodeExportFailed, .invalidResponse, .persistenceFailed:
            return "server_failure".localizedString
        }
    }
}

actor GatewayServerAuthorizationService {
    typealias MQTTInformation = GatewayInformation.MQTTConnectInformation

    static let shared = GatewayServerAuthorizationService()

    private struct InFlightAuthorization {
        let id: UUID
        let task: Task<Result<MQTTInformation, GatewayServerAuthorizationError>, Never>
    }

    private var inFlightAuthorizations: [String: InFlightAuthorization] = [:]

    static func isValid(_ information: MQTTInformation?) -> Bool {
        guard let information else { return false }
        return !information.serverAddress.isEmpty
            && !information.clientId.isEmpty
            && !(information.userName?.isEmpty ?? true)
            && !(information.password?.isEmpty ?? true)
    }

    static func parse(
        response: [String: Any]
    ) -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        guard let data = response["data"] as? [String: Any] else {
            return .failure(.invalidResponse(missingFields: ["data"]))
        }

        var missingFields: [String] = []
        let username = data["mqttUsername"] as? String
        let password = data["mqttPassword"] as? String
        let clientId = data["mqttClientId"] as? String
        let host = data["host"] as? String
        let port = data["port"] as? Int

        if username?.isEmpty != false { missingFields.append("mqttUsername") }
        if password?.isEmpty != false { missingFields.append("mqttPassword") }
        if clientId?.isEmpty != false { missingFields.append("mqttClientId") }
        if host?.isEmpty != false { missingFields.append("host") }
        if port == nil || !(1...65535).contains(port ?? 0) { missingFields.append("port") }

        guard missingFields.isEmpty,
              let username,
              let password,
              let clientId,
              let host,
              let port else {
            return .failure(.invalidResponse(missingFields: missingFields))
        }

        return .success(
            MQTTInformation(
                customId: customId,
                serverAddress: "tcp://\(host):\(port)",
                userName: username,
                password: password,
                clientId: clientId,
                keepalive: 60,
                clearSession: true,
                authMode: .none,
                sslVersion: .all
            )
        )
    }

    private static func persist(
        _ information: MQTTInformation,
        to gateway: GatewayModel
    ) -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        let previousInformation = gateway.mqttServerInfo
        gateway.mqttServerInfo = information
        guard gateway.save() else {
            gateway.mqttServerInfo = previousInformation
            return .failure(.persistenceFailed)
        }
        return .success(information)
    }

}
```

- [ ] **Step 4: 实现同 Gateway 请求合并与 Authorization**

在 actor 内追加：

```swift
    func authorize(
        gateway: GatewayModel,
        node: Node,
        policy: GatewayServerAuthorizationRequestPolicy = .ifMissing
    ) async -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        if policy == .ifMissing,
           let information = gateway.mqttServerInfo,
           Self.isValid(information) {
            return .success(information)
        }
        guard NetworkRequest.shared.networkable else {
            return .failure(.noNetwork)
        }

        let key = "\(gateway.siteId)|\(gateway.mac.uppercased())"
        let authorization: InFlightAuthorization
        if let existing = inFlightAuthorizations[key] {
            authorization = existing
        } else {
            let id = UUID()
            let task = Task<Result<MQTTInformation, GatewayServerAuthorizationError>, Never> {
                guard var nodeData = await node.export() else {
                    return .failure(.nodeExportFailed)
                }
                nodeData["gatewayPreconfigured"] = gateway.export()
                let result = await NetworkRequest.shared.request(
                    .gatewayRegister(
                        siteId: gateway.siteId,
                        gatewayId: gateway.mac,
                        nodeId: node.uuid.uuidString,
                        node: nodeData,
                        updateTimestamp: gateway.lastUpdate
                    )
                )
                switch result {
                case .success(let response):
                    return Self.parse(response: response)
                case .failure(let error):
                    return .failure(.requestFailed(error))
                }
            }
            authorization = InFlightAuthorization(id: id, task: task)
            inFlightAuthorizations[key] = authorization
        }

        let result = await authorization.task.value
        if inFlightAuthorizations[key]?.id == authorization.id {
            inFlightAuthorizations[key] = nil
        }

        switch result {
        case .success(let information):
            return Self.persist(information, to: gateway)
        case .failure(let error):
            if policy == .always,
               let information = gateway.mqttServerInfo,
               Self.isValid(information),
               case .invalidResponse = error {
                return .success(information)
            }
            return .failure(error)
        }
    }
```

这里仅在 `.always` 且服务端成功响应不重复返回凭据时允许保留已有有效目标；本地目标为空时，缺失字段仍必须失败。

- [ ] **Step 5: 将新文件加入四个品牌 target**

在 `project.pbxproj` 中使用未占用的 `C8A901xx2F810001000000xx` 标识增加：

```text
C8A901092F81000100000009 /* GatewayServerAuthorizationService.swift in Sources */
C8A9010A2F8100010000000A /* GatewayServerAuthorizationService.swift in Sources */
C8A9010B2F8100010000000B /* GatewayServerAuthorizationService.swift in Sources */
C8A9010C2F8100010000000C /* GatewayServerAuthorizationService.swift in Sources */
C8A901012F81000100000001 /* GatewayServerAuthorizationService.swift */
```

把 file reference 放入 Gateway `Model` group，并把四个 build file 分别加入与 `WiFiSSIDProvider.swift` 相同的四个 Sources build phase。不要修改其他 target membership。

- [ ] **Step 6: 运行契约并确认 GREEN**

Run:

```bash
scripts/check_wifi_gateway_server_information_recovery.sh
git diff --check
```

Expected: 脚本输出 `PASS: WiFi Gateway Server Authorization service contracts`；`git diff --check` 无输出。

- [ ] **Step 7: 提交共享服务**

```bash
git add scripts/check_wifi_gateway_server_information_recovery.sh SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add gateway server authorization service"
```

---

### Task 2: 让 Fast Add 与 Cloud Sync 复用授权规则

**Files:**
- Modify: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Modify: `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift:510-544`
- Modify: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:530-760`

**Interfaces:**
- Consumes: `GatewayServerAuthorizationService.shared.authorize(gateway:node:policy:)`。
- Produces: `CloudSynchronizationHandle.gatewayAuthorizationTask`，让 Cloud cancel 使当前 waiter 失效。
- Guarantee: Add 仍允许后续现有流程自行决定总体成功；Cloud 使用 `.always` 发起注册，本地目标为空且响应无完整凭据时必须进入 failure，已有有效目标时不因更新响应未重复返回凭据而清空。

- [ ] **Step 1: 扩展 Add/Cloud 失败契约**

在脚本成功输出前增加：

```bash
add_controller="SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift"
cloud_manager="SunSmart/Common/Cloud/CloudSynchronizationManager.swift"

rg -n "GatewayServerAuthorizationService\.shared\.authorize" "$add_controller" >/dev/null \
  || fail "Fast Add must use the shared Authorization service"
if rg -n 'mqttUsername|mqttPassword|mqttClientId' "$add_controller" >/dev/null; then
  fail "Fast Add must not keep a duplicate Gateway Register parser"
fi
rg -n "GatewayServerAuthorizationService\.shared\.authorize" "$cloud_manager" >/dev/null \
  || fail "Cloud sync must use the shared Authorization service"
rg -n "policy: \.always" "$cloud_manager" >/dev/null \
  || fail "Cloud sync must still upload/register when a local target exists"
rg -n "gatewayAuthorizationTask\?\.cancel\(\)" "$cloud_manager" >/dev/null \
  || fail "Cloud cancellation must invalidate the Authorization waiter"
rg -n "gateway\.syncCloudError = authorizationError\.networkApiError" "$cloud_manager" >/dev/null \
  || fail "Missing credentials must fail Cloud sync when no local target exists"
```

- [ ] **Step 2: 运行脚本并验证 RED**

Run: `scripts/check_wifi_gateway_server_information_recovery.sh`

Expected: FAIL at `Fast Add must use the shared Authorization service`。

- [ ] **Step 3: 替换 Fast Add 内联解析**

在 `appendMessagesBack` 的 Gateway Task 中，用以下调用替换 `networkable`、`node.export()`、Gateway Register switch 和 MQTT 字段解析块：

```swift
                    _ = await GatewayServerAuthorizationService.shared.authorize(
                        gateway: gatewayModel,
                        node: node,
                        policy: .ifMissing
                    )

                    let syncDatas = node.getNodeSyncGatewayData(gateway: gatewayModel)
```

失败时仍按现有 Fast Add 语义继续计算其他 append messages；不要新增回滚、删除或新的 Add 成功判定。

- [ ] **Step 4: 让 Cloud syncGateway 通过共享服务发起注册**

在 `CloudSynchronizationHandle` 的 `requestHandle` 后增加：

```swift
    /// Gateway Register 使用共享服务；取消时只使当前 Cloud waiter 失效，
    /// 同 Gateway 的其他 Add/Repair/Authorize waiter 可继续复用底层请求。
    private var gatewayAuthorizationTask: _Concurrency.Task<Void, Never>?
```

在 `cancel()` 中增加：

```swift
        gatewayAuthorizationTask?.cancel()
        gatewayAuthorizationTask = nil
```

在 `syncOperation()` 设置 `.inProgress`、发送状态回调并执行现有 `requestHandle?.cancel()` 后，紧接着、创建通用 API 之前增加：

```swift
        if case .syncGateway(let gateway, let node) = operation {
            gatewayAuthorizationTask?.cancel()
            gatewayAuthorizationTask = AsyncTask { [weak self] in
                guard let self else { return }
                let result = await GatewayServerAuthorizationService.shared.authorize(
                    gateway: gateway,
                    node: node,
                    policy: .always
                )
                guard !Task.isCancelled else { return }

                switch result {
                case .success:
                    self.state = .successful
                    gateway.lastUploadCloudTimestamp = gateway.lastUpdate
                    gateway.syncCloudError = nil
                case .failure(let authorizationError):
                    self.state = .failure(error: authorizationError.networkApiError)
                    gateway.syncCloudError = authorizationError.networkApiError
                }
                gateway.save()
                self.gatewayAuthorizationTask = nil
                DispatchQueue.main.async {
                    self.handleCallback?(self, self.state)
                }
            }
            return
        }
```

通用 `NetworkRequest` 成功 switch 中的 `.syncGateway` 分支成为不可达兜底；保留为最小安全分支但不得再承担 credential 解析。不要打印 Gateway Register 响应或 MQTT 字段值。

- [ ] **Step 5: 运行契约和现有 Cloud 诊断检查**

Run:

```bash
scripts/check_wifi_gateway_server_information_recovery.sh
git diff --check
```

Expected: 新增 Add/Cloud 断言全部通过，脚本输出 PASS；无空白错误。

- [ ] **Step 6: 提交 Add/Cloud 复用**

```bash
git add scripts/check_wifi_gateway_server_information_recovery.sh SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift
git commit -m "fix: persist gateway server authorization data"
```

---

### Task 3: 把 Server Authorization 纳入 Recovery 任务图

**Files:**
- Modify: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:181-637`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:668-735`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:1300-1335`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:480-505`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1669-1808`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2109-2565`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:3003-3105`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:3578-3610`
- Modify: `SunSmart/Main/Space/View/SyncDevicesProgressView.swift:157-181`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Produces: `ActionType.gatewayServerAuthorization(gateway:)`。
- Produces: `ActionType.gatewayServerInformation(gateway:)`，每次访问 `messageHandles` 时读取最新持久化目标。
- Produces: `ActionType.gatewayServerInformationVerification(gateway:)`。
- Produces: `SyncType.gatewayServerRecovery(node:gateway:)`，供 WiFi Authorize 使用。
- Produces: `makeGatewayServerRecoverySteps(node:gateway:authorizationDependencies:includesVerification:) -> [SyncDeviceStepModel]`。
- Consumes: `GatewayServerAuthorizationService.shared.authorize(...)`。
- Guarantee: Server Authorization 失败只阻塞 Server Information 与验证；其他依赖 Initialize 的 Mesh 任务继续。

- [ ] **Step 1: 扩展任务图失败契约**

在脚本成功输出前增加：

```bash
cell_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
sync_controller="SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
progress_view="SunSmart/Main/Space/View/SyncDevicesProgressView.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "case gatewayServerAuthorization\(gateway: GatewayModel\)" "$cell_model" >/dev/null \
  || fail "ActionType must define Server Authorization"
rg -n "case gatewayServerInformation\(gateway: GatewayModel\)" "$cell_model" >/dev/null \
  || fail "Server Information must read GatewayModel dynamically"
rg -n "GatewayServerAuthorizationService\.isValid\(gateway\.mqttServerInfo\)" "$cell_model" >/dev/null \
  || fail "Recovery verification must require a valid local MQTT target"
rg -n "case gatewayServerRecovery\(" "$sync_controller" >/dev/null \
  || fail "SyncType must define focused server recovery"
rg -n "makeGatewayServerRecoverySteps" "$sync_controller" >/dev/null \
  || fail "Repair and Authorize must share a server task builder"
rg -n "completeGatewayServerAuthorizationTaskIfNeeded" "$sync_controller" >/dev/null \
  || fail "Sync worker must execute the HTTP Authorization task"
rg -n "authorizationDependencies" "$sync_controller" >/dev/null \
  || fail "Server Information must depend on Authorization"
rg -n "failureMessage" "$cell_model" "$progress_view" >/dev/null \
  || fail "Authorization errors must be visible in task details"
rg -n '"server_authorization" = "Server Authorization";' "$en_strings" >/dev/null \
  || fail "English Server Authorization localization is missing"
rg -n '"server_authorization" = "服务器授权";' "$zh_strings" >/dev/null \
  || fail "Chinese Server Authorization localization is missing"
```

- [ ] **Step 2: 运行脚本并验证 RED**

Run: `scripts/check_wifi_gateway_server_information_recovery.sh`

Expected: FAIL at `ActionType must define Server Authorization`。

- [ ] **Step 3: 增加动态服务器 ActionType 和成功条件**

在 `ActionType` 的 Gateway cases 中增加：

```swift
    /// WiFi 网关恢复：向服务器注册并持久化 MQTT 目标
    case gatewayServerAuthorization(gateway: GatewayModel)
    /// WiFi 网关恢复：执行时读取最新 MQTT 目标并下发
    case gatewayServerInformation(gateway: GatewayModel)
    /// WiFi 网关 Authorize：只验证服务器信息是否收敛
    case gatewayServerInformationVerification(gateway: GatewayModel)
```

在 `.configuration` 的 `isSuccessful` switch 中增加，并收紧 Recovery Verification：

```swift
            case .gatewayServerAuthorization(let gateway):
                return GatewayServerAuthorizationService.isValid(gateway.mqttServerInfo)
            case .gatewayServerInformation(let gateway),
                 .gatewayServerInformationVerification(let gateway):
                guard let target = gateway.mqttServerInfo,
                      GatewayServerAuthorizationService.isValid(target),
                      let current = node.gatewayInfo?.mqttConnectInfo else {
                    return false
                }
                return current == target
            case .gatewayRecoveryVerification(let gateway):
                let serverInformationComplete = !node.isWiFiGateway
                    || GatewayServerAuthorizationService.isValid(gateway.mqttServerInfo)
                return serverInformationComplete
                    && node.isKeybindComplete
                    && node.getNodeSyncGatewayData(gateway: gateway).isEmpty
```

在 `.configuration` 的 `messageHandles` switch 中增加：

```swift
            case .gatewayServerAuthorization,
                 .gatewayServerInformationVerification:
                break
            case .gatewayServerInformation(let gateway):
                guard let information = gateway.mqttServerInfo,
                      GatewayServerAuthorizationService.isValid(information) else {
                    break
                }
                messageHandles.append(
                    contentsOf: NodeSyncData
                        .syncGatewayMQTTInformation(mqttInformation: information)
                        .getMessageHandles(node: node)
                )
```

在 `.delete` 的 `isSuccessful` switch 中，把现有 Gateway no-op 分支扩展为：

```swift
            case .gatewayRecoveryInitialization,
                 .gatewayRepairInitialization,
                 .gatewayRecoveryVerification,
                 .gatewayRecoveryAssociatedSpace,
                 .gatewayServerAuthorization,
                 .gatewayServerInformation,
                 .gatewayServerInformationVerification:
                return true
```

在 `.delete` 的 `messageHandles` switch 中做相同扩展并 `break`。`.read` switch 已有 `default`，不增加任何读取行为。

- [ ] **Step 4: 让任务模型保存具体失败信息**

在 `SyncDeviceStepTaskModel` 增加：

```swift
    /// 仅用于任务详情展示，不记录认证字段或完整响应
    var failureMessage: String?
```

修改 `markSkipped()` 和 `resetSkippedState()`：

```swift
    func markSkipped() {
        failureMessage = nil
        isSkipped = true
        state = .failed
        isFineshed = true
    }

    func resetSkippedState() {
        failureMessage = nil
        isSkipped = false
    }
```

在 `SyncDevicesProgressViewCell.taskModel` 的 failed 分支使用：

```swift
                failureLabel.text = taskModel.isSkipped
                    ? "skipped".localizedString
                    : taskModel.failureMessage ?? "failure".localizedString
```

- [ ] **Step 5: 增加可复用服务器任务构建器**

在 `makeGatewayRecoveryDeviceModel` 前增加：

```swift
    private func makeGatewayServerRecoverySteps(
        node: Node,
        gateway: GatewayModel,
        authorizationDependencies: [SyncDeviceStepModel],
        includesVerification: Bool
    ) -> [SyncDeviceStepModel] {
        let authorizationTask = SyncDeviceStepTaskModel(
            name: "server_authorization".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayServerAuthorization(gateway: gateway)
            )
        )
        let authorizationStep = SyncDeviceStepModel(
            type: "server_authorization".localizedString,
            state: .none,
            tasks: [authorizationTask]
        )
        authorizationTask.parentStepModel = authorizationStep
        authorizationStep.relevanceStepModels = authorizationDependencies

        let informationTask = SyncDeviceStepTaskModel(
            name: "server_information".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayServerInformation(gateway: gateway)
            )
        )
        let informationStep = SyncDeviceStepModel(
            type: "server_information".localizedString,
            state: .none,
            tasks: [informationTask]
        )
        informationTask.parentStepModel = informationStep
        informationStep.relevanceStepModels = authorizationDependencies + [authorizationStep]

        var steps = [authorizationStep, informationStep]
        if includesVerification {
            let verificationTask = SyncDeviceStepTaskModel(
                name: "gateway_recovery_verification".localizedString,
                operationType: .configuration(
                    node: node,
                    type: .gatewayServerInformationVerification(gateway: gateway)
                )
            )
            let verificationStep = SyncDeviceStepModel(
                type: "gateway_recovery_verification".localizedString,
                state: .none,
                tasks: [verificationTask]
            )
            verificationTask.parentStepModel = verificationStep
            verificationStep.relevanceStepModels = [informationStep]
            steps.append(verificationStep)
        }
        return steps
    }
```

在完整 `makeGatewayRecoveryDeviceModel` 中：

- WiFi Gateway 始终追加 `makeGatewayServerRecoverySteps(..., authorizationDependencies: [initializeStep], includesVerification: false)`；
- 删除原先仅在 `mqttServerInfo != nil` 时创建 WiFi Server Information 的分支；
- 非 WiFi Gateway 保留原有 `if let mqttServerInfo` 静态任务；
- Final Verification 继续依赖 `steps` 中所有前置步骤。

实际 WiFi 分支应为：

```swift
        if node.isWiFiGateway {
            steps.append(
                contentsOf: makeGatewayServerRecoverySteps(
                    node: node,
                    gateway: gateway,
                    authorizationDependencies: [initializeStep],
                    includesVerification: false
                )
            )
        } else if let mqttServerInfo = gateway.mqttServerInfo {
            let serverTask = SyncDeviceStepTaskModel(
                name: "server_information".localizedString,
                operationType: .configuration(
                    node: node,
                    type: .gatewayMQTTInformation(mqttInformation: mqttServerInfo)
                )
            )
            let serverStep = SyncDeviceStepModel(
                type: "server_information".localizedString,
                state: .none,
                tasks: [serverTask]
            )
            serverTask.parentStepModel = serverStep
            serverStep.relevanceStepModels = [initializeStep]
            steps.append(serverStep)
        }
```

- [ ] **Step 6: 增加 focused Server Recovery SyncType**

在 `SyncType` 增加：

```swift
        /// WiFi Gateway 手动 Authorize 的服务器恢复子链
        case gatewayServerRecovery(node: Node, gateway: GatewayModel)
```

在 `setupDataSource()` switch 增加：

```swift
            case .gatewayServerRecovery(let node, let gateway):
                guard node.isWiFiGateway else {
                    syncState = .syncFailure
                    break
                }
                let steps = makeGatewayServerRecoverySteps(
                    node: node,
                    gateway: gateway,
                    authorizationDependencies: [],
                    includesVerification: true
                )
                let deviceModel = SyncDevicesModel(
                    name: node.name ?? gateway.name,
                    address: node.primaryUnicastAddress
                )
                deviceModel.imageName = node.iconName
                deviceModel.steps = steps
                steps.forEach { $0.parentDeviceModel = deviceModel }
                configurationSection.devices.append(deviceModel)
```

将 `gatewayRecoveryNode` 扩展为：

```swift
    private var gatewayRecoveryNode: Node? {
        switch type {
        case .gatewayRecovery(let node, _, _),
             .gatewayServerRecovery(let node, _):
            return node
        default:
            return nil
        }
    }
```

- [ ] **Step 7: 在 Sync worker 中执行 HTTP Authorization**

在 `startSync()` 前增加：

```swift
    private func completeGatewayServerAuthorizationTaskIfNeeded(
        for model: SyncCellModel,
        syncRunIdentifier: UUID
    ) -> Bool {
        guard let taskModel = model as? SyncDeviceStepTaskModel,
              case .configuration(let node, let type) = taskModel.operationType,
              case .gatewayServerAuthorization(let gateway) = type else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let result = await GatewayServerAuthorizationService.shared.authorize(
                gateway: gateway,
                node: node,
                policy: .ifMissing
            )
            guard self.isActiveSyncRun(syncRunIdentifier) else {
                semaphore.signal()
                return
            }
            switch result {
            case .success:
                taskModel.failureMessage = nil
                taskModel.state = .successful
            case .failure(let error):
                taskModel.failureMessage = error.localizedDescription
                taskModel.state = .failed
                taskModel.failedCount += 1
            }
            self.updateCell(model: taskModel)
            semaphore.signal()
        }
        semaphore.wait()
        return true
    }
```

在 `startSync()` 已把 model 置为 `.inSettings` 且刷新 UI 后、Profile/EFC 特殊任务之前增加：

```swift
                if self.completeGatewayServerAuthorizationTaskIfNeeded(
                    for: model,
                    syncRunIdentifier: syncRunIdentifier
                ) {
                    continue
                }
```

现有 `getNextHandleModel()` 会继续选择不依赖 Authorization 的 Mesh steps；循环结束时 `markPendingGatewayRecoveryTasksSkipped()` 会把 Server Information 与 Verification 标记为 Skipped。现有 `prepareDeviceForResync` 保留 Success tasks，并重置 Failed/Skipped tasks；只需确保 `prepareTaskForResync` 通过 `resetSkippedState()` 清空 `failureMessage`。

- [ ] **Step 8: 增加本地化**

追加：

```text
// SunSmart/en.lproj/Localizable.strings
"server_authorization" = "Server Authorization";

// SunSmart/zh-Hans.lproj/Localizable.strings
"server_authorization" = "服务器授权";
```

- [ ] **Step 9: 运行任务图契约与既有 Repair 回归**

Run:

```bash
scripts/check_wifi_gateway_server_information_recovery.sh
scripts/check_wifi_gateway_repair_recovery.sh
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: 两个脚本均 PASS；两个 strings 文件均 `OK`；无空白错误。

- [ ] **Step 10: 提交 Recovery 任务图**

```bash
git add scripts/check_wifi_gateway_server_information_recovery.sh SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/View/SyncDevicesProgressView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: require server information in gateway recovery"
```

---

### Task 4: 让 WiFi Gateway Authorize 复用服务器恢复子链

**Files:**
- Modify: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:20-165`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:691-785`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1210-1280`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:220-260`

**Interfaces:**
- Produces: `GatewayViewController.performServerAuthorization()`，默认保留其他 Gateway 的 legacy Authorize。
- Produces: `GatewayViewController.recoverServerInformation()`，打开 `.gatewayServerRecovery`。
- Produces: `GatewayViewController.refreshServerInformationFromPersistence()`，只刷新不可编辑的 Server Information 字段。
- Consumes: `WiFiGatewayViewController.prepareForGatewayRecovery(_:)`，等待自动 WiFi acknowledged 请求，阻止用户主动网络操作期间并发。
- Guarantee: WiFi Authorize 不直接调用 `MeshAPI.sendMessage`，不使用 Window 级无限 HUD，不存在 Node export 或响应字段失败后静默返回。

- [ ] **Step 1: 扩展页面分流失败契约**

在脚本成功输出前增加：

```bash
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

rg -n "func performServerAuthorization\(\)" "$gateway_controller" >/dev/null \
  || fail "Gateway controller must expose an overridable Authorization hook"
rg -n "func recoverServerInformation\(\)" "$gateway_controller" >/dev/null \
  || fail "Gateway controller must expose focused server recovery navigation"
rg -n "refreshServerInformationFromPersistence" "$gateway_controller" >/dev/null \
  || fail "Gateway page must refresh persisted Server Information"
rg -n "override func performServerAuthorization\(\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must override Authorize"
rg -n "recoverServerInformation\(\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Authorize must enter the focused Sync chain"
rg -n "prepareForGatewayRecovery" "$wifi_controller" >/dev/null \
  || fail "WiFi Authorize must reuse the acknowledged-request coordinator"
rg -n "self\.performServerAuthorization\(\)" "$gateway_controller" >/dev/null \
  || fail "Server Information header must call the overridable hook"
```

- [ ] **Step 2: 运行脚本并验证 RED**

Run: `scripts/check_wifi_gateway_server_information_recovery.sh`

Expected: FAIL at `Gateway controller must expose an overridable Authorization hook`。

- [ ] **Step 3: 增加 Server Information 持久化刷新**

在 `GatewayViewController` 增加：

```swift
    func refreshServerInformationFromPersistence() {
        guard let persistedGateway = GatewayModel.load(
            siteId: gatewayModel.siteId,
            macAddress: gatewayModel.mac
        ).first else {
            return
        }
        gatewayModel.mqttServerInfo = persistedGateway.mqttServerInfo
        setGatewayModel.mqttServerInfo = persistedGateway.mqttServerInfo
    }
```

在 `viewWillAppear` 的 `updateData()` 之前调用：

```swift
        refreshServerInformationFromPersistence()
```

只同步 `mqttServerInfo`，不得覆盖用户尚未保存的 Name、Associated Spaces、APN 或 Activate 工作副本。

- [ ] **Step 4: 增加可覆盖 Authorize hook 和 focused 导航**

保留现有 `authorizeRequest()` 作为其他 Gateway 的 legacy 实现，并增加：

```swift
    func performServerAuthorization() {
        authorizeRequest()
    }

    func recoverServerInformation() {
        guard !isPresentingGatewayRecovery,
              let navigationController else {
            return
        }
        isPresentingGatewayRecovery = true

        let controller = SyncDevicesViewController(
            type: .gatewayServerRecovery(
                node: node,
                gateway: gatewayModel
            )
        )
        controller.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            self.refreshServerInformationFromPersistence()
            self.updateData()
            self.updateSaveBtnState()
            self.tableView.reloadData()
            NotificationCenter.default.post(
                name: .init(siteGatewayDataChangedNotificaitonName),
                object: self.gateway
            )
        }
        navigationController.pushViewController(controller, animated: true)
    }
```

把 Server Information header 的点击分支从 `self.authorizeRequest()` 改为：

```swift
                self.performServerAuthorization()
```

在现有完整 Recovery 的 `syncSuccessCallback` 中也先调用 `refreshServerInformationFromPersistence()`，再刷新 table/header。

- [ ] **Step 5: WiFi Gateway 覆盖 Authorize**

在 `performGatewayRepair()` 后增加：

```swift
    override func performServerAuthorization() {
        prepareForGatewayRecovery { [weak self] in
            self?.recoverServerInformation()
        }
    }
```

不要增加额外 Window HUD。`prepareForGatewayRecovery` 已处理：权限、Gateway Offline、用户主动 Connect/Disconnect/Refresh、自动 WiFi 请求等待和重复 pending action。

- [ ] **Step 6: 运行页面与并发回归契约**

Run:

```bash
scripts/check_wifi_gateway_server_information_recovery.sh
scripts/check_wifi_gateway_repair_recovery.sh
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_disconnect_clear_credentials.sh
git diff --check
```

Expected: 四个脚本全部 PASS；无空白错误。

- [ ] **Step 7: 提交 WiFi Authorize 页面路径**

```bash
git add scripts/check_wifi_gateway_server_information_recovery.sh SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "fix: recover WiFi gateway server authorization"
```

---

### Task 5: 完成静态回归、四品牌构建与验收记录

**Files:**
- Create: `docs/260710_1715_wifi_gateway_server_information_recovery_implementation_summary.md`
- Verify only: 所有本轮修改文件

**Interfaces:**
- Consumes: Tasks 1-4 的完整实现。
- Produces: 可审计的静态检查、四品牌构建结果、API/真机已执行与未执行矩阵。
- Guarantee: 未连接真实 Gateway 或未确认重复注册合同，不宣称现场问题完全修复。

- [ ] **Step 1: 运行新增与所有相关既有契约**

Run:

```bash
scripts/check_wifi_gateway_server_information_recovery.sh
scripts/check_wifi_gateway_repair_recovery.sh
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_disconnect_clear_credentials.sh
scripts/check_wifi_gateway_sig_mesh_status_header.sh
scripts/check_wifi_gateway_wifi_status_header.sh
scripts/check_wifi_gateway_apn_removed.sh
scripts/check_wifi_gateway_info_rows_hidden.sh
scripts/check_wifi_gateway_menu_icons.sh
scripts/check_gateway_associated_spaces_deferred_save.sh
```

Expected: 每个脚本都输出 PASS，全部 exit 0。

- [ ] **Step 2: 审计凭据和旧直发边界**

Run:

```bash
rg -n 'print\(.*(mqttUsername|mqttPassword|mqttClientId|Gateway Register|response)' SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift SunSmart/Common/Cloud/CloudSynchronizationManager.swift SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift
rg -n 'wifiGatewayCredentials|wifiGatewayCredentialsSet|wifiGatewayCredentialsClear|ssid|password' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
rg -n 'MeshAPI\.sendMessage.*gatewayMQTTConnectInfoSet' SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
```

Expected: 三条命令均无命中并以预期 exit 1 结束。Authorization 服务源码本身包含 `mqttPassword` 解析字段，因此第一条只检查 `print(...)`；不得把“字段解析存在”误报为日志泄露。

- [ ] **Step 3: 校验本地化、项目文件和空白**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check HEAD~4..HEAD
git status --short
```

Expected: 两个 strings 文件均 `OK`；diff 无空白错误；除待创建总结外工作区干净。

- [ ] **Step 4: 构建 SunSmart generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0 且输出 `BUILD SUCCEEDED`；允许工程既有 warning，不允许新增 compile error。

- [ ] **Step 5: 构建 Archipelago generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0 且输出 `BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SLG Sync Plus generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0 且输出 `BUILD SUCCEEDED`。

- [ ] **Step 7: 构建 SylSmart generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0 且输出 `BUILD SUCCEEDED`。

- [ ] **Step 8: 执行或明确记录 API/真机矩阵**

逐项记录：

```text
1. Gateway Register 对已注册 Gateway 重复调用是否返回/重签完整 MQTT credentials
2. 在线 Repair：Server Authorization -> Server Information -> Final Verification 全成功
3. 离线 Repair：Mesh tasks 继续，Authorization failed，后继 skipped，整体失败
4. 恢复网络 Retry：已成功 Mesh tasks 不重跑，只执行服务器失败链和验证
5. 手动 Authorize：进入服务器 Sync 子链，成功后页面警告消失
6. Authorize 与自动 WiFi acknowledged request：等待前置请求，不并发发送
7. Server Information 下发中 Gateway 断电：任务失败，可 Retry，不提前成功
8. 后台 syncGateway：有效 credentials 被持久化，不被丢弃
```

没有真实设备或服务端观测条件时，在总结中写“未执行”和原因，不得写“通过”。

- [ ] **Step 9: 编写实施总结**

创建 `docs/260710_1715_wifi_gateway_server_information_recovery_implementation_summary.md`，固定包含：

```markdown
# WiFi Gateway Server Information 恢复实施总结

## 结论

## 实施内容

## 静态验证

## iPhoneOS 构建

## API 合同确认

## 真机验收矩阵

## 未完成项与风险
```

只填写实际命令结果和已执行事实；不得把源码契约或 build 通过等同于现场修复通过。

- [ ] **Step 10: 提交总结**

```bash
git add docs/260710_1715_wifi_gateway_server_information_recovery_implementation_summary.md
git commit -m "docs: summarize WiFi gateway server recovery"
```

- [ ] **Step 11: 最终工作区检查**

Run:

```bash
git status --short
git log -5 --oneline
```

Expected: 工作区干净；最近提交依次覆盖共享服务、Add/Cloud、Recovery 任务图、WiFi Authorize 和实施总结。

---

## 实施顺序与检查点

1. Task 1 完成后检查共享服务错误分类、持久化回滚和四 target membership。
2. Task 2 完成后检查 Fast Add 总体语义未改变、Cloud nil 目标不会假成功。
3. Task 3 完成后检查离线依赖图和 Retry：Success 保留、Failed/Skipped 后继重置。
4. Task 4 完成后检查 WiFi 与其他 Gateway 分流，以及 Authorize 不再绕过 Mesh 串行。
5. Task 5 完成后检查四品牌构建与真机/API 未执行项是否如实记录。

默认按项目规则使用 `2. Inline Execution`，由 `superpowers:executing-plans` 在当前会话按 Task 1-5 分阶段执行与检查，不启用 subagents。
