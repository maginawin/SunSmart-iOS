# WiFi Gateway Repair 完整恢复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本项目明确采用 Inline Execution，不使用 subagents。

**Goal:** 让 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 在 Adding 中断后通过一次 Repair 完成 Composition、Key Bind 和 Gateway 业务恢复，并保证成功返回后不再展示 `Devices not synced`。

**Architecture:** 在现有 `.gatewayRecovery` 中增加 `repair` 与 `devicesNotSynced` 两种触发来源。Repair 使用两阶段 Initialize：Composition 不完整时先读取 Composition，再动态追加强制 Key/Bind 和剩余基础配置；随后复用现有 Associated Spaces、Project、Sync Spaces、Server 任务，最后用独立 Verification 任务验证 `isKeybindComplete` 与 Gateway 差异为空。Gateway 页面只负责状态渲染和导航，WiFi 子类负责隐藏 SAVE、阻止 Repair 状态自动请求以及复用现有请求协调器。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SnapKit、Bash/`rg` 源码契约检查、Xcode `xcodebuild` generic iPhoneOS。

## Global Constraints

- 仅处理 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 页面路径。
- Repair 与 `Devices not synced` 共用现有 Gateway Recovery 执行器，但使用不同 Initialize 模式。
- Repair 状态隐藏 SAVE；其他设备和 4G Gateway 的 Repair 行为保持不变。
- 不修改 Fast Add 的整体成功判定、回滚或删除策略。
- 不修改普通 Save 的差异同步策略。
- Recovery 不读取、保存或重新下发 WiFi SSID、Password。
- 不新增 Auth 信息。
- App 现有公开能力足够时不修改 NordicSigMeshSDK；若实施中证明确实不足，停止并重新确认 SDK 变更范围。
- 所有新增用户可见文案同时支持 English 和简体中文；禁止硬编码用户可见文案。
- 不顺手重构无关模块，不格式化大范围无关文件。
- 重要分析、计划和总结保存在 `docs/`，文件名遵循 `yyMMdd_HHmm_[description].md`。
- iOS 验证直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 Simulator、shell wrapper 或日志重定向。
- 修改共享代码或本地化后，必须验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 scheme。
- 当前工程没有可用的 App XCTest target；本计划使用聚焦源码契约脚本先行，并以 iPhoneOS build 和真机矩阵作为最终验证。
- 真机断电矩阵未执行前，不得宣称现场问题已经完全修复。

---

## 文件结构与职责

- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 构造 Repair Composition 消息和 Composition 完成后的强制基础配置消息；不处理页面和结果聚合。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 定义 `gatewayRepairInitialization`、`gatewayRecoveryVerification` 两种操作，并提供消息与成功条件。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 定义 Recovery trigger、组装任务图、在 Composition Status 后动态追加配置、隔离运行标识并聚合最终结果。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 保留其他 Gateway 的通用 Repair；让 WiFi Gateway 可覆盖 Repair 行为并进入带 trigger 的 Gateway Recovery；返回时刷新页面主状态。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Repair 状态隐藏 SAVE；Repair 走 Recovery；Key Bind 不完整时不启动 WiFi 自动请求。
- `SunSmart/en.lproj/Localizable.strings`
  - 增加 Verification 任务英文标题。
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 Verification 任务简体中文标题。
- `scripts/check_wifi_gateway_repair_recovery.sh`
  - 守住 Repair builder、任务图、成功语义、页面分流、WiFi 请求门禁和凭据排除边界。
- `docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md`
  - 记录最终静态检查、四品牌构建和未执行的真机验收项。

---

### Task 1: 增加 Repair 两阶段初始化消息构建器

**Files:**
- Create: `scripts/check_wifi_gateway_repair_recovery.sh`
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift:59-169`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:216-637`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:648-710`

**Interfaces:**
- Consumes: `Node.getForcedGatewayInitializationMessageHandles()`、`Node.getConfigMessageHandles()`、`Node.isKeybindComplete`。
- Produces: `Node.getGatewayRepairCompositionMessageHandles() -> [MeshMessageHandle]`。
- Produces: `Node.getGatewayRepairInitializationMessageHandles() -> [MeshMessageHandle]`。
- Produces: `ActionType.gatewayRepairInitialization`。
- Guarantee: Repair Composition 不完整时只先返回 Composition Get；Composition 已完整时直接返回强制基础配置；任何 builder 都不生成 WiFi Credentials 消息。

- [ ] **Step 1: 创建 Repair Recovery 源码契约脚本的失败基线**

创建 `scripts/check_wifi_gateway_repair_recovery.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

message_handles="SunSmart/Common/Data/Node+MessageHandles.swift"
cell_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
sync_controller="SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "func getGatewayRepairCompositionMessageHandles\(\) -> \[MeshMessageHandle\]" "$message_handles" >/dev/null \
  || fail "Repair must expose a Composition-stage builder"
rg -n "ConfigCompositionDataGet\(\)" "$message_handles" >/dev/null \
  || fail "Repair Composition builder must send ConfigCompositionDataGet"
rg -n "func getGatewayRepairInitializationMessageHandles\(\) -> \[MeshMessageHandle\]" "$message_handles" >/dev/null \
  || fail "Repair must expose a post-Composition initialization builder"
rg -n "getForcedGatewayInitializationMessageHandles\(\)" "$message_handles" >/dev/null \
  || fail "Repair initialization must reuse forced Gateway key/bind handles"
rg -n "getConfigMessageHandles\(\)\.filter" "$message_handles" >/dev/null \
  || fail "Repair initialization must append remaining normal configuration"
rg -n "ConfigNetKeyAdd|ConfigAppKeyAdd|ConfigModelAppBind" "$message_handles" >/dev/null \
  || fail "Repair initialization must explicitly filter duplicate key/bind messages"
rg -n "case gatewayRepairInitialization" "$cell_model" >/dev/null \
  || fail "ActionType must define gatewayRepairInitialization"
rg -n "getGatewayRepairCompositionMessageHandles\(\)" "$cell_model" >/dev/null \
  || fail "Repair action must choose the Composition stage first"
awk '
  /case \.gatewayRepairInitialization:/ {
    getline
    if ($0 ~ /return node\.isKeybindComplete/) found = 1
  }
  END { exit(found ? 0 : 1) }
' "$cell_model" \
  || fail "Repair initialization success must require isKeybindComplete"

echo "PASS: WiFi Gateway Repair initialization contracts"
```

- [ ] **Step 2: 赋予脚本执行权限并验证失败**

Run:

```bash
chmod +x scripts/check_wifi_gateway_repair_recovery.sh
scripts/check_wifi_gateway_repair_recovery.sh
```

Expected: FAIL，首个失败为 `Repair must expose a Composition-stage builder`。

- [ ] **Step 3: 在 Node 消息扩展中增加两阶段 Repair builder**

在 `getForcedGatewayAssociatedSpaceMessageHandles(...)` 之后、`extension Node` 结束前增加：

```swift
    func getGatewayRepairCompositionMessageHandles() -> [MeshMessageHandle] {
        let hasCompositionModels = elements.contains { !$0.models.isEmpty }
        guard elements.isEmpty || !hasCompositionModels || companyIdentifier == nil else {
            return []
        }

        let handle = MeshMessageHandle(
            message: ConfigCompositionDataGet(),
            address: primaryUnicastAddress
        )
        handle.continuous = false
        return [handle]
    }

    func getGatewayRepairInitializationMessageHandles() -> [MeshMessageHandle] {
        var messageHandles = getForcedGatewayInitializationMessageHandles()
        let completionHandles = getConfigMessageHandles().filter { handle in
            switch handle.message {
            case is ConfigNetKeyAdd,
                 is ConfigAppKeyAdd,
                 is ConfigModelAppBind:
                return false
            default:
                return true
            }
        }
        messageHandles.append(contentsOf: completionHandles)
        return messageHandles
    }
```

该过滤只去掉已经由 forced builder 无条件生成的 Key/Bind，保留 Publish、Subscription、Sensor Descriptor、Firmware Information 和 Composition Hash 等正常完成项。

- [ ] **Step 4: 在 ActionType 中增加 Repair Initialize**

在 `gatewayRecoveryInitialization` 后增加：

```swift
    /// WiFi 网关 Repair：Composition 完成后强制重下发基础配置
    case gatewayRepairInitialization
```

在 `DeviceOperationType.isSuccessful` 的 `.configuration` switch 中，将初始化分支改为：

```swift
            case .deviceInitialize:
                return node.isKeybindComplete
            case .gatewayRecoveryInitialization:
                return true
            case .gatewayRepairInitialization:
                return node.isKeybindComplete
```

在 `.delete` switch 中把无需处理的分支扩展为：

```swift
            case .gatewayRecoveryInitialization,
                 .gatewayRepairInitialization,
                 .gatewayRecoveryAssociatedSpace:
                return true
```

在 `.delete` 的 `messageHandles` switch 中把空操作分支扩展为：

```swift
            case .gatewayRecoveryInitialization,
                 .gatewayRepairInitialization,
                 .gatewayRecoveryAssociatedSpace:
                break
```

在 `.configuration` 的 `messageHandles` switch 中，在 `gatewayRecoveryInitialization` 后增加：

```swift
            case .gatewayRepairInitialization:
                let compositionHandles = node.getGatewayRepairCompositionMessageHandles()
                if compositionHandles.isEmpty {
                    messageHandles.append(contentsOf: node.getGatewayRepairInitializationMessageHandles())
                } else {
                    messageHandles.append(contentsOf: compositionHandles)
                }
```

- [ ] **Step 5: 运行新脚本并确认通过**

Run:

```bash
scripts/check_wifi_gateway_repair_recovery.sh
```

Expected: `PASS: WiFi Gateway Repair initialization contracts`。

- [ ] **Step 6: 审计 Repair builder 不包含 WiFi Credentials**

Run:

```bash
awk '/func getGatewayRepairCompositionMessageHandles/{flag=1} flag{print} /^    }/{if (flag && ++ends == 2) exit}' SunSmart/Common/Data/Node+MessageHandles.swift | rg -n "wifiGatewayCredentials|password|ssid"
```

Expected: 无输出，exit 1。

- [ ] **Step 7: 运行已有 Gateway 静态回归**

Run:

```bash
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_sig_mesh_status_header.sh
scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 三个脚本全部输出 PASS。

- [ ] **Step 8: 检查差异并提交**

Run:

```bash
git diff --check
git status --short
```

Expected: 只包含 Task 1 的 builder、ActionType 和新脚本改动，无 whitespace error。

Commit:

```bash
git add scripts/check_wifi_gateway_repair_recovery.sh SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "feat: add WiFi gateway repair initialization"
```

---

### Task 2: 扩展 Gateway Recovery 任务图并增加最终验证

**Files:**
- Modify: `scripts/check_wifi_gateway_repair_recovery.sh`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:216-637`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:648-710`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:478-497`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1665-1778`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2297-2383`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2615-2631`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2742-2763`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:3003-3019`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:3503-3533`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: Task 1 的 `gatewayRepairInitialization` 与两个 Node builder。
- Produces: `SyncDevicesViewController.GatewayRecoveryTrigger`，cases `.devicesNotSynced`、`.repair`。
- Produces: `SyncType.gatewayRecovery(node:gateway:trigger:)`。
- Produces: `ActionType.gatewayRecoveryVerification(gateway:)`。
- Guarantee: Repair Composition Status 后动态追加 forced 配置；Verification 必须在所有适用任务后执行；只有 `isKeybindComplete` 且 Gateway 差异为空时 Recovery 才能成功。

- [ ] **Step 1: 扩展契约脚本，建立任务图失败基线**

在脚本最终 `echo` 之前增加：

```bash
rg -n "enum GatewayRecoveryTrigger" "$sync_controller" >/dev/null \
  || fail "Sync controller must define a Gateway Recovery trigger"
rg -n "case devicesNotSynced" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define devicesNotSynced"
rg -n "case repair" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define Repair"
rg -n "case gatewayRecovery\(" "$sync_controller" >/dev/null \
  || fail "SyncType must define Gateway Recovery"
rg -n "trigger: GatewayRecoveryTrigger" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery SyncType must carry the trigger"
rg -n "var startsImmediately: Bool" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define its initial run behavior"
rg -n "case gatewayRecoveryVerification\(gateway: GatewayModel\)" "$cell_model" >/dev/null \
  || fail "ActionType must define final Gateway Recovery verification"
rg -n "node\.isKeybindComplete && node\.getNodeSyncGatewayData\(gateway: gateway\)\.isEmpty" "$cell_model" >/dev/null \
  || fail "Final verification must require key bind and empty Gateway diff"
rg -n "isGatewayRepairInitialization" "$sync_controller" >/dev/null \
  || fail "Sync controller must identify the Repair initializer"
rg -n "statusMessage is ConfigCompositionDataStatus" "$sync_controller" >/dev/null \
  || fail "Repair must append initialization after Composition Status"
rg -n "getGatewayRepairInitializationMessageHandles\(\)" "$sync_controller" >/dev/null \
  || fail "Composition success must append forced Repair initialization"
rg -n "gateway_recovery_verification" "$sync_controller" "$en_strings" "$zh_strings" >/dev/null \
  || fail "Recovery verification task must be localized"
```

- [ ] **Step 2: 运行脚本并验证失败**

Run:

```bash
scripts/check_wifi_gateway_repair_recovery.sh
```

Expected: FAIL，首个新增失败为 `Sync controller must define a Gateway Recovery trigger`。

- [ ] **Step 3: 增加最终 Verification ActionType**

在 `ActionType` 的 Gateway recovery cases 后增加：

```swift
    /// WiFi 网关恢复：验证 Key Bind 和 Gateway 业务差异均已收敛
    case gatewayRecoveryVerification(gateway: GatewayModel)
```

在 `.configuration` 的 `isSuccessful` switch 中增加：

```swift
            case .gatewayRecoveryVerification(let gateway):
                return node.isKeybindComplete && node.getNodeSyncGatewayData(gateway: gateway).isEmpty
```

在 `.configuration` 的 `messageHandles` switch 中增加空消息分支：

```swift
            case .gatewayRecoveryVerification:
                break
```

在 `.delete` 的 `isSuccessful` 和 `messageHandles` switches 中，把该 case 归入不执行删除操作的 `return true` / `break` 分支，确保所有 switch exhaustive。

- [ ] **Step 4: 定义 GatewayRecoveryTrigger 并扩展 SyncType**

在 `SyncType` 前增加：

```swift
    enum GatewayRecoveryTrigger {
        case devicesNotSynced
        case repair

        var startsImmediately: Bool {
            switch self {
            case .devicesNotSynced:
                return false
            case .repair:
                return true
            }
        }
    }
```

把 SyncType case 改为：

```swift
        /// WiFi 网关添加中断后的完整恢复
        case gatewayRecovery(
            node: Node,
            gateway: GatewayModel,
            trigger: GatewayRecoveryTrigger
        )
```

把 `setupDataSource()` 中的 pattern 改为：

```swift
            case .gatewayRecovery(let node, let gateway, let trigger):
                if let deviceModel = makeGatewayRecoveryDeviceModel(
                    node: node,
                    gateway: gateway,
                    trigger: trigger
                ) {
                    configurationSection.devices.append(deviceModel)
                } else {
                    syncState = .syncFailure
                    DispatchQueue.main.async {
                        XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
                    }
                }
```

- [ ] **Step 5: 按 trigger 选择 Initialize，并追加 Verification step**

把 builder 签名改为：

```swift
    private func makeGatewayRecoveryDeviceModel(
        node: Node,
        gateway: GatewayModel,
        trigger: GatewayRecoveryTrigger
    ) -> SyncDevicesModel? {
```

用以下代码创建 Initialize task：

```swift
        let initializationAction: ActionType
        switch trigger {
        case .devicesNotSynced:
            initializationAction = .gatewayRecoveryInitialization
        case .repair:
            initializationAction = .gatewayRepairInitialization
        }

        let initializeTask = SyncDeviceStepTaskModel(
            name: "initialize".localizedString,
            operationType: .configuration(node: node, type: initializationAction)
        )
```

在所有可选 Server step 已追加后、创建 `SyncDevicesModel` 前增加：

```swift
        let verificationTask = SyncDeviceStepTaskModel(
            name: "gateway_recovery_verification".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayRecoveryVerification(gateway: gateway)
            )
        )
        let verificationStep = SyncDeviceStepModel(
            type: "gateway_recovery_verification".localizedString,
            state: .none,
            tasks: [verificationTask]
        )
        verificationTask.parentStepModel = verificationStep
        verificationStep.relevanceStepModels = steps
        steps.append(verificationStep)
```

Verification 依赖当前 `steps` 的完整快照，因此 Associated Spaces 失败不会阻止其他独立任务执行，但最后 Verification 会进入 Skipped，Recovery 不会成功。

- [ ] **Step 6: 在 Composition Status 后动态追加 Repair 配置**

在 `successfulBack` 中，把正常 Initialize 判断前增加 Repair 分支：

```swift
                        if self.isGatewayRepairInitialization(model),
                           statusMessage is ConfigCompositionDataStatus,
                           let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                           let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            let appendedHandles = node.getGatewayRepairInitializationMessageHandles()
                            if !appendedHandles.isEmpty {
                                MeshProxyMessageCommand.shared.addMessage(
                                    messageHandles: appendedHandles,
                                    finishedBack: nil
                                )
                            }
                        } else if self.isNormalDeviceInitialization(model),
                                  statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
                            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
                               node.isInitialize {
                                MeshProxyMessageCommand.shared.addMessage(
                                    messageHandles: node.getConfigMessageHandles(),
                                    finishedBack: nil
                                )
                            }
                        }
```

原有正常 Initialize 的后续 `else if` 逻辑继续保留在该链之后。

- [ ] **Step 7: 增加 Repair Initialize 类型判断并收紧成功语义**

在 `isGatewayRecoveryInitialization` 后增加：

```swift
    private func isGatewayRepairInitialization(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model),
              case .configuration(_, let actionType) = operationType,
              case .gatewayRepairInitialization = actionType else {
            return false
        }
        return true
    }
```

在 `isSyncOperationSuccessful(...)` 最前面增加：

```swift
        if isGatewayRepairInitialization(model) {
            return !messageHandles.isEmpty && resultSuccessful && operationSuccessful
        }
```

保留现有 `gatewayRecoveryInitialization` 的 forced-handle 成功规则。Repair 的 `operationSuccessful` 来自 `node.isKeybindComplete`，因此即使所有消息收到成功 Status，只要最终基础配置仍不完整就必须失败。

- [ ] **Step 8: 更新 gatewayRecoveryNode pattern**

把 property 改为：

```swift
    private var gatewayRecoveryNode: Node? {
        guard case .gatewayRecovery(let node, _, _) = type else {
            return nil
        }
        return node
    }
```

使用 `rg -n "case \.gatewayRecovery|\.gatewayRecovery\("` 检查并更新本文件内所有旧的双参数 pattern，不保留编译不完整的 case。

- [ ] **Step 9: 增加 Verification 本地化**

在 English strings 增加：

```text
"gateway_recovery_verification" = "Verify Configuration";
```

在简体中文 strings 增加：

```text
"gateway_recovery_verification" = "验证配置";
```

- [ ] **Step 10: 运行新契约和本地化语法检查**

Run:

```bash
scripts/check_wifi_gateway_repair_recovery.sh
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: Repair script PASS；两个 strings 文件均输出 `OK`。

- [ ] **Step 11: 审计 Recovery 不包含 WiFi Credentials**

Run:

```bash
rg -n "wifiGatewayCredentials|wifiGatewayCredentialsSet|wifiGatewayCredentialsClear|password|ssid" SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected: Recovery 新增代码无 WiFi Credentials、SSID 或 password 命中；如文件其他既有路径命中，逐条确认不位于 Gateway Recovery cases 或 builders。

- [ ] **Step 12: 运行现有 Gateway 恢复相关静态回归**

Run:

```bash
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_disconnect_clear_credentials.sh
scripts/check_wifi_gateway_sig_mesh_status_header.sh
scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 全部 PASS。

- [ ] **Step 13: 检查差异并提交**

Run:

```bash
git diff --check
git status --short
```

Expected: 只包含任务图、动态初始化、Verification、本地化和脚本扩展。

Commit:

```bash
git add scripts/check_wifi_gateway_repair_recovery.sh SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add WiFi gateway repair recovery flow"
```

---

### Task 3: 路由 WiFi Repair、隐藏 SAVE 并禁止 Repair 状态自动请求

**Files:**
- Modify: `scripts/check_wifi_gateway_repair_recovery.sh`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:35-97`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:140-223`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:419-486`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:749-768`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1230-1243`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:45-143`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:203-237`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:423-477`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:858-905`

**Interfaces:**
- Consumes: Task 2 的 `GatewayRecoveryTrigger` 和三参数 `.gatewayRecovery`。
- Produces: `GatewayViewController.performGatewayRepair()` override hook，默认保留通用 Repair。
- Produces: `GatewayViewController.resync(trigger:)`。
- WiFi override: Repair 使用 `.repair`；`Devices not synced` 使用 `.devicesNotSynced`。
- Guarantee: WiFi Repair 状态隐藏底部 SAVE、不自动发送 WiFi GET、只导航一次；其他 Gateway 仍使用现有 `repairDevices`。

- [ ] **Step 1: 扩展 UI 与请求门禁契约，建立失败基线**

在脚本最终 `echo` 前增加：

```bash
rg -n "func performGatewayRepair\(\)" "$gateway_controller" >/dev/null \
  || fail "Gateway base controller must expose an overridable Repair hook"
rg -n "func resync\(trigger: SyncDevicesViewController\.GatewayRecoveryTrigger\)" "$gateway_controller" >/dev/null \
  || fail "Gateway recovery navigation must carry a trigger"
rg -n "resync\(trigger: \.devicesNotSynced\)" "$gateway_controller" >/dev/null \
  || fail "Devices not synced must use its explicit trigger"
rg -n "override func performGatewayRepair\(\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must override the base Repair behavior"
rg -n "resync\(trigger: \.repair\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Repair must enter Gateway Recovery"
rg -n "override func showRepairBottomActions\(\)[[:space:][:print:]]*" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must keep a dedicated Repair bottom-state hook"
rg -n "bottomView\.isHidden = true" "$wifi_controller" >/dev/null \
  || fail "WiFi Repair state must hide the bottom action view"
rg -n "bottomView\.isHidden = false" "$wifi_controller" >/dev/null \
  || fail "Configured WiFi Gateway state must restore the bottom action view"
rg -n "guard node\.isKeybindComplete else" "$wifi_controller" >/dev/null \
  || fail "WiFi automatic requests must be blocked while Repair is required"
rg -n "isPresentingGatewayRecovery" "$gateway_controller" >/dev/null \
  || fail "Gateway page must prevent duplicate Recovery navigation"
rg -n "repairDevices\(nodes: \[node\]" "$gateway_controller" >/dev/null \
  || fail "Base Gateway must retain legacy Repair for non-WiFi gateways"
```

- [ ] **Step 2: 运行脚本并验证失败**

Run:

```bash
scripts/check_wifi_gateway_repair_recovery.sh
```

Expected: FAIL，首个新增失败为 `Gateway base controller must expose an overridable Repair hook`。

- [ ] **Step 3: 给 GatewayViewController 增加可覆盖的 Repair hook**

增加页面级标记：

```swift
    private var isPresentingGatewayRecovery = false
```

把 Repair 空状态按钮回调改为：

```swift
                view.showEmptyDataView(
                    imageName: "device_state_offline",
                    title: "device_repair_message".localizedString,
                    backgroundColor: Background_Color,
                    buttonText: "repair".localizedString,
                    buttomWidth: SCRXFrom(216),
                    bottomMargin: SCRYFit(-78)
                ) { [weak self] in
                    self?.performGatewayRepair()
                }
```

把现有私有 `repair()` 替换为可覆盖 hook，方法体保持其他 Gateway 原行为：

```swift
    func performGatewayRepair() {
        repairDevices(nodes: [node], result: { [weak self] _, _ in
            guard let self else { return }
            if self.node.isKeybindComplete {
                self.updateData()
                NotificationCenter.default.post(
                    name: .init(siteGatewayDataChangedNotificaitonName),
                    object: self.gateway
                )
            }
        })
    }
```

- [ ] **Step 4: 让页面每次返回都重新渲染主状态**

在 `viewWillAppear` 中，设置可见状态后增加：

```swift
        isPresentingGatewayRecovery = false
        if isViewLoaded {
            updateData()
            tableView.reloadData()
            updateSaveBtnState()
        }
```

这保证 Repair 部分成功、失败或完整成功后，返回页都按最新 `isKeybindComplete` 与 Gateway diff 展示，而不是沿用进入 Sync 前的空状态或 header。

- [ ] **Step 5: 把 resync 改为带 trigger 且防重复导航**

替换为：

```swift
    func resync(trigger: SyncDevicesViewController.GatewayRecoveryTrigger) {
        guard !isPresentingGatewayRecovery,
              let navigationController else {
            return
        }
        isPresentingGatewayRecovery = true

        let vc = SyncDevicesViewController(
            type: .gatewayRecovery(
                node: node,
                gateway: gatewayModel,
                trigger: trigger
            ),
            reSync: !trigger.startsImmediately
        )
        vc.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            self.updateData()
            self.updateSaveBtnState()
            self.tableView.reloadData()
            NotificationCenter.default.post(
                name: .init(siteGatewayDataChangedNotificaitonName),
                object: self.gateway
            )
        }
        navigationController.pushViewController(vc, animated: true)
    }
```

把 Name header 的 `Devices not synced` 点击改为：

```swift
                prepareForGatewayRecovery { [weak self] in
                    self?.resync(trigger: .devicesNotSynced)
                }
```

- [ ] **Step 6: WiFi Gateway Repair 隐藏 SAVE 并进入完整 Recovery**

把两个 bottom hooks 改为：

```swift
    override func showConfiguredBottomActions() {
        bottomView.isHidden = false
        bottomView.showSaveOnlyUI()
    }

    override func showRepairBottomActions() {
        bottomView.isHidden = true
    }
```

增加 WiFi 专用 Repair：

```swift
    override func performGatewayRepair() {
        prepareForGatewayRecovery { [weak self] in
            self?.resync(trigger: .repair)
        }
    }
```

该 override 不调用 `repairDevices`，因此不再创建 Window 级 `Repairing…` HUD；其他 Gateway 仍走父类原实现。

- [ ] **Step 7: Repair 状态禁止自动 WiFi 请求**

在 `gatewayOnlineStateDidUpdate` 的 Online 分支增加：

```swift
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
```

在 `loadNetworkConnectivityFromGateway()` 开头增加同样的 Key Bind guard：

```swift
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
```

在 `viewWillAppear` 的 WiFi 状态恢复逻辑改为：

```swift
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        if networkConnectState == .connected {
            startWiFiRSSIStatusRefresh()
        } else if node.state,
                  !isNetworkOperationInProgress,
                  !isWiFiRequestInProgress,
                  !isNetworkConnectivityVisible {
            loadNetworkConnectivityFromGateway()
        }
```

在 `startWiFiRSSIStatusRefresh()` 和 `refreshWiFiRSSIStatus()` 的开头增加：

```swift
        guard node.isKeybindComplete else {
            stopWiFiRSSIStatusRefresh()
            return
        }
```

确保 Repair 状态不会由页面出现、Proxy Online 或 Timer 触发 Credentials/Status/RSSI GET；已有自动请求仍由 `prepareForGatewayRecovery` 等待，不主动取消。

- [ ] **Step 8: 运行 Repair、WiFi 与页面静态回归**

Run:

```bash
scripts/check_wifi_gateway_repair_recovery.sh
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_disconnect_clear_credentials.sh
scripts/check_wifi_gateway_sig_mesh_status_header.sh
scripts/check_wifi_gateway_wifi_status_header.sh
scripts/check_wifi_gateway_apn_removed.sh
scripts/check_wifi_gateway_info_rows_hidden.sh
scripts/check_wifi_gateway_menu_icons.sh
```

Expected: 全部 PASS。

- [ ] **Step 9: 审计 Repair 不再从 WiFi 页面调用通用 HUD 流程**

Run:

```bash
rg -n "repairDevices|showCustomHUD.*repairing|Repairing" SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
```

Expected: 无输出，exit 1。

Run:

```bash
rg -n "repairDevices\(nodes: \[node\]" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
```

Expected: 父类 `performGatewayRepair()` 保留一个命中，证明其他 Gateway 行为未被删除。

- [ ] **Step 10: 检查差异并提交**

Run:

```bash
git diff --check
git status --short
```

Expected: 只包含 Gateway/WiFi 页面和契约脚本改动，无无关格式化。

Commit:

```bash
git add scripts/check_wifi_gateway_repair_recovery.sh SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "fix: recover WiFi gateway through Repair flow"
```

---

### Task 4: 全量回归、四品牌构建和实施总结

**Files:**
- Create: `docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md`
- Verify: `SunSmart.xcworkspace`
- Verify: all files changed by Tasks 1-3

**Interfaces:**
- Consumes: Tasks 1-3 的完整实现。
- Produces: 静态检查与四品牌 iPhoneOS 构建证据；明确区分“构建通过”和“真机现场已验证”。

- [ ] **Step 1: 运行所有聚焦 WiFi Gateway 脚本**

Run:

```bash
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

Expected: 每个脚本输出 PASS。

- [ ] **Step 2: 运行 forced builder 与凭据排除审计**

Run:

```bash
rg -n "func getForcedGateway|func getGatewayRepair" SunSmart/Common/Data/Node+MessageHandles.swift
```

Expected: 同时列出 forced Gateway、Repair Composition 和 Repair Initialization builders。

Run:

```bash
rg -n "wifiGatewayCredentials|wifiGatewayCredentialsSet|wifiGatewayCredentialsClear|ssid|password" SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: Gateway Recovery/Repair 新增范围没有 WiFi Credentials 写入；任何既有命中都必须逐条定位并确认不属于 Recovery builders/task graph。

- [ ] **Step 3: 运行本地化和 diff 检查**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
git diff --check 893df9a3..HEAD
git status --short
```

Expected: 两个 strings 文件 `OK`；diff check 无输出；工作区在创建总结前干净。

- [ ] **Step 4: 构建 SunSmart generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit 0。允许工程既有 warning，不允许新增 compile error。

- [ ] **Step 5: 构建 Archipelago generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit 0。

- [ ] **Step 6: 构建 SLG Sync Plus generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit 0。

- [ ] **Step 7: 构建 SylSmart generic iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，exit 0。

- [ ] **Step 8: 创建实施总结**

创建 `docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md`，必须包含以下完整结构。每项验证写入刚执行命令的输出结论和 exit code；如果未连接真机，必须保留“未执行”而不是写成通过：

```markdown
# WiFi Gateway Repair 完整恢复实施总结

## 结论

记录 Repair SAVE 显隐、两阶段初始化、完整 Gateway Recovery、最终 Verification 和 WiFi 请求门禁的实施状态。

## 实施内容

- Repair 页面状态与导航
- Composition 后动态强制初始化
- Gateway 业务恢复与最终成功语义
- WiFi 自动请求串行与生命周期
- 本地化与多 target 影响

## 静态验证

列出每个脚本、凭据排除审计、`plutil` 和 `git diff --check` 的命令结论与 exit code。

## iPhoneOS 构建

| Scheme | 结果 |
| --- | --- |
每个 Scheme 使用一行，结果只能写成以下两类之一：

- `通过（exit 0）`；
- `失败（exit code + 首个 compile error）`。

## 尚需真机验收

明确记录以下矩阵是否执行：

1. Provisioning 完成但 Composition 未完成时断电；
2. Composition 完成但 AppKey/Model Bind 未完成时断电；
3. Key Bind 完成但 Gateway append 未完成时断电；
4. Repair 页面 SAVE 隐藏；
5. Repair 只进入一次 Sync 页且可以退出；
6. Repair 成功后 `isKeybindComplete == true`；
7. Repair 成功后 Gateway diff 为空且不显示 `Devices not synced`；
8. Repair 失败、Offline、Retry 和返回页面状态；
9. WiFi Credentials 未被 Recovery 覆盖。
```

- [ ] **Step 9: 检查总结与最终差异**

Run:

```bash
rg -n "T[B]D|T[O]DO|待[补]充|实[际]结果" docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md
git diff --check
git status --short
```

Expected: 总结无占位符；diff check 无输出；status 只包含实施总结。

- [ ] **Step 10: 提交总结**

Commit:

```bash
git add docs/260710_1604_wifi_gateway_repair_recovery_implementation_summary.md
git commit -m "docs: summarize WiFi gateway Repair verification"
```

- [ ] **Step 11: 最终提交范围审计**

Run:

```bash
git status --short
git log --oneline 893df9a3..HEAD
git diff --stat 893df9a3..HEAD
git diff --check 893df9a3..HEAD
```

Expected:

- 工作区干净；
- 只有本计划对应的 Repair initialization、Recovery flow、Gateway/WiFi page 和 summary commits；
- 无 NordicSigMeshSDK、Fast Add、其他 Gateway 或无关模块改动；
- final diff check 无输出。

---

## 真机验收执行表

以下步骤需要 CID `0x0A78`、PID `0x2721` 实机。没有设备时只记录为未执行。

| 场景 | 操作 | 预期 |
| --- | --- | --- |
| Adding 刚出现但尚未留下 Node | 立即断电后返回 Site | 不应伪造可 Repair 的 Gateway；沿用现有添加失败结果 |
| Provisioning 完成、Composition 未完成 | 断电、重新上电、进入 Gateway | 展示 Repair；SAVE 隐藏；点击 REPAIR 进入一次 Sync 页 |
| Composition 未完成的 Repair | 执行 Repair | Initialize 先显示并取得 Composition，再执行 forced Key/Bind |
| AppKey/Model Bind 中断 | 执行 Repair | Initialize 成功后 `isKeybindComplete == true` |
| Gateway append 中断 | 执行 Repair | Associated Spaces、Project、Sync Spaces、Server 按任务图执行 |
| Repair 成功 | 返回 Gateway 页面 | 正常详情；不展示 `Devices not synced`；Network Connectivity 重新加载 |
| Initialize 失败 | 关闭网关或制造无响应 | Initialize Failed；后续任务 Skipped；不提示成功 |
| Associated Spaces 失败 | 让一个 Space Key 配置失败 | 其他独立 Gateway 任务继续；Verification Skipped；总体失败 |
| 最终差异未收敛 | 保留一个无法完成的 Gateway diff | Verify Configuration Failed；不调用成功回调 |
| 中途 Offline | Recovery 中断电 | 当前任务失败；未开始任务 Skipped；可退出 Sync 页 |
| Retry | 恢复供电后重试 | 使用新运行标识；旧回调不更新新任务 |
| WiFi 凭据 | Repair 前后对比 SSID/Password | Recovery 不读取后覆盖、不 SET、不 CLEAR Credentials |

## 执行方式

项目 `AGENTS.md` 已指定默认采用 `2. Inline Execution`。计划提交并自检后，直接使用 `superpowers:executing-plans` 在当前会话按 Task 1-4 执行，并在每个 commit 后运行相应检查；不使用 subagents。
