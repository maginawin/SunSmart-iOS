# 全部 EFC Controller 恢复支持 Implementation Plan

> **执行要求：** 在当前 `fix` worktree 中使用 Superpowers Inline Execution 按任务执行；每个任务遵循测试先行。未经用户明确授权，不创建 Git commit。

**目标：** 让 Restore Device Data 支持设备配置注册表中全部 EmergencyController 产品，并确保只有相同 CID/PID 的历史设备能够恢复，且恢复成功必须经过当前 EFC 专用同步链确认。

**架构：** 保留 SDK 现有基于 MAC/旧 MAC 的历史 Node 扫描，不修改 NordicSigMeshSDK。App 新增纯 Swift 候选身份策略，在页面扫描边界按注册表和 CID/PID 校验 EFC；Fast Add 仅负责 Provision、Key Bind、本地 EFC 数据迁移，随后顺序复用 `SyncDevicesViewController(.emergencyFire)` 完成权威任务同步和状态落库。

**技术栈：** Swift、UIKit、NordicSigMeshSDK、独立 `swiftc` 聚焦测试、Shell contract、Xcode iPhoneOS build。

## 全局约束

- 所有 EFC Controller 类型按当前 `MeshLibManager.manager.supportDeviceInfos` 动态识别，不维护 PID 白名单。
- EFC 的历史 Node 与当前广播必须都存在 CID/PID、都精确命中 EmergencyController 注册项，且两个身份完全一致。
- 非 EFC 设备保持现有恢复身份行为；Gateway Restore 入口保持仅 Gateway。
- EFC Fast Add 阶段不得继续展平 `EmergencyFireControllerSyncPlanner` handles。
- EFC Provision 成功不等于 Restore 成功；只有 `.emergencyFire` 同步后 `isSynced == true` 才显示成功。
- EFC 失败和 Retry 不得进入普通 `.devices` 同步。
- 不新增用户可见文案；复用现有 `Sync device(s)`、Repair、Failed、Retry 文案和国际化 key。
- 新增源码必须加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 只使用 iPhoneOS generic destination 构建，不使用 Simulator。
- 不修改本地 NordicSigMeshSDK，不提交 Git。

---

## 文件结构

- 新建 `SunSmart/Main/Device/Model/DeviceRestoreCandidatePolicy.swift`：纯 Swift EFC 注册身份和扫描候选策略，不依赖 UIKit、数据库或 NordicSigMeshSDK。
- 新建 `Tests/Device/DeviceRestoreCandidatePolicyTests.swift`：覆盖多个 EFC 产品、身份缺失/不匹配和入口范围。
- 新建 `scripts/check_device_restore_efc_support.sh`：编译运行聚焦测试，并检查新源码属于四个 App target。
- 修改 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`：接入候选策略，移除旧的 EFC handles 执行方式，串联 EFC 专用同步队列和 Retry 路由。
- 修改 `scripts/check_efc_controller_flows.sh`：删除“Restore 必须排除 EFC”的旧合约，锁定动态注册表、精确身份和 `.emergencyFire` 路由。
- 修改 `SunSmart.xcodeproj/project.pbxproj`：将候选策略文件加入四个共享 target。
- 新建 `docs/260803_1034_efc_restore_all_controllers_implementation_summary.md`：记录最终实现、验证结果和真机边界。

## Task 1：建立纯 Swift EFC 恢复候选策略

**文件：**

- 新建：`SunSmart/Main/Device/Model/DeviceRestoreCandidatePolicy.swift`
- 新建：`Tests/Device/DeviceRestoreCandidatePolicyTests.swift`
- 新建：`scripts/check_device_restore_efc_support.sh`
- 修改：`SunSmart.xcodeproj/project.pbxproj`

**接口：**

- 输入：历史 Node CID/PID、广播 CID/PID、设备配置注册表、入口类型、Gateway/Space 归属。
- 输出：历史 Node 是否属于入口、扫描身份是否允许恢复、某身份是否为已注册 EFC。

- [ ] **Step 1：先创建失败的候选策略测试**

测试定义以下纯值类型和预期调用：

```swift
let registrations = [
    DeviceRestoreProductRegistration(
        identity: .init(companyIdentifier: 0x0A78, productIdentifier: 0x2131),
        deviceCategory: "EmergencyController"
    ),
    DeviceRestoreProductRegistration(
        identity: .init(companyIdentifier: 0x1234, productIdentifier: 0x5678),
        deviceCategory: "EmergencyController"
    ),
    DeviceRestoreProductRegistration(
        identity: .init(companyIdentifier: 0x0A78, productIdentifier: 0x2001),
        deviceCategory: "Lighting"
    ),
]

precondition(DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
    .init(companyIdentifier: 0x0A78, productIdentifier: 0x2131),
    registrations: registrations
))
precondition(DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
    .init(companyIdentifier: 0x1234, productIdentifier: 0x5678),
    registrations: registrations
))
```

还必须断言：

- 相同 EFC CID/PID 允许；
- 不同 EFC 产品拒绝；
- 旧身份或广播身份缺失拒绝；
- 旧 EFC/广播普通设备、旧普通设备/广播 EFC 都拒绝；
- 两端都是非 EFC 时保持允许；
- `.all` 允许 EFC；
- `.currentSpaceNonGateways` 允许同 Space EFC、拒绝其他 Space 和 Gateway；
- `.gatewaysOnly` 只允许 Gateway。

- [ ] **Step 2：运行测试确认因类型尚不存在而失败**

运行：

```bash
swiftc -parse-as-library Tests/Device/DeviceRestoreCandidatePolicyTests.swift -o /tmp/DeviceRestoreCandidatePolicyTests
```

预期：编译失败，错误包含找不到 `DeviceRestoreCandidatePolicy` 或相关输入类型。

- [ ] **Step 3：实现最小候选策略**

源码提供以下确定接口：

```swift
struct DeviceRestoreProductIdentity: Hashable {
    let companyIdentifier: UInt16
    let productIdentifier: UInt16
}

struct DeviceRestoreProductRegistration: Equatable {
    let identity: DeviceRestoreProductIdentity
    let deviceCategory: String
}

enum DeviceRestoreCandidateFilter {
    case all
    case gatewaysOnly
    case currentSpaceNonGateways
}

enum DeviceRestoreCandidatePolicy {
    static func identity(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> DeviceRestoreProductIdentity?
    static func isRegisteredEmergencyController(
        _ identity: DeviceRestoreProductIdentity?,
        registrations: [DeviceRestoreProductRegistration]
    ) -> Bool
    static func includesHistoricalNode(
        filter: DeviceRestoreCandidateFilter,
        isGateway: Bool,
        belongsToCurrentSpace: Bool
    ) -> Bool
    static func allowsScannedIdentity(
        historicalIdentity: DeviceRestoreProductIdentity?,
        advertisedIdentity: DeviceRestoreProductIdentity?,
        registrations: [DeviceRestoreProductRegistration]
    ) -> Bool
}
```

`allowsScannedIdentity` 规则固定为：只要任一端属于已注册 EFC，就必须两端均为已注册 EFC且身份相等；两端均非 EFC 时返回 `true`，保持普通设备现状。

- [ ] **Step 4：运行聚焦测试确认通过**

运行：

```bash
swiftc -parse-as-library SunSmart/Main/Device/Model/DeviceRestoreCandidatePolicy.swift Tests/Device/DeviceRestoreCandidatePolicyTests.swift -o /tmp/DeviceRestoreCandidatePolicyTests
/tmp/DeviceRestoreCandidatePolicyTests
```

预期：输出 `DeviceRestoreCandidatePolicyTests passed`。

- [ ] **Step 5：加入四个 target 并建立检查脚本**

`check_device_restore_efc_support.sh` 必须：

1. 编译并执行上述测试；
2. 检查 `DeviceRestoreCandidatePolicy.swift` 在 `project.pbxproj` 中存在四条 Sources build file；
3. 检查文件引用存在；
4. 输出 `PASS: Restore Device Data EFC support`。

运行脚本，预期 PASS。

## Task 2：在 Restore 扫描边界接入动态注册与精确身份

**文件：**

- 修改：`SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- 修改：`scripts/check_efc_controller_flows.sh`

**接口：**

- 消费 Task 1 的 `DeviceRestoreCandidatePolicy`。
- 产生页面适配方法 `restoreProductRegistrations`、`restoreProductIdentity`、`isRegisteredEmergencyController` 和 `shouldIncludeRestoreCandidate`。

- [ ] **Step 1：先更新 EFC contract 使当前实现失败**

删除旧的两条排除断言，新增断言要求：

- `shouldIncludeRestoreNode` 调用 `DeviceRestoreCandidatePolicy.includesHistoricalNode`；
- 扫描回调调用 `shouldIncludeRestoreCandidate(node:device:)`；
- 页面使用 `MeshLibManager.manager.supportDeviceInfos` 构建注册项；
- 不出现 `return node.deviceType != .emergencyController`；
- 不出现 `node.deviceType != .gateway && node.deviceType != .emergencyController`。

运行：

```bash
bash scripts/check_efc_controller_flows.sh
```

预期：FAIL，指出候选策略尚未接入。

- [ ] **Step 2：实现 ViewController 适配层**

适配层必须从每个 `MeshDeviceConfigInfo` 构造：

```swift
DeviceRestoreProductRegistration(
    identity: .init(
        companyIdentifier: info.companyId,
        productIdentifier: info.productId
    ),
    deviceCategory: info.deviceCategory
)
```

`shouldIncludeRestoreNode` 只处理入口和 Space 归属，不再排除 EFC。扫描回调在 RSSI 判断之后、写入 section 之前调用精确身份校验；若历史或广播任一端属于 EFC 而规则不满足，立即丢弃。

- [ ] **Step 3：保证 EFC 类型使用精确配置项**

对通过身份校验的 EFC，从注册表按 CID+PID 精确取得 `MeshDeviceConfigInfo`，写入历史 Node 的 `deviceConfigInfo`，并将 `ProvisioningDevice.deviceType` 设置为 `.emergencyController`。非 EFC 继续沿用历史 Node 的类型赋值。

- [ ] **Step 4：运行候选测试与 EFC contract**

运行：

```bash
bash scripts/check_device_restore_efc_support.sh
bash scripts/check_efc_controller_flows.sh
```

预期：全部 PASS。

## Task 3：移除过时的 EFC Fast Add handles 执行链

**文件：**

- 修改：`SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- 修改：`scripts/check_efc_controller_flows.sh`

**接口：**

- 保留：`restoreEmergencyFireControllerIfNeeded(oldNode:newNode:) -> DeviceEmerFireData?`。
- 删除：EFC message handle 地址映射、handle failure 聚合和 `resolveEmergencyFireRestoreSyncFailed`。
- 产生：Provision 成功后的 `emergencyFireRestoreControllersByAddress` 待同步集合。

- [ ] **Step 1：先增加禁止旧执行方式的 contract**

断言 Restore 文件中不存在：

```text
prepareEmergencyFireControllerRestoreMessages
emergencyFireRestoreMessageHandlesByAddress
emergencyFireRestoreControllerAddress(containing:
resolveEmergencyFireRestoreSyncFailed
failedEmergencyFireRestoreControllerAddresses
```

同时断言仍存在 `DeviceEmerFireStore.shared.restoreDevice`。运行 contract，预期因旧符号存在而失败。

- [ ] **Step 2：将 EFC Fast Add 分支改为只迁移数据**

EFC 分支执行：

1. 精确确认 old/new Node 属于相同已注册 EFC；
2. 调用 `restoreEmergencyFireControllerIfNeeded`；
3. 保留 Attention 消息；
4. 不调用 Planner、不追加 EFC vendor/publication/subscription handles；
5. 迁移失败时记录为 EFC restore failure，后续显示 `syncFailed`。

- [ ] **Step 3：修改 addSuccess 真值**

如果新地址存在 EFC controller：

- Node 仍加入 `restoreNodes`；
- `ProvisioningDevice.addState` 设置为 `.adding`；
- 不写 `controller.isSynced = true`；
- 等待 Task 4 专用同步完成。

普通设备、Battery Power Switch、Dongle 和 Gateway 收口保持原样。

- [ ] **Step 4：运行 EFC contract**

运行 `bash scripts/check_efc_controller_flows.sh`，预期 PASS。

## Task 4：串联 EFC 专用同步队列和正确 Retry

**文件：**

- 修改：`SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- 修改：`scripts/check_efc_controller_flows.sh`

**接口：**

- 产生：`runEmergencyFireRestoreSyncQueue(entries:completion:)`。
- 每个 entry 包含 `ProvisioningDevice` 与 `DeviceEmerFireData`。
- 每个同步页面固定使用：

```swift
SyncDevicesViewController(
    type: .emergencyFire(
        data: controller,
        items: nil,
        context: .saveConfiguration(
            persistsSyncResult: true,
            changedFromConfiguration: nil
        )
    )
)
```

- [ ] **Step 1：先增加专用同步与 Retry contract**

要求 Restore 文件包含 `.emergencyFire(data:`、`persistsSyncResult: true` 和专用队列方法；要求 `syncBtnAction` 先拆分 EFC/普通失败设备，并且 EFC 不被传入 `.devices(syncFailedNodes)`。

运行 contract，预期失败。

- [ ] **Step 2：实现初次恢复队列**

在普通 deferred restore 与 CCT 读取完成后、`finishDeviceRestoreAdd` 之前：

1. 收集 Provision 成功且有本地 controller 的 EFC；
2. 按地址顺序逐个 push `.emergencyFire` 页面；
3. `syncSuccessCallback` 中再次检查 `controller.isSynced`；为真时设备设为 `.success`，否则 `.syncFailed`；
4. `backActionCallback` 中将当前设备设为 `.syncFailed`；
5. 两种回调均先 pop 当前同步页，再处理下一 EFC；
6. 全部处理后才调用原 `finishDeviceRestoreAdd`。

为避免当前 Sync 页面自动恢复失败时直接跳回 BLE 页面并绕过队列，队列内的 EFC Sync 页面不启用其通用 `automationRestore` 跳转；失败停留在专用页面，由用户查看原因、Retry 或返回。成功仍自动收口并继续队列。

- [ ] **Step 3：拆分手动 Retry 路由**

`syncBtnAction` 固定顺序：

1. 从 `syncFailed` 设备中解析 EFC controller；
2. 先运行 EFC 专用队列；
3. 队列结束后仅把剩余普通 Node 传入 `.devices`；
4. EFC 成功仅在 `controller.isSynced == true` 时改为 success；
5. BLE OTA specified 流程在全部专用/普通 Retry 完成后才执行原回调或返回。

- [ ] **Step 4：处理初始 Planner/能力失败**

如果 Scene Client、绑定 Node、Node readiness 或 publish group 不满足，现有 Planner 会使专用同步页进入失败并展示既有 Repair/Failed 信息。Restore 保持该设备 `.syncFailed`，不转普通设备成功，不新增硬编码模型白名单。

- [ ] **Step 5：运行聚焦 contract**

运行：

```bash
bash scripts/check_device_restore_efc_support.sh
bash scripts/check_efc_controller_flows.sh
```

预期：全部 PASS。

## Task 5：静态检查、四 target 构建与交付记录

**文件：**

- 检查：所有本次改动文件
- 新建：`docs/260803_1034_efc_restore_all_controllers_implementation_summary.md`

- [ ] **Step 1：执行差异与格式检查**

运行：

```bash
git diff --check
git status --short
```

确认只包含本次 EFC Restore 源码、测试、脚本、工程配置和 docs；保留用户已有改动。

- [ ] **Step 2：执行所有聚焦测试与现有 EFC contracts**

运行：

```bash
bash scripts/check_device_restore_efc_support.sh
bash scripts/check_efc_controller_flows.sh
bash scripts/check_efc_comprehensive_status_mapping.sh
bash scripts/check_efc_status_content_list.sh
bash scripts/check_efc_i18n.sh
```

预期：全部 PASS。

- [ ] **Step 3：构建四个 iPhoneOS target**

逐条直接运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：四条命令均 `BUILD SUCCEEDED`。

- [ ] **Step 4：记录验证边界**

实施总结必须明确区分：

- 已完成的静态测试、contracts 和 iPhoneOS 构建；
- 未完成的真实 `0x0A78/0x2131` EFC、第二种 EFC 产品、关联灯在线/离线、BLE OTA specified、真实 Mesh ACK、网关和服务器配置验收。

## 自检结果

- 规格覆盖：全部注册 EFC、CID/PID 精确一致、Space/OTA 入口、Gateway 不变、两阶段同步、专用 Retry、四 target 均已分配任务。
- 范围检查：不修改 SDK、不重构 Planner/SyncDevices 页面、不新增文案、不改变普通设备身份规则。
- 类型一致性：计划统一使用 `DeviceRestoreProductIdentity`、`DeviceRestoreProductRegistration`、`DeviceRestoreCandidatePolicy` 和 `.emergencyFire(... .saveConfiguration(persistsSyncResult: true ...))`。
- 占位符检查：未使用未决占位内容或未定义的文件名。
