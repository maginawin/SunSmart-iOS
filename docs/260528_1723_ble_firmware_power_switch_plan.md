# BLE Firmware Space Device Display Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. The local AGENTS.md preference is Inline Execution, so do not switch to subagent-driven execution unless explicitly requested.

**Goal:** 修复 `Site - Space - More - Firmware update via BLE` 中设备名称与 Space 展示名称不一致，以及已从 Space 删除/不应展示的设备仍可能出现在 BLE 固件升级列表的问题。

**Architecture:** BLE 固件升级仍以真实 `Node` 作为升级目标，不引入虚拟设备作为升级对象。Space 入口的 BLE 页面增加一个“Space 展示实体解析器”：负责把真实 node 映射到当前 Space 中用户看到的实体名称，并判断该 node 是否仍属于可见且支持 BLE 固件升级的设备集合。普通灯继续使用 `Node.name`；Power Switch 使用绑定的 `DeviceSwitchData/PJEightKeySwitchData.name`；Kinetic switch 不支持固件升级，必须排除；Dongle、Emergency Fire 等包装实体按各自 Space 列表模型名称展示。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `MeshNetworkManager`, `DeviceSwitchData`, `PJEightKeySwitchData`, `DeviceDongleData`, `DeviceEmerFireData`, `BleFirmwareUpdateViewController`.

---

## Root Cause

1. Space More 入口没有传当前 Space 的目标设备列表。
   - `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift:139` 调用 `BleFirmwareUpdateViewController(site: site, space: space)`。
   - `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:235-238` 在 `nodes == nil` 时默认使用 `MeshNetworkManager.instance.realNodes`。
   - 结果：BLE 页面缺少 Space 可见设备集合校验；只要真实 node 残留在 `realNodes`，就可能进入固件页。

2. BLE 页面按真实 `Node` 名称展示设备。
   - `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift:589-593` 使用 `device.name`，最多加 `device.group.name` 前缀。
   - Power Switch 在 Space 的 switch 页面使用 `DeviceSwitchData.name` 展示，例如 `PJEightKeySwitchesViewCell.configure(...)` 中的 `switchData.name`。
   - Others 中 Dongle 使用 `DeviceDongleData.name`，Emergency Fire 使用 `DeviceEmerFireData.name`。
   - 因此真实 node 名称仍可能是 `SW1`、`SW2` 或其它底层默认名，而用户期望看到 Space 中对应设备卡片上的名称。

3. 删除 Power Switch 后残留的风险存在。
   - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:872-886` 删除 switch 时只在 `switchData.proxyNode?.isBatteryPowerSwitch == true` 时 force remove 真实 node。
   - AC power switch 满足 `isACPowerSwitch`，但不满足 `isBatteryPowerSwitch`，因此当前删除路径下真实 AC node 有残留到 `realNodes` 的风险。
   - Battery power switch 正常走该路径时会被 `forceRemove`；但 BLE 页面没有二次按 `switchs` 过滤，遇到异常残留或旧数据仍可能展示。

4. Kinetic switch 不应进入 BLE 固件升级页。
   - `Node.DeviceType` 中 `"Switches"`、`"BatteryPowerSwitch"`、`"ACPowerSwitch"` 都会映射为 `.switches`。
   - Battery/AC power switch 可通过 `node.isPowerSwitch` 识别并按真实 node 升级。
   - Kinetic/EnOcean switch 不支持 BLE 固件升级；在 BLE 页应排除 `node.deviceType == .switches && !node.isPowerSwitch`。

## Scope

本次只处理 BLE 固件升级页的数据过滤、Space 展示名解析、Power Switch 删除残留。不要改固件升级流程、RSSI 扫描、Mesh OTA、固件包加载、权限体系、资源和 target 配置。

## Files

- Modify: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart.xcworkspace` / `SunSmart` scheme

## Task 1: Add Space Display Resolver For BLE Firmware Nodes

- [ ] 在 `BleFirmwareUpdateViewController` 所在文件新增一个小型 resolver，用于 Space 入口 BLE 页的 node 过滤和展示名解析。

实现要点：
- 保留 `space == nil` 且显式传入 `nodes` 的 Site gateway firmware update 行为。
- `space != nil` 时，基础列表仍可来自 `nodes ?? MeshNetworkManager.instance.realNodes`。
- resolver 需要返回两个能力：
  - `isVisibleFirmwareNode(_ node: Node) -> Bool`
  - `displayName(for node: Node, displayDeviceNamePrefix: Bool) -> String`
- 对普通灯类设备，继续使用 `Node.name`，并保留 `GroupName-DeviceName` 前缀逻辑。
- 对 Power Switch，只有当前 `MeshNetworkManager.instance.switchs` 中存在同一 `proxyNodeAddress`，且 `switchData.proxyNode?.isPowerSwitch == true` 时才保留；名称使用该 `switchData.name`。
- 对 Kinetic switch / EnOcean switch，排除 `node.deviceType == .switches && !node.isPowerSwitch`，因为它不支持 BLE 固件升级。
- 对 Dongle，只有当前 `MeshNetworkManager.instance.dongles` 中存在 `bindNodeAddress == node.primaryUnicastAddress` 时才保留；名称使用 `DeviceDongleData.name`。
- 对 Emergency Fire Controller，只有 `DeviceEmerFireStore.shared.devices(in: space)` 中存在 `bindNodeAddress == node.primaryUnicastAddress` 时才保留；名称使用 `DeviceEmerFireData.name`。
- 其它真实 node 类型暂按当前行为保留并使用 `Node.name`；后续如果新增包装实体，应扩展 resolver，而不是在 cell 中新增散落判断。
- 未绑定真实 node 的虚拟实体不进入 BLE 列表，因为它们没有可 BLE 直连升级的真实 node。

建议新增的私有结构：

```swift
private struct BLEFirmwareSpaceDeviceResolver {
    let space: SpaceData?

    func isVisibleFirmwareNode(_ node: Node) -> Bool {
        guard let space else {
            return true
        }
        if node.isPowerSwitch {
            return powerSwitchData(for: node) != nil
        }
        if node.deviceType == .switches {
            return false
        }
        if node.deviceType == .dongle {
            return dongleData(for: node) != nil
        }
        if node.deviceType == .emergencyController {
            return emergencyFireData(for: node, in: space) != nil
        }
        return true
    }

    func displayName(for node: Node, displayDeviceNamePrefix: Bool) -> String {
        if let switchData = powerSwitchData(for: node) {
            return switchData.name
        }
        if let dongleData = dongleData(for: node) {
            return dongleData.name
        }
        if let space,
           let emergencyData = emergencyFireData(for: node, in: space) {
            return emergencyData.name
        }
        var name = node.name ?? ""
        if let group = node.group, displayDeviceNamePrefix {
            name = "\(group.name)-\(name)"
        }
        return name
    }

    private func powerSwitchData(for node: Node) -> DeviceSwitchData? {
        MeshNetworkManager.instance.switchs.first {
            $0.proxyNodeAddress == node.primaryUnicastAddress &&
            $0.proxyNode?.isPowerSwitch == true
        }
    }

    private func dongleData(for node: Node) -> DeviceDongleData? {
        MeshNetworkManager.instance.dongles.first {
            $0.bindNodeAddress == node.primaryUnicastAddress
        }
    }

    private func emergencyFireData(for node: Node, in space: SpaceData) -> DeviceEmerFireData? {
        DeviceEmerFireStore.shared.devices(in: space).first {
            $0.bindNodeAddress == node.primaryUnicastAddress
        }
    }
}
```

然后将初始化中的 `self.nodes = nodes ?? MeshNetworkManager.instance.realNodes` 替换为：

```swift
private let displayResolver: BLEFirmwareSpaceDeviceResolver

self.displayResolver = BLEFirmwareSpaceDeviceResolver(space: space)
self.nodes = (nodes ?? MeshNetworkManager.instance.realNodes).filter {
    displayResolver.isVisibleFirmwareNode($0)
}
```

## Task 2: Use Resolver Display Name In BLE Device Cells

- [ ] 在 BLE 设备 cell 显示名逻辑中使用 resolver 给出的 Space 展示名。

实现要点：
- `BleFirmwareTypeUpdateViewCell` 增加 `displayNameProvider: ((Node, Bool) -> String)?`。
- `BleFirmwareUpdateViewController.collectionView(_:cellForItemAt:)` 设置 provider。
- `BleFirmwareUpdateDeviceCell` 不再自己直接写死 `device.name`，而是先调用 provider；provider 不存在时回退到旧逻辑。
- `device` 的 `didSet` 和 `displayDeviceNamePrefix.didSet` 必须使用同一套名称解析，避免 cell 复用后显示不一致。

不要改全局 `Node.name`，也不要在升级过程中修改 node 的真实名称；这里只修正 BLE 列表展示名。

## Task 3: Remove AC Power Switch Real Node On Delete

- [ ] 在 `MeshNetworkManager.deleteSwitch(switchData:)` 中把真实 node 删除条件从 battery-only 扩展为 all power switch。

当前风险点：
- `realBatteryPowerSwitchNode` 只匹配 `isBatteryPowerSwitch`，AC 删除后真实 node 可能还留在 mesh network。

目标行为：
- `switchData.proxyNode?.isPowerSwitch == true` 时，删除 switch cache 后也移除真实 proxy node。
- 可保留原 reset 调用，因为 `MeshAPI.resetNodeWithoutWaitingForStatus(address:)` 是按 node 地址执行 reset，不依赖 battery-only 语义。
- 方法名可保持不动以降低 diff，也可以聚焦重命名为 `realPowerSwitchNode` / `removeRealPowerSwitchNodeIfNeeded`。若重命名，控制在同一文件同一小段内。

## Task 4: Verify Behavior

- [ ] 代码编译验证：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：build succeeded。

- [ ] 手动验证矩阵：
  - 普通灯仍显示 `Node.name` 或 `GroupName-NodeName`，与 Space 灯列表一致。
  - Space 中有 1 个 Battery power switch，BLE firmware update 只显示 1 个。
  - Battery power switch 显示 Space switch 名称，不显示 `SW1`/`SW2`。
  - AC power switch 显示 Space switch 名称，不显示 `SW1`/`SW2`。
  - Kinetic switch / EnOcean switch 不显示。
  - Dongle 显示 Space Others 中的 `DeviceDongleData.name`。
  - Emergency Fire Controller 显示 Space Others 中的 `DeviceEmerFireData.name`。
  - 未绑定真实 node 的虚拟 switch data 不显示。
  - 已删除但真实 node 异常残留的 Power Switch / Dongle / Emergency Fire Controller 不显示。
  - 删除 Battery power switch 后重新进入 BLE firmware update，不显示已删除项。
  - 删除 AC power switch 后重新进入 BLE firmware update，不显示已删除项。
  - Site 级 gateway firmware update 仍只展示传入的 gateway nodes。

## Risk Notes

- 过滤逻辑只在 `space != nil` 时按 Space 展示实体校验，避免影响 Site gateway firmware update。
- 不从包装模型生成升级目标，只用包装模型校验和命名；升级对象仍是真实 `Node`，符合 BLE 点对点升级需要。
- 普通灯继续沿用 `realNodes + Node.name`，因为 Space 灯列表本身就是这个模型。
- 本次不清理历史数据库中的异常记录；如果已有脏数据同时包含包装实体和真实 node，页面会按当前 Space 展示实体列表展示，这是符合用户对 Space 的预期。

## Answer To Open Question

“之前从 Space 删除的 battery power switch 或 ac power switch 是否有可能出现在这里？”

结论：当前代码下有可能，尤其是 AC power switch。BLE 页面默认遍历 `realNodes`，而删除 switch 时只对 battery power switch 的真实 node 做 `forceRemove`；AC power switch 的真实 node 可能残留。Battery power switch 正常删除路径会移除真实 node，但页面没有按当前 `switchs` 做二次过滤，所以遇到异常残留或旧数据时仍可能显示。
