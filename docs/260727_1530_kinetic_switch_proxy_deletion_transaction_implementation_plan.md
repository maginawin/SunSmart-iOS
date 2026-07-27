# Kinetic Switch Proxy 删除事务实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents.

**Goal:** 让 Kinetic Switch Proxy 只在 Mesh 解绑成功或节点从 Space 删除后清除本地关联，并让 Group Members 移除 Proxy 节点成为可重试的复合事务。

**Architecture:** 扩展现有纯 Swift `KineticSwitchBindingPolicy`，集中表达保存、同步、Group Members 预检和引用清理决策。业务控制器只负责把策略结果应用到 `DeviceSwitchData`；Mesh 成功回调提交实际状态，失败路径不清除当前 Proxy。Group Members 在任何状态修改前完成原子预检和用户确认，并复用现有同步步骤依赖保证 Proxy 清理先于真实组退订。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 SQLite 数据模型、独立 `swiftc` 策略/源码契约测试、Xcode generic iPhoneOS build。

## Global Constraints

- 所有实现与文档使用简体中文说明，UI 文案使用英文默认值并同步简体中文。
- 支持 iOS 15 及以上，不新增第三方依赖。
- 不修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 不新增 Auth 信息，不重构无关模块，不格式化无关文件。
- 新增本地化 Key 必须同时写入 `SunSmart/en.lproj/Localizable.strings` 和 `SunSmart/zh-Hans.lproj/Localizable.strings`。
- 新增共享 Swift 文件必须继续属于 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 保留工作区中已有修改，不执行 Git commit、merge、push 或 reset。
- 严格执行 RED → 最小 GREEN；编译通过与真机 Mesh 验收分开报告。
- iOS 构建直接使用 `xcodebuild`、generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO`，不使用 shell 包装、重定向或 Simulator。

---

### Task 1: 扩展 Proxy 事务纯策略

**Files:**

- Modify: `SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift`
- Modify: `Tests/Device/KineticSwitchBindingPolicyTests.swift`

**Interfaces:**

- Produces: `KineticSwitchProxySaveDecision<Address>`
- Produces: `KineticSwitchGroupMemberRemovalDecision`
- Produces: `KineticSwitchProxyReferenceCleanupDecision`
- Produces: `KineticSwitchBindingPolicy.proxySaveDecision(savedCurrent:pendingRemoval:requestedCurrent:)`
- Produces: `KineticSwitchBindingPolicy.shouldConfigureProxy(current:pendingRemoval:isExitingGroup:)`
- Produces: `KineticSwitchBindingPolicy.groupMemberRemovalDecision(node:current:pendingRemoval:)`
- Produces: `KineticSwitchBindingPolicy.referenceCleanupDecision(node:current:pendingRemoval:)`

- [ ] **Step 1: 为保存事务写失败测试**

在现有测试入口增加以下用例：

```swift
testRemovingCurrentProxyPreservesItUntilUnbindSucceeds()
testReplacingCurrentProxyMarksOldProxyForRemoval()
testDifferentPendingProxyRejectsNewRemoval()
```

核心断言：

```swift
precondition(
    KineticSwitchBindingPolicy.proxySaveDecision(
        savedCurrent: 0x0001,
        pendingRemoval: Optional<UInt16>.none,
        requestedCurrent: Optional<UInt16>.none
    ) == .preserveCurrentForRemoval(0x0001)
)
```

- [ ] **Step 2: 为同步优先级和 Group Members 预检写失败测试**

覆盖：

```swift
precondition(
    KineticSwitchBindingPolicy.shouldConfigureProxy(
        current: 0x0001,
        pendingRemoval: 0x0001,
        isExitingGroup: false
    ) == false
)

precondition(
    KineticSwitchBindingPolicy.groupMemberRemovalDecision(
        node: 0x0002,
        current: 0x0002,
        pendingRemoval: 0x0001
    ) == .rejectPendingRemovalConflict
)
```

同时覆盖：

- 稳定绑定允许检查配置；
- L1 → L2 替换允许配置 L2；
- 节点正在退组时禁止生成绑定任务；
- 节点只作为已有待删除 Proxy 时复用旧任务；
- 当前 Proxy 与不同待删除地址冲突时拒绝覆盖。

- [ ] **Step 3: 为引用清理写失败测试**

覆盖：

```swift
let cleanup = KineticSwitchBindingPolicy.referenceCleanupDecision(
    node: 0x0001,
    current: 0x0001,
    pendingRemoval: 0x0001
)
precondition(cleanup.clearsCurrent)
precondition(cleanup.clearsPendingRemoval)
precondition(cleanup.clearsCredentials)
```

并覆盖当前 Proxy 为 L2、待删除 Proxy 为 L1 时，删除 L1 只清理待删除地址。

- [ ] **Step 4: 运行测试确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests
```

Expected: 编译失败，提示新增决策类型或函数不存在。

- [ ] **Step 5: 实现最小纯策略**

新增类型：

```swift
enum KineticSwitchProxySaveDecision<Address: Equatable>: Equatable {
    case unchanged
    case preserveCurrentForRemoval(Address)
    case replaceCurrent(pendingRemoval: Address)
    case rejectPendingRemovalConflict
}

enum KineticSwitchGroupMemberRemovalDecision: Equatable {
    case unaffected
    case markPendingRemoval
    case reusePendingRemoval
    case rejectPendingRemovalConflict
}

struct KineticSwitchProxyReferenceCleanupDecision: Equatable {
    let clearsCurrent: Bool
    let clearsPendingRemoval: Bool
    let clearsCredentials: Bool
}
```

实现规则：

```swift
static func shouldConfigureProxy<Address: Equatable>(
    current: Address?,
    pendingRemoval: Address?,
    isExitingGroup: Bool
) -> Bool {
    guard !isExitingGroup, let current else {
        return false
    }
    return current != pendingRemoval
}
```

其他函数严格实现设计文档中的状态表，不读取 UIKit、数据库或 SDK 类型。

- [ ] **Step 6: 运行测试确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests
/tmp/KineticSwitchBindingPolicyTests
```

Expected: 输出 `KineticSwitchBindingPolicyTests passed`。

---

### Task 2: 保存时保留当前 Proxy，成功后再提交清除

**Files:**

- Modify: `SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Test: `Tests/Device/KineticSwitchBindingPolicyTests.swift`

**Interfaces:**

- Consumes: `proxySaveDecision(...)`
- Consumes: `shouldConfigureProxy(...)`
- Produces: 保存后的同地址待删除状态 `proxyNodeAddress == deleteProxyNodeAddress`

- [ ] **Step 1: 在保存入口应用 Proxy 保存决策**

在 `saveSwitch(switchData:)` 读取对应的已保存 `realSwitch`，再调用：

```swift
let decision = KineticSwitchBindingPolicy.proxySaveDecision(
    savedCurrent: realSwitch.proxyNodeAddress,
    pendingRemoval: realSwitch.deleteProxyNodeAddress,
    requestedCurrent: switchData.proxyNodeAddress
)
```

应用规则：

- `.preserveCurrentForRemoval(address)`：
  - 恢复 `switchData.proxyNodeAddress = address`；
  - 从 `realSwitch` 恢复 MAC 和 Security Key；
  - 设置 `switchData.deleteProxyNodeAddress = address`。
- `.replaceCurrent(pendingRemoval:)`：
  - 保留编辑副本的新 Proxy、MAC、Key；
  - 记录旧 Proxy 为待删除地址。
- `.rejectPendingRemovalConflict`：
  - 使用 `switch_proxy_notcleared_message`；
  - 不更新真实 Switch，不进入同步页面。
- `.unchanged`：
  - 保留现有字段。

- [ ] **Step 2: 同地址待删除时禁止生成绑定任务**

在 `DeviceSwitchData.getNeedSyncDatas(deleteSwitch:)` 的普通同步分支中，只有下列策略返回 `true` 才计算 `syncProxy`：

```swift
KineticSwitchBindingPolicy.shouldConfigureProxy(
    current: proxyNodeAddress,
    pendingRemoval: deleteProxyNodeAddress,
    isExitingGroup: false
)
```

删除任务继续从 `deleteProxyNodeAddress` 生成，确保同地址状态只有解绑任务。

- [ ] **Step 3: 运行聚焦测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests
/tmp/KineticSwitchBindingPolicyTests
```

Expected: PASS。

- [ ] **Step 4: 静态检查关键路径**

Run:

```bash
rg -n "proxySaveDecision|shouldConfigureProxy|deleteProxyNodeAddress" SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- 保存入口应用事务决策；
- 同地址待删除不会生成 `syncProxy`；
- 原有删除 Proxy 任务仍存在。

---

### Task 3: 区分 Mesh 解绑成功与 Space 删除节点

**Files:**

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `Tests/Device/KineticSwitchBindingPolicyTests.swift`

**Interfaces:**

- Consumes: `referenceCleanupDecision(node:current:pendingRemoval:)`
- Produces: `Node.commitSuccessfulEnOceanSwitchUnbind(enOceanMacAddress:)`
- Produces: `Node.removeEnOceanSwitchReferencesForDeletedNode()`

- [ ] **Step 1: 拆分两种清理入口**

将现有单个 `deleteEnOceanSwitch(enOceanMacAddress:)` 拆为语义明确的方法：

```swift
func commitSuccessfulEnOceanSwitchUnbind(enOceanMacAddress: String)
func removeEnOceanSwitchReferencesForDeletedNode()
```

- [ ] **Step 2: Mesh 成功回调处理所有匹配 Switch**

`SunricherVendorSet.enOceanDelete` 成功后：

- 遍历 `MeshNetworkManager.instance.switchs`，不使用 `first(where:)`；
- 当前地址等于节点地址时，要求 Switch MAC 与响应 MAC 一致；
- 待删除地址等于节点地址时允许清理待删除引用；
- 使用 `referenceCleanupDecision` 决定清除字段；
- 当前地址被清除时同步清除 MAC 和 Key；
- 每个变化的 Switch 都保存；
- 失败消息仍由现有 `guard isSuccess` 阻止，不提交清理。

- [ ] **Step 3: Space 删除节点按地址清理所有引用**

`deleteExtension()` 调用 `removeEnOceanSwitchReferencesForDeletedNode()`：

- 当前地址匹配：清除当前 Proxy、MAC、Key；
- 仅待删除地址匹配：只清除待删除字段；
- 同时匹配：清除全部；
- 一个节点被多个异常 Switch 引用时全部处理；
- 完成后统一发送 Switch 与 Space 刷新通知。

- [ ] **Step 4: 保持 Switch 整体删除成功后的兜底清理**

检查 `MeshNetworkManager.deleteSwitch(switchData:)`：

- 只清理由当前或待删除地址明确指向且 MAC 匹配的节点；
- 不通过两个可空 MAC 直接相等来选择节点；
- 不扩大到无关节点。

- [ ] **Step 5: 运行策略测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests
/tmp/KineticSwitchBindingPolicyTests
```

Expected: PASS。

---

### Task 4: Group Members Proxy 移除复合事务

**Files:**

- Modify: `SunSmart/Main/Group/Controller/GroupMembersViewController.swift`
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift` only if the existing dependency contract is missing
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/Device/KineticSwitchProxyTransactionContractTests.swift`

**Interfaces:**

- Consumes: `groupMemberRemovalDecision(node:current:pendingRemoval:)`
- Produces: `GroupMemberProxyRemovalPlan`
- Produces: `group_remove_switch_proxy_confirmation`

- [ ] **Step 1: 写源码契约 RED 测试**

契约测试接收以下文件路径：

1. `GroupMembersViewController.swift`
2. `Node+SyncData.swift`
3. `SyncDevicesViewController.swift`
4. `SyncDevicesCellModel.swift`
5. English `Localizable.strings`
6. Chinese `Localizable.strings`

断言：

```swift
require(groupMembersSource.contains("groupMemberProxyRemovalPlans"))
require(groupMembersSource.contains("\"group_remove_switch_proxy_confirmation\".localizedString"))
require(nodeSyncSource.contains("guard groupState != .exitFailure else"))
require(syncSource.contains("step.relevanceStepModels = deleteSteps.filter({ $0 != step })"))
require(syncSource.contains("proxyConfigurationStep.relevanceStepModels = [proxyDeletionStep]"))
require(syncModelSource.contains("models.append(contentsOf: model.deviceModel.steps)"))
require(englishStrings.contains("\"group_remove_switch_proxy_confirmation\""))
require(chineseStrings.contains("\"group_remove_switch_proxy_confirmation\""))
```

- [ ] **Step 2: 运行契约测试确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Device/KineticSwitchProxyTransactionContractTests.swift -o /tmp/KineticSwitchProxyTransactionContractTests
/tmp/KineticSwitchProxyTransactionContractTests SunSmart/Main/Group/Controller/GroupMembersViewController.swift SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: FAIL，提示缺少 Group Members 事务入口或本地化 Key。

- [ ] **Step 3: 在任何状态修改前完成原子预检**

在 `saveAction()` 计算 `exitNodes` 和 `addNodes` 后、设置 `groupState` 前：

```swift
private struct GroupMemberProxyRemovalPlan {
    let node: Node
    let switchData: DeviceSwitchData
    let decision: KineticSwitchGroupMemberRemovalDecision
}
```

新增：

```swift
private func groupMemberProxyRemovalPlans(
    for exitNodes: [Node]
) -> [GroupMemberProxyRemovalPlan]?
```

行为：

- 搜索与当前组存在绑定或待解绑关系的全部 Switch；
- `.rejectPendingRemovalConflict` 时显示现有未清理提示并返回 `nil`；
- 任一冲突阻止整批保存；
- 未发生冲突时返回所有 `.markPendingRemoval` 和 `.reusePendingRemoval` 计划。

- [ ] **Step 4: 增加影响确认**

存在 Proxy 计划时显示一次确认：

```text
One or more selected devices are being used as switch proxies. Removing them from the group will also unbind the corresponding switch proxies.
```

简体中文：

```text
一个或多个所选设备正在作为开关代理。从组中移除这些设备也会解除对应的开关代理绑定。
```

Key：

```text
group_remove_switch_proxy_confirmation
```

操作复用 `alert_item_cancel` 和 `alert_item_continue`。

取消时不设置 `groupState`、不写 `deleteProxyNodeAddress`、不进入同步。

- [ ] **Step 5: 用户继续后提交待删除意图**

对 `.markPendingRemoval`：

```swift
switchData.deleteProxyNodeAddress = node.primaryUnicastAddress
switchData.save()
```

保留当前 Proxy、MAC 和 Key。

对 `.reusePendingRemoval` 不覆盖现有地址。

随后执行原有节点 `exitFailure`、Profile 清理及 SyncDevices 页面流程。

- [ ] **Step 6: 退组期间禁止生成重新绑定任务**

在 `Node.getNodeSyncSwitchs(group:switchData:)` 中使用：

```swift
guard groupState != .exitFailure else {
    return (nil, [])
}
```

退组状态直接返回空的绑定结果，避免同一事务重新配置 Proxy 或重新添加 Switch 虚拟组订阅；删除结果继续由 `getNodeNeedDeleteSwitchs` 生成。

- [ ] **Step 7: 验证真实组退订依赖**

保留并验证现有依赖：

```swift
if let step = removeGroupStep {
    step.relevanceStepModels = deleteSteps.filter({ $0 != step })
}
```

因此任一 Proxy 或 Switch 虚拟组清理步骤失败时，真实组退订保持等待/跳过。

- [ ] **Step 8: 保证 Proxy 替换按删除 → 配置顺序执行**

当普通保存同时产生旧 Proxy 删除和新 Proxy 配置时：

- 将两个操作包装为同步步骤；
- 新 Proxy 配置步骤依赖旧 Proxy 删除步骤；
- 旧 Proxy 删除失败时跳过新 Proxy 配置；
- Proxy 子步骤和任务加入同步状态聚合，确保失败后仍可选择并重试。

- [ ] **Step 9: 运行策略与契约测试确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests
/tmp/KineticSwitchBindingPolicyTests
swiftc -parse-as-library Tests/Device/KineticSwitchProxyTransactionContractTests.swift -o /tmp/KineticSwitchProxyTransactionContractTests
/tmp/KineticSwitchProxyTransactionContractTests SunSmart/Main/Group/Controller/GroupMembersViewController.swift SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 两个测试程序均输出 `passed`。

---

### Task 5: 集成验证与总结

**Files:**

- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Create: `docs/yyMMdd_HHmm_kinetic_switch_proxy_deletion_transaction_fix_summary.md`

**Interfaces:**

- Consumes: Tasks 1–4 的全部实现。
- Produces: 自动化、编译与真机验收分层报告。

- [ ] **Step 1: 检查工程和差异**

Run:

```bash
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
```

Expected: 工程文件 `OK`，差异检查无输出。

- [ ] **Step 2: 重新执行所有聚焦测试**

Run Task 4 Step 8 的两个测试程序。

Expected: PASS。

- [ ] **Step 3: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: 保存实施总结**

总结必须列出：

- 解绑失败保留 Proxy 的状态迁移；
- Space 删除节点的直接清理；
- Group Members 确认与复合事务；
- 自动化测试结果；
- 四品牌 iPhoneOS 编译结果；
- 仍需执行的真机 Mesh 场景；
- 未修改 NordicSigMeshSDK；
- 未执行 Git commit。
