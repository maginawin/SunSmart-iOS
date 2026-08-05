# Space Mesh Node 500 上限实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagents unless the user explicitly requests them.

**Goal:** 将单个 Space 的真实 Mesh Node 上限从 300 提升到 500，并把 Classic、Professional、Group 指定添加和 Restore 收敛到同一容量策略，同时保持全部 Switch 合计 16 个的现有上限。

**Architecture:** 新增一个不依赖 UIKit 或 NordicSigMeshSDK 的 `SpaceNodeCapacityPolicy`，只负责“现有 Node + 在途 Node + 本次请求”的容量计算和稳定前缀裁剪。`SpaceData`、各 Device Add Controller 和 Restore Controller 复用该策略；Unicast Address/Element 检查继续作为容量通过后的独立第二层校验。Main 的非 Switch 分类统一显示 Space 总 Node 数/500，Switches 继续显示 Switch 数/16。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、本地 Swift Package、独立 `swiftc` focused tests、Swift source contract tests、Shell check、Xcode generic iPhoneOS builds。

## Global Constraints

- 单个 Space 最多 500 个真实 Mesh Node，按 Node 数统计，不按 Element/Unicast Address 数统计。
- Battery Power Switch 和 AC Power Switch 各占 1 个 Node 名额，并继续占用 1 个 Switch 名额；当前产品各有 8 个 Element。
- Kinetic Switch 不占新增 Node 名额；Space 已有 500 个 Node 时，只要 Switch 少于 16 且 Group Address 足够，仍可新增 Kinetic Switch。
- Kinetic、Battery、AC 三种 Switch 合计仍最多 16 个；不得修改该上限。
- 超出剩余 Node 名额的批量请求沿用部分接受：稳定保留当前顺序中的前 N 个，其余取消选择并提示上限；任何路径都不得 Provision 第 501 个 Node。
- Restore 仅在具有具体 `SpaceData` 上下文时应用 Space Node 上限；Site 级 Gateway Restore 的 `space == nil` 路径不套用 Space 上限。
- Node 容量校验必须先于 Unicast Address 申请，禁止为已超出 500 Node 的设备发起无意义地址申请。
- 不修改 NordicSigMeshSDK 业务源码；只有 500 Node 压测证明存在 SDK 瓶颈时才另立任务。
- 不修改数据库 schema、图片资源、依赖版本、Scene/Timed/Group/Gateway/OTA 限制。
- `devices_number_exceeds_message` 已使用 `%d`，本次不新增本地化 Key。
- 新公共源码必须同时加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 所有构建使用 generic iPhoneOS，不使用 Simulator，不通过 shell 包装或重定向日志。
- 未经用户明确授权，不执行 Git commit、push 或 merge；每个 Task 以验证检查点代替 commit。

---

## 文件结构与职责

### 新建文件

- `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
  - Foundation-only 容量策略；定义 500 上限、剩余名额、接受数量和稳定前缀裁剪。
- `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
  - 纯 Swift 边界测试，不依赖 App、UIKit 或 SDK。
- `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
  - 读取 App 源码，锁定容量策略在 SpaceData、Main、Classic、Professional、Restore 和 Switch 路径中的接入契约。
- `scripts/check_space_node_capacity.sh`
  - 编译并运行 focused tests、integration contract，并校验公共策略属于四个 App target。

### 修改文件

- `SunSmart.xcodeproj/project.pbxproj`
  - 为 `SpaceNodeCapacityPolicy.swift` 增加一个 File Reference 和四个 Sources Build Phase 条目。
- `SunSmart/Common/Data/SpaceData.swift`
  - `maxDevicesCount` 改为读取统一策略的 500 上限。
- `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`
  - 为 `.wait`、`.addConnecting`、`.adding` 提供统一的 Node 容量预留判断。
- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - 左下角容量分子改用 Space 全部真实 Node 数。
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 全选、手动选择和最终批量开始添加统一使用容量策略。
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - Professional 候选页的全选、逐项选择和单项添加统一使用容量策略。
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 在 Controller 边界重新裁剪批次，防止 View 层绕过。
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - Space Restore 的全选和最终开始恢复使用容量策略；Site Gateway Restore 保持原行为。

### 明确不修改

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/**`
- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift` 的 `/16` 规则
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

---

### Task 1: 建立纯 Swift Space Node 容量策略

**Files:**

- Create: `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
- Create: `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
- Create: `scripts/check_space_node_capacity.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `SpaceNodeCapacityPolicy.maxNodeCount: Int`
- Produces: `SpaceNodeCapacityPolicy.remainingNodeCount(existingNodeCount:inFlightNodeCount:) -> Int`
- Produces: `SpaceNodeCapacityPolicy.acceptedNodeCount(existingNodeCount:inFlightNodeCount:requestedNodeCount:) -> Int`
- Produces: `SpaceNodeCapacityPolicy.acceptedPrefix(_:existingNodeCount:inFlightNodeCount:) -> [Element]`
- Depends on: Swift Standard Library only

- [ ] **Step 1: 先写容量边界失败测试**

创建 `Tests/Device/SpaceNodeCapacityPolicyTests.swift`，测试内容固定为：

```swift
@main
struct SpaceNodeCapacityPolicyTests {
    static func main() {
        precondition(SpaceNodeCapacityPolicy.maxNodeCount == 500)
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 499,
                inFlightNodeCount: 0
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 500,
                inFlightNodeCount: 0
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 498,
                inFlightNodeCount: 1
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.remainingNodeCount(
                existingNodeCount: 501,
                inFlightNodeCount: 0
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedNodeCount(
                existingNodeCount: 499,
                inFlightNodeCount: 0,
                requestedNodeCount: 2
            ) == 1
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedNodeCount(
                existingNodeCount: 500,
                inFlightNodeCount: 0,
                requestedNodeCount: 1
            ) == 0
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedPrefix(
                ["A", "B", "C"],
                existingNodeCount: 498,
                inFlightNodeCount: 1
            ) == ["A"]
        )
        precondition(
            SpaceNodeCapacityPolicy.acceptedPrefix(
                ["A", "B"],
                existingNodeCount: -1,
                inFlightNodeCount: -1
            ) == ["A", "B"]
        )
        print("SpaceNodeCapacityPolicyTests passed")
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Device/SpaceNodeCapacityPolicyTests.swift -o /tmp/SpaceNodeCapacityPolicyTests
```

Expected: 编译失败，错误包含 `cannot find 'SpaceNodeCapacityPolicy' in scope`。

- [ ] **Step 3: 实现最小容量策略**

创建 `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`：

```swift
enum SpaceNodeCapacityPolicy {
    static let maxNodeCount = 500

    static func remainingNodeCount(
        existingNodeCount: Int,
        inFlightNodeCount: Int
    ) -> Int {
        let occupiedNodeCount = max(existingNodeCount, 0) + max(inFlightNodeCount, 0)
        return max(maxNodeCount - occupiedNodeCount, 0)
    }

    static func acceptedNodeCount(
        existingNodeCount: Int,
        inFlightNodeCount: Int,
        requestedNodeCount: Int
    ) -> Int {
        min(
            max(requestedNodeCount, 0),
            remainingNodeCount(
                existingNodeCount: existingNodeCount,
                inFlightNodeCount: inFlightNodeCount
            )
        )
    }

    static func acceptedPrefix<Element>(
        _ elements: [Element],
        existingNodeCount: Int,
        inFlightNodeCount: Int
    ) -> [Element] {
        let count = acceptedNodeCount(
            existingNodeCount: existingNodeCount,
            inFlightNodeCount: inFlightNodeCount,
            requestedNodeCount: elements.count
        )
        return Array(elements.prefix(count))
    }
}
```

- [ ] **Step 4: 将策略加入四个 App target**

修改 `SunSmart.xcodeproj/project.pbxproj`：

- 在 `PBXFileReference` 中加入一次 `SpaceNodeCapacityPolicy.swift`。
- 将 File Reference 放入 `SunSmart/Main/Device/Model` 对应 Group。
- 在四个 `PBXSourcesBuildPhase` 中各加入一次该文件。
- 不修改 NordicSigMeshSDK package reference，不新增依赖。

- [ ] **Step 5: 建立 focused check 脚本**

创建 `scripts/check_space_node_capacity.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

policy="SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift"
policy_tests="Tests/Device/SpaceNodeCapacityPolicyTests.swift"
contract_tests="Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift"
project="SunSmart.xcodeproj/project.pbxproj"
policy_binary="/tmp/SpaceNodeCapacityPolicyTests"
contract_binary="/tmp/SpaceNodeCapacityIntegrationContractTests"

swiftc -parse-as-library "$policy" "$policy_tests" -o "$policy_binary"
"$policy_binary"

if [ -f "$contract_tests" ]; then
  swiftc -parse-as-library "$contract_tests" -o "$contract_binary"
  "$contract_binary" "$PWD"
fi

source_count="$(rg -c 'SpaceNodeCapacityPolicy.swift in Sources \*/,$' "$project")"
if [ "$source_count" -ne 4 ]; then
  printf 'FAIL: SpaceNodeCapacityPolicy must belong to all four app targets.\n' >&2
  exit 1
fi

printf 'PASS: Space Node capacity policy and target membership.\n'
```

- [ ] **Step 6: 运行测试并确认 GREEN**

Run:

```bash
bash scripts/check_space_node_capacity.sh
```

Expected:

```text
SpaceNodeCapacityPolicyTests passed
PASS: Space Node capacity policy and target membership.
```

- [ ] **Step 7: Task 1 检查点**

Run: `git diff --check`

Expected: exit 0，无输出。检查 diff 仅包含容量策略、测试、脚本和四 target membership；不执行 commit。

---

### Task 2: 接入 SpaceData、Main 容量显示和在途状态真值

**Files:**

- Create: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
- Modify: `SunSmart/Common/Data/SpaceData.swift:207-208`
- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift:36-65`
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:314-326`
- Verify unchanged: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift:263`
- Modify: `scripts/check_space_node_capacity.sh`

**Interfaces:**

- Consumes: `SpaceNodeCapacityPolicy.maxNodeCount`
- Produces: `ProvisioningDevice.DeviceAddState.reservesNodeCapacity: Bool`
- Preserves: `SpaceData.maxDevicesCount: Int` for existing call sites
- Preserves: Switches footer `/16`

- [ ] **Step 1: 写 Space/Main/Switch integration contract 的 RED 断言**

创建 `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`，读取 repository root 参数，并至少断言：

```swift
import Foundation

@main
struct SpaceNodeCapacityIntegrationContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }
        let root = CommandLine.arguments[1]
        let spaceData = try source(root, "SunSmart/Common/Data/SpaceData.swift")
        let provisioningState = try source(
            root,
            "SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift"
        )
        let lights = try source(
            root,
            "SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
        )
        let switches = try source(
            root,
            "SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift"
        )
        let devices = try source(
            root,
            "SunSmart/Main/Device/Controller/DevicesViewController.swift"
        )
        let lightsUpdateUI = section(
            in: lights,
            from: "private func updateUI(reloadTableView: Bool = true)",
            to: "private func updateAllOnOffItemUI()"
        )

        require(
            spaceData.contains("SpaceNodeCapacityPolicy.maxNodeCount"),
            "SpaceData must expose the shared 500-node policy"
        )
        require(
            !spaceData.contains("var maxDevicesCount: Int = 300"),
            "SpaceData must not retain the 300-node root value"
        )
        require(
            provisioningState.contains("var reservesNodeCapacity: Bool"),
            "Provisioning add state must define the in-flight capacity truth"
        )
        require(
            provisioningState.contains("case .wait, .addConnecting, .adding:"),
            "Only wait, connecting, and adding states reserve node capacity"
        )
        require(
            lightsUpdateUI.contains(
                "let nodeCount = MeshNetworkManager.instance.realNodes.count"
            ) && lightsUpdateUI.contains(
                "footerView.countBtn.setTitle(\"\\(nodeCount)/\\(space.maxDevicesCount)\""
            ),
            "Lights footer must display total Space nodes"
        )
        require(
            switches.contains("\\(MeshNetworkManager.instance.switchs.count)/16"),
            "Switches footer must retain the aggregate 16-switch limit"
        )
        let switchAdd = section(
            in: devices,
            from: "private func switchAdd()",
            to: "private func preCreatedDongle()"
        )
        require(
            switchAdd.contains("MeshNetworkManager.instance.switchs.count < 16"),
            "Kinetic Switch add must retain the 16-switch limit"
        )
        require(
            !switchAdd.contains("maxDevicesCount") && !switchAdd.contains("realNodes.count"),
            "Kinetic Switch add must remain independent from the Mesh Node limit"
        )

        print("SpaceNodeCapacityIntegrationContractTests passed")
    }

    private static func source(_ root: String, _ path: String) throws -> String {
        try String(contentsOfFile: root + "/" + path, encoding: .utf8)
    }

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard
            let startRange = source.range(of: start),
            let endRange = source.range(
                of: end,
                range: startRange.upperBound..<source.endIndex
            )
        else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
```

- [ ] **Step 2: 运行 contract 并确认 RED**

Run: `bash scripts/check_space_node_capacity.sh`

Expected: `SpaceNodeCapacityIntegrationContractTests` 因仍存在 300 根值或缺少 `reservesNodeCapacity` 而失败。

- [ ] **Step 3: 将 SpaceData 接入 500 单一真值**

把现有可变默认值改成只读计算属性：

```swift
/// Space 最多真实 Mesh Node 数量。
var maxDevicesCount: Int {
    SpaceNodeCapacityPolicy.maxNodeCount
}
```

不得在数据库、ImportData 或 ExportData 中增加该值，因为本次仍是所有 Space 统一固定为 500。

- [ ] **Step 4: 定义统一在途状态**

在 `ProvisioningDevice.DeviceAddState` 中新增：

```swift
var reservesNodeCapacity: Bool {
    switch self {
    case .wait, .addConnecting, .adding:
        return true
    default:
        return false
    }
}
```

`.success` 不应计为在途，因为成功 Node 已由 `realNodes.count` 统计；`.failed` 和 `.syncFailed` 也不预留新 Node 名额。

- [ ] **Step 5: 统一 Main 的非 Switch 容量显示**

在 `DeviceLightsViewController.updateUI` 中把分子从 `devices.count` 改为 `MeshNetworkManager.instance.realNodes.count`：

```swift
let nodeCount = MeshNetworkManager.instance.realNodes.count
footerView.countBtn.setTitle("\(nodeCount)/\(space.maxDevicesCount)", for: .normal)
```

Sensors、Others 已使用总 `realNodes.count`，不做行为修改。Switches 保持现有 `switchs.count/16`。

- [ ] **Step 6: 运行 focused checks 并确认 GREEN**

Run: `bash scripts/check_space_node_capacity.sh`

Expected:

```text
SpaceNodeCapacityPolicyTests passed
SpaceNodeCapacityIntegrationContractTests passed
PASS: Space Node capacity policy and target membership.
```

- [ ] **Step 7: Task 2 检查点**

Run: `git diff --check`

Expected: exit 0。检查 Switch 数量代码和中英文 `switchs_overrun_message` 均未修改；不执行 commit。

---

### Task 3: 收敛 Classic Add 的选择与最终批量边界

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

**Interfaces:**

- Consumes: `SpaceNodeCapacityPolicy.acceptedPrefix`
- Consumes: `ProvisioningDevice.DeviceAddState.reservesNodeCapacity`
- Produces: Classic 内部 `nodeCapacityAcceptedDevices(from:) -> [ProvisioningDevice]`
- Preserves: Battery/AC Power Switch 的 16 Switch 校验和 Element 地址申请

- [ ] **Step 1: 扩展 contract，先锁定最终边界**

在 integration contract 中读取 `DeviceAddClassicModeController.swift`，截取 `checkDeviceAddressesAreSufficient(devices:)`，断言：

```swift
require(
    classicCapacityCheck.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
    "Classic Add must apply the shared policy before provisioning"
)
require(
    classicCapacityCheck.contains("validateBatteryPowerSwitchLimit(for: acceptedDevices)"),
    "Classic Add must validate Switch capacity after Node batch clipping"
)
require(
    classicCapacityCheck.contains("estimatedAddressCount = acceptedDevices.reduce"),
    "Classic address demand must only include accepted Node slots"
)
```

- [ ] **Step 2: 运行 contract 并确认 RED**

Run: `bash scripts/check_space_node_capacity.sh`

Expected: 失败信息包含 `Classic Add must apply the shared policy before provisioning`。

- [ ] **Step 3: 新增 Classic 最终容量裁剪 helper**

先把 `private var maxDeviceCount = 200` 改为只读兼容入口，并删除 `init` 中的重复赋值：

```swift
private var maxDeviceCount: Int {
    space.maxDevicesCount
}
```

在 Classic Controller 中新增私有方法，要求：

```swift
private func nodeCapacityAcceptedDevices(
    from devices: [ProvisioningDevice]
) -> [ProvisioningDevice] {
    let inFlightNodeCount = showDevices.filter {
        $0.addState.reservesNodeCapacity
    }.count
    let acceptedDevices = SpaceNodeCapacityPolicy.acceptedPrefix(
        devices,
        existingNodeCount: MeshNetworkManager.instance.realNodes.count,
        inFlightNodeCount: inFlightNodeCount
    )
    guard acceptedDevices.count < devices.count else {
        return acceptedDevices
    }

    let acceptedIdentifiers = Set(
        acceptedDevices.map { $0.peripheral.identifier }
    )
    devices
        .filter { !acceptedIdentifiers.contains($0.peripheral.identifier) }
        .forEach { $0.selectedState = .unselected }
    SRAlertView(
        title: "notification".localizedString,
        message: String(
            format: "devices_number_exceeds_message".localizedString,
            space.maxDevicesCount
        ),
        actions: [SRAlertAction(title: "ok".localizedString)]
    ).show()
    return acceptedDevices
}
```

稳定顺序必须来自调用方的 `devices`；不得按 RSSI、名称或地址再次排序。

- [ ] **Step 4: 在最终开始添加处使用 acceptedDevices**

`checkDeviceAddressesAreSufficient(devices:)` 的第一步改为：

```swift
let acceptedDevices = nodeCapacityAcceptedDevices(from: devices)
guard !acceptedDevices.isEmpty else {
    updateUIState()
    return
}
guard validateBatteryPowerSwitchLimit(for: acceptedDevices) else {
    return
}
```

后续 `prepareFastAddGroupSyncBatch`、状态切换、Element 地址合计、地址申请回调和 `addDevice` 循环全部使用 `acceptedDevices`。不得让被裁掉设备进入 `.wait/.addConnecting/.adding`。

- [ ] **Step 5: 全选和逐项选择使用同一剩余名额**

- 全选时使用 `acceptedPrefix` 选择前 N 个，而不是直接执行可能为负的 `prefix(maxDeviceCount - existNodeCount)`。
- 用户尝试再选择一个设备时，已选择但尚未开始的设备也必须计入本批次请求。
- 取消选择不受容量限制。
- 保留单选绑定目标、Kinetic/Power Switch 禁选和 Dongle 提示的现有顺序。
- 把两处“Space 只能添加 200 个设备”旧注释改成“Space Node 容量检查”。

- [ ] **Step 6: 运行 focused checks 并确认 GREEN**

Run: `bash scripts/check_space_node_capacity.sh`

Expected: 所有 policy 和 integration contract 通过。

- [ ] **Step 7: Task 3 检查点**

Run: `git diff --check`

Expected: exit 0。人工检查 `acceptedDevices` 贯穿地址申请回调，未只在 UI 选择层做限制；不执行 commit。

---

### Task 4: 收敛 Professional Add 候选页与 Controller 最终边界

**Files:**

- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

**Interfaces:**

- Consumes: `SpaceNodeCapacityPolicy.acceptedPrefix`
- Consumes: `ProvisioningDevice.DeviceAddState.reservesNodeCapacity`
- Produces: Professional Controller 内部 `nodeCapacityAcceptedDevices(from:) -> [ProvisioningDevice]`
- Candidate View provides early UX clamping; Controller remains authoritative

- [ ] **Step 1: 扩展 Professional contract 并确认 RED**

新增断言：

```swift
require(
    candidateView.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
    "Professional Candidate selection must clip to remaining Node slots"
)
require(
    professionalCapacityCheck.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
    "Professional Controller must enforce Node capacity before provisioning"
)
require(
    professionalCapacityCheck.contains("validateBatteryPowerSwitchLimit(for: acceptedDevices)"),
    "Professional Power Switch validation must run on the accepted Node batch"
)
require(
    professionalCapacityCheck.contains("estimatedAddressCount = acceptedDevices.reduce"),
    "Professional address demand must only include accepted Node slots"
)
```

Run: `bash scripts/check_space_node_capacity.sh`

Expected: Candidate/Professional 新断言失败。

- [ ] **Step 2: Candidate View 收敛全选和逐项选择**

先把 Candidate View 的 `private var maxDeviceCount = 200` 改为：

```swift
private var maxDeviceCount: Int {
    space.maxDevicesCount
}
```

删除 `init(frame:space:)` 中的 `maxDeviceCount = space.maxDevicesCount`，避免继续保留第二个可变容量状态。

在 Candidate View 增加只负责当前页面 UX 的 helper，使用：

- `MeshNetworkManager.instance.realNodes.count`
- `candidateDevices.filter { $0.addState.reservesNodeCapacity }.count`
- 当前已选择且不在途的数量
- `SpaceNodeCapacityPolicy.acceptedPrefix`

全选只选择剩余前 N 个；逐项选择达到剩余名额时显示 `devices_number_exceeds_message`；单设备 `deviceAdd` 仍保留容量预检查。所有旧的 200 设备注释同步更正。

- [ ] **Step 3: Professional Controller 增加权威最终裁剪**

实现与 Classic 同名同语义的 `nodeCapacityAcceptedDevices(from:)`，但在途集合使用 `candidateDevices`。在 `checkDeviceAddressesAreSufficient(devices:)` 开头裁剪，并让以下操作全部使用 `acceptedDevices`：

- `validateBatteryPowerSwitchLimit`
- `prepareFastAddGroupSyncBatch`
- 状态变更
- `estimatedAddressCount`
- 地址申请后的添加循环
- 直接地址充足时的添加循环

`candidateView(_:startAdd:)` 继续负责单选模式的 `prefix(1)`，然后交给 Controller 容量边界，不在 Delegate 中复制另一套算术。

- [ ] **Step 4: 验证 Power Switch 双重限制顺序**

必须保持顺序：

1. 先按 Node 剩余名额裁剪。
2. 再验证裁剪后批次是否使全部 Switch 超过 16。
3. 再计算裁剪后设备的 Element 地址需求。
4. 最后开始 Provisioning。

这样 500 Node 时 Battery/AC 的 accepted batch 为 0，不发起地址申请；Kinetic Switch 不经过该物理 Provisioning 流程，因此仍只受 Switch 16 限制。

- [ ] **Step 5: 运行 focused checks 并确认 GREEN**

Run: `bash scripts/check_space_node_capacity.sh`

Expected: policy、Main/Switch contract、Classic contract、Professional contract 全部通过。

- [ ] **Step 6: Task 4 检查点**

Run: `git diff --check`

Expected: exit 0。人工确认 Candidate View 是早期 UX，Professional Controller 是最终真值；不执行 commit。

---

### Task 5: 将 Space Restore 纳入 500 Node 上限

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

**Interfaces:**

- Consumes: `SpaceNodeCapacityPolicy.acceptedPrefix`
- Produces: Restore 内部 `nodeCapacityAcceptedRestoreData(from:) -> [DeviceRestoreData]`
- Preserves: `space == nil` 的 Site Gateway Restore 不应用 Space 限制

- [ ] **Step 1: 扩展 Restore contract 并确认 RED**

新增断言：

```swift
require(
    restoreController.contains("guard space != nil else"),
    "Site-level restore without a Space must bypass Space Node capacity"
)
require(
    restoreController.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
    "Space Restore must clip the selected restore batch"
)
require(
    restoreAddSelected.contains(
        "recordPendingBatteryPowerSwitchRestoreLinkGroups(for: acceptedRestoreDatas)"
    ),
    "Restore side effects must only be recorded for accepted Node slots"
)
require(
    restoreCapacityCheck.contains("estimatedAddressCount = acceptedRestoreDatas.reduce"),
    "Restore address demand must only include accepted Node slots"
)
```

Run: `bash scripts/check_space_node_capacity.sh`

Expected: Restore contract 失败。

- [ ] **Step 2: 新增 Restore 容量裁剪 helper**

实现规则：

```swift
private func nodeCapacityAcceptedRestoreData(
    from restoreDatas: [DeviceRestoreData]
) -> [DeviceRestoreData] {
    guard space != nil else {
        return restoreDatas
    }
    let inFlightNodeCount = showDevices.filter {
        $0.addState.reservesNodeCapacity
    }.count
    let acceptedRestoreDatas = SpaceNodeCapacityPolicy.acceptedPrefix(
        restoreDatas,
        existingNodeCount: MeshNetworkManager.instance.realNodes.count,
        inFlightNodeCount: inFlightNodeCount
    )
    // 对未接受项取消选择、刷新 footer，并显示现有国际化上限提示。
    return acceptedRestoreDatas
}
```

取消选择时按 `unprovisionedDevice.peripheral.identifier` 区分，不能修改历史 Node 数据，也不能清理 Restore cache。

- [ ] **Step 3: 收敛 Restore 全选**

当 `space != nil` 时：

- 全选只选择剩余名额允许的前 N 个 `DeviceRestoreData`。
- 超出时显示 `devices_number_exceeds_message`。
- `space == nil` 的 Site Gateway Restore 保持全选全部可恢复 Gateway。
- 取消全选保持现状。

- [ ] **Step 4: 收敛最终 Restore 批次和副作用**

在 `addSelectedBtnClick()` 中先得到 `acceptedRestoreDatas`，然后仅对接受项执行：

- `recordPendingBatteryPowerSwitchRestoreLinkGroups`
- `checkDeviceAddressesAreSufficient`
- 后续 Battery/AC Restore configuration bookkeeping

在 `checkDeviceAddressesAreSufficient` 中再次调用 helper 作为最终防线，并确保状态切换、`estimatedAddressCount`、地址申请和 `addDevice` 循环全部使用 `acceptedRestoreDatas`。

若最终接受数量为 0：刷新 footer/列表后返回，不改变 Restore 自动重试计数，不进入地址申请，不进入 Provisioning。

- [ ] **Step 5: 运行 focused checks 并确认 GREEN**

Run: `bash scripts/check_space_node_capacity.sh`

Expected: 全部 policy 和 integration contract 通过。

- [ ] **Step 6: Task 5 检查点**

Run: `git diff --check`

Expected: exit 0。人工确认 `space == nil` Site Gateway Restore 未被 500 Space Node 限制误伤；不执行 commit。

---

### Task 6: 静态一致性、四品牌构建和验收交接

**Files:**

- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
- Modify: `scripts/check_space_node_capacity.sh`
- Verify only: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/**`
- Verify only: `SunSmart/en.lproj/Localizable.strings`
- Verify only: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**

- Verifies: App 只有一个活动 Node 上限根值 500
- Verifies: Switch 总上限仍为 16，Kinetic 不读取 Node 容量
- Verifies: SDK 没有为本需求发生代码改动
- Verifies: 四品牌 target 编译同一容量策略

- [ ] **Step 1: 完成 integration contract 的全链路断言**

最终 contract 至少覆盖：

- `SpaceData.maxDevicesCount` 来源为 `SpaceNodeCapacityPolicy.maxNodeCount`。
- 不存在活动的 `var maxDevicesCount: Int = 300`。
- `.wait/.addConnecting/.adding` 是唯一容量预留状态。
- Lights、Sensors、Others 使用总 `realNodes.count` 作为容量分子。
- Switches 仍显示 `/16`。
- `DevicesViewController.switchAdd()` 只检查 Switch 16，不检查 Node 上限。
- Classic、Professional、Restore 最终方法均使用 `acceptedPrefix`。
- 三条最终路径的 Element 地址计算都只使用接受后的批次。
- Restore 的 `space == nil` 路径绕过 Space 容量。
- `devices_number_exceeds_message` 在 English 和简体中文中均保留 `%d`。

- [ ] **Step 2: 运行完整 focused check**

Run: `bash scripts/check_space_node_capacity.sh`

Expected:

```text
SpaceNodeCapacityPolicyTests passed
SpaceNodeCapacityIntegrationContractTests passed
PASS: Space Node capacity policy and target membership.
```

- [ ] **Step 3: 检查没有残留活动 300 Node 根值**

Run:

```bash
rg -n -g '*.swift' 'maxDevicesCount|SpaceNodeCapacityPolicy|maxDeviceCount' SunSmart/Common/Data SunSmart/Main/Device SunSmart/Main/Group
```

Expected:

- 唯一业务上限根值是 `SpaceNodeCapacityPolicy.maxNodeCount = 500`。
- `SpaceData.maxDevicesCount` 只代理该值。
- 其他 `maxDeviceCount` 只作为兼容读取或局部 UI 使用，不包含 200/300 常量。

- [ ] **Step 4: 检查 Switch 16 没有变化**

Run:

```bash
rg -n 'switchs\.count < 16|switchs\.count >= 16|switchs\.count\)/16' SunSmart/Main SunSmart/Common/Data
```

Expected: Main、创建、编辑、Group、Space initialization 的现有 16 限制仍存在；本次 diff 不改变其数值。

- [ ] **Step 5: 确认 SDK 未修改且没有 300 Node 限制**

Run: `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short`

Expected: 无本任务产生的 SDK 改动。

Run:

```bash
rg -n -g '*.swift' '(maxNodes|maxDevices|nodeLimit|deviceLimit|\b300\b)' /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK
```

Expected: 只允许出现与 Node 容量无关的注释/速率值；不得存在 300 Node 业务限制。

- [ ] **Step 6: 四品牌 generic iPhoneOS Debug build**

按顺序直接运行：

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

Expected: 四个命令均以 `** BUILD SUCCEEDED **` 和 exit 0 结束。

- [ ] **Step 7: 最终静态检查**

Run: `git diff --check`

Expected: exit 0，无输出。

Run: `git status --short`

Expected: 只出现本计划明确列出的 App、测试、脚本、project 和 docs 文件；SDK 不在 App diff 中。

- [ ] **Step 8: 真实环境验收矩阵**

以下结果不得用 build 或 focused test 代替：

| 场景 | 期望 |
| --- | --- |
| 499 Node，Classic 添加 1 台 | Provision 成功后显示 500/500 |
| 499 Node，Classic/Professional 批量选择 2 台 | 仅稳定保留第 1 台；第 2 台取消选择并提示 500 上限 |
| 500 Node，Main Add Device | 阻止进入普通添加或在最终边界拒绝，不申请地址 |
| 500 Node，Group 指定添加 | 不得 Provision 第 501 台 |
| 500 Node，Space Restore | 不得恢复第 501 台，不记录被拒绝 Power Switch 的 Restore 副作用 |
| Site Gateway Restore，`space == nil` | 不受 Space 500 限制影响 |
| 500 Node、15 Switch，新增 Kinetic | 允许创建第 16 个 Switch，Proxy/虚拟 Group 正常 |
| 500 Node、少于 16 Switch，新增 Battery/AC | 物理 Node 添加被拒绝，不申请 8 个 Element 地址 |
| 499 Node、少于 16 Switch，新增 Battery/AC | 添加成功后为 500 Node，并占用 1 个 Switch 名额和 8 个连续 Unicast Address |
| 16 Switch、Node 未满 | 第 17 个 Kinetic/Battery/AC 均被 Switch 上限拒绝 |
| 地址不足但 Node 有余量 | 进入 `applyAddress`；成功后只继续接受批次 |
| 500 Node 数据导入/重启/切换 Main 分类 | Lights/Sensors/Others 均显示 500/500；Switches 显示实际 Switch 数/16 |
| 500 Node 云端同步 | Site/Space 上传、下载和再次加载保持全部 Node；无截断或 JSON 失败 |
| 500 Node 压力 | 记录 Main 首次加载、地址查询、RSSI/Heartbeat、Group/Scene/Timed、同步任务、CPU 和内存，与 300 Node 基线比较 |

- [ ] **Step 9: Task 6 检查点与交付边界**

输出实施总结，严格区分：

- 已通过的 focused tests、source contracts、`git diff --check` 和四品牌 build。
- 尚未完成或失败的真实 500 Node、BLE Mesh、服务器地址池、云端和硬件验收。
- 如果压测没有证明 SDK 问题，明确写“SDK 未修改”；不能把 App build 成功描述为 SDK/硬件 500 Node 已验收。
- 不执行 commit；等待用户明确授权后再处理 Git 提交。

---

## 执行顺序与检查点

确认执行后，按 `superpowers:executing-plans` 在当前会话 Inline Execution：

1. Task 1–2：建立单一真值、测试、四 target membership 和 Main 显示；汇报检查点。
2. Task 3–5：依次接入 Classic、Professional、Restore，每个流程保持 RED→GREEN；汇报检查点。
3. Task 6：完整 contract、四品牌 build、静态检查和真实环境验收交接；汇报最终结果。

任何 Task 发现现有工作区出现非本任务改动、服务端明确限制不足、或 Restore 的产品语义与本计划冲突时，停止扩大范围，保留已完成验证并向用户确认。
