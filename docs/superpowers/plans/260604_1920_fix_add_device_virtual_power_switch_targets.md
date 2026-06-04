# Fix Add Device Virtual Power Switch Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Add Device 的 `Add Device(s) to` 下拉菜单与 `Site - Space - Switches` 使用一致的 Battery/AC Power Switch 数据转换规则，使旧虚拟 Battery/AC Power Switch 也能展示为可选目标。

**Architecture:** 将“从 `DeviceSwitchData` 获取可用于 Add Device 下拉菜单的 8-key power switch 数据”的逻辑抽成 Add Device 共享 helper。Classic Mode 和 Professional Mode 都通过同一个 helper 获取 Battery/AC 虚拟目标，避免两个模式继续重复 `compactMap { $0 as? PJEightKeySwitchData }` 并漏掉旧数据。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 `PJEightKeySwitchRepository` metadata 转换逻辑、Xcode iOS device build。

---

## 文件结构

- 修改 `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
  - 添加 Add Device 专用的 `DeviceSwitchData` 转换 helper。
  - 添加 `Sequence where Element == DeviceSwitchData` 的 Battery/AC 虚拟目标过滤 helper。
  - 保留现有 `PJEightKeySwitchData.isUnboundVirtualPowerSwitchAddTarget` 语义。

- 修改 `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `unboundBatteryPowerSwitches` / `unboundACPowerSwitches` 改为调用共享 helper。

- 修改 `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - `unboundBatteryPowerSwitches` / `unboundACPowerSwitches` 改为调用共享 helper。

- 不修改 `DeviceSwitchData.batteryPowerSwitchData`
  - 该属性要求 `proxyNode?.isPowerSwitch == true`，不适合作为未绑定虚拟设备候选入口。

- 不修改 `DeviceSwitchesViewController`
  - Switches 页面的展示逻辑已经能通过 repository metadata 识别旧 8-key 数据，本次修复是让 Add Device 下拉菜单对齐它。

---

### Task 1: 添加 Add Device 共享转换与过滤 helper

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`

- [x] **Step 1: 在 `DeviceAddViewController.swift` 中扩展 `DeviceSwitchData`**

在 `extension PJEightKeySwitchData` 前添加：

```swift
extension DeviceSwitchData {
    var addDeviceEightKeySwitchTargetData: PJEightKeySwitchData? {
        if let eightKeySwitch = self as? PJEightKeySwitchData {
            return eightKeySwitch
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: self)
    }
}
```

- [x] **Step 2: 在同一文件中添加序列过滤 helper**

紧跟 `DeviceSwitchData` extension 后添加：

```swift
extension Sequence where Element == DeviceSwitchData {
    func unboundVirtualPowerSwitchAddTargets(kind: PJEightKeyPowerSwitchKind) -> [PJEightKeySwitchData] {
        compactMap { $0.addDeviceEightKeySwitchTargetData }
            .filter {
                $0.isUnboundVirtualPowerSwitchAddTarget &&
                    $0.powerSwitchKind == kind
            }
    }
}
```

- [x] **Step 3: 检查 helper 命名**

确认命名表达的是 Add Device 下拉候选语义，而不是通用绑定状态：

- `addDeviceEightKeySwitchTargetData`：只负责把当前 switch 转为 Add Device 可判断的 8-key 数据。
- `unboundVirtualPowerSwitchAddTargets(kind:)`：负责最终候选过滤。

---

### Task 2: Classic Mode 使用共享 helper

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [x] **Step 1: 替换 `unboundBatteryPowerSwitches`**

将当前实现：

```swift
private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .compactMap { $0 as? PJEightKeySwitchData }
        .filter { $0.isUnboundVirtualPowerSwitchAddTarget && $0.powerSwitchKind == .battery }
}
```

替换为：

```swift
private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .unboundVirtualPowerSwitchAddTargets(kind: .battery)
}
```

- [x] **Step 2: 替换 `unboundACPowerSwitches`**

将当前实现：

```swift
private var unboundACPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .compactMap { $0 as? PJEightKeySwitchData }
        .filter { $0.isUnboundVirtualPowerSwitchAddTarget && $0.powerSwitchKind == .ac }
}
```

替换为：

```swift
private var unboundACPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .unboundVirtualPowerSwitchAddTargets(kind: .ac)
}
```

- [x] **Step 3: 行为检查**

确认 Classic Mode 中以下逻辑不变：

- 选中虚拟 Battery/AC Power Switch 后仍锁定 `Switches` 分类；
- 选择其他分类仍提示 `You can't choose other devices.`;
- 虚拟目标时仍隐藏 Select all 相关控件和设备行左侧选择按钮；
- Group 目标导致不可选时仍保留 Select all 控件但禁用选择行为。

---

### Task 3: Professional Mode 使用共享 helper

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [x] **Step 1: 替换 `unboundBatteryPowerSwitches`**

将当前实现：

```swift
private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .compactMap { $0 as? PJEightKeySwitchData }
        .filter { $0.isUnboundVirtualPowerSwitchAddTarget && $0.powerSwitchKind == .battery }
}
```

替换为：

```swift
private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .unboundVirtualPowerSwitchAddTargets(kind: .battery)
}
```

- [x] **Step 2: 替换 `unboundACPowerSwitches`**

将当前实现：

```swift
private var unboundACPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .compactMap { $0 as? PJEightKeySwitchData }
        .filter { $0.isUnboundVirtualPowerSwitchAddTarget && $0.powerSwitchKind == .ac }
}
```

替换为：

```swift
private var unboundACPowerSwitches: [PJEightKeySwitchData] {
    MeshNetworkManager.instance.switchs
        .unboundVirtualPowerSwitchAddTargets(kind: .ac)
}
```

- [x] **Step 3: 行为检查**

确认 Professional Mode 的 Candidate Device List 中以下逻辑不变：

- Add Device(s) to 与 Classic Mode 使用相同 Battery/AC 虚拟目标列表；
- 选中虚拟 Battery/AC Power Switch 后仍限制为 `Switches` 分类；
- 选择其他分类仍提示 `You can't choose other devices.`;
- 虚拟目标时仍隐藏 Select all 相关控件和设备行左侧选择按钮。

---

### Task 4: 验证与提交

**Files:**
- Verify only: `SunSmart.xcworkspace`

- [x] **Step 1: 静态检查改动范围**

Run:

```bash
git diff -- SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- 只新增共享 helper；
- Classic 和 Professional 只替换 Battery/AC 虚拟目标列表的数据来源；
- 没有改动 LINK 页面不允许切换 Add Device(s) to 的逻辑；
- 没有改动设备匹配 `company id`、`product id`、panel 匹配逻辑。

- [x] **Step 2: iOS build 验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [x] **Step 3: 提交**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift docs/superpowers/plans/260604_1920_fix_add_device_virtual_power_switch_targets.md
git commit -m "fix: align add device virtual switch targets"
```

---

## 自检

- 覆盖 `docs/260604_1916_add_device_switch_source_analysis.md` 中的根因：Add Device 不再只依赖 runtime 类型为 `PJEightKeySwitchData` 的对象。
- 保持 Battery/AC 虚拟目标过滤条件：必须是 `displayStatus.isVirtualSwitch`，并且 `powerSwitchKind` 与分类一致。
- 不使用 `DeviceSwitchData.batteryPowerSwitchData`，避免未绑定虚拟目标继续被 `proxyNode?.isPowerSwitch == true` 排除。
- Classic Mode 与 Professional Mode 复用同一个 helper，避免后续再次出现两个入口规则不同。
- 不扩大到 Emergency Controller、Dongle、真实设备添加、LINK 页面锁定等已实现逻辑。
