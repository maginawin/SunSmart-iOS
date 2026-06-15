# Space Lights All 色温广播修复开发方案

> 2026-06-15 修正：本计划中使用 `MeshAPI.setAllColorTemperatureState(temperature:)` 的 `.allNodes` 方案已被后续真机现象否定。原因见 `docs/260615_1717_space_lights_all_cct_broadcast_failure_analysis.md`。最终实现应使用 `LightCTLTemperatureSetUnacknowledged` 发到 `.subElementBroadcastGroupAddress`，以覆盖非 Primary Element 上的 Light CTL Temperature Server。

## 目标

将 `Site > Space > Main > Lights` 分类下长按 All 按钮弹窗的色温控制改为广播发送，使其与亮度 `MeshAPI.setAllLightnessState(lightness:)` 的发送逻辑一致，减少多设备色温变化的先后差异。

## 当前事实

- All 弹窗入口在 `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`。
- 亮度回调 `lightControl(_:levelValueChanged:ended:)` 已调用 `MeshAPI.setAllLightnessState(lightness:)`，SDK 内部发到 `.allNodes`。
- 色温回调 `lightControl(_:cctValueChanged:ended:)` 当前筛选 `devices.filter({ $0.effectiveSupportCct })` 后，对每个节点调用 `MeshAPI.setNodeColorTemperatureState(address: $0.primaryUnicastAddress, temperature: nodeTemperature)`，属于逐台单播。
- SDK 已有 `MeshAPI.setAllColorTemperatureState(temperature:ack:)`，内部发送 `LightCTLTemperatureSetUnacknowledged` 或 `LightCTLTemperatureSet` 到 `.allNodes`，可直接复用。

## 方案选择

采用窄修复：只修改 `DeviceLightsViewController.lightControl(_:cctValueChanged:ended:)` 的发送层。

不修改 SDK，不新增 API，不改 Group、Scene、Profile 或单灯控制页。色温广播使用当前 slider 给出的统一 `temperature`，与亮度广播一样发送一条全局控制命令。

## 行为设计

1. 保留 emergency manual-control guard。
2. 继续计算 `temperature = UInt16(cct)`。
3. 继续筛选 `cctNodes = devices.filter({ $0.effectiveSupportCct })`，用于本地 UI 状态更新。
4. 将 mesh 发送从循环内逐台单播移到循环外，调用 `MeshAPI.setAllColorTemperatureState(temperature: temperature)`。
5. 循环内只更新本地节点状态：`$0.temperature = $0.clampEffectiveCct(temperature)`。
6. 保持 `updateAllOnOffItemUI()` 和 `collectionView.reloadData()` 不变。

## CCT range 取舍

当前 All 弹窗的 CCT 范围来自所有支持 CCT 设备的 `effectiveCctRange` 并集。旧单播逻辑能对每台设备分别 `clampEffectiveCct` 后发送不同值；改成广播后只能发送一个统一值。

本次按用户预期优先保证广播一致性：发送 slider 的统一色温值。App 本地展示仍按每台设备的 range clamp，避免列表显示越界。若后续发现某些设备对越界广播处理不一致，再单独评估是否把 All 弹窗 CCT slider 范围改为所有 CCT 设备 range 的交集。

## 开发任务

### Task 1: 修改 All 色温发送路径

**文件：**

- 修改：`SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

**步骤：**

- [x] 在 `lightControl(_:cctValueChanged:ended:)` 中保留 guard、`temperature` 和 `cctNodes`。
- [x] 在循环前调用 `MeshAPI.setAllColorTemperatureState(temperature: temperature)`。
- [x] 删除循环内的 `MeshAPI.setNodeColorTemperatureState(address: $0.primaryUnicastAddress, temperature: nodeTemperature)`。
- [x] 循环内保留本地状态更新。
- [x] 清理旧注释中已过期的 `setAllColorTemperatureState` 示例，避免误导后续排查。

预期核心结构：

```swift
let temperature = UInt16(cct)
let cctNodes = devices.filter({ $0.effectiveSupportCct })
MeshAPI.setAllColorTemperatureState(temperature: temperature)
cctNodes.forEach({
    let nodeTemperature = $0.clampEffectiveCct(temperature)
    $0.temperature = nodeTemperature
})
```

### Task 2: 静态核查发送路径

**文件：**

- 核查：`SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- 核查：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift`

**步骤：**

- [x] 运行搜索，确认 `DeviceLightsViewController` 中 All 色温回调不再出现逐台 `setNodeColorTemperatureState(address: $0.primaryUnicastAddress...)`。
- [x] 确认该回调出现 `MeshAPI.setAllColorTemperatureState(temperature:)`。
- [x] 确认 SDK `setAllColorTemperatureState` 仍发到 `.allNodes`。

推荐命令：

```bash
rg -n "setNodeColorTemperatureState|setAllColorTemperatureState|cctValueChanged" SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
rg -n "setAllColorTemperatureState|address: \\.allNodes" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift
```

### Task 3: 验证

**步骤：**

- [x] 运行 `git diff --check`，确认没有空白问题。
- [x] 运行 iPhoneOS 构建：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

- [x] 构建已通过，未触发本地 Pods/DerivedData/签名环境排查。

## 验收标准

- All 弹窗亮度仍调用 `MeshAPI.setAllLightnessState(lightness:)`。
- All 弹窗色温改为调用 `MeshAPI.setAllColorTemperatureState(temperature:)`。
- 色温控制不再按 `primaryUnicastAddress` 逐台发送。
- 本地列表仍只更新支持 CCT 的灯，并按各自 `effectiveCctRange` clamp 展示值。
- `git diff --check` 通过。
- `SunSmart` iPhoneOS Debug 构建通过。
