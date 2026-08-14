# Gateway Information Date Time 与 Time Zone 实现计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话内按任务执行并设置阶段性检查点。遵循项目约定，不使用 subagents。

**目标：** 为 4G/WiFi Gateway Information 页面增加 Gateway 实际 Date time 与 Time zone 读取、持久化和 Cloud Gateway 快照同步；在 Fast Add 中按 Site Offset 初始化 Gateway 时间，并停止 WiFi Gateway 页面连接成功后的隐式 TimeSet。

**架构：** Gateway Information 入口注入明确的 Site/Gateway/Node Context；独立 Coordinator 管理 direct Proxy 判定、TimeGet attempt、SDK 自动持久化回滚、格式化、本地保存和 `.syncGateway`。Fast Add 使用独立小型策略生成并验证一次性 TimeSet；WiFi 页面仅保留网络自动加载门闩。

**技术栈：** Swift、UIKit、NordicSigMeshSDK、SIG Mesh Time Model、现有 `CloudSynchronizationManager`、命令行 `swiftc` 聚焦测试、shell contract、`xcodebuild` generic iPhoneOS 构建。

## 全局约束

- `SiteData.timezone` 是 Site 全局真值，Information 与 Fast Add 结果不得修改 Site timezone、Site props pending、Site props API 或 Site timestamps。
- Information 只发送 `TimeGet`，不发送 `TimeSet`，也不主动连接、重连或断开 Gateway。
- Fast Add 对 4G/WiFi Gateway 各发送一次 Site Offset `TimeSet`；此后只有 Sync Gateways 可以再次写 Gateway 时间。
- Fast Add TimeSet 失败时 Gateway 仍添加成功；Node 保持 `timezone = nil`、`timestamp = 0`，Gateway payload 省略 `timezoneOffset/timestamp`，不写 `0/0` 哨兵。
- Date time 固定为 `yyyy-MM-dd HH:mm:ss`；Time zone 固定为 `UTC±HH:mm`。
- 所有新增用户文案同时支持 English 和简体中文；优先复用现有 Key。
- Time Model 使用其实际 Element，不硬编码 Primary Element。
- 修改共享源码或 Xcode 文件成员关系时，同步覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 不修改 NordicSigMeshSDK 源码；利用业务层发送前快照和回调后恢复，处理 SDK 在业务回调前自动保存 `TimeStatus` 的现状。
- 不做无关重构，不批量格式化，不新增 Auth 信息。
- 未获得明确授权前不执行 Git commit、push 或 merge。

---

### Task 1：建立 Gateway 时间读取的纯逻辑核心

**Files:**

- Create: `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`
- Create: `Tests/Device/GatewayTimeInformationCoordinatorTests.swift`

**Interfaces:**

- Produces: `GatewayTimeInformationSnapshot`
- Produces: `GatewayTimeInformationFormatter.makeSnapshot(seconds:offsetMinutes:)`
- Produces: `GatewayTimeInformationAttemptCore.begin()`、`receive(attemptID:seconds:offsetMinutes:)`、`fail(attemptID:)`、`detach()`
- Consumes: Foundation `Date`、`DateFormatter`、`TimeZone`

- [ ] **Step 1：写失败测试，固定格式和状态机行为**

测试文件至少包含以下断言：

```swift
private static func testFormatsGatewayTimeAndOffset() {
    let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
        seconds: 1,
        offsetMinutes: 480
    )
    require(snapshot != nil, "Known Gateway time must format")
    require(snapshot?.timeZoneText == "UTC+08:00", "Expected UTC+08:00")
    require(
        snapshot?.dateTimeText == "2000-01-01 08:00:01",
        "Mesh epoch conversion and Gateway offset must both be applied"
    )
}

private static func testRejectsUnknownTime() {
    require(
        GatewayTimeInformationFormatter.makeSnapshot(seconds: 0, offsetMinutes: 480) == nil,
        "seconds == 0 must remain unknown"
    )
}

private static func testAttemptDeduplicatesAndRestoresAfterDetach() {
    var core = GatewayTimeInformationAttemptCore()
    let attempt = core.begin()
    require(attempt != nil, "First read must start")
    require(core.begin() == nil, "Concurrent read must be ignored")
    core.detach()
    require(
        core.receive(attemptID: attempt!, seconds: 100, offsetMinutes: 480) == .restoreOnly,
        "A response after page exit must restore the pre-send Node state"
    )
}
```

同时覆盖 `UTC+00:00`、`UTC-05:30`、15 分钟 Offset、错误 attempt、timeout 后重试。

- [ ] **Step 2：运行测试并确认失败**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift Tests/Device/GatewayTimeInformationCoordinatorTests.swift -o /tmp/GatewayTimeInformationCoordinatorTests
```

Expected: FAIL，提示核心类型或方法尚未定义。

- [ ] **Step 3：实现最小纯逻辑核心**

在 runtime imports 之前定义：

```swift
struct GatewayTimeInformationSnapshot: Equatable {
    let seconds: UInt64
    let offsetMinutes: Int
    let dateTimeText: String
    let timeZoneText: String
}

enum GatewayTimeInformationDecision: Equatable {
    case success(GatewayTimeInformationSnapshot)
    case failure(showError: Bool)
    case restoreOnly
    case ignored
}

enum GatewayTimeInformationFormatter {
    static let meshEpochOffset: TimeInterval = 946_684_800

    static func makeSnapshot(
        seconds: UInt64,
        offsetMinutes: Int
    ) -> GatewayTimeInformationSnapshot? {
        guard seconds > 0,
              let timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let sign = offsetMinutes < 0 ? "-" : "+"
        let absoluteMinutes = abs(offsetMinutes)
        let timeZoneText = String(
            format: "UTC%@%02d:%02d",
            sign,
            absoluteMinutes / 60,
            absoluteMinutes % 60
        )
        let date = Date(
            timeIntervalSince1970: TimeInterval(seconds) + meshEpochOffset
        )
        return .init(
            seconds: seconds,
            offsetMinutes: offsetMinutes,
            dateTimeText: formatter.string(from: date),
            timeZoneText: timeZoneText
        )
    }
}
```

`GatewayTimeInformationAttemptCore` 只允许一个 active attempt；attached 状态收到有效 response 返回 `.success`，无效 response 返回 `.failure(showError: true)`，detach 后 response 返回 `.restoreOnly`，错误 attempt 返回 `.ignored`。

- [ ] **Step 4：运行聚焦测试并确认通过**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift Tests/Device/GatewayTimeInformationCoordinatorTests.swift -o /tmp/GatewayTimeInformationCoordinatorTests
/tmp/GatewayTimeInformationCoordinatorTests
```

Expected: 输出 `GatewayTimeInformationCoordinatorTests passed`。

- [ ] **Step 5：检查本任务变更**

Run: `git diff --check`

Expected: 无输出。

---

### Task 2：实现 Information runtime Coordinator 与 Gateway Cloud 同步

**Files:**

- Modify: `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Create: `Tests/Device/GatewayTimeInformationRuntimeContractTests.swift`

**Interfaces:**

- Consumes: Task 1 的 formatter/core
- Consumes: `GatewayCloudSyncGenerationPolicy.next(now:current:uploaded:)`
- Consumes: `CloudSynchronizationManager.shared.addSynchronizationHandle(operation:level:callback:)`
- Produces: `GatewayInformationContext(site:gateway:)`
- Produces: `GatewayTimeInformationCoordinator.init(context:)`
- Produces: `@discardableResult func read() -> Bool`、`func finishPage()`
- Produces callbacks: `var onReadState: ((GatewayTimeInformationReadState) -> Void)?`、`var onCloudFailure: (() -> Void)?`

- [ ] **Step 1：写 runtime contract 失败测试**

Contract 读取源码并断言：

```swift
require(source.contains("currentProxyReadyContext"), "Read must require Proxy Ready")
require(source.contains("currentProxy?.nodeAddress"), "Read must match the current direct Proxy")
require(source.contains("TimeGet()"), "Information must send TimeGet")
require(source.contains("node.timeModel"), "TimeGet must use the actual Time Server Model")
require(!source.contains("TimeSet("), "Information coordinator must never send TimeSet")
require(source.contains("GatewayCloudSyncGenerationPolicy.next"), "Gateway generation policy must be reused")
require(source.contains(".syncGateway(gateway: gateway, node: node)"), "Gateway Register must update Cloud gateway snapshot")
```

- [ ] **Step 2：运行 contract 并确认失败**

Run:

```bash
swiftc -parse-as-library Tests/Device/GatewayTimeInformationRuntimeContractTests.swift -o /tmp/GatewayTimeInformationRuntimeContractTests
/tmp/GatewayTimeInformationRuntimeContractTests SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift SunSmart.xcodeproj/project.pbxproj
```

Expected: FAIL，缺少 runtime Coordinator 或四 target membership。

- [ ] **Step 3：实现 Context、连接判定和 TimeGet**

在 `#if canImport(NordicSigMeshSDK)` 中实现：

```swift
struct GatewayInformationContext {
    let site: SiteData
    let gateway: Gateway

    var node: Node { gateway.node }
    var gatewayModel: GatewayModel { gateway.model }
}

enum GatewayTimeInformationReadState {
    case disconnected
    case reading
    case succeeded(GatewayTimeInformationSnapshot)
    case failed
}
```

`read()` 必须在主线程执行，并同时校验：

```swift
guard let ready = MeshLibManager.manager.currentProxyReadyContext,
      ready.nodeAddress == node.primaryUnicastAddress,
      MeshLibManager.manager.currentProxy?.nodeAddress == node.primaryUnicastAddress else {
    onReadState?(.disconnected)
    return
}
```

随后取得 `node.timeModel`，保存发送前 `timestamp/timezone`，开始 attempt，并使用：

```swift
MeshAPI.sendMessage(message: TimeGet(), model: model, timeout: 10) { response in
    // DispatchQueue.main，验证 attempt 与 typed TimeStatus。
}
```

Mesh response closure 必须在 attempt terminal 前强持有 Coordinator；`finishPage()` 只 detach UI，不提前释放发送前 Node 快照，确保页面退出后、timeout 前到达的响应仍可恢复 SDK 自动写入。

- [ ] **Step 4：实现 SDK 自动保存后的接受与恢复**

SDK 会先执行 `Node.updateNodeStatus(TimeStatus)`。Coordinator 回调必须：

- 有效 response：再次明确赋值 response seconds/offset，并检查 `savePropertys()` 返回 true；
- seconds 为零、错误类型、页面已退出或旧 attempt：恢复发送前 timestamp/timezone，并调用 `savePropertys()`；
- 有效值保存失败：恢复旧值并再次保存；不刷新 UI、不 enqueue Cloud；
- timeout：没有 response 时不改 Node；保留旧 UI 并提示一次失败。

- [ ] **Step 5：实现 Gateway generation 与 `.syncGateway`**

本地保存成功后：

```swift
gateway.lastUpdate = GatewayCloudSyncGenerationPolicy.next(
    now: Int64(Date().timeIntervalSince1970),
    current: gateway.lastUpdate,
    uploaded: gateway.lastUploadCloudTimestamp
)
gateway.syncCloudError = nil
guard gateway.save() else {
    onCloudFailure?()
    return
}
CloudSynchronizationManager.shared.addSynchronizationHandle(
    operation: .syncGateway(gateway: gateway, node: node),
    level: .promptly
) { [weak self] state in
    guard self?.isPageAttached == true else { return }
    if case .failure = state { self?.onCloudFailure?() }
    if case .cancel = state { self?.onCloudFailure?() }
}
```

Cloud 失败保留 UI 与 Node；Gateway 继续 dirty。不得读取或写入 `context.site.timezone`。

- [ ] **Step 6：将新文件加入四个 app target**

在 `project.pbxproj` 为 `GatewayTimeInformationCoordinator.swift` 增加一个 file reference、四个 PBXBuildFile，并分别加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart Sources phase。

- [ ] **Step 7：运行 Task 1 测试与 runtime contract**

Run Task 1 两条命令，再运行本任务 contract。

Expected: 两个 binary 均输出 passed。

---

### Task 3：接入 Gateway Information 页面、稳定行身份和本地化

**Files:**

- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `scripts/check_wifi_gateway_menu_icons.sh`
- Create: `Tests/Device/GatewayInformationTimeRowsContractTests.swift`
- Create: `scripts/check_gateway_information_time.sh`

**Interfaces:**

- Consumes: `GatewayInformationContext`、`GatewayTimeInformationCoordinator`
- Produces: private stable `DeviceInfoRow.ID`
- Produces localized keys: `gateway_date_time`、`gateway_not_connected`

- [ ] **Step 1：写页面 contract 失败测试**

Contract 必须检查：

- Gateway Information 入口传入 `GatewayInformationContext(site:gateway:)`；
- 普通设备 initializer 仍可不传 Context；
- `.dateTime`、`.timeZone` 位于 `.signalStrength` 后；
- MAC Copy 使用 `.mac` identity，不再使用 `indexPath.row == 1`；
- 两行点击调用同一 `requestGatewayTime()`；
- 页面退出调用 Coordinator `finishPage()`；
- English/中文 Key 同时存在。

- [ ] **Step 2：运行 contract 并确认失败**

Run:

```bash
swiftc -parse-as-library Tests/Device/GatewayInformationTimeRowsContractTests.swift -o /tmp/GatewayInformationTimeRowsContractTests
/tmp/GatewayInformationTimeRowsContractTests SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: FAIL，Gateway Context 与新行尚未接入。

- [ ] **Step 3：将 Device 信息数组改为稳定 identity**

在 `DeviceInformationViewController` 内定义：

```swift
private struct DeviceInfoRow {
    enum ID {
        case name, mac, pid, address, versionIdentifier
        case model, deviceType, firmware, signalStrength
        case dateTime, timeZone
    }
    let id: ID
    let model: CustomCellModel
}
```

`deviceInfoModels` 改为 `[DeviceInfoRow]`；cell 渲染读取 `.model`；MAC Copy 和时间刷新均按 `.id` 分发。

- [ ] **Step 4：注入可选 Gateway Context**

Initializer 新增默认 nil 参数：

```swift
gatewayContext: GatewayInformationContext? = nil
```

`GatewayViewController` 的 Information action 传入当前 `site/gateway`。只有 Context 非 nil 时在 Signal strength 后追加 Date time 与 Time zone。

同步更新 `check_wifi_gateway_menu_icons.sh`：不再匹配旧的单行 initializer，改为同时断言 `showsGroupSection: false`、`showsSceneSection: false` 和 `gatewayContext: GatewayInformationContext(site: site, gateway: gateway)`。

- [ ] **Step 5：绑定页面状态与点击行为**

- 初始已连接读取中：两行均为 `--`；无 HUD；
- 初始未连接：Date time 为 `gateway_not_connected`，Time zone 为 `--`；
- success：使用同一 Snapshot 同时更新两行；
- failure：保留旧 Snapshot；首次失败保持 `--`，复用 `failed_to_retrieve_data` Toast；
- Cloud failure：复用 `site_entry_sync_failed_to_update_server` Toast；
- 点击任一新增行重新检查连接；读取中重复点击无效；
- 不订阅 Proxy Ready，后续才连接成功时等待用户点击；
- `viewDidDisappear` 仅在页面真正离开 navigation stack 时调用 `finishPage()`，避免临时覆盖页面误取消。

- [ ] **Step 6：新增/复用本地化**

新增：

```text
"gateway_date_time" = "Date time";
"gateway_not_connected" = "Gateway not connected";
```

中文：

```text
"gateway_date_time" = "日期时间";
"gateway_not_connected" = "网关未连接";
```

Time zone 复用 `site_time_zone_row_title`；失败 Toast 复用已确认 Key。

- [ ] **Step 7：实现并运行聚焦检查脚本**

`scripts/check_gateway_information_time.sh` 依次编译/运行 Task 1、Task 2、Task 3 tests，并执行：

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 三个 test binary passed，两个 strings 文件均输出 `OK`。

---

### Task 4：在 4G/WiFi Gateway Fast Add 中增加一次 Site Offset TimeSet

**Files:**

- Create: `SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift`
- Create: `Tests/Site/GatewayFastAddTimeInitializationTests.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_gateway_information_time.sh`

**Interfaces:**

- Produces: `GatewayFastAddTimeInitializationPolicy.accepts(seconds:offsetMinutes:targetOffsetMinutes:)`
- Produces: `GatewayFastAddTimeInitialization.make(node:siteTimeZone:) -> GatewayFastAddTimeInitialization?`
- Produces: `GatewayFastAddTimeInitialization.acceptsCurrentNodeState(_:) -> Bool`
- Produces: `GatewayFastAddTimeInitialization.clearUninitializedTime(on:)`
- Consumes: `SiteTimeZoneValue.offsetMinutes`、`Node.setLocalTimeMessage(date:timeZone:)`

- [ ] **Step 1：写失败测试固定成功/失败判定**

```swift
require(
    GatewayFastAddTimeInitializationPolicy.accepts(
        seconds: 100,
        offsetMinutes: 480,
        targetOffsetMinutes: 480
    ),
    "Non-zero matching TimeStatus must succeed"
)
require(
    !GatewayFastAddTimeInitializationPolicy.accepts(
        seconds: 0,
        offsetMinutes: 480,
        targetOffsetMinutes: 480
    ),
    "Unknown time must fail"
)
require(
    !GatewayFastAddTimeInitializationPolicy.accepts(
        seconds: 100,
        offsetMinutes: 0,
        targetOffsetMinutes: 480
    ),
    "Wrong offset must fail"
)
```

- [ ] **Step 2：运行测试并确认失败**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift Tests/Site/GatewayFastAddTimeInitializationTests.swift -o /tmp/GatewayFastAddTimeInitializationTests
```

Expected: FAIL，策略尚未定义。

- [ ] **Step 3：实现纯策略和 runtime helper**

核心判定必须是：

```swift
seconds > 0 && offsetMinutes == targetOffsetMinutes
```

runtime helper 使用 Site fixed Offset 和发送时 `Date()`：

```swift
guard let model = node.timeSetupModel,
      let fixedTimeZone = TimeZone(
        secondsFromGMT: siteTimeZone.offsetMinutes * 60
      ) else {
    return nil
}
let message = Node.setLocalTimeMessage(
    date: Date(),
    timeZone: fixedTimeZone
)
return GatewayFastAddTimeInitialization(
    handle: MeshMessageHandle(message: message, model: model),
    targetOffsetMinutes: siteTimeZone.offsetMinutes
)
```

runtime value 持有 `handle: MeshMessageHandle` 与 `targetOffsetMinutes: Int`；`acceptsCurrentNodeState(_:)` 将 Node timestamp 和 timezone Offset 转交给纯策略。`clearUninitializedTime(on:)` 设置 timezone nil、timestamp 0 并保存。

不得使用 `TimeZone.current`，不得手动给 Date 增减 Offset。

- [ ] **Step 4：接入 Gateway Fast Add append queue**

在 `device.deviceType == .gateway` 分支中：

1. 保留 Gateway Authorization 与全部 `getNodeSyncGatewayData`；
2. 保留 Attention；
3. 最后追加 TimeSet handle；
4. 记录该 Node Address 的目标 Offset，供 success callback 校验；
5. `appendMessageSuccessBack` 遇到 TimeSet 时读取 SDK 已更新的 Node timestamp/timezone；不符合策略则清空；
6. 新增 `appendMessageFailedBack`，TimeSet 失败时清空；
7. 清空实现必须设置 `node.timezone = nil`、`node.timestamp = 0` 并调用 `savePropertys()`；
8. 不调用 addFail，不回滚 Provision/Key Bind。

- [ ] **Step 5：固定 Cloud 省略字段契约**

在 contract 中断言 `ExportData.swift` 仍然只在 `timezone != nil` 时添加 `timezoneOffset` 和 `timestamp`。禁止为失败 Gateway 注入 `0/0`。

- [ ] **Step 6：将 helper 加入四 target 并运行测试**

更新 `project.pbxproj` 的 file reference 和四个 Sources phase。运行 helper tests 与 `scripts/check_gateway_information_time.sh`。

Expected: 所有检查通过。

---

### Task 5：停止 WiFi Proxy Ready 自动 TimeSet，同时保留自动加载门闩

**Files:**

- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayAutomaticLoadGate.swift`
- Create: `Tests/Device/WiFiGatewayAutomaticLoadGateTests.swift`
- Create: `scripts/check_wifi_gateway_proxy_ready_no_time_set.sh`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Delete: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift`
- Delete: `Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift`
- Delete: `scripts/check_wifi_gateway_proxy_ready_time_set.sh`

**Interfaces:**

- Preserves: `WiFiGatewayAutomaticLoadGate.request(forceReload:)`、`markReady(sessionID:)`、`takeIfReady(currentSessionID:)`、`invalidate()`
- Removes: `WiFiGatewayTimeSyncSessionGate`、`WiFiGatewayTimeSyncCoordinator`、`activeTimeSyncContext`

- [ ] **Step 1：先迁移 automatic-load gate 测试并确认可独立运行**

新测试保留三项行为：当前 Ready session 才能 drain、reload 覆盖 resume、invalidate 关闭 barrier。删除所有 TimeSet/session sync 测试。

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/WiFiGatewayAutomaticLoadGate.swift Tests/Device/WiFiGatewayAutomaticLoadGateTests.swift -o /tmp/WiFiGatewayAutomaticLoadGateTests
/tmp/WiFiGatewayAutomaticLoadGateTests
```

Expected: 输出 `WiFiGatewayAutomaticLoadGateTests passed`。

- [ ] **Step 2：改写 Proxy Ready hook**

`gatewayProxyDidBecomeReady` 只执行：

```swift
override func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext) {
    stopWiFiRSSIStatusRefresh()
    guard MeshLibManager.manager.currentProxyReadyContext == context else { return }
    automaticLoadGate.markReady(sessionID: context.sessionID)
    drainAutomaticLoadIfPossible()
}
```

移除 `activeTimeSyncContext` 及断开时对它的清理；保留 `automaticLoadGate.invalidate()`。

- [ ] **Step 3：删除旧 TimeSet Coordinator 并更新 target membership**

从 `project.pbxproj` 删除旧 file reference 和四个 PBXBuildFile；为 `WiFiGatewayAutomaticLoadGate.swift` 添加对应的一个 file reference 与四个 Sources membership。

- [ ] **Step 4：新增反向 contract**

`check_wifi_gateway_proxy_ready_no_time_set.sh` 必须断言：

- WiFi controller 的 Proxy Ready hook 包含 `markReady` 和 `drainAutomaticLoadIfPossible`；
- WiFi controller 不包含 `WiFiGatewayTimeSyncCoordinator`；
- 新 gate 文件不包含 `TimeSet`、`TimeStatus`、`TimeZone.current`；
- 旧 coordinator 文件和旧 test/script 已不存在；
- 新 gate 文件存在四个 target Sources membership。

- [ ] **Step 5：运行 gate tests 和 contract**

Expected: test binary 和脚本均输出 passed。

---

### Task 6：补齐组合回归与工程级静态检查

**Files:**

- Modify: `scripts/check_gateway_information_time.sh`
- Review: `scripts/check_wifi_gateway_info_rows_hidden.sh`
- Review: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Review: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes all prior task outputs
- Produces one repeatable focused validation entrypoint

- [ ] **Step 1：扩展聚焦脚本覆盖全部新测试**

脚本按顺序运行：

1. GatewayTimeInformationCoordinatorTests；
2. GatewayTimeInformationRuntimeContractTests；
3. GatewayInformationTimeRowsContractTests；
4. GatewayFastAddTimeInitializationTests；
5. WiFiGatewayAutomaticLoadGateTests；
6. WiFi no-TimeSet contract；
7. English/中文 `plutil -lint`。

- [ ] **Step 2：运行既有时间和 Gateway 回归**

Run:

```bash
scripts/check_site_sync_gateways.sh
scripts/check_gateway_information_time.sh
scripts/check_wifi_gateway_proxy_ready_no_time_set.sh
scripts/check_wifi_gateway_info_rows_hidden.sh
scripts/check_wifi_gateway_menu_icons.sh
scripts/check_device_information_menu_transition.sh
scripts/check_wifi_gateway_server_information_recovery.sh
```

Expected: 所有脚本输出 PASS/passed；既有 Sync Gateways 行为未回归。

- [ ] **Step 3：检查禁止边界**

Run:

```bash
rg -n "SiteData\.timezone|SitePropsAPIClient|syncSite" SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift
```

Expected: 无业务写入命中；若类型声明或注释命中，人工确认不存在赋值/API 调用。

- [ ] **Step 4：检查工程成员关系与 whitespace**

Run:

```bash
git diff --check
git status --short
```

Expected: 无 whitespace 错误；status 仅包含本需求文件。

---

### Task 7：四 target generic iPhoneOS 构建与验收交接

**Files:**

- No source changes unless a build error directly属于本需求
- Update after execution: implementation summary document under `docs/`，文件名使用执行时的 `yyMMdd_HHmm_..._summary.md`

**Interfaces:**

- Consumes all completed implementation tasks
- Produces build evidence and explicit real-device/server acceptance checklist

- [ ] **Step 1：构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 2：构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3：构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4：构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5：真机验证 4G/WiFi Information**

逐项记录：已连接进入自动 TimeGet、未连接文案、点击重试、连续点击去重、seconds 为零/超时、断开、正负 Offset 格式、页面退出后的旧响应恢复。

- [ ] **Step 6：真机验证 Fast Add 和 WiFi 页面回归**

分别验证 4G/WiFi：Fast Add TimeSet 成功；TimeSet 失败仍添加成功且 Cloud payload 省略时间字段；WiFi Proxy Ready 不发送 TimeSet但网络信息仍自动加载；Sync Gateways 可后续修正失败 Gateway。

- [ ] **Step 7：服务器回读验收**

TimeGet/TimeSet 成功后的 `.syncGateway` 必须通过真实 `/get/siteprops` 回读匹配 Gateway 的 `timestamp/timezoneOffset`。失败路径必须回读确认服务器对缺失字段的真实行为；不能以本地 Node 保存或 HTTP 成功代替服务器持久化证据。

- [ ] **Step 8：编写实现总结**

总结必须区分：聚焦测试、静态 contract、四 target build、真机 BLE/Mesh、真实服务器回读。未执行的真机或服务器项明确标记为待验收。

## 需求覆盖自审

- Information 两行、位置、格式、点击和连接语义：Tasks 1–3。
- Gateway TimeStatus 本地持久化与 Cloud Gateway 快照：Task 2。
- Site 根级 timezone 不可写：Tasks 2、3、6。
- Fast Add 4G/WiFi 一次 TimeSet、失败不回滚且省略字段：Task 4。
- 停止 WiFi 页面自动 TimeSet并保留自动加载：Task 5。
- Sync Gateways 保持后续唯一修正入口：Tasks 4、6、7。
- 四 target、本地化、真机和服务器证据边界：Tasks 3、6、7。
