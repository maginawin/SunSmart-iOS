# WiFi Gateway 添加中断恢复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 在添加中断电后出现错误权限提示、无法恢复完整配置以及 WiFi 自动请求与同步消息并发的问题。

**Architecture:** 使用 Site 与 Gateway 的单一权限真值统一所有入口；为手动 `Devices not synced` 增加独立的 `gatewayRecovery` 同步类型，强制重新下发关键 Key、Model Bind 与 Gateway 配置；由 WiFi Gateway 页面在进入 Sync 前串行协调自动请求和用户主动网络操作。普通 Save、其他设备同步和 WiFi 凭据配置保持原行为。

**Tech Stack:** Swift 5、UIKit、NordicSigMeshSDK、Bluetooth Mesh Config/Vendor Messages、Xcode workspace、iPhoneOS `xcodebuild`

## Global Constraints

- 当前年份按 2026 年处理。
- 仅处理 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 手动恢复路径。
- Visitor 不展示入口且不能进入；只有 Site Owner 或拥有有效 Editor Space 权限的用户可进入和配置。
- 已关联网关要求用户至少能有效编辑一个 Associated Space；未关联网关允许拥有任一有效 Editor Space 的用户接管配置。
- 有效 Editor 必须同时满足 `SpaceData.canEditing` 和 `SpaceData.deviceOperates.contains(.edit)`。
- 手动 `Devices not synced` 使用强制完整恢复；普通 Save 继续使用差异同步。
- 不读取设备真实 Key/Bind 后再做差异修复。
- 不下发、不保存、不覆盖 WiFi SSID 或 Password，不新增 Auth 信息。
- 同一 Gateway 同一时间只允许一个 acknowledged Mesh 请求。
- Lower Transport ACK 不能作为业务成功；必须收到对应 Config Status 或 Vendor Status。
- 用户主动执行 `Connect`、`Disconnect` 或 `Refresh` 时阻止进入 Sync；自动读取时等待完成后继续。
- 所有新增用户文案同时提供 English 和简体中文本地化，禁止硬编码。
- 不新增 App XCTest target；验证采用源码检查、iPhoneOS 构建和实机矩阵。
- 不修改 `NordicSigMeshSDK`；使用 App 已可访问的 Config/Vendor 消息类型。
- 不调整 Fast Add 成功语义，不重构通用 Mesh 框架。
- 用户确认计划后，按项目偏好使用 `superpowers:executing-plans` Inline Execution，不使用 subagents。

---

## 文件结构与职责

- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift`：Gateway 单一权限真值。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：Site Gateway 列表、卡片和入口。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`：详情权限、恢复入口和子类同步前置 hook。
- `SunSmart/Common/Data/Node+MessageHandles.swift`：强制初始化与 Associated Space 消息。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`：recovery ActionType 和 Skipped 标记。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`：专用恢复任务图、依赖和离线终止。
- `SunSmart/Main/Space/View/SyncDevicesProgressView.swift`：任务详情中的 `Skipped`。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`：WiFi acknowledged 请求串行与同步前等待。
- `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings`：新增文案。

本次不新建 Swift 源文件，避免额外 target membership 变更。

---

### Task 1: 统一 WiFi Gateway 权限真值

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift:264`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:253-263`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2221-2248`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2351`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:49-61`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:483-492`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:903-920`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:993-1005`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1211-1229`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1268-1283`

**Interfaces:**
- Consumes: `SiteData.permission`、`SiteData.spaces`、`SpaceData.canEditing`、`SpaceData.deviceOperates`、`GatewayModel.associatedSpaces`。
- Produces: `SiteData.canConfigureGateway(_:) -> Bool`、`GatewayViewController.canConfigureCurrentGateway: Bool`。

- [ ] **Step 1: 记录修复前失败基线**

Run:

```bash
rg -n "associatedSpaces.contains\(where: \{ \$0.permission == \.editor \}\)|site.deviceOperates.contains\(\.edit\)" SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
```

Expected: `Devices not synced` 强制要求 Associated Space Editor，且 Site 列表、入口、Save 使用不同条件。

- [ ] **Step 2: 增加单一权限方法**

在 `GatewayModel.swift` 增加：

```swift
extension SiteData {
    func canConfigureGateway(_ gateway: GatewayModel) -> Bool {
        if permission == .owner {
            return true
        }

        let effectiveEditableSpaceIDs = Set(
            spaces
                .filter { $0.canEditing && $0.deviceOperates.contains(.edit) }
                .map(\.id)
        )
        guard !effectiveEditableSpaceIDs.isEmpty else {
            return false
        }
        if gateway.associatedSpaces.isEmpty {
            return true
        }
        return gateway.associatedSpaces.contains {
            effectiveEditableSpaceIDs.contains($0.spaceId)
        }
    }
}
```

不得使用 `GatewaySpaceData.permission` 作为最终真值；它可能是云端快照，必须用当前 `SpaceData` 重新计算。

- [ ] **Step 3: 统一 Site 列表、卡片与入口**

`setupData()` 使用：

```swift
self.showGatewayModels = self.gatewayModels.filter {
    self.site.canConfigureGateway($0)
}
```

卡片状态使用：

```swift
let permissionState: GatewayPermissionState = site.canConfigureGateway(gateway.model)
    ? .normal
    : .noPermission
```

入口使用：

```swift
guard site.canConfigureGateway(gateway.model) else {
    XWHUDManager.showTipHUD("gateway_no_authority".localizedString, isLineFeed: true)
    return
}
```

- [ ] **Step 4: 统一 Gateway 详情防御性权限**

在 `GatewayViewController` 增加：

```swift
var canConfigureCurrentGateway: Bool {
    site.canConfigureGateway(setGatewayModel)
}
```

failable initializer 增加：

```swift
guard site.canConfigureGateway(gateway.model) else {
    return nil
}
```

将 Save、Name、Activate、Associated Spaces Add/Remove、APN、Server Authorization、Delete、`Devices not synced` 的旧权限条件替换为 `canConfigureCurrentGateway`。Save 最终检查正在编辑的 `setGatewayModel`：

```swift
guard site.canConfigureGateway(setGatewayModel) else {
    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    return
}
```

- [ ] **Step 5: 做权限源码审计**

Run:

```bash
rg -n "associatedSpaces.contains\(where: \{ \$0.permission == \.editor \}\)|site.deviceOperates.contains\(\.edit\)" SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
```

Expected: Gateway 展示、进入、修改与同步不再使用旧权限分支；剩余命中逐项确认与 Gateway 配置无关。

- [ ] **Step 6: 编译并提交**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

```bash
git add SunSmart/Main/Device/Gateway/Model/GatewayModel.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "fix: unify WiFi gateway access permissions"
```

---

### Task 2: 构建不依赖缓存的强制恢复消息

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift:1-180`

**Interfaces:**
- Consumes: 当前/主 NetworkKey 与 ApplicationKey、`Node.requiredFunctionTypes`、`supportModels`、`subnetAppkeyBindModels`。
- Produces: `Node.getForcedGatewayInitializationMessageHandles()`、`Node.getForcedGatewayAssociatedSpaceMessageHandles(networkKey:applicationKey:activate:)`。

- [ ] **Step 1: 记录缓存裁剪失败基线**

Run:

```bash
rg -n "if !appKeys.contains|if !networkKeys.contains|if !applicationKeys.contains|if !.*bind.contains" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift SunSmart/Common/Data/Node+MessageHandles.swift
```

Expected: 普通 initialize/config/Associated Space 构建器会按本地 Key/Bind 缓存跳过消息。

- [ ] **Step 2: 增加强制初始化消息构建器**

```swift
extension Node {
    func getForcedGatewayInitializationMessageHandles() -> [MeshMessageHandle] {
        let manager = MeshNetworkManager.instance
        let currentNetworkKey = manager.currentNetworkKey
        let currentApplicationKey = manager.currentApplicationKey
        let mainNetworkKey = manager.mainNetworkKey
        let mainApplicationKey = manager.mainApplicationKey
        var handles: [MeshMessageHandle] = []

        func append(_ message: ConfigMessage) {
            let handle = MeshMessageHandle(message: message, address: primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }

        append(ConfigAppKeyAdd(applicationKey: currentApplicationKey))
        var bindingKeys = [currentApplicationKey]
        if requiredFunctionTypes.contains(.mainNetwork),
           mainNetworkKey.index != currentNetworkKey.index {
            append(ConfigNetKeyAdd(networkKey: mainNetworkKey))
            append(ConfigAppKeyAdd(applicationKey: mainApplicationKey))
            bindingKeys.insert(mainApplicationKey, at: 0)
        }

        for model in supportModels {
            for applicationKey in bindingKeys {
                guard let message = ConfigModelAppBind(applicationKey: applicationKey, to: model) else {
                    continue
                }
                append(message)
            }
        }
        return handles
    }
}
```

`ConfigMessage` 是 SDK 已公开的共同协议；不要为该局部 helper 修改 SDK。

- [ ] **Step 3: 增加强制 Associated Space 构建器**

```swift
extension Node {
    func getForcedGatewayAssociatedSpaceMessageHandles(
        networkKey: NetworkKey,
        applicationKey: ApplicationKey,
        activate: Bool
    ) -> [MeshMessageHandle] {
        var handles: [MeshMessageHandle] = []

        let netKey = MeshMessageHandle(
            message: ConfigNetKeyAdd(networkKey: networkKey),
            address: primaryUnicastAddress
        )
        netKey.continuous = false
        handles.append(netKey)

        let appKey = MeshMessageHandle(
            message: ConfigAppKeyAdd(applicationKey: applicationKey),
            address: primaryUnicastAddress
        )
        appKey.continuous = false
        handles.append(appKey)

        for model in subnetAppkeyBindModels {
            guard let message = ConfigModelAppBind(applicationKey: applicationKey, to: model) else {
                continue
            }
            let handle = MeshMessageHandle(message: message, address: primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }

        if activate, let vendorModel = sunricherVendorModel {
            let handle = MeshMessageHandle(
                message: SunricherVendorSet(
                    function: .gatewaySubnetAppkeyAdd(subnetAppkeyIndex: applicationKey.index)
                ),
                model: vendorModel
            )
            handle.continuous = false
            handles.append(handle)
        }
        return handles
    }
}
```

该方法不得调用 `node.knows(...)`、`model.isBoundTo(...)` 或普通 `NodeSyncData.gatewayAssociatedSpaces`。

- [ ] **Step 4: 检查边界、编译并提交**

Run:

```bash
rg -n "WiFiGatewayCredentials|wifiGatewayCredentials|networkSSID|networkPassword|node\.knows|isBoundTo" SunSmart/Common/Data/Node+MessageHandles.swift
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: forced builders 中无凭据写入和缓存裁剪；构建输出 `** BUILD SUCCEEDED **`。

```bash
git add SunSmart/Common/Data/Node+MessageHandles.swift
git commit -m "feat: add forced WiFi gateway recovery messages"
```

---

### Task 3: 增加专用 Gateway recovery 任务图

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:45-735`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:75`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:142-715`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1240-1650`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2585-2610`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:3324-3365`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:749-759`

**Interfaces:**
- Consumes: Task 2 的 forced builders、`GatewayModel` 完整目标配置、现有 Gateway Vendor ActionType。
- Produces: `SyncType.gatewayRecovery(node:gateway:)`、`ActionType.gatewayRecoveryInitialization`、`ActionType.gatewayRecoveryAssociatedSpace(...)`、固定顺序 task graph。

- [ ] **Step 1: 记录修复前差异同步失败基线**

Run:

```bash
rg -n "SyncDevicesViewController\(type: \.devices\(\[node\]\), reSync: true\)|node.getSyncData\(type: \.all\)" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: `Devices not synced` 仍进入 `.devices([node])`，最终受 `isKeybindComplete` 和本地缓存裁剪。

- [ ] **Step 2: 增加 recovery ActionType 与消息映射**

在 `ActionType` 增加：

```swift
case gatewayRecoveryInitialization
case gatewayRecoveryAssociatedSpace(
    networkKey: NetworkKey,
    applicationKey: ApplicationKey,
    activate: Bool
)
```

在 configuration `messageHandles` 分支增加：

```swift
case .gatewayRecoveryInitialization:
    messageHandles.append(contentsOf: node.getForcedGatewayInitializationMessageHandles())

case .gatewayRecoveryAssociatedSpace(let networkKey, let applicationKey, let activate):
    messageHandles.append(
        contentsOf: node.getForcedGatewayAssociatedSpaceMessageHandles(
            networkKey: networkKey,
            applicationKey: applicationKey,
            activate: activate
        )
    )
```

在 configuration `isSuccessful` 分支增加：

```swift
case .gatewayRecoveryInitialization:
    return true

case .gatewayRecoveryAssociatedSpace(let networkKey, let applicationKey, let activate):
    guard node.knows(networkKey: networkKey),
          node.knows(applicationKey: applicationKey),
          !node.subnetAppkeyBindModels.contains(where: { !$0.isBoundTo(applicationKey) }) else {
        return false
    }
    return !activate
        || (node.gatewayInfo?.subnetAppkeyIndexs.contains(applicationKey.index) ?? false)
```

Initialization 返回 true 只是不使用旧缓存做二次判断；最终结果仍由 non-empty handles 和每个 handle 的业务 Status 决定。

- [ ] **Step 3: 增加专用 SyncType 并替换手动恢复入口**

在 `SyncType` 增加：

```swift
case gatewayRecovery(node: Node, gateway: GatewayModel)
```

`GatewayViewController.resync()` 使用：

```swift
private func resync() {
    let vc = SyncDevicesViewController(
        type: .gatewayRecovery(node: node, gateway: gatewayModel),
        reSync: true
    )
    vc.syncSuccessCallback = { [weak self] _ in
        guard let self else { return }
        self.updateSaveBtnState()
        self.tableView.reloadData()
        NotificationCenter.default.post(
            name: .init(siteGatewayDataChangedNotificaitonName),
            object: self.gateway
        )
    }
    navigationController?.pushViewController(vc, animated: true)
}
```

普通 Save 继续使用 `.devices([node])`。

- [ ] **Step 4: 构建固定 recovery device model**

在 `SyncDevicesViewController` 增加以下完整构建器：

```swift
private func makeGatewayRecoveryDeviceModel(
    node: Node,
    gateway: GatewayModel
) -> SyncDevicesModel? {
    guard let meshNetwork = MeshNetworkManager.instance.meshNetwork else {
        return nil
    }

    let initializeTask = SyncDeviceStepTaskModel(
        name: "initialize".localizedString,
        operationType: .configuration(node: node, type: .gatewayRecoveryInitialization)
    )
    let initializeStep = SyncDeviceStepModel(
        type: "initialize".localizedString,
        state: .none,
        tasks: [initializeTask]
    )
    initializeTask.parentStepModel = initializeStep
    var steps = [initializeStep]

    let associatedTargets = gateway.associatedSpaces.compactMap { space
        -> (GatewaySpaceData, NetworkKey, ApplicationKey)? in
        guard let networkKey = meshNetwork.networkKeys.first(where: {
            $0.index == space.appKeyIndex
        }), let applicationKey = meshNetwork.applicationKeys.first(where: {
            $0.index == space.appKeyIndex
                && $0.boundNetworkKey.index == networkKey.index
        }) else {
            return nil
        }
        return (space, networkKey, applicationKey)
    }
    guard associatedTargets.count == gateway.associatedSpaces.count else {
        return nil
    }

    if !associatedTargets.isEmpty {
        let tasks = associatedTargets.map { space, networkKey, applicationKey in
            SyncDeviceStepTaskModel(
                name: space.spaceName,
                operationType: .configuration(
                    node: node,
                    type: .gatewayRecoveryAssociatedSpace(
                        networkKey: networkKey,
                        applicationKey: applicationKey,
                        activate: gateway.activate
                    )
                )
            )
        }
        let step = SyncDeviceStepModel(
            type: "associated_spaces".localizedString,
            state: .none,
            tasks: tasks
        )
        tasks.forEach { $0.parentStepModel = step }
        steps.append(step)
    }

    let projectTask = SyncDeviceStepTaskModel(
        name: "association_project".localizedString,
        operationType: .configuration(
            node: node,
            type: .gatewayAssociationProjectId(projectId: gateway.siteId)
        )
    )
    let projectStep = SyncDeviceStepModel(
        type: "association_project".localizedString,
        state: .none,
        tasks: [projectTask]
    )
    projectTask.parentStepModel = projectStep
    steps.append(projectStep)

    let targetAppKeyIndexes = gateway.activate
        ? Array(Set(gateway.associatedSpaces.map(\.appKeyIndex))).sorted()
        : []
    let spacesTask = SyncDeviceStepTaskModel(
        name: "gateway_sync_spaces".localizedString,
        operationType: .configuration(
            node: node,
            type: .gatewaySubnetAppkeyIndexs(appkeyIndexs: targetAppKeyIndexes)
        )
    )
    let spacesStep = SyncDeviceStepModel(
        type: "gateway_sync_spaces".localizedString,
        state: .none,
        tasks: [spacesTask]
    )
    spacesTask.parentStepModel = spacesStep
    steps.append(spacesStep)

    if let mqttServerInfo = gateway.mqttServerInfo {
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
        steps.append(serverStep)
    }

    steps.dropFirst().forEach { $0.relevanceStepModels = [initializeStep] }

    let device = SyncDevicesModel(
        name: node.name ?? gateway.name,
        address: node.primaryUnicastAddress
    )
    device.imageName = node.iconName
    device.steps = steps
    steps.forEach { $0.parentDeviceModel = device }
    return device
}
```

Project、Sync Spaces、Server 只依赖 Initialize，不能依赖 Associated Spaces。

- [ ] **Step 5: 在 setupDataSource 接入 recovery 类型**

```swift
case .gatewayRecovery(let node, let gateway):
    guard let device = makeGatewayRecoveryDeviceModel(node: node, gateway: gateway) else {
        syncState = .syncFailure
        DispatchQueue.main.async {
            XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
        }
        break
    }
    configurationSection.devices.append(device)
```

顺序必须为 Initialize → Associated Spaces（如有）→ Association Project → Sync Spaces → Server Information（如有）。

- [ ] **Step 6: 强化 initialization 成功语义**

在 `isSyncOperationSuccessful(...)` 的通用分支前增加：

```swift
if let task = model as? SyncDeviceStepTaskModel,
   case .configuration(_, .gatewayRecoveryInitialization) = task.operationType {
    return !messageHandles.isEmpty && resultSuccessful
}
```

空 handles、timeout、cancelled、失败 Status 或只有 Transport ACK 均不能成功。

同时把 `successfulBack` 中“收到任意 `ConfigAppKeyStatus` 后追加 `node.getConfigMessageHandles()`”收紧为仅服务普通 `.deviceInitialize`：

```swift
private func isNormalDeviceInitialization(_ model: SyncCellModel) -> Bool {
    guard let task = model as? SyncDeviceStepTaskModel,
          case .configuration(_, .deviceInitialize) = task.operationType else {
        return false
    }
    return true
}
```

原 callback 条件改为：

```swift
if isNormalDeviceInitialization(model),
   (statusMessage is ConfigCompositionDataStatus
    || statusMessage is ConfigAppKeyStatus) {
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

Gateway recovery initialization 和 Associated Space 已包含自己的 forced binds，不能在 ConfigAppKeyStatus callback 中再启动一组普通 config handles，否则会重新引入并发。

- [ ] **Step 7: 静态检查、编译并提交**

Run:

```bash
rg -n "gatewayRecovery|gatewayRecoveryInitialization|getForcedGateway|wifiGatewayCredentials|networkPassword" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: recovery 使用 forced builders；普通 Save 保持 `.devices([node])`；无凭据写入；构建成功。

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "feat: add WiFi gateway recovery sync plan"
```

---

### Task 4: 实现关键失败、离线终止和 Skipped 状态

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:1248-1275`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1953-2340`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2670-2845`
- Modify: `SunSmart/Main/Space/View/SyncDevicesProgressView.swift:150-185`

**Interfaces:**
- Consumes: Task 3 的 recovery SyncType 和 initialize dependency。
- Produces: `SyncDeviceStepTaskModel.isSkipped`、`markSkipped()`、`resetSkippedState()`、Gateway recovery 中止语义。

- [ ] **Step 1: 记录 Waiting 残留失败基线**

Run:

```bash
rg -n "relevanceStepModels.contains\(where: \{ \$0.state == \.failed \}\)|case \.failed:" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/View/SyncDevicesProgressView.swift
```

Expected: 依赖失败后只跳过发送，任务仍为 Waiting，没有 `Skipped` 终态。

- [ ] **Step 2: 为 task model 增加聚焦的 skipped 标记**

不要扩展全局 `SyncDevicesState`。在 `SyncDeviceStepTaskModel` 增加：

```swift
private(set) var isSkipped = false

func markSkipped() {
    isSkipped = true
    state = .failed
    isFineshed = true
}

func resetSkippedState() {
    isSkipped = false
}
```

内部沿用 `.failed`，让父级聚合保持失败；用户可见状态由 `isSkipped` 区分。

- [ ] **Step 3: 终止 Gateway recovery 并标记剩余任务**

```swift
private var gatewayRecoveryNode: Node? {
    guard case .gatewayRecovery(let node, _) = type else { return nil }
    return node
}

private func markPendingGatewayRecoveryTasksSkipped() {
    guard gatewayRecoveryNode != nil else { return }
    sections
        .flatMap(\.allModels)
        .compactMap { $0 as? SyncDeviceStepTaskModel }
        .filter { $0.state == .none || $0.state == .wait }
        .forEach { $0.markSkipped() }
}
```

在 sync while loop 每次开始下一任务前增加：

```swift
if let recoveryNode = gatewayRecoveryNode, !recoveryNode.state {
    markPendingGatewayRecoveryTasksSkipped()
    syncState = .syncFailure
    break
}
```

while loop 结束、计算最终状态前再次调用 `markPendingGatewayRecoveryTasksSkipped()`，处理 Initialize 失败后被 dependency 阻止的任务。Bluetooth guard 改为：

```swift
guard MeshLibManager.manager.isOpenBluetooth else {
    if gatewayRecoveryNode != nil {
        markPendingGatewayRecoveryTasksSkipped()
        syncState = .syncFailure
        DispatchQueue.main.async {
            self.updateSyncStateUI()
            self.tableView.reloadData()
        }
        return
    }

    sections.forEach { section in
        section.allModels.forEach {
            $0.state = .failed
            $0.isFineshed = true
        }
    }
    syncState = .syncFailure
    applyProfileSensorTargetStateIfNeeded()
    DispatchQueue.main.async {
        self.updateSyncStateUI()
        self.tableView.reloadData()
    }
    return
}
```

Gateway 在某个已发送任务中途离线时，该任务由现有 message result 进入 Failed；下一轮 loop 检测离线后把尚未发送任务设为 Skipped。不要为单条 message 新增 HUD；任务行展示明细，流程结束沿用 Sync 页面的一次汇总结果。

- [ ] **Step 4: 重试时清理 skipped 标记**

在 `prepareTaskForResync(_:)` 开头执行：

```swift
task.resetSkippedState()
task.isFineshed = false
task.failedCount = 0
task.state = .none
```

- [ ] **Step 5: 在任务详情展示 Skipped**

在 progress cell 每次刷新先执行：

```swift
failureLabel.text = "failure".localizedString
```

`.failed` 分支改为：

```swift
case .failed:
    stateImageView.image = UIImage(named: "sync_failed_small")
    failureLabel.isHidden = false
    failureLabel.text = taskModel.isSkipped
        ? "skipped".localizedString
        : "failure".localizedString
    resyncBtn.isHidden = taskModel.isSkipped || !taskModel.isFineshed
```

Skipped 不显示成功图标、不计入成功数、不触发 sync success callback。

- [ ] **Step 6: 编译并提交**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`，普通 Sync 与 Emergency Fire 的 state enum 未受影响。

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/View/SyncDevicesProgressView.swift
git commit -m "fix: mark blocked gateway recovery tasks skipped"
```

---

### Task 5: 串行化 WiFi 请求并协调进入 Sync

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:749-759`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1211-1225`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:15-62`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:240-350`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:376-490`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:614-845`

**Interfaces:**
- Consumes: Gateway 统一权限和 Task 3 的 `resync()`。
- Produces: `GatewayViewController.prepareForGatewayRecovery(_:)`、acknowledged request origin/token、pending recovery completion、页面 HUD 生命周期。

- [ ] **Step 1: 记录并发失败基线**

Run:

```bash
rg -n "loadNetworkConnectivityFromGateway|refreshWiFiRSSIStatus|sendWiFiGatewayGet|func resync|isNetworkOperationInProgress" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
```

Expected: 自动 GET、RSSI GET 与 Sync 没有共同 request gate，`Devices not synced` 只检查 Proxy `isConnecting`。

- [ ] **Step 2: 在父类增加同步前置 hook**

```swift
func prepareForGatewayRecovery(_ completion: @escaping () -> Void) {
    completion()
}
```

`Devices not synced` 点击使用：

```swift
guard canConfigureCurrentGateway else {
    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    return
}
prepareForGatewayRecovery { [weak self] in
    self?.resync()
}
```

非 WiFi Gateway 立即执行；WiFi 子类决定等待或阻止。

- [ ] **Step 3: 增加 acknowledged request token 与来源**

```swift
private enum AcknowledgedRequestOrigin: Equatable {
    case automatic
    case userInitiated
}

private struct ActiveAcknowledgedRequest {
    let identifier: Int
    let origin: AcknowledgedRequestOrigin
}

private var acknowledgedRequestIdentifier = 0
private var activeAcknowledgedRequest: ActiveAcknowledgedRequest?
private var pendingGatewayRecovery: (() -> Void)?
private var isPreparingGatewayRecovery = false

private func beginAcknowledgedRequest(
    origin: AcknowledgedRequestOrigin
) -> Int? {
    guard activeAcknowledgedRequest == nil else { return nil }
    acknowledgedRequestIdentifier += 1
    activeAcknowledgedRequest = ActiveAcknowledgedRequest(
        identifier: acknowledgedRequestIdentifier,
        origin: origin
    )
    return acknowledgedRequestIdentifier
}

private func finishAcknowledgedRequest(
    identifier: Int,
    completion: () -> Void
) {
    guard activeAcknowledgedRequest?.identifier == identifier else { return }
    activeAcknowledgedRequest = nil
    completion()
    continuePendingGatewayRecoveryIfPossible()
}
```

旧 identifier 不得清除新请求或触发 pending recovery。

- [ ] **Step 4: 让 GET/SET/CLEAR 统一经过 gate**

三个发送 helper 均新增 `origin` 参数并返回是否成功启动。GET 的完整形态：

```swift
@discardableResult
private func sendWiFiGatewayGet(
    _ function: VendorFunctionGet,
    origin: AcknowledgedRequestOrigin,
    timeout: TimeInterval = 10,
    completion: @escaping (SunricherVendorStatus?) -> Void
) -> Bool {
    guard let vendorModel = node.sunricherVendorModel else {
        completion(nil)
        return false
    }
    guard let identifier = beginAcknowledgedRequest(origin: origin) else {
        return false
    }

    MeshAPI.sendMessage(
        message: SunricherVendorGet(function: function),
        model: vendorModel,
        timeout: timeout
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self else { return }
            self.finishAcknowledgedRequest(identifier: identifier) {
                completion(response as? SunricherVendorStatus)
            }
        }
    }
    return true
}
```

SET 使用完整的同源 gate：

```swift
@discardableResult
private func sendWiFiGatewayCredentialsSet(
    _ credentials: WiFiGatewayCredentials,
    origin: AcknowledgedRequestOrigin,
    timeout: TimeInterval = 10,
    completion: @escaping (WiFiGatewayCredentialsSetResult?) -> Void
) -> Bool {
    guard let vendorModel = node.sunricherVendorModel else {
        completion(nil)
        return false
    }
    guard let identifier = beginAcknowledgedRequest(origin: origin) else {
        return false
    }

    MeshAPI.sendMessage(
        message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)),
        model: vendorModel,
        timeout: timeout
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self else { return }
            self.finishAcknowledgedRequest(identifier: identifier) {
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayCredentialsSet(let result) = status.status.parameters else {
                    completion(nil)
                    return
                }
                completion(result)
            }
        }
    }
    return true
}
```

CLEAR 使用：

```swift
@discardableResult
private func sendWiFiGatewayCredentialsClear(
    origin: AcknowledgedRequestOrigin,
    timeout: TimeInterval = 10,
    completion: @escaping (WiFiGatewayCredentialsClearResult?) -> Void
) -> Bool {
    guard let vendorModel = node.sunricherVendorModel else {
        completion(nil)
        return false
    }
    guard let identifier = beginAcknowledgedRequest(origin: origin) else {
        return false
    }

    MeshAPI.sendMessage(
        message: SunricherVendorSet(function: .wifiGatewayCredentialsClear),
        model: vendorModel,
        timeout: timeout
    ) { [weak self] response in
        DispatchQueue.main.async {
            guard let self else { return }
            self.finishAcknowledgedRequest(identifier: identifier) {
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayCredentialsClear(let result) = status.status.parameters else {
                    completion(nil)
                    return
                }
                completion(result)
            }
        }
    }
    return true
}
```

调用来源固定为：

- 页面进入 credentials/status GET、RSSI GET：`.automatic`；
- 用户 Refresh credentials/status GET：`.userInitiated`；
- Connect SET/status polling：`.userInitiated`；
- Disconnect CLEAR：`.userInitiated`。

Timer 触发时 gate 被占用则跳过本次 tick，不启动第二个请求。

- [ ] **Step 5: 实现进入 Sync 的三种决策**

```swift
override func prepareForGatewayRecovery(
    _ completion: @escaping () -> Void
) {
    guard canConfigureCurrentGateway else {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
        return
    }

    let userOperationInProgress = isNetworkRefreshInProgress
        || isNetworkOperationInProgress
        || activeAcknowledgedRequest?.origin == .userInitiated
    guard !userOperationInProgress else {
        XWHUDManager.showTipHUD(
            "wifi_gateway_wait_current_operation".localizedString,
            isLineFeed: true
        )
        return
    }

    stopWiFiRSSIStatusRefresh()
    guard activeAcknowledgedRequest?.origin == .automatic else {
        completion()
        return
    }

    guard pendingGatewayRecovery == nil else { return }
    pendingGatewayRecovery = completion
    isPreparingGatewayRecovery = true
    pendingNetworkResultHUD = nil
    XWHUDManager.showCustomHUD(
        withMessage: "preparing_device_sync".localizedString,
        view: view
    )
}
```

用户主动操作中不保存 completion；自动请求中只保存一次。

- [ ] **Step 6: 自动请求结束后继续或离线终止**

```swift
private func continuePendingGatewayRecoveryIfPossible() {
    guard activeAcknowledgedRequest == nil,
          let completion = pendingGatewayRecovery else {
        return
    }

    pendingGatewayRecovery = nil
    isPreparingGatewayRecovery = false
    XWHUDManager.hideInView(with: view)

    guard node.state else {
        XWHUDManager.showTipHUD("device_offline".localizedString, isLineFeed: true)
        return
    }
    completion()
}
```

`showCredentialsFetchFailedIfVisible()` 和自动读取失败提示先执行：

```swift
guard !isPreparingGatewayRecovery else { return }
```

自动请求失败但 Node 仍 Online 时仍进入 recovery。

- [ ] **Step 7: 阻止网络操作与自动请求重叠**

在 Connect、Disconnect、Refresh 真正改变状态前检查 `activeAcknowledgedRequest == nil`；被自动请求占用时只提示 `wifi_gateway_wait_current_operation`，不改变 connect state，不启动 Timer。

`configureNetworkConnectivityCell(_:)` 的 `canSelectWiFi`、`canRefresh`、`canEditSSID`、`canEditPassword` 和 `connectActionCallback` 同时受 `canConfigureCurrentGateway` 约束，callback 内保留 guard。

- [ ] **Step 8: 清理生命周期**

```swift
private func cancelPendingGatewayRecovery() {
    pendingGatewayRecovery = nil
    isPreparingGatewayRecovery = false
    XWHUDManager.hideInView(with: view)
}
```

在 `viewWillDisappear` 中仅当 `isMovingFromParent`、`isBeingDismissed` 或 navigation controller 正在 dismiss 时调用；正常 push 到 Sync 前 completion 已清空。`deinit` 只把 `pendingGatewayRecovery` 置 nil 并停止 Timer，不再访问 `view`。不要取消已发送的 acknowledged 请求。

- [ ] **Step 9: 请求来源审计、编译并提交**

Run:

```bash
rg -n "sendWiFiGateway(Get|CredentialsSet|CredentialsClear)" SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 每个调用显式传入来源；没有绕过 gate 的 acknowledged WiFi 请求；构建成功。

```bash
git add SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "fix: serialize WiFi gateway pre-sync requests"
```

---

### Task 6: 增加国际化并核对共享 target

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings:1581-1595`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:1587-1601`

**Interfaces:**
- Consumes: Task 4 的 `skipped`，Task 5 的两个提示 Key。
- Produces: English 与简体中文文案。

- [ ] **Step 1: 验证 Key 尚不存在**

Run:

```bash
rg -n '"(preparing_device_sync|wifi_gateway_wait_current_operation|skipped)"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 修复前无匹配。

- [ ] **Step 2: 增加 English 文案**

```text
"preparing_device_sync" = "Preparing device sync…";
"wifi_gateway_wait_current_operation" = "Please wait for the current operation to finish.";
"skipped" = "Skipped";
```

- [ ] **Step 3: 增加简体中文文案**

```text
"preparing_device_sync" = "正在准备设备同步…";
"wifi_gateway_wait_current_operation" = "请等待当前操作完成。";
"skipped" = "已跳过";
```

- [ ] **Step 4: 检查 strings 与 target membership**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
rg -n '"(preparing_device_sync|wifi_gateway_wait_current_operation|skipped)"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
rg -n "GatewayViewController.swift|WiFiGatewayViewController.swift|SyncDevicesViewController.swift|Localizable.strings" SunSmart.xcodeproj/project.pbxproj
```

Expected: 两个 strings 文件均 `OK`；三个 Key 两种语言各出现一次；明确共享源文件/资源实际进入哪些品牌 target。

- [ ] **Step 5: Commit**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "chore: localize WiFi gateway recovery feedback"
```

---

### Task 7: 完整验证与实机场景验收

**Files:**
- Verify: `docs/260710_1206_wifi_gateway_interrupted_add_recovery_design.md`
- Verify: Tasks 1-6 修改的全部文件

**Interfaces:**
- Consumes: 完整实现。
- Produces: 构建、权限矩阵、并发行为和断电恢复证据。

- [ ] **Step 1: 最终静态边界检查**

Run:

```bash
git diff --check
rg -n "getForcedGateway|gatewayRecovery|prepareForGatewayRecovery|isSkipped" SunSmart
rg -n "WiFiGatewayCredentials|wifiGatewayCredentialsSet|networkPassword" SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: 无 whitespace 错误；核心路径可追踪；forced builder/task graph 不包含凭据写入。

- [ ] **Step 2: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 构建所有实际受影响品牌 scheme**

根据 Task 6 的 membership 证据逐个直接执行适用命令：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 每个实际受影响 scheme 均 `** BUILD SUCCEEDED **`。不得凭 scheme 名称跳过 membership 核对。

- [ ] **Step 4: 验收权限矩阵**

1. Owner + 无 Associated Spaces：入口可见，可进入，可点击 `Devices not synced`。
2. 有效 Editor + 无 Associated Spaces：可进入和配置。
3. 有效 Editor + 至少一个可编辑 Associated Space：可进入和配置。
4. Editor 只有无关 Space：已关联 Gateway 不展示，异常入口被拒绝。
5. Visitor：入口不展示，不能进入。
6. Editor 的 `disableEditorPermission`、`meshOTADistribution`、Space 待删除或待密码验证：按无有效 Editor 处理。

Expected: Site 列表、Gateway card、入口、详情修改和 `Devices not synced` 完全一致。

- [ ] **Step 5: 验收 WiFi 并发协调**

1. 自动 credentials/status GET 中点击：只显示一个 `Preparing device sync…`，无中间弹窗，结束后自动进入 Sync。
2. RSSI GET 中点击：停止新 Timer，等待当前 GET 后进入 Sync。
3. 自动 GET timeout 但 Gateway Online：仍进入 Sync。
4. 等待期间 Offline：关闭 HUD，不进入 Sync，只提示一次 `Device Offline`。
5. Connect、Disconnect、Refresh 中点击：提示等待，不排队、不自动跳转。
6. 连续点击：只创建一个 pending completion 和一个 Sync 页面。
7. 页面关闭后旧 callback 返回：不弹窗、不导航、不修改新状态。

Expected: Log 中同一 Gateway 不再并发发送两个 acknowledged WiFi/Sync Vendor 请求，不再出现本问题对应的 continuation misuse。

- [ ] **Step 6: 验收任务依赖与状态**

1. Initialize 第一个 Config 请求失败：Initialize Failed，后续 Skipped，后续 Vendor payload 不发送。
2. Associated Spaces 失败：Project、Sync Spaces、Server Information 继续，总体失败。
3. 只有 Transport ACK、没有 Vendor Status：timeout/failed，不更新成功缓存。
4. 同步中 Offline：当前任务失败，未开始任务 Skipped。
5. Re-sync：原 Skipped 恢复 Waiting。
6. 全部必要任务成功：重新计算差异为空，`Devices not synced` 消失。

- [ ] **Step 7: 验收 Adding 中断电场景**

1. 添加指定 WiFi Gateway。
2. Adding 数秒后断电，保留半完成 Node/GatewayModel。
3. 重新上电并等待 BLE Proxy Online。
4. 点击 `Devices not synced`，执行一次 Re-sync。
5. 确认顺序为 Initialize、Associated Spaces、Association Project、Sync Spaces、Server Information。
6. 确认适用任务全部成功，`Devices not synced` 消失。
7. 确认原 WiFi 连接未被覆盖。

Expected: 一次完整恢复修复半完成 Gateway，无需预读 Key/Bind。

- [ ] **Step 8: 最终工作区检查**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: 只有批准范围内变更和 Tasks 1-6 的聚焦提交，无临时文件、Auth 信息或无关格式化。

---

## 设计覆盖映射

| 设计要求 | 实施任务 |
| --- | --- |
| Owner / 有效 Editor / Visitor 权限矩阵 | Task 1、Task 7 Step 4 |
| 手动恢复无视本地 Key/Bind complete 缓存 | Task 2、Task 3 |
| Initialize → Associated Spaces → Project → Sync Spaces → Server | Task 3 |
| 不读状态后差异修复，不覆盖 WiFi 凭据 | Task 2、Task 3、Task 7 Step 1/7 |
| Initialize 失败停止，Associated Spaces 失败继续独立任务 | Task 3 dependencies、Task 4 |
| 仅业务 Status 成功后更新缓存 | Task 3 Step 6、现有 `handle.isSuccessful` 落盘路径、Task 7 Step 6 |
| 自动请求等待、用户主动操作阻止、HUD 去重 | Task 5、Task 7 Step 5 |
| 离线终止、Skipped、单次结果反馈 | Task 4、Task 5、Task 7 Step 6 |
| English / 简体中文 | Task 6 |
| 共享 target iPhoneOS 构建 | Task 6 Step 4、Task 7 Step 2/3 |

---

## 实施停止条件

遇到以下任一情况时停止当前 task，回到用户确认，不扩大范围：

- SDK 公开 API 无法构造强制 Config 消息，必须修改或发布 `NordicSigMeshSDK`；
- 实机对重复 `ConfigAppKeyAdd` 或 `ConfigModelAppBind` 返回不可幂等的设备特有错误；
- Associated Space AppKey index 无法从当前 Mesh Network 唯一解析；
- 共享 Sync 改动影响非 Gateway 流程；
- 需要新增 App test target、修改部署版本、依赖或 Auth；
- 任一品牌 target 因共享资源/代码出现新的编译错误。
