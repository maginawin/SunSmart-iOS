# BLE OTA Batch 固件版本规则实施计划

> **执行要求：** 后续使用 `superpowers:executing-plans` 在当前会话内逐项执行并阶段性检查；不使用 subagents。

**目标：** 为 BLE OTA 增加支持 `x.y.z.b` 的方向性固件更新判定，保证两个 BLE OTA 入口、固件提示与下载状态一致，同时保持 Mesh OTA 和 WiFi 固件页面现有行为。

**架构：** 新增无 UIKit 依赖的 `FirmwareVersionUpdatePolicy`。`.bleBatchAware` 表达 BLE 的方向性规则，`.numeric` 完整保留旧比较。BLE controller、BLE cell 和 BLE 固件下载入口显式使用新策略；共享 `FirmwareVersionViewController` 默认仍使用 `.numeric`。

**技术栈：** Swift、Foundation、UIKit、Xcode project source membership、独立 `swiftc` 表驱动测试、iPhoneOS `xcodebuild`。

## 全局约束

- 只影响 BLE OTA，不修改 Mesh OTA 的版本判断。
- 只接受 `x.y.z` 与 `x.y.z.b`；前三段必须是无符号整数。
- 基础版本不同时只比较 `x.y.z`。
- 基础版本相同时，batch 只比较存在性和相等性，不比较大小。
- 同基础版本下：正式版设备不能更新到 batch；batch 可以更新到正式版；不同 batch 可以双向更新。
- 缺失或非法版本 fail-closed，不开放 OTA，也不计为已升级。
- 保持扫描发现、RSSI `>= -80 dBm`、权限、升级状态和 composition hash 条件不变。
- 不修改数据库、服务器 API、固件包格式、NordicSigMeshSDK 和用户可见文案。
- 新增源文件加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 只使用 iPhoneOS generic destination 构建，不使用 Simulator。

## 文件结构

- Create: `SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift`：解析和方向性判定。
- Create: `Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift`：纯 Swift 表驱动测试。
- Modify: `SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift`：按策略计算已升级设备。
- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`：设备 eligibility、计数及 BLE 下载入口。
- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`：服务器新版本标志及计数。
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`：注入策略并默认保留旧行为。
- Modify: `SunSmart.xcodeproj/project.pbxproj`：四个 target 的 source membership。

---

### Task 1：建立方向性版本策略及表驱动测试

**Files:**

- Create: `Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift`
- Create: `SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `FirmwareVersionUpdateEligibility.allowed | disallowed | invalid`
- Produces: `FirmwareVersionUpdatePolicy.numeric | bleBatchAware`
- Produces: `eligibility(currentVersion:targetVersion:)`

- [ ] **Step 1：先建立失败的表驱动测试**

测试使用 `@main`，逐项调用 `.bleBatchAware.eligibility`。完整入口与矩阵如下：

```swift
import Foundation

@main
struct FirmwareVersionUpdatePolicyTests {
    static func main() {
        let cases: [(String?, String?, FirmwareVersionUpdateEligibility)] = [
            ("1.2.3", "2.0.0", .allowed),
            ("1.2.3.8", "2.0.0.1", .allowed),
            ("1.2.3", "1.3.0", .allowed),
            ("1.2.3", "1.2.4", .allowed),
            ("2.0.0", "1.9.9.100", .disallowed),
            ("1.2.3", "1.2.3", .disallowed),
            ("1.2.3", "1.2.3.4", .disallowed),
            ("1.2.3.4", "1.2.3", .allowed),
            ("1.2.3.4", "1.2.3.4", .disallowed),
            ("1.2.3.4", "1.2.3.5", .allowed),
            ("1.2.3.10", "1.2.3.9", .allowed),
            ("1.2.3.9", "1.2.3.10", .allowed),
            (nil, "1.2.3", .invalid),
            ("1.2.3", nil, .invalid),
            ("", "1.2.3", .invalid),
            ("1.2", "1.2.3", .invalid),
            ("1.2.3.4.5", "1.2.3", .invalid),
            ("1.a.3", "1.2.3", .invalid),
            ("1.2.3.", "1.2.3", .invalid)
        ]
        for testCase in cases {
            let actual = FirmwareVersionUpdatePolicy.bleBatchAware.eligibility(
                currentVersion: testCase.0,
                targetVersion: testCase.1
            )
            precondition(actual == testCase.2)
        }
        precondition(FirmwareVersionUpdatePolicy.numeric.eligibility(
            currentVersion: "1.2.3", targetVersion: "1.2.4"
        ) == .allowed)
        precondition(FirmwareVersionUpdatePolicy.numeric.eligibility(
            currentVersion: "1.2.4", targetVersion: "1.2.3"
        ) == .disallowed)
        print("FirmwareVersionUpdatePolicyTests passed")
    }
}
```

- [x] **Step 2：确认测试先失败**

Run: `swiftc -parse-as-library Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift -o /tmp/firmware-version-policy-tests`

Expected: FAIL，找不到策略类型。

- [ ] **Step 3：实现最小策略**

完整最小实现为：

```swift
import Foundation

enum FirmwareVersionUpdateEligibility: Equatable {
    case allowed, disallowed, invalid
}

enum FirmwareVersionUpdatePolicy {
    case numeric
    case bleBatchAware

    func eligibility(
        currentVersion: String?,
        targetVersion: String?
    ) -> FirmwareVersionUpdateEligibility {
        guard let currentVersion, let targetVersion else {
            return .invalid
        }

        switch self {
        case .numeric:
            return targetVersion.compare(currentVersion, options: .numeric) == .orderedDescending
                ? .allowed
                : .disallowed
        case .bleBatchAware:
            guard let current = ParsedBLEFirmwareVersion(currentVersion),
                  let target = ParsedBLEFirmwareVersion(targetVersion) else {
                return .invalid
            }
            if current.base != target.base {
                return target.base.lexicographicallyPrecedes(current.base)
                    ? .disallowed
                    : .allowed
            }
            switch (current.batch, target.batch) {
            case (nil, nil), (nil, .some):
                return .disallowed
            case (.some, nil):
                return .allowed
            case let (.some(currentBatch), .some(targetBatch)):
                return currentBatch == targetBatch ? .disallowed : .allowed
            }
        }
    }
}

private struct ParsedBLEFirmwareVersion {
    let base: [UInt]
    let batch: String?

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 || components.count == 4 else {
            return nil
        }
        let base = components.prefix(3).compactMap(UInt.init)
        guard base.count == 3 else {
            return nil
        }
        if components.count == 4, components[3].isEmpty {
            return nil
        }
        self.base = base
        self.batch = components.count == 4 ? String(components[3]) : nil
    }
}
```

- [ ] **Step 4：确认测试通过**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift -o /tmp/firmware-version-policy-tests
/tmp/firmware-version-policy-tests
```

Expected: `FirmwareVersionUpdatePolicyTests passed`。

- [ ] **Step 5：加入四个 App target**

在 `SunSmart.xcodeproj/project.pbxproj` 的 Firmware/Model group 加入 file reference；为四个 target 各建一个 PBXBuildFile，并加入对应 Sources phase。

Run: `rg -n "FirmwareVersionUpdatePolicy.swift in Sources" SunSmart.xcodeproj/project.pbxproj`

Expected: 四条不同的 Sources build file 记录。

- [ ] **Step 6：提交**

```bash
git add SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add BLE firmware batch version policy"
```

---

### Task 2：统一 BLE 设备 eligibility 与已升级计数

**Files:**

- Modify: `SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift`
- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
- Test: `Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift`

**Interfaces:**

- Consumes: `.bleBatchAware.eligibility(currentVersion:targetVersion:)`
- Produces: `FirmwareUpdateTypeData.upgradedNodes(using:) -> [Node]`

- [ ] **Step 1：锁定 invalid 与 disallowed 的区别**

测试明确断言 nil 为 `.invalid`、相同有效版本为 `.disallowed`。集成代码只能统计 `.disallowed`，不能使用 `!= .allowed`。

- [ ] **Step 2：model 支持显式策略**

```swift
func upgradedNodes(using policy: FirmwareVersionUpdatePolicy) -> [Node] {
    guard let targetVersion else { return [] }
    return nodes.filter {
        policy.eligibility(
            currentVersion: $0.firmwareVersion,
            targetVersion: targetVersion
        ) == .disallowed
    }
}
```

现有 `upgradedNodes` computed property 调用 `.numeric`，保持非 BLE 调用兼容。

- [ ] **Step 3：替换 controller 的两个 eligibility 比较点**

扫描回调和 `setupData(loadServerData:)` 都使用：

```swift
let enableUpgrade = FirmwareVersionUpdatePolicy.bleBatchAware.eligibility(
    currentVersion: node.firmwareVersion,
    targetVersion: node.targetFirmwareData?.version
) == .allowed
```

后续 RSSI、selected state 和扫描完成逻辑原样保留。

- [ ] **Step 4：替换两个已升级计数点**

BLE cell 首次绑定和 `reloadNodeUI(node:)` 使用 `firmwareTypeData.upgradedNodes(using: .bleBatchAware).count`。

- [ ] **Step 5：替换 BLE cell 的服务器新版本标志**

```swift
FirmwareVersionUpdatePolicy.bleBatchAware.eligibility(
    currentVersion: targetVersion,
    targetVersion: serverVersion
) == .allowed
```

- [ ] **Step 6：验证并提交**

运行 Task 1 的表驱动测试和 `git diff --check`，预期测试通过且静态检查无输出。

```bash
git add SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift
git commit -m "feat: apply batch rules to BLE firmware eligibility"
```

---

### Task 3：为共享固件下载页注入 BLE-only 策略

**Files:**

- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- Verify unchanged: `SunSmart/Main/Firmware/Controller/MeshFirmwareListViewController.swift`
- Verify unchanged: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`

**Interfaces:**

- Consumes: `FirmwareVersionUpdatePolicy`
- Produces: `FirmwareVersionViewController.init(type:versionUpdatePolicy:)`

- [ ] **Step 1：给共享页面增加默认旧策略的构造参数**

```swift
private let versionUpdatePolicy: FirmwareVersionUpdatePolicy

init(
    type: FirmwareUpdateTypeData,
    versionUpdatePolicy: FirmwareVersionUpdatePolicy = .numeric
) {
    self.type = type
    self.versionUpdatePolicy = versionUpdatePolicy
    super.init(nibName: nil, bundle: nil)
}
```

默认 `.numeric`，因此 Mesh controller 与 WiFi 子类不需要修改。

- [ ] **Step 2：共享页面使用注入策略判断服务器版本**

```swift
let hasNewerVersion = displayedCurrentTargetVersion.map {
    versionUpdatePolicy.eligibility(
        currentVersion: $0,
        targetVersion: newFirmwareData.version
    ) == .allowed
} ?? true
```

没有本地缓存时仍允许首次下载，与当前行为一致。

- [ ] **Step 3：只在 BLE 调用点注入新策略**

```swift
let vc = FirmwareVersionViewController(
    type: firmwareTypeData,
    versionUpdatePolicy: .bleBatchAware
)
```

不得修改 Mesh 和 WiFi 的调用方式。

- [ ] **Step 4：核查作用域**

Run: `rg -n "versionUpdatePolicy: \.bleBatchAware|FirmwareVersionViewController\(" SunSmart/Main/Firmware --glob '*.swift'`

Expected: `.bleBatchAware` 只出现在 BLE 调用点和 BLE 专用判断；Mesh 与 WiFi 仍使用默认 initializer。

- [ ] **Step 5：测试、静态检查并提交**

运行 Task 1 的表驱动测试和 `git diff --check`。

```bash
git add SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift
git commit -m "feat: scope batch firmware downloads to BLE OTA"
```

---

### Task 4：完整回归与四 target 构建验证

**Files:**

- Verify: Tasks 1–3 修改的全部文件
- Update only if implementation evidence requires correction: `docs/260714_1013_ble_ota_batch_version_analysis.md`

**Interfaces:**

- Consumes: Tasks 1–3 的最终代码与测试。
- Produces: BLE-only 行为、四 target 构建证据和聚焦的提交集。

- [x] **Step 1：运行最终表驱动测试**

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift Tests/Firmware/FirmwareVersionUpdatePolicyTests.swift -o /tmp/firmware-version-policy-tests
/tmp/firmware-version-policy-tests
```

Expected: `FirmwareVersionUpdatePolicyTests passed`。

- [ ] **Step 2：确认 BLE 未遗漏旧比较点**

```bash
rg -n "compare\(.*options: \.numeric" SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift
```

Expected: BLE controller 和 BLE cell 不再直接使用 `.numeric` 判断 eligibility；model 不保留直接字符串比较。

- [ ] **Step 3：确认 Mesh 与 WiFi 未切换到 BLE 策略**

Run: `rg -n "bleBatchAware" SunSmart/Main/Firmware`

Expected: 只命中新策略、BLE controller、BLE cell 和 BLE 计数；不命中 Mesh controller、Mesh cell、Mesh 设备选择或 WiFi controller。

- [ ] **Step 4：构建 SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6：构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7：构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 8：检查变更范围与提交**

```bash
git diff --check
git status --short
git log -4 --oneline
```

Expected: 静态检查无输出；没有无关资源、本地化、依赖、SDK 或 Mesh OTA 改动；历史包含三个聚焦实现提交。

- [ ] **Step 9：手工验收**

分别从以下入口进入：

- `Site > Space > More > Firmware update via BLE`
- `Site > 右上角菜单 > Firmware update > Firmware update via BLE`

对同一基础版本验证：正式版到 batch 禁止、batch 到正式版允许、相同 batch 禁止、不同 batch 双向允许；再验证低 RSSI 仍不可选。进入目标固件页面，验证不同 batch 会提示并允许下载，正式版缓存不会提示同基础版本 batch。最后进入 Mesh OTA，确认显示、选择和下载行为与改动前一致。

## 执行检查点

- Checkpoint 1：Task 1 后审查解析规则、矩阵测试和四 target source membership。
- Checkpoint 2：Task 3 后审查所有 BLE 消费点以及 Mesh/WiFi 默认策略隔离。
- Checkpoint 3：Task 4 后汇总测试、四 target 构建与手工验收证据。
